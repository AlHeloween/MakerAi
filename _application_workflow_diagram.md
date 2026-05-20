# Application Workflow Diagram — MakerAI v3.3

> **Purpose:** Catalog of all modules and key functions with abstract logic, path, semantic domain, and I/O parameters.
> **Coverage:** Estimated ~80% of the core codebase. Key public APIs and abstract classes are documented.
> **Last updated:** 2026-05-20

---

## Architecture Layers

```
┌─────────────────────────────────────┐
│  Applications / Demos                │
└───────┬──────┬──────────┬───────────┘
        │      │          │
┌───────v──┐ ┌─v──────┐ ┌─v───────────┐
│ ChatUI    │ │ Agents  │ │ Design (Dsg) │
│ FMX       │ │ Graph   │ │ IDE Editors  │
└─────┬─────┘ └───┬────┘ └──────┬──────┘
      │           │              │
┌─────v───────────v──────────────v──────┐
│  Chat Drivers (12 providers)          │
│  TAiChatConnection (universal)         │
└───────────────────┬───────────────────┘
                    │
┌───────────────────v───────────────────┐
│  Core: TAiChat (abstract base)        │
│  ModelCaps, SessionCaps, RunNew()     │
└─────┬─────────┬──────────┬────────────┘
      │         │          │
┌─────v──┐ ┌───v────┐ ┌───v────────┐
│ Tools   │ │ RAG     │ │ MCP         │
│ Funcs   │ │ Vect/Gr │ │ Client/Srv  │
└─────────┘ └─────────┘ └─────────────┘
```

---

## Module Catalog

### Core/ — Foundation Layer

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiChat.Run()` | `Source/Core/uMakerAi.Chat.pas` | Chat execution | Prompt string, media files | Chat response via events |
| `TAiChat.RunNew()` | `Source/Core/uMakerAi.Chat.pas` | v3.3 unified execution | Prompt, capabilities | Response with bridge orchestration |
| `TAiChat.EnsureNewSystemConfig()` | `Source/Core/uMakerAi.Chat.pas` | Capability system setup | ModelCaps, SessionCaps | Gap detection → bridge activation |
| `TAiChat.GetMessages()` | `Source/Core/uMakerAi.Chat.pas` | Message formatting | Chat messages list | Provider-formatted message array |
| `TAiMediaFile.LoadFromFile()` | `Source/Core/uMakerAi.Core.pas` | File abstraction | File path | TAiMediaFile with content/base64 |
| `TAiChatMessage` | `Source/Core/uMakerAi.Chat.Messages.pas` | Message container | Role, text, files | Structured chat message |
| `TAiChatMessages` | `Source/Core/uMakerAi.Chat.Messages.pas` | Message collection | Messages | Conversation history |
| `TAiCapabilities` | `Source/Core/uMakerAi.Core.pas` | Capability sets | cap_ values | Set operations for gap detection |
| `TAiPrompts` | `Source/Core/uMakerAi.Prompts.pas` | Prompt templates | Template text | Rendered prompt with placeholder substitution |

### Chat/ — LLM Provider Drivers

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiChatConnection` | `Source/Chat/uMakerAi.Chat.AiConnection.pas` | Universal connector | DriverName, Model, ApiKey | Unified chat interface |
| `TAiOpenChat` | `Source/Chat/uMakerAi.Chat.OpenAi.pas` | OpenAI driver | GPT model, messages | API response with streaming |
| `TAiClaudeChat` | `Source/Chat/uMakerAi.Chat.Claude.pas` | Anthropic driver | Claude model, messages | API response with thinking |
| `TAiGeminiChat` | `Source/Chat/uMakerAi.Chat.Gemini.pas` | Google driver | Gemini model, media | Multimodal response |
| `TAiOllamaChat` | `Source/Chat/uMakerAi.Chat.Ollama.pas` | Local models | Ollama endpoint | Local LLM response |
| `TAiChatFactory` | `Source/Chat/uMakerAi.Chat.Initializations.pas` | Driver registry | Provider name, params | Registered driver instance |

### Agents/ — Autonomous Agent Framework

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAIAgentManager.Run()` | `Source/Agents/uMakerAi.Agents.pas` | Graph executor | Graph nodes, input | Execution via thread pool |
| `TAIAgentsNode.OnExecute` | `Source/Agents/uMakerAi.Agents.pas` | Node callback | Blackboard state | Updated state + next nodes |
| `TAIAgentsLink.Evaluate()` | `Source/Agents/uMakerAi.Agents.pas` | Edge evaluation | Node outputs | Next node selection (fanout/conditional) |
| `TAIBlackboard` | `Source/Agents/uMakerAi.Agents.pas` | Shared state | Key-value pairs | Thread-safe state access |
| `TAiCheckpointer` | `Source/Agents/uMakerAi.Agents.Checkpoint.pas` | Execution persistence | Graph state | JSON snapshot |
| `TAiFluentGraphBuilder` | `Source/Agents/uMakerAi.Agents.GraphBuilder.pas` | Graph construction | Builder commands | Agent graph |

### RAG/ — Retrieval-Augmented Generation

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiRAGVector.Search()` | `Source/RAG/uMakerAi.RAG.Vectors.pas` | Vector search | Query embedding | Ranked results with scores |
| `TAiRAGVector.ExecuteVGQL()` | `Source/RAG/uMakerAi.RAG.Vectors.pas` | VQL execution | VGQL query string | Search results |
| `TAiRagGraph.SearchNodes()` | `Source/RAG/uMakerAi.RAG.Graph.Core.pas` | Graph search | Query, filter | Nodes with metadata |
| `TAiRagGraph.ExecuteGQL()` | `Source/RAG/uMakerAi.RAG.Graph.Core.pas` | GQL execution | GQL query string | Graph traversal results |
| `THNSWIndex` | `Source/RAG/uMakerAi.RAG.Vectors.Index.pas` | HNSW index | Embedding vectors | Fast approximate search |
| `TAiEmbeddingNode` | `Source/RAG/uMakerAi.RAG.Vectors.Index.pas` | Embedding container | Vector, text, metadata | Searchable node |

### MCP/ — Model Context Protocol

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiMCPServer.Start()` | `Source/MCPServer/uMakerAi.MCPServer.Core.pas` | MCP server | Protocol, port | Running MCP service |
| `TAiMCPServerStdio` | `Source/MCPServer/UMakerAi.MCPServer.Stdio.pas` | StdIO transport | stdio streams | JSON-RPC messages |
| `TAiMCPServerSSE` | `Source/MCPServer/UMakerAi.MCPServer.SSE.pas` | SSE transport | HTTP context | Server-sent events |
| `TMCPClientItem.Execute()` | `Source/MCPClient/uMakerAi.MCPClient.Core.pas` | MCP client | Tool name, params | Tool execution result |

### Tools/ — Function Calling System

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiFunctions.Execute()` | `Source/Tools/uMakerAi.Tools.Functions.pas` | Function dispatcher | Function name, JSON args | Tool result |
| `TAiWhisper.Transcribe()` | `Source/Tools/uMakerAi.Whisper.pas` | STT | Audio file | Transcription text |
| `TAiDalle.Generate()` | `Source/Tools/uMakerAi.OpenAi.Dalle.pas` | Image generation | Prompt, size options | Generated image |
| `TAiShell.Execute()` | `Source/Tools/uMakerAi.Tools.Shell.pas` | Shell commands | Command string | Shell output |
| `TAiComputerUseTool` | `Source/Tools/uMakerAi.Tools.ComputerUse.pas` | UI automation | Action, target | Screen interaction result |

### ChatUI/ — FMX Visual Components

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TChatList` | `Source/ChatUI/uMakerAi.UI.ChatList.pas` | Chat container | Messages | Rendered chat UI |
| `TChatInput` | `Source/ChatUI/uMakerAi.UI.ChatInput.pas` | Input bar | User input (text/voice) | Message + media files |
| `TChatBubble` | `Source/ChatUI/uMakerAi.UI.ChatBubble.pas` | Message display | Message content | Formatted chat bubble |

### Embeddings/ — Embedding Providers

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiEmbeddingsCore.GetEmbedding()` | `Source/Embeddings/uMakerAi.Embeddings.core.pas` | Abstract base | Text | Embedding vector |
| `TAiOpenAiEmbeddings` | `Source/Embeddings/uMakerAi.Embeddings.OpenAi.pas` | OpenAI embeddings | Text | OpenAI embedding vector |
| `TAiEmbeddingConnection` | `Source/Embeddings/uMakerAi.Embeddings.Connection.pas` | Provider connector | Provider name | Configured embedder |

### Utils/ — Utilities

| Function/Class | Path | Domain | Input | Output |
|---------------|------|--------|-------|--------|
| `TAiVoiceMonitor` | `Source/Utils/uMakerAi.Utils.VoiceMonitor.pas` | Voice detection | Audio device | Voice activity events |
| `TAiScreenCapture` | `Source/Utils/uMakerAi.Utils.ScreenCapture.pas` | Screen capture | Area rectangle | Captured bitmap |
| `TPythonBridge` | `Source/Utils/uMakerAi.Utils.Python.pas` | Python interop | Python script | Script output |

---

## Chat State Machine

```
acsIdle → acsConnecting → [acsReasoning] → acsWriting
                                                  │
                        ┌─────────────────────────┤
                        ▼                         ▼
                 acsToolCalling              acsFinished
                        │                    acsError
                        ▼                    acsAborted
                 acsToolExecuting
                        │
                        └──→ loop back to acsWriting
```

---

## Agent Graph Execution Model

```
TAIAgentManager.FThreadPool (TThreadPool)
    │
    ├── TAIAgentsNode (each)
    │   ├── OnExecute → pool thread
    │   ├── Inputs[] → from upstream
    │   ├── TAIBlackboard → shared state (TCriticalSection)
    │   └── ToolRegistry → tools
    │
    ├── TAIAgentsLink (edges)
    │   ├── Mode: lmFanout | lmConditional | lmManual
    │   └── JoinMode: jmAny | jmAll (TCriticalSection)
    │
    └── TAiCheckpointer (optional)
        ├── Suspend → JSON snapshot
        └── Resume → restore + continue
```

---

## Coverage Estimate

| Module | Functions/Classes Documented | Coverage |
|--------|------------------------------|----------|
| Core | 8 / ~20 | ~40% |
| Chat | 6 / ~50 | ~12% |
| Agents | 6 / ~30 | ~20% |
| RAG | 6 / ~25 | ~24% |
| MCP | 4 / ~15 | ~27% |
| Tools | 5 / ~30 | ~17% |
| ChatUI | 3 / ~15 | ~20% |
| Embeddings | 3 / ~25 | ~12% |
| Utils | 3 / ~10 | ~30% |

**Total codebase coverage:** ~20% of public API surface documented in this diagram.
