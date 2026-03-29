//
//  ListingStatus.swift
//  hentpant
//

import Foundation

enum ListingStatus: String, Codable {
    case available
    case pendingPickup = "pending_pickup"
    case completed
    case removed

    var displayName: String {
        switch self {
        case .available: return String(localized: "Available")
        case .pendingPickup: return String(localized: "Pending pickup")
        case .completed: return String(localized: "Completed")
        case .removed: return String(localized: "Removed")
        }
    }
}
