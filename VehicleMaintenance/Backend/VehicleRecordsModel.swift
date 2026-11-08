import FirebaseFirestore
import Foundation

/// Detailed history for one vehicle, loaded while its detail screen is open.
@MainActor
@Observable
final class VehicleRecordsModel {
    let fleetId: String
    let vehicleId: String

    private(set) var inspections: [Inspection] = []
    /// Inspections saved on this phone that haven't reached the server yet.
    private(set) var unsyncedInspectionIds: Set<String> = []
    private(set) var defects: [Defect] = []
    private(set) var unsyncedDefectIds: Set<String> = []
    private(set) var services: [ServiceRecord] = []
    private(set) var costs: [String: Double] = [:]

    @ObservationIgnored nonisolated(unsafe) private var listeners: [ListenerRegistration] = []

    init(fleetId: String, vehicleId: String, includeCosts: Bool) {
        self.fleetId = fleetId
        self.vehicleId = vehicleId

        let inspectionsQuery = FS.inspections(fleetId, vehicleId).order(by: "completedAt", descending: true).limit(to: 100)
        listeners.append(firestoreListen(inspectionsQuery, includeMetadataChanges: true) { [weak self] (items: [Inspection], snapshot) in
            self?.inspections = items
            self?.unsyncedInspectionIds = Set(snapshot.documents.filter(\.metadata.hasPendingWrites).map(\.documentID))
        })

        let defectsQuery = FS.defects(fleetId, vehicleId).order(by: "reportedAt", descending: true).limit(to: 100)
        listeners.append(firestoreListen(defectsQuery, includeMetadataChanges: true) { [weak self] (items: [Defect], snapshot) in
            self?.defects = items
            self?.unsyncedDefectIds = Set(snapshot.documents.filter(\.metadata.hasPendingWrites).map(\.documentID))
        })

        let servicesQuery = FS.services(fleetId, vehicleId).order(by: "date", descending: true).limit(to: 200)
        listeners.append(firestoreListen(servicesQuery) { [weak self] (items: [ServiceRecord], _) in
            self?.services = items
        })

        if includeCosts {
            listeners.append(firestoreListen(FS.costs(fleetId, vehicleId)) { [weak self] (items: [ServiceCost], _) in
                var map: [String: Double] = [:]
                for cost in items { if let id = cost.id { map[id] = cost.amount } }
                self?.costs = map
            })
        }
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    var approvedServices: [ServiceRecord] { services.filter { $0.status == .approved } }

    func cost(of record: ServiceRecord) -> Double? {
        record.id.flatMap { costs[$0] }
    }

    var totalSpent: Double {
        approvedServices.compactMap { cost(of: $0) }.reduce(0, +)
    }

    func spent(inYearOf date: Date, calendar: Calendar = .current) -> Double {
        let year = calendar.component(.year, from: date)
        return approvedServices
            .filter { calendar.component(.year, from: $0.date) == year }
            .compactMap { cost(of: $0) }
            .reduce(0, +)
    }

    var monthlyCosts: [MonthlyCost] {
        CostAggregation.monthlyTotals(approvedServices.compactMap { record in
            cost(of: record).map { (date: record.date, cost: $0) }
        })
    }
}
