import SwiftUI

/// Routes between setup, sign-in, email verification, fleet selection and the main app.
struct RootView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(ErrorCenter.self) private var errors
    @State private var session: SessionModel?

    private var sessionKey: String {
        guard let uid = auth.uid, !auth.needsEmailVerification else { return "" }
        return uid
    }

    var body: some View {
        Group {
            if !FirebaseSetup.isConfigured {
                SetupNeededView()
            } else if auth.isLoading {
                ProgressView()
            } else if !auth.isSignedIn {
                SignInView()
            } else if auth.needsEmailVerification {
                VerifyEmailView()
            } else if let session {
                SessionRootView()
                    .environment(session)
            } else {
                ProgressView()
            }
        }
        .onChange(of: sessionKey, initial: true) { _, key in
            session?.stop()
            if !key.isEmpty, let email = auth.email {
                session = SessionModel(uid: key, email: email)
            } else {
                session = nil
            }
        }
        .alert("Couldn't Sync", isPresented: Binding(
            get: { errors.message != nil },
            set: { if !$0 { errors.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errors.message ?? "")
        }
    }
}

struct SessionRootView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        if let fleet = session.fleetModel {
            MainTabView()
                .environment(fleet)
                .id(fleet.fleetId)
        } else if !session.membershipsLoaded {
            ProgressView("Loading your fleets…")
        } else {
            NavigationStack {
                FleetPickerView(isInitialSetup: true)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(FleetModel.self) private var fleet

    @State private var selectedTab: Tab = DemoConfig.initialTab ?? .fleet

    enum Tab: String {
        case fleet, defects, upcoming, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            VehicleListView()
                .tabItem { Label("Fleet", systemImage: "car.2.fill") }
                .tag(Tab.fleet)

            DefectsTabView()
                .tabItem { Label("Defects", systemImage: "exclamationmark.triangle.fill") }
                .badge(defectBadge)
                .tag(Tab.defects)

            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar.badge.clock") }
                .tag(Tab.upcoming)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }

    private var defectBadge: Int {
        fleet.allOpenDefects.count + (fleet.isManager ? fleet.allPendingServices.count : 0)
    }
}
