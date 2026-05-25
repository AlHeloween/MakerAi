# Plan: HTTP/2 Protocol + Multistreaming (Parallel SSE) Support

**Date:** 2026-05-21  
**Project:** MakerAI v3.3 (Delphi Pascal)  
**Scope:** Add HTTP/2 transport protocol support to all LLM drivers and the MCP client, plus concurrent parallel streaming (multistreaming) for multi-model or multi-tool scenarios.

---

## Abstract Definition

The MakerAI framework currently uses **Delphi's `TNetHTTPClient`** (WinHTTP backend) in HTTP/1.1 mode for all API communication. Every LLM driver, MCP client transport, and tool component creates temporary `TNetHTTPClient` instances for each request. Streaming is achieved via SSE (Server-Sent Events) over a single TCP connection per request — a one-directional, non-multiplexed stream.

### Current State

| Feature | Status | Limitation |
|---------|--------|------------|
| HTTP protocol | HTTP/1.1 only | No header compression, no multiplexing |
| Streaming | SSE over HTTP/1.1 | One connection per concurrent stream |
| Parallel requests | Sequential per `TAiChat` instance | Must create multiple `TAiChatConnection` components for concurrency |
| Client reuse | New `TNetHTTPClient` per request | Connection pool not utilized |

### Target State

| Feature | Target | Benefit |
|---------|--------|---------|
| HTTP/2 | `THTTPProtocolVersion.HTTP_2_0` with ALPN fallback to HTTP/1.1 | Header compression (HPACK), connection reuse, lower latency |
| Multistreaming | Parallel SSE streams over shared HTTP/2 connection | Concurrent model calls (tool + reasoning + web search in parallel) |
| Connection pool | Singleton pool of pre-warmed `TNetHTTPClient` instances | Eliminates per-request setup overhead |

### Formal Model

Let `C = {c_1, ..., c_n}` be a pool of `n` `TNetHTTPClient` instances, each configured with `ProtocolVersion = HTTP_2_0` and `Asynchronous = True`.

For any LLM request `R_i(model, prompt, stream_callback)`, the dispatcher `D(C)` assigns `R_i → c_j` where `c_j` has the fewest active streams among available clients.

HTTP/2 stream multiplexing allows `m` concurrent streams per connection:
- `streams_per_connection ≤ max_concurrent_streams` (server-negotiated, typically 100-256)
- Each stream `s_k` carries one SSE token stream via `OnReceiveData` callback
- Streams are independent: `cancel(s_k)` does not affect `s_{l≠k}`

**Invariant**: All existing API contracts are preserved — `TAiChat.Run()`, `TAiChat.GetMessages()`, `OnReceiveData` events remain unchanged. The transport layer changes are transparent to consumers.

---

## Structural Diagram

```
                     APPLICATION LAYER
     ┌──────────────────┬──────────────────────────┐
     │  TAiChatConnection│  TAIAgentManager         │
     │  (single model)   │  (multi-node parallel)   │
     └────────┬─────────┴────────────┬─────────────┘
              │                      │
              ▼                      ▼
     ┌───────────────────────────────────────────────┐
     │        NEW: THTTP2ConnectionPool              │
     │  ┌──────────┐ ┌──────────┐ ┌──────────┐      │
     │  │ Client_1 │ │ Client_2 │ │ Client_N │      │
     │  │ (HTTP/2) │ │ (HTTP/2) │ │ (HTTP/2) │      │
     │  └────┬─────┘ └────┬─────┘ └────┬─────┘      │
     │       │streams     │streams     │streams      │
     │    s₁ s₂ s₃     s₄ s₅ s₆     s₇ s₈ ...     │
     └───────┼───────────┼───────────┼──────────────┘
             │           │           │
     ┌───────v───────────v───────────v──────────────┐
     │  SSE Stream Manager (per-client)             │
     │  - Dispatches OnReceiveData to correct       │
     │    callback via stream ID mapping            │
     │  - Cancels individual streams                │
     │  - Reports stream stats (tokens/s, latency)  │
     └──────────────────────────────────────────────┘
             │           │           │
             ▼           ▼           ▼
     ┌──────────────────────────────────────────────┐
     │  LLM APIs (unchanged)                        │
     │  OpenAI / Claude / Gemini / Ollama / ...     │
     │  (negotiate HTTP/2 via ALPN)                 │
     └──────────────────────────────────────────────┘
```

---

## Input/Output Parameters

### Input
| Parameter | Type | Description |
|-----------|------|-------------|
| `AProvider` | string | LLM provider name (`'OpenAI'`, `'Claude'`, etc.) |
| `AModel` | string | Model identifier |
| `APrompt` | string | User prompt text |
| `AMediaFiles` | `TAiMediaFiles` | Optional attached media |
| `AStreamCallback` | `TOnReceiveData` | Per-stream data callback |
| `AParallel` | boolean | Whether to allow concurrent streams (new param) |
| `AMaxConcurrentStreams` | integer | Cap on parallel streams per connection (default 4) |

### Output
| Parameter | Type | Description |
|-----------|------|-------------|
| `StreamHandle` | string (GUID) | Unique stream identifier for tracking/cancellation |
| `OnStreamComplete` | event | Fires when stream closes (success or error) |
| `OnStreamError` | event | Per-stream error (doesn't kill other streams) |

---

## Sub-Tasks

### Sub 1: HTTP/2 Transport Layer
- **File:** `Source/Core/uMakerAi.Chat.pas` (TAiChat base), all 12 Chat drivers
- **Change:** Add `Client.ProtocolVersion := THTTPProtocolVersion.HTTP_2_0` with fallback to HTTP/1.1 on failure
- **Conditional:** `{$IF CompilerVersion >= 35}` (Delphi 11+) — HTTP/2 support requires WinHTTP 2.0
- **Lines affected:** ~40 `TNetHTTPClient.Create()` call sites
- **Verification:** Set a breakpoint on `DoReceiveData` and inspect connection properties

### Sub 2: Connection Pool Manager
- **New file:** `Source/Core/uMakerAi.Http2.Pool.pas`
- **Class:** `THTTP2ConnectionPool` — singleton that maintains pre-warmed clients
- **Key methods:**
  - `AcquireClient(Provider): TNetHTTPClient` — get or create a client for the provider
  - `ReleaseClient(Client)` — return to pool (mark idle, don't destroy)
  - `GetActiveStreamCount(Client): Integer` — current load
  - `Shrink(MaxIdle)` — cleanup idle connections
  - `Stats: THTTP2PoolStats` — diagnostics (total clients, active streams, reuse rate)
- **Config:** Pool size, max idle time, max streams per connection

### Sub 3: Per-Stream Callback Routing
- **Modification:** `TAiChat` — add `FActiveStreams: TDictionary<string, TStreamContext>`
- **New type:** `TStreamContext` — bundles stream GUID, OnReceiveData callback, OnComplete callback, start time, token count
- **Flow:** When `DoReceiveData` fires for stream `s_k`, lookup `TStreamContext` by stream ID and route to correct callback
- **Cancel:** `TAiChat.CancelStream(StreamHandle)` — abort specific stream without closing others

### Sub 4: TAiChat API Extensions
- **New methods on `TAiChat`:**
  - `RunParallel(Prompts: TArray<TPromptRequest>; Callbacks: TArray<TOnReceiveData>): TArray<string>` — returns array of StreamHandles
  - `CancelStream(StreamHandle: string): Boolean`
  - `GetStreamStatus(StreamHandle: string): TStreamStatus` — tokens received, elapsed, isActive
- **New published property:**
  - `MaxParallelStreams: Integer` (default 4)
- **Event:**
  - `OnStreamCompleted(StreamHandle: string; Msg: TAiChatMessage)` — per-stream completion

### Sub 5: Agent Integration
- **File:** `Source/Agents/uMakerAi.Agents.Node.LLM.pas`
- **Change:** TLLMNode uses `RunParallel` when its tool registry has multiple independent tools
- **Benefit:** ReAct loop can call 3 tools simultaneously (e.g., web search + shell + vision) instead of sequentially
- **File:** `Source/Agents/uMakerAi.Agents.pas`
- **Change:** `TAIAgentManager` — set `MaxConcurrentTasks` to align with HTTP/2 stream limits

### Sub 6: MCP Client HTTP/2 Upgrade
- **File:** `Source/MCPClient/uMakerAi.MCPClient.Core.pas`
- **Change:** `TMCPClientHTTP` and `TMCPClientSSE` — use pooled HTTP/2 clients
- **Benefit:** MCP server calls (tools/list, tools/call) multiplexed over shared connection

### Sub 7: Registration in Initializations.pas
- **File:** `Source/Chat/uMakerAi.Chat.Initializations.pas`
- **Add per-provider config:** `MaxParallelStreams` and `Http2Enabled` parameters
- **Example:**
  ```pascal
  TAiChatFactory.Instance.RegisterUserParam('OpenAI', 'Http2Enabled', 'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAI', 'MaxParallelStreams', '8');
  ```

### Sub 8: Tests
- **New test:** `tests/TestHttp2Connection.dpr` — DUnit project
- **Cases:**
  1. Single HTTP/2 request succeeds (verify ProtocolVersion = HTTP_2_0)
  2. Fallback to HTTP/1.1 when server doesn't support HTTP/2 (verify graceful degradation)
  3. Two parallel streams on same client → both receive independent OnReceiveData callbacks
  4. Cancel stream #1 → stream #2 continues unaffected
  5. Pool exhaustion → new request blocks until client freed (or creates overflow client)
  6. Multi-model parallel: Claude (reasoning) + Gemini (vision) + OpenAI (text) simultaneously

---

## Implementation Approach

### Phase 1: Transport (Sub 1, 2)
- Enable HTTP/2 on all `TNetHTTPClient` instances with compile-time guard
- Build pool manager
- No consumer API changes — transparent upgrade

### Phase 2: Multistreaming (Sub 3, 4)
- Add per-stream routing infrastructure
- Add `RunParallel` and `CancelStream` APIs
- Backward-compatible: `Run()` still works as before

### Phase 3: Integration (Sub 5, 6, 7)
- Wire Agents and MCP client into pooled HTTP/2
- Add provider-specific HTTP/2 config

### Phase 4: Verification (Sub 8)
- DUnit tests with mock HTTP/2 server
- Manual integration test with 3 simultaneous provider calls

---

## Test Cases

| # | Test | Expected Result |
|---|------|----------------|
| TC1 | Single request via HTTP/2 | `Client.ProtocolVersion = HTTP_2_0`, response received via SSE |
| TC2 | Server doesn't support HTTP/2 | Graceful fallback to HTTP/1.1, request still succeeds |
| TC3 | Two parallel streams on one client | Stream A callback receives token_a_1, token_a_2, ...; Stream B callback receives token_b_1, token_b_2, ... — independently |
| TC4 | Cancel stream mid-flight | Cancelled stream fires OnStreamComplete with status=aborted; other streams unaffected |
| TC5 | Pool size = 2, request 3 concurrent streams | Third request queues until a client freed, or spawns a timeout exception |
| TC6 | TLLMNode with 3 tools | All 3 tools execute in parallel over 3 streams; blackboard updated atomically |
| TC7 | Delphi < 11 (CompilerVersion < 35) | HTTP/2 code compiles out; everything works as HTTP/1.1 |
| TC8 | Connection pool stats | `Pool.Stats` returns correct: TotalClients, ActiveStreams, StreamsCompleted, AverageLatency |

---

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| HTTP version | HTTP/1.1 | HTTP/2 (with HTTP/1.1 fallback) |
| Header overhead per request | ~1-2 KB (uncompressed) | ~200 bytes (HPACK) |
| Concurrent streams | 1 per `TAiChatConnection` | Up to `MaxParallelStreams` (default 4) per client |
| TNetHTTPClient instances | 1 per request (temporary) | Pooled (1-4 persistent per provider) |
| Agent tool calls | Sequential (ReAct loop: call tool → wait → call next) | Parallel (all independent tools fire simultaneously) |
| MCP client calls | Sequential | Multiplexed over shared HTTP/2 connection |

---

## Files Affected (estimate)

| File | Change | Effort |
|------|--------|--------|
| `Source/Core/uMakerAi.Http2.Pool.pas` | NEW — connection pool manager | Medium |
| `Source/Core/uMakerAi.Chat.pas` | MOD — HTTP/2 client init, RunParallel, stream routing | High |
| `Source/Chat/uMakerAi.Chat.OpenAi.pas` | MOD — HTTP/2 client config | Small |
| `Source/Chat/uMakerAi.Chat.Claude.pas` | MOD — HTTP/2 client config | Small |
| `Source/Chat/uMakerAi.Chat.Gemini.pas` | MOD — HTTP/2 client config | Small |
| `Source/Chat/uMakerAi.Chat.Ollama.pas` | MOD — HTTP/2 client config | Small |
| 8 other Chat drivers | MOD — HTTP/2 client config each | ~1 line each |
| `Source/MCPClient/uMakerAi.MCPClient.Core.pas` | MOD — pooled HTTP/2 | Medium |
| `Source/Agents/uMakerAi.Agents.pas` | MOD — MaxConcurrentStreams alignment | Small |
| `Source/Agents/uMakerAi.Agents.Node.LLM.pas` | MOD — parallel tool execution | Medium |
| `Source/Chat/uMakerAi.Chat.Initializations.pas` | MOD — Http2Enabled + MaxParallelStreams params | Small |
| `Source/Core/uMakerAi.Core.pas` | MOD — TStreamStatus, TPromptRequest types | Small |
| `tests/TestHttp2Connection.dpr` | NEW — DUnit test project | Medium |
