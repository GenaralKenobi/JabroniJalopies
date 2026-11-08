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
              ["vehicle", "specs", "checklist", "defect"].contains(screen),
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
        let condition = fleet.condition(of: vehicle.id)
        HStack(spacing: 12) {
            VehicleThumbnail(data: vehicle.photo)

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.displayName)
                    .font(.headline)
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Text(Formatting.distance(vehicle.odometer, unit: unit))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if condition != .ok {
                    ConditionBadge(condition: condition, compact: true)
                }
                if let due = fleet.reminderStatus(of: vehicle), due != .ok {
                    StatusBadge(status: due)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
