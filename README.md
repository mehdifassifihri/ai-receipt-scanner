# SnapExpense AI

SnapExpense AI is a Flutter expense-tracking app that turns receipt photos into organized spending records. It combines OpenAI-powered receipt extraction, a FastAPI backend, and Supabase authentication, database, and storage.

## Features

- **Scan receipts:** Capture a receipt or choose an image from your gallery, then extract merchant, date, amount, currency, and category with OpenAI.
- **Review and save:** Check extracted details and make corrections before saving an expense.
- **Spending dashboard:** View monthly totals, category breakdowns, and recent expenses.
- **Expense history:** Search, filter, edit, and delete saved expenses.
- **Analytics:** Explore spending trends by period, category, and currency.
- **Ask Snap:** Ask questions about your saved expenses and open the supporting expense records from the answers.
- **Secure accounts:** Sign up, log in, and recover your password through Supabase Auth.

## Project structure

The project is organized into two independent applications:

- [frontend/](frontend/README.md): Flutter mobile app, assets, platform projects, and UI tests.
- [backend/](backend/README.md): FastAPI server, OpenAI receipt extraction, Supabase migrations, and server tests.

## Run the frontend

```sh
cd frontend
flutter pub get
flutter run --dart-define-from-file=config/local.json
```

## Run the backend

Configure `backend/.env` using `backend/.env.example`, then:

```sh
cd backend
uv run --frozen uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload --no-access-log
```

See the backend README for Supabase setup and database migration instructions.
The Flutter app connects to FastAPI and Supabase Auth. See the frontend README for public app configuration and device-specific server URLs.
