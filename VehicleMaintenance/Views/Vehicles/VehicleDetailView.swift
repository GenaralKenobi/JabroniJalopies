import SwiftUI

struct VehicleDetailView: View {
    let vehicleId: String

    @Environment(FleetModel.self) private var fleet
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    @State private var records: VehicleRecordsModel?
    @State private var showingEdit = false
    @State private var showingChecklistPicker = false
    @State private var activeChecklist: ChecklistTemplate?
    @State private var confirmingUnsafeStart: ChecklistTemplate?
    @State private var showingReportProblem = false
    @State private var showingLogService = false
    @State private var editingService: ServiceRecord?
    @State private var reviewingService: ServiceRecord?
    @State private var showingAddReminder = false
    @State private var editingReminder: Reminder?
    @State private var showingOdometerPrompt = false
    @State private var odometerText = ""
    @State private var confirmingDelete = false
    @State private var didOpenDemoScreen = false
    @State private var demoSpecs = false
    @State private var addingEquipment: Equipment?
    @State private var demoChains = false
    @State private var demoEquipmentId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let vehicle = fleet.vehicle(vehicleId) {
            content(vehicle)
        } else {
            ContentUnavailableView("Vehicle Unavailable", systemImage: "car",
                                   description: Text("It may have been deleted or your access changed."))
        }
    }

    private func content(_ vehicle: Vehicle) -> some View {
        let openDefects = fleet.openDefects[vehicleId] ?? []
        let condition = VehicleCondition(openDefects: openDefects)
        let checklists = fleet.checklists(for: vehicleId)

        return List {
            headerSection(vehicle, condition: condition, openDefects: openDefects)
            actionsSection(vehicle, checklists: checklists, condition: condition)

            Section {
                NavigationLink {
                    SpecsView(vehicleId: vehicleId)
                } label: {
                    Label("Fluids, Tires & Pressures", systemImage: "list.bullet.rectangle.portrait")
                }
            }

            defectsSection(openDefects)
            chainsSection
            equipmentSection
            remindersSection(vehicle)
            inspectionsSection
            servicesSection(vehicle)
            if fleet.isManager, let records, !records.approvedServices.isEmpty {
                costSection(records)
            }
            detailsSection(vehicle)
        }
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .syncStatusBanner()
        .toolbar { ToolbarItem(placement: .primaryAction) { menu(vehicle) } }
        .task {
            if records == nil {
                records = VehicleRecordsModel(fleetId: fleet.fleetId, vehicleId: vehicleId, includeCosts: fleet.isManager)
            }
            openDemoScreenIfNeeded(checklists: checklists)
        }
        .navigationDestination(isPresented: $demoSpecs) { SpecsView(vehicleId: vehicleId) }
        .navigationDestination(isPresented: $demoChains) { ChainsView(vehicleId: vehicleId) }
        .navigationDestination(item: $demoEquipmentId) { EquipmentDetailView(equipmentId: $0) }
        .sheet(isPresented: $showingEdit) { VehicleFormView(vehicle: vehicle) }
        .sheet(item: $addingEquipment) { EquipmentFormView(item: $0) }
        .sheet(isPresented: $showingReportProblem) { ReportDefectView(owner: .vehicle(vehicleId)) }
        .sheet(isPresented: $showingLogService) { ServiceRecordFormView(vehicle: vehicle) }
        .sheet(item: $editingService) { ServiceRecordFormView(vehicle: vehicle, record: $0, cost: records?.cost(of: $0)) }
        .sheet(item: $reviewingService) { ServiceReviewView(vehicle: vehicle, record: $0) }
        .sheet(isPresented: $showingAddReminder) { ReminderFormView(vehicle: vehicle) }
        .sheet(item: $editingReminder) { ReminderFormView(vehicle: vehicle, reminder: $0) }
        .fullScreenCover(item: $activeChecklist) { checklist in
            InspectionFormView(vehicle: vehicle, checklist: checklist)
        }
        .confirmationDialog("Choose a Checklist", isPresented: $showingChecklistPicker, titleVisibility: .visible) {
            ForEach(checklists) { checklist in
                Button(checklist.name) { start(checklist, condition: condition) }
            }
        }
        .alert("This Vehicle Is Marked Unsafe to Drive", isPresented: Binding(
            get: { confirmingUnsafeStart != nil },
            set: { if !$0 { confirmingUnsafeStart = nil } }
        )) {
            Button("Continue Checklist") {
                activeChecklist = confirmingUnsafeStart
                confirmingUnsafeStart = nil
            }
            Button("Cancel", role: .cancel) { confirmingUnsafeStart = nil }
        } message: {
            Text("Open safety defects: \(openDefects.filter(\.unsafe).map(\.title).joined(separator: ", ")).\n\nDo not drive it until a manager clears these.")
        }
        .alert("Update Odometer", isPresented: $showingOdometerPrompt) {
            TextField("Odometer", text: $odometerText).keyboardType(.numberPad)
            Button("Save") {
                if let value = NumberParsing.int(odometerText) { fleet.updateOdometer(of: vehicle, to: value) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the current reading in \(unit.displayName.lowercased()).")
        }
        .confirmationDialog("Delete \(vehicle.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Vehicle and All Records", role: .destructive) {
                Task {
                    do {
                        try await fleet.delete(vehicle)
                        dismiss()
                    } catch {
                        ErrorCenter.shared.report(error, "Deleting vehicle (needs a connection)")
                    }
                }
            }
        } message: {
            Text("This permanently deletes its checklists, defects, photos and service history.")
        }
    }

    // MARK: Sections

    private func headerSection(_ vehicle: Vehicle, condition: VehicleCondition, openDefects: [Defect]) -> some View {
        Section {
            VStack(spacing: 12) {
                if let data = vehicle.photo, let image = UIImage(data: data) {
                    Color.clear
                        .frame(height: 170)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(spacing: 4) {
                    Text(vehicle.displayName).font(.title2.bold()).multilineTextAlignment(.center)
                    if !vehicle.subtitle.isEmpty { Text(vehicle.subtitle).foregroundStyle(Color.secondary) }
                }
                if condition == .outOfService {
                    UnsafeBanner(defects: openDefects)
                } else {
                    ConditionBadge(condition: condition)
                }
                let alerts = fleet.equipmentAlerts(on: vehicleId)
                if !alerts.isEmpty {
                    EquipmentAlertBanner(alerts: alerts)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
        }
    }

    private func actionsSection(_ vehicle: Vehicle, checklists: [ChecklistTemplate], condition: VehicleCondition) -> some View {
        Section {
            if checklists.isEmpty {
                Label(fleet.isManager ? "Create a checklist in Settings → Checklists" : "No checklist assigned to this vehicle",
                      systemImage: "checklist")
                    .foregroundStyle(Color.secondary)
            } else {
                Button {
                    if checklists.count == 1, let only = checklists.first {
                        start(only, condition: condition)
                    } else {
                        showingChecklistPicker = true
                    }
                } label: {
                    Label("Start Checklist", systemImage: "checklist.checked")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Button {
                showingReportProblem = true
            } label: {
                Label("Report a Problem", systemImage: "exclamationmark.bubble")
            }
            Button(action: promptForOdometer) {
                LabeledContent {
                    Text(Formatting.distance(vehicle.odometer, unit: unit))
                } label: {
                    Label("Update Odometer", systemImage: "speedometer")
                }
            }
        }
    }

    @ViewBuilder
    private func defectsSection(_ openDefects: [Defect]) -> some View {
        Section {
            if openDefects.isEmpty {
                Label("No open defects", systemImage: "checkmark.circle")
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(openDefects) { defect in
                    NavigationLink {
                        DefectDetailView(owner: .vehicle(vehicleId), defectId: defect.id ?? "")
                    } label: {
                        DefectRow(defect: defect, unsynced: records?.unsyncedDefectIds.contains(defect.id ?? "") ?? false)
                    }
                }
            }
            if let records, records.defects.contains(where: { $0.status == .closed }) {
                NavigationLink("Closed Defects") {
                    DefectHistoryView(owner: .vehicle(vehicleId), defects: records.defects)
                }
            }
        } header: {
            Text("Open Defects")
        }
    }

    @ViewBuilder
    private var chainsSection: some View {
        let inventory = fleet.chainInventories[vehicleId]
        if let inventory, !inventory.sizes.isEmpty {
            Section {
                ChainSummaryRows(inventory: inventory)
                NavigationLink {
                    ChainsView(vehicleId: vehicleId)
                } label: {
                    Label("Log Chains", systemImage: "link")
                }
            } header: {
                Text("Chains")
            }
        } else if fleet.isManager {
            Section("Chains") {
                NavigationLink {
                    ChainsView(vehicleId: vehicleId)
                } label: {
                    Label("Set Up Chain Tracking", systemImage: "link")
                }
            }
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        let items = fleet.equipment(on: vehicleId)
        if !items.isEmpty || fleet.isManager {
            Section {
                ForEach(items) { item in
                    NavigationLink {
                        EquipmentDetailView(equipmentId: item.id ?? "")
                    } label: {
                        EquipmentRow(item: item)
                    }
                }
                if fleet.isManager {
                    Menu {
                        ForEach(EquipmentType.allCases) { type in
                            Button {
                                addingEquipment = .new(type, vehicleId: vehicleId)
                            } label: {
                                Label("Add \(type.displayName)", systemImage: type.symbolName)
                            }
                        }
                    } label: {
                        Label("Add Chainsaw or Rope", systemImage: "plus")
                    }
                }
            } header: {
                Text("Chainsaws & Ropes")
            } footer: {
                if !items.isEmpty {
                    Text("Tap a saw or rope to report a problem\(items.contains { $0.type == .rope } ? " or submit a rope length change" : "").")
                }
            }
        }
    }

    private func remindersSection(_ vehicle: Vehicle) -> some View {
        let items = (fleet.reminders[vehicleId] ?? []).sorted {
            $0.status(currentOdometer: vehicle.odometer) > $1.status(currentOdometer: vehicle.odometer)
        }
        return Section {
            if items.isEmpty {
                if fleet.isManager {
                    Button { showingAddReminder = true } label: {
                        Label("Add a maintenance reminder", systemImage: "bell.badge")
                    }
                } else {
                    Text("No maintenance reminders").foregroundStyle(Color.secondary)
                }
            } else {
                ForEach(items) { reminder in
                    if fleet.isManager {
                        Button { editingReminder = reminder } label: {
                            ReminderRow(reminder: reminder, vehicle: vehicle)
                        }
                    } else {
                        ReminderRow(reminder: reminder, vehicle: vehicle)
                    }
                }
                if fleet.isManager {
                    Button { showingAddReminder = true } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }
            }
        } header: {
            Text("Maintenance")
        }
    }

    @ViewBuilder
    private var inspectionsSection: some View {
        Section {
            if let records {
                if records.inspections.isEmpty {
                    Text("No checklists completed yet").foregroundStyle(Color.secondary)
                } else {
                    ForEach(records.inspections.prefix(5)) { inspection in
                        NavigationLink {
                            InspectionDetailView(vehicleId: vehicleId, inspection: inspection)
                        } label: {
                            InspectionRow(inspection: inspection,
                                          unsynced: records.unsyncedInspectionIds.contains(inspection.id ?? ""))
                        }
                    }
                    if records.inspections.count > 5 {
                        NavigationLink("All Checklists (\(records.inspections.count))") {
                            InspectionListView(vehicleId: vehicleId, records: records)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Recent Checklists")
        }
    }

    @ViewBuilder
    private func servicesSection(_ vehicle: Vehicle) -> some View {
        let pending = fleet.pendingServices[vehicleId] ?? []
        Section {
            ForEach(pending) { record in
                Button {
                    if fleet.isManager {
                        reviewingService = record
                    } else if record.createdBy == fleet.uid {
                        editingService = record
                    }
                } label: {
                    ServiceRecordRow(record: record, cost: nil, showsReviewHint: fleet.isManager)
                }
            }
            if let records {
                ForEach(records.services.filter { $0.status != .pending }.prefix(5)) { record in
                    Button {
                        if fleet.isManager { editingService = record }
                    } label: {
                        ServiceRecordRow(record: record, cost: fleet.isManager ? records.cost(of: record) : nil)
                    }
                    .disabled(!fleet.isManager)
                }
                if !records.services.isEmpty {
                    NavigationLink("All Service History") {
                        ServiceHistoryView(vehicle: vehicle, records: records)
                    }
                }
            }
            Button { showingLogService = true } label: {
                Label("Log a Service", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("Service History")
        } footer: {
            if !fleet.isManager {
                Text("Services you log are reviewed by a manager before they count.")
            }
        }
    }

    private func costSection(_ records: VehicleRecordsModel) -> some View {
        Section("Costs (Managers Only)") {
            LabeledContent("Total Spent", value: Formatting.currency(records.totalSpent))
            LabeledContent("This Year", value: Formatting.currency(records.spent(inYearOf: .now)))
            CostChartView(monthlyTotals: records.monthlyCosts)
                .frame(height: 170)
                .padding(.vertical, 8)
        }
    }

    private func detailsSection(_ vehicle: Vehicle) -> some View {
        Section("Details") {
            if !vehicle.licensePlate.isEmpty { LabeledContent("License Plate", value: vehicle.licensePlate) }
            if !vehicle.vin.isEmpty {
                LabeledContent("VIN") {
                    Text(vehicle.vin).font(.footnote.monospaced()).textSelection(.enabled)
                }
            }
            if fleet.isManager {
                let assigned = fleet.members.filter { vehicle.assignedUids.contains($0.id ?? "") }
                LabeledContent("Assigned Drivers",
                               value: assigned.isEmpty ? "None" : assigned.map(\.displayName).joined(separator: ", "))
            }
        }
    }

    private func menu(_ vehicle: Vehicle) -> some View {
        Menu {
            Button { showingLogService = true } label: { Label("Log Service", systemImage: "wrench.and.screwdriver") }
            Button { showingReportProblem = true } label: { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
            Button(action: promptForOdometer) { Label("Update Odometer", systemImage: "speedometer") }
            if let records, !records.services.isEmpty {
                ShareLink(item: ServiceHistoryExport(records: records.services, costs: records.costs,
                                                     includeCosts: fleet.isManager, unit: unit),
                          preview: SharePreview("\(vehicle.displayName) Service History")) {
                    Label("Export Service History", systemImage: "square.and.arrow.up")
                }
            }
            if fleet.isManager {
                Divider()
                Button { showingEdit = true } label: { Label("Edit Vehicle", systemImage: "pencil") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete Vehicle", systemImage: "trash") }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: Actions

    private func start(_ checklist: ChecklistTemplate, condition: VehicleCondition) {
        if condition == .outOfService {
            confirmingUnsafeStart = checklist
        } else {
            activeChecklist = checklist
        }
    }

    private func promptForOdometer() {
        odometerText = String(fleet.vehicle(vehicleId)?.odometer ?? 0)
        showingOdometerPrompt = true
    }

    private func openDemoScreenIfNeeded(checklists: [ChecklistTemplate]) {
        guard !didOpenDemoScreen, let screen = DemoConfig.screen else { return }
        didOpenDemoScreen = true
        switch screen {
        case "specs": demoSpecs = true
        case "checklist": activeChecklist = checklists.first
        case "truckchains": demoChains = true
        case "equipment-detail":
            demoEquipmentId = fleet.equipment(on: vehicleId, type: .rope).first?.id ?? fleet.equipment(on: vehicleId).first?.id
        default: break
        }
    }
}
