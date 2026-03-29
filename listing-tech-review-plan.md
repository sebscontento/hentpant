# Listing Tech Review And Improvement Plan

## Current stack

- iOS app built with SwiftUI.
- Backend uses Supabase Auth, PostgREST RPCs, and Supabase Storage.
- Maps use MapKit.
- Image picking uses PhotosUI.
- Most product state and backend orchestration live inside one `@MainActor` `AppState`.
- Supabase SQL migrations define tables, RPCs, and storage bucket policies.

## What looks good

- The app already has a usable end-to-end listing flow: create, browse, claim, pickup, confirm.
- The backend schema is more mature than the README suggests: listings, ratings, reports, roles, and storage policies exist.
- The model layer is small and understandable.

## Main problems found

### 1. Photo handling is fragile and is the most likely reason images are not showing

Relevant files:

- [CreateListingView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/CreateListingView.swift)
- [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift)
- [ListingsListView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/List/ListingsListView.swift)
- [ListingDetailView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/ListingDetailView.swift)

Observed risks:

- Photo upload uses raw `Data` from `PhotosPicker` and only detects JPEG and PNG.
- Anything else is silently treated as `.jpg` with `image/jpeg`.
- iPhone photos are often HEIC, so the app can upload HEIC bytes with a fake JPEG extension and MIME type.
- The list and detail screens rely on remote `AsyncImage` loading after upload, so a bad upload becomes a missing image.
- Failure states are visually hidden behind generic placeholders, which makes the bug hard to diagnose.

Why this matters:

- This is the strongest code-level explanation for "pictures aren't shown".
- Even if storage permissions are correct, malformed upload metadata can still break preview/rendering.

### 2. Listing creation is split across too many brittle steps

Relevant file:

- [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift)

Current flow:

1. Insert listing with empty `photo_paths`.
2. Upload photos one by one.
3. Call RPC to patch in photo paths.
4. Reload everything.

Risks:

- Partial success is easy: listing created, photo upload fails, listing remains without images.
- There is no rollback if upload fails after the listing row is inserted.
- There is no per-photo error reporting.
- A full app-wide reload is used to refresh one listing.

### 3. `AppState` is doing too much

Relevant file:

- [AppState.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Services/AppState.swift)

It currently owns:

- auth
- profile syncing
- listing CRUD and lifecycle RPCs
- storage uploads
- ratings
- reports
- error messaging
- session hydration

Impact:

- Listing bugs are harder to isolate and test.
- UI refresh logic is tightly coupled to backend details.
- A small storage bug can spill into unrelated screens.

### 4. Architecture docs are out of sync with the actual backend

Relevant files:

- [README.md](/Users/contento/dev/hentminpant/hentpant/README.md)
- [plan.md](/Users/contento/dev/hentminpant/plan.md)
- [specplan.md](/Users/contento/dev/hentminpant/specplan.md)

Notes:

- `README.md` and `plan.md` still describe a Firebase-oriented direction.
- The codebase has already moved to Supabase.
- That mismatch makes maintenance harder and increases the chance of wrong implementation assumptions.

### 5. The image UI has weak observability

Relevant files:

- [ListingsListView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/List/ListingsListView.swift)
- [ListingDetailView.swift](/Users/contento/dev/hentminpant/hentpant/hentpant/Views/Listing/ListingDetailView.swift)

Notes:

- `AsyncImage` failures fall back to generic placeholder art.
- There is no debug logging for generated storage paths or public URLs.
- There is no explicit "image failed to load" state for QA.

## Recommended plan

## Phase 1: Stabilize photos first

Goal: make listing images reliable before broader refactors.

Tasks:

- Normalize all picked images before upload.
- Convert HEIC and other unsupported raw formats into real JPEG data in-app.
- Resize and compress photos before upload to reduce failures and bandwidth.
- Store verified MIME type and extension based on the converted output, not guessed input.
- Add upload/result logging around path creation, upload success, and public URL generation.
- Show a distinct UI state when a remote image fails to load.

Suggested implementation shape:

- Add a small `ListingImageProcessor` service that takes `PhotosPickerItem` data and outputs normalized JPEG bytes.
- Add a `ListingPhotoService` that uploads photos and returns paths/URLs.

## Phase 2: Make listing creation transactional from the app’s point of view

Goal: avoid half-created listings with broken media.

Tasks:

- Move listing creation into a single use-case style flow.
- If any upload fails, either:
  - delete the just-created listing, or
  - keep it as draft/incomplete and do not expose it publicly.
- Return the finished listing instead of calling `loadAllFromRemote()` for everything.
- Surface user-facing errors like "Listing posted, but photo upload failed" separately from auth errors.

## Phase 3: Split `AppState` by responsibility

Goal: reduce coupling and make the listing flow testable.

Suggested split:

- `SessionStore` for auth/session/profile.
- `ListingsRepository` for query + mutation calls.
- `ListingPhotoService` for storage uploads and URL generation.
- `RatingsRepository` and `ReportsRepository` for their own domains.

Benefits:

- Smaller files.
- Easier previews and unit tests.
- Lower chance of regressions when changing listing logic.

## Phase 4: Improve listing read models and UI states

Goal: make failures visible and the UX more resilient.

Tasks:

- Add explicit image state to the listing view models: loading, loaded, failed, empty.
- Consider storing a `primary_photo_url` or derived thumbnail path for simpler list rendering.
- Add retry affordances for failed image loads.
- Avoid hiding broken photos behind the same placeholder used for listings with no photo.

## Phase 5: Clean up project docs and technical direction

Goal: make the repo easier to understand for future work.

Tasks:

- Update `README.md` so it reflects Supabase, not Firebase.
- Replace or archive `plan.md` if it no longer matches the implementation direction.
- Keep one source-of-truth architecture doc.

## Suggested execution order

1. Fix image normalization and upload metadata.
2. Add image failure logging and clearer UI states.
3. Refactor listing creation into a dedicated service/use-case.
4. Split `AppState`.
5. Align docs.

## Concrete first sprint

- Build `ListingImageProcessor` for JPEG normalization.
- Add debug logs for upload path, MIME type, and generated public URL.
- Refactor `createListing(...)` so photo upload failures produce actionable errors.
- Add a small QA checklist:
  - upload from camera roll
  - upload HEIC photo from iPhone
  - upload 3 photos
  - create listing on slow network
  - verify list thumbnail
  - verify detail carousel

## Bottom line

The stack itself is workable for an MVP. The main issue is not SwiftUI or Supabase as choices, but that the listing flow is too tightly coupled and the image pipeline is under-specified. Fixing photo normalization and separating storage logic from `AppState` should give the biggest reliability win fastest.
