import Foundation

/// Decides when to send a new grade to the trainer: often enough to feel the road, rarely enough
/// not to flood a serialized control point that takes a round trip per command.
struct GradeSync: Sendable {
    static let minimumChangePercent = 0.5
    static let minimumInterval: TimeInterval = 2
    /// Resend an unchanged grade periodically in case the trainer reset or dropped it.
    static let refreshInterval: TimeInterval = 15

    private(set) var lastSent: (gradePercent: Double, at: TimeInterval)?

    mutating func shouldSend(_ gradePercent: Double, at time: TimeInterval) -> Bool {
        guard let last = lastSent else {
            lastSent = (gradePercent, time)
            return true
        }
        let elapsed = time - last.at
        let changed = abs(gradePercent - last.gradePercent) >= Self.minimumChangePercent
        guard (changed && elapsed >= Self.minimumInterval) || elapsed >= Self.refreshInterval else {
            return false
        }
        lastSent = (gradePercent, time)
        return true
    }

    mutating func reset() {
        lastSent = nil
    }
}
