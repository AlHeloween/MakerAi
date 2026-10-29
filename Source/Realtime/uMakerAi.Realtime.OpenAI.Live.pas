// MakerAI Suite — Driver OpenAI GPT-Live (voice full-duplex)
// wss://api.openai.com/v1/live/sessions  (Authorization: Bearer)
//
// GPT-Live listens while speaking: user audio is sent in a continuous stream
// and the model decides when to speak (no VAD, commits or turns).
// Heavy reasoning is DELEGATED to another model:
//   - Delegation = ldResponses (default): OpenAI passes it to a model of the
//     API Responses (DelegationModel) with declared tools. Local functions
//     (AiFunctions / OnCallToolFunction) are executed here and the
//     result returns with response.item.create + response.create.
//   - Delegation = ldClient, or DelegateChat assigned: the application resolves
//     the task. With DelegateChat (TAiChatConnection: Claude, Ollama, an agent
//     graph...) the driver builds the request with the transcription, runs the
//     chat in a thread and returns the response with session.commentary.append.
//     Without DelegateChat it fires OnDelegation and the app responds with
//     AppendCommentary / AppendThinking.
//
// Protocol (types from official openai-python SDK, src/openai/types/live):
//   client:  session.start (first; wait for session.started),
//             session.input_audio.append, session.input_audio.mute/unmute,
//             session.commentary/thinking/instructions.append,
//             response.item.create, response.create, session.close
//   server:  session.started, session.input_transcript.delta,
//             session.output_transcript.delta, session.output_audio.delta,
//             session.delegation.created, response.event (nested Responses
//             event), session.usage.updated, session.closed, error, info
//
// Differences from gpt-realtime handled by the driver:
//   - Transcripts do not mark turns or have a "done" event, and in a
//     full-duplex conversation voices overlap (the model may start before
//     the user finishes). Deltas are emitted as they arrive; complete turns
//     (OnTranscriptCompleted / OnAssistantText) are assembled using the
//     timeline of each fragment (start_ms/end_ms) with the official SDK
//     aggregator policy:
//       * the turn changes only if the other starts 500 ms or more after the
//         end of the current turn; before that, speech is queued and the
//         current turn continues accumulating;
//       * a fragment that started before the current turn is a delayed
//         transcription of the previous turn (wait up to 1 s);
//       * the assistant's turn closes after 2 s without new text OR voice
//         in the output audio (transcripts arrive in bursts: a 1 s pause
//         between phrases could be seen as 2 s and split a long story);
//         if the model continues speaking, the turn resumes instead of opening a new one.
//     Short "mhm"/"uh-huh" are NOT discarded (the SDK does): a brief acknowledgment counts as a turn.
//   - Output audio is a continuous stream (includes silence), without time
//     stamps or end event: OnAudioDone fires only on session.closed.
//   - Voice, audio format and instructions do not change after startup.
//   - The model is in session.start, not in the URL.
// Audio: PCM16 mono at 24 kHz (default) or 16 kHz (AudioRate). G.711 (8 kHz)
// is not supported by the driver.
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.Realtime.OpenAI.Live;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.SyncObjs, System.Generics.Collections, System.Diagnostics, System.Math,
  uMakerAi.Core, uMakerAi.Chat.Messages, uMakerAi.Tools.Functions,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Realtime, uMakerAi.Realtime.WebSocket, uMakerAi.WebSocket.Client;

type
  // Input and output PCM16 audio frequency
  TAiLiveAudioRate = (lar24k, lar16k);

  // Who resolves the tasks delegated by the voice model
  TAiLiveDelegation = (
    ldResponses, // a model from the OpenAI Responses API managed by OpenAI
    ldClient     // the application (DelegateChat or OnDelegation)
  );

  // Reasoning effort of the delegated model (lreDefault = not sent)
  TAiLiveReasoningEffort = (lreDefault, lreNone, lreMinimal, lreLow,
    lreMedium, lreHigh, lreXHigh);

  // Fallback for function calling when AiFunctions does not handle the function.
  // The handler must assign ToolCall.Response with the result.
  TAiLiveToolCallEvent = procedure(Sender: TObject;
    ToolCall: TAiToolsFunction) of object;

  // Delegation to the application. Context is the transcription since the last
  // delegation (the server event does not carry the task text).
  // Respond with AppendCommentary(Text, DelegationId).
  TAiLiveDelegationEvent = procedure(Sender: TObject;
    const DelegationId, Context: string) of object;

  // Accumulated usage: audio seconds of the session and context ratio
  // (0..1; -1 if the server does not report it)
  TAiLiveUsageEvent = procedure(Sender: TObject;
    Seconds, ContextRatio: Double) of object;

  // End of session: close_requested, expired, content, remote_hangup or
  // connection_lost
  TAiLiveClosedEvent = procedure(Sender: TObject; const Reason: string;
    Seconds: Double) of object;

  // Raw event from the delegated model (Responses), for UI or diagnostics
  TAiLiveResponseEvent = procedure(Sender: TObject;
    const DelegationId, EventType, EventJson: string) of object;

  // Conversation turn assembled from transcription fragments
  TAiLiveTurn = record
    Speaker:  Integer; // 0 empty, 1 user, 2 assistant
    Text:     string;
    SentText: string;  // text already sent in a delegation
    StartMs:  Int64;   // session timeline
    EndMs:    Int64;
    Wall:     Int64;   // local clock of last fragment (NowMs)
  end;

  // State of function calls for a delegated response
  TAiLiveToolTurn = record
    Pending:   Integer; // functions being executed
    HadCalls:  Boolean; // the response requested functions
    Completed: Boolean; // response.completed received
  end;

  TAiOpenAiLiveChat = class(TAiRealtimeVoiceBase)
  private
    FWebSocket:      TAiRealtimeWSClient;
    FConnectThread:  TThread;
    FB64:            TBase64Encoding; // no line breaks
    FSessionStarted: Boolean;
    FClosedEvent:    TEvent;          // session.closed received
    // Configuration
    FVoice:             string;
    FInstructions:      string;
    FAudioRate:         TAiLiveAudioRate;
    FDelegation:        TAiLiveDelegation;
    FDelegationModel:   string;
    FDelegationInstructions: string;
    FReasoningEffort:   TAiLiveReasoningEffort;
    FMaxOutputTokens:   Integer;
    FParallelToolCalls: Boolean;
    FToolChoice:        string;
    FEnableWebSearch:   Boolean;
    FStore:             Boolean;
    FCloseTimeoutMs:    Integer;
    FCustomToolsJson:   TStrings;
    FAiFunctions:       TAiFunctions;      // external reference
    FDelegateChat:      TAiChatConnection; // external reference
    // Own events
    FOnCallToolFunction: TAiLiveToolCallEvent;
    FOnDelegation:       TAiLiveDelegationEvent;
    FOnUsage:            TAiLiveUsageEvent;
    FOnSessionClosed:    TAiLiveClosedEvent;
    FOnResponseEvent:    TAiLiveResponseEvent;
    // Session state
    FSessionId:    string;
    FUsageSeconds: Double;
    FCloseReason:  string;
    FEventSeq:     Integer;
    // Conversation turns (main thread: TAiWSClient delivers each
    // frame via TThread.Queue, so ProcessServerEvent runs there):
    //   FPrev: previous turn, waiting for delayed fragments before closing
    //   FCur:  current turn
    //   FBuf:  speech of the other overlapped with the current turn (queued)
    FClock:          TStopwatch;
    FPrev, FCur, FBuf: TAiLiveTurn;
    FTimelineMax:    Int64;       // end of last fragment (session ms)
    FVoiceWall:      Int64;       // last output audio with voice (NowMs)
    FTranscript:     TStringList; // closed turns 'User: ...' / 'Assistant: ...'
    FDelegatedLines: Integer;     // first line not yet checked by DelegationContext
    // Worker threads (functions and DelegateChat)
    FToolLock:      TCriticalSection;
    FToolTurns:     TDictionary<string, TAiLiveToolTurn>; // keyed by delegation_id
    FDelegateLock:  TCriticalSection; // DelegateChat handles one task at a time
    FActiveWorkers: Integer;
    FShuttingDown:  Boolean;
    procedure OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
      const Data: TBytes; IsFinal: Boolean);
    procedure OnWSConnected(Sender: TObject);
    procedure OnWSDisconnected(Sender: TObject);
    procedure OnWSError(Sender: TObject; const ErrorMsg: string);
    procedure SetAiFunctions(const Value: TAiFunctions);
    procedure SetDelegateChat(const Value: TAiChatConnection);
    procedure SetCustomToolsJson(const Value: TStrings);
    function  NextEventId: string;
    function  BuildToolsArray: TJSONArray;
    function  BuildDelegation: TJSONObject;
    // Transcription segments -> turns
    procedure HandleFragment(ASpeaker: Integer; const ADelta: string;
      AStartMs, AEndMs: Int64);
    procedure AppendToTurn(var ATurn: TAiLiveTurn; ASpeaker: Integer;
      const ADelta: string; AStartMs, AEndMs: Int64);
    procedure FinishTurn(var ATurn: TAiLiveTurn);
    procedure PromoteBuffered;
    procedure AdvanceTimeline(ATimeMs: Int64);
    procedure CheckSegmentTimers;
    procedure FinishAllTurns;
    function  DelegationContext: string;
    // Delegation
    procedure HandleDelegationCreated(const JObj: TJSONObject);
    procedure RunDelegateChat(const ADelegationId, AContext: string);
    procedure HandleResponseEvent(const JObj: TJSONObject);
    procedure HandleFunctionCall(const AKey: string; const AItem: TJSONObject);
    procedure TryContinueAfterTools(const AKey: string);
    procedure SendFunctionOutput(const ACallId, AOutput: string);
    procedure SendAppend(const AType, AContent, ADelegationId: string);
    procedure StartWorker(AProc: TProc);
    // Dispatchers for own events (TThread.Queue to main thread)
    procedure DoDelegation(const ADelegationId, AContext: string);
    procedure DoUsage(ASeconds, ARatio: Double);
    procedure DoSessionClosed(const AReason: string; ASeconds: Double);
    procedure DoResponseEvent(const ADelegationId, AType, AJson: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function  GetTargetSampleRate: Integer; override;
    procedure InternalSendAudio(const ResampledPCM16: TBytes); override;
    procedure InternalConnect;    override;
    procedure InternalDisconnect; override;
    // Continuous stream: the model decides when to speak, no turns to close
    procedure InternalCommitAudio; override;
    procedure InternalClearAudio;  override;
    // Processes a JSON event from the server (protected: the suite feeds it without network)
    procedure ProcessServerEvent(const JObj: TJSONObject); virtual;
    // Local clock in ms to close turns on inactivity (virtual: the suite
    // controls it)
    function  NowMs: Int64; virtual;
    // Complete session.start message (protected: the suite inspects it)
    function  BuildSessionStart: TJSONObject;
    // Sends a message and frees it (virtual: the suite captures what was sent)
    procedure SendJson(AObj: TJSONObject); virtual;
    // Effective delegation: DelegateChat assigned forces ldClient
    function  EffectiveDelegation: TAiLiveDelegation;
    // Splits a text into fragments of at most AMaxBytes UTF-8 (injections
    // accept 500 tokens); breaks at spaces when possible
    class function SplitForAppend(const AText: string;
      AMaxBytes: Integer = 400): TArray<string>;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    // WaveIn callback cannot touch sockets: sending is queued to main thread
    procedure SendAudioChunk(const PCM16Data: TBytes); override;
    // Stop passing microphone audio to the model (and resume)
    procedure Mute;
    procedure Unmute;
    // Text the model can say to the user (result of a task).
    // ADelegationId: the one from OnDelegation, or '' for general context. With
    // ldResponses only '' is accepted. Long texts are split into several sends.
    procedure AppendCommentary(const AText: string; const ADelegationId: string = '');
    // Silent context or progress (does not ask the model to speak)
    procedure AppendThinking(const AText: string; const ADelegationId: string = '');
    // New instructions during the conversation (e.g. change topic)
    procedure AppendInstructions(const AText: string; const ADelegationId: string = '');
    class function GetDriverName:   string; override;
    class function GetDefaultModel: string; override;
    // Session id assigned by the server (session.started)
    property SessionId: string read FSessionId;
    // Accumulated audio seconds (session.usage.updated / session.closed)
    property UsageSeconds: Double read FUsageSeconds;
    // Reason of the last session closure
    property CloseReason: string read FCloseReason;
  published
    // Model voice: marin (default), cedar, alloy, coral,
    // sage, verse... or a custom voice id. Does not change after connect.
    property Voice: string read FVoice write FVoice;
    // Conversation instructions (tone, interruptions, when to delegate).
    // Business rules go in DelegationInstructions.
    property Instructions: string read FInstructions write FInstructions;
    property AudioRate: TAiLiveAudioRate read FAudioRate write FAudioRate default lar24k;
    property Delegation: TAiLiveDelegation read FDelegation write FDelegation default ldResponses;
    // Model of the Responses API that resolves tasks (ldResponses)
    property DelegationModel: string read FDelegationModel write FDelegationModel;
    // Prompt for the delegated model (ldResponses), separate from Instructions
    property DelegationInstructions: string read FDelegationInstructions
      write FDelegationInstructions;
    property ReasoningEffort: TAiLiveReasoningEffort read FReasoningEffort
      write FReasoningEffort default lreDefault;
    // Maximum tokens per delegated response (0 = not sent)
    property MaxOutputTokens: Integer read FMaxOutputTokens write FMaxOutputTokens default 0;
    property ParallelToolCalls: Boolean read FParallelToolCalls
      write FParallelToolCalls default True;
    // '' (not sent), 'auto', 'none', 'required' or a function name
    property ToolChoice: string read FToolChoice write FToolChoice;
    // Web search of the delegated model (performed by OpenAI)
    property EnableWebSearch: Boolean read FEnableWebSearch write FEnableWebSearch default False;
    // Save the session in OpenAI (for forks and recording download)
    property Store: Boolean read FStore write FStore default False;
    // Maximum wait for session.closed when disconnecting (documentation
    // suggests up to 15 s; 0 = no wait)
    property CloseTimeoutMs: Integer read FCloseTimeoutMs write FCloseTimeoutMs default 5000;
    // Local functions and MCP of the delegated model (ldResponses)
    property AiFunctions: TAiFunctions read FAiFunctions write SetAiFunctions;
    // Extra tools in raw JSON (object or array of 'function' tools)
    property CustomToolsJson: TStrings read FCustomToolsJson write SetCustomToolsJson;
    // Chat that resolves delegated tasks (any provider). When assigned,
    // the session uses ldClient. Asynchronous=False is forced on connect.
    property DelegateChat: TAiChatConnection read FDelegateChat write SetDelegateChat;
    property OnCallToolFunction: TAiLiveToolCallEvent read FOnCallToolFunction
      write FOnCallToolFunction;
    property OnDelegation: TAiLiveDelegationEvent read FOnDelegation write FOnDelegation;
    property OnUsage: TAiLiveUsageEvent read FOnUsage write FOnUsage;
    property OnSessionClosed: TAiLiveClosedEvent read FOnSessionClosed write FOnSessionClosed;
    property OnResponseEvent: TAiLiveResponseEvent read FOnResponseEvent
      write FOnResponseEvent;
  end;

procedure Register;

implementation

const
  CLIVE_WSS = 'wss://api.openai.com/v1/live/sessions';
  CLIVE_DEFAULT_DELEGATION_MODEL = 'gpt-6-luna';
  CSPEAKER_USER      = 1;
  CSPEAKER_ASSISTANT = 2;
  // Minimum separation to change turn (min_turn_separation_ms from SDK)
  CMIN_TURN_SEPARATION_MS = 500;
  // Assistant silence that closes its turn (assistant_silence_ms from SDK)
  CASSISTANT_SILENCE_MS = 2000;
  // Local clock: wait for delayed fragments of the previous turn, and for a
  // current turn that stopped receiving text while the other speaks
  CLATE_FRAGMENT_MS = 1000;
  // Absolute PCM16 average level above which output audio has voice
  // (the server sends digital silence between phrases)
  COUTPUT_VOICE_LEVEL = 500;
  // Request that DelegateChat receives: transcription is automatic and the
  // response will be spoken aloud
  CDELEGATE_PROMPT =
    'Voice conversation so far (automatic transcription, may contain errors):' +
    sLineBreak + '%s' + sLineBreak + sLineBreak +
    'The voice assistant delegated the user''s current request to you. ' +
    'Resolve it and reply with the result only, in the user''s language, as ' +
    'plain text that will be read aloud (no markdown, no lists).';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiOpenAiLiveChat]);
end;

{ TAiOpenAiLiveChat }

constructor TAiOpenAiLiveChat.Create(AOwner: TComponent);
begin
  inherited;
  ApiKey := '@OPENAI_API_KEY';
  Model := GetDefaultModel;
  FAudioRate := lar24k;
  FDelegation := ldResponses;
  FDelegationModel := CLIVE_DEFAULT_DELEGATION_MODEL;
  FReasoningEffort := lreDefault;
  FParallelToolCalls := True;
  FCloseTimeoutMs := 5000;
  FCustomToolsJson := TStringList.Create;
  FTranscript := TStringList.Create;
  FToolLock := TCriticalSection.Create;
  FDelegateLock := TCriticalSection.Create;
  FToolTurns := TDictionary<string, TAiLiveToolTurn>.Create;
  FClosedEvent := TEvent.Create(nil, True, False, '');
  FB64 := TBase64Encoding.Create(0);
  FClock := TStopwatch.StartNew;
  FWebSocket := TAiRealtimeWSClient.Create;
  FWebSocket.OnFrame        := OnWSFrame;
  FWebSocket.OnConnected    := OnWSConnected;
  FWebSocket.OnDisconnected := OnWSDisconnected;
  FWebSocket.OnError        := OnWSError;
end;

destructor TAiOpenAiLiveChat.Destroy;
var
  Waited: Integer;
begin
  FShuttingDown := True;
  if IsConnected then InternalDisconnect;
  if Assigned(FConnectThread) then
  begin
    FWebSocket.Disconnect;
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  // Function and DelegateChat threads use Self: wait for them (up to
  // 30 s). From the main thread the queue is drained in case they synchronize.
  Waited := 0;
  while (TInterlocked.CompareExchange(FActiveWorkers, 0, 0) > 0) and (Waited < 30000) do
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      CheckSynchronize(10)
    else
      Sleep(10);
    Inc(Waited, 10);
  end;
  FWebSocket.Free;
  FB64.Free;
  FClosedEvent.Free;
  FToolTurns.Free;
  FDelegateLock.Free;
  FToolLock.Free;
  FTranscript.Free;
  FCustomToolsJson.Free;
  inherited;
end;

procedure TAiOpenAiLiveChat.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FAiFunctions then
      FAiFunctions := nil;
    if AComponent = FDelegateChat then
      FDelegateChat := nil;
  end;
end;

procedure TAiOpenAiLiveChat.SetAiFunctions(const Value: TAiFunctions);
begin
  if FAiFunctions = Value then Exit;
  if Assigned(FAiFunctions) then
    FAiFunctions.RemoveFreeNotification(Self);
  FAiFunctions := Value;
  if Assigned(FAiFunctions) then
    FAiFunctions.FreeNotification(Self);
end;

procedure TAiOpenAiLiveChat.SetDelegateChat(const Value: TAiChatConnection);
begin
  if FDelegateChat = Value then Exit;
  if Assigned(FDelegateChat) then
    FDelegateChat.RemoveFreeNotification(Self);
  FDelegateChat := Value;
  if Assigned(FDelegateChat) then
    FDelegateChat.FreeNotification(Self);
end;

procedure TAiOpenAiLiveChat.SetCustomToolsJson(const Value: TStrings);
begin
  FCustomToolsJson.Assign(Value);
end;

class function TAiOpenAiLiveChat.GetDriverName: string;
begin
  Result := 'OpenAiLive';
end;

class function TAiOpenAiLiveChat.GetDefaultModel: string;
begin
  Result := 'gpt-live-1';
end;

function TAiOpenAiLiveChat.GetTargetSampleRate: Integer;
begin
  if FAudioRate = lar16k then
    Result := 16000
  else
    Result := 24000;
end;

function TAiOpenAiLiveChat.EffectiveDelegation: TAiLiveDelegation;
begin
  if Assigned(FDelegateChat) then
    Result := ldClient
  else
    Result := FDelegation;
end;

function TAiOpenAiLiveChat.NextEventId: string;
begin
  Result := 'mkai_' + IntToStr(TInterlocked.Increment(FEventSeq));
end;

procedure TAiOpenAiLiveChat.SendJson(AObj: TJSONObject);
begin
  try
    FWebSocket.SendText(AObj.ToJSON);
  finally
    AObj.Free;
  end;
end;

// -----------------------------------------------------------------------------
// session.start
// -----------------------------------------------------------------------------

function TAiOpenAiLiveChat.BuildToolsArray: TJSONArray;
var
  JTool: TJSONObject;
  JParsed: TJSONValue;
  ToolsStr: string;
  I: Integer;
begin
  Result := TJSONArray.Create;

  if FEnableWebSearch then
  begin
    JTool := TJSONObject.Create;
    JTool.AddPair('type', 'web_search');
    Result.Add(JTool);
  end;

  // Flat format of the Responses API: {type:function, name, description, parameters}
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

  if Trim(FCustomToolsJson.Text) <> '' then
  begin
    JParsed := TJSONObject.ParseJSONValue(FCustomToolsJson.Text);
    try
      if JParsed is TJSONArray then
      begin
        for I := 0 to TJSONArray(JParsed).Count - 1 do
          Result.Add(TJSONObject(TJSONArray(JParsed).Items[I].Clone));
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

function TAiOpenAiLiveChat.BuildDelegation: TJSONObject;
const
  CEfforts: array[TAiLiveReasoningEffort] of string =
    ('', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh');
var
  JResp, JReasoning, JChoice: TJSONObject;
  JTools: TJSONArray;
  LModel, LChoice: string;
begin
  Result := TJSONObject.Create;
  if EffectiveDelegation = ldClient then
  begin
    Result.AddPair('type', 'client');
    Exit;
  end;

  Result.AddPair('type', 'responses');
  JResp := TJSONObject.Create;
  LModel := Trim(FDelegationModel);
  if LModel = '' then
    LModel := CLIVE_DEFAULT_DELEGATION_MODEL;
  JResp.AddPair('model', LModel);
  if Trim(FDelegationInstructions) <> '' then
    JResp.AddPair('instructions', FDelegationInstructions);
  if FMaxOutputTokens > 0 then
    JResp.AddPair('max_output_tokens', TJSONNumber.Create(FMaxOutputTokens));
  if not FParallelToolCalls then
    JResp.AddPair('parallel_tool_calls', TJSONFalse.Create);
  if FReasoningEffort <> lreDefault then
  begin
    JReasoning := TJSONObject.Create;
    JReasoning.AddPair('effort', CEfforts[FReasoningEffort]);
    JResp.AddPair('reasoning', JReasoning);
  end;

  JTools := BuildToolsArray;
  if Assigned(JTools) then
    JResp.AddPair('tools', JTools);

  LChoice := Trim(FToolChoice);
  if LChoice <> '' then
  begin
    if SameText(LChoice, 'auto') or SameText(LChoice, 'none') or SameText(LChoice, 'required') then
      JResp.AddPair('tool_choice', LowerCase(LChoice))
    else
    begin
      JChoice := TJSONObject.Create;
      JChoice.AddPair('type', 'function');
      JChoice.AddPair('name', LChoice);
      JResp.AddPair('tool_choice', JChoice);
    end;
  end;

  Result.AddPair('responses', JResp);
end;

function TAiOpenAiLiveChat.BuildSessionStart: TJSONObject;
var
  JSession, JAudio, JFormat, JOutput: TJSONObject;
  LModel: string;
begin
  LModel := Model;
  if LModel = '' then
    LModel := GetDefaultModel;

  JSession := TJSONObject.Create;
  JSession.AddPair('model', LModel);
  if Trim(FInstructions) <> '' then
    JSession.AddPair('instructions', FInstructions);

  JAudio := TJSONObject.Create;
  JFormat := TJSONObject.Create;
  JFormat.AddPair('type', 'audio/pcm');
  JFormat.AddPair('rate', TJSONNumber.Create(GetTargetSampleRate));
  JAudio.AddPair('format', JFormat);
  if Trim(FVoice) <> '' then
  begin
    JOutput := TJSONObject.Create;
    JOutput.AddPair('voice', Trim(FVoice));
    JAudio.AddPair('output', JOutput);
  end;
  JSession.AddPair('audio', JAudio);

  JSession.AddPair('delegation', BuildDelegation);
  if FStore then
    JSession.AddPair('store', TJSONTrue.Create);

  Result := TJSONObject.Create;
  Result.AddPair('type', 'session.start');
  Result.AddPair('event_id', NextEventId);
  Result.AddPair('session', JSession);
end;

// -----------------------------------------------------------------------------
// Server events
// -----------------------------------------------------------------------------

// Average of absolute PCM16 sample values
function AudioLevel(const AData: TBytes): Integer;
var
  I, N: Integer;
  Sum: Int64;
begin
  N := Length(AData) div 2;
  if N = 0 then
    Exit(0);
  Sum := 0;
  for I := 0 to N - 1 do
    Inc(Sum, Abs(PSmallInt(@AData[I * 2])^));
  Result := Sum div N;
end;

function TAiOpenAiLiveChat.NowMs: Int64;
begin
  Result := FClock.ElapsedMilliseconds;
end;

procedure TAiOpenAiLiveChat.ProcessServerEvent(const JObj: TJSONObject);
var
  EventType, S, Code: string;
  JSession, JUsage, JCtx, JError: TJSONObject;
  Seconds, Ratio: Double;
  StartMs, EndMs: Int64;
  Audio: TBytes;
begin
  if not JObj.TryGetValue<string>('type', EventType) then Exit;
  // Output audio arrives every ~100 ms: serves as a clock to close turns
  CheckSegmentTimers;

  if EventType = 'session.started' then
  begin
    if JObj.TryGetValue<TJSONObject>('session', JSession) then
      JSession.TryGetValue<string>('id', FSessionId);
    FSessionStarted := True;
    DoSessionReady;
  end

  else if (EventType = 'session.input_transcript.delta') or
          (EventType = 'session.output_transcript.delta') then
  begin
    S := '';
    JObj.TryGetValue<string>('delta', S);
    // Without timestamps (-1) the fragment is placed after the last. TryGetValue
    // leaves value at 0 if field is missing: need to check the result
    if not JObj.TryGetValue<Int64>('start_ms', StartMs) then
      StartMs := -1;
    if not JObj.TryGetValue<Int64>('end_ms', EndMs) then
      EndMs := -1;
    if S <> '' then
    begin
      if EventType = 'session.input_transcript.delta' then
        HandleFragment(CSPEAKER_USER, S, StartMs, EndMs)
      else
        HandleFragment(CSPEAKER_ASSISTANT, S, StartMs, EndMs);
    end;
  end

  else if EventType = 'session.output_audio.delta' then
  begin
    S := '';
    JObj.TryGetValue<string>('delta', S);
    if S <> '' then
    begin
      Audio := TNetEncoding.Base64.DecodeStringToBytes(S);
      // Audio arrives at real-time rate (transcripts in bursts): while
      // it has voice, the assistant continues speaking
      if AudioLevel(Audio) > COUTPUT_VOICE_LEVEL then
        FVoiceWall := NowMs;
      DoAudioChunk(Audio);
    end;
  end

  else if EventType = 'session.delegation.created' then
    HandleDelegationCreated(JObj)

  else if EventType = 'response.event' then
    HandleResponseEvent(JObj)

  else if EventType = 'session.usage.updated' then
  begin
    Seconds := FUsageSeconds;
    Ratio := -1;
    if JObj.TryGetValue<TJSONObject>('usage', JUsage) then
      JUsage.TryGetValue<Double>('seconds', Seconds);
    if JObj.TryGetValue<TJSONObject>('context_window', JCtx) then
      JCtx.TryGetValue<Double>('usage_ratio', Ratio);
    FUsageSeconds := Seconds;
    DoUsage(Seconds, Ratio);
  end

  else if EventType = 'session.closed' then
  begin
    FCloseReason := '';
    JObj.TryGetValue<string>('reason', FCloseReason);
    if JObj.TryGetValue<TJSONObject>('usage', JUsage) then
      JUsage.TryGetValue<Double>('seconds', FUsageSeconds);
    // Transcripts have no end event: close whatever is still open
    FinishAllTurns;
    FSessionStarted := False;
    DoAudioDone;
    DoSessionClosed(FCloseReason, FUsageSeconds);
    FClosedEvent.SetEvent;
  end

  else if EventType = 'error' then
  begin
    S := 'Unknown error';
    Code := '';
    if JObj.TryGetValue<TJSONObject>('error', JError) then
    begin
      JError.TryGetValue<string>('message', S);
      JError.TryGetValue<string>('code', Code);
    end;
    DoError(S, Code);
  end;
  // session.updated, info and acknowledgements (*.appended, input_audio.muted/unmuted)
  // require no action
end;

procedure TAiOpenAiLiveChat.AppendToTurn(var ATurn: TAiLiveTurn; ASpeaker: Integer;
  const ADelta: string; AStartMs, AEndMs: Int64);
begin
  if ATurn.Speaker = 0 then
  begin
    ATurn.Speaker := ASpeaker;
    ATurn.StartMs := AStartMs;
    ATurn.EndMs := AEndMs;
  end;
  ATurn.Text := ATurn.Text + ADelta;
  if AEndMs > ATurn.EndMs then
    ATurn.EndMs := AEndMs;
  ATurn.Wall := NowMs;
end;

procedure TAiOpenAiLiveChat.FinishTurn(var ATurn: TAiLiveTurn);
var
  T: string;
  Idx: Integer;
begin
  T := Trim(ATurn.Text);
  if (ATurn.Speaker <> 0) and (T <> '') then
  begin
    if ATurn.Speaker = CSPEAKER_USER then
      Idx := FTranscript.Add('User: ' + T)
    else
      Idx := FTranscript.Add('Assistant: ' + T);
    // Already sent completely in a delegation: do not repeat in the next one
    if ATurn.SentText = ATurn.Text then
      FTranscript.Objects[Idx] := TObject(1);
    if ATurn.Speaker = CSPEAKER_USER then
      DoTranscriptCompleted(T, '')
    else
      DoAssistantText(T);
  end;
  ATurn := Default(TAiLiveTurn);
end;

procedure TAiOpenAiLiveChat.PromoteBuffered;
begin
  // Current turn ended: goes to wait for delayed fragments and the buffered
  // speech becomes the current turn
  FinishTurn(FPrev);
  FPrev := FCur;
  FCur := FBuf;
  FBuf := Default(TAiLiveTurn);
end;

procedure TAiOpenAiLiveChat.AdvanceTimeline(ATimeMs: Int64);
begin
  if FCur.Speaker = 0 then Exit;
  if (FBuf.Speaker <> 0) and (ATimeMs >= FCur.EndMs + CMIN_TURN_SEPARATION_MS) then
    PromoteBuffered
  else if (FCur.Speaker = CSPEAKER_ASSISTANT) and (FBuf.Speaker = 0) and
          (ATimeMs >= FCur.EndMs + CASSISTANT_SILENCE_MS) then
  begin
    FinishTurn(FPrev);
    FinishTurn(FCur);
  end;
end;

procedure TAiOpenAiLiveChat.HandleFragment(ASpeaker: Integer; const ADelta: string;
  AStartMs, AEndMs: Int64);
begin
  // Without timestamps: after everything previous (turn change on arrival)
  if AStartMs < 0 then
    AStartMs := FTimelineMax + CMIN_TURN_SEPARATION_MS;
  if AEndMs < AStartMs then
    AEndMs := AStartMs;
  if AEndMs > FTimelineMax then
    FTimelineMax := AEndMs;

  // Deltas are emitted on arrival; only turn closure waits
  if ASpeaker = CSPEAKER_USER then
    DoTranscriptDelta(ADelta)
  else
    DoAssistantTextDelta(ADelta);

  AdvanceTimeline(AStartMs);

  // Turn was closed by inactivity but the same speaker continues without a
  // real pause (according to timeline): resume it instead of opening a new one
  if (FCur.Speaker = 0) and (FPrev.Speaker = ASpeaker) and
     (AStartMs < FPrev.EndMs + CASSISTANT_SILENCE_MS) then
  begin
    FCur := FPrev;
    FPrev := Default(TAiLiveTurn);
  end;

  // Delayed transcription of the previous turn
  if (FPrev.Speaker = ASpeaker) and (FCur.Speaker <> 0) and (AStartMs < FCur.StartMs) then
    AppendToTurn(FPrev, ASpeaker, ADelta, AStartMs, AEndMs)
  else if (FCur.Speaker = 0) or (FCur.Speaker = ASpeaker) then
    AppendToTurn(FCur, ASpeaker, ADelta, AStartMs, AEndMs)
  else if FBuf.Speaker <> 0 then
  begin
    AppendToTurn(FBuf, ASpeaker, ADelta, AStartMs, AEndMs);
    if AStartMs >= FCur.EndMs + CMIN_TURN_SEPARATION_MS then
      PromoteBuffered;
  end
  else if AStartMs >= FCur.EndMs + CMIN_TURN_SEPARATION_MS then
  begin
    // Turn change: the current one waits for delayed fragments
    FinishTurn(FPrev);
    FPrev := FCur;
    FCur := Default(TAiLiveTurn);
    AppendToTurn(FCur, ASpeaker, ADelta, AStartMs, AEndMs);
  end
  else
    // Overlapped speech: stays queued until the current turn ends
    AppendToTurn(FBuf, ASpeaker, ADelta, AStartMs, AEndMs);
end;

procedure TAiOpenAiLiveChat.CheckSegmentTimers;
var
  T: Int64;
begin
  if (FPrev.Speaker = 0) and (FCur.Speaker = 0) then Exit;
  T := NowMs;
  if (FPrev.Speaker <> 0) and (T - FPrev.Wall >= CLATE_FRAGMENT_MS) then
    FinishTurn(FPrev);
  if (FBuf.Speaker <> 0) and (T - FCur.Wall >= CLATE_FRAGMENT_MS) then
    PromoteBuffered
  else if (FCur.Speaker = CSPEAKER_ASSISTANT) and (FBuf.Speaker = 0) and
          (T - Max(FCur.Wall, FVoiceWall) >= CASSISTANT_SILENCE_MS) then
  begin
    // No text or voice: the turn moves to wait for delayed fragments (or for
    // the model to continue) and closes if none arrive
    FinishTurn(FPrev);
    FPrev := FCur;
    FPrev.Wall := T;
    FCur := Default(TAiLiveTurn);
  end;
end;

procedure TAiOpenAiLiveChat.FinishAllTurns;
begin
  FinishTurn(FPrev);
  FinishTurn(FCur);
  FinishTurn(FBuf);
end;

function TAiOpenAiLiveChat.DelegationContext: string;
var
  I: Integer;
  SB: TStringBuilder;

  procedure AddOpen(var ATurn: TAiLiveTurn);
  begin
    if (ATurn.Speaker = 0) or (Trim(ATurn.Text) = '') or (ATurn.SentText = ATurn.Text) then
      Exit;
    if ATurn.Speaker = CSPEAKER_USER then
      SB.AppendLine('User: ' + Trim(ATurn.Text))
    else
      SB.AppendLine('Assistant: ' + Trim(ATurn.Text));
    ATurn.SentText := ATurn.Text;
  end;

begin
  // What DelegateChat has not yet seen (it keeps its own history): closed
  // and open turns, in timeline order
  SB := TStringBuilder.Create;
  try
    for I := FDelegatedLines to FTranscript.Count - 1 do
      if FTranscript.Objects[I] = nil then
        SB.AppendLine(FTranscript[I]);
    FDelegatedLines := FTranscript.Count;
    AddOpen(FPrev);
    AddOpen(FCur);
    AddOpen(FBuf);
    Result := SB.ToString.TrimRight;
  finally
    SB.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Delegation to the application (ldClient)
// -----------------------------------------------------------------------------

procedure TAiOpenAiLiveChat.HandleDelegationCreated(const JObj: TJSONObject);
var
  JDeleg: TJSONObject;
  Id, Target, Context: string;
begin
  if not JObj.TryGetValue<TJSONObject>('delegation', JDeleg) then Exit;
  Id := '';
  Target := '';
  JDeleg.TryGetValue<string>('id', Id);
  JDeleg.TryGetValue<string>('target', Target);
  // Delegations to Responses are resolved by OpenAI (see HandleResponseEvent)
  if (Id = '') or (Target <> 'client') then Exit;

  Context := DelegationContext;
  DoDelegation(Id, Context);

  if Assigned(FDelegateChat) then
    RunDelegateChat(Id, Context)
  else if not Assigned(FOnDelegation) then
  begin
    // Nobody will answer: notify the model so it does not wait in silence
    DoError('Delegation without DelegateChat or OnDelegation', 'delegation_unhandled');
    AppendCommentary('This task cannot be completed: no handler is configured.', Id);
  end;
end;

procedure TAiOpenAiLiveChat.RunDelegateChat(const ADelegationId, AContext: string);
begin
  StartWorker(
    procedure
    var
      Answer: string;
    begin
      FDelegateLock.Enter;
      try
        try
          Answer := FDelegateChat.AddMessageAndRun(
            Format(CDELEGATE_PROMPT, [AContext]), 'user', []);
          if Trim(Answer) = '' then
          begin
            Answer := 'The task produced no answer.';
            if FDelegateChat.LastError <> '' then
              DoError('DelegateChat: ' + FDelegateChat.LastError, 'delegate_chat_error');
          end;
        except
          on E: Exception do
          begin
            DoError('DelegateChat: ' + E.Message, 'delegate_chat_error');
            Answer := 'The task failed: ' + E.Message;
          end;
        end;
      finally
        FDelegateLock.Leave;
      end;
      if not FShuttingDown then
        AppendCommentary(Answer, ADelegationId);
    end);
end;

// -----------------------------------------------------------------------------
// Delegation to Responses (ldResponses): function calling
// -----------------------------------------------------------------------------

procedure TAiOpenAiLiveChat.HandleResponseEvent(const JObj: TJSONObject);
var
  JInner, JItem, JResp, JErr: TJSONObject;
  Key, IType, ItemType, Msg: string;
  Turn: TAiLiveToolTurn;
begin
  if not JObj.TryGetValue<TJSONObject>('event', JInner) then Exit;
  Key := '';
  JObj.TryGetValue<string>('delegation_id', Key);
  IType := '';
  JInner.TryGetValue<string>('type', IType);

  if Assigned(FOnResponseEvent) then
    DoResponseEvent(Key, IType, JInner.ToJSON);

  if IType = 'response.output_item.done' then
  begin
    if JInner.TryGetValue<TJSONObject>('item', JItem) then
    begin
      ItemType := '';
      JItem.TryGetValue<string>('type', ItemType);
      if ItemType = 'function_call' then
        HandleFunctionCall(Key, JItem);
    end;
  end

  else if (IType = 'response.completed') or (IType = 'response.incomplete') then
  begin
    FToolLock.Enter;
    try
      if FToolTurns.TryGetValue(Key, Turn) then
      begin
        Turn.Completed := True;
        FToolTurns[Key] := Turn;
      end;
    finally
      FToolLock.Leave;
    end;
    TryContinueAfterTools(Key);
  end

  else if IType = 'response.failed' then
  begin
    Msg := 'The delegated response failed';
    if JInner.TryGetValue<TJSONObject>('response', JResp) and
       JResp.TryGetValue<TJSONObject>('error', JErr) then
      JErr.TryGetValue<string>('message', Msg);
    FToolLock.Enter;
    try
      FToolTurns.Remove(Key);
    finally
      FToolLock.Leave;
    end;
    DoError(Msg, 'delegation_failed');
  end;
end;

procedure TAiOpenAiLiveChat.HandleFunctionCall(const AKey: string; const AItem: TJSONObject);
var
  FuncName, CallId, Args: string;
  Turn: TAiLiveToolTurn;
begin
  FuncName := '';
  CallId := '';
  Args := '';
  AItem.TryGetValue<string>('name', FuncName);
  AItem.TryGetValue<string>('call_id', CallId);
  AItem.TryGetValue<string>('arguments', Args);
  if (FuncName = '') or (CallId = '') then Exit;

  FToolLock.Enter;
  try
    if not FToolTurns.TryGetValue(AKey, Turn) then
      Turn := Default(TAiLiveToolTurn);
    Inc(Turn.Pending);
    Turn.HadCalls := True;
    FToolTurns.AddOrSetValue(AKey, Turn);
  finally
    FToolLock.Leave;
  end;

  StartWorker(
    procedure
    var
      ToolCall: TAiToolsFunction;
      Handled: Boolean;
      T: TAiLiveToolTurn;
    begin
      ToolCall := TAiToolsFunction.Create;
      try
        ToolCall.id := CallId;
        ToolCall.name := FuncName;
        ToolCall.Arguments := Args;
        Handled := False;
        try
          if Assigned(FAiFunctions) then
            Handled := FAiFunctions.DoCallFunction(ToolCall);
          if (not Handled) and Assigned(FOnCallToolFunction) then
          begin
            // The fallback runs on the main thread (it may touch the UI)
            TThread.Synchronize(nil,
              procedure
              begin
                FOnCallToolFunction(Self, ToolCall);
              end);
            Handled := True;
          end;
          if not Handled then
            ToolCall.Response := 'Error: no handler for function ' + FuncName;
        except
          on E: Exception do
            ToolCall.Response := 'Error running ' + FuncName + ': ' + E.Message;
        end;
        if not FShuttingDown then
          SendFunctionOutput(CallId, ToolCall.Response);
      finally
        ToolCall.Free;
      end;
      FToolLock.Enter;
      try
        if FToolTurns.TryGetValue(AKey, T) then
        begin
          Dec(T.Pending);
          FToolTurns[AKey] := T;
        end;
      finally
        FToolLock.Leave;
      end;
      TryContinueAfterTools(AKey);
    end);
end;

procedure TAiOpenAiLiveChat.TryContinueAfterTools(const AKey: string);
var
  Turn: TAiLiveToolTurn;
  Ready: Boolean;
  J: TJSONObject;
begin
  // Only one continuation per response: when the response that requested
  // the functions finishes and all results have been sent
  FToolLock.Enter;
  try
    Ready := FToolTurns.TryGetValue(AKey, Turn) and Turn.HadCalls and
      Turn.Completed and (Turn.Pending <= 0);
    if Ready then
      FToolTurns.Remove(AKey);
  finally
    FToolLock.Leave;
  end;
  if (not Ready) or FShuttingDown then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'response.create');
  J.AddPair('event_id', NextEventId);
  SendJson(J);
end;

procedure TAiOpenAiLiveChat.SendFunctionOutput(const ACallId, AOutput: string);
var
  J, JItem: TJSONObject;
begin
  JItem := TJSONObject.Create;
  JItem.AddPair('type', 'function_call_output');
  JItem.AddPair('call_id', ACallId);
  JItem.AddPair('output', AOutput);
  J := TJSONObject.Create;
  J.AddPair('type', 'response.item.create');
  J.AddPair('event_id', NextEventId);
  J.AddPair('item', JItem);
  SendJson(J);
end;

procedure TAiOpenAiLiveChat.StartWorker(AProc: TProc);
begin
  TInterlocked.Increment(FActiveWorkers);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AProc();
      finally
        TInterlocked.Decrement(FActiveWorkers);
      end;
    end).Start;
end;

// -----------------------------------------------------------------------------
// Context injections
// -----------------------------------------------------------------------------

class function TAiOpenAiLiveChat.SplitForAppend(const AText: string;
  AMaxBytes: Integer): TArray<string>;
var
  Parts: TList<string>;
  Rest, Chunk: string;
  I, Bytes, CharBytes, Cut, LastSpace: Integer;
begin
  Parts := TList<string>.Create;
  try
    Rest := Trim(AText);
    while Rest <> '' do
    begin
      // Advance character by character without splitting surrogate pairs
      Bytes := 0;
      Cut := 0;
      LastSpace := 0;
      I := 1;
      while I <= Length(Rest) do
      begin
        if IsLeadChar(Rest[I]) and (I < Length(Rest)) then
          CharBytes := TEncoding.UTF8.GetByteCount(Copy(Rest, I, 2))
        else
          CharBytes := TEncoding.UTF8.GetByteCount(Rest[I]);
        if Bytes + CharBytes > AMaxBytes then
          Break;
        Inc(Bytes, CharBytes);
        if IsLeadChar(Rest[I]) and (I < Length(Rest)) then
          Inc(I, 2)
        else
          Inc(I);
        Cut := I - 1;
        if Rest[Cut] = ' ' then
          LastSpace := Cut;
      end;
      if Cut >= Length(Rest) then
      begin
        Parts.Add(Rest);
        Break;
      end;
      if Cut = 0 then
        Cut := 1; // AMaxBytes smaller than one character: advance anyway
      // Prefer to break at a space in the second half of the fragment
      if LastSpace > Cut div 2 then
        Cut := LastSpace;
      Chunk := Trim(Copy(Rest, 1, Cut));
      if Chunk <> '' then
        Parts.Add(Chunk);
      Rest := Trim(Copy(Rest, Cut + 1, MaxInt));
    end;
    Result := Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

procedure TAiOpenAiLiveChat.SendAppend(const AType, AContent, ADelegationId: string);
var
  J: TJSONObject;
  Part: string;
begin
  for Part in SplitForAppend(AContent) do
  begin
    J := TJSONObject.Create;
    J.AddPair('type', AType);
    J.AddPair('event_id', NextEventId);
    J.AddPair('content', Part);
    // Required field even if null (general context). With delegation to
    // Responses the server only accepts null
    if (ADelegationId <> '') and (EffectiveDelegation = ldClient) then
      J.AddPair('delegation_id', ADelegationId)
    else
      J.AddPair('delegation_id', TJSONNull.Create);
    SendJson(J);
  end;
end;

procedure TAiOpenAiLiveChat.AppendCommentary(const AText, ADelegationId: string);
begin
  SendAppend('session.commentary.append', AText, ADelegationId);
end;

procedure TAiOpenAiLiveChat.AppendThinking(const AText, ADelegationId: string);
begin
  SendAppend('session.thinking.append', AText, ADelegationId);
end;

procedure TAiOpenAiLiveChat.AppendInstructions(const AText, ADelegationId: string);
begin
  SendAppend('session.instructions.append', AText, ADelegationId);
end;

procedure TAiOpenAiLiveChat.Mute;
var
  J: TJSONObject;
begin
  if not IsConnected then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'session.input_audio.mute');
  J.AddPair('event_id', NextEventId);
  SendJson(J);
end;

procedure TAiOpenAiLiveChat.Unmute;
var
  J: TJSONObject;
begin
  if not IsConnected then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'session.input_audio.unmute');
  J.AddPair('event_id', NextEventId);
  SendJson(J);
end;

// -----------------------------------------------------------------------------
// Dispatchers for own events
// -----------------------------------------------------------------------------

procedure TAiOpenAiLiveChat.DoDelegation(const ADelegationId, AContext: string);
begin
  if not Assigned(FOnDelegation) then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnDelegation) then
        FOnDelegation(Self, ADelegationId, AContext);
    end);
end;

procedure TAiOpenAiLiveChat.DoUsage(ASeconds, ARatio: Double);
begin
  if not Assigned(FOnUsage) then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnUsage) then
        FOnUsage(Self, ASeconds, ARatio);
    end);
end;

procedure TAiOpenAiLiveChat.DoSessionClosed(const AReason: string; ASeconds: Double);
begin
  if not Assigned(FOnSessionClosed) then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnSessionClosed) then
        FOnSessionClosed(Self, AReason, ASeconds);
    end);
end;

procedure TAiOpenAiLiveChat.DoResponseEvent(const ADelegationId, AType, AJson: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnResponseEvent) then
        FOnResponseEvent(Self, ADelegationId, AType, AJson);
    end);
end;

// -----------------------------------------------------------------------------
// WebSocket
// -----------------------------------------------------------------------------

procedure TAiOpenAiLiveChat.OnWSConnected(Sender: TObject);
begin
  DoConnected;
  // session.start goes before any other command
  SendJson(BuildSessionStart);
end;

procedure TAiOpenAiLiveChat.OnWSDisconnected(Sender: TObject);
begin
  FSessionStarted := False;
  FClosedEvent.SetEvent; // do not wait for a session.closed that will never arrive
  DoDisconnected;
end;

procedure TAiOpenAiLiveChat.OnWSError(Sender: TObject; const ErrorMsg: string);
begin
  DoError(ErrorMsg, 'websocket_error');
end;

procedure TAiOpenAiLiveChat.OnWSFrame(Sender: TObject; Opcode: TAiRealtimeWSOpcode;
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

procedure TAiOpenAiLiveChat.SendAudioChunk(const PCM16Data: TBytes);
var
  LData: TBytes;
begin
  if not IsConnected then Exit;
  if Length(PCM16Data) = 0 then Exit;
  LData := Copy(PCM16Data);
  TThread.Queue(nil,
    procedure
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

procedure TAiOpenAiLiveChat.InternalConnect;
begin
  // TAiRealtimeConnection copies its ApiKey/Model even if empty
  if ApiKey = '' then
    ApiKey := '@OPENAI_API_KEY';
  if Model = '' then
    Model := GetDefaultModel;
  // Delegation is resolved in a thread with a blocking call
  if Assigned(FDelegateChat) then
    FDelegateChat.Params.Values['Asynchronous'] := 'False';

  FSessionStarted := False;
  FSessionId := '';
  FCloseReason := '';
  FUsageSeconds := 0;
  FPrev := Default(TAiLiveTurn);
  FCur := Default(TAiLiveTurn);
  FBuf := Default(TAiLiveTurn);
  FTimelineMax := 0;
  FVoiceWall := 0;
  FTranscript.Clear;
  FDelegatedLines := 0;
  FToolLock.Enter;
  try
    FToolTurns.Clear;
  finally
    FToolLock.Leave;
  end;
  FClosedEvent.ResetEvent;

  FWebSocket.ExtraHeaders.Values['Authorization'] := 'Bearer ' + ResolvedApiKey;
  FConnectThread := TThread.CreateAnonymousThread(
    procedure
    begin
      if not FWebSocket.Connect(CLIVE_WSS) then
        DoError('Could not connect to GPT-Live', 'connection_failed');
    end);
  FConnectThread.FreeOnTerminate := False;
  FConnectThread.Start;
end;

procedure TAiOpenAiLiveChat.InternalDisconnect;
var
  J: TJSONObject;
  SW: TStopwatch;
begin
  // Graceful shutdown: session.closed carries the reason and final usage
  if FSessionStarted and (FCloseTimeoutMs > 0) then
  begin
    FClosedEvent.ResetEvent;
    J := TJSONObject.Create;
    J.AddPair('type', 'session.close');
    J.AddPair('event_id', NextEventId);
    try
      SendJson(J);
      // Frames are processed on the main thread (TThread.Queue): if you
      // wait there without draining the queue, session.closed never arrives
      SW := TStopwatch.StartNew;
      while (FClosedEvent.WaitFor(0) <> wrSignaled) and
            (SW.ElapsedMilliseconds < FCloseTimeoutMs) do
      begin
        if TThread.CurrentThread.ThreadID = MainThreadID then
          CheckSynchronize(10)
        else
          FClosedEvent.WaitFor(10);
      end;
    except
      // Socket is gone: close anyway
    end;
  end;
  FWebSocket.SendClose(1000, '');
  FWebSocket.Disconnect;
  if Assigned(FConnectThread) then
  begin
    FConnectThread.WaitFor;
    FreeAndNil(FConnectThread);
  end;
  FSessionStarted := False;
  Connected := False;
end;

procedure TAiOpenAiLiveChat.InternalSendAudio(const ResampledPCM16: TBytes);
var
  J: TJSONObject;
begin
  // Before session.started the server does not accept commands
  if (Length(ResampledPCM16) = 0) or (not FSessionStarted) then Exit;
  J := TJSONObject.Create;
  J.AddPair('type', 'session.input_audio.append');
  J.AddPair('audio', FB64.EncodeBytesToString(ResampledPCM16));
  SendJson(J);
end;

procedure TAiOpenAiLiveChat.InternalCommitAudio;
begin
  // Continuous stream: not applicable
end;

procedure TAiOpenAiLiveChat.InternalClearAudio;
begin
  // Continuous stream: not applicable
end;

initialization
  TAiRealtimeFactory.Instance.RegisterDriver(
    TAiOpenAiLiveChat.GetDriverName, TAiOpenAiLiveChat);

end.
