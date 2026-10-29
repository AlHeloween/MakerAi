// MakerAI Suite — Driver MakerAI Realtime (STT + LLM + TTS)
// wss://api.cimamaker.com/v1/audio/realtime  (RFC 6455 + subprotocol "realtime")
// The server is MKAIServer, which also deploys on-prem: the Endpoint property
// points to another instance (empty = the SaaS above).
//
// Full voice conversation in a single WebSocket:
//   1. STT  — the server transcribes the user's audio (Whisper)
//   2. LLM  — generates the assistant response (mk-scout, mk-pro, etc.)
//   3. TTS  — returns the response as PCM16 audio at 24 kHz
//
// Simplified protocol (no separate audio buffer like OpenAI):
//   Client → {type:"session", model, voice?, language?, ...}   (post-connect)
//   Server → {type:"ready"}                                    → OnSessionReady
//   Client → {type:"audio",  data:"<base64 PCM16>"}           (voice chunks)
//   Client → {type:"commit"}                                   (end of turn)
//   Server → {type:"user_text",      text:"..."}               → OnTranscriptCompleted
//   Server → {type:"assistant_text", text:"..."}               → OnAssistantText
//   Server → {type:"audio",          data:"<base64 PCM16>"}    → OnAudioChunk
//   Server → {type:"audio_done"}                               → OnAudioDone
//   Server → {type:"error",          message:"..."}            → OnError
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.Realtime.MakerAi;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.IOUtils,
  uMakerAi.Realtime, uMakerAi.Realtime.WebSocket, uMakerAi.WebSocket.Client;

type
  // Compatibility aliases — the event types now live in
  // uMakerAi.Realtime (shared by all full-duplex voice drivers)
  TAiRealtimeAssistantTextEvent = uMakerAi.Realtime.TAiRealtimeAssistantTextEvent;
  TAiRealtimeAudioChunkEvent    = uMakerAi.Realtime.TAiRealtimeAudioChunkEvent;

  TAiMakerAiRealtimeChat = class(TAiRealtimeVoiceBase)
  private
    FWebSocket:     TAiRealtimeWSClient;
    FConnectThread: TThread;
    FSessionSent:   Boolean;
    // MakerAI driver specific properties
    FEndpoint:      string;  // '' = the default SaaS (see ResolvedEndpoint)
    FVoice:         string;
    FSttModel:      string;
    FSttPrompt:     string;  // domain glossary for Whisper (stt_prompt field)
    FCallerUri:     string;  // caller identifier (memory per caller)
    FTtsModel:      string;
    FInstructions:  string;
    FRagId:         string;
    FStateless:     Boolean;
    FVadMode:       string;  // '' | 'server' | 'disabled'
    // Simplified VAD events (no parameters, specific to this protocol)
    FOnSpeechStart:   TNotifyEvent;
    FOnSpeechEnd:     TNotifyEvent;
    // Internal WebSocket callbacks
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    // Server event processing
    procedure ProcessServerEvent(const JObj: TJSONObject);
    procedure SendSessionMessage;
    function  ResolvedEndpoint: string;
    // Thread-safe dispatchers for simplified VAD events
    // (DoAssistantText/DoAudioChunk/DoAudioDone are inherited from the base)
    procedure DoSpeechStart;
    procedure DoSpeechEnd;
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
    // Override: dispatches sending to the main thread to avoid blocking the
    // WaveIn callback (which cannot call SChannel/sockets directly).
    procedure SendAudioChunk(const PCM16Data: TBytes); override;
    // Direct TTS on the server without going through STT/LLM ({"type":"say"}).
    // Ideal for deterministic greetings when answering a call; the server
    // responds with audio chunks + audio_done and annotates it in the history.
    procedure Say(const AText: string);
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  published
    // MKAI server WebSocket. Empty (default) = wss://api.cimamaker.com/
    // v1/audio/realtime; it is filled only for a custom instance (on-prem or
    // staging). Being empty by default, it is not written into existing DFMs
    // and the behavior does not change for anyone.
    property Endpoint:     string read FEndpoint     write FEndpoint;
    // Session parameters (optional; all resolved by the server if omitted)
    property Voice:        string read FVoice        write FVoice;
    property SttModel:     string read FSttModel     write FSttModel;
    property SttPrompt:    string read FSttPrompt    write FSttPrompt;
    property CallerUri:    string read FCallerUri    write FCallerUri;
    property TtsModel:     string read FTtsModel     write FTtsModel;
    property Instructions: string read FInstructions write FInstructions;
    property RagId:        string read FRagId        write FRagId;
    // Each commit runs with fresh instructions, without multi-turn history.
    // Useful for pure transformation sessions (translation, dictation, etc.)
    property Stateless:    Boolean read FStateless write FStateless default False;
    // Server VAD: '' or 'disabled' → manual client commit;
    // 'server' → the server detects turns (OpenAI turn_detection server_vad,
    //             threshold 0.5, silence 500ms, prefix 300ms). The client MUST
    //             NOT send type:commit — the server triggers it automatically.
    property VadMode:      string  read FVadMode  write FVadMode;
    // OnAssistantText / OnAudioChunk / OnAudioDone are inherited from
    // TAiRealtimeVoiceBase (published in the base)
    // Server VAD events (speech_start / speech_end from OpenAI)
    property OnSpeechStart: TNotifyEvent read FOnSpeechStart write FOnSpeechStart;
    property OnSpeechEnd:   TNotifyEvent read FOnSpeechEnd   write FOnSpeechEnd;
  end;

  procedure Register;

implementation

const
  CMAKERAIREALTIME_WSS  = 'wss://api.cimamaker.com/v1/audio/realtime';
  CMAKERAIREALTIME_SUBP = 'realtime';
  CMAKERAIREALTIME_LOG  = ''; // debug: 'C:\Temp\makerai_ws.log' (Windows) or '/tmp/makerai_ws.log'

procedure MkLog(const AMsg: string);
begin
  if CMAKERAIREALTIME_LOG = '' then Exit;
  try
    TFile.AppendAllText(CMAKERAIREALTIME_LOG,
      FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMsg + sLineBreak);
  except end;
end;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMakerAiRealtimeChat]);
end;

{ TAiMakerAiRealtimeChat }

constructor TAiMakerAiRealtimeChat.Create(AOwner: TComponent);
begin
  inherited;
  FSessionSent   := False;
  FConnectThread := nil;
  FSttModel      := 'mk-whisper-large';
  FWebSocket     := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame        := OnWSFrame;
  FWebSocket.OnConnected    := OnWSConnected;
  FWebSocket.OnDisconnected := OnWSDisconnected;
  FWebSocket.OnError        := OnWSError;
end;

destructor TAiMakerAiRealtimeChat.Destroy;
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

class function TAiMakerAiRealtimeChat.GetDriverName: string;
begin
  Result := 'MakerAi';
end;

class function TAiMakerAiRealtimeChat.GetDefaultModel: string;
begin
  Result := 'mk-gpt-oss-20b';
end;

function TAiMakerAiRealtimeChat.GetTargetSampleRate: Integer;
begin
  Result := 24000;
end;

procedure TAiMakerAiRealtimeChat.Say(const AText: string);
var
  JMsg: TJSONObject;
begin
  if (AText = '') or not IsConnected then Exit;
  JMsg := TJSONObject.Create;
  try
    JMsg.AddPair('type', 'say');
    JMsg.AddPair('text', AText);
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
  MkLog('SAY sent len=' + IntToStr(Length(AText)));
end;

procedure TAiMakerAiRealtimeChat.SendSessionMessage;
var
  JMsg:   TJSONObject;
  LModel: string;
begin
  LModel := Model;
  if LModel = '' then LModel := GetDefaultModel;
  JMsg := TJSONObject.Create;
  try
    JMsg.AddPair('type',  'session');
    JMsg.AddPair('model', LModel);
    if Language      <> '' then JMsg.AddPair('language',     Language);
    if FVoice        <> '' then JMsg.AddPair('voice',        FVoice);
    if FSttModel     <> '' then JMsg.AddPair('stt_model',    FSttModel);
    if FSttPrompt    <> '' then JMsg.AddPair('stt_prompt',   FSttPrompt);
    if FCallerUri    <> '' then JMsg.AddPair('caller_uri',   FCallerUri);
    if FTtsModel     <> '' then JMsg.AddPair('tts_model',    FTtsModel);
    if FInstructions <> '' then JMsg.AddPair('instructions', FInstructions);
    if FRagId        <> '' then JMsg.AddPair('rag_id',       FRagId);
    if FStateless then JMsg.AddPair('stateless', TJSONBool.Create(True));
    if FVadMode      <> '' then JMsg.AddPair('vad',          FVadMode);
    MkLog('SESSION_JSON ' + JMsg.ToJSON);
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
  FSessionSent := True;
end;

procedure TAiMakerAiRealtimeChat.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType: string;
  AText:     string;
  AudioB64:  string;
  AudioData: TBytes;
  ErrMsg:    string;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;

  if EventType = 'ready' then
    DoSessionReady

  else if EventType = 'user_text' then
  begin
    AText := '';
    JObj.TryGetValue<string>('text', AText);
    if AText <> '' then
      DoTranscriptCompleted(AText, '');
  end

  else if EventType = 'assistant_text' then
  begin
    AText := '';
    JObj.TryGetValue<string>('text', AText);
    if AText <> '' then
      DoAssistantText(AText);
  end

  else if EventType = 'audio' then
  begin
    AudioB64 := '';
    JObj.TryGetValue<string>('data', AudioB64);
    if AudioB64 <> '' then
    begin
      AudioData := TNetEncoding.Base64.DecodeStringToBytes(AudioB64);
      DoAudioChunk(AudioData);
    end;
  end

  else if EventType = 'audio_done' then
    DoAudioDone

  else if EventType = 'speech_start' then
    DoSpeechStart

  else if EventType = 'speech_end' then
    DoSpeechEnd

  else if EventType = 'error' then
  begin
    ErrMsg := 'MakerAI server error';
    if not JObj.TryGetValue<string>('message', ErrMsg) then
      JObj.TryGetValue<string>('error', ErrMsg);
    DoError(ErrMsg, 'server_error');
  end;
end;

{ Thread-safe dispatchers for simplified VAD events }

procedure TAiMakerAiRealtimeChat.DoSpeechStart;
begin
  MkLog('SPEECH_START');
  if not Assigned(FOnSpeechStart) then Exit;
  TThread.Queue(nil, procedure begin
    if Assigned(FOnSpeechStart) then FOnSpeechStart(Self);
  end);
end;

procedure TAiMakerAiRealtimeChat.DoSpeechEnd;
begin
  MkLog('SPEECH_END');
  if not Assigned(FOnSpeechEnd) then Exit;
  TThread.Queue(nil, procedure begin
    if Assigned(FOnSpeechEnd) then FOnSpeechEnd(Self);
  end);
end;

{ WebSocket handlers }

{ Override of SendAudioChunk: queues resampling + sending to the main thread.
  VoiceMonitor calls this method from the WaveIn callback (Windows audio
  system thread), where calling socket or SChannel functions is NOT allowed.
  TThread.Queue moves the operation to the main thread. }
procedure TAiMakerAiRealtimeChat.SendAudioChunk(const PCM16Data: TBytes);
var
  LData: TBytes;
begin
  if not IsConnected then Exit;
  if Length(PCM16Data) = 0 then Exit;
  LData := Copy(PCM16Data); // quick copy before leaving the callback
  TThread.Queue(nil, procedure
  var
    Resampled: TBytes;
    TargetHz:  Integer;
  begin
    if not IsConnected then Exit;
    TargetHz := GetTargetSampleRate;
    if InputSampleRate <> TargetHz then
      Resampled := ResamplePCM16(LData, InputSampleRate, TargetHz)
    else
      Resampled := LData;
    InternalSendAudio(Resampled);
  end);
end;

procedure TAiMakerAiRealtimeChat.OnWSConnected(Sender: TObject);
begin
  MkLog('WS_CONNECTED');
  DoConnected;
  SendSessionMessage;
  MkLog('SESSION_SENT model=' + Model);
end;

procedure TAiMakerAiRealtimeChat.OnWSDisconnected(Sender: TObject);
begin
  MkLog('WS_DISCONNECTED');
  FSessionSent := False;
  DoDisconnected;
end;

procedure TAiMakerAiRealtimeChat.OnWSError(Sender: TObject;
  const ErrorMsg: string);
begin
  MkLog('WS_ERROR: ' + ErrorMsg);
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiMakerAiRealtimeChat.OnWSFrame(Sender: TObject;
  Opcode: TAiRealtimeWSOpcode; const Data: TBytes; IsFinal: Boolean);
var
  JsonStr: string;
  JObj:    TJSONObject;
begin
  MkLog('FRAME opcode=' + IntToStr(Ord(Opcode)) +
        ' len=' + IntToStr(Length(Data)) +
        ' data=' + Copy(TEncoding.UTF8.GetString(Data), 1, 200));
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

{ Implementation of abstract methods }

function TAiMakerAiRealtimeChat.ResolvedEndpoint: string;
begin
  Result := Trim(FEndpoint);
  if Result = '' then
    Result := CMAKERAIREALTIME_WSS;
end;

procedure TAiMakerAiRealtimeChat.InternalConnect;
var
  LUrl: string;
begin
  // Resolved ONCE: the connection thread must not re-read FEndpoint,
  // which the user could change in the meantime.
  LUrl := ResolvedEndpoint;
  MkLog('CONNECT url=' + LUrl + ' key_prefix=' +
        Copy(ResolvedApiKey, 1, 8) + '...');
  FWebSocket.ExtraHeaders.Values['Authorization']          := 'Bearer ' + ResolvedApiKey;
  FWebSocket.ExtraHeaders.Values['Sec-WebSocket-Protocol'] := CMAKERAIREALTIME_SUBP;
  FConnectThread := TThread.CreateAnonymousThread(procedure begin
    MkLog('THREAD_CONNECT_START');
    if not FWebSocket.Connect(LUrl) then
    begin
      MkLog('CONNECT_FAILED');
      DoError('Could not connect to MakerAI WebSocket server',
              'connection_failed');
    end
    else
      MkLog('THREAD_CONNECT_END');
  end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiMakerAiRealtimeChat.InternalDisconnect;
begin
  FWebSocket.SendClose(1000, '');
  FWebSocket.Disconnect;
  if Assigned(FConnectThread) then
  begin
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FSessionSent := False;
  Connected    := False;
end;

procedure TAiMakerAiRealtimeChat.InternalSendAudio(
  const ResampledPCM16: TBytes);
var
  JObj: TJSONObject;
  B64:  string;
begin
  if Length(ResampledPCM16) = 0 then Exit;
  B64  := TNetEncoding.Base64.EncodeBytesToString(ResampledPCM16);
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'audio');
    JObj.AddPair('data', B64);
    FWebSocket.SendText(JObj.ToJSON);
    MkLog('AUDIO_SENT bytes=' + IntToStr(Length(ResampledPCM16)));
  finally
    JObj.Free;
  end;
end;

procedure TAiMakerAiRealtimeChat.InternalCommitAudio;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'commit');
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

procedure TAiMakerAiRealtimeChat.InternalClearAudio;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'clear');
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

initialization
  TAiRealtimeFactory.Instance.RegisterDriver(
    TAiMakerAiRealtimeChat.GetDriverName, TAiMakerAiRealtimeChat);

end.
