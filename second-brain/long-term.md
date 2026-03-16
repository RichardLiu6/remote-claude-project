# Long-term Notes

## 语音系统架构（03-07 重构）
- 标识符：CC session_id（替代 tmux session 名，支持任意环境）
- 双通道：voice-local-{id}（afplay 本地播放）+ voice-web-{id}（WS 广播到浏览器）
- 开关：统一 `/voice` skill（local/web/both/off），默认 both
- 链路：/voice 创建 flag → voice-inject.sh 检查 flag 注入指令 → CC 生成 tag → voice-push.sh 路由到 afplay / POST server
- session_id 通过 hook stdin JSON 获取，每次 UserPromptSubmit 写入 ~/.claude/current-session-id 供 skill 读取
- `/voice` 无参数 toggle：关→开检查 `~/.claude/web-session-{id}` 标记（start-claude.sh 启动=web，否则=local），开→关
- **不能默认 both**：local 通道的 afplay 始终在 Mac 执行，手机远端操作时 Mac 会无故出声
- web session 注册链：start-claude.sh `export CLAUDE_VIA_WEB=1` → voice-inject.sh 检测后创建 `~/.claude/web-session-{sid}` → kill 时清理
- [设计文档](../docs/plans/2026-03-07-voice-refactor-design.md)

## Claude Code 自动化（03-07 更新）
- 4 hooks: PostToolUse `node --check`(.js) + `xcodebuild`(.swift) + PreToolUse 关键文件保护 + Stop `ios-app-test.sh`
- iOS App 测试链：编辑→编译检查(10-30s) / Stop→完整测试(编译+结构+安装模拟器+启动验证)
- Stop hook 智能跳过：`stop_hook_active` 防递归 + `git diff` 仅 swift 变更时触发
- 2 skills: `mobile-input-debug`（IME 调试）+ `server-restart`（开发重启）
- 1 agent: `mobile-ux-reviewer`（移动端 UX 检查清单）
- 1 MCP: Playwright（浏览器自动化测试）

## 移动端触摸滚动（03-07 实现，03-07 更新）
- 根因：xterm.js scrollback buffer 连 tmux 时永远为空（tmux 管自己的 buffer）
- 方案：`\x01scroll:up:N` / `down:N` / `exit` WebSocket 协议，server 端 `tmux copy-mode` + `send-keys -X scroll-up/down`
- 物理参数：Apple 原生 0.95/帧衰减，非线性加速 `pow(px/6, 1.6)`，40ms 节流
- 手势分流：`_touchInTerminal` flag 限定滚动仅 terminal 区域，quick-bar/键盘区不触发
- 详见 skill `tmux-xterm-scroll`

## 移动端输入模型（03-07 v3 重写）
- v3 架构：InputController 状态机（IDLE→COMPOSING→BUFFERING→FLUSHING）
- 30ms 统一 debounce buffer 替代逐字符发送 + sentBuffer（v3 从 150ms 降至 30ms）
- snapshot diff：compositionend 不再全量发送，只发增量
- AbortController 管理事件监听器，session 切换时一次性清理
- 评分趋势 6.7→6.8→7.7，核心改善：软 Enter 恢复、Tab 补全后同步、中文不重复
- InputController 生命周期修复：cleanupConnection 销毁后在 connect() 中重建，避免 session 切换后输入断连
- overlay textarea 改为始终 on-screen（opacity:0.01 + pointer-events:none），不再 left:-9999px，修复 iOS focus() 失败
- 输入框视觉隐藏：不再显示 "Type here..." 条，节省 36px 屏幕空间
- 详见 skill `mobile-input-debug`

## Agent Team 迭代模式（03-07 建立）
- 每版本 3 人团队：engineer（worktree 隔离）+ user（10 维评分）+ PM（RICE 分析）
- 反馈链：v(N) user/PM 反馈注入 v(N+1) engineer prompt
- iOS App 6 版本迭代：5.5→7.5→8.5→8.8→9.2（PM 9.3），TestFlight 85-90%
- Input 系统 3 版本迭代：6.7→6.8→7.7
- 详见 skill `agent-team-iteration`

## 已清理的 Worktree 分支（03-07 归档）
- `worktree-agent-a5d6b55b`：iOS App v1-v2（MVP + scroll/voice/notify/clipboard），已合入 ios-native-app-phase1
- `worktree-agent-a3d92b36`：多渠道 Agent 文档（WeChat/Lark/iMessage），已合入 master
- `worktree-agent-ae7bedb4`：iOS App 早期 + Agent 文档，已合入 ios-native-app-phase1
- `feature/ios-native-app-phase1`：滚动/通知等早期功能，已合入 master
- 活跃分支仅保留：`master` + `ios-native-app-phase1`（iOS App v6）

## crontab + CC /loop 定时任务（03-08 记录）
- macOS crontab：`crontab -e` 编辑，`crontab -l` 查看，最小粒度 1 分钟
- CC `/loop` 命令：`/loop 5m <prompt>` 在当前 session 内循环执行，默认 10 分钟间隔
- 组合场景：crontab 跑系统级定时（日报生成、服务健康检查），/loop 跑 session 内持续任务（监控部署、轮询 PR）
- crontab 跑 CC：`*/30 * * * * cd /path && claude -p "检查部署状态" --allowedTools Bash,Read >> /tmp/cron.log 2>&1`
- 注意：crontab 环境变量极简（无 PATH/LANG），需在命令中显式 export 或用 full path

## macOS TCC + tmux Full Disk Access（03-16 排查）
- Desktop/Documents/Downloads 受 TCC 保护，tmux 进程无 FDA 时 brew 初始化失败 → claude 启动也失败
- 修复：System Settings → Privacy → Full Disk Access → 添加 `/opt/homebrew/bin/tmux`，重启 tmux server
- 只影响 Desktop 下的项目（如 abl-ai），Documents 下的项目不受影响

## CC + Slack 内网集成（03-10 社区经验）
- 方案：内网 Pod 1:1 对应 Slack Thread，绕开官方 Slack 集成（需订阅 + 不能跑内网）
- Pod 在内网可直接访问公司所有服务，配合 Agent Skill 覆盖审核/开发/部署/日志/排查全流程
- [详细对比](../docs/cc-slack-integration-pattern.md)

## 多渠道消息 Agent（03-07 研究）
- OpenClaw 三层架构：Channel Adapter → Gateway → Agent Runtime
- 推荐方案：WeCom（企业微信）+ Lark（飞书）双通道
- LLM：Minimax API（api.minimax.io/v1，OpenAI 兼容，MiniMax-M2.5）
- iMessage 可行但受限（chat.db polling + AppleScript）
- [统一框架文档](../docs/unified-agent-framework.md)
