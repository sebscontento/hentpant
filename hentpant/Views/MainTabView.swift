//
//  MainTabView.swift
//  hentpant
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            MapBrowseView()
                .tag(AppTab.map)
                .tabItem {
                    Label(String(localized: "Map"), systemImage: "map")
                }
                .badge(appState.availableListings().count)

            ListingsListView()
                .tag(AppTab.list)
                .tabItem {
                    Label(String(localized: "List"), systemImage: "list.bullet")
                }
                .badge(appState.availableListings().count)

            if appState.session?.canPostPant == true {
                CreateListingView()
                    .tag(AppTab.create)
                    .tabItem {
                        Label(String(localized: "Give Away"), systemImage: "plus.circle.fill")
                    }
            }

            ProfileView()
                .tag(AppTab.profile)
                .tabItem {
                    Label(String(localized: "Profile"), systemImage: "person.circle")
                }
        }
        .onChange(of: appState.session?.canPostPant) { _, canPostPant in
            if canPostPant != true && appState.selectedTab == .create {
                appState.selectedTab = .map
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let flowNotice = appState.flowNotice {
                FlowNoticeBanner(message: flowNotice) {
                    appState.clearFlowNotice()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            if let authError = appState.authError, authError.contains("temporarily") || authError.contains("Note:") {
                FlowNoticeBanner(message: authError) {
                    appState.clearAuthError()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(
                get: { appState.authError != nil && !appState.authError!.contains("temporarily") && !appState.authError!.contains("Note:") },
                set: { isPresented in
                    if !isPresented {
                        appState.clearAuthError()
                    }
                }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                appState.clearAuthError()
            }
        } message: {
            Text(appState.authError ?? "")
        }
    }
}

private struct FlowNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .padding(6)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss message"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState(skipAuthListener: true))
}
