# 脊柱AI影像随访系统 — API 参考文档

> 自动生成自 `app.py`，共 68 个路由  
> 后端框架：Flask 3.1 · 数据库：SQLite · 认证方式：Session Cookie

---

## 目录

1. [通用约定](#1-通用约定)
2. [认证 Auth](#2-认证-auth)
3. [总览 Overview](#3-总览-overview)
4. [日志 Logs](#4-日志-logs)
5. [随访日程 Schedules](#5-随访日程-schedules)
6. [患者 Patients](#6-患者-patients)
7. [患者登记 Registration](#7-患者登记-registration)
8. [影像上传 Exam Upload](#8-影像上传-exam-upload)
9. [复核 Reviews](#9-复核-reviews)
10. [病例分享 Case Sharing](#10-病例分享-case-sharing)
11. [聊天 Chat](#11-聊天-chat)
12. [问卷 Questionnaires](#12-问卷-questionnaires)
13. [患者门户 Portal（公开）](#13-患者门户-portal公开)
14. [公开问卷 Public Questionnaire](#14-公开问卷-public-questionnaire)
15. [公开病例 Public Case](#15-公开病例-public-case)
16. [公开登记 Public Register](#16-公开登记-public-register)
17. [系统管理 System](#17-系统管理-system)
18. [数据模型](#18-数据模型)

---

## 1. 通用约定

### 基础 URL

```
http://<host>:5000
```

### 认证

所有 `/api/` 路由（除 `/api/public/*` 和 `/api/auth/login`）需要有效 Session Cookie。  
登录后服务端通过 `Set-Cookie` 下发 session，有效期 30 天。

### 成功响应格式

```json
{
  "ok": true,
  "message": "ok",
  "data": { ... }
}
```

### 错误响应格式

```json
{
  "ok": false,
  "error": {
    "code": "bad_request",
    "message": "错误描述",
    "details": null
  }
}
```

常见 HTTP 状态码：`400` 参数错误 · `401` 未认证 · `403` 无权限 · `404` 资源不存在

### 通用查询参数（分页）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `page` | int | 1 | 页码（≥1） |
| `per_page` | int | 20 | 每页条数（1-100） |

分页响应统一包含 `total`、`page`、`per_page`、`has_more` 字段。

### 时间格式

所有时间字段为 ISO 8601 UTC：`2026-03-20T08:30:00Z`

---

## 2. 认证 Auth

### GET `/api/auth/session`

检查当前会话状态。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `authenticated` | bool | 是否已登录 |
| `user` | User? | 用户信息（仅已登录时） |
| `modules` | string[]? | 已授权模块列表 |

---

### POST `/api/auth/login`

用户登录。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `username` | ✅ | string | 用户名（不区分大小写） |
| `password` | ✅ | string | 密码 |

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `user` | User | 用户信息 |
| `modules` | string[] | 已授权模块列表 |

**错误码：** `login_failed`（账号或密码错误） · `disabled`（账号已被禁用）

---

### POST `/api/auth/logout`

退出登录，清除 session。

**响应：** `{ "message": "已退出" }`

---

## 3. 总览 Overview

### GET `/api/overview`

🔒 需登录 · 需 `overview` 模块权限

获取仪表板数据。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `stats.patient_total` | int | 患者总数 |
| `stats.pending_reviews` | int | 待复核数 |
| `stats.unread_messages` | int | 未读消息数 |
| `stats.today_schedules` | int | 今日待办日程数 |
| `stats.alerts` | int | 预警数（重度/Cobb角超阈值） |
| `stats.inference_server` | string | 推理服务器状态 |
| `feed` | Event[] | 最近 60 条工作事件 |
| `schedules` | Schedule[] | 待办日程列表（最多 50 条） |

---

## 4. 日志 Logs

### GET `/api/logs`

🔒 需登录

获取工作事件日志。非管理员仅可见自己关联的记录。

**查询参数：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `limit` | int | 120 | 返回条数（20-500） |

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `items` | LogItem[] | 日志条目列表 |

**LogItem 字段：** `id`, `event_type`, `title`, `message`, `level`, `patient_id`, `exam_id`, `created_at`, `uploader_name`, `owner_name`, `pic_name`, `preview_url`, `spine_class_text`, `confidence`

---

## 5. 随访日程 Schedules

### POST `/api/schedules`

🔒 需登录

创建随访日程。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `patient_id` | ✅ | int | 患者 ID |
| `title` | ✅ | string | 日程标题 |
| `scheduled_at` | ✅ | string | 日程时间（ISO 8601） |
| `note` | | string | 备注 |

**响应 data：** `{ "item": Schedule }`

---

## 6. 患者 Patients

### GET `/api/patients`

🔒 需登录 · 需 `followup` 模块权限

分页查询患者列表。

**查询参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `page` | int | 页码 |
| `per_page` | int | 每页条数 |
| `search` | string | 按姓名模糊搜索 |

**响应 data：** `{ "items": PatientRow[], "total", "page", "per_page", "has_more" }`

---

### POST `/api/patients`

🔒 需登录

创建患者。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `name` | ✅ | string | 姓名 |
| `age` | | int | 年龄 |
| `sex` | | string | 性别 |
| `phone` | | string | 手机号 |
| `email` | | string | 邮箱 |
| `note` | | string | 备注 |

**响应 data：** `{ "patient": PatientRow }`

---

### GET `/api/patients/<patient_id>`

🔒 需登录

获取患者详情（含检查列表、时间线、Cobb 角趋势）。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `patient` | PatientDetail | 患者详情 |
| `patient.note` | string? | 备注 |
| `patient.next_schedule` | Schedule? | 下次待办日程 |
| `patient.timeline` | Event[] | 时间线（最多 80 条） |
| `patient.trend` | `{date, cobb_angle}[]` | Cobb 角趋势数据 |
| `patient.exams` | ExamRow[] | 检查记录列表（倒序） |

---

### PATCH `/api/patients/<patient_id>`

🔒 需登录

更新患者信息。Body 中包含的字段会被更新。

**可更新字段：** `name`, `age`, `sex`, `phone`, `email`, `note`

**响应 data：** `{ "patient": PatientRow }`

---

### DELETE `/api/patients/<patient_id>`

🔒 需登录 · 需 `followup` 模块权限

删除患者及其所有关联数据（检查、会话、日程等）。

**响应：** `{ "message": "患者已删除" }`

---

## 7. 患者登记 Registration

### POST `/api/registration-sessions`

🔒 需登录

创建实时登记会话（用于扫码登记）。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `form_state` | | object | 初始表单数据 |

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `token` | string | 登记 token |
| `status` | string | 状态（`active` / `submitted`） |
| `form_state` | object | 表单数据 |
| `register_url` | string | 登记页面 URL |
| `qr_data_url` | string | 二维码（data URL） |
| `channel` | string | WebSocket 频道名 |

---

### GET `/api/registration-sessions/<token>`

获取登记会话状态（公开，无需认证）。

**响应 data：** `{ "token", "status", "focus_field", "form_state", "patient", "updated_at", "channel" }`

---

### POST `/api/registration-sessions/<token>/focus`

上报当前聚焦字段（用于实时协作）。

**请求 Body：** `{ "field": "name", "actor_name": "张三" }`

---

### POST `/api/registration-sessions/<token>/field`

更新单个表单字段值。

**请求 Body：** `{ "field": "name", "value": "李四", "actor_name": "张三" }`

---

### POST `/api/registration-sessions/<token>/submit`

提交登记表单，创建/更新患者记录。

**请求 Body：** `{ "form_state": {...}, "actor_name": "登记者" }`

**响应 data：** `{ "patient": PatientRow, "portal_url": string }`

---

## 8. 影像上传 Exam Upload

### POST `/api/patients/<patient_id>/exams`

🔒 需登录

医生端上传影像。

**请求：** `multipart/form-data`

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `file` | ✅ | File | 影像文件（.png/.jpg/.jpeg/.bmp/.webp，最大 64MB） |

**响应 data：** `{ "exam": ExamRow }`

上传后自动触发远程 AI 推理。

---

## 9. 复核 Reviews

### GET `/api/reviews`

🔒 需登录 · 需 `review` 模块权限

分页查询复核队列。非管理员仅可见自己负责的检查。

**查询参数：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `status` | string | `pending_review` | 筛选状态：`pending_review` / `reviewed` / `all` |
| `page` | int | 1 | 页码 |
| `per_page` | int | 20 | 每页条数 |

**响应 data：** `{ "items": ExamRow[], "total", "page", "per_page", "has_more" }`

---

### GET `/api/reviews/<exam_id>`

🔒 需登录

获取复核详情（含 AI 推理结果和评论）。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `exam` | ExamDetail | 检查详情 |
| `exam.comments` | Comment[] | 评论列表 |

---

### POST `/api/reviews/<exam_id>/review`

🔒 需登录

提交复核结果。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `decision` | | string | `reviewed`（默认）或其他值保持 pending |
| `note` | | string | 复核备注 |

**响应 data：** `{ "exam": ExamDetail }`

---

### DELETE `/api/reviews/<exam_id>`

🔒 需登录

删除检查记录及关联文件。

---

## 10. 病例分享 Case Sharing

### POST `/api/reviews/<exam_id>/share-link`

🔒 需登录

生成外部分享链接（含二维码）。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `link.id` | int | 分享链接 ID |
| `link.token` | string | 分享 token |
| `link.url` | string | 分享页面 URL |
| `link.qr_data_url` | string | 二维码（data URL） |
| `link.channel` | string | WebSocket 频道名 |
| `accesses` | AccessLog[] | 访问记录 |

---

### GET `/api/reviews/<exam_id>/share-accesses`

🔒 需登录

获取分享链接的访问记录。

**响应 data：** `{ "items": AccessLog[], "channel": string }`

**AccessLog 字段：** `id`, `access_ip`, `viewer_label`, `user_agent`, `accessed_at`

---

### GET `/api/reviews/<exam_id>/comments`

🔒 需登录

获取检查评论列表。

**响应 data：** `{ "items": Comment[], "channel": string }`

---

### POST `/api/reviews/<exam_id>/comments`

🔒 需登录

添加评论。

**请求 Body：** `{ "content": "评论内容" }`

**响应 data：** `{ "comment": Comment }`

---

### POST `/api/reviews/<exam_id>/share-user`

🔒 需登录

站内分享病例给其他用户（自动创建私聊消息）。

**请求 Body：** `{ "user_id": 2 }`

**响应 data：** `{ "conversation_id": int }`

---

### GET `/api/users/share-targets`

🔒 需登录

获取可分享的用户列表（按最近互动排序）。

**查询参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `query` | string | 按姓名/用户名搜索 |

**响应 data：** `{ "items": ShareTarget[] }`

**ShareTarget 字段：** `id`, `username`, `display_name`, `role`, `last_interaction`

---

## 11. 聊天 Chat

### GET `/api/chat/users`

🔒 需登录

搜索可发起聊天的用户。

**查询参数：** `query`（搜索关键字）

**响应 data：** `{ "items": [{id, display_name, username, role}] }`

---

### GET `/api/chat/conversations`

🔒 需登录 · 需 `chat` 模块权限

获取会话列表。

**响应 data：** `{ "items": Conversation[], "total", "page", "per_page", "has_more" }`

---

### POST `/api/chat/conversations`

🔒 需登录

创建会话。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `type` | | string | `private`（默认）/ `group` / `patient` |
| `target_user_id` | ✅* | int | 私聊目标用户 ID（type=private） |
| `name` | ✅* | string | 群名称（type=group） |
| `member_user_ids` | | int[] | 群成员 ID 列表（type=group） |
| `patient_id` | ✅* | int | 患者 ID（type=patient） |

**响应 data：** `{ "conversation": Conversation }`

---

### GET `/api/chat/conversations/<conversation_id>/messages`

🔒 需登录

获取消息列表（支持游标分页）。

**查询参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `limit` | int | 返回条数（1-300，默认 50） |
| `before_id` | int | 返回此 ID 之前的消息（游标） |

**响应 data：** `{ "items": Message[], "channel": string, "has_more": bool }`

---

### POST `/api/chat/conversations/<conversation_id>/messages`

🔒 需登录

发送消息。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `content` | ✅ | string | 消息内容 |
| `message_type` | | string | 消息类型（默认 `text`） |
| `payload` | | object | 附加数据 |

**响应 data：** `{ "message": Message }`

---

### POST `/api/chat/conversations/<conversation_id>/read`

🔒 需登录

标记会话已读。

---

## 12. 问卷 Questionnaires

### GET `/api/questionnaires`

🔒 需登录 · 需 `questionnaire` 模块权限

获取问卷列表。

**响应 data：** `{ "items": Questionnaire[] }`

---

### POST `/api/questionnaires`

🔒 需登录

创建问卷。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `title` | ✅ | string | 问卷标题 |
| `description` | | string | 描述 |
| `allow_non_patient` | | bool | 是否允许非患者填写 |
| `open_from` | | string | 开放开始时间（ISO 8601） |
| `open_until` | | string | 开放结束时间 |
| `questions` | ✅ | Question[] | 题目列表 |

**Question 对象：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `q_type` | ✅ | string | 题型：`single` / `multi` / `choice` / `text` / `blank` |
| `title` | ✅ | string | 题目标题 |
| `options` | | array | 选项列表（选择题必填） |

**响应 data：** `{ "questionnaire": Questionnaire }`

---

### GET `/api/questionnaires/<qid>`

🔒 需登录

获取问卷详情（含题目、统计、回收情况）。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `questionnaire` | object | 问卷信息 |
| `questionnaire.questions` | Question[] | 题目列表 |
| `questionnaire.stats` | QuestionStat[] | 各题统计分布 |
| `questionnaire.completed_count` | int | 已完成数 |
| `questionnaire.pending_count` | int | 待完成数 |

---

### PUT `/api/questionnaires/<qid>`

🔒 需登录

全量更新问卷（无回收记录时可用）。

请求格式同创建。若已有回收记录，返回错误提示使用安全编辑接口。

---

### PATCH `/api/questionnaires/<qid>/safe-edit`

🔒 需登录

安全编辑问卷（有回收记录时使用）。仅可修改已有题目的标题/选项，不可新增/更改已答题目的题型。

---

### DELETE `/api/questionnaires/<qid>`

🔒 需登录

删除问卷及所有回收记录。

---

### POST `/api/questionnaires/<qid>/stop`

🔒 需登录

终止问卷收集。

---

### POST `/api/questionnaires/<qid>/assign`

🔒 需登录

向患者分配问卷（自动通过聊天推送链接）。

**请求 Body：** `{ "patient_ids": [1, 2, 3] }`

**响应 data：**

```json
{
  "assignments": [
    {
      "id": 1,
      "patient_id": 1,
      "patient_name": "张三",
      "token": "qa_xxx",
      "url": "http://host/q/qa_xxx",
      "status": "pending"
    }
  ]
}
```

---

### GET `/api/questionnaires/<qid>/responses`

🔒 需登录

获取问卷回收列表和统计。

**响应 data：** `{ "stats": QuestionStat[], "responses": ResponseRow[] }`

---

### GET `/api/questionnaires/<qid>/responses/<rid>`

🔒 需登录

获取单份回答详情。

**响应 data：**

```json
{
  "response": {
    "id": 1,
    "submitted_at": "...",
    "responder_name": "张三",
    "responder_ip": "...",
    "answers": [
      {
        "question_id": 1,
        "question_title": "...",
        "q_type": "single",
        "answer": "选项A"
      }
    ]
  }
}
```

---

### DELETE `/api/questionnaires/<qid>/responses/<rid>`

🔒 需登录

删除单份填写记录。

---

## 13. 患者门户 Portal（公开）

以下接口通过患者 `portal_token` 访问，无需登录。

### GET `/api/public/portal/<token>`

获取患者门户首页数据。

**响应 data：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `patient` | object | `{id, name, age, sex}` |
| `uploads` | PortalExam[] | 影像列表（最多 60 条） |
| `timeline` | Event[] | 时间线（最多 80 条） |
| `assignments` | Assignment[] | 问卷任务列表 |

---

### GET `/api/public/portal/<token>/chat`

获取患者端聊天数据。

**响应 data：** `{ "conversation", "contacts", "messages", "patient_name" }`

---

### POST `/api/public/portal/<token>/messages`

患者发送聊天消息。

**请求 Body：** `{ "content": "消息内容", "sender_name": "张三" }`

**响应 data：** `{ "message": Message }`

---

### POST `/api/public/portal/<token>/exams`

患者上传影像。

**请求：** `multipart/form-data`

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `file` | ✅ | File | 影像文件 |
| `sender_name` | | string | 上传者名称 |

**响应 data：** `{ "exam": ExamRow }`

---

### DELETE `/api/public/portal/<token>/exams/<exam_id>`

患者删除自己上传的未复核影像。

---

## 14. 公开问卷 Public Questionnaire

### GET `/api/public/questionnaires/<token>`

通过分配 token 获取问卷数据。

**响应 data：** `{ "assignment": {...}, "questionnaire": {...} }`

---

### POST `/api/public/questionnaires/<token>/submit`

提交问卷回答。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `answers` | ✅ | object | `{ "<question_id>": answer_value, ... }` |
| `responder_name` | | string | 填写者姓名 |
| `responder_cookie_id` | | string | 设备标识（防重复提交） |
| `patient_cookie_token` | | string | 患者 token（用于身份验证） |

---

## 15. 公开病例 Public Case

### GET `/api/public/case/<token>`

通过分享 token 获取病例详情。

**响应 data：** `{ "exam": ExamDetail }`（含 `comments`）

---

### POST `/api/public/case/<token>/comments`

访客添加评论。

**请求 Body：** `{ "content": "评论内容", "author_name": "访客" }`

---

## 16. 公开登记 Public Register

以下为 `/api/registration-sessions/*` 的公开别名，功能相同：

| 路由 | 对应 |
|------|------|
| `GET /api/public/register/<token>` | 获取登记会话 |
| `POST /api/public/register/<token>/focus` | 上报聚焦字段 |
| `POST /api/public/register/<token>/field` | 更新单字段 |
| `POST /api/public/register/<token>/submit` | 提交登记 |

---

## 17. 系统管理 System

### GET `/api/system/status`

🔒 需登录 · 需 `status` 模块权限

获取系统运行状态（推理服务、数据库、存储等）。

---

### GET `/api/users`

🔒 需管理员

获取用户列表。

**响应 data：** `{ "items": User[] }`

---

### POST `/api/users`

🔒 需管理员

创建用户。

**请求 Body（JSON）：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `username` | ✅ | string | 用户名 |
| `display_name` | ✅ | string | 显示名称 |
| `password` | ✅ | string | 密码（≥ 6 位） |
| `role` | | string | 角色：`admin` / `doctor` / `nurse` |
| `module_permissions` | | string[] | 模块权限列表 |

**响应 data：** `{ "user": User }`

---

### PATCH `/api/users/<user_id>`

🔒 需管理员

更新用户信息。

**可更新字段：** `display_name`, `role`, `is_active`, `module_permissions`, `password`

**响应 data：** `{ "user": User }`

---

### GET `/api/lookups/base`

🔒 需登录

获取基础查找数据（用户列表 + 患者列表）。

**响应 data：** `{ "users": [...], "patients": PatientRow[] }`

---

### GET `/healthz`

健康检查（公开）。

**响应：** `{ "ok": true, "time": "..." }`

---

## 18. 数据模型

### User

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `username` | string | 用户名 |
| `display_name` | string | 显示名称 |
| `role` | string | 角色：`admin` / `doctor` / `nurse` |
| `is_active` | bool | 是否启用 |
| `module_permissions` | string[] | 模块权限列表 |
| `last_login_at` | string? | 最后登录时间 |
| `created_at` | string | 创建时间 |

### PatientRow

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `name` | string | 姓名 |
| `age` | int? | 年龄 |
| `sex` | string? | 性别 |
| `phone` | string? | 手机号 |
| `email` | string? | 邮箱 |
| `status` | string | `follow_up` / `pending_review` / `has_message` |
| `status_text` | string | 状态文本 |
| `unread_count` | int | 未读消息数 |
| `exam_count` | int | 检查总数 |
| `last_exam_date` | string? | 最后检查时间 |
| `last_followup` | string? | 最后随访时间 |
| `portal_url` | string | 患者门户 URL |
| `updated_at` | string | 更新时间 |

### ExamRow

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `patient_id` | int | 患者 ID |
| `patient_name` | string | 患者姓名 |
| `upload_date` | string | 上传时间 |
| `status` | string | `pending_review` / `reviewed` |
| `spine_class` | string? | 脊柱分类 |
| `spine_class_text` | string? | 分类文本描述 |
| `spine_class_confidence` | float? | 分类置信度 |
| `cobb_angle` | float? | Cobb 角度 |
| `curve_value` | float? | 弯曲值 |
| `severity_label` | string? | 严重程度标签 |
| `improvement_value` | float? | 改善值 |
| `image_url` | string | 影像 URL（推理后优先） |
| `raw_image_url` | string | 原始影像 URL |
| `inference_image_url` | string? | AI 推理结果图 URL |
| `cervical_avg_ratio` | float? | 颈椎平均比率 |
| `cervical_assessment` | string? | 颈椎评估 |

### Conversation

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `type` | string | `private` / `group` / `patient` |
| `name` | string | 会话名称 |
| `patient_id` | int? | 关联患者 ID |
| `updated_at` | string | 最后更新时间 |
| `unread` | int | 未读消息数 |
| `last_message` | Message? | 最后一条消息 |

### Message

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `conversation_id` | int | 会话 ID |
| `sender_kind` | string | `user` / `patient` |
| `sender_user_id` | int? | 发送者用户 ID |
| `sender_name` | string | 发送者名称 |
| `message_type` | string | `text` / `share_case` / `questionnaire_share` |
| `content` | string | 消息内容 |
| `payload` | object | 附加数据 |
| `created_at` | string | 发送时间 |

### Comment

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `author_name` | string | 作者名称 |
| `author_kind` | string | `user` / `guest` |
| `content` | string | 评论内容 |
| `created_at` | string | 创建时间 |

### Questionnaire

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `title` | string | 标题 |
| `description` | string? | 描述 |
| `status` | string | `active` / `stopped` |
| `allow_non_patient` | bool | 是否允许非患者填写 |
| `open_from` | string? | 开放时间起 |
| `open_until` | string? | 开放时间止 |
| `created_at` | string | 创建时间 |

### Schedule

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `patient_id` | int | 患者 ID |
| `patient_name` | string | 患者姓名 |
| `title` | string | 日程标题 |
| `note` | string? | 备注 |
| `scheduled_at` | string | 计划时间 |
| `status` | string | `todo` |

### Event

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 主键 |
| `event_type` | string | 事件类型 |
| `title` | string | 标题 |
| `message` | string | 描述 |
| `level` | string | `info` / `warn` |
| `patient_id` | int? | 关联患者 |
| `exam_id` | int? | 关联检查 |
| `ref` | object | 额外关联数据 |
| `created_at` | string | 创建时间 |

---

### 可用模块列表

`overview` · `followup` · `review` · `chat` · `questionnaire` · `status` · `users`
