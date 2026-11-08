import Foundation

enum ItemVerdict: Equatable {
    case pass
    case fail
}

/// What a driver entered for one checklist item.
struct ItemAnswer: Equatable {
    var verdict: ItemVerdict?
    /// Raw text of the number reading, if the item asks for one.
    var reading: String = ""
    /// Description of the problem (new defects).
    var details: String = ""
    /// Note when confirming or reporting an existing defect fixed.
    var note: String = ""
    /// Photos taken for this item, by photo id.
    var photoIds: [String] = []
}

/// Turns a completed checklist into the records to save: the inspection itself,
/// new defects, and updates to defects that were already open.
struct InspectionPlan {
    struct NewDefect {
        var id: String
        var defect: Defect
    }

    struct DefectUpdate {
        var defectId: String
        var event: DefectEvent
        /// Set when a driver reports an existing defect as fixed.
        var newStatus: DefectStatus?
        /// Photos added to an existing defect.
        var photoIds: [String]
    }

    var inspectionId: String
    var inspection: Inspection
    var newDefects: [NewDefect]
    var defectUpdates: [DefectUpdate]
    /// Titles of failed items that make the vehicle unsafe to drive.
    var unsafeItems: [String]

    var recordCount: Int { 1 + newDefects.count }
}

enum InspectionValidationError: Equatable, LocalizedError {
    case unanswered([String])
    case missingReading([String])
    case missingFixNote([String])

    var errorDescription: String? {
        switch self {
        case .unanswered(let items): "Mark pass or fail for: \(items.joined(separator: ", "))."
        case .missingReading(let items): "Enter a number for: \(items.joined(separator: ", "))."
        case .missingFixNote(let items): "Add a note explaining why these look fixed: \(items.joined(separator: ", "))."
        }
    }
}

enum InspectionPlanner {
    struct Person {
        var uid: String
        var name: String
    }

    static func validate(
        template: ChecklistTemplate,
        answers: [String: ItemAnswer],
        openDefectsByItem: [String: Defect]
    ) -> InspectionValidationError? {
        let unanswered = template.items.filter { answers[$0.id]?.verdict == nil }.map(\.title)
        if !unanswered.isEmpty { return .unanswered(unanswered) }

        let missingReading = template.items.filter {
            $0.requiresReading && NumberParsing.decimal(answers[$0.id]?.reading ?? "") == nil
        }.map(\.title)
        if !missingReading.isEmpty { return .missingReading(missingReading) }

        let missingNote = template.items.filter { item in
            openDefectsByItem[item.id] != nil
                && answers[item.id]?.verdict == .pass
                && (answers[item.id]?.note.trimmed.isEmpty ?? true)
        }.map(\.title)
        if !missingNote.isEmpty { return .missingFixNote(missingNote) }

        return nil
    }

    static func plan(
        template: ChecklistTemplate,
        answers: [String: ItemAnswer],
        openDefectsByItem: [String: Defect],
        person: Person,
        odometer: Int?,
        now: Date = .now,
        makeId: () -> String = { UUID().uuidString }
    ) -> InspectionPlan {
        var results: [InspectionResult] = []
        var newDefects: [InspectionPlan.NewDefect] = []
        var updates: [InspectionPlan.DefectUpdate] = []
        var unsafeItems: [String] = []
        let inspectionId = makeId()

        for item in template.items {
            let answer = answers[item.id] ?? ItemAnswer()
            let passed = answer.verdict == .pass
            var result = InspectionResult(
                itemId: item.id, title: item.title, passed: passed,
                reading: item.requiresReading ? NumberParsing.decimal(answer.reading) : nil,
                readingLabel: item.requiresReading ? item.readingLabel : nil,
                note: nil, defectId: nil)

            if let existing = openDefectsByItem[item.id], let existingId = existing.id {
                // The item already has an open defect: confirm it or report it fixed.
                result.defectId = existingId
                let note = answer.note.trimmed.isEmpty ? nil : answer.note.trimmed
                result.note = note
                if passed {
                    updates.append(.init(
                        defectId: existingId,
                        event: DefectEvent(type: .reportedFixed, by: person.uid, byName: person.name, at: now, note: note),
                        newStatus: .reportedFixed, photoIds: answer.photoIds))
                } else {
                    updates.append(.init(
                        defectId: existingId,
                        event: DefectEvent(type: .confirmed, by: person.uid, byName: person.name, at: now, note: note),
                        newStatus: existing.status == .reportedFixed ? .open : nil,
                        photoIds: answer.photoIds))
                    if existing.unsafe || item.unsafeIfFailed { unsafeItems.append(item.title) }
                }
            } else if !passed {
                let defectId = makeId()
                let details = answer.details.trimmed
                result.defectId = defectId
                result.note = details.isEmpty ? nil : details
                var photos: [String: DefectPhoto] = [:]
                for photoId in answer.photoIds {
                    photos[photoId] = DefectPhoto(status: .pending, path: nil, addedBy: person.uid,
                                                  addedByName: person.name, addedAt: now, byteCount: nil)
                }
                let defect = Defect(
                    itemId: item.id, title: item.title, details: details, unsafe: item.unsafeIfFailed,
                    status: .open, resolution: nil, reportedBy: person.uid, reportedByName: person.name,
                    reportedAt: now, inspectionId: inspectionId, closedAt: nil, closedBy: nil, closedByName: nil,
                    history: [DefectEvent(type: .reported, by: person.uid, byName: person.name, at: now,
                                          note: details.isEmpty ? nil : details)],
                    photos: photos, expireAt: nil, updatedAt: now)
                newDefects.append(.init(id: defectId, defect: defect))
                if item.unsafeIfFailed { unsafeItems.append(item.title) }
            }
            results.append(result)
        }

        let inspection = Inspection(
            checklistId: template.id ?? "", checklistName: template.name,
            performedBy: person.uid, performedByName: person.name, completedAt: now,
            odometer: odometer, results: results,
            failedCount: results.filter { !$0.passed }.count,
            unsafe: !unsafeItems.isEmpty, expireAt: Retention.expiry(from: now))

        return InspectionPlan(inspectionId: inspectionId, inspection: inspection, newDefects: newDefects,
                              defectUpdates: updates, unsafeItems: unsafeItems)
    }
}
