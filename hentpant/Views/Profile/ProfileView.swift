//
//  ProfileView.swift
//  hentpant
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState

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
                    }

                    Section {
                        Button(String(localized: "Sign out"), role: .destructive) {
                            appState.signOut()
                        }
                    }

                    if user.canPromoteRoles {
                        Section(String(localized: "Admin")) {
                            ForEach(Array(appState.profilesById.keys).sorted(), id: \.self) { uid in
                                if let p = appState.profilesById[uid], uid != user.id {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(p.displayName)
                                            Text(p.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Menu(p.staffRole.rawValue) {
                                            Button(String(localized: "User")) {
                                                appState.setStaffRole(uid, role: .user)
                                            }
                                            Button(String(localized: "Moderator")) {
                                                appState.setStaffRole(uid, role: .moderator)
                                            }
                                            Button(String(localized: "Admin")) {
                                                appState.setStaffRole(uid, role: .admin)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if user.canDeleteUsers {
                        Section(String(localized: "Delete users")) {
                            ForEach(Array(appState.profilesById.keys).sorted(), id: \.self) { uid in
                                if let p = appState.profilesById[uid], uid != user.id {
                                    Button(role: .destructive) {
                                        appState.deleteUser(uid)
                                    } label: {
                                        Text(String(localized: "Delete \(p.displayName)"))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Profile"))
        }
    }

    private func roleLine(_ user: UserProfile) -> String {
        switch user.staffRole {
        case .user:
            return String(localized: "Standard account")
        case .moderator:
            return String(localized: "Moderator — can remove any listing")
        case .admin:
            return String(localized: "Admin — can delete users and assign roles")
        }
    }

    private func giverReceiverLine(_ user: UserProfile) -> String {
        var parts: [String] = []
        if user.canGive { parts.append(String(localized: "Giver")) }
        if user.canReceive { parts.append(String(localized: "Receiver")) }
        return parts.isEmpty ? String(localized: "None") : parts.joined(separator: " · ")
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
