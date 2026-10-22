# SnapExpense AI

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
