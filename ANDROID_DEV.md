# Android（Flutter）开发与联调指南

> 主路径 UI：`ui_flutter/template/` → 覆盖到你真实工程 `recorderphone_ui/`（见 `WINDOWS_DEV.md` / `ui_flutter/README.md`）。

## 1) 前置条件
- 安装 Android Studio（含 Android SDK）
- `flutter doctor -v` 里 Android toolchain 必须是 ✅

## 2) Android 如何连到桌面 Core（最容易踩坑的点）

### 方案 A（推荐：真机 USB 调试 + `adb reverse`，最省事）
让手机里访问 `http://127.0.0.1:17600` 时，实际转发到你的开发机端口。

1. 手机开启开发者选项与 USB 调试，连接电脑
2. 在 Windows PowerShell / macOS / Linux 执行：
```bash
adb devices
adb reverse tcp:17600 tcp:17600
```
3. 手机端 RecorderPhone 里 `Server URL` 填：
```text
http://127.0.0.1:17600
```

> Core 如果跑在 WSL：通常 Windows 的 `127.0.0.1:17600` 也能转发到 WSL（WSL2 localhost forwarding）。  
> 若你的环境关闭了该转发，改成让 Core 监听 `0.0.0.0:17600` 再试。

### 方案 B（Android 模拟器）
模拟器里宿主机 localhost 是固定地址 `10.0.2.2`：
```text
http://10.0.2.2:17600
```

### 方案 C（同一局域网：真机直连桌面 IP）
1. Core 需要监听可被局域网访问（例如 WSL 里）：
```bash
bash dev/run-core.sh 0.0.0.0:17600
```
2. 手机端 `Server URL` 填你的桌面局域网 IP，例如：
```text
http://192.168.1.23:17600
```
3. Windows 防火墙/安全软件可能拦截入站端口，需放行 17600（仅局域网）。

## 3) 跑 Android UI

### 真实 Flutter 工程（你在 Windows 上跑的那个）
在 Windows 工程目录：
```powershell
cd C:\src\RecorderPhone\recorderphone_ui
flutter pub get
flutter run -d android
```

> 首次跑不起来优先看 `flutter doctor -v` 与 Android Studio SDK 是否完整。

## 4) 常见问题

### Q：为什么 Android 上用 `http://127.0.0.1:17600` 访问不到？
A：那是手机自己的 localhost。用上面的 A/B/C 任一方案即可。

### Q：Android 上能不能“也采集手机应用使用情况”？
A：可以，但需要 `PACKAGE_USAGE_STATS`（Usage Access）等权限，并且后台采集在不同品牌系统上会有系统限制。当前仓库优先把“桌面链路 + 复盘闭环”打磨稳定后再做 Android Collector（对应 PRD 的 M2）。

