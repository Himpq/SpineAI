# Spine FUPT (Flask SPA)

面向脊柱随访场景的简洁医疗后台，支持医生端、患者端和共享阅片链接。

## 核心流程

1. 医生建档患者（手机号/邮箱可先登记）
2. 医生一键生成患者登记 URL/二维码
3. 患者通过登记链接补充个人信息
4. 患者或医生上传 X 光，后台调用远程 AI 推理
5. 医生在复核页查看影像、添加标注、保存复核意见
6. 医生可一键生成共享 URL/二维码给同事查看（含标注/复核信息）
7. 医生可安排复查日程，首页展示日历和任务列表

## 主要页面

- `随访总览`：任务、复核队列、近 14 天日程
- `患者管理`：建档、登记链接、任务安排、随访时间线
- `检查复核`：影像复核、标注、共享、手动登记、删除随访数据
- `状态`：远程推理服务与系统状态
- `用户与权限`：管理员账号管理

## 运行

```powershell
pip install -r requirements.txt
python app.py
```

访问地址由 [config.json](config.json) 里的 `APP_HOST` / `APP_PORT` 决定。

默认账号来自 [config.json](config.json)：

- `admin / admin123`
- `doctor1 / doctor123`

## 配置

- 运行配置放在 [config.json](config.json)，不再从环境变量读取这些参数。
- 远程推理地址、超时、StepFun 配置、匿名推理限制、管理员账号都可以直接在 JSON 里改。
- 如果你要迁移到新机器，先改 [config.json](config.json)，再启动 `app.py`。

