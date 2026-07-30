import Foundation

actor ConversionService {
    private struct StreamInventory {
        let hasAudio: Bool
        let hasMotionVideo: Bool
    }

    private var process: Process?
    private let documentService = DocumentConversionService()

    func duration(of url: URL) async -> Double? {
        guard let ffprobe = try? FFmpegLocator.locate(.ffprobe) else { return nil }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = ffprobe
        task.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        let detectedKind = MediaKind.detect(from: request.sourceURL)
        if detectedKind == .document, request.outputFormat.kind == .document {
            try await documentService.convert(request, progress: progress)
            return
        }
        if detectedKind == .document || request.outputFormat.kind == .document {
            throw ConversionError.unsupportedRoute
        }

        let sourceInventory: StreamInventory?
        if detectedKind == .video || detectedKind == .audio {
            sourceInventory = try await streamInventory(in: request.sourceURL)
        } else {
            sourceInventory = nil
        }
        let effectiveSourceKind: MediaKind?
        if sourceInventory?.hasMotionVideo == true {
            effectiveSourceKind = .video
        } else if sourceInventory?.hasAudio == true {
            effectiveSourceKind = .audio
        } else {
            effectiveSourceKind = detectedKind
        }

        if request.outputFormat.kind == .audio,
           detectedKind != .image,
           let sourceInventory,
           !sourceInventory.hasAudio {
            throw ConversionError.missingAudioTrack
        }

        let routedRequest = ConversionRequest(
            sourceURL: request.sourceURL,
            outputURL: request.outputURL,
            outputFormat: request.outputFormat,
            speedMultiplier: request.speedMultiplier,
            sourceKindOverride: effectiveSourceKind
        )

        let ffmpeg = try FFmpegLocator.locate(.ffmpeg)
        let sourceDuration = await duration(of: request.sourceURL) ?? 0
        let expectedDuration = sourceDuration * request.expectedDurationScale
        let task = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        task.executableURL = ffmpeg
        task.arguments = try FFmpegCommandBuilder.arguments(for: routedRequest)
        task.standardOutput = progressPipe
        task.standardError = errorPipe
        process = task

        do {
            try task.run()
        } catch {
            process = nil
            throw ConversionError.launchFailed(error.localizedDescription)
        }

        let reader = Task.detached {
            let handle = progressPipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let range = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    let line = String(decoding: lineData, as: UTF8.self)
                    if line.hasPrefix("out_time_ms="), expectedDuration > 0,
                       let micros = Double(line.dropFirst("out_time_ms=".count)) {
                        progress(min(0.99, max(0, micros / 1_000_000 / expectedDuration)))
                    }
                }
            }
        }

        task.waitUntilExit()
        _ = await reader.result
        process = nil

        if task.terminationReason == .uncaughtSignal || task.terminationStatus == 255 {
            throw ConversionError.cancelled
        }
        guard task.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let log = String(decoding: data, as: UTF8.self)
            let useful = log.split(separator: "\n").suffix(8).joined(separator: "\n")
            throw ConversionError.conversionFailed(useful.isEmpty ? "FFmpeg exited with code \(task.terminationStatus)." : useful)
        }
        if request.outputFormat.kind == .audio || request.outputFormat.kind == .video {
            let outputInventory = try await streamInventory(in: request.outputURL)
            switch request.outputFormat.kind {
            case .audio:
                guard outputInventory.hasAudio, !outputInventory.hasMotionVideo else {
                    throw ConversionError.conversionFailed(
                        "The converted file did not contain a valid audio-only stream."
                    )
                }
            case .video:
                guard outputInventory.hasMotionVideo else {
                    throw ConversionError.conversionFailed(
                        "The converted file did not contain a playable video stream."
                    )
                }
                if effectiveSourceKind == .audio, !outputInventory.hasAudio {
                    throw ConversionError.conversionFailed(
                        "The visualizer video was created without the original audio."
                    )
                }
            case .image, .document:
                break
            }
        }
        progress(1)
    }

    func cancel() {
        process?.terminate()
        Task { await documentService.cancel() }
    }

    private func streamInventory(in url: URL) async throws -> StreamInventory {
        let ffprobe = try FFmpegLocator.locate(.ffprobe)
        let task = Process()
        let output = Pipe()
        task.executableURL = ffprobe
        task.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_type:stream_disposition=attached_pic",
            "-of", "json",
            url.path
        ]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                throw ConversionError.mediaInspectionFailed(url.lastPathComponent)
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = object["streams"] as? [[String: Any]]
            else {
                throw ConversionError.mediaInspectionFailed(url.lastPathComponent)
            }
            var hasAudio = false
            var hasMotionVideo = false
            for stream in streams {
                switch stream["codec_type"] as? String {
                case "audio":
                    hasAudio = true
                case "video":
                    let disposition = stream["disposition"] as? [String: Any]
                    let attachedPicture = disposition?["attached_pic"] as? Int ?? 0
                    if attachedPicture == 0 {
                        hasMotionVideo = true
                    }
                default:
                    continue
                }
            }
            return StreamInventory(hasAudio: hasAudio, hasMotionVideo: hasMotionVideo)
        } catch {
            if let conversionError = error as? ConversionError {
                throw conversionError
            }
            throw ConversionError.mediaInspectionFailed(url.lastPathComponent)
        }
    }
}
