import FirebaseFirestore
import Foundation

enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case chainsaw
    case rope

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chainsaw: "Chainsaw"
        case .rope: "Rope"
        }
    }

    var pluralName: String {
        switch self {
        case .chainsaw: "Chainsaws"
        case .rope: "Ropes"
        }
    }

    var symbolName: String {
        switch self {
        case .chainsaw: "hammer.fill"
        case .rope: "lasso"
        }
    }

    /// What an unsafe defect means for this kind of equipment.
    var unsafeLabel: String { "Do not use" }
}

/// fleets/{f}/equipment/{id} — a chainsaw or rope. Managers can move it between trucks.
struct Equipment: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var type: EquipmentType
    /// Name or number, e.g. "Saw 4" or "Rigging rope A".
    var name: String
    /// The truck it's currently on.
    var vehicleId: String
    var make: String
    var model: String
    var serialNumber: String
    var notes: String
    /// Chainsaws: bar length in inches.
    var barLengthInches: Double?
    /// Ropes: e.g. "1/2 in".
    var diameter: String
    /// Ropes: current length in feet. Reductions need manager approval.
    var lengthFeet: Double?
    /// Ropes: warn when the rope is shorter than this.
    var minLengthFeet: Double?
    @ServerTimestamp var createdAt: Date?
    var movedAt: Date?

    static func new(_ type: EquipmentType, vehicleId: String) -> Equipment {
        Equipment(type: type, name: "", vehicleId: vehicleId, make: "", model: "", serialNumber: "", notes: "",
                  diameter: "")
    }
}

extension Equipment {
    var displayName: String { name.isEmpty ? type.displayName : name }

    var detailLine: String {
        switch type {
        case .chainsaw:
            return [[make, model].filter { !$0.isEmpty }.joined(separator: " "),
                    barLengthInches.map { "\(ChainSize.format($0)) bar" } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .rope:
            return [diameter, lengthFeet.map { "\(Formatting.feet($0))" } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    var isBelowMinimumLength: Bool {
        guard type == .rope, let length = lengthFeet, let minimum = minLengthFeet else { return false }
        return length < minimum
    }
}

enum ReviewStatus: String, Codable {
    case pending, approved, rejected
}

/// fleets/{f}/equipment/{ropeId}/lengthChanges/{id} — a requested rope length reduction.
struct LengthChange: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    /// Feet to remove (always positive).
    var amountFeet: Double
    var reason: String
    var status: ReviewStatus
    var submittedBy: String
    var submittedByName: String
    var submittedAt: Date
    var reviewedBy: String?
    var reviewedByName: String?
    var reviewedAt: Date?
    var expireAt: Date
}

/// A chain size carried on a truck, e.g. 18".
struct ChainSize: Codable, Identifiable, Hashable {
    /// Firestore-safe key, e.g. "in18" or "in18_5".
    var key: String
    var inches: Double

    var id: String { key }
    var label: String { Self.format(inches) }

    init(inches: Double) {
        self.inches = inches
        self.key = Self.key(for: inches)
    }

    static func key(for inches: Double) -> String {
        "in" + Self.number(inches).replacingOccurrences(of: ".", with: "_")
    }

    static func format(_ inches: Double) -> String { "\(number(inches))\"" }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// fleets/{f}/vehicles/{v}/chains/inventory — the truck's chain sizes and how many sharp chains it has.
struct ChainInventory: Codable, Hashable {
    var sizes: [ChainSize]
    /// Sharp chains on the truck, keyed by `ChainSize.key`. Logs change it by increments
    /// so offline logs from several people add up. It can go below zero, for example when
    /// chains were added on a phone that hasn't synced yet.
    var counts: [String: Int]
    var updatedAt: Date?
    /// When a manager last counted the chains on the truck. Logs made before this are
    /// not applied to the counts: the manager's count already includes them.
    var correctedAt: Date?
    var correctedByName: String?
    /// The time of the log that last changed the counts (checked by the security rules).
    var lastLoggedAt: Date?

    func count(_ size: ChainSize) -> Int { counts[size.key] ?? 0 }

    var sortedSizes: [ChainSize] { sizes.sorted { $0.inches < $1.inches } }

    var hasNegativeCount: Bool { sizes.contains { count($0) < 0 } }
}

enum ChainLogKind: String, Codable {
    /// End of day: dull chains (to resharpen) and thrown-away chains taken off the truck.
    case usedBox
    /// Chains put on the truck (new or back from sharpening).
    case added
    /// A manager setting the counts to match what's actually on the truck.
    case correction

    var label: String {
        switch self {
        case .usedBox: "Used chain box emptied"
        case .added: "Chains added"
        case .correction: "Chains counted by a manager"
        }
    }

    var symbolName: String {
        switch self {
        case .usedBox: "tray.and.arrow.up"
        case .added: "plus.circle"
        case .correction: "slider.horizontal.3"
        }
    }
}

struct ChainLogItem: Codable, Hashable {
    var sizeKey: String
    var inches: Double
    var dull: Int
    var discarded: Int
    var added: Int
    /// Corrections: the change from what the app showed.
    var adjustment: Int
    /// Corrections: how many the manager counted on the truck.
    var counted: Int? = nil

    var label: String { ChainSize.format(inches) }
    /// The net change this item made to the truck's count.
    var countChange: Int { added + adjustment - dull - discarded }
}

/// fleets/{f}/vehicles/{v}/chainLogs/{id}
struct ChainLog: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var kind: ChainLogKind
    var items: [ChainLogItem]
    var loggedBy: String
    var loggedByName: String
    var loggedAt: Date
    @ServerTimestamp var receivedAt: Date?
    var expireAt: Date

    var summary: String {
        items.compactMap { item -> String? in
            switch kind {
            case .usedBox:
                var parts: [String] = []
                if item.dull > 0 { parts.append("\(item.dull) dull") }
                if item.discarded > 0 { parts.append("\(item.discarded) thrown away") }
                return parts.isEmpty ? nil : "\(item.label): " + parts.joined(separator: ", ")
            case .added:
                return item.added > 0 ? "\(item.label): +\(item.added)" : nil
            case .correction:
                let change = item.adjustment == 0 ? "" : " (\(item.adjustment > 0 ? "+" : "")\(item.adjustment))"
                return item.counted.map { "\(item.label): \($0)\(change)" }
                    ?? (item.adjustment != 0 ? "\(item.label): \(item.adjustment > 0 ? "+" : "")\(item.adjustment)" : nil)
            }
        }
        .joined(separator: " · ")
    }
}

/// Where a defect lives: on a truck or on a piece of equipment.
enum DefectOwner: Hashable {
    case vehicle(String)
    case equipment(String)

    func defects(fleetId: String) -> CollectionReference {
        switch self {
        case .vehicle(let id): FS.defects(fleetId, id)
        case .equipment(let id): FS.equipmentDefects(fleetId, id)
        }
    }

    func photoPath(fleetId: String, defectId: String, photoId: String) -> String {
        switch self {
        case .vehicle(let id):
            "fleets/\(fleetId)/vehicles/\(id)/defects/\(defectId)/\(photoId).jpg"
        case .equipment(let id):
            "fleets/\(fleetId)/equipment/\(id)/defects/\(defectId)/\(photoId).jpg"
        }
    }
}
