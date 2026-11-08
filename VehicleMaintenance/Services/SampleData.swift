import Foundation
import SwiftData

/// Demo content for SwiftUI previews and the debug "Load Sample Data" button.
enum SampleData {
    @MainActor
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now) ?? .now }

        let sedan = Vehicle(name: "Daily Driver", make: "Toyota", modelName: "Camry", year: 2019,
                            licensePlate: "8ABC123", odometer: 48_250)
        let truck = Vehicle(make: "Ford", modelName: "F-150", year: 2016, odometer: 102_400)
        context.insert(sedan)
        context.insert(truck)

        let sedanRecords: [(ServiceType, Int, Int, Double, String)] = [
            (.oilChange, 170, 43_400, 79.99, "Quick Lube"),
            (.tireRotation, 170, 43_400, 25.00, "Quick Lube"),
            (.cabinFilter, 300, 40_100, 34.50, "DIY"),
            (.brakes, 420, 37_800, 389.00, "Main Street Auto"),
            (.oilChange, 360, 38_500, 74.99, "Quick Lube"),
        ]
        for (type, days, odometer, cost, shop) in sedanRecords {
            let record = ServiceRecord(date: daysAgo(days), odometer: odometer, serviceType: type, cost: cost, shop: shop)
            context.insert(record)
            record.vehicle = sedan
        }

        let sedanReminders: [(ServiceType, Int?, Int?, Int, Int)] = [
            (.oilChange, 5_000, 6, 170, 43_400),
            (.tireRotation, 6_000, 6, 170, 43_400),
            (.cabinFilter, 15_000, 12, 300, 40_100),
            (.inspection, nil, 12, 350, 39_000),
        ]
        for (type, distance, months, days, odometer) in sedanReminders {
            let reminder = MaintenanceReminder(serviceType: type, intervalDistance: distance, intervalMonths: months,
                                               lastServiceDate: daysAgo(days), lastServiceOdometer: odometer,
                                               notificationsEnabled: false)
            context.insert(reminder)
            reminder.vehicle = sedan
        }

        let truckRecord = ServiceRecord(date: daysAgo(400), odometer: 96_000, serviceType: .oilChange, cost: 92.00, shop: "Dealer")
        context.insert(truckRecord)
        truckRecord.vehicle = truck

        let truckReminder = MaintenanceReminder(serviceType: .oilChange, intervalDistance: 5_000, intervalMonths: 6,
                                                lastServiceDate: daysAgo(400), lastServiceOdometer: 96_000,
                                                notificationsEnabled: false)
        context.insert(truckReminder)
        truckReminder.vehicle = truck
    }

    @MainActor
    static let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Vehicle.self, ServiceRecord.self, MaintenanceReminder.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            insert(into: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()
}
