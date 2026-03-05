---
name: mobile-input-debug
description: 移动端输入系统调试指南。修改 index.html 的输入事件处理（keydown/beforeinput/input/compositionend）时使用。包含 diff 模型原理、IME 时序陷阱、已知 iOS 行为差异。
---

# Mobile Input Debug Guide

## 输入架构（Diff 模型）

当前 `public/index.html` 使用四层事件协作：

1. **keydown**: 只处理明确识别的物理键盘按键（Enter/arrows/Tab/Esc/Backspace）
2. **beforeinput**: 只处理软键盘 Enter（`insertParagraph`，含 300ms post-IME 抑制）+ edge cases
3. **input**: 核心 -- diff `previousValue` vs `textarea.value`，发送退格 + 增量
4. **compositionend**: 只记录时间戳，**不发送文本**（由 input 的 diff 处理）

关键原则：**观察结果（diff）而非拦截过程（事件）**，从根本上消除 IME 时序 bug。

## 已知 iOS 行为差异

- iOS Safari 软键盘 Enter 发 `insertParagraph`（InputEvent）而非 `Enter` keyCode
- iOS IME（中文拼音）的 compositionend 后会紧跟一个 input 事件 -- 不能在两处都发文本
- iOS 12+ `visualViewport` API 用于定位 quick-bar（older iOS fallback to `window.innerHeight`）
- Safari 的 `isComposing` 在 compositionend 时已经是 false
- iOS 自动大写/自动纠错可能在 textarea 中插入意外文本

## 调试步骤

1. 在 textarea 的 input handler 加 `console.log('diff:', previousValue, '->', textarea.value)`
2. 检查 `lastCompositionEnd` 时间戳与当前时间差是否 > 300ms
3. 用 Safari Web Inspector 远程调试（Settings > Safari > Advanced > Web Inspector）
4. 注意：Chrome DevTools 的移动模拟 **不能** 复现真实 IME 行为，必须真机测试

## 防踩坑清单

修改输入相关代码后，依次验证：

- [ ] 中文拼音输入"你好"确认不重复/不丢字
- [ ] 物理键盘 Enter 只发一次回车
- [ ] 软键盘 Enter（insertParagraph）只发一次回车
- [ ] IME 确认后立即按 Enter，不会吞掉 Enter
- [ ] `previousValue` 在每次 diff 后正确更新
- [ ] Quick-bar 按钮用 mousedown preventDefault 保持键盘不收起
- [ ] Backspace 在 IME 未激活时正确删字

## 相关文件

- `public/index.html` -- 搜索 `previousValue`、`lastCompositionEnd`、`handleSoftEnter`
- CLAUDE.md Mobile Input System 章节
- TODO #14: 移动端滑动+选中统一交互方案
- TODO #15 (completed): diff 模型重构
