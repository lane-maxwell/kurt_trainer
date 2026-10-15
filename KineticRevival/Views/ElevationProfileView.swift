import Charts
import SwiftUI

struct ElevationProfileView: View {
    let route: Route
    var currentDistance: Double?
    var showsAxes = true

    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault

    /// A lakefront path that varies by 8 m shouldn't be drawn as a sawtooth.
    private static let minimumSpanMeters = 60.0

    private var samples: [(distance: Double, elevation: Double)] { route.profile() }

    var body: some View {
        let lowest = samples.map(\.elevation).min() ?? 0
        let highest = max(samples.map(\.elevation).max() ?? 0, lowest + Self.minimumSpanMeters)
        // Pad the floor so flat routes don't render as a full-height block.
        let floor = units.elevation(fromMeters: lowest - max((highest - lowest) * 0.2, 5))

        Chart {
            ForEach(samples.indices, id: \.self) { index in
                let sample = samples[index]
                AreaMark(
                    x: .value("Distance", units.distance(fromMeters: sample.distance)),
                    yStart: .value("Floor", floor),
                    yEnd: .value("Elevation", units.elevation(fromMeters: sample.elevation))
                )
                .foregroundStyle(.linearGradient(
                    colors: [.orange.opacity(0.6), .orange.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            if let currentDistance {
                RuleMark(x: .value("You", units.distance(fromMeters: currentDistance)))
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: floor...units.elevation(fromMeters: highest + 2))
        .chartXScale(domain: 0...units.distance(fromMeters: route.totalDistance))
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .accessibilityLabel("Elevation profile")
    }
}

struct GradeBadge: View {
    let percent: Double

    var body: some View {
        Text("\(percent.formatted(.number.precision(.fractionLength(1))))%")
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.gradient, in: .capsule)
            .foregroundStyle(.white)
            .accessibilityLabel("Grade \(percent.formatted(.number.precision(.fractionLength(1)))) percent")
    }

    private var color: Color {
        switch percent {
        case ..<(-1): .blue
        case ..<3: .green
        case ..<6: .yellow
        case ..<9: .orange
        default: .red
        }
    }
}
