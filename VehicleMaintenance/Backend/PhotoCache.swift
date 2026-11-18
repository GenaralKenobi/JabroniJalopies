import FirebaseStorage
import Foundation

/// Copies of uploaded defect photos kept on the phone, so they can be seen without signal.
///
/// - Photos this phone uploads are kept (no download needed).
/// - Photos viewed here are kept after the first download.
/// - Photos of open defects are "pinned": they're removed last when space runs short,
///   and managers' phones download them ahead of time (see `prefetch`).
/// - Everything else is removed oldest-viewed first once the total passes `limitBytes`.
@MainActor
@Observable
final class PhotoCache {
    static let shared = PhotoCache()
    static let limitBytes = 100 * 1024 * 1024
    /// Largest photo we'll download (the app uploads ~200–400 KB; this only guards against oddities).
    private static let maxDownloadBytes: Int64 = 15 * 1024 * 1024

    /// Space used by saved photos, for Settings.
    private(set) var totalBytes = 0

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var pinned: Set<String> = []
    @ObservationIgnored private var inFlight: [String: Task<Data?, Never>] = [:]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("SavedPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Re-downloadable, so keep it out of iCloud backups.
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        totalBytes = files().reduce(0) { $0 + $1.size }
    }

    // MARK: Reading

    /// The saved copy, if there is one (also marks it as recently used).
    func data(for path: String) -> Data? {
        let url = fileURL(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        return data
    }

    /// The saved copy, or a download (which is then saved). Nil when offline and not saved.
    func load(_ path: String) async -> Data? {
        if let data = data(for: path) { return data }
        if let task = inFlight[path] { return await task.value }
        let task = Task<Data?, Never> {
            try? await Storage.storage().reference(withPath: path).data(maxSize: Self.maxDownloadBytes)
        }
        inFlight[path] = task
        let data = await task.value
        inFlight[path] = nil
        if let data { store(data, for: path) }
        return data
    }

    // MARK: Writing

    func store(_ data: Data, for path: String) {
        let url = fileURL(path)
        let existing = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            totalBytes += data.count - existing
            trim()
        } catch {
            // Out of space or similar: the photo still shows from the internet.
        }
    }

    /// Removes every saved photo (Settings, signing out, deleting the account).
    func clear() {
        prefetchTask?.cancel()
        for file in files() { try? FileManager.default.removeItem(at: file.url) }
        totalBytes = 0
    }

    // MARK: Open defects

    /// Tells the cache which photos belong to open defects. With `download`, fetches any
    /// that aren't saved yet (managers' phones), one at a time, while online.
    func keepOpenDefectPhotos(_ paths: Set<String>, download: Bool) {
        pinned = paths
        guard download else { return }
        let missing = paths.filter { !FileManager.default.fileExists(atPath: fileURL($0).path) }.sorted()
        guard !missing.isEmpty else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            // Let the screen settle first; new defects often arrive in bursts.
            try? await Task.sleep(for: .seconds(3))
            for path in missing {
                guard !Task.isCancelled, let self, ConnectivityMonitor.shared.isOnline else { return }
                _ = await self.load(path)
            }
        }
    }

    // MARK: Housekeeping

    private func trim() {
        guard totalBytes > Self.limitBytes else { return }
        // Oldest-used first; open-defect photos only if there's still too much.
        let sorted = files().sorted { lhs, rhs in
            let lhsPinned = pinned.contains(lhs.path), rhsPinned = pinned.contains(rhs.path)
            if lhsPinned != rhsPinned { return !lhsPinned }
            return lhs.used < rhs.used
        }
        var total = sorted.reduce(0) { $0 + $1.size }
        for file in sorted where total > Self.limitBytes * 9 / 10 {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
        totalBytes = max(0, total)
    }

    private struct SavedFile { let url: URL; let path: String; let size: Int; let used: Date }

    private func files() -> [SavedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return SavedFile(url: url, path: Self.path(fromFileName: url.lastPathComponent),
                             size: values?.fileSize ?? 0, used: values?.contentModificationDate ?? .distantPast)
        }
    }

    /// Storage paths ("fleets/f/vehicles/v/defects/d/p.jpg") become flat file names and back.
    private func fileURL(_ path: String) -> URL {
        directory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "|"))
    }

    private static func path(fromFileName name: String) -> String {
        name.replacingOccurrences(of: "|", with: "/")
    }
}
