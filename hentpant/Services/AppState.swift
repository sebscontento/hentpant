//
//  AppState.swift
//  hentpant
//
//  Central app state (MVVM). Swap persistence for Firebase Auth, Firestore, Storage, and Functions.
//

import AuthenticationServices
import CoreLocation
import CryptoKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: UserProfile?
    @Published private(set) var listings: [Listing] = []
    @Published private(set) var ratings: [Rating] = []
    @Published private(set) var reports: [Report] = []
    @Published private(set) var profilesById: [String: UserProfile] = [:]
    @Published var authError: String?

    private var passwordByEmail: [String: String] = [:]

    init() {
        seedDemoDataIfNeeded()
    }

    // MARK: - Auth (email + Sign in with Apple; admin via demo seed)

    func signUp(
        email: String,
        password: String,
        displayName: String,
        canGive: Bool,
        canReceive: Bool
    ) {
        authError = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, password.count >= 6 else {
            authError = String(localized: "Enter a valid email and password (min 6 characters).")
            return
        }
        guard canGive || canReceive else {
            authError = String(localized: "Select at least giver or receiver.")
            return
        }
        guard passwordByEmail[normalized] == nil else {
            authError = String(localized: "An account with this email already exists.")
            return
        }
        passwordByEmail[normalized] = password
        let id = UUID().uuidString
        let profile = UserProfile(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: normalized,
            canGive: canGive,
            canReceive: canReceive,
            staffRole: .user,
            averageRating: 0,
            ratingCount: 0
        )
        profilesById[id] = profile
        session = profile
    }

    func signIn(email: String, password: String) {
        authError = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let stored = passwordByEmail[normalized], stored == password else {
            authError = String(localized: "Invalid email or password.")
            return
        }
        guard let profile = profilesById.values.first(where: { $0.email == normalized }) else {
            authError = String(localized: "Profile missing.")
            return
        }
        session = profile
    }

    func signOut() {
        session = nil
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        authError = nil
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            authError = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authError = String(localized: "Could not read Apple credential.")
                return
            }
            let userId = credential.user
            let email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ?? "apple_\(userId)@privaterelay.appleid.com"
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let display = name.isEmpty ? String(localized: "Apple User") : name

            if var existing = profilesById[userId] {
                if existing.email != email { existing.email = email }
                if existing.displayName == String(localized: "Apple User"), !display.isEmpty {
                    existing.displayName = display
                }
                profilesById[userId] = existing
                session = existing
            } else {
                let profile = UserProfile(
                    id: userId,
                    displayName: display,
                    email: email,
                    canGive: true,
                    canReceive: true,
                    staffRole: .user,
                    averageRating: 0,
                    ratingCount: 0
                )
                profilesById[userId] = profile
                session = profile
            }
        }
    }

    // MARK: - Listings

    func createListing(
        photoData: [Data],
        quantityText: String,
        bagSize: BagSize,
        latitude: Double,
        longitude: Double,
        detail: String?
    ) {
        guard let user = session, user.canPostPant else { return }
        let listing = Listing(
            id: UUID(),
            giverId: user.id,
            photoData: Array(photoData.prefix(3)),
            quantityText: quantityText,
            bagSize: bagSize,
            latitude: latitude,
            longitude: longitude,
            detail: detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            status: .available,
            collectorId: nil,
            createdAt: Date(),
            pickedUpAt: nil,
            giverConfirmedAt: nil,
            moderationReason: nil
        )
        listings.insert(listing, at: 0)
    }

    func claimListing(_ id: UUID) {
        guard let user = session, user.canClaimPant else { return }
        guard let index = listings.firstIndex(where: { $0.id == id }) else { return }
        guard listings[index].status == .available else { return }
        listings[index].status = .reserved
        listings[index].collectorId = user.id
    }

    func markPickedUp(_ id: UUID) {
        guard let user = session else { return }
        guard let index = listings.firstIndex(where: { $0.id == id }) else { return }
        guard listings[index].status == .reserved, listings[index].collectorId == user.id else { return }
        listings[index].status = .awaitingGiverConfirmation
        listings[index].pickedUpAt = Date()
    }

    func confirmPickup(_ id: UUID) {
        guard let user = session else { return }
        guard let index = listings.firstIndex(where: { $0.id == id }) else { return }
        guard listings[index].giverId == user.id else { return }
        guard listings[index].status == .awaitingGiverConfirmation else { return }
        listings[index].status = .completed
        listings[index].giverConfirmedAt = Date()
    }

    func deleteListing(_ id: UUID, reason: String?) {
        guard let user = session, user.canDeleteAnyListing else { return }
        guard let index = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[index].status = .removed
        listings[index].moderationReason = reason
    }

    func deleteUser(_ id: String) {
        guard let admin = session, admin.canDeleteUsers else { return }
        guard id != admin.id else { return }
        profilesById[id] = nil
        listings.removeAll { $0.giverId == id || $0.collectorId == id }
        if session?.id == id { session = nil }
    }

    func setStaffRole(_ userId: String, role: StaffRole) {
        guard let admin = session, admin.canPromoteRoles else { return }
        guard userId != admin.id else { return }
        guard var profile = profilesById[userId] else { return }
        if role == .admin { profile.staffRole = .admin }
        else if role == .moderator { profile.staffRole = .moderator }
        else { profile.staffRole = .user }
        profilesById[userId] = profile
        if session?.id == userId { session = profile }
    }

    // MARK: - Ratings

    func submitRating(listingId: UUID, toUserId: String, stars: Int, comment: String?) {
        guard let user = session else { return }
        guard stars >= 1 && stars <= 5 else { return }
        guard let listing = listings.first(where: { $0.id == listingId }), listing.status == .completed else { return }
        guard listing.giverId == user.id || listing.collectorId == user.id else { return }
        guard toUserId != user.id else { return }
        guard toUserId == listing.giverId || toUserId == listing.collectorId else { return }
        if ratings.contains(where: { $0.listingId == listingId && $0.fromUserId == user.id && $0.toUserId == toUserId }) {
            return
        }
        let r = Rating(
            id: UUID(),
            listingId: listingId,
            fromUserId: user.id,
            toUserId: toUserId,
            stars: stars,
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: Date()
        )
        ratings.append(r)
        recomputeReputation(for: toUserId)
    }

    // MARK: - Reports

    func submitReport(target: ReportTarget, targetId: String, reason: String) {
        guard let user = session else { return }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reports.append(
            Report(
                id: UUID(),
                target: target,
                targetId: targetId,
                reporterId: user.id,
                reason: trimmed,
                createdAt: Date()
            )
        )
    }

    // MARK: - Queries

    func profile(id: String) -> UserProfile? {
        profilesById[id]
    }

    func displayName(for userId: String) -> String {
        profilesById[userId]?.displayName ?? String(localized: "Unknown user")
    }

    func openListings() -> [Listing] {
        listings.filter { $0.status == .available || $0.status == .reserved || $0.status == .awaitingGiverConfirmation }
    }

    func needsRatingPrompt(for listingId: UUID) -> UserProfile? {
        guard let user = session else { return nil }
        guard let listing = listings.first(where: { $0.id == listingId }), listing.status == .completed else { return nil }
        let other: String?
        if listing.giverId == user.id { other = listing.collectorId }
        else if listing.collectorId == user.id { other = listing.giverId }
        else { other = nil }
        guard let otherId = other else { return nil }
        let already = ratings.contains { $0.listingId == listingId && $0.fromUserId == user.id && $0.toUserId == otherId }
        if already { return nil }
        return profilesById[otherId]
    }

    // MARK: - Private

    private func recomputeReputation(for userId: String) {
        let relevant = ratings.filter { $0.toUserId == userId }
        guard !relevant.isEmpty else { return }
        let sum = relevant.reduce(0) { $0 + $1.stars }
        let avg = Double(sum) / Double(relevant.count)
        guard var p = profilesById[userId] else { return }
        p.averageRating = (avg * 10).rounded() / 10
        p.ratingCount = relevant.count
        profilesById[userId] = p
        if session?.id == userId { session = p }
    }

    private func seedDemoDataIfNeeded() {
        let modId = "demo-mod"
        let adminId = "demo-admin"
        profilesById[modId] = UserProfile(
            id: modId,
            displayName: "Demo Moderator",
            email: "mod@demo.pant",
            canGive: true,
            canReceive: true,
            staffRole: .moderator,
            averageRating: 4.8,
            ratingCount: 12
        )
        profilesById[adminId] = UserProfile(
            id: adminId,
            displayName: "Demo Admin",
            email: "admin@demo.pant",
            canGive: true,
            canReceive: true,
            staffRole: .admin,
            averageRating: 5,
            ratingCount: 3
        )
        passwordByEmail["mod@demo.pant"] = "demo12"
        passwordByEmail["admin@demo.pant"] = "demo12"

        let cph = (55.6761, 12.5683)
        let demo = Listing(
            id: UUID(),
            giverId: modId,
            photoData: [],
            quantityText: "~25 bottles",
            bagSize: .medium,
            latitude: cph.0 + 0.01,
            longitude: cph.1 + 0.005,
            detail: String(localized: "Demo listing by the bench (sample data)."),
            status: .available,
            collectorId: nil,
            createdAt: Date().addingTimeInterval(-3600),
            pickedUpAt: nil,
            giverConfirmedAt: nil,
            moderationReason: nil
        )
        listings.append(demo)
    }

    // MARK: - Apple helpers (nonce)

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset[Int.random(in: 0..<charset.count)])
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
