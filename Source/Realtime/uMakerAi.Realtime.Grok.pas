unit uMakerAi.Realtime.Grok;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.IOUtils, System.Math, System.SyncObjs, System.Net.HttpClient,
  uMakerAi.Core, uMakerAi.Chat.Messages, uMakerAi.Tools.Functions,
  uMakerAi.Realtime, uMakerAi.Realtime.WebSocket, uMakerAi.WebSocket.Client;

type
  // Model reasoning level while speaking
  TAiGrokReasoningEffort = (
    greHigh, // full reasoning (server default)
    greNone  // no reasoning — lower latency
  );

  // Fallback for function calling when AiFunctions does not handle the function.
  // The handler must assign ToolCall.Response with the result.
  TAiGrokToolCallEvent = procedure(Sender: TObject;
    ToolCall: TAiToolsFunction) of object;

  TAiGrokRealtimeChat = class(TAiRealtimeVoiceBase)
  private
    FWebSocket:         TAiRealtimeWSClient;
    FConnectThread:     TThread; // connection thread — waits before freeing FWebSocket
    FSessionConfigured: Boolean;
    // Grok driver specific properties
    FVoice:           string;
    FInstructions:    string;
    FReasoningEffort: TAiGrokReasoningEffort;
    FIdleTimeoutMs:   Integer;
    FOutputSpeed:     Double;   // 0.7..1.5; 0 = server default
    FKeyterms:        TStrings; // transcription bias (max 100 terms)
    FPronunciationReplace: TStrings; // Phrase=Pronunciation for TTS
    // Phase 3: resumption, binary transport, ephemeral tokens, file_search
    FEnableResumption: Boolean;
    FConversationId:   string;  // assigned by server (conversation.created)
    FBinaryAudio:      Boolean; // raw PCM in binary WS frames (in + out)
    FEphemeralToken:   string;  // auth client-side via WS subprotocol
    FFileSearchCollections: TStrings; // vector_store_ids for file_search
    FFileSearchMaxResults:  Integer;
    FCustomToolsJson:  TStrings; // extra tools in raw JSON (remote MCP, etc.)
    // Function calling / tools
    FAiFunctions:        TAiFunctions; // external reference (FreeNotification)
    FOnCallToolFunction: TAiGrokToolCallEvent;
    FEnableWebSearch:    Boolean;
    FEnableXSearch:      Boolean;
    FPendingToolCalls:   Integer; // tool calls in progress (TInterlocked)
    FHadToolCalls:       Boolean; // current response contains function calls
    FToolsDone:          Boolean; // response.done arrived for the response with tools
    FContinuationSent:   Integer; // guard 0/1 for a single response.create
    // State to convert accumulated transcription -> deltas
    FLastItemId:     string;
    FLastTranscript: string;
    // Accumulator for assistant text in current turn
    FAssistantText:  string;
    // Text spoken before a tool call — preserved so that final OnAssistantText
    // includes the full turn (pre + post tools)
    FCarryAssistantText: string;
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    procedure ProcessServerEvent(const JObj: TJSONObject);
    procedure SendSessionUpdate;
    function  VADObject: TJSONObject;
    function  BuildWssUrl: string;
    function  LanguageHint: string;
    procedure HandleTranscriptionUpdated(const JObj: TJSONObject);
    // Function calling
    procedure SetAiFunctions(const Value: TAiFunctions);
    procedure SetKeyterms(const Value: TStrings);
    procedure SetPronunciationReplace(const Value: TStrings);
    procedure SetFileSearchCollections(const Value: TStrings);
    procedure SetCustomToolsJson(const Value: TStrings);
    function  BuildToolsArray: TJSONArray;
    procedure HandleFunctionCall(const JObj: TJSONObject);
    procedure SendFunctionOutput(const ACallId, AOutput: string);
    procedure TryContinueAfterTools;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function  GetTargetSampleRate: Integer; override;
    procedure InternalSendAudio(const ResampledPCM16: TBytes); override;
    procedure InternalConnect;    override;
    procedure InternalDisconnect; override;
    procedure InternalCommitAudio; override;
    procedure InternalClearAudio;  override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    // Dispatches sending to main thread: WaveIn callback cannot call
    // SChannel/sockets directly (same reason as MakerAI driver)
    procedure SendAudioChunk(const PCM16Data: TBytes); override;
    // Explicitly requests a response from the model (response.create).
    // Needed in VADMode = rvmManual after CommitAudio; with server_vad
    // the server triggers it automatically upon detecting end of turn.
    procedure CreateResponse;
    // Forced TTS phrase without going through the model (IVR announcements, disclosures).
    // AInterruptible=False discards user audio until finished.
    procedure ForceMessage(const AText: string; AInterruptible: Boolean = True);
    // Mints an ephemeral token via POST /v1/realtime/client_secrets using the
    // API key (accepts @VAR_NAME convention). Intended for backends that
    // deliver the token to mobile/browser clients; assign it in
    // EphemeralToken. Raises exception if server rejects request.
    class function MintEphemeralToken(const AApiKey: string;
      AExpiresSeconds: Integer = 300): string;
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
    // Conversation id assigned by server (conversation.created).
    // Persist and reassign before Connect (with EnableResumption=True)
    // to resume conversation with turn replay (expires after 30 min).
    property ConversationId: string read FConversationId write FConversationId;
  published
    // TTS voice: eva, ara, rex, sal, leo... or voice_id from Custom Voices.
    // Empty = server default
    property Voice: string read FVoice write FVoice;
    // System prompt for the session
    property Instructions: string read FInstructions write FInstructions;
    // Reasoning while speaking (greNone reduces latency)
    property ReasoningEffort: TAiGrokReasoningEffort
      read FReasoningEffort write FReasoningEffort default greHigh;
    // If user does not speak within this period, the model re-engages (0 = omit)
    property IdleTimeoutMs: Integer read FIdleTimeoutMs write FIdleTimeoutMs
      default 0;
    // TTS playback speed (0.7..1.5; 0 = server default)
    property OutputSpeed: Double read FOutputSpeed write FOutputSpeed;
    // Function component (local + MCP); declared in session.update
    // and the driver executes tool calls automatically
    property AiFunctions: TAiFunctions read FAiFunctions write SetAiFunctions;
    // Fallback when AiFunctions does not handle the function (or not assigned)
    property OnCallToolFunction: TAiGrokToolCallEvent
      read FOnCallToolFunction write FOnCallToolFunction;
    // Native xAI tools (executed by server)
    property EnableWebSearch: Boolean read FEnableWebSearch
      write FEnableWebSearch default False;
    property EnableXSearch: Boolean read FEnableXSearch
      write FEnableXSearch default False;
    // Domain terms to bias transcription (max 100)
    property Keyterms: TStrings read FKeyterms write SetKeyterms;
    // TTS pronunciation corrections, format Phrase=Pronunciation
    // (case-insensitive match by whole word)
    property PronunciationReplace: TStrings read FPronunciationReplace
      write SetPronunciationReplace;
    // Session resumption: server caches turns and replays them
    // upon reconnection with same ConversationId (both sessions must
    // enable it; history expires after 30 min of inactivity)
    property EnableResumption: Boolean read FEnableResumption
      write FEnableResumption default False;
    // Raw PCM audio in binary WebSocket frames (input and output):
    // ~33% less bandwidth than base64. JSON events remain as text.
    property BinaryAudio: Boolean read FBinaryAudio
      write FBinaryAudio default False;
    // Ephemeral token (with or without xai-client-secret. prefix). If assigned,
    // authenticates via WebSocket subprotocol and does NOT send the ApiKey —
    // intended for mobile/browser clients. See MintEphemeralToken
    property EphemeralToken: string read FEphemeralToken write FEphemeralToken;
    // Collections (vector_store_ids) for the native file_search tool
    property FileSearchCollections: TStrings read FFileSearchCollections
      write SetFileSearchCollections;
    property FileSearchMaxResults: Integer read FFileSearchMaxResults
      write FFileSearchMaxResults default 0;
    // Additional tools in raw JSON (single object or array of objects), e.g.
    // {"type":"mcp","server_url":"https://...","server_label":"mis-tools"}
    property CustomToolsJson: TStrings read FCustomToolsJson
      write SetCustomToolsJson;
  end;

  procedure Register;

implementation

const
  CGROKREALTIME_WSS = 'wss://api.x.ai/v1/realtime';
  CGROKREALTIME_LOG = ''; // diagnostic log path; '' to disable

procedure GkLog(const AMsg: string);
begin
  if CGROKREALTIME_LOG = '' then Exit;
  try
    TFile.AppendAllText(CGROKREALTIME_LOG,
      FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMsg + sLineBreak);
  except end;
end;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGrokRealtimeChat]);
end;

{ TAiGrokRealtimeChat }

constructor TAiGrokRealtimeChat.Create(AOwner: TComponent);
begin
  inherited;
  FSessionConfigured := False;
  FConnectThread     := nil;
  FReasoningEffort   := greHigh;
  FIdleTimeoutMs     := 0;
  FOutputSpeed       := 0;
  FKeyterms             := TStringList.Create;
  FPronunciationReplace := TStringList.Create;
  FFileSearchCollections := TStringList.Create;
  FCustomToolsJson       := TStringList.Create;
  FFileSearchMaxResults  := 0;
  // Grok default VAD is 0.85; base initializes 0.5 (OpenAI)
  VADThreshold       := 0.85;
  FWebSocket         := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame        := OnWSFrame;
  FWebSocket.OnConnected    := OnWSConnected;
  FWebSocket.OnDisconnected := OnWSDisconnected;
  FWebSocket.OnError        := OnWSError;
end;

destructor TAiGrokRealtimeChat.Destroy;
begin
  if IsConnected then InternalDisconnect;
  // Abort pending connection even if not yet connected
  if Assigned(FConnectThread) then
  begin
    FWebSocket.Disconnect;
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FWebSocket.Free;
  FKeyterms.Free;
  FPronunciationReplace.Free;
  FFileSearchCollections.Free;
  FCustomToolsJson.Free;
  inherited;
end;

procedure TAiGrokRealtimeChat.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FAiFunctions) then
    FAiFunctions := nil;
end;

procedure TAiGrokRealtimeChat.SetAiFunctions(const Value: TAiFunctions);
begin
  if FAiFunctions = Value then Exit;
  FAiFunctions := Value;
  if Assigned(FAiFunctions) then
    FAiFunctions.FreeNotification(Self);
end;

procedure TAiGrokRealtimeChat.SetKeyterms(const Value: TStrings);
begin
  FKeyterms.Assign(Value);
end;

procedure TAiGrokRealtimeChat.SetPronunciationReplace(const Value: TStrings);
begin
  FPronunciationReplace.Assign(Value);
end;

procedure TAiGrokRealtimeChat.SetFileSearchCollections(const Value: TStrings);
begin
  FFileSearchCollections.Assign(Value);
end;

procedure TAiGrokRealtimeChat.SetCustomToolsJson(const Value: TStrings);
begin
  FCustomToolsJson.Assign(Value);
end;

class function TAiGrokRealtimeChat.MintEphemeralToken(const AApiKey: string;
  AExpiresSeconds: Integer): string;
var
  Http: THTTPClient;
  Body: TStringStream;
  Resp: IHTTPResponse;
  JObj: TJSONObject;
  Key, Content: string;
begin
  Result := '';
  Key := AApiKey;
  if (Length(Key) > 1) and (Key[1] = '@') then
    Key := GetEnvironmentVariable(Copy(Key, 2, MaxInt));
  Http := THTTPClient.Create;
  Body := TStringStream.Create(
    '{"expires_after":{"seconds":' + IntToStr(AExpiresSeconds) + '}}',
    TEncoding.UTF8);
  try
    Http.CustomHeaders['Authorization'] := 'Bearer ' + Key;
    Http.ContentType := 'application/json';
    Resp := Http.Post('https://api.x.ai/v1/realtime/client_secrets', Body);
    Content := Resp.ContentAsString(TEncoding.UTF8);
    if (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
      raise Exception.CreateFmt(
        'MintEphemeralToken: HTTP %d — %s', [Resp.StatusCode, Content]);
    JObj := TJSONObject.ParseJSONValue(Content) as TJSONObject;
    if not Assigned(JObj) then
      raise Exception.Create('MintEphemeralToken: response is not valid JSON');
    try
      // Response schema is not documented: look for token in
      // typical locations in OpenAI-compatible APIs
      if not JObj.TryGetValue<string>('client_secret.value', Result) then
        if not JObj.TryGetValue<string>('value', Result) then
          if not JObj.TryGetValue<string>('client_secret', Result) then
            if not JObj.TryGetValue<string>('token', Result) then
              raise Exception.Create(
                'MintEphemeralToken: token not found in response: ' +
                Copy(Content, 1, 300));
    finally
      JObj.Free;
    end;
  finally
    Body.Free;
    Http.Free;
  end;
end;

class function TAiGrokRealtimeChat.GetDriverName: string;
begin
  Result := 'Grok';
end;

class function TAiGrokRealtimeChat.GetDefaultModel: string;
begin
  // Pinned version for stable behavior across releases
  Result := 'grok-voice-think-fast-2.0';
end;

function TAiGrokRealtimeChat.GetTargetSampleRate: Integer;
begin
  Result := 24000; // audio/pcm default for Grok Voice
end;

function TAiGrokRealtimeChat.BuildWssUrl: string;
var
  M: string;
begin
  M := Model;
  if M = '' then M := GetDefaultModel;
  Result := CGROKREALTIME_WSS + '?model=' + M;
  // Resume a previous conversation (replay of cached turns)
  if FEnableResumption and (FConversationId <> '') then
    Result := Result + '&conversation_id=' + FConversationId;
end;

// Grok requires BCP-47 regional variant for Spanish and Portuguese
// (es-MX, not 'es'; pt-BR, not 'pt'). Both documented cases are corrected.
function TAiGrokRealtimeChat.LanguageHint: string;
begin
  Result := Language;
  if SameText(Result, 'es') then Result := 'es-MX'
  else if SameText(Result, 'pt') then Result := 'pt-BR';
end;

function TAiGrokRealtimeChat.VADObject: TJSONObject;
begin
  if VADMode = rvmManual then
  begin
    Result := nil;
    Exit;
  end;
  // Grok only supports server_vad; rvmSemanticVad maps to server_vad
  Result := TJSONObject.Create;
  Result.AddPair('type', 'server_vad');
  Result.AddPair('threshold',           TJSONNumber.Create(VADThreshold));
  Result.AddPair('prefix_padding_ms',   TJSONNumber.Create(PrefixPaddingMs));
  Result.AddPair('silence_duration_ms', TJSONNumber.Create(SilenceDurationMs));
  if FIdleTimeoutMs > 0 then
    Result.AddPair('idle_timeout_ms',   TJSONNumber.Create(FIdleTimeoutMs));
end;

procedure TAiGrokRealtimeChat.SendSessionUpdate;
// Grok schema: voice/instructions/turn_detection/reasoning at session level;
// formats and transcription nested under session.audio.input/output.
var
  JMsg, JSession, JAudio, JInput, JOutput, JFormat, JOutFormat: TJSONObject;
  JTranscription, JVAD, JReasoning, JReplace: TJSONObject;
  JTools, JKeyterms: TJSONArray;
  I: Integer;
begin
  JMsg     := TJSONObject.Create;
  JSession := TJSONObject.Create;
  JAudio   := TJSONObject.Create;
  JInput   := TJSONObject.Create;
  JOutput  := TJSONObject.Create;

  JMsg.AddPair('type', 'session.update');

  if FVoice <> '' then
    JSession.AddPair('voice', FVoice);
  if FInstructions <> '' then
    JSession.AddPair('instructions', FInstructions);

  // VAD / turn detection
  JVAD := VADObject;
  if Assigned(JVAD) then
    JSession.AddPair('turn_detection', JVAD)
  else
    JSession.AddPair('turn_detection', TJSONNull.Create);

  // Reasoning while speaking
  JReasoning := TJSONObject.Create;
  if FReasoningEffort = greNone then
    JReasoning.AddPair('effort', 'none')
  else
    JReasoning.AddPair('effort', 'high');
  JSession.AddPair('reasoning', JReasoning);

  // Tools: local/MCP functions (AiFunctions) + native xAI tools
  JTools := BuildToolsArray;
  if Assigned(JTools) then
    JSession.AddPair('tools', JTools);

  // TTS pronunciation corrections (Phrase=Pronunciation)
  if FPronunciationReplace.Count > 0 then
  begin
    JReplace := TJSONObject.Create;
    for I := 0 to FPronunciationReplace.Count - 1 do
      if FPronunciationReplace.Names[I] <> '' then
        JReplace.AddPair(FPronunciationReplace.Names[I],
                         FPronunciationReplace.ValueFromIndex[I]);
    JSession.AddPair('replace', JReplace);
  end;

  // Session resumption (must also be enabled upon reconnection)
  if FEnableResumption then
  begin
    JReplace := TJSONObject.Create; // reuse local variable
    JReplace.AddPair('enabled', TJSONBool.Create(True));
    JSession.AddPair('resumption', JReplace);
  end;

  // Input format: PCM16 at 24 kHz
  JFormat := TJSONObject.Create;
  JFormat.AddPair('type', 'audio/pcm');
  JFormat.AddPair('rate', TJSONNumber.Create(24000));
  JInput.AddPair('format', JFormat);
  if FBinaryAudio then
    JInput.AddPair('transport', 'binary');

  // Transcription bias: language and domain terms (optional)
  if (Language <> '') or (FKeyterms.Count > 0) then
  begin
    JTranscription := TJSONObject.Create;
    if Language <> '' then
      JTranscription.AddPair('language_hint', LanguageHint);
    if FKeyterms.Count > 0 then
    begin
      JKeyterms := TJSONArray.Create;
      for I := 0 to Min(FKeyterms.Count, 100) - 1 do
        JKeyterms.Add(FKeyterms[I]);
      JTranscription.AddPair('keyterms', JKeyterms);
    end;
    JInput.AddPair('transcription', JTranscription);
  end;

  // Output format: PCM16 at 24 kHz
  JOutFormat := TJSONObject.Create;
  JOutFormat.AddPair('type', 'audio/pcm');
  JOutFormat.AddPair('rate', TJSONNumber.Create(24000));
  JOutput.AddPair('format', JOutFormat);
  if FBinaryAudio then
    JOutput.AddPair('transport', 'binary');
  // Playback speed (only if user configured within valid range)
  if (FOutputSpeed >= 0.7) and (FOutputSpeed <= 1.5) then
    JOutput.AddPair('speed', TJSONNumber.Create(FOutputSpeed));

  JAudio.AddPair('input',  JInput);
  JAudio.AddPair('output', JOutput);
  JSession.AddPair('audio', JAudio);
  JMsg.AddPair('session', JSession);
  try
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
end;

// User transcription: Grok sends the item's ACCUMULATED text in each
// .updated event. The delta is computed against what was already received
// to maintain the OnTranscriptDelta semantics of other drivers.
procedure TAiGrokRealtimeChat.HandleTranscriptionUpdated(const JObj: TJSONObject);
var
  ItemId, Transcript, Delta: string;
begin
  Transcript := '';
  ItemId     := '';
  if not JObj.TryGetValue<string>('transcript', Transcript) then
    JObj.TryGetValue<string>('delta', Transcript); // schema tolerance
  JObj.TryGetValue<string>('item_id', ItemId);
  if Transcript = '' then Exit;

  if ItemId <> FLastItemId then
  begin
    // New audio item: reset accumulator
    FLastItemId     := ItemId;
    FLastTranscript := '';
  end;

  if Transcript.StartsWith(FLastTranscript) then
    Delta := Copy(Transcript, Length(FLastTranscript) + 1, MaxInt)
  else
    Delta := Transcript; // server rewrote text: emit full

  FLastTranscript := Transcript;
  if Delta <> '' then
    DoTranscriptDelta(Delta);
end;

procedure TAiGrokRealtimeChat.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType:  string;
  ItemId:     string;
  AudioMs:    Int64;
  Transcript: string;
  Delta:      string;
  Status:     string;
  AudioB64:   string;
  ErrMsg:     string;
  ErrCode:    string;
  JError:     TJSONObject;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;

  if EventType = 'session.created' then
  begin
    // Server confirmed session — send our configuration
    FSessionConfigured := False;
    SendSessionUpdate;
  end

  else if EventType = 'conversation.created' then
  begin
    // Save id for resumption (?conversation_id= upon reconnection)
    JObj.TryGetValue<string>('conversation.id', FConversationId);
    GkLog('CONVERSATION_ID=' + FConversationId);
  end

  else if (EventType = 'conversation.item.created') or
          (EventType = 'conversation.item.added') then
  begin
    // Conversation items. When resuming with conversation_id, cached turns
    // (user, assistant, tool calls and outputs) arrive replicated here —
    // verified: they arrive as .added although docs say .created.
    // Context is restored on the server; client only records it.
    GkLog('CONV_ITEM ' + EventType);
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

  else if EventType = 'conversation.item.input_audio_transcription.updated' then
    HandleTranscriptionUpdated(JObj)

  else if EventType = 'conversation.item.input_audio_transcription.completed' then
  begin
    // Grok also emits .completed for partial segments: the status field
    // distinguishes 'in_progress' (partial) from 'completed' (final).
    // Only final triggers OnTranscriptCompleted.
    Status := '';
    JObj.TryGetValue<string>('status', Status);
    if SameText(Status, 'in_progress') then
      HandleTranscriptionUpdated(JObj)
    else
    begin
      Transcript := '';
      ItemId     := '';
      JObj.TryGetValue<string>('transcript', Transcript);
      JObj.TryGetValue<string>('item_id', ItemId);
      // Reset accumulator for the closed item
      FLastItemId     := '';
      FLastTranscript := '';
      DoTranscriptCompleted(Transcript, ItemId);
    end;
  end

  else if EventType = 'response.created' then
  begin
    // FCarryAssistantText (pre-tools text) is preserved; FAssistantText
    // accumulates only the current response
    FAssistantText     := '';
    FHadToolCalls      := False;
    FToolsDone         := False;
    FPendingToolCalls  := 0;
    FContinuationSent  := 0;
  end

  else if EventType = 'response.function_call_arguments.done' then
    HandleFunctionCall(JObj)

  // Grok delivers spoken text in response.output_audio_transcript.*;
  // response.text.delta is also accepted for OpenAI compatibility
  else if (EventType = 'response.output_audio_transcript.delta') or
          (EventType = 'response.text.delta') then
  begin
    Delta := '';
    JObj.TryGetValue<string>('delta', Delta);
    if Delta <> '' then
    begin
      FAssistantText := FAssistantText + Delta;
      DoAssistantTextDelta(Delta);
    end;
  end

  else if EventType = 'response.output_audio_transcript.done' then
  begin
    // Carries the authoritative full transcript of the assistant turn
    Transcript := '';
    JObj.TryGetValue<string>('transcript', Transcript);
    if Transcript <> '' then
      FAssistantText := Transcript;
  end

  else if EventType = 'response.output_audio.delta' then
  begin
    AudioB64 := '';
    JObj.TryGetValue<string>('delta', AudioB64);
    if AudioB64 <> '' then
      DoAudioChunk(TNetEncoding.Base64.DecodeStringToBytes(AudioB64));
  end

  else if EventType = 'response.done' then
  begin
    if FHadToolCalls then
    begin
      // Intermediate turn of tool calls: the spoken response arrives in the
      // next response (after sending outputs + response.create).
      // Preserve already spoken text for final OnAssistantText.
      if FAssistantText <> '' then
        FCarryAssistantText := FCarryAssistantText + FAssistantText + ' ';
      FToolsDone := True;
      TryContinueAfterTools;
    end
    else
    begin
      // Final turn: emit full text (pre-tools + this response)
      if FCarryAssistantText + FAssistantText <> '' then
        DoAssistantText(FCarryAssistantText + FAssistantText);
      FAssistantText      := '';
      FCarryAssistantText := '';
      DoAudioDone;
    end;
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

{ WebSocket handlers }

procedure TAiGrokRealtimeChat.OnWSConnected(Sender: TObject);
begin
  GkLog('WS_CONNECTED');
  // session.update will be sent when session.created arrives
  DoConnected;
end;

procedure TAiGrokRealtimeChat.OnWSDisconnected(Sender: TObject);
begin
  GkLog('WS_DISCONNECTED');
  FSessionConfigured := False;
  DoDisconnected;
end;

procedure TAiGrokRealtimeChat.OnWSError(Sender: TObject; const ErrorMsg: string);
begin
  GkLog('WS_ERROR: ' + ErrorMsg);
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiGrokRealtimeChat.OnWSFrame(Sender: TObject;
  Opcode: TAiRealtimeWSOpcode; const Data: TBytes; IsFinal: Boolean);
var
  JsonStr: string;
  JObj:    TJSONObject;
begin
  // Output audio in binary mode: the frame IS the raw PCM from assistant
  if Opcode = rwsoBinary then
  begin
    GkLog('FRAME binary len=' + IntToStr(Length(Data)));
    if Length(Data) > 0 then
      DoAudioChunk(Data);
    Exit;
  end;
  GkLog('FRAME opcode=' + IntToStr(Ord(Opcode)) +
        ' len=' + IntToStr(Length(Data)) +
        ' data=' + Copy(TEncoding.UTF8.GetString(Data), 1, 2000));
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

{ Override of SendAudioChunk: enqueues resampling + sending to main thread.
  VoiceMonitor calls this method from the WaveIn callback (Windows audio system
  thread), where calling socket or SChannel functions is NOT allowed.
  TThread.Queue moves the operation to the main thread. }
procedure TAiGrokRealtimeChat.SendAudioChunk(const PCM16Data: TBytes);
var
  LData: TBytes;
begin
  if not IsConnected then Exit;
  if Length(PCM16Data) = 0 then Exit;
  LData := Copy(PCM16Data); // quick copy before leaving callback
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

{ Implemented abstract methods }

procedure TAiGrokRealtimeChat.InternalConnect;
var
  URL, Token: string;
begin
  if FEphemeralToken <> '' then
  begin
    // Client-side auth: ephemeral token travels as WebSocket subprotocol
    // and API key is NOT sent (may not even exist on client)
    Token := FEphemeralToken;
    if not Token.StartsWith('xai-client-secret.') then
      Token := 'xai-client-secret.' + Token;
    FWebSocket.ExtraHeaders.Values['Authorization']          := '';
    FWebSocket.ExtraHeaders.Values['Sec-WebSocket-Protocol'] := Token;
  end
  else
  begin
    // Server-side auth with API key. Do NOT send Sec-WebSocket-Protocol:
    // Grok reserves the subprotocol for ephemeral tokens
    FWebSocket.ExtraHeaders.Values['Authorization'] := 'Bearer ' + ResolvedApiKey;
    FWebSocket.ExtraHeaders.Values['Sec-WebSocket-Protocol'] := '';
  end;
  URL := BuildWssUrl;
  GkLog('CONNECT url=' + URL);
  FConnectThread := TThread.CreateAnonymousThread(procedure begin
    if not FWebSocket.Connect(URL) then
      DoError('Could not connect to xAI WebSocket server',
              'connection_failed');
  end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiGrokRealtimeChat.InternalDisconnect;
begin
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

procedure TAiGrokRealtimeChat.InternalSendAudio(const ResampledPCM16: TBytes);
var
  JObj: TJSONObject;
  B64:  string;
begin
  if Length(ResampledPCM16) = 0 then Exit;
  // Binary mode: raw PCM as binary frame, without JSON/base64 overhead
  if FBinaryAudio then
  begin
    FWebSocket.SendBinary(ResampledPCM16);
    Exit;
  end;
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

// Builds the tools array for session.update:
// native xAI tools (booleans) + local/MCP functions from AiFunctions
// in plain OpenAI Responses format (same as Grok uses).
// Returns nil if there are no tools to declare.
function TAiGrokRealtimeChat.BuildToolsArray: TJSONArray;
var
  JTool:    TJSONObject;
  ToolsStr: string;
  JParsed:  TJSONValue;
  I:        Integer;
begin
  Result := TJSONArray.Create;

  if FEnableWebSearch then
  begin
    JTool := TJSONObject.Create;
    JTool.AddPair('type', 'web_search');
    Result.Add(JTool);
  end;

  if FEnableXSearch then
  begin
    JTool := TJSONObject.Create;
    JTool.AddPair('type', 'x_search');
    Result.Add(JTool);
  end;

  // file_search over xAI collections (vector stores)
  if FFileSearchCollections.Count > 0 then
  begin
    JTool := TJSONObject.Create;
    JTool.AddPair('type', 'file_search');
    var JIds := TJSONArray.Create;
    for I := 0 to FFileSearchCollections.Count - 1 do
      if Trim(FFileSearchCollections[I]) <> '' then
        JIds.Add(Trim(FFileSearchCollections[I]));
    JTool.AddPair('vector_store_ids', JIds);
    if FFileSearchMaxResults > 0 then
      JTool.AddPair('max_num_results', TJSONNumber.Create(FFileSearchMaxResults));
    Result.Add(JTool);
  end;

  if Assigned(FAiFunctions) then
  begin
    ToolsStr := FAiFunctions.GetTools(tfOpenAIResponses);
    if ToolsStr <> '' then
    begin
      JParsed := TJSONObject.ParseJSONValue(ToolsStr);
      try
        if JParsed is TJSONArray then
          for I := 0 to TJSONArray(JParsed).Count - 1 do
            Result.Add(TJSONObject(TJSONArray(JParsed).Items[I].Clone));
      finally
        JParsed.Free;
      end;
    end;
  end;

  // Tools in raw JSON (remote MCP, new API shapes, etc.)
  if Trim(FCustomToolsJson.Text) <> '' then
  begin
    JParsed := TJSONObject.ParseJSONValue(FCustomToolsJson.Text);
    try
      if JParsed is TJSONArray then
      begin
        for I := 0 to TJSONArray(JParsed).Count - 1 do
          Result.Add(TJSONObject(TJSONArray(JParsed).Items[I].Clone))
      end
      else if JParsed is TJSONObject then
        Result.Add(TJSONObject(JParsed.Clone));
    finally
      JParsed.Free;
    end;
  end;

  if Result.Count = 0 then
    FreeAndNil(Result);
end;

// Executes a tool call requested by the model. Execution runs in its own
// thread so as not to block the WebSocket reader thread (user handlers may
// be slow). Sending response.create is coordinated with response.done via
// TryContinueAfterTools: xAI requires ALL outputs to be sent before
// response.create.
procedure TAiGrokRealtimeChat.HandleFunctionCall(const JObj: TJSONObject);
var
  FuncName, CallId, Args: string;
begin
  FuncName := '';
  CallId   := '';
  Args     := '';
  JObj.TryGetValue<string>('name', FuncName);
  JObj.TryGetValue<string>('call_id', CallId);
  JObj.TryGetValue<string>('arguments', Args);
  if FuncName = '' then Exit;

  GkLog('TOOL_CALL name=' + FuncName + ' call_id=' + CallId + ' args=' + Args);
  FHadToolCalls := True;
  TInterlocked.Increment(FPendingToolCalls);

  TThread.CreateAnonymousThread(
    procedure
    var
      ToolCall: TAiToolsFunction;
      Handled:  Boolean;
    begin
      ToolCall := TAiToolsFunction.Create;
      try
        ToolCall.id        := CallId;
        ToolCall.name      := FuncName;
        ToolCall.Arguments := Args;
        Handled := False;
        try
          if Assigned(FAiFunctions) then
            Handled := FAiFunctions.DoCallFunction(ToolCall);
          if (not Handled) and Assigned(FOnCallToolFunction) then
          begin
            // Fallback runs synchronized to the main thread (may touch UI)
            TThread.Synchronize(nil, procedure begin
              FOnCallToolFunction(Self, ToolCall);
            end);
            Handled := True;
          end;
          if not Handled then
            ToolCall.Response :=
              'Error: no handler for function ' + FuncName;
        except
          on E: Exception do
            ToolCall.Response := 'Error executing ' + FuncName + ': ' + E.Message;
        end;
        SendFunctionOutput(CallId, ToolCall.Response);
      finally
        ToolCall.Free;
        TInterlocked.Decrement(FPendingToolCalls);
        TryContinueAfterTools;
      end;
    end).Start;
end;

procedure TAiGrokRealtimeChat.SendFunctionOutput(const ACallId, AOutput: string);
var
  JMsg, JItem: TJSONObject;
begin
  JMsg := TJSONObject.Create;
  try
    JMsg.AddPair('type', 'conversation.item.create');
    JItem := TJSONObject.Create;
    JItem.AddPair('type', 'function_call_output');
    JItem.AddPair('call_id', ACallId);
    JItem.AddPair('output', AOutput);
    JMsg.AddPair('item', JItem);
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
end;

// Sends response.create continuation exactly once, only when
// (a) response.done of the tools turn already arrived and (b) no tool calls
// are still running. Can be triggered from reader thread (response.done) or
// from the last tool call thread — CompareExchange prevents duplicates.
procedure TAiGrokRealtimeChat.TryContinueAfterTools;
begin
  if not FToolsDone then Exit;
  if FPendingToolCalls > 0 then Exit;
  if TInterlocked.CompareExchange(FContinuationSent, 1, 0) <> 0 then Exit;
  GkLog('TOOLS_COMPLETE -> response.create');
  CreateResponse;
end;

procedure TAiGrokRealtimeChat.ForceMessage(const AText: string;
  AInterruptible: Boolean);
var
  JMsg, JItem, JContent: TJSONObject;
  JArr: TJSONArray;
begin
  if not IsConnected then Exit;
  JMsg := TJSONObject.Create;
  try
    JMsg.AddPair('type', 'conversation.item.create');
    JItem := TJSONObject.Create;
    JItem.AddPair('type', 'force_message');
    JItem.AddPair('role', 'assistant');
    if not AInterruptible then
      JItem.AddPair('interruptible', TJSONBool.Create(False));
    JContent := TJSONObject.Create;
    JContent.AddPair('type', 'output_text');
    JContent.AddPair('text', AText);
    JArr := TJSONArray.Create;
    JArr.Add(JContent);
    JItem.AddPair('content', JArr);
    JMsg.AddPair('item', JItem);
    FWebSocket.SendText(JMsg.ToJSON);
  finally
    JMsg.Free;
  end;
end;

procedure TAiGrokRealtimeChat.CreateResponse;
var
  JObj: TJSONObject;
begin
  if not IsConnected then Exit;
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('type', 'response.create');
    FWebSocket.SendText(JObj.ToJSON);
  finally
    JObj.Free;
  end;
end;

procedure TAiGrokRealtimeChat.InternalCommitAudio;
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

procedure TAiGrokRealtimeChat.InternalClearAudio;
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

initialization
  TAiRealtimeFactory.Instance.RegisterDriver(
    TAiGrokRealtimeChat.GetDriverName, TAiGrokRealtimeChat);

end.
