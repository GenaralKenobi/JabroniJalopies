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
    /// Chain sizes and counts, keyed by vehicle id.
    private(set) var chainInventories: [String: ChainInventory] = [:]
    /// Chainsaws and ropes on visible trucks (managers: all, including unassigned).
    private(set) var equipment: [Equipment] = []
    /// Open defects keyed by equipment id.
    private(set) var equipmentDefects: [String: [Defect]] = [:]
    /// Rope length reductions waiting for a manager, keyed by equipment id.
    private(set) var pendingLengthChanges: [String: [LengthChange]] = [:]

    private let onLostAccess: () -> Void
    private var baseListeners: [ListenerRegistration] = []
    private var vehicleListener: ListenerRegistration?
    private var vehicleQueryKey: String?
    private var inviteListener: ListenerRegistration?
    private var perVehicle: [String: [ListenerRegistration]] = [:]
    private var equipmentListeners: [String: ListenerRegistration] = [:]
    private var equipmentByQuery: [String: [Equipment]] = [:]
    private var perEquipment: [String: [ListenerRegistration]] = [:]
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

    /// Open defects across visible trucks and their equipment, unsafe and newest first.
    var allOpenDefects: [DefectEntry] {
        let vehicleEntries = sortedVehicles.flatMap { vehicle in
            (openDefects[vehicle.id ?? ""] ?? []).map {
                DefectEntry(owner: .vehicle(vehicle.id ?? ""), context: vehicle.displayName, defect: $0)
            }
        }
        let equipmentEntries = equipment.flatMap { item in
            (equipmentDefects[item.id ?? ""] ?? []).map {
                DefectEntry(owner: .equipment(item.id ?? ""), context: context(for: .equipment(item.id ?? "")), defect: $0)
            }
        }
        return (vehicleEntries + equipmentEntries).sorted { lhs, rhs in
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

    // MARK: Equipment

    func equipment(_ id: String?) -> Equipment? {
        guard let id else { return nil }
        return equipment.first { $0.id == id }
    }

    func equipment(on vehicleId: String, type: EquipmentType? = nil) -> [Equipment] {
        equipment
            .filter { $0.vehicleId == vehicleId && (type == nil || $0.type == type) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Equipment whose truck no longer exists (managers can move it).
    var unassignedEquipment: [Equipment] {
        let vehicleIds = Set(vehicles.compactMap(\.id))
        return equipment.filter { !vehicleIds.contains($0.vehicleId) }
    }

    func condition(ofEquipment equipmentId: String?) -> VehicleCondition {
        guard let equipmentId else { return .ok }
        return VehicleCondition(openDefects: equipmentDefects[equipmentId] ?? [])
    }

    /// Equipment on a truck that needs attention: open defects or a rope below its minimum length.
    func equipmentAlerts(on vehicleId: String) -> [EquipmentAlert] {
        equipment(on: vehicleId).compactMap { item in
            let defects = equipmentDefects[item.id ?? ""] ?? []
            guard !defects.isEmpty || item.isBelowMinimumLength else { return nil }
            return EquipmentAlert(equipment: item, defects: defects)
        }
    }

    var allPendingLengthChanges: [(equipment: Equipment, change: LengthChange)] {
        equipment.flatMap { item in
            (pendingLengthChanges[item.id ?? ""] ?? []).map { (equipment: item, change: $0) }
        }
        .sorted { $0.change.submittedAt > $1.change.submittedAt }
    }

    func context(for owner: DefectOwner) -> String {
        switch owner {
        case .vehicle(let id):
            return vehicle(id)?.displayName ?? "Vehicle"
        case .equipment(let id):
            guard let item = equipment(id) else { return "Equipment" }
            let truck = vehicle(item.vehicleId)?.displayName
            return [item.displayName, truck].compactMap { $0 }.joined(separator: " · ")
        }
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
        equipmentListeners.values.forEach { $0.remove() }
        equipmentListeners.removeAll()
        perEquipment.values.flatMap { $0 }.forEach { $0.remove() }
        perEquipment.removeAll()
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
                updateEquipmentListeners()
            }
            equipmentListeners.values.forEach { $0.remove() }
            equipmentListeners.removeAll()
            equipmentByQuery.removeAll()
            updateEquipmentListeners()
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

    /// Members who see the whole fleet listen to all equipment; restricted drivers
    /// listen per assigned truck (the security rules require that query shape).
    private func updateEquipmentListeners() {
        guard let me else { return }
        let seesAll = me.role == .manager || me.seesAllVehicles
        let wanted: Set<String> = seesAll ? ["*"] : Set(vehicles.compactMap(\.id))
        for key in Set(equipmentListeners.keys).subtracting(wanted) {
            equipmentListeners[key]?.remove()
            equipmentListeners[key] = nil
            equipmentByQuery[key] = nil
        }
        for key in wanted.subtracting(equipmentListeners.keys) {
            let query: Query = key == "*"
                ? FS.equipmentCollection(fleetId)
                : FS.equipmentCollection(fleetId).whereField("vehicleId", isEqualTo: key)
            equipmentListeners[key] = firestoreListen(query) { [weak self] (items: [Equipment], _) in
                guard let self else { return }
                equipmentByQuery[key] = items
                equipment = equipmentByQuery.values.flatMap { $0 }
                updatePerEquipmentListeners()
            }
        }
        equipment = equipmentByQuery.filter { wanted.contains($0.key) }.values.flatMap { $0 }
        updatePerEquipmentListeners()
    }

    private func updatePerEquipmentListeners() {
        let ids = Set(equipment.compactMap(\.id))
        for removed in Set(perEquipment.keys).subtracting(ids) {
            perEquipment[removed]?.forEach { $0.remove() }
            perEquipment[removed] = nil
            equipmentDefects[removed] = nil
            pendingLengthChanges[removed] = nil
        }
        for item in equipment where !perEquipment.keys.contains(item.id ?? "") {
            guard let equipmentId = item.id else { continue }
            var listeners: [ListenerRegistration] = []
            let defectsQuery = FS.equipmentDefects(fleetId, equipmentId)
                .whereField("status", in: [DefectStatus.open.rawValue, DefectStatus.reportedFixed.rawValue])
            listeners.append(firestoreListen(defectsQuery) { [weak self] (items: [Defect], _) in
                self?.equipmentDefects[equipmentId] = items.sorted { $0.reportedAt > $1.reportedAt }
            })
            if item.type == .rope {
                let pendingQuery = FS.lengthChanges(fleetId, equipmentId)
                    .whereField("status", isEqualTo: ReviewStatus.pending.rawValue)
                listeners.append(firestoreListen(pendingQuery) { [weak self] (items: [LengthChange], _) in
                    self?.pendingLengthChanges[equipmentId] = items.sorted { $0.submittedAt < $1.submittedAt }
                })
            }
            perEquipment[equipmentId] = listeners
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
            chainInventories[removed] = nil
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
            let chainsListener = FS.chainInventory(fleetId, vehicleId).addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    self?.chainInventories[vehicleId] = try? snapshot?.data(as: ChainInventory.self)
                }
            }
            perVehicle[vehicleId] = [remindersListener, defectsListener, pendingListener, chainsListener]
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

/// A defect on a truck or a piece of equipment, with a label for lists.
struct DefectEntry: Identifiable {
    var owner: DefectOwner
    var context: String
    var defect: Defect
    var id: String { defect.id ?? UUID().uuidString }
}

struct EquipmentAlert: Identifiable {
    var equipment: Equipment
    var defects: [Defect]
    var id: String { equipment.id ?? "" }

    var isDoNotUse: Bool { defects.contains(where: \.unsafe) }

    var message: String {
        var parts: [String] = []
        if isDoNotUse {
            parts.append("DO NOT USE")
        }
        let titles = defects.map(\.title)
        if !titles.isEmpty { parts.append(titles.joined(separator: ", ")) }
        if equipment.isBelowMinimumLength, let minimum = equipment.minLengthFeet {
            parts.append("shorter than the \(Formatting.feet(minimum)) minimum")
        }
        return parts.joined(separator: " — ")
    }
}
