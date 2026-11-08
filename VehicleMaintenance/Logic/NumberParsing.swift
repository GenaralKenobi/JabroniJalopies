import Foundation

/// Lenient parsing for numbers typed into text fields.
enum NumberParsing {
    /// Keeps only digits, so "48,250" and "48 250" both parse to 48250.
    static func int(_ text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Locale-aware decimal parsing ("89.99" or "89,99" depending on region).
    static func decimal(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        if let number = formatter.number(from: trimmed) { return number.doubleValue }
        return Double(trimmed)
    }
}
