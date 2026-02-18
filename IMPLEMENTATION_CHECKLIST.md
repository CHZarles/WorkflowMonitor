# 组件实现优先级 + 验收 Checklist（MVP）

> 对齐文档：`PRD.md`、`IA_WIREFRAMES.md`、`VISUAL_STYLE.md`、`COMPONENTS_TOKENS.md`、`design-tokens.json`。

---

## 1) 组件实现优先级（按“先闭环、再打磨”）

### P0（必须：做完即可跑通核心闭环）
- **C01 AppShell**：最小导航与全局状态承载（Windows Panel / Android Scaffold）
- **C02 TopBar/TitleBar**：日期、tracking 状态 pill、搜索/设置入口
- **C11 TimelineList**：今日 block 列表 + idle 片段灰显
- **C10 BlockCard**：block 摘要 + 主动作（填写复盘/查看）
- **C12 BlockDetail（Drawer/BottomSheet）**：TopN + 复盘表单 + 保存
- **C14 ReviewForm（10 秒复盘）**：三字段 + 软校验（产出为空提示）
- **C20 SummaryNotification**：到点提醒 + 动作（填写/延后/跳过/暂停）
- **C21 QuickReviewSheet**：从通知直达输入并保存
- **C22 Toast/InlineBanner**：保存成功、权限缺失、断档提示
- **C30 SettingsList/Row**：设置入口框架
- **C31 PrivacyLevelSelector**：L1/L2/L3（L3 二次确认 + 预览）
- **C33 ReminderSchedule**：间隔/空闲切段/勿扰时段（MVP 先最小）
- **C34 DataManagement**：导出 Markdown/CSV + 一键清空（danger 确认）

### P1（强建议：显著提升“可长期用”）
- **C32 BlacklistManager**：应用/域名黑名单（从 BlockDetail 一键加入）
- **C35 HealthCheck**：权限/通知/后台限制诊断 + 下一步引导
- 标签体系强化：**C15 TagChips**（工作/会议/学习/娱乐 + 自定义）
- 搜索页（从 IA）：按应用/域名/复盘文本检索（可先做简版）

### P2（可选：锦上添花/后续迭代）
- 周报表页（趋势/碎片化指数/有效复盘块数）
- LLM 段总结与编辑工作流（默认关闭）
- 局域网同步/配对与冲突策略

---

## 2) 验收 Checklist（按场景验收）

### 2.1 核心闭环（每天都要跑）
- 记录中状态清晰：`ON/PAUSED/ERROR` 在 TopBar/托盘可见且可点击解释
- 45 分钟到点：通知到达（Windows/Android）并可一键进入复盘输入
- 复盘保存：保存后 block 状态从 ⏳→✅，时间轴立即可见预览文本
- 延后/跳过：延后在预期时间再次提醒；跳过后列表显示“已跳过”（可补填）

### 2.2 隐私与权限（建立信任）
- 默认 L1：不显示窗口标题/完整 URL 字段；设置里解释“会/不会记录什么”
- L2/L3 开启：有明确告知；L3 必须二次确认 + 示例预览
- 黑名单生效：加入后后续不再记录/或聚合中隐藏；UI 明确“含隐藏项/已隐藏”
- 暂停记录：可选 15m/1h/手动；到期自动恢复（若选择了 until）
- 删除/清空：不可逆动作均有确认；清空后时间轴为空态指引

### 2.3 可靠性（最少保证）
- Windows Agent 连续运行 8 小时不崩溃；异常后可自恢复（重启继续记录）
- Android 在常见机型/系统限制下仍能基本到达通知（WorkManager 场景）
- HealthCheck（若做 P1）：能指出“缺权限/禁通知/电池限制/扩展断开”等原因并给跳转

### 2.4 性能与资源
- Windows：托盘常驻 CPU 平均 < 1%，内存 < 150MB（含数据库）
- Android：日耗电增量可接受（中轻度使用 < 5% 目标）
- 写库频率合理：事件有合并/节流，避免高频小写入导致卡顿

### 2.5 视觉一致性（Token 驱动）
- 深色模式：所有页面可读（text 对比度足够），accent/soft 不刺眼
- 组件一致：BlockCard/BottomSheet/Drawer/Buttons/Chips 命名与语义一致
- 图表：TopN 条形同色系，不出现彩虹条；时长展示统一 `h m`

### 2.6 可用性与无障碍
- Android 触控目标 ≥ 48dp；输入框支持多行与系统字体放大
- Windows 键盘可达：Tab 顺序正确；`Ctrl+Enter` 保存复盘；`Ctrl+K` 聚焦搜索（若实现）

### 2.7 导出可用
- Markdown：每个 block 有时间范围、TopN、复盘文本；粘贴到常见笔记结构不乱
- CSV：字段齐全（block_id/start/end/top_items/note/tags），可被表格工具打开

