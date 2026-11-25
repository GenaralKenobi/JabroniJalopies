import SwiftUI

/// What's kept on a truck, grouped by where it lives. Everyone who can see the truck
/// can look things up; managers and the truck's lead keep it up to date.
struct TruckContentsView: View {
    let vehicleId: String

    @Environment(FleetModel.self) private var fleet
    @State private var model: TruckContentsModel?
    @State private var search = ""
    @State private var editing: TruckItem?
    @State private var copying = false
    @State private var copyMessage: String?
    @State private var managingKits = false

    var body: some View {
        let vehicle = fleet.vehicle(vehicleId)
        let canEdit = fleet.canEditContents(of: vehicle)
        let items = model?.items ?? []
        let groups = TruckContents.grouped(items, matching: search)

        List {
            leadSection(vehicle, canEdit: canEdit)

            if let model, model.loaded, items.isEmpty {
                Section {
                    Text(canEdit
                         ? "Nothing listed yet. Add what's kept on this truck so everyone knows where to find it."
                         : "Nothing listed for this truck yet.")
                        .foregroundStyle(.secondary)
                    if canEdit {
                        Button { editing = .new() } label: { Label("Add First Item", systemImage: "plus") }
                    }
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item, canEdit: canEdit)
                    }
                    .onDelete(perform: canEdit ? deleteHandler(group) : nil)
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text("\(group.items.count)").monospacedDigit()
                    }
                }
            }

            if !search.trimmed.isEmpty, groups.isEmpty, !items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("On the Truck — \(vehicle?.displayName ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search this truck")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { editing = .new() } label: { Label("Add Item", systemImage: "plus") }
                        if !fleet.kits.isEmpty {
                            Menu {
                                ForEach(fleet.kits) { kit in
                                    Button(kit.name) {
                                        var item = TruckItem.new()
                                        item.name = kit.name
                                        item.parts = kit.parts.map { KitPart.new($0.name, quantity: $0.quantity) }
                                        editing = item
                                    }
                                }
                            } label: {
                                Label("Add from Kit", systemImage: "shippingbox")
                            }
                        }
                        if fleet.isManager && !fleet.kits.isEmpty {
                            Button { managingKits = true } label: { Label("Manage Kits", systemImage: "list.bullet") }
                        }
                        let others = fleet.sortedVehicles.filter { $0.id != vehicleId }
                        if !others.isEmpty {
                            Menu {
                                ForEach(others) { other in
                                    Button(other.displayName) { copy(from: other, existing: items) }
                                }
                            } label: {
                                Label("Copy from Another Truck", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    } primaryAction: {
                        editing = .new()
                    }
                    .disabled(copying)
                }
            }
        }
        .sheet(item: $editing) { item in
            TruckItemFormView(vehicleId: vehicleId, item: item, locations: TruckContents.locations(items))
        }
        .sheet(isPresented: $managingKits) { KitsView() }
        .alert("Copied", isPresented: Binding(get: { copyMessage != nil }, set: { if !$0 { copyMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copyMessage ?? "")
        }
        .task {
            if model == nil { model = TruckContentsModel(fleetId: fleet.fleetId, vehicleId: vehicleId) }
        }
    }

    @ViewBuilder
    private func leadSection(_ vehicle: Vehicle?, canEdit: Bool) -> some View {
        if fleet.isManager, let vehicle {
            Section {
                Picker(selection: Binding(
                    get: { fleet.truckLead(of: vehicle)?.id ?? "" },
                    set: { fleet.setTruckLead($0.isEmpty ? nil : $0, vehicle: vehicleId) }
                )) {
                    Text("None").tag("")
                    ForEach(fleet.leadOptions(for: vehicle)) { member in
                        Text(member.displayName).tag(member.id ?? "")
                    }
                } label: {
                    Label("Truck Lead", systemImage: "person.badge.key")
                }
            } footer: {
                Text("Managers and the truck lead can change this list. Everyone who can see \(vehicle.displayName) can look at it.")
            }
        } else if let leadName = fleet.truckLeadName(of: vehicle) {
            Section {
                LabeledContent {
                    Text(fleet.isTruckLead(of: vehicle) ? "You" : leadName)
                } label: {
                    Label("Truck Lead", systemImage: "person.badge.key")
                }
            } footer: {
                if canEdit {
                    Text("You're this truck's lead, so you can add, change and remove items.")
                }
            }
        }
    }

    private func deleteHandler(_ group: TruckContents.Group) -> (IndexSet) -> Void {
        { offsets in
            for index in offsets { fleet.delete(group.items[index], vehicle: vehicleId) }
        }
    }

    @ViewBuilder
    private func row(_ item: TruckItem, canEdit: Bool) -> some View {
        if canEdit {
            Button { editing = item } label: { rowContent(item) }
                .buttonStyle(.plain)
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: TruckItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(Color.primary)
                if let parts = TruckContents.partsText(item.parts) {
                    Label(parts, systemImage: "shippingbox")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if model?.unsyncedIds.contains(item.id ?? "") == true {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Not synced yet")
            }
            if let quantity = TruckContents.quantityText(item.quantity) {
                Text(quantity)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func copy(from other: Vehicle, existing: [TruckItem]) {
        guard let otherId = other.id else { return }
        copying = true
        Task {
            defer { copying = false }
            do {
                let added = try await fleet.copyContents(from: otherId, to: vehicleId, existing: existing)
                copyMessage = added == 0
                    ? "Everything listed on \(other.displayName) is already on this truck's list."
                    : "Added \(added) item\(added == 1 ? "" : "s") from \(other.displayName). Change counts or remove anything this truck doesn't carry."
            } catch {
                ErrorCenter.shared.report(error, "Copying from \(other.displayName)")
            }
        }
    }
}

/// Add or change one item on the truck.
struct TruckItemFormView: View {
    let vehicleId: String
    let locations: [String]

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var item: TruckItem
    @State private var quantityText: String
    @State private var addedCount = 0
    @State private var kitSaved = false
    @FocusState private var nameFocused: Bool
    private let isNew: Bool

    init(vehicleId: String, item: TruckItem, locations: [String]) {
        self.vehicleId = vehicleId
        self.locations = locations
        _item = State(initialValue: item)
        _quantityText = State(initialValue: item.quantity.map(String.init) ?? "")
        isNew = item.id == nil
    }

    private var isValid: Bool { !item.name.trimmed.isEmpty }

    private var partsBinding: Binding<[KitPart]> {
        Binding(get: { item.parts ?? [] }, set: { item.parts = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item, e.g. First-aid kit", text: $item.name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.sentences)
                    TextField("Quantity (optional)", text: $quantityText)
                        .keyboardType(.numberPad)
                }

                Section {
                    TextField("Location, e.g. Left side box", text: $item.location)
                        .textInputAutocapitalization(.words)
                    if !locations.isEmpty {
                        Menu {
                            ForEach(locations, id: \.self) { location in
                                Button(location) { item.location = location }
                            }
                        } label: {
                            Label("Choose a Location", systemImage: "mappin.and.ellipse")
                        }
                    }
                } header: {
                    Text("Where on the Truck")
                } footer: {
                    Text("Items are grouped by location. Leave it blank if it doesn't matter.")
                }

                Section("Notes") {
                    TextField("Optional", text: $item.notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    ForEach(item.parts ?? []) { part in
                        let binding = elementBinding(partsBinding, part)
                        HStack {
                            TextField("e.g. Gauze pads", text: binding.name)
                            TextField("Qty", text: Binding(
                                get: { binding.wrappedValue.quantity.map(String.init) ?? "" },
                                set: { binding.wrappedValue.quantity = NumberParsing.int($0) }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        }
                    }
                    .onDelete { item.parts?.remove(atOffsets: $0) }
                    Button {
                        item.parts = (item.parts ?? []) + [.new()]
                    } label: {
                        Label("Add Item Inside", systemImage: "plus")
                    }
                    if fleet.isManager, !(item.parts ?? []).isEmpty, !item.name.trimmed.isEmpty {
                        Button {
                            do {
                                try fleet.saveKit(name: item.name, parts: item.parts ?? [])
                                kitSaved = true
                            } catch {
                                ErrorCenter.shared.report(error, "Saving kit")
                            }
                        } label: {
                            Label(kitSaved ? "Saved as a Kit" : "Save as a Kit for Other Trucks", systemImage: "shippingbox")
                        }
                        .disabled(kitSaved)
                    }
                } header: {
                    Text("Inside This Item")
                } footer: {
                    Text("For kits, like a first-aid kit: list what's in it. Saving it as a kit lets you add it to any truck with Add from Kit.")
                }

                if isNew {
                    Section {
                        Button {
                            if save() { startNext() }
                        } label: {
                            Label("Save and Add Another", systemImage: "plus.circle")
                        }
                        .disabled(!isValid)
                    } footer: {
                        if addedCount > 0 {
                            Text("\(addedCount) added. The location is kept for the next item.")
                        }
                    }
                } else {
                    Section {
                        Button("Remove from Truck", role: .destructive) {
                            fleet.delete(item, vehicle: vehicleId)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .dismissesKeyboardOnScroll()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isNew && addedCount > 0 ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if save() { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear { if isNew { nameFocused = true } }
        }
    }

    private func save() -> Bool {
        let trimmedQuantity = quantityText.trimmed
        if trimmedQuantity.isEmpty {
            item.quantity = nil
        } else if let value = NumberParsing.int(trimmedQuantity), value >= 0 {
            item.quantity = value
        } else {
            ErrorCenter.shared.message = "Enter the quantity as a whole number, or leave it blank."
            return false
        }
        do {
            try fleet.save(item, vehicle: vehicleId)
            return true
        } catch {
            ErrorCenter.shared.report(error, "Saving \(item.name)")
            return false
        }
    }

    private func startNext() {
        addedCount += 1
        item = .new(location: item.location)
        quantityText = ""
        kitSaved = false
        nameFocused = true
    }
}

/// Managers' saved kits: delete the ones no longer used. (Kits are saved from an item's
/// "Inside This Item" section with "Save as a Kit for Other Trucks".)
struct KitsView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(fleet.kits) { kit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kit.name)
                            if let parts = TruckContents.partsText(kit.parts) {
                                Text(parts).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            try? fleet.deleteKit(fleet.kits[index])
                        }
                    }
                } footer: {
                    Text("Swipe left to delete a kit. Trucks that already have it keep their items. To change a kit, edit it on a truck and save it as a kit again with the same name.")
                }
            }
            .navigationTitle("Kits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
