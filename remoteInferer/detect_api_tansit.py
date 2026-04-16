"""
颈椎侧位 X 光关键点检测 (Tansit) Pipeline
15 关键点: C3-C7 × [Ant, Post, Lamina]
输出: keypoints (list of [x, y]), ratios (Torg-Pavlov Ratio per vertebra)
"""

import os
import math
import numpy as np
import cv2
from PIL import Image

import torch
import torch.nn as nn
import torch.nn.functional as F

ROOT = os.path.dirname(os.path.abspath(__file__))
TANSIT_WEIGHTS = os.path.join(ROOT, "weights", "tansit.pth")

IMAGE_SIZE = 512
HEATMAP_SIZE = 256
NUM_KEYPOINTS = 15

KEYPOINT_NAMES = [
    "C3_Ant", "C3_Post", "C3_Lamina",
    "C4_Ant", "C4_Post", "C4_Lamina",
    "C5_Ant", "C5_Post", "C5_Lamina",
    "C6_Ant", "C6_Post", "C6_Lamina",
    "C7_Ant", "C7_Post", "C7_Lamina",
]

MEAN = [0.485, 0.456, 0.406]
STD  = [0.229, 0.224, 0.225]


def tensor_to_numpy(tensor: torch.Tensor) -> np.ndarray:
    return np.asarray(tensor.detach().cpu().tolist())

# ================================================================
# HRNet 模型（与 tansit/predict.py 完全一致）
# ================================================================

class ConvBnRelu(nn.Module):
    def __init__(self, in_ch, out_ch, kernel_size=3, stride=1, padding=1):
        super().__init__()
        self.conv = nn.Conv2d(in_ch, out_ch, kernel_size, stride, padding, bias=False)
        self.bn   = nn.BatchNorm2d(out_ch)
        self.relu = nn.ReLU(inplace=True)

    def forward(self, x):
        return self.relu(self.bn(self.conv(x)))


class BasicBlock(nn.Module):
    expansion = 1

    def __init__(self, in_ch, out_ch, stride=1, downsample=None):
        super().__init__()
        self.conv1      = nn.Conv2d(in_ch, out_ch, 3, stride, 1, bias=False)
        self.bn1        = nn.BatchNorm2d(out_ch)
        self.relu       = nn.ReLU(inplace=True)
        self.conv2      = nn.Conv2d(out_ch, out_ch, 3, 1, 1, bias=False)
        self.bn2        = nn.BatchNorm2d(out_ch)
        self.downsample = downsample

    def forward(self, x):
        identity = x
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        if self.downsample is not None:
            identity = self.downsample(x)
        return self.relu(out + identity)


class Bottleneck(nn.Module):
    expansion = 4

    def __init__(self, in_ch, mid_ch, stride=1, downsample=None):
        super().__init__()
        self.conv1      = nn.Conv2d(in_ch, mid_ch, 1, bias=False)
        self.bn1        = nn.BatchNorm2d(mid_ch)
        self.conv2      = nn.Conv2d(mid_ch, mid_ch, 3, stride, 1, bias=False)
        self.bn2        = nn.BatchNorm2d(mid_ch)
        self.conv3      = nn.Conv2d(mid_ch, mid_ch * self.expansion, 1, bias=False)
        self.bn3        = nn.BatchNorm2d(mid_ch * self.expansion)
        self.relu       = nn.ReLU(inplace=True)
        self.downsample = downsample

    def forward(self, x):
        identity = x
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.relu(self.bn2(self.conv2(out)))
        out = self.bn3(self.conv3(out))
        if self.downsample is not None:
            identity = self.downsample(x)
        return self.relu(out + identity)


def _make_layer(block, in_ch, out_ch, num_blocks, stride=1):
    downsample = None
    if stride != 1 or in_ch != out_ch * block.expansion:
        downsample = nn.Sequential(
            nn.Conv2d(in_ch, out_ch * block.expansion, 1, stride, bias=False),
            nn.BatchNorm2d(out_ch * block.expansion),
        )
    layers = []
    if block == Bottleneck:
        layers.append(block(in_ch, out_ch, stride, downsample))
        for _ in range(1, num_blocks):
            layers.append(block(out_ch * block.expansion, out_ch))
    else:
        layers.append(block(in_ch, out_ch * block.expansion, stride, downsample))
        for _ in range(1, num_blocks):
            layers.append(block(out_ch * block.expansion, out_ch * block.expansion))
    return nn.Sequential(*layers)


class HRBranch(nn.Module):
    def __init__(self, channels, num_blocks=4):
        super().__init__()
        layers = [BasicBlock(channels, channels) for _ in range(num_blocks)]
        self.blocks = nn.Sequential(*layers)

    def forward(self, x):
        return self.blocks(x)


class FuseModule(nn.Module):
    def __init__(self, channels_list):
        super().__init__()
        self.num_branches = len(channels_list)
        self.fuse_layers  = nn.ModuleList()
        for i in range(self.num_branches):
            row = nn.ModuleList()
            for j in range(self.num_branches):
                if j == i:
                    row.append(nn.Identity())
                elif j < i:
                    ops = []
                    for k in range(i - j):
                        in_c = channels_list[j] if k == 0 else channels_list[i]
                        ops.append(nn.Conv2d(in_c, channels_list[i], 3, 2, 1, bias=False))
                        ops.append(nn.BatchNorm2d(channels_list[i]))
                        if k < i - j - 1:
                            ops.append(nn.ReLU(inplace=True))
                    row.append(nn.Sequential(*ops))
                else:
                    row.append(nn.Sequential(
                        nn.Conv2d(channels_list[j], channels_list[i], 1, bias=False),
                        nn.BatchNorm2d(channels_list[i]),
                    ))
            self.fuse_layers.append(row)
        self.relu = nn.ReLU(inplace=True)

    def forward(self, x_list):
        out = []
        for i in range(self.num_branches):
            y = None
            for j in range(self.num_branches):
                t = self.fuse_layers[i][j](x_list[j])
                if j > i:
                    t = F.interpolate(t, size=x_list[i].shape[2:],
                                      mode="bilinear", align_corners=True)
                y = t if y is None else y + t
            out.append(self.relu(y))
        return out


class TransitionModule(nn.Module):
    def __init__(self, prev_channels_list, next_channels_list):
        super().__init__()
        self.transitions = nn.ModuleList()
        for i, out_c in enumerate(next_channels_list):
            if i < len(prev_channels_list):
                in_c = prev_channels_list[i]
                if in_c != out_c:
                    self.transitions.append(nn.Sequential(
                        nn.Conv2d(in_c, out_c, 3, 1, 1, bias=False),
                        nn.BatchNorm2d(out_c),
                        nn.ReLU(inplace=True),
                    ))
                else:
                    self.transitions.append(nn.Identity())
            else:
                in_c = prev_channels_list[-1]
                self.transitions.append(nn.Sequential(
                    nn.Conv2d(in_c, out_c, 3, 2, 1, bias=False),
                    nn.BatchNorm2d(out_c),
                    nn.ReLU(inplace=True),
                ))

    def forward(self, x_list):
        out = []
        for i, trans in enumerate(self.transitions):
            out.append(trans(x_list[i] if i < len(x_list) else x_list[-1]))
        return out


class HRStage(nn.Module):
    def __init__(self, channels_list, num_blocks=4, num_modules=1):
        super().__init__()
        self.modules_list = nn.ModuleList()
        for _ in range(num_modules):
            branches = nn.ModuleList([HRBranch(ch, num_blocks) for ch in channels_list])
            fuse     = FuseModule(channels_list)
            self.modules_list.append(nn.ModuleDict({"branches": branches, "fuse": fuse}))

    def forward(self, x_list):
        for module in self.modules_list:
            branches_out = [branch(x_list[i]) for i, branch in enumerate(module["branches"])]
            x_list = module["fuse"](branches_out)
        return x_list


class HRNet(nn.Module):
    def __init__(self, num_keypoints=NUM_KEYPOINTS):
        super().__init__()
        self.num_keypoints = num_keypoints

        self.stem = nn.Sequential(
            nn.Conv2d(3, 64, 3, 2, 1, bias=False), nn.BatchNorm2d(64), nn.ReLU(inplace=True),
            nn.Conv2d(64, 64, 3, 2, 1, bias=False), nn.BatchNorm2d(64), nn.ReLU(inplace=True),
        )
        self.stage1     = _make_layer(Bottleneck, 64, 64, num_blocks=4)
        self.transition1 = TransitionModule([256], [32, 64])
        self.stage2     = HRStage([32, 64], num_blocks=4, num_modules=1)
        self.transition2 = TransitionModule([32, 64], [32, 64, 128])
        self.stage3     = HRStage([32, 64, 128], num_blocks=4, num_modules=4)
        self.transition3 = TransitionModule([32, 64, 128], [32, 64, 128, 256])
        self.stage4     = HRStage([32, 64, 128, 256], num_blocks=4, num_modules=3)

        total_ch = 32 + 64 + 128 + 256  # 480
        self.head = nn.Sequential(
            nn.Conv2d(total_ch, 256, 3, 1, 1, bias=False), nn.BatchNorm2d(256), nn.ReLU(inplace=True),
            nn.Conv2d(256, 256, 3, 1, 1, bias=False), nn.BatchNorm2d(256), nn.ReLU(inplace=True),
            nn.ConvTranspose2d(256, 256, 4, 2, 1, bias=False), nn.BatchNorm2d(256), nn.ReLU(inplace=True),
            nn.Conv2d(256, num_keypoints, 1),
        )

    def forward(self, x):
        x = self.stem(x)
        x = self.stage1(x)
        x_list = self.transition1([x])
        x_list = self.stage2(x_list)
        x_list = self.transition2(x_list)
        x_list = self.stage3(x_list)
        x_list = self.transition3(x_list)
        x_list = self.stage4(x_list)

        target_size = x_list[0].shape[2:]
        upsampled = [x_list[0]] + [
            F.interpolate(feat, size=target_size, mode="bilinear", align_corners=True)
            for feat in x_list[1:]
        ]
        heatmaps = self.head(torch.cat(upsampled, dim=1))
        return heatmaps


# ================================================================
# 推理工具函数
# ================================================================

def _decode_heatmaps(heatmaps: np.ndarray, orig_w: int, orig_h: int):
    """DARK Pose 亚像素解码，返回 list of [x, y]。"""
    num_kp, hm_h, hm_w = heatmaps.shape
    keypoints = []
    for i in range(num_kp):
        hm  = heatmaps[i].copy()
        idx = np.argmax(hm)
        cy, cx = divmod(idx, hm_w)
        dx, dy = 0.0, 0.0
        if 1 <= cx < hm_w - 1 and 1 <= cy < hm_h - 1 and hm[cy, cx] > 0:
            hm_log = np.log(np.maximum(hm, 1e-10))
            gx  = (hm_log[cy, cx + 1] - hm_log[cy, cx - 1]) * 0.5
            gy  = (hm_log[cy + 1, cx] - hm_log[cy - 1, cx]) * 0.5
            Hxx = hm_log[cy, cx + 1] + hm_log[cy, cx - 1] - 2 * hm_log[cy, cx]
            Hyy = hm_log[cy + 1, cx] + hm_log[cy - 1, cx] - 2 * hm_log[cy, cx]
            Hxy = (hm_log[cy + 1, cx + 1] - hm_log[cy + 1, cx - 1]
                   - hm_log[cy - 1, cx + 1] + hm_log[cy - 1, cx - 1]) * 0.25
            det = Hxx * Hyy - Hxy * Hxy
            if abs(det) > 1e-6:
                dx = float(np.clip(-(Hyy * gx - Hxy * gy) / det, -0.5, 0.5))
                dy = float(np.clip(-(Hxx * gy - Hxy * gx) / det, -0.5, 0.5))
        keypoints.append([
            float((cx + dx) / hm_w * orig_w),
            float((cy + dy) / hm_h * orig_h),
        ])
    return keypoints


def _enforce_anatomical_order(keypoints):
    """强制垂直（C3→C7）和水平（Ant→Post→Lamina）的解剖学顺序。"""
    kps = [list(pt) for pt in keypoints]
    # 垂直排序
    for pt_type in range(3):
        indices = [i * 3 + pt_type for i in range(5)]
        ys = sorted([(kps[idx][1], idx) for idx in indices], key=lambda t: t[0])
        sorted_pts = [kps[ys[j][1]].copy() for j in range(5)]
        for j, idx in enumerate(indices):
            kps[idx] = sorted_pts[j]
    # 水平排序
    for v in range(5):
        pts = sorted([kps[v * 3 + k] for k in range(3)], key=lambda p: p[0])
        for k in range(3):
            kps[v * 3 + k] = pts[k]
    return kps


def _compute_ratios(keypoints):
    """计算 Torg-Pavlov Ratio，返回 dict {vertebra: {A, B, ratio}}。"""
    results = {}
    for vi, v in enumerate(["C3", "C4", "C5", "C6", "C7"]):
        base = vi * 3
        ant, post, lamina = keypoints[base], keypoints[base + 1], keypoints[base + 2]
        a = math.hypot(ant[0] - post[0], ant[1] - post[1])
        b = math.hypot(post[0] - lamina[0], post[1] - lamina[1])
        results[v] = {"A": round(a, 2), "B": round(b, 2), "ratio": round(b / a, 4) if a > 1e-6 else 0.0}
    return results


# ================================================================
# 懒加载模型（进程内单例）
# ================================================================
_tansit_model  = None
_tansit_device = None


def _load_model():
    global _tansit_model, _tansit_device
    if _tansit_model is not None:
        return _tansit_model, _tansit_device

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model  = HRNet(num_keypoints=NUM_KEYPOINTS).to(device)

    if not os.path.isfile(TANSIT_WEIGHTS):
        raise FileNotFoundError(f"Tansit weights not found: {TANSIT_WEIGHTS}")

    state = torch.load(TANSIT_WEIGHTS, map_location=device, weights_only=True)
    model.load_state_dict(state)
    model.eval()

    _tansit_model  = model
    _tansit_device = device
    print(f"[Tansit] Model loaded on {device}: {TANSIT_WEIGHTS}")
    return _tansit_model, _tansit_device


# ================================================================
# 公开接口
# ================================================================

def run_tansit_pipeline(img_bgr: np.ndarray):
    """
    输入: BGR numpy 图像
    输出: {
        'keypoints': list of 15 × [x, y]  (C3-C7, 每节 Ant/Post/Lamina),
        'ratios':    dict {C3..C7: {A, B, ratio}}
    }
    """
    model, device = _load_model()

    # BGR → RGB → PIL
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    img_pil = Image.fromarray(img_rgb)
    orig_w, orig_h = img_pil.size

    # CLAHE 对比度增强
    img_lab = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2LAB)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    img_lab[:, :, 0] = clahe.apply(img_lab[:, :, 0])
    img_pil = Image.fromarray(cv2.cvtColor(img_lab, cv2.COLOR_LAB2RGB))

    # 多尺度 TTA: 3 尺度 × 2 (原图 + 水平翻转) = 6 次
    scales = [0.8, 1.0, 1.2]
    accumulated = None
    count = 0

    for scale in scales:
        sz = int(IMAGE_SIZE * scale)
        for flip in (False, True):
            img_s = img_pil.resize((sz, sz), Image.BILINEAR)
            if flip:
                img_s = img_s.transpose(Image.FLIP_LEFT_RIGHT)

            arr = np.array(img_s, dtype=np.float32) / 255.0
            for c in range(3):
                arr[:, :, c] = (arr[:, :, c] - MEAN[c]) / STD[c]

            tensor = torch.from_numpy(arr.transpose(2, 0, 1)).unsqueeze(0).to(device)
            with torch.no_grad():
                hm = model(tensor)
            hm = F.interpolate(hm, size=(HEATMAP_SIZE, HEATMAP_SIZE),
                               mode="bilinear", align_corners=True)
            hm_np = tensor_to_numpy(hm.squeeze(0))

            if flip:
                hm_np = hm_np[:, :, ::-1].copy()
                for vi in range(5):
                    ant_ch, lam_ch = vi * 3, vi * 3 + 2
                    hm_np[[ant_ch, lam_ch]] = hm_np[[lam_ch, ant_ch]]

            accumulated = hm_np if accumulated is None else accumulated + hm_np
            count += 1

    heatmaps_avg = accumulated / count
    keypoints = _decode_heatmaps(heatmaps_avg, orig_w, orig_h)
    keypoints = _enforce_anatomical_order(keypoints)
    ratios    = _compute_ratios(keypoints)

    return {"keypoints": keypoints, "ratios": ratios}
