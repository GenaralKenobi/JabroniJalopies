import SwiftUI

/// Quick-reference card for a vehicle's fluids, tires and pressures.
struct SpecsView: View {
    let vehicleId: String

    @Environment(FleetModel.self) private var fleet
    @State private var editing = false

    var body: some View {
        let vehicle = fleet.vehicle(vehicleId)
        let sections = vehicle.map { SpecDefaults.filled($0.specSections) } ?? []

        Group {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No Specs Yet", systemImage: "list.bullet.rectangle.portrait")
                } description: {
                    Text(fleet.isManager
                         ? "Add oil type, tire size, pressures and more so drivers can look them up quickly."
                         : "A manager hasn't filled in this vehicle's specs yet.")
                } actions: {
                    if fleet.isManager {
                        Button("Add Specs") { editing = true }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.rows) { row in
                                SpecRowView(row: row)
                            }
                        }
                    }
                    if fleet.isManager, let vehicle {
                        let missing = SpecDefaults.emptyRowCount(vehicle.specSections)
                        if missing > 0 {
                            Section {
                                Button("\(missing) field\(missing == 1 ? "" : "s") not filled in") { editing = true }
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Specs — \(vehicle?.displayName ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if fleet.isManager {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let vehicle {
                SpecsEditorView(vehicleId: vehicleId, sections: vehicle.specSections)
            }
        }
    }
}

private struct SpecRowView: View {
    let row: SpecRow

    var body: some View {
        // Pressures and torque get extra emphasis — they're what drivers look up roadside.
        let emphasized = ["pressure", "psi", "torque"].contains { row.label.localizedCaseInsensitiveContains($0) }
        HStack(alignment: .firstTextBaseline) {
            Text(row.label)
                .foregroundStyle(Color.secondary)
            Spacer(minLength: 12)
            Text(row.value)
                .font(emphasized ? .title3.weight(.bold).monospacedDigit() : .body.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Managers edit values and can add, rename, remove and reorder fields and sections.
struct SpecsEditorView: View {
    let vehicleId: String

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var sections: [SpecSection]
    @State private var errorMessage: String?

    init(vehicleId: String, sections: [SpecSection]) {
        self.vehicleId = vehicleId
        _sections = State(initialValue: sections.isEmpty ? SpecDefaults.sections() : sections)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($sections) { $section in
                    Section {
                        ForEach($section.rows) { $row in
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Field name", text: $row.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                                TextField("Value", text: $row.value)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { section.rows.remove(atOffsets: $0) }
                        .onMove { section.rows.move(fromOffsets: $0, toOffset: $1) }

                        Button {
                            section.rows.append(SpecRow(id: UUID().uuidString, label: "", value: ""))
                        } label: {
                            Label("Add Field", systemImage: "plus")
                        }
                    } header: {
                        HStack {
                            TextField("Section name", text: $section.title)
                                .font(.headline)
                                .textCase(nil)
                            Spacer()
                            Button(role: .destructive) {
                                sections.removeAll { $0.id == section.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete section")
                        }
                    }
                }

                Section {
                    Button {
                        sections.append(SpecSection(id: UUID().uuidString, title: "New Section",
                                                    rows: [SpecRow(id: UUID().uuidString, label: "", value: "")]))
                    } label: {
                        Label("Add Section", systemImage: "rectangle.stack.badge.plus")
                    }
                } footer: {
                    Text("Empty fields are hidden from drivers. Swipe left on a field to delete it.")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Specs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private func save() {
        let cleaned = sections.map { section in
            SpecSection(id: section.id, title: section.title.trimmed.isEmpty ? "Other" : section.title.trimmed,
                        rows: section.rows
                            .map { SpecRow(id: $0.id, label: $0.label.trimmed, value: $0.value.trimmed) }
                            .filter { !$0.label.isEmpty || !$0.value.isEmpty })
        }
        do {
            try fleet.updateSpecs(of: vehicleId, to: cleaned)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
