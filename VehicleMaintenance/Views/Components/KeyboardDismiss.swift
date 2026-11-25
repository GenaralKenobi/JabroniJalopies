import SwiftUI

extension View {
    /// Scrolling in either direction puts the keyboard away. (There used to be a "Done"
    /// button above the keyboard, but it covered the text being typed, so it was removed.)
    func dismissesKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.immediately)
    }
}
