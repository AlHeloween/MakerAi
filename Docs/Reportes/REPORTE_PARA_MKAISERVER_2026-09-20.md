# Report to MKAIServer — Computer Use can now be delegated, 2026-09-20

Written from the MakerAi side (`E:\Delphi\Delphi13\Compo\FMXCompo\AiMaker`)
for the broker (`E:\Copilot\MKAIServer`). Continues
`REPORTE_PARA_MKAISERVER_2026-09-16.md`.

This comes from an analysis that arrived from your side and was **correct on
both points it raised**:

> 1. There is no Linux executor.
> 2. The broker pass-through is Claude-only in practice: astra and Gemini
>    still execute locally even if the interceptor sets `Response`.

Both are resolved. Everything below is **verified at runtime against the real
APIs**, not inferred from documentation.

Commits in `dev` and `master` (both at the same point, `0f1fbf1`):

```
83a1656  fix(gemini)         el driver no ejecutaba NINGUNA funcion de usuario
38eeacf  feat(computer-use)  OpenAI y Gemini respetan la intercepcion, como Claude
4d1f81a  fix(computer-use)   Claude manda coordenadas como array y como cadena
2e3e3be  feat(computer-use)  executor de Linux + Computer Use sobre X11
b99e269  fix(websocket)      OpenSSL no validaba el certificado del servidor
0a88e43  fix(shell)          TAiShell: Windows no ingles, stderr y timeout
```

The version **remains 3.7.0 / API_LEVEL 37**: there was no bump; it is additive
content on top of the tag.

Ordered by what blocks you, not by size.

---

## 0. First: `git pull` **and rebuild the package**, not just the app

`ResApiServer.dpr` links the drivers by absolute path to our `Source\Chat`
(lines 89–101), so those arrive by themselves when recompiling. **But the base
class `TAiChat` does not**: that is resolved through the installed package, and
it also changed (the interception contract lives in `TAiChat.DoCallFunction`).

```
1. git pull            in E:\Delphi\Delphi13\Compo\FMXCompo\AiMaker
2. rebuild and install Source\Packages\MakerAI.dpk
3. rebuild ResApiServer
```

If you only do step 3, you stay on the old base and none of this works.

> **Trap we found along the way:** `api-server\chat\` has copies of
> `UMakerAi.Chat.pas`, `uMakerAi.Core.pas` and `uMakerAi.Chat.Messages.pas`
> dated **July 3** (ours is from September and is 75 KB larger). Today they are
> **not compiled** — that folder is not in the `.dproj` search path and the
> `.dpr` does not link it — but if someone adds that directory to the path, the
> server will start compiling a base from three months ago without warning.
> They should be deleted.

---

## 1. Delegation now works in all three drivers

The contract was and still is the same: **if the `OnCallToolFunction` handler
leaves `ToolCall.Response` filled, the driver does not execute the action
locally**. The base class and Claude complied. Now OpenAI and Gemini do too.

What happened before:

| Driver | Before | Now |
|--------|--------|-----|
| Claude | Respected `Response` | same |
| OpenAI (`gpt-6-astra`) | Fired the event but **discarded `Response`** and executed anyway | respects `Response` |
| Gemini | **Did not even fire the event** | fires and respects `Response` |

### Wiring in the broker

```pascal
// 1. A TAiComputerUseTool must be assigned EVEN IF IT DOES NOTHING.
//    In OpenAI the only interception point lives INSIDE the traversal of the
//    'actions' array, and that block is conditioned on the tool existing.
//    Without it OnCallToolFunction is not called and there is nothing to delegate.
FCU := TAiComputerUseTool.Create(nil);
FConn.ChatTools.ComputerUseTool := FCU;

// 2. DO NOT assign OnExecuteAction or OnRequestScreenshot: the broker has no
//    screen. Leaving them unassigned is correct.
// 3. The interceptor claims the call for the remote client.
FConn.OnCallToolFunction := ReclamarParaElCliente;

procedure TMiBroker.ReclamarParaElCliente(Sender: TObject;
  AiToolCall: TAiToolsFunction);
begin
  // Putting any non-empty value is enough: the driver no longer executes.
  AiToolCall.Response := '{"output":"delegated"}';
  // ...and here you enqueue/emit the tool_call toward your client.
end;
```

### What the driver does when you delegate

- It **does not emit** `computer_call_output` and **does not fall back**.
- The raw `computer_call` **remains in the history** as an `assistant` message
  with its `ToolCallId`. **That is what you must forward to the client.**
- The turn is cut there, which is what you want: the response will be brought
  by the client on the next round.

### OpenAI delegation is ATOMIC over the batch

`gpt-6-astra` does not send one action: it sends a `computer_call` with an
**`actions` array** (e.g. `keypress[WIN,r]` + `type 'notepad'` + `keypress[ENTER]`)
and the API allows **a single** `computer_call_output` per call.

That is why, **as soon as the first action returns with `Response` filled, the
entire batch is considered delegated** and the rest is not traversed. Splitting
the actions between a local executor and a remote one would leave the final
screenshot without an owner.

Consequence for you: forward the **complete item**, not action by action.

### If you are missing the tool, now you find out

Before, without `ComputerUseTool` assigned, the synchronous path still emitted
a `computer_call_output` **without `image_url`** — and the API rejects that with
400 because it requires exactly one of `image_url` or `file_id`. The streaming
path swallowed it silently. Now both cut the turn and report it via `LastError`:

```
computer_call call_xxx: cap_ComputerUse esta activo pero ChatTools.ComputerUseTool
no esta asignado. El turno se corta sin responder al modelo.
```

---

## 2. The client side (the one that does have a screen)

It does not have to interpret each provider's raw JSON. The translators are
**public precisely for this**:

```pascal
// The client receives the raw tool_call forwarded by the broker
LCU := TAiToolsFunction.Create;
LCU.Id        := <call_id>;
LCU.Name      := <action type>;   // 'click', 'type', 'left_click'...
LCU.Arguments := <action json>;

// Translates to the canonical format of TAiComputerUseTool
MiTool.TranslateOpenAIToolCall(LCU);   // or TranslateClaudeToolCall(LCU)

// And executes locally, with its own OnExecuteAction / OnRequestScreenshot
LRespuesta := MiTool.ProcessToolCall(LCU, LScreenshot);
```

For OpenAI, remember: the `computer_call` carries an `actions` array and the
client must traverse it in order, keeping **only the screenshot from the last
one**.

### Claude trap that affects you if you forward raw JSON

We found that **Claude sends coordinates sometimes as an array and sometimes as
a string with the array inside, within the same turn**:

```
✅ left_click args={ "coordinate": [299, 282] }     <- the first calls
❌ left_click args={ "coordinate": "[299, 400]" }   <- from a certain point on
```

Our `TryGetValue<TJSONArray>` did not match the second form: the coordinate was
lost, the action fell to **(0, 0)** —a click in the corner— and the model became
disoriented and retried until the turn was exhausted. It affected `coordinate`,
`start_coordinate`, `region` (zoom) and numeric fields (`"duration": "1"`), that
is, click, double/triple click, drag and zoom.

Fixed in `4d1f81a`: the translators accept both forms. **If your client parses
the JSON itself instead of using the translator, it must tolerate both.**

---

## 3. Alternative: let the broker itself execute, on Linux

If in some scenario you prefer not to depend on a client with a screen, there is
now a Linux executor.

`TAiLinuxExecutor` (`Source\Tools\uMakerAi.Tools.ComputerUse.Linux.pas`) covers
the 19 actions over X11 with **xdotool** and captures with **scrot**. Same public
interface as the Windows and macOS ones, so it is interchangeable.

The framework did not need changes: `TAiComputerUseTool` only uses the RTL and
delegates everything to its two events, so it crossed over to Linux64 as-is.

Setup on a headless VPS (tested from scratch on Ubuntu 24.04 and 26.04):

```bash
apt-get install -y xvfb xdotool scrot x11-apps
Xvfb :99 -screen 0 1280x800x24 &
export DISPLAY=:99
# and, if a browser is needed:
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb
google-chrome --no-sandbox --disable-gpu --window-size=1280,800 <url> &
```

Tested at runtime with `gpt-6-astra` and `claude-opus-4-8`: it filled out a
complete web form (click on field, type, click on button) and read back the
exact result from the page. Demo: `083-ComputerUseLinux`.

**Two things we learned that will save you time:**

- **Do not declare dimensions and do not rescale if it is not necessary.** If
  the X screen is 1280 wide and you declare `ScreenWidth = AreaWidth = 1280`,
  clicks land where the model thinks they do. Windows demo 066 does rescale
  (3440 monitor to declared 1280), and that is why the conversion matters there.
- **`catNavigate` uses `xdg-open`** and on a bare Xvfb there is no handler
  registered. It is more reliable to launch the browser already pointing at the
  URL and let the model only drive it: the initial navigation is provided by
  the infrastructure.

For automating **browser only**, **CDP** (Chrome DevTools Protocol) is still the
better idea: it skips Xvfb, xdotool and scrot entirely and leaves the golden
image much lighter. It is not implemented; it would be another executor, and
since they are two handlers it would not touch anything else in the framework.

---

## 4. Two changes that may break something when you recompile

### ⚠️ TLS: the POSIX transport now validates the certificate

`TOpenSSLTransport` was running with `SSL_VERIFY_NONE`: it accepted **any**
certificate, from anyone. It is the transport used by the Realtime module on
Linux and macOS. It now validates the chain against the system CA store **and
hostname**.

**If you point Realtime at an endpoint with its own certificate** (an internal
LM Studio, a proxy of yours), it will stop connecting until you set:

```pascal
LTransport.InsecureSkipVerify := True;
```

On Linux, the `ca-certificates` package must be installed.

### ⚠️ Gemini: user functions now execute

`TAiGeminiChat.DoCallFunction` had `inherited` commented out and responded
`'Command <name> not found'` to **every** tool call that was not Computer Use —
and it is the driver's only dispatch point. Neither `AiFunctions` nor
`OnCallToolFunction` were ever fired.

If something on your side depended on that "not found" (unlikely, but worth
checking), it now behaves differently: functions execute.

---

## 5. What is NOT verified

- **Computer Use in Gemini**: the gate and interception are implemented the
  same as in Claude, but **without a runtime test**. The `GEMINI_API_KEY` here
  is not valid. If you use it, let us know how it behaves.
- **The end-to-end of demo 066** with a real mouse and keyboard was not re-run
  after these changes; the local path is covered by 082 with a simulated
  executor.

---

## 6. Summary of what you need to do

1. `git pull` in MakerAi, **rebuild and install `MakerAI.dpk`**, rebuild
   ResApiServer.
2. Assign a `TAiComputerUseTool` to `ChatTools` even if it does nothing.
3. **Do not** assign `OnExecuteAction` or `OnRequestScreenshot`.
4. In `OnCallToolFunction`, fill `Response` and enqueue the tool_call.
5. Forward to the client the **complete** `computer_call` (the raw `assistant`
   message from the history), not action by action.
6. In the client, use `TranslateOpenAIToolCall` / `TranslateClaudeToolCall`
   before `ProcessToolCall`, or tolerate Claude sending coordinates as a string.
7. Check whether the TLS change affects you.
8. Delete `api-server\chat\*.pas`, which are July copies.