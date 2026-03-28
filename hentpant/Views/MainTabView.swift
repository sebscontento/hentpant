//
//  MainTabView.swift
//  hentpant
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            MapBrowseView()
                .tabItem {
                    Label(String(localized: "Map"), systemImage: "map")
                }

            ListingsListView()
                .tabItem {
                    Label(String(localized: "List"), systemImage: "list.bullet")
                }

            if appState.session?.canPostPant == true {
                CreateListingView()
                    .tabItem {
                        Label(String(localized: "Post"), systemImage: "plus.circle.fill")
                    }
            }

            ProfileView()
                .tabItem {
                    Label(String(localized: "Profile"), systemImage: "person.circle")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
