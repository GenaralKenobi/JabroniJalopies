import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Distance Unit", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Existing odometer readings are not converted when you switch units.")
                }

                Section("Notifications") {
                    switch notificationStatus {
                    case .authorized, .provisional, .ephemeral:
                        Label("Reminder notifications are on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .denied:
                        Button("Turn On in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    default:
                        Button("Enable Reminder Notifications") {
                            Task {
                                await ReminderNotifications.requestAuthorization()
                                await refreshNotificationStatus()
                            }
                        }
                    }
                }

                #if DEBUG
                Section("Developer") {
                    Button("Load Sample Data") {
                        SampleData.insert(into: modelContext)
                    }
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .task { await refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshNotificationStatus() }
                }
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
