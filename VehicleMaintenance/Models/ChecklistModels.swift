import FirebaseFirestore
import Foundation

/// fleets/{f}/checklists/{id} — a checklist template built by a manager.
struct ChecklistTemplate: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String
    var items: [ChecklistItem]
    /// Vehicles this checklist applies to. Empty means every vehicle.
    var vehicleIds: [String]
    var updatedAt: Date?
    /// Set for a scheduled checklist that each truck needs monthly or every N days
    /// (e.g. "Monthly Service"). nil for everyday checklists.
    var schedule: ItemFrequency? = nil
    /// When a scheduled checklist is first due on trucks that haven't done it yet.
    var firstDue: Date? = nil
    /// Set for a checklist due every N hours (or miles / km, in each vehicle's own unit) of
    /// the vehicle's reading, e.g. a 250-hour service. Used instead of `schedule`.
    var readingInterval: Int? = nil

    var isScheduled: Bool { schedule != nil || readingInterval != nil }

    func applies(to vehicleId: String) -> Bool {
        vehicleIds.isEmpty || vehicleIds.contains(vehicleId)
    }
}

struct ChecklistItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// Ask for a number with this item, e.g. a tire pressure.
    var requiresReading: Bool
    /// Unit or label for the number, e.g. "PSI".
    var readingLabel: String
    /// A failure means the vehicle should not be driven.
    var unsafeIfFailed: Bool
    /// How often the item needs doing. `nil` means on every checklist.
    var frequency: ItemFrequency? = nil

    static func new(_ title: String = "", reading: String? = nil, unsafe: Bool = false,
                    frequency: ItemFrequency? = nil) -> ChecklistItem {
        ChecklistItem(id: UUID().uuidString, title: title, requiresReading: reading != nil,
                      readingLabel: reading ?? "", unsafeIfFailed: unsafe, frequency: frequency)
    }
}

/// A checklist item that only needs doing every so often on each truck.
struct ItemFrequency: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case weekly, monthly, days
    }

    var kind: Kind
    /// For `.days`: the interval in days.
    var days: Int?

    static let weekly = ItemFrequency(kind: .weekly)
    static let monthly = ItemFrequency(kind: .monthly)
    static func every(_ days: Int) -> ItemFrequency { ItemFrequency(kind: .days, days: max(1, days)) }

    var label: String {
        switch kind {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .days: (days ?? 1) == 1 ? "Daily" : "Every \(days ?? 1) days"
        }
    }
}

/// fleets/{f}/vehicles/{v}/checklistState/periodic — repeating-item and scheduled-checklist state for one truck.
struct ChecklistState: Codable, Hashable {
    /// When each repeating item (by item id) was last done on this truck.
    var lastDone: [String: Date]
    /// When each scheduled checklist (by checklist id) was last done on this truck.
    var checklistLastDone: [String: Date]
    /// The vehicle's reading when each scheduled checklist was last done (for hour / mile based ones).
    var checklistLastReading: [String: Int]
    /// How many checklists in a row skipped each due repeating item (by item id). Reset when it's done.
    var skips: [String: Int]

    init(lastDone: [String: Date] = [:], checklistLastDone: [String: Date] = [:],
         checklistLastReading: [String: Int] = [:], skips: [String: Int] = [:]) {
        self.lastDone = lastDone
        self.checklistLastDone = checklistLastDone
        self.checklistLastReading = checklistLastReading
        self.skips = skips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastDone = try container.decodeIfPresent([String: Date].self, forKey: .lastDone) ?? [:]
        checklistLastDone = try container.decodeIfPresent([String: Date].self, forKey: .checklistLastDone) ?? [:]
        checklistLastReading = try container.decodeIfPresent([String: Int].self, forKey: .checklistLastReading) ?? [:]
        skips = try container.decodeIfPresent([String: Int].self, forKey: .skips) ?? [:]
    }
}

/// fleets/{f}/vehicles/{v}/inspections/{id} — a completed checklist. Never edited.
struct Inspection: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var checklistId: String
    var checklistName: String
    var performedBy: String
    var performedByName: String
    /// When the driver finished, by the phone's clock (may be well before it synced).
    var completedAt: Date
    /// When the server received it.
    @ServerTimestamp var receivedAt: Date?
    var odometer: Int?
    var results: [InspectionResult]
    var failedCount: Int
    var unsafe: Bool
    var expireAt: Date
}

struct InspectionResult: Codable, Hashable {
    var itemId: String
    var title: String
    var passed: Bool
    var reading: Double?
    var readingLabel: String?
    var note: String?
    /// The defect this result created or confirmed.
    var defectId: String?
}

enum DefectStatus: String, Codable {
    case open
    /// A driver says it looks fixed; a manager still needs to close it.
    case reportedFixed
    case closed

    var label: String {
        switch self {
        case .open: "Open"
        case .reportedFixed: "Reported fixed"
        case .closed: "Closed"
        }
    }
}

enum DefectResolution: String, Codable {
    case repaired
    case notDefect

    var label: String {
        switch self {
        case .repaired: "Repaired"
        case .notDefect: "Not a defect"
        }
    }
}

enum DefectEventType: String, Codable {
    case reported, confirmed, reportedFixed, repaired, notDefect, reopened, photoAdded

    var label: String {
        switch self {
        case .reported: "Reported"
        case .confirmed: "Confirmed still a problem"
        case .reportedFixed: "Reported fixed"
        case .repaired: "Marked repaired"
        case .notDefect: "Marked not a defect"
        case .reopened: "Reopened"
        case .photoAdded: "Added a photo"
        }
    }

    var symbolName: String {
        switch self {
        case .reported: "exclamationmark.bubble"
        case .confirmed: "exclamationmark.2"
        case .reportedFixed: "hand.thumbsup"
        case .repaired: "checkmark.seal.fill"
        case .notDefect: "xmark.seal"
        case .reopened: "arrow.uturn.backward"
        case .photoAdded: "camera"
        }
    }
}

struct DefectEvent: Codable, Hashable {
    var type: DefectEventType
    var by: String
    var byName: String
    var at: Date
    var note: String?
}

enum DefectPhotoStatus: String, Codable {
    /// Taken, waiting on the phone that took it to upload.
    case pending
    case uploaded
}

struct DefectPhoto: Codable, Hashable {
    var status: DefectPhotoStatus
    var path: String?
    var addedBy: String
    var addedByName: String
    var addedAt: Date
    var byteCount: Int?
}

/// fleets/{f}/vehicles/{v}/defects/{id} — a problem found on a vehicle.
struct Defect: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var itemId: String?
    var title: String
    var details: String
    var unsafe: Bool
    var status: DefectStatus
    var resolution: DefectResolution?
    var reportedBy: String
    var reportedByName: String
    var reportedAt: Date
    @ServerTimestamp var receivedAt: Date?
    var inspectionId: String?
    var closedAt: Date?
    var closedBy: String?
    var closedByName: String?
    var history: [DefectEvent]
    /// Keyed by photo id.
    var photos: [String: DefectPhoto]
    /// Set when closed; Firestore's TTL policy deletes the record after this date.
    var expireAt: Date?
    var updatedAt: Date?
}

extension Defect {
    var isOpen: Bool { status != .closed }

    var sortedPhotos: [(id: String, photo: DefectPhoto)] {
        photos.map { (id: $0.key, photo: $0.value) }.sorted { $0.photo.addedAt < $1.photo.addedAt }
    }

    /// Pending photos older than this are probably never coming (lost phone, app deleted).
    func stalePhotoCount(now: Date = .now, after interval: TimeInterval = 24 * 3600) -> Int {
        photos.values.filter { $0.status == .pending && now.timeIntervalSince($0.addedAt) > interval }.count
    }
}
