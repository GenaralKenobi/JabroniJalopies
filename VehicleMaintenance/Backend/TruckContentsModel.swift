import FirebaseFirestore
import Foundation

/// A truck's contents list, kept up to date while its screen is open (works offline from the cache).
@MainActor
@Observable
final class TruckContentsModel {
    private(set) var items: [TruckItem] = []
    private(set) var loaded = false
    /// Items changed on this phone that haven't reached the server yet.
    private(set) var unsyncedIds: Set<String> = []

    @ObservationIgnored nonisolated(unsafe) private var listener: ListenerRegistration?

    init(fleetId: String, vehicleId: String) {
        listener = firestoreListen(FS.contents(fleetId, vehicleId), includeMetadataChanges: true,
                                   onError: { [weak self] _ in self?.loaded = true }) { [weak self] (items: [TruckItem], snapshot) in
            self?.items = items
            self?.unsyncedIds = Set(snapshot.documents.filter(\.metadata.hasPendingWrites).map(\.documentID))
            self?.loaded = true
        }
    }

    deinit {
        listener?.remove()
    }
}
