import FirebaseFirestore
import Foundation

extension FleetModel {
    // MARK: Scheduled checklists and overdue repeating items

    /// Scheduled (monthly / every N days) checklists on a truck, soonest due first.
    func scheduledChecklists(on vehicleId: String, now: Date = .now) -> [ScheduledDue] {
        guard let vehicle = vehicle(vehicleId) else { return [] }
        return checklists(for: vehicleId)
            .compactMap { ScheduledChecklists.entry(for: $0, vehicle: vehicle, state: checklistStates[vehicleId], now: now) }
            .sorted { $0.sortDate < $1.sortDate }
    }

    /// Every truck's scheduled checklists, soonest due first.
    func allScheduledChecklists(now: Date = .now) -> [ScheduledDue] {
        sortedVehicles.flatMap { scheduledChecklists(on: $0.id ?? "", now: now) }.sorted { $0.sortDate < $1.sortDate }
    }

    /// Due repeating items that were skipped on the last few checklists in a row.
    func itemsSkippedTooOften(on vehicleId: String, now: Date = .now) -> [ChecklistItem] {
        let skips = checklistStates[vehicleId]?.skips ?? [:]
        return dueRepeatingItems(on: vehicleId, now: now).filter { ScheduledChecklists.isSkippedTooOften(skips[$0.id]) }
    }

    /// Overdue scheduled checklists plus overdue repeating items on a truck.
    func overdueCount(on vehicleId: String, now: Date = .now) -> Int {
        scheduledChecklists(on: vehicleId, now: now).filter { $0.status == .overdue }.count
            + itemsSkippedTooOften(on: vehicleId, now: now).count
    }

    /// Managers plan (or clear, with nil) the day a scheduled checklist will be done on a truck.
    func plan(_ entry: ScheduledDue, on date: Date?) throws {
        let field = "checklistPlans.\(entry.checklistId)"
        let value: Any
        if let date {
            value = try FS.encode(ChecklistPlan(date: Calendar.current.startOfDay(for: date), forDue: entry.due,
                                                forReading: entry.dueReading, byName: myName))
        } else {
            value = FieldValue.delete()
        }
        let batch = FS.db.batch()
        batch.updateData([field: value], forDocument: FS.vehicle(fleetId, entry.vehicleId))
        commitInBackground(batch, "Planning \(entry.checklist.name)")
    }

    // MARK: Manager alerts

    func scheduleAlertsSoon() {
        scheduleAlertTask?.cancel()
        scheduleAlertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncScheduleAlerts()
        }
    }

    /// Managers' phones: an alert two weeks before each scheduled checklist is due on a
    /// truck (unless a day is already planned), and one when a repeating item has been
    /// skipped on several checklists in a row. Local notifications only; no server.
    func syncScheduleAlerts() {
        guard isManager else {
            ScheduleAlerts.sync(fleetId: fleetId, alerts: [])
            return
        }
        var alerts: [ScheduleAlerts.Alert] = []
        for entry in allScheduledChecklists() where entry.plannedFor == nil {
            let vehicleName = vehicle(entry.vehicleId)?.displayName ?? "A truck"
            let due = ScheduledChecklists.dueDescription(entry)
            if let dueReading = entry.dueReading {
                // Reading-based: alert as soon as the vehicle is within a tenth of the interval of it.
                guard entry.status != .later else { continue }
                let togo = Formatting.distance(max(0, dueReading - entry.currentReading), unit: entry.unit)
                alerts.append(.init(
                    id: entry.id,
                    title: entry.status == .overdue ? "\(entry.checklist.name) overdue" : "\(entry.checklist.name) due at \(due)",
                    body: entry.status == .overdue
                        ? "\(vehicleName) passed \(due) (now \(Formatting.distance(entry.currentReading, unit: entry.unit))). Plan a day for \(entry.checklist.name)."
                        : "\(vehicleName) is \(togo) from \(entry.checklist.name). Plan a day for it in the Upcoming tab.",
                    fireAt: nil,
                    onceKey: "due-\(entry.id)-r\(dueReading)"))
                continue
            }
            guard let dueDate = entry.due else { continue }
            alerts.append(.init(
                id: entry.id,
                title: entry.status == .overdue ? "\(entry.checklist.name) overdue" : "\(entry.checklist.name) due \(due)",
                body: "\(vehicleName) is due for \(entry.checklist.name) on \(due). Plan a day for it in the Upcoming tab.",
                fireAt: ScheduledChecklists.alertDate(due: dueDate),
                onceKey: "due-\(entry.id)-\(Int(dueDate.timeIntervalSince1970))"))
        }
        for vehicle in sortedVehicles {
            guard let vehicleId = vehicle.id else { continue }
            for item in itemsSkippedTooOften(on: vehicleId) {
                let skips = checklistStates[vehicleId]?.skips[item.id] ?? ScheduledChecklists.skipLimit
                alerts.append(.init(
                    id: "skip-\(vehicleId)-\(item.id)",
                    title: "\(vehicle.displayName): \(item.title) overdue",
                    body: "Skipped on the last \(skips) checklists on \(vehicle.displayName).",
                    fireAt: nil,
                    onceKey: "skip-\(vehicleId)-\(item.id)"))
            }
        }
        let fleetId = fleetId
        if alerts.isEmpty {
            ScheduleAlerts.sync(fleetId: fleetId, alerts: [])
            return
        }
        // Ask for notification permission the first time there's something to alert about
        // (the system only asks once); without it these alerts would silently go nowhere.
        Task {
            guard await ReminderNotifications.requestAuthorization() else { return }
            ScheduleAlerts.sync(fleetId: fleetId, alerts: alerts)
        }
    }
}
