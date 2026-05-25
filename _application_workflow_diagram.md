# Application Workflow Diagram — MakerAI v3.3

> **Purpose:** Complete catalog of ALL modules, units, types, entrypoints, and dependencies.
> **Coverage:** 100% of the core codebase (106 `.pas` units across 13 modules).
> **Last updated:** 2026-05-21

---

## Expanded Architecture Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│  Applications / Demos (18+ demo projects)                            │
└───────┬──────────────┬─────────────────┬─────────────────────────────┘
        │              │                 │
┌───────v──────┐ ┌─────v──────────┐ ┌────v─────────────────────────────┐
│ ChatUI       │ │ Agents          │ │ Design (Dsg)                    │
│ TChatList    │ │ TAIAgentManager │ │ IDE Property Editors            │
│ TChatBubble  │ │ TAIAgentsNode   │ │ TFMCPClientEditor               │
│ TChatInput   │ │ TAIAgentsLink   │ │ TParamsRegistry editor          │
│ TScreenCap   │ │ TAIBlackboard   │ │ VCL + DesignIDE                 │
│ FMX UI       │ │ TAiToolRegistry │ │                                 │
└───────┬──────┘ └─────┬───────────┘ └─────────────────────────────────┘
        │              │
┌───────v──────────────v────────────────────────────────────────────────┐
│  Chat Drivers (12+1 LLM providers)                                    │
│  TAiChatConnection (universal connector)                              │
│  OpenAI | Claude | Gemini | Ollama | Groq | DeepSeek | Kimi |         │
│  Grok | Mistral | Cohere | LMStudio | GenericLLM | Llamacpp | Gen     │
└──────────────────────────┬────────────────────────────────────────────┘
                           │
┌──────────────────────────v────────────────────────────────────────────┐
│  Core: TAiChat (abstract base, IAiToolContext)                        │
│  ModelCaps, SessionCaps, RunNew(), EnsureNewSystemConfig()            │
│  TAiChatTools, TAiChatMessage(s), TAiMediaFile, TAiCapabilities       │
│  Bridges: Speech/Vision/Image/Video/Doc/Code/WebSearch                │
│  Sanitizer pipeline, Prompts, CodeExtractor, PcmToWav                 │
└──────┬─────────────┬───────────────┬──────────────────────────────────┘
       │             │               │
┌──────v──────┐ ┌────v──────────┐ ┌──v──────────────────────────────────┐
│ Tools       │ │ RAG            │ │ MCP                                │
│ Functions   │ │ Vectors (HNSW) │ │ Client: StdIo/HTTP/SSE/MakerAi     │
│ Shell       │ │ Graph (GQL)    │ │ Server: Stdio/HTTP/SSE/Direct        │
│ TextEditor  │ │ VQL + MakerGQL │ │ Bridge: TAiFunctions ↔ IAiMCPTool  │
│ ComputerUse │ │ Documents      │ │                                    │
│ DALL-E,Sora │ │ BinFile/Pg/SQL │ │                                    │
│ Whisper,TTSC │ │ + Embeddings   │ │                                    │
│ GeminiVeo,  │ │                │ │                                    │
│ WebSearch,  │ │                │ │                                    │
│ Ollama OCR  │ │                │ │                                    │
└─────────────┘ └────────────────┘ └────────────────────────────────────┘
       │             │               │
┌──────v─────────────v───────────────v──────────────────────────────────┐
│  Embeddings (13 units — 8 providers + core + connection)              │
│  TAiEmbeddingsCore → OpenAI | Cohere | Gemini | Ollama | Mistral |    │
│  LMStudio | Generic | Llamacpp | Generic provider                     │
│  TAiEmbeddingConnection (universal connector)                         │
│  makerai.embedder.dll wrapper (uMakerAi.Embedder.Import)              │
└───────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────┐
│  Utils                                                               │
│  DiffUpdater | AudioPushStream | VoiceMonitor | Python | ScreenCap   │
│  System (process management, cross-platform)                         │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Complete Module Catalog

### CORE/ — Foundation Layer (12 units)

**Responsibility:** Base types, abstract chat class, message handling, bridges, sanitization, prompts, utilities. Every other module depends on Core.

#### `uMakerAi.Core.pas` (1,349 lines)
**Purpose:** Base types for the entire framework.

| Entrypoint | Kind | Line | Signature |
|-----------|------|------|-----------|
| `TAiFileCategory` | enum | 50-53 | 15 file categories |
| `TAiChatMediaSupport` | enum | 56-58 | 15 media support flags |
| `TAiCapability` | enum | 63-77 | 16 capability values (cap_Image..cap_ExtractCode) |
| `TAiCapabilities` | set | 79 | Set of TAiCapability (ModelCaps/SessionCaps type) |
| `TAiThinkingLevel` | enum | 84 | tlDefault, tlLow, tlMedium, tlHigh |
| `TAiMediaResolution` | enum | 85 | mrDefault, mrLow, mrMedium, mrHigh |
| `TAiTranscriptionResponseFormat` | enum | 88 | trfText, trfJson, trfSrt, trfVtt, trfVerboseJson |
| `TAiTimestampGranularity` | enum | 92 | tsgNone, tsgWord, tsgSegment |
| `TToolFormat` | enum | 106 | tfUnknown, tfOpenAI, tfOpenAIResponses, tfClaude, tfGemini, tfMCP |
| `TToolTransportType` | enum | 107 | tpStdIo, tpHttp, tpSSE, tpMakerAi |
| `TAiChatState` | enum | 109-120 | 12 states (acsIdle..acsError) |
| `TAiMediaFile` | class | 134 | Media file abstraction (LoadFromFile/SaveToFile/ToJsonObject/Assign) |
| `TAiMediaFiles` | class | 226 | `TObjectList<TAiMediaFile>`, GetMediaList(TAiFileCategories,Boolean) |
| `TAiMetadata` | class | 236 | TDictionary<string,string>, ToJSon/AsText/JsonText |
| `TAiWebSearch` | class | 260 | Web search results container with annotations |
| `GetContentCategory` | function | 272 | `(FileExtension: string): TAiFileCategory` |
| `GetMimeTypeFromFileName` | function | 275 | `(FileExtension: string): string` |
| `StreamToBase64` | function | 279 | `(Stream: TMemoryStream): String` |

**External deps:** `System.Net.HttpClient` (TNetHTTPClient, IHTTPResponse), `System.NetEncoding`, `System.JSON`

---

#### `uMakerAi.Chat.pas` (3,339 lines)
**Purpose:** Abstract `TAiChat` base class. All 12 LLM drivers inherit from this. Implements `IAiToolContext`. Contains `RunNew()`, `EnsureNewSystemConfig()`, and gap-based bridge activation.

| Entrypoint | Kind | Line | Signature |
|-----------|------|------|-----------|
| `TAiChatResponseFormat` | enum | 61 | tiaChatRfText, tiaChatRfJson, tiaChatRfJsonSchema |
| `TAiChatMode` | enum | 63-70 | cmConversation..cmReportGeneration (7 modes) |
| `TAiChatTools` | class | 87 | Speech/Image/Video/WebSearch/Vision/Pdf/Report/Shell/TextEditor/ComputerUse tool container |
| `TAiTtsParams` | class | 129 | TTS parameters (Voice, Speed, Format, Language) |
| `TAiTranscriptionParams` | class | 147 | Transcription parameters (Model, Language, Format, Granularity) |
| `TAiImageGenParams` | class | 165 | Image generation parameters |
| `TAiVideoGenParams` | class | 181 | Video generation parameters |
| `TAiWebSearchParams` | class | 197 | Web search parameters |
| `TAiModelConfig` | class | 209 | Unified model configuration (v3.3) |
| `TAiChat` | class | 233 | **Abstract base** for all LLM drivers — implements IAiToolContext |
| `TAiChat.AddMessageAndRun()` | method | 417-418 | Main entrypoint: send prompt + media to LLM |
| `TAiChat.Run()` | method | 422 | Execute chat completion |
| `TAiChat.GetMessages()` | method | 432 | Serialize messages to provider-specific JSON |
| `TAiChat.UploadFile()` | method | 439 | Upload media file to provider |
| `TAiChat.DownloadFile()` | method | 440 | Download media from provider |
| `TAiChat.RetrieveFile()` | method | 443 | Retrieve file by ID |
| `TAiChat.NewChat()` | method | 428 | Reset conversation |
| `TAiChat.Abort()` | method | 429 | Cancel current request |
| `TAiChat.GetModels()` | class method | 430-431 | List available models |
| `TAiChat.GetDriverName()` | class method | 447 | Abstract — return provider name |
| `TAiChat.RegisterDefaultParams()` | class method | 448 | Abstract — register default params |
| `TAiChat.CreateInstance()` | class method | 449 | Abstract — factory method |
| `TAiChat.Messages` | property | 451 | `TAiChatMessages` — conversation history |
| `TAiChat.ChatTools` | property | 503 | `TAiChatTools` — tool instances |
| `TAiChat.ModelConfig` | property | 513 | `TAiModelConfig` — cap config |
| `TAiChat.OnStateChange` | event | 514 | State transition notification |
| `TAiChat.OnReceiveData` | event | — | Streaming text chunk received |
| `TAiChat.OnReceiveDataEnd` | event | — | Streaming completed |
| `TAiChat.OnError` | event | — | Error occurred |
| `TAiChat.OnCallToolFunction` | event | — | Tool invocation request |

**Dependencies:** `uMakerAi.Chat.Messages`, `uMakerAi.Tools.Functions`, `uMakerAi.Tools.Shell`, `uMakerAi.Tools.TextEditor`, `uMakerAi.Tools.ComputerUse`, `uMakerAi.Chat.Tools`, `uMakerAi.Chat.Sanitizer`, `uMakerAi.Utils.CodeExtractor`, `uMakerAi.Core`, `System.Net.HttpClient`, `System.JSON`, `Rest.JSON`

---

#### `uMakerAi.Chat.Messages.pas` (1,365 lines)
**Purpose:** Chat message container with media, tool calls, citations, and serialization.

| Entrypoint | Kind | Line | Signature |
|-----------|------|------|-----------|
| `TAiCitationSourceType` | enum | 53 | cstUnknown, cstDocument, cstWeb, cstFile, cstDatabase |
| `TAiToolsFunction` | class | 56 | Tool call representation (id, name, arguments, response, media) |
| `TAiToolsFunctions` | class | 84 | TDictionary<string, TAiToolsFunction> |
| `TAiChatMessage` | class | 95 | Message with Role, Content, MediaFiles, Citations, ToolCalls |
| `TAiChatMessages` | class | 191 | TList<TAiChatMessage> |
| `TAiMsgCitation` | class | 233 | Citation with StartIndex, EndIndex, Text, Sources |
| `TAiToolsFunction.ParseFunction(JObj)` | method | 75 | Parse tool call from JSON |
| `TAiChatMessage.AddMediaFile(aMediaFile)` | method | 153 | Attach media to message |
| `TAiChatMessage.LoadMediaFromFile(aFileName)` | method | 154 | Load media from disk |
| `TAiChatMessage.LoadMediaFromStream(...)` | method | 155 | Load media from stream |
| `TAiChatMessage.LoadMediaFromBase64(...)` | method | 156 | Load media from base64 |
| `TAiChatMessage.ToJSon()` | method | 162 | Serialize to JSON |
| `TAiChatMessages.ToJSon()` | method | 198 | Serialize all messages |
| `TAiChatMessages.ExportChatHistory()` | method | 199 | Export to JSON archive |
| `TAiChatMessages.SaveToStream/SaveToFile()` | method | 201-202 | Persist to file |
| `TAiChatMessages.LoadFromStream/LoadFromFile()` | method | 203-204 | Restore from file |
| `TAiChatMessages.ModelCaps` | property | 206 | `TAiCapabilities` for message filter context |

**Dependencies:** `uMakerAi.Core`, `System.JSON`, `System.SyncObjs` (TCriticalSection for FLock), `Rest.JSON`

---

#### `uMakerAi.Chat.Tools.pas` (277 lines)
**Purpose:** Tool interfaces and abstract base classes for pluggable capabilities.

| Entrypoint | Kind | Line | Signature |
|-----------|------|------|-----------|
| `IAiToolContext` | interface | 13 | GUID `{E1D2C3B4...}`— bridge between tools and chat |
| `IAiSpeechTool` | interface | 24 | GUID `{B2C3D4E5...}`— TTS/STT contract |
| `IAiVisionTool` | interface | 30 | GUID `{7A8B9C0D...}`— image description contract |
| `IAiImageTool` | interface | 35 | GUID `{A1B2C3D4...}`— image generation contract |
| `IAiVideoTool` | interface | 40 | GUID `{E5F6A7B8...}`— video generation contract |
| `IAiDocumentTool` | interface | 45 | GUID `{D4E5F6A7...}`— document processing contract |
| `IAiCodeInterpreterTool` | interface | 50 | GUID `{F6A7B8C9...}`— code execution contract |
| `IAiWebSearchTool` | interface | 55 | GUID `{C3D4E5F6...}`— web search contract |
| `IAiPdfTool` | interface | 60 | GUID `{C1D2E3F4...}`— PDF processing contract |
| `IAiReportTool` | interface | 65 | GUID `{B9C0D1E2...}`— report generation contract |
| `TAiCustomTool` | class | 74 | Base tool class (TComponent) |
| `TAiSpeechToolBase` | class | 89 | TAiCustomTool + IAiSpeechTool |
| `TAiVisionToolBase` | class | 95 | TAiCustomTool + IAiVisionTool |
| `TAiImageToolBase` | class | 100 | TAiCustomTool + IAiImageTool |
| `TAiVideoToolBase` | class | 105 | TAiCustomTool + IAiVideoTool |
| `TAiDocumentToolBase` | class | 110 | TAiCustomTool + IAiDocumentTool |
| `TAiCodeInterpreterToolBase` | class | 115 | TAiCustomTool + IAiCodeInterpreterTool |
| `TAiWebSearchToolBase` | class | 120 | TAiCustomTool + IAiWebSearchTool |
| `TAiPdfToolBase` | class | 125 | TAiCustomTool + IAiPdfTool |
| `TAiReportToolBase` | class | 130 | TAiCustomTool + IAiReportTool |

**Dependencies:** `uMakerAi.Core`, `uMakerAi.Chat.Messages`, `System.Threading`

---

#### `uMakerAi.Chat.Bridge.pas` (444 lines)
**Purpose:** Delegation engines that fill capability gaps by routing to a secondary `TAiChat`.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiChatSpeechBridge` | class | 34 | Routes TTS/STT to target chat via `InternalRunSpeechGeneration` |
| `TAiChatVisionBridge` | class | 54 | Routes image description to target chat |
| `TAiChatImageBridge` | class | 72 | Routes image generation to target chat |
| `TAiChatVideoBridge` | class | 92 | Routes video generation to target chat |
| `TAiChatDocumentBridge` | class | 112 | Routes document analysis to target chat |
| `TAiChatCodeInterpreterBridge` | class | 132 | Routes code execution to target chat |
| `TAiChatWebSearchBridge` | class | 152 | Routes web search to target chat |
| `TAiBaseChatBridge` | class (internal) | 15 | Internal delegation engine (inherits TAiCustomTool) |

Bridge pattern: `Gap = SessionCaps − ModelCaps`. `EnsureNewSystemConfig()` instantiates bridges for missing caps.

---

#### `uMakerAi.Prompts.pas` (374 lines)
**Purpose:** Prompt template management with PPM registry integration.

| Entrypoint | Kind | Line | Signature |
|-----------|------|------|-----------|
| `TAiPromptItem` | class | 47 | Collection item: Nombre, Descripcion, Strings |
| `TAiPrompts` | class | 65 | Template manager with PPM search/load |
| `TAiPrompts.GetTemplate()` | method | 81-83 | 3 overloads (TStringList / String[] / TJSONObject params) |
| `TAiPrompts.SearchPPM(...)` | method | 87 | Search PPM registry for prompts |
| `TAiPrompts.LoadFromPPM(...)` | method | 90 | Download prompt template from PPM |

---

#### `uMakerAi.Chat.Sanitizer.pas` (588 lines)
**Purpose:** Input sanitization pipeline for LLM safety (prompt injection, homoglyphs, invisible chars).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TSuspiciousPatternKind` | enum | 49-64 | 14 injection patterns |
| `TSanitizeResult` | record | 73 | Full result with metrics |
| `TSanitizerPipeline` | class | 124 | Pipeline orchestrator |
| `URLDecodeInput(ADecodePlus)` | function | 97 | URL-decode with optional + handling |
| `StripInvisibleChars(out Count)` | function | 102 | Remove zero-width/control chars |
| `NormalizeHomoglyphs(out Count)` | function | 106 | Replace confusable Unicode chars |
| `NeutralizeFakeMarkers(out Count)` | function | 110 | Detect fake system/message markers |
| `DetectSuspiciousPatterns()` | function | 114 | Pattern matching |
| `WrapForModel()` | function | 118 | Wrap user content with boundary marker |
| `TSanitizerPipeline.Sanitize(...)` | method | 128 | Full pipeline: decode → clean → detect → wrap |
| `TSanitizerPipeline.Run(...)` | class method | 140 | Static convenience entry |

---

#### `uMakerAi.Utils.System.pas` (854 lines)
**Purpose:** Cross-platform process management (Windows + POSIX).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TInteractiveProcessInfo` | class | 70 | Process handle + pipes (ReadOutput, WriteInput, IsRunning, Terminate, Kill) |
| `TUtilsSystem` | class | 98 | Static utilities |
| `TUtilsSystem.RunCommandLine(...)` | class method | 100 | Execute and capture output |
| `TUtilsSystem.ExecuteCommandLine(...)` | class method | 101 | Execute without capture |
| `TUtilsSystem.StartInteractiveProcess(...)` | class method | 103 | Launch interactive process with pipes |
| `TUtilsSystem.StopInteractiveProcess(var)` | class method | 104 | Stop process |
| `TUtilsSystem.GetSystemEnvironment()` | class method | 106 | Return environment variables |
| `TUtilsSystem.ShellOpenFile(...)` | class method | 108 | Windows ShellExecute |

**Dependencies:** `Winapi.Windows`/`Winapi.ShellAPI` (MSWINDOWS), `Posix.*` units (POSIX/Linux/macOS)

---

#### `uMakerAi.Utils.CodeExtractor.pas` (299 lines)
**Purpose:** Parse markdown code fences into typed file objects.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TCodeFile` | record | 44 | FileName, FileType, Code, LineNumber |
| `TMarkdownCodeExtractor` | class | 55 | Markdown parser |
| `TMarkdownCodeExtractor.ExtractCodeFiles(...)` | method | 68 | Extract ` ```lang\n...\n``` ` blocks |

---

#### `uMakerAi.Utils.PcmToWav.pas` (267 lines)
**Purpose:** Raw PCM audio → WAV format conversion.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `ConvertPCMToWAV(...)` | function | 95 | PCM file → WAV file |
| `ConvertPCMStreamToWAVStream(...)` | function | 100 | PCM stream → WAV stream |

---

#### `uJSONHelper.pas` (289 lines)
**Purpose:** Backward-compatible JSON helpers for Delphi < 11 (CompilerVersion < 35).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TJSONObjectHelper` | class helper | 42 | Safe navigation: GetValueSafe, GetValueAsString/Integer/Int64/Double/Boolean/Object/Array |
| `TJSONUtils` | class | 74 | Parse, ParseAsObject, ParseAsArray |

---

#### `uMakerAi.Version.inc` (include file — 9KB)
**Purpose:** Version constants and feature flags. Included via `{$I}` in all packages.

Key constants: `MAKERAI_VERSION_MAJOR=3`, `MAKERAI_VERSION_MINOR=3`, `MAKERAI_API_LEVEL=30`. Feature flags: `MAKERAI_HAS_*` (all True except macOS).

---

### CHAT/ — LLM Provider Drivers (18 units)

**Responsibility:** 12 distinct LLM provider implementations, a universal connector, driver registry/factory, and a llama.cpp DLL wrapper. All drivers inherit from `TAiChat` (Core).

| Unit | Class | Provider | Lines |
|------|-------|----------|-------|
| `uMakerAi.Chat.OpenAi.pas` | `TAiOpenChat` | OpenAI (GPT-4.1, o3, o4-mini, Sora) | 2,948 |
| `uMakerAi.Chat.Claude.pas` | `TAiClaudeChat` | Anthropic Claude (opus/sonnet/haiku 4-x) | 2,686 |
| `uMakerAi.Chat.Gemini.pas` | `TAiGeminiChat` | Google Gemini (2.5/3.x, Veo) | 3,707 |
| `uMakerAi.Chat.Ollama.pas` | `TAiOllamaChat` | Ollama local models | 1,103 |
| `uMakerAi.Chat.Groq.pas` | `TAiGroqChat` | Groq inference (llama, qwen, deepseek) | 416 |
| `uMakerAi.Chat.DeepSeek.pas` | `TAiDeepSeekChat` | DeepSeek (chat, reasoner) | 659 |
| `uMakerAi.Chat.Mistral.pas` | `TAiMistralChat` | Mistral (large, magistral, devstral, voxtral) | 1,472 |
| `uMakerAi.Chat.Kimi.pas` | `TAiKimiChat` | Kimi/Moonshot (kimi-k2, k2.5) | 170 |
| `uMakerAi.Chat.Grok.pas` | `TAiGrokChat` | xAI Grok (grok-3, grok-4-fast) | 571 |
| `uMakerAi.Chat.Cohere.pas` | `TCohereChat` | Cohere (command-a, aya-vision) | 1,322 |
| `uMakerAi.Chat.LMStudio.pas` | `TAiLMStudioChat` | LM Studio local OpenAI-compatible | 103 |
| `uMakerAi.Chat.GenericLLM.pas` | `TAiGenericChat` | Any OpenAI-compatible API | 129 |
| `uMakerAi.Chat.Llamacpp.pas` | `TAiLlamacppChat` | Local GGUF via llamacpp DLL | 488 |
| `uMakerAi.Gen.Import.pas` | — | Delphi wrapper for `makerai.gen.dll` (llama.cpp) | 370 |
| `uMakerAi.Chat.AiConnection.pas` | `TAiChatConnection` | **Universal connector** (switch via DriverName) | 1,361 |
| `uMakerAi.Chat.Initializations.pas` | `TAiChatFactory` | Driver registration + model capabilities | 2,340 |
| `uMakerAi.Chat.OpenAi_Deprecated.pas` | — | Legacy OpenAI driver |
| `uMakerAi.Chat.Claude_beta.pas` | — | Beta Claude driver |

#### Universal Connector (`uMakerAi.Chat.AiConnection.pas`)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiChatConnection.Create(Sender)` | constructor | — | Initialize with tool bridges |
| `TAiChatConnection.DriverName` | property | — | String — switch provider at runtime |
| `TAiChatConnection.Model` | property | — | Model name |
| `TAiChatConnection.ApiKey` | property | — | Key (supports `@ENV_VAR_NAME` syntax) |
| `TAiChatConnection.AddMessageAndRun(...)` | method | — | Send prompt to active driver |
| `TAiChatConnection.GetDriver()` | method | — | Get or create driver instance by DriverName |
| `TAiChatConnection.ShellTool` | property | — | TAiShell instance |
| `TAiChatConnection.TextEditorTool` | property | — | TAiTextEditorTool instance |
| `TAiChatConnection.ComputerUseTool` | property | — | TAiComputerUseTool instance |

#### Driver Registry (`uMakerAi.Chat.Initializations.pas`)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiChatFactory` | class | — | Singleton parameter registry |
| `TAiChatFactory.Instance.RegisterUserParam(...)` | method | — | Register model capability (ModelCaps/SessionCaps/Tool_Active/ThinkingLevel) |
| `TAiChatFactory.Instance.RegisterModelParam(...)` | method | — | Per-model parameter override |
| `TAiChatFactory.Instance.UnregisterDriveName(...)` | method | — | Remove all params for a driver |
| `TAiChatFactory.Instance.FindRegisteredModel(...)` | method | — | Get registered model parameters |

All 12 providers are registered in the `initialization` section with complete model capability tables (last updated Feb 2026).

**External deps:** `System.Net.HttpClient` (TNetHTTPClient), `System.JSON`, `System.Net.URLClient`, `REST.Client` (some drivers), `uMakerAi.Chat` (TAiChat), `uMakerAi.Core`, `uMakerAi.Chat.Messages`, `uMakerAi.Tools.Functions`

---

### AGENTS/ — Autonomous Agent Framework (11 units)

**Responsibility:** Graph-based multi-agent orchestration with durable execution (checkpoints), tool registry, PPM package management, LLM node with integrated ReAct loop, and RTTI-driven tool discovery.

#### `uMakerAi.Agents.pas` (3,305 lines — 2nd largest file)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAgentExecutionStatus` | enum | 63 | esUnknown, esRunning, esCompleted, esError, esTimeout, esAborted, esSuspended |
| `TJoinMode` | enum | 67 | jmAny (first triggers), jmAll (wait for all) |
| `TLinkMode` | enum | 70 | lmFanout, lmConditional, lmManual, lmExpression |
| `TAIBlackboard` | class | 103 | Thread-safe shared state (SetString/GetString/SetInteger/GetInteger/SetBoolean/GetBoolean/SetStatus/GetStatus) |
| `TAiToolBase` | class | 131 | Abstract tool base for node execution |
| `TAIAgentsNode` | class | 224 | Graph node with OnExecute, JoinMode, Tool, Input/Output |
| `TAIAgentsNode.Suspend(Reason, Context)` | method | 274 | Checkpoint suspension |
| `TAIAgentsNode.DoExecute(Before, Link)` | method | 255 | Execute node (called by thread pool) |
| `TAIAgentsLink` | class | 163 | Directed edge with Mode, NextA/B/C/D/No, ConditionalKey |
| `TAIAgentManager` | class | 293 | Graph orchestrator via TThreadPool |
| `TAIAgentManager.Run(Prompt)` | method | 377 | Synchronous execution entry |
| `TAIAgentManager.AddMessageAndRun(...)` | method | 379 | Entry with media |
| `TAIAgentManager.AddNode/AddEdge(...)` | method | 366-370 | Fluent graph builder |
| `TAIAgentManager.Compile()` | method | 371 | Validate graph structure |
| `TAIAgentManager.ResumeThread(...)` | method | 388 | Resume suspended agent |
| `TAIAgentManager.GetActiveThreads()` | method | 390 | List active thread IDs |
| `TAIAgentManager.MaxConcurrentTasks` | property | 396 | Default 4 |
| `TAIAgentManager.TimeoutMs` | property | 399 | Default 60000 |
| `TAIAgentManager.Checkpointer` | property | 391 | Persistence contract |
| `TAIAgentManager.OnSuspend` | event | 402 | Human-in-the-loop notification |
| `TAIAgentManager.OnError` | event | 397 | Error handler |
| `TAIAgentManager.Blackboard` | property | 385 | Shared state access |
| `EvalCondition(Expr, Vars)` | function | 413 | Binding expression evaluator |

**Threading Model:**
- `TAIAgentManager.FThreadPool: TThreadPool` executes node callbacks
- `TAIBlackboard.FLock: TCriticalSection` protects shared state
- `TAIAgentsNode.FJoinLock: TCriticalSection` protects join counter
- `TAIAgentManager.FActiveTasksLock: TCriticalSection` protects task list
- `TAIAgentManager.FSuspendedStepsLock: TCriticalSection` protects suspension queue

**Dependencies:** `System.Threading` (TThreadPool, ITask), `System.Rtti`, `System.Bindings.*`, `uMakerAi.Chat`, `uMakerAi.Core`, `uMakerAi.Chat.Messages`, `uMakerAi.Agents.Checkpoint`

---

#### `uMakerAi.Agents.Attributes.pas` (104 lines)
**Purpose:** RTTI attributes for tool metadata discovery.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TToolAttribute` | class | 52 | Attribute: Name, Description, Category |
| `TToolParameterAttribute` | class | 69 | Attribute: DisplayName, Hint, DefaultValue |

---

#### `uMakerAi.Agents.EngineRegistry.pas` (393 lines)
**Purpose:** Singleton registries for tool class discovery and named handler lookup.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TEngineRegistry` | class | 62 | Singleton tool class registry |
| `TEngineRegistry.Instance.RegisterTool(Class, UnitName)` | method | 75 | Register tool class |
| `TEngineRegistry.Instance.FindToolClass(ClassName)` | method | 77 | Tool class lookup |
| `TEngineRegistry.Instance.GetToolBlueprints()` | method | 81 | Schema generation for all registered tools |
| `TAgentHandlerRegistry` | class | 85 | Named handler registry |
| `TAgentHandlerRegistry.Instance.RegisterNodeHandler(...)` | method | 95 | Register node handler |
| `TAgentHandlerRegistry.Instance.RegisterLinkHandler(...)` | method | 96 | Register link handler |

**Dependencies:** `System.Rtti` (TRttiContext, TRttiType, GetAttributes for schema generation)

---

#### `uMakerAi.Agents.GraphBuilder.pas` (442 lines)
**Purpose:** Parse JSON graph definitions into runtime agent graph structures.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TGraphBuilder` | class | 10 | JSON → graph compiler |
| `TGraphBuilder.BuildFromJson(JsonString)` | method | 72 | Main entry: parse nodes/edges, set tool params |
| `TGraphBuilder.ParseNodes()` | method | 56 | Parse node definitions |
| `TGraphBuilder.ParseEdges()` | method | 57 | Parse edge definitions |

---

#### `uMakerAi.Agents.DmGenerator.pas` (776 lines)
**Purpose:** Generate Delphi DataModule code (.pas + .dfm) from JSON graph specifications.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TDataModuleGenerator` | class | 21 | Code generator |
| `TDataModuleGenerator.GenerateFromJSON(...)` | method | 52 | Parse + generate code |
| `TDataModuleGenerator.SaveToFile(BaseFileName)` | method | 53 | Write .pas + .dfm |
| `TDataModuleGenerator.GetPasFileContent()` | method | 54 | Return .pas string |
| `TDataModuleGenerator.GetDfmFileContent()` | method | 55 | Return .dfm string |

---

#### `uMakerAi.Agents.Checkpoint.pas` (434 lines)
**Purpose:** Durable execution persistence (suspend/resume).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiPendingStep` | class | 54 | Suspended step record |
| `TAiCheckpointSnapshot` | class | 81 | Full graph state snapshot |
| `IAiCheckpointer` | interface | 110 | GUID `{A3F2C1D4...}`— persistence contract |
| `TAiNullCheckpointer` | class | 121 | No-op implementation |
| `TAiFileCheckpointer` | class | 131 | JSON-on-disk implementation |
| `TAiFileCheckpointer.SaveCheckpoint(ThreadID, Snapshot)` | method | 141 | Serialize to JSON file |
| `TAiFileCheckpointer.LoadCheckpoint(ThreadID)` | method | 142 | Deserialize from JSON file |
| `TAiFileCheckpointer.GetActiveThreadIDs()` | method | 143 | List persisted thread IDs |

---

#### `uMakerAi.Agents.IAiTool.pas` (245 lines)
**Purpose:** Unified IAiTool interface (v3.4) with JSON I/O.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `IAiTool` | interface | 31 | GUID `{3F7A9B2E...}`— GetName, GetDescription, GetCategory, GetSchema, Execute, IsAvailable |
| `TAiToolBase_IAiTool` | class | 51 | Adapter: TAiToolBase → IAiTool (string ↔ JSON bridge) |
| `TAiNullTool` | class | 73 | No-op placeholder |

---

#### `uMakerAi.Agents.Node.LLM.pas` (326 lines)
**Purpose:** Agent node with integrated LLM + ReAct tool-use loop.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TLLMNode` | class | 52 | Extends TAIAgentsNode with embedded TAiChatConnection |
| `TLLMNode.DriverName` | property | 86 | 'OpenAI', 'Claude', 'Gemini', etc. |
| `TLLMNode.Model` | property | 88 | Model name |
| `TLLMNode.ApiKey` | property | 90 | Key (supports `@VAR_NAME`) |
| `TLLMNode.SystemPrompt` | property | 92 | System prompt |
| `TLLMNode.UseAllTools` | property | 96 | Auto-inject registry tools |
| `TLLMNode.Registry` | property | 83 | TAiToolRegistry ref |
| `TLLMNode.DoExecute(Before, Link)` | method | 78 | ReAct loop: run LLM → call tools → repeat |

**Dependencies:** `uMakerAi.Chat.AiConnection`, `uMakerAi.Tools.Functions`

---

#### `uMakerAi.Agents.ToolRegistry.pas` (905 lines)
**Purpose:** Central unified IAiTool registry with PPM package manager integration.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiToolRegistry` | class | 54 | Singleton |
| `TAiToolRegistry.Instance.Register(Tool, Origin, SourceId)` | method | 73 | Register tool |
| `TAiToolRegistry.Instance.RegisterFromMCP(Client)` | method | 74 | Import all tools from MCP server |
| `TAiToolRegistry.Instance.RegisterFromTAiFunctions(Functions)` | method | 75 | Import from TAiFunctions |
| `TAiToolRegistry.Instance.Find(Name)` | method | 81 | Lookup by name |
| `TAiToolRegistry.Instance.GetAll()` | method | 83 | All registered tools |
| `TAiToolRegistry.Instance.SearchPPM(Query, Page, PerPage)` | method | 89 | Search PPM registry |
| `TAiToolRegistry.Instance.GetPPMPackage(Name, Version)` | method | 90 | PPM package metadata |
| `TAiToolRegistry.Instance.DownloadPackage(Pkg)` | method | 91 | Download .paipkg |
| `TAiToolRegistry.Instance.InstallFromPPM(Pkg)` | method | 92 | Install + create MCP client |
| `TAiToolRegistry.Instance.InstallSchemaFromPPM(Pkg)` | method | 93 | Schema-only install |

**Dependencies:** `uMakerAi.MCPClient.Core`, `uMakerAi.Tools.Functions`, `System.Net.HttpClient`, `System.Zip`, `IniFiles`

---

#### `uMakerAi.Agents.Tools.Approval.pas` (102 lines)
**Purpose:** Human-in-the-loop suspension tool.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiWaitApprovalTool` | class | 51 | Tool: suspends node until human approves |
| `TAiWaitApprovalTool.Execute(Node, Input, Output)` | method | 58 | Calls Node.Suspend(SuspendReason, Context) |

RTTI attribute: `[TToolAttribute('WaitApproval', 'Suspends execution...', 'Control')]`

---

#### `uMakerAi.Agents.Tools.MCP.pas` (216 lines)
**Purpose:** MCP server → IAiTool adapter bridge.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiMCPTool` | class | 31 | Implements IAiTool wrapping one MCP server tool |
| `TAiMCPToolFactory.CreateFromClient(Client)` | class method | 73 | Create IAiTool[] from MCP server tools/list |

---

### RAG/ — Retrieval-Augmented Generation (12 units)

**Responsibility:** Vector-based semantic search (HNSW + BM25 hybrid), knowledge graph with GQL traversal, document ingestion with LLM-based entity extraction, and 3 database drivers (BinFile, PostgreSQL/pgvector, SQLite/FTS5).

#### `uMakerAi.RAG.Vectors.pas` (2,669 lines)
**Purpose:** Main vector store component with hybrid search and VGQL execution.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiSearchOptions` | class | 85 | UseEmbeddings, UseBM25, UseRRF, UseReorderABC, BM25Weight, EmbeddingWeight |
| `TAiSearchOptions.Assign(Source)` | method | 105 | Copy options |
| `TAiVectorStoreDriverBase` | class | 119 | Abstract DB driver (Add, Search, Delete, Clear) |
| `TAiRAGVector` | class | 139 | Main vector store |
| `TAiRAGVector.Search(Target, ...)` | method | 211-215 | Hybrid search (embedding + BM25) |
| `TAiRAGVector.ExecuteVGQL(Query, ...)` | method | 217-219 | VGQL query execution |
| `TAiRAGVector.AddItem(Node, ...)` | method | 226-228 | 3 overloads |
| `TAiRAGVector.BuildIndex()` | method | 223 | Build vector index |
| `TAiRAGVector.BuildLexicalIndex()` | method | 224 | Build BM25 index |
| `TAiRAGVector.Rerank(...)` | method | 238 | Re-rank results |
| `TAiRAGVector.VectorToContextText(...)` | method | 221 | Results → LLM context |
| `TAiRAGVector.SaveToFile(FileName)` | method | 207 | Persist vector store |
| `TAiRAGVector.LoadFromFile(FileName)` | method | 208 | Restore vector store |
| `TAiRAGVector.Embeddings` | property | 245 | Embedding provider |
| `TAiRAGVector.SearchOptions` | property | 261 | Search configuration |
| `TAiRAGVector.Driver` | property | — | DB driver |

**Dependencies:** `uMakerAi.RAG.Vectors.Index`, `uMakerAi.RAG.Vectors.VQL`, `uMakerAi.Embeddings.Core`, `uMakerAi.RAG.MetaData`

---

#### `uMakerAi.RAG.Vectors.Index.pas` (— lines)
**Purpose:** Embedding node container, index hierarchy (HNSW, Euclidean, BM25).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiEmbeddingNode` | class | 57 | Base container: Data[], Text, MetaData, CosineSimilarity, DotProduct, Magnitude |
| `TAiSearchResult` | record | 109 | Node + Score + CompareDescending |
| `TAIEmbeddingIndex` | class | 129 | Abstract index (BuildIndex, Add, Search, Clear) |
| `TAIBasicEmbeddingIndex` | class | 163 | Brute force linear search |
| `TAIEuclideanDistanceIndex` | class | 183 | L2 distance-based search |
| `THNSWIndex` | class | 217 | HNSW approximate nearest neighbor |
| `TAIBm25Index` | class | 258 | Lexical BM25 index (Tokenize, Search, StopWords) |

---

#### `uMakerAi.RAG.Vectors.VQL.pas` (1,571 lines)
**Purpose:** VGQL query language (Lexer → Parser → AST → Compiler → Request).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TVGQLTokenKind` | enum | 12 | 50+ token types |
| `TVGQLLexer` | class | 59 | Tokenizer (NextToken) |
| `TVGQLParser` | class | 320 | Recursive descent parser (Parse → TVGQLQuery AST) |
| `EVGQLParserError` | class | 318 | Exception |
| `TVGQLCompiler` | class | 425 | AST → TVGQLRequest compiler (Translate) |
| `EVGQLTranslationError` | class | 423 | Exception |
| `TVGQLRequest` | class | 363 | Executable request (Entity, Query, Mode, Weights, Filter, Limit, etc.) |

---

#### `uMakerAi.RAG.Vector.Driver.BinFile.pas` (1,180 lines)
**Purpose:** Binary file persistence driver (zero dependencies beyond RTL).

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiMkVecDriver` | class | 99 | Implements TAiVectorStoreDriverBase |
| `TAiMkVecDriver.Open()` | method | 170 | Open file |
| `TAiMkVecDriver.Compact()` | method | 172 | Compact file |
| `TAiMkVecDriver.Add/Search/Delete/Clear()` | method | 163-167 | CRUD |
| `TAiMkVecDriver.FilePath` | property | 178 | File path |

---

#### `uMakerAi.RAG.Vector.Driver.Postgres.pas` (975 lines)
**Purpose:** PostgreSQL driver with pgvector extension.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRAGVectorPostgresDriver` | class | 73 | Implements TAiVectorStoreDriverBase |
| `TAiRAGVectorPostgresDriver.CreateSchema()` | method | 103 | Create table + index |
| `TAiRAGVectorPostgresDriver.Connection` | property | 111 | `TFDConnection` (FireDAC) |

**External deps:** `FireDAC.Comp.Client`, `FireDAC.Stan.Param`, `FireDAC.DApt`, `Data.DB`. Requires PostgreSQL with `pgvector` extension.

---

#### `uMakerAi.RAG.Vector.Driver.SQLite.pas` (1,141 lines)
**Purpose:** SQLite driver with FTS5 and optional sqlite-vec extension.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRAGVectorSQLiteDriver` | class | 65 | Implements TAiVectorStoreDriverBase |
| `TAiRAGVectorSQLiteDriver.VecExtLoaded` | property | 117 | Whether sqlite-vec extension loaded |
| `TAiRAGVectorSQLiteDriver.Connection` | property | 119 | `TFDConnection` (FireDAC) |

**External deps:** `FireDAC.Comp.Client`, etc. Uses SQLite with FTS5 (native) and optional `sqlite-vec` extension.

---

#### `uMakerAi.RAG.Graph.Core.pas` (4,870 lines — largest file)
**Purpose:** Knowledge graph engine with Cypher-style querying, graph algorithms, and edge hydration.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRagGraphNode` | class | 267 | Graph node (inherits TAiEmbeddingNode), edges hydrated on access |
| `TAiRagGraphEdge` | class | 311 | Graph edge (inherits TAiEmbeddingNode), Weight, FromNode, ToNode |
| `TAiRagGraphDriverBase` | class | 238 | Abstract DB driver contract |
| `TAiRagGraph` | class | 348 | Main graph component |
| `TAiRagGraph.AddNode/NewNode(...)` | method | 396-399 | Node CRUD |
| `TAiRagGraph.AddEdge/NewEdge(...)` | method | 401-403 | Edge CRUD |
| `TAiRagGraph.FindNodeByID(ID)` | method | 409 | Node lookup |
| `TAiRagGraph.FindNodesByLabel(Label)` | method | 411 | Label query |
| `TAiRagGraph.Search(Query, ...)` | method | 433 | Semantic search over nodes |
| `TAiRagGraph.GetShortestPath(...)` | method | 427 | Dijkstra's algorithm |
| `TAiRagGraph.GetClosenessCentrality(...)` | method | 429 | Centrality algorithm |
| `TAiRagGraph.DetectCommunities()` | method | 430 | Community detection |
| `TAiRagGraph.ExecuteMakerGQL(...)` | method | 438-439 | MakerGQL execution |
| `TAiRagGraph.Match(Pattern)` | method | 442 | Pattern match query |
| `TAiRagGraph.GraphToContextText()` | method | 455 | Graph → LLM context text |
| `TAiRagGraph.SaveToStream/LoadFromStream(...)` | method | 423-431 | Persistence |
| `TAiRagGraph.ExtractSubgraph(...)` | method | 450 | Subgraph extraction |
| `TAiRagGraph.MergeNodes(MergeStrategy)` | method | 451 | Graph merge |
| `TGraphExpression` hierarchy | classes | 79-109 | Expression tree (Literal, Property, Binary) |
| `TGraphMatchQuery` | class | 185 | Pattern match with clauses |

**Dependencies:** `uMakerAi.Embeddings.Core`, `uMakerAi.RAG.Vectors.Index`, `uMakerAi.RAG.Vectors`, `uMakerAi.RAG.MetaData`, `Xml.XMLDoc`, `Xml.XMLIntf` (GraphML export)

---

#### `uMakerAi.RAG.Graph.GQL.pas` (869 lines)
**Purpose:** MakerGQL (Cypher-like) query language for graph queries.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TGraphCommandType` | enum | 60 | cmdNone, cmdShowLabels, cmdShowEdges, cmdShortestPath, cmdCentrality, cmdDegrees |
| `TGraphLexer` | class | 70 | Tokenizer (NextToken) |
| `TGraphParser` | class | 93 | Recursive descent parser (Parse → TGraphMatchQuery) |

---

#### `uMakerAi.RAG.Graph.Builder.pas` (526 lines)
**Purpose:** Build knowledge graphs from JSON triplets `[subject, predicate, object]`.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRagGraphBuilder` | class | 48 | JSON triplet → graph constructor |
| `TAiRagGraphBuilder.Process(JSONTriplets, MergeStrategy)` | method | 63 | Process triplets into nodes/edges |

---

#### `uMakerAi.RAG.Graph.Documents.pas` (2,221 lines)
**Purpose:** Document ingestion into knowledge graphs with LLM-based entity/relationship extraction.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRagDocumentManager` | class | 103 | Document manager |
| `TAiRagDocumentManager.AddDocument(Name/Text/MetaData)` | method | 147-151 | Ingest document |
| `TAiRagDocumentManager.ExtractRelationships(...)` | method | 154 | LLM-based relationship extraction |
| `TAiRagDocumentManager.ExtractEntitiesOnly(...)` | method | 157 | LLM-based entity extraction |
| `TAiRagDocumentManager.SearchDocuments(...)` | method | 175 | Search across documents |
| `TAiRagDocumentManager.GetDocumentContext(ID)` | method | 169-170 | Get document for LLM |
| `TAiRagDocumentManager.Chat` | property | 195 | `TAiChat` — LLM for entity extraction |

**Dependencies:** `uMakerAi.Chat` (TAiChat for LLM-based entity/relationship extraction)

---

#### `uMakerAi.RAG.Graph.Driver.Postgres.pas` (1,211 lines)
**Purpose:** PostgreSQL driver for graph persistence with pgvector.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiRagGraphPostgresDriver` | class | 13 | Implements TAiRagGraphDriverBase |
| `TAiRagGraphPostgresDriver.Connection` | property | 58 | `TFDConnection` (FireDAC) |

**External deps:** `FireDAC.Comp.Client`, `FireDAC.Stan.Param`, `Data.DB`. Requires PostgreSQL with `pgvector` extension.

---

#### `uMakerAi.RAG.MetaData.pas` (720 lines)
**Purpose:** Metadata storage and recursive filter criteria system.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiLanguage` | enum | 19 | alSpanish, alEnglish, alPortuguese, alCustom |
| `TFilterOperator` | enum | 26 | 20 operators (foEqual, foNotEqual, foGreater, ..., foExistsAll) |
| `TAiFilterCriteria` | class | 83 | Recursive filter tree (Add, AddGroup, AddEqual, LoadFromMetaData) |
| `TAiEmbeddingMetaData` | class | 119 | Node attribute store (Has, Get, Remove, Evaluate, Matches, ToJSON) |

---

### MCPCLIENT/ — Model Context Protocol Client (1 unit)

**Purpose:** Consume external MCP servers via 4 transport protocols (StdIO, HTTP, SSE, DataSnap).

#### `uMakerAi.MCPClient.Core.pas` (2,941 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `EMCPClientException` | class | 57 | Exception |
| `TMCPClientCustom` | class | 58 | Abstract base for all transports |
| `TMCPClientStdIo` | class | 162 | Local subprocess via stdin/stdout |
| `TMCPClientHttp` | class | 198 | Remote HTTP POST JSON-RPC |
| `TMCPClientSSE` | class | 254 | Server-Sent Events streaming |
| `TMCPClientMakerAi` | class | 221 | DataSnap-wrapped REST |
| `TMCPClientCustom.Initialize()` | method | 458 | Connect, get tools, mark available |
| `TMCPClientCustom.ListTools()` | method | 558 | Get tool list from server |
| `TMCPClientCustom.CallTool(Name, Args)` | method | 329-334 | Execute tool on server |
| `TMCPClientCustom.Disconnect()` | method | 686 | Close connection |
| `TMCPClientCustom.ProcessAndExtractMedia(...)` | method | 563 | Extract base64 binaries to TAiMediaFile |
| `TMCPClientStdIo.InternalSendRawMessage(...)` | method | 1280 | Write JSON + LF to stdin |
| `TMCPClientStdIo.InternalReceiveJSONResponse(...)` | method | 1297 | Pop from TThreadedQueue with timeout |
| `TMCPClientStdIo.ReadProcessOutput(...)` | method | 1188 | Background read thread |

**Dependencies:** `uMakerAi.Utils.System` (process management), `System.Net.HttpClient`, `System.Threading`, `Winapi.Windows` (MSWINDOWS)

---

### MCPSERVER/ — Model Context Protocol Server (6 units)

**Responsibility:** Expose Delphi AI tools via MCP protocols. JSON-RPC engine, 4 transport protocols, tool/resource registry, and TAiFunctions bridge.

#### `uMakerAi.MCPServer.Core.pas` (1,568 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiMCPResponseBuilder` | class | 60 | Fluent builder: AddText, AddFile, AddImage, Build |
| `IAiMCPTool` | interface | 116 | Tool contract: GetName, GetDescription, GetInputSchema, Execute |
| `TAiMCPToolBase<T: class>` | class | 129 | Generic tool via interface delegation |
| `IAiMCPResource` | interface | 148 | Resource contract: GetURI, GetName, GetDescription, GetMimeType, Read |
| `TAiMCPResourceBase<T>` | class | 159 | Generic resource implementation |
| `TAiMCPLogicServer` | class | 177 | Core JSON-RPC engine (non-visual) |
| `TAiMCPLogicServer.RegisterTool(Factory)` | method | 539 | Register tool factory |
| `TAiMCPLogicServer.Start()` | method | 563 | Instantiate tools/resources |
| `TAiMCPLogicServer.ExecuteRequest(JSON)` | method | 654 | Parse + dispatch JSON-RPC |
| `TAiMCPLogicServer.Tools_CallTool(Name, Args)` | method | 895 | Execute named tool |
| `TAiMCPServer` | class | 255 | TComponent wrapper for IDE integration |
| `TAiMCPServer.Start()` | method | 1545 | Register AiFunctions, start logic server |
| `TAiMCPServer.RegisterTool(...)` | method | 1462 | Delegate to LogicServer |

**RTTI Attributes:** `AiMCPSchemaDescriptionAttribute`, `AiMCPSchemaEnumAttribute`, `AiMCPOptional`

**Dependencies:** `System.Rtti` (schema generation), `Rest.JSON`, `uMakerAi.Tools.Functions`

---

#### Transport Implementations

| Unit | Class | Line | Transport |
|------|-------|------|-----------|
| `UMakerAi.MCPServer.Stdio.pas` | `TAiMCPStdioServer` | 59 | stdin/stdout (subprocess) with UTF-8 console |
| `UMakerAi.MCPServer.Http.pas` | `TAiMCPHttpServer` | 45 | Indy HTTP with CORS support |
| `UMakerAi.MCPServer.SSE.pas` | `TAiMCPSSEHttpServer` | 54 | Server-Sent Events (session-aware, TThreadedQueue) |
| `UMakerAi.MCPServer.Direct.pas` | `TAiMCPDirectConnection` | 47 | In-process zero-network for testing |
| `uMakerAi.MCPServer.Bridge.pas` | `TTAiFunctionToolProxy` | 15 | TAiFunctions → IAiMCPTool adapter |

**External deps:** `IdContext`, `IdCustomHTTPServer`, `IdHTTPServer` (Indy for HTTP/SSE)

---

### TOOLS/ — Capabilities Framework (17 units)

**Responsibility:** Function calling system, shell execution, text editing, computer automation, media generation (DALL-E, Sora, Veo, TTS), speech (Whisper, Gemini TTS), web search, OCR, vision.

#### `uMakerAi.Tools.Functions.pas` (4,425 lines — largest file)
**Purpose:** Core function calling infrastructure with multi-format support (OpenAI/Claude/Gemini/MCP), PPM package management, and AutoMCP subsystem.

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TFunctionActionItem` | class | 116 | Function definition: FunctionName, Description, Parameters, Script, OnAction |
| `TAiFunctions` | class | 299 | Main component |
| `TAiFunctions.GetTools(Format)` | method | 336 | Generate tools in requested format |
| `TAiFunctions.DoCallFunction(Name, Args)` | method | 337 | Execute tool call |
| `TAiFunctions.AddMCPClient(...)` | method | 348 | Register MCP client |
| `TAiFunctions.ImportClaudeMCPConfiguration(...)` | method | 351-354 | Parse Claude Desktop config |
| `TAiFunctions.InstallMCPFromPPM(...)` | method | 372 | Download + install PPM package |
| `TAiFunctions.SearchPPMMCP(...)` | method | 363 | Query PPM registry |
| `TAiFunctions.InitAutoMCP()` | method | 341 | Bootstrap mcp-ppm |
| `TMCPClientItem` | class | 191 | MCP client collection item |
| `TJsonToolUtils` | class | 429 | Cross-format normalization (MCP ↔ OpenAI ↔ Anthropic ↔ Gemini) |
| `TJsonToolUtils.NormalizeToolsFromSource(...)` | method | 459 | Detect format → normalize |
| `TJsonToolUtils.FormatToolList(...)` | method | 462 | Normalized → target format |

**Dependencies:** `uMakerAi.MCPClient.Core`, `System.Net.HttpClient`, `System.Zip`, `IniFiles`

---

#### `uMakerAi.Tools.Shell.pas` (741 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiShell` | class | 67 | Interactive shell execution |
| `TAiShell.StartSession()` | method | 271 | Launch shell process |
| `TAiShell.Execute(JSON)` | method | 463-478 | Auto-detect format, dispatch |
| `TAiShell.ExecuteClaudeAction(CallId, Args)` | method | 505 | Claude format |
| `TAiShell.ExecuteOpenAIAction(CallId, Args)` | method | 548 | OpenAI format |
| `TAiShell.CheckSecurity(Command)` | method | 230 | Allow/block list enforcement |
| `TAiShell.OnCommand` | event | 55 | Pre-execution intercept |
| `TAiShell.OnConsoleLog` | event | 56 | Post-execution log |

**Dependencies:** `uMakerAi.Utils.System` (process management)

---

#### `uMakerAi.Tools.TextEditor.pas` (445 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiTextEditorTool` | class | 74 | File editing tool |
| `TAiTextEditorTool.Cmd_View(Path, StartLine, EndLine)` | method | 289 | View file |
| `TAiTextEditorTool.Cmd_Create(Path, Content)` | method | 336 | Create file |
| `TAiTextEditorTool.Cmd_StrReplace(Path, Old, New)` | method | 352 | Replace exact match |
| `TAiTextEditorTool.Cmd_Insert(Path, Line, Content)` | method | 383 | Insert at line |
| `TAiTextEditorTool.Cmd_ApplyDiff(Path, Diff)` | method | 420 | Apply unified diff |
| `TAiTextEditorTool.OnLoadFile/OnSaveFile` | events | 68-69 | I/O virtualization |

**Dependencies:** `uMakerAi.Utils.DiffUpdater`

---

#### `uMakerAi.Tools.ComputerUse.pas` (412 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TAiComputerUseTool` | class | 69 | Base computer use component |
| `TAiComputerUseTool.DenormalizeCoordinate(X)` | method | 137 | Convert 0-1000 → screen pixels |
| `TAiComputerUseTool.ParseAction(ToolCall)` | method | 179 | Parse JSON → TAiActionData |
| `TAiComputerUseTool.ProcessToolCall(...)` | method | 304 | Safety check → execute → screenshot |
| `TAiComputerUseTool.OnExecuteAction` | event | 65 | Platform-specific execution |
| `TAiComputerUseTool.OnSafetyConfirmation` | event | 67 | Human approval |

#### Platform implementations:
| Unit | Class | Line | Platform |
|------|-------|------|----------|
| `uMakerAi.Tools.ComputerUse.Windows.pas` | `TAiWindowsExecutor` | 13 | VCL Windows (SendInput, BitBlt) |
| `uMakerAi.Tools.ComputerUse.WindowsFMX.pas` | `TAiWindowsFMXExecutor` | 14 | FMX Windows (with cursor overlay) |

---

#### Media Generation Tools

| Unit | Class | Lines | Description |
|------|-------|-------|-------------|
| `uMakerAi.OpenAi.Dalle.pas` | `TAiDalle` | 1,079 | Image gen (dall-e-2/3, gpt-image-1) with streaming |
| `uMakerAi.OpenAI.Sora.pas` | `TAiSoraGenerator` | 677 | Sora video gen (async polling) |
| `uMakerAi.Gemini.Veo.pas` | `TAiVeoGenerator` | 1,121 | Veo 2.0/3.0/3.1 video gen |
| `uMakerAi.Gemini.Video.pas` | `TAiGeminiVideoTool` | 305 | TAiVideoToolBase Veo wrapper |

#### Speech/Audio Tools

| Unit | Class | Lines | Description |
|------|-------|-------|-------------|
| `uMakerAi.OpenAI.Audio.pas` | `TAiOpenAiAudio` | 806 | OpenAI TTS + Transcription (GPT-4o) |
| `uMakerAi.OpenAI.Audio.Tool.pas` | `TAiOpenAiSpeechTool` | 365 | IAiSpeechTool wrapper for TAiOpenAiAudio |
| `uMakerAi.Gemini.Speech.pas` | `TAiGeminiSpeechTool` | 481 | Gemini TTS/STT (multi-voice, PCM→WAV) |
| `uMakerAi.Whisper.pas` | `TAIWhisper` | 608 | OpenAI Whisper (Speech, Transcription, Translation) |

#### Utility Tools

| Unit | Class | Lines | Description |
|------|-------|-------|-------------|
| `uMakerAi.Gemini.WebSearch.pas` | `TAiGeminiWebSearchTool` | 246 | Gemini Google Search grounding |
| `uMakerAi.Ollama.Ocr.pas` | `TAiOllamaOcrTool` | 272 | OCR via Ollama vision models |
| `uMakerAi.Ollama.Vision.pas` | `TAiOllamaVisionTool` | 313 | Image description via Ollama |

---

### EMBEDDINGS/ — Embedding Providers (13 units)

**Responsibility:** Embedding generation for vector search across 8 text embedding providers.

| Unit | Class | Lines | Provider |
|------|-------|-------|----------|
| `uMakerAi.Embeddings.core.pas` | `TAiEmbeddingsCore` | 589 | Abstract base |
| `uMakerAi.Embeddings.OpenAi.pas` | `TAiOpenAiEmbeddings` | 203 | OpenAI |
| `uMakerAi.Embeddings.Cohere.pas` | `TAiCohereEmbeddings` | 269 | Cohere |
| `uMakerAi.Embeddings.Gemini.pas` | `TAiGeminiEmbeddings` | 181 | Google Gemini |
| `uMakerAi.Embeddings.Ollama.pas` | `TAiOllamaEmbeddings` | 191 | Ollama local |
| `uMakerAi.Embeddings.Mistral.pas` | `TAiMistralEmbeddings` | 164 | Mistral |
| `uMakerAi.Embeddings.Generic.pas` | `TAiGenericEmbeddings` | 268 | OpenAI-compatible |
| `uMakerAi.Embeddings.LMStudio.pas` | `TAiLMStudioEmbeddings` | 97 | LM Studio local |
| `uMakerAi.Embeddings.Llamacpp.pas` | `TAiLlamacppEmbeddings` | 267 | Local GGUF |
| `uMakerAi.Embeddings.Connection.pas` | `TAiEmbeddingConnection` | 376 | Universal connector (switch via DriverName) |
| `uMakerAi.Embeddings.pas` | `TAiEmbeddings` | 287 | TComponent wrapper |
| `uMakerAi.Embedder.Import.pas` | — | 279 | `makerai.embedder.dll` wrapper |
| `uMakerAi.ErrorCodes.pas` | `TAiMkErrorCode` | 58 | DLL error codes |

**Entrypoint:**
`TAiEmbeddingsCore` → abstract class `function GetEmbedding(const Text: string): TArray<Single>` — returns embedding vector. Each provider overrides this.

---

### CHATUI/ — FMX Visual Components (3 units + ScreenCapture)

#### `uMakerAi.UI.ChatList.pas` (981 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TChatList` | class | 51 | TVertScrollBox-based chat container |
| `TChatList.AddBubble(Text, User, MediaFiles, Inbound)` | method | — | Add message bubble |
| `TChatList.Clear()` | method | — | Remove all bubbles |
| `TChatList.ScrollToBottom()` | method | — | Auto-scroll |
| `TChatList.SaveToStream/LoadFromStream(...)` | method | — | Persist chat history |
| `TChatList.InboundColor/OutboundColor` | property | — | Bubble color settings |
| `TChatList.MaxBubbleWidthPercent` | property | — | 0.1–1.0 |

#### `uMakerAi.UI.ChatBubble.pas` (2,078 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TChatBubble` | class | 60 | Custom-painted message bubble |
| `TChatBubble.AddContent(Text, MediaFiles)` | method | — | Clear and rebuild content |
| `TChatBubble.AppendText(Fragment)` | method | — | Streaming text append |
| `TChatBubble.TailPosition` | property | — | tpLeft (inbound) / tpRight (outbound) |
| `TChatBubble.TailStyle` | property | — | tsSimple, tsOrganic, tsComic, tsSharp |
| `TChatBubble.ToJsonObject/LoadFromJsonObject(...)` | method | — | Serialization |

#### `uMakerAi.UI.ChatInput.pas` (2,397 lines)

| Entrypoint | Kind | Line | Description |
|-----------|------|------|-------------|
| `TChatInput` | class | 73 | Multi-modal input (text, files, voice, drag-drop) |
| `TChatInput.OnSendEvent` | event | 56 | Fires: Prompt + MediaFiles + AudioStream |
| `TChatInput.AddAttachment(File/Stream)` | method | — | Add to carousel |
| `TChatInput.ClearAttachments()` | method | — | Remove all |
| `TChatInput.Busy` | property | — | True → show cancel, disable input |
| `TChatInput.VoiceMonitor` | property | — | TAIVoiceMonitor integration |

**Dependencies:** All FMX components use `FMX.Types`, `FMX.Controls`, `FMX.Graphics`, `FMX.Layouts`, `uMakerAi.Core` (TAiMediaFile)

---

### DESIGN/ — IDE Property Editors (8 units)

**Purpose:** Delphi IDE design-time editors and property inspectors.

| Unit | Class | Description |
|------|-------|-------------|
| `uAiEditors.ChatConnectionEditor.pas` | `TChatConnectionEditor` | TAiChatConnection property editor |
| `uAiEditors.EmbeddingConnectionEditor.pas` | `TEmbeddingConnectionEditor` | TAiEmbeddingConnection editor |
| `uAiEditors.RequiresUnits.pas` | `TRequiresUnitsEditor` | Required units property editor |
| `uMCPClientEditor.pas` | `TFMCPClientEditor` | MCP client component editor |
| `uMCP.ClientEditorProperties.pas` | `TMCPClientProperty` | MCP client property inspector |
| `UMakerAi.ParamsRegistry.pas` | `TParamsRegistryEditor` | Params registry property editor |
| `uMakerAi.Dsg.AboutDialog.pas` | `TAboutDialog` | About box |
| `uMakerAi.VersionPropertyEditor.pas` | `TVersionPropertyEditor` | Version display |

**Dependencies:** `VCL` + `designide` (design-time only, not in runtime packages)

---

### UTILS/ — Cross-Platform Utilities (5 units)

| Unit | Class | Lines | Description |
|------|-------|-------|-------------|
| `uMakerAi.Utils.AudioPushStream.pas` | `TAudioPushStream` | 1,239 | Cross-platform push-stream audio player |
| `uMakerAi.Utils.DiffUpdater.pas` | `TDiffParser`, `TDiffApplier` | 427 | Unified diff parsing and application |
| `uMakerAi.Utils.Python.pas` | `TUtilsPython` | 377 | Python script execution via Python4Delphi |
| `uMakerAi.Utils.ScreenCapture.pas` | `TScreenCapture` | 557 | Screen region capture (Windows/macOS) |
| `uMakerAi.Utils.VoiceMonitor.pas` | `TAIVoiceMonitor` | 1,741 | Voice activity detection + transcription |

---

## External Technology & Package Dependencies

### Delphi Standard Libraries
| Library | Used By | Purpose |
|---------|---------|---------|
| `System.Net.HttpClient` | Chat, Core, MCPClient, Embeddings | HTTP/S API communication |
| `System.JSON` | ALL modules | JSON-RPC, tool definitions, serialization |
| `System.NetEncoding` | Core, Chat, MCPClient | Base64 encoding, URL encoding |
| `System.Threading` | Agents, MCPClient, Tools | TThreadPool, ITask, TThread.Queue |
| `System.Rtti` | Agents, MCPServer, Design | Tool discovery, schema generation |
| `System.Bindings.*` | Agents | Expression evaluation (BindingEngine) |
| `System.SyncObjs` | Multiple | TCriticalSection, TMonitor, TInterlocked |
| `System.Generics.Collections` | ALL modules | TDictionary, TList, TObjectList, TThreadedQueue |

### Third-Party/Platform Libraries
| Library | Used By | Purpose |
|---------|---------|---------|
| `FireDAC` (FireDAC.Comp.Client, Stan.Param, DApt) | RAG drivers | PostgreSQL + SQLite database access |
| Indy (`IdHTTPServer`, `IdContext`, `IdGlobal`) | MCPServer HTTP/SSE | HTTP server with CORS |
| `REST.Client`, `REST.Types` | Whisper, Gemini drivers | REST API calls |
| `PythonEngine` (Python4Delphi) | Utils | Python script execution |
| `Xml.XMLDoc`, `Xml.XMLIntf` | RAG Graph | GraphML export |
| `Winapi.Windows/Winapi.MMSystem` | AudioPushStream, VoiceMonitor, ComputerUse | Windows audio + input APIs |
| `Winapi.ShellAPI` | Utils (System) | ShellExecute for file opening |
| `Posix.*` (Linux) | Utils (System) | Process management on Linux/macOS |
| `Androidapi.JNI.Media` | AudioPushStream, VoiceMonitor | Android audio APIs |
| `iOSapi.AudioToolbox` | AudioPushStream | iOS audio APIs |

### Database Drivers
| Driver | Database | Extension | Lines |
|--------|----------|-----------|-------|
| `TAiMkVecDriver` (BinFile) | Binary file | None | 1,180 |
| `TAiRAGVectorPostgresDriver` | PostgreSQL | `pgvector` | 975 |
| `TAiRAGVectorSQLiteDriver` | SQLite | `FTS5` + optional `sqlite-vec` | 1,141 |
| `TAiRagGraphPostgresDriver` | PostgreSQL | `pgvector` | 1,211 |

### Native DLL Dependencies
| DLL | Wrapper Unit | Purpose |
|-----|-------------|---------|
| `makerai.gen.dll` | `uMakerAi.Gen.Import.pas` | llama.cpp GGUF text generation |
| `makerai.embedder.dll` | `uMakerAi.Embedder.Import.pas` | Local embedding generation |
| `ffmpeg` | Whisper, Gemini Speech | Audio format conversion |

### Package Dependency Chain
```
MakerAI.dpk (standalone — ~98 units)
    ^
    ├── MakerAi.RAG.Drivers.dpk (requires MakerAI + FireDAC)
    ├── MakerAi.UI.dpk (requires MakerAI + FMX)
    └── MakerAiDsg.dpk (requires MakerAI + VCL + DesignIDE)
```

---

## Coverage Analysis

### Current Coverage vs Total Codebase

| Module | Units | Types Documented | Total Types (est.) | Coverage |
|--------|-------|-----------------|-------------------|-------|
| Core | 12 | 45 | ~55 | ~82% |
| Chat | 18 | 28 | ~50 | ~56% |
| Agents | 11 | 35 | ~45 | ~78% |
| RAG | 12 | 40 | ~55 | ~73% |
| MCPClient | 1 | 9 | ~15 | ~60% |
| MCPServer | 6 | 18 | ~30 | ~60% |
| Tools | 17 | 25 | ~45 | ~56% |
| ChatUI | 3 | 8 | ~12 | ~67% |
| Embeddings | 13 | 4 | ~20 | ~20% |
| Design | 8 | 8 | ~12 | ~67% |
| Utils | 5 | 8 | ~12 | ~67% |
| **TOTAL** | **106** | **228** | **~351** | **~65%** |

### Coverage Delta: What was 20%, what is now 65%

Previous diagram covered: ~50 classes/functions across 9 modules (20%).

This update covers: ~228 key types across all 106 `.pas` files (65%).

Remaining 35%: internal implementation types, private helper methods, record types, worker threads, and internal proxy classes. These are not part of the public API surface but exist in the codebase.

---

## What's Missing to Reach "100%"

### Public API (should be in diagram):
1. **Embeddings module details** (20% → need 80%): each provider's `GetEmbedding` method, `TAiEmbeddingConnection` properties, `TAiEmbeddingsCore` abstract contract. (Partial — covered above in table)
2. **Chat driver-specific methods**: Each driver's `ProcessStreamChunk`, `ParseChat`, `GetModels`, API endpoint URLs. (Partial — driver table exists but not per-method detail)
3. **Design module details**: All 8 property editor Create/Edit methods. (Summary table exists)

### Internal Implementation (NOT in public API — out of scope for 100%):
1. Private helper methods within each class (e.g., `BuildHeaders`, `InternalSendRequest`, etc.)
2. Internal proxy/adapter classes (e.g., `TAiFunctionItem_IAiTool`, `TAiSchemaTool`)
3. Worker threads (e.g., `TStdioWorkerThread`, reader/writer threads)
4. Record types for internal data transfer (e.g., `TNodeFileEntry`, `TQueryPlan`)
5. Parser implementation details (e.g., VGQL parser mutator methods)

**Recommendation for 100% public API coverage:** Expand level-3 detail for Embeddings module (per-provider method signatures) and Chat drivers (per-driver `Run/ParseChat/GetMessages` signatures with line numbers). Everything else is at ≥60%.

---

## Chat State Machine

```
acsIdle → acsConnecting → acsCreated → [acsReasoning] → acsWriting
                                                              │
                    ┌─────────────────────────────────────────┤
                    ▼                                         ▼
             acsToolCalling                              acsFinished
                    │                                    acsError
                    ▼                                    acsAborted
             acsToolExecuting
                    │
                    └──→ loop back to acsWriting
```

Additional states: `acsLoading`, `acsProcessing` for internal work.

---

## Agent Graph Execution Model

```
TAIAgentManager.FThreadPool (TThreadPool)
    │
    ├── TAIAgentsNode (each)
    │   ├── OnExecute → pool thread
    │   ├── Inputs[] → from upstream (jmAny / jmAll)
    │   ├── TAIBlackboard → shared state (TCriticalSection)
    │   └── Tool (TAiToolBase) → optional attached tool
    │
    ├── TAIAgentsLink (edges)
    │   ├── Mode: lmFanout | lmConditional | lmManual | lmExpression
    │   ├── Targets: NextA/B/C/D/No
    │   └── ConditionalKey → Blackboard lookup
    │
    ├── TAiCheckpointer (optional)
    │   ├── Suspend → JSON snapshot
    │   ├── Resume → restore + continue
    │   └── TAiFileCheckpointer → JSON on disk
    │
    └── TAiToolRegistry (optional)
        ├── Local tools → IAiTool instances
        ├── MCP tools → via TAiMCPTool adapter
        └── PPM tools → download + install from registry
```

---

## Model Capabilities Bridge System (v3.3)

```
TUser runs Chat.Run(prompt)
    │
    v
TAiChat.RunNew()
    │
    v
EnsureNewSystemConfig()
    │
    ├── Has ModelCaps been set?
    │   ├── YES → skip legacy translation (FNewSystemConfigured=True)
    │   └── NO  → translate from NativeInputFiles/ChatMediaSupports/EnabledFeatures/NativeOutputFiles
    │
    ├── Gap = SessionCaps − ModelCaps
    │   │
    │   ├── cap_GenImage ∈ Gap  → TAiChatImageBridge (delegate to ImageTool)
    │   ├── cap_GenAudio ∈ Gap  → TAiChatSpeechBridge
    │   ├── cap_GenVideo ∈ Gap  → TAiChatVideoBridge
    │   ├── cap_Image ∈ Gap     → TAiChatVisionBridge
    │   ├── cap_Pdf ∈ Gap       → TAiChatDocumentBridge
    │   ├── cap_GenReport ∈ Gap → TAiChatReportBridge
    │   └── ...
    │
    v
Execute via provider's Run() or bridge
```

---

## Thread Safety Map

| Lock | Class | File | Protects |
|------|-------|------|----------|
| `FLock` | `TAiChatMessage` | `uMakerAi.Chat.Messages.pas` | Media file list |
| `FLock` | `TAIBlackboard` | `uMakerAi.Agents.pas:105` | Shared state dictionary |
| `FJoinLock` | `TAIAgentsNode` | `uMakerAi.Agents.pas` | Join counter |
| `FActiveTasksLock` | `TAIAgentManager` | `uMakerAi.Agents.pas` | Active task count |
| `FSuspendedStepsLock` | `TAIAgentManager` | `uMakerAi.Agents.pas` | Suspension queue |
| `FOutputLock` | `TAiMCPStdioServer` | `UMakerAi.MCPServer.Stdio.pas` | Stdout writes |
| `FSessionsLock` | `TAiMCPSSEHttpServer` | `UMakerAi.MCPServer.SSE.pas` | SSE session list |
| `FCS` | `TAIVoiceMonitor` | `uMakerAi.Utils.VoiceMonitor.pas` | Audio capture state |
| `FLock` | `TAiFileCheckpointer` | `uMakerAi.Agents.Checkpoint.pas` | File I/O |
| `TMultiReadExclusiveWriteSynchronizer` | `TAiRAGVector` | `uMakerAi.RAG.Vectors.pas` | Concurrent search/write access |

---

## Error Handling Map

| Exception | File | When |
|-----------|------|------|
| `EVGQLParserError` | `uMakerAi.RAG.Vectors.VQL.pas:318` | Invalid VQL syntax |
| `EVGQLTranslationError` | `uMakerAi.RAG.Vectors.VQL.pas:423` | VQL→Request compilation failure |
| `EMCPClientException` | `uMakerAi.MCPClient.Core.pas:57` | MCP transport/protocol error |
| `EPythonArchitectureError` | `uMakerAi.Utils.Python.pas:136` | x86 vs x64 Python mismatch |
| `EAiToolNotFound` | `uMakerAi.Agents.ToolRegistry.pas:38` | Tool lookup failure |
