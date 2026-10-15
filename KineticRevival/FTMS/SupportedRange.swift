import Foundation

/// A Supported Resistance Level (0x2AD6) or Supported Power (0x2AD8) range: sint16 min, sint16 max, uint16 increment.
struct SupportedRange: Equatable, Sendable {
    let minimum: Double
    let maximum: Double
    let increment: Double

    init(minimum: Double, maximum: Double, increment: Double) {
        self.minimum = minimum
        self.maximum = maximum
        self.increment = increment
    }

    /// - Parameter scale: Multiplier applied to raw values (0.1 for resistance level, 1 for watts).
    init(data: Data, scale: Double, characteristic: String) throws {
        var reader = ByteReader(data, characteristic: characteristic)
        minimum = Double(try reader.int16()) * scale
        maximum = Double(try reader.int16()) * scale
        increment = Double(try reader.uint16()) * scale
        guard minimum <= maximum else {
            throw FTMSParseError.unexpectedValue(
                characteristic: characteristic,
                detail: "minimum \(minimum) exceeds maximum \(maximum)"
            )
        }
    }
}
