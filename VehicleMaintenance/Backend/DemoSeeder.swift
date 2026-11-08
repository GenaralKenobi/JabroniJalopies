#if DEBUG
import FirebaseAuth
import Foundation

/// Demo mode for CI screenshots: with `-useEmulator YES -demoSeed YES`, signs in
/// as the demo manager created by `firebase/scripts/seed-demo.mjs`.
enum DemoSeeder {
    static let email = "mia.manager@demo.test"
    static let password = "demo-password"

    @MainActor
    static func runIfRequested() async {
        guard FirebaseSetup.usesEmulator, UserDefaults.standard.bool(forKey: "demoSeed") else { return }
        guard Auth.auth().currentUser == nil else { return }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            print("Demo sign-in failed (did the seed script run?): \(error)")
        }
    }
}
#endif
