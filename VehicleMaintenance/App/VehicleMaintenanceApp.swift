import SwiftData
import SwiftUI

@main
struct VehicleMaintenanceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Vehicle.self, ServiceRecord.self, MaintenanceReminder.self])
    }
}
