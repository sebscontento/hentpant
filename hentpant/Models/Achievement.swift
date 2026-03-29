//
//  Achievement.swift
//  hentpant
//

import Foundation

enum AchievementType: String, Codable, CaseIterable, Identifiable {
    case firstListing
    case firstPickup
    case tenListings
    case tenPickups
    case fiftyPickups
    case ecoWarrior
    case nightOwl
    case weekendWarrior
    case quickCollector
    case generousGiver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstListing: return String(localized: "First Steps")
        case .firstPickup: return String(localized: "First Pickup")
        case .tenListings: return String(localized: "Generous Giver")
        case .tenPickups: return String(localized: "Dedicated Collector")
        case .fiftyPickups: return String(localized: "Pant Champion")
        case .ecoWarrior: return String(localized: "Eco Warrior")
        case .nightOwl: return String(localized: "Night Owl")
        case .weekendWarrior: return String(localized: "Weekend Warrior")
        case .quickCollector: return String(localized: "Speed Collector")
        case .generousGiver: return String(localized: "Community Hero")
        }
    }

    var description: String {
        switch self {
        case .firstListing: return String(localized: "Post your first listing")
        case .firstPickup: return String(localized: "Complete your first pickup")
        case .tenListings: return String(localized: "Post 10 listings")
        case .tenPickups: return String(localized: "Complete 10 pickups")
        case .fiftyPickups: return String(localized: "Complete 50 pickups")
        case .ecoWarrior: return String(localized: "Collect 100kg of pant")
        case .nightOwl: return String(localized: "Complete a pickup after 9pm")
        case .weekendWarrior: return String(localized: "Complete 5 pickups on weekends")
        case .quickCollector: return String(localized: "Claim and complete a listing within 1 hour")
        case .generousGiver: return String(localized: "Give away 25 listings")
        }
    }

    var icon: String {
        switch self {
        case .firstListing: return "footprints"
        case .firstPickup: return "checkmark.circle.fill"
        case .tenListings: return "gift.fill"
        case .tenPickups: return "bag.fill"
        case .fiftyPickups: return "trophy.fill"
        case .ecoWarrior: return "leaf.fill"
        case .nightOwl: return "moon.fill"
        case .weekendWarrior: return "calendar"
        case .quickCollector: return "bolt.fill"
        case .generousGiver: return "heart.fill"
        }
    }

    var pointsReward: Int {
        switch self {
        case .firstListing: return 50
        case .firstPickup: return 100
        case .tenListings: return 250
        case .tenPickups: return 500
        case .fiftyPickups: return 2000
        case .ecoWarrior: return 1000
        case .nightOwl: return 75
        case .weekendWarrior: return 150
        case .quickCollector: return 100
        case .generousGiver: return 750
        }
    }
}

struct Achievement: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: String
    let type: AchievementType
    var unlockedAt: Date?
    var pointsAwarded: Int

    var isUnlocked: Bool {
        unlockedAt != nil
    }
}

struct UserAchievementProgress: Identifiable {
    let id: String
    let type: AchievementType
    let current: Int
    let required: Int
    let isUnlocked: Bool

    var progress: Float {
        guard required > 0 else { return 0 }
        let rawProgress = Float(current) / Float(required)
        return min(max(rawProgress, 0), 1)
    }
}
