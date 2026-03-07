# iOS 原生 App 方案 — Claude Remote Terminal

> 替代 Web 终端（xterm.js），根治 iOS Safari 的 IME / 滚动 / 语音兼容性问题

## 动机：Web 终端的结构性痛点

| 问题 | 根因 | 现有 workaround | 原生 App 下 |
|------|------|-----------------|------------|
| IME 输入重复/丢字 | iOS Safari composition 事件时序非标准，xterm.js 未为移动端设计 | diff 模型（比较 textarea 前后值） | UITextView 原生输入，问题不存在 |
| 滚动/滑动冲突 | xterm.js canvas 设 `touch-action: none`，劫持所有触摸事件 | `touch-action: pan-y` override + Select mode overlay | 原生 ScrollView / SwiftTerm 内置滚动 |
| 键盘 quick-bar 定位 | visualViewport API 在 iOS 上行为不一致，键盘高度获取不可靠 | visualViewport.resize 监听 + padding 调整 | inputAccessoryView 系统级贴合 |
| 文本选择/复制 | canvas 不支持原生选择，需叠 div overlay | Select mode（抓终端 buffer 文本叠到 div） | 原生 UITextView 长按选择 |
| 语音播放 | iOS Safari autoplay 策略严格，需 silence.wav unlock hack | 用户首次交互时播放静音 WAV 解锁 AudioContext | AVAudioPlayer 原生权限，无限制 |
| iOS 版本升级破坏 | Safari 行为随 iOS 更新变化，hack 可能失效 | 每次 iOS 更新后排查修复 | UIKit/SwiftUI API 向后兼容性强 |

**核心结论**：Web 终端 index.html 中约 40% 的代码是 workaround。原生 App 下这些问题消失，不是"换一种方式实现"，而是问题本身不存在。

## 架构

```
┌─ iOS App (SwiftUI) ──────────────────────────┐
│                                              │
│  SessionPickerView                           │
│    └─ GET /api/sessions → 列表展示           │
│                                              │
│  TerminalView                                │
│    └─ SwiftTerm (TerminalView)               │
│       └─ WebSocket /ws?session=X             │
│       └─ ANSI 渲染、颜色、光标 ✅            │
│                                              │
│  InputAccessoryBar                           │
│    └─ Tab | ^C | Esc | ↑ | ↓                │
│    └─ inputAccessoryView 贴合键盘顶部        │
│                                              │
│  VoiceManager                                │
│    └─ AVAudioPlayer (TTS 播放)               │
│    └─ 监听 WS \x01voice: 控制帧             │
│    └─ POST /api/voice-toggle 开关            │
│                                              │
│  NotificationManager                         │
│    └─ UserNotifications (任务完成推送)         │
│                                              │
└──────────────────────────────────────────────┘
            │
            │ WebSocket + REST（协议完全复用）
            │
┌─ Mac server.js (零改动) ─────────────────────┐
│  Express + ws + node-pty + tmux              │
│  现有 API 全部兼容：                          │
│    GET  /api/sessions                        │
│    WS   /ws?session=X                        │
│    POST /voice-event                         │
│    GET  /api/voice-status                    │
│    POST /api/voice-toggle                    │
│    GET  /api/clipboard                       │
│    POST /api/upload                          │
└──────────────────────────────────────────────┘
```

**关键：server.js 一行不用改。** WebSocket 协议（文本透传 + `\x01resize:` 控制帧 + `\x01voice:` 推送）直接复用。

## 协议兼容性

### 现有 WebSocket 协议

```
客户端 → 服务端：
  普通文本    → pty.write(text)          # 键盘输入
  \x01resize:{"cols":80,"rows":24}      # 终端尺寸变化

服务端 → 客户端：
  普通文本    → 终端输出（ANSI 序列）     # pty.onData
  \x01voice:{"url":"/audio/xxx.mp3","text":"..."} # TTS 推送
```

### SwiftTerm 对接要点

- SwiftTerm 有 `TerminalView`（UIKit）和 `SwiftUITerminal`（SwiftUI）两种
- 需要自己实现 WebSocket 数据源，将 ws 收到的数据 feed 给 SwiftTerm 的 `terminal.feed(byteArray:)`
- SwiftTerm 的 `sizeChanged` 回调 → 发送 `\x01resize:` 给 server
- `\x01voice:` 控制帧需要在 ws.onMessage 中拦截，不传给 SwiftTerm

### 技术风险点

| 风险 | 影响 | 验证方式 |
|------|------|---------|
| SwiftTerm 渲染兼容性 | Claude Code 使用的 ANSI 序列（颜色、spinner、进度条）能否正确渲染 | 跑 SwiftTerm demo，连上现有 server.js 观察 |
| WebSocket 库选择 | 需要可靠的 iOS WebSocket 客户端 | URLSessionWebSocketTask（系统自带）或 Starscream |
| 键盘输入映射 | 特殊键（Ctrl+C、Tab、ESC、方向键）需要正确转为 ANSI escape 序列 | SwiftTerm 内置支持，但需确认和 tmux 的兼容性 |
| 后台保活 | App 切到后台时 WebSocket 可能断开 | 重连机制 + 断线提示 |

## 分阶段实施

### Phase 1：MVP（最小可用）

**目标**：能连上 tmux session，能打字，能看输出

- [ ] Xcode 项目搭建（SwiftUI）
- [ ] 集成 SwiftTerm
- [ ] WebSocket 连接（URLSessionWebSocketTask）
- [ ] Session 选择器（调用 GET /api/sessions）
- [ ] 基础键盘输入 → ws.send
- [ ] resize 事件 → `\x01resize:` 控制帧
- [ ] 断线重连

**验收标准**：用 App 连上现有 server.js，在 Claude Code session 里打字交互，ANSI 颜色正确

### Phase 2：输入增强

- [ ] inputAccessoryView 快捷键栏（Tab / ^C / Esc / ↑↓）
- [ ] 长按选择/复制终端文本
- [ ] 粘贴支持
- [ ] 剪贴板桥接（GET /api/clipboard）

### Phase 3：语音集成

- [ ] 监听 `\x01voice:` 控制帧
- [ ] AVAudioPlayer 播放 TTS 音频（从 server 下载 mp3）
- [ ] 语音开关按钮（POST /api/voice-toggle）
- [ ] 语音状态显示（GET /api/voice-status）

### Phase 4：体验打磨

- [ ] UserNotifications 任务完成推送
- [ ] 文件上传（相册/文件 → POST /api/upload）
- [ ] 深色/浅色主题
- [ ] Tailscale IP 配置页面
- [ ] App Icon

## 签名与分发

| 方案 | 费用 | 有效期 | 适合 |
|------|------|--------|------|
| 免费 Apple ID + Xcode 直装 | $0 | 7 天需重签 | 开发调试阶段 |
| Apple Developer Program | $99/年 | 1 年 | 长期个人使用（推荐） |
| TestFlight | 需开发者账号 | 90 天/build | 分享给他人测试 |

**推荐**：开发阶段用免费直装，确认好用后买 $99 开发者账号。

## 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI | 声明式 UI，现代 Apple 开发标准 |
| 终端渲染 | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Miguel de Icaza 维护，支持 xterm 兼容 |
| WebSocket | URLSessionWebSocketTask | 系统自带，无需三方依赖 |
| 音频播放 | AVFoundation | 系统自带 |
| 通知 | UserNotifications | 系统自带 |
| 网络发现 | Hardcoded Tailscale IP / mDNS | 初期手动配置，后续可加自动发现 |

## 与 Web 终端的关系

原生 App 和 Web 终端**可以共存**：
- 同一个 server.js 同时服务 Web 和 App 客户端
- Web 终端作为 fallback（其他设备、临时使用）
- App 作为主力日常使用工具

不需要废弃 Web 终端，但 App 成熟后，移动端输入相关的 hack 代码不再需要维护。
