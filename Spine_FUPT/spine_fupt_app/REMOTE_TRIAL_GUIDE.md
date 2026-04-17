# Spine FUPT App 远程试用指南

## 1. 安装 APK

APK 文件位于:
```
D:\HealthIT\spine\code\spine_fupt_app\build\app\outputs\flutter-apk\app-release.apk
```

将此文件发送给试用者（微信、QQ、网盘均可），在 Android 手机上安装即可。

---

## 2. 让远程用户连接你的后端服务器

### 方案 A：使用 ngrok（推荐，最简单）

1. **下载 ngrok**：https://ngrok.com/download  
2. **注册并获取 authtoken**  
3. **启动后端**：
   ```bash
   cd D:\HealthIT\spine\code\Spine_FUPT
   python app.py
   ```
4. **启动 ngrok**：
   ```bash
   ngrok http 5000
   ```
5. ngrok 会输出一个公网地址，类似：
   ```
   Forwarding  https://xxxx-xxx.ngrok-free.app -> http://localhost:5000
   ```
6. **在 App 中配置**：打开 App → 登录页左上角齿轮图标 → 输入 ngrok 的 https 地址 → 保存

### 方案 B：局域网直连（同一 WiFi）

1. 查看电脑 IP：
   ```powershell
   ipconfig | Select-String "IPv4"
   ```
2. 启动后端时绑定 `0.0.0.0`（app.py 默认已是 `host='0.0.0.0'`）
3. 在 App 中配置服务器地址为 `http://你的IP:5000`

---

## 3. 测试账号

| 账号 | 密码 | 角色 |
|------|------|------|
| admin | admin123 | 管理员 |
| doctor | doctor123 | 医生 |

也可以在 App「更多」→「用户管理」→ 右上角 + 创建新账号。

---

## 4. 问卷功能试用

1. 先在 Web 端（浏览器访问后端地址）创建问卷
2. 在 App 的「问卷」标签页查看问卷列表
3. 点进问卷详情 → 浮动按钮「发送给患者」
4. 患者会收到一个填写链接（token URL），可在浏览器或 App 的 `/q/:token` 路由打开

---

## 5. 注意事项

- ngrok 免费版每次启动地址会变，试用者需要重新配置
- 如需固定域名，可购买 ngrok 付费计划，或使用 Cloudflare Tunnel（免费）
- 手机需允许安装未知来源应用
