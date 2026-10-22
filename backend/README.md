# SnapExpense AI backend

Separate FastAPI server for the existing Flutter app. The Flutter client now connects through Supabase Auth and this API. It provides authenticated expense CRUD, private
receipt uploads, OpenAI extraction **drafts**, and currency-separated analytics.

## 1. Start the local server

Requires Python 3.12 or 3.13. This workspace already has an isolated `.venv` and
locked dependencies installed.

```sh
cd backend
# If installing on another machine:
uv sync --frozen --extra dev
# A blank, ignored .env has already been created here. On another machine:
cp -n .env.example .env
uv run --frozen uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload --no-access-log
```

Without uv, create a virtual environment, install `requirements.lock.txt` with
`pip install --require-hashes -r requirements.lock.txt`, then run
`python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log`.

- Interactive API documentation: <http://127.0.0.1:8000/docs>
- OpenAPI contract: <http://127.0.0.1:8000/openapi.json>
- Liveness: `GET /health` works without external credentials.
- Readiness: `GET /ready` returns **503** until credentials, tables, and a private
  bucket are configured. It makes no paid OpenAI call and does not verify OpenAI
  billing/model access; a `ready` response explicitly reports that limitation.

## 2. Configure Supabase

1. Create a Supabase project, or choose a dedicated existing project.
2. Run `supabase/migrations/202610180001_initial_schema.sql` **once** in its SQL
   editor. Alternatively, use the Supabase CLI to link and push this migration.
   This file requires Supabase's `auth` and `storage` schemas; it is not a plain
   standalone PostgreSQL initialization script.
3. Set these values in **backend/.env**, locally:
   - `SUPABASE_URL`: the project's HTTPS URL.
   - `SUPABASE_PUBLISHABLE_KEY`: its publishable key, or legacy anon key.
   - `SUPABASE_SERVICE_ROLE_KEY`: the legacy **service_role** secret, backend only.
4. Keep `SUPABASE_STORAGE_BUCKET=receipts`. If changing it, also change the bucket
   ID and Storage policies in a new migration; the initial migration uses receipts.
5. Supabase Auth handles user signup, login, email confirmation, and sessions.
   This server does not duplicate those password-management endpoints. Create a
   confirmed test user through your project's Auth tooling before testing protected
   API calls. In production, enable the sign-in providers your product needs.

Every protected request sends `Authorization: Bearer <Supabase access token>`.
The backend verifies the session using `/auth/v1/user`. It does not trust a client
user ID or decode an unsigned JWT. Ordinary queries use the user's JWT and RLS;
only extraction-job writes/admission use the server service-role key.

Without Flutter auth yet, get a test session using:

```sh
uv run --frozen python -m scripts.get_access_token
```

The script prompts for a test user's email/password, signs in directly with
Supabase Auth, and prints an access token for Swagger's **Authorize** dialog.
Do not paste service-role keys, OpenAI keys, passwords, or access tokens into chat.

## 3. Configure OpenAI

Set `OPENAI_API_KEY` in backend/.env and enable API billing/credits on its project.
The configurable initial model is `gpt-5-mini`. It receives a receipt image using
Responses API image input and returns a strict Pydantic Structured Output schema.
No separate OCR provider is used. Model access and extraction quality still need
verification against your account and representative receipts.

- `OPENAI_MODEL`: change after benchmarking your real receipt languages/layouts.
- `OPENAI_REASONING_EFFORT=low`: suitable for the default model. Set it to an empty
  value if switching to a model that does not accept this parameter.
- `OPENAI_TIMEOUT_SECONDS=45`: server timeout; SDK automatic retries are disabled
  so network retries do not silently repeat extraction calls.
- `EXTRACTION_DAILY_LIMIT=50`: attempted uncached extractions per user per UTC day.
  Admission is atomic in PostgreSQL across API workers. Completed cached results
  do not consume another attempt. Failed attempts count toward the limit.

All missing or ambiguous fields stay null, with review warnings. Amounts are
validated as decimal strings and converted to **integer minor units**, never
stored as floating-point money. Currency must be evidenced and one of the app's
five currencies. Category is only a suggestion. There is no fabricated confidence
score and extraction never creates a saved expense automatically.

`store=False` disables stored Responses API responses; this is **not a promise of
zero provider retention**. Review provider data controls before handling real user
receipts. No fine-tuning, AI agent tools, or web fetching is used.

Official references:
- <https://developers.openai.com/api/docs/guides/images-vision>
- <https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses>
- <https://developers.openai.com/api/docs/models/gpt-5-mini>
- <https://developers.openai.com/api/docs/guides/your-data>
- <https://supabase.com/docs/reference/javascript/auth-getuser>
- <https://supabase.com/docs/guides/storage/security/access-control>

Restart the server after changing .env.

## API contract used by Flutter

| Method | Path | Purpose |
|---|---|---|
| GET | `/health`, `/ready` | Liveness and dependency readiness |
| GET | `/v1/me` | Verified current user |
| GET | `/v1/metadata` | App currencies/categories and amount/date conventions |
| POST | `/v1/receipts` | Multipart `file`: one JPEG/PNG; returns receipt metadata |
| GET | `/v1/receipts/{id}` | Owned receipt metadata |
| GET | `/v1/receipts/{id}/image-url` | Private image URL, valid for 300 seconds |
| POST | `/v1/receipts/{id}/extract` | Run extraction or reuse a completed draft |
| GET | `/v1/receipts/{id}/extraction` | Latest job state and draft/error code |
| POST | `/v1/expenses` | Save user-confirmed fields; requires `Idempotency-Key: <UUID>` |
| GET | `/v1/expenses` | Paginated history with merchant/category/currency/date filters |
| GET | `/v1/expenses/{id}` | Owned expense details |
| PUT | `/v1/expenses/{id}` | Replace editable fields; retain expense/receipt identity |
| DELETE | `/v1/expenses/{id}` | Delete only this expense; retain receipt images |
| GET | `/v1/analytics` | Spending report by period and original currency |

Receipt upload accepts up to 6 MiB and 20 megapixels. The server verifies actual
JPEG/PNG content, applies EXIF orientation, removes image metadata, caps the longest
side at 4096 pixels, and stores a normalized JPEG. Multipart bodies are bounded
before parsing, including requests without Content-Length. HEIC/PDF/SVG are not
accepted in this MVP. Image upload retries deduplicate by owner and normalized
image hash. If database insertion fails, cleanup targets only this upload's own
random storage object. A process crash can still leave an orphan object; a future
retention/cleanup task is needed before a larger public rollout.

Extraction runs **synchronously** in the request (no pretend background queue).
Allow a frontend/proxy timeout of at least 90 seconds. A job records processing,
completed, or failed state; stale processing leases become retryable after five
minutes. One processing extraction per user is enforced in PostgreSQL. Successful
results are cached per receipt/model/prompt version. Network failure after an
OpenAI request was sent can still be ambiguous about provider billing; no
exactly-once external execution is claimed.

Confirmed expense example:

```json
{
  "receipt_id": "<receipt UUID>",
  "merchant": "Starbucks",
  "transaction_date": "2026-10-18",
  "amount_in_cents": 2450,
  "currency": "MAD",
  "category": "Food & Drinks"
}
```

Generate a new Idempotency-Key UUID per new expense. Reuse it only for retries with
the identical payload. A retry returns the existing expense; reusing it with a
different payload returns 409. A receipt can be attached to only one expense.
Manual expenses may omit receipt_id. PUT takes the same editable fields but no
receipt_id; it cannot reassign another user's receipt or change ownership.

History query parameters: `limit` (1–100), `offset`, `search`, `category`, `currency`,
`date_from`, `date_to` (inclusive). Search is case-insensitive and supports SQL LIKE
pattern characters. Dates are date-only, validated against the current UTC date.

Analytics periods: `this_month`, `last_month`, `last_three_months`, `this_year`.
The current month/year are through today. Comparisons use an immediately preceding
range of exactly the same day count, matching the Flutter calculations. Every
report filters one currency (default USD). Totals and averages are minor-unit
integers; category percentages and percentage changes are ratios. Missing baseline
spending yields null change. Daily/monthly buckets are zero-filled. Reports fetch
all relevant database pages, not only Supabase's first page. They are not a
transactional snapshot across concurrent edits; large-scale reporting can later
move to a SQL aggregate RPC.

## Database layout

- `receipts`: owner, image path, content hash, MIME type, size, timestamp.
- `extraction_jobs`: owner/receipt, model/prompt version, status, draft, safe error code.
- `expenses`: owner, optional receipt, idempotency key, confirmed fields, timestamps.

RLS isolates user data. A composite foreign key prevents linking another user's
receipt even through a direct database API call. Storage is private and limited
to the user's UUID folder. User-facing queries never use the service-role key.
Cloud persistence is provided by Supabase; there is **no in-memory production
fallback**. The in-memory repository exists only in tests.

## Checks

```sh
uv run --frozen --extra dev pytest -q
uv run --frozen --extra dev ruff check .
uv run --frozen --extra dev ruff format --check .
```

Tests cover API upload → draft → confirm → edit → delete, ownership isolation,
idempotency, extraction failures/caching/quotas, image validation and metadata
removal, real OpenAI SDK serialization with a mocked HTTP transport, Supabase
header/RLS credential forwarding, pagination beyond 1,000 rows, analytics, and SQL
syntax. Tests make **no paid API calls**. SQL parsing is not a substitute for live
Supabase tests: migrations, actual RLS behavior, storage, OpenAI credentials, and
real receipt accuracy must still be checked against your configured project.

## Deployment

A Dockerfile, hashed production requirements, and Compose configuration are
included. Docker is not installed in this workspace, so container builds have not
been run. When Docker is available:

```sh
cd backend
docker compose up --build
```

Compose binds to loopback; put the service behind HTTPS/reverse proxy when making
it public. Provide secrets through your host's secret/environment settings. The
container runs as a non-root user, does not contain .env, and supports a `PORT`
environment variable. Configure request/rate limits at the proxy and appropriate
Supabase/OpenAI account usage controls before inviting public users. Automatic
account deletion, orphan cleanup, offline sync, and distributed background job
workers are intentionally not part of this first server setup.

## Generate Flutter connection settings

After filling backend/.env, run from this directory:

```sh
uv run --frozen python -m scripts.configure_flutter
```

Only public values are written to frontend/config/local.json. Override the API URL
with `--api-url http://10.0.2.2:8000` for Android Emulator, or your computer's LAN
address for a physical phone. Rebuild Flutter using
`--dart-define-from-file=config/local.json`. Never copy server secrets into Flutter.

## Opt-in live checks

With the configured local server running:

```sh
uv run --frozen python -m scripts.live_check --extract
uv run --frozen python -m scripts.live_auth_check
```

These commands create and remove disposable users in your Supabase project.
The first also uploads a synthetic test receipt and removes its Storage object.
`--extract` makes one live, billable model request; the subsequent cache check
should not make a second request. Omit the flag to skip extraction. These are
manual checks, never part of pytest or CI, and never print session secrets.
The receipt script uses the Mac's Menlo font for its synthetic receipt.

The auth script generates real signup/recovery tokens without sending email. It
checks confirmation requirements, password changes, rejection of the old password,
and single use of recovery tokens. It also reports whether the mobile callback
is allowlisted. Configure `snapexpense://auth/callback` in Supabase Auth's redirect
URL list; service-role credentials cannot change dashboard project settings.

For an opt-in check of the actual Flutter SDK/client against the live backend:

```sh
uv run --frozen python -m scripts.live_flutter_check
```

It provisions a disposable confirmed user, passes its temporary login credentials
through a permission-restricted temporary config, runs the Flutter client check,
and removes the config and user in `finally`. The check saves, discards local
stores and HTTP clients, signs out/in, reloads, edits, and deletes an expense.
It verifies fresh-client persistence; it does not simulate an operating-system
process kill or send email. Never run these live helpers as part of ordinary CI.

## Ask Snap (read-only)

`POST /v1/ask-snap` accepts `message` (1–1000 characters), optional supported
`currency`, and at most six user/assistant history entries (2000 characters each).
It uses the existing OpenAI key and `ASK_SNAP_MODEL` (default `gpt-5-mini`).
No new dependencies or database migration are required.

The model translates conversation text into a strict, bounded query plan. It has
no database tools, no SQL output, no expense mutation path, and does not receive
raw expense rows/images. Conversation text, including short prior answers, is
sent to OpenAI with `store=False`; this does not promise zero provider retention.
Totals, comparisons, date windows, category changes, filters, and references are
computed on the server from the authenticated user's RLS-protected expenses.
Currencies are kept separate. A cross-currency largest-expense question asks the
user to choose a currency. A comparison uses the preceding equal-length period.
Answers currently use English templates; question interpretation is model-based.

Supported intents: totals/category breakdowns, merchant receipt search, largest
expenses, previous-period comparisons, and explanations of transaction dates
outside a selected period. Custom inclusive date ranges must end today or earlier.
Amount lower thresholds distinguish "above" from "at least". Unrepresented filters
(e.g. line items, upper limits, budgets) should prompt clarification rather than
invent an answer. Results cover saved expenses only, not unscanned purchases.
Up to ten real expense references accompany an answer; totals include all matched
records, not just displayed references. Account reads are fully paginated, capped
at 10,000 records with an explicit error instead of partial totals.

Admission control allows one active question per user, four globally, ten attempts
per minute and sixty per hour per user. This bounded in-memory limiter is for the
current single-process server. Before running multiple workers/replicas, enforce
shared quotas at a gateway or in a database. Provider failures/refusals/timeouts
return safe retryable errors; there is no generic invented-answer fallback.
No chat messages are stored by this backend or logged by its request middleware.

Run `python -m scripts.check_ask_snap` from backend/ for an **opt-in billable live
check** with six questions against synthetic expenses, including an attempted
write. It creates and deletes a disposable user; do not run it in ordinary CI.
