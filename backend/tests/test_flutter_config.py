import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

from pydantic import SecretStr

spec = importlib.util.spec_from_file_location(
    "configure_flutter", Path(__file__).resolve().parents[1] / "scripts/configure_flutter.py"
)
configure_flutter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure_flutter)


def test_flutter_config_contains_only_public_values(monkeypatch, tmp_path):
    script = tmp_path / "backend/scripts/configure_flutter.py"
    script.parent.mkdir(parents=True)
    script.touch()
    monkeypatch.setattr(configure_flutter, "__file__", str(script))
    monkeypatch.setattr(
        configure_flutter,
        "Settings",
        lambda: SimpleNamespace(
            supabase_url="https://example.supabase.co",
            supabase_publishable_key=SecretStr("sb_publishable_example"),
            supabase_service_role_key=SecretStr("private-service-key"),
            openai_api_key=SecretStr("private-openai-key"),
        ),
    )
    monkeypatch.setattr("sys.argv", ["configure_flutter", "--api-url", "http://10.0.2.2:8000"])
    configure_flutter.main()
    result = json.loads((tmp_path / "frontend/config/local.json").read_text())
    assert result == {
        "API_BASE_URL": "http://10.0.2.2:8000",
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_example",
    }
