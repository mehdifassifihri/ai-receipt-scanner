"""Opt-in live smoke test. Creates and cleans up disposable users and receipt data.

Run from backend/: python -m scripts.live_check [--extract]
--extract makes one billable OpenAI extraction through the running server.
No credentials, access tokens, user emails, or signed image URLs are printed.
"""

import argparse
import io
import secrets
from datetime import UTC, datetime
from uuid import uuid4

import httpx
from PIL import Image, ImageDraw, ImageFont

from app.config import Settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extract", action="store_true")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    s = Settings()
    assert not s.missing_configuration(), "Configure backend/.env first"
    admin = {
        "apikey": s.supabase_service_role_key.get_secret_value(),
        "Authorization": f"Bearer {s.supabase_service_role_key.get_secret_value()}",
    }
    public = {"apikey": s.supabase_publishable_key.get_secret_value()}
    users = []
    paths = []
    checks = []

    def check(condition, name):
        if not condition:
            raise RuntimeError(name + " FAILED")
        checks.append(name)
        print("PASS:", name, flush=True)

    def ok(response, name):
        if not response.is_success:
            # Never dump provider bodies/headers, which may contain session secrets.
            code = (
                response.json().get("error", {}).get("code")
                if response.headers.get("content-type", "").startswith("application/json")
                and isinstance(response.json().get("error"), dict)
                else None
            )
            raise RuntimeError(
                f"{name}: HTTP {response.status_code}" + (f" ({code})" if code else "")
            )
        return response.json() if response.content else None

    with httpx.Client(timeout=110) as c:
        try:
            check(c.get(args.base_url + "/ready").status_code == 200, "backend readiness")
            tokens = []
            for _ in range(2):
                email = f"snapexpense-smoke-{uuid4().hex}@example.invalid"
                password = secrets.token_urlsafe(28)
                user = ok(
                    c.post(
                        s.supabase_url + "/auth/v1/admin/users",
                        headers=admin,
                        json={"email": email, "password": password, "email_confirm": True},
                    ),
                    "create disposable confirmed user",
                )
                users.append(user["id"])
                session = ok(
                    c.post(
                        s.supabase_url + "/auth/v1/token?grant_type=password",
                        headers=public,
                        json={"email": email, "password": password},
                    ),
                    "password login",
                )
                tokens.append(session)
            h = {"Authorization": "Bearer " + tokens[0]["access_token"]}
            other = {"Authorization": "Bearer " + tokens[1]["access_token"]}
            check(
                ok(c.get(args.base_url + "/v1/me", headers=h), "verify identity")["id"] == users[0],
                "real password login and identity",
            )
            image = Image.new("RGB", (1000, 1300), "white")
            draw = ImageDraw.Draw(image)
            font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 30)
            today = datetime.now(UTC).date().isoformat()
            lines = [
                "SNAP TEST MARKET",
                "TEST RECEIPT - NOT A REAL PURCHASE",
                today,
                "Receipt # " + uuid4().hex[:10],
                "",
                "Bread                 MAD 20.00",
                "Milk                  MAD 15.50",
                "Apples                MAD 14.50",
                "",
                "TOTAL                 MAD 50.00",
                "PAID BY CARD          MAD 50.00",
            ]
            for i, line in enumerate(lines):
                draw.text((45, 70 + i * 70), line, fill="black", font=font)
            buf = io.BytesIO()
            image.save(buf, format="PNG")
            receipt = ok(
                c.post(
                    args.base_url + "/v1/receipts",
                    headers=h,
                    files={"file": ("synthetic-receipt.png", buf.getvalue(), "image/png")},
                ),
                "upload receipt",
            )
            paths.append(receipt["storage_path"])
            rid = receipt["id"]
            check(bool(rid), "private receipt upload")
            signed = ok(
                c.get(args.base_url + f"/v1/receipts/{rid}/image-url", headers=h),
                "receipt image URL",
            )
            check(c.get(signed["url"]).status_code == 200, "signed receipt preview")
            check(
                c.get(args.base_url + f"/v1/receipts/{rid}", headers=other).status_code == 404,
                "cross-user receipt isolation",
            )
            check(
                c.get(
                    s.supabase_url + f"/storage/v1/object/public/receipts/{receipt['storage_path']}"
                ).status_code
                != 200,
                "receipt bucket is not publicly readable",
            )
            if args.extract:
                result = c.post(args.base_url + f"/v1/receipts/{rid}/extract", headers=h)
                if result.is_success:
                    draft = result.json()["job"]["result"]
                    check(
                        draft["requires_review"] is True,
                        "live OpenAI extraction produces a review draft",
                    )
                    check(
                        draft["fields"]["amount_in_cents"] == 5000
                        and draft["fields"]["currency"] == "MAD",
                        "synthetic receipt amount and currency accuracy",
                    )
                    cached = ok(
                        c.post(args.base_url + f"/v1/receipts/{rid}/extract", headers=h),
                        "cached extraction",
                    )
                    check(cached["cached"] is True, "extraction cache avoids a second model call")
                else:
                    error = result.json().get("error", {})
                    print(
                        "BLOCKED: live OpenAI extraction:",
                        result.status_code,
                        error.get("code", "unknown"),
                        error.get("message", ""),
                        flush=True,
                    )
            body = {
                "receipt_id": rid,
                "merchant": "Snap Test Market",
                "transaction_date": today,
                "amount_in_cents": 5000,
                "currency": "MAD",
                "category": "Groceries",
            }
            key = str(uuid4())
            headers = {**h, "Idempotency-Key": key}
            expense = ok(
                c.post(args.base_url + "/v1/expenses", headers=headers, json=body),
                "confirmed expense save",
            )
            eid = expense["id"]
            replay = ok(
                c.post(args.base_url + "/v1/expenses", headers=headers, json=body),
                "idempotent save",
            )
            check(replay["id"] == eid, "confirmed save is idempotent")
            check(
                c.get(args.base_url + f"/v1/expenses/{eid}", headers=other).status_code == 404,
                "cross-user expense isolation",
            )
            # A fresh access token/client reload verifies persistence beyond client memory.
            renewed = ok(
                c.post(
                    s.supabase_url + "/auth/v1/token?grant_type=refresh_token",
                    headers=public,
                    json={"refresh_token": tokens[0]["refresh_token"]},
                ),
                "refresh session",
            )
            h = {"Authorization": "Bearer " + renewed["access_token"]}
            persisted = ok(
                c.get(args.base_url + f"/v1/expenses/{eid}", headers=h), "reload saved expense"
            )
            check(
                persisted["amount_in_cents"] == 5000, "session refresh and durable expense reload"
            )
            edited = {k: v for k, v in body.items() if k != "receipt_id"}
            edited["amount_in_cents"] = 5250
            ok(c.put(args.base_url + f"/v1/expenses/{eid}", headers=h, json=edited), "edit expense")
            check(
                ok(c.get(args.base_url + f"/v1/expenses/{eid}", headers=h), "reload edit")[
                    "amount_in_cents"
                ]
                == 5250,
                "durable edit",
            )
            report = ok(
                c.get(args.base_url + "/v1/analytics?period=this_month&currency=MAD", headers=h),
                "analytics",
            )
            check(report["total_in_cents"] == 5250, "analytics reflects saved data")
            ok(c.delete(args.base_url + f"/v1/expenses/{eid}", headers=h), "delete expense")
            check(
                c.get(args.base_url + f"/v1/expenses/{eid}", headers=h).status_code == 404,
                "durable deletion",
            )
            check(
                ok(
                    c.get(
                        args.base_url + "/v1/analytics?period=this_month&currency=MAD", headers=h
                    ),
                    "analytics after deletion",
                )["total_in_cents"]
                == 0,
                "analytics updates after deletion",
            )
            check(
                c.post(s.supabase_url + "/auth/v1/logout", headers={**public, **h}).is_success,
                "session logout",
            )
        finally:
            if paths:
                r = c.request(
                    "DELETE",
                    s.supabase_url + "/storage/v1/object/receipts",
                    headers=admin,
                    json={"prefixes": paths},
                )
                print("Cleanup receipt objects:", r.status_code, flush=True)
            for uid in users:
                r = c.delete(s.supabase_url + "/auth/v1/admin/users/" + uid, headers=admin)
                print("Cleanup disposable user:", r.status_code, flush=True)
    print(f"Completed {len(checks)} live checks. No email delivery was exercised.", flush=True)


if __name__ == "__main__":
    main()
