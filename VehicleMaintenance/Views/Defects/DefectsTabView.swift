import SwiftUI

/// Everything that needs attention: open defects across the fleet and, for
/// managers, driver-logged services waiting for sign-off.
struct DefectsTabView: View {
    @Environment(FleetModel.self) private var fleet
    @State private var reviewing: (vehicle: Vehicle, record: ServiceRecord)?
    @State private var showingReview = false

    var body: some View {
        NavigationStack {
            List {
                let defects = fleet.allOpenDefects
                Section {
                    if defects.isEmpty {
                        Label("No open defects", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(defects, id: \.defect.id) { entry in
                        NavigationLink {
                            DefectDetailView(vehicleId: entry.vehicle.id ?? "", defectId: entry.defect.id ?? "")
                        } label: {
                            DefectRow(defect: entry.defect, vehicleName: entry.vehicle.displayName)
                        }
                    }
                } header: {
                    Text("Open Defects")
                } footer: {
                    if !defects.isEmpty {
                        Text(fleet.isManager ? "Only managers can close defects." : "A manager closes defects once they're repaired.")
                    }
                }

                let pending = fleet.allPendingServices
                if !pending.isEmpty {
                    Section {
                        ForEach(pending, id: \.record.id) { entry in
                            Button {
                                if fleet.isManager {
                                    reviewing = entry
                                    showingReview = true
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.vehicle.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ServiceRecordRow(record: entry.record, cost: nil, showsReviewHint: fleet.isManager)
                                }
                            }
                            .disabled(!fleet.isManager)
                        }
                    } header: {
                        Text(fleet.isManager ? "Services Awaiting Your Sign-Off" : "Services Awaiting Sign-Off")
                    }
                }
            }
            .navigationTitle("Defects")
            .syncStatusBanner()
            .sheet(isPresented: $showingReview) {
                if let reviewing {
                    ServiceReviewView(vehicle: reviewing.vehicle, record: reviewing.record)
                }
            }
        }
    }
}

struct DefectRow: View {
    let defect: Defect
    var vehicleName: String?
    var unsynced = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: defect.unsafe ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(defect.status == .closed ? Color.secondary : defect.unsafe ? Color.red : Color.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                if let vehicleName {
                    Text(vehicleName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(defect.title).foregroundStyle(.primary)
                if !defect.details.isEmpty {
                    Text(defect.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text("\(defect.reportedByName) · \(defect.reportedAt.formatted(.relative(presentation: .named)))")
                    if !defect.photos.isEmpty {
                        Label("\(defect.photos.count)", systemImage: "camera")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if unsynced {
                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            Spacer(minLength: 4)
            DefectStatusBadge(defect: defect)
        }
        .padding(.vertical, 2)
    }
}

struct DefectHistoryView: View {
    let vehicleId: String
    let records: VehicleRecordsModel

    var body: some View {
        List(records.defects.filter { $0.status == .closed }) { defect in
            NavigationLink {
                DefectDetailView(vehicleId: vehicleId, defectId: defect.id ?? "")
            } label: {
                DefectRow(defect: defect)
            }
        }
        .navigationTitle("Closed Defects")
    }
}
