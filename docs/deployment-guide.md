# 脊柱AI影像随访系统 — 部署指南

> 版本：1.2.0 · 更新日期：2026-04-01

---

## 1. 环境要求

### 后端服务器

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux / Windows / macOS |
| Python | ≥ 3.10 |
| 磁盘 | ≥ 2 GB（数据库 + 影像存储） |
| 内存 | ≥ 512 MB |
| 网络 | 需可达 AI 推理服务器（默认 `spine.healthit.cn:15443`） |

### Flutter 客户端构建

| 项目 | 要求 |
|------|------|
| Flutter SDK | ≥ 3.27 |
| Android SDK | API 21+（targetSdk 36） |
| JDK | 17 |

---

## 2. 后端部署

### 2.1 获取代码

```bash
# 项目目录
cd /opt/spine-fupt        # 或你选择的部署路径
# 将 Spine_FUPT 文件夹复制至此
```

### 2.2 安装依赖

```bash
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

**依赖清单（requirements.txt）：**

```
Flask==3.1.0
Flask-SQLAlchemy==3.1.1
requests==2.32.3
flask-sock==0.7.0
qrcode==7.4.2
Pillow==10.4.0
flask-cors==5.0.1
```

### 2.3 环境变量（配置项）

| 变量名 | 必填 | 默认值 | 说明 |
|--------|------|--------|------|
| `FLASK_SECRET_KEY` | **建议** | `spine-workbench-secret-change-me` | Session 加密密钥，**生产环境务必修改** |
| `SPINE_REMOTE_INFER_BASE` | | `http://spine.healthit.cn:15443` | AI 推理服务地址 |
| `SPINE_REMOTE_TIMEOUT` | | `60` | 推理请求超时（秒） |
| `SPINE_ALERT_COBB` | | `45` | Cobb 角预警阈值 |
| `SPINE_ADMIN_USER` | | `admin` | 初始管理员用户名 |
| `SPINE_ADMIN_PASSWORD` | | `admin123` | 初始管理员密码，**首次启动后建议修改** |

可通过 `.env` 文件或系统环境变量设置：

```bash
export FLASK_SECRET_KEY="your-random-secret-key-here"
export SPINE_REMOTE_INFER_BASE="http://your-inference-server:15443"
export SPINE_ADMIN_PASSWORD="strong-password"
```

### 2.4 数据库初始化

系统使用 SQLite，数据库文件自动创建在项目目录下：

```
Spine_FUPT/spine_workbench.db
```

**首次启动时自动执行：**
1. `db.create_all()` — 创建 19 张数据表
2. `ensure_schema_columns()` — 增量迁移（自动添加新版本字段）
3. `bootstrap_admin()` — 若无用户则创建初始管理员

无需手动执行迁移命令。

### 2.5 启动服务

**开发模式（调试）：**

```bash
python app.py
# 监听 0.0.0.0:5000，debug=True
```

**生产模式（推荐用 Gunicorn）：**

```bash
pip install gunicorn
gunicorn -w 1 -b 0.0.0.0:5000 --timeout 120 app:app
```

> ⚠️ WebSocket 功能依赖 `flask-sock`，Gunicorn 需使用 1 个 worker（`-w 1`）  
> 或使用支持 WebSocket 的 ASGI 服务器。

**验证启动：**

```bash
curl http://localhost:5000/healthz
# 预期返回：{"ok": true, "time": "2026-03-20T...Z"}
```

### 2.6 文件存储

上传影像存储路径：

```
Spine_FUPT/static/uploads/
```

确保该目录对运行用户可写。最大上传大小：64 MB。

支持的影像格式：`.png` `.jpg` `.jpeg` `.bmp` `.webp`

### 2.7 反向代理（可选）

Nginx 配置示例：

```nginx
server {
    listen 80;
    server_name spine.example.com;
    client_max_body_size 64M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /ws {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## 3. 数据库迁移

### 自动迁移

每次启动时 `ensure_schema_columns()` 会自动检查并添加缺失列：

- `wb_exams`: `inference_image_path`, `review_owner_user_id`, `spine_class`, `spine_class_id`, `spine_class_confidence`
- `wb_questionnaires`: `allow_non_patient`, `open_from`, `open_until`
- `wb_questions`: `is_active`
- `wb_questionnaire_responses`: `responder_patient_id`, `responder_cookie_id`

### 手动备份

```bash
# 备份数据库
cp spine_workbench.db spine_workbench_$(date +%Y%m%d).db.bak

# 备份上传文件
tar czf uploads_$(date +%Y%m%d).tar.gz static/uploads/
```

---

## 4. Flutter APK 构建

### 4.1 配置服务器地址

App 内通过设置页面配置后端地址，无需硬编码。默认首次打开时进入登录页，可在设置中修改服务器 URL。

### 4.2 Debug 构建

```bash
cd spine_fupt_app
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk
```

### 4.3 Release 构建

```bash
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk
```

### 4.4 签名配置

Release 构建需要签名。创建 `android/key.properties`：

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=spine-fupt
storeFile=../keystore/spine-fupt.jks
```

生成 keystore：

```bash
keytool -genkey -v -keystore keystore/spine-fupt.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias spine-fupt
```

### 4.5 版本号管理

在 `pubspec.yaml` 中更新：

```yaml
version: 1.0.0+1    # 格式：<版本名>+<构建号>
```

- 版本名（`1.0.0`）：用户可见的版本号
- 构建号（`+1`）：每次发布递增，Google Play / 应用商店用于判断更新

---

## 5. 网络环境注意事项（中国大陆）

Flutter 构建时需要从 Google 下载依赖，在中国大陆需设置镜像：

```bash
# PowerShell / Bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

Gradle 构建文件中已配置国内镜像仓库（`maven.aliyun.com`、`storage.flutter-io.cn`）。

---

## 6. 故障排查

| 症状 | 排查方向 |
|------|----------|
| `healthz` 无响应 | 检查 Python 进程是否运行、端口是否被占用 |
| 登录失败 | 检查数据库文件权限、`FLASK_SECRET_KEY` 是否变更 |
| AI 推理超时 | 检查 `SPINE_REMOTE_INFER_BASE` 可达性；调大 `SPINE_REMOTE_TIMEOUT` |
| 上传失败 | 检查 `static/uploads/` 目录写权限；文件大小 < 64 MB |
| WebSocket 断连 | Nginx 需配置 WebSocket 代理（见 2.7） |
| APK 构建失败（网络） | 设置 `FLUTTER_STORAGE_BASE_URL` 环境变量 |
