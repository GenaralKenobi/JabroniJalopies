import FirebaseFirestore
import Foundation

/// fleets/{fleetId}/vehicles/{vehicleId}
struct Vehicle: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    /// Optional nickname or unit number, e.g. "Truck 12".
    var name: String
    var make: String
    var model: String
    var year: Int
    var vin: String
    var licensePlate: String
    var odometer: Int
    var odometerUpdatedAt: Date?
    var odometerUpdatedBy: String?
    /// Drivers who can see this vehicle even when they can't see the whole fleet.
    var assignedUids: [String]
    var specSections: [SpecSection]
    /// Small JPEG thumbnail stored inline so it works offline and on the free plan.
    var photo: Data?
    @ServerTimestamp var createdAt: Date?

    static func new() -> Vehicle {
        Vehicle(name: "", make: "", model: "", year: Calendar.current.component(.year, from: .now),
                vin: "", licensePlate: "", odometer: 0, assignedUids: [],
                specSections: SpecDefaults.sections())
    }
}

extension Vehicle {
    /// "2019 Toyota Camry"
    var yearMakeModel: String {
        [year > 0 ? String(year) : "", make, model]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var displayName: String {
        if !name.isEmpty { return name }
        let ymm = yearMakeModel
        return ymm.isEmpty ? "Vehicle" : ymm
    }

    /// Shown under the display name when a nickname is used.
    var subtitle: String { name.isEmpty ? "" : yearMakeModel }
}

/// A group of quick-reference specs, e.g. "Fluids" or "Tires & Wheels".
struct SpecSection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var rows: [SpecRow]
}

struct SpecRow: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var value: String
}
