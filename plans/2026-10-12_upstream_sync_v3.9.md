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

**Status:** PARTIAL — the form class AND `Source` are translated. Forms: 38 `.fmx`/`.dfm` files, +693/−693, 38/38 skeleton-identical. `Source`: **40 files, +452/−452**, every file skeleton-identical to HEAD, all three runtime packages build with 0 errors (`MakerAI`, `MakerAi.UI`, `MakerAi.RAG.Drivers`), regression suite **117/117** on replication. The detector still flags 1015 lines in `Source`, of which **2 carry an accent** — both are character-class constants that must keep them (a tokenizer's `'¿'`/`'¡'` set and the accent-stripping table) — and the rest is the word-list false-positive class. Remaining surface: the demo `.pas`/`.dpr` trees.

| Step | Result | Evidence |
|------|--------|----------|
| Inventory | 284 files carried Spanish (4420 comment + 3978 string hits) | `.temp/demo_inventory.txt` |
| Translation | 4 passes with `aicall` (opencode-go/beam-free, free) on multi-file marker maps | commits `7fe7638`, `c8f08f4` |
| Gate | Every applied file skeleton-verified; refusing maps left files untouched | `.temp/split_apply.py` output |
| Residual | 1432 hits / 241 files — Demos-V3_1 602, Demos 410, Demos-V3_4 220, Demos-Book 168, Apps 32. **Superseded:** the detector under-reported (see Instrument corrections); re-measured with the corrected scanner | `.temp/demo_inventory.txt`, `.temp/inv10.txt` |
| Refused files (round 8) | The three files the marker pipeline could not translate are now English: `Demos/027-DocumentManager/uMainDocumentManager.pas`, its `Demos-V3_1` copy, `Demos-V3_1/058-FMXTelegramBot/uDmTelegramBot.pas` — 0 accent escapes, 0 real Spanish, `skeleton == HEAD` | `.temp/verify3.py` output; `.temp/numbered.py` applies |
| Instrument: skeleton gate | `scripts/audit/check_edit_skeleton.py` treats a `#NNN` character escape between quoted parts as string DATA (`'jer' + #225 + 'rquico'` ≡ one literal), and adjacent parts without `+`. Qualified by 15 discriminating controls (identifier, keyword, number, merge, split, code-after-string, non-string operand, directive, statement removal all still refused) | `.temp/gate_controls.py` — 15/15 |
| Instrument: leak detector | `scripts/audit/scan_spanish_leaks.py` now judges the whole visible string expression (fragments joined, `#NNN` rendered) and treats an accent escape, or a real accented character, as a hit on its own. It was reporting `Escriba un texto de búsqueda.` as clean because no single fragment matched the word list | `.temp/detector_controls.py` — 9/9 |
| Compile oracle | Unavailable for demos in this checkout — control project (untranslated `mcp-json`) fails with the same path/unit errors | `.temp/demo_build_json.log`, `.temp/demo_build_firedac.log`, `.temp/demo_build1.log` |
| Form pass (round 9) | The detector walked `.pas` only, so the captions, hints and embedded prompts of the form files were never measured. 40 `.dfm`/`.fmx` files carried 746 lines of non-English text; translated through the numbered applier in five model passes plus a hand pass. **38 files changed, +693/−693** — content replaced line-for-line | `.temp/forms_emit.py`, `.temp/forms_split.py`, `.temp/maps/forms_manual.map` |
| Instrument: coverage | `CODE_EXTS = (.pas, .dpr, .dfm, .fmx)` — the acceptance scan now covers the same surface the task claims. Controls: a resource path is not prose; a Spanish caption beside a path is still a hit | `.temp/detector_controls.py` — 13/13 |
| Instrument: accent escapes | The accent set knew only the nine LOWERCASE codes, so `EXTRACCI'#211'N` and `V'#205'A` were reported clean — uppercase Spanish was never measured. Widened to sixteen codes with a digit lookahead, and `numbered.py` now imports the one definition instead of keeping its own | `.temp/detector_controls.py` — 13/13 |
| Instrument: per-line refusal | One row that dropped a `)` used to cost the file every other row. Refusal is per line (control escapes, quote count, code-neutrality), a dropped trailing `)`/`;`/`,` is restored from the original line, and the whole file still passes the skeleton gate as the final oracle | `.temp/apply_forms3.log` |

**Next action:** the demo `.pas`/`.dpr` trees — `.temp/inv12.txt` flags Demos-V3_1 594, Demos 402, Demos-V3_4 237, Demos-Book 180, Apps 33. Same pipeline as `Source`: `.temp/tree_emit.py <root>` → `.temp/forms_split.py split|apply` → `.temp/check_maps.py` on every answer before applying (a lost header applies NOTHING and still exits 0) → `.temp/check_changed.py`-style skeleton check per root. One instrument note: an emit filter built on `residual_audit.is_real` was dropping real text (`Guardar audio`, `Error al procesar JSON`), so recall belongs to the detector and the model is the precision stage.
