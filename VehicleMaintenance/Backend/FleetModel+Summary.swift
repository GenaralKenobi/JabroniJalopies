import FirebaseFirestore
import Foundation

/// Working with the small summary kept on each truck (and each saw or rope).
///
/// The fleet list shows its badges from these summaries alone, so a phone doesn't have
/// to load every truck's defects, reminders and services when the app opens (each
/// document loaded is a billed read).
///
/// Summaries are kept right in two ways:
/// 1. Actions adjust them as they happen (a new defect adds one, closing one takes one
///    away). These go out with the action, so they work offline too.
/// 2. Any phone that has a truck's details loaded checks the summary against them once
///    the server has confirmed them, and corrects it if it has drifted. Managers' phones
///    load every truck's details, so drift doesn't last.
enum VehicleSummaries {
    /// The fleet-list maintenance badge from a summary: the worst of the earliest due
    /// date and the lowest due odometer, the same as checking every reminder.
    static func reminderStatus(_ summary: VehicleSummary?, odometer: Int, now: Date = .now) -> DueStatus? {
        guard let summary, summary.hasReminders == true || summary.nextDueDate != nil || summary.nextDueOdometer != nil else {
            return nil
        }
        return DueCalculator().status(nextDueDate: summary.nextDueDate, nextDueOdometer: summary.nextDueOdometer,
                                      currentOdometer: odometer, now: now)
    }

    static func condition(_ summary: VehicleSummary?) -> VehicleCondition {
        if (summary?.unsafeDefects ?? 0) > 0 { return .outOfService }
        if (summary?.openDefects ?? 0) > 0 { return .needsAttention }
        return .ok
    }

    /// Summary fields that differ from what the loaded reminders say.
    static func reminderChanges(_ reminders: [Reminder], current: VehicleSummary?) -> [String: Any] {
        let nextDate = reminders.compactMap(\.nextDueDate).min()
        let nextOdometer = reminders.compactMap(\.nextDueOdometer).min()
        var fields: [String: Any] = [:]
        if current?.hasReminders != !reminders.isEmpty {
            fields["summary.hasReminders"] = !reminders.isEmpty
        }
        if !sameDate(current?.nextDueDate, nextDate) {
            fields["summary.nextDueDate"] = nextDate.map { $0 as Any } ?? FieldValue.delete()
        }
        if current?.nextDueOdometer != nextOdometer {
            fields["summary.nextDueOdometer"] = nextOdometer.map { $0 as Any } ?? FieldValue.delete()
        }
        return fields
    }

    /// Summary fields that differ from the loaded open defects.
    static func defectChanges(_ defects: [Defect], openDefects: Int?, unsafeDefects: Int?, prefix: String = "summary") -> [String: Any] {
        let open = defects.filter(\.isOpen)
        var fields: [String: Any] = [:]
        if openDefects != open.count { fields["\(prefix).openDefects"] = open.count }
        let unsafe = open.filter(\.unsafe).count
        if unsafeDefects != unsafe { fields["\(prefix).unsafeDefects"] = unsafe }
        return fields
    }

    private static func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) < 1
        default: false
        }
    }
}

extension QuerySnapshot {
    /// Data the server has confirmed, with nothing from this phone still waiting to sync.
    var isServerConfirmed: Bool { !metadata.isFromCache && !metadata.hasPendingWrites }
}

extension FleetModel {
    // MARK: Correcting summaries from loaded details

    func reconcileDefectSummary(vehicleId: String, defects: [Defect]) {
        guard let vehicle = vehicle(vehicleId) else { return }
        writeSummary(VehicleSummaries.defectChanges(defects, openDefects: vehicle.summary?.openDefects,
                                                    unsafeDefects: vehicle.summary?.unsafeDefects),
                     to: FS.vehicle(fleetId, vehicleId))
    }

    func reconcileReminderSummary(vehicleId: String, reminders: [Reminder]) {
        guard let vehicle = vehicle(vehicleId) else { return }
        writeSummary(VehicleSummaries.reminderChanges(reminders, current: vehicle.summary), to: FS.vehicle(fleetId, vehicleId))
    }

    func reconcilePendingSummary(vehicleId: String, count: Int) {
        guard let vehicle = vehicle(vehicleId), vehicle.summary?.pendingServices != count else { return }
        writeSummary(["summary.pendingServices": count], to: FS.vehicle(fleetId, vehicleId))
    }

    func reconcileEquipmentDefectSummary(equipmentId: String, defects: [Defect]) {
        guard let item = equipment(equipmentId) else { return }
        writeSummary(VehicleSummaries.defectChanges(defects, openDefects: item.summary?.openDefects,
                                                    unsafeDefects: item.summary?.unsafeDefects),
                     to: FS.equipment(fleetId, equipmentId))
    }

    func reconcileLengthChangeSummary(equipmentId: String, count: Int) {
        guard let item = equipment(equipmentId), item.summary?.pendingLengthChanges != count else { return }
        writeSummary(["summary.pendingLengthChanges": count], to: FS.equipment(fleetId, equipmentId))
    }

    private func writeSummary(_ fields: [String: Any], to document: DocumentReference) {
        guard !fields.isEmpty else { return }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: document)
        // Quietly: a summary that can't be corrected right now will be corrected later.
        batch.commit()
    }

    // MARK: Adjusting summaries as things happen

    /// Adds to (or, with negative numbers, takes from) summary counts, e.g.
    /// `["openDefects": 1, "unsafeDefects": 1]`. Sent on its own so it can never cause
    /// the action itself to be rejected.
    func adjustSummary(of owner: DefectOwner, _ counts: [String: Int]) {
        let changes = counts.filter { $0.value != 0 }
        guard !changes.isEmpty else { return }
        var fields: [String: Any] = [:]
        for (key, value) in changes { fields["summary.\(key)"] = FieldValue.increment(Int64(value)) }
        let document: DocumentReference
        switch owner {
        case .vehicle(let id): document = FS.vehicle(fleetId, id)
        case .equipment(let id): document = FS.equipment(fleetId, id)
        }
        let batch = FS.db.batch()
        batch.updateData(fields, forDocument: document)
        batch.commit()
    }
}
