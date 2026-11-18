import SwiftUI

@main
struct VehicleMaintenanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth: AuthModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseSetup.configure()
        _auth = State(initialValue: AuthModel())
        _ = ConnectivityMonitor.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(ErrorCenter.shared)
                .environment(ConnectivityMonitor.shared)
                .environment(PhotoUploadQueue.shared)
                .task {
                    #if DEBUG
                    await DemoSeeder.runIfRequested()
                    #endif
                    PhotoUploadQueue.shared.process()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PhotoUploadQueue.shared.process()
                BackgroundSync.appDidBecomeActive()
            case .background:
                PhotoUploadQueue.shared.scheduleBackgroundRefresh()
                BackgroundSync.appDidEnterBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundSync.refreshId)) {
            await BackgroundSync.handleWake()
        }
    }
}
