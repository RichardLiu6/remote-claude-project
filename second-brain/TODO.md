# TODO

## #20 [03-07] 通知系统重构后验证 — ⬜
- /notify skill 真机测试（local / web / both / off）
- 手机浏览器 Notification API 权限授权 + 通知弹出
- 标题闪烁 + 蜂鸣音效果确认

## #14 [03-04] 移动端滑动+选中统一交互 — ⬜
- #12 滑动历史 ✅ 已完成
- #13 长按选中待实现
- 手势分流：短滑=滚动 / 长按=选中 / 点按=键盘

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

## #16 [03-07] 原生 iOS App：SwiftUI + SwiftTerm — 🔄
- v1-v5 已完成，用户评分 5.5→7.5→8.5→v5待评
- v5: TerminalView 拆分、fetchSessions 安全修复、文件上传、横屏优化
- v6（最终版）待 v5 评审后启动
- [评审文档](../docs/ios-app-user-review-v4.md)

## #22 [03-07] 移动端输入系统 v3 重写 — ✅
- InputController 状态机 + 150ms debounce + snapshot diff
- 用户评分 6.7→6.8→7.7（架构级改善）
- [v3 用户评价](../docs/input-user-review-v3.md) | [v3 PM 终版](../docs/input-pm-assessment-v3.md)

## #23 [03-07] 多渠道消息 Agent 框架 — ⬜
- WeCom + Lark + Minimax API 统一 Agent
- [统一框架文档](../docs/unified-agent-framework.md)
- iMessage/WeChat/Lark 集成方案已完成
