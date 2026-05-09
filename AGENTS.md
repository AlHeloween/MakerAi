# AGENTS.md

This file provides operational rules for AI coding agents working in this repository. It supplements and bridges the tiered `CLAUDE.md` system with ADID Framework conventions.

## First Steps (Before Any Work)

1. Read `CLAUDE.md` at this root for the project overview, architecture, and conventions.
2. Read `project_progress.md` to understand what has been done so far and what's pending.
3. Check `.opencode/skills/` for available skills (9 skills: `delphi_builder`, `dunit`, `adm-exe`, `adm-mcp-service`, `agent-assets`, `apply-patch-edits`, `cmd-runner`, `patch-tool`, `rag`).
4. Read the relevant module `CLAUDE.md` in `Source/<Module>/` for subsystem-specific guidance.
5. Read `.opencode/rules/adid-framework-and-adm.mdc` for ADID operational rules.
6. Publish state and plan before writing code.
7. Do not perform write actions until the plan is approved.

## Project Identity

- **Language**: Delphi Pascal (Object Pascal). NOT Python.
- **Version**: 3.3 (Feb 2026). `Source/Core/uMakerAi.Version.inc` for all feature flags.
- **Source of truth**: The Delphi source in `Source/` is the canonical codebase. `CLAUDE.md` files (root + 18 sub-files) are the canonical agent instructions.
- **Comments/Locale**: Code comments and variable names are in **Spanish**. Match the language style of the file being edited.
- **Git workflow**: `master` is release, `dev` is active development. PRs target `master`.
- **No formal test suite**: Testing is manual via Delphi IDE demos. The `Demos/` directory may be absent from this checkout.

## Governing Sources (Priority Order)

1. Existing Delphi source code (`Source/`) â€” primary source of truth
2. `CLAUDE.md` (root) â€” project architecture, patterns, conventions
3. Module `CLAUDE.md` files â€” subsystem-specific guidance
4. `Docs/Version 3/` â€” external documentation (.docx, .pdf, .md)
5. `.opencode/rules/adid-framework-and-adm.mdc` â€” framework operational rules
6. `.opencode/rules/semantic-coding-agent-drop-in.mdc` â€” semantic agent workflow

## Agent Delegation

When tasks are large or repetitive, delegate to a sub-agent via the `task` tool rather than processing inline.

| Agent Type | Use For |
|------------|---------|
| `explore` | Codebase exploration, file search, pattern discovery, prior-art verification |
| `general` | Batch / bulk operations: multi-file edits, encoding conversions, string replacements across many files, bulk analysis, mechanical refactors |

### Delegation Rules
- **`explore`** — always use before any implementation to check for conflicting prior implementations (Planning Workflow step 9).
- **`general`** — use for any task touching 10+ files, doing repetitive mechanical work, or where inline tool calls would bloat context. Example: scanning 106 `.pas` files for Spanish strings, converting 100+ files to UTF-8, bulk find-and-replace across an entire module.
- Prefer multiple agents launched in parallel for independent subtasks.
- Each agent call must specify: what to do, what files/dirs to touch, what to return, and how to verify.

## Available Skills

| Skill | Tool File | Purpose |
|-------|-----------|---------|
| `delphi_builder` | `.opencode/skills/delphi_builder/` | Build Delphi `.dproj` via MSBuild CLI |
| `dunit` | `.opencode/skills/dunit/` | Run DUnit tests for Delphi |
| `adm-exe` | `.opencode/skills/adm-exe/` | Declarative updates, verify-all, rollback, templates |
| `adm-mcp-service` | `.opencode/skills/adm-mcp-service/` | MCP server (stdio/HTTP) service management |
| `agent-assets` | `.opencode/skills/agent-assets/` | Canonical artifacts + agent scaffold management |
| `apply-patch-edits` | `.opencode/skills/apply-patch-edits/` | apply_patch-only edits for canonical files |
| `cmd-runner` | `.opencode/skills/cmd-runner/` | Safe interactive Windows commands via ConPTY |
| `patch-tool` | `.opencode/skills/patch-tool/` | apply_patch-format patches with ADID backups |
| `rag` | `.opencode/skills/rag/` | Index/query repos using ADM RAG + bge-m3 |

## Code Conventions (Delphi-Specific)

### Naming
- Unit prefix: `uMakerAi.` (e.g., `uMakerAi.Chat.OpenAi.pas`)
- Class prefix: `TAi` or `TAI` (e.g., `TAiChat`, `TAIAgentManager`)
- Interface prefix: `IAi` (e.g., `IAiPdfTool`, `IAiVisionTool`)
- Driver naming: `TAi[Provider]Chat` (exception: `TCohereChat`)

### Architecture Rules
- All LLM drivers inherit from `TAiChat` (defined in `Source/Core/uMakerAi.Chat.pas`)
- New drivers register in `Source/Chat/uMakerAi.Chat.Initializations.pas` via `TAiChatFactory`
- Model capabilities use `ModelCaps`/`SessionCaps` (`TAiCapabilities`) â€” v3.3 unified system
- Deprecated API: `NativeInputFiles`, `NativeOutputFiles`, `ChatMediaSupports`, `EnabledFeatures` â€” do NOT use
- 79 conditional compilation directives in codebase; primary split at `CompilerVersion 35` (Delphi 11)

### Quality Standards
- Follow existing code style within each file (spacing, line breaks, comment style)
- Use existing error patterns: `Exception.Create(msg)` or `Exception.CreateFmt(msg, [args])`
- Thread safety: Respect existing `TCriticalSection` locks and `TThread.Queue` patterns
- No hardcoded secrets; use `@VAR_NAME` convention for API keys resolved via `GetEnvironmentVariable()`

## ADID Framework Integration

This is a **Delphi project**, not a Python project. The ADID Framework Python-oriented conventions (PEP 8, PEP 257, PEP 484, `uv`, `pyproject.toml`) are adjusted as follows:

| ADID Rule | Delphi Adaptation |
|-----------|------------------|
| `pyproject.toml` / `uv sync` | N/A â€” use Delphi IDE or `delphi_builder` skill for builds |
| `uv run scripts/build_artefacts.py` | N/A â€” Delphi artifacts managed via IDE |
| PEP 8 style | Follow existing Delphi style in each file |
| PEP 257 docstrings | Use existing comment patterns in `.pas` files |
| PEP 484 type hints | Use Pascal type declarations |
| cmd_runner | Available via `.\cmd_runner.exe` or via `.opencode/skills/cmd-runner/` |
| adm tools | Available via `tools/adm.exe` |
| RAG indexing | `tools/adm.exe --rag index <name> Source/` |

### Workspace Lanes
- `experiments/` â€” short-lived experiments and scratch code
- `futures/` â€” planned work / drafts not ready for mainline
- `obsolete/` â€” deprecated artifacts kept for reference only
- `makeups/` â€” explicit stubs (include note explaining what is stubbed and why)

### Non-Mainline Activity
Changes under `experiments/`, `futures/`, `obsolete/`, `makeups/` should use `--patch-tool` and standard shell commands instead of adding new declarative descriptors under `updates/`.

## Planning Workflow

1. Read this file and `CLAUDE.md` for context.
2. Read `project_progress.md` for session history, completed tasks, and pending work.
3. Load relevant skills via `skill` tool.
4. Publish State with semantic vector: `sv=[[keywords],[weights]]`
5. Explore the affected modules via explorer agent to identify prior implementations.
6. Create plan in `plans/[ISO8601]_plan_description.md`.
7. Each plan must include: abstract definition, structural diagram, input/output parameters, brief implementation, test cases.
8. Complex plans split into sub-task files in `plans/`.
9. Double-check every plan with explorer agent to verify no conflicting prior implementation exists.
10. Implement after plan approval.
11. After each task, update `project_progress.md` with what was done and verification results.
12. Move completed plan to `plans_completed/`.

## Key Source Files

| Task | Primary File |
|------|-------------|
| Add new LLM provider | `Source/Chat/uMakerAi.Chat.*.pas` â†’ register in `Initializations.pas` |
| Configure model capabilities | `Source/Chat/uMakerAi.Chat.Initializations.pas` |
| Modify capability orchestration | `Source/Core/uMakerAi.Chat.pas` |
| Add `TAiCapability` value | `Source/Core/uMakerAi.Core.pas` |
| Modify function calling | `Source/Tools/uMakerAi.Tools.Functions.pas` |
| RAG vector operations | `Source/RAG/uMakerAi.RAG.Vectors.pas` |
| RAG graph operations | `Source/RAG/uMakerAi.RAG.Graph.Core.pas` |
| Agent orchestration | `Source/Agents/uMakerAi.Agents.pas` |
| MCP server creation | `Source/MCPServer/uMakerAi.MCPServer.Core.pas` |
| Version/feature flags | `Source/Core/uMakerAi.Version.inc` |

## Package Build Order

```
1. Source/Packages/MakerAI.dpk          â†’ Runtime core (~98 units)
2. Source/Packages/MakerAi.RAG.Drivers.dpk â†’ PostgreSQL connectors
3. Source/Packages/MakerAi.UI.dpk       â†’ FMX visual components
4. Source/Packages/MakerAiDsg.dpk       â†’ Design-time editors (VCL + DesignIDE)
```

Group project: `Source/Packages/MakerAiGrp.groupproj`

## Thread Safety Brief

| Lock | Class | Protects |
|------|-------|----------|
| `FLock` | `TAiChatMessage` | Media file list |
| `FLock` | `TAIBlackboard` | Shared state dictionary |
| `FJoinLock` | `TAIAgentsLink` | Join counter |
| `FActiveTasksLock` | `TAIAgentManager` | Active task count |
| `FOutputLock` | `TAiMCPServerStdio` | Stdout writes |
| `FSessionsLock` | `TAiMCPServerSSE` | SSE session list |
| `FCS` | `TAiVoiceMonitor` | Audio capture state |

## Error Handling

| Exception | Module | When |
|-----------|--------|------|
| `EVGQLParserError` | RAG/VQL | Invalid VQL syntax |
| `EVGQLTranslationError` | RAG/VQL | VQL-to-SQL compilation failure |
| `EMCPClientException` | MCPClient | MCP transport/protocol error |
| `EPythonArchitectureError` | Utils | Python arch mismatch (x86 vs x64) |

## External Documentation

Key docs in `Docs/Version 3/`:
- `uMakerAi-ChatConnection.docx` â€” TAiChatConnection guide
- `uMakerAi.Chat.docx` â€” Core chat reference
- `uMakerAi-CapabilitySystem.EN.md` â€” Capability system (English)
- `uMakerAi-RAG.docx` â€” RAG system docs
- `uMakerAI-RAGGraph.docx` â€” Graph RAG docs
- `uMakerAi.ToolFuncions.docx` â€” Function calling docs
- `TAiAgentes-FLUENT GRAPH BUILDER.docx` â€” Agent graph builder
- `uMakerAi-MCP.Server.EN.pdf` â€” MCP Server (English)

## Enforcement

- **Do not violate Agent Delegation rules above.** Failing to delegate bulk/repetitive work to sub-agents bloats context, degrades output quality, and wastes compute.
- **Do not add backward-compat parsing, fallback paths, or "auto-repair" behaviors that silently reinterpret descriptors.** Fail fast with clear errors. Ground all work in existing code, tests, docs, and runtime behavior.
