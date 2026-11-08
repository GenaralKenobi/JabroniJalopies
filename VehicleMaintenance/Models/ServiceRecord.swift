import Foundation
import SwiftData

@Model
final class ServiceRecord {
    var date: Date = Date.now
    var odometer: Int = 0
    var serviceTypeRaw: String = ServiceType.other.rawValue
    /// Custom description; required when the type is `.other`.
    var title: String = ""
    var cost: Double = 0
    var shop: String = ""
    var notes: String = ""
    var vehicle: Vehicle?

    init(
        date: Date = .now,
        odometer: Int = 0,
        serviceType: ServiceType = .other,
        title: String = "",
        cost: Double = 0,
        shop: String = "",
        notes: String = ""
    ) {
        self.date = date
        self.odometer = odometer
        self.serviceTypeRaw = serviceType.rawValue
        self.title = title
        self.cost = cost
        self.shop = shop
        self.notes = notes
    }
}

extension ServiceRecord {
    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .other }
        set { serviceTypeRaw = newValue.rawValue }
    }

    var displayTitle: String {
        title.isEmpty ? serviceType.displayName : title
    }
}
