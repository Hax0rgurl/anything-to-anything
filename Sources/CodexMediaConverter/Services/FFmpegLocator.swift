import Foundation

enum FFmpegLocator {
    enum Tool: String { case ffmpeg, ffprobe }

    static func locate(_ tool: Tool) throws -> URL {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(tool.rawValue))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates += [
            home.appendingPathComponent(".local/bin/\(tool.rawValue)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(tool.rawValue)"),
            URL(fileURLWithPath: "/usr/local/bin/\(tool.rawValue)"),
            URL(fileURLWithPath: "/usr/bin/\(tool.rawValue)")
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(tool.rawValue)
            }
        }

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }
        throw ConversionError.missingFFmpeg(tool.rawValue)
    }
}
