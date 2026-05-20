# Repository Index — MakerAI v3.3

> **Purpose:** Folder-by-folder map of the repository. Each section describes a top-level directory, its purpose, and key entry points.
> **Last verified:** 2026-05-20

---

## Source/ — Delphi Source Code

AI orchestration framework for Delphi. ~94 `.pas` units across 12 modules.

| Module | Purpose | Key Entry Points |
|--------|---------|-----------------|
| `Source/Core/` | Foundation: base types, abstract chat, messages, prompts | `uMakerAi.Core.pas`, `uMakerAi.Chat.pas`, `uMakerAi.Chat.Messages.pas`, `uMakerAi.Prompts.pas`, `uMakerAi.Version.inc` |
| `Source/Chat/` | 12 LLM provider drivers + universal connector | `uMakerAi.Chat.AiConnection.pas` (connector), `uMakerAi.Chat.Initializations.pas` (factory), `uMakerAi.Chat.OpenAi.pas`, `uMakerAi.Chat.Claude.pas`, `uMakerAi.Chat.Gemini.pas`, etc. |
| `Source/Agents/` | Graph-based autonomous agent framework | `uMakerAi.Agents.pas` (manager, node, link), `uMakerAi.Agents.GraphBuilder.pas` (fluent builder), `uMakerAi.Agents.Checkpoint.pas` |
| `Source/RAG/` | Retrieval-Augmented Generation (vector + graph) | `uMakerAi.RAG.Vectors.pas` (vector store), `uMakerAi.RAG.Vectors.VQL.pas` (query language), `uMakerAi.RAG.Graph.Core.pas` (graph engine), `uMakerAi.RAG.Graph.GQL.pas` |
| `Source/MCPServer/` | Model Context Protocol server (StdIO/HTTP/SSE/Direct) | `uMakerAi.MCPServer.Core.pas`, `UMakerAi.MCPServer.Stdio.pas`, `UMakerAi.MCPServer.Http.pas`, `UMakerAi.MCPServer.SSE.pas` |
| `Source/MCPClient/` | MCP client connector | `uMakerAi.MCPClient.Core.pas` |
| `Source/Tools/` | Function calling, TTS, STT, vision, computer use, shell | `uMakerAi.Tools.Functions.pas` (function calling), `uMakerAi.Whisper.pas`, `uMakerAi.OpenAi.Dalle.pas`, `uMakerAi.Tools.Shell.pas`, `uMakerAi.Tools.ComputerUse.pas` |
| `Source/Embeddings/` | 11 embedding providers | `uMakerAi.Embeddings.core.pas` (abstract base), `uMakerAi.Embeddings.OpenAi.pas`, `uMakerAi.Embeddings.Gemini.pas`, etc. |
| `Source/ChatUI/` | FMX visual components | `uMakerAi.UI.ChatList.pas`, `uMakerAi.UI.ChatInput.pas`, `uMakerAi.UI.ChatBubble.pas` |
| `Source/Design/` | Design-time property editors (VCL + DesignIDE) | `uAiEditors.ChatConnectionEditor.pas`, `UMakerAi.ParamsRegistry.pas`, `uMCPClientEditor.pas` |
| `Source/Utils/` | Voice monitor, Python bridge, diff updater, screen capture | `uMakerAi.Utils.VoiceMonitor.pas`, `uMakerAi.Utils.Python.pas`, `uMakerAi.Utils.ScreenCapture.pas` |
| `Source/Packages/` | Delphi package projects (.dpk, .dproj, .groupproj) | `MakerAI.dpk` (runtime), `MakerAi.RAG.Drivers.dpk`, `MakerAi.UI.dpk`, `MakerAiDsg.dpk`, `MakerAiGrp.groupproj` |

---

## Docs/ — Documentation

Multi-format documentation in Spanish (ES/) and English (EN/).

| Path | Purpose | Formats |
|------|---------|---------|
| `Docs/Version 3/EN/` | English docs | .md (15), .docx (16), .pdf (1), .xlsx (1), .pptx (1) |
| `Docs/Version 3/ES/` | Spanish originals | .docx (17), .pdf (4), .md (2) |
| `Docs/Pruebas/` | Test artifacts | .xlsx (1) |
| `Docs/ADID_Framework_15_3.md` | ADID operational rules | .md |

---

## tools/ — CLI Tools

External executables used by the project toolchain.

| Tool | Purpose |
|------|---------|
| `tools/adm.exe` | ADID Update Manager — declarative updates, verify-all, rollback, RAG |
| `tools/rg.exe` | ripgrep — fast file content search |
| `tools/fd.exe` | fd — fast file discovery |
| `tools/apply_patch.exe` | Patch application tool |
| `tools/sed.exe` | Stream editor |
| `tools/ambr.exe` / `tools/ambs.exe` | Ambiguous search/replace tools |
| `tools/cmd_runner.exe` | Safe Windows command execution via ConPTY |
| `tools/init_msvc.cmd` | MSVC environment initialization |
| `tools/init_delphi.cmd` | Delphi environment initialization |
| `tools/build_delphi_msbuild.cmd` | Delphi MSBuild wrapper |

---

## scripts/ — Automation Scripts

Python scripts organized by purpose.

| Subdir | Purpose | Scripts |
|--------|---------|---------|
| `scripts/translation/` | Pattern-based comment translators | `translate_comments.py`, `translate_final.py` |
| `scripts/mojibake/` | `?` character fixers | `fix_mojibake.py`, `fix_mojibake2.py`, `fix_mojibake3.py`, `fix_final_complete.py`, `fix_last7.py` |
| `scripts/spanish_fix/` | Spanish word/phrase fixers | `fix_all_spanish.py`, `fix_trailing_comments.py`, `fix_trailing_q.py` |
| `scripts/audit/` | Auditors + extractors | `find_all_q.py`, `find_spanish_comments.py`, `extract_q_words.py`, `find_ahora.py` |
| `scripts/docs/` | Doc checkers + fixers | `check_en_docs.py`, `check_xlsx.py`, `audit_docs.py`, `spot_check_en.py`, `fix_docs_spanish.py` |
| `scripts/build/` | Delphi build batch files | `build_058.bat`, `build_064.bat`, `build_audio.bat`, `build_demo.bat`, `build_package.bat` |

---

## Project Infrastructure

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Root project overview, architecture, conventions (412 lines) |
| `AGENTS.md` | Agent operational rules bridging CLAUDE.md with ADID |
| `README.md` | Public-facing project description |
| `project_progress.md` | Session-by-session work log with verification |
| `.opencode/` | Agent configuration: rules, skills, plans |
| `.opencode/rules/` | ADID framework + semantic coding agent rules |
| `.opencode/skills/` | 9 skills (delphi_builder, adm-exe, rag, etc.) |
| `LICENSE.txt` | MIT License |

---

## Workspace Lanes

| Lane | Purpose |
|------|---------|
| `experiments/` | Short-lived experiments and scratch code |
| `futures/` | Planned work / drafts not ready for mainline |
| `obsolete/` | Deprecated artifacts kept for reference |
| `makeups/` | Explicit stubs/makeups with explanation notes |

---

## Other Directories

| Path | Purpose |
|------|---------|
| `Resources/` | UI resource images (icons, logos) |
| `Redis/` | Audio converter DLLs (ConvertToWave32.dll, ConvertToWave64.dll) |
| `ppm/` | PascalAI Package Manager reference |
| `logs/` | cmd_runner execution logs |
| `plans/` | Active development plans |
| `plans_completed/` | Archived completed plans |
| `.adid_rag/` | Local RAG runtime state (not committed) |
