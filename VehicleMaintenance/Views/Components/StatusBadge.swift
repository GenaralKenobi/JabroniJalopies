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
        Label(status.label, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
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
