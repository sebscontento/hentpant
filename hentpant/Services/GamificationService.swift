//
//  GamificationService.swift
//  hentpant
//

import Foundation
import Supabase

/// Service for handling gamification operations (points, achievements, stats)
actor GamificationService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Stats

    func getUserStats(userId: String) async throws -> UserStats {
        guard let uuid = UUID(uuidString: userId) else {
            throw GamificationError.invalidUserId
        }

        let row: UserStatsRow = try await supabase
            .from("user_stats")
            .select()
            .eq("id", value: uuid)
            .single()
            .execute()
            .value

        return row.toUserStats()
    }

    func getLeaderboard(limit: Int = 10) async throws -> [UserStats] {
        let rows: [UserStatsRow] = try await supabase
            .from("user_stats")
            .select("id, points, level, total_listings_collected, total_listings_posted")
            .order("points", ascending: false)
            .limit(limit)
            .execute()
            .value

        return rows.map { $0.toUserStats() }
    }

    // MARK: - Achievements

    func getUserAchievements(userId: String) async throws -> [Achievement] {
        guard let uuid = UUID(uuidString: userId) else {
            throw GamificationError.invalidUserId
        }

        let rows: [AchievementRow] = try await supabase
            .from("achievements")
            .select()
            .eq("user_id", value: uuid)
            .execute()
            .value

        return rows.map { $0.toAchievement() }
    }

    func getAchievementProgress(userId: String) async throws -> [UserAchievementProgress] {
        let unlockedAchievements = try await getUserAchievements(userId: userId)
        let stats = try await getUserStats(userId: userId)

        var progress: [UserAchievementProgress] = []

        for type in AchievementType.allCases {
            let unlocked = unlockedAchievements.first { $0.type == type }
            let (current, required) = await getProgressForAchievement(type: type, stats: stats)

            progress.append(UserAchievementProgress(
                id: type.rawValue,
                type: type,
                current: current,
                required: required,
                isUnlocked: unlocked?.isUnlocked ?? false
            ))
        }

        return progress
    }

    private func getProgressForAchievement(type: AchievementType, stats: UserStats) async -> (current: Int, required: Int) {
        switch type {
        case .firstListing:
            return (stats.totalListingsPosted, 1)
        case .firstPickup:
            return (stats.totalListingsCollected, 1)
        case .tenListings:
            return (stats.totalListingsPosted, 10)
        case .tenPickups:
            return (stats.totalListingsCollected, 10)
        case .fiftyPickups:
            return (stats.totalListingsCollected, 50)
        case .ecoWarrior:
            // Estimate: average 2kg per listing collected
            let estimatedKg = Int(Double(stats.totalListingsCollected) * 2.0)
            return (estimatedKg, 100)
        case .nightOwl:
            // This requires time-based tracking, simplified for now
            return (0, 1)
        case .weekendWarrior:
            // Requires weekend-specific tracking
            return (0, 5)
        case .quickCollector:
            // Requires timing tracking
            return (0, 1)
        case .generousGiver:
            return (stats.totalListingsPosted, 25)
        }
    }

    // MARK: - Point Awards

    func awardPoints(userId: String, points: Int, reason: String? = nil) async {
        guard let uuid = UUID(uuidString: userId) else { return }

        do {
            try await supabase.rpc(
                "award_points",
                params: AwardPointsParams(p_user_id: uuid, p_points: points, p_reason: reason)
            ).execute()
        } catch {
            print("Failed to award points: \(error)")
        }
    }

    func unlockAchievement(userId: String, type: AchievementType) async -> Bool {
        guard let uuid = UUID(uuidString: userId) else { return false }

        do {
            let result: Bool = try await supabase
                .rpc("unlock_achievement", params: UnlockAchievementParams(p_user_id: uuid, p_type: type.rawValue))
                .execute()
                .value
            return result
        } catch {
            print("Failed to unlock achievement: \(error)")
            return false
        }
    }

    // MARK: - Listing Actions

    func processListingPosted(userId: String) async {
        // Points and base achievements (like firstListing) are securely handled
        // by Supabase standard database triggers automatically.
    }

    func processPickupCompleted(giverId: String, collectorId: String, distanceMeters: Double, bagSize: String) async {
        // Base points and core gamification are now securely handled by Supabase database 
        // triggers automatically upon status transitioning.
        
        // Check for night owl (after 9pm)
        if Calendar.current.component(.hour, from: .now) >= 21 {
            await checkAndUnlockAchievement(userId: collectorId, type: .nightOwl)
        }

        // Check for weekend warrior
        let weekday = Calendar.current.component(.weekday, from: .now)
        if weekday == 1 || weekday == 7 { // Sunday or Saturday
            await checkAndUnlockAchievement(userId: collectorId, type: .weekendWarrior)
        }
    }

    private func checkAndUnlockAchievement(userId: String, type: AchievementType) async {
        let unlocked = await unlockAchievement(userId: userId, type: type)
        if unlocked {
            print("Achievement unlocked: \(type.displayName)")
        }
    }
}

// MARK: - Database Rows

struct UserStatsRow: Codable {
    let id: UUID
    let total_listings_posted: Int
    let total_listings_collected: Int
    let total_distance_meters: Double
    let total_earnings_dkk: Double
    let points: Int
    let level: Int
    let streak_days: Int
    let last_active_date: Date?
    let created_at: Date
    let updated_at: Date

    func toUserStats() -> UserStats {
        UserStats(
            id: id.uuidString,
            totalListingsPosted: total_listings_posted,
            totalListingsCollected: total_listings_collected,
            totalDistanceMeters: total_distance_meters,
            totalEarningsDkk: total_earnings_dkk,
            points: points,
            level: UserStats.level(forPoints: points),
            streakDays: streak_days,
            lastActiveDate: last_active_date
        )
    }
}

struct AchievementRow: Codable {
    let id: UUID
    let user_id: UUID
    let type: String
    let unlocked_at: Date?
    let points_awarded: Int
    let created_at: Date

    func toAchievement() -> Achievement {
        Achievement(
            id: id,
            userId: user_id.uuidString,
            type: AchievementType(rawValue: type) ?? .firstListing,
            unlockedAt: unlocked_at,
            pointsAwarded: points_awarded
        )
    }
}

// MARK: - Errors

enum GamificationError: LocalizedError {
    case invalidUserId
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidUserId:
            return String(localized: "Invalid user ID")
        case .networkError:
            return String(localized: "Network error")
        }
    }
}
