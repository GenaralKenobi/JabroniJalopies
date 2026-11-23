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
    @ObservationIgnored nonisolated(unsafe) private var inspectionsListener: ListenerRegistration?

    /// The vehicle screen shows the 5 newest checklists, so it loads 6 (the 6th means there are more).
    /// The full list loads up to 100 only when it's opened, which saves downloading a truck's whole
    /// history every time someone opens it.
    static let recentInspections = 6
    static let allInspections = 100
    private(set) var loadedAllInspections = false

    init(fleetId: String, vehicleId: String, includeCosts: Bool) {
        self.fleetId = fleetId
        self.vehicleId = vehicleId

        listenToInspections(limit: Self.recentInspections)

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
        inspectionsListener?.remove()
    }

    /// Called when the full checklist list opens.
    func loadAllInspections() {
        guard !loadedAllInspections else { return }
        loadedAllInspections = true
        listenToInspections(limit: Self.allInspections)
    }

    private func listenToInspections(limit: Int) {
        inspectionsListener?.remove()
        let query = FS.inspections(fleetId, vehicleId).order(by: "completedAt", descending: true).limit(to: limit)
        inspectionsListener = firestoreListen(query, includeMetadataChanges: true) { [weak self] (items: [Inspection], snapshot) in
            self?.inspections = items
            self?.unsyncedInspectionIds = Set(snapshot.documents.filter(\.metadata.hasPendingWrites).map(\.documentID))
        }
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
