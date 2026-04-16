"""
Standalone inference pipeline (no project imports):
- HRNet keypoints (22 channels, default S1->L1)
"""
import os
from typing import Tuple, List, Dict

import cv2
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image
import timm
import torchvision.models as tvm
import pathlib
import torch.serialization as serialization
import pickle
import types
import sys
import io
import zlib
import gzip
import importlib

from settings import get_path

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
ROOT = os.path.dirname(os.path.abspath(__file__))
HRNET_WEIGHTS = get_path("detect_v3_hrnet_weights")
HED_WEIGHTS   = get_path("detect_v3_hed_weights")
OPLL_WEIGHTS  = get_path("detect_v3_opll_weights")
THYROID_ROOT  = get_path("detect_v3_thyroid_root")


def _tensor_to_numpy(tensor: torch.Tensor) -> np.ndarray:
    """Convert a tensor to a NumPy array without relying on torch's NumPy bridge."""
    return np.asarray(tensor.detach().cpu().tolist())

# ------------------------------------------------------------
# Thyroid Segmentation (imports from Thyroid project)
# ------------------------------------------------------------
_thyroid_model_cache = {}

def _load_thyroid_model(model_id: str = "swin-unet"):
    """
    Load thyroid segmentation model from D:/1_Himpq/Code/Thyroid/res/{save_dir}/best_{tag}.pth
    Cache per model_id.
    """
    model_id = model_id.lower()
    if model_id in _thyroid_model_cache:
        return _thyroid_model_cache[model_id]

    if THYROID_ROOT not in sys.path:
        sys.path.append(THYROID_ROOT)
    try:
        get_model = importlib.import_module("utils.model").get_model
    except Exception as e:
        raise ImportError(f"Cannot import Thyroid get_model: {e}")

    # map save dir
    if "deeplab" in model_id:
        save_dir = "res/deeplabv3_"
    elif "hrnet" in model_id:
        save_dir = "res/hrnet_"
    elif "segformer" in model_id or "mit" in model_id:
        save_dir = "res/segformer_"
    elif "swin" in model_id:
        save_dir = "res/swin_unet_"
    else:
        save_dir = "res/unet"

    tag = model_id.replace("+", "plus")
    ckpt_path = os.path.join(THYROID_ROOT, save_dir, f"best_{tag}.pth")
    if not os.path.exists(ckpt_path):
        raise FileNotFoundError(f"Thyroid checkpoint not found: {ckpt_path}")

    model = get_model(model_id, in_channels=1, out_channels=1)
    ckpt = torch.load(ckpt_path, map_location=DEVICE)
    state = ckpt.get("model", ckpt)
    model.load_state_dict(state)
    model.to(DEVICE)
    model.eval()
    _thyroid_model_cache[model_id] = model
    return model


@torch.no_grad()
def run_thyroid_pipeline(img_bgr: np.ndarray, model_id: str = "swin-unet", target_size: int = 512, threshold: float = 0.5):
    """
    Simple thyroid nodule segmentation: grayscale -> resize -> normalize -> model -> mask -> overlay
    Returns dict with overlay, mask, logits statistics.
    """
    if img_bgr is None:
        raise ValueError("input image is None")
    # preprocessing
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    resized = cv2.resize(gray, (target_size, target_size), interpolation=cv2.INTER_LINEAR)
    tensor = torch.from_numpy(resized).float().unsqueeze(0).unsqueeze(0) / 255.0  # 1x1xH xW
    tensor = (tensor - 0.5) / 0.5
    tensor = tensor.to(DEVICE)

    model = _load_thyroid_model(model_id)
    logits = model(tensor)
    probs = _tensor_to_numpy(torch.sigmoid(logits)[0, 0])
    mask = (probs > threshold).astype(np.uint8) * 255
    # resize back
    mask_orig = cv2.resize(mask, (w, h), interpolation=cv2.INTER_NEAREST)
    overlay = img_bgr.copy()
    color = np.zeros_like(overlay)
    color[:, :, 0] = mask_orig  # blue channel
    overlay = cv2.addWeighted(overlay, 0.8, color, 0.4, 0)
    return {
        "prob_map": probs,
        "mask": mask_orig,
        "overlay": overlay,
        "threshold": threshold,
        "model_id": model_id,
    }
# ------------------------------------------------------------
# HRNet Keypoint Model (W32 multi-scale head, stride=4 output)
# ------------------------------------------------------------
class HRNetW32MultiScale(nn.Module):
    """
    Mirror of the training definition in ../SMIS3/train_hrnet_2.py (HRNetMultiScale).
    Uses four feature stages of HRNet-W32, projects each to 256 channels,
    upsamples to 1/4 resolution, concatenates, then predicts 22 heatmaps.
    """
    def __init__(self, num_joints: int = 22, backbone_id: str = "hrnet_w32_ms"):
        super().__init__()
        # allow loading checkpoints saved with *_ms identifier
        backbone_id_clean = backbone_id.replace("-", "_")
        if backbone_id_clean.endswith("_ms"):
            backbone_id_clean = backbone_id_clean[:-3]

        self.backbone = timm.create_model(
            backbone_id_clean,
            pretrained=False,               # weights come from checkpoint; avoid downloading
            features_only=True,
            out_indices=(0, 1, 2, 3),
            in_chans=1,
        )

        ch = self.backbone.feature_info.channels()  # e.g., [64, 128, 256, 512]
        self.fuse = nn.ModuleList([nn.Conv2d(c, 256, kernel_size=1, bias=False) for c in ch])
        self.head = nn.Sequential(
            nn.Conv2d(256 * 4, 256, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
            nn.Conv2d(256, num_joints, kernel_size=1),
        )

    def forward(self, x):
        feats = self.backbone(x)  # list of 4 feature maps, strides 4/8/16/32
        ref_h, ref_w = feats[0].shape[2:]
        target_h, target_w = x.shape[2] // 4, x.shape[3] // 4

        ups = []
        for conv, f in zip(self.fuse, feats):
            u = conv(f)
            if u.shape[2:] != (ref_h, ref_w):
                u = F.interpolate(u, size=(ref_h, ref_w), mode="bilinear", align_corners=False)
            ups.append(u)

        fused = torch.cat(ups, dim=1)
        out = self.head(fused)
        if out.shape[2:] != (target_h, target_w):
            out = F.interpolate(out, size=(target_h, target_w), mode="bilinear", align_corners=False)
        return out


# ------------------------------------------------------------
# HED Line Detector (from iliac_line/model.py simplified)
# ------------------------------------------------------------
class HEDLineDetector(nn.Module):
    def __init__(self, pretrained=False):
        super().__init__()
        vgg = tvm.vgg16_bn(weights=tvm.VGG16_BN_Weights.IMAGENET1K_V1 if pretrained else None)
        # adapt first conv to 1 channel
        conv1 = vgg.features[0]
        new_conv1 = nn.Conv2d(1, conv1.out_channels, kernel_size=conv1.kernel_size, stride=conv1.stride, padding=conv1.padding, bias=conv1.bias is not None)
        with torch.no_grad():
            new_conv1.weight[:] = conv1.weight.mean(dim=1, keepdim=True)
            if conv1.bias is not None:
                new_conv1.bias[:] = conv1.bias
        vgg.features[0] = new_conv1
        self.slice1 = vgg.features[:6]
        self.slice2 = vgg.features[6:13]
        self.slice3 = vgg.features[13:23]
        self.slice4 = vgg.features[23:33]
        self.slice5 = vgg.features[33:43]

        self.side1 = nn.Conv2d(64, 1, 1)
        self.side2 = nn.Conv2d(128, 1, 1)
        self.side3 = nn.Conv2d(256, 1, 1)
        self.side4 = nn.Conv2d(512, 1, 1)
        self.side5 = nn.Conv2d(512, 1, 1)
        self.fuse = nn.Conv2d(5, 1, 1, bias=False)
        nn.init.constant_(self.fuse.weight, 0.2)

    def _up(self, x, ref):
        return F.interpolate(x, size=ref.shape[2:], mode="bilinear", align_corners=False)

    def forward(self, x):
        h1 = self.slice1(x)
        h2 = self.slice2(h1)
        h3 = self.slice3(h2)
        h4 = self.slice4(h3)
        h5 = self.slice5(h4)
        s1 = self._up(self.side1(h1), x)
        s2 = self._up(self.side2(h2), x)
        s3 = self._up(self.side3(h3), x)
        s4 = self._up(self.side4(h4), x)
        s5 = self._up(self.side5(h5), x)
        fuse = torch.sigmoid(self.fuse(torch.cat([s1, s2, s3, s4, s5], dim=1)))
        sides = [torch.sigmoid(o) for o in [s1, s2, s3, s4, s5]]
        sides.append(fuse)
        return sides


# ------------------------------------------------------------
# OPLL UNet Model
# ------------------------------------------------------------
class DoubleConv(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, 3, padding=1),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_channels, out_channels, 3, padding=1),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True)
        )
    def forward(self, x):
        return self.conv(x)

class UNetOPLL(nn.Module):
    def __init__(self, in_channels=1, out_channels=1):
        super().__init__()
        self.enc1 = DoubleConv(in_channels, 64)
        self.pool1 = nn.MaxPool2d(2)
        self.enc2 = DoubleConv(64, 128)
        self.pool2 = nn.MaxPool2d(2)
        self.enc3 = DoubleConv(128, 256)
        self.pool3 = nn.MaxPool2d(2)
        self.enc4 = DoubleConv(256, 512)
        self.pool4 = nn.MaxPool2d(2)
        self.bottleneck = DoubleConv(512, 1024)
        self.up_conv1 = nn.Conv2d(1024, 512, 1)
        self.dec1 = DoubleConv(1024, 512)
        self.up_conv2 = nn.Conv2d(512, 256, 1)
        self.dec2 = DoubleConv(512, 256)
        self.up_conv3 = nn.Conv2d(256, 128, 1)
        self.dec3 = DoubleConv(256, 128)
        self.up_conv4 = nn.Conv2d(128, 64, 1)
        self.dec4 = DoubleConv(128, 64)
        self.out = nn.Conv2d(64, out_channels, 1)
    
    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(self.pool1(e1))
        e3 = self.enc3(self.pool2(e2))
        e4 = self.enc4(self.pool3(e3))
        b = self.bottleneck(self.pool4(e4))
        u1 = self.up_conv1(b)
        u1 = F.interpolate(u1, size=(e4.size(2), e4.size(3)), mode='bilinear', align_corners=True)
        d1 = self.dec1(torch.cat([u1, e4], dim=1))
        u2 = self.up_conv2(d1)
        u2 = F.interpolate(u2, size=(e3.size(2), e3.size(3)), mode='bilinear', align_corners=True)
        d2 = self.dec2(torch.cat([u2, e3], dim=1))
        u3 = self.up_conv3(d2)
        u3 = F.interpolate(u3, size=(e2.size(2), e2.size(3)), mode='bilinear', align_corners=True)
        d3 = self.dec3(torch.cat([u3, e2], dim=1))
        u4 = self.up_conv4(d3)
        u4 = F.interpolate(u4, size=(e1.size(2), e1.size(3)), mode='bilinear', align_corners=True)
        d4 = self.dec4(torch.cat([u4, e1], dim=1))
        return torch.sigmoid(self.out(d4))


# ------------------------------------------------------------
# Utils
# ------------------------------------------------------------
def letterbox_gray(img: np.ndarray, size: int = 512) -> Tuple[np.ndarray, float, int, int]:
    h, w = img.shape[:2]
    scale = size / max(h, w)
    nh, nw = int(round(h * scale)), int(round(w * scale))
    resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    pad_h = size - nh
    pad_w = size - nw
    top = pad_h // 2
    left = pad_w // 2
    boxed = cv2.copyMakeBorder(resized, top, pad_h - top, left, pad_w - left, cv2.BORDER_CONSTANT, value=0)
    return boxed, scale, left, top


def reorder_quad(quad: List[Tuple[float, float]]):
    pts = np.array(quad, dtype=np.float32)
    ys = pts[:, 1]
    xs = pts[:, 0]
    top_idx = ys.argsort()[:2]
    bot_idx = ys.argsort()[2:]
    top = pts[top_idx]
    bot = pts[bot_idx]
    lt = top[np.argmin(top[:, 0])]
    rt = top[np.argmax(top[:, 0])]
    lb = bot[np.argmin(bot[:, 0])]
    rb = bot[np.argmax(bot[:, 0])]
    return [lt.tolist(), rt.tolist(), rb.tolist(), lb.tolist()]


def spine_midpoints(coords: List[Tuple[float, float]], reverse_order=True) -> List[Tuple[float, float]]:
    """
    从关键点还原每个椎体/骶骨的中心点（用于曲率计算）
    """
    mids = []
    if reverse_order:
        # S1 两点
        if len(coords) >= 2:
            s1 = coords[0:2]
            if len(s1) == 2:
                mids.append(((s1[0][0] + s1[1][0]) / 2.0, (s1[0][1] + s1[1][1]) / 2.0))
        # L5->L1
        for k in range(5):
            quad = coords[2 + 4 * k: 2 + 4 * (k + 1)]
            if len(quad) < 4:
                break
            poly = reorder_quad(quad)
            mids.append(((poly[0][0] + poly[2][0]) / 2.0, (poly[0][1] + poly[2][1]) / 2.0))
    else:
        # L1->L5 then S1
        for k in range(5):
            quad = coords[4 * k: 4 * k + 4]
            if len(quad) < 4:
                break
            poly = reorder_quad(quad)
            mids.append(((poly[0][0] + poly[2][0]) / 2.0, (poly[0][1] + poly[2][1]) / 2.0))
        if len(coords) >= 2:
            s1 = coords[-2:]
            mids.append(((s1[0][0] + s1[1][0]) / 2.0, (s1[0][1] + s1[1][1]) / 2.0))
    return mids


def compute_spine_curvature_sum(coords: List[Tuple[float, float]], reverse_order=True) -> float:
    """
    计算脊柱中轴折转总角度（deg）
    - 先做简单平滑，降低噪声
    - 再用相邻切线夹角求和
    """
    pts = spine_midpoints(coords, reverse_order)
    if len(pts) < 3:
        return 0.0
    # 按 y 从上到下排序
    pts = sorted(pts, key=lambda p: p[1])
    pts = np.array(pts, dtype=np.float32)

    # 简单滑动平均平滑
    n = len(pts)
    win = 5 if n >= 5 else 3
    half = win // 2
    smoothed = []
    for i in range(n):
        l = max(0, i - half)
        r = min(n, i + half + 1)
        smoothed.append(pts[l:r].mean(axis=0))
    smoothed = np.array(smoothed, dtype=np.float32)

    # 切线向量
    vecs = smoothed[1:] - smoothed[:-1]
    total_deg = 0.0
    for i in range(len(vecs) - 1):
        v1 = vecs[i]
        v2 = vecs[i + 1]
        n1 = np.linalg.norm(v1)
        n2 = np.linalg.norm(v2)
        if n1 < 1e-6 or n2 < 1e-6:
            continue
        cosang = np.clip(np.dot(v1, v2) / (n1 * n2), -1.0, 1.0)
        ang = np.degrees(np.arccos(cosang))
        # 限制单段异常角度，避免噪声爆炸
        if ang > 60:
            ang = 60
        total_deg += ang
    return float(total_deg)


# ------------------------------------------------------------
# Load models (singleton)
# ------------------------------------------------------------
_HR_MODEL = None
_HED_MODEL = None
_OPLL_MODEL = None


def _torch_load_compat(path, map_location, pickle_module=None, weights_only=False):
    """
    兼容加载多种 checkpoint 格式：
    - 标准 torch.save(zip/pickle)
    - zlib/gzip 压缩后的 checkpoint（二进制首字节常见 0x78）
    """
    try:
        kwargs = {"map_location": map_location, "weights_only": weights_only}
        if pickle_module is not None:
            kwargs["pickle_module"] = pickle_module
        return torch.load(path, **kwargs)
    except TypeError:
        kwargs = {"map_location": map_location}
        if pickle_module is not None:
            kwargs["pickle_module"] = pickle_module
        return torch.load(path, **kwargs)
    except Exception as first_exc:
        try:
            with open(path, "rb") as f:
                raw = f.read()

            decompressed = None
            # zlib stream (often starts with 0x78)
            try:
                decompressed = zlib.decompress(raw)
            except Exception:
                pass

            # gzip stream fallback
            if decompressed is None:
                try:
                    decompressed = gzip.decompress(raw)
                except Exception:
                    pass

            if decompressed is None:
                raise first_exc

            buf = io.BytesIO(decompressed)
            try:
                kwargs = {"map_location": map_location, "weights_only": weights_only}
                if pickle_module is not None:
                    kwargs["pickle_module"] = pickle_module
                return torch.load(buf, **kwargs)
            except TypeError:
                kwargs = {"map_location": map_location}
                if pickle_module is not None:
                    kwargs["pickle_module"] = pickle_module
                buf.seek(0)
                return torch.load(buf, **kwargs)
        except Exception as second_exc:
            raise RuntimeError(f"Failed to load checkpoint: {path}. Primary error: {first_exc}. Fallback error: {second_exc}") from second_exc


def load_models():
    global _HR_MODEL, _HED_MODEL, _OPLL_MODEL

    # Cross-platform path fixer for pickled checkpoints
    if os.name == "nt":
        target_path_class = pathlib.WindowsPath
        def path_factory(*args, **kwargs):
            return pathlib.WindowsPath(*args, **kwargs)
    else:
        target_path_class = pathlib.PosixPath
        def path_factory(*args, **kwargs):
            return pathlib.PosixPath(*args, **kwargs)

    class PathFixUnpickler(pickle.Unpickler):
        def find_class(self, module, name):
            if module.startswith("pathlib") and ("WindowsPath" in name or "PureWindowsPath" in name or "PosixPath" in name or "PurePosixPath" in name):
                return path_factory
            return super().find_class(module, name)

    pickle_module = types.ModuleType("pathfix_pickle")
    pickle_module.Unpickler = PathFixUnpickler
    pickle_module.Pickler = pickle.Pickler
    pickle_module.load = pickle.load
    pickle_module.loads = pickle.loads
    pickle_module.dump = pickle.dump
    pickle_module.dumps = pickle.dumps
    if _HR_MODEL is None:
        model = HRNetW32MultiScale(num_joints=22, backbone_id="hrnet_w32_ms").to(DEVICE)
        state = _torch_load_compat(HRNET_WEIGHTS, map_location=DEVICE, weights_only=False, pickle_module=pickle_module)
        model.load_state_dict(state["model_state"] if isinstance(state, dict) and "model_state" in state else state, strict=False)
        model.eval()
        _HR_MODEL = model
    if _HED_MODEL is None:
        model = HEDLineDetector(pretrained=False).to(DEVICE)
        state = _torch_load_compat(HED_WEIGHTS, map_location=DEVICE, weights_only=False, pickle_module=pickle_module)
        model.load_state_dict(state["model_state"] if isinstance(state, dict) and "model_state" in state else state, strict=False)
        model.eval()
        _HED_MODEL = model
    if _OPLL_MODEL is None:
        model = UNetOPLL(in_channels=1, out_channels=1).to(DEVICE)
        state = _torch_load_compat(OPLL_WEIGHTS, map_location=DEVICE, weights_only=False)
        model.load_state_dict(state if not isinstance(state, dict) or "model_state" not in state else state["model_state"])
        model.eval()
        _OPLL_MODEL = model
    return _HR_MODEL, _HED_MODEL, _OPLL_MODEL


# ------------------------------------------------------------
# Inference
# ------------------------------------------------------------
def infer_hrnet(img_bgr: np.ndarray) -> Tuple[List[Tuple[float, float]], np.ndarray]:
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    gray = clahe.apply(gray)
    boxed, scale, left, top = letterbox_gray(gray, 512)
    norm = (boxed.astype(np.float32) / 255.0 - 0.5) / 0.5
    tensor = torch.from_numpy(norm).unsqueeze(0).unsqueeze(0).to(DEVICE)
    model, _, _ = load_models()
    with torch.no_grad():
        hm = model(tensor)[0]  # (22,128,128)
    # temperature scaling + softmax
    temp = 0.6
    flat = (hm / temp).view(22, -1)
    probs = torch.softmax(flat, dim=1)
    idx = probs.argmax(dim=1)
    Hh, Wh = hm.shape[1:]
    y = (idx // Wh).float() * 4 - top
    x = (idx % Wh).float() * 4 - left
    x = _tensor_to_numpy(x / scale)
    y = _tensor_to_numpy(y / scale)
    coords = [(float(px), float(py)) for px, py in zip(x, y)]
    return coords, _tensor_to_numpy(hm)


def infer_hed_line(img_bgr: np.ndarray) -> Tuple[int, np.ndarray]:
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    boxed, scale, left, top = letterbox_gray(gray, 512)
    norm = (boxed.astype(np.float32) / 255.0 - 0.5) / 0.5
    tensor = torch.from_numpy(norm).unsqueeze(0).unsqueeze(0).to(DEVICE)
    _, hed, _ = load_models()
    with torch.no_grad():
        prob = _tensor_to_numpy(hed(tensor)[-1][0, 0])
    # resize back to original
    prob_full = cv2.resize(prob, (gray.shape[1], gray.shape[0]), interpolation=cv2.INTER_LINEAR)
    skeleton = postprocess_prob_map(prob_full, thresh=0.5)
    ys, xs = np.nonzero(skeleton)
    if len(ys) > 0:
        peak_y = ys.min()  # highest point
    else:
        peak_y, _ = np.unravel_index(np.argmax(prob_full), prob_full.shape)
    return int(peak_y), prob_full


def infer_opll(img_bgr: np.ndarray) -> np.ndarray:
    """OPLL分割推理"""
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    top = int(h * 0.05)
    bottom = int(h * 0.95)
    left = int(w * 0.12)
    right = int(w * 0.9)
    ct_region = gray[top:bottom, left:right]
    cols = np.where(ct_region.max(axis=0) > 10)[0]
    if len(cols) > 0:
        ct_region = ct_region[:, cols[0]:cols[-1]+1]
    ct_region = cv2.resize(ct_region, (600, 600))
    gray_inv = 255 - ct_region
    tensor = torch.from_numpy(gray_inv).float().unsqueeze(0).unsqueeze(0) / 255.0
    tensor = tensor.to(DEVICE)
    _, _, opll = load_models()
    with torch.no_grad():
        pred = opll(tensor)
    pred_mask = (_tensor_to_numpy(pred.squeeze()) * 255).astype(np.uint8)
    return pred_mask


# ------------------------------------------------------------
# Drawing
# ------------------------------------------------------------
def draw_keypoints(img: np.ndarray, coords: List[Tuple[float, float]], reverse_order=True, hed_y: int = None) -> Tuple[np.ndarray, int]:
    vis = img.copy()
    if len(coords) < 22:
        return vis, 0

    def draw_trisect_right_edge(pt_top_right, pt_bottom_right, color):
        a2 = np.array(pt_top_right, dtype=np.float32)
        b2 = np.array(pt_bottom_right, dtype=np.float32)
        v = b2 - a2
        v_len = np.linalg.norm(v)
        if v_len < 1e-3:
            return
        perp = np.array([-v[1], v[0]], dtype=np.float32)
        if perp[0] < 0:
            perp = -perp
        perp = perp / (np.linalg.norm(perp) + 1e-6)
        offset = max(6, int(v_len * 0.08))
        p1 = a2 + perp * offset
        p2 = b2 + perp * offset
        cv2.line(vis, tuple(np.int32(p1)), tuple(np.int32(p2)), color, 2, cv2.LINE_AA)
        # trisect marks
        v_unit = v / v_len
        t1 = p1 + v_unit * (v_len / 3.0)
        t2 = p1 + v_unit * (2 * v_len / 3.0)
        for t in (t1, t2):
            cv2.circle(vis, tuple(np.int32(t)), 3, color, -1, cv2.LINE_AA)

    colors = [
        (255, 128, 0),   # L5
        (0, 200, 255),   # L4
        (0, 255, 128),   # L3
        (128, 200, 255), # L2
        (255, 0, 128),   # L1
    ]
    alpha = 0.35
    score_total = 0
    spine_points = []

    if reverse_order:
        s1 = coords[0:2]
        for k in range(5):  # L5->L1
            quad = coords[2 + 4 * k : 2 + 4 * (k + 1)]
            if len(quad) < 4:
                break
            poly = np.array(reorder_quad(quad), dtype=np.int32)
            color = colors[min(k, len(colors)-1)]
            # fill
            overlay = vis.copy()
            cv2.fillPoly(overlay, [poly], color)
            vis = cv2.addWeighted(overlay, alpha, vis, 1 - alpha, 0)
            cv2.polylines(vis, [poly], True, color, 2, cv2.LINE_AA)
            for pt in poly:
                cv2.circle(vis, tuple(pt), 3, (0, 255, 0), -1, cv2.LINE_AA)
            # trisect right edge for L4, L5 (k=0=>L5, k=1=>L4)
            if k <= 1:
                rt, rb = poly[1], poly[2]  # after reorder lt,rt,rb,lb
                draw_trisect_right_edge(rt, rb, color)
                if hed_y is not None:
                    y0, y1 = rt[1], rb[1]
                    if (hed_y - y0) * (hed_y - y1) <= 0 and abs(y1 - y0) > 1e-3:
                        t = (hed_y - y0) / (y1 - y0)
                        idx = min(2, max(0, int(t * 3)))
                        val = (-1, -2, -3)[idx] if k == 0 else (3, 2, 1)[idx]
                        score_total += val
            # spine mid-point of this vertebra
            spine_points.append(((poly[0][0]+poly[2][0])/2.0, (poly[0][1]+poly[2][1])/2.0))
        if len(s1) == 2:
            cv2.line(vis, (int(s1[0][0]), int(s1[0][1])), (int(s1[1][0]), int(s1[1][1])), (255, 0, 255), 3, cv2.LINE_AA)
            cv2.circle(vis, (int(s1[0][0]), int(s1[0][1])), 4, (255, 0, 255), -1)
            cv2.circle(vis, (int(s1[1][0]), int(s1[1][1])), 4, (255, 0, 255), -1)
            spine_points.append(((s1[0][0]+s1[1][0])/2.0, (s1[0][1]+s1[1][1])/2.0))
    else:
        # legacy L1->L5 then S1
        for k in range(5):
            quad = coords[4 * k : 4 * k + 4]
            if len(quad) < 4:
                break
            poly = np.array(reorder_quad(quad), dtype=np.int32)
            cv2.polylines(vis, [poly], True, (0, 165, 255), 2, cv2.LINE_AA)
            for pt in poly:
                cv2.circle(vis, tuple(pt), 3, (0, 255, 0), -1, cv2.LINE_AA)
            spine_points.append(((poly[0][0]+poly[2][0])/2.0, (poly[0][1]+poly[2][1])/2.0))
        s1 = coords[-2:]
        cv2.line(vis, (int(s1[0][0]), int(s1[0][1])), (int(s1[1][0]), int(s1[1][1])), (255, 0, 255), 3, cv2.LINE_AA)
        spine_points.append(((s1[0][0]+s1[1][0])/2.0, (s1[0][1]+s1[1][1])/2.0))

    # draw smoothed spine midline
    if len(spine_points) >= 3:
        pts = np.array(sorted(spine_points, key=lambda p: p[1]), dtype=np.float32)
        # simple polyfit smoothing on y as function of order
        xs = pts[:,0]; ys=pts[:,1]; t = np.arange(len(pts))
        coeff_x = np.polyfit(t, xs, deg=min(3, len(pts)-1))
        coeff_y = np.polyfit(t, ys, deg=min(3, len(pts)-1))
        t_new = np.linspace(0, len(pts)-1, num=200)
        xs_new = np.polyval(coeff_x, t_new)
        ys_new = np.polyval(coeff_y, t_new)
        line_pts = np.stack([xs_new, ys_new], axis=1).astype(np.int32)
        for i in range(len(line_pts)-1):
            cv2.line(vis, tuple(line_pts[i]), tuple(line_pts[i+1]), (255,255,0), 2, cv2.LINE_AA)

    return vis, score_total


def compute_cobb_angle(coords: List[Tuple[float, float]], reverse_order=True):
    if len(coords) < 22:
        return 0.0, None, None, None
    try:
        if reverse_order:
            s1_pts = coords[0:2]
            # L2 block: k=3 (S1 + L5 + L4 + L3 + L2)
            start = 2 + 4 * 3
            l2_quad = coords[start:start+4]
        else:
            s1_pts = coords[-2:]
            # L2 block is k=3 counted from top (L1 index0, L2 index1?) 鈥?for simplicity fallback
            l2_quad = coords[4:8] if len(coords) >= 8 else []

        if len(s1_pts) < 2 or len(l2_quad) < 2:
            return 0.0, None, None, None

        v = np.array(s1_pts[1]) - np.array(s1_pts[0])

        l2_sorted = sorted(l2_quad, key=lambda p: p[1])[:2]
        l2_sorted = sorted(l2_sorted, key=lambda p: p[0])
        u = np.array(l2_sorted[1]) - np.array(l2_sorted[0])

        norm_u = np.linalg.norm(u)
        norm_v = np.linalg.norm(v)
        if norm_u < 1e-6 or norm_v < 1e-6:
            return 0.0, None, None, None
        # 直接用 L2 上终板向量 与 S1 上终板向量的夹角（取锐角 0-90）
        cosang = np.clip(np.dot(u, v) / (norm_u * norm_v), -1.0, 1.0)
        ang = np.degrees(np.arccos(cosang))
        if ang > 90:
            ang = 180 - ang
        u_hat = u / (norm_u + 1e-6)
        v_hat = v / (norm_v + 1e-6)
        return float(ang), (tuple(l2_sorted[0]), tuple(l2_sorted[1])), (tuple(s1_pts[0]), tuple(s1_pts[1])), (u_hat, v_hat)
    except Exception:
        return 0.0, None, None, None


def overlay_heatmap(base_bgr: np.ndarray, heat: np.ndarray, alpha=0.4) -> np.ndarray:
    hm_norm = cv2.normalize(heat, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    hm_color = cv2.applyColorMap(hm_norm, cv2.COLORMAP_JET)
    hm_color = cv2.resize(hm_color, (base_bgr.shape[1], base_bgr.shape[0]))
    return cv2.addWeighted(base_bgr, 1 - alpha, hm_color, alpha, 0)

def draw_hed_contour(base_bgr: np.ndarray, prob_full: np.ndarray, thresh: float = 0.5) -> np.ndarray:
    bin_mask = (prob_full >= thresh).astype(np.uint8)
    bin_mask = cv2.morphologyEx(bin_mask, cv2.MORPH_CLOSE, np.ones((3,3), np.uint8))
    contours, _ = cv2.findContours(bin_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    overlay = base_bgr.copy()
    cv2.drawContours(overlay, contours, -1, (0,255,0), 2, cv2.LINE_AA)
    return overlay

def draw_hed_line(base_bgr: np.ndarray, prob_full: np.ndarray, thresh: float = 0.5) -> np.ndarray:
    line_mask = postprocess_prob_map(prob_full, thresh=thresh)
    coords = np.column_stack(np.nonzero(line_mask))
    vis = base_bgr.copy()
    if coords.size == 0:
        return vis
    xs = coords[:,1]; ys = coords[:,0]
    try:
        deg = min(3, len(xs)-1)
        coeffs = np.polyfit(xs, ys, deg=deg)
        xs_sorted = np.linspace(xs.min(), xs.max(), num=200)
        ys_pred = np.polyval(coeffs, xs_sorted)
        pts = np.stack([xs_sorted, ys_pred], axis=1).astype(np.int32)
        for i in range(len(pts)-1):
            cv2.line(vis, (pts[i,0], pts[i,1]), (pts[i+1,0], pts[i+1,1]), (0,255,0), 3, cv2.LINE_AA)
    except Exception:
        for y,x in coords:
            cv2.circle(vis, (int(x), int(y)), 1, (0,255,0), -1, cv2.LINE_AA)
    return vis


def postprocess_prob_map(prob: np.ndarray, thresh: float = 0.5) -> np.ndarray:
    binary = (prob >= thresh).astype(np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    try:
        from skimage import morphology
        skeleton = morphology.thin(binary > 0).astype(np.uint8)
    except Exception:
        skeleton = binary
    return skeleton


def clamp_point(pt, w, h):
    """Ensure a point stays inside image bounds."""
    x, y = int(pt[0]), int(pt[1])
    x = max(0, min(w - 1, x))
    y = max(0, min(h - 1, y))
    return (x, y)


# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

def run_pipeline(img_path_or_np, return_debug_image=True, reverse_order=True):
    # load image
    if isinstance(img_path_or_np, str):
        if not os.path.exists(img_path_or_np):
            raise FileNotFoundError(img_path_or_np)
        img_bgr = cv2.imread(img_path_or_np, cv2.IMREAD_COLOR)
    else:
        img_bgr = img_path_or_np.copy()
    if img_bgr is None:
        raise ValueError('Invalid image input')

    coords, hm = infer_hrnet(img_bgr)
    peak_y, hed_prob = infer_hed_line(img_bgr)
    cobb, l2_line, s1_line, uv = compute_cobb_angle(coords, reverse_order=reverse_order)
    curvature_deg = compute_spine_curvature_sum(coords, reverse_order=reverse_order)
    mids = spine_midpoints(coords, reverse_order)
    curvature_per_seg = curvature_deg / max(1, len(mids) - 2) if len(mids) >= 3 else 0.0

    # 构建按椎体分组的结构化坐标
    vertebrae = {}
    if reverse_order:
        # S1: 前2个点
        if len(coords) >= 2:
            vertebrae['S1'] = {'points': coords[0:2], 'type': 'line'}
        # L5->L1: 每个椎体4个点
        for k, name in enumerate(['L5', 'L4', 'L3', 'L2', 'L1']):
            quad = coords[2 + 4*k : 2 + 4*(k+1)]
            if len(quad) == 4:
                vertebrae[name] = {'points': reorder_quad(quad), 'type': 'quad'}
    else:
        # L1->L5: 每个椎体4个点
        for k, name in enumerate(['L1', 'L2', 'L3', 'L4', 'L5']):
            quad = coords[4*k : 4*k+4]
            if len(quad) == 4:
                vertebrae[name] = {'points': reorder_quad(quad), 'type': 'quad'}
        # S1: 最后2个点
        if len(coords) >= 22:
            vertebrae['S1'] = {'points': coords[-2:], 'type': 'line'}

    result = {
        'coords': coords,  # 原始22个点坐标列表
        'vertebrae': vertebrae,  # 按椎体分组的结构化坐标
        'spine_midpoints': mids,  # 脊柱中线点序列
        'peak_y': peak_y,  # HED检测的髂嵴线y坐标
        'cobb_deg': cobb,  # Cobb角度
        'cobb_l2_line': l2_line,  # L2终板线 (pt1, pt2)
        'cobb_s1_line': s1_line,  # S1终板线 (pt1, pt2)
        'cobb_unit_vectors': uv,  # L2和S1的单位向量 (u_hat, v_hat)
        'curvature_deg': curvature_deg,  # 脊柱总曲率角度
        'curvature_per_seg': curvature_per_seg,  # 平均每段曲率
    }
    if return_debug_image:
        vis, score = draw_keypoints(img_bgr, coords, reverse_order=reverse_order, hed_y=peak_y)
        # draw hed horizontal line
        cv2.line(vis, (0, peak_y), (vis.shape[1]-1, peak_y), (0, 0, 255), 3, cv2.LINE_AA)
        # overlay hed heatmap lightly
        hed_overlay = overlay_heatmap(vis, hed_prob, alpha=0.25)
        hed_overlay = draw_hed_line(hed_overlay, hed_prob, thresh=0.5)
        # score text — dynamic font scale based on image size
        _sf = max(hed_overlay.shape[:2]) / 1000.0
        _fs = max(0.5, _sf)
        _th = max(1, int(round(_sf * 2)))
        _lh = int(40 * _sf)
        cv2.putText(hed_overlay, f'Score {score:+d}', (int(20*_sf), _lh), cv2.FONT_HERSHEY_SIMPLEX, 1.1*_fs, (0, 255, 255), _th, cv2.LINE_AA)
        cv2.putText(hed_overlay, f'Cobb L2-S1: {cobb:.1f} deg', (int(20*_sf), _lh*2), cv2.FONT_HERSHEY_SIMPLEX, 1.0*_fs, (0, 255, 0), _th, cv2.LINE_AA)
        cv2.putText(hed_overlay, f'Curvature: {curvature_deg:.1f} deg', (int(20*_sf), _lh*3), cv2.FONT_HERSHEY_SIMPLEX, 1.0*_fs, (0, 200, 255), _th, cv2.LINE_AA)


        # Cobb 杈呭姪绾夸笌瑙掑害绀烘剰锛堣鍓埌鍥惧唴锛?
        if l2_line and s1_line:
            H, W = hed_overlay.shape[:2]
            p1, p2 = np.array(l2_line[0], dtype=np.float32), np.array(l2_line[1], dtype=np.float32)
            q1, q2 = np.array(s1_line[0], dtype=np.float32), np.array(s1_line[1], dtype=np.float32)

            cv2.line(hed_overlay, clamp_point(p1, W, H), clamp_point(p2, W, H), (0, 255, 255), 2, cv2.LINE_AA)
            cv2.line(hed_overlay, clamp_point(q1, W, H), clamp_point(q2, W, H), (255, 0, 255), 2, cv2.LINE_AA)
            for pt, color in [(p1, (0,255,255)), (p2, (0,255,255)), (q1, (255,0,255)), (q2, (255,0,255))]:
                cv2.circle(hed_overlay, clamp_point(pt, W, H), 4, color, -1)

            # 在右下角固定角度示意，使用两终板向量（均指向左侧），取内角
            u_vec = p2 - p1
            v_vec = q2 - q1
            un = np.linalg.norm(u_vec)
            vn = np.linalg.norm(v_vec)
            if un > 1e-6 and vn > 1e-6:
                u_hat = u_vec / un
                v_hat = v_vec / vn
                # 让两个向量朝左（x为负）
                if u_hat[0] > 0:
                    u_hat = -u_hat
                if v_hat[0] > 0:
                    v_hat = -v_hat
                # 内角
                cosang = float(np.clip(np.dot(u_hat, v_hat), -1.0, 1.0))
                inner_diff = np.arccos(cosang)
                # 绘制示意
                anchor = np.array([W - 120, H - 80], dtype=np.float32)
                length = 70
                for vec, color in [(u_hat, (0,255,255)), (v_hat, (255,0,255))]:
                    end_pt = anchor + vec * length
                    cv2.arrowedLine(hed_overlay, tuple(anchor.astype(int)), tuple(clamp_point(end_pt, W, H)), color, 2, cv2.LINE_AA, tipLength=0.08)
                # 弧线
                ang_u = np.arctan2(u_hat[1], u_hat[0])
                ang_v = np.arctan2(v_hat[1], v_hat[0])
                # 最小夹角方向
                diff = (ang_v - ang_u + np.pi) % (2*np.pi) - np.pi
                steps = np.linspace(0, diff, num=60)
                radius = int(45 * _sf)
                arc_pts = []
                for d in steps:
                    ang = ang_u + d
                    arc_pts.append(anchor + radius * np.array([np.cos(ang), np.sin(ang)], dtype=np.float32))
                arc_pts = np.array([clamp_point(pt, W, H) for pt in arc_pts], dtype=np.int32)
                if len(arc_pts) > 1:
                    cv2.polylines(hed_overlay, [arc_pts], False, (0,200,255), _th, cv2.LINE_AA)
                text_pos = tuple((anchor + np.array([int(-20*_sf), int(-10*_sf)])).astype(int))
                cv2.putText(hed_overlay, f"{cobb:.1f}deg", text_pos, cv2.FONT_HERSHEY_SIMPLEX, 0.9*_fs, (0,255,0), _th, cv2.LINE_AA)
        result['debug_image'] = hed_overlay
        result['score'] = score
    return result

def run_opll_pipeline(img_path_or_np, return_debug_image=True):
    if isinstance(img_path_or_np, str):
        if not os.path.exists(img_path_or_np):
            raise FileNotFoundError(img_path_or_np)
        img_bgr = cv2.imread(img_path_or_np, cv2.IMREAD_COLOR)
    else:
        img_bgr = img_path_or_np.copy()
    if img_bgr is None:
        raise ValueError('Invalid image input')
    
    pred_mask = infer_opll(img_bgr)
    result = {'pred_mask': pred_mask}
    
    if return_debug_image:
        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape
        top = int(h * 0.05)
        bottom = int(h * 0.95)
        left = int(w * 0.12)
        right = int(w * 0.9)
        ct_region = gray[top:bottom, left:right]
        cols = np.where(ct_region.max(axis=0) > 10)[0]
        if len(cols) > 0:
            ct_region = ct_region[:, cols[0]:cols[-1]+1]
        ct_region = cv2.resize(ct_region, (600, 600))
        
        gray_bgr = cv2.cvtColor(ct_region, cv2.COLOR_GRAY2BGR)
        pred_img = gray_bgr.copy()
        pred_img[:, :, 1] = np.maximum(pred_img[:, :, 1], pred_mask)
        result['debug_image'] = pred_img
    
    return result

if __name__ == "__main__":
    import random
    test_dir = ROOT / "testimgs"
    if test_dir.exists():
        imgs = list(test_dir.glob("*.png")) + list(test_dir.glob("*.jpg"))
        if imgs:
            img = random.choice(imgs)
            print("Run on", img)
            res = run_pipeline(str(img), True)
            print("Done, peak_y:", res["peak_y"])
            cv2.imwrite("debug_v3.png", res["debug_image"])
        else:
            print("No test images found.")
    else:
        print("testimgs dir missing.")

