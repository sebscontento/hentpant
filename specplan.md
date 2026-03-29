# PantCollect — Specification & Architecture Plan

This document describes the **product**, **features**, and **technical architecture** of **PantCollect** (Xcode project: `hentpant`). It reflects the current SwiftUI implementation and the intended production backend.

---

## 1. Product overview

**PantCollect** connects people who want to dispose of **pant** (Danish deposit bottles and cans) with people who collect them for recycling value.

- **Givers** post listings with photos, quantity estimate, bag size, and an **approximate** map pin (privacy: not necessarily the exact address).
- **Receivers** browse on a map or list, **claim** a pickup, mark **picked up**, and the **giver confirms** completion.
- **No** home entry or mandatory in-person coordination in scope for MVP; trust is supported via **ratings** and **reporting**.

**Target:** Denmark, iOS first. **MVP:** free, no monetization.

---

## 2. User roles and permissions

Roles combine **giver/receiver flags** on the profile with optional **staff** roles.

| Capability | User | Moderator | Admin |
|------------|------|-----------|-------|
| Post listings (if `canGive`) | ✅ | ✅ | ✅ |
| Claim / collect (if `canReceive`) | ✅ | ✅ | ✅ |
| Remove any listing (moderation) | — | ✅ | ✅ |
| Delete users | — | — | ✅ |
| Promote/demote staff roles | — | — | ✅ |

- A user may be **giver**, **receiver**, or **both** (`canGive` / `canReceive`).
- **Moderators** cannot self-promote to admin in product rules; in production, elevated accounts are created or assigned via backend.
- **Demo accounts** (debug): `mod@demo.pant` / `demo12`, `admin@demo.pant` / `demo12` seed moderator and admin profiles.

---

## 3. Feature specification

### 3.1 Authentication

- **Email/password:** sign up (display name, giver/receiver toggles) and log in; validation and duplicate-email checks.
- **Sign in with Apple:** nonce-based request; new users default to giver + receiver; Apple user id used as stable profile id.
- **Session:** unauthenticated users see auth; authenticated users see main tabs.

### 3.2 Listings

- **Create:** up to **3** photos (PhotosPicker), **quantity** text, **bag size** (small / medium / large), **optional description**, **pin** on MapKit (tap to place; default near user when location is available).
- **Lifecycle status:** `available` → `pending_pickup` (claimed) → `completed` (receiver marks pickup done or giver confirms) or `removed` (moderation).

### 3.3 Discovery

- **Map:** MapKit annotations for open listings; user location (`UserAnnotation`, recenter control); tap annotation → detail sheet.
- **List:** same open listings, sorted by **distance** when location is available, else by **recency**; navigation to detail.

### 3.4 Collection flow

- **Claim:** eligible user sets listing to `pending_pickup` and records `collectorId`.
- **Picked up:** collector can finish the journey by setting `completed` and `pickedUpAt`.
- **Confirm:** giver can also finish the journey by setting `completed` and `giverConfirmedAt`.

### 3.5 Trust and safety

- **Ratings:** after `completed`, each party may rate the other once per listing (1–5 stars, optional comment); profile **average** and **count** update.
- **Reports:** report a **listing** or **user** with a reason (stored in app state; backend persistence planned).

### 3.6 Moderation and admin (in-app)

- **Moderator:** remove listing with optional reason (`removed` + `moderationReason`).
- **Admin:** delete users (and their listing involvement); change **staff role** (user / moderator / admin) for other users via profile UI.

### 3.7 Not yet implemented (planned / README alignment)

- **Remote persistence:** replace in-memory store with **Firebase** (or equivalent): Auth, Firestore, Storage for photos, Cloud Functions, **FCM** push.
- **Push notifications:** e.g. claim and pickup events (no `UserNotifications` wiring in MVP state).
- **Private chat:** explicitly out of MVP; communication via listing state and notifications only.

---

## 4. Architecture

### 4.1 High-level structure

```text
hentpantApp
  └── AppState (@MainActor ObservableObject) — injected as environmentObject
        └── ContentView → RootView
              ├── session == nil → AuthView
              └── session != nil → MainTabView
                    ├── MapBrowseView
                    ├── ListingsListView
                    ├── CreateListingView (if canPostPant)
                    └── ProfileView
```

- **Pattern:** SwiftUI with a central **observable app state** (MVVM-style: views bind to `AppState`, no separate ViewModels per screen required for MVP).
- **Navigation:** `NavigationStack` per tab where needed; map uses **sheet** for listing detail; list uses **NavigationLink** + `NavigationPath`.

### 4.2 Layers

| Layer | Responsibility |
|--------|----------------|
| **Views** | SwiftUI screens under `Views/` (Auth, Map, List, Listing, Profile, Components). |
| **Services** | `AppState` (auth, listings, ratings, reports, admin); `LocationManager` (CoreLocation, ~100 m accuracy). |
| **Models** | Value types: `UserProfile`, `Listing`, `ListingStatus`, `BagSize`, `StaffRole`, `Rating`, `Report`, `ReportTarget`. |

### 4.3 State and data flow

- **`AppState`** holds: `session`, `listings`, `ratings`, `reports`, `profilesById`, `authError`; email auth uses an in-memory `passwordByEmail` map.
- **Threading:** `AppState` and `LocationManager` are `@MainActor`.
- **Persistence:** none on disk; restart clears data except what’s baked into **seed** (demo moderator, admin, one demo listing near Copenhagen).

### 4.4 External capabilities

- **MapKit:** browse map, pin picker on create, small preview on detail.
- **PhotosUI:** multi-select images → `Data` in memory.
- **CoreLocation:** when-in-use authorization for distance sorting and map centering.
- **AuthenticationServices:** Sign in with Apple.
- **Entitlements:** Sign in with Apple capability expected in release builds (see Xcode project).

### 4.5 Future backend mapping (conceptual)

| Client concept | Intended backend |
|----------------|------------------|
| `UserProfile` | Firestore `users` (or Auth + profile doc) |
| `Listing.photoData` | Firebase Storage URLs + metadata in Firestore |
| `Rating`, `Report` | Firestore collections; security rules by role |
| Claim / confirm / moderate | Functions or trusted server logic + FCM for notifications |

---

## 5. Domain model (summary)

- **`UserProfile`:** `id`, `displayName`, `email`, `canGive`, `canReceive`, `staffRole`, `averageRating`, `ratingCount`.
- **`Listing`:** `id`, `giverId`, `photoData[]`, `quantityText`, `bagSize`, lat/lon, `detail`, `status`, `collectorId`, timestamps, `moderationReason`.
- **`ListingStatus`:** `available`, `reserved`, `awaitingGiverConfirmation`, `completed`, `removed`.
- **`Rating`:** per listing, from/to users, stars, optional comment, deduplicated by (listing, from, to).

---

## 6. Technical constraints

- **iOS:** 18+ per README (project may allow slightly lower deployment target; treat README as product target).
- **Localization:** user-facing strings use `String(localized:)` for future translation.
- **Privacy:** UX copy encourages placing the pin away from the exact address; precise address is not a required field.

---

## 7. Repository layout

- **`hentpant/`** — Xcode project `hentpant.xcodeproj`, app sources under `hentpant/hentpant/` (`Models/`, `Services/`, `Views/`).
- **`plan.md`** (repo root) — original product/technical plan; this **`specplan.md`** is the consolidated spec + architecture reference.

---

*Last aligned with codebase: March 2026.*
