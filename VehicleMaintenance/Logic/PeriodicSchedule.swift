import Foundation

/// When repeating checklist items (weekly, monthly, every N days) are due.
/// - Weekly and monthly items follow the calendar: once done, they're done for the rest of
///   that week (Monday to Sunday) or calendar month, and become due again when the next
///   week or month starts, however late in the old one they were done.
/// - "Every N days" items count from the day they were last done on that truck.
enum PeriodicSchedule {
    /// Weeks start on Monday, whatever the phone's region uses, so everyone in the fleet agrees.
    static let firstWeekday = 2

    static func nextDue(_ frequency: ItemFrequency, lastDone: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastDone else { return nil }
        switch frequency.kind {
        case .weekly:
            var weekCalendar = calendar
            weekCalendar.firstWeekday = firstWeekday
            weekCalendar.minimumDaysInFirstWeek = 1
            return weekCalendar.dateInterval(of: .weekOfYear, for: lastDone)?.end
        case .monthly:
            return calendar.dateInterval(of: .month, for: lastDone)?.end
        case .days:
            let start = calendar.startOfDay(for: lastDone)
            return calendar.date(byAdding: .day, value: max(1, frequency.days ?? 1), to: start)
        }
    }

    /// Items without a frequency, and repeating items never done on this truck, are always due.
    static func isDue(_ frequency: ItemFrequency?, lastDone: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let frequency else { return true }
        guard let next = nextDue(frequency, lastDone: lastDone, calendar: calendar) else { return true }
        return now >= next
    }
}
