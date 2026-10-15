import Foundation

/// UserDefaults keys and defaults shared by `@AppStorage` views and ride setup.
enum RiderSettings {
    static let riderWeightKey = "riderWeightKg"
    static let bikeWeightKey = "bikeWeightKg"
    static let difficultyKey = "trainerDifficulty"

    static let defaultRiderWeight = 75.0
    static let defaultBikeWeight = 9.0
    /// Fraction of the real grade sent to the trainer. Zwift and Rouvy default to 50%, which keeps
    /// steep climbs rideable on a trainer without real gearing for them.
    static let defaultDifficulty = 0.5

    static let riderWeightRange = 30.0...200.0
    static let bikeWeightRange = 4.0...30.0

    static func physicsParameters(from defaults: UserDefaults = .standard) -> BikePhysics.Parameters {
        let rider = defaults.object(forKey: riderWeightKey) as? Double ?? defaultRiderWeight
        let bike = defaults.object(forKey: bikeWeightKey) as? Double ?? defaultBikeWeight
        return BikePhysics.Parameters(
            totalMassKg: rider.clamped(to: riderWeightRange) + bike.clamped(to: bikeWeightRange)
        )
    }

    static func difficulty(from defaults: UserDefaults = .standard) -> Double {
        (defaults.object(forKey: difficultyKey) as? Double ?? defaultDifficulty).clamped(to: 0...1)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
