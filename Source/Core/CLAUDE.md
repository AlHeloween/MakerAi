# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source/Core Overview

This folder contains the foundation layer of the MakerAI framework. All provider-specific chat drivers, RAG systems, and UI components depend on these core abstractions.

## Unit Responsibilities

| Unit | Purpose |
|------|---------|
| `uMakerAi.Core.pas` | Base types: `TAiMediaFile`, `TAiFileCategory`, `TAiChatMediaSupport`, `TAiChatState`, MIME utilities |
| `uMakerAi.Chat.pas` | Abstract `TAiChat` base class - all LLM drivers inherit from this |
| `uMakerAi.Chat.Messages.pas` | `TAiChatMessage`, `TAiChatMessages`, `TAiToolsFunction`, citations system |
| `uMakerAi.Chat.Tools.pas` | `IAiToolContext` interface and base tool classes (`TAiSpeechToolBase`, `TAiVisionToolBase`, etc.) |
| `uMakerAi.Chat.Bridge.pas` | Bridge utilities for chat interoperability |
| `uMakerAi.Prompts.pas` | `TAiPrompts`: templates with `<#var>`, PPM prompts and skills (`LoadFromPPM`, `LoadSkillFromPPM`) and local skills (`LoadSkillFromFile`, `LoadSkillsFromFolder`); `ApplySkill(nombre, SystemPrompt, Append)` copies the instructions to any `TStrings` (it works the same for `TAiChat` and `TAiChatConnection`, which do not inherit from one another) |
| `uMakerAi.Skills.Format.pas` | Single parser for SKILL.md (`TAiSkillDoc`: YAML frontmatter + body; text, file, folder or PPM; `FindSkillFiles`) and read-only client for the PPM registry (`TAiPPMClient`: version by semver without retractions, `skill-` prefix on a 404, clear error on a 200 with HTML). Used by `TAiPrompts`, `TAiSkill` and `TAiSkills` |
| `uMakerAi.Telemetry.pas` | `TAiTelemetry` — opt-in OpenTelemetry tracing (OTLP/HTTP JSON, GenAI semconv); no-op-safe helpers `AiSpanStart`/`AiSpanEnd`/`AiSpanAttr` used by Chat, Tools and MCP |
| `uMakerAi.Evals.pas` | `TAiEvalRunner` — evals with fluent cases (`ExpectContains`/`Regex`/`Equals`/`MinLength`/`MaxLength`/`Judge`) over a generic target `function(Input): string`; `ToText`/`ToJSON` report; optional LLM-as-judge via the `Judge` property; `eval.case` span per case |
| `uMakerAi.Version.inc` | Version constants and feature flags - included via `{$I}` directive |
| `uMakerAi.Utils.*.pas` | Utility helpers (CodeExtractor, PcmToWav, System) |

## Key Types and Patterns

### File Category System
```pascal
TAiFileCategory = (Tfc_Text, Tfc_Image, Tfc_Audio, Tfc_Video, Tfc_Pdf, ...)
TAiChatMediaSupport = (Tcm_Text, Tcm_Image, Tcm_Audio, Tcm_Video, Tcm_Pdf, ...)
```
`TAiFileCategory` represents physical file types. `TAiChatMediaSupport` represents model capabilities.

### Chat State Machine
```pascal
TAiChatState = (acsIdle, acsConnecting, acsCreated, acsReasoning, acsWriting,
                acsToolCalling, acsToolExecuting, acsFinished, acsAborted, acsError)
```
All chat implementations follow this state flow. Use `OnStateChange` event to track transitions.

### TAiChat Abstract Methods
When creating a new LLM driver, these class methods must be implemented:
```pascal
class function GetDriverName: string; virtual; abstract;
class procedure RegisterDefaultParams(Params: TStrings); virtual; abstract;
class function CreateInstance(Sender: TComponent): TAiChat; virtual; abstract;
```

### Tool Context Interface
`IAiToolContext` allows tools to report events back to the chat without circular dependencies:
```pascal
IAiToolContext = interface
  procedure DoData(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
  procedure DoDataEnd(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
  procedure DoError(const ErrorMsg: string; E: Exception);
  procedure DoStateChange(State: TAiChatState; const Description: string = '');
  function GetAsynchronous: Boolean;
end;
```

## Delphi Version Compatibility

The code uses conditional compilation for Delphi version differences:
```pascal
{$IF CompilerVersion >= 34}  // Delphi 10.3 Rio+
  Client.SynchronizeEvents := False;
{$IFEND}

{$IF CompilerVersion < 35}
uses uJSONHelper;  // JSON helper for older Delphi versions
{$ENDIF}
```

## Thread Safety

- `TAiChatMessage` uses `TCriticalSection` (`FLock`) for thread-safe media file operations
- Tool base classes use `TThread.Queue` for reporting events to the main thread
- Streaming responses are handled asynchronously via `OnReceiveData` event

## Helper Functions

From `uMakerAi.Core.pas`:
- `GetContentCategory(FileExtension)` - Returns `TAiFileCategory` from file extension
- `GetMimeTypeFromFileName(FileExtension)` - Returns MIME type string
- `GetFileExtensionFromMimeType(MimeType)` - Reverse lookup
- `StreamToBase64(Stream)` - Converts TMemoryStream to Base64 string

## SmartDispatch: dedicated classifier (sep 27/2026)

`TAiChatTools.DispatchClassifier: TAiDispatchClassifierBase` (interface `IAiDispatchClassifier` in `uMakerAi.Chat.Tools`). If assigned, `InternalRunSmartDispatch` asks it for the tag before pass 1 by LLM (`ClassifySmartDispatch`); only tags whose tool is assigned are accepted (`SmartDispatchTags`). Tool tag → `RunSmartDispatchTool` with the **original prompt** (the classifier does not rewrite). `CHAT` → normal `InternalRunCompletions`, **with history** (the LLM pass responds in an isolated two-message context). `''` or exception → pass 1 by LLM as usual; the exception does not trigger `OnError`, only `DoStateChange`. Implementation with Jev: `TAiJevDispatchClassifier` (`Source/Tools/uMakerAi.Jev.SmartDispatch.pas`).

## Evals: calibrated judge (sep 27/2026)

`TAiEvalRunner.Scorer: TAiEvalScorerBase` + check `ExpectScore('criterio', min = 0.5)` (`ekScore`, added at the end of the enum so as not to move ordinals). `Score(criterio, input, salida)` returns the 0..1 probability that the output meets the criterion; the check passes if it is ≥ `min`. A scorer error fails the check with `scorer error: …` (does not raise). Without `Scorer` assigned, the check fails with an explicit reason. Implementation with Jev: `TAiJevEvalScorer` (`Source/Tools/uMakerAi.Jev.Evals.pas`).

## Input guardrail (sep 27/2026)

`TAiChatTools.PromptGuard: TAiPromptGuardBase` (in `uMakerAi.Chat.Tools`, with the record `TAiPromptVerdict`: `Allowed`, `Category`, `Score`, `Reason`). `TAiChat.Run` consults it for each `user` message **after** the regex sanitizer (`SanitizerActive`) and before memory and the LLM. If it blocks, it fires `OnPromptGuard(Sender, Verdict, var Action)` with `Action = saBlock` by default (same `TAiSanitizeAction` as the sanitizer: `saAllow` continues, `saAllowWrapped` wraps the prompt with `TSanitizerPipeline`); with `saBlock` it calls `DoError` and `Run` returns `''` without touching the network. If `CheckPrompt` raises, `BlockOnError` (default `True`) decides. `TAiChatConnection` propagates `OnPromptGuard` as `OnSanitize`. Implementation with Jev: `TAiJevPromptGuard` (`Source/Tools/uMakerAi.Jev.PromptGuard.pas`).

## Streaming parser: two fixes (sep 28/2026)

- **Duplicate text in `OnReceiveDataEnd` (async).** The `[DONE]` builds a synthetic message with `content = FLastContent` (already accumulated by the deltas) and `ParseChat` added that content to `FLastContent` again: the event received `'Listo'#13#10'Listo'`. It affected all the drivers of the common parser (verified live: Groq, DeepSeek; after the fix Kimi, Grok and Mistral also deliver it only once). Fix: `FLastContent` is restored after `ParseChat` **only if there was content** (without content, `ParseChat` uses the reasoning as the response and that is preserved). `TAiDeepSeekChat` has a copy of `ProcessLine` and carries the same fix. `TAiOpenChat` does not go through here (it overrides `OnInternalReceiveData` for the Responses API).
- **`executed_tools` in the delta.** Groq `code_interpreter` with `gpt-oss` sends `executed_tools` inside `choices[0].delta`, in two chunks per tool with the same `index` (first `arguments`, then `arguments` + `output`); the parser only read the field at the root (format of the retired `groq/compound`). `MergeStreamExecutedTools` combines them by `index` in `FLastExecutedToolsJSON` and the `[DONE]` delivers them to `ProcessExecutedTools`, like the sync path.

## Freeing a chat with an async request in flight (sep 28/2026)

`OnReceiveDataEnd` exits on the last chunk, **before** the HTTP client closes the request. The closure (`OnRequestCompletedEvent`, on the HTTP thread because `SynchronizeEvents := False`) frees `FCurrentPostStream`; if the integrator freed the chat right after the final event — the natural thing to do — the destructor freed the same stream in parallel: **intermittent `Invalid pointer operation`**, which also reached `OnError`. Fix: the constructor no longer wires the virtual methods directly to `TNetHTTPClient` but instead a fixed layer (`ClientReceiveData`, `ClientRequestCompleted/Error/Exception`) that marks the request as in flight (`FRequestDone: TEvent`, turned off when data arrives in async mode and turned on when closing) and calls the virtuals — it works for all drivers without touching them. The destructor (`WaitPendingRequest`) waits for that closure (max. 15 s; pumps `CheckSynchronize` if it runs on the main thread, for Delphi < 10.4), and beforehand disconnects the user events and sets `FAbort`. With no request in flight it waits for nothing. **A driver must not reassign `FClient.OnReceiveData`/`OnRequest*`** (Claude did so redundantly and it was removed). Suite: `chat.async.free-waits-request` (deterministic, closure from another thread at 300 ms; fails without the fix).

## ParseJsonTranscript outside cmTranscription (sep 28/2026)

In the Phase 1 bridge of `RunNew` (text model with `SessionCaps` `[cap_Audio]` in `cmConversation`) the transcription is **input** for the model. `ParseJsonTranscript` also wrote it to `ResMsg` and fired `OnReceiveDataEnd` with the raw text before the real response (Cohere, Groq, Mistral, OpenAI). Now, outside `cmTranscription`, it only fills `MediaFile.Transcription`, `Procesado` and the token counters. Note: those drivers transcribe with the session's `Model`, so the bridge only applied with manual configurations (transcription model with `ModelCaps []`). Suite: `chat.transcript.bridge-mode`.

## tool_choice forced only on the first call (sep 29/2026)

`TAiChat.Tool_choice` is read with `GetTool_choice`: if the value forces a tool (`required`/`any` or a specific function) and the last message in the history is a tool result (`Role = 'tool'` or `ToolCallId`), it returns `'auto'`. Previously it was resent on every round and the model was forced to call another tool: with `claude-sonnet-5` and `required`, **231 requests in an endless loop**. All drivers read the property (the base used the `FTool_choice` field and it was changed), so the fix is a single one. `auto` and `none` do not change. Suite: `chat.toolchoice.followup`; tested live with Claude (sonnet-5, sonnet-5-5, opus-5-5) and OpenAI (`gpt-6-sol`).

## Empty Model = default model with its parameters (sep 28/2026)

`TAiChatFactory.GetDriverParams` (and the embeddings one) builds the parameters in three levels: driver defaults (`RegisterDefaultParams`, includes `Model=<default>`), the driver's in the catalog, and the **model's**. The third was only consulted if `ModelName` had a value, so a connection with `DriverName` and no `Model` used the default model **without** its caps, `Max_Tokens` or `ThinkingLevel`. Measured: 9 of 15 drivers gave a different chat (Qwen without vision, Groq without reasoning/interpreter and with `Max_Tokens` 8192 instead of 65536, Gemini without audio/PDF/search, Grok, Kimi, Mistral, MakerAi, DeepSeek, GLM). Now, without `ModelName`, level 3 uses the `Model` resolved by levels 1 and 2. `TAiChatConnection.Model` remains empty (it does not change what is saved in the DFM). **Behavior change:** anyone who used only `DriverName` now receives the catalog configuration of their default model — the same one they obtained by assigning it explicitly. Suite: `conn.empty-model-default-params` (invariant for all registered drivers).

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.