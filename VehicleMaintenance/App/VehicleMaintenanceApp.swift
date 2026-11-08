import SwiftUI

@main
struct VehicleMaintenanceApp: App {
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
            case .active: PhotoUploadQueue.shared.process()
            case .background: PhotoUploadQueue.shared.scheduleBackgroundRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(PhotoUploadQueue.backgroundTaskId)) {
            await PhotoUploadQueue.shared.processInBackground()
        }
    }
}
