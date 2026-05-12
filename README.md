# FireJournal (Firebase)

FireJournal is an iOS SwiftUI journal demo built on Firebase Authentication + Firestore.

## What this app demonstrates

- Email/password auth with FirebaseAuth
- Per-user Firestore data paths: `users/{uid}/entry`
- Live Firestore UI updates with `@FirestoreQuery`
- Entry CRUD + favorite toggle
- Photo upload to Firebase Cloud Storage; download URLs stored in Firestore
- Auto-tag generation from caption/photo metadata helper

## Project structure

- `module-6-FireJournal/FireJournal/Authentication`: auth controller + auth UI
- `module-6-FireJournal/FireJournal/Views`: root router, journal list, detail
- `module-6-FireJournal/FireJournal/Models`: Firestore entry model + tagger

## Important decisions

- Auth state drives root navigation (`ContentView` chooses auth or journal UI).
- Data is scoped by UID using subcollection path `users/{uid}/entry`.
- Photos are uploaded to Firebase Cloud Storage and the download URL is saved in Firestore (`photoURL`).
- Legacy `photoData` field is kept for backward compatibility with old entries.
- Vision/CoreML image tagging is compile-time disabled on Simulator.

## Known compatibility fields

These names are intentionally preserved for existing data compatibility:

- `uesrTags` (typo kept intentionally)
- `metadataLatitute` (typo kept intentionally)

If you rename these, plan a migration.

## Setup

1. Place valid `GoogleService-Info.plist` in `module-6-FireJournal/FireJournal/`.
2. Ensure Firebase project has Authentication (Email/Password) enabled.
3. Ensure Firestore is created and security rules support your expected user-scoped access.
4. Ensure Firebase Cloud Storage is enabled (Blaze plan required) with per-user security rules.

## Build

From repository root:

```bash
xcodebuild -project module-6-FireJournal/FireJournal.xcodeproj -scheme FireJournal -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

