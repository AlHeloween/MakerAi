// BIDIRECTIONAL VOICE BRIDGE WITH DIARIZATION (console)
// =======================================================
//
// Evolution of demo 063: the [THEM] channel identifies WHO speaks in the
// meeting (diarization with gpt-4o-transcribe-diarize) and each speaker is
// translated and read with a DISTINCT TTS VOICE.
//
//   [THEM] loopback -> local VAD (speech segments)
//                    -> diarized transcription (gpt-4o-transcribe-diarize)
//                    -> speaker auto-registration (known_speakers, max 4)
//                    -> translate(es) per speaker -> TTS (voice per speaker)
//                    -> headphones
//
//   [ME]    microphone -> Realtime STT (low latency, single speaker)
//                     -> translate(en) -> TTS -> CABLE Input (the meeting hears it)
//
// SPEAKER AUTO-REGISTRATION: the A/B/C diarization labels are only
// consistent within the same request. The first time a new
// voice appears, its audio is clipped from the segment (>= 2 s) and registered with
// AddKnownSpeaker as 'Speaker N'; from then on the API returns that
// name stably in all following segments.
//
// Requirements: OPENAI_API_KEY, VB-CABLE (optional, see demo 063), headphones.
// Documentation: Docs/Version 3/uMakerAi-AudioBridge.md

program VoiceBridgeDiarizedDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading,
  System.Generics.Collections,
  System.Math,
  Winapi.Windows,
  uMakerAi.Utils.AudioCapture,
  uMakerAi.Utils.AudioPlayback,
  uMakerAi.Utils.PcmToWav,
  uMakerAi.Core,
  uMakerAi.OpenAI.Audio,
  uMakerAi.Realtime,
  uMakerAi.Realtime.OpenAI,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi;

const
  // ==========================================================================
  // CONFIGURACION
  // ==========================================================================
  TARGET_LANG_REMOTE = 'espanol';
  TARGET_LANG_LOCAL = 'ingles';
  STT_LANG_LOCAL = 'es';

  TRANSLATOR_DRIVER = 'OpenAi';
  TRANSLATOR_MODEL = 'gpt-4o-mini';
  TRANSLATOR_APIKEY = '@OPENAI_API_KEY';

  STT_APIKEY = '@OPENAI_API_KEY';
  STT_MODEL = 'gpt-realtime-2.1';

  TTS_PCM_RATE = 24000;
  MEETING_DEVICE_HINT = 'CABLE Input';

  // --- Local VAD segmenter for the [THEM] channel (PCM16 16 kHz mono) ---
  SEG_SAMPLE_RATE = 16000;
  SEG_START_LEVEL = 400; // nivel medio para considerar inicio de habla
  SEG_STOP_LEVEL = 250; // por debajo se acumula silencio
  SEG_SILENCE_MS = 900; // silencio que cierra el segmento
  SEG_MIN_MS = 700; // segmentos mas cortos se descartan
  SEG_MAX_MS = 25000; // corte forzado de segmentos largos
  SEG_PREBUF_MS = 400; // pre-buffer para no perder el arranque de la frase

  // TTS voice per registered speaker (Speaker 1..4)
  SPEAKER_VOICES: array [0 .. 3] of TAiTTSVoice = (TAiTTSVoice.tvNova, TAiTTSVoice.tvShimmer,
    TAiTTSVoice.tvCoral, TAiTTSVoice.tvSage);

var
  GConsoleLock: TCriticalSection;

procedure SafeWriteLn(const aText: string);
begin
  GConsoleLock.Enter;
  try
    WriteLn(aText);
  finally
    GConsoleLock.Leave;
  end;
end;

type
  // --------------------------------------------------------------------------
  // Segmentador de habla por nivel (VAD local) sobre chunks PCM16 mono.
  // Alimentado desde OnData (hilo principal); dispara OnSegment con el PCM
  // completo de cada frase detectada.
  // --------------------------------------------------------------------------
  TSpeechSegmenter = class
  private
    FBuffer: TMemoryStream; // segmento en curso
    FPreBuffer: TMemoryStream; // ultimos SEG_PREBUF_MS de silencio
    FInSpeech: Boolean;
    FSilenceMs: Integer;
    FBytesPerMs: Integer;
    FOnSegment: TProc<TBytes>;
    procedure CloseSegment;
  public
    constructor Create(aOnSegment: TProc<TBytes>);
    destructor Destroy; override;
    procedure Feed(const aChunk: TBytes; aChunkMs: Integer);
  end;

constructor TSpeechSegmenter.Create(aOnSegment: TProc<TBytes>);
begin
  inherited Create;
  FOnSegment := aOnSegment;
  FBuffer := TMemoryStream.Create;
  FPreBuffer := TMemoryStream.Create;
  FBytesPerMs := (SEG_SAMPLE_RATE * 2) div 1000;
end;

destructor TSpeechSegmenter.Destroy;
begin
  FBuffer.Free;
  FPreBuffer.Free;
  inherited;
end;

procedure TSpeechSegmenter.CloseSegment;
var
  Pcm: TBytes;
begin
  if FBuffer.Size >= SEG_MIN_MS * FBytesPerMs then
  begin
    SetLength(Pcm, FBuffer.Size);
    FBuffer.Position := 0;
    FBuffer.ReadBuffer(Pcm[0], FBuffer.Size);
    if Assigned(FOnSegment) then
      FOnSegment(Pcm);
  end;
  FBuffer.Clear;
  FPreBuffer.Clear;
  FInSpeech := False;
  FSilenceMs := 0;
end;

procedure TSpeechSegmenter.Feed(const aChunk: TBytes; aChunkMs: Integer);
var
  I, NumSamples: Integer;
  Sum, Level: Int64;
  MaxPre: Int64;
  Tmp: TMemoryStream;
begin
  if Length(aChunk) = 0 then
    Exit;

  // Nivel medio del chunk
  NumSamples := Length(aChunk) div 2;
  Sum := 0;
  for I := 0 to NumSamples - 1 do
    Sum := Sum + Abs(PSmallInt(@aChunk[I * 2])^);
  Level := Sum div NumSamples;

  if not FInSpeech then
  begin
    // Mantener pre-buffer rodante
    FPreBuffer.Position := FPreBuffer.Size;
    FPreBuffer.WriteBuffer(aChunk[0], Length(aChunk));
    MaxPre := SEG_PREBUF_MS * FBytesPerMs;
    if FPreBuffer.Size > MaxPre then
    begin
      Tmp := TMemoryStream.Create;
      try
        FPreBuffer.Position := FPreBuffer.Size - MaxPre;
        Tmp.CopyFrom(FPreBuffer, MaxPre);
        FPreBuffer.Clear;
        Tmp.Position := 0;
        FPreBuffer.CopyFrom(Tmp, 0);
      finally
        Tmp.Free;
      end;
    end;

    if Level >= SEG_START_LEVEL then
    begin
      // Inicio de habla: el segmento arranca con el pre-buffer
      FInSpeech := True;
      FSilenceMs := 0;
      FBuffer.Clear;
      FPreBuffer.Position := 0;
      FBuffer.CopyFrom(FPreBuffer, 0);
      FPreBuffer.Clear;
    end;
  end
  else
  begin
    FBuffer.Position := FBuffer.Size;
    FBuffer.WriteBuffer(aChunk[0], Length(aChunk));

    if Level < SEG_STOP_LEVEL then
      Inc(FSilenceMs, aChunkMs)
    else
      FSilenceMs := 0;

    if (FSilenceMs >= SEG_SILENCE_MS) or (FBuffer.Size >= SEG_MAX_MS * FBytesPerMs) then
      CloseSegment;
  end;
end;

type
  // --------------------------------------------------------------------------
  // Canal [ELLOS]: loopback -> VAD -> diarizacion -> traduccion -> TTS
  // --------------------------------------------------------------------------
  TDiarizedRemoteSide = class
  private
    FTag: string;
    FClosing: Boolean;
    FCapture: TAiAudioCapture;
    FChat: TAiChatConnection;
    FAudioApi: TAiOpenAiAudio; // diarizacion + TTS
    FPlayer: TAiAudioPlayer;
    FSegmenter: TSpeechSegmenter;
    FLock: TCriticalSection; // serializa diarizar/traducir/TTS
    FSpeakerNames: TArray<string>; // 'Hablante 1'.. en orden de registro
    procedure CaptureData(Sender: TObject; const aBuffer: TBytes; aSampleRate, aChannels: Integer);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
    procedure ProcessSegment(const aPcm: TBytes);
    procedure ProcessSegmentWork(const aPcm: TBytes);
    function SpeakerIndex(const aName: string): Integer;
    function TryEnrollSpeaker(const aPcm: TBytes; const aRawSpeaker: string;
      const aSegments: TDiarizedSegments; out aName: string): Boolean;
    function Translate(const aText: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Capture: TAiAudioCapture read FCapture;
  end;

constructor TDiarizedRemoteSide.Create;
begin
  inherited Create;
  FTag := '[THEM]';
  FLock := TCriticalSection.Create;

  FChat := TAiChatConnection.Create(nil);
  FChat.DriverName := TRANSLATOR_DRIVER;
  FChat.Model := TRANSLATOR_MODEL;
  FChat.Params.Values['Asynchronous'] := 'False';
  FChat.Params.Values['ApiKey'] := TRANSLATOR_APIKEY;

  FAudioApi := TAiOpenAiAudio.Create(nil);
  FAudioApi.ApiKey := '@OPENAI_API_KEY';
  FAudioApi.TranscriptionModel := TAiTranscriptionModel.tmGpt4oDiarize;
  FAudioApi.TranscriptionResponseFormat := TAiTranscriptionResponseFormat.trfDiarizedJson;
  FAudioApi.TTSModel := TAiTTSModel.gpt_4o_mini_tts;
  FAudioApi.TTSResponseFormat := TAiTTSResponseFormat.trfPcm;
  FAudioApi.TTSSpeed := 1.0;

  FPlayer := TAiAudioPlayer.Create(nil);
  FPlayer.DeviceId := ''; // auriculares (predeterminado)
  FPlayer.OnError := PlayerError;
  FPlayer.OnStateChange := PlayerStateChange;

  FSegmenter := TSpeechSegmenter.Create(
    procedure(aPcm: TBytes)
    begin
      ProcessSegment(aPcm);
    end);

  FCapture := TAiAudioCapture.Create(nil);
  FCapture.Source := asLoopback;
  FCapture.OutputSampleRate := SEG_SAMPLE_RATE;
  FCapture.OutputChannels := 1;
  FCapture.OnData := CaptureData;
  FCapture.OnError := CaptureError;
end;

destructor TDiarizedRemoteSide.Destroy;
begin
  Stop;
  FLock.Enter;
  try
    FClosing := True;
  finally
    FLock.Leave;
  end;
  FCapture.Free;
  FSegmenter.Free;
  FPlayer.Free;
  FAudioApi.Free;
  FChat.Free;
  FLock.Free;
  inherited;
end;

procedure TDiarizedRemoteSide.Start;
begin
  FPlayer.Active := True;
  FCapture.Active := True;
  SafeWriteLn(FTag + ' diarized channel active (local VAD + gpt-4o-transcribe-diarize).');
end;

procedure TDiarizedRemoteSide.Stop;
begin
  FClosing := True;
  if Assigned(FCapture) then
    FCapture.Active := False;
  if Assigned(FPlayer) then
    FPlayer.Active := False;
end;

procedure TDiarizedRemoteSide.CaptureData(Sender: TObject; const aBuffer: TBytes; aSampleRate, aChannels: Integer);
begin
  // OnData llega en el hilo principal: alimentar el VAD local
  if not FClosing then
    FSegmenter.Feed(aBuffer, FCapture.ChunkDurationMs);
end;

procedure TDiarizedRemoteSide.CaptureError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR capture: ' + ErrorMessage);
end;

procedure TDiarizedRemoteSide.PlayerError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR playback: ' + ErrorMessage);
end;

procedure TDiarizedRemoteSide.PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
begin
  // Anti-feedback: our TTS plays through the device captured by
  // loopback; when the queue finishes the capture is reactivated.
  if not aIsPlaying then
    FCapture.Muted := False;
end;

function TDiarizedRemoteSide.SpeakerIndex(const aName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FSpeakerNames) do
    if SameText(FSpeakerNames[I], aName) then
      Exit(I);
end;

// Recorta del segmento el tramo mas largo del hablante aRawSpeaker y lo
// registra como known_speaker. Devuelve el nombre asignado ('Hablante N').
function TDiarizedRemoteSide.TryEnrollSpeaker(const aPcm: TBytes; const aRawSpeaker: string;
  const aSegments: TDiarizedSegments; out aName: string): Boolean;
const
  // La API exige muestras de 1.2 a 10.0 s; nos quedamos lejos de los bordes
  // (10.0 exactos puede rechazarse por redondeo).
  MIN_SAMPLE_SEC = 2.0;
  MAX_SAMPLE_SEC = 9.0;
var
  I: Integer;
  RunStart, RunEnd, BestStart, BestEnd: Double;
  InRun: Boolean;
  StartByte, LenBytes: Integer;
  Pcm: TMemoryStream;
  Wav: TMemoryStream;
begin
  Result := False;
  aName := '';
  if FAudioApi.KnownSpeakerCount >= 4 then
    Exit;

  // Buscar el tramo contiguo mas largo de este hablante
  BestStart := 0;
  BestEnd := 0;
  InRun := False;
  RunStart := 0;
  RunEnd := 0;
  for I := 0 to High(aSegments) do
  begin
    if SameText(aSegments[I].Speaker, aRawSpeaker) then
    begin
      if not InRun then
      begin
        InRun := True;
        RunStart := aSegments[I].StartTime;
      end;
      RunEnd := aSegments[I].EndTime;
    end
    else if InRun then
    begin
      if (RunEnd - RunStart) > (BestEnd - BestStart) then
      begin
        BestStart := RunStart;
        BestEnd := RunEnd;
      end;
      InRun := False;
    end;
  end;
  if InRun and ((RunEnd - RunStart) > (BestEnd - BestStart)) then
  begin
    BestStart := RunStart;
    BestEnd := RunEnd;
  end;

  if (BestEnd - BestStart) < MIN_SAMPLE_SEC then
    Exit; // muestra demasiado corta: se intentara en un proximo segmento

  if (BestEnd - BestStart) > MAX_SAMPLE_SEC then
    BestEnd := BestStart + MAX_SAMPLE_SEC;

  // Recortar el PCM (16 kHz mono PCM16 -> 32000 bytes/s, alineado a muestra)
  StartByte := (Round(BestStart * SEG_SAMPLE_RATE) * 2);
  LenBytes := (Round((BestEnd - BestStart) * SEG_SAMPLE_RATE) * 2);
  if StartByte + LenBytes > Length(aPcm) then
    LenBytes := Length(aPcm) - StartByte;
  if LenBytes <= 0 then
    Exit;

  Pcm := TMemoryStream.Create;
  try
    Pcm.WriteBuffer(aPcm[StartByte], LenBytes);
    if not ConvertPCMStreamToWAVStream(Pcm, Wav, SEG_SAMPLE_RATE, 1, 16) then
      Exit;
    try
      aName := Format('Hablante %d', [FAudioApi.KnownSpeakerCount + 1]);
      FAudioApi.AddKnownSpeaker(aName, Wav, 'audio/wav');
      FSpeakerNames := FSpeakerNames + [aName];
      Result := True;
      SafeWriteLn(Format('%s (new speaker registered: %s)', [FTag, aName]));
    finally
      Wav.Free;
    end;
  finally
    Pcm.Free;
  end;
end;

function TDiarizedRemoteSide.Translate(const aText: string): string;
var
  Prompt: string;
begin
  FChat.NewChat;
  Prompt := Format('Traduce al %s el siguiente texto. Responde UNICAMENTE con la traduccion, ' +
    'sin comentarios ni comillas:'#10'%s', [TARGET_LANG_REMOTE, aText]);
  Result := Trim(FChat.AddMessageAndRun(Prompt, 'user', []));
end;

procedure TDiarizedRemoteSide.ProcessSegment(const aPcm: TBytes);
var
  Data: TBytes;
begin
  Data := aPcm; // copia de referencia para la captura del closure
  TTask.Run(
    procedure
    begin
      try
        ProcessSegmentWork(Data);
      except
        on E: Exception do
          SafeWriteLn(Format('%s ERROR diarizing/translating: %s', [FTag, E.Message]));
      end;
    end);
end;

procedure TDiarizedRemoteSide.ProcessSegmentWork(const aPcm: TBytes);
var
  PcmStream, WavStream, TtsStream: TMemoryStream;
  Media: TAiMediaFile;
  Res: TTranscriptionResult;
  Batch: TDictionary<string, string>; // speaker crudo -> nombre a mostrar
  I, Idx: Integer;
  Raw, Display, GroupSpeaker, GroupText, Translated: string;
  TtsPcm: TBytes;

  procedure EmitGroup;
  var
    VIdx: Integer;
  begin
    if (GroupText = '') or FClosing then
      Exit;
    SafeWriteLn(Format('%s %s: %s', [FTag, GroupSpeaker, GroupText]));
    Translated := Translate(GroupText);
    if Translated = '' then
      Exit;
    SafeWriteLn(Format('%s    -> %s', [FTag, Translated]));

    // TTS voice according to the registered speaker
    VIdx := SpeakerIndex(GroupSpeaker);
    if (VIdx >= 0) and (VIdx <= High(SPEAKER_VOICES)) then
      FAudioApi.TTSVoice := SPEAKER_VOICES[VIdx]
    else
      FAudioApi.TTSVoice := TAiTTSVoice.tvNova;

    TtsStream := FAudioApi.Speech(Translated);
    try
      if (TtsStream <> nil) and (TtsStream.Size > 0) and not FClosing and FPlayer.Active then
      begin
        SetLength(TtsPcm, TtsStream.Size);
        TtsStream.Position := 0;
        TtsStream.ReadBuffer(TtsPcm[0], TtsStream.Size);
        FCapture.Muted := True; // anti-realimentacion (se libera en OnStateChange)
        FPlayer.PlayPCM16(TtsPcm, TTS_PCM_RATE, 1);
      end;
    finally
      TtsStream.Free;
    end;
  end;

begin
  FLock.Enter;
  try
    if FClosing then
      Exit;

    // 1) PCM -> WAV -> transcripcion diarizada
    PcmStream := TMemoryStream.Create;
    try
      PcmStream.WriteBuffer(aPcm[0], Length(aPcm));
      if not ConvertPCMStreamToWAVStream(PcmStream, WavStream, SEG_SAMPLE_RATE, 1, 16) then
        Exit;
    finally
      PcmStream.Free;
    end;

    Media := TAiMediaFile.Create;
    try
      Media.LoadFromStream('segment.wav', WavStream);
    finally
      WavStream.Free;
    end;

    try
      try
        Res := FAudioApi.Transcribe(Media);
      except
        on E: Exception do
        begin
          // If the API rejects the registered speaker samples, clear
          // the registry and retry without them (they will be re-registered later).
          if Pos('known_speaker', LowerCase(E.Message)) > 0 then
          begin
            SafeWriteLn(FTag + ' (speaker samples rejected by the API: restarting registration)');
            FAudioApi.ClearKnownSpeakers;
            FSpeakerNames := nil;
            Res := FAudioApi.Transcribe(Media);
          end
          else
            raise;
        end;
      end;
    finally
      Media.Free;
    end;

    try
      if Length(Res.Segments) = 0 then
      begin
        // No segments (silence/music): nothing to translate
        if Trim(Res.Text) <> '' then
          SafeWriteLn(Format('%s (no speakers) %s', [FTag, Trim(Res.Text)]));
        Exit;
      end;

      // 2) Mapear hablantes: conocidos -> su nombre; nuevos -> registrar
      Batch := TDictionary<string, string>.Create;
      try
        for I := 0 to High(Res.Segments) do
        begin
          Raw := Res.Segments[I].Speaker;
          if (Raw = '') or Batch.ContainsKey(Raw) then
            Continue;
          Idx := SpeakerIndex(Raw);
          if Idx >= 0 then
            Batch.Add(Raw, FSpeakerNames[Idx]) // ya registrado: nombre estable
          else if TryEnrollSpeaker(aPcm, Raw, Res.Segments, Display) then
            Batch.Add(Raw, Display)
          else
            Batch.Add(Raw, 'Hablante ' + Raw); // sin registrar (muestra corta o cupo lleno)
        end;

        // 3) Agrupar segmentos consecutivos del mismo hablante y emitir
        GroupSpeaker := '';
        GroupText := '';
        for I := 0 to High(Res.Segments) do
        begin
          Raw := Res.Segments[I].Speaker;
          if not Batch.TryGetValue(Raw, Display) then
            Display := 'Hablante ?';
          if Display <> GroupSpeaker then
          begin
            EmitGroup;
            GroupSpeaker := Display;
            GroupText := Trim(Res.Segments[I].Text);
          end
          else
            GroupText := GroupText + ' ' + Trim(Res.Segments[I].Text);
        end;
        EmitGroup;
      finally
        Batch.Free;
      end;
    finally
      Res.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

type
  // --------------------------------------------------------------------------
  // Canal [YO]: microfono -> Realtime STT -> traduccion -> TTS al cable
  // (identico al demo 063)
  // --------------------------------------------------------------------------
  TLocalSide = class
  private
    FTag: string;
    FClosing: Boolean;
    FCapture: TAiAudioCapture;
    FSTT: TAiOpenAiRealtimeSTT;
    FChat: TAiChatConnection;
    FTTS: TAiOpenAiAudio;
    FPlayer: TAiAudioPlayer;
    FMuteCapture: TAiAudioCapture;
    FChatLock: TCriticalSection;
    procedure SttSessionReady(Sender: TObject);
    procedure SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
    procedure SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
  public
    constructor Create(const aPlayerDeviceId: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property MuteCapture: TAiAudioCapture read FMuteCapture write FMuteCapture;
  end;

constructor TLocalSide.Create(const aPlayerDeviceId: string);
begin
  inherited Create;
  FTag := '[ME]   ';
  FChatLock := TCriticalSection.Create;

  FChat := TAiChatConnection.Create(nil);
  FChat.DriverName := TRANSLATOR_DRIVER;
  FChat.Model := TRANSLATOR_MODEL;
  FChat.Params.Values['Asynchronous'] := 'False';
  FChat.Params.Values['ApiKey'] := TRANSLATOR_APIKEY;

  FTTS := TAiOpenAiAudio.Create(nil);
  FTTS.ApiKey := '@OPENAI_API_KEY';
  FTTS.TTSModel := TAiTTSModel.gpt_4o_mini_tts;
  FTTS.TTSVoice := TAiTTSVoice.tvOnyx;
  FTTS.TTSResponseFormat := TAiTTSResponseFormat.trfPcm;
  FTTS.TTSSpeed := 1.0;

  FPlayer := TAiAudioPlayer.Create(nil);
  FPlayer.DeviceId := aPlayerDeviceId;
  FPlayer.OnError := PlayerError;
  FPlayer.OnStateChange := PlayerStateChange;

  FSTT := TAiOpenAiRealtimeSTT.Create(nil);
  FSTT.ApiKey := STT_APIKEY;
  FSTT.Model := STT_MODEL;
  // [ME] channel (single speaker): gpt-live-transcribe (Aug 2026).
  // The remote channel still uses gpt-4o-transcribe-diarize because the new
  // models do NOT support diarization.
  FSTT.TranscriptionModel := otmGptLiveTranscribe;
  FSTT.TranscriptionPrompt := 'Mi voz en una reunion de trabajo traducida';
  FSTT.Language := STT_LANG_LOCAL;
  FSTT.OnSessionReady := SttSessionReady;
  FSTT.OnTranscriptCompleted := SttTranscriptCompleted;
  FSTT.OnError := SttError;

  FCapture := TAiAudioCapture.Create(nil);
  FCapture.Source := asMicrophone;
  FCapture.OutputSampleRate := 16000;
  FCapture.OutputChannels := 1;
  FCapture.RealtimeSTT := FSTT;
  FCapture.OnError := CaptureError;
end;

destructor TLocalSide.Destroy;
begin
  Stop;
  FChatLock.Enter;
  try
    FClosing := True;
  finally
    FChatLock.Leave;
  end;
  FCapture.Free;
  FSTT.Free;
  FPlayer.Free;
  FTTS.Free;
  FChat.Free;
  FChatLock.Free;
  inherited;
end;

procedure TLocalSide.Start;
begin
  FPlayer.Active := True;
  FSTT.Connect;
  FCapture.Active := True;
end;

procedure TLocalSide.Stop;
begin
  FClosing := True;
  if Assigned(FCapture) then
    FCapture.Active := False;
  if Assigned(FSTT) and FSTT.IsConnected then
    FSTT.Disconnect;
  if Assigned(FPlayer) then
    FPlayer.Active := False;
end;

procedure TLocalSide.SttSessionReady(Sender: TObject);
begin
  SafeWriteLn(FTag + ' STT connected and ready.');
end;

procedure TLocalSide.SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
begin
  SafeWriteLn(Format('%s ERROR STT [%s]: %s', [FTag, ErrorCode, ErrorMsg]));
end;

procedure TLocalSide.CaptureError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR capture: ' + ErrorMessage);
end;

procedure TLocalSide.PlayerError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR playback: ' + ErrorMessage);
end;

procedure TLocalSide.PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
begin
  if (not aIsPlaying) and Assigned(FMuteCapture) then
    FMuteCapture.Muted := False;
end;

procedure TLocalSide.SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
var
  Text: string;
begin
  Text := Trim(Transcript);
  if Text = '' then
    Exit;
  SafeWriteLn(Format('%s %s', [FTag, Text]));
  TTask.Run(
    procedure
    var
      Prompt, Res: string;
      TtsStream: TMemoryStream;
      Pcm: TBytes;
    begin
      try
        FChatLock.Enter;
        try
          if FClosing then
            Exit;
          FChat.NewChat;
          Prompt := Format('Traduce al %s el siguiente texto. Responde UNICAMENTE con la traduccion, ' +
            'sin comentarios ni comillas:'#10'%s', [TARGET_LANG_LOCAL, Text]);
          Res := Trim(FChat.AddMessageAndRun(Prompt, 'user', []));
          if Res = '' then
            Exit;
          SafeWriteLn(Format('%s    -> %s', [FTag, Res]));

          TtsStream := FTTS.Speech(Res);
          try
            if (TtsStream = nil) or (TtsStream.Size = 0) then
              Exit;
            SetLength(Pcm, TtsStream.Size);
            TtsStream.Position := 0;
            TtsStream.ReadBuffer(Pcm[0], TtsStream.Size);
          finally
            TtsStream.Free;
          end;

          if FClosing or not FPlayer.Active then
            Exit;
          if Assigned(FMuteCapture) then
            FMuteCapture.Muted := True;
          FPlayer.PlayPCM16(Pcm, TTS_PCM_RATE, 1);
        finally
          FChatLock.Leave;
        end;
      except
        on E: Exception do
          SafeWriteLn(Format('%s ERROR translating/TTS: %s', [FTag, E.Message]));
      end;
    end);
end;

// ============================================================================

function FindMeetingDevice(out aDeviceId, aDeviceName: string): Boolean;
var
  D: TAiAudioDeviceInfo;
begin
  Result := False;
  aDeviceId := '';
  aDeviceName := '';
  for D in TAiAudioPlayer.GetPlaybackDevices do
    if Pos(LowerCase(MEETING_DEVICE_HINT), LowerCase(D.DeviceName)) > 0 then
    begin
      aDeviceId := D.EndpointId;
      aDeviceName := D.DeviceName;
      Exit(True);
    end;
end;

var
  Remote: TDiarizedRemoteSide;
  Local: TLocalSide;
  StopRequested: Boolean;
  MeetingDeviceId, MeetingDeviceName: string;
  HasCable: Boolean;
  D: TAiAudioDeviceInfo;

begin
  SetConsoleOutputCP(CP_UTF8);
  StopRequested := False;
  GConsoleLock := TCriticalSection.Create;
  try
    try
      WriteLn('=== Voice bridge with DIARIZATION (MakerAI) ===');
      WriteLn;
      WriteLn('  [THEM] loopback -> diarization -> per-speaker translation -> TTS');
      WriteLn('          (each meeting speaker with a distinct voice)');
      WriteLn('  [ME]    microphone -> Realtime -> translation -> TTS to cable');
      WriteLn;

      if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
      begin
        WriteLn('ERROR: the environment variable OPENAI_API_KEY is not defined.');
        Exit;
      end;

      HasCable := FindMeetingDevice(MeetingDeviceId, MeetingDeviceName);
      if HasCable then
      begin
        WriteLn('Virtual cable: ' + MeetingDeviceName + '  (meeting mic = CABLE Output)');
        for D in TAiAudioPlayer.GetPlaybackDevices do
          if D.IsDefault and SameText(D.EndpointId, MeetingDeviceId) then
          begin
            WriteLn;
            WriteLn('*** WARNING: "CABLE Input" is the DEFAULT output of Windows.          ***');
            WriteLn('*** Set your HEADPHONES as the default output or you will hear nothing.***');
            Break;
          end;
      end
      else
      begin
        WriteLn('WARNING: no virtual cable ("' + MEETING_DEVICE_HINT + '"): TEST MODE,');
        WriteLn('  English TTS will play through the default device.');
        MeetingDeviceId := '';
      end;
      WriteLn;

      Remote := TDiarizedRemoteSide.Create;
      Local := TLocalSide.Create(MeetingDeviceId);
      if not HasCable then
        Local.MuteCapture := Remote.Capture;
      try
        Remote.Start;
        Local.Start;

        WriteLn('Bridge active... press ENTER to finish.');
        WriteLn;

        TTask.Run(
          procedure
          begin
            ReadLn;
            StopRequested := True;
          end);

        while not StopRequested do
          CheckSynchronize(50);

        WriteLn('Stopping...');
        Remote.Stop;
        Local.Stop;
        CheckSynchronize(200);
      finally
        Remote.Free;
        Local.Free;
      end;
    except
      on E: Exception do
        WriteLn(E.ClassName, ': ', E.Message);
    end;
  finally
    GConsoleLock.Free;
  end;

end.
