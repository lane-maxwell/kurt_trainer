import Foundation

/// Ride totals the trainer doesn't report itself, accumulated from Indoor Bike Data samples.
///
/// The T-6400's own elapsed-time field counts from power-on rather than from the start of a ride,
/// and it reports no distance, so both are derived here from speed over time.
struct RideMetrics: Sendable {
    /// Gaps longer than this (e.g. a dropped connection) are not integrated, to avoid inventing distance.
    static let maximumSampleGap: TimeInterval = 5

    private(set) var movingTime: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var maximumPowerWatts = 0
    private var powerSecondsSum: Double = 0
    private var lastSample: (date: Date, speedKph: Double, powerWatts: Int)?

    var averagePowerWatts: Int? {
        movingTime > 0 ? Int((powerSecondsSum / movingTime).rounded()) : nil
    }

    mutating func record(_ data: IndoorBikeData, at date: Date) {
        let speed = max(data.speedKph ?? 0, 0)
        let power = max(data.powerWatts ?? 0, 0)
        maximumPowerWatts = max(maximumPowerWatts, power)

        if let last = lastSample {
            let interval = date.timeIntervalSince(last.date)
            if interval > 0, interval <= Self.maximumSampleGap, speed > 0 || last.speedKph > 0 {
                let averageSpeedMetersPerSecond = (speed + last.speedKph) / 2 / 3.6
                distanceMeters += averageSpeedMetersPerSecond * interval
                movingTime += interval
                powerSecondsSum += Double(power + last.powerWatts) / 2 * interval
            }
        }
        lastSample = (date, speed, power)
    }

    /// Ends the current sample run so the next sample starts a new segment instead of bridging a gap.
    mutating func pause() {
        lastSample = nil
    }
}
