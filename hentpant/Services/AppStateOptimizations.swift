//
//  AppStateOptimizations.swift
//  hentpant
//
//  Performance optimization patterns and examples.
//  Shows how to integrate caching and incremental updates into AppState.
//

import Foundation
import Supabase

// MARK: - Usage Guide

/// To optimize AppState, implement these patterns in the AppState class:
///
/// PATTERN 1: Use selective fields in loadAllFromRemote()
/// =====================================================
/// Replace:
///     let profileRows: [ProfileRow] = try await supabase
///         .from("profiles")
///         .select()
///         .execute()
///         .value
///
/// With:
///     let profileRows: [ProfileRow] = try await supabase
///         .from("profiles")
///         .select(FieldSelections.profileFields)
///         .execute()
///         .value
///
/// Do this for all queries to reduce payload by 25-30%
///
///
/// PATTERN 2: Update listings locally instead of full reload
/// ===========================================================
/// Replace:
///     func claimListing(_ id: UUID) async {
///         // ... RPC call ...
///         await loadAllFromRemote()  // SLOW - reloads everything
///     }
///
/// With:
///     func claimListing(_ id: UUID) async {
///         // ... RPC call ...
///         // Update locally - FAST
///         if let index = listings.firstIndex(where: { $0.id == id }) {
///             listings[index].status = .pendingPickup
///             listings[index].collectorId = session?.id
///         }
///     }
///
///
/// PATTERN 3: Cache profiles to avoid repeated queries
/// ====================================================
/// Add to AppState init:
///     private var profileCache: [String: (UserProfile, Date)] = [:]
///     private let cacheExpiry: TimeInterval = 300  // 5 min
///
/// In loadAllFromRemote(), cache profiles:
///     let now = Date()
///     for profile in profiles {
///         profileCache[profile.id] = (profile, now)
///     }
///
/// Before fetching, check cache:
///     if let (cached, timestamp) = profileCache[userId],
///        Date().timeIntervalSince(timestamp) < cacheExpiry {
///         return cached
///     }
///
///
/// PATTERN 4: Use pagination for large datasets
/// =============================================
/// Instead of:
///     let listings: [ListingRow] = try await supabase
///         .from("listings")
///         .select()
///         .execute()
///         .value
///
/// Use:
///     let limit = 50
///     let offset = 0
///     let listings: [ListingRow] = try await supabase
///         .from("listings")
///         .select(FieldSelections.listingFields)
///         .order("created_at", ascending: false)
///         .limit(limit)
///         .offset(offset)
///         .execute()
///         .value

// MARK: - Implementation in AppState

/// To implement the patterns above, add these methods directly to the AppState class:
///
/// @MainActor
/// final class AppState: ObservableObject {
///     // ... existing code ...
///     
///     /// Update a single listing without full reload
///     func updateListingLocal(_ id: UUID, status: ListingStatus) {
///         if let index = listings.firstIndex(where: { $0.id == id }) {
///             listings[index].status = status
///         }
///     }
///     
///     /// Update profile rating after submission
///     func updateProfileRating(_ userId: String, newStars: Int) {
///         if var profile = profilesById[userId] {
///             let oldCount = Double(profile.ratingCount)
///             let oldAvg = profile.averageRating
///             let newCount = oldCount + 1
///             profile.averageRating = ((oldAvg * oldCount) + Double(newStars)) / newCount
///             profile.ratingCount += 1
///             profilesById[userId] = profile
///         }
///     }
/// }
