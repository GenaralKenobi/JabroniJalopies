import Foundation

enum DueStatus: Int, Comparable, CaseIterable {
    case ok = 0
    case dueSoon = 1
    case overdue = 2

    static func < (lhs: DueStatus, rhs: DueStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .ok: "Up to date"
        case .dueSoon: "Due soon"
        case .overdue: "Overdue"
        }
    }

    var sectionTitle: String {
        switch self {
        case .ok: "Later"
        case .dueSoon: "Due Soon"
        case .overdue: "Overdue"
        }
    }

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .dueSoon: "clock.fill"
        case .overdue: "exclamationmark.triangle.fill"
        }
    }
}

/// Pure due-date math, kept free of SwiftData/SwiftUI so it is easy to test.
struct DueCalculator {
    /// Within this distance of the next due odometer counts as "due soon".
    var soonDistance: Int = 500
    /// Within this many days of the next due date counts as "due soon".
    var soonDays: Int = 30
    var calendar: Calendar = .current

    func nextDueDate(lastDate: Date, intervalMonths: Int?) -> Date? {
        guard let months = intervalMonths, months > 0 else { return nil }
        return calendar.date(byAdding: .month, value: months, to: lastDate)
    }

    func nextDueOdometer(lastOdometer: Int, intervalDistance: Int?) -> Int? {
        guard let distance = intervalDistance, distance > 0 else { return nil }
        return lastOdometer + distance
    }

    /// The worst of the date-based and distance-based status.
    func status(nextDueDate: Date?, nextDueOdometer: Int?, currentOdometer: Int, now: Date = .now) -> DueStatus {
        var result = DueStatus.ok

        if let dueDate = nextDueDate {
            if dueDate <= now {
                result = max(result, .overdue)
            } else if let soon = calendar.date(byAdding: .day, value: soonDays, to: now), dueDate <= soon {
                result = max(result, .dueSoon)
            }
        }

        if let dueOdometer = nextDueOdometer {
            if currentOdometer >= dueOdometer {
                result = max(result, .overdue)
            } else if dueOdometer - currentOdometer <= soonDistance {
                result = max(result, .dueSoon)
            }
        }

        return result
    }
}
