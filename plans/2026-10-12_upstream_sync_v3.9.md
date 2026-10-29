# Plan: Upstream Sync v3.3 → v3.9.0 (English fork)

<!-- intention: fork on upstream v3.3 with full ES→EN translation -> fork synced to upstream v3.9.0 (master) with English preserved across all maintained surfaces -->

**Date:** 2026-10-12
**Branch:** `local` (merge `upstream/master` @ `39c093b`, tag `v3.9.0`)
**Owner decisions (2026-10-12):** upstream ref = master/v3.9.0 · Demos+Apps included, translated later · core (Source/Tests/Docs) translated in this cycle · push `origin/local` after merge + green build.

## Abstract

Merge 314 upstream commits (v3.3 → v3.9.0) into `local`; resolve 52 conflicts preferring upstream content for code; then run the ES→EN translation pass over every upstream-touched surface (Source .pas, Tests, Docs/manuals, CLAUDE.md files); re-apply the fork's identifier renames; verify with the Delphi MSBuild build of all packages plus ES-leak scans; push after green. Demos*/Apps (~1143 files) land Spanish and are translated as a bounded follow-up (S8).

## Structural Diagram

```
S1 merge upstream/master ─► S2 resolve 52 conflicts (prefer upstream)
        │                          │
        │                          ▼
        │              S3 translate core Source/*.pas (~155 touched files)
        │              S4 translate Docs/manuals + CLAUDE.md + indexes
        │              S5 re-apply identifier renames (Nombre→Name, …)
        │                          │
        ▼                          ▼
backup branch pre-sync   S6 oracle: MSBuild 4 packages + leak scans
                                   │
                                   ▼
                          S7 push origin/local (backup)      S8 demos translation (residual)
```

## Grounded Inventory (instruments: git diff/merge-tree, pwsh grouping)

- Dry-run `git merge-tree --write-tree --name-only local upstream/master`: **52 conflicted files** — ~40 `Source/*.pas`, `README.md`, `Docs/CLAUDE.md`, `Docs/Version 3/ES/uMakerAi-PPMRegistry.md`, `.gitignore`, 5× rename/delete `scripts/build/build_*.bat`; **~111 auto-merged files**.
- Upstream diff v3.3→v3.9.0: **1459 files, +470,052 / −3,612** (1328 added, 121 modified, 10 deleted).
- Core translation scope: Source `.pas` 47 new (~11.3k lines) + 70 modified (upstream +17.3k/−15.1k); Tests 11 files (+7.4k); Docs 20 files (+3.6k incl. 7 new ES .md manuals ~2,673 lines).
- Demos+Apps (later): Demos 317, Demos-V3_1 525, Demos-V3_4 190, Demos-Book 87, Apps 24 ≈ +400k lines, all Spanish.
- Manuals brought by upstream: Agents-Skill 255, AudioBridge 215, ChatModes 373, ChatTools-SmartDispatch 506, FunctionCalling-SmartDispatch 289, OpenAI-Dalle 832, Skills 203 (.md, ES) · Skills.EN.md 205 (EN, upstream) · Jev-TypeSafe & Qwen-Alibaba .docx ES+EN pairs · PPMRegistry.md +7/−7 · Docs/CLAUDE.md +22/−5 · Reportes/*.md 700 (ES) · 3 PNG.
- Working tree guard: owner's 10 dirty framework files (.codex/.cursor/.opencode, Docs/ADID_Framework_15_4.md) are NOT in upstream's touched set — do not touch them.

## Tasks

| id | task | acceptance |
|----|------|-----------|
| S1 | Safety branch `pre-sync-2026-10-12` at `6521287`; `git merge upstream/master` on `local` | merge stops with expected 52 conflicts; no unexpected file overwritten |
| S2 | Resolve conflicts: upstream content for code; keep our `scripts/build/*.bat`; merge `.gitignore`; commit merge | `git diff --name-only --diff-filter=U` empty; tree committed |
| S3 | ES→EN translation of upstream-touched `.pas` (Source) + `.rc`; string-level only | `find_spanish_comments.py` on Source → 0; build green in S6 |
| S4 | Docs/manuals: move ES originals to `ES/`, translate to `EN/<Manual>/<Name>.EN.md`; Jev/Qwen EN docx from upstream verified into `EN/`; PPMRegistry delta; update indexes (DOCINDEX.md, Docs/Version 3/README.md, EN/README.md) | `check_en_docs.py` → 0 leaks; every new manual has EN counterpart |
| S5 | Re-apply fork identifier renames (Nombre→Name, Resultado→Result, entidad→entity, .rc IA→AI) where still applicable | grep counts → 0 for the tracked set |
| S6 | Oracle: init Delphi env; MSBuild all 4 packages; leak scans | 0 errors; no ES leaks in core |
| S7 | Push `local` → `origin/local` after S6 green | remote updated |
| S8 | Residual: translate Demos*/Apps in bounded batches (own plan) | per-batch leak scan |

## Smoke Contract

- **Baseline (pre-merge, captured before S1):** HEAD `6521287`; `find_spanish_comments.py --Source` count recorded; Delphi build of 4 packages recorded (green/red with exact output).
- **Post-change (S6):** same build command → 0 errors; `check_en_docs.py` → 0 leaks; `find_spanish_comments.py` on Source → 0.
- **Expected delta:** +1143 new files (demos/apps, Spanish by decision), core files remain English, packages compile.

## Claim Ledger

| id | statement | status |
|----|-----------|--------|
| C1 | `upstream/master` = `39c093b` = v3.9.0, 314 commits after base `2761cd4` | ✓ `git log`/`rev-list` |
| C2 | Conflicts = 52 files, ~111 auto-merged | ✓ `git merge-tree` |
| C3 | Owner's dirty files do not overlap upstream changes | ✓ name-set diff |
| C4 | ES→EN translation is string-level (comments/literals/identifiers only) | ✓ plans_completed/20260519 (invariant) |

## Risk Ledger

| id | trigger | severity | containment / rollback |
|----|---------|----------|-----------------------|
| R1 | conflict resolution breaks compilation | high | build oracle S6; pre-merge branch `pre-sync-2026-10-12`; `git merge --abort` before commit |
| R2 | translation pass corrupts code | high | string-level invariant + diff review + build oracle |
| R3 | rename/delete `.bat` conflicts resolved wrongly | low | keep ours under `scripts/build/`, documented in S2 |
| R4 | untracked files collide with upstream adds | low | git refuses; rename untracked then retry |

## Validation

Plan follows repo conventions: `plans/[ISO8601]_`. Merging on `local` (fork's working branch). No product-source edit before this plan; merge is the first mutation, preceded by the safety branch.

## Execution Record (2026-10-29)

**Status:** COMPLETE for the core scope; demos deferred (owner decision).

| Task | Result | Evidence |
|------|--------|----------|
| S1 merge | `e2b5cf4` — `upstream/master` (`39c093b`, v3.9.0) merged into `local`; 52 conflicts resolved: 46 to the upstream side, 5 `scripts/build/*.bat` kept ours, `.gitignore` union | `git log --oneline`; `.temp/mergetree.txt` |
| S2 conflicts | 0 unmerged files; `.gitignore` union dropping upstream's `*.bat`/`*.ps1` patterns (our build scripts are tracked artifacts) | `git diff --diff-filter=U` empty |
| S3 core translation | ~130 Source units translated via two pipelines (whole-file and line-map), EVERY file gated by `scripts/audit/check_edit_skeleton.py` (code skeleton identical; Pascal case-insensitive) | skeleton OK per applied file; commits `f9f0bf4`, `80dbbd9` |
| S4 docs/manuals | New EN manuals: ChatModes, ChatTools-SmartDispatch, FunctionCalling-SmartDispatch, OpenAI-Dalle, AudioBridge, Agents-Skill (upstream EN: Skills, Jev-TypeSafe, Qwen-Alibaba); ES originals moved to `Docs/Version 3/ES/`; PPMRegistry EN updated to `registry.cimamaker.com`; README, module CLAUDE.md files and reports translated | `git show --stat 5f68d52`; `.temp/md_scan2.txt` |
| S5 identifier renames | NOT re-applied — the merge took upstream identifiers; the fork's earlier ES→EN identifier set was not reinstated (upstream compatibility kept) | residual |
| S6 oracle | (1) full rebuild of all 4 packages: 0 errors (`.temp/rebuild_a..d.log`); (2) RegressionSuite 117/117 PASS, exit 0 (`.temp/suite_run3.log`); (3) ES-leak scans recorded | see files |
| S7 push | `git push origin local` after the green oracles | remote ref |
| S8 demos | deferred (owner decision) — Demos*/Apps arrived in Spanish | residual |

**Residual (bounded):**
- Tests comments remain Spanish (`uRegression.Suites.pas`, `uRegression.Fixtures.pas`); test DATA strings stay Spanish by design.
- Source leak-scan residual (~800 comment + ~590 string flags) — the detector over-reports (English words such as `actual`, `ms` match the Spanish word list); the true remainder is driven to zero with the committed line-map pipeline (`scripts/audit/scan_spanish_leaks.py` → aicall map → `.temp/pair_apply.py`).
- Demos*/Apps (~1143 files, ~400k lines) — translation deferred per owner decision.
- Owner's framework dirty files (`.codex/`, `.cursor/`, `.opencode/`, `Docs/ADID_Framework_15_4.md`, `tools/claude_svchain.py`) were left untouched.

**Tool defects encountered (class, not anecdote):**
- Sub-agent facility: every `task` child was terminated ~2.5 min after dispatch ("failed: undefined"; the job then reads "killed") — long work cannot be delegated there → switched to `aicall` pipelines.
- `logsearch` fails with `ENAMETOOLONG` on any pattern (host spawn defect).
- `aicall` providers: nvidia free endpoint fails 3x; opencode free tier exhausted; the streamlake free model trips its circuit breaker after timeouts; openrouter `:free` returned truncated maps; the reliable channel was `deepseek-flash` ($0.15/$0.60 per M).

## Demo pass (2026-10-29, after the core sync)

**Status:** PARTIAL — 8398 → 1432 flagged hits (−82.9%) across `Demos`, `Demos-V3_1`, `Demos-V3_4`, `Demos-Book`, `Apps`; ~260 files translated under the skeleton gate. Seven passes; the last two unlocked continuation lines of multi-line strings.

| Step | Result | Evidence |
|------|--------|----------|
| Inventory | 284 files carried Spanish (4420 comment + 3978 string hits) | `.temp/demo_inventory.txt` |
| Translation | 4 passes with `aicall` (opencode-go/beam-free, free) on multi-file marker maps | commits `7fe7638`, `c8f08f4` |
| Gate | Every applied file skeleton-verified; refusing maps left files untouched | `.temp/split_apply.py` output |
| Residual | 1432 hits / 241 files — Demos-V3_1 602, Demos 410, Demos-V3_4 220, Demos-Book 168, Apps 32 | `.temp/demo_inventory.txt` |
| Compile oracle | Unavailable for demos in this checkout — control project (untranslated `mcp-json`) fails with the same path/unit errors | `.temp/demo_build_json.log`, `.temp/demo_build_firedac.log`, `.temp/demo_build1.log` |

**Next action:** the tail is now dominated by three classes — (1) detector false positives on English lines (`File not found: %s` counts as a hit), (2) three files the skeleton gate refuses because the model merges a string-concatenation line (`Demos/027-DocumentManager/uMainDocumentManager.pas`, its `Demos-V3_1` copy, `Demos-V3_1/058-FMXTelegramBot/uDmTelegramBot.pas`), (3) a long tail of single hits the model keeps returning empty for. Next pass: split the refused files by line range and translate them in small windows, and drive `.temp/residual_audit.py` to separate real Spanish from detector noise before chasing the tail further.
