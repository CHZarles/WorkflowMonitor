# 浏览器扩展（Manifest V3，域名级追踪）

## 功能
- 仅记录“正在使用的 tab 的域名（hostname）”（不枚举所有打开的 tab）
- 浏览器窗口在前台（focus）时：上报当前活跃 tab（`activity=focus`）
- 浏览器不在前台但有 audible tab 时：上报“正在播放音频”的 tab（`activity=audio`，可在 popup 里关闭）
- 可选：上报 tab 标题（默认关闭）
- 可选：Keep alive（稳定性开关，默认开启，减少 MV3 service worker 休眠导致的“需要 reload 才恢复”）
- 上报目标（默认）：`http://127.0.0.1:17600/event`

说明：
- 扩展的 “Send tab title” 只决定“是否发送”。Core 侧还可以通过 `store_titles` 决定是否真正落库（默认更严格，避免误采集）。
- 如果你想在 UI 里把 `youtube.com` 拆成“不同视频标题”，需要 **Core 允许存标题（L2）** + **扩展发送标题** 两者都开启；否则只能看到域名粒度（这是隐私策略的一部分）。

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
- 如果状态不更新/怀疑 service worker 没醒：先点一次 `Force send`，不行再点 `Repair`
- 打开任意网页并切换 tab：Core 的 `GET /events` 会出现域名事件

### 常见问题
**Q：为什么 Diagnostics 里 Browser tab 经常变“stale”，我 reload 扩展就好了？**  
A：多数情况下并不需要 reload。优先按下面顺序排查：
1) 打开扩展 popup，看 `Last status` 是否在持续更新（是否有 `error` / 连续错误次数）  
2) 确认 `Server URL` 指向正在运行的 Core（`Test /health` 必须是 OK）  
3) 确认 `Keep alive (stability)` 为 ON（可显著减少 MV3 休眠带来的“断更”）  
4) 点击一次 `Force send`（会立刻尝试发送当前 tab / audible tab）  
5) 点击一次 `Repair`（会重建 keep-alive/offscreen 并清理错误计数，然后强制上报一次）  
6) 只有当 popup 里持续报错、且 `Force send/Repair` 都无效时，再考虑 reload 扩展/重启浏览器

**Q：我想看 YouTube 视频标题，而不是只看到 youtube.com？**  
A：需要两步都打开：
- Core：Settings 里开启 `Store window/tab titles (L2)`  
- 扩展：popup 里开启 `Send tab title (optional)`，然后点一次 `Force send`  
> 注意：在你开启 L2 之前写入数据库的历史记录不会自动补标题；想“立刻看到效果”可以删除当天数据或全清后再试。

## 字段说明（Core 侧可见）
- `event=tab_active`：域名级活跃 tab 事件
- `event=tab_audio_stop`：后台音频“停止”标记（当音频停止或浏览器回到前台时发送，用于更准确结束后台音频统计/让 UI 及时消失）
- `activity=focus|audio`：
  - `focus`：浏览器在前台，用户正在看的 tab
  - `audio`：浏览器不在前台，但某个 tab 在播放音频（视为“正在使用”）
