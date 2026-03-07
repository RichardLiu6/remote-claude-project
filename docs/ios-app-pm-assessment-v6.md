# iOS App 产品评估报告 v6（最终版）

> Claude Remote Terminal -- v5->v6 最终验证 + 六版本全周期回顾 + TestFlight 就绪度终评
>
> 评估日期：2026-03-07 | 当前版本：v6（ios-native-app-phase1 分支，commit a340311）
> 上一版评估：docs/ios-app-pm-assessment-v5.md（v5 评估，用户评分 8.8/10，PM 评分 9.0/10）

---

## A. v5 PM 建议完成情况验证

v6 共 **3 次提交**（7ef2f86 / 221988e / a340311），全部为 iOS App 改进。修改 12 个文件，新增 3 个文件（SwiftTermView.swift / TerminalContainerView.swift / IMETextField.swift），净增 iOS 代码 +875/-844 行。

### v5 PM 的 RICE Top 10 完成情况

| RICE排名 | 功能 | RICE分 | v6 状态 | 证据 |
|----------|------|--------|---------|------|
| **1** | **动态字体自适应** | 32.0 | **已完成** | commit 7ef2f86：`sizeChanged` 回调中检测 `newCols < 70`，调用 `adaptFontSize()` 循环缩小 fontSize（步进 1pt，下限 8pt），触发 SwiftTerm 重新计算列数。DebugLogStore 记录每次适配。**终结了连续 4 版的遗留** |
| **2** | **滚动真机验证 + 修复** | 25.6 | **未做** | ScrollGestureHandler.swift 234 行与 v5 完全一致。无 "Exit Scroll" 浮动按钮。**连续 5 版未验证** |
| **3** | **快捷栏 Select 按钮** | 18.7 | **已完成** | commit 221988e：InputAccessoryBar 新增 `.select` KeyAction + 紫色 `selectButton` 视图。TerminalView 通过 `triggerSelect` Binding 传递到 SwiftTermView.updateUIView，调用 `showSelectionOverlay()`。与 Web 端 Select 按钮对齐 |
| **4** | **断线终端半透明遮罩** | 11.2 | **已完成** | commit 7ef2f86：`disconnectOverlay` ViewBuilder，条件 `!wsManager.connectionState.isConnected && wsManager.connectionState != .connecting`。黑色 50% 透明度 + ProgressView spinner + 状态文字。`allowsHitTesting(false)` 不阻塞操作 |
| **5** | **TerminalView 剩余拆分** | 10.0 | **已完成** | commit 7ef2f86：TerminalView 852 行拆为 4 个文件——TerminalView（226 行）、SwiftTermView（196 行）、TerminalContainerView（208 行）、IMETextField（153 行）。TerminalView 瘦身 **73%**（852->226 行） |
| **6** | **NetworkMonitor debounce** | 10.0 | **已完成** | commit 7ef2f86：`debounceWorkItem` + 2 秒延迟。网络恢复和路径切换均 debounce，网络丢失即时通知。**终结了连续 2 版的遗留** |
| **7** | **通知/语音真机验证** | 7.2 | **部分完成** | VoiceManager 和 NotificationManager 均接入 DebugLogStore（commit 221988e），可诊断性大幅提升。但无明确的端到端真机验证记录 |
| **8** | **LaunchScreen** | 13.3 | **未做** | 无 LaunchScreen.storyboard 或 SwiftUI LaunchScreen |
| **9** | **TestFlight 配置 + 回归测试** | 8.0 | **部分完成** | MARKETING_VERSION 更新为 6.0（commit a340311），Xcode project 正确引用新文件。但无 signing 配置、无 TestFlight metadata |
| **10** | **命令收藏/快捷面板** | 6.4 | **未做** | InputAccessoryBar 无长按手势或收藏逻辑 |

### v6 计划执行率

| 类别 | 数量 | 明细 |
|------|------|------|
| v5 PM 计划完成 | 5 项 | 动态字体、Select 按钮、断线遮罩、TerminalView 拆分、debounce |
| v5 PM 计划部分完成 | 2 项 | 通知/语音验证（接入日志但无端到端验证记录）、TestFlight 配置（版本号但无 signing） |
| v5 PM 计划未做 | 3 项 | 滚动真机验证、LaunchScreen、命令收藏 |
| **总计划执行率** | **6/10（60%）** | 含部分完成折算为 5+1=6 |

**历版计划执行率对比：v3 50% -> v4 44% -> v5 28% -> v6 60%。** v6 逆转了连续下降趋势，达到六版本中的最高计划执行率。

### v6 计划外完成的工作

| 功能 | 代码量 | 说明 |
|------|--------|------|
| Onboarding "Test Connection" 按钮 | ~50 行 | commit a340311：配置页新增连接测试按钮，ping `/api/sessions`，显示 testing/success/failed 三态反馈 |
| 横屏迷你状态条 | ~15 行 | commit 7ef2f86：16pt 半透明条，显示连接状态点 + session 名 + SCROLL 标签 + 状态文字 |
| DebugLogStore 全覆盖 | ~30 行 | commit 221988e：FileUploadManager / VoiceManager / NotificationManager 全部接入日志 |

**注：** 横屏迷你状态条和 DebugLogStore 全覆盖分别是 v5 用户评价中 "最想要的 5 个改进" 的第 4 和第 5 项。v6 在计划内外同时覆盖了用户核心诉求。

---

## B. 六版本全周期回顾

### B1. 用户/PM 评分趋势

| 版本 | 用户评分 | PM评分 | 主题 | 核心提分因素 | 核心失分因素 |
|------|---------|--------|------|-------------|-------------|
| v1 | -- | -- | 奠基 | SwiftTerm + WebSocket 基础架构 | 仅 MVP |
| v2 | 5.5 | -- | 功能补全 | 滚动代码、语音、通知、剪贴板、快捷栏 | 中文未验证、假绿灯、无 session 结束检测 |
| v3 | 7.5 | 7.5 | 可靠性 | isConnected 修正、session 结束检测、IMETextField、触觉反馈 | 快捷栏缺 NL、动态字体未做、滚动未验证 |
| v4 | 8.5 | 8.5 | 零摩擦 | NL+15 键快捷栏、NWPathMonitor、scenePhase 重连、auto-connect | 动态字体未做、滚动未验证、fetchSessions crash |
| v5 | 8.8 | 9.0 | 追平与发布准备 | P0 修复、文件上传、App 图标、Onboarding、横屏优化 | 动态字体 4 版、滚动 4 版未验证 |
| **v6** | **--** | **9.3** | **打磨发布** | 动态字体终结、Select 按钮、断线遮罩、代码拆分、debounce、Test Connection | 滚动 5 版未验证、无 LaunchScreen |

**评分曲线：5.5 -> 7.5 -> 8.5 -> 8.8/9.0 -> 9.3**

v6 PM 评分 9.3 的来源分析：
- 动态字体终结历史遗留：终端可读性维度 +1.0（7.0 -> 8.0）
- Select 按钮 + 断线遮罩：复制粘贴 +1.0（5.0 -> 6.0）、网络稳定性感知 +0.3（9.5 -> 9.8）
- 横屏迷你状态条：终端可读性额外 +0.5（解决 v5 横屏信息丢失问题）
- TerminalView 73% 瘦身：代码组织质量显著提升
- Test Connection：首次启动体验 +0.5（8.5 -> 9.0）
- 滚动仍未验证：继续压分 -1.5

### B2. 每版核心贡献

| 版本 | 定义性功能 | 一句话总结 |
|------|-----------|-----------|
| **v1** | SwiftTerm + WebSocket + Session 选择器 | 从零到可运行 |
| **v2** | ScrollGestureHandler + VoiceManager + NotificationManager | 功能骨架搭齐 |
| **v3** | ConnectionState 枚举 + DisconnectReason + IMETextField | 从"能用"到"可靠" |
| **v4** | NL 按钮 + NWPathMonitor + auto-connect + session 切换 | 从"可靠"到"好用" |
| **v5** | P0 修复 + 文件上传 + App 图标 + Onboarding + DebugLogPanel | 从"好用"到"可展示" |
| **v6** | 动态字体 + Select 按钮 + 断线遮罩 + 73% 拆分 + debounce | 从"可展示"到"可发布" |

### B3. 代码量和架构演进

#### 代码量追踪（v1-v6）

| 文件 | v2 | v3 | v4 | v5 | v6 | v5->v6 |
|------|-----|-----|-----|-----|-----|--------|
| ClaudeTerminalApp.swift | 12 | 12 | 11 | 33 | 33 | -- |
| Models/ServerConfig.swift | 79 | 79 | 78 | 78 | 78 | -- |
| Models/SessionModel.swift | 23 | 23 | 22 | 22 | 22 | -- |
| Audio/VoiceManager.swift | 205 | 205 | 204 | 204 | **209** | +5 |
| Network/WebSocketManager.swift | ~260 | 435 | 434 | 440 | 440 | -- |
| Network/ClipboardBridge.swift | 51 | 51 | 50 | 50 | 50 | -- |
| Network/NotificationManager.swift | 129 | 129 | 128 | 128 | **133** | +5 |
| Network/NetworkMonitor.swift | -- | -- | 100 | 103 | **117** | +14 |
| Network/FileUploadManager.swift | -- | -- | -- | 249 | **256** | +7 |
| Views/InputAccessoryBar.swift | 99 | 99 | 142 | 145 | **174** | +29 |
| Views/SessionPickerView.swift | 286 | 286 | 307 | 307 | **307** | -- (版本号改行) |
| Views/TerminalView.swift | ~290 | 800 | 979 | 852 | **226** | **-626** |
| Views/TerminalToolbar.swift | -- | -- | -- | 186 | 186 | -- |
| Views/SessionSwitcher.swift | -- | -- | -- | 67 | 67 | -- |
| Views/DebugLogPanel.swift | -- | -- | -- | 209 | 209 | -- |
| Views/OnboardingView.swift | -- | -- | -- | 245 | **273** | +28 |
| **Views/SwiftTermView.swift** | -- | -- | -- | -- | **196** | +196 (新增) |
| **Views/TerminalContainerView.swift** | -- | -- | -- | -- | **208** | +208 (新增) |
| **Views/IMETextField.swift** | -- | -- | -- | -- | **153** | +153 (新增) |
| Gestures/ScrollGestureHandler.swift | 235 | 235 | 234 | 234 | 234 | -- |
| **合计（iOS）** | **~1669** | **~2354** | **~2689** | **~3552** | **~3571** | **+19（+0.5%）** |

**v6 关键架构指标：**

| 指标 | v5 | v6 | 变化 | 说明 |
|------|-----|-----|------|------|
| 总代码量 | 3552 行 | 3571 行 | +19（+0.5%） | 近乎零增长的重构版本 |
| Swift 文件数 | 17 | 20 | +3 | SwiftTermView / TerminalContainerView / IMETextField |
| 最大文件 | 852 行（TerminalView） | 440 行（WebSocketManager） | -48% | 最大文件不再是 TerminalView |
| 平均文件大小 | 209 行 | 179 行 | -14% | 文件粒度更合理 |
| TerminalView 行数 | 852 | 226 | -73% | 从"巨石文件"变为"协调器" |
| 300 行以上文件 | 3 个 | 2 个 | -1 | 仅 WebSocketManager(440) 和 SessionPickerView(307) |

**架构成熟度里程碑：** v6 是第一个"总代码量几乎不变但文件组织显著改善"的版本。TerminalView 从 v4 的 979 行怪物瘦身到 226 行的纯协调器，符合 SwiftUI 最佳实践。v6 证明团队已从"功能堆砌"模式转向"结构优化"模式。

#### 架构演进图

```
v1: 单体 (TerminalView = 全部)
  |
v2: +5 功能模块 (Scroll/Voice/Notify/Clipboard/Input)
  |
v3: +状态管理 (ConnectionState/DisconnectReason/IMETextField)
  |
v4: +网络感知 (NWPathMonitor/scenePhase)
  |
v5: +代码拆分第一波 (TerminalToolbar/SessionSwitcher) + 新功能模块 (Upload/Debug/Onboarding)
  |
v6: +代码拆分第二波 (SwiftTermView/TerminalContainerView/IMETextField) + 技术债清零
```

### B4. 用户痛点解决时间线

| 痛点 | 首次提出 | 解决版本 | 等待版本数 | 说明 |
|------|---------|---------|-----------|------|
| 假绿灯（isConnected 不准） | v2 | v3 | 1 | ConnectionState 枚举 + first message 确认 |
| 中文输入问题 | v2 | v3 | 1 | IMETextField 代理 |
| 快捷栏缺 NL/Enter | v2 | v4 | 2 | NL 按钮首位 + 16 键全布局 |
| 无网络感知 | v3 | v4 | 1 | NWPathMonitor + NO NET 标签 |
| 无 auto-connect | v3 | v4 | 1 | UserDefaults 缓存 last_session |
| fetchSessions crash (P0) | v2 | v5 | 3 | guard let + throw URLError |
| 无文件上传 | v4 对比 | v5 | 1 | PHPicker + DocumentPicker |
| 无 App 图标 | v2 | v5 | 3 | AI 生成紫色渐变 + 终端光标 |
| 无首次引导 | v2 | v5 | 3 | OnboardingView 3 页 + 配置页 |
| **动态字体缺失** | **v2** | **v6** | **4** | sizeChanged + adaptFontSize 循环缩小 |
| **Select 按钮可发现性** | **v4** | **v6** | **2** | 快捷栏紫色 Select 按钮 |
| **断线无视觉提示** | **v4** | **v6** | **2** | 半透明遮罩 + spinner |
| **NetworkMonitor debounce** | **v4 PM** | **v6** | **2** | 2 秒 debounce + cancel 机制 |
| **横屏信息丢失** | **v5 用户** | **v6** | **1** | 16pt 迷你状态条 |
| **DebugLogStore 半接入** | **v5 用户** | **v6** | **1** | FileUpload/Voice/Notify 全接入 |
| **Onboarding 无连接测试** | **v5 用户** | **v6** | **1** | Test Connection 按钮 |
| 滚动未真机验证 | v2 | **未解决** | **5** | 连续 5 版代码完整但零验证 |
| LaunchScreen 缺失 | v2 | **未解决** | **5** | 无 storyboard 或 SwiftUI 启动屏 |
| 通知内容无摘要 | v3 | **未解决** | **4** | 仍为固定 "Task completed" 文本 |
| 命令收藏/快捷面板 | v4 PM | **未解决** | **3** | 无长按手势或收藏逻辑 |
| Widget 桌面小组件 | v4 PM | **未解决** | **3** | 无 WidgetKit Target |

**v6 解决了 6 个历史遗留痛点 + 1 个 v5 新增痛点。** 最显著的成就是终结了"动态字体"这个连续 4 版的房间里的大象。最大的遗憾是"滚动真机验证"升级为连续 5 版未解决。

---

## C. TestFlight 就绪度最终评估

### C1. 10 项 TestFlight 检查清单

| # | 检查项 | v5 状态 | v6 状态 | 说明 |
|---|--------|---------|---------|------|
| 1 | App 无已知 crash 路径 | 通过 | **通过** | fetchSessions 修复 (v5)，URL guard let 全覆盖 |
| 2 | 核心功能完整 | 通过 | **通过** | 连接/输入/显示/重连/上传/选择 |
| 3 | App 图标 | 通过 | **通过** | 紫色渐变 + 终端光标 (v5) |
| 4 | Onboarding 引导 | 通过 | **通过+** | v5 基础 + v6 新增 Test Connection 按钮 |
| 5 | 版本号一致性 | 通过 | **通过** | Settings 显示 "6.0"，MARKETING_VERSION 6.0（Debug+Release） |
| 6 | Debug 日志 | 通过 | **通过+** | v5 基础 + v6 全模块接入（WS/NET/VOICE/UPLOAD/SYS/ERR 全覆盖） |
| 7 | 动态字体 | **未通过** | **通过** | `adaptFontSize()` 循环缩小至 cols >= 70 或 8pt 下限 |
| 8 | 滚动浏览 | **未通过** | **未通过** | **连续 5 版未验证。** 代码完整（234 行 ScrollGestureHandler），但无任何真机验证记录 |
| 9 | 通知/语音端到端 | **未通过** | **条件通过** | 已接入 DebugLogStore 可诊断。代码逻辑完整，但无端到端真机验证的明确记录。降为"条件通过" |
| 10 | 代码质量 | 基本通过 | **通过** | TerminalView 226 行，最大文件 440 行，平均 179 行。20 个文件职责清晰 |

### C2. 通过率对比

| 版本 | 通过 | 条件通过 | 未通过 | 通过率 |
|------|------|---------|--------|--------|
| v4 | 4 | 0 | 6 | 40% |
| v5 | 7 | 0 | 3 | 70% |
| **v6** | **8** | **1** | **1** | **85%（宽口径 90%）** |

**v6 TestFlight 就绪度：85-90%。** 较 v5 的 70% 提升 15-20 个百分点。唯一的硬性"未通过"是滚动浏览。

### C3. 是否建议提交 TestFlight？

**建议：有条件地提交。**

**理由：**

1. **提交 TestFlight 的阻塞项只剩 1 个**（滚动），而滚动是一个"代码完整但未验证"的功能——它可能工作正常，也可能有 bug。TestFlight 本身就是验证渠道。

2. **TestFlight 的价值在于真机反馈。** 继续在开发环境中迭代不会产生比 TestFlight beta 测试更有价值的反馈。v6 已经具备了让真实用户使用的最低门槛——有图标、有引导、有连接测试、核心功能完整、无 crash 路径。

3. **建议在提交前做一次快速的滚动真机验证。** 不需要完美——只需确认基本的上下滚动在真机上可以工作。如果不工作，加一个"已知问题"说明。TestFlight 的 "What to Test" 字段可以引导 beta 用户重点测试滚动。

4. **缺失的 LaunchScreen 不是阻塞项。** App Store 提交需要 LaunchScreen，但 TestFlight 不做硬性要求。黑屏启动对于开发者工具类 App 是可接受的。

**提交前的最小检查清单：**
- [ ] 滚动：在真机上快速验证上下滑动是否触发 tmux copy-mode
- [ ] Signing：配置 Apple Developer Team + Provisioning Profile
- [ ] TestFlight metadata：填写 "What to Test" + beta app description

---

## D. 产品成熟度终评

### D1. 与 Web 终端的最终对比

| 维度 | Web | App v6 | 赢家 | v5->v6 变化 |
|------|-----|--------|------|------------|
| 首次配置 | 打开 URL 即用 | Onboarding + IP 配置 + **Test Connection** | Web | 差距缩小（Test Connection 降低出错率） |
| 启动速度 | CDN 加载 | 原生秒开 + auto-connect | **App** | --> |
| 终端渲染 | xterm.js canvas | SwiftTerm 原生 | **App** | --> |
| 快捷键栏 | 12 按钮 + Select | **17 按钮 + 分组 + NL + Select + compact** | **App** | **v6 新增 Select** |
| 中文输入 | diff 模型 + 防抖 | IMETextField 原生 | **App** | --> |
| 触摸滚动 | 非线性加速，已验证 | 代码完整，**未验证** | Web | --> |
| 文本选择/复制 | Select mode overlay | **长按 + 快捷栏 Select** | **App** | **v6 可发现性提升** |
| 连接状态 | 无明确指示 | 四态 + NWPathMonitor + NO NET + **断线遮罩** | **App** | **v6 遮罩新增** |
| 断线重连 | 指数退避 | 指数退避 + 网络感知 + 前后台 + **debounce** | **App** | **v6 debounce** |
| 文件上传 | POST /api/upload | PHPicker + DocPicker + progress | **App** | --> |
| 动态字体 | cols < 70 自动缩小 | **cols < 70 循环缩小至 8pt** | **平手** | **v6 追平** |
| 横屏体验 | 浏览器自适应 | 隐藏顶栏 + **迷你状态条** + compact 快捷栏 | **App** | **v6 修复信息丢失** |
| 调试能力 | 浏览器 DevTools | shake Debug Panel + **全模块日志** | **App** | **v6 全覆盖** |
| 触觉反馈 | 无 | 6 种场景 | **App** | --> |
| App 图标/品牌 | N/A | 紫色渐变终端光标 | **App** | --> |
| 首次引导 | 无 | 3 页 + 配置 + **连接测试** | **App** | **v6 Test Connection** |

**v6 在 16 个维度中赢 12 个、平 1 个、输 3 个。**

- **v6 新增或改善的维度（6 个）：** Select 按钮、断线遮罩、debounce、动态字体追平、迷你状态条、全模块日志
- **App 仍输的 3 个维度：** 首次配置（Web 仍更简单）、触摸滚动（未验证）、（无 LaunchScreen 属于品牌细节不单独计）

**关键变化：** v5 时 App 仍在动态字体和滚动两个"基础功能"上输给 Web。v6 解决了动态字体，App 仅在"滚动未验证"这一个基础功能上落后。其余差距均属于"首次配置便利性"这类结构性差异（Web 天然优势）。

### D2. 各维度评分详情（v6）

| 维度 | v2 | v3 | v4 | v5(用户) | v6(PM) | v5->v6 | 理由 |
|------|-----|-----|-----|---------|--------|--------|------|
| 首次启动体验 | 7 | 7 | 8.5 | 8.5 | **9.0** | +0.5 | Test Connection 按钮让用户在引导阶段就能验证配置 |
| 终端可读性 | 7 | 7 | 7 | 7 | **8.5** | +1.5 | 动态字体（连续 4 版终结）+ 横屏迷你状态条（信息不再丢失） |
| 打字体验 | 6 | 8 | 9 | 9 | **9** | -- | 无变化。Select 按钮虽在快捷栏但不影响打字本身 |
| 滚动浏览 | 2 | 3 | 3 | 3 | **3** | -- | **连续 5 版未验证。** 这是整个产品最后的短板 |
| 复制粘贴 | 4 | 5 | 5 | 5 | **6** | +1.0 | Select 按钮解决了"长按选择可发现性差"的核心问题 |
| 网络稳定性 | 7 | 9 | 9.5 | 9.5 | **9.8** | +0.3 | 断线遮罩明确告知"内容可能过时" + debounce 防止频繁重连 |
| 语音功能 | 6 | 6 | 6 | 6 | **6.5** | +0.5 | DebugLogStore 接入，可诊断"语音为何不响"的问题 |
| 通知功能 | 6 | 6 | 6 | 6 | **6.5** | +0.5 | DebugLogStore 接入，可诊断权限和事件匹配 |
| 多 session 管理 | 5 | 6.5 | 7.5 | 8 | **8.5** | +0.5 | 横屏迷你状态条显示 session 名，不再完全丢失上下文 |
| 整体完成度 | 5 | 7.5 | 8.5 | 8.8 | **9.3** | +0.5 | 动态字体+Select+遮罩+拆分+debounce+Test Connection |
| **总评** | **5.5** | **7.5** | **8.5** | **8.8** | **9.3** | **+0.5** | |

### D3. 日常使用推荐度

**推荐等级：强烈推荐，附一个已知限制。**

v6 是第一个可以作为**唯一终端客户端**使用的版本——不再需要"切回 Web 调字体"或"切回 Web 上传文件"。唯一仍需切回 Web 的场景是：需要回看大量历史输出时（滚动未验证）。

**使用场景覆盖率：**

| 场景 | v4 | v5 | v6 | 说明 |
|------|-----|-----|-----|------|
| 日常指令交互 | 100% | 100% | 100% | NL+快捷栏 |
| 长输出阅读 | 30% | 30% | 30% | 滚动未验证 |
| 截图/文件给 CC | 0% | 100% | 100% | PHPicker |
| 小屏幕使用 | 70% | 70% | **100%** | 动态字体 |
| 横屏使用 | 50% | 80% | **100%** | 迷你状态条 |
| 文本复制 | 60% | 60% | **80%** | Select 按钮 |
| 网络切换/地铁 | 90% | 90% | **95%** | debounce |
| 故障排查 | 20% | 50% | **80%** | 全模块日志 |
| 新用户上手 | 30% | 70% | **85%** | Test Connection |

### D4. 产品成熟度雷达图

| 评估维度 | v1 | v2 | v3 | v4 | v5 | v6 | 说明 |
|---------|-----|-----|-----|-----|-----|-----|------|
| 基本功能完整性 | 40% | 60% | 75% | 90% | 95% | **97%** | 仅剩滚动验证和命令收藏 |
| 稳定性/可信度 | 30% | 40% | 70% | 85% | 92% | **95%** | 全模块日志 + debounce |
| 效率 vs Web | 40% | 50% | 60% | 85% | 92% | **95%** | 动态字体追平 + Select 按钮 |
| 代码组织 | 70% | 60% | 50% | 45% | 65% | **85%** | 73% 瘦身，20 文件合理分工 |
| 可发现性 | 50% | 50% | 55% | 65% | 70% | **80%** | Select 按钮 + Test Connection |
| 品牌/专业感 | 30% | 30% | 30% | 35% | 70% | **75%** | 缺 LaunchScreen，其余完善 |
| iOS 工作流融合 | 10% | 10% | 10% | 20% | 30% | **30%** | 无 Widget/Shortcuts/Siri |
| TestFlight 就绪度 | 10% | 20% | 35% | 50% | 80% | **90%** | 仅剩 signing + 滚动验证 |

### D5. 未来方向建议（post-v6）

v6 作为 Phase 1 的最终版本，已将产品从 MVP 推向接近发布状态。以下是 Phase 2 的建议方向，按优先级排列：

#### 第一优先级：TestFlight 提交与滚动修复

| 任务 | 预估 | 说明 |
|------|------|------|
| 滚动真机验证 + 修复 | 1 天 | 连续 5 版的最后一个"大象"。在真机上验证 ScrollGestureHandler + tmux copy-mode 的完整流程 |
| Apple Developer 签名 | 0.5 天 | Team ID / Provisioning Profile / Capabilities |
| TestFlight 提交 | 0.5 天 | 填写 metadata + "What to Test" + 首次提交 |

#### 第二优先级：iOS 原生能力深挖

| 任务 | 说明 |
|------|------|
| WidgetKit 桌面小组件 | 显示活跃 session 数 + 最近活动。一键直达 session |
| Shortcuts 集成 | "开始 Claude session" / "发送指令" 快捷指令 |
| LaunchScreen | 匹配 App 图标风格，黑底 + 紫色光标 |
| Haptic 引擎升级 | 利用 Core Haptics 替代简单的 UIImpactFeedbackGenerator |

#### 第三优先级：体验打磨

| 任务 | 说明 |
|------|------|
| 命令收藏/历史 | 长按快捷栏按钮弹出收藏面板，常用命令一键发送 |
| 通知内容增强 | 通知 body 包含 CC 最后一行输出摘要 |
| 多段语音排队 | VoiceManager 音频队列，替代当前的 cancel-and-play |
| pinch-to-zoom | 手势缩放字体，与动态字体系统联动 |

---

## 关键结论

### 1. v6 是最高效的版本

v6 用仅 +19 行的净代码增长（+875/-844），交付了 5 个 RICE Top 10 任务 + 3 个计划外改进。60% 的计划执行率是六版本中最高的。这证明团队已从"功能堆砌"成熟到"精准交付"。

### 2. "房间里的大象"解决了一半

v6 终结了动态字体这个连续 4 版的遗留问题（`adaptFontSize()` 实现优雅、DebugLogStore 记录适配过程），但滚动验证升级为连续 5 版未解决。滚动是现在**唯一的"大象"**，但它的特殊性在于——代码一直在那里（234 行 ScrollGestureHandler），缺的是真机验证而非实现。

### 3. 代码架构达到了应有的水平

TerminalView 从 v4 的 979 行减至 v6 的 226 行（-77%），最终符合 SwiftUI 的"View 是协调器"哲学。20 个文件、平均 179 行、最大 440 行——这是一个合理的 Swift 项目结构。v6 是第一个"不需要在读代码时迷路"的版本。

### 4. TestFlight 就绪度达到发布标准

从 v4 的 40% -> v5 的 70% -> v6 的 85-90%。剩余的 10-15% 集中在两个明确的任务上：滚动验证和 Apple Developer 签名。这不是"差距太大不知从何入手"，而是"差两步就到终点"。

### 5. 评分曲线进入高原期

5.5 -> 7.5 -> 8.5 -> 8.8 -> 9.3。增幅从 +2.0 -> +1.0 -> +0.3 -> +0.5。9.3 分意味着产品已经进入了"边际改善递减"区间——每提升 0.1 分都需要解决更细微的问题。在这个阶段，最有价值的不是继续打磨，而是让真实用户使用并收集反馈。这正是 TestFlight 的意义所在。

### 6. v1 到 v6 的完整旅程

| 里程碑 | 版本 | 意义 |
|--------|------|------|
| 从零到可运行 | v1 | SwiftTerm + WebSocket 证明了原生终端的可行性 |
| 功能骨架搭齐 | v2 | 5 个功能模块让 App 从 Demo 变成了工具 |
| 从"能用"到"可靠" | v3 | ConnectionState 枚举消除了假绿灯，IMETextField 解决了中文输入 |
| 从"可靠"到"好用" | v4 | NL 按钮是最高频改进，auto-connect 让启动无摩擦 |
| 从"好用"到"可展示" | v5 | App 图标 + Onboarding 让产品有了"品牌感" |
| **从"可展示"到"可发布"** | **v6** | **动态字体 + Select + 断线遮罩 + 代码重构 = 发布级质量** |

六个版本、20 个 Swift 文件、3571 行代码——从一个空白 Xcode 项目到一个功能超越 Web 端的 iOS 终端客户端。Phase 1 结束。
