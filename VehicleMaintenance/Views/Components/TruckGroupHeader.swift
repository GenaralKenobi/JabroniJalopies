import SwiftUI

/// The tappable first row of a truck's group on the Defects and Upcoming tabs:
/// the truck's name, a one-line summary, and a chevron that opens or closes the group.
struct TruckGroupHeader: View {
    let name: String
    let summary: String
    let symbol: String
    let color: Color
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(Color.primary)
                    Text(summary).font(.caption).foregroundStyle(color == .secondary ? Color.secondary : color)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Hides this truck's items" : "Shows this truck's items")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Which truck groups are open, plus Expand All / Collapse All.
struct ExpandedGroups {
    var open: Set<String> = []

    func binding(_ id: String, in state: Binding<ExpandedGroups>) -> Binding<Bool> {
        Binding(get: { state.wrappedValue.open.contains(id) },
                set: { isOpen in
                    if isOpen { state.wrappedValue.open.insert(id) } else { state.wrappedValue.open.remove(id) }
                })
    }
}

struct ExpandAllButton: View {
    let ids: [String]
    @Binding var groups: ExpandedGroups

    var body: some View {
        let allOpen = !ids.isEmpty && ids.allSatisfy(groups.open.contains)
        Button(allOpen ? "Collapse All" : "Expand All") {
            withAnimation(.snappy) { groups.open = allOpen ? [] : Set(ids) }
        }
        .disabled(ids.isEmpty)
    }
}

extension View {
    /// For the CI screenshots: launching with `-expandGroups YES` opens every truck group.
    func expandGroupsForScreenshots(_ ids: [String], _ groups: Binding<ExpandedGroups>) -> some View {
        task(id: ids) {
            if UserDefaults.standard.bool(forKey: "expandGroups") { groups.wrappedValue.open = Set(ids) }
        }
    }
}
