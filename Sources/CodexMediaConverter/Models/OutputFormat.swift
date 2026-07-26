import Foundation

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case mp4, mov, webm, mkv
    case mp3, m4a, wav, flac, ogg, opus
    case jpg, png, webp, tiff, gif
    case txt, md, html, rtf, doc, docx, odt, pdf

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var title: String { rawValue.uppercased() }

    var kind: MediaKind {
        switch self {
        case .mp4, .mov, .webm, .mkv: .video
        case .mp3, .m4a, .wav, .flac, .ogg, .opus: .audio
        case .jpg, .png, .webp, .tiff, .gif: .image
        case .txt, .md, .html, .rtf, .doc, .docx, .odt, .pdf: .document
        }
    }

    static func formats(for kind: MediaKind) -> [OutputFormat] {
        allCases.filter { $0.kind == kind }
    }

    var summary: String {
        switch self {
        case .mp4: "Most compatible video"
        case .mov: "Apple editing video"
        case .webm: "Compact web video"
        case .mkv: "Flexible video container"
        case .mp3: "Universal compressed audio"
        case .m4a: "High-quality Apple audio"
        case .wav: "Uncompressed audio"
        case .flac: "Lossless compressed audio"
        case .ogg: "Open compressed audio"
        case .opus: "Efficient speech and music"
        case .jpg: "Small universal photo"
        case .png: "Lossless photo"
        case .webp: "Compact web photo"
        case .tiff: "High-quality archival photo"
        case .gif: "Animated image from video"
        case .txt: "Plain text with formatting removed"
        case .md: "Markdown text; complex formatting is simplified"
        case .html: "Web document with portable styling"
        case .rtf: "Rich Text Format"
        case .doc: "Legacy Microsoft Word document"
        case .docx: "Modern Microsoft Word document"
        case .odt: "OpenDocument text"
        case .pdf: "Fixed-layout PDF"
        }
    }
}
