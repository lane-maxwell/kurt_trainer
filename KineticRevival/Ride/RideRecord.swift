import Foundation

struct RideSample: Codable, Equatable, Sendable {
    let timestamp: Date
    /// Riding time since the start, excluding pauses.
    let elapsed: TimeInterval
    let distance: Double
    let speedMetersPerSecond: Double
    let powerWatts: Int
    let cadenceRpm: Double?
    let latitude: Double
    let longitude: Double
    let elevation: Double
}

struct RideRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let routeName: String
    let startedAt: Date
    let samples: [RideSample]

    var duration: TimeInterval { samples.last?.elapsed ?? 0 }
    var distance: Double { samples.last?.distance ?? 0 }

    var averageSpeedMetersPerSecond: Double {
        duration > 0 ? distance / duration : 0
    }

    var averagePowerWatts: Int {
        guard !samples.isEmpty else { return 0 }
        return Int((Double(samples.map(\.powerWatts).reduce(0, +)) / Double(samples.count)).rounded())
    }

    var maximumPowerWatts: Int { samples.map(\.powerWatts).max() ?? 0 }

    var elevationGain: Double {
        zip(samples, samples.dropFirst()).reduce(0) { $0 + max($1.1.elevation - $1.0.elevation, 0) }
    }

    /// Mechanical work in kJ, which approximates kcal burned (human efficiency ~24% cancels 4.184 kJ/kcal).
    var workKilojoules: Double {
        zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            total + Double(pair.1.powerWatts) * (pair.1.elapsed - pair.0.elapsed) / 1000
        }
    }
}
