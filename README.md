# Hyperion Support

Mobile/web support and ticketing app for the Ministry of Finance's
PFM-Systems Division — lets MDA/MMDA staff log, track, and escalate
Hyperion budgeting-system issues, and gives support staff a triage
dashboard. Flutter (single codebase, web + Android) + Firebase.

Back-office roles (Support Coordinator, Functional/Technical Lead,
PFM-Systems Management) get a full desktop Enterprise Web Dashboard
(sidebar nav, data tables, charts) automatically at viewport widths
≥900px — see `core/responsive.dart` / `core/routing/desktop_shell.dart`.
Everyone else, and back-office roles on a narrower viewport, gets the
mobile bottom-nav experience. Same codebase, same Firebase backend, one
`ResponsiveScreen` switch per route in `app_router.dart`.

See [DECISIONS.md](DECISIONS.md) for the judgment calls made while building
this and the bugs found (and fixed) along the way — worth reading before
extending anything, especially the Firestore security rules.

## Stack

- **Flutter** + **Riverpod** (state) + **go_router** (routing)
- **Firebase**: Firestore (data + offline persistence), Auth (custom claims
  for role/institution), Storage (attachments — not yet active, see
  DECISIONS.md), Cloud Messaging (push), Cloud Functions (admin user
  provisioning + lifecycle notifications — written, not yet deployed, see
  DECISIONS.md)
- **Hive** for the offline ticket-draft queue

## Project layout

```
lib/
  core/           shared: auth, theming, routing, offline, push notifications
  features/       feature-first: auth, tickets, dashboard, notifications,
                  knowledge_base, profile, admin — each split into
                  data/domain/presentation
functions/        Cloud Functions (Node.js) — adminCreateUser + ticket
                  lifecycle notification triggers
scripts/          one-off local admin tooling (seed.js — creates test
                  accounts via the Admin SDK; not part of the shipped app)
firestore.rules   the actual access-control boundary — see Section 3 of
                  the project brief and DECISIONS.md
```

## Local setup

1. `flutter pub get`
2. Firebase project `hyport-a1c90` is already wired up
   (`lib/firebase_options.dart`, `android/app/google-services.json`). To
   point at a different project instead, run `flutterfire configure`.
3. To seed test accounts (one per role): put a service account key at
   `scripts/service-account.json` (Firebase Console -> Project settings ->
   Service accounts -> Generate new private key), then:
   ```
   cd scripts && npm install && node seed.js
   ```
   All seeded accounts share the password `Hyport@2026`.

## Running

```
flutter run -d chrome     # web
flutter run               # connected Android device/emulator
```

## Building

```
flutter build web
flutter build apk
```

## Testing on iOS

There's no Mac in this project's dev environment, and iOS builds
(compiling, code signing, everything) can only happen on macOS or a cloud
Mac CI — that's an Apple platform requirement, not something local tooling
can work around. Two ways to actually get this in front of an iOS tester:

- **Today, no setup**: the web build is an installable PWA — open the
  hosted site in Safari and use Share -> "Add to Home Screen." Real app
  icon, real name, works offline-capable-ish like the rest of this app's
  web build, but it's the web app in a home-screen wrapper, not a native
  binary — won't exercise anything iOS-native-specific.
- **Real native build**: `codemagic.yaml` at the repo root is a ready
  (but unverified — see its own header comment) pipeline that builds a
  signed `.ipa` on Codemagic's cloud Mac runners and pushes it to Firebase
  App Distribution, so testers install via a normal email/link rather than
  the App Store. Needs, one-time: an Apple Developer Program membership
  ($99/yr — required by Apple for any signed build, no way around this),
  a Codemagic account (free tier is enough), and a Firebase service
  account key for this project. Exact steps are documented as comments
  inside `codemagic.yaml`. The iOS platform files (`ios/`) and this
  project's Firebase iOS app registration are already in place — see
  DECISIONS.md.

## What's not live yet

- **Firebase Storage** (attachments) — blocked on the Blaze billing plan.
  Attachments are picked in the UI but not uploaded until this is resolved;
  see DECISIONS.md.
- **Cloud Functions** (`functions/`) — written and verified to load
  correctly, but undeployed for the same Blaze-plan reason. Once billing
  clears: `firebase deploy --only functions`.
- **Web push (FCM)** — needs a VAPID key generated in the Firebase Console
  (Cloud Messaging -> Web Push certificates), then set
  `webPushVapidKey` in `lib/core/services/push_notification_service.dart`.
  Android push doesn't need this step.
