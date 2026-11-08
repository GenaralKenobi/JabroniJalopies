import Foundation

struct MonthlyCost: Identifiable, Equatable {
    let month: Date
    let total: Double
    var id: Date { month }
}

enum CostAggregation {
    /// Totals per calendar month for the last `months` months (oldest first),
    /// including months with no spending.
    static func monthlyTotals(
        _ entries: [(date: Date, cost: Double)],
        months: Int = 12,
        endingAt now: Date = .now,
        calendar: Calendar = .current
    ) -> [MonthlyCost] {
        guard months > 0, let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }

        let monthStarts: [Date] = (0..<months).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonth)
        }
        var totals = Dictionary(uniqueKeysWithValues: monthStarts.map { ($0, 0.0) })

        for entry in entries {
            guard let start = calendar.dateInterval(of: .month, for: entry.date)?.start,
                  let existing = totals[start] else { continue }
            totals[start] = existing + entry.cost
        }

        return monthStarts.map { MonthlyCost(month: $0, total: totals[$0] ?? 0) }
    }
}
