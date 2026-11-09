import FirebaseFirestore
import Foundation

enum FleetRole: String, Codable, CaseIterable, Identifiable {
    case manager
    case driver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manager: "Manager"
        case .driver: "Driver"
        }
    }
}

/// fleets/{fleetId}
struct Fleet: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String
    var createdBy: String
    @ServerTimestamp var createdAt: Date?
    /// Defect photos need Cloud Storage, which requires Firebase's pay-as-you-go plan.
    var photosEnabled: Bool?
    var usage: FleetUsage?
    /// "mi" or "km". Fleet-wide so everyone enters odometer readings in the same unit.
    var distanceUnit: String?
    /// "HH:mm" local time for the daily checklist reminder on everyone's phone; nil = off.
    var checklistReminderTime: String?
}

struct FleetUsage: Codable, Hashable {
    var photoBytes: Int64?
    var photoCount: Int64?
    /// Inspections, defects and service records created (used to estimate database size).
    var recordCount: Int64?
}

/// fleets/{fleetId}/members/{uid} — a person's profile and role within one fleet.
struct Member: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var role: FleetRole
    var displayName: String
    var phone: String
    var email: String
    /// When false, the member only sees vehicles whose `assignedUids` include them.
    var seesAllVehicles: Bool
    var inviteId: String?
    @ServerTimestamp var joinedAt: Date?
}

/// users/{uid}/memberships/{fleetId} — lets a user list the fleets they belong to.
struct Membership: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var fleetName: String
    @ServerTimestamp var joinedAt: Date?
}

enum InviteStatus: String, Codable {
    case pending, accepted, declined, revoked
}

/// invites/{inviteId}
struct Invite: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var fleetId: String
    var fleetName: String
    /// Always lowercased.
    var email: String
    var role: FleetRole
    var invitedBy: String
    var invitedByName: String
    @ServerTimestamp var createdAt: Date?
    var status: InviteStatus
}

/// The details a person enters when creating or joining a fleet.
struct ProfileDraft: Equatable {
    var displayName: String = ""
    var phone: String = ""

    var isValid: Bool { !displayName.trimmed.isEmpty }
}
