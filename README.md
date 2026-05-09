# MakerAI Suite v3.3 â€” The AI Ecosystem for Delphi

ðŸŒ **Official Website:** [https://makerai.cimamaker.com](https://makerai.cimamaker.com)

[![GitHub Stars](https://img.shields.io/github/stars/gustavoeenriquez/MakerAi?style=social)](https://github.com/gustavoeenriquez/MakerAi)
[![GitHub Issues](https://img.shields.io/github/issues/gustavoeenriquez/MakerAi)](https://github.com/gustavoeenriquez/MakerAi/issues)
[![License](https://img.shields.io/github/license/gustavoeenriquez/MakerAi)](LICENSE.txt)
[![Telegram](https://img.shields.io/badge/Join-Telegram%20Chat-blue.svg)](https://t.me/+7LaihFwqgsk1ZjQx)
[![Delphi Supported Versions](https://img.shields.io/badge/Delphi%20Support-11%20Alexandria%20to%2013%20Florence-blue.svg)](https://www.embarcadero.com/products/delphi)
[![Free Pascal](https://img.shields.io/badge/Free%20Pascal-3.2%2B-orange.svg)](https://github.com/gustavoeenriquez/MakerAi/tree/fpc)

> **Free Pascal / Lazarus port available** â€” Full port of MakerAI Suite for FPC 3.2+ (12 LLM drivers, RAG, Agents, MCP, Embeddings). See the [`fpc` branch](https://github.com/gustavoeenriquez/MakerAi/tree/fpc).

---

## MakerAI is more than an API wrapper

Most AI libraries for Delphi stop at wrapping REST calls. **MakerAI is different.**

Yes, MakerAI includes **native, provider-specific components** that give you direct, full-fidelity access to each provider's API â€” every model parameter, every response field, every streaming event, exactly as the provider defines it.

But on top of that, MakerAI is a **complete AI application ecosystem** that lets you build production-grade intelligent systems entirely in Delphi:

- **RAG pipelines** (vector and graph-based) with SQL-like query languages (VQL / GQL)
- **Autonomous Agents** with graph orchestration, checkpoints, and human-in-the-loop approval
- **MCP Servers and Clients** â€” expose or consume tools using the Model Context Protocol
- **Native ChatTools** â€” bridge AI reasoning with deterministic real-world capabilities (PDF, Vision, Speech, Web Search, Shell, Computer Use)
- **FMX Visual Components** â€” drop-in UI for multimodal chat interfaces
- **Universal Connector** â€” switch providers at runtime without changing your application code

Whether you need a simple one-provider integration or a multi-agent, multi-provider, retrieval-augmented production system, MakerAI covers the full stack â€” **natively in Delphi**.

---

## ðŸš€ What's New in v3.3

### TAiCapabilities â€” Unified Model Configuration System

The biggest architectural change in v3.3 is the **`TAiCapabilities`** system, which replaces scattered per-provider flags with a unified, declarative model of what each model can do and what a session needs:

- **`ModelCaps`** â€” what the model natively supports (e.g. `[cap_Image, cap_Reasoning]`)
- **`SessionCaps`** â€” what capabilities the current session requires
- **Gap analysis** â€” when `SessionCaps` exceeds `ModelCaps`, MakerAI automatically activates bridges (tool-assisted OCR, vision bridges, etc.) without changing your code
- **`ThinkingLevel`** â€” unified reasoning depth control (`tlLow`, `tlMedium`, `tlHigh`) across all providers that support extended thinking

### Models Updated (February 2026)

| Provider | New / Updated Models |
|----------|----------------------|
| OpenAI | **gpt-5.2**, gpt-image-1, o3, o3-mini |
| Claude | **claude-opus-4-6**, **claude-sonnet-4-6**, claude-3-7-sonnet |
| Gemini | **gemini-3.0**, gemini-2.5-flash, gemini-2.5-flash-image |
| Grok | **grok-4**, grok-3, grok-imagine-image |
| Mistral | Magistral (reasoning), mistral-ocr-latest |
| DeepSeek | deepseek-reasoner (extended thinking) |
| Kimi | kimi-k2.5 (extended thinking) |

### Agents â€” Durable Execution & Human-in-the-Loop

- **`TAiFileCheckpointer`** â€” persists agent graph state to disk; resume workflows after crashes or restarts
- **`TAiWaitApprovalTool`** â€” suspends a node and waits for human approval before continuing
- `TAIAgentManager.OnSuspend` event for building approval UIs
- `ResumeThread(ThreadID, NodeName, Input)` to continue suspended workflows

### RAG â€” Graph Document Management

- New **`uMakerAi.RAG.Graph.Documents.pas`** â€” full document lifecycle management (ingest, chunk, embed, link) directly into the knowledge graph

### Cross-Provider Reasoning Fixes

- `reasoning_content` is now correctly preserved and re-sent in multi-turn tool call conversations for all providers that require it (DeepSeek-reasoner, Kimi k2.5, Groq reasoning models)

### Other Additions

- **`TAiEmbeddingsConnection`** â€” abstract connector for swappable embedding providers
- **`TAiAudioPushStream`** â€” push-based audio streaming utility
- **Demo 027** â€” Document Manager
- **Demo 012** â€” ChatWebList (chat with web-based content)

### Bug Fixes (March 2026)

- **MCP concurrent tool calls â€” race condition** (`uMakerAi.MCPClient.Core.pas`): When a model responded with two or more tools from the same MCP server in a single turn, `ParseChat` launched all tool calls as parallel `TTask`s. Since `TMCPClientStdIo` shares a single process/pipe per instance (no synchronization), concurrent calls corrupted the JSON-RPC communication, causing intermittent failures. Fixed by adding `FCallLock: TCriticalSection` to `TMCPClientCustom` â€” calls to the same server are now serialized while calls to different servers still run in parallel.

- **`EAggregateException` on tool errors â€” Claude driver** (`uMakerAi.Chat.Claude.pas`): The local `_CreateTask` procedure in `TAiClaudeChat.ParseChat` lacked the `try/except` present in the base class. Any exception raised inside a tool task (MCP timeout, network error, etc.) escaped unhandled, causing `TTask.WaitForAll` to wrap it in an `EAggregateException` and crash the application. Fixed to match base class behavior: exceptions are caught, reported via `OnError`, and the tool receives an error response so the conversation can continue.

---

## ðŸ—ï¸ Architecture

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Your Delphi Application                                         â”‚
â””â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
     â”‚                  â”‚                 â”‚
â”Œâ”€â”€â”€â”€â–¼â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ ChatUI  â”‚   â”‚ Agents             â”‚  â”‚ Design-Time               â”‚
â”‚ FMX     â”‚   â”‚ TAIAgentManager    â”‚  â”‚ Property Editors          â”‚
â”‚ Visual  â”‚   â”‚ TAIBlackboard      â”‚  â”‚ Object Inspector support  â”‚
â”‚ Comps   â”‚   â”‚ Checkpoint/Approve â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
â””â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
     â”‚                  â”‚
â”Œâ”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  TAiChatConnection  â€” Universal Connector                        â”‚
â”‚  Switch provider at runtime via DriverName property             â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                               â”‚
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Native Provider Drivers  (direct API access, full fidelity)     â”‚
â”‚  OpenAI Â· Claude Â· Gemini Â· Grok Â· Mistral Â· DeepSeek Â· Kimi    â”‚
â”‚  Groq Â· Cohere Â· Ollama Â· LM Studio Â· GenericLLM                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                               â”‚
     â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
     â”‚                         â”‚                        â”‚
â”Œâ”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  ChatTools  â”‚   â”‚  RAG                â”‚   â”‚  MCP                â”‚
â”‚  PDF/Vision â”‚   â”‚  Vector (VQL)       â”‚   â”‚  Server (HTTP/SSE   â”‚
â”‚  Speech/STT â”‚   â”‚  Graph (GQL)        â”‚   â”‚  StdIO/Direct)      â”‚
â”‚  Web Search â”‚   â”‚  PostgreSQL/SQLite  â”‚   â”‚  Client             â”‚
â”‚  Shell      â”‚   â”‚  HNSW Â· BM25 Â· RRF  â”‚   â”‚  TAiFunctions bridgeâ”‚
â”‚  ComputerUseâ”‚   â”‚  Rerank Â· Documents â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## ðŸ“¡ Supported AI Providers

MakerAI gives you **two ways to work with each provider**, which you can mix freely:

### Direct Provider Components
Full, provider-specific access to every API feature. Use when you need complete control:

| Component | Provider | Latest Models |
|-----------|----------|---------------|
| `TAiOpenChat` | OpenAI | gpt-5.2, o3, o3-mini |
| `TAiClaudeChat` | Anthropic | claude-opus-4-6, claude-sonnet-4-6 |
| `TAiGeminiChat` | Google | gemini-3.0, gemini-2.5-flash |
| `TAiGrokChat` | xAI | grok-4, grok-3 |
| `TAiMistralChat` | Mistral AI | Magistral, mistral-large |
| `TAiDeepSeekChat` | DeepSeek | deepseek-reasoner, deepseek-chat |
| `TAiKimiChat` | Moonshot | kimi-k2.5 |
| `TAiGroqChat` | Groq | llama-3.3, deepseek-r1 |
| `TCohereChat` | Cohere | command-r-plus |
| `TAiOllamaChat` | Ollama | Any local model |
| `TAiLMStudioChat` | LM Studio | Any local model |
| `TAiGenericChat` | OpenAI-compatible | Any OpenAI-API endpoint |

### Universal Connector
Provider-agnostic code. Switch models or providers by changing one property:

```pascal
AiConn.DriverName := 'OpenAI';
AiConn.Model := 'gpt-5.2';
AiConn.ApiKey := '@OPENAI_API_KEY';  // resolved from environment variable

// Switch to Gemini without changing anything else
AiConn.DriverName := 'Gemini';
AiConn.Model := 'gemini-3.0-flash';
AiConn.ApiKey := '@GEMINI_API_KEY';
```

---

## ðŸ“Š Feature Support Matrix

| Feature | OpenAI (gpt-5.2) | Claude (4.6) | Gemini (3.0) | Grok (4) | Mistral | DeepSeek | Ollama |
|:--------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Text Generation | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| Streaming (SSE) | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| Function Calling | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| JSON Mode / Schema | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| Image Input | âœ… | âœ… | âœ… | âœ… | âœ… | âŒ | âœ… |
| PDF / Files | âœ… | âœ… | âœ… | âš ï¸ | âœ… | âŒ | âš ï¸ |
| Image Generation | âœ… | âŒ | âœ… | âœ… | âŒ | âŒ | âŒ |
| Video Generation | âœ… | âŒ | âœ… | âŒ | âŒ | âŒ | âŒ |
| Extended Thinking | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âš ï¸ |
| Speech (TTS/STT) | âœ… | âŒ | âœ… | âŒ | âŒ | âŒ | âš ï¸ |
| Web Search | âœ… | âœ… | âœ… | âœ… | âŒ | âŒ | âŒ |
| Computer Use | âœ… | âœ… | âŒ | âŒ | âŒ | âŒ | âŒ |
| RAG (all modes) | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| MCP Client/Server | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |
| Agents | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… | âœ… |

> **Legend:** âœ… Native | âš ï¸ Tool-Assisted bridge | âŒ Not Supported

---

## ðŸ§© Ecosystem Modules

### ðŸ§  RAG â€” Retrieval-Augmented Generation

Two complementary retrieval engines with their own query languages:

**Vector RAG** â€” semantic and hybrid search over document embeddings:
- HNSW index for approximate nearest-neighbor search
- BM25 lexical index for keyword matching
- Hybrid search with RRF (Reciprocal Rank Fusion) or weighted fusion
- Reranking and Lost-in-the-Middle reordering for LLM context
- **VQL** (Vector Query Language) â€” SQL-like DSL for complex retrieval queries:
  ```sql
  MATCH documents SEARCH 'machine learning'
  USING HYBRID WEIGHTS(semantic: 0.7, lexical: 0.3) FUSION RRF
  WHERE category = 'tech' AND date > '2025-01-01'
  RERANK 'neural networks' WITH REGENERATE
  LIMIT 10
  ```
- Drivers: PostgreSQL/pgvector, SQLite, in-memory

**Graph RAG** â€” knowledge graph with semantic search over entities and relationships:
- Nodes and edges with embeddings and metadata
- **GQL** (Graph Query Language) â€” Cypher-like DSL:
  ```cypher
  MATCH (p:Person)-[r:WORKS_AT]->(c:Company)
  WHERE c.city = 'Madrid' DEPTH 2
  RETURN p, r, c
  ```
- Dijkstra shortest path, centrality analysis, hub detection
- Export to GraphViz DOT, GraphML (Gephi), native JSON format
- Document lifecycle management (ingest â†’ chunk â†’ embed â†’ link)

### ðŸ¤– Agents â€” Autonomous Orchestration

Graph-based multi-agent workflows with full thread safety:

- **`TAIAgentManager`** â€” executes directed graphs of AI nodes via thread pool
- **`TAIAgentsNode`** â€” single execution unit; runs an LLM call, a tool, or custom logic
- **`TAIBlackboard`** â€” thread-safe shared state dictionary between all nodes
- **Link modes:** `lmFanout` (parallel broadcast), `lmConditional` (routing), `lmExpression` (binding), `lmManual`
- **Join modes:** `jmAny` (first arrival wins), `jmAll` (wait for all inputs)
- **Durable execution:** `TAiFileCheckpointer` persists state; resume after crashes
- **Human-in-the-loop:** `TAiWaitApprovalTool` suspends execution for human approval
- Supports any LLM provider via `TAiChatConnection`

### ðŸ”— MCP â€” Model Context Protocol

Full implementation of the MCP standard for both consuming and exposing tools:

**MCP Server** â€” expose Delphi functions as MCP tools, callable by any MCP client (Claude Desktop, AI agents, etc.):
- Transports: **HTTP**, **SSE** (Server-Sent Events), **StdIO**, **Direct** (in-process)
- Bridge `TAiFunctions â†’ IAiMCPTool` â€” any existing `TAiFunctions` component becomes an MCP server instantly
- API Key authentication, CORS configuration
- `TAiMCPResponseBuilder` for structured responses (text + files + media)
- RTTI-based automatic JSON Schema generation from parameter classes

**MCP Client** â€” consume any external MCP server from your Delphi app:
- Connect to Claude Desktop tools, filesystem servers, database tools, etc.
- Integrated into `TAiFunctions` component alongside native function definitions

### ðŸ› ï¸ ChatTools â€” AI Ã— Deterministic Capabilities

ChatTools bridge the gap between AI reasoning and real-world operations. They activate automatically based on gap analysis between `SessionCaps` and `ModelCaps`:

| Tool Interface | What it does | Implementations |
|----------------|-------------|-----------------|
| `IAiPdfTool` | Extract text from PDFs | Mistral OCR, Ollama OCR |
| `IAiVisionTool` | Describe / analyze images | Any vision model |
| `IAiSpeechTool` | Text-to-speech / speech-to-text | Whisper, Gemini Speech, OpenAI TTS |
| `IAiWebSearchTool` | Live web search | Gemini Web Search |
| `IAiImageTool` | Generate images | DALL-E 3, gpt-image-1, Gemini, Grok |
| `IAiVideoTool` | Generate video | Sora, Gemini Veo |
| `TAiShell` | Execute shell commands | Windows/Linux |
| `TAiTextEditorTool` | Read/write/patch files | Diff-based editing |
| `TAiComputerUseTool` | Control mouse and keyboard | Claude Computer Use, OpenAI |

Tools follow a common pattern: `SetContext(AiChat)` + `Execute*()`. They can run standalone, as function-call bridges, or as automatic capability bridges.

### ðŸŽ¨ FMX Visual Components

Drop-in FireMonkey components for building multimodal chat UIs:

- **`TChatList`** â€” scrollable message container with Markdown rendering, code blocks, copy buttons
- **`TChatBubble`** â€” individual message bubble (user / assistant / tool)
- **`TChatInput`** â€” text input bar with voice recording, file attachment, and send button

Compatible with all providers. Works with streaming responses.

### ðŸ“ Design-Time Integration

Full Delphi IDE support via the `MakerAiDsg.dpk` design-time package:
- `DriverName` property shows a dropdown of all registered providers in the Object Inspector
- `Model` property lists all models for the selected provider
- MCP Client configuration editor with transport type selection
- Embedding connection editor
- Version/About dialog

---

## ðŸ“¦ Installation

```bash
git clone https://github.com/gustavoeenriquez/MakerAi.git
```

### Package Compilation Order

Compile and install in this exact order:

1. `Source/Packages/MakerAI.dpk` â€” Runtime core (~100 units)
2. `Source/Packages/MakerAi.RAG.Drivers.dpk` â€” PostgreSQL/pgvector connector
3. `Source/Packages/MakerAi.UI.dpk` â€” FMX visual components
4. `Source/Packages/MakerAiDsg.dpk` â€” Design-time editors (requires VCL + DesignIDE)

Open `Source/Packages/MakerAiGrp.groupproj` to compile all packages at once.

### Required Library Paths

Add all of these to **Tools > Options > Language > Delphi > Library**:

```
Source/Agents
Source/Chat
Source/ChatUI
Source/Core
Source/Design
Source/MCPClient
Source/MCPServer
Source/Packages
Source/RAG
Source/Resources
Source/Tools
Source/Utils
```

### API Keys

API keys are resolved from environment variables using the `@VAR_NAME` convention:

```pascal
AiConn.ApiKey := '@OPENAI_API_KEY';    // reads OPENAI_API_KEY from environment
AiConn.ApiKey := '@CLAUDE_API_KEY';    // reads CLAUDE_API_KEY
AiConn.ApiKey := '@GEMINI_API_KEY';    // reads GEMINI_API_KEY
AiConn.ApiKey := 'sk-...';             // or set a literal key directly
```

### Delphi Version Compatibility

| Delphi Version | Support |
|----------------|---------|
| 10.4 Sydney | Minimum (core framework) |
| 11 Alexandria | Full support |
| 12 Athens | Full support |
| 13 Florence | Full support (latest tested) |

---

## ðŸ—‚ï¸ Demo Projects

Open `Demos/DemosVersion31.groupproj` to access all demos.

| Demo | Description |
|------|-------------|
| `010-Minimalchat` | Minimal chat with Ollama and TAiChatConnection |
| `012-ChatAllFunctions` | Full-featured multimodal chat (images, audio, streaming, tools) |
| `012-ChatWebList` | Chat with web-based content list |
| `021-RAG+Postgres-UpdateDB` | Build a vector RAG database with PostgreSQL/pgvector |
| `022-1-RAG_SQLite` | Lightweight vector RAG with SQLite |
| `023-RAGVQL` | VQL query language for semantic search |
| `025-RAGGraph` | Knowledge graph RAG with GQL queries |
| `026-RAGGraph-Basic` | Simplified graph RAG patterns |
| `027-DocumentManager` | Document ingestion and management |
| `031-MCPServer` | Multi-protocol MCP server (HTTP, SSE, StdIO) |
| `032-MCP_StdIO_FileManager` | File manager exposed via MCP StdIO |
| `032-MCPServerDataSnap` | MCP server using DataSnap transport |
| `034-MCPServer_Http_FileManager` | File manager via MCP HTTP |
| `035-MCPServerWithTAiFunctions` | TAiFunctions bridge to MCP |
| `036-MCPServerStdIO_AiFunction` | StdIO MCP server with AI functions |
| `041-GeminiVeo` | Video generation with Google Veo |
| `051-AgentDemo` | Visual agent graph builder and runner |
| `052-AgentConsole` | Console-based agent execution |
| `053-DemoAgentesTools` | Agents with integrated tool use |

---

## ðŸ”„ Changelog

### v3.3 (February 2026)
- New `TAiCapabilities` system (`ModelCaps` / `SessionCaps` / `ThinkingLevel`)
- Models updated: OpenAI gpt-5.2, Claude 4.6, Gemini 3.0, Grok 4, Mistral Magistral, DeepSeek-reasoner, Kimi k2.5
- Agents: durable execution (checkpoints), human-in-the-loop approval tool
- RAG: Graph Document management (`uMakerAi.RAG.Graph.Documents`)
- Fix: `reasoning_content` preserved in multi-turn tool calls (DeepSeek, Kimi, Groq)
- New: `TAiEmbeddingsConnection`, `TAiAudioPushStream`
- New demos: DocumentManager, ChatWebList

### v3.2 (January 2026)
- Native ChatTools framework (`IAiPdfTool`, `IAiVisionTool`, `IAiSpeechTool`, etc.)
- Unified deterministic tool orchestration and capability bridges

### v3.1 (November 2025)
- GPT-5.1, Gemini 3.0, Claude 4.5 initial support
- FMX multimodal UI components
- RAG Rerank + Graph RAG engine
- MCP Server framework (SSE, StdIO, HTTP)

### v3.0 (October 2025)
- Major architecture redesign
- Visual FMX chat components
- Graph-based vector database
- Full Delphi 10.4â€“13 compatibility

### v2.5 (August 2025)
- MCP Client/Server (Model Context Protocol)
- Agent graph orchestration
- Linux/POSIX full support

---

## ðŸ’¬ Community & Support

- **Website:** [https://makerai.cimamaker.com](https://makerai.cimamaker.com)
- **Telegram (Spanish):** [https://t.me/MakerAi_Suite_Delphi](https://t.me/MakerAi_Suite_Delphi)
- **Telegram (English):** [https://t.me/MakerAi_Delphi_Suite_English](https://t.me/MakerAi_Delphi_Suite_English)
- **Email:** gustavoeenriquez@gmail.com
- **GitHub Issues:** [https://github.com/gustavoeenriquez/MakerAi/issues](https://github.com/gustavoeenriquez/MakerAi/issues)

---

## ðŸ“œ License

MIT License â€” see `LICENSE.txt` for details.

Copyright Â© 2024â€“2026 Gustavo EnrÃ­quez â€” CimaMaker
