"""
颈椎 / 腰椎 X 光分类 —— 推理脚本 (All-in-One)
包含: 模型定义 → 单张/批量推理 → ONNX 导出 → Gradio Web 应用

用法:
    python classify.py <图像路径> [图像路径2 ...]   # 命令行分类
    python classify.py --export-onnx                 # 导出 ONNX
    python classify.py --app                         # 启动 Gradio Web UI
    python classify.py --folder <目录>               # 批量分类整个目录
"""

import os
import sys
import argparse
import glob

import cv2
import numpy as np
import torch
import torch.nn as nn
from torchvision import models
from torchvision.models import EfficientNet_B0_Weights
try:
    import albumentations as A
    from albumentations.pytorch import ToTensorV2
except ImportError:
    A = None
    ToTensorV2 = None


# =====================================================================
#  配置
# =====================================================================
MODEL_PATH  = r"E:\spine\code\spine_classifier\output\best_model.pth"
ONNX_PATH   = r"E:\spine\code\spine_classifier\output\spine_classifier.onnx"
IMG_SIZE     = 224
CLASS_NAMES  = ['颈椎 (Cervical)', '腰椎 (Lumbar)']
DEVICE       = 'cuda' if torch.cuda.is_available() else 'cpu'

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD  = [0.229, 0.224, 0.225]


def tensor_to_numpy(tensor: torch.Tensor) -> np.ndarray:
    """Convert a tensor to a NumPy array without relying on torch's NumPy bridge."""
    return np.asarray(tensor.detach().cpu().tolist())


# =====================================================================
#  模型定义 (与训练脚本一致)
# =====================================================================
class SpineClassifier(nn.Module):
    """基于 EfficientNet-B0 的脊椎分类器"""

    def __init__(self, pretrained=True, dropout=0.3):
        super().__init__()
        if pretrained:
            self.backbone = models.efficientnet_b0(weights=EfficientNet_B0_Weights.IMAGENET1K_V1)
        else:
            self.backbone = models.efficientnet_b0(weights=None)
        in_features = self.backbone.classifier[1].in_features  # 1280
        self.backbone.classifier = nn.Sequential(
            nn.Dropout(p=dropout),
            nn.Linear(in_features, 1),
        )

    def forward(self, x):
        return self.backbone(x).squeeze(-1)


# =====================================================================
#  图像预处理
# =====================================================================
def get_val_transforms(img_size=224):
    if A is not None and ToTensorV2 is not None:
        return A.Compose([
            A.LongestMaxSize(max_size=img_size),
            A.PadIfNeeded(min_height=img_size, min_width=img_size,
                          border_mode=cv2.BORDER_CONSTANT, fill=0),
            A.CenterCrop(height=img_size, width=img_size),
            A.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
            ToTensorV2(),
        ])

    class _FallbackTransform:
        def __init__(self, size):
            self.size = size
            self.mean = np.array(IMAGENET_MEAN, dtype=np.float32).reshape(1, 1, 3)
            self.std = np.array(IMAGENET_STD, dtype=np.float32).reshape(1, 1, 3)

        def __call__(self, image=None, **kwargs):
            img = kwargs.get("image", image)
            if isinstance(img, dict):
                img = img.get("image")
            if img is None:
                raise ValueError("Fallback transform requires image input")
            h, w = img.shape[:2]
            scale = self.size / max(h, w)
            nh, nw = max(1, int(round(h * scale))), max(1, int(round(w * scale)))
            resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)

            canvas = np.zeros((self.size, self.size, 3), dtype=np.uint8)
            top = (self.size - nh) // 2
            left = (self.size - nw) // 2
            canvas[top:top + nh, left:left + nw] = resized

            arr = canvas.astype(np.float32) / 255.0
            arr = (arr - self.mean) / self.std
            arr = np.transpose(arr, (2, 0, 1))
            tensor = torch.from_numpy(arr).float()
            return {"image": tensor}

    print("Warning: albumentations not installed, using fallback preprocessing.")
    return _FallbackTransform(img_size)


# =====================================================================
#  推理器
# =====================================================================
class SpinePredictor:
    """脊椎分类推理器，支持 PyTorch 和 ONNX"""

    def __init__(self, model_path=None, onnx_path=None, device=None):
        self.device = device or DEVICE
        self.transform = get_val_transforms(IMG_SIZE)
        self.onnx_session = None
        self.model = None

        # 优先 ONNX
        if onnx_path and os.path.exists(onnx_path):
            self._load_onnx(onnx_path)
        elif model_path and os.path.exists(model_path):
            self._load_pytorch(model_path)
        else:
            raise FileNotFoundError(f"未找到模型文件: {model_path} 或 {onnx_path}")

    def _load_pytorch(self, path):
        print(f"加载 PyTorch 模型: {path}")
        self.model = SpineClassifier(pretrained=False)
        try:
            ckpt = torch.load(path, map_location=self.device, weights_only=True)
        except TypeError:
            ckpt = torch.load(path, map_location=self.device)

        state_dict = None
        if isinstance(ckpt, dict):
            if 'model_state_dict' in ckpt and isinstance(ckpt['model_state_dict'], dict):
                state_dict = ckpt['model_state_dict']
            elif 'state_dict' in ckpt and isinstance(ckpt['state_dict'], dict):
                state_dict = ckpt['state_dict']
            elif 'model' in ckpt and isinstance(ckpt['model'], dict):
                state_dict = ckpt['model']
            elif all(isinstance(v, torch.Tensor) for v in ckpt.values()):
                state_dict = ckpt

        if state_dict is None:
            raise KeyError("无法从checkpoint中找到模型权重（支持: model_state_dict/state_dict/model/纯state_dict）")

        # 兼容 DataParallel 保存的 module.* 前缀
        cleaned_state_dict = {}
        for key, value in state_dict.items():
            if key.startswith('module.'):
                cleaned_state_dict[key[7:]] = value
            else:
                cleaned_state_dict[key] = value

        self.model.load_state_dict(cleaned_state_dict, strict=False)
        self.model = self.model.to(self.device)
        self.model.eval()

    def _load_onnx(self, path):
        import onnxruntime as ort
        print(f"加载 ONNX 模型: {path}")
        providers = ['CUDAExecutionProvider', 'CPUExecutionProvider']
        self.onnx_session = ort.InferenceSession(path, providers=providers)

    def preprocess(self, image_path):
        img = cv2.imread(image_path)
        if img is None:
            raise ValueError(f"无法读取图像: {image_path}")
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        return self.transform(image=img)['image']

    def preprocess_array(self, img_bgr):
        if img_bgr is None:
            raise ValueError("输入图像为空")
        img = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        return self.transform(image=img)['image']

    def predict(self, image_path):
        """
        预测单张图像
        Returns: dict with class_name, class_id, confidence, logit, prob_lumbar
        """
        img_tensor = self.preprocess(image_path)

        if self.onnx_session is not None:
            input_np = tensor_to_numpy(img_tensor.unsqueeze(0))
            input_name = self.onnx_session.get_inputs()[0].name
            output = self.onnx_session.run(None, {input_name: input_np})
            logit = output[0].item()
        else:
            with torch.no_grad():
                img_input = img_tensor.unsqueeze(0).to(self.device)
                logit = self.model(img_input).item()

        prob = 1 / (1 + np.exp(-logit))
        class_id = 1 if prob >= 0.5 else 0
        confidence = prob if class_id == 1 else 1 - prob

        return {
            'class_name':  CLASS_NAMES[class_id],
            'class_id':    class_id,
            'confidence':  float(confidence),
            'logit':       float(logit),
            'prob_lumbar': float(prob),
        }

    def predict_array(self, img_bgr):
        """
        预测单张内存图像(BGR)
        Returns: dict with class_name, class_id, confidence, logit, prob_lumbar
        """
        img_tensor = self.preprocess_array(img_bgr)

        if self.onnx_session is not None:
            input_np = tensor_to_numpy(img_tensor.unsqueeze(0))
            input_name = self.onnx_session.get_inputs()[0].name
            output = self.onnx_session.run(None, {input_name: input_np})
            logit = output[0].item()
        else:
            with torch.no_grad():
                img_input = img_tensor.unsqueeze(0).to(self.device)
                logit = self.model(img_input).item()

        prob = 1 / (1 + np.exp(-logit))
        class_id = 1 if prob >= 0.5 else 0
        confidence = prob if class_id == 1 else 1 - prob

        return {
            'class_name':  CLASS_NAMES[class_id],
            'class_id':    class_id,
            'confidence':  float(confidence),
            'logit':       float(logit),
            'prob_lumbar': float(prob),
        }

    def predict_batch(self, image_paths):
        return [self.predict(p) for p in image_paths]


# =====================================================================
#  Grad-CAM (用于 Gradio 可视化)
# =====================================================================
class GradCAM:
    def __init__(self, model, target_layer):
        self.model = model
        self.gradients = None
        self.activations = None
        target_layer.register_forward_hook(
            lambda m, i, o: setattr(self, 'activations', o.detach()))
        target_layer.register_full_backward_hook(
            lambda m, gi, go: setattr(self, 'gradients', go[0].detach()))

    def generate(self, x):
        self.model.zero_grad()
        output = self.model(x)
        output.backward()
        weights = self.gradients.mean(dim=(2, 3), keepdim=True)
        cam = tensor_to_numpy(torch.relu((weights * self.activations).sum(dim=1)).squeeze())
        if cam.max() > 0:
            cam = (cam - cam.min()) / cam.max()
        return cam, output.item()


# =====================================================================
#  ONNX 导出
# =====================================================================
def export_onnx(model_path=MODEL_PATH, onnx_path=ONNX_PATH):
    """导出 ONNX 并验证一致性"""
    model = SpineClassifier(pretrained=False)
    ckpt = torch.load(model_path, map_location='cpu', weights_only=True)
    model.load_state_dict(ckpt['model_state_dict'])
    model.eval()
    print(f"模型已加载 (Best epoch: {ckpt['epoch']}, AUC: {ckpt['best_auc']:.4f})")

    os.makedirs(os.path.dirname(onnx_path), exist_ok=True)
    dummy_input = torch.randn(1, 3, IMG_SIZE, IMG_SIZE)

    torch.onnx.export(
        model, dummy_input, onnx_path,
        opset_version=13,
        input_names=['input'],
        output_names=['output'],
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}},
    )
    print(f"ONNX 已导出 -> {onnx_path}")

    # 验证
    import onnx
    onnx_model = onnx.load(onnx_path)
    onnx.checker.check_model(onnx_model)
    print("ONNX 模型验证通过")

    # 一致性比较
    import onnxruntime as ort
    session = ort.InferenceSession(onnx_path, providers=['CPUExecutionProvider'])
    test_input = torch.randn(1, 3, IMG_SIZE, IMG_SIZE)
    with torch.no_grad():
        pt_out = tensor_to_numpy(model(test_input))
    ort_out = session.run(None, {'input': tensor_to_numpy(test_input)})[0]
    max_diff = np.abs(pt_out - ort_out).max()
    print(f"PyTorch vs ONNX 最大差异: {max_diff:.8f}")
    print("一致性验证通过!" if max_diff < 1e-5 else "警告: 输出差异较大，请检查")

    size_mb = os.path.getsize(onnx_path) / 1024 / 1024
    print(f"ONNX 大小: {size_mb:.1f} MB")


# =====================================================================
#  Gradio Web 应用
# =====================================================================
def launch_app(model_path=MODEL_PATH):
    """启动 Gradio Web 界面"""
    import gradio as gr

    # 加载模型
    model = SpineClassifier(pretrained=False)
    ckpt = torch.load(model_path, map_location=DEVICE, weights_only=True)
    model.load_state_dict(ckpt['model_state_dict'])
    model = model.to(DEVICE)
    model.eval()

    transform = get_val_transforms(IMG_SIZE)
    grad_cam = GradCAM(model, model.backbone.features[-1])

    def predict_and_visualize(image):
        if image is None:
            return None, "请上传一张 X 光图像"

        img_rgb = image.copy()
        augmented = transform(image=img_rgb)
        img_tensor = augmented['image'].unsqueeze(0).to(DEVICE)
        img_tensor.requires_grad_(True)

        cam, logit = grad_cam.generate(img_tensor)
        prob = 1 / (1 + np.exp(-logit))
        class_id = 1 if prob >= 0.5 else 0

        # 热力图叠加
        cam_resized = cv2.resize(cam, (img_rgb.shape[1], img_rgb.shape[0]))
        heatmap = cv2.applyColorMap(np.uint8(255 * cam_resized), cv2.COLORMAP_JET)
        heatmap = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)
        overlay = np.uint8(0.5 * img_rgb + 0.5 * heatmap)

        label_text = {
            CLASS_NAMES[0]: float(1 - prob),
            CLASS_NAMES[1]: float(prob),
        }
        return overlay, label_text

    with gr.Blocks(title="脊椎 X 光分类器", theme=gr.themes.Soft()) as demo:
        gr.Markdown("# 颈椎 / 腰椎 X 光片分类器")
        gr.Markdown("上传一张脊椎 X 光片，模型将自动判断是**颈椎**还是**腰椎**，并显示 Grad-CAM 注意力热力图。")
        with gr.Row():
            with gr.Column():
                input_image = gr.Image(label="上传 X 光图像", type="numpy")
                predict_btn = gr.Button("开始分类", variant="primary")
            with gr.Column():
                output_image = gr.Image(label="Grad-CAM 热力图")
                output_label = gr.Label(label="分类结果", num_top_classes=2)
        predict_btn.click(fn=predict_and_visualize, inputs=input_image,
                          outputs=[output_image, output_label])

    demo.launch(server_name="0.0.0.0", server_port=7860, share=False)


# =====================================================================
#  命令行分类 & 目录批量分类
# =====================================================================
def classify_folder(folder_path, predictor):
    """批量分类目录下所有图像"""
    import psutil
    process = psutil.Process()
    exts = ('*.png', '*.jpg', '*.jpeg', '*.bmp', '*.tiff')
    image_paths = []
    for ext in exts:
        image_paths.extend(glob.glob(os.path.join(folder_path, ext)))
    image_paths.sort()

    if not image_paths:
        print(f"目录中未找到图像: {folder_path}")
        return

    print(f"共发现 {len(image_paths)} 张图像\n")
    counts = {0: 0, 1: 0}
    for path in image_paths:
        try:
            result = predictor.predict(path)
            mem_mb = process.memory_info().rss / 1024 / 1024
            counts[result['class_id']] += 1
            print(f"  {os.path.basename(path):30s}  →  {result['class_name']}  "
                  f"(置信度: {result['confidence']:.4f}, 内存占用: {mem_mb:.2f} MB)")
        except Exception as e:
            print(f"  {os.path.basename(path):30s}  →  错误: {e}")

    print(f"\n统计: 颈椎={counts[0]}, 腰椎={counts[1]}, 总计={sum(counts.values())}")


# =====================================================================
#  主入口
# =====================================================================
def main():
    parser = argparse.ArgumentParser(description='颈椎/腰椎 X光分类 - 推理脚本')
    parser.add_argument('images', nargs='*', help='待分类的图像文件路径')
    parser.add_argument('--model', default=MODEL_PATH, help='PyTorch 模型路径')
    parser.add_argument('--onnx', default=ONNX_PATH, help='ONNX 模型路径')
    parser.add_argument('--export-onnx', action='store_true', help='导出 ONNX 模型')
    parser.add_argument('--app', action='store_true', help='启动 Gradio Web 界面')
    parser.add_argument('--folder', type=str, help='批量分类整个目录')
    args = parser.parse_args()

    # ONNX 导出
    if args.export_onnx:
        export_onnx(args.model, args.onnx)
        return

    # Gradio Web
    if args.app:
        launch_app(args.model)
        return

    # 命令行推理
    predictor = SpinePredictor(model_path=args.model, onnx_path=args.onnx)

    # 目录批量
    if args.folder:
        classify_folder(args.folder, predictor)
        return

    # 单张/多张
    if not args.images:
        parser.print_help()
        print("\n示例:")
        print(f"  python classify.py image1.jpg image2.png")
        print(f"  python classify.py --folder E:\\spine\\data\\c_spine+spine\\cspine")
        print(f"  python classify.py --export-onnx")
        print(f"  python classify.py --app")
        return

    import psutil
    process = psutil.Process()
    for path in args.images:
        result = predictor.predict(path)
        mem_mb = process.memory_info().rss / 1024 / 1024
        print(f"\n{path}")
        print(f"  分类:     {result['class_name']}")
        print(f"  置信度:   {result['confidence']:.4f}")
        print(f"  腰椎概率: {result['prob_lumbar']:.4f}")
        print(f"  内存占用: {mem_mb:.2f} MB")


if __name__ == '__main__':
    main()
