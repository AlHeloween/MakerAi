# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**A2A interoperability test bench** against the official [`a2a-sdk`](https://pypi.org/project/a2a-sdk/) SDK from `a2aproject`.

The regression suite (`Tests/RegressionSuite`) validates the framework's behavior. This validates something different: that **the wire format is the spec's**, not the one we believe it is.

> That distinction is not theoretical. For months the 9 A2A cases in the suite passed with the **wrong** response format, because MakerAI's client and server shared the same mistake. A test that validates against your own implementation proves that you are consistent with yourself, not that you are conformant.

## How it runs

```powershell
cd Tests\Interop
.\run_interop.ps1                # creates the venv if missing, installs a2a-sdk and runs everything
.\run_interop.ps1 -SkipInstall   # if the venv is already set up
```

Exit code 0 = both directions conformant. Requires Python 3.10+ and demo 072 built in `Win64\Release`.

## What it tests

| Direction | What it validates |
|---|---|
| **1.** Our client → reference server | That we know how to **read** what a v1.0 agent emits |
| **2.** Conformant client → our server | That what **we emit** parses as v1.0 |

The key is in how it is validated: `ref_server.py` builds the responses with the SDK's **protobuf types** and serializes them with `json_format.MessageToJson`, so the JSON is canonical. And `ref_client.py` validates ours with `json_format.ParseDict` **without** `ignore_unknown_fields`: any extra or misnamed field makes parsing fail.

## Files

| File | What it is |
|---|---|
| `ref_server.py <port>` | Conformant A2A server; serializes with the SDK's types |
| `ref_client.py <url>` | Client that validates card and responses against the protobuf types |
| `run_interop.ps1` | Orchestrates both directions and returns the exit code |
| `.venv/` | Virtual environment (not versioned) |

## SDK 1.x is proto-first

The types in `a2a.types` are **protobuf**, not Pydantic, and the wire format is **protojson**. Practical consequences:

- `TaskState` is an `EnumTypeWrapper`: it is traversed with `.keys()`, not by iterating.
- Enums travel as `TASK_STATE_COMPLETED` / `ROLE_AGENT` (SCREAMING_SNAKE_CASE), not in kebab-case as in the 0.x era.
- The proto's `snake_case` fields come out in `camelCase` in the JSON.

To inspect the canonical shape of any message:

```python
import a2a.types as T
from google.protobuf import json_format
print([f.name for f in T.SendMessageResponse.DESCRIPTOR.fields])   # ['task', 'message']
```

## Findings this bench produced (August 2026)

See `Source/Agents/CLAUDE.md` for details. In short, two real bugs that no internal test could see:

1. `SendMessage` returned the Task **unwrapped**; v1.0 requires `{"result": {"task": {...}}}`. `GetTask`/`CancelTask` do go direct.
2. The Agent Card published `url`/`protocolVersion`/`preferredTransport` at the root, which **do not exist** in v1.0: they go in `supportedInterfaces[]`.

Fixed with the `TAiA2AServer.WireEra` and `TAiA2AClient.UnwrapSendMessageResult` properties.

## Navigation

> See [../RegressionSuite/CLAUDE.md](../RegressionSuite/CLAUDE.md) for the framework regression suite.
> See [../../Source/Agents/CLAUDE.md](../../Source/Agents/CLAUDE.md) for the A2A implementation.