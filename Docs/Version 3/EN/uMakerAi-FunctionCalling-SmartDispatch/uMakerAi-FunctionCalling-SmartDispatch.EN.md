# Function Calling vs cmSmartDispatch — Selection Guide

**MakerAI v3.3 — Technical documentation**
Last updated: April 2026

---

## Index

1. [Introduction](#1-introduction)
2. [Native Function Calling](#2-native-function-calling)
3. [cmSmartDispatch](#3-cmsmartdispatch)
4. [Comparison table](#4-comparison-table)
5. [Decision tree](#5-decision-tree)
6. [Model compatibility](#6-model-compatibility)
7. [Recommended scenarios](#7-recommended-scenarios)
8. [Migration between modes](#8-migration-between-modes)

---

## 1. Introduction

MakerAI offers two mechanisms for an LLM to invoke external tools:

1. **Native function calling** — the model receives tool definitions in JSON and responds with structured `tool_use` blocks. It requires explicit support from the model and the provider.

2. **cmSmartDispatch** — the framework teaches the model to choose tools using plain-text tags (`[IMAGEGEN]`, `[WEBSEARCH]`, etc.). It works with any model capable of following instructions.

Both mechanisms produce the same final result (the correct tool is executed, and the result reaches the user), but they differ in requirements, capabilities, and optimal use cases.

---

## 2. Native Function Calling

### How it works

The framework sends the available tool definitions to the model along with the user's message. The model responds with a JSON block indicating which tool to invoke and with which parameters. The framework parses that block, executes the tool, and sends the result back to the model so it can generate the final response.

```pascal
// Enable native function calling
Conn.DriverName := 'OpenAI';
Conn.Params.Values['Model']       := 'gpt-4.1';
Conn.Params.Values['Tool_Active'] := 'True';  // enabled by default in most models
```

### Capabilities

- **Multiple tools per turn**: the model can call 2 or more tools in the same message before responding to the user.
- **Rich parameters**: each tool can receive structured parameters with JSON schema validation.
- **Tool iteration**: the `tool_use → result → tool_use → result → response` loop is managed automatically.
- **Asynchronous mode**: compatible with `Asynchronous = True` and streaming.

### Requirements

- The model must support function calling (see section 6).
- `Tool_Active = True` in the connection parameters (it is the default in most capable models).
- For `ChatTools` tools (Image, WebSearch, Speech, Video): no additional configuration is required; they are enabled via the `ModelCaps`/`SessionCaps` system.
- For custom tools (`TAiFunctions`): define the JSON schema with `TAiToolsFunction`.

---

## 3. cmSmartDispatch

### How it works

The framework performs **two LLM calls** per message. The first (Step 1) uses an isolated context with a specialized dispatch prompt so the model classifies the request into a tag. The second (Step 2) executes the tool or returns the direct response.

```pascal
// Enable SmartDispatch
Conn.DriverName := 'Ollama';
Conn.Params.Values['Model']        := 'gemma3:4b';
Conn.Params.Values['Asynchronous'] := 'False';  // required
Conn.ChatMode := cmSmartDispatch;
```

### Capabilities

- **No model requirements**: works with any LLM that follows basic instructions.
- **ChatTools tools**: `ImageTool`, `WebSearchTool`, `SpeechTool`, `VideoTool`.
- **Simulated tools**: facilitates development and testing with mock implementations.
- **Local model + cloud tools**: the classifier can be a low-cost local model while the tools use premium APIs.

### Limitations

- One tool per turn.
- Does not support `Asynchronous = True`.
- Additional latency of ~0.5–2 s due to the second LLM call.
- Custom tools via `TAiFunctions` are not available (only the 4 `ChatTools` tools).

---

## 4. Comparison table

| Criterion | Native Function Calling | cmSmartDispatch |
|----------|------------------------|-----------------|
| **Required model support** | Yes — JSON tool_use | No — any model |
| **Tools per turn** | Multiple (unlimited) | One |
| **Available tools** | ChatTools + custom TAiFunctions | Only ChatTools (Image, Video, Speech, Web) |
| **Tool parameters** | Schema-based JSON, validated | Plain text (rewritten prompt/query) |
| **Asynchronous / streaming mode** | Yes | No |
| **Additional latency** | Minimal | +1 LLM call (~0.5–2 s) |
| **History contamination** | No | No |
| **Routing accuracy** | Very high (JSON structure) | High with models ≥4b |
| **Inference cost** | 1 call per turn | 2 calls per turn |
| **Small local models** | No (≥7b recommended with tools) | Yes (≥3b recommended) |
| **Development/prototyping** | Requires a real API | Mock tools facilitate testing |
| **Multi-step production** | Optimal | Not recommended |

---

## 5. Decision tree

```
Does the model support function calling?
│
├─ NO (small local model, Phi-3, Gemma 3:4b, etc.)
│   └─ Use cmSmartDispatch
│
└─ YES
    │
    ├─ Do you need custom tools (TAiFunctions)?
    │   └─ YES → Native function calling (cmConversation)
    │
    ├─ Do you need multiple tools in the same turn?
    │   └─ YES → Native function calling (cmConversation)
    │
    ├─ Do you need streaming / asynchronous mode?
    │   └─ YES → Native function calling (cmConversation)
    │
    ├─ Is the model local and do you want to use external cloud tools?
    │   └─ cmSmartDispatch (classifies locally, executes in cloud)
    │
    └─ Any other case → cmConversation (recommended default)
```

---

## 6. Model compatibility

### Models with native function calling (use cmConversation)

| Provider | Models | Notes |
|----------|---------|-------|
| OpenAI | `gpt-4.1`, `gpt-4o`, `o3`, `o4-mini` | Tool_Active=True (default) |
| Claude | `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5` | Tool_Active=True (default) |
| Gemini | `gemini-2.5-flash`, `gemini-2.5-pro`, `gemini-3-pro-preview` | Tool_Active=True (default) |
| Groq | `llama-4-scout`, `llama-4-maverick`, `qwen3-32b` | Tool_Active=True (default) |
| Ollama | `qwen2.5:7b`, `qwen3:8b`, `llama3.3:70b` | Tool_Active=True by model |
| Ollama | `gemma4:e2b`, `gemma4:e4b` | Tool_Active=True — also support SmartDispatch |

### Models without function calling (use cmSmartDispatch)

| Provider | Models | Notes |
|----------|---------|-------|
| Ollama | `gemma3:1b/4b/12b/27b` | No function calling via Ollama |
| Ollama | `llama3.2:3b` | Limited/unreliable function calling |
| Ollama | `phi3:mini`, `phi3:medium` | No function calling |
| Ollama | `mistral:7b` | No function calling in Ollama |
| LM Studio | Any small GGUF | Depends on the loaded model |

> **Gemma 4 note:** Gemma 4 models (`gemma4:e2b`, `gemma4:e4b`) do support native function calling via Ollama (`Tool_Active=True`). They can be used with both modes; native mode is preferable for production.

---

## 7. Recommended scenarios

### Scenario A: Production application with OpenAI/Claude

```pascal
// Native function calling — optimal for production
Conn.DriverName := 'OpenAI';
Conn.Params.Values['Model']       := 'gpt-4.1';
// Tool_Active=True is already the default for gpt-4.1
Conn.ChatMode := cmConversation;  // default
```

**Why:** Maximum accuracy, support for multiple tools, streaming available.

---

### Scenario B: Offline prototype with a local model

```pascal
// SmartDispatch — local model, no API key required
Conn.DriverName := 'Ollama';
Conn.Params.Values['Model']        := 'gemma3:4b';
Conn.Params.Values['Asynchronous'] := 'False';
Conn.ChatMode := cmSmartDispatch;

// Mock tools for rapid development
Conn.ChatTools.ImageTool     := TMockImageTool.Create(nil);
Conn.ChatTools.WebSearchTool := TMockWebSearchTool.Create(nil);
```

**Why:** Development without API cost, testing the complete flow with mocks.

---

### Scenario C: Local model + premium tools

```pascal
// SmartDispatch: free classification + high-quality tools
Conn.DriverName := 'Ollama';
Conn.Params.Values['Model']        := 'llama3.2:3b';
Conn.Params.Values['Asynchronous'] := 'False';
Conn.ChatMode := cmSmartDispatch;

// Real premium-quality tools
ImageTool        := TAiDalleImageTool.Create(nil);
ImageTool.ApiKey := '@OPENAI_API_KEY';
ImageTool.Model  := 'gpt-image-1';
Conn.ChatTools.ImageTool := ImageTool;

SearchTool        := TAiBraveSearchTool.Create(nil);
SearchTool.ApiKey := '@BRAVE_API_KEY';
Conn.ChatTools.WebSearchTool := SearchTool;
```

**Why:** Minimum inference cost (local model for classification), premium tools only when needed.

---

### Scenario D: Complex multi-tool application

```pascal
// Native function calling — supports multiple tools per turn
Conn.DriverName := 'Claude';
Conn.Params.Values['Model'] := 'claude-sonnet-4-6';
Conn.ChatMode := cmConversation;

// Multiple ChatTools tools
Conn.ChatTools.WebSearchTool := MiWebSearch;
Conn.ChatTools.ImageTool     := MiImageGen;

// Additional custom tools via TAiFunctions
Conn.AiChat.Functions.AddFunction('GetWeather', 'Gets the current weather', ...);
Conn.AiChat.Functions.AddFunction('SendEmail', 'Sends an email', ...);
```

**Why:** The model can call `GetWeather` and `WebSearch` in the same turn before responding; SmartDispatch cannot do this.

---

## 8. Migration between modes

### From cmSmartDispatch to native function calling

When the model allows it (switching to a provider with support), migration is trivial — just change two lines:

```pascal
// Before (SmartDispatch with a model without function calling)
Conn.DriverName := 'Ollama';
Conn.Params.Values['Model']        := 'gemma3:4b';
Conn.Params.Values['Asynchronous'] := 'False';
Conn.ChatMode := cmSmartDispatch;

// After (native function calling)
Conn.DriverName := 'OpenAI';
Conn.Params.Values['Model'] := 'gpt-4.1';
// Remove the Asynchronous=False line if it is not needed
Conn.ChatMode := cmConversation;  // or simply omit it; it is the default

// ChatTools tools remain the same — they are compatible with both modes
```

`ChatTools` tools (`ImageTool`, `WebSearchTool`, etc.) are fully compatible with both modes. They do not require changes when migrating.

### From native function calling to cmSmartDispatch

```pascal
// Before (native function calling)
Conn.DriverName := 'OpenAI';
Conn.ChatMode   := cmConversation;

// After (SmartDispatch for testing with a local model)
Conn.DriverName := 'Ollama';
Conn.Params.Values['Model']        := 'gemma3:4b';
Conn.Params.Values['Asynchronous'] := 'False';   // required
Conn.ChatMode := cmSmartDispatch;

// Note: custom TAiFunctions will NOT be transferred — only ChatTools works
```

> **Restriction:** Custom tools defined with `TAiFunctions` are not available in `cmSmartDispatch`. If the application uses them, it is not possible to migrate directly to SmartDispatch without removing that functionality.

---

> See [uMakerAi-ChatTools-SmartDispatch.md](uMakerAi-ChatTools-SmartDispatch.md) for the complete `cmSmartDispatch` documentation.
> See [uMakerAi.ToolFuncions.docx](uMakerAi.ToolFuncions.docx) for the documentation on `TAiFunctions` and native function calling.