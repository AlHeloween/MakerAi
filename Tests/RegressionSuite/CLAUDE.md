# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**MakerAI regression suite** — the framework's safety net. It validates critical subsystems **in-process**, without external services, without API keys, and without depending on compiled demos: it starts its own MCP and A2A servers and a fake PPM registry on high ports (18790-18794) and shuts them down when finished.

It is built on `TAiEvalRunner` (`Source/Core/uMakerAi.Evals.pas`), so it is both the test suite and the canonical example of using the evals component.

## Build & Run

```bash
msbuild MakerAiRegressionSuite.dproj /p:Config=Release /p:Platform=Win64
```

```bash
# Run (exit code 0 = all green, 1 = failures, 2 = unhandled error)
Win64\Release\MakerAiRegressionSuite.exe

# JSON report for CI
Win64\Release\MakerAiRegressionSuite.exe --json report.json

# With OpenTelemetry traces (OTLP collector at localhost:4318)
Win64\Release\MakerAiRegressionSuite.exe --otel
```

Typical duration: ~5 seconds (cases with a URL to a closed port wait for Windows to reject it, ~2 s each).

## Current coverage (117 cases)

| Area | Cases |
|------|-------|
| MCP dual-era | modern negotiation (2026-07-28), fallback to legacy handshake, `tools/list`, `tools/call` |
| MCP leaks | `mcp.initialize.no-leak`: 5 `Initialize` calls against the in-process server do not leave live blocks (measures `GetMemoryManagerState`). Covers the client leak (`tools/list` response) and the server leak (schema cloned per tool on each `tools/list`); fails if either is missing |
| MCP MRTR | retry with `accept`, elicitation message received, no handler → explicit error |
| Agents | sequential graph with final status and chained output; `lmExpression` with decimal point under a comma-locale |
| SmartDispatch + Jev | `ChatTools.DispatchClassifier` over a real `TAiOpenChat` (URL to a closed port): the tag goes directly to the tool without going through the LLM; `TAiJevDispatchClassifier` only offers the received tags, respects `MinConfidence`, and does not query Jev if only CHAT remains |
| Input guardrail | `ChatTools.PromptGuard` over a real `TAiOpenChat` (URL to a closed port, SmartDispatch to a fake tool): blocks without touching the network, allows, `OnPromptGuard` overrides the block, guard down with `BlockOnError` closed/open; `TAiJevPromptGuard` prioritizes safety over `out_of_scope` and only asks about scope with `Scope` |
| Guardrails + Jev | `TAiGuardrails.Classifier` with `TAiJevGuardrailClassifier`: high risk blocks with a reason, low risk allows, what the lists already block does not reach Jev, `BlockOnError` closed/open; permission categories: blocks a forbidden category even if it is not the chosen one, risk takes precedence, `ToolDescriptions` travels in the state, `OnCategorized` overrides |
| Bulk labeling | `TAiJevBatchLabeler`: label/confidence per row, a row with an error does not stop the batch, doubtful rows, tokens summed, validation of `Questions` and `LabelQuestion` before calling, JSON states as-is, `Cancel` from `OnProgress` |
| Model router | `TAiJevModelRouter`: minimum by code, minimum for sensitive, +1 per doubt, the cheapest tier that reaches it and the most capable if none does; migration between providers (only text user/assistant), `ConnectionParams` and `Tier.Params` applied after the model, same provider keeps the chat — over a real `TAiChatConnection` without network |
| Evals + Jev | `TAiEvalRunner.Scorer` with `TAiJevEvalScorer`: `ExpectScore` passes, fails with the score in the reason, a Jev error fails the check without an exception, the input travels in the state |
| RAG + Jev | `TAiRAGVector.Reranker` with `TAiJevRAGReranker` in the real VQL pipeline (fake embeddings via `TAiEmbeddingsCore.OnGetEmbedding`): orders by evidence and discards the injected passage; reranker down → falls back to cosine without an exception |
| Agents + Jev | `TAiJevRouterTool` in a real graph: chosen route, low confidence → `NextNo`, Jev down (401) → `NextNo` without breaking the graph, and the `<Node>.jev.*` keys of the blackboard |
| A2A 1.0 | Agent Card, `SendMessage` → `TASK_STATE_COMPLETED`, federation (local graph → remote agent) |
| A2A orchestration | pool with 3 simultaneous tasks, human-in-the-loop with resume by `taskId`, federated human-in-the-loop (suspension of the local node), `blocking=false` + `GetTask`, tolerance of state literals, cancel terminal task → `-32002` |
| Guardrails | blocklist with wildcard, strict allowlist, forbidden pattern in arguments, programmatic veto, real integration (the blocked tool is NOT executed) |
| A2A authorization | public base card, RPC without key -> 401, key with different casing -> 401 |
| A2A streaming | resume a task in `input-required` with `SendStreamingMessage` (raw SSE) |
| A2A Agent Card | declared skills (with tags) and `run-graph` skill by default when there are none |
| RAG | search with `Options` set to nil on the `.mkai` driver (AV regression due to `IfThen`) |
| Memory | `TAiMemory` isolates namespaces also in operations by Id (issue #127): from another namespace, `Get` does not see the memory and `Update`/`Link`/`Delete` do not touch it; `ImportFromJSON` ignores the JSON's `namespace` and writes to the active one (fails without the fix) |
| Skills (format) | common SKILL.md parser (`uMakerAi.Skills.Format`): quotes, `#` comment, scalar split across two lines, `- x` and inline `[a, "b"]` lists, `>` block, Markdown without frontmatter; folder `<dir>/<name>/SKILL.md` with the folder name as fallback. Fake PPM registry (port 18794): automatic `skill-` prefix, highest version by semver excluding retired ones (1.10.0 beats 1.2.0), `TAiPrompts.LoadSkillFromPPM` through the same path; clear errors for a nonexistent package, one of another type, or a 200 with HTML, and `TAiPrompts` returns nil without an exception |
| Skills (TAiPrompts) | `LoadSkillsFromFolder` loads two skills and ignores the folder without SKILL.md; name from the frontmatter or the folder; `SkillDescription`; `ApplySkill` replaces and adds on a `TStrings`; nonexistent name → `False` |
| Skills (TAiSkills) | registration in `TAiFunctions` (off without skills, `enum` only with enabled ones, catalog in the description, no `read_skill_file` if there are no folders); `use_skill` via `DoCallFunction` (delivers with origin, unknown name with the list, veto, `OnSkillLoaded`); confined `read_skill_file` (reads and lists supporting files, rejects `..` in two forms, absolute paths, binaries, large files, nonexistent ones, and skills without a folder); lifecycle (on release it removes its functions; releasing `TAiFunctions` first does not leave dangling references) |
| Skills (agents) | `TLLMNode.ResolveConfig`: seven node/skill combinations (no skill → Claude; driver/model/key from the skill with an empty node; the node changes driver and does not inherit another's model; model only from the node; SKILL.md without driver; `driver:` from the frontmatter is applied and `apikey:` is not); `SystemPrompt` skill + node; `ConfigureChat` over a real `TAiChatConnection` leaves driver, model, and key resolved also when changing driver (fails with the old order); `TAiSkill` from JSON, folder with SKILL.md, and fake registry |
| Streaming | `OnReceiveDataEnd` without duplicated text when closing the stream (simulated SSE over `TAiGroqChat`; fails without the fix) and Groq's `executed_tools` combined by `index` from the delta (chunks from a real `gpt-oss-20b` SSE) |
| tool_choice | forced `Tool_choice` (`required` or a function) is read as `auto` in the round that returns tool results; `auto`/`none` do not change (previously: endless loop, 231 requests with `claude-sonnet-5`) |
| OpenAI (request) | default `gpt-6-sol` in the driver and in `TAiChatConnection`; GPT-6 does not take effort `minimal` (→ `low`), 5.x does; `tlMax` → `max`; `TAiMakerAiChat` with `mk-gpt-oss-20b` |
| Claude (request) | September 2026 generation (sonnet-5-5/opus-5-5): forcing tool → `auto`; `claude-sonnet-5` sends `any` only on the first call; effort `max`/`xhigh` (not in 4.6 → `high`)/`minimal` → `low`; alias of the retired `claude-opus-4-1` → `claude-opus-5-5` |
| Gemini (request) | defaults of the driver, `TAiChatConnection`, and the tools (TTS, transcription, search) at `gemini-3.8-flash(-tts)`; sampling omitted by version (3.6/3.7/3.8 no, 3.0 yes); `tlMinimal` → `LOW` and `tlMax` → `HIGH`; alias of the retired ones (`gemini-3-pro-preview`, `imagen-4.0-*`, `aa_gemini-3-pro-fast`) — without network or key |
| Qwen (request) | `enable_thinking` always present (false without `cap_Reasoning`), `thinking_budget` by `ThinkingLevel`, absent in `qwq-*`, false in synchronous open weights; `stream_options.include_usage` only in streaming; input audio rewritten as a data URI (fails without the fix); `TAiQwenRAGReranker` with fake transport: batches, mapping by `index`, `instruct`, trimming; image request: generates without attachments, edits with 1-3 (editing model, data URI, without forcing size), fails with 4 or with `z-image-turbo`; video request: t2v/i2v/kf2v depending on the attached images, `-t2v` → `-i2v`, 720p by `size` or `resolution` depending on family, types of `VideoParams.Params`; `qwen-mt` translation: a single user message with `translation_options` (languages, domain, glossary) and accumulated plus/turbo streaming converted to increments with a split SSE line (fails without the fix); `TAiQwenVoices` with fake transport (clone, design with fallback and preview, list, delete) and TTS model chosen by the voice prefix |
| Connection | media subparameters (`VideoParams`, `TtsParams`, `ImageParams`) edited after creating the chat reach the driver in `AddMessageAndRun` (URL to a closed port; fails without the fix) |
| Parameter registry | with an empty `Model`, each registered driver receives the same parameters as with its default model; Qwen connection without `Model` with `cap_Image`, Groq with `Max_Tokens` 65536 (fails without the fix) |
| Realtime: connector | `DriverParams` applied by RTTI when creating the driver (text), when changing driver without false errors, Grok with enum and list (`Keyterms` with `|`), unknown key reported by `OnError` on connect (`Url` to a closed port, without network) |
| Realtime Qwen | server events without network: the three transcription formats (accumulated stash, text+stash with rewriting, incremental delta) come out as deltas; assistant text and audio, close, and error; `session.update` of the three drivers (formats, manual VAD → null, language, translation voice) and registration in the factory and in `TAiRealtimeConnection`; `TAiQwenRealtimeTTS`: `session.update` (mode, language, voice, instructions), realtime model chosen by the prefix of its own voice, and events (ready only once, audio, responses, end, error) |
| Chat lifecycle | releasing the chat with an asynchronous request in flight waits for the HTTP client to close it (simulated close from another thread; fails without the fix) and without a request it releases instantly; `ParseJsonTranscript` in the Phase 1 bridge does not write the response or fire events (in `cmTranscription` it does); catalog and user `Voice`/`Voice_Format` reach `TtsParams` |
| Chat / tool results | OpenAI-compatible serialization: parallel tool calls with image → a single synthetic `user` after the group, model without `cap_Image` → transcription without media, transcription not duplicated, inline text attachment |
| GPT-Live | `TAiOpenAiLiveChat` with `TLiveProbe` (captures what is sent, simulated `NowMs` clock, no network): `session.start` (model in the session, delegation to Responses with tools/tool_choice/reasoning, `DelegateChat` → `client`, factory, and connector); events (deltas, audio, usage, close, error); turns with the timeline (late fragment, close due to inactivity), the **real trace** of overlapping speech (fails with grouping by arrival order), and a long story with bursty transcripts (the audio voice keeps the turn; a turn closed due to inactivity is resumed if the model continues); functions via `response.event` with a single `response.create` even if the response ends before the function; `client` delegation (context without repeating what was already sent, fragments ≤ 400 bytes, `delegation_id` null with Responses, notice if nobody handles it); real `DelegateChat` against a closed port |
| OpenAI Audio | `TAiOpenAiAudio` with `TFakeOpenAiAudio` (replaces `PostMultipart`, no network): format degraded to json is interpreted as json and left in `Warning` (fails without the fix: `Text` with the raw JSON); timestamps and logprobs ignored with a warning and not sent; `languages[]`/`keywords[]` without warnings; `whisper-1` with srt + timestamps stays the same and warns about deprecation; `TranslateToEnglish` (whisper-1 only) warns about deprecation; `audio.defaults`: v3.9 defaults (`gpt-transcribe`, `gpt-4o-mini-tts`) in `TAiOpenAiAudio` and `TAiOpenAiSpeechTool`, with the constructor value equal to the published `default` (RTTI) |
| Evals | runner self-test (PASS/FAIL count) |
| Jev: usage | `Usage` and `OnUsage` in `TAiJev` (one event per call) and in PromptGuard, Dispatch, Guardrail, Eval, ModelRouter, RAG, and Batch (one per operation); reranker in parallel with a fake `TAiJev` per passage → a single event with the exact total and on the caller's thread; `ResetUsage`; configurable price |
| Jev on System One (Ollama) servers | `jev.systemone.local`: images in the request (`images`, base64 without line breaks that decodes to the original bytes, PNG and JPEG recognized by their bytes even if the file has no extension), an "image" that is not PNG/JPEG/WebP rejected before the network, the TypeSafe price is not charged with a local `Url` unless there is a custom price, and `JevAdapterInputPrice` takes the `Url` from the `Jev` being used |
| Jev (TypeSafe) | request shape (Choice with option without description → `null`, Score, Noul with partial criteria), parsing of the three responses, retry on 429/529, retries exhausted, local validation without network, 401 without retry — with `TFakeJev` (without network or API key) |

## Structure

| File | Contents |
|---------|-----------|
| `MakerAiRegressionSuite.dpr` | Main program: CLI (`--json`, `--otel`), execution, and exit code |
| `uRegression.Suites.pas` | Case definitions (`DefineCases`) and the *dispatcher* that runs each scenario against the real components |
| `uRegression.Fixtures.pas` | `TFakeJev` (TAiJev with queued HTTP responses), `TFakeDispatchClassifier` and `TFakeImageTool` (SmartDispatch without network), `TPassageFakeJev` (responds according to the passage), `FakeEmbedding`, `TFakePromptGuard`, `TFakeOpenAiAudio` (captured multipart, `FieldValues`), and the `ChatError` / `PromptGuardAllow` / `JevCategorizedAllow` / `BatchCancelAfterFirst` handlers, test MCP tools (`echo_upper`, `confirm_op` with MRTR), a "legacy-only" MCP server (responds `-32601` to `server/discover`), and `of object` handlers (includes `NodeSuspendOnce` for human-in-the-loop and `AcquireManager` as the factory for the A2A pool) |

A2A orchestration scenarios live in `RunA2AFlowScenario`, separate from the basic `a2a:` block, because each one builds its own topology (pool, suspension, non-blocking).

## How to add a case

1. In `uRegression.Suites.pas` → `DefineCases`, declare the case with its scenario and expectations:
   ```pascal
   FRunner.AddCase('area.subarea.detail')
     .Input('area:escenario')
     .ExpectContains('...');
   ```
2. In the corresponding `Run<Area>Scenario`, implement the scenario returning a string with the observable result.
3. If the scenario needs a new tool or server, add it to `uRegression.Fixtures.pas`.

Conventions: case names in `area.subarea.detail`; scenarios return compact strings (`'state|output'`) to be able to assert with `ExpectEquals`.

## Notes

- Framework events are `of object` (no lambdas): handlers live in `TFixtureHandlers`.
- Each case emits an `eval.case <name>` span when run with `--otel`, useful for viewing the full suite in Jaeger/Langfuse.
- The suite does not require API keys. If cases that call real providers are added in the future, they must be skipped when the corresponding environment variable is missing.

## Navigation

> See [../../CLAUDE.md](../../CLAUDE.md) for project overview.