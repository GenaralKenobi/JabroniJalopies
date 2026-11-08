import Foundation
import UserNotifications

/// Local notifications on the morning a time-based reminder comes due
/// (managers' devices). Distance-based reminders show as badges in the app.
enum ReminderNotifications {
    static let notificationHour = 9

    struct Entry {
        var id: String
        var vehicleName: String
        var reminder: Reminder
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Replaces this fleet's scheduled reminder notifications with `entries`.
    static func sync(_ entries: [Entry], prefix: String) {
        let center = UNUserNotificationCenter.current()
        let fullPrefix = "reminder-\(prefix)-"
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(fullPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for entry in entries {
                let reminder = entry.reminder
                guard reminder.notificationsEnabled, let dueDate = reminder.nextDueDate, dueDate > .now else { continue }
                var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
                components.hour = notificationHour
                let content = UNMutableNotificationContent()
                content.title = "\(reminder.displayTitle) due"
                content.body = "\(entry.vehicleName) is due for: \(reminder.displayTitle)."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(identifier: "reminder-\(entry.id)", content: content, trigger: trigger))
            }
        }
    }
}

/// Warns managers when the fleet is approaching Firebase's free storage allowance.
enum UsageAlerts {
    static func check(_ report: UsageReport, fleetId: String, fleetName: String) {
        let key = "usageAlertLevel-\(fleetId)"
        let lastLevel = UserDefaults.standard.integer(forKey: key)
        guard report.level.rawValue > lastLevel else {
            if report.level.rawValue < lastLevel {
                UserDefaults.standard.set(report.level.rawValue, forKey: key)
            }
            return
        }
        UserDefaults.standard.set(report.level.rawValue, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "\(fleetName): storage \(report.level == .critical ? "almost full" : "getting full")"
        content.body = report.summary + " Open Settings → Data & Storage to review."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "usage-\(fleetId)", content: content, trigger: nil))
    }
}
