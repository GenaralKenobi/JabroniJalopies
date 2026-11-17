import SwiftUI

/// A maintenance reminder someone wants to put in their own calendar.
struct ReminderCalendarItem: Identifiable {
    let reminder: Reminder
    let vehicle: Vehicle
    var id: String { "\(vehicle.id ?? "")/\(reminder.id ?? reminder.displayTitle)" }

    /// The due date, or a week from today for reminders due only by reading
    /// (the person can change the day on the calendar screen).
    var eventDate: Date {
        if let due = reminder.nextDueDate { return max(due, Calendar.current.startOfDay(for: .now)) }
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
    }

    var title: String { "\(reminder.displayTitle) — \(vehicle.displayName)" }

    var notes: String {
        var due: [String] = []
        if let date = reminder.nextDueDate { due.append(Formatting.shortDate(date)) }
        if let reading = reminder.nextDueOdometer {
            due.append("at \(Formatting.distance(reading, unit: vehicle.unit)) (now \(Formatting.distance(vehicle.odometer, unit: vehicle.unit)))")
        }
        let when = due.isEmpty ? "" : " Due \(due.joined(separator: " or ")), whichever comes first."
        return "Maintenance for \(vehicle.displayName).\(when) From Jabroni Jalopies."
    }
}

extension View {
    /// Swipe left or long-press a reminder row to add it to a calendar.
    func addToCalendarActions(_ item: ReminderCalendarItem, selection: Binding<ReminderCalendarItem?>) -> some View {
        self
            .swipeActions(edge: .trailing) {
                Button { selection.wrappedValue = item } label: {
                    Label("Calendar", systemImage: "calendar.badge.plus")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button { selection.wrappedValue = item } label: {
                    Label("Add to My Calendar", systemImage: "calendar.badge.plus")
                }
            }
    }

    /// Shows the system New Event screen for the chosen reminder.
    func reminderCalendarSheet(_ selection: Binding<ReminderCalendarItem?>) -> some View {
        sheet(item: selection) { item in
            CalendarEventEditor(title: item.title, date: item.eventDate, notes: item.notes) { _ in
                selection.wrappedValue = nil
            }
            .ignoresSafeArea()
        }
    }
}
