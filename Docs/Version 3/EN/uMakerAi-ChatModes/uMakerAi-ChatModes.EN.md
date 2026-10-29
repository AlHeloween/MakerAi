# TAiChatMode — Chat operation modes

**MakerAI v3.3 — Technical documentation**
Last updated: April 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Enum reference](#2-enum-reference)
3. [The internal flow of RunNew: three phases](#3-the-internal-flow-of-runnew-three-phases)
4. [cmConversation — Smart mode (default)](#4-cmconversation--smart-mode-default)
5. [Forced modes — Direct call without gap analysis](#5-forced-modes--direct-call-without-gap-analysis)
   - [cmImageGeneration](#51-cmimagegeneration)
   - [cmVideoGeneration](#52-cmvideogeneration)
   - [cmSpeechGeneration](#53-cmspeechgeneration)
   - [cmTranscription](#54-cmtranscription)
   - [cmWebSearch](#55-cmwebsearch)
   - [cmReportGeneration](#56-cmreportgeneration)
6. [cmSmartDispatch — Smart dispatch](#6-cmsmartdispatch--smart-dispatch)
7. [Comparison table](#7-comparison-table)
8. [How to choose the correct mode](#8-how-to-choose-the-correct-mode)
9. [Changing mode at runtime](#9-changing-mode-at-runtime)
10. [Source file reference](#10-source-file-reference)

---

## 1. Introduction

`TAiChatMode` is the property that controls how `TAiChat.RunNew` processes each message. It determines:

- Which **input bridges** are activated (transcription, image description, PDF extraction)
- Which **output function** is executed (completions, image generation, TTS, web search, etc.)
- Whether or not the **capability gap analysis** (`ModelCaps`/`SessionCaps`) is applied

It is set in `TAiChat.ChatMode` or in `TAiChatConnection.ChatMode`. The default value is `cmConversation`.

```pascal
Conn.ChatMode := cmConversation;    // default — automatic orchestration
Conn.ChatMode := cmImageGeneration; // force: always generates an image
Conn.ChatMode := cmSpeechGeneration;// force: always generates speech
Conn.ChatMode := cmSmartDispatch;   // dispatch for models without function calling
```

---

## 2. Enum reference

Defined in `Source/Core/uMakerAi.Chat.pas`:

```pascal
TAiChatMode = (
  cmConversation,      // Smart orchestration with gap analysis (default)
  cmImageGeneration,   // Force image generation (skips gap analysis)
  cmVideoGeneration,   // Force video generation (skips gap analysis)
  cmSpeechGeneration,  // Force text-to-speech / TTS (skips gap analysis)
  cmTranscription,     // Force audio transcription (skips gap analysis)
  cmWebSearch,         // Force web search (skips gap analysis)
  cmReportGeneration,  // Force PDF/HTML/XLSX report generation
  cmSmartDispatch      // Two-step dispatch for models without function calling
);
```

### Classification

| Category | Modes |
|-----------|-------|
| **Smart** | `cmConversation` |
| **Forced** (direct, without gap analysis) | `cmImageGeneration`, `cmVideoGeneration`, `cmSpeechGeneration`, `cmTranscription`, `cmWebSearch`, `cmReportGeneration` |
| **Dispatch** | `cmSmartDispatch` |

---

## 3. The internal flow of RunNew: three phases

All modes go through the same `TAiChat.RunNew` method. `ChatMode` controls which parts are executed:

```text
RunNew(AskMsg)
  │
  ├── PHASE 1: Input bridge  ←── only cmConversation
  │   Processes attached files with gap analysis:
  │   • Audio without cap_Audio  → InternalRunTranscription
  │   • Image without cap_Image → InternalRunImageDescription
  │   • PDF without cap_Pdf      → InternalRunPDFDescription
  │
  ├── PHASE 2: Web grounding  ←── all except cmSmartDispatch
  │   If cap_WebSearch in Gap → InternalRunWebSearch
  │
  └── PHASE 3: Output orchestration  ←── all modes
      cmConversation:    gap analysis → correct branch
      cmImageGeneration: InternalRunImageGeneration (direct)
      cmVideoGeneration: InternalRunImageVideoGeneration (direct)
      cmSpeechGeneration:InternalRunSpeechGeneration (direct)
      cmTranscription:   InternalRunTranscription (direct)
      cmWebSearch:       InternalRunWebSearch (direct)
      cmReportGeneration:InternalRunReport (direct)
      cmSmartDispatch:   InternalRunSmartDispatch (two steps)
```

**Forced modes** (Phase 3) jump directly to their function without going through gap analysis or Phases 1 or 2.

---

## 4. cmConversation — Smart mode (default)

### What it does

The default mode. It applies all three phases and uses **gap analysis** (`SessionCaps − ModelCaps`) to automatically decide which function to execute. It is the most flexible mode and is recommended for production applications.

### Gap analysis in Phase 3

```text
cap_GenVideo  in Gap  →  InternalRunImageVideoGeneration
cap_GenImage  in Gap  →  InternalRunImageGeneration
cap_GenAudio  in Gap  →  InternalRunSpeechGeneration
cap_GenReport in Gap  →  InternalRunReport
(none)                →  InternalRunCompletions  ← most common case
```

### When to use it

- Conversational chat applications
- When the model can generate text, images, or audio according to the capability configuration
- When you want the framework to automatically decide the correct bridge

### Example

```pascal
Conn.DriverName := 'OpenAI';
Conn.Params.Values['Model']  := 'gpt-4.1';
Conn.ChatMode := cmConversation;  // default — no need to specify it

// With SessionCaps=[cap_GenImage], gap analysis activates image generation
// automatically when the model does not have native cap_GenImage
Conn.Params.Values['SessionCaps'] := '[cap_GenImage]';
```

### Attached files with gap analysis (Phase 1)

`cmConversation` is the only mode that processes files automatically in Phase 1:

```pascal
// If the model does not have cap_Audio (gap), the framework transcribes the audio before sending it
Conn.ChatMode := cmConversation;
Resp := Conn.AddMessageAndRun('Transcribe this', 'user', [AudioMediaFile]);
// → Internally: transcription → insert text into the prompt → completions
```

---

## 5. Forced modes — Direct call without gap analysis

Forced modes **skip gap analysis** and call the corresponding output function directly. They are useful when:

- You know in advance what type of output you want
- You want a more explicit API without depending on the capability configuration
- You are building a dedicated interface (e.g., TTS only, image generation only)

> **Important:** Forced modes also **skip Phase 1** (file input bridge). If you need the framework to process attached files automatically, use `cmConversation`.

### 5.1 cmImageGeneration

Generates an image from the user's message. It requires an `ImageTool` assigned in `ChatTools`, or for the model to have native image-generation capability (`cap_GenImage` in `ModelCaps`).

```pascal
Conn.ChatMode := cmImageGeneration;
Conn.ChatTools.ImageTool := MiDalleImageTool;

// Each call generates an image, regardless of the prompt content
Resp := Conn.AddMessageAndRun('A mountainous landscape at sunset', 'user', []);
// → InternalRunImageGeneration direct
```

**Requires:** `ChatTools.ImageTool` assigned, or a model with native `cap_GenImage` (e.g., `gemini-2.5-flash-image`).

---

### 5.2 cmVideoGeneration

Generates a video from the message. It requires an assigned `VideoTool` (`TAiGeminiVideoTool`, `TAiSoraGenerator`, etc.).

```pascal
Conn.ChatMode := cmVideoGeneration;
Conn.ChatTools.VideoTool := MiVideoTool;

Resp := Conn.AddMessageAndRun('A wave breaking on the shore', 'user', []);
// → InternalRunImageVideoGeneration direct
```

**Note:** Video generation is inherently asynchronous and can take minutes. The result arrives via `OnReceiveDataEnd`.

---

### 5.3 cmSpeechGeneration

Converts the message text to audio (TTS). It requires an assigned `SpeechTool` or a model with native TTS.

```pascal
Conn.ChatMode := cmSpeechGeneration;
Conn.ChatTools.SpeechTool := MiSpeechTool;

Resp := Conn.AddMessageAndRun('Welcome to MakerAI', 'user', []);
// → InternalRunSpeechGeneration direct
// The audio arrives in ResMsg.MediaFiles
```

**Difference from cmConversation:** In `cmConversation`, the text first goes through the LLM and the generated response is converted to audio. In `cmSpeechGeneration`, the user's message text is converted directly without going through completions.

---

### 5.4 cmTranscription

Transcribes the first audio file found in the message's attached files.

```pascal
Conn.ChatMode := cmTranscription;
Conn.ChatTools.SpeechTool := MiWhisperTool;

Resp := Conn.AddMessageAndRun('', 'user', [AudioMediaFile]);
// → InternalRunTranscription direct on the first audio file
// The transcription arrives in Resp and in AudioMediaFile.Transcription
```

**Note:** It processes only the **first** audio file found and stops. If there are multiple files, use `cmConversation` with gap analysis to process all of them.

---

### 5.5 cmWebSearch

Executes a web search directly using the message text as the query.

```pascal
Conn.ChatMode := cmWebSearch;
Conn.ChatTools.WebSearchTool := MiGeminiWebSearchTool;

Resp := Conn.AddMessageAndRun(
  'latest artificial intelligence news 2025', 'user', []);
// → InternalRunWebSearch direct
// Citations arrive in ResMsg.Citations
```

**Difference from cmConversation:** In `cmConversation` with `cap_WebSearch` in gap, it first searches the web and then the LLM synthesizes. In `cmWebSearch`, the search tool's response reaches the user directly without additional synthesis.

---

### 5.6 cmReportGeneration

Generates a report (PDF, HTML, XLSX) from the message content. It requires an assigned `ReportTool`.

```pascal
Conn.ChatMode := cmReportGeneration;
Conn.ChatTools.ReportTool := MiReportTool;

Resp := Conn.AddMessageAndRun('Generate a Q1 sales report', 'user', []);
// → InternalRunReport direct
// The report arrives in ResMsg.MediaFiles
```

---

## 6. cmSmartDispatch — Smart dispatch

Two-step mode for models without native function calling. The LLM classifies the request into a plain-text label (`[IMAGEGEN]`, `[WEBSEARCH]`, `[CHAT]`, etc.) and the framework executes the corresponding tool.

**Exclusive requirement:** `Asynchronous = False`.

```pascal
Conn.ChatMode := cmSmartDispatch;
Conn.Params.Values['Asynchronous'] := 'False';  // required
```

> See complete documentation in [uMakerAi-ChatTools-SmartDispatch.md](uMakerAi-ChatTools-SmartDispatch.md).

---

## 7. Comparison table

| Mode | Gap analysis | Phase 1 (files) | Phase 2 (web) | Async supported | Typical use |
|------|:---:|:---:|:---:|:---:|------------|
| `cmConversation` | ✅ Complete | ✅ | ✅ | ✅ | General chat, production |
| `cmImageGeneration` | ❌ Direct | ❌ | ❌ | ✅ | Dedicated image UI |
| `cmVideoGeneration` | ❌ Direct | ❌ | ❌ | ✅ | Dedicated video UI |
| `cmSpeechGeneration` | ❌ Direct | ❌ | ❌ | ✅ | TTS UI, text reader |
| `cmTranscription` | ❌ Direct | ❌ | ❌ | ✅ | Transcription UI |
| `cmWebSearch` | ❌ Direct | ❌ | ❌ | ✅ | Dedicated search engine |
| `cmReportGeneration` | ❌ Direct | ❌ | ❌ | ✅ | Report generator |
| `cmSmartDispatch` | ❌ (LLM routing) | ❌ | ❌ | ❌ **No** | Local models without function calling |

---

## 8. How to choose the correct mode

### Can the user ask questions of any type?
→ **`cmConversation`** — the framework decides which tool to use

### Is your application's function specific (images only, TTS only)?
→ **Corresponding forced mode** — more explicit, without gap analysis overhead

### Are you using a small local model without function calling (Ollama, LM Studio)?
→ **`cmSmartDispatch`** — with `Asynchronous = False`

### Do you need the LLM to synthesize the search result before responding?
→ **`cmConversation`** with `cap_WebSearch` in gap — the LLM receives the web result and generates the final response

### Do you need the raw search result directly?
→ **`cmWebSearch`** — the tool result arrives without additional synthesis

### Quick decision tree

```
General chat application?
  └─ YES → cmConversation

Single function known in advance?
  ├─ Images only        → cmImageGeneration
  ├─ Video only         → cmVideoGeneration
  ├─ TTS only           → cmSpeechGeneration
  ├─ Transcription only → cmTranscription
  ├─ Web search only    → cmWebSearch
  └─ Reports only       → cmReportGeneration

Local model without function calling?
  └─ cmSmartDispatch (with Asynchronous=False)
```

---

## 9. Changing mode at runtime

`ChatMode` can be changed between calls. It is useful for applications with multiple functions:

```pascal
// "Normal chat" button
procedure TForm1.BtnChatClick(Sender: TObject);
begin
  Conn.ChatMode := cmConversation;
  Conn.AddMessageAndRun(EdInput.Text, 'user', []);
end;

// "Generate image" button
procedure TForm1.BtnImageClick(Sender: TObject);
begin
  Conn.ChatMode := cmImageGeneration;
  Conn.AddMessageAndRun(EdInput.Text, 'user', []);
end;

// "Read aloud" button
procedure TForm1.BtnTTSClick(Sender: TObject);
begin
  Conn.ChatMode := cmSpeechGeneration;
  Conn.AddMessageAndRun(EdInput.Text, 'user', []);
end;
```

> **Note:** Changing modes does not clear the history. If you want to prevent messages from different modes from mixing in the LLM context, call `Conn.Messages.Clear` before changing the mode.

---

## 10. Source file reference

| File | Relevant content |
|---------|---------------------|
| `Source/Core/uMakerAi.Chat.pas` | `TAiChatMode` enum (line ~63), `RunNew` with the three phases (line ~2840) |
| `Source/Chat/uMakerAi.Chat.AiConnection.pas` | `TAiChatConnection.ChatMode` property, `SetChatMode` |
| `Source/Chat/uMakerAi.Chat.Tools.pas` | ChatTools base classes compatible with all modes |

---

> See [uMakerAi-CapabilitySystem.md](uMakerAi-CapabilitySystem.md) to understand the gap analysis used by `cmConversation`.
> See [uMakerAi-ChatTools-SmartDispatch.md](uMakerAi-ChatTools-SmartDispatch.md) for the complete documentation of `cmSmartDispatch`.
> See [uMakerAi-FunctionCalling-SmartDispatch.md](uMakerAi-FunctionCalling-SmartDispatch.md) for the comparison with native function calling.