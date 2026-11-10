import Foundation

/// Where a scheduled checklist stands on one truck.
enum ScheduleStatus: Int, Comparable {
    /// More than two weeks away.
    case later
    /// Due within two weeks: managers are alerted so they can plan a day.
    case dueSoon
    /// Past its due date: drivers see it tagged "Overdue".
    case overdue

    static func < (a: ScheduleStatus, b: ScheduleStatus) -> Bool { a.rawValue < b.rawValue }
}

/// One scheduled checklist on one truck.
struct ScheduledDue: Identifiable, Hashable {
    let checklist: ChecklistTemplate
    let vehicleId: String
    let due: Date
    let lastDone: Date?
    /// The manager's planned day, if one was picked for this due date.
    let plannedFor: Date?
    let status: ScheduleStatus

    var id: String { "\(vehicleId)-\(checklist.id ?? "")" }
    var checklistId: String { checklist.id ?? "" }
}

/// Monthly and every-N-days checklists, and weekly items skipped too often.
enum ScheduledChecklists {
    /// Managers are alerted this many days before a scheduled checklist is due.
    static let alertLeadDays = 14
    /// A repeating item skipped on this many checklists in a row is overdue.
    static let skipLimit = 3

    /// Monthly: one month after it was last done on the truck. Every N days: N days after.
    /// Never done on this truck: the checklist's first due date.
    static func dueDate(schedule: ItemFrequency, firstDue: Date?, lastDone: Date?,
                        calendar: Calendar = .current) -> Date? {
        guard let lastDone else { return firstDue.map { calendar.startOfDay(for: $0) } }
        let start = calendar.startOfDay(for: lastDone)
        switch schedule.kind {
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: start)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: start)
        case .days: return calendar.date(byAdding: .day, value: max(1, schedule.days ?? 1), to: start)
        }
    }

    /// The day managers are alerted: two weeks before it's due.
    static func alertDate(due: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -alertLeadDays, to: due) ?? due
    }

    static func status(due: Date, now: Date = .now, calendar: Calendar = .current) -> ScheduleStatus {
        if now >= due { return .overdue }
        if now >= alertDate(due: due, calendar: calendar) { return .dueSoon }
        return .later
    }

    /// A plan applies only to the due date it was made for.
    static func activePlan(_ plan: ChecklistPlan?, due: Date) -> Date? {
        guard let plan, abs(plan.forDue.timeIntervalSince(due)) < 3600 else { return nil }
        return plan.date
    }

    static func entry(for checklist: ChecklistTemplate, vehicle: Vehicle, state: ChecklistState?,
                      now: Date = .now, calendar: Calendar = .current) -> ScheduledDue? {
        guard let schedule = checklist.schedule, let checklistId = checklist.id, let vehicleId = vehicle.id else { return nil }
        let lastDone = state?.checklistLastDone[checklistId]
        guard let due = dueDate(schedule: schedule, firstDue: checklist.firstDue, lastDone: lastDone, calendar: calendar) else {
            return nil
        }
        return ScheduledDue(checklist: checklist, vehicleId: vehicleId, due: due, lastDone: lastDone,
                            plannedFor: activePlan(vehicle.checklistPlans?[checklistId], due: due),
                            status: status(due: due, now: now, calendar: calendar))
    }

    static func isSkippedTooOften(_ skips: Int?) -> Bool { (skips ?? 0) >= skipLimit }

    /// "Monthly" / "Every 14 days".
    static func scheduleLabel(_ schedule: ItemFrequency) -> String {
        schedule.kind == .days && (schedule.days ?? 1) > 1 ? "Every \(schedule.days ?? 1) days" : schedule.label
    }

    /// "Due Dec 10", "Planned Nov 20 · due Dec 10", "Overdue since Dec 10".
    static func statusText(_ entry: ScheduledDue) -> String {
        let due = entry.due.formatted(date: .abbreviated, time: .omitted)
        if entry.status == .overdue { return "Overdue since \(due)" }
        if let planned = entry.plannedFor {
            return "Planned \(planned.formatted(date: .abbreviated, time: .omitted)) · due \(due)"
        }
        return "Due \(due)"
    }
}
