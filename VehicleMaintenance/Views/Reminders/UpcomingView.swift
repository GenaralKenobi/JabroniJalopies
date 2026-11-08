import SwiftData
import SwiftUI

/// Every reminder across all vehicles, grouped by urgency.
struct UpcomingView: View {
    @Query private var reminders: [MaintenanceReminder]

    private var sortedReminders: [MaintenanceReminder] {
        reminders
            .filter { $0.vehicle != nil }
            .sorted(by: MaintenanceReminder.urgencyOrder)
    }

    var body: some View {
        NavigationStack {
            let all = sortedReminders
            Group {
                if all.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("Add maintenance reminders to a vehicle to see what's coming up.")
                    )
                } else {
                    List {
                        ForEach(DueStatus.allCases.reversed(), id: \.self) { status in
                            let items = all.filter { $0.status == status }
                            if !items.isEmpty {
                                Section(status.sectionTitle) {
                                    ForEach(items) { reminder in
                                        if let vehicle = reminder.vehicle {
                                            NavigationLink(value: vehicle) {
                                                ReminderRow(reminder: reminder, showsVehicle: true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: Vehicle.self) { vehicle in
                VehicleDetailView(vehicle: vehicle)
            }
        }
    }
}

#Preview {
    UpcomingView()
        .modelContainer(SampleData.previewContainer)
}
