# Web 演示（OPLL & L4/L5 Locator）

快速说明：
- 该目录提供一个最小的 Flask 前端页面，用于展示两个模块（OPLL segmentation 与 L4/L5 Locator）的介绍和占位图片。
- 当前后端接口为占位（返回 501），前端已预留调用按钮与显示区，后续可以把模型推理逻辑接入 `/api/opll` 与 `/api/l4l5locator`。

运行（推荐虚拟环境）：
1. 安装依赖：

```bash
pip install -r requirements.txt
```

2. 运行：

```bash
python app.py
# 或者
# set FLASK_APP=app.py
# flask run --host=0.0.0.0 --port=5000
```

3. 打开浏览器访问：http://127.0.0.1:5000

开发说明：
- 演示接口：`/api/l4l5locator/demo` 返回示例 JSON 与示意图（仅用于前端演示）。
- 报告演示接口：`/api/report/spine_demo` 与 `/api/report/opll_demo` 返回示例量化报告 JSON 与示例图像。
- 模型推理接口：编辑 `app.py`，在 `/api/opll` 与 `/api/l4l5locator` 添加实现。
- 前端模板：`templates/index.html`；静态资源：`static/`
