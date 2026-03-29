//
//  hentpantApp.swift
//  hentpant
//
//  Created by Sebastian  on 28/03/2026.
//

import SwiftUI
import FirebaseCore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    
    // Set up push notification delegate
    UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
    
    return true
  }
  
  // Handle remote notification token registration
  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task {
      await PushNotificationManager.shared.handleDeviceToken(deviceToken)
    }
  }
  
  // Handle remote notification registration failure
  func application(_ application: UIApplication,
                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
  }
}

@main
struct hentpantApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
