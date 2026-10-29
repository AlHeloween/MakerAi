# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Module Overview

MakerAI MCP Server - A Model Context Protocol implementation for Delphi that exposes AI-callable tools and resources through multiple transport protocols (HTTP, SSE, StdIO, Direct). Part of MakerAI 3.x framework.

## Building

MCPServer is included in the main MakerAI runtime package:

```text
Open: Source/Packages/MakerAI.dpk
Build â†’ Compile
```

**IDE:** RAD Studio (Delphi 11 Alexandria to 13 Florence)

**Required library paths:** `Source/MCPServer`, `Source/Core`, `Source/Tools`, `Source/Utils`

## Testing

No dedicated test framework. Testing via demo projects with HTTP/curl.

**Run demo server:**
```bash
# SSE protocol (default)
AiMCPServerDemo.exe --protocol sse --port 8080 --cors-origins "*"

# HTTP protocol
AiMCPServerDemo.exe --protocol http --port 8080

# Stdio protocol
AiMCPServerDemo.exe --protocol stdio
```

**Test via curl:**
```bash
# List tools
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Call a tool
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"system_info","arguments":{"type":"basic"}},"id":2}'
```

## Architecture

### Class Hierarchy

```text
TAiMCPLogicServer (JSON-RPC engine, tool/resource registry)
    â””â”€â”€ TAiMCPServer (TComponent wrapper)
            â”œâ”€â”€ TAiMCPHttpServer (stateless HTTP JSON-RPC)
            â”œâ”€â”€ TAiMCPSSEHttpServer (bidirectional event streaming)
            â”œâ”€â”€ TAiMCPStdioServer (stdin/stdout for subprocess)
            â””â”€â”€ TAiMCPDirectConnection (in-process, zero network)
```

### Key Interfaces

**IAiMCPTool** - Tool contract:
- `GetName`, `GetDescription`, `GetInputSchema`
- **`GetInputSchema` returns a NEW object on every call and the caller owns it** (`TAiMCPToolBase<T>` generates it from the params class; the Bridge proxy builds it from the `TAiFunctions` item). `Tools_ListTools` adds it to the response without cloning. Until Oct 2026 it was cloned and the original leaked on every `tools/list` (~32 blocks per request on a long-running server; regression case `mcp.initialize.no-leak`). A custom `IAiMCPTool` must not return a cached field
- `Execute(Arguments: TJSONObject; AuthContext: TAiAuthContext): TJSONObject`

**IAiMCPResource** - Resource contract:
- `GetURI`, `GetName`, `GetDescription`, `GetMimeType`, `Read`

### Units

| Unit | Purpose |
|------|---------|
| `uMakerAi.MCPServer.Core.pas` | Core classes, JSON-RPC engine, tool/resource registry (~1,500 lines) |
| `UMakerAi.MCPServer.Http.pas` | HTTP transport with CORS support |
| `UMakerAi.MCPServer.SSE.pas` | Server-Sent Events transport (session-aware) |
| `UMakerAi.MCPServer.Stdio.pas` | Standard I/O transport |
| `UMakerAi.MCPServer.Direct.pas` | In-process direct invocation |
| `uMakerAi.MCPServer.Bridge.pas` | Adapter bridging TAiFunctions to IAiMCPTool |

### Tool Implementation Pattern

```delphi
type
  TMyParams = class
  private
    FPath: string;
    FRecursive: Boolean;
  public
    [AiMCPSchemaDescription('Directory to process')]
    property Path: string read FPath write FPath;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Include subdirectories')]
    property Recursive: Boolean read FRecursive write FRecursive;
  end;

  TMyTool = class(TAiMCPToolBase<TMyParams>)
  protected
    function ExecuteWithParams(const AParams: TMyParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

// Registration
Server.RegisterTool('my_tool',
  function: IAiMCPTool begin Result := TMyTool.Create; end);
```

### Schema Attributes

- `[AiMCPSchemaDescription('...')]` - Parameter description for JSON Schema
- `[AiMCPOptional]` - Mark parameter as optional
- `[AiMCPSchemaEnum(['a', 'b', 'c'])]` - Enum constraint

### Response Builder

```delphi
Result := TAiMCPResponseBuilder.New
  .AddText('Processing complete')
  .AddFile('/path/to/output.pdf')
  .Build;
```

### Protocol Selection

| Protocol | Use Case |
|----------|----------|
| HTTP | Simple clients, stateless interactions, load balancing |
| SSE | Claude Desktop, MakerAI clients, real-time streaming |
| StdIO | Local subprocess, CLI integration |
| Direct | Embedded integration, testing, same-process calls |

### MCP Protocol Methods

| Method | Purpose |
|--------|---------|
| `initialize` | Server capability handshake (legacy, spec <= 2025-11-25) |
| `server/discover` | Version/capability discovery without handshake (spec 2026-07-28) |
| `tools/list` | List available tools |
| `tools/call` | Execute tool with arguments |
| `resources/list` | List available resources |
| `resources/read` | Read resource content |

### Dual-era: spec 2026-07-28 (stateless) + legacy

The server is **dual-era** and decides per request:

- A request with `_meta['io.modelcontextprotocol/protocolVersion']` is served
  **stateless** (spec 2026-07-28): without a session, and the `OnClientConnect`
  vetting (issue #110) is applied **per request** with the identity carried
  in `_meta`.
- An `initialize` selects the legacy semantics with `Mcp-Session-Id` (session
  gate intact).
- All results carry `resultType: "complete"` + `serverInfo` in `_meta`;
  lists (`tools/list`, `resources/*`, `prompts/list`) carry
  `ttlMs`/`cacheScope` (interface `CacheableResult`). Extra fields that
  legacy clients ignore.
- Reserved MCP-range errors: `-32022` UnsupportedProtocolVersion (with
  `data.supported`/`data.requested`) and `-32020` HeaderMismatch — the
  HTTP transport validates `Mcp-Method`/`Mcp-Name` against the body **only
  if they are present** (legacy clients do not send them and are accepted
  the same way).
- Public constants in `uMakerAi.MCPServer.Core.pas`:
  `MCP_PROTOCOL_VERSION_MODERN`, `MCP_META_*`, `MCP_ERROR_*`.

**WATCH OUT (Delphi):** `_meta` keys contain dots
(`io.modelcontextprotocol/...`); read them with exact
`GetValue(name)`, never with `GetValue<T>`/`TryGetValue<T>` (they interpret
the dot as a path).

**stdio rule:** stdout is protocol-exclusive; any server banner/log
must go to stderr (see the fix in demo 031).

### MRTR (Multi Round-Trip Requests, spec 2026-07-28)

A tool can request additional information from the user (elicitation) by
returning an `InputRequiredResult` instead of executing:

- The tool returns `{resultType:'input_required', inputRequests:{id: ElicitRequest...},
  requestState:'<opaque>'}` — `DecorateModernResult` respects the existing `resultType`.
- On retry, the server delivers `params.inputResponses` and `params.requestState`
  to the tool via `AuthContext.InputResponses` (the request's TJSONObject — the tool does NOT
  free it) and `AuthContext.RequestState`.
- `requestState` travels through the client: it is UNTRUSTED input. Protect with
  HMAC/AEAD if it affects authorization; a corrupted value must produce a clean
  rejection, never an internal exception.
- Full example: `Demos/031-MCPServer/uTool.ConfirmDemo.pas` (tool `confirm_demo`).

## Demo Projects

| Demo | Location | Description |
|------|----------|-------------|
| 031-MCPServer | `/Demos/031-MCPServer/` | Multi-protocol showcase with FileAccess, SysInfo, WorldTime tools |
| 035-MCPServerWithTAiFunctions | `/Demos/035-MCPServerWithTAiFunctions/` | TAiFunctions bridge integration |
| 036-MCPServerStdIO_AiFunction | `/Demos/036-MCPServerStdIO_AiFunction/` | StdIO + TAiFunctions |

## Known Issues

- MCP SSE Server is experimental (intermittent connectivity)
- Linux compilation requires manual path adjustments

## Authentication

Two layers in `TAiMCPServer.ValidateRequest` (HTTP and SSE transports enforce it on every endpoint; 401 on failure):

1. **`ApiKey` property** — exact match against `Authorization: Bearer <key>` or `X-API-Key: <key>`.
2. **`OnValidateRequest` event** — custom validation (Basic login/password, JWT, DB lookup); receives the raw auth header + remote IP and fills `TAiAuthContext`.

Both Indy transports assign `OnParseAuthentication` (`VHandled := True`) so Indy does not reject non-Basic `Authorization` schemes (e.g. `Bearer`) with 401 before the request reaches `ValidateRequest`. Working example with hardcoded credentials: `/Demos/037-MCPServerRAG/`.

## Documentation

- `/Docs/Version 3/MCPServer/uMakerAi-MCP.Server.EN.pdf` - English documentation
- `/Docs/Version 3/MCPServer/uMakerAi-MCP.Server.ES.pdf` - Spanish documentation

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.