import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles = "mi"
    case kilometers = "km"

    /// `@AppStorage` / `UserDefaults` key.
    static let storageKey = "distanceUnit"

    var id: String { rawValue }
    var abbreviation: String { rawValue }

    var displayName: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        }
    }

    /// Default based on the device region (miles for the US and UK).
    static var localeDefault: DistanceUnit {
        let system = Locale.current.measurementSystem
        return (system == .us || system == .uk) ? .miles : .kilometers
    }

    /// The user's saved preference, for places that can't use `@AppStorage` (e.g. initializers).
    static var current: DistanceUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? localeDefault
    }
}
