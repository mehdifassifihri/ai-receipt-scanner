# Build and live-service verification

## Glass controls — 20 October 2026

- Flutter analysis: clean; full suite: 55 passed.
- iOS native accessibility bridge and scanner integration: 2 passed on simulator.
- Ask Snap and captured-receipt visual previews: 2 passed and inspected.
- Android debug APK: built successfully; existing camera Kotlin warning remains.
- Renderer: portable grouped blur + painted rim highlights; no true refraction.
- No physical iPhone connected: real-device profile/60fps verification remains open.
- [Tuning values, package evaluation and profiling procedure](LIQUID_GLASS.md).


## Flutter architecture audit — 20 October 2026

See [the detailed audit](FLUTTER_ARCHITECTURE_AUDIT.md) for scoped findings,
refactoring decisions, security boundaries and release follow-ups.

- Flutter analysis: no issues.
- Flutter unit/widget tests: 49 passed (33 before the audit).
- Dart formatting: clean across lib, test and integration_test.
- iOS native secure-storage integration test: passed; synthetic Keychain value
  written, read and deleted successfully on iPhone 15 Pro Max.
- Android debug build: passed with secure storage integrated. Existing camera
  plugin future-Kotlin compatibility warning remains nonfatal.
- iOS app rebuilt and launched with Supabase initialized; app left running.
- Ask Snap/sidebar preview tests: 2 passed; rendered previews inspected.
- No backend source or database schema changes were required.


## Ask Snap — 20 October 2026

Ask Snap is available from the Home shortcut and navigation tab. See
[Ask Snap implementation notes](ASK_SNAP.md) for its API, privacy boundaries,
limits, and supported questions.

| Check | Result |
| --- | --- |
| Flutter static analysis | No issues |
| Flutter unit/widget suite | 32 passed |
| Backend test suite | 63 passed |
| Backend Ruff lint | Passed |
| Live OpenAI Ask Snap checks | 6 passed; disposable account deleted |
| Android debug APK | Built successfully |
| iOS simulator build and launch | Passed; Supabase initialized |
| Running backend health endpoint | Passed |

Live checks covered currency-separated totals, historical receipt dates, largest
purchases, comparisons, inclusive amount filters, and refusal of write requests.
The assistant did not modify the seeded expense records. Phone previews were
rendered and inspected. The app remains running in the iPhone 15 Pro Max simulator,
and the backend is running on port 8000.

## Previous verification — 19 October 2026

## Completed checks

| Check | Result |
| --- | --- |
| Flutter static analysis | No issues |
| Flutter unit/widget suite (`--concurrency=1`) | 29 passed |
| Backend pytest | 50 passed |
| Backend Ruff lint | Passed |
| Live backend receipt/data checks | 17 passed |
| Live Flutter client against Supabase/FastAPI | Passed |
| Live signup confirmation/recovery token checks | Passed; no email sent |
| Android debug APK | Built successfully |
| Updated iOS simulator build and launch | Passed; Supabase initialized |

Android artifact: `frontend/build/app/outputs/flutter-apk/app-debug.apk`.
The build still emits a camera plugin warning about future built-in Kotlin
compatibility; it does not prevent this build. No dependencies were downgraded.

## Verified with real services

The backend was restarted with the configured `.env`. Its `/ready` endpoint passes,
including the database tables and private receipt Storage bucket. A disposable
user uploaded a clearly marked synthetic receipt. OpenAI extracted its MAD 50.00
total correctly. A second extraction used the cache. Private signed previews,
public-access denial, cross-user isolation, idempotent saves, refreshed sessions,
durable edits/deletions, and recalculated analytics all passed.

The actual Flutter SDK/API client also logged into a disposable account and saved
an expense. After destroying its local store and HTTP client, signing out, and
signing in again, a fresh store reloaded the saved expense. Edits and deletion
survived fresh-client reloads too. This verifies server persistence beyond client
memory; it is not an operating-system process-kill test.

Live auth checks generated real one-time signup and recovery tokens through the
admin API without emailing anyone. They verified that an unconfirmed account
cannot log in, confirmation enables login, recovery updates the password, the old
password stops working, and the recovery token cannot be reused. All disposable
users, receipt objects, and temporary client credentials were cleaned up.

## Password recovery implemented

Flutter now includes Forgot password, reset-email feedback, a new-password form,
matching-password validation, recovery-session routing, and return to signed-out
login after updating. Signup and recovery callbacks use
`snapexpense://auth/callback`, registered on iOS and Android. Expired-session/link
errors are displayed on login. The recovery UI and auth-state routing are covered
by mocked SDK HTTP tests.

## Required project setting and remaining manual verification

The live token check found the mobile redirect is not allowlisted. Add exactly
`snapexpense://auth/callback` in **Supabase → Authentication → URL Configuration →
Redirect URLs**, then save. The service-role key cannot modify this project
setting; the desktop dashboard automation tool was unavailable during this task.

After allowlisting, test an email delivered to an accessible inbox and open the
link on the same device where it was requested (PKCE). Inbox delivery and that
complete email-to-app round trip have not been verified. Real photographed
receipts in the app's target languages/layouts still need accuracy evaluation;
the live extraction above used a synthetic receipt with a known total.

## Environment issues resolved during checks

The Android build initially ran out of disk space and left a stale project Gradle
cache lock. Its daemon was stopped and only the project's generated cache/build
intermediates were cleared. After more disk space became available, the APK built
successfully. Global user caches and personal files were not deleted.
