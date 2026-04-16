# SpineAI
Private Healthcare Project, Spine Diagnosis

## 本次大版本更新

这次更新把项目从“混合在一起的脚本堆”整理成了更清晰的几个服务，并把运行配置统一收敛到 JSON：

- `remoteInferer` 现在是独立的纯推理后端，已删除前端壳、静态资源、模板和旧版重复检测脚本，运行参数改为 `config.json` 管理。
- `Spine_FUPT` 改成 JSON 配置驱动，启动端口、远程推理地址、StepFun、阈值和管理员初始化都不再依赖环境变量；同时移除了不再使用的 `sample/`。
- `spine.healthit.cn` 也完成了配置抽离，入口、转发地址和推理地址可以直接通过 `config.json` 调整，适合新部署。
- 修复了旧模型 checkpoint 在新 PyTorch 环境下的加载问题，兼容带有 `WindowsPath` 的历史权重文件。
- 子项目文档已经同步整理，具体运行方式和配置项分别放在各自目录下的 README 中维护。

## 当前目录

- [remoteInferer](remoteInferer/README.md)：独立推理后端
- [Spine_FUPT](Spine_FUPT/README.md)：随访后台
- [spine.healthit.cn](spine.healthit.cn/README.md)：站点入口与反向代理

## 部署提示

如果要重新部署，优先查看对应目录下的 [config.json](Spine_FUPT/config.json)、[config.json](remoteInferer/config.json) 和各自的 README，不需要再从环境变量里找运行参数。
