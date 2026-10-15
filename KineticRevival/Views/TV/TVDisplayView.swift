import SwiftUI

/// What the TV shows over AirPlay: the active route ride, the free-ride dashboard, or a welcome screen.
/// Non-interactive; everything is controlled from the phone.
struct TVDisplayView: View {
    @Environment(AppModel.self) private var app
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let ride = app.activeRide {
                TVRideView(session: ride)
            } else if bluetooth.state.isLinked {
                TVFreeRideView(trainer: bluetooth.trainer)
            } else {
                TVWelcomeView()
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut, value: app.activeRide == nil)
    }
}

private struct TVRideView: View {
    let session: RideSession
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @AppStorage(CameraView.storageKey) private var cameraView = CameraView.close

    var body: some View {
        ZStack {
            // A wide TV shows more road, so pull back a little from the phone's framing.
            FollowingRideMap(session: session, view: cameraView, distanceScale: 1.3)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    TVPowerTile(watts: session.powerWatts)
                    Spacer()
                    TVTile {
                        VStack(alignment: .trailing, spacing: 12) {
                            GradeBadge(percent: session.roadGradePercent)
                                .scaleEffect(1.8, anchor: .trailing)
                                .padding(.bottom, 12)
                            TVStat(
                                value: units.speed(fromMetersPerSecond: session.speedMetersPerSecond)
                                    .formatted(.number.precision(.fractionLength(1))),
                                unit: units.speedUnit
                            )
                            if let cadence = session.cadenceRpm {
                                TVStat(value: "\(Int(cadence))", unit: "rpm")
                            }
                        }
                    }
                }
                Spacer()
                TVTile {
                    VStack(spacing: 16) {
                        HStack {
                            Text(session.route.name).font(.title2.weight(.semibold))
                            Spacer()
                            TVStat(value: session.elapsed.rideClock, unit: nil)
                            Spacer().frame(width: 48)
                            TVStat(value: units.formatDistance(session.distance), unit: "ridden")
                            Spacer().frame(width: 48)
                            TVStat(value: units.formatDistance(session.remainingDistance), unit: "to go")
                        }
                        ElevationProfileView(route: session.route, currentDistance: session.distance, showsAxes: false)
                            .frame(height: 110)
                    }
                }
            }
            .padding(48)

            if session.phase == .paused || session.phase == .finished {
                TVBanner(text: session.phase == .paused ? "Paused" : "Ride complete")
            }
        }
    }
}

private struct TVFreeRideView: View {
    let trainer: TrainerController
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault

    var body: some View {
        VStack(spacing: 48) {
            TVPowerTile(watts: trainer.latestData?.powerWatts ?? 0)
                .scaleEffect(1.4)
            HStack(spacing: 80) {
                TVStat(
                    value: (trainer.latestData?.speedKph).map { units.speed(fromKph: $0).formatted(.number.precision(.fractionLength(1))) } ?? "—",
                    unit: units.speedUnit
                )
                TVStat(value: trainer.metrics.movingTime.rideClock, unit: "moving")
                TVStat(value: units.formatDistance(trainer.metrics.distanceMeters), unit: "distance")
                TVStat(value: targetText, unit: "target")
            }
        }
        .padding(64)
    }

    private var targetText: String {
        switch trainer.displayedMode {
        case let .resistance(level): "Level \(level.formatted(.number.precision(.fractionLength(0))))"
        case let .erg(watts): "\(watts) W"
        case let .simulation(grade): "\(grade.formatted(.number.precision(.fractionLength(1))))%"
        case nil: "—"
        }
    }
}

private struct TVWelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bicycle")
                .font(.system(size: 120))
                .foregroundStyle(.orange)
            Text("Kinetic Revival")
                .font(.system(size: 72, weight: .bold, design: .rounded))
            Text("Connect your trainer and pick a route on your iPhone.")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TVPowerTile: View {
    let watts: Int

    var body: some View {
        TVTile {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(watts)")
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: watts)
                Text("W")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TVStat: View {
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit).font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TVTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(28)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
    }
}

private struct TVBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .padding(.horizontal, 64)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial, in: .capsule)
    }
}
