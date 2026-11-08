import Foundation
import Network

/// Tracks whether the device has a network connection, and nudges the photo
/// upload queue whenever a connection comes back.
@MainActor
@Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                let monitor = ConnectivityMonitor.shared
                let cameBack = online && !monitor.isOnline
                monitor.isOnline = online
                if cameBack {
                    PhotoUploadQueue.shared.process()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "ConnectivityMonitor"))
    }
}
