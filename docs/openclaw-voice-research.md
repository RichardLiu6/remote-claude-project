# OpenClaw 语音策略研究报告

> 研究日期：2026-03-01
> 研究目标：分析 OpenClaw 语音生态，提取可用于我们 Voice Mode C1 的改进方案
> 研究方法：3人并行研究团队（架构、语音管线、集成分析）

---

## 一、OpenClaw 项目概览

- **GitHub**: [openclaw/openclaw](https://github.com/openclaw/openclaw) — 195K+ stars
- **定位**: 开源个人 AI 助手，支持 WhatsApp/Telegram/Discord 等多平台
- **创建者**: Peter Steinberger（PSPDFKit 创始人），2025年11月发布
- **语音子项目**:
  - [openclaw-voice](https://github.com/Purple-Horizons/openclaw-voice) — 浏览器端语音聊天
  - [VoxClaw](https://github.com/malpern/VoxClaw) — Mac 网络语音（菜单栏 app）
  - [Jupiter Voice](https://github.com/openclaw/openclaw/discussions/12891) — 全本地语音助手

## 二、OpenClaw 语音架构

### 核心设计：语音分布在4个独立子系统

```
┌─────────────────────────────────────────────────────┐
│                  Gateway (控制面)                      │
│  port 18789 · WebSocket · Session · RPC · Auth       │
│                                                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐   │
│  │   STT    │  │   TTS    │  │  Voice-Call Skill  │   │
│  │ 5 providers│ │ 3 providers│ │ Twilio/Telnyx    │   │
│  │ batch转录  │ │ 输出路径   │  │ Realtime WS     │   │
│  └────┬─────┘  └─────┬────┘  └───────────────────┘   │
│       │ 文本进入      │ 文本输出                        │
│       ▼ 标准消息流    ▼ 通道适配                        │
│  ┌──────────────────────────────┐                     │
│  │      Agent Pipeline          │                     │
│  │  deriveSession → buildPrompt │                     │
│  │  → runAgent → persistLog    │                     │
│  └──────────────────────────────┘                     │
└─────────────────────────────────────────────────────┘
          ▲                    │
     inbound msg          outbound reply
          │                    ▼
┌─────────────────┐  ┌─────────────────┐
│  Node (设备端)    │  │  Channel (平台)  │
│  macOS/iOS/      │  │  Telegram/       │
│  Android App     │  │  Discord/Web     │
│  • Wake Word     │  │  • 格式适配      │
│  • Talk Mode     │  │  • Opus/MP3      │
│  • 本地音频 I/O   │  │                  │
└─────────────────┘  └─────────────────┘
```

**关键设计原则**：
1. 语音走标准消息流 — STT 转文本后进入与文本相同的 Agent Pipeline
2. 音频 I/O 在边缘设备 — Gateway 无头，设备端处理麦克风/扬声器
3. TTS 通道感知 — Telegram 用 Opus，电话用 PCM，默认 MP3

### STT 提供商（5个，自动降级）

| 提供商 | 默认模型 | 特点 |
|--------|---------|------|
| OpenAI | gpt-4o-mini-transcribe | 兼容接口，可指向 LocalAI |
| Groq | whisper-large-v3-turbo | 快速推理 |
| Deepgram | nova-3 | 专用 STT，智能格式化 |
| Google | Gemini 多模态 | 音频作为内联数据 |
| Mistral | voxtral-mini-latest | Mistral 音频模型 |

### TTS 提供商（3个）

| 提供商 | 默认 Voice | 成本 | 格式 |
|--------|-----------|------|------|
| ElevenLabs | eleven_multilingual_v2 | 付费 | mp3/opus/pcm |
| OpenAI | gpt-4o-mini-tts, alloy | 付费 | mp3/opus/pcm |
| **Edge TTS** | en-US-MichelleNeural | **免费** | mp3/webm/ogg/wav |

### TTS Auto 模式

| 模式 | 行为 |
|------|------|
| `off` | 禁用 |
| `always` | 每条回复都 TTS |
| `inbound` | 用户发语音时才 TTS 回复 |
| `tagged` | 仅当 AI 使用 `[[tts:...]]` 指令时 |

### TTS 指令系统

AI 可在回复中内嵌指令控制 TTS 行为：
```
[[tts:provider=elevenlabs voice_id=abc123 speed=1.2]]
[[tts:text]]自定义 TTS 文本，而非整条回复[[/tts:text]]
```

### 关键代码路径

| 组件 | 路径 | 用途 |
|------|------|------|
| TTS 入口 | `src/tts/tts.ts` | 配置解析、auto 模式、输出格式 |
| TTS 实现 | `src/tts/tts-core.ts` | 三个提供商的具体实现 |
| 文本清理 | `src/line/markdown-to-line.js` | stripMarkdown() |
| STT 提供商 | `src/media-understanding/providers/` | 5个提供商目录 |
| STT 编排 | `src/media-understanding/runner.ts` | 并发控制、降级 |
| 语音通话 | `skills/voice-call/SKILL.md` | Twilio/Telnyx 集成 |

## 三、社区语音方案对比

| 方案 | STT | TTS | 特点 |
|------|-----|-----|------|
| **Core OpenClaw** | 5 cloud providers | ElevenLabs/OpenAI/Edge | 批处理、多平台 |
| **openclaw-voice** | faster-whisper 本地 | ElevenLabs/Chatterbox/XTTS | 浏览器端、VAD 过滤 |
| **VoxClaw** | 无 | Apple AVSpeech/OpenAI/ElevenLabs | Mac 菜单栏 app、Bonjour |
| **Jupiter Voice** | Lightning Whisper MLX | Kokoro ONNX | 全本地、Apple Silicon |
| **我们 (Voice C1)** | 无 | Edge TTS | Hook 驱动、零成本 |

## 四、对我们项目的集成建议

### ADOPT（建议采纳）

#### 1. TTS 分句流式播放 ⭐⭐⭐ (P1, 2-3h)
- **现状**: 整段生成完才播放，长回复等待 3-5 秒
- **改进**: 按句号/问号/感叹号切分，逐句生成+推送，前端播放队列
- **效果**: 首字延迟 3-5s → ~1s
- **参考**: openclaw-voice 的 sentence-by-sentence streaming

#### 2. TTS 后端可切换 ⭐⭐ (P2, 1-1.5h)
- **现状**: 硬编码 Edge TTS
- **改进**: 环境变量 `VOICE_TTS_PROVIDER`（edge/say/openai）
- **效果**: 离线用 macOS `say`，高质量用 OpenAI TTS
- **参考**: OpenClaw 的多 TTS provider 抽象

#### 3. 播放状态 UI ⭐⭐ (P0, 30min)
- **现状**: speaker 按钮闪绿就没了
- **改进**: 监听 audio play/ended 事件，显示播放进度/状态
- **参考**: openclaw-voice 的语音活动指示器

#### 4. 语音历史回放 ⭐ (P3, 1h)
- **现状**: MP3 播完 5 分钟后删除，错过就没了
- **改进**: 保留最近 10 条，长按 speaker 可回放
- **参考**: VoxClaw 的 teleprompter UI

### SKIP（不建议采纳）

| 功能 | 原因 |
|------|------|
| STT / 语音输入 | 场景不匹配（命令/代码输入），iOS 浏览器不支持 Web Speech API |
| Wake Word 唤醒 | 浏览器后台不能持续监听麦克风，单用户不需要 |
| WebRTC 实时双向 | 与 tmux+WS 架构不匹配，我们是异步播报不是实时对话 |
| ElevenLabs 默认 | 需付费 API key，Edge TTS 中文质量已够用 |
| 独立桌面 App | 违反"最少中间层"原则，Web Terminal 已覆盖 |

### 改进优先级

| 优先级 | 改进 | 工作量 | 价值 |
|--------|------|--------|------|
| **P0** | 播放状态 UI | 30 min | 中 — 最小改动最快见效 |
| **P1** | 分句流式播放 | 2-3 h | 高 — 体验质的飞跃 |
| **P2** | TTS 后端可配置 | 1-1.5 h | 中 — 灵活性+离线 |
| **P3** | 语音历史回放 | 1 h | 低 — Nice to have |

> 总计约 5-6 小时。建议先做 P0+P1（~3h）即可大幅提升体验。

## 五、核心结论

OpenClaw 语音生态丰富但主要面向"桌面端+全功能对话"。我们的场景（手机远程控制 CC、异步播报）更简单，**Hook 驱动 + Edge TTS 的方向是对的**。

最值得借鉴的是**分句流式 TTS** — 不等全部生成完就开始播放，一个改进就能让体验质变。其次是 TTS 后端抽象，给未来升级留空间。

---

*Sources:*
- [openclaw/openclaw](https://github.com/openclaw/openclaw)
- [Purple-Horizons/openclaw-voice](https://github.com/Purple-Horizons/openclaw-voice)
- [malpern/VoxClaw](https://github.com/malpern/VoxClaw)
- [Jupiter Voice Discussion](https://github.com/openclaw/openclaw/discussions/12891)
- [Realtime Speech APIs Discussion](https://github.com/openclaw/openclaw/discussions/1655)
