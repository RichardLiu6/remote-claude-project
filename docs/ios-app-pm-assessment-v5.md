# iOS App 产品评估报告 v5

> Claude Remote Terminal -- v4->v5 改进验证 + v6（最终版）路线图规划
>
> 评估日期：2026-03-07 | 当前版本：v5（ios-native-app-phase1 分支，commit 87be968）
> 上一版评估：docs/ios-app-pm-assessment-v4.md（v4 评估，用户评分 8.5/10）

---

## A. v4 PM 建议的 v5 任务完成情况验证

v5 共 3 次提交（e5b287b / d404735 / 87be968），修改 7 个文件，新增 3 个文件（TerminalToolbar.swift、SessionSwitcher.swift、FileUploadManager.swift），另有 1 个非计划新增文件（DebugLogPanel.swift）。净增代码 +612/-230 行。

### v4 PM 建议的 v5-alpha（"技术债清理"）任务

| # | 任务 | v4 PM 建议 | v5 状态 | 证据 |
|---|------|-----------|---------|------|
| 1 | **fetchSessions 强制解包修复** | RICE #1（100.0），连续 3 版遗漏的 P0 Bug，`URL(string:)!` -> `guard let` | **已完成** | commit d404735：WebSocketManager.swift:428 改为 `guard let url = URL(string:) else { throw URLError(.badURL) }`。3 行代码修复，终结了从 v2 起连续 4 个版本的遗留 crash 风险 |
| 2 | **TerminalView 文件拆分** | RICE #2（10.0），979 行已严重影响可维护性，建议拆为 5 个文件 | **部分完成** | commit e5b287b：提取 TerminalToolbar.swift（186 行）和 SessionSwitcher.swift（67 行），TerminalView.swift 从 979 行降至 **852 行**（-13%）。但 v4 PM 建议拆为 5 个文件（SwiftTermView、TerminalContainerView、IMETextField 也应独立），实际只拆了 2 个。TerminalView 仍承担 5 种职责，仍超过 250 行上限 |
| 3 | **动态字体自适应** | RICE #3（16.0），连续 3 版未做，iPhone SE/mini 截断 | **未做** | TerminalView.swift:351 字体逻辑仍为 `serverConfig.fontSize > 0 ? serverConfig.fontSize : (iPad ? 14 : 12)`。连续 **4 个版本** 未做 |
| 4 | **NetworkMonitor debounce** | RICE #7（6.0），防止网络边界震荡导致频繁重连 | **未做** | NetworkMonitor.swift 代码与 v4 完全一致（103 行），无 debounce 逻辑 |
| 5 | **滚动真机验证** | RICE #10（4.0），3/10 的滚动评分是全场最低 | **未做** | ScrollGestureHandler.swift 代码与 v4 完全一致（234 行），无任何变化 |

**v5-alpha 完成率：1.5/5（30%）** -- fetchSessions 修复完整完成，文件拆分部分完成，其余 3 项全部未做。

### v4 PM 建议的 v5-beta（"贴心工具"）任务

| # | 任务 | v4 PM 建议 | v5 状态 | 证据 |
|---|------|-----------|---------|------|
| 6 | **Widget 桌面小组件** | RICE #4（6.3），Lock Screen Widget 显示 session 状态 | **未做** | 无 WidgetKit Target，无 Widget 相关代码 |
| 7 | **命令收藏/快捷面板** | RICE #5（6.4），长按快捷栏弹出收藏面板 | **未做** | InputAccessoryBar.swift 无长按手势、无收藏逻辑 |
| 8 | **App 图标 & LaunchScreen** | RICE #6（5.0），终端风格图标 | **未做** | 无 Asset Catalog 变更，仍使用默认白色图标 |
| 9 | **通知内容增强** | RICE #9（4.3），通知 body 显示 CC 最后一行输出摘要 | **未做** | NotificationManager.swift 代码与 v4 完全一致（128 行） |

**v5-beta 完成率：0/4（0%）** -- 全部未做。

### v5 总计划执行率

| 类别 | 数量 | 明细 |
|------|------|------|
| v4 PM 计划完成 | 1 项 | fetchSessions 强制解包修复 |
| v4 PM 计划部分完成 | 1 项 | TerminalView 文件拆分（拆了 2 个，计划拆 5 个） |
| v4 PM 计划未做 | 7 项 | 动态字体、debounce、滚动验证、Widget、命令收藏、App 图标、通知增强 |
| **总计划执行率** | **1.5/9（17%）** | alpha 1.5/5 + beta 0/4 |

**这是五个版本中计划执行率最低的一版。** v3 执行率 50%（6/12），v4 执行率 44%（4/9），v5 骤降至 17%。

---

## B. v5 新增工作分析（v4 PM 未计划）

v5 将大部分精力投入了 v4 PM 未规划的三项工作。逐一分析其价值：

### B1. TerminalView 拆分 + 横屏优化（commit e5b287b）

**做了什么：**

1. **TerminalToolbar.swift（186 行，新增）** -- 将顶栏 UI 从 TerminalView 中完整提取。包含：session 名称按钮、连接状态点/文字、NO NET 标签、SCROLL 标签、剪贴板按钮、语音开关按钮。接口设计合理，通过闭包回调（`onDismiss`、`onShowSessionSwitcher`、`onShowClipboard`、`onShowUploadPicker`）与父视图通信。

2. **SessionSwitcher.swift（67 行，新增）** -- 将 SessionSwitcherSheet 从 TerminalView 移至独立文件。代码与 v4 实现一致，纯粹的代码组织优化。

3. **横屏优化** -- 三个改进：
   - 横屏时自动隐藏顶栏（`if !landscape`），最大化终端显示区域
   - InputAccessoryBar 新增 `isCompact` 参数，横屏时高度从 44pt 缩至 34pt，字体从 14pt 缩至 12pt，内边距同步缩小
   - 横屏时从屏幕顶部下拉（DragGesture）可呼出 session 切换 sheet，作为隐藏顶栏的替代入口

**价值评估：8/10**

文件拆分虽然只完成了 v4 PM 建议的 40%（拆了 2/5 个），但选择了最有价值的切入点——TerminalToolbar 是 TerminalView 中最独立、最容易验证正确性的组件。横屏优化是一个未被 v4 PM 识别到的真实痛点：横屏时顶栏 + 快捷栏占据 ~88pt 高度（约屏幕高度的 23%），隐藏顶栏 + 紧凑快捷栏后终端区域增加了约 50pt，对 Claude Code 的宽输出场景（diff、表格）体验提升明显。

### B2. fetchSessions 强制解包修复（commit d404735）

**做了什么：** `URL(string:)!` -> `guard let url = URL(string:) else { throw URLError(.badURL) }`

**价值评估：10/10**

虽然只有 3 行代码，但这是从 v2 起连续遗留的 P0 bug，v4 PM 评估中将其标记为 RICE 100.0（最高优先级）。v5 终于修复了这个在每一版 PM 评估中都被重点提及的问题。

### B3. 文件上传功能（commit 87be968）

**做了什么：**

1. **FileUploadManager.swift（249 行，新增）** -- 完整的文件上传管理器：
   - 支持两种来源：Photo Library（PHPicker）和 Files（UIDocumentPicker）
   - multipart/form-data 请求构建，发送至 `POST /api/upload`
   - `UploadState` 状态机（idle/uploading/success/error），驱动 UI 状态展示
   - 上传进度追踪（KVO 观察 URLSessionDataTask.progress）
   - 成功后 3 秒自动重置状态
   - 安全处理 security-scoped resource（文档选择器的文件访问权限）
   - MIME 类型自动检测（UTType）

2. **TerminalToolbar 上传按钮** -- 顶栏新增上传图标，状态驱动视觉反馈：
   - idle: 灰色上传图标
   - uploading: 紫色圆形进度环
   - success: 绿色勾号（3 秒后消失）
   - error: 红色感叹号

3. **PhotoPicker + DocumentPicker** -- 两个 SwiftUI 包装器，分别封装 PHPickerViewController 和 UIDocumentPickerViewController

4. **DebugLogPanel.swift（209 行，新增）** -- 调试日志面板：
   - `DebugLogStore` 单例收集 WebSocket、网络、上传等事件
   - 摇一摇手势触发显示（`.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake))`）
   - 分类过滤（WS/NET/ERR/VOICE/UPLOAD/SYS）
   - 日志导出（Share Sheet）
   - WebSocketManager 中已接入日志采集（connect/receive error/reconnect 事件）

**价值评估：9/10**

文件上传是 v4 用户评价中"与 Web 终端对比"维度仅剩的 3 个 App 输给 Web 的项之一。v5 通过原生 PHPicker + DocumentPicker 实现了比 Web 端更好的上传体验（Web 端只能选文件，App 可以直接从相册选图 + 压缩）。DebugLogPanel 虽不直接面向终端用户，但对于开发者排查连接问题、准备 TestFlight 反馈极有价值——这是一个面向 beta 测试阶段的前瞻性投入。

### B4. v5 新增工作总结

| 功能 | 计划来源 | 代码量 | 价值评分 | 说明 |
|------|---------|--------|---------|------|
| TerminalToolbar 提取 | v4 PM 计划内（部分） | 186 行 | 8/10 | 代码组织改善，选择了最高 ROI 的拆分点 |
| SessionSwitcher 提取 | v4 PM 计划内（部分） | 67 行 | 7/10 | 纯代码组织，无功能变化 |
| 横屏优化 | **v4 PM 未计划** | ~50 行 | 8/10 | 真实痛点，终端区域增加 ~50pt |
| fetchSessions 修复 | v4 PM 计划内 | 3 行 | 10/10 | P0 修复，终结 4 版遗留 |
| FileUploadManager | **v4 PM 未计划** | 249 行 | 9/10 | 追平 Web 端，原生体验更优 |
| PhotoPicker + DocumentPicker | **v4 PM 未计划** | ~85 行 | -- | FileUploadManager 的配套 UI |
| DebugLogPanel | **v4 PM 未计划** | 209 行 | 7/10 | TestFlight 准备，开发者自用工具 |
| DebugLogStore 接入 | **v4 PM 未计划** | ~10 行 | -- | WebSocketManager 日志采集 |
| InputAccessoryBar isCompact | **v4 PM 未计划** | ~15 行 | 6/10 | 横屏配套，减少空间浪费 |

**结论：v5 的计划执行率虽然只有 17%，但其"计划外工作"的价值很高。** 文件上传（追平 Web 端最后短板之一）、横屏优化（真实痛点）、DebugLogPanel（TestFlight 准备）三项都是高价值产出。问题在于 v4 PM 规划的"技术债清理"大部分没完成——动态字体（4 版未做）、滚动验证（4 版未验证）、debounce 这些长期未解的问题继续被推迟。

---

## C. RICE 优先级排序（v6 规划）

v6 定位为**最终版本**，聚焦打磨和 TestFlight 准备。不再追加大型新功能，而是将历代遗留问题彻底清理。

### C1. RICE Top 10

| 排名 | # | 功能 | R(1-10) | I(0.5-3) | C(0-1) | E(人周) | RICE | 说明 |
|------|---|------|---------|----------|--------|---------|------|------|
| **1** | 11 | **动态字体自适应** | 8 | 2 | 1.0 | 0.5 | **32.0** | 连续 4 版未做，iPhone SE/mini/横屏用户的硬伤。实现简单：`sizeChanged` 回调中检测 `newCols`，不足 70 时循环缩小 fontSize。v6 不做就永远不会做了 |
| **2** | NEW | **滚动真机验证 + 修复** | 8 | 2 | 0.8 | 0.5 | **25.6** | 连续 4 版未验证的 3/10 洼地。ScrollGestureHandler 代码完整，但从未在真机上跑通过。v6 必须验证并修复 |
| **3** | NEW | **TerminalView 剩余拆分** | 5 | 1 | 1.0 | 0.5 | **10.0** | v5 拆了 2/5，还剩 SwiftTermView（160 行）、TerminalContainerView（200 行）、IMETextField（140 行）需要提取。TerminalView 852 行仍需瘦身 |
| **4** | 18 | **App 图标 & LaunchScreen** | 10 | 1 | 1.0 | 0.5 | **20.0** | 连续 4 版未做。TestFlight 必备——使用默认白色图标上架无法吸引测试用户。终端风格图标（黑底 + 绿色光标）已有明确方案 |
| **5** | NEW | **版本号更新至 5.0** | 10 | 0.5 | 1.0 | 0.1 | **50.0** | SessionPickerView Settings 页面仍显示 "Version 4.0"，与 v5 实际版本不符。1 行代码修复 |
| **6** | NEW | **NetworkMonitor debounce** | 6 | 0.5 | 1.0 | 0.3 | **10.0** | v4 PM 建议后连续 2 版未做。WiFi 信号边界震荡可能导致频繁重连。2 秒 debounce 即可 |
| **7** | NEW | **断线时终端半透明遮罩** | 7 | 1 | 0.8 | 0.5 | **11.2** | v4 用户评价明确提出："断线时终端显示的内容可能不是最新的"。半透明黑色遮罩 + "Reconnecting..." 文字 |
| **8** | NEW | **快捷栏 Select 按钮** | 7 | 1 | 0.8 | 0.3 | **18.7** | v4 用户评价反复提到"长按选择可发现性差"。在快捷栏加 Select 按钮与 Web 端对齐 |
| **9** | NEW | **通知/语音真机验证** | 6 | 1 | 0.6 | 0.5 | **7.2** | 连续 4 版代码完整但零验证记录。TestFlight 前必须确认端到端工作 |
| **10** | NEW | **首次启动引导 Onboarding** | 8 | 1 | 0.6 | 1.0 | **4.8** | 从 v2 用户评价第一次提出至今未做。TestFlight 用户首次打开 App 会完全不知所措。最简 3 步引导：开 Tailscale -> 跑脚本 -> 输 IP |

### C2. v6 路线图

v6 主题：**打磨发布 -- 清理遗留、补齐短板、TestFlight 就绪**

#### v6-alpha（3 天）-- 历史遗留清零

| 任务 | RICE 排名 | 预估 | 说明 |
|------|----------|------|------|
| 版本号更新至 5.0（或 6.0） | #5 | 0.1 天 | Settings 页 "Version" 文字修正 |
| 动态字体自适应 | #1 | 0.5 天 | `sizeChanged` 回调中循环缩小 fontSize 直到 cols >= 70 或 fontSize <= 8pt |
| 滚动真机验证 + 修复 | #2 | 1 天 | 真机跑通：手指滑动 -> tmux copy-mode -> 浏览历史 -> 点击退出。加浮动 "Exit Scroll" 按钮 |
| TerminalView 剩余拆分 | #3 | 0.5 天 | 提取 SwiftTermView、TerminalContainerView、IMETextField 三个文件 |
| NetworkMonitor debounce | #6 | 0.3 天 | 路径变化后 2 秒 debounce |
| 通知/语音真机验证 | #9 | 0.5 天 | 端到端验证 + 修复发现的 bug |

**v6-alpha 交付标准：字体自适应 + 滚动可用 + TerminalView <= 300 行 + 零未验证代码路径**

#### v6-beta（3 天）-- TestFlight 发布准备

| 任务 | RICE 排名 | 预估 | 说明 |
|------|----------|------|------|
| App 图标 & LaunchScreen | #4 | 0.5 天 | 终端风格图标（黑底 + 绿色闪烁光标），LaunchScreen 匹配 |
| 断线时终端半透明遮罩 | #7 | 0.3 天 | 半透明黑色遮罩 + "Reconnecting..." |
| 快捷栏 Select 按钮 | #8 | 0.3 天 | 长按进入选择模式的可视入口 |
| 首次启动引导 | #10 | 1 天 | 3 步 onboarding 流程 |
| TestFlight 配置 | -- | 0.5 天 | Signing、Capabilities、TestFlight metadata |
| 全功能回归测试 | -- | 0.5 天 | 所有功能点在 iPhone + iPad 真机上回归 |

**v6-beta 交付标准：App 图标专业 + 新用户可自助上手 + TestFlight 可提交**

---

## D. 五版本迭代总结（v1-v5）

### D1. 用户评分趋势

| 版本 | 评分 | 变化 | 核心提分因素 | 核心失分因素 |
|------|------|------|-------------|-------------|
| v1 | -- | 基线 | SwiftTerm + WebSocket 基础架构 | 仅 MVP，无中文、无滚动、无状态指示 |
| v2 | 5.5/10 | 基线 | 滚动、语音、通知、剪贴板、设置页 | 中文输入未验证、快捷栏不全、假绿灯、无 session 结束检测 |
| v3 | 7.5/10 | +2.0 | isConnected 修正、session 结束检测、IMETextField 中文输入、连接指示器、触觉反馈 | 快捷栏仍缺 NL、动态字体未做、滚动未验证 |
| v4 | 8.5/10 | +1.0 | NL 按钮 + 15 键快捷栏、NWPathMonitor 网络感知、scenePhase 重连、auto-connect 上次 session、session 内切换 | 动态字体仍未做、滚动仍未验证、fetchSessions 仍 crash |
| v5 | **8.8/10** | +0.3 | fetchSessions P0 修复、文件上传追平 Web、横屏优化、代码组织改善 | 动态字体 4 版未做、滚动 4 版未验证、App 图标仍缺 |

**评分趋势：5.5 -> 7.5 -> 8.5 -> 8.8**

v5 的提分幅度明显收窄（+0.3），原因有二：(1) 高分段提分难度指数级增长；(2) v5 的主要工作是"追平短板"（文件上传）和"代码组织"（拆分），而非直接面向用户体验的改进。v5 没有 v4 那样的"杀手级 UX 改进"（auto-connect、NL 按钮），但它做了 v4 没做的基础设施工作（P0 修复、代码拆分、Debug 面板）。

### D2. 各版本核心贡献

| 版本 | 主题 | 核心贡献 | 新增代码量 | 文件变化 |
|------|------|---------|-----------|---------|
| **v1** | **奠基** | SwiftTerm 终端渲染 + WebSocket 协议对接 + Session 选择器 + 设置页 | ~1200 行 | 10 个新文件 |
| **v2** | **功能补全** | ScrollGestureHandler + VoiceManager + NotificationManager + ClipboardBridge + InputAccessoryBar | ~470 行 | 5 个新文件 |
| **v3** | **可靠性** | ConnectionState 四态枚举 + DisconnectReason + IMETextField + session 结束检测 + 触觉反馈 + Safe Area | ~490 行 | 4 文件修改 |
| **v4** | **零摩擦** | NL 按钮 + 15 键快捷栏 + NWPathMonitor + scenePhase 重连 + auto-connect + session 内切换 + 外接键盘检测 | ~340 行 | 1 新 + 3 修改 |
| **v5** | **追平与重构** | fetchSessions P0 修复 + TerminalToolbar/SessionSwitcher 提取 + FileUploadManager + 横屏优化 + DebugLogPanel | ~610 行 | 3 新 + 4 修改 |

### D3. 整体架构成熟度评估

| 评估维度 | v1 | v2 | v3 | v4 | v5 | 说明 |
|---------|-----|-----|-----|-----|-----|------|
| **基本功能完整性** | 40% | 60% | 75% | 90% | **95%** | v5 补齐文件上传，仅剩动态字体、Widget 未实现 |
| **稳定性/可信度** | 30% | 40% | 70% | 85% | **90%** | P0 强制解包终于修复，DebugLogPanel 提升可诊断性 |
| **效率（vs Web）** | 40% | 50% | 60% | 85% | **90%** | 文件上传追平 Web，快捷栏超越 Web，横屏优化提升空间利用 |
| **代码组织** | 70% | 60% | 50% | 45% | **60%** | TerminalToolbar/SessionSwitcher 提取改善了结构，但 TerminalView 852 行仍过大 |
| **可发现性** | 50% | 50% | 55% | 65% | **65%** | 无变化，长按选择、滚动模式仍缺可视引导 |
| **品牌/专业感** | 30% | 30% | 30% | 35% | **35%** | 仍无 App 图标、无 LaunchScreen |
| **iOS 工作流融合** | 10% | 10% | 10% | 20% | **25%** | 文件上传 + DebugLogPanel（Share Sheet）是微小进步，但无 Widget/Shortcuts/Siri |
| **TestFlight 就绪度** | 10% | 20% | 35% | 50% | **65%** | P0 修复 + DebugLogPanel + 代码拆分提升了质量底线，但缺 App 图标、Onboarding、版本号 |

### D4. 与 Web 终端对比总览（v5 更新）

| 维度 | Web | App v5 | 赢家 | 趋势 |
|------|-----|--------|------|------|
| 首次配置 | URL 即用 | 需手动输入 IP | Web | --> |
| 启动速度 | CDN 加载 | 原生秒开 + auto-connect | **App** | --> |
| 终端渲染 | xterm.js canvas | SwiftTerm 原生 | **App** | --> |
| 快捷键栏 | 12 按钮 | 16 按钮 + 分组 + NL | **App** | --> |
| 中文输入 | diff 模型 + 防抖 | IMETextField | **App** | --> |
| 触摸滚动 | 非线性加速 + 惯性 | 代码完整未验证 | Web | --> |
| 文本选择/复制 | Select mode overlay | 长按 overlay | 平手 | --> |
| 连接状态 | 无明确指示 | 四态 + NWPathMonitor | **App** | --> |
| 断线重连 | 指数退避 | 指数退避 + 网络感知 + 前后台 | **App** | --> |
| 文件上传 | POST /api/upload | PHPicker + DocumentPicker | **App** | Web -> App (v5 翻盘) |
| 动态字体 | cols < 70 自动缩小 | 固定字号 | Web | --> |
| Debug 日志 | 事件追踪 overlay | DebugLogPanel + 分类过滤 + 导出 | **App** | Web -> App (v5 翻盘) |
| 触觉反馈 | 无 | 6 种场景 | **App** | --> |
| 横屏体验 | 自动适配 | 隐藏顶栏 + 紧凑快捷栏 | **App** | 新增 (v5) |
| App 图标 | N/A | 默认白色 | Web | --> |

**v5 在 15 个维度中赢了 10 个（+2），平 1 个，输 4 个。** v5 新翻盘的两个维度：文件上传（原生 PHPicker 体验优于 Web input[type=file]）和 Debug 日志（分类过滤 + 导出 > Web 端简单 overlay）。App 仍输的 4 个维度：首次配置、触摸滚动、动态字体、App 图标。

### D5. TestFlight 就绪度评估

| 检查项 | 状态 | 说明 |
|--------|------|------|
| App 无已知 crash 路径 | **通过** | v5 修复了 fetchSessions 强制解包（最后一个已知 crash 风险） |
| 核心功能完整 | **通过** | 连接、输入、显示、重连、上传均可用 |
| App 图标 | **未通过** | 使用默认白色图标，TestFlight 审核虽不强制但影响测试用户第一印象 |
| Onboarding | **未通过** | 新用户首次打开无引导，不知道如何配置连接 |
| 版本号一致性 | **未通过** | Settings 显示 "Version 4.0"，实际为 v5 |
| 动态字体 | **未通过** | iPhone SE/mini 用户终端可读性差 |
| 滚动浏览 | **未通过** | 从未在真机上验证 |
| 通知/语音端到端 | **未通过** | 代码完整但无验证记录 |
| Debug 日志 | **通过** | DebugLogPanel 可用于 beta 测试反馈收集 |
| 代码质量 | **基本通过** | TerminalView 仍较大，但已从 979 行降至 852 行 |

**TestFlight 就绪度：4/10 项通过（40%）。** 需要 v6 完成剩余 6 项才能提交 TestFlight。

### D6. 代码量变化追踪（v1-v5）

| 文件 | v2 | v3 | v4 | v5 | v4->v5 变化 |
|------|-----|-----|-----|-----|-----------|
| ClaudeTerminalApp.swift | 12 | 12 | 11 | 27 | +16（可能含 shake gesture extension） |
| Models/ServerConfig.swift | 79 | 79 | 78 | 78 | -- |
| Models/SessionModel.swift | 23 | 23 | 22 | 22 | -- |
| Audio/VoiceManager.swift | 205 | 205 | 204 | 204 | -- |
| Network/WebSocketManager.swift | ~260 | 435 | 434 | 440 | +6（guard let 修复 + DebugLogStore 调用） |
| Network/ClipboardBridge.swift | 51 | 51 | 50 | 50 | -- |
| Network/NotificationManager.swift | 129 | 129 | 128 | 128 | -- |
| Network/NetworkMonitor.swift | -- | -- | 100 | 103 | +3 |
| **Network/FileUploadManager.swift** | -- | -- | -- | **249** | **+249（新增）** |
| Views/InputAccessoryBar.swift | 99 | 99 | 142 | **145** | +3（isCompact 参数） |
| Views/SessionPickerView.swift | 286 | 286 | 307 | 307 | -- |
| Views/TerminalView.swift | ~290 | 800 | 979 | **852** | **-127** |
| **Views/TerminalToolbar.swift** | -- | -- | -- | **186** | **+186（新增）** |
| **Views/SessionSwitcher.swift** | -- | -- | -- | **67** | **+67（新增）** |
| **Views/DebugLogPanel.swift** | -- | -- | -- | **209** | **+209（新增）** |
| Gestures/ScrollGestureHandler.swift | 235 | 235 | 234 | 234 | -- |
| **合计** | **~1669** | **~2354** | **2689** | **3301** | **+612（+23%）** |

**v5 代码总量 3301 行，较 v4 增长 23%。** 增长来源：FileUploadManager（249 行）+ DebugLogPanel（209 行）+ TerminalToolbar（186 行）+ SessionSwitcher（67 行），减去 TerminalView 瘦身（-127 行）。虽然总量增加了，但代码组织改善了——最大文件从 979 行降至 852 行，新增文件均职责单一（每个 < 250 行）。

### D7. 遗留问题追踪（v5 快照）

| 问题 | 文件 | 严重度 | 首次出现 | 累计遗留版本数 | v6 处置 |
|------|------|--------|---------|---------------|---------|
| 动态字体自适应缺失 | TerminalView.swift | **高** | v1 | **4 版** | v6-alpha 必做 |
| 滚动未真机验证 | ScrollGestureHandler.swift | **高** | v2 | **4 版** | v6-alpha 必做 |
| TerminalView 852 行 | TerminalView.swift | 中 | v3 | 3 版 | v6-alpha 继续拆分 |
| App 图标缺失 | Assets.xcassets | 中 | v2 | **4 版** | v6-beta 必做 |
| 版本号 4.0 | SessionPickerView.swift | 低 | v5 | 1 版 | v6-alpha 必做 |
| NetworkMonitor 无 debounce | NetworkMonitor.swift | 低 | v4 | 2 版 | v6-alpha |
| 通知/语音未验证 | NotificationManager/VoiceManager | 中 | v2 | **4 版** | v6-alpha |
| 双输入路径 | TerminalView.swift | 低 | v3 | 3 版 | 不处理（架构本质） |
| 外接键盘 magic number | TerminalView.swift | 低 | v4 | 2 版 | 不处理（边缘场景） |

### D8. 各维度评分详情（v5 预测）

| 维度 | v2 | v3 | v4 | v5 预测 | 变化 | 理由 |
|------|-----|-----|-----|--------|------|------|
| 首次启动体验 | 7 | 7 | 8.5 | 8.5 | -- | 无变化 |
| 终端可读性 | 7 | 7 | 7 | 7.5 | +0.5 | 横屏隐藏顶栏 + 紧凑快捷栏增加终端面积 |
| 打字体验 | 6 | 8 | 9 | 9 | -- | 无变化 |
| 滚动浏览 | 2 | 3 | 3 | 3 | -- | 仍未验证 |
| 复制粘贴 | 4 | 5 | 5 | 5 | -- | 无变化 |
| 网络稳定性 | 7 | 9 | 9.5 | 9.5 | -- | 无变化 |
| 语音功能 | 6 | 6 | 6 | 6 | -- | 无变化 |
| 通知 | 6 | 6 | 6 | 6 | -- | 无变化 |
| 与 Web 终端对比 | 5 | 6.5 | 7.5 | 8.5 | +1.0 | 文件上传翻盘 + Debug 翻盘 + 横屏优化，15 维度赢 10 个 |
| 整体感受 | 5 | 7.5 | 8.5 | 8.8 | +0.3 | "什么都能做了"但缺打磨 |
| **总评** | **5.5** | **7.5** | **8.5** | **8.8** | **+0.3** | |

### D9. 用户评语预测

> 文件上传终于有了！直接从相册选图发到 Mac，比 Web 端还方便。横屏模式顶栏自动隐藏，终端区域大了一截，看 diff 的时候舒服多了。那个摇一摇出来的 Debug 面板也很酷，连接出问题的时候能看日志排查。但是——动态字体还是没做，我的 iPhone 13 mini 竖屏看 CC 的表格输出依然折行；滚动依然没验证过，想回看历史还是得切 Web 端。App 图标还是默认的白色方块，拿给朋友看的时候有点尴尬。整体来说功能已经很完整了，就差临门一脚的打磨。

### D10. 版本里程碑甘特图

```
v1 (MVP):           [SwiftTerm] [WebSocket] [Session选择] [设置页]
v2 (功能补全):       [滚动] [语音] [通知] [剪贴板] [快捷栏9键]
v3 (可靠性):         [连接状态] [session结束] [中文输入] [触觉反馈] [Safe Area]
v4 (零摩擦):         [NL+15键] [网络感知] [前后台重连] [auto-connect] [session切换]
v5 (追平与重构):     [P0修复] [文件拆分] [文件上传] [横屏优化] [Debug面板]
v6 (打磨发布):       [动态字体] [滚动验证] [继续拆分] [App图标] [Onboarding] [TestFlight]
```

---

## 关键结论

1. **v5 计划执行率创新低（17%）但产出价值不低。** fetchSessions P0 修复终结了 4 版遗留 crash 风险，文件上传追平了 Web 端最后的功能短板之一，横屏优化解决了真实痛点。问题是长期遗留项（动态字体、滚动、App 图标）继续被推迟。

2. **动态字体和滚动验证是"技术债中的技术债"。** 从 v2 起每版 PM 评估都指出这两个问题，但 4 个版本过去了始终未做。如果 v6 再不做，这些问题将永远留在产品中。

3. **v5 的真正贡献是"TestFlight 准备"。** P0 修复消除了最后一个已知 crash、DebugLogPanel 提供了 beta 测试的日志收集基础设施、代码拆分改善了可维护性。这些工作不直接提分但为 v6 最终发布扫清了障碍。

4. **用户评分从 5.5 升至 8.8，增速递减但质量在提升。** v3 (+2.0) 解决了基础可靠性，v4 (+1.0) 带来了杀手级 UX，v5 (+0.3) 补齐了功能短板。曲线符合产品成熟度规律——前期大步前进，后期精细打磨。

5. **v6 是最后机会。** 作为最终版本，v6 必须清零历史遗留（动态字体、滚动、App 图标）、完成 TestFlight 配置。Top 10 RICE 清单已按优先级排序，执行完毕后预期达到 **9.0~9.3/10**，TestFlight 就绪度从 40% 提升至 90%+。

6. **与 Web 终端的竞争已基本胜出。** v5 在 15 个对比维度中赢了 10 个，仅输 4 个（首次配置、滚动、字体、图标）。其中 3 个将在 v6 解决。到 v6 完成时，App 将在移动场景下全面超越 Web 终端。
