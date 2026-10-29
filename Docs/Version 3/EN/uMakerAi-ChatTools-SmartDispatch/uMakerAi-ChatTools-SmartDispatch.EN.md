# cmSmartDispatch — Smart tool dispatch for small models

**MakerAI v3.3 — Technical documentation**
Last updated: April 2026

---

## Index

1. [Purpose](#1-purpose)
2. [The problem: models without function calling](#2-the-problem-models-without-function-calling)
3. [How it works: two-step flow](#3-how-it-works-two-step-flow)
4. [Available tags](#4-available-tags)
5. [Basic configuration](#5-basic-configuration)
6. [Supported tools](#6-supported-tools)
7. [Complete example with simulated tools](#7-complete-example-with-simulated-tools)
8. [Example with real tools](#8-example-with-real-tools)
9. [Internal dispatch prompt](#9-internal-dispatch-prompt)
10. [Limitations and considerations](#10-limitations-and-considerations)
11. [Comparison with other modes](#11-comparison-with-other-modes)
12. [Source file reference](#12-source-file-reference)

---

## 1. Purpose

`cmSmartDispatch` is a MakerAI chat mode that allows using tools (`ImageTool`, `WebSearchTool`, `SpeechTool`, `VideoTool`) with **any LLM model**, including those without native function calling support.

The idea is to solve a specific problem: small local models such as Gemma 3:4b, LLaMA 3.2:3b, or Phi-3-mini process natural language perfectly, but they do not understand the JSON function-calling protocol used by the API. With `cmSmartDispatch`, the framework teaches them to choose tools using plain-text tags (`[IMAGEGEN]`, `[WEBSEARCH]`, etc.) — a protocol that any model can follow.

---

## 2. The problem: models without function calling

### Models with native function calling

A model such as `gpt-4.1` or `qwen2.5:7b` can receive tool definitions in JSON format, evaluate which one to apply, and return a structured response that the framework parses automatically.

```
User: "generate an image of a cat"
  → The model returns: { "tool_use": "ImageTool", "input": { "prompt": "a cat" } }
  → The framework executes ImageTool.ExecuteImageGeneration("a cat")
```

### Models without function calling

A model such as `gemma3:4b` or `phi3:mini` receives the same request but simply responds in natural language:

```
User: "generate an image of a cat"
  → The model returns: "Sorry, I can't generate images directly."
```

There is no way to tell it to use a tool through the standard JSON protocol.

### The solution: tag protocol

`cmSmartDispatch` solves this with a **preliminary dispatch step**: it asks the model to classify the request into a plain-text tag instead of responding directly. The model learns to respond like this:

```
User: "generate an image of a cat"
  → Pass 1: [IMAGEGEN] a cat
  → Pass 2: the framework executes ImageTool.ExecuteImageGeneration("a cat")
```

---

## 3. How it works: two-step flow

```text
User sends message
       │
       ▼
┌─────────────────────────────────────────────┐
│ STEP 1 — Classification (silent)            │
│                                             │
│  The LLM receives:                          │
│  • system: dispatch prompt                  │
│  • user:   original user message            │
│                                             │
│  The LLM responds:                          │
│  • "[TAG] rewritten content"                │
│                                             │
│  Note: this step is NOT added to history    │
│  and uses an isolated context (no history). │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
          Parse [TAG] and content
                   │
          ┌────────┴────────┐
          │                 │
         CHAT          TOOL (IMAGEGEN,
          │            WEBSEARCH, etc.)
          │                 │
          ▼                 ▼
  Use the response   Execute the corresponding
  from Step 1         tool
  directly
          │                 │
          └────────┬────────┘
                   │
                   ▼
        Result returned to the user
        and added to history
```

### Context isolation details

Step 1 runs with a completely isolated context: it contains only the dispatch prompt (as a `system` message) and the current user message. Conversation history is deliberately not included to prevent previous tool responses (`[SIMULATED IMAGE] ...`) from confusing the classification of new requests.

---

## 4. Available tags

The tags available in Step 1 depend on which tools are assigned to the connection:

| Tag | Generated when | Tool executed |
|----------|------------------|-----------------------|
| `[IMAGEGEN]` | `ChatTools.ImageTool` is assigned | `ImageTool.ExecuteImageGeneration()` |
| `[VIDEOGEN]` | `ChatTools.VideoTool` is assigned | `VideoTool.ExecuteVideoGeneration()` |
| `[TTS]` | `ChatTools.SpeechTool` is assigned | `SpeechTool.ExecuteSpeechGeneration()` |
| `[WEBSEARCH]` | `ChatTools.WebSearchTool` is assigned | `WebSearchTool.ExecuteSearch()` |
| `[CHAT]` | Always available (fallback) | Direct LLM response (Step 1) |

The dispatch prompt is built dynamically: it only includes the tags for tools that are actually assigned.

---

## 5. Basic configuration

### Requirements

- `ChatMode := cmSmartDispatch` on the connection
- `Asynchronous = False` in the parameters — asynchronous mode is not supported
- At least one tool assigned in `ChatTools` (if there are no tools, all requests will go to `[CHAT]`)
- Tools must be assigned **before** setting `DriverName`

### Minimal configuration

```pascal
Conn := TAiChatConnection.Create(nil);

// 1. Assign tools BEFORE the driver
Conn.ChatTools.ImageTool     := MiImageTool;
Conn.ChatTools.WebSearchTool := MiWebSearchTool;

// 2. Configure driver
Conn.DriverName := 'Ollama';
Conn.Params.Values['URL']          := 'http://localhost:11434/';
Conn.Params.Values['Model']        := 'gemma3:4b';
Conn.Params.Values['Asynchronous'] := 'False';   // REQUIRED
Conn.Params.Values['Max_Tokens']   := '512';

// 3. Enable mode
Conn.ChatMode      := cmSmartDispatch;
Conn.SystemPrompt.Text := 'You are a helpful assistant. Answer in English.';
```

> **Note:** `SystemPrompt` is used in Step 2 (final response), not in the Step 1 dispatch. Step 1 always uses the framework's internal dispatch prompt.

---

## 6. Supported tools

`cmSmartDispatch` is compatible with the same `ChatTools` tools used by `cmConversation` mode. To use them with SmartDispatch, simply implement the corresponding base class:

| Base class | Generated tag | Method to override |
|------------|--------------|----------------------|
| `TAiImageToolBase` | `[IMAGEGEN]` | `ExecuteImageGeneration(APrompt, ResMsg, AskMsg)` |
| `TAiVideoToolBase` | `[VIDEOGEN]` | `ExecuteVideoGeneration(APrompt, ResMsg, AskMsg)` |
| `TAiSpeechToolBase` | `[TTS]` | `ExecuteSpeechGeneration(AText, ResMsg, AskMsg)` |
| `TAiWebSearchToolBase` | `[WEBSEARCH]` | `ExecuteSearch(AQuery, ResMsg, AskMsg)` |

### Implementation pattern

```pascal
type
  TMiImageTool = class(TAiImageToolBase)
  protected
    procedure ExecuteImageGeneration(const APrompt: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

procedure TMiImageTool.ExecuteImageGeneration(const APrompt: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  // APrompt: description already rewritten by the dispatcher
  // ResMsg:  fill in with the result
  ResMsg.Prompt := GenerarImagen(APrompt);   // actual API call
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;
```

### Combination with real framework tools

MakerAI's built-in tools (`TAiDalle`, `TAiGeminiImageTool`, `TAiBraveSearch`, etc.) implement the same base classes and work without changes in SmartDispatch mode:

```pascal
// Real ImageTool with DALL-E
ImageTool        := TAiDalleImageTool.Create(nil);
ImageTool.ApiKey := '@OPENAI_API_KEY';
Conn.ChatTools.ImageTool := ImageTool;

// Real WebSearchTool with Brave Search
SearchTool        := TAiBraveSearchTool.Create(nil);
SearchTool.ApiKey := '@BRAVE_API_KEY';
Conn.ChatTools.WebSearchTool := SearchTool;

// The model can be local (Ollama) and the tools external APIs
Conn.DriverName := 'Ollama';
Conn.ChatMode   := cmSmartDispatch;
```

---

## 7. Complete example with simulated tools

The demo `Demos/Console/Demos02-ChatTools/08-SmartDispatch/` uses simulated (mock) tools to validate routing without real API calls.

```pascal
program SmartDispatch;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.Tools,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama;

const
  DRIVER     = 'Ollama';
  MODEL      = 'gemma3:4b';
  OLLAMA_URL = 'http://localhost:11434/';

// --- Simulated tools ---

type
  TMockImageTool = class(TAiImageToolBase)
  protected
    procedure ExecuteImageGeneration(const APrompt: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

  TMockWebSearchTool = class(TAiWebSearchToolBase)
  protected
    procedure ExecuteSearch(const AQuery: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

procedure TMockImageTool.ExecuteImageGeneration(const APrompt: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  Writeln('  >> [ImageTool] prompt: "', APrompt, '"');
  ResMsg.Prompt := '[SIMULATED IMAGE] ' + APrompt;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure TMockWebSearchTool.ExecuteSearch(const AQuery: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  Writeln('  >> [WebSearchTool] query: "', AQuery, '"');
  ResMsg.Prompt := '[SIMULATED WEB SEARCH] ' + AQuery;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

// --- Demo ---

procedure RunDemo;
var
  Conn      : TAiChatConnection;
  ImageTool : TMockImageTool;
  SearchTool: TMockWebSearchTool;
  Resp      : String;
begin
  ImageTool  := TMockImageTool.Create(nil);
  SearchTool := TMockWebSearchTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.ChatTools.ImageTool     := ImageTool;
    Conn.ChatTools.WebSearchTool := SearchTool;

    Conn.DriverName := DRIVER;
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';

    Conn.ChatMode          := cmSmartDispatch;
    Conn.SystemPrompt.Text := 'You are a helpful assistant. Answer in English.';

    // CHAT — direct question
    Resp := Conn.AddMessageAndRun('What is the capital of France?', 'user', []);
    Writeln('CHAT: ', Resp);

    // IMAGEGEN — image request
    Resp := Conn.AddMessageAndRun('Generate an image of a cat with a hat', 'user', []);
    Writeln('IMAGEGEN: ', Resp);

    // WEBSEARCH — search request
    Resp := Conn.AddMessageAndRun('Search for the latest AI news in 2025', 'user', []);
    Writeln('WEBSEARCH: ', Resp);

  finally
    Conn.Free;
    ImageTool.Free;
    SearchTool.Free;
  end;
end;

begin
  RunDemo;
  Readln;
end.
```

### Expected output

```
CHAT: Paris is the capital of France.
  >> [ImageTool] prompt: "a cat wearing a hat"
IMAGEGEN: [SIMULATED IMAGE] a cat wearing a hat
  >> [WebSearchTool] query: "latest AI news 2025"
WEBSEARCH: [SIMULATED WEB SEARCH] latest AI news 2025
```

---

## 8. Example with real tools

Combination of a local Ollama model with real tools from external APIs:

```pascal
uses
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama,
  uMakerAi.OpenAi.Dalle,        // TAiDalleImageTool
  uMakerAi.Gemini.WebSearch;    // TAiGeminiWebSearchTool (or any WebSearch)

procedure ConfigurarSmartDispatch(Conn: TAiChatConnection);
var
  ImageTool : TAiDalleImageTool;
  SearchTool: TAiGeminiWebSearchTool;
begin
  // Real tools
  ImageTool        := TAiDalleImageTool.Create(nil);
  ImageTool.ApiKey := '@OPENAI_API_KEY';
  ImageTool.Model  := 'dall-e-3';

  SearchTool        := TAiGeminiWebSearchTool.Create(nil);
  SearchTool.ApiKey := '@GEMINI_API_KEY';

  // Assign BEFORE the driver
  Conn.ChatTools.ImageTool     := ImageTool;
  Conn.ChatTools.WebSearchTool := SearchTool;

  // Local model without function calling
  Conn.DriverName := 'Ollama';
  Conn.Params.Values['URL']          := 'http://localhost:11434/';
  Conn.Params.Values['Model']        := 'llama3.2:3b';
  Conn.Params.Values['Asynchronous'] := 'False';

  Conn.ChatMode := cmSmartDispatch;
end;
```

In this pattern, reasoning and classification are done by the local model (with no API cost), while image generation or web search is done by external services.

---

## 9. Internal dispatch prompt

The framework automatically builds the dispatch prompt in `TAiChat.BuildSmartDispatchPrompt`. Its structure is:

```
You are a task dispatcher. Your ONLY job is to classify the user request
and output exactly one line.
Output format: [TAG] rewritten_request

Available tags:
  [IMAGEGEN] <image description> — use when user asks to create, draw,
    or generate an image
  [WEBSEARCH] <optimized search query> — use when user asks for recent
    news, current info, or web search
  [CHAT] <your answer> — use for general conversation, questions,
    calculations, or anything else

STRICT RULES:
  - Output ONLY the single line [TAG] content. No other text.
  - Do NOT say you cannot generate images — just use the appropriate tag.
  - Always pick exactly ONE tag. [CHAT] is the fallback.

Examples:
  User: draw a red cat => [IMAGEGEN] a red cat
  User: latest AI news => [WEBSEARCH] latest artificial intelligence news 2025
  User: what is 2+2 => [CHAT] 4
```

> **Language note:** The dispatch prompt is in English by design. Multilingual models classify more accurately when the tag protocol is in English, regardless of the user's language.

The `SystemPrompt` that the developer sets on the connection **does not interfere** with dispatch — it is only applied in Step 2 (response or tool execution).

---

## 10. Limitations and considerations

### Asynchronous mode not supported

`cmSmartDispatch` requires `Asynchronous = False`. Step 1 is synchronous by design: it needs the classifier's response before it can execute the tool in Step 2. If `Asynchronous = True`, the framework raises an exception in `RunNew`.

```pascal
// CORRECT
Conn.Params.Values['Asynchronous'] := 'False';

// INCORRECT — throws an exception
Conn.Params.Values['Asynchronous'] := 'True';
Conn.ChatMode := cmSmartDispatch;
```

### Models that ignore the protocol

Some very small models (1b-2b parameters) may produce malformed output that does not include any tag. In that case, `ParseSmartDispatchResponse` falls back to the `[CHAT]` tag and returns the model's literal response.

A model of at least 3b-4b parameters is recommended for reliable results. Tested models:

| Model | Results |
|--------|-----------|
| `gemma3:4b` (Ollama) | Excellent classification |
| `gemma4:e4b` (Ollama) | Excellent — also supports native function calling |
| `llama3.2:3b` (Ollama) | Good classification in clear cases |
| `phi3:mini` (Ollama) | Variable — depends on the prompt |
| `gemma3:1b` (Ollama) | Not recommended — frequently ignores the protocol |

### Additional latency

Step 1 is a full LLM call (although with a minimal context of 2 messages and a very short response of ~10-30 tokens). Typical overhead is 0.5-2 seconds depending on the model and hardware. For real-time use cases, consider `cmConversation` with a model that supports native function calling.

### Step 1 without an LLM: `ChatTools.DispatchClassifier`

Since Sep 27/2026, Step 1 can be delegated to a dedicated classifier, which is faster and cheaper than an LLM call. It is assigned in `ChatTools.DispatchClassifier` (a `TAiDispatchClassifierBase`); the included implementation uses the Jev model from TypeSafe AI:

```pascal
uses uMakerAi.Jev.SmartDispatch;

JevDispatch := TAiJevDispatchClassifier.Create(Self);   // ApiKey = '@TYPESAFE_API_KEY'
AiChat.ChatTools.DispatchClassifier := JevDispatch;
```

- Only the tags whose tool is assigned are offered to it; if only CHAT remains, it is not queried.
- **Tool tag:** the tool receives the user's **original** prompt (the classifier does not rewrite the request as the LLM does in Step 1).
- **CHAT:** it is answered with a normal call, **with the full conversation history** (the LLM Step 1 answers in an isolated two-message context).
- If the classifier is not confident (`MinConfidence`, 0.6 by default) or fails, the chat performs the LLM Step 1 as usual.

Calibration (jev-1.13.0): 15/15 requests in Spanish and English, including "describe what a red cat would look like" → CHAT. Demo: `Demos/085-JevDispatchGuard`.

### Conversation history

History is maintained correctly. Each exchange adds exactly one `user/assistant` pair to the history. The Step 1 dispatch is transparent — it does not appear in the visible history.

### No support for chained tools

SmartDispatch dispatches exactly **one tool per message**. There is no support for tool chaining (calling WebSearch and then ImageGen in the same turn). For multi-tool flows, use `cmConversation` mode with a model that supports native function calling and multiple tool calls.

---

## 11. Comparison with other modes

| Feature | `cmConversation` + tools | `cmSmartDispatch` |
|---------------|--------------------------|-------------------|
| Requires function calling | Yes | No |
| Compatible models | OpenAI, Claude, Gemini, Qwen, LLaMA... | Any model |
| Multiple tools in one turn | Yes (tool_use loop) | No (1 tool per turn) |
| History contaminated by tool | No | No (isolation in Step 1) |
| Asynchronous mode | Yes | No |
| Extra latency | Minimal | +1 LLM call (Step 1) |
| Routing accuracy | High (structured JSON) | High on models ≥4b |
| Ideal use cases | Production, multi-step | Local models, prototypes |

> See [uMakerAi-FunctionCalling-SmartDispatch.md](uMakerAi-FunctionCalling-SmartDispatch.md) for an extended comparison with a selection guide.

---

## 12. Source file reference

| File | Relevant content |
|---------|---------------------|
| `Source/Core/uMakerAi.Chat.pas` | `InternalRunSmartDispatch`, `BuildSmartDispatchPrompt`, `ParseSmartDispatchResponse`, `ClassifySmartDispatch`, `RunSmartDispatchTool` |
| `Source/Core/uMakerAi.Chat.Tools.pas` | `IAiDispatchClassifier`, `TAiDispatchClassifierBase` |
| `Source/Tools/uMakerAi.Jev.SmartDispatch.pas` | `TAiJevDispatchClassifier` (Step 1 with Jev) |
| `Source/Core/uMakerAi.Core.pas` | `TAiChatMode` enum (value `cmSmartDispatch`) |
| `Source/Chat/uMakerAi.Chat.AiConnection.pas` | `TAiChatConnection.ChatMode` property |
| `Source/Chat/uMakerAi.Chat.Tools.pas` | `TAiImageToolBase`, `TAiWebSearchToolBase`, `TAiSpeechToolBase`, `TAiVideoToolBase` |
| `Demos/Console/Demos02-ChatTools/08-SmartDispatch/` | Complete demo with mock tools |

---

> See [uMakerAi-CapabilitySystem.md](uMakerAi-CapabilitySystem.md) for the configuration of `ModelCaps`/`SessionCaps`.
> See [uMakerAi-FunctionCalling-SmartDispatch.md](uMakerAi-FunctionCalling-SmartDispatch.md) for the comparison with native function calling.