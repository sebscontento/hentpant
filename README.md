# PantCollect (hentpant)

**PantCollect** connects people who want to get rid of their **pant** (Danish deposit bottles and cans) with people who collect them. Givers post a photo, quantity estimate, and approximate location; collectors see listings on a map, claim a pickup, and confirm when the bag is gone—without home entry or mandatory meetups.

## Stack

- **iOS** 18+ (SwiftUI, MVVM-style `ObservableObject` app state)
- **MapKit** for browse map and pin placement
- **PhotosUI** for up to three listing photos
- **Sign in with Apple** and email/password (demo moderator/admin accounts in debug)
- **In-memory store** in `AppState` for the MVP; structure matches a future **Firebase** setup (Auth, Firestore, Storage, Cloud Functions, FCM)

## Repository layout

- `hentpant/` — Xcode project and Swift sources (`Models/`, `Services/`, `Views/`)

## License

See [LICENSE](LICENSE).
