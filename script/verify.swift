import Foundation
import PDFKit

enum VerificationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

@main
enum VerifyAnythingToAnything {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
            throw VerificationFailure.failed(
                "Expected ffmpeg and ffprobe paths, plus optional --media-only."
            )
        }
        let ffmpeg = URL(fileURLWithPath: CommandLine.arguments[1])
        let ffprobe = URL(fileURLWithPath: CommandLine.arguments[2])
        let mediaOnly = CommandLine.arguments.dropFirst(3).first == "--media-only"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnythingToAnythingVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        if !mediaOnly {
            try await verifyDocumentMatrix(in: root)
        }
        try verifyMediaMatrix(in: root, ffmpeg: ffmpeg, ffprobe: ffprobe)
        try await verifyMovieAudioRoutes(in: root, ffmpeg: ffmpeg, ffprobe: ffprobe)
        print(mediaOnly
            ? "Anything to Anything media verification passed"
            : "Anything to Anything full verification passed")
    }

    private static func verifyDocumentMatrix(in root: URL) async throws {
        let folder = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("source.txt")
        let phrase = "document conversion test"
        try Data("A heading\n\nA \(phrase).\n\nSecond paragraph.".utf8).write(to: source)
        let service = DocumentConversionService()
        let formats = OutputFormat.allCases.filter { $0.kind == .document }

        var fixtures: [OutputFormat: URL] = [:]
        for format in formats {
            let output = folder.appendingPathComponent("fixture.\(format.fileExtension)")
            try await service.convert(
                ConversionRequest(sourceURL: source, outputURL: output, outputFormat: format),
                progress: { _ in }
            )
            try validateDocument(output, format: format, phrase: phrase)
            fixtures[format] = output
        }

        var routeCount = 0
        for sourceFormat in formats {
            guard let input = fixtures[sourceFormat] else {
                throw VerificationFailure.failed("Missing \(sourceFormat.title) fixture.")
            }
            for targetFormat in formats {
                let output = folder.appendingPathComponent(
                    "\(sourceFormat.fileExtension)-to-\(targetFormat.fileExtension).\(targetFormat.fileExtension)"
                )
                try await service.convert(
                    ConversionRequest(sourceURL: input, outputURL: output, outputFormat: targetFormat),
                    progress: { _ in }
                )
                try validateDocument(output, format: targetFormat, phrase: phrase)
                routeCount += 1
            }
        }
        try check(routeCount == formats.count * formats.count, "The document route matrix was incomplete.")

        let markdown = folder.appendingPathComponent("structure.md")
        let markdownHTML = folder.appendingPathComponent("structure.html")
        try Data("# Title\n\n- one\n- two\n\n**bold**".utf8).write(to: markdown)
        try await service.convert(
            ConversionRequest(sourceURL: markdown, outputURL: markdownHTML, outputFormat: .html),
            progress: { _ in }
        )
        let html = try String(contentsOf: markdownHTML, encoding: .utf8)
        try check(html.contains("<h1>Title</h1>"), "Markdown heading was not preserved in HTML.")
        try check(html.contains("<li>one</li>"), "Markdown list was not preserved in HTML.")
        try check(html.contains("<strong>bold</strong>"), "Markdown bold text was not preserved in HTML.")

        print("Verified \(routeCount) document-to-document routes")
    }

    private static func validateDocument(
        _ url: URL,
        format: OutputFormat,
        phrase: String
    ) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try check(size > 0, "\(format.title) output is empty.")
        if format == .pdf {
            let document = PDFDocument(url: url)
            try check((document?.pageCount ?? 0) > 0, "PDF output is unreadable.")
            let text = (0..<(document?.pageCount ?? 0))
                .compactMap { document?.page(at: $0)?.string }
                .joined(separator: "\n")
            try check(
                text.localizedCaseInsensitiveContains(phrase),
                "PDF output lost the expected text."
            )
        } else if format == .txt || format == .md || format == .html {
            let text = try String(contentsOf: url, encoding: .utf8)
            try check(
                text.localizedCaseInsensitiveContains(phrase),
                "\(format.title) output lost the expected text."
            )
        }
    }

    private static func verifyMediaMatrix(
        in root: URL,
        ffmpeg: URL,
        ffprobe: URL
    ) throws {
        let folder = root.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("fixture.mp4")
        let audio = folder.appendingPathComponent("fixture.wav")
        let image = folder.appendingPathComponent("fixture.png")

        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=10",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-t", "0.8", "-shortest",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", video.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=523:sample_rate=48000",
            "-t", "0.8", audio.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=0x4757ff:s=160x90",
            "-frames:v", "1", image.path
        ])

        let sources: [(MediaKind, URL)] = [
            (.video, video),
            (.audio, audio),
            (.image, image)
        ]
        let formats = OutputFormat.allCases.filter { $0.kind != .document }
        var routeCount = 0
        for (sourceKind, sourceURL) in sources {
            try check(
                MediaKind.detect(from: sourceURL) == sourceKind,
                "Media kind detection failed for \(sourceURL.lastPathComponent)."
            )
            for format in formats {
                let output = folder.appendingPathComponent(
                    "\(sourceKind.rawValue.lowercased())-to-\(format.fileExtension).\(format.fileExtension)"
                )
                let request = ConversionRequest(
                    sourceURL: sourceURL,
                    outputURL: output,
                    outputFormat: format
                )
                let arguments = try FFmpegCommandBuilder.arguments(for: request)
                _ = try run(ffmpeg, arguments)
                let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try check(
                    size > 0,
                    "\(sourceKind.rawValue) to \(format.title) produced an empty file."
                )
                let streams = try run(ffprobe, [
                    "-v", "error",
                    "-show_entries", "stream=codec_type",
                    "-of", "csv=p=0",
                    output.path
                ])
                switch format.kind {
                case .video, .image:
                    try check(
                        streams.contains("video"),
                        "\(sourceKind.rawValue) to \(format.title) has no video/image stream."
                    )
                case .audio:
                    try check(
                        streams.contains("audio"),
                        "\(sourceKind.rawValue) to \(format.title) has no audio stream."
                    )
                case .document:
                    throw VerificationFailure.failed("Document format leaked into the media matrix.")
                }
                routeCount += 1
            }
        }

        let speedOutput = folder.appendingPathComponent("tutorial-2x.mp4")
        let speedArguments = try FFmpegCommandBuilder.arguments(for: ConversionRequest(
            sourceURL: video,
            outputURL: speedOutput,
            outputFormat: .mp4,
            speedMultiplier: 2
        ))
        _ = try run(ffmpeg, speedArguments)
        let speedStreams = try run(ffprobe, [
            "-v", "error",
            "-show_entries", "stream=codec_type",
            "-of", "csv=p=0",
            speedOutput.path
        ])
        try check(speedStreams.contains("video"), "Speed-up output has no video stream.")
        try check(!speedStreams.contains("audio"), "Speed-up output still contains audio.")
        try check(routeCount == sources.count * formats.count, "The media route matrix was incomplete.")
        print("Verified \(routeCount) media conversion routes plus speed-up audio removal")
    }

    private static func verifyMovieAudioRoutes(
        in root: URL,
        ffmpeg: URL,
        ffprobe: URL
    ) async throws {
        let folder = root.appendingPathComponent("MovieAudioRoutes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent("movie-with-audio.mov")
        let quietAudio = folder.appendingPathComponent("quiet-audio.m4a")
        let silentAudio = folder.appendingPathComponent("silent-audio.m4a")
        let videoOnly = folder.appendingPathComponent("video-without-audio.mov")
        let audioOnlyMP4 = folder.appendingPathComponent("audio-inside-mp4.mp4")

        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=6.4",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=6.4",
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-ac", "2",
            "-shortest", movie.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=523:sample_rate=48000:duration=6.4",
            "-af", "volume=0.001",
            "-c:a", "aac", "-b:a", "192k", "-ac", "2",
            quietAudio.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-t", "6.4",
            "-c:a", "aac", "-b:a", "192k",
            silentAudio.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            videoOnly.path
        ])
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=659:sample_rate=48000:duration=2.4",
            "-vn", "-c:a", "aac", "-ac", "2",
            "-f", "mp4", audioOnlyMP4.path
        ])

        let service = ConversionService()
        let movieDuration = try probe(movie, with: ffprobe).duration
        for format in OutputFormat.formats(for: .audio) {
            let output = folder.appendingPathComponent("movie-to-\(format.fileExtension).\(format.fileExtension)")
            try await service.convert(
                ConversionRequest(
                    sourceURL: movie,
                    outputURL: output,
                    outputFormat: format
                ),
                progress: { _ in }
            )
            let result = try probe(output, with: ffprobe)
            try check(result.audioStreamCount == 1, "MOV to \(format.title) lost its audio.")
            try check(result.videoStreamCount == 0, "MOV to \(format.title) retained a video stream.")
            try check(
                abs(result.duration - movieDuration) <= 0.2,
                "MOV to \(format.title) changed duration by more than 0.2 seconds."
            )
        }

        let quietDuration = try probe(quietAudio, with: ffprobe).duration
        var quietMP4: URL?
        for format in OutputFormat.formats(for: .video) {
            let output = folder.appendingPathComponent("quiet-audio-to-\(format.fileExtension).\(format.fileExtension)")
            try await service.convert(
                ConversionRequest(
                    sourceURL: quietAudio,
                    outputURL: output,
                    outputFormat: format
                ),
                progress: { _ in }
            )
            let result = try probe(output, with: ffprobe)
            try check(result.videoStreamCount == 1, "Audio to \(format.title) has no video.")
            try check(result.audioStreamCount == 1, "Audio to \(format.title) lost the original audio.")
            try check(
                result.width == 1_280 && result.height == 720,
                "Audio to \(format.title) is not 1280×720."
            )
            try check(
                abs(result.duration - quietDuration) <= 0.2,
                "Audio to \(format.title) changed duration by more than 0.2 seconds."
            )
            let maximumLuma = try visibleFrameMaximumLuma(
                output,
                at: 2,
                ffmpeg: ffmpeg
            )
            try check(
                maximumLuma > 40,
                "Audio to \(format.title) still renders as a black screen."
            )
            if format == .mp4 {
                quietMP4 = output
            }
        }

        let silentVideo = folder.appendingPathComponent("silent-reference.mp4")
        try await service.convert(
            ConversionRequest(
                sourceURL: silentAudio,
                outputURL: silentVideo,
                outputFormat: .mp4
            ),
            progress: { _ in }
        )
        guard let quietMP4 else {
            throw VerificationFailure.failed("Quiet MP4 visualizer fixture was not created.")
        }
        let quietFrame = try decodedGrayFrame(
            quietMP4,
            at: 2,
            name: "quiet",
            folder: folder,
            ffmpeg: ffmpeg
        )
        let silentFrame = try decodedGrayFrame(
            silentVideo,
            at: 2,
            name: "silent",
            folder: folder,
            ffmpeg: ffmpeg
        )
        try check(
            quietFrame.count == silentFrame.count && !quietFrame.isEmpty,
            "Visualizer comparison frames were incomplete."
        )
        let audioDependentPixelCount = zip(quietFrame, silentFrame).reduce(into: 0) {
            if abs(Int($1.0) - Int($1.1)) > 8 {
                $0 += 1
            }
        }
        try check(
            audioDependentPixelCount > 5_000,
            "Quiet audio did not draw an audio-dependent waveform above the static grid."
        )

        let reclassifiedOutput = folder.appendingPathComponent("audio-only-mp4-visualizer.mp4")
        try await service.convert(
            ConversionRequest(
                sourceURL: audioOnlyMP4,
                outputURL: reclassifiedOutput,
                outputFormat: .mp4
            ),
            progress: { _ in }
        )
        let reclassified = try probe(reclassifiedOutput, with: ffprobe)
        try check(
            reclassified.videoStreamCount == 1 && reclassified.audioStreamCount == 1,
            "Audio-only MP4 was not reclassified into an audio visualizer movie."
        )

        let impossibleOutput = folder.appendingPathComponent("video-only.mp3")
        do {
            try await service.convert(
                ConversionRequest(
                    sourceURL: videoOnly,
                    outputURL: impossibleOutput,
                    outputFormat: .mp3
                ),
                progress: { _ in }
            )
            throw VerificationFailure.failed("Video without audio incorrectly reported success.")
        } catch ConversionError.missingAudioTrack {
            try check(
                !FileManager.default.fileExists(atPath: impossibleOutput.path),
                "Missing-audio preflight left an invalid output behind."
            )
        }

        print("Verified MOV audio extraction, visible quiet-audio movies, and stream-aware routing")
    }

    private struct MediaProbe {
        let audioStreamCount: Int
        let videoStreamCount: Int
        let width: Int
        let height: Int
        let duration: Double
    }

    private static func probe(_ url: URL, with ffprobe: URL) throws -> MediaProbe {
        let raw = try run(ffprobe, [
            "-v", "error",
            "-show_entries", "stream=codec_type,width,height:format=duration",
            "-of", "json",
            url.path
        ])
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = object["streams"] as? [[String: Any]],
              let format = object["format"] as? [String: Any],
              let durationText = format["duration"] as? String,
              let duration = Double(durationText)
        else {
            throw VerificationFailure.failed("FFprobe returned invalid JSON for \(url.lastPathComponent).")
        }
        let videoStreams = streams.filter { $0["codec_type"] as? String == "video" }
        return MediaProbe(
            audioStreamCount: streams.filter { $0["codec_type"] as? String == "audio" }.count,
            videoStreamCount: videoStreams.count,
            width: videoStreams.first?["width"] as? Int ?? 0,
            height: videoStreams.first?["height"] as? Int ?? 0,
            duration: duration
        )
    }

    private static func visibleFrameMaximumLuma(
        _ url: URL,
        at seconds: Double,
        ffmpeg: URL
    ) throws -> Double {
        let metadata = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(seconds),
            "-i", url.path,
            "-frames:v", "1",
            "-vf", "signalstats,metadata=print:file=-",
            "-f", "null", "-"
        ])
        guard let line = metadata.split(separator: "\n").first(where: {
            $0.hasPrefix("lavfi.signalstats.YMAX=")
        }), let value = Double(line.split(separator: "=").last ?? "") else {
            throw VerificationFailure.failed(
                "Could not measure visualizer luma for \(url.lastPathComponent)."
            )
        }
        return value
    }

    private static func decodedGrayFrame(
        _ url: URL,
        at seconds: Double,
        name: String,
        folder: URL,
        ffmpeg: URL
    ) throws -> Data {
        let output = folder.appendingPathComponent("\(name)-frame.gray")
        _ = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-ss", String(seconds),
            "-i", url.path,
            "-frames:v", "1",
            "-pix_fmt", "gray",
            "-f", "rawvideo",
            output.path
        ])
        return try Data(contentsOf: output)
    }

    @discardableResult
    private static func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let task = Process()
        let output = Pipe()
        let error = Pipe()
        task.executableURL = executable
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = error
        try task.run()
        task.waitUntilExit()
        let stdout = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let stderr = String(
            decoding: error.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard task.terminationStatus == 0 else {
            let useful = stderr.split(separator: "\n").suffix(12).joined(separator: "\n")
            throw VerificationFailure.failed(
                "\(executable.lastPathComponent) failed with code \(task.terminationStatus):\n\(useful)"
            )
        }
        return stdout
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw VerificationFailure.failed(message) }
    }
}
