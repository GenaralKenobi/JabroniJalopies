import Foundation

/// Overall state of a vehicle based on its open defects.
enum VehicleCondition: Int, Comparable {
    case ok = 0
    case needsAttention = 1
    case outOfService = 2

    static func < (lhs: VehicleCondition, rhs: VehicleCondition) -> Bool { lhs.rawValue < rhs.rawValue }

    init(openDefects: [Defect]) {
        let open = openDefects.filter(\.isOpen)
        if open.contains(where: \.unsafe) {
            self = .outOfService
        } else if !open.isEmpty {
            self = .needsAttention
        } else {
            self = .ok
        }
    }

    var label: String {
        switch self {
        case .ok: "No open defects"
        case .needsAttention: "Needs attention"
        case .outOfService: "Unsafe to drive"
        }
    }

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .needsAttention: "wrench.adjustable.fill"
        case .outOfService: "exclamationmark.octagon.fill"
        }
    }
}
