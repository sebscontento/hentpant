//
//  SupabaseDTOs.swift
//  hentpant
//

import Foundation

struct ListingInsert: Encodable {
    let id: UUID?
    let giver_id: UUID
    let photo_paths: [String]
    let quantity_text: String
    let bag_size: String
    let latitude: Double
    let longitude: Double
    let detail: String?
}

struct ProfileInsert: Encodable {
    let id: UUID
    let display_name: String
    let email: String
    let can_give: Bool
    let can_receive: Bool
}

struct RatingInsert: Encodable {
    let listing_id: UUID
    let from_user_id: UUID
    let to_user_id: UUID
    let stars: Int
    let comment: String?
}

struct ReportInsert: Encodable {
    let target: String
    let target_id: String
    let reporter_id: UUID
    let reason: String
}

struct SetListingPhotoPathsParams: Encodable {
    let p_listing_id: UUID
    let p_paths: [String]
}

/// RPCs that only take `p_listing_id` (claim, mark picked up, confirm).
struct ListingIdRpcParams: Encodable {
    let p_listing_id: UUID
}

struct ModerateListingParams: Encodable {
    let p_listing_id: UUID
    let p_reason: String?
}

struct AdminSetRoleParams: Encodable {
    let p_target: UUID
    let p_role: String
}

struct AdminDeleteUserParams: Encodable {
    let p_target: UUID
}

struct UpdateOwnRolesParams: Encodable {
    let p_can_give: Bool
    let p_can_receive: Bool
}

struct ReviewModeratorApplicationParams: Encodable {
    let p_target: UUID
    let p_approve: Bool
}

struct AwardPointsParams: Encodable {
    let p_user_id: UUID
    let p_points: Int
    let p_reason: String?
}

struct UnlockAchievementParams: Encodable {
    let p_user_id: UUID
    let p_type: String
}

struct ProfileRow: Codable, Hashable {
    let id: UUID
    var displayName: String
    var email: String
    var canGive: Bool
    var canReceive: Bool
    var staffRole: String
    var moderatorRequestStatus: String
    var averageRating: Double
    var ratingCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case canGive = "can_give"
        case canReceive = "can_receive"
        case staffRole = "staff_role"
        case moderatorRequestStatus = "moderator_request_status"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decode(String.self, forKey: .email)
        canGive = try container.decode(Bool.self, forKey: .canGive)
        canReceive = try container.decode(Bool.self, forKey: .canReceive)
        staffRole = try container.decode(String.self, forKey: .staffRole)
        moderatorRequestStatus = try container.decodeIfPresent(String.self, forKey: .moderatorRequestStatus) ?? "none"
        averageRating = try container.decode(Double.self, forKey: .averageRating)
        ratingCount = try container.decode(Int.self, forKey: .ratingCount)
    }

    func toUserProfile() -> UserProfile {
        UserProfile(
            id: id.uuidString,
            displayName: displayName,
            email: email,
            canGive: canGive,
            canReceive: canReceive,
            staffRole: StaffRole(rawValue: staffRole) ?? .user,
            moderatorRequestStatus: ModeratorRequestStatus(rawValue: moderatorRequestStatus) ?? .none,
            averageRating: averageRating,
            ratingCount: ratingCount
        )
    }
}

struct ListingRow: Codable, Hashable {
    let id: UUID
    let giverId: UUID
    var photoPaths: [String]
    var quantityText: String
    var bagSize: String
    var latitude: Double
    var longitude: Double
    var detail: String?
    var status: String
    var collectorId: UUID?
    var createdAt: Date
    var pickedUpAt: Date?
    var giverConfirmedAt: Date?
    var moderationReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case giverId = "giver_id"
        case photoPaths = "photo_paths"
        case quantityText = "quantity_text"
        case bagSize = "bag_size"
        case latitude
        case longitude
        case detail
        case status
        case collectorId = "collector_id"
        case createdAt = "created_at"
        case pickedUpAt = "picked_up_at"
        case giverConfirmedAt = "giver_confirmed_at"
        case moderationReason = "moderation_reason"
    }

    func toListing(photoUrls: [URL]) throws -> Listing {
        let mappedStatus: ListingStatus
        switch status {
        case "available":
            mappedStatus = .available
        case "pending_pickup", "claimed", "reserved":
            mappedStatus = .pendingPickup
        case "completed", "awaitingGiverConfirmation":
            mappedStatus = .completed
        case "removed":
            mappedStatus = .removed
        default:
            mappedStatus = .available
        }

        return Listing(
            id: id,
            giverId: giverId.uuidString,
            photoData: [],
            photoUrls: photoUrls,
            quantityText: quantityText,
            bagSize: BagSize(rawValue: bagSize) ?? .medium,
            latitude: latitude,
            longitude: longitude,
            detail: detail,
            status: mappedStatus,
            collectorId: collectorId?.uuidString,
            createdAt: createdAt,
            pickedUpAt: pickedUpAt,
            giverConfirmedAt: giverConfirmedAt,
            moderationReason: moderationReason
        )
    }
}

struct RatingRow: Codable, Hashable {
    let id: UUID
    let listingId: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let stars: Int
    let comment: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case listingId = "listing_id"
        case fromUserId = "from_user_id"
        case toUserId = "to_user_id"
        case stars
        case comment
        case createdAt = "created_at"
    }

    func toRating() -> Rating {
        Rating(
            id: id,
            listingId: listingId,
            fromUserId: fromUserId.uuidString,
            toUserId: toUserId.uuidString,
            stars: stars,
            comment: comment,
            createdAt: createdAt
        )
    }
}

struct ReportRow: Codable, Hashable {
    let id: UUID
    let target: String
    let targetId: String
    let reporterId: UUID
    let reason: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case target
        case targetId = "target_id"
        case reporterId = "reporter_id"
        case reason
        case createdAt = "created_at"
    }

    func toReport() -> Report {
        Report(
            id: id,
            target: ReportTarget(rawValue: target) ?? .listing,
            targetId: targetId,
            reporterId: reporterId.uuidString,
            reason: reason,
            createdAt: createdAt
        )
    }
}
