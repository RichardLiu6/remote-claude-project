const express = require('express');
const { WebSocketServer } = require('ws');
const { spawn } = require('node-pty');
const { execSync } = require('child_process');
const http = require('http');
const path = require('path');
const url = require('url');

const app = express();
const server = http.createServer(app);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// --- REST API ---

// List tmux sessions
app.get('/api/sessions', (req, res) => {
  try {
    const output = execSync(
      "tmux list-sessions -F '#{session_name}|#{session_created}|#{session_windows}' 2>/dev/null",
      { encoding: 'utf-8' }
    );
    const sessions = output.trim().split('\n').filter(Boolean).map(line => {
      const [name, created, windows] = line.split('|');
      return { name, created: Number(created), windows: Number(windows) };
    });
    res.json(sessions);
  } catch {
    res.json([]);
  }
});

// Voice event endpoint (placeholder for C1 Hook push)
let lastVoiceEvent = null;
app.post('/voice-event', (req, res) => {
  lastVoiceEvent = { text: req.body.text, timestamp: Date.now() };
  res.json({ ok: true });
});

app.get('/voice-event', (req, res) => {
  res.json(lastVoiceEvent || { text: null });
});

// --- Clipboard bridge (Mac pbpaste → phone browser) ---
app.get('/api/clipboard', (req, res) => {
  try {
    const text = execSync('pbpaste', { encoding: 'utf-8', timeout: 2000 });
    res.json({ text });
  } catch {
    res.json({ text: '', error: 'pbpaste failed' });
  }
});

// --- Resize debug API ---
app.get('/api/debug/resize', (req, res) => {
  const clients = [];
  wss.clients.forEach(ws => {
    clients.push({
      session: ws.sessionName,
      ptyCols: ws._ptyCols,
      ptyRows: ws._ptyRows,
      lastResizeAt: ws._lastResizeAt,
    });
  });
  res.json({ clients });
});

// --- WebSocket Terminal ---

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const { pathname, query } = url.parse(req.url, true);
  if (pathname === '/ws') {
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.sessionName = query.session;
      wss.emit('connection', ws, req);
    });
  } else {
    socket.destroy();
  }
});

wss.on('connection', (ws) => {
  const session = ws.sessionName;
  if (!session) {
    ws.send('\r\nError: no session specified\r\n');
    ws.close();
    return;
  }

  console.log(`[ws] new connection for session="${session}"`);

  const pty = spawn('/opt/homebrew/bin/tmux', ['attach', '-t', session], {
    name: 'xterm-256color',
    cols: 80,
    rows: 24,
    env: { ...process.env, TERM: 'xterm-256color', LANG: process.env.LANG || 'en_US.UTF-8', LC_ALL: process.env.LC_ALL || 'en_US.UTF-8' },
  });

  // Disable tmux mouse for this pane so xterm.js handles selection/scroll natively.
  // Run as a separate tmux command (not through the pty, which would type into CC).
  try {
    execSync(`/opt/homebrew/bin/tmux set-option -t "${session}" -p mouse off 2>/dev/null`);
  } catch {}

  // Track resize state on ws object for debug API
  ws._ptyCols = 80;
  ws._ptyRows = 24;
  ws._lastResizeAt = null;

  console.log(`[ws] pty spawned with initial size 80x24, pid=${pty.pid}`);

  pty.onData((data) => {
    if (ws.readyState === ws.OPEN) ws.send(data);
  });

  ws.on('message', (msg) => {
    const str = msg.toString();
    // Handle resize messages
    if (str.startsWith('\x01resize:')) {
      try {
        const { cols, rows } = JSON.parse(str.slice(8));
        console.log(`[resize] session="${session}" ${ws._ptyCols}x${ws._ptyRows} → ${cols}x${rows}`);
        pty.resize(cols, rows);
        ws._ptyCols = cols;
        ws._ptyRows = rows;
        ws._lastResizeAt = new Date().toISOString();
      } catch (e) {
        console.error(`[resize] parse error:`, e.message);
      }
      return;
    }
    pty.write(str);
  });

  pty.onExit(() => {
    if (ws.readyState === ws.OPEN) {
      ws.send('\r\n[session ended]\r\n');
      ws.close();
    }
  });

  ws.on('close', () => {
    console.log(`[ws] closed for session="${session}", killing pty pid=${pty.pid}`);
    pty.kill();
  });
});

// --- Start ---

const PORT = process.env.PORT || 8022;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Web terminal running on http://0.0.0.0:${PORT}`);
});
