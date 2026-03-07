const express = require('express');
const { WebSocketServer } = require('ws');
const { spawn } = require('node-pty');
const { execSync, execFile } = require('child_process');
const http = require('http');
const path = require('path');
const url = require('url');
const fs = require('fs');
const crypto = require('crypto');
const os = require('os');

const app = express();
const server = http.createServer(app);

app.use(express.json({ limit: '25mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// --- Voice TTS setup ---
const audioDir = path.join(__dirname, 'public', 'audio');
fs.mkdirSync(audioDir, { recursive: true });
// Cleanup stale audio files from previous runs
fs.readdir(audioDir, (err, files) => {
  if (err) return;
  files.filter(f => f.endsWith('.mp3')).forEach(f => {
    fs.unlink(path.join(audioDir, f), () => {});
  });
});
// Generate a tiny silent WAV for Chrome mobile audio unlock
(function createSilenceWav() {
  const silencePath = path.join(audioDir, 'silence.wav');
  if (fs.existsSync(silencePath)) return;
  const sampleRate = 22050, numSamples = Math.floor(sampleRate * 0.05); // 50ms
  const dataSize = numSamples * 2;
  const buf = Buffer.alloc(44 + dataSize); // data stays zeroed = silence
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + dataSize, 4);
  buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(1, 22); buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * 2, 28); buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34); buf.write('data', 36);
  buf.writeUInt32LE(dataSize, 40);
  fs.writeFileSync(silencePath, buf);
  console.log('[voice] created silence.wav for audio unlock');
})();
let ttsQueue = [];
let ttsProcessing = false;

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

// --- Voice TTS endpoint ---
let lastVoiceEvent = null;

function broadcastVoice(payload) {
  const msg = '\x01voice:' + JSON.stringify(payload);
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(msg);
  });
}

function processNextTTS() {
  if (ttsProcessing || ttsQueue.length === 0) return;
  ttsProcessing = true;

  const { text } = ttsQueue.shift();
  const filename = `voice-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.mp3`;
  const outputPath = path.join(audioDir, filename);

  console.log(`[voice] generating TTS: "${text.slice(0, 40)}..." (queue: ${ttsQueue.length})`);

  execFile('/opt/homebrew/bin/python3.13',
    ['-m', 'edge_tts', '--text', text, '--voice', 'zh-CN-XiaoxiaoNeural', '--write-media', outputPath],
    { timeout: 15000 },
    (err) => {
      ttsProcessing = false;
      if (err) {
        console.error('[voice] edge-tts error:', err.message);
        fs.unlink(outputPath, () => {});
      } else {
        const audioUrl = `/audio/${filename}`;
        lastVoiceEvent = { text, url: audioUrl, timestamp: Date.now() };
        console.log(`[voice] broadcast: ${audioUrl}`);
        broadcastVoice({ url: audioUrl, text });
        setTimeout(() => fs.unlink(outputPath, () => {}), 5 * 60 * 1000);
      }
      processNextTTS();
    }
  );
}

app.post('/voice-event', (req, res) => {
  const text = (req.body.text || '').slice(0, 500).trim();
  if (!text) return res.status(400).json({ ok: false, error: 'empty text' });

  if (ttsQueue.length >= 3) {
    return res.status(429).json({ ok: false, error: 'queue full (3 max)' });
  }

  ttsQueue.push({ text });
  const position = ttsQueue.length;
  processNextTTS();

  res.json({ ok: true, status: ttsProcessing && position > 1 ? 'queued' : 'generating', queue: position });
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

// --- File upload (phone → Mac for Claude Code) ---
app.post('/api/upload', (req, res) => {
  const { data, filename } = req.body;
  if (!data || !filename) return res.status(400).json({ error: 'missing data or filename' });
  const ext = path.extname(filename).toLowerCase() || '.jpg';
  const safeName = `cc-upload-${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`;
  const dest = path.join('/tmp', safeName);
  try {
    const buf = Buffer.from(data, 'base64');
    fs.writeFileSync(dest, buf);
    console.log(`[upload] saved ${dest} (${buf.length} bytes)`);
    // Auto-cleanup after 1 hour
    setTimeout(() => fs.unlink(dest, () => {}), 60 * 60 * 1000);
    res.json({ path: dest });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
