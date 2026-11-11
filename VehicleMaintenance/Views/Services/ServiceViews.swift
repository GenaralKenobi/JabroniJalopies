import SwiftUI

struct ServiceRecordRow: View {
    let record: ServiceRecord
    let cost: Double?
    var showsReviewHint = false
    var unit: DistanceUnit = DistanceUnit.current

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.serviceType.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle).foregroundStyle(Color.primary)
                Text("\(Formatting.shortDate(record.date)) · \(Formatting.distance(record.odometer, unit: unit))")
                    .font(.caption).foregroundStyle(Color.secondary)
                if !record.shop.isEmpty {
                    Text(record.shop).font(.caption).foregroundStyle(Color.secondary)
                }
                switch record.status {
                case .pending:
                    Label(showsReviewHint ? "Logged by \(record.createdByName) — tap to review" : "Awaiting manager sign-off",
                          systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                case .rejected:
                    Label("Rejected\(record.reviewNote.map { ": \($0)" } ?? "")", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                case .approved:
                    EmptyView()
                }
            }
            Spacer(minLength: 8)
            if let cost, cost > 0 {
                Text(Formatting.currency(cost))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ServiceRecordFormView: View {
    let vehicle: Vehicle
    let original: ServiceRecord?

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    private var unit: DistanceUnit { vehicle.unit }

    @State private var draft: ServiceRecord
    @State private var odometerText: String
    @State private var costText: String
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(vehicle: Vehicle, record: ServiceRecord? = nil, cost: Double? = nil) {
        self.vehicle = vehicle
        original = record
        _draft = State(initialValue: record ?? ServiceRecord(
            date: .now, odometer: vehicle.odometer, serviceType: .oilChange, title: "", shop: "", notes: "",
            status: .pending, createdBy: "", createdByName: ""))
        _odometerText = State(initialValue: String(record?.odometer ?? vehicle.odometer))
        _costText = State(initialValue: cost.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(2))) } ?? "")
    }

    private var isValid: Bool { draft.serviceType != .other || !draft.title.trimmed.isEmpty }

    private var canDelete: Bool {
        guard let original else { return false }
        return fleet.isManager || (original.createdBy == fleet.uid && original.status == .pending)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $draft.serviceType) {
                        ForEach(ServiceType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    TextField(draft.serviceType == .other ? "Description" : "Description (optional)", text: $draft.title)
                }

                Section {
                    DatePicker("Date", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                    HStack {
                        Text(unit.readingName)
                        TextField("0", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(Color.secondary)
                    }
                    if fleet.isManager {
                        HStack {
                            Text("Cost")
                            TextField("0.00", text: $costText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(Formatting.currencyCode).foregroundStyle(Color.secondary)
                        }
                    }
                    TextField("Shop or mechanic", text: $draft.shop)
                } footer: {
                    if !fleet.isManager {
                        Text("A manager will review this entry before it counts toward maintenance reminders.")
                    }
                }

                Section("Notes") {
                    TextField("Parts used, warranty info…", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if canDelete {
                    Section {
                        Button("Delete Service Record", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(original == nil ? "Log Service" : "Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(fleet.isManager || original != nil ? "Save" : "Submit", action: save).disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this service record?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original, let vehicleId = vehicle.id { fleet.delete(original, vehicleId: vehicleId) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        var record = draft
        record.title = record.title.trimmed
        record.shop = record.shop.trimmed
        record.notes = record.notes.trimmed
        record.odometer = NumberParsing.int(odometerText) ?? vehicle.odometer
        do {
            try fleet.logService(record, cost: fleet.isManager ? NumberParsing.decimal(costText) : nil, vehicle: vehicle)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Managers approve or reject a service a driver logged.
struct ServiceReviewView: View {
    let vehicle: Vehicle
    let record: ServiceRecord

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    private var unit: DistanceUnit { vehicle.unit }
    @State private var costText = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Vehicle", value: vehicle.displayName)
                    LabeledContent("Service", value: record.displayTitle)
                    LabeledContent("Date", value: Formatting.shortDate(record.date))
                    LabeledContent(unit.readingName, value: Formatting.distance(record.odometer, unit: unit))
                    if !record.shop.isEmpty { LabeledContent("Shop", value: record.shop) }
                    LabeledContent("Logged by", value: record.createdByName)
                    if !record.notes.isEmpty {
                        Text(record.notes).font(.subheadline)
                    }
                }
                Section {
                    HStack {
                        Text("Cost")
                        TextField("0.00", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Formatting.currencyCode).foregroundStyle(Color.secondary)
                    }
                    TextField("Note to driver (optional)", text: $note, axis: .vertical)
                } footer: {
                    Text("Approving resets matching maintenance reminders. Costs are only visible to managers.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Section {
                    Button {
                        do {
                            try fleet.approve(record, vehicle: vehicle, cost: NumberParsing.decimal(costText), note: note)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Approve", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        if let vehicleId = vehicle.id { fleet.reject(record, vehicleId: vehicleId, note: note) }
                        dismiss()
                    } label: {
                        Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Review Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

struct ServiceHistoryView: View {
    let vehicle: Vehicle
    let records: VehicleRecordsModel

    @Environment(FleetModel.self) private var fleet
    @State private var searchText = ""
    @State private var editing: ServiceRecord?

    private var filtered: [ServiceRecord] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return records.services }
        return records.services.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.shop.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
                || $0.createdByName.localizedCaseInsensitiveContains(query)
        }
    }

    private var byYear: [(year: Int, records: [ServiceRecord])] {
        let groups = Dictionary(grouping: filtered) { Calendar.current.component(.year, from: $0.date) }
        return groups.keys.sorted(by: >).map { (year: $0, records: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(byYear, id: \.year) { group in
                Section {
                    ForEach(group.records) { record in
                        Button {
                            if fleet.isManager || (record.createdBy == fleet.uid && record.status == .pending) {
                                editing = record
                            }
                        } label: {
                            ServiceRecordRow(record: record, cost: fleet.isManager ? records.cost(of: record) : nil, unit: vehicle.unit)
                        }
                    }
                } header: {
                    HStack {
                        Text(String(group.year))
                        Spacer()
                        if fleet.isManager {
                            Text(Formatting.currency(group.records.compactMap { records.cost(of: $0) }.reduce(0, +)))
                        }
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                if searchText.trimmed.isEmpty {
                    ContentUnavailableView("No Service History", systemImage: "wrench.and.screwdriver")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search services, shops, notes")
        .navigationTitle("Service History")
        .sheet(item: $editing) { record in
            ServiceRecordFormView(vehicle: vehicle, record: record, cost: records.cost(of: record))
        }
    }
}
