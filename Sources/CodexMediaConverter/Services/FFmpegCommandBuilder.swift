import Foundation

struct ConversionRequest {
    let sourceURL: URL
    let outputURL: URL
    let outputFormat: OutputFormat
    let speedMultiplier: Double?

    init(sourceURL: URL, outputURL: URL, outputFormat: OutputFormat, speedMultiplier: Double? = nil) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        self.speedMultiplier = speedMultiplier
    }

    var expectedDurationScale: Double {
        guard let speedMultiplier else { return 1 }
        return 1 / speedMultiplier
    }
}

enum ConversionError: LocalizedError {
    case unsupportedInput(String)
    case speedUpRequiresVideo
    case invalidSpeed
    case missingFFmpeg(String)
    case launchFailed(String)
    case conversionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedInput(let ext): "Unsupported input type: .\(ext)"
        case .speedUpRequiresVideo: "Speed Up Tutorial accepts video files only."
        case .invalidSpeed: "Speed must be between 1.25× and 10×."
        case .missingFFmpeg(let tool): "\(tool) is not installed or bundled."
        case .launchFailed(let message): "Could not start conversion: \(message)"
        case .conversionFailed(let message): message
        case .cancelled: "Conversion cancelled."
        }
    }
}

enum FFmpegCommandBuilder {
    static func arguments(for request: ConversionRequest) throws -> [String] {
        guard let sourceKind = MediaKind.detect(from: request.sourceURL) else {
            throw ConversionError.unsupportedInput(request.sourceURL.pathExtension)
        }

        var args = ["-hide_banner", "-loglevel", "error", "-y"]

        if let speed = request.speedMultiplier {
            guard sourceKind == .video else { throw ConversionError.speedUpRequiresVideo }
            guard (1.25...10).contains(speed) else { throw ConversionError.invalidSpeed }
            let value = speed.formatted(.number.precision(.fractionLength(0...2)))
            args += ["-i", request.sourceURL.path]
            args += [
                "-vf", "setpts=PTS/\(value),scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-an",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "20",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                "-progress", "pipe:1",
                "-nostats",
                request.outputURL.path
            ]
            return args
        }

        if sourceKind == .image && request.outputFormat.kind == .video {
            args += ["-loop", "1", "-framerate", "30", "-i", request.sourceURL.path, "-t", "5"]
        } else if sourceKind == .image && request.outputFormat.kind == .audio {
            args += ["-i", request.sourceURL.path, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "5", "-map", "1:a:0"]
        } else {
            args += ["-i", request.sourceURL.path]
        }

        args += codecArguments(sourceKind: sourceKind, format: request.outputFormat)
        args += ["-progress", "pipe:1", "-nostats", request.outputURL.path]
        return args
    }

    private static func codecArguments(sourceKind: MediaKind, format: OutputFormat) -> [String] {
        switch format {
        case .mp4:
            if sourceKind == .audio { return waveformVideo(codec: ["-c:v", "libx264", "-pix_fmt", "yuv420p"], audio: ["-c:a", "aac", "-b:a", "192k"]) }
            return evenDimensions + ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .mov:
            if sourceKind == .audio { return waveformVideo(codec: ["-c:v", "libx264", "-pix_fmt", "yuv420p"], audio: ["-c:a", "aac", "-b:a", "192k"]) }
            return evenDimensions + ["-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        case .webm:
            if sourceKind == .audio { return waveformVideo(codec: ["-c:v", "libvpx-vp9", "-crf", "31", "-b:v", "0"], audio: ["-c:a", "libopus", "-b:a", "160k"]) }
            return evenDimensions + ["-c:v", "libvpx-vp9", "-crf", "31", "-b:v", "0", "-c:a", "libopus", "-b:a", "160k"]
        case .mkv:
            if sourceKind == .audio { return waveformVideo(codec: ["-c:v", "libx264", "-crf", "20"], audio: ["-c:a", "aac", "-b:a", "192k"]) }
            return evenDimensions + ["-c:v", "libx264", "-crf", "20", "-c:a", "aac", "-b:a", "192k"]
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: return ["-vn", "-c:a", "aac", "-b:a", "256k"]
        case .wav: return ["-vn", "-c:a", "pcm_s24le"]
        case .flac: return ["-vn", "-c:a", "flac"]
        case .ogg: return ["-vn", "-c:a", "libvorbis", "-q:a", "6"]
        case .opus: return ["-vn", "-c:a", "libopus", "-b:a", "160k"]
        case .jpg:
            return imageArguments(sourceKind: sourceKind, codec: ["-q:v", "2"])
        case .png:
            return imageArguments(sourceKind: sourceKind, codec: ["-compression_level", "6"])
        case .webp:
            return imageArguments(sourceKind: sourceKind, codec: ["-c:v", "libwebp", "-quality", "90"])
        case .tiff:
            return imageArguments(sourceKind: sourceKind, codec: ["-c:v", "tiff"])
        case .gif:
            if sourceKind == .video {
                return ["-vf", "fps=15,scale='min(1280,iw)':-2:flags=lanczos", "-loop", "0"]
            }
            if sourceKind == .audio {
                return ["-filter_complex", "[0:a]showwaves=s=1200x675:mode=line:rate=24:colors=0x7C5CFC[v]", "-map", "[v]", "-t", "10", "-loop", "0"]
            }
            return ["-frames:v", "1"]
        }
    }

    private static func waveformVideo(codec: [String], audio: [String]) -> [String] {
        ["-filter_complex", "[0:a]showwaves=s=1280x720:mode=line:rate=30:colors=0x7C5CFC[v]", "-map", "[v]", "-map", "0:a"] + codec + audio + ["-shortest"]
    }

    private static var evenDimensions: [String] {
        ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
    }

    private static func imageArguments(sourceKind: MediaKind, codec: [String]) -> [String] {
        if sourceKind == .audio {
            return ["-filter_complex", "[0:a]showwavespic=s=1600x900:colors=0x7C5CFC[v]", "-map", "[v]", "-frames:v", "1"] + codec
        }
        return ["-frames:v", "1"] + codec
    }
}
