// MakerAI Suite — Qwen Realtime Drivers (Alibaba Model Studio / DashScope)
// wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime?model=<model>
// Protocol compatible with OpenAI Realtime (beta events: response.audio.delta,
// response.audio_transcript.*). Auth: Authorization: Bearer (@DASHSCOPE_API_KEY).
//
// Three drivers, registered in TAiRealtimeFactory (usable directly from
// TAiRealtimeConnection with DriverName):
//   'Qwen'          TAiQwenRealtimeChat       voice to voice (omni): STT + LLM + TTS
//   'QwenSTT'       TAiQwenRealtimeSTT        live transcription (asr)
//   'QwenTranslate' TAiQwenRealtimeTranslate  simultaneous translation with voice
//
// Audio: input PCM16 mono 16 kHz (all models); output PCM16 24 kHz.
//
// Differences normalized by the driver (verified live, sep 2026):
//   - User transcription arrives in three forms depending on the model:
//       omni:      ...transcription.delta with text='' and stash=accumulated text
//       asr:       ...transcription.text  with text=confirmed + stash=pending
//       translate: ...transcription.delta with incremental delta
//     Everything is converted to OnTranscriptDelta semantics (incremental; if the
//     server rewrites the beginning the full text is emitted, same as Grok).
//   - Each model has its default voice (qwen3.8-omni: Tina; qwen3-omni: Cherry)
//     and rejects foreign voices with an error. Empty voice = server default, except in
//     translation: if session.update does not include voice the server falls to an invalid
//     one (Chelsie), so QwenTranslate sends Tina by default.
//   - VAD: server_vad (rvmSemanticVad maps to server_vad); rvmManual sends
//     turn_detection null and requires CommitAudio + CreateResponse.
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.Realtime.Qwen;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  uMakerAi.Realtime, uMakerAi.Realtime.WebSocket, uMakerAi.WebSocket.Client;

type
  // Common base: WebSocket, session and translation of server events
  TAiQwenRealtimeBase = class(TAiRealtimeVoiceBase)
  private
    FWebSocket:         TAiRealtimeWSClient;
    FConnectThread:     TThread;
    FSessionConfigured: Boolean;
    FUrl:               string;
    FVoice:             string;
    FB64:               TBase64Encoding; // without line breaks
    // Accumulated transcription -> deltas
    FLastItemId:     string;
    FLastTranscript: string;
    // Assistant text in current turn
    FAssistantText:  string;
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    procedure SendJson(AObj: TJSONObject);
    procedure EmitCumulative(const ItemId, Full: string);
  protected
    FInstructions: string; // published only in the conversation driver
    function  VADObject: TJSONValue;
    // Body of 'session' in session.update; each driver adds its own
    function  BuildSession: TJSONObject; virtual; abstract;
    function  GetTargetSampleRate: Integer; override;
    procedure InternalSendAudio(const ResampledPCM16: TBytes); override;
    procedure InternalConnect;    override;
    procedure InternalDisconnect; override;
    procedure InternalCommitAudio; override;
    procedure InternalClearAudio;  override;
    // Process a JSON event from the server (protected: the suite feeds it without red)
    procedure ProcessServerEvent(const JObj: TJSONObject); virtual;
    // Full session.update message (protected: the suite inspects it)
    function  BuildSessionUpdate: TJSONObject;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    // WaveIn callback cannot touch sockets: sending is queued to the main thread
    procedure SendAudioChunk(const PCM16Data: TBytes); override;
    // Request a response (response.create). Needed with VADMode = rvmManual
    // after CommitAudio, or after sending audio from a file in a burst.
    procedure CreateResponse;
  published
    // Base endpoint (other region: wss://dashscope.aliyuncs.com/api-ws/v1/realtime)
    property Url: string read FUrl write FUrl;
    // TTS voice; empty = server default for the model
    property Voice: string read FVoice write FVoice;
  end;

  // 'Qwen' — voice conversation (omni realtime)
  TAiQwenRealtimeChat = class(TAiQwenRealtimeBase)
  protected
    function BuildSession: TJSONObject; override;
  public
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  published
    // Session system prompt
    property Instructions: string read FInstructions write FInstructions;
  end;

  // 'QwenSTT' — live transcription (qwen3-asr-flash-realtime)
  TAiQwenRealtimeSTT = class(TAiQwenRealtimeBase)
  protected
    function BuildSession: TJSONObject; override;
  public
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  end;

  // 'QwenTranslate' — simultaneous translation: OnTranscriptDelta/Completed = source
  // language; OnAssistantTextDelta/Text = translation; OnAudioChunk = translated voice
  TAiQwenRealtimeTranslate = class(TAiQwenRealtimeBase)
  private
    FTargetLanguage: string;
  protected
    function BuildSession: TJSONObject; override;
  public
    constructor Create(AOwner: TComponent); override;
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
  published
    // Target language ('en', 'es', 'zh', 'ja'...)
    property TargetLanguage: string read FTargetLanguage write FTargetLanguage;
  end;

procedure Register;

implementation

const
  CQWENREALTIME_WSS = 'wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiQwenRealtimeChat, TAiQwenRealtimeSTT, TAiQwenRealtimeTranslate]);
end;

{ TAiQwenRealtimeBase }

constructor TAiQwenRealtimeBase.Create(AOwner: TComponent);
begin
  inherited;
  ApiKey := '@DASHSCOPE_API_KEY';
  Model := GetDefaultModel;
  FUrl := CQWENREALTIME_WSS;
  FSessionConfigured := False;
  FConnectThread := nil;
  FB64 := TBase64Encoding.Create(0);
  FWebSocket := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame        := OnWSFrame;
  FWebSocket.OnConnected    := OnWSConnected;
  FWebSocket.OnDisconnected := OnWSDisconnected;
  FWebSocket.OnError        := OnWSError;
end;

destructor TAiQwenRealtimeBase.Destroy;
begin
  if IsConnected then InternalDisconnect;
  if Assigned(FConnectThread) then
  begin
    FWebSocket.Disconnect;
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FWebSocket.Free;
  FB64.Free;
  inherited;
end;

function TAiQwenRealtimeBase.GetTargetSampleRate: Integer;
begin
  Result := 16000; // input for all Qwen realtime models
end;

procedure TAiQwenRealtimeBase.SendJson(AObj: TJSONObject);
begin
  try
    FWebSocket.SendText(AObj.ToJSON);
  finally
    AObj.Free;
  end;
end;

function TAiQwenRealtimeBase.VADObject: TJSONValue;
var
  J: TJSONObject;
begin
  if VADMode = rvmManual then
    Exit(TJSONNull.Create);
  J := TJSONObject.Create;
  J.AddPair('type', 'server_vad');
  J.AddPair('threshold', TJSONNumber.Create(VADThreshold));
  J.AddPair('silence_duration_ms', TJSONNumber.Create(SilenceDurationMs));
  J.AddPair('prefix_padding_ms', TJSONNumber.Create(PrefixPaddingMs));
  Result := J;
end;

function TAiQwenRealtimeBase.BuildSessionUpdate: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'session.update');
  Result.AddPair('session', BuildSession);
end;

procedure TAiQwenRealtimeBase.EmitCumulative(const ItemId, Full: string);
var
  Delta: string;
begin
  if ItemId <> FLastItemId then
  begin
    FLastItemId := ItemId;
    FLastTranscript := '';
  end;
  if Full = FLastTranscript then
    Exit;
  if Full.StartsWith(FLastTranscript) then
    Delta := Copy(Full, Length(FLastTranscript) + 1, MaxInt)
  else
    Delta := Full; // server rewrote the beginning: emit full text
  FLastTranscript := Full;
  if Delta <> '' then
    DoTranscriptDelta(Delta);
end;

procedure TAiQwenRealtimeBase.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType, ItemId, Text, Stash, Delta, Transcript, AudioB64, ErrMsg, ErrCode: string;
  AudioMs: Int64;
  JError: TJSONObject;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;
  ItemId := JObj.GetValue<string>('item_id', '');

  if EventType = 'session.created' then
  begin
    FSessionConfigured := False;
    SendJson(BuildSessionUpdate);
  end

  else if EventType = 'session.updated' then
  begin
    if not FSessionConfigured then
    begin
      FSessionConfigured := True;
      DoSessionReady;
    end;
  end

  else if EventType = 'input_audio_buffer.speech_started' then
  begin
    AudioMs := JObj.GetValue<Int64>('audio_start_ms', 0);
    DoSpeechStarted(AudioMs, ItemId);
  end

  else if EventType = 'input_audio_buffer.speech_stopped' then
  begin
    AudioMs := JObj.GetValue<Int64>('audio_end_ms', 0);
    DoSpeechStopped(AudioMs, ItemId);
  end

  // Partial user transcription: incremental delta (translation) or
  // text + stash accumulated (omni, asr)
  else if (EventType = 'conversation.item.input_audio_transcription.delta') or
          (EventType = 'conversation.item.input_audio_transcription.text') then
  begin
    Delta := JObj.GetValue<string>('delta', '');
    if Delta <> '' then
    begin
      FLastItemId := ItemId;
      FLastTranscript := FLastTranscript + Delta;
      DoTranscriptDelta(Delta);
    end
    else
    begin
      Text := JObj.GetValue<string>('text', '');
      Stash := JObj.GetValue<string>('stash', '');
      EmitCumulative(ItemId, Text + Stash);
    end;
  end

  else if EventType = 'conversation.item.input_audio_transcription.completed' then
  begin
    Transcript := JObj.GetValue<string>('transcript', '');
    FLastItemId := '';
    FLastTranscript := '';
    DoTranscriptCompleted(Trim(Transcript), ItemId);
  end

  else if EventType = 'response.created' then
    FAssistantText := ''

  else if (EventType = 'response.audio_transcript.delta') or (EventType = 'response.text.delta') or
          (EventType = 'response.output_audio_transcript.delta') then
  begin
    Delta := JObj.GetValue<string>('delta', '');
    if Delta <> '' then
    begin
      FAssistantText := FAssistantText + Delta;
      DoAssistantTextDelta(Delta);
    end;
  end

  else if (EventType = 'response.audio_transcript.done') or (EventType = 'response.text.done') or
          (EventType = 'response.output_audio_transcript.done') then
  begin
    // Authoritative full text of the turn
    Transcript := JObj.GetValue<string>('transcript', JObj.GetValue<string>('text', ''));
    if Transcript <> '' then
      FAssistantText := Transcript;
  end

  else if (EventType = 'response.audio.delta') or (EventType = 'response.output_audio.delta') then
  begin
    AudioB64 := JObj.GetValue<string>('delta', '');
    if AudioB64 <> '' then
      DoAudioChunk(TNetEncoding.Base64.DecodeStringToBytes(AudioB64));
  end

  else if EventType = 'response.done' then
  begin
    if Trim(FAssistantText) <> '' then
      DoAssistantText(Trim(FAssistantText));
    FAssistantText := '';
    DoAudioDone;
  end

  else if EventType = 'error' then
  begin
    ErrMsg := 'Unknown error';
    ErrCode := '';
    if JObj.TryGetValue<TJSONObject>('error', JError) then
    begin
      JError.TryGetValue<string>('message', ErrMsg);
      JError.TryGetValue<string>('code', ErrCode);
    end;
    DoError(ErrMsg, ErrCode);
  end;
end;

procedure TAiQwenRealtimeBase.OnWSConnected(Sender: TObject);
begin
  // session.update is sent upon receiving session.created
  DoConnected;
end;

procedure TAiQwenRealtimeBase.OnWSDisconnected(Sender: TObject);
begin
  FSessionConfigured := False;
  DoDisconnected;
end;

procedure TAiQwenRealtimeBase.OnWSError(Sender: TObject; const ErrorMsg: string);
begin
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiQwenRealtimeBase.OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
  const Data: TBytes; IsFinal: Boolean);
var
  V: TJSONValue;
begin
  if Opcode <> rwsoText then Exit;
  V := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Data));
  try
    if V is TJSONObject then
      ProcessServerEvent(TJSONObject(V));
  finally
    V.Free;
  end;
end;

procedure TAiQwenRealtimeBase.SendAudioChunk(const PCM16Data: TBytes);
var
  LData: TBytes;
begin
  if not IsConnected then Exit;
  if Length(PCM16Data) = 0 then Exit;
  LData := Copy(PCM16Data);
  TThread.Queue(nil, procedure
  var
    Resampled: TBytes;
  begin
    if not IsConnected then Exit;
    if InputSampleRate <> GetTargetSampleRate then
      Resampled := ResamplePCM16(LData, InputSampleRate, GetTargetSampleRate)
    else
      Resampled := LData;
    InternalSendAudio(Resampled);
  end);
end;

procedure TAiQwenRealtimeBase.InternalConnect;
var
  LUrl: string;
begin
  // TAiRealtimeConnection copies its ApiKey/Model even if they are empty
  if ApiKey = '' then
    ApiKey := '@DASHSCOPE_API_KEY';
  FWebSocket.ExtraHeaders.Values['Authorization'] := 'Bearer ' + ResolvedApiKey;
  if Model = '' then
    Model := GetDefaultModel;
  LUrl := FUrl + '?model=' + Model;
  FConnectThread := TThread.CreateAnonymousThread(procedure begin
    if not FWebSocket.Connect(LUrl) then
      DoError('Could not connect to the Qwen realtime server', 'connection_failed');
  end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiQwenRealtimeBase.InternalDisconnect;
begin
  FWebSocket.SendClose(1000, '');
  FWebSocket.Disconnect;
  if Assigned(FConnectThread) then
  begin
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FSessionConfigured := False;
  Connected := False;
end;

procedure TAiQwenRealtimeBase.InternalSendAudio(const ResampledPCM16: TBytes);
var
  J: TJSONObject;
begin
  if Length(ResampledPCM16) = 0 then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'input_audio_buffer.append');
  // Base64 WITHOUT line breaks: TNetEncoding.Base64 breaks every 76 characters and
  // DashScope responds "Illegal base64 character d" (xAI and OpenAI tolerate them)
  J.AddPair('audio', FB64.EncodeBytesToString(ResampledPCM16));
  SendJson(J);
end;

procedure TAiQwenRealtimeBase.InternalCommitAudio;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  J.AddPair('type', 'input_audio_buffer.commit');
  SendJson(J);
end;

procedure TAiQwenRealtimeBase.InternalClearAudio;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  J.AddPair('type', 'input_audio_buffer.clear');
  SendJson(J);
end;

procedure TAiQwenRealtimeBase.CreateResponse;
var
  J: TJSONObject;
begin
  if not IsConnected then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'response.create');
  SendJson(J);
end;

{ TAiQwenRealtimeChat }

class function TAiQwenRealtimeChat.GetDriverName: string;
begin
  Result := 'Qwen';
end;

class function TAiQwenRealtimeChat.GetDefaultModel: string;
begin
  Result := 'qwen3.8-omni-flash-realtime';
end;

function TAiQwenRealtimeChat.BuildSession: TJSONObject;
var
  jMods: TJSONArray;
begin
  Result := TJSONObject.Create;
  jMods := TJSONArray.Create;
  jMods.Add('text');
  jMods.Add('audio');
  Result.AddPair('modalities', jMods);
  if FInstructions <> '' then
    Result.AddPair('instructions', FInstructions);
  if FVoice <> '' then
    Result.AddPair('voice', FVoice);
  Result.AddPair('input_audio_format', 'pcm16');
  Result.AddPair('output_audio_format', 'pcm24');
  Result.AddPair('turn_detection', VADObject);
end;

{ TAiQwenRealtimeSTT }

class function TAiQwenRealtimeSTT.GetDriverName: string;
begin
  Result := 'QwenSTT';
end;

class function TAiQwenRealtimeSTT.GetDefaultModel: string;
begin
  Result := 'qwen3-asr-flash-realtime';
end;

function TAiQwenRealtimeSTT.BuildSession: TJSONObject;
var
  jMods: TJSONArray;
  jTr: TJSONObject;
begin
  Result := TJSONObject.Create;
  jMods := TJSONArray.Create;
  jMods.Add('text');
  Result.AddPair('modalities', jMods);
  Result.AddPair('input_audio_format', 'pcm');
  Result.AddPair('sample_rate', TJSONNumber.Create(GetTargetSampleRate));
  if Language <> '' then
  begin
    jTr := TJSONObject.Create;
    jTr.AddPair('language', Language);
    Result.AddPair('input_audio_transcription', jTr);
  end;
  Result.AddPair('turn_detection', VADObject);
end;

{ TAiQwenRealtimeTranslate }

constructor TAiQwenRealtimeTranslate.Create(AOwner: TComponent);
begin
  inherited;
  FTargetLanguage := 'en';
  Voice := 'Tina';
end;

class function TAiQwenRealtimeTranslate.GetDriverName: string;
begin
  Result := 'QwenTranslate';
end;

class function TAiQwenRealtimeTranslate.GetDefaultModel: string;
begin
  Result := 'qwen3.8-livetranslate-flash-realtime';
end;

function TAiQwenRealtimeTranslate.BuildSession: TJSONObject;
var
  jTr: TJSONObject;
begin
  Result := TJSONObject.Create;
  jTr := TJSONObject.Create;
  jTr.AddPair('language', FTargetLanguage);
  Result.AddPair('translation', jTr);
  // Without explicit voice the server falls to Chelsie, which this model rejects
  if Voice <> '' then
    Result.AddPair('voice', Voice)
  else
    Result.AddPair('voice', 'Tina');
end;

initialization
  TAiRealtimeFactory.Instance.RegisterDriver(TAiQwenRealtimeChat.GetDriverName, TAiQwenRealtimeChat);
  TAiRealtimeFactory.Instance.RegisterDriver(TAiQwenRealtimeSTT.GetDriverName, TAiQwenRealtimeSTT);
  TAiRealtimeFactory.Instance.RegisterDriver(TAiQwenRealtimeTranslate.GetDriverName, TAiQwenRealtimeTranslate);

end.
