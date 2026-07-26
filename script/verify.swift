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
        guard CommandLine.arguments.count == 3 else {
            throw VerificationFailure.failed("Expected ffmpeg and ffprobe paths.")
        }
        let ffmpeg = URL(fileURLWithPath: CommandLine.arguments[1])
        let ffprobe = URL(fileURLWithPath: CommandLine.arguments[2])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnythingToAnythingVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try await verifyDocumentMatrix(in: root)
        try verifyMediaMatrix(in: root, ffmpeg: ffmpeg, ffprobe: ffprobe)
        print("Anything to Anything full verification passed")
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
