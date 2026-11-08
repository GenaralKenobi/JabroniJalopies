import SwiftData
import SwiftUI

/// Identifies a request to log a service, optionally pre-filled from a reminder.
struct ServiceLogRequest: Identifiable {
    let id = UUID()
    var type: ServiceType?
    var title: String = ""
}

struct VehicleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let vehicle: Vehicle

    @State private var showingEditVehicle = false
    @State private var serviceLog: ServiceLogRequest?
    @State private var editingRecord: ServiceRecord?
    @State private var showingAddReminder = false
    @State private var editingReminder: MaintenanceReminder?
    @State private var showingOdometerPrompt = false
    @State private var odometerText = ""

    var body: some View {
        let records = vehicle.sortedRecords
        let reminders = vehicle.sortedReminders

        List {
            headerSection
            remindersSection(reminders)
            historySection(records)
            if !records.isEmpty {
                costSection(records)
            }
        }
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { actionsMenu(hasRecords: !records.isEmpty) }
        }
        .sheet(isPresented: $showingEditVehicle) {
            VehicleFormView(vehicle: vehicle)
        }
        .sheet(item: $serviceLog) { request in
            ServiceRecordFormView(vehicle: vehicle, preselectedType: request.type, preselectedTitle: request.title)
        }
        .sheet(item: $editingRecord) { record in
            ServiceRecordFormView(vehicle: vehicle, record: record)
        }
        .sheet(isPresented: $showingAddReminder) {
            ReminderFormView(vehicle: vehicle)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(vehicle: vehicle, reminder: reminder)
        }
        .alert("Update Odometer", isPresented: $showingOdometerPrompt) {
            TextField("Odometer", text: $odometerText)
                .keyboardType(.numberPad)
            Button("Save") {
                if let value = NumberParsing.int(odometerText) {
                    vehicle.odometer = value
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the current reading in \(unit.displayName.lowercased()).")
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                if let data = vehicle.photoData, let image = UIImage(data: data) {
                    Color.clear
                        .frame(height: 180)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !vehicle.subtitle.isEmpty {
                        Text(vehicle.subtitle).foregroundStyle(.secondary)
                    }
                }
                if !(vehicle.reminders ?? []).isEmpty {
                    StatusBadge(status: vehicle.overallStatus)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

            LabeledContent("Odometer") {
                Button(Formatting.distance(vehicle.odometer, unit: unit), action: promptForOdometer)
            }
            if !vehicle.licensePlate.isEmpty {
                LabeledContent("License Plate", value: vehicle.licensePlate)
            }
            if !vehicle.vin.isEmpty {
                LabeledContent("VIN") {
                    Text(vehicle.vin)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func remindersSection(_ reminders: [MaintenanceReminder]) -> some View {
        Section {
            if reminders.isEmpty {
                Button {
                    showingAddReminder = true
                } label: {
                    Label("Add a maintenance reminder", systemImage: "bell.badge")
                }
            } else {
                ForEach(reminders) { reminder in
                    Button {
                        editingReminder = reminder
                    } label: {
                        ReminderRow(reminder: reminder)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            serviceLog = ServiceLogRequest(type: reminder.serviceType, title: reminder.title)
                        } label: {
                            Label("Log Service", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteReminder(reminder)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Maintenance")
        } footer: {
            if !reminders.isEmpty {
                Text("Swipe right on an item to log it as done.")
            }
        }
    }

    private func historySection(_ records: [ServiceRecord]) -> some View {
        Section("Recent Service") {
            if records.isEmpty {
                Button {
                    serviceLog = ServiceLogRequest()
                } label: {
                    Label("Log your first service", systemImage: "wrench.and.screwdriver")
                }
            } else {
                ForEach(records.prefix(5)) { record in
                    Button {
                        editingRecord = record
                    } label: {
                        ServiceRecordRow(record: record)
                    }
                }
                NavigationLink("All Service History (\(records.count))") {
                    ServiceHistoryView(vehicle: vehicle)
                }
            }
        }
    }

    private func costSection(_ records: [ServiceRecord]) -> some View {
        Section("Costs") {
            LabeledContent("Total Spent", value: Formatting.currency(vehicle.totalSpent))
            LabeledContent("This Year", value: Formatting.currency(vehicle.spent(inYearOf: .now)))
            CostChartView(records: records)
                .frame(height: 180)
                .padding(.vertical, 8)
        }
    }

    private func actionsMenu(hasRecords: Bool) -> some View {
        Menu {
            Button {
                serviceLog = ServiceLogRequest()
            } label: {
                Label("Log Service", systemImage: "wrench.and.screwdriver")
            }
            Button {
                showingAddReminder = true
            } label: {
                Label("Add Reminder", systemImage: "bell.badge")
            }
            Button(action: promptForOdometer) {
                Label("Update Odometer", systemImage: "speedometer")
            }
            Divider()
            Button {
                showingEditVehicle = true
            } label: {
                Label("Edit Vehicle", systemImage: "pencil")
            }
            if hasRecords {
                ShareLink(
                    item: ServiceHistoryExport(vehicle: vehicle, unit: unit),
                    preview: SharePreview("\(vehicle.displayName) Service History")
                ) {
                    Label("Export History (CSV)", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: Actions

    private func promptForOdometer() {
        odometerText = String(vehicle.odometer)
        showingOdometerPrompt = true
    }

    private func deleteReminder(_ reminder: MaintenanceReminder) {
        ReminderNotifications.cancel(for: reminder)
        modelContext.delete(reminder)
    }
}

#Preview {
    let container = SampleData.previewContainer
    let vehicle = try! container.mainContext.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)])).first!
    NavigationStack {
        VehicleDetailView(vehicle: vehicle)
    }
    .modelContainer(container)
}
