import Foundation

/// Common maintenance categories. Stored on models as a raw `String` so SwiftData
/// predicates and future cases stay safe.
enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case oilChange
    case tireRotation
    case brakes
    case airFilter
    case cabinFilter
    case battery
    case coolant
    case transmissionFluid
    case sparkPlugs
    case wipers
    case tires
    case alignment
    case inspection
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oilChange: "Oil Change"
        case .tireRotation: "Tire Rotation"
        case .brakes: "Brakes"
        case .airFilter: "Engine Air Filter"
        case .cabinFilter: "Cabin Air Filter"
        case .battery: "Battery"
        case .coolant: "Coolant Flush"
        case .transmissionFluid: "Transmission Fluid"
        case .sparkPlugs: "Spark Plugs"
        case .wipers: "Wiper Blades"
        case .tires: "New Tires"
        case .alignment: "Wheel Alignment"
        case .inspection: "Inspection"
        case .other: "Other"
        }
    }

    /// SF Symbol name.
    var symbolName: String {
        switch self {
        case .oilChange: "drop.fill"
        case .tireRotation: "arrow.triangle.2.circlepath"
        case .brakes: "exclamationmark.brakesignal"
        case .airFilter: "wind"
        case .cabinFilter: "aqi.medium"
        case .battery: "minus.plus.batteryblock.fill"
        case .coolant: "thermometer.medium"
        case .transmissionFluid: "gearshape.2.fill"
        case .sparkPlugs: "bolt.fill"
        case .wipers: "windshield.front.and.wiper"
        case .tires: "circle.circle"
        case .alignment: "arrow.left.and.right"
        case .inspection: "checklist"
        case .other: "wrench.and.screwdriver.fill"
        }
    }

    /// Typical intervals (distance in miles, time in months). These are generic
    /// starting points — the owner's manual always wins.
    private var typicalInterval: (miles: Int?, months: Int?) {
        switch self {
        case .oilChange: (5_000, 6)
        case .tireRotation: (6_000, 6)
        case .brakes: (25_000, 24)
        case .airFilter: (15_000, 12)
        case .cabinFilter: (15_000, 12)
        case .battery: (nil, 48)
        case .coolant: (50_000, 60)
        case .transmissionFluid: (60_000, 60)
        case .sparkPlugs: (60_000, nil)
        case .wipers: (nil, 12)
        case .tires: (50_000, 72)
        case .alignment: (nil, 24)
        case .inspection: (nil, 12)
        case .other: (nil, nil)
        }
    }

    /// Suggested interval expressed in the user's distance unit, rounded to a tidy number.
    func suggestedInterval(in unit: DistanceUnit) -> (distance: Int?, months: Int?) {
        let interval = typicalInterval
        // No suggested hour intervals: they depend on the machine, so the manager enters them.
        if unit == .hours { return (nil, interval.months) }
        let distance = interval.miles.map { miles -> Int in
            switch unit {
            case .kilometers: return Int((Double(miles) * 1.609_344 / 1_000).rounded()) * 1_000
            default: return miles
            }
        }
        return (distance, interval.months)
    }
}
