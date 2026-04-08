
import os
import sys
import numpy as np
import cv2
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image

# -----------------------------------------------------------------------------
# Configuration & Constants (Moved from dataset_la.py)
# -----------------------------------------------------------------------------
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
# You can change this path to absolute path if needed, currently assumes specific relative location
# Points to f:\Code\AI\SMIS2\xRayProj\干扰训练kp_enhance_ver最新力作.pth
CKPT_PATH = "/www/wwwroot/Spine/model1.pth"


def tensor_to_numpy(tensor: torch.Tensor) -> np.ndarray:
    return np.asarray(tensor.detach().cpu().tolist())

CONF_THR = 0.3
TARGET_SIZE = (512, 512)

LEVELS = ["L1","L2","L3","L4","L5","S1"]
LEVEL_POINTS = {lvl: ["a_1","a_2","b_1","b_2"] for lvl in LEVELS}
LEVEL_POINTS["S1"] = ["a_1","a_2"]  # S1 only 2 points

# OpenCv colors are BGR
COLORS_BGR = {
    'red': (0, 0, 255),
    'orange': (0, 165, 255),
    'yellow': (0, 255, 255),
    'green': (0, 255, 0),
    'lime': (0, 255, 0),
    'cyan': (255, 255, 0),
    'magenta': (255, 0, 255),
    'blue': (255, 0, 0)
}
LEVEL_COLORS = [COLORS_BGR['red'], COLORS_BGR['orange'], COLORS_BGR['yellow'], 
                COLORS_BGR['green'], COLORS_BGR['cyan'], COLORS_BGR['magenta']]

# -----------------------------------------------------------------------------
# Model Definition (Copied from model.py to be standalone)
# -----------------------------------------------------------------------------
class ConvBlock(nn.Module):
    """Two-layer conv + BN + ReLU block."""
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.conv(x)


class Down(nn.Module):
    """Downsample by 2 then conv block."""
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.pool = nn.MaxPool2d(2)
        self.conv = ConvBlock(in_ch, out_ch)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.conv(self.pool(x))


class Up(nn.Module):
    """
    UNet upsampling with skip concat.
    If bilinear=True: upsample then ConvBlock(in_ch -> out_ch).
    in_ch should equal (skip_ch + up_ch) after concat.
    """
    def __init__(self, in_ch: int, out_ch: int, bilinear: bool = True):
        super().__init__()
        if bilinear:
            self.up = nn.Upsample(scale_factor=2, mode="bilinear", align_corners=False)
            self.conv = ConvBlock(in_ch, out_ch)
        else:
            self.up = nn.ConvTranspose2d(in_ch // 2, in_ch // 2, kernel_size=2, stride=2)
            self.conv = ConvBlock(in_ch, out_ch)

    def forward(self, x1: torch.Tensor, x2: torch.Tensor) -> torch.Tensor:
        x1 = self.up(x1)
        diff_y = x2.size(2) - x1.size(2)
        diff_x = x2.size(3) - x1.size(3)
        if diff_y != 0 or diff_x != 0:
            x1 = F.pad(x1, [diff_x // 2, diff_x - diff_x // 2, diff_y // 2, diff_y - diff_y // 2])
        x = torch.cat([x2, x1], dim=1)
        return self.conv(x)

class UNetKeypoint(nn.Module):
    """
    UNet backbone + heatmap head for keypoints.
    """
    def __init__(
        self,
        in_channels: int = 3,
        num_joints: int = 22,
        num_centers: int = 0,
        num_offsets: int = 0,
        base_channels: int = 32,
        bilinear: bool = True,
    ):
        super().__init__()
        self.num_centers = num_centers
        self.num_offsets = num_offsets

        self.in_conv = ConvBlock(in_channels, base_channels)
        self.down1 = Down(base_channels, base_channels * 2)
        self.down2 = Down(base_channels * 2, base_channels * 4)
        self.down3 = Down(base_channels * 4, base_channels * 8)
        self.down4 = Down(base_channels * 8, base_channels * 8)

        self.up1 = Up(base_channels * 16, base_channels * 4, bilinear)
        self.up2 = Up(base_channels * 8, base_channels * 2, bilinear)
        self.up3 = Up(base_channels * 4, base_channels, bilinear)
        self.up4 = Up(base_channels * 2, base_channels, bilinear)

        self.out_conv = nn.Conv2d(base_channels, num_joints, kernel_size=1)
        self.center_head = nn.Conv2d(base_channels, num_centers, kernel_size=1) if num_centers > 0 else None
        self.offset_head = nn.Conv2d(base_channels, num_offsets * 2, kernel_size=1) if num_offsets > 0 else None

    def forward(self, x: torch.Tensor):
        x1 = self.in_conv(x)
        x2 = self.down1(x1)
        x3 = self.down2(x2)
        x4 = self.down3(x3)
        x5 = self.down4(x4)

        x = self.up1(x5, x4)
        x = self.up2(x, x3)
        x = self.up3(x, x2)
        x = self.up4(x, x1)

        kp = self.out_conv(x)
        centers = self.center_head(x) if self.center_head is not None else None

        offsets = None
        if self.offset_head is not None:
            off_map = self.offset_head(x)  # [B, num_offsets*2, H, W]
            off_vec = off_map.mean(dim=[2, 3])
            offsets = torch.sigmoid(off_vec.view(off_vec.size(0), self.num_offsets, 2))

        if centers is not None or offsets is not None:
            return kp, centers, offsets
        return kp

def create_kp_model(
    in_channels: int = 3,
    num_joints: int = 22,
    num_centers: int = 0,
    num_offsets: int = 0,
    base_channels: int = 32,
    bilinear: bool = True,
) -> UNetKeypoint:
    return UNetKeypoint(
        in_channels=in_channels,
        num_joints=num_joints,
        num_centers=num_centers,
        num_offsets=num_offsets,
        base_channels=base_channels,
        bilinear=bilinear,
    )

# -----------------------------------------------------------------------------
# Inference Logic
# -----------------------------------------------------------------------------
_MODEL = None

def load_model():
    """Singleton model loader"""
    global _MODEL
    if _MODEL is None:
        print(f"Loading model on {DEVICE}...")
        model = create_kp_model(num_joints=22, num_centers=0, 
                                num_offsets=5, base_channels=32, bilinear=True).to(DEVICE)
        
        if os.path.exists(CKPT_PATH):
            ckpt = torch.load(CKPT_PATH, map_location=DEVICE)
            if "model_state" in ckpt:
                model.load_state_dict(ckpt["model_state"])
            else:
                model.load_state_dict(ckpt)
            model.eval()
            print(f"Model loaded from {CKPT_PATH}")
        else:
            raise FileNotFoundError(f"Checkpoint not found at {CKPT_PATH}")
        _MODEL = model
    return _MODEL

def apply_clahe_enhancement(img, clip_limit=2.0, tile_grid_size=(8, 8)):
    """
    Apply CLAHE to each channel of the image.
    Matches the augmentation style used in training (per-channel).
    """
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_grid_size)
    if img.ndim == 3:
        # Apply to each channel
        channels = [clahe.apply(img[..., c]) for c in range(img.shape[2])]
        return np.stack(channels, axis=2)
    else:
        return clahe.apply(img)

def load_image_raw(path: str, enhance=False):
    # Returns RGB array (uint8) and Tensor (float 0-1)
    img = Image.open(path).convert('RGB')
    arr = np.array(img) # H, W, 3 (RGB), uint8
    
    if enhance:
        arr = apply_clahe_enhancement(arr)
        
    t = torch.from_numpy(arr.astype(np.float32) / 255.0).float().permute(2, 0, 1).unsqueeze(0)
    return arr, t

def sort_points_clockwise(pts):
    if len(pts) < 3:
        return pts
    c = pts.mean(axis=0)
    ang = np.arctan2(pts[:,1]-c[1], pts[:,0]-c[0])
    return pts[np.argsort(ang)]

def extract_peaks_from_sum_heatmap(hm_sig, H_img, W_img, thr=0.1):
    hm_all = hm_sig.max(dim=1, keepdim=True)[0]
    
    k = 5
    pad = k // 2
    hmax = F.max_pool2d(hm_all, (k, k), stride=1, padding=pad)
    keep = (hmax == hm_all) & (hm_all > thr)
    
    y_idxs, x_idxs = torch.where(keep[0,0])
    scores = hm_all[0, 0, y_idxs, x_idxs]
    
    y_np = tensor_to_numpy(y_idxs).astype(float)
    x_np = tensor_to_numpy(x_idxs).astype(float)
    s_np = tensor_to_numpy(scores).astype(float)
    
    H_hm, W_hm = hm_sig.shape[-2:]
    sy = H_img / H_hm
    sx = W_img / W_hm
    
    raw_peaks = []
    border = 15
    
    x_coords = []
    for i in range(len(s_np)):
        px = x_np[i] * sx
        py = y_np[i] * sy
        if px < border or px > W_img - border or py < border or py > H_img - border:
            continue
        raw_peaks.append({'x': px, 'y': py, 'conf': s_np[i]})
        x_coords.append(px)
        
    if x_coords:
        x_median = np.median(x_coords)
        valid_peaks = []
        x_thr = W_img * 0.35
        for p in raw_peaks:
            if abs(p['x'] - x_median) < x_thr:
                valid_peaks.append(p)
        return valid_peaks
    else:
        return raw_peaks

def reconstruct_spine_structure(peaks, H_img, W_img):
    if not peaks:
        return np.zeros(22), np.zeros(22), np.zeros(22)

    peaks.sort(key=lambda p: p['y'])
    
    # 1. Clustering layers
    layers = []
    if len(peaks) > 0:
        current_layer = [peaks[0]]
        ref_y = peaks[0]['y']
        layer_thr = H_img * 0.045
        
        for i in range(1, len(peaks)):
            p = peaks[i]
            if abs(p['y'] - ref_y) < layer_thr:
                current_layer.append(p)
            else:
                layers.append(current_layer)
                current_layer = [p]
                ref_y = p['y']
        if current_layer:
            layers.append(current_layer)
    
    # 2. Side determination (Fitting)
    left_candidates_x = []
    left_candidates_y = []
    right_candidates_x = []
    right_candidates_y = []
    
    for layer in layers:
        layer.sort(key=lambda p: p['x'])
        if len(layer) >= 2:
            max_gap = 0
            cut_idx = 1
            for k in range(len(layer)-1):
                gap = layer[k+1]['x'] - layer[k]['x']
                if gap > max_gap:
                    max_gap = gap
                    cut_idx = k + 1
            
            if max_gap > W_img * 0.02: 
                for p in layer[:cut_idx]:
                    left_candidates_x.append(p['x'])
                    left_candidates_y.append(p['y'])
                for p in layer[cut_idx:]:
                    right_candidates_x.append(p['x'])
                    right_candidates_y.append(p['y'])
    
    poly_left = None
    poly_right = None
    
    if len(left_candidates_x) > 2:
        try:
            z = np.polyfit(left_candidates_y, left_candidates_x, 2)
            poly_left = np.poly1d(z)
        except: pass
    elif len(left_candidates_x) > 1:
        z = np.polyfit(left_candidates_y, left_candidates_x, 1)
        poly_left = np.poly1d(z)
        
    if len(right_candidates_x) > 2:
        try:
            z = np.polyfit(right_candidates_y, right_candidates_x, 2)
            poly_right = np.poly1d(z)
        except: pass
    elif len(right_candidates_x) > 1:
        z = np.polyfit(right_candidates_y, right_candidates_x, 1)
        poly_right = np.poly1d(z)

    global_fallback = False
    if not (poly_left and poly_right):
        global_fallback = True
        
    for p in peaks:
        if 'side' in p: del p['side']
        if not global_fallback:
            dist_l = abs(p['x'] - poly_left(p['y']))
            dist_r = abs(p['x'] - poly_right(p['y']))
            if dist_l < dist_r:
                p['side'] = 'left'
            else:
                p['side'] = 'right'
        else:
            x_mean = np.mean([pk['x'] for pk in peaks])
            if p['x'] < x_mean: p['side'] = 'left'
            else: p['side'] = 'right'

    # 3. Label Assignment
    pool_left = [p for p in peaks if p.get('side') == 'left']
    pool_right = [p for p in peaks if p.get('side') == 'right']
    
    pool_left.sort(key=lambda p: p['y'], reverse=True)
    pool_right.sort(key=lambda p: p['y'], reverse=True)
    
    level_defs = [
        {'name': 'S1', 'idxs': [20, 21], 'n': 2},
        {'name': 'L5', 'idxs': [16, 17, 18, 19], 'n': 4},
        {'name': 'L4', 'idxs': [12, 13, 14, 15], 'n': 4},
        {'name': 'L3', 'idxs': [8, 9, 10, 11], 'n': 4},
        {'name': 'L2', 'idxs': [4, 5, 6, 7], 'n': 4},
        {'name': 'L1', 'idxs': [0, 1, 2, 3], 'n': 4},
    ]

    pred_x = np.zeros(22)
    pred_y = np.zeros(22)
    pred_c = np.zeros(22)

    for info in level_defs:
        target_idxs = info['idxs']
        
        if info['name'] == 'S1':
            if pool_left:
                p = pool_left.pop(0)
                idx = target_idxs[0]
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']
            if pool_right:
                p = pool_right.pop(0)
                idx = target_idxs[1]
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']
        else:
            current_lefts = []
            while len(pool_left) > 0 and len(current_lefts) < 2:
                current_lefts.append(pool_left.pop(0))
            
            if len(current_lefts) >= 1:
                p = current_lefts[0]; idx = target_idxs[1] 
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']
            if len(current_lefts) >= 2:
                p = current_lefts[1]; idx = target_idxs[0]
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']

            current_rights = []
            while len(pool_right) > 0 and len(current_rights) < 2:
                current_rights.append(pool_right.pop(0))
                
            if len(current_rights) >= 1:
                p = current_rights[0]; idx = target_idxs[3]
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']
            if len(current_rights) >= 2:
                p = current_rights[1]; idx = target_idxs[2]
                pred_x[idx] = p['x']; pred_y[idx] = p['y']; pred_c[idx] = p['conf']

    return pred_x, pred_y, pred_c

def draw_poly_with_edge_thirds_cv2(img_bgr, pts, label, color, offset=5.0):
    if len(pts) < 3:
        return
    
    pts = sort_points_clockwise(pts)
    pts_int = pts.astype(np.int32)
    
    # Overlay for polygon
    overlay = img_bgr.copy()
    cv2.fillPoly(overlay, [pts_int], color)
    cv2.addWeighted(overlay, 0.25, img_bgr, 0.75, 0, img_bgr)
    
    # Edges
    cv2.polylines(img_bgr, [pts_int], True, color, 1, cv2.LINE_AA)
    
    # Right edge thirds 
    right_two_idx = np.argsort(pts[:,0])[-2:]
    if len(right_two_idx) < 2:
        return
        
    p1 = pts[right_two_idx[0]]
    p2 = pts[right_two_idx[1]]
    
    if p1[1] <= p2[1]:
        p_top, p_bot = p1, p2 
    else: 
        p_top, p_bot = p2, p1
        
    v = p_bot - p_top
    n = np.array([v[1], -v[0]])
    n_norm = np.linalg.norm(n)
    n = np.array([1.0, 0.0]) if n_norm < 1e-6 else n / n_norm
    
    p_top_off = p_top + n * offset
    p_bot_off = p_bot + n * offset
    
    p1_th = p_top_off + (p_bot_off - p_top_off) / 3.0
    p2_th = p_top_off + 2.0 * (p_bot_off - p_top_off) / 3.0
    
    # Draw right line offset (using same color as polygon edge)
    pt1 = tuple(p_top_off.astype(int))
    pt2 = tuple(p_bot_off.astype(int))
    cv2.line(img_bgr, pt1, pt2, color, 1, cv2.LINE_AA)
    
    # Draw tick marks
    len_tick = 3
    for pt in [p1_th, p2_th]:
        cx, cy = pt
        cv2.line(img_bgr, (int(cx - len_tick), int(cy)), (int(cx + len_tick), int(cy)), color, 1, cv2.LINE_AA)

    # Label
    p_mid = 0.5 * (p_top_off + p_bot_off)
    label_pos = (int(p_mid[0] - offset - 25), int(p_mid[1]))
    
    (w, h), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
    cv2.rectangle(img_bgr, (label_pos[0], label_pos[1] - h - 2), (label_pos[0] + w, label_pos[1] + 2), (0,0,0), -1)
    cv2.putText(img_bgr, label, (label_pos[0], label_pos[1]), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1, cv2.LINE_AA)


def run_inference(img_path_or_np, debug=False, output_dir=None, enhance=False, conf_thr=0.3):
    model = load_model()
    
    if isinstance(img_path_or_np, str):
        img_np_full, img_t = load_image_raw(img_path_or_np, enhance=enhance)
        # img_np_full is RGB array [H, W, 3] from PIL (uint8)
        
        # Prepare BGR visual image from RGB source (img_np_full is already uint8)
        img_visual = cv2.cvtColor(img_np_full, cv2.COLOR_RGB2BGR)
        
    elif isinstance(img_path_or_np, np.ndarray):
        # Assume input numpy array is BGR (Standard OpenCV format)
        img_visual = img_path_or_np.copy()
        
        if enhance:
            img_visual = apply_clahe_enhancement(img_visual)

        # Convert BGR to RGB for model input
        img_rgb = cv2.cvtColor(img_visual, cv2.COLOR_BGR2RGB)
        img_t = torch.from_numpy(img_rgb.astype(np.float32) / 255.0).float().permute(2, 0, 1).unsqueeze(0)
    else:
        raise ValueError("Input must be a file path or numpy array (BGR)")

    H0, W0 = img_visual.shape[:2]
    img_resized = F.interpolate(img_t, size=TARGET_SIZE, mode='bilinear', align_corners=False)

    with torch.no_grad():
        img_in = img_resized.to(DEVICE)
        out = model(img_in)
        kp_logits = out[0] if isinstance(out, tuple) else out
        hm_sig = torch.sigmoid(kp_logits)

    # 1. Extract Peaks
    peaks = extract_peaks_from_sum_heatmap(hm_sig, H0, W0, thr=conf_thr)
    
    # 2. Reconstruct
    pred_x_full, pred_y_full, conf_np = reconstruct_spine_structure(peaks, H0, W0)
    valid = conf_np > 0

    # --- Debug Outputs ---
    vis_peaks = None
    vis_heatmap = None

    if debug:
        # Debug 1: Left/Right detected points (peaks)
        vis_peaks = img_visual.copy()
        # Scale for better visibility if image is large
        scale = max(1, min(H0, W0) // 512)
        
        if peaks:
            for p in peaks:
                x, y = int(p['x']), int(p['y'])
                side = p.get('side', 'unknown')
                
                # Colors BGR
                if side == 'left': 
                    # Lime (0, 255, 0)
                    color = (0, 255, 0) 
                    label = 'L'
                elif side == 'right': 
                    # Blue (255, 0, 0)
                    color = (255, 0, 0) 
                    label = 'R'
                else: 
                    # Yellow (0, 255, 255)
                    color = (0, 255, 255) 
                    label = '?'
                
                cv2.circle(vis_peaks, (x, y), 4 * scale, color, -1)
                # cv2.putText(vis_peaks, label, (x+5, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5*scale, color, scale, cv2.LINE_AA)
        
        _sf = max(H0, W0) / 1000.0
        _fs = max(0.5, _sf)
        _th = max(1, int(round(_sf * 2)))
        _lh = int(40 * _sf)
        cv2.putText(vis_peaks, "1. Peaks (L/R)", (int(20*_sf), _lh), cv2.FONT_HERSHEY_SIMPLEX, _fs, (0, 0, 255), _th)

        # Debug 2: Predicted Heatmap
        # Aggregate heatmaps
        hm_all = hm_sig.max(dim=1, keepdim=True)[0]
        heatmap_np = tensor_to_numpy(hm_all[0, 0])
        # Normalize 0..1
        heatmap_np = (heatmap_np - heatmap_np.min()) / (heatmap_np.max() - heatmap_np.min() + 1e-8)
        heatmap_uint8 = (heatmap_np * 255).astype(np.uint8)
        heatmap_color = cv2.applyColorMap(heatmap_uint8, cv2.COLORMAP_JET)
        # Resize to original image size
        heatmap_resized = cv2.resize(heatmap_color, (W0, H0))
        # Overlay
        vis_heatmap = cv2.addWeighted(img_visual.copy(), 0.6, heatmap_resized, 0.4, 0)
        cv2.putText(vis_heatmap, "2. Heatmap", (int(20*_sf), _lh), cv2.FONT_HERSHEY_SIMPLEX, _fs, (0, 0, 255), _th)

    # Draw Polygons for L4, L5
    l4_idx = [12, 13, 14, 15]
    l5_idx = [16, 17, 18, 19]
    
    l4_pts = np.array([[pred_x_full[i], pred_y_full[i]] for i in l4_idx if valid[i]])
    l5_pts = np.array([[pred_x_full[i], pred_y_full[i]] for i in l5_idx if valid[i]])

    if len(l4_pts) >= 3:
        draw_poly_with_edge_thirds_cv2(img_visual, l4_pts, "L4", COLORS_BGR['orange'])
    if len(l5_pts) >= 3:
        draw_poly_with_edge_thirds_cv2(img_visual, l5_pts, "L5", COLORS_BGR['cyan'])

    # Draw all keypoints
    ch = 0
    for vi, lvl in enumerate(LEVELS):
        color = LEVEL_COLORS[vi % len(LEVEL_COLORS)]
        pts_list = LEVEL_POINTS[lvl]
        for _ in pts_list:
            if valid[ch]:
                cv2.drawMarker(img_visual, (int(pred_x_full[ch]), int(pred_y_full[ch])), 
                               color, cv2.MARKER_CROSS, 15, 2)
            ch += 1
    
    if debug and vis_peaks is not None and vis_heatmap is not None:
        cv2.putText(img_visual, "3. Final Result", (int(20*_sf), _lh), cv2.FONT_HERSHEY_SIMPLEX, _fs, (0, 0, 255), _th)
        # Concatenate images horizontally
        sep_width = 10
        sep = np.zeros((H0, sep_width, 3), dtype=np.uint8) + 255 # White separator
        combined = np.hstack([vis_peaks, sep, vis_heatmap, sep, img_visual])
        return combined
            
    return img_visual

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("image", help="Input image path")
    parser.add_argument("--output", help="Output image path", default="result.png")
    parser.add_argument("--debug", action="store_true", help="Generate debug images")
    parser.add_argument("--enhance", action="store_true", help="Apply CLAHE enhancement before inference")
    args = parser.parse_args()
    
    if os.path.exists(args.image):
        output_dir = os.path.dirname(os.path.abspath(args.output))
        res = run_inference(args.image, debug=args.debug, output_dir=output_dir, enhance=args.enhance)
        cv2.imwrite(args.output, res)
        print(f"Result saved to {args.output}")
    else:
        print("Image not found")
