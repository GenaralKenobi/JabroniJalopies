import SwiftUI

extension DueStatus {
    var color: Color {
        switch self {
        case .ok: .green
        case .dueSoon: .orange
        case .overdue: .red
        }
    }
}

struct StatusBadge: View {
    let status: DueStatus

    var body: some View {
        // An explicit HStack rather than Label: inside list rows Label can collapse
        // to icon-only when space is tight.
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
            Text(status.label)
                .lineLimit(1)
        }
            .font(.caption.weight(.semibold))
            .fixedSize()
            .accessibilityElement(children: .combine)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

#Preview {
    VStack {
        ForEach(DueStatus.allCases, id: \.self) { StatusBadge(status: $0) }
    }
}
