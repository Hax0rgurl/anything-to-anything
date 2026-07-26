import Foundation
import PDFKit
import WebKit

actor DocumentConversionService {
    private var process: Process?

    func convert(
        _ request: ConversionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        progress(0.05)
        let source = request.sourceURL
        let output = request.outputURL
        let sourceExtension = source.pathExtension.lowercased()
        let target = request.outputFormat

        if sourceExtension == target.fileExtension {
            try FileManager.default.copyItem(at: source, to: output)
            progress(1)
            return
        }

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnythingToAnything-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }

        switch target {
        case .pdf:
            let html = try await htmlInput(from: source, in: temporaryFolder)
            progress(0.55)
            try await HTMLPDFRenderer.render(htmlURL: html, outputURL: output)

        case .html:
            if sourceExtension == "pdf" {
                let text = try extractPDFText(source)
                try Data(htmlDocument(fromPlainText: text).utf8).write(to: output, options: .withoutOverwriting)
            } else if ["md", "markdown"].contains(sourceExtension) {
                let markdown = try String(contentsOf: source, encoding: .utf8)
                try Data(htmlDocument(fromMarkdown: markdown).utf8).write(to: output, options: .withoutOverwriting)
            } else {
                try runTextutil(source: source, output: output, format: "html")
            }

        case .txt, .md:
            let text: String
            if sourceExtension == "pdf" {
                text = try extractPDFText(source)
            } else if ["md", "markdown", "txt", "text"].contains(sourceExtension) {
                text = try String(contentsOf: source, encoding: .utf8)
            } else {
                let intermediate = temporaryFolder.appendingPathComponent("document.txt")
                try runTextutil(source: source, output: intermediate, format: "txt")
                text = try String(contentsOf: intermediate, encoding: .utf8)
            }
            try Data(text.utf8).write(to: output, options: .withoutOverwriting)

        case .rtf, .doc, .docx, .odt:
            if sourceExtension == "pdf" || ["md", "markdown"].contains(sourceExtension) {
                let html = try await htmlInput(from: source, in: temporaryFolder)
                try runTextutil(source: html, output: output, format: target.fileExtension)
            } else {
                try runTextutil(source: source, output: output, format: target.fileExtension)
            }

        default:
            throw ConversionError.unsupportedRoute
        }

        guard FileManager.default.fileExists(atPath: output.path),
              (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
            throw ConversionError.conversionFailed("The document converter did not produce an output file.")
        }
        progress(1)
    }

    func cancel() {
        process?.terminate()
    }

    private func htmlInput(from source: URL, in temporaryFolder: URL) async throws -> URL {
        let output = temporaryFolder.appendingPathComponent("document.html")
        let ext = source.pathExtension.lowercased()
        if ["html", "htm"].contains(ext) {
            try FileManager.default.copyItem(at: source, to: output)
        } else if ext == "pdf" {
            let text = try extractPDFText(source)
            try Data(htmlDocument(fromPlainText: text).utf8).write(to: output, options: .withoutOverwriting)
        } else if ["md", "markdown"].contains(ext) {
            let markdown = try String(contentsOf: source, encoding: .utf8)
            try Data(htmlDocument(fromMarkdown: markdown).utf8).write(to: output, options: .withoutOverwriting)
        } else {
            try runTextutil(source: source, output: output, format: "html")
        }
        return output
    }

    private func runTextutil(source: URL, output: URL, format: String) throws {
        let task = Process()
        let errorPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        task.arguments = [
            "-convert", format,
            "-output", output.path,
            source.path
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errorPipe
        process = task
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            process = nil
            throw ConversionError.launchFailed(error.localizedDescription)
        }
        process = nil
        if task.terminationReason == .uncaughtSignal {
            throw ConversionError.cancelled
        }
        guard task.terminationStatus == 0 else {
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.conversionFailed(
                message.isEmpty ? "textutil exited with code \(task.terminationStatus)." : message
            )
        }
    }

    private func extractPDFText(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.conversionFailed("The PDF could not be opened.")
        }
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.conversionFailed(
                "This PDF has no extractable text. Scanned PDFs require OCR, which is not included."
            )
        }
        return text
    }

    private func htmlDocument(fromPlainText text: String) -> String {
        let body = escapeHTML(text)
            .replacingOccurrences(of: "\n\n", with: "</p><p>")
            .replacingOccurrences(of: "\n", with: "<br>")
        return htmlShell("<p>\(body)</p>")
    }

    private func htmlDocument(fromMarkdown markdown: String) -> String {
        var output: [String] = []
        var inList = false
        var inCode = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inList { output.append("</ul>"); inList = false }
                output.append(inCode ? "</code></pre>" : "<pre><code>")
                inCode.toggle()
            } else if inCode {
                output.append(escapeHTML(rawLine))
            } else if line.hasPrefix("#") {
                if inList { output.append("</ul>"); inList = false }
                let count = min(6, line.prefix(while: { $0 == "#" }).count)
                let title = line.dropFirst(count).trimmingCharacters(in: .whitespaces)
                output.append("<h\(count)>\(inlineMarkdown(String(title)))</h\(count)>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { output.append("<ul>"); inList = true }
                output.append("<li>\(inlineMarkdown(String(line.dropFirst(2))))</li>")
            } else {
                if inList { output.append("</ul>"); inList = false }
                if line.isEmpty {
                    output.append("<br>")
                } else {
                    output.append("<p>\(inlineMarkdown(line))</p>")
                }
            }
        }
        if inList { output.append("</ul>") }
        if inCode { output.append("</code></pre>") }
        return htmlShell(output.joined(separator: "\n"))
    }

    private func inlineMarkdown(_ value: String) -> String {
        var result = escapeHTML(value)
        let replacements = [
            (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
            (#"__(.+?)__"#, "<strong>$1</strong>"),
            (#"\*(.+?)\*"#, "<em>$1</em>"),
            (#"`(.+?)`"#, "<code>$1</code>")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private func htmlShell(_ body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
        @page { margin: 0.75in; }
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.5; color: #161616; }
        img { max-width: 100%; } pre { white-space: pre-wrap; background: #f4f4f4; padding: 12px; }
        </style></head><body>\(body)</body></html>
        """
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

@MainActor
private final class HTMLPDFRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var webView: WKWebView?
    private var outputURL: URL?

    static func render(htmlURL: URL, outputURL: URL) async throws {
        let renderer = HTMLPDFRenderer()
        try await renderer.render(htmlURL: htmlURL, outputURL: outputURL)
    }

    private func render(htmlURL: URL, outputURL: URL) async throws {
        self.outputURL = outputURL
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 816, height: 1056))
        self.webView = webView
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(
                htmlURL,
                allowingReadAccessTo: htmlURL.deletingLastPathComponent()
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKPDFConfiguration()
        webView.createPDF(configuration: configuration) { [weak self] result in
            guard let self else { return }
            do {
                let data = try result.get()
                guard let outputURL = self.outputURL else {
                    throw ConversionError.conversionFailed("The PDF destination was lost.")
                }
                try data.write(to: outputURL, options: .withoutOverwriting)
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}
