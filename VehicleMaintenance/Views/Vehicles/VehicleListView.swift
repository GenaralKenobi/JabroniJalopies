import SwiftData
import SwiftUI

struct VehicleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var showingAddVehicle = false

    var body: some View {
        NavigationStack {
            Group {
                if vehicles.isEmpty {
                    ContentUnavailableView {
                        Label("No Vehicles", systemImage: "car")
                    } description: {
                        Text("Add a vehicle to start tracking its maintenance.")
                    } actions: {
                        Button("Add Vehicle") { showingAddVehicle = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(vehicles) { vehicle in
                            NavigationLink(value: vehicle) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                        .onDelete(perform: deleteVehicles)
                    }
                }
            }
            .navigationTitle("Garage")
            .navigationDestination(for: Vehicle.self) { vehicle in
                VehicleDetailView(vehicle: vehicle)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddVehicle = true
                    } label: {
                        Label("Add Vehicle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddVehicle) {
                VehicleFormView()
            }
        }
    }

    private func deleteVehicles(at offsets: IndexSet) {
        for index in offsets {
            let vehicle = vehicles[index]
            vehicle.reminders?.forEach(ReminderNotifications.cancel(for:))
            modelContext.delete(vehicle)
        }
    }
}

private struct VehicleRow: View {
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            VehicleThumbnail(data: vehicle.photoData)

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName)
                    .font(.headline)
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(Formatting.distance(vehicle.odometer, unit: unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !(vehicle.reminders ?? []).isEmpty {
                StatusBadge(status: vehicle.overallStatus)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VehicleListView()
        .modelContainer(SampleData.previewContainer)
}
