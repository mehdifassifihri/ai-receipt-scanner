# SnapExpense AI — Flutter app

Material 3, Poppins, and a lime/lavender visual system. Includes the animated launch,
Dashboard, camera/gallery scanner, editable receipt review, history/details, and
currency-separated Analytics.

## Connected backend setup

The app now signs in through Supabase Auth and calls FastAPI with the user's access
token. Receipt upload/extraction, expense CRUD, private receipt previews, and
Analytics use the backend. Dashboard totals and its chart derive from the fully
paginated server expense list. No sample transactions are mixed into connected
accounts. Account creation may require email confirmation depending on Supabase settings.

1. Complete `backend/.env` and apply the Supabase migration from the backend README.
2. From `backend/`, run `uv run --frozen python -m scripts.configure_flutter`.
   This writes `frontend/config/local.json` with **only** the project URL,
   publishable key and API URL. Service-role and OpenAI keys remain server-only.
3. Start FastAPI from `backend/` using the backend README instructions.
4. From `frontend/`, run:

   ```sh
   flutter run --dart-define-from-file=config/local.json
   ```

The default API URL `http://127.0.0.1:8000` works for an iOS simulator on the server's
Mac. For Android Emulator generate the config with
`--api-url http://10.0.2.2:8000`. For a physical device use your computer's LAN
hostname/IP, put both devices on the same network, and start uvicorn with
`--host 0.0.0.0`. iOS may ask for local network permission. Use HTTPS for deployed
servers; Android permits cleartext HTTP only in debug builds. Native plugins were
added, so rebuild the app fully rather than hot reloading.

For Flutter web, add its exact origin to backend `CORS_ORIGINS`; never use the
service-role key in browser/app configuration. Settings supplied through Dart
defines are public app configuration, not secret storage.

Without app configuration, startup displays a setup screen. Local demo data remains
available only in isolated previews/tests and the explicitly labelled history demo.
Supabase restores sessions and refreshes tokens; signing out destroys the account's
in-memory store and navigation history. Saves/deletes update the UI after server
success. Refresh failures keep the previous snapshot and display a retry action.
There is no offline write queue. Only JPEG/PNG receipts up to 6 MiB are accepted.
Unknown extraction fields require manual completion; AI output is never auto-saved.

Run `flutter analyze` and `flutter test` to check the integration. HTTP tests cover
pagination, failed writes/deletes, authentication headers, upload, extraction, user
confirmation, and server Analytics mapping without calling paid services.

## Account pages and glass summary

`LoginScreen` and `RegistrationScreen` use the shared account form with Supabase
Auth, email validation, password visibility, and matching password confirmation.
Registration opens as its own route; returning preserves the login form. Both
forms scroll above the keyboard. Email confirmation remains controlled by Supabase.

`SpendingGlassCard` gives both live and preview Monthly Spending cards a bounded
backdrop blur, translucent gradient, white edge, and soft shadow. Text is drawn
above the blur. No dependencies were added for this effect.

## Editor launch

When opening the parent folder in VS Code, select **SnapExpense AI (Flutter)**
from Run and Debug. The root `.vscode/launch.json` sets the working directory to
`frontend/` and loads `config/local.json`. For Android Studio, open `frontend/`
as the Flutter project; its main.dart run configuration includes the same flag.
Restart the Dart analysis server after moving a project if the editor shows old paths.

A **Connect SnapExpense** page means public connection settings are missing. Fill
backend/.env, generate the public Flutter config using the backend helper, and
fully restart the app. A build succeeding does not verify live Supabase or OpenAI.

## Password recovery and email callbacks

Login now has **Forgot password?**. The app sends a Supabase recovery email, handles
its callback, validates a new password and matching confirmation, and signs out the
recovery session before returning to login. Recovery errors retain the form for retry.
Signup confirmation also returns to the mobile app.

iOS and Android register `snapexpense://auth/callback`. Add that exact URL in
**Supabase → Authentication → URL Configuration → Redirect URLs** and save. This
project setting is required: the live test found Supabase currently falling back
to its site URL. It cannot be configured with the app's service-role API key.
Use the email link on the same device where recovery was requested (PKCE).

The automated live auth check exercises confirmation and recovery tokens without
sending email. Actual inbox delivery and the complete email-to-app round trip
still require a manual test with an accessible email account after allowlisting.

## Ask Snap

Open Ask Snap from the Home summary shortcut or the Ask Snap navigation tab.
The chat supports suggested questions, all/separate currency selection, short
follow-up context, loading/errors/retry, and clear conversation. Answers show
server-computed totals and date/currency scope. Related expense cards fetch the
current authorized expense before opening its details, so stale/deleted references
fail safely. The assistant cannot edit records; normal expense detail actions
remain user-controlled. A conversation lives only while its screen/tab is alive
and is removed with the account's navigation tree on sign-out. It retains at most
20 exchanges and sends at most six prior text entries as context.

Disconnected previews disable sending rather than treating sample data as real.
The app uses the existing authenticated backend client; no OpenAI key is bundled
in Flutter. The server must be restarted after installing this endpoint.

## Architecture and session security

See [the architecture audit](../docs/FLUTTER_ARCHITECTURE_AUDIT.md) for findings,
changes, verification and remaining release requirements.

Supabase session and PKCE storage now uses the secure-storage plugin on mobile.
Existing preference-backed sessions migrate after a successful secure write;
failed migrations do not fall back to plaintext persistence. Expired sessions
must renew before protected Home is shown. Logout/account switching invalidates
the old API client, store and protected navigation.

Release builds require an HTTPS `API_BASE_URL`. Local HTTP configuration remains
supported in debug builds. Rebuild native apps after adding secure storage.
The simulator Keychain adapter can be checked without any real credentials:

```sh
flutter test integration_test/secure_storage_test.dart -d <device-id>
```

## Ask Snap glass controls

Ask Snap’s floating composer/suggestions and Receipt Scanner’s image overlays use
shared glass components, with iOS Reduce Transparency, high-contrast and reduced-
motion solid fallbacks. Long answers and the receipt image remain unfiltered.
See [glass implementation and tuning notes](../docs/LIQUID_GLASS.md) for renderer
evaluation, adjustable values, validation and physical-iPhone profiling steps.
