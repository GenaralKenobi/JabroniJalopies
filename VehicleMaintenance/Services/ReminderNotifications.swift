import Foundation
import UserNotifications

/// Schedules a local notification on the morning a date-based reminder comes due.
/// Distance-based reminders can't be scheduled ahead of time; they surface in the
/// app as status badges when the odometer is updated.
enum ReminderNotifications {
    static let notificationHour = 9

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func schedule(for reminder: MaintenanceReminder) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])

        guard reminder.notificationsEnabled,
              let dueDate = reminder.nextDueDate,
              dueDate > .now else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        components.hour = notificationHour

        let content = UNMutableNotificationContent()
        let vehicleName = reminder.vehicle?.displayName ?? "Your vehicle"
        content.title = "\(reminder.displayTitle) due"
        content.body = "\(vehicleName) is due for: \(reminder.displayTitle)."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.notificationID, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel(for reminder: MaintenanceReminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
    }
}
