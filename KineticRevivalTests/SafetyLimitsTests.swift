import Testing
@testable import KineticRevival

struct SafetyLimitsTests {
    @Test func ignoresImplausiblyWideRangesFromT6400() {
        let limits = SafetyLimits(
            reportedResistance: SupportedRange(minimum: -200, maximum: 200, increment: 0.1),
            reportedPower: SupportedRange(minimum: -4000, maximum: 4000, increment: 1)
        )

        #expect(limits.resistanceRange == SafetyLimits.defaultResistanceRange)
        #expect(limits.powerRange == SafetyLimits.defaultPowerRange)
    }

    @Test func narrowsToStricterTrainerRanges() {
        let limits = SafetyLimits(
            reportedResistance: SupportedRange(minimum: 0, maximum: 40, increment: 1),
            reportedPower: SupportedRange(minimum: 100, maximum: 250, increment: 1)
        )

        #expect(limits.resistanceRange == 0...40)
        #expect(limits.powerRange == 100...250)
    }

    @Test func fallsBackToDefaultsWhenTrainerRangeDoesNotOverlap() {
        let limits = SafetyLimits(reportedResistance: SupportedRange(minimum: 500, maximum: 900, increment: 1))
        #expect(limits.resistanceRange == SafetyLimits.defaultResistanceRange)
    }

    @Test(arguments: [(-5.0, 0.0), (12.34, 12.3), (250.0, 100.0)])
    func clampsAndRoundsResistance(input: Double, expected: Double) {
        #expect(SafetyLimits().clampResistance(input) == expected)
    }

    @Test(arguments: [(0, 50), (175, 175), (2000, 400)])
    func clampsPower(input: Int, expected: Int) {
        #expect(SafetyLimits().clampPower(input) == expected)
    }
}
