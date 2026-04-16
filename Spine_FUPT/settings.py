from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"


DEFAULT_CONFIG: dict[str, Any] = {
    "APP_HOST": "0.0.0.0",
    "APP_PORT": 19191,
    "APP_DEBUG": True,
    "SECRET_KEY": "spine-workbench-secret-change-me",
    "REMOTE_INFER_BASE": "http://spine.healthit.cn:15443",
    "REMOTE_INFER_TIMEOUT": 60,
    "ALERT_COBB": 45,
    "STEPFUN_API_BASE": "https://api.stepfun.com/v1",
    "STEPFUN_API_KEY": "",
    "STEPFUN_MODEL": "step-1-8k",
    "ANON_INFER_LIMIT": 3,
    "ANON_INFER_WINDOW": 3600,
    "ADMIN_USER": "admin",
    "ADMIN_PASSWORD": "admin123",
}


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(base)
    for key, value in override.items():
        if isinstance(merged.get(key), dict) and isinstance(value, dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_config() -> dict[str, Any]:
    config = deepcopy(DEFAULT_CONFIG)
    if CONFIG_PATH.exists():
        with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
            loaded_config = json.load(config_file)
        if not isinstance(loaded_config, dict):
            raise ValueError(f"Configuration file must contain a JSON object: {CONFIG_PATH}")
        config = _deep_merge(config, loaded_config)
    return config


CONFIG = load_config()


def get_value(key: str, default: Any = None) -> Any:
    return CONFIG.get(key, default)