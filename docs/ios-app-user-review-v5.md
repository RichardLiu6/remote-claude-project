# iOS App v5 用户体验评价

## 总评：8.8/10（v2: 5.5 -> v3: 7.5 -> v4: 8.5 -> v5: 8.8，+0.3）

## 一句话感受

v5 是一个"还债 + 补齐"的版本。它做了 v4 评价中 Web 端最后仍然赢的两件事之一——文件上传——同时做了一次早该做的代码架构清理。横屏优化和 Debug 面板是加分项，但不改变日常使用的核心体验。这一版的主题词是"完善"：该补的功能补了，该拆的代码拆了，该修的 crash 修了。但"完善"不等于"突破"——v5 没有像 v4 的 NL 按钮或网络感知那样给日常工作流带来质变。

## 详细评分

### 1. 首次启动体验 -- 8.5/10（v4: 8.5 -> v5: 8.5，->）

**v5 做了什么：** 无直接变化。

启动缓存（auto-connect to last session）延续 v4 的逻辑，`SessionPickerView` 的 `loadSessions()` + `autoConnectIfPossible()` 代码完全未动。`hasAttemptedAutoConnect` 防重复进入机制仍在。打开 App -> 自动进入上次 session -> 1-2 秒可用，这个体验保持不变。

有一个间接变化值得注意：`fetchSessions` 的 `URL(string:)!` force unwrap 被修复为 `guard let url = URL(string:) else { throw URLError(.badURL) }`。这意味着如果用户在设置页输入了一个格式错误的 host（比如多了空格或特殊字符），v4 会直接 crash，v5 会优雅地显示错误信息。这不是一个"启动体验改进"，但它是一个"启动不会挂掉"的保障。从用户体验评分角度，防 crash 属于基本要求而非加分项，所以分数不变。

**仍然希望：**
- 首次启动引导（开 Tailscale -> 跑脚本 -> 输入 IP）
- 设置页"Test Connection"按钮
- auto-connect 时的 toast 提示
- 设置页版本号仍显示 "4.0"，v5 忘记更新了

### 2. 终端可读性 -- 7/10（v4: 7 -> v5: 7，->）

**v5 做了什么：** 横屏时隐藏顶栏。

`TerminalView` 在 `GeometryReader` 中检测 `geometry.size.width > geometry.size.height`，横屏时 `TerminalToolbar` 整个不渲染（`if !landscape`）。这让终端区域在横屏下多了大约 44pt 的垂直空间——在 iPhone 横屏本来就非常有限的高度中，多一行半终端内容。

横屏模式下 `InputAccessoryBar` 的 `isCompact` 参数生效，按钮高度从 44pt 降为 34pt，字号从 14 降为 12，padding 缩小。这也额外省了 10pt 给终端。

但核心的可读性问题——动态字号适配——仍然没动。连续四个版本了。`SwiftTermView.makeUIView` 中 `termView.font` 设置完就再也不改了，`sizeChanged` 回调中只做了 resize 发送，完全没有检查 `newCols` 是否足够。在 iPhone SE/mini 上 12pt 字号只有约 55 cols，CC 的输出会频繁折行。横屏下因为宽度增加，cols 可能够了，但竖屏问题依旧。

**横屏隐藏顶栏的代价：** 用户看不到连接状态、NO NET 标签、SCROLL 标签、session 名。v5 的补偿方案是一个从顶部边缘向下滑动的手势，触发 session switcher sheet。但这个手势（`DragGesture` with `value.startLocation.y < 44`）不够直观——用户怎么知道可以从顶部下滑？没有任何视觉提示。而且它只能打开 session switcher，不能看到连接状态或 NO NET 标签。横屏下如果网络断了，用户看不到任何提示。

**评分不变的原因：** 横屏优化是正确方向但执行不够完整（连接状态丢失），动态字号连续缺失，两者相互抵消。

**仍然希望：**
- 自动检测 cols，不足 70 时自动缩小字号
- 横屏下用一个极简的半透明状态条代替完全隐藏（比如只显示连接状态点 + session 名的迷你条）
- pinch-to-zoom 手势

### 3. 打字体验 -- 9/10（v4: 9 -> v5: 9，->）

**v5 做了什么：** `InputAccessoryBar` 加了 `isCompact` 模式。

横屏时按钮变小了——字号 14->12，padding 14/6->10/4，整体高度 44->34。这让横屏下快捷栏占用更少空间的同时仍然可用。按键的手感会因为热区缩小而略差，但横屏下手指到按钮的距离更短（屏幕高度有限），所以影响不大。

NL 按钮、16 键布局、三组分隔线、外接键盘自动隐藏——这些 v4 的核心打字体验全部保持。代码只有尺寸数值的调整，逻辑完全一致。

**为什么不加分：** compact 模式是横屏优化的配套改动，不是打字体验本身的改进。v4 遗留的"Select/Paste 按钮缺失"和"NL 按钮按下反馈"问题仍然存在。

**仍然希望：**
- 快捷栏加 Select/Paste 按钮
- NL 按钮按下时的颜色脉冲反馈
- 低频键长按子菜单收纳

### 4. 滚动浏览 -- 3/10（v4: 3 -> v5: 3，->）

**v5 做了什么：** 无直接变化。

`ScrollGestureHandler` 代码和 v4 完全一致——非线性加速、惯性、长按检测、节流，代码写得很完整，但连续四个版本没有任何迹象表明在真机上验证过完整的滚动流程。

四个版本不动一个核心功能，要开始认真考虑这到底是"没时间做"还是"做不了"。如果是 SwiftTerm 和 tmux scroll 协议之间存在兼容性问题导致无法工作，那应该在某个版本记录下来。如果只是优先级排序的问题——那 v5 选择做文件上传和 Debug 面板而不是修滚动，说明团队认为文件上传比回看历史更重要。从日常使用角度，我不同意这个判断。

**仍然希望：**
- 真机验证完整流程
- 浮动 "Exit Scroll" 按钮
- 滚动位置指示条

### 5. 复制粘贴 -- 5/10（v4: 5 -> v5: 5，->）

**v5 做了什么：** 无直接变化。

长按 -> overlay -> 全选 -> Done 按钮复制的流程保持不变。快捷栏仍然没有 Select 按钮。overlay 仍然默认 `selectAll(nil)` 全选。可发现性问题完全没有改善。

v4 评价中明确列出了"快捷栏加 Select 按钮"作为第四优先级改进项，但 v5 没有做。

**仍然希望：**
- 快捷栏 Select 按钮
- 不默认全选
- overlay 上方加 Copy 按钮

### 6. 网络稳定性 -- 9.5/10（v4: 9.5 -> v5: 9.5，->）

**v5 做了什么：** 两个间接改进。

**1. fetchSessions force unwrap 修复。** `URL(string:)!` -> `guard let url = URL(string:) else { throw URLError(.badURL) }`。这修复了一个潜在的 crash 路径——如果 `config.baseURL` 包含非法 URL 字符（空格、中文等），`URL(string:)` 返回 nil，force unwrap 直接崩。v5 把它变成了一个优雅的错误传播。从网络稳定性角度，防 crash 是加分的，但这个 bug 触发概率极低（需要用户手动输入错误的 host），所以不影响评分。

**2. DebugLogStore 日志集成。** `WebSocketManager` 的 `establishConnection()` 和 `receiveMessage()` 中新增了 `DebugLogStore.shared.log(...)` 调用。`NetworkMonitor` 的状态变化也有日志。这不直接改善网络稳定性，但大幅改善了网络问题的可诊断性——当用户遇到连接问题时，摇一摇手机就能看到完整的 WS 连接/断开/重连日志、网络类型切换记录。以前出了问题只能猜，现在有了 console 级别的调试能力。

**为什么不加分：** 诊断能力的提升是间接价值。v4 的 9.5 分已经是基于"几乎无感知"的网络体验给出的——NWPathMonitor + scenePhase 重连 + NO NET 标签。v5 没有改变任何网络行为本身。断线时终端区域的半透明遮罩仍然缺失——这是 v4 评价中唯一未满分的原因，v5 没有解决。

**仍然希望：**
- 断线时终端区域半透明遮罩
- 横屏下的连接状态显示（目前完全隐藏）

### 7. 语音功能 -- 6/10（v4: 6 -> v5: 6，->）

**v5 做了什么：** 无直接变化。VoiceManager 代码和 v4 完全一致。

DebugLogStore 预留了 `.voice` category，但 `VoiceManager` 本身没有接入任何日志。如果接入了（下载开始/完成/播放开始/结束），Debug 面板就能诊断语音问题——比如"为什么按了 voice toggle 没声音"。这是一个遗漏。

连续四个版本没有改动。多段语音互相 cancel、无音量/语速控制、`lastSpokenText` 没有在 UI 展示。

**仍然希望：**
- 多段语音排队播放
- VoiceManager 接入 DebugLogStore
- 语速控制
- 播放时顶栏显示文本摘要

### 8. 通知功能 -- 6/10（v4: 6 -> v5: 6，->）

**v5 做了什么：** 无直接变化。NotificationManager 代码和 v4 完全一致。

和语音一样，连续四个版本没有改动。通知内容仍然是固定的 "Task completed in session X"，没有 CC 输出的最后一行摘要。模式匹配硬编码（emoji + 固定字符串），不可配置。

**仍然希望：**
- 通知内容包含 CC 输出摘要
- 模式匹配可配置
- NotificationManager 接入 DebugLogStore

### 9. 多 session 管理 -- 8/10（v4: 7.5 -> v5: 8，+0.5）

**v5 做了什么：** `SessionSwitcherSheet` 独立为文件，横屏下可通过手势唤出。

v4 的 session switcher 是嵌在 `TerminalView` 内部的一个巨大 `sheet` block。v5 把它拆成了独立的 `SessionSwitcherSheet.swift`，代码更清晰，但对用户来说 UI 和交互完全一致——同样的半屏 sheet、同样的当前 session 绿色标记、同样的 windows 数量和时间显示。

真正的用户可感知变化是：**横屏模式下，顶栏被隐藏了，原本点击 session 名触发 switcher 的入口消失了。** v5 补偿了一个从顶部边缘下滑的手势来唤出 session switcher。这个手势能用，但有两个问题：

1. **可发现性为零。** 没有任何 UI 元素暗示"从顶部下滑可以切换 session"。新用户在横屏下完全不知道怎么切 session。
2. **手势阈值设计。** `value.startLocation.y < 44` 要求起始点在屏幕最上方 44pt 以内，`value.translation.height > 50` 要求至少下滑 50pt。在横屏下 iPhone 的总高度大约 375pt，上方 44pt 是一个很窄的触发区域。而且 iPhone 的刘海/灵动岛正好在这个位置，实际可触摸区域更小。

**加 0.5 分的原因：** 横屏下总算有了切 session 的方式（v4 横屏下没有单独处理，应该也是通过顶栏操作）。代码拆分让 session 相关的逻辑更容易维护和迭代。但手势的可发现性问题限制了加分幅度。

**仍然希望：**
- 横屏下保留一个迷你 session 名按钮
- 手势下滑时显示一个短暂的 "Release to switch session" 提示
- session 列表支持下拉刷新

### 10. 整体完成度 -- 8.8/10（v4: 8.5 -> v5: 8.8，+0.3）

**v5 新增功能的价值排序：**

**第一：文件上传（FileUploadManager）。** 这是 v4 评价中 App 对 Web 端输的三个维度之一（滚动、动态字号、文件上传）。v5 补上了其中一个。

`FileUploadManager` 的实现完整度很高：
- **两个来源：** PHPicker（照片库）和 UIDocumentPicker（文件），通过 `confirmationDialog` 让用户选择。
- **progress 追踪：** 上传过程中 toolbar 的按钮图标变为 `arrow.up.circle` + 紫色圆形进度环。上传成功后变绿色 checkmark，3 秒后自动重置为 idle。上传失败变红色感叹号。
- **multipart/form-data：** 正确的 boundary + Content-Disposition + Content-Type 构建。JPEG 压缩质量 0.85，文件 MIME type 通过 `UTType` 自动检测。
- **security-scoped resource：** document picker 的文件正确调用了 `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`。
- **错误处理：** 文件读取失败、URL 无效、HTTP 非 200、网络错误——每种情况都有对应的 `.error(String)` 状态。

从日常使用场景来看：给 CC 发一张截图（"看看这个 bug 的报错截图"）或一个文件（"帮我分析这个 CSV"），以前只能通过 Mac 端操作或者 Web 终端的上传功能。现在 App 也能做了。这个功能的使用频率不高（也许一天 1-2 次），但在需要的时候非常关键——没有它就得切到 Mac 或 Web 端。

**但有几个细节问题：**
- `PhotoPicker` 的 filename 使用了 `result.assetIdentifier ?? "photo_\(Int(Date().timeIntervalSince1970)).jpg"`，然后又拼了一个 `.jpg` 后缀。如果 assetIdentifier 本身包含扩展名，就会变成 `ABC123.jpg.jpg`。
- 上传 progress 使用的是 `task.progress.observe(\.fractionCompleted)`，但 `URLSessionDataTask` 的 progress 对于上传并不总是准确——它跟踪的是 request body 的发送进度，而 body 已经一次性设置为 `httpBody`，所以实际上进度可能直接从 0 跳到 1。要准确跟踪上传进度应该使用 `URLSessionUploadTask` + delegate。
- 上传按钮在 toolbar 中的位置（clipboard 按钮左边）在已经挤了 6 个按钮的顶栏中显得有点拥挤。

**第二：Debug 面板（DebugLogPanel + DebugLogStore）。** 摇一摇手机打开 debug 日志——这是一个开发者级别的功能，普通用户可能永远不会用到。但对于我这种需要排查连接问题的用户来说，它非常有价值。

实现细节：
- **DebugLogStore 单例：** 最多保留 500 条日志，每条有时间戳（精确到毫秒）、分类（WS/NET/VOICE/UPLOAD/SYS/ERR）、消息文本。
- **分类过滤：** 顶部的 filter chips 可以只看某一类日志，比如只看 WS 事件或只看 ERR。
- **自动滚动：** 新日志进来时 `ScrollViewReader` 自动滚到底部。
- **导出：** 通过 `UIActivityViewController` 分享为纯文本。
- **触发方式：** `ClaudeTerminalApp` 中注册了 `UIWindow.motionEnded` 的 shake 检测，通过 `NotificationCenter` 传递到 `TerminalView` 打开 sheet。

这个功能的架构设计值得认可：`DebugLogStore` 是全局单例，任何模块都可以往里写日志，不需要传递引用。但当前只有 `WebSocketManager` 和 `NetworkMonitor` 接入了日志，`VoiceManager`、`NotificationManager`、`FileUploadManager` 都还没接入。特别是 `FileUploadManager`——作为 v5 新增的功能，DebugLogStore 也有 `.upload` 分类，但 `FileUploadManager` 里一行 `DebugLogStore.shared.log` 都没有。这是一个明显的遗漏。

**第三：代码架构拆分（TerminalToolbar + SessionSwitcher）。** TerminalView.swift 从 v4 的约 980 行减少到当前的 ~330 行核心终端逻辑。TerminalToolbar.swift ~187 行，SessionSwitcher.swift ~67 行。纯粹的代码组织优化，用户完全无感知，但对后续维护和迭代是正确的投入。

**第四：横屏优化。** 横屏隐藏顶栏 + compact 快捷栏。思路正确，但如前所述，执行不够完整——连接状态信息的丢失是一个实际问题。

**v5 对日常工作流的影响有多大？**

坦率地说，不大。文件上传一天也许用 1-2 次，Debug 面板也许一周用一次。横屏模式大多数人竖着用手机。相比 v4 的三个核心改进（NL 按钮每天用 50 次、网络感知随时在工作、auto-connect 每次启动受益），v5 的改进都是低频场景。

这就是为什么 v4->v5 只给了 +0.3 而不是 v3->v4 的 +1.0。v4 解决了高频痛点，v5 补充了低频功能。两者都有价值，但带来的体验提升量级不同。

**v5 没做的事——对照 v4 评价的"最想要的 5 个改进"：**

1. 真机验证触摸滚动 -- 没做（第一优先级）
2. 动态字号适配 -- 没做（第二优先级）
3. 断线时半透明遮罩 -- 没做（第三优先级）
4. 快捷栏 Select 按钮 -- 没做（第四优先级）
5. 首次启动引导 -- 没做（第五优先级）

v4 评价列出的前五优先级一个都没做。v5 做的是文件上传（v4 对比表中的弱项）、代码重构、横屏优化、Debug 面板——这些都是有价值的工作，但不是 v4 评价认为最重要的事。

## 分数变化汇总

| 维度 | v2 | v3 | v4 | v5 | v4->v5 变化 |
|------|-----|-----|-----|-----|------------|
| 1. 首次启动体验 | 7 | 7 | 8.5 | 8.5 | -> |
| 2. 终端可读性 | 7 | 7 | 7 | 7 | -> |
| 3. 打字体验 | 6 | 8 | 9 | 9 | -> |
| 4. 滚动浏览 | 2 | 3 | 3 | 3 | -> |
| 5. 复制粘贴 | 4 | 5 | 5 | 5 | -> |
| 6. 网络稳定性 | 7 | 9 | 9.5 | 9.5 | -> |
| 7. 语音功能 | 6 | 6 | 6 | 6 | -> |
| 8. 通知功能 | 6 | 6 | 6 | 6 | -> |
| 9. 多 session 管理 | 5 | 6.5 | 7.5 | 8 | +0.5 |
| 10. 整体完成度 | 5 | 7.5 | 8.5 | 8.8 | +0.3 |
| **总评** | **5.5** | **7.5** | **8.5** | **8.8** | **+0.3** |

**提分的维度：** 多 session 管理 (+0.5)、整体完成度 (+0.3)
**未改变的维度：** 首次启动、终端可读性、打字体验、滚动浏览、复制粘贴、网络稳定性、语音、通知（8 个维度没动）
**评分趋势：** v2(5.5) -> v3(7.5) -> v4(8.5) -> v5(8.8)。增速明显放缓：+2.0 -> +1.0 -> +0.3

## v5 新增功能深度评价

### 文件上传解决了多少功能缺口？

v4 评价的对比表中 App 输给 Web 端的三个维度：滚动浏览（3 vs 8）、动态字号（无 vs 有）、文件上传（无 vs 有）。v5 补上了文件上传，App 输的维度从 3 个减少到 2 个。

**使用场景分析：**
- 给 CC 发截图让它分析报错 -> photo picker -> 上传 -> CC 可以在 cwd 找到文件（如果服务端 /api/upload 把文件存到了 session 的 cwd）
- 发一个配置文件让 CC 修改 -> document picker -> 上传
- 上传频率估计：每天 0-3 次，低频但关键

**实现质量评估：**
- 架构完整：picker -> manager -> multipart POST -> progress -> status icon，全链路有反馈
- 错误覆盖全面：读取失败、URL 无效、HTTP 错误、网络错误
- 但 progress 追踪可能不准确（用了 dataTask 而非 uploadTask）
- PhotoPicker 的 filename 拼接有 double extension 风险
- FileUploadManager 没接入 DebugLogStore（尽管有 `.upload` category）

### Debug 面板的实际价值？

**开发者视角：** 非常有用。在通勤环境中遇到连接问题时，以前只能盲猜原因（网络？服务器？WebSocket?），现在摇一摇就能看到时间轴日志。category filter 让排查更精准——比如只看 ERR 类日志。export 功能可以把日志发给自己事后分析。

**普通用户视角：** 几乎没用。不知道摇一摇会弹出什么，看到了也不知道日志在说什么。但这无所谓——它只在需要时出现，不影响正常使用。shake 触发不会误触（需要明确的摇晃动作），所以不会打断工作流。

**遗漏点：** `VoiceManager`、`NotificationManager`、`FileUploadManager` 都没接入日志。只有 WS 和 NET 有日志，Debug 面板的 VOICE/UPLOAD 分类形同虚设。

### 代码拆分的工程价值？

TerminalView.swift 从约 980 行拆到约 330 行，toolbar 和 session switcher 各自独立。这对开发者来说是正确的投入：

- **TerminalToolbar.swift（187 行）：** 纯展示 + 回调 pattern，所有状态通过参数传入，不持有任何 manager 的 ownership（除了 `@ObservedObject uploadManager`）。这意味着 toolbar 可以独立测试和修改，不影响终端核心逻辑。
- **SessionSwitcherSheet.swift（67 行）：** 更加干净，纯数据驱动（接收 `currentSession` + `sessions` + `onSelect`），完全无副作用。
- **TerminalView.swift：** 仍然是最大的文件（~330 行），但职责更聚焦：WebSocket 连接、事件分发、SwiftTerm wrapper。

代码拆分不直接影响用户体验，但降低了后续功能开发的心智负担。如果 v6 要加断线遮罩，改 TerminalToolbar 就行，不用在一个 980 行的文件里找上下文。

### 横屏优化的得失？

**得：**
- 终端区域多了约 54pt 垂直空间（toolbar 44pt + compact bar 省 10pt）
- 对于偶尔横屏使用的场景（比如看宽表格输出），更多的终端行数是实际的改善

**失：**
- 连接状态完全不可见——横屏下看不到绿灯/黄灯/红灯、看不到 NO NET、看不到 SCROLL 标签
- session 名不可见——如果开了多个 session，横屏下不知道自己在哪个 session
- session switcher 的唤出手势（顶部边缘下滑）无任何视觉暗示
- 横屏下无法访问 voice toggle、clipboard bridge、upload 按钮

**净效果：** 对于纯输入场景（打字 -> NL 发送），横屏优化是正面的。对于需要感知连接状态或切换 session 的场景，横屏优化是负面的。这是一个 trade-off，但执行上可以做得更好——比如一个迷你状态条。

## 最想要的 5 个改进（v6 应该做什么）

### 1. 真机验证触摸滚动并修复问题
连续四个版本未验证。这是 App 最大的功能债务。CC 的回复越来越长（Opus 的输出动辄上百行），不能回看历史是一个日益严重的日常痛点。v6 必须在真机上验证并修通。

### 2. 动态字号适配
连续四个版本未做。iPhone SE/mini 的竖屏可读性问题。Web 端早就有了。

### 3. 断线时终端半透明遮罩
连续两个版本未做。v4 评价就提了，v5 的 DebugLogStore 让诊断更容易，但用户层面仍然看不到"当前内容可能过时"的提示。

### 4. 横屏模式下的迷你状态条
v5 新增的问题。横屏隐藏顶栏后连接状态完全不可见。加一个 16pt 高的半透明条，只显示连接状态点 + session 名。

### 5. FileUploadManager / VoiceManager / NotificationManager 接入 DebugLogStore
v5 搭好了日志基础设施但只接入了一半。把剩下的三个 manager 都接上，让 Debug 面板真正覆盖所有子系统。

## 对比 Web 终端（更新版）

| 维度 | Web | App v5 | 赢家 | v4->v5 变化 |
|------|-----|--------|------|------------|
| 首次配置 | 打开 URL 即用 | 需要手动输入 IP | Web | -> |
| 启动速度 | 依赖 CDN 加载 | 原生秒开 + auto-connect | App | -> |
| 终端渲染质量 | xterm.js canvas | SwiftTerm 原生 | App | -> |
| 快捷键栏 | 12 个按钮 | 16 个 + 分组 + NL + compact | App | -> |
| 触摸滚动 | 非线性加速，已验证 | 代码完整，未经实测 | Web | -> |
| 文本选择/复制 | Select mode + overlay | 长按 overlay + haptic | 平手 | -> |
| 连接状态 | 无明确指示 | 四态 + NWPathMonitor + NO NET | App | -> |
| 断线重连 | 指数退避 | 指数退避 + 前后台 + 网络感知 | App | -> |
| 文件上传 | POST /api/upload | PHPicker + DocPicker + progress | 平手 | Web -> 平手 |
| 动态字体 | 自动适配 cols >= 70 | 固定字号 | Web | -> |
| 横屏体验 | 浏览器自适应 | 专门优化（隐藏toolbar + compact） | App | 新增 |
| 调试能力 | 浏览器 DevTools | shake-to-open Debug Panel | 平手 | 新增 |
| 触觉反馈 | 无 | 6 种场景 | App | -> |

v5 在文件上传上追平了 Web 端（从 "Web 赢" 变成 "平手"）。App 仍然输的核心维度缩减到 2 个：触摸滚动未实测、动态字体未实现。

## 会不会推荐给朋友？

推荐程度和 v4 一样——直接推荐，无附加条件。

但推荐的措辞不会因为 v5 而改变。v4 已经跨过了"可以作为主力工具"的门槛，v5 在这个基础上添了一些锦上添花的功能（文件上传、Debug 面板），但没有修复最让人困扰的短板（滚动回看）。如果朋友问"v5 比 v4 好在哪？"，我会说"可以上传文件了，横屏体验好一点，有调试日志了"。如果朋友问"值不值得从 v4 升级？"，我会说"值得，但不急"。

v5 的价值主要面向未来——代码拆分和 DebugLogStore 为后续迭代打了更好的基础。它让 v6 更容易做横屏迷你状态条（改 TerminalToolbar），更容易排查滚动问题（DebugLogStore + shake），更容易扩展 session 管理（独立的 SessionSwitcherSheet）。这是一个"为下一版铺路"的版本，而不是"让这一版惊艳"的版本。
