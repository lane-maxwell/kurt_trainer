import Foundation
import Testing
@testable import KineticRevival

struct BikePhysicsTests {
    private let physics = BikePhysics(parameters: .init(totalMassKg: 84))

    private func settle(power: Double, grade: Double, from speed: Double = 0) -> Double {
        (0..<4000).reduce(speed) { current, _ in
            physics.nextSpeed(from: current, powerWatts: power, grade: grade, interval: 0.25)
        }
    }

    @Test func reachesRealisticFlatSpeedAt200Watts() {
        let speed = settle(power: 200, grade: 0)

        #expect((30...38).contains(speed * 3.6))
        #expect(abs(physics.steadyStatePower(speed: speed, grade: 0) - 200) < 1)
    }

    @Test func climbsSlowerThanItRidesFlat() {
        let flat = settle(power: 250, grade: 0)
        let climb = settle(power: 250, grade: 0.08)

        #expect(climb < flat / 2)
        #expect((8...16).contains(climb * 3.6))
    }

    @Test func coastsFasterDownhill() {
        #expect(settle(power: 0, grade: -0.06) * 3.6 > 50)
    }

    @Test func slowsToAStopWithoutPower() {
        #expect(settle(power: 0, grade: 0, from: 10) < 0.5)
    }

    @Test func neverRollsBackwards() {
        #expect(physics.nextSpeed(from: 0.1, powerWatts: 0, grade: 0.2, interval: 1) == 0)
    }

    /// Regression: 27 W on Grant's Trail's (bogus) 7.2% bridge ramp used to pin speed at 0 forever.
    @Test(arguments: [(27.0, 0.072), (60.0, 0.072), (150.0, 0.19)])
    func weakEffortsStillCrawlUpSteepGrades(power: Double, grade: Double) {
        let speed = settle(power: power, grade: grade)

        #expect(speed > 0.2)
        #expect(abs(physics.steadyStatePower(speed: speed, grade: grade) - power) < 1)
    }

    @Test func largeStepsMatchSmallSteps() {
        let coarse = physics.nextSpeed(from: 0, powerWatts: 300, grade: 0, interval: 1)
        let fine = (0..<100).reduce(0.0) { s, _ in physics.nextSpeed(from: s, powerWatts: 300, grade: 0, interval: 0.01) }

        #expect(abs(coarse - fine) < 0.05)
    }

    @Test func heavierRiderClimbsSlower() {
        let heavy = BikePhysics(parameters: .init(totalMassKg: 110))
        let light = (0..<4000).reduce(0.0) { s, _ in physics.nextSpeed(from: s, powerWatts: 250, grade: 0.06, interval: 0.25) }
        let slow = (0..<4000).reduce(0.0) { s, _ in heavy.nextSpeed(from: s, powerWatts: 250, grade: 0.06, interval: 0.25) }

        #expect(slow < light)
    }
}

struct GradeSyncTests {
    private func send(_ sync: inout GradeSync, _ grade: Double, at time: TimeInterval) -> Bool {
        sync.shouldSend(grade, at: time)
    }

    @Test func sendsFirstGradeImmediately() {
        var sync = GradeSync()
        #expect(send(&sync, 2, at: 0) == true)
    }

    @Test func ignoresSmallChanges() {
        var sync = GradeSync()
        _ = sync.shouldSend(2, at: 0)

        #expect(send(&sync, 2.3, at: 5) == false)
    }

    @Test func rateLimitsLargeChanges() {
        var sync = GradeSync()
        _ = sync.shouldSend(2, at: 0)

        #expect(send(&sync, 5, at: 1) == false)
        #expect(send(&sync, 5, at: 2) == true)
    }

    @Test func refreshesUnchangedGradePeriodically() {
        var sync = GradeSync()
        _ = sync.shouldSend(2, at: 0)

        #expect(send(&sync, 2, at: 14) == false)
        #expect(send(&sync, 2, at: 15) == true)
    }

    @Test func resetForcesNextSend() {
        var sync = GradeSync()
        _ = sync.shouldSend(2, at: 0)
        sync.reset()

        #expect(send(&sync, 2, at: 0.5) == true)
    }
}

@MainActor
struct RideSessionTests {
    private let clock = TestClock()

    private func makeSession(route: Route, rider: SimulatedRider = SimulatedRider(), difficulty: Double = 0.5) -> RideSession {
        RideSession(
            route: route,
            trainer: rider,
            physics: .init(totalMassKg: 84),
            difficulty: difficulty,
            advancesAutomatically: false,
            now: { [clock] in clock.now }
        )
    }

    private func ride(_ session: RideSession, seconds: Double) {
        for _ in 0..<Int(seconds * 4) {
            clock.advance(by: 0.25)
            session.advance(by: 0.25)
        }
    }

    @Test func doesNotMoveBeforeStarting() throws {
        let session = makeSession(route: try straightRoute { _ in 0 })
        session.advance(by: 1)

        #expect(session.distance == 0)
        #expect(session.phase == .ready)
    }

    @Test func movesAlongRouteUnderPower() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        session.start()

        ride(session, seconds: 60)

        #expect(session.distance > 300)
        #expect(session.powerWatts == 200)
        #expect(session.cadenceRpm == 85)
        #expect(abs(session.elapsed - 60) < 0.001)
    }

    @Test func recordsOneSamplePerSecond() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        session.start()

        ride(session, seconds: 10)

        #expect((10...11).contains(session.samples.count))
        #expect(session.samples.first?.distance == 0)
    }

    @Test func sendsScaledGradeToTrainer() async throws {
        let rider = SimulatedRider()
        let session = makeSession(route: try straightRoute { $0 * 0.06 }, rider: rider, difficulty: 0.5)
        session.start()
        for _ in 0..<5 { await Task.yield() }

        #expect(rider.sentGrades.first == 3.0)
        #expect(abs(session.trainerGradePercent - 3.0) < 1e-6)
    }

    @Test func estimatesPositionBetweenTicks() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        session.start()
        ride(session, seconds: 10)
        let speed = session.speedMetersPerSecond

        let halfTick = session.estimatedDistance(at: clock.now.addingTimeInterval(0.05))
        let stalled = session.estimatedDistance(at: clock.now.addingTimeInterval(5))

        #expect(abs(halfTick - (session.distance + speed * 0.05)) < 1e-9)
        #expect(abs(stalled - (session.distance + speed * RideSession.maximumExtrapolation)) < 1e-9)
        #expect(session.estimatedDistance(at: clock.now.addingTimeInterval(-1)) == session.distance)
    }

    @Test func previewsCanFastForward() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        session.start()
        ride(session, seconds: 10)

        session.setPlaybackSpeed(5)
        let estimate = session.estimatedDistance(at: clock.now.addingTimeInterval(0.1))

        #expect(session.isPreview)
        #expect(session.playbackSpeed == 5)
        #expect(abs(estimate - (session.distance + session.speedMetersPerSecond * 0.5)) < 1e-9)
    }

    @Test func rejectsUnsupportedPlaybackSpeeds() throws {
        let session = makeSession(route: try straightRoute { _ in 0 })
        session.setPlaybackSpeed(3)
        #expect(session.playbackSpeed == 1)
    }

    @Test func realTrainerRidesAlwaysRunInRealTime() throws {
        let trainer = TrainerController(client: ControlPointClient(timeout: .milliseconds(200)))
        let session = RideSession(
            route: try straightRoute { _ in 0 },
            trainer: trainer,
            physics: .init(totalMassKg: 84),
            difficulty: 0.5,
            advancesAutomatically: false
        )

        session.setPlaybackSpeed(10)

        #expect(!session.isPreview)
        #expect(session.playbackSpeed == 1)
    }

    @Test func estimateHoldsStillWhenPausedAndAtTheFinish() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        #expect(session.estimatedDistance(at: clock.now) == 0)

        session.start()
        ride(session, seconds: 10)
        session.pause()
        #expect(session.estimatedDistance(at: clock.now.addingTimeInterval(0.2)) == session.distance)

        let short = makeSession(route: try straightRoute(lengthMeters: 50, pointCount: 2) { _ in 0 })
        short.start()
        ride(short, seconds: 60)
        #expect(short.estimatedDistance(at: clock.now.addingTimeInterval(0.2)) <= short.route.totalDistance)
    }

    @Test func pauseHoldsPositionAndTime() throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        session.start()
        ride(session, seconds: 10)
        session.pause()
        let distance = session.distance

        ride(session, seconds: 10)

        #expect(session.distance == distance)
        #expect(abs(session.elapsed - 10) < 0.001)
        #expect(session.speedMetersPerSecond == 0)
    }

    @Test func finishesAtTheEndOfTheRoute() async throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 50, pointCount: 2) { _ in 0 })
        session.start()

        ride(session, seconds: 60)
        for _ in 0..<5 { await Task.yield() }

        #expect(session.phase == .finished)
        #expect(session.distance == session.route.totalDistance)
        #expect(session.remainingDistance == 0)
    }

    @Test func producesRecordOnlyAfterRiding() async throws {
        let session = makeSession(route: try straightRoute(lengthMeters: 5000) { _ in 0 })
        #expect(session.makeRecord() == nil)

        session.start()
        ride(session, seconds: 5)
        await session.finish()

        let record = try #require(session.makeRecord())
        #expect(record.routeName == "Test")
        #expect(record.distance == session.distance)
    }
}

/// Rides every bundled route end to end, so a broken route fails here rather than mid-ride.
@MainActor
struct BundledRouteRideTests {
    @Test func everyBundledRouteCanBeRiddenToTheFinish() async throws {
        let library = RouteLibrary(directory: URL.temporaryDirectory.appending(path: "RideAll-\(UUID().uuidString)"))
        let routes = library.routes.filter { library.isBuiltIn($0) }
        #expect(routes.count >= 25)

        for route in routes {
            let clock = TestClock()
            let session = RideSession(
                route: route,
                trainer: SimulatedRider(powerWatts: 250),
                physics: .init(totalMassKg: 84),
                difficulty: 0.5,
                advancesAutomatically: false,
                now: { [clock] in clock.now }
            )
            session.start()

            var previous = session.position.coordinate
            var slowest = Double.infinity
            var biggestJump = 0.0
            let step: TimeInterval = 1
            let limit = route.totalDistance / 1.0 // a 1 m/s crawl is the slowest acceptable average
            while session.phase == .riding, session.elapsed < limit {
                clock.advance(by: step)
                session.advance(by: step)
                let here = session.position.coordinate
                biggestJump = max(biggestJump, Geo.distance(from: previous, to: here) - session.speedMetersPerSecond * step)
                previous = here
                if session.elapsed > 30 { slowest = min(slowest, session.speedMetersPerSecond) }
            }
            for _ in 0..<5 { await Task.yield() }

            #expect(session.phase == .finished, "\(route.name) never reached the finish")
            #expect(slowest > 1.5, "\(route.name) slowed to \(slowest) m/s at 250 W")
            #expect(biggestJump < 1, "\(route.name) jumped \(biggestJump) m further than speed allows")
            #expect(session.samples.count > 10, "\(route.name) recorded too few samples")
        }
    }
}

struct RideRecordTests {
    private func sample(_ second: Double, distance: Double, watts: Int, elevation: Double = 0) -> RideSample {
        RideSample(
            timestamp: Date(timeIntervalSinceReferenceDate: second),
            elapsed: second,
            distance: distance,
            speedMetersPerSecond: 10,
            powerWatts: watts,
            cadenceRpm: 90,
            latitude: 45,
            longitude: 7,
            elevation: elevation
        )
    }

    @Test func summarisesSamples() {
        let record = RideRecord(id: UUID(), routeName: "R", startedAt: .now, samples: [
            sample(0, distance: 0, watts: 100, elevation: 10),
            sample(10, distance: 100, watts: 200, elevation: 15),
            sample(20, distance: 200, watts: 300, elevation: 12),
        ])

        #expect(record.duration == 20)
        #expect(record.distance == 200)
        #expect(record.averageSpeedMetersPerSecond == 10)
        #expect(record.averagePowerWatts == 200)
        #expect(record.maximumPowerWatts == 300)
        #expect(record.elevationGain == 5)
        #expect(record.workKilojoules == 5)
    }

    @Test func emptyRecordIsZero() {
        let record = RideRecord(id: UUID(), routeName: "R", startedAt: .now, samples: [])

        #expect(record.duration == 0)
        #expect(record.averagePowerWatts == 0)
        #expect(record.averageSpeedMetersPerSecond == 0)
    }

    @Test func exportsValidTCXWithPower() throws {
        let record = RideRecord(
            id: UUID(),
            routeName: "Alpe <d'Huez> & more",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            samples: [sample(0, distance: 0, watts: 150), sample(1, distance: 10, watts: 250)]
        )

        let tcx = TCXExporter.export(record)
        let elements = try XMLElementCollector.collect(tcx)

        #expect(elements.filter { $0.name == "Trackpoint" }.count == 2)
        #expect(elements.filter { $0.name == "ns3:Watts" }.map(\.text) == ["150", "250"])
        #expect(tcx.contains("<Id>2023-11-14T22:13:20Z</Id>"))
        #expect(tcx.contains("Alpe &lt;d&apos;Huez&gt; &amp; more"))
        #expect(tcx.contains("<Cadence>90</Cadence>"))
    }
}
