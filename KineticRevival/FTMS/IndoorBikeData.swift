import Foundation

/// A decoded Indoor Bike Data (0x2AD2) notification. Fields are nil when the trainer omits them.
struct IndoorBikeData: Equatable, Sendable {
    var speedKph: Double?
    var averageSpeedKph: Double?
    var cadenceRpm: Double?
    var averageCadenceRpm: Double?
    var totalDistanceMeters: Int?
    var resistanceLevel: Int?
    var powerWatts: Int?
    var averagePowerWatts: Int?
    var heartRateBpm: Int?
    var elapsedTimeSeconds: Int?
    var remainingTimeSeconds: Int?

    private struct Flags: OptionSet {
        let rawValue: UInt16
        // Bit 0 is inverted: instantaneous speed is present when "more data" is CLEAR.
        static let moreData = Flags(rawValue: 1 << 0)
        static let averageSpeed = Flags(rawValue: 1 << 1)
        static let instantaneousCadence = Flags(rawValue: 1 << 2)
        static let averageCadence = Flags(rawValue: 1 << 3)
        static let totalDistance = Flags(rawValue: 1 << 4)
        static let resistanceLevel = Flags(rawValue: 1 << 5)
        static let instantaneousPower = Flags(rawValue: 1 << 6)
        static let averagePower = Flags(rawValue: 1 << 7)
        static let expendedEnergy = Flags(rawValue: 1 << 8)
        static let heartRate = Flags(rawValue: 1 << 9)
        static let metabolicEquivalent = Flags(rawValue: 1 << 10)
        static let elapsedTime = Flags(rawValue: 1 << 11)
        static let remainingTime = Flags(rawValue: 1 << 12)
    }

    init(
        speedKph: Double? = nil,
        averageSpeedKph: Double? = nil,
        cadenceRpm: Double? = nil,
        averageCadenceRpm: Double? = nil,
        totalDistanceMeters: Int? = nil,
        resistanceLevel: Int? = nil,
        powerWatts: Int? = nil,
        averagePowerWatts: Int? = nil,
        heartRateBpm: Int? = nil,
        elapsedTimeSeconds: Int? = nil,
        remainingTimeSeconds: Int? = nil
    ) {
        self.speedKph = speedKph
        self.averageSpeedKph = averageSpeedKph
        self.cadenceRpm = cadenceRpm
        self.averageCadenceRpm = averageCadenceRpm
        self.totalDistanceMeters = totalDistanceMeters
        self.resistanceLevel = resistanceLevel
        self.powerWatts = powerWatts
        self.averagePowerWatts = averagePowerWatts
        self.heartRateBpm = heartRateBpm
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.remainingTimeSeconds = remainingTimeSeconds
    }

    init(data: Data) throws {
        var reader = ByteReader(data, characteristic: "Indoor Bike Data")
        let flags = Flags(rawValue: try reader.uint16())

        if !flags.contains(.moreData) {
            speedKph = Double(try reader.uint16()) / 100
        }
        if flags.contains(.averageSpeed) {
            averageSpeedKph = Double(try reader.uint16()) / 100
        }
        if flags.contains(.instantaneousCadence) {
            cadenceRpm = Double(try reader.uint16()) / 2
        }
        if flags.contains(.averageCadence) {
            averageCadenceRpm = Double(try reader.uint16()) / 2
        }
        if flags.contains(.totalDistance) {
            totalDistanceMeters = Int(try reader.uint24())
        }
        if flags.contains(.resistanceLevel) {
            resistanceLevel = Int(try reader.int16())
        }
        if flags.contains(.instantaneousPower) {
            powerWatts = Int(try reader.int16())
        }
        if flags.contains(.averagePower) {
            averagePowerWatts = Int(try reader.int16())
        }
        if flags.contains(.expendedEnergy) {
            // Total energy (uint16), energy per hour (uint16), energy per minute (uint8).
            try reader.skip(5)
        }
        if flags.contains(.heartRate) {
            heartRateBpm = Int(try reader.uint8())
        }
        if flags.contains(.metabolicEquivalent) {
            try reader.skip(1)
        }
        if flags.contains(.elapsedTime) {
            elapsedTimeSeconds = Int(try reader.uint16())
        }
        if flags.contains(.remainingTime) {
            remainingTimeSeconds = Int(try reader.uint16())
        }
    }
}
