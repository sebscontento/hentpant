# Gamification System

The hentpant gamification system rewards users for participating in the pant recycling economy. Points, levels, and achievements encourage both givers and collectors to stay active and engaged.

---

## Points

Points are the core currency of the gamification system. Every user accumulates points by participating in the listing lifecycle.

### How Points Are Earned

| Action | Points | Who Gets Them |
|---|---|---|
| Post a listing | +10 pts | Giver |
| Complete a listing (giver confirms pickup) | +25 pts | Giver |
| Successfully pick up a listing | +50 pts | Collector |
| Leave a review | +10 pts | Reviewer |
| Unlock an achievement | varies | Giver or Collector |

> Points are awarded **securely on the database** via Supabase triggers on the `listings` and `ratings` tables. This means points cannot be tampered with from the client — they are always assigned by the backend automatically when a listing changes state or a review is submitted.

---

## Levels

As users accumulate points, they advance through levels. Each new level starts every 500 total points.

| Level Range | Title |
|---|---|
| 1–4 | Beginner |
| 5–9 | Collector |
| 10–19 | Eco Warrior |
| 20–29 | Pant Master |
| 30+ | Legend |

The level formula is:
```
level = max(1, floor(totalPoints / 500) + 1)
```

So for example, 500 points = Level 2 and 1 000 points = Level 3. Progress toward the next level resets each time a new 500-point band begins.

---

## Achievements

Achievements are one-time milestones that unlock permanently and reward bonus points. They are stored in the `achievements` table in Supabase and respect a `UNIQUE(user_id, type)` constraint so they can only ever be unlocked once.

| Achievement | Display Name | Requirement | Bonus Points |
|---|---|---|---|
| `firstListing` | First Steps | Post your first listing | 50 pts |
| `firstPickup` | First Pickup | Complete your first pickup | 100 pts |
| `tenListings` | Generous Giver | Post 10 listings | 250 pts |
| `tenPickups` | Dedicated Collector | Complete 10 pickups | 500 pts |
| `fiftyPickups` | Pant Champion | Complete 50 pickups | 2 000 pts |
| `ecoWarrior` | Eco Warrior | Collect 100 kg of pant | 1 000 pts |
| `nightOwl` | Night Owl | Complete a pickup after 9 pm | 75 pts |
| `weekendWarrior` | Weekend Warrior | Complete 5 pickups on weekends | 150 pts |
| `quickCollector` | Speed Collector | Claim and complete a listing within 1 hour | 100 pts |
| `generousGiver` | Community Hero | Give away 25 listings | 750 pts |

---

## Implementation

The system is split between the **Supabase backend** (where all authoritative logic runs) and the **iOS client** (which reads and displays state and handles a handful of time-sensitive bonus checks).

### Backend (Supabase)

#### Tables

| Table | Purpose |
|---|---|
| `user_stats` | One row per user — stores `points`, `level`, `total_listings_posted`, `total_listings_collected`, `total_distance_meters`, `total_earnings_dkk`, `streak_days` |
| `achievements` | One row per unlocked achievement per user — stores `type`, `unlocked_at`, `points_awarded` |

#### Key RPC Functions

| Function | What it does |
|---|---|
| `award_points(p_user_id, p_points, p_reason)` | Adds points to `user_stats` and recalculates the user's level |
| `unlock_achievement(p_user_id, p_type)` | Marks an achievement as unlocked, awards its bonus points, returns `false` if already unlocked |
| `process_gamification_on_listing_complete(listing_id, giver_id, collector_id, distance_m, bag_size)` | Awards completion points to both parties, checks all volumetric & count-based achievements |
| `notify_listing_participants(listing_id, event_type, message)` | Assembles a push notification payload for all listing participants |

#### Database Triggers

These are the backbone of the system:

```
listings INSERT  → award 10 pts to giver, check firstListing achievement
listings.status → 'pendingPickup'              → notify both parties "listing claimed"
listings.status → 'awaitingGiverConfirmation'  → notify both parties "item picked up"
listings.status → 'completed'                  → notify both parties + run process_gamification_on_listing_complete
```

`on_listing_changed` fires `AFTER INSERT OR UPDATE` on the `listings` table, and `after_rating_insert` fires `AFTER INSERT` on the `ratings` table:

```
ratings INSERT → refresh recipient rating stats + award 10 pts to reviewer
```

Migration files:
- [`20260328230000_add_gamification_and_notification_triggers.sql`](supabase/migrations/20260328230000_add_gamification_and_notification_triggers.sql)
- [`20260329184645_add_review_points.sql`](supabase/migrations/20260329184645_add_review_points.sql)

The original gamification schema is in: [`hentpant/supabase/migrations/20260328_add_gamification.sql`](hentpant/supabase/migrations/20260328_add_gamification.sql)

#### Row Level Security

- Users can read **only their own** `user_stats` and `achievements`.
- A separate permissive policy also allows reading all `user_stats` rows for the leaderboard (points + level only).
- Only `SECURITY DEFINER` RPC functions may write to these tables — users cannot INSERT or UPDATE directly.

---

### iOS Client

#### `GamificationService.swift`

A Swift `actor` responsible for:
- Fetching `UserStats` and `[Achievement]` rows for a given user.
- Computing achievement progress by cross-referencing stats with each `AchievementType`'s requirements.
- Calling `award_points` and `unlock_achievement` RPCs for **time-aware bonuses** only (see below).

#### `AppState.swift`

- Loads gamification data on login via `loadGamificationData(userId:)`.
- Exposes `@Published var userStats`, `achievements`, `achievementProgress`, and `recentlyUnlockedAchievement` for the UI to observe.

#### Time-aware bonuses (client-side only)

Two achievements need device-local clock context that the database cannot easily evaluate:

| Achievement | Client check |
|---|---|
| `nightOwl` | `Calendar.current.component(.hour, from: .now) >= 21` |
| `weekendWarrior` | `weekday == 1 || weekday == 7` |

These are evaluated on the device when a pickup is confirmed and then call `unlock_achievement` via RPC to the backend. The backend `UNIQUE` constraint prevents duplicate unlocks.

---

## Data Flow Summary

```
User posts listing
  └─ listings INSERT trigger fires
       └─ award_points(giver, +10)   [DB]
       └─ unlock_achievement(giver, 'firstListing')  [DB, if eligible]

Receiver claims listing
  └─ listings.status = 'pendingPickup'
       └─ notify_listing_participants("listing_claimed")  [DB]

Receiver marks picked up
  └─ listings.status = 'awaitingGiverConfirmation'
       └─ notify_listing_participants("listing_picked_up")  [DB]
       └─ nightOwl / weekendWarrior checked  [iOS client]

Giver confirms pickup
  └─ listings.status = 'completed'
       └─ notify_listing_participants("listing_completed")  [DB]
       └─ process_gamification_on_listing_complete(...)  [DB]
            └─ award_points(giver, +25)
            └─ award_points(collector, +50)
            └─ unlock milestones (tenListings, tenPickups, generousGiver, etc.)

User leaves a review
  └─ ratings INSERT trigger fires
       └─ refresh recipient average_rating + rating_count  [DB]
       └─ award_points(reviewer, +10)  [DB]
```
