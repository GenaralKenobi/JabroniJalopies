import Foundation
import Testing
@testable import VehicleMaintenance

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let person = InspectionPlanner.Person(uid: "dan", name: "Dan")

private func sequentialIds() -> () -> String {
    var counter = 0
    return { counter += 1; return "id\(counter)" }
}

private func template(_ items: [ChecklistItem]) -> ChecklistTemplate {
    var checklist = ChecklistTemplate(name: "Morning", items: items, vehicleIds: [])
    checklist.id = "morning"
    return checklist
}

private let lights = ChecklistItem(id: "lights", title: "Lights", requiresReading: false, readingLabel: "", unsafeIfFailed: true)
private let tires = ChecklistItem(id: "tires", title: "Tire pressure", requiresReading: true, readingLabel: "PSI", unsafeIfFailed: false)
private let horn = ChecklistItem(id: "horn", title: "Horn", requiresReading: false, readingLabel: "", unsafeIfFailed: false)

private func openDefect(item: ChecklistItem, status: DefectStatus = .open, unsafe: Bool = false) -> Defect {
    var defect = Defect(itemId: item.id, title: item.title, details: "Broken", unsafe: unsafe, status: status,
                        reportedBy: "ana", reportedByName: "Ana", reportedAt: now.addingTimeInterval(-3600),
                        history: [], photos: [:])
    defect.id = "existing-\(item.id)"
    return defect
}

struct InspectionPlannerTests {
    @Test func requiresEveryItemAnswered() {
        let error = InspectionPlanner.validate(template: template([lights, horn]),
                                               answers: ["lights": ItemAnswer(verdict: .pass)],
                                               openDefectsByItem: [:])
        #expect(error == .unanswered(["Horn"]))
    }

    @Test func requiresNumberReadings() {
        let error = InspectionPlanner.validate(template: template([tires]),
                                               answers: ["tires": ItemAnswer(verdict: .pass, reading: "")],
                                               openDefectsByItem: [:])
        #expect(error == .missingReading(["Tire pressure"]))
    }

    @Test func requiresNoteWhenReportingExistingDefectFixed() {
        let existing = ["horn": openDefect(item: horn)]
        let missing = InspectionPlanner.validate(template: template([horn]),
                                                 answers: ["horn": ItemAnswer(verdict: .pass)],
                                                 openDefectsByItem: existing)
        #expect(missing == .missingFixNote(["Horn"]))
        let ok = InspectionPlanner.validate(template: template([horn]),
                                            answers: ["horn": ItemAnswer(verdict: .pass, note: "Works now")],
                                            openDefectsByItem: existing)
        #expect(ok == nil)
    }

    @Test func allPassingCreatesNoDefects() {
        let plan = InspectionPlanner.plan(
            template: template([lights, tires]),
            answers: ["lights": ItemAnswer(verdict: .pass), "tires": ItemAnswer(verdict: .pass, reading: "72")],
            openDefectsByItem: [:], person: person, odometer: 1000, now: now, makeId: sequentialIds())
        #expect(plan.newDefects.isEmpty)
        #expect(plan.defectUpdates.isEmpty)
        #expect(plan.inspection.failedCount == 0)
        #expect(plan.inspection.unsafe == false)
        #expect(plan.inspection.results.first { $0.itemId == "tires" }?.reading == 72)
        #expect(plan.recordCount == 1)
    }

    @Test func failingSafetyItemCreatesUnsafeDefectWithPendingPhotos() {
        let plan = InspectionPlanner.plan(
            template: template([lights, horn]),
            answers: ["lights": ItemAnswer(verdict: .fail, details: "Left headlight out", photoIds: ["p1"]),
                      "horn": ItemAnswer(verdict: .pass)],
            openDefectsByItem: [:], person: person, odometer: nil, now: now, makeId: sequentialIds())
        #expect(plan.newDefects.count == 1)
        let defect = plan.newDefects[0].defect
        #expect(defect.unsafe)
        #expect(defect.status == .open)
        #expect(defect.details == "Left headlight out")
        #expect(defect.inspectionId == plan.inspectionId)
        #expect(defect.photos["p1"]?.status == .pending)
        #expect(defect.history.first?.type == .reported)
        #expect(plan.unsafeItems == ["Lights"])
        #expect(plan.inspection.unsafe)
        #expect(plan.inspection.results.first { $0.itemId == "lights" }?.defectId == plan.newDefects[0].id)
    }

    @Test func passingAnOpenDefectReportsItFixedButNeverCloses() {
        let existing = ["horn": openDefect(item: horn)]
        let plan = InspectionPlanner.plan(
            template: template([horn]),
            answers: ["horn": ItemAnswer(verdict: .pass, note: "Works now")],
            openDefectsByItem: existing, person: person, odometer: nil, now: now, makeId: sequentialIds())
        #expect(plan.newDefects.isEmpty)
        #expect(plan.defectUpdates.count == 1)
        #expect(plan.defectUpdates[0].newStatus == .reportedFixed)
        #expect(plan.defectUpdates[0].event.type == .reportedFixed)
        #expect(plan.defectUpdates[0].event.note == "Works now")
    }

    @Test func failingAnOpenDefectConfirmsInsteadOfDuplicating() {
        let existing = ["lights": openDefect(item: lights, status: .reportedFixed, unsafe: true)]
        let plan = InspectionPlanner.plan(
            template: template([lights]),
            answers: ["lights": ItemAnswer(verdict: .fail)],
            openDefectsByItem: existing, person: person, odometer: nil, now: now, makeId: sequentialIds())
        #expect(plan.newDefects.isEmpty)
        #expect(plan.defectUpdates[0].event.type == .confirmed)
        // A "reported fixed" defect that's still broken goes back to open.
        #expect(plan.defectUpdates[0].newStatus == .open)
        #expect(plan.unsafeItems == ["Lights"])
    }

    @Test func inspectionsExpireAfterFiveYears() {
        let plan = InspectionPlanner.plan(
            template: template([horn]), answers: ["horn": ItemAnswer(verdict: .pass)],
            openDefectsByItem: [:], person: person, odometer: nil, now: now, makeId: sequentialIds())
        let years = Calendar.current.dateComponents([.year], from: now, to: plan.inspection.expireAt).year
        #expect(years == 5)
    }
}

struct VehicleConditionTests {
    @Test func reflectsWorstOpenDefect() {
        #expect(VehicleCondition(openDefects: []) == .ok)
        #expect(VehicleCondition(openDefects: [openDefect(item: horn)]) == .needsAttention)
        #expect(VehicleCondition(openDefects: [openDefect(item: horn), openDefect(item: lights, unsafe: true)]) == .outOfService)
        #expect(VehicleCondition(openDefects: [openDefect(item: lights, status: .closed, unsafe: true)]) == .ok)
    }
}

struct UsageReportTests {
    @Test func levelsFollowTheWorstAllowance() {
        #expect(UsageReport(usage: nil).level == .ok)
        #expect(UsageReport(usage: FleetUsage(photoBytes: 4_100_000_000, photoCount: 1, recordCount: 0)).level == .warning)
        #expect(UsageReport(usage: FleetUsage(photoBytes: 0, photoCount: 0, recordCount: 260_000)).level == .critical)
        // Negative counters (e.g. after a purge race) clamp to zero.
        #expect(UsageReport(usage: FleetUsage(photoBytes: -5, photoCount: -1, recordCount: -3)).photoBytes == 0)
    }
}

struct SpecDefaultsTests {
    @Test func startsWithFluidsTiresAndParts() {
        let sections = SpecDefaults.sections(makeId: sequentialIds())
        #expect(sections.map(\.title) == ["Fluids", "Tires & Wheels", "Parts & Capacities"])
        #expect(sections[1].rows.contains { $0.label == "Front pressure (cold, PSI)" })
        #expect(SpecDefaults.filled(sections).isEmpty)
    }

    @Test func quickViewHidesEmptyRows() {
        var sections = SpecDefaults.sections(makeId: sequentialIds())
        sections[1].rows[0].value = "LT235/65R16C"
        let filled = SpecDefaults.filled(sections)
        #expect(filled.count == 1)
        #expect(filled[0].rows.map(\.label) == ["Tire size"])
        #expect(SpecDefaults.emptyRowCount(sections) == SpecDefaults.emptyRowCount(SpecDefaults.sections()) - 1)
    }
}

struct ChecklistTests {
    @Test func appliesToAllVehiclesWhenUnassigned() {
        var checklist = ChecklistDefaults.morningChecklist(makeId: sequentialIds())
        #expect(checklist.applies(to: "van"))
        checklist.vehicleIds = ["truck"]
        #expect(!checklist.applies(to: "van"))
        #expect(checklist.applies(to: "truck"))
    }

    @Test func starterChecklistHasSafetyItemsAndAReading() {
        let checklist = ChecklistDefaults.morningChecklist()
        #expect(checklist.items.contains { $0.unsafeIfFailed })
        #expect(checklist.items.contains { $0.requiresReading && $0.readingLabel == "PSI" })
    }
}

struct ReminderTests {
    @Test func matchesByTypeAndCustomTitle() {
        let oil = Reminder(serviceType: .oilChange, title: "Synthetic oil", intervalDistance: 5000, intervalMonths: 6,
                           lastServiceDate: now, lastServiceOdometer: 0, notificationsEnabled: true)
        #expect(oil.matches(serviceType: .oilChange, title: ""))
        #expect(!oil.matches(serviceType: .brakes, title: ""))
        let other = Reminder(serviceType: .other, title: "DOT inspection", intervalDistance: nil, intervalMonths: 12,
                             lastServiceDate: now, lastServiceOdometer: 0, notificationsEnabled: true)
        #expect(other.matches(serviceType: .other, title: "dot inspection"))
        #expect(!other.matches(serviceType: .other, title: "Wash"))
    }
}
