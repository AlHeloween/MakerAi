// MIT License
//
// MakerAI - A2A Server (Agent-to-Agent Protocol, Linux Foundation)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.A2A.Server;

// -----------------------------------------------------------------------------
// TAiA2AServer (spec A2A 1.0): exposes one or more TAIAgentManager as an A2A
// agent for orchestration / federation flows.
//
// - Agent Card at GET /.well-known/agent-card.json (and the legacy alias
//   /.well-known/agent.json).
// - JSON-RPC 2.0 binding at POST /: 1.0 methods (SendMessage, GetTask,
//   CancelTask) with tolerance for the 0.x aliases (message/send, tasks/get,
//   tasks/cancel).
//
// CONCURRENCY
//   A single TAIAgentManager cannot run two graphs at once, so a
//   server with a single manager serializes the tasks (the second one receives
//   AgentBusy). For real orchestration (fan-out of several nodes against the same
//   remote agent) assign OnAcquireManager: the factory returns a fresh
//   graph instance and the server keeps a pool of up to MaxConcurrentTasks.
//   The slot reservation is atomic, so two simultaneous requests cannot
//   take the same manager.
//
// TASK LIFECYCLE
//   SendMessage creates the task and launches the graph. If configuration.blocking is
//   false (or WaitTimeoutMs elapses) it responds with the task in working state and the
//   client continues with GetTask; the state is lazily refreshed from the
//   manager, so a task never lies. The slot is freed only
//   when a terminal state is reached.
//
// HUMAN-IN-THE-LOOP
//   A graph suspension (Node.Suspend) is published as input-required and the
//   task keeps its manager. A later SendMessage including that taskId
//   resumes the graph (ResumeThread) with the received text as the human
//   response, so the multi-turn conversation crosses A2A.
//
// OBSERVABILITY
//   The server span continues the caller's trace if the header
//   traceparent (W3C) arrives, the same way the MCP server does with _meta.
//
// No streaming and no push notifications: capabilities=false and the spec requires
// rejecting SendStreamingMessage with UnsupportedOperationError.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, System.Threading,
  System.Net.HttpClient, System.Net.URLClient,
  IdContext, IdCustomHTTPServer, IdHTTPServer, IdGlobal, IdGlobalProtocols,
  uMakerAi.Agents;

type
  // Exception with an explicit JSON-RPC code (avoids mapping errors by message
  // prefix, which was fragile and lost the code on any touch-up).
  EA2AServerError = class(Exception)
  private
    FCode: Integer;
  public
    constructor CreateCode(ACode: Integer; const AMsg: string);
    property Code: Integer read FCode;
  end;

  // How the spec's enums are serialized:
  //   anProto -> TASK_STATE_COMPLETED / ROLE_AGENT  (v1.0: ProtoJSON)
  //   anLower -> completed / agent                  (0.x era, kebab-case)
  // v1.0 moved from kebab-case to SCREAMING_SNAKE_CASE for ProtoJSON conformance,
  // so anProto is the correct one and anLower the compatibility one.
  // Reading always tolerates both.
  TAiA2ANaming = (anProto, anLower);

  // Wire format era. Verified against a2a-sdk 1.1.2:
  //   weV1  -> SendMessage returns a SendMessageResponse, with the Task WRAPPED
  //            in {"task": {...}}, and the Agent Card publishes supportedInterfaces[].
  //   weV03 -> the Task travels flat in result and the card carries url/protocolVersion
  //            at the root (what MakerAI emitted before August 2026).
  // NOTE: GetTask and CancelTask return the Task DIRECTLY in both eras; in the
  // proto they are "returns (Task)" and have no response message of their own.
  TAiA2AWireEra = (weV1, weV03);

  TAiA2AServer = class;

  // Pool slot: a manager + its reservation. The reservation belongs to the server and
  // does not depend on Manager.Busy, to close the TOCTOU window between "I saw it
  // free" and "I set it running".
  TAiA2AManagerSlot = class
  public
    Manager: TAIAgentManager;
    Owned: Boolean; // created by the factory -> we free it
    InUse: Boolean;
    PrevOnFinish: TAIAgentsOnFinish;
    HookedFinish: Boolean;
  end;

  // Push notification config registered for a task. The v1.0 form is
  // FLAT: {id, taskId, url, token, authentication:{scheme, credentials}}.
  TAiA2APushConfig = class
  public
    Id: string;
    TaskId: string;
    Url: string;
    Token: string;
    AuthScheme: string;
    AuthCredentials: string;
    function ToJson: TJSONObject;
  end;

  TAiA2ATaskInfo = class
  public
    Id: string;
    MessageId: string;  // messageId of the message that created the task
    ContextId: string;
    State: string; // canonical lowercase: working, completed, ...
    OutputText: string;
    ErrorText: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    // Link to the live execution (nil when the task is terminal)
    Slot: TAiA2AManagerSlot;
    ThreadID: string;
    SuspendNode: string;
    SuspendReason: string;
    SuspendContext: string;
    // Structured response the graph left in the blackboard (see
    // A2A_BB_ARTIFACTS / A2A_BB_MESSAGE). Empty = normal text response.
    ArtifactsJson: string;
    MessageJson: string;
    History: TStringList; // 'role<TAB>text'
    constructor Create;
    destructor Destroy; override;
  end;

  // ---------------------------------------------------------------------------
  // Skills declared on the Agent Card
  // ---------------------------------------------------------------------------
  // An A2A skill is what a client reads to DECIDE whether this agent serves it.
  // It is not an entry point: the spec carries no skill selector in
  // SendMessage, so skills describe, they do not route.
  //
  // That is why they are NOT derived from the nodes automatically: a normal graph has
  // nodes named 'Node1'/'Node2' without description, and publishing them would be noise
  // that also hints at an invocation granularity that does not exist. Whoever
  // wants useful skills declares them here; see also PublishNodesAsSkills
  // for the case where the nodes DO carry a description in their Tool.
  TAiA2ASkill = class(TCollectionItem)
  private
    FId: string;
    FTitle: string;
    FDescription: string;
    FTags: string;
  protected
    function GetDisplayName: string; override;
  public
    procedure Assign(Source: TPersistent); override;
  published
    property Id: string read FId write FId;
    // 'Title' and not 'Name': TCollectionItem has no Name, but the Agent Card's
    // field is called 'name'.
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    // Comma-separated. Emitted as a JSON array.
    property Tags: string read FTags write FTags;
  end;

  TAiA2ASkills = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TAiA2ASkill;
    procedure SetItem(AIndex: Integer; const Value: TAiA2ASkill);
  public
    constructor Create(AOwner: TPersistent);
    function Add: TAiA2ASkill;
    // Shortcut to declare a skill in one line from code.
    function AddSkill(const AId, ATitle, ADescription: string;
      const ATags: string = ''): TAiA2ASkill;
    property Items[AIndex: Integer]: TAiA2ASkill read GetItem write SetItem; default;
  end;

  // Manager factory for the pool. It must return a new and complete graph
  // (same shape as AgentManager); the server takes care of freeing it.
  TAiA2AAcquireManager = procedure(Sender: TObject; var AManager: TAIAgentManager) of object;
  // Last touch on the Agent Card before publishing it.
  TAiA2ACardEvent = procedure(Sender: TObject; ACard: TJSONObject) of object;
  // Own authorization. Called before processing the request; AAllow=False
  // responds 401. AAuthHeader is the raw Authorization value.
  TAiA2AAuthEvent = procedure(Sender: TObject; const AAuthHeader: string; var AAllow: Boolean) of object;

  TAiA2AServer = class(TComponent)
  private
    FHttpServer: TIdHTTPServer;
    FAgentManager: TAIAgentManager;
    FPort: Integer;
    FActive: Boolean;
    FAgentName: string;
    FAgentDescription: string;
    FAgentVersion: string;
    FWaitTimeoutMs: Integer;
    FMaxConcurrentTasks: Integer;
    FTaskTtlSeconds: Integer;
    FMaxTasks: Integer;
    FApiKey: string;
    FPublicUrl: string;
    FStateNaming: TAiA2ANaming;
    FWireEra: TAiA2AWireEra;
    FPublishExtendedCard: Boolean;
    FSkills: TAiA2ASkills;
    FPublishNodesAsSkills: Boolean;
    FCardCacheSeconds: Integer;
    FAcquireTimeoutMs: Integer;
    FEnableStreaming: Boolean;
    FEnablePushNotifications: Boolean;
    FPushConfigs: TObjectList<TAiA2APushConfig>;
    FPushLock: TCriticalSection;

    // Last base URL served, so GetExtendedAgentCard can be answered without
    // having the HTTP context at hand.
    FLastBaseUrl: string;
    // Bridge between DoSendMessage and HandleJsonRpc for the 'message' arm
    FLastMessageJson: string;
    FTasks: TObjectDictionary<string, TAiA2ATaskInfo>;
    FTasksLock: TCriticalSection;
    FSlots: TObjectList<TAiA2AManagerSlot>;
    FSlotsLock: TCriticalSection;
    FOnAcquireManager: TAiA2AAcquireManager;
    FOnCustomizeCard: TAiA2ACardEvent;
    FOnAuthorize: TAiA2AAuthEvent;
    procedure SetActive(const Value: Boolean);
    procedure SetAgentManager(const Value: TAIAgentManager);
    procedure SetSkills(const Value: TAiA2ASkills);
    // TIdHTTPServer only understands Basic authentication. With any other
    // scheme (Bearer, the one A2A uses) it responds 401 by itself and
    // HttpCommand never gets to run. Marking it as handled lets the
    // request continue and we decide the authorization.
    procedure ParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: string;
      var VUsername, VPassword: string; var VHandled: Boolean);
    procedure HttpCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    // --- pool ---
    function AcquireSlot: TAiA2AManagerSlot;
    procedure ReleaseSlot(ASlot: TAiA2AManagerSlot);
    procedure ClearSlots;
    // --- tasks ---
    function NewTask(const AContextId: string): TAiA2ATaskInfo;
    function FindTask(const AId: string): TAiA2ATaskInfo;
    // AIgnoreBusy: skip the Manager.Busy check. It only makes
    // sense from OnGraphFinished, where the graph is already known to have finished.
    procedure RefreshTask(AInfo: TAiA2ATaskInfo; AIgnoreBusy: Boolean = False); // requires FTasksLock taken
    procedure StartTask(AInfo: TAiA2ATaskInfo; const AInput: string);
    procedure ResumeTask(AInfo: TAiA2ATaskInfo; const AInput: string; const AMessageId: string);
    procedure WaitTask(AInfo: TAiA2ATaskInfo);
    procedure PurgeTasks;
    // --- json ---
    function BuildAgentCard(const ABaseUrl: string): TJSONObject;
    // AHistoryLength: -1 the whole history, 0 none, N the last N.
    function BuildTaskJson(AInfo: TAiA2ATaskInfo; AHistoryLength: Integer = -1): TJSONObject;
    // Wraps the Task as a SendMessageResponse when the era is v1.0.
    function WrapSendMessageResult(ATask: TJSONObject): TJSONObject;
    function WrapSendMessageAsMessage(const AMessageJson: string; ATask: TJSONObject): TJSONObject;
    // --- streaming SSE ---
    procedure SseWriteEvent(AContext: TIdContext; AId: TJSONValue; APayload: TJSONObject);
    function StreamStatusEvent(AInfo: TAiA2ATaskInfo): TJSONObject;
    // Emits the task's artifacts (only makes sense if completed). They go
    // BEFORE the final status: that is the spec example's order.
    procedure SseEmitArtifacts(AContext: TIdContext; AId: TJSONValue; AInfo: TAiA2ATaskInfo);
    procedure HandleStreamingRequest(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo; const AMethod: string; AParams: TJSONObject; AId: TJSONValue);
    function HandleJsonRpc(const ABody, ATraceParent: string): string;
    function RpcError(AId: TJSONValue; ACode: Integer; const AMsg: string): string;
    function RpcResult(AId: TJSONValue; AResult: TJSONObject): string;
    function DoSendMessage(AParams: TJSONObject): TJSONObject;
    function DoGetTask(AParams: TJSONObject): TJSONObject;
    function DoCancelTask(AParams: TJSONObject): TJSONObject;
    function DoListTasks(AParams: TJSONObject): TJSONObject;
    // --- push notifications ---
    function DoCreatePushConfig(AParams: TJSONObject): TJSONObject;
    function DoGetPushConfig(AParams: TJSONObject): TJSONObject;
    function DoListPushConfigs(AParams: TJSONObject): TJSONObject;
    function DoDeletePushConfig(AParams: TJSONObject): TJSONObject;
    procedure DeliverPushNotifications(AInfo: TAiA2ATaskInfo);
    // Hooks into TAIAgentManager.OnFinish: it is the notice that a graph
    // finished. It replaces polling, which was the only way to find out and
    // depended on someone querying the task.
    procedure RefreshLiveTasks;
    procedure OnGraphFinished(Sender: TObject; const Input, Output: string;
      Status: TAgentExecutionStatus; E: Exception);
    function EmitState(const ACanonical: string): string;
    function EmitRole(const ACanonical: string): string;
    class function ExtractTextFromParts(AMessage: TJSONObject): string; static;
    class function StatusToA2AState(AStatus: TAgentExecutionStatus): string; static;
    class function IsTerminal(const AState: string): Boolean; static;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Active: Boolean read FActive write SetActive;
  published
    property Port: Integer read FPort write FPort default 8280;
    property AgentManager: TAIAgentManager read FAgentManager write SetAgentManager;
    property AgentName: string read FAgentName write FAgentName;
    property AgentDescription: string read FAgentDescription write FAgentDescription;
    property AgentVersion: string read FAgentVersion write FAgentVersion;
    // Maximum wait of a blocking SendMessage. On expiry the task is NOT failed:
    // it is returned in working so the client continues with GetTask.
    property WaitTimeoutMs: Integer read FWaitTimeoutMs write FWaitTimeoutMs default 60000;
    // Alias of the previous name: already-written DFM files keep loading. It is
    // not serialized again (stored False) so the new name is the only
    // one left on disk.
    property RunTimeoutMs: Integer read FWaitTimeoutMs write FWaitTimeoutMs stored False;
    // Pool cap. Only exceeds 1 if OnAcquireManager is assigned.
    property MaxConcurrentTasks: Integer read FMaxConcurrentTasks write FMaxConcurrentTasks default 4;
    // Retention of finished tasks (seconds) and hard cap of the registry.
    property TaskTtlSeconds: Integer read FTaskTtlSeconds write FTaskTtlSeconds default 3600;
    property MaxTasks: Integer read FMaxTasks write FMaxTasks default 1000;
    // If not empty, Authorization: Bearer <ApiKey> (or X-API-Key) is required.
    property ApiKey: string read FApiKey write FApiKey;
    // Public URL to announce in the card (useful behind a reverse proxy).
    property PublicUrl: string read FPublicUrl write FPublicUrl;
    property StateNaming: TAiA2ANaming read FStateNaming write FStateNaming default anProto;
    // Wire format. weV1 is the spec 1.0 one and the default; weV03 reproduces
    // what MakerAI emitted before August 2026, so integrations that already
    // depended on that form do not break.
    property WireEra: TAiA2AWireEra read FWireEra write FWireEra default weV1;
    // Enables GetExtendedAgentCard. The extended card is built the same as
    // the public one, so to differentiate it you must enrich it in
    // OnCustomizeCard (which receives the card before it is published).
    property PublishExtendedCard: Boolean read FPublishExtendedCard write FPublishExtendedCard default False;
    // Declared skills. If empty, a single 'run-graph' skill is published
    // representing the whole graph's execution.
    property Skills: TAiA2ASkills read FSkills write SetSkills;
    // Adds one skill per graph node that has a description (its Tool's).
    // Nodes without description are omitted on purpose: publishing
    // 'Node1' with nothing else does not help anyone choose an agent.
    property PublishNodesAsSkills: Boolean read FPublishNodesAsSkills write FPublishNodesAsSkills default False;
    // Cache-Control/max-age seconds of the Agent Card (spec SHOULD).
    property CardCacheSeconds: Integer read FCardCacheSeconds write FCardCacheSeconds default 3600;
    // How long a pool slot is waited for before returning AgentBusy.
    property AcquireTimeoutMs: Integer read FAcquireTimeoutMs write FAcquireTimeoutMs default 10000;
    // Enables SendStreamingMessage and SubscribeToTask, and announces it in
    // capabilities.streaming. With False they are rejected with UnsupportedOperation.
    property EnableStreaming: Boolean read FEnableStreaming write FEnableStreaming default True;
    // Enables the config CRUD and the webhook delivery, and announces it in
    // capabilities.pushNotifications.
    property EnablePushNotifications: Boolean read FEnablePushNotifications
      write FEnablePushNotifications default True;
    property OnAcquireManager: TAiA2AAcquireManager read FOnAcquireManager write FOnAcquireManager;
    property OnCustomizeCard: TAiA2ACardEvent read FOnCustomizeCard write FOnCustomizeCard;
    property OnAuthorize: TAiA2AAuthEvent read FOnAuthorize write FOnAuthorize;
  end;

const
  // Canonical states of the spec (JSON-RPC lowercase form)
  A2A_STATE_SUBMITTED = 'submitted';
  A2A_STATE_WORKING = 'working';
  A2A_STATE_INPUT_REQUIRED = 'input-required';
  A2A_STATE_COMPLETED = 'completed';
  A2A_STATE_CANCELED = 'canceled';
  A2A_STATE_FAILED = 'failed';

  // A2A-specific JSON-RPC error codes (spec 1.0, section 5.4)
  A2A_ERR_AGENT_BUSY = -32000;
  A2A_ERR_TASK_NOT_FOUND = -32001;
  A2A_ERR_TASK_NOT_CANCELABLE = -32002;
  A2A_ERR_PUSH_NOT_SUPPORTED = -32003;
  A2A_ERR_UNSUPPORTED_OPERATION = -32004;
  A2A_ERR_CONTENT_TYPE_NOT_SUPPORTED = -32005;
  A2A_ERR_INVALID_AGENT_RESPONSE = -32006;
  A2A_ERR_EXTENDED_CARD_NOT_CONFIGURED = -32007;
  A2A_ERR_EXTENSION_SUPPORT_REQUIRED = -32008;
  A2A_ERR_VERSION_NOT_SUPPORTED = -32009;
  A2A_ERR_INVALID_PARAMS = -32602;

  // google.rpc ErrorInfo: the spec requires error.data to be an ARRAY containing
  // it, with the ProtoJSON @type convention.
  A2A_ERRORINFO_TYPE = 'type.googleapis.com/google.rpc.ErrorInfo';
  A2A_ERROR_DOMAIN = 'a2a-protocol.org';

  // Protocol version we announce and accept in the A2A-Version header
  A2A_VERSION_HEADER = 'A2A-Version';
  A2A_VERSION = '1.0';

  // --- Channel blackboard <-> A2A -------------------------------------------
  // The server seeds these keys before running the graph, so the nodes
  // know which conversation they are in:
  A2A_BB_MESSAGE_ID = 'A2A.MessageId';
  A2A_BB_TASK_ID = 'A2A.TaskId';
  A2A_BB_CONTEXT_ID = 'A2A.ContextId';
  // And reads these at the end, to respond with something richer than plain text:
  //   A2A.Artifacts -> JSON array of artifacts, emitted as-is. Allows
  //                    DataPart, FilePart (bytes or url) and several artifacts.
  //   A2A.Message   -> JSON Message object. If present, SendMessage responds
  //                    {"message": ...} instead of {"task": ...}, which is the
  //                    other arm of the SendMessageResponse oneof.
  A2A_BB_ARTIFACTS = 'A2A.Artifacts';
  A2A_BB_MESSAGE = 'A2A.Message';

// Converts either form ('TASK_STATE_INPUT_REQUIRED' or
// 'input-required') to the canonical lowercase. Published because the client uses it.
function A2ACanonicalState(const AValue: string): string;

procedure Register;

implementation

uses System.Hash, System.StrUtils, uMakerAi.Telemetry;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiA2AServer]);
end;

function A2ACanonicalState(const AValue: string): string;
var
  S: string;
begin
  S := Trim(AValue).ToLower;
  if S.StartsWith('task_state_') then
    S := S.Substring(Length('task_state_'));
  S := S.Replace('_', '-');
  Result := S;
end;

function NewGuidStr: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G).Replace('{', '').Replace('}', '').ToLower;
end;

{ EA2AServerError }

constructor EA2AServerError.CreateCode(ACode: Integer; const AMsg: string);
begin
  inherited Create(AMsg);
  FCode := ACode;
end;

{ TAiA2ATaskInfo }

constructor TAiA2ATaskInfo.Create;
begin
  inherited Create;
  History := TStringList.Create;
end;

destructor TAiA2ATaskInfo.Destroy;
begin
  History.Free;
  inherited;
end;

{ TAiA2AServer }

// -----------------------------------------------------------------------------
// Declared skills
// -----------------------------------------------------------------------------

function TAiA2ASkill.GetDisplayName: string;
begin
  if FId <> '' then
    Result := FId
  else
    Result := inherited GetDisplayName;
end;

procedure TAiA2ASkill.Assign(Source: TPersistent);
begin
  if Source is TAiA2ASkill then
  begin
    FId          := TAiA2ASkill(Source).Id;
    FTitle       := TAiA2ASkill(Source).Title;
    FDescription := TAiA2ASkill(Source).Description;
    FTags        := TAiA2ASkill(Source).Tags;
  end
  else
    inherited Assign(Source);
end;

constructor TAiA2ASkills.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TAiA2ASkill);
end;

function TAiA2ASkills.GetItem(AIndex: Integer): TAiA2ASkill;
begin
  Result := TAiA2ASkill(inherited Items[AIndex]);
end;

procedure TAiA2ASkills.SetItem(AIndex: Integer; const Value: TAiA2ASkill);
begin
  inherited Items[AIndex] := Value;
end;

function TAiA2ASkills.Add: TAiA2ASkill;
begin
  Result := TAiA2ASkill(inherited Add);
end;

function TAiA2ASkills.AddSkill(const AId, ATitle, ADescription: string;
  const ATags: string): TAiA2ASkill;
begin
  Result := Add;
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Description := ADescription;
  Result.Tags := ATags;
end;

procedure TAiA2AServer.SetSkills(const Value: TAiA2ASkills);
begin
  FSkills.Assign(Value);
end;

constructor TAiA2AServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPort := 8280;
  FAgentVersion := '1.0.0';
  FWaitTimeoutMs := 60000;
  FMaxConcurrentTasks := 4;
  FTaskTtlSeconds := 3600;
  FMaxTasks := 1000;
  FStateNaming := anProto;
  FWireEra := weV1;
  FCardCacheSeconds := 3600;
  FAcquireTimeoutMs := 10000;
  FEnableStreaming := True;
  FEnablePushNotifications := True;
  FSkills := TAiA2ASkills.Create(Self);
  FPushConfigs := TObjectList<TAiA2APushConfig>.Create(True);
  FPushLock := TCriticalSection.Create;
  FTasks := TObjectDictionary<string, TAiA2ATaskInfo>.Create([doOwnsValues]);
  FTasksLock := TCriticalSection.Create;
  FSlots := TObjectList<TAiA2AManagerSlot>.Create(True);
  FSlotsLock := TCriticalSection.Create;
  FHttpServer := TIdHTTPServer.Create(Self);
  FHttpServer.OnCommandGet := HttpCommand;
  FHttpServer.OnCommandOther := HttpCommand;
  FHttpServer.OnParseAuthentication := ParseAuthentication;
end;

destructor TAiA2AServer.Destroy;
begin
  Stop;
  FSkills.Free;
  FTasks.Free;
  FPushConfigs.Free;
  FPushLock.Free;
  FTasksLock.Free;
  ClearSlots;
  FSlots.Free;
  FSlotsLock.Free;
  inherited;
end;

procedure TAiA2AServer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FAgentManager) then
  begin
    FAgentManager := nil;
    ClearSlots;
  end;
end;

procedure TAiA2AServer.SetAgentManager(const Value: TAIAgentManager);
begin
  if FAgentManager <> Value then
  begin
    FAgentManager := Value;
    ClearSlots; // the pool is rebuilt with the new manager
    if Assigned(FAgentManager) then
      FAgentManager.FreeNotification(Self);
  end;
end;

procedure TAiA2AServer.SetActive(const Value: Boolean);
begin
  if Value = FActive then
    Exit;
  if csDesigning in ComponentState then
  begin
    FActive := Value;
    Exit;
  end;
  if Value then
    Start
  else
    Stop;
end;

procedure TAiA2AServer.Start;
begin
  if FActive then
    Exit;
  FHttpServer.DefaultPort := FPort;
  FHttpServer.Active := True;
  FActive := True;

  // There is no polling thread anymore: graph-finish detection goes through the
  // TAIAgentManager's own OnFinish event, which is deterministic and costs nothing.
  // RefreshLiveTasks is kept in case an integrator wants to force a review.
end;

procedure TAiA2AServer.Stop;
begin
  if not FActive then
    Exit;
  FHttpServer.Active := False;
  FActive := False;

end;

// ---------------------------------------------------------------------------
// Manager pool
// ---------------------------------------------------------------------------

procedure TAiA2AServer.ClearSlots;
var
  Slot: TAiA2AManagerSlot;
begin
  FSlotsLock.Enter;
  try
    for Slot in FSlots do
      if Slot.Owned and Assigned(Slot.Manager) then
      begin
        Slot.Manager.Free;
        Slot.Manager := nil;
      end;
    FSlots.Clear;
  finally
    FSlotsLock.Leave;
  end;
end;

function TAiA2AServer.AcquireSlot: TAiA2AManagerSlot;
var
  Slot: TAiA2AManagerSlot;
  NewMgr: TAIAgentManager;
  Esperado: Integer;
begin
  Result := nil;
  Esperado := 0;
  repeat
  FSlotsLock.Enter;
  try
    // The design-time manager is always slot 0.
    if (FSlots.Count = 0) and Assigned(FAgentManager) then
    begin
      Slot := TAiA2AManagerSlot.Create;
      Slot.Manager := FAgentManager;
      Slot.Owned := False;
      FSlots.Add(Slot);
    end;

    for Slot in FSlots do
      if (not Slot.InUse) and Assigned(Slot.Manager) and (not Slot.Manager.Busy) then
      begin
        Slot.InUse := True;
        Exit(Slot);
      end;

    // Grow the pool only if there is a factory: without it there is no way to have a
    // second equivalent graph.
    if Assigned(FOnAcquireManager) and (FSlots.Count < FMaxConcurrentTasks) then
    begin
      NewMgr := nil;
      FOnAcquireManager(Self, NewMgr);
      if Assigned(NewMgr) then
      begin
        Slot := TAiA2AManagerSlot.Create;
        Slot.Manager := NewMgr;
        Slot.Owned := True;
        Slot.InUse := True;
        FSlots.Add(Slot);
        Exit(Slot);
      end;
    end;
    finally
      FSlotsLock.Leave;
    end;
    if Result <> nil then
      Break;
    Sleep(25);
    Inc(Esperado, 25);
  until Esperado >= FAcquireTimeoutMs;

  // No free slot: instead of rejecting immediately, wait a bit. A
  // concurrency spike is normal and graphs are usually short-lived; returning
  // AgentBusy at the first turn converts a wait into an error for the client.
  if Result = nil then
    raise EA2AServerError.CreateCode(A2A_ERR_AGENT_BUSY,
      'Agent busy: no free agent slot (MaxConcurrentTasks=' + IntToStr(FMaxConcurrentTasks) + ')');
end;

procedure TAiA2AServer.ReleaseSlot(ASlot: TAiA2AManagerSlot);
begin
  if ASlot = nil then
    Exit;
  FSlotsLock.Enter;
  try
    ASlot.InUse := False;
  finally
    FSlotsLock.Leave;
  end;
end;

// ---------------------------------------------------------------------------
// Registry de tasks
// ---------------------------------------------------------------------------

function TAiA2AServer.NewTask(const AContextId: string): TAiA2ATaskInfo;
begin
  Result := TAiA2ATaskInfo.Create;
  Result.Id := NewGuidStr;
  if AContextId <> '' then
    Result.ContextId := AContextId
  else
    Result.ContextId := NewGuidStr;
  Result.State := A2A_STATE_SUBMITTED;
  Result.CreatedAt := Now;
  Result.UpdatedAt := Result.CreatedAt;
  FTasksLock.Enter;
  try
    FTasks.Add(Result.Id, Result);
  finally
    FTasksLock.Leave;
  end;
end;

// v1.0: SendMessage responds a SendMessageResponse, which is a oneof
// {task | message}. The Task therefore goes WRAPPED. GetTask and CancelTask do
// not carry a wrapper: in the proto they return the Task directly.
function TAiA2AServer.WrapSendMessageResult(ATask: TJSONObject): TJSONObject;
begin
  if FWireEra = weV03 then
    Exit(ATask);
  Result := TJSONObject.Create;
  Result.AddPair('task', ATask); // takes ownership
end;

// The other arm of the oneof: respond with a Message instead of a Task,
// for agents that answer at once without creating a task.
function TAiA2AServer.WrapSendMessageAsMessage(const AMessageJson: string; ATask: TJSONObject): TJSONObject;
var
  MsgObj: TJSONValue;
begin
  MsgObj := TJSONObject.ParseJSONValue(AMessageJson);
  if not(MsgObj is TJSONObject) then
  begin
    MsgObj.Free;
    Exit(WrapSendMessageResult(ATask)); // invalid JSON: the task is responded
  end;
  ATask.Free; // not used in this branch
  if FWireEra = weV03 then
    Exit(TJSONObject(MsgObj));
  Result := TJSONObject.Create;
  Result.AddPair('message', MsgObj);
end;

function TAiA2AServer.FindTask(const AId: string): TAiA2ATaskInfo;
begin
  if not FTasks.TryGetValue(AId, Result) then
    Result := nil;
end;

class function TAiA2AServer.IsTerminal(const AState: string): Boolean;
begin
  Result := (AState = A2A_STATE_COMPLETED) or (AState = A2A_STATE_FAILED) or (AState = A2A_STATE_CANCELED);
end;

class function TAiA2AServer.StatusToA2AState(AStatus: TAgentExecutionStatus): string;
begin
  case AStatus of
    esCompleted:
      Result := A2A_STATE_COMPLETED;
    esSuspended:
      Result := A2A_STATE_INPUT_REQUIRED; // the graph's human-in-the-loop
    esAborted:
      Result := A2A_STATE_CANCELED;
    esRunning:
      Result := A2A_STATE_WORKING;
  else
    Result := A2A_STATE_FAILED; // esError, esTimeout, esUnknown
  end;
end;

// Refreshes the task's state from its manager. Called with FTasksLock taken.
// It is the piece that keeps a task from lying: while the execution stays
// alive, the published state always comes from the graph, not from what was
// noted when answering the SendMessage.
procedure TAiA2AServer.RefreshTask(AInfo: TAiA2ATaskInfo; AIgnoreBusy: Boolean);
var
  Mgr: TAIAgentManager;
  St: TAgentExecutionStatus;
  Names: TArray<string>;
  Node: TAIAgentsNode;
begin
  if (AInfo = nil) or (AInfo.Slot = nil) then
    Exit;
  if IsTerminal(AInfo.State) then
    Exit;

  Mgr := AInfo.Slot.Manager;
  if not Assigned(Mgr) then
    Exit;

  // NOTE the engine's order: TAIAgentManager fires OnFinish and only
  // AFTER that sets FBusy to 0. A refresh launched from that event would see the
  // manager as busy and the final transition would be lost.
  if Mgr.Busy and not AIgnoreBusy then
  begin
    AInfo.State := A2A_STATE_WORKING;
    Exit;
  end;

  St := Mgr.Blackboard.GetStatus;
  // UpdatedAt only moves when the state REALLY changes. Stamping it on every
  // query had two bad effects: two snapshots of the same task came out with
  // different timestamps (and subscribed clients could not deduplicate them), and
  // the purge TTL, measured against this field, never expired.
  var LCambio := AInfo.State <> StatusToA2AState(St);
  if LCambio then
  begin
    AInfo.State := StatusToA2AState(St);
    AInfo.UpdatedAt := Now;
  end;

  if St = esSuspended then
  begin
    // We keep the slot: the suspended graph lives inside that manager and it is
    // the only one that can resume it.
    AInfo.ThreadID := Mgr.CurrentThreadID;
    Names := Mgr.GetSuspendedNodeNames;
    if Length(Names) > 0 then
    begin
      AInfo.SuspendNode := Names[0];
      Node := Mgr.FindNode(AInfo.SuspendNode);
      if Assigned(Node) then
      begin
        AInfo.SuspendReason := Node.SuspendReason;
        AInfo.SuspendContext := Node.SuspendContext;
      end;
    end;
    Exit;
  end;

  if St = esCompleted then
  begin
    if Assigned(Mgr.EndNode) then
      AInfo.OutputText := Mgr.EndNode.Output;
    // Optional structured response left by the graph
    AInfo.ArtifactsJson := Mgr.Blackboard.GetString(A2A_BB_ARTIFACTS);
    AInfo.MessageJson := Mgr.Blackboard.GetString(A2A_BB_MESSAGE);
    if AInfo.OutputText <> '' then
      AInfo.History.Add('agent'#9 + AInfo.OutputText);
  end
  else if AInfo.State = A2A_STATE_FAILED then
  begin
    if AInfo.ErrorText = '' then
      AInfo.ErrorText := Mgr.Blackboard.GetString('Execution.ErrorMessage');
    if AInfo.ErrorText = '' then
      AInfo.ErrorText := 'Graph execution failed';
  end;

  ReleaseSlot(AInfo.Slot);
  AInfo.Slot := nil;

  // Notify the registered webhooks. The POST is done in a separate TTask,
  // so this does not block even with FTasksLock taken.
  if LCambio then
    DeliverPushNotifications(AInfo);
end;

procedure TAiA2AServer.StartTask(AInfo: TAiA2ATaskInfo; const AInput: string);
var
  Slot: TAiA2AManagerSlot;
begin
  Slot := AcquireSlot; // raises AgentBusy if there is no room
  try
    // The server drives the execution: it needs Run to return immediately
    // so it can apply its own timeout and publish the task in working. In
    // synchronous mode Run would Wait(INFINITE) and would also raise an exception
    // instead of leaving the state in the blackboard.
    Slot.Manager.Asynchronous := True;
    // Hook into the graph's finish to be able to notify without polling.
    if not Slot.HookedFinish then
    begin
      Slot.PrevOnFinish := Slot.Manager.OnFinish; // chained, not overwritten
      Slot.Manager.OnFinish := OnGraphFinished;
      Slot.HookedFinish := True;
    end;
    FTasksLock.Enter;
    try
      AInfo.Slot := Slot;
      AInfo.State := A2A_STATE_WORKING;
      AInfo.UpdatedAt := Now;
      AInfo.History.Add('user'#9 + AInput);
    finally
      FTasksLock.Leave;
    end;
    // Overload with seeding: guarantees Compile + ResetExecutionState, without which
    // a manager reused from the pool would drag the previous task's
    // state (blackboard, node Outputs, link NoCycles). The seeding
    // runs AFTER the reset, so these values survive.
    var LMsgId := AInfo.MessageId;
    var LTaskId := AInfo.Id;
    var LCtxId := AInfo.ContextId;
    Slot.Manager.Run(AInput,
      procedure(B: TAIBlackboard)
      begin
        // The graph needs to know which conversation it is in: without this a node
        // cannot distinguish turns or correlate with external systems.
        B.SetString(A2A_BB_MESSAGE_ID, LMsgId);
        B.SetString(A2A_BB_TASK_ID, LTaskId);
        B.SetString(A2A_BB_CONTEXT_ID, LCtxId);
      end);
  except
    on E: Exception do
    begin
      FTasksLock.Enter;
      try
        AInfo.Slot := nil;
        AInfo.State := A2A_STATE_FAILED;
        AInfo.ErrorText := E.Message;
        AInfo.UpdatedAt := Now;
      finally
        FTasksLock.Leave;
      end;
      ReleaseSlot(Slot);
      // Not propagated: an execution failure is task state, not a transport
      // error (the spec distinguishes one from the other).
    end;
  end;
end;

procedure TAiA2AServer.ResumeTask(AInfo: TAiA2ATaskInfo; const AInput: string; const AMessageId: string);
var
  Slot: TAiA2AManagerSlot;
  ThreadID, NodeName: string;
begin
  FTasksLock.Enter;
  try
    Slot := AInfo.Slot;
    ThreadID := AInfo.ThreadID;
    NodeName := AInfo.SuspendNode;
  finally
    FTasksLock.Leave;
  end;

  if (Slot = nil) or (not Assigned(Slot.Manager)) or (NodeName = '') then
    raise EA2AServerError.CreateCode(A2A_ERR_UNSUPPORTED_OPERATION,
      'Task ' + AInfo.Id + ' cannot be resumed (no live execution)');

  try
    FTasksLock.Enter;
    try
      AInfo.State := A2A_STATE_WORKING;
      AInfo.SuspendReason := '';
      AInfo.SuspendContext := '';
      AInfo.UpdatedAt := Now;
      AInfo.History.Add('user'#9 + AInput);
    finally
      FTasksLock.Leave;
    end;
    // The resumed graph must see the NEW turn's metadata. Without this
    // a node that decides by messageId repeats the previous turn's
    // decision: the one that suspended would suspend again indefinitely.
    if Assigned(Slot.Manager) then
    begin
      Slot.Manager.Blackboard.SetString(A2A_BB_MESSAGE_ID, AMessageId);
      Slot.Manager.Blackboard.SetString(A2A_BB_TASK_ID, AInfo.Id);
      Slot.Manager.Blackboard.SetString(A2A_BB_CONTEXT_ID, AInfo.ContextId);
    end;
    Slot.Manager.ResumeThread(ThreadID, NodeName, AInput);
  except
    on E: Exception do
    begin
      FTasksLock.Enter;
      try
        AInfo.Slot := nil;
        AInfo.State := A2A_STATE_FAILED;
        AInfo.ErrorText := E.Message;
        AInfo.UpdatedAt := Now;
      finally
        FTasksLock.Leave;
      end;
      ReleaseSlot(Slot);
    end;
  end;
end;

// Bounded active wait. It does not hold FTasksLock: blocking the registry during
// the whole run would hang any concurrent GetTask.
procedure TAiA2AServer.WaitTask(AInfo: TAiA2ATaskInfo);
var
  Slot: TAiA2AManagerSlot;
  Waited: Integer;
begin
  FTasksLock.Enter;
  try
    Slot := AInfo.Slot;
  finally
    FTasksLock.Leave;
  end;
  if (Slot = nil) or (not Assigned(Slot.Manager)) then
    Exit;

  Waited := 0;
  while Slot.Manager.Busy and (Waited < FWaitTimeoutMs) do
  begin
    Sleep(15);
    Inc(Waited, 15);
  end;

  FTasksLock.Enter;
  try
    RefreshTask(AInfo);
  finally
    FTasksLock.Leave;
  end;
end;

// Discards expired finished tasks and caps the registry. Without this a long-lived
// server accumulates memory without a ceiling.
procedure TAiA2AServer.PurgeTasks;
var
  Pair: TPair<string, TAiA2ATaskInfo>;
  Doomed: TList<string>;
  Oldest: TAiA2ATaskInfo;
  OldestId: string;
  Limit: TDateTime;
begin
  Doomed := TList<string>.Create;
  try
    FTasksLock.Enter;
    try
      Limit := IncSecond(Now, -FTaskTtlSeconds);
      for Pair in FTasks do
        if IsTerminal(Pair.Value.State) and (Pair.Value.UpdatedAt < Limit) then
          Doomed.Add(Pair.Key);
      for var Id in Doomed do
        FTasks.Remove(Id);

      // Hard cap: if there is still excess, the oldest terminal falls.
      while (FMaxTasks > 0) and (FTasks.Count > FMaxTasks) do
      begin
        Oldest := nil;
        OldestId := '';
        for Pair in FTasks do
          if IsTerminal(Pair.Value.State) and ((Oldest = nil) or (Pair.Value.UpdatedAt < Oldest.UpdatedAt)) then
          begin
            Oldest := Pair.Value;
            OldestId := Pair.Key;
          end;
        if OldestId = '' then
          Break; // all alive: nothing to discard
        FTasks.Remove(OldestId);
      end;
    finally
      FTasksLock.Leave;
    end;
  finally
    Doomed.Free;
  end;
end;

// ---------------------------------------------------------------------------
// JSON serialization
// ---------------------------------------------------------------------------

function TAiA2AServer.EmitState(const ACanonical: string): string;
begin
  if FStateNaming = anLower then
    Result := ACanonical
  else
    Result := 'TASK_STATE_' + ACanonical.Replace('-', '_').ToUpper;
end;

function TAiA2AServer.EmitRole(const ACanonical: string): string;
begin
  if FStateNaming = anLower then
    Result := ACanonical
  else
    Result := 'ROLE_' + ACanonical.ToUpper;
end;

function TAiA2AServer.BuildAgentCard(const ABaseUrl: string): TJSONObject;
var
  Caps, Skill, Schemes, Bearer: TJSONObject;
  Skills, Modes: TJSONArray;
  LName, LDesc: string;
begin
  LName := FAgentName;
  if LName = '' then
    LName := Name; // component name as fallback
  LDesc := FAgentDescription;
  if (LDesc = '') and Assigned(FAgentManager) then
    LDesc := FAgentManager.Description;

  Result := TJSONObject.Create;
  Result.AddPair('name', LName);
  Result.AddPair('description', LDesc);
  Result.AddPair('version', FAgentVersion);

  if FWireEra = weV1 then
  begin
    // v1.0: the root has NO url, protocolVersion or preferredTransport.
    // All of that lives in supportedInterfaces[], which is what a v1.0 client
    // queries to know which URL to talk to. Without this, it does not know where to call.
    var Ifaces := TJSONArray.Create;
    var Iface := TJSONObject.Create;
    Iface.AddPair('url', ABaseUrl);
    Iface.AddPair('protocolBinding', 'JSONRPC'); // it is a string, not an enum
    Iface.AddPair('protocolVersion', '1.0.0');
    Ifaces.AddElement(Iface);
    Result.AddPair('supportedInterfaces', Ifaces);
  end
  else
  begin
    Result.AddPair('protocolVersion', '1.0.0');
    Result.AddPair('url', ABaseUrl);
    Result.AddPair('preferredTransport', 'JSONRPC');
  end;

  Caps := TJSONObject.Create;
  Caps.AddPair('streaming', TJSONBool.Create(FEnableStreaming));
  Caps.AddPair('pushNotifications', TJSONBool.Create(FEnablePushNotifications));
  Caps.AddPair('extendedAgentCard', TJSONBool.Create(FPublishExtendedCard));
  // stateTransitionHistory does not exist in v1.0's AgentCapabilities
  if FWireEra = weV03 then
    Caps.AddPair('stateTransitionHistory', TJSONBool.Create(False));
  Result.AddPair('capabilities', Caps);

  Modes := TJSONArray.Create;
  Modes.Add('text/plain');
  Result.AddPair('defaultInputModes', Modes);
  Modes := TJSONArray.Create;
  Modes.Add('text/plain');
  Result.AddPair('defaultOutputModes', Modes);

  if FApiKey <> '' then
  begin
    Bearer := TJSONObject.Create;
    Bearer.AddPair('type', 'http');
    Bearer.AddPair('scheme', 'bearer');
    Schemes := TJSONObject.Create;
    Schemes.AddPair('bearer', Bearer);
    Result.AddPair('securitySchemes', Schemes);
    var SecArr := TJSONArray.Create;
    var SecItem := TJSONObject.Create;
    if FWireEra = weV1 then
    begin
      // v1.0: SecurityRequirement has a 'schemes' field
      var SchemesMap := TJSONObject.Create;
      SchemesMap.AddPair('bearer', TJSONArray.Create);
      SecItem.AddPair('schemes', SchemesMap);
    end
    else
      SecItem.AddPair('bearer', TJSONArray.Create);
    SecArr.AddElement(SecItem);
    if FWireEra = weV1 then
      Result.AddPair('securityRequirements', SecArr) // renamed in v1.0
    else
      Result.AddPair('security', SecArr);
  end;

  Skills := TJSONArray.Create;

  // 1. The developer-declared skills take precedence.
  for var I := 0 to FSkills.Count - 1 do
  begin
    var LSk := FSkills[I];
    if Trim(LSk.Id) = '' then
      Continue; // without an id it is not a valid skill
    Skill := TJSONObject.Create;
    Skill.AddPair('id', LSk.Id);
    if LSk.Title <> '' then
      Skill.AddPair('name', LSk.Title)
    else
      Skill.AddPair('name', LSk.Id);
    Skill.AddPair('description', LSk.Description);
    var LTags := TJSONArray.Create;
    for var LTag in SplitString(LSk.Tags, ',') do
      if Trim(LTag) <> '' then
        LTags.Add(Trim(LTag));
    Skill.AddPair('tags', LTags);
    Skills.AddElement(Skill);
  end;

  // 2. Nodes with description, only if requested. Those without it are omitted:
  //    publishing 'Node1' without a description does not help choose an agent.
  if FPublishNodesAsSkills and Assigned(FAgentManager) then
    for var LNode in FAgentManager.GetNodes do
    begin
      if not Assigned(LNode) or not Assigned(LNode.Tool) then
        Continue;
      if Trim(LNode.Tool.Description) = '' then
        Continue;
      Skill := TJSONObject.Create;
      Skill.AddPair('id', 'node-' + LNode.Name);
      Skill.AddPair('name', LNode.Name);
      Skill.AddPair('description', LNode.Tool.Description);
      Skill.AddPair('tags', TJSONArray.Create);
      Skills.AddElement(Skill);
    end;

  // 3. If none remained, the default skill: run the whole graph.
  //    The Agent Card must NEVER go out without skills.
  if Skills.Count = 0 then
  begin
    Skill := TJSONObject.Create;
    Skill.AddPair('id', 'run-graph');
    Skill.AddPair('name', LName);
    Skill.AddPair('description', LDesc);
    Skill.AddPair('tags', TJSONArray.Create);
    Skills.AddElement(Skill);
  end;

  Result.AddPair('skills', Skills);

  if Assigned(FOnCustomizeCard) then
    FOnCustomizeCard(Self, Result);
end;

class function TAiA2AServer.ExtractTextFromParts(AMessage: TJSONObject): string;
var
  Parts: TJSONArray;
  V, DataVal: TJSONValue;
  PartObj: TJSONObject;
  SB: TStringBuilder;
  S: string;

  procedure Append(const AText: string);
  begin
    if AText = '' then
      Exit;
    if SB.Length > 0 then
      SB.Append(sLineBreak);
    SB.Append(AText);
  end;

begin
  Result := '';
  if not Assigned(AMessage) then
    Exit;
  if not AMessage.TryGetValue<TJSONArray>('parts', Parts) then
    Exit;
  SB := TStringBuilder.Create;
  try
    for V in Parts do
      if V is TJSONObject then
      begin
        PartObj := TJSONObject(V);
        // spec 1.0: {"text": "..."}; we also tolerate the 0.x style
        // {"type":"text","text":"..."}
        if PartObj.TryGetValue<string>('text', S) then
          Append(S)
        // DataPart: the structured payload travels as raw JSON, so an
        // orchestration can pass objects and not only prose.
        else if PartObj.TryGetValue<TJSONValue>('data', DataVal) then
          Append(DataVal.ToJSON);
      end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAiA2AServer.BuildTaskJson(AInfo: TAiA2ATaskInfo; AHistoryLength: Integer): TJSONObject;
var
  StatusObj, Artifact, PartObj, MsgObj: TJSONObject;
  Artifacts, PartsArr, HistArr: TJSONArray;
  StatusText: string;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AInfo.Id);
  Result.AddPair('contextId', AInfo.ContextId);

  StatusObj := TJSONObject.Create;
  StatusObj.AddPair('state', EmitState(AInfo.State));
  StatusObj.AddPair('timestamp', DateToISO8601(TTimeZone.Local.ToUniversalTime(AInfo.UpdatedAt), True));

  // In input-required the status message carries the question to the human; in
  // failed it carries the error. It is what the client shows or forwards.
  StatusText := '';
  if AInfo.State = A2A_STATE_INPUT_REQUIRED then
  begin
    StatusText := AInfo.SuspendReason;
    if AInfo.SuspendContext <> '' then
      StatusText := Trim(StatusText + sLineBreak + AInfo.SuspendContext);
    if StatusText = '' then
      StatusText := 'The agent requires additional input to continue';
  end
  else if AInfo.ErrorText <> '' then
    StatusText := AInfo.ErrorText;

  if StatusText <> '' then
  begin
    MsgObj := TJSONObject.Create;
    // Deterministic on purpose: two snapshots of the SAME task must come out
    // identical. With a new GUID per call, two clients subscribed to the same
    // task received different events and could not deduplicate.
    MsgObj.AddPair('messageId', AInfo.Id + '-status');
    MsgObj.AddPair('role', EmitRole('agent'));
    MsgObj.AddPair('taskId', AInfo.Id);
    MsgObj.AddPair('contextId', AInfo.ContextId);
    var MParts := TJSONArray.Create;
    var MPart := TJSONObject.Create;
    MPart.AddPair('text', StatusText);
    MParts.AddElement(MPart);
    MsgObj.AddPair('parts', MParts);
    StatusObj.AddPair('message', MsgObj);
  end;
  Result.AddPair('status', StatusObj);

  // If the graph left structured artifacts, they take precedence: they allow DataPart,
  // FilePart (bytes or url) and several artifacts, which plain text does not.
  Artifacts := nil;
  if (AInfo.State = A2A_STATE_COMPLETED) and (Trim(AInfo.ArtifactsJson) <> '') then
    Artifacts := TJSONArray(TJSONObject.ParseJSONValue(AInfo.ArtifactsJson));
  if not(Artifacts is TJSONArray) then
  begin
    Artifacts.Free;
    Artifacts := nil;
  end;

  if Artifacts = nil then
  begin
  Artifacts := TJSONArray.Create;
  if (AInfo.State = A2A_STATE_COMPLETED) and (AInfo.OutputText <> '') then
  begin
    Artifact := TJSONObject.Create;
    Artifact.AddPair('artifactId', AInfo.Id + '-result');
    Artifact.AddPair('name', 'result');
    PartsArr := TJSONArray.Create;
    PartObj := TJSONObject.Create;
    PartObj.AddPair('text', AInfo.OutputText);
    PartsArr.AddElement(PartObj);
    Artifact.AddPair('parts', PartsArr);
    Artifacts.AddElement(Artifact);
  end;
  end;
  Result.AddPair('artifacts', Artifacts);

  HistArr := TJSONArray.Create;
  // historyLength trims from the end: 0 = no history, N = the last N.
  var LDesde := 0;
  if AHistoryLength = 0 then
    LDesde := AInfo.History.Count
  else if (AHistoryLength > 0) and (AInfo.History.Count > AHistoryLength) then
    LDesde := AInfo.History.Count - AHistoryLength;
  for I := LDesde to AInfo.History.Count - 1 do
  begin
    var Line := AInfo.History[I];
    var Sep := Pos(#9, Line);
    if Sep <= 0 then
      Continue;
    MsgObj := TJSONObject.Create;
    MsgObj.AddPair('messageId', AInfo.Id + '-h' + IntToStr(I));
    MsgObj.AddPair('role', EmitRole(Copy(Line, 1, Sep - 1)));
    MsgObj.AddPair('taskId', AInfo.Id);
    MsgObj.AddPair('contextId', AInfo.ContextId);
    var HParts := TJSONArray.Create;
    var HPart := TJSONObject.Create;
    HPart.AddPair('text', Copy(Line, Sep + 1, MaxInt));
    HParts.AddElement(HPart);
    MsgObj.AddPair('parts', HParts);
    HistArr.AddElement(MsgObj);
  end;
  Result.AddPair('history', HistArr);
end;

// ---------------------------------------------------------------------------
// JSON-RPC methods
// ---------------------------------------------------------------------------

function TAiA2AServer.DoSendMessage(AParams: TJSONObject): TJSONObject;
var
  MsgObj, ConfigObj, PushObj, PushParams: TJSONObject;
  InputText, TaskId, ContextId, MessageId: string;
  Info: TAiA2ATaskInfo;
  Blocking: Boolean;
  LHistLen: Integer;
begin
  if not(Assigned(FAgentManager) or Assigned(FOnAcquireManager)) then
    raise EA2AServerError.CreateCode(-32603, 'No AgentManager assigned to this A2A server');

  MsgObj := nil;
  if Assigned(AParams) then
    AParams.TryGetValue<TJSONObject>('message', MsgObj);
  // 'message' is mandatory: without it the request is malformed and must be
  // rejected, not turned into a task with empty text (CORE-ERR-002).
  if not Assigned(MsgObj) then
    raise EA2AServerError.CreateCode(A2A_ERR_INVALID_PARAMS, 'SendMessage requires a "message" parameter');
  InputText := ExtractTextFromParts(MsgObj);

  // taskId/contextId travel in the Message; we tolerate seeing them loose in
  // params too, which is how several 0.x-era clients send them.
  TaskId := '';
  ContextId := '';
  MessageId := '';
  if Assigned(MsgObj) then
  begin
    TaskId := MsgObj.GetValue<string>('taskId', '');
    MessageId := MsgObj.GetValue<string>('messageId', '');
    ContextId := MsgObj.GetValue<string>('contextId', '');
  end;
  if Assigned(AParams) then
  begin
    if TaskId = '' then
      TaskId := AParams.GetValue<string>('taskId', '');
    if ContextId = '' then
      ContextId := AParams.GetValue<string>('contextId', '');
  end;

  Blocking := True;
  ConfigObj := nil;
  LHistLen := -1;
  if Assigned(AParams) and AParams.TryGetValue<TJSONObject>('configuration', ConfigObj) then
  begin
    Blocking := ConfigObj.GetValue<Boolean>('blocking', True);
    LHistLen := ConfigObj.GetValue<Integer>('historyLength', -1);
    if LHistLen < 0 then
      LHistLen := ConfigObj.GetValue<Integer>('history_length', -1);
  end;

  PurgeTasks;

  if TaskId <> '' then
  begin
    FTasksLock.Enter;
    try
      Info := FindTask(TaskId);
      if Assigned(Info) then
        RefreshTask(Info);
    finally
      FTasksLock.Leave;
    end;
    if Info = nil then
      raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_FOUND, 'Task not found: ' + TaskId);

    // If the caller sends a contextId, it must be the task's. A crossed
    // taskId/contextId pair is an error, not something to ignore (CORE-MULTI-006).
    if (ContextId <> '') and (Info.ContextId <> ContextId) then
      raise EA2AServerError.CreateCode(A2A_ERR_INVALID_PARAMS,
        Format('contextId "%s" does not belong to task "%s"', [ContextId, TaskId]));

    if Info.State = A2A_STATE_INPUT_REQUIRED then
      ResumeTask(Info, InputText, MessageId)
    else if IsTerminal(Info.State) then
      // The spec requires it this way (CORE-SEND-002): continuing an already-terminal task is
      // UnsupportedOperation. Before, the task was returned as-is, for seeming
      // more useful to the caller; the TCK marks it as a MUST violation.
      raise EA2AServerError.CreateCode(A2A_ERR_UNSUPPORTED_OPERATION,
        Format('Task "%s" is in a terminal state (%s) and cannot be continued', [TaskId, Info.State]));
  end
  else
  begin
    Info := NewTask(ContextId);
    Info.MessageId := MessageId;

    // The webhook can come in the request itself, not only through the CRUD:
    // configuration.taskPushNotificationConfig registers the config for this
    // task. It is the route clients use to avoid making two calls.
    if Assigned(ConfigObj) and ConfigObj.TryGetValue<TJSONObject>('taskPushNotificationConfig', PushObj) then
    begin
      PushParams := TJSONObject.Create;
      try
        PushParams.AddPair('taskId', Info.Id);
        PushParams.AddPair('config', TJSONObject(PushObj.Clone));
        DoCreatePushConfig(PushParams).Free;
      finally
        PushParams.Free;
      end;
    end;

    StartTask(Info, InputText);
  end;

  // If TaskId pointed to a task already in working and there was no resume, there is
  // nothing new to launch: that same task is waited on / refreshed.
  if Blocking then
    WaitTask(Info)
  else
  begin
    FTasksLock.Enter;
    try
      RefreshTask(Info);
    finally
      FTasksLock.Leave;
    end;
  end;

  FTasksLock.Enter;
  try
    FLastMessageJson := Info.MessageJson;
    Result := BuildTaskJson(Info, LHistLen);
  finally
    FTasksLock.Leave;
  end;
end;

function TAiA2AServer.DoGetTask(AParams: TJSONObject): TJSONObject;
var
  Id: string;
  Info: TAiA2ATaskInfo;
  LHistLen: Integer;
begin
  Id := '';
  LHistLen := -1;
  if Assigned(AParams) then
  begin
    Id := AParams.GetValue<string>('id', '');
    if Id = '' then
      Id := AParams.GetValue<string>('taskId', '');
    LHistLen := AParams.GetValue<Integer>('historyLength', -1);
    if LHistLen < 0 then
      LHistLen := AParams.GetValue<Integer>('history_length', -1);
  end;

  FTasksLock.Enter;
  try
    Info := FindTask(Id);
    if not Assigned(Info) then
      raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_FOUND, 'Task not found: ' + Id);
    RefreshTask(Info); // the published state always comes from the live graph
    Result := BuildTaskJson(Info, LHistLen);
  finally
    FTasksLock.Leave;
  end;
end;

// ListTasks (v1.0). Filters by contextId and/or state, with simple paging by
// pageSize. ListTasksResponse = {tasks, nextPageToken, pageSize, totalSize}.
function TAiA2AServer.DoListTasks(AParams: TJSONObject): TJSONObject;
var
  Pair: TPair<string, TAiA2ATaskInfo>;
  Arr: TJSONArray;
  FiltroCtx, FiltroEstado: string;
  PageSize, Total, Emitidos: Integer;
begin
  FiltroCtx := '';
  FiltroEstado := '';
  PageSize := 0;
  if Assigned(AParams) then
  begin
    FiltroCtx := AParams.GetValue<string>('contextId', '');
    // The filter arrives as a TaskState literal; it is normalized so it can be
    // compared with the internal state regardless of the caller's era.
    FiltroEstado := A2ACanonicalState(AParams.GetValue<string>('status', ''));
    PageSize := AParams.GetValue<Integer>('pageSize', 0);
  end;

  Arr := TJSONArray.Create;
  Total := 0;
  Emitidos := 0;
  FTasksLock.Enter;
  try
    for Pair in FTasks do
    begin
      RefreshTask(Pair.Value); // the listing must not lie either
      if (FiltroCtx <> '') and (Pair.Value.ContextId <> FiltroCtx) then
        Continue;
      if (FiltroEstado <> '') and (Pair.Value.State <> FiltroEstado) then
        Continue;
      Inc(Total);
      if (PageSize > 0) and (Emitidos >= PageSize) then
        Continue; // counted in totalSize but not emitted
      Arr.AddElement(BuildTaskJson(Pair.Value));
      Inc(Emitidos);
    end;
  finally
    FTasksLock.Leave;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('tasks', Arr);
  Result.AddPair('totalSize', TJSONNumber.Create(Total));
  if PageSize > 0 then
    Result.AddPair('pageSize', TJSONNumber.Create(PageSize));
end;

{ TAiA2APushConfig }

function TAiA2APushConfig.ToJson: TJSONObject;
var
  Auth: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', Id);
  Result.AddPair('taskId', TaskId);
  Result.AddPair('url', Url);
  if Token <> '' then
    Result.AddPair('token', Token);
  if (AuthScheme <> '') or (AuthCredentials <> '') then
  begin
    Auth := TJSONObject.Create;
    Auth.AddPair('scheme', AuthScheme);
    Auth.AddPair('credentials', AuthCredentials);
    Result.AddPair('authentication', Auth);
  end;
end;

// -----------------------------------------------------------------------------
// Push notifications
// -----------------------------------------------------------------------------
// The v1.0 form is FLAT: TaskPushNotificationConfig = {tenant, id, taskId,
// url, token, authentication}. There is no nested pushNotificationConfig object
// as in the 0.x era. The nested {taskId, config:{...}} is accepted anyway
// because that is what several clients send.

// Reads a key tolerating both conventions. The JSON-RPC binding uses
// camelCase, but several clients -the TCK itself among them- send the
// proto names in snake_case.
function ParamStr2(AParams: TJSONObject; const ACamel, ASnake: string): string;
begin
  Result := '';
  if not Assigned(AParams) then
    Exit;
  Result := AParams.GetValue<string>(ACamel, '');
  if Result = '' then
    Result := AParams.GetValue<string>(ASnake, '');
end;
function TAiA2AServer.DoCreatePushConfig(AParams: TJSONObject): TJSONObject;
var
  Cfg: TAiA2APushConfig;
  Src, AuthObj: TJSONObject;
  TaskId: string;
begin
  if not FEnablePushNotifications then
    raise EA2AServerError.CreateCode(A2A_ERR_PUSH_NOT_SUPPORTED, 'Push notifications are not supported');
  if not Assigned(AParams) then
    raise EA2AServerError.CreateCode(A2A_ERR_INVALID_PARAMS, 'Missing params');

  TaskId := ParamStr2(AParams, 'taskId', 'task_id');
  // The body can come nested in 'config' or flat in the params themselves
  if not AParams.TryGetValue<TJSONObject>('config', Src) then
    Src := AParams;
  if TaskId = '' then
    TaskId := ParamStr2(Src, 'taskId', 'task_id');
  if TaskId = '' then
    raise EA2AServerError.CreateCode(A2A_ERR_INVALID_PARAMS, 'taskId is required');

  Cfg := TAiA2APushConfig.Create;
  Cfg.TaskId := TaskId;
  Cfg.Id := Src.GetValue<string>('id', '');
  if Cfg.Id = '' then
    Cfg.Id := NewGuidStr;
  Cfg.Url := Src.GetValue<string>('url', '');
  Cfg.Token := Src.GetValue<string>('token', '');
  if Src.TryGetValue<TJSONObject>('authentication', AuthObj) then
  begin
    Cfg.AuthScheme := AuthObj.GetValue<string>('scheme', '');
    Cfg.AuthCredentials := AuthObj.GetValue<string>('credentials', '');
  end;

  FPushLock.Enter;
  try
    // Re-registering the same id replaces: creating duplicates would make the
    // webhook receive the same notification twice.
    for var I := FPushConfigs.Count - 1 downto 0 do
      if (FPushConfigs[I].TaskId = Cfg.TaskId) and (FPushConfigs[I].Id = Cfg.Id) then
        FPushConfigs.Delete(I);
    FPushConfigs.Add(Cfg);
    Result := Cfg.ToJson;
  finally
    FPushLock.Leave;
  end;
end;

function TAiA2AServer.DoGetPushConfig(AParams: TJSONObject): TJSONObject;
var
  TaskId, Id: string;
begin
  if not FEnablePushNotifications then
    raise EA2AServerError.CreateCode(A2A_ERR_PUSH_NOT_SUPPORTED, 'Push notifications are not supported');
  TaskId := '';
  Id := '';
  TaskId := ParamStr2(AParams, 'taskId', 'task_id');
  if Assigned(AParams) then
    Id := AParams.GetValue<string>('id', '');

  FPushLock.Enter;
  try
    for var Cfg in FPushConfigs do
      if (Cfg.TaskId = TaskId) and (Cfg.Id = Id) then
        Exit(Cfg.ToJson);
  finally
    FPushLock.Leave;
  end;
  raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_FOUND,
    Format('No push notification config "%s" for task "%s"', [Id, TaskId]));
end;

function TAiA2AServer.DoListPushConfigs(AParams: TJSONObject): TJSONObject;
var
  TaskId: string;
  Arr: TJSONArray;
begin
  if not FEnablePushNotifications then
    raise EA2AServerError.CreateCode(A2A_ERR_PUSH_NOT_SUPPORTED, 'Push notifications are not supported');
  TaskId := '';
  TaskId := ParamStr2(AParams, 'taskId', 'task_id');

  Arr := TJSONArray.Create;
  FPushLock.Enter;
  try
    for var Cfg in FPushConfigs do
      if (TaskId = '') or (Cfg.TaskId = TaskId) then
        Arr.AddElement(Cfg.ToJson);
  finally
    FPushLock.Leave;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('configs', Arr);
end;

function TAiA2AServer.DoDeletePushConfig(AParams: TJSONObject): TJSONObject;
var
  TaskId, Id: string;
begin
  if not FEnablePushNotifications then
    raise EA2AServerError.CreateCode(A2A_ERR_PUSH_NOT_SUPPORTED, 'Push notifications are not supported');
  TaskId := '';
  Id := '';
  TaskId := ParamStr2(AParams, 'taskId', 'task_id');
  if Assigned(AParams) then
    Id := AParams.GetValue<string>('id', '');

  FPushLock.Enter;
  try
    for var I := FPushConfigs.Count - 1 downto 0 do
      if (FPushConfigs[I].TaskId = TaskId) and (FPushConfigs[I].Id = Id) then
        FPushConfigs.Delete(I);
  finally
    FPushLock.Leave;
  end;
  // Delete is IDEMPOTENT: deleting something that is no longer there is not an error.
  Result := TJSONObject.Create;
end;

// Delivers the task's state to the registered webhooks. Called when a state
// change is detected. The POST goes in a separate TTask: blocking here would stop
// the task's refresh and, with the lock taken, the whole registry.
// Refreshes the tasks with a live execution. An active watcher is needed: the
// push delivery fires when a state change is detected, and RefreshTask only
// ran when a client asked. If nobody called GetTask, the task
// finished and the webhook never found out.
// A graph just finished. Its task is located and refreshed, which
// fires the push delivery if the state changed. Before, this depended on a thread
// polling every 100 ms: it worked only if someone queried the task, so
// with blocking=false the webhook never found out.
procedure TAiA2AServer.OnGraphFinished(Sender: TObject; const Input, Output: string;
  Status: TAgentExecutionStatus; E: Exception);
var
  Pair: TPair<string, TAiA2ATaskInfo>;
  Afectado: TAiA2ATaskInfo;
  Previo: TAIAgentsOnFinish;
begin
  Afectado := nil;
  Previo := nil;
  FTasksLock.Enter;
  try
    for Pair in FTasks do
      if Assigned(Pair.Value.Slot) and (Pair.Value.Slot.Manager = Sender) then
      begin
        Afectado := Pair.Value;
        Previo := Pair.Value.Slot.PrevOnFinish;
        Break;
      end;
    if Assigned(Afectado) then
      // AIgnoreBusy: the engine fires OnFinish BEFORE setting FBusy to 0,
      // so here the manager still declares itself busy. Without this,
      // RefreshTask took the 'still working' branch and never detected
      // the step to completed: the webhook never found out.
      RefreshTask(Afectado, True);
  finally
    FTasksLock.Leave;
  end;

  // Chain the handler the integrator might have set: appropriating
  // the event without returning it would break their code.
  if Assigned(Previo) then
    Previo(Sender, Input, Output, Status, E);
end;
procedure TAiA2AServer.RefreshLiveTasks;
var
  Pair: TPair<string, TAiA2ATaskInfo>;
  Vivos: TArray<TAiA2ATaskInfo>;
  Lista: TList<TAiA2ATaskInfo>;
begin
  Lista := TList<TAiA2ATaskInfo>.Create;
  try
    FTasksLock.Enter;
    try
      for Pair in FTasks do
        if Assigned(Pair.Value.Slot) and not IsTerminal(Pair.Value.State) then
          Lista.Add(Pair.Value);
      Vivos := Lista.ToArray;
      for var Info in Vivos do
        RefreshTask(Info); // fires DeliverPushNotifications if it changed
    finally
      FTasksLock.Leave;
    end;
  finally
    Lista.Free;
  end;
end;
procedure TAiA2AServer.DeliverPushNotifications(AInfo: TAiA2ATaskInfo);
var
  Destinos: TArray<TAiA2APushConfig>;
  Payload: string;
  Lista: TList<TAiA2APushConfig>;
begin
  if not FEnablePushNotifications then
    Exit;

  Lista := TList<TAiA2APushConfig>.Create;
  try
    FPushLock.Enter;
    try
      for var Cfg in FPushConfigs do
        if Cfg.TaskId = AInfo.Id then
          Lista.Add(Cfg);
      Destinos := Lista.ToArray;
    finally
      FPushLock.Leave;
    end;
  finally
    Lista.Free;
  end;
  if Length(Destinos) = 0 then
    Exit;

  // The payload is NOT the bare Task but a StreamResponse, the same oneof
  // the streaming uses: {task | message | statusUpdate | artifactUpdate}.
  // Here the full snapshot is sent, so it goes through the 'task' arm.
  var Envuelto := TJSONObject.Create;
  try
    Envuelto.AddPair('task', BuildTaskJson(AInfo));
    Payload := Envuelto.ToJSON;
  finally
    Envuelto.Free;
  end;

  for var Cfg in Destinos do
  begin
    var LUrl := Cfg.Url;
    var LScheme := Cfg.AuthScheme;
    var LCreds := Cfg.AuthCredentials;
    var LToken := Cfg.Token;
    if LUrl = '' then
      Continue;
    TTask.Run(
      procedure
      var
        Http: THTTPClient;
        Body: TStringStream;
        Headers: TNetHeaders;
      begin
        Http := THTTPClient.Create;
        Body := TStringStream.Create(Payload, TEncoding.UTF8);
        try
          Http.ConnectionTimeout := 5000;
          Http.ResponseTimeout := 5000;
          Http.ContentType := 'application/json';
          SetLength(Headers, 0);
          if LScheme <> '' then
            Headers := Headers + [TNameValuePair.Create('Authorization', LScheme + ' ' + LCreds)];
          if LToken <> '' then
            Headers := Headers + [TNameValuePair.Create('X-A2A-Notification-Token', LToken)];
          try
            Http.Post(LUrl, Body, nil, Headers);
          except
            // A fallen webhook cannot take down the agent's execution.
          end;
        finally
          Body.Free;
          Http.Free;
        end;
      end);
  end;
end;
function TAiA2AServer.DoCancelTask(AParams: TJSONObject): TJSONObject;
var
  Id: string;
  Info: TAiA2ATaskInfo;
  Slot: TAiA2AManagerSlot;
begin
  Id := '';
  if Assigned(AParams) then
  begin
    Id := AParams.GetValue<string>('id', '');
    if Id = '' then
      Id := AParams.GetValue<string>('taskId', '');
  end;

  FTasksLock.Enter;
  try
    Info := FindTask(Id);
    if not Assigned(Info) then
      raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_FOUND, 'Task not found: ' + Id);
    RefreshTask(Info);
    if IsTerminal(Info.State) then
      raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_CANCELABLE,
        'Task ' + Id + ' is already in a terminal state (' + Info.State + ')');
    Slot := Info.Slot;
  finally
    FTasksLock.Leave;
  end;

  // Aborts ONLY this task's manager. With a pool, aborting the design-time
  // manager would cancel another caller's task.
  if Assigned(Slot) and Assigned(Slot.Manager) then
    Slot.Manager.Abort;

  FTasksLock.Enter;
  try
    Info.State := A2A_STATE_CANCELED;
    Info.UpdatedAt := Now;
    if Assigned(Info.Slot) then
    begin
      ReleaseSlot(Info.Slot);
      Info.Slot := nil;
    end;
    Result := BuildTaskJson(Info);
  finally
    FTasksLock.Leave;
  end;
end;

// ---------------------------------------------------------------------------
// JSON-RPC / HTTP layer
// ---------------------------------------------------------------------------

// Canonical ErrorInfo reason for each A2A code: the error name in
// UPPER_SNAKE_CASE and without the "Error" suffix. The standard JSON-RPC errors
// (-32600 and below) carry no reason.
function A2AReasonForCode(ACode: Integer): string;
begin
  case ACode of
    A2A_ERR_TASK_NOT_FOUND: Result := 'TASK_NOT_FOUND';
    A2A_ERR_TASK_NOT_CANCELABLE: Result := 'TASK_NOT_CANCELABLE';
    A2A_ERR_PUSH_NOT_SUPPORTED: Result := 'PUSH_NOTIFICATION_NOT_SUPPORTED';
    A2A_ERR_UNSUPPORTED_OPERATION: Result := 'UNSUPPORTED_OPERATION';
    A2A_ERR_CONTENT_TYPE_NOT_SUPPORTED: Result := 'CONTENT_TYPE_NOT_SUPPORTED';
    A2A_ERR_INVALID_AGENT_RESPONSE: Result := 'INVALID_AGENT_RESPONSE';
    A2A_ERR_EXTENDED_CARD_NOT_CONFIGURED: Result := 'EXTENDED_AGENT_CARD_NOT_CONFIGURED';
    A2A_ERR_EXTENSION_SUPPORT_REQUIRED: Result := 'EXTENSION_SUPPORT_REQUIRED';
    A2A_ERR_VERSION_NOT_SUPPORTED: Result := 'VERSION_NOT_SUPPORTED';
  else
    Result := ''; // standard JSON-RPC error: no ErrorInfo
  end;
end;

function TAiA2AServer.RpcError(AId: TJSONValue; ACode: Integer; const AMsg: string): string;
var
  Resp, Err, Info: TJSONObject;
  Data: TJSONArray;
  Reason: string;
begin
  Resp := TJSONObject.Create;
  try
    Resp.AddPair('jsonrpc', '2.0');
    Err := TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err.AddPair('message', AMsg);

    // The spec requires ErrorInfo inside an array in error.data for the
    // A2A-specific errors (section 9.5).
    Reason := A2AReasonForCode(ACode);
    if Reason <> '' then
    begin
      Info := TJSONObject.Create;
      Info.AddPair('@type', A2A_ERRORINFO_TYPE);
      Info.AddPair('domain', A2A_ERROR_DOMAIN);
      Info.AddPair('reason', Reason);
      Data := TJSONArray.Create;
      Data.AddElement(Info);
      Err.AddPair('data', Data);
    end;

    Resp.AddPair('error', Err);
    if Assigned(AId) then
      Resp.AddPair('id', TJSONValue(AId.Clone))
    else
      Resp.AddPair('id', TJSONNull.Create);
    Result := Resp.ToJSON;
  finally
    Resp.Free;
  end;
end;

function TAiA2AServer.RpcResult(AId: TJSONValue; AResult: TJSONObject): string;
var
  Resp: TJSONObject;
begin
  Resp := TJSONObject.Create;
  try
    Resp.AddPair('jsonrpc', '2.0');
    Resp.AddPair('result', AResult); // takes ownership
    if Assigned(AId) then
      Resp.AddPair('id', TJSONValue(AId.Clone))
    else
      Resp.AddPair('id', TJSONNull.Create);
    Result := Resp.ToJSON;
  finally
    Resp.Free;
  end;
end;

function TAiA2AServer.HandleJsonRpc(const ABody, ATraceParent: string): string;
var
  Root: TJSONValue;
  Req, Params: TJSONObject;
  Method: string;
  IdVal: TJSONValue;
  LSpan: TAiSpan;
  LTaskJson: TJSONObject;
begin
  Root := TJSONObject.ParseJSONValue(ABody);
  if not(Root is TJSONObject) then
  begin
    Root.Free;
    Exit(RpcError(nil, -32700, 'Parse error: body is not a JSON object'));
  end;
  Req := TJSONObject(Root);
  try
    Method := Req.GetValue<string>('method', '');
    IdVal := Req.GetValue('id');
    Params := Req.GetValue<TJSONObject>('params', nil);

    // Continues the caller's trace if a traceparent came: without this every hop
    // of a federation starts a new trace and the flow is not observable.
    LSpan := AiSpanStart('a2a.server ' + Method, skServer, ATraceParent);
    AiSpanAttr(LSpan, 'a2a.method', Method);
    try
      // 1.0 methods + 0.x aliases (message/send, tasks/get, tasks/cancel)
      if SameText(Method, 'SendMessage') or SameText(Method, 'message/send') then
      begin
        // DoSendMessage leaves in FLastMessageJson whatever the graph put in
        // A2A.Message; if there is something, the response goes through the 'message' arm.
        FLastMessageJson := '';
        LTaskJson := DoSendMessage(Params);
        if FLastMessageJson <> '' then
          Result := RpcResult(IdVal, WrapSendMessageAsMessage(FLastMessageJson, LTaskJson))
        else
          Result := RpcResult(IdVal, WrapSendMessageResult(LTaskJson));
      end
      else if SameText(Method, 'GetTask') or SameText(Method, 'tasks/get') then
        Result := RpcResult(IdVal, DoGetTask(Params))
      else if SameText(Method, 'CancelTask') or SameText(Method, 'tasks/cancel') then
        Result := RpcResult(IdVal, DoCancelTask(Params))
      else if SameText(Method, 'ListTasks') or SameText(Method, 'tasks/list') then
        Result := RpcResult(IdVal, DoListTasks(Params))
      else if SameText(Method, 'GetExtendedAgentCard') or SameText(Method, 'agent/getExtendedCard') then
      begin
        // Only if the integrator enabled it: the extended card is meant
        // for already-authenticated clients, with more detail than the public one.
        if not FPublishExtendedCard then
          Result := RpcError(IdVal, A2A_ERR_EXTENDED_CARD_NOT_CONFIGURED, 'Extended agent card is not configured')
        else
          Result := RpcResult(IdVal, BuildAgentCard(FLastBaseUrl));
      end
      else if SameText(Method, 'SendStreamingMessage') or SameText(Method, 'SubscribeToTask') or
        SameText(Method, 'message/stream') or SameText(Method, 'tasks/resubscribe') then
        // The spec requires UnsupportedOperationError if capabilities.streaming=false
        Result := RpcError(IdVal, A2A_ERR_UNSUPPORTED_OPERATION, 'Streaming not supported by this agent')
      else if SameText(Method, 'CreateTaskPushNotificationConfig') then
        Result := RpcResult(IdVal, DoCreatePushConfig(Params))
      else if SameText(Method, 'GetTaskPushNotificationConfig') then
        Result := RpcResult(IdVal, DoGetPushConfig(Params))
      else if SameText(Method, 'ListTaskPushNotificationConfigs') then
        Result := RpcResult(IdVal, DoListPushConfigs(Params))
      else if SameText(Method, 'DeleteTaskPushNotificationConfig') then
        Result := RpcResult(IdVal, DoDeletePushConfig(Params))
      else if Method.ToLower.Contains('pushnotification') then
        // Variants we do not implement: with capabilities.pushNotifications at
        // false the spec asks for this specific code, not a MethodNotFound.
        Result := RpcError(IdVal, A2A_ERR_PUSH_NOT_SUPPORTED, 'Push notification method not supported')
      else
        Result := RpcError(IdVal, -32601, 'Method not found: ' + Method);
      AiSpanEnd(LSpan);
      LSpan := nil;
    except
      on E: EA2AServerError do
      begin
        AiSpanEnd(LSpan, E.Message);
        Result := RpcError(IdVal, E.Code, E.Message);
      end;
      on E: Exception do
      begin
        AiSpanEnd(LSpan, E.Message);
        // The graph engine signals contention with this text; without mapping it
        // a concurrent fan-out would return -32603 instead of AgentBusy.
        if E.Message.ToLower.Contains('busy') then
          Result := RpcError(IdVal, A2A_ERR_AGENT_BUSY, E.Message)
        else
          Result := RpcError(IdVal, -32603, E.Message);
      end;
    end;
  finally
    Req.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Streaming SSE (binding JSON-RPC)
// -----------------------------------------------------------------------------
// Each event travels as a 'data:' line with the JSON-RPC WRAPPER inside,
// per section 9.4.2 of the spec:
//     data: {jsonrpc, id, result: <StreamResponse>}
// NOTE: the REST binding sends the bare StreamResponse; the JSON-RPC one does not.
// StreamResponse is a oneof: task | message | statusUpdate | artifactUpdate.

procedure TAiA2AServer.SseWriteEvent(AContext: TIdContext; AId: TJSONValue; APayload: TJSONObject);
var
  Env: TJSONObject;
begin
  Env := TJSONObject.Create;
  try
    Env.AddPair('jsonrpc', '2.0');
    if Assigned(AId) then
      Env.AddPair('id', TJSONValue(AId.Clone))
    else
      Env.AddPair('id', TJSONNull.Create);
    Env.AddPair('result', APayload); // takes ownership
    // The double line break is what closes an event in SSE
    AContext.Connection.IOHandler.Write(ToBytes('data: ' + Env.ToJSON + #10#10, IndyTextEncoding_UTF8));
  finally
    Env.Free;
  end;
end;

function TAiA2AServer.StreamStatusEvent(AInfo: TAiA2ATaskInfo): TJSONObject;
var
  Ev, StatusObj: TJSONObject;
begin
  StatusObj := TJSONObject.Create;
  StatusObj.AddPair('state', EmitState(AInfo.State));
  StatusObj.AddPair('timestamp', DateToISO8601(TTimeZone.Local.ToUniversalTime(AInfo.UpdatedAt), True));
  Ev := TJSONObject.Create;
  Ev.AddPair('taskId', AInfo.Id);
  Ev.AddPair('contextId', AInfo.ContextId);
  Ev.AddPair('status', StatusObj);
  Result := TJSONObject.Create;
  Result.AddPair('statusUpdate', Ev);
end;

procedure TAiA2AServer.ParseAuthentication(AContext: TIdContext;
  const AAuthType, AAuthData: string; var VUsername, VPassword: string;
  var VHandled: Boolean);
begin
  VHandled := True;
end;

procedure TAiA2AServer.SseEmitArtifacts(AContext: TIdContext; AId: TJSONValue;
  AInfo: TAiA2ATaskInfo);
var
  TaskJson, ArtEv, ArtPayload: TJSONObject;
  Artifacts: TJSONArray;
  I: Integer;
begin
  FTasksLock.Enter;
  try
    TaskJson := BuildTaskJson(AInfo);
  finally
    FTasksLock.Leave;
  end;
  try
    if TaskJson.TryGetValue<TJSONArray>('artifacts', Artifacts) then
      for I := 0 to Artifacts.Count - 1 do
      begin
        ArtEv := TJSONObject.Create;
        ArtEv.AddPair('taskId', AInfo.Id);
        ArtEv.AddPair('contextId', AInfo.ContextId);
        ArtEv.AddPair('artifact', TJSONObject(Artifacts.Items[I].Clone));
        ArtEv.AddPair('lastChunk', TJSONBool.Create(I = Artifacts.Count - 1));
        ArtPayload := TJSONObject.Create;
        ArtPayload.AddPair('artifactUpdate', ArtEv);
        SseWriteEvent(AContext, AId, ArtPayload);
      end;
  finally
    TaskJson.Free;
  end;
end;

procedure TAiA2AServer.HandleStreamingRequest(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo; const AMethod: string; AParams: TJSONObject; AId: TJSONValue);
var
  Info: TAiA2ATaskInfo;
  MsgObj, TaskJson, Payload, ArtEv, ArtPayload: TJSONObject;
  Artifacts: TJSONArray;
  InputText, TaskId, ContextId, MessageId, EstadoPrevio, Hdr: string;
  Esperado, I: Integer;
  Suscripcion: Boolean;
begin
  Suscripcion := SameText(AMethod, 'SubscribeToTask') or SameText(AMethod, 'tasks/resubscribe');

  // Resolve the task BEFORE opening the stream: if an error must be returned,
  // normal JSON is responded. Once the SSE is open it can no longer be done.
  Info := nil;
  if Suscripcion then
  begin
    TaskId := '';
    if Assigned(AParams) then
      TaskId := AParams.GetValue<string>('id', '');
    FTasksLock.Enter;
    try
      Info := FindTask(TaskId);
      if Assigned(Info) then
        RefreshTask(Info);
    finally
      FTasksLock.Leave;
    end;
    if Info = nil then
    begin
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := RpcError(AId, A2A_ERR_TASK_NOT_FOUND, 'Task not found: ' + TaskId);
      Exit;
    end;
    if IsTerminal(Info.State) then
    begin
      // Subscribing to an already-terminal task is an error per the spec
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := RpcError(AId, A2A_ERR_UNSUPPORTED_OPERATION,
        'Task is already in a terminal state: ' + Info.State);
      Exit;
    end;
  end
  else
  begin
    MsgObj := nil;
    if Assigned(AParams) then
      AParams.TryGetValue<TJSONObject>('message', MsgObj);
    if not Assigned(MsgObj) then
    begin
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := RpcError(AId, A2A_ERR_INVALID_PARAMS,
        'SendStreamingMessage requires a message parameter');
      Exit;
    end;
    InputText := ExtractTextFromParts(MsgObj);
    ContextId := MsgObj.GetValue<string>('contextId', '');
    MessageId := MsgObj.GetValue<string>('messageId', '');
    TaskId    := MsgObj.GetValue<string>('taskId', '');
    if Assigned(AParams) then
    begin
      if TaskId = '' then
        TaskId := AParams.GetValue<string>('taskId', '');
      if ContextId = '' then
        ContextId := AParams.GetValue<string>('contextId', '');
    end;
    PurgeTasks;
    try
      if TaskId <> '' then
      begin
        // Same contract as SendMessage: with a taskId it RESUMES, it does not open a
        // new task. Without this a human-in-the-loop flow over streaming lost
        // the suspended graph on every turn and started from scratch.
        FTasksLock.Enter;
        try
          Info := FindTask(TaskId);
          if Assigned(Info) then
            RefreshTask(Info);
        finally
          FTasksLock.Leave;
        end;
        if Info = nil then
          raise EA2AServerError.CreateCode(A2A_ERR_TASK_NOT_FOUND, 'Task not found: ' + TaskId);

        // A crossed taskId/contextId pair is an error, not something to ignore.
        if (ContextId <> '') and (Info.ContextId <> ContextId) then
          raise EA2AServerError.CreateCode(A2A_ERR_INVALID_PARAMS,
            Format('contextId "%s" does not belong to task "%s"', [ContextId, TaskId]));

        if Info.State = A2A_STATE_INPUT_REQUIRED then
          ResumeTask(Info, InputText, MessageId)
        else if IsTerminal(Info.State) then
          raise EA2AServerError.CreateCode(A2A_ERR_UNSUPPORTED_OPERATION,
            Format('Task "%s" is in a terminal state (%s) and cannot be continued',
              [TaskId, Info.State]));
      end
      else
      begin
        Info := NewTask(ContextId);
        Info.MessageId := MessageId;
        StartTask(Info, InputText);
      end;
    except
      on E: EA2AServerError do
      begin
        AResponseInfo.ResponseNo := 200;
        AResponseInfo.ContentText := RpcError(AId, E.Code, E.Message);
        Exit;
      end;
    end;
  end;

  // --- From here on the stream is open ---
  Hdr := 'HTTP/1.1 200 OK' + #13#10 + 'Content-Type: text/event-stream; charset=utf-8' + #13#10 +
    'Cache-Control: no-cache' + #13#10 + 'Connection: keep-alive' + #13#10 +
    'X-Accel-Buffering: no' + #13#10 + #13#10;
  AContext.Connection.IOHandler.Write(ToBytes(Hdr, IndyTextEncoding_UTF8));
  AResponseInfo.HeaderHasBeenWritten := True; // so Indy does not write its own

  // 1. Initial snapshot of the task
  FTasksLock.Enter;
  try
    RefreshTask(Info);
    EstadoPrevio := Info.State;
    TaskJson := BuildTaskJson(Info);
  finally
    FTasksLock.Leave;
  end;
  Payload := TJSONObject.Create;
  Payload.AddPair('task', TaskJson);
  SseWriteEvent(AContext, AId, Payload);

  // 1b. The task may have reached its final state BEFORE this first
  // snapshot: a fast graph, or a resume that completes right away. Then there is
  // no change left to detect and the loop below would keep spinning
  // until WaitTimeoutMs runs out with the client waiting. It is closed now.
  //
  // input-required only closes if it is NOT a subscription: in
  // SendStreamingMessage it means "your turn", but whoever does
  // SubscribeToTask is an observer and must keep watching the
  // later transitions.
  if IsTerminal(EstadoPrevio) or
    ((EstadoPrevio = A2A_STATE_INPUT_REQUIRED) and not Suscripcion) then
  begin
    if EstadoPrevio = A2A_STATE_COMPLETED then
      SseEmitArtifacts(AContext, AId, Info);
    FTasksLock.Enter;
    try
      Payload := StreamStatusEvent(Info);
    finally
      FTasksLock.Leave;
    end;
    SseWriteEvent(AContext, AId, Payload);
    AContext.Connection.Disconnect;
    Exit;
  end;

  // 2. Follow the execution and emit each state change
  Esperado := 0;
  while (Esperado < FWaitTimeoutMs) and AContext.Connection.Connected do
  begin
    Sleep(50);
    Inc(Esperado, 50);

    FTasksLock.Enter;
    try
      RefreshTask(Info);
      if Info.State <> EstadoPrevio then
      begin
        EstadoPrevio := Info.State;
        Payload := StreamStatusEvent(Info);
      end
      else
        Payload := nil;
    finally
      FTasksLock.Leave;
    end;

    if not Assigned(Payload) then
      Continue;

    // 3. On completion, first the artifacts and then the final status.
    if EstadoPrevio = A2A_STATE_COMPLETED then
      SseEmitArtifacts(AContext, AId, Info);

    SseWriteEvent(AContext, AId, Payload);

    // input-required also closes the stream: the ball goes to the client
    if IsTerminal(EstadoPrevio) or (EstadoPrevio = A2A_STATE_INPUT_REQUIRED) then
      Break;
  end;

  AContext.Connection.Disconnect;
end;
procedure TAiA2AServer.HttpCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Body, BaseUrl, Scheme, AuthHdr, VerHdr, CtHdr, CardJson, ETag, PeekMethod: string;
  Token: string;
  CardPublica: Boolean;
  PeekRoot: TJSONValue;
  Card: TJSONObject;
  Allowed: Boolean;
begin
  AResponseInfo.ContentType := 'application/json; charset=utf-8';
  AResponseInfo.CharSet := 'utf-8';

  // --- Autorizacion ---
  // The base Agent Card stays OUTSIDE the ApiKey check: it is a
  // discovery document, and it is exactly where the client reads WHICH security
  // scheme it must use. Protecting it is a vicious circle -to know
  // how to authenticate you would already have to be authenticated- and it leaves the agent
  // invisible to any client that does not carry the key in advance.
  // To publish data only to authenticated clients there is the extended card
  // (GetExtendedAgentCard), which does go through here.
  //
  // OnAuthorize IS still called: if someone wants to close the card too,
  // it is their own explicit decision.
  CardPublica := SameText(ARequestInfo.Command, 'GET') and
    (SameText(ARequestInfo.URI, '/.well-known/agent-card.json') or
     SameText(ARequestInfo.URI, '/.well-known/agent.json'));

  AuthHdr := ARequestInfo.RawHeaders.Values['Authorization'];
  Allowed := True;
  if (FApiKey <> '') and not CardPublica then
  begin
    Token := Trim(AuthHdr);
    if StartsText('Bearer ', Token) then
      Token := Trim(Copy(Token, Length('Bearer ') + 1, MaxInt))
    else
      Token := '';
    // The secret is compared EXACTLY. With SameText a key 'AbC' was validated by
    // 'abc', which throws away much of its entropy; only the
    // scheme name goes case-insensitive.
    Allowed := (Token <> '') and (Token = FApiKey);
    if not Allowed then
      Allowed := ARequestInfo.RawHeaders.Values['X-API-Key'] = FApiKey;
  end;
  if Assigned(FOnAuthorize) then
    FOnAuthorize(Self, AuthHdr, Allowed);
  if not Allowed then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.CustomHeaders.Values['WWW-Authenticate'] := 'Bearer';
    AResponseInfo.ContentText := '{"error":"unauthorized"}';
    Exit;
  end;

  // Agent Card discovery (path 1.0 + alias legacy)
  if SameText(ARequestInfo.Command, 'GET') and
    (SameText(ARequestInfo.URI, '/.well-known/agent-card.json') or SameText(ARequestInfo.URI, '/.well-known/agent.json')) then
  begin
    if FPublicUrl <> '' then
      BaseUrl := FPublicUrl
    else
    begin
      // Behind a TLS reverse proxy the real scheme arrives by header; without
      // this the card would announce http:// and the client could not come back.
      Scheme := LowerCase(ARequestInfo.RawHeaders.Values['X-Forwarded-Proto']);
      if Scheme = '' then
        Scheme := 'http';
      BaseUrl := Scheme + '://' + ARequestInfo.Host + '/';
    end;
    FLastBaseUrl := BaseUrl;
    Card := BuildAgentCard(BaseUrl);
    try
      CardJson := Card.ToJSON;
    finally
      Card.Free;
    end;

    // The spec recommends (SHOULD) the card be cacheable: without this every
    // client asks for it again on every discovery.
    ETag := '"' + THashSHA2.GetHashString(CardJson).Substring(0, 32) + '"';
    AResponseInfo.CustomHeaders.Values['Cache-Control'] :=
      Format('public, max-age=%d', [FCardCacheSeconds]);
    AResponseInfo.CustomHeaders.Values['ETag'] := ETag;

    // Conditional revalidation: if the client already has this version, 304.
    if SameText(Trim(ARequestInfo.RawHeaders.Values['If-None-Match']), ETag) then
    begin
      AResponseInfo.ResponseNo := 304;
      AResponseInfo.ContentText := '';
      Exit;
    end;

    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentText := CardJson;
    Exit;
  end;

  if SameText(ARequestInfo.Command, 'POST') then
  begin
    // --- Header validations required by the spec (section 5.4) ---
    // Version: if the client declares one we do not support, it must be rejected
    // with its own code. Absent = assumed compatible (0.x clients).
    VerHdr := Trim(ARequestInfo.RawHeaders.Values[A2A_VERSION_HEADER]);
    if (VerHdr <> '') and (not SameText(VerHdr, A2A_VERSION)) and (not VerHdr.StartsWith('1.')) then
    begin
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := RpcError(nil, A2A_ERR_VERSION_NOT_SUPPORTED,
        Format('A2A version "%s" is not supported; this agent speaks %s', [VerHdr, A2A_VERSION]));
      Exit;
    end;

    // Content-Type: it must be JSON. Returning ParseError here would be misleading,
    // because the body may be perfectly well formed.
    CtHdr := LowerCase(ARequestInfo.ContentType);
    if (CtHdr <> '') and (not CtHdr.Contains('json')) then
    begin
      AResponseInfo.ResponseNo := 200;
      AResponseInfo.ContentText := RpcError(nil, A2A_ERR_CONTENT_TYPE_NOT_SUPPORTED,
        Format('Content-Type "%s" is not supported; use application/json', [ARequestInfo.ContentType]));
      Exit;
    end;

    // Remembered so the card can be built in GetExtendedAgentCard, which
    // arrives via JSON-RPC and carries no URL context.
    if FLastBaseUrl = '' then
      if FPublicUrl <> '' then
        FLastBaseUrl := FPublicUrl
      else
        FLastBaseUrl := 'http://' + ARequestInfo.Host + '/';
    Body := '';
    if Assigned(ARequestInfo.PostStream) then
    begin
      ARequestInfo.PostStream.Position := 0;
      with TStringStream.Create('', TEncoding.UTF8) do
        try
          CopyFrom(ARequestInfo.PostStream, 0);
          Body := DataString;
        finally
          Free;
        end;
    end;
    // The streaming methods do not respond JSON but an SSE, so they are
    // diverted before entering the normal dispatcher.
    if FEnableStreaming then
    begin
      PeekRoot := TJSONObject.ParseJSONValue(Body);
      try
        if PeekRoot is TJSONObject then
        begin
          PeekMethod := TJSONObject(PeekRoot).GetValue<string>('method', '');
          if SameText(PeekMethod, 'SendStreamingMessage') or SameText(PeekMethod, 'message/stream') or
            SameText(PeekMethod, 'SubscribeToTask') or SameText(PeekMethod, 'tasks/resubscribe') then
          begin
            HandleStreamingRequest(AContext, ARequestInfo, AResponseInfo, PeekMethod,
              TJSONObject(PeekRoot).GetValue<TJSONObject>('params', nil),
              TJSONObject(PeekRoot).GetValue('id'));
            Exit;
          end;
        end;
      finally
        PeekRoot.Free;
      end;
    end;

    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentText := HandleJsonRpc(Body, ARequestInfo.RawHeaders.Values['traceparent']);
    Exit;
  end;

  AResponseInfo.ResponseNo := 404;
  AResponseInfo.ContentText := '{"error":"not found"}';
end;

end.
