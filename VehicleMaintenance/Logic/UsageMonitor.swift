import Foundation

/// Estimates how close a fleet is to Firebase's free allowances.
struct UsageReport: Equatable {
    enum Level: Int, Comparable {
        case ok, warning, critical
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Cloud Storage no-cost allowance on the Blaze plan.
    static let photoAllowanceBytes: Int64 = 5 * 1_000_000_000
    /// Firestore free stored-data allowance.
    static let databaseAllowanceBytes: Int64 = 1_073_741_824
    /// Rough average size of an inspection, defect or service record with its index entries.
    static let estimatedBytesPerRecord: Int64 = 4_096

    static let warningFraction = 0.8
    static let criticalFraction = 0.95

    var photoBytes: Int64
    var photoCount: Int64
    var recordCount: Int64

    init(usage: FleetUsage?) {
        photoBytes = max(0, usage?.photoBytes ?? 0)
        photoCount = max(0, usage?.photoCount ?? 0)
        recordCount = max(0, usage?.recordCount ?? 0)
    }

    var estimatedDatabaseBytes: Int64 { recordCount * Self.estimatedBytesPerRecord }
    var photoFraction: Double { Double(photoBytes) / Double(Self.photoAllowanceBytes) }
    var databaseFraction: Double { Double(estimatedDatabaseBytes) / Double(Self.databaseAllowanceBytes) }

    var level: Level {
        let worst = max(photoFraction, databaseFraction)
        if worst >= Self.criticalFraction { return .critical }
        if worst >= Self.warningFraction { return .warning }
        return .ok
    }

    var summary: String {
        switch level {
        case .ok: "Storage is well within the free allowance."
        case .warning: "Storage is over 80% of the free allowance. Consider deleting old records."
        case .critical: "Storage is nearly at the free allowance. Delete old records or expect small charges."
        }
    }
}
