# Plan: Agent Infrastructure Setup (2026-05-09)

## Abstract Definition

Establish AGENTS.md as the operational bridge between the existing tiered CLAUDE.md system (19 files) and the ADID Framework conventions. Create planning infrastructure (`plans/` + `plans_completed/`) for structured development workflow. This ensures the repository conforms to the `.opencode/rules/semantic-coding-agent-drop-in.mdc` requirement that AGENTS.md be the first file read by coding agents, while respecting the existing Delphi Pascal codebase and its 18 sub-module CLAUDE.md files.

## Structural Diagram

```
AGENTS.md (NEW)                     â† Agent entry point (ADID + Delphi conventions)
â”œâ”€â”€ References CLAUDE.md (root)     â† Project architecture, patterns, conventions
â”œâ”€â”€ References 18 sub-CLAUDE.md     â† Module-specific guidance
â”œâ”€â”€ References 2 .opencode/rules/   â† adid-framework + semantic-coding-agent
â”œâ”€â”€ References 9 skills             â† .opencode/skills/
â””â”€â”€ Defines planning workflow       â†’ plans/ + plans_completed/

plans/ (NEW)                        â† Active development plans (ISO8601 prefixes)
plans_completed/ (NEW)              â† Completed plan archive
```

## Input/Output Parameters

| Parameter | Type | Value |
|-----------|------|-------|
| Input: Project source | Delphi Pascal | `Source/` with ~100 units across 10 modules |
| Input: CLAUDE.md system | 19 .md files | Root + 18 sub-module files |
| Input: ADID Framework rules | 3 .mdc files | `.opencode/rules/` |
| Output: AGENTS.md | Bridging file | Delphi-adapted ADID conventions |
| Output: plans/ | Directory | ISO8601-prefixed plan files |
| Output: plans_completed/ | Directory | Archived completed plans |

## Brief Implementation

### 1. AGENTS.md Creation
- Positioned as the first-read agent file (per semantic-coding-agent-drop-in.mdc)
- Bridges ADID Framework with Delphi/Pascal reality (NOT Python)
- Does NOT duplicate CLAUDE.md content â€” references it
- Defines governing source priority order
- Documents Delphi-specific conventions (naming, architecture, thread safety, errors)
- Lists all 9 available skills with purposes
- Adapts ADID Python conventions to Delphi equivalents
- Defines the planning workflow with ISO8601 conventions

### 2. Planning Infrastructure
- `plans/` â€” active development plans
- `plans_completed/` â€” completed plan archive
- Both tracked in git (not gitignored, as a canonical project artifact)
- This file serves as the first plan: `plans/20260509_agent_infrastructure_setup.md`

### 3. Workflow Integration
- Each future plan follows: abstract â†’ structural diagram â†’ I/O params â†’ implementation â†’ test cases
- Each plan double-checked via explorer agent before implementation
- Completed plans moved to `plans_completed/`

## Test Cases

| # | Test | Expected Result |
|---|------|-----------------|
| 1 | Agent reads AGENTS.md first | AGENTS.md found at project root with valid markdown |
| 2 | CLAUDE.md remains canonical | All 412 lines of CLAUDE.md intact and referenced |
| 3 | ADID Framework rules applied | No PEP 8/257/484 requirements imposed on Delphi code |
| 4 | Skills discoverable | All 9 skills listed in AGENTS.md match .opencode/skills/ |
| 5 | Planning workflow functional | New plan can be created in plans/, moved to plans_completed/ |
| 6 | Delphi conventions respected | Code modifications follow AGENTS.md naming, architecture, thread safety rules |
| 7 | No backward-compat added | New code uses v3.3 ModelCaps/SessionCaps, not legacy API |

## Status

- [x] AGENTS.md created at project root
- [x] `plans/` directory created
- [x] `plans_completed/` directory created
- [ ] Explorer agent double-check verification
- [ ] Plan moved to plans_completed/ after verification
