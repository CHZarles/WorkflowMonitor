# RecorderPhone（Windows：可用 / Android：进行中）

RecorderPhone 是一套**本地优先**的“使用记录 + 分段复盘”工具：
- **Windows 桌面版**（推荐）：一个可携带的 `RecorderPhone.exe`（自动拉起本机 Core + Collector）
- **浏览器扩展**（可选但强烈建议）：记录活跃 Tab（默认**域名级**；可选标题/后台音频）
- **Android**（进行中）：独立本地模式（UsageStats + 本地 SQLite），不依赖桌面

这仓库同时包含产品文档与实现代码（见 `PRD.md` / `IA_WIREFRAMES.md` / `VISUAL_STYLE.md` / `COMPONENTS_TOKENS.md`）。

---

## Windows 版：你能用它做什么

- **Now（正在用）**：基于“前台 focus + 后台音频”判断你此刻在用的 app / tab
- **Blocks（分段）**：按时间聚合（默认 45 分钟一段）+ TopN（应用/网站）占比
- **复盘闭环**：到点通知 → 一键 Quick Review（3 字段 + 标签 + 跳过）→ 变成可检索的工作日志素材
- **首页价值**：`0:00–24:00` 应用/网站泳道时间轴 + 今日 Top（信息密度优先）
- **隐私分级**（渐进式）：  
  - L1（默认）：只存应用/域名与时长  
  - L2：允许存窗口标题 / Tab 标题（才能区分 YouTube 不同视频等）  
  - L3：允许存 `exePath`（更敏感，用于识别与诊断）
- **黑名单**：从详情页一键加入（应用/域名），后续不再记录或聚合为隐藏项
- **导出与 Reports**：本地导出 `report-*.md`（给你读）+ 可选 `report-*.csv`（给你分析/导入）；可接 OpenAI-compatible 云端生成日报/周报（可选）
- **桌面化**：托盘常驻、开机自启（可选）、单实例、防重复记录、打包版内置更新

---

## Windows 快速使用（推荐：打包版，只点一个 exe）

1) 去 GitHub Releases 下载最新 `RecorderPhone-<tag>-windows.zip`  
2) 解压到一个**可写目录**（建议别放 `C:\\Program Files\\`）  
3) 双击运行 `RecorderPhone.exe`（会自动启动本机 `recorder_core.exe` + `windows_collector.exe`）  
4) 托盘图标：
   - 左键：`Open / Hide`
   - 右键：`Quick Review / Pause / Resume / Exit`（退出会停止后台采集）
5) （可选但强烈建议）安装浏览器扩展：加载 `extension/`（Chrome/Edge “加载已解压扩展”）  
   - 扩展默认上报：`http://127.0.0.1:17600/event`
   - popup 里 `Test /health` 显示 OK 即链路正常
6) 在 UI 的 `Settings` 里做一次“最小配置”：
   - `Privacy`：默认 L1；想区分同站点不同标题（如 YouTube 不同视频）→ 开启 L2（Store titles）
   - `Startup`：需要“全天不断档记录”→ 开启开机自启（可选）
   - `Updates`：点 `Check`；有新版本就 `Update & restart`

数据默认落在（打包版）：
- `%LOCALAPPDATA%\\RecorderPhone\\recorder-core.db`

---

## 更新本地 Windows 应用

两种方式：
- **应用内更新**：`Settings → Updates` → `Check` → `Update & restart`（基于 GitHub Releases；Public 仓库无需 token）
- **手动更新**：下载新的 `RecorderPhone-<tag>-windows.zip`，托盘 `Exit` 后用新目录替换旧目录（或直接解压到新目录运行）

详细发布/打包流程见：`RELEASING.md`。

---

## 目录结构
```
core/           Core 本机服务（Rust）
collectors/     采集器（Windows）
ui_flutter/     Flutter UI 模板（Windows/Android 共用）
recorderphone_ui/  你本机生成的 Flutter 工程（运行/打包用，通常不提交）
extension/      Chrome/Edge MV3 扩展（域名级上报）
packages/       Flutter plugins（Android UsageStats 等）
android/        旧 Compose 原型（保留参考）
schemas/        本机上报事件 schema
dev/            开发/打包脚本（overlay/sync/package）
dist/           打包输出（被 gitignore）
```
其它文档/示例：
- `samples/`：主题映射示例（Android/WPF/WinUI）

## Tokens（两端主题接入）
- 源数据：`design-tokens.json`
- Flutter 模板：`ui_flutter/template/lib/theme/tokens.dart`

> 目前是“手动同步”方式：tokens 变化后需要同步更新两端映射文件（后续可加生成脚本）。

## 浏览器扩展 → Core（链路）
- 扩展默认上报到：`http://127.0.0.1:17600/event`
- 事件结构：`schemas/ingest-event.schema.json`
- Core 默认提供 `/health`、`/event`、`/events`、`/blocks/today`、`/blocks/review`、`/privacy/rules`、`/export/markdown`、`/export/csv`（见 `core/README.md`）

## 从源码构建/运行（开发用）
- Windows 开发指南：`WINDOWS_DEV.md`
- Android 真机测试：`ANDROID_DEV.md`
- Core：`core/README.md`
- Collectors：`collectors/README.md`
- Flutter UI：`ui_flutter/README.md`
- Extension：`extension/README.md`

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
