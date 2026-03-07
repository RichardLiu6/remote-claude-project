# Web Terminal 移动端输入体验评测 v1

> 评测对象：`public/index.html` 中的移动端输入系统
>
> 评测环境：iPhone Safari，iOS 英文键盘（联想/自动纠正开启），搜狗/原生拼音输入法
>
> 评测日期：2026-03-07

---

## 0. 输入系统架构速览

在打分之前先说清楚这套输入系统到底怎么工作的，不然后面的吐槽没有上下文。

**核心思路**：xterm.js 在移动端设置了 `disableStdin: true`，所有输入走一个透明的 `<textarea id="overlay-input">`。用户点终端区域 -> textarea 获得焦点 -> 键盘弹出 -> 按键事件被三层拦截器捕获 -> 通过 WebSocket 发送到 tmux。

**三层事件模型**：

| 层 | 事件 | 职责 |
|---|------|------|
| 1 | `keydown` | 处理已识别的物理按键（Enter/方向键/Tab/Esc/Backspace）。移动端大量按键报 `Unidentified` 或 keyCode=229，直接跳过 |
| 2 | `beforeinput` | 捕获 keydown 漏掉的软键盘操作：deleteContentBackward、insertParagraph/insertLineBreak。**重点：软键盘 Enter 在这里被彻底屏蔽** |
| 3 | `input` | 纯 diff 模型——对比 `sentBuffer` 和 `textarea.value`，计算增量发送。处理自动补全替换时的回退+重发 |

**IME 处理**：`compositionstart` 进入组合态（所有层跳过），`compositionend` 发送整个组合结果并重置状态。

**软键盘 Enter 被禁用**：这是整个系统最重要的设计决策。软键盘的 Enter 键完全不发送 `\r`，终端回车只能通过快捷栏的 NL 按钮（发送 `\x1b\r`）。

---

## 1. 十项评分

### 1.1 英文输入流畅度 — 7/10

**好的方面**：diff 模型工作原理简洁——每次 `input` 事件触发时，比较 `textarea.value` 和 `sentBuffer`，只发送增量部分。正常逐字打英文时，每个字符都能立即发送，延迟取决于 WebSocket 往返时间。800ms 后自动 `resetSentState()` 清空 textarea 和 sentBuffer，防止无限增长。

**不好的方面**：`sentBuffer` 的 800ms 重置窗口是个隐患。如果你打字速度刚好卡在一个节奏——打几个字、停一秒、再打几个字——在停顿超过 800ms 的那个瞬间，sentBuffer 被清空了但 textarea.value 也被清空了，视觉上输入框会闪一下。不影响功能，但心理上会觉得"咦，我刚打的字呢"。

另外，`keydown` 里对 `keyCode === 229` 且 key 是空白字符的情况做了特殊跳过（`_isWhitespaceKey`），这是为了防 iOS 中文 IME 的 Enter 误触。但这个判断对英文输入没影响，不扣分。

### 1.2 中文输入体验 — 6/10

**好的方面**：`compositionstart/compositionend` 的处理逻辑是正确的。进入组合态后三层拦截器全部跳过，直到 compositionend 才发送完整的组合结果。`justFinishedComposition` + `requestAnimationFrame` 防止了部分浏览器在 compositionend 后额外触发的 `input` 事件导致重复发送。

**问题一：compositionend 发送的是整个 textarea.value，不是组合文本**。看代码第 1184 行：
```javascript
const text = overlayInput.value;
if (text) wsSend(text);
```
如果你在一次 IME 会话中连续输入了两个中文词，第一个词 compositionend 后 resetSentState 清空了 textarea，第二个词开始前 textarea 是空的，所以不会重复——大多数情况没问题。但如果 800ms resetTimer 还没触发、用户在同一个 compositionend 周期内 textarea 里残留了之前的英文字符（比如先打了 "abc" 没发回车，又切中文打了"你好"），compositionend 会把 "abc你好" 全发出去，而 "abc" 之前已经通过 input 事件的 diff 发过了——**重复发送**。

**问题二：中文输入法切换瞬间的边界状态不可预测**。从英文切到中文，如果切换的那一刻 sentBuffer 里有内容且 textarea 也有内容，下一次 compositionend 可能会把残留内容一起发出去。

**问题三：候选词联想**。搜狗输入法的候选词选择有时会触发 `input` 事件而不走 composition 流程（比如滑动输入），这时候 diff 模型能兜底处理，但如果滑动输入触发了 textarea 内容的批量替换，回退逻辑会发一堆 `\x7f` 再重发——终端上可能看到闪烁。

### 1.3 特殊键响应 — 5/10

**核心问题：软键盘 Enter 被完全禁用了。**

这是我最想吐槽的一点。代码在 `beforeinput` 层拦截了 `insertParagraph` 和 `insertLineBreak`，直接 `e.preventDefault()` 加 `resetSentState()`。终端回车只能按快捷栏的 NL 按钮。

从开发者角度理解这个决策：iOS 中文输入法确认候选词时也会触发 Enter/insertParagraph，如果不区分"用户想发回车"和"用户在确认拼音"，就会在选字时意外发送回车。这个问题确实很难解决。

但从用户角度：**每次想按回车都要去点一个小按钮，太反人类了。** 特别是输入 `git push origin main` 这种纯英文命令，打完之后本能反应就是按键盘上的 Return 键，结果什么都没发生。你得把视线从键盘移到快捷栏，找到 NL 按钮，点一下。一天下来要多点几十次。

Tab 键响应正常——快捷栏按钮直接发 `\t`，没有歧义。^C 发 `\x03` 也没问题。Esc 发 `\x1b` 正常。方向键通过快捷栏按钮发送转义序列，没问题。

但物理键盘的 Enter 走 keydown 层的 `KEY_MAP['Enter']` 发 `\r` 是正常的——所以如果你外接蓝牙键盘，Enter 是好使的。**只有软键盘的 Enter 被禁了。** 这个体验断层很大。

### 1.4 粘贴体验 — 7/10

**两种粘贴方式**：

1. **Paste 按钮**（快捷栏）：调用 `GET /api/clipboard` 获取 Mac 端的 pbpaste 内容，直接通过 WebSocket 发送。这个体验很好——按一下 Paste，Mac 剪贴板的内容直接出现在终端里。按钮还有状态反馈（"..." -> "OK!" -> 恢复）。

2. **iOS 原生粘贴**：在 textarea 里长按粘贴。粘贴后内容进入 textarea.value，然后被 `input` 事件的 diff 逻辑捕获。如果粘贴的内容和 sentBuffer 没有公共前缀（正常情况下 sentBuffer 为空或已被 reset），会直接全量发送。

**问题**：如果粘贴一段很长的文本（比如一个多行脚本），WebSocket 会一次性发送整个文本。tmux 那边能不能正确处理取决于 pty 的缓冲区大小和 tmux 的 paste 设置。如果文本包含换行符，每个 `\n` 都会被 tmux 当成回车执行——这在粘贴多行命令时可能导致命令被逐行执行而不是作为整体粘贴。但这不是前端的锅，是 tmux 的行为。

另外 Paste 按钮获取的是 **Mac 端** 的剪贴板，不是手机端的。如果你想粘贴手机上复制的内容（比如微信里的一段话），得用 iOS 原生粘贴。两种粘贴源不同，用户需要知道区别。

### 1.5 输入框可见性 — 6/10

**键盘关闭时**：`overlay-input` 被设为 `display: none`（连接前）或 `left: -9999px; width: 1px; height: 1px; opacity: 0.01`（连接后、键盘关闭时）。完全不可见。用户不知道要在哪里打字——只知道"点终端区域就会弹键盘"。

**键盘打开时**：通过 `adjustQuickBarPosition()` 添加 `.input-visible` 类，输入框变为 `width: 100%; height: 36px; opacity: 1`，显示在快捷栏上方。有 placeholder "Type here..."。这时候是可见的，用户能看到自己在哪里输入。

**问题**：输入框显示的内容和终端显示的内容是割裂的。你在输入框里打字，但字符出现在终端的光标位置——两个地方。而且输入框里的内容会在 800ms 后被 resetSentState 清空，所以你看到输入框里的字会突然消失。这是 diff 模型的副作用：输入框只是一个"中转站"，不是真正的输入目标。

第一次用的人一定会困惑：到底该看输入框还是看终端？答案是看终端，输入框只是用来骗 iOS 弹出键盘的。但这个 mental model 不直觉。

### 1.6 快捷键栏 — 7/10

**按钮列表**：NL / Tab / Shift-Tab / 左 / 右 / 上 / 下 / ^C / Esc / `/` / Select / Done / Paste / 📷 / Debug

15 个按钮，功能覆盖面很全。`mousedown + preventDefault` 防止按钮点击导致 textarea 失去焦点（键盘收起），这个处理很精妙。水平滚动 `overflow-x: auto` 可以左右滑动查看更多按钮。

**位置**：通过 `visualViewport` API 精确计算键盘高度，快捷栏固定在键盘正上方。跟随键盘弹出/收起。Select 模式下键盘关闭但快捷栏仍然显示在屏幕底部。

**问题一**：15 个按钮太多了，一屏放不下，得滑动才能看到后面的 Paste/Upload/Debug。高频操作（NL、Tab、^C）放在最前面是对的，但 Paste 和 Upload 需要滑动才能看到，每次用都得滑一下。

**问题二**：NL 按钮的标签不直觉。"NL" 代表 Newline，但在终端场景下用户期望的是 "Enter" 或 "Return" 或至少 "⏎"。叫 NL 需要额外的学习成本。

**问题三**：按钮之间间距偏小（gap: 6px），在颠簸的地铁上可能误触相邻按钮。不过 min-height: 34px 的触摸目标大小是合理的。

### 1.7 键盘与滚动冲突 — 8/10

**做得好的地方**：这是整个输入系统里处理得最漂亮的部分。

触摸滚动通过 `touchstart/touchmove/touchend` 全局监听，发送 tmux copy-mode 滚动命令。滚动时 `_touchMoved` 标志为 true，touchend 时如果 `_keyboardOpen` 为 true 会重新 focus overlayInput——**键盘不会因为你滑了一下就收起来**。这个细节非常关键。

进入滚动模式（`_inScrollMode = true`）后，`adjustQuickBarPosition` 会隐藏输入框（但快捷栏保留），避免输入框遮挡终端内容。点击终端区域（非滑动）会发送 `\x01scroll:exit` 退出 copy-mode 并重新弹出输入框。

**CSS 层面**：`body { position: fixed; overscroll-behavior: none; }` 防止 iOS 橡皮筋回弹。`touch-action: none` 在 terminal-container 和 xterm 元素上设置，让 JS 全权接管触摸。`touch-action: manipulation` 在全局 `*` 上设置，禁止双击缩放。

**扣分点**：快捷栏自身的水平滚动和终端区域的垂直滚动有可能冲突。如果手指从快捷栏区域开始触摸然后垂直滑动，理论上 touchmove 会同时触发快捷栏和终端的滚动逻辑。不过实际上快捷栏高度只有 ~44px，冲突概率低。

### 1.8 输入延迟感 — 7/10

**链路分析**：按键 -> keydown/beforeinput/input 事件 -> wsSend() -> WebSocket -> server.js -> node-pty -> tmux -> pty 输出 -> node-pty onData -> WebSocket -> term.write()

在 Tailscale 局域网内（延迟通常 < 5ms），整个链路的往返时间大概在 10-30ms，人感觉不到明显延迟。

**但**：diff 模型在 `input` 事件中做字符串比较和计算，虽然计算量极小（O(n) 前缀匹配），但 JavaScript 的 GC 在密集输入时可能引入微小卡顿。加上 iOS Safari 的事件处理本身不如原生 app 快，快速连续打字时可能偶尔感觉到 1-2 帧的延迟。

**重要的是**：终端回显完全依赖远端。你打的每个字符都要走一圈网络才能在屏幕上显示。对比原生终端 app（本地 pty，字符直接写入渲染缓冲区），这是 Web Terminal 方案固有的延迟。在好的网络下可以接受，在高延迟网络下会明显感觉"字跟不上手"。

### 1.9 自动纠正干扰 — 8/10

textarea 设置了 `autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"`，理论上应该完全关闭 iOS 的自动纠正和联想。

**但实际上 iOS 不一定尊重这些属性**。部分 iOS 版本仍然会显示联想栏（QuickType bar），用户点击联想词时会触发 textarea 内容的批量替换。

好消息是 diff 模型的自动补全处理（代码 1256-1274 行）专门为这个场景设计：检测 `current` 不以 `sentBuffer` 开头时，找最长公共前缀，发送 backspace 删除差异部分，再发送新内容。这个逻辑是正确的。

**扣分点**：自动纠正虽然在 HTML 属性层面关闭了，但 `autocapitalize="off"` 在某些 iOS 版本上不生效。如果首字母被自动大写了，diff 模型不会发 backspace 修正——因为从它的角度看，用户就是打了个大写字母。对终端命令来说，`Git` 和 `git` 是完全不同的。

### 1.10 整体打字满意度 — 6/10

**对比 Termius / Blink Shell 等原生终端 App**：

| 维度 | Web Terminal | 原生 App |
|------|-------------|----------|
| Enter 键 | 需要按快捷栏 NL 按钮 | 键盘 Return 直接发送 |
| 输入延迟 | WebSocket 往返 | 本地 pty 或 SSH 直连 |
| IME 处理 | composition 事件 + diff 模型 | 系统原生 |
| 联想词 | diff 模型兜底，偶有闪烁 | 原生处理，无缝 |
| 粘贴 | 两种方式（Mac/本地） | 统一剪贴板 |
| 键盘工具栏 | 自建快捷栏，15 按钮 | 系统 inputAccessoryView |

最大的体验差距就是 **Enter 键被禁用**。这一条就能把满意度从 8 分拉到 6 分。其次是输入框的"中转站"心智模型不直觉。再次是中文输入的边界 case（切换输入法时的残留内容）。

在"能用"这个层面，这套系统是靠谱的。在"好用"这个层面，离原生 app 还有明显距离。

---

## 2. 真实场景模拟

### 场景 A：输入 "git push origin main" + Enter

**操作过程**：
1. 点击终端区域 -> `touchend` 触发 -> `overlayInput.focus()` -> 键盘弹出
2. `adjustQuickBarPosition()` 检测键盘高度 > 50px -> 显示快捷栏和输入框
3. 逐字输入 "g" "i" "t" " " "p" "u" "s" "h" " " "o" "r" "i" "g" "i" "n" " " "m" "a" "i" "n"
4. 每个字符触发 `input` 事件 -> `current.startsWith(sentBuffer)` 为 true -> 发送增量字符
5. **想按 Enter**——键盘上的 Return 键被 beforeinput 拦截（`insertParagraph` -> `preventDefault`）
6. 视线移到快捷栏 -> 找到 NL 按钮 -> 点击 -> 发送 `\x1b\r`

**用户感受**：前面打字都很顺畅，最后被 Enter 卡住那一下很恼火。特别是如果你已经习惯了键盘操作的肌肉记忆，手指按到 Return 键结果什么都没发生，要重新定位 NL 按钮。打一个简单的 git 命令变成了"打字 + 找按钮"两步操作。

### 场景 B：输入中文 "修复登录页面的样式问题"

**操作过程**：
1. 切换到中文输入法（拼音）
2. 输入 "xiufu" -> compositionstart 触发 -> `isComposing = true`
3. 键盘显示候选词：修复 / 修复了 / ...
4. 点击"修复" -> compositionend 触发 -> `isComposing = false`
5. `overlayInput.value` = "修复" -> `wsSend("修复")` -> `resetSentState()`
6. 继续输入 "denglu" -> compositionstart -> 选择"登录" -> compositionend -> 发送"登录"
7. 重复直到输入完整句子
8. 想确认/发送 -> 还是要按 NL 按钮

**用户感受**：中文输入的 composition 流程基本正确，每个词组都能正确发送。但有个微妙的问题——每次 compositionend 后 `resetSentState()` 清空了 textarea，输入框会闪一下空白。而且如果你打字很快，在上一个 compositionend 的 `requestAnimationFrame` 还没执行完时就开始下一个 composition，`justFinishedComposition` 标志可能还是 true，导致下一个 input 事件被误吞。概率很低但不是零。

### 场景 C：输入 "th" 后点击联想建议 "the"

**操作过程**：
1. 输入 "t" -> input 事件 -> sentBuffer = "t"，发送 "t"
2. 输入 "h" -> input 事件 -> sentBuffer = "th"，发送 "h"
3. 点击联想栏 "the" -> iOS 将 textarea.value 从 "th" 替换为 "the"
4. input 事件触发 -> `current = "the"`, `sentBuffer = "th"`
5. `current.startsWith(sentBuffer)` -> "the".startsWith("th") = **true**
6. `newChars = "the".slice(2) = "e"` -> 发送 "e"
7. sentBuffer = "the"

**用户感受**：完美。这是最常见的联想补全场景（追加字符），diff 模型处理得干净利落。终端上看到 "the" 完整出现，没有任何闪烁或多余字符。

**但如果联想建议是 "then"**：同理，发送 "en"，也没问题。

**如果联想建议是 "they"（替换了最后一个字符）**：
1. textarea.value 从 "th" 变成 "they"
2. `"they".startsWith("th")` = true -> 发送 "ey"
3. 终端显示 "they" 没问题——但实际上终端收到的是 "t" + "h" + "ey" = "they"，正确

**如果联想建议是完全不同的词（如 "that"）**：
1. textarea.value 从 "th" 变成 "that"
2. `"that".startsWith("th")` = false
3. 进入替换逻辑：commonLen = "th" vs "that" -> commonLen = 2（"th" 都匹配）
4. charsToDelete = 2 - 2 = 0，newPart = "that".slice(2) = "at"
5. 发送 "at"，终端显示 "that"

等一下——这有问题。sentBuffer = "th"，iOS 把 textarea 改成了 "that"。公共前缀是 "th"（2 个字符），所以 charsToDelete = 0，然后发送 "at"。终端收到的是 "t" + "h" + "at" = "that"。对了，没问题。但如果联想替换成 "this"：公共前缀是 "th"，charsToDelete = 0，newPart = "is"，终端收到 "this"。也对了。

**真正出问题的场景**：如果 iOS 联想把 "th" 整个替换成 "I"（一个字符）。公共前缀长度 = 0。charsToDelete = 2。发送两个 `\x7f`（退格），然后发送 "I"。终端上会看到先删掉 "th"，再出现 "I"。**视觉上会有一闪**——先退两格再打一个字母。在低延迟下用户可能注意不到，高延迟下会看到字符跳动。

### 场景 D：快速输入 "npm install express ws node-pty"

**操作过程**：
1. 快速连续按键 "n" "p" "m" " " "i" "n" "s" "t" "a" "l" "l" " " ...
2. 每次按键触发 keydown（大多数 keyCode=229，被跳过）+ input 事件
3. input 事件里 diff 模型逐字符发送
4. 800ms resetTimer 在打字间隙可能触发——但因为打字速度很快，每次 input 都会 `scheduleReset()` 重置定时器，所以不会在打字过程中 reset

**用户感受**：快速打字基本流畅。每个字符都通过 diff 单独发送，WebSocket 消息量比较大（每字符一条消息），但在局域网内不是问题。

**潜在问题**：如果 iOS 联想在你打 "instal" 时弹出 "install" 并且你手快点了一下，会触发替换逻辑。但因为 "install" 是 "instal" 的扩展（追加 "l"），`startsWith` 匹配成功，只发送追加的字符，不会出问题。

真正让人不爽的是打完整条命令后——**还是要去按 NL 按钮**。

### 场景 E：粘贴一个 URL

**方式一：iOS 原生粘贴**
1. 长按输入框 -> 粘贴菜单 -> 粘贴
2. textarea.value 从 "" 变成 "https://github.com/user/repo"
3. input 事件 -> sentBuffer = ""，current = URL
4. `current.startsWith(sentBuffer)` -> "https://...".startsWith("") = true（空字符串是任何字符串的前缀）
5. 发送整个 URL

**方式二：Paste 按钮**
1. 滑动快捷栏找到 Paste 按钮 -> 点击
2. `fetch('/api/clipboard')` -> 获取 Mac 剪贴板内容
3. `wsSend(text)` 直接发送

**用户感受**：两种方式都能工作。但方式一有个问题——如果粘贴前 sentBuffer 不为空（比如你已经打了 "cd " 想补一个路径），粘贴后 textarea.value = "cd https://..."，sentBuffer = "cd "。`startsWith` 匹配成功，发送 "https://..."。正确。但如果 iOS 粘贴替换了已有内容（某些情况下 textarea 的粘贴行为是替换选中文本），就走替换逻辑，多发几个退格。功能正确但可能有短暂闪烁。

### 场景 F：按 Tab 触发补全，然后继续输入

**操作过程**：
1. 输入 "serv" -> 通过 diff 模型发送
2. 按快捷栏 Tab 按钮 -> `sendKey('\t')` -> wsSend('\t') + overlayInput.focus()
3. tmux/shell 补全 "server.js"（由远端 shell 处理）
4. 终端显示 "server.js"——但输入框里仍然是 "serv"（sentBuffer = "serv"）
5. 继续输入 " --port 8022"
6. input 事件 -> current = "serv --port 8022"，sentBuffer = "serv"
7. `startsWith` 匹配成功 -> 发送 " --port 8022"

**用户感受**：Tab 补全本身是正确的——Tab 字符发到远端，shell 完成补全。但输入框和终端的内容出现了**不一致**：终端显示 "server.js"，输入框显示 "serv"。这是因为远端补全的结果不会回写到输入框。

更严重的问题：如果补全后用户按 Backspace 想删除补全结果的最后一个字符，keydown 捕获 Backspace -> `wsSend('\x7f')` -> 终端删掉 "s"（"server.j"），同时 `sentBuffer = sentBuffer.slice(0, -1)` = "ser"，`overlayInput.value = overlayInput.value.slice(0, -1)` = "ser"。但终端上是 "server.j"，输入框是 "ser"——**两边完全对不上了**。继续打字时 diff 模型会基于错误的 sentBuffer 计算增量，可能导致字符重复或丢失。

这是 diff 模型的一个本质缺陷：它假设 sentBuffer 和终端实际内容是同步的，但 Tab 补全、远端命令输出等都会破坏这个假设。800ms 的 resetTimer 能在停顿后恢复一致性，但在快速操作中（Tab 补全后立刻继续打字），这个时间窗口内的输入可能出错。

---

## 3. 总结与改进建议

### 最大的痛点（按严重程度排序）

| # | 痛点 | 影响 | 建议 |
|---|------|------|------|
| 1 | **软键盘 Enter 被完全禁用** | 每条命令都多一步操作，严重影响效率 | 考虑非 IME 状态下（英文键盘）恢复 Enter 功能；或检测当前无 composition 活跃时允许 Enter 发送 `\r` |
| 2 | **Tab 补全后 sentBuffer 与终端不同步** | 补全后继续输入可能乱码 | Tab 发送后立即 resetSentState()，强制重新同步 |
| 3 | **compositionend 发送 textarea 全量而非增量** | 输入法切换边界可能重复发送 | compositionend 中只发送 `e.data`（composition 产生的文本），不发送 `overlayInput.value` |
| 4 | **输入框"中转站"定位不直觉** | 新用户困惑 | 考虑让输入框始终可见且显示当前输入内容，或干脆隐藏输入框只保留终端显示 |
| 5 | **NL 按钮标签语义不清** | 用户不知道 NL 是什么 | 改为 "Enter" 或 "Return" 或 "⏎" |

### 这套系统做对了的事情

1. **diff 模型处理联想补全**——iOS 联想词替换是移动端终端输入最难处理的问题之一，用 sentBuffer + 公共前缀 + backspace 回退的方式解决，思路正确
2. **mousedown preventDefault 保持焦点**——快捷栏按钮不会导致键盘收起，这个细节非常重要
3. **滚动时保持键盘**——`_keyboardOpen` + touchend re-focus 的设计让滑动不会意外关闭键盘
4. **debug overlay**——有了事件调试面板，遇到输入异常时可以实时查看事件流，这对排查问题价值极大
5. **visualViewport 精确适配**——键盘高度计算准确，快捷栏定位正确，不会被键盘遮挡

### 最终评价

作为一个每天用手机操控 Claude Code 的人，这套输入系统在"能用"和"好用"之间。最核心的问题就是 Enter 键。如果能在非 IME 活跃状态下恢复软键盘 Enter 的功能，整体体验会有质的提升。其他问题（sentBuffer 同步、compositionend 全量发送）属于边界 case，日常使用中低概率遇到，但遇到了会很恼人。

| 维度 | 分数 |
|------|------|
| 英文输入流畅度 | 7/10 |
| 中文输入体验 | 6/10 |
| 特殊键响应 | 5/10 |
| 粘贴体验 | 7/10 |
| 输入框可见性 | 6/10 |
| 快捷键栏 | 7/10 |
| 键盘与滚动冲突 | 8/10 |
| 输入延迟感 | 7/10 |
| 自动纠正干扰 | 8/10 |
| 整体打字满意度 | 6/10 |
| **综合** | **6.7/10** |
