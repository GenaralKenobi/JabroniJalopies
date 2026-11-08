import Foundation

/// Totals for the fleet-wide chain report (managers).
struct ChainTotals: Equatable {
    struct Row: Identifiable, Equatable {
        var inches: Double
        var onTrucks: Int
        var dull: Int
        var discarded: Int
        var added: Int
        var id: Double { inches }
        var label: String { ChainSize.format(inches) }
    }

    var rows: [Row]

    /// Sums current truck counts, plus log activity since `since`.
    static func make(inventories: [ChainInventory], logs: [ChainLog], since: Date) -> ChainTotals {
        var byInches: [Double: Row] = [:]
        func row(_ inches: Double) -> Row {
            byInches[inches] ?? Row(inches: inches, onTrucks: 0, dull: 0, discarded: 0, added: 0)
        }
        for inventory in inventories {
            for size in inventory.sizes {
                var r = row(size.inches)
                r.onTrucks += max(0, inventory.count(size))
                byInches[size.inches] = r
            }
        }
        for log in logs where log.loggedAt >= since {
            for item in log.items {
                var r = row(item.inches)
                r.dull += item.dull
                r.discarded += item.discarded
                r.added += item.added
                byInches[item.inches] = r
            }
        }
        return ChainTotals(rows: byInches.values.sorted { $0.inches < $1.inches })
    }
}

/// Parses chain sizes typed by a manager, e.g. "16, 18, 20.5" or "16\" 18\"".
enum ChainSizeParser {
    static func parse(_ text: String) -> [ChainSize] {
        let separators = CharacterSet(charactersIn: ",; \n\"″'")
        let values = text.components(separatedBy: separators)
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 && $0 < 100 }
        var seen = Set<String>()
        return values.map(ChainSize.init(inches:))
            .filter { seen.insert($0.key).inserted }
            .sorted { $0.inches < $1.inches }
    }
}
