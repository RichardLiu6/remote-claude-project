# TODO

## iOS App — TestFlight 阻塞项

## #24 [03-07] iOS App 滚动真机验证 + 修复 — ⬜
- 连续 5 版未验证的"大象"，TestFlight 提交前阻塞项
- 真机验证：手指滑动 → tmux copy-mode → 滚动浏览 → 点击退出
- 如 SwiftTerm + tmux copy-mode 兼容性有问题，考虑绕过 tmux 用 SwiftTerm scrollback buffer 本地滚动
- 浮动 "Exit Scroll" 按钮 + 滚动位置指示条

## #25 [03-07] iOS App TestFlight 提交 — ⬜
- Apple Developer Team 签名 + Provisioning Profile
- TestFlight metadata："What to Test" + beta 描述
- LaunchScreen（黑底 + 紫色光标，匹配 App 图标）

## iOS App — 体验打磨

## #13 [03-07] 文本选择/复制增强（Web + App 双端） — ⬜
- 长按选中：滑动选中文本，松手弹出操作菜单
- 操作菜单：复制 / 打开浏览器（URL 识别）/ 搜索
- Select overlay 不默认全选，Done → "Copy & Close"
- 对标 Termius 原生选择体验

## #26 [03-07] iOS App 语音队列播放 — ⬜
- 当前 downloadTask?.cancel() 多段互相覆盖
- 改为 FIFO 队列，前段播完再播下段
- 语速控制（0.5x / 1.0x / 1.5x / 2.0x）

## #27 [03-07] iOS App 通知内容增强 — ⬜
- 通知 body 包含 CC 最后一行输出摘要（替代固定 "Task completed"）
- 模式匹配可配置 + 通知设置页面

## #28 [03-07] iOS App 原生能力深挖 — ⬜
- WidgetKit 桌面小组件：活跃 session 数 + 一键直达
- Shortcuts 集成："开始 Claude session" / "发送指令"
- pinch-to-zoom 手势缩放字体
- 命令收藏/历史：长按快捷栏弹出收藏面板

## Web 终端

## #29 [03-07] Web 终端 PWA 全屏体验真机验证 — ⬜
- 添加到主屏幕后确认地址栏隐藏、safe-area 适配
- standalone 模式下键盘/quick-bar/滚动交互正常

## #20 [03-07] 通知系统重构后验证 — ⬜
- /notify skill 真机测试（local / web / both / off）
- 手机浏览器 Notification API 权限授权 + 通知弹出
- 标题闪烁 + 蜂鸣音效果确认

## #14 [03-04] 移动端滑动+选中统一交互 — ⬜
- #12 滑动历史 ✅ 已完成
- ~~#13 长按选中待实现~~ 滑动区域限定为 terminal 已完成
- 手势分流：短滑=滚动 / 长按=选中 / 点按=键盘

## 远程控制方案

## #23 [03-07] 多渠道消息 Agent 框架 — ⬜
- WeCom + Lark + Minimax API 统一 Agent
- [统一框架文档](../docs/unified-agent-framework.md)

## #5 [—] 语音代理 C2：自然对话感 — ⬜
- [setup-guide#C2](../docs/remote-claude-setup-guide.md#方案-c2语音代理自然对话感)

## #6 [—] Telegram Bot D1：语音+文字入口 — ⬜
- [setup-guide#D1](../docs/remote-claude-setup-guide.md#d1telegram-bot推荐支持语音消息)

## #7 [—] iMessage D2：AppleScript 文字入口 — ⬜
- [setup-guide#D2](../docs/remote-claude-setup-guide.md#d2imessage文字为主mac-原生)
