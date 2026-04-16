import os
import cv2
import base64
import numpy as np
import json
import requests
import time
from collections import deque
from flask import Flask, render_template, jsonify, url_for, request, Response, stream_with_context
os.chdir(os.path.dirname(os.path.abspath(__file__)))
# Import our new standalone detect api v3
try:
    from detect_api_v3 import run_pipeline
except ImportError as e:
    print(f"Warning: detect_api_v3 import failed: {e}")
    run_pipeline = None

try:
    from openai import OpenAI
    client = OpenAI(api_key=os.environ.get("STEPFUN_API_KEY", ""), base_url="https://api.stepfun.com/v1")
except ImportError as e:
    print(f"Warning: OpenAI client import failed: {e}")
    client = None

app = Flask(__name__, static_folder='static', template_folder='templates')

REMOTE_INFER_URL = "http://127.0.0.1:15443"
REMOTE_TIMEOUT = 120

_LATENCY_HISTORY_MS = deque(maxlen=30)
_STATUS_ERRORS = deque(maxlen=20)


def _to_float_or_none(val):
    try:
        if val is None:
            return None
        return float(val)
    except (TypeError, ValueError):
        return None


def _normalize_metrics(raw_metrics):
    src = raw_metrics if isinstance(raw_metrics, dict) else {}

    cpu_percent = _to_float_or_none(src.get('cpu_percent'))
    ram_total_mb = _to_float_or_none(src.get('ram_total_mb') or src.get('memory_total_mb') or src.get('ram_total'))
    ram_used_mb = _to_float_or_none(src.get('ram_used_mb') or src.get('memory_used_mb') or src.get('ram_used'))
    ram_percent = _to_float_or_none(src.get('ram_percent') or src.get('memory_percent'))
    process_rss_mb = _to_float_or_none(src.get('process_rss_mb') or src.get('rss_mb'))

    gpu_alloc_mb = _to_float_or_none(src.get('gpu_mem_allocated_mb') or src.get('gpu_allocated_mb'))
    gpu_reserved_mb = _to_float_or_none(src.get('gpu_mem_reserved_mb') or src.get('gpu_reserved_mb') or src.get('gpu_total_mb'))
    gpu_count_raw = src.get('gpu_count', src.get('cuda_device_count'))
    try:
        gpu_count = int(gpu_count_raw) if gpu_count_raw is not None else 0
    except (TypeError, ValueError):
        gpu_count = 0

    if ram_percent is None and ram_total_mb and ram_total_mb > 0 and ram_used_mb is not None:
        ram_percent = max(0.0, min(100.0, ram_used_mb / ram_total_mb * 100.0))

    cuda_available = src.get('cuda_available')
    if cuda_available is None:
        cuda_available = bool(gpu_count > 0)

    if not cuda_available:
        gpu_count = 0

    return {
        'ts': src.get('ts'),
        'cpu_percent': cpu_percent,
        'ram_total_mb': ram_total_mb,
        'ram_used_mb': ram_used_mb,
        'ram_percent': ram_percent,
        'process_rss_mb': process_rss_mb,
        'cuda_available': bool(cuda_available),
        'gpu_count': gpu_count,
        'gpu_mem_allocated_mb': gpu_alloc_mb,
        'gpu_mem_reserved_mb': gpu_reserved_mb,
    }

def _encode_b64(img_bgr):
    ok, buffer = cv2.imencode('.png', img_bgr)
    if not ok:
        raise ValueError("Failed to encode image")
    return base64.b64encode(buffer).decode('utf-8')

def _remote_post(path, payload):
    if not REMOTE_INFER_URL:
        raise RuntimeError("REMOTE_INFER_URL not set")
    url = REMOTE_INFER_URL.rstrip("/") + path
    resp = requests.post(url, json=payload, timeout=REMOTE_TIMEOUT)
    resp.raise_for_status()
    return resp.json()

def _remote_get(path):
    if not REMOTE_INFER_URL:
        raise RuntimeError("REMOTE_INFER_URL not set")
    url = REMOTE_INFER_URL.rstrip("/") + path
    resp = requests.get(url, timeout=REMOTE_TIMEOUT)
    resp.raise_for_status()
    return resp.json()


def _push_status_error(message):
    _STATUS_ERRORS.append({
        'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'message': str(message)
    })


def _build_infer_response_format():
    return {
        'request': {
            'image_base64': 'base64 image string',
            'conf': 'optional float for /infer/l4l5'
        },
        'response': {
            'status': 'ok|error',
            'message': 'text',
            'image_base64': 'optional png base64',
            'image_mimetype': 'optional image/png',
            'extra': 'task-specific fields'
        }
    }

@app.after_request
def add_cache_headers(response):
    if request.path.startswith('/static/'):
        response.cache_control.max_age = 31536000
        response.cache_control.public = True
    return response


# @app.route('/api/report/spine_demo', methods=['GET'])
# def api_report_spine_demo():
#     """返回脊柱量化评分的示例 JSON，用于前端展示"""
#     report = {
#         'title': 'Spine Quantitative Report (Demo)',
#         'summary': '基于 UNetKeypoint 的关键点定位，用于 L4/L5/S1 的量化评分。L4/L5 可用于髂嵴线与三等分线交点评分。',
#         'metrics': {
#             'dataset': 'BUU Spine Dataset (3600 X-Ray)',
#             'mean_pixel_error_px': 4.61,
#             'notes': '在外部医院数据上，L4/L5 与 S1 定位可用，L3 以上误差较大。'
#         },
#         'images': [url_for('static', filename='img/j1.png'), url_for('static', filename='img/output.png')]
#     }
#     return jsonify(report), 200


# @app.route('/api/report/opll_demo', methods=['GET'])
# def api_report_opll_demo():
#     """返回 OPLL 分割报告示例"""
#     rpt = {
#         'title': 'OPLL Segmentation Report (Demo)',
#         'summary': '基于 2D UNet 的 OPLL 病灶分割，适配颈部 CT 矢状面。',
#         'metrics': {
#             'dataset': 'Shanghai Changzheng Hospital (223 CT cases)',
#             'avg_dice': 70.30,
#             'avg_iou': 54.68,
#             'inference_time_sec': 0.5
#         },
#         'images': [url_for('static', filename='img/output.png')]
#     }
#     return jsonify(rpt), 200

@app.route('/')
def index():
    """主页：展示 OPLL 与 L4L5 Locator 的前端说明与占位图"""
    return render_template('index.html')

@app.route('/api/opll', methods=['POST'])
def api_opll():
    """OPLL分割API"""
    if run_pipeline is None and not REMOTE_INFER_URL:
        return jsonify({'status': 'error', 'message': 'Inference module not loaded'}), 500
    
    img = None
    use_example = request.form.get('use_example')
    if use_example:
        try:
            example_id = int(use_example)
            if 1 <= example_id <= 6:
                img_path = os.path.join(app.static_folder, 'img', 'testimg', 'opll', f'{example_id}.png')
                if os.path.exists(img_path):
                    img = cv2.imread(img_path)
                    if img is None:
                        return jsonify({'status': 'error', 'message': f'Failed to read example image {example_id}'}), 500
                else:
                    return jsonify({'status': 'error', 'message': 'Example image not found'}), 404
            else:
                return jsonify({'status': 'error', 'message': 'Invalid example ID (1-6)'}), 400
        except ValueError:
            return jsonify({'status': 'error', 'message': 'Invalid example ID format'}), 400
    
    if img is None:
        if 'file' not in request.files:
            return jsonify({'status': 'error', 'message': 'No file part'}), 400
        file = request.files['file']
        if file.filename == '':
            return jsonify({'status': 'error', 'message': 'No selected file'}), 400
        try:
            filestr = file.read()
            npimg = np.frombuffer(filestr, np.uint8)
            img = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
            if img is None:
                return jsonify({'status': 'error', 'message': 'Failed to decode image'}), 400
        except Exception as e:
            return jsonify({'status': 'error', 'message': f"Image read error: {e}"}), 400
    
    try:
        if REMOTE_INFER_URL:
            payload = {'image_base64': _encode_b64(img)}
            remote_res = _remote_post('/infer/opll', payload)
            return jsonify(remote_res), 200
        from detect_api_v3 import run_opll_pipeline
        res = run_opll_pipeline(img, return_debug_image=True)
        result_bgr = res['debug_image']
        _, buffer = cv2.imencode('.png', result_bgr)
        result_b64 = base64.b64encode(buffer).decode('utf-8')
        return jsonify({
            'status': 'ok',
            'message': 'Success',
            'image_base64': result_b64,
            'image_mimetype': 'image/png'
        }), 200
    except Exception as e:
        print(f"OPLL inference error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/l4l5locator', methods=['POST'])
def api_l4l5locator():
    """L4/L5 Locator API: Receives an image, runs inference, returns processed image."""
    if run_pipeline is None and not REMOTE_INFER_URL:
        return jsonify({'status': 'error', 'message': 'Inference module not loaded'}), 500

    # Get Confidence Threshold
    try:
        conf_thr = float(request.form.get('conf', 0.3))
    except ValueError:
        conf_thr = 0.3

    img = None
    
    # Check if using example image
    use_example = request.form.get('use_example')
    if use_example:
        try:
            example_id = int(use_example)
            if 1 <= example_id <= 6:
                # Path to example image
                img_path = os.path.join(app.static_folder, 'img', 'testimg', f'{example_id}.png')
                if os.path.exists(img_path):
                    img = cv2.imread(img_path)
                    if img is None:
                         return jsonify({'status': 'error', 'message': f'Failed to read example image {example_id}'}), 500
                else:
                    return jsonify({'status': 'error', 'message': 'Example image not found'}), 404
            else:
                 return jsonify({'status': 'error', 'message': 'Invalid example ID (1-6)'}), 400
        except ValueError:
             return jsonify({'status': 'error', 'message': 'Invalid example ID format'}), 400

    # If no example loaded, check uploaded file
    if img is None:
        if 'file' not in request.files:
            return jsonify({'status': 'error', 'message': 'No file part'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'status': 'error', 'message': 'No selected file'}), 400

        try:
            # Read image from upload
            filestr = file.read()
            npimg = np.frombuffer(filestr, np.uint8)
            img = cv2.imdecode(npimg, cv2.IMREAD_COLOR)

            if img is None:
                 return jsonify({'status': 'error', 'message': 'Failed to decode image'}), 400
        except Exception as e:
             return jsonify({'status': 'error', 'message': f"Image read error: {e}"}), 400

    try:
        if REMOTE_INFER_URL:
            payload = {'image_base64': _encode_b64(img), 'conf': conf_thr}
            remote_res = _remote_post('/infer/l4l5', payload)
            return jsonify(remote_res), 200
        # Run inference (v3 pipeline)
        res = run_pipeline(img, return_debug_image=True)
        result_bgr = res['debug_image']
        
        # Encode result back to image for client
        _, buffer = cv2.imencode('.png', result_bgr)
        result_b64 = base64.b64encode(buffer).decode('utf-8')
        
        return jsonify({
            'status': 'ok',
            'message': 'Success',
            'image_base64': result_b64,
            'image_mimetype': 'image/png',
            'score': res.get('score', 0),
            'cobb_deg': res.get('cobb_deg', 0),
            'curvature_deg': res.get('curvature_deg', 0),
            'curvature_per_seg': res.get('curvature_per_seg', 0),
            'vertebrae': res.get('vertebrae', {}),
            'spine_midpoints': res.get('spine_midpoints', []),
            'cobb_l2_line': res.get('cobb_l2_line'),
            'cobb_s1_line': res.get('cobb_s1_line'),
            'peak_y': res.get('peak_y')
        }), 200

    except Exception as e:
        print(f"Inference error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/api/remote_metrics', methods=['GET'])
def api_remote_metrics():
    """Proxy remote machine metrics for UI/monitoring."""
    if not REMOTE_INFER_URL:
        return jsonify({'status': 'error', 'message': 'REMOTE_INFER_URL not set', 'metrics': _normalize_metrics({})}), 400
    try:
        metrics = _normalize_metrics(_remote_get('/metrics'))
        return jsonify({'status': 'ok', 'metrics': metrics}), 200
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e), 'metrics': _normalize_metrics({})}), 500


@app.route('/api/system/status', methods=['GET'])
def api_system_status():
    """System status API for frontend performance monitor panel."""
    if not REMOTE_INFER_URL:
        return jsonify({
            'ok': True,
            'data': {
                'inference_server': {
                    'status': 'offline',
                    'message': 'REMOTE_INFER_URL not set',
                    'queue_length': 0,
                    'recent_latency_ms': None,
                    'error_rate': 100.0,
                    'recent_errors': list(_STATUS_ERRORS),
                    'metrics': {},
                    'infer_response_format': _build_infer_response_format()
                }
            }
        }), 200

    try:
        t0 = time.perf_counter()
        _ = _remote_get('/health')
        metrics = _normalize_metrics(_remote_get('/metrics'))
        latency_ms = (time.perf_counter() - t0) * 1000.0
        _LATENCY_HISTORY_MS.append(latency_ms)

        return jsonify({
            'ok': True,
            'data': {
                'inference_server': {
                    'status': 'online',
                    'message': 'remote inference server reachable',
                    'queue_length': 0,
                    'recent_latency_ms': round(latency_ms, 2),
                    'error_rate': 0.0,
                    'recent_errors': list(_STATUS_ERRORS),
                    'metrics': metrics,
                    'infer_response_format': _build_infer_response_format()
                }
            }
        }), 200
    except Exception as e:
        _push_status_error(e)
        return jsonify({
            'ok': True,
            'data': {
                'inference_server': {
                    'status': 'offline',
                    'message': str(e),
                    'queue_length': 0,
                    'recent_latency_ms': None,
                    'error_rate': 100.0,
                    'recent_errors': list(_STATUS_ERRORS),
                    'metrics': {},
                    'infer_response_format': _build_infer_response_format()
                }
            }
        }), 200


# @app.route('/api/l4l5locator/demo', methods=['GET'])
# def api_l4l5locator_demo():
#     """演示 API：返回一个示例定位结果与示意图 URL（前端用于演示）"""
#     # 示例关键点（x,y）为像素坐标，示例用于 UI 展示
#     demo_kpts = {
#         'l4': [[120, 220], [180, 220], [180, 180], [120, 180]],
#         'l5': [[140, 280], [200, 280], [200, 240], [140, 240]]
#     }
#     # 返回静态文件 URL 方便前端直接加载
#     try:
#         img_url = url_for('static', filename='img/l4l5_demo_result.svg')
#     except Exception:
#         img_url = '/static/img/l4l5_demo_result.svg'

#     return jsonify({'status':'ok', 'message':'demo result', 'result_image': img_url, 'keypoints': demo_kpts}), 200


@app.route('/api/spine_analysis', methods=['POST'])
def api_spine_analysis():
    """脊柱形态AI分析API：接收检测结果，返回流式AI分析"""
    if client is None:
        return jsonify({'status': 'error', 'message': 'AI client not initialized'}), 500
    
    try:
        data = request.get_json()
        score = data.get('score', 0)
        cobb_deg = data.get('cobb_deg', 0)
        curvature_deg = data.get('curvature_deg', 0)
        curvature_per_seg = data.get('curvature_per_seg', 0)
        conversation = data.get('conversation', [])
        
        # 从检测结果中提取结构化数据
        vertebrae = data.get('vertebrae', {})
        spine_midpoints = data.get('spine_midpoints', [])
        cobb_l2_line = data.get('cobb_l2_line')
        cobb_s1_line = data.get('cobb_s1_line')
        peak_y = data.get('peak_y')
        
        system_prompt = """
你是一个专注于脊柱矢状面形态评估的医学影像分析助手。
你的任务是基于定量指标对腰椎形态及相关风险进行解释性评估，而不是给出确诊结论。

一、你将接收的输入指标包括（可能部分缺失）：

1) L2–S1 Cobb 角（cobb_deg，单位：°）

定义：L2 上终板方向 与 S1 上终板方向的夹角（取锐角 0–90°）。

量化分级（用于"曲度大小"）：
- < 30°：前凸偏小 / 偏直倾向
- 30°–55°：常见正常范围
- > 55°：前凸偏大（需结合评分与曲率判断风险方向）

注：这是 L2–S1 段的经验分级；若换成 L1–S1 阈值会略偏大。

2) 髂脊线与 L4/L5 交点分数（score，范围：-2 到 +2）

定义：髂脊线（HED 检出线的最高点 y 对应的水平线）与 L4、L5 右缘三等分交点落点转成分数并累加得到总分（分数由外部/代码传入）。

量化解释（用于"力学位置风险方向"）：
- -2：结构位置异常，易发生腰椎退变性疾病倾向
- -1 ~ +1：最适区间（推荐目标）
- +2：结构负荷异常，腰痛易发倾向

你只要保证最终对外输出的总分就是 [-2, +2]，模型解释就不会跑偏。

3) 中轴折转总角度（curvature_deg，单位：°）

定义：由 S1 与 L5–L1 中点组成中轴点序列 → 平滑 → 相邻切线夹角求和（单段角度上限 60°）。本质是 Total Turning Angle（总转角），用于衡量整体弯曲"总量"和是否分段折转。

量化分级（用于"平滑性/折转多寡"）：
- < 15°：偏直 / 曲度不足（或过度平滑）
- 15°–35°：平滑理想（形态连续）
- 35°–60°：弯曲偏大或轻度不平滑
- > 60°：明显不平滑 / 折转多（也需要警惕关键点噪声或漏检）

4) 归一化折转强度（turn_deg_per_seg，单位：°/seg）

定义：为降低点数/覆盖段长度影响，对总转角做段数归一化：
turn_deg_per_seg = curvature_deg / max(1, N-2)
其中 N 是中轴点数（通常 N≈6，N-2≈4）。

量化分级（更推荐用于跨样本对比）：
- < 4 °/seg：偏直 / 低弯曲
- 4–8 °/seg：平滑理想
- 8–12 °/seg：偏弯或轻度不平滑
- > 12 °/seg：明显不平滑 / 局部折转多

二、组合使用建议

- Cobb 看"曲度大小"（小/正常/偏大）
- score 看"风险方向"（退变倾向 vs 腰痛倾向，最适 -1~1）
- curvature_deg / turn_deg_per_seg 看"是否平滑、是否多段折转"（越大越不平滑）

三、评估原则（必须遵守）

- Cobb 角只用于评估"弯曲程度"，不用于评估姿态
- 不允许将 Cobb 角与垂直或水平角度混用
- score 用于评估"力学位置与风险倾向"
- 若多个指标出现矛盾，需要如实指出，并进行综合解释
- 不进行疾病诊断，只允许使用："偏高 / 偏低 / 正常范围 / 风险倾向 / 可能相关"
- 禁止使用"确诊、必然、一定患病"等措辞

四、综合分析输出结构（必须按此顺序）

你的回答应包含以下四个部分：

 - 指标概述
   - 简要复述输入的 Cobb 角、交点评分、总曲率、归一化曲率

 - 单项指标解读
   - Cobb 角：前凸程度评价（偏小/正常/偏大）
   - 交点评分：结构力学风险方向（退变/平衡/腰痛倾向）
   - 总曲率与归一化曲率：脊柱中轴线弯曲程度与平滑性评估
     * 说明曲率数值的临床意义
     * 判断是否存在局部折角、侧弯或椎体排列异常
     * 结合 Cobb 角分析前凸与整体曲线的一致性

 - 综合判断
   - 指出各指标是否一致（Cobb 角、交点评分、曲率三者的相互印证）
   - 若存在潜在风险，说明风险类型：
     * 退变倾向：交点评分 -2，可能伴随曲率异常
     * 腰痛倾向：交点评分 +2，应力集中
     * 脊柱不稳/侧弯：归一化曲率 > 12°/seg 且与 Cobb 角不匹配
     * 结构平衡良好：三项指标均在正常范围

 - 总结性结论（非诊断）
   - 使用"整体来看""从结构形态角度""提示可能存在"等表述
   - 强调这是基于影像几何指标的分析结果
   - 强调可能出现的风险倾向，提供参考意见

五、示例总结语气（供你模仿）

"从几何结构角度看，该腰椎前凸程度处于正常偏高范围，结合交点评分提示负荷分布略偏向腰痛风险方向。"
"尽管 Cobb 角显示腰椎曲度尚可，但 L4/L5 与髂脊线关系偏离理想区间，提示潜在的结构不平衡。"
"归一化曲率达 13°/seg，明显超出正常范围，提示存在局部折角或侧弯倾向，建议结合临床症状进一步评估椎体稳定性。"
"总曲率 22° 且归一化曲率 5.5°/seg，两者均在正常范围，脊柱排列规整，生理曲度保持良好。"

你应始终保持专业、克制、结构化的分析风格，重点放在量化指标的解读与整合上。
**必须对曲率指标进行详细解读**，说明其计算原理和病理意义。
分析结果要包括根据指标评判的比较口述的关于患病可能性的结论，特别关注曲率异常时的风险提示。
"""
        
        messages = [{"role": "system", "content": system_prompt}]
        
        # 构建包含结构化数据的用户消息
        data_summary = {
            'score': score,
            'cobb_deg': cobb_deg,
            'curvature_deg': curvature_deg,
            'curvature_per_seg': curvature_per_seg,
            'peak_y': peak_y,
            'vertebrae': vertebrae,
            'spine_midpoints': spine_midpoints,
            'cobb_l2_line': cobb_l2_line,
            'cobb_s1_line': cobb_s1_line
        }
        
        print(f"[DEBUG] Sending to AI - Score: {score}, Cobb: {cobb_deg}, Vertebrae keys: {list(vertebrae.keys()) if vertebrae else 'None'}")
        
        if not conversation:
            user_content = f"""检测结果数据：
{json.dumps(data_summary, ensure_ascii=False, indent=2)}

请基于以上数据进行分析。主要指标：Score: {score:+d}， L2-S1 Cobb: {cobb_deg:.1f}deg， Curvature: {curvature_deg:.2f}deg， Curvature/seg: {curvature_per_seg:.2f}deg/seg"""
            messages.append({"role": "user", "content": user_content})
        else:
            initial_content = f"""检测结果数据：
{json.dumps(data_summary, ensure_ascii=False, indent=2)}

请基于以上数据进行分析。主要指标：Score: {score:+d}， L2-S1 Cobb: {cobb_deg:.1f}deg， Curvature: {curvature_deg:.2f}deg， Curvature/seg: {curvature_per_seg:.2f}deg/seg"""
            messages.append({"role": "user", "content": initial_content})
            messages.extend(conversation)
        
        def generate():
            try:
                completion = client.chat.completions.create(
                    model="step-1-8k",
                    messages=messages,
                    stream=True
                )
                
                for chunk in completion:
                    if chunk.choices[0].delta.content:
                        yield f"data: {json.dumps({'content': chunk.choices[0].delta.content}, ensure_ascii=False)}\n\n"
                
                yield "data: [DONE]\n\n"
            except Exception as e:
                yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"
        
        return Response(stream_with_context(generate()), mimetype='text/event-stream')
    
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
