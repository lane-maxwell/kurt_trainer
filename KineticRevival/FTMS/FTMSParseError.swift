import Foundation

enum FTMSParseError: Error, Equatable, CustomStringConvertible {
    case truncated(characteristic: String, expectedAtLeast: Int, actual: Int)
    case unexpectedValue(characteristic: String, detail: String)

    var description: String {
        switch self {
        case let .truncated(characteristic, expected, actual):
            "\(characteristic) payload truncated: needed at least \(expected) bytes, got \(actual)"
        case let .unexpectedValue(characteristic, detail):
            "\(characteristic) payload invalid: \(detail)"
        }
    }
}
