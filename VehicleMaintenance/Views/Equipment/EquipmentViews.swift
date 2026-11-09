import SwiftUI

struct EquipmentRow: View {
    @Environment(FleetModel.self) private var fleet
    let item: Equipment
    var showsTruck = false

    var body: some View {
        let condition = fleet.condition(ofEquipment: item.id)
        let pending = fleet.pendingLengthChanges[item.id ?? ""] ?? []
        HStack(spacing: 12) {
            Image(systemName: item.type.symbolName)
                .foregroundStyle(condition == .ok ? Color.brand : condition.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).foregroundStyle(Color.primary)
                if showsTruck {
                    Text(fleet.vehicle(item.vehicleId)?.displayName ?? "Not on a truck")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.secondary)
                }
                if !item.detailLine.isEmpty {
                    Text(item.detailLine).font(.caption).foregroundStyle(Color.secondary)
                }
                if !pending.isEmpty {
                    Label("−\(Formatting.feet(pending.reduce(0) { $0 + $1.amountFeet })) pending approval", systemImage: "hourglass")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if condition == .outOfService {
                Text("Do not use")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.red, in: Capsule())
            } else if condition == .needsAttention || item.isBelowMinimumLength {
                ConditionBadge(condition: .needsAttention, compact: true)
            }
        }
    }
}

/// Red/orange banner on a truck listing equipment problems, so crews see them before heading out.
struct EquipmentAlertBanner: View {
    let alerts: [EquipmentAlert]

    var body: some View {
        let doNotUse = alerts.contains(where: \.isDoNotUse)
        VStack(alignment: .leading, spacing: 6) {
            Label(doNotUse ? "Equipment: do not use" : "Equipment needs attention",
                  systemImage: doNotUse ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(alerts) { alert in
                Text("• \(alert.equipment.displayName): \(alert.message)")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(doNotUse ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct EquipmentDetailView: View {
    let equipmentId: String

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var closedDefects: [Defect] = []
    @State private var history: [LengthChange] = []
    @State private var showingReport = false
    @State private var showingEdit = false
    @State private var showingMove = false
    @State private var showingReduction = false
    @State private var confirmingDelete = false

    var body: some View {
        if let item = fleet.equipment(equipmentId) {
            content(item)
        } else {
            ContentUnavailableView("Not Available", systemImage: "questionmark.circle",
                                   description: Text("It may have been removed or moved to a truck you can't see."))
        }
    }

    private func content(_ item: Equipment) -> some View {
        let openDefects = fleet.equipmentDefects[equipmentId] ?? []
        let pending = fleet.pendingLengthChanges[equipmentId] ?? []
        let owner = DefectOwner.equipment(equipmentId)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(item.displayName, systemImage: item.type.symbolName)
                        .font(.title3.bold())
                    Text("On \(fleet.vehicle(item.vehicleId)?.displayName ?? "no truck")")
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
                if openDefects.contains(where: \.unsafe) {
                    Label("DO NOT USE", systemImage: "exclamationmark.octagon.fill")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.red)
                }
                details(item)
            }

            if item.type == .rope {
                ropeSection(item, pending: pending)
            }

            Section {
                if openDefects.isEmpty {
                    Label("No open defects", systemImage: "checkmark.circle").foregroundStyle(Color.secondary)
                }
                ForEach(openDefects) { defect in
                    NavigationLink {
                        DefectDetailView(owner: owner, defectId: defect.id ?? "")
                    } label: {
                        DefectRow(defect: defect)
                    }
                }
                Button { showingReport = true } label: {
                    Label("Report a Problem", systemImage: "exclamationmark.bubble")
                }
                if !closedDefects.isEmpty {
                    NavigationLink("Closed Defects (\(closedDefects.count))") {
                        DefectHistoryView(owner: owner, defects: closedDefects)
                    }
                }
            } header: {
                Text("Defects")
            } footer: {
                if item.type == .rope && !fleet.isManager {
                    Text("Only managers can mark a rope \"Do not use\".")
                }
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .syncStatusBanner()
        .toolbar {
            if fleet.isManager {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button { showingMove = true } label: { Label("Move to Another Truck", systemImage: "arrow.left.arrow.right") }
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: equipmentId) { await loadHistory() }
        .sheet(isPresented: $showingReport) {
            ReportDefectView(owner: owner, allowUnsafe: item.type == .chainsaw || fleet.isManager, unsafeLabel: "Do not use")
        }
        .sheet(isPresented: $showingEdit) { EquipmentFormView(item: item) }
        .sheet(isPresented: $showingMove) { MoveEquipmentView(item: item) }
        .sheet(isPresented: $showingReduction) { LengthReductionFormView(rope: item) }
        .confirmationDialog("Remove \(item.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove and Delete History", role: .destructive) {
                guard ConnectivityMonitor.shared.isOnline else {
                    ErrorCenter.shared.message = "Removing equipment needs a connection. Try again when you have signal."
                    return
                }
                Task {
                    do {
                        try await fleet.delete(item)
                        dismiss()
                    } catch {
                        ErrorCenter.shared.report(error, "Removing \(item.displayName) (needs a connection)")
                    }
                }
            }
        } message: {
            Text("This deletes its defects, photos and length history. To keep the history, move it instead.")
        }
    }

    @ViewBuilder
    private func details(_ item: Equipment) -> some View {
        switch item.type {
        case .chainsaw:
            if !item.make.isEmpty || !item.model.isEmpty {
                LabeledContent("Make / model", value: [item.make, item.model].filter { !$0.isEmpty }.joined(separator: " "))
            }
            if let bar = item.barLengthInches { LabeledContent("Bar length", value: ChainSize.format(bar)) }
        case .rope:
            if !item.diameter.isEmpty { LabeledContent("Diameter", value: item.diameter) }
        }
        if !item.serialNumber.isEmpty { LabeledContent("Serial", value: item.serialNumber) }
        if !item.notes.isEmpty { Text(item.notes).font(.subheadline).foregroundStyle(Color.secondary) }
    }

    private func ropeSection(_ rope: Equipment, pending: [LengthChange]) -> some View {
        Section {
            LabeledContent("Length") {
                Text(rope.lengthFeet.map(Formatting.feet) ?? "Not set")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            if let minimum = rope.minLengthFeet {
                LabeledContent("Minimum", value: Formatting.feet(minimum))
                if rope.isBelowMinimumLength {
                    Label("Shorter than the minimum length", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(pending) { change in
                VStack(alignment: .leading, spacing: 8) {
                    LengthChangeRow(change: change, ropeName: nil)
                    if fleet.isManager {
                        HStack {
                            Button("Approve") { fleet.review(change, of: rope, approve: true) }
                                .buttonStyle(.borderedProminent).tint(.green)
                            Button("Reject", role: .destructive) { fleet.review(change, of: rope, approve: false) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Button { showingReduction = true } label: {
                Label("Submit Length Reduction", systemImage: "scissors")
            }
            if !history.isEmpty {
                NavigationLink("Length History") { LengthHistoryView(changes: history) }
            }
        } header: {
            Text("Rope Length")
        } footer: {
            Text(fleet.isManager ? "Approving a reduction updates the rope's length."
                 : "A manager approves reductions before the length changes. Submissions can't be withdrawn.")
        }
    }

    private func loadHistory() async {
        let defects = try? await FS.equipmentDefects(fleet.fleetId, equipmentId)
            .whereField("status", isEqualTo: DefectStatus.closed.rawValue).getDocuments()
        closedDefects = defects?.documents.compactMap { try? $0.data(as: Defect.self) } ?? []
        let changes = try? await FS.lengthChanges(fleet.fleetId, equipmentId)
            .order(by: "submittedAt", descending: true).limit(to: 100).getDocuments()
        history = changes?.documents.compactMap { try? $0.data(as: LengthChange.self) } ?? []
    }
}

struct LengthChangeRow: View {
    let change: LengthChange
    let ropeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ropeName {
                Text(ropeName).font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
            }
            HStack {
                Text("−\(Formatting.feet(change.amountFeet))").font(.headline.monospacedDigit()).foregroundStyle(Color.primary)
                Spacer()
                switch change.status {
                case .pending: Text("Pending").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                case .approved: Text("Approved").font(.caption.weight(.semibold)).foregroundStyle(.green)
                case .rejected: Text("Rejected").font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            if !change.reason.isEmpty { Text(change.reason).font(.subheadline).foregroundStyle(Color.primary) }
            Text("\(change.submittedByName) · \(change.submittedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(Color.secondary)
        }
    }
}

struct LengthHistoryView: View {
    let changes: [LengthChange]

    var body: some View {
        List(changes) { change in
            VStack(alignment: .leading, spacing: 2) {
                LengthChangeRow(change: change, ropeName: nil)
                if let reviewer = change.reviewedByName {
                    Text("Reviewed by \(reviewer)").font(.caption).foregroundStyle(Color.secondary)
                }
            }
        }
        .navigationTitle("Length History")
    }
}

struct LengthReductionFormView: View {
    let rope: Equipment

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var reason = ""
    @State private var errorMessage: String?

    private var amount: Double? { NumberParsing.decimal(amountText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Rope", value: rope.displayName)
                    LabeledContent("Current length", value: rope.lengthFeet.map(Formatting.feet) ?? "Not set")
                    HStack {
                        Text("Remove")
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("ft").foregroundStyle(Color.secondary)
                    }
                    TextField("Reason (e.g. cut out damaged section)", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("A manager must approve this before the length changes. Once submitted it can't be withdrawn.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .keyboardDoneButton()
            .navigationTitle("Length Reduction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        guard let amount else { return }
                        do {
                            try fleet.requestLengthReduction(of: rope, by: amount, reason: reason)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(amount == nil || reason.trimmed.isEmpty)
                }
            }
        }
    }
}

struct EquipmentFormView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    let original: Equipment?
    @State private var draft: Equipment
    @State private var barText: String
    @State private var lengthText: String
    @State private var minLengthText: String
    @State private var errorMessage: String?

    init(item: Equipment) {
        original = item.id == nil ? nil : item
        _draft = State(initialValue: item)
        _barText = State(initialValue: item.barLengthInches.map { $0.formatted() } ?? "")
        _lengthText = State(initialValue: item.lengthFeet.map { $0.formatted() } ?? "")
        _minLengthText = State(initialValue: item.minLengthFeet.map { $0.formatted() } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.type == .chainsaw ? "Name or number (e.g. Saw 4)" : "Name or number (e.g. Rigging A)",
                              text: $draft.name)
                    switch draft.type {
                    case .chainsaw:
                        TextField("Make (e.g. Stihl)", text: $draft.make)
                        TextField("Model (e.g. MS 462)", text: $draft.model)
                        HStack {
                            Text("Bar length")
                            TextField("—", text: $barText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text("in").foregroundStyle(Color.secondary)
                        }
                    case .rope:
                        TextField("Diameter (e.g. 1/2 in)", text: $draft.diameter)
                        HStack {
                            Text("Length")
                            TextField("—", text: $lengthText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text("ft").foregroundStyle(Color.secondary)
                        }
                        HStack {
                            Text("Minimum length")
                            TextField("Optional", text: $minLengthText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text("ft").foregroundStyle(Color.secondary)
                        }
                    }
                    TextField("Serial number (optional)", text: $draft.serialNumber)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                } footer: {
                    if draft.type == .rope && original != nil {
                        Text("As a manager you can correct the length here, for example after replacing the rope. Drivers submit reductions from the rope's page for approval.")
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .keyboardDoneButton()
            .navigationTitle(original == nil ? "Add \(draft.type.displayName)" : "Edit \(draft.type.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(draft.name.trimmed.isEmpty)
                }
            }
        }
    }

    private func save() {
        var item = draft
        item.name = item.name.trimmed
        item.barLengthInches = item.type == .chainsaw ? NumberParsing.decimal(barText) : nil
        if item.type == .rope {
            // Only take the typed length if it was changed, so an untouched field never
            // overwrites a reduction approved while the form was open.
            let initialText = original?.lengthFeet.map { $0.formatted() } ?? ""
            if lengthText != initialText {
                item.lengthFeet = NumberParsing.decimal(lengthText)
            } else {
                item.lengthFeet = original?.lengthFeet
            }
            item.minLengthFeet = NumberParsing.decimal(minLengthText)
        }
        if let original {
            fleet.update(item, from: original)
            dismiss()
            return
        }
        do {
            try fleet.add(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MoveEquipmentView: View {
    let item: Equipment
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(fleet.sortedVehicles) { vehicle in
                Button {
                    if let id = vehicle.id {
                        fleet.move(item, to: id)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text(vehicle.displayName).foregroundStyle(Color.primary)
                        Spacer()
                        if vehicle.id == item.vehicleId {
                            Text("Current").font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
                .disabled(vehicle.id == item.vehicleId)
            }
            .navigationTitle("Move \(item.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Managers: every chainsaw and rope in the fleet, including ones not on a truck.
struct EquipmentListView: View {
    @Environment(FleetModel.self) private var fleet

    var body: some View {
        List {
            ForEach(EquipmentType.allCases) { type in
                let items = fleet.equipment.filter { $0.type == type }
                    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                Section(type.pluralName) {
                    if items.isEmpty {
                        Text("None yet — add them from a truck's page.").foregroundStyle(Color.secondary)
                    }
                    ForEach(items) { item in
                        NavigationLink {
                            EquipmentDetailView(equipmentId: item.id ?? "")
                        } label: {
                            EquipmentRow(item: item, showsTruck: true)
                        }
                    }
                }
            }
        }
        .navigationTitle("Equipment")
    }
}
