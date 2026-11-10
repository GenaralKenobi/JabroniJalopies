import Foundation
import Testing
@testable import VehicleMaintenance

private func item(_ name: String, _ location: String = "", quantity: Int? = nil, notes: String = "") -> TruckItem {
    TruckItem(name: name, quantity: quantity, location: location, notes: notes)
}

struct TruckContentsTests {
    @Test func groupsByLocationWithUnplacedItemsLast() {
        let groups = TruckContents.grouped([
            item("Wedges", "Left side box"),
            item("Rain gear"),
            item("First-aid kit", "Cab"),
            item("Bar oil", "left side box "),
            item("Cones", "Bed"),
        ])
        #expect(groups.map(\.title) == ["Bed", "Cab", "Left side box", "Other"])
        #expect(groups[2].items.map(\.name) == ["Bar oil", "Wedges"])
    }

    @Test func callsTheOnlyGroupItemsWhenNothingHasALocation() {
        let groups = TruckContents.grouped([item("Rain gear"), item("Cones")])
        #expect(groups.map(\.title) == ["Items"])
        #expect(groups[0].items.map(\.name) == ["Cones", "Rain gear"])
    }

    @Test func searchesNameLocationAndNotes() {
        let items = [
            item("Fire extinguisher", "Cab", notes: "Behind the driver seat"),
            item("Mix gas", "Left side box", notes: "Red cans"),
        ]
        #expect(TruckContents.filter(items, "driver").map(\.name) == ["Fire extinguisher"])
        #expect(TruckContents.filter(items, "left gas").map(\.name) == ["Mix gas"])
        #expect(TruckContents.filter(items, "  ").count == 2)
        #expect(TruckContents.grouped(items, matching: "cab").map(\.title) == ["Cab"])
    }

    @Test func listsDistinctLocations() {
        let items = [item("A", "Cab"), item("B", "cab"), item("C", " Bed "), item("D")]
        #expect(TruckContents.locations(items) == ["Bed", "Cab"])
    }

    @Test func copiesOnlyItemsTheTruckDoesNotHave() {
        let source = [item("Cones", "Bed", quantity: 6), item("Rakes", "Bed"), item("Cones", "Cab")]
        let target = [item("cones ", "bed", quantity: 2)]
        let missing = TruckContents.missing(from: source, in: target)
        #expect(missing.map { "\($0.name)@\($0.location)" } == ["Rakes@Bed", "Cones@Cab"])
    }

    @Test func formatsQuantity() {
        #expect(TruckContents.quantityText(3) == "×3")
        #expect(TruckContents.quantityText(nil) == nil)
    }
}
