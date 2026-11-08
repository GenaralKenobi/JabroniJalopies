import SwiftUI

struct ReminderRow: View {
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let reminder: MaintenanceReminder
    var showsVehicle = false

    var body: some View {
        let status = reminder.status
        HStack(spacing: 12) {
            Image(systemName: reminder.serviceType.symbolName)
                .foregroundStyle(status.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.displayTitle)
                    .foregroundStyle(.primary)
                if showsVehicle, let vehicle = reminder.vehicle {
                    Text(vehicle.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(dueDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if status != .ok {
                StatusBadge(status: status)
            }
        }
        .padding(.vertical, 2)
    }

    private var dueDescription: String {
        var parts: [String] = []
        if let dueOdometer = reminder.nextDueOdometer {
            let remaining = dueOdometer - (reminder.vehicle?.odometer ?? reminder.lastServiceOdometer)
            let detail = remaining >= 0
                ? "\(remaining.formatted()) left"
                : "\((-remaining).formatted()) over"
            parts.append("\(Formatting.distance(dueOdometer, unit: unit)) (\(detail))")
        }
        if let dueDate = reminder.nextDueDate {
            parts.append(Formatting.shortDate(dueDate))
        }
        return parts.isEmpty ? "No interval set" : "Next: " + parts.joined(separator: " · ")
    }
}
