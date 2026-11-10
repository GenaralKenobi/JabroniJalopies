import Foundation

/// Sorting, grouping and searching for a truck's contents list.
enum TruckContents {
    /// Heading for items with no location, when other items have one.
    static let otherHeading = "Other"

    struct Group: Identifiable, Hashable {
        /// The location as entered ("" for items with no location).
        let location: String
        let title: String
        let items: [TruckItem]
        var id: String { location }
    }

    /// Items grouped by location (A–Z, items without a location last), each group sorted by name.
    /// Locations that differ only in case or surrounding spaces are treated as the same place.
    static func grouped(_ items: [TruckItem], matching search: String = "") -> [Group] {
        let filtered = filter(items, search)
        var byKey: [String: (location: String, items: [TruckItem])] = [:]
        for item in filtered {
            let location = item.location.trimmed
            let key = location.lowercased()
            byKey[key, default: (location: location, items: [])].items.append(item)
        }
        let keys = byKey.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        let onlyUnplaced = keys == [""]
        return keys.map { key in
            let entry = byKey[key]!
            let sorted = entry.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let title = key.isEmpty ? (onlyUnplaced ? "Items" : otherHeading) : entry.location
            return Group(location: entry.location, title: title, items: sorted)
        }
    }

    /// Distinct locations already used on the truck, A–Z, for quick picking.
    static func locations(_ items: [TruckItem]) -> [String] {
        var seen: [String: String] = [:]
        for item in items {
            let location = item.location.trimmed
            guard !location.isEmpty else { continue }
            seen[location.lowercased()] = seen[location.lowercased()] ?? location
        }
        return seen.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func filter(_ items: [TruckItem], _ search: String) -> [TruckItem] {
        let terms = search.trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let text = "\(item.name) \(item.location) \(item.notes)"
            return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }

    /// Items from another truck that this truck doesn't already have (same name and location).
    static func missing(from source: [TruckItem], in target: [TruckItem]) -> [TruckItem] {
        func key(_ item: TruckItem) -> String { "\(item.name.trimmed.lowercased())|\(item.location.trimmed.lowercased())" }
        var existing = Set(target.map(key))
        var result: [TruckItem] = []
        for item in source where !existing.contains(key(item)) {
            existing.insert(key(item))
            result.append(item)
        }
        return result
    }

    /// "×3", or nil when no quantity was entered.
    static func quantityText(_ quantity: Int?) -> String? {
        quantity.map { "×\($0)" }
    }
}
