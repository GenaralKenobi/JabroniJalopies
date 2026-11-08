import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Client-side recursive deletes (Firestore doesn't cascade to subcollections).
enum FleetDeleter {
    /// Deletes every document in a query, in batches. Returns the number deleted.
    @discardableResult
    static func deleteAll(_ query: Query) async throws -> Int {
        var deleted = 0
        while true {
            let snapshot = try await query.limit(to: 300).getDocuments()
            if snapshot.documents.isEmpty { return deleted }
            let batch = FS.db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            deleted += snapshot.documents.count
        }
    }

    /// Deletes a vehicle with all of its records and photos.
    static func deleteVehicle(fleetId: String, vehicleId: String) async throws {
        try await deletePhotos(fleetId: fleetId, vehicleId: vehicleId, defects: FS.defects(fleetId, vehicleId))
        for name in FS.vehicleSubcollections {
            try await deleteAll(FS.vehicle(fleetId, vehicleId).collection(name))
        }
        try await FS.vehicle(fleetId, vehicleId).delete()
    }

    /// Deletes all of a fleet's data except the fleet document and the caller's membership.
    static func deleteFleetData(fleetId: String) async throws {
        let vehicles = try await FS.vehicles(fleetId).getDocuments()
        for vehicle in vehicles.documents {
            try await deleteVehicle(fleetId: fleetId, vehicleId: vehicle.documentID)
        }
        try await deleteAll(FS.checklists(fleetId))
        try await deleteAll(FS.invites.whereField("fleetId", isEqualTo: fleetId))
        try await FS.fleet(fleetId).delete()
    }

    /// Deletes the uploaded photos for the defects in a query.
    static func deletePhotos(fleetId: String, vehicleId: String, defects: Query) async throws {
        let snapshot = try await defects.getDocuments()
        for document in snapshot.documents {
            guard let defect = try? document.data(as: Defect.self) else { continue }
            for photo in defect.photos.values {
                guard let path = photo.path else { continue }
                try? await Storage.storage().reference(withPath: path).delete()
            }
        }
    }
}
