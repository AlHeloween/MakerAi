# Report to MakerAi — findings from MKAIServer, 2026-08-29

Written from the broker side (`E:\Copilot\MKAIServer`) after a day of production diagnostics. Everything that follows is **measured**, not inferred; each point includes its evidence and how to reproduce it.

Ordered by urgency, not by size.

---

## 0. URGENT — there is an uncommitted fix and it is at risk

```
$ git status --short
 M Source/Chat/uMakerAi.Chat.MakerAi.pas
$ git log --oneline dev..origin/dev
(vacío)
```

The fix for zero usage in the `MakerAi` driver **exists only as a local change in the shared checkout**. It is neither committed nor pushed.

This is not theoretical: today itself, while reverting a failed attempt of mine, I ran `git checkout -- Source/Core/uMakerAi.Chat.pas` in this repo. I named the file one by one, which is why that change was saved. A `git checkout .` or `git reset --hard` would have wiped it without warning.

**Action: commit and push now.** It is the only thing in this report at risk of being lost.

---

## 1. `uMakerAi.Chat.DeepSeek.pas` has the SAME zero-usage bug

It is the exact sibling of the one just fixed in the MakerAi driver, and this one does reach MKAIServer production: `ResApiServer.dpr:87` links the DeepSeek driver.

**Where** — `uMakerAi.Chat.DeepSeek.pas:336-338`, in the synthetic close of the stream:

```pascal
FakeUsage.AddPair('prompt_tokens',     TJSONNumber.Create(0));
FakeUsage.AddPair('completion_tokens', TJSONNumber.Create(0));
FakeUsage.AddPair('total_tokens',      TJSONNumber.Create(0));
```

**Consequence measured today in production**, a real call by the broker with `stream:true` to `mk-deepseek-v4-flash`:

```
46 chunks de salida real
usage en el SSE:  prompt_tokens 0 · completion_tokens 0 · total_tokens 0
facturado:        input 0 · output 0 · cobro $0.000000
```

**It is a money leak**: all DeepSeek streaming traffic is billed at zero. Without streaming, the same model accounts correctly (measured: 18 in / 37 out), so the hole is exclusive to that path.

**How to fix it** — the base class ALREADY does it correctly; you just have to stop duplicating the close. In `uMakerAi.Chat.pas`:

- `:2705-2706` captures the usage from the SSE chunks into `FStreamPromptTokens` / `FStreamCompletionTokens`.
- `:2464-2466` uses them in the synthetic close.
- `:2468-2469` resets them, so that a turn without usage does not inherit the previous one.

It is exactly the three-piece pattern that was applied to the MakerAi driver. Here it is enough to replicate it or, better, to have the driver reuse the base class's close instead of fabricating its own.

**Acceptance criterion:** a call with `stream:true` to a DeepSeek model returns in the last chunk a `usage` with the real tokens, and it matches what the same call without streaming reports.

---

## 2. Inventory: which drivers duplicate the synthetic close

```
uMakerAi.Chat.DeepSeek.pas           <- activo, con el bug (punto 1)
uMakerAi.Chat.MakerAi.pas            <- arreglado, pendiente de commit (punto 0)
uMakerAi.Chat.OpenAi_Deprecated.pas  <- deprecado, probablemente da igual
```

The other drivers use the base class's close and therefore do not suffer from this. The root of the problem is not a one-off oversight: it is that **the synthetic close was copied instead of reused**, so every improvement in the base (`usage`, `finish_reason`, `reasoning_content`) has to be remembered and replicated in three places. If it can be unified, the entire family of bugs is closed in one go.

---

## 3. `finish_reason` hardcoded to `'stop'` in the synthetic close

Same pattern, another field. In the three sites from the inventory, and also in the base class:

```
uMakerAi.Chat.pas:~2484        FakeChoice.AddPair('finish_reason', 'stop');
uMakerAi.Chat.DeepSeek.pas:351 FakeChoice.AddPair('finish_reason', 'stop');
```

Consequence: a response **cut off by `max_tokens`** is presented to the consumer as a clean finish. There is no way to distinguish "it finished speaking" from "it stopped halfway", which is exactly what a client needs to decide whether to retry with more budget or warn the user.

**An honest warning about what did NOT work**, so the same path is not repeated: I tried it this way and failed. I added capture of the real `finish_reason` from the SSE deltas, exposed it as a property, read it in `ParseChat`, and used it in the close. It compiled, deployed, and **changed nothing**: the consumer still saw `stop`. I reverted everything.

What did work was fixing it **outside the library, in the consumer**: MKAIServer reads `choices[0].finish_reason` from the provider's raw JSON in its own streaming bridge. Verified with `completion_tokens` as a witness:

```
max_tokens=40 -> finish=length  completion_tokens=40
max_tokens=60 -> finish=length  completion_tokens=60
```

In other words: the data arrives correctly over the wire, but **something between the synthetic close and the library consumer keeps overwriting it**. I did not find what. If attacking it from inside AiMaker, that is the thread, and it is worth verifying with a real consumer before considering it fixed — it fooled me three times.

---

## 4. `Thinking_tokens` is only populated by two drivers

```
uMakerAi.Chat.Gemini.pas   (6 asignaciones)
uMakerAi.Chat.OpenAi.pas   (2 asignaciones)
```

Claude, DeepSeek, GLM, Kimi, and the others never touch it. I fixed it for the OpenAI dialect in the base class (commit `1f87db9`, see point 5), but **Claude still does not report it**: it parses its own SSE and does not go through there.

Watch out for an accounting detail when touching it: in the OpenAI dialect, reasoning tokens **already come inside `completion_tokens`**, so adding them separately duplicates them. In Gemini it is the opposite: `thoughtsTokenCount` is OUTSIDE `candidatesTokenCount`. That asymmetry cost us an inflated-totals bug in the broker; it is documented in `MKAIServer/database/migrations/migration_025`.

---

## 5. What I ALREADY changed in this repo today — do not redo

Four commits on `dev`, all deployed and verified in production:

| Commit | What |
|---|---|
| `1f87db9` | `ParseChat` captures `reasoning_tokens` from the usage (OpenAI dialect). Previously `Thinking_tokens` was always 0 for GLM, DeepSeek, Kimi, and gpt-oss |
| `89e9bc9` | `DoCallFunction` no longer hijacks tools whose name contains `_99_`. It branched only on `Pos(MCP_TOOL_SEP, Name)`, so a legitimate tool named `alfa_99_beta` was looked up as an MCP server, was not found, and went silent |
| `3ff9631` | Claude driver: do not declare `code_execution` when `web_search_20260209` is present, because Anthropic auto-injects it and rejects the entire request due to duplicate names |
| `9914654` | `ParseChat` stops using reasoning as the response when there are `tool_calls` or `finish_reason='length'` |

The last one deserves a note, because it is from the same family as the rest: the fallback "if `content` is empty, use `reasoning`" makes sense for models that respond only in reasoning, but it sent the model's internal monologue — in English — as if it were the answer to the user. Reproduced stably with Kimi (`content` of 184 chars identical to `reasoning`), and **it was not a GLM problem** even though it was reported as one.

---

## 6. Method note

Three of today's bugs only appeared when verifying after deployment, not before. And twice I accepted a fix that compiled and did nothing. With this library, the only valid test is to measure the effect from a real consumer; the compiler says nothing useful about these failures.

---

*Generated from the MKAIServer session of 2026-08-29. The production evidence is from the SaaS (`api.cimamaker.com`); calera1 was intentionally left with the previous binary because it was in use.*