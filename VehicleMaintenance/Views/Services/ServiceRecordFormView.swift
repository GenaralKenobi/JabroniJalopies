import SwiftData
import SwiftUI

struct ServiceRecordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    let vehicle: Vehicle
    /// `nil` when logging a new service.
    let record: ServiceRecord?

    @State private var serviceType: ServiceType
    @State private var title: String
    @State private var date: Date
    @State private var odometerText: String
    @State private var costText: String
    @State private var shop: String
    @State private var notes: String
    @State private var showingDeleteConfirmation = false

    init(vehicle: Vehicle, record: ServiceRecord? = nil, preselectedType: ServiceType? = nil, preselectedTitle: String = "") {
        self.vehicle = vehicle
        self.record = record
        _serviceType = State(initialValue: record?.serviceType ?? preselectedType ?? .oilChange)
        _title = State(initialValue: record?.title ?? preselectedTitle)
        _date = State(initialValue: record?.date ?? .now)
        _odometerText = State(initialValue: String(record?.odometer ?? vehicle.odometer))
        _costText = State(initialValue: {
            guard let cost = record?.cost, cost > 0 else { return "" }
            return cost.formatted(.number.grouping(.never).precision(.fractionLength(2)))
        }())
        _shop = State(initialValue: record?.shop ?? "")
        _notes = State(initialValue: record?.notes ?? "")
    }

    private var isValid: Bool {
        serviceType != .other || !title.trimmed.isEmpty
    }

    /// Reminders that will be reset when this (new) service is saved.
    private var matchingReminders: [MaintenanceReminder] {
        guard record == nil else { return [] }
        return (vehicle.reminders ?? []).filter { $0.matches(serviceType: serviceType, title: title.trimmed) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    TextField(serviceType == .other ? "Description" : "Description (optional)", text: $title)
                } footer: {
                    if !matchingReminders.isEmpty {
                        let names = matchingReminders.map(\.displayTitle).joined(separator: ", ")
                        Text("Saving will reset your \(names) reminder.")
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    HStack {
                        Text("Odometer")
                        TextField("0", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Cost")
                        TextField("0.00", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Formatting.currencyCode).foregroundStyle(.secondary)
                    }
                    TextField("Shop or mechanic", text: $shop)
                }

                Section("Notes") {
                    TextField("Parts used, warranty info…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if record != nil {
                    Section {
                        Button("Delete Service Record", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(record == nil ? "Log Service" : "Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this service record?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        let odometer = NumberParsing.int(odometerText) ?? vehicle.odometer
        let target = record ?? ServiceRecord()
        target.serviceType = serviceType
        target.title = title.trimmed
        target.date = date
        target.odometer = odometer
        target.cost = NumberParsing.decimal(costText) ?? 0
        target.shop = shop.trimmed
        target.notes = notes.trimmed

        if record == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
            resetMatchingReminders(date: date, odometer: odometer)
        }

        if odometer > vehicle.odometer {
            vehicle.odometer = odometer
        }
        dismiss()
    }

    private func resetMatchingReminders(date: Date, odometer: Int) {
        let calendar = Calendar.current
        for reminder in matchingReminders
        where calendar.startOfDay(for: date) >= calendar.startOfDay(for: reminder.lastServiceDate) {
            reminder.lastServiceDate = date
            reminder.lastServiceOdometer = odometer
            ReminderNotifications.schedule(for: reminder)
        }
    }

    private func delete() {
        if let record {
            modelContext.delete(record)
        }
        dismiss()
    }
}
