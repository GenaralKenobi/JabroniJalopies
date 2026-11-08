import Foundation

/// The starting set of quick-reference specs for a new vehicle. Managers can
/// rename, remove or add rows and whole sections.
enum SpecDefaults {
    static let template: [(title: String, rows: [String])] = [
        ("Fluids", [
            "Engine oil", "Oil capacity", "Coolant", "Transmission fluid", "Brake fluid",
            "Power steering fluid", "Differential / axle oil", "DEF", "Washer fluid", "Fuel type",
        ]),
        ("Tires & Wheels", [
            "Tire size", "Brand / model", "Load index / speed rating",
            "Front pressure (cold, PSI)", "Rear pressure (cold, PSI)", "Spare pressure (PSI)",
            "Lug nut torque", "Dual rear wheels",
        ]),
        ("Parts & Capacities", [
            "Oil filter", "Engine air filter", "Cabin air filter", "Battery (group / CCA)",
            "Wiper blades", "Headlight bulb", "GVWR", "Towing capacity",
        ]),
    ]

    static func sections(makeId: () -> String = { UUID().uuidString }) -> [SpecSection] {
        template.map { section in
            SpecSection(id: makeId(), title: section.title,
                        rows: section.rows.map { SpecRow(id: makeId(), label: $0, value: "") })
        }
    }

    /// Sections with only the rows that have values (what the quick view shows).
    static func filled(_ sections: [SpecSection]) -> [SpecSection] {
        sections.compactMap { section in
            let rows = section.rows.filter { !$0.value.trimmed.isEmpty }
            return rows.isEmpty ? nil : SpecSection(id: section.id, title: section.title, rows: rows)
        }
    }

    static func emptyRowCount(_ sections: [SpecSection]) -> Int {
        sections.reduce(0) { $0 + $1.rows.filter { $0.value.trimmed.isEmpty }.count }
    }
}
