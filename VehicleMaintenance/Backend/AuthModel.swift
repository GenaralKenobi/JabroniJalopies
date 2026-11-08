import FirebaseAuth
import Foundation

/// The signed-in Firebase user.
@MainActor
@Observable
final class AuthModel {
    private(set) var uid: String?
    private(set) var email: String?
    private(set) var isEmailVerified = false
    private(set) var isLoading = true

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        guard FirebaseSetup.isConfigured else {
            isLoading = false
            return
        }
        handle = Auth.auth().addStateDidChangeListener { _, user in
            MainActor.assumeIsolated {
                self.update(user)
            }
        }
    }

    var isSignedIn: Bool { uid != nil }

    /// Skips the email-verification gate in emulator demo mode.
    var needsEmailVerification: Bool {
        isSignedIn && !isEmailVerified && !FirebaseSetup.usesEmulator
    }

    private func update(_ user: User?) {
        uid = user?.uid
        email = user?.email?.lowercased()
        isEmailVerified = user?.isEmailVerified ?? false
        isLoading = false
    }

    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email.trimmed, password: password)
            update(result.user)
        } catch {
            throw Self.friendly(error)
        }
    }

    func signUp(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email.trimmed, password: password)
            try? await result.user.sendEmailVerification()
            update(result.user)
        } catch {
            throw Self.friendly(error)
        }
    }

    func resendVerification() async throws {
        try await Auth.auth().currentUser?.sendEmailVerification()
    }

    /// Reloads the user and refreshes the ID token so the server sees `email_verified`.
    func refresh() async {
        guard let user = Auth.auth().currentUser else { return }
        try? await user.reload()
        _ = try? await user.getIDTokenResult(forcingRefresh: true)
        update(Auth.auth().currentUser)
    }

    func resetPassword(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmed)
        } catch {
            throw Self.friendly(error)
        }
    }

    func signOut() async {
        try? Auth.auth().signOut()
        update(nil)
        await FirebaseSetup.clearLocalCache()
    }

    /// Re-enters the password, which Firebase requires before deleting an account.
    func reauthenticate(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else { throw AppError("Not signed in.") }
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
        } catch {
            throw Self.friendly(error)
        }
    }

    func deleteAuthUser() async throws {
        try await Auth.auth().currentUser?.delete()
        update(nil)
        await FirebaseSetup.clearLocalCache()
    }

    static func friendly(_ error: Error) -> Error {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound:
            return AppError("That email and password don't match.")
        case .emailAlreadyInUse:
            return AppError("An account with that email already exists. Try signing in.")
        case .invalidEmail:
            return AppError("That email address doesn't look right.")
        case .weakPassword:
            return AppError("Choose a password with at least 6 characters.")
        case .networkError:
            return AppError("No connection. Signing in needs internet the first time.")
        case .tooManyRequests:
            return AppError("Too many attempts. Wait a moment and try again.")
        default:
            return error
        }
    }
}
