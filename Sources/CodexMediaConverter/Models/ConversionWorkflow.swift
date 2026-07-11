import Foundation

enum ConversionWorkflow: String, CaseIterable, Identifiable {
    case formatConversion = "Format Conversion"
    case speedUp = "Speed Up Tutorial"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .formatConversion: "arrow.triangle.2.circlepath"
        case .speedUp: "gauge.with.dots.needle.67percent"
        }
    }
}
