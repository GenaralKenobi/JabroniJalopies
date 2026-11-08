import Foundation
import SwiftData

@Model
final class Vehicle {
    /// Optional nickname, e.g. "Daily Driver".
    var name: String = ""
    var make: String = ""
    var modelName: String = ""
    var year: Int = 0
    var vin: String = ""
    var licensePlate: String = ""
    /// Latest known odometer reading, in the user's distance unit.
    var odometer: Int = 0
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.vehicle)
    var serviceRecords: [ServiceRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceReminder.vehicle)
    var reminders: [MaintenanceReminder]? = []

    init(
        name: String = "",
        make: String = "",
        modelName: String = "",
        year: Int = Calendar.current.component(.year, from: .now),
        vin: String = "",
        licensePlate: String = "",
        odometer: Int = 0,
        photoData: Data? = nil
    ) {
        self.name = name
        self.make = make
        self.modelName = modelName
        self.year = year
        self.vin = vin
        self.licensePlate = licensePlate
        self.odometer = odometer
        self.photoData = photoData
        self.createdAt = .now
    }
}

extension Vehicle {
    /// "2019 Toyota Camry"
    var yearMakeModel: String {
        [year > 0 ? String(year) : "", make, modelName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var displayName: String {
        if !name.isEmpty { return name }
        let ymm = yearMakeModel
        return ymm.isEmpty ? "Vehicle" : ymm
    }

    /// Shown under the display name when a nickname is used.
    var subtitle: String { name.isEmpty ? "" : yearMakeModel }

    /// Newest first.
    var sortedRecords: [ServiceRecord] {
        (serviceRecords ?? []).sorted { $0.date > $1.date }
    }

    /// Most urgent first.
    var sortedReminders: [MaintenanceReminder] {
        (reminders ?? []).sorted(by: MaintenanceReminder.urgencyOrder)
    }

    var overallStatus: DueStatus {
        (reminders ?? []).map(\.status).max() ?? .ok
    }

    var totalSpent: Double {
        (serviceRecords ?? []).reduce(0) { $0 + $1.cost }
    }

    func spent(inYearOf date: Date, calendar: Calendar = .current) -> Double {
        let year = calendar.component(.year, from: date)
        return (serviceRecords ?? [])
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.cost }
    }
}
