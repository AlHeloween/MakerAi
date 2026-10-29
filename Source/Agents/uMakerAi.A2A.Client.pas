// MIT License
//
// MakerAI - A2A Client (Agent-to-Agent Protocol, Linux Foundation)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.A2A.Client;

// -----------------------------------------------------------------------------
// TAiA2AClient (spec A2A 1.0): consumes remote A2A agents.
//
// - FetchAgentCard: GET /.well-known/agent-card.json (with fallback to the
//   legacy /.well-known/agent.json alias). The card's url field becomes the
//   JSON-RPC endpoint: a third-party agent can publish the card on one host
//   and serve the RPC on another route.
// - SendText / SendTextEx: SendMessage with a TextPart. SendTextEx accepts
//   taskId and contextId, which is what allows continuing a conversation or
//   answering a task in input-required.
// - GetTask / CancelTask.
// - Literal tolerance: states and roles are read both in protobuf form
//   (TASK_STATE_COMPLETED / ROLE_AGENT) and in JSON-RPC form
//   (completed / agent), because the ecosystem uses both.
// - Telemetry: spans 'a2a.client <method>' (skClient) and propagation of the
//   W3C traceparent to the remote agent.
//
// TAiA2ARemoteAgentTool federates a graph node against a remote agent. If the
// remote agent asks for human input (input-required), the LOCAL node suspends
// instead of failing: on resume, the response travels to the remote task and the
// flow continues where it was. That is what lets a human-in-the-loop cross the
// federation instead of dying at the edge.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.HttpClient, System.Net.URLClient,
  uMakerAi.Agents, uMakerAi.Agents.Attributes,
  uMakerAi.Tools.Functions, uMakerAi.Chat.Messages;

type
  EA2AClientException = class(Exception);
  // The remote agent responded, but the task did not end well. It is distinguished from
  // the transport error so an orchestrator can decide whether to retry.
  EA2ARemoteTaskError = class(EA2AClientException);

  TAiA2ATaskState = (tsUnknown, tsSubmitted, tsWorking, tsInputRequired, tsCompleted, tsCanceled, tsFailed, tsRejected,
    tsAuthRequired);

  TAiA2AClient = class(TComponent)
  private
    FUrl: string;      // agent base, e.g. http://localhost:8280
    FEndpoint: string; // effective JSON-RPC endpoint (set by the Agent Card)
    FTimeout: Integer; // ms
    FRetryCount: Integer;
    FApiKey: string;
    FLastTaskId: string;
    FLastContextId: string;
    FLastState: string;
    FLastTaskState: TAiA2ATaskState;
    FLastStatusMessage: string;
    function JsonRpcCall(const AMethod: string; AParams: TJSONObject): TJSONObject;
    function ResolveEndpoint: string;
    function BuildHeaders(const ATraceParent: string): TNetHeaders;
    procedure ReadTaskStatus(ATask: TJSONObject);
  public
    constructor Create(AOwner: TComponent); override;

    // Downloads and returns the Agent Card (the caller frees the object). As a
    // useful effect it sets Endpoint from the card's url field.
    function FetchAgentCard: TJSONObject;

    // Sends a text message and returns the resulting Task (the caller
    // frees the object). The artifacts' text lands in AOutputText.
    function SendText(const AText: string; out AOutputText: string): TJSONObject;
    // Same, but continuing an existing task: with ATaskId of a task in
    // input-required, AText is the human response that resumes it.
    function SendTextEx(const AText, ATaskId, AContextId: string; out AOutputText: string; ABlocking: Boolean = True)
      : TJSONObject;

    function GetTask(const ATaskId: string): TJSONObject;
    function CancelTask(const ATaskId: string): TJSONObject;

    // Extracts the artifacts' text from an already-obtained Task.
    class function ArtifactsText(ATask: TJSONObject): string; static;
    // Normalizes the SendMessage result into a Task-shaped object,
    // tolerating the v1.0 {task}/{message} wrapper and the flat 0.x Task.
    class function UnwrapSendMessageResult(ARawResult: TJSONObject): TJSONObject; static;

    // Last task sent (convenience)
    property LastTaskId: string read FLastTaskId;
    property LastContextId: string read FLastContextId;
    // Raw literal exactly as the remote agent sent it.
    property LastState: string read FLastState;
    // Normalized state, independent of the literal's form.
    property LastTaskState: TAiA2ATaskState read FLastTaskState;
    // status.message text: the question to the human in input-required, or the
    // error detail in failed.
    property LastStatusMessage: string read FLastStatusMessage;
    // Effective JSON-RPC endpoint (Url + '/' until the card says otherwise).
    property Endpoint: string read ResolveEndpoint;
  published
    property Url: string read FUrl write FUrl;
    property Timeout: Integer read FTimeout write FTimeout default 60000;
    // Retries on transport failure (not on task failure), with growing
    // wait. 0 = no retry.
    property RetryCount: Integer read FRetryCount write FRetryCount default 2;
    // If not empty it is sent as Authorization: Bearer <ApiKey>.
    property ApiKey: string read FApiKey write FApiKey;
  end;

  // Agent federation: assign as a TAIAgentsNode's Tool so that node
  // delegates its input to a remote A2A agent. The node's input travels
  // as a text message and the output is the task artifacts' text.
  [TToolAttribute('A2ARemoteAgent', 'Delegates the node input to a remote A2A agent and returns the text of its artifacts',
    'A2A')]
  TAiA2ARemoteAgentTool = class(TAiToolBase)
  private
    [TToolParameterAttribute('Agent URL', 'Base URL of the remote A2A agent (e.g. http://host:8280)', '')]
    FAgentUrl: string;
    [TToolParameterAttribute('Timeout ms', 'Timeout of the remote call in milliseconds', '60000')]
    FTimeoutMs: Integer;
    [TToolParameterAttribute('Suspend on input required',
      'If the remote agent asks for human input, suspends the local node instead of failing', 'True')]
    FSuspendOnInputRequired: Boolean;
    [TToolParameterAttribute('Api Key', 'Bearer token of the remote agent', '')]
    FApiKey: string;
    FClient: TAiA2AClient;
    function GetClient: TAiA2AClient;
    function StateKey(ANode: TAIAgentsNode): string;
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string); override;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
  published
    property AgentUrl: string read FAgentUrl write FAgentUrl;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs default 60000;
    property SuspendOnInputRequired: Boolean read FSuspendOnInputRequired write FSuspendOnInputRequired default True;
    property ApiKey: string read FApiKey write FApiKey;
  end;

  // Exposes a remote A2A agent as a chat TOOL: when a TAiFunctions is assigned,
  // the LLM can invoke the agent like any other
  // function. It complements TAiA2ARemoteAgentTool, which does the same but for
  // a graph node instead of a chat.
  TAiA2AAgentTool = class(TComponent)
  private
    FFunctions: TAiFunctions;
    FAgentUrl: string;
    FToolName: string;
    FDescription: string;
    FApiKey: string;
    FTimeoutMs: Integer;
    FItem: TFunctionActionItem;
    procedure SetFunctions(const Value: TAiFunctions);
    procedure DoToolAction(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Registers the function in the assigned TAiFunctions. It is called only when
    // Functions is assigned; it is exposed in case it must be redone after changing
    // ToolName or Description at runtime.
    procedure RegisterTool;
    // Fills ToolName and Description from the remote agent's Agent Card.
    // That way the LLM sees the description the agent itself publishes about itself.
    procedure DiscoverFromCard;
  published
    property Functions: TAiFunctions read FFunctions write SetFunctions;
    property AgentUrl: string read FAgentUrl write FAgentUrl;
    // Name under which the LLM sees the tool. If left empty, 'ask_remote_agent'
    // is used.
    property ToolName: string read FToolName write FToolName;
    property Description: string read FDescription write FDescription;
    property ApiKey: string read FApiKey write FApiKey;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs default 60000;
  end;

// Normalizes either form of the literal ('TASK_STATE_INPUT_REQUIRED'
// or 'input-required') to the enum.
function A2AParseState(const AValue: string): TAiA2ATaskState;

procedure Register;

implementation

uses System.Math, System.StrUtils, uMakerAi.Telemetry, uMakerAi.Agents.EngineRegistry;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiA2AClient, TAiA2AAgentTool]);
end;

function A2AParseState(const AValue: string): TAiA2ATaskState;
var
  S: string;
begin
  S := Trim(AValue).ToLower;
  if S.StartsWith('task_state_') then
    S := S.Substring(Length('task_state_'));
  S := S.Replace('_', '-');

  if S = 'submitted' then
    Result := tsSubmitted
  else if S = 'working' then
    Result := tsWorking
  else if S = 'input-required' then
    Result := tsInputRequired
  else if S = 'completed' then
    Result := tsCompleted
  else if S = 'canceled' then
    Result := tsCanceled
  else if (S = 'failed') or (S = 'error') then
    Result := tsFailed
  else if S = 'rejected' then
    Result := tsRejected
  else if S = 'auth-required' then
    Result := tsAuthRequired
  else
    Result := tsUnknown;
end;

{ TAiA2AClient }

constructor TAiA2AClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimeout := 60000;
  FRetryCount := 2;
  FLastTaskState := tsUnknown;
end;

function TAiA2AClient.ResolveEndpoint: string;
begin
  if FEndpoint <> '' then
    Result := FEndpoint
  else
    Result := FUrl.TrimRight(['/']) + '/';
end;

function TAiA2AClient.BuildHeaders(const ATraceParent: string): TNetHeaders;
begin
  SetLength(Result, 0);
  if ATraceParent <> '' then
    Result := Result + [TNameValuePair.Create('traceparent', ATraceParent)];
  if FApiKey <> '' then
    Result := Result + [TNameValuePair.Create('Authorization', 'Bearer ' + FApiKey)];
end;

function TAiA2AClient.FetchAgentCard: TJSONObject;
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  BaseUrl, Content, CardUrl, S: string;
  V, VCard: TJSONValue;
  Ifaces: TJSONArray;
  IfaceObj: TJSONObject;
  LSpan: TAiSpan;
begin
  Result := nil;
  BaseUrl := FUrl.TrimRight(['/']);
  LSpan := AiSpanStart('a2a.client agent-card', skClient);
  AiSpanAttr(LSpan, 'a2a.url', BaseUrl);
  Http := THTTPClient.Create;
  try
    try
      Http.ConnectionTimeout := FTimeout;
      Http.ResponseTimeout := FTimeout;
      Resp := Http.Get(BaseUrl + '/.well-known/agent-card.json', nil, BuildHeaders(AiSpanTraceParent(LSpan)));
      if Resp.StatusCode <> 200 then
        Resp := Http.Get(BaseUrl + '/.well-known/agent.json', nil, BuildHeaders(AiSpanTraceParent(LSpan)));
      // legacy alias
      if Resp.StatusCode <> 200 then
        raise EA2AClientException.CreateFmt('Agent card not found (HTTP %d)', [Resp.StatusCode]);
      Content := Resp.ContentAsString(TEncoding.UTF8);
      V := TJSONObject.ParseJSONValue(Content);
      if not(V is TJSONObject) then
      begin
        V.Free;
        raise EA2AClientException.Create('Agent card is not a JSON object');
      end;
      Result := TJSONObject(V);

      // The card takes precedence over the base URL: the RPC endpoint may not be the root.
      // In v1.0 the URL lives in supportedInterfaces[]; the root's 'url' field
      // is from the 0.x era and no longer exists in the spec's AgentCard.
      CardUrl := '';
      if Result.TryGetValue<TJSONArray>('supportedInterfaces', Ifaces) then
        for VCard in Ifaces do
          if VCard is TJSONObject then
          begin
            IfaceObj := TJSONObject(VCard);
            // We care about the JSON-RPC binding; if it does not say which, it is accepted.
            S := IfaceObj.GetValue<string>('protocolBinding', '');
            if (S = '') or SameText(S, 'JSONRPC') or S.ToUpper.Contains('JSONRPC') then
            begin
              CardUrl := IfaceObj.GetValue<string>('url', '');
              if CardUrl <> '' then
                Break;
            end;
          end;
      if CardUrl = '' then
        CardUrl := Result.GetValue<string>('url', ''); // 0.x-era fallback
      if CardUrl <> '' then
        FEndpoint := CardUrl;

      AiSpanEnd(LSpan);
      LSpan := nil;
    except
      on E: Exception do
      begin
        AiSpanEnd(LSpan, E.Message);
        raise;
      end;
    end;
  finally
    Http.Free;
  end;
end;

function TAiA2AClient.JsonRpcCall(const AMethod: string; AParams: TJSONObject): TJSONObject;
var
  Http: THTTPClient;
  Req: TJSONObject;
  Body: TStringStream;
  Resp: IHTTPResponse;
  Root: TJSONValue;
  RespObj, ErrObj: TJSONObject;
  ResultVal: TJSONValue;
  LSpan: TAiSpan;
  Attempt: Integer;
  LastErr: string;
  Payload: string;
begin
  Result := nil;
  Req := TJSONObject.Create;
  LSpan := AiSpanStart('a2a.client ' + AMethod, skClient);
  AiSpanAttr(LSpan, 'a2a.method', AMethod);
  try
    try
      Req.AddPair('jsonrpc', '2.0');
      Req.AddPair('id', TJSONNumber.Create(1));
      Req.AddPair('method', AMethod);
      if Assigned(AParams) then
        Req.AddPair('params', AParams); // takes ownership
      Payload := Req.ToJSON;

      Attempt := 0;
      LastErr := '';
      while True do
      begin
        Http := THTTPClient.Create;
        try
          Http.ConnectionTimeout := FTimeout;
          Http.ResponseTimeout := FTimeout;
          Http.ContentType := 'application/json';
          Body := TStringStream.Create(Payload, TEncoding.UTF8);
          try
            try
              Resp := Http.Post(ResolveEndpoint, Body, nil, BuildHeaders(AiSpanTraceParent(LSpan)));
              LastErr := '';
            except
              on E: Exception do
              begin
                Resp := nil;
                LastErr := E.Message;
              end;
            end;
          finally
            Body.Free;
          end;
        finally
          Http.Free;
        end;

        if Assigned(Resp) and (Resp.StatusCode = 200) then
          Break;

        if Assigned(Resp) then
          LastErr := Format('HTTP %d: %s', [Resp.StatusCode, Resp.ContentAsString(TEncoding.UTF8)]);

        // Only the transport is retried. A failed task is not a network
        // failure and repeating it would duplicate the remote agent's work.
        Inc(Attempt);
        if Attempt > FRetryCount then
          raise EA2AClientException.Create(LastErr);
        Sleep(Min(200 * Attempt, 2000));
      end;

      Root := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
      if not(Root is TJSONObject) then
      begin
        Root.Free;
        raise EA2AClientException.Create('Invalid JSON-RPC response');
      end;
      RespObj := TJSONObject(Root);
      try
        if RespObj.TryGetValue<TJSONObject>('error', ErrObj) then
          raise EA2ARemoteTaskError.Create('A2A error: ' + ErrObj.ToJSON);
        if RespObj.TryGetValue('result', ResultVal) and (ResultVal is TJSONObject) then
          Result := TJSONObject(ResultVal.Clone)
        else
          raise EA2AClientException.Create('A2A response has no result object');
      finally
        RespObj.Free;
      end;
      AiSpanEnd(LSpan);
      LSpan := nil;
    except
      on E: Exception do
      begin
        AiSpanEnd(LSpan, E.Message);
        raise;
      end;
    end;
  finally
    Req.Free;
  end;
end;

class function TAiA2AClient.ArtifactsText(ATask: TJSONObject): string;
var
  Artifacts, AParts: TJSONArray;
  ArtObj, PObj: TJSONObject;
  AV, PV, DataVal: TJSONValue;
  SB: TStringBuilder;
  S: string;
begin
  Result := '';
  if not Assigned(ATask) then
    Exit;
  SB := TStringBuilder.Create;
  try
    if ATask.TryGetValue<TJSONArray>('artifacts', Artifacts) then
      for AV in Artifacts do
        if AV is TJSONObject then
        begin
          ArtObj := TJSONObject(AV);
          if ArtObj.TryGetValue<TJSONArray>('parts', AParts) then
            for PV in AParts do
              if (PV is TJSONObject) then
              begin
                PObj := TJSONObject(PV);
                if PObj.TryGetValue<string>('text', S) then
                begin
                  if SB.Length > 0 then
                    SB.Append(sLineBreak);
                  SB.Append(S);
                end
                else if PObj.TryGetValue<TJSONValue>('data', DataVal) then
                begin
                  if SB.Length > 0 then
                    SB.Append(sLineBreak);
                  SB.Append(DataVal.ToJSON);
                end;
              end;
        end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Reads the Task's id/contextId/status and leaves the normalized state at hand.
procedure TAiA2AClient.ReadTaskStatus(ATask: TJSONObject);
var
  StatusObj, MsgObj: TJSONObject;
  Parts: TJSONArray;
  PV: TJSONValue;
  S: string;
begin
  FLastTaskId := '';
  FLastContextId := '';
  FLastState := '';
  FLastTaskState := tsUnknown;
  FLastStatusMessage := '';
  if not Assigned(ATask) then
    Exit;

  FLastTaskId := ATask.GetValue<string>('id', '');
  FLastContextId := ATask.GetValue<string>('contextId', '');

  if ATask.TryGetValue<TJSONObject>('status', StatusObj) then
  begin
    FLastState := StatusObj.GetValue<string>('state', '');
    FLastTaskState := A2AParseState(FLastState);
    if StatusObj.TryGetValue<TJSONObject>('message', MsgObj) and MsgObj.TryGetValue<TJSONArray>('parts', Parts) then
      for PV in Parts do
        if (PV is TJSONObject) and TJSONObject(PV).TryGetValue<string>('text', S) then
        begin
          if FLastStatusMessage <> '' then
            FLastStatusMessage := FLastStatusMessage + sLineBreak;
          FLastStatusMessage := FLastStatusMessage + S;
        end;
  end;
end;

function TAiA2AClient.SendTextEx(const AText, ATaskId, AContextId: string; out AOutputText: string; ABlocking: Boolean)
  : TJSONObject;
var
  Params, Msg, PartObj, Config, Raw: TJSONObject;
  Parts: TJSONArray;
  G: TGUID;
begin
  AOutputText := '';

  Params := TJSONObject.Create;
  Msg := TJSONObject.Create;
  Params.AddPair('message', Msg);
  CreateGUID(G);
  Msg.AddPair('messageId', GUIDToString(G).Replace('{', '').Replace('}', '').ToLower);
  Msg.AddPair('role', 'ROLE_USER');
  if ATaskId <> '' then
    Msg.AddPair('taskId', ATaskId);
  if AContextId <> '' then
    Msg.AddPair('contextId', AContextId);
  Parts := TJSONArray.Create;
  Msg.AddPair('parts', Parts);
  PartObj := TJSONObject.Create;
  PartObj.AddPair('text', AText);
  Parts.AddElement(PartObj);

  if not ABlocking then
  begin
    Config := TJSONObject.Create;
    Config.AddPair('blocking', TJSONBool.Create(False));
    Params.AddPair('configuration', Config);
  end;

  Raw := JsonRpcCall('SendMessage', Params); // JsonRpcCall frees Params
  try
    Result := UnwrapSendMessageResult(Raw);
  finally
    Raw.Free;
  end;
  ReadTaskStatus(Result);
  AOutputText := ArtifactsText(Result);
end;

// The SendMessage result is a SendMessageResponse: a oneof {task | message}.
// This function ALWAYS returns a Task-shaped object, so the rest of the
// client does not have to know which era the remote agent speaks.
//   {"task": {...}}     -> v1.0, the normal case
//   {"message": {...}}  -> v1.0, the agent answered at once without creating a task
//   {...task fields...} -> 0.x era, the Task traveled flat
class function TAiA2AClient.UnwrapSendMessageResult(ARawResult: TJSONObject): TJSONObject;
var
  Inner, MsgObj, StatusObj, ArtObj: TJSONObject;
  Parts, Artifacts: TJSONArray;
begin
  if not Assigned(ARawResult) then
    Exit(nil);

  if ARawResult.TryGetValue<TJSONObject>('task', Inner) then
    Exit(TJSONObject(Inner.Clone));

  if ARawResult.TryGetValue<TJSONObject>('message', MsgObj) then
  begin
    // Immediate response without a task: a completed Task is synthesized with the
    // message text as an artifact, so the SendText contract is not broken.
    Result := TJSONObject.Create;
    Result.AddPair('id', MsgObj.GetValue<string>('taskId', ''));
    Result.AddPair('contextId', MsgObj.GetValue<string>('contextId', ''));
    StatusObj := TJSONObject.Create;
    StatusObj.AddPair('state', 'TASK_STATE_COMPLETED');
    Result.AddPair('status', StatusObj);
    Artifacts := TJSONArray.Create;
    if MsgObj.TryGetValue<TJSONArray>('parts', Parts) then
    begin
      ArtObj := TJSONObject.Create;
      ArtObj.AddPair('artifactId', 'inline-message');
      ArtObj.AddPair('name', 'result');
      ArtObj.AddPair('parts', TJSONArray(Parts.Clone));
      Artifacts.AddElement(ArtObj);
    end;
    Result.AddPair('artifacts', Artifacts);
    Exit;
  end;

  Result := TJSONObject(ARawResult.Clone);
end;

function TAiA2AClient.SendText(const AText: string; out AOutputText: string): TJSONObject;
begin
  Result := SendTextEx(AText, '', '', AOutputText, True);
end;

function TAiA2AClient.GetTask(const ATaskId: string): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('id', ATaskId);
  Result := JsonRpcCall('GetTask', Params);
  ReadTaskStatus(Result);
end;

function TAiA2AClient.CancelTask(const ATaskId: string): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('id', ATaskId);
  Result := JsonRpcCall('CancelTask', Params);
  ReadTaskStatus(Result);
end;

{ TAiA2ARemoteAgentTool }

constructor TAiA2ARemoteAgentTool.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  FTimeoutMs := 60000;
  FSuspendOnInputRequired := True;
end;

destructor TAiA2ARemoteAgentTool.Destroy;
begin
  FClient.Free;
  inherited;
end;

function TAiA2ARemoteAgentTool.GetClient: TAiA2AClient;
begin
  if not Assigned(FClient) then
    FClient := TAiA2AClient.Create(nil);
  FClient.Url := FAgentUrl;
  FClient.Timeout := FTimeoutMs;
  FClient.ApiKey := FApiKey;
  Result := FClient;
end;

// Blackboard key where this node's pending remote task is remembered.
// It goes per node, not per tool: the same tool instance can be assigned to
// several nodes of the graph.
function TAiA2ARemoteAgentTool.StateKey(ANode: TAIAgentsNode): string;
begin
  Result := 'A2A.' + ANode.Name + '.PendingTask';
end;

procedure TAiA2ARemoteAgentTool.Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string);
var
  Client: TAiA2AClient;
  Task: TJSONObject;
  OutText, Pending, TaskId, ContextId: string;
  Sep: Integer;
  Board: TAIBlackboard;
begin
  if Trim(FAgentUrl) = '' then
    raise EA2AClientException.Create('TAiA2ARemoteAgentTool: AgentUrl not configured');

  Board := nil;
  if Assigned(ANode) and Assigned(ANode.Graph) then
    Board := ANode.Graph.Blackboard;

  // If this node already had a remote task in input-required, this call is the
  // resume: AInput is the human response and travels to the SAME remote task.
  TaskId := '';
  ContextId := '';
  if Assigned(Board) then
  begin
    Pending := Board.GetString(StateKey(ANode));
    Sep := Pos('|', Pending);
    if Sep > 0 then
    begin
      TaskId := Copy(Pending, 1, Sep - 1);
      ContextId := Copy(Pending, Sep + 1, MaxInt);
    end;
  end;

  Client := GetClient;
  Task := Client.SendTextEx(AInput, TaskId, ContextId, OutText);
  try
    case Client.LastTaskState of
      tsCompleted:
        begin
          if Assigned(Board) then
            Board.SetString(StateKey(ANode), '');
          AOutput := OutText;
        end;

      tsInputRequired:
        begin
          if not FSuspendOnInputRequired then
            raise EA2ARemoteTaskError.CreateFmt('The remote A2A agent requires additional input: %s',
              [Client.LastStatusMessage]);
          // The remote task is remembered and the local node suspends. On resume
          // (ResumeThread) this Execute runs again and continues right there.
          if Assigned(Board) then
            Board.SetString(StateKey(ANode), Client.LastTaskId + '|' + Client.LastContextId);
          AOutput := AInput; // pass-through while waiting for the human
          ANode.Suspend(Client.LastStatusMessage, 'A2A task ' + Client.LastTaskId + ' @ ' + FAgentUrl);
        end;
    else
      raise EA2ARemoteTaskError.CreateFmt('The remote A2A agent ended in %s%s',
        [Client.LastState, IfThen(Client.LastStatusMessage <> '', ': ' + Client.LastStatusMessage, '')]);
    end;
  finally
    Task.Free;
  end;
end;

{ TAiA2AAgentTool }

constructor TAiA2AAgentTool.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimeoutMs := 60000;
  FToolName := 'ask_remote_agent';
  FDescription := 'Delegates a query to a specialized remote agent and returns its response';
end;

procedure TAiA2AAgentTool.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FFunctions) then
  begin
    FFunctions := nil;
    FItem := nil; // the collection destroys it; only the reference is released here
  end;
end;

procedure TAiA2AAgentTool.SetFunctions(const Value: TAiFunctions);
begin
  if FFunctions = Value then
    Exit;
  FFunctions := Value;
  if Assigned(FFunctions) then
  begin
    FFunctions.FreeNotification(Self);
    RegisterTool;
  end;
end;

procedure TAiA2AAgentTool.RegisterTool;
var
  Param: TFunctionParamsItem;
begin
  if not Assigned(FFunctions) then
    Exit;
  if not Assigned(FItem) then
    FItem := FFunctions.Functions.Add;

  FItem.FunctionName := FToolName;
  FItem.Description.Text := FDescription;
  FItem.Enabled := True;
  FItem.OnAction := DoToolAction;
  // A single parameter: the natural-language query. The remote agent is
  // opaque by design, so exposing a detailed schema to it makes no sense.
  if FItem.Parameters.Count = 0 then
  begin
    Param := FItem.Parameters.Add;
    Param.Name := 'query';
    Param.Description.Text := 'The query or instruction for the remote agent';
    Param.ParamType := TToolsParamType.ptString;
    Param.Required := True;
  end;
end;

procedure TAiA2AAgentTool.DiscoverFromCard;
var
  Client: TAiA2AClient;
  Card: TJSONObject;
begin
  Client := TAiA2AClient.Create(nil);
  try
    Client.Url := FAgentUrl;
    Client.ApiKey := FApiKey;
    Client.Timeout := FTimeoutMs;
    Card := Client.FetchAgentCard;
    try
      if FDescription = '' then
        FDescription := Card.GetValue<string>('description', '')
      else
        FDescription := FDescription + ' (' + Card.GetValue<string>('description', '') + ')';
      RegisterTool;
    finally
      Card.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TAiA2AAgentTool.DoToolAction(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Client: TAiA2AClient;
  Task: TJSONObject;
  Consulta, Salida: string;
begin
  Handled := True;
  if Trim(FAgentUrl) = '' then
  begin
    ToolCall.Response := '{"error":"TAiA2AAgentTool: AgentUrl not configured"}';
    Exit;
  end;

  Consulta := ToolCall.Params.Values['query'];
  if Consulta = '' then
    Consulta := ToolCall.Arguments; // last resort: the raw JSON

  Client := TAiA2AClient.Create(nil);
  try
    Client.Url := FAgentUrl;
    Client.ApiKey := FApiKey;
    Client.Timeout := FTimeoutMs;
    try
      Task := Client.SendText(Consulta, Salida);
      try
        case Client.LastTaskState of
          tsCompleted:
            ToolCall.Response := Salida;
          tsInputRequired:
            // The remote agent asks for more data. It is returned to the LLM as
            // text: it is the LLM that decides whether to ask the user.
            ToolCall.Response := 'The remote agent needs more information: ' + Client.LastStatusMessage;
        else
          ToolCall.Response := 'The remote agent did not complete the task (' + Client.LastState + '): ' +
            Client.LastStatusMessage;
        end;
      finally
        Task.Free;
      end;
    except
      on E: Exception do
        // A remote agent failure is told to the LLM instead of breaking the
        // chat turn: it can retry or continue without that information.
        ToolCall.Response := 'Error calling the remote agent: ' + E.Message;
    end;
  finally
    Client.Free;
  end;
end;
initialization

TEngineRegistry.Instance.RegisterTool(TAiA2ARemoteAgentTool, 'uMakerAi.A2A.Client');

end.
