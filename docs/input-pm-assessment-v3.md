# 移动端输入系统 PM 评估报告 v3（终版）

**日期**: 2026-03-07
**评估人**: 产品经理（输入体验方向）
**评估对象**: `public/index.html` v3 最终代码（InputController 状态机 + 150ms debounce + Ctrl 按钮）
**参考文档**: `docs/input-pm-assessment-v1.md`（v1 评估）、`docs/input-pm-assessment-v2.md`（v2 评估）、`tests/test-input-system.mjs`（47 项自动化测试）

---

## A. v2 PM 建议的 5 项 v3 改进验证

v2 评估为 v3 规划了 5 项改进（RICE Top 5），以下逐项验证：

### #12b Document 级 touch/selection 监听器泄漏修复（v2 RICE: 31.7, P0）

**状态: 未修复**

`connect()` 中 `if (isMobile)` 块内注册的 4 个 document 级监听器仍然没有清理机制：

| 监听器 | 行号 | 选项 | 清理机制 |
|--------|------|------|----------|
| `touchstart` | L971 | `{ passive: true, capture: true }` | 无 |
| `touchmove` | L999 | `{ passive: true, capture: true }` | 无 |
| `touchend` | L1031 | `{ capture: true }` | 无 |
| `selectionchange` | L1076 | 无 | 无 |

`cleanupConnection()` 调用 `inputController.destroy()` 清理了 InputController 的 textarea 事件（通过 AbortController），但这 4 个 document 级监听器不在 InputController 管辖范围内。每次调用 `connect()` 都会累积新的 handler。

**影响**: 切换 session 5 次后，document 上会有 20 个 touch handler + 5 个 selectionchange handler。导致：
- 滑动滚动发送 5 倍的 scroll 命令
- long-press 触发 5 个平行计时器
- 性能逐步下降

**修复难度**: 0.3 周。将 4 个 listener 注册挪到 AbortController 管辖下（在 `connect()` 中创建一个 `_touchAC`，`cleanupConnection()` 中 abort），或改为 guard 变量只注册一次。

---

### #17 Soft Backspace 延迟感修复（v2 RICE: 18.7, P0）

**状态: 未修复**

软键盘 Backspace 仍走 diff 路径，需等待 150ms BUFFER_MS 才能生效。代码路径：

1. 用户按软键盘 Backspace → 浏览器修改 `textarea.value`
2. `_onInput()` 触发 → `_startBuffer()` 设置 150ms 定时器
3. 150ms 后 `_flush()` → `_computeDiff()` 检测到删除 → 发送 `\x7f`

物理键盘 Backspace 不受影响（`_onKeydown` 直接发送 + 更新 snapshot），但软键盘用户（即所有手机用户）每次删除都有 150ms 延迟。连续按 Backspace 删除多个字符时，延迟会叠加为可感知的滞后。

**影响**: 用户对删除操作的延迟容忍度远低于输入。150ms 在快速连续删除时产生明显的"粘滞感"。

**修复方案**: 在 `_onInput()` 中检测 `e.inputType === 'deleteContentBackward'`，立即 flush（不等 150ms）。或对 Backspace 类 inputType 将 BUFFER_MS 缩短为 0-16ms。

---

### #13 BUFFER_MS 动态调优 / 真机验证（v2 RICE: 14.0, P1）

**状态: 未调优**

当前 BUFFER_MS = 150ms（固定值）。v2 评估认为是 80ms（可能基于设计文档而非实际代码），实际实现为 150ms。

| 参数 | 研究报告建议 | v2 评估认知 | 实际代码 |
|------|-------------|------------|----------|
| BUFFER_MS | 30ms | 80ms | **150ms** |

150ms 比研究报告建议的 30ms 高出 5 倍。这意味着：
- 每个字符从键入到出现在终端有 150ms 延迟
- 快速打字时延迟可能导致用户感知输入"反应慢"
- 但 150ms 大幅降低了 autocomplete 替换导致的 race condition 风险

**需要真机验证**: 在 iPhone 15 + iOS 18 上对比 50ms/80ms/150ms 的实际表现：
- autocomplete 替换是否在缓冲窗口内完成
- 打字延迟感是否可接受
- 中文 compositionend 后的 diff 是否准确

---

### #15 Quick-bar Enter 按钮位置调整（v2 RICE: 13.5, P1）

**状态: 部分调整**

v2 恢复了软键盘 Enter 的 `\r` 发送功能（非 COMPOSING 状态下 `_onBeforeInput` 拦截 `insertParagraph/insertLineBreak` 并发送 `\r`），但 quick-bar 的第一个按钮仍然是 `Enter`。

当前 quick-bar 按钮顺序：`Enter` | Tab | S-Tab | Left | Right | Up | Down | ^C | ^D | ^Z | ^A | ^E | ^L | ^R | Esc | / | Select | Done | Paste | Upload | Debug

v2 评估建议将 Enter 从第一位移到靠后位置（因软键盘 Enter 已恢复），释放高频位置给 ^C/^D/^Z。当前未做此调整。

**影响**: 轻微——Enter 在第一位仍然可用，只是占据了可给更高频 Ctrl 键的位置。

**备注**: v1 时代 Enter 按钮标签是 "NL"，v3 已改为 "Enter"，标签更直观。但 NL 按钮发送的是 `\x1b\r`（ESC + CR），而非纯 `\r`。这是为了兼容某些终端模式。

---

### #8 外接键盘 Cmd 组合键映射（v2 RICE: 8.0, P1）

**状态: 未实现**

`_onKeydown` 中有 `e.ctrlKey` 检测（L1321-1334），但没有 `e.metaKey`（Cmd 键）检测。iPad + Magic Keyboard 用户仍无法使用 Cmd+C（复制）、Cmd+V（粘贴）等常用组合键。

**影响**: iPad 用户（约 20-30% 场景）的外接键盘体验受限。

---

### 汇总

| 排名 | # | 改进项 | v2 RICE | v2 优先级 | v3 状态 | 解决质量 |
|------|---|--------|---------|-----------|---------|----------|
| 1 | 12b | document 级监听器泄漏修复 | 31.7 | P0 | 未修复 | -- |
| 2 | 17 | Soft Backspace 延迟感修复 | 18.7 | P0 | 未修复 | -- |
| 3 | 13 | BUFFER_MS 动态调优 | 14.0 | P1 | 未调优 | 仍为 150ms |
| 4 | 15 | Quick-bar Enter 位置调整 | 13.5 | P1 | 标签已改进 | 位置未调整 |
| 5 | 8 | 外接键盘 Cmd 映射 | 8.0 | P1 | 未实现 | -- |

**结论**: v2 PM 建议的 5 项 v3 改进中，0 项完成、1 项有微小改进（Enter 标签）、4 项未动。v3 在 v2 基础上没有新的输入系统代码变更。

---

## B. 三版代码复杂度对比

### B.1 代码行数对比

| 指标 | v1 | v2/v3 | 变化 |
|------|------|-------|------|
| 文件总行数 | 1399 | 1431 | +32 (+2.3%) |
| 输入事件处理 | ~150 行（分散的 keydown/beforeinput/input/composition + sentBuffer） | ~174 行（InputController 类，L1203-L1376） | +24 (+16%) |
| Quick-bar 构建 | ~110 行（10 个按钮） | ~116 行（16 个按钮 + flush 联动） | +6 |
| 触摸手势 | ~115 行 | ~115 行 | 不变 |
| 键盘/视口调整 | ~50 行 | ~50 行 | 不变 |
| **输入相关总计** | **~425 行** | **~455 行** | **+30 (+7%)** |

注：v2 PM 评估报告中引用的行数（v2 = 1522 行、550 行输入代码）与实际代码存在偏差。本评估基于 `git show f3d501b` 后的实际 `wc -l` 结果。

### B.2 Hack/Workaround 三版对比

| # | Hack 描述 | v1 | v2/v3 | 性质 |
|---|-----------|-----|-------|------|
| H1 | `disableStdin: true` + 独立 textarea | 存在 | 保留 | 架构基础，非 hack |
| H2 | `sentBuffer` diff 模型 | 存在 | **替换为 snapshot diff** | 架构升级 |
| H3 | `scheduleReset()` 800ms 清空 | 存在 | **删除** | 不再需要 |
| H4 | `_emptyKeyTs` 100ms 窗口 | 存在 | 保留（封装到 InputController） | iOS 固有行为抑制 |
| H5 | `justFinishedComposition` + rAF | 存在 | **删除** | 状态机 + 缓冲替代 |
| H6 | `_isWhitespaceKey` 检测 | 存在 | 保留（封装到 InputController） | iOS 中文 IME 行为 |
| H7 | `keydownHandled` 标志 | 存在 | 保留（改为 `this._keydownHandled`） | 封装改善 |
| H8 | beforeinput 阻断 insertParagraph | **阻断不发送** | **改为发送 `\r`** | 根本改进 |
| H9 | `autocomplete="off" autocorrect="off"` | 存在 | 保留 | iOS 不完全尊重，无害 |
| H10 | 透明 textarea -> `.input-visible` 切换 | 存在 | 保留 | UI 必需 |
| H11 | `mousedown preventDefault` 在 quick-bar | 存在 | 保留 | 正确做法 |
| H12 | `enterkeyhint="send"` | 存在 | 保留 | 提示性属性，无害 |

**v1: 12 个 hack** -> **v2/v3: 8 个保留 + 1 个改进 + 3 个删除**

真正的 workaround 仅剩 3 个（H4/H6/H7），均为 iOS 特定行为抑制，已封装在 InputController 内部。

### B.3 可维护性趋势

| 维度 | v1 | v2/v3 | 趋势 |
|------|------|-------|------|
| **封装程度** | 分散的全局变量和函数 | InputController 类封装所有输入逻辑 | 显著上升 |
| **状态管理** | 6 个相互依赖的布尔/字符串 | 4 态状态机 + 3 个辅助变量 | 显著上升 |
| **生命周期** | 全局注册、无清理 | InputController: AbortController; touch: 仍无清理 | 部分上升 |
| **调试能力** | debug overlay 记录原始事件 | debug overlay + flush 日志 + 状态转换隐式记录 | 上升 |
| **代码重复** | keydown 和 beforeinput 都处理 Backspace | 物理 BS 走 keydown、软 BS 走 diff，各司其职 | 消除 |
| **耦合度** | `isComposing` 全局变量跨模块 | `isComposing` 仍为全局（InputController 写入、touch handler 读取） | 未变 |

**可维护性评分**: v1 = 4/10 → v2/v3 = 7/10。InputController 封装是核心升级。残留问题是 document 级 touch listener 的生命周期管理和 `isComposing` 全局耦合。

---

## C. 竞品差距最终状态

### C.1 竞品对比表（三版演进）

| 特性 | v1 | v2/v3 | Termius iOS | Blink Shell |
|------|-----|-------|-------------|-------------|
| **特殊键栏** | 10 按钮 | 16+5 按钮（含 6 个 Ctrl） | 可自定义分组 | SmartKeys |
| **Ctrl/Alt/Cmd** | 仅 ^C | ^C/^D/^Z/^A/^E/^L/^R + Ctrl+A-Z | 完整 | 完整 |
| **软键盘 Enter** | 禁用 | 正常发送 `\r` | 正常 | 正常 |
| **IME/CJK** | 有 bug（P1-P4） | 状态机 + diff，P1-P4 已修复 | 原生 | 专门 IME mode |
| **输入延迟** | 即时（但有 race condition） | 150ms debounce（无 race condition） | 即时 | 即时 |
| **Predictive Text** | 无法禁用 | 无法禁用（debounce 缓解） | 原生控制 | 原生控制 |
| **外接键盘** | 基本 | Ctrl+A-Z（缺 Cmd 映射） | 完整含自定义 | 完整 |
| **事件清理** | 无（全泄漏） | InputController: AbortController; touch: 泄漏 | N/A | N/A |
| **Backspace** | 手动 slice（不准） | 物理: 即时; 软: 150ms diff | 即时 | 即时 |
| **自定义键栏** | 不支持 | 不支持 | 支持 | 支持 |
| **命令历史** | 不支持 | 不支持 | Snippets | 支持 |

### C.2 差距评分（三版对比）

```
                        v1              v2/v3           竞品平均
输入可靠性:     [====------] 40%   [========--] 80%   [=========-] 85%
特殊键覆盖:     [===-------] 30%   [======----] 60%   [=======---] 70%
手势交互:       [======----] 60%   [======----] 60%   [=======---] 70%
自定义能力:     [----------] 0%    [----------] 0%    [======----] 60%
IME 兼容性:     [====------] 40%   [=======---] 70%   [========--] 80%
Enter 键体验:   [==--------] 20%   [=========--] 90%  [==========] 100%
输入延迟感:     [=========--] 90%  [======----] 60%   [=========--] 90%
Backspace:      [=====-----] 50%   [======----] 60%   [==========] 100%
```

**关键观察**:

1. **输入可靠性**: v1 → v2/v3 提升 40 个百分点，接近竞品水平。核心 bug 已修复。
2. **输入延迟感**: v1 → v2/v3 **下降** 30 个百分点。这是 debounce 模型的代价——用可靠性换延迟感。150ms 是偏保守的选择。
3. **Backspace**: v1 → v2/v3 仅提升 10 个百分点。物理 BS 改善明显，但软键盘 BS 的 150ms 延迟抵消了 diff 模型的准确性优势。
4. **最大残留差距**: 自定义能力（0% vs 60%）、输入延迟感（60% vs 90%）、Backspace（60% vs 100%）。

---

## D. 测试覆盖率评估

### D.1 测试资产清单

| 测试文件 | 类型 | 场景数 | 断言数 | 通过率 |
|----------|------|--------|--------|--------|
| `tests/test-input-system.mjs` | 单元测试（InputControllerSim） | 24 组 | 47 | 47/47 (100%) |
| `tests/test-mobile-ux.mjs` | Playwright 端到端 | ~25 场景 | — | 需运行服务器 |
| `tests/test-cold-start.sh` | Shell 集成 | 1 场景 | — | — |

### D.2 单元测试覆盖分析

**已覆盖场景** (24 组):

| # | 场景 | 可靠度 | v1 有无 |
|---|------|--------|---------|
| 1-4 | 英文打字 + debounce 合并 + autocomplete（追加/纠错） | 高 | 无 |
| 5-6 | 软键盘 Enter（非 COMPOSING 发送 / COMPOSING 阻断） | 高 | 无（v1 无此功能） |
| 7 | Tab 重置 snapshot | 高 | 无 |
| 8 | 中文 composition 增量 diff | 高 | 无 |
| 9 | 物理键盘 Backspace 即时发送 | 高 | 无 |
| 10 | 软键盘 Backspace 走 diff | 高 | 无 |
| 11 | iOS 整词删除 | 高 | 无 |
| 12 | Session 切换 AbortController 清理 | 高 | 无 |
| 13 | Composition 暂停缓冲 | 高 | 无 |
| 14 | Enter 先 flush 缓冲 | 高 | 无 |
| 15 | 无变化时不发送 | 高 | 无 |
| 16-17 | 状态机完整周期（普通 + composition） | 高 | 无 |
| 18-23 | Ctrl+C/D/Z/A/E/L/R + buffer flush + composition 阻断 | 高 | 无 |
| 24 | 软 Enter 打字后 flush buffer | 高 | 无 |

**未覆盖但可自动化的场景**:

| 场景 | 可行性 | 说明 |
|------|--------|------|
| Document 级 touch listener 泄漏检测 | 高 | Playwright: 多次 connect/disconnect + 计数 |
| Quick-bar 所有 21 个按钮 wsSend 正确性 | 高 | Playwright: 点击按钮 + 拦截 WebSocket |
| InputController destroy() 后事件不触发 | 高 | 单元测试: destroy() 后调用 typeChar/softEnter 验证无发送 |
| BUFFER_MS 边界: autocomplete 在窗口内/外 | 高 | 单元测试: 调整时序 |
| sendKey() flush 联动 | 高 | 单元测试: 模拟 quick-bar sendKey 前 buffer 状态 |
| 连续软 Backspace 延迟累积 | 中 | 单元测试: 多次 softBackspace + 计时 |

**只能真机测试的场景**（与 v1/v2 评估一致）:

| 场景 | 原因 |
|------|------|
| iOS predictive text + autocomplete 真实时序 | Playwright 无法模拟 iOS 联想词 |
| 150ms BUFFER_MS 是否产生可感知延迟 | 主观体感 |
| 软键盘 Backspace 150ms 延迟是否可接受 | 主观体感 |
| 中文搜狗输入法 composition 边界 | 输入法差异 |
| 软键盘弹出/收起布局联动 | visualViewport 因设备而异 |
| 蓝牙键盘 Ctrl+字母 | USB/BT 键盘事件差异 |

### D.3 覆盖率评估

| 维度 | v1 | v2/v3 | 变化 |
|------|------|-------|------|
| 单元测试覆盖 | 0%（无测试） | ~75%（24 组/47 断言） | 从零到高 |
| Playwright 覆盖 | 0% | ~40%（代码检查为主） | 从零到中 |
| 真机覆盖 | 手动 | 手动 | 未变 |
| **综合覆盖率** | **~5%** | **~50%** | **+45pp** |

**评价**: 测试覆盖率从接近零提升到 50%，是 v2/v3 最大的质量保障改进之一。InputController 的核心逻辑（状态转换、diff 计算、特殊键处理）都有自动化测试。主要缺口在 document 级 listener 管理和 UI 交互层。

---

## E. "可发布"状态评估

### E.1 发布标准检查

| 标准 | 状态 | 说明 |
|------|------|------|
| **核心功能可用** | PASS | 英文/中文输入、Enter/Tab/Esc/方向键、Ctrl 组合键均正常 |
| **已知 Critical Bug 数** | 0 | v1 的 P1-P4 bug 全部修复 |
| **已知 High Bug 数** | 2 | #12b listener 泄漏 + #17 soft BS 延迟 |
| **自动化测试通过** | PASS | 47/47 (100%) |
| **回归风险** | 低 | InputController 封装隔离了输入逻辑，修改不易影响其他模块 |
| **用户体验底线** | PASS | "日常可用"——输入不出错、Enter 正常、Ctrl 键可用 |
| **性能** | WARN | listener 泄漏会导致长时间使用后性能下降 |

### E.2 判定

**结论: 有条件可发布。**

输入系统已达到"日常可用"的质量水平，核心输入路径（英文、中文、特殊键）可靠，不再有阻断性 bug。但存在两个 High 级问题：

1. **Document 级 listener 泄漏 (#12b)**: 不影响首次连接体验，但切换 session 多次后会出现滚动异常和性能下降。对于大多数用户（连接一个 session 持续使用）影响可忽略。
2. **Soft Backspace 150ms 延迟 (#17)**: 所有手机用户受影响。单次删除不明显，连续删除时会感到"粘滞"。不阻断使用但影响体感。

**发布建议**:
- **可以发布**：作为内部工具 / 个人使用场景，当前质量足够
- **发布前快速修复**（如果追求更好体验）：#12b（0.3 周）+ #17（0.2 周）= 0.5 周即可解决两个 High 问题
- **不建议延迟发布等待**: #13 BUFFER_MS 调优、#8 Cmd 映射、#15 按钮位置等属于 polish，可在发布后迭代

---

## F. 未来改进方向（不在 v3 范围）

以下改进留给后续版本，按 RICE 排序：

### 第一梯队 — 体感打磨（0.5-1 周）

| # | 改进项 | RICE | 说明 |
|---|--------|------|------|
| 12b | Document 级 listener 泄漏修复 | 31.7 | 创建 `_touchAC = new AbortController()`，4 个 listener 使用 `{ signal: _touchAC.signal }`，cleanupConnection 中 abort |
| 17 | Soft Backspace 立即 flush | 18.7 | `_onInput` 中检测 `deleteContentBackward` 时调用 `_flush()` 而非 `_startBuffer()` |
| 13 | BUFFER_MS 真机调优 | 14.0 | 从 150ms 逐步降低到 80ms/50ms，在 iPhone 上验证 autocomplete 覆盖率 |
| 15 | Quick-bar 按钮重排 | 13.5 | 将 ^C/^D/^Z 前移，Enter 后移（或保持但可接受） |

### 第二梯队 — 功能补全（1-2 周）

| # | 改进项 | RICE | 说明 |
|---|--------|------|------|
| 8 | 外接键盘 Cmd 映射 | 8.0 | `e.metaKey` 检测：Cmd+C→复制, Cmd+V→粘贴 |
| 14 | isComposing 全局变量去耦 | 6.75 | InputController 暴露只读属性，touch handler 通过引用读取 |
| 3 | 输入预览 | 6.7 | input-visible 区域实时显示 textarea.value |

### 第三梯队 — 高级功能（3+ 周）

| # | 改进项 | RICE | 说明 |
|---|--------|------|------|
| 4 | 命令历史 | 4.9 | localStorage 存储 + quick-bar 上下翻页 |
| 6 | 多行输入模式 | 1.2 | 展开 textarea，Enter 换行，专用发送按钮 |
| 5 | 智能补全 | 1.25 | 本地历史前缀匹配 + 可选 Claude API |
| -- | Quick-bar 可自定义 | -- | 拖拽排序 + 添加/删除按钮 |
| -- | Termius 式手势 | -- | 长按空格 + 滑动 = 方向键 |

---

## G. 三版迭代 ROI 总结

### G.1 投入产出对比表

| 维度 | v1（基线） | v2/v3（当前） | 增量投入 | 增量产出 |
|------|-----------|-------------|---------|---------|
| **代码行数** | 1399 | 1431 | +32 行 (+2.3%) | — |
| **输入相关代码** | ~425 行 | ~455 行 | +30 行 (+7%) | — |
| **Hack 数量** | 12 个 | 9 个（3 删除 + 1 改进） | -3 个 hack | 技术债降低 25% |
| **真正 workaround** | 6 个 | 3 个（均为 iOS 固有行为） | -3 个 workaround | 维护负担减半 |
| **Critical/High Bug** | 4 个（P1-P4） | 2 个（#12b, #17） | -2 个 critical bug | 核心路径无阻断 bug |
| **测试断言数** | 0 | 47 | +47 | 回归保护从零到有 |
| **测试通过率** | N/A | 100% | — | 可自动化验证 |
| **特殊键覆盖** | 10 个按钮 | 16+5 个按钮 | +11 个按钮 | Ctrl 操作全覆盖 |
| **软键盘 Enter** | 禁用 | 正常发送 | 恢复核心功能 | 用户最大痛点消除 |
| **输入可靠性** | 40% | 80% | +40pp | 接近竞品水平 |
| **代码封装** | 全局散落 | InputController 类 | 架构升级 | 可独立测试/替换 |

### G.2 用户体验评分变化

| 维度 | v1 | v2/v3 | 变化 |
|------|-----|-------|------|
| 英文输入流畅度 | 7/10 | 8/10 | +1（race condition 消除，但 150ms 延迟） |
| 中文输入体验 | 6/10 | 8/10 | +2（compositionend 走 diff，不再重复） |
| 特殊键响应 | 5/10 | 8/10 | +3（Enter 恢复 + 6 个 Ctrl 按钮） |
| 粘贴体验 | 7/10 | 7/10 | 不变 |
| 输入框可见性 | 6/10 | 6/10 | 不变 |
| 快捷键栏 | 7/10 | 8/10 | +1（更多按钮） |
| 键盘与滚动冲突 | 8/10 | 8/10 | 不变 |
| 输入延迟感 | 9/10 | 7/10 | -2（150ms debounce 代价） |
| 自动纠正干扰 | 8/10 | 8/10 | 不变 |
| Backspace 体验 | 6/10 | 6/10 | 不变（物理改善，软键盘延迟抵消） |
| 整体打字满意度 | 6/10 | 8/10 | +2（Enter 恢复 + 可靠性提升是质变） |
| **综合** | **6.8/10** | **7.5/10** | **+0.7** |

### G.3 ROI 结论

**投入**: 约 1.5 周工程时间（InputController 重写 + 测试编写 + Ctrl 按钮 + Enter 恢复），32 行净增。

**产出**:
- 消除了 4 个 Critical/High bug 中的 2 个（最严重的 P1 英文联想 + P4 中文重复）
- 恢复了用户最大痛点（软键盘 Enter）
- 建立了 47 项自动化测试防线
- 架构从"hack 堆叠"升级为"可维护的状态机"
- 用户体验综合评分 +0.7（6.8 → 7.5）

**ROI 评价**: **高**。以极小的代码增量（+2.3%）实现了架构质变。输入系统从"能用但痛苦"提升到"日常可用"。最大的投资回报来自 InputController 封装——它不仅解决了当前 bug，还为未来迭代（BUFFER_MS 调优、Cmd 映射等）提供了清晰的修改入口。

**未兑现的价值**: v2 PM 规划的 5 项 v3 改进均未完成。如果完成 #12b + #17（额外 0.5 周），综合评分可进一步提升至 ~7.8/10，输入延迟感和 Backspace 体验各提升 1-2 分。这是当前投入产出比最高的后续动作。

---

## 附录: 三版关键数据对比总表

| 指标 | v1 | v2/v3 | 竞品参考 |
|------|------|-------|---------|
| 文件总行数 | 1399 | 1431 | N/A |
| 输入代码行数 | ~425 | ~455 | N/A |
| Hack 数量 | 12 | 9 | N/A |
| Critical/High Bug | 4 | 2 | 0 |
| 自动化测试 | 0 | 47 | N/A |
| Quick-bar 按钮 | 10+5 | 16+5 | 可自定义 |
| 软键盘 Enter | 禁用 | 正常 | 正常 |
| Ctrl 组合键 | 仅 ^C | ^C/D/Z/A/E/L/R + Ctrl+A-Z | 完整 |
| 输入可靠性 | 40% | 80% | 85% |
| 输入延迟感 | 90%（即时） | 60%（150ms） | 90% |
| 综合 UX 评分 | 6.8/10 | 7.5/10 | 8.5/10 |
| 可维护性 | 4/10 | 7/10 | N/A |
| 发布就绪 | 否 | **有条件是** | 是 |
