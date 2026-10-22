# Ask Snap — first release

Read-only assistant for saved SnapExpense expenses. Enter from the Dashboard
shortcut or Ask Snap navigation tab. Suggested questions cover monthly totals,
largest purchases, category changes, and all-time spending. Users may also search
merchants or ask why a receipt is excluded from a period.

## How an answer is produced

1. FastAPI authenticates the Supabase session and applies request admission limits.
2. OpenAI translates the bounded question/conversation into a strict query plan.
   There are no model tools, SQL, or expense write operations.
3. The backend loads only that user's authorized expenses, checks pagination, and
   calculates integer-cent totals, filters, dates, comparisons, and real references.
4. Flutter shows the result with scope/filters and tappable expense cards. A card
   fetches its current authorized record before opening expense details.

The model receives conversation text, not raw database rows, receipt images, or
service credentials. Prior answer text can contain spending information. Responses
use `store=False`; provider retention is not claimed to be zero. Chats are not
persisted in the database and are cleared with the account's UI on logout.

## First-release boundaries

- Answers use English templates. Model interpretation can still misunderstand a
  question; the displayed date/currency/filter scope lets users check its meaning.
- Records mean saved expenses, not all spending. No exchange-rate conversions.
- Comparisons use the preceding equal-duration date window, shown in the answer.
- Amount filters support lower bounds, with "above" distinct from "at least".
- Largest expenses are compared only within one currency. No investment/tax advice.
- At most ten references are shown; totals/counts include all matched rows.
- Reads are capped at 10,000 saved records, with an explicit error above that cap.
- Short followups use at most six prior conversation entries. The UI retains at
  most twenty exchanges while that page/tab lives. No durable conversation history.
- Admission limits are single-process: one active question per user, four globally,
  ten attempts/minute and sixty/hour per user. Shared quotas are required before
  deploying multiple workers or replicas.

## Validation

Backend tests cover integer arithmetic, currency separation, old receipt dates,
threshold boundaries, comparisons, custom date validation, account isolation,
read-only behavior, bounded input/rate limits, pagination, provider refusal, and
strict SDK serialization. UI tests cover auth headers, grounded answers/reference
navigation, short history, disabled previews, retries, and narrow-phone loading.
Six opt-in live model questions were checked against synthetic expenses. The
attempted write did not change any records; the disposable user was removed.

See backend/README.md for the authenticated `/v1/ask-snap` contract and the opt-in
`scripts.check_ask_snap` evaluator. No new package or SQL migration is required.
