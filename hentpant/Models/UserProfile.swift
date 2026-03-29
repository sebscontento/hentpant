//
//  UserProfile.swift
//  hentpant
//

import Foundation

enum ModeratorRequestStatus: String, Codable {
    case none
    case pending
    case rejected

    var isPending: Bool {
        self == .pending
    }
}

struct UserProfile: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var email: String
    /// User offers pant for others to collect.
    var canGive: Bool
    /// User can collect pant from others.
    var canReceive: Bool
    var staffRole: StaffRole
    var moderatorRequestStatus: ModeratorRequestStatus
    var averageRating: Double
    var ratingCount: Int

    var canPostPant: Bool {
        canGive || staffRole.isModeratorOrAbove
    }

    var canClaimPant: Bool {
        canReceive || staffRole.isModeratorOrAbove
    }

    var canDeleteAnyListing: Bool {
        staffRole == .moderator || staffRole == .admin
    }

    var canDeleteUsers: Bool {
        staffRole == .admin
    }

    var canPromoteRoles: Bool {
        staffRole == .admin
    }

    var canApplyForModerator: Bool {
        staffRole == .user && !moderatorRequestStatus.isPending
    }
}
