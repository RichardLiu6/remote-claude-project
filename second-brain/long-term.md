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

## 移动端输入模型
- Diff-based：观察结果（textarea value diff）而非拦截事件
- 四层协作：keydown（物理键）→ beforeinput（软 Enter）→ input（diff 核心）→ compositionend（时间戳）
- 详见 skill `mobile-input-debug`
