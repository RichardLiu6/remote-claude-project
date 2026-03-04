# TODO

> 项目任务追踪，由 Claude Code 自动维护

| # | 类型 | 状态 | 任务 | 来源 | 日期 |
|---|------|------|------|------|------|
| 11 | 🐛 Bug | ⬜ | 手机输入法换行删字+双行（首次修复破坏Enter，已回退，需重新排查） | session 讨论 | 2026-03-03 |
| 12 | 🐛 Bug | ⬜ | 远程界面滑动查看历史（路线1已回退移除，待重新设计） | session 讨论 | 2026-03-03 |
| 13 | 🔧 Improve | ⬜ | 优化移动端文本选择/复制体验（对标 Termius 原生选择） | session 讨论 | 2026-03-03 |
| 14 | 🔧 Improve | ⬜ | 移动端滑动+选中统一交互方案（#12+#13 合并专项开发） | session 讨论 | 2026-03-04 |
| 5 | ✨ Feature | ⬜ | 语音代理 C2：自然对话感（需额外 LLM 调用） | setup-guide C2 | — |
| 6 | ✨ Feature | ⬜ | Telegram Bot D1：语音+文字消息入口 | setup-guide D1 | — |
| 7 | ✨ Feature | ⬜ | iMessage D2：AppleScript 文字入口 | setup-guide D2 | — |

## 已完成

| # | 类型 | 任务 | 完成日期 |
|---|------|------|---------|
| 1 | ✨ Feature | 语音模式 C1：Hook 驱动 + Edge TTS | 2026-02-28 |
| 2 | 🐛 Bug | 修复 4 个 P0 bug（JSON/Markdown/Queue/Regex） | 2026-03-01 |
| 3 | 🔧 Improve | 语音格式升级：`[voice:]` → `<!-- voice: {} -->` | 2026-03-01 |
| 4 | ✨ Feature | Per-session voice flag 文件隔离 | 2026-03-01 |
| 8 | ✨ Feature | TODO 追踪系统：Skill + Hook 验证端到端 | 2026-03-01 |
| 9 | 🐛 Bug | 修复 SSH echo 污染 iOS Shortcuts session 列表 | 2026-03-02 |
| 10 | 🐛 Bug | 页面刷新后 session 选择器重置（sessionStorage 持久化） | 2026-03-03 |
| 11 | 🐛 Bug | 手机输入法换行删字+双行（首次修复破坏Enter，已回退） | 2026-03-03 |
