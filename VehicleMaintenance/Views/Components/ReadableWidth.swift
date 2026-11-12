import SwiftUI

extension View {
    /// On wide screens (iPad), keeps a list to a comfortable reading width, centred,
    /// instead of stretching rows across the whole screen.
    func readableWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            content
        }
    }
}
