#if DEBUG
import FirebaseAuth
import Foundation
import os

/// Demo mode for CI screenshots: with `-useEmulator YES -demoSeed YES`, signs in
/// as the demo manager created by `firebase/scripts/seed-demo.mjs`.
enum DemoSeeder {
    static let email = "mia.manager@demo.test"
    static let password = "demo-password"
    private static let log = Logger(subsystem: "com.generalkenobi.jabronisjalopies", category: "demo")

    @MainActor
    static func runIfRequested() async {
        guard FirebaseSetup.usesEmulator, UserDefaults.standard.bool(forKey: "demoSeed") else { return }
        guard Auth.auth().currentUser == nil else {
            log.notice("DEMO: already signed in")
            return
        }
        for attempt in 1...3 {
            do {
                try await Auth.auth().signIn(withEmail: email, password: password)
                log.notice("DEMO: signed in on attempt \(attempt)")
                return
            } catch {
                log.error("DEMO: sign-in attempt \(attempt) failed: \(String(describing: error), privacy: .public)")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
#endif
