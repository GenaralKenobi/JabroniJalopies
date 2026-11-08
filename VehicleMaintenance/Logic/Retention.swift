import Foundation

/// Records are kept for five years, then deleted automatically by Firestore's
/// TTL policy (documents) and a Cloud Storage lifecycle rule (photos).
enum Retention {
    static let years = 5

    static func expiry(from date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: years, to: date) ?? date.addingTimeInterval(5 * 365.25 * 86_400)
    }
}
