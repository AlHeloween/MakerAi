# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Module Overview

MCPClient implements the Model Context Protocol (MCP) client for MakerAI, enabling Delphi applications to consume external MCP servers through multiple transport protocols. This module is **dual-era**: supports the stateless MCP Specification (2026-07-28) with automatic fallback to the legacy handshake spec (2025-06-18).

## Architecture

### Class Hierarchy

```text
TMCPClientCustom (Abstract Base)
â”œâ”€â”€ TMCPClientStdIo   - Local subprocess via stdin/stdout pipes
â”œâ”€â”€ TMCPClientHttp    - Remote server via HTTP POST JSON-RPC
â”œâ”€â”€ TMCPClientSSE     - Bidirectional Server-Sent Events streaming
â””â”€â”€ TMCPClientMakerAi - DataSnap-wrapped REST API variant
```

### Transport Types

| Class | Use Case | Key Component |
|-------|----------|---------------|
| `TMCPClientStdIo` | Local MCP server (npx, node) | `TInteractiveProcessInfo` subprocess + read thread |
| `TMCPClientHttp` | Remote HTTP endpoints | `TNetHTTPClient` with retry logic |
| `TMCPClientSSE` | Real-time streaming | Async HTTP + `TThreadedQueue` message buffer |
| `TMCPClientMakerAi` | DataSnap servers | Unwraps nested JSON-RPC from DataSnap array |

### MCP Protocol Flow (dual-era)

The client probes the server's era with `server/discover` (StdIO and HTTP):

**Modern server (spec 2026-07-28, stateless):**
1. `server/discover` responds → `NegotiatedProtocol = '2026-07-28'`
2. No handshake or `notifications/initialized`; each request carries `_meta`
   (`io.modelcontextprotocol/protocolVersion`, `clientInfo`, `clientCapabilities`)
   via `AttachModernMeta`. In HTTP, the headers `MCP-Protocol-Version`,
   `Mcp-Method` and `Mcp-Name` are added.
3. `tools/list` / `tools/call` directly.

**Legacy server (automatic fallback):**
1. `server/discover` returns an error (-32601) or times out → `NegotiatedProtocol = 'legacy'`
2. Send `initialize` request (StdIO: `2024-11-05`, HTTP: `2025-06-18`)
3. Send `notifications/initialized` notification
4. `tools/list` / `tools/call` as usual

Notes:
- `TMCPClientSSE` remains **legacy on purpose** (the HTTP+SSE transport is
  deprecated in spec 2026-07-28).
- An error in the reserved MCP range (-32020..-32099) identifies a modern
  server (`IsModernErrorCode`) — the probe must not fall back to legacy on it.
- `ReadProcessOutput` (StdIO) rescues JSON-RPC embedded in noisy lines
  (`banner{"jsonrpc"...}`) from servers that pollute stdout.
- `_meta` keys contain dots: read them with the exact `GetValue(name)`, never
  path-based variants (`GetValue<T>`).

### MRTR (Multi Round-Trip Requests, spec 2026-07-28)

If the server responds `resultType:'input_required'` to a `tools/call`:

- With `OnInputRequired` assigned (StdIO and HTTP), the client invokes the handler
  with the `inputRequests` map, collects `inputResponses`, and **retries** the
  original request with `inputResponses` + a literal echo of `requestState`
  (max `MCP_MRTR_MAX_ROUNDS` = 3 rounds; new JSON-RPC id per round).
- Assigning `OnInputRequired` declares the `elicitation` capability in
  `_meta.clientCapabilities` (the spec forbids the server from requesting
  undeclared types).
- Without a handler (or if the handler sets `AHandled=False`), the
  `ProcessAndExtractMedia` guard returns a clear error instead of a partial
  result.
- The handler is `of object` (no lambdas); it must not free the received objects.

## Key Patterns

**`ListTools` returns an object the caller owns.** `Initialize` (HTTP and the base used by the other transports) keeps a text copy in `FTools` and frees it; before Oct 2026 it leaked the whole `tools/list` response on every `Initialize` (~228 blocks, seen as `TJSONObject` leaks when closing an app that uses MCP).

**Thread-Safe Messaging**: StdIo and SSE use `TThreadedQueue<TJSONObject>` for async response handling.

**Media Extraction**: `ProcessAndExtractMedia()` extracts base64-encoded binary content from tool responses into `TAiMediaFile` objects.

**Default Parameters**:
```text
Command=npx
Arguments=@
RootDir=<home-path>
Timeout=15000
URL=http://localhost:3001/sse
```

## Integration Points

- **TAiFunctions**: MCP clients registered via `MCPClients` collection property
- **Design-Time Editor**: `TFMCPClientEditor` in `Source/Design/uMCPClientEditor.pas`
- **Package**: Included in `Source/Packages/MakerAI.dpk`

## Dependencies

- `uMakerAi.Utils.System` - Subprocess management (`TUtilsSystem.StartInteractiveProcess`)
- `uMakerAi.Core` - Core types (`TAiMediaFile`, `TToolTransportType`)
- `uJSONHelper` - JSON parsing utilities

## Known Limitations

- SSE transport is experimental (intermittent connectivity per parent CLAUDE.md)
- `FBusy` flag prevents concurrent operations on same client
- Windows-focused subprocess management (`{$IFDEF MSWINDOWS}`)

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.