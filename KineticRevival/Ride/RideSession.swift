import Foundation
import Observation
import os

/// One ride along a route: integrates virtual speed from trainer power, moves the rider along the
/// course, sends the road grade to the trainer, and records samples.
@MainActor
@Observable
final class RideSession {
    enum Phase: Equatable {
        case ready
        case riding
        case paused
        case finished
    }

    static let tickInterval: Duration = .milliseconds(100)
    /// How far ahead of the last physics tick `estimatedDistance(at:)` will project, so a stalled
    /// loop can't run the camera away down the road.
    static let maximumExtrapolation: TimeInterval = 0.3
    /// Fast-forward options for previews; a real trainer always runs in real time.
    static let playbackSpeeds: [Double] = [1, 2, 5, 10]
    static let sampleInterval: TimeInterval = 1

    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "Ride")

    let route: Route
    private(set) var phase: Phase = .ready
    private(set) var distance = 0.0
    private(set) var speedMetersPerSecond = 0.0
    private(set) var elapsed: TimeInterval = 0
    private(set) var powerWatts = 0
    private(set) var cadenceRpm: Double?
    /// The road's grade at the rider's position, in percent.
    private(set) var roadGradePercent = 0.0
    private(set) var position: RoutePosition
    private(set) var samples: [RideSample] = []
    private(set) var startedAt: Date?
    /// How many ride seconds pass per real second. Only previews can change it.
    private(set) var playbackSpeed: Double = 1

    @ObservationIgnored private let trainer: RideTrainer
    @ObservationIgnored private let physics: BikePhysics
    @ObservationIgnored private let difficulty: Double
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let advancesAutomatically: Bool
    @ObservationIgnored private var gradeSync = GradeSync()
    @ObservationIgnored private var gradeTask: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var nextSampleAt: TimeInterval = 0
    @ObservationIgnored private var lastAdvanceAt: Date?

    init(
        route: Route,
        trainer: RideTrainer,
        physics: BikePhysics.Parameters,
        difficulty: Double,
        advancesAutomatically: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.route = route
        self.trainer = trainer
        self.physics = BikePhysics(parameters: physics)
        self.difficulty = difficulty.clamped(to: 0...1)
        self.now = now
        self.advancesAutomatically = advancesAutomatically
        self.position = route.position(at: 0)
        self.roadGradePercent = route.grade(at: 0) * 100
    }

    var remainingDistance: Double { max(route.totalDistance - distance, 0) }

    /// True when a simulated rider is pedaling, so the ride can be fast-forwarded.
    var isPreview: Bool { trainer is SimulatedRider }

    func setPlaybackSpeed(_ speed: Double) {
        guard isPreview, Self.playbackSpeeds.contains(speed) else { return }
        playbackSpeed = speed
    }

    /// Where the rider is between physics ticks, for drawing at display frame rate.
    func estimatedDistance(at date: Date) -> Double {
        guard phase == .riding, let lastAdvanceAt else { return distance }
        let ahead = min(max(date.timeIntervalSince(lastAdvanceAt), 0), Self.maximumExtrapolation) * playbackSpeed
        return min(distance + speedMetersPerSecond * ahead, route.totalDistance)
    }
    var progress: Double { distance / route.totalDistance }

    /// The grade the trainer is asked to simulate, after the difficulty scaling.
    var trainerGradePercent: Double { roadGradePercent * difficulty }

    // MARK: Lifecycle

    func start() {
        guard phase == .ready else { return }
        startedAt = now()
        phase = .riding
        recordSample()
        syncGrade()
        startLoop()
        Self.logger.info("Started ride on \(self.route.name, privacy: .public)")
    }

    func pause() {
        guard phase == .riding else { return }
        phase = .paused
        speedMetersPerSecond = 0
        stopLoop()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .riding
        gradeSync.reset()
        syncGrade()
        startLoop()
    }

    func finish() async {
        guard phase == .riding || phase == .paused else { return }
        phase = .finished
        stopLoop()
        recordSample()
        gradeTask?.cancel()
        await trainer.releaseResistance()
        Self.logger.info("Finished ride: \(Int(self.distance)) m in \(Int(self.elapsed)) s")
    }

    /// Nil if the ride never started.
    func makeRecord() -> RideRecord? {
        guard let startedAt, samples.count >= 2 else { return nil }
        return RideRecord(id: UUID(), routeName: route.name, startedAt: startedAt, samples: samples)
    }

    // MARK: Simulation step

    /// One physics step. Driven by the ride loop; called directly by tests.
    func advance(by interval: TimeInterval) {
        guard phase == .riding, interval > 0 else { return }

        let data = trainer.latestData
        powerWatts = max(data?.powerWatts ?? 0, 0)
        cadenceRpm = data?.cadenceRpm

        let grade = route.grade(at: distance)
        speedMetersPerSecond = physics.nextSpeed(
            from: speedMetersPerSecond,
            powerWatts: Double(powerWatts),
            grade: grade,
            interval: interval
        )
        distance = min(distance + speedMetersPerSecond * interval, route.totalDistance)
        elapsed += interval
        lastAdvanceAt = now()
        roadGradePercent = route.grade(at: distance) * 100
        position = route.position(at: distance)

        if elapsed >= nextSampleAt { recordSample() }
        syncGrade()

        if distance >= route.totalDistance {
            Task { await finish() }
        }
    }

    // MARK: Private

    private func recordSample() {
        samples.append(RideSample(
            timestamp: now(),
            elapsed: elapsed,
            distance: distance,
            speedMetersPerSecond: speedMetersPerSecond,
            powerWatts: powerWatts,
            cadenceRpm: cadenceRpm,
            latitude: position.coordinate.latitude,
            longitude: position.coordinate.longitude,
            elevation: position.elevation
        ))
        nextSampleAt = elapsed + Self.sampleInterval
    }

    /// Skips while a previous grade is still in flight; the next tick picks up the latest value.
    private func syncGrade() {
        guard gradeTask == nil else { return }
        let grade = (trainerGradePercent * 10).rounded() / 10
        guard gradeSync.shouldSend(grade, at: elapsed) else { return }

        gradeTask = Task { [weak self, trainer] in
            await trainer.setSimulationGrade(grade)
            self?.gradeTask = nil
        }
    }

    private func startLoop() {
        guard advancesAutomatically else { return }
        loop = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                let current = clock.now
                let seconds = (current - last) / .seconds(1)
                last = current
                guard let self else { return }
                // A long stall (app suspended) shouldn't teleport the rider down the road.
                self.advance(by: min(seconds, 1) * self.playbackSpeed)
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }
}
