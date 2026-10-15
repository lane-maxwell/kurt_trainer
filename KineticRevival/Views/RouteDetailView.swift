import MapKit
import SwiftUI

struct RouteDetailView: View {
    let route: Route

    @Environment(AppModel.self) private var app
    @Environment(BluetoothManager.self) private var bluetooth
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault

    var body: some View {
        List {
            Section {
                RouteMap(route: route)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            Section("Profile") {
                ElevationProfileView(route: route)
                    .frame(height: 140)
                    .padding(.vertical, 8)
                LabeledContent("Distance", value: units.formatDistance(route.totalDistance))
                LabeledContent("Climbing", value: units.formatElevation(route.elevationGain))
                LabeledContent("Steepest", value: "\(steepestGradePercent.formatted(.number.precision(.fractionLength(1))))%")
                if !route.hasElevation {
                    Label("This GPX has no elevation data, so it will ride flat.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    startRide(with: bluetooth.trainer)
                } label: {
                    Label("Start ride", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isTrainerReady)
                .listRowBackground(Color.clear)

                Button("Preview with a simulated 200 W rider") {
                    startRide(with: SimulatedRider())
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } footer: {
                if !isTrainerReady {
                    Text("Connect your trainer in the Trainer tab to ride for real.")
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Bindable(app).activeRide) { session in
            RideView(session: session)
        }
    }

    private var isTrainerReady: Bool {
        if case .connected = bluetooth.state { true } else { false }
    }

    private var steepestGradePercent: Double {
        stride(from: 0, through: route.totalDistance, by: 25).map { route.grade(at: $0) }.max().map { $0 * 100 } ?? 0
    }

    private func startRide(with trainer: RideTrainer) {
        app.startRide(on: route, with: trainer)
    }
}

extension RideSession: Identifiable {}

/// Static overview of a route with start and finish markers.
struct RouteMap: View {
    let route: Route

    var body: some View {
        Map(initialPosition: .rect(boundingRect)) {
            MapPolyline(coordinates: route.displayCoordinates)
                .stroke(.orange, lineWidth: 4)
            Marker("Start", systemImage: "flag", coordinate: route.points[0].coordinate)
                .tint(.green)
            Marker("Finish", systemImage: "flag.checkered", coordinate: route.points[route.points.count - 1].coordinate)
                .tint(.red)
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private var boundingRect: MKMapRect {
        let rect = route.displayCoordinates
            .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
            .reduce(MKMapRect.null) { $0.union($1) }
        return rect.insetBy(dx: -rect.width * 0.15 - 200, dy: -rect.height * 0.15 - 200)
    }
}

extension Route {
    /// At most ~2000 points, which is plenty for drawing and keeps MapKit responsive on long routes.
    var displayCoordinates: [CLLocationCoordinate2D] {
        let step = max(points.count / 2000, 1)
        var coordinates = stride(from: 0, to: points.count, by: step).map { points[$0].coordinate }
        if (points.count - 1) % step != 0 { coordinates.append(points[points.count - 1].coordinate) }
        return coordinates
    }
}
