import Foundation
import PDFKit
import Testing
@testable import VehicleMaintenance

struct PrintTests {
    private func checklist() -> ChecklistTemplate {
        var mirrors = ChecklistItem.new("Mirrors")
        mirrors.details = ["Not cracked", "  ", "Adjusted correctly", "Clear to see through"]
        return ChecklistTemplate(name: "Morning", items: [mirrors, .new("Lowest tire pressure", reading: "PSI"), .new("  "),
                                                          .new("Grease fittings", frequency: .weekly)],
                                 vehicleIds: [])
    }

    @Test func checklistPrintsItemsWithDetailBullets() {
        let doc = PrintDocument.checklist(checklist())
        #expect(doc.title == "Morning")
        #expect(doc.sections.first?.entries == [
            PrintDocument.Entry(title: "1. Mirrors", suffix: nil, bullets: ["Not cracked", "Adjusted correctly", "Clear to see through"]),
            PrintDocument.Entry(title: "2. Lowest tire pressure", suffix: "PSI: ________", bullets: []),
            PrintDocument.Entry(title: "3. Grease fittings", suffix: "(Weekly)", bullets: []),
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
            var item = ChecklistItem.new("Step \(n)")
            item.details = ["First thing to check", "Second thing to check"]
            return item
        }
        let data = PrintDocument.checklist(template).pdfData()
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for n in [1, 23, 45] { #expect(text.contains("\(n). Step \(n)")) }
        // An item and its details always land on the same page.
        for index in 0..<pdf.pageCount {
            let page = pdf.page(at: index)?.string ?? ""
            let titles = page.components(separatedBy: "Step ").count - 1
            let firsts = page.components(separatedBy: "First thing to check").count - 1
            let seconds = page.components(separatedBy: "Second thing to check").count - 1
            #expect(titles == firsts && firsts == seconds)
        }
    }

    @Test func truckListsUseTwoColumnsAndKeepEveryItem() throws {
        let items: [TruckItem] = (1...60).map { n in
            var item = TruckItem.new()
            item.name = "Thing \(n)"
            item.location = n <= 50 ? "Cab" : "Bed"  // 50 items in the cab run past a column
            return item
        }
        let doc = PrintDocument.contents(items, truckName: "Van 12")
        #expect(doc.columns == 2)
        #expect(doc.columnWidth < (PrintDocument.pageSize.width - PrintDocument.margin * 2) / 2)
        let pdf = try #require(PDFDocument(data: doc.pdfData()))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for n in 1...60 { #expect(text.contains("Thing \(n)")) }
        // A location that runs past a column says it continues.
        #expect(text.contains("(CONT.)"))
        // Two columns fit 60 short items on fewer pages than one column would.
        var single = doc
        single.columns = 1
        let singlePages = try #require(PDFDocument(data: single.pdfData())).pageCount
        #expect(pdf.pageCount < singlePages)
    }
}
