import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A vehicle's service history as a shareable CSV file.
struct ServiceHistoryExport: Transferable {
    let csv: String

    init(vehicle: Vehicle, unit: DistanceUnit) {
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        let header = ["Date", "Service", "Odometer (\(unit.abbreviation))", "Cost", "Shop", "Notes"]
        let rows = vehicle.sortedRecords.map { record in
            [
                record.date.formatted(dateStyle),
                record.displayTitle,
                String(record.odometer),
                String(format: "%.2f", record.cost),
                record.shop,
                record.notes,
            ]
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
