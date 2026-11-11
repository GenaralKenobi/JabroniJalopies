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
    /// The due date for time-based checklists; nil for ones due at a reading.
    let due: Date?
    /// For hour / mile based checklists: the reading it's due at, the vehicle's reading now, and its unit.
    var dueReading: Int? = nil
    var currentReading: Int = 0
    var unit: DistanceUnit = .miles
    let lastDone: Date?
    /// The manager's planned day, if one was picked for this due date.
    let plannedFor: Date?
    let status: ScheduleStatus

    var id: String { "\(vehicleId)-\(checklist.id ?? "")" }
    var checklistId: String { checklist.id ?? "" }

    /// For sorting: dated ones by date; reading-based ones sit by how urgent they are.
    var sortDate: Date {
        if let due { return due }
        switch status {
        case .overdue: return .distantPast
        case .dueSoon: return .now
        case .later: return .distantFuture
        }
    }
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

    /// Readings: due `interval` after the last time it was done; if it's never been done on
    /// this vehicle, at the next multiple of the interval (so a vehicle at 1,180 hours with
    /// a 250-hour service is due at 1,250).
    static func dueReading(interval: Int, lastReading: Int?, current: Int) -> Int {
        if let lastReading { return lastReading + interval }
        return max(interval, ((current + interval - 1) / interval) * interval)
    }

    /// Managers are alerted when the reading is within a tenth of the interval of the due reading.
    static func alertMargin(interval: Int) -> Int { max(1, interval / 10) }

    static func readingStatus(due: Int, interval: Int, current: Int) -> ScheduleStatus {
        if current >= due { return .overdue }
        if current >= due - alertMargin(interval: interval) { return .dueSoon }
        return .later
    }

    static func status(due: Date, now: Date = .now, calendar: Calendar = .current) -> ScheduleStatus {
        if now >= due { return .overdue }
        if now >= alertDate(due: due, calendar: calendar) { return .dueSoon }
        return .later
    }

    /// A plan applies only to the due date it was made for.
    static func activePlan(_ plan: ChecklistPlan?, due: Date) -> Date? {
        guard let plan, let forDue = plan.forDue, abs(forDue.timeIntervalSince(due)) < 3600 else { return nil }
        return plan.date
    }

    static func activePlan(_ plan: ChecklistPlan?, dueReading: Int) -> Date? {
        guard let plan, plan.forReading == dueReading else { return nil }
        return plan.date
    }

    static func entry(for checklist: ChecklistTemplate, vehicle: Vehicle, state: ChecklistState?,
                      now: Date = .now, calendar: Calendar = .current) -> ScheduledDue? {
        guard let checklistId = checklist.id, let vehicleId = vehicle.id else { return nil }
        let lastDone = state?.checklistLastDone[checklistId]
        if let interval = checklist.readingInterval, interval > 0 {
            let due = dueReading(interval: interval, lastReading: state?.checklistLastReading[checklistId],
                                 current: vehicle.odometer)
            return ScheduledDue(checklist: checklist, vehicleId: vehicleId, due: nil, dueReading: due,
                                currentReading: vehicle.odometer, unit: vehicle.unit, lastDone: lastDone,
                                plannedFor: activePlan(vehicle.checklistPlans?[checklistId], dueReading: due),
                                status: readingStatus(due: due, interval: interval, current: vehicle.odometer))
        }
        guard let schedule = checklist.schedule else { return nil }
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

    /// "Dec 10" this year, "Jan 4, 2027" otherwise.
    static func shortDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Where it's due: "Dec 10" or "1,250 hr".
    static func dueDescription(_ entry: ScheduledDue) -> String {
        if let due = entry.due { return shortDate(due) }
        return Formatting.distance(entry.dueReading ?? 0, unit: entry.unit)
    }

    /// "Due Dec 10", "Planned Nov 20 · due Dec 10", "Overdue since Dec 10", "Due at 1,250 hr (38 hr to go)".
    static func statusText(_ entry: ScheduledDue) -> String {
        let due = dueDescription(entry)
        let planned = entry.plannedFor.map { "Planned \(shortDate($0)) · " } ?? ""
        if let dueReading = entry.dueReading {
            let remaining = dueReading - entry.currentReading
            if entry.status == .overdue {
                return "Overdue since \(due) (now \(Formatting.distance(entry.currentReading, unit: entry.unit)))"
            }
            return "\(planned)Due at \(due) (\(Formatting.distance(remaining, unit: entry.unit)) to go)"
        }
        if entry.status == .overdue { return "Overdue since \(due)" }
        if let planned = entry.plannedFor {
            return "Planned \(shortDate(planned)) · due \(due)"
        }
        return "Due \(due)"
    }

    /// "Monthly", "Every 14 days", "Every 250 hr" (nil for an everyday checklist).
    static func label(for checklist: ChecklistTemplate, unit: DistanceUnit? = nil) -> String? {
        if let schedule = checklist.schedule { return scheduleLabel(schedule) }
        if let interval = checklist.readingInterval {
            return "Every \(interval.formatted()) \(unit?.abbreviation ?? "hr / mi / km")"
        }
        return nil
    }
}
