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

/// The "do your checklist" reminder. A manager sets the time and the days of the
/// week for the whole fleet; every member's phone schedules it locally (no server).
enum ChecklistReminder {
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    static let weekdays = Array(1...7)
    static let defaultDays = [2, 3, 4, 5, 6]  // Monday–Friday

    /// One repeating notification per selected weekday.
    static func identifier(_ fleetId: String, weekday: Int) -> String { "checklist-\(fleetId)-\(weekday)" }

    static func allIdentifiers(_ fleetId: String) -> [String] {
        ["checklist-\(fleetId)"] + weekdays.map { identifier(fleetId, weekday: $0) }
    }

    /// Short day names in the order of the phone's calendar (e.g. starting Sunday in the US).
    static var orderedDays: [(weekday: Int, symbol: String)] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday
        return (0..<7).map { offset in
            let weekday = (first - 1 + offset) % 7 + 1
            return (weekday, symbols[weekday - 1])
        }
    }

    /// "Weekdays", "Every day", "Weekends" or e.g. "Mon, Wed, Fri".
    static func describe(_ days: [Int]?) -> String {
        let set = Set(days ?? weekdays)
        if set.count == 7 { return "Every day" }
        if set == Set(defaultDays) { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        let names = Calendar.current.shortWeekdaySymbols
        return orderedDays.map(\.weekday).filter(set.contains).map { names[$0 - 1] }.joined(separator: ", ")
    }

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

    /// Schedules this fleet's reminder on the selected days (`days` nil = every day),
    /// or removes it when `time` is nil or no days are selected.
    static func sync(fleetId: String, fleetName: String, time: String?, days: [Int]?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers(fleetId))
        let selected = Set(days ?? weekdays).intersection(weekdays)
        guard let parsed = parse(time), !selected.isEmpty else { return }
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard await ReminderNotifications.requestAuthorization() else { return }
            }
            let content = UNMutableNotificationContent()
            content.title = "Vehicle checklist"
            content.body = "Complete today's checklist before heading out (\(fleetName))."
            content.sound = .default
            for weekday in selected {
                let components = DateComponents(hour: parsed.hour, minute: parsed.minute, weekday: weekday)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                try? await center.add(UNNotificationRequest(identifier: identifier(fleetId, weekday: weekday),
                                                            content: content, trigger: trigger))
            }
        }
    }

    static func cancel(fleetId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allIdentifiers(fleetId))
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

/// Managers' alerts for scheduled checklists coming due and for repeating items
/// skipped too often. Each alert is sent once (per due date, or per skipping streak).
enum ScheduleAlerts {
    struct Alert {
        var id: String
        var title: String
        var body: String
        /// When to alert. nil, or a time already passed, means now (if not sent before).
        var fireAt: Date?
        /// Identifies this occurrence, so the same alert isn't sent twice.
        var onceKey: String
    }

    static func sync(fleetId: String, alerts: [Alert], now: Date = .now) {
        let prefix = "schedule-\(fleetId)-"
        let sentKey = "scheduleAlertsSent-\(fleetId)"
        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
        let center = UNUserNotificationCenter.current()

        var requests: [UNNotificationRequest] = []
        for alert in alerts where !sent.contains(alert.onceKey) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            var trigger: UNNotificationTrigger?
            if let fireAt = alert.fireAt, fireAt > now {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: fireAt)
                components.hour = ReminderNotifications.notificationHour
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            requests.append(UNNotificationRequest(identifier: prefix + alert.id, content: content, trigger: trigger))
            sent.insert(alert.onceKey)
        }

        // Forget occurrences that no longer apply (done, re-planned, or no longer skipped),
        // so a new due date or a new skipping streak alerts again.
        let current = Set(alerts.map(\.onceKey))
        defaults.set(Array(sent.intersection(current)), forKey: sentKey)

        let wanted = Set(alerts.map { prefix + $0.id })
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            requests.forEach { center.add($0) }
        }
    }
}
