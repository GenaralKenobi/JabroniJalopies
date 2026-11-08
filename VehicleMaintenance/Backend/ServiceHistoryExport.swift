import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A vehicle's service history as a shareable CSV file.
struct ServiceHistoryExport: Transferable {
    let csv: String

    init(records: [ServiceRecord], costs: [String: Double], includeCosts: Bool, unit: DistanceUnit) {
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var header = ["Date", "Service", "Odometer (\(unit.abbreviation))", "Shop", "Status", "Logged by", "Notes"]
        if includeCosts { header.insert("Cost", at: 3) }
        let rows = records.map { record in
            var row = [
                record.date.formatted(dateStyle),
                record.displayTitle,
                String(record.odometer),
                record.shop,
                record.status.rawValue,
                record.createdByName,
                record.notes,
            ]
            if includeCosts {
                row.insert(record.id.flatMap { costs[$0] }.map { String(format: "%.2f", $0) } ?? "", at: 3)
            }
            return row
        }
        csv = CSV.make(header: header, rows: rows)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("Service History.csv")
    }
}
