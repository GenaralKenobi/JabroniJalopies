import FirebaseFirestore
import Foundation

extension FleetModel {
    // MARK: Equipment (managers)

    @discardableResult
    func add(_ item: Equipment) throws -> String {
        let ref = FS.equipmentCollection(fleetId).document()
        let batch = FS.db.batch()
        try batch.setData(from: item, forDocument: ref)
        commitInBackground(batch, "Adding \(item.type.displayName.lowercased())")
        return ref.documentID
    }

    /// Saves edits from the equipment form. Only the form's fields are written, so a
    /// move or an approved rope reduction made meanwhile isn't undone. The length is
    /// only written if the manager changed it.
    func update(_ edited: Equipment, from original: Equipment) {
        guard let id = original.id else { return }
        func optional(_ value: Double?) -> Any { value.map { $0 as Any } ?? FieldValue.delete() }
        var fields: [AnyHashable: Any] = [
            "name": edited.name,
            "make": edited.make,
            "model": edited.model,
            "serialNumber": edited.serialNumber,
            "notes": edited.notes,
            "diameter": edited.diameter,
            "barLengthInches": optional(edited.barLengthInches),
            "minLengthFeet": optional(edited.minLengthFeet),
        ]
        if edited.lengthFeet != original.lengthFeet {
            fields["lengthFeet"] = optional(edited.lengthFeet)
        }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: FS.equipment(fleetId, id))
        commitInBackground(batch, "Saving \(edited.displayName)")
    }

    func move(_ item: Equipment, to vehicleId: String) {
        guard let id = item.id else { return }
        let batch = FS.db.batch()
        batch.updateData(["vehicleId": vehicleId, "movedAt": Date.now], forDocument: FS.equipment(fleetId, id))
        commitInBackground(batch, "Moving \(item.displayName)")
    }

    /// Deletes a piece of equipment with its defects, photos and length history. Needs a connection.
    func delete(_ item: Equipment) async throws {
        guard let id = item.id else { return }
        try await FleetDeleter.deleteEquipment(fleetId: fleetId, equipmentId: id)
    }

    // MARK: Rope length

    /// Anyone can request a reduction; it applies only when a manager approves.
    func requestLengthReduction(of rope: Equipment, by feet: Double, reason: String) throws {
        guard let ropeId = rope.id, feet > 0 else { return }
        let now = Date.now
        let change = LengthChange(amountFeet: feet, reason: reason.trimmed, status: .pending, submittedBy: uid,
                                  submittedByName: myName, submittedAt: now, expireAt: Retention.expiry(from: now))
        let batch = FS.db.batch()
        try batch.setData(from: change, forDocument: FS.lengthChanges(fleetId, ropeId).document())
        commitInBackground(batch, "Submitting rope length change")
        bumpRecordCount(1)
    }

    func review(_ change: LengthChange, of rope: Equipment, approve: Bool) {
        guard let ropeId = rope.id, let changeId = change.id else { return }
        let batch = FS.db.batch()
        batch.updateData([
            "status": (approve ? ReviewStatus.approved : ReviewStatus.rejected).rawValue,
            "reviewedBy": uid,
            "reviewedByName": myName,
            "reviewedAt": Date.now,
        ], forDocument: FS.lengthChanges(fleetId, ropeId).document(changeId))
        if approve {
            batch.updateData(["lengthFeet": FieldValue.increment(-change.amountFeet)], forDocument: FS.equipment(fleetId, ropeId))
        }
        commitInBackground(batch, approve ? "Approving length change" : "Rejecting length change")
    }

    // MARK: Chains

    /// Managers set which chain sizes a truck carries. Existing counts are kept.
    func setChainSizes(_ sizes: [ChainSize], vehicleId: String) throws {
        let batch = FS.db.batch()
        batch.setData(["sizes": try FS.encode(sizes), "updatedAt": Date.now],
                      forDocument: FS.chainInventory(fleetId, vehicleId), merge: true)
        commitInBackground(batch, "Saving chain sizes")
    }

    /// End of day: dull chains (to resharpen) and thrown-away chains come off the truck.
    func emptyUsedChainBox(vehicleId: String, sizes: [ChainSize], dull: [String: Int], discarded: [String: Int]) throws {
        let items = sizes.map { size in
            ChainLogItem(sizeKey: size.key, inches: size.inches, dull: dull[size.key] ?? 0,
                         discarded: discarded[size.key] ?? 0, added: 0, adjustment: 0)
        }
        try writeChainLog(.usedBox, items: items, vehicleId: vehicleId)
    }

    /// Anyone can record chains put on the truck.
    func addChains(vehicleId: String, sizes: [ChainSize], added: [String: Int]) throws {
        let items = sizes.map { size in
            ChainLogItem(sizeKey: size.key, inches: size.inches, dull: 0, discarded: 0,
                         added: added[size.key] ?? 0, adjustment: 0)
        }
        try writeChainLog(.added, items: items, vehicleId: vehicleId)
    }

    /// Managers set the counts to what's actually on the truck. Applied as an
    /// adjustment, so logs still syncing from other phones aren't lost.
    func correctChainCounts(vehicleId: String, inventory: ChainInventory, actual: [String: Int]) throws {
        let items = inventory.sortedSizes.map { size in
            ChainLogItem(sizeKey: size.key, inches: size.inches, dull: 0, discarded: 0, added: 0,
                         adjustment: (actual[size.key] ?? inventory.count(size)) - inventory.count(size))
        }
        try writeChainLog(.correction, items: items, vehicleId: vehicleId)
    }

    private func writeChainLog(_ kind: ChainLogKind, items: [ChainLogItem], vehicleId: String) throws {
        let meaningful = items.filter { $0.dull != 0 || $0.discarded != 0 || $0.added != 0 || $0.adjustment != 0 }
        guard !meaningful.isEmpty else { throw AppError("Enter at least one number.") }
        let now = Date.now
        let log = ChainLog(kind: kind, items: meaningful, loggedBy: uid, loggedByName: myName, loggedAt: now,
                           expireAt: Retention.expiry(from: now))
        let batch = FS.db.batch()
        try batch.setData(from: log, forDocument: FS.chainLogs(fleetId, vehicleId).document())
        var counts: [AnyHashable: Any] = ["updatedAt": now]
        for item in meaningful where item.countChange != 0 {
            counts[FieldPath(["counts", item.sizeKey])] = FieldValue.increment(Int64(item.countChange))
        }
        batch.updateData(counts, forDocument: FS.chainInventory(fleetId, vehicleId))
        commitInBackground(batch, kind.label)
        bumpRecordCount(1)
    }

    /// Chain logs across every truck since a date (manager totals). Needs a connection for fresh data.
    func chainLogs(since date: Date) async throws -> [ChainLog] {
        var logs: [ChainLog] = []
        for vehicle in vehicles {
            guard let vehicleId = vehicle.id else { continue }
            let snapshot = try await FS.chainLogs(fleetId, vehicleId)
                .whereField("loggedAt", isGreaterThanOrEqualTo: date)
                .getDocuments()
            logs += snapshot.documents.compactMap { try? $0.data(as: ChainLog.self) }
        }
        return logs
    }
}
