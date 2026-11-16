import SwiftUI

struct SignInView: View {
    @Environment(AuthModel.self) private var auth

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resetSent = false
    @State private var showingPassword = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Jabroni Jalopies")
                            .font(.title2.bold())
                        Text("Checklists, defects and maintenance for your vehicles — even without signal.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    HStack {
                        Group {
                            if showingPassword {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }
                        Button {
                            showingPassword.toggle()
                        } label: {
                            Image(systemName: showingPassword ? "eye.slash" : "eye")
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
                    }
                } footer: {
                    if mode == .createAccount {
                        Text("Use at least 6 characters for your password. If your manager invited you, use the email address they invited. You'll get an email to confirm it.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else { Text(mode.rawValue).bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button(resetSent ? "Password reset email sent" : "Forgot password?") {
                            Task { await sendReset() }
                        }
                        .disabled(email.trimmed.isEmpty || resetSent)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, _ in errorMessage = nil }
        }
    }

    private var canSubmit: Bool { !isWorking && !email.trimmed.isEmpty && password.count >= 6 }

    private func submit() {
        focus = nil
        isWorking = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .signIn: try await auth.signIn(email: email, password: password)
                case .createAccount: try await auth.signUp(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func sendReset() async {
        do {
            try await auth.resetPassword(email: email)
            resetSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VerifyEmailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var message: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Confirm Your Email", systemImage: "envelope.badge")
            } description: {
                Text("We sent a link to \(auth.email ?? "your email"). Tap it, then come back here.\n\nConfirming your email lets your manager's invite find you.")
            } actions: {
                Button {
                    Task {
                        isChecking = true
                        await auth.refresh()
                        isChecking = false
                        if auth.needsEmailVerification { message = "Not confirmed yet. Check your inbox and spam folder." }
                    }
                } label: {
                    if isChecking { ProgressView() } else { Text("I've Confirmed It") }
                }
                .buttonStyle(.borderedProminent)

                Button("Resend Email") {
                    Task {
                        do {
                            try await auth.resendVerification()
                            message = "Sent. It can take a minute to arrive. Check your spam folder too."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Color.secondary)
                }
            }
        }
        // Coming back from the Mail app after tapping the link: check automatically.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await auth.refresh() } }
        }
    }
}

struct SetupNeededView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Firebase Not Set Up", systemImage: "gearshape.2")
        } description: {
            Text("This build doesn't include GoogleService-Info.plist. Follow FIREBASE_SETUP.md in the project repository to connect the app to your Firebase project.")
        }
    }
}
