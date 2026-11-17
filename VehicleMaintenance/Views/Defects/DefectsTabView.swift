import SwiftUI

/// Everything that needs attention: open defects across the fleet and, for
/// managers, driver-logged services waiting for sign-off.
struct DefectsTabView: View {
    @Environment(FleetModel.self) private var fleet
    @State private var reviewing: (vehicle: Vehicle, record: ServiceRecord)?
    @State private var showingReview = false
    @State private var expanded = ExpandedGroups()

    var body: some View {
        NavigationStack {
            List {
                let groups = defectGroups
                if groups.isEmpty {
                    Section("Open Defects") {
                        Label("No open defects", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.secondary)
                    }
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        TruckGroupHeader(name: group.name, summary: group.summary,
                                         symbol: group.unsafeCount > 0 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                                         color: group.unsafeCount > 0 ? .red : .orange,
                                         isExpanded: expanded.binding(group.id, in: $expanded))
                        if expanded.open.contains(group.id) {
                            ForEach(group.entries) { entry in
                                NavigationLink {
                                    DefectDetailView(owner: entry.owner, defectId: entry.defect.id ?? "")
                                } label: {
                                    DefectRow(defect: entry.defect, context: entry.equipmentName)
                                }
                            }
                        }
                    } header: {
                        if index == 0 { Text("Open Defects") }
                    } footer: {
                        if index == groups.count - 1 {
                            Text("Tap a truck to see its problems. \(fleet.isManager ? "Only managers can close defects." : "A manager closes defects once they're repaired.")")
                        }
                    }
                }

                let ropeChanges = fleet.allPendingLengthChanges
                if !ropeChanges.isEmpty {
                    Section {
                        ForEach(ropeChanges, id: \.change.id) { entry in
                            NavigationLink {
                                EquipmentDetailView(equipmentId: entry.equipment.id ?? "")
                            } label: {
                                LengthChangeRow(change: entry.change, ropeName: fleet.context(for: .equipment(entry.equipment.id ?? "")))
                            }
                        }
                    } header: {
                        Text(fleet.isManager ? "Rope Length Changes to Approve" : "Rope Length Changes Awaiting Approval")
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
                                    Text(entry.vehicle.displayName).font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                                    ServiceRecordRow(record: entry.record, cost: nil, showsReviewHint: fleet.isManager, unit: entry.vehicle.unit)
                                }
                            }
                            .disabled(!fleet.isManager)
                        }
                    } header: {
                        Text(fleet.isManager ? "Services Awaiting Your Sign-Off" : "Services Awaiting Sign-Off")
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Defects")
            .expandGroupsForScreenshots(defectGroups.map(\.id), $expanded)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ExpandAllButton(ids: defectGroups.map(\.id), groups: $expanded)
                }
            }
            .syncStatusBanner()
            .sheet(isPresented: $showingReview) {
                if let reviewing {
                    ServiceReviewView(vehicle: reviewing.vehicle, record: reviewing.record)
                }
            }
        }
    }
}

extension DefectsTabView {
    /// Open defects grouped by truck. A saw's or rope's defects go with the truck it's on.
    struct DefectGroup: Identifiable {
        struct Entry: Identifiable {
            let owner: DefectOwner
            let defect: Defect
            /// The saw or rope's name; nil for the truck's own defects.
            let equipmentName: String?
            var id: String { "\(owner)-\(defect.id ?? "")" }
        }

        let id: String
        let name: String
        var entries: [Entry] = []

        var unsafeCount: Int { entries.filter(\.defect.unsafe).count }
        var summary: String {
            let count = entries.count == 1 ? "1 problem" : "\(entries.count) problems"
            let unsafe = unsafeCount
            return unsafe == 0 ? count : "\(count) · \(unsafe) unsafe"
        }
    }

    var defectGroups: [DefectGroup] {
        var groups: [String: DefectGroup] = [:]
        var order: [String] = []
        for entry in fleet.allOpenDefects {
            let truckId: String
            var equipmentName: String?
            switch entry.owner {
            case .vehicle(let id):
                truckId = id
            case .equipment(let id):
                let item = fleet.equipment(id)
                truckId = item.flatMap { fleet.vehicle($0.vehicleId)?.id } ?? "none"
                equipmentName = item?.displayName ?? "Equipment"
            }
            if groups[truckId] == nil {
                let name = truckId == "none" ? "Not on a truck" : fleet.vehicle(truckId)?.displayName ?? "Vehicle"
                groups[truckId] = DefectGroup(id: truckId, name: name)
                order.append(truckId)
            }
            groups[truckId]?.entries.append(.init(owner: entry.owner, defect: entry.defect, equipmentName: equipmentName))
        }
        // Trucks with unsafe problems first, then the most problems, then by name.
        return order.compactMap { groups[$0] }.sorted { lhs, rhs in
            if (lhs.unsafeCount > 0) != (rhs.unsafeCount > 0) { return lhs.unsafeCount > 0 }
            if lhs.entries.count != rhs.entries.count { return lhs.entries.count > rhs.entries.count }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

struct DefectRow: View {
    let defect: Defect
    var context: String?
    var unsynced = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: defect.unsafe ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(defect.status == .closed ? Color.secondary : defect.unsafe ? Color.red : Color.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                if let context {
                    Text(context).font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                }
                Text(defect.title).foregroundStyle(Color.primary)
                if !defect.details.isEmpty {
                    Text(defect.details).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text("\(defect.reportedByName) · \(defect.reportedAt.formatted(.relative(presentation: .named)))")
                    if !defect.photos.isEmpty {
                        Label("\(defect.photos.count)", systemImage: "camera")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
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
    let owner: DefectOwner
    let defects: [Defect]

    var body: some View {
        List(defects.filter { $0.status == .closed }) { defect in
            NavigationLink {
                DefectDetailView(owner: owner, defectId: defect.id ?? "")
            } label: {
                DefectRow(defect: defect)
            }
        }
        .navigationTitle("Closed Defects")
    }
}
