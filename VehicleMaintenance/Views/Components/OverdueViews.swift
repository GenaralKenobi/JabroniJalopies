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
                Text("• \(entry.checklist.name) — \(ScheduledChecklists.statusText(entry).lowercased())")
            }
            ForEach(items) { item in
                Text("• \(item.title) — skipped on the last \(ScheduledChecklists.skipLimit)+ checklists")
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

    init(entry: ScheduledDue, vehicleName: String) {
        self.entry = entry
        self.vehicleName = vehicleName
        let start = Calendar.current.startOfDay(for: .now)
        _date = State(initialValue: entry.plannedFor ?? max(start, min(entry.due, Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Truck", value: vehicleName)
                    LabeledContent("Due", value: entry.due.formatted(date: .abbreviated, time: .omitted))
                    DatePicker("Planned for", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                } footer: {
                    Text(date > entry.due
                         ? "That's after the due date, so drivers will see it marked Overdue from \(entry.due.formatted(date: .abbreviated, time: .omitted))."
                         : "Drivers see it marked Overdue only if it isn't done by the due date.")
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
    }

    private func save(_ date: Date?) {
        do {
            try fleet.plan(entry, on: date)
            dismiss()
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
            HStack(alignment: .firstTextBaseline) {
                Text(vehicleName.map { "\($0) · \(entry.checklist.name)" } ?? entry.checklist.name)
                    .foregroundStyle(Color.primary)
                Spacer()
                if let schedule = entry.checklist.schedule {
                    Text(ScheduledChecklists.scheduleLabel(schedule))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Color.brand)
                        .background(Color.brand.opacity(0.12), in: Capsule())
                }
            }
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
