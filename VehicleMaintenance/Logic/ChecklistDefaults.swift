import Foundation

/// The starter checklist created with every new fleet. Managers can edit it.
enum ChecklistDefaults {
    static func morningChecklist(makeId: () -> String = { UUID().uuidString }) -> ChecklistTemplate {
        func item(_ title: String, reading: String? = nil, unsafe: Bool = false) -> ChecklistItem {
            ChecklistItem(id: makeId(), title: title, requiresReading: reading != nil,
                          readingLabel: reading ?? "", unsafeIfFailed: unsafe)
        }
        return ChecklistTemplate(
            name: "Morning Checklist",
            items: [
                item("Tires — inflation and tread", unsafe: true),
                item("Lowest tire pressure", reading: "PSI"),
                item("Brakes and parking brake", unsafe: true),
                item("Headlights, brake lights and turn signals", unsafe: true),
                item("Windshield, wipers and washer fluid"),
                item("Mirrors"),
                item("Horn"),
                item("Seat belts", unsafe: true),
                item("Fluid leaks under vehicle"),
                item("Engine oil level"),
                item("Warning lights on dash"),
                item("Fire extinguisher and first-aid kit"),
            ],
            vehicleIds: [],
            updatedAt: .now)
    }
}
