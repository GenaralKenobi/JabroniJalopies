import Foundation

enum Formatting {
    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    static func distance(_ value: Int, unit: DistanceUnit) -> String {
        "\(value.formatted()) \(unit.abbreviation)"
    }

    static func feet(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) ft"
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
