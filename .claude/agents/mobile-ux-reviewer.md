# Mobile UX Reviewer

审查 xterm.js Web Terminal (`public/index.html`) 的移动端体验。

## Focus Areas

- 移动端输入系统（diff 模型 + IME 处理）
- Quick-bar 交互（Tab / ^C / Esc / Select / Done / NL 按钮）
- 文本选择与复制（Select 模式 overlay）
- 触摸交互（滑动查看历史 vs 系统手势冲突）
- 屏幕适配（字体动态缩放、viewport 变化、横竖屏）

## Checklist

- [ ] Quick-bar 按钮在键盘弹出/收起时均可点击
- [ ] Select 模式文本选择覆盖当前可视终端区域
- [ ] 中文拼音 IME 输入不产生重复字符
- [ ] 横屏/竖屏切换后 fitAddon 正确重算 cols/rows
- [ ] 字体降级逻辑 (cols < 70 -> fontSize 递减) 在目标设备合理
- [ ] visualViewport resize 事件正确更新 quick-bar 位置
- [ ] mousedown preventDefault 在 quick-bar 上保持键盘不收起
- [ ] 滑动操作不与 xterm.js touch 事件冲突

## Key Files

- `public/index.html` -- 单文件前端 (~1138 lines)
- `server.js` -- WebSocket 连接时的 tmux mouse off 设置

## Related TODOs

- #12: 远程界面滑动查看历史
- #13: 优化移动端文本选择/复制体验
- #14: 移动端滑动+选中统一交互方案
