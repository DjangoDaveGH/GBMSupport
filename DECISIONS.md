# Decisions log

Judgment calls made without stopping to ask, per the project brief's
instruction to keep going and record reasoning here instead. Newest first.

## 2FA/OTP removed entirely — user asked to remove it, not just re-disable it

Phone MFA was already sitting behind the `twoFactorMandatory = false` flag
(previous entry) because reCAPTCHA wasn't resolving for real users. The
user asked to remove it outright rather than continue troubleshooting or
leave the disabled scaffolding in place. Unlike the previous entry, this
is a genuine deletion, not a flag flip — nothing here is meant to come
back:

- Deleted `PhoneMfaService`, `OtpVerifyScreen`, `TwoFactorSetupScreen`,
  and `scripts/disable_2fa_for_testing.js` outright.
- `app_router.dart`: removed the `/otp-verify` and `/setup-2fa` routes,
  the `needsTwoFactorSetup` redirect gate, and `/otp-verify` from
  `preAuthPaths`. Login now goes straight from credentials to `/home`
  via the ordinary redirect, no MFA step in between.
- `login_screen.dart`: dropped the `FirebaseAuthMultiFactorException`
  catch clause — Firebase can't throw it for an account with no enrolled
  factor, and no account can enroll one anymore.
- `settings_screen.dart` / `edit_user_dialog.dart`: removed the Security
  section (`_TwoFactorStatus`, `_ChangePhoneDialog`) and the admin
  "Reset 2FA" action.
- `AppUser.twoFactorEnabled` and `UserRepository.setTwoFactorEnabled`
  removed; `functions/index.js`'s `adminResetTwoFactor` callable deleted;
  `firestore.rules`' `onlyFieldsChanged` carve-out for `twoFactorEnabled`
  dropped.
- The old client-side `OtpRepository` (generated codes shown on-screen,
  predates the Firebase phone MFA work) was already deleted in the
  working tree before this pass — left deleted, not restored.

Existing `users/{uid}.twoFactorEnabled` fields in Firestore are now
simply unread/ignored, not backfilled away — harmless leftover data, not
worth a migration for a field nothing references anymore.

## 2FA temporarily disabled — participants were blocked from using the app

Root-caused as far as tooling in this environment allows (no browser-
automation tool by default, so drove a real headless Chromium — found
already installed from an earlier session — via a scratch Playwright
script to actually click through sign-in and hit "Send Code" for real,
rather than continuing to guess at Firebase project settings). That test
proved the project config is genuinely correct: the flow reached a real
interactive reCAPTCHA challenge (an actual "select all squares with
buses" puzzle), which only happens *after* Firebase has already validated
project config, phone/MFA provider enablement, the authorized domain, and
the SMS region policy — everything fixed in the two prior entries. So the
remaining failure is reCAPTCHA itself not resolving for real users in the
field — most likely a network-level or browser-extension-level block on
`google.com/recaptcha`/`gstatic.com/recaptcha` (common on office/
government networks with content filtering), not a project
misconfiguration. Confirmed via Admin SDK that no seeded account had
actually completed enrollment (`multiFactor.enrolledFactors` empty on all
8), so disabling the app-level gate is safe — no account can get stuck at
a Firebase-enforced challenge that already exists.

With participants waiting to use the app, the user asked to scrap 2FA
enforcement for now rather than keep troubleshooting a network-dependent
issue live. Disabled via a single shared flag, `twoFactorMandatory` (now
`false`) in `lib/features/auth/data/phone_mfa_service.dart` — read by
both `app_router.dart`'s redirect gate (wrapped in `if
(twoFactorMandatory)`, `// ignore: dead_code` while off) and
`settings_screen.dart`'s Security section visibility (hidden entirely
while off, rather than showing a misleading "Required" status nobody can
actually complete). Deliberately a flag flip, not a revert/deletion —
`PhoneMfaService`, `TwoFactorSetupScreen`, `OtpVerifyScreen`,
`adminResetTwoFactor`, and all the Firebase-side config fixes stay
exactly as built, ready to re-enable by flipping the one constant back to
`true` once reCAPTCHA is confirmed working end-to-end (worth testing from
a non-office network / with extensions disabled first, per the previous
entry's diagnostic suggestions, before flipping it back).

Rebuilt and redeployed web (`gbmsupport.web.app`) and Android
immediately given the urgency (participants actively blocked). No
Firestore/rules/functions changes needed — this was purely a client-side
routing/UI change.

## Fixed: same "operation-not-allowed" persisted on web after the region-policy fix — real cause was the custom hosting site was never authorized

The SMS region policy fix (previous entry) didn't resolve it — user kept
seeing the identical error on web specifically. Reproducing the exact
client call via REST (`accounts/mfaEnrollment:start`) surfaced a
*different* error (`MISSING_CLIENT_IDENTIFIER`, expected — curl isn't a
real browser with a reCAPTCHA token), which ruled out that path without
confirming the real cause. Went back to the Identity Platform config
already pulled for the region-policy investigation and noticed
`authorizedDomains` only listed `mofapp-60963.web.app` /
`mofapp-60963.firebaseapp.com` / `localhost` — **`gbmsupport.web.app` was
never added**, a leftover gap from creating that second Hosting site and
switching deploys to it (see the earlier "custom .web.app subdomain"
work) without touching Firebase Auth's separate authorized-domains list.
Phone verification's reCAPTCHA step legitimately fails on an
unauthorized domain, which fits both the web-only symptom (user confirmed
Android wasn't tested/affected the same way) and the generic
`operation-not-allowed` surfacing instead of a more specific
domain-related error.

Fixed the same way as the region policy — a `PATCH` to
`identitytoolkit.googleapis.com/admin/v2/projects/mofapp-60963/config`
adding `gbmsupport.web.app` to `authorizedDomains` (kept the existing
three rather than replacing them, in case anything still references the
default site). Confirmed via the response body that all four domains are
now listed. No code/deploy needed. Worth remembering for any *future*
custom domain (e.g. if `gbmsupport.com` gets connected later, per the
earlier domain conversation) — that'll need the same authorized-domains
addition, not just the Hosting-side connection.

## Fixed: "operation-not-allowed" on OTP send (SMS region policy, not the Phone/MFA toggles)

Follow-up to the "unverified email" fix — user still hit an error after
that (`auth/operation-not-allowed`) even with Phone sign-in and SMS MFA
both confirmed enabled in the Console. Diagnosed by reading the project's
actual Identity Platform config directly (`GET
https://identitytoolkit.googleapis.com/admin/v2/projects/mofapp-60963/config`,
authenticated with the existing `scripts/service-account.json` — this
config isn't exposed through firebase-admin's `auth()` module or the
Console UI path we'd been checking, only the raw Identity Toolkit Admin
API) rather than guessing at more Console settings. Found the real cause:
`smsRegionConfig: { allowlistOnly: {} }` — an *empty* allowlist, meaning
zero countries were permitted to receive SMS at all. This is a separate
anti-fraud setting from the Phone/MFA enable toggles (which were both
genuinely fine — `phoneNumber.enabled: true`, `mfa.state: ENABLED` in the
same config dump), defaults to this locked-down empty state when MFA is
first turned on, and isn't obviously surfaced in the Sign-in method UI
the user had been looking at.

Fixed with a `PATCH` to the same Admin API endpoint, allowlisting Ghana
specifically (`smsRegionConfig.allowlistOnly.allowedRegions: ["GH"]`)
rather than opening it to all regions — narrower blast radius for
SMS-pumping abuse, and the only real audience for this app is Ghanaian
phone numbers anyway. Confirmed via a second `GET` that the change
persisted. No code/deploy needed — this is pure Firebase project
configuration, orthogonal to everything already shipped.

## Fixed: "unverified email" error on the 2FA setup/OTP screen

User-reported bug, root-caused rather than guessed at: confirmed via a
direct Admin SDK query (`getUserByEmail('m@m.com').emailVerified`) that
seeded accounts had `emailVerified: false`. Firebase phone Multi-Factor
Authentication refuses to enroll a factor for an unverified email
(`auth/unverified-email`) — a real Firebase-side precondition, not
something this app was doing wrong in its own logic. This app has no
email-verification flow anywhere (accounts are exclusively
admin-provisioned, trusted as entered — see the original "no self-signup"
scoping decision), so every admin-created and seeded account was landing
in this unverified state by default and had no way to clear it.

Fix: force `emailVerified: true` at account-creation/update time in both
places accounts get created — `adminCreateUser` (`functions/index.js`)
for real accounts, and `scripts/seed.js` for test accounts — rather than
building an actual verification-email flow this app doesn't otherwise
need. Re-ran `seed.js` to retroactively fix the 8 already-existing seeded
accounts (`updateUser` covers existing users, per the script's own
"safe to re-run" design) and redeployed `adminCreateUser` so new accounts
don't hit this going forward.

## 2FA made mandatory for every account, not opt-in

The previous session built SMS OTP as a self-service Settings toggle. The
user corrected this: every account must go through phone verification on
login, no exceptions, no opt-out. Real architectural implication, not a
flag flip — the whole mechanism depends on Firebase itself throwing
`FirebaseAuthMultiFactorException` during sign-in, which only happens for
an account that already has an enrolled factor. An account that's never
enrolled just signs in normally no matter what "mandatory" means at the
product level, so mandatory has to be enforced by the app.

- **`app_router.dart`**: a new redirect gate (`needsTwoFactorSetup`),
  same shape as the `needsOtp` gate removed last session but checking
  *enrollment* rather than *per-session verification* — any signed-in
  user with `!appUser.twoFactorEnabled` gets forced to a new `/setup-2fa`
  route before anything else in the app is reachable. This is a
  genuinely different gate from `/otp-verify` (which challenges an
  *already-enrolled* user mid-sign-in, before Firebase even considers
  them authenticated) — this one catches an authenticated-but-never-
  enrolled user and forces first-time setup.
- **New `TwoFactorSetupScreen`**: full-screen, non-dismissable version of
  the same send-code/confirm-code mechanics already built
  (`PhoneMfaService`, `normalizeGhanaPhone`). No Cancel button — a Sign
  Out action instead, so a user who can't complete it right now isn't
  hard-stuck with zero way out of the screen.
- **Settings' 2FA row** stopped being a toggle (`_TwoFactorSwitch` →
  `_TwoFactorStatus`) — always shows "Required", with a "Change" action
  for re-enrolling a new number (unenroll-then-enroll,
  `_ChangePhoneDialog`) rather than an on/off switch. Matches "not an
  option" literally: there's no path in the UI to disable it anymore.
- **Lost-phone recovery** (flagged as a real gap the moment 2FA has no
  opt-out — a user who loses their phone would otherwise be permanently
  locked out): new `adminResetTwoFactor` Cloud Function
  (`functions/index.js`), directly mirroring `adminUpdateUser`'s
  pfm_management-only auth check and audit-log pattern. Client SDK can
  only unenroll the *signed-in* user's own factor, so clearing someone
  else's enrolled factor has to go through the Admin SDK
  (`admin.auth().updateUser(uid, {multiFactor: {enrolledFactors: []}})`)
  — a genuinely different code path from the client-side `unenroll()`
  already in `PhoneMfaService`, not reusable from the client. Wired into
  `edit_user_dialog.dart` as a "Reset" action, shown only when the target
  user has 2FA enrolled, with its own confirm-before-firing dialog since
  it forces that account back through setup next login.
- **Testing implication caught before it became a live lockout**: the 8
  seeded accounts (`scripts/seed.js`) have fake phone numbers
  (`+233200000001`..`008`) that can't receive real SMS — mandatory
  enrollment would have hard-locked every test account with no way to
  complete setup. Resolved by having the user register those exact 8
  numbers as Firebase Console "phone numbers for testing" (fixed
  verification code, no real SMS sent) rather than touching seed data —
  they already existed and already mapped one-to-one to the 8 seeded
  accounts.

Deployed: `adminResetTwoFactor` via `firebase deploy --only functions`
(all 5 functions redeployed clean), web rebuilt/redeployed to
`gbmsupport.web.app`, Android APK rebuilt. Not verified end-to-end in a
real browser/device — no browser-automation tool in this environment,
same standing limitation as every UI change this session; `flutter
analyze` clean and all deploys succeeded, but the actual click-through
(sign in unenrolled → forced to /setup-2fa → complete with a Console test
number → sign out/back in → real /otp-verify challenge fires → admin
Reset button forces it again) is on the user once the Console test
numbers are registered.

## GBMS rebrand + UI "softer/modern" polish pass, both design-tokens-only

Two follow-up requests handled as pure design-token changes rather than
touching individual screens, since the app is disciplined about pulling
from `AppTheme`/`AppRadius`/`ColorScheme` rather than hardcoding values
(confirmed via grep before starting: 31 files reference
`colorScheme.outlineVariant`, 41 reference `AppRadius.*`, only 4 hardcoded
border colors app-wide, all on decorative white avatar rings unrelated to
card styling) — both changes cascade everywhere automatically with zero
per-screen edits.

**Rebrand** ("Ghana Budget Management System (GBMS) Support", confirmed
via AskUserQuestion against a memo found in the user's Downloads folder
that expanded GBMS this way, since the user's own phrasing suggested a
different expansion): every "Oracle Hyperion"/"Hyperion Support" string
across `lib/`, `web/`, `android/app/src/main/AndroidManifest.xml`
(`android:label`), and `ios/Runner/Info.plist`
(`CFBundleDisplayName`/`CFBundleName`) replaced with "GBMS"/"GBMS Support
Centre". First grep pass used mixed-case patterns and missed four
ALL-CAPS occurrences (`splash_screen.dart`, `login_screen.dart`,
`desktop_shell.dart`, `home_screen.dart`, `web/index.html`'s static
pre-Flutter loading screen) — caught on a case-insensitive re-sweep before
calling it done, a reminder to always grep `-i` for brand strings rather
than trusting the first pass. `config/general.appName` in Firestore
(admin-editable, would override the code default) was checked and
confirmed not yet set by any admin, so the Dart-level default change
alone was sufficient — no Firestore write needed.

**"Softer/modern" polish** (user request: "touch up the UI a bit, no
structural changes, just the feel"; confirmed scope via AskUserQuestion —
whole-app pass, softer/modern direction over "keep crisp/corporate" or
"more vibrant"): `AppRadius` scale bumped up a notch across the board
(sm 8->10, md 10->14, lg 12->18, xl 18->24); `outline`/`outlineVariant`
lightened for less visually-heavy card borders; `CardThemeData` gained
real elevation+shadowColor instead of being purely flat-with-border;
button shapes moved from `AppRadius.sm` to the now-larger `AppRadius.md`
plus subtle shadowColor on Elevated/Filled buttons; `NavigationBarThemeData`
and `AppBarTheme.scrolledUnderElevation` gained subtle elevation/shadow
(both were explicitly flat/0 before); route transitions
(`app_router.dart`'s `_fadePage`) switched from `Curves.easeOut` at 220ms
to `Curves.easeOutCubic` at 260ms to match `_slideUpPage`'s already-smoother
curve. Deliberately did **not** touch the many screens' own
`Container`+`BoxDecoration` "card" blocks directly (that pattern is
duplicated per-screen, not routed through a shared widget) — those still
pick up the softer look because they reference `AppRadius.*` and
`Theme.of(context).colorScheme.outlineVariant` rather than hardcoded
values, which was confirmed before starting rather than assumed.

**Not verified visually**: no browser-automation tool is available in
this environment (recurring limitation this session) — rebuilt and
redeployed web + Android after both changes, confirmed via `flutter
analyze` and a direct `curl` fetch of the deployed HTML (bypassing
WebFetch's own 15-minute cache, which served stale content on the first
check), but an actual look-and-feel pass in a real browser/device is
still worth the user doing themselves.

## SMS OTP for login via Firebase phone Multi-Factor Authentication

The user asked for SMS OTP on login. Rather than integrate a third-party
SMS gateway (Twilio/Africa's Talking/Hubtel — a new vendor account, a new
secret to store, and a new Cloud Function to send messages), used
**Firebase Authentication's built-in phone Multi-Factor Authentication**
instead, confirmed with the user: Google sends the SMS directly, no
third-party account needed. Also confirmed: this **replaces** the old
custom on-screen OTP flow rather than sitting alongside it, since Firebase
MFA has its own enrollment/challenge mechanics that don't compose with the
old Firestore-based `otp_codes` scheme.

**Real architectural shift, not just a delivery-mechanism swap**: the old
flow signed a 2FA user in immediately via `signInWithEmailAndPassword`,
then gated navigation post-hoc with an app-level flag
(`otpVerifiedProvider`) checked in the router's `redirect`. Firebase MFA
throws `FirebaseAuthMultiFactorException` *from inside*
`signInWithEmailAndPassword` for an MFA-enrolled account — the user isn't
signed in at all (no `User` from `authStateChanges()`) until the phone
challenge resolves. So the OTP step moved from "a redirect gate after
sign-in" to "a catch-block in `LoginScreen._submit()`, before sign-in
exists" — `otpVerifiedProvider` and the router's `needsOtp` redirect logic
became genuinely dead code, not something to keep as a fallback, and were
deleted along with `OtpRepository`/`otp_codes` (both firestore.rules and
the collection itself).

- **New `PhoneMfaService`** (`lib/features/auth/data/phone_mfa_service.dart`)
  wraps `verifyPhoneNumber`'s callback API (`codeSent`/`verificationFailed`)
  in `Completer`-based `Future`s for enroll/unenroll (Settings) and the
  sign-in challenge (`MultiFactorResolver`-driven, from `LoginScreen`'s
  catch block). Also a small `normalizeGhanaPhone` helper — Firebase phone
  auth requires E.164 (`+233...`), but `AppUser.phone` (already existed,
  already captured by admins in `add_user_screen.dart`) has never been
  format-enforced, so local `0XXXXXXXXX` numbers get converted rather than
  rejected outright.
- **`OtpVerifyScreen`** reworked to take a `MultiFactorResolver` via
  router `extra` (pushed from `LoginScreen`, not reached by redirect
  anymore) instead of a uid. Kept the exact same 6-digit-box UI and
  resend-cooldown pattern from the old build — only what backs it changed,
  the mockup-matched shell didn't need to.
- **Settings' 2FA switch** stopped being a bare toggle: turning it on now
  opens a real two-step dialog (confirm/edit phone number → enter the
  code just texted) that only flips `users/{uid}.twoFactorEnabled` after
  Firebase enrollment actually succeeds. That field is now explicitly a
  denormalized "is enrolled" read flag for UI display — Firebase's own
  `user.multiFactor.enrolledFactors` is the real source of truth, this
  Firestore field just avoids every screen needing to hit that API to
  show a badge/subtitle.
- `/otp-verify` had to move into the router's `preAuthPaths` list — it's
  now reached mid-sign-in (before `authStateChanges` emits a user), so
  the existing "no firebaseUser -> redirect to /welcome unless on a
  pre-auth path" rule would otherwise bounce straight off it.

**Manual Console setup** (confirmed done by the user, can't be driven from
here): Authentication -> Sign-in method -> Phone enabled; Authentication
-> Settings -> Multi-factor authentication -> SMS enabled.

**Not verified end-to-end**: no browser-automation tool is available in
this environment (same limitation as the Firebase project migration
entry below) — enrollment and the sign-in challenge should be tested for
real on the deployed app. Two things flagged as optional follow-ups, not
blockers: Android SHA-1/SHA-256 fingerprints (smoother Play-Integrity
verification, falls back to reCAPTCHA without them) and iOS APNs config
(same fallback story; this project has no Mac to build/test iOS locally
regardless, an existing documented constraint).

## Firebase project migration to mofapp-60963, and every Blaze-gated feature activated

The user upgraded `hyport-a1c90` to Blaze, but every deploy kept failing
with "Billing account ... is not open" — confirmed across two different
Google accounts logged into the CLI, so the billing account itself was
broken, not an account-permissions issue. The account that owned/
administered `hyport-a1c90` (`appsysunit@gmail.com`) then became fully
locked out with no recovery path, ruling out a self-service fix via that
account's Console access. Decided with the user, after confirming there
was no real production data yet (QA/seed data only) and after weighing
"add a new owner to the same project" against "start a fresh project": to
create a brand-new Firebase project under a new account
(`mofappsunit@gmail.com`) and cut the whole app over, clean, rather than
pursue a Google support ticket to recover the old account.

The new project ended up as **`mofapp-60963`** rather than the originally
planned `hyport-mof` — `firebase projects:create hyport-mof` succeeded at
the GCP-project layer but then failed attaching Firebase to it (`403
PERMISSION_DENIED` on `addFirebase`, cause unclear — possibly a first-time-
account quirk since `mofappsunit@gmail.com` was brand new and had to
accept Cloud's Terms of Service before project creation would even work at
all). Rather than fight that further, created `mofapp-60963` directly
through the Firebase Console's "Add project" flow instead, which worked
immediately. The orphaned `hyport-mof` GCP project (Firebase never
attached) was left alone rather than deleted — inert, costs nothing,
not worth a destructive cleanup step.

What migrating actually involved, in order, each with its own real
first-time-setup wrinkle:
- **Blaze upgrade on the new project** — needed separately from the old
  project's billing; this time it activated cleanly.
- **`flutterfire configure --project=mofapp-60963`** regenerated
  `lib/firebase_options.dart` and `android/app/google-services.json`
  correctly, but did *not* rewrite `ios/Runner/GoogleService-Info.plist`
  on this run (unclear why — possibly because a plist already existed at
  that path). Re-fetched it manually via `firebase apps:sdkconfig IOS
  <appId>`, the same fallback used during the original iOS scaffolding.
- **Firestore**: had to be created explicitly (`firebase
  firestore:databases:create "(default)" --location=nam5`) before any
  rules/functions could deploy — brand-new projects don't provision one
  automatically. Hit a real race condition here: the API-enablement step
  and the actual database-creation call happened too close together, so
  the first attempt 403'd with "Cloud Firestore API has not been used ...
  or it is disabled" even though the API had just been "enabled" moments
  earlier by the same command. Waiting and retrying resolved it — no code
  or config was wrong, just eventual-consistency lag on Google's side.
- **Storage**: needed the one-time "Get started" click in the Console
  before `firebase deploy --only storage` would accept anything — the API
  being enabled isn't sufficient, the bucket itself has to exist first.
- **Cloud Functions**: `adminCreateUser`/`adminUpdateUser` deployed clean
  on the first pass (no Eventarc trigger). The two Firestore-triggered
  functions (`onTicketCreated`/`onTicketUpdated`) failed on the first
  attempt with an Eventarc Service Agent permission error — expected and
  explicitly flagged by Google's own error message as "first time using
  2nd gen functions, ... permissions to propagate" — a bare retry a
  minute later succeeded with no changes needed.
- **Auth**: Email/Password sign-in had to be enabled explicitly in the
  Console (Authentication -> Sign-in method) before the seeded accounts
  could actually sign in, even though the Admin SDK could already create
  them regardless of that toggle. Verified past this with a direct
  `accounts:signInWithPassword` REST call before trusting it, rather than
  assuming the toggle was sufficient.
- **`scripts/service-account.json`** (gitignored) had to be regenerated
  from the new project's Console and swapped in before `seed.js` could
  run again.

With Blaze active and genuinely working this time (unlike the abandoned
`hyport-a1c90` attempt), everything that had been built-but-gated behind
billing got activated, and a few UI gaps that had been explicitly deferred
pending Storage got built for real rather than left disabled:
- **Application Logo upload** (`desktop_settings_screen.dart`) was a
  hard-disabled button (`onPressed: null`) pending Storage. Wired for
  real, mirroring the exact upload pattern already used for ticket
  attachments (`new_ticket_screen.dart`) and profile photos
  (`profile_screen.dart`): pick an image, upload to a fixed
  `branding/logo` Storage path, persist the resulting URL onto
  `config/general.logoUrl`. New `branding/logo` Storage rule restricts
  writes to `pfm_management`, matching the existing Firestore rule on
  `config/general` itself.
- **Reports PDF export** (`reports_screen.dart` / `report_detail_screen.dart`)
  previously had no export at all — "no Storage yet to persist those."
  Rather than duplicate each report type's row-building logic between the
  on-screen widgets and a new PDF renderer, extracted it into
  `report_section_data.dart` (`List<ReportSectionData>` — title + label/
  value rows) as the single source both `ReportDetailScreen`'s widgets and
  the new `ReportPdfExporter` (`report_pdf_export.dart`, using the `pdf`
  package) read from, so the two can't drift apart. Exported PDFs upload
  to `reports/{uid}/...` (new Storage rule, owner-only + support-side-role
  gated) and the resulting URL is attached to that export's `report_views`
  entry (`ReportView.pdfUrl`, new nullable field) — so "Recent Reports"
  entries with an export are now real, re-openable files (`url_launcher`,
  new dependency) rather than just a view-history log.
- Doc comments and README that previously said "blocked on the Blaze
  billing plan" (`otp_repository.dart`, `otp_verify_screen.dart`,
  `audit_log_repository.dart`) were corrected: Blaze is active now, so
  those gaps (emailed OTP codes, broader audit-log instrumentation) are
  unbuilt-scope items, not billing blockers. Deliberately did *not* build
  real OTP email delivery in this pass — the user scoped this migration to
  reactivating what was already gated plus the logo button and PDF export,
  not new email-provider integration work.

**Not done, still open**: Web Push (FCM) needs a VAPID key generated fresh
for `mofapp-60963` (Console -> Cloud Messaging -> Web Push certificates)
and set in `lib/core/services/push_notification_service.dart` —
independent of Blaze, was already a manual step before the migration too.
No browser-automation tool was available in this environment to click
through the live app end-to-end (logo upload, PDF export, attachment
upload) — verified instead via `flutter analyze`, successful builds/
deploys, and a direct Auth REST call confirming sign-in works; a manual
pass through the deployed app (https://mofapp-60963.web.app) is still
worth doing.

## iOS testing pipeline scaffolded (no Apple Developer account yet — confirmed with the user)

Asked how to get an "APK equivalent" for iOS testers. There isn't a true
one — Apple requires every install to be code-signed, which needs a paid
Apple Developer Program account ($99/yr) and a way to build on macOS,
neither of which exist in this project or this dev environment. Confirmed
via AskUserQuestion that the account doesn't exist yet but the user still
wants the pipeline built now, ready to go the moment it does. What's
actually in place:

- **`ios/` platform files scaffolded** via `flutter create --platforms=ios
  --org gov.mofep.hyport .` — additive only, verified nothing under
  `lib/`, `android/`, or `web/` changed. Bundle ID
  (`gov.mofep.hyport.hyport`) deliberately matches Android's existing
  `applicationId` so the two platforms don't need separate mental mapping
  when configuring Firebase/signing later.
- **Registered a real Firebase iOS app** (`firebase apps:create IOS`,
  project `hyport-a1c90`) and filled in `lib/firebase_options.dart`'s
  `ios` block, which had shipped with literal `'REPLACE_ME'` placeholder
  values (pre-existing — from the original "Firebase project connection"
  entry below, written before iOS tooling existed to fill it in). Without
  this, a build off this scaffold would have compiled fine but crashed on
  first launch the moment `Firebase.initializeApp` ran, since this app
  passes `DefaultFirebaseOptions.currentPlatform` explicitly rather than
  relying on native auto-config — so the `GoogleService-Info.plist` also
  dropped into `ios/Runner/` is a secondary/defensive addition (some
  Firebase iOS tooling expects it to exist at that path), not the thing
  actually making Firebase work here.
- **Fixed a real branding gap while touching icons anyway**: both
  `android/app/src/main/res/mipmap-*/ic_launcher.png` and the label in
  `AndroidManifest.xml` (`android:label="hyport"`) were still `flutter
  create`'s unbranded defaults — the exact same bug flagged-but-not-fixed
  in the web PWA icon entry below, just never circled back to. Since iOS
  icon generation meant rebuilding the same Pillow script anyway, ran it
  against Android's launcher sizes too and fixed the label
  (`"Hyperion Support"`, matching the web manifest's `short_name` and the
  new iOS `CFBundleDisplayName`) in the same pass rather than leaving a
  known, already-documented inconsistency sitting there. iOS App Store
  icons are saved as flat RGB (no alpha channel) — Apple's App Store
  Connect rejects icons with transparency, unlike the web/Android ones.
- **`codemagic.yaml`**: a cloud-Mac CI pipeline (Codemagic has a free tier)
  that builds a signed `.ipa` and publishes it to Firebase App Distribution
  — testers get an email/link and install directly, no App Store review,
  the closest real equivalent to "hand someone an APK" that iOS allows.
  Every manual one-time setup step (Apple Developer enrollment, Codemagic
  account + Apple signing connection, a Firebase service-account key for
  distribution, a tester group in the Firebase console) is documented
  inline as comments in the file itself, since none of it can be automated
  from here — each step needs credentials or accounts only the user has.
  Explicitly **not verified end-to-end**: no Apple or Codemagic account
  exists yet to actually run this against, so treat the yaml as a
  well-informed starting point to check against Codemagic's current docs
  at setup time, not a guaranteed-turnkey pipeline. `triggering.events` is
  deliberately empty (manual-only) so it can't accidentally fire before
  signing is configured.
- Also documented in README under a new "Testing on iOS" section, which
  leads with the option that already works today with zero setup: the
  rebranded PWA via Safari's "Add to Home Screen."

Verified: `flutter analyze` clean (0 issues). Could not verify the iOS
build itself compiles or runs — that requires Xcode/macOS, unavailable in
this environment; Codemagic's cloud Mac runners are the intended way to
find out, once connected.

## Chat screen restyled to strictly match the mockup; Comment/Conversation relabeled to Chat everywhere

Re-checking the Chat screen (`ticket_chat_screen.dart`, built in the
previous pass) directly against the mockup poster's own chat screenshot
surfaced three real visual mismatches, not just polish:

1. **Bubble colors were backwards.** The mockup shows the *other* party's
   messages (John Mensah, left-aligned) in the navy/branded bubble, and
   your own sent messages (right-aligned) in plain white — the reverse of
   the "your bubble is the branded one" convention most chat UIs use
   (iMessage, WhatsApp), which is what the first pass had defaulted to
   without checking the reference closely enough. Swapped: `isSelf` is now
   white-with-dark-text, the other party is navy-with-white-text.
2. **Chat background was the app's usual white/mist**, but the mockup uses
   a distinct muted slate-gray (`#AEB6C4`) specifically for this screen —
   like a chat "wallpaper" that reads differently from the rest of the
   app's chrome, common in messaging UIs. Set via `Scaffold.backgroundColor`
   on this screen only; nowhere else in the app uses this color.
3. **Input field was the app's default 8px-radius rectangular field**; the
   mockup's is a fully rounded pill. Overrode `InputDecoration` locally on
   this one `TextField` (border radius `AppRadius.pill`) rather than
   changing the shared theme, since every other text field in the app is
   deliberately the sharper default shape.

**Comment/Conversation → Chat, everywhere it's user-visible** — toolbar
button, requester's action button, AppBar tooltip, the Timeline tab's
per-entry description ("Comment" → "Chat message"), and the same set on
the desktop ticket detail screen (its own separate dialog-based
implementation, per the earlier mobile-only scoping decision — only the
labels changed there, not the underlying dialog-vs-dedicated-screen
structure) plus the desktop Audit Logs screen's action label ("Added
Comment" → "Sent Chat Message"). `TicketActivityAction.commented` itself
(the wire-level enum value) was deliberately left unchanged — renaming it
would mean a Firestore schema/data migration for a label-only ask, not
something either request implied.

Verified: `flutter analyze` clean (0 issues) after all of the above.

Asked to add a click-to-install icon and "make sure the web app is
consistent." Checking what installability actually looked like today
turned up a real gap: `web/manifest.json` (name "hyport", blue
`#0175C2` theme) and every icon file (`web/favicon.png`,
`web/icons/Icon-*.png`, including the maskable variants) were still
`flutter create`'s default template output — the literal Flutter logo,
never swapped for this app's real branding despite the in-app UI, splash
screen, and native Android launch screen all being rebranded already (see
entries below). Anyone installing the PWA before this would have gotten a
generic blue Flutter icon and the name "hyport" on their home screen —
about as inconsistent with "Oracle Hyperion Support Centre" as it gets.
Regenerated `favicon.png` and all four `icons/Icon*.png` sizes (192/512,
plus maskable variants with extra safe-zone padding per the maskable-icon
spec) from the same real Coat-of-Arms asset already used as the app's logo
everywhere else (`assets/images/mof_logo.png`), composited on the app's
actual navy (`#0B3578`) rather than left on white — via a one-off Pillow
script, not committed as a build step since this only needs to run again
if the source logo changes. Updated `manifest.json` (real name/short_name/
description, navy theme+background color) and `index.html` (page title,
description meta, apple-mobile-web-app-title, and a new `theme-color` meta
tag that didn't exist before) to match. Deliberately left Android's own
launcher icon (`android/app/src/main/res/mipmap-*/ic_launcher.png`) alone
— it has the exact same unbranded-Flutter-logo problem, but the ask was
specifically about the web app; flagging it here since it's the same bug
in a different place.

**Install button**: Chrome/Edge fire a `beforeinstallprompt` event when a
site meets PWA-installability criteria (valid manifest + service worker +
HTTPS, all already true here); there's no Dart-native API for it, so
`web/index.html` gained a small JS bridge (`window.hyportPwaInstall`) that
captures the event, exposes `available`/`installed` flags, and an async
`hyportPwaInstallPrompt()` that triggers the native browser prompt and
resolves with the user's choice. `lib/core/services/pwa_install.dart` picks
between a real `dart:js_interop`-backed implementation (web) and a no-op
stub (everywhere else) via the standard `dart.library.js_interop`
conditional export — chosen over the older `dart:js`/`dart:js_util` because
this app's own `flutter build web` already reports a passing Wasm dry run,
and `js_util` isn't available under the Wasm compile target while
`js_interop` is, so this stays forward-compatible if the project ever
switches. `PwaInstallButton` polls `PwaInstall.canInstall` on a 1s timer
(the bridge is a plain object, not something Dart can subscribe to) and
renders nothing at all — not a disabled button — until the browser actually
offers an install (so Safari/Firefox visitors, where this event doesn't
exist, never see a dead button).

**Placement, for the "consistent" half of the ask**: this app has two
completely separate shell widgets — `AppShell` (mobile bottom-nav chrome)
and `DesktopShell` (back-office sidebar+top-bar chrome, ≥900px) — chosen
per request by `ResponsiveScreen`, and neither one has a single shared
top bar that every individual screen's own `Scaffold`/`AppBar` sits inside
(each screen builds its own). Rather than touch every screen file, the
button is added once at each shell level: a small floating pill
(`PwaInstallButton()`, positioned above the bottom nav bar) in `AppShell`,
and a compact icon button next to the notification bell in `DesktopShell`'s
`_TopBar`. Between the two, it's reachable from every authenticated route
regardless of which chrome renders — deliberately not added to the pre-auth
Welcome/Login pages, which felt like the wrong moment to ask a first-time
visitor to install anything.

**Verification**: `flutter analyze` clean, `flutter build web --release`
succeeds (including its own Wasm dry run — the `js_interop` choice above is
confirmed compatible, not just theoretically), and a fresh headless-browser
boot of the built output shows the real Welcome screen with zero console
errors. `beforeinstallprompt` itself is a real-Chrome-only signal that
generally doesn't fire reliably against a plain local static server in a
headless test harness (it factors in engagement heuristics beyond just
"manifest is valid"), so the install button's actual on-click behavior
wasn't observed firing end-to-end here — the manifest/icon/meta changes and
the bridge code are all independently verifiable and correct, but treat the
literal "does tapping Install produce a real browser install dialog" as
unconfirmed until tried on the deployed site in real Chrome.

## Dedicated Chat screen (replacing the Conversation tab) + Knowledge Base restyle

The user shared two more mockup screens: a dedicated Chat/Conversation UI
(chat-partner header with avatar/role/online status, call + menu icons,
image message bubbles, persistent input bar) and the Knowledge Base screen
(2-column category grid with per-category article counts, a Popular
Articles list with "View All"). Confirmed both structural forks via
AskUserQuestion before building: a real dedicated chat screen rather than
restyling the existing tab in place, and keeping all 12 ticket categories
in the KB grid (styled like the mockup's 6) rather than only showing the 6
pictured.

**New Chat screen replaces the old Conversation tab + popup dialog
entirely**, not just adds to it — leaving both alive would have meant two
different UIs writing to the same comment stream, which is the kind of
half-finished duplication this project avoids elsewhere. `ticket_detail_
screen.dart`'s TabBar drops back to 3 tabs (Timeline/Details/SLA); the
"Add Note" toolbar button, the requester's "Comment" button, and a new chat
icon in the AppBar all push the new `/tickets/:id/chat` route instead.
`_ConversationTab` and `_showCommentDialog` were deleted rather than left
as dead code.

**Chat partner resolution**: whichever side of the conversation the viewer
*isn't* — a requester sees the assignee (or "Awaiting assignment" / a
generic Support Team header if nobody's assigned yet, since there's no
real person to name), any support-side viewer sees the requester (always
resolvable, `createdBy` is required on every ticket). Online status reuses
the existing `AppUser.isRecentlyActive` (5-minute-recency heuristic, see
the Admin Mobile App entry below) rather than inventing a second presence
signal.

**Image messages**: `TicketActivity` gained an optional `attachmentUrl`
field (no `firestore.rules` change needed, same reasoning as the ticket
Impact/Affects fields above). Upload goes through the same
`firebaseStorageProvider` path as ticket attachments, with the same
non-fatal fallback — if Storage isn't provisioned, the text still sends
and the user gets an honest message rather than a blocked send. One
simplification from the mockup: the mockup shows an attached screenshot
and a follow-up caption ("Please find attached.") as two separate message
bubbles; this app sends them as one bubble (image + caption together) per
send action, rather than silently splitting one user action into two
Firestore writes.

**Call icon stays decorative** — this app has no telephony integration
(no `url_launcher` dependency, confirmed before building), consistent with
the existing phone icon on the Requested-By card in Ticket Detail, which
has always been tooltip-only. Tapping it now shows an honest snackbar
("Calling isn't available yet") rather than doing nothing silently, since
it's a much more prominent icon here than the small card affordance it
mirrors.

**Knowledge Base**: replaced the horizontal-scroll category list with a
2-column grid matching the mockup's tile style (icon, label, real
per-category article count computed from the currently-visible article
set) — kept all 12 `TicketCategory` values rather than the 6 pictured, per
the confirmed answer, so nothing becomes browse-unreachable. Search hint
copy updated to match ("Search articles, guides..."), Popular Articles
gained a "View All" link (scrolls to the existing "All Articles" section
below via `Scrollable.ensureVisible` — there's no separate full-popular-
list screen to link to, and building one wasn't asked for) and
mockup-style view-count formatting (`_compactViews`: "2.3k views" instead
of a raw integer).

**Verification**: `flutter analyze` clean (0 issues) and `flutter build
web --release` succeeds. Not re-verified live against the real backend for
the same reason as the entry above (Flutter's CanvasKit web renderer
doesn't expose an automatable DOM in this headless sandbox) — same
recommendation stands: a manual pass through the new Chat screen and KB
grid before treating this as fully proven in practice.

## Ticket-creation wizard and ticket-management screens rebuilt to match a new mockup poster

The user shared a mockup poster covering two flows not previously matched
pixel-for-pixel: "Ticket Creation Flow" (5 wizard steps) and "Ticket
Management" (My Tickets, Tickets-Filters, Ticket Details Summary, My Closed
Tickets — mobile screens only, matching how every prior mockup pass in this
log scoped to what the given poster actually covers). Confirmed scope
up front via AskUserQuestion rather than assuming: auto-derive the ticket
title instead of keeping a typed Title field, rebuild filtering as a
full-page multi-select screen instead of the old single-select bottom
sheet, add a real SLA tab to Ticket Detail, and give Closed Tickets its own
screen. All four were approved.

**New ticket fields, not previously in the data model.** The mockup's
Step 3 ("Impact & Priority") introduces two concepts `Ticket` didn't have:
an Impact level (Low/Medium/High) and whether the issue affects "Only Me"
or "Multiple Users". Added `TicketImpact` (`core/models/enums.dart`) and
`Ticket.impact`/`Ticket.affectsMultipleUsers`, both with safe defaults
(`medium`/`false`) on `fromMap` so every ticket created before this change
still parses. No `firestore.rules` change was needed — the `create` rule
checks specific required fields, it doesn't allowlist a fixed field set, so
adding new ones to the create payload doesn't touch the security boundary.

**Title is no longer typed by the user.** Mockup Step 2 ("Describe Your
Issue") is a single text box — no Title field, and Step 1 is a flat
category list with no sub-category picker. Rather than removing
`Ticket.title` (ticket-list rows, notifications, etc. all key off it), it's
now derived from the description — first sentence, trimmed to ~70 chars
(`deriveTicketTitle` in `new_ticket_screen.dart`). `subCategory` is still a
required field/param everywhere (unchanged schema), the wizard just always
passes `''` now — matches how the subcategory badge in Ticket Detail was
already conditional on non-empty, so nothing breaks, it just stops being
populated going forward.

**Filters became multi-select, which collides with a real Firestore limit.**
The mockup's Filters screen has checkboxes, not single-select dropdowns, for
both Status and Priority. Firestore only allows one `whereIn` clause per
query — so `TicketRepository.watchTickets` applies the Status set
server-side (`whereIn`) since that's the more heavily-used filter (the tab
chips), and applies the Priority set client-side on the returned page. This
means a heavy priority filter combined with a large ticket volume could
return fewer than a page's worth of visibly-matching tickets even though
more exist further back — an acceptable approximation at this app's scale,
not correct for arbitrarily large result sets. Status checkboxes are five
labeled groups (Open/In Progress/Pending User/Resolved/Closed) covering all
seven `TicketStatus` values with no gaps or overlaps — "Pending User" maps
to `{assigned, reopened}` (nothing in the existing model tracks "waiting on
the requester" more precisely than that). The mockup's Priority checkboxes
only show High/Medium/Low; Critical was kept anyway (ordered first) since
dropping it from the filter UI would make critical tickets unfilterable — a
real functional gap, not just a style simplification.

**Review step keeps the description even though the mockup's review card
doesn't show it.** Screen 12's review card lists only Category/Impact/
Priority/Affects. Dropping the actual issue text right before final submit
would be a real regression — a requester couldn't proofread what they're
about to file — so it's shown underneath those rows, a deliberate addition
beyond strict 1:1 matching.

**Ticket counts on My Tickets are approximate.** The tab chips (All/Open/
In Progress/Resolved/Closed) show live counts, but they're computed from
the same `ticketPageSize`-capped (20) query the list itself already uses,
not a dedicated aggregation query — consistent with the page-size
constraint the rest of this list already lived with before this change.
Tapping "Closed" now pushes the new dedicated Closed Tickets screen instead
of filtering in place, per the confirmed scope.

**Added composite Firestore indexes** for `status`+`createdAt` and the
role-scoped `institutionId`+`status`+`createdAt` / `createdBy`+`status`+
`createdAt` combinations the new Status `whereIn` filtering needs
(`firestore.indexes.json`). Following this project's own established
pattern (see the Enterprise Web Dashboard QA entry below), combinations
involving `category` equality *and* a Status filter simultaneously aren't
pre-indexed — if that specific combination gets hit in practice, Firestore's
error message names the exact missing index and it can be added reactively,
same as every other index gap found in this project so far.

**Verification**: `flutter analyze` clean (0 issues) and `flutter build web
--release` succeeds. Served the release build locally and drove it with a
headless Playwright/Chromium session — the Welcome screen renders correctly
(real illustration, copy, buttons) with zero console errors, confirming the
app boots cleanly end-to-end with all the changes above in the build.
**Not verified**: a full interactive click-through of the new wizard/
filters/SLA-tab/Closed-Tickets screens. Flutter's CanvasKit web renderer
doesn't expose an automatable DOM by default; enabling its semantics
placeholder (the standard trick) only materialized an ARIA node for the
placeholder itself, not the rest of the widget tree, in this headless
environment — so role/text-based Playwright locators couldn't find the
Login/wizard buttons to drive the flow. Recommend a manual pass (or a
proper `flutter drive`/integration-test run, which talks to the widget
tree directly instead of the DOM) before relying on this being fully
correct in practice, same honesty standard as every other unverified change
logged in this file.

Deployed on request: `firebase deploy --only hosting,firestore:indexes`
(hosting URL unchanged: https://hyport-a1c90.web.app) and a fresh `flutter
build apk --release` (not itself distributed anywhere, just built).

## Bottom-nav icons swapped to real assets; rest of the icon set left alone

Asked directly whether all 28 files in `ASSETS.zip` had been used —
they hadn't (only 7: logo, background, 5 illustrations). Went through
the remaining 21 and made a deliberate call on each rather than using
them indiscriminately:

- **Used**: Home/Tickets/Notifications/Knowledge Base/Profile bottom-nav
  icons (`11.png`, `8.png`, `13.png`, `9.png`, `14.png`) — persistent
  chrome on every mobile screen, highest visual-impact asset in the set.
  These are single two-tone glyphs, not outline/filled pairs like
  Material's, so selected vs. unselected is now opacity-based (1.0 vs.
  0.45) rather than icon-swapping — `app_shell.dart`'s `_tabButton`.
  Fixed a pre-existing cosmetic wrap ("Notifications" → two lines) while
  in there — shrank the tab label to 9.5px, `softWrap: false`.
- **Not used, deliberately**:
  - The 6 category-tile icons (`16.png`–`21.png`) — there are 12
    `TicketCategory` values and only 6 icons; using them for some
    categories and Material icons for the rest would look like a bug,
    not a feature.
  - The FAB plus (`12.png`) — it's a flat gold circle with no border
    ring, but every mockup screen (and the current code) shows the FAB
    with a white ring around it. Swapping in the asset as-is would
    regress that detail; there's no way to add the ring back without
    just redrawing the circle anyway, which is what the code already
    does.
  - The filter icon (`26.png`) — rendered white, meant for a dark
    surface. Every current filter-button usage is on a light AppBar; it
    would be invisible.
  - The loading spinner (`22.png`) — `BrandedLoader` is already a
    custom-animated gradient-ring `CustomPainter` explicitly built
    earlier to match this same reference graphic. The static PNG would
    be a downgrade (no animation), not a fix.
  - Search icon (`15.png`) — near-pixel-identical to
    `Icons.search_rounded` already in use across 11 files; swapping it
    is all cost (11 files touched) for no visible difference.

Verified live via Playwright (mobile width, real login): both
unselected (dimmed) and selected (full-opacity, bold, navy label) states
render correctly, no console errors. Deployed both platforms.

## OTP Verify screen rebuilt to match the mockup; primary button casing made consistent

Re-checking the auth flow against the reference poster surfaced the OTP
Verify screen as the furthest off: headline said "Two-Factor
Verification" instead of "Verify Your Account"; the code entry was a
single 6-character text field instead of 6 individual boxes; there was no
resend countdown; and the app bar carried both a title and a separate
"Sign out" text action the mockup doesn't show (just a bare back arrow).
Rebuilt `otp_verify_screen.dart`: 6 separate `TextField` boxes with
auto-advance-on-type and backspace-to-previous-box (handles a pasted
6-digit code landing in one box too), a real 45-second resend cooldown
(`Timer.periodic`, client-side only — no backend rate-limiting exists to
back it), back-arrow-only header that signs out on tap (there's nowhere
else "back" can mean from a screen the user can't otherwise leave), and
"VERIFY" in caps. Subtitle stays honest rather than copying the mockup's
"sent to {email}" claim verbatim — codes aren't emailed yet (see
OtpRepository's doc comment) — so it reads "Enter the 6-digit code for
{email}" instead, with the existing gold banner still disclosing the
on-screen-display situation plainly.

Also normalized primary auth-button label casing to match the mockup
throughout: "SEND RESET LINK", "RESET PASSWORD", "SUBMIT REQUEST" were
title-case in code but all-caps in every reference screen (LOGIN already
matched). Left "Back to Login" as a plain sentence-case link, matching
the mockup's treatment of it as secondary, not a primary CTA.

Verified live via Playwright (mobile width, real 2FA toggle + sign-out +
re-login round trip): headline, illustration, honest subtitle, 6-box
input with auto-advance focus highlighting, and the disabled VERIFY state
all render correctly. The one test wrinkle — the resend countdown showed
as already-expired in a screenshot — was the test script's own
accumulated retry delays (~26s of failed-click backoff before that
screenshot) outpacing nothing but itself, not a code issue; the countdown
field defaults to and resets to 45 on every generate() call.

## Native Android splash invisible on API 31+ — `values/styles.xml` alone isn't enough

The branded `launch_background.xml` splash (navy + crest) was reported as
not appearing on a real device. Root cause: Android 12 (API 31) replaced
the old windowBackground-drawable splash mechanism with its own native
SplashScreen API, and it does **not** honor a plain `LaunchTheme` override
in `values/styles.xml` — on any API 31+ device (i.e. most phones sold
since ~2021) it ignores `android:windowBackground` entirely for the
launch moment and shows its own default (just the launcher icon on a
plain background) unless the theme explicitly sets
`windowSplashScreenBackground` / `windowSplashScreenAnimatedIcon`. Added
`values-v31/styles.xml` with those attributes (navy background, the same
crest drawable, matching icon-background color so there's no visible seam
around it). `values/styles.xml` and `drawable-v21/launch_background.xml`
stay as the fallback for API <31. Removing "Login with Microsoft" (button
+ divider) from `login_screen.dart` happened in the same pass — the app
never had real Microsoft SSO configured, just a placeholder that showed a
"not configured yet" snackbar.

## Auth CTA buttons weren't full-width; bottom-nav labels didn't match mockup by role

Continuing the mockup-matching pass, live-testing the auth flow with
Playwright at mobile width surfaced a concrete bug: clicking where the
LOGIN button visually should be (full card width, per the mockup and per
`WelcomeScreen`'s buttons) did nothing — because `login_screen.dart`'s
`FilledButton` had no `SizedBox(width: double.infinity)` wrapper, so it
sized to its text and rendered as a small pill on the left rather than a
full-width button. Same gap existed on every other primary auth CTA:
Forgot Password's "Send Reset Link", OTP Verify's "Verify", Reset
Password's "Reset Password" and "Back to Login", and Request Access's
"Submit Request" and "Back to Login" — none were wrapped, all fixed the
same way.

Also fixed: the bottom-nav bar's Home/Notifications labels didn't switch
per role. The mockups use different words for the same two destinations —
User Mobile App (Phase 3) says "Home" / "Notifications"; Admin Mobile App
(Phase 4) says "Dashboard" / "Alerts" for the identical tabs — but
`app_shell.dart`'s shared icon map only had one hardcoded label per path
("Alerts" for both, inherited from whichever mockup was referenced last).
Added a `_supportLabelOverrides` map so back-office roles see "Dashboard"/
"Alerts" and everyone else sees "Home"/"Notifications", matching each
mockup exactly.

Verified live: Welcome → Login → (OTP, when 2FA is on) → Coordinator
Dashboard, Ticket Queue, Ticket Detail, and the drawer nav all screenshot-
matched their mockups closely. Rebuilt and redeployed both platforms.

## Branded splash on every platform + fixed 9 routes that showed raw mobile UI on desktop web

Two asks: (1) a consistent branded splash screen everywhere, not just
inside the already-authenticated Dart `SplashScreen` widget; (2) audit why
desktop web sometimes showed "the mobile app" instead of the Enterprise
Web Dashboard chrome.

**Splash, before the Dart engine even paints:**
- **Android**: the default Flutter template ships `launch_background.xml`
  as a plain white `<item android:drawable="@android:color/white" />` —
  real users would see a white flash, then the navy `SplashScreen` widget,
  a jarring double-splash. Replaced both `drawable/` and
  `drawable-v21/launch_background.xml` (v21 is what actually applies on
  real API21+ devices — easy to fix only the non-v21 one and have nothing
  change) with navy background + the real Coat of Arms, matching
  `SplashScreen` exactly. AAPT rejected a raw `#0A1B3D` string directly on
  `android:drawable` ("incompatible with attribute drawable (attr)
  reference") — needs a proper `@color/` resource, not an inline hex
  string in that position; added `values/colors.xml`.
- **Web**: `flutter_bootstrap.js` shows nothing at all until the engine
  boots — on a slow connection that's a blank white tab for several
  seconds. Added a plain HTML/CSS loading screen directly in
  `web/index.html` (navy background, real crest via a copy of the logo at
  `web/splash_logo.png`, same "ORACLE HYPERION SUPPORT CENTRE" text),
  removed via the documented `flutter-first-frame` window event once
  Flutter's actual first frame paints — no flash of unstyled content, no
  dependency on the Flutter engine having loaded to look branded.

**9 routes had zero desktop treatment** — no `ResponsiveScreen`, no
`DesktopShell`, just the mobile widget's own `Scaffold`+`AppBar` rendered
directly at whatever the browser's width happened to be. For back-office
roles on desktop web this meant clicking the bell icon, the profile
avatar, "New Article," "Assign," or "Add User" replaced the entire
Enterprise Dashboard chrome (sidebar, top bar) with a narrow phone-styled
screen stretched or left-pinned across a 1440px browser window — visually
indistinguishable from "the mobile app accidentally embedded in a giant
blank page." Fixed `/notifications`, `/profile`, `/tickets/:id/assign`,
`/knowledge-base/new`, `/knowledge-base/:id`, `/settings`, `/system-status`,
and `/admin/users/new` the same way the rest of the app already handles
this (`/tickets/:id`, `/admin-settings/sla`, `/reports/:type`, etc.):
wrapped in `ResponsiveScreen` with the desktop variant embedded inside
`DesktopShell`.

Since every one of these screens already had its own `Scaffold`+`AppBar`
(needed for the mobile layout), embedding them as-is inside `DesktopShell`
would have shown two stacked title bars (DesktopShell's + the screen's
own). Added a `bool embedded` constructor param to each
(`NotificationsScreen`, `SettingsScreen`, `SystemStatusScreen`,
`AssignTicketScreen`, `ArticleDetailScreen`, `ArticleEditorScreen`,
`AddUserScreen`) — when true, the screen returns just its body content
(no `Scaffold`/`AppBar`); the mobile call site is unchanged.
`ProfileScreen` has no `AppBar` of its own, so it only needed centering +
a max-width constraint, no new param. `NewTicketScreen` is a special case
— back-office roles never create tickets (Section 3), so it isn't wrapped
in `DesktopShell` at all; just centered + width-capped so it doesn't look
broken if a requester-side user (who always gets the mobile UI, any
viewport width) opens it on a wide browser.

Verified live via Playwright: Notifications, Profile, Settings, System
Status, and New Article (via the desktop Knowledge Base screen's "New
Article" button) all now render inside the sidebar+top-bar chrome with no
duplicate headers and no console errors. Deployed both platforms
(`firebase deploy --only hosting`, fresh `flutter build apk --release`).

## Real brand assets integrated; auth flow rebuilt to match mockups pixel-closely

Found `hyperionsupportui.zip` and `ASSETS.zip` sitting unextracted in the
project root — the actual reference mockup posters (8 images, all phases)
and the real design files (Ghana Coat of Arms, dark hex-link background
texture, and 5 character illustrations) that earlier sessions built vector
approximations for because the real files weren't available yet (see the
"Rebrand" entry below). Extracted both, cataloged all 26 numbered assets,
and used the ones with a clear 1:1 mockup match:

- `assets/images/mof_logo.png` — the real Coat of Arms, replacing
  `Icons.account_balance_rounded` on Splash, the desktop Login hero panel,
  and the desktop sidebar (`desktop_shell.dart`). Left untouched:
  Institutions list-row icons (generic "this is a building" glyph, not the
  ministry mark — a different semantic use the mockup itself doesn't
  brand with the crest either).
- `assets/images/bg_hex_pattern.png` — the real background texture,
  replacing `hex_pattern.dart`'s hand-painted `CustomPainter`
  approximation. Same low-opacity-overlay API (`HexPatternBackground`),
  just swapped what paints it.
- 5 character illustrations (agent-at-laptop, phone-with-OTP,
  padlock+envelope, shield+checkmark, bank+plus-badge) replacing the
  icon-in-a-colored-circle placeholders on Welcome/OTP-Verify/
  Forgot-Password/Reset-Password/Request-Access respectively.

**Built the Welcome screen (mockup screen 2) — it didn't exist at all.**
The app went straight from Splash to Login; the mockup's intro screen
(illustration, headline, 3 feature bullets, dot indicator, Login/Request
Access buttons) had never been built. Added `welcome_screen.dart` and
wired it into `app_router.dart` as the new pre-auth landing page (added
`/welcome` to `preAuthPaths`, changed the not-authenticated fallback from
`/login` to `/welcome`) — Splash → Welcome → Login now matches the
mockup's actual flow.

**Real bug found via this same testing, not fixed (out of scope for a UI
pass, flagging for a dedicated fix)**: a cold page load/hard-refresh
directly to any pre-auth path (`/login`, `/reset-password?oobCode=...`,
etc.) gets silently redirected to `/splash` by the router's
`authState.isLoading` branch (`return onSplash ? null : '/splash'`), and
once auth resolves, the final `if (onSplash || onPreAuthPath) return
'/home'`-adjacent logic sends them to the not-authenticated fallback
(`/welcome`) instead of back to the page they actually requested — losing
the original URL, including any query parameters. This means a **password
reset email link, opened cold (not already logged in), currently loses its
`oobCode` and dumps the user on Welcome instead of the Reset Password
form.** Pre-existing (same bug shape existed before this session, just
landed on `/login` instead of `/welcome`), reproduced live via Playwright
while testing this pass, not fixed here since it needs the redirect logic
to remember and restore the pre-loading location rather than a one-line
tweak — worth a dedicated fix soon given the password-reset-link impact.

Deployed: `flutter build web --release` → `firebase deploy --only
hosting` (https://hyport-a1c90.web.app) and a fresh `flutter build apk
--release`.

Not yet attempted in this pass: matching the remaining ~40+ mockup
screens (dashboards, ticket screens, admin screens across all 3 phases)
screen-by-screen — this pass covered the shared auth flow only, since
it's common to every app surface and was furthest from the mockups
(missing a whole screen). The icon set's other ~20 small assets (bell,
tickets, category tiles, etc.) also weren't swapped in — existing Material
icons already read close enough at that size that the churn didn't seem
worth it versus the illustrations/logo/background, which were the
visibly-approximated items called out explicitly in the "Rebrand" entry
below.

## RBAC review ahead of testing: one real functional/security bug, two rule-vs-UI mismatches

Asked to check the whole RBAC surface — every role check in
`firestore.rules`, `core/models/enums.dart`'s `isSupportSide`/
`hasBackOfficeAccess` split, and every screen/route that gates on them —
before testing starts. Traced every role (`mda_user`, `focal_person`,
`support_coordinator`, `functional_lead`, `technical_lead`,
`vendor_support`, `pfm_management`) through ticket read/write, ticket
activity, users, institutions, config, knowledge base, and route guards.
Most of it held up (see below); found three real issues:

1. **Assigning a ticket to Vendor/Specialist via plain "Assign" silently
   orphaned it.** `AssignTicketScreen` (shared by mobile and desktop —
   both "Assign"/"Reassign" actions push the same `/tickets/:id/assign`
   route) sourced its officer picker from `assignableUsersProvider`
   unfiltered, which includes `vendor_support`. `TicketRepository.
   assignTicket()` only ever sets `assignedTo`, never `escalationLevel` —
   only the separate `escalate()` (used by the dedicated "Escalate to
   Vendor/Specialist" dialog) sets both together. But a vendor's read
   access (`firestore.rules`) and their ticket-queue query
   (`TicketRepository.scopedQuery`) both require `escalationLevel == 2`,
   not just `assignedTo == uid`. Net effect: a Support Coordinator plain-
   assigning a ticket straight to a vendor (a perfectly natural thing to
   try — the picker offered it) would produce a ticket the vendor could
   never see, in their own queue or by any read path. Fixed by excluding
   `vendor_support` from `AssignTicketScreen`'s candidate list — Vendor is
   now reachable only through Escalate, which sets both fields atomically.
   Also tightened the mirroring gap this exposed in `firestore.rules`:
   Vendor's ticket-`update` branch (the one that lets them mark a ticket
   resolved) checked `assignedTo == uid` but not `escalationLevel == 2`,
   unlike the read rule right above it — so even after the client fix, a
   ticket "assigned" to a vendor at the wrong escalation level via a
   modified client could still have been resolved by them, per this
   project's own stated principle that the rule shouldn't rely on the
   client. Added the same `escalationLevel == 2` check there too.

2. **`institutions` and `config` (SLA policy, general settings) writes
   were allowed for any back-office role in `firestore.rules`
   (`isSupportSide()`), but every actual entry point — the Institutions
   screen, SLA Management, and the desktop Settings screen's General tab —
   lives under `/admin-settings` or `/admin/institutions`, both restricted
   by `app_router.dart`'s `adminOnlyPaths` to `role == pfm_management`
   exactly. Confirmed there's no other writer into either collection
   client-side (`grep` for `collection('config')` / institution writes).
   Not exploitable through the app's own UI, but a Functional/Technical
   Lead or Coordinator with a modified client could have created
   institutions or rewritten the SLA policy the app never gives them a
   way to reach. Narrowed both rules to `role() == 'pfm_management'` to
   match the UI's actual (and apparently intentional, given how
   specifically `adminOnlyPaths` is scoped) access model.

Deliberately **not** changed: the ticket `update` rule's broad
`isSupportSide()` grant (all four back-office roles can write any ticket
field, including PFM-Systems Management, even though the UI never gives
Management an assign/escalate/resolve/close button). Unlike institutions/
config, this is a many-role, many-action rule underpinning the whole
ticket workflow — narrowing it risks breaking a legitimate Management
action this review can't fully rule out from static reading alone.
Flagged for a judgment call rather than changed unilaterally.

Confirmed correct, not touched: `isSupportSide` vs. `hasBackOfficeAccess`
usage is consistent everywhere it matters (`ticket_repository.dart`'s
`scopedQuery` checks `vendor_support` before falling through to the
broader `isSupportSide`, so vendor never gets unscoped visibility; the
Knowledge Base edit FAB uses `hasBackOfficeAccess` on both mobile and
desktop, matching the Vendor-scope-creep fix from earlier in this log);
`adminCreateUser`'s `pfm_management`-only check; and every button in
`ticket_detail_screen.dart`'s admin toolbar (Start Work/Resolve/Close) is
gated by exact role + assignee, not just "is support side." Also verified
`app_router.dart`'s `adminOnlyPaths = ['/admin']` — via plain string-
prefix `startsWith`, not path-segment matching — happens to also cover
`/admin-settings*` (since `'/admin-settings'.startsWith('/admin')` is
true), which is why Settings ends up `pfm_management`-only even though it
isn't nested under `/admin/`. Correct today, but fragile: renaming that
route to anything else starting with `/admin` (or not) would silently
change its access level. Worth a path-segment-aware check
(`location == '/admin' || location.startsWith('/admin/')`) if this file
gets touched again, but not changed here since it isn't broken.

All three fixes are in `firestore.rules` (deployed) and
`assign_ticket_screen.dart` (compiles clean, `flutter analyze` — 0
issues).

## Enterprise Web Dashboard (Phase 5) QA pass: two real regressions found and fixed

Picked up mid-build: a previous session had already built the full desktop
web experience (Phase 5 mockup screens 30-40) — `DesktopShell` (sidebar +
top bar, `core/routing/desktop_shell.dart`), `ResponsiveScreen`
(`core/responsive.dart`, 900px breakpoint, gated to `hasBackOfficeAccess`
roles only — Vendor stays on the mobile UI at any width) and desktop
versions of Dashboard, Tickets, Ticket Detail, Assignments, SLA Monitoring,
Analytics, Reports, Audit Logs, Knowledge Base, Users, Institutions, and
Settings — but it hadn't been QA'd against the real backend or written up
here yet. `flutter analyze` was clean, but per this project's own pattern
(see every other entry below), a clean analyzer run isn't the same as a
working app.

Verified via a real Playwright/Chromium session against a `flutter build
web --release` bundle (the `flutter run -d web-server` dev server's
DDC/DWDS bootstrap never completed in this headless sandbox — release
build sidesteps that entirely and is closer to what actually ships anyway),
logged in as `management@hyport.test` (`pfm_management`, full nav) at a
1440×900 viewport. Found two real regressions, both introduced by the
unlogged Phase 5 work, both fixed and redeployed:

1. **Audit Logs screen: `permission-denied` for every role.**
   `AuditLogRepository.watchRecent()` runs a `collectionGroup('activity')`
   query across every ticket's `activity` subcollection (Phase 5 mockup
   screen 40 — see that file's own doc comment for why this is scoped as
   ticket-lifecycle events only, not a full system audit trail). The
   existing per-ticket `allow read` rule at
   `tickets/{ticketId}/activity/{activityId}` only ever governed direct,
   ticket-scoped reads — Firestore requires a separate rule using
   `match /{path=**}/activity/{activityId}` for a collection-group query to
   be permitted *at all*, and nothing like that existed. Fixed by adding
   that rule, scoped to `isSupportSide()` — the same set of roles as the
   per-ticket rule (deliberately excludes Vendor, matching the desktop nav
   guard's `hasBackOfficeAccess`), so this can't be used to widen Vendor's
   ticket-scoped access into a full cross-ticket activity feed. Deployed
   (`firebase deploy --only firestore:rules`) and re-verified live: the
   screen went from a bare error string to real data (assignment/creation/
   escalation/status-change entries across all seeded tickets, newest
   first).

2. **Ticket Detail's Timeline tab: broke everywhere, not just desktop.**
   Same root cause's other half. Supporting the collection-group query
   above also needs a `firestore.indexes.json` `fieldOverrides` entry for
   `activity.timestamp` (Firestore field-override entries are declarative
   overrides, not additive — a field only gets the exact index variants
   listed). The entry that shipped listed only `COLLECTION_GROUP`-scope
   indexes, which **replaced** Firestore's default automatic
   `COLLECTION`-scope single-field index for that same field — the one the
   pre-existing, previously-shipped, already-tested `TicketRepository.
   watchActivity()` depends on (`tickets/{id}/activity` ordered by
   `timestamp`, used by both the mobile Timeline tab and this desktop one).
   Confirmed by reproducing it live: opening any ticket's Timeline tab threw
   `[cloud_firestore/failed-precondition] The query requires a
   COLLECTION_DESC index for collection activity and field timestamp` —
   a real, user-visible break in a feature that had nothing to do with the
   Enterprise Web Dashboard, caused by a side effect of adding it. Fixed by
   adding the `COLLECTION`-scope ASC/DESC variants back alongside the
   `COLLECTION_GROUP` ones in the same override entry, so both query shapes
   are covered. Deployed (`firebase deploy --only firestore:indexes`).
   **Not re-verified visually**: outbound network to Google's APIs
   (`firestore.googleapis.com`, `identitytoolkit.googleapis.com`) went down
   from this environment immediately after deploying this fix (`curl`
   timeouts on both, and the already-working Admin-SDK `scripts/` tooling
   started failing with `ECONNRESET` at the same moment) — an environment
   outage, not an app issue, confirmed by the earlier-in-session Playwright
   runs succeeding cleanly on identical code paths. The fix itself is
   mechanically certain (the exact missing index variant was named in the
   error and is now declared), but re-open a ticket's Timeline tab once
   connectivity is back to be sure.

Screens confirmed fully working end-to-end against real data before the
outage: Dashboard, Tickets (list), Assignments, SLA Monitoring, Knowledge
Base, Reports, Analytics, Users, Institutions, Settings — plus Audit Logs
and Ticket Detail's non-Timeline tabs, post-fix. The Tickets/Users/Recent-
Tickets tables' rightmost column appearing cut off in a screenshot at
1440px is not a bug: each is deliberately wrapped in a horizontal
`SingleChildScrollView` (confirmed in source, not just visually) — that's
what an unscrolled wide table looks like, not clipped content.

## Admin Mobile App (Phase 4) built as an expansion of the existing app, not a separate codebase

The user shared the Phase 4 "Mobile Admin App" mockup poster (10 screens:
Admin Dashboard, Ticket Queue, Assign Ticket, Ticket Details, Analytics,
Reports, Users, Institutions, Knowledge Base admin view, Settings) and
asked to proceed with it after the User Mobile App pass. Built as a real
expansion of the support-side experience already in this app (same
Firebase backend, same roles: Support Coordinator/Functional Lead/
Technical Lead/PFM Management), not a duplicate Flutter project — the
mockup is genuinely "for Support Officers," which already exist as roles
here, so a separate codebase would have meant re-building auth, data
models, and repositories from scratch for no reason.

Notable structural decisions:
- **Bottom nav changed for support-side roles**: from a plain 6-icon row
  (Home/Tickets/Dashboard/Alerts/Knowledge/Profile) to the mockup's
  4-destination-plus-center-FAB bar (Dashboard/Tickets/+/Alerts/Profile),
  matching requesters' bar shape. Analytics/Reports/Knowledge Base (and,
  PFM Management only, Users/Institutions/Settings) moved to a drawer
  reachable via the mockup's own ☰ icon — there wasn't room for 7+
  destinations in a bottom bar, and the mockup shows the hamburger icon
  precisely for this reason.
- **New real data, not fabricated stats**: `Ticket.firstRespondedAt`
  (stamped once, on first assignment) powers a genuine "First Response
  Time" metric; `AppUser.lastActiveAt` (stamped once per sign-in) powers
  real online/offline dots on the Users screen — coarse ("active in the
  last 5 minutes"), not a live presence system, but derived from real
  timestamps rather than random/fake values. `config/sla` is a real,
  admin-editable Firestore doc (per-priority target hours) that both the
  Admin Dashboard's Overdue count and Analytics'/Reports' SLA Compliance
  actually read from — changing it in Settings → SLA Management has an
  immediate, real effect elsewhere.
- **Reports has no PDF export**: same Storage blocker as attachments.
  Each report type renders live-computed data from the same ticket/user
  queries the rest of the app uses; "Recent Reports" logs which report
  types an admin viewed (`report_views`, self-scoped) rather than listing
  fake downloadable files.
- **Knowledge Base articles gained a `status`** (draft/review/published).
  Fixed a real gap this introduced immediately: the query never filtered
  by status, so every signed-in user — not just editors — could originally
  see draft/review articles. Scoped the requester-facing list to
  `published` only; editors still see everything via status tabs.
- **A real layout bug found and fixed via live QA, not code review**:
  `PercentRing` (the SLA Compliance gauge) showed a genuine 100% compliance
  as "00%". Root cause: `Stack`'s default `Clip.hardEdge` silently clipped
  the leading "1" off "100%" because the label was wide enough to overflow
  a 52px ring. Confirmed the true value independently via a direct
  Firestore query (`scripts/`) before touching the widget, since the first
  instinct — "the calculation is wrong" — would have been the wrong fix.
  A first attempt (`FittedBox` inside the `Stack`) didn't actually resolve
  it in practice; fixed for real by setting `clipBehavior: Clip.none` on
  the `Stack` directly, which unconditionally guarantees the label is
  never clipped regardless of sizing edge cases.

## Real email-OTP two-factor login, with an explicit interim delivery step

The user asked for Two-Factor Authentication (previously a disabled
"Coming soon" toggle) to be built for real, with codes delivered by email.
Real server-generated-and-emailed codes need a Cloud Function — blocked on
the same Blaze billing plan issue as Storage (confirmed still blocked this
session: `firebase deploy --only functions` fails outright asking for the
upgrade). Rather than wait or fake it, the user explicitly asked for the
code to be shown directly on-screen for now, to be "reversed" to real email
delivery once billing clears. Built accordingly:

- `AppUser.twoFactorEnabled` (self-toggleable, `firestore.rules` carve-out
  on `users/{uid}` mirroring the existing `fcmTokens` self-update pattern)
  and a new `otp_codes/{uid}` collection (owner-only read/write) holding a
  client-generated 6-digit code + 5-minute expiry.
- `OtpVerifyScreen`, gated into the router's redirect logic: if
  `appUser.twoFactorEnabled` and the session hasn't verified yet, every
  route redirects to `/otp-verify` first — including mid-session, so
  toggling 2FA on in Settings immediately requires it before anything else
  loads.
- **A real bug caught before it shipped, not after**: the "verified" flag
  (`otpVerifiedProvider`, keyed by uid) was initially `.autoDispose`. Since
  nothing ever `ref.watch`es it (only `ref.read`s from the router redirect
  and the verify screen), it would have been torn down to `false` the
  instant it was set — an infinite bounce back to the OTP screen right
  after successfully verifying. Caught by reasoning through Riverpod's
  dispose semantics before testing, not by observing the loop live. Fixed
  by making it a plain (non-autoDispose) family, with `_goRouterRefreshProvider`
  explicitly invalidating the whole family on sign-out instead — otherwise
  the same account signing back in would skip 2FA entirely on its second
  login, since a plain family never tears itself down. Verified live: sign
  out then sign back in with 2FA on correctly issues a **new** code and
  re-prompts, rather than silently letting the session through.
- Every place this is user-visible says plainly that email delivery isn't
  active yet (Settings subtitle, the on-screen code banner itself) —
  consistent with how Storage/System-Status/SSO are handled elsewhere in
  this app: real functionality with an honestly-labeled interim gap, never
  a UI that pretends to be doing something it isn't.

## Full mobile-app rebuild to match detailed Figma-style mockups (User Mobile App scope only)

The user pasted 8 detailed mockup posters covering an entire 3-app system
(User Mobile App, Admin Mobile App, Enterprise Web Dashboard — ~50 screens)
and asked for "the actual app UI" to be coded to match. Scoped this to the
User Mobile App only (Splash/Login/Forgot-Password/Request-Access, Home,
New Ticket, My Tickets, Ticket Detail, Notifications, Knowledge Base,
Profile/Settings) since that's what maps onto the existing working app;
the Admin Mobile App and Enterprise Web Dashboard are separate, unbuilt
phases — see the achieved-vs-gaps report delivered alongside this pass.

Notable additions/changes beyond pure visual restyling:
- **Real per-article view counts** (`KnowledgeArticle.viewCount`): rather
  than fabricate a "popular articles" number to match the mockup, added a
  genuine `viewCount` field incremented once per article open
  (`incrementViewCount`, fire-and-forget). Firestore rule for
  `knowledge_articles` split into `create/delete` (editor-only) vs
  `update` (editor-only for content fields, but any signed-in reader may
  bump `viewCount` alone via an `onlyFieldsChanged` carve-out — same
  pattern as the existing `users.fcmTokens` self-update rule).
- **Single-user lookup** (`userByIdProvider` / `UserRepository.watchUserById`):
  added to support a ticket's "Assigned to" card showing the assignee's
  name/role — didn't exist before since prior screens only ever needed
  lists of users, not a single lookup by id.
- **Ticket Detail restructured into tabs** (Timeline/Conversation/Details)
  without touching the existing role-based action logic (assign/escalate/
  resolve/close/reopen) or its dialogs — those were already correct and
  tested, only the surrounding layout changed. "Conversation" is a client-
  side filter of the same activity stream down to `commented` entries
  (no separate conversation collection exists), rendered as chat bubbles.
- **Found and fixed two real bugs during visual QA** (not just restyling
  issues):
  1. `SettingsScreen`'s `_SettingsSwitch` overflowed horizontally on a
     390px-wide viewport ("Two-Factor Authentication" + "Coming soon"
     badge + `Switch` didn't fit) — wrapped the label in `Flexible` with
     ellipsis. Pre-existing bug, not introduced this session, just never
     caught because nothing had linked to `/settings` before now (see
     next point).
  2. `/settings` was a dead route — built earlier in the session but never
     linked from anywhere in the nav. Added a "Settings" tile to the
     rebuilt Profile screen.
  3. New Ticket wizard's Continue button didn't reactively enable once
     the Title/Description fields were filled, because the `TextFormField`s
     had no `onChanged`/listener wired to trigger a rebuild of the parent
     step-gating state (`_canAdvance` was only ever re-evaluated on other
     `setState` calls, e.g. selecting a category). Fixed by adding
     controller listeners in `initState` that call `setState(() {})` on
     every keystroke. Caught via headless-browser click-through, not code
     review — the bug wasn't visible without actually typing into the
     fields end-to-end.
- Verified via a real Playwright/Chromium session against the live
  Firebase backend (mobile viewport, 390×844): logged in as both a
  Support Coordinator (6-tab bar incl. Dashboard) and an MDA/MMDA User
  (5-tab bar with center FAB), clicked through every rebuilt screen, and
  submitted a real ticket end-to-end (`#PFMSD-2026-000004`, confirming the
  counter continued correctly past the pre-existing `HYP-`-prefixed seed
  tickets rather than colliding with them).

## Rebrand: navy/gold palette from reference images, no source asset files available

The user pasted a set of brand reference images in-conversation (a support-
agent illustration, OTP/verification and security-themed illustrations, an
icon set, a branded loading graphic, a dark hex-pattern texture, and the
Ghana Coat of Arms) and asked for the UI to match. Chat-pasted images are
not written to the project's filesystem — confirmed nothing landed in
`assets/` — so this was done by close visual inspection rather than reading
the actual files. Changed based on that inspection:

- **Palette**: replaced the emerald-green primary with a navy-led palette
  (`AppTheme.navy`/`navyDark`/`navyDarkest` ~`#1B3B6F`) plus a vibrant
  royal-blue accent (`accentBlue` ~`#2F5FCE`, used for category/icon tiles
  — matches the reference icon set's rounded-square tile color, kept
  visually distinct from the darker hero-panel navy), gold unchanged,
  `success`/`plum` added for future use. Renamed every `AppTheme.emerald*`
  reference across 11 files via a scripted `emerald`→`navy` substitution —
  this collided with a *pre-existing*, differently-valued `AppTheme.navy`
  accent constant (duplicate declaration, wouldn't compile); resolved by
  redesigning the constant set from scratch rather than patching around it.
- **Branded loading indicator** (`core/widgets/branded_loader.dart`): a
  rotating navy→accent-blue gradient ring, replacing every full-page
  `CircularProgressIndicator` (button-inline spinners were left as plain
  white — they sit on colored button backgrounds where the gradient ring
  wouldn't have contrast).
- **Illustrated empty states** (`core/widgets/empty_state.dart`): layered
  soft-circle "blob" shapes behind a white icon disc, with an optional
  small badge circle — a vector approximation of the reference
  illustrations' "icon on organic blob, small accent badge" composition
  (e.g. the bank building with an orange plus badge), built from Flutter
  shapes rather than the actual illustration art.
- **Background texture**: a tiled hexagon-outline `CustomPainter`
  (`core/widgets/hex_pattern.dart`) at very low opacity behind the login
  screen's gradient panel, echoing the reference's dark geometric texture
  without reproducing its exact interlocking pattern.

**Explicitly not attempted**: the Ghana Coat of Arms and the detailed
character/scene illustrations (support agent at a laptop, phone with OTP,
padlock+envelope, shield+checkmark). The coat of arms is an official
national emblem — redrawing it from a chat image by eye risks an
inaccurate or inappropriate rendering of a government symbol, so the app
keeps a generic `Icons.account_balance_rounded` placeholder pending the
real file. The character illustrations are a specific commissioned/stock
art style that can't be approximated credibly with vector shapes; empty
states use the icon-on-blob treatment instead. Provide the actual image
files (dropped into `assets/images/`) to get pixel-accurate versions of
either.

## Cloud Functions written, not yet deployable (Blaze still blocked)

`functions/index.js` now has all three Day 3 functions, fully implemented:
- `adminCreateUser` — the callable `AddUserScreen` already called against a
  nonexistent function. Creates/updates the Firebase Auth account, sets
  `role`/`institutionId` custom claims, writes the `users/{uid}` Firestore
  doc, and logs to `audit_logs`. Restricted to callers whose own token has
  `role: pfm_management`. Doesn't send the password-reset email itself
  (Admin SDK can generate a reset link but can't trigger Firebase's hosted
  reset *email* — only the client SDK's `sendPasswordResetEmail` does that,
  and it works for any email regardless of who's signed in) — so
  `AddUserScreen` now calls that itself immediately after the callable
  succeeds.
- `onTicketCreated` / `onTicketUpdated` — Firestore triggers writing
  `Notification` docs (received/assigned/escalated/resolved) and pushing via
  FCM to whatever tokens are on file for the target user, per Section 7.

Still can't deploy: Cloud Functions (2nd gen) also require the Blaze plan,
same wall as Storage (see the entry below). Verified the code loads
cleanly (`node --check`, `require()` both succeed, exports the 3 expected
functions) so it's ready the moment billing clears —
`firebase deploy --only functions` from the project root.

## FCM wired client-side, degrades gracefully without a web VAPID key

Added `PushNotificationService` + `PushNotificationListener`
(`core/services/`): on sign-in, requests notification permission, gets an
FCM token, and saves it to `users/{uid}.fcmTokens` (an array — one person
can have more than one device) via a new Firestore rule carve-out that lets
a user update *only* that field on their own doc (everything else on
`users/{uid}` stays admin-managed/`allow write: if false`, per Section 5).
Foreground messages surface as a SnackBar via a global
`scaffoldMessengerKey`; tapping a notification (foreground, background, or
from terminated via `getInitialMessage()`) navigates to the ticket using
the `ticketId` in the message's data payload.

Web push additionally needs a VAPID key (Firebase Console -> Project
settings -> Cloud Messaging -> Web Push certificates), which requires
generating one in the console — nothing to automate, just a step you'll
need to do once. `webPushVapidKey` in `push_notification_service.dart` is
currently blank; until it's filled in, `getToken()` returns null on web
specifically (skips registration cleanly, no crash) while Android still
registers normally. `web/firebase-messaging-sw.js` (the background-message
service worker web push needs) is already in place either way.

Notifications will visibly do nothing end-to-end until both this and the
Cloud Functions deploy land — the pieces are independently gated (billing
vs. a console step) so whichever clears first, do that one; the app
degrades safely either way in the meantime.

## Bug found during role QA: Vendor/Specialist had scope creep beyond Section 3

`UserRole.isSupportSide` (`this != mdaUser && this != focalPerson`) was used
as a stand-in for "back-office role" in several permission checks, but it's
broader than intended: it includes `vendorSupport`. Section 3 caps Vendor at
"only sees tickets explicitly escalated to them... cannot see institutional
data outside those tickets" — no dashboard, no knowledge-base editing, no
closing tickets. Testing the Vendor account surfaced that they got a
**Dashboard tab** and would have gotten a **Close ticket** button on any
resolved ticket assigned to them.

Introduced `UserRole.hasBackOfficeAccess` (Coordinator/Leads/Management
only — mirrors `firestore.rules`' existing `isSupportSide()` function
exactly, which already excluded Vendor) and switched the Dashboard nav tab
(`app_shell.dart`), the `/dashboard` route guard (`app_router.dart`), the
knowledge-base edit FAB (`knowledge_base_screen.dart`), and the "Close
ticket" action (`ticket_detail_screen.dart`) to use it instead of the
broader `isSupportSide`. Left `isSupportSide` itself unchanged and still
used for home-screen layout choice and the new-ticket FAB visibility —
Vendor still needs the stat-card-style home (not the requester's "your
tickets" + new-ticket view, since Vendor never creates tickets), so
narrowing that shared getter would have introduced a *different* bug
(Vendor gaining a New Ticket button) rather than fixing this one.

Also tightened `firestore.rules`' vendor update branch to defense-in-depth
match: previously `isVendor() && resource.data.assignedTo == uid` permitted
changing *any* field once assigned; now it additionally requires
`onlyFieldsChanged([...])` and `request.resource.data.status == 'resolved'`
— the one action Vendor actually has. The client never offered anything
broader, but per this project's own stated principle, the rule shouldn't
rely on that.

First deploy of that tightened rule shipped with a bug of its own, caught
immediately by testing the actual Vendor resolve flow rather than trusting
the rule read-through: the allowed-fields list was
`['status', 'updatedAt', 'resolutionNotes']`, but
`TicketRepository.changeStatus` *also* sets `resolvedAt` whenever the new
status is `resolved` — so `onlyFieldsChanged` correctly saw a 4th changed
field and denied the entire write. The UI surfaced this as a bare
`[pageerror] Error` with no useful message; confirming it required checking
the ticket document directly via the Admin SDK (still `status: escalated`,
`resolvedAt: null` after the "successful-looking" dialog interaction) to
prove the write never landed. Fixed by adding `'resolvedAt'` to the allowed
list. Lesson: when hand-listing allowed fields for `onlyFieldsChanged`,
cross-check against the actual write path's field set, not against memory
of what the action "should" touch.

## Bug found during role QA: signing out and a different user signing in (same tab) served stale, dead Firestore listeners

While testing an escalation handoff (Coordinator escalates a ticket, signs
out, Functional Lead signs in to resolve it), the Functional Lead got
`permission-denied` opening the exact ticket that was just escalated to
them — even though their custom claims were verified correct (checked via
the Admin SDK and by decoding a freshly-issued ID token directly). A full
page reload fixed it immediately, which pointed at client-side state, not
the security rules.

Root cause: `ticketDetailProvider`, `ticketActivityProvider`,
`articleDetailProvider`, `articleListProvider`, `assignableUsersProvider`,
and `allUsersProvider` were plain (non-`autoDispose`) `StreamProvider`s (some
`.family`, some not), keyed independent of *who's viewing* — e.g.
`ticketDetailProvider` is keyed only by `ticketId`. Riverpod keeps a
non-autoDispose provider's stream alive for the app's entire lifetime once
created. Sequence that broke: Coordinator opens ticket X (listener created
under Coordinator's auth) → Coordinator signs out → the still-alive listener
gets re-evaluated against the rules with `request.auth == null`, fails with
permission-denied, and Firestore's JS SDK doesn't auto-recover a listener
that's already errored → Functional Lead signs in and opens the *same*
ticket X → Riverpod hands them the same cached, already-dead stream instead
of creating a new one under their auth.

`ticketListProvider` and `userNotificationsProvider` happened to dodge this
because they're keyed by something viewer-specific (the full `AppUser`, or
a uid string) — a different signed-in user is automatically a different
cache key, so they always got fresh streams. That's what limited this to
detail/single-item screens and made it easy to miss.

Fixed by adding `.autoDispose` everywhere above: Riverpod now tears down the
provider (and its Firestore listener) once no widget is watching it —
which happens naturally on sign-out, since go_router's redirect unmounts
the whole authenticated route tree — so the next time anyone watches that
same key, they get a brand-new listener under whatever auth is current.
Also applied to `authStateChangesProvider`/`currentAppUserProvider` for the
same hygiene, though those weren't implicated (they already rebuild
reactively on auth changes since nothing keys them by a stale id). This is
a real production concern, not just a testing artifact — anyone signing out
on a shared device without fully closing the tab would have hit it.

## Bug found during role QA: User vs. Focal Person ticket visibility was identical

Section 3's role table draws a real distinction: a plain MDA/MMDA **User**
"view/track[s] their own tickets", while a **Focal Person** can "view all
tickets from their institution". The initial implementation of
`TicketRepository.scopedQuery` and `firestore.rules` treated both roles
identically (institution-wide visibility for both), which would have let
any ordinary user see every other user's tickets at their institution —
a real over-exposure, not just a missing nice-to-have.

Fixed on both sides: `scopedQuery` now filters plain Users by
`createdBy == viewer.id` and only gives Focal Persons the institution-wide
`institutionId` filter; `firestore.rules`' `isFocalPerson()` check mirrors
this for ticket reads and the activity subcollection. Added a matching
`createdBy + createdAt` composite index and redeployed. Ticket
create/reopen/close rules didn't need changes — those were already scoped
to `createdBy == request.auth.uid` regardless of role.

Not implemented: Focal Person's other stated power, "validate/triage
requests before escalation," beyond visibility — the brief doesn't specify
a concrete mechanic for this (a distinct approval step? a triage status?),
and Day 2's milestone scopes assignment/escalation/status-change actions to
support-side roles only. Revisit with the PFM-Systems team if Focal Persons
need an explicit triage action beyond commenting.

## Bug found + fixed by end-to-end testing: counters rule denied the first ticket of the year

Verified the full ticket-creation loop against the real backend (seeded
accounts, headless-browser driven) and the very first ticket submission
failed with `permission-denied` on the transaction commit. Root cause: the
`counters/{counterId}` rule in `firestore.rules` read
`resource.data.count is int ? resource.data.count : 0` — but `resource.data`
on a **non-existent** document (the counter doc for a new year doesn't
exist until the first ticket) is a rules evaluation error, not a graceful
null. The ternary never got a chance to protect against it, because the
condition expression itself throws before the ternary can pick a branch —
so every rule evaluation for the first ticket of each year failed closed.

Fixed by checking `resource == null` first and relying on `&&` short-circuit
evaluation to avoid ever touching `resource.data` when the document doesn't
exist yet. Redeployed and re-verified: `mda.user@hyport.test` successfully
created ticket `HYP-2026-000001`, it appeared live on their home screen, the
Support Coordinator account could see it, and the Accra Metro user (a
different institution) correctly could not. This is exactly the kind of bug
that only surfaces by actually running the app against real rules — a code
review of the rules file alone read as correct.

## Firebase Storage deferred — Blaze plan billing not yet resolved

The real Firebase project (`hyport-a1c90`) is connected — `lib/firebase_options.dart`
has real web + Android config, and `firestore.rules`/`firestore.indexes.json`
are deployed. Firebase Storage is not yet active: as of late 2024, Google
requires a project be on the Blaze (pay-as-you-go) plan to provision Cloud
Storage at all, even for usage that stays within the free tier, and billing
setup is stuck on the account-holder's end (payment method rejected).

Since attachment upload is one part of ticket creation, not a hard
dependency, `NewTicketScreen._submit` was changed to treat attachment
upload failures as non-fatal: if `_uploadAttachments` throws (e.g. because
the Storage bucket doesn't exist yet), the ticket is still created with an
empty `attachmentUrls` list and the user sees a message explaining
attachments weren't saved, rather than the whole submission failing. Once
Storage is active, revert nothing — this behavior is correct permanently
(a flaky upload shouldn't block ticket creation either). Deploy
`storage.rules` (`firebase deploy --only storage:rules`) once billing is
sorted — the rules file is already written and unchanged.

## Firebase project connection — done

Connected to project `hyport-a1c90`. `lib/firebase_options.dart` has real
web + Android values (filled in by hand from the console's web snippet and
`android/app/google-services.json`, since the `flutterfire` CLI hit a PATH
issue in this environment — same net result). Email/Password auth is
enabled. Firestore rules + indexes are deployed. Storage is pending — see
the entry above.

## Custom claims vs. Firestore doc for role/institution

`firestore.rules` reads `role`/`institutionId` from Firebase Auth **custom
claims**, not from the `users/{uid}` document, because rules can't trust
client-writable data as the access boundary. The app's UI, however, reads
role/institution from the Firestore `users/{uid}` doc (`currentAppUserProvider`
in `core/auth/auth_providers.dart`) because custom claims aren't reactively
observable without a forced token refresh, and the Firestore doc gives
live updates if an admin changes someone's role. Custom claims are set
server-side by the `adminCreateUser` Cloud Function (Admin SDK) at account
creation — never by the client. This means: whoever builds that Cloud
Function (Day 3) must keep the custom claims and the `users/{uid}` doc in
sync on every role/institution change, or the UI and the security rules will
disagree about what a user can do.

## Admin user provisioning goes through a Cloud Function, not client SDK

The client Firebase SDK cannot create other users' Firebase Auth accounts or
set custom claims — only the Admin SDK can. `AddUserScreen` therefore calls
an `adminCreateUser` HTTPS callable Cloud Function. It's now implemented
(`functions/index.js`) but not yet deployed — see "Cloud Functions written,
not yet deployable" above. Until it deploys, the Add User screen will
compile and render but the call will fail at runtime with a "not found"
error.

## Charting library: fl_chart over Syncfusion

Section 5 said "pick whichever the team already knows." No prior team
convention exists yet, so `fl_chart` was chosen: it's free (Syncfusion's
Flutter charts require a commercial license outside their free community
tier) and has no license-key setup step, which matters for a 4-day sprint.

## Offline draft storage: Hive over sqflite

Section 6 allows either. `sqflite` has no first-class web support, and this
app must build for both mobile and web from one codebase, so `hive` (via
`hive_flutter`) was used instead. Draft tickets are stored as plain
`Map<String, dynamic>` in a dynamic `Box<Map>` rather than through a
generated `TypeAdapter`, to avoid pulling `build_runner`/`hive_generator`
into the loop for a single small record type — see
`features/tickets/data/draft_ticket.dart` and `draft_ticket_repository.dart`.

## No Freezed / json_serializable

Section 4 allows either plain `toMap`/`fromMap` or Freezed. Plain classes
were used throughout (`core/models/enums.dart` and the `domain/*.dart`
files) to avoid a `build_runner` watch step slowing iteration during the
sprint. If the team wants Freezed's immutability/union-type guarantees
later, the models are small enough to port in an afternoon.

## Ticket reference generation: client-side transaction, not a Cloud Function

`HYP-{year}-{6-digit sequence}` references are generated via a Firestore
transaction against a `counters/tickets_{year}` document
(`TicketRepository.createTicket`), run directly from the client, rather than
through a callable Cloud Function. This keeps ticket creation working
offline-first (no function round-trip) and Firestore transactions already
guarantee the sequence can't collide under concurrent writes. `firestore.rules`
restricts writes to that counter doc to exactly `+1` on the `count` field so a
client can't forge reference numbers.

## Who can provision new users (admin capability)

The concept note's 7 roles don't explicitly name who can create new user
accounts. Assumed **PFM-Systems Division / Management**
(`UserRole.pfmManagement`) is the only role that can reach the "Add User"
screen (`adminOnlyPaths` in `core/routing/app_router.dart`), since they're
the role with full oversight and no ticket-handling duties. Revisit if the
Ministry wants Support Coordinators to provision accounts too.

## Escalation routing: functional vs. technical category split

Section 3 lists issue types for Functional Leads (budget forms, workflow,
validation, reporting, Smart View) and Technical Leads (metadata, security,
business rules, Essbase, integration, environment) but Section 4's category
list doesn't map 1:1 onto that language. `TicketCategory.isFunctional` in
`core/models/enums.dart` makes the explicit mapping:
- Functional: workflow, budget_forms, reports, smart_view, data_validation,
  general_enquiry, mobile_app_issue
- Technical: access, business_rules, metadata, essbase, system_performance

This mapping drives which lead role appears as an escalation option in
`TicketDetailScreen._showEscalateDialog`. Revisit with the PFM-Systems team
if any category should route differently.

## Ticket list/detail permissions are enforced twice, deliberately

`TicketRepository.scopedQuery` (client) and `firestore.rules` (server)
encode the same institution/role scoping independently. This is intentional
redundancy, not duplication to clean up: the client-side version exists so
the UI never has to load and then hide data it isn't allowed to see, and the
rules version is what actually stops a modified client. Keep both in sync if
the access model changes — see Section 3.
