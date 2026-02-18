# 浏览器扩展（Manifest V3，域名级追踪）

## 功能
- 仅记录“正在使用的 tab 的域名（hostname）”（不枚举所有打开的 tab）
- 浏览器窗口在前台（focus）时：上报当前活跃 tab（`activity=focus`）
- 浏览器不在前台但有 audible tab 时：上报“正在播放音频”的 tab（`activity=audio`，可在 popup 里关闭）
- 可选：上报 tab 标题（默认关闭）
- 上报目标（默认）：`http://127.0.0.1:17600/event`

说明：
- 扩展的 “Send tab title” 只决定“是否发送”。Core 侧还可以通过 `store_titles` 决定是否真正落库（默认更严格，避免误采集）。

## 安装（Chrome / Edge）
1. 打开扩展管理页
   - Chrome：`chrome://extensions/`
   - Edge：`edge://extensions/`
2. 打开「开发者模式」
3. 点击「加载已解压的扩展程序」并选择本目录：`extension/`
4. 点击扩展图标，在 popup 里开启 `Enable tracking`

## 联调
- 先运行 Core（默认监听 `127.0.0.1:17600`）：`cargo run -p recorder_core -- --listen 127.0.0.1:17600`
- 打开 popup 点击 `Test /health` 应显示 OK
- 如果状态不更新/怀疑 service worker 没醒：点一次 `Force send`
- 打开任意网页并切换 tab：Core 的 `GET /events` 会出现域名事件

## 字段说明（Core 侧可见）
- `event=tab_active`：域名级活跃 tab 事件
- `event=tab_audio_stop`：后台音频“停止”标记（当音频停止或浏览器回到前台时发送，用于更准确结束后台音频统计/让 UI 及时消失）
- `activity=focus|audio`：
  - `focus`：浏览器在前台，用户正在看的 tab
  - `audio`：浏览器不在前台，但某个 tab 在播放音频（视为“正在使用”）
