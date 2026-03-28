//
//  ListingStatus.swift
//  hentpant
//

import Foundation

enum ListingStatus: String, Codable {
    case available
    case reserved
    case awaitingGiverConfirmation
    case completed
    case removed

    var displayName: String {
        switch self {
        case .available: return String(localized: "Available")
        case .reserved: return String(localized: "Reserved")
        case .awaitingGiverConfirmation: return String(localized: "Awaiting confirmation")
        case .completed: return String(localized: "Completed")
        case .removed: return String(localized: "Removed")
        }
    }
}
