import Foundation

/// A decoded Fitness Machine Status (0x2ADA) notification.
enum MachineStatus: Equatable, Sendable {
    case reset
    case stoppedOrPausedByUser
    case startedOrResumedByUser
    case targetResistanceChanged(level: Double)
    case targetPowerChanged(watts: Int)
    case controlPermissionLost
    case spinDown(SpinDownStatus)
    case other(opCode: UInt8)

    enum SpinDownStatus: UInt8, Equatable, Sendable {
        case requested = 0x01
        case success = 0x02
        case error = 0x03
        case stopPedaling = 0x04
    }

    init(data: Data) throws {
        var reader = ByteReader(data, characteristic: "Machine Status")
        let opCode = try reader.uint8()
        switch opCode {
        case 0x01:
            self = .reset
        case 0x02:
            self = .stoppedOrPausedByUser
        case 0x04:
            self = .startedOrResumedByUser
        case 0x07:
            // FTMS 1.0 specifies a uint8 here, but the T-6400 sends sint16 (`07 64 00` for 10.0).
            let raw = reader.remaining >= 2 ? Int(try reader.int16()) : Int(try reader.uint8())
            self = .targetResistanceChanged(level: Double(raw) / 10)
        case 0x08:
            self = .targetPowerChanged(watts: Int(try reader.int16()))
        case 0x14:
            let raw = try reader.uint8()
            guard let status = SpinDownStatus(rawValue: raw) else {
                throw FTMSParseError.unexpectedValue(
                    characteristic: "Machine Status",
                    detail: "unknown spin-down status 0x\(String(format: "%02x", raw))"
                )
            }
            self = .spinDown(status)
        case 0xFF:
            self = .controlPermissionLost
        default:
            self = .other(opCode: opCode)
        }
    }
}
