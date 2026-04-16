# remoteInferer

这是独立的推理后端，和 `spine.healthit.cn` 分开。

## 运行

1. 安装依赖。

```bash
pip install -r requirements.txt
```

2. 启动推理服务。

```bash
python remote_infer_server.py
```

## 配置

- 所有运行时配置都放在 [config.json](config.json)。
- 这里不再提供 `app.py` 前端壳，也不再使用环境变量作为配置来源。
- 模型路径、推理端口、默认阈值、权重目录都可以直接在 JSON 里改。

## 保留文件

- [remote_infer_server.py](remote_infer_server.py)：主推理 API。
- [detect_api_v3.py](detect_api_v3.py)：当前主线推理管线。
- [detect_api_tansit.py](detect_api_tansit.py)：颈椎侧位关键点管线。
- [classify.py](classify.py)：分类器与推理模型定义。
- [settings.py](settings.py)：JSON 配置读取工具。
- [config.json](config.json)：运行配置。

## 已删除的旧内容

- `app.py` 前端壳已删除。
- `detect_api.py` 和 `detect_api_v2.py` 已删除。
- `static/` 和 `templates/` 前端资源已删除。
