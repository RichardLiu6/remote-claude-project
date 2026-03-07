# iOS Native App Review v1

> 对比分支 `ios-native-app-phase1`（ios-app/ClaudeTerminal/）与 master 分支 Web App（public/index.html + server.js）
>
> 审查日期：2026-03-07

---

## 1. 功能对比矩阵

| 功能 | Web App | iOS App | 差距说明 |
|------|---------|---------|---------|
| Session 选择器 | ✅ 卡片列表 + 下拉切换 | ✅ List + NavigationStack | iOS 版更美观；Web 版支持顶栏下拉快速切换 session，iOS 缺少连接后切换 session 的能力 |
| 终端渲染（ANSI 颜色） | ✅ xterm.js 5.5 | ✅ SwiftTerm | 两端均完整支持 256-color。SwiftTerm 原生渲染性能更优 |
| 键盘输入 | ✅ 透明 textarea + diff 模型 | ✅ SwiftTerm 原生 becomeFirstResponder | iOS 直接用 SwiftTerm 键盘输入，省去了 Web 端的复杂 diff/sentBuffer 机制 |
| IME/中文输入 | ✅ composition 事件 + 防重复 | ⚠️ 依赖 SwiftTerm 内建 IME 支持 | SwiftTerm 对 iOS 原生 IME 有基本支持，但未做 Web 端那样的 composition 防抖/sentBuffer 追踪。需实测确认中文输入可靠性 |
| 快捷键栏（Tab/^C/Esc/Up/Down） | ✅ 12 个按钮（NL/Tab/Shift-Tab/方向键/^C/Esc/ / /Select/Done/Paste/Upload/Debug） | ⚠️ 9 个按钮（Tab/^C/Esc/Up/Down/^D/^Z/^L） | iOS 缺少：NL(换行发送)、Shift-Tab、左右方向键、Select、Done、Paste、Upload、Debug。iOS 多了 ^D/^Z/^L（Web 无） |
| 触摸滚动（tmux copy-mode） | ✅ 非线性加速 + 惯性动量 + copy-mode 管理 | ⚠️ 有 sendScroll API 但未接入 UI | WebSocketManager 实现了 scroll 协议，但 TerminalView 中没有 touchmove 处理逻辑，无法通过手势触发滚动 |
| 文本选择/复制 | ✅ Select mode overlay + auto-copy + 长按进入 | ⚠️ clipboardCopy delegate 仅处理 SwiftTerm 内部复制 | SwiftTerm 自身支持选中复制，但没有 Web 端那样的全屏 overlay 选择模式和长按触发 |
| 语音模式（TTS 播放） | ✅ voice 控制帧 -> Audio 元素播放 mp3 | ⚠️ 解析了 voice 控制帧，但 onVoiceEvent 回调未实现播放 | iOS 端 parseTextMessage 能正确解析 voice 帧，但 TerminalView 没有设置 onVoiceEvent 回调，也没有 AVAudioPlayer 播放逻辑 |
| 语音开关按钮 | ✅ 无独立按钮（Hook 驱动） | ❌ | 两端均无独立 UI 按钮（通过 Hook 管理），但 Web 端能播放 TTS，iOS 不能 |
| 通知（任务完成） | ✅ Browser Notification + 标题闪烁 + beep 音 | ⚠️ 解析了 notify 帧但仅 print | server.js 广播 notify 帧后，Web 端弹 Notification + 音效 + 标题闪烁；iOS 端仅在控制台打印，未调用 UNUserNotificationCenter |
| 断线重连 | ✅ 指数退避 + 抖动，最多 10 次 | ✅ 指数退避 + 抖动，最多 10 次 | 两端实现逻辑一致，iOS 额外有 ping keep-alive（30s 间隔） |
| 终端尺寸自适应（resize） | ✅ fitAddon + visualViewport 响应键盘 | ✅ SwiftTerm sizeChanged delegate | 两端均支持。Web 端需处理键盘弹出时的精确高度计算，iOS 由 SwiftUI 布局自动处理 |
| 剪贴板桥接（Mac pbpaste） | ✅ GET /api/clipboard + Paste 按钮 | ❌ | Web 端可通过 Paste 按钮获取 Mac 剪贴板内容并输入终端，iOS 完全缺失 |
| 文件上传（手机 -> Mac） | ✅ POST /api/upload + 相机按钮 | ❌ | Web 端可拍照/选图上传到 Mac /tmp，自动输入路径；iOS 完全缺失 |
| 深色主题 | ✅ CSS 固定暗色 | ✅ .preferredColorScheme(.dark) | 两端均为暗色主题 |
| 动态字体大小 | ✅ 自动缩小至 cols >= 70 | ⚠️ iPad/iPhone 区分固定字号 | Web 端根据屏幕宽度动态调整 fontSize（14->10），iOS 仅按设备类型固定（iPad 14pt / iPhone 12pt），不根据 cols 动态调整 |
| Debug 日志面板 | ✅ 事件追踪 overlay | ❌ | Web 端有 Debug 按钮显示输入事件日志（keydown/beforeinput/input），iOS 完全缺失 |
| Select mode overlay | ✅ 全屏可选文本 div + URL 高亮 | ❌ | Web 端可将终端 buffer 导出到可选文本层，支持 URL 点击；iOS 完全缺失 |
| 服务器配置持久化 | ❌ 硬编码为 location.host | ✅ Settings sheet + UserDefaults | iOS 有独立设置页可修改 host/port 并持久化，Web 端无需此功能（浏览器地址即服务器） |
| 音频解锁（Chrome mobile） | ✅ silence.wav 预播放 | N/A | 仅 Web 端需要处理浏览器自动播放策略限制 |
| Session 内切换 | ✅ 顶栏下拉 select 可直接切换 | ❌ 需退出回 picker 重新选择 | Web 端连接后可通过顶栏下拉快速切换另一个 session |
| 触觉反馈 | ❌ | ✅ bell() 触发 UIImpactFeedbackGenerator | iOS 独有优势：终端 bell 触发震动反馈 |
| URL 打开 | ❌ | ✅ requestOpenLink delegate | iOS 可直接打开终端中的 URL 链接 |

---

## 2. 代码质量审查

### 2.1 Swift 编码规范

**整体评价：良好。** 代码结构清晰，命名规范，注释充足。

具体问题：

| # | 文件 | 问题 | 严重度 |
|---|------|------|--------|
| Q1 | `WebSocketManager.swift:141-145` | `establishConnection()` 中在 `task.resume()` 后立即将 `isConnected` 设为 `true`，但 WebSocket 此时尚未真正建立连接。应在收到第一条消息或通过 delegate 确认连接成功后才设为 `true` | 高 |
| Q2 | `WebSocketManager.swift:134` | `session!` 强制解包。虽然上面有 `guard` 保护了 `sessionName`，但 `session`（URLSession）在此处是刚赋值的，强制解包是安全的。不过更好的做法是用 `guard let` | 低 |
| Q3 | `WebSocketManager.swift:125-129` | `onTerminalData` 回调在 `makeUIView` 中设置，使用了 `context.coordinator` 闭包捕获。如果 SwiftUI 重建 View，旧 coordinator 的 terminalView 引用可能失效。应在 `updateUIView` 中重新绑定 | 中 |
| Q4 | `TerminalView.swift:125-129` | `wsManager.onTerminalData` 闭包捕获了 `context.coordinator`，但 coordinator 对 `terminalView` 是 `weak` 引用（正确）。然而 `wsManager` 本身持有 `onTerminalData` 闭包，而闭包引用了 `context.coordinator`。由于 coordinator 不持有 wsManager，不会形成循环引用 — 但 wsManager 被 `@StateObject` 持有，生命周期可能超过 coordinator | 中 |
| Q5 | `WebSocketManager.swift:269-279` | `fetchSessions` 使用 `URL(string:)!` 强制解包，如果 host 包含非法字符会崩溃 | 中 |
| Q6 | `SessionPickerView.swift` | `loadSessions()` 在 `onAppear` 和多个按钮中调用，但没有防抖机制。快速连续点击 Refresh 可能导致并发请求 | 低 |

### 2.2 内存管理

- **WebSocketManager**: `deinit` 中调用 `disconnect()` — 正确清理 WebSocket 连接
- **Coordinator**: `weak var terminalView` — 正确避免循环引用
- **receiveMessage**: `[weak self]` 捕获 — 正确
- **startPing**: `[weak self]` 捕获且检查 task identity — 正确防止旧连接 ping
- **潜在问题**: `onTerminalData` / `onVoiceEvent` / `onSessionEnded` 三个回调均为强引用闭包。如果这些闭包捕获了持有 `wsManager` 的对象（如 View 的 coordinator），可能造成隐式循环。当前代码中 coordinator 不持有 wsManager（wsManager 由 TerminalView 的 @StateObject 持有），所以暂时安全

### 2.3 错误处理

- `fetchSessions`: 正确使用 `try/catch`，错误消息展示给用户
- `WebSocket send`: 仅 `print` 错误，未通知 UI 层 — 可接受（终端场景下消息丢失不致命）
- `parseTextMessage`: JSON 解析失败静默忽略 — 可接受
- **缺失**: 网络切换（WiFi -> Cellular）时无感知机制，仅靠 receive 失败触发重连

### 2.4 WebSocket 协议完整性（与 server.js 对比）

| 协议特性 | server.js | iOS App | 状态 |
|----------|-----------|---------|------|
| 纯文本 -> pty.write | ✅ | ✅ sendInput | 完整 |
| `\x01resize:{cols,rows}` | ✅ 解析并 pty.resize | ✅ sendResize | 完整 |
| `\x01scroll:up/down:N` | ✅ tmux copy-mode + scroll | ✅ sendScroll | 协议完整，但 UI 未接入 |
| `\x01scroll:exit` | ✅ tmux send-keys cancel | ✅ sendScroll(direction:"exit") | 协议完整，但 UI 未接入 |
| 服务端 -> `\x01voice:{...}` | ✅ broadcastVoice | ✅ 解析 | 解析完整，但无播放 |
| 服务端 -> `\x01notify:{...}` | ✅ broadcastNotify | ⚠️ 仅 print | 缺少 UNNotification 调用 |
| 服务端 -> `[session ended]` | ✅ ws.send + close | ⚠️ onSessionEnded 回调已定义但未检测 | `parseTextMessage` 中没有检查 `[session ended]` 文本 |
| Binary data | ✅ pty.onData 发送 | ✅ handleMessage .data case | 完整 |

### 2.5 SwiftTerm Delegate 方法实现

| Delegate 方法 | 实现状态 | 说明 |
|---------------|---------|------|
| `send(source:data:)` | ✅ | 正确转发到 WebSocket |
| `sizeChanged(source:newCols:newRows:)` | ✅ | 防重复 + 非零检查 |
| `setTerminalTitle(source:title:)` | ✅ 空实现 | 可用于更新顶栏标题 |
| `scrolled(source:position:)` | ✅ 空实现 | tmux 管理滚动，正确 |
| `clipboardCopy(source:content:)` | ✅ | 写入 UIPasteboard |
| `requestOpenLink(source:link:params:)` | ✅ | UIApplication.shared.open |
| `hostCurrentDirectoryUpdate` | ✅ 空实现 | tmux 模式下不适用 |
| `rangeChanged` | ✅ 空实现 | 无需处理 |
| `bell(source:)` | ✅ | 触觉反馈 |
| `iTermContent` | ✅ 空实现 | 注释说明未支持 |

---

## 3. v2 改进优先级列表

### P0 — 必须修复（影响基本可用性）

| # | 改进项 | 说明 | 实现建议 |
|---|--------|------|---------|
| 1 | **触摸滚动接入 UI** | WebSocketManager 已有 sendScroll，但 TerminalView 没有手势处理，用户无法回看历史输出 | 在 SwiftTermView 上添加 UIPanGestureRecognizer，移植 Web 端的非线性加速 + 惯性算法，调用 wsManager.sendScroll |
| 2 | **isConnected 状态修正** | establishConnection 中过早设置 isConnected=true，导致 UI 显示"Connected"但实际连接可能失败 | 将 isConnected=true 移到 receiveMessage 第一次成功接收消息时设置，或使用 URLSessionWebSocketTask 的 state 检查 |
| 3 | **[session ended] 检测** | 终端 session 结束时无响应，用户不知道 session 已断开 | 在 parseTextMessage 中检查文本是否包含 `[session ended]`，触发 onSessionEnded 回调 |
| 4 | **中文输入实测验证** | SwiftTerm 的 IME 支持未经验证，可能存在拼音输入确认后重复发送等问题 | 在真机上测试拼音/手写输入，如有问题需拦截 markedText 事件并做 composition 处理 |

### P1 — 重要功能补齐（影响日常使用效率）

| # | 改进项 | 说明 | 实现建议 |
|---|--------|------|---------|
| 5 | **快捷键栏补全** | 缺少 NL(发送换行)、Shift-Tab、左右方向键、Select、Done | 在 InputAccessoryBar 中添加缺失按键。NL 键发送 `\x1b\r`（Escape+CR），Shift-Tab 发送 `\x1b[Z` |
| 6 | **剪贴板桥接** | 无法获取 Mac 端剪贴板内容 | 添加 Paste 按钮，调用 GET /api/clipboard API，将结果通过 sendInput 发送 |
| 7 | **本地通知** | notify 控制帧仅 print，不触发系统通知 | 在 parseTextMessage 的 notify 分支中调用 UNUserNotificationCenter.add()，请求通知权限 |
| 8 | **语音播放** | voice 控制帧已解析但无播放逻辑 | 在 TerminalView.onAppear 中设置 wsManager.onVoiceEvent 回调，用 AVAudioPlayer 或 AVPlayer 播放 mp3 URL |
| 9 | **文件上传** | 无法从手机发送图片到 Mac | 添加 PHPickerViewController 选图 -> base64 编码 -> POST /api/upload -> sendInput(返回路径) |
| 10 | **Session 内切换** | 连接后需退出 picker 才能换 session | 在 topBar 添加 session 名称点击跳回 picker，或添加下拉 Picker |
| 11 | **动态字体自适应** | iPhone 固定 12pt，窄屏可能 cols 不足 | 连接后检查 terminal.cols，若 < 70 则循环减小 fontSize 直到满足（移植 Web 端 optimizeMobileFontSize 逻辑） |

### P2 — 体验增强（锦上添花）

| # | 改进项 | 说明 | 实现建议 |
|---|--------|------|---------|
| 12 | **Select mode overlay** | 无法方便地选中终端文本并复制 | 利用 SwiftTerm 的 getTerminal() 获取 buffer 文本，显示在 UITextView overlay 上，支持原生文本选择 |
| 13 | **Debug 日志面板** | 无调试信息可查 | 添加可选的 debug overlay（SwiftUI Sheet），显示 WebSocket 收发日志和连接状态变化 |
| 14 | **网络状态感知** | WiFi/Cellular 切换无感知 | 使用 NWPathMonitor 监听网络变化，主动触发重连而非等待 receive 超时 |
| 15 | **Background 保活** | App 进后台后 WebSocket 断开 | 使用 BGTaskScheduler 或在 scenePhase 变化时重连。注意 iOS 后台限制，可用 beginBackgroundTask 争取短暂保活 |
| 16 | **fetchSessions 强制解包** | `URL(string:)!` 在 host 含特殊字符时崩溃 | 改为 `guard let url = URL(...)` 并抛出合适错误 |
| 17 | **iPad 分屏支持** | 当前未针对 iPad 多窗口优化 | 支持 iPad Split View，可同时查看两个 session |
| 18 | **App 图标 & Launch Screen** | Assets.xcassets 中 AppIcon 为空 | 设计并添加应用图标，添加 Launch Screen storyboard |
| 19 | **Haptic 扩展** | 仅 bell 触发震动 | 连接成功/断线/通知时也添加不同级别的 haptic 反馈 |
| 20 | **键盘快捷键（外接键盘）** | 未处理外接蓝牙键盘的 Cmd+C / Cmd+V 等 | 在 TerminalView 中添加 `.keyCommands` 支持，映射常用 Cmd 组合键 |

---

## 4. 总结

iOS App Phase 1 完成了核心的终端连接和基本输入功能，代码架构清晰、协议兼容性好（server.js 零修改）。主要差距集中在三个方面：

1. **交互完整性**：触摸滚动、文本选择、快捷键栏等直接影响日常使用的功能尚未完整实现
2. **辅助功能缺失**：剪贴板桥接、文件上传、语音播放、通知等 Web 端已有的辅助功能需要逐一补齐
3. **状态管理细节**：isConnected 过早设置、session ended 未检测等影响连接可靠性的问题需优先修复

建议按 P0 -> P1 -> P2 顺序迭代，每个优先级作为一个 PR 提交。
