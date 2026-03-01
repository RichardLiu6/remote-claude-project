# Voice Mode C1 架构分析与优化路线图

> 分析日期：2026-03-01
> 分析方法：4 位专家并行分析（架构评审、Flag 系统、优化规划、UX 设计）
> 当前状态：Voice Mode C1 已上线，Hook 驱动 + Edge TTS + WebSocket 广播

---

## 一、当前架构

```
用户发消息
    │
    ▼
┌────────────────────────────┐
│  UserPromptSubmit Hook     │  voice-inject.sh（同步）
│  检查 ~/.claude/voice-mode │
│  存在 → 注入 [voice:] 指令  │  ~200-300 input tokens/次
└────────────┬───────────────┘
             ▼
      CC 生成回复（末尾含 [voice: 中文摘要]）
             │
             ▼
┌────────────────────────────┐
│  Stop Hook                 │  voice-push.sh（async, 15s）
│  python3 提取 message      │
│  grep 提取 [voice:] 文本   │  ← 脆弱环节
│  curl POST /voice-event &  │  ← fire-and-forget
└────────────┬───────────────┘
             ▼
┌────────────────────────────┐
│  server.js /voice-event    │
│  ttsInFlight 互斥锁        │  ← 静默丢弃
│  edge-tts → MP3            │  zh-CN-XiaoxiaoNeural
│  WS 广播 \x01voice:        │
│  5min 后自动清理 MP3        │
└────────────┬───────────────┘
             ▼
┌────────────────────────────┐
│  手机浏览器                 │
│  silence.wav 预解锁         │
│  voicePlayer.play()        │
│  speaker 按钮闪绿 800ms    │
└────────────────────────────┘
```

**优势**：零 API 成本、零额外 LLM 调用、纯本地、可插拔
**限制**：无 STT、阻塞式 TTS、单一音色、无播放状态反馈

---

## 二、发现的缺陷（按严重度排序）

### 高危

| # | 缺陷 | 详情 | 影响 |
|---|------|------|------|
| 1 | **Regex 提取脆弱** | `grep -o '\[voice:[[:space:]]*[^]]*\]'` 无法匹配换行、嵌套 `]`、UTF-8 截断 | 语音内容被截断或完全提取失败 |
| 2 | **TTS 互斥锁丢语音** | `ttsInFlight` 返回 429，但 hook 的 `curl &` 不检查返回码 | 快速连续回复时语音静默消失 |

### 中危

| # | 缺陷 | 详情 | 影响 |
|---|------|------|------|
| 3 | **"零成本"被低估** | 每轮注入 ~200-300 input tokens + ~100-150 output tokens | 50 轮交互额外消耗 15-20K tokens |
| 4 | **JSON 手工拼接** | `sed 's/"/\\"/g'` 未处理 `\`、`\n`、`\r` 等字符 | 含反斜杠的路径/代码导致 JSON 解析失败 |
| 5 | **多 session 不隔离** | `~/.claude/voice-mode` 全局单文件 | 一个 session 开语音 → 所有 session 都开 |
| 6 | **CLAUDE_VOICE_MODE 从未实现** | CLAUDE.md 记载环境变量方案但代码中未使用 | 文档与实现不一致 |

### 低危

| # | 缺陷 | 详情 |
|---|------|------|
| 7 | edge-tts 网络依赖 | 无离线 fallback（macOS `say` 可用但未接入） |
| 8 | 时序问题 | CC 被中断时 Stop hook 可能提取半截话 |
| 9 | TTS 文本未清理 | Markdown 格式符号（`**`、`#`、反引号）会被朗读 |

---

## 三、Flag 系统分析

### 当前方案：全局文件检测

```
~/.claude/voice-mode  →  存在=开  不存在=关
```

- 作用域：用户级，影响所有 CC session
- 持久性：跨 session 持久，不自动清理
- 切换方式：`POST /api/voice-toggle` 或手动 `touch/rm`

### 可选方案对比

| 方案 | 原理 | 优点 | 缺点 | 推荐度 |
|------|------|------|------|--------|
| A 环境变量 | `tmux set-environment` | 天然 per-session | Hook 非 tmux 子进程，拿不到变量 | 不推荐 |
| **B Session 级 flag** | `~/.claude/voice-mode-{session}` | 简单、向后兼容 | 需清理过期文件 | **推荐** |
| C JSON 配置 | `~/.claude/voice-config.json` | 最灵活，可扩展 | Hook 需 JSON 解析 | 长期方向 |

### 建议：方案 B → 方案 C 渐进迁移

近期用 session 级 flag 文件解决隔离问题，长期迁移到 JSON 配置支持 per-session TTS 引擎、音量、语速等参数。

---

## 四、替代架构方案

### 方案 A：服务端摘要 + TTS 队列（推荐）

取消 `[voice:]` 标签，CC 正常回复。server.js 收到 Stop hook POST 后用规则提取摘要（取最后一段非代码文本前 80 字）。TTS 队列替代互斥锁。

- 优点：消除 token 消耗、消除 regex 脆弱性、消除 429 丢失
- 代价：摘要质量不如 CC 生成的精准

### 方案 B：CLAUDE.md 静态指令 + 结构化输出

把语音指令写入 CLAUDE.md（一次性加载），CC 输出 `<!-- voice: {} -->` HTML 注释，用 python3 `json.loads` 解析。

- 优点：指令只加载一次不重复注入、JSON 解析可靠
- 代价：CLAUDE.md 规则对所有 session 生效

### 方案 C：浏览器端 Web Speech API

取消服务端 TTS，前端 `speechSynthesis.speak()` 直接朗读。

- 优点：零网络依赖、零文件 I/O、延迟更低
- 代价：iOS Safari 后台不发声、中文质量不如 Edge TTS

---

## 五、优化路线图

### 第一阶段：修缺陷（~2h）

| 项目 | 改动 | 工作量 |
|------|------|--------|
| 修 JSON 拼接 | voice-push.sh 改用 `python3 -c "json.dumps()"` | 15 min |
| 修 regex 提取 | 改用 python3 正则（支持换行、嵌套） | 30 min |
| TTS 队列替代锁 | server.js `ttsInFlight` → 请求队列 | 45 min |
| TTS 文本清理 | 去除 Markdown 格式再送 edge-tts | 15 min |

### 第二阶段：核心体验提升（~3.5h）

| 项目 | 改动 | 工作量 |
|------|------|--------|
| **播放状态 UI** | CSS 脉冲动画 + 按钮状态机（静默/生成/播放/待播） | 1h |
| **分句流式播放** | hook 分句 POST + server 逐句生成 + 前端 AudioQueue | 2-3h |

"首句优先"策略：第一句限 20 字（如"搞定了，已提交"），确保 <1s 出声。

### 第三阶段：扩展功能（~3h）

| 项目 | 改动 | 工作量 |
|------|------|--------|
| TTS 后端可切换 | `generateTTS()` 抽象 + env 分发（edge/say/openai） | 1.5h |
| 智能播报分级 | flag 文件写入 L1/L2/L3，inject hook 读取选模板 | 1.5h |

分级定义：
- **L1 提示音**：固定短语（"搞定了"/"出错了"），盯屏幕时用
- **L2 摘要**：当前行为，50-80 字
- **L3 详报**：分点播报 150 字，离开屏幕/走路时用

### 第四阶段：锦上添花（~4h）

| 项目 | 改动 | 工作量 |
|------|------|--------|
| 语音历史回放 | server 保留 20 条 + 底部抽屉 UI + 播放速度控制 | 2h |
| 语音人格切换 | `~/.claude/voice-persona/` JSON 配置 | 2h |

Persona 示例：
```json
{"name": "搭档", "voice": "XiaoxiaoNeural", "style": "口语化汇报", "maxLength": 80}
{"name": "极简", "voice": "YunxiNeural", "style": "最少字说清楚", "maxLength": 20}
{"name": "教学", "voice": "XiaoxiaoNeural", "style": "分步骤解释", "maxLength": 150}
```

### 第五阶段：未来架构（预留设计）

| 项目 | 方向 |
|------|------|
| TTS Provider 抽象层 | 为 Claude Native Voice API 预留接口 |
| Session 级 JSON 配置 | `voice-config.json` 替代 flag 文件 |
| 流式 PCM 播放 | Web Audio API 替代 `<audio>` 元素 |
| 打断手势 | 单击暂停、双击跳句、摇晃停止 |

---

## 六、跨专家共识

四位专家不约而同指向的最高优先项：

1. **分句流式播放** — 首字延迟 3-5s → <1s，体验质变
2. **修 regex + JSON** — 用 python3 替代 shell 正则和手工拼接
3. **TTS 队列** — 消除静默丢语音的竞态条件
4. **播放状态 UI** — 最小投入最快见效

**核心主张**：分句流式 + 播放可视化 = 让语音从"偶尔蹦出来的附加功能"变成"持续陪伴的信息通道"

---

## 七、与 OpenClaw 的关键差异

| 维度 | OpenClaw | 我们 |
|------|---------|------|
| 定位 | 多平台 AI 助手（桌面端+全功能对话） | 手机远程控制 CC（异步播报） |
| TTS 提供商 | ElevenLabs/OpenAI/Edge TTS（三选一） | Edge TTS only（免费） |
| 触发方式 | auto 模式（off/always/inbound/tagged） | Hook 注入 + flag 文件 |
| 指令格式 | `[[tts:provider=x voice=y]]` | `[voice: 摘要文本]` |
| 文本清理 | `stripMarkdown()` 去格式 | 无（直接送 TTS） |
| 流式 | 句子级分段播放 | 整段生成完才播放 |

**结论**：OpenClaw 验证了 Edge TTS 免费方案的可行性。最值得借鉴的是分句流式 TTS 和文本清理。STT/唤醒词/WebRTC 对我们场景 ROI 太低。

---

*分析团队：arch-critic（架构评审）、flag-expert（Flag 系统）、optimization-planner（优化规划）、ux-architect（UX 设计）*
*基础研究：openclaw-voice-research 团队（framework-lead、voice-pipeline、integration-arch）*
