# Android（Flutter）开发与真机测试

> 主路径 UI：`ui_flutter/template/` → 覆盖到你真实工程 `recorderphone_ui/`（见 `WINDOWS_DEV.md` / `ui_flutter/README.md`）。

当前 Android 端是**独立本地模式**（不依赖桌面 Core）：
- 采集：UsageStats（Usage Access）
- 落盘：手机本地 SQLite（blocks + reviews）
- 页面：Today / Review / Settings（移动端轻量版）

---

## 1) 前置条件
- 安装 Android Studio（含 Android SDK）
- `flutter doctor -v` 里 Android toolchain 必须是 ✅

---

## 2) 连接手机（USB 调试）

1) 手机开启开发者选项与 USB 调试，插线连接电脑  
2) Windows 上确认 `adb` 可用：
```powershell
adb devices
```
如果显示 `unauthorized`，在手机上点“允许 USB 调试”。

---

## 3) 在真机上跑（推荐最短闭环）

### 一条命令（推荐）
```powershell
cd C:\src\RecorderPhone
powershell -ExecutionPolicy Bypass -File .\dev\run-android.ps1
```
如果你电脑上同时连了多个设备/模拟器，`flutter run` 会提示你选择；或者你也可以显式指定设备 id：
```powershell
flutter devices
# 复制设备 id（例如 emulator-5554 / R58N...）
powershell -ExecutionPolicy Bypass -File .\dev\run-android.ps1 -Device <deviceId>
```

### 手动步骤（发生问题时用）
在 **Windows PowerShell** 复制执行：
```powershell
cd C:\src\RecorderPhone

# 覆盖模板 UI 到真实工程 + flutter pub get
powershell -ExecutionPolicy Bypass -File .\dev\overlay-ui.ps1

cd .\recorderphone_ui

# 如果你之前只创建了 Windows 平台，需要补 Android 平台目录（只需执行一次）
flutter create --platforms=windows,android --overwrite .

flutter run
```

首次打开 App：
- 进入 `Settings`，点击 `Open` 打开系统页面，开启 RecorderPhone 的 **Usage Access**
- 回到 App，`Today` 会自动刷新（或点右上角刷新）生成 blocks

---

## 4) 常见问题

### Q：`Running Gradle task 'assembleDebug'...` 看起来卡住？
A：第一次构建可能需要下载依赖（常见 5–15 分钟）。如果你想看详细进度，用 Gradle 直跑：
```powershell
cd C:\src\RecorderPhone\recorderphone_ui\android
.\gradlew.bat assembleDebug --stacktrace --info --no-daemon
```

### Q：Gradle 报 `Timeout waiting to lock build logic queue` / `buildLogic.lock`？
A：同一个工程同时有另一个 Gradle 在跑（常见原因：Android Studio 后台 Sync、或你开了多个 `flutter run`）。
```powershell
# 结束旧的 Gradle daemon（推荐）
cd C:\src\RecorderPhone\recorderphone_ui\android
.\gradlew.bat --stop

# 如果 lock 仍残留（无占用时可删）
Remove-Item -Force .\.gradle\noVersion\buildLogic.lock -ErrorAction SilentlyContinue
```
然后重新 `flutter run` 即可。

### Q：为什么看见的是包名（com.xxx）而不是应用名？
A：已在插件里做了 label 解析；如果你看到旧数据，去 `Settings → Wipe all` 清空后重新生成 blocks。

### Q：Android 还会连桌面 Core 吗？
A：后续可以做“局域网配对/同步”（只传 block 聚合），但你之前要求 Android 不依赖桌面，所以当前先把“手机本地可用”打稳。
