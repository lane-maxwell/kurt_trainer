import Foundation

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric
    case imperial

    static let storageKey = "unitSystem"

    static var localeDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    var id: String { rawValue }

    var speedUnit: String { self == .metric ? "km/h" : "mph" }
    var distanceUnit: String { self == .metric ? "km" : "mi" }

    func speed(fromKph kph: Double) -> Double {
        self == .metric ? kph : kph / 1.609344
    }

    var elevationUnit: String { self == .metric ? "m" : "ft" }
    var weightUnit: String { self == .metric ? "kg" : "lb" }

    func speed(fromMetersPerSecond speed: Double) -> Double {
        self.speed(fromKph: speed * 3.6)
    }

    func distance(fromMeters meters: Double) -> Double {
        self == .metric ? meters / 1000 : meters / 1609.344
    }

    func elevation(fromMeters meters: Double) -> Double {
        self == .metric ? meters : meters * 3.28084
    }

    func weight(fromKilograms kg: Double) -> Double {
        self == .metric ? kg : kg * 2.20462
    }

    func kilograms(fromWeight weight: Double) -> Double {
        self == .metric ? weight : weight / 2.20462
    }

    func formatDistance(_ meters: Double) -> String {
        "\(distance(fromMeters: meters).formatted(.number.precision(.fractionLength(1)))) \(distanceUnit)"
    }

    func formatElevation(_ meters: Double) -> String {
        "\(Int(elevation(fromMeters: meters).rounded()).formatted()) \(elevationUnit)"
    }
}

extension TimeInterval {
    var rideClock: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
