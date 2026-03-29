//
//  ProfileView.swift
//  hentpant
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var canGive = false
    @State private var canReceive = false

    var body: some View {
        NavigationStack {
            List {
                if let user = appState.session {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.displayName)
                                .font(.title2.weight(.semibold))
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(roleLine(user))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        LabeledContent(String(localized: "Reputation")) {
                            if user.ratingCount == 0 {
                                Text(String(localized: "No ratings yet"))
                            } else {
                                Text(String(format: String(localized: "%.1f ★ (%lld)"), user.averageRating, user.ratingCount))
                            }
                        }

                        LabeledContent(String(localized: "Roles")) {
                            Text(giverReceiverLine(user))
                                .multilineTextAlignment(.trailing)
                        }

                        LabeledContent(String(localized: "Moderator request")) {
                            Text(moderatorRequestLine(user))
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    // MARK: - Points & Level
                    if let stats = appState.userStats {
                        Section {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(String(localized: "Total Points"), systemImage: "star.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("\(stats.points) pts")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.yellow)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Label(String(localized: "Level"), systemImage: "chart.bar.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("\(stats.levelTitle) (Lvl \(stats.level))")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 6)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(String(localized: "Progress to next level"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(stats.points) / \(stats.nextLevelPoints) pts")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(stats.progressToNextLevel))
                                    .tint(.yellow)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "How to earn points"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                pointRow(icon: "plus.circle.fill", color: .green,
                                         label: "Post a listing", points: "+10 pts")
                                pointRow(icon: "checkmark.circle.fill", color: .blue,
                                         label: "Confirm a pickup (giver)", points: "+25 pts")
                                pointRow(icon: "bag.fill", color: .orange,
                                         label: "Pick up an item (collector)", points: "+50 pts")
                                pointRow(icon: "star.fill", color: .mint,
                                         label: "Leave a review", points: "+10 pts")
                                pointRow(icon: "trophy.fill", color: .yellow,
                                         label: "Unlock achievements", points: "varies")
                            }
                            .padding(.top, 4)
                        } header: {
                            Text(String(localized: "Points & Level"))
                        }
                    }

                    Section(String(localized: "What you can do now")) {
                        capabilityRow(
                            title: String(localized: "Post listings"),
                            isEnabled: user.canPostPant,
                            detail: user.canPostPant
                                ? String(localized: "The Give Away tab is available for new listings.")
                                : String(localized: "Turn on the giver role below to create listings.")
                        )
                        capabilityRow(
                            title: String(localized: "Claim listings"),
                            isEnabled: user.canClaimPant,
                            detail: user.canClaimPant
                                ? String(localized: "Map and List screens can claim items.")
                                : String(localized: "Turn on the receiver role below to claim items.")
                        )
                        capabilityRow(
                            title: String(localized: "Moderate listings"),
                            isEnabled: user.canDeleteAnyListing,
                            detail: user.canDeleteAnyListing
                                ? String(localized: "You can remove listings from detail screens.")
                                : String(localized: "Moderation tools appear only for moderators and admins.")
                        )
                    }

                    Section {
                        Toggle(String(localized: "I give away items"), isOn: $canGive)
                        Toggle(String(localized: "I claim items"), isOn: $canReceive)

                        if !roleSelectionIsValid {
                            Label(
                                String(localized: "Choose at least one role to stay active in the app."),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }

                        Button(String(localized: "Save participation roles")) {
                            Task { await appState.updateParticipationRoles(canGive: canGive, canReceive: canReceive) }
                        }
                        .disabled(!roleSelectionIsValid || !roleSelectionChanged(from: user))
                    } header: {
                        Text(String(localized: "Participation"))
                    } footer: {
                        Text(String(localized: "You can be a giver, a receiver, or both, but at least one role must stay enabled."))
                    }

                    if user.canApplyForModerator {
                        Section {
                            Button(String(localized: "Apply to become a moderator")) {
                                Task { await appState.applyForModerator() }
                            }
                        } header: {
                            Text(String(localized: "Moderator"))
                        } footer: {
                            Text(String(localized: "Admins review moderator applications before granting access."))
                        }
                    } else if user.moderatorRequestStatus.isPending {
                        Section(String(localized: "Moderator")) {
                            Text(String(localized: "Your moderator application is pending admin review."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button(String(localized: "Sign out"), role: .destructive) {
                            Task { await appState.signOut() }
                        }
                    }

                    if user.canPromoteRoles {
                        if !pendingModeratorApplications(currentUserId: user.id).isEmpty {
                            Section(String(localized: "Moderator applications")) {
                                ForEach(pendingModeratorApplications(currentUserId: user.id), id: \.id) { profile in
                                    VStack(alignment: .leading, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.displayName)
                                            Text(profile.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        HStack {
                                            Button(String(localized: "Approve")) {
                                                Task { await appState.reviewModeratorApplication(profile.id, approve: true) }
                                            }
                                            .buttonStyle(.borderedProminent)

                                            Button(String(localized: "Reject"), role: .destructive) {
                                                Task { await appState.reviewModeratorApplication(profile.id, approve: false) }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Section(String(localized: "Admin")) {
                            ForEach(adminManagedProfiles(currentUserId: user.id), id: \.id) { p in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(p.displayName)
                                        Text(p.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(adminSubtitle(for: p))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu(p.staffRole.rawValue) {
                                        Button(String(localized: "User")) {
                                            Task { await appState.setStaffRole(p.id, role: .user) }
                                        }
                                        Button(String(localized: "Moderator")) {
                                            Task { await appState.setStaffRole(p.id, role: .moderator) }
                                        }
                                        Button(String(localized: "Admin")) {
                                            Task { await appState.setStaffRole(p.id, role: .admin) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if user.canDeleteUsers {
                        Section(String(localized: "User deletion")) {
                            Text(
                                String(
                                    localized: "Deleting users is disabled in the app for now. Use the Supabase Dashboard until a supported backend flow is added."
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Profile"))
            .onAppear {
                syncRoleToggles()
                Task { await appState.refreshGamificationData() }
            }
            .onChange(of: appState.session) { _, _ in
                syncRoleToggles()
            }
        }
    }

    private var sortedProfiles: [UserProfile] {
        appState.profilesById.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func adminManagedProfiles(currentUserId: String) -> [UserProfile] {
        sortedProfiles.filter { $0.id != currentUserId }
    }

    private func pendingModeratorApplications(currentUserId: String) -> [UserProfile] {
        adminManagedProfiles(currentUserId: currentUserId).filter { $0.moderatorRequestStatus.isPending }
    }

    private func roleLine(_ user: UserProfile) -> String {
        switch user.staffRole {
        case .user:
            return String(localized: "Standard account")
        case .moderator:
            return String(localized: "Moderator - can remove any listing")
        case .admin:
            return String(localized: "Admin - can assign roles and review moderator requests")
        }
    }

    private func giverReceiverLine(_ user: UserProfile) -> String {
        var parts: [String] = []
        if user.canGive { parts.append(String(localized: "Giver")) }
        if user.canReceive { parts.append(String(localized: "Receiver")) }
        return parts.isEmpty ? String(localized: "None") : parts.joined(separator: " · ")
    }

    private func moderatorRequestLine(_ user: UserProfile) -> String {
        switch user.staffRole {
        case .moderator:
            return String(localized: "Approved moderator")
        case .admin:
            return String(localized: "Admin access")
        case .user:
            switch user.moderatorRequestStatus {
            case .none:
                return String(localized: "Not requested")
            case .pending:
                return String(localized: "Pending review")
            case .rejected:
                return String(localized: "Rejected")
            }
        }
    }

    private func adminSubtitle(for user: UserProfile) -> String {
        let participation = giverReceiverLine(user)
        if user.moderatorRequestStatus.isPending && user.staffRole == .user {
            return participation + " · " + String(localized: "Moderator request pending")
        }
        return participation
    }

    private var roleSelectionIsValid: Bool {
        canGive || canReceive
    }

    private func roleSelectionChanged(from user: UserProfile) -> Bool {
        canGive != user.canGive || canReceive != user.canReceive
    }

    @ViewBuilder
    private func pointRow(icon: String, color: Color, label: String, points: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
            Spacer()
            Text(points)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func capabilityRow(title: String, isEnabled: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? .green : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func syncRoleToggles() {
        canGive = appState.session?.canGive ?? false
        canReceive = appState.session?.canReceive ?? false
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState(skipAuthListener: true))
}
