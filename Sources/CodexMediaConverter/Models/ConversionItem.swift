import Foundation

enum ConversionState: Equatable {
    case waiting
    case converting
    case finished(URL)
    case failed(String)

    var label: String {
        switch self {
        case .waiting: "Waiting"
        case .converting: "Converting"
        case .finished: "Done"
        case .failed: "Failed"
        }
    }
}

struct ConversionItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var progress: Double = 0
    var state: ConversionState = .waiting

    var sourceKind: MediaKind? { MediaKind.detect(from: sourceURL) }
}
