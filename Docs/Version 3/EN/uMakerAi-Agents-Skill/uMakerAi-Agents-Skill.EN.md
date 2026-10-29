# TAiSkill — Reusable skills for LLM agents

## Purpose

`TAiSkill` is a reusable configuration container for LLM nodes (`TLLMNode`) in the MakerAI agent system. It gathers an agent's personality into a single object: its instructions (system prompt), the suggested driver and model, the API key, and the list of tools it should have available.

The core idea is to separate **what a node does** (its purpose, its personality) from **where it lives** (which graph, with which model, with which additional tools). A skill is defined once — on disk or in the PPM registry — and reused across multiple nodes or projects.

> **v3.8:** `TAiSkill` understands the **SKILL.md** format (the Agent Skills format and the one published by PPM) in addition to its own JSON; `FromPPM` downloads from the real registry, and the combination with the node was rewritten (see [Combination rules](#combination-rules)). Before v3.8, `FromPPM` did not work and the skill's `DriverName` was never applied.

---

## Involved files

| File | Role |
|---|---|
| `Source/Agents/uMakerAi.Agents.Skill.pas` | `TAiSkill` |
| `Source/Agents/uMakerAi.Agents.Node.LLM.pas` | `TLLMNode` with the `Skill` property, `ResolveConfig` and `ConfigureChat` |
| `Source/Core/uMakerAi.Skills.Format.pas` | SKILL.md parser (`TAiSkillDoc`) and PPM registry client (`TAiPPMClient`), shared with `TAiPrompts` |

---

## Formats

### 1. SKILL.md (recommended)

A Markdown file with a YAML *frontmatter* block at the top. It is the format of Claude's Agent Skills and of the `skill` packages in the PPM registry, so the same file works in MakerAI, Claude Code, and PPM.

```markdown
---
name: revisor-delphi
description: Reviews Delphi code for bugs and bad practices.
model: claude-sonnet-5
allowed-tools:
  - filesystem
  - git
driver: Claude          # MakerAI extension (optional)
---

You are an expert Delphi code reviewer. Analyze the code you are given and
identify logic bugs, memory leaks, and violations of best practices.
Respond in Spanish with a list of findings ordered by severity.
```

| Frontmatter | Property | Notes |
|---|---|---|
| `name` | `Name` | If missing, the folder (or file) name is used |
| `description` | `Description` | For documentation; not sent to the LLM |
| `model` | `Model` | See [Combination rules](#combination-rules) |
| `allowed-tools` | `ExtraTools` | `- x` list or inline `a, b` / `[a, b]` |
| `driver` | `DriverName` | MakerAI extension; Agent Skills do not have it |
| *body* | `SystemPrompt` | Everything after the second `---` |

**A SKILL.md never supplies an `ApiKey`**, even if it carries an `apikey:` key. This is content that can come from third parties (the registry, a shared folder): if it could set the key, a malicious skill could request `@ANY_VARIABLE` and the node would send that secret to the provider.

`allowed-tools` names that do not exist in the `TAiToolRegistry` are ignored when loading tools. This is normal for skills written for Claude Code, which declare `Read`, `Grep`, or `Bash`.

### 2. Own JSON (developer files)

The original format of `TAiSkill`. It is kept for local files and is the **only** one that accepts `apiKey`, because it is the developer's own file.

```json
{
  "name":         "sql-expert",
  "description":  "SQL expert",
  "driverName":   "OpenAI",
  "model":        "gpt-5.6",
  "apiKey":       "@OPENAI_API_KEY",
  "systemPrompt": "You are an SQL expert...",
  "extraTools":   ["database"]
}
```

---

## Loading skills

| Method | Format | Source |
|---|---|---|
| `TAiSkill.FromPPM('skill-code-review')` | SKILL.md | PPM registry |
| `TAiSkill.FromFolder('Skills\revisor')` | SKILL.md | Folder containing `SKILL.md` |
| `TAiSkill.FromSkillFile('Skills\revisor\SKILL.md')` | SKILL.md | File |
| `TAiSkill.FromFile(path)` | depends on the path | Folder or `.md` → SKILL.md; any other file → JSON |
| `TAiSkill.FromJSON(text)` | JSON | Text in code |
| `Skill.LoadFromSkillText(text)` | SKILL.md | Text in code |

All of them raise `EAiSkillError` on failure, with a message explaining what happened (file not found, package does not exist, package is not a skill, etc.).

### From the PPM registry

```pascal
Node.Skill := TAiSkill.FromPPM('skill-code-review');
Node.Skill := TAiSkill.FromPPM('code-review');   // also tries 'skill-code-review'
```

- Default registry: `https://registry.cimamaker.com`. For another one, pass it as the second parameter: `FromPPM('my-skill', 'https://my-registry.local')`.
- With no version, the **highest non-yanked version** (by semver) is used. To pin one: `FromPPM('skill-code-review', '', '1.0.0')`.
- `Skill.Version` and `Skill.SourcePath` tell you what was downloaded and from where.
- To browse available skills: `ppm search --type skill`, or `TAiPrompts.SearchPPM('', 'skill')`.

> Watch the names: PPM has packages of type `prompt` and of type `skill`. `code-reviewer` is a **prompt**, so `FromPPM('code-reviewer')` fails with *"it is of type prompt, not a skill"*; the equivalent skill is `skill-code-review`.

`FromPPM` performs a synchronous HTTP request. To avoid blocking the UI, load the skill on a thread and assign it afterwards:

```pascal
TTask.Run(procedure
begin
  var Skill := TAiSkill.FromPPM('skill-code-review');
  TThread.Queue(nil, procedure
  begin
    Node.Skill := Skill;
  end);
end);
```

### From a skills folder

```text
MyApp/
  Skills/
    revisor-delphi/
      SKILL.md
    sql-expert/
      SKILL.md
    traductor.json        ← own JSON, also valid
```

```pascal
NodeA.Skill := TAiSkill.FromFolder('Skills\revisor-delphi');
NodeB.Skill := TAiSkill.FromFile('Skills\traductor.json');
```

---

## Integration with TLLMNode

`TLLMNode` exposes `Skill: TAiSkill` in its `public` section (it is not stored in the DFM).

**Memory management:** the node takes ownership of the skill. When a new one is assigned, the previous one is released; the active one is released in the node's destructor. Do not share the same instance between two nodes (it would be a double-free): load one per node.

```pascal
Node.Skill := TAiSkill.FromFolder('Skills\revisor');   // the node is the owner
Node.Skill := TAiSkill.FromPPM('skill-code-review');    // releases the previous one
Node.Skill := nil;                                      // no skill
// Skill.Free;  ← NEVER with a skill assigned to a node
```

---

## Combination rules

`TLLMNode.ResolveConfig` combines the node's properties with the skill's. `DoExecute` uses it (via `ConfigureChat`) to configure the chat for each run, and it can be called directly to see what configuration will come out.

| Field | Rule |
|---|---|
| `DriverName` | The node's. If empty, the skill's. If neither, `'Claude'`. |
| `Model` | The node's. If empty, the skill's **only if it belongs to the effective driver**: same `DriverName`, or neither set a driver. Otherwise, the driver's default. |
| `ApiKey` | The node's. If empty, the skill's (JSON only). |
| `SystemPrompt` | **Concatenated**: the skill's first (base instructions), then the node's (adjustments for that node), separated by a blank line. |
| `ServiceURL`, `MaxTokens` | Node only. |

> **Behavior change in v3.8:** `TLLMNode.DriverName` defaults to `''` (previously `'Claude'`). Without a skill nothing changes, because the result is still `'Claude'`. With a skill, the skill's driver is now actually used; before, the constructor's fixed `'Claude'` always overwrote it. Existing DFMs store `DriverName = 'Claude'` explicitly and behave as before.

### Examples

| Skill | Node | Result |
|---|---|---|
| `OpenAI` / `gpt-5.6` / `@K` | empty | `OpenAI` / `gpt-5.6` / `@K` |
| `OpenAI` / `gpt-5.6` / `@K` | `DriverName := 'Claude'` | `Claude` / Claude default / `@K` — `gpt-5.6` is not inherited |
| `OpenAI` / `gpt-5.6` | `Model := 'gpt-5.4'` | `OpenAI` / `gpt-5.4` |
| SKILL.md without driver, `model: claude-opus-4-6` | empty | `Claude` / `claude-opus-4-6` |
| SKILL.md without driver, `model: claude-opus-4-6` | `DriverName := 'OpenAI'` | `OpenAI` / OpenAI default |
| `systemPrompt: "You are a reviewer..."` | `SystemPrompt := 'Review security only.'` | `"You are a reviewer...\n\nReview security only."` |

### Tools (ExtraTools)

| `UseAllTools` | `Skill.ExtraTools` | Result |
|---|---|---|
| `True` (default) | any | The entire `TAiToolRegistry` is loaded |
| `False` | empty | No tools are loaded |
| `False` | `['filesystem','git']` | Only `filesystem` and `git` (whichever exist in the registry) |

---

## Usage examples

### Node with a registry skill

```pascal
var
  Manager: TAIAgentManager;
  Node: TLLMNode;
begin
  Manager := TAIAgentManager.Create(nil);
  Node := TLLMNode.Create(Manager);

  Node.Skill := TAiSkill.FromPPM('skill-code-review');   // instructions + model
  Node.ApiKey := '@CLAUDE_API_KEY';                      // the key is set by the node
  Node.SystemPrompt := 'Respond in Spanish.';            // appended to the skill's

  Manager.StartNode := Node;
  Manager.Run('Review this code: ' + MyCode);
end;
```

### Same skill, different provider

```pascal
Node.Skill      := TAiSkill.FromFolder('Skills\revisor-delphi');
Node.DriverName := 'OpenAI';       // the skill's Claude model is not inherited
Node.Model      := 'gpt-5.6';
Node.ApiKey     := '@OPENAI_API_KEY';
```

### Graph with multiple personalities

```pascal
NodeA.Skill := TAiSkill.FromFolder('Skills\optimista');
NodeB.Skill := TAiSkill.FromFolder('Skills\critico');
// Same driver for both (configured on each node), different instructions
NodeA.DriverName := 'Claude';
NodeB.DriverName := 'Claude';
```

### Inspect the configuration before running

```pascal
var Cfg := Node.ResolveConfig;
Writeln(Cfg.DriverName, ' / ', Cfg.Model);
```

---

## Relationship with other components

| Component | Purpose |
|---|---|
| `TAiSkill` + `TLLMNode` | The **fixed** personality of an agent node |
| `TAiPrompts.LoadSkillFromPPM` | Fetch a skill's text as a template for manual use |
| Agent Card A2A skills (`TAiA2AServer.Skills`) | Describe outward what an agent can do; they do not execute anything |

---

## Thread safety

`TAiSkill` is a plain data object with no synchronization. It is configured **before** the graph runs and is not modified during execution. `TLLMNode` reads it without modifying it on every `DoExecute`.

---

## Implementation notes

- `TAiSkill` does not inherit from `TPersistent` or `TComponent`: it is a pure runtime object, which is why `TLLMNode.Skill` is `public`.
- The SKILL.md parser lives in `uMakerAi.Skills.Format` and is the same one used by `TAiPrompts` and the rest of the framework. It understands the YAML that real skills use: scalars (quoted or with a `#` comment), lists, and `|` / `>` blocks.
- `ExtraTools` uses `dupIgnore` and `CaseSensitive=False`.
- Regression tests live in `Tests/RegressionSuite` (`skills.*` cases, no network: the registry is a fake server).
