//
//  PushNotificationManager.swift
//  hentpant
//
//  Manages Apple Push Notification (APNs) registration, token handling,
//  and notification reception for real-time updates on listings and messages
//

import UserNotifications
import UIKit
import Foundation
import Supabase

@MainActor
class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var isNotificationEnabled = false
    @Published var deviceToken: String?
    @Published var lastNotification: UNNotification?
    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    
    static let shared = PushNotificationManager()
    
    private var notificationHandler: ((NotificationPayload) -> Void)?
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Request Notification Permissions
    
    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                self.isNotificationEnabled = granted
                self.notificationPermissionStatus = granted ? .authorized : .denied
            }
            
            if granted {
                await registerForRemoteNotifications()
            }
        } catch {
            print("❌ Notification permission request failed: \(error)")
            await MainActor.run {
                self.isNotificationEnabled = false
                self.notificationPermissionStatus = .denied
            }
        }
    }
    
    // MARK: - Register for Remote Notifications
    
    @MainActor
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    // Called automatically by AppDelegate when APNs token is received
    func handleDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        await MainActor.run {
            self.deviceToken = token
            self.isNotificationEnabled = true
        }
        
        print("✅ Device token registered: \(token)")
    }
    
    // MARK: - Register Token with Backend
    
    func registerTokenWithBackend(_ token: String, supabaseClient: SupabaseClient) async {
        do {
            try await supabaseClient.rpc("register_device_token", params: ["p_device_token": token]).execute()
            print("✅ Device token registered with Supabase")
        } catch {
            print("❌ Failed to register device token with backend: \(error)")
        }
    }
    
    // MARK: - Unregister Token
    
    func unregisterToken(_ token: String, supabaseClient: SupabaseClient) async {
        do {
            try await supabaseClient.rpc("unregister_device_token", params: ["p_device_token": token]).execute()
            print("✅ Device token unregistered from Supabase")
        } catch {
            print("❌ Failed to unregister device token: \(error)")
        }
    }
    
    // MARK: - Notification Handler Registration
    
    func setNotificationHandler(_ handler: @escaping (NotificationPayload) -> Void) {
        self.notificationHandler = handler
    }
    
    // MARK: - UNUserNotificationCenterDelegate Methods
    
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        Task { @MainActor in
            self.lastNotification = notification
            
            if let payload = parseNotificationPayload(userInfo) {
                self.notificationHandler?(payload)
            }
        }
        
        // Show notification banner and sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle user interaction with notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        Task { @MainActor in
            if let payload = parseNotificationPayload(userInfo) {
                self.notificationHandler?(payload)
            }
        }
        
        completionHandler()
    }
    
    // MARK: - Parse Notification Payload
    
    private func parseNotificationPayload(_ userInfo: [AnyHashable: Any]) -> NotificationPayload? {
        // Extract APNs custom data from under "aps" key
        // Firebase typically sends custom data in root or under "gcm." prefix
        
        let title = userInfo["title"] as? String ?? userInfo["aps.alert.title"] as? String ?? "New Update"
        let body = userInfo["body"] as? String ?? userInfo["aps.alert.body"] as? String ?? ""
        let listingId = userInfo["listing_id"] as? String
        let eventType = userInfo["event_type"] as? String ?? "update"
        
        return NotificationPayload(
            title: title,
            body: body,
            listingId: listingId,
            eventType: eventType,
            userInfo: userInfo
        )
    }
}

// MARK: - Notification Payload

struct NotificationPayload {
    let title: String
    let body: String
    let listingId: String?
    let eventType: String
    let userInfo: [AnyHashable: Any]
    
    enum EventType: String {
        case listingClaimed = "listing_claimed"
        case listingPickedUp = "listing_picked_up"
        case confirmationRequested = "confirmation_requested"
        case listingCompleted = "listing_completed"
        case listingRemoved = "listing_removed"
        case ratingReceived = "rating_received"
        case moderationAlert = "moderation_alert"
        case general = "general"
    }
    
    var eventTypeEnum: EventType {
        EventType(rawValue: eventType) ?? .general
    }
}
