# TODO

## #20 [03-07] 通知系统重构后验证 — ⬜
- /notify skill 真机测试（local / web / both / off）
- 手机浏览器 Notification API 权限授权 + 通知弹出
- 标题闪烁 + 蜂鸣音效果确认

## #18 [03-07] 语音系统重构后验证 — ✅
- /voice skill 真机测试（local / web / both / off）— 通过
- 手机 Web Terminal 确认 WS 语音播放正常（speaker 按钮已移除）
- 电脑 Cursor/Terminal 确认 afplay 本地播放正常

## #14 [03-04] 移动端滑动+选中统一交互 — ⬜
- #12 滑动历史 ✅ 已完成
- #13 长按选中待实现
- 手势分流：短滑=滚动 / 长按=选中 / 点按=键盘

## #12 [03-07] 远程界面滑动查看历史 — ✅
- 路线1（scroll zone + tmux copy-mode）已回退
- 路线2（term.scrollLines）失败 — xterm.js buffer 为空（tmux 管理自己的 buffer）
- 路线3（\x01scroll 协议 + tmux copy-mode server-side）— 真机验证通过
- 优化完成：iOS 自然方向 + 非线性加速曲线 + Apple 0.95 衰减惯性

## #13 [03-07] 移动端文本选择/复制体验优化 — ⬜
- 长按进入选中模式，滑动选中文本，松手复制
- 不能与普通滑动滚动、键盘输入冲突
- 对标 Termius 原生选择体验

## #5 [—] 语音代理 C2：自然对话感 — ⬜
- [setup-guide#C2](../docs/remote-claude-setup-guide.md#方案-c2语音代理自然对话感)

## #6 [—] Telegram Bot D1：语音+文字入口 — ⬜
- [setup-guide#D1](../docs/remote-claude-setup-guide.md#d1telegram-bot推荐支持语音消息)

## #7 [—] iMessage D2：AppleScript 文字入口 — ⬜
- [setup-guide#D2](../docs/remote-claude-setup-guide.md#d2imessage文字为主mac-原生)

## #16 [03-04] 原生 iOS App：SwiftUI + SwiftTerm — ⬜
- [方案文档](../docs/ios-native-app-plan.md)
