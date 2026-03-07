# 移动端输入系统 PM 评估报告 v1

**日期**: 2026-03-07
**评估人**: 产品经理（输入体验方向）
**评估对象**: `public/index.html` 移动端输入系统
**参考文档**: `docs/mobile-input-redesign.md`（技术研究）、`docs/mobile-ux-test-report.md`（测试报告）

---

## A. 输入系统现状审计

### A.1 支持的输入方式

| 输入方式 | 支持状态 | 实现机制 | 备注 |
|----------|----------|----------|------|
| 英文直接键入 | 支持 | keydown → `KEY_MAP` / input → `sentBuffer` diff | 逐字即发，有 autocomplete race condition |
| 中文拼音 IME | 支持 | compositionstart/end → `wsSend(全量text)` → resetSentState | compositionend 后可能重复发送（P4） |
| 英文联想词/autocomplete | 部分支持 | input 事件中 `sentBuffer` diff → 退格 + 发新文本 | 800ms resetTimer 可导致 diff 错误（P1/P2） |
| 粘贴 | 支持（服务端） | quick-bar "Paste" 按钮 → `fetch('/api/clipboard')` → wsSend | 非标准粘贴流，依赖 Mac 剪贴板 API |
| 语音输入转文字 | 未明确支持 | iOS 听写走 composition 或直接 input，理论上通过 diff 处理 | 未测试，长文本可能超出 sentBuffer 追踪能力 |
| 物理蓝牙键盘 | 基本支持 | keydown → KEY_MAP 处理特殊键 | 未做专门优化（如 Cmd 组合键） |
| 图片上传 | 支持 | quick-bar 📷按钮 → `fetch('/api/upload')` | 路径自动输入终端 |

### A.2 支持的特殊键

| 键 | 来源 | 实现 |
|----|------|------|
| Enter (\\r) | keydown KEY_MAP / quick-bar NL 按钮 | 软键盘 Enter 被 **阻断**，必须按 NL 按钮 |
| Tab (\\t) | keydown KEY_MAP / quick-bar Tab 按钮 | 正常 |
| Shift+Tab | quick-bar ⇧Tab 按钮 | 发送 `\x1b[Z` |
| 方向键 ← → ↑ ↓ | keydown KEY_MAP / quick-bar 按钮 | 正常 |
| Backspace (\\x7f) | keydown / beforeinput deleteContentBackward | 手动拦截 + slice sentBuffer（有整词删除 bug） |
| Delete (fwd) | keydown / beforeinput deleteContentForward | 发送 `\x1b[3~` |
| Esc | keydown KEY_MAP / quick-bar Esc 按钮 | 正常 |
| Ctrl+C | quick-bar ^C 按钮 | 发送 `\x03` |
| / | quick-bar / 按钮 | 直接 wsSend('/') |

**缺失的键**: Ctrl+D、Ctrl+Z、Ctrl+A、Ctrl+L、Ctrl+R、F1-F12、Home/End、PgUp/PgDn。

### A.3 已知 Workaround 和 Hack 清单

| # | Hack | 代码位置 | 目的 |
|---|------|----------|------|
| H1 | `disableStdin: true` + 独立 textarea | connect() L836 | xterm.js 原生移动输入不可靠，用外部 textarea 接管 |
| H2 | `sentBuffer` diff 模型 | L1154-1280 | 追踪已发送字符以处理 autocomplete 替换 |
| H3 | `scheduleReset()` 800ms 清空 | L1166-1172 | 防止 textarea.value 无限增长 |
| H4 | `_emptyKeyTs` 100ms 窗口 | L1310-1311 | 抑制 iOS Enter 后的虚假 Backspace |
| H5 | `justFinishedComposition` + rAF | L1182-1188 | 抑制 compositionend 后的重复 input 事件 |
| H6 | `_isWhitespaceKey` 检测 | L1293 | 识别 iOS 中文 IME 的 `key="\n\r"` Enter |
| H7 | `keydownHandled` 标志 | L1143,1239,1302 | 防止 keydown 和 input 双重处理 |
| H8 | beforeinput 阻断 insertParagraph | L1225-1232 | 禁止软键盘 Enter，强制用 NL 按钮 |
| H9 | `autocomplete="off" autocorrect="off"` | L305 | 尝试禁用 predictive text（iOS 上无效） |
| H10 | 透明 textarea → `.input-visible` 切换 | CSS L110-142 | 键盘关闭时隐藏输入框但保持可聚焦 |
| H11 | `mousedown preventDefault` 在 quick-bar | buildQuickBar() | 点击按钮时不触发 textarea blur |
| H12 | `enterkeyhint="send"` | L306 | 改变软键盘 Enter 键的视觉提示 |

### A.4 代码复杂度评估

| 模块 | 行数（约） | Edge Case 处理数 |
|------|-----------|-----------------|
| 输入事件处理（keydown/beforeinput/input/composition） | ~150 行（L1119-1280） | 8 个独立 edge case |
| 触摸手势（scroll/long-press/select） | ~115 行（L864-1055） | 6 个状态分支 |
| 键盘/视口调整 | ~50 行（L671-722） | 3 个布局分支 |
| Quick-bar 构建 | ~110 行（L560-669） | - |
| **输入相关总计** | **~425 行** | **17 个 edge case** |

**整体评估**: 输入系统是 `index.html` 1373 行中最复杂的部分（约 31%），12 个 hack/workaround 层层叠加，相互依赖。技术债务中等偏高。

---

## B. 竞品输入体验对比

### B.1 竞品特性矩阵

| 特性 | 本项目 | Termius iOS | Blink Shell | a-Shell | WebSSH | VS Code Mobile |
|------|--------|-------------|-------------|---------|--------|----------------|
| **架构** | Web (xterm.js + textarea) | 原生 UIKit | 原生 (hterm) | 原生 (hterm) | 原生 | Web (Monaco) |
| **特殊键栏** | 固定 10+5 个按钮 | 可自定义分组，可拖拽排序 | SmartKeys（软键盘时显示，外接键盘时隐藏） | Tab/Ctrl/Esc/方向键 | 可自定义布局 | 有限 |
| **Ctrl/Alt/Cmd 组合** | 仅 ^C 按钮 | 完整支持（Ctrl/Alt/Cmd 修饰键长按） | 完整（CTRL/ALT/ESC 修饰键） | Ctrl 键 | 完整 | 部分 |
| **F1-F12** | 不支持 | 支持（扩展键盘） | 支持（CMD 组合） | 不支持 | 支持 | 不支持 |
| **手势输入** | 滑动=tmux scroll | 长按空格+滑动=方向键（三档速度） | 两指滑动=scroll | 基本 | 基本 | 无 |
| **IME/CJK** | 有 bug（P1-P4） | 原生 iOS 输入，无额外问题 | 专门 IME mode，cursor 适配 | 原生 | v29.8 修复 CJK 问题 | 基本 |
| **Predictive Text** | 无法禁用（iOS 忽略属性） | 原生输入框，用户可在 iOS 设置禁用 | 原生控制 | 原生控制 | 原生控制 | 无法禁用 |
| **外接键盘** | 基本（无快捷键） | 完整（含自定义映射） | 完整（拥抱蓝牙键盘） | 支持 | 支持 | 部分 |
| **AI 集成** | 无（但面向 Claude Code） | AI 助手，键盘上方 AI 面板 | 集成 VS Code | 无 | 无 | Copilot |
| **命令历史** | 不支持 | 支持（snippets 功能） | 支持 | 支持 | 支持 | 支持 |
| **粘贴** | 服务端 Mac 剪贴板 | 原生剪贴板 | 原生剪贴板 | 原生剪贴板 | 原生剪贴板 | 原生 |
| **价格** | 免费（自建） | 免费+订阅 | 付费 | 免费 | 免费+付费 | 免费 |

### B.2 竞品关键启发

**Termius** — 最值得学习的竞品:
- 长按空格 + 滑动 = 方向键的手势设计极为优雅，三档速度自适应
- 可自定义键组 + 拖拽排序的 extra key 设计满足专业用户需求
- AI 面板置于键盘上方，与我们的 quick-bar 位置一致，可借鉴其交互模式

**Blink Shell** — 原生方案的上限:
- 原生 app 在 IME 处理上天然无 Web 的 composition 事件链问题
- SmartKeys 根据软/硬键盘自动切换的设计值得模仿
- 修饰键（Ctrl/Alt）的长按锁定机制在 Web 上可用 quick-bar 状态按钮模拟

**WebSSH** — 同类 Web 方案的参考:
- v29.8 专门修复 CJK 输入问题说明这是普遍痛点
- "Toggle Keyboard" 功能解决了键盘可见性管理

**VS Code Mobile / Codespaces** — 反面教材:
- 移动端体验很差，GitHub 官方承认没有具体计划支持 iPad
- 证明 Web 终端在移动端的输入问题是行业性难题，不是我们做得不好

### B.3 本项目 vs 竞品的差距定位

```
输入可靠性:  本项目 [====------] 40%    竞品平均 [========--] 80%
特殊键覆盖:  本项目 [===-------] 30%    竞品平均 [=======---] 70%
手势交互:    本项目 [======----] 60%    竞品平均 [=======---] 70%
自定义能力:  本项目 [==========] 0%     竞品平均 [======----] 60%
IME 兼容性:  本项目 [====------] 40%    竞品平均 [========--] 80%
```

**核心差距**: 输入可靠性（autocomplete race condition）和特殊键覆盖（缺 Ctrl 组合键）是两大短板。手势交互（tmux scroll + long-press select）已有不错基础。

---

## C. RICE 优先级评估

评分标准:
- **R (Reach)**: 影响用户比例（1-10）
- **I (Impact)**: 对体验的改善程度（0.25 / 0.5 / 1 / 2 / 3）
- **C (Confidence)**: 实施成功的把握（10%-100%）
- **E (Effort)**: 工程投入（人周，越大越不优先）

### C.1 评估表

| # | 改进项 | R | I | C | E（人周） | RICE 分数 | 优先级 |
|---|--------|---|---|---|-----------|-----------|--------|
| 1 | **统一 debounce 缓冲（消除英文联想问题）** | 9 | 3 | 80% | 1.5 | **14.4** | **P0** |
| 2 | **关闭 autocorrect/autocapitalize** | 8 | 1 | 40% | 0.2 | **16.0** | **P0** |
| 3 | **输入预览（输入框实时显示将发送内容）** | 6 | 0.5 | 90% | 0.3 | **9.0** | P2 |
| 4 | **命令历史（↑浏览历史）** | 7 | 2 | 70% | 2 | **4.9** | P2 |
| 5 | **智能补全（常用命令建议）** | 5 | 2 | 50% | 4 | **1.25** | P3 |
| 6 | **多行输入模式** | 4 | 1 | 60% | 2 | **1.2** | P3 |
| 7 | **语音转文字输入** | 3 | 0.5 | 70% | 1 | **1.05** | P3 |
| 8 | **外接键盘支持优化** | 6 | 2 | 80% | 1 | **9.6** | **P1** |
| 9 | **输入撤销（Cmd+Z）** | 3 | 0.5 | 50% | 1.5 | **0.5** | P4 |
| 10 | **剪贴板历史** | 2 | 0.5 | 60% | 3 | **0.2** | P4 |
| 11 | **Ctrl/Alt 修饰键按钮** (新增) | 8 | 2 | 90% | 0.5 | **28.8** | **P0** |
| 12 | **事件监听器泄漏修复** (已知 bug) | 10 | 1 | 95% | 0.3 | **31.7** | **P0** |

### C.2 评分详解

#### #1 统一 debounce 缓冲 — RICE 14.4 (P0)

- **Reach 9**: 所有使用英文键盘的用户（几乎所有人，包括输入命令）
- **Impact 3 (Massive)**: 解决 P1-P4 四个已知 critical/high bug，是输入系统最核心的可靠性改进
- **Confidence 80%**: `docs/mobile-input-redesign.md` 已有详细设计（InputController + 状态机 + 30ms 缓冲），方案成熟
- **Effort 1.5 周**: 需重写 ~150 行输入事件处理代码，替换 ~120 行旧代码。需 iOS 真机测试

#### #2 关闭 autocorrect/autocapitalize — RICE 16.0 (P0)

- **Reach 8**: 所有使用软键盘的移动端用户
- **Impact 1 (Low)**: 减少干扰但不能完全解决问题（iOS 仍然会显示 predictive text bar）
- **Confidence 40%**: `autocorrect="off"` 在 iOS Safari 上效果不确定。`inputmode="none"` 会禁用整个键盘。可能需要 `<input type="password">` 作为可选模式，但有无障碍问题
- **Effort 0.2 周**: 代码改动极小（已有属性，验证效果即可），但因 iOS 限制可能无效
- **注**: 分数虽高但 Confidence 低，实际价值取决于真机验证结果。建议与 #1 同期做

#### #8 外接键盘支持优化 — RICE 9.6 (P1)

- **Reach 6**: iPad 用户 + 蓝牙键盘用户（约 30-40% 场景）
- **Impact 2 (High)**: 外接键盘是终端重度用户的常见场景，Cmd+C/V/Z/A 等组合键是基本预期
- **Confidence 80%**: keydown 事件中检测 `e.metaKey`/`e.ctrlKey` 并映射到终端序列，技术简单
- **Effort 1 周**: 需建立完整的快捷键映射表 + 测试各种键盘

#### #11 Ctrl/Alt 修饰键按钮 — RICE 28.8 (P0)

- **Reach 8**: 所有终端用户（Ctrl+D 退出、Ctrl+Z 挂起、Ctrl+A tmux prefix 是基本操作）
- **Impact 2 (High)**: 当前只有 ^C，缺少 Ctrl+D/Z/A/L/R 严重限制终端使用场景
- **Confidence 90%**: 在 quick-bar 添加 Ctrl 状态按钮，点击后下一个按键前加 Ctrl 前缀，技术简单
- **Effort 0.5 周**: 需处理 Ctrl 锁定/一次性触发的 UX 设计

#### #12 事件监听器泄漏修复 — RICE 31.7 (P0)

- **Reach 10**: 所有用户（切换 session 就会触发）
- **Impact 1 (Low)**: 导致重复 scroll 命令、重复 long-press 计时器、性能下降
- **Confidence 95%**: 测试报告已明确指出位置和修复方案（AbortController）
- **Effort 0.3 周**: 小改动，高确定性

---

## D. 测试策略建议

### D.1 必须自动化测试的场景

| 场景 | 自动化可行性 | 工具 | 理由 |
|------|-------------|------|------|
| 事件监听器泄漏检测 | 高 | Playwright | 多次 connect/disconnect 后检查 handler 计数 |
| keydown → wsSend 映射正确性 | 高 | Playwright | 模拟按键，验证 WebSocket 收到正确的转义序列 |
| beforeinput 阻断 Enter | 高 | Playwright | 触发 insertParagraph 事件，验证未发送 \\r |
| 布局三态切换（键盘开/关/select） | 中 | Playwright | 通过 dispatchEvent 模拟 visualViewport resize |
| sentBuffer diff 正确性 | 高 | 单元测试 | 将 diff 逻辑提取为纯函数，用 Jest/Vitest 测试各种替换场景 |
| Quick-bar 按钮功能 | 高 | Playwright | 点击每个按钮，验证 wsSend 调用 |
| 重连后状态一致性 | 中 | Playwright | 断开/重连后验证 sentBuffer/isComposing 等状态正确重置 |

### D.2 只能真机测试的场景

| 场景 | 原因 | 最低覆盖 |
|------|------|----------|
| iOS predictive text / autocomplete 替换 | Playwright 无法模拟 iOS 原生联想词点击 | iPhone 15 + iOS 18 |
| 中文拼音输入法全流程 | composition 事件链因输入法而异 | iOS 原生拼音 + 搜狗输入法 |
| 软键盘弹出/收起与布局联动 | visualViewport 行为因设备而异 | iPhone SE (小屏) + iPhone 15 Pro Max (大屏) |
| 长按文本选择 + 复制 | navigator.clipboard 需要 secure context + 真实手势 | 真机 Safari |
| 蓝牙键盘组合键 | USB/BT 键盘事件与软键盘完全不同 | Magic Keyboard + 第三方蓝牙键盘 |
| 语音听写输入 | iOS 听写的 composition 行为独特 | iPhone + 启用听写 |
| 滑动 scroll 手感（momentum） | 只有真机能感受 60fps 惯性滚动 | 真机手动测试 |

### D.3 推荐测试矩阵

| 维度 | 必测 | 可选 |
|------|------|------|
| **设备** | iPhone SE 3 (小屏 4.7") / iPhone 15 (标准 6.1") | iPhone 15 Pro Max (大屏) / iPad Air |
| **iOS 版本** | iOS 17 / iOS 18 | iOS 16（最低兼容线） |
| **输入法** | iOS 原生英文 / iOS 原生中文拼音 | 搜狗输入法 / Google Gboard |
| **语言** | 英文 / 中文 | 日文（compostion 行为差异大） |
| **键盘** | 软键盘 / Apple Magic Keyboard | 第三方蓝牙键盘 |
| **浏览器** | Safari (主要) | Chrome iOS (用户可能使用) |

**最小测试集**: iPhone 15 + iOS 18 + Safari + 原生英文/中文 = 1 台设备覆盖 70% 场景。

### D.4 CI 集成可行性

| 方案 | 可行性 | 成本 | 覆盖度 |
|------|--------|------|--------|
| **Playwright Chromium 模拟** | 高 | 免费 | 40%（无法模拟真实 iOS 输入行为） |
| **Playwright WebKit 模拟** | 中 | 免费 | 50%（WebKit 引擎但非真实 Safari） |
| **纯函数单元测试** | 高 | 免费 | 20%（仅覆盖 diff 逻辑） |
| **BrowserStack / Sauce Labs 真机** | 中 | $29-199/月 | 75%（真实 iOS Safari 但远程操作延迟高） |
| **本地真机 + Appium** | 低 | 设备成本 | 85%（配置复杂，维护成本高） |

**推荐策略**: Playwright Chromium 自动化 (CI) + 每次发版前手动真机测试 (iPhone 15)。将 diff 逻辑提取为纯函数单独做单元测试。

---

## E. 三版迭代路线图

### v1 — 基础修复与必备功能（1-2 周）

**主题**: 修复已知 bug，补齐最基本的终端操作能力

| 改进项 | RICE | 工作量 | 说明 |
|--------|------|--------|------|
| #12 事件监听器泄漏修复 | 31.7 | 0.3 周 | `AbortController` 或 guard boolean，修复 session 切换后的 handler 累积 |
| #11 Ctrl/Alt 修饰键按钮 | 28.8 | 0.5 周 | quick-bar 添加 Ctrl 状态按钮。点击 Ctrl → 下一个字符前加 `\x01`~`\x1a` 前缀。覆盖 Ctrl+D/Z/A/L/R/K 等常用操作 |
| #2 autocorrect/autocapitalize 验证 | 16.0 | 0.2 周 | 真机验证现有属性效果；若无效，添加可选 `type="password"` 模式开关 |
| #1 统一 debounce 缓冲（Phase 1） | 14.4 | 1 周 | 先做最小修复：去掉 800ms resetTimer → 仅在 Enter/特殊键后 reset；compositionend 延迟 50ms 走 diff 发送。不重写整体架构 |

**v1 目标**: 输入不再出错（修复 P1-P4），终端基本操作不再受限（Ctrl 组合键）。

**v1 验收标准**:
- 在 iPhone 15 + iOS 18 上连续输入英文句子 + 点击联想词，终端显示正确
- 中文拼音输入"你好世界"无重复字符
- Ctrl+D 可退出 python/node REPL
- 切换 session 3 次后滑动速度正常（无 handler 累积）

---

### v2 — 架构升级与体验提升（2-3 周）

**主题**: 用状态机重写输入核心，补齐外接键盘支持

| 改进项 | RICE | 工作量 | 说明 |
|--------|------|--------|------|
| #1 统一 debounce 缓冲（Phase 2 完整版） | 14.4 | 1.5 周 | 实现 `InputController` 状态机（IDLE/COMPOSING/BUFFERING/FLUSHING）+ snapshot diff + 30ms 统一缓冲。替换全部旧输入逻辑 |
| #8 外接键盘支持优化 | 9.6 | 1 周 | 检测 `e.metaKey`/`e.ctrlKey`，映射 Cmd+C→复制 / Cmd+V→粘贴 / Cmd+K→清屏等；SmartKeys 自动隐藏（检测无 visualViewport 变化 = 外接键盘） |
| #3 输入预览 | 9.0 | 0.3 周 | 随 `.input-visible` 改进——实时显示 textarea.value 而非隐藏，用户可见即将发送的内容 |
| Backspace 走 diff 路径 | — | 包含在 #1 中 | 不再手动 `slice(0,-1)`，让浏览器修改 textarea.value 后 diff 检测实际删除量 |

**v2 目标**: 输入架构从"hack 堆叠"升级为"状态机驱动"，代码可维护性大幅提升。外接键盘用户获得桌面级体验。

**v2 验收标准**:
- 删除全部 12 个 hack（H1-H12），用统一的 InputController 替代
- Magic Keyboard 上 Cmd+C/V/K/Z 正常工作
- 连接外接键盘后 quick-bar 自动隐藏
- 输入框可见时显示正在输入的内容

---

### v3 — 高级功能与专业化（3-4 周）

**主题**: 接近原生终端 App 的专业体验

| 改进项 | RICE | 工作量 | 说明 |
|--------|------|--------|------|
| #4 命令历史 | 4.9 | 2 周 | 在 quick-bar 添加 ↑↓ 历史浏览。本地 localStorage 存储最近 100 条命令。长按 ↑ 显示历史列表。需 hook 检测命令边界（检测 `\r` 后 reset） |
| #5 智能补全 | 1.25 | 3 周 | 基于本地历史 + 常用命令词典做前缀匹配。在输入框上方显示建议气泡。可选连接 Claude API 做智能建议 |
| #7 语音转文字 | 1.05 | 1 周 | 利用 iOS 原生听写（已通过 textarea 支持）。优化：听写结束后自动 flush 缓冲 |
| #6 多行输入模式 | 1.2 | 2 周 | 长按 NL 按钮切换多行模式。展开 textarea 为 3-5 行高度，Enter 换行而非发送，专门的"发送"按钮。适合编写 Claude Code 多行 prompt |
| 手势优化（Termius 式） | — | 2 周 | 长按空格 + 滑动 = 方向键。双指缩放 = 字体大小调节。已有的 momentum scroll 可进一步调优 |
| Quick-bar 可自定义 | — | 1.5 周 | 用户可添加/删除/排序按钮。设置面板或长按编辑模式。配置存 localStorage |

**v3 目标**: 输入体验从"能用"提升到"好用"，接近 Termius / Blink Shell 的专业水准。

---

### 路线图总览

```
                    v1 (1-2 wk)          v2 (2-3 wk)           v3 (3-4 wk)
                 ┌──────────────┐   ┌──────────────────┐   ┌──────────────────┐
可靠性           │ Bug 修复      │   │ 状态机重写        │   │                  │
                 │ P1-P4 修复    │──▶│ InputController  │   │                  │
                 │ 监听器泄漏    │   │ snapshot diff    │   │                  │
                 └──────────────┘   └──────────────────┘   │                  │
                 ┌──────────────┐   ┌──────────────────┐   │                  │
功能             │ Ctrl 修饰键   │   │ 外接键盘优化      │   │ 命令历史          │
                 │ autocorrect  │──▶│ 输入预览          │──▶│ 智能补全          │
                 │              │   │                  │   │ 多行输入          │
                 └──────────────┘   └──────────────────┘   │ 语音输入          │
                                                           │ 手势优化          │
                                                           │ Quick-bar 自定义  │
                                                           └──────────────────┘
 用户体验        [==--------]       [======----]            [==========]
 目标           "不出错"            "好维护+外接键盘"       "接近原生 App"
```

---

## 附录: 竞品信息来源

- [Termius - New Touch Terminal on iOS](https://termius.com/blog/new-touch-terminal-on-ios)
- [Termius - iOS/iPadOS Changelog](https://termius.com/changelog/ios-changelog)
- [Termius - Mobile Keyboard Customization](https://support.termius.com/hc/en-us/articles/4403035505689-Can-the-mobile-Termius-keyboard-be-customized)
- [Termius - Extended Keyboard Documentation](https://github.com/smanask/Termius-Documentation/blob/master/ios/features/extended_keyboard.md)
- [Blink Shell Documentation](https://docs.blink.sh/)
- [Blink Shell GitHub](https://github.com/blinksh/blink)
- [Blink Shell Changelog](https://github.com/blinksh/blink/blob/main/CHANGELOG.md)
- [a-Shell GitHub](https://github.com/holzschu/a-shell)
- [a-Shell App Store](https://apps.apple.com/us/app/a-shell/id1473805438)
- [WebSSH Documentation](https://webssh.net/)
- [WebSSH - Keyboard Accessory Customisation](https://webssh.net/documentation/help/howtos/SSH/customise-keyboard-accessory-view-layout/)
- [VS Code Codespaces Mobile Discussion](https://github.com/orgs/community/discussions/162416)
- [xterm.js - Accommodate predictive keyboard (#2403)](https://github.com/xtermjs/xterm.js/issues/2403)
- [xterm.js - Erratic text on Chrome Android (#3600)](https://github.com/xtermjs/xterm.js/issues/3600)
- [xterm.js - Mobile platform support (#1101)](https://github.com/xtermjs/xterm.js/issues/1101)
