# Report to MKAIServer — changes in MakerAi, 2026-09-16

Written from the MakerAi side (`E:\Delphi\Delphi13\Compo\FMXCompo\AiMaker`)
for the broker (`E:\Copilot\MKAIServer`). It is the counterpart to
`REPORTE_MKAISERVER_2026-08-29.md`.

Everything below has been **verified against the real APIs** (validation
probes + generation calls), not inferred from documentation.

New commits on `dev` and `master` (same point, fast-forward):

```
fca6aba fix(deepseek): el nombre canonico es deepseek-flash y el gate de thinking no lo cubria
ca175d0 feat(openai): familia gpt-image-2.5 (flare/sunburst)
dc555a3 (tag: v3.7.0)
```

The version **remains 3.7.0 / API_LEVEL 37**: there was no bump, only additive
content on top of the tag.

Ordered by money at risk, not by size.

---

## 1. URGENT — `git pull` + recompile, or DeepSeek bills for unrequested reasoning

`ResApiServer.dpr:87` links `uMakerAi.Chat.DeepSeek.pas`, so this reaches the
broker's production as soon as someone uses the new model name.

**What was happening:** the `thinking` block was sent only if the model started
with `deepseek-v4`:

```pascal
if StartsText('deepseek-v4', LModel) then   // deepseek-flash NO entra
```

DeepSeek renamed the model (see point 2). With the canonical name
`deepseek-flash`, that gate returns False, the driver **does not send
`thinking`**, and the API applies its default, which is **to reason**. Measured
with a raw call without the parameter:
`completion_tokens_details.reasoning_tokens: 157`.

Consequence: a request with `ModelCaps=[]` (fast/economical mode, which is what
the broker wants for the cheap tier) pays for reasoning tokens.

**Already fixed** in `fca6aba`: the decision lives in
`ModelSupportsThinking()` and covers `deepseek-v4*`, `deepseek-flash*`, and the
grace-period aliases (`deepseek-chat`, `deepseek-reasoner`, which also route
to flash).

**Broker action:** `git pull` in the shared checkout and **recompile the
server**. Without recompiling, the fix does not exist for MKAIServer.

Runtime-tested 4/4 after the fix:

| Case | reasoning_content | thinking tokens |
|---|---|---|
| `deepseek-flash` without `cap_Reasoning` | 0 chars | **0** |
| `deepseek-flash` with `cap_Reasoning` (tlLow) | 974 chars | 216 |
| `deepseek-v4-flash` (legacy alias) without cap | 0 chars | 0 |
| `deepseek-v4-pro` with `cap_Reasoning` | 1,437 chars | 336 |

---

## 2. DeepSeek renamed the cheap model: `deepseek-flash`

`GET /models` today returns **only two** models:

```json
["deepseek-flash", "deepseek-v4-pro"]
```

Official docs, verbatim:

> *"Use `deepseek-flash` as the model name. The legacy names
> `deepseek-v4-flash` and `deepseek-v4-flash-vision-exp` are still accepted,
> but the corresponding models have been retired."*

Verified: `deepseek-v4-flash`, `deepseek-chat`, and `deepseek-reasoner` still
respond, and in all three cases the `model` field of the response returns
`deepseek-flash`.

**MakerAi side (already done):** the driver and registry default is
`deepseek-flash`; `deepseek-v4-flash` is registered as a legacy alias so
existing DFMs do not break.

**Broker action:**
- Its `mk-deepseek-v4-flash` → upstream map must point to `deepseek-flash`.
- Expose `mk-deepseek-flash` as the new public name and **keep
  `mk-deepseek-v4-flash` as an alias**, so deployed clients do not break.
- Do not use `deepseek-chat` / `deepseek-reasoner` for new routes: they have
  been retired since 24 Jul 2026 and only continue during a grace period.

---

## 3. DeepSeek prices: up ~2x and there is now peak/off-peak pricing

This is what impacts broker accounting the most. If the price table is static
with August values, **the broker is undercharging**.

Per 1M tokens, **peak hours**:

| Model | Input (miss) | Input (cache hit) | Output |
|---|---|---|---|
| `deepseek-flash` | $0.30 | $0.003 | $1.20 |
| `deepseek-v4-pro` | $1.32 | $0.022 | $3.96 |

- **Off-peak you pay exactly half.**
- Peak hours: **01:00–04:00 and 06:00–10:00 UTC, Monday to Friday.**
- What we had noted before (`$0.14/$0.28` flash, `$0.435/$0.87` pro, and
  "peak 2x coming soon 9-12 and 14-18 UTC+8") is **obsolete**: the hours are
  different and the rate is already in effect.

**Broker action:** decide whether margin absorbs off-peak or whether it is
passed on to the client, and in any case move the windows to UTC. Watch out
for local-time use: the window is UTC and Mon–Fri, so the weekend is all
off-peak.

**What the DeepSeek email does say, and it does not require any action:**
`deepseek-v4-pro` **continues** after 14 Sep 2026, with the same billing. It
was an announced retirement that was canceled; there is nothing to migrate.

---

## 4. OpenAI: `gpt-image-2.5` family (flare / sunburst)

Two new models, endpoints `/v1/images/generations` and `/v1/images/edits`
(they are not in `/responses`). Canonical IDs and snapshots, all four verified:

```
gpt-image-2.5-flare      gpt-image-2.5-flare-2026-09-08
gpt-image-2.5-sunburst   gpt-image-2.5-sunburst-2026-09-08
```

`flare` = fast for everyday generation. `sunburst` = premium, fine control in
editing.

### Parameter rules the proxy must respect (all verified)

| Parameter | Rule |
|---|---|
| `quality` | 2.5 accepts `low/medium/high/xhigh/max/auto`. **`xhigh` and `max` only in 2.5**; sending them to gpt-image-1/2 risks a 400. Curious detail: the schema error message still lists only `low/medium/high/auto`, but `xhigh`/`max` pass and the response echoes them back |
| `background` | `transparent` works with **real alpha** (new compared with gpt-image-2, which did not support it). It requires `output_format` `png` or `webp` — with `jpeg` you have to correct it, not resend it |
| `input_fidelity` | **REJECTED**: *"The model 'gpt-image-2.5-sunburst' does not support the 'input_fidelity' parameter"*. Must be stripped if the client sends it |
| `response_format` | **Unknown parameter** across the entire gpt-image family. Strip |
| `n` | The schema accepts up to 10, but the real limit in gpt-image-2 was 8. MakerAi clamps to 8 as a precaution; recommendation: do the same in the broker |
| `size` | Width and height divisible by 16, aspect 1:3..3:1, maximum `3840x2160`, and there is a **minimum pixel budget**: `512x512` responds *"below the current minimum pixel budget"*. `1024x1024` and above works |
| `stream` + `partial_images` | Accepted (gpt-image-2 did not have streaming) |

### Image accounting — the important point

The price per token is **identical** to gpt-image-2: $5/M text input,
$1.25/M cached text, $8/M image input, $2/M cached image, **$30/M image
output**.

Therefore **the cost per image is NOT flat per model, it depends on the
quality tier**. Measured, same size 1024x1024:

| Request | output_tokens | Cost |
|---|---|---|
| `flare` + `quality=xhigh` | 3,122 | ~$0.094 |
| `sunburst` + `quality=max` | 7,024 | ~$0.211 |

**Broker action:** bill from `usage.output_tokens` in the response, not with a
flat per-image rate. A flat per-model rate is off by more than 100% between
`xhigh` and `max`.

### Response shape change (risk of billing zero)

In `/v1/images/generations`, the fields `background`, `output_format`, `size`,
`quality`, and **`usage`** come at the **ROOT** of the JSON, not inside
`data[]`. Each `data[]` item contains only `b64_json` and a new
**`generation_id`**; there is no longer a `revised_prompt`.

```json
{
  "created": 1789562281,
  "background": "transparent",
  "output_format": "png",
  "quality": "xhigh",
  "size": "1024x1024",
  "usage": { "input_tokens": 27, "output_tokens": 3122, "total_tokens": 3149,
             "output_tokens_details": { "image_tokens": 3122 } },
  "data": [ { "b64_json": "...", "generation_id": "67793cd9-..." } ]
}
```

If the broker's parser looks for `usage` inside `data[]`, it **bills zero** —
it is the same leak pattern as point 1 in the August report. In MakerAi this
was fixed in `ca175d0` with `TAiDalleImage.ParseRootMeta`, which fills the
empty fields from the root (it affected the entire gpt-image family, not just
2.5).

When forwarding the response, it is advisable to propagate `generation_id`: it
is what enables multi-turn editing by referencing the previous image.

---

## 5. `mk-gpt-image-2.5-flare` and `mk-gpt-image-2.5-sunburst` are already registered

**Updated 16 Sep 2026 (commit ff52a43).** The aliases are already in the
`MakerAi` driver block of `Source/Chat/uMakerAi.Chat.Initializations.pas`
(~line 1897), alongside `mk-gpt-image-1/-1.5/-1-mini/-2`, with `ModelCaps=[]` /
`SessionCaps=[cap_GenImage]` / `Tool_Active=False`.

**These are the public names the broker must expose, exactly as-is:**

```
mk-gpt-image-2.5-flare     ->  gpt-image-2.5-flare
mk-gpt-image-2.5-sunburst  ->  gpt-image-2.5-sunburst
```

If the broker prefers other names, it must notify so the registry can be
changed: without the corresponding entry, the MakerAi client computes an empty
gap, sends the request via `/responses`, and fails with *"model was not
found"*.

**Also fixed (same commit):** the `mk-deepseek-*` routes had no entry in the
registry, so they inherited the `MakerAi` driver's global default, which
includes `ModelCaps=[cap_Image]` — they declared a vision capability DeepSeek
does not have in its public API. They are now registered:

```
mk-deepseek-flash      ModelCaps=[]              (modo rapido, sin thinking)
mk-deepseek-v4-flash   ModelCaps=[]              (alias del anterior)
mk-deepseek-v4-pro     ModelCaps=[cap_Reasoning] + ThinkingLevel=tlMedium
```

These are the names inferred from the August report (`mk-deepseek-v4-flash` in
production) plus the Sep 2026 rename. **If the broker exposes other names,
notify us** so they can be adjusted.

---

## 6. Summary of actions for MKAIServer

1. `git pull` + **recompile** (fixes the DeepSeek thinking leak).
2. Map `mk-deepseek-v4-flash` → `deepseek-flash` and expose
   `mk-deepseek-flash` while keeping the old alias.
3. Update the DeepSeek price table (2x) and implement peak/off-peak in UTC,
   Mon–Fri.
4. If the 2.5 image models are offered: apply the parameter rules (strip
   `input_fidelity`/`response_format`, `xhigh`/`max` only in 2.5, transparent
   requires png/webp, minimum 1024x1024, n≤8).
5. Read `usage` from the **root** of the image response and bill by
   `output_tokens`, not per image.
6. Expose the image models with the names already registered in MakerAi:
   `mk-gpt-image-2.5-flare` and `mk-gpt-image-2.5-sunburst`.