# Long-term Notes

## 语音系统架构
- Flag 文件 per-session 控制生成，broadcastVoice() 全 WS 客户端广播
- 非 tmux 环境直接 exit 0，不触发语音（#17 已完成）
- 链路：speaker 按钮 → flag 文件 → voice-inject.sh → CC 生成 tag → voice-push.sh → POST /voice-event → edge-tts → WS broadcast

## Claude Code 自动化（03-04 搭建）
- 2 hooks: PostToolUse `node --check` + PreToolUse 关键文件保护
- 2 skills: `mobile-input-debug`（IME 调试）+ `server-restart`（开发重启）
- 1 agent: `mobile-ux-reviewer`（移动端 UX 检查清单）
- 1 MCP: Playwright（浏览器自动化测试）

## 移动端输入模型
- Diff-based：观察结果（textarea value diff）而非拦截事件
- 四层协作：keydown（物理键）→ beforeinput（软 Enter）→ input（diff 核心）→ compositionend（时间戳）
- 详见 skill `mobile-input-debug`
