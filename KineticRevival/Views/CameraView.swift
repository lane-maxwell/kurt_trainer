import Foundation

/// How the ride camera frames the rider on the flat satellite map.
enum CameraView: String, CaseIterable, Identifiable, Sendable {
    /// Near the rider, for seeing the path itself.
    case close
    /// Higher and wider, for seeing what's coming.
    case wide

    static let storageKey = "cameraView"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .close: "Close"
        case .wide: "Wide"
        }
    }

    var systemImage: String {
        switch self {
        case .close: "plus.magnifyingglass"
        case .wide: "minus.magnifyingglass"
        }
    }

    /// Metres from the camera to the rider.
    var distance: Double {
        switch self {
        case .close: 220
        case .wide: 600
        }
    }

    /// Degrees from looking straight down.
    var pitch: Double {
        switch self {
        case .close: 60
        case .wide: 55
        }
    }

    var toggled: CameraView { self == .close ? .wide : .close }
}
