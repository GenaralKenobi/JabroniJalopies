import FirebaseFirestore
import FirebaseStorage
import Foundation

// All writes go to Firestore's local cache first and sync in the background,
// so every action here works offline unless it says otherwise.

extension FleetModel {
    // MARK: Fleet

    func renameFleet(_ name: String) {
        let batch = FS.db.batch()
        batch.updateData(["name": name.trimmed], forDocument: FS.fleet(fleetId))
        batch.setData(["fleetName": name.trimmed], forDocument: FS.memberships(uid).document(fleetId), merge: true)
        commitInBackground(batch, "Renaming fleet")
    }

    func setPhotosEnabled(_ enabled: Bool) {
        let batch = FS.db.batch()
        batch.updateData(["photosEnabled": enabled], forDocument: FS.fleet(fleetId))
        commitInBackground(batch, "Updating photo setting")
    }

    func bumpRecordCount(_ count: Int, in batch: WriteBatch) {
        guard count != 0 else { return }
        batch.updateData(["usage.recordCount": FieldValue.increment(Int64(count))], forDocument: FS.fleet(fleetId))
    }

    // MARK: Vehicles

    /// Creates or updates a vehicle (managers). Returns its id.
    @discardableResult
    func save(_ vehicle: Vehicle) throws -> String {
        let ref = vehicle.id.map { FS.vehicle(fleetId, $0) } ?? FS.vehicles(fleetId).document()
        let batch = FS.db.batch()
        try batch.setData(from: vehicle, forDocument: ref)
        commitInBackground(batch, "Saving vehicle")
        return ref.documentID
    }

    /// Deletes a vehicle and all of its records. Needs a connection.
    func delete(_ vehicle: Vehicle) async throws {
        guard let id = vehicle.id else { return }
        try await FleetDeleter.deleteVehicle(fleetId: fleetId, vehicleId: id)
    }

    /// Drivers and managers can record the odometer.
    func updateOdometer(of vehicle: Vehicle, to value: Int) {
        guard let id = vehicle.id else { return }
        let batch = FS.db.batch()
        batch.updateData([
            "odometer": value,
            "odometerUpdatedAt": FieldValue.serverTimestamp(),
            "odometerUpdatedBy": uid,
        ], forDocument: FS.vehicle(fleetId, id))
        commitInBackground(batch, "Updating odometer")
    }

    func updateSpecs(of vehicleId: String, to sections: [SpecSection]) throws {
        let batch = FS.db.batch()
        batch.updateData(["specSections": try FS.encode(sections)], forDocument: FS.vehicle(fleetId, vehicleId))
        commitInBackground(batch, "Saving specs")
    }

    // MARK: Members and visibility

    func updateMyProfile(_ profile: ProfileDraft) {
        let batch = FS.db.batch()
        batch.updateData([
            "displayName": profile.displayName.trimmed,
            "phone": profile.phone.trimmed,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: FS.members(fleetId).document(uid))
        commitInBackground(batch, "Saving profile")
    }

    func setRole(_ role: FleetRole, for member: Member) throws {
        guard let memberId = member.id else { return }
        if member.role == .manager, role != .manager, managers.count <= 1 {
            throw AppError("A fleet needs at least one manager.")
        }
        let batch = FS.db.batch()
        batch.updateData(["role": role.rawValue], forDocument: FS.members(fleetId).document(memberId))
        commitInBackground(batch, "Changing role")
    }

    func setSeesAllVehicles(_ seesAll: Bool, for member: Member) {
        guard let memberId = member.id else { return }
        let batch = FS.db.batch()
        batch.updateData(["seesAllVehicles": seesAll], forDocument: FS.members(fleetId).document(memberId))
        commitInBackground(batch, "Changing vehicle access")
    }

    func setAssigned(_ assigned: Bool, member memberId: String, vehicle vehicleId: String) {
        let batch = FS.db.batch()
        batch.updateData([
            "assignedUids": assigned ? FieldValue.arrayUnion([memberId]) : FieldValue.arrayRemove([memberId]),
        ], forDocument: FS.vehicle(fleetId, vehicleId))
        commitInBackground(batch, "Changing vehicle assignment")
    }

    func remove(_ member: Member) throws {
        guard let memberId = member.id else { return }
        if member.role == .manager, managers.count <= 1 {
            throw AppError("A fleet needs at least one manager.")
        }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.members(fleetId).document(memberId))
        for vehicle in vehicles where vehicle.assignedUids.contains(memberId) {
            guard let vehicleId = vehicle.id else { continue }
            batch.updateData(["assignedUids": FieldValue.arrayRemove([memberId])], forDocument: FS.vehicle(fleetId, vehicleId))
        }
        commitInBackground(batch, "Removing member")
    }

    // MARK: Invites

    func invite(email: String, role: FleetRole) throws -> Invite {
        let normalized = email.trimmed.lowercased()
        guard normalized.contains("@"), normalized.contains(".") else { throw AppError("Enter a valid email address.") }
        if members.contains(where: { $0.email == normalized }) {
            throw AppError("\(normalized) is already in this fleet.")
        }
        if invites.contains(where: { $0.email == normalized }) {
            throw AppError("\(normalized) has already been invited.")
        }
        let invite = Invite(fleetId: fleetId, fleetName: fleet?.name ?? "", email: normalized, role: role,
                            invitedBy: uid, invitedByName: myName, status: .pending)
        let batch = FS.db.batch()
        try batch.setData(from: invite, forDocument: FS.invites.document())
        commitInBackground(batch, "Sending invite")
        return invite
    }

    func revoke(_ invite: Invite) {
        guard let id = invite.id else { return }
        let batch = FS.db.batch()
        batch.updateData(["status": InviteStatus.revoked.rawValue, "respondedAt": FieldValue.serverTimestamp()],
                         forDocument: FS.invites.document(id))
        commitInBackground(batch, "Revoking invite")
    }

    // MARK: Reminders (managers)

    func save(_ reminder: Reminder, vehicleId: String) throws {
        let ref = reminder.id.map { FS.reminders(fleetId, vehicleId).document($0) } ?? FS.reminders(fleetId, vehicleId).document()
        let batch = FS.db.batch()
        try batch.setData(from: reminder, forDocument: ref)
        commitInBackground(batch, "Saving reminder")
    }

    func delete(_ reminder: Reminder, vehicleId: String) {
        guard let id = reminder.id else { return }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.reminders(fleetId, vehicleId).document(id))
        commitInBackground(batch, "Deleting reminder")
    }

    // MARK: Service records

    /// Managers' entries are approved immediately; drivers' entries wait for sign-off.
    func logService(_ draft: ServiceRecord, cost: Double?, vehicle: Vehicle) throws {
        guard let vehicleId = vehicle.id else { return }
        var record = draft
        let ref = record.id.map { FS.services(fleetId, vehicleId).document($0) } ?? FS.services(fleetId, vehicleId).document()
        let isNew = record.id == nil
        if isNew {
            record.createdBy = uid
            record.createdByName = myName
            record.status = isManager ? .approved : .pending
            if isManager {
                record.reviewedBy = uid
                record.reviewedByName = myName
                record.reviewedAt = .now
            }
        }
        record.expireAt = Retention.expiry(from: record.date)

        let batch = FS.db.batch()
        try batch.setData(from: record, forDocument: ref)
        if isManager, let cost {
            try batch.setData(from: ServiceCost(amount: cost, expireAt: record.expireAt),
                              forDocument: FS.costs(fleetId, vehicleId).document(ref.documentID))
        }
        if isNew {
            bumpRecordCount(1, in: batch)
        }
        if record.status == .approved {
            applyApprovedService(record, vehicle: vehicle, in: batch)
        }
        commitInBackground(batch, "Saving service record")
    }

    func approve(_ record: ServiceRecord, vehicle: Vehicle, cost: Double?, note: String) throws {
        guard let vehicleId = vehicle.id, let id = record.id else { return }
        var approved = record
        approved.status = .approved
        approved.reviewedBy = uid
        approved.reviewedByName = myName
        approved.reviewedAt = .now
        approved.reviewNote = note.trimmed.isEmpty ? nil : note.trimmed

        let batch = FS.db.batch()
        try batch.setData(from: approved, forDocument: FS.services(fleetId, vehicleId).document(id))
        if let cost {
            try batch.setData(from: ServiceCost(amount: cost, expireAt: record.expireAt),
                              forDocument: FS.costs(fleetId, vehicleId).document(id))
        }
        applyApprovedService(approved, vehicle: vehicle, in: batch)
        commitInBackground(batch, "Approving service")
    }

    func reject(_ record: ServiceRecord, vehicleId: String, note: String) {
        guard let id = record.id else { return }
        let batch = FS.db.batch()
        batch.updateData([
            "status": ServiceStatus.rejected.rawValue,
            "reviewedBy": uid,
            "reviewedByName": myName,
            "reviewedAt": FieldValue.serverTimestamp(),
            "reviewNote": note.trimmed,
        ], forDocument: FS.services(fleetId, vehicleId).document(id))
        commitInBackground(batch, "Rejecting service")
    }

    func delete(_ record: ServiceRecord, vehicleId: String) {
        guard let id = record.id else { return }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.services(fleetId, vehicleId).document(id))
        if isManager {
            batch.deleteDocument(FS.costs(fleetId, vehicleId).document(id))
        }
        commitInBackground(batch, "Deleting service record")
    }

    /// An approved service resets matching reminders and advances the odometer.
    private func applyApprovedService(_ record: ServiceRecord, vehicle: Vehicle, in batch: WriteBatch) {
        guard let vehicleId = vehicle.id else { return }
        let calendar = Calendar.current
        for reminder in reminders[vehicleId] ?? []
        where reminder.matches(serviceType: record.serviceType, title: record.title)
            && calendar.startOfDay(for: record.date) >= calendar.startOfDay(for: reminder.lastServiceDate) {
            guard let reminderId = reminder.id else { continue }
            batch.updateData([
                "lastServiceDate": record.date,
                "lastServiceOdometer": record.odometer,
            ], forDocument: FS.reminders(fleetId, vehicleId).document(reminderId))
        }
        if record.odometer > vehicle.odometer {
            batch.updateData([
                "odometer": record.odometer,
                "odometerUpdatedAt": FieldValue.serverTimestamp(),
                "odometerUpdatedBy": uid,
            ], forDocument: FS.vehicle(fleetId, vehicleId))
        }
    }

    // MARK: Checklists (managers)

    func save(_ checklist: ChecklistTemplate) throws {
        var updated = checklist
        updated.updatedAt = .now
        let ref = checklist.id.map { FS.checklists(fleetId).document($0) } ?? FS.checklists(fleetId).document()
        let batch = FS.db.batch()
        try batch.setData(from: updated, forDocument: ref)
        commitInBackground(batch, "Saving checklist")
    }

    func delete(_ checklist: ChecklistTemplate) {
        guard let id = checklist.id else { return }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.checklists(fleetId).document(id))
        commitInBackground(batch, "Deleting checklist")
    }

    // MARK: Inspections and defects

    /// Saves a completed checklist. The text records are written in one batch so
    /// a problem is flagged as soon as any signal is available; photos are queued
    /// separately and attach whenever they finish uploading.
    func submit(_ plan: InspectionPlan, vehicle: Vehicle, odometer: Int?, photos: [String: Data],
                repeatingItemIds: [String] = []) throws {
        guard let vehicleId = vehicle.id else { return }
        let batch = FS.db.batch()
        try batch.setData(from: plan.inspection, forDocument: FS.inspections(fleetId, vehicleId).document(plan.inspectionId))

        // Repeating items count as done whether they passed or failed (a failure becomes a defect).
        if !repeatingItemIds.isEmpty {
            var lastDone: [String: Date] = [:]
            repeatingItemIds.forEach { lastDone[$0] = plan.inspection.completedAt }
            batch.setData(["lastDone": lastDone], forDocument: FS.checklistState(fleetId, vehicleId), merge: true)
        }

        for newDefect in plan.newDefects {
            try batch.setData(from: newDefect.defect, forDocument: FS.defects(fleetId, vehicleId).document(newDefect.id))
        }

        for update in plan.defectUpdates {
            var fields: [AnyHashable: Any] = [
                "history": FieldValue.arrayUnion([try FS.encode(update.event)]),
                "updatedAt": Date.now,
            ]
            if let status = update.newStatus {
                fields["status"] = status.rawValue
            }
            for photoId in update.photoIds {
                fields["photos.\(photoId)"] = try FS.encode(pendingPhoto())
            }
            batch.updateData(fields, forDocument: FS.defects(fleetId, vehicleId).document(update.defectId))
        }

        if let odometer, odometer > vehicle.odometer {
            batch.updateData([
                "odometer": odometer,
                "odometerUpdatedAt": FieldValue.serverTimestamp(),
                "odometerUpdatedBy": uid,
            ], forDocument: FS.vehicle(fleetId, vehicleId))
        }
        bumpRecordCount(plan.recordCount, in: batch)
        commitInBackground(batch, "Saving checklist")

        enqueuePhotos(photos, plan: plan, vehicleId: vehicleId)
    }

    private func enqueuePhotos(_ photos: [String: Data], plan: InspectionPlan, vehicleId: String) {
        var defectForPhoto: [String: String] = [:]
        for newDefect in plan.newDefects {
            newDefect.defect.photos.keys.forEach { defectForPhoto[$0] = newDefect.id }
        }
        for update in plan.defectUpdates {
            update.photoIds.forEach { defectForPhoto[$0] = update.defectId }
        }
        for (photoId, data) in photos {
            guard let defectId = defectForPhoto[photoId] else { continue }
            PhotoUploadQueue.shared.enqueue(data: data, photoId: photoId, fleetId: fleetId,
                                            owner: .vehicle(vehicleId), defectId: defectId)
        }
    }

    func pendingPhoto() -> DefectPhoto {
        DefectPhoto(status: .pending, path: nil, addedBy: uid, addedByName: myName, addedAt: .now, byteCount: nil)
    }

    /// Reports a problem outside of a checklist, on a truck or a piece of equipment.
    func reportDefect(owner: DefectOwner, title: String, details: String, unsafe: Bool, photos: [String: Data]) throws {
        let ref = owner.defects(fleetId: fleetId).document()
        let now = Date.now
        var photoEntries: [String: DefectPhoto] = [:]
        photos.keys.forEach { photoEntries[$0] = pendingPhoto() }
        let defect = Defect(
            itemId: nil, title: title.trimmed, details: details.trimmed, unsafe: unsafe, status: .open,
            reportedBy: uid, reportedByName: myName, reportedAt: now,
            history: [DefectEvent(type: .reported, by: uid, byName: myName, at: now,
                                  note: details.trimmed.isEmpty ? nil : details.trimmed)],
            photos: photoEntries, updatedAt: now)
        let batch = FS.db.batch()
        try batch.setData(from: defect, forDocument: ref)
        bumpRecordCount(1, in: batch)
        commitInBackground(batch, "Reporting problem")
        for (photoId, data) in photos {
            PhotoUploadQueue.shared.enqueue(data: data, photoId: photoId, fleetId: fleetId,
                                            owner: owner, defectId: ref.documentID)
        }
    }

    /// Driver actions on an open defect.
    func addEvent(_ type: DefectEventType, note: String, to defect: Defect, owner: DefectOwner) throws {
        guard let defectId = defect.id else { return }
        let event = DefectEvent(type: type, by: uid, byName: myName, at: .now, note: note.trimmed.isEmpty ? nil : note.trimmed)
        var fields: [AnyHashable: Any] = [
            "history": FieldValue.arrayUnion([try FS.encode(event)]),
            "updatedAt": Date.now,
        ]
        switch type {
        case .reportedFixed:
            fields["status"] = DefectStatus.reportedFixed.rawValue
        case .confirmed where defect.status == .reportedFixed:
            fields["status"] = DefectStatus.open.rawValue
        default:
            break
        }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: owner.defects(fleetId: fleetId).document(defectId))
        commitInBackground(batch, "Updating defect")
    }

    /// Managers close a defect as repaired or not a defect.
    func close(_ defect: Defect, owner: DefectOwner, resolution: DefectResolution, note: String) throws {
        guard let defectId = defect.id else { return }
        let now = Date.now
        let event = DefectEvent(type: resolution == .repaired ? .repaired : .notDefect, by: uid, byName: myName,
                                at: now, note: note.trimmed.isEmpty ? nil : note.trimmed)
        let batch = FS.db.batch()
        batch.updateData([
            "status": DefectStatus.closed.rawValue,
            "resolution": resolution.rawValue,
            "closedAt": now,
            "closedBy": uid,
            "closedByName": myName,
            "expireAt": Retention.expiry(from: now),
            "updatedAt": now,
            "history": FieldValue.arrayUnion([try FS.encode(event)]),
        ], forDocument: owner.defects(fleetId: fleetId).document(defectId))
        commitInBackground(batch, "Closing defect")
    }

    func reopen(_ defect: Defect, owner: DefectOwner, note: String) throws {
        guard let defectId = defect.id else { return }
        let event = DefectEvent(type: .reopened, by: uid, byName: myName, at: .now, note: note.trimmed.isEmpty ? nil : note.trimmed)
        let batch = FS.db.batch()
        batch.updateData([
            "status": DefectStatus.open.rawValue,
            "resolution": FieldValue.delete(),
            "closedAt": FieldValue.delete(),
            "closedBy": FieldValue.delete(),
            "closedByName": FieldValue.delete(),
            "expireAt": FieldValue.delete(),
            "updatedAt": Date.now,
            "history": FieldValue.arrayUnion([try FS.encode(event)]),
        ], forDocument: owner.defects(fleetId: fleetId).document(defectId))
        commitInBackground(batch, "Reopening defect")
    }

    /// Managers can mark an equipment defect "do not use" (or clear it) after it's reported.
    func setUnsafe(_ unsafe: Bool, on defect: Defect, owner: DefectOwner) {
        guard let defectId = defect.id else { return }
        let batch = FS.db.batch()
        batch.updateData(["unsafe": unsafe, "updatedAt": Date.now],
                         forDocument: owner.defects(fleetId: fleetId).document(defectId))
        commitInBackground(batch, "Updating defect")
    }

    func addPhotos(_ photos: [String: Data], to defect: Defect, owner: DefectOwner) throws {
        guard let defectId = defect.id, !photos.isEmpty else { return }
        var fields: [AnyHashable: Any] = ["updatedAt": Date.now]
        for photoId in photos.keys {
            fields["photos.\(photoId)"] = try FS.encode(pendingPhoto())
        }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: owner.defects(fleetId: fleetId).document(defectId))
        commitInBackground(batch, "Adding photo")
        for (photoId, data) in photos {
            PhotoUploadQueue.shared.enqueue(data: data, photoId: photoId, fleetId: fleetId,
                                            owner: owner, defectId: defectId)
        }
    }

    // MARK: Data cleanup (managers, needs a connection)

    struct PurgeSummary {
        var inspections = 0
        var defects = 0
        var services = 0
        var photos = 0
        var chainLogs = 0
        var lengthChanges = 0
        var total: Int { inspections + defects + services + chainLogs + lengthChanges }
    }

    /// Deletes inspections, closed defects (with photos) and reviewed service
    /// records dated before `cutoff`, across every vehicle in the fleet.
    func purgeRecords(before cutoff: Date) async throws -> PurgeSummary {
        var summary = PurgeSummary()
        var freedPhotoBytes: Int64 = 0
        let vehicleIds = try await FS.vehicles(fleetId).getDocuments().documents.map(\.documentID)

        for vehicleId in vehicleIds {
            summary.inspections += try await FleetDeleter.deleteAll(
                FS.inspections(fleetId, vehicleId).whereField("completedAt", isLessThan: cutoff))

            let oldDefects = try await FS.defects(fleetId, vehicleId)
                .whereField("closedAt", isLessThan: cutoff).getDocuments()
            for document in oldDefects.documents {
                if let defect = try? document.data(as: Defect.self) {
                    for photo in defect.photos.values {
                        guard let path = photo.path else { continue }
                        try? await Storage.storage().reference(withPath: path).delete()
                        summary.photos += 1
                        freedPhotoBytes += Int64(photo.byteCount ?? 0)
                    }
                }
                try await document.reference.delete()
                summary.defects += 1
            }

            let oldServices = try await FS.services(fleetId, vehicleId)
                .whereField("date", isLessThan: cutoff).getDocuments()
            for document in oldServices.documents {
                guard (try? document.data(as: ServiceRecord.self))?.status != .pending else { continue }
                let batch = FS.db.batch()
                batch.deleteDocument(document.reference)
                batch.deleteDocument(FS.costs(fleetId, vehicleId).document(document.documentID))
                try await batch.commit()
                summary.services += 1
            }
        }

        for vehicleId in vehicleIds {
            summary.chainLogs += try await FleetDeleter.deleteAll(
                FS.chainLogs(fleetId, vehicleId).whereField("loggedAt", isLessThan: cutoff))
        }

        let equipmentIds = try await FS.equipmentCollection(fleetId).getDocuments().documents.map(\.documentID)
        for equipmentId in equipmentIds {
            let oldDefects = try await FS.equipmentDefects(fleetId, equipmentId)
                .whereField("closedAt", isLessThan: cutoff).getDocuments()
            for document in oldDefects.documents {
                if let defect = try? document.data(as: Defect.self) {
                    for photo in defect.photos.values {
                        guard let path = photo.path else { continue }
                        try? await Storage.storage().reference(withPath: path).delete()
                        summary.photos += 1
                        freedPhotoBytes += Int64(photo.byteCount ?? 0)
                    }
                }
                try await document.reference.delete()
                summary.defects += 1
            }
            let oldChanges = try await FS.lengthChanges(fleetId, equipmentId)
                .whereField("submittedAt", isLessThan: cutoff).getDocuments()
            for document in oldChanges.documents
            where (try? document.data(as: LengthChange.self))?.status != .pending {
                try await document.reference.delete()
                summary.lengthChanges += 1
            }
        }

        try await FS.fleet(fleetId).updateData([
            "usage.recordCount": FieldValue.increment(Int64(-summary.total)),
            "usage.photoBytes": FieldValue.increment(-freedPhotoBytes),
            "usage.photoCount": FieldValue.increment(Int64(-summary.photos)),
        ])
        return summary
    }
}
