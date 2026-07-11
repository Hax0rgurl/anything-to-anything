import Foundation

enum MediaKind: String, CaseIterable, Codable {
    case video = "Video"
    case audio = "Audio"
    case image = "Photo"

    var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        }
    }

    static func detect(from url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
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
}
