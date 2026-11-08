import FirebaseFirestore
import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Collects errors from background syncing so they can be shown to the user.
/// Writes are queued while offline and may be rejected much later, so errors
/// can't always be shown where the action happened.
@MainActor
@Observable
final class ErrorCenter {
    static let shared = ErrorCenter()

    var message: String?

    func report(_ error: Error?, _ context: String) {
        guard let error else { return }
        message = "\(context): \(Self.friendly(error))"
    }

    static func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: nsError.code) {
            case .permissionDenied:
                return "You don't have permission to do that. Your role or vehicle access may have changed."
            case .unavailable:
                return "The server can't be reached. Your changes are saved and will sync when you're back online."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// Commits a batch without waiting for the server. Firestore applies it to the
/// local cache immediately, so the app works offline; the server confirms later.
func commitInBackground(_ batch: WriteBatch, _ context: String) {
    batch.commit { error in
        MainActor.assumeIsolated {
            ErrorCenter.shared.report(error, context)
        }
    }
}

/// Starts a query listener that decodes documents into `T`.
func firestoreListen<T: Decodable>(
    _ query: Query,
    includeMetadataChanges: Bool = false,
    onError: (@MainActor (Error) -> Void)? = nil,
    _ handler: @escaping @MainActor ([T], QuerySnapshot) -> Void
) -> ListenerRegistration {
    query.addSnapshotListener(includeMetadataChanges: includeMetadataChanges) { snapshot, error in
        MainActor.assumeIsolated {
            if let error {
                onError?(error)
                return
            }
            guard let snapshot else { return }
            let items: [T] = snapshot.documents.compactMap { document in
                do {
                    return try document.data(as: T.self)
                } catch {
                    #if DEBUG
                    print("Failed to decode \(document.reference.path): \(error)")
                    #endif
                    return nil
                }
            }
            handler(items, snapshot)
        }
    }
}

extension Error {
    var isPermissionDenied: Bool {
        let nsError = self as NSError
        return nsError.domain == FirestoreErrorDomain && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }
}
