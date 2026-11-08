import FirebaseFirestore
import Foundation

/// Live data for the fleet that's currently open. Firestore listeners keep it
/// up to date, and they keep working from the on-device cache when offline.
@MainActor
@Observable
final class FleetModel {
    let fleetId: String
    let uid: String
    let email: String

    private(set) var fleet: Fleet?
    private(set) var members: [Member] = []
    private(set) var vehicles: [Vehicle] = []
    private(set) var vehiclesLoaded = false
    private(set) var checklists: [ChecklistTemplate] = []
    private(set) var invites: [Invite] = []
    /// Keyed by vehicle id.
    private(set) var reminders: [String: [Reminder]] = [:]
    private(set) var openDefects: [String: [Defect]] = [:]
    private(set) var pendingServices: [String: [ServiceRecord]] = [:]

    private let onLostAccess: () -> Void
    private var baseListeners: [ListenerRegistration] = []
    private var vehicleListener: ListenerRegistration?
    private var vehicleQueryKey: String?
    private var inviteListener: ListenerRegistration?
    private var perVehicle: [String: [ListenerRegistration]] = [:]
    private var stopped = false

    init(fleetId: String, uid: String, email: String, onLostAccess: @escaping () -> Void) {
        self.fleetId = fleetId
        self.uid = uid
        self.email = email
        self.onLostAccess = onLostAccess
        start()
    }

    // MARK: Derived state

    var me: Member? { members.first { $0.id == uid } }
    var isManager: Bool { me?.role == .manager }
    var myName: String { me?.displayName ?? email }
    var person: InspectionPlanner.Person { .init(uid: uid, name: myName) }
    var photosEnabled: Bool { fleet?.photosEnabled ?? false }
    var usage: UsageReport { UsageReport(usage: fleet?.usage) }

    var sortedVehicles: [Vehicle] {
        vehicles.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var managers: [Member] { members.filter { $0.role == .manager } }

    func vehicle(_ id: String?) -> Vehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id }
    }

    func member(_ uid: String) -> Member? { members.first { $0.id == uid } }

    func condition(of vehicleId: String?) -> VehicleCondition {
        guard let vehicleId else { return .ok }
        return VehicleCondition(openDefects: openDefects[vehicleId] ?? [])
    }

    func reminderStatus(of vehicle: Vehicle) -> DueStatus? {
        guard let id = vehicle.id, let items = reminders[id], !items.isEmpty else { return nil }
        return items.map { $0.status(currentOdometer: vehicle.odometer) }.max()
    }

    func checklists(for vehicleId: String) -> [ChecklistTemplate] {
        checklists.filter { $0.applies(to: vehicleId) }
    }

    /// Open defects across all visible vehicles, unsafe and newest first.
    var allOpenDefects: [(vehicle: Vehicle, defect: Defect)] {
        sortedVehicles.flatMap { vehicle in
            (openDefects[vehicle.id ?? ""] ?? []).map { (vehicle: vehicle, defect: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.defect.unsafe != rhs.defect.unsafe { return lhs.defect.unsafe }
            return lhs.defect.reportedAt > rhs.defect.reportedAt
        }
    }

    var allPendingServices: [(vehicle: Vehicle, record: ServiceRecord)] {
        sortedVehicles.flatMap { vehicle in
            (pendingServices[vehicle.id ?? ""] ?? []).map { (vehicle: vehicle, record: $0) }
        }
        .sorted { $0.record.date > $1.record.date }
    }

    var allReminders: [(vehicle: Vehicle, reminder: Reminder)] {
        sortedVehicles.flatMap { vehicle in
            (reminders[vehicle.id ?? ""] ?? []).map { (vehicle: vehicle, reminder: $0) }
        }
    }

    // MARK: Listeners

    private func start() {
        baseListeners.append(FS.fleet(fleetId).addSnapshotListener { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.handleListenerError(error); return }
                guard let snapshot else { return }
                if !snapshot.exists && !snapshot.metadata.isFromCache {
                    self.lostAccess()
                    return
                }
                self.fleet = try? snapshot.data(as: Fleet.self)
                self.checkUsageAlert()
            }
        })

        baseListeners.append(firestoreListen(FS.members(fleetId), onError: { [weak self] in self?.handleListenerError($0) }) {
            [weak self] (items: [Member], snapshot) in
            guard let self else { return }
            members = items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            if me == nil && !snapshot.metadata.isFromCache {
                lostAccess()
                return
            }
            configureRoleDependentListeners()
            checkUsageAlert()
        })

        baseListeners.append(firestoreListen(FS.checklists(fleetId)) { [weak self] (items: [ChecklistTemplate], _) in
            self?.checklists = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        })
    }

    func stop() {
        stopped = true
        baseListeners.forEach { $0.remove() }
        baseListeners.removeAll()
        vehicleListener?.remove()
        inviteListener?.remove()
        perVehicle.values.flatMap { $0 }.forEach { $0.remove() }
        perVehicle.removeAll()
    }

    private func handleListenerError(_ error: Error) {
        if error.isPermissionDenied {
            lostAccess()
        } else {
            ErrorCenter.shared.report(error, "Syncing fleet")
        }
    }

    private func lostAccess() {
        guard !stopped else { return }
        stop()
        onLostAccess()
    }

    /// The vehicle query depends on the person's role and visibility.
    private func configureRoleDependentListeners() {
        guard let me else { return }
        let seesAll = me.role == .manager || me.seesAllVehicles
        let key = seesAll ? "all" : "assigned"
        if key != vehicleQueryKey {
            vehicleQueryKey = key
            vehicleListener?.remove()
            let query: Query = seesAll
                ? FS.vehicles(fleetId)
                : FS.vehicles(fleetId).whereField("assignedUids", arrayContains: uid)
            vehicleListener = firestoreListen(query, onError: { [weak self] in self?.handleListenerError($0) }) {
                [weak self] (items: [Vehicle], _) in
                guard let self else { return }
                vehicles = items
                vehiclesLoaded = true
                updatePerVehicleListeners()
            }
        }

        if me.role == .manager, inviteListener == nil {
            let query = FS.invites
                .whereField("fleetId", isEqualTo: fleetId)
                .whereField("status", isEqualTo: InviteStatus.pending.rawValue)
            inviteListener = firestoreListen(query) { [weak self] (items: [Invite], _) in
                self?.invites = items.sorted { $0.email < $1.email }
            }
        } else if me.role != .manager {
            inviteListener?.remove()
            inviteListener = nil
            invites = []
        }
    }

    private func updatePerVehicleListeners() {
        let ids = Set(vehicles.compactMap(\.id))
        for removed in Set(perVehicle.keys).subtracting(ids) {
            perVehicle[removed]?.forEach { $0.remove() }
            perVehicle[removed] = nil
            reminders[removed] = nil
            openDefects[removed] = nil
            pendingServices[removed] = nil
        }
        for vehicleId in ids.subtracting(perVehicle.keys) {
            let remindersListener = firestoreListen(FS.reminders(fleetId, vehicleId)) { [weak self] (items: [Reminder], _) in
                guard let self else { return }
                reminders[vehicleId] = items.sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
                syncReminderNotifications()
            }
            let defectsQuery = FS.defects(fleetId, vehicleId)
                .whereField("status", in: [DefectStatus.open.rawValue, DefectStatus.reportedFixed.rawValue])
            let defectsListener = firestoreListen(defectsQuery) { [weak self] (items: [Defect], _) in
                self?.openDefects[vehicleId] = items.sorted { $0.reportedAt > $1.reportedAt }
            }
            let pendingQuery = FS.services(fleetId, vehicleId)
                .whereField("status", isEqualTo: ServiceStatus.pending.rawValue)
            let pendingListener = firestoreListen(pendingQuery) { [weak self] (items: [ServiceRecord], _) in
                self?.pendingServices[vehicleId] = items
            }
            perVehicle[vehicleId] = [remindersListener, defectsListener, pendingListener]
        }
    }

    // MARK: Notifications

    private func syncReminderNotifications() {
        guard isManager else { return }
        let entries = allReminders.compactMap { entry -> ReminderNotifications.Entry? in
            guard let vehicleId = entry.vehicle.id, let reminderId = entry.reminder.id else { return nil }
            return .init(id: "\(fleetId)-\(vehicleId)-\(reminderId)", vehicleName: entry.vehicle.displayName,
                         reminder: entry.reminder)
        }
        ReminderNotifications.sync(entries, prefix: fleetId)
    }

    private func checkUsageAlert() {
        guard isManager, let fleet else { return }
        UsageAlerts.check(UsageReport(usage: fleet.usage), fleetId: fleetId, fleetName: fleet.name)
    }
}
