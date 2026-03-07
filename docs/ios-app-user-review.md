# iOS App 用户体验评价

## 总评：5.5/10

## 一句话感受

骨架搭得不错，但现在还不能替代 Web 终端——滚动看不了历史、中文输入没验证、复制文本要靠运气，日常通勤用的话每天都会骂。

## 详细评分

### 1. 首次启动体验 — 7/10

**好的地方：**
打开 App 直接就是 session 列表，NavigationStack + 暗色主题看着很专业。顶部显示了当前服务器地址 `100.81.22.113:8022`，让我知道连的是哪台机器。设置页可以改 IP 和端口，还有 UserDefaults 持久化，换个网络环境不用每次重新输。Session 卡片展示了名称、窗口数、创建时间（用 RelativeDateTimeFormatter 显示"2小时前"），信息量刚好。

**不好的地方：**
第一次打开完全没有引导。如果我还没开 Tailscale、还没在 Mac 上跑 `start-claude.sh`，App 只会显示一个红色的 `wifi.exclamationmark` 图标和一段报错文字，新用户会一脸懵。设置页虽然有，但没有"测试连接"按钮——我改完 IP 保存后，只能回到主页看能不能刷出 session 来验证。另外默认 IP 是硬编码的 `100.81.22.113`，换一台 Mac 就得手动改。

**我希望：**
- 首次启动有个简单的引导：第一步开 Tailscale、第二步在 Mac 跑脚本、第三步输入 IP
- 设置页加一个"Test Connection"按钮，点了就请求 `/api/sessions` 看能不能通
- 支持 Bonjour/mDNS 自动发现局域网内的 server，或者至少能扫二维码配置

### 2. 终端可读性 — 7/10

**好的地方：**
SwiftTerm 的 ANSI 渲染质量很高，256 色支持完整，比 xterm.js 的 canvas 渲染看着更锐利。提供了三个主题（Dark/Light/Solarized），设置页有实时字体预览 `AaBbCc 012 Hello World`，这个细节不错。iPhone 默认 12pt、iPad 14pt 的区分也合理。触觉反馈（bell 震动）是 Web 端没有的，终端 beep 的时候能感受到，比声音提示更低调。

**不好的地方：**
字体大小在 iPhone 上是固定 12pt，Web 端会根据屏幕宽度动态调整（如果 cols < 70 就从 14pt 往下降到 10pt 来确保 CC 的配置菜单不被截断）。iOS 端完全没有这个逻辑，iPhone SE 或者 iPhone mini 上 12pt 大概率会导致一行显示不完整，CC 的宽屏输出（比如 diff 视图、表格）会被截断。设置页的字号滑块只在 8-20 之间，但改了之后没有告诉你当前对应多少 cols。

**我希望：**
- 连接后自动检测 terminal.cols，如果 < 70 就自动缩小字号，和 Web 端逻辑对齐
- 在设置页字号滑块旁边显示预估的 cols 数（比如"12pt ~ 78 cols"）
- 支持 pinch-to-zoom 实时调整字号，这比进设置页方便太多了

### 3. 打字体验 — 6/10

**好的地方：**
SwiftTerm 原生的 `becomeFirstResponder()` 直接调起系统键盘，不需要 Web 端那套透明 textarea + diff 模型的 hack。理论上键盘输入应该更稳定。快捷键栏做得很整齐，有 Tab/^C/Esc/方向上下/^D/^Z/^L 九个按钮，分组用 Divider 隔开，`monospaced` 字体风格统一。ScrollView 包裹支持横向滚动，不会因为按钮多了挤不下。

**不好的地方：**
快捷键栏缺了好几个关键按钮：没有 NL（换行/发送，这是给 CC 发指令最常用的键）、没有左右方向键（编辑命令行的时候要用）、没有 Select 和 Done（进入/退出文本选择模式）、没有 Paste（粘贴按钮）。Web 端有 12 个按钮，iOS 只有 9 个，而且多出来的 ^D/^Z/^L 使用频率远不如缺失的那些。

中文输入是最大的隐患。技术审查报告明确指出"SwiftTerm 对 iOS 原生 IME 有基本支持，但未做 Web 端那样的 composition 防抖/sentBuffer 追踪"，而且"需实测确认中文输入可靠性"。作为一个中英文混合输入的用户，我每天给 CC 写指令都是"帮我把这个函数的 error handling 改一下"这种混合句子。如果拼音输入确认后会重复发送、或者候选词选择有 bug，那这个 App 基本没法用。Web 端为了搞定 IME 花了巨大精力做了 diff-based input model，iOS 端完全没有对应的防护。

**我希望：**
- 补齐 NL/左右方向键/Select/Paste 按钮，把 ^D/^Z/^L 放到第二行或者长按子菜单里
- 在真机上严格测试中文拼音输入、手写输入、九宫格输入，确保没有重复/丢字问题
- 键盘弹出时 InputAccessoryBar 要紧贴键盘顶部（目前看代码是 VStack 底部固定的，可能键盘弹出后位置不对）

### 4. 滚动浏览 — 2/10

**好的地方：**
代码里有一个精心设计的 `ScrollGestureHandler`，实现了非线性加速（pow 曲线）、惯性动量（CADisplayLink 驱动 0.95 衰减）、25fps 节流、手势消歧（短按=键盘聚焦，拖动=滚动）。`WebSocketManager` 也完整实现了 scroll 协议（`\x01scroll:up:N`/`\x01scroll:down:N`/`\x01scroll:exit`）。从代码质量看，这套滚动系统写得非常好。

**不好的地方：**
然而根据技术审查，v1 的 TerminalView 中并没有将 ScrollGestureHandler 接入 UI 手势——也就是说用户根本无法通过手指滑动来回看历史输出。这对我来说是致命伤：CC 的回复经常有几十行甚至上百行，在 Web 端我已经习惯了上下滑看完整输出。

等等，我仔细再看了一遍当前代码——`TerminalContainerView` 确实重写了 `touchesBegan`/`touchesMoved`/`touchesEnded`，把触摸事件路由到了 `ScrollGestureHandler`。顶栏也有 SCROLL 标签显示。看起来 v2 已经把滚动接入了？但技术审查报告说"有 sendScroll API 但未接入 UI"。这里有矛盾，说明代码是后来补上的。

假设滚动已经接入（从代码看确实接入了），那滚动体验应该不错——但有个问题：`TerminalContainerView` 重写了所有 touch 事件，这意味着 SwiftTerm 自己的触摸交互（比如点击定位光标）全部被拦截了。用户点击终端时，`scrollHandler.onTap` 只做了 `becomeFirstResponder()`（唤起键盘），并没有把点击位置传给 SwiftTerm。

另外，退出滚动模式只能通过"点击"触发（在 `touchesEnded` 中 `!touchMoved` 时发送 `scroll:exit`），没有明显的 UI 按钮。在 Web 端有专门的视觉提示告诉用户"你在 copy-mode 里，点击退出"。

**我希望：**
- 确认滚动功能在真机上真的能用（代码看着是接上了，但需要实测）
- 退出 copy-mode 时加一个明显的浮动按钮，不要只靠点击
- 滚动时在终端上显示一个半透明的"行号/位置"指示器
- 点击事件同时传递给 SwiftTerm，不要完全拦截

### 5. 复制粘贴 — 4/10

**好的地方：**
有三层复制机制：(1) SwiftTerm 内建的 `clipboardCopy` delegate 把选中文本写入 `UIPasteboard`；(2) 长按触发 `showSelectionOverlay`，把终端 buffer 文本导出到一个 `UITextView` overlay 上，支持原生 iOS 文本选择；(3) 顶栏有剪贴板桥接按钮，通过 `GET /api/clipboard` 获取 Mac 端剪贴板内容。overlay 关闭时自动复制选中文本，还有成功震动反馈——这些细节说明开发者有认真想过这个场景。

**不好的地方：**
实际使用中，长按进入选择模式的发现性很差。没有任何 UI 提示告诉用户"长按可以选文本"。快捷键栏也没有 Select 按钮（Web 端有）。overlay 出来之后用 `selectAll(nil)` 默认全选整个 buffer，如果我只想选中间某一小段代码，得先取消全选再重新拖选，操作很繁琐。

剪贴板桥接按钮（顶栏那个文件夹图标）设计有问题：点了之后弹出一个 `confirmationDialog`，让我在"Paste Mac Clipboard"和"Paste iOS Clipboard"之间选。但这个"Paste"其实是"把文本发送到终端输入"，不是"粘贴到 iOS 剪贴板"，措辞容易误解。而且如果 Mac 端剪贴板是空的或者 API 报错，对话框可能只有一个 Cancel 按钮，用户会困惑。

**我希望：**
- 快捷键栏加一个 Select 按钮，和 Web 端对齐
- 长按进入选择模式时，不要默认全选，让用户自己拖选
- 选择模式的 overlay 加一个"Copy"按钮（除了现有的 Done），明确告诉用户"选好了按这个复制"
- 剪贴板桥接的措辞改成"Send to Terminal"而不是"Paste"

### 6. 网络稳定性 — 7/10

**好的地方：**
WebSocket 重连机制实现得很扎实：指数退避 + 随机抖动（`base * 2^attempt + random(0..1)`），最多 10 次重试。顶栏有连接状态指示器（绿色/红色圆点 + "Connected"/"Disconnected"/"Reconnecting... (3/10)" 文字）。30 秒 ping 保活防止空闲断线。`URLSessionConfiguration.waitsForConnectivity = true` 让系统在网络恢复时自动重连。消息大小上限 16MB，不会因为 CC 输出太长而断开。

**不好的地方：**
技术审查指出一个关键问题：`establishConnection()` 中 `task.resume()` 后立即设置 `isConnected = true`，但 WebSocket 此时可能还没真正建立连接。这意味着我进地铁信号不好的时候，App 可能会短暂显示绿色"Connected"然后立刻变红，给人一种"连上了又断了"的错觉。

没有 NWPathMonitor 网络状态监听。WiFi 切到蜂窝（比如出地铁）时，App 不会主动重连，只能等 WebSocket receive 超时后才触发重连，这个延迟可能有几十秒。Web 端也有同样的问题，但浏览器的网络栈通常更积极地检测连接断开。

App 进后台后 WebSocket 会被 iOS 系统杀掉，但没有任何保活机制。如果我看了一眼微信再切回来，连接已经断了需要重连。

**我希望：**
- 修正 `isConnected` 的设置时机——等收到第一条消息再标记为已连接
- 加 NWPathMonitor 监听网络变化，主动触发重连
- App 从后台切回前台时（`scenePhase` 变化）立即检查连接并重连
- 断线时在终端区域显示一个明显的半透明遮罩，而不只是改顶栏小圆点的颜色

### 7. 语音功能 — 6/10

**好的地方：**
`VoiceManager` 设计得很完整：AVAudioSession 配置了 `.playback` + `.mixWithOthers`（可以边听音乐边听 TTS）、AVAudioPlayer 支持 delegate 回调管理播放状态、下载新音频前 cancel 上一个任务（避免堆积）。顶栏有语音开关按钮（喇叭图标，开启时绿色）和播放状态动画（波形图标）。voice-toggle 通过 `POST /api/voice-toggle` 走服务器 API，和 Web 端共享状态——这意味着我在 App 里开了语音，Web 端也知道。

**不好的地方：**
技术审查说 v1 的 `onVoiceEvent` 回调没有接上，但从当前代码看 `TerminalView.onAppear` 里确实设置了 `wsManager.onVoiceEvent = { payload in voiceManager.handleVoiceEvent(payload) }`。如果这是 v2 补上的，那流程应该是通的。

但有个问题：`handleVoiceEvent` 用 `URLSession.shared.dataTask` 下载 mp3，然后在主线程用 `AVAudioPlayer(data:)` 播放。这个流程没有问题，但下载是异步的，如果 CC 连续输出多段语音（比如长回复被分成多个 TTS 片段），新下载会 cancel 旧的，导致只能听到最后一段。Web 端也有类似问题，但至少 Web 端用 HTML5 Audio 可以排队。

没有音量控制，也没有语速调节。通勤时环境噪音大，12pt 的 Edge TTS 默认语速在嘈杂地铁里不太听得清。

**我希望：**
- 多段语音支持排队播放，不要 cancel 前面的
- 加一个简单的语速/音量控制（至少支持 1x/1.5x/2x）
- 语音播放时在顶栏显示正在播放的文本摘要（现在有 `lastSpokenText` 属性但没用上）
- 支持耳机线控暂停/继续

### 8. 通知 — 6/10

**好的地方：**
`NotificationManager` 实现了完整的本地通知流程：请求权限、扫描终端输出匹配完成模式（checkmark/sparkles/party emoji + 关键词）、10 秒冷却防刷屏、只在 App 后台时触发（`applicationState != .active`）。支持服务端推送的 `\x01notify:` 控制帧。`TerminalView.onAppear` 里设置了 `wsManager.onNotifyEvent` 回调和 `notificationManager.requestPermission()`——流程是通的。扫描逻辑也集成在 `onTerminalData` 回调里了。

**不好的地方：**
通知内容太笼统。每次都是固定的 "Task completed in session \"claude\""，不告诉我完成了什么任务。Web 端用标题闪烁 + beep 音 + 浏览器通知三管齐下，体验更丰富。

没有通知分类和分组。如果我同时跑两个 session，通知会混在一起分不清。也没有"查看"操作——点通知不会跳转到对应的 session。

模式匹配太粗暴。`completionPatterns` 里的 emoji 和关键词（"Task completed"/"Build succeeded"/"All tests passed"）是写死的，CC 的实际输出千变万化，很多时候任务完成了但不会输出这些特定文字。

**我希望：**
- 通知内容包含 CC 输出的最后一行摘要，而不是固定文字
- 支持 UNNotificationCategory 添加"查看"action，点了直接跳到对应 session
- 提供通知偏好设置（开关、静音时段、通知模式选择）
- 模式匹配做成可配置的，或者用更智能的启发式规则

### 9. 与 Web 终端对比 — 5/10

| 维度 | Web | App | 赢家 |
|------|-----|-----|------|
| 首次配置 | 打开 URL 即用，零配置 | 需要手动输入 IP | Web |
| 终端渲染质量 | xterm.js canvas 渲染 | SwiftTerm 原生渲染，更锐利 | App |
| 键盘输入基础 | 复杂 diff 模型但经过充分验证 | SwiftTerm 原生但 IME 未验证 | Web（稳定性） |
| 快捷键栏 | 12 个按钮，覆盖所有常用操作 | 9 个按钮，缺少 NL/方向键/Select | Web |
| 触摸滚动 | 非线性加速 + 惯性，充分验证 | 代码实现了但未经实测验证 | Web（确定性） |
| 文本选择/复制 | Select mode + 全屏 overlay + URL 高亮 | 长按 overlay + SwiftTerm 内建 | 平手 |
| 剪贴板桥接 | Paste 按钮 + Mac 剪贴板获取 | 有 ClipboardBridge 且 UI 集成 | App（双源选择更直观） |
| 语音 TTS | Audio 元素播放 + Hook 联动 | AVAudioPlayer + 专用 Manager | App（原生音频更可靠） |
| 通知 | 浏览器 Notification + 标题闪烁 + beep | UNUserNotificationCenter 本地通知 | App（系统级通知更可靠） |
| 断线重连 | 指数退避，10 次重试 | 指数退避 + ping 保活 | App |
| 触觉反馈 | 无 | bell 震动 | App |
| 文件上传 | 相机/相册 + POST /api/upload | 无 | Web |
| Session 内切换 | 顶栏下拉切换 | 必须退出再重选 | Web |
| 动态字体 | 自动适配 cols >= 70 | 固定 12pt/14pt | Web |
| 外接键盘 | 浏览器原生支持 | 无 keyCommands 处理 | Web |
| 调试能力 | Debug 面板显示事件日志 | 无 | Web |
| 离线可用 | 不可用 | 不可用 | 平手 |
| 启动速度 | 依赖 CDN 加载 xterm.js | 原生秒开 | App |
| 内存占用 | Safari 标签页可被系统回收 | App 在后台有保留期 | App |
| 服务器配置 | 不需要（URL = 服务器地址） | Settings 页持久化 | 各有千秋 |
| 多主题 | 固定暗色 | Dark/Light/Solarized | App |
| URL 点击 | 无 | requestOpenLink 自动打开 | App |

**总结：** App 在底层能力（渲染、音频、通知、触觉）上有原生优势，但在交互完整性（快捷键、滚动、选择、上传）上全面落后于 Web 端。Web 端是经过数月迭代打磨的产品，App 还在 Phase 1。

### 10. 整体感受 — 5/10

**愿不愿意从 Web 切换到 App？**

现在不愿意。

App 的代码架构很好——清晰的 MVVM 分层（Models/Views/Network/Audio/Gestures），WebSocket 协议和 server.js 零修改兼容，SwiftTerm 选型正确。但作为一个每天真实使用的人，我需要的不是架构优雅，而是"发指令、看输出、复制代码"这三个核心流程无摩擦。

目前 App 在"发指令"上缺少 NL 键和可靠的中文输入验证，在"看输出"上滚动功能未经实测，在"复制代码"上选择模式发现性差且操作繁琐。这三个核心流程都有卡点，还不如继续用 Web 终端。

但我愿意等。如果把技术审查里的 P0 和 P1 都修完，特别是：
1. 补齐快捷键栏（NL 是第一优先）
2. 验证并修复中文输入
3. 确认触摸滚动可靠工作
4. 加上 App 切换前后台的重连

那 App 就能超过 Web 终端了，因为原生的渲染、通知、触觉反馈和音频确实更好。

## 最想要的 5 个改进（按优先级）

1. **补齐 NL（换行）按钮和左右方向键** — 没有 NL 键就没法给 CC 发多行指令，这是每次使用都要碰的操作。Web 端最常按的就是 NL 和方向键
2. **验证并修复中文拼音输入** — 不做这个就不敢用。哪怕只是在真机上跑一遍拼音输入确认没问题也行，如果有 bug 就必须加 composition 防抖
3. **确认触摸滚动端到端可用** — 代码看着是接上了，但技术审查说没接。需要在真机上验证滚动→tmux copy-mode→看历史→点击退出这个完整流程
4. **App 前后台切换时自动重连** — 用手机的人一定会频繁切 App，回来之后发现断了要手动等重连，体验很差
5. **修正 isConnected 状态 + 加网络状态监听** — 地铁场景下假"Connected"绿灯会让人困惑，加 NWPathMonitor 主动重连能减少等待时间

## 对比 Web 终端

| 维度 | Web 终端得分 | App 得分 | 赢家 | 差距原因 |
|------|------------|---------|------|---------|
| 首次启动 | 9 | 7 | Web | App 需手动配 IP，无引导 |
| 终端可读性 | 7 | 7 | 平手 | App 渲染更锐但字号不自适应 |
| 打字体验 | 8 | 6 | Web | App 缺 NL 键、IME 未验证 |
| 滚动浏览 | 8 | 2 | Web | App 滚动需实测确认 |
| 复制粘贴 | 7 | 4 | Web | App 可发现性差、操作繁琐 |
| 网络稳定性 | 6 | 7 | App | App 有 ping 保活 + 退避重连 |
| 语音功能 | 7 | 6 | Web | App 有架构但排队播放缺失 |
| 通知 | 5 | 6 | App | 系统通知 > 浏览器通知 |
| 功能完整度 | 9 | 5 | Web | App 缺文件上传、Debug 面板等 |
| 原生体验 | 4 | 8 | App | 触觉反馈、秒启动、URL 打开 |

## 会不会推荐给朋友？

现阶段不会。

不是因为 App 写得不好——相反，代码质量和架构设计在 Phase 1 来说已经很扎实了。不推荐的原因是：如果朋友照着我的推荐下了这个 App，结果发现不能方便地发换行、中文输入可能有问题、看历史要碰运气，他的第一印象就毁了。

等 P0 + P1 修完之后，我会第一个推荐。原生 App 在通知推送、触觉反馈、启动速度上的优势是 Web 终端永远追不上的。到那时候我会说："删掉主屏幕上的 Safari 快捷方式，用这个。"
