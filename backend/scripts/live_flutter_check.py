"""Opt-in Flutter/network smoke check using a disposable cloud user. No paid model call."""

import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path
from uuid import uuid4

import httpx

from app.config import Settings


def main():
    s = Settings()
    root = Path(__file__).resolve().parents[2]
    admin = {
        "apikey": s.supabase_service_role_key.get_secret_value(),
        "Authorization": f"Bearer {s.supabase_service_role_key.get_secret_value()}",
    }
    email = f"snapexpense-flutter-{uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(28)
    uid = None
    config = None
    with httpx.Client(timeout=30) as c:
        try:
            r = c.post(
                s.supabase_url + "/auth/v1/admin/users",
                headers=admin,
                json={"email": email, "password": password, "email_confirm": True},
            )
            if r.status_code != 200:
                raise RuntimeError(f"Create disposable Flutter user: HTTP {r.status_code}")
            uid = r.json()["id"]
            fd, config = tempfile.mkstemp(prefix="snapexpense-live-", suffix=".json")
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w") as file:
                json.dump(
                    {
                        "API_BASE_URL": "http://127.0.0.1:8000",
                        "SUPABASE_URL": s.supabase_url,
                        "SUPABASE_PUBLISHABLE_KEY": s.supabase_publishable_key.get_secret_value(),
                        "LIVE_TEST_EMAIL": email,
                        "LIVE_TEST_PASSWORD": password,
                    },
                    file,
                )
            result = subprocess.run(
                [
                    "flutter",
                    "test",
                    "tool/live_backend_check_test.dart",
                    "--concurrency=1",
                    f"--dart-define-from-file={config}",
                ],
                cwd=root / "frontend",
                timeout=240,
            )
            if result.returncode:
                raise RuntimeError("Live Flutter client check failed")
        finally:
            if config:
                Path(config).unlink(missing_ok=True)
            if uid:
                r = c.delete(s.supabase_url + "/auth/v1/admin/users/" + uid, headers=admin)
                print("Cleanup disposable Flutter user:", r.status_code, flush=True)


if __name__ == "__main__":
    main()
