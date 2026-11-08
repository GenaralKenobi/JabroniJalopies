import SwiftUI

struct DefectDetailView: View {
    let owner: DefectOwner
    let defectId: String

    @Environment(FleetModel.self) private var fleet
    @State private var document: LiveDocument<Defect>?
    @State private var action: DefectEventType?
    @State private var note = ""
    @State private var newPhotoIds: [String] = []
    @State private var newPhotos: [String: Data] = [:]
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let defect = document?.value {
                content(defect)
            } else if document?.exists == false {
                ContentUnavailableView("Defect Not Found", systemImage: "questionmark.circle",
                                       description: Text("It may have been deleted."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Defect")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if document == nil {
                document = LiveDocument(owner.defects(fleetId: fleet.fleetId).document(defectId))
            }
        }
    }

    private func content(_ defect: Defect) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(defect.title).font(.title3.bold())
                        Spacer()
                        DefectStatusBadge(defect: defect)
                    }
                    Text(fleet.context(for: owner)).foregroundStyle(Color.secondary)
                    if defect.unsafe && defect.isOpen {
                        Label(isEquipment ? "Do not use" : "Unsafe to drive", systemImage: "exclamationmark.octagon.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    if !defect.details.isEmpty {
                        Text(defect.details)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent("Reported by", value: defect.reportedByName)
                LabeledContent("Reported", value: defect.reportedAt.formatted(date: .abbreviated, time: .shortened))
                if let received = defect.receivedAt, received.timeIntervalSince(defect.reportedAt) > 10 * 60 {
                    LabeledContent("Reached server", value: received.formatted(date: .abbreviated, time: .shortened))
                    Text("Reported offline and uploaded later.")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
                if document?.hasPendingWrites == true {
                    Label("Changes waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.blue)
                }
            }

            photosSection(defect)
            actionsSection(defect)

            Section("History") {
                ForEach(Array(defect.history.enumerated().reversed()), id: \.offset) { _, event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.type.symbolName)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type.label).font(.subheadline.weight(.semibold))
                            Text("\(event.byName) · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(Color.secondary)
                            if let note = event.note {
                                Text(note).font(.subheadline)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { action.map { ActionBox(type: $0) } },
            set: { action = $0?.type }
        )) { box in
            noteSheet(for: box.type, defect: defect)
        }
    }

    private var isEquipment: Bool {
        if case .equipment = owner { return true }
        return false
    }

    private struct ActionBox: Identifiable {
        let type: DefectEventType
        var id: String { type.rawValue }
    }

    @ViewBuilder
    private func photosSection(_ defect: Defect) -> some View {
        let photos = defect.sortedPhotos
        if !photos.isEmpty || fleet.photosEnabled {
            Section {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos, id: \.id) { entry in
                                DefectPhotoView(photoId: entry.id, photo: entry.photo)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if fleet.photosEnabled {
                    PhotoAttachmentControls(photoIds: $newPhotoIds, photos: $newPhotos)
                    if !newPhotoIds.isEmpty {
                        Button("Add \(newPhotoIds.count) Photo\(newPhotoIds.count == 1 ? "" : "s")") {
                            do {
                                try fleet.addPhotos(newPhotos, to: defect, owner: owner)
                                newPhotoIds = []
                                newPhotos = [:]
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                if defect.stalePhotoCount() > 0 {
                    Text("Some photos were taken over a day ago and never uploaded. Ask the person who took them to open the app with a connection.")
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ defect: Defect) -> some View {
        Section {
            if defect.isOpen {
                Button { action = .confirmed } label: {
                    Label("Still a Problem", systemImage: "exclamationmark.2")
                }
                if defect.status == .open {
                    Button { action = .reportedFixed } label: {
                        Label("Looks Fixed", systemImage: "hand.thumbsup")
                    }
                }
                if fleet.isManager {
                    Button { action = .repaired } label: {
                        Label("Mark Repaired", systemImage: "checkmark.seal.fill")
                    }
                    .tint(.green)
                    Button { action = .notDefect } label: {
                        Label("Not a Defect", systemImage: "xmark.seal")
                    }
                    if isEquipment {
                        Button(role: defect.unsafe ? nil : .destructive) {
                            fleet.setUnsafe(!defect.unsafe, on: defect, owner: owner)
                        } label: {
                            Label(defect.unsafe ? "Clear \"Do Not Use\"" : "Mark \"Do Not Use\"",
                                  systemImage: "exclamationmark.octagon")
                        }
                    }
                }
            } else if fleet.isManager {
                Button { action = .reopened } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        } footer: {
            if defect.isOpen && !fleet.isManager {
                Text("Only a manager can close a defect.")
            }
        }
    }

    private func noteSheet(for type: DefectEventType, defect: Defect) -> some View {
        let noteRequired = type == .reportedFixed || type == .notDefect
        return NavigationStack {
            Form {
                Section {
                    TextField(noteRequired ? "Note (required)" : "Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    switch type {
                    case .reportedFixed: Text("A manager will review and close it.")
                    case .repaired: Text("Closes the defect. Records are kept for 5 years.")
                    case .notDefect: Text("Closes the defect without a repair.")
                    default: EmptyView()
                    }
                }
            }
            .navigationTitle(type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { action = nil; note = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { perform(type, on: defect) }
                        .disabled(noteRequired && note.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func perform(_ type: DefectEventType, on defect: Defect) {
        do {
            switch type {
            case .repaired: try fleet.close(defect, owner: owner, resolution: .repaired, note: note)
            case .notDefect: try fleet.close(defect, owner: owner, resolution: .notDefect, note: note)
            case .reopened: try fleet.reopen(defect, owner: owner, note: note)
            default: try fleet.addEvent(type, note: note, to: defect, owner: owner)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        action = nil
        note = ""
    }
}

/// Report a problem on a truck (outside a checklist) or on a chainsaw or rope.
struct ReportDefectView: View {
    let owner: DefectOwner
    /// Whether this person may mark it unsafe / do not use.
    var allowUnsafe = true
    var unsafeLabel = "Unsafe to drive"

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var unsafe = false
    @State private var photoIds: [String] = []
    @State private var photos: [String: Data] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("For", value: fleet.context(for: owner))
                    TextField("What's wrong? (e.g. Chain brake sticks)", text: $title)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                if allowUnsafe {
                    Section {
                        Toggle(isOn: $unsafe) {
                            Label(unsafeLabel, systemImage: "exclamationmark.octagon")
                                .foregroundStyle(unsafe ? Color.red : Color.primary)
                        }
                    } footer: {
                        if unsafe {
                            Text("Everyone will see a red \"\(unsafeLabel)\" warning until a manager clears it.")
                                .foregroundStyle(.red)
                        }
                    }
                }
                if fleet.photosEnabled {
                    Section {
                        PhotoAttachmentControls(photoIds: $photoIds, photos: $photos)
                    } header: {
                        Text("Photos (optional)")
                    } footer: {
                        Text("The problem is reported right away. Photos upload when there's signal.")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") {
                        do {
                            try fleet.reportDefect(owner: owner, title: title, details: details,
                                                   unsafe: allowUnsafe && unsafe,
                                                   photos: photos.filter { photoIds.contains($0.key) })
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
        }
    }
}
