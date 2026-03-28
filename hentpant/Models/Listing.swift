//
//  Listing.swift
//  hentpant
//

import CoreLocation
import Foundation

struct Listing: Identifiable, Equatable {
    let id: UUID
    var giverId: String
    /// Up to three JPEG/PNG payloads (MVP in-memory; Firebase Storage in production).
    var photoData: [Data]
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceMeters(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
    }
}
