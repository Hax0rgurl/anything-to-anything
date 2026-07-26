import Foundation

actor ConversionService {
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
        let sourceKind = MediaKind.detect(from: request.sourceURL)
        if sourceKind == .document, request.outputFormat.kind == .document {
            try await documentService.convert(request, progress: progress)
            return
        }
        if sourceKind == .document || request.outputFormat.kind == .document {
            throw ConversionError.unsupportedRoute
        }

        let ffmpeg = try FFmpegLocator.locate(.ffmpeg)
        let sourceDuration = await duration(of: request.sourceURL) ?? 0
        let expectedDuration = sourceDuration * request.expectedDurationScale
        let task = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        task.executableURL = ffmpeg
        task.arguments = try FFmpegCommandBuilder.arguments(for: request)
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
        progress(1)
    }

    func cancel() {
        process?.terminate()
        Task { await documentService.cancel() }
    }
}
