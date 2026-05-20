# Plan: Translation Completion — Unified Batch (Plan C + Full P3)

**Date:** 2026-05-19  
**Project:** MakerAI v3.3 (Delphi Pascal)  
**Parent Plan:** `plans/20260509_language_conversion_and_docs.md`  
**Scope:** Complete ALL remaining Spanish-to-English translation across 94 `.pas` source files, author headers, mojibake, strings, identifiers, and comments in a single unified session.

---

## Abstract Definition

The prior translation effort (2026-05-09, P0-P3) completed ~80% of the work but left four categories of stragglers:

1. **Mojibake**: Garbled characters (`Enr�quez`, `cach?`, `n�mero`) from UTF-8 BOM conversion that left Windows-1252-interpreted byte sequences in ~72 author headers, 4 copyright lines, and ~50 comment lines
2. **P0 Straggler Strings**: ~36 Spanish error/exception/user-message strings across ~16 files still in Spanish
3. **P2 Identifier Remnants**: `Nombre` parameter not fully migrated in `uMakerAi.Tools.Functions.pas` (9 occurrences) and `uMakerAi.Prompts.pas` (~20 occurrences)
4. **P3 Spanish Comments**: ~5,000+ comment lines across ~85 files never translated from ES to EN

This plan defines a unified batch operation using parallel `general` sub-agents to complete all four categories, followed by Delphi MSBuild verification.

**Invariant**: All modification is string-level (comments, literals, docstrings). No logic, API signatures (beyond parameter renames), or functionality changes. The build before and after must produce identical BPL bytecodes.

---

## Structural Diagram

```
                        INPUT (94 .pas files)
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
    ┌───────────────────┐ ┌──────────┐ ┌─────────────────┐
    │  Batch 1 (general)│ │ Batch 2  │ │  Batch 3         │
    │  Author Headers   │ │ (general)│ │  (general)       │
    │  + Mojibake Fix   │ │P0 Strings│ │  P2 Identifiers  │
    │  ~72 files        │ │~16 files │ │  2 files         │
    └────────┬──────────┘ └────┬─────┘ └────────┬────────┘
             │                 │                │
             └─────────────────┼────────────────┘
                               ▼
                ┌──────────────────────────────┐
                │  Batch 4a (general)           │
                │  P3 Comments: Core+Chat+Tools │
                │  ~40 files                    │
                └──────────────┬───────────────┘
                               │
                ┌──────────────┼───────────────┐
                ▼              ▼               ▼
    ┌───────────────────┐ ┌──────────┐ ┌─────────────────┐
    │  Batch 4b (general)│ │ Batch 4c │ │  Batch 5         │
    │  Agents+RAG+       │ │ (general)│ │  (general)       │
    │  Embeddings ~30    │ │MCPServer+│ │  Docs Parity     │
    │  files             │ │MCPClient │ │  Verification    │
    │                    │ │+ChatUI+  │ │                  │
    │                    │ │Utils+    │ │                  │
    │                    │ │Design ~25│ │                  │
    └────────┬───────────┘ └────┬─────┘ └────────┬─────────┘
             │                  │                 │
             └──────────────────┼─────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │  Verification Gate    │
                    │  MSBuild all 4 pkgs   │
                    │  0 errors required    │
                    └───────────────────────┘
```

**Parallelism**: Batches 1, 2, 3 launch simultaneously (independent file sets). Batches 4a, 4b, 4c launch simultaneously (independent module groups). Batch 4 starts after batch 3 completes (depends on P2 changes in `Functions.pas`). Batch 5 runs after all prior complete. Verification runs last.

---

## Input/Output Parameters

| Parameter | Type | Current | Target |
|-----------|------|---------|--------|
| Author headers in Spanish | comments in ~72 files | `// Nombre: Gustavo Enr�quez` + Spanish contact | `// Author: Gustavo Enriquez` + English contact |
| Mojibake characters | encoding artifacts | ~600 char instances (`�`, `?`) across headers, copyrights, comments | 0 |
| P0 Spanish error strings | string literals | ~36 Spanish strings in ~16 files | 0 (all English) |
| P2 Spanish identifiers | Pascal names | `Nombre` param in 2 files (Functions.pas + Prompts.pas) | `Name` |
| P3 Spanish comments | code comments | ~5,000+ lines in ~85 files | 0 (all English) |
| Build status | compiler | All packages build, 0 errors, 66 warnings | All packages build, 0 errors, unchanged warnings |
| `project_progress.md` | metadata | Out of date | Updated with final audit |

---

## Work Units (Subtasks)

### Sub 1: Author Header Standardization + Mojibake Fix

**File:** `plans/20260519_sub1_author_headers_mojibake.md`

**Abstract**: Every `.pas` file has an author header block at lines ~5-32. ~90 of these contain mojibake characters and Spanish labels. Fix all in one batch.

**Files**: All 106 `.pas` files with author header blocks, prioritized:
- ~57 files with `Enr�quez` pattern (replacement char)
- ~10 files with `Enr?quez` pattern (question mark)
- ~5 files already correct (`Enriquez`)
- ~4 copyright lines with mojibake: `Copyright (c) 2013 Gustavo Enr?quez - CimaMaker`
- 1 special format: `Utils/uMakerAi.Utils.Python.pas:119` `AUTOR: Gustavo Enr?quez`

**Operations per file**:
1. Replace `// Nombre: Gustavo Enr�quez` / `// Nombre: Gustavo Enr?quez` with `// Author: Gustavo Enriquez`
2. Replace `// - Email:` with `// Email:`
3. Replace `// - Telegram:` with `// Telegram:`
4. Replace `// - LinkedIn:` with `// LinkedIn:`
5. Replace `// - GitHub:` with `// GitHub:`
6. Fix copyright line mojibake: `Copyright (c) 2013 Gustavo Enr?quez - CimaMaker` → `Copyright (c) 2013 Gustavo Enriquez - CimaMaker` (in `Core/uMakerAi.Chat.pas`, `Chat/uMakerAi.Chat.OpenAi.pas`, `Tools/uMakerAi.Tools.TextEditor.pas`, `Core/uMakerAi.Chat.Bridge.pas`)
7. Fix `Utils/uMakerAi.Utils.Python.pas:119`: `AUTOR: Gustavo Enr?quez` → `AUTHOR: Gustavo Enriquez`
8. Fix other mojibake in comments: `n�mero`→`número`, `a�adir`→`añadir`, `cach?`→`caché`, `c?digo`→`código`, `�rea`→`área`, `�xito`→`éxito`, `M?todo`→`Método`, `m?tricas`→`métricas`, `configuraci?n`→`configuración`, `conversi?n`→`conversión`, `descripci?n`→`descripción`, `posici?n`→`posición`, `selecci?n`→`selección`, `implementaci?n`→`implementación`, `sincronizaci?n`→`sincronización`, `conexi?n`→`conexión`, `traducci?n`→`traducción`, `validaci?n`→`validación`

**Verification**: `rg "Enr�quez|Enr\?quez|a�adir|cach\?|c\?digo" Source/` returns 0 results.

---

### Sub 2: P0 Straggler String Translation

**File:** `plans/20260519_sub2_p0_straggler_strings.md`

**Abstract**: Translate remaining Spanish runtime strings and comment-strings to English.

**Files + mappings**:

| # | File | Old (ES) | New (EN) |
|---|------|----------|----------|
| 1 | `VoiceMonitor.pas` | `'Error al abrir dispositivo de audio: '` | `'Error opening audio device: '` |
| 2 | `VoiceMonitor.pas` | `'Error al iniciar la captura de audio: '` | `'Error starting audio capture: '` |
| 3 | `VoiceMonitor.pas` | `'Error al abrir dispositivo de audio (Code: ` | `'Error opening audio device (Code: ` |
| 4 | `VoiceMonitor.pas` | `'Error al preparar el header de audio: '` | `'Error preparing audio header: '` |
| 5 | `VoiceMonitor.pas` | `'Error al a�adir buffer de audio: '` | `'Error adding audio buffer: '` |
| 6 | `VoiceMonitor.pas` | `'No se pudo inicializar AudioRecord.'` | `'Failed to initialize AudioRecord.'` |
| 7 | `ChatInput.pas` | `'Error al cargar la imagen: '` | `'Error loading image: '` |
| 8 | `ChatInput.pas` | `'Error al procesar el archivo: '` | `'Error processing file: '` |
| 9 | `Chat.Mistral.pas` | `'Error al obtener URL firmada: %d - %s'` | `'Error getting signed URL: %d - %s'` |
| 10 | `Chat.Ollama.pas` | `'Error al copiar el modelo: %d - %s'` | `'Error copying model: %d - %s'` |
| 11 | `Chat.Ollama.pas` | `'Error al crear el modelo: %d - %s'` | `'Error creating model: %d - %s'` |
| 12 | `Chat.Ollama.pas` | `'Error al eliminar el modelo: %d - %s'` | `'Error deleting model: %d - %s'` |
| 13 | `Chat.Claude.pas` | `'Error al obtener modelos de Claude: %d - %s'` | `'Error getting Claude models: %d - %s'` |
| 14 | `Chat.Claude_beta.pas` | `'Error al obtener modelos de Claude: %d - %s'` | `'Error getting Claude models: %d - %s'` |
| 15 | `Chat.Cohere.pas` | `'Error al obtener la lista de modelos de Cohere: %d - %s'` | `'Error getting Cohere model list: %d - %s'` |
| 16 | `Tools.Functions.pas` | `'Error al procesar JSON: '` | `'Error processing JSON: '` |
| 17 | `Tools.TextEditor.pas` | `'Error al aplicar diff: '` | `'Error applying diff: '` |
| 18 | `Chat.OpenAi_Deprecated.pas` | `'Error al procesar la propiedad Tools: '` | `'Error processing Tools property: '` |
| 19 | `Chat.OpenAi_Deprecated.pas` | `'Error al parsear la respuesta del endpoint /v1/responses: '` | `'Error parsing /v1/responses endpoint response: '` |
| 20 | `Chat.OpenAi.pas` | `// Mensaje de éxito o descripción del error` | `// Success message or error description` |
| 21 | `Core.Chat.pas` | `'[Transcripción de audio]'` | `'[Audio transcription]'` |
| 22 | `MCPClient.Core.pas` | `// No se pudo lanzar el servidor local` | `// Failed to launch local server` |
| 23 | `RAG.Graph.Core.pas` | `// No se puede continuar si el paso anterior no arrojó resultados` | `// Cannot continue if previous step returned no results` |
| 24 | `Agents.pas` | `// No se pueden serializar objetos complejos` | `// Complex objects cannot be serialized` |
| 25 | `Functions.pas` | `'SaveMCPConfig: Error al guardar: '` | `'SaveMCPConfig: Error saving: '` |
| 26 | `Functions.pas` | `// Caso 3: Es un valor simple (string, número, etc.). No se hace nada.` | `// Case 3: Simple value (string, number, etc.). Do nothing.` |
| 27 | `Functions.pas` | `// Formato no reconocido` | `// Unrecognized format` |

**Additional strings found during validation** (not in original list):

| 28 | `VoiceMonitor.pas:1457` | `'Permiso para grabar audio denegado.'` | `'Audio recording permission denied.'` |
| 29 | `VoiceMonitor.pas:1491` | `'Excepción al iniciar captura en Android: '` | `'Exception starting capture on Android: '` |
| 30 | `Chat.Mistral.pas:441` | `'Se necesita un TAiMediaFile con contenido para subir.'` | `'A TAiMediaFile with content is needed for upload.'` |
| 31 | `Chat.Mistral.pas:1013` | `'Se requiere un TAiMediaFile para el proceso de OCR.'` | `'A TAiMediaFile is required for the OCR process.'` |
| 32 | `Chat.Mistral.pas:744` | `'La propiedad Tools está mal definida, debe ser un JsonArray'` | `'The Tools property is incorrectly defined, it must be a JsonArray'` |
| 33 | `Chat.Claude.pas:416` | `'Error creando Batch: %d - %s'` | `'Error creating Batch: %d - %s'` |
| 34 | `Chat.Cohere.pas:1130` | `'La lista de documentos para Rerank no puede estar vacía.'` | `'The document list for Rerank cannot be empty.'` |
| 35 | `ChatInput.pas:1380` | `'El portapapeles no contiene contenido compatible.'` | `'The clipboard does not contain compatible content.'` |

**Verification**: `rg "Error al|No se pudo|No se puede|No se pueden|Formato no reconocido|Se necesita|Se requiere|La lista|está mal|El portapapeles|Permiso para" Source/` returns 0 results on string literals.

---

### Sub 3: P2 Identifier Migration (Nombre → Name)

**File:** `plans/20260519_sub3_p2_identifiers.md`

**Abstract**: Complete the `Nombre` → `Name` parameter rename in `uMakerAi.Tools.Functions.pas` AND `uMakerAi.Prompts.pas`. These two files have almost identical public APIs using `Nombre` as a parameter name.

**File 1**: `Source/Tools/uMakerAi.Tools.Functions.pas`
**File 2**: `Source/Core/uMakerAi.Prompts.pas`

**Occurrences** (all in `TFunctionActionItems` class):
```pascal
Line 183:     Function IndexOf(Nombre: String): Integer;           → IndexOf(Name: String)
Line 184:     Function GetFunction(Nombre: String): ...;            → GetFunction(Name: String)
Line 185:     Function AddFunction(Nombre: String; ...);            → AddFunction(Name: String)
Line 700: function TFunctionActionItems.AddFunction(Nombre: String; ...);  → AddFunction(Name: String)
Line 705:   Item.FunctionName := Nombre;                           → Item.FunctionName := Name;
Line 728: function TFunctionActionItems.GetFunction(Nombre: String): ...;  → GetFunction(Name: String)
Line 734:   I := IndexOf(Nombre);                                  → I := IndexOf(Name);
Line 776: function TFunctionActionItems.IndexOf(Nombre: String): Integer;  → IndexOf(Name: String)
Line 785: If ... (AnsiUpperCase(Nombre) = AnsiUpperCase(Item.FunctionName)) ... → (AnsiUpperCase(Name) = AnsiUpperCase(Item.FunctionName))
```

**File 2 — Prompts.pas**: `TAiPrompts` class has the same pattern (~20 occurrences):

```pascal
Property Nombre: string;                           → Property Name: string;
Function IndexOf(Nombre: String): Integer;          → IndexOf(Name: String)
Function GetString(Nombre: String): string;         → GetString(Name: String)
Function AddString(Nombre: String; ...);            → AddString(Name: String)
Function GetTemplate(Nombre: String; ...);          → GetTemplate(Name: String)
// All internal uses of the Nombre parameter       → Name
```

**Also check**: Call sites of these methods across all files (search for `IndexOf(`, `GetString(`, `AddString(`, `GetTemplate(` callers).

**Verification**: `rg "\bNombre\b" Source/ --include='*.pas'` returns 0 results in identifier/parameter context (false positives in comments tolerated since Sub 1 handles those).

---

### Sub 4: P3 Spanish Comment Translation

**Abstract**: Translate all remaining Spanish code comments to English across ~85 `.pas` files (~5,000+ comment lines). Execute in 3 parallel batches.

**Module Batches**:

| Batch | Modules | Files | Est. Spanish Comment Lines |
|-------|---------|-------|---------------------------|
| 4a | Core (11), Chat (18), Tools (16) | ~40 | ~2,200 |
| 4b | Agents (11), RAG (12), Embeddings (11) | ~30 | ~1,500 |
| 4c | MCPServer (6), MCPClient (1), ChatUI (4), Utils (4), Design (8) | ~23 | ~1,300 |

**Translation rules**:
1. Translate Spanish to English, preserving technical accuracy
2. Keep Pascal variable/type names in comments unchanged (they're in English already)
3. Preserve formatting: same line position, same `//` or `{ }` or `(* *)` style
4. Do NOT change string literals, function names, or runtime behavior
5. For unclear comments, flag as `[TODO: VERIFY]`

**Verification**: Delphi MSBuild compilation produces 0 errors for all 4 packages.

---

### Sub 5: Documentation Parity Fix + Final Audit

**Abstract**: Clean up documentation directory structure, verify EN coverage, update project_progress.md.

**Operations**:
1. Fix `Docs/Version 3/ES/RAG/uMakerAi-Agents.docx` — mis-placed file (Agents content in RAG folder)
2. Verify all 17 ES docs have EN equivalents
3. Update `project_progress.md` with final translation completion status
4. Create DOCINDEX.md if needed

---

### Sub 6: Build Verification Gate

**Abstract**: Run Delphi MSBuild for all 4 packages after all translation changes.

**Command** (via `cmd_runner`):
```
MSBuild Source/Packages/MakerAiGrp.groupproj /p:Config=Release /p:Platform=Win64 /t:Build
```

**Success criteria**: All 4 packages build with 0 errors. Warnings unchanged from baseline (66 pre-existing).

---

## Test Cases (Verification)

| # | Test | Expected |
|---|------|----------|
| 1 | `rg "Enr�quez\|Enr\?quez" Source/` | 0 results |
| 2 | `rg "Error al\|No se pudo" Source/` on string literals | 0 results |
| 3 | `rg "\bNombre\b" Source/` in code context | 0 results |
| 4 | `rg "[áéíóúñÁÉÍÓÚÑ]" Source/` | < 5 results (technical terms only) |
| 5 | MSBuild MakerAiGrp.groupproj Win64 Release | 0 errors |
| 6 | `project_progress.md` updated | All phases complete |

---

## Dependency & Execution Order

```
Phase 1 (parallel):
  Sub 1 (Author headers) ─┐
  Sub 2 (P0 strings)     ─┼─► Phase 2
  Sub 3 (P2 identifiers) ─┘

Phase 2 (await Phase 1, then parallel):
  Sub 4a (P3: Core+Chat+Tools) ─┐
  Sub 4b (P3: Agents+RAG+Emb)  ─┼─► Phase 3
  Sub 4c (P3: MCPServer+...)    ─┘

Phase 3 (await Phase 2):
  Sub 5 (Docs parity + audit)

Phase 4 (await Phase 3):
  Sub 6 (Build verification gate)
```

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Comment translation changes semantics | Low | Each batch sub-agent self-reviews |
| P2 `Nombre`→`Name` breaks callers in Functions.pas AND Prompts.pas | Medium-High | grep all occurrences; search all callers; verify build |
| Files with mixed UTF-8/ANSI break build | Low | Already converted UTF-8 BOM |
| Batch parallelism causes conflicts | Low | Non-overlapping file sets per batch |
| Build verification impossible (no Delphi) | High | Skip gate; rely on syntax correctness |

---

## Status

- [x] Scope assessment (source survey, doc audit)
- [ ] Sub 1: Author header standardization + mojibake fix (~90 files)
- [ ] Sub 2: P0 straggler string translation (~14 files)
- [ ] Sub 3: P2 identifier migration (1 file)
- [ ] Sub 4a: P3 comments — Core + Chat + Tools (~40 files)
- [ ] Sub 4b: P3 comments — Agents + RAG + Embeddings (~30 files)
- [ ] Sub 4c: P3 comments — MCPServer + MCPClient + ChatUI + Utils + Design (~23 files)
- [ ] Sub 5: Documentation parity fix + final audit
- [ ] Sub 6: Build verification gate (MSBuild all 4 packages)
- [ ] Update `project_progress.md`

---

## reproduce:

```yaml
plan: translation_completion_unified_batch
date: 2026-05-19
project: MakerAI v3.3
scope:
  - ~94 .pas source files
  - ~36 Spanish runtime strings + comment-strings
  - ~72 author headers + 4 copyright lines (mojibake + Spanish labels)
  - ~5,000+ Spanish comment lines
  - 2 public API identifier renames (Nombre→Name in Functions.pas + Prompts.pas)
  - Documentation parity verification
verification:
  - rg queries for zero Spanish strings/mojibake in source
  - MSBuild MakerAiGrp.groupproj Win64 Release → 0 errors
target: 0 remaining Spanish content in Source/
```
