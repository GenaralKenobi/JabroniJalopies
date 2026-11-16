import SwiftUI
import UIKit

/// Tapping anywhere that isn't a text field puts the keyboard away.
///
/// Add `.background(KeyboardDismissOnTap())` once, near the root of the app. It listens for
/// taps on the whole window without getting in the way of buttons or text fields: a tap on a
/// text field is ignored (so moving from one field to another doesn't flicker), and every other
/// tap still reaches whatever was tapped.
struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override init(frame: CGRect) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { KeyboardDismisser.shared.install(on: window) }
        }
    }
}

@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private weak var window: UIWindow?
    private var recognizer: UITapGestureRecognizer?

    func install(on window: UIWindow) {
        guard self.window !== window else { return }
        if let recognizer, let old = self.window { old.removeGestureRecognizer(recognizer) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false   // never swallow the tap
        tap.delegate = self
        window.addGestureRecognizer(tap)
        self.window = window
        recognizer = tap
    }

    @objc private func tapped() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // A tap on (or inside) a text field or text view is for that field, not for dismissing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
