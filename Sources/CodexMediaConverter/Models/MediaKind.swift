import Foundation

enum MediaKind: String, CaseIterable, Codable {
    case video = "Video"
    case audio = "Audio"
    case image = "Photo"
    case document = "Document"

    var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc.richtext"
        }
    }

    static func detect(from url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        if documentExtensions.contains(ext) { return .document }
        return nil
    }

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpeg", "mpg", "mts", "m2ts", "3gp"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "ac3"
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif", "avif"
    ]
    private static let documentExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "html", "htm", "rtf",
        "doc", "docx", "odt", "wordml", "webarchive", "pdf"
    ]
}
