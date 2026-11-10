import SwiftUI

struct VehicleListView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(SessionModel.self) private var session

    @State private var path: [String] = []
    @State private var showingAddVehicle = false
    @State private var showingFleets = false
    @State private var searchText = ""
    @State private var didOpenDemoScreen = false

    private var filteredVehicles: [Vehicle] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return fleet.sortedVehicles }
        return fleet.sortedVehicles.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.yearMakeModel.localizedCaseInsensitiveContains(query)
                || $0.licensePlate.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !fleet.vehiclesLoaded {
                    ProgressView()
                } else if fleet.vehicles.isEmpty {
                    emptyState
                } else {
                    List(filteredVehicles) { vehicle in
                        NavigationLink(value: vehicle.id ?? "") {
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search vehicles")
                }
            }
            .navigationTitle(fleet.fleet?.name ?? "Fleet")
            .navigationDestination(for: String.self) { vehicleId in
                VehicleDetailView(vehicleId: vehicleId)
            }
            .toolbar {
                if session.memberships.count > 1 || !session.invites.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingFleets = true
                        } label: {
                            Label("Switch Fleet", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                if fleet.isManager {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddVehicle = true
                        } label: {
                            Label("Add Vehicle", systemImage: "plus")
                        }
                    }
                }
            }
            .syncStatusBanner()
            .sheet(isPresented: $showingAddVehicle) {
                VehicleFormView()
            }
            .sheet(isPresented: $showingFleets) {
                NavigationStack {
                    FleetPickerView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { showingFleets = false } }
                        }
                }
            }
            .onChange(of: fleet.openDefects.count) { _, _ in openDemoScreenIfNeeded() }
            .onAppear { openDemoScreenIfNeeded() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if fleet.isManager {
            ContentUnavailableView {
                Label("No Vehicles Yet", systemImage: "car.2")
            } description: {
                Text("Add the vehicles in your fleet, then invite drivers from Settings → Members.")
            } actions: {
                Button("Add Vehicle") { showingAddVehicle = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("No Vehicles Assigned", systemImage: "car.2",
                                   description: Text("Your manager hasn't given you access to any vehicles yet."))
        }
    }

    private func openDemoScreenIfNeeded() {
        guard !didOpenDemoScreen, let screen = DemoConfig.screen,
              ["vehicle", "specs", "contents", "checklist", "defect", "truckchains", "equipment-detail"].contains(screen),
              !fleet.vehicles.isEmpty, fleet.openDefects.count >= fleet.vehicles.count,
              let worst = fleet.sortedVehicles.max(by: { fleet.condition(of: $0.id) < fleet.condition(of: $1.id) }),
              let id = worst.id else { return }
        didOpenDemoScreen = true
        path = [id]
    }
}

struct VehicleRow: View {
    @Environment(FleetModel.self) private var fleet
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let vehicle: Vehicle

    var body: some View {
        let vehicleId = vehicle.id ?? ""
        let condition = fleet.condition(of: vehicle.id)
        let alerts = fleet.equipmentAlerts(on: vehicleId)
        let due = fleet.reminderStatus(of: vehicle).flatMap { $0 == .ok ? nil : $0 }

        HStack(alignment: .top, spacing: 12) {
            VehicleThumbnail(data: vehicle.photo)

            // Everything stacks under the name, and badges wrap onto extra lines,
            // so nothing gets squeezed however many badges a truck has.
            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName)
                    .font(.headline)
                Text([vehicle.subtitle, Formatting.distance(vehicle.odometer, unit: unit)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)

                if condition != .ok || !alerts.isEmpty || due != nil {
                    FlowLayout(spacing: 6) {
                        if condition != .ok {
                            ConditionBadge(condition: condition, compact: true)
                        }
                        if !alerts.isEmpty {
                            equipmentBadge(alerts)
                        }
                        if let due {
                            StatusBadge(status: due)
                        }
                    }
                    .padding(.top, 2)
                }

                if !fleet.checklists(for: vehicleId).isEmpty {
                    if let last = fleet.lastInspections[vehicleId], Calendar.current.isDateInToday(last.completedAt) {
                        Label("Checked today", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                    } else {
                        Label("Not checked today", systemImage: "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func equipmentBadge(_ alerts: [EquipmentAlert]) -> some View {
        let doNotUse = alerts.contains(where: \.isDoNotUse)
        return HStack(spacing: 4) {
            Image(systemName: doNotUse ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
            Text(alerts.count == 1 ? alerts[0].equipment.displayName : "\(alerts.count) equipment")
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(doNotUse ? Color.red : Color.orange)
        .background((doNotUse ? Color.red : Color.orange).opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Equipment needs attention: \(alerts.map(\.equipment.displayName).joined(separator: ", "))")
    }
}
