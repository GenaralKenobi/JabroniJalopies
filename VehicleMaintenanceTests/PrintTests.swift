import Foundation
import PDFKit
import Testing
@testable import VehicleMaintenance

struct PrintTests {
    private func checklist() -> ChecklistTemplate {
        var mirrors = ChecklistItem.new("Mirrors")
        mirrors.details = ["Not cracked", "  ", "Adjusted correctly", "Clear to see through"]
        return ChecklistTemplate(name: "Morning", items: [mirrors, .new("Lowest tire pressure", reading: "PSI"), .new("  ")],
                                 vehicleIds: [])
    }

    @Test func checklistPrintsItemsWithDetailBullets() {
        let doc = PrintDocument.checklist(checklist())
        #expect(doc.title == "Morning")
        #expect(doc.sections.first?.entries == [
            PrintDocument.Entry(title: "Mirrors", suffix: nil, bullets: ["Not cracked", "Adjusted correctly", "Clear to see through"]),
            PrintDocument.Entry(title: "Lowest tire pressure", suffix: "PSI: ________", bullets: []),
        ])
    }

    @Test func contentsPrintByLocationWithKitParts() {
        var kit = TruckItem.new()
        kit.name = "First aid kit"
        kit.location = "Cab"
        kit.quantity = 1
        kit.notes = "Check monthly"
        kit.parts = [KitPart.new("Gauze", quantity: 4)]
        let doc = PrintDocument.contents([kit], truckName: "Van 12")
        #expect(doc.title == "Van 12: What's on the Truck")
        #expect(doc.sections.first?.entries.first == PrintDocument.Entry(title: "First aid kit", suffix: "×1",
                                                                         bullets: ["Gauze ×4", "Note: Check monthly"]))
    }

    @Test func longChecklistsMakeMultiplePagesWithEveryItem() throws {
        var template = checklist()
        template.items = (1...45).map { n in
            var item = ChecklistItem.new("Item \(n)")
            item.details = ["First thing to check", "Second thing to check"]
            return item
        }
        let data = PrintDocument.checklist(template).pdfData()
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for n in [1, 23, 45] { #expect(text.contains("Item \(n)")) }
        // An item and its details always land on the same page.
        for index in 0..<pdf.pageCount {
            let page = pdf.page(at: index)?.string ?? ""
            let titles = page.components(separatedBy: "\n").filter { $0.hasPrefix("Item ") }.count
            let firsts = page.components(separatedBy: "First thing to check").count - 1
            let seconds = page.components(separatedBy: "Second thing to check").count - 1
            #expect(titles == firsts && firsts == seconds)
        }
    }
}
