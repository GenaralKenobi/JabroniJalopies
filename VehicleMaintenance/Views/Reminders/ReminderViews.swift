import SwiftUI

struct ReminderRow: View {
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let reminder: Reminder
    let vehicle: Vehicle
    var showsVehicle = false

    var body: some View {
        let status = reminder.status(currentOdometer: vehicle.odometer)
        HStack(spacing: 12) {
            Image(systemName: reminder.serviceType.symbolName)
                .foregroundStyle(status.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.displayTitle).foregroundStyle(Color.primary)
                if showsVehicle {
                    Text(vehicle.displayName).font(.caption.weight(.medium)).foregroundStyle(Color.secondary)
                }
                Text(dueDescription).font(.caption).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            if status != .ok && !showsVehicle {
                StatusBadge(status: status)
            }
        }
        .padding(.vertical, 2)
    }

    private var dueDescription: String {
        var parts: [String] = []
        if let dueOdometer = reminder.nextDueOdometer {
            let remaining = dueOdometer - vehicle.odometer
            let detail = remaining >= 0 ? "\(remaining.formatted()) left" : "\((-remaining).formatted()) over"
            parts.append("\(Formatting.distance(dueOdometer, unit: unit)) (\(detail))")
        }
        if let dueDate = reminder.nextDueDate {
            parts.append(Formatting.shortDate(dueDate))
        }
        return parts.isEmpty ? "No interval set" : "Next: " + parts.joined(separator: " · ")
    }
}

struct ReminderFormView: View {
    let vehicle: Vehicle
    let original: Reminder?

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    @State private var serviceType: ServiceType
    @State private var title: String
    @State private var distanceText: String
    @State private var monthsText: String
    @State private var lastServiceDate: Date
    @State private var lastOdometerText: String
    @State private var notificationsEnabled: Bool
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(vehicle: Vehicle, reminder: Reminder? = nil) {
        self.vehicle = vehicle
        original = reminder
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
        (serviceType != .other || !title.trimmed.isEmpty) && (intervalDistance != nil || intervalMonths != nil)
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
                        TextField("—", text: $distanceText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(Color.secondary)
                    }
                    HStack {
                        Text("Every")
                        TextField("—", text: $monthsText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("months").foregroundStyle(Color.secondary)
                    }
                } header: {
                    Text("Interval")
                } footer: {
                    Text("Due at whichever comes first. Approved service records reset it automatically.")
                }
                Section("Last Done") {
                    DatePicker("Date", selection: $lastServiceDate, in: ...Date.now, displayedComponents: .date)
                    HStack {
                        Text("Odometer")
                        TextField("0", text: $lastOdometerText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(Color.secondary)
                    }
                }
                Section {
                    Toggle("Notify When Due", isOn: $notificationsEnabled)
                } footer: {
                    Text("Managers get a notification on the due date for time-based reminders.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if original != nil {
                    Section {
                        Button("Delete Reminder", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
            }
            .onChange(of: serviceType) { _, newType in
                guard original == nil else { return }
                let suggestion = newType.suggestedInterval(in: unit)
                distanceText = suggestion.distance.map { String($0) } ?? ""
                monthsText = suggestion.months.map { String($0) } ?? ""
            }
            .confirmationDialog("Delete this reminder?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original, let vehicleId = vehicle.id { fleet.delete(original, vehicleId: vehicleId) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        guard let vehicleId = vehicle.id else { return }
        var reminder = Reminder(serviceType: serviceType, title: title.trimmed, intervalDistance: intervalDistance,
                                intervalMonths: intervalMonths, lastServiceDate: lastServiceDate,
                                lastServiceOdometer: NumberParsing.int(lastOdometerText) ?? vehicle.odometer,
                                notificationsEnabled: notificationsEnabled)
        reminder.id = original?.id
        do {
            try fleet.save(reminder, vehicleId: vehicleId)
            if notificationsEnabled {
                Task { await ReminderNotifications.requestAuthorization() }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UpcomingView: View {
    @Environment(FleetModel.self) private var fleet

    var body: some View {
        NavigationStack {
            let entries = fleet.allReminders
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("Nothing Scheduled", systemImage: "calendar.badge.checkmark",
                                           description: Text(fleet.isManager
                                                             ? "Add maintenance reminders from a vehicle's page."
                                                             : "Your manager hasn't scheduled any maintenance yet."))
                } else {
                    List {
                        ForEach(DueStatus.allCases.reversed(), id: \.self) { status in
                            let items = entries.filter { $0.reminder.status(currentOdometer: $0.vehicle.odometer) == status }
                            if !items.isEmpty {
                                Section(status.sectionTitle) {
                                    ForEach(items, id: \.reminder.id) { entry in
                                        NavigationLink(value: entry.vehicle.id ?? "") {
                                            ReminderRow(reminder: entry.reminder, vehicle: entry.vehicle, showsVehicle: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: String.self) { VehicleDetailView(vehicleId: $0) }
            .syncStatusBanner()
        }
    }
}
