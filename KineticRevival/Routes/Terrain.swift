import SwiftUI

/// A one-word feel for a route, from average climbing per kilometre.
enum Terrain: String, CaseIterable, Sendable {
    case flat = "Flat"
    case rolling = "Rolling"
    case hilly = "Hilly"
    case mountain = "Mountain"

    init(climbingMetersPerKilometer rate: Double) {
        switch rate {
        case ..<5: self = .flat
        case ..<12: self = .rolling
        case ..<25: self = .hilly
        default: self = .mountain
        }
    }

    var color: Color {
        switch self {
        case .flat: .green
        case .rolling: .yellow
        case .hilly: .orange
        case .mountain: .red
        }
    }
}

extension Route {
    var terrain: Terrain {
        Terrain(climbingMetersPerKilometer: elevationGain / max(totalDistance / 1000, 0.001))
    }
}
