//
//  hentpantApp.swift
//  hentpant
//
//  Created by Sebastian  on 28/03/2026.
//

import SwiftUI

@main
struct hentpantApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
