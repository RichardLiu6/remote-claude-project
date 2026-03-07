# iOS App 产品评估报告 v5

> Claude Remote Terminal -- v4->v5 改进验证 + v6（最终版）路线图规划
>
> 评估日期：2026-03-07 | 当前版本：v5（ios-native-app-phase1 分支，commit 957095e）
> 上一版评估：docs/ios-app-pm-assessment-v4.md（v4 评估，用户评分 8.5/10）

---

## A. v4 PM 建议的 v5 任务完成情况验证

v5 共 **7 次提交**（e5b287b / d404735 / 87be968 / 7376ff3 / 54c1bfd / 3c7c4a1 / 957095e），其中 6 个 iOS App 提交 + 1 个 Web 端 input 系统重写。iOS 侧修改 12 个文件，新增 6 个文件（TerminalToolbar.swift / SessionSwitcher.swift / FileUploadManager.swift / DebugLogPanel.swift / OnboardingView.swift / AppIcon-1024.png），净增 iOS 代码 +2018/-405 行。

> **注意**：用户提供的评估范围仅列出 3 个 commit（e5b287b / d404735 / 87be968），但 ios-native-app-phase1 分支实际还有 4 个后续 commit 属于 v5 范畴。本评估覆盖全部 7 个 commit。

### v4 PM 建议的 v5-alpha（"技术债清理"）任务

| # | 任务 | v4 PM 建议 | v5 状态 | 证据 |
|---|------|-----------|---------|------|
| 1 | **fetchSessions 强制解包修复** | RICE #1（100.0），连续 3 版遗漏的 P0 Bug | **已完成** | commit d404735：`URL(string:)!` -> `guard let url else { throw URLError(.badURL) }`。3 行代码修复，终结了从 v2 起连续 4 版的 crash 风险 |
| 2 | **TerminalView 文件拆分** | RICE #2（10.0），979 行拆为 5 个文件 | **部分完成** | commit e5b287b：提取 TerminalToolbar.swift（186 行）+ SessionSwitcher.swift（67 行）。TerminalView 从 979 行降至 **852 行**（-13%）。v4 PM 建议的 SwiftTermView / TerminalContainerView / IMETextField 三个拆分**未做** |
| 3 | **动态字体自适应** | RICE #3（16.0），连续 3 版未做 | **未做** | TerminalView.swift:351 字体逻辑仍为 `serverConfig.fontSize > 0 ? ... : (iPad ? 14 : 12)`。**连续 4 版未做** |
| 4 | **NetworkMonitor debounce** | RICE #7（6.0） | **未做** | NetworkMonitor.swift 仅增加 3 行 DebugLogStore 调用，无 debounce 逻辑 |
| 5 | **滚动真机验证** | RICE #10（4.0） | **未做** | ScrollGestureHandler.swift 234 行，与 v4 完全一致 |

**v5-alpha 完成率：1.5/5（30%）**

### v4 PM 建议的 v5-beta（"贴心工具"）任务

| # | 任务 | v4 PM 建议 | v5 状态 | 证据 |
|---|------|-----------|---------|------|
| 6 | **Widget 桌面小组件** | RICE #4（6.3） | **未做** | 无 WidgetKit Target |
| 7 | **命令收藏/快捷面板** | RICE #5（6.4） | **未做** | InputAccessoryBar 无长按手势、无收藏逻辑 |
| 8 | **App 图标 & LaunchScreen** | RICE #6（5.0） | **已完成** | commit 3c7c4a1：AI 生成 1024x1024 图标，白色终端光标 + Claude 紫色渐变背景。Contents.json 更新。LaunchScreen 未做 |
| 9 | **通知内容增强** | RICE #9（4.3） | **未做** | NotificationManager.swift 128 行，与 v4 完全一致 |

**v5-beta 完成率：1/4（25%）**

### v5 总计划执行率

| 类别 | 数量 | 明细 |
|------|------|------|
| v4 PM 计划完成 | 2 项 | fetchSessions 修复、App 图标 |
| v4 PM 计划部分完成 | 1 项 | TerminalView 拆分（拆了 2/5 个） |
| v4 PM 计划未做 | 6 项 | 动态字体、debounce、滚动验证、Widget、命令收藏、通知增强 |
| **总计划执行率** | **2.5/9（28%）** | alpha 1.5/5 + beta 1/4 |

**历版计划执行率对比：v3 50% -> v4 44% -> v5 28%。** 执行率持续下降，但 v5 在计划外完成了大量高价值工作（见 Section B）。

---

## B. v5 新增工作分析（v4 PM 未计划）

v5 最显著的特点是"做了很多 PM 没规划的工作，而且大部分价值很高"。逐一分析：

### B1. TerminalView 拆分 + 横屏优化（commit e5b287b）

**做了什么：**

1. **TerminalToolbar.swift（186 行，新增）** -- 顶栏 UI 完整提取。包含 session 名称按钮、连接状态点/文字、NO NET 标签、SCROLL 标签、上传按钮、剪贴板按钮、语音开关。通过闭包回调（`onDismiss` / `onShowSessionSwitcher` / `onShowClipboard` / `onShowUploadPicker`）与父视图通信。

2. **SessionSwitcher.swift（67 行，新增）** -- SessionSwitcherSheet 移至独立文件。纯代码组织优化。

3. **横屏优化** -- 三个改进：
   - 横屏时自动隐藏顶栏（`if !landscape`），最大化终端面积
   - InputAccessoryBar 新增 `isCompact` 参数，横屏高度 44pt -> 34pt，字体 14pt -> 12pt
   - 横屏时从屏幕顶部下拉（DragGesture）可呼出 session 切换 sheet

**价值评估：8/10** -- 选择了最高 ROI 的拆分点，横屏优化是 v4 PM 未识别的真实痛点。

### B2. 文件上传功能（commit 87be968）

**做了什么：**

1. **FileUploadManager.swift（249 行，新增）** -- 完整的文件上传管理器：
   - 支持 Photo Library（PHPicker）和 Files（UIDocumentPicker）两种来源
   - multipart/form-data 请求 -> `POST /api/upload`
   - `UploadState` 状态机（idle / uploading / success / error）驱动 UI
   - 上传进度追踪（KVO 观察 URLSessionDataTask.progress）
   - 成功后 3 秒自动重置、安全处理 security-scoped resource、MIME 自动检测

2. **TerminalToolbar 上传按钮** -- 状态驱动视觉：idle 灰色、uploading 紫色进度环、success 绿色勾号、error 红色感叹号

3. **PhotoPicker + DocumentPicker** -- 两个 SwiftUI 封装器

**价值评估：9/10** -- 文件上传是 v4 用户评价中 App 输给 Web 的仅有 3 项之一。原生 PHPicker 体验优于 Web 端 `input[type=file]`。

### B3. DebugLogPanel（commit 54c1bfd）

**做了什么：**

1. **DebugLogPanel.swift（209 行，新增）** -- 调试日志面板：
   - `DebugLogStore` 单例收集 WS / NET / VOICE / UPLOAD / SYS / ERR 事件
   - 摇一摇手势触发（`.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake))`）
   - 分类过滤 chips + 自动滚动 + 日志导出（Share Sheet）
   - 保留最近 500 条，LazyVStack 性能友好

2. **ClaudeTerminalApp.swift** -- 新增 `UIWindow.motionEnded` 扩展和 `.deviceDidShake` Notification

3. **WebSocketManager** -- connect / receive error / reconnect 事件接入 DebugLogStore

**价值评估：7/10** -- 不直接面向终端用户，但对 TestFlight beta 测试的问题排查极有价值。

### B4. App 图标（commit 3c7c4a1）

**做了什么：** AI 生成的 1024x1024 图标——白色终端块状光标 + 柔和光晕，深紫至蓝紫渐变背景。更新 Contents.json。

**价值评估：8/10** -- 连续 4 版缺失的品牌化问题终于解决。App 图标是 TestFlight 的门面，从"开发中 Demo"变成了"有品牌感的产品"。

### B5. Onboarding 引导流（commit 957095e）

**做了什么：**

1. **OnboardingView.swift（245 行，新增）** -- 首次启动 3 页引导 + 配置页：
   - Page 1 "Connect"：Tailscale VPN 加密说明
   - Page 2 "Control"：终端操控能力介绍（session 切换、快捷栏、滚动、长按复制）
   - Page 3 "Features"：语音/上传/剪贴板/通知功能展示
   - Page 4 "Setup"：输入 Tailscale IP 和端口，保存到 ServerConfig
   - 精美的渐变图标 + 动画页面过渡 + Skip 按钮
   - `UserDefaults("onboarding_completed")` 确保仅首次显示

2. **版本号更新** -- Settings 页 "Version 4.0" -> "5.0"，pbxproj MARKETING_VERSION 同步更新

**价值评估：9/10** -- 从 v2 用户评价第一次提到"首次打开完全没有引导"，到 v5 终于解决。这是 TestFlight 的硬性前提——新测试用户必须知道如何配置连接。

### B6. Web 端 Input 系统重写（commit 7376ff3）

**做了什么：** `public/index.html` 移动端输入系统全面重写（+477/-172 行），新增 `tests/test-input-system.mjs`（1001 行测试）。InputController 状态机、即时退格、软键盘 Enter 恢复、Ctrl+A-Z 检测。

**与 iOS App 的关系：** 这是 Web 端改进，不直接影响 iOS App。但它与 iOS 端 InputAccessoryBar 的快捷栏重排保持了一致（Enter 首位、Tab 其次、^C 第三）。

**价值评估（对 iOS App）：1/10** -- 仅间接相关。

### B7. v5 新增工作总结

| 功能 | 计划来源 | 代码量 | 价值评分 | 说明 |
|------|---------|--------|---------|------|
| TerminalToolbar 提取 | v4 PM 计划内 | 186 行 | 8/10 | 最高 ROI 拆分点 |
| SessionSwitcher 提取 | v4 PM 计划内 | 67 行 | 7/10 | 纯组织优化 |
| 横屏优化 | **未计划** | ~50 行 | 8/10 | 终端面积 +50pt |
| fetchSessions 修复 | v4 PM 计划内 | 3 行 | 10/10 | P0 终结 |
| FileUploadManager | **未计划** | 249 行 | 9/10 | 追平并超越 Web |
| DebugLogPanel | **未计划** | 209 行 | 7/10 | TestFlight 基础设施 |
| App 图标 | v4 PM 计划内 | 图片资源 | 8/10 | 品牌化，连续 4 版缺失 |
| OnboardingView | **未计划** | 245 行 | 9/10 | TestFlight 硬性前提 |
| 版本号 5.0 | **未计划** | 2 行 | 10/10 | 基本正确性 |
| InputAccessoryBar isCompact | **未计划** | ~15 行 | 6/10 | 横屏配套 |
| Web Input 重写 | **未计划** | 1478 行 | 1/10 | Web 端，与 iOS 间接相关 |

**结论：v5 虽然对 v4 PM 计划执行率仅 28%，但实际产出远超计划。** 计划外完成了 Onboarding（PM RICE #10）、App 图标（PM RICE #6）、文件上传、DebugLogPanel、横屏优化等高价值功能。如果用"计划内 + 计划外"综合口径，v5 是 **产出最全面的版本**。

---

## C. RICE 优先级排序（v6 规划）

v6 定位为**最终版本**，聚焦打磨和 TestFlight 准备。由于 v5 已完成 App 图标和 Onboarding，v6 的工作量大幅减少。

### C1. v5 结束后的 RICE 进展更新

| 原排名 | # | 功能 | v5 状态 | 说明 |
|--------|---|------|---------|------|
| 1 | 16 | fetchSessions 修复 | **已完成 (v5)** | commit d404735 |
| 2 | -- | TerminalView 拆分 | 部分完成 (v5) | 拆了 2/5 |
| 3 | 11 | 动态字体自适应 | **未做** | 连续 4 版 |
| 4 | 29 | Widget | **未做** | |
| 5 | 27 | 命令收藏 | **未做** | |
| 6 | 18 | App 图标 | **已完成 (v5)** | commit 3c7c4a1 |
| 7 | -- | debounce | **未做** | 连续 2 版 |
| 8 | -- | 大输出渲染优化 | **未做** | |
| 9 | -- | 通知内容增强 | **未做** | |
| 10 | -- | 滚动验证 | **未做** | 连续 4 版 |
| 计划外 | -- | Onboarding | **已完成 (v5)** | commit 957095e |
| 计划外 | -- | 文件上传 | **已完成 (v5)** | commit 87be968 |
| 计划外 | -- | DebugLogPanel | **已完成 (v5)** | commit 54c1bfd |

### C2. RICE Top 10（v6 最终版）

| 排名 | # | 功能 | R | I | C | E(人周) | RICE | 说明 |
|------|---|------|---|---|---|---------|------|------|
| **1** | 11 | **动态字体自适应** | 8 | 2 | 1.0 | 0.5 | **32.0** | 连续 4 版未做。`sizeChanged` 回调检测 `newCols`，不足 70 循环缩小 fontSize。这是 v6 不做就永远不会做的项目 |
| **2** | NEW | **滚动真机验证 + 修复** | 8 | 2 | 0.8 | 0.5 | **25.6** | 3/10 的评分洼地，连续 4 版代码完整但零验证。加浮动 "Exit Scroll" 按钮提升可发现性 |
| **3** | NEW | **快捷栏 Select 按钮** | 7 | 1 | 0.8 | 0.3 | **18.7** | 用户反复提到"长按选择可发现性差"。与 Web 端的 Select 按钮对齐 |
| **4** | NEW | **断线终端半透明遮罩** | 7 | 1 | 0.8 | 0.5 | **11.2** | 断线时内容可能过时，半透明黑色遮罩 + "Reconnecting..." 明确告知用户 |
| **5** | NEW | **TerminalView 剩余拆分** | 5 | 1 | 1.0 | 0.5 | **10.0** | 852 行仍需瘦身。提取 SwiftTermView / TerminalContainerView / IMETextField |
| **6** | NEW | **NetworkMonitor debounce** | 6 | 0.5 | 1.0 | 0.3 | **10.0** | 连续 2 版未做。WiFi 边界震荡可能导致频繁重连。2 秒 debounce |
| **7** | NEW | **通知/语音真机验证** | 6 | 1 | 0.6 | 0.5 | **7.2** | 连续 4 版代码完整但零验证。TestFlight 前必须确认端到端工作 |
| **8** | NEW | **LaunchScreen** | 8 | 0.5 | 1.0 | 0.3 | **13.3** | App 图标已有，LaunchScreen 应匹配。黑底 + 光标动画或静态 logo |
| **9** | NEW | **TestFlight 配置 + 回归测试** | 10 | 1 | 0.8 | 1.0 | **8.0** | Signing / Capabilities / TestFlight metadata / 全功能真机回归 |
| **10** | 27 | **命令收藏/快捷面板** | 8 | 2 | 0.8 | 2 | **6.4** | 常用命令收藏 + 一键发送，重度用户效率倍增器。v6 最终版的锦上添花功能 |

### C3. v6 路线图

v6 主题：**打磨发布 -- 清零遗留 + TestFlight 提交**

#### v6-alpha（3 天）-- 历史遗留清零

| 任务 | RICE | 预估 | 说明 |
|------|------|------|------|
| 动态字体自适应 | #1 | 0.5 天 | `sizeChanged` 回调中循环缩小 fontSize 至 cols >= 70 或 8pt 下限 |
| 滚动真机验证 + 修复 | #2 | 1 天 | 真机跑通完整流程 + 浮动 "Exit Scroll" 按钮 |
| TerminalView 剩余拆分 | #5 | 0.5 天 | 提取 SwiftTermView + TerminalContainerView + IMETextField |
| NetworkMonitor debounce | #6 | 0.3 天 | 2 秒 debounce |
| 通知/语音真机验证 | #7 | 0.5 天 | 端到端验证 + 修复 |

**v6-alpha 交付标准：字体自适应 + 滚动可用 + TerminalView <= 300 行 + 零未验证功能**

#### v6-beta（3 天）-- TestFlight 发布

| 任务 | RICE | 预估 | 说明 |
|------|------|------|------|
| 快捷栏 Select 按钮 | #3 | 0.3 天 | 长按进入选择模式的可视入口 |
| 断线终端半透明遮罩 | #4 | 0.3 天 | 半透明黑色遮罩 + "Reconnecting..." |
| LaunchScreen | #8 | 0.3 天 | 匹配 App 图标风格 |
| TestFlight 配置 + 回归测试 | #9 | 1 天 | Signing / Capabilities / metadata / 全功能回归 |
| 命令收藏（可选） | #10 | 1 天 | 时间允许的话做 |

**v6-beta 交付标准：TestFlight 可提交 + 零已知严重 bug + 全功能真机验证通过**

---

## D. 五版本迭代总结（v1-v5）

### D1. 用户评分趋势

| 版本 | 评分 | 变化 | 核心提分因素 | 核心失分因素 |
|------|------|------|-------------|-------------|
| v1 | -- | 基线 | SwiftTerm + WebSocket 基础架构 | 仅 MVP，无中文、无滚动、无状态指示 |
| v2 | 5.5/10 | 基线 | 滚动代码、语音、通知、剪贴板、设置页 | 中文未验证、快捷栏不全、假绿灯、无 session 结束检测 |
| v3 | 7.5/10 | +2.0 | isConnected 修正、session 结束检测、IMETextField、连接指示器、触觉反馈 | 快捷栏缺 NL、动态字体未做、滚动未验证 |
| v4 | 8.5/10 | +1.0 | NL+15 键快捷栏、NWPathMonitor、scenePhase 重连、auto-connect、session 切换 | 动态字体未做、滚动未验证、fetchSessions crash |
| v5 | **9.0/10** | **+0.5** | P0 修复、文件上传、App 图标、Onboarding、横屏优化、DebugLogPanel | 动态字体 4 版未做、滚动 4 版未验证 |

**评分趋势：5.5 -> 7.5 -> 8.5 -> 9.0**

v5 的 +0.5 评分提升来源分析：
- 文件上传追平 Web：与 Web 对比维度 +1.0
- App 图标 + Onboarding：首次启动体验 +0.5
- 横屏优化：终端可读性 +0.5
- 其余维度无变化（动态字体、滚动仍拖后腿）

### D2. 各版本核心贡献

| 版本 | 主题 | 核心贡献 | iOS 新增代码 | 新增文件数 |
|------|------|---------|-------------|-----------|
| **v1** | **奠基** | SwiftTerm + WebSocket + Session 选择器 + 设置页 | ~1200 行 | 10 |
| **v2** | **功能补全** | ScrollGestureHandler + VoiceManager + NotificationManager + ClipboardBridge + InputAccessoryBar | ~470 行 | 5 |
| **v3** | **可靠性** | ConnectionState 枚举 + DisconnectReason + IMETextField + session 结束检测 + 触觉反馈 + Safe Area | ~490 行 | 0（纯修改） |
| **v4** | **零摩擦** | NL+15 键快捷栏 + NWPathMonitor + scenePhase 重连 + auto-connect + session 切换 + 外接键盘检测 | ~340 行 | 1 |
| **v5** | **追平与发布准备** | P0 修复 + 文件拆分 + 文件上传 + 横屏优化 + DebugLogPanel + App 图标 + Onboarding + 版本号 | ~860 行 | 6 |

v5 是 **新增文件数最多的版本**（6 个），也是 **新增代码量最大的版本**（~860 行 iOS 代码）。

### D3. 整体架构成熟度评估

| 评估维度 | v1 | v2 | v3 | v4 | v5 | 说明 |
|---------|-----|-----|-----|-----|-----|------|
| **基本功能完整性** | 40% | 60% | 75% | 90% | **95%** | 文件上传补齐后仅剩动态字体、Widget |
| **稳定性/可信度** | 30% | 40% | 70% | 85% | **92%** | P0 修复 + DebugLogPanel 可诊断性 |
| **效率 vs Web** | 40% | 50% | 60% | 85% | **92%** | 文件上传超越 Web，Debug 超越 Web |
| **代码组织** | 70% | 60% | 50% | 45% | **65%** | TerminalToolbar/SessionSwitcher 提取 + DebugLogPanel/OnboardingView 独立模块 |
| **可发现性** | 50% | 50% | 55% | 65% | **70%** | Onboarding 引导新用户，但长按选择/滚动仍缺引导 |
| **品牌/专业感** | 30% | 30% | 30% | 35% | **70%** | App 图标 + Onboarding 大幅提升专业感。缺 LaunchScreen |
| **iOS 工作流融合** | 10% | 10% | 10% | 20% | **30%** | 文件上传 + Share Sheet 导出日志。无 Widget/Shortcuts/Siri |
| **TestFlight 就绪度** | 10% | 20% | 35% | 50% | **80%** | App 图标 + Onboarding + P0 修复 + DebugLogPanel + 版本号 5.0 |

**v5 最大跃升维度：品牌/专业感（35% -> 70%，+35pp）和 TestFlight 就绪度（50% -> 80%，+30pp）。** 这两个维度的大幅提升来自 App 图标和 Onboarding 的共同贡献。

### D4. 与 Web 终端对比总览（v5 更新）

| 维度 | Web | App v5 | 赢家 | v4->v5 变化 |
|------|-----|--------|------|------------|
| 首次配置 | URL 即用 | Onboarding 3 步引导 + IP 配置 | Web | 差距缩小 (Onboarding 新增) |
| 启动速度 | CDN 加载 | 原生秒开 + auto-connect | **App** | --> |
| 终端渲染 | xterm.js canvas | SwiftTerm 原生 | **App** | --> |
| 快捷键栏 | 12 按钮 | 16 按钮 + 分组 + NL | **App** | --> |
| 中文输入 | diff 模型 + 防抖 | IMETextField | **App** | --> |
| 触摸滚动 | 非线性加速 + 惯性 | 代码完整未验证 | Web | --> |
| 文本选择/复制 | Select mode overlay | 长按 overlay | 平手 | --> |
| 连接状态 | 无明确指示 | 四态 + NWPathMonitor | **App** | --> |
| 断线重连 | 指数退避 | 指数退避 + 网络感知 + 前后台 | **App** | --> |
| 文件上传 | POST /api/upload | PHPicker + DocumentPicker | **App** | **v5 翻盘** |
| 动态字体 | cols < 70 自动缩小 | 固定字号 | Web | --> |
| Debug 日志 | 事件追踪 overlay | DebugLogPanel + 分类过滤 + 导出 | **App** | **v5 翻盘** |
| 触觉反馈 | 无 | 6 种场景 | **App** | --> |
| 横屏体验 | 自动适配 | 隐藏顶栏 + 紧凑快捷栏 | **App** | **v5 新增** |
| App 图标/品牌 | N/A | 紫色渐变终端光标图标 | **App** | **v5 翻盘** |

**v5 在 15 个维度中赢 11 个、平 1 个、输 3 个。** v5 新翻盘的 3 个维度：文件上传、Debug 日志、App 图标。App 仍输的 3 个维度：首次配置（Web 仍更简单）、触摸滚动（未验证）、动态字体。

### D5. TestFlight 就绪度评估

| 检查项 | 状态 | 说明 |
|--------|------|------|
| App 无已知 crash 路径 | **通过** | fetchSessions P0 修复 |
| 核心功能完整 | **通过** | 连接/输入/显示/重连/上传 |
| App 图标 | **通过** | 紫色渐变 + 终端光标，commit 3c7c4a1 |
| Onboarding 引导 | **通过** | 3 页介绍 + IP 配置页，commit 957095e |
| 版本号一致性 | **通过** | Settings 显示 "5.0"，MARKETING_VERSION 5.0 |
| Debug 日志 | **通过** | DebugLogPanel + 分类过滤 + 导出 |
| 动态字体 | **未通过** | iPhone SE/mini 可读性差，连续 4 版 |
| 滚动浏览 | **未通过** | 从未真机验证，连续 4 版 |
| 通知/语音端到端 | **未通过** | 代码完整但零验证记录，连续 4 版 |
| 代码质量 | **基本通过** | TerminalView 852 行仍较大，但整体文件组织改善 |

**TestFlight 就绪度：7/10 项通过（70%）。** 较 v4 的 40% 大幅提升。剩余 3 项（动态字体、滚动验证、通知/语音验证）是 v6 的核心任务。

### D6. 代码量变化追踪（v1-v5）

| 文件 | v2 | v3 | v4 | v5 | v4->v5 |
|------|-----|-----|-----|-----|--------|
| ClaudeTerminalApp.swift | 12 | 12 | 11 | **33** | +22（shake gesture + onboarding） |
| Models/ServerConfig.swift | 79 | 79 | 78 | 78 | -- |
| Models/SessionModel.swift | 23 | 23 | 22 | 22 | -- |
| Audio/VoiceManager.swift | 205 | 205 | 204 | 204 | -- |
| Network/WebSocketManager.swift | ~260 | 435 | 434 | **440** | +6 |
| Network/ClipboardBridge.swift | 51 | 51 | 50 | 50 | -- |
| Network/NotificationManager.swift | 129 | 129 | 128 | 128 | -- |
| Network/NetworkMonitor.swift | -- | -- | 100 | **103** | +3 |
| **Network/FileUploadManager.swift** | -- | -- | -- | **249** | +249（新增） |
| Views/InputAccessoryBar.swift | 99 | 99 | 142 | **145** | +3 |
| Views/SessionPickerView.swift | 286 | 286 | 307 | **307** | -- (版本号改行不增数) |
| Views/TerminalView.swift | ~290 | 800 | 979 | **852** | -127 |
| **Views/TerminalToolbar.swift** | -- | -- | -- | **186** | +186（新增） |
| **Views/SessionSwitcher.swift** | -- | -- | -- | **67** | +67（新增） |
| **Views/DebugLogPanel.swift** | -- | -- | -- | **209** | +209（新增） |
| **Views/OnboardingView.swift** | -- | -- | -- | **245** | +245（新增） |
| Gestures/ScrollGestureHandler.swift | 235 | 235 | 234 | 234 | -- |
| **合计（iOS）** | **~1669** | **~2354** | **2689** | **3552** | **+863（+32%）** |

**v5 iOS 代码总量 3552 行，较 v4 增长 32%。** 新增 6 个文件（860+ 行），TerminalView 瘦身 127 行。最大文件从 979 行降至 852 行。文件数从 12 增至 17，平均文件大小从 224 行降至 209 行，代码组织有所改善。

### D7. 遗留问题追踪（v5 快照）

| 问题 | 文件 | 严重度 | 首次出现 | 累计版本数 | v6 处置 |
|------|------|--------|---------|-----------|---------|
| 动态字体缺失 | TerminalView.swift | **高** | v1 | **4 版** | v6-alpha 必做 |
| 滚动未真机验证 | ScrollGestureHandler.swift | **高** | v2 | **4 版** | v6-alpha 必做 |
| 通知/语音未验证 | NM/VM | 中 | v2 | **4 版** | v6-alpha 必做 |
| TerminalView 852 行 | TerminalView.swift | 中 | v3 | 3 版 | v6-alpha |
| NetworkMonitor 无 debounce | NetworkMonitor.swift | 低 | v4 | 2 版 | v6-alpha |
| 双输入路径 | TerminalView.swift | 低 | v3 | 3 版 | 不处理 |
| 外接键盘 magic number | TerminalView.swift | 低 | v4 | 2 版 | 不处理 |
| LaunchScreen 缺失 | -- | 低 | v2 | 4 版 | v6-beta |

### D8. 各维度评分详情（v5）

| 维度 | v2 | v3 | v4 | v5 | 变化 | 理由 |
|------|-----|-----|-----|-----|------|------|
| 首次启动体验 | 7 | 7 | 8.5 | **9.0** | +0.5 | Onboarding 3 步引导 + App 图标品牌感 |
| 终端可读性 | 7 | 7 | 7 | **7.5** | +0.5 | 横屏隐藏顶栏 + 紧凑快捷栏增加终端面积 |
| 打字体验 | 6 | 8 | 9 | **9** | -- | 无变化 |
| 滚动浏览 | 2 | 3 | 3 | **3** | -- | 仍未验证 |
| 复制粘贴 | 4 | 5 | 5 | **5** | -- | 无变化 |
| 网络稳定性 | 7 | 9 | 9.5 | **9.5** | -- | 无变化 |
| 语音功能 | 6 | 6 | 6 | **6** | -- | 无变化 |
| 通知 | 6 | 6 | 6 | **6** | -- | 无变化 |
| 与 Web 终端对比 | 5 | 6.5 | 7.5 | **8.5** | +1.0 | 文件上传翻盘 + Debug 翻盘 + App 图标翻盘，15 维度赢 11 |
| 整体感受 | 5 | 7.5 | 8.5 | **9.0** | +0.5 | "功能完整 + 有品牌感 + 新用户可上手" |
| **总评** | **5.5** | **7.5** | **8.5** | **9.0** | **+0.5** | |

### D9. 用户评语预测

> v5 是一个"补全"版本。文件上传终于有了，直接从相册选图比 Web 端还方便，上传过程有紫色进度环的视觉反馈。App 图标终于不是白方块了，紫色渐变加上终端光标，一看就是开发者工具。首次打开有 Onboarding 引导了，3 页介绍 + IP 配置，朋友拿到也知道怎么连。横屏模式隐藏顶栏让终端大了一截。Debug 面板摇一摇就出来，连接出问题时能看日志。
>
> 但老问题还在——动态字体还是没做，mini 上看 CC 表格折行；滚动四个版本了都没真机验证过，想回看历史还得切 Web。这两个问题已经是"房间里的大象"了。
>
> 整体来说，v5 是第一个"可以拿给别人看"的版本——有图标、有引导、功能基本完整。距离 TestFlight 只差把那几个老问题补上。

### D10. 版本里程碑甘特图

```
v1 (MVP):           [SwiftTerm] [WebSocket] [Session选择] [设置页]
v2 (功能补全):       [滚动代码] [语音] [通知] [剪贴板] [快捷栏9键]
v3 (可靠性):         [连接状态] [session结束] [中文输入] [触觉反馈] [Safe Area]
v4 (零摩擦):         [NL+15键] [网络感知] [前后台重连] [auto-connect] [session切换]
v5 (追平与发布准备): [P0修复] [文件拆分] [文件上传] [横屏优化] [Debug面板] [App图标] [Onboarding] [v5.0]
v6 (打磨发布):       [动态字体] [滚动验证] [继续拆分] [Select按钮] [遮罩] [LaunchScreen] [TestFlight]
```

---

## 关键结论

1. **v5 是产出最全面的版本。** 虽然对 v4 PM 计划的执行率仅 28%，但完成了 7 个 commit、6 个新文件、860+ 行 iOS 新增代码。计划外完成的 Onboarding 和 App 图标直接解决了 v4 PM 评估中列为 v5-beta / v6 的任务。

2. **v5 将 TestFlight 就绪度从 40% 提升至 70%。** App 图标、Onboarding、P0 修复、DebugLogPanel、版本号更新这五项组合消除了 TestFlight 提交的大部分阻塞项。剩余 3 项（动态字体、滚动验证、通知/语音验证）集中在"验证和适配"类工作。

3. **"房间里的大象"不能再忽视。** 动态字体和滚动验证从 v2 起每版 PM 评估都指出，已连续 4 版未做。v6 作为最终版本，这是最后机会。如果 v6 仍不解决，产品将带着 3/10 的滚动评分和 iPhone SE/mini 的可读性问题上 TestFlight。

4. **评分从 5.5 升至 9.0，产品已达"可推荐"水平。** v5 是第一个"可以拿给别人看"的版本——有专业图标、有新用户引导、功能接近完整。推荐门槛从 v4 的"直接推荐（但有 caveats）"变成了"放心推荐（滚动和小屏除外）"。

5. **v6 的工作量因 v5 的超额交付而大幅减少。** v4 PM 规划的 v5-beta 4 项任务中，App 图标和 Onboarding 已在 v5 完成。v6 只需聚焦 3 个核心遗留项（动态字体 + 滚动 + 通知/语音验证）+ TestFlight 配置，预估 6 天可完成。完成后预期达到 **9.3~9.5/10**。

6. **与 Web 终端的对比：App 已全面领先。** v5 在 15 个维度中赢 11、平 1、输 3，且输的 3 项中 2 项（滚动、字体）将在 v6 解决。到 v6 完成时，App 将仅在"首次配置"维度输给 Web（需要 IP vs URL 直接打开），在所有其他维度持平或领先。
