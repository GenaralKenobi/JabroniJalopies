import Foundation

/// When repeating checklist items (weekly, monthly, every N days) are due.
/// Intervals run from the day the item was last done on that truck.
enum PeriodicSchedule {
    static func nextDue(_ frequency: ItemFrequency, lastDone: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastDone else { return nil }
        let start = calendar.startOfDay(for: lastDone)
        switch frequency.kind {
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: start)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: start)
        case .days: return calendar.date(byAdding: .day, value: max(1, frequency.days ?? 1), to: start)
        }
    }

    /// Items without a frequency, and repeating items never done on this truck, are always due.
    static func isDue(_ frequency: ItemFrequency?, lastDone: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let frequency else { return true }
        guard let next = nextDue(frequency, lastDone: lastDone, calendar: calendar) else { return true }
        return now >= next
    }
}
