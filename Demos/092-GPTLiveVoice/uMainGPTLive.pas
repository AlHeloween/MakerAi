unit uMainGPTLive;

// MakerAI — Demo 092: OpenAI GPT-Live (full-duplex voice
//
// Voice conversation with TAiOpenAiLiveChat: the model listens while it speaks
// (it can be interrupted) and delegates reasoning:
//   - "Responses (OpenAI)": a model from the Responses API managed by
//     OpenAI, with optional web search and this demo's local functions.
//   - "My chat (DelegateChat)": any TAiChatConnection (Driver/Model of
//     the screen) resolves the task with the same functions; the driver
//     passes the transcript and speaks the answer.
//
// Example functions (TAiFunctions): hora_actual(zona) and luz(habitacion,
// encendida), which changes the screen indicator.
//
// RAG via MCP (optional): the demo 037 server (MCPServerRAG, HTTP)
// is added as an MCP client of the same TAiFunctions, so its tool
// rag_vector reaches the model along with the local functions. A
// TAiGuardrails allows only queries (search, list_docs, stats): the
// voice model cannot delete or index. See CLAUDE.md to prepare 037
// with PostgreSQL and the example document conocimiento_cafe_la_ceiba.txt.
//
// Audio: TAiAudioCapture (microphone, PCM16 24 kHz) -> driver -> TAiAudioPlayer.
// With speakers the microphone hears the assistant: "Speaker mode" mutes the
// microphone while its voice plays (detected by the energy of the audio that
// arrives). With headphones leave it off: that way it can be interrupted.
//
// Requires OPENAI_API_KEY (and the key of the provider chosen for DelegateChat).
// Cost: US$0.05 per minute of session plus the delegated model's tokens.

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Diagnostics, System.DateUtils, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Edit, FMX.ListBox, FMX.Layouts, FMX.Memo.Types,
  FMX.ScrollBox, FMX.Memo, FMX.Objects,
  uMakerAi.Core, uMakerAi.Chat.Messages, uMakerAi.Tools.Functions,
  uMakerAi.Chat.AiConnection, uMakerAi.Chat.Initializations,
  uMakerAi.Realtime, uMakerAi.Realtime.OpenAI.Live,
  uMakerAi.Utils.AudioCapture, uMakerAi.Utils.AudioPlayback,
  uMakerAi.MCPClient.Core, uMakerAi.Guardrails;

type
  TFormGPTLive = class(TForm)
    LayConfig: TLayout;
    LayRow1: TLayout;
    LblMic: TLabel;
    CbxMic: TComboBox;
    LblSpeaker: TLabel;
    CbxSpeaker: TComboBox;
    LblVoice: TLabel;
    CbxVoice: TComboBox;
    LayRow2: TLayout;
    LblDelegation: TLabel;
    CbxDelegation: TComboBox;
    LblChatDriver: TLabel;
    EdChatDriver: TEdit;
    LblChatModel: TLabel;
    EdChatModel: TEdit;
    ChkWebSearch: TCheckBox;
    LayRow3: TLayout;
    LblInstructions: TLabel;
    EdInstructions: TEdit;
    ChkSpeakerMode: TCheckBox;
    LayRow4: TLayout;
    ChkRag: TCheckBox;
    LblRagUrl: TLabel;
    EdRagUrl: TEdit;
    LblRagHint: TLabel;
    LayButtons: TLayout;
    BtnConnect: TButton;
    BtnMute: TButton;
    PbMicLevel: TProgressBar;
    CircleLight: TCircle;
    LblLight: TLabel;
    LblStatus: TLabel;
    LayGuide: TLayout;
    LblGuide: TLabel;
    MemoGuide: TMemo;
    LayLive: TLayout;
    LblLiveUser: TLabel;
    LblLiveAssistant: TLabel;
    MemoConversation: TMemo;
    Splitter1: TSplitter;
    MemoLog: TMemo;
    LayStatusBar: TLayout;
    LblUsage: TLabel;
    TimerSpeaker: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnConnectClick(Sender: TObject);
    procedure BtnMuteClick(Sender: TObject);
    procedure TimerSpeakerTimer(Sender: TObject);
  private
    FLive: TAiOpenAiLiveChat;
    FCapture: TAiAudioCapture;
    FPlayer: TAiAudioPlayer;
    FFunctions: TAiFunctions;
    FGuard: TAiGuardrails;
    FChat: TAiChatConnection;
    FMicDevices: TArray<TAiAudioDeviceInfo>;
    FSpeakerDevices: TArray<TAiAudioDeviceInfo>;
    FClock: TStopwatch;
    FConnected: Boolean;
    FMuted: Boolean;
    FLiveUser: string;
    FLiveAssistant: string;
    FLastUserMs: Int64;      // last user text (for latency)
    FWaitingAnswer: Boolean; // the user spoke and the assistant has not yet
    FLastVoiceOutMs: Int64;  // last time the output had voice (speaker mode)
    FHeardWhileSpeaking: string; // what the model heard while speaking
    procedure Log(const S: string);
    procedure LoadDevices;
    procedure SetConnectedUI(AConnected: Boolean);
    procedure SetupFunctions;
    procedure FillGuide;
    function SetupRag: Boolean;
    procedure SetLight(const ARoom: string; AOn: Boolean);
    // Guardrail: the voice model can only query the RAG
    procedure GuardCheck(Sender: TObject; const AToolName, AArguments: string;
      var AAllow: Boolean; var AReason: string);
    // Driver events
    procedure LiveConnected(Sender: TObject);
    procedure LiveDisconnected(Sender: TObject);
    procedure LiveSessionReady(Sender: TObject);
    procedure LiveUserDelta(Sender: TObject; const Delta: string);
    procedure LiveUserDone(Sender: TObject; const Transcript, ItemId: string);
    procedure LiveAssistantDelta(Sender: TObject; const AText: string);
    procedure LiveAssistantDone(Sender: TObject; const AText: string);
    procedure LiveAudio(Sender: TObject; const AData: TBytes);
    procedure LiveError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure LiveUsage(Sender: TObject; Seconds, ContextRatio: Double);
    procedure LiveClosed(Sender: TObject; const Reason: string; Seconds: Double);
    procedure LiveDelegation(Sender: TObject; const DelegationId, Context: string);
    procedure LiveResponseEvent(Sender: TObject; const DelegationId, EventType, EventJson: string);
    // Audio
    procedure CaptureLevel(Sender: TObject; const aSoundLevel: Int64);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerError(Sender: TObject; const ErrorMessage: string);
    // Local functions (run in a driver thread)
    procedure FuncHoraActual(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure FuncLuz(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
  end;

var
  FormGPTLive: TFormGPTLive;

implementation

{$R *.fmx}

const
  // Absolute average (PCM16) above which the output "has voice"
  CVOICE_OUT_LEVEL = 300;
  // Margin after the assistant's last voice: player buffer + queue
  CSPEAKER_TAIL_MS = 800;
  CPRICE_PER_MINUTE = 0.05;
  CVOICES: array[0..9] of string = ('marin', 'cedar', 'alloy', 'ash', 'ballad',
    'coral', 'echo', 'sage', 'shimmer', 'verse');
  // Credentials of the demo 037 server (hardcoded in its uTool.RAG.pas)
  CRAG_TOKEN = 'admin:MakerAi2026*';
  CRAG_LIVE_INSTRUCTIONS = ' For questions about Cafe La Ceiba (hours, ' +
    'prices, wifi, pets, events, policies) consult the knowledge base.';
  CRAG_BACKEND_INSTRUCTIONS = 'For questions about Cafe La Ceiba use the ' +
    'rag_vector tool with operation=search and topK=3, and answer only with what ' +
    'the result says; if it does not appear, say so.';

{ TFormGPTLive }

procedure TFormGPTLive.FormCreate(Sender: TObject);
var
  V: string;
begin
  FClock := TStopwatch.StartNew;

  for V in CVOICES do
    CbxVoice.Items.Add(V);
  CbxVoice.ItemIndex := 0;
  CbxDelegation.Items.Add('Responses (OpenAI)');
  CbxDelegation.Items.Add('My chat (DelegateChat)');
  CbxDelegation.ItemIndex := 0;
  EdChatDriver.Text := 'OpenAi';
  EdChatModel.Text := 'gpt-6-luna';
  EdInstructions.Text := 'Speak in Spanish, in short, natural phrases. ' +
    'For the time or the house lights use the tools.';
  EdRagUrl.Text := 'http://localhost:8093/mcp';

  FLive := TAiOpenAiLiveChat.Create(Self);
  FLive.OnConnected := LiveConnected;
  FLive.OnDisconnected := LiveDisconnected;
  FLive.OnSessionReady := LiveSessionReady;
  FLive.OnTranscriptDelta := LiveUserDelta;
  FLive.OnTranscriptCompleted := LiveUserDone;
  FLive.OnAssistantTextDelta := LiveAssistantDelta;
  FLive.OnAssistantText := LiveAssistantDone;
  FLive.OnAudioChunk := LiveAudio;
  FLive.OnError := LiveError;
  FLive.OnUsage := LiveUsage;
  FLive.OnSessionClosed := LiveClosed;
  FLive.OnDelegation := LiveDelegation;
  FLive.OnResponseEvent := LiveResponseEvent;

  FCapture := TAiAudioCapture.Create(Self);
  FCapture.Source := asMicrophone;
  FCapture.OutputSampleRate := 24000; // what GPT-Live expects: no resampling
  FCapture.OutputChannels := 1;
  FCapture.OnUpdate := CaptureLevel;
  FCapture.OnError := CaptureError;

  FPlayer := TAiAudioPlayer.Create(Self);
  FPlayer.OnError := PlayerError;

  SetupFunctions;
  FillGuide;
  LoadDevices;
  SetLight('', False);
  SetConnectedUI(False);
  Log('Ready. With speakers enable "Speaker mode"; with headphones, '
    + 'leave it off to be able to interrupt the assistant.');
end;

procedure TFormGPTLive.FormDestroy(Sender: TObject);
begin
  TimerSpeaker.Enabled := False;
  if FConnected then
  begin
    FCapture.Active := False;
    FLive.Disconnect;
  end;
  FPlayer.Active := False;
end;

procedure TFormGPTLive.Log(const S: string);
begin
  MemoLog.Lines.Add(Format('[%6.1f s] %s', [FClock.ElapsedMilliseconds / 1000, S]));
  MemoLog.GoToTextEnd;
end;

procedure TFormGPTLive.LoadDevices;
var
  D: TAiAudioDeviceInfo;
  I: Integer;
begin
  CbxMic.Items.Clear;
  CbxSpeaker.Items.Clear;
  CbxMic.Items.Add('(default)');
  CbxSpeaker.Items.Add('(default)');
  try
    FMicDevices := TAiAudioCapture.GetAudioDevices(asMicrophone);
    FSpeakerDevices := TAiAudioPlayer.GetPlaybackDevices;
  except
    on E: Exception do
      Log('Could not list devices: ' + E.Message);
  end;
  for D in FMicDevices do
    CbxMic.Items.Add(D.DeviceName);
  for D in FSpeakerDevices do
    CbxSpeaker.Items.Add(D.DeviceName);
  CbxMic.ItemIndex := 0;
  CbxSpeaker.ItemIndex := 0;
  // Preselect the defaults by name (so they are visible)
  for I := 0 to High(FMicDevices) do
    if FMicDevices[I].IsDefault then
      CbxMic.ItemIndex := I + 1;
  for I := 0 to High(FSpeakerDevices) do
    if FSpeakerDevices[I].IsDefault then
      CbxSpeaker.ItemIndex := I + 1;
end;

procedure TFormGPTLive.SetupFunctions;
var
  Fn: TFunctionActionItem;
  P: TFunctionParamsItem;
begin
  FFunctions := TAiFunctions.Create(Self);
  // All calls (local and MCP) go through the guardrail
  FGuard := TAiGuardrails.Create(Self);
  FGuard.OnCheckToolCall := GuardCheck;
  FFunctions.Guardrails := FGuard;

  Fn := FFunctions.Functions.Add;
  Fn.FunctionName := 'hora_actual';
  Fn.Enabled := True;
  Fn.Description.Text := 'Returns the current date and time in a time zone.';
  Fn.OnAction := FuncHoraActual;
  P := Fn.Parameters.Add;
  P.Name := 'zona';
  P.ParamType := ptString;
  P.Description.Text := 'IANA time zone, for example America/Bogota or Europe/Madrid.';
  P.Required := True;

  Fn := FFunctions.Functions.Add;
  Fn.FunctionName := 'luz';
  Fn.Enabled := True;
  Fn.Description.Text := 'Turns a house room''s light on or off.';
  Fn.OnAction := FuncLuz;
  P := Fn.Parameters.Add;
  P.Name := 'habitacion';
  P.ParamType := ptString;
  P.Description.Text := 'Room: living room, kitchen, study or bedroom.';
  P.Required := True;
  P := Fn.Parameters.Add;
  P.Name := 'encendida';
  P.ParamType := ptBoolean;
  P.Description.Text := 'true to turn on, false to turn off.';
  P.Required := True;
end;

procedure TFormGPTLive.FillGuide;
begin
  // Example questions to walk through what the demo shows
  MemoGuide.Lines.Text :=
    'CONVERSATION' + sLineBreak +
    '• Hello, how are you?' + sLineBreak +
    '• Explain photosynthesis to me in two sentences.' + sLineBreak +
    sLineBreak +
    'INTERRUPT (with headphones)' + sLineBreak +
    '• Tell me a long story about a dragon.' + sLineBreak +
    '  ...and halfway through: "Wait, make it about a cat instead".' + sLineBreak +
    sLineBreak +
    'LOCAL FUNCTIONS' + sLineBreak +
    '• What time is it in Madrid?' + sLineBreak +
    '• Turn on the living room light.' + sLineBreak +
    '• Turn off the light.' + sLineBreak +
    sLineBreak +
    'RAG VIA MCP (check "RAG from demo 037")' + sLineBreak +
    '• What is the Wi-Fi password of Café La Ceiba?' + sLineBreak +
    '• What time do they open on Saturdays?' + sLineBreak +
    '• How much is the cappuccino?' + sLineBreak +
    '• Can I bring my dog?' + sLineBreak +
    '• What is on Thursday afternoons?' + sLineBreak +
    '• How much is the coffee tasting and how many spots are there?' + sLineBreak +
    sLineBreak +
    'GUARDRAIL (must be refused)' + sLineBreak +
    '• Delete the entire knowledge base.' + sLineBreak +
    '  The log shows "Guardrail BLOCKED".' + sLineBreak +
    sLineBreak +
    'WEB SEARCH (check "Web search")' + sLineBreak +
    '• What technology news is there today?' + sLineBreak +
    sLineBreak +
    'DELEGATE TO YOUR CHAT' + sLineBreak +
    'Choose "My chat (DelegateChat)" and repeat the function or RAG ones: ' +
    'the Driver/Model model responds. The log shows the delegation.';
end;

function TFormGPTLive.SetupRag: Boolean;
var
  Item: TMCPClientItem;
begin
  // Built on every connection: the URL may have changed
  FFunctions.MCPClients.Clear;
  if not ChkRag.IsChecked then
    Exit(True);
  Item := FFunctions.MCPClients.Add;
  Item.Name := 'cafe'; // the tool reaches the model as cafe_99_rag_vector
  Item.TransportType := tpHttp;
  Item.Params.Values['URL'] := Trim(EdRagUrl.Text);
  Item.Params.Values['ApiBearerToken'] := CRAG_TOKEN;
  Item.Enabled := True;
  // Check now: if 037 is not running, warn before connecting
  Result := Item.MCPClient.Initialize and Item.MCPClient.Available;
  if Result then
    Log('RAG via MCP ready: ' + Item.Params.Values['URL'])
  else
  begin
    Log('Could not connect to the RAG server (' + Item.Params.Values['URL'] +
      '). Is demo 037 running with --protocol http --port 8093?');
    FFunctions.MCPClients.Clear;
  end;
end;

procedure TFormGPTLive.GuardCheck(Sender: TObject; const AToolName, AArguments: string;
  var AAllow: Boolean; var AReason: string);
var
  Args, Msg: string;
begin
  if Pos('rag_vector', AToolName) = 0 then
    Exit; // local functions: no restriction
  Args := StringReplace(AArguments, ' ', '', [rfReplaceAll]);
  AAllow := (Pos('"operation":"search"', Args) > 0) or
    (Pos('"operation":"list_docs"', Args) > 0) or (Pos('"operation":"stats"', Args) > 0);
  if not AAllow then
    AReason := 'the voice assistant can only query (search, list_docs, stats)';
  // var parameters cannot be captured: the message is built before
  if AAllow then
    Msg := 'RAG: ' + AArguments
  else
    Msg := 'Guardrail BLOCKED: ' + AArguments;
  TThread.Queue(nil,
    procedure
    begin
      Log(Msg);
    end);
end;

procedure TFormGPTLive.SetLight(const ARoom: string; AOn: Boolean);
begin
  if AOn then
    CircleLight.Fill.Color := TAlphaColors.Gold
  else
    CircleLight.Fill.Color := TAlphaColors.Dimgray;
  if ARoom = '' then
    LblLight.Text := 'Light: off'
  else
    LblLight.Text := 'Light ' + ARoom + ': ' + IfThen(AOn, 'on', 'off');
end;

procedure TFormGPTLive.SetConnectedUI(AConnected: Boolean);
begin
  FConnected := AConnected;
  BtnConnect.Text := IfThen(AConnected, 'Disconnect', 'Connect');
  BtnMute.Enabled := AConnected;
  // Voice, audio and instructions do not change while the session is open
  CbxMic.Enabled := not AConnected;
  CbxSpeaker.Enabled := not AConnected;
  CbxVoice.Enabled := not AConnected;
  CbxDelegation.Enabled := not AConnected;
  EdChatDriver.Enabled := not AConnected;
  EdChatModel.Enabled := not AConnected;
  ChkWebSearch.Enabled := not AConnected;
  EdInstructions.Enabled := not AConnected;
  ChkRag.Enabled := not AConnected;
  EdRagUrl.Enabled := not AConnected;
  if not AConnected then
  begin
    FMuted := False;
    BtnMute.Text := 'Mute microphone';
  end;
end;

procedure TFormGPTLive.BtnConnectClick(Sender: TObject);
begin
  if FConnected then
  begin
    Log('Disconnecting...');
    TimerSpeaker.Enabled := False;
    FCapture.Active := False;
    FLive.Disconnect; // espera session.closed (motivo y consumo final)
    FPlayer.ClearQueue;
    FPlayer.Active := False;
    SetConnectedUI(False);
    LblStatus.Text := 'Disconnected';
    Exit;
  end;

  if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
  begin
    Log('Missing environment variable OPENAI_API_KEY');
    Exit;
  end;

  if not SetupRag then
    Exit;
  FLive.Voice := CbxVoice.Selected.Text;
  FLive.Instructions := EdInstructions.Text;
  FLive.DelegationInstructions := '';
  if ChkRag.IsChecked then
  begin
    // The voice model decides when to delegate; the delegate decides how to use the tool
    FLive.Instructions := FLive.Instructions + CRAG_LIVE_INSTRUCTIONS;
    FLive.DelegationInstructions := CRAG_BACKEND_INSTRUCTIONS;
  end;
  FLive.EnableWebSearch := ChkWebSearch.IsChecked;
  FLive.AiFunctions := FFunctions;

  FreeAndNil(FChat);
  if CbxDelegation.ItemIndex = 1 then
  begin
    // The delegated chat has the same functions; the driver passes it the
    // transcript and speaks its answer
    FChat := TAiChatConnection.Create(Self);
    FChat.DriverName := Trim(EdChatDriver.Text);
    if Trim(EdChatModel.Text) <> '' then
      FChat.Model := Trim(EdChatModel.Text);
    FChat.AiFunctions := FFunctions;
    FChat.SystemPrompt.Text := 'You are the backend of a voice assistant. ' +
      'Respond with the result, brief and unformatted, in the user''s language.';
    if ChkRag.IsChecked then
      FChat.SystemPrompt.Add(CRAG_BACKEND_INSTRUCTIONS);
    FLive.DelegateChat := FChat;
    Log(Format('Delegation: DelegateChat (%s / %s)', [FChat.DriverName, FChat.Model]));
  end
  else
  begin
    FLive.DelegateChat := nil;
    Log('Delegation: Responses (' + FLive.DelegationModel + ')');
  end;

  // Player and capture (capture activates when session.started arrives)
  if CbxSpeaker.ItemIndex > 0 then
    FPlayer.DeviceId := FSpeakerDevices[CbxSpeaker.ItemIndex - 1].EndpointId
  else
    FPlayer.DeviceId := '';
  FPlayer.Active := True;
  if CbxMic.ItemIndex > 0 then
    FCapture.DeviceId := FMicDevices[CbxMic.ItemIndex - 1].EndpointId
  else
    FCapture.DeviceId := '';
  FCapture.RealtimeSTT := FLive;

  FLiveUser := '';
  FLiveAssistant := '';
  FWaitingAnswer := False;
  LblLiveUser.Text := '';
  LblLiveAssistant.Text := '';
  LblStatus.Text := 'Connecting...';
  SetConnectedUI(True);
  TimerSpeaker.Enabled := True;
  FLive.Connect;
end;

procedure TFormGPTLive.BtnMuteClick(Sender: TObject);
begin
  // Server-side silence: the model stops receiving the microphone
  FMuted := not FMuted;
  if FMuted then
    FLive.Mute
  else
    FLive.Unmute;
  BtnMute.Text := IfThen(FMuted, 'Enable microphone', 'Mute microphone');
  Log(IfThen(FMuted, 'Microphone muted (session.input_audio.mute)', 'Microphone active'));
end;

procedure TFormGPTLive.TimerSpeakerTimer(Sender: TObject);
var
  Speaking: Boolean;
begin
  // Speaker mode: mute the microphone while the assistant's voice plays
  // so it does not hear itself (Muted sends silence, does not cut the flow)
  Speaking := FClock.ElapsedMilliseconds - FLastVoiceOutMs < CSPEAKER_TAIL_MS;
  FCapture.Muted := ChkSpeakerMode.IsChecked and Speaking;
  if FConnected then
    LblStatus.Text := IfThen(Speaking, 'Assistant speaking', 'Listening') +
      IfThen(FCapture.Muted, ' (microphone paused)', '');
end;

// -----------------------------------------------------------------------------
// Eventos del driver (llegan en el hilo principal)
// -----------------------------------------------------------------------------

procedure TFormGPTLive.LiveConnected(Sender: TObject);
begin
  Log('WebSocket connected; sending session.start');
end;

procedure TFormGPTLive.LiveDisconnected(Sender: TObject);
begin
  Log('WebSocket closed');
  if FConnected then
  begin
    // Server-side close (expired, network error...)
    TimerSpeaker.Enabled := False;
    FCapture.Active := False;
    FPlayer.Active := False;
    SetConnectedUI(False);
    LblStatus.Text := 'Disconnected';
  end;
end;

procedure TFormGPTLive.LiveSessionReady(Sender: TObject);
begin
  Log('Session started: ' + FLive.SessionId + ' — speak whenever you want');
  FCapture.Active := True;
  LblStatus.Text := 'Listening';
end;

procedure TFormGPTLive.LiveUserDelta(Sender: TObject; const Delta: string);
begin
  // Full-duplex: what the model hears while speaking can interrupt it
  // (a cough, an "mm", or its own voice if the microphone captures it)
  if FClock.ElapsedMilliseconds - FLastVoiceOutMs < CSPEAKER_TAIL_MS then
    FHeardWhileSpeaking := FHeardWhileSpeaking + Delta
  else if FHeardWhileSpeaking <> '' then
  begin
    Log('The model heard you while speaking: "' + Trim(FHeardWhileSpeaking) +
      '" (if it was not you, it is echo: lower the volume or enable "Speaker mode")');
    FHeardWhileSpeaking := '';
  end;
  FLiveUser := FLiveUser + Delta;
  LblLiveUser.Text := 'You: ' + Trim(FLiveUser);
  FLastUserMs := FClock.ElapsedMilliseconds;
  FWaitingAnswer := True;
end;

procedure TFormGPTLive.LiveUserDone(Sender: TObject; const Transcript, ItemId: string);
begin
  MemoConversation.Lines.Add('You: ' + Transcript);
  MemoConversation.GoToTextEnd;
  FLiveUser := '';
  LblLiveUser.Text := '';
end;

procedure TFormGPTLive.LiveAssistantDelta(Sender: TObject; const AText: string);
begin
  if FWaitingAnswer then
  begin
    // Approximate: includes the delay of the user transcription
    Log(Format('First assistant text %d ms after the last user text',
      [FClock.ElapsedMilliseconds - FLastUserMs]));
    FWaitingAnswer := False;
  end;
  FLiveAssistant := FLiveAssistant + AText;
  LblLiveAssistant.Text := 'Assistant: ' + Trim(FLiveAssistant);
end;

procedure TFormGPTLive.LiveAssistantDone(Sender: TObject; const AText: string);
begin
  if FHeardWhileSpeaking <> '' then
  begin
    Log('The model heard you while speaking: "' + Trim(FHeardWhileSpeaking) +
      '" (if it was not you, it is echo: lower the volume or enable "Speaker mode")');
    FHeardWhileSpeaking := '';
  end;
  MemoConversation.Lines.Add('Assistant: ' + AText);
  MemoConversation.GoToTextEnd;
  FLiveAssistant := '';
  LblLiveAssistant.Text := '';
end;

procedure TFormGPTLive.LiveAudio(Sender: TObject; const AData: TBytes);
var
  I, N: Integer;
  Sum: Int64;
begin
  // The server sends continuous audio (with silence) in real time
  FPlayer.PlayPCM16(AData, FLive.TargetSampleRate, 1);
  N := Length(AData) div 2;
  if N = 0 then Exit;
  Sum := 0;
  for I := 0 to N - 1 do
    Inc(Sum, Abs(PSmallInt(@AData[I * 2])^));
  if Sum div N > CVOICE_OUT_LEVEL then
    FLastVoiceOutMs := FClock.ElapsedMilliseconds;
end;

procedure TFormGPTLive.LiveError(Sender: TObject; const ErrorMsg, ErrorCode: string);
begin
  Log('ERROR [' + ErrorCode + '] ' + ErrorMsg);
end;

procedure TFormGPTLive.LiveUsage(Sender: TObject; Seconds, ContextRatio: Double);
begin
  LblUsage.Text := Format('Session: %.0f s — US$%.3f voice — context %.1f%%',
    [Seconds, Seconds / 60 * CPRICE_PER_MINUTE, Max(ContextRatio, 0) * 100]);
end;

procedure TFormGPTLive.LiveClosed(Sender: TObject; const Reason: string; Seconds: Double);
begin
  Log(Format('Session closed (%s): %.0f s, US$%.3f voice',
    [Reason, Seconds, Seconds / 60 * CPRICE_PER_MINUTE]));
end;

procedure TFormGPTLive.LiveDelegation(Sender: TObject; const DelegationId, Context: string);
begin
  Log('Delegation ' + DelegationId + ' to DelegateChat: ' +
    StringReplace(Context, sLineBreak, ' | ', [rfReplaceAll]));
end;

procedure TFormGPTLive.LiveResponseEvent(Sender: TObject; const DelegationId, EventType, EventJson: string);
begin
  // Only the delegated model's milestones (without deltas)
  if (EventType = 'response.created') or (EventType = 'response.completed') or
     (EventType = 'response.failed') then
    Log('Responses: ' + EventType);
end;

// -----------------------------------------------------------------------------
// Audio
// -----------------------------------------------------------------------------

procedure TFormGPTLive.CaptureLevel(Sender: TObject; const aSoundLevel: Int64);
begin
  PbMicLevel.Value := Min(100, aSoundLevel * 100 div 3000);
end;

procedure TFormGPTLive.CaptureError(Sender: TObject; const ErrorMessage: string);
begin
  Log('Microphone: ' + ErrorMessage);
end;

procedure TFormGPTLive.PlayerError(Sender: TObject; const ErrorMessage: string);
begin
  Log('Speaker: ' + ErrorMessage);
end;

// -----------------------------------------------------------------------------
// Funciones locales: corren en un hilo del driver; la UI va por TThread.Queue
// -----------------------------------------------------------------------------

procedure TFormGPTLive.FuncHoraActual(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Zona: string;
begin
  Zona := ToolCall.Params.Values['zona'];
  // Demo: local time of the machine; a real service would convert to the requested zone
  ToolCall.Response := Format('{"zona":"%s","hora_local_del_equipo":"%s","nota":"%s"}',
    [Zona, FormatDateTime('yyyy-mm-dd hh:nn', Now),
     'time of the machine where the demo runs']);
  Handled := True;
  TThread.Queue(nil,
    procedure
    begin
      Log('Function hora_actual(' + Zona + ')');
    end);
end;

procedure TFormGPTLive.FuncLuz(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Room: string;
  IsOn: Boolean;
begin
  Room := ToolCall.Params.Values['habitacion'];
  IsOn := SameText(ToolCall.Params.Values['encendida'], 'true');
  ToolCall.Response := Format('{"habitacion":"%s","encendida":%s}',
    [Room, IfThen(IsOn, 'true', 'false')]);
  Handled := True;
  TThread.Queue(nil,
    procedure
    begin
      SetLight(Room, IsOn);
      Log(Format('Function luz(%s, %s)', [Room, IfThen(IsOn, 'on', 'off')]));
    end);
end;

end.
