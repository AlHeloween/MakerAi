# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Directory Purpose

This is the documentation root for MakerAI v3.2 - an AI orchestration framework for Delphi. **No source code exists here** - all implementation is in `/Source/`.

## Documentation Structure

```text
Docs/
├── Version 3/           ← Current version documentation
│   ├── Agents/          ← Agent orchestration (graph-based workflows)
│   ├── MCPServer/       ← Model Context Protocol server implementation
│   ├── RAG/             ← Retrieval-Augmented Generation (vector + graph)
│   └── PDF/             ← Distribution-ready consolidated PDFs
└── Reportes/            ← Field reports from framework consumers
```

## Language

Documentation is primarily in **Spanish**. English versions available for:
- MCP Server (`MCPServer/uMakerAi-MCP.Server.EN.pdf`)

## Subdirectory CLAUDE.md Files

Specialized guidance exists in subdirectories:
- `Version 3/CLAUDE.md` - Full documentation map and source code cross-references
- `Version 3/MCPServer/CLAUDE.md` - MCP protocol patterns, testing commands
- `Version 3/RAG/CLAUDE.md` - pgvector reference, RAG implementation patterns

## Key Documentation → Source Mapping

| Documentation | Source Code |
|---------------|-------------|
| `uMakerAi-ChatConnection.docx` | `Source/Chat/uMakerAi.Chat.AiConnection.pas` |
| `uMakerAi.Chat.docx` | `Source/Core/uMakerAi.Chat.pas` |
| `uMakerAi-Agents.ES.docx` | `Source/Agents/uMakerAi.Agents.pas` |
| `uMakerAi-RAG.ES.docx` | `Source/RAG/uMakerAi.RAG.Vectors.pas` |
| `uMakerAI-RAGGraph.docx` | `Source/RAG/uMakerAi.RAG.Graph.Core.pas` |
| `uMakerAi-MCP.Server.*.docx` | `Source/MCPServer/uMakerAi.MCPServer.Core.pas` |
| `uMakerAi.ToolFuncions.docx` | `Source/Tools/uMakerAi.Tools.Functions.pas` |
| `uMakerAi-AudioBridge.md` | `Source/Utils/uMakerAi.Utils.AudioCapture.pas`, `Source/Utils/uMakerAi.Utils.AudioPlayback.pas` |
| `uMakerAi-Skills.md` / `uMakerAi-Skills.EN.md` | `Source/Tools/uMakerAi.Tools.Skills.pas`, `Source/Core/uMakerAi.Skills.Format.pas`, `Source/Agents/uMakerAi.Agents.Skill.pas` |

## Field Reports

`Reportes/` collects reports written from applications that consume the
framework in production. They are not usage documentation: they are measured
findings, with their evidence and how to reproduce them. Useful because they
catch failures that the compiler does not see and that the demos do not
exercise. Reports in the opposite direction also go here: what MakerAi must
notify those applications about.

| Report | Origin -> destination | Status |
|---------|-----------------------|--------|
| `REPORTE_MKAISERVER_2026-08-29.md` | MKAIServer -> MakerAi | Addressed in 36b4379 and aa77522, except for the runtime verification of DeepSeek usage |
| `REPORTE_PARA_MKAISERVER_2026-09-16.md` | MakerAi -> MKAIServer | Delivered: actions after ca175d0 (gpt-image-2.5) and fca6aba (deepseek-flash); pending on the broker side |
| `REPORTE_PARA_MKAISERVER_2026-09-20.md` | MakerAi -> MKAIServer | Delivered: how to delegate Computer Use to a remote client now that OpenAI and Gemini respect the interception (38eeacf), plus the Linux executor (2e3e3be). Responds to the analysis that arrived from the broker: both of its points were correct. Pending on the broker side |

## File Formats

- `.docx` - Editable source documents (Word)
- `.pdf` - Distribution versions
- `.xlsx` - Test specification matrix (`Test List.xlsx`)
- `.m4a` - Webinar audio recordings

## Navigation

> See [../CLAUDE.md](../CLAUDE.md) for project overview.