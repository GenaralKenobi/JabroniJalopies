import SwiftData
import SwiftUI

struct ReminderFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    let vehicle: Vehicle
    /// `nil` when adding a new reminder.
    let reminder: MaintenanceReminder?

    @State private var serviceType: ServiceType
    @State private var title: String
    @State private var distanceText: String
    @State private var monthsText: String
    @State private var lastServiceDate: Date
    @State private var lastOdometerText: String
    @State private var notificationsEnabled: Bool
    @State private var showingDeleteConfirmation = false

    init(vehicle: Vehicle, reminder: MaintenanceReminder? = nil) {
        self.vehicle = vehicle
        self.reminder = reminder

        let type = reminder?.serviceType ?? .oilChange
        let suggestion = type.suggestedInterval(in: DistanceUnit.current)
        let distance = reminder == nil ? suggestion.distance : reminder?.intervalDistance
        let months = reminder == nil ? suggestion.months : reminder?.intervalMonths

        _serviceType = State(initialValue: type)
        _title = State(initialValue: reminder?.title ?? "")
        _distanceText = State(initialValue: distance.map { String($0) } ?? "")
        _monthsText = State(initialValue: months.map { String($0) } ?? "")
        _lastServiceDate = State(initialValue: reminder?.lastServiceDate ?? .now)
        _lastOdometerText = State(initialValue: String(reminder?.lastServiceOdometer ?? vehicle.odometer))
        _notificationsEnabled = State(initialValue: reminder?.notificationsEnabled ?? true)
    }

    private var intervalDistance: Int? { NumberParsing.int(distanceText).flatMap { $0 > 0 ? $0 : nil } }
    private var intervalMonths: Int? { NumberParsing.int(monthsText).flatMap { $0 > 0 ? $0 : nil } }

    private var isValid: Bool {
        (serviceType != .other || !title.trimmed.isEmpty)
            && (intervalDistance != nil || intervalMonths != nil)
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
                    TextField(serviceType == .other ? "Name" : "Custom name (optional)", text: $title)
                }

                Section {
                    HStack {
                        Text("Every")
                        TextField("—", text: $distanceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Every")
                        TextField("—", text: $monthsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("months").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Interval")
                } footer: {
                    Text("Due at whichever comes first. Leave one blank to track by distance or time only. Suggested values are typical — check your owner's manual.")
                }

                Section("Last Done") {
                    DatePicker("Date", selection: $lastServiceDate, in: ...Date.now, displayedComponents: .date)
                    HStack {
                        Text("Odometer")
                        TextField("0", text: $lastOdometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Notify When Due", isOn: $notificationsEnabled)
                } footer: {
                    Text("Time-based reminders send a notification on the due date. Distance-based reminders update whenever you record a new odometer reading.")
                }

                if reminder != nil {
                    Section {
                        Button("Delete Reminder", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onChange(of: serviceType) { _, newType in
                // Only pre-fill intervals for new reminders; never overwrite a saved schedule.
                guard reminder == nil else { return }
                let suggestion = newType.suggestedInterval(in: unit)
                distanceText = suggestion.distance.map { String($0) } ?? ""
                monthsText = suggestion.months.map { String($0) } ?? ""
            }
            .confirmationDialog("Delete this reminder?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        let target = reminder ?? MaintenanceReminder()
        target.serviceType = serviceType
        target.title = title.trimmed
        target.intervalDistance = intervalDistance
        target.intervalMonths = intervalMonths
        target.lastServiceDate = lastServiceDate
        target.lastServiceOdometer = NumberParsing.int(lastOdometerText) ?? vehicle.odometer
        target.notificationsEnabled = notificationsEnabled

        if reminder == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }

        if notificationsEnabled, target.intervalMonths != nil {
            Task {
                if await ReminderNotifications.requestAuthorization() {
                    ReminderNotifications.schedule(for: target)
                }
            }
        } else {
            ReminderNotifications.cancel(for: target)
        }
        dismiss()
    }

    private func delete() {
        if let reminder {
            ReminderNotifications.cancel(for: reminder)
            modelContext.delete(reminder)
        }
        dismiss()
    }
}
