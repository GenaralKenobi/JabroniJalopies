import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit

/// Instant defect alerts for managers.
///
/// A manager's phone registers for push notifications and saves its token at
/// `users/{uid}/devices/{token}`. When someone reports a defect, a Cloud Function
/// (firebase/functions) sends a notification to the fleet's managers' tokens.
/// Drivers' phones never register.
@MainActor
final class PushRegistration: NSObject, MessagingDelegate {
    static let shared = PushRegistration()

    /// `UserDefaults` / `@AppStorage` key: whether this phone wants instant defect alerts (on by default).
    static let preferenceKey = "pushDefectAlerts"

    /// The person this phone is registered for (nil when not registered).
    private var activeUid: String?
    private static let tokenKey = "pushToken"

    /// This phone's push token. Remembered across launches so signing out can delete it even
    /// after the app has restarted (otherwise a signed-out manager's phone would keep getting alerts).
    private var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    static var wantsAlerts: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// For managers: ask for notification permission (once) and register this phone.
    /// Safe to call often.
    func enableIfWanted() async {
        guard Self.wantsAlerts, FirebaseSetup.isConfigured, let uid = Auth.auth().currentUser?.uid else { return }
        guard activeUid != uid else { return }
        guard await ReminderNotifications.requestAuthorization() else { return }
        activeUid = uid
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
        if let token { await save(token, uid: uid) }
    }

    /// Stops alerts on this phone (the toggle was turned off, or the person signed out).
    func disable() async {
        guard FirebaseSetup.isConfigured else { return }
        let uid = activeUid ?? Auth.auth().currentUser?.uid
        activeUid = nil
        if let uid, let token {
            try? await FS.devices(uid).document(token).delete()
        }
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    /// Called when iOS gives the phone its push address.
    func didRegister(deviceToken: Data) {
        guard FirebaseSetup.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.token = fcmToken
            if let uid = self.activeUid, uid == Auth.auth().currentUser?.uid {
                await self.save(fcmToken, uid: uid)
            }
        }
    }

    private func save(_ token: String, uid: String) async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        do {
            try await FS.devices(uid).document(token).setData([
                "token": token,
                "platform": "ios",
                "appVersion": version,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            ErrorCenter.shared.report(error, "Setting up instant alerts")
        }
    }
}

/// Receives the push address from iOS and shows notifications while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistration.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            ErrorCenter.shared.report(error, "Setting up instant alerts")
        }
    }

    /// Show alerts as a banner even when the app is open (a defect reported while you're looking at the app).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
