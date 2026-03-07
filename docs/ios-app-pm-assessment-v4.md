# iOS App 产品评估报告 v4

> Claude Remote Terminal -- v3->v4 改进验证 + v5 路线图规划
>
> 评估日期：2026-03-07 | 当前版本：v4（ios-native-app-phase1 分支，commit a0578e3）
> 上一版评估：docs/ios-app-pm-assessment-v3.md（v3 评估，用户评分 7.5/10）

---

## A. v3 -> v4 改进验证

v4 共 3 次提交（4063c44 / 1cf159e / a0578e3），修改 4 个文件，新增 1 个文件（NetworkMonitor.swift），净增 406 行（+406 / -60）。

### v3 PM 建议的 v4-alpha/beta 任务完成情况

#### v4-alpha（"快速修复遗留"）

| 任务 | v3 PM 建议 | v4 状态 | 证据 |
|------|-----------|---------|------|
| **fetchSessions 强制解包修复** | v3 遗漏的 #3 Bug，`URL(string:)!` -> `guard let` | **未修复** | WebSocketManager.swift:424 仍为 `URL(string: "...")!`，与 v3 完全相同。这是连续两个版本遗漏的已知 crash 风险 |
| **快捷键栏补全（NL/方向键）** | RICE #1，NL 是用户评价第一痛点 | **已完成** | InputAccessoryBar.swift 全面重写：NL 键放首位（绿色高亮）+ Tab/^C/Esc + 左右上下方向键 + ^A/^E/^R/^D/^Z/^L，共 15 个按键，分三组（Divider 分隔）。从 9 键 -> 15 键，覆盖度超过 Web 端的 12 键 |
| **动态字体自适应** | RICE #3，iPhone SE/mini 截断问题 | **未做** | TerminalView.swift 字体逻辑仍为 `serverConfig.fontSize > 0 ? serverConfig.fontSize : (iPad ? 14 : 12)`，无 cols 检测和自动缩小逻辑 |
| **scenePhase 前后台重连** | RICE #10，App 切回前台自动重连 | **已完成** | TerminalView.swift:131 `.onChange(of: scenePhase)` 检测 `.active`，若 WebSocket 未连接则调用 `reconnect()`。实现简洁正确 |
| **通知+语音真机验证** | 代码完整但缺真机验证记录 | **未做** | NotificationManager 和 VoiceManager 代码无任何变化，未见验证记录 |

**v4-alpha 完成率：2/5（40%）**

#### v4-beta（"效率提升"）

| 任务 | v3 PM 建议 | v4 状态 | 证据 |
|------|-----------|---------|------|
| **NWPathMonitor 网络感知** | RICE #4，WiFi/蜂窝切换主动重连 | **已完成** | 新增 NetworkMonitor.swift（100 行），使用 NWPathMonitor 监听网络路径变化。检测三种事件：网络恢复（`onNetworkRestored`）、网络丢失（`onNetworkLost`）、路径类型切换（WiFi -> Cellular，同样触发 `onNetworkRestored`）。TerminalView.onAppear 中正确接入回调，网络恢复时检查 WebSocket 状态并按需重连。顶栏增加红色 "NO NET" 标签 |
| **Session 内切换** | RICE #6，需退出 picker 重选 | **已完成** | TerminalView 顶栏 session 名改为可点击 Button，点击后异步获取 session 列表并弹出 `SessionSwitcherSheet`（半高 sheet）。切换逻辑：断开当前 WebSocket -> 更新 session 名 -> 重新连接 + 更新语音/通知 session。Sheet UI 设计精良：当前 session 绿色高亮 + checkmark，每个 session 显示 window 数量和创建时间 |
| **TerminalView 文件拆分** | v3 评估 800 行，建议拆分 | **未做** | TerminalView.swift 从 800 行膨胀到 **979 行**（+22%），新增 SessionSwitcherSheet 视图内嵌于同一文件底部。IMETextField（150 行）和 TerminalContainerView（200 行）仍在同一文件内 |
| **App 图标 + LaunchScreen** | RICE #7，终端风格图标 | **未做** | 无 Asset Catalog 变更 |

**v4-beta 完成率：2/4（50%）**

### v4 额外完成的工作（非 v3 PM 计划内）

| 功能 | 说明 | 评价 |
|------|------|------|
| **外接键盘检测** | 通过 `keyboardWillShowNotification` 的 `keyboardFrameEndUserInfoKey` 判断键盘高度，< 100pt 视为外接键盘，自动隐藏快捷键栏 | 实用功能，解决了外接键盘用户屏幕空间浪费问题。但判断逻辑依赖 magic number（100pt），在某些 iPad 配件键盘上可能误判 |
| **上次 Session 自动连接** | 启动时从 UserDefaults 读取 `last_session_name`，如果在活跃 session 列表中则自动连接 | 极好的 UX 优化。日常使用只有一个 session 的用户（大多数场景）完全跳过 session picker，实现"打开即连接"的零步操作 |
| **InputAccessoryBar isHidden 参数** | 快捷键栏支持隐藏（配合外接键盘检测） | 接口设计合理 |

### v4 改进总结

| 类别 | 数量 | 明细 |
|------|------|------|
| v3 PM 计划完成 | 4 项 | 快捷键栏补全、scenePhase 重连、NWPathMonitor、Session 内切换 |
| v3 PM 计划未做 | 5 项 | fetchSessions 强制解包、动态字体、通知/语音验证、文件拆分、App 图标 |
| 额外完成 | 3 项 | 外接键盘检测、自动连接上次 Session、InputAccessoryBar isHidden |
| **总计划执行率** | **4/9（44%）** | alpha 2/5 + beta 2/4 |

---

## B. RICE Top 15 进展评估

基于 v2 评估的 RICE Top 15 + v3 新增项，追踪 v4 进展：

| 排名 | # | 功能 | RICE | 建议版本 | 当前状态 | 完成版本 |
|------|---|------|------|---------|---------|---------|
| 1 | 2 | isConnected 状态修正 | 40.0 | v3 | **已完成** | v3 |
| 2 | 3 | [session ended] 检测 | 40.0 | v3 | **已完成** | v3 |
| 3 | 16 | fetchSessions 强制解包修复 | 20.0 | v3 | **未修复（连续 2 版遗漏）** | -- |
| 4 | 5 | 快捷键栏补全（NL/方向键） | 30.0 | v4 | **已完成** | v4 |
| 5 | 11 | 动态字体自适应 | 16.0 | v3/v4 | **未做（连续 2 版未做）** | -- |
| 6 | 4 | 中文输入（IMETextField） | 12.0 | v3 | **已完成** | v3 |
| 7 | 14 | NWPathMonitor 网络感知 | 8.0 | v4 | **已完成** | v4 |
| 8 | NEW | scenePhase 前后台重连 | 16.0 | v4 | **已完成** | v4 |
| 9 | 10 | Session 内切换 | 7.0 | v4 | **已完成** | v4 |
| 10 | 25 | 任务状态一览卡片 | 4.8 | v4 | 未做 | -- |
| 11 | 18 | App 图标 & Launch Screen | 5.0 | v4 | 未做 | -- |
| 12 | 27 | 命令收藏/快捷面板 | 3.5 | v5 | 未做 | -- |
| 13 | 30 | 连接健康指示器 | 4.0 | v5 | 部分（NetworkMonitor "NO NET" 标签） | v4 部分 |
| 14 | 29 | Widget 桌面小组件 | 2.4 | v5 | 未做 | -- |
| 15 | 24 | 权限请求快速审批 | 3.0 | v6 | 未做 | -- |

**结论：截至 v4，Top 15 中已完成 7 项（含部分完成 1 项），未完成 8 项。v4 贡献了 4 项完整完成（#5/#14/scenePhase/#10），是产出最高的一个版本。**

**仍然未完成的高优先级项：**
- **fetchSessions 强制解包**（RICE 20.0）：连续 2 版遗漏，属于"一行代码能修但就是忘了"的典型遗漏
- **动态字体自适应**（RICE 16.0）：连续 2 版未做，iPhone SE/mini 用户体验受损

---

## C. 用户评分预测：7.5 -> 8.5

### 各维度分数预测

| 维度 | v3 评分 | v4 预估 | 变化 | 理由 |
|------|--------|--------|------|------|
| 首次启动体验 | 7 | 8.5 | +1.5 | 自动连接上次 Session 是杀手级改进——大多数用户每天只用一个 session，v4 实现了"打开即用" |
| 终端可读性 | 7 | 7 | -- | 动态字体仍未做，iPhone SE/mini 仍截断 |
| 打字体验 | 8 | 9 | +1 | NL 键终于补上了（绿色高亮首位），左右方向键也有了。15 键覆盖度超过 Web 端 |
| 滚动浏览 | 3 | 3 | -- | 无变化，仍未真机验证 |
| 复制粘贴 | 5 | 5 | -- | 无直接改进 |
| 网络稳定性 | 9 | 9.5 | +0.5 | NWPathMonitor + scenePhase 双重保障。WiFi/蜂窝切换、前后台切换都能主动重连。"NO NET" 标签清晰展示网络状态 |
| 语音功能 | 6 | 6 | -- | 无变化 |
| 通知 | 6 | 6 | -- | 无变化 |
| 与 Web 终端对比 | 6.5 | 8 | +1.5 | 快捷键栏反超 Web（15 键 vs 12 键），Session 内切换追平 Web，自动重连机制全面超越 Web。App 在日常操控维度已经领先 |
| 整体感受 | 7.5 | 8.5 | +1.0 | "打开即连接 + NL 键 + 网络自愈 + Session 切换"四件套组合，让 App 从"可以用"变成"更好用" |

**综合预测：8.5/10（v3 PM 预测 v4 完成后 7.5~8.0，实际表现超预期）**

### 超预期原因分析

v3 PM 预测 v4 达到 7.5~8.0，实际预估 8.5，超出的原因：

1. **自动连接上次 Session** 不在 v3 PM 计划内，但它是 v4 最有价值的 UX 改进。首次启动体验从 7 跳到 8.5，是单项提升最大的维度
2. **快捷键栏不仅补齐，而且超越 Web 端**。v3 PM 只要求"补 NL/方向键"，v4 实际做了 NL + Tab + ^C + Esc + 四向方向键 + ^A/^E/^R/^D/^Z/^L = 15 键，分三组用 Divider 分隔，布局比 Web 端更有组织
3. **外接键盘检测自动隐藏快捷栏** 是一个"没人想到但用上就回不去"的功能

### 未达预期的维度

- **动态字体**未做，v3 PM 预测"终端可读性 7.5 -> 8.5"未实现
- **App 图标/LaunchScreen** 未做，v3 PM 预测"首次启动体验 7 -> 7.5"的图标部分未实现（但被自动连接弥补了）
- **滚动浏览**依然是 3/10 的洼地，拖累总分

### 用户评语预测

> 终于！NL 键在第一个位置，绿色的，一眼就看到。打开 App 自动连上 session 不用选，这个体验太顺了。进地铁断了，出来 App 自己就重连了，不用手动操作。Session 切换也不用退出重进了。但是滚动还是没验证，横屏字体还是会截断。整体来说已经能替代 Web 终端日常使用了。

---

## D. 代码膨胀评估

### D1. TerminalView.swift 膨胀分析

| 版本 | 行数 | 变化 | 主要内容 |
|------|------|------|---------|
| v2 | ~290 行 | 基线 | SwiftTermView + Coordinator |
| v3 | ~800 行 | +176% | + TerminalContainerView + IMETextField + 连接状态 UI |
| v4 | **979 行** | +22% | + SessionSwitcherSheet + 外接键盘检测 + scenePhase + NetworkMonitor 接入 |

**v3 PM 明确建议"v4 应拆分 TerminalView"，但 v4 反而让它更大了。** TerminalView.swift 目前承担 7 种职责：

1. **TerminalView**（SwiftUI 主视图）：顶栏 + 终端 + 快捷栏 + Alert/Sheet 逻辑（~220 行）
2. **SwiftTermView**（UIViewRepresentable）：SwiftTerm 包装 + Coordinator（~160 行）
3. **TerminalContainerView**（UIView）：触摸路由 + 选择覆盖层（~200 行）
4. **IMETextField**（UITextField 子类）：diff-based 输入代理（~140 行）
5. **SessionSwitcherSheet**（SwiftUI 视图）：Session 切换半高弹窗（~65 行）
6. **外接键盘检测逻辑**：~20 行
7. **连接状态 UI 组件**：~30 行

**拆分建议（v5 必做）：**

| 目标文件 | 内容 | 预估行数 |
|---------|------|---------|
| `Views/TerminalView.swift` | 主视图 + 顶栏 + 状态逻辑 | ~250 行 |
| `Views/SwiftTermView.swift` | UIViewRepresentable + Coordinator | ~160 行 |
| `Views/TerminalContainerView.swift` | UIView + 触摸路由 + 选择覆盖层 | ~200 行 |
| `Views/IMETextField.swift` | diff-based 输入代理 | ~140 行 |
| `Views/SessionSwitcherSheet.swift` | Session 切换弹窗 | ~65 行 |

拆分后每个文件 <= 250 行，可维护性大幅改善。

### D2. InputAccessoryBar.swift 质量评价

从 99 行增长到 142 行（+43%），但代码质量**优秀**：

- `KeyAction` 枚举完整覆盖 15 种按键，每个都有对应的 `ansiSequence`
- NL 按钮独立提取为 `nlButton` 计算属性（绿色高亮样式）
- 通用按钮用 `keyButton(_:icon:action:)` 工厂方法，避免重复代码
- 三组按键用 Divider 分隔（常用操作 / 方向键 / 行编辑 Ctrl 组合），信息架构清晰
- `isHidden` 参数支持外接键盘场景

**这是 v4 代码质量最高的文件。**

### D3. NetworkMonitor.swift（新增文件）

100 行，职责单一：

- 使用 `NWPathMonitor` 监听网络路径变化
- 发布 `isConnected`（Bool）和 `connectionType`（WiFi/Cellular/Ethernet/Unknown）
- 通过 `onNetworkRestored` / `onNetworkLost` 回调通知外部
- 正确处理三种转换：网络恢复、网络丢失、路径类型切换（WiFi -> Cellular 也触发 reconnect）

**代码质量评价：结构清晰，API 设计合理，生命周期管理正确（init 启动、deinit 停止）。唯一的风险点是路径切换时每次都触发 `onNetworkRestored`，如果 WiFi 信号在边界处震荡，可能导致频繁重连。建议 v5 加 debounce。**

### D4. SessionPickerView.swift 变化

从 286 行增长到 307 行（+7%），新增自动连接逻辑。实现简洁：

- `hasAttemptedAutoConnect` 标记防止重复触发
- `autoConnectIfPossible()` 仅 5 行：读 UserDefaults -> 查找匹配 session -> 设置 `selectedSession`
- 版本号从 3.0 -> 4.0

### D5. 遗留问题汇总

| 问题 | 文件 | 严重度 | 版本遗留 | 说明 |
|------|------|--------|---------|------|
| `URL(string:)!` 强制解包 | WebSocketManager.swift:424 | **高** | v2 起 | fetchSessions 可因非法字符 crash。已连续 3 个版本未修。应升级为 P0 |
| TerminalView.swift 979 行 | TerminalView.swift | 中 | v3 起 | 持续膨胀，v3 PM 建议拆分但 v4 反而加了 SessionSwitcherSheet |
| 动态字体自适应缺失 | TerminalView.swift | 中 | v2 起 | 连续 3 个版本未做，iPhone SE/mini 截断 |
| 双输入路径 | TerminalView.swift | 低 | v3 起 | SwiftTerm delegate + IMETextField 并存。v4 未改变 |
| 外接键盘检测 magic number | TerminalView.swift:206 | 低 | v4 新增 | `frame.height < 100` 阈值可能在某些 iPad 配件键盘上误判 |
| NetworkMonitor 无 debounce | NetworkMonitor.swift | 低 | v4 新增 | 网络边界震荡可能导致频繁重连 |

### D6. 代码量变化追踪

| 文件 | v2 | v3 | v4 | v3->v4 变化 |
|------|-----|-----|-----|-----------|
| ClaudeTerminalApp.swift | 12 | 12 | 11 | -1 |
| Models/ServerConfig.swift | 79 | 79 | 78 | -1 |
| Models/SessionModel.swift | 23 | 23 | 22 | -1 |
| Audio/VoiceManager.swift | 205 | 205 | 204 | -1 |
| Network/WebSocketManager.swift | ~260 | 435 | 434 | -1 |
| Network/ClipboardBridge.swift | 51 | 51 | 50 | -1 |
| Network/NotificationManager.swift | 129 | 129 | 128 | -1 |
| **Network/NetworkMonitor.swift** | -- | -- | **100** | **+100（新增）** |
| Views/InputAccessoryBar.swift | 99 | 99 | **142** | **+43** |
| Views/SessionPickerView.swift | 286 | 286 | **307** | **+21** |
| Views/TerminalView.swift | ~290 | 800 | **979** | **+179** |
| Gestures/ScrollGestureHandler.swift | 235 | 235 | 234 | -1 |
| **合计** | ~1669 | ~2354 | **2689** | **+335（+14%）** |

**v4 代码总量 2689 行，较 v3 增长 14%。新增代码集中在 TerminalView（+179）和 NetworkMonitor（+100）。增速较 v3（+39%）有所收敛，但 TerminalView 的膨胀趋势未得到遏制。**

---

## E. v5 路线图："贴心工具"阶段

### E1. v5 主题定位

**v4 达成了"日常可用"的里程碑。v5 的目标是从"能用"变成"好用"——通过 Widget、收藏、性能优化和品牌化，让 App 融入用户的 iOS 工作流。**

v5 主题：**贴心工具 -- 让 App 成为 iOS 工作流的一部分**

### E2. RICE 重新排序

| 排名 | # | 功能 | R | I | C | E | RICE | 说明 |
|------|---|------|---|---|---|---|------|------|
| **1** | 16 | **fetchSessions 强制解包修复** | 10 | 1 | 1.0 | 0.1 | **100.0** | 连续 3 版遗漏的 P0 Bug。1 行代码修复。Effort 极低导致 RICE 极高 |
| **2** | NEW | **TerminalView 文件拆分** | 5 | 1 | 1.0 | 0.5 | **10.0** | 979 行已严重影响可维护性。v3 PM 建议后 v4 反而加重 |
| **3** | 11 | **动态字体自适应** | 8 | 2 | 1.0 | 1 | **16.0** | 连续 3 版未做。iPhone SE/mini/横屏用户的硬伤 |
| **4** | 29 | **Widget 桌面小组件** | 9 | 2 | 0.7 | 2 | **6.3** | v5 主题核心。Lock Screen Widget 显示 session 状态/最后活动时间，Home Screen Widget 一键跳入 session |
| **5** | 27 | **命令收藏/快捷面板** | 8 | 2 | 0.8 | 2 | **6.4** | 常用命令收藏 + 一键发送。重度用户的效率倍增器 |
| **6** | 18 | **App 图标 & Launch Screen** | 10 | 0.5 | 1.0 | 1 | **5.0** | 品牌化。当前使用默认白色图标，不专业 |
| **7** | NEW | **NetworkMonitor debounce** | 6 | 0.5 | 1.0 | 0.5 | **6.0** | 防止网络边界震荡导致频繁重连 |
| **8** | NEW | **性能优化：大输出渲染** | 7 | 1 | 0.6 | 2 | **2.1** | CC 输出大段代码时 SwiftTerm 渲染性能。需要 Instruments profiling |
| **9** | NEW | **通知内容增强** | 8 | 1 | 0.8 | 1.5 | **4.3** | 通知 body 显示 CC 最后一行输出摘要，而非固定文字 |
| **10** | NEW | **滚动真机验证 + 修复** | 8 | 1 | 0.5 | 1 | **4.0** | 3/10 的滚动评分是全场最低。必须真机验证并修复发现的 bug |

### E3. v5 路线图

#### v5-alpha（Week 1）-- 技术债清理

| 任务 | RICE 排名 | 预估 | 说明 |
|------|----------|------|------|
| fetchSessions 强制解包修复 | #1 | 0.1 天 | `guard let url = URL(string:) else { throw }` |
| TerminalView 文件拆分 | #2 | 0.5 天 | 拆为 5 个文件，每个 <= 250 行 |
| 动态字体自适应 | #3 | 1 天 | 连接后检测 `terminal.cols`，若 < 70 循环缩小 fontSize |
| NetworkMonitor debounce | #7 | 0.5 天 | 路径变化后 2 秒 debounce，防止震荡 |
| 滚动真机验证 | #10 | 1 天 | 真机测试 + 修复发现的 bug |

**v5-alpha 交付标准：零已知 crash + TerminalView <= 250 行 + 字体自适应 + 滚动可用**

#### v5-beta（Week 2）-- 贴心工具

| 任务 | RICE 排名 | 预估 | 说明 |
|------|----------|------|------|
| Widget 桌面小组件 | #4 | 2 天 | WidgetKit Target + Lock Screen Widget（session 状态）+ Home Widget（一键跳入）|
| 命令收藏/快捷面板 | #5 | 1.5 天 | 长按快捷栏按钮弹出收藏面板，支持添加/删除/排序常用命令 |
| App 图标 + LaunchScreen | #6 | 0.5 天 | 终端风格图标（黑底 > 绿色闪烁光标），LaunchScreen 匹配 |
| 通知内容增强 | #9 | 0.5 天 | 缓存最后 5 行输出，通知时附带最后一行摘要 |

**v5-beta 交付标准：Widget 可用 + 命令收藏 + 专业 App 图标**

### E4. v5 完成后的预期评分

| 维度 | v4 预估 | v5 预估 | 提升原因 |
|------|--------|--------|---------|
| 首次启动体验 | 8.5 | 9 | App 图标 + LaunchScreen 提升品牌感，Widget 一键跳入 |
| 终端可读性 | 7 | 8.5 | 动态字体自适应解决截断问题 |
| 打字体验 | 9 | 9 | v4 已达优秀水平 |
| 滚动浏览 | 3 | 7 | 真机验证 + 修复（保守估计，取决于发现多少 bug） |
| 复制粘贴 | 5 | 5.5 | 命令收藏减少重复输入，间接改善 |
| 网络稳定性 | 9.5 | 9.5 | v4 已接近天花板 |
| 语音功能 | 6 | 6 | v5 不涉及 |
| 通知 | 6 | 7 | 通知内容增强（最后一行摘要） |
| 与 Web 终端对比 | 8 | 9 | Widget + 命令收藏 + App 图标 = 原生体验全面领先 |
| 整体感受 | 8.5 | 9 | "iOS 工作流的一部分" |

**v5 完成后综合预测：8.5~9.0/10**

### E5. v6 方向预览

v6 主题：**智能助手**

- 权限请求快速审批（解析 CC 权限请求 -> 系统通知 -> 一键批准）
- 输出摘要（CC 回复过长时自动折叠 + 摘要）
- Siri / Shortcuts 集成（"Hey Siri, 检查 Claude 任务状态"）
- 语音排队播放 + 语速控制
- 多服务器支持（切换不同 Mac）

### E6. 版本里程碑甘特图

```
v5-alpha (Week 1): [fetchSessions fix] [文件拆分] [动态字体] [debounce] [滚动验证]
v5-beta  (Week 2): [Widget] [命令收藏] [App图标] [通知增强]
v6       (Month 2): [权限审批] [输出摘要] [Siri] [语音排队] [多服务器]
```

---

## F. 产品成熟度评估：能不能开始日常使用了？

### F1. 成熟度评估矩阵

| 评估维度 | v2 | v3 | v4 | 说明 |
|---------|-----|-----|-----|------|
| **基本功能完整性** | 60% | 75% | **90%** | v4 补齐了 NL 键、Session 切换、网络自愈——日常使用三大必需 |
| **稳定性/可信度** | 40% | 70% | **85%** | scenePhase + NWPathMonitor 双重重连保障。但 fetchSessions crash 风险仍在 |
| **效率（vs Web）** | 50% | 60% | **85%** | 快捷键栏反超 Web，自动连接跳过 Session picker，Session 内切换追平 Web |
| **可发现性** | 50% | 55% | **65%** | NL 键绿色高亮是正确的设计语言。但长按选择、滚动模式仍缺可视引导 |
| **品牌/专业感** | 30% | 30% | **35%** | 仍无 App 图标、无 LaunchScreen，看起来像个开发中的 Demo |
| **iOS 工作流融合** | 10% | 10% | **20%** | 自动连接上次 Session 是第一步。但无 Widget、无 Shortcuts、无 Siri |

### F2. 日常使用可行性判断

**结论：v4 已经达到日常使用门槛。**

理由：

1. **"打开即连接"的零步操作** 消除了最大的使用摩擦。v3 需要"打开 App -> 等加载 session 列表 -> 点击 session -> 等连接"4 步，v4 缩短为"打开 App -> 自动连接"1 步（实际是零步——打开即到位）

2. **NL 键 + 完整快捷栏** 覆盖了日常操控 CC 的 99% 场景。以前没有 NL 键，每次发多行指令都要折腾，现在首位绿色 NL 键一按即发

3. **网络全自愈** 解决了通勤场景的核心痛点。WiFi -> 蜂窝切换、App 前后台切换，全部自动重连，不需要用户干预

4. **Session 内切换** 解决了多 session 用户（约 20% 场景）的操作中断

### F3. 日常使用的已知风险

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| fetchSessions crash | 低（需要特殊字符的服务器地址） | 高（App 崩溃） | 手动确保 IP 地址格式正确 |
| 滚动不可用 | 中（未经真机验证） | 中（无法回看 CC 长回复） | 用 Web 终端回看 |
| 横屏字体截断 | 中（iPhone 横屏必现） | 低（多数人竖屏使用） | 切回竖屏 |
| 外接键盘误判 | 低（特定 iPad 配件） | 低（快捷栏消失） | 重启 App |

### F4. 推荐使用场景

| 场景 | 推荐度 | 说明 |
|------|--------|------|
| 通勤地铁上操控 CC | **强烈推荐** | 网络自愈 + NL 键 + 自动连接 = 完美通勤工具 |
| 会议间隙快速查看 | **强烈推荐** | 自动连接上次 session，3 秒看到状态 |
| 长时间竖屏工作 | **推荐** | 快捷栏完整，中文输入可靠 |
| 横屏深度工作 | **暂不推荐** | 字体截断 + 快捷栏占空间，等 v5 动态字体 |
| 需要频繁回看历史 | **暂不推荐** | 滚动未验证，建议用 Web 终端 |
| iPad + 外接键盘 | **可以尝试** | keyCommands 支持完善，但 UI 布局未对 iPad 优化 |

### F5. 与 v3 PM 预测对比

| 维度 | v3 PM 预测 v4 分数 | 实际 v4 预估 | 差异原因 |
|------|-------------------|-------------|---------|
| 首次启动 | 7.5 | **8.5** | 自动连接超预期 |
| 终端可读性 | 8.5 | **7** | 动态字体未做 |
| 打字体验 | 9 | **9** | 符合预期 |
| 滚动浏览 | 6 | **3** | 仍未真机验证 |
| 网络稳定性 | 9 | **9.5** | 超预期（双重保障） |
| 与 Web 对比 | 7.5 | **8** | 超预期（快捷栏反超） |
| 整体 | 8 | **8.5** | 总体超预期 |

**v3 PM 预测 v4 达到 7.5~8.0，实际 v4 预估 8.5。超出的部分主要来自"自动连接上次 Session"这个计划外功能的出色表现，以及快捷键栏从"补齐"到"超越 Web"的超额交付。未达预期的部分集中在动态字体和滚动两个连续延期的老问题上。**

---

## 附录：v4 代码文件清单

| 文件 | v3 行数 | v4 行数 | 变化 |
|------|---------|---------|------|
| `ClaudeTerminalApp.swift` | 12 | 11 | 无实质变化 |
| `Models/ServerConfig.swift` | 79 | 78 | 无实质变化 |
| `Models/SessionModel.swift` | 23 | 22 | 无实质变化 |
| `Audio/VoiceManager.swift` | 205 | 204 | 无实质变化 |
| `Network/WebSocketManager.swift` | 435 | 434 | 无实质变化 |
| `Network/ClipboardBridge.swift` | 51 | 50 | 无实质变化 |
| `Network/NotificationManager.swift` | 129 | 128 | 无实质变化 |
| **`Network/NetworkMonitor.swift`** | -- | **100** | **v4 新增（NWPathMonitor 网络感知）** |
| **`Views/InputAccessoryBar.swift`** | 99 | **142** | **v4 重构（15 键完整快捷栏）** |
| **`Views/SessionPickerView.swift`** | 286 | **307** | **v4 新增自动连接逻辑** |
| **`Views/TerminalView.swift`** | 800 | **979** | **v4 新增 Session 切换 + scenePhase + 网络监控 + 外接键盘检测** |
| `Gestures/ScrollGestureHandler.swift` | 235 | 234 | 无实质变化 |
| **合计** | **2354** | **2689** | **+335（+14%）** |

---

## 关键结论

1. **v4 是产出最高的版本**：4 项 RICE 高排名功能完成（快捷栏补全 / NWPathMonitor / scenePhase 重连 / Session 内切换），3 项计划外的优秀 UX 改进
2. **fetchSessions 强制解包已是 P0**：连续 3 版遗漏，v5 第一天必须修复
3. **TerminalView 膨胀是最大的技术债**：979 行、7 种职责，v5 必须拆分
4. **App 已达日常使用门槛**：通勤、会议间隙、竖屏操控场景均可替代 Web 终端
5. **v5 应转向"贴心工具"**：技术债清理 + Widget + 命令收藏 + App 图标，目标 9.0/10
