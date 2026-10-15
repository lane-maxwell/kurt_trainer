import Foundation
import Testing
@testable import KineticRevival

struct RideMetricsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func ride(_ samples: [(second: Double, kph: Double, watts: Int)]) -> RideMetrics {
        var metrics = RideMetrics()
        for sample in samples {
            metrics.record(
                IndoorBikeData(speedKph: sample.kph, powerWatts: sample.watts),
                at: start.addingTimeInterval(sample.second)
            )
        }
        return metrics
    }

    @Test func integratesDistanceAndTimeAtSteadySpeed() {
        let metrics = ride((0...10).map { (Double($0), 36, 200) })

        #expect(metrics.movingTime == 10)
        #expect(abs(metrics.distanceMeters - 100) < 0.0001)
        #expect(metrics.averagePowerWatts == 200)
        #expect(metrics.maximumPowerWatts == 200)
    }

    @Test func ignoresTimeSpentStationary() {
        let metrics = ride([(0, 0, 0), (1, 0, 0), (2, 0, 0)])

        #expect(metrics.movingTime == 0)
        #expect(metrics.distanceMeters == 0)
        #expect(metrics.averagePowerWatts == nil)
    }

    @Test func doesNotBridgeGapsLongerThanTheLimit() {
        let metrics = ride([(0, 36, 100), (1, 36, 100), (30, 36, 100), (31, 36, 100)])

        #expect(metrics.movingTime == 2)
        #expect(abs(metrics.distanceMeters - 20) < 0.0001)
    }

    @Test func pauseStartsANewSegment() {
        var metrics = ride([(0, 36, 100), (1, 36, 100)])
        metrics.pause()
        metrics.record(IndoorBikeData(speedKph: 36, powerWatts: 100), at: start.addingTimeInterval(3))

        #expect(metrics.movingTime == 1)
    }

    @Test func treatsNegativeReadingsAsZero() {
        let metrics = ride([(0, -5, -20), (1, -5, -20)])

        #expect(metrics.distanceMeters == 0)
        #expect(metrics.maximumPowerWatts == 0)
    }
}
