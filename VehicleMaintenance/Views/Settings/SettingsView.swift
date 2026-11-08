import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(SessionModel.self) private var session
    @Environment(FleetModel.self) private var fleet
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var editingProfile = false
    @State private var renamingFleet = false
    @State private var fleetName = ""
    @State private var confirmingLeave = false
    @State private var errorMessage: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    if let me = fleet.me {
                        Button { editingProfile = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(me.displayName).foregroundStyle(Color.primary)
                                    Text("\(me.role.displayName) · \(me.email)").font(.caption).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Text("Edit").foregroundStyle(.tint)
                            }
                        }
                    }
                } header: {
                    Text("Your Profile in \(fleet.fleet?.name ?? "This Fleet")")
                }

                fleetSection

                if fleet.isManager {
                    managerSection
                }

                Section("App") {
                    Picker("Distance Unit", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    notificationRow
                }

                Section("Account") {
                    LabeledContent("Signed in as", value: session.email)
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Button("Sign Out") {
                        Task {
                            session.stop()
                            await auth.signOut()
                        }
                    }
                    NavigationLink("Delete Account") { DeleteAccountView() }
                        .foregroundStyle(.red)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .syncStatusBanner()
            .task { await refreshNotificationStatus() }
            .onAppear(perform: openDemoScreenIfNeeded)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshNotificationStatus() } }
            }
            .navigationDestination(for: String.self) { screen in
                switch screen {
                case "members": MembersView()
                case "storage": DataStorageView()
                case "checklists": ChecklistTemplatesView()
                case "equipment": EquipmentListView()
                case "chains": ChainTotalsView()
                default: EmptyView()
                }
            }
            .sheet(isPresented: $editingProfile) { ProfileEditView() }
            .alert("Rename Fleet", isPresented: $renamingFleet) {
                TextField("Fleet name", text: $fleetName)
                Button("Save") { if !fleetName.trimmed.isEmpty { fleet.renameFleet(fleetName) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Leave \(fleet.fleet?.name ?? "this fleet")?", isPresented: $confirmingLeave,
                                titleVisibility: .visible) {
                Button("Leave Fleet", role: .destructive) {
                    Task {
                        do { try await session.leave(fleetId: fleet.fleetId) } catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: {
                Text("Your past checklists and reports stay in the fleet's records.")
            }
        }
    }

    private var fleetSection: some View {
        Section("Fleet") {
            LabeledContent("Fleet", value: fleet.fleet?.name ?? "")
            NavigationLink(value: "members") {
                LabeledContent("Members", value: "\(fleet.members.count)")
            }
            NavigationLink("Switch or Join Fleet") { FleetPickerView() }
            Button("Leave Fleet", role: .destructive) { confirmingLeave = true }
        }
    }

    private var managerSection: some View {
        Section {
            NavigationLink(value: "checklists") {
                LabeledContent("Checklists", value: "\(fleet.checklists.count)")
            }
            NavigationLink(value: "equipment") {
                LabeledContent("Chainsaws & Ropes", value: "\(fleet.equipment.count)")
            }
            NavigationLink(value: "chains") {
                Text("Chain Totals")
            }
            Toggle("Defect Photos", isOn: Binding(
                get: { fleet.photosEnabled },
                set: { fleet.setPhotosEnabled($0) }
            ))
            NavigationLink(value: "storage") {
                HStack {
                    Text("Data & Storage")
                    Spacer()
                    if fleet.usage.level != .ok {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(fleet.usage.level == .critical ? Color.red : Color.orange)
                    }
                }
            }
            Button("Rename Fleet") {
                fleetName = fleet.fleet?.name ?? ""
                renamingFleet = true
            }
        } header: {
            Text("Manager")
        } footer: {
            Text("Defect photos need Cloud Storage, which requires Firebase's pay-as-you-go (Blaze) plan. Turn this on after enabling Storage — see FIREBASE_SETUP.md.")
        }
    }

    @ViewBuilder
    private var notificationRow: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Notifications are on", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Button("Turn On Notifications in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        default:
            Button("Enable Notifications") {
                Task {
                    await ReminderNotifications.requestAuthorization()
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openDemoScreenIfNeeded() {
        guard path.isEmpty, let screen = DemoConfig.screen, ["members", "storage", "checklists", "equipment", "chains"].contains(screen) else { return }
        path.append(screen)
    }
}

enum AppLinks {
    /// Must be a public URL for the App Store listing. Update after publishing PRIVACY.md (see README).
    static let privacyPolicy = URL(string: "https://github.com/GenaralKenobi/Maintenance-/blob/main/PRIVACY.md")!
}

struct ProfileEditView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ProfileDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileFields(profile: $profile)
                } footer: {
                    Text("This profile is only used in \(fleet.fleet?.name ?? "this fleet"). Other fleets keep their own.")
                }
            }
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        fleet.updateMyProfile(profile)
                        dismiss()
                    }
                    .disabled(!profile.isValid)
                }
            }
            .onAppear {
                profile = ProfileDraft(displayName: fleet.me?.displayName ?? "", phone: fleet.me?.phone ?? "")
            }
        }
    }
}

struct DataStorageView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var cutoff = Calendar.current.date(byAdding: .year, value: -3, to: .now) ?? .now
    @State private var confirmingPurge = false
    @State private var isPurging = false
    @State private var resultMessage: String?

    var body: some View {
        let report = fleet.usage
        Form {
            if report.level != .ok {
                Section {
                    Label(report.summary, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(report.level == .critical ? Color.red : Color.orange)
                }
            }

            Section {
                usageRow(title: "Photos",
                         detail: "\(report.photoCount) photos · \(bytes(report.photoBytes)) of \(bytes(UsageReport.photoAllowanceBytes))",
                         fraction: report.photoFraction)
                usageRow(title: "Records",
                         detail: "\(report.recordCount) records · about \(bytes(report.estimatedDatabaseBytes)) of \(bytes(UsageReport.databaseAllowanceBytes))",
                         fraction: report.databaseFraction)
            } header: {
                Text("Usage")
            } footer: {
                Text("Compared with Firebase's free allowances. Record size is an estimate. You'll also get a notification if storage passes 80%. For an email alert, set a budget in Google Cloud Billing (see FIREBASE_SETUP.md).")
            }

            Section {
                Label("Records are deleted automatically 5 years after they're created (defects: 5 years after they're closed).",
                      systemImage: "clock.arrow.circlepath")
                    .font(.subheadline)
            }

            Section {
                DatePicker("Delete records before", selection: $cutoff, in: ...Date.now, displayedComponents: .date)
                Button(role: .destructive) {
                    confirmingPurge = true
                } label: {
                    if isPurging {
                        HStack { ProgressView(); Text("Deleting…") }
                    } else {
                        Text("Delete Old Records")
                    }
                }
                .disabled(isPurging || !connectivity.isOnline)
                if let resultMessage {
                    Text(resultMessage).font(.subheadline)
                }
            } header: {
                Text("Free Up Space")
            } footer: {
                Text(connectivity.isOnline
                     ? "Deletes completed checklists, closed defects with their photos, reviewed service records, chain logs and reviewed rope changes from before this date. Open defects and anything awaiting approval are kept."
                     : "Needs a connection.")
            }
        }
        .navigationTitle("Data & Storage")
        .confirmationDialog("Permanently delete records from before \(cutoff.formatted(date: .abbreviated, time: .omitted))?",
                            isPresented: $confirmingPurge, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { purge() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func usageRow(title: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(Color.secondary)
            }
            ProgressView(value: min(fraction, 1))
                .tint(fraction >= UsageReport.criticalFraction ? Color.red : fraction >= UsageReport.warningFraction ? Color.orange : Color.brand)
            Text(detail).font(.caption).foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 4)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func purge() {
        isPurging = true
        resultMessage = nil
        Task {
            do {
                let summary = try await fleet.purgeRecords(before: cutoff)
                resultMessage = "Deleted \(summary.inspections) checklists, \(summary.defects) defects (\(summary.photos) photos), \(summary.services) service records, \(summary.chainLogs) chain logs and \(summary.lengthChanges) rope changes."
            } catch {
                resultMessage = "Couldn't finish: \(ErrorCenter.friendly(error))"
            }
            isPurging = false
        }
    }
}

struct DeleteAccountView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(SessionModel.self) private var session
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var confirming = false

    var body: some View {
        Form {
            Section {
                Text("Deleting your account removes your login, your profiles, and your membership in every fleet. Checklists and reports you submitted stay in each fleet's records, labelled with your name, until they're deleted under the fleet's retention policy.")
                    .font(.subheadline)
                Text("If you're the only manager of a fleet with other members, make someone else a manager first. If you're the only member, the fleet and all its data are deleted.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("Enter your password to confirm. Needs a connection.")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    if isDeleting { ProgressView() } else { Text("Delete My Account") }
                }
                .disabled(password.isEmpty || isDeleting || !connectivity.isOnline)
            }
        }
        .navigationTitle("Delete Account")
        .confirmationDialog("Delete your account permanently?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { delete() }
        }
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await auth.reauthenticate(password: password)
                try await session.deleteAllUserData()
                try await auth.deleteAuthUser()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }
}
