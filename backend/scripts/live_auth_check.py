"""Exercise real confirmation/recovery tokens without sending email or using personal users."""

import secrets
from uuid import uuid4

import httpx

from app.config import Settings


def main():
    s = Settings()
    admin = {
        "apikey": s.supabase_service_role_key.get_secret_value(),
        "Authorization": f"Bearer {s.supabase_service_role_key.get_secret_value()}",
    }
    public = {"apikey": s.supabase_publishable_key.get_secret_value()}
    email = f"snapexpense-auth-{uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(28)
    uid = None

    def checked(response, name):
        if not response.is_success:
            raise RuntimeError(f"{name}: HTTP {response.status_code}")
        print("PASS:", name, flush=True)
        return response.json() if response.content else None

    with httpx.Client(timeout=30) as c:
        try:
            link = checked(
                c.post(
                    s.supabase_url + "/auth/v1/admin/generate_link",
                    headers=admin,
                    json={"type": "signup", "email": email, "password": password},
                ),
                "generate signup confirmation (no email sent)",
            )
            uid = link.get("id") or link["user"]["id"]
            assert (
                c.post(
                    s.supabase_url + "/auth/v1/token?grant_type=password",
                    headers=public,
                    json={"email": email, "password": password},
                ).status_code
                == 400
            ), "Expected confirmation required before login"
            print("PASS: unconfirmed account cannot sign in", flush=True)
            verified = checked(
                c.post(
                    s.supabase_url + "/auth/v1/verify",
                    headers=public,
                    json={
                        "type": "signup",
                        "token_hash": link.get("properties", link)["hashed_token"],
                    },
                ),
                "confirm signup with real one-time token",
            )
            assert verified["user"]["email_confirmed_at"]
            checked(
                c.post(
                    s.supabase_url + "/auth/v1/token?grant_type=password",
                    headers=public,
                    json={"email": email, "password": password},
                ),
                "confirmed account password login",
            )
            link = checked(
                c.post(
                    s.supabase_url + "/auth/v1/admin/generate_link",
                    headers=admin,
                    json={
                        "type": "recovery",
                        "email": email,
                        "redirect_to": "snapexpense://auth/callback",
                    },
                ),
                "generate recovery token (no email sent)",
            )
            # Report only allowlist behavior; never print a token or link.
            props = link.get("properties", link)
            redirect = props.get("redirect_to", "")
            print(
                "Recovery redirect allowlist:",
                "mobile callback accepted"
                if redirect.startswith("snapexpense://auth/callback")
                else "mobile callback needs dashboard configuration",
                flush=True,
            )
            session = checked(
                c.post(
                    s.supabase_url + "/auth/v1/verify",
                    headers=public,
                    json={"type": "recovery", "token_hash": props["hashed_token"]},
                ),
                "verify recovery token",
            )
            new_password = secrets.token_urlsafe(28)
            checked(
                c.put(
                    s.supabase_url + "/auth/v1/user",
                    headers={**public, "Authorization": "Bearer " + session["access_token"]},
                    json={"password": new_password},
                ),
                "update password using recovery session",
            )
            assert (
                c.post(
                    s.supabase_url + "/auth/v1/token?grant_type=password",
                    headers=public,
                    json={"email": email, "password": password},
                ).status_code
                == 400
            ), "Old password still accepted"
            print("PASS: old password rejected", flush=True)
            checked(
                c.post(
                    s.supabase_url + "/auth/v1/token?grant_type=password",
                    headers=public,
                    json={"email": email, "password": new_password},
                ),
                "new password accepted",
            )
            assert (
                c.post(
                    s.supabase_url + "/auth/v1/verify",
                    headers=public,
                    json={"type": "recovery", "token_hash": props["hashed_token"]},
                ).status_code
                >= 400
            ), "Recovery token unexpectedly reusable"
            print("PASS: recovery token cannot be reused", flush=True)
        finally:
            if uid:
                r = c.delete(s.supabase_url + "/auth/v1/admin/users/" + uid, headers=admin)
                print("Cleanup disposable auth user:", r.status_code, flush=True)


if __name__ == "__main__":
    main()
