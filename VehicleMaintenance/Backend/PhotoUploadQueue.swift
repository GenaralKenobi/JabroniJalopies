import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

/// Defect photos are saved on the phone first and uploaded separately from the
/// defect's text, so a problem is flagged right away even on a weak signal.
/// The queue survives the app closing and the phone restarting, and retries
/// when the connection returns, when the app opens, and in background refreshes.
@MainActor
@Observable
final class PhotoUploadQueue {
    static let shared = PhotoUploadQueue()
    static let backgroundTaskId = "com.generalkenobi.jabronijalopies.photo-upload"
    /// Give up on a photo after this many attempts that failed for reasons retrying
    /// can't fix (e.g. no longer a member). Network failures are never counted.
    static let maxAttempts = 10

    struct Job: Codable, Identifiable, Equatable {
        var id: String  // photo id
        var fleetId: String
        var vehicleId: String
        var defectId: String
        /// Set for equipment defects (chainsaws, ropes); otherwise the defect is on `vehicleId`.
        var equipmentId: String?
        var createdAt: Date
        var attempts: Int

        var owner: DefectOwner {
            equipmentId.map(DefectOwner.equipment) ?? .vehicle(vehicleId)
        }
    }

    private(set) var jobs: [Job] = []
    private(set) var isUploading = false

    private let directory: URL
    private var manifestURL: URL { directory.appendingPathComponent("jobs.json") }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("PendingPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode([Job].self, from: data) {
            jobs = saved
        }
    }

    var pendingCount: Int { jobs.count }

    func isPending(photoId: String) -> Bool { jobs.contains { $0.id == photoId } }

    /// The local copy of a photo that hasn't uploaded yet (shown on this phone only).
    func localImageData(photoId: String) -> Data? {
        try? Data(contentsOf: fileURL(photoId))
    }

    func enqueue(data: Data, photoId: String, fleetId: String, owner: DefectOwner, defectId: String) {
        do {
            try data.write(to: fileURL(photoId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            ErrorCenter.shared.report(error, "Saving photo")
            return
        }
        var vehicleId = ""
        var equipmentId: String?
        switch owner {
        case .vehicle(let id): vehicleId = id
        case .equipment(let id): equipmentId = id
        }
        jobs.append(Job(id: photoId, fleetId: fleetId, vehicleId: vehicleId, defectId: defectId,
                        equipmentId: equipmentId, createdAt: .now, attempts: 0))
        saveManifest()
        process()
    }

    /// Uploads whatever is waiting. Safe to call often.
    func process() {
        guard !isUploading, !jobs.isEmpty, FirebaseSetup.isConfigured, Auth.auth().currentUser != nil else { return }
        isUploading = true
        Task {
            await uploadAll()
            isUploading = false
        }
    }

    /// Called from the background refresh task.
    func processInBackground() async {
        guard !isUploading, !jobs.isEmpty, FirebaseSetup.isConfigured, Auth.auth().currentUser != nil else { return }
        isUploading = true
        await uploadAll()
        isUploading = false
        scheduleBackgroundRefresh()
    }

    /// Asks iOS for background time to keep trying while photos are waiting.
    func scheduleBackgroundRefresh() {
        guard !jobs.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func uploadAll() async {
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Photo upload")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        for job in jobs {
            do {
                try await upload(job)
                finish(job)
            } catch {
                // Weak or no signal never counts against a photo; only errors that
                // retrying can't fix (no permission, storage not set up) do.
                guard Self.isPermanent(error) else {
                    if !ConnectivityMonitor.shared.isOnline { break }
                    continue
                }
                guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { continue }
                jobs[index].attempts += 1
                if jobs[index].attempts >= Self.maxAttempts {
                    finish(job)
                }
                saveManifest()
            }
        }
    }

    private static func isPermanent(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == StorageErrorDomain else { return false }
        let permanent: [StorageErrorCode] = [.unauthorized, .unauthenticated, .bucketNotFound, .projectNotFound, .invalidArgument]
        return permanent.map(\.rawValue).contains(nsError.code)
    }

    private func upload(_ job: Job) async throws {
        let url = fileURL(job.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let path = job.owner.photoPath(fleetId: job.fleetId, defectId: job.defectId, photoId: job.id)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await Storage.storage().reference(withPath: path).putFileAsync(from: url, metadata: metadata)

        // Attach to the defect. If the defect was deleted meanwhile (e.g. old records
        // cleared by a manager), there's nothing to attach to and nothing to report.
        job.owner.defects(fleetId: job.fleetId).document(job.defectId).updateData([
            "photos.\(job.id).status": DefectPhotoStatus.uploaded.rawValue,
            "photos.\(job.id).path": path,
            "photos.\(job.id).byteCount": size,
            "updatedAt": Date.now,
        ]) { error in
            MainActor.assumeIsolated {
                guard let error, (error as NSError).code != FirestoreErrorCode.notFound.rawValue else { return }
                ErrorCenter.shared.report(error, "Attaching photo")
            }
        }
        // Count it toward the fleet's storage use (an estimate; failures don't matter).
        FS.fleet(job.fleetId).updateData([
            "usage.photoBytes": FieldValue.increment(Int64(size)),
            "usage.photoCount": FieldValue.increment(Int64(1)),
        ]) { _ in }
    }

    /// Discards every waiting photo (used when signing out, so the next person to
    /// sign in on this phone can't see or upload them).
    func removeAll() {
        for job in jobs {
            try? FileManager.default.removeItem(at: fileURL(job.id))
        }
        jobs.removeAll()
        saveManifest()
    }

    private func finish(_ job: Job) {
        try? FileManager.default.removeItem(at: fileURL(job.id))
        jobs.removeAll { $0.id == job.id }
        saveManifest()
    }

    private func fileURL(_ photoId: String) -> URL {
        directory.appendingPathComponent("\(photoId).jpg")
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
