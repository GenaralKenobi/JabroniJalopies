import Foundation

/// A checklist someone started but hasn't submitted, kept on this phone so it can be
/// finished later (for example a long service done over a day or two).
struct ChecklistDraft: Codable {
    var answers: [String: ItemAnswer]
    var odometerText: String
    var doingEarly: Set<String>
    var checkedIds: Set<String>
    var photoIds: [String]
    var savedAt: Date
}

/// Saves drafts to disk: one per fleet, vehicle and checklist. Photos are separate files.
/// Drafts are erased when the checklist is submitted or discarded, and on sign-out.
@MainActor
@Observable
final class ChecklistDraftStore {
    static let shared = ChecklistDraftStore()

    /// Bumped on every save or delete, so screens showing "in progress" refresh.
    private(set) var version = 0

    @ObservationIgnored private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("ChecklistDrafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func key(fleetId: String, vehicleId: String, checklistId: String) -> String {
        "\(fleetId)_\(vehicleId)_\(checklistId)"
    }

    func load(_ key: String) -> (draft: ChecklistDraft, photos: [String: Data])? {
        _ = version
        guard let data = try? Data(contentsOf: draftURL(key)),
              let draft = try? JSONDecoder().decode(ChecklistDraft.self, from: data) else { return nil }
        var photos: [String: Data] = [:]
        for id in draft.photoIds {
            if let photo = try? Data(contentsOf: photoURL(key, id)) { photos[id] = photo }
        }
        return (draft, photos)
    }

    /// Just the saved progress, for "Continue (5 of 12 checked)" on the truck page.
    func summary(_ key: String) -> ChecklistDraft? {
        _ = version
        guard let data = try? Data(contentsOf: draftURL(key)) else { return nil }
        return try? JSONDecoder().decode(ChecklistDraft.self, from: data)
    }

    func save(_ draft: ChecklistDraft, photos: [String: Data], key: String) {
        let protection: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        for (id, data) in photos where !FileManager.default.fileExists(atPath: photoURL(key, id).path) {
            try? data.write(to: photoURL(key, id), options: protection)
        }
        // Remove photos no longer attached.
        let keep = Set(draft.photoIds)
        for url in photoFiles(key) where !keep.contains(photoId(from: url, key: key)) {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: draftURL(key), options: protection)
        version += 1
    }

    func delete(_ key: String) {
        try? FileManager.default.removeItem(at: draftURL(key))
        for url in photoFiles(key) { try? FileManager.default.removeItem(at: url) }
        version += 1
    }

    /// Signing out: nothing from this person stays on the phone.
    func deleteAll() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls { try? FileManager.default.removeItem(at: url) }
        version += 1
    }

    private func draftURL(_ key: String) -> URL { directory.appendingPathComponent("\(key).json") }
    private func photoURL(_ key: String, _ id: String) -> URL { directory.appendingPathComponent("\(key)__\(id).jpg") }

    private func photoFiles(_ key: String) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("\(key)__") }
    }

    private func photoId(from url: URL, key: String) -> String {
        String(url.deletingPathExtension().lastPathComponent.dropFirst("\(key)__".count))
    }
}
