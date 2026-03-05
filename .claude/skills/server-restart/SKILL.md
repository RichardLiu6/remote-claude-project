---
name: server-restart
description: 重启 Web Terminal server.js 并验证端口就绪。用于 server.js 修改后的快速测试循环。
disable-model-invocation: true
---

# Server Restart

重启 server.js 并验证 8022 端口就绪。

## Steps

1. 杀掉现有 server.js 进程
2. 启动新的 server.js（后台）
3. 等待 8022 端口就绪（最多 5 秒）
4. curl 健康检查 /api/sessions

```bash
# 1. Stop existing
pkill -f "node server.js" 2>/dev/null; sleep 1

# 2. Start (background)
cd /Users/haoyuliu_2024/Documents/LIG_ALL/实时更新学习Claude/remote-claude-project
nohup node server.js > /tmp/web-terminal-server.log 2>&1 &

# 3. Wait for port
for i in $(seq 1 10); do
  lsof -i :8022 -sTCP:LISTEN >/dev/null 2>&1 && break
  sleep 0.5
done

# 4. Health check
curl -sf http://localhost:8022/api/sessions | python3 -m json.tool
```

## Troubleshooting

- 端口占用: `lsof -i :8022` 查看占用进程
- 启动失败: `cat /tmp/web-terminal-server.log` 查看错误
- node-pty 权限: `chmod +x node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper`
- 正常运行时应由 `start-claude.sh` 管理 server 生命周期，此 skill 仅用于开发调试
