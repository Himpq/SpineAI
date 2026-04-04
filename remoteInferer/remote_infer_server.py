import argparse
import base64
import math
import os
import time
import traceback
import ctypes
from ctypes import wintypes
from typing import Optional

import cv2
import numpy as np
from flask import Flask, jsonify, request

try:
    import psutil
except Exception:
    psutil = None

try:
    import torch
except Exception:
    torch = None
try:
    import timm
except Exception:
    timm = None
try:
    from ultralytics import YOLO
except Exception:
    YOLO = None

from detect_api_v3 import run_pipeline, run_opll_pipeline

try:
    from detect_api_tansit import run_tansit_pipeline
except ImportError as e:
    print(f"Warning: detect_api_tansit import failed: {e}")
    run_tansit_pipeline = None

app = Flask(__name__)

_XRAY_CLASSIFIER = None
_XRAY_CLASSIFIER_INIT_ERROR = None
_CPU_TIMES_PREV = None
_YOLO_MODEL_CACHE = {}
_SEG_MODEL_CACHE = {}
_CLAVICLE_T1_MODEL_CACHE = {}

_XRAY_VIEW_CLASSIFIER = None
_XRAY_VIEW_CLASSIFIER_INIT_ERROR = None

@app.after_request
def add_cors_headers(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return resp


def _decode_image_b64(b64_str: str) -> np.ndarray:
    if not isinstance(b64_str, str) or not b64_str.strip():
        raise ValueError("image_base64 missing")
    if b64_str.startswith("data:") and "," in b64_str:
        b64_str = b64_str.split(",", 1)[1]
    raw = base64.b64decode(b64_str)
    npimg = np.frombuffer(raw, np.uint8)
    img = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Failed to decode image")
    return img


def _encode_image_b64(img_bgr: np.ndarray) -> str:
    ok, buf = cv2.imencode(".png", img_bgr)
    if not ok:
        raise ValueError("Failed to encode image")
    return base64.b64encode(buf).decode("utf-8")

def _jsonify_safe(obj):
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    if isinstance(obj, (list, tuple)):
        return [_jsonify_safe(v) for v in obj]
    if isinstance(obj, dict):
        return {k: _jsonify_safe(v) for k, v in obj.items()}
    return obj


def _collect_windows_cpu_percent():
    global _CPU_TIMES_PREV

    class FILETIME(ctypes.Structure):
        _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]

    idle = FILETIME()
    kernel = FILETIME()
    user = FILETIME()
    ok = ctypes.windll.kernel32.GetSystemTimes(
        ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user)
    )
    if not ok:
        return None

    def _to_int(ft):
        return (ft.dwHighDateTime << 32) | ft.dwLowDateTime

    idle_now = _to_int(idle)
    kernel_now = _to_int(kernel)
    user_now = _to_int(user)

    now = (idle_now, kernel_now, user_now)
    if _CPU_TIMES_PREV is None:
        _CPU_TIMES_PREV = now
        return 0.0

    idle_prev, kernel_prev, user_prev = _CPU_TIMES_PREV
    _CPU_TIMES_PREV = now

    idle_delta = max(0, idle_now - idle_prev)
    kernel_delta = max(0, kernel_now - kernel_prev)
    user_delta = max(0, user_now - user_prev)
    total = kernel_delta + user_delta
    if total <= 0:
        return 0.0
    busy = max(0, total - idle_delta)
    return round((busy / total) * 100.0, 2)


def _collect_windows_memory_mb():
    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [
            ("dwLength", wintypes.DWORD),
            ("dwMemoryLoad", wintypes.DWORD),
            ("ullTotalPhys", ctypes.c_ulonglong),
            ("ullAvailPhys", ctypes.c_ulonglong),
            ("ullTotalPageFile", ctypes.c_ulonglong),
            ("ullAvailPageFile", ctypes.c_ulonglong),
            ("ullTotalVirtual", ctypes.c_ulonglong),
            ("ullAvailVirtual", ctypes.c_ulonglong),
            ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
        ]

    stat = MEMORYSTATUSEX()
    stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
    ok = ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat))
    if not ok:
        return None, None, None

    total_mb = stat.ullTotalPhys / 1024 / 1024
    avail_mb = stat.ullAvailPhys / 1024 / 1024
    used_mb = max(0.0, total_mb - avail_mb)
    return round(total_mb, 2), round(used_mb, 2), float(stat.dwMemoryLoad)


def _collect_windows_process_rss_mb():
    class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("PageFaultCount", wintypes.DWORD),
            ("PeakWorkingSetSize", ctypes.c_size_t),
            ("WorkingSetSize", ctypes.c_size_t),
            ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
            ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
            ("PagefileUsage", ctypes.c_size_t),
            ("PeakPagefileUsage", ctypes.c_size_t),
        ]

    counters = PROCESS_MEMORY_COUNTERS()
    counters.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
    handle = ctypes.windll.kernel32.GetCurrentProcess()
    ok = ctypes.windll.psapi.GetProcessMemoryInfo(
        handle,
        ctypes.byref(counters),
        counters.cb,
    )
    if not ok:
        return None
    return round(counters.WorkingSetSize / 1024 / 1024, 2)


def _normalize_class_name(class_name: Optional[str], class_id: Optional[int]) -> Optional[str]:
    if class_name is not None:
        name = str(class_name).strip().lower()
        compact = name.replace("_", "").replace("-", "").replace(" ", "")
        if "腰椎" in name or "lumbar" in name or "lspine" in compact:
            return "lumbar"
        if "颈椎" in name or "cervical" in name or "cspine" in compact:
            return "cervical"

    if class_id == 1:
        return "lumbar"
    if class_id == 0:
        return "cervical"
    return None


class XRayViewClassifierV2:
    def __init__(self, weight_path: str):
        self.class_names = [
            "c_spine_lateral",
            "buu_ap_chest_pelvis",
            "totalseg_full_ap",
            "shoulder_to_chest_ap",
        ]
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.model = timm.create_model("resnet34", pretrained=False, num_classes=4, in_chans=3)
        state_dict = torch.load(weight_path, map_location=self.device, weights_only=True)
        self.model.load_state_dict(state_dict)
        self.model.to(self.device)
        self.model.eval()

    def predict_array(self, img_bgr: np.ndarray):
        img_gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        img_resized = cv2.resize(img_gray, (320, 320), interpolation=cv2.INTER_LINEAR)
        img3 = np.repeat(img_resized[:, :, None], 3, axis=2).astype(np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        img3 = (img3 - mean) / std
        x = torch.from_numpy(np.transpose(img3, (2, 0, 1))).float().unsqueeze(0).to(self.device)

        with torch.no_grad():
            logits = self.model(x)
            probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
        
        top_idx = int(np.argmax(probs))
        return {
            "class_id": top_idx,
            "class_name": self.class_names[top_idx],
            "confidence": float(probs[top_idx]),
            "probs": {self.class_names[i]: float(probs[i]) for i in range(len(self.class_names))}
        }

def _get_xray_view_classifier():
    global _XRAY_VIEW_CLASSIFIER, _XRAY_VIEW_CLASSIFIER_INIT_ERROR
    if _XRAY_VIEW_CLASSIFIER is not None:
        return _XRAY_VIEW_CLASSIFIER
    if _XRAY_VIEW_CLASSIFIER_INIT_ERROR is not None:
        raise RuntimeError(_XRAY_VIEW_CLASSIFIER_INIT_ERROR)

    try:
        if timm is None:
            raise ImportError("timm is not installed")
        
        base_dir = os.path.dirname(os.path.abspath(__file__))
        model_path = os.path.join(base_dir, "weights", "xray_view_4class.pth")
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Missing view classifier weights at {model_path}")
        
        _XRAY_VIEW_CLASSIFIER = XRayViewClassifierV2(model_path)
        return _XRAY_VIEW_CLASSIFIER
    except Exception as exc:
        _XRAY_VIEW_CLASSIFIER_INIT_ERROR = str(exc)
        print("[ERROR] view classify model init failed")
        traceback.print_exc()
        raise


def _get_xray_classifier():
    global _XRAY_CLASSIFIER, _XRAY_CLASSIFIER_INIT_ERROR

    if _XRAY_CLASSIFIER is not None:
        return _XRAY_CLASSIFIER
    if _XRAY_CLASSIFIER_INIT_ERROR is not None:
        raise RuntimeError(_XRAY_CLASSIFIER_INIT_ERROR)

    try:
        from classify import SpinePredictor

        base_dir = os.path.dirname(os.path.abspath(__file__))
        env_model = os.getenv("CLASSIFY_MODEL_PATH")
        env_model = "./weights/classify.pth"
        model_candidates = [
            env_model,
            os.path.join(base_dir, "classify.pth"),
        ]
        model_path = next((p for p in model_candidates if p and os.path.exists(p)), None)

        if model_path is None:
            raise FileNotFoundError("No valid classifier model found. Set CLASSIFY_MODEL_PATH or place classify.pth in project root.")

        _XRAY_CLASSIFIER = SpinePredictor(model_path=model_path, onnx_path=None)
        return _XRAY_CLASSIFIER
    except Exception as exc:
        _XRAY_CLASSIFIER_INIT_ERROR = str(exc) or repr(exc)
        print("[ERROR] classify model init failed")
        traceback.print_exc()
        raise


def _resolve_model_path(model_name: str, model_path: Optional[str]):
    base_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    alias_dir_map = {
        "clavicle": ["锁骨_T1识别.pt", "锁骨_T1识别", "suogu", "lockbone", "T1", "t1"],
        "t1": ["锁骨_T1识别.pt", "锁骨_T1识别", "T1", "t1"],
        "pelvis": ["盆骨锁骨分割模型_hrnetw32ms.pth", "盆骨锁骨分割模型_hrnetw32ms", "pelvic", "sacrum"],
        "sacrum": ["盆骨锁骨分割模型_hrnetw32ms.pth", "盆骨锁骨分割模型_hrnetw32ms", "pelvic", "sacrum"],
    }
    if model_path:
        candidates.append(model_path)
        candidates.append(os.path.join(base_dir, model_path))
    if model_name:
        names = [model_name]
        names.extend(alias_dir_map.get(model_name, []))
        for resolved_name in names:
            candidates.extend(
                [
                    os.path.join(base_dir, "weights", resolved_name),
                    os.path.join(base_dir, "weights", f"{resolved_name}.pt"),
                    os.path.join(base_dir, "weights", f"{resolved_name}.pth"),
                ]
            )
    for cand in candidates:
        if not cand:
            continue
        if os.path.isfile(cand):
            return cand
        if os.path.isdir(cand):
            for name in sorted(os.listdir(cand)):
                full = os.path.join(cand, name)
                if os.path.isfile(full) and os.path.splitext(full)[1].lower() in {".pt", ".pth", ".onnx"}:
                    return full
    return None


def _extract_points_from_yolo(result):
    pts = []
    if not hasattr(result, "keypoints") or result.keypoints is None:
        return pts
    try:
        arr = result.keypoints.xy
        if arr is None:
            return pts
        arr = arr.cpu().numpy()
        if arr.ndim == 3 and arr.shape[0] > 0:
            for x, y in arr[0]:
                if np.isfinite(x) and np.isfinite(y):
                    pts.append((float(x), float(y)))
    except Exception:
        return []
    return pts


def _compute_pelvic_tilt(points):
    if not points or len(points) < 2:
        return None
    left = min(points, key=lambda p: p[0])
    right = max(points, key=lambda p: p[0])
    dx = float(right[0] - left[0])
    dy = float(right[1] - left[1])
    if abs(dx) < 1e-6 and abs(dy) < 1e-6:
        return None
    angle = math.degrees(math.atan2(dy, dx))
    return {
        "pelvic_tilt_deg": round(float(angle), 4),
        "pelvic_tilt_abs_deg": round(abs(float(angle)), 4),
        "left_point": [round(float(left[0]), 2), round(float(left[1]), 2)],
        "right_point": [round(float(right[0]), 2), round(float(right[1]), 2)],
    }


class _UNetConvBlock(torch.nn.Module):
    def __init__(self, c_in: int, c_out: int):
        super().__init__()
        self.net = torch.nn.Sequential(
            torch.nn.Conv2d(c_in, c_out, kernel_size=3, padding=1, bias=False),
            torch.nn.BatchNorm2d(c_out),
            torch.nn.ReLU(inplace=True),
            torch.nn.Conv2d(c_out, c_out, kernel_size=3, padding=1, bias=False),
            torch.nn.BatchNorm2d(c_out),
            torch.nn.ReLU(inplace=True),
        )

    def forward(self, x):
        return self.net(x)


class _UNetSeg(torch.nn.Module):
    def __init__(self, in_ch: int = 1, out_ch: int = 3, base_ch: int = 32):
        super().__init__()
        c1 = base_ch
        c2 = base_ch * 2
        c3 = base_ch * 4
        c4 = base_ch * 8
        c5 = base_ch * 16
        self.enc1 = _UNetConvBlock(in_ch, c1)
        self.enc2 = _UNetConvBlock(c1, c2)
        self.enc3 = _UNetConvBlock(c2, c3)
        self.enc4 = _UNetConvBlock(c3, c4)
        self.pool = torch.nn.MaxPool2d(2, 2)
        self.bottleneck = _UNetConvBlock(c4, c5)
        self.up4 = torch.nn.ConvTranspose2d(c5, c4, kernel_size=2, stride=2)
        self.dec4 = _UNetConvBlock(c4 + c4, c4)
        self.up3 = torch.nn.ConvTranspose2d(c4, c3, kernel_size=2, stride=2)
        self.dec3 = _UNetConvBlock(c3 + c3, c3)
        self.up2 = torch.nn.ConvTranspose2d(c3, c2, kernel_size=2, stride=2)
        self.dec2 = _UNetConvBlock(c2 + c2, c2)
        self.up1 = torch.nn.ConvTranspose2d(c2, c1, kernel_size=2, stride=2)
        self.dec1 = _UNetConvBlock(c1 + c1, c1)
        self.out = torch.nn.Conv2d(c1, out_ch, kernel_size=1)

    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(self.pool(e1))
        e3 = self.enc3(self.pool(e2))
        e4 = self.enc4(self.pool(e3))
        b = self.bottleneck(self.pool(e4))
        d4 = self.dec4(torch.cat([self.up4(b), e4], dim=1))
        d3 = self.dec3(torch.cat([self.up3(d4), e3], dim=1))
        d2 = self.dec2(torch.cat([self.up2(d3), e2], dim=1))
        d1 = self.dec1(torch.cat([self.up1(d2), e1], dim=1))
        return self.out(d1)


def _load_clavicle_t1_model(model_path: str):
    cache_hit = _CLAVICLE_T1_MODEL_CACHE.get(model_path)
    if cache_hit is not None:
        return cache_hit
    if torch is None:
        raise RuntimeError("torch is required for clavicle/T1 .pt model")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    checkpoint = torch.load(model_path, map_location=device)
    if isinstance(checkpoint, dict) and "model" in checkpoint and isinstance(checkpoint.get("model"), dict):
        state_dict = checkpoint["model"]
        args = checkpoint.get("args", {}) if isinstance(checkpoint.get("args"), dict) else {}
    elif isinstance(checkpoint, dict):
        state_dict = checkpoint
        args = {}
    else:
        raise RuntimeError("Unsupported clavicle/T1 checkpoint format")

    base_ch = int(args.get("base_ch", 32))
    img_size = args.get("img_size", [512, 512])
    if isinstance(img_size, (list, tuple)) and len(img_size) >= 2:
        img_w = int(img_size[0])
        img_h = int(img_size[1])
    else:
        img_w, img_h = 512, 512

    model = _UNetSeg(in_ch=1, out_ch=3, base_ch=base_ch).to(device)
    model.load_state_dict(state_dict, strict=False)
    model.eval()
    loaded = {"model": model, "device": device, "img_w": img_w, "img_h": img_h}
    _CLAVICLE_T1_MODEL_CACHE[model_path] = loaded
    return loaded


def _infer_clavicle_t1_seg(model_path: str, img: np.ndarray):
    loaded = _load_clavicle_t1_model(model_path)
    model = loaded["model"]
    device = loaded["device"]
    img_w = loaded["img_w"]
    img_h = loaded["img_h"]

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    resized = cv2.resize(gray, (img_w, img_h), interpolation=cv2.INTER_LINEAR).astype(np.float32) / 255.0
    tensor = torch.from_numpy(resized).unsqueeze(0).unsqueeze(0).to(device)
    with torch.no_grad():
        logits = model(tensor)
        pred = torch.argmax(logits, dim=1).squeeze(0).detach().cpu().numpy().astype(np.uint8)
    pred = cv2.resize(pred, (w, h), interpolation=cv2.INTER_NEAREST)

    colors = np.array([[0, 0, 0], [0, 255, 255], [255, 80, 80]], dtype=np.uint8)
    color_mask = colors[np.clip(pred, 0, 2)]
    overlay = cv2.addWeighted(img, 0.65, color_mask, 0.35, 0.0)
    return pred, overlay


class _HRNetW32MSSeg(torch.nn.Module):
    def __init__(self, backbone_name: str, in_channels: int = 1, out_channels: int = 5):
        super().__init__()
        self.backbone = timm.create_model(
            backbone_name,
            features_only=True,
            pretrained=False,
            in_chans=in_channels,
        )
        channels = list(self.backbone.feature_info.channels())
        self.proj = torch.nn.ModuleList([torch.nn.Conv2d(c, 128, kernel_size=1) for c in channels])
        self.head = torch.nn.Sequential(
            torch.nn.Conv2d(128 * len(channels), 256, kernel_size=3, padding=1, bias=False),
            torch.nn.BatchNorm2d(256),
            torch.nn.ReLU(inplace=True),
            torch.nn.Conv2d(256, 128, kernel_size=3, padding=1, bias=False),
            torch.nn.BatchNorm2d(128),
            torch.nn.ReLU(inplace=True),
            torch.nn.Conv2d(128, out_channels, kernel_size=1),
        )

    def forward(self, x):
        feats = self.backbone(x)
        target_hw = feats[0].shape[2:]
        merged = []
        for feat, proj in zip(feats, self.proj):
            y = proj(feat)
            if y.shape[2:] != target_hw:
                y = torch.nn.functional.interpolate(y, size=target_hw, mode="bilinear", align_corners=False)
            merged.append(y)
        z = torch.cat(merged, dim=1)
        logits = self.head(z)
        if logits.shape[2:] != x.shape[2:]:
            logits = torch.nn.functional.interpolate(logits, size=x.shape[2:], mode="bilinear", align_corners=False)
        return logits


def _load_seg_model(model_path: str):
    cache_hit = _SEG_MODEL_CACHE.get(model_path)
    if cache_hit is not None:
        return cache_hit
    if torch is None:
        raise RuntimeError("torch is required for .pth segmentation model")
    if timm is None:
        raise RuntimeError("timm is required for .pth segmentation model")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    checkpoint = torch.load(model_path, map_location=device)
    state_dict = checkpoint.get("model_state_dict", checkpoint)
    num_classes = int(checkpoint.get("num_classes", 5))
    image_size = checkpoint.get("image_size", [512, 512])
    image_size = (int(image_size[0]), int(image_size[1]))
    backbone = checkpoint.get("backbone", "hrnet_w32")

    model = _HRNetW32MSSeg(backbone_name=backbone, in_channels=1, out_channels=num_classes).to(device)
    model.load_state_dict(state_dict, strict=False)
    model.eval()

    loaded = {"model": model, "device": device, "image_size": image_size, "num_classes": num_classes}
    _SEG_MODEL_CACHE[model_path] = loaded
    return loaded


def _infer_segmentation(model_path: str, img: np.ndarray):
    loaded = _load_seg_model(model_path)
    model = loaded["model"]
    device = loaded["device"]
    image_size = loaded["image_size"]
    num_classes = loaded["num_classes"]

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    resized = cv2.resize(gray, image_size, interpolation=cv2.INTER_LINEAR).astype(np.float32) / 255.0
    tensor = torch.from_numpy(resized).unsqueeze(0).unsqueeze(0).to(device)
    with torch.no_grad():
        logits = model(tensor)
        pred = torch.argmax(logits, dim=1).squeeze(0).detach().cpu().numpy().astype(np.uint8)
    pred = cv2.resize(pred, (w, h), interpolation=cv2.INTER_NEAREST)

    colors = np.array(
        [[0, 0, 0], [0, 255, 255], [255, 120, 0], [0, 220, 100], [255, 0, 180], [255, 255, 0]],
        dtype=np.uint8,
    )
    color_mask = colors[np.clip(pred, 0, min(num_classes, len(colors)) - 1)]
    overlay = cv2.addWeighted(img, 0.65, color_mask, 0.35, 0.0)
    return pred, overlay


def _infer_with_custom_model(model_name: str, model_path: str, img: np.ndarray, conf: float):
    ext = os.path.splitext(model_path)[1].lower()
    payload = {"status": "ok", "model_name": model_name, "model_path": model_path}

    # clavicle/T1 training script saves UNetSeg state_dict checkpoint, not Ultralytics YOLO checkpoint.
    if ext == ".pt" and model_name in {"clavicle", "t1"}:
        pred_mask, overlay = _infer_clavicle_t1_seg(model_path, img)
        payload.update(
            {
                "image_base64": _encode_image_b64(overlay),
                "image_mimetype": "image/png",
                "mask_shape": [int(pred_mask.shape[0]), int(pred_mask.shape[1])],
                "classes": ["background", "clavicle", "T1"],
            }
        )
        return payload

    if ext in {".pt", ".onnx"} and YOLO is not None:
        model = _YOLO_MODEL_CACHE.get(model_path)
        if model is None:
            model = YOLO(model_path)
            _YOLO_MODEL_CACHE[model_path] = model
        results = model.predict(source=img, conf=conf, verbose=False)
        first = results[0] if results else None
        if first is None:
            raise RuntimeError("empty inference result")
        plot_img = first.plot() if hasattr(first, "plot") else img
        boxes = []
        try:
            if first.boxes is not None:
                xyxy = first.boxes.xyxy.cpu().numpy()
                cls = first.boxes.cls.cpu().numpy() if first.boxes.cls is not None else []
                score = first.boxes.conf.cpu().numpy() if first.boxes.conf is not None else []
                for i, box in enumerate(xyxy):
                    boxes.append(
                        {
                            "xyxy": [float(v) for v in box.tolist()],
                            "cls": float(cls[i]) if i < len(cls) else None,
                            "score": float(score[i]) if i < len(score) else None,
                        }
                    )
        except Exception:
            boxes = []
        points = _extract_points_from_yolo(first)
        payload.update(
            {
                "boxes": boxes,
                "keypoints": [[round(x, 2), round(y, 2)] for x, y in points],
                "image_base64": _encode_image_b64(plot_img),
                "image_mimetype": "image/png",
            }
        )
        if model_name == "pelvis":
            tilt = _compute_pelvic_tilt(points)
            if tilt:
                payload.update(tilt)
        return payload

    if ext == ".pth":
        pred_mask, overlay = _infer_segmentation(model_path, img)
        payload.update(
            {
                "image_base64": _encode_image_b64(overlay),
                "image_mimetype": "image/png",
                "mask_shape": [int(pred_mask.shape[0]), int(pred_mask.shape[1])],
            }
        )
        if model_name == "pelvis":
            ys, xs = np.where(pred_mask > 0)
            if len(xs) > 20:
                midx = float(np.mean(xs))
                left_idx = np.where(xs < midx)[0]
                right_idx = np.where(xs >= midx)[0]
                points = []
                for idxs in (left_idx, right_idx):
                    if len(idxs) == 0:
                        continue
                    xg = xs[idxs]
                    yg = ys[idxs]
                    y_min = float(np.min(yg))
                    top = np.where(yg <= y_min + 6)[0]
                    if len(top) == 0:
                        continue
                    px = float(np.mean(xg[top]))
                    py = float(np.mean(yg[top]))
                    points.append((px, py))
                tilt = _compute_pelvic_tilt(points)
                if tilt:
                    payload.update(tilt)
        return payload

    raise RuntimeError(f"Unsupported model format: {ext}. Supported: .pt/.onnx/.pth")


@app.get("/health")
def health():
    return jsonify({"status": "ok", "ts": time.time()}), 200


@app.get("/metrics")
def metrics():
    data = {
        "ts": time.time(),
        "cpu_percent": None,
        "ram_total_mb": None,
        "ram_used_mb": None,
        "ram_percent": None,
        "process_rss_mb": None,
        "cuda_available": False,
        "gpu_count": 0,
        "gpu_mem_allocated_mb": None,
        "gpu_mem_reserved_mb": None,
    }

    if psutil is not None:
        vm = psutil.virtual_memory()
        data.update(
            {
                "cpu_percent": psutil.cpu_percent(interval=0.1),
                "ram_total_mb": round(vm.total / 1024 / 1024, 2),
                "ram_used_mb": round(vm.used / 1024 / 1024, 2),
                "ram_percent": vm.percent,
                "process_rss_mb": round(psutil.Process(os.getpid()).memory_info().rss / 1024 / 1024, 2),
            }
        )
    elif os.name == "nt":
        cpu_percent = _collect_windows_cpu_percent()
        ram_total_mb, ram_used_mb, ram_percent = _collect_windows_memory_mb()
        process_rss_mb = _collect_windows_process_rss_mb()
        data.update(
            {
                "cpu_percent": cpu_percent,
                "ram_total_mb": ram_total_mb,
                "ram_used_mb": ram_used_mb,
                "ram_percent": ram_percent,
                "process_rss_mb": process_rss_mb,
            }
        )

    if torch is not None and torch.cuda.is_available():
        gpu_allocated_mb = round(torch.cuda.memory_allocated() / 1024 / 1024, 2)
        gpu_reserved_mb = round(torch.cuda.memory_reserved() / 1024 / 1024, 2)
        if gpu_reserved_mb <= 0 and torch.cuda.device_count() > 0:
            gpu_reserved_mb = round(torch.cuda.get_device_properties(0).total_memory / 1024 / 1024, 2)
        data.update(
            {
                "cuda_available": True,
                "gpu_count": torch.cuda.device_count(),
                "gpu_mem_allocated_mb": gpu_allocated_mb,
                "gpu_mem_reserved_mb": gpu_reserved_mb,
            }
        )
    else:
        data.update({"cuda_available": False, "gpu_count": 0})

    return jsonify(data), 200


@app.post("/infer/l4l5")
@app.post("/infer/l4l5locator")
def infer_l4l5():
    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    img = _decode_image_b64(b64)
    try:
        result = run_pipeline(img, return_debug_image=True)
    except Exception as exc:
        print(f"[FATAL] detect_api_v3 error: {exc}")
        os._exit(1)
    debug_img = result.pop("debug_image", None)
    payload = {"status": "ok", **_jsonify_safe(result)}
    if debug_img is not None:
        payload.update({"image_base64": _encode_image_b64(debug_img), "image_mimetype": "image/png"})
    return jsonify(payload), 200


@app.post("/classify/xray")
def classify_xray():
    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    try:
        img = _decode_image_b64(b64)
        predictor = _get_xray_classifier()
        result = predictor.predict_array(img)

        class_id = result.get("class_id")
        class_name = _normalize_class_name(result.get("class_name"), class_id)
        if class_name is None:
            return jsonify({"status": "error", "message": "Failed to normalize class result"}), 500

        confidence = (
            result.get("confidence")
            if result.get("confidence") is not None
            else result.get("probability", result.get("prob", result.get("score")))
        )

        if class_id is None:
            class_id = 1 if class_name == "lumbar" else 0

        payload = {
            "class_name": class_name,
            "class_id": int(class_id),
            "confidence": float(confidence) if confidence is not None else None,
            "class": class_name,
            "label": class_name,
            "type": class_name,
            "id": int(class_id),
            "probability": float(confidence) if confidence is not None else None,
            "prob": float(confidence) if confidence is not None else None,
            "score": float(confidence) if confidence is not None else None,
        }
        return jsonify(payload), 200
    except Exception as exc:
        print("[ERROR] /classify/xray failed")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(exc) or repr(exc)}), 500

@app.post("/classify/xray_view")
def classify_xray_view():
    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    try:
        img = _decode_image_b64(b64)
        predictor = _get_xray_view_classifier()
        result = predictor.predict_array(img)
        
        payload = {
            "status": "ok",
            "class_id": result["class_id"],
            "class_name": result["class_name"],
            "confidence": result["confidence"],
            "probs": result["probs"]
        }
        return jsonify(payload), 200
    except Exception as exc:
        print("[ERROR] /classify/xray_view failed")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(exc) or repr(exc)}), 500

@app.post("/infer/opll")
def infer_opll():
    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    img = _decode_image_b64(b64)
    try:
        result = run_opll_pipeline(img, return_debug_image=True)
    except Exception as exc:
        print(f"[FATAL] detect_api_v3 error: {exc}")
        os._exit(1)
    debug_img = result.pop("debug_image", None)
    payload = {"status": "ok", **_jsonify_safe(result)}
    if "pred_mask" in payload:
        payload["pred_mask"] = None
    if debug_img is not None:
        payload.update({"image_base64": _encode_image_b64(debug_img), "image_mimetype": "image/png"})
    return jsonify(payload), 200


@app.post("/infer/tansit")
def infer_tansit():
    """颈椎关键点检测 + Torg-Pavlov Ratio，返回 keypoints 和 ratios。"""
    if run_tansit_pipeline is None:
        return jsonify({"status": "error", "message": "tansit pipeline not loaded"}), 500

    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    try:
        img = _decode_image_b64(b64)
        result = run_tansit_pipeline(img)
        return jsonify({"status": "ok", **result}), 200
    except Exception as exc:
        print(f"[ERROR] tansit inference error: {exc}")
        return jsonify({"status": "error", "message": str(exc)}), 500


def _infer_extra_model_by_name(model_name: str):
    data = request.get_json(silent=True) or {}
    b64 = data.get("image_base64")
    if not b64:
        return jsonify({"status": "error", "message": "image_base64 missing"}), 400

    try:
        conf = float(data.get("conf", 0.25))
    except Exception:
        conf = 0.25
    default_file_map = {
        "clavicle": "锁骨_T1识别.pt",
        "t1": "锁骨_T1识别.pt",
        "pelvis": "盆骨锁骨分割模型_hrnetw32ms.pth",
        "sacrum": "盆骨锁骨分割模型_hrnetw32ms.pth",
    }
    default_file = default_file_map.get(model_name, model_name)
    default_path = os.path.join("weights", default_file)
    input_model_path = data.get("model_path") or data.get("weights_path") or default_path
    model_path = _resolve_model_path(model_name=model_name, model_path=input_model_path)
    if model_path is None:
        return (
            jsonify(
                {
                    "status": "error",
                    "message": f"model not found for {model_name}",
                    "model_name": model_name,
                    "model_path": input_model_path,
                }
            ),
            404,
        )

    try:
        img = _decode_image_b64(b64)
        payload = _infer_with_custom_model(model_name=model_name, model_path=model_path, img=img, conf=conf)
        return jsonify(payload), 200
    except Exception as exc:
        print(f"[ERROR] infer/{model_name} failed: {exc}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(exc), "model_name": model_name, "model_path": model_path}), 500


@app.post("/infer/clavicle")
@app.post("/infer/lockbone")
@app.post("/infer/suogu")
def infer_clavicle():
    return _infer_extra_model_by_name("clavicle")


@app.post("/infer/t1")
@app.post("/infer/t1locator")
def infer_t1():
    return _infer_extra_model_by_name("t1")


@app.post("/infer/pelvis")
@app.post("/infer/pelvic")
@app.post("/infer/pelvic_tilt")
@app.post("/infer/sacrum")
@app.post("/infer/sacral")
def infer_pelvis():
    return _infer_extra_model_by_name("pelvis")


def main():
    parser = argparse.ArgumentParser(description="Remote inference server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    app.run(host=args.host, port=args.port, debug=False)


if __name__ == "__main__":
    main()
