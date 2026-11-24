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

    @Test func kitsListWhatsInsideAndSearchFindsIt() {
        var kit = item("First-aid kit", "Cab")
        kit.parts = [KitPart.new("Gauze pads", quantity: 4), KitPart.new("Eyewash"), KitPart.new("  ")]
        #expect(TruckContents.partsText(kit.parts) == "Gauze pads ×4 · Eyewash")
        #expect(TruckContents.partsText(nil) == nil)
        #expect(TruckContents.filter([kit, item("Rope")], "eyewash").map(\.name) == ["First-aid kit"])
    }

    @Test func formatsQuantity() {
        #expect(TruckContents.quantityText(3) == "×3")
        #expect(TruckContents.quantityText(nil) == nil)
    }
}

struct ServiceContactTests {
    @Test func emptyFieldsAreDroppedAndAllEmptyIsNil() {
        #expect(ServiceContact.cleaned(name: "  ", phone: "", website: "", address: "\n") == nil)
        let contact = ServiceContact.cleaned(name: " Main Street Ford ", phone: "", website: "", address: "")
        #expect(contact?.name == "Main Street Ford")
        #expect(contact?.phone == nil)
    }

    @Test func linksForPhoneWebsiteAndAddress() {
        let contact = ServiceContact(name: nil, phone: "(555) 123-4567", website: "mainstreetford.com", address: "12 Main St, Springfield")
        #expect(contact.phoneURL?.absoluteString == "tel:5551234567")
        #expect(contact.websiteURL?.absoluteString == "https://mainstreetford.com")
        #expect(contact.mapsURL?.absoluteString.hasPrefix("https://maps.apple.com/?q=12%20Main%20St") == true)
        #expect(ServiceContact(name: nil, phone: "+1 555 123 4567", website: "http://x.com", address: nil).phoneURL?.absoluteString == "tel:+15551234567")
        #expect(ServiceContact(name: nil, phone: "call Bob", website: "not a site", address: nil).phoneURL == nil)
        #expect(ServiceContact(name: nil, phone: nil, website: "not a site", address: nil).websiteURL == nil)
    }
}
