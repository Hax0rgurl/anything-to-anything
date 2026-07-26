import Foundation
import PDFKit

enum VerificationFailure: Error {
    case failed(String)
}

@main
enum VerifyDocumentConversion {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnythingToAnythingVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.txt")
        try Data("A heading\n\nA document conversion test.".utf8).write(to: source)
        let service = DocumentConversionService()

        let html = root.appendingPathComponent("output.html")
        try await service.convert(
            ConversionRequest(sourceURL: source, outputURL: html, outputFormat: .html),
            progress: { _ in }
        )
        let htmlText = try String(contentsOf: html, encoding: .utf8)
        try check(
            htmlText.localizedCaseInsensitiveContains("document conversion test"),
            "TXT to HTML lost the document text."
        )

        let docx = root.appendingPathComponent("output.docx")
        try await service.convert(
            ConversionRequest(sourceURL: html, outputURL: docx, outputFormat: .docx),
            progress: { _ in }
        )
        try check(
            (try docx.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0,
            "HTML to DOCX produced an empty file."
        )

        let pdf = root.appendingPathComponent("output.pdf")
        try await service.convert(
            ConversionRequest(sourceURL: html, outputURL: pdf, outputFormat: .pdf),
            progress: { _ in }
        )
        let pdfDocument = PDFDocument(url: pdf)
        try check((pdfDocument?.pageCount ?? 0) > 0, "HTML to PDF produced an unreadable PDF.")

        let extracted = root.appendingPathComponent("extracted.txt")
        try await service.convert(
            ConversionRequest(sourceURL: pdf, outputURL: extracted, outputFormat: .txt),
            progress: { _ in }
        )
        let extractedText = try String(contentsOf: extracted, encoding: .utf8)
        try check(
            extractedText.localizedCaseInsensitiveContains("document conversion test"),
            "PDF to TXT did not recover the expected text."
        )
        print("Anything to Anything document verification passed")
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw VerificationFailure.failed(message) }
    }
}
