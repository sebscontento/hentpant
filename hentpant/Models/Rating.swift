//
//  Rating.swift
//  hentpant
//

import Foundation

struct Rating: Identifiable, Equatable {
    let id: UUID
    let listingId: UUID
    let fromUserId: String
    let toUserId: String
    let stars: Int
    let comment: String?
    let createdAt: Date
}
