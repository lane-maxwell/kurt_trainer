import Foundation

/// The Fitness Machine Feature (0x2ACC) bitfields: what the trainer measures and what it can target.
struct MachineFeatures: Equatable, Sendable {
    struct Measurements: OptionSet, Sendable {
        let rawValue: UInt32
        static let cadence = Measurements(rawValue: 1 << 1)
        static let totalDistance = Measurements(rawValue: 1 << 2)
        static let resistanceLevel = Measurements(rawValue: 1 << 7)
        static let heartRate = Measurements(rawValue: 1 << 10)
        static let elapsedTime = Measurements(rawValue: 1 << 12)
        static let power = Measurements(rawValue: 1 << 14)
    }

    struct Targets: OptionSet, Sendable {
        let rawValue: UInt32
        static let resistance = Targets(rawValue: 1 << 2)
        static let power = Targets(rawValue: 1 << 3)
        static let indoorBikeSimulation = Targets(rawValue: 1 << 13)
        static let wheelCircumference = Targets(rawValue: 1 << 14)
        static let spinDown = Targets(rawValue: 1 << 15)
    }

    let measurements: Measurements
    let targets: Targets

    init(measurements: Measurements, targets: Targets) {
        self.measurements = measurements
        self.targets = targets
    }

    init(data: Data) throws {
        var reader = ByteReader(data, characteristic: "Machine Feature")
        measurements = Measurements(rawValue: try reader.uint32())
        targets = Targets(rawValue: try reader.uint32())
    }
}
