# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tools Module Overview

The `Source/Tools/` directory contains capability components that extend LLM functionality beyond basic chat. These are standalone components that can be attached to chat instances to enable function calling, media generation, shell execution, and computer automation.

## Unit Categories

### Function Calling System
- `uMakerAi.Tools.Functions.pas` - Core function calling infrastructure
  - `TAiFunctions` - Component for defining callable functions with parameters
  - `TFunctionActionItem` - Individual function definition with `FunctionName`, `Description`, `Parameters`
  - `TFunctionParamsItem` - Parameter definition with `ParamType` (ptString, ptInteger, ptBoolean, etc.)
  - `TMCPClientItem` - MCP server connection management within functions

### Guardrails (security policy)
- `uMakerAi.Guardrails.pas` — `TAiGuardrails`: assigned to `TAiFunctions.Guardrails` and consulted in `DoCallFunction` **before** executing any tool (local, MCP or AutoMCP)
  - Evaluation order: `Enabled` → `AllowedTools` (strict whitelist, `TMask` wildcards) → `BlockedTools` → `BlockedArgPatterns` (forbidden substrings in the arguments JSON, case-insensitive) → `Classifier` (semantic judgment, only for what the lists let through; if it raises an exception it **blocks**) → `OnCheckToolCall` (final programmatic veto/permission)
  - `Classifier: TAiGuardrailClassifierBase` — abstract base class with `CheckToolCall(tool, args, out reason): Boolean`. Jev implementation: `TAiJevGuardrailClassifier`
  - A block does NOT execute the tool: it sets `ToolCall.Response` to `{"error":"Blocked by guardrails: ..."}` so the LLM can re-plan, fires `OnBlocked` (audit), increments `BlockedCount` and marks the span with `guardrail.blocked`

### Jev (TypeSafe AI) — calibrated decisions
- `uMakerAi.Jev.pas` — `TAiJev`: client for `POST https://api.typesafe.ai/v1/systemone`. **It is not a chat driver** (Jev does not generate text): it receives a `state` (text or JSON) and typed questions, and returns calibrated probabilities + confidence
  - Questions in `TAiJevQuestions` (`TCollection`, editable at design time): `AddChoice` (options `'key=description'`, 2 to 255), `AddScore` (ordered levels, 2 to 10), `AddNoul` (yes/no, optional criteria `true=`/`false=`). They are validated **before** going to the network
  - `Ask(state, questions)` → `TAiJevResult` (the caller frees it); `R['id'].Choice/.Score/.Noul/.Confidence/.Probability(op)/.Top(n)`. Shortcuts `Choose` and `Noul` for a single question
  - Multiple questions travel in **one** call: prefer a complete `TAiJevQuestions` over separate calls
  - `Model` defaults to `jev-1.13.0` (not `jev-latest`: thresholds are calibrated against a version). `ApiKey` defaults to `@TYPESAFE_API_KEY`
  - Retries 429/503/529 with exponential backoff (`MaxRetries`, `RetryDelay`); other errors raise `EAiJevError` (with `StatusCode`), fill `LastError` and fire `OnError`. Telemetry span `jev.ask`
  - Sends the body in explicit UTF-8: with the default encoding the API returns 400 on accents or `¿`
  - `DoPost` is virtual: the regression suite replaces it (`TFakeJev`) to test without the network
  - Jev does not do arithmetic, does not count, and does not reliably compare dates: that goes in code. The confidence of the same input varies by a few points between calls; leave margin in the thresholds
  - Demo: `Demos/084-JevRouter`
- `uMakerAi.Jev.SmartDispatch.pas` — `TAiJevDispatchClassifier` for `ChatTools.DispatchClassifier`: replaces pass 1 of `cmSmartDispatch` (an LLM that classifies) with a Choice to Jev over the tags with an assigned tool. If only CHAT remains it does not call Jev. With confidence < `MinConfidence` (0.6) it returns `''` and the chat uses the LLM as before. Calibrated tag descriptions (15/15 in Spanish and English); `TagDescriptions` (`TAG=description`) replaces them
- `uMakerAi.Jev.Guardrails.pas` — `TAiJevGuardrailClassifier` for `TAiGuardrails.Classifier`: Noul over `{tool, arguments}` with `Policy` (empty = `DEFAULT_POLICY`: deleting/overwriting data, exposing credentials or private data, moving money, destructive commands); blocks if P ≥ `BlockThreshold` (0.5). `BlockOnError` (default `True`) blocks if Jev does not respond. `LastRisk` stores the last probability. Calibrated: safe ≤ 0.17, dangerous ≥ 0.88 over 13 tool calls
  - **Permission categories (optional):** `Categories` (`key=description`) adds a Choice in the **same call**; it blocks if the probability of any of `BlockedCategories` reaches `CategoryThreshold` (0.5), even if it is not the chosen one. `OnCategorized(tool, args, category, confidence, var Allow, var Reason)` audits or changes the decision; `LastCategory`/`LastCategoryConfidence`. `ToolDescriptions` (`name=description`) adds a description to the state: without it `anular_comprobante` came out `read` (0.83), with it `write` (0.95). Calibrated: 19/20 in 6 categories without descriptions, 20/20 with it
  - **With `Categories` and without `Policy`, `ABUSE_POLICY` is used** (only the abusive) instead of `DEFAULT_POLICY`: the strict policy treats any payment or deletion as risk (a normal `pay_invoice` gave 0.88) and overrode the categories. `ABUSE_POLICY`: 0 errors in 19 cases, dangerous ≥ 0.64, legitimate ≤ 0.35. Without `Categories` the behavior does not change
- `uMakerAi.Jev.Evals.pas` — `TAiJevEvalScorer` for `TAiEvalRunner.Scorer`: answers `ExpectScore('criterion', min)` with a Noul over `{input, response}` ("Does `response` satisfy this criterion: …?"). Calibrated 10/10: passing ≥ 0.97, failing ≤ 0.02. `LastScore` stores the last probability
- `uMakerAi.Jev