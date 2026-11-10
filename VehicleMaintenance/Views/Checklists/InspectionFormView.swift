import PhotosUI
import SwiftUI

/// A driver completing a checklist. Works fully offline: everything is saved
/// to the phone on submit and uploads when there's signal.
struct InspectionFormView: View {
    let vehicle: Vehicle
    let checklist: ChecklistTemplate

    @Environment(FleetModel.self) private var fleet
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    @State private var answers: [String: ItemAnswer] = [:]
    @State private var photos: [String: Data] = [:]
    @State private var odometerText: String
    @State private var validationMessage: String?
    @State private var photoPromptItemId: String?
    @State private var cameraItemId: IdentifiedString?
    @State private var libraryItemId: String?
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var outcome: Outcome?
    @State private var confirmingCancel = false
    /// Repeating items that aren't due yet but the driver chose to do now.
    @State private var doingEarly: Set<String> = []
    /// Guards against a double tap saving the checklist twice.
    @State private var submitted = false

    struct IdentifiedString: Identifiable { let id: String }

    struct Outcome {
        var title: String
        var message: String
    }

    init(vehicle: Vehicle, checklist: ChecklistTemplate) {
        self.vehicle = vehicle
        self.checklist = checklist
        _odometerText = State(initialValue: String(vehicle.odometer))
    }

    /// The most recent open defect for each checklist item on this vehicle.
    private var openDefectsByItem: [String: Defect] {
        var map: [String: Defect] = [:]
        for defect in (fleet.openDefects[vehicle.id ?? ""] ?? []).sorted(by: { $0.reportedAt < $1.reportedAt }) {
            if let itemId = defect.itemId { map[itemId] = defect }
        }
        return map
    }

    private var lastDone: [String: Date] { fleet.checklistStates[vehicle.id ?? ""]?.lastDone ?? [:] }

    /// Items to answer now: every-time items, repeating items that are due (or have an open
    /// defect), and anything the driver chose to do early.
    private var activeItems: [ChecklistItem] {
        let defects = openDefectsByItem
        return checklist.items.filter { item in
            PeriodicSchedule.isDue(item.frequency, lastDone: lastDone[item.id])
                || defects[item.id] != nil
                || doingEarly.contains(item.id)
        }
    }

    private var notDueItems: [ChecklistItem] {
        let active = Set(activeItems.map(\.id))
        return checklist.items.filter { !active.contains($0.id) }
    }

    private var requiredItems: [ChecklistItem] { activeItems.filter { !InspectionPlanner.isOptional($0) } }
    private var answeredRequiredCount: Int { requiredItems.filter { answers[$0.id]?.verdict != nil }.count }
    /// Due repeating items left unanswered (not ones opened early, which aren't due anyway).
    private var skippedItems: [ChecklistItem] {
        InspectionPlanner.skippedItems(activeItems, answers: answers)
            .filter { PeriodicSchedule.isDue($0.frequency, lastDone: lastDone[$0.id]) }
    }

    /// What gets validated and saved: required items plus the repeating items that were answered.
    private var checklistToSubmit: ChecklistTemplate {
        var copy = checklist
        copy.items = InspectionPlanner.itemsToSubmit(activeItems, answers: answers)
        return copy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Vehicle", value: vehicle.displayName)
                    HStack {
                        Text("Odometer")
                        TextField("Reading", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(unit.abbreviation).foregroundStyle(Color.secondary)
                    }
                } footer: {
                    if !connectivity.isOnline {
                        Label("You're offline. Your checklist will be saved on this phone and sent when you have signal.",
                              systemImage: "wifi.slash")
                    }
                }

                ForEach(activeItems) { item in
                    Section {
                        ItemCard(item: item,
                                 lastDone: lastDone[item.id],
                                 existingDefect: openDefectsByItem[item.id],
                                 answer: binding(for: item.id),
                                 photos: $photos,
                                 photosEnabled: fleet.photosEnabled,
                                 onFail: { promptForPhoto(item) })
                    }
                }

                if !notDueItems.isEmpty {
                    Section {
                        ForEach(notDueItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    if let frequency = item.frequency,
                                       let next = PeriodicSchedule.nextDue(frequency, lastDone: lastDone[item.id]) {
                                        Text("\(frequency.label) · next due \(next.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(Color.secondary)
                                    }
                                }
                                Spacer()
                                Button("Do Now") { doingEarly.insert(item.id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } header: {
                        Text("Not Due Yet")
                    } footer: {
                        Text("These repeat weekly, monthly or on a schedule, and were done recently on this truck.")
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        Text("Submit Checklist (\(answeredRequiredCount)/\(requiredItems.count))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(submitted)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    let skipped = skippedItems.count
                    if skipped > 0 {
                        Text("\(skipped) repeating item\(skipped == 1 ? "" : "s") not done. \(skipped == 1 ? "It stays" : "They stay") due and will show on the next checklist for this truck until someone does \(skipped == 1 ? "it" : "them").")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle(checklist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if answers.isEmpty { dismiss() } else { confirmingCancel = true }
                    }
                }
            }
            .confirmationDialog("Discard this checklist?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .confirmationDialog("Add a photo of the problem?", isPresented: Binding(
                get: { photoPromptItemId != nil },
                set: { if !$0 { photoPromptItemId = nil } }
            ), titleVisibility: .visible) {
                if CameraPicker.isAvailable {
                    Button("Take Photo") {
                        cameraItemId = photoPromptItemId.map(IdentifiedString.init)
                        photoPromptItemId = nil
                    }
                }
                Button("Choose from Library") {
                    libraryItemId = photoPromptItemId
                    photoPromptItemId = nil
                }
                Button("Not Now", role: .cancel) { photoPromptItemId = nil }
            } message: {
                Text("Optional. The problem is reported right away; photos upload when there's signal.")
            }
            .fullScreenCover(item: $cameraItemId) { target in
                CameraPicker { image in addPhoto(image, to: target.id) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: Binding(
                get: { libraryItemId != nil },
                set: { if !$0 { libraryItemId = nil } }
            ), selection: $libraryItems, maxSelectionCount: 4, matching: .images)
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty, let itemId = libraryItemId ?? lastFailedItemId else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            addPhoto(image, to: itemId)
                        }
                    }
                    libraryItems = []
                    libraryItemId = nil
                }
            }
            .alert(outcome?.title ?? "", isPresented: Binding(
                get: { outcome != nil },
                set: { if !$0 { outcome = nil; dismiss() } }
            )) {
                // Closing the alert runs the binding above, which closes the form once.
                Button("OK") {}
            } message: {
                Text(outcome?.message ?? "")
            }
        }
        .interactiveDismissDisabled(!answers.isEmpty)
    }

    @State private var lastFailedItemId: String?

    private func binding(for itemId: String) -> Binding<ItemAnswer> {
        Binding(
            get: { answers[itemId] ?? ItemAnswer() },
            set: { answers[itemId] = $0 }
        )
    }

    private func promptForPhoto(_ item: ChecklistItem) {
        lastFailedItemId = item.id
        guard fleet.photosEnabled, (answers[item.id]?.photoIds.isEmpty ?? true) else { return }
        photoPromptItemId = item.id
    }

    private func addPhoto(_ image: UIImage, to itemId: String) {
        guard let data = ImageProcessing.defectPhotoJPEG(image) else { return }
        let photoId = UUID().uuidString
        photos[photoId] = data
        var answer = answers[itemId] ?? ItemAnswer()
        answer.photoIds.append(photoId)
        answers[itemId] = answer
    }

    private func submit() {
        guard !submitted else { return }
        let existing = openDefectsByItem
        let checklist = checklistToSubmit
        let skipped = skippedItems
        if let error = InspectionPlanner.validate(template: checklist, answers: answers, openDefectsByItem: existing) {
            validationMessage = error.localizedDescription
            return
        }
        validationMessage = nil
        let plan = InspectionPlanner.plan(template: checklist, answers: answers, openDefectsByItem: existing,
                                          person: fleet.person, odometer: NumberParsing.int(odometerText))

        // Only send photos attached to defects (a passing item's photos are dropped).
        var usedPhotoIds = Set(plan.newDefects.flatMap { $0.defect.photos.keys })
        plan.defectUpdates.forEach { usedPhotoIds.formUnion($0.photoIds) }
        let usedPhotos = photos.filter { usedPhotoIds.contains($0.key) }

        do {
            try fleet.submit(plan, vehicle: vehicle, odometer: NumberParsing.int(odometerText), photos: usedPhotos,
                             repeatingItemIds: checklist.items.filter { $0.frequency != nil }.map(\.id))
            submitted = true
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        let offlineNote = connectivity.isOnline ? "" : "\n\nSaved on this phone. It will be sent automatically when you have signal."
        let photoNote = (usedPhotos.isEmpty ? "" : "\n\nPhotos will upload in the background.")
            + (skipped.isEmpty ? "" : "\n\nNot done yet (still due): \(skipped.map(\.title).joined(separator: ", ")).")
        if !plan.unsafeItems.isEmpty {
            outcome = Outcome(
                title: "⚠️ Do Not Drive This Vehicle",
                message: "Safety items failed: \(plan.unsafeItems.joined(separator: ", ")).\n\nThe vehicle is now marked UNSAFE TO DRIVE until a manager clears it.\(offlineNote)\(photoNote)")
        } else if plan.inspection.failedCount > 0 {
            let count = plan.inspection.failedCount
            outcome = Outcome(
                title: "Checklist Saved",
                message: "\(count) problem\(count == 1 ? "" : "s") reported to your manager.\(offlineNote)\(photoNote)")
        } else {
            outcome = Outcome(title: "All Good", message: "Checklist saved.\(offlineNote)\(photoNote)")
        }
    }
}

/// One checklist item: pass/fail (or still-a-problem/looks-fixed for an open
/// defect), an optional number reading, a description and photos.
private struct ItemCard: View {
    let item: ChecklistItem
    let lastDone: Date?
    let existingDefect: Defect?
    @Binding var answer: ItemAnswer
    @Binding var photos: [String: Data]
    let photosEnabled: Bool
    let onFail: () -> Void

    private func scheduleText(_ frequency: ItemFrequency) -> String {
        guard let lastDone else { return "Not done on this truck yet" }
        let done = "Last done on this truck \(lastDone.formatted(date: .abbreviated, time: .omitted))"
        if let due = PeriodicSchedule.nextDue(frequency, lastDone: lastDone), due <= .now {
            return "\(done) · due since \(due.formatted(date: .abbreviated, time: .omitted))"
        }
        return done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(.headline)
                Spacer()
                if let frequency = item.frequency {
                    Text(frequency.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Color.brand)
                        .background(Color.brand.opacity(0.12), in: Capsule())
                }
                if item.unsafeIfFailed {
                    Text("Safety")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
            }

            if let frequency = item.frequency {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scheduleText(frequency))
                        .foregroundStyle(Color.secondary)
                    Text(PeriodicSchedule.isDue(frequency, lastDone: lastDone)
                         ? "Optional. If you skip it, it stays due until someone does it."
                         : "Optional.")
                        .foregroundStyle(Color.secondary)
                }
                .font(.caption)
            }

            if let existingDefect {
                existingDefectBanner(existingDefect)
            }

            HStack(spacing: 10) {
                verdictButton(existingDefect == nil ? "Pass" : "Looks Fixed", symbol: "checkmark", verdict: .pass, color: .green)
                verdictButton(existingDefect == nil ? "Fail" : "Still a Problem", symbol: "xmark", verdict: .fail, color: .red)
            }

            if item.requiresReading {
                HStack {
                    Text("Reading")
                    TextField("Enter number", text: $answer.reading)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    if !item.readingLabel.isEmpty {
                        Text(item.readingLabel).foregroundStyle(Color.secondary)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }

            failureDetails
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var failureDetails: some View {
        if existingDefect == nil, answer.verdict == .fail {
            if item.unsafeIfFailed {
                Label("This will mark the vehicle UNSAFE TO DRIVE.", systemImage: "exclamationmark.octagon.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
            }
            TextField("Describe the problem", text: $answer.details, axis: .vertical)
                .lineLimit(2...5)
            if photosEnabled {
                PhotoAttachmentControls(photoIds: $answer.photoIds, photos: $photos)
            }
        } else if existingDefect != nil, answer.verdict == .pass {
            TextField("Why does it look fixed? (required)", text: $answer.note, axis: .vertical)
                .lineLimit(2...4)
            Text("A manager will confirm before the defect is closed.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        } else if existingDefect != nil, answer.verdict == .fail {
            TextField("Add a note (optional)", text: $answer.note, axis: .vertical)
                .lineLimit(1...4)
            if photosEnabled {
                PhotoAttachmentControls(photoIds: $answer.photoIds, photos: $photos)
            }
        }
    }

    private func existingDefectBanner(_ defect: Defect) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(defect.status == .reportedFixed ? "Defect reported fixed — awaiting manager" : "Open defect",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            if !defect.details.isEmpty {
                Text(defect.details).font(.subheadline)
            }
            Text("\(defect.reportedByName), \(defect.reportedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .foregroundStyle(defect.unsafe ? Color.red : Color.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((defect.unsafe ? Color.red : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func verdictButton(_ title: String, symbol: String, verdict: ItemVerdict, color: Color) -> some View {
        let selected = answer.verdict == verdict
        return Button {
            answer.verdict = verdict
            if verdict == .fail, existingDefect == nil {
                onFail()
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? Color.white : color)
                .background(selected ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
