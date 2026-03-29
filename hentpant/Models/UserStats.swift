//
//  UserStats.swift
//  hentpant
//

import Foundation

struct UserStats: Identifiable, Codable, Equatable {
    let id: String
    var totalListingsPosted: Int
    var totalListingsCollected: Int
    var totalDistanceMeters: Double
    var totalEarningsDkk: Double
    var points: Int
    var level: Int
    var streakDays: Int
    var lastActiveDate: Date?

    var nextLevelPoints: Int {
        level * 500
    }

    var progressToNextLevel: Float {
        let currentLevelPoints = points
        let required = nextLevelPoints
        return required > 0 ? Float(currentLevelPoints) / Float(required) : 0
    }

    var levelTitle: String {
        switch level {
        case 0..<5: return String(localized: "Beginner")
        case 5..<10: return String(localized: "Collector")
        case 10..<20: return String(localized: "Eco Warrior")
        case 20..<30: return String(localized: "Pant Master")
        default: return String(localized: "Legend")
        }
    }
}
