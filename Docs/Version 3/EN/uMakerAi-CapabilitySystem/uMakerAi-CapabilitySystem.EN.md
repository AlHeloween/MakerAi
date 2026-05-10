# Capability System: ModelCaps and SessionCaps

**MakerAI v3.3 — Technical Documentation**
Last updated: March 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [The TAiCapability Enum](#2-the-taicapability-enum)
3. [ModelCaps vs SessionCaps](#3-modelcaps-vs-sessioncaps)
4. [Gap Analysis: The Core Engine](#4-gap-analysis-the-core-engine)
5. [Configuration via TAiChatFactory](#5-configuration-via-taichatfactory)
6. [Runtime Configuration](#6-runtime-configuration)
7. [Compatibility with Legacy System](#7-compatibility-with-legacy-system)
8. [Frequent Configuration Patterns](#8-frequent-configuration-patterns)
9. [Capability Reference by Provider](#9-capability-reference-by-provider)
10. [Adding a New Provider](#10-adding-a-new-provider)
11. [Source File Reference](#11-source-file-reference)

---

## 1. Introduction

MakerAI v3.3 introduces the **unified capability system** (`TAiCapabilities`), replacing the four scattered legacy parameters (`NativeInputFiles`, `NativeOutputFiles`, `ChatMediaSupports`, `EnabledFeatures`) with two orthogonal and simple properties:

| Property | Meaning |
|----------|---------|
| `ModelCaps` | What the model can do **natively** via completions |
| `SessionCaps` | What the session **needs** (can exceed native capabilities) |

The difference between them (`Gap = SessionCaps - ModelCaps`) determines which bridges and tools the orchestrator activates automatically before calling the API.

**Advantages over the previous system:**
- A single line completely describes a model
- The correct bridge activates itself, without additional code
- Backward compatible: models configured with the legacy system continue working without changes

---

## 2. The TAiCapability Enum

Defined in `Source/Core/uMakerAi.Core.pas`:

```pascal
TAiCapability = (
  // ---- Input / Comprehension (native completions) ----
  cap_Image,            // model understands incoming images
  cap_Audio,            // model understands/transcribes incoming audio
  cap_Video,            // model understands incoming video
  cap_Pdf,              // model understands incoming PDFs
  cap_WebSearch,        // model can search the web
  cap_Reasoning,        // model has extended reasoning (CoT/thinking)
  cap_CodeInterpreter,  // model can execute code
  cap_Memory,           // model has persistent memory
  cap_TextEditor,       // model can edit text files
  cap_ComputerUse,      // model can control the computer
  cap_Shell,            // model can execute shell commands

  // ---- Output / Generation (gap -> activates automatic bridge) ----
  cap_GenImage,         // produce an image as output
  cap_GenAudio,         // produce audio as output (TTS)
  cap_GenVideo,         // produce video as output
  cap_GenReport,        // produce a report (PDF, HTML, XLSX)
  cap_ExtractCode       // post-process: extract code blocks from response
);

TAiCapabilities = set of TAiCapability;
```

### Conceptual Classification

**Input capabilities** (`cap_Image` .. `cap_Shell`): describe what types of content the model natively understands in the completions endpoint. If the model lacks an input capability but the session needs it, the orchestrator runs an **input bridge** (transcription, image description, PDF text extraction) before sending the prompt.

**Generation capabilities** (`cap_GenImage` .. `cap_ExtractCode`): describe what type of content the session produces as output. When there's a gap in these capabilities, the orchestrator redirects the call to a specialized endpoint (TTS, image generation, etc.) instead of completions.

---

## 3. ModelCaps vs SessionCaps

### ModelCaps — Native Model Capabilities

Represents exactly what the model can do through the completions endpoint **without external intervention**. It's a fixed fact of the model: it doesn't change based on user needs.

Examples:
- `GPT-4.1`: can process images → `ModelCaps = [cap_Image]`
- `dall-e-3`: only generates images, no completions → `ModelCaps = []`
- `gemini-2.5-flash`: full multimodal → `ModelCaps = [cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]`

### SessionCaps — Desired Session Capabilities

Represents what the **user wants** the session to be able to do. It can match `ModelCaps` (no gap, direct call) or exceed it (with gap, bridges activate).

Examples:
- Want to use GPT-4o to generate TTS audio: `SessionCaps = [cap_Image, cap_GenAudio]` → Gap = `[cap_GenAudio]` → uses OpenAI TTS endpoint
- Want to use Ollama (no vision) with images: `SessionCaps = [cap_Image]` + `ModelCaps = []` → Gap = `[cap_Image]` → vision description bridge before completions

### Relationship with Legacy Parameters

When assigning `ModelCaps` and `SessionCaps`, the system automatically synchronizes legacy parameters:

| New Property | Synchronizes (legacy) |
|--------------|----------------------|
| `ModelCaps` | `NativeInputFiles` + `ChatMediaSupports` |
| `SessionCaps` | `NativeOutputFiles` + `EnabledFeatures` |

This synchronization occurs in the `SetModelCaps` and `SetSessionCaps` setters (called both from code and via RTTI when applying factory params).

---

## 4. Gap Analysis: The Core Engine

The `TAiChat.RunNew` method calculates the gap on its first line:

```pascal
Gap := FSessionCaps - FModelCaps;  // set subtraction
```

Then executes three phases:

### Phase 1: Input Bridge (only in `cmConversation`)

For each file attached to the message that the model doesn't natively support:

| Gap contains | File type | Bridge activated |
|--------------|-----------|------------------|
| `cap_Audio` | `.mp3`, `.wav`, etc. | `InternalRunTranscription` → converts to text |
| `cap_Image` | `.png`, `.jpg`, etc. | `InternalRunImageDescription` → describes the image |
| `cap_Pdf` | `.pdf` | `InternalRunPDFDescription` → extracts/describes the PDF |

Already processed files (`MF.Procesado = True`) are skipped. There's also priority 1: if the `OnProcessMediaFile` event is assigned, it's used before the automatic bridge.

### Phase 2: Grounding (always, no mode guard)

| Gap contains | Action |
|--------------|--------|
| `cap_WebSearch` | `InternalRunWebSearch` — searches the web and injects results into context |

### Phase 3: Output Orchestration (in `cmConversation`)

The gap determines which endpoint is used. Evaluated in priority order:

| Gap contains | Method invoked |
|--------------|----------------|
| `cap_GenVideo` | `InternalRunImageVideoGeneration` |
| `cap_GenImage` | `InternalRunImageGeneration` |
| `cap_GenAudio` | `InternalRunSpeechGeneration` |
| `cap_GenReport` | `InternalRunReport` |
| (empty) | `InternalRunCompletions` (normal conversation) |

`cap_ExtractCode` doesn't redirect the endpoint: it's managed internally by `InternalRunCompletions` via the legacy parameter `Tfc_ExtractTextFile in NativeOutputFiles` (synchronized by `SyncLegacyFromSessionCaps`).

### Forced Modes

If `ChatMode` is different from `cmConversation`, the Gap is ignored in Phase 1 and Phase 3, and the corresponding method is called directly:

```pascal
cmImageGeneration  → InternalRunImageGeneration  (always)
cmVideoGeneration  → InternalRunImageVideoGeneration
cmSpeechGeneration → InternalRunSpeechGeneration
cmWebSearch        → InternalRunWebSearch
cmReportGeneration → InternalRunReport
cmTranscription    → InternalRunTranscription (first audio of message)
```

---

## 5. Configuration via TAiChatFactory

The standard way to configure capabilities is in `Source/Chat/uMakerAi.Chat.Initializations.pas`, using `TAiChatFactory.Instance.RegisterUserParam`.

### Configuration Levels

Parameters have three levels (from lowest to highest priority):

1. **Driver defaults** — `RegisterDefaultParams` in the driver class
2. **Global provider defaults** — `RegisterUserParam(Driver, Param, Value)`
3. **Model override** — `RegisterUserParam(Driver, Model, Param, Value)`

A model override always wins over the driver global.

### Syntax

```pascal
// Global default for entire provider
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'ModelCaps',   '[cap_Image]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'SessionCaps', '[cap_Image]');

// Override for a specific model
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'model-name', 'ModelCaps',   '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'model-name', 'SessionCaps', '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'model-name', 'ThinkingLevel', 'tlMedium');
```

### Capability String Format

The string follows Pascal set format, using exact enum names from `TAiCapability`:

```
'[]'                                        // empty set
'[cap_Image]'                               // one capability
'[cap_Image, cap_Reasoning]'                // multiple capabilities
'[cap_Image, cap_Audio, cap_Video, cap_Pdf]'  // full multimedia
```

The parser (in `ApplyParamsToChat`, via RTTI `tkSet`) is case-sensitive: names must exactly match enum values.

### ThinkingLevel Parameter

For models with extended reasoning, configure the level with `ThinkingLevel`:

| Value | Description |
|-------|-------------|
| `tlDefault` | Lets provider choose (generally Medium) |
| `tlLow` | Minimal reasoning — fast response, low cost |
| `tlMedium` | Quality/speed balance — recommended value |
| `tlHigh` | Maximum reasoning — higher quality, slower and more expensive |

`ThinkingLevel` only has effect if `cap_Reasoning` is in `ModelCaps`. If the model doesn't have `cap_Reasoning`, the parameter is ignored.

### Custom Profiles (aa_*)

To create model variants with different configurations (e.g., different thinking level, reduced caps), use `RegisterCustomModel` + override:

```pascal
// Creates 'aa_o3-high' that internally uses model 'o3'
TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_o3-high', 'o3');
TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'aa_o3-high', 'ThinkingLevel', 'tlHigh');

// Creates 'aa_gemini-3-pro-fast' with reduced thinking for fast responses
TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3-pro-fast', 'gemini-3-pro-preview');
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'ThinkingLevel', 'tlLow');
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'ModelCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');  // no cap_Reasoning
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'SessionCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');
```

The `aa_` prefix is a project convention for custom profiles; it's not mandatory but helps distinguish them from official models in dropdown lists.

---

## 6. Runtime Configuration

Besides the factory, `ModelCaps` and `SessionCaps` can be assigned directly on the instance in code:

### On TAiChatConnection

```pascal
// At design time (Object Inspector) or in code
AiConnection.DriverName := 'OpenAi';
AiConnection.Model := 'gpt-4.1';

// Override caps for this specific session
AiConnection.ModelCaps   := [cap_Image, cap_Pdf];
AiConnection.SessionCaps := [cap_Image, cap_Pdf, cap_GenAudio];
// Gap = [cap_GenAudio] -> next Run() will use TTS endpoint
```

### On TAiChat directly

```pascal
var Chat: TAiOpenChat;
Chat := TAiOpenChat.Create(nil);
Chat.ApiKey := '@OPENAI_API_KEY';
Chat.Model  := 'gpt-image-1';
Chat.ModelCaps   := [];
Chat.SessionCaps := [cap_GenImage];
// Gap = [cap_GenImage] -> Run() will call InternalRunImageGeneration
```

**Important:** When assigning `ModelCaps` or `SessionCaps` directly, `FNewSystemConfigured = True` is activated, which prevents `EnsureNewSystemConfig` from overwriting these values with automatic translation from legacy parameters.

### Query Current Caps

```pascal
// Read effective caps (after applying factory params)
var Gap: TAiCapabilities;
Gap := AiConnection.SessionCaps - AiConnection.ModelCaps;

if cap_GenAudio in Gap then
  ShowMessage('This session will generate audio via TTS');

if cap_Reasoning in AiConnection.ModelCaps then
  ShowMessage('This model has native reasoning');
```

---

## 7. Compatibility with Legacy System

### Legacy Parameters

The previous system configured capabilities via four parameters:

| Legacy Parameter | Type | Description |
|------------------|------|-------------|
| `NativeInputFiles` | `TAiFileCategories` | File types the model natively accepts |
| `NativeOutputFiles` | `TAiFileCategories` | File types the model generates |
| `ChatMediaSupports` | `TAiChatMediaSupports` | Native logical model capabilities |
| `EnabledFeatures` | `TAiChatMediaSupports` | Desired session capabilities |

### Automatic Translation

If a model was configured with the legacy system and `ModelCaps`/`SessionCaps` were **not** explicitly assigned (`FNewSystemConfigured = False`), the `EnsureNewSystemConfig` method (called at the start of each `Run`) automatically translates:

```
ChatMediaSupports + NativeInputFiles/OutputFiles  →  ModelCaps
EnabledFeatures   + NativeOutputFiles             →  SessionCaps
```

This translation happens once per session and is invisible to the user. The legacy system continues working without any code changes.

### Configuration Priority

```
1. ModelCaps/SessionCaps explicitly assigned  (FNewSystemConfigured=True)  ← Highest priority
2. Automatic translation from legacy params    (FNewSystemConfigured=False)
3. Driver defaults (RegisterDefaultParams)                                  ← Lowest priority
```

### Migration Guide

To migrate an existing driver to the new system:

```pascal
// Before (legacy)
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'ChatMediaSupports', 'Tcm_Image,Tcm_Pdf');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'EnabledFeatures',   'Tcm_Image,Tcm_Pdf');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'NativeInputFiles',  'Tfc_Image,Tfc_Pdf');

// After (new system v3.3)
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'ModelCaps',   '[cap_Image, cap_Pdf]');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'SessionCaps', '[cap_Image, cap_Pdf]');
```

It's not necessary to remove existing legacy parameters if new ones are configured: when `ModelCaps`/`SessionCaps` are present in factory params, RTTI applies them via setters that activate `FNewSystemConfigured = True`, ignoring automatic translation.

---

## 8. Frequent Configuration Patterns

### Pattern 1: Plain Text Model (no special capabilities)

```pascal
// Text only, no tools
RegisterUserParam('Driver', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'SessionCaps', '[]');
RegisterUserParam('Driver', 'Tool_Active', 'False');
```

Result: `Gap = []` → `InternalRunCompletions` direct.

### Pattern 2: Model with Native Vision

```pascal
// Model can see images directly in completions
RegisterUserParam('Driver', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Driver', 'SessionCaps', '[cap_Image]');
RegisterUserParam('Driver', 'Tool_Active', 'True');
```

Result: `Gap = []` → images go direct to completions API.

### Pattern 3: Full Multimodal Model (Gemini 2.5 Flash)

```pascal
RegisterUserParam('Gemini', 'gemini-2.5-flash', 'ModelCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
RegisterUserParam('Gemini', 'gemini-2.5-flash', 'SessionCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
```

Result: `Gap = []` → everything goes direct to Gemini native completions.

### Pattern 4: Model with Reasoning (CoT/thinking)

```pascal
RegisterUserParam('Driver', 'reasoning-model', 'ModelCaps',    '[cap_Image, cap_Reasoning]');
RegisterUserParam('Driver', 'reasoning-model', 'SessionCaps',  '[cap_Image, cap_Reasoning]');
RegisterUserParam('Driver', 'reasoning-model', 'ThinkingLevel', 'tlMedium');
```

Result: the driver activates extended reasoning mode according to configured level.

### Pattern 5: TTS via Dedicated Endpoint

```pascal
// ModelCaps empty = no completions / doesn't understand inputs
// Gap = [cap_GenAudio] → InternalRunSpeechGeneration
RegisterUserParam('Driver', 'tts-model', 'ModelCaps',    '[]');
RegisterUserParam('Driver', 'tts-model', 'SessionCaps',  '[cap_GenAudio]');
RegisterUserParam('Driver', 'tts-model', 'Tool_Active',  'False');
RegisterUserParam('Driver', 'tts-model', 'Voice',        'alloy');
```

### Pattern 6: Image Generation via Dedicated Endpoint

```pascal
// ModelCaps empty = uses image endpoint, not completions
// Gap = [cap_GenImage] → InternalRunImageGeneration
RegisterUserParam('Driver', 'image-model', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'image-model', 'SessionCaps', '[cap_GenImage]');
RegisterUserParam('Driver', 'image-model', 'Tool_Active', 'False');
```

### Pattern 7: NATIVE Image Generation via Completions (Gemini)

```pascal
// cap_GenImage in ModelCaps AND SessionCaps = model returns image in completions response
// Gap = [] → InternalRunCompletions (model generates image inline in response)
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'ModelCaps',   '[cap_Image, cap_GenImage]');
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'SessionCaps', '[cap_Image, cap_GenImage]');
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'Tool_Active', 'False');
```

The difference with Pattern 6: here `cap_GenImage` is in **both** `ModelCaps` and `SessionCaps`, so there's no gap. Completions itself returns the image inline. In Pattern 6, `cap_GenImage` is only in `SessionCaps`, creating the gap that redirects to the dedicated image endpoint.

### Pattern 8: STT (Transcription) via Dedicated Endpoint

```pascal
// cap_Audio in ModelCaps (supports audio) + Tool_Active=False (no tools)
// Use with ChatMode = cmTranscription
RegisterUserParam('Driver', 'whisper', 'ModelCaps',   '[cap_Audio]');
RegisterUserParam('Driver', 'whisper', 'SessionCaps', '[cap_Audio]');
RegisterUserParam('Driver', 'whisper', 'Tool_Active', 'False');
```

### Pattern 9: Vision Bridge for Text-Only Model

```pascal
// Model (e.g., Ollama text-only) has no native vision
// User wants to send images → automatic bridge describes them before prompt
RegisterUserParam('Ollama', 'ModelCaps',   '[]');          // can't see images
RegisterUserParam('Ollama', 'SessionCaps', '[cap_Image]'); // session requires images
// Gap = [cap_Image] → in Phase 1, InternalRunImageDescription executes automatically
// Image is described in text and attached to prompt
```

### Pattern 10: Video Generation

```pascal
// ModelCaps=[cap_Image]: accepts image as input (text-to-video or image-to-video)
// SessionCaps adds cap_GenVideo: Gap=[cap_GenVideo] → InternalRunImageVideoGeneration
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'SessionCaps', '[cap_Image, cap_GenVideo]');
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'Tool_Active', 'False');
```

---

## 9. Capability Reference by Provider

### OpenAI

| Model | ModelCaps | SessionCaps | Tool_Active | Notes |
|-------|-----------|-------------|-------------|-------|
| gpt-4.1 / 4.1-mini / 4.1-nano | `[cap_Image]` | `[cap_Image]` | True | 1M ctx, 32K output |
| gpt-4o / gpt-4o-mini | `[cap_Image]` | `[cap_Image]` | True | |
| o3 | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| o3-pro | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlHigh |
| o4-mini | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| o3/o4-mini-deep-research | `[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]` | idem | True | |
| gpt-4o-search-preview | `[cap_WebSearch]` | `[cap_WebSearch]` | False | |
| gpt-image-1 / dall-e-3 / dall-e-2 | `[]` | `[cap_GenImage]` | False | Gap → image endpoint |
| gpt-4o-mini-tts | `[]` | `[cap_GenAudio]` | False | Gap → TTS endpoint |
| gpt-4o-audio-preview | `[cap_Audio, cap_GenAudio]` | `[cap_Audio, cap_GenAudio]` | False | Native audio I/O in completions |
| gpt-4o-transcribe / mini-transcribe | `[cap_Audio]` | `[cap_Audio]` | False | Native STT |
| aa_gpt-4.1-pdf | `[cap_Image, cap_Pdf]` | `[cap_Image, cap_Pdf]` | True | Profile with native PDF |

### Gemini (Google)

| Model | ModelCaps | SessionCaps | Tool_Active | Notes |
|-------|-----------|-------------|-------------|-------|
| gemini-2.5-flash | `[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]` | idem | True | 1M ctx, 65K output |
| gemini-2.5-flash-lite | `[cap_Image, cap_Audio, cap_Video, cap_Pdf]` | idem | True | Budget/fast |
| gemini-2.5-pro | `[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]` | idem | True | |
| gemini-3-pro-preview | same as 2.5-pro | idem | True | ThinkingLevel=tlHigh |
| gemini-3.1-pro-preview | same | idem | True | ThinkingLevel=tlHigh |
| gemini-2.5-flash-image | `[cap_Image, cap_GenImage]` | idem | False | Native image gen in completions |
| gemini-3-pro-image-preview | `[cap_Image, cap_GenImage]` | idem | False | No ThinkingLevel |
| gemini-2.5-flash-preview-tts | `[]` | `[cap_GenAudio]` | False | Gap → TTS |
| gemini-2.5-pro-preview-tts | `[]` | `[cap_GenAudio]` | False | Gap → TTS |
| aa_veo-2.0/3.0/3.1 | `[cap_Image]` | `[cap_Image, cap_GenVideo]` | False | Gap=[cap_GenVideo] → video |

### Claude (Anthropic)

| Configuration | ModelCaps | SessionCaps | Tool_Active |
|---------------|-----------|-------------|-------------|
| Global (all models) | `[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]` | idem | False |

All current Claude models (Opus 4.6, Sonnet 4.6/4.5, Haiku 4.5) share the same native capabilities: vision, PDF, reasoning and web search.

### Groq

| Model | ModelCaps | SessionCaps | Tool_Active |
|-------|-----------|-------------|-------------|
| Global (default) | `[]` | `[]` | True |
| llama-3.1/3.3 | `[]` (inherits global) | `[]` | True |
| qwen/qwen-3-32b | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| deepseek-r1-distill-llama-70b | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| llama-4-scout / llama-4-maverick | `[cap_Image]` | `[cap_Image]` | True | |
| compound-beta / mini | `[cap_WebSearch, cap_CodeInterpreter]` | idem | False | Native, no tool calls |
| whisper-large-v3 / turbo | `[cap_Audio]` | `[cap_Audio]` | False | STT |
| canopylabs/orpheus-v1-english | `[]` | `[cap_GenAudio]` | False | Gap → TTS |

### DeepSeek

| Model | ModelCaps | SessionCaps | Tool_Active | Notes |
|-------|-----------|-------------|-------------|-------|
| deepseek-chat | `[]` | `[]` | True | Text + tools, 128K ctx |
| deepseek-reasoner | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |

### Kimi (Moonshot AI)

| Model | ModelCaps | SessionCaps | Tool_Active |
|-------|-----------|-------------|-------------|
| kimi-k2 | `[]` | `[]` | True |
| kimi-k2.5 | `[cap_Image, cap_Pdf, cap_Reasoning]` | idem | True |
| kimi-k2-thinking | `[cap_Reasoning]` | `[cap_Reasoning]` | True |
| moonshot-v1-* | `[]` | `[]` | False |
| moonshot-v1-*-vision | `[cap_Image]` | `[cap_Image]` | False |

### xAI Grok

| Model | ModelCaps | SessionCaps | Tool_Active |
|-------|-----------|-------------|-------------|
| grok-3 | `[]` | `[]` | True |
| grok-3-mini | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlLow |
| grok-4-fast-reasoning | `[cap_Image, cap_Reasoning]` | idem | True | 2M ctx |
| grok-2-image-1212 / grok-imagine-* | `[]` | `[cap_GenImage]` | False | Gap → image |
| grok-imagine-video | `[]` | `[cap_GenVideo]` | False | Gap → video |

### Mistral

| Configuration | ModelCaps | SessionCaps | Tool_Active |
|---------------|-----------|-------------|-------------|
| Global (default) | `[cap_Image]` | `[cap_Image]` | True |
| magistral-medium/small | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| devstral-latest | `[]` | `[cap_Pdf, cap_Image]` | True | No own vision |
| voxtral-mini/small | `[cap_Audio]` | `[cap_Audio]` | False | STT via completions |
| mistral-ocr-latest | `[cap_Pdf]` | `[cap_Pdf]` | False | OCR via /v1/ocr |

### Cohere

| Model | ModelCaps | SessionCaps | Tool_Active |
|-------|-----------|-------------|-------------|
| command-a-03-2025 | `[]` | `[]` | True |
| command-a-reasoning-08-2025 | `[cap_Reasoning]` | `[cap_Reasoning]` | True |
| command-a-vision-07-2025 | `[cap_Image]` | `[cap_Image]` | False |
| c4ai-aya-vision-8b/32b | `[cap_Image]` | `[cap_Image]` | False |

### Ollama (Local Models)

| Configuration | ModelCaps | SessionCaps | Tool_Active |
|---------------|-----------|-------------|-------------|
| Global (default) | `[]` | `[]` | False |
| llama3.3 / qwen2.5 | `[]` | `[]` | True |
| qwen3:latest | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| deepseek-r1:latest | `[cap_Reasoning]` | `[cap_Reasoning]` | False | ThinkingLevel=tlMedium |
| llama3.2-vision | `[cap_Image]` | `[cap_Image]` | False | |
| qwen2.5vl | `[cap_Image]` | `[cap_Image]` | True | |
| gemma3:1b/4b/12b/27b | `[cap_Image]` | `[cap_Image]` | True | |

---

## 10. Adding a New Provider

When creating a new driver (`TAi[Provider]Chat` inheriting from `TAiChat`), configure capabilities in `uMakerAi.Chat.Initializations.pas`:

```pascal
// 1. Configure global provider defaults
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'Max_Tokens',  '16000');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'Tool_Active', 'True');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'ModelCaps',   '[cap_Image]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'SessionCaps', '[cap_Image]');

// 2. Per-model overrides
// Basic model (text only)
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-basic', 'ModelCaps',   '[]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-basic', 'SessionCaps', '[]');

// Model with reasoning
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'ModelCaps',    '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'SessionCaps',  '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'ThinkingLevel', 'tlMedium');

// TTS model
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'ModelCaps',   '[]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'SessionCaps', '[cap_GenAudio]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'Tool_Active', 'False');
```

### Design Questions When Configuring a New Model

1. **What input types does the completions endpoint accept?**
   → Those are the input `ModelCaps` (`cap_Image`, `cap_Audio`, etc.)

2. **Can the completions endpoint generate images/audio/video inline?**
   → Add the corresponding `cap_Gen*` to `ModelCaps` (and `SessionCaps`). Gap = 0, goes direct.

3. **Does the model have a separate TTS/image/video endpoint?**
   → `ModelCaps = []`, `SessionCaps = [cap_Gen*]`. Gap activates the bridge.

4. **Does the model have extended reasoning?**
   → `cap_Reasoning` in `ModelCaps` and `SessionCaps`, plus `ThinkingLevel`.

5. **Does the model support tool calling?**
   → `Tool_Active = True`.

---

## 11. Source File Reference

| Purpose | File |
|---------|------|
| Definition of `TAiCapability` and `TAiCapabilities` | `Source/Core/uMakerAi.Core.pas` (line 65) |
| Declaration of `ModelCaps`/`SessionCaps` in `TAiChat` | `Source/Core/uMakerAi.Chat.pas` (line 430) |
| Setter implementation and legacy sync | `Source/Core/uMakerAi.Chat.pas` (line 2886) |
| Gap analysis and orchestration phases (`RunNew`) | `Source/Core/uMakerAi.Chat.pas` (line 3004) |
| Apply params via RTTI (`ApplyParamsToChat`) | `Source/Chat/uMakerAi.Chat.AiConnection.pas` (line 509) |
| Model configuration by provider | `Source/Chat/uMakerAi.Chat.Initializations.pas` |

---

*Documentation generated for MakerAI v3.3 — March 2026*
*Official project source: https://makerai.cimamaker.com*