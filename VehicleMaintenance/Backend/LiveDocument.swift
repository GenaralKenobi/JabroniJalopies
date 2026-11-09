import FirebaseFirestore
import Foundation

/// A single Firestore document kept up to date while a screen is open.
@MainActor
@Observable
final class LiveDocument<T: Decodable> {
    private(set) var value: T?
    private(set) var exists = true
    private(set) var hasPendingWrites = false
    @ObservationIgnored nonisolated(unsafe) private var listener: ListenerRegistration?

    init(_ reference: DocumentReference) {
        listener = reference.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if error != nil {
                    // No access (or it was deleted): show "not found" instead of spinning forever.
                    self.exists = false
                    return
                }
                guard let snapshot else { return }
                self.exists = snapshot.exists
                self.value = try? snapshot.data(as: T.self)
                self.hasPendingWrites = snapshot.metadata.hasPendingWrites
            }
        }
    }

    deinit {
        listener?.remove()
    }
}
