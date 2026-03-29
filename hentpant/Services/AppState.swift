//
//  AppState.swift
//  hentpant
//
//  Central app state backed by Supabase Auth, PostgREST, Storage, and RPC.
//

import AuthenticationServices
import CoreLocation
import CryptoKit
import Foundation
import Supabase

enum AppTab: Hashable {
    case map
    case list
    case create
    case profile
}

struct CreateListingPrefill: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
    let addressLabel: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: UserProfile?
    @Published private(set) var userStats: UserStats?
    @Published private(set) var achievements: [Achievement] = []
    @Published private(set) var achievementProgress: [UserAchievementProgress] = []
    @Published private(set) var listings: [Listing] = []
    @Published private(set) var ratings: [Rating] = []
    @Published private(set) var reports: [Report] = []
    @Published private(set) var profilesById: [String: UserProfile] = [:]
    @Published private(set) var listingActionIds: Set<UUID> = []
    @Published var authError: String?
    @Published private(set) var flowNotice: String?
    @Published private(set) var authInFlight = false
    @Published var selectedTab: AppTab = .map
    @Published private(set) var createListingPrefill: CreateListingPrefill?
    @Published var recentlyUnlockedAchievement: AchievementType?

    private var appleRawNonce: String?
    private var flowNoticeSequence = 0
    private let listingPhotoService = ListingPhotoService()
    private let pushNotificationManager = PushNotificationManager.shared
    private var gamificationService: GamificationService?

    init(skipAuthListener: Bool = false) {
        self.gamificationService = GamificationService(supabase: supabase)
        if !skipAuthListener {
            Task { await startAuthListener() }
        }
        setupPushNotificationHandler()
    }
    
    // MARK: - Push Notifications Setup
    
    private func setupPushNotificationHandler() {
        pushNotificationManager.setNotificationHandler { [weak self] payload in
            Task { @MainActor in
                await self?.handleIncomingNotification(payload)
            }
        }
    }
    
    private func handleIncomingNotification(_ payload: NotificationPayload) async {
        // Update UI based on notification type
        switch payload.eventTypeEnum {
        case .listingClaimed, .listingPickedUp, .confirmationRequested, .listingCompleted, .listingRemoved:
            // Refresh listings when listing status changes
            if let listingId = payload.listingId {
                postFlowNotice(payload.body)
                await refresh()
            }
        case .ratingReceived:
            postFlowNotice("You received a new rating: \(payload.body)")
            await refresh()
        case .moderationAlert:
            postFlowNotice("Moderation notice: \(payload.body)")
        case .general:
            postFlowNotice(payload.body)
        }
    }

    // MARK: - Auth

    func signUp(
        email: String,
        password: String,
        displayName: String,
        canGive: Bool,
        canReceive: Bool
    ) async {
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        authError = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, password.count >= 6 else {
            authError = String(localized: "Enter a valid email and password (min 6 characters).")
            return
        }
        guard !trimmedDisplayName.isEmpty else {
            authError = String(localized: "Enter a display name.")
            return
        }
        guard canGive || canReceive else {
            authError = String(localized: "Select at least giver or receiver.")
            return
        }
        do {
            let response = try await supabase.auth.signUp(
                email: normalized,
                password: password,
                data: [
                    "display_name": .string(trimmedDisplayName),
                    "can_give": .bool(canGive),
                    "can_receive": .bool(canReceive),
                ]
            )
            let session = try await sessionAfterSignUp(response: response, email: normalized, password: password)
            try await waitForProfile(for: session.user.id)
            try await applySession(session)
        } catch {
            authError = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        authError = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let session = try await supabase.auth.signIn(email: normalized, password: password)
            try await loadProfile(for: session.user)
            try await applySession(session)
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        authError = nil
        do {
            try await supabase.auth.signOut()
            clearLocalState()
        } catch {
            authError = error.localizedDescription
        }
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = randomNonceString()
        appleRawNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(raw)
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
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                authError = String(localized: "Missing Apple identity token.")
                return
            }
            guard let rawNonce = appleRawNonce else {
                authError = String(localized: "Sign-in was not prepared correctly. Try again.")
                return
            }
            appleRawNonce = nil
            Task {
                await signInWithApple(idToken: idToken, nonce: rawNonce, credential: credential)
            }
        }
    }

    private func signInWithApple(
        idToken: String,
        nonce: String,
        credential: ASAuthorizationAppleIDCredential
    ) async {
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            try await ensureAppleProfile(credential: credential, userId: session.user.id)
            try await applySession(session)
        } catch {
            authError = error.localizedDescription
        }
    }

    private func ensureAppleProfile(credential: ASAuthorizationAppleIDCredential, userId: UUID) async throws {
        // Wait for the auth trigger to create the profile (up to 3 seconds)
        for attempt in 0..<6 {
            do {
                let _: ProfileRow = try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                return
            } catch {
                if attempt < 5 {
                    // Profile not ready yet, wait and retry
                    try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
                    continue
                }
                // After retries, try to create profile with Apple info
                let email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    ?? "apple_\(credential.user)@privaterelay.appleid.com"
                let given = credential.fullName?.givenName
                let family = credential.fullName?.familyName
                let name = [given, family].compactMap { $0 }.joined(separator: " ")
                let display = name.isEmpty ? String(localized: "Apple User") : name
                try await createProfile(
                    for: userId,
                    displayName: display,
                    email: email,
                    canGive: true,
                    canReceive: true
                )
                return
            }
        }
    }

    /// Reload listings, profiles, and ratings from Supabase.
    func refresh() async {
        authError = nil
        do {
            _ = try await supabase.auth.session
            await loadAllFromRemote()
            await refreshGamificationData()
        } catch let error as AuthError where error == .sessionMissing {
            clearLocalState()
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Listings

    @discardableResult
    func createListing(
        photos: [ProcessedListingImage],
        quantityText: String,
        bagSize: BagSize,
        latitude: Double,
        longitude: Double,
        detail: String?
    ) async -> Bool {
        guard let user = session, user.canPostPant, let uid = UUID(uuidString: user.id) else { return false }
        authError = nil
        guard !photos.isEmpty else {
            authError = String(localized: "Add at least one photo before publishing.")
            return false
        }
        let q = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard trimmedDetail != nil else {
            authError = String(localized: "Add a description with pickup notes before publishing.")
            return false
        }

        var createdListingId: UUID?
        var uploadedPaths: [String] = []
        do {
            let listingId = UUID()
            let uploadPlan = listingPhotoService.makeUploadPlan(listingId: listingId, images: photos)
            let plannedPhotoPaths = uploadPlan.map(\.path)
            let insert = ListingInsert(
                id: listingId,
                giver_id: uid,
                photo_paths: plannedPhotoPaths,
                quantity_text: q,
                bag_size: bagSize.rawValue,
                latitude: latitude,
                longitude: longitude,
                detail: trimmedDetail
            )
            let row: ListingRow = try await supabase.from("listings").insert(insert).select().single().execute().value
            createdListingId = listingId
            uploadedPaths = try await listingPhotoService.uploadPhotos(uploadPlan)
            let listing = try row.toListing(photoUrls: listingPhotoService.publicURLs(for: row.photoPaths))
            listings.removeAll { $0.id == listing.id }
            listings.insert(listing, at: 0)
            await refreshGamificationData()
            postFlowNotice(String(localized: "Listing published. It is now available for receivers to claim."))

            return true
        } catch {
            let createdListing = createdListingId != nil
            let cleanupSucceeded: Bool
            if let listingId = createdListingId {
                cleanupSucceeded = await rollbackFailedListingCreation(
                    listingId: listingId,
                    uploadedPaths: uploadedPaths
                )
            } else {
                cleanupSucceeded = false
            }
            authError = listingCreationMessage(
                for: error,
                createdListing: createdListing,
                cleanupSucceeded: cleanupSucceeded
            )
            return false
        }
    }

    func claimListing(_ id: UUID) async {
        guard let user = session else { return }
        guard user.canClaimPant else {
            authError = String(localized: "Your account is not currently allowed to claim listings. Enable the receiver role in Profile and try again.")
            return
        }
        await runListingRpc(
            id,
            successMessage: String(localized: "Listing is now pending pickup. Pickup contact details are now visible.")
        ) {
            try await supabase.rpc("claim_listing", params: ListingIdRpcParams(p_listing_id: id)).execute()
        }
    }

    func markListingDone(_ id: UUID) async {
        await runListingRpc(
            id,
            successMessage: String(localized: "Pickup completed. The listing is now marked done.")
        ) {
            try await supabase.rpc("mark_listing_picked_up", params: ListingIdRpcParams(p_listing_id: id)).execute()
        }
    }

    func releaseListingClaim(_ id: UUID) async {
        await runListingRpc(
            id,
            successMessage: String(localized: "Listing is available again.")
        ) {
            try await supabase.rpc("release_listing_claim", params: ListingIdRpcParams(p_listing_id: id)).execute()
        }
    }

    func deleteListing(_ id: UUID, reason: String?) async {
        await runListingRpc(
            id,
            successMessage: String(localized: "Listing removed from the map and list.")
        ) {
            try await supabase.rpc(
                "moderate_remove_listing",
                params: ModerateListingParams(p_listing_id: id, p_reason: reason)
            ).execute()
        }
    }

    func deleteUser(_ id: String) async {
        guard !id.isEmpty else { return }
        authError = String(
            localized: "User deletion is disabled in the app right now. Use the Supabase Dashboard until a supported backend flow is added."
        )
    }

    func updateParticipationRoles(canGive: Bool, canReceive: Bool) async {
        guard canGive || canReceive else {
            authError = String(localized: "Choose at least one role: giver or receiver.")
            return
        }
        await runRpc(successMessage: String(localized: "Participation roles updated.")) {
            try await supabase.rpc(
                "update_own_participation_roles",
                params: UpdateOwnRolesParams(p_can_give: canGive, p_can_receive: canReceive)
            ).execute()
        }
    }

    func applyForModerator() async {
        await runRpc(successMessage: String(localized: "Moderator application submitted for review.")) {
            try await supabase.rpc("request_moderator_role").execute()
        }
    }

    func setStaffRole(_ userId: String, role: StaffRole) async {
        guard let target = UUID(uuidString: userId) else { return }
        await runRpc(successMessage: String(localized: "Staff role updated.")) {
            try await supabase.rpc(
                "admin_set_staff_role",
                params: AdminSetRoleParams(p_target: target, p_role: role.rawValue)
            ).execute()
        }
    }

    func reviewModeratorApplication(_ userId: String, approve: Bool) async {
        guard let target = UUID(uuidString: userId) else { return }
        await runRpc(
            successMessage: approve
                ? String(localized: "Moderator application approved.")
                : String(localized: "Moderator application rejected.")
        ) {
            try await supabase.rpc(
                "admin_review_moderator_application",
                params: ReviewModeratorApplicationParams(p_target: target, p_approve: approve)
            ).execute()
        }
    }

    // MARK: - Ratings & reports

    @discardableResult
    func submitRating(listingId: UUID, toUserId: String, stars: Int, comment: String?) async -> Bool {
        guard let user = session, let from = UUID(uuidString: user.id), let to = UUID(uuidString: toUserId) else { return false }
        guard stars >= 1 && stars <= 5 else { return false }
        authError = nil
        do {
            try await supabase.from("ratings").insert(
                RatingInsert(
                    listing_id: listingId,
                    from_user_id: from,
                    to_user_id: to,
                    stars: stars,
                    comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            ).execute()
            await loadAllFromRemote()
            await refreshGamificationData()
            postFlowNotice(String(localized: "Thanks for leaving a rating."))
            return true
        } catch {
            authError = submissionMessage(
                for: error,
                feature: String(localized: "ratings"),
                fallback: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    func submitReport(target: ReportTarget, targetId: String, reason: String) async -> Bool {
        guard let user = session, let reporter = UUID(uuidString: user.id) else { return false }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        authError = nil
        do {
            try await supabase.from("reports").insert(
                ReportInsert(
                    target: target.rawValue,
                    target_id: targetId,
                    reporter_id: reporter,
                    reason: trimmed
                )
            ).execute()
            postFlowNotice(String(localized: "Report submitted."))
            return true
        } catch {
            authError = submissionMessage(
                for: error,
                feature: String(localized: "reporting"),
                fallback: error.localizedDescription
            )
            return false
        }
    }

    // MARK: - Queries

    func profile(id: String) -> UserProfile? {
        profilesById[id]
    }

    func displayName(for userId: String) -> String {
        profilesById[userId]?.displayName ?? String(localized: "Unknown user")
    }

    func isListingActionInFlight(_ listingId: UUID) -> Bool {
        listingActionIds.contains(listingId)
    }

    func clearAuthError() {
        authError = nil
    }

    func clearFlowNotice() {
        flowNotice = nil
    }

    func beginCreateListing(latitude: Double, longitude: Double, addressLabel: String? = nil) {
        guard session?.canPostPant == true else { return }
        createListingPrefill = CreateListingPrefill(
            latitude: latitude,
            longitude: longitude,
            addressLabel: addressLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        selectedTab = .create
    }

    func clearCreateListingPrefill() {
        createListingPrefill = nil
    }

    func openListings() -> [Listing] {
        listings.filter { shouldShowInOpenFlow($0, for: session?.id) }
    }

    func availableListings() -> [Listing] {
        listings.filter { listing in
            listing.status == .available && !listing.isOwned(by: session?.id)
        }
    }

    func activeJourneyListings() -> [Listing] {
        guard let userId = session?.id else { return [] }
        return listings.filter { listing in
            isOpenStatus(listing.status) && (listing.giverId == userId || listing.collectorId == userId)
        }
    }

    func needsRatingPrompt(for listingId: UUID) -> UserProfile? {
        guard let user = session else { return nil }
        guard let listing = listings.first(where: { $0.id == listingId }), listing.status == .completed else { return nil }
        let other: String?
        if listing.giverId == user.id { other = listing.collectorId }
        else if listing.collectorId == user.id { other = listing.giverId }
        else { other = nil }
        guard let otherId = other else { return nil }
        let already = ratings.contains {
            $0.listingId == listingId && $0.fromUserId == user.id && $0.toUserId == otherId
        }
        if already { return nil }
        return profilesById[otherId]
    }

    // MARK: - Private

    private func startAuthListener() async {
        for await (event, authSession) in supabase.auth.authStateChanges {
            switch event {
            case .signedOut, .userDeleted:
                clearLocalState()
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery, .mfaChallengeVerified:
                if let authSession, !authSession.isExpired {
                    try? await applySession(authSession)
                } else {
                    clearLocalState()
                }
            }
        }
    }

    private func applySession(_ session: Session) async throws {
        // loadAllFromRemote handles all errors internally and sets authError if needed
        // It no longer throws, so we can safely call it here
        await loadAllFromRemote()
        let uid = session.user.id.uuidString
        self.session = profilesById[uid]

        // Load gamification data
        await loadGamificationData(userId: uid)

        // Setup push notifications after session is established
        await setupPushNotifications()
    }
    
    private func setupPushNotifications() async {
        // Request notification permissions
        await pushNotificationManager.requestNotificationPermission()
        
        // Register token with backend once available
        if let token = pushNotificationManager.deviceToken {
            await pushNotificationManager.registerTokenWithBackend(token, supabaseClient: supabase)
        }
    }

    private func sessionAfterSignUp(response: AuthResponse, email: String, password: String) async throws -> Session {
        if let session = response.session {
            return session
        }
        do {
            return try await supabase.auth.signIn(email: email, password: password)
        } catch {
            throw NSError(
                domain: "AppState",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Account created, but automatic sign-in failed. Please try logging in."]
            )
        }
    }

    private func createProfile(
        for userId: UUID,
        displayName: String,
        email: String,
        canGive: Bool,
        canReceive: Bool
    ) async throws {
        try await supabase.from("profiles").insert(
            ProfileInsert(
                id: userId,
                display_name: displayName,
                email: email,
                can_give: canGive,
                can_receive: canReceive
            )
        ).execute()
    }

    private func waitForProfile(for userId: UUID, attempts: Int = 5) async throws {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                let _: ProfileRow = try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }

        throw lastError ?? NSError(
            domain: "AppState",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Profile was not created for the new account."]
        )
    }

    private func loadProfile(for user: User) async throws {
        do {
            let _: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
        } catch {
            throw NSError(
                domain: "AppState",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Profile not found for user"]
            )
        }
    }

    private func loadAllFromRemote() async {
        do {
            let profileRows: [ProfileRow] = try await supabase.from("profiles").select().execute().value
            profilesById = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id.uuidString, $0.toUserProfile()) })
        } catch {
            profilesById = [:]
            if authError == nil {
                authError = nonBlockingSyncMessage(for: error, feature: String(localized: "profiles"))
            }
        }

        do {
            let listingRows: [ListingRow] = try await supabase.from("listings")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            listings = try listingRows.map { row in
                let urls = try listingPhotoService.publicURLs(for: row.photoPaths)
                return try row.toListing(photoUrls: urls)
            }
        } catch {
            listings = []
            if authError == nil {
                authError = nonBlockingSyncMessage(for: error, feature: String(localized: "listings"))
            }
        }

        do {
            let ratingRows: [RatingRow] = try await supabase.from("ratings").select().execute().value
            ratings = ratingRows.map { $0.toRating() }
        } catch {
            ratings = []
            if authError == nil {
                authError = nonBlockingSyncMessage(for: error, feature: String(localized: "ratings"))
            }
        }

        if let uid = try? await supabase.auth.session.user.id.uuidString {
            session = profilesById[uid]
            if session?.canDeleteAnyListing == true || session?.canPromoteRoles == true {
                do {
                    let reportRows: [ReportRow] = try await supabase.from("reports")
                        .select()
                        .order("created_at", ascending: false)
                        .execute()
                        .value
                    reports = reportRows.map { $0.toReport() }
                } catch {
                    reports = []
                    if authError == nil {
                        authError = nonBlockingSyncMessage(for: error, feature: String(localized: "reports"))
                    }
                }
            } else {
                reports = []
            }
        }
    }

    private func nonBlockingSyncMessage(for error: Error, feature: String) -> String {
        let message = error.localizedDescription.lowercased()
        if isSupabaseSchemaMismatchError(message) {
            return String(
                localized: "Signed in, but some \(feature) data could not be loaded because the connected Supabase project is missing the latest schema. Apply the latest migrations, then refresh."
            )
        }
        return String(localized: "Signed in, but some \(feature) data could not be loaded right now.")
    }

    private func submissionMessage(for error: Error, feature: String, fallback: String) -> String {
        let message = error.localizedDescription.lowercased()
        if isSupabaseSchemaMismatchError(message) {
            return String(
                localized: "\(feature.capitalized) is temporarily unavailable because the connected Supabase project is missing the latest schema. Apply the latest migrations, then try again."
            )
        }
        return fallback
    }

    private func listingCreationMessage(for error: Error, createdListing: Bool, cleanupSucceeded: Bool) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("mime") || message.contains("image") || message.contains("storage") || message.contains("upload") {
            if createdListing && cleanupSucceeded {
                return String(localized: "We could not finish posting your listing, so the unfinished draft was removed. Please try again with smaller photos if needed.")
            }
            if createdListing {
                return String(localized: "We could not finish posting your listing, and cleanup may have been incomplete. Refresh the app and check for a partial listing before trying again.")
            }
            return String(localized: "One or more photos could not be prepared or uploaded. Please try again with smaller photos if needed.")
        }
        if createdListing && cleanupSucceeded {
            return String(localized: "We could not finish posting your listing, so the unfinished draft was removed. Please try again.")
        }
        if createdListing {
            return String(localized: "We could not finish posting your listing, and cleanup may have been incomplete. Refresh the app and check for a partial listing before trying again.")
        }
        return error.localizedDescription
    }

    private func rollbackFailedListingCreation(listingId: UUID, uploadedPaths: [String]) async -> Bool {
        do {
            if !uploadedPaths.isEmpty {
                try await listingPhotoService.deletePhotos(paths: uploadedPaths)
            }
            try await supabase.from("listings").delete().eq("id", value: listingId).execute()
            listings.removeAll { $0.id == listingId }
            return true
        } catch {
            return false
        }
    }

    private func runRpc(successMessage: String? = nil, _ op: () async throws -> Void) async {
        authError = nil
        do {
            try await op()
            await loadAllFromRemote()
            await refreshGamificationData()
            if let successMessage {
                postFlowNotice(successMessage)
            }
        } catch {
            authError = actionMessage(for: error)
        }
    }

    private func runListingRpc(
        _ listingId: UUID,
        successMessage: String? = nil,
        _ op: () async throws -> Void
    ) async {
        guard !listingActionIds.contains(listingId) else { return }
        listingActionIds.insert(listingId)
        defer { listingActionIds.remove(listingId) }
        await runRpc(successMessage: successMessage, op)
    }

    private func clearLocalState() {
        // Unregister device token before signing out
        if let token = pushNotificationManager.deviceToken {
            Task {
                await pushNotificationManager.unregisterToken(token, supabaseClient: supabase)
            }
        }

        session = nil
        userStats = nil
        achievements = []
        achievementProgress = []
        listings = []
        ratings = []
        reports = []
        profilesById = [:]
        flowNotice = nil
        selectedTab = .map
        createListingPrefill = nil
    }

    // MARK: - Gamification

    private func loadGamificationData(userId: String) async {
        guard let service = gamificationService else { return }

        // Load stats
        Task.detached { [weak self] in
            do {
                let stats = try await service.getUserStats(userId: userId)
                await MainActor.run {
                    self?.userStats = stats
                }
            } catch {
                print("Failed to load user stats: \(error)")
            }
        }

        // Load achievements
        Task.detached { [weak self] in
            do {
                let achievements = try await service.getUserAchievements(userId: userId)
                let progress = try await service.getAchievementProgress(userId: userId)
                await MainActor.run {
                    self?.achievements = achievements
                    self?.achievementProgress = progress
                }
            } catch {
                print("Failed to load achievements: \(error)")
            }
        }
    }

    func refreshGamificationData() async {
        guard let userId = session?.id else { return }
        await loadGamificationData(userId: userId)
    }

    func awardPoints(points: Int, reason: String) async {
        guard let userId = session?.id, let service = gamificationService else { return }
        await service.awardPoints(userId: userId, points: points, reason: reason)
    }

    private func actionMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if isSupabaseSchemaMismatchError(message) || message.contains("function public.") || message.contains("could not find the function") {
            return String(
                localized: "The app and Supabase schema are out of sync. Apply the latest migrations to the Supabase project used by the app, then try again."
            )
        }
        if message.contains("column") && message.contains("moderator_request_status") {
            return String(
                localized: "The Supabase database is missing the moderator request schema. Apply the latest migrations, then reopen the app."
            )
        }
        if message.contains("cannot claim listing") {
            return String(localized: "This listing could not be claimed. It may already be pending pickup, removed, or be your own listing.")
        }
        if message.contains("cannot collect") {
            return String(localized: "Your account is not currently allowed to claim listings. Enable the receiver role in Profile and try again.")
        }
        if message.contains("cannot mark picked up") {
            return String(localized: "Only the receiver on a pending pickup listing can mark it as done.")
        }
        if message.contains("cannot confirm pickup") {
            return String(localized: "This listing could not be completed from the current account.")
        }
        if message.contains("cannot release claim") {
            return String(localized: "Only the giver or receiver on this listing can make it available again.")
        }
        return error.localizedDescription
    }

    private func isSchemaCacheAvailabilityError(_ message: String) -> Bool {
        message.contains("schema cache")
            || message.contains("could not find the table")
            || message.contains("could not find the relation")
    }

    private func isMissingListingLifecycleColumnError(_ message: String) -> Bool {
        guard message.contains("column") else { return false }
        return message.contains("moderation_reason")
            || message.contains("picked_up_at")
            || message.contains("giver_confirmed_at")
    }

    private func isSupabaseSchemaMismatchError(_ message: String) -> Bool {
        isSchemaCacheAvailabilityError(message) || isMissingListingLifecycleColumnError(message)
    }

    private func isOpenStatus(_ status: ListingStatus) -> Bool {
        status == .available || status == .pendingPickup
    }

    private func shouldShowInOpenFlow(_ listing: Listing, for userId: String?) -> Bool {
        guard isOpenStatus(listing.status) else { return false }

        switch listing.status {
        case .available:
            return true
        case .pendingPickup:
            guard let userId else { return false }
            return listing.giverId == userId || listing.collectorId == userId
        case .completed, .removed:
            return false
        }
    }

    private func postFlowNotice(_ message: String) {
        flowNoticeSequence += 1
        let sequence = flowNoticeSequence
        flowNotice = message

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                guard flowNoticeSequence == sequence else { return }
                flowNotice = nil
            }
        }
    }

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
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
