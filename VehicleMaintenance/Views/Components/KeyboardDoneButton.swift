import SwiftUI
import UIKit

extension View {
    /// Adds a "Done" button above the keyboard. Number pads have no return key, so
    /// without this the keyboard can cover the Save/Submit buttons with no way to close it.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}
