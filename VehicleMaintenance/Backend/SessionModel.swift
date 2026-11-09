import FirebaseFirestore
import Foundation

/// Everything about the signed-in user that isn't tied to one fleet:
/// which fleets they belong to, pending invites, and which fleet is open.
@MainActor
@Observable
final class SessionModel {
    let uid: String
    let email: String

    private(set) var memberships: [Membership] = []
    private(set) var membershipsLoaded = false
    private(set) var invites: [Invite] = []
    private(set) var fleetModel: FleetModel?

    private var listeners: [ListenerRegistration] = []
    private static let selectedFleetKey = "selectedFleetId"

    init(uid: String, email: String) {
        self.uid = uid
        self.email = email.lowercased()
        start()
    }

    private func start() {
        listeners.append(firestoreListen(FS.memberships(uid)) { [weak self] (items: [Membership], _) in
            guard let self else { return }
            memberships = items.sorted { $0.fleetName.localizedCaseInsensitiveCompare($1.fleetName) == .orderedAscending }
            membershipsLoaded = true
            restoreSelection()
        })

        let inviteQuery = FS.invites
            .whereField("email", isEqualTo: email)
            .whereField("status", isEqualTo: InviteStatus.pending.rawValue)
        listeners.append(firestoreListen(inviteQuery) { [weak self] (items: [Invite], _) in
            self?.invites = items
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        fleetModel?.stop()
        fleetModel = nil
    }

    // MARK: Fleet selection

    private func restoreSelection() {
        guard fleetModel == nil else { return }
        let saved = UserDefaults.standard.string(forKey: Self.selectedFleetKey)
        if let saved, memberships.contains(where: { $0.id == saved }) {
            select(fleetId: saved)
        } else if let first = memberships.first?.id {
            select(fleetId: first)
        }
    }

    func select(fleetId: String) {
        guard fleetModel?.fleetId != fleetId else { return }
        fleetModel?.stop()
        fleetModel = FleetModel(fleetId: fleetId, uid: uid, email: email) { [weak self] in
            self?.handleLostAccess(fleetId: fleetId)
        }
        UserDefaults.standard.set(fleetId, forKey: Self.selectedFleetKey)
    }

    /// Called when this user was removed from a fleet.
    private func handleLostAccess(fleetId: String) {
        FS.memberships(uid).document(fleetId).delete()
        ChecklistReminder.cancel(fleetId: fleetId)
        ReminderNotifications.sync([], prefix: fleetId)
        if fleetModel?.fleetId == fleetId {
            fleetModel?.stop()
            fleetModel = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedFleetKey)
            ErrorCenter.shared.message = "You no longer have access to that fleet."
            if let next = memberships.first(where: { $0.id != fleetId })?.id {
                select(fleetId: next)
            }
        }
    }

    // MARK: Creating and joining fleets

    func createFleet(name: String, profile: ProfileDraft) throws {
        let fleetRef = FS.fleets.document()
        let fleetId = fleetRef.documentID
        let trimmedName = name.trimmed

        let batch = FS.db.batch()
        try batch.setData(from: Fleet(name: trimmedName, createdBy: uid, photosEnabled: false,
                                      usage: FleetUsage(photoBytes: 0, photoCount: 0, recordCount: 0),
                                      distanceUnit: DistanceUnit.current.rawValue),
                          forDocument: fleetRef)
        try batch.setData(from: Member(role: .manager, displayName: profile.displayName.trimmed,
                                       phone: profile.phone.trimmed, email: email, seesAllVehicles: true),
                          forDocument: FS.members(fleetId).document(uid))
        try batch.setData(from: Membership(fleetName: trimmedName), forDocument: FS.memberships(uid).document(fleetId))
        commitInBackground(batch, "Creating fleet")

        // A starter checklist, written after the manager membership exists.
        let starter = FS.db.batch()
        try starter.setData(from: ChecklistDefaults.morningChecklist(), forDocument: FS.checklists(fleetId).document())
        commitInBackground(starter, "Creating starter checklist")

        UserDefaults.standard.set(fleetId, forKey: Self.selectedFleetKey)
        fleetModel?.stop()
        fleetModel = nil
        select(fleetId: fleetId)
    }

    func accept(_ invite: Invite, profile: ProfileDraft) throws {
        guard let inviteId = invite.id else { return }
        let batch = FS.db.batch()
        try batch.setData(from: Member(role: invite.role, displayName: profile.displayName.trimmed,
                                       phone: profile.phone.trimmed, email: email, seesAllVehicles: true,
                                       inviteId: inviteId),
                          forDocument: FS.members(invite.fleetId).document(uid))
        batch.updateData(["status": InviteStatus.accepted.rawValue,
                          "acceptedBy": uid,
                          "respondedAt": FieldValue.serverTimestamp()],
                         forDocument: FS.invites.document(inviteId))
        try batch.setData(from: Membership(fleetName: invite.fleetName),
                          forDocument: FS.memberships(uid).document(invite.fleetId))
        commitInBackground(batch, "Joining \(invite.fleetName)")
        select(fleetId: invite.fleetId)
    }

    func decline(_ invite: Invite) {
        guard let inviteId = invite.id else { return }
        FS.invites.document(inviteId).updateData([
            "status": InviteStatus.declined.rawValue,
            "respondedAt": FieldValue.serverTimestamp(),
        ]) { error in
            MainActor.assumeIsolated { ErrorCenter.shared.report(error, "Declining invite") }
        }
    }

    /// Leaves a fleet. The person's past inspections stay in the fleet's records.
    func leave(fleetId: String) async throws {
        let members = try await FS.members(fleetId).getDocuments().documents.compactMap { try? $0.data(as: Member.self) }
        let managers = members.filter { $0.role == .manager }
        if managers.count == 1, managers.first?.id == uid, members.count > 1 {
            throw AppError("You're the only manager. Make someone else a manager before leaving.")
        }
        if members.count == 1 {
            // Last person out: remove the fleet's data entirely while still a manager.
            try await FleetDeleter.deleteFleetData(fleetId: fleetId)
        }
        let batch = FS.db.batch()
        batch.deleteDocument(FS.members(fleetId).document(uid))
        batch.deleteDocument(FS.memberships(uid).document(fleetId))
        try await batch.commit()
        ChecklistReminder.cancel(fleetId: fleetId)
        ReminderNotifications.sync([], prefix: fleetId)
        if fleetModel?.fleetId == fleetId {
            fleetModel?.stop()
            fleetModel = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedFleetKey)
        }
    }

    /// Removes the person from every fleet and deletes their user data.
    /// Requires a connection. Call `AuthModel.deleteAuthUser()` afterwards.
    func deleteAllUserData() async throws {
        for membership in memberships {
            guard let fleetId = membership.id else { continue }
            let members = try await FS.members(fleetId).getDocuments().documents.compactMap { try? $0.data(as: Member.self) }
            let managers = members.filter { $0.role == .manager }
            if managers.count == 1, managers.first?.id == uid, members.count > 1 {
                throw AppError("You're the only manager of \(membership.fleetName). Make someone else a manager first.")
            }
        }
        for membership in memberships {
            guard let fleetId = membership.id else { continue }
            try await leave(fleetId: fleetId)
        }
        try await FS.user(uid).delete()
        stop()
    }
}
