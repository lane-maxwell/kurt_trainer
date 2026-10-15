import Foundation

enum ControlPointOpCode: UInt8, Sendable, CustomStringConvertible {
    case requestControl = 0x00
    case reset = 0x01
    case setTargetResistanceLevel = 0x04
    case setTargetPower = 0x05
    case startOrResume = 0x07
    case stopOrPause = 0x08
    case setIndoorBikeSimulation = 0x11
    case spinDownControl = 0x13
    case responseCode = 0x80

    var description: String {
        switch self {
        case .requestControl: "Request Control"
        case .reset: "Reset"
        case .setTargetResistanceLevel: "Set Target Resistance"
        case .setTargetPower: "Set Target Power"
        case .startOrResume: "Start/Resume"
        case .stopOrPause: "Stop/Pause"
        case .setIndoorBikeSimulation: "Set Indoor Bike Simulation"
        case .spinDownControl: "Spin Down Control"
        case .responseCode: "Response"
        }
    }
}

/// Parameters for FTMS op code 0x11. The trainer derives resistance from these and the rider's speed.
struct SimulationParameters: Equatable, Sendable {
    var gradePercent: Double
    var windSpeedMetersPerSecond = 0.0
    /// Typical road tyre on smooth tarmac.
    var rollingResistanceCoefficient = 0.004
    /// 0.5 · air density · CdA for a rider on the hoods, in kg/m.
    var windResistanceCoefficient = 0.51
}

enum ControlPointCommand: Equatable, Sendable, CustomStringConvertible {
    case requestControl
    /// Resistance level in trainer units with 0.1 resolution. Encoded as sint16, which is what
    /// the Kinetic T-6400 was verified to accept (`04 64 00` → level 10.0).
    case setTargetResistance(level: Double)
    case setTargetPower(watts: Int)
    case setIndoorBikeSimulation(SimulationParameters)
    case startSpinDown

    var opCode: ControlPointOpCode {
        switch self {
        case .requestControl: .requestControl
        case .setTargetResistance: .setTargetResistanceLevel
        case .setTargetPower: .setTargetPower
        case .setIndoorBikeSimulation: .setIndoorBikeSimulation
        case .startSpinDown: .spinDownControl
        }
    }

    var encoded: Data {
        switch self {
        case .requestControl:
            Data([opCode.rawValue])
        case let .setTargetResistance(level):
            Data([opCode.rawValue]) + Self.littleEndian(Int16(clamping: Int((level * 10).rounded())))
        case let .setTargetPower(watts):
            Data([opCode.rawValue]) + Self.littleEndian(Int16(clamping: watts))
        case let .setIndoorBikeSimulation(parameters):
            Data([opCode.rawValue])
                + Self.littleEndian(Int16(clamping: Int((parameters.windSpeedMetersPerSecond * 1000).rounded())))
                + Self.littleEndian(Int16(clamping: Int((parameters.gradePercent * 100).rounded())))
                + Data([
                    UInt8(clamping: Int((parameters.rollingResistanceCoefficient * 10000).rounded())),
                    UInt8(clamping: Int((parameters.windResistanceCoefficient * 100).rounded())),
                ])
        case .startSpinDown:
            Data([opCode.rawValue, 0x01])
        }
    }

    var description: String {
        switch self {
        case .requestControl: "Request Control"
        case let .setTargetResistance(level): "Set Target Resistance \(level.formatted(.number.precision(.fractionLength(1))))"
        case let .setTargetPower(watts): "Set Target Power \(watts) W"
        case let .setIndoorBikeSimulation(parameters): "Simulate \(parameters.gradePercent.formatted(.number.precision(.fractionLength(1))))% grade"
        case .startSpinDown: "Start Spin Down"
        }
    }

    private static func littleEndian(_ value: Int16) -> Data {
        let bits = UInt16(bitPattern: value)
        return Data([UInt8(bits & 0xFF), UInt8(bits >> 8)])
    }
}

enum ControlPointResultCode: UInt8, Sendable, CustomStringConvertible {
    case success = 0x01
    case opCodeNotSupported = 0x02
    case invalidParameter = 0x03
    case operationFailed = 0x04
    case controlNotPermitted = 0x05

    var description: String {
        switch self {
        case .success: "success"
        case .opCodeNotSupported: "op code not supported"
        case .invalidParameter: "invalid parameter"
        case .operationFailed: "operation failed"
        case .controlNotPermitted: "control not permitted"
        }
    }
}

/// An indication on the control point answering a previous write: `80 <request op code> <result>`.
struct ControlPointResponse: Equatable, Sendable {
    let requestOpCode: UInt8
    let result: ControlPointResultCode
    /// Op-code-specific trailing bytes, e.g. target speeds for a spin-down.
    let parameters: Data

    init(requestOpCode: UInt8, result: ControlPointResultCode, parameters: Data = Data()) {
        self.requestOpCode = requestOpCode
        self.result = result
        self.parameters = parameters
    }

    init(data: Data) throws {
        var reader = ByteReader(data, characteristic: "Control Point")
        let responseCode = try reader.uint8()
        guard responseCode == ControlPointOpCode.responseCode.rawValue else {
            throw FTMSParseError.unexpectedValue(
                characteristic: "Control Point",
                detail: "expected response op code 0x80, got 0x\(String(format: "%02x", responseCode))"
            )
        }
        requestOpCode = try reader.uint8()
        let rawResult = try reader.uint8()
        guard let result = ControlPointResultCode(rawValue: rawResult) else {
            throw FTMSParseError.unexpectedValue(
                characteristic: "Control Point",
                detail: "unknown result code 0x\(String(format: "%02x", rawResult))"
            )
        }
        self.result = result
        parameters = Data(data.dropFirst(3))
    }
}

/// Speed window a spin-down needs, returned with the Start Spin Down acknowledgement.
struct SpinDownTarget: Equatable, Sendable {
    let lowKph: Double
    let highKph: Double

    init(lowKph: Double, highKph: Double) {
        self.lowKph = lowKph
        self.highKph = highKph
    }

    init(parameters: Data) throws {
        var reader = ByteReader(parameters, characteristic: "Spin Down response")
        lowKph = Double(try reader.uint16()) / 100
        highKph = Double(try reader.uint16()) / 100
    }
}
