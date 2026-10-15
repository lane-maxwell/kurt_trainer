import Foundation

/// App-imposed bounds on what we ask the trainer to do.
///
/// The T-6400 reports implausible ranges (resistance −200…200, power −4000…4000 W), so the trainer's
/// own limits are only used to narrow these further, never to widen them.
struct SafetyLimits: Equatable, Sendable {
    static let defaultResistanceRange: ClosedRange<Double> = 0...100
    static let defaultPowerRange: ClosedRange<Int> = 50...400
    static let gradePercentRange: ClosedRange<Double> = -15...20

    let resistanceRange: ClosedRange<Double>
    let powerRange: ClosedRange<Int>

    init(
        reportedResistance: SupportedRange? = nil,
        reportedPower: SupportedRange? = nil
    ) {
        resistanceRange = Self.narrow(
            Self.defaultResistanceRange,
            by: reportedResistance.map { $0.minimum...$0.maximum }
        )
        powerRange = Self.narrow(
            Self.defaultPowerRange,
            by: reportedPower.map { Int($0.minimum.rounded(.up))...Int($0.maximum.rounded(.down)) }
        )
    }

    func clampResistance(_ level: Double) -> Double {
        let rounded = (level * 10).rounded() / 10
        return min(max(rounded, resistanceRange.lowerBound), resistanceRange.upperBound)
    }

    func clampPower(_ watts: Int) -> Int {
        min(max(watts, powerRange.lowerBound), powerRange.upperBound)
    }

    func clampGrade(_ percent: Double) -> Double {
        let rounded = (percent * 10).rounded() / 10
        return min(max(rounded, Self.gradePercentRange.lowerBound), Self.gradePercentRange.upperBound)
    }

    /// Fallback for trainers that refuse FTMS simulation: a linear grade → resistance-level map.
    /// The constants are a starting point, to be tuned against how the T-6400's brake actually feels.
    func resistance(forGradePercent percent: Double) -> Double {
        clampResistance(Self.flatRoadResistance + Self.resistancePerGradePercent * percent)
    }

    static let flatRoadResistance = 10.0
    static let resistancePerGradePercent = 3.0

    private static func narrow<T: Comparable>(_ base: ClosedRange<T>, by reported: ClosedRange<T>?) -> ClosedRange<T> {
        guard let reported, base.overlaps(reported) else { return base }
        return base.clamped(to: reported)
    }
}
