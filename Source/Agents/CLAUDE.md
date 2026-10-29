# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Module Overview

The Agents module implements a graph-based autonomous agent orchestration framework. It enables building workflows where multiple AI-powered nodes execute in sequence or parallel, with conditional routing and shared state management.

## Unit Structure

| Unit | Purpose |
|------|---------|
| `uMakerAi.Agents.pas` | Core framework: `TAIAgentManager`, `TAIAgentsNode`, `TAIAgentsLink`, `TAIBlackboard` |
| `uMakerAi.Agents.Attributes.pas` | RTTI attributes `TToolAttribute`, `TToolParameterAttribute` and `TSecretAttribute` (`[TSecret]`: the property is never serialized to disk and incoming values from JSON are ignored — credentials only at runtime) |
| `uMakerAi.Agents.EngineRegistry.pas` | Singleton registries for tool discovery (`TEngineRegistry`, `TAgentHandlerRegistry`) |
| `uMakerAi.Agents.GraphBuilder.pas` | `TGraphBuilder` parses JSON graph specs into runtime structures. `StrictValidation` (default True) raises `EAiGraphError` on structural defects (edge to missing node, undeclared port, >4 fanout outputs); set False for the legacy warn-and-drop behavior (fix M-02) |
| `uMakerAi.Agents.DmGenerator.pas` | `TDataModuleGenerator` generates Delphi DataModule code from JSON graphs |
| `uMakerAi.Agents.Node.LLM.pas` | `TLLMNode`: node with an LLM and a ReAct loop over `TAiToolRegistry`. `ResolveConfig` combines node + skill (driver from the node → from the skill → `'Claude'`; the skill's `Model` only if it belongs to the effective driver; the skill's `SystemPrompt` + the node's; `ApiKey` from the node or the skill) and `ConfigureChat` applies it in order Driver → Model → Params (v3.8: `SetDriverName` resets the model, so the old order lost the skill's model and key). `DriverName` is `''` by default since v3.8 |
| `uMakerAi.Agents.Skill.pas` | `TAiSkill`: reusable config for a `TLLMNode`. Two formats: SKILL.md (`FromPPM`, `FromFolder`, `FromSkillFile`; common parser from `Source/Core/uMakerAi.Skills.Format.pas`) and its own JSON (`FromJSON`, `FromFile`). `ApiKey` only from JSON: a SKILL.md is third-party content. Guide: `Docs/Version 3/uMakerAi-Agents-Skill.md` |
| `uMakerAi.Agents.Tools.JevRouter.pas` | `TAiJevRouterTool`: node tool that chooses the next route with Jev (TypeSafe AI) and writes it to `Blackboard['next_route']` for an `lmConditional` link. Registered in `TEngineRegistry` as `JevRouter` |
| `uMakerAi.A2A.Server.pas` | `TAiA2AServer` (A2A 1.0 spec): exposes `TAIAgentManager`(s) as an A2A agent — Agent Card at `/.well-known/agent-card.json`, JSON-RPC `SendMessage`/`GetTask`/`CancelTask` (+ 0.x aliases). Manager pool, real task lifecycle, `input-required` resume, bearer auth and `traceparent`; no streaming (rejects with UnsupportedOperationError) |
| `uMakerAi.A2A.Client.pas` | `TAiA2AClient`: consumes remote A2A agents — `FetchAgentCard`, `SendText`/`SendTextEx`, `GetTask`/`CancelTask`; normalized state in `LastTaskState` and agent question in `LastStatusMessage`. Includes `TAiA2ARemoteAgentTool` (federation): assigned as a node's `Tool`, delegates the node input to a remote A2A agent; registered in `TEngineRegistry` |

## Core Classes

**TAIAgentManager** - Orchestrates workflow execution via TThreadPool. Key properties: `StartNode`, `EndNode`, `MaxConcurrentTasks` (default 4). Use `Run(APrompt)` for sync execution, `Compile()` to validate before running. `Compile` is purely structural (validation + InEdges); it does NOT clear the Blackboard — a pre-seeded `Blackboard.AskMsg` survives the first `Run` (fix M-03). For an explicit clean slate between runs call `ResetExecutionState` (clears blackboard, node/link transient state; keeps graph structure).

**TAIAgentsNode** - Workflow vertex. Executes via `OnExecute` callback or attached `Tool: TAiToolBase`. Join modes: `jmAny` (first input triggers), `jmAll` (waits for all inputs).

**TAIAgentsLink** - Directed edge connecting nodes. Four routing modes:
- `lmFanout` - Broadcasts to all NextA/B/C/D slots
- `lmConditional` - Routes based on `Blackboard[ConditionalKey]` value
- `lmManual` - Targets specified programmatically via `ManualTargetsKey`
- `lmExpression` - Evaluates `ExpressionA/B/C/D` bindings against blackboard

**TAIBlackboard** - Thread-safe shared state (TDictionary with TCriticalSection). Standard accessors: `SetString/GetString`, `SetInteger/GetInteger`, `SetBoolean/GetBoolean`. Chat messages via `AskMsg`, `ResMsg` properties.

**TAiToolBase** - Abstract base for node tools. Inherit and implement `Execute(ANode, AInput, var AOutput)`.

**TAiToolParams** - Public RTTI mapper for tool parameters (fix M-04): `ToJSON`/`FromJSON`/`SchemaOf`. Excludes `AI_TOOL_RESERVED_PROPS` (`Name`, `Tag`, `ID`, `Description`) both ways, honors `[TSecret]` (never written; incoming values ignored; `SchemaOf` marks them `writeOnly` + `x-credential-type`). `FromJSON` accepts typed JSON values or their string representation (single mapper — `GraphBuilder.SetToolParameters` delegates here). Serialization notes: `TAIAgentManager.SaveToStream` raises `EAiGraphError` for nodes with `OnExecute` and no `Tool` unless `AllowPartialSerialization := True` (fix M-06).

## Creating Custom Tools

```pascal
uses uMakerAi.Agents, uMakerAi.Agents.Attributes, uMakerAi.Agents.EngineRegistry;

type
  [TToolAttribute('MyTool', 'Does something useful', 'Custom')]
  TMyTool = class(TAiToolBase)
  private
    [TToolParameterAttribute('API Key', 'Your API key', '')]
    FApiKey: string;
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string); override;
  published
    property ApiKey: string read FApiKey write FApiKey;
  end;

initialization
  TEngineRegistry.Instance.RegisterTool(TMyTool, 'uMyToolUnit');
```

## Routing with Jev (`TAiJevRouterTool`)

A node **without `OnExecute`** with `TAiJevRouterTool` as `Tool` asks Jev which of the `Routes` corresponds to its input and writes the key to `Blackboard[RouteKey]` (default `next_route`, which is the link's default `ConditionalKey`). The existing `lmConditional` link does the rest: **the engine does not change**.

```pascal
Router := TAiJevRouterTool.Create(Manager);
Router.AddRoute('contable',   'Journal entries, PUC, IFRS, financial statements');
Router.AddRoute('tributario', 'Income tax, VAT, withholding, DIAN');
Router.AddRoute('general',    '');
Router.AddFlag('fuentes', 'Does answering `consulta` require citing a specific rule?');
Manager.FindNode('Recepcion').Tool := Router;
Manager.AddConditionalEdge('Recepcion', 'Enrutador', Targets);   // route key -> node
Manager.FindNode('Recepcion').Next.NextNo := Manager.FindNode('humano');
```

- **Final route:** `Choice` if its confidence ≥ `MinConfidence` (0.5); otherwise `FallbackRoute`. With an empty `FallbackRoute` the link falls to `NextNo` (in GraphBuilder, the `out_failure` port).
- **A down Jev does not bring down the graph:** the error (network, 401, configuration) stays in `<Node>.jev.error`, `FallbackRoute` is used, and the graph ends `esCompleted`.
- **Blackboard** (prefix `<Node>.jev.`): `choice`, `confidence`, `top` (3 most likely), one value per flag and `error`. Numbers use **decimal point** (`'0.85'`), suitable for `lmExpression` (`Recepcion.jev.fuentes >= 0.5`).
- **Flags:** Nodes that travel in the same call as the route. `OnRoute(Sender, Node, Result, var Route)` allows combining them, e.g. `contable` + high `fuentes` → `contable_normativo`.
- **GraphBuilder:** route keys are the `idStr` of the router node's output ports — name the ports the same as the `Routes`. `ApiKey` is `[TSecret]` (default `@TYPESAFE_API_KEY`), never travels in the JSON.
- **The wording of `Instructions` moves confidence.** "Which route or specialist should handle…?" gave 0.44 where "Which specialist should respond…?" gave 0.68 (same query, `jev-1.13.0`); the second is the default. Calibrate `MinConfidence` after fixing the wording.
- The node output is its input unchanged: the chosen agent receives the original query.
- An external `TAiJev` is assigned in `Router.Jev` (shared, or the suite's `TFakeJev`); if not, the tool creates its own with `ApiKey`/`Model`.

**`lmExpression` and the decimal point (fix Sep 27/2026):** `EvalCondition` parsed numbers only with regional settings, so on a Windows with decimal comma `'10.25' > 9.5` was compared as text and gave `False`. Now it tries regional settings first and then decimal point (case `agents.expression.decimal-point`).

## JSON Graph Format

GraphBuilder expects this structure:
```json
{
  "nodes": [
    {
      "id": "node_guid",
      "label": "NodeName",
      "toolClassName": "TMyTool",
      "parameters": { "ApiKey": "xxx" },
      "properties": {
        "engine": { "joinMode": "jmAny", "linkMode": "lmFanout" }
      }
    }
  ],
  "edges": [
    {
      "sourceNodeId": "node1_guid",
      "targetNodeId": "node2_guid",
      "sourceTerminal": "out_a"
    }
  ]
}
```

Port terminals: `out_a`, `out_b`, `out_c`, `out_d`, `out_failure` (maps to NextNo in ALL link modes, including `lmConditional` — fix M-07).

## Reusing a manager across runs

`Compile` validates structure only; it does **not** clear execution state (fix M-03 — clearing there freed the `AskMsg`/`ResMsg` that `Run` seeds beforehand). Since `Compile` also early-exits when `FCompiled` is already `True`, **consecutive `Run(APrompt)` calls on the same instance inherit the previous run's state**: blackboard keys, node `Input`/`Output`/`FError`/`FSuspended`, and link `NoCycles`.

That is the historic behavior and it is preserved. To get a clean run, use the seeding overload:

```pascal
Manager.Run('prompt',
  procedure(B: TAIBlackboard)
  begin
    B.SetString('cliente_id', '42');   // seeded AFTER the reset, so it survives
  end);
```

Guaranteed order: `Compile` -> `ResetExecutionState` -> `ASeed` -> seed `AskMsg`/`ResMsg` -> execute. Seeding before `Run` instead of inside `ASeed` would be wiped by the reset.

`ASeed` may assign `AskMsg` (it is not overwritten if already set). It need not assign `ResMsg` — `Run` always creates a fresh one for the run.

`ResetExecutionState` is also public if you prefer to call it explicitly.

> `TAIBlackboard.SetAskMsg`/`SetResMsg` free the previously stored message before replacing it. Without that, every repeated `Run` leaked the prior `ResMsg`, because `SetValue` only does `AddOrSetValue` and `Clear` was no longer being reached.

## Execution Status

`TAgentExecutionStatus`: `esUnknown`, `esRunning`, `esCompleted`, `esError`, `esTimeout`, `esAborted`, `esSuspended`

Access via `Blackboard.SetStatus()`/`GetStatus()`.

`esSuspended` is set when one or more nodes called `Node.Suspend(...)` during execution. Use `TAIAgentManager.ResumeThread(ThreadID, NodeName, Input)` to resume.

## Durable Execution (Checkpoint / Suspend-Resume)

**Key types** (in `uMakerAi.Agents.Checkpoint`):
- `IAiCheckpointer` — persistence contract; assign to `TAIAgentManager.Checkpointer`
- `TAiNullCheckpointer` — no-op (default behavior, no disk writes)
- `TAiFileCheckpointer` — JSON on disk (`<dir>/<GUID>.checkpoint.json`)
- `TAiCheckpointSnapshot` — serialized state (blackboard + node/link states + pending steps)

**Suspend a node from `OnExecute`:**
```pascal
procedure MyNodeExecute(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
  Input: string; var Output: string);
begin
  Output := Input; // pass-through
  Node.Suspend('Requires approval', 'Additional context');
end;
```

Or use the built-in `TAiWaitApprovalTool` (from `uMakerAi.Agents.Tools.Approval`).

**Resume after suspension:**
```pascal
// Detect suspended threads on app startup
var Threads := AgentManager.GetActiveThreads;
// Resume when user approves
AgentManager.ResumeThread(ThreadID, 'NombreDelNodo', 'Approved');
```

**Event for human-in-the-loop UI:**
```pascal
AgentManager.OnSuspend := procedure(Sender: TObject; const ThreadID, NodeName,
  Reason, Context: string) begin
  ShowMessage('Approval required: ' + Reason);
end;
```

## A2A: orchestration flows

**Concurrency.** A `TAIAgentManager` does not execute two graphs at once, so an A2A server with a single manager serializes tasks (the second receives `AgentBusy`, `-32000`). For real fan-out assign `TAiA2AServer.OnAcquireManager`: the factory returns a new graph and the server keeps a pool of up to `MaxConcurrentTasks`. Slot reservation is atomic (it does not depend on `Busy`), so two simultaneous requests do not end up with the same manager.

```pascal
procedure TForm1.AcquireManager(Sender: TObject; var AManager: TAIAgentManager);
begin
  AManager := TAIAgentManager.Create(nil);   // the server frees it
  AManager.AddNode('Uno', NodeExec).AddNode('Dos', NodeExec);
  AManager.AddEdge('Uno', 'Dos');
  AManager.SetEntryPoint('Uno').SetFinishPoint('Dos');
end;
```

**Task lifecycle.** `SendMessage` with `configuration.blocking = false` (or when `WaitTimeoutMs` expires) responds with the task in `working`; the client continues with `GetTask`, which refreshes state from the live graph. The slot is released only when a terminal state is reached. A wait timeout **does not** mark `failed`.

> The server forces `Asynchronous := True` on the managers it drives: in synchronous mode `Run` would do `Wait(INFINITE)` (ignoring the timeout) and throw an exception instead of leaving the state on the blackboard.

**Human-in-the-loop over A2A.** A suspension (`Node.Suspend`) is published as `input-required` with the question in `status.message`, and the task keeps its manager. A later `SendMessage` with the same `taskId` resumes the graph (`ResumeThread`) using the received text as the human response.

On the federated side, `TAiA2ARemoteAgentTool` suspends the **local node** when the remote agent asks for input (`SuspendOnInputRequired`, default `True`) instead of failing; when the local node resumes, the response travels to the same remote task. The pending remote task is remembered on the blackboard under `A2A.<NodeName>.PendingTask`.

**State literals.** `StateNaming` chooses the emitted form: `anProto` (`TASK_STATE_COMPLETED`, default) or `anLower` (`completed`). Reading always tolerates both — use `TAiA2AClient.LastTaskState` (enum) and do not compare strings.

> v1.0 moved from kebab-case to SCREAMING_SNAKE_CASE for ProtoJSON conformance, so **`anProto` is the correct spec format** and `anLower` the compatibility one with the 0.x era. It is the opposite of what intuition suggests.

## Normative sources of the protocol

**Do not reason from memory or from the web: the proto rules.**

| Source | Status |
|---|---|
| [`specification/a2a.proto`](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto) | **Single normative definition** of all objects and messages |
| `spec/a2a.json` | JSON Schema generated at build, **not versioned and not normative** |
| [a2a-protocol.org/latest/specification](https://a2a-protocol.org/latest/specification/) | Prose derived from the proto; useful for understanding, not for settling disputes |
| [`a2aproject/a2a-tck`](https://github.com/a2aproject/a2a-tck) | **Official conformance TCK**; validates JSON-RPC with RFC 2119 levels (MUST / SHOULD / MAY) |

Practical shortcut to consult the canonical form of any message without reading the proto: install `a2a-sdk` (it is proto-first) and inspect the descriptor.

```python
import a2a.types as T
print([f.name for f in T.SendMessageResponse.DESCRIPTOR.fields])   # ['task', 'message']
```

## Wire format: v1.0 vs 0.x

Verified against the official `a2a-sdk` 1.1.2 (August 2026). SDK 1.x is **proto-first**: types are protobuf and the wire is **protojson**.

`WireEra` (default `weV1`) controls two differences that break interop:

**1. `SendMessage` returns the Task wrapped.** `SendMessageResponse` is a *oneof* `{task | message}`:

```jsonc
{"result": {"task": {...}}}    // v1.0
{"result": {...campos...}}     // 0.x
```

**`GetTask` and `CancelTask` do NOT have a wrapper** in any era: in the proto they are `returns (Task)` and do not have their own response message.

The client normalizes both forms with `UnwrapSendMessageResult`, which also synthesizes a Task when the agent responds with `{"message": ...}` (immediate response without creating a task).

**2. The Agent Card changed shape.** In v1.0 the root **does not have** `url`, `protocolVersion` or `preferredTransport`: they go inside `supportedInterfaces[] = [url, protocolBinding, tenant, protocolVersion]`. Without that, a v1.0 client does not know what URL to talk to. Also `security` is called `securityRequirements` (with a `schemes` field) and `capabilities.stateTransitionHistory` no longer exists.

The client reads the URL from `supportedInterfaces` with fallback to the flat `url` of 0.x.

### Authorization

`ApiKey` requires `Authorization: Bearer <key>` (or `X-API-Key`). Without it → 401 with `WWW-Authenticate`. `OnAuthorize` allows deciding by hand and is always called.

Two things that were hard to find and should not be broken again:

> **`TIdHTTPServer` only understands `Basic` authentication.** Faced with an `Authorization: Bearer …` it responds **401 on its own** and `HttpCommand` never gets to execute. That is why the server hooks `OnParseAuthentication` with `VHandled := True`. Without that handler bearer auth **does not work at all** — only `X-API-Key` passed, and the 401 looked like ours. MCP servers already did this; A2A did not. Same trap as demo 037 and 080.

> **The base Agent Card is left out of the `ApiKey` check.** It is a discovery document, and it is exactly where the client reads *which* security scheme to use: protecting it is a vicious circle. For data only to authenticated clients there is the extended card. `OnAuthorize` is still called on it, in case someone wants to close it on purpose.

The secret is compared **exactly**; only the scheme name is case-insensitive. With `SameText` on the entire header, `secretkey` was valid for `SecretKey`.

### Agent Card skills

A skill is what a client reads to **decide whether this agent serves them**. It is not an entry point: the spec has no skill selector in `SendMessage`, so skills describe, they do not route.

That is why **they are not derived from the graph nodes**. A normal graph has `Nodo1`/`Nodo2` nodes without a description, and publishing them would be noise that also hints at an invocation granularity that does not exist. They are declared:

```pascal
Server.Skills.AddSkill('traducir', 'Traductor', 'Traduce texto', 'idiomas, texto');
```

`Tags` is comma-separated and emitted as a JSON array. If the collection is empty, a single `run-graph` skill is published — the card **never** goes out without skills.

`PublishNodesAsSkills := True` also adds one skill per node, but **only for nodes whose `Tool` has a `Description`**; the rest are deliberately omitted. For total control, `OnCustomizeCard` is still available.

> **Interop tests must speak raw HTTP.** The `a2a.wire.v1`, `a2a.wire.v03` and `a2a.listtasks` cases in the suite do not use `TAiA2AClient` on purpose: for months the 9 A2A cases passed with the wrong format because client and server shared the error. A test that validates against your own implementation does not prove conformance.
>
> For real conformance there is `Tests/Interop/run_interop.ps1`, which tests both directions against the official `a2a-sdk`.

## Supported JSON-RPC methods

| Method | Status |
|---|---|
| `SendMessage` | ✅ (+ 0.x alias `message/send`) |
| `GetTask` | ✅ (+ `tasks/get`) |
| `CancelTask` | ✅ (+ `tasks/cancel`) |
| `ListTasks` | ✅ `contextId` and `status` filters, paginated by `pageSize`; returns `{tasks, totalSize, pageSize}` |
| `GetExtendedAgentCard` | ✅ if `PublishExtendedCard := True`; otherwise `UnsupportedOperationError`. To differentiate it from the public one, enrich it in `OnCustomizeCard` |
| `SendStreamingMessage` | ✅ SSE (+ alias `message/stream`) |
| `SubscribeToTask` | ✅ SSE (+ `tasks/resubscribe`); error if the task is already terminal |
| `CreateTaskPushNotificationConfig` etc. | ✅ full CRUD + webhook delivery |

## Threading Model

- Nodes execute in parallel via TThreadPool
- `MaxConcurrentTasks` limits concurrent executions
- TAIBlackboard operations are thread-safe
- Node callbacks (`OnExecute`) run on worker threads - use `TThread.Synchronize` for UI updates

## Dependencies

Internal: `uMakerAi.Chat`, `uMakerAi.Core`, `uMakerAi.Chat.Messages`

Framework: `System.Threading`, `System.Bindings.*`, `System.Rtti`, `System.JSON`, `System.SyncObjs`

## Streaming SSE

`EnableStreaming` (default `True`) enables `SendStreamingMessage` and `SubscribeToTask`, and announces it in `capabilities.streaming`.

**Framing depends on the binding.** Each event goes on a `data:` line, but:

```jsonc
// binding JSON-RPC (el nuestro) — CON envoltorio, spec §9.4.2
data: {"jsonrpc":"2.0","id":1,"result":{ StreamResponse }}

// binding REST — el StreamResponse DESNUDO
data: {"statusUpdate": { ... }}
```

`StreamResponse` is a oneof: `task | message | statusUpdate | artifactUpdate`.

**Emission order:** initial `task` snapshot → `artifactUpdate` (one per artifact, the last with `lastChunk: true`) → terminal `statusUpdate`. Artifacts go **before** the final status; it is the order of the spec example and what the TCK ordering test validates.

**`SendStreamingMessage` with `taskId` resumes**, just like `SendMessage`: same validations (nonexistent task → `-32001`, crossed `taskId`/`contextId` pair → `-32602`, terminal task → `-32004`). Without this, a human-in-the-loop over streaming opened a new task on every turn and lost the suspended graph.

> **The state can be final before the first snapshot** — a fast graph, or a resume that completes right away. Tracking is done by comparing against the snapshot state, so in that case there is no change left to detect and the stream stayed open until `WaitTimeoutMs` was exhausted. Now it closes immediately.
>
> With a nuance that is hard to see: **`input-required` closes only if it is NOT a subscription**. In `SendStreamingMessage` it means "your turn"; whoever does `SubscribeToTask` is an observer and must keep seeing later transitions. Closing the stream on them breaks the TCK's `SUBSCRIBE-TERMINAL`.

A stream also closes on `input-required`: the ball passes to the client.

> **Snapshots of the same task must be identical.** Two subscribed clients receive the same events, so nothing volatile can slip into them. Two real failures because of this: the status `messageId` was generated with a new GUID on every call, and `RefreshTask` stamped `UpdatedAt := Now` on every query instead of only when the state changed. The latter also prevented the purge TTL, which is measured against that field, from expiring.

## Calling an A2A agent from a chat

`TAiA2AAgentTool` exposes a remote agent as a **chat tool**: when assigned a `TAiFunctions`, the LLM can invoke it like any other function.

```pascal
AgentTool := TAiA2AAgentTool.Create(Self);
AgentTool.AgentUrl := 'http://host:8280';
AgentTool.ToolName := 'preguntar_experto';
AgentTool.Description := 'Ask an agent specialized in regulations';
AgentTool.Functions := AiFunctions1;   // al asignarlo se registra la función
```

It is the sibling of `TAiA2ARemoteAgentTool`: that one federates a **graph node**, this one a **conversation**.

`DiscoverFromCard` fills the description from the agent's Agent Card, so the LLM sees the one the agent publishes about itself.

Failures are told to the model as text instead of breaking the turn: if the remote agent goes down or asks for more data, the LLM can retry, ask the user, or continue without that information. An exception would abort the entire conversation because of a problem with a collaborator.

## Push notifications

`EnablePushNotifications` (default `True`) enables CRUD of configs and delivery, and announces it in the card.

- The config arrives via `CreateTaskPushNotificationConfig` **or** inside `SendMessage`, in `configuration.taskPushNotificationConfig`.
- Parameters are accepted in camelCase **and** snake_case: the binding uses camelCase but several clients send the proto names.
- The webhook payload is a **`StreamResponse`** (`task` arm), not the bare Task. It is sent with `Authorization` if the config includes `authentication`.
- `Delete` is idempotent and re-registering the same `id` replaces, so the webhook does not receive the same notification twice.

**Delivery is active**: nobody needs to poll the task. The server hooks `TAIAgentManager.OnFinish` (chaining the previous handler) and from there refreshes the task, which triggers delivery. It works with `blocking:false`.

> **Watch the graph engine order.** `TAIAgentManager` fires `OnFinish` and **only afterwards** sets `FBusy` to 0. A refresh launched from that event sees the manager as busy, takes the "still working" branch and loses the final transition — the webhook never finds out. That is why `RefreshTask` has the `AIgnoreBusy` parameter, which should only be used from `OnGraphFinished`, where it is already known that the graph finished.

The TCK passes `PUSH-DELIVER-*` with a blocking flow, so it **does not cover this scenario**; demo 080 does.

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for source directory overview and [../../CLAUDE.md](../../CLAUDE.md) for project overview.