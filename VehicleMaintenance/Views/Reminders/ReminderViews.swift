import SwiftUI

struct ReminderRow: View {
    private var unit: DistanceUnit { vehicle.unit }
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
    private var unit: DistanceUnit { vehicle.unit }

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
        let suggestion = type.suggestedInterval(in: vehicle.unit)
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
                        Text(unit.readingName)
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
            .keyboardDoneButton()
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
    @State private var planning: ScheduledDue?
    @State private var calendarReminder: ReminderCalendarItem?
    @State private var expanded = ExpandedGroups()

    var body: some View {
        NavigationStack {
            let groups = upcomingGroups
            Group {
                if groups.isEmpty {
                    ContentUnavailableView("Nothing Scheduled", systemImage: "calendar.badge.checkmark",
                                           description: Text(fleet.isManager
                                                             ? "Add maintenance reminders from a vehicle's page, or give a checklist a schedule in Settings → Checklists."
                                                             : "Your manager hasn't scheduled any maintenance yet."))
                } else {
                    List {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Section {
                                TruckGroupHeader(name: group.vehicle.displayName, summary: group.summary,
                                                 symbol: group.worst.symbolName,
                                                 color: group.worst == .ok ? .secondary : group.worst.color,
                                                 isExpanded: expanded.binding(group.id, in: $expanded))
                                if expanded.open.contains(group.id) {
                                    ForEach(group.scheduled) { entry in
                                        HStack {
                                            NavigationLink(value: entry.vehicleId) {
                                                ScheduledChecklistRow(entry: entry)
                                            }
                                            if fleet.isManager {
                                                Button(entry.plannedFor == nil ? "Plan" : "Change") { planning = entry }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                            }
                                        }
                                    }
                                    ForEach(group.reminders) { reminder in
                                        NavigationLink(value: group.id) {
                                            ReminderRow(reminder: reminder, vehicle: group.vehicle)
                                        }
                                        .addToCalendarActions(ReminderCalendarItem(reminder: reminder, vehicle: group.vehicle),
                                                              selection: $calendarReminder)
                                    }
                                }
                            } footer: {
                                if index == groups.count - 1 {
                                    Text(fleet.isManager
                                         ? "Tap a truck to see what's coming up. Scheduled checklists show when due within \(ScheduledChecklists.alertLeadDays) days or overdue: plan a day for each. Swipe left on a maintenance reminder to add it to your calendar."
                                         : "Tap a truck to see what's coming up. Swipe left on a maintenance reminder to add it to your calendar.")
                                }
                            }
                        }
                    }
                }
            }
            .expandGroupsForScreenshots(groups.map(\.id), $expanded)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ExpandAllButton(ids: groups.map(\.id), groups: $expanded)
                }
            }
            .readableWidth()
            .navigationTitle("Upcoming")
            .onAppear { fleet.watchAllReminders(true) }
            .onDisappear { fleet.watchAllReminders(false) }
            .navigationDestination(for: String.self) { VehicleDetailView(vehicleId: $0) }
            .sheet(item: $planning) { entry in
                PlanChecklistView(entry: entry, vehicleName: fleet.vehicle(entry.vehicleId)?.displayName ?? "")
            }
            .reminderCalendarSheet($calendarReminder)
            .syncStatusBanner()
        }
    }
}

extension UpcomingView {
    /// One truck's scheduled checklists and maintenance reminders.
    struct UpcomingGroup: Identifiable {
        let vehicle: Vehicle
        var scheduled: [ScheduledDue] = []
        var reminders: [Reminder] = []
        var id: String { vehicle.id ?? "" }

        private var statuses: [DueStatus] {
            scheduled.map { entry -> DueStatus in
                switch entry.status {
                case .overdue: .overdue
                case .dueSoon: .dueSoon
                case .later: .ok
                }
            } + reminders.map { $0.status(currentOdometer: vehicle.odometer) }
        }

        var worst: DueStatus { statuses.max() ?? .ok }

        var summary: String {
            let overdue = statuses.filter { $0 == .overdue }.count
            let soon = statuses.filter { $0 == .dueSoon }.count
            let later = statuses.count - overdue - soon
            var parts: [String] = []
            if overdue > 0 { parts.append("\(overdue) overdue") }
            if soon > 0 { parts.append("\(soon) due soon") }
            if later > 0 { parts.append("\(later) later") }
            return parts.joined(separator: " · ")
        }
    }

    var upcomingGroups: [UpcomingGroup] {
        // Managers see scheduled checklists due within two weeks or overdue; drivers see overdue ones.
        let scheduled = fleet.allScheduledChecklists().filter {
            fleet.isManager ? $0.status != .later : $0.status == .overdue
        }
        let groups: [UpcomingGroup] = fleet.sortedVehicles.compactMap { vehicle in
            let id = vehicle.id ?? ""
            let reminders = (fleet.reminders[id] ?? []).sorted {
                $0.status(currentOdometer: vehicle.odometer) > $1.status(currentOdometer: vehicle.odometer)
            }
            let checklists = scheduled.filter { $0.vehicleId == id }
            guard !reminders.isEmpty || !checklists.isEmpty else { return nil }
            return UpcomingGroup(vehicle: vehicle, scheduled: checklists, reminders: reminders)
        }
        // Trucks with the most urgent items first; sortedVehicles keeps them by name otherwise.
        return groups.enumerated().sorted { lhs, rhs in
            if lhs.element.worst != rhs.element.worst { return lhs.element.worst > rhs.element.worst }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
