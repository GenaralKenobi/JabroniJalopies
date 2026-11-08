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
                            Text(checklist.name).foregroundStyle(.primary)
                            Text(summary(checklist)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Drivers pick a checklist from a vehicle's page. Each item is pass/fail, and can also ask for a number reading.")
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
        return "\(checklist.items.count) items · \(safety) safety · \(vehicles)"
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

                Section {
                    ForEach($draft.items) { $item in
                        ChecklistItemEditor(item: $item)
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
                    Text("Every item is pass/fail. Turn on \"Record a number\" to also ask for a reading. Safety items mark the vehicle unsafe to drive when they fail.")
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
                                    Text(vehicle.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.accentColor : .secondary)
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

    private func save() {
        var checklist = draft
        checklist.name = checklist.name.trimmed
        checklist.items = checklist.items.map { item in
            var item = item
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
            Toggle(isOn: $item.unsafeIfFailed) {
                Label("Unsafe to drive if failed", systemImage: "exclamationmark.octagon")
                    .foregroundStyle(item.unsafeIfFailed ? Color.red : Color.primary)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
