import EventKit
import EventKitUI
import SwiftUI

/// The system "New Event" screen, filled in. The person picks the calendar and taps Add,
/// so the app never needs access to read their calendar.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let date: Date
    let notes: String
    let onFinish: (_ added: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: date)
        event.endDate = event.startDate
        event.notes = notes
        // A reminder at 7 AM on the day.
        event.addAlarm(EKAlarm(relativeOffset: 7 * 60 * 60))
        context.coordinator.store = store

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (Bool) -> Void
        var store: EKEventStore?

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action == .saved)
        }
    }
}
