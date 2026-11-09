import Foundation

enum Formatting {
    /// All costs are in US dollars, whatever region a phone is set to.
    static let currencyCode = "USD"

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    static func distance(_ value: Int, unit: DistanceUnit) -> String {
        "\(value.formatted()) \(unit.abbreviation)"
    }

    static func feet(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) ft"
    }

    /// "today at 6:12 AM", "yesterday at 4:30 PM", or "Nov 3 at 6:05 AM".
    static func dayAndTime(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
