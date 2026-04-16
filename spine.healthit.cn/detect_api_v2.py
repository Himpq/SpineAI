import os
import sys
import numpy as np
import cv2
import torch
import torch.nn as nn
import torch.nn.functional as F
import matplotlib.pyplot as plt
from PIL import Image

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# --- Model Paths ---
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Phase 1: Coarse Segmentation (ROI)
# COARSE_MODEL_PATH = os.path.join(CURRENT_DIR, "best_roi_model.pth")
# Phase 2: Fine Localization (Keypoints)
# LOC_MODEL_PATH = os.path.join(CURRENT_DIR, "best_loc_model.pth")

COARSE_MODEL_PATH = r"./weights/latest_model.pth"
LOC_MODEL_PATH = r"./latest_loc_model.pth"
# LOC_MODEL_PATH = r"D:\1_Himpq\Code\Spine\xRaySpine_Checkpoints\latest_loc_model.pth"
# --- Parameters ---
COARSE_INPUT_SIZE = (512, 1024) # (H, W) for Dataset transform
LOC_INPUT_SIZE = (512, 256)     # (H, W) for Model input

# -----------------------------------------------------------------------------
# [Standalone] Model Definition (from xRaySpine/model.py)
# -----------------------------------------------------------------------------
class ConvBlock(nn.Module):
    def __init__(self, in_ch, out_ch):
        super(ConvBlock, self).__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True)
        )

    def forward(self, x):
        return self.conv(x)

class AttentionBlock(nn.Module):
    def __init__(self, F_g, F_l, F_int):
        super(AttentionBlock, self).__init__()
        self.W_g = nn.Sequential(
            nn.Conv2d(F_g, F_int, kernel_size=1, stride=1, padding=0, bias=True),
            nn.BatchNorm2d(F_int)
        )
        
        self.W_x = nn.Sequential(
            nn.Conv2d(F_l, F_int, kernel_size=1, stride=1, padding=0, bias=True),
            nn.BatchNorm2d(F_int)
        )

        self.psi = nn.Sequential(
            nn.Conv2d(F_int, 1, kernel_size=1, stride=1, padding=0, bias=True),
            nn.BatchNorm2d(1),
            nn.Sigmoid()
        )
        
        self.relu = nn.ReLU(inplace=True)
        
    def forward(self, g, x):
        g1 = self.W_g(g)
        x1 = self.W_x(x)
        psi = self.relu(g1 + x1)
        psi = self.psi(psi)
        return x * psi

class AttentionUNet(nn.Module):
    def __init__(self, img_ch=3, output_ch=1):
        super(AttentionUNet, self).__init__()
        
        filters = [64, 128, 256, 512, 1024]
        
        self.maxpool = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv1 = ConvBlock(img_ch, filters[0])
        self.conv2 = ConvBlock(filters[0], filters[1])
        self.conv3 = ConvBlock(filters[1], filters[2])
        self.conv4 = ConvBlock(filters[2], filters[3])
        self.conv5 = ConvBlock(filters[3], filters[4])
        
        self.up5 = nn.Upsample(scale_factor=2, mode='bilinear', align_corners=True)
        self.att5 = AttentionBlock(F_g=filters[3], F_l=filters[3], F_int=filters[2]) # Gate from Up, Local from encoders
        self.up_conv5 = ConvBlock(filters[4] + filters[3], filters[3]) 
        
        self.up_sample5 = nn.ConvTranspose2d(filters[4], filters[3], kernel_size=2, stride=2)
        self.att5 = AttentionBlock(F_g=filters[3], F_l=filters[3], F_int=filters[2])
        self.up_conv5 = ConvBlock(filters[3] + filters[3], filters[3])
        
        self.up_sample4 = nn.ConvTranspose2d(filters[3], filters[2], kernel_size=2, stride=2)
        self.att4 = AttentionBlock(F_g=filters[2], F_l=filters[2], F_int=filters[1])
        self.up_conv4 = ConvBlock(filters[2] + filters[2], filters[2])
        
        self.up_sample3 = nn.ConvTranspose2d(filters[2], filters[1], kernel_size=2, stride=2)
        self.att3 = AttentionBlock(F_g=filters[1], F_l=filters[1], F_int=filters[0])
        self.up_conv3 = ConvBlock(filters[1] + filters[1], filters[1])
        
        self.up_sample2 = nn.ConvTranspose2d(filters[1], filters[0], kernel_size=2, stride=2)
        self.att2 = AttentionBlock(F_g=filters[0], F_l=filters[0], F_int=filters[0]//2)
        self.up_conv2 = ConvBlock(filters[0] + filters[0], filters[0])
        
        self.conv_1x1 = nn.Conv2d(filters[0], output_ch, kernel_size=1)
        
    def forward(self, x):
        # Encoder
        x1 = self.conv1(x)
        
        x2 = self.maxpool(x1)
        x2 = self.conv2(x2)
        
        x3 = self.maxpool(x2)
        x3 = self.conv3(x3)
        
        x4 = self.maxpool(x3)
        x4 = self.conv4(x4)
        
        x5 = self.maxpool(x4)
        x5 = self.conv5(x5)
        
        # Decoder
        
        # d5
        d5 = self.up_sample5(x5)
        x4_att = self.att5(g=d5, x=x4)
        d5 = torch.cat((x4_att, d5), dim=1)
        d5 = self.up_conv5(d5)
        
        # d4
        d4 = self.up_sample4(d5)
        x3_att = self.att4(g=d4, x=x3)
        d4 = torch.cat((x3_att, d4), dim=1)
        d4 = self.up_conv4(d4)
        
        # d3
        d3 = self.up_sample3(d4)
        x2_att = self.att3(g=d3, x=x2)
        d3 = torch.cat((x2_att, d3), dim=1)
        d3 = self.up_conv3(d3)
        
        # d2
        d2 = self.up_sample2(d3)
        x1_att = self.att2(g=d2, x=x1)
        d2 = torch.cat((x1_att, d2), dim=1)
        d2 = self.up_conv2(d2)
        
        out = self.conv_1x1(d2)
        
        return out

# -----------------------------------------------------------------------------
# [Standalone] Utils (from xRaySpine/pre_process.py, xRaySpine/utils.py)
# -----------------------------------------------------------------------------
def refine_mask(mask_prob, threshold=0.5, dilate_iter=3):
    """
    Refine the predicted probability map for ROI extraction.
    """
    # 1. Binarize
    if mask_prob.max() <= 1.0:
        mask_bin = (mask_prob > threshold).astype(np.uint8) * 255
    else:
        mask_bin = mask_prob.astype(np.uint8)
    
    # Kernels
    open_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    close_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (40, 40)) 
    dilate_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))

    # 2. Morphological Opening (Remove burrs/noise first)
    mask_bin = cv2.morphologyEx(mask_bin, cv2.MORPH_OPEN, open_kernel)
    
    # 3. Keep Largest Component
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(mask_bin, connectivity=8)
    if num_labels > 1:
        areas = stats[1:, 4]
        if len(areas) > 0:
            max_label = 1 + np.argmax(areas)
            mask_refined = np.zeros_like(mask_bin)
            mask_refined[labels == max_label] = 255
            mask_bin = mask_refined
    
    # 4. Morphological Closing (Fill holes inside)
    mask_bin = cv2.morphologyEx(mask_bin, cv2.MORPH_CLOSE, close_kernel)
    
    # 5. Dilation (Expand boundaries)
    if dilate_iter > 0:
        mask_bin = cv2.dilate(mask_bin, dilate_kernel, iterations=dilate_iter)
    
    return mask_bin

def get_roi_bbox(mask_bin, margin_ratio=0.1):
    """
    Get bounding box from binary mask with margin.
    Returns: (x_min, y_min, x_max, y_max)
    """
    y_indices, x_indices = np.where(mask_bin > 127)
    
    if len(y_indices) == 0:
        # Fallback: return full image or center crop
        h, w = mask_bin.shape
        return 0, 0, w, h
        
    y_min, y_max = np.min(y_indices), np.max(y_indices)
    x_min, x_max = np.min(x_indices), np.max(x_indices)
    
    h_box = y_max - y_min
    w_box = x_max - x_min
    
    # Add Margin
    margin_h = int(h_box * margin_ratio)
    margin_w = int(w_box * margin_ratio)
    
    h_img, w_img = mask_bin.shape
    
    y_min = max(0, y_min - margin_h)
    y_max = min(h_img, y_max + margin_h)
    x_min = max(0, x_min - margin_w)
    x_max = min(w_img, x_max + margin_w)
    
    return x_min, y_min, x_max, y_max

def get_roi_bbox_asym(mask_bin, margin_top=0.02, margin_bottom=0.1, margin_lr=0.1):
    """
    Get bounding box with asymmetric margins.
    Crucial for avoiding T12 (top) while keeping S1 (bottom).
    """
    y_indices, x_indices = np.where(mask_bin > 127)
    
    if len(y_indices) == 0:
        h, w = mask_bin.shape
        return 0, 0, w, h
        
    y_min, y_max = np.min(y_indices), np.max(y_indices)
    x_min, x_max = np.min(x_indices), np.max(x_indices)
    
    h_box = y_max - y_min
    w_box = x_max - x_min
    
    m_top = int(h_box * margin_top)
    m_bot = int(h_box * margin_bottom)
    m_lr = int(w_box * margin_lr)
    
    h_img, w_img = mask_bin.shape
    
    y_min = max(0, y_min - m_top)
    y_max = min(h_img, y_max + m_bot)
    x_min = max(0, x_min - m_lr)
    x_max = min(w_img, x_max + m_lr)
    
    return x_min, y_min, x_max, y_max

# -----------------------------------------------------------------------------
# Singleton Model Holder
# -----------------------------------------------------------------------------
_COARSE_MODEL = None
_LOC_MODEL = None

def load_models():
    """Load both models if not already loaded."""
    global _COARSE_MODEL, _LOC_MODEL
    
    if _COARSE_MODEL is None:
        if not os.path.exists(COARSE_MODEL_PATH):
            raise FileNotFoundError(f"Coarse model not found: {COARSE_MODEL_PATH}")
        # print(f"Loading Coarse Model from {COARSE_MODEL_PATH}")
        model = AttentionUNet(img_ch=3, output_ch=1).to(DEVICE)
        state = torch.load(COARSE_MODEL_PATH, map_location=DEVICE)
        model.load_state_dict(state)
        model.eval()
        _COARSE_MODEL = model
        
    if _LOC_MODEL is None:
        if not os.path.exists(LOC_MODEL_PATH):
            raise FileNotFoundError(f"Loc model not found: {LOC_MODEL_PATH}")
        # print(f"Loading Localization Model from {LOC_MODEL_PATH}")
        model = AttentionUNet(img_ch=3, output_ch=22).to(DEVICE)
        # Handle matching issue
        try:
            state = torch.load(LOC_MODEL_PATH, map_location=DEVICE)
        except Exception as e:
            # Fallback for some pytorch versions saving weirdly
            print(f"Direct load failed, trying full load: {e}")
            state = torch.load(LOC_MODEL_PATH, map_location=DEVICE)

        try:
            model.load_state_dict(state, strict=True)
        except RuntimeError:
            print("Warning: Strict loading failed, trying sloppy loading (removing mismatch layers)...")
            if isinstance(state, dict):
                # Remove mismatch keys
                if 'conv_1x1.weight' in state:
                    del state['conv_1x1.weight']
                if 'conv_1x1.bias' in state:
                    del state['conv_1x1.bias']
                model.load_state_dict(state, strict=False)
            
        model.eval()
        _LOC_MODEL = model

    return _COARSE_MODEL, _LOC_MODEL

# -----------------------------------------------------------------------------
# Helper: Drawing Closed Polygons
# -----------------------------------------------------------------------------
def draw_spine_polygons(image, kps_dict):
    """
    Draw closed polygons for L1-L5 and line for S1 on the image.
    kps_dict: { 'L1a1': (x,y), ... } (may contain None)
    image: BGR numpy array
    """
    overlay = image.copy()

    def draw_trisect_right_edge(a2_pt, b2_pt, color):
        a2_np = np.array(a2_pt, dtype=np.float32)
        b2_np = np.array(b2_pt, dtype=np.float32)
        v = b2_np - a2_np
        v_len = float(np.linalg.norm(v))
        if v_len < 1.0:
            return

        # Perpendicular pointing to the right (positive x direction)
        perp = np.array([-v[1], v[0]], dtype=np.float32)
        if np.linalg.norm(perp) < 1e-6:
            return
        if perp[0] < 0:
            perp = -perp
        perp = perp / (np.linalg.norm(perp) + 1e-6)

        offset = max(6, int(v_len * 0.08))
        p1 = a2_np + perp * offset
        p2 = b2_np + perp * offset

        p1_i = (int(round(p1[0])), int(round(p1[1])))
        p2_i = (int(round(p2[0])), int(round(p2[1])))
        cv2.line(overlay, p1_i, p2_i, color, thickness=2)

        # Mark trisection points
        v_unit = v / v_len
        t1 = p1 + v_unit * (v_len / 3.0)
        t2 = p1 + v_unit * (2.0 * v_len / 3.0)
        t1_i = (int(round(t1[0])), int(round(t1[1])))
        t2_i = (int(round(t2[0])), int(round(t2[1])))
        cv2.circle(overlay, t1_i, 3, color, -1)
        cv2.circle(overlay, t2_i, 3, color, -1)
    
    # Define topology
    # L1-L5: a1(TL) -> a2(TR) -> b2(BR) -> b1(BL) -> close
    levels = ["L1", "L2", "L3", "L4", "L5"]
    
    # Define nice colors
    colors = {
        'L1': (50, 50, 200),   # Red-ish
        'L2': (0, 165, 255),   # Orange
        'L3': (0, 255, 255),   # Yellow
        'L4': (0, 200, 0),     # Green
        'L5': (255, 0, 0),     # Blue
        'S1': (200, 0, 200)    # Purple
    }
    
    # Draw L1-L5 Polygons
    for lvl in levels:
        pts = []
        # Order matters for filling polygon correctly
        for suffix in ['a1', 'a2', 'b2', 'b1']: 
            k = f"{lvl}{suffix}"
            pt = kps_dict.get(k)
            if pt is not None:
                pts.append(pt)
        
        if len(pts) == 4:
            pts_np = np.array(pts, dtype=np.int32)
            pts_np = pts_np.reshape((-1, 1, 2))
            
            color = colors.get(lvl, (255, 255, 255))
            
            # Fill with transparency
            poly_overlay = overlay.copy()
            cv2.fillPoly(poly_overlay, [pts_np], color=color)
            cv2.addWeighted(poly_overlay, 0.4, overlay, 0.6, 0, overlay)
            
            # Thick Outline
            cv2.polylines(overlay, [pts_np], isClosed=True, color=color, thickness=2)

            # For L4/L5: draw a trisected line segment to the right of the rectangle
            if lvl in ("L4", "L5"):
                a2 = kps_dict.get(f"{lvl}a2")
                b2 = kps_dict.get(f"{lvl}b2")
                if a2 is not None and b2 is not None:
                    draw_trisect_right_edge(a2, b2, color)

    # Draw S1 (Line or Triangle)
    # S1 usually has a1, a2 (Upper Plate). 
    s1a1 = kps_dict.get('S1a1')
    s1a2 = kps_dict.get('S1a2')
    if s1a1 and s1a2:
        color = colors['S1']
        cv2.line(overlay, s1a1, s1a2, color, thickness=3)
        # Optional: draw bubbles at ends
        cv2.circle(overlay, s1a1, 4, color, -1)
        cv2.circle(overlay, s1a2, 4, color, -1)

    # Label Text
    for lvl in levels + ["S1"]:
        group_pts = []
        suffixes = ['a1', 'a2', 'b1', 'b2'] if lvl != 'S1' else ['a1', 'a2']
        for s in suffixes:
            pt = kps_dict.get(f"{lvl}{s}")
            if pt: group_pts.append(pt)
        
        if group_pts:
            cx = int(np.mean([p[0] for p in group_pts]))
            cy = int(np.mean([p[1] for p in group_pts]))
            
            # Draw text with background
            text = lvl
            (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)
            cv2.rectangle(overlay, (cx - tw//2 - 2, cy - th//2 - 2), (cx + tw//2 + 2, cy + th//2 + 2), (0,0,0), -1)
            cv2.putText(overlay, text, (cx - tw//2, cy + th//2), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

    return overlay


# -----------------------------------------------------------------------------
# Main Pipeline
# -----------------------------------------------------------------------------
def run_pipeline(img_path_or_np, return_debug_image=True):
    coarse_model, loc_model = load_models()
    
    # 1. Load Original Image
    if isinstance(img_path_or_np, str):
        if not os.path.exists(img_path_or_np): raise ValueError("File not found")
        img_pil = Image.open(img_path_or_np).convert("RGB")
        img_np_orig = np.array(img_pil) # RGB
    else:
        # Assume BGR input (OpenCV)
        if img_path_or_np.ndim == 3 and img_path_or_np.shape[2] == 3:
            img_np_orig = cv2.cvtColor(img_path_or_np, cv2.COLOR_BGR2RGB)
        else:
            img_np_orig = img_path_or_np # Gray?
        img_pil = Image.fromarray(img_np_orig)
        
    H_orig, W_orig = img_np_orig.shape[:2]
    
    # -----------------------------------------------------
    # Step 1: Coarse Segmentation (Global View)
    # -----------------------------------------------------
    target_w, target_h = 512, 1024
    img_coarse_in = img_pil.resize((target_w, target_h), Image.BILINEAR)
    img_coarse_t = torch.from_numpy(np.array(img_coarse_in)).float().permute(2, 0, 1) / 255.0
    img_coarse_t = img_coarse_t.unsqueeze(0).to(DEVICE)
    
    with torch.no_grad():
        out = coarse_model(img_coarse_t)
        prob = torch.sigmoid(out)[0, 0].cpu().numpy()
        
    # Refine Mask
    # Reduce dilation to avoid merging T12 into the blob
    mask_refined = refine_mask(prob, threshold=0.5, dilate_iter=1)
    
    # Get BBox on Coarse Image
    # 策略调整 (回退): 负Margin切掉了正常L1。
    # 现使用小正Margin (0.02) 紧贴上缘，底部 (0.15) 宽松保留S1。
    roi_x1, roi_y1, roi_x2, roi_y2 = get_roi_bbox_asym(
        mask_refined, 
        margin_top=0.15,     # 改回正值：防止切坏L1
        margin_bottom=0.15,  # 增大底部：确保S1不被切
        margin_lr=0.12
    )
    
    # Map BBox back to Original Image
    scale_x = W_orig / target_w
    scale_y = H_orig / target_h
    
    orig_x1 = int(roi_x1 * scale_x)
    orig_x2 = int(roi_x2 * scale_x)
    orig_y1 = int(roi_y1 * scale_y)
    orig_y2 = int(roi_y2 * scale_y)
    
    # Clamp
    orig_x1, orig_y1 = max(0, orig_x1), max(0, orig_y1)
    orig_x2, orig_y2 = min(W_orig, orig_x2), min(H_orig, orig_y2)
    
    # If BBox is invalid or too small, fallback to full image
    if (orig_x2 - orig_x1) < 10 or (orig_y2 - orig_y1) < 10:
        print("Warning: ROI too small, using full image.")
        orig_x1, orig_y1, orig_x2, orig_y2 = 0, 0, W_orig, H_orig

    # -----------------------------------------------------
    # Step 2: Crop & Fine Localization
    # -----------------------------------------------------
    # Crop Original
    img_crop = img_pil.crop((orig_x1, orig_y1, orig_x2, orig_y2))
    
    # Resize for Loc Model
    # Loc model input_size=(512, 256) -> usually (Height, Width) in tensor
    # PIL Resize (W, H) -> (256, 512)
    loc_h_in, loc_w_in = LOC_INPUT_SIZE # 512, 256 (Tensor H, W)
    img_loc_in = img_crop.resize((loc_w_in, loc_h_in), Image.BILINEAR)
    
    img_loc_t = torch.from_numpy(np.array(img_loc_in)).float().permute(2, 0, 1) / 255.0
    img_loc_t = img_loc_t.unsqueeze(0).to(DEVICE)
    
    with torch.no_grad():
        out_loc = loc_model(img_loc_t)
        # Output (1, 22, 512, 256)
        heatmaps = out_loc[0].cpu().numpy()
        
    # -----------------------------------------------------
    # Step 3: Interpret Points
    # -----------------------------------------------------
    # Points are in (loc_w_in, loc_h_in) = (256, 512) coordinate system
    
    # Crop width/height
    crop_w = orig_x2 - orig_x1
    crop_h = orig_y2 - orig_y1
    
    scale_crop_x = crop_w / loc_w_in
    scale_crop_y = crop_h / loc_h_in
    
    kps_dict = {}
    
    labels = []
    for lvl in ["L1", "L2", "L3", "L4", "L5"]:
        labels.extend([f"{lvl}a1", f"{lvl}a2", f"{lvl}b1", f"{lvl}b2"])
    labels.extend(["S1a1", "S1a2"])
    
    valid_count = 0
    for i, label in enumerate(labels):
        hm = heatmaps[i] # (512, 256) H, W
        
        # Argmax
        py, px = np.unravel_index(np.argmax(hm), hm.shape)
        val = hm[py, px]
        
        if val > 0.05: # Confidence Threshold
            # Map px, py (in 256, 512) to Crop
            cx = px * scale_crop_x
            cy = py * scale_crop_y
            
            # Map to Global
            gx = int(cx + orig_x1)
            gy = int(cy + orig_y1)
            
            kps_dict[label] = (gx, gy)
            valid_count += 1
        else:
            kps_dict[label] = None

    result = {
        "keypoints": kps_dict,
        "bbox": (orig_x1, orig_y1, orig_x2, orig_y2),
        "valid_points": valid_count
    }
    
    # -----------------------------------------------------
    # Step 4: Visualizations (One Big Image)
    # -----------------------------------------------------
    if return_debug_image:
        # Prepare BGR Base Images
        vis_1_orig = cv2.cvtColor(img_np_orig, cv2.COLOR_RGB2BGR)
        
        # Vis 2: Coarse Mask + ROI (on resized coarse image)
        vis_2_mask = cv2.cvtColor(np.array(img_coarse_in), cv2.COLOR_RGB2BGR)
        # Colorize mask
        mask_green = np.zeros_like(vis_2_mask)
        mask_green[:, :, 1] = mask_refined # Green channel
        vis_2_mask = cv2.addWeighted(vis_2_mask, 0.7, mask_green, 0.5, 0)
        # Draw ROI found in this scale
        cv2.rectangle(vis_2_mask, (roi_x1, roi_y1), (roi_x2, roi_y2), (0, 0, 255), 3)
        
        # Vis 3: Prediction Heatmap Overlay (on Crop Input)
        vis_3_hm = cv2.cvtColor(np.array(img_loc_in), cv2.COLOR_RGB2BGR)
        # Combine maps
        hm_combined = np.max(heatmaps, axis=0) # (512, 256)
        # Normalize 0-255
        hm_norm = cv2.normalize(hm_combined, None, 0, 255, cv2.NORM_MINMAX, dtype=cv2.CV_8U)
        hm_color = cv2.applyColorMap(hm_norm, cv2.COLORMAP_JET)
        vis_3_hm = cv2.addWeighted(vis_3_hm, 0.6, hm_color, 0.4, 0)
        
        # Vis 4: Final Result with Polygons (on Original)
        vis_4_final = cv2.cvtColor(img_np_orig, cv2.COLOR_RGB2BGR)
        vis_4_final = draw_spine_polygons(vis_4_final, kps_dict)
        # Draw the Used Crop BBox
        cv2.rectangle(vis_4_final, (orig_x1, orig_y1), (orig_x2, orig_y2), (0, 255, 255), 2)

        # ---------------- Combine into Grid ----------------
        # Helper to scale preserving aspect ratio to fixed Height
        def scale_h(img, h=600):
            factor = h / img.shape[0]
            w = int(img.shape[1] * factor)
            return cv2.resize(img, (w, h))

        row_h = 600
        img1 = scale_h(vis_1_orig, row_h)
        img2 = scale_h(vis_2_mask, row_h) 
        img3 = scale_h(vis_3_hm, row_h)
        img4 = scale_h(vis_4_final, row_h)
        
        # Top Row
        top_h = row_h
        top_w = img1.shape[1] + img2.shape[1]
        top_row = np.zeros((top_h, top_w, 3), dtype=np.uint8)
        top_row[:, :img1.shape[1]] = img1
        top_row[:, img1.shape[1]:] = img2
        
        # Bot Row
        bot_h = row_h
        bot_crop_w = img3.shape[1]
        
        bot_w = img3.shape[1] + img4.shape[1]
        bot_row = np.zeros((bot_h, bot_w, 3), dtype=np.uint8)
        bot_row[:, :img3.shape[1]] = img3
        bot_row[:, img3.shape[1]:] = img4
        
        # Final Canvas
        final_w = max(top_w, bot_w)
        final_h = top_h + bot_h
        canvas = np.zeros((final_h, final_w, 3), dtype=np.uint8)
        
        # Center rows? Or left align
        canvas[:top_h, :top_w] = top_row
        canvas[top_h:, :bot_w] = bot_row
        
        # Titles
        cv2.putText(canvas, "1. Original", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(canvas, "2. Coarse ROI Mask", (img1.shape[1] + 20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(canvas, "3. Crop Heatmaps", (20, top_h + 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(canvas, "4. Final Result", (img3.shape[1] + 20, top_h + 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)

        result["debug_image"] = canvas
        
    return result

if __name__ == "__main__":
    test_dir = os.path.join(CURRENT_DIR, "../../testimgs") # Relative fallback
    if not os.path.exists(test_dir):
        # Fallback to local 'testimgs' if running separated
        test_dir = os.path.join(CURRENT_DIR, "testimgs")

    test_target = None
    if os.path.exists(test_dir):
        files = [f for f in os.listdir(test_dir) if f.lower().endswith(('.png', '.jpg'))]
        if files:
            import random
            test_target = os.path.join(test_dir, random.choice(files))
            
    if test_target and os.path.exists(test_target):
        print(f"Running Standalone Pipeline on: {test_target}")
        res = run_pipeline(test_target, return_debug_image=True)
        print(f"Analysis Complete. Found {res['valid_points']}/22 Keypoints.")
        
        plt.figure(figsize=(15, 15))
        plt.imshow(cv2.cvtColor(res['debug_image'], cv2.COLOR_BGR2RGB))
        plt.axis('off')
        plt.title("Standalone Spine Detection v2")
        plt.show()
    else:
        print("No image found for testing.")
