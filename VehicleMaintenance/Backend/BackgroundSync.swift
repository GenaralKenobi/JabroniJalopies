import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit
import UserNotifications

/// Gets checklists, defects and photos to the server when the app isn't on screen.
///
/// iOS freezes an app a few seconds after it leaves the screen, and Firestore only sends
/// while the app is running. So:
/// 1. When the app leaves the screen, it asks iOS for extra time to finish sending.
/// 2. If changes are still waiting (usually no signal), it asks iOS to wake it in the
///    background, including a task that runs only when the phone has a connection.
/// 3. If a problem they reported (or its photo) still hasn't gone after 2 hours, a notification
///    asks the person to open the app. Other changes (checklists, readings) don't trigger it.
/// iOS decides when background wake-ups happen, so 3 is the safety net.
@MainActor
enum BackgroundSync {
    /// Background refresh (shared with the photo queue; the id is kept for existing installs).
    static let refreshId = PhotoUploadQueue.backgroundTaskId
    /// Runs when the phone has a network connection.
    static let processingId = "com.generalkenobi.jabronijalopies.sync"
    private static let reminderId = "unsynced-changes-reminder"
    private static let reminderDelay: TimeInterval = 2 * 60 * 60

    private final class TaskBox: @unchecked Sendable {
        var id: UIBackgroundTaskIdentifier = .invalid
    }

    /// The app just left the screen.
    static func appDidEnterBackground() {
        guard FirebaseSetup.isConfigured, Auth.auth().currentUser != nil else { return }
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "Send changes") {
            UIApplication.shared.endBackgroundTask(box.id)
            box.id = .invalid
        }
        Task { @MainActor in
            PhotoUploadQueue.shared.process()
            // iOS gives about 30 seconds; leave a margin.
            let unsynced = await FirebaseSetup.hasUnsyncedChanges(timeout: 20)
            if unsynced || PhotoUploadQueue.shared.pendingCount > 0 { scheduleWakeUps() }
            if await hasUnsentDefects() {
                await remindLater()
            } else {
                cancelReminder()
            }
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    /// The app is on screen again: the person can see the sync banner, so no reminder needed.
    static func appDidBecomeActive() {
        cancelReminder()
    }

    /// iOS woke the app in the background.
    static func handleWake() async {
        guard FirebaseSetup.isConfigured, Auth.auth().currentUser != nil else { return }
        let unsynced = await FirebaseSetup.hasUnsyncedChanges(timeout: 20)
        await PhotoUploadQueue.shared.processInBackground()
        if unsynced || PhotoUploadQueue.shared.pendingCount > 0 { scheduleWakeUps() }
        if await !hasUnsentDefects() { cancelReminder() }
    }

    /// Whether a problem this person reported (or changed), or a photo for one, is still only on this phone.
    private static func hasUnsentDefects() async -> Bool {
        if PhotoUploadQueue.shared.pendingCount > 0 { return true }
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        // Truck and equipment defects both live in collections named "defects".
        let query = Firestore.firestore().collectionGroup("defects").whereField("reportedBy", isEqualTo: uid)
        guard let snapshot = try? await query.getDocuments(source: .cache) else { return false }
        return snapshot.documents.contains { $0.metadata.hasPendingWrites }
    }

    /// Registers the connection-only task. Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingId, using: .main) { task in
            let work = Task { @MainActor in
                await handleWake()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    private static func scheduleWakeUps() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshId)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: processingId)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(processing)
    }

    private static func remindLater() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Problem not sent yet"
        content.body = "A problem you reported hasn't reached your manager. Open Jabroni Jalopies when you have signal so it can send."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderDelay, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger))
    }

    private static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
    }
}
