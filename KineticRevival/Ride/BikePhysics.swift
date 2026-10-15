import Foundation

/// Converts rider power into virtual road speed: the same idea Rouvy and Zwift use, so speed on a
/// climb reflects watts and weight rather than how fast the trainer's flywheel spins.
struct BikePhysics: Sendable {
    struct Parameters: Equatable, Sendable {
        var totalMassKg: Double
        var rollingResistanceCoefficient = 0.004
        /// Drag area for a rider on the hoods.
        var dragAreaSquareMeters = 0.32
        var airDensity = 1.225
        var drivetrainEfficiency = 0.97
    }

    static let gravity = 9.80665
    /// Propulsive force is P / v, which explodes from a standstill; below this speed it's capped.
    /// Kept low so weak efforts still crawl up steep grades: at 1 m/s the cap was 27 W → 26 N,
    /// less than gravity on a 7% grade, which left riders stuck at 0 mph forever.
    static let minimumPropulsionSpeed = 0.2
    /// Large steps overshoot when the low-speed force is high, so each step is split up.
    static let maximumSubstep: TimeInterval = 0.02

    let parameters: Parameters

    /// Advances speed by one time step under rider power and road grade (fraction, 0.05 = 5%).
    func nextSpeed(from speed: Double, powerWatts: Double, grade: Double, interval: TimeInterval) -> Double {
        guard interval > 0 else { return speed }
        let steps = Int((interval / Self.maximumSubstep).rounded(.up))
        let substep = interval / Double(steps)
        return (0..<steps).reduce(speed) { current, _ in
            step(from: current, powerWatts: powerWatts, grade: grade, interval: substep)
        }
    }

    private func step(from speed: Double, powerWatts: Double, grade: Double, interval: TimeInterval) -> Double {
        let p = parameters
        let angle = atan(grade)
        let propulsion = max(powerWatts, 0) * p.drivetrainEfficiency / max(speed, Self.minimumPropulsionSpeed)
        let gravity = p.totalMassKg * Self.gravity * sin(angle)
        let rolling = speed > 0 || propulsion > 0
            ? p.totalMassKg * Self.gravity * cos(angle) * p.rollingResistanceCoefficient
            : 0
        let drag = 0.5 * p.airDensity * p.dragAreaSquareMeters * speed * speed

        let acceleration = (propulsion - gravity - rolling - drag) / p.totalMassKg
        return max(speed + acceleration * interval, 0)
    }

    /// Power needed to hold `speed` steadily on `grade`; used to sanity-check the model.
    func steadyStatePower(speed: Double, grade: Double) -> Double {
        let p = parameters
        let angle = atan(grade)
        let resistance = p.totalMassKg * Self.gravity * (sin(angle) + cos(angle) * p.rollingResistanceCoefficient)
            + 0.5 * p.airDensity * p.dragAreaSquareMeters * speed * speed
        return resistance * speed / p.drivetrainEfficiency
    }
}
