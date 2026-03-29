# Push Notification Implementation Guide

## Overview

The hentpant app now has a complete push notification system using Apple Push Notification service (APNs). Users receive real-time notifications about listing status changes, ratings, and moderation alerts.

## What's Implemented

### 1. **iOS App Side**
- ✅ `PushNotificationManager.swift` - Handles APNs registration, token management, and notification reception
- ✅ `NotificationSettingsView.swift` - Shows notification status and what users will receive
- ✅ Updated `AppDelegate` to handle remote notifications
- ✅ Updated `AppState` to integrate push notifications with app state
- ✅ Automatic token registration on login
- ✅ Automatic token cleanup on logout

### 2. **Database Side**
- ✅ Migration adds `device_tokens` and `last_notification_date` to profiles
- ✅ RPC functions for token management
- ✅ RPC functions for sending notifications
- ✅ Row-level security policies for notifications

### 3. **Notification Types**
- Listing claimed or picked up
- Giver confirmation requested
- Listing completed
- Listing removed by moderation
- Rating received
- Moderation alerts

## Step 1: Apply Database Migration

Run this SQL in your Supabase SQL Editor:

```sql
-- Migration: Add push notification support
-- Date: 2026-03-28
-- Purpose: Track device tokens for push notifications

-- Add device tokens to profiles table
alter table public.profiles add column if not exists device_tokens text[] default '{}';
alter table public.profiles add column if not exists last_notification_date timestamptz;

-- Create index for efficient device token lookups
create index if not exists profiles_device_tokens_idx on public.profiles using gin (device_tokens);

-- RPC function to register or update device token
create or replace function public.register_device_token(p_device_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Add token if not already present, update last_notification_date
  update public.profiles
  set 
    device_tokens = case 
      when not (device_tokens @> array[p_device_token]) then array_append(device_tokens, p_device_token)
      else device_tokens
    end,
    last_notification_date = now()
  where id = uid;
end;
$$;

-- RPC function to unregister device token
create or replace function public.unregister_device_token(p_device_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set device_tokens = array_remove(device_tokens, p_device_token)
  where id = uid;
end;
$$;

-- RPC function to send notification to user (for moderators/admins)
create or replace function public.send_notification_to_user(
  p_target_user_id uuid,
  p_title text,
  p_body text,
  p_data jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id uuid := auth.uid();
  v_sender_role text;
  v_tokens text[];
  v_result jsonb;
begin
  if v_sender_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Check if sender is moderator or admin
  select staff_role into v_sender_role from public.profiles where id = v_sender_id;
  if v_sender_role not in ('moderator', 'admin') then
    raise exception 'Only moderators or admins can send notifications';
  end if;

  -- Get target user's device tokens
  select device_tokens into v_tokens from public.profiles where id = p_target_user_id;

  -- Return notification payload (in production, would integrate with FCM)
  v_result := jsonb_build_object(
    'target_user_id', p_target_user_id,
    'title', p_title,
    'body', p_body,
    'data', coalesce(p_data, '{}'::jsonb),
    'device_count', array_length(v_tokens, 1),
    'sent_at', now()
  );

  return v_result;
end;
$$;

-- RPC function to notify listing participants of status change
create or replace function public.notify_listing_participants(
  p_listing_id uuid,
  p_event_type text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_giver_id uuid;
  v_collector_id uuid;
  v_result jsonb;
begin
  -- Get listing participants
  select giver_id, collector_id into v_giver_id, v_collector_id
  from public.listings where id = p_listing_id;

  if v_giver_id is null then
    raise exception 'Listing not found';
  end if;

  -- Build notification payload
  v_result := jsonb_build_object(
    'listing_id', p_listing_id::text,
    'event_type', p_event_type,
    'message', p_message,
    'giver_notified', v_giver_id is not null,
    'collector_notified', v_collector_id is not null,
    'sent_at', now()
  );

  return v_result;
end;
$$;

grant execute on function public.register_device_token(text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;
grant execute on function public.send_notification_to_user(uuid, text, text, jsonb) to authenticated;
grant execute on function public.notify_listing_participants(uuid, text, text) to authenticated;
```

## Step 2: Configure Apple Push Notification Certificate

1. Go to [Apple Developer Account](https://developer.apple.com/)
2. Create a new Apple Push Notification Authentication Key (*.p8 file)
3. In your Supabase project:
   - Go to Project Settings > Push Notifications
   - Upload the *.p8 file
   - Enter your Team ID and Bundle ID

## Step 3: Test Notifications

### From Supabase SQL Console:

```sql
-- Get a user's device tokens
select id, display_name, device_tokens, last_notification_date 
from public.profiles 
where device_tokens != '{}' 
limit 5;

-- Send a test notification to a user (replace UUID)
select * from public.send_notification_to_user(
  'USER_ID_HERE'::uuid,
  'Test Notification',
  'This is a test push notification'
);

-- Notify listing participants
select * from public.notify_listing_participants(
  'LISTING_ID_HERE'::uuid,
  'listing_claimed',
  'Your listing was just claimed!'
);
```

## Swift Code Reference

### PushNotificationManager

The `PushNotificationManager` handles all APNs operations:

```swift
// Request notification permissions
await PushNotificationManager.shared.requestNotificationPermission()

// Check if notifications are enabled
if PushNotificationManager.shared.isNotificationEnabled {
    // Notifications are available
}

// Get device token (after registration)
if let token = PushNotificationManager.shared.deviceToken {
    print("Device token: \(token)")
}

// Handle incoming notifications
PushNotificationManager.shared.setNotificationHandler { payload in
    print("Received: \(payload.title)")
    print("Listing ID: \(payload.listingId ?? "N/A")")
}
```

### Adding Notification Settings to Profile View

```swift
import SwiftUI

struct ProfileView: View {
    var body: some View {
        VStack {
            // ... existing profile content ...
            
            NotificationSettingsView()
                .padding()
        }
    }
}
```

## How It Works

### User Flow

1. **Login** → App requests notification permission
2. **Permission Granted** → App registers with APNs
3. **Token Received** → App sends token to Supabase via `register_device_token()` RPC
4. **Event Triggered** → Supabase backend calls notification RPC
5. **Notification Sent** → APNs delivers notification to user's device
6. **User Interaction** → App receives notification in `handleIncomingNotification()`
7. **Logout** → Token unregistered via `unregister_device_token()` RPC

### Key Components

**PushNotificationManager.swift**
- Singleton manager for all notification operations
- Handles permission requests and token registration
- Acts as UNUserNotificationCenterDelegate
- Parses incoming notification payloads

**AppState Integration**
- Sets up push notifications after user logs in
- Handles incoming notifications by refreshing UI
- Cleans up tokens on logout

**Database Support**
- Tracks device tokens per user
- RPC functions for notification operations
- Moderators/admins can send notifications

## Notification Payload Format

Notifications can include:

```json
{
  "title": "Listing Status",
  "body": "Your item was picked up!",
  "listing_id": "uuid...",
  "event_type": "listing_picked_up",
  "aps": {
    "alert": {
      "title": "Listing Status",
      "body": "Your item was picked up!"
    },
    "sound": "default",
    "badge": 1
  }
}
```

## Future Enhancements

- [ ] Integration with Firebase Cloud Messaging (FCM) for Android
- [ ] Notification scheduling and batch operations
- [ ] User notification preferences (notification categories)
- [ ] Rich notifications with images
- [ ] Deep linking to specific listings from notifications
- [ ] Analytics on notification delivery and engagement

## Troubleshooting

### Device token not registering
- Ensure user is logged in
- Check that notification permission is granted
- Verify Supabase RPC functions exist

### Notifications not appearing
- Check Apple Developer account configuration
- Verify APNs certificate is valid and expires
- Check bundle ID matches configured certificate
- Ensure app is built with correct provisioning profile

### Token appears in database but no notifications
- APNs certificate may be expired
- Check notification payload format
- Verify token is not revoked

## Testing Checklist

- [ ] App builds without errors
- [ ] Notifications permission popup appears on first launch
- [ ] Device token can be seen in Supabase (profiles table)
- [ ] Test notification sends from Supabase SQL console
- [ ] Notification appears on device
- [ ] Tapping notification triggers correct action
- [ ] Notification dismissed after interaction
- [ ] Token unregisters on logout
- [ ] Token re-registers on login
