import BackgroundTasks
import FirebaseAuth
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
/// 3. If they still haven't gone after a while, a notification asks the person to open the app.
/// iOS decides when background wake-ups happen, so 3 is the safety net.
@MainActor
enum BackgroundSync {
    /// Background refresh (shared with the photo queue; the id is kept for existing installs).
    static let refreshId = PhotoUploadQueue.backgroundTaskId
    /// Runs when the phone has a network connection.
    static let processingId = "com.generalkenobi.jabronijalopies.sync"
    private static let reminderId = "unsynced-changes-reminder"
    private static let reminderDelay: TimeInterval = 45 * 60

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
            if unsynced || PhotoUploadQueue.shared.pendingCount > 0 {
                scheduleWakeUps()
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
        if unsynced || PhotoUploadQueue.shared.pendingCount > 0 {
            scheduleWakeUps()
        } else {
            cancelReminder()
        }
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
        content.title = "Not sent yet"
        content.body = "A checklist, problem or photo on this phone hasn't reached the fleet. Open Jabroni Jalopies when you have signal."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderDelay, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger))
    }

    private static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
    }
}
