import SwiftUI

/// Managers' list of checklist templates.
struct ChecklistTemplatesView: View {
    @Environment(FleetModel.self) private var fleet
    @State private var editing: ChecklistTemplate?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(fleet.checklists) { checklist in
                    Button { editing = checklist } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(checklist.name).foregroundStyle(Color.primary)
                            Text(summary(checklist)).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
            } footer: {
                Text("Drivers pick a checklist from a vehicle's page. Each item is pass/fail, and can also ask for a number reading. Scheduled checklists (monthly or every N days) are due on each truck on their schedule.")
            }
            Section {
                Button { creating = true } label: { Label("New Checklist", systemImage: "plus") }
            }
        }
        .navigationTitle("Checklists")
        .sheet(item: $editing) { ChecklistEditorView(checklist: $0) }
        .sheet(isPresented: $creating) { ChecklistEditorView(checklist: nil) }
    }

    private func summary(_ checklist: ChecklistTemplate) -> String {
        let vehicles = checklist.vehicleIds.isEmpty ? "All vehicles" : "\(checklist.vehicleIds.count) vehicle\(checklist.vehicleIds.count == 1 ? "" : "s")"
        let safety = checklist.items.filter(\.unsafeIfFailed).count
        let repeating = checklist.items.filter { $0.frequency != nil }.count
        let schedule = checklist.schedule.map { ScheduledChecklists.scheduleLabel($0) + " · " } ?? ""
        return schedule + "\(checklist.items.count) items · \(safety) safety" + (repeating > 0 ? " · \(repeating) weekly" : "") + " · \(vehicles)"
    }
}

struct ChecklistEditorView: View {
    let original: ChecklistTemplate?

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChecklistTemplate
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(checklist: ChecklistTemplate?) {
        original = checklist
        _draft = State(initialValue: checklist ?? ChecklistTemplate(name: "", items: [.new()], vehicleIds: []))
    }

    private var isValid: Bool {
        !draft.name.trimmed.isEmpty && !draft.items.isEmpty && draft.items.allSatisfy { !$0.title.trimmed.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Checklist name (e.g. Morning Checklist)", text: $draft.name)
                }

                scheduleSection

                Section {
                    ForEach($draft.items) { $item in
                        ChecklistItemEditor(item: $item, showsRepeat: !draft.isScheduled)
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        draft.items.append(.new())
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                } header: {
                    Text("Items")
                } footer: {
                    if draft.isScheduled {
                        Text("Every item is pass/fail. Turn on \"Record a number\" to also ask for a reading. Safety items mark the vehicle unsafe to drive when they fail.")
                    } else {
                        Text("Every item is pass/fail. Turn on \"Record a number\" to also ask for a reading. Safety items mark the vehicle unsafe to drive when they fail. Weekly items appear once each week (Monday to Sunday) until they're done; drivers can skip one, and after \(ScheduledChecklists.skipLimit) skips in a row it's marked Overdue and managers are alerted. For monthly or every-N-days work, make a separate checklist and set its Schedule.")
                    }
                }

                Section {
                    Toggle("All Vehicles", isOn: Binding(
                        get: { draft.vehicleIds.isEmpty },
                        set: { all in draft.vehicleIds = all ? [] : fleet.sortedVehicles.compactMap(\.id) }
                    ))
                    if !draft.vehicleIds.isEmpty {
                        ForEach(fleet.sortedVehicles) { vehicle in
                            let id = vehicle.id ?? ""
                            let selected = draft.vehicleIds.contains(id)
                            Button {
                                if selected {
                                    draft.vehicleIds.removeAll { $0 == id }
                                    if draft.vehicleIds.isEmpty { draft.vehicleIds = [id] }
                                } else {
                                    draft.vehicleIds.append(id)
                                }
                            } label: {
                                HStack {
                                    Text(vehicle.displayName).foregroundStyle(Color.primary)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.brand : .secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Used For")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if original != nil {
                    Section {
                        Button("Delete Checklist", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Completed checklists stay in each vehicle's history.")
                    }
                }
            }
            .navigationTitle(original == nil ? "New Checklist" : "Edit Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .confirmationDialog("Delete this checklist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original { fleet.delete(original) }
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Picker("Schedule", selection: Binding(
                get: { ScheduleChoice(draft.schedule) },
                set: { choice in
                    draft.schedule = choice.frequency(days: draft.schedule?.days ?? 30)
                    if draft.schedule != nil, draft.firstDue == nil {
                        draft.firstDue = Calendar.current.date(byAdding: .day, value: ScheduledChecklists.alertLeadDays, to: .now)
                    }
                }
            )) {
                ForEach(ScheduleChoice.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if draft.schedule?.kind == .days {
                Stepper("Every \(draft.schedule?.days ?? 30) days",
                        value: Binding(get: { draft.schedule?.days ?? 30 }, set: { draft.schedule = .every($0) }),
                        in: 1...730)
            }
            if draft.isScheduled {
                DatePicker("First due", selection: Binding(
                    get: { draft.firstDue ?? .now },
                    set: { draft.firstDue = $0 }
                ), displayedComponents: .date)
            }
        } header: {
            Text("Schedule")
        } footer: {
            if let schedule = draft.schedule {
                Text("Each truck needs this checklist \(schedule.kind == .monthly ? "every month" : "every \(schedule.days ?? 1) days"), counted from when it was last done on that truck. Trucks that haven't done it yet are due on the first due date. Managers are alerted \(ScheduledChecklists.alertLeadDays) days before it's due and can plan a day for it. If it isn't done by the due date, drivers see it marked Overdue.")
            } else {
                Text("Drivers can do this checklist any time, such as every morning.")
            }
        }
    }

    private func save() {
        var checklist = draft
        checklist.name = checklist.name.trimmed
        if !checklist.isScheduled { checklist.firstDue = nil }
        checklist.items = checklist.items.map { item in
            var item = item
            if checklist.isScheduled { item.frequency = nil }
            item.title = item.title.trimmed
            item.readingLabel = item.requiresReading ? item.readingLabel.trimmed : ""
            return item
        }
        do {
            try fleet.save(checklist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChecklistItemEditor: View {
    @Binding var item: ChecklistItem
    var showsRepeat = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item (e.g. Brake lights)", text: $item.title)
                .font(.body.weight(.medium))
            Toggle("Record a number", isOn: $item.requiresReading)
                .font(.subheadline)
            if item.requiresReading {
                TextField("Unit (e.g. PSI, mi, %)", text: $item.readingLabel)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
            }
            if showsRepeat {
                Picker("Repeat", selection: Binding(
                    get: { RepeatChoice(item.frequency) },
                    set: { item.frequency = $0.frequency(days: item.frequency?.days ?? 14) }
                )) {
                    ForEach(RepeatChoice.options(current: item.frequency), id: \.self) { Text($0.label).tag($0) }
                }
                .font(.subheadline)
                if let kind = item.frequency?.kind, kind != .weekly {
                    Text("Monthly and every-N-days items now belong in a scheduled checklist. This item still works as before.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            if showsRepeat, item.frequency?.kind == .days {
                Stepper("Every \(item.frequency?.days ?? 14) days",
                        value: Binding(get: { item.frequency?.days ?? 14 },
                                       set: { item.frequency = .every($0) }),
                        in: 1...365)
                    .font(.subheadline)
            }
            Toggle(isOn: $item.unsafeIfFailed) {
                Label("Unsafe to drive if failed", systemImage: "exclamationmark.octagon")
                    .foregroundStyle(item.unsafeIfFailed ? Color.red : Color.primary)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

/// The Repeat options shown in the checklist editor.
private enum RepeatChoice: CaseIterable {
    case everyTime, weekly, monthly, days

    /// New items repeat every checklist or weekly. Older monthly / every-N-days items keep their option.
    static func options(current: ItemFrequency?) -> [RepeatChoice] {
        let choice = RepeatChoice(current)
        return [.everyTime, .weekly] + ([.monthly, .days].contains(choice) ? [choice] : [])
    }

    init(_ frequency: ItemFrequency?) {
        switch frequency?.kind {
        case nil: self = .everyTime
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .days: self = .days
        }
    }

    var label: String {
        switch self {
        case .everyTime: "Every checklist"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .days: "Every … days"
        }
    }

    func frequency(days: Int) -> ItemFrequency? {
        switch self {
        case .everyTime: nil
        case .weekly: .weekly
        case .monthly: .monthly
        case .days: .every(days)
        }
    }
}

/// The Schedule options for a whole checklist.
private enum ScheduleChoice: CaseIterable {
    case anyTime, monthly, days

    init(_ schedule: ItemFrequency?) {
        switch schedule?.kind {
        case nil: self = .anyTime
        case .monthly: self = .monthly
        case .days, .weekly: self = .days
        }
    }

    var label: String {
        switch self {
        case .anyTime: "Any time (e.g. every morning)"
        case .monthly: "Monthly"
        case .days: "Every … days"
        }
    }

    func frequency(days: Int) -> ItemFrequency? {
        switch self {
        case .anyTime: nil
        case .monthly: .monthly
        case .days: .every(days)
        }
    }
}
