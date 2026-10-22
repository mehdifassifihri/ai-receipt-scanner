# Flutter architecture and security audit — 20 October 2026

## Scope and baseline

Applied `frontend/.agents/skills/flutter-architecture-guardian/SKILL.md`.
Inspected bootstrap, configuration, themes, all screen/state/service boundaries,
API client, tests, auth SDK implementation, platform manifests, dependency lock,
and server authentication/repository/RLS sources. No `AGENTS.md` was present.

Baseline: `flutter analyze` had no issues; `flutter test --concurrency=1` passed
33 tests. Findings below were pre-existing; they are not regressions introduced
by this audit. This is a source review and targeted validation, not a penetration
test or certification of the deployed infrastructure.

## Initial findings

| Priority | Finding | Resolution |
| --- | --- | --- |
| Critical | No critical issue confirmed within the inspected scope | Server ownership checks and RLS exist; production policy configuration was not revalidated live |
| High | Default Supabase session and PKCE persistence used preferences | Added Keychain/Keystore-backed SDK adapters and migration |
| High | Expired restored session could reach protected UI before renewal | Startup gate waits for SDK refresh |
| High | Old account requests could finish after teardown; request closure did not reject delayed token acquisition or completed responses | Immediate account invalidation, API closure guards, stale result rejection, cache cleanup |
| High | HTTP backend configuration was accepted for release | HTTPS required outside debug builds; privileged keys and URL credentials rejected |
| Medium | Ask Snap mixed UI, networking, history and retry state | Extracted a ChangeNotifier controller; screen owns only UI resources/navigation |
| Medium | Offset pagination could accept changing totals or repeated rows | Rejects inconsistent totals and duplicate IDs, preserving the previous store snapshot |
| Medium | Dashboard repeated immutable list allocation and analytics work during rebuilds | Stable snapshots and bounded report cache, invalidated with store changes |
| Medium | Dashboard/sidebar accessed Supabase directly | Account presentation scope passes identity and logout callback from composition root |
| Medium | Technical exception text could surface in expense UIs | Unknown errors use safe messages; intentional API messages remain visible |
| Low | Shared theme values and formatting drift | Extracted shared theme/tokens and formatted Dart sources |
| Medium, follow-up | Several large screen files still combine many UI sections; camera/extraction orchestration remains coupled to screens | Retained to avoid a broad high-risk rewrite; migrate feature-by-feature with characterization tests |
| High, release follow-up | Android release uses debug signing and placeholder application identity | Not changed: production signing material and final app identity must be supplied deliberately |

## Architecture decision

Keep the existing coherent hybrid layout: `screens/`, `widgets/`, `state/`,
`services/`, `models/`, and `data/`. Keep Material 3, Poppins, Navigator,
ChangeNotifier/InheritedNotifier, Supabase and the existing HTTP client. No new
state management, router, dependency injection framework, repositories, or empty
domain layers were introduced. A wholesale directory migration adds risk without
fixing these defects.

The only new direct runtime dependency is `flutter_secure_storage` 10.3.x
(lockfile resolves 10.3.4). Existing packages were retained. Its transitive native
adapters are recorded in the lockfile. This version supports the installed native
build setup; no camera/Xcode compatibility pin was removed.

## Main modules changed

- `frontend/lib/services/auth/secure_auth_storage.dart`: SDK LocalStorage and
  PKCE adapters; serialized operations; migrate existing session/verifier values
  only after successful secure writes; remove legacy copies. Storage is scoped
  by the existing Supabase project namespace. This does not store passwords.
- `frontend/lib/services/auth/session_access.dart`: account-bound access token
  retrieval. Reuses SDK refresh coordination, rereads the authoritative session,
  and rejects changed/expired/missing owners.
- `frontend/lib/data/app_configuration.dart` and `lib/main.dart`: public-key and
  endpoint validation, debug-only HTTP, secure SDK storage initialization.
- `frontend/lib/data/app_connection.dart`: composition and optional test injection,
  expired-session startup gate, immediate old-store invalidation, SDK session
  events, protected Navigator reset, account identity scope.
- `frontend/lib/state/account_scope.dart` and
  `lib/services/auth/profile_name.dart`: presentation identity/greeting without
  leaking SDK objects or tokens into unrelated widgets.
- `frontend/lib/state/ask_snap_controller.dart` and
  `lib/screens/ask_snap_screen.dart`: separate bounded chat state, networking,
  history and retry coordination from widgets. Chat remains memory-only.
- `frontend/lib/data/backend_api.dart`: closed-session guards, response shape
  validation, safe failures, consistency checks while paginating.
- `frontend/lib/state/expense_store.dart`: invalidation/cleanup, immutable snapshot
  reuse, bounded analytics cache, centralized loading of expense references.
- `frontend/lib/theme/app_theme.dart`, `lib/app.dart`, screens: shared existing
  theme values. Per-card accents remain local and unchanged.
- `frontend/lib/widgets/snap_sidebar.dart`: injected account data/logout action,
  duplicate-logout protection, same sidebar composition and styling.
- `frontend/lib/screens/home_shell.dart`: reuse a single page list per build and
  constant tab widgets; existing navigation remains.
- Expense/review/extraction/analytics screens: safe error presentation.
- `frontend/android/app/src/main/AndroidManifest.xml`: disable Android automatic
  app backup to avoid restoring unusable encrypted auth state.
- `frontend/pubspec.yaml`, `pubspec.lock` and generated platform plugin registration:
  secure-storage dependency integration. Generated files are tool-managed.

Dart formatting may touch additional files without changing their logic.

## Security boundaries and migration notes

- Supabase remains the single session authority. The installed GoTrue SDK already
  deduplicates refreshes, prevents stale refresh overwrites and emits sign-out
  for invalid refresh credentials; a parallel token system was not added.
- Legacy preferences are read for migration only. Failed secure writes retain
  the legacy value for retry; the app does not fall back to plaintext writes.
- Storage operations are serialized so an earlier session write cannot finish
  after a queued logout deletion and resurrect that persisted session.
- Native mobile storage uses platform-backed protection. Browser storage does
  not acquire iOS Keychain/Android Keystore guarantees merely through this plugin.
- Local debug configuration still supports simulator/LAN development. Release
  deployment now needs an HTTPS `API_BASE_URL`; do not use `config/local.json`
  unchanged for a production release if it contains a local HTTP URL.
- Existing app-side account ownership checks complement server JWT verification
  and Supabase RLS; route guarding alone does not authorize backend requests.
- Offset consistency checks detect changing counts and duplicate IDs; they are
  not a transactional snapshot of concurrent database edits with unchanged counts.
- Closing a client prevents stale responses from being consumed locally. It
  cannot undo a server operation already accepted before logout.
- No real account data or credentials are used in the added automated tests.

## Validation

Executed successfully:

- `flutter pub add 'flutter_secure_storage:^10.3.4'`: resolved dependencies and
  updated the lockfile; existing package versions retained.
- `dart format lib test integration_test`: formatting applied.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  56 files checked, zero changes required.
- `flutter analyze`: no issues.
- `flutter test --concurrency=1`: **49 tests passed**, up from 33 baseline tests.
- `flutter test integration_test/secure_storage_test.dart -d 383EA713-08E5-4ABA-A078-A8AA64AA5E15`:
  **passed on the iPhone 15 Pro Max simulator**. The Xcode native build succeeded;
  actual Keychain write/read/delete used a disposable synthetic key, then removed it.
- `flutter build apk --debug --dart-define-from-file=config/local.json`: passed;
  APK at `frontend/build/app/outputs/flutter-apk/app-debug.apk`. The pre-existing
  camera plugin future-Kotlin compatibility warning remains nonfatal.
- `flutter test tool/render_ask_snap_preview_test.dart tool/render_sidebar_preview_test.dart --concurrency=1`:
  two preview tests passed. Rendered Ask Snap and sidebar phone previews inspected;
  existing layout, typography and styling preserved.
- `flutter run -d 383EA713-08E5-4ABA-A078-A8AA64AA5E15 --dart-define-from-file=config/local.json`:
  Xcode build and app launch succeeded; Supabase initialized with the secure
  storage adapter. Detached the debugger, leaving the app running.
- Client source/assets/config marker scan: no privileged-key markers found;
  local configuration contains only the three expected public configuration fields.

The new tests cover migration success/failure and existing-value precedence,
serialized logout deletion, project namespaces, configuration validation, stale
request rejection, pagination consistency, analytics cache invalidation, profile
formatting, bounded chat/history, duplicate requests/logout, disposal, coordinated
SDK refresh, revoked refresh tokens, startup gating and protected route reset on
logout/account switching. Existing receipt, analytics and auth widget tests remain.

No paid model calls or live credential-based auth tests were needed for this
Flutter refactor. Deployed server settings and physical-device security behaviors
remain separate from these automated results.

## Remaining recommendations

1. Before distribution: configure release signing/final application IDs and HTTPS
   hosting; revalidate deployed RLS, private bucket policies, auth redirects,
   provider abuse limits, email delivery and real-device login/recovery flows.
2. Exercise secure-storage persistence across process kill, OS backup/restore,
   reinstall and locked-device scenarios on physical iOS/Android hardware. Native
   simulator write/read/delete verifies the adapter, not every OS lifecycle case.
3. Extract scanner/extraction and auth-form orchestration incrementally when those
   features next change. Keep UI sections local until extraction improves a real
   responsibility boundary. Add resume/offline and native plugin failure tests.
4. Profile large accounts and text scaling/accessibility on physical devices;
   consider cursor pagination/server aggregates for genuinely large datasets.
5. Choose app-switcher snapshot protection and local retention policy based on the
   product threat model. This audit did not add biometrics, pinning, or screen
   capture restrictions without a product requirement.

Secure-storage dependency reference:
https://pub.dev/packages/flutter_secure_storage/versions/10.3.4
