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
    /// "mi", "km" or "hr" for this vehicle; nil uses the fleet's unit.
    var readingUnit: String?
    var odometerUpdatedAt: Date?
    var odometerUpdatedBy: String?
    /// Drivers who can see this vehicle even when they can't see the whole fleet.
    var assignedUids: [String]
    /// The one non-manager (the "truck lead") who may also edit this truck's contents list.
    var contentsEditorUid: String?
    /// The truck lead's name, so drivers can see it without loading the member list.
    var contentsEditorName: String?
    /// A small summary of what's going on with this truck, so the fleet list can show
    /// badges from this one document instead of loading every truck's records.
    var summary: VehicleSummary?
    /// When repeating checklist items and scheduled checklists were last done on this truck.
    var checklistState: ChecklistState?
    /// Dates managers picked for doing scheduled checklists on this truck, by checklist id.
    var checklistPlans: [String: ChecklistPlan]?
    var specSections: [SpecSection]
    /// Small JPEG thumbnail stored inline so it works offline and on the free plan.
    var photo: Data?
    /// Who services this truck (a mechanic or dealer). Every field is optional.
    var serviceContact: ServiceContact?
    @ServerTimestamp var createdAt: Date?

    static func new() -> Vehicle {
        Vehicle(name: "", make: "", model: "", year: Calendar.current.component(.year, from: .now),
                vin: "", licensePlate: "", odometer: 0, assignedUids: [],
                specSections: SpecDefaults.sections())
    }
}

extension Vehicle {
    var unit: DistanceUnit { DistanceUnit.resolved(readingUnit) }

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

/// fleets/{fleetId}/vehicles/{vehicleId}/contents/{itemId} — one thing kept on the truck.
struct TruckItem: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String
    /// nil when a count doesn't matter (e.g. "Rain gear").
    var quantity: Int?
    /// Where on the truck, e.g. "Left side box". Empty means no particular place.
    var location: String
    var notes: String
    var updatedAt: Date?
    var updatedBy: String?
    var updatedByName: String?
    /// What's inside it, for a kit such as a first-aid kit (gauze, eyewash, tourniquet…).
    var parts: [KitPart]? = nil

    static func new(location: String = "") -> TruckItem {
        TruckItem(name: "", quantity: nil, location: location, notes: "")
    }
}

/// One thing inside a kit, e.g. "Gauze pads" ×4.
/// A truck's mechanic or dealer. Any of the fields can be missing.
struct ServiceContact: Codable, Hashable {
    var name: String?
    var phone: String?
    var website: String?
    var address: String?

    /// Trims each field and drops empty ones; nil when nothing is left.
    static func cleaned(name: String, phone: String, website: String, address: String) -> ServiceContact? {
        func clean(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        let contact = ServiceContact(name: clean(name), phone: clean(phone), website: clean(website), address: clean(address))
        return contact.isEmpty ? nil : contact
    }

    var isEmpty: Bool { name == nil && phone == nil && website == nil && address == nil }

    /// tel: link from the digits (and a leading +).
    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.enumerated().filter { $0.element.isNumber || ($0.offset == 0 && $0.element == "+") }.map { String($0.element) }.joined()
        return digits.count >= 3 ? URL(string: "tel:\(digits)") : nil
    }

    /// Adds https:// when the website was typed without it.
    var websiteURL: URL? {
        guard let website else { return nil }
        let text = website.lowercased().hasPrefix("http://") || website.lowercased().hasPrefix("https://") ? website : "https://\(website)"
        guard let url = URL(string: text), url.host?.contains(".") == true else { return nil }
        return url
    }

    /// Opens the address in Maps.
    var mapsURL: URL? {
        guard let address, let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }
}

struct KitPart: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var quantity: Int?

    static func new(_ name: String = "", quantity: Int? = nil) -> KitPart {
        KitPart(id: UUID().uuidString, name: name, quantity: quantity)
    }
}

/// A kit a manager saved for the fleet, to add to any truck in one go.
struct TruckKit: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var parts: [KitPart]
}

/// A manager's planned day for a scheduled checklist on one truck.
struct ChecklistPlan: Codable, Hashable {
    var date: Date
    /// The due date this plan was made for. Once the checklist is done the due date
    /// moves on, and the old plan no longer applies.
    var forDue: Date? = nil
    /// For reading-based checklists: the due reading this plan was made for.
    var forReading: Int? = nil
    var byName: String?
}

/// Kept on each truck's document and updated as things change (see FleetModel+Summary).
/// A missing value means "not known yet": the app then loads the details to find out.
struct VehicleSummary: Codable, Hashable {
    var lastChecklistAt: Date?
    var lastChecklistBy: String?
    /// Open (or reported fixed) defects, and how many of those are safety defects.
    var openDefects: Int?
    var unsafeDefects: Int?
    /// Driver-logged services waiting for a manager.
    var pendingServices: Int?
    /// The earliest maintenance reminder due date and lowest due odometer.
    var nextDueDate: Date?
    var nextDueOdometer: Int?
    /// Whether the truck has any maintenance reminders at all.
    var hasReminders: Bool?
}
