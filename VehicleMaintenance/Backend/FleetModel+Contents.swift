import FirebaseFirestore
import Foundation

extension FleetModel {
    // MARK: Truck contents

    /// Managers, and the truck's lead, can change what's listed on a truck.
    func canEditContents(of vehicle: Vehicle?) -> Bool {
        guard let vehicle else { return false }
        return isManager || (vehicle.contentsEditorUid != nil && vehicle.contentsEditorUid == uid)
    }

    /// The person a manager picked to look after this truck's contents list, if they're still in the fleet.
    func truckLead(of vehicle: Vehicle?) -> Member? {
        vehicle?.contentsEditorUid.flatMap { member($0) }
    }

    /// Managers pick the truck lead. A driver who can't see every vehicle is also
    /// given access to this one, so they can open the list they're responsible for.
    func setTruckLead(_ memberId: String?, vehicle vehicleId: String) {
        var fields: [AnyHashable: Any] = [:]
        if let memberId {
            fields["contentsEditorUid"] = memberId
        } else {
            fields["contentsEditorUid"] = FieldValue.delete()
        }
        if let memberId, let person = member(memberId), person.role != .manager, !person.seesAllVehicles {
            fields["assignedUids"] = FieldValue.arrayUnion([memberId])
        }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: FS.vehicle(fleetId, vehicleId))
        commitInBackground(batch, "Changing truck lead")
    }

    func save(_ item: TruckItem, vehicle vehicleId: String) throws {
        var item = item
        item.name = item.name.trimmed
        item.location = item.location.trimmed
        item.notes = item.notes.trimmed
        item.updatedAt = .now
        item.updatedBy = uid
        item.updatedByName = myName
        let collection = FS.contents(fleetId, vehicleId)
        let ref = item.id.map { collection.document($0) } ?? collection.document()
        let batch = FS.db.batch()
        try batch.setData(from: item, forDocument: ref)
        commitInBackground(batch, "Saving \(item.name)")
    }

    func delete(_ item: TruckItem, vehicle vehicleId: String) {
        guard let id = item.id else { return }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.contents(fleetId, vehicleId).document(id))
        commitInBackground(batch, "Removing \(item.name)")
    }

    /// Copies another truck's items that this truck doesn't already have. Returns how many were added.
    func copyContents(from sourceVehicleId: String, to vehicleId: String, existing: [TruckItem]) async throws -> Int {
        let snapshot = try await FS.contents(fleetId, sourceVehicleId).getDocuments()
        let source = snapshot.documents.compactMap { try? $0.data(as: TruckItem.self) }
        let toAdd = TruckContents.missing(from: source, in: existing)
        guard !toAdd.isEmpty else { return 0 }
        let collection = FS.contents(fleetId, vehicleId)
        // Firestore batches are limited to 500 writes.
        for chunk in stride(from: 0, to: toAdd.count, by: 450).map({ Array(toAdd[$0..<min($0 + 450, toAdd.count)]) }) {
            let batch = FS.db.batch()
            for var item in chunk {
                item.id = nil
                item.updatedAt = .now
                item.updatedBy = uid
                item.updatedByName = myName
                try batch.setData(from: item, forDocument: collection.document())
            }
            commitInBackground(batch, "Copying truck contents")
        }
        return toAdd.count
    }
}
