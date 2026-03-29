//
//  RootView.swift
//  hentpant
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.session != nil {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: appState.session?.id)
        .task {
            await appState.refresh()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState(skipAuthListener: true))
}
