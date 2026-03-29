# Bug Audit Report

Date: 2026-03-28

## What I tested

- Built the iOS app with `xcodebuild -project hentpant/hentpant.xcodeproj -scheme hentpant -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
- Launched the built app in the iOS 18 simulator
- Reviewed the SwiftUI flows for auth, listings, map, create listing, and profile/admin
- Compared the app code against the Supabase migrations

## Summary

The project compiles, but there are several high-impact runtime and product bugs. The biggest problems are incorrect default location behavior during listing creation, brittle listing creation with no rollback, and admin/user-management flows that are exposed in the UI even though the backend path is likely to fail in hosted Supabase.

There is also no automated test target in the Xcode project, so none of these paths are being regression-tested right now.

## Findings

### 1. New listings can be posted at the wrong location

Severity: High

Why this is a bug:

- The create-listing screen starts with a hard-coded Copenhagen coordinate.
- It only replaces that coordinate during `.onAppear` if `location.lastLocation` is already available.
- On a real device, location often arrives after `.onAppear`, so the pin can stay in Copenhagen unless the user manually notices and moves it.

Evidence:

- Default pin and camera are hard-coded to Copenhagen in [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift#L21) and [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift#L24).
- The only auto-update happens once in `.onAppear` in [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift#L91).
- The submitted listing uses whatever pin value is currently stored in [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift#L154).

User impact:

- People outside Copenhagen can accidentally publish pickups in the wrong city.

### 2. Listing creation is non-transactional and leaves broken partial state

Severity: High

Why this is a bug:

- The app inserts the listing row first, then uploads photos, then patches `photo_paths`.
- If upload or the patch RPC fails, the listing row has already been created.
- The error shown to the user expglicitly admits the listing may already exist, but the app does not clean it up or mark it incomplete.

Evidence:

- Listing row is inserted before uploads in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L225).
- Upload happens as a second step in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L236).
- `photo_paths` are patched in a third step in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L238).
- The user-facing error says the listing was created even when photos failed in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L569).

User impact:

- Users can end up with public listings that have no photos or incomplete media after an upload failure.

### 3. Admin “Delete user” is wired to a backend path that is likely to fail on hosted Supabase

Severity: High

Why this is a bug:

- The admin UI exposes destructive user deletion.
- The app calls an RPC that directly deletes from `auth.users`.
- Hosted Supabase commonly blocks or complicates direct SQL deletion from `auth.users`; your own docs already warn this may fail at runtime.

Evidence:

- The destructive UI is exposed in [ProfileView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Profile/ProfileView.swift#L144).
- The app calls `admin_delete_user` in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L287).
- The SQL function directly runs `delete from auth.users` in [20250328120000_initial_schema.sql](/Users/contento/dev/hentminpant/supabase/migrations/20250328120000_initial_schema.sql#L361).
- The repo documentation explicitly says this can fail at runtime in [SUPABASE.md](/Users/contento/dev/hentminpant/SUPABASE.md).

User impact:

- Admins are offered a feature that may not work in production and can fail only after a destructive action is attempted.

### 4. Sign-up duplicates profile creation logic that the database already performs

Severity: Medium

Why this is a bug:

- The database trigger already creates a `profiles` row for every new auth user.
- The app still performs a read-then-insert fallback after sign-up.
- If the read fails for a transient reason, the app can try to create a duplicate profile and turn a successful sign-up into an app-level error.

Evidence:

- The DB trigger inserts into `public.profiles` automatically in [20250328120000_initial_schema.sql](/Users/contento/dev/hentminpant/supabase/migrations/20250328120000_initial_schema.sql#L23).
- The app still calls `ensureProfileExists` after sign-up in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L69).
- That fallback inserts a profile row again in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L463).

User impact:

- Intermittent sign-up failures can happen even when auth succeeded.

### 5. The app advertises report support, but reports are never loaded into app state

Severity: Medium

Why this is a bug:

- `reports` exists as published state, and users can submit reports.
- `loadAllFromRemote()` fetches profiles, listings, and ratings, but never fetches reports.
- That means any future or intended moderation/report UI will always have stale or empty local data.

Evidence:

- Reports state exists in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L19).
- Reports can be submitted in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L351).
- `loadAllFromRemote()` never loads `reports` in [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift#L525).

User impact:

- Reporting is write-only from the app’s perspective.

### 6. Location updates are started in multiple screens and never stopped

Severity: Medium

Why this is a bug:

- `LocationManager.start()` is called in the list, map, and create-listing screens.
- None of those views stop updates when they disappear.
- This can waste battery and keep location work active longer than necessary.

Evidence:

- List screen starts updates in [ListingsListView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/List/ListingsListView.swift#L35).
- Map screen starts updates in [MapBrowseView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Map/MapBrowseView.swift#L46).
- Create screen starts updates in [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift#L91).
- `LocationManager` exposes `stop()` but none of these views call it in [LocationManager.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/LocationManager.swift).

User impact:

- Unnecessary location polling and battery drain.

### 7. The app does not have an automated test target

Severity: Medium

Why this is a bug:

- There is only one application target in the Xcode project and no test target.
- `xcodebuild -list` also reported only the `hentpant` scheme/target.

Evidence:

- Only the app target is defined in [project.pbxproj](/Users/contento/dev/hentminpant/hentpant/hentpant.xcodeproj/project.pbxproj#L55).
- The project target list contains only `hentpant` in [project.pbxproj](/Users/contento/dev/hentminpant/hentpant/hentpant.xcodeproj/project.pbxproj#L110).

User impact:

- Bugs in sign-up, listing creation, RPC actions, and location flows can regress without detection.

## Verification notes

- Build status: passed
- Simulator launch: passed
- Runtime observation: the app launches, but the main issues are logic and backend-contract bugs rather than compile errors

## Recommended fix order

1. Fix create-listing location initialization so the pin updates when the real location arrives.
2. Make listing creation transactional from the app’s point of view, including cleanup on upload failure.
3. Remove or replace the current admin-delete-user flow with a supported backend path.
4. Delete the duplicate profile-creation fallback or make it idempotent.
5. Add at least one test target and cover auth, listing creation, and RPC error handling.
