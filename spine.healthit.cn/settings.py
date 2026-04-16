"""Shared configuration helpers for spine.healthit.cn."""

from __future__ import annotations

import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
CONFIG_ENV_VAR = "SPINE_HEALTHIT_CONFIG"
DEFAULT_CONFIG_PATH = BASE_DIR / "config.json"


DEFAULT_CONFIG: dict[str, Any] = {
    "app": {
        "host": "0.0.0.0",
        "port": 5000,
        "debug": True,
        "remote_infer_url": "http://127.0.0.1:15443",
        "remote_timeout": 120,
        "fupt_proxy_url": "http://127.0.0.1:19191",
        "fupt_proxy_timeout": 120,
        "demo_dicom_path": "static/demo/dicom3d/spine_vertebrae_float32.nii.gz",
        "default_l4l5_conf": 0.3,
        "default_extra_conf": 0.25,
        "default_thyroid_threshold": 0.5,
    },
    "ai": {
        "stepfun_api_base_url": "https://api.stepfun.com/v1",
        "stepfun_api_key_env": "STEPFUN_API_KEY",
        "analysis_model": "step-1-8k",
    },
    "paths": {
        "weights_dir": "weights",
        "thyroid_root": "../Thyroid",
    },
    "remote_infer": {
        "infer_paths": {
            "opll": "/infer/opll",
            "l4l5": "/infer/l4l5",
            "clavicle": "/infer/clavicle",
            "t1": "/infer/t1",
            "pelvis": "/infer/pelvis",
            "sacrum": "/infer/pelvis",
            "cervical": "/infer/tansit",
            "thyroid": "/infer/thyroid",
            "metrics": "/metrics",
            "dicom3d_example": "/dicom3d/example",
        },
        "extra_model_weight_files": {
            "clavicle": "锁骨_T1识别.pt",
            "t1": "锁骨_T1识别.pt",
            "pelvis": "盆骨锁骨分割模型_hrnetw32ms.pth",
            "sacrum": "盆骨锁骨分割模型_hrnetw32ms.pth",
            "cervical": "cervical",
        },
    },
    "detect_api": {
        "ckpt_path": "/www/wwwroot/Spine/model1.pth",
        "conf_thr": 0.3,
        "target_size": [512, 512],
    },
    "detect_api_v2": {
        "coarse_model_path": "./weights/latest_model.pth",
        "loc_model_path": "./latest_loc_model.pth",
        "coarse_input_size": [512, 1024],
        "loc_input_size": [512, 256],
    },
    "detect_api_v3": {
        "hrnet_weights": "./weights/hrnet_w32ms.pth",
        "hed_weights": "./weights/hedline.pth",
        "opll_weights": "./weights/opll.pth",
    },
}


_CONFIG_CACHE: dict[str, Any] | None = None


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(base)
    for key, value in override.items():
        if isinstance(merged.get(key), dict) and isinstance(value, dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_path(path_value: Any, base_dir: Path | None = None) -> str | None:
    if path_value in (None, ""):
        return None
    path = Path(path_value)
    if not path.is_absolute():
        path = (base_dir or BASE_DIR) / path
    return str(path.resolve(strict=False))


def load_config(force_reload: bool = False) -> dict[str, Any]:
    global _CONFIG_CACHE
    if _CONFIG_CACHE is not None and not force_reload:
        return _CONFIG_CACHE

    config_path_value = os.environ.get(CONFIG_ENV_VAR)
    config_path = Path(config_path_value) if config_path_value else DEFAULT_CONFIG_PATH
    if not config_path.is_absolute():
        config_path = BASE_DIR / config_path

    config = deepcopy(DEFAULT_CONFIG)
    if config_path.exists():
        with config_path.open("r", encoding="utf-8") as config_file:
            loaded_config = json.load(config_file)
        if isinstance(loaded_config, dict):
            config = _deep_merge(config, loaded_config)

    _CONFIG_CACHE = config
    return config


def get_value(*keys: str, default: Any = None) -> Any:
    current: Any = load_config()
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def get_bool(*keys: str, default: bool = False) -> bool:
    value = get_value(*keys, default=default)
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return bool(value)
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def get_int(*keys: str, default: int = 0) -> int:
    value = get_value(*keys, default=default)
    if value is None:
        return default
    return int(value)


def get_float(*keys: str, default: float = 0.0) -> float:
    value = get_value(*keys, default=default)
    if value is None:
        return default
    return float(value)


def get_path(*keys: str, default: Any = None, base_dir: Path | None = None) -> str | None:
    value = get_value(*keys, default=default)
    return resolve_path(value, base_dir=base_dir)