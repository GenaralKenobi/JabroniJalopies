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

/// The daily "do your checklist" reminder. A manager sets the time for the whole
/// fleet; every member's phone schedules it locally (no server needed).
enum ChecklistReminder {
    static func identifier(_ fleetId: String) -> String { "checklist-\(fleetId)" }

    /// Parses "HH:mm" into hour and minute.
    static func parse(_ time: String?) -> (hour: Int, minute: Int)? {
        guard let parts = time?.split(separator: ":"), parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    static func format(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Schedules (or removes, when `time` is nil) this fleet's daily reminder.
    static func sync(fleetId: String, fleetName: String, time: String?) {
        let center = UNUserNotificationCenter.current()
        let id = identifier(fleetId)
        guard let parsed = parse(time) else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }
        let hour = parsed.hour, minute = parsed.minute
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard await ReminderNotifications.requestAuthorization() else { return }
            }
            let content = UNMutableNotificationContent()
            content.title = "Vehicle checklist"
            content.body = "Complete today's checklist before heading out (\(fleetName))."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            // Same identifier replaces any earlier schedule.
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel(fleetId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(fleetId)])
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
