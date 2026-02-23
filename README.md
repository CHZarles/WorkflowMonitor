# RecorderPhone（工程骨架）

这是一套跨设备“使用记录 + 周期复盘”系统的**工程骨架**，包含：
- Core：跨平台本机服务（Rust + SQLite + blocks/导出）
- UI：Flutter（Windows/Android 共用，当前提供模板）
- Windows Collector：最小 Win32 采集器（Rust，前台应用/可选窗口标题 + 后台音频 App（QQ 音乐等））
- 浏览器扩展：Chrome/Edge Manifest V3（**域名级**活跃 Tab（focus）+ 可选后台音频 Tab（audio）上报 → POST 到 Core）

设计文档：
- `PRD.md`
- `IA_WIREFRAMES.md`
- `VISUAL_STYLE.md`
- `COMPONENTS_TOKENS.md`
- `design-tokens.json`（Light/Dark + tokens 源数据）
- `WINDOWS_DEV.md`（在 Windows 查看最新开发进展：WSL 同步 + Flutter 覆盖流程）
- `ANDROID_DEV.md`（Android 端如何联调桌面 Core：adb reverse / 模拟器 / 局域网）
- `RELEASING.md`（发布到 GitHub：每次升级从 Releases 下载 Windows 打包版）

## 目录结构
```
core/           Core 本机服务（Rust）
collectors/     采集器（Windows）
ui_flutter/     Flutter UI 模板（需 flutter create 生成平台目录）
extension/      Chrome/Edge MV3 扩展（域名级上报）
schemas/        本机上报事件 schema
samples/        主题映射示例（Android/WPF/WinUI）
dev/            开发脚本（WSL 联调 / 同步到 Windows）
```

## Tokens（两端主题接入）
- 源数据：`design-tokens.json`
- Flutter 模板：`ui_flutter/template/lib/theme/tokens.dart`

> 目前是“手动同步”方式：tokens 变化后需要同步更新两端映射文件（后续可加生成脚本）。

## 浏览器扩展 → Core（开发期链路）
- 扩展默认上报到：`http://127.0.0.1:17600/event`
- 事件结构：`schemas/ingest-event.schema.json`
- Core 默认提供 `/health`、`/event`、`/events`、`/blocks/today`、`/blocks/review`、`/privacy/rules`、`/export/markdown`、`/export/csv`（见 `core/README.md`）

## 如何构建/运行
- Core：见 `core/README.md`
- Collectors：见 `collectors/README.md`
- Flutter UI：见 `ui_flutter/README.md`
- Extension：见 `extension/README.md`

## 下载/发布（Windows）
如果你希望“每次升级都去 GitHub 拿最新 exe”，直接看：`RELEASING.md`（已内置 GitHub Actions：tag 触发打包并发布到 Releases）。

## Quickstart（先把链路跑通）
### 方案 A（WSL 也能跑通：推荐）
1. 在 WSL 启动 Core：`bash dev/run-core.sh 127.0.0.1:17600`（等价于 `cargo run -p recorder_core -- --listen 127.0.0.1:17600`）
2. 在 Windows 浏览器加载 `extension/`（解压加载），popup 点击 `Test /health` 应显示 `OK`
3. 随便打开/切换几个网页 tab：访问 `http://127.0.0.1:17600/events` 能看到域名事件

### 方案 A2（Windows 本地一键启动：不依赖 WSL）
在 Windows PowerShell：
`powershell -ExecutionPolicy Bypass -File .\\dev\\run-desktop.ps1 -SendTitle`
> 详见：`WINDOWS_DEV.md`。

### 方案 A3（Windows 打包版：只点一个 exe）
在 Windows PowerShell 生成打包目录（会把 Core/Collector 放到 UI 旁边）：
`powershell -ExecutionPolicy Bypass -File .\\dev\\package-windows.ps1 -InstallProtocol`

然后双击运行：
`dist\\windows\\RecorderPhone\\RecorderPhone.exe`

### 方案 B（仅用于扩展联调：不支持 UI）
1. 在 WSL 启动简化接收服务：`node dev/ingest-server.mjs`
2. 说明：该服务只提供 `/health`、`/event`、`/events`，不提供 `/settings`、`/blocks/today`、`/privacy/rules` 等接口  
   如果你要运行 Flutter UI（Today Top/Review/Settings/导出），请使用方案 A 启动 `recorder_core`。

## 一键全清（重置所有数据）
这会删除 Core 的 SQLite 数据库（包含：events、blocks/review、privacy rules、settings）。

- WSL/Linux：`bash dev/wipe-core-db.sh`
- Windows（仅当 Core 在 Windows 上运行时）：`powershell -ExecutionPolicy Bypass -File .\\dev\\wipe-core-db.ps1`
