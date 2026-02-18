# Android（Compose）项目说明

> ⚠️ 旧原型：当前主路径是 `ui_flutter/`（Flutter UI）。  
> 这个 Compose 工程仅作为早期验证保留。

> 构建环境要求：Android Studio（推荐）+ Android SDK（本仓库不包含 SDK）。

## 打开方式
- 用 Android Studio 打开：`android/RecorderPhone/`

## Tokens / 主题
- 源：`design-tokens.json`
- Compose Theme：`android/RecorderPhone/app/src/main/java/com/recorderphone/ui/theme/RecorderTheme.kt`

## 下一步（MVP 竖切）
- 接入 UsageStats（前台应用事件流）→ 聚合成 block → 45 分钟通知 → 快速复盘输入 → 今日时间轴展示
