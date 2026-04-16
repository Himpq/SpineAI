## spine.healthit.cn

这是这个站点的前端和反向代理入口。

## 页面

- `https://spine.healthit.cn/app`：APP 介绍页面
- `https://spine.healthit.cn/fupt`：随访页面

## 配置

- 主配置在 [config.json](config.json)，启动地址、转发地址、模型路径、默认阈值都从这里读取。
- 如果你要在新机器上部署，可以把外部配置文件路径通过 `SPINE_HEALTHIT_CONFIG` 指到任意位置。
- `STEPFUN_API_KEY` 仍然通过环境变量读取，不放进配置文件。
- `app-副本.py` 是旧备份入口，不建议作为部署入口。

## 部署顺序

1. 准备 Python 环境并安装 `requirements.txt`。
2. 准备本地模型文件和依赖目录，至少保证 `weights/` 和 `../Thyroid` 路径可用，或者在 [config.json](config.json) 里改成新的实际路径。
3. 按新环境修改 [config.json](config.json) 里的 `remote_infer_url`、`fupt_proxy_url`、端口和模型文件名。
4. 设置 `STEPFUN_API_KEY`，如果外部推理服务地址不同，也一起改 [config.json](config.json) 里的对应项。
5. 先启动远端推理服务，再启动 `python app.py`。
6. 用 nginx 或其他反向代理把域名指向 `app.py` 监听的端口，`/fupt` 继续代理到随访服务。

## 说明

- `/fupt` 会转发到配置里的 SpineFUPT 后端。
- 页面里的 `/api`、`/static`、`/ws` 会按代理前缀自动重写。
