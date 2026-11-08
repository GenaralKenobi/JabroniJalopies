import SwiftUI

extension Color {
    /// The app's orange accent, read straight from the asset catalog.
    static let brand = Color("AccentColor")
}

extension VehicleCondition {
    var color: Color {
        switch self {
        case .ok: .green
        case .needsAttention: .orange
        case .outOfService: .red
        }
    }
}

/// "Unsafe to drive" / "Needs attention" pill for vehicles.
struct ConditionBadge: View {
    let condition: VehicleCondition
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: condition.symbolName)
            Text(compact && condition == .outOfService ? "Unsafe" : condition.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(condition == .outOfService ? Color.white : condition.color)
        .background(condition == .outOfService ? AnyShapeStyle(Color.red) : AnyShapeStyle(condition.color.opacity(0.15)),
                    in: Capsule())
    }
}

/// The strong warning shown on vehicles with an unsafe defect.
struct UnsafeBanner: View {
    let defects: [Defect]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("UNSAFE TO DRIVE", systemImage: "exclamationmark.octagon.fill")
                .font(.headline.weight(.heavy))
            Text("Do not drive this vehicle until a manager clears it.")
                .font(.subheadline.weight(.semibold))
            ForEach(defects.filter(\.unsafe), id: \.id) { defect in
                Text("• \(defect.title)").font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct DefectStatusBadge: View {
    let defect: Defect

    private var text: String {
        switch defect.status {
        case .open: defect.unsafe ? "Unsafe" : "Open"
        case .reportedFixed: "Reported fixed"
        case .closed: defect.resolution?.label ?? "Closed"
        }
    }

    private var color: Color {
        switch defect.status {
        case .open: defect.unsafe ? .red : .orange
        case .reportedFixed: .blue
        case .closed: .green
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
