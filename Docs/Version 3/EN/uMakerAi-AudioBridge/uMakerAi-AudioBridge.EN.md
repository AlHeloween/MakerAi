# uMakerAi — Audio Bridge for Real-Time Translation

**Units:** `Source/Utils/uMakerAi.Utils.AudioCapture.pas` · `Source/Utils/uMakerAi.Utils.AudioPlayback.pas`
**Components:** `TAiAudioCapture` · `TAiAudioPlayer`
**Demos:** `Demos/061-LoopbackAudioCapture` · `Demos/062-BidirectionalTranslator` · `Demos/063-VoiceBridgeTranslator`
**Platform:** Windows (WASAPI, Vista+). No additional drivers or DLLs (the virtual cable is optional, see §4).

---

## 1. Overview

This module lets you build a **real-time video-call translator/interpreter**: it captures the audio the system plays (what the other side of the meeting says) and the local microphone, transcribes and translates it, and plays the synthesized voice (TTS) on the appropriate device — including a **virtual cable** so that the meeting application (Zoom, Meet, Teams) receives the translation as if it were the user's microphone.

```text
                 ┌──────────────────────── USER'S MACHINE ────────────────────────┐
 Meeting ──────▶ │ headphones ──(loopback)──▶ TAiAudioCapture ─▶ STT(en) ─▶ Translate │
 (remote audio)  │                                                            │ (es)  │
                 │ headphones ◀──────────── TAiAudioPlayer ◀─────── TTS ◀────┘       │
                 │                                                                    │
                 │ microphone ─────────────▶ TAiAudioCapture ─▶ STT(es) ─▶ Translate  │
                 │                                                            │ (en)  │
 Meeting ◀────── │ CABLE Input ◀──────────── TAiAudioPlayer ◀─────── TTS ◀────┘       │
 (mic = CABLE    └────────────────────────────────────────────────────────────────────┘
  Output)
```

The AI pieces are interchangeable: the STT is any `TAiRealtimeBase` (OpenAI Realtime driver included), translation is a `TAiChatConnection` (OpenAI, Claude, Gemini, local Ollama, etc.), and TTS is `TAiOpenAiAudio` (or ElevenLabs/Gemini Speech).

---

## 2. TAiAudioCapture — WASAPI capture (loopback and microphone)

Captures the audio the system **plays** (loopback mode, no Stereo Mix or cables needed) or a microphone, and delivers **PCM16 chunks ready for STT** (linear resampling with inter-packet continuity and mono mixing built in).

| Property | Default | Description |
|-----------|---------|-------------|
| `Source` | `asLoopback` | `asLoopback` = playback audio; `asMicrophone` = microphone |
| `DeviceId` | `''` | WASAPI endpoint ID (see `GetAudioDevices`). `''` = default |
| `OutputSampleRate` | `16000` | Output rate. `0` = device native (typically 48000) |
| `OutputChannels` | `1` | `0` = native (max 2), `1` = mono, `2` = stereo |
| `ChunkDurationMs` | `100` | Duration of each chunk delivered in `OnData` |
| `InjectSilence` | `True` | WASAPI loopback delivers no packets when nothing is playing; with `True`, silence chunks are injected to keep the stream continuous (needed for streaming VAD/STT) |
| `Muted` | `False` | Replaces chunks with silence **without cutting the stream**. Can be changed while capture is active. This is the anti-feedback piece (§5) |
| `RealtimeSTT` | — | If a `TAiRealtimeBase` is assigned, each chunk is forwarded (mono) to the STT, automatically synchronizing `InputSampleRate` |

Events: `OnData` (PCM16 chunk, safe copy), `OnFormat` (native and effective format), `OnUpdate` (average level), `OnError`.

```pascal
// Enumerate devices (for loopback, PLAYBACK devices are listed)
for D in TAiAudioCapture.GetAudioDevices(asLoopback) do
  Memo1.Lines.Add(D.DeviceName + IfThen(D.IsDefault, ' (default)', ''));

Capture := TAiAudioCapture.Create(Self);
Capture.Source := asLoopback;
Capture.OutputSampleRate := 16000;   // optimal for Whisper / Realtime STT
Capture.OutputChannels := 1;
Capture.RealtimeSTT := MyRealtime;   // or use OnData manually
Capture.Active := True;
```

Technical notes:
- The native mix format is usually float32 48 kHz stereo; conversion to PCM16 is internal.
- Events are dispatched via `TThread.Queue`; in console applications you must call `CheckSynchronize`.
- With `InjectSilence` and absolute silence, chunks are emitted at ~2× `ChunkDurationMs` (reduced cadence, enough to keep VAD alive).

---

## 3. TAiAudioPlayer — WASAPI playback to a selectable device

The capture's counterpart: plays PCM16 on **any output endpoint**, not just the default. This is what allows sending TTS to the virtual cable.

| Property / method | Description |
|--------------------|-------------|
| `DeviceId` | WASAPI ID of the output endpoint. `''` = default |
| `Active` | Starts/stops the playback thread |
| `PlayPCM16(aData, aRate, aChannels)` | Enqueues a phrase; phrases play in order, without overlapping |
| `ClearQueue` | Empties the queue (does not cut the current phrase) |
| `IsPlaying` | True while audio is playing |
| `OnStateChange(IsPlaying)` | Fires when the queue starts/finishes playing — connect the anti-feedback here (§5) |
| `GetPlaybackDevices` (class) | Enumerates output endpoints |

The component automatically converts to the device format (linear resampling + channel mapping). OpenAI TTS with `TTSResponseFormat := trfPcm` returns **PCM16 24 kHz mono**, which plays directly:

```pascal
Player := TAiAudioPlayer.Create(Self);
Player.DeviceId := CableInputEndpointId;  // '' = default
Player.Active := True;

PcmStream := TTS.Speech('Good morning, the report is ready');  // TAiOpenAiAudio, trfPcm
Player.PlayPCM16(StreamABytes(PcmStream), 24000, 1);
```

---

## 4. The virtual cable (VB-CABLE) — MUST READ FOR DISTRIBUTION

### 4.1 Why it is needed

Windows **does not allow injecting audio into a physical microphone**. For the meeting application to "hear" the TTS, a virtual device with two ends is required:

- **CABLE Input** — a *playback* endpoint: our app plays the TTS there.
- **CABLE Output** — a *recording* endpoint: the meeting app selects it as the microphone.

Everything that enters through `CABLE Input` comes out through `CABLE Output`.

### 4.2 Installation and correct configuration

1. Download from the official site: <https://vb-audio.com/Cable/> (VBCABLE_Driver_Pack). Run the installer **as administrator** and reboot if it asks.
2. **⚠️ KNOWN TRAP (verified):** the installer can leave `CABLE Input` as **Windows' default output device**. If it stays that way, ALL system audio (including the meeting and our local TTS) goes into the cable and the user **hears nothing**. After installing:
   - Windows Settings → System → Sound → **Output = the user's headphones**.
3. In the meeting application: **Microphone = `CABLE Output (VB-Audio Virtual Cable)`**, Speaker = headphones.
4. **Headphones mandatory:** with speakers, the physical microphone captures the remote audio and the TTS, duplicating transcriptions.

Device assignment in the translator app:

| Flow | Device |
|-------|-------------|
| Loopback capture (what the meeting says) | The device where the user LISTENS to the meeting (headphones) |
| TTS for the user (local translation) | Headphones |
| TTS for the meeting (translated voice) | `CABLE Input` |
| Microphone capture (user's voice) | Physical microphone |

### 4.3 Detection from code

```pascal
function FindCableDevice(out aId, aName: string): Boolean;
var
  D: TAiAudioDeviceInfo;
begin
  Result := False;
  for D in TAiAudioPlayer.GetPlaybackDevices do
    if Pos('cable input', LowerCase(D.DeviceName)) > 0 then
    begin
      aId := D.EndpointId;
      aName := D.DeviceName;
      Exit(True);
    end;
end;
```

The distribution app should check for the cable at startup and, if missing, guide the user to install it (or degrade to a "subtitles only" mode with no TTS into the meeting).

### 4.4 License and redistribution — IMPORTANT

- **VB-CABLE is donationware by VB-Audio Software.** The standard license allows the end user to install it free of charge, but does **NOT allow redistributing the driver inside a commercial application's installer without authorization**.
- Options for the distribution app:
  1. **Recommended:** the installer/app detects the missing cable and opens the official download page (or launches the installer the user downloaded). Zero legal risk.
  2. **Distribution license:** contact VB-Audio (<https://vb-audio.com/Services/licensing.htm>) to obtain bundling/OEM authorization.
  3. **Alternatives:** "Virtual Audio Cable" by E. Muzychenko (paid commercial license, redistributable under agreement) or develop your own driver (APO/AVStream — high cost).
- The device name (`CABLE Input/Output`) can vary with other cables; make the search pattern configurable.

---

## 5. Anti-feedback: the `Muted` property

When the local TTS (the translation the user hears) plays through the headphones, the **loopback captures it** — and the system would re-translate its own synthesized voice in a loop.

Built-in solution: mute the capture **without cutting the stream** while the TTS itself is playing.

```pascal
// Before playing our TTS on a device that the loopback captures:
CaptureLoopback.Muted := True;
PlayerLocal.PlayPCM16(Pcm, 24000, 1);

// In PlayerLocal.OnStateChange:
procedure TForm1.PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
begin
  if not aIsPlaying then
    CaptureLoopback.Muted := False; // the queue finished playing
end;
```

**Design trade-off:** while muted, if the remote counterpart keeps talking, that fragment is not translated (same as a simultaneous interpreter who cannot listen while speaking). TTS to the cable (`CABLE Input`) does NOT need mute, because the loopback does not capture that device.

---

## 6. Checklist for the distribution app

- [ ] **Explicit device selection in the UI** (loopback, mic, local TTS, meeting TTS) with persistence. Do not trust the default device: the cable installer can change it (§4.2).
- [ ] Cable check at startup + installation wizard (official link, §4.4).
- [ ] Headphones notice (or echo detection: if the mic transcribes the same as the loopback, alert).
- [ ] Realtime STT model: `'gpt-realtime-2.1'`, which is already the driver default (see `uMakerAi.Realtime.OpenAI.GetDefaultModel`). Do not use `gpt-4o-realtime-preview`: OpenAI retired it.
- [ ] API keys using the framework's `@ENV_VAR` convention (do not hardcode).
- [ ] `OnError` handling for all 4 audio components + STT reconnection.
- [ ] If the user hot-switches the default device, restart the affected capture/playback (`Active := False/True`).
- [ ] Expected full-cycle latency (end of phrase → VAD → STT → translation → TTS → audio): 2–4 s with OpenAI. Showing subtitles of the translated text while TTS arrives greatly improves perceived quality.
- [ ] Costs: Realtime STT + TTS bill per minute of audio; `InjectSilence` keeps the stream active (the server-side VAD discards silence, but the audio is still sent — for long calls consider pausing the send with `Muted`/disconnection when there is no activity).

---

## 7. Diarization: identifying who is speaking in the meeting

Realtime STT does not diarize. To label remote participants, use the REST endpoint with **`gpt-4o-transcribe-diarize`** (`TAiOpenAiAudio`, see `Source/Tools/uMakerAi.OpenAI.Audio.pas`):

- `TranscriptionModel := tmGpt4oDiarize` + `TranscriptionResponseFormat := trfDiarizedJson` → `TTranscriptionResult.Segments` (Speaker/Text/StartTime/EndTime) and `DiarizedText`.
- **Known speakers**: `AddKnownSpeaker(name, voiceSample)` (max 4; the API requires samples of **1.2 to 10.0 s** — use 2–9 s to avoid edge rejections) makes segments use real names.
- **Consistent labels across requests**: the letters A/B/C are only stable within a SINGLE request. The validated pattern (demo 064) is *self-registration*: the first time a voice appears, its longest fragment from the segment (2–9 s) is cut and registered as "Speaker N"; subsequent requests return that name stably.
- Architecture of the diarized remote channel: local level-based VAD (speech segments with pre-buffer) → diarized `Transcribe` → translate per speaker → TTS with a distinct voice per speaker.
- Resilience: if the API rejects the registered samples (`known_speaker_references`), clear them with `ClearKnownSpeakers` and retry without them (they re-register on later segments).
- Latency: the diarized channel is REST per segment (~2–4 s after end of phrase). For instant subtitles + attribution, combine Realtime (immediate text) with parallel diarization (label).

## 8. Reference demos

| Demo | What it shows |
|------|-------------|
| `061-LoopbackAudioCapture` | Basic loopback capture → 16 kHz mono WAV |
| `062-BidirectionalTranslator` | Bidirectional translator with TEXT output (loopback + mic → STT → translation) |
| `063-VoiceBridgeTranslator` | Full voice bridge: TTS to headphones and to `CABLE Input`, anti-feedback with `Muted`, cable detection, and a cable-free test mode |
| `064-VoiceBridgeDiarized` | Voice bridge with diarization: local VAD + `gpt-4o-transcribe-diarize`, speaker self-registration (stable labels), and a distinct TTS voice per participant |

Requirements for demos 062/063/064: `OPENAI_API_KEY` environment variable.

---

*MakerAI Suite — Gustavo Enríquez · document generated June 2026*
