# iOS App v6 用户体验评价（最终版）

## 总评：9.2/10（v2: 5.5 -> v3: 7.5 -> v4: 8.5 -> v5: 8.8 -> v6: 9.2，+0.4）

## 一句话感受

v6 是六个版本中第一个"对着上一版评价逐条打勾"的版本。v4 评价列出的前五优先级，到 v5 一个都没做——v6 一口气做了四个（动态字号、断线遮罩、横屏迷你状态条、快捷栏 Select 按钮），只有触摸滚动的真机验证仍然缺席。加上 DebugLogStore 的完整接入和 Onboarding 的 Test Connection 按钮，v6 在功能债务清零方面的执行力是整个迭代历程中最强的一次。这不是一个追求创新的版本，而是一个追求"该做的全做了"的版本。对于准备提交 TestFlight 的节点来说，这恰恰是最正确的姿态。

## 详细评分

### 1. 首次启动体验 -- 9/10（v4: 8.5 -> v5: 8.5 -> v6: 9，+0.5）

**v6 做了什么：** Onboarding 增加 "Test Connection" 按钮。

这个改动精准地回应了 v4、v5 连续两版评价中的诉求："设置页 Test Connection 按钮"。实现在 `OnboardingView.swift` 的 `configPage` 中，用户输入 Tailscale IP 和端口后，点击 "Test Connection"，App 调用 `WebSocketManager.fetchSessions(config:)` 尝试拉取 session 列表。四种状态（`idle`/`testing`/`success`/`failed`）各自有对应的 UI——spinner、绿色 "Connected!"、红色 "Failed - Check IP"。

从首次使用者的角度，这解决了一个关键的"信心问题"：以前输入 IP 后只能点 "Get Started" 然后祈祷，现在可以先验证网络可达性。如果 Tailscale 没开或 IP 填错，用户在 Onboarding 阶段就能发现，而不是进了主界面看到一个 "Cannot reach server" 的红色报错。

`ConnectionTestState` 作为 `Equatable` 枚举设计得很干净——`label` 和 `bgColor` 都是计算属性，UI 代码只需要绑定状态值。按钮在 `testing` 状态下 `disabled`，防止重复点击。

**加分的原因：** 这是首次启动体验的最后一块拼图。v4 的 auto-connect 解决了"回访用户秒进入"，v6 的 Test Connection 解决了"新用户知道配置对不对"。两者加起来，首次启动流程从"输入 IP -> 盲目前进 -> 出错才知道"变成了"输入 IP -> 验证连通 -> 确认前进"。

版本号更新到 6.0（v5 评价中指出 Settings 仍显示 "4.0"，这次终于改了）。

**仍然希望：**
- auto-connect 时的 toast 提示（"Connecting to last session: claude..."）
- Onboarding Test Connection 失败时，显示具体错误信息而非只有 "Failed - Check IP"

### 2. 终端可读性 -- 8.5/10（v4: 7 -> v5: 7 -> v6: 8.5，+1.5）

**v6 做了什么：** 动态字体自适应。

连续四个版本被点名的"第二优先级"终于做了。实现在 `SwiftTermView.Coordinator.sizeChanged` 中：当 `newCols < 70` 时，调用 `adaptFontSize`，每次缩小 1pt，最小到 8pt，然后让 SwiftTerm 重新计算布局。SwiftTerm 会再次触发 `sizeChanged`，如果 cols 仍然不够，继续缩小——这是一个递归收敛的过程，直到 cols >= 70 或 fontSize 触底 8pt。

代码实现简洁有效：

```swift
if newCols < 70 {
    adaptFontSize(terminalView: source, currentCols: newCols)
    return // adaptFontSize will trigger another sizeChanged with updated cols
}
```

每次字号调整都写入 DebugLogStore（`.system` 分类），这意味着用户可以在 Debug 面板中看到 "Font adapted: 11pt (cols were 62 < 70)" 这样的记录，方便验证自适应逻辑是否正常工作。

**为什么加 1.5 分这么多：**

这是四个版本的累积债务。iPhone SE/mini 用户在竖屏下从"CC 输出频繁折行导致难以阅读"变成了"自动缩小到合适字号，70 cols 保证 CC 配置界面和代码输出基本不折行"。这是一个从"能用但难受"到"不需要想这件事"的质变。而且 Web 端早就有了——App 在这个维度上从"输"变成了"追平"。

**不满分的原因：**
- 只有缩小逻辑，没有放大逻辑。如果用户从竖屏（自动缩到 10pt）旋转到横屏（宽度足够 12pt），字号不会回升。这意味着横屏下可能用着没必要那么小的字号。
- 没有 pinch-to-zoom 手势。用户不能手动调整。
- 8pt 的下限可能在某些设备上还是太大——但这是一个极端情况，大多数 iPhone 上 8-10pt 应该足够。

**仍然希望：**
- 宽度恢复时自动放大字号（双向自适应）
- pinch-to-zoom 手势
- Settings 中预览不同字号下的终端效果

### 3. 打字体验 -- 9/10（v4: 9 -> v5: 9 -> v6: 9，->）

**v6 做了什么：** 无直接变化。

IMETextField（153 行）从 TerminalView.swift 中拆出成独立文件，但代码逻辑完全未改。diff-based 输入检测、`markedTextRange` 检测 IME 组合状态、`deleteBackward` override、`keyCommands` 处理方向键和 Ctrl 组合——全部保持。

InputAccessoryBar 新增了 `.select` 的 `KeyAction` 枚举值和 `selectButton` 视图，但这属于复制粘贴体验的改进，不是打字体验本身。

NL 按钮、16 键布局、三组分隔线、external keyboard 检测——全部保持。NL 按钮仍然没有按下时的颜色脉冲反馈。

**仍然希望：**
- NL 按钮按下时的颜色脉冲反馈
- 低频键（^Z/^L）长按子菜单收纳

### 4. 滚动浏览 -- 3/10（v4: 3 -> v5: 3 -> v6: 3，->）

**v6 做了什么：** 无变化。

`ScrollGestureHandler`（234 行）代码和 v2 时期完全一致。非线性加速（`pow(absPx / 6.0, 1.6)`）、CADisplayLink 惯性（`decay: 0.95`）、节流（40ms）、长按检测（500ms）——代码写得很完整，但五个版本了，仍然没有任何迹象表明在真机上完整验证过 tmux 的 copy-mode 交互。

v5 评价就说了："四个版本不动一个核心功能，要开始认真考虑这到底是'没时间做'还是'做不了'"。现在是五个版本了。v6 明确以"历史遗留清零"为主题，清掉了动态字号（四版欠债）、断线遮罩（两版欠债）、横屏状态条（一版欠债）、Select 按钮（两版欠债），唯独滚动——v4 评价列出的"第一优先级"——再次被跳过。

到了这个阶段，我倾向于认为这是 SwiftTerm + tmux 的兼容性限制而非优先级问题。如果是优先级问题，v6 的"清零"主题不应该跳过排名第一的项目。如果是技术限制——tmux copy-mode 需要发送特定的键序列进入（`Prefix + [`），SwiftTerm 的滚动回调和 tmux 的 copy-mode 之间可能存在状态同步问题——那应该在某处记录这个结论。

**分数不变的原因：** 滚动代码有写但不可验证。作为"挑剔的日常用户"，如果一个功能五个版本都没在真机上工作过，它和不存在没有区别。CC Opus 的输出动辄上百行，不能回看历史意味着每次要翻回去看，只能重新发一遍 prompt 或者切到 Mac。

**仍然希望：**
- 真机验证完整流程：手指滑动 -> 进入 tmux copy-mode -> 滚动浏览 -> 单击退出
- 浮动 "Exit Scroll" 按钮
- 滚动位置指示条

### 5. 复制粘贴 -- 6.5/10（v4: 5 -> v5: 5 -> v6: 6.5，+1.5）

**v6 做了什么：** 快捷栏 Select 按钮。

这是 v4 评价中列出的"第四优先级"改进。实现路径完整：

1. **InputAccessoryBar** 新增 `.select` 的 `KeyAction`，`selectButton` 用紫色背景（`Color(red: 0.35, green: 0.2, blue: 0.5)`）视觉区分，图标是 `text.cursor`，标签 "Sel"。
2. **TerminalView** 中 `onKey` 回调检测 `.select` 动作，设置 `triggerSelect = true`。
3. **SwiftTermView.updateUIView** 检测 `triggerSelect`，调用 `uiView.showSelectionOverlay(for: termView)`。
4. **TerminalContainerView.showSelectionOverlay** 读取 SwiftTerm 的 `getText(start:end:)` 填充到 UITextView overlay，默认 `selectAll(nil)` 全选。

从用户路径来看，这把复制粘贴的入口从"知道要长按 -> 等 500ms -> overlay 出现 -> 调整选区 -> Done"简化为"按快捷栏 Sel -> overlay 出现 -> 调整选区 -> Done"。关键区别是**可发现性**：紫色的 "Sel" 按钮始终可见在快捷栏里，新用户不需要猜"长按会有什么效果"。

**加 1.5 分的原因：**
- 解决了 v4/v5 评价中反复提到的"可发现性为零"问题。Select 按钮和 NL 按钮一样，是一个"看到就知道能点"的入口。
- 紫色的视觉区分合理——和绿色 NL、灰色功能键形成三级视觉层次。
- 通过 `triggerSelect` binding 实现了 SwiftUI -> UIKit 的单向事件传递，在 `updateUIView` 中 reset，不会重复触发。设计模式干净。

**不满分的原因：**
- overlay 仍然默认 `selectAll(nil)` 全选。日常使用中通常只想选几行，全选后需要拖手柄缩小选区，这比不全选然后从零开始拖选其实更麻烦。
- overlay 上方只有 "Done" 按钮，没有明确的 "Copy" 按钮。虽然 Done 的 `dismissSelectionOverlay` 逻辑中会自动 copy 选中的文本，但用户不一定知道"点 Done 就是 Copy"。应该有一个 "Copy & Close" 的文字标签。
- 长按触发选择和 Sel 按钮触发选择的行为一致（都是全选），没有差异化。可以考虑长按=局部选择，Sel=全选。

**仍然希望：**
- 不默认全选，或者提供"选最后 N 行"的选项
- "Done" 按钮改为 "Copy & Close" 增加语义清晰度
- 选中文本后显示字数/行数统计

### 6. 网络稳定性 -- 9.5/10（v4: 9.5 -> v5: 9.5 -> v6: 9.5，->）

**v6 做了什么：** 两个改进。

**1. NetworkMonitor debounce。** `NetworkMonitor.swift` 新增了 `debounceWorkItem` 和 `debounceInterval: 2.0`。当网络恢复或网络类型切换时（WiFi -> Cellular），不再立即触发 `onNetworkRestored`，而是等 2 秒。如果 2 秒内网络再次变化，取消前一个 `DispatchWorkItem` 并重新计时。网络丢失仍然立即通知（不 debounce）。

这解决了一个真实场景：在电梯、地下通道等信号不稳定的环境中，NWPathMonitor 可能在 1-2 秒内连续报告"断 -> 通 -> 断 -> 通"。v5 会触发多次重连尝试，每次都创建新的 URLSessionWebSocketTask，可能导致资源浪费和连接竞争。v6 的 debounce 把这种场景下的重连次数从可能的 4-5 次降到 1 次。

**2. 断线半透明遮罩。** `TerminalView.disconnectOverlay` 在 WebSocket 断开且不处于 `connecting` 状态时，覆盖一个 50% 透明度的黑色层 + spinner + 状态文字。`allowsHitTesting(false)` 确保遮罩不拦截触摸事件（用户仍然可以操作终端，比如按 ^C）。

断线遮罩是 v4 评价中"网络稳定性唯一未满分的原因"，v5 和 v6 评价中都被列为改进项。现在终于做了。但它的判断条件 `!wsManager.connectionState.isConnected && wsManager.connectionState != .connecting` 意味着在 `reconnecting` 状态下也会显示遮罩——这是合理的，因为重连期间终端内容确实可能过时。

**为什么不加分到 10：** 断线遮罩是正确的 UX 补充，但它不改变网络稳定性本身——v4 的 NWPathMonitor + scenePhase + 指数退避已经让网络体验接近完美。遮罩是"告知用户当前状态"，不是"改善网络恢复速度"。debounce 避免了不必要的重连，但对正常使用几乎无感知（只有信号极差的环境才能体会到区别）。9.5 分已经反映了"网络几乎无感知"的体验等级。

**仍然希望：**
- 遮罩上增加"点击重试"按钮（目前 `allowsHitTesting(false)` 导致遮罩不可交互）
- 断线持续时间计时器显示

### 7. 语音功能 -- 6.5/10（v4: 6 -> v5: 6 -> v6: 6.5，+0.5）

**v6 做了什么：** VoiceManager 完整接入 DebugLogStore。

对比 v5 的代码，v6 的 VoiceManager 新增了以下日志点：
- `configureAudioSession()`: "Audio session configured" 或 "Audio session error: ..."
- `handleVoiceEvent()`: "Voice event: {text prefix}"
- `toggleVoice()`: "Voice toggle requested for session: X" + "Voice toggled: ON/OFF"
- `playAudioData()`: "Playing audio (N bytes)" 或 "Playback error: ..."

v5 评价中明确指出"VoiceManager 没有接入任何日志，Debug 面板的 VOICE 分类形同虚设"——v6 修复了这个遗漏。现在如果用户按了 voice toggle 没反应，摇一摇手机、过滤 VOICE 分类，就能看到是 "Voice toggle requested" 之后卡在了哪一步——是请求没发出、是服务端返回了错误、还是音频下载/播放出了问题。

**加 0.5 分的原因：** 日志接入让语音功能从"出了问题只能猜"变成了"出了问题可以查"。这是诊断能力的实质提升，虽然不改变功能本身的能力上限。

**分数上限仍然受限的原因：** 核心限制没有改变——多段语音仍然互相 cancel（`downloadTask?.cancel()` 在 `handleVoiceEvent` 开头）、没有音量/语速控制、`lastSpokenText` 仍然不在 UI 中展示。这些是语音功能作为日常工具的实用性上限。

**仍然希望：**
- 多段语音排队播放（队列而非覆盖）
- 语速控制（0.5x / 1.0x / 1.5x / 2.0x）
- 播放时顶栏显示当前朗读文本摘要

### 8. 通知功能 -- 6.5/10（v4: 6 -> v5: 6 -> v6: 6.5，+0.5）

**v6 做了什么：** NotificationManager 完整接入 DebugLogStore。

新增日志点：
- `requestPermission()`: "Notification permission: granted/denied"
- `scanTerminalOutput()`: "Completion pattern matched, sending notification"
- `handleNotifyEvent()`: "Notify event: title - body"
- `sendNotification()`: "Notification send error: ..."

逻辑和语音相同——从"不可诊断"变成"可诊断"。如果用户说"我后台了但没收到通知"，Debug 日志可以确认是"permission denied"还是"pattern 没 match"还是"cooldown 被限流了"。

**加 0.5 分的原因同语音：** 诊断能力提升，功能本身未变。

**仍然希望：**
- 通知内容包含 CC 输出的最后一行摘要（而非固定 "Task completed in session X"）
- 模式匹配可配置
- 通知设置页面（开/关、cooldown 时长）

### 9. 多 session 管理 -- 8.5/10（v4: 7.5 -> v5: 8 -> v6: 8.5，+0.5）

**v6 做了什么：** 横屏迷你状态条。

`TerminalView.landscapeMiniStatusBar` 在横屏模式下渲染一个 16pt 高的半透明条，包含：
- 连接状态点（绿/黄/红，6px 圆形）
- session 名（10pt 等宽字体，灰色）
- SCROLL 标签（8pt 粗体，黄底黑字，条件显示）
- 连接状态文字（9pt，靠右）

背景是 `Color.black.opacity(0.6)`，半透明可以隐约看到被遮挡的终端内容。16pt 的高度只占用大约一行终端的空间，对于横屏下本就有限的垂直高度来说是一个合理的 trade-off。

这精准地解决了 v5 评价中"横屏隐藏顶栏后连接状态完全不可见"的问题。现在横屏下用户能看到：
1. 自己在哪个 session（session 名）
2. 连接是否正常（状态点 + 文字）
3. 是否在滚动模式（SCROLL 标签）

**加分的原因：** v5 的横屏优化做了"减"（隐藏顶栏），但遗漏了"补"（状态信息缺失）。v6 的迷你状态条完成了"补"。横屏从"多了空间但丢了信息"变成了"多了空间且保留关键信息"。

横屏下 session 切换仍然依赖顶部边缘下滑手势（`landscapeSwipeGesture`），可发现性问题未解决。但迷你状态条中的 session 名至少暗示了"session 是一个可操作的概念"。

**仍然希望：**
- 迷你状态条的 session 名可点击（触发 session switcher）
- session 列表支持下拉刷新
- 横屏下滑手势的 affordance 提示

### 10. 整体完成度 -- 9.2/10（v4: 8.5 -> v5: 8.8 -> v6: 9.2，+0.4）

**v6 新增功能的价值排序：**

**第一：动态字体自适应。** 四个版本的欠债，终于清了。这是 v6 对日常使用体验影响最大的改进。iPhone SE/mini 用户从"频繁折行"变成了"自动适配"。Web 端长期领先的维度被追平。

**第二：断线半透明遮罩。** 两个版本的欠债。视觉反馈从"什么都看不出来"变成了"一眼就知道断了"。spinner + 状态文字让用户知道 App 正在尝试重连，不需要手动操作。

**第三：横屏迷你状态条。** 一个版本的欠债。补上了 v5 横屏优化的遗漏。16pt 的高度是正确的平衡点。

**第四：快捷栏 Select 按钮。** 两个版本的欠债。复制粘贴的可发现性从"长按猜测"变成了"按钮直达"。紫色视觉区分合理。

**第五：DebugLogStore 完整接入。** 一个版本的欠债。FileUploadManager（v5 的遗漏）、VoiceManager、NotificationManager 全部接入。六个 category（WS/NET/VOICE/UPLOAD/SYS/ERR）全部有实际数据流入，Debug 面板不再有形同虚设的过滤器。

**第六：Onboarding Test Connection。** 首次启动体验的最后一块拼图。

**v6 的核心价值：系统性还债。**

六个改进中有五个是回应之前评价中明确提出的改进项。这是一种成熟的工程判断——在 TestFlight 之前把已知的 UX 债务清掉，而不是追求新功能。

**对照 v5 评价的"最想要的 5 个改进"：**

| 优先级 | v5 评价提出的改进 | v6 是否完成 |
|--------|------------------|------------|
| 1 | 真机验证触摸滚动 | 未做 |
| 2 | 动态字号适配 | 已做 |
| 3 | 断线时半透明遮罩 | 已做 |
| 4 | 横屏模式下迷你状态条 | 已做 |
| 5 | FileUpload/Voice/Notification 接入 DebugLogStore | 已做 |

5 个中做了 4 个。唯一缺席的是排名第一的滚动。但考虑到 v6 同时还做了快捷栏 Select 按钮和 Onboarding Test Connection（之前评价中也提过但没进前五），实际回应的改进项数量达到了 6 个。这个执行率在整个迭代历程中是最高的。

**代码架构的变化：**

v6 Phase 1 把 TerminalView.swift 拆成了四个文件：

| 文件 | v5 行数（估算） | v6 行数 | 职责 |
|------|--------------|---------|------|
| TerminalView.swift | ~330 (v5 拆分后) | 226 | 布局、生命周期、事件分发 |
| SwiftTermView.swift | (嵌在 TerminalView 中) | 196 | SwiftTerm UIViewRepresentable + delegate |
| TerminalContainerView.swift | (嵌在 TerminalView 中) | 208 | UIView 容器、触摸路由、选择 overlay |
| IMETextField.swift | (嵌在 TerminalView 中) | 153 | 输入代理、IME 处理 |

v5 的 TerminalView 约 330 行（v5 已经从 v4 的 ~980 行拆出了 TerminalToolbar 和 SessionSwitcher），v6 进一步拆到 226 行核心逻辑 + 3 个独立文件。总代码量没有减少（反而因为新功能略有增加），但每个文件的职责更加单一。

整个 App 现在有 20 个 .swift 文件、3571 行代码。对于一个带终端渲染、WebSocket 通信、语音播放、文件上传、Push 通知、Debug 面板的 App 来说，这个规模相当克制。

## 分数变化汇总

| 维度 | v2 | v3 | v4 | v5 | v6 | v5->v6 变化 |
|------|-----|-----|-----|-----|-----|------------|
| 1. 首次启动体验 | 7 | 7 | 8.5 | 8.5 | 9 | +0.5 |
| 2. 终端可读性 | 7 | 7 | 7 | 7 | 8.5 | +1.5 |
| 3. 打字体验 | 6 | 8 | 9 | 9 | 9 | -> |
| 4. 滚动浏览 | 2 | 3 | 3 | 3 | 3 | -> |
| 5. 复制粘贴 | 4 | 5 | 5 | 5 | 6.5 | +1.5 |
| 6. 网络稳定性 | 7 | 9 | 9.5 | 9.5 | 9.5 | -> |
| 7. 语音功能 | 6 | 6 | 6 | 6 | 6.5 | +0.5 |
| 8. 通知功能 | 6 | 6 | 6 | 6 | 6.5 | +0.5 |
| 9. 多 session 管理 | 5 | 6.5 | 7.5 | 8 | 8.5 | +0.5 |
| 10. 整体完成度 | 5 | 7.5 | 8.5 | 8.8 | 9.2 | +0.4 |
| **总评** | **5.5** | **7.5** | **8.5** | **8.8** | **9.2** | **+0.4** |

**提分的维度：** 首次启动 (+0.5)、终端可读性 (+1.5)、复制粘贴 (+1.5)、网络稳定性 (->，但新增遮罩)、语音 (+0.5)、通知 (+0.5)、多 session (+0.5)、整体完成度 (+0.4)
**未改变的维度：** 打字体验 (9)、滚动浏览 (3)
**v5->v6 有分数变化的维度：** 7 个（迭代历程中最多，v4->v5 只有 2 个）

## 六版迭代总回顾

### 版本人格

| 版本 | 主题词 | 关键交付 | 提分幅度 |
|------|--------|---------|---------|
| v2 | "存在" | MVP：SwiftTerm + WebSocket + 基本 UI | 基线 5.5 |
| v3 | "可用" | IME 输入修复、触觉反馈、安全区域 | +2.0 |
| v4 | "好用" | NL 按钮、网络感知、auto-connect | +1.0 |
| v5 | "完善" | 文件上传、Debug 面板、代码拆分 | +0.3 |
| v6 | "还债" | 动态字号、断线遮罩、Select 按钮、迷你状态条 | +0.4 |

v2 -> v3 是从"勉强能用"到"可以作为工具"的跨越。v3 -> v4 是从"能用的工具"到"好用的工具"的提升。v4 -> v5 是低频功能补充和工程整理。v5 -> v6 是系统性清零和 TestFlight 准备。

增速曲线（+2.0 -> +1.0 -> +0.3 -> +0.4）显示 v3 是最大的一次跳跃，此后进入精细优化阶段。v6 的 +0.4 比 v5 的 +0.3 略高，说明"对着问题清单逐条打勾"比"选自己想做的功能"更能提升用户体验评分。

### 从 5.5 到 9.2 的核心变化

**v2 的 5.5 分意味着什么：** 能连上、能显示、能打字，但 IME 不工作、没有快捷键、网络断了没有任何反馈、不能回看历史、不能复制文本。一个"技术验证级"的产品。

**v6 的 9.2 分意味着什么：** 打开 App -> 自动连接上次 session -> 1-2 秒进入终端 -> 字号自动适配屏幕 -> 中文输入无问题 -> 16 键快捷栏覆盖所有常用操作 -> 网络断了有遮罩提示、恢复后自动重连 -> 可以上传文件 -> 可以语音朗读 -> 后台有推送 -> 横屏有迷你状态条 -> 出了问题摇一摇看日志。一个"日常工具级"的产品。

**3.7 分的差距来自哪里：**
- 输入系统：+3（v2 的 6 -> v4 的 9）。IME 修复 + NL 按钮 + 16 键布局。
- 网络感知：+2.5（v2 的 7 -> v4 的 9.5）。NWPathMonitor + scenePhase + 指数退避 + debounce。
- 首次启动：+2（v2 的 7 -> v6 的 9）。auto-connect + Test Connection。
- 多 session：+3.5（v2 的 5 -> v6 的 8.5）。session switcher + 横屏手势 + 迷你状态条。
- 复制粘贴：+2.5（v2 的 4 -> v6 的 6.5）。长按 overlay + Select 按钮。
- 终端可读性：+1.5（v2 的 7 -> v6 的 8.5）。动态字号。
- 整体完成度：+4.2（v2 的 5 -> v6 的 9.2）。文件上传、Debug 面板、代码架构。

### 未满分的两个短板

**滚动浏览（3/10）** 是整个迭代历程中唯一从未实质改善的维度。从 v2 的 2 分到 v3 的 3 分（加了代码但没验证），之后五个版本纹丝不动。这是 App 的最大短板，也是唯一一个让评分无法突破 9.5 的系统性问题。

**语音和通知（各 6.5/10）** 的核心限制是功能设计层面的——多段语音覆盖、通知内容固定、不可配置。这些需要的不是 bug fix 而是功能迭代，属于"做到了基本可用但没有做到好用"的状态。

## TestFlight 就绪度评估

### 可以上架的理由

1. **核心功能闭环完整：** 启动 -> 配置服务器 -> 连接 session -> 终端交互 -> 断线恢复 -> 切换 session。每个环节都有 UI 反馈和错误处理。
2. **首次使用体验达标：** Onboarding 3 页介绍 + 配置页 + Test Connection，新用户不会迷路。
3. **终端渲染质量合格：** 动态字号保证各尺寸 iPhone 都能达到 70 cols。主题可切换。
4. **输入系统稳定：** IME diff-based 模型经过多版本验证，中英文输入可靠。16 键快捷栏覆盖日常操作。
5. **网络鲁棒性高：** 指数退避重连 + NWPathMonitor + scenePhase + debounce，Tailscale VPN 环境下几乎无感知。
6. **Debug 支持完善：** shake-to-open 日志面板，全子系统接入，可导出。TestFlight 用户遇到问题可以立即提供诊断信息。
7. **代码架构清晰：** 20 个文件、3571 行，职责分明。没有上千行的巨型文件。后续维护和迭代的心智负担低。
8. **版本号已更新：** MARKETING_VERSION 6.0，Settings 页面显示正确。

### 上架前建议修复的问题

**P0（阻塞）：** 无。没有发现会导致 crash 的代码路径（v5 已修复 force unwrap）。

**P1（强烈建议）：**
1. **PhotoPicker 文件名 double extension：** `result.assetIdentifier ?? "photo_\(...)".jpg"` 再拼 `+ ".jpg"`，可能产生 `ABC123.jpg.jpg`。应该在拼接前检查是否已有 `.jpg` 后缀。
2. **上传 progress 不准确：** 使用 `URLSessionDataTask` 的 `progress.observe` 跟踪上传进度，但 `httpBody` 一次性设置后进度可能直接跳 0->1。TestFlight 用户看到进度条可能会困惑。建议要么改用 `URLSessionUploadTask`，要么简单使用一个 indeterminate spinner 代替进度环。

**P2（建议但不阻塞）：**
3. 动态字号只缩不放——横屏后字号不会回升。
4. Select overlay 默认全选——不符合多数"选择部分文本"的使用场景。
5. 断线遮罩不可交互（`allowsHitTesting(false)`）——无法手动触发重连。
6. Onboarding Test Connection 失败时不显示具体错误原因。

### TestFlight 综合就绪度：85/100

App 的功能完整性和稳定性已经达到了 TestFlight 的门槛。剩余 15 分的扣分来自：滚动功能不可用（-8）、两个 P1 代码问题（-4）、语音/通知功能的基本可用但不够好用（-3）。

## 对比 Web 终端（最终版）

| 维度 | Web | App v6 | 赢家 | v5->v6 变化 |
|------|-----|--------|------|------------|
| 首次配置 | 打开 URL 即用 | Onboarding + Test Connection | Web（但差距缩小） | App 改善 |
| 启动速度 | 依赖 CDN 加载 | 原生秒开 + auto-connect | App | -> |
| 终端渲染质量 | xterm.js canvas | SwiftTerm 原生 | App | -> |
| 快捷键栏 | 12 个按钮 | 17 个 + 分组 + NL + Sel + compact | App | App 新增 Sel |
| 触摸滚动 | 非线性加速，已验证 | 代码完整，未经实测 | Web | -> |
| 文本选择/复制 | Select mode + overlay | Sel 按钮 + 长按 overlay + haptic | App（可发现性）| App 改善 |
| 连接状态 | 无明确指示 | 四态 + NWPathMonitor + NO NET + 遮罩 | App | App 新增遮罩 |
| 断线重连 | 指数退避 | 指数退避 + 前后台 + 网络感知 + debounce | App | App 新增 debounce |
| 文件上传 | POST /api/upload | PHPicker + DocPicker + progress | 平手 | -> |
| 动态字体 | 自动适配 cols >= 70 | sizeChanged 自动适配 cols >= 70 | 平手 | Web -> 平手 |
| 横屏体验 | 浏览器自适应 | 隐藏 toolbar + 迷你状态条 + compact | App | App 改善 |
| 调试能力 | 浏览器 DevTools | shake Debug Panel（全子系统） | 平手 | App 改善 |
| 触觉反馈 | 无 | 6 种场景 | App | -> |

**v6 在动态字体上追平了 Web 端，App 仍然输的核心维度只剩 1 个：触摸滚动未实测。** 这是从 v4 对比中的 3 个输项（滚动、动态字号、文件上传）逐步缩减到 v5 的 2 个、v6 的 1 个的过程。

App 赢的维度：启动速度、终端渲染、快捷键栏、连接状态、断线重连、横屏体验、触觉反馈（7 个）。
平手的维度：文本选择/复制、文件上传、动态字体、调试能力（4 个）。
Web 赢的维度：首次配置、触摸滚动（2 个）。

## 会不会推荐给朋友？

**推荐，并且推荐的措辞要比 v5 更积极。**

如果朋友问"v6 比 v5 好在哪？"，我会说："字号终于会自动适配了，断线会有半透明遮罩告诉你，横屏下有迷你状态条，快捷栏多了个 Select 按钮方便复制，Debug 日志全部接通了。简而言之，之前版本所有被吐槽的小问题，这一版基本都修了。"

如果朋友问"值不值得从 v5 升级？"，我会说："值得，而且建议立刻升级。动态字号和断线遮罩是日常使用中每天都会感受到的改善。"

如果朋友问"能上 TestFlight 了吗？"，我会说："可以了。核心功能闭环完整，没有 crash 风险，有 Debug 面板方便反馈问题。唯一要管理预期的是滚动功能——别指望能像 Web 版那样流畅回看历史。"

## 如果还有 v7——最值得做的 3 件事

### 1. 真机验证并修通触摸滚动
五个版本的欠债。这是 App 和 Web 端最后一个功能差距。也是日常使用中最高频的痛点——CC 的回复越来越长，不能回看就意味着信息丢失。如果 SwiftTerm + tmux copy-mode 有兼容性问题，考虑绕过 tmux 的 copy-mode、直接在 SwiftTerm 的 scrollback buffer 上实现本地滚动。

### 2. Select overlay 不默认全选 + "Copy" 按钮
当前的 `selectAll(nil)` 在大多数场景下是错误的默认行为。更好的做法：overlay 打开后光标在文末，用户需要手动选择想要的范围。Done 按钮改为明确的 "Copy & Close"。

### 3. 语音队列播放
当前 `downloadTask?.cancel()` 导致多段语音互相覆盖。实现一个简单的 FIFO 队列，前一段播完再播下一段。这会让语音功能从"只能听最后一段"变成"完整听完所有内容"。
