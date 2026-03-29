//
//  Listing.swift
//  hentpant
//

import CoreLocation
import Foundation

struct Listing: Identifiable, Equatable {
    let id: UUID
    var giverId: String
    /// Local image bytes while composing a listing (not persisted).
    var photoData: [Data]
    /// Public storage URLs after upload (Supabase `listing-photos` bucket).
    var photoUrls: [URL]
    var quantityText: String
    var bagSize: BagSize
    var latitude: Double
    var longitude: Double
    var detail: String?
    var status: ListingStatus
    var collectorId: String?
    var createdAt: Date
    var pickedUpAt: Date?
    var giverConfirmedAt: Date?
    var moderationReason: String?

    /// First image for thumbnails: prefers remote URL, then local data.
    var primaryPhotoURL: URL? {
        photoUrls.first
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceMeters(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
    }

    func isOwned(by userId: String?) -> Bool {
        giverId == userId
    }

    func isParticipant(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return giverId == userId || collectorId == userId
    }

    func counterpartUserId(for userId: String?) -> String? {
        guard let userId else { return nil }
        if giverId == userId {
            return collectorId
        }
        if collectorId == userId {
            return giverId
        }
        return nil
    }

    func isClaimable(by user: UserProfile?) -> Bool {
        guard let user else { return false }
        return status == .available && !isOwned(by: user.id) && user.canClaimPant
    }

    func statusDisplay(for userId: String?) -> String {
        switch status {
        case .available where giverId == userId:
            return String(localized: "Live")
        case .pendingPickup where collectorId == userId:
            return String(localized: "Pending pickup")
        case .pendingPickup where giverId == userId:
            return String(localized: "Pending pickup")
        default:
            return status.displayName
        }
    }
}
