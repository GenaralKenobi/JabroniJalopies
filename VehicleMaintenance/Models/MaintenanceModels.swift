import FirebaseFirestore
import Foundation

/// fleets/{f}/vehicles/{v}/reminders/{id} — a recurring maintenance item.
struct Reminder: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var serviceType: ServiceType
    var title: String
    var intervalDistance: Int?
    var intervalMonths: Int?
    var lastServiceDate: Date
    var lastServiceOdometer: Int
    var notificationsEnabled: Bool
}

extension Reminder {
    var displayTitle: String { title.isEmpty ? serviceType.displayName : title }

    var nextDueDate: Date? {
        DueCalculator().nextDueDate(lastDate: lastServiceDate, intervalMonths: intervalMonths)
    }

    var nextDueOdometer: Int? {
        DueCalculator().nextDueOdometer(lastOdometer: lastServiceOdometer, intervalDistance: intervalDistance)
    }

    func status(currentOdometer: Int, now: Date = .now) -> DueStatus {
        DueCalculator().status(nextDueDate: nextDueDate, nextDueOdometer: nextDueOdometer,
                               currentOdometer: currentOdometer, now: now)
    }

    /// Whether a logged service of the given type/title should reset this reminder.
    func matches(serviceType type: ServiceType, title otherTitle: String) -> Bool {
        guard type == serviceType else { return false }
        if type == .other {
            return title.localizedCaseInsensitiveCompare(otherTitle) == .orderedSame
        }
        return true
    }
}

enum ServiceStatus: String, Codable {
    /// Logged by a driver and waiting for a manager to sign off.
    case pending
    case approved
    case rejected
}

/// fleets/{f}/vehicles/{v}/services/{id}
struct ServiceRecord: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var date: Date
    var odometer: Int
    var serviceType: ServiceType
    var title: String
    var shop: String
    var notes: String
    var status: ServiceStatus
    var createdBy: String
    var createdByName: String
    @ServerTimestamp var createdAt: Date?
    var reviewedBy: String?
    var reviewedByName: String?
    var reviewedAt: Date?
    var reviewNote: String?
    var expireAt: Date?
}

extension ServiceRecord {
    var displayTitle: String { title.isEmpty ? serviceType.displayName : title }
}

/// fleets/{f}/vehicles/{v}/costs/{serviceId} — kept separate so only managers can read it.
struct ServiceCost: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var amount: Double
    var expireAt: Date?
}
