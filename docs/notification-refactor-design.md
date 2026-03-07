# 通知 Hook 多环境适配方案

Date: 2026-03-07
Status: 设计中
Related: 语音重构 (#17/#18), [voice refactor design](plans/2026-03-07-voice-refactor-design.md)

## 现状问题

`notify.sh` 固定执行两件事：
1. `afplay Funk.aiff` — Mac 播放提示音
2. `terminal-notifier` — macOS 桌面弹通知，点击激活 Cursor 窗口

当用户通过手机远端使用 CC（Web Terminal → tmux）时：
- Mac 桌面弹了通知，但用户不在电脑前，看不到
- 手机端没有任何通知提示
- 用户不知道 CC 已停止等待输入，导致响应延迟

## 设计目标

根据使用环境将通知路由到正确的设备，复用语音重构中验证过的 hook-skill-bridge 模式。

## 通知通道

| 通道 | 实现方式 | 适用场景 |
|------|---------|---------|
| **local** | terminal-notifier + afplay（现有逻辑） | 电脑前使用 Cursor/Terminal |
| **web** | WS 推送到 Web Terminal → 浏览器 Notification API + 震动 | 手机远端使用 |
| **push** | 未来可选：iOS Push / Telegram Bot / Bark 等 | 手机不在 Web Terminal 时 |

## 方案：复用语音双通道模式

### Flag 文件
- `~/.claude/notify-local-{session_id}` — Mac 桌面通知
- `~/.claude/notify-web-{session_id}` — WS 推送到浏览器

### 开关
`/notify` skill（或复用 `/voice` 扩展为 `/mode`），参数同 voice：
- `/notify local` / `/notify web` / `/notify both` / `/notify off`
- 无参数 toggle

### notify.sh 改动
```
1. 从 stdin JSON 读 session_id
2. 检查 notify-local-{id} → 执行现有 terminal-notifier + afplay
3. 检查 notify-web-{id} → POST 到 server.js 新端点 /notify-event
4. 都没有 → 默认 local（通知不应该完全静默，和语音不同）
```

### server.js 新增
```
POST /notify-event
  → broadcastNotify(payload) — WS 推送 \x01notify:{...}
```

### index.html 新增
```
收到 \x01notify: 消息 →
  1. 浏览器 Notification API 弹通知（需用户授权）
  2. navigator.vibrate() 震动（仅 Android，iOS 不支持）
  3. 页面标题闪烁 "⚠ 需要操作"
  4. 可选：播放提示音（复用 voicePlayer）
```

## 与语音系统的区别

| 维度 | 语音 | 通知 |
|------|------|------|
| 默认行为 | 默认关闭 | 默认开启（local） |
| 无 flag 时 | 静默退出 | 仍然执行 local 通知 |
| 内容 | TTS 音频 | 短文本 + 提示音 |
| 频率 | 每次 Stop | 仅 Notification 事件 |

## 需要考虑的问题

1. **浏览器 Notification 权限**：首次需要用户点击授权，Web Terminal 可以在连接时提示
2. **默认通道**：通知和语音不同，不能默认关闭。建议无 flag 时 = local（向后兼容）
3. **是否合并语音和通知的开关**：可以做一个 `/mode` skill 统一管理，但增加复杂度。建议先独立，后续再考虑合并
4. **push 通道**：Bark（iOS 推送 app）是最轻量的方案，一个 URL 调用即可。但这是 V2 功能
5. **activate_cursor.sh**：Web 通道不需要激活 Cursor 窗口，local 通道保留

## 实现步骤

1. 改 notify.sh — 加 session_id 读取 + flag 检查 + web POST
2. server.js — 加 /notify-event 端点 + broadcastNotify()
3. index.html — 加 WS notify 消息处理 + Notification API
4. 新建 /notify skill
5. 真机验证
