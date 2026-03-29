//
//  UserStats.swift
//  hentpant
//

import Foundation

struct UserStats: Identifiable, Codable, Equatable {
    static let pointsPerLevel = 500

    let id: String
    var totalListingsPosted: Int
    var totalListingsCollected: Int
    var totalDistanceMeters: Double
    var totalEarningsDkk: Double
    var points: Int
    var level: Int
    var streakDays: Int
    var lastActiveDate: Date?

    static func level(forPoints points: Int) -> Int {
        max(1, (points / Self.pointsPerLevel) + 1)
    }

    var currentLevelFloorPoints: Int {
        max(0, (level - 1) * Self.pointsPerLevel)
    }

    var nextLevelPoints: Int {
        level * Self.pointsPerLevel
    }

    var progressToNextLevel: Float {
        let currentLevelPoints = points - currentLevelFloorPoints
        let required = nextLevelPoints - currentLevelFloorPoints
        guard required > 0 else { return 0 }
        let rawProgress = Float(currentLevelPoints) / Float(required)
        return min(max(rawProgress, 0), 1)
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
