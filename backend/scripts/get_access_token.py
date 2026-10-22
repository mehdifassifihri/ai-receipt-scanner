"""Developer helper: get a Supabase session without building Flutter auth first.

Run from backend: .venv/bin/python -m scripts.get_access_token
The user must already exist and be confirmed in Supabase Auth.
"""

import getpass
import sys

import httpx

from app.config import Settings


def main():
    settings = Settings()
    if not settings.supabase_url or not settings.supabase_publishable_key:
        sys.exit("Configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in backend/.env first.")
    email = input("Supabase test-user email: ").strip()
    password = getpass.getpass("Password (hidden): ")
    try:
        response = httpx.post(
            f"{settings.supabase_url}/auth/v1/token",
            params={"grant_type": "password"},
            headers={"apikey": settings.supabase_publishable_key.get_secret_value()},
            json={"email": email, "password": password},
            timeout=20,
        )
    except httpx.RequestError:
        sys.exit("Could not reach Supabase Auth.")
    if response.status_code != 200:
        sys.exit(
            "Sign-in failed. Check the test user, password, and email confirmation in Supabase."
        )
    token = response.json().get("access_token")
    if not token:
        sys.exit("Supabase did not return an access token.")
    print(
        "\nPaste this access token into Swagger's Authorize dialog. Treat it as a secret; do not share it in chat.\n"
    )
    print(token)


if __name__ == "__main__":
    main()
