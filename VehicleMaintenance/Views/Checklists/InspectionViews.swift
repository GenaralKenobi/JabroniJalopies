import SwiftUI

struct InspectionRow: View {
    let inspection: Inspection
    var unsynced = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: inspection.unsafe ? "exclamationmark.octagon.fill"
                  : inspection.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(inspection.unsafe ? Color.red : inspection.failedCount > 0 ? Color.orange : Color.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(inspection.checklistName).foregroundStyle(Color.primary)
                Text("\(inspection.performedByName) · \(inspection.completedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                if unsynced {
                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            if inspection.failedCount > 0 {
                Text("\(inspection.failedCount) failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(inspection.unsafe ? Color.red : Color.orange)
            }
        }
    }
}

struct InspectionListView: View {
    let vehicleId: String
    let records: VehicleRecordsModel

    var body: some View {
        List(records.inspections) { inspection in
            NavigationLink {
                InspectionDetailView(vehicleId: vehicleId, inspection: inspection)
            } label: {
                InspectionRow(inspection: inspection, unsynced: records.unsyncedInspectionIds.contains(inspection.id ?? ""))
            }
        }
        .navigationTitle("Checklists")
    }
}

struct InspectionDetailView: View {
    let vehicleId: String
    let inspection: Inspection

    var body: some View {
        List {
            Section {
                LabeledContent("Checklist", value: inspection.checklistName)
                LabeledContent("Completed by", value: inspection.performedByName)
                LabeledContent("Completed", value: inspection.completedAt.formatted(date: .abbreviated, time: .shortened))
                if let received = inspection.receivedAt, received.timeIntervalSince(inspection.completedAt) > 10 * 60 {
                    LabeledContent("Synced", value: received.formatted(date: .abbreviated, time: .shortened))
                    Text("Completed offline and uploaded later.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                if let odometer = inspection.odometer {
                    LabeledContent("Odometer", value: odometer.formatted())
                }
            }

            if inspection.unsafe {
                Section {
                    Label("Safety items failed — vehicle marked unsafe to drive", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section("Results") {
                ForEach(inspection.results, id: \.itemId) { result in
                    let row = HStack(alignment: .top, spacing: 12) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                            if let reading = result.reading {
                                Text("\(reading.formatted()) \(result.readingLabel ?? "")")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                            if let note = result.note {
                                Text(note).font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    if let defectId = result.defectId {
                        NavigationLink {
                            DefectDetailView(vehicleId: vehicleId, defectId: defectId)
                        } label: { row }
                    } else {
                        row
                    }
                }
            }
        }
        .navigationTitle(inspection.completedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}
