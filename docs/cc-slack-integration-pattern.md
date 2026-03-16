# Claude Code + Slack 集成模式（社区经验）

> 来源：社区用户分享（2026-03）

## 背景

Claude Code 原生支持 Slack，但有两个限制：
1. 需要订阅 Anthropic 服务器费用
2. 不能在公司内网运行（无法访问内部服务）

## 架构方案

```
Slack Thread ←→ 内网 Pod（运行 Claude Code）←→ 公司内部服务
```

- **一个 Pod 对应一个 Slack Thread**：每次对话启动一个独立 Pod
- **Pod 运行在内网**：可直接访问公司所有内部服务（代码库、CI/CD、日志系统、数据库等）
- **配合 Agent Skill**：扩展 CC 能力，覆盖更多工作流

## 日常使用场景

通过手机 + Slack 聊天驱动，典型指令：
- "帮我审核一下呗"（Code Review）
- "帮我开发个功能呗"（Feature Dev）
- "帮我部署一下呗"（Deployment）
- "帮我看一下日志呗"（Log Analysis）
- "帮我排查一下呗"（Troubleshooting）

## 关键洞察

1. **内网 Pod 是关键**：绕开官方 Slack 集成的限制，Pod 在内网跑，天然能访问所有内部资源
2. **1:1 映射简化管理**：一个 Slack Thread = 一个 Pod = 一个 CC session，天然隔离
3. **手机操控**：和我们的方案（手机 → Web Terminal → tmux → CC）思路一致，都是移动端驱动
4. **Agent Skill 是倍增器**：预配置好常用工作流的 skill，用自然语言触发

## 与本项目方案对比

| 维度 | 本项目（Web Terminal） | Slack Pod 方案 |
|------|----------------------|---------------|
| 入口 | 手机浏览器 + xterm.js | 手机 Slack App |
| 交互 | 完整 CLI | Slack 聊天（文本） |
| 网络 | Tailscale VPN | 公司内网 |
| 多 session | tmux session | Pod per Thread |
| 优势 | 完整终端控制 | 团队协作可见、无需 VPN |
| 劣势 | 需 VPN、单人 | 需容器编排、文本交互受限 |
