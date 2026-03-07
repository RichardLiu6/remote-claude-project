# Web Terminal 移动端输入体验评测 v3

> 评测对象：`public/index.html` 中的移动端输入系统（v3 重写后）
>
> 评测环境：iPhone Safari，iOS 英文键盘（联想/自动纠正开启），搜狗/原生拼音输入法，外接蓝牙键盘
>
> 评测日期：2026-03-07
>
> 基线对比：`docs/input-user-review-v1.md`（综合 6.7/10）、`docs/input-user-review-v2.md`（综合 6.8/10）

---

## 0. v3 变更清单

v3 是一次**架构级重写**，不是增量修补。通过 `git diff` 确认，核心改动如下：

| # | 改动 | 具体内容 |
|---|------|----------|
| 1 | **输入模型重写为 InputController 类** | 用状态机（IDLE/COMPOSING/BUFFERING/FLUSHING）替代原来的 sentBuffer + 三层事件拦截器。所有输入统一走 150ms debounce buffer |
| 2 | **软键盘 Enter 恢复！** | `beforeinput` 中 `insertParagraph`/`insertLineBreak` 不再 `preventDefault()` 阻断，而是在非 COMPOSING 状态下直接发送 `\r` |
| 3 | **Backspace 从同步改为 diff 驱动** | `beforeinput` 不再拦截 `deleteContentBackward`，让浏览器自然处理，由 150ms debounce 后的 diff 统一发送 |
| 4 | **compositionend 不再全量发送 textarea.value** | 改为进入 BUFFERING 状态，150ms 后通过 `_computeDiff()` 与 snapshot 比较，只发增量 |
| 5 | **Tab 后 resetSnapshot()** | `sendKey()` 在发送 `\t`/`\r`/`\x1b\r` 后调用 `resetSnapshot()`，解决 Tab 补全后 sentBuffer 不同步的问题 |
| 6 | **蓝牙键盘 Ctrl+key 支持** | keydown 新增 `e.ctrlKey` 检测，所有 Ctrl+A-Z 直接发送对应控制字符 |
| 7 | **AbortController 清理事件监听** | 每次 session 切换时 `destroy()` 通过 AbortController 移除所有事件监听器，防止监听器累积 |
| 8 | **快捷栏标签改为 Enter（发 \r）** | 从 v2 的 NL/\x1b\r 改为 Enter/\r，语义正确 |
| 9 | **保留 v2 的 6 个 Ctrl 按钮** | ^D/^Z/^A/^E/^L/^R 全部保留 |
| 10 | **滚动模式保留输入框** | `adjustQuickBarPosition()` 去除了 `!_inScrollMode` 条件，滚动历史时输入框始终可见 |
| 11 | **inputmode="text" 保留** | 从 v2 继承 |
| 12 | **方向键标签改为英文** | 从 v2 的 Unicode 箭头（←→↑↓）改回英文（Left/Right/Up/Down），⇧Tab 改为 S-Tab |
| 13 | **Buffering 时按特殊键先 flush** | Enter/Tab/Backspace/Ctrl+key 在 BUFFERING 状态下先清空 buffer 再发送，防止丢字 |

**v1/v2 三大痛点修复状态**：

| 痛点 | v3 修复状态 | 说明 |
|------|------------|------|
| 软键盘 Enter 被禁用 | **已修复** | `_onBeforeInput` 在非 COMPOSING 状态下发送 `\r`，并先 flush 未发送的 buffer |
| Tab 补全后 sentBuffer 不同步 | **已修复** | `sendKey()` 在 Tab/Enter 后调用 `resetSnapshot()` |
| compositionend 发送全量 textarea | **已修复** | compositionend 只进入 BUFFERING，150ms 后 diff 发送增量 |

---

## 1. 十项评分（v1 vs v2 vs v3 对比）

### 1.1 英文输入流畅度 -- 7.5/10（v1: 7, v2: 7, +0.5）

**提分原因**：150ms debounce buffer 替代了逐字符即时发送 + 800ms resetTimer。好处有两个：

1. **不再有 800ms 闪烁**。v1/v2 的 `scheduleReset()` 在停顿 800ms 后清空 textarea 和 sentBuffer，输入框会突然变空。v3 用 snapshot 机制，textarea.value 在 debounce flush 后保留（`this.snapshot = this.textarea.value`），直到 Enter/Tab 才 reset。输入框内容更稳定。

2. **autocomplete 替换更稳定**。150ms 窗口让 iOS 联想替换有时间完成，不会在替换进行到一半时就发送部分内容。

**扣分点**：150ms 是一个可感知的延迟。在 Tailscale 局域网内（网络延迟 < 5ms），v1/v2 的逐字符发送让终端回显几乎是即时的。v3 每个字符要等 150ms 才发出去，快速打字时不会感知（因为每次按键都重置 debounce，实际上是最后一个字符后 150ms 才 flush），但**打单个字符然后等待**（比如在 vim 里按 `j` 移动光标）会有 150ms 的延迟。对终端操作来说，150ms 在边界上——不算慢，但比逐字符发送能感觉到差异。

这是一个权衡：稳定性提升 vs 即时性轻微下降。对大多数移动端使用场景（输入命令），150ms 可以接受。但对交互式程序（vim、less），这个延迟会影响手感。

### 1.2 中文输入体验 -- 8/10（v1: 6, v2: 6, +2）

**大幅提分原因**：v3 的 compositionend 处理从根本上修复了 v1/v2 的问题。

v1/v2 的做法：compositionend 直接发送 `overlayInput.value`（textarea 全量内容）。如果 textarea 里残留了之前的英文字符，会重复发送。

v3 的做法：compositionend 只是把状态从 COMPOSING 切换到 BUFFERING，等 150ms 后通过 `_computeDiff()` 计算 snapshot 和当前 value 的差异，只发送增量。这意味着：

1. **不再重复发送 textarea 残留内容**——diff 只关心"上次 flush 之后新增了什么"。
2. **英文切中文的边界状态安全了**——先打英文 "abc"，debounce flush 后 snapshot = "abc"，然后切中文输入"你好"，compositionend 后 textarea = "abc你好"，diff = "你好"，只发增量。
3. **连续中文输入更流畅**——每次 compositionend 进入 BUFFERING，如果 150ms 内又开始新的 composition，`_onCompositionStart` 会先 flush 上一个，再进入 COMPOSING。逻辑严谨。

**扣分点**：compositionend 后的 150ms 等待意味着中文每个词组确认后有 150ms 才显示在终端上。对于快速连续输入多个词组的场景（比如"修复登录页面的样式问题"），每个词组之间都有 150ms 的间隙。体感上每个词组会比 v1/v2 稍慢一点出现在终端（v1/v2 的 compositionend 是即时发送的，虽然有重复风险）。

### 1.3 特殊键响应 -- 9/10（v1: 5, v2: 6, +3）

**这是 v3 最大的突破。**

软键盘 Enter 恢复工作了。`_onBeforeInput` 检测到 `insertParagraph`/`insertLineBreak` 时，只要当前不在 COMPOSING 状态，就直接发送 `\r`。这意味着：

1. **打完命令直接按键盘 Return——一气呵成**。不用再移手指去找快捷栏按钮。
2. **打字 -> 按回车**这条核心操作链路完整了。这是 v1/v2 最大的体验瓶颈，v3 彻底解决。
3. **Enter 前先 flush buffer**——如果用户打字很快、还有未发送的 buffer 内容，Enter 会先 flush 再发 `\r`，确保命令完整执行。

**IME Enter vs 终端 Enter 的歧义问题**：v1/v2 禁用软键盘 Enter 的理由是"中文输入法确认候选词也触发 Enter，无法区分"。v3 的解法是**利用 COMPOSING 状态**：composition 活跃时不处理 Enter（`if (this.state === 'COMPOSING') return`），只有非 composing 时才发送 `\r`。这在大多数场景下是正确的——iOS 的 compositionstart 在进入拼音编辑时触发，compositionend 在选定候选词后触发，选词过程中的 Enter/确认走的是 composition 流程而非 insertParagraph。

**潜在风险**：某些第三方输入法（如搜狗）在 composition 结束后**同一事件周期内**触发 compositionend + insertParagraph，这时 state 已经不是 COMPOSING（compositionend 把它切到了 BUFFERING），insertParagraph 可能被当成终端 Enter 处理。不过这是极端边界 case，大多数主流输入法（iOS 原生拼音、搜狗）的 compositionend 事件后不会紧接着触发 insertParagraph。减去 1 分留给这个理论风险。

Tab 补全后 `resetSnapshot()` 修复了 v1/v2 的第二大痛点。蓝牙键盘 Ctrl+A-Z 全部可用。Enter 按钮标签改为 "Enter"，语义清晰。

### 1.4 粘贴体验 -- 7.5/10（v1: 7, v2: 7, +0.5）

**提分原因**：粘贴走 diff 模型时，150ms debounce 给了 iOS 粘贴动画时间完成。v1/v2 的即时 diff 可能在粘贴过程中（iOS 有时分多步写入 textarea）捕获到中间状态。v3 等 150ms 后一次性 diff，粘贴完整性更好。

Paste 按钮逻辑不变——直接 wsSend，不走 InputController。

**仍有的问题**：粘贴多行文本时，每个 `\n` 被 tmux 解释为回车执行，这不是前端能解决的问题。

### 1.5 输入框可见性 -- 7/10（v1: 6, v2: 6, +1）

**提分原因**：

1. **滚动模式下输入框不再消失**。v1/v2 进入滚动模式时隐藏输入框，v3 的 `adjustQuickBarPosition()` 去除了 `!_inScrollMode` 条件判断，滚动历史时仍能看到输入框并打字。这对"一边查看历史输出一边输入新命令"的场景很实用。

2. **800ms 闪烁消除**。v1/v2 的 resetTimer 800ms 清空 textarea 导致输入框闪烁。v3 只在 Enter/Tab 时 resetSnapshot()，正常打字过程中 textarea 内容稳定存在。

**仍有的问题**：输入框的"中转站"定位没变——内容同时出现在输入框和终端，用户仍需要知道"看终端不看输入框"。但至少不会突然闪烁消失了。

### 1.6 快捷键栏 -- 7/10（v1: 7, v2: 7, 不变）

**改善的方面**：

1. Enter 按钮标签从 "NL" 改为 "Enter"，语义清晰。发送序列从 `\x1b\r` 改为 `\r`——语义正确（`\x1b\r` 在某些程序中被解析为 Alt+Enter）。
2. 保留了 v2 新增的 ^D/^Z/^A/^E/^L/^R 六个 Ctrl 键。
3. `sendKey()` 增加了 buffer flush + resetSnapshot 逻辑——按 Enter/Tab 前先发送未完成的输入。

**恶化的方面**：

1. **方向键标签从 Unicode 箭头改回英文单词**。v2 的 ←→↑↓ 比 v3 的 Left/Right/Up/Down 更紧凑、更直觉。英文标签占用更多水平空间，加剧了快捷栏拥挤问题。"Left" 5 个字母 vs "←" 1 个字符——面积差 5 倍。
2. ⇧Tab 改为 "S-Tab"——比 Unicode 符号不直觉，对非程序员用户来说 "S-Tab" 不如 "⇧Tab" 一目了然。
3. 按钮总数仍然是 22 个（16 个键 + Select + Done + Paste + 相机 + Debug），一屏放不下。

**关键问题**：v3 恢复了软键盘 Enter 后，快捷栏的 Enter 按钮变得冗余——用户可以直接按键盘上的 Return 键了。Enter 按钮仍有价值（万一在某些 IME 场景下软键盘 Enter 被吞，还有 fallback），但不再是必须品。可以考虑把它移到靠后位置，把更常用的操作（Tab、^C）放到最前面。

功能保持 + 标签退步 + Enter 冗余新问题，综合不变。

### 1.7 键盘与滚动冲突 -- 8.5/10（v1: 8, v2: 8, +0.5）

**提分原因**：滚动模式下保留输入框和快捷栏。v1/v2 进入滚动模式时输入框消失，用户如果在查看历史时想打字，需要先退出滚动模式。v3 滚动时输入框始终可见，无缝衔接。

其余触摸滚动、re-focus、CSS 防弹簧等处理不变，仍是整个系统最稳定的部分。

### 1.8 输入延迟感 -- 6.5/10（v1: 7, v2: 7, -0.5）

**扣分原因**：150ms debounce 引入了可感知的延迟。

v1/v2 是逐字符即时发送——按下 "g"，WebSocket 立刻发出，终端在 ~10ms 内回显。整个链路延迟 = 网络往返时间。

v3 是 buffer 150ms 后批量发送——按下 "g"，等 150ms，然后发出。终端回显延迟 = 150ms + 网络往返。在 Tailscale 局域网内，总延迟从 ~10ms 变成 ~160ms。

160ms 在大多数打字场景下不明显（因为连续打字时 buffer 不断重置，实际上是最后一个字符后 150ms 才发出，一批字符一起到达终端）。但在以下场景中会有感知：

- **vim/less 单键操作**：按 `j` 等 150ms 才移动光标。
- **交互式补全提示**：打一个字符后等待 shell 的补全建议，会比 v1/v2 晚 150ms 出现。
- **连续快速命令**：输入 `y` 确认 prompt 时，150ms 的等待让人觉得"卡了一下"。

这是 v3 架构的核心权衡。150ms 值选得不算差——50ms 可能不够让 iOS 联想完成替换，300ms 用户肯定能感知到延迟。150ms 是中间值，但对终端这种需要即时反馈的场景来说，还是偏高了。建议考虑降到 80-100ms——iOS 联想替换通常在 50-80ms 内完成，100ms 的 buffer 足以覆盖。

### 1.9 自动纠正干扰 -- 8/10（v1: 8, v2: 8, 不变）

textarea 的 `autocorrect="off"` + `inputmode="text"` 不变。v3 的 debounce buffer 对自动纠正干扰没有额外影响——iOS 的联想替换仍然可能出现（`autocorrect` 在部分 iOS 版本上不被完全尊重），diff 模型在 flush 时正确处理替换（发 backspace + 新内容），和 v1/v2 行为一致。

首字母自动大写的问题仍存在——`autocapitalize="off"` 在某些 iOS 版本上不生效。

### 1.10 整体打字满意度 -- 8/10（v1: 6, v2: 6, +2）

**v3 做到了 v1 和 v2 评审里反复强调的那件事：恢复软键盘 Enter。**

"打字 -> 按回车执行"这条核心链路终于完整了。不用再"打字 -> 移手指到快捷栏 -> 找按钮 -> 点击"。这一个改动就把整体满意度从 6 拉到 8。

架构重写为 InputController 类 + 状态机也让代码更可维护——事件监听器不再散落在全局作用域，session 切换时通过 AbortController 清理干净。compositionend 改为 diff 驱动消除了输入法边界的重复发送问题。Tab 后 resetSnapshot 解决了补全后继续输入乱码的隐患。

扣掉的 2 分给：
1. 150ms debounce 带来的延迟感（-1）——交互式程序体验不如逐字符发送
2. 快捷栏标签退步（方向键改回英文单词）+ 按钮仍然过多（-0.5）
3. 中文输入法边界的理论风险（compositionend + insertParagraph 同帧触发）（-0.5）

---

## 2. 真实场景模拟（A-I 复测 + J/K 新增）

### 场景 A：输入 "git push origin main" + Enter（复测）

**v3 变化**：

1. 逐字输入 "g" "i" "t" " " "p" "u" "s" "h" " " "o" "r" "i" "g" "i" "n" " " "m" "a" "i" "n"
2. 每次按键触发 input -> `_startBuffer()` 重置 150ms 定时器
3. 快速打字时 buffer 不断延期，实际在最后一个字母 "n" 之后 150ms 才 flush——所有字符一次性通过 diff 发出
4. **按键盘 Return 键** -> `_onBeforeInput` 捕获 `insertParagraph` -> 不在 COMPOSING 状态 -> **先 flush 未发送的 buffer** -> 发送 `\r`
5. 命令执行

**用户感受**：流畅。打字 -> 按 Return -> 命令执行。一气呵成，和原生终端 app 的体验一致。v1 的"恼火"、v2 的"无奈"不复存在。唯一的细微差异是打完最后一个字母到终端显示之间有 ~150ms 的等待（因为 buffer 还没 flush），但按 Return 时会强制 flush，所以最终回显是及时的。

**对比 v1/v2**：从"两步操作"变回"一步操作"。体验质变。

### 场景 B：输入中文 "修复登录页面的样式问题"（复测）

**v3 变化**：

1. 切中文输入法 -> 输入 "xiufu" -> compositionstart -> state = COMPOSING
2. 选择"修复" -> compositionend -> state = BUFFERING（不再直接发送 overlayInput.value）
3. 150ms 后 `_flush()` -> `_computeDiff()` 计算 snapshot（空串）和 textarea.value（"修复"）的差异 -> 发送 "修复"
4. snapshot = "修复"
5. 继续输入 "denglu" -> compositionstart -> COMPOSING -> 选择"登录" -> compositionend -> BUFFERING
6. 150ms 后 diff：snapshot = "修复"，value = "修复登录" -> 发送 "登录"
7. 重复直到完成
8. **按 Return** -> 发送 `\r` -> 命令执行

**用户感受**：中文输入流畅度明显提升。每个词组确认后有 ~150ms 的延迟才显示在终端（比 v1/v2 的即时发送稍慢），但换来的是**不会重复发送**。v1/v2 的 textarea 闪烁问题也消失了。

最重要的是——最后可以直接按 Return 了。v1/v2 的中文输入完成后还要去找 NL 按钮，现在不用了。

### 场景 C：输入 "th" 后点击联想建议 "the"（复测）

**v3 变化**：

1. 输入 "t" -> input -> BUFFERING（150ms 定时器启动）
2. 输入 "h"（在 150ms 内）-> input -> BUFFERING（定时器重置）
3. 150ms 后 flush -> diff: snapshot="" vs value="th" -> 发送 "th"，snapshot = "th"
4. 点击联想栏 "the" -> iOS 替换 textarea.value 为 "the" -> input -> BUFFERING
5. 150ms 后 flush -> diff: snapshot="th" vs value="the" -> commonLen=2, backspaces=0, newText="e" -> 发送 "e"

**用户感受**：和 v1/v2 一样完美。150ms buffer 反而更稳——iOS 联想替换有时分两步完成（先删后写），buffer 等它完成后再 diff，避免了中间态。

**但注意一个变化**：v1/v2 打 "t" 后立刻显示在终端（逐字符发送），v3 打 "t" 后要等 150ms。如果用户打 "t" 后 150ms 内就点了联想 "the"，可能出现 "t" 还没发出去就被替换为 "the" 的情况。此时 flush 只发 "the"（diff: snapshot="" vs "the"），没问题。但终端显示会是"突然出现 the"而不是"先出现 t 再补全为 the"。体验上略有不同但不影响正确性。

### 场景 D：快速输入 "npm install express ws node-pty"（复测）

**v3 变化**：

1. 快速连续打字，每次按键重置 150ms buffer
2. 在打字间隙（手指从一个键移到下一个键的时间 < 150ms），buffer 不会 flush
3. 如果打字中途有 > 150ms 的停顿（比如想下一个字母），buffer flush 一次，发送之前积累的字符
4. 打完后按 Return -> flush + `\r`

**用户感受**：和 v1/v2 基本一致。快速打字时 buffer 起到了"攒批"的效果——不是每个字符一条 WebSocket 消息，而是积累后一次性发送。这对 WebSocket 消息量有好处（减少消息数），但终端回显会"一批一批"出现而非逐字符出现。在低延迟网络下差异不大，但视觉上能注意到终端上的字是"跳着"出现的。

打完后按 Return 直接执行。不用找按钮了。

### 场景 E：粘贴一个 URL（复测）

**v3 变化**：

1. iOS 原生粘贴 -> textarea.value 一次性变为 URL -> input -> BUFFERING
2. 150ms 后 flush -> diff: snapshot="" vs URL -> 发送整个 URL

**用户感受**：和 v1/v2 一致。iOS 粘贴有时分步写入 textarea（先清空再写入），150ms buffer 等它完成后再 diff，比 v1/v2 的即时 diff 更安全。Paste 按钮仍走 wsSend 直连，不受 buffer 影响。

### 场景 F：按 Tab 触发补全，然后继续输入（复测）

**v3 变化**：

1. 输入 "serv" -> buffer -> flush -> 发送 "serv"，snapshot = "serv"
2. 按快捷栏 Tab -> `sendKey('\t')` -> **先 flush 未发送的 buffer**（如果有的话）-> wsSend('\t') -> **resetSnapshot()**
3. snapshot = ""，textarea.value = ""
4. 远端 shell 补全为 "server.js"（终端显示）
5. 继续输入 " --port 8022"
6. input -> BUFFERING -> 150ms 后 flush -> diff: snapshot="" vs " --port 8022" -> 发送 " --port 8022"

**用户感受**：v1/v2 的核心问题修复了。Tab 后 `resetSnapshot()` 清空了 snapshot 和 textarea，后续输入基于干净的状态开始。不会出现 sentBuffer 和终端不一致的问题。

Tab 补全后按 Backspace 也安全了——snapshot 是空的，textarea 也是空的，Backspace 通过 diff 发送 `\x7f`，不会基于错误的 sentBuffer 计算。

### 场景 G：按 ^D 退出（复测）

**v3 变化**：和 v2 相同。^D 按钮仍在快捷栏，sendKey('\x04')，功能正确。

**新增的好处**：如果外接蓝牙键盘，可以直接按 Ctrl+D——v3 的 `_onKeydown` 新增了 `e.ctrlKey` 检测，所有 Ctrl+A-Z 都能用物理按键发送。不再只能通过快捷栏。

### 场景 H：按 ^L 清屏后继续输入（复测）

**v3 变化**：^L 按钮功能不变。`sendKey()` 里先 flush buffer 再发送，所以清屏前的未完成输入不会丢失。

### 场景 I：快速输入后立即按 Enter（复测）

**v3 变化——场景完全改变**：

1. 快速输入 "ls -la" -> 每次按键 BUFFERING，buffer 不断延期
2. 立即按键盘 Return -> `_onBeforeInput` 捕获 insertParagraph -> **先 flush 未发送的 buffer**（"ls -la"）-> **发送 `\r`** -> resetSnapshot
3. 终端收到 "ls -la\r"，命令执行

**用户感受**：完美。这是 v1/v2 最痛苦的场景（"按了 Return 但什么都没发生"），v3 完全解决。而且先 flush 再发 Enter 的顺序保证了命令完整性——不会出现先发回车再发命令的乱序。

### 场景 J（新）：连续删除一整行（按住 Backspace）

**操作过程**：

1. 输入 "some-long-command --with-many-flags"（35 个字符）
2. buffer flush 后 snapshot = 完整命令
3. 按住 Backspace 不放 -> iOS 开始连续触发 keydown(Backspace)

**分析 v3 的处理**：

v3 的 Backspace 在 keydown 中处理（`e.keyCode !== 229` 条件通过时）：
- `e.preventDefault()`
- 如果在 BUFFERING 状态先 flush
- `this.send('\x7f')` 直接发送一个 DEL
- `this.snapshot = this.snapshot.slice(0, -1)`
- `this.textarea.value = this.textarea.value.slice(0, -1)`
- `this._keydownHandled = true`

每个 Backspace 按键触发一个 DEL，不走 buffer——**Backspace 是即时发送的**（和 Enter/Tab 一样绕过 debounce）。这意味着按住 Backspace 时，每个重复按键都立刻发送 `\x7f`，终端逐字符删除。

**但还有第二条路径**：软键盘的 Backspace 可能报 `keyCode === 229`（keydown 里的条件 `e.keyCode !== 229` 不通过），此时 keydown 不处理，也不设 `_keydownHandled`。浏览器正常删除 textarea 内容，触发 input 事件，进入 BUFFERING。150ms 后 diff 发现 textarea 变短了，发送 backspace。

**用户感受**：

- **物理键盘按住 Backspace**：即时逐字符删除，每个 DEL 立刻发送。体验和 v1/v2 一致，流畅无延迟。
- **软键盘按住 Backspace**：取决于 iOS 是否报 keyCode=229。
  - 如果 iOS 报 key="Backspace" + keyCode=8：走 keydown 路径，即时删除，无延迟。
  - 如果 iOS 报 keyCode=229：走 buffer 路径，每 150ms 批量删除。用户会看到终端"顿一下删几个字"而非"连续丝滑删除"。iOS Safari 在非 IME 状态下通常报 key="Backspace" + keyCode=8，所以大多数情况走即时路径。但在某些 IME 刚切换的瞬间可能报 229。

**总结**：大多数情况下连续删除是即时的，边界 case 下可能有 150ms 的顿挫。整体体验可接受。

### 场景 K（新）：外接蓝牙键盘 Ctrl+C

**操作过程**：

1. 连接蓝牙键盘
2. 终端正在运行一个长任务
3. 按 Ctrl+C

**v3 处理**：

1. keydown 触发 -> `e.ctrlKey = true, e.key = 'c'`
2. 进入新增的 Ctrl+key 检测逻辑（第 1321-1334 行）
3. `e.key.length === 1` -> `code = 'c'.charCodeAt(0) = 99` -> 在 97-122 范围内
4. `e.preventDefault()`
5. 如果 BUFFERING 状态先 flush
6. `ctrlChar = String.fromCharCode(99 - 96) = '\x03'`（ETX，即 Ctrl+C）
7. `this.send('\x03')` -> 终端收到 SIGINT -> 任务中断

**用户感受**：完美。v1/v2 没有 `e.ctrlKey` 处理，蓝牙键盘按 Ctrl+C 什么都不发生。v3 支持所有 Ctrl+A-Z（26 个组合），不仅是 Ctrl+C。这意味着蓝牙键盘用户可以用 Ctrl+D 退出、Ctrl+A 跳行首、Ctrl+L 清屏、Ctrl+R 反向搜索——完整的终端键盘体验。

还测试 Ctrl+W（删除前一个单词）：`code = 'w'.charCodeAt(0) = 119`，`ctrlChar = String.fromCharCode(119 - 96) = '\x17'`。正确，shell 收到 `\x17` 会删除光标前的一个单词。Ctrl+U（删除到行首）：`'\x15'`。也正确。

**v1/v2 评审里指出的"缺少 ^W 和 ^U"和"蓝牙键盘 Ctrl 不工作"两个问题，v3 一举全部解决。**

---

## 3. v3 架构评价

### 3.1 InputController 类 + 状态机

v1/v2 的输入逻辑散落在全局作用域：`sentBuffer`、`resetTimer`、`justFinishedComposition`、`keydownHandled` 等变量和 `compositionstart`/`compositionend`/`beforeinput`/`input`/`keydown` 五个事件监听器互相耦合。session 切换时事件监听器不清理，可能累积。

v3 封装为 `InputController` 类：
- 状态（snapshot、state、bufferTimer）内聚在实例中
- 事件监听器通过 `AbortController` 绑定，`destroy()` 一键清理
- 四状态机（IDLE -> COMPOSING -> BUFFERING -> FLUSHING）让逻辑流清晰可追踪

这是正确的工程方向。代码可维护性和可测试性大幅提升。

### 3.2 debounce buffer 的取舍

150ms debounce 是 v3 最核心也最有争议的决策。

**收益**：
- 消除 autocomplete 竞态条件（iOS 联想替换在 buffer 内完成后再 diff）
- 消除 800ms resetTimer 的突然清空
- 统一了中文/英文/联想/粘贴的处理路径（全部走 diff）
- 减少 WebSocket 消息量（攒批发送）

**代价**：
- 所有常规输入（非 Enter/Tab/Backspace）延迟 150ms
- 交互式程序（vim、less）的即时反馈变差
- 终端字符"跳着出现"而非逐字符出现

建议：考虑将 BUFFER_MS 设为可配置项（默认 150ms），高级用户可以通过 URL 参数或设置面板降低到 50-80ms。

### 3.3 COMPOSING 状态下的 Enter 安全性

v3 用 COMPOSING 状态区分"IME 确认"和"终端 Enter"。核心假设是：iOS 的 insertParagraph 事件不会在 COMPOSING 状态（compositionstart 到 compositionend 之间）触发。

这个假设在 iOS Safari 上基本成立——选择候选词走的是 composition 流程，不触发 insertParagraph。但需要注意：

1. **某些第三方输入法**可能在 compositionend 同一事件循环内触发 insertParagraph。v3 的 compositionend 把 state 从 COMPOSING 改为 BUFFERING，如果紧接着的 insertParagraph 到达时 state 已经是 BUFFERING，会被当作终端 Enter 处理，意外发送 `\r`。
2. **iOS 15+ 的"实况文本"**等系统级输入可能有非标准的事件序列。

实际风险较低，但建议在 compositionend 后增加一个短暂的防抖（比如 50ms 内的 insertParagraph 不发送），进一步降低误触概率。

---

## 4. v1 vs v2 vs v3 评分对比

| 维度 | v1 | v2 | v3 | v2->v3 | 原因 |
|------|----|----|----|----|------|
| 英文输入流畅度 | 7 | 7 | 7.5 | +0.5 | 消除 800ms 闪烁，autocomplete 更稳 |
| 中文输入体验 | 6 | 6 | 8 | +2 | compositionend 改为 diff 驱动，不再重复发送 |
| 特殊键响应 | 5 | 6 | 9 | +3 | **软键盘 Enter 恢复** + Ctrl+key 蓝牙支持 |
| 粘贴体验 | 7 | 7 | 7.5 | +0.5 | 150ms buffer 让粘贴更完整 |
| 输入框可见性 | 6 | 6 | 7 | +1 | 滚动模式保留输入框 + 无 800ms 闪烁 |
| 快捷键栏 | 7 | 7 | 7 | -- | Enter 标签改善 vs 方向键标签退步 |
| 键盘与滚动冲突 | 8 | 8 | 8.5 | +0.5 | 滚动模式下输入框不消失 |
| 输入延迟感 | 7 | 7 | 6.5 | -0.5 | 150ms debounce 可感知 |
| 自动纠正干扰 | 8 | 8 | 8 | -- | 不变 |
| 整体打字满意度 | 6 | 6 | 8 | +2 | Enter 恢复 = 核心链路打通 |
| **综合** | **6.7** | **6.8** | **7.7** | **+0.9** | **架构级改善** |

---

## 5. 总结

### v3 做对了什么

1. **恢复软键盘 Enter**——v1 和 v2 评审里反复强调的第一优先级问题，终于解决。用 COMPOSING 状态区分 IME 确认和终端 Enter，方案简洁有效。这一个改动让综合分从 6.8 跳到 7.7。

2. **统一输入模型**——InputController 类 + 状态机替代散落的全局变量和事件监听器。compositionend 不再特殊处理（发 textarea 全量），而是走和英文输入一样的 diff 路径。代码从"三层拦截器各自为政"变成"一个状态机统一调度"，可维护性质变。

3. **修复 Tab 补全同步问题**——`sendKey()` 在 Tab/Enter 后 `resetSnapshot()`。简单但关键。

4. **蓝牙键盘 Ctrl+A-Z 支持**——一行 `e.ctrlKey` 检测 + 字符编码计算，解锁了 26 个 Ctrl 组合键。v2 评审里"缺少 ^W / ^U"和"蓝牙键盘 Ctrl 不工作"的两个问题一并解决。

5. **AbortController 清理**——session 切换不再累积事件监听器。这是 v1/v2 的隐性 bug（虽然不影响首次使用，但多次 connect/disconnect 后可能导致内存泄漏和重复处理）。

### v3 可以继续改进的

| 优先级 | 问题 | 建议 |
|--------|------|------|
| P1 | 150ms debounce 对交互式程序（vim、less）延迟偏高 | BUFFER_MS 降到 80-100ms，或对单字符输入走 fast path（50ms） |
| P1 | compositionend 后紧接的 insertParagraph 可能误触 Enter | compositionend 后 50ms 内屏蔽 insertParagraph |
| P2 | 方向键标签从 Unicode 箭头退步为英文单词 | 改回 ←→↑↓，节省空间 |
| P2 | 快捷栏 22 个按钮仍然过多 | Enter 按钮可降优先级（软键盘 Enter 已恢复），考虑分组/折叠 |
| P3 | 软键盘 Backspace keyCode=229 时走 buffer 路径有 150ms 延迟 | 在 beforeinput deleteContentBackward 中即时发送 DEL（恢复 v1/v2 行为） |
| P3 | CLAUDE.md 中 "Soft keyboard Enter is blocked (use NL quick-bar button)" 描述过时 | 更新为 "Soft keyboard Enter sends \r when not composing" |

### 三版评分趋势

```
v1 (6.7) ─── v2 (6.8) ─────── v3 (7.7)
              +0.1               +0.9
          （锦上添花）       （架构级重写）
```

v1 到 v2 是微调——改名、加按钮，没触及核心痛点。v2 到 v3 是重写——新架构、解决三大痛点、支持蓝牙键盘。评分趋势清晰反映了这一点：+0.1 vs +0.9。

### 对工程师的话

v3 是一次真正意义上的"做对了的重构"。架构从"打补丁"变成"重新设计"，解决了 v1 就存在的三个核心问题。特别是恢复软键盘 Enter——这件事看起来简单，但背后需要理解 iOS IME 事件模型、状态机设计、buffer flush 时序，才能在不引入 IME 误触的前提下安全恢复。

150ms debounce 是唯一的遗憾。如果能降到 80ms 或引入"单字符 fast path"，输入延迟感可以从 6.5 回到 7 甚至更高，综合分有望突破 8.0。

从 6.7 到 7.7，移动端输入体验从"能用但恼火"进入了"好用且可靠"的区间。
