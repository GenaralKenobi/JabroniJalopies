import SwiftData
import SwiftUI

enum AppTab: String {
    case garage, upcoming, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = Self.initialTab

    var body: some View {
        TabView(selection: $selectedTab) {
            VehicleListView()
                .tabItem { Label("Garage", systemImage: "car.fill") }
                .tag(AppTab.garage)

            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar.badge.clock") }
                .tag(AppTab.upcoming)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task { loadDemoDataIfRequested() }
    }

    // MARK: Launch arguments (debug builds only)
    //
    // CI launches the app with `-demoData YES -initialTab upcoming` to capture
    // screenshots. These arrive through the UserDefaults argument domain.

    private static var initialTab: AppTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "initialTab"), let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .garage
    }

    private func loadDemoDataIfRequested() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "demoData") else { return }
        let existing = (try? modelContext.fetchCount(FetchDescriptor<Vehicle>())) ?? 0
        if existing == 0 {
            SampleData.insert(into: modelContext)
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
