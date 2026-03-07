# TODO

> 项目任务追踪，由 Claude Code 自动维护。每条任务保持一句话精简，详情见链接文档。

| # | 类型 | 状态 | 任务 | 文档 | 日期 |
|---|------|------|------|------|------|
| 12 | 🐛 Bug | ⬜ | 远程界面滑动查看历史（路线1已回退，待重新设计） | — | 2026-03-03 |
| 13 | 🔧 Improve | ⬜ | 移动端文本选择/复制体验优化 | — | 2026-03-03 |
| 14 | 🔧 Improve | ⬜ | 移动端滑动+选中统一交互（#12+#13 合并） | — | 2026-03-04 |
| 5 | ✨ Feature | ⬜ | 语音代理 C2：自然对话感 | [setup-guide#C2](remote-claude-setup-guide.md#方案-c2语音代理自然对话感) | — |
| 6 | ✨ Feature | ⬜ | Telegram Bot D1：语音+文字入口 | [setup-guide#D1](remote-claude-setup-guide.md#d1telegram-bot推荐支持语音消息) | — |
| 7 | ✨ Feature | ⬜ | iMessage D2：AppleScript 文字入口 | [setup-guide#D2](remote-claude-setup-guide.md#d2imessage文字为主mac-原生) | — |
| 16 | ✨ Feature | ⬜ | 原生 iOS App：SwiftUI + SwiftTerm 替代 Web 终端 | [方案文档](ios-native-app-plan.md) | 2026-03-04 |
| 17 | 🔧 Improve | ⬜ | 语音 hook 非 tmux 环境应直接 exit 0（去掉全局 fallback） | — | 2026-03-05 |

## 已完成

| # | 类型 | 任务 | 文档 | 完成日期 |
|---|------|------|------|---------|
| 1 | ✨ Feature | 语音模式 C1：Hook 驱动 + Edge TTS | [语音分析](voice-mode-analysis-condensed.md) | 2026-02-28 |
| 2 | 🐛 Bug | 修复 4 个 P0 bug（JSON/Markdown/Queue/Regex） | — | 2026-03-01 |
| 3 | 🔧 Improve | 语音格式升级：`[voice:]` → `<!-- voice: {} -->` | [提取模式](voice-mode-analysis.md) | 2026-03-01 |
| 4 | ✨ Feature | Per-session voice flag 文件隔离 | [setup-guide#开关](remote-claude-setup-guide.md#语音模式开关机制c1-核心) | 2026-03-01 |
| 8 | ✨ Feature | TODO 追踪系统：Skill + Hook 端到端 | — | 2026-03-01 |
| 9 | 🐛 Bug | SSH echo 污染 iOS Shortcuts session 列表 | — | 2026-03-02 |
| 10 | 🐛 Bug | 页面刷新后 session 选择器重置 | — | 2026-03-03 |
| 11 | 🐛 Bug | iOS IME insertParagraph 换行删字 | — | 2026-03-04 |
| 15 | 🔧 Improve | 移动端输入重构：diff 模型替代三层事件拦截 | — | 2026-03-04 |
