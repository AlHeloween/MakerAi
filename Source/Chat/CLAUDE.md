# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The Chat module contains LLM provider drivers for the MakerAI framework. Each driver implements provider-specific API communication, message formatting, streaming, and tool calling for a different LLM service.

## Module Structure

### Universal Connector
- `uMakerAi.Chat.AiConnection.pas` - `TAiChatConnection` component that abstracts all provider differences. Set `DriverName` property to switch providers without code changes. Manages tool integration (Shell, TextEditor, ComputerUse, Speech, Video, Vision, WebSearch, Image).

### Provider Drivers
Each inherits from `TAiChat` (defined in Core):

| File | Class | Provider |
|------|-------|----------|
| `uMakerAi.Chat.OpenAi.pas` | `TAiOpenChat` | OpenAI (GPT-4.1, o3, o4-mini, Sora) |
| `uMakerAi.Chat.Claude.pas` | `TAiClaudeChat` | Anthropic Claude (claude-opus/sonnet/haiku-4-x) |
| `uMakerAi.Chat.Gemini.pas` | `TAiGeminiChat` | Google Gemini (2.5-flash/pro, 3-pro, Veo) |
| `uMakerAi.Chat.Ollama.pas` | `TAiOllamaChat` | Ollama (local models) |
| `uMakerAi.Chat.LMStudio.pas` | `TAiLMStudioChat` | LM Studio (local OpenAI-compatible) |
| `uMakerAi.Chat.Groq.pas` | `TAiGroqChat` | Groq inference (llama, qwen, deepseek, voxtral) |
| `uMakerAi.Chat.DeepSeek.pas` | `TAiDeepSeekChat` | DeepSeek (deepseek-chat, deepseek-reasoner) |
| `uMakerAi.Chat.Mistral.pas` | `TAiMistralChat` | Mistral (large, magistral, devstral, voxtral) |
| `uMakerAi.Chat.Kimi.pas` | `TAiKimiChat` | Kimi/Moonshot (kimi-k2, kimi-k2.5) |
| `uMakerAi.Chat.Grok.pas` | `TAiGrokChat` | xAI Grok (grok-3, grok-4-fast) |
| `uMakerAi.Chat.Cohere.pas` | `TCohereChat` | Cohere (command-a, aya-vision) |
| `uMakerAi.Chat.GenericLLM.pas` | `TAiGenericChat` | Any OpenAI-compatible API |

### Configuration
- `uMakerAi.Chat.Initializations.pas` - Driver registration and model capabilities. Uses `TAiChatFactory` to configure `ModelCaps`, `SessionCaps`, `Tool_Active`, `ThinkingLevel` per model. **Ãšltima actualizaciÃ³n: Feb 2026.**

### Legacy (Deprecated)
- `uMakerAi.Chat.OpenAi_Deprecated.pas`
- `uMakerAi.Chat.Ollama_old.pas`, `uMakerAi.Chat.Ollama_old1.pas`
- `uMakerAi.Chat.Claude_beta.pas`

---

## Capability System (v3.3 â€” nuevo)

### Concepto central
Dos propiedades de tipo `TAiCapabilities` (set de `TAiCapability`) reemplazan los cuatro params legacy:

| Propiedad | DescripciÃ³n | Sincroniza a (legacy) |
|-----------|-------------|----------------------|
| `ModelCaps` | Capacidades nativas del modelo vÃ­a completions | `NativeInputFiles` + `ChatMediaSupports` |
| `SessionCaps` | Capacidades deseadas en la sesiÃ³n | `NativeOutputFiles` + `EnabledFeatures` |

**Gap = SessionCaps âˆ’ ModelCaps** â†’ determina quÃ© bridge/tool activa `RunNew` automÃ¡ticamente.

### TAiCapability enum
```delphi
TAiCapability = (
  // Entrada / ComprensiÃ³n
  cap_Image, cap_Audio, cap_Video, cap_Pdf,
  cap_WebSearch, cap_Reasoning, cap_CodeInterpreter,
  cap_Memory, cap_TextEditor, cap_ComputerUse, cap_Shell,
  // Salida / GeneraciÃ³n (gap â†’ activa bridge)
  cap_GenImage, cap_GenAudio, cap_GenVideo, cap_GenReport, cap_ExtractCode
);
```

### Patrones de configuraciÃ³n frecuentes

```delphi
// Modelo de texto + tools (default para la mayorÃ­a)
RegisterUserParam('Driver', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'SessionCaps', '[]');

// Modelo con visiÃ³n nativa
RegisterUserParam('Driver', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Driver', 'SessionCaps', '[cap_Image]');

// Modelo con reasoning
RegisterUserParam('Driver', Model, 'ModelCaps',    '[cap_Reasoning]');
RegisterUserParam('Driver', Model, 'SessionCaps',  '[cap_Reasoning]');
RegisterUserParam('Driver', Model, 'ThinkingLevel', 'tlMedium');

// TTS via endpoint dedicado (Gap=[cap_GenAudio] â†’ InternalRunSpeechGeneration)
RegisterUserParam('Driver', Model, 'ModelCaps',   '[]');
RegisterUserParam('Driver', Model, 'SessionCaps', '[cap_GenAudio]');
RegisterUserParam('Driver', Model, 'Tool_Active', 'False');

// GeneraciÃ³n de imagen via endpoint dedicado (Gap=[cap_GenImage])
RegisterUserParam('Driver', Model, 'ModelCaps',   '[]');
RegisterUserParam('Driver', Model, 'SessionCaps', '[cap_GenImage]');
RegisterUserParam('Driver', Model, 'Tool_Active', 'False');
```

### Compatibilidad con sistema legacy
`EnsureNewSystemConfig` traduce automÃ¡ticamente los params legacy (`NativeInputFiles`, `ChatMediaSupports`, `EnabledFeatures`, `NativeOutputFiles`) al nuevo sistema en el primer `Run`. Los modelos con configuraciÃ³n antigua siguen funcionando sin cambios. Si se asignan `ModelCaps`/`SessionCaps` explÃ­citamente, `FNewSystemConfigured=True` y la traducciÃ³n automÃ¡tica se omite.

---

## Key Patterns

### Driver Implementation
All drivers implement these core methods:
- `Run()` - Execute chat completion (sync or async based on `Asynchronous` property). Calls `EnsureNewSystemConfig` then `RunNew`.
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
- `ModelCaps` / `SessionCaps` â€” **sistema nuevo v3.3** (preferido)
- `NativeInputFiles` / `NativeOutputFiles` â€” fÃ­sico, legacy (aÃºn soportado)
- `ChatMediaSupports` / `EnabledFeatures` â€” lÃ³gico, legacy (aÃºn soportado)
- `Tool_Active` â€” habilita function calling
- `ThinkingLevel` â€” nivel de razonamiento (`tlLow`, `tlMedium`, `tlHigh`)
- `Max_Tokens` â€” tokens mÃ¡ximos de respuesta
- `Temperature` â€” temperatura de sampling

### Chat State Machine
Drivers follow states in `TAiChatState`:
```text
acsIdle â†’ acsConnecting â†’ acsReasoning â†’ acsWriting â†’ acsToolCalling â†’ acsFinished/acsError
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
- `uMakerAi.Chat.pas` - Abstract `TAiChat` base class (`ModelCaps`, `SessionCaps`, `RunNew`, `RunLegacy`)
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
- Thinking/reasoning via `EnableThinking` + `ThinkingBudget`; `ThinkingLevel` mapea a presupuesto automÃ¡tico
- Citations (RAG nativo): soporte parcial implementado
- Modelos actuales: `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`

### OpenAI
- GPT-4.1 (32K output, vision), o3/o4-mini (reasoning + vision), GPT-4o (audio multimodal)
- GeneraciÃ³n de imagen: `gpt-image-1` (calidad HD), `dall-e-3/2` â†’ `SessionCaps=[cap_GenImage]`
- TTS: `gpt-4o-mini-tts` â†’ `SessionCaps=[cap_GenAudio]`
- Video: Sora â†’ `SessionCaps=[cap_GenVideo]`
- Web search: `gpt-4o-search-preview` â†’ `ModelCaps=[cap_WebSearch]`, `Tool_Active=False`
- Modelos de reasoning usan `ThinkingLevel` para controlar esfuerzo

### Gemini (Google)
- Gemini 2.5-flash/pro: vision + audio + video + PDF + web search + code interpreter + reasoning
- Gemini 3-pro-preview / 3.1-pro-preview: capacidades completas + `ThinkingLevel=tlHigh`
- GeneraciÃ³n de imagen nativa vÃ­a completions: `gemini-2.5-flash-image-preview` â†’ `ModelCaps=[cap_Image, cap_GenImage]`
- TTS: `gemini-2.5-flash-tts` / `gemini-2.5-pro-tts` â†’ `SessionCaps=[cap_GenAudio]`
- Video: Veo 2.0/3.0/3.1 â†’ `SessionCaps=[cap_GenVideo]`
- Grounding nativo: el driver gestiona `groundingSupports` automÃ¡ticamente

### Groq (inferencia rÃ¡pida)
- Modelos populares: llama-4-scout/maverick (vision), kimi-k2, compound-beta, deepseek-r1, qwen3
- TTS: `playai-tts`, `playai-tts-arabic`, `voxtral-mini/small` â†’ `SessionCaps=[cap_GenAudio]`
- TranscripciÃ³n: `whisper-large-v3/turbo` â†’ `ModelCaps=[cap_Audio]`, `Tool_Active=False`
- compound-beta/mini: web search + code interpreter nativos, `Tool_Active=False`

### Mistral
- Vision: todos los modelos hereden el global `ModelCaps=[cap_Image]` (Mistral Large/Medium/Small 3.x)
- Reasoning: magistral-medium/small â†’ `ModelCaps=[cap_Reasoning]`, `ThinkingLevel=tlMedium`
- CÃ³digo: devstral-latest / devstral-small-latest â†’ `ModelCaps=[]` (sin visiÃ³n)
- TTS: voxtral-mini/small-latest â†’ `ModelCaps=[cap_Audio]`, `Tool_Active=False`
- OCR: mistral-ocr-latest â†’ `ModelCaps=[cap_Pdf]`, `Tool_Active=False`

### xAI Grok
- grok-3: texto + tools (default)
- grok-3-mini: reasoning ligero (`ThinkingLevel=tlLow`)
- grok-4-fast-reasoning / grok-4-1-fast-reasoning: vision + reasoning, 2M ctx
- grok-code-fast-1: reasoning para cÃ³digo, sin visiÃ³n
- Imagen: grok-2-image-1212, grok-imagine-image/pro â†’ `SessionCaps=[cap_GenImage]`
- Video: grok-imagine-video â†’ `SessionCaps=[cap_GenVideo]`

### DeepSeek
- `deepseek-chat` (V3.2): texto + tools, 128K ctx, 32K output
- `deepseek-reasoner` (R1): reasoning + tools, `ThinkingLevel=tlMedium`
- Sin visiÃ³n en la API pÃºblica (DeepSeek-VL2 no disponible vÃ­a api.deepseek.com)

### Kimi (Moonshot AI)
- `kimi-k2`: texto + tools, 256K ctx (default del driver)
- `kimi-k2.5`: vision + PDF + reasoning + tools, MoE 1T params activos 32B
- `kimi-k2-thinking`: reasoning + tools, sin visiÃ³n
- `moonshot-v1-*`: legacy, sin tools (`Tool_Active=False`)
- `moonshot-v1-*-vision-preview`: visiÃ³n vÃ­a base64, sin tools

### Cohere
- `command-a-03-2025`: texto + tools (flagship, 256K ctx)
- `command-a-reasoning-08-2025`: reasoning + tools, 32K output
- `command-a-vision-07-2025`: visiÃ³n, **sin tools** (`Tool_Active=False`)
- `command-a-translate-08-2025`: traducciÃ³n especializada, sin tools
- `c4ai-aya-vision-8b/32b`: visiÃ³n multilingual, sin tools

### Ollama
- Default global: texto puro, sin tools (`Tool_Active=False`, `ModelCaps=[]`)
- Modelos con tools: llama3.3, qwen2.5, qwen3, qwen2.5vl
- Modelos con reasoning: qwen3 (`ThinkingLevel=tlMedium`), deepseek-r1 (via `<think>` tags)
- Modelos con visiÃ³n: llama3.2-vision, qwen2.5vl, gemma3 (todos los tamaÃ±os: 1b/4b/12b/27b)
- Gemma 3: visiÃ³n en todos los tamaÃ±os; **sin function calling** vÃ­a Ollama (`Tool_Active=False`)
- Gemma 4 (e2b/e4b): visiÃ³n + audio nativo + reasoning + **function calling** (`Tool_Active=True`)

### LM Studio
- Default global conservador: texto puro, sin tools, `Max_Tokens=4096`
- IDs de modelo segÃºn nombre/alias configurado en la app (no son fijos)
- Modelos configurados: llama-3.3-70b, qwen2.5-7b, deepseek-r1-7b, llama-3.2-11b-vision, mistral-7b, gemma-3-4b/12b/27b-it

### GenericLLM
- Driver catch-all para cualquier API OpenAI-compatible
- Defaults conservadores: texto, sin tools, `Max_Tokens=4096`
- Configurar: `DriverName='GenericLLM'`, `URL='http://host/v1/'`, `Model='nombre'`
- El usuario activa caps segÃºn las capacidades reales de su endpoint

---

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.
