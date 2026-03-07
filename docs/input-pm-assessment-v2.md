# 移动端输入系统 PM 评估报告 v2

**日期**: 2026-03-07
**评估人**: 产品经理（输入体验方向）
**评估对象**: `public/index.html` v2 输入系统（InputController 状态机）
**参考文档**: `docs/input-pm-assessment-v1.md`（v1 评估）、`docs/input-user-review-v1.md`（v1 用户反馈）、`docs/mobile-input-redesign.md`（研究报告）

---

## A. v1 RICE 前 4 项改进验证

v1 评估的 RICE 排名前 4 项：

### #12 事件监听器泄漏修复 (v1 RICE: 31.7, P0)

**状态: ⚠️ 部分修复**

- InputController 本身使用 `AbortController` 管理 5 个 textarea 事件监听器（compositionstart/end、beforeinput、input、keydown），`destroy()` 时一次性清除。这是根本修复。
- `cleanupConnection()` 调用 `inputController.destroy()` 确保 session 切换时无 InputController 层面的泄漏。
- **遗留问题**: `connect()` 中 `if (isMobile)` 块内注册的 4 个 document 级监听器（`touchstart`、`touchmove`、`touchend`、`selectionchange`）仍然没有清理机制。每次调用 `connect()` 都会累积新的 touch handler。这与 v1 的问题相同。

**解决质量**: 核心输入事件（InputController 管辖）= 根本修复。document 级触摸/选择事件 = 未修复。

---

### #11 Ctrl/Alt 修饰键按钮 (v1 RICE: 28.8, P0)

**状态: ✅ 已解决**

v2 quick-bar 新增 7 个 Ctrl 组合键按钮：

| 按钮 | 序列 | 用途 |
|------|------|------|
| ^C | `\x03` | 中断进程（v1 已有） |
| ^D | `\x04` | EOF / 退出 REPL |
| ^Z | `\x1a` | 挂起进程 |
| ^A | `\x01` | tmux prefix / 行首 |
| ^E | `\x05` | 行尾 |
| ^L | `\x0c` | 清屏 |
| ^R | `\x12` | 反向搜索历史 |

此外，`_onKeydown` 新增物理键盘 `Ctrl+[a-z]` 组合键映射（line 1382-1398），将 `e.ctrlKey + 字母键` 转换为对应控制字符。这解决了外接蓝牙键盘的 Ctrl 组合键问题。

**解决质量**: 根本修复。按钮覆盖了终端最常用的 6 个 Ctrl 组合。物理键盘 Ctrl+A-Z 全覆盖。

---

### #2 关闭 autocorrect/autocapitalize (v1 RICE: 16.0, P0)

**状态: ⚠️ 无实质变化**

textarea 仍然是 `autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"`。这些属性在 iOS Safari 上效果有限——iOS 仍然显示 predictive text bar。

v2 没有新增 `type="password"` 可选模式开关（v1 研究报告建议的降级方案）。不过 v2 的 80ms 缓冲窗口（BUFFER_MS）有效缓解了 autocomplete 替换导致的 race condition，间接降低了 autocorrect 干扰的影响。

**解决质量**: 属性层面无变化。缓冲机制间接缓解了 autocomplete 的负面影响。

---

### #1 统一 debounce 缓冲（消除英文联想问题）(v1 RICE: 14.4, P0)

**状态: ✅ 已解决**

这是 v2 最核心的改进。InputController 实现了完整的状态机 + snapshot diff + 统一缓冲：

| v1 问题 | v2 修复 |
|---------|---------|
| P1: 英文联想词时序 race condition | 80ms BUFFER_MS 缓冲窗口，autocomplete 替换在 flush 前完成，diff 只看最终结果 |
| P2: 800ms resetTimer 误清 | 去掉了 scheduleReset/resetTimer，snapshot 仅在 flush/Enter/Tab 后更新 |
| P3: sentBuffer 与 textarea.value 不同步 | snapshot diff 模型替代 sentBuffer 追加式追踪，单一 flush 点更新 |
| P4: compositionend 发送全量 + 后续 input 重复 | compositionend 不直接发送，进入 BUFFERING 状态，30ms 后通过 diff 发送增量 |
| D1: 英文/中文逻辑不统一 | 统一的 IDLE-COMPOSING-BUFFERING-FLUSHING 状态机，两种语言同路径 |
| D3: 800ms 硬编码魔法数字 | 改为 80ms BUFFER_MS，无 resetTimer |
| D4: compositionend 发全量 | compositionend 走 diff，只发增量 |
| Tab/特殊键后 sentBuffer 不同步 | Tab/Enter 后调用 resetSnapshot()，强制重新同步 |
| Backspace 手动 slice 不准 | 物理键盘 Backspace 直接发送 + 更新 snapshot；软键盘 Backspace 交给浏览器处理后走 diff |

**额外修复 — 软键盘 Enter 恢复**：v1 最大的用户痛点（"软键盘 Enter 被完全禁用"）在 v2 中修复。`_onBeforeInput` 在非 COMPOSING 状态下拦截 `insertParagraph/insertLineBreak` 后发送 `\r`（而非 v1 的 `preventDefault + 不发送`）。用户不再需要每次都去按快捷栏的 Enter 按钮。

**解决质量**: 根本修复。从"hack 堆叠"升级为"状态机驱动"，消除了 v1 的 4 个 Critical/High bug 和 3 个设计缺陷。

---

### 汇总

| # | 改进项 | v1 RICE | 状态 | 解决质量 |
|---|--------|---------|------|----------|
| 12 | 事件监听器泄漏修复 | 31.7 | ⚠️ 部分 | InputController: 根本修复。document 级 touch/selection: 未修复 |
| 11 | Ctrl/Alt 修饰键按钮 | 28.8 | ✅ 完成 | quick-bar 7 个按钮 + 物理键盘 Ctrl+A-Z |
| 2 | autocorrect/autocapitalize | 16.0 | ⚠️ 间接缓解 | HTML 属性无变化，缓冲间接缓解 |
| 1 | 统一 debounce 缓冲 | 14.4 | ✅ 完成 | InputController 状态机 + snapshot diff，根本修复 |

---

## B. 代码复杂度变化

### B.1 代码行数对比

| 指标 | v1 | v2 | 变化 |
|------|------|------|------|
| 文件总行数 | ~1373 | 1522 | +149 (+11%) |
| 输入事件处理 | ~150 行（分散的 keydown/beforeinput/input/composition） | ~265 行（InputController 类） | +115 (+77%) |
| Quick-bar 构建 | ~110 行（10 个按钮） | ~120 行（16 个按钮 + flush 联动） | +10 |
| 触摸手势 | ~115 行 | ~115 行 | 不变 |
| 键盘/视口调整 | ~50 行 | ~50 行 | 不变 |
| **输入相关总计** | **~425 行** | **~550 行** | **+125 (+29%)** |

行数增加主要来自：(1) InputController 类封装增加了方法定义开销；(2) 新增的 Ctrl 组合键处理逻辑；(3) 状态转换调试日志。

### B.2 Hack/Workaround 变化

| # | v1 Hack | v2 状态 | 说明 |
|---|---------|---------|------|
| H1 | `disableStdin: true` + 独立 textarea | **保留** | 架构基础，非 hack |
| H2 | `sentBuffer` diff 模型 | **替换** | 改为 snapshot diff，逻辑更清晰 |
| H3 | `scheduleReset()` 800ms 清空 | **删除** | 不再需要定时清空 |
| H4 | `_emptyKeyTs` 100ms 窗口 | **保留** | iOS Enter 序列的固有行为仍需抑制 |
| H5 | `justFinishedComposition` + rAF | **删除** | 状态机 + 缓冲替代 |
| H6 | `_isWhitespaceKey` 检测 | **保留** | iOS 中文 IME 行为仍需处理 |
| H7 | `keydownHandled` 标志 | **保留** | 改为 `_keydownHandled`，封装在 InputController 内 |
| H8 | beforeinput 阻断 insertParagraph | **改进** | 不再阻断，改为发送 `\r`（非 COMPOSING 时） |
| H9 | `autocomplete="off" autocorrect="off"` | **保留** | iOS 不完全尊重，但不伤害 |
| H10 | 透明 textarea -> `.input-visible` 切换 | **保留** | UI 层面必需 |
| H11 | `mousedown preventDefault` 在 quick-bar | **保留** | 保持键盘焦点，正确做法 |
| H12 | `enterkeyhint="send"` | **保留** | 提示性属性，无害 |

**v1: 12 个 hack** -> **v2: 8 个保留 + 1 个改进 + 3 个删除**

实际 hack 减少了 3 个（H3 scheduleReset、H5 justFinishedComposition、H8 阻断 Enter）。剩余 8 个中，H1/H9/H10/H11/H12 是架构/UI 必需品而非 hack，真正的 workaround 只剩 H4（_emptyKeyTs）、H6（_isWhitespaceKey）、H7（_keydownHandled）——3 个 iOS 特定行为抑制。

### B.3 可维护性评估

| 维度 | v1 | v2 | 评价 |
|------|------|------|------|
| **封装程度** | 分散的全局变量和函数 | InputController 类封装所有输入逻辑 | 显著改善 |
| **状态管理** | 6 个相互依赖的布尔/字符串（isComposing, keydownHandled, justFinishedComposition, sentBuffer, _emptyKeyTs, _enterParagraphHandled） | 4 态状态机（IDLE/COMPOSING/BUFFERING/FLUSHING）+ 3 个辅助变量 | 显著改善 |
| **生命周期** | 全局注册、无清理 | AbortController + destroy() | 根本改善 |
| **调试能力** | debug overlay 记录原始事件 | debug overlay + 状态转换日志 `_setState()` | 改善 |
| **代码重复** | keydown 和 beforeinput 都处理 Backspace | keydown 处理物理键盘 Backspace，soft 走 diff | 消除重复 |
| **耦合度** | `isComposing` 全局变量跨模块使用 | `isComposing` 仍为全局（InputController 内写入）| 未完全解耦 |

**总体评估**: v2 的可维护性从"中等偏高技术债务"改善为"中等偏低"。InputController 封装使得输入系统成为一个可独立理解、替换和测试的模块。最大的残留问题是 `isComposing` 全局变量和 document 级 touch listener 的泄漏。

---

## C. 竞品差距缩小

### C.1 更新竞品对比表

| 特性 | v1 | v2 | Termius iOS | Blink Shell | WebSSH |
|------|-----|-----|-------------|-------------|--------|
| **特殊键栏** | 10 个按钮 | 16+5 个按钮（含 6 个 Ctrl） | 可自定义分组 | SmartKeys | 可自定义 |
| **Ctrl/Alt/Cmd 组合** | 仅 ^C | ^C/^D/^Z/^A/^E/^L/^R + Ctrl+A-Z | 完整 | 完整 | 完整 |
| **软键盘 Enter** | 禁用（必须按 NL） | 正常发送 \r | 正常 | 正常 | 正常 |
| **IME/CJK** | 有 bug（P1-P4） | 状态机 + diff，P1-P4 已修复 | 原生 | 专门 IME mode | v29.8 修复 |
| **Predictive Text** | 无法禁用 | 无法禁用（缓冲缓解） | 原生控制 | 原生控制 | 原生控制 |
| **外接键盘** | 基本（无快捷键） | Ctrl+A-Z 支持 | 完整（含自定义） | 完整 | 支持 |
| **事件清理** | 无（泄漏） | InputController: AbortController | N/A | N/A | N/A |
| **Backspace 处理** | 手动 slice（不准） | 物理: 直接发送; 软: diff 检测 | 原生 | 原生 | 原生 |

### C.2 差距评分更新

```
                        v1              v2              竞品平均
输入可靠性:     [====------] 40%   [========--] 80%   [========--] 80%
特殊键覆盖:     [===-------] 30%   [======----] 60%   [=======---] 70%
手势交互:       [======----] 60%   [======----] 60%   [=======---] 70%
自定义能力:     [----------] 0%    [----------] 0%    [======----] 60%
IME 兼容性:     [====------] 40%   [=======---] 70%   [========--] 80%
Enter 键体验:   [==--------] 20%   [=========--] 90%  [==========] 100%
```

**特殊键覆盖率**: v1 = 30% -> v2 = 60%

v1 支持: Enter(quick-bar), Tab, Shift-Tab, 方向键x4, ^C, Esc, / = 10 个按钮

v2 新增: ^D, ^Z, ^A, ^E, ^L, ^R + Ctrl+A-Z(物理键盘) = 覆盖率从 10/~25 常用键 (40%) 提升到 16+26/~25 常用键 (60%+)

**仍然缺失**: F1-F12、Home/End、PgUp/PgDn、Alt 组合键。Cmd+C/V 粘贴映射。

**核心差距变化**: v1 的两大短板（输入可靠性 + 特殊键覆盖）都有显著改善。v2 的主要差距缩小到自定义能力（0%）和高级功能（命令历史、多行输入等）。

---

## D. v3 RICE 重新评估

### D.1 v1 遗留项重新评分

| # | 改进项 | v1 RICE | v2 后状态 | v3 R | I | C | E（周） | v3 RICE | 优先级 |
|---|--------|---------|-----------|------|---|---|---------|---------|--------|
| 12b | **document 级 touch/selection 监听器泄漏修复** | 31.7 的残留 | 未修复 | 10 | 1 | 95% | 0.3 | **31.7** | **P0** |
| 8 | **外接键盘支持优化（Cmd 组合键映射）** | 9.6 | Ctrl+A-Z 已支持，缺 Cmd+C/V/K | 5 | 1 | 80% | 0.5 | **8.0** | P1 |
| 3 | **输入预览（输入框实时显示将发送内容）** | 9.0 | 未做 | 5 | 0.5 | 80% | 0.3 | **6.7** | P2 |
| 4 | **命令历史（上浏览历史）** | 4.9 | 未做 | 7 | 2 | 70% | 2 | **4.9** | P2 |
| 6 | **多行输入模式** | 1.2 | 未做 | 4 | 1 | 60% | 2 | **1.2** | P3 |
| 5 | **智能补全** | 1.25 | 未做 | 5 | 2 | 50% | 4 | **1.25** | P3 |
| 7 | **语音转文字** | 1.05 | 未做 | 3 | 0.5 | 70% | 1 | **1.05** | P3 |
| 9 | **输入撤销** | 0.5 | 未做 | 3 | 0.5 | 50% | 1.5 | **0.5** | P4 |
| 10 | **剪贴板历史** | 0.2 | 未做 | 2 | 0.5 | 60% | 3 | **0.2** | P4 |

### D.2 v2 中新发现的改进项

| # | 改进项 | R | I | C | E（周） | RICE | 优先级 | 说明 |
|---|--------|---|---|---|---------|------|--------|------|
| 13 | **BUFFER_MS 动态调优** | 7 | 0.5 | 80% | 0.2 | **14.0** | P1 | 当前 80ms 固定值；可根据 `navigator.connection` 或历史 autocomplete 时序自动调整。快速打字时 80ms 可能感觉到延迟，建议降到 30-50ms 后真机验证 |
| 14 | **isComposing 全局变量去耦** | 3 | 0.5 | 90% | 0.2 | **6.75** | P2 | InputController 内部写入全局 `isComposing`，与 touch handler 中的条件判断耦合。应改为 InputController 暴露只读属性 |
| 15 | **Quick-bar Enter 按钮降级角色调整** | 6 | 0.25 | 90% | 0.1 | **13.5** | P1 | 软键盘 Enter 已恢复，⏎ 按钮变为备用。可考虑移到靠后位置或标注为 "Backup Enter"，释放高频位置给其他按钮 |
| 16 | **InputController 状态可视化** | 4 | 0.25 | 90% | 0.2 | **4.5** | P2 | Debug overlay 已有状态转换日志；可在 input-visible 区域显示当前状态（IDLE/COMPOSING/BUFFERING）便于用户理解系统行为 |
| 17 | **Soft Backspace 延迟感** | 8 | 1 | 70% | 0.3 | **18.7** | **P0** | 软键盘 Backspace 走 diff 路径需等待 80ms 缓冲，用户按 Backspace 后 80ms 才看到删除效果。物理键盘无此问题。建议 Backspace 类 inputType 时缩短缓冲或立即 flush |

### D.3 v3 RICE 排序（Top 8）

| 排名 | # | 改进项 | RICE | 优先级 | 工作量 |
|------|---|--------|------|--------|--------|
| 1 | 12b | document 级监听器泄漏修复 | 31.7 | P0 | 0.3 周 |
| 2 | 17 | Soft Backspace 延迟感修复 | 18.7 | P0 | 0.3 周 |
| 3 | 13 | BUFFER_MS 动态调优 / 真机验证 | 14.0 | P1 | 0.2 周 |
| 4 | 15 | Quick-bar Enter 按钮位置调整 | 13.5 | P1 | 0.1 周 |
| 5 | 8 | 外接键盘 Cmd 组合键映射 | 8.0 | P1 | 0.5 周 |
| 6 | 14 | isComposing 全局变量去耦 | 6.75 | P2 | 0.2 周 |
| 7 | 3 | 输入预览 | 6.7 | P2 | 0.3 周 |
| 8 | 4 | 命令历史 | 4.9 | P2 | 2 周 |

### D.4 v3 应该做什么

**v3 主题: 消除残留问题 + 体感打磨**

v2 完成了架构升级（InputController 状态机），v3 不需要大架构改动，重点是：

1. **修复残留泄漏** (#12b): document 级 touch/selection listener 使用 AbortController 或 guard 变量清理。0.3 周工作量，无风险。

2. **消除 Backspace 延迟** (#17): `deleteContentBackward` 类 inputType 在 `_onInput` 中立即 flush（不等待 80ms），或将 BUFFER_MS 对 Backspace 场景缩短为 0。用户对删除操作的延迟容忍度远低于输入。

3. **BUFFER_MS 真机调优** (#13): 当前 80ms 比研究报告建议的 30ms 高出一倍多。在 iPhone 15 + iOS 18 上对比 30ms/50ms/80ms 的 autocomplete 覆盖率和打字延迟感。目标: 找到最短的安全缓冲窗口。

4. **Quick-bar 微调** (#15): 软键盘 Enter 已恢复，⏎ 按钮可从第一位移到 ^C 之后。将高频 Ctrl 键（^C, ^D, ^Z）前移。

5. **外接键盘 Cmd 映射** (#8): 检测 `e.metaKey`，映射 Cmd+C -> 复制、Cmd+V -> 粘贴。iPad 用户刚需。

**v3 预估工作量**: 1-1.5 周

**v3 验收标准**:
- 切换 session 5 次后，检查 `getEventListeners(document)` 无 touch handler 累积
- 软键盘 Backspace 响应延迟 < 16ms（一帧）
- iPhone 15 真机连续输入英文 + 点联想词，无闪烁、无重复
- Magic Keyboard Cmd+C/V 正常工作

---

## E. 测试覆盖评估

### E.1 现有自动化测试

| 测试文件 | 类型 | 场景数 | 通过率 | 覆盖范围 |
|----------|------|--------|--------|----------|
| `tests/test-input-system.mjs` | 单元测试（InputController 模拟） | 15 组 / 41 断言 | 41/41 (100%) | 英文打字、autocomplete 替换、中文 composition、Enter/Tab/Esc 特殊键、Backspace（物理+软）、iOS 整词删除、session 切换清理、debounce 合并 |
| `tests/test-mobile-ux.mjs` | Playwright 端到端 | ~25 场景 | 需运行服务器 | input-visible CSS、long-press 常量、keyboard+swipe、z-index、listener 选项 |
| `tests/test-cold-start.sh` | Shell 集成 | 1 场景 | — | 冷启动 |

### E.2 覆盖分析

**已覆盖的场景**:

| 场景 | 测试方式 | 可靠度 |
|------|----------|--------|
| 英文逐字输入 + debounce 合并 | 单元测试 | 高 |
| 英文 autocomplete 替换（追加/纠错） | 单元测试 | 高 |
| 中文 composition 全流程 | 单元测试 | 高 |
| Enter/Tab/Esc 立即发送 + buffer flush | 单元测试 | 高 |
| 物理键盘 Backspace | 单元测试 | 高 |
| iOS 软键盘整词删除 | 单元测试 | 高 |
| AbortController 清理 | 单元测试 | 高 |
| input-visible CSS 切换 | Playwright | 中 |
| long-press 参数验证 | Playwright（代码检查） | 中 |
| keyboard+swipe re-focus 逻辑 | Playwright（代码检查） | 中 |

**未覆盖但可自动化的场景**:

| 场景 | 可行性 | 建议工具 |
|------|--------|----------|
| Ctrl+字母组合键映射正确性 | 高 | 单元测试（扩展 InputControllerSim） |
| Quick-bar 所有 16 个按钮的 wsSend 正确性 | 高 | Playwright（点击按钮 + 拦截 WebSocket） |
| Document 级 touch listener 泄漏检测 | 高 | Playwright（多次 connect/disconnect + getEventListeners） |
| Soft Enter 在非 COMPOSING 时发送 \r | 高 | 单元测试 |
| BUFFER_MS 边界：autocomplete 在缓冲窗口内/外 | 高 | 单元测试（调整 BUFFER_MS + 模拟时序） |
| InputController destroy() 后事件不触发 | 高 | 单元测试 |

**只能真机测试的场景**（与 v1 相同）:

| 场景 | 原因 |
|------|------|
| iOS predictive text + autocomplete 真实时序 | Playwright 无法模拟 iOS 原生联想词 |
| 80ms BUFFER_MS 是否足够覆盖 autocomplete | 需真实 iOS 输入法时序 |
| 软键盘 Backspace 延迟感（80ms）是否可接受 | 主观体感 |
| 中文拼音 + 搜狗输入法边界 | composition 事件链因输入法而异 |
| 软键盘弹出/收起布局联动 | visualViewport 行为因设备而异 |
| 蓝牙键盘 Ctrl+字母组合 | USB/BT 键盘事件与软键盘不同 |

### E.3 测试覆盖率评估

- **单元测试覆盖**: InputController 核心逻辑的 ~70%（缺 Ctrl 组合、soft Enter、destroy 后行为）
- **Playwright 覆盖**: UI/DOM 层面 ~40%（代码检查为主，缺少真正的交互测试）
- **真机覆盖**: 0%（需手动执行）
- **综合覆盖率**: ~45%

### E.4 v3 测试建议

1. **扩展 test-input-system.mjs**: 新增 Ctrl+字母、soft Enter、destroy 后行为、BUFFER_MS 边界的测试用例
2. **Playwright listener 泄漏测试**: connect() 5 次后检查 document listener 数量
3. **真机测试清单**: 每次发版前在 iPhone 15 + iOS 18 上执行标准化测试流程（英文打字 + 联想 + 中文 + Enter + Tab 补全 + Backspace）

---

## 附录: v1 vs v2 用户体验评分变化预估

| 维度 | v1 分数 | v2 预估 | 变化原因 |
|------|---------|---------|----------|
| 英文输入流畅度 | 7/10 | 8/10 | race condition 消除，debounce 合并 |
| 中文输入体验 | 6/10 | 8/10 | P4 修复，compositionend 走 diff |
| 特殊键响应 | 5/10 | 8/10 | 软键盘 Enter 恢复 + Ctrl 按钮 |
| 粘贴体验 | 7/10 | 7/10 | 未变化 |
| 输入框可见性 | 6/10 | 6/10 | 未变化 |
| 快捷键栏 | 7/10 | 8/10 | 更多按钮，NL->⏎ |
| 键盘与滚动冲突 | 8/10 | 8/10 | 未变化 |
| 输入延迟感 | 7/10 | 7/10 | 80ms 缓冲增加了微小延迟，但消除了闪烁 |
| 自动纠正干扰 | 8/10 | 8/10 | 缓冲间接改善但属性层面未变 |
| 整体打字满意度 | 6/10 | 8/10 | Enter 键恢复是质变 |
| **综合** | **6.7/10** | **7.6/10** | **+0.9** |

**最大改善来源**: 软键盘 Enter 恢复（5->8, +3）、中文输入修复（6->8, +2）、Ctrl 按钮补全（5->8 特殊键 +3）。

**v2 结论**: 输入系统从"能用但痛苦"提升到"日常可用"。架构从 hack 堆叠升级为可维护的状态机。v3 的目标是"顺滑"——消除延迟感、修复残留泄漏、真机调优缓冲参数。
