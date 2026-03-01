#!/bin/bash
# 用法: ~/start-claude.sh [项目名] [skip]
# 示例: ~/start-claude.sh ABL_work skip

export PATH="/opt/homebrew/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"

PROJECT="${1:-default}"
SKIP_MODE="${2:-normal}"

# Web Terminal 配置
WEB_TERMINAL_DIR=~/Documents/LIG_ALL/实时更新学习Claude/remote-claude-project
WEB_TERMINAL_PORT=8022

# 按需启动 Web Terminal
start_web_terminal() {
  if ! lsof -i :$WEB_TERMINAL_PORT -sTCP:LISTEN &>/dev/null; then
    (cd "$WEB_TERMINAL_DIR" && nohup node server.js </dev/null >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1
    echo "Web terminal started on port $WEB_TERMINAL_PORT"
  fi
}

# 按需关闭 Web Terminal（无 CC session 时）
stop_web_terminal_if_idle() {
  local remaining
  remaining=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" -eq 0 ]; then
    pkill -f "node.*server.js" 2>/dev/null
    echo "Web terminal stopped (no sessions)"
  fi
}

# 特殊命令：关闭 tmux 会话
if [ "$PROJECT" = "list" ]; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null || echo "No active sessions"
    exit 0
fi

if [ "$PROJECT" = "list-detail" ]; then
    tmux list-sessions -F '#{session_name} | #{pane_current_path}' 2>/dev/null || echo "No active sessions"
    exit 0
fi

if [ "$PROJECT" = "kill-all" ] || [ "$PROJECT" = "关闭全部" ]; then
    # 给每个会话的 CC 发 /exit
    for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
        tmux send-keys -t "$sess" "/exit" Enter
    done
    sleep 2
    tmux kill-server 2>/dev/null
    stop_web_terminal_if_idle
    echo "All sessions closed"
    exit 0
fi

if [ "$PROJECT" = "kill-latest" ] || [ "$PROJECT" = "关闭最近" ]; then
    LATEST=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | tail -1)
    if [ -n "$LATEST" ]; then
        tmux send-keys -t "$LATEST" "/exit" Enter
        sleep 2
        tmux kill-session -t "$LATEST" 2>/dev/null
        echo "Closed session: $LATEST"
    else
        echo "No sessions to close"
    fi
    stop_web_terminal_if_idle
    exit 0
fi

if [ "$PROJECT" = "kill" ]; then
    SESSION_TO_KILL="$SKIP_MODE"
    if tmux has-session -t "$SESSION_TO_KILL" 2>/dev/null; then
        # 先给 Claude Code 发 /exit 优雅退出
        tmux send-keys -t "$SESSION_TO_KILL" "/exit" Enter
        sleep 2
        # 再关闭 tmux 会话
        tmux kill-session -t "$SESSION_TO_KILL" 2>/dev/null
        echo "Closed session: $SESSION_TO_KILL"
    else
        echo "Session not found: $SESSION_TO_KILL"
    fi
    stop_web_terminal_if_idle
    exit 0
fi

# 项目名 → 文件夹路径 + 英文 session 别名
case "$PROJECT" in
    Richard所有信息-ai整理版)   DIR=~/Desktop/Richard所有信息-ai整理版;   ALIAS="richard" ;;
    ABL_work)                   DIR=~/Documents/ABL_work;                  ALIAS="abl" ;;
    实时更新学习Claude)          DIR=~/Documents/LIG_ALL/实时更新学习Claude; ALIAS="claude-learn" ;;
    *)                          echo "Unknown project: $PROJECT"; exit 1 ;;
esac

if [ ! -d "$DIR" ]; then
    echo "Error: $DIR does not exist"
    exit 1
fi

SESSION_NAME="${ALIAS}-$(date +%H%M)"

# 启动 Web Terminal（如果没跑）
start_web_terminal

tmux new-session -d -s "$SESSION_NAME" -c "$DIR"

if [ "$SKIP_MODE" = "skip" ]; then
    tmux send-keys -t "$SESSION_NAME" "unset CLAUDECODE; claude --dangerously-skip-permissions" Enter
else
    tmux send-keys -t "$SESSION_NAME" "unset CLAUDECODE; claude" Enter
fi

# 后台等 CC 启动后发 /rename（不阻塞 SSH 返回）
(sleep 3 && tmux send-keys -t "$SESSION_NAME" "/rename $SESSION_NAME" && sleep 1 && tmux send-keys -t "$SESSION_NAME" Enter) </dev/null &>/dev/null &
disown

echo "Session $SESSION_NAME started in $DIR"
