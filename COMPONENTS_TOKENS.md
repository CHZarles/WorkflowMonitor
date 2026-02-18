# 组件清单 + Token 表（供开发落地）

> 基于：`PRD.md`、`IA_WIREFRAMES.md`、`VISUAL_STYLE.md`。  
> 目标：输出一份“可直接实现”的最小设计系统（MVP 优先），两端（Windows11 / Android）语义一致、实现方式各自贴近平台。

---

## 1) Design Tokens（统一命名）

### 1.1 Color Tokens
> 默认值见 `VISUAL_STYLE.md`；这里给“工程可用”的 key + 建议用途。

| Token | Light | Dark | 用途 |
|---|---:|---:|---|
| `color.bg.0` | `#FFFFFF` | `#0B0F1A` | 页面最底背景 |
| `color.bg.1` | `#F6F7F9` | `#0F1624` | 次级背景（列表底） |
| `color.surface.0` | `#FFFFFF` | `#111A2B` | 卡片/面板 |
| `color.surface.1` | `#F2F3F5` | `#162238` | 次级表面（说明块/选中底） |
| `color.border.0` | `#E6E8EC` | `#22314D` | 分割线/卡片描边 |
| `color.text.0` | `#0B0F1A` | `#F3F6FF` | 主文本 |
| `color.text.1` | `#3B4252` | `#C7D0E0` | 次文本 |
| `color.text.2` | `#6B7280` | `#93A3BD` | 辅助/注释 |
| `color.accent.0` | `#2F80ED` | `#2F80ED` | 主动作（保存/填写复盘） |
| `color.accent.1` | `#1B5FD6` | `#1B5FD6` | 按压/强调 |
| `color.accent.soft` | `rgba(47,128,237,0.12)` | `rgba(47,128,237,0.18)` | 选中背景/高亮条 |
| `color.semantic.success` | `#22C55E` | `#22C55E` | 已复盘 ✅ |
| `color.semantic.warning` | `#F59E0B` | `#F59E0B` | 权限/断档/提醒风险 |
| `color.semantic.danger` | `#EF4444` | `#EF4444` | 删除/清空/不可逆动作 |
| `color.semantic.info` | `#38BDF8` | `#38BDF8` | 信息提示 |

**状态用色规则（强约束）**
- 成功/警告/危险只用于状态与风险提示；不要当装饰色铺满页面。
- TopN 图表：同色系（accent）不同透明度/明度；避免彩虹条。

### 1.2 Spacing / Radius / Border / Elevation
| Token | 值 | 用途 |
|---|---:|---|
| `space.1` | 4 | 超紧凑内边距 |
| `space.2` | 8 | 默认间距（chip/行内） |
| `space.3` | 12 | 小卡片内边距 |
| `space.4` | 16 | 标准卡片内边距 |
| `space.5` | 20 | 区块间距 |
| `space.6` | 24 | 大区块间距 |
| `space.8` | 32 | 页面级留白 |
| `radius.s` | 8 | chip/输入框 |
| `radius.m` | 12 | card/抽屉 |
| `radius.l` | 16 | 大面板/容器 |
| `border.1` | 1 | 默认描边 |
| `elevation.1` | low | 卡片与背景分层（克制） |
| `elevation.2` | mid | 抽屉/弹窗 |

### 1.3 Typography Tokens（语义层级）
| Token | 含义 | 建议（Android sp / Windows px） |
|---|---|---|
| `type.display` | 页面标题 | 20–22 |
| `type.title` | 卡片/抽屉标题 | 16–18（semi-bold） |
| `type.body` | 正文/列表 | 14–16 |
| `type.caption` | 注释/辅助 | 12–13 |

### 1.4 Motion Tokens（轻量）
| Token | 值 | 用途 |
|---|---:|---|
| `motion.duration.short` | 120–160ms | hover/press 反馈 |
| `motion.duration.medium` | 200–240ms | 抽屉/BottomSheet |
| `motion.easing.standard` | ease-out | 默认过渡 |

### 1.5 Icon / Touch Target
| Token | 值 | 用途 |
|---|---:|---|
| `icon.size.s` | 16 | 行内 |
| `icon.size.m` | 20 | 标题栏 |
| `icon.size.l` | 24 | 主动作 |
| `hit.min` | 48dp | Android 触控最小尺寸（Windows 可保证可点区域） |

---

## 2) 平台映射（实现建议）

### 2.1 Android（Material 3）
- `color.accent.*` → `colorScheme.primary` / `primaryContainer`（soft）/ `onPrimary`
- `color.surface.*` → `surface` / `surfaceContainer*`
- `color.border.0` → `outline` / `outlineVariant`
- `type.*` → `MaterialTheme.typography`（以语义映射，不强行固定字号）

### 2.2 Windows11（Fluent / WinUI / WPF）
- 可提供开关：`跟随系统 Accent`（用 `SystemAccentColor` 系列资源）或使用固定 `color.accent.0`
- 文字/背景/边框尽量走系统主题资源（保证深浅色一致性），仅把 Token 作为默认 fallback

---

## 3) 组件清单（MVP 必做）

> 每个组件都应在 Windows 与 Android 具备同名语义；UI 形态可分别为 Drawer（Windows）/BottomSheet（Android）。

### 3.1 导航与框架

**C01. AppShell（Windows Panel / Android Scaffold）**
- 用途：承载“今日/搜索/设置/导出”最小导航
- Props：`currentDate`、`trackingState`、`syncState?`
- States：`tracking=on/off/paused`、`health=ok/warn`

**C02. TopBar / TitleBar**
- 用途：标题 + 状态入口 + 搜索入口
- Anatomy：标题、状态 pill（可点）、操作区（搜索/设置）
- 交互：状态 pill 点击进入“健康检查/权限”

### 3.2 核心：时间轴与 Block

**C10. BlockCard（时间段卡片）**
- 用途：展示一个 block 的摘要与主动作
- Anatomy：
  - 左：时间范围（09:45–10:30）+ 状态（✅/⏳/⏸）
  - 中：Top3（应用/域名 + 时长）
  - 右：主动作按钮（`填写复盘` / `查看`）
- Props：
  - `blockId`、`start/end`、`status`（pending/done/skipped）
  - `topItems[]`（name、type app/domain、duration）
  - `notePreview?`、`tags[]?`
- States：
  - 默认/hover（Windows）/pressed
  - `selected`：左侧 4px accent bar + `color.accent.soft` 背景
  - `privacyHidden`：某些项被隐藏（显示 “含隐藏项”）

**C11. TimelineList（今日时间轴列表）**
- 用途：按时间顺序组织 BlockCard 与 idle 片段
- Props：`blocks[]`、`idleSegments[]`、`filters?`
- 规则：idle 片段灰显，不触发复盘主动作

**C12. BlockDetail（Windows Drawer / Android BottomSheet）**
- 用途：查看/编辑 block，完成复盘闭环
- Sections：
  1) Header：block 时间 + 状态 pill
  2) ActivityBreakdown：TopN 条形图
  3) ReviewForm：三字段（做什么/产出/下一步）+ 标签
  4) Controls：黑名单/隐藏项/删除
- Props：`block`（含 topItems、note、tags、privacyFlags）
- Actions：`save`、`snooze`（仅 pending）、`delete`（danger 确认）

**C13. ActivityBreakdownChart（TopN 条形图）**
- 用途：解释型图表，强调“主要在做什么”
- Props：`items[]`（label、duration、percent?）`maxItems=5`
- 规则：同色系；显示时长优先，占比为辅

**C14. ReviewForm（10 秒复盘表单）**
- 用途：快速输入，完成“有效复盘块数”
- Fields：
  - `doing?`（可选）
  - `output`（建议必填：可做软校验：空则提示，不强阻断）
  - `next?`（可选）
- 交互：`Ctrl/⌘ + Enter` 保存（Windows），Android 键盘 action “完成”

**C15. TagChips（标签）**
- 用途：快速分类（工作/会议/学习/娱乐…）
- Props：`options[]`、`selected[]`、`allowCustom=true`
- Style：未选中中性；选中 `accent/soft` 背景 + accent 文本

### 3.3 提醒与反馈

**C20. SummaryNotification（复盘通知模板）**
- 标题：该复盘了（45 分钟）
- 内容：Top3 + 时长
- Actions：填写复盘 / 延后（10/20/30）/ 跳过 / 暂停记录
- 规则：按钮不超过 4 个；“危险动作”不出现在通知（如删除/清空）

**C21. QuickReviewSheet（通知点击后的轻量页）**
- 用途：从通知 1 步到输入
- Props：`prefillTop3`、`blockId`
- 规则：默认聚焦到“产出/结果”输入框；保存后 toast “已保存”

**C22. Toast / InlineBanner（轻提示）**
- 用途：保存成功/权限缺失/断档提醒
- 语义：info/success/warning/danger（danger 仅用于不可逆前）

### 3.4 设置与隐私

**C30. SettingsList + SettingsRow**
- 用途：统一设置入口（隐私、黑名单、提醒、数据、LLM）
- Props：`title`、`description?`、`value?`、`action`

**C31. PrivacyLevelSelector**
- 用途：L1/L2/L3 选择 + 解释（建立信任）
- Props：`level`、`onChange`
- 交互规则：
  - 切到 L2/L3：显示“将记录什么/不会记录什么”
  - 开启 L3：必须二次确认 + 预览示例（域名/URL）

**C32. BlacklistManager**
- 用途：管理应用/域名黑名单
- Tabs：应用 / 域名
- Props：`items[]`、`onAdd`、`onRemove`
- 交互：从 BlockDetail 一键加入；加入时可选择范围（本段/1h/永久，默认永久需确认）

**C33. ReminderSchedule（提醒节奏）**
- 用途：设置间隔、空闲切段阈值、勿扰时间
- Props：`interval`、`idleCutoff`、`dndRange`

**C34. DataManagement（数据）**
- 用途：导出、保留周期、一键清空
- Actions：`exportMarkdown`、`exportCsv`、`purgeAll`（danger 确认）

**C35. HealthCheck（健康检查）**
- 用途：展示“为什么断档/为什么没提醒”的可解释诊断
- Windows：扩展未连接/被暂停/系统通知关闭
- Android：Usage Access 未开/通知被禁/被电池限制

---

## 4) 组件状态机（MVP 一致规则）

### 4.1 TrackingState（全局）
- `ON`：记录中（正常）
- `PAUSED_UNTIL`：暂停到某个时间（展示倒计时）
- `PAUSED_MANUAL`：手动暂停（显示恢复按钮）
- `ERROR`：断档/权限缺失（banner + 进入健康检查）

### 4.2 BlockStatus
- `PENDING_REVIEW`：待复盘（⏳，主动作“填写复盘”）
- `DONE`：已复盘（✅，主动作“查看”）
- `SKIPPED`：跳过（—，可补填；列表显示“已跳过”）

---

## 5) 最小交付物（给开发的“落地包”建议）
- `design-tokens.json`（按 1) 的 token 输出，含 light/dark）
- 组件实现优先级：C10/C12/C14/C20/C31/C32/C34
- UI 验收：深色模式、权限缺失态、通知→输入→保存闭环、导出可读性

