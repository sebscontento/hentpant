# PantCollect – iOS App Plan

## 1. Overview
**PantCollect** connects people who want to get rid of their pant (deposit bottles/cans) with those who collect them.  
Givers post a photo, quantity estimate, and location of a bag left outside. Collectors see available listings on a map, pick up the bag, and confirm collection.  
No home entry, no mandatory meetups – just a simple, trust‑based exchange.

**Target:** Denmark (iOS only initially)  
**MVP:** Free, no monetization  
**Tech:** SwiftUI, Firebase (Auth, Firestore, Storage, Cloud Functions)

---

## 2. User Roles & Permissions

| Role         | Can post pant | Can claim/collect | Can delete others' posts | Can delete users | Can promote/demote |
|--------------|---------------|-------------------|--------------------------|------------------|-------------------|
| Pant Giver   | ✅             | ✅ (if also receiver) | ❌                       | ❌               | ❌                |
| Pant Receiver| ✅ (if also giver) | ✅             | ❌                       | ❌               | ❌                |
| Moderator    | ✅             | ✅                 | ✅ (any post)            | ❌               | ❌                |
| Admin        | ✅             | ✅                 | ✅ (any post)            | ✅               | ✅                |

- A user can be **both** giver and receiver – roles are flags in the user profile.
- Moderators cannot be admins (enforced in app logic / Firebase rules).
- Admins and moderators can also participate as givers/receivers.

---

## 3. Core Features (MVP)

### Authentication
- Sign up / log in with **Apple ID** or **email/password**.
- Required fields: display name, email, role selection at signup (giver / receiver / both).
- Admin accounts are created manually in the backend (Firebase console or a protected function).

### Post a Pant Listing
- **Photo** – take or upload from gallery (max 3 images).
- **Quantity estimate** – e.g., “~20 bottles” or bag size (small/medium/large).
- **Location** – user drops a pin on map (not exact address, to preserve privacy). Geocoding stores coordinates.
- **Optional description** – e.g., “left next to the green bench”.
- **Status** – initially “available”.

### Map & Listings
- **MapKit** view showing all available posts as pins.
- Tap a pin to see details (photo, quantity, distance, time ago).
- **List view** alternative for accessibility.

### Claim a Listing
- Collector taps **“I’ll collect this”**.
- Listing status changes to “reserved” – other users see it as claimed and cannot claim it.
- Push notification sent to the giver that someone is coming.

### Confirm Collection
- Collector marks **“Picked up”** (after physically picking the bag).
- Giver receives a notification and can **confirm** that the bag is gone.
- Once giver confirms, listing is removed and both users get a **completed** status.

### Rating & Trust
- After completion, both users can rate each other (1–5 stars) with a short comment.
- Ratings affect user reputation displayed on profile.

### Moderation Tools
- Moderators can delete any listing (with a reason).
- Admins can delete users and change roles.

### Privacy & Safety
- Locations are approximate (user can adjust pin to avoid exact home address).
- No private chat in MVP – all communication is via listing updates and notifications.
- In‑app reporting button for listings or users.

---

## 4. Technical Architecture

### Frontend – iOS (SwiftUI)
- iOS 16+ (to use latest SwiftUI features).
- MVVM pattern with `@StateObject`, `@ObservableObject`.
- **MapKit** for maps.
- **PhotosUI** for image picking.
- **UserNotifications** for push.

### Backend – Firebase
- **Authentication**: FirebaseAuth (Apple & email/password).
- **Firestore Database**: Stores users, listings, ratings, roles.
- **Firebase Storage**: Stores listing photos.
- **Cloud Functions**: For role validation, automatic cleanup of stale listings, and sending push notifications via FCM.

### Data Model (Firestore)

#### Users collection