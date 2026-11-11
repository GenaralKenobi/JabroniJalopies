import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles = "mi"
    case kilometers = "km"
    /// Engine / hour-meter readings, for machines that run on hours (chippers, loaders…).
    case hours = "hr"

    /// `@AppStorage` / `UserDefaults` key.
    static let storageKey = "distanceUnit"

    var id: String { rawValue }
    var abbreviation: String { rawValue }

    var displayName: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        case .hours: "Hours"
        }
    }

    /// What the reading is called: "Odometer" or "Hour meter".
    var readingName: String { self == .hours ? "Hour meter" : "Odometer" }

    /// The fleet-wide setting is miles or kilometres; hours are chosen per vehicle.
    static let fleetOptions: [DistanceUnit] = [.miles, .kilometers]

    /// Default based on the device region (miles for the US and UK).
    static var localeDefault: DistanceUnit {
        let system = Locale.current.measurementSystem
        return (system == .us || system == .uk) ? .miles : .kilometers
    }

    /// The fleet's saved unit, for places that can't use `@AppStorage` (e.g. initializers).
    static var current: DistanceUnit {
        let saved = UserDefaults.standard.string(forKey: storageKey).flatMap(DistanceUnit.init(rawValue:))
        return (saved == .hours ? nil : saved) ?? localeDefault
    }

    /// A vehicle's own unit if it has one, otherwise the fleet's.
    static func resolved(_ vehicleUnit: String?) -> DistanceUnit {
        vehicleUnit.flatMap(DistanceUnit.init(rawValue:)) ?? current
    }
}
