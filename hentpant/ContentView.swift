//
//  ContentView.swift
//  hentpant
//
//  Created by Sebastian  on 28/03/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(skipAuthListener: true))
}
