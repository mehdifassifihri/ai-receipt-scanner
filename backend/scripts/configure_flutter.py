"""Copy only public connection settings into Flutter's ignored local config."""

import argparse
import json
from pathlib import Path

from app.config import Settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    settings = Settings()
    path = Path(__file__).resolve().parents[2] / "frontend/config/local.json"
    config = {
        "API_BASE_URL": args.api_url,
        "SUPABASE_URL": str(settings.supabase_url or ""),
        "SUPABASE_PUBLISHABLE_KEY": settings.supabase_publishable_key.get_secret_value()
        if settings.supabase_publishable_key
        else "",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"Public Flutter configuration written to {path}.")
    missing = [key for key, value in config.items() if not value]
    if missing:
        print("Still needed in backend/.env: " + ", ".join(missing))
    print("No service-role key or OpenAI key was copied.")


if __name__ == "__main__":
    main()
