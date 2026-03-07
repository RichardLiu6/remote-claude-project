# TODO

## #19 [03-07] 通知 hook 多环境适配 — ⬜
- 现状：notify.sh 固定用 terminal-notifier + afplay（Cursor 桌面通知）
- 问题：手机远端使用 CC 时，通知仍然弹在 Mac 桌面，手机收不到
- 需要：类似语音重构的思路，根据环境路由通知到不同通道
- [详细方案](../docs/notification-refactor-design.md)

## #18 [03-07] 语音系统重构后验证 — ✅
- /voice skill 真机测试（local / web / both / off）— 通过
- 手机 Web Terminal 确认 WS 语音播放正常（speaker 按钮已移除）
- 电脑 Cursor/Terminal 确认 afplay 本地播放正常

## #14 [03-04] 移动端滑动+选中统一交互 — ⬜
- 合并 #12（滑动历史）+ #13（文本选择）
- touch scroll 已实现（03-04 commit），待真机验证
- 选中/复制部分待设计

## #12 [03-03] 远程界面滑动查看历史 — ⬜
- 路线1已回退，03-04 用 touchstart/move/end 重新实现
- 待手机验证是否可关闭

## #13 [03-03] 移动端文本选择/复制体验优化 — ⬜
- 对标 Termius 原生选择

## #5 [—] 语音代理 C2：自然对话感 — ⬜
- [setup-guide#C2](../docs/remote-claude-setup-guide.md#方案-c2语音代理自然对话感)

## #6 [—] Telegram Bot D1：语音+文字入口 — ⬜
- [setup-guide#D1](../docs/remote-claude-setup-guide.md#d1telegram-bot推荐支持语音消息)

## #7 [—] iMessage D2：AppleScript 文字入口 — ⬜
- [setup-guide#D2](../docs/remote-claude-setup-guide.md#d2imessage文字为主mac-原生)

## #16 [03-04] 原生 iOS App：SwiftUI + SwiftTerm — ⬜
- [方案文档](../docs/ios-native-app-plan.md)
