// MakerAI Suite — Driver OpenAI Realtime STT
// wss://api.openai.com/v1/realtime  (RFC 6455 + OpenAI Realtime protocol v1)
//
// Supported models: gpt-realtime-2.1 (default — better alphanumeric recognition and noise/silence handling), gpt-realtime-2.1-mini (faster/cheaper), gpt-realtime (previous)
// Transcription models:
//   gpt-live-transcribe (default — low latency, WER 9.60% vs 11.65% whisper)
//   gpt-transcribe (confirmed turns; uses previous turns as context)
//   gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1 (DEPRECATED by OpenAI on 2026-08-26; will be disabled on 2027-02-26)
// New models accept context: TranscriptionPrompt (free topic), TranscriptionKeywords (domain terms), Languages (multi-language) and LowDelay (faster partials at the expense of accuracy).
// Audio: PCM16, 24kHz, mono, little-endian
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.Realtime.OpenAI;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.IOUtils,
  uMakerAi.Realtime, uMakerAi.Realtime.WebSocket, uMakerAi.WebSocket.Client;

type
  // otmGpt4oTranscribe, otmGpt4oMiniTranscribe and otmWhisper1: DEPRECATED by
  // OpenAI on 2026-08-26, disabled on 2027-02-26. Retained to not break existing
  // DFM/FMX; migrate to otmGptLiveTranscribe or otmGptTranscribe.
  TAiOpenAiTranscriptionModel = (
    otmGpt4oTranscribe,     // gpt-4o-transcribe (DEPRECATED, disabled 2027-02-26)
    otmGpt4oMiniTranscribe, // gpt-4o-mini-transcribe (DEPRECATED, disabled 2027-02-26)
    otmWhisper1,            // whisper-1 (DEPRECATED, disabled 2027-02-26)
    otmGptLiveTranscribe,   // gpt-live-transcribe (recommended for live)
    otmGptTranscribe        // gpt-transcribe (confirmed turns + context)
  );

  TAiOpenAiRealtimeSTT = class(TAiRealtimeBase)
  private
    FWebSocket:          TAiRealtimeWSClient;
    FConnectThread:      TThread; // connection thread — waited for before freeing FWebSocket
    FTranscriptionModel: TAiOpenAiTranscriptionModel;
    FSessionConfigured:  Boolean;
    // Transcription context (only gpt-live-transcribe/gpt-transcribe models)
    FTranscriptionPrompt:   string;   // free description of the topic/environment
    FTranscriptionKeywords: TStrings; // expected domain terms
    FLanguages:             TStrings; // expected languages (multi); if empty,
                                      // Language (from base) is used
    FLowDelay:              Boolean;  // delay:'low' — only gpt-live-transcribe
    procedure SetTranscriptionKeywords(const Value: TStrings);
    procedure SetLanguages(const Value: TStrings);
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    procedure ProcessServerEvent(const JObj: TJSONObject);
    procedure SendSessionUpdate;
    function  VADObject: TJSONObject;
    function  TranscriptionModelStr: string;
    function  BuildWssUrl: string;
    protected
    function  GetTargetSampleRate: Integer; override;
    procedure InternalSendAudio(const ResampledPCM16: TBytes); override;
    procedure InternalConnect;    override;
    procedure InternalDisconnect; override;
    procedure InternalCommitAudio; override;
    procedure InternalClearAudio;  override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  published
    property TranscriptionModel: TAiOpenAiTranscriptionModel
      read  FTranscriptionModel
      write FTranscriptionModel
      default otmGptLiveTranscribe;
    // Free context of the recording (topic, environment) — improves accuracy.
    // Only gpt-live-transcribe / gpt-transcribe
    property TranscriptionPrompt: string
      read FTranscriptionPrompt write FTranscriptionPrompt;
    // Expected domain terms (names, products, codes) — one per line,
    // without < > or line breaks. Only new models
    property TranscriptionKeywords: TStrings
      read FTranscriptionKeywords write SetTranscriptionKeywords;
    // Expected languages when audio may mix multiple languages (BCP-47 codes,
    // one per line). Empty = uses Language. Only new models
    property Languages: TStrings read FLanguages write SetLanguages;
    // Faster partials at the expense of accuracy (only gpt-live-transcribe)
    property LowDelay: Boolean read FLowDelay write FLowDelay default False;
  end;

  // -------------------------------------------------------------------------
  // Continuous streaming voice translation (gpt-realtime-translate, May 2026)
  // wss://api.openai.com/v1/realtime/translations
  //
  // Unlike normal Realtime, there is NO VAD or turns: audio is sent
  // continuously (including silences) and the server emits in parallel:
  //   session.input_transcript.delta  -> OnTranscriptDelta   (source language)
  //   session.output_transcript.delta -> OnAssistantTextDelta (translated text)
  //   session.output_audio.delta      -> OnAudioChunk (translated TTS, PCM16 24k)
  // On disconnect, session.close is sent; session.closed triggers
  // OnAssistantText (full translated text) + OnAudioDone.
  // -------------------------------------------------------------------------
  TAiOpenAiRealtimeTranslate = class(TAiRealtimeVoiceBase)
  private
    FWebSocket:         TAiRealtimeWSClient;
    FConnectThread:     TThread;
    FSessionConfigured: Boolean;
    FTargetLanguage:    string;  // output language ('es', 'en', ...)
    FTranslatedText:    string;  // accumulated translated transcript
    FSourceTranscription: Boolean; // also emit source transcript
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    procedure ProcessServerEvent(const JObj: TJSONObject);
    procedure SendSessionUpdate;
  protected
    function  GetTargetSampleRate: Integer; override;
    procedure InternalSendAudio(const ResampledPCM16: TBytes); override;
    procedure InternalConnect;    override;
    procedure InternalDisconnect; override;
    // No turn buffer: commit and clear do not apply to continuous stream
    procedure InternalCommitAudio; override;
    procedure InternalClearAudio;  override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  published
    // Language to which incoming audio is translated (ISO code: 'es', 'en'...)
    property TargetLanguage: string read FTargetLanguage write FTargetLanguage;
    // Also emit transcription in the SOURCE language via
    // OnTranscriptDelta (by default the endpoint only delivers the translation)
    property SourceTranscription: Boolean read FSourceTranscription
      write FSourceTranscription default False;
  end;

  Procedure Register;

implementation


const
  CTRANSLATE_WSS = 'wss://api.openai.com/v1/realtime/translations';
  CTRANSLATE_LOG = ''; // diagnostic log path; '' to disable

procedure TrLog(const AMsg: string);
begin
  if CTRANSLATE_LOG = '' then Exit;
  try
    TFile.AppendAllText(CTRANSLATE_LOG,
      FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMsg + sLineBreak);
  except end;
end;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiOpenAiRealtimeSTT, TAiOpenAiRealtimeTranslate]);
end;

{ TAiOpenAiRealtimeSTT }

constructor TAiOpenAiRealtimeSTT.Create(AOwner: TComponent);
begin
  inherited;
  FTranscriptionModel := otmGptLiveTranscribe;
  FSessionConfigured  := False;
  FConnectThread      := nil;
  FLowDelay           := False;
  FTranscriptionKeywords := TStringList.Create;
  FLanguages             := TStringList.Create;
  FWebSocket          := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame       := OnWSFrame;
  FWebSocket.OnConnected   := OnWSConnected;
  FWebSocket.OnDisconnected:= OnWSDisconnected;
  FWebSocket.OnError       := OnWSError;
end;

destructor TAiOpenAiRealtimeSTT.Destroy;
begin
  if IsConnected then InternalDisconnect;
  // Abort pending connection even if not yet connected
  if Assigned(FConnectThread) then
  begin
    FWebSocket.Disconnect; // close WinHTTP handles to unblock the thread
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FWebSocket.Free;
  FTranscriptionKeywords.Free;
  FLanguages.Free;
  inherited;
end;

procedure TAiOpenAiRealtimeSTT.SetTranscriptionKeywords(const Value: TStrings);
begin
  FTranscriptionKeywords.Assign(Value);
end;

procedure TAiOpenAiRealtimeSTT.SetLanguages(const Value: TStrings);
begin
  FLanguages.Assign(Value);
end;

class function TAiOpenAiRealtimeSTT.GetDriverName: string;
begin
  Result := 'OpenAI';
end;

class function TAiOpenAiRealtimeSTT.GetDefaultModel: string;
begin
  Result := 'gpt-realtime-2.1';
end;

function TAiOpenAiRealtimeSTT.GetTargetSampleRate: Integer;
begin
  Result := 24000; // OpenAI Realtime API requires PCM16 at 24kHz
end;

function TAiOpenAiRealtimeSTT.TranscriptionModelStr: string;
begin
  case FTranscriptionModel of
    otmGpt4oTranscribe:     Result := 'gpt-4o-transcribe';
    otmGpt4oMiniTranscribe: Result := 'gpt-4o-mini-transcribe';
    otmWhisper1:            Result := 'whisper-1';
    otmGptTranscribe:       Result := 'gpt-transcribe';
  else
    Result := 'gpt-live-transcribe';
  end;
end;

function TAiOpenAiRealtimeSTT.BuildWssUrl: string;
var
  M: string;
begin
  M := Model;
  if M = '' then M := GetDefaultModel;
  Result := 'wss://api.openai.com/v1/realtime?model=' + M;
end;

function TAiOpenAiRealtimeSTT.VADObject: TJSONObject;
begin
  if VADMode = rvmManual then
  begin
    Result := nil;
    Exit;
  end;
  Result := TJSONObject.Create;
  if VADMode = rvmSemanticVad then
    Result.AddPair('type', 'semantic_vad')
  else
  begin
    Result.AddPair('type', 'server_vad');
    Result.AddPair('threshold',           TJSONNumber.Create(VADThreshold));
    Result.AddPair('prefix_padding_ms',   TJSONNumber.Create(PrefixPaddingMs));
    Result.AddPair('silence_duration_ms', TJSONNumber.Create(SilenceDurationMs));
  end;
  // Pure transcription — do not generate LLM response after the turn
  Result.AddPair('create_response', TJSONFalse.Create);
end;

procedure TAiOpenAiRealtimeSTT.SendSessionUpdate;
// Updated schema 2026: fields are nested under session.audio.input.
// session.type = 'realtime' for gpt-realtime.
// modalities remains at session level (outside audio).
var
  JMsg, JSession, JAudio, JInput, JTranscription, JVAD, JFormat, JNoise: TJSONObject;
  JLanguages, JKeywords: TJSONArray;
  I: Integer;
begin
  JMsg     := TJSONObject.Create;
  JSession := TJSONObject.Create;
  JAudio   := TJSONObject.Create;
  JInput   := TJSONObject.Create;

  JMsg.AddPair('type', 'session.update');
  JSession.AddPair('type', 'realtime');

  // Input audio format: PCM16 at 24 kHz
  JFormat := TJSONObject.Create;
  JFormat.AddPair('type', 'audio/pcm');
  JFormat.AddPair('rate', TJSONNumber.Create(24000));
  JInput.AddPair('format', JFormat);

  // Transcription model + context
  JTranscription := TJSONObject.Create;
  JTranscription.AddPair('model', TranscriptionModelStr);
  if FTranscriptionModel in [otmGptLiveTranscribe, otmGptTranscribe] then
  begin
    // New models: languages (array), prompt, keywords and delay
    JLanguages := nil;
    if FLanguages.Count > 0 then
    begin
      JLanguages := TJSONArray.Create;
      for I := 0 to FLanguages.Count - 1 do
        if Trim(FLanguages[I]) <> '' then
          JLanguages.Add(Trim(FLanguages[I]));
    end
    else if Language <> '' then
    begin
      JLanguages := TJSONArray.Create;
      JLanguages.Add(Language);
    end;
    if Assigned(JLanguages) then
      JTranscription.AddPair('languages', JLanguages);

    if FTranscriptionPrompt <> '' then
      JTranscription.AddPair('prompt', FTranscriptionPrompt);

    if FTranscriptionKeywords.Count > 0 then
    begin
      JKeywords := TJSONArray.Create;
      for I := 0 to FTranscriptionKeywords.Count - 1 do
        if Trim(FTranscriptionKeywords[I]) <> '' then
          JKeywords.Add(Trim(FTranscriptionKeywords[I]));
      JTranscription.AddPair('keywords', JKeywords);
    end;

    if FLowDelay and (FTranscriptionModel = otmGptLiveTranscribe) then
      JTranscription.AddPair('delay', 'low');
  end
  else if Language <> '' then
    // Legacy models: singular language field
    JTranscription.AddPair('language', Language);
  JInput.AddPair('transcription', JTranscription);

  // VAD / turn detection
  JVAD := VADObject;
  if Assigned(JVAD) then
    JInput.AddPair('turn_detection', JVAD)
  else
    JInput.AddPair('turn_detection', TJSONNull.Create);

  // Noise reduction (optional)
  if NoiseReduction <> rnrNone then
  begin
    JNoise := TJSONObject.Create;
    if NoiseReduction = rnrNearField then
      JNoise.AddPair('type', 'near_field')
    else
      JNoise.AddPair('type', 'far_field');
    JInput.AddPair('noise_reduction', JNoise);
  end;

  JAudio.AddPair('input', JInput);
  JSession.AddPair('audio', JAudio);
  JMsg.AddPair('session', JSession);
  try
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
end;

procedure TAiOpenAiRealtimeSTT.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType:  string;
  ItemId:     string;
  AudioMs:    Int64;
  Delta:      string;
  Transcript: string;
  ErrMsg:     string;
  ErrCode:    string;
  JError:     TJSONObject;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;

  if EventType = 'session.created' then
  begin
    // The server confirmed the session — we send our configuration
    FSessionConfigured := False;
    SendSessionUpdate;
  end

  else if EventType = 'session.updated' then
  begin
    FSessionConfigured := True;
    DoSessionReady;
  end

  else if EventType = 'input_audio_buffer.speech_started' then
  begin
    AudioMs := 0;
    ItemId  := '';
    JObj.TryGetValue<Int64>('audio_start_ms', AudioMs);
    JObj.TryGetValue<string>('item_id', ItemId);
    DoSpeechStarted(AudioMs, ItemId);
  end

  else if EventType = 'input_audio_buffer.speech_stopped' then
  begin
    AudioMs := 0;
    ItemId  := '';
    JObj.TryGetValue<Int64>('audio_end_ms', AudioMs);
    JObj.TryGetValue<string>('item_id', ItemId);
    DoSpeechStopped(AudioMs, ItemId);
  end

  else if EventType = 'conversation.item.input_audio_transcription.delta' then
  begin
    Delta := '';
    JObj.TryGetValue<string>('delta', Delta);
    if Delta <> '' then
      DoTranscriptDelta(Delta);
  end

  else if EventType = 'conversation.item.input_audio_transcription.completed' then
  begin
    Transcript := '';
    ItemId     := '';
    JObj.TryGetValue<string>('transcript', Transcript);
    JObj.TryGetValue<string>('item_id', ItemId);
    DoTranscriptCompleted(Transcript, ItemId);
  end

  else if EventType = 'conversation.item.input_audio_transcription.failed' then
  begin
    ErrMsg  := 'Transcription failed';
    ErrCode := 'transcription_failed';
    JError  := JObj.GetValue<TJSONObject>('error');
    if Assigned(JError) then
    begin
      JError.TryGetValue<string>('message', ErrMsg);
      JError.TryGetValue<string>('code',    ErrCode);
    end;
    DoError(ErrMsg, ErrCode);
  end

  else if EventType = 'error' then
  begin
    ErrMsg  := 'Unknown error';
    ErrCode := '';
    JError  := JObj.GetValue<TJSONObject>('error');
    if Assigned(JError) then
    begin
      JError.TryGetValue<string>('message', ErrMsg);
      JError.TryGetValue<string>('code',    ErrCode);
    end;
    DoError(ErrMsg, ErrCode);
  end;
end;

{ WebSocket events }

procedure TAiOpenAiRealtimeSTT.OnWSConnected(Sender: TObject);
begin
  // FConnected and the OnConnected event are triggered from DoConnected
  // which we call here; session.update will be sent when session.created arrives
  DoConnected;
end;

procedure TAiOpenAiRealtimeSTT.OnWSDisconnected(Sender: TObject);
begin
  FSessionConfigured := False;
  DoDisconnected;
end;

procedure TAiOpenAiRealtimeSTT.OnWSError(Sender: TObject; const ErrorMsg: string);
begin
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiOpenAiRealtimeSTT.OnWSFrame(Sender: TObject;
  Opcode: TAiRealtimeWSOpcode; const Data: TBytes; IsFinal: Boolean);
var
  JsonStr: string;
  JObj:    TJSONObject;
begin
  if WS_DIAG_LOG <> '' then
    try TFile.AppendAllText(WS_DIAG_LOG,
      'FRAME opcode=' + IntToStr(Ord(Opcode)) + ' len=' + IntToStr(Length(Data)) +
      ' json=' + Copy(TEncoding.UTF8.GetString(Data), 1, 120) + sLineBreak);
    except end;
  if Opcode <> rwsoText then Exit;
  JsonStr := TEncoding.UTF8.GetString(Data);
  JObj    := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if Assigned(JObj) then
  try
    ProcessServerEvent(JObj);
  finally
    JObj.Free;
  end;
end;

{ Implemented abstract methods }

procedure TAiOpenAiRealtimeSTT.InternalConnect;
var
  URL: string;
begin
  FWebSocket.ExtraHeaders.Values['Authorization']          := 'Bearer ' + ResolvedApiKey;
  FWebSocket.ExtraHeaders.Values['Sec-WebSocket-Protocol'] := 'realtime';
  URL := BuildWssUrl;
  // Connect in background with controlled TThread (not fire-and-forget)
  // so we can wait for its completion before freeing FWebSocket
  FConnectThread := TThread.CreateAnonymousThread(procedure begin
    if not FWebSocket.Connect(URL) then
      DoError('Could not connect to WebSocket server', 'connection_failed');
  end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiOpenAiRealtimeSTT.InternalDisconnect;
begin
  FWebSocket.SendClose(1000, '');
  // Abort the ongoing connection by closing WinHTTP handles —
  // WinHTTP calls in FConnectThread will fail and the thread will terminate
  FWebSocket.Disconnect;
  if Assigned(FConnectThread) then
  begin
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FSessionConfigured := False;
  Connected          := False;
end;

procedure TAiOpenAiRealtimeSTT.InternalSendAudio(const ResampledPCM16: TBytes);
var
  JObj: TJSONObject;
  B64:  string;
begin
  if Length(ResampledPCM16) = 0 then Exit;
  // Encode PCM16 as Base64 and send as JSON event
  B64  := TNetEncoding.Base64.EncodeBytesToString(ResampledPCM16);
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type',  'input_audio_buffer.append');
    JObj.AddPair('audio', B64);
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

procedure TAiOpenAiRealtimeSTT.InternalCommitAudio;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'input_audio_buffer.commit');
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

procedure TAiOpenAiRealtimeSTT.InternalClearAudio;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'input_audio_buffer.clear');
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

{ TAiOpenAiRealtimeTranslate }

constructor TAiOpenAiRealtimeTranslate.Create(AOwner: TComponent);
begin
  inherited;
  FSessionConfigured := False;
  FConnectThread     := nil;
  FTargetLanguage    := 'en';
  FWebSocket         := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame        := OnWSFrame;
  FWebSocket.OnConnected    := OnWSConnected;
  FWebSocket.OnDisconnected := OnWSDisconnected;
  FWebSocket.OnError        := OnWSError;
end;

destructor TAiOpenAiRealtimeTranslate.Destroy;
begin
  if IsConnected then InternalDisconnect;
  if Assigned(FConnectThread) then
  begin
    FWebSocket.Disconnect;
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FWebSocket.Free;
  inherited;
end;

class function TAiOpenAiRealtimeTranslate.GetDriverName: string;
begin
  Result := 'OpenAiTranslate';
end;

class function TAiOpenAiRealtimeTranslate.GetDefaultModel: string;
begin
  Result := 'gpt-realtime-translate';
end;

function TAiOpenAiRealtimeTranslate.GetTargetSampleRate: Integer;
begin
  Result := 24000; // PCM16 24 kHz mono
end;

procedure TAiOpenAiRealtimeTranslate.SendSessionUpdate;
var
  JMsg, JSession, JAudio, JOutput, JInput, JTranscription: TJSONObject;
begin
  JMsg     := TJSONObject.Create;
  JSession := TJSONObject.Create;
  JAudio   := TJSONObject.Create;
  JOutput  := TJSONObject.Create;
  JMsg.AddPair('type', 'session.update');
  JOutput.AddPair('language', FTargetLanguage);
  JAudio.AddPair('output', JOutput);
  // Source language transcription is opt-in (default endpoint delivers only translation)
  if FSourceTranscription then
  begin
    JInput := TJSONObject.Create;
    JTranscription := TJSONObject.Create;
    JTranscription.AddPair('model', 'gpt-live-transcribe');
    JInput.AddPair('transcription', JTranscription);
    JAudio.AddPair('input', JInput);
  end;
  JSession.AddPair('audio', JAudio);
  JMsg.AddPair('session', JSession);
  try
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
end;

procedure TAiOpenAiRealtimeTranslate.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType, Delta, AudioB64: string;
  ErrMsg, ErrCode: string;
  JError: TJSONObject;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;

  if (EventType = 'session.created') or (EventType = 'session.updated') then
  begin
    // The translation endpoint does not document a handshake; if the server
    // confirms the session it is notified once
    if not FSessionConfigured then
    begin
      FSessionConfigured := True;
      DoSessionReady;
    end;
  end

  else if EventType = 'session.input_transcript.delta' then
  begin
    Delta := '';
    JObj.TryGetValue<string>('delta', Delta);
    if Delta <> '' then
      DoTranscriptDelta(Delta); // transcription in source language
  end

  else if EventType = 'session.output_transcript.delta' then
  begin
    Delta := '';
    JObj.TryGetValue<string>('delta', Delta);
    if Delta <> '' then
    begin
      FTranslatedText := FTranslatedText + Delta;
      DoAssistantTextDelta(Delta); // translated text
    end;
  end

  else if EventType = 'session.output_audio.delta' then
  begin
    AudioB64 := '';
    if not JObj.TryGetValue<string>('delta', AudioB64) then
      JObj.TryGetValue<string>('audio', AudioB64); // schema tolerance
    if AudioB64 <> '' then
      DoAudioChunk(TNetEncoding.Base64.DecodeStringToBytes(AudioB64));
  end

  else if EventType = 'session.closed' then
  begin
    if FTranslatedText <> '' then
      DoAssistantText(FTranslatedText);
    FTranslatedText := '';
    DoAudioDone;
  end

  else if EventType = 'error' then
  begin
    ErrMsg  := 'Unknown error';
    ErrCode := '';
    JError  := nil;
    JObj.TryGetValue<TJSONObject>('error', JError);
    if Assigned(JError) then
    begin
      JError.TryGetValue<string>('message', ErrMsg);
      JError.TryGetValue<string>('code',    ErrCode);
    end;
    DoError(ErrMsg, ErrCode);
  end;
end;

procedure TAiOpenAiRealtimeTranslate.OnWSConnected(Sender: TObject);
begin
  TrLog('WS_CONNECTED');
  DoConnected;
  // Configure output language immediately: the endpoint accepts audio
  // from the start and does not require waiting for confirmation
  SendSessionUpdate;
  if not FSessionConfigured then
  begin
    FSessionConfigured := True;
    DoSessionReady;
  end;
end;

procedure TAiOpenAiRealtimeTranslate.OnWSDisconnected(Sender: TObject);
begin
  TrLog('WS_DISCONNECTED');
  FSessionConfigured := False;
  DoDisconnected;
end;

procedure TAiOpenAiRealtimeTranslate.OnWSError(Sender: TObject;
  const ErrorMsg: string);
begin
  TrLog('WS_ERROR: ' + ErrorMsg);
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiOpenAiRealtimeTranslate.OnWSFrame(Sender: TObject;
  Opcode: TAiRealtimeWSOpcode; const Data: TBytes; IsFinal: Boolean);
var
  JsonStr: string;
  JObj:    TJSONObject;
begin
  TrLog('FRAME opcode=' + IntToStr(Ord(Opcode)) +
        ' len=' + IntToStr(Length(Data)) +
        ' data=' + Copy(TEncoding.UTF8.GetString(Data), 1, 300));
  if Opcode <> rwsoText then Exit;
  JsonStr := TEncoding.UTF8.GetString(Data);
  JObj    := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if Assigned(JObj) then
  try
    ProcessServerEvent(JObj);
  finally
    JObj.Free;
  end;
end;

procedure TAiOpenAiRealtimeTranslate.InternalConnect;
var
  URL, M: string;
begin
  FWebSocket.ExtraHeaders.Values['Authorization'] := 'Bearer ' + ResolvedApiKey;
  M := Model;
  if M = '' then M := GetDefaultModel;
  URL := CTRANSLATE_WSS + '?model=' + M;
  TrLog('CONNECT url=' + URL + ' lang=' + FTargetLanguage);
  FConnectThread := TThread.CreateAnonymousThread(procedure begin
    if not FWebSocket.Connect(URL) then
      DoError('Could not connect to translation server',
              'connection_failed');
  end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiOpenAiRealtimeTranslate.InternalDisconnect;
var
  JObj: TJSONObject;
begin
  // Graceful stream closure: the server emits session.closed with pending
  // data before closing
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'session.close');
    try FWebSocket.SendText(JObj.ToJSON); except end;
  finally
    JObj.Free;
  end;
  FWebSocket.SendClose(1000, '');
  FWebSocket.Disconnect;
  if Assigned(FConnectThread) then
  begin
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FSessionConfigured := False;
  Connected          := False;
end;

procedure TAiOpenAiRealtimeTranslate.InternalSendAudio(
  const ResampledPCM16: TBytes);
var
  JObj: TJSONObject;
begin
  if Length(ResampledPCM16) = 0 then Exit;
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type',  'session.input_audio_buffer.append');
    JObj.AddPair('audio',
      TNetEncoding.Base64.EncodeBytesToString(ResampledPCM16));
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

procedure TAiOpenAiRealtimeTranslate.InternalCommitAudio;
begin
  // Continuous stream without turns: not applicable
end;

procedure TAiOpenAiRealtimeTranslate.InternalClearAudio;
begin
  // Continuous stream without turns: not applicable
end;

initialization
  TAiRealtimeFactory.Instance.RegisterDriver(
    TAiOpenAiRealtimeSTT.GetDriverName, TAiOpenAiRealtimeSTT);
  TAiRealtimeFactory.Instance.RegisterDriver(
    TAiOpenAiRealtimeTranslate.GetDriverName, TAiOpenAiRealtimeTranslate);

end.
