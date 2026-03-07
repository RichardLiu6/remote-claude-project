#!/bin/bash
# 用法: ~/start-claude.sh [项目名] [skip]
# 示例: ~/start-claude.sh ABL_work skip

export PATH="/opt/homebrew/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"

# Claude Code OAuth token（从本地文件读取，token 过期时只需更新此文件）
if [ -f ~/.claude-oauth-token ]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-oauth-token)"
fi

PROJECT="${1:-default}"
SKIP_MODE="${2:-normal}"

# 按需加载 SSH key（跟随 server 生命周期，锁屏不影响）
if ! ssh-add -l &>/dev/null; then
  echo "SSH key not loaded, adding..." >&2
  ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
fi

# Web Terminal 配置
WEB_TERMINAL_DIR=~/Documents/LIG_ALL/实时更新学习Claude/remote-claude-project
WEB_TERMINAL_PORT=8022

# 按需启动 Web Terminal
start_web_terminal() {
  if ! lsof -i :$WEB_TERMINAL_PORT -sTCP:LISTEN &>/dev/null; then
    (cd "$WEB_TERMINAL_DIR" && nohup node server.js </dev/null >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1
    echo "Web terminal started on port $WEB_TERMINAL_PORT"
  fi
  # 防止系统睡眠（有 session 时保持唤醒，caffeinate 跟随 node 进程）
  if ! pgrep -f 'caffeinate.*-s' &>/dev/null; then
    caffeinate -s -w $(lsof -ti :$WEB_TERMINAL_PORT | head -1) &>/dev/null &
    disown
  fi
}

# 按需关闭 Web Terminal（无 CC session 时）
stop_web_terminal_if_idle() {
  local remaining
  remaining=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" -eq 0 ]; then
    pkill -f "node.*server.js" 2>/dev/null
    ssh-add -d ~/.ssh/id_ed25519 2>/dev/null
    echo "Web terminal stopped (no sessions), SSH key removed"
  fi
}

# 特殊命令：关闭 tmux 会话
if [ "$PROJECT" = "projects" ]; then
    # 输出所有可用项目名，每行一个（供 iOS 快捷指令 Split by New Lines）
    grep -E '^\s+\S+\)\s+DIR=' "$0" | sed 's/).*//' | sed 's/^ *//'
    exit 0
fi

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

if [ "$PROJECT" = "kill-pick" ]; then
    # 接受逗号分隔的 session 名，批量关闭（供 iOS 快捷指令）
    NAMES="$SKIP_MODE"
    if [ -z "$NAMES" ]; then
        echo "Usage: $0 kill-pick name1,name2,..."
        exit 1
    fi
    IFS=',' read -ra SESSIONS <<< "$NAMES"
    for sess in "${SESSIONS[@]}"; do
        if tmux has-session -t "$sess" 2>/dev/null; then
            tmux send-keys -t "$sess" "/exit" Enter
        fi
    done
    sleep 3
    for sess in "${SESSIONS[@]}"; do
        tmux kill-session -t "$sess" 2>/dev/null && echo "Closed: $sess"
    done
    stop_web_terminal_if_idle
    exit 0
fi

if [ "$PROJECT" = "kill" ]; then
    SESSION_TO_KILL="$SKIP_MODE"
    if tmux has-session -t "$SESSION_TO_KILL" 2>/dev/null; then
        tmux send-keys -t "$SESSION_TO_KILL" "/exit" Enter
        sleep 2
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
    richard-ai)                 DIR=~/Desktop/Richard所有信息-ai整理版;   ALIAS="richard-ai" ;;
    abl-ai)                     DIR=~/Desktop/Richard所有信息-ai整理版/ABL全部信息-ai整理版; ALIAS="abl-ai" ;;
    实时更新学习Claude)          DIR=~/Documents/LIG_ALL/实时更新学习Claude; ALIAS="claude-learn" ;;
    remote-claude-project)      DIR=~/Documents/LIG_ALL/实时更新学习Claude/remote-claude-project; ALIAS="remote-cc" ;;
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
