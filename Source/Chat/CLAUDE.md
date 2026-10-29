# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The Chat module contains LLM provider drivers for the MakerAI framework. Each driver implements provider-specific API communication, message formatting, streaming, and tool calling for a different LLM service.

## Module Structure

### Universal Connector
- `uMakerAi.Chat.AiConnection.pas` - `TAiChatConnection` component that abstracts all provider differences. Set `DriverName` property to switch providers without code changes. Manages tool integration (Shell, TextEditor, ComputerUse, Speech, Video, Vision, WebSearch, Image). `Params` is applied by RTTI to the chat **and to its sub-objects** (that is why `Voice` reaches `TtsParams.Voice`); `Voice_Format` (key of the OpenAI TTS catalog and of demo 012) is an alias of `VoiceFormat` — it used to be silently ignored because the property has no underscore. The media sub-objects (`TtsParams`, `TranscriptionParams`, `ImageParams`, `VideoParams`, `WebSearchParams`) are copied to the chat on every `Run` / `AddMessageAndRun` (`SyncMediaParams`, fix Sep 28 2026): previously, editing `C.VideoParams.Params.Values[...]` or `C.TtsParams.Voice` after creating the chat did not reach the driver (they were only copied when assigning the whole object or when changing `Params`).

### Provider Drivers
Each inherits from `TAiChat` (defined in Core):

| File | Class | Provider |
|------|-------|----------|
| `uMakerAi.Chat.OpenAi.pas` | `TAiOpenChat` | OpenAI (GPT-5.5, GPT-5.4, GPT-5.4-mini — GPT-5.x family) |
| `uMakerAi.Chat.Claude.pas` | `TAiClaudeChat` | Anthropic Claude (claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5) |
| `uMakerAi.Chat.Gemini.pas` | `TAiGeminiChat` | Google Gemini (gemini-3.1-pro, gemini-3-flash, gemini-3.1-flash-lite — 3.x family) |
| `uMakerAi.Chat.Ollama.pas` | `TAiOllamaChat` | Ollama (local models) |
| `uMakerAi.Chat.LMStudio.pas` | `TAiLMStudioChat` | LM Studio (local OpenAI-compatible) |
| `uMakerAi.Chat.Groq.pas` | `TAiGroqChat` | Groq inference (llama, qwen, deepseek, voxtral) |
| `uMakerAi.Chat.DeepSeek.pas` | `TAiDeepSeekChat` | DeepSeek (deepseek-flash, deepseek-v4-pro) |
| `uMakerAi.Chat.Mistral.pas` | `TAiMistralChat` | Mistral (large, magistral, devstral, voxtral) |
| `uMakerAi.Chat.Kimi.pas` | `TAiKimiChat` | Kimi/Moonshot (kimi-k3, kimi-k2.6/k2.7) |
| `uMakerAi.Chat.GLM.pas` | `TAiGLMChat` | GLM / Zhipu Z.ai (glm-4.7, glm-4.7-flash, glm-5.x, glm-5v/4.6v vision) |
| `uMakerAi.Chat.Qwen.pas` | `TAiQwenChat` | Qwen / Alibaba Model Studio (qwen3.8-flash/max, qwen3.7-plus, qwq-plus, qwen3-coder, qwen3-vl) |
| `uMakerAi.Chat.Grok.pas` | `TAiGrokChat` | xAI Grok (grok-4.3, grok-4.5, grok-build) |
| `uMakerAi.Chat.Cohere.pas` | `TCohereChat` | Cohere (command-a, aya-vision) |
| `uMakerAi.Chat.GenericLLM.pas` | `TAiGenericChat` | Any OpenAI-compatible API |

### Configuration
- `uMakerAi.Chat.Initializations.pas` - Driver registration and model capabilities. Uses `TAiChatFactory` to configure `ModelCaps`, `SessionCaps`, `Tool_Active`, `ThinkingLevel` per model. **Last update: May 2026.**

### Legacy (Deprecated)
- `uMakerAi.Chat.OpenAi_Deprecated.pas`
- `uMakerAi.Chat.Ollama_old.pas`, `uMakerAi.Chat.Ollama_old1.pas`
- `uMakerAi.Chat.Claude_beta.pas`

---

## Capability System (v3.3 — new)

### Central concept
Two properties of type `TAiCapabilities` (a set of `TAiCapability`) replace the four legacy params:

| Property | Description | Syncs to (legacy) |
|-----------|-------------|----------------------|
| `ModelCaps` | Native capabilities of the model via completions | `NativeInputFiles` + `ChatMediaSupports` |
| `SessionCaps` | Desired capabilities in the session | `NativeOutputFiles` + `EnabledFeatures` |

**Gap = SessionCaps − ModelCaps** → determines which bridge/tool the internal orchestrator activates automatically.

### TAiCapability enum
```delphi
TAiCapability = (
  // Input / Understanding
  cap_Image, cap_Audio, cap_Video, cap_Pdf,
  cap_WebSearch, cap_Reasoning, cap_CodeInterpreter,
  cap_Memory, cap_TextEditor, cap_ComputerUse, cap_Shell,
  // Output / Generation (gap → activates bridge)
  cap_GenImage, cap_GenAudio, cap_GenVideo, cap_GenReport, cap_ExtractCode
);
```

### Common configuration patterns

```delphi
// Text model + tools (default for most)
RegisterUserParam('Driver', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'SessionCaps', '[]');

// Model with native vision
RegisterUserParam('Driver', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Driver', 'SessionCaps', '[cap_Image]');

// Model with reasoning
RegisterUserParam('Driver', Model, 'ModelCaps',    '[cap_Reasoning]');
RegisterUserParam('Driver', Model, 'SessionCaps',  '[cap_Reasoning]');
RegisterUserParam('Driver', Model, 'ThinkingLevel', 'tlMedium');

// TTS via dedicated endpoint (Gap=[cap_GenAudio] → InternalRunSpeechGeneration)
RegisterUserParam('Driver', Model, 'ModelCaps',   '[]');
RegisterUserParam('Driver', Model, 'SessionCaps', '[cap_GenAudio]');
RegisterUserParam('Driver', Model, 'Tool_Active', 'False');

// Image generation via dedicated endpoint (Gap=[cap_GenImage])
RegisterUserParam('Driver', Model, 'ModelCaps',   '[]');
RegisterUserParam('Driver', Model, 'SessionCaps', '[cap_GenImage]');
RegisterUserParam('Driver', Model, 'Tool_Active', 'False');
```

### Compatibility with the legacy system
`EnsureNewSystemConfig` automatically translates the legacy params (`NativeInputFiles`, `ChatMediaSupports`, `EnabledFeatures`, `NativeOutputFiles`) to the new system on the first `Run`. Models with the old configuration keep working without changes. If `ModelCaps`/`SessionCaps` are assigned explicitly, `FNewSystemConfigured=True` and the automatic translation is skipped.

---

## Key Patterns

### Driver Implementation
All drivers implement these core methods:
- `Run()` - Execute chat completion (sync or async). Calls `EnsureNewSystemConfig`, applies the prompt sanitizer, then delegates to the private orchestrator `RunNew()`. Full chain: `AddMessageAndRun → Run → RunNew`.
- `GetMessages()` - Serialize message history to provider-specific JSON format
- `ParseChat()` - Parse provider response into `TAiChatMessage`
- `GetModels()` - Retrieve available models from API

Streaming drivers additionally implement:
- `ProcessStreamChunk()` - Handle SSE/streaming response chunks
- `OnInternalReceiveData` / `OnInternalReceiveDataEnd` - Event callbacks

### Parameter Registry
Model capabilities are configured via `TAiChatFactory.Instance.RegisterUserParam()`:
```delphi
// Global driver defaults
TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Max_Tokens', '8000');
TAiChatFactory.Instance.RegisterUserParam('Ollama', 'ModelCaps',  '[]');
TAiChatFactory.Instance.RegisterUserParam('Ollama', 'SessionCaps','[]');

// Model-specific overrides
TAiChatFactory.Instance.RegisterUserParam('Ollama', 'qwen3:latest', 'ModelCaps',    '[cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('Ollama', 'qwen3:latest', 'ThinkingLevel', 'tlMedium');
```

Key parameters:
- `ModelCaps` / `SessionCaps` — **new v3.3 system** (preferred)
- `NativeInputFiles` / `NativeOutputFiles` — physical, legacy (still supported)
- `ChatMediaSupports` / `EnabledFeatures` — logical, legacy (still supported)
- `Tool_Active` — enables function calling
- `ThinkingLevel` — reasoning level (`tlLow`, `tlMedium`, `tlHigh`)
- `Max_Tokens` — maximum response tokens
- `Temperature` — sampling temperature

### Chat State Machine
Drivers follow states in `TAiChatState`:
```text
acsIdle → acsConnecting → acsReasoning → acsWriting → acsToolCalling → acsFinished/acsError
```

### Tool Calling Flow
1. Message sent with tool definitions
2. Model responds with `tool_use` block
3. `OnCallToolFunction` event fires
4. Tool result appended to messages
5. `Run()` called again for final response

---

## Dependencies

- `uMakerAi.Core.pas` - Base types (`TAiMediaFile`, `TAiFileCategory`, `TAiChatState`, `TAiCapability`)
- `uMakerAi.Chat.pas` - Abstract `TAiChat` base class (`ModelCaps`, `SessionCaps`). Public API: `AddMessageAndRun`, `Run`. `RunNew` is private (the internal 3-phase orchestrator).
- `uMakerAi.Chat.Messages.pas` - `TAiChatMessage`, `TAiChatMessages`
- `uMakerAi.Tools.Functions.pas` - `TAiFunctions`, `TAiToolsFunction`
- `uMakerAi.ParamsRegistry.pas` - `TAiChatFactory` for model configuration

---

## Adding a New Driver

1. Create `uMakerAi.Chat.NewProvider.pas`
2. Define class inheriting from `TAiChat`
3. Implement `Run()`, `GetMessages()`, `ParseChat()`, `GetModels()`
4. Register in `uMakerAi.Chat.Initializations.pas` initialization section
5. Configure capabilities via `TAiChatFactory.Instance.RegisterUserParam()`:
   ```delphi
   TAiChatFactory.Instance.RegisterUserParam('NewProvider', 'Max_Tokens',  '16000');
   TAiChatFactory.Instance.RegisterUserParam('NewProvider', 'Tool_Active', 'True');
   TAiChatFactory.Instance.RegisterUserParam('NewProvider', 'ModelCaps',   '[cap_Image]');
   TAiChatFactory.Instance.RegisterUserParam('NewProvider', 'SessionCaps', '[cap_Image]');
   ```

---

## Provider-Specific Notes

### Claude (Anthropic)
- `x-anthropic-version` header + beta features via dynamic headers
- **Thinking by family (Aug 2026, runtime-tested):** the driver classifies the model with `IsClaudeAdaptiveOnly` (4.7/4.8/5: budget_tokens and temperature/top_p/top_k return 400) and `IsClaude46` (4.6). On 4.6+ it sends `thinking:{type:"adaptive"}` and maps `ThinkingLevel` → `output_config.effort` (low/medium/high); on ≤4.5 it keeps `{enabled, budget_tokens}`. The `interleaved-thinking` header is only sent on the legacy path.
- `output_format` migrated to `output_config.format` (deprecated API-wide); format and effort share the same `output_config` object
- Web search: `web_search_20260209` (dynamic filtering) on 4.6+; `web_search_20250305` on legacy
- `stop_reason:"refusal"` (opus-5/fable-5 classifiers): marks `IsRefusal`, parses `stop_details` (category/explanation) and fires `OnError`
- **Aug 2026 phase (runtime-tested except Fast mode):**
  - `FastMode` — `speed:"fast"` + beta `fast-mode-2026-02-01`, only opus-5/4.8 (on others it is ignored with a log). WARNING: research preview with its own rate limit; requires org quota (the test org has 0 TPM allocated → 429)
  - `{role:"system"}` messages mid-conversation in the history (they preserve the prompt cache): they pass straight through on opus-5/4.8/fable/mythos; on models without support (sonnet-5, 4.6…) they are automatically degraded to a `user` turn wrapped in `<system-reminder>`. Usage: `AddMessage(text, 'system')` after a user turn + `Run(nil)`
  - `EnableCompaction` — beta `compact-2026-01-12` + `context_management.edits[compact_20260112]` (merged with `FContextConfig` if it exists); the received `compaction` blocks are preserved (`FCompactionBlocks`) and forwarded intact at the start of the corresponding assistant message
  - `RefusalFallbackModel` — beta `server-side-fallback-2026-06-01` + `fallbacks:[{model}]`: on a refusal the API retries on that model in the same call (the only supported target today: `claude-opus-4-8`)
- Citations (native RAG): partial support implemented

**September 2026 generation (revised Sep 29/2026 against the official reference and live-tested):** `claude-opus-5-5` ($4/$20, CHEAPER successor to Opus 5; default effort **medium**), `claude-sonnet-5-5` ($2/$10) and `claude-fable-5-1` ($10/$50, 30-day retention same as Fable 5). Breaking changes handled by the driver: thinking **cannot be turned off** (the driver never sends `disabled`), and **forcing a tool (`tool_choice` any/tool) returns 400** → `IsClaudeNoForcedTool` downgrades it to `auto` with a `LogDebug`. `claude-sonnet-5-5` does accept `system` messages mid-conversation. Effort ladder: `tlXHigh` → `xhigh` (only 4.7+; on 4.6 it requests `high`), `tlMax` → `max`, `tlMinimal`/`tlNone` → `low`. **There is no Haiku 5**: `claude-haiku-4-5` is still the current Haiku and remains the driver default.

**Active models (Aug 2026, all registered):**
- `claude-opus-5` — **RECOMMENDED**, successor to 4.8 at the same price ($5/$25), thinking on by default, 1M ctx / 128K out
- `claude-sonnet-5` — best price/quality, almost-Opus on code/agents ($3/$15; intro $2/$10 until Aug 31/2026); new tokenizer ~30% more tokens than 4.6. RUNTIME-TESTED
- `claude-fable-5` — top capability ($10/$50); **requires 30-day data retention** (ZDR → 400 on every request); thinking always on
- `claude-opus-4-8`, `claude-opus-4-7` — Opus 4.x generations (same adaptive-only surface)
- `claude-sonnet-4-6`, `claude-opus-4-6` — previous generation (adaptive recommended, budget deprecated). Opus 4.6 RUNTIME-TESTED with adaptive
- `claude-haiku-4-5-20251001` — speed/cost, 200K ctx; legacy budget path RUNTIME-TESTED

**Retired/deprecated:** `claude-opus-4-1` and `claude-opus-4-1-20250805` **RETIRED on Aug 5 2026** → aliases of `claude-opus-5-5`; `claude-sonnet-4-20250514` / `claude-opus-4-20250514` (TBD)

### OpenAI
**GPT-6 family (revised Sep 29/2026 against the official doc and live-tested):** `gpt-6-astra` ($10/$50, OpenAI's "general-purpose" model), `gpt-6-sol` ($2/$10, code and agents) and `gpt-6-luna` ($0.10/$0.50, high volume). 1.05M ctx / 128K out, text+image, `reasoning.effort` none/low/medium/high/xhigh/max (default medium) — **no `minimal`**: `OpenAiEffort` requests it as `low`. **Driver default: `gpt-6-sol`** (previously `gpt-5.1` in `TAiChatConnection` and, due to a bug, **`gpt-5` in the direct component**: the `TAiChat` constructor leaves `gpt-5` and the `if Model = ''` in `TAiOpenChat` was never satisfied; `gpt-5` shuts down on Dec 11 2026). `TAiMakerAiChat` inherits from `TAiOpenChat`: its constructor sets `mk-gpt-oss-20b`, same as `RegisterDefaultParams`. `gpt-5.1` is still active. `ModelRequiresDefaultSampling`/`ModelUsesMaxCompletionTokens` cover `gpt-6` (Azure/GenericLLM Chat Completions path).

**GPT-5.6 family (July 2026 — current production):** 1.05M context, 128K output, vision + reasoning + tools + prompt caching across the whole family. The `gpt-5.6` alias routes to Sol.
- `gpt-5.6-sol` — Flagship. `ModelCaps=[cap_Image, cap_Reasoning]`, `ThinkingLevel=tlHigh`
- `gpt-5.6-terra` — Cost/capability balance. `ThinkingLevel=tlMedium`
- `gpt-5.6-luna` — Economy tier (runtime-tested Aug 2026). `ThinkingLevel=tlLow`
- Jul 30/2026 prices: Luna −80%, Terra −20%; "Fast mode" replaces Priority Processing (2.5× speed, 2× price, Sol only)

**GPT-5.x family (May 2026):**
- `gpt-5.4` — Standard production, vision + tools, 1M context. `ModelCaps=[cap_Image]`
- `gpt-5.4-mini` — Fast and cheap, vision + tools. `ModelCaps=[cap_Image]`
- `gpt-5.5` — vision + reasoning. `ModelCaps=[cap_Image, cap_Reasoning]`, `ThinkingLevel=tlMedium`
- `gpt-5.5-pro` — Intensive reasoning. `ModelCaps=[cap_Image, cap_Reasoning]`, `ThinkingLevel=tlHigh`

**Multimedia capabilities (model names unchanged):**
- Image generation: `gpt-image-1` (and `gpt-image-1.5` / `gpt-image-2`) → `SessionCaps=[cap_GenImage]`
- TTS: `gpt-4o-mini-tts` → `SessionCaps=[cap_GenAudio]`
- Transcription: `gpt-transcribe` (recommended, WER 8.98%), `gpt-live-transcribe` (live/Realtime), `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1` → `ModelCaps=[cap_Audio]`
- Video: Sora → `SessionCaps=[cap_GenVideo]`
- Web search: `gpt-4o-search-preview` → `ModelCaps=[cap_WebSearch]`, `Tool_Active=False`

**Deprecated (Feb 2026):** GPT-4.1, GPT-4o (chat), o3, o4-mini — kept in the code for backward compatibility but not recommended for new projects.

### Gemini (Google)

**Revised Sep 29/2026 against the official doc (NO runtime test: no API key).** Default of the driver, of `TAiGeminiSpeechTool` (transcription) and of `TAiGeminiWebSearchTool`: **`gemini-3.8-flash`**; default TTS: **`gemini-3.8-flash-tts`**.
- `gemini-3.8-flash` (stable, Sep 2026) and `gemini-3.7-flash` (stable, Aug 2026, code-oriented): 1M ctx / 65K out, text/image/video/audio/PDF input, tools, search, code execution, computer use (preview). **Thinking is low/medium/high only: `minimal` errors out and cannot be turned off** — the driver maps `tlMinimal`/`tlNone` to `LOW` and `tlXHigh`/`tlMax` to `HIGH`
- TTS `gemini-3.8-flash-tts` and `gemini-3.8-flash-lite-tts` (stable, Sep 22/2026; official replacement for `gemini-2.5-flash-preview-tts`). The doc presents the new `/v1beta/interactions` API; the migration guide still covers `generateContent`, which is what the driver and `TAiGeminiSpeechTool` use. **Verify at runtime when a key is available**
- The sampling gate compares the **version** (`GeminiModelVersion` ≥ 3.5), not a list of names: it covers 3.7, 3.8 and whatever comes next
- Not registered yet (different API or unused in the driver): `gemini-3.5-transcribe`, `gemini-3.8-live`, `gemini-3.5-live-translate-preview`, `gemini-embedding-2-preview`, Lyria, Deep Research, `antigravity-preview-09-2026`

**3.5/3.6 family (Jul 2026, registered WITHOUT a runtime test):**
- `gemini-3.5-flash` (GA May 19/2026, alias `gemini-flash-latest`) — flash flagship, frontier agentic/coding; Computer Use tool in public preview for this model. `ThinkingLevel=tlMedium`
- `gemini-3.6-flash` (GA Jul 21/2026) — better token efficiency and agentic planning, cheaper than 3.5 Flash. `ThinkingLevel=tlMedium`
- `gemini-3.5-flash-lite` (GA Jul 21/2026) — low latency, subagents. `ThinkingLevel=tlLow`
- **Sampling params deprecated on 3.5+/3.6/omni** (Jul 21/2026): the driver automatically omits `temperature`/`topP` for those models
- `gemini-3.5-pro` does NOT exist yet (announced at I/O, delayed — Reuters Jul 16)

**Previous 3.x family (still active):**
- `gemini-3.1-pro-preview` — flagship pro, 2M context. `ThinkingLevel=tlHigh`
- `gemini-3-flash-preview`, `gemini-3.1-flash-lite` — previous generation

**Specialized models:**
- Image (**Nano Banana** family, GA May-Jun 2026): `gemini-3.1-flash-image` (NB 2, with video-to-image), `gemini-3-pro-image` (NB Pro), `gemini-3.1-flash-lite-image` (NB 2 Lite, ultra-fast). The earlier `-preview` ones remain registered
- `gemini-3.1-flash-tts-preview` — TTS; since Jun 17/2026 it supports streaming (`streamGenerateContent`)
- `veo-3.1-generate-preview` — video. **veo-2.0 and veo-3.0 SHUT DOWN on Jun 30 2026** (the tool enum is kept for DFM compatibility)
- `gemini-omni-flash-preview` — 3-10s 720p video (preview Jun 30/2026)
- `gemini-embedding-2` (GA Apr 2026) — multimodal embedding, 3072 dims

**Shut down/deprecated:**
- **Imagen 4.0 (`imagen-4.0-*-generate-001`): SHUTDOWN Aug 17 2026** — the three names remain as **aliases** of `gemini-3.1-flash-image` (Nano Banana 2) with their caps: they move from `:predict` to completions with image
- `gemini-3-pro-preview`: **shut down** — alias of `gemini-3.1-pro-preview` (and `aa_gemini-3-pro-fast` points directly to the successor: `GetBaseModel` does not chain aliases)
- `gemini-2.0-flash(-lite)`: shut down Jun 1 2026 (they were the default of the transcription and search tools)
- **2.5 family (`gemini-2.5-flash`, `-lite`, `-pro`, TTS): NOT shut down, LIMITED** to accounts that already used it (the previous note said "closed Jun 17 2026", that was incorrect). For a new user it fails, which is why it stopped being the default. They remain registered, with `aa_gemini-3.8-flash-pdf/-code-interpreter/-web-search` profiles as replacements for the `aa_gemini-2.5-*`
- `gemini-2.5-flash-image`: shuts down on **Oct 2 2026** (replacement: `gemini-3.1-flash-image`); turn it into an alias after that date
- **Watch out for existing DFMs**: they store `Model` with the old value (`gemini-2.0-flash` in the tools); the default change only affects new components

**Other:**
- Native grounding: the driver manages `groundingSupports` automatically

### Groq (fast inference)
**Updated Aug 2026, runtime-tested 4/4.** Two MUTUALLY exclusive reasoning systems (prefix gating in the driver): `openai/gpt-oss-*` uses `include_reasoning` + `reasoning_effort` low/medium/high; `qwen/*` uses `reasoning_format` parsed/raw/hidden + `reasoning_effort` default/none (without `parsed` the `<think>` arrives raw in content).
- Text: `openai/gpt-oss-20b` (driver default since Sep 2026), `openai/gpt-oss-120b`, `qwen/qwen3.8-27b`. **Retired Sep 2026** (`model_not_found`): `llama-3.1-8b-instant` and `llama-3.3-70b-versatile`, with aliases to `gpt-oss-20b` and `gpt-oss-120b` so as not to break previous code. The `qwen/qwen3.6|3.8-27b` accept at most `Max_Tokens=16384` (the API rejects more with 400); `qwen3.6` was registered with 40960 and did not respond
- Reasoning: `openai/gpt-oss-120b/20b` (tested), `qwen/qwen3.6-27b` (new Aug 2026, replaces qwen3-32b — alias registered; tested)
- **Groq has NO vision currently**: llama-4-scout/maverick retired and gpt-oss-120b is text-only ("content must be a string" with images — verified; cap_Image removed from the registry)
- RETIRED Aug 2026: `qwen/qwen3-32b`, `llama-4-scout`, `moonshotai/kimi-k2-instruct(-0905)`
- Agentic: `groq/compound`/`-mini` **not available** (Sep 2026: `model_not_found` and not in `GET /models`); no alias on purpose, because there is no replacement with web search
- TTS: `canopylabs/orpheus-v1-english`/`-arabic-saudi` → `SessionCaps=[cap_GenAudio]` (playai-tts removed 12/31/25)
- STT: `whisper-large-v3/turbo` → `ModelCaps=[cap_Audio]`, `Tool_Active=False`
- Arabic: `allam-2-7b` (4K ctx, no tools); prompt-guard-2 are classifiers, not chat

### Mistral
**Active models (Jun 2026):**
- `mistral-large-latest` → Large 3 (v25.12), 256K ctx, vision + tools. Inherits the `[cap_Image]` defaults
- `mistral-medium-latest` → **Medium 3.5** (v26.04), 256K ctx, vision + reasoning_effort + tools. `ModelCaps=[cap_Image,cap_Reasoning]`, `ThinkingLevel=tlMedium`
- `mistral-small-latest` → **Small 4** (v26.03), 256K ctx, vision + reasoning_effort + tools. `ModelCaps=[cap_Image,cap_Reasoning]`, `ThinkingLevel=tlMedium`
- Ministral: `ministral-14b/8b/3b-latest` → 262K ctx, vision + tools. Inherits the defaults
- Dedicated reasoning: `magistral-medium/small-latest` → `ModelCaps=[cap_Reasoning]`, `ThinkingLevel=tlMedium` (uses `prompt_mode: 'reasoning'`)
- Code: `devstral-latest` / `devstral-small-latest` → `ModelCaps=[]` (no vision)
- STT: `voxtral-mini/small-latest` → `ModelCaps=[cap_Audio]`, `Tool_Active=False`
- **TTS: `voxtral-mini-tts-2603`** (Mar 2026, RUNTIME-TESTED Aug 2026) → `SessionCaps=[cap_GenAudio]` activates `InternalRunNativeSpeechGeneration` (POST `/v1/audio/speech`). The API **requires** `voice` (slug from the `GET /v1/audio/voices` catalog: `en_paul_neutral`/happy/sad…, `gb_oliver_neutral`, `gb_jane_sarcasm`) or `ref_audio`; properties `TtsVoice` (default `en_paul_neutral`) and `TtsFormat` (mp3/wav/pcm/flac/opus). Multilingual model with any voice
- OCR: `mistral-ocr-latest` → `/v1/ocr` endpoint, `SessionCaps=[cap_Pdf]`, `Tool_Active=False`. **OCR 4** (`mistral-ocr-4-0`, Jun 2026): the alias already points to it; new `OcrIncludeBlocks` property (structural blocks with bounding boxes per page) and `pages` accepts ranges (`"0-5"`)
- Devstral 2 (`devstral-2512`) and Magistral 1.2 (`magistral-*-2509`) are covered by the `-latest` aliases

**Reasoning in the driver:**
- Magistral → `prompt_mode: 'reasoning'` (chain-of-thought visible in the response)
- Small 4 / Medium 3.5 → `reasoning_effort: 'low'|'medium'|'high'` according to `ThinkingLevel`

### xAI Grok
**Updated Aug 2026, runtime-tested 6/6.** Full catalog turnover: the current family (grok-4.x, grok-build) **always reasons** (`reasoning_content` captured by the base) and does NOT accept `frequency/presence/stop` or `reasoning_effort` (prefix gate in the driver); logprobs not supported on 4.20+.
- `grok-4.3` [driver default]: 1M ctx, vision + reasoning (tested). $1.25/$2.50 per M (<200K; 2x over 200K)
- `grok-4.5` [premium]: 500K ctx, vision + reasoning (tested). $2/$6 per M
- `grok-4.20-0309-reasoning`/`-non-reasoning`/`-multi-agent-0309`: 1M ctx
- `grok-build-0.1`: coding with reasoning (tested), 256K ctx. $1/$2 per M
- Image: `grok-imagine-image` ($0.02) / `-image-quality` ($0.05) → `SessionCaps=[cap_GenImage]`
- Video: `grok-imagine-video` ($0.05/s) / `-video-1.5` ($0.08/s) → `SessionCaps=[cap_GenVideo]`. **Implemented and tested**: `InternalRunNativeVideoGeneration` (asynchronous job `POST /videos/generations` + polling `GET /videos/{id}` + mp4 download as a `TAiMediaFile`); duration via the `VideoDurationSeconds` property (default 5, max 15)
- **RETIRED Aug 2026**: the entire grok-3 family, grok-4-0709, grok-4-fast-*, grok-4-1*, grok-code-fast-1, grok-2-vision, grok-2-image, grok-imagine-image-pro. Registered aliases: grok-3/grok-4/grok-4-0709 → grok-4.3; grok-code-fast-1 → grok-build-0.1; grok-2-image(-1212) → grok-imagine-image; -image-pro → -image-quality (tested via alias)

### DeepSeek
**Updated Aug 2026, runtime-tested 4/4 (incl. tools in thinking mode).** V4 (Apr 2026) are the only models in `/v1/models`: 1M ctx / 384K output. The API turns thinking **on by default** (effort=high); the driver controls it explicitly in `InitChatCompletions`: `cap_Reasoning` in `ModelCaps` → `thinking:{type:enabled}` + `reasoning_effort` (tlLow=low, tlMedium=high, tlHigh=max); without the cap → `thinking:{type:disabled}` (fast/cheap mode). In thinking mode the API ignores temperature/top_p/penalties without error. With tools, `reasoning_content` MUST be forwarded in the history (400 if missing) — the driver's `GetMessages` override already does this.
- **RENAME Sep 2026 (runtime-verified):** `/v1/models` now only lists `deepseek-flash` and `deepseek-v4-pro`. `deepseek-v4-flash` (and `deepseek-v4-flash-vision-exp`) are still accepted as aliases but those models **were retired** and route to the new flash. The driver default is now `deepseek-flash`; the legacy alias remains registered for old configurations.
  - **PITFALL:** the gate for the `thinking` block was on `StartsText('deepseek-v4', LModel)`, so with the canonical name `deepseek-flash` `thinking` was NOT sent and the API default (thinking ON) was applied → reasoning tokens were billed with `ModelCaps=[]`. It is now decided in `ModelSupportsThinking()`, which covers `deepseek-v4*`, `deepseek-flash*` and the aliases in grace
- `deepseek-flash` [driver default]: peak $0.30/M in miss / $0.003 hit / $1.20/M out
- `deepseek-v4-pro`: 1.6T (49B act), reasoning by default via the registry. Peak $1.32/M in miss / $3.96/M out. **CONTINUES after Sep 14 2026** (official notice, billing unchanged). Note: effort low→high (minimum supported, Aug 2026)
- `deepseek-chat` and `deepseek-reasoner`: **officially RETIRED Jul 24 2026** — they still route to `deepseek-flash` in grace (verified Sep 2026); do not depend on them
- No vision in the public API
- WARNING: the **peak/off-peak rate is already in effect**: off-peak you pay half; peak hours 01:00-04:00 and 06:00-10:00 **UTC** (Mon-Fri)

### Kimi (Moonshot AI)
**Updated Aug 2026, runtime-tested 4/4.** CRITICAL RULE discovered empirically: the new family (k3/k2.6/k2.7) returns **400 if the request includes `top_p`** (it only accepts `temperature`) — the global `top_p` default was removed from the registry and the constructor sets `Top_p := 0`. All new models return `reasoning_content` and need a generous `max_tokens` (with a short budget the reasoning consumes it and `content` arrives empty with `finish=length`).
- `kimi-k3` (Jul 16/2026): **flagship and driver default**, 1M ctx, vision + reasoning (tested). Flat price: $3/M input, $0.30/M cache-hit, $15/M output
- `kimi-k2.7-code` / `-highspeed`: multimodal coding (tested — generates correct Delphi)
- `kimi-k2.6`: vision + text + tools (tested)
- `kimi-latest`: moving alias
- `kimi-k2.5`: **RETIRES Aug 31 2026** → migrate to kimi-k3
- `kimi-k2` and `kimi-k2-thinking`: **ALREADY RETIRED** from the API (entries removed from the registry)
- `moonshot-v1-*` (+vision-preview): **TOTAL SUNSET Aug 31 2026**

### GLM (Zhipu AI / Z.ai)
**Registered Aug 2026, capabilities verified against the official docs; NO runtime test yet.** OpenAI-compatible API; international endpoint `https://api.z.ai/api/paas/v4/` (mainland China: `open.bigmodel.cn/api/paas/v4/` — change `URL`). Key: `@GLM_API_KEY`.
- **Thinking ON by default in the API** (glm-4.7/5.x): the driver controls it explicitly like DeepSeek V4 — `cap_Reasoning` → `thinking:{enabled}`; without the cap → `disabled` (fast mode). **EXCEPTION: `glm-5.3` uses forced thinking and does NOT accept disabled** (the driver always sends enabled for 5.3, command-a-plus pattern).
- `reasoning_effort`: values **low/high/max** (API default: max), documented ONLY on glm-5.2/5.3 — the driver sends it only there (mapping tlLow→low, tlMedium→high, tlHigh→max, same as DeepSeek).
- **Z.ai REQUIRES forwarding `reasoning_content` in the multi-turn history** ("remember to return the historical reasoning_content") — the driver's `GetMessages` override does this. Capture in parse/streaming: the base.
- `tool_choice`: the API **only supports `'auto'`**. Limited sampling (clamped in the driver): `temperature` [0,1], `top_p` [0.01,1], `max_tokens` ≤131072 (real max output 128K; 16K on 4.5v). Penalties/n/logprobs/seed are not sent.
- Text: `glm-4.7` [driver default] (200K ctx, $0.60/$2.20); `glm-4.7-flash` **FREE**; `glm-4.7-flashx` ($0.07/$0.40); `glm-5.3` (1M ctx, flagship coding, $1.40/$4.40), `glm-5.2` (1M ctx), `glm-5.1` (8h agents), `glm-5` (200K, $1.00/$3.20) → all `[cap_Reasoning]` `tlMedium`; `glm-5-turbo` (200K, $1.20/$4.00, no cap = fast)
- Vision (image/video/file input, OpenAI `image_url` format; `video_url`/`file_url` not wired yet): `glm-5v-turbo` (200K, with tools), `glm-4.6v` ($0.30/$0.90, **first V family with native function calling**), `glm-4.6v-flash` **FREE**, `glm-4.6v-flashx` ($0.04/$0.40) → `[cap_Image]`; `glm-4.5v` → `[cap_Image]` + **`Tool_Active=False`** (no FC, max output 16K)
- Phase 2 pending: GLM-Image (gen), GLM-OCR, GLM-ASR (STT), CogVideoX-3 (video) — dedicated endpoints

### Qwen (Alibaba Model Studio / DashScope)
**New Sep 28 2026, runtime-tested (sync, async, reasoning on/off, tools sync and async, vision, qwq-plus; phase 2: image, TTS, ASR, native audio, embeddings and rerank).** OpenAI-compatible API; international (Singapore) endpoint `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/` (US `dashscope-us…`, China `dashscope.aliyuncs.com…` — change `URL`). Key: `@DASHSCOPE_API_KEY`, **bound to the region where it was created** (another region → 401). Pay-as-you-go billing against the card: no balance top-up.
- **Reasoning ON by default in the API** on the hybrids (qwen3.x, qwen-plus/flash/turbo, qwen3-max, VL, omni). The driver ALWAYS sends `enable_thinking`: `cap_Reasoning` → true; without the cap → false (fast, no reasoning tokens). The hybrids are registered without the cap. `ThinkingLevel` → `thinking_budget` (tlLow 1024, tlMedium 4096, tlHigh 16384; tlDefault no limit). `reasoning_content` is captured by the base (sync and streaming).
- Reasoning-only (`qwq-*`, `*-thinking-*`): `enable_thinking` is not sent to them. **`qwq-plus` only responds in streaming** (without stream it returns empty with no error) → registered `Asynchronous=True`.
- Open weights (`qwen3-32b`, `qwen3.6-27b`, `qwen3-235b-a22b…`, detected by the size in the name): `enable_thinking=true` only in streaming (400 in sync) → in sync the driver sends false.
- Streaming: `stream_options.include_usage` so the tokens arrive. Tools + stream work. `temperature` clamped to [0, 2).
- Catalog (only what was tested; any other id among the account's ~170 works with the global settings): vision `[cap_Image]` → `qwen3.8-flash` [default], `qwen3.8-max`, `qwen3.7-plus`, `qwen3-vl-flash`, `qwen3.8-omni-flash` (tested with image only); text → `qwen3-max`, `qwen-plus`, `qwen-flash`, `qwen-turbo`; code → `qwen3-coder-plus/flash`; reasoning `[cap_Reasoning]` → `qwq-plus`, `qwen3-235b-a22b-thinking-2507`.
- Empty `Model` (general fix Sep 28 2026): previously a connection without `Model` used the driver's default model **without** its catalog parameters (Qwen without `cap_Image`: the image was not sent). Now `GetDriverParams` resolves the model level with the default; see the registry section in `Source/Core/CLAUDE.md`.
- **Audio input: the API requires a data URI** in `input_audio.data` (`data:audio/wav;base64,…`); the bare base64 from the common serializer gives 400 *"URL does not appear to be valid"*. `InitChatCompletions` rewrites it (`FixAudioDataUris`). With that, `qwen3.8-omni-flash` (`[cap_Image, cap_Audio]`) understands native audio, sync and stream.
- **Phase 2 (Sep 28 2026), runtime-tested from Delphi** — by capability gap, like the rest of the drivers. All three use their own HTTP client (synchronous even with `Asynchronous=True`; in async the result arrives via `OnReceiveDataEnd` with the media, same as Grok/Mistral). If the session `Model` is not from the family, the task default is used (`ModelFor`), so the bridge works from a chat model:
  - `[cap_GenImage]` → native API `api/v1/services/aigc/multimodal-generation/generation` (synchronous, returns URLs that expire in 24 h; the driver downloads them as `qwen_image_N.png`). Registered: `qwen-image-3.0` [task default], `qwen-image-3.0-pro`, `qwen-image-2.0(-pro)`, `qwen-image-max`, `z-image-turbo` (~6 s), `wan2.7-image(-pro)`. `qwen-image-3.0` takes ~50 s. Size in `ImageParams.Params.Values['size']` (default `1024*1024`, accepts `1024x1024`); `qwen-image-plus` only supports 1328*1328, 1664*928, 928*1664, 1472*1104, 1104*1472. Also `negative_prompt` and `watermark` in `ImageParams.Params`; `N` > 1 requests several.
  - **Image editing** (same API and same gap): the images attached to the prompt (**1 to 3**; 4 → error before calling) are the input and travel as data URIs. They reach generation intact because `cap_Image` is not in the gap of an image model. Registered `qwen-image-edit-plus` [default when editing, ~9 s], `qwen-image-edit` (~17 s), `qwen-image-edit-max` (~40 s); `qwen-image-2.0/3.0` and `wan2.7-image` also edit. **`z-image-turbo` does not edit** (the driver fails with a clear message). **Without an explicit `size`, no size is sent when editing**: the model preserves the aspect ratio (1024×576 → 1376×768); forcing 1024*1024 would distort it. From a chat model (`SessionCaps` `[cap_Image, cap_GenImage]`), attaching an image and requesting the change edits with the default. The body is built by `BuildImageRequest` (protected; the suite tests it without network).
  - `[cap_GenAudio]` → same native API with `input {text, voice, language_type}` → WAV (`qwen_tts.wav`). `qwen3-tts-flash` [default], `qwen3-tts-instruct-flash`. Voice in `TtsParams.Voice` (default `Cherry`; also `Ethan`…), language in `TtsParams.Language` (`es` or `Spanish`; empty = `Auto`).
  - Transcription → `qwen3-asr-flash` via `chat/completions` with `input_audio` (data URI) and `asr_options`. In **`cmTranscription`** the transcription is the response (`ParseJsonTranscript`) and the `Prompt` travels as **context** for the recognizer (proper nouns: "MakerAI" instead of "MakeItAI"); `TranscriptionParams.Language` → `asr_options.language`. As a **Phase 1 bridge** (a text model with `SessionCaps` `[cap_Audio]`) it only fills `MediaFile.Transcription` and fires no events: the final response comes from the chat model. `qwen3-asr-flash` in `cmConversation` also transcribes (native audio via chat).
  - `uMakerAi.Embeddings.Qwen` — `TAiQwenEmbeddings` (driver `Qwen` in `TAiEmbeddingConnection`): inherits from `TAiOpenAiEmbeddings` (the compatible endpoint accepts the same body). `text-embedding-v4` [default, 1024 dims; supports 64–2048], `text-embedding-v3`, `qwen3.7-text-embedding`.
  - `Source/Tools/uMakerAi.Qwen.Rerank.pas` — `TAiQwenRAGReranker` for `TAiRAGVector.Reranker`: `qwen3-rerank` through the native API, score 0..1 per passage. Up to 500 documents per call (501 → 400), above that it splits into batches (`BatchSize`). `Instruct` describes the task and sharpens the score (0.85 → 0.91 on the correct passage). `gte-rerank-v2` does not exist in the international region and `gte-rerank` gives AccessDenied.
  - **Video (wan)** `[cap_GenVideo]`: asynchronous API task (`X-DashScope-Async: enable` → `task_id`; poll `api/v1/tasks/{id}` every 5 s, 10 min timeout, respects `Abort`). Depending on the images attached to the prompt: **0** = text to video (`wan2.6-t2v` [default], `wan2.7-t2v`, `wan2.5-t2v-preview`, `wan2.2-t2v-plus`, `wan2.1-t2v-turbo/plus`); **1** = image to video (`img_url` as a data URI; a `-t2v` model switches only to its `-i2v`; default `wan2.6-i2v-flash`); **2** = first and last frame (`first_frame_url`/`last_frame_url`, **a different endpoint** `image2video/video-synthesis`; `wan2.2-kf2v-flash` [default], `wan2.1-kf2v-plus`); 3 or more → error. `VideoParams.Params` passes through to `parameters` with its type (number, bool, text; `negative_prompt` goes in `input`). **Without an explicit size the API delivers 1080P (the most expensive)**: the driver requests 720P, via `size=1280*720` on the wan2.5/2.6 t2v models (they ignore `resolution`) and via `resolution=720P` on the rest. `duration`: 2–15 s on wan2.6/2.7, 3–10 on wan2.5-i2v, not supported on wan2.1/2.2 (fixed 5 s). wan2.5+ includes AAC audio. Measured times: wan2.6 ~45–55 s, wan2.7 ~95 s, kf2v ~60 s per 5 s of video. Result: `qwen_video.mp4` in `MediaFiles` (24 h URL). **Careful when probing the API: an invalid body still creates a task (HTTP 200) that fails later, and an unknown parameter is ignored and the task runs (and is billed); in-flight tasks cannot be canceled.** The body is built by `BuildVideoRequest` (protected; tested without network).
  - Realtime (voice to voice, live STT, simultaneous translation): drivers `Qwen`/`QwenSTT`/`QwenTranslate` in `Source/Realtime/uMakerAi.Realtime.Qwen.pas`; live TTS (text → audio while it is generated, e.g. reading an LLM response): component `TAiQwenRealtimeTTS` in `Source/Realtime/uMakerAi.Realtime.QwenTTS.pas` (see `Source/Realtime/CLAUDE.md`). `qwen3-s2s-flash-realtime` is not enabled on the tested account.
  - **Text translation (`qwen-mt-plus/flash/turbo/lite`)**: the API accepts **a single `user` message** (system → 400 *"Role must be in [user, assistant]"*, history → 400 *"only one"*, tools → 400) and **without `translation_options` it does not translate: it chats**. With a `qwen-mt` model the driver builds its own request (`BuildTranslationRequest`): only the last user message + `translation_options` from published properties (assignable via `Params`): `TranslateTo` (English name or code; empty = English), `TranslateFrom` (empty = auto), `TranslateDomain` (context in English) and `TranslateTerms` (glossary `source=target`, TStrings: assign it on `AiChat` as `TAiQwenChat`). The history is still stored, so a translation conversation works turn by turn. Measured quality: `qwen-mt-plus` translates "caja menor" as *petty cash fund*; `flash` as *smaller box*, and correctly with `TranslateDomain` or `TranslateTerms`. **Streaming: `qwen-mt-plus` and `qwen-mt-turbo` send the ACCUMULATED text in each chunk** (`incremental_output` does not change it); the common parser concatenated them and the text came out repeated. The driver overrides `OnInternalReceiveData` and rewrites each SSE line to the delta before passing it to the base (it handles lines split across chunks). `flash`/`lite` are already incremental.
  - **Custom voices** — `Source/Tools/uMakerAi.Qwen.Voices.pas`, `TAiQwenVoices`: `CloneVoice` (audio sample → `qwen-voice-enrollment`, target model `qwen3-tts-vc-2026-01-22`), `DesignVoice` (text description → `qwen-voice-design`, target `qwen3-tts-vd-2026-01-26`; returns a WAV preview and `LastDesignFallback` if the description could not be followed, e.g. `wer_too_high`), `ListVoices`, `DeleteVoice` (picks the service by the id prefix). API `api/v1/services/audio/tts/customization`. The id is used as `TtsParams.Voice` in normal TTS (`cap_GenAudio`). **A custom voice only works with its target model** (`qwen3-tts-flash` rejects it with *"voice does not exist or is not licensed"*): `TtsModelFor` chooses `qwen3-tts-vc-…` / `qwen3-tts-vd-…` by the `qwen-tts-vc-` / `qwen-tts-vd-` prefix if the session does not fix one. Live-tested: clone, design, list, synthesize with both (the re-transcribed audio matches the text) and delete. Clone only with the voice owner's consent.
  - Not covered: (`qwen-mt-*`, `livetranslate`), voice cloning (`qwen3-tts-vc/vd`).

### Cohere
**Updated Aug 2026, runtime-tested 5/5 (incl. tools).** The new models (a-plus, north, a-reasoning) reason by default: the content carries a `type:'thinking'` block before the `text`. The driver controls it in `InitChatCompletions`: `cap_Reasoning` → `thinking:{enabled}`; without the cap → `disabled` (fast mode), EXCEPT command-a-plus, which **does not allow disabled** (fails with `INVALID_TOOL_GENERATION`). `ParseChat` and streaming capture the thinking into `ReasoningContent` / `OnReceiveThinking`. FIX Aug 2026: the synchronous return with tool calling arrived empty — `ExecuteAndRespondToToolCalls` now reuses the same `ResMsg` in round 2 (the base's `Run(Nil, ResMsg)` pattern).
- `command-a-plus-05-2026` [FLAGSHIP]: MoE 218B/25B, Apache 2.0, 436K ctx, vision + reasoning always active (tested). $2.5/$10 per M
- `north-mini-code-1-0`: coding, 436K ctx, reasons by default (driver sends disabled without cap_Reasoning; tested)
- `command-a-03-2025`: text + tools (288K ctx, driver default)
- `command-a-reasoning-08-2025`: reasoning + tools
- `command-a-vision-07-2025`: vision, **no tools** (`Tool_Active=False`)
- `command-a-translate-08-2025`: specialized translation, no tools
- `c4ai-aya-expanse-32b` / `c4ai-aya-vision-32b`: multilingual, no tools (the 8b models are NO LONGER in the API)
- `tiny-aya-global/earth/fire/water`: lightweight 8K ctx, no tools
- `cohere-transcribe-03-2026`: STT (transcriptions endpoint)
- Rerank v4.0: `rerank-v4.0-fast`/`-pro` (32K ctx) via `RerankModel` + `Rerank()` method

### Ollama
- Global default: plain text, no tools (`Tool_Active=False`, `ModelCaps=[]`)
- Models with tools: llama3.3, qwen2.5, qwen3, qwen2.5vl
- Models with reasoning: qwen3 (`ThinkingLevel=tlMedium`), deepseek-r1 (via `<think>` tags)
- Models with vision: llama3.2-vision, qwen2.5vl, gemma3 (all sizes: 1b/4b/12b/27b)
- Gemma 3: vision in all sizes; **no function calling** via Ollama (`Tool_Active=False`)
- Gemma 4 (e2b/e4b): vision + native audio + reasoning + **function calling** (`Tool_Active=True`)

### LM Studio
- Conservative global default: plain text, no tools, `Max_Tokens=4096`
- Model IDs depend on the name/alias configured in the app (they are not fixed)
- Configured models: llama-3.3-70b, qwen2.5-7b, deepseek-r1-7b, llama-3.2-11b-vision, mistral-7b, gemma-3-4b/12b/27b-it

### GenericLLM
- Catch-all driver for any OpenAI-compatible API
- Conservative defaults: text, no tools, `Max_Tokens=4096`
- Configure: `DriverName='GenericLLM'`, `URL='http://host/v1/'`, `Model='name'`
- The user enables caps according to the real capabilities of their endpoint

---

## Public call chain

```
AddMessageAndRun(prompt, role, files)  ← recommended entry point (public)
  └── Run(AskMsg, ResMsg)              ← prompt sanitizer (public, virtual)
        └── RunNew(AskMsg, ResMsg)     ← internal orchestrator: 3 phases + ChatMode (PRIVATE)
```

- **`AddMessageAndRun`** — creates the message, adds it to the history and calls `Run`.
- **`Run`** — applies the prompt sanitizer; if it passes, delegates to `RunNew`.
- **`RunNew`** — does the real work: gap analysis, Phase 1 (input bridges), Phase 2 (web), Phase 3 (dispatch by `ChatMode`). It is `private` — never call it directly.

## Events — type `of object`

All `TAiChat` / `TAiChatConnection` events are of the `of object` type:

```delphi
TAiChatOnDataEvent = procedure(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSonObject; aRole, aText: String) of object;
```

**They do not accept anonymous methods.** Always assign a class method:

```delphi
// Correct — form or class method
Conn.OnReceiveDataEnd := Self.HandleDataEnd;

// Does NOT compile — of object does not accept lambdas
Conn.OnReceiveDataEnd := procedure(...) begin ... end;
```

For code without a class (console), use the synchronous return value of `AddMessageAndRun`:
```delphi
Resp := Conn.AddMessageAndRun(prompt, 'user', []);
```

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.