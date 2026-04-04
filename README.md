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

## 患者/共享入口

- 患者登记：`/register/<register_token>`
- 患者查看随访：`/patient/<access_key>`
- 同事共享阅片：`/shared/<share_token>`

## 关键 API（新增）

- `GET /api/status`
- `POST /api/patients/<id>/portal-link`
- `PATCH /api/patients/<id>`
- `GET|POST /api/tasks`
- `PATCH|DELETE /api/tasks/<id>`
- `DELETE /api/exams/<id>`
- `POST /api/exams/<id>/manual-result`
- `GET|POST /api/exams/<id>/annotations`
- `PATCH|DELETE /api/annotations/<id>`
- `POST /api/exams/<id>/share`
- `GET /api/shared/exams/<token>`
- `GET|POST /api/public/register/<token>`
- `GET /api/public/patient/<access_key>`
- `POST /api/public/patient/<access_key>/exams`

## 运行

```powershell
pip install -r requirements.txt
python app.py
```

访问：`http://127.0.0.1:5000`

默认账号：

- `admin / admin123`
- `doctor1 / doctor123`

## 环境变量

- `SPINE_REMOTE_INFER_URL`：远程推理服务地址
- `SPINE_REMOTE_TIMEOUT`：推理超时（秒）
- `SPINE_LOW_CONF`：低置信度阈值
- `SPINE_IMPROVE_DELTA`：改善阈值（Cobb 角）
- `SPINE_WORSEN_DELTA`：恶化阈值（Cobb 角）
- `SPINE_COBB_ALERT`：高风险 Cobb 提示阈值

