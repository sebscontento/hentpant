//
//  NotificationSettingsView.swift
//  hentpant
//
//  Shows notification permission status and settings
//

import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationManager = PushNotificationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Push Notifications")
                        .font(.headline)
                    
                    if notificationManager.isNotificationEnabled {
                        Badge(text: "Enabled", style: .success)
                    } else {
                        Badge(text: "Disabled", style: .warning)
                    }
                }
                
                Spacer()
                
                if let token = notificationManager.deviceToken {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Device Registered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(token.prefix(16) + "...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("You'll receive notifications about:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                NotificationTypeItem(
                    icon: "tag.fill",
                    title: "Listing Updates",
                    description: "When someone claims or picks up your item"
                )
                
                NotificationTypeItem(
                    icon: "star.fill",
                    title: "Ratings",
                    description: "When you receive a rating from another user"
                )
                
                NotificationTypeItem(
                    icon: "shield.fill",
                    title: "Moderation Notices",
                    description: "Important updates from moderators"
                )
            }
        }
        .padding()
    }
}

struct NotificationTypeItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

/// Simple badge component for notification status
struct Badge: View {
    let text: String
    let style: BadgeStyle
    
    enum BadgeStyle {
        case success
        case warning
        case info
    }
    
    var backgroundColor: Color {
        switch style {
        case .success:
            return Color.green.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.2)
        case .info:
            return Color.blue.opacity(0.2)
        }
    }
    
    var foregroundColor: Color {
        switch style {
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .info:
            return Color.blue
        }
    }
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .cornerRadius(4)
    }
}

#Preview {
    NotificationSettingsView()
}
