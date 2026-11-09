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
    static func contacts(_ fleetId: String) -> CollectionReference { fleet(fleetId).collection("contacts") }
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

    static func equipmentCollection(_ f: String) -> CollectionReference { fleet(f).collection("equipment") }
    static func equipment(_ f: String, _ e: String) -> DocumentReference { equipmentCollection(f).document(e) }
    static func equipmentDefects(_ f: String, _ e: String) -> CollectionReference { equipment(f, e).collection("defects") }
    static func lengthChanges(_ f: String, _ e: String) -> CollectionReference { equipment(f, e).collection("lengthChanges") }
    static func chainInventory(_ f: String, _ v: String) -> DocumentReference {
        vehicle(f, v).collection("chains").document("inventory")
    }
    static func chainLogs(_ f: String, _ v: String) -> CollectionReference { vehicle(f, v).collection("chainLogs") }
    static func checklistState(_ f: String, _ v: String) -> DocumentReference {
        vehicle(f, v).collection("checklistState").document("periodic")
    }

    static let vehicleSubcollections = ["reminders", "services", "costs", "inspections", "defects", "chains", "chainLogs", "checklistState"]
    static let equipmentSubcollections = ["defects", "lengthChanges"]

    /// Encodes a value for use inside `updateData` (e.g. an array of structs or a map).
    static func encode<T: Encodable>(_ value: T) throws -> Any {
        try Firestore.Encoder().encode(EncodingBox(value: value))["value"] as Any
    }
}

/// Wraps a value so Firestore's encoder (which needs a keyed container) can encode it.
private struct EncodingBox<V: Encodable>: Encodable {
    let value: V
}
