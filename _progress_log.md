# Progress Log — MakerAI v3.3

> **Purpose:** Session-by-session activity log with timestamps, reasons, script names, and outputs.
> **Last updated:** 2026-05-20

---
---

## 2026-10-29 — Demo trees English pass (Demos*, Apps)

**Reason:** the v3.9 upstream merge brought the demo trees in Spanish; the fork's rule is English on every maintained surface.

### Done

- Inventoried the demo trees with the committed detector: 284 files carried Spanish text (8398 flagged hits).
- Translated ~250 files with `aicall` (opencode-go/beam-free, free) using multi-file marker maps, applied by `.temp/split_apply.py` under the skeleton gate.
- Four passes: **8398 → 2061 flagged hits (-75.5%)**.

### Verification

- Skeleton gate PASS on every applied file - code tokens unchanged, only comments and string literals.
- Demo compilation is not available in this checkout: translated (`mcp-firedac`) and untranslated (`mcp-json`) projects fail identically with missing-unit/path errors, so the compile failure is inherited.

**Residual:** 2061 flagged hits in 247 files (Demos-V3_1 837, Demos-Book 377, Demos 562, Demos-V3_4 252, Apps 33); the detector also over-reports English text. Next pass: `.temp/demo_inv.py` -> `.temp/build_batches.py` -> dispatch with the same prompt.

**Commits:** `7fe7638`, `c8f08f4`.

**Follow-up passes (same day):** the rule "never touch a continuation line" was the bottleneck — the skeleton gate blanks string contents, so a continuation line IS translatable. Allowing it took the count from 2061 to 1432 flagged hits (**8398 → 1432, −82.9%**; commits `9454bc5` and the pass-7 commit). Residual classes: detector false positives on English, three files the gate refuses because the model merges a concatenation line, and a single-hit tail.

### Round 8 — the three gate-refused files, and two instrument corrections

- Added a line-numbered applier (`.temp/numbered.py emit|apply`): one entry per line NUMBER, so two lines cannot be merged, the original indentation is preserved, and a line whose CONTROL escapes (`#10`) changed is refused individually instead of costing the whole file.
- Closed the three files the marker pipeline could not translate — `Demos/027-DocumentManager/uMainDocumentManager.pas`, its `Demos-V3_1` copy, `Demos-V3_1/058-FMXTelegramBot/uDmTelegramBot.pas`: 0 accent escapes, 0 real Spanish, `skeleton == HEAD` ✓.
- Corrected `scripts/audit/check_edit_skeleton.py`: a `#NNN` character escape between quoted parts is string DATA, so `'jer' + #225 + 'rquico'` and a plain literal are one unit. Qualified by 15 discriminating controls (15/15, `.temp/gate_controls.py`) — identifier, keyword, number, line merge, line split, code-after-string, non-string operand, compiler directive and statement removal are all still refused.
- Corrected `scripts/audit/scan_spanish_leaks.py`: it judged each fragment of a split string separately and reported `Escriba un texto de búsqueda.` as clean, while the user saw Spanish. It now joins the whole visible expression, renders the escapes, and treats an accent escape or a real accented character as a hit on its own. Qualified by 9 controls (9/9, `.temp/detector_controls.py`).
- Consequence found by the corrected scanner: it walks `.pas` only — **16 `.fmx` and 8 `.dfm`** files still carry accented interface text. Tracked as the next unit.
- A defect of my own applier, found and fixed: replacing a line dropped its `\r`, leaving mixed line endings (git showed symmetric 33/33 instead of the 33 lines lost it looked like).

## 2026-10-29 — Upstream Sync v3.3 → v3.9.0 + Full English Pass

**Reason:** Owner decision: update the fork to upstream master (v3.9.0) and keep the whole repository in English.

### Done

- Merged `upstream/master` (`39c093b`, 314 commits) into `local`; resolved 52 conflicts; safety branch `pre-sync-2026-10-12`.
- Translated Source (~130 units) under a string-level invariant verified per file by `scripts/audit/check_edit_skeleton.py`.
- Translated the new manuals, reports, README and module `CLAUDE.md` files; placed upstream docs into `Docs/Version 3/ES/` (archive) and `EN/` (deliverable).
- Updated five regression-suite expectations to the new English messages.

### Verification

- Full rebuild of the four packages: 0 errors.
- Regression suite: **117/117 PASS** (exit 0).
- Leak scans recorded; residual list lives in the plan.

**Commits:** `e2b5cf4` (merge), `ade66df`, `60ceea7`, `f9f0bf4`, `80dbbd9`, `5f68d52`.
**Plan:** `plans/2026-10-12_upstream_sync_v3.9.md`.
## 2026-05-20 — Project Organization (ADID Style Cleanup)

**Reason:** Repository accumulated organizational debt after translation work. Required index files, workspace lanes, and script categorization per ADID conventions.

### Scripts executed

| Script | Purpose | Result |
|--------|---------|--------|
| `git mv` (batch) | Reorganize 19 scripts into 6 subdirs | 19 files moved to translation/, mojibake/, spanish_fix/, audit/, docs/, build/ |
| `git mv` (batch) | Move 2 old plans → plans_completed/ | 2 plans archived |
| `git mv` (batch) | Move .opencode/plans/ translation plan → plans_completed/ | 1 plan archived |
| `git mv` (batch) | Move 5 build_*.bat from root → scripts/build/ | 5 files moved, root cleaned |
| `mkdir` (batch) | Create 4 workspace lanes + 6 script subdirs | 10 new directories |
| Manual write | `index.md` created | 2,500 chars, all root dirs mapped |
| Manual write | `DOCINDEX.md` created | 4,200 chars, 60+ docs indexed |
| Manual write | `_progress_log.md` created | This file |
| Manual write | `_application_workflow_diagram.md` created | Module catalog |

### Verification
- `git status` shows clean renames + new files only
- Root directory reduced from 28 to ~22 entries
- `index.md` verified against actual directory listing

---

## 2026-05-20 — Doc Fixes

**Reason:** 8 EN .docx and 2 .xlsx files had minor Spanish fragments after source code translation complete. Fix via targeted Python script.

### Script: `scripts/docs/fix_docs_spanish.py`
- Fixed 8 .docx files (Installation_EN: 3 paragraphs, 7 others: 1-4 fragments each)
- Fixed 2 .xlsx files (sheet names + cell values translated)
- Verified: 0 leaks in all 15 EN docs after fix
- Commit: `daf6905`

---

## 2026-05-19 — Final `?` Char + Doc Audit

**Reason:** Complete remaining mojibake `?` characters in comments and audit all documentation files.

### Script: `scripts/mojibake/fix_trailing_q.py`
- 1,526 fixes in 51 files (trailing comment `?` characters)

### Script: `scripts/mojibake/fix_last7.py`
- Fixed 7 remaining unique `?` patterns to 0 Spanish `?` characters

### Scripts: `scripts/docs/check_en_docs.py`, `scripts/docs/audit_docs.py`
- Audited all 39 doc files (docx, pdf, xlsx)
- Found: 8 EN .docx with minor fragments, 2 .xlsx with Spanish headers
- All 15 EN .md files: clean

---

## 2026-05-19 — Translation Completion (6 Python passes)

**Reason:** Complete ES→EN translation of all Pascal source comments. See `project_progress.md` for detailed pass breakdown.

### Scripts executed
- `scripts/translation/translate_comments.py` — 968 fixes, 83 files
- `scripts/mojibake/fix_mojibake2.py` — 1,418 fixes, 66 files
- `scripts/mojibake/fix_mojibake3.py` — 70 fixes, 27 files
- `scripts/translation/translate_final.py` — 590 fixes, 75 files
- `scripts/mojibake/fix_final_complete.py` — 1,045 fixes, 70 files
- `scripts/spanish_fix/fix_all_spanish.py` — 603 fixes, 77 files
- `scripts/spanish_fix/fix_trailing_q.py` — 1,526 fixes, 51 files

**Total:** ~5,100 lines translated, Delphi build verified (exit_code=0)

### Commit: `cdc5674`

---

## 2026-05-09 — Initial Setup + Language Assessment

**Reason:** AGENTS.md creation, build fixes, language conversion planning.

See `project_progress.md` for detailed breakdown.
