# Long-term Notes

## 语音系统架构（03-07 重构）
- 标识符：CC session_id（替代 tmux session 名，支持任意环境）
- 双通道：voice-local-{id}（afplay 本地播放）+ voice-web-{id}（WS 广播到浏览器）
- 开关：统一 `/voice` skill（local/web/both/off），默认 both
- 链路：/voice 创建 flag → voice-inject.sh 检查 flag 注入指令 → CC 生成 tag → voice-push.sh 路由到 afplay / POST server
- session_id 通过 hook stdin JSON 获取，每次 UserPromptSubmit 写入 ~/.claude/current-session-id 供 skill 读取
- `/voice` 无参数 toggle：关→开用 tmux 检测默认通道（tmux=web, 非 tmux=local），开→关
- **不能默认 both**：local 通道的 afplay 始终在 Mac 执行，手机远端操作时 Mac 会无故出声
- [设计文档](../docs/plans/2026-03-07-voice-refactor-design.md)

## Claude Code 自动化（03-04 搭建）
- 2 hooks: PostToolUse `node --check` + PreToolUse 关键文件保护
- 2 skills: `mobile-input-debug`（IME 调试）+ `server-restart`（开发重启）
- 1 agent: `mobile-ux-reviewer`（移动端 UX 检查清单）
- 1 MCP: Playwright（浏览器自动化测试）

## 移动端触摸滚动（03-07 实现）
- 根因：xterm.js scrollback buffer 连 tmux 时永远为空（tmux 管自己的 buffer）
- 方案：`\x01scroll:up:N` / `down:N` / `exit` WebSocket 协议，server 端 `tmux copy-mode` + `send-keys -X scroll-up/down`
- 物理参数：Apple 原生 0.95/帧衰减，非线性加速 `pow(px/6, 1.6)`，40ms 节流
- 手势分流：短滑=滚动 / 长按=选中(待实现) / 点按=键盘
- 详见 skill `tmux-xterm-scroll`

## 移动端输入模型（03-07 v3 重写）
- v3 架构：InputController 状态机（IDLE→COMPOSING→BUFFERING→FLUSHING）
- 150ms 统一 debounce buffer 替代逐字符发送 + sentBuffer
- snapshot diff：compositionend 不再全量发送，只发增量
- AbortController 管理事件监听器，session 切换时一次性清理
- 评分趋势 6.7→6.8→7.7，核心改善：软 Enter 恢复、Tab 补全后同步、中文不重复
- 遗留：document 级 touch listener 泄漏（不在 InputController 管辖内）
- 详见 skill `mobile-input-debug`

## Agent Team 迭代模式（03-07 建立）
- 每版本 3 人团队：engineer（worktree 隔离）+ user（10 维评分）+ PM（RICE 分析）
- 反馈链：v(N) user/PM 反馈注入 v(N+1) engineer prompt
- iOS App 6 版本迭代：5.5→7.5→8.5→...
- Input 系统 3 版本迭代：6.7→6.8→7.7
- 详见 skill `agent-team-iteration`

## 多渠道消息 Agent（03-07 研究）
- OpenClaw 三层架构：Channel Adapter → Gateway → Agent Runtime
- 推荐方案：WeCom（企业微信）+ Lark（飞书）双通道
- LLM：Minimax API（api.minimax.io/v1，OpenAI 兼容，MiniMax-M2.5）
- iMessage 可行但受限（chat.db polling + AppleScript）
- [统一框架文档](../docs/unified-agent-framework.md)
