import SwiftUI

/// Fleet-list badge: scheduled checklists and repeating items overdue on a truck.
struct OverdueBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar.badge.exclamationmark")
            Text(count == 1 ? "1 overdue" : "\(count) overdue")
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color.orange)
        .background(Color.orange.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Truck-page banner listing what's overdue, so whoever is on the truck gets it done.
struct OverdueBanner: View {
    let scheduled: [ScheduledDue]
    let items: [ChecklistItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Overdue on This Truck", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            ForEach(scheduled) { entry in
                Text("• \(entry.checklist.name), due \(entry.dueReading == nil ? "" : "at ")\(ScheduledChecklists.dueDescription(entry))")
            }
            ForEach(items) { item in
                Text("• \(item.title), skipped on \(ScheduledChecklists.skipLimit)+ checklists in a row")
            }
            Text("Please get these done. Start the checklist below.")
                .font(.caption)
        }
        .font(.subheadline)
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Managers pick the day a scheduled checklist will be done on a truck.
struct PlanChecklistView: View {
    let entry: ScheduledDue
    let vehicleName: String

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @AppStorage("addPlansToCalendar") private var addToCalendar = true
    @State private var showingCalendar = false

    init(entry: ScheduledDue, vehicleName: String) {
        self.entry = entry
        self.vehicleName = vehicleName
        let start = Calendar.current.startOfDay(for: .now)
        let weekAway = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        _date = State(initialValue: entry.plannedFor ?? max(start, min(entry.due ?? weekAway, weekAway)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Truck", value: vehicleName)
                    LabeledContent("Due", value: entry.dueReading == nil
                                   ? ScheduledChecklists.dueDescription(entry)
                                   : "At \(ScheduledChecklists.dueDescription(entry)) (now \(Formatting.distance(entry.currentReading, unit: entry.unit)))")
                    DatePicker("Planned for", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                } footer: {
                    if let due = entry.due {
                        Text(date > due
                             ? "That's after the due date, so drivers will see it marked Overdue from \(ScheduledChecklists.shortDate(due))."
                             : "Drivers see it marked Overdue only if it isn't done by the due date.")
                    } else {
                        Text("It's due by the vehicle's reading, not the date. Drivers see it marked Overdue once the reading passes \(ScheduledChecklists.dueDescription(entry)), even if you planned a later day.")
                    }
                }
                Section {
                    Toggle(isOn: $addToCalendar) {
                        Label("Add to My Calendar", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text(entry.plannedFor == nil
                         ? "After saving, you can add it to any calendar on this phone."
                         : "Changing the day doesn't move an event you added before; change or delete it in your calendar.")
                }
                if entry.plannedFor != nil {
                    Section {
                        Button("Remove Planned Day", role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle(entry.checklist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(date) } }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingCalendar) {
            CalendarEventEditor(
                title: "\(entry.checklist.name) — \(vehicleName)",
                date: date,
                notes: "Scheduled checklist for \(vehicleName), due \(entry.dueReading == nil ? "" : "at ")\(ScheduledChecklists.dueDescription(entry)). Planned in Jabroni Jalopies."
            ) { _ in
                showingCalendar = false
                dismiss()
            }
            .ignoresSafeArea()
        }
    }

    private func save(_ date: Date?) {
        do {
            try fleet.plan(entry, on: date)
            if date != nil, addToCalendar {
                showingCalendar = true
            } else {
                dismiss()
            }
        } catch {
            ErrorCenter.shared.report(error, "Planning \(entry.checklist.name)")
        }
    }
}

/// One scheduled checklist on one truck, for the truck page and the Upcoming tab.
struct ScheduledChecklistRow: View {
    let entry: ScheduledDue
    var vehicleName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let vehicleName {
                Text(vehicleName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(entry.checklist.name + (ScheduledChecklists.label(for: entry.checklist, unit: entry.dueReading == nil ? nil : entry.unit).map { " · " + $0 } ?? ""))
                .foregroundStyle(Color.primary)
            Label(ScheduledChecklists.statusText(entry), systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch entry.status {
        case .overdue: "exclamationmark.triangle.fill"
        case .dueSoon: entry.plannedFor == nil ? "calendar.badge.clock" : "calendar.badge.checkmark"
        case .later: entry.plannedFor == nil ? "calendar" : "calendar.badge.checkmark"
        }
    }

    private var color: Color {
        switch entry.status {
        case .overdue: .orange
        case .dueSoon: entry.plannedFor == nil ? .orange : .secondary
        case .later: .secondary
        }
    }
}
