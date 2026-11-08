import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Configures Firebase from `GoogleService-Info.plist`, or — in debug builds
/// launched with `-useEmulator YES` — against the local Firebase emulators
/// (used by CI to capture screenshots with realistic data).
enum FirebaseSetup {
    private(set) static var isConfigured = false
    private(set) static var usesEmulator = false
    static let emulatorHost = "127.0.0.1"

    static func configure() {
        guard FirebaseApp.app() == nil else { return }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "useEmulator") {
            configureForEmulator()
            return
        }
        #endif

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
        applyFirestoreSettings()
        isConfigured = true
    }

    /// Offline persistence is what lets checklists be completed without signal.
    static func applyFirestoreSettings() {
        let settings = FirestoreSettings()
        if usesEmulator {
            settings.host = "\(emulatorHost):8080"
            settings.isSSLEnabled = false
        }
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 200 * 1024 * 1024))
        Firestore.firestore().settings = settings
    }

    /// Removes the on-device copy of fleet data (called on sign-out).
    static func clearLocalCache() async {
        let db = Firestore.firestore()
        do {
            try await db.terminate()
            try await db.clearPersistence()
        } catch {
            // Not fatal: the cache is still protected by iOS data protection.
        }
        applyFirestoreSettings()
    }

    private static func configureForEmulator() {
        let options = FirebaseOptions(googleAppID: "1:123456789012:ios:0123456789abcdef", gcmSenderID: "123456789012")
        options.projectID = "demo-maintenance"
        options.apiKey = "AIzaSyDemoKeyForEmulatorUseOnly00000000"
        options.storageBucket = "demo-maintenance.appspot.com"
        FirebaseApp.configure(options: options)
        usesEmulator = true
        Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
        applyFirestoreSettings()
        Storage.storage().useEmulator(withHost: emulatorHost, port: 9199)
        isConfigured = true
    }
}
