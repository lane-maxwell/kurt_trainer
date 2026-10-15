import MapKit
import SwiftUI

/// The in-ride screen: a 3D map following the rider, live numbers, and the elevation profile.
struct RideView: View {
    @Bindable var session: RideSession

    @Environment(\.dismiss) private var dismiss
    @Environment(RideStore.self) private var store
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @AppStorage(CameraView.storageKey) private var cameraView = CameraView.close
    @State private var isConfirmingEnd = false
    @State private var isShowingSummary = false

    var body: some View {
        ZStack {
            FollowingRideMap(session: session, view: cameraView)
                .ignoresSafeArea()

            VStack {
                RideMetricsOverlay(session: session, units: units)
                Spacer()
                RideBottomPanel(
                    session: session,
                    units: units,
                    cameraView: $cameraView,
                    onEnd: { isConfirmingEnd = true }
                )
            }
            .padding()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .finished { isShowingSummary = true }
        }
        .confirmationDialog("End this ride?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("End ride", role: .destructive) {
                Task { await session.finish() }
            }
        }
        .sheet(isPresented: $isShowingSummary) {
            RideSummaryView(record: session.makeRecord()) {
                dismiss()
            }
            .interactiveDismissDisabled()
        }
    }

}

/// A chase-cam map that follows the rider along the route. Used on the phone and on the TV.
///
/// The camera is set directly on every display frame rather than animated: MapKit animates a
/// pitched camera's eye through 3D space, so chained animations swing the view off the road on
/// curves. Setting it each frame keeps the rider exactly on the line and still looks smooth.
struct FollowingRideMap: View {
    let session: RideSession
    var view: CameraView = .close
    /// Scales the camera's distance, e.g. to show more of the route on a big TV.
    var distanceScale: Double = 1

    @State private var camera: MapCameraPosition = .automatic
    @State private var heading: Double?
    @State private var lastFrame: Date?

    /// Time constant for easing the view into a new direction.
    private static let headingTimeConstant: TimeInterval = 0.6

    var body: some View {
        TimelineView(.animation) { context in
            ZStack {
                map
                // MapKit annotations get hidden by 3D terrain, so the rider is a fixed overlay at
                // the screen centre, which is exactly where the camera is pointed.
                RiderPuck()
                    .allowsHitTesting(false)
            }
            .onChange(of: context.date, initial: true) { _, date in follow(at: date) }
        }
    }

    private func follow(at date: Date) {
        let position = session.route.position(at: session.estimatedDistance(at: date))
        let interval = lastFrame.map { min(max(date.timeIntervalSince($0), 0), 0.5) } ?? 0
        lastFrame = date

        // Ease over ride time, not wall time, so a fast-forwarded preview still turns with the road
        // instead of leaving the camera parked over the corner building.
        let fraction = 1 - exp(-interval * session.playbackSpeed / Self.headingTimeConstant)
        let smoothed = heading.map { Geo.blendHeading($0, toward: position.heading, fraction: fraction) } ?? position.heading
        heading = smoothed

        camera = .camera(MapCamera(
            centerCoordinate: position.coordinate,
            distance: view.distance * distanceScale,
            heading: smoothed,
            pitch: view.pitch
        ))
    }

    private var map: some View {
        Map(position: $camera, interactionModes: []) {
            MapPolyline(coordinates: session.route.displayCoordinates)
                .stroke(.orange.opacity(0.85), lineWidth: 6)
        }
        // Flat imagery on purpose. Realistic 3D looked great in stills but buildings hid the road
        // and, when one stood between camera and rider, put the rider marker on its roof.
        .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}

private struct RiderPuck: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .stroke(.white, lineWidth: 3)
            .frame(width: 22, height: 22)
            .shadow(radius: 4)
            .accessibilityLabel("Your position")
    }
}

private struct RideMetricsOverlay: View {
    let session: RideSession
    let units: UnitSystem

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(session.powerWatts)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("watts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                GradeBadge(percent: session.roadGradePercent)
                Text("\(units.speed(fromMetersPerSecond: session.speedMetersPerSecond).formatted(.number.precision(.fractionLength(1)))) \(units.speedUnit)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                if let cadence = session.cadenceRpm {
                    Text("\(Int(cadence)) rpm")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .animation(.snappy, value: session.powerWatts)
    }
}

private struct RideBottomPanel: View {
    let session: RideSession
    let units: UnitSystem
    @Binding var cameraView: CameraView
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                stat(title: "Time", value: session.elapsed.rideClock)
                Spacer()
                stat(title: "Ridden", value: units.formatDistance(session.distance))
                Spacer()
                stat(title: "To go", value: units.formatDistance(session.remainingDistance))
            }

            ElevationProfileView(route: session.route, currentDistance: session.distance, showsAxes: false)
                .frame(height: 60)

            if session.isPreview {
                Picker("Preview speed", selection: Binding(
                    get: { session.playbackSpeed },
                    set: { session.setPlaybackSpeed($0) }
                )) {
                    ForEach(RideSession.playbackSpeeds, id: \.self) { speed in
                        Text("\(Int(speed))×").tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Preview speed")
            }

            HStack(spacing: 12) {
                switch session.phase {
                case .riding:
                    Button("Pause", systemImage: "pause.fill") { session.pause() }
                        .buttonStyle(.bordered)
                case .paused:
                    Button("Resume", systemImage: "play.fill") { session.resume() }
                        .buttonStyle(.borderedProminent)
                case .ready, .finished:
                    EmptyView()
                }
                Button("\(cameraView.toggled.title) view", systemImage: cameraView.toggled.systemImage) {
                    cameraView = cameraView.toggled
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                Button("End", systemImage: "stop.fill", role: .destructive, action: onEnd)
                    .buttonStyle(.bordered)
                    .disabled(session.phase == .finished)
            }
            .controlSize(.large)
        }
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
