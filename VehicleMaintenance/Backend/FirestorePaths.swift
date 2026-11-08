import FirebaseFirestore
import Foundation

/// Every Firestore location the app uses, in one place.
enum FS {
    static var db: Firestore { Firestore.firestore() }

    static func user(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }
    static func memberships(_ uid: String) -> CollectionReference { user(uid).collection("memberships") }
    static var invites: CollectionReference { db.collection("invites") }

    static var fleets: CollectionReference { db.collection("fleets") }
    static func fleet(_ fleetId: String) -> DocumentReference { fleets.document(fleetId) }
    static func members(_ fleetId: String) -> CollectionReference { fleet(fleetId).collection("members") }
    static func checklists(_ fleetId: String) -> CollectionReference { fleet(fleetId).collection("checklists") }
    static func vehicles(_ fleetId: String) -> CollectionReference { fleet(fleetId).collection("vehicles") }
    static func vehicle(_ fleetId: String, _ vehicleId: String) -> DocumentReference {
        vehicles(fleetId).document(vehicleId)
    }

    static func reminders(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("reminders") }
    static func services(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("services") }
    static func costs(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("costs") }
    static func inspections(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("inspections") }
    static func defects(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("defects") }

    /// Cloud Storage path for a defect photo.
    static func photoPath(fleetId: String, vehicleId: String, defectId: String, photoId: String) -> String {
        "fleets/\(fleetId)/vehicles/\(vehicleId)/defects/\(defectId)/\(photoId).jpg"
    }

    static let vehicleSubcollections = ["reminders", "services", "costs", "inspections", "defects"]

    /// Encodes a value for use inside `updateData` (e.g. an array of structs or a map).
    static func encode<T: Encodable>(_ value: T) throws -> Any {
        struct Box<V: Encodable>: Encodable { let value: V }
        return try Firestore.Encoder().encode(Box(value: value))["value"] as Any
    }
}
