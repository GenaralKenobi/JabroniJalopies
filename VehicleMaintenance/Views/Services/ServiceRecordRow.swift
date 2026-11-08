import SwiftUI

struct ServiceRecordRow: View {
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    let record: ServiceRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.serviceType.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle)
                    .foregroundStyle(.primary)
                Text("\(Formatting.shortDate(record.date)) · \(Formatting.distance(record.odometer, unit: unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !record.shop.isEmpty {
                    Text(record.shop)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if record.cost > 0 {
                Text(Formatting.currency(record.cost))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 2)
    }
}
