from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"


DEFAULT_CONFIG = {
    "classify_model_path": "./weights/best_model.pth",
    "classify_onnx_path": "./weights/spine_classifier.onnx",
    "classify_img_size": 224,
    "classify_dropout": 0.3,
    "classify_gradio_host": "0.0.0.0",
    "classify_gradio_port": 7860,
    "classify_gradio_share": False,
    "remote_infer_server_host": "0.0.0.0",
    "remote_infer_server_port": 8000,
    "remote_infer_server_debug": False,
    "remote_infer_server_weights_dir": "./weights",
    "remote_infer_server_xray_view_weights": "./weights/xray_view_4class.pth",
    "remote_infer_server_classify_model_candidates": [
        "./weights/best_model.pth",
        "./weights/classify.pth",
        "./classify.pth",
    ],
    "remote_infer_server_default_model_files": {
        "clavicle": "锁骨_T1识别.pt",
        "t1": "锁骨_T1识别.pt",
        "pelvis": "盆骨锁骨分割模型_hrnetw32ms.pth",
        "sacrum": "盆骨锁骨分割模型_hrnetw32ms.pth",
    },
    "remote_infer_server_model_aliases": {
        "clavicle": ["锁骨_T1识别.pt", "锁骨_T1识别", "suogu", "lockbone", "T1", "t1"],
        "t1": ["锁骨_T1识别.pt", "锁骨_T1识别", "T1", "t1"],
        "pelvis": ["盆骨锁骨分割模型_hrnetw32ms.pth", "盆骨锁骨分割模型_hrnetw32ms", "pelvic", "sacrum"],
        "sacrum": ["盆骨锁骨分割模型_hrnetw32ms.pth", "盆骨锁骨分割模型_hrnetw32ms", "pelvic", "sacrum"],
    },
    "remote_infer_server_xray_view_input_size": 320,
    "remote_infer_server_clavicle_t1_min_area": 20,
    "remote_infer_server_default_image_size": [512, 512],
    "remote_infer_server_default_conf": 0.15,
    "remote_infer_server_tansit_conf": 0.3,
    "tansit_weights": "./weights/tansit.pth",
    "detect_v3_hrnet_weights": "./weights/hrnet_w32ms.pth",
    "detect_v3_hed_weights": "./weights/hedline.pth",
    "detect_v3_opll_weights": "./weights/opll.pth",
    "detect_v3_thyroid_root": "../Thyroid",
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


def _lookup(path: str, data: dict[str, Any], default: Any = None) -> Any:
    current: Any = data
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return default
        current = current[part]
    return current


def get_value(path: str, default: Any = None) -> Any:
    return _lookup(path, CONFIG, default)


def resolve_path(value: Any) -> str | None:
    if value is None:
        return None
    candidate = Path(str(value))
    if not candidate.is_absolute():
        candidate = (BASE_DIR / candidate).resolve()
    return str(candidate)


def get_path(path: str, default: Any = None) -> str | None:
    value = get_value(path, default=default)
    return resolve_path(value)


def first_existing_path(candidates: Any) -> str | None:
    if candidates is None:
        return None
    if isinstance(candidates, (str, Path)):
        iterable = [candidates]
    else:
        iterable = list(candidates)
    for candidate in iterable:
        resolved = resolve_path(candidate)
        if resolved and Path(resolved).is_file():
            return resolved
    return None