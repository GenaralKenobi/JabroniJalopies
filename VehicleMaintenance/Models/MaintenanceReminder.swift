import Foundation
import SwiftData

/// A recurring maintenance item, due every N distance units and/or N months —
/// whichever comes first.
@Model
final class MaintenanceReminder {
    var serviceTypeRaw: String = ServiceType.other.rawValue
    var title: String = ""
    var intervalDistance: Int?
    var intervalMonths: Int?
    var lastServiceDate: Date = Date.now
    var lastServiceOdometer: Int = 0
    var notificationsEnabled: Bool = true
    /// Identifier of the pending local notification for this reminder.
    var notificationID: String = UUID().uuidString
    var vehicle: Vehicle?

    init(
        serviceType: ServiceType = .other,
        title: String = "",
        intervalDistance: Int? = nil,
        intervalMonths: Int? = nil,
        lastServiceDate: Date = .now,
        lastServiceOdometer: Int = 0,
        notificationsEnabled: Bool = true
    ) {
        self.serviceTypeRaw = serviceType.rawValue
        self.title = title
        self.intervalDistance = intervalDistance
        self.intervalMonths = intervalMonths
        self.lastServiceDate = lastServiceDate
        self.lastServiceOdometer = lastServiceOdometer
        self.notificationsEnabled = notificationsEnabled
        self.notificationID = UUID().uuidString
    }
}

extension MaintenanceReminder {
    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .other }
        set { serviceTypeRaw = newValue.rawValue }
    }

    var displayTitle: String {
        title.isEmpty ? serviceType.displayName : title
    }

    var nextDueDate: Date? {
        DueCalculator().nextDueDate(lastDate: lastServiceDate, intervalMonths: intervalMonths)
    }

    var nextDueOdometer: Int? {
        DueCalculator().nextDueOdometer(lastOdometer: lastServiceOdometer, intervalDistance: intervalDistance)
    }

    var status: DueStatus {
        DueCalculator().status(
            nextDueDate: nextDueDate,
            nextDueOdometer: nextDueOdometer,
            currentOdometer: vehicle?.odometer ?? lastServiceOdometer
        )
    }

    /// Whether a logged service of the given type/title should reset this reminder.
    func matches(serviceType type: ServiceType, title otherTitle: String) -> Bool {
        guard type == serviceType else { return false }
        if type == .other {
            return title.localizedCaseInsensitiveCompare(otherTitle) == .orderedSame
        }
        return true
    }

    /// Most urgent first, then soonest due date.
    static func urgencyOrder(_ a: MaintenanceReminder, _ b: MaintenanceReminder) -> Bool {
        let statusA = a.status, statusB = b.status
        if statusA != statusB { return statusA > statusB }
        return (a.nextDueDate ?? .distantFuture) < (b.nextDueDate ?? .distantFuture)
    }
}
