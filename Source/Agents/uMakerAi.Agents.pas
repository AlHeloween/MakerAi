// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Agents;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults, System.TypInfo,
  System.JSON, System.Math,
  System.Threading, System.Rtti, System.SyncObjs, System.Types, System.StrUtils,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Chat, uMakerAi.Core, uMakerAi.Chat.Messages,
  uMakerAi.Agents.Checkpoint;  // IAiCheckpointer, TAiCheckpointSnapshot, TAiPendingStep

{$IF CompilerVersion < 35}
type
  TInterlockedHelper = class helper for TInterlocked
    class function Exchange(var Target: Boolean; Value: Boolean): Boolean; overload; static; inline;
  end;
{$ENDIF}

const
  // Component infrastructure properties that are NOT tool parameters:
  // they are excluded from the 'properties' blob in both directions (M-04).
  AI_TOOL_RESERVED_PROPS: array [0 .. 3] of string = ('Name', 'Tag', 'ID', 'Description');

type

{$RTTI INHERIT}
  TMsgState = (msYes, msNo, msOK, msCancel, msAbort, msRetry, msIgnore, msAll, msNoToAll, msYesToAll, msHelp, msClose);
  TMsgStates = set of TMsgState;

  TAgentExecutionStatus = (esUnknown, esRunning, esCompleted, esError,
                           esTimeout, esAborted, esSuspended);

  // Join mode for the nodes
  TJoinMode = (jmAny, jmAll);

  // Link execution mode
  TLinkMode = (lmFanout, lmConditional, lmManual, lmExpression); // --- NEW: lmExpression mode ---

  // Forward Declarations
  TAIAgentManager = class;
  TAIAgentsBase = class;
  TAIAgentsNode = class;
  TAIAgentsLink = class;
  TAIBlackboard = class;
  TAiToolBase = Class;

  TAIAgentsOnPrint = procedure(Sender: TObject; Value: String) of object;
  TAgentPrintRef = reference to procedure(Sender: TObject; Value: String);

  TAIAgentsOnEnd = procedure(Node: TAIAgentsNode; Value: string) of object;
  TAIAgentsNodeOnExecute = procedure(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: String; var Output: String) of object;
  TAIAgentsLinkOnExecute = procedure(Node: TAIAgentsNode; Link: TAIAgentsLink; var IsOk: Boolean; var Handled: Boolean) of object;
  TAIAgentsOnError = procedure(Sender: TObject; Node: TAIAgentsNode; Link: TAIAgentsLink; E: Exception; var Abort: Boolean) of object;
  TAIAgentsOnConfirm = procedure(Sender: TObject; Node: TAIAgentsNode; const AQuestion: string; Buttons: TMsgStates; var AResponse: string; var AModalResult: TMsgState) of object;

  TAIAgentsOnEnterNode = procedure(Sender: TObject; Node: TAIAgentsNode) of object;
  TAIAgentsOnExitNode = procedure(Sender: TObject; Node: TAIAgentsNode) of object;
  TAIAgentsOnStart = procedure(Sender: TObject; const Input: string) of object;
  // TAIAgentsOnFinish = procedure(Sender: TObject; const Input, Output: string; Status: string; E: Exception) of object;
  TAIAgentsOnFinish = procedure(Sender: TObject; const Input, Output: string; Status: TAgentExecutionStatus; E: Exception) of object;

  // Fired when a node suspends waiting for human input
  TAIAgentsOnSuspend = procedure(Sender: TObject;
                                 const AThreadID:  string;
                                 const ANodeName:  string;
                                 const AReason:    string;
                                 const AContext:   string) of object;

  // Blackboard seeding callback for the Run(APrompt, ASeed) overload.
  // Invoked AFTER ResetExecutionState and BEFORE Run seeds
  // AskMsg/ResMsg, so what is seeded here survives the cleanup.
  TAiBlackboardSeed = reference to procedure(ABlackboard: TAIBlackboard);

  // --- Blackboard ---
  TAIBlackboard = class(TObject)
  private
    FLock: TCriticalSection;
    function GetAskMsg: TAiChatMessage;
    function GetResMsg: TAiChatMessage;
    procedure SetAskMsg(const Value: TAiChatMessage);
    procedure SetResMsg(const Value: TAiChatMessage);
    // Frees the previous instance stored in AKey if it differs from ANew.
    procedure FreeOwnedObject(const AKey: string; ANew: TObject);
  protected // --- MODIFIED: protected for access from the same unit ---
    FData: TDictionary<string, TValue>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure SetValue(const AKey: string; const AValue: TValue);
    function TryGetValue(const AKey: string; out AValue: TValue): Boolean;
    procedure SetString(const AKey, AValue: string);
    function GetString(const AKey: string; const ADefault: string = ''): string;
    procedure SetInteger(const AKey: string; AValue: Integer);
    function GetInteger(const AKey: string; const ADefault: Integer = 0): Integer;
    procedure SetBoolean(const AKey: string; AValue: Boolean);
    procedure SetStatus(Value: TAgentExecutionStatus);
    function GetStatus: TAgentExecutionStatus;
    function GetBoolean(const AKey: string; const ADefault: Boolean = False): Boolean;
    Property AskMsg: TAiChatMessage read GetAskMsg write SetAskMsg;
    Property ResMsg: TAiChatMessage read GetResMsg write SetResMsg;
  end;

  TAiToolBase = class(TComponent)
  private
    FDescription: string;
    FID: String;
    procedure SetDescription(const Value: String);
    procedure SetID(const Value: String);
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string); virtual; abstract;
  public
    procedure Run(ANode: TAIAgentsNode; const AInput: string; var AOutput: string);
  published
    property Description: string read FDescription write SetDescription;
    Property ID: String read FID write SetID; // GUID identifying each node
  end;

  TAiAgentsToolSample = class(TAiToolBase)
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string); override;
  end;

  // Structural error of the graph (validation in GraphBuilder, incomplete
  // serialization in SaveToStream, etc.)
  EAiGraphError = class(Exception);

  // M-04: public and single RTTI mapper for a tool's parameters.
  // Excludes AI_TOOL_RESERVED_PROPS and respects [TSecret] in both directions:
  // secret properties are not written and their incoming values are ignored.
  // FromJSON is tolerant: accepts typed values or string-represented values
  // (unifies the GraphBuilder mapper that read everything as text).
  TAiToolParams = class
  private
    class function IsReserved(const APropName: string): Boolean;
  public
    class function ToJSON(ATool: TAiToolBase): TJSONObject;
    class procedure FromJSON(ATool: TAiToolBase; AJson: TJSONObject);
    // JSON Schema of the editable parameters; [TSecret] properties are
    // included with "writeOnly": true so an editor shows a credential
    // selector instead of a text field.
    class function SchemaOf(AToolClass: TClass): TJSONObject;
  end;

  // --- Base Component ---
  TAIAgentsBase = class(TComponent)
  private
    FDescription: String;
    FID: String;
    procedure SetDescription(const Value: String);
    procedure SetID(const Value: String);
  Published
    Property Description: String read FDescription write SetDescription;
    Property ID: String read FID write SetID; // GUID identifying each node
  end;

  // --- Link (Edge) ---
  TAIAgentsLink = class(TAIAgentsBase)
  private
    FNextNo: TAIAgentsNode;
    FNextB: TAIAgentsNode;
    FNextC: TAIAgentsNode;
    FNextA: TAIAgentsNode;
    FNextD: TAIAgentsNode;
    FGraph: TAIAgentManager;
    FOnExecute: TAIAgentsLinkOnExecute;
    FNoCycles: Integer;
    FMaxCycles: Integer;
    FReady: Boolean;
    FSourceNode: TAIAgentsNode;
    FConditionalTargets: TDictionary<string, TAIAgentsNode>;
    FMode: TLinkMode;
    FConditionalKey: string;
    FManualTargetsKey: string;
    // --- NEW: Fields for the lmExpression mode ---
    FExpressionA: string;
    FExpressionB: string;
    FExpressionC: string;
    FExpressionD: string;
    procedure SetNextA(const Value: TAIAgentsNode);
    procedure SetNextB(const Value: TAIAgentsNode);
    procedure SetNextC(const Value: TAIAgentsNode);
    procedure SetNextD(const Value: TAIAgentsNode);
    procedure SetNextNo(const Value: TAIAgentsNode);
    procedure SetGraph(const Value: TAIAgentManager);
    procedure SetOnExecute(const Value: TAIAgentsLinkOnExecute);
    procedure SetMaxCycles(const Value: Integer);
    procedure SetMode(const Value: TLinkMode);
  protected
    property Ready: Boolean read FReady write FReady;
    procedure BuildManualTargets(const TargetsCSV: string; out Nodes: TList<TAIAgentsNode>);
    procedure CreateAndQueueTask(ANodeToExecute, ASourceNode: TAIAgentsNode; ACurrentLink: TAIAgentsLink);
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure Print(Value: String);
    procedure DoExecute(Sender: TAIAgentsNode); // --- MODIFIED: It is now the only execution method
    procedure AddConditionalTarget(const AKey: string; ANode: TAIAgentsNode);
    property NoCycles: Integer read FNoCycles write FNoCycles;
  published
    property NextA: TAIAgentsNode read FNextA write SetNextA;
    property NextB: TAIAgentsNode read FNextB write SetNextB;
    property NextC: TAIAgentsNode read FNextC write SetNextC;
    property NextD: TAIAgentsNode read FNextD write SetNextD;
    property NextNo: TAIAgentsNode read FNextNo write SetNextNo;
    property Graph: TAIAgentManager read FGraph write SetGraph;
    property OnExecute: TAIAgentsLinkOnExecute read FOnExecute write SetOnExecute;
    property MaxCycles: Integer read FMaxCycles write SetMaxCycles default 1;
    property Mode: TLinkMode read FMode write SetMode default lmFanout;
    property ConditionalKey: string read FConditionalKey write FConditionalKey;
    property ManualTargetsKey: string read FManualTargetsKey write FManualTargetsKey;
    // --- NEW: Properties for the lmExpression mode ---
    property ExpressionA: string read FExpressionA write FExpressionA;
    property ExpressionB: string read FExpressionB write FExpressionB;
    property ExpressionC: string read FExpressionC write FExpressionC;
    property ExpressionD: string read FExpressionD write FExpressionD;
  end;

  // --- Node ---
  TAIAgentsNode = class(TAIAgentsBase)
  private
    FOutput: String;
    FInput: String;
    FNext: TAIAgentsLink;
    FGraph: TAIAgentManager;
    FInEdges: TList<TAIAgentsLink>;
    FOnExecute: TAIAgentsNodeOnExecute;
    FPromptName: String;
    FMsgError: String;
    FError: Boolean;
    FJoinLock: TCriticalSection;
    FJoinMode: TJoinMode;
    FTool: TAiToolBase;
    FJoinInputs: TDictionary<TAIAgentsLink, string>;
    // --- human-in-the-loop suspension ---
    FSuspended:      Boolean;
    FSuspendReason:  string;
    FSuspendContext: string;
    procedure SetInput(const Value: String);
    procedure SetNext(const Value: TAIAgentsLink);
    procedure SetOutput(const Value: String);
    procedure SetGraph(const Value: TAIAgentManager);
    procedure SetOnExecute(const Value: TAIAgentsNodeOnExecute);
    procedure SetPromptName(const Value: String);
    procedure SetJoinMode(const Value: TJoinMode);
    procedure SetTool(const Value: TAiToolBase);
    procedure SetError(const Value: Boolean);
    procedure SetMsgError(const Value: String);
  protected
    procedure DoExecute(aBeforeNode: TAIAgentsNode; aLink: TAIAgentsLink); virtual;
    // Performs the routing to the next link after the node's execution.
    // Subclasses that override DoExecute must call this method at the end.
    procedure DoTraverseLinks(aBeforeNode: TAIAgentsNode; aLink: TAIAgentsLink);
    // Evaluates the join logic (jmAny / jmAll) and updates Self.Input.
    // Returns True if the node must execute now, False if it must wait.
    // Subclasses that completely override DoExecute MUST call this
    // at the start and exit if it returns False.
    function CheckJoinAndPrepareInput(aBeforeNode: TAIAgentsNode; aLink: TAIAgentsLink): Boolean;
    procedure Reset;
    procedure ResetExecutionState;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure Print(Value: String);
    procedure ForceFinalExecute;
    function RequestConfirmation(const AQuestion: string; Buttons: TMsgStates; var AResponse: string): TMsgState;
    function RequestInput(const ACaption, APrompt: string; var AValue: string): Boolean;
    // Suspends this node. Call from OnExecute or from a Tool's Execute.
    // DoExecute checks FSuspended on return and does not route to the next Link.
    procedure Suspend(const AReason: string; const AContext: string = '');
    property Error:          Boolean read FError        Write SetError;
    property MsgError:       String  read FMsgError     write SetMsgError;
    property Suspended:      Boolean read FSuspended;
    property SuspendReason:  string  read FSuspendReason;
    property SuspendContext: string  read FSuspendContext;
  published
    property Input: String read FInput write SetInput;
    property Output: String read FOutput write SetOutput;
    property Next: TAIAgentsLink read FNext write SetNext;
    property Graph: TAIAgentManager read FGraph write SetGraph;
    property OnExecute: TAIAgentsNodeOnExecute read FOnExecute write SetOnExecute;
    property PromptName: String read FPromptName write SetPromptName;
    property JoinMode: TJoinMode read FJoinMode write SetJoinMode default jmAny;
    property Tool: TAiToolBase read FTool write SetTool;
  end;

  // --- Orchestrator ---

  TAIAgentManager = class(TComponent)
  private
    FEndNode: TAIAgentsNode;
    FStartNode: TAIAgentsNode;
    FOnPrint: TAIAgentsOnPrint;
    FOnPrintRef: TAgentPrintRef;
    FNodes: TList<TAIAgentsNode>;
    FLinks: TList<TAIAgentsLink>;
    FOnEnd: TAIAgentsOnEnd;
    FOnError: TAIAgentsOnError;
    FOnConfirm: TAIAgentsOnConfirm;
    FBusy: Integer;
    FAbort: Boolean;
    FBlackboard: TAIBlackboard;
    FCompiled: Boolean;
    FActiveTasks: TList<ITask>;
    FActiveTasksLock: TCriticalSection;
    FOnExitNode: TAIAgentsOnExitNode;
    FOnEnterNode: TAIAgentsOnEnterNode;
    FMaxConcurrentTasks: Integer;
    FTimeoutMs: Cardinal;
    FOnFinish: TAIAgentsOnFinish;
    FOnStart: TAIAgentsOnStart;
    FDescription: String;
    FAsynchronous: Boolean;
    FAllowPartialSerialization: Boolean;
    // --- Durable execution (checkpoint / suspend-resume) ---
    FCheckpointer:       IAiCheckpointer;
    FCurrentThreadID:    string;
    // Telemetry: traceparent of the current graph's span. Nodes run in
    // pool workers (no per-thread context), so they read it from here.
    FRunTraceParent:     string;
    FCheckpointSeq:      Integer;  // protected by FActiveTasksLock
    FSuspendedSteps:     TObjectList<TAiPendingStep>; // owned
    FSuspendedStepsLock: TCriticalSection;
    FOnSuspend:          TAIAgentsOnSuspend;
    function GetBusy: Boolean;
    procedure SetCheckpointer(const Value: IAiCheckpointer);
    procedure SetOnSuspend(const Value: TAIAgentsOnSuspend);
    procedure SetMaxConcurrentTasks(const Value: Integer);
    procedure SetEndNode(const Value: TAIAgentsNode);
    procedure SetStartNode(const Value: TAIAgentsNode);
    procedure SetOnPrint(const Value: TAIAgentsOnPrint);
    procedure SetOnEnd(const Value: TAIAgentsOnEnd);
    procedure SetOnError(const Value: TAIAgentsOnError);
    procedure SetOnConfirm(const Value: TAIAgentsOnConfirm);
    procedure SetOnEnterNode(const Value: TAIAgentsOnEnterNode);
    procedure SetOnExitNode(const Value: TAIAgentsOnExitNode);
    procedure SetOnFinish(const Value: TAIAgentsOnFinish);
    procedure SetOnStart(const Value: TAIAgentsOnStart);
    procedure SetDescription(const Value: String);
    procedure SetAsynchronous(const Value: Boolean);
  protected
    // --- CORREGIDO: TThreadPool ---
    FThreadPool: TThreadPool;
    procedure DoPrint(Sender: TObject; Value: String);
    procedure DoPrintFromRef(Sender: TObject; Value: String);
    procedure DoNodeCompleted(ANode: TAIAgentsNode);
    procedure DoNodeSuspended(ANode: TAIAgentsNode;
                              ABeforeNode: TAIAgentsNode;
                              ALink: TAIAgentsLink);
    function  BuildSnapshot: TAiCheckpointSnapshot;
    procedure RestoreFromSnapshot(ASnapshot: TAiCheckpointSnapshot);
    function  FindLink(const AName: string): TAIAgentsLink;
    procedure AddComponentToList(AComponent: TAIAgentsBase);
    procedure RemoveComponentFromList(AComponent: TAIAgentsBase);
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function InternalRun(Msg: String): ITask; Virtual;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure Abort;
    function FindNode(const AName: string): TAIAgentsNode;
    procedure DoError(Node: TAIAgentsNode; Link: TAIAgentsLink; E: Exception);
    function DoConfirm(Node: TAIAgentsNode; const AQuestion: string; Buttons: TMsgStates; var AResponse: string): TMsgState;

    procedure SetOnPrintEvent(const APrintProc: TAgentPrintRef);
    procedure ClearGraph;
    function AddNode(const AName: string; AExecuteProc: TAIAgentsNodeOnExecute): TAIAgentManager;
    function AddEdge(const AStartNodeName, AEndNodeName: string): TAIAgentManager;
    function AddConditionalEdge(const AStartNodeName: string; const AConditionalLinkName: string; AConditionalTargets: TDictionary<string, string>): TAIAgentManager;
    function SetEntryPoint(const ANodeName: string): TAIAgentManager;
    function SetFinishPoint(const ANodeName: string): TAIAgentManager;
    procedure Compile;
    procedure ResetExecutionState;
    procedure SaveToStream(AStream: TStream);
    Procedure LoadFromStream(AStream: TStream);
    procedure SaveStateToStream(AStream: TStream);
    procedure LoadStateFromStream(AStream: TStream);

    function Run(APrompt: String): String; overload; virtual;

    /// Clean run: discards the previous run's state before
    /// executing. Guaranteed order: Compile -> ResetExecutionState -> ASeed ->
    /// AskMsg/ResMsg seeding -> execution.
    ///
    /// Use this overload when reusing the same TAIAgentManager for several
    /// runs: Run(APrompt) keeps the historical behavior and drags
    /// the blackboard and the node/link state of the previous execution.
    ///
    /// ASeed may assign AskMsg (it is not overwritten if already assigned).
    /// It does not need to assign ResMsg: Run always creates it for the run.
    function Run(const APrompt: String; ASeed: TAiBlackboardSeed): String; overload;

    function AddMessageAndRun(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String;
    function AddMessageAndRunMsg(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;

    function NewMessage(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;

    property Busy: Boolean read GetBusy;
    property Blackboard: TAIBlackboard read FBlackboard;
    property CurrentThreadID: string read FCurrentThreadID;
    // Resumes a suspended thread. AInput is the human's response/approval.
    // Returns True if the thread was found and the resume started.
    function ResumeThread(const AThreadID, ANodeName, AInput: string): Boolean;
    // Lists thread IDs with active checkpoints (suspended or in progress)
    function GetActiveThreads: TArray<string>;
    // Names of the currently suspended nodes (human-in-the-loop). It is the
    // synchronous way to know WHICH node asks for input: OnSuspend fires via
    // TThread.Queue and on a headless server (without a message pump or
    // CheckSynchronize) it might never arrive.
    function GetSuspendedNodeNames: TArray<string>;
    // The graph's nodes, in registration order. Needed to
    // publish them outward (e.g. the A2A Agent Card's skills):
    // walking the Owner's Components does not work, because a node placed on
    // a form does not have the manager as Owner.
    function GetNodes: TArray<TAIAgentsNode>;
    property Checkpointer: IAiCheckpointer read FCheckpointer write SetCheckpointer;
  published
    property StartNode: TAIAgentsNode read FStartNode write SetStartNode;
    property EndNode: TAIAgentsNode read FEndNode write SetEndNode;
    property OnPrint: TAIAgentsOnPrint read FOnPrint write SetOnPrint;
    property OnEnd: TAIAgentsOnEnd read FOnEnd write SetOnEnd;
    property OnError: TAIAgentsOnError read FOnError write SetOnError;
    property OnConfirm: TAIAgentsOnConfirm read FOnConfirm write SetOnConfirm;
    property OnEnterNode: TAIAgentsOnEnterNode read FOnEnterNode write SetOnEnterNode;
    property OnExitNode: TAIAgentsOnExitNode read FOnExitNode write SetOnExitNode;
    property MaxConcurrentTasks: Integer read FMaxConcurrentTasks write SetMaxConcurrentTasks default 4;
    property OnStart: TAIAgentsOnStart read FOnStart write SetOnStart;
    property OnFinish: TAIAgentsOnFinish read FOnFinish write SetOnFinish;
    property TimeoutMs: Cardinal read FTimeoutMs write FTimeoutMs default 60000;
    Property Description: String read FDescription write SetDescription;
    property Asynchronous: Boolean read FAsynchronous write SetAsynchronous default True;
    // M-06: with False (default), SaveToStream raises EAiGraphError if a node
    // has OnExecute without a Tool (the handler cannot be rebuilt on load and
    // the file would be "complete" but unusable). True keeps the
    // historical placeholder as a diagnostic dump.
    property AllowPartialSerialization: Boolean read FAllowPartialSerialization write FAllowPartialSerialization default False;
    property OnSuspend: TAIAgentsOnSuspend read FOnSuspend write SetOnSuspend;
  end;

  TAIAgents = Class(TAIAgentManager)
  End deprecated 'Use TAIAgentManager instead';

function EvalCondition(const Expr: string; Vars: TDictionary<string, TValue>): Boolean;

procedure Register;

implementation

uses uMakerAi.Agents.EngineRegistry, uMakerAi.Agents.Attributes, uMakerAi.Telemetry;

{$IF CompilerVersion < 35}
class function TInterlockedHelper.Exchange(var Target: Boolean; Value: Boolean): Boolean;
begin
  Integer((@Result)^) := AtomicExchange(Integer((@Target)^), Integer((@Value)^));
end;
{$ENDIF}

procedure Register;
begin
  {$WARN SYMBOL_DEPRECATED OFF}
  RegisterComponents('MakerAI', [TAIAgentManager, TAIAgentsNode, TAIAgentsLink, TAiAgentsToolSample, TAIAgents]);
  {$WARN SYMBOL_DEPRECATED ON}
end;

// Simple expression evaluator for lmExpression link mode.
// Supports: bare key (truthy), key=val, key<>val, key!=val, key>val,
//           key<val, key>=val, key<=val.  Values are compared as strings
// unless both sides parse as numbers.
function EvalCondition(const Expr: string; Vars: TDictionary<string, TValue>): Boolean;
var
  LExpr, LKey, LOp, LRhs: string;
  LVal: TValue;
  LLhs, LRhsNum: Double;
  LFound: Boolean;
  I, P: Integer;
  Ops: array[0..5] of string;
  Op: string;
begin
  Result := False;
  LExpr := Trim(Expr);
  if LExpr = '' then Exit;

  Ops[0] := '<>';
  Ops[1] := '!=';
  Ops[2] := '>=';
  Ops[3] := '<=';
  Ops[4] := '>';
  Ops[5] := '<';

  LOp := '';
  P   := 0;
  // Check two-char ops first, then single-char =
  for I := 0 to 5 do
  begin
    P := Pos(Ops[I], LExpr);
    if P > 0 then begin LOp := Ops[I]; Break; end;
  end;
  if LOp = '' then
  begin
    P := Pos('=', LExpr);
    if P > 0 then LOp := '=';
  end;

  if LOp = '' then
  begin
    // Bare key: truthy check
    LKey := LExpr;
    if not Vars.TryGetValue(LKey, LVal) then Exit;
    if LVal.Kind = tkEnumeration then
      Result := LVal.AsBoolean
    else if LVal.Kind in [tkInteger, tkInt64, tkFloat] then
      Result := LVal.AsExtended <> 0
    else if LVal.Kind in [tkString, tkUString, tkLString, tkWString] then
      Result := LVal.AsString <> ''
    else
      Result := not LVal.IsEmpty;
    Exit;
  end;

  LKey := Trim(Copy(LExpr, 1, P - 1));
  LRhs := Trim(Copy(LExpr, P + Length(LOp), MaxInt));

  LFound := Vars.TryGetValue(LKey, LVal);
  if not LFound then
  begin
    Result := (LOp = '<>') or (LOp = '!=');
    Exit;
  end;

  // Get LHS as string and number (if parseable)
  var LLhsStr: string;
  if LVal.Kind in [tkString, tkUString, tkLString, tkWString] then
    LLhsStr := LVal.AsString
  else if LVal.Kind = tkEnumeration then
    LLhsStr := BoolToStr(LVal.AsBoolean, True)
  else
    LLhsStr := LVal.ToString;

  // First with the regional settings and then with the decimal point: on a
  // Spanish Windows '0.7' does not parse with plain TryStrToFloat and the
  // comparison fell back to text. The expressions and the values the
  // tools write (e.g. TAiJevRouterTool) use the point.
  var LLhsIsNum: Boolean := TryStrToFloat(LLhsStr, LLhs) or
    TryStrToFloat(LLhsStr, LLhs, TFormatSettings.Invariant);
  var LRhsIsNum: Boolean := TryStrToFloat(LRhs, LRhsNum) or
    TryStrToFloat(LRhs, LRhsNum, TFormatSettings.Invariant);

  if LLhsIsNum and LRhsIsNum then
  begin
    case IndexStr(LOp, ['=', '<>', '!=', '>', '<', '>=', '<=']) of
      0:    Result := LLhs = LRhsNum;
      1, 2: Result := LLhs <> LRhsNum;
      3:    Result := LLhs > LRhsNum;
      4:    Result := LLhs < LRhsNum;
      5:    Result := LLhs >= LRhsNum;
      6:    Result := LLhs <= LRhsNum;
    end;
  end
  else
  begin
    case IndexStr(LOp, ['=', '<>', '!=', '>', '<', '>=', '<=']) of
      0:    Result := SameText(LLhsStr, LRhs);
      1, 2: Result := not SameText(LLhsStr, LRhs);
      3:    Result := CompareText(LLhsStr, LRhs) > 0;
      4:    Result := CompareText(LLhsStr, LRhs) < 0;
      5:    Result := CompareText(LLhsStr, LRhs) >= 0;
      6:    Result := CompareText(LLhsStr, LRhs) <= 0;
    end;
  end;
end;

{ TAiToolParams }

class function TAiToolParams.IsReserved(const APropName: string): Boolean;
var
  S: string;
begin
  for S in AI_TOOL_RESERVED_PROPS do
    if SameText(S, APropName) then
      Exit(True);
  Result := False;
end;

class function TAiToolParams.ToJSON(ATool: TAiToolBase): TJSONObject;
var
  LContext: TRttiContext;
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  LValue: TValue;
begin
  Result := TJSONObject.Create;
  if not Assigned(ATool) then
    Exit;

  LContext := TRttiContext.Create;
  try
    LRttiType := LContext.GetType(ATool.ClassType);
    for LProp in LRttiType.GetProperties do
    begin
      // We only care about the properties that can be read and written
      if not(LProp.IsReadable and LProp.IsWritable and (LProp.Visibility = mvPublished)) then
        Continue;

      // Component infrastructure, not tool parameters (M-04)
      if IsReserved(LProp.Name) then
        Continue;

      // Properties marked [TSecret] are never written to disk (M-05)
      if LProp.HasAttribute<TSecretAttribute> then
        Continue;

      LValue := LProp.GetValue(ATool);
      if LValue.IsEmpty then
        Continue;

      // Convert the TValue to a JSON-compatible type
      case LValue.Kind of
        tkInteger, tkInt64:
          Result.AddPair(LProp.Name, TJSONNumber.Create(LValue.AsInt64));
        tkFloat:
          Result.AddPair(LProp.Name, TJSONNumber.Create(LValue.AsExtended));
        tkString, tkUString, tkLString, tkWString:
          Result.AddPair(LProp.Name, TJSONString.Create(LValue.AsString));
        tkEnumeration:
          if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            Result.AddPair(LProp.Name, TJSONBool.Create(LValue.AsBoolean))
          else // Store other enums by their text name
            Result.AddPair(LProp.Name, TJSONString.Create(GetEnumName(LProp.PropertyType.Handle, LValue.AsOrdinal)));
      end;
    end;
  finally
    LContext.Free;
  end;
end;

class procedure TAiToolParams.FromJSON(ATool: TAiToolBase; AJson: TJSONObject);
var
  LContext: TRttiContext;
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  LValue: TValue;
  LPair: TJSONPair;
  LJsonValue: TJSONValue;
  OrdValue: Integer;
begin
  if not Assigned(ATool) or not Assigned(AJson) then
    Exit;

  LContext := TRttiContext.Create;
  try
    LRttiType := LContext.GetType(ATool.ClassType);
    for LPair in AJson do
    begin
      LProp := LRttiType.GetProperty(LPair.JsonString.Value);
      if Assigned(LProp) and LProp.IsWritable then
      begin
        // Component infrastructure: ignored when reading (M-04)
        if IsReserved(LProp.Name) then
          Continue;

        // A tampered file cannot inject credentials: incoming
        // values for [TSecret] properties are ignored (M-05)
        if LProp.HasAttribute<TSecretAttribute> then
          Continue;

        LJsonValue := LPair.JsonValue;
        LValue := TValue.Empty; // Initialize

        // Origin-tolerant: accepts the native JSON type or its string
        // representation (editor graph JSONs usually carry everything as text)
        case LProp.PropertyType.TypeKind of
          tkInteger:
            if LJsonValue is TJSONNumber then
              LValue := TValue.From<Integer>(TJSONNumber(LJsonValue).AsInt)
            else
              LValue := TValue.From<Integer>(StrToIntDef(LJsonValue.Value, 0));
          tkInt64:
            if LJsonValue is TJSONNumber then
              LValue := TValue.From<Int64>(TJSONNumber(LJsonValue).AsInt64)
            else
              LValue := TValue.From<Int64>(StrToInt64Def(LJsonValue.Value, 0));
          tkFloat:
            if LJsonValue is TJSONNumber then
              LValue := TValue.From<Double>(TJSONNumber(LJsonValue).AsDouble)
            else
              LValue := TValue.From<Double>(StrToFloatDef(LJsonValue.Value, 0.0, TFormatSettings.Invariant));
          tkString, tkUString, tkLString, tkWString:
            LValue := TValue.From<string>(LJsonValue.Value);
          tkEnumeration:
            if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            begin
              if LJsonValue is TJSONBool then
                LValue := TValue.From<Boolean>(TJSONBool(LJsonValue).AsBoolean)
              else
                LValue := TValue.From<Boolean>(SameText(LJsonValue.Value, 'true'));
            end
            else
            begin
              OrdValue := GetEnumValue(LProp.PropertyType.Handle, LJsonValue.Value);
              if OrdValue >= 0 then
                LValue := TValue.FromOrdinal(LProp.PropertyType.Handle, OrdValue);
            end;
        end;

        if not LValue.IsEmpty then
          LProp.SetValue(ATool, LValue);
      end;
    end;
  finally
    LContext.Free;
  end;
end;

class function TAiToolParams.SchemaOf(AToolClass: TClass): TJSONObject;
var
  LContext: TRttiContext;
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  LPropsObj, LPropSchema: TJSONObject;
  LEnumArr: TJSONArray;
  LParamAttr: TToolParameterAttribute;
  LSecretAttr: TSecretAttribute;
  LTypeData: PTypeData;
  i: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  LPropsObj := TJSONObject.Create;
  Result.AddPair('properties', LPropsObj);
  if not Assigned(AToolClass) then
    Exit;

  LContext := TRttiContext.Create;
  try
    LRttiType := LContext.GetType(AToolClass);
    for LProp in LRttiType.GetProperties do
    begin
      if not(LProp.IsReadable and LProp.IsWritable and (LProp.Visibility = mvPublished)) then
        Continue;
      if IsReserved(LProp.Name) then
        Continue;

      LPropSchema := TJSONObject.Create;

      case LProp.PropertyType.TypeKind of
        tkInteger, tkInt64:
          LPropSchema.AddPair('type', 'integer');
        tkFloat:
          LPropSchema.AddPair('type', 'number');
        tkString, tkUString, tkLString, tkWString:
          LPropSchema.AddPair('type', 'string');
        tkEnumeration:
          if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            LPropSchema.AddPair('type', 'boolean')
          else
          begin
            LPropSchema.AddPair('type', 'string');
            LEnumArr := TJSONArray.Create;
            LTypeData := GetTypeData(LProp.PropertyType.Handle);
            for i := LTypeData^.MinValue to LTypeData^.MaxValue do
              LEnumArr.Add(GetEnumName(LProp.PropertyType.Handle, i));
            LPropSchema.AddPair('enum', LEnumArr);
          end;
      else
        begin
          // Type not supported by the mapper: it does not appear in the schema
          LPropSchema.Free;
          Continue;
        end;
      end;

      // Presentation metadata of the [TToolParameter] attribute
      LParamAttr := LProp.GetAttribute<TToolParameterAttribute>;
      if Assigned(LParamAttr) then
      begin
        if LParamAttr.DisplayName <> '' then
          LPropSchema.AddPair('title', LParamAttr.DisplayName);
        if LParamAttr.Hint <> '' then
          LPropSchema.AddPair('description', LParamAttr.Hint);
        if LParamAttr.DefaultValue <> '' then
          LPropSchema.AddPair('default', LParamAttr.DefaultValue);
      end;

      // [TSecret] properties DO appear in the schema, marked writeOnly, so
      // an editor shows a credential selector and not a text field
      LSecretAttr := LProp.GetAttribute<TSecretAttribute>;
      if Assigned(LSecretAttr) then
      begin
        LPropSchema.AddPair('writeOnly', TJSONBool.Create(True));
        LPropSchema.AddPair('x-credential-type', LSecretAttr.CredentialType);
      end;

      LPropsObj.AddPair(LProp.Name, LPropSchema);
    end;
  finally
    LContext.Free;
  end;
end;

// Typed format: each entry is {"t":"<type>","v":<value>}
// Types: "s"=string, "i"=integer, "i64"=int64, "f"=float, "b"=boolean, "e"=enum (ordinal as integer)
procedure SerializeBlackboard(ABlackboard: TAIBlackboard; AJSONObject: TJSONObject);
var
  LPair: TPair<string, TValue>;
  LWrapper: TJSONObject;
begin
  ABlackboard.FLock.Enter;
  try
    for LPair in ABlackboard.FData do
    begin
      var LValue := LPair.Value;
      LWrapper := nil;
      case LValue.Kind of
        tkInteger:
          begin
            LWrapper := TJSONObject.Create;
            LWrapper.AddPair('t', 'i');
            LWrapper.AddPair('v', TJSONNumber.Create(LValue.AsInteger));
          end;
        tkInt64:
          begin
            LWrapper := TJSONObject.Create;
            LWrapper.AddPair('t', 'i64');
            LWrapper.AddPair('v', TJSONNumber.Create(LValue.AsInt64));
          end;
        tkFloat:
          begin
            LWrapper := TJSONObject.Create;
            LWrapper.AddPair('t', 'f');
            LWrapper.AddPair('v', TJSONNumber.Create(LValue.AsExtended));
          end;
        tkString, tkUString:
          begin
            LWrapper := TJSONObject.Create;
            LWrapper.AddPair('t', 's');
            LWrapper.AddPair('v', TJSONString.Create(LValue.AsString));
          end;
        tkEnumeration:
          begin
            LWrapper := TJSONObject.Create;
            if LValue.TypeInfo = System.TypeInfo(Boolean) then
            begin
              LWrapper.AddPair('t', 'b');
              LWrapper.AddPair('v', TJSONBool.Create(LValue.AsBoolean));
            end
            else
            begin
              LWrapper.AddPair('t', 'e');
              LWrapper.AddPair('v', TJSONNumber.Create(LValue.AsOrdinal));
            end;
          end;
      end;
      if Assigned(LWrapper) then
        AJSONObject.AddPair(LPair.Key, LWrapper);
    end;
  finally
    ABlackboard.FLock.Leave;
  end;
end;

procedure DeserializeBlackboard(AJSONObject: TJSONObject; ABlackboard: TAIBlackboard);
var
  LPair: TJSONPair;
  LWrapper: TJSONObject;
  LType, LKey: string;
  LVal: TJSONValue;
begin
  ABlackboard.Clear;
  for LPair in AJSONObject do
  begin
    LKey := LPair.JsonString.Value;
    if not (LPair.JsonValue is TJSONObject) then
      Continue;
    LWrapper := LPair.JsonValue as TJSONObject;
    if not LWrapper.TryGetValue<string>('t', LType) then
      Continue;
    LVal := LWrapper.GetValue('v');
    if not Assigned(LVal) then
      Continue;
    if LType = 's' then
      ABlackboard.SetString(LKey, LVal.Value)
    else if LType = 'i' then
      ABlackboard.SetInteger(LKey, (LVal as TJSONNumber).AsInt)
    else if LType = 'i64' then
      ABlackboard.SetValue(LKey, TValue.From<Int64>((LVal as TJSONNumber).AsInt64))
    else if LType = 'f' then
      ABlackboard.SetValue(LKey, TValue.From<Double>((LVal as TJSONNumber).AsDouble))
    else if LType = 'b' then
      ABlackboard.SetBoolean(LKey, (LVal as TJSONBool).AsBoolean)
    else if LType = 'e' then
      ABlackboard.SetInteger(LKey, (LVal as TJSONNumber).AsInt);
  end;
end;

{ TAIBlackboard }

procedure TAIBlackboard.Clear;
var
  LValue: TValue;
  LMsg: TAiChatMessage;
begin
  FLock.Enter;
  try
    // 1. Find and Free AskMsg
    // We use the internal keys defined in the Getters/Setters ('Sys.AskMsg')
    if FData.TryGetValue('Sys.AskMsg', LValue) then
    begin
      LMsg := TAiChatMessage(LValue.AsObject);

      // We check whether it is a valid object before freeing
      if LValue.IsObject and Assigned(LMsg) then
        LMsg.Free;
    end;

    // 2. Find and Free ResMsg
    if FData.TryGetValue('Sys.ResMsg', LValue) then
    begin
      LMsg := TAiChatMessage(LValue.AsObject);

      if LValue.IsObject and Assigned(LMsg) then
        LMsg.Free;
    end;

    // 3. Clear the dictionary (removes the keys and pointers)
    FData.Clear;
  finally
    FLock.Leave;
  end;
end;

constructor TAIBlackboard.Create;
begin
  inherited;
  FData := TDictionary<string, TValue>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TAIBlackboard.Destroy;
begin
  Clear;
  FData.Free;
  FLock.Free;
  inherited;
end;

function TAIBlackboard.GetAskMsg: TAiChatMessage;
var
  Val: TValue;
begin
  // We use TryGetValue which is already Thread-Safe (it has its own FLock)
  // 'Sys.AskMsg' is the internal key where we store the object
  if TryGetValue('Sys.AskMsg', Val) and (not Val.IsEmpty) then
    Result := Val.AsType<TAiChatMessage>
  else
    Result := nil;
end;

function TAIBlackboard.GetBoolean(const AKey: string; const ADefault: Boolean): Boolean;
var
  LValue: TValue;
begin
  if TryGetValue(AKey, LValue) and LValue.IsType<Boolean> then
    Result := LValue.AsBoolean
  else
    Result := ADefault;
end;

function TAIBlackboard.GetInteger(const AKey: string; const ADefault: Integer): Integer;
var
  LValue: TValue;
begin
  if TryGetValue(AKey, LValue) and LValue.IsType<Integer> then
    Result := LValue.AsInteger
  else
    Result := ADefault;
end;

function TAIBlackboard.GetResMsg: TAiChatMessage;
var
  Val: TValue;
begin
  if TryGetValue('Sys.ResMsg', Val) and (not Val.IsEmpty) then
    Result := Val.AsType<TAiChatMessage>
  else
    Result := nil;
end;

function TAIBlackboard.GetStatus: TAgentExecutionStatus;
var
  Val: TValue;
begin
  // We retrieve the Enum, or return esUnknown if it does not exist
  if TryGetValue('Execution.Status', Val) then
    Result := Val.AsType<TAgentExecutionStatus>
  else
    Result := esUnknown;
end;

function TAIBlackboard.GetString(const AKey, ADefault: string): string;
var
  LValue: TValue;
begin
  if TryGetValue(AKey, LValue) and LValue.IsType<string> then
    Result := LValue.AsString
  else
    Result := ADefault;
end;

procedure TAIBlackboard.FreeOwnedObject(const AKey: string; ANew: TObject);
var
  LOld: TValue;
begin
  // The blackboard owns AskMsg/ResMsg: Clear frees them. But SetValue
  // only does AddOrSetValue and does not free the previous object, so reassigning
  // without going through Clear lost the previous instance. It showed when reusing a
  // manager for several runs: Run assigns ResMsg unconditionally and, since
  // Compile no longer clears the blackboard (M-03), nothing freed the previous one.
  FLock.Enter;
  try
    if FData.TryGetValue(AKey, LOld) and LOld.IsObject then
    begin
      if (LOld.AsObject <> nil) and (LOld.AsObject <> ANew) then
        LOld.AsObject.Free;
      FData.Remove(AKey);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAIBlackboard.SetAskMsg(const Value: TAiChatMessage);
begin
  FreeOwnedObject('Sys.AskMsg', Value);
  // SetValue is also Thread-Safe
  SetValue('Sys.AskMsg', TValue.From(Value));
end;

procedure TAIBlackboard.SetBoolean(const AKey: string; AValue: Boolean);
begin
  SetValue(AKey, AValue);
end;

procedure TAIBlackboard.SetInteger(const AKey: string; AValue: Integer);
begin
  SetValue(AKey, AValue);
end;

procedure TAIBlackboard.SetResMsg(const Value: TAiChatMessage);
begin
  FreeOwnedObject('Sys.ResMsg', Value);
  SetValue('Sys.ResMsg', TValue.From(Value));
end;

procedure TAIBlackboard.SetStatus(Value: TAgentExecutionStatus);
begin
  // We store the Enum inside the TValue
  SetValue('Execution.Status', TValue.From(Value));
end;

procedure TAIBlackboard.SetString(const AKey, AValue: string);
begin
  SetValue(AKey, AValue);
end;

procedure TAIBlackboard.SetValue(const AKey: string; const AValue: TValue);
begin
  FLock.Enter;
  try
    FData.AddOrSetValue(AKey, AValue);
  finally
    FLock.Leave;
  end;
end;

function TAIBlackboard.TryGetValue(const AKey: string; out AValue: TValue): Boolean;
begin
  FLock.Enter;
  try
    Result := FData.TryGetValue(AKey, AValue);
  finally
    FLock.Leave;
  end;
end;

{ TAIAgents }

procedure TAIAgentManager.Abort;
begin
  FAbort := True;
end;

function TAIAgentManager.GetBusy: Boolean;
begin
  Result := FBusy <> 0;
end;

function TAIAgentManager.AddEdge(const AStartNodeName, AEndNodeName: string): TAIAgentManager;
var
  StartNode, EndNode: TAIAgentsNode;
  Link: TAIAgentsLink;
begin
  FCompiled := False;
  StartNode := FindNode(AStartNodeName);
  EndNode := FindNode(AEndNodeName);
  if not Assigned(StartNode) then
    raise Exception.CreateFmt('Edge creation failed: Start node "%s" not found.', [AStartNodeName]);
  if not Assigned(EndNode) then
    raise Exception.CreateFmt('Edge creation failed: End node "%s" not found.', [AEndNodeName]);

  Link := TAIAgentsLink.Create(Self);
  Link.Name := 'Link_' + AStartNodeName + '_to_' + AEndNodeName;
  Link.Graph := Self;
  Link.Mode := lmFanout;
  StartNode.Next := Link;
  Link.NextA := EndNode;
  Result := Self;
end;

function TAIAgentManager.AddMessageAndRun(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String;
begin
  // We configure the message in the Blackboard
  Blackboard.AskMsg := NewMessage(APrompt, aRole, aMediaFiles);

  // We call Run, which will handle the Sync/Async logic
  Result := Run(APrompt);
end;

function TAIAgentManager.AddMessageAndRunMsg(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;
begin
  if FAsynchronous then
    raise Exception.Create('AddMessageAndRunMsg is only compatible with Asynchronous = False (Synchronous mode).');

  // We execute (this waits for completion)
  AddMessageAndRun(APrompt, aRole, aMediaFiles);

  // We return the complete object from the Blackboard
  Result := Blackboard.ResMsg;
end;

function TAIAgentManager.AddNode(const AName: string; AExecuteProc: TAIAgentsNodeOnExecute): TAIAgentManager;
var
  Node: TAIAgentsNode;
begin
  FCompiled := False;
  if FindNode(AName) <> nil then
    raise Exception.CreateFmt('A node with the name "%s" already exists.', [AName]);

  Node := TAIAgentsNode.Create(Self);
  Node.Name := AName;
  Node.Graph := Self;
  Node.OnExecute := AExecuteProc;
  Result := Self;
end;

procedure TAIAgentManager.AddComponentToList(AComponent: TAIAgentsBase);
begin
  if (AComponent is TAIAgentsNode) and Assigned(FNodes) then
  begin
    if FNodes.IndexOf(TAIAgentsNode(AComponent)) = -1 then
      FNodes.Add(TAIAgentsNode(AComponent));
  end
  else if (AComponent is TAIAgentsLink) and Assigned(FLinks) then
  begin
    if FLinks.IndexOf(TAIAgentsLink(AComponent)) = -1 then
      FLinks.Add(TAIAgentsLink(AComponent));
  end;
end;

function TAIAgentManager.AddConditionalEdge(const AStartNodeName, AConditionalLinkName: string; AConditionalTargets: TDictionary<string, string>): TAIAgentManager;
var
  StartNode, TargetNode: TAIAgentsNode;
  Link: TAIAgentsLink;
  DecisionKey, TargetNodeName: string;
begin
  FCompiled := False;
  StartNode := FindNode(AStartNodeName);
  if not Assigned(StartNode) then
    raise Exception.CreateFmt('Conditional edge creation failed: Start node "%s" not found.', [AStartNodeName]);

  Link := TAIAgentsLink.Create(Self);
  Link.Name := AConditionalLinkName;
  Link.Graph := Self;
  Link.Mode := lmConditional;

  for DecisionKey in AConditionalTargets.Keys do
  begin
    TargetNodeName := AConditionalTargets.Items[DecisionKey];
    TargetNode := FindNode(TargetNodeName);
    if not Assigned(TargetNode) then
      raise Exception.CreateFmt('Conditional edge creation failed: Target node "%s" for decision "%s" not found.', [TargetNodeName, DecisionKey]);
    Link.AddConditionalTarget(DecisionKey, TargetNode);
  end;

  StartNode.Next := Link;
  Result := Self;
end;

procedure TAIAgentManager.ClearGraph;
begin
  FStartNode := nil;
  FEndNode := nil;
  FNodes.Clear;
  FLinks.Clear;
  for var i := ComponentCount - 1 downto 0 do
  begin
    if Components[i] is TAIAgentsBase then
      Components[i].Free;
  end;
  FCompiled := False;
end;

procedure TAIAgentManager.Compile;
var
  Node: TAIAgentsNode;
  Link: TAIAgentsLink;
  TargetNode: TAIAgentsNode;
  StartCount, EndCount: Integer;
begin
  if FCompiled then
    Exit;
  try
    // Compile only validates and builds the structure (InEdges). The execution
    // state (blackboard, messages) is NOT touched here: clearing it freed the
    // AskMsg/ResMsg seeded by Run before the first run (M-03).
    // For an explicit state reset use ResetExecutionState.
    if not Assigned(FStartNode) then
      raise Exception.Create('StartNode is not assigned.');
    if not Assigned(FEndNode) then
      raise Exception.Create('EndNode is not assigned.');

    StartCount := 0;
    EndCount := 0;
    for Node in FNodes do
    begin
      if Node = FStartNode then
        Inc(StartCount);
      if Node = FEndNode then
        Inc(EndCount);
      Node.Reset;
    end;
    if StartCount <> 1 then
      raise Exception.CreateFmt('Invalid number of StartNode references: %d (expected 1).', [StartCount]);
    if EndCount <> 1 then
      raise Exception.CreateFmt('Invalid number of EndNode references: %d (expected 1).', [EndCount]);

    for Link in FLinks do
    begin
      Link.Ready := False;
      Link.NoCycles := 0;
      if not Assigned(Link.FSourceNode) then
        raise Exception.CreateFmt('Link "%s" is not connected from any source node.', [Link.Name]);

      if Assigned(Link.NextA) then
        Link.NextA.FInEdges.Add(Link);
      if Assigned(Link.NextB) then
        Link.NextB.FInEdges.Add(Link);
      if Assigned(Link.NextC) then
        Link.NextC.FInEdges.Add(Link);
      if Assigned(Link.NextD) then
        Link.NextD.FInEdges.Add(Link);
      if Assigned(Link.NextNo) then
        Link.NextNo.FInEdges.Add(Link);

      if Assigned(Link.FConditionalTargets) then
      begin
        for TargetNode in Link.FConditionalTargets.Values do
          TargetNode.FInEdges.Add(Link);
      end;
    end;
    FCompiled := True;
  except
    on E: Exception do
    begin
      DoError(nil, nil, E);
      raise;
    end;
  end;
end;

procedure TAIAgentManager.ResetExecutionState;
var
  Node: TAIAgentsNode;
  Link: TAIAgentsLink;
begin
  // Explicit reset of the execution state, separate from Compile (M-03).
  // Clears the blackboard (frees AskMsg/ResMsg) and the transient state of
  // nodes and links; it does NOT touch the graph structure or FCompiled.
  FAbort := False;
  FBlackboard.Clear;
  for Node in FNodes do
    Node.ResetExecutionState;
  for Link in FLinks do
  begin
    Link.Ready := False;
    Link.NoCycles := 0;
  end;
end;

constructor TAIAgentManager.Create(aOwner: TComponent);
begin
  inherited;
  FBlackboard := TAIBlackboard.Create;
  FNodes := TList<TAIAgentsNode>.Create;
  FLinks := TList<TAIAgentsLink>.Create;
  FActiveTasks := TList<ITask>.Create;
  FActiveTasksLock := TCriticalSection.Create;
  FCompiled := False;
  FAsynchronous := True; // Default VCL behavior
  FBusy := 0;

  // --- NEW: Scheduler initialization ---
  FMaxConcurrentTasks := 4;
  FTimeoutMs := 60000;
  FThreadPool := TThreadPool.Create;
  FThreadPool.SetMaxWorkerThreads(FMaxConcurrentTasks);

  // --- Durable execution ---
  FSuspendedSteps     := TObjectList<TAiPendingStep>.Create(True);
  FSuspendedStepsLock := TCriticalSection.Create;
  FCheckpointer       := nil;
  FCurrentThreadID    := '';
  FCheckpointSeq      := 0;
end;

destructor TAIAgentManager.Destroy;
begin
  FSuspendedSteps.Free;
  FSuspendedStepsLock.Free;
  FActiveTasks.Free;
  FActiveTasksLock.Free;
  FThreadPool.Free; // --- NEW: Scheduler release ---
  FBlackboard.Free;
  inherited;
  FreeAndNil(FNodes);
  FreeAndNil(FLinks);
end;

procedure TAIAgentManager.DoError(Node: TAIAgentsNode; Link: TAIAgentsLink; E: Exception);
var
  LAbort: Boolean;
  ErrorMsg: String;
  AggE: EAggregateException;
  I: Integer;
begin
  // Extract the real message: if it is an EAggregateException (failed parallel branch),
  // expose the inner errors' messages instead of "One or more occurred".
  if (E is EAggregateException) then
  begin
    AggE := EAggregateException(E);
    if AggE.Count > 0 then
    begin
      ErrorMsg := '';
      for I := 0 to AggE.Count - 1 do
      begin
        if I > 0 then ErrorMsg := ErrorMsg + ' | ';
        ErrorMsg := ErrorMsg + AggE.InnerExceptions[I].Message;
      end;
    end
    else
      ErrorMsg := E.Message;
  end
  else
    ErrorMsg := E.Message;

  Blackboard.SetStatus(esError);
  Blackboard.SetString('Execution.ErrorMessage', ErrorMsg);

  LAbort := True;
  if Assigned(FOnError) then
    FOnError(Self, Node, Link, E, LAbort);

  if LAbort then
    Abort;
end;

function TAIAgentManager.DoConfirm(Node: TAIAgentsNode; const AQuestion: string; Buttons: TMsgStates; var AResponse: string): TMsgState;
begin
  Result := msCancel;
  if Assigned(FOnConfirm) then
    FOnConfirm(Self, Node, AQuestion, Buttons, AResponse, Result)
  else
  begin
    DoError(Node, nil, Exception.Create('User confirmation required, but OnConfirm event is not assigned.'));
    Result := msAbort;
  end;
end;

procedure TAIAgentManager.DoPrint(Sender: TObject; Value: String);
begin
  if Assigned(FOnPrint) then
    FOnPrint(Sender, Value);
end;

procedure TAIAgentManager.DoPrintFromRef(Sender: TObject; Value: String);
begin
  if Assigned(FOnPrintRef) then
    FOnPrintRef(Sender, Value);
end;

function TAIAgentManager.FindNode(const AName: string): TAIAgentsNode;
var
  i: Integer;
  Node: TAIAgentsNode;
begin
  Result := nil;

  // Search the nodes registered in the graph (Graph := Self). Covers the case
  // of nodes placed on a Form/DataModule, whose Owner is NOT the manager.
  for Node in FNodes do
    if SameText(Node.Name, AName) then
      Exit(Node);

  // Fallback: nodes created with the manager as Owner before Graph was assigned
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TAIAgentsNode) and SameText(Components[i].Name, AName) then
    begin
      Result := TAIAgentsNode(Components[i]);
      Exit;
    end;
end;

// Make sure you have these units in the implementation's 'uses' clause:
// System.JSON, System.JSON.Types, System.Rtti, System.TypInfo, uEngineRegistry

// ... (The DeserializeToolProperties helper and the TAgentHandlerRegistry class stay as before) ...

// -----------------------------------------------------------------------------
// FINAL IMPLEMENTATION OF TAIAgentManager.LoadFromStream
// -----------------------------------------------------------------------------
procedure TAIAgentManager.LoadFromStream(AStream: TStream);
var
  LRoot, LGraphJSON, LNodeJSON, LLinkJSON, LTargetsJSON: TJSONObject;
  LNodesArray, LLinksArray: TJSONArray;
  LReader: TStreamReader;
  LJsonValue: TJSONValue;
  LNode: TAIAgentsNode;
  LLink: TAIAgentsLink;
  LNodeMap: TDictionary<string, TAIAgentsNode>;
  LLinkMap: TDictionary<string, TAIAgentsLink>;
  LKey: string;
  LToolClass: TClass; // Variable to store the tool's class type
begin
  if not Assigned(AStream) or (AStream.Size = 0) then
    Exit;

  ClearGraph;

  LNodeMap := TDictionary<string, TAIAgentsNode>.Create;
  LLinkMap := TDictionary<string, TAIAgentsLink>.Create;
  LReader := TStreamReader.Create(AStream, TEncoding.UTF8);
  try
    LJsonValue := TJSONObject.ParseJSONValue(LReader.ReadToEnd);
    if not Assigned(LJsonValue) or not(LJsonValue is TJSONObject) then
      raise Exception.Create('Invalid JSON format: root is not an object.');
    LRoot := LJsonValue as TJSONObject;
    try
      // =======================================================================
      // PASS 1: CREATE ALL NODE AND LINK INSTANCES
      // =======================================================================

      // --- 1.A: Create Nodes ---
      LNodesArray := LRoot.GetValue('nodes') as TJSONArray;
      if Assigned(LNodesArray) then
      begin
        for LJsonValue in LNodesArray do
        begin
          LNodeJSON := LJsonValue as TJSONObject;
          LKey := LNodeJSON.GetValue<string>('name', '');
          if LKey = '' then
            raise Exception.Create('Node found without a name in JSON.');
          if LNodeMap.ContainsKey(LKey) then
            raise Exception.CreateFmt('Duplicate node name found in JSON: "%s"', [LKey]);

          LNode := TAIAgentsNode.Create(Self);
          LNode.Name := LKey;
          LNode.Description := LNodeJSON.GetValue<string>('description', '');
          LNode.PromptName := LNodeJSON.GetValue<string>('promptName', '');

          var
          LJoinModeStr := LNodeJSON.GetValue<string>('joinMode', 'jmAny');
          LNode.JoinMode := TJoinMode(GetEnumValue(TypeInfo(TJoinMode), LJoinModeStr));

          // --- CORRECTED SECTION ---
          var
          LToolValue := LNodeJSON.GetValue('tool');
          if Assigned(LToolValue) and (LToolValue is TJSONObject) then
          begin
            var
            LToolDataObj := LToolValue as TJSONObject;
            var
            LToolClassName := LToolDataObj.GetValue<string>('className');
            if LToolClassName <> '' then
            begin
              // 1. Look up the class TYPE in YOUR registry
              LToolClass := TEngineRegistry.Instance.FindToolClass(LToolClassName);

              // 2. If found, create an instance of that class
              if Assigned(LToolClass) and LToolClass.InheritsFrom(TAiToolBase) then
              begin
                // We create the instance using the NODE as owner
                LNode.Tool := TAiToolBase(LToolClass).Create(LNode);

                // 3. Deserialize the properties into the new instance
                var
                LPropertiesJSON := LToolDataObj.GetValue('properties') as TJSONObject;
                if Assigned(LPropertiesJSON) then
                  TAiToolParams.FromJSON(LNode.Tool, LPropertiesJSON);
              end;
            end;
          end;
          // --- END OF THE CORRECTION ---

          LNodeMap.Add(LKey, LNode);
        end;
      end;

      // --- 1.B: Create Links --- (Unchanged)
      LLinksArray := LRoot.GetValue('links') as TJSONArray;
      if Assigned(LLinksArray) then
      begin
        for LJsonValue in LLinksArray do
        begin
          LLinkJSON := LJsonValue as TJSONObject;
          LKey := LLinkJSON.GetValue<string>('name', '');
          if LKey = '' then
            raise Exception.Create('Link found without a name in JSON.');
          if LLinkMap.ContainsKey(LKey) then
            raise Exception.CreateFmt('Duplicate link name found in JSON: "%s"', [LKey]);

          LLink := TAIAgentsLink.Create(Self);
          LLink.Name := LKey;
          LLink.Description := LLinkJSON.GetValue<string>('description', '');
          LLink.MaxCycles := LLinkJSON.GetValue<Integer>('maxCycles', 1);

          var
          LLinkModeStr := LLinkJSON.GetValue<string>('mode', 'lmFanout');
          LLink.Mode := TLinkMode(GetEnumValue(TypeInfo(TLinkMode), LLinkModeStr));

          if LLink.Mode = lmConditional then
            LLink.ConditionalKey := LLinkJSON.GetValue<string>('conditionalKey', 'next_route');

          if LLink.Mode = lmExpression then
          begin
            var
            LExpressionsJSON := LLinkJSON.GetValue('expressions') as TJSONObject;
            if Assigned(LExpressionsJSON) then
            begin
              LLink.ExpressionA := LExpressionsJSON.GetValue<string>('expressionA', '');
              LLink.ExpressionB := LExpressionsJSON.GetValue<string>('expressionB', '');
              LLink.ExpressionC := LExpressionsJSON.GetValue<string>('expressionC', '');
              LLink.ExpressionD := LExpressionsJSON.GetValue<string>('expressionD', '');
            end;
          end;

          LLinkMap.Add(LKey, LLink);
        end;
      end;

      // =======================================================================
      // PASS 2: CONNECT EVERYTHING (Unchanged)
      // =======================================================================

      if Assigned(LNodesArray) then
      begin
        for LJsonValue in LNodesArray do
        begin
          LNodeJSON := LJsonValue as TJSONObject;
          LNode := LNodeMap[LNodeJSON.GetValue<string>('name')];
          var
          LNextLinkName := LNodeJSON.GetValue<string>('nextLink', '');
          if (LNextLinkName <> '') and LLinkMap.TryGetValue(LNextLinkName, LLink) then
            LNode.Next := LLink;
          var
          LHandlerName := LNodeJSON.GetValue<string>('onExecuteHandler', '');
          if LHandlerName <> '' then
            LNode.OnExecute := TAgentHandlerRegistry.Instance.FindNodeHandler(LHandlerName);
        end;
      end;

      if Assigned(LLinksArray) then
      begin
        for LJsonValue in LLinksArray do
        begin
          LLinkJSON := LJsonValue as TJSONObject;
          LLink := LLinkMap[LLinkJSON.GetValue<string>('name')];
          var
          LSourceNodeName := LLinkJSON.GetValue<string>('sourceNode', '');
          if (LSourceNodeName <> '') and LNodeMap.TryGetValue(LSourceNodeName, LNode) then
            LLink.FSourceNode := LNode;
          LTargetsJSON := LLinkJSON.GetValue('targets') as TJSONObject;
          if Assigned(LTargetsJSON) then
          begin
            if LNodeMap.TryGetValue(LTargetsJSON.GetValue<string>('nextA', ''), LNode) then
              LLink.NextA := LNode;
            if LNodeMap.TryGetValue(LTargetsJSON.GetValue<string>('nextB', ''), LNode) then
              LLink.NextB := LNode;
            if LNodeMap.TryGetValue(LTargetsJSON.GetValue<string>('nextC', ''), LNode) then
              LLink.NextC := LNode;
            if LNodeMap.TryGetValue(LTargetsJSON.GetValue<string>('nextD', ''), LNode) then
              LLink.NextD := LNode;
            if LNodeMap.TryGetValue(LTargetsJSON.GetValue<string>('nextNo', ''), LNode) then
              LLink.NextNo := LNode;
          end;
          var
          LCondTargetsJSON := LLinkJSON.GetValue('conditionalTargets') as TJSONObject;
          if Assigned(LCondTargetsJSON) then
          begin
            for var LPair in LCondTargetsJSON do
            begin
              var
              LTargetNodeName := LPair.JsonValue.Value;
              if LNodeMap.TryGetValue(LTargetNodeName, LNode) then
                LLink.AddConditionalTarget(LPair.JsonString.Value, LNode);
            end;
          end;
        end;
      end;

      // =======================================================================
      // FINAL STEP: CONFIGURE GRAPH (Unchanged)
      // =======================================================================
      LGraphJSON := LRoot.GetValue('graph') as TJSONObject;
      if Assigned(LGraphJSON) then
      begin
        Self.Description := LGraphJSON.GetValue<string>('description', '');
        Self.MaxConcurrentTasks := LGraphJSON.GetValue<Integer>('maxConcurrentTasks', 4);
        Self.TimeoutMs := LGraphJSON.GetValue<Cardinal>('timeoutMs', 60000);
        var
        LStartNodeName := LGraphJSON.GetValue<string>('startNode', '');
        if (LStartNodeName <> '') and LNodeMap.TryGetValue(LStartNodeName, LNode) then
          Self.StartNode := LNode;
        var
        LEndNodeName := LGraphJSON.GetValue<string>('endNode', '');
        if (LEndNodeName <> '') and LNodeMap.TryGetValue(LEndNodeName, LNode) then
          Self.EndNode := LNode;
      end;
      FCompiled := False;
    finally
      LRoot.Free;
    end;
  finally
    LReader.Free;
    LLinkMap.Free;
    LNodeMap.Free;
  end;
end;

procedure TAIAgentManager.LoadStateFromStream(AStream: TStream);
var
  LRoot, LStateObj, LBlackboardObj, LNodeStatesObj, LLinkStatesObj, LNodeStateObj, LJoinInputsObj: TJSONObject;
  LReader: TStreamReader;
  LJsonValue: TJSONValue;
  LNode: TAIAgentsNode;
  LLink: TAIAgentsLink;
  LPair: TJSONPair;
  LLinkMap: TDictionary<string, TAIAgentsLink>; // Temporary map to look links up by name
begin
  if ComponentCount = 0 then
    raise Exception.Create('Cannot load state into an empty graph. Load the graph structure first.');

  // Create the link map for a fast lookup
  LLinkMap := TDictionary<string, TAIAgentsLink>.Create;
  for var i := 0 to ComponentCount - 1 do
    if Components[i] is TAIAgentsLink then
      LLinkMap.Add(Components[i].Name, TAIAgentsLink(Components[i]));

  LReader := TStreamReader.Create(AStream, TEncoding.UTF8);
  try
    LJsonValue := TJSONObject.ParseJSONValue(LReader.ReadToEnd);
    LRoot := LJsonValue as TJSONObject;
    try
      LStateObj := LRoot.GetValue('executionState') as TJSONObject;
      if not Assigned(LStateObj) then
        Exit;

      // 1. Restore the Blackboard
      LBlackboardObj := LStateObj.GetValue('blackboard') as TJSONObject;
      if Assigned(LBlackboardObj) then
        DeserializeBlackboard(LBlackboardObj, Self.Blackboard);

      // 2. Restore the nodes' state
      LNodeStatesObj := LStateObj.GetValue('nodeStates') as TJSONObject;
      if Assigned(LNodeStatesObj) then
      begin
        for LPair in LNodeStatesObj do
        begin
          LNode := FindNode(LPair.JsonString.Value);
          if Assigned(LNode) then
          begin
            LNodeStateObj := LPair.JsonValue as TJSONObject;
            LNode.Input := LNodeStateObj.GetValue<string>('input', '');
            LNode.Output := LNodeStateObj.GetValue<string>('output', '');

            // Restore Join inputs
            LNode.FJoinInputs.Clear;
            LJoinInputsObj := LNodeStateObj.GetValue('joinInputs') as TJSONObject;
            if Assigned(LJoinInputsObj) then
            begin
              for var LJoinPair in LJoinInputsObj do
              begin
                if LLinkMap.TryGetValue(LJoinPair.JsonString.Value, LLink) then
                  LNode.FJoinInputs.Add(LLink, LJoinPair.JsonValue.Value);
              end;
            end;
          end;
        end;
      end;

      // 3. Restore the links' state
      LLinkStatesObj := LStateObj.GetValue('linkStates') as TJSONObject;
      if Assigned(LLinkStatesObj) then
      begin
        for LPair in LLinkStatesObj do
        begin
          if LLinkMap.TryGetValue(LPair.JsonString.Value, LLink) then
          begin
            var
            LLinkStateObj := LPair.JsonValue as TJSONObject;
            LLink.FNoCycles := LLinkStateObj.GetValue<Integer>('noCycles', 0);
          end;
        end;
      end;

    finally
      LRoot.Free;
    end;
  finally
    LReader.Free;
    LLinkMap.Free;
  end;
end;

function TAIAgentManager.NewMessage(APrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;
var
  MF: TAiMediaFile;
begin
  // Creates the message
  Result := TAiChatMessage.Create(APrompt, aRole);
  try
    if Length(aMediaFiles) > 0 then
    begin
      for MF in aMediaFiles do
      begin
        if Assigned(MF) then
          Result.AddMediaFile(MF);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TAIAgentManager.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (AComponent is TAIAgentsBase) then
  begin
    if Operation = opInsert then
      AddComponentToList(TAIAgentsBase(AComponent))
    else if Operation = opRemove then
      RemoveComponentFromList(TAIAgentsBase(AComponent));
  end;
end;

procedure TAIAgentManager.RemoveComponentFromList(AComponent: TAIAgentsBase);
begin
  if (AComponent is TAIAgentsNode) and Assigned(FNodes) then
    FNodes.Remove(TAIAgentsNode(AComponent))
  else if (AComponent is TAIAgentsLink) and Assigned(FLinks) then
    FLinks.Remove(TAIAgentsLink(AComponent));
end;

function TAIAgentManager.Run(const APrompt: String; ASeed: TAiBlackboardSeed): String;
begin
  // Early check: if busy, there is no point clearing the previous
  // run's state (Run would relaunch with the same message).
  if FBusy <> 0 then
    raise Exception.Create('The Agent Manager is currently busy.');

  // The order is the only thing that makes this overload correct:
  //   1. Compile validates the structure and does NOT touch the state (M-03).
  //   2. ResetExecutionState clears the blackboard, nodes and links.
  //   3. ASeed seeds after the cleanup, not before: the other way it would be lost,
  //      because Clear frees AskMsg/ResMsg.
  //   4. Run(APrompt) seeds AskMsg only if ASeed did not, and executes.
  Compile;
  ResetExecutionState;

  if Assigned(ASeed) then
    ASeed(FBlackboard);

  Result := Run(APrompt);
end;

function TAIAgentManager.Run(APrompt: String): String;
var
  LTask: ITask;
  LStatus: TAgentExecutionStatus; // Variable for the new enum
begin
  Result := '';

  // 1. BUSY CHECK (simple thread-safe check)
  if FBusy <> 0 then
    raise Exception.Create('The Agent Manager is currently busy.');

  // 2. MESSAGE MANAGEMENT
  // If no previous message was provided, we create a new basic one
  if Not Assigned(Blackboard.AskMsg) then
    Blackboard.AskMsg := NewMessage(APrompt, 'user', []);

  // We always reset the response message for this execution
  Blackboard.ResMsg := TAiChatMessage.Create('', 'assistant');

  // 3. EXECUTION
  // Calls the corrected version of InternalRun that uses the dynamic loop
  LTask := InternalRun(APrompt);

  // 4. SYNCHRONOUS / ASYNCHRONOUS LOGIC
  if FAsynchronous then
  begin
    // ASYNCHRONOUS MODE (Default): We return empty immediately.
    // The result will arrive via events (OnFinish).
    Result := '';
  end
  else
  begin
    // SYNCHRONOUS MODE (REST services): We wait.
    if Assigned(LTask) then
    begin
      try
        LTask.Wait(INFINITE); // We wait for InternalRun to finish
      except
        on E: Exception do
          raise Exception.Create('Error waiting for agent execution: ' + E.Message);
      end;

      // --- MAIN CHANGE HERE ---
      // We retrieve the state as an Enum instead of a String.
      // This assumes you implemented the GetStatus helper in TAIBlackboard.
      LStatus := Blackboard.GetStatus;

      if LStatus = esError then
        raise Exception.Create('Execution Failed: ' + Blackboard.GetString('Execution.ErrorMessage'));

      if LStatus = esTimeout then
        raise Exception.Create('Execution Timed Out');

      // Optional: Handle esAborted explicitly if you wish
      if LStatus = esAborted then
        raise Exception.Create('Execution Aborted');

      // -----------------------------

      // We return the generated content
      if Assigned(Blackboard.ResMsg) and (Blackboard.ResMsg.Prompt <> '') then
        Result := Blackboard.ResMsg.Prompt
      else if Assigned(FEndNode) then
        Result := FEndNode.Output;
    end;
  end;
end;

function TAIAgentManager.InternalRun(Msg: String): ITask;
var
  InitialInput: String;
begin
  // 1. Busy-state check
  if TInterlocked.Exchange(FBusy, 1) <> 0 then
    raise Exception.Create('Agent is busy (InternalRun check).');

  Compile; // Makes sure the graph is ready

  FAbort := False;

  // --- Generate a unique ThreadID for this execution ---
  var LNewGUID: TGUID;
  CreateGUID(LNewGUID);
  FCurrentThreadID := GUIDToString(LNewGUID);

  // Telemetry: span of the whole graph run. The close happens in the
  // orchestrator task's finally; the nodes nest via FRunTraceParent.
  var LGraphSpan := AiSpanStart('agent.graph ' + Name, skInternal);
  AiSpanAttr(LGraphSpan, 'agent.graph.name', Name);
  AiSpanAttr(LGraphSpan, 'agent.run.id', FCurrentThreadID);
  FRunTraceParent := AiSpanTraceParent(LGraphSpan);
  FCheckpointSeq   := 0;
  FSuspendedStepsLock.Enter;
  try
    FSuspendedSteps.Clear;
  finally
    FSuspendedStepsLock.Leave;
  end;

  // We set the initial state in the Blackboard
  Blackboard.SetStatus(esRunning);

  // 2. Cleanup of previous tasks
  FActiveTasksLock.Enter;
  try
    FActiveTasks.Clear;
  finally
    FActiveTasksLock.Leave;
  end;

  InitialInput := Msg;

  // 3. Create the orchestrator's main task
  Result := TTask.Run(
    procedure
    var
      TasksToWaitOn: TArray<ITask>;
      WaitResult: Boolean;
      // CHANGE: Variable of type Enum
      FinalStatus: TAgentExecutionStatus;
      FinalException: Exception;
      FinalErrorMsg: String; // Telemetry: safe copy of the error message
      FinalOutput: String;
      HasPendingTasks: Boolean;
      CurrentTask: ITask;
    begin
      FinalException := nil;
      FinalStatus := esUnknown; // Safe initial value

      try
        try
          // ONSTART EVENT (Direct call, no SafeSync)
          if Assigned(FOnStart) then
            FOnStart(Self, InitialInput);

          if FAbort then
          begin
            FinalStatus := esAborted;
            Exit;
          end;

          // INITIAL NODE EXECUTION
          if Assigned(FStartNode) then
          begin
            FStartNode.Input := InitialInput;
            FStartNode.DoExecute(nil, nil);
          end;

          // --- START OF THE DYNAMIC WAIT LOOP ---
          repeat
            // A. Take a snapshot of the current tasks
            FActiveTasksLock.Enter;
            try
              TasksToWaitOn := FActiveTasks.ToArray;
            finally
              FActiveTasksLock.Leave;
            end;

            // B. Check whether any task is active
            HasPendingTasks := False;
            for CurrentTask in TasksToWaitOn do
            begin
              if (CurrentTask.Status <> TTaskStatus.Completed) and (CurrentTask.Status <> TTaskStatus.Canceled) and (CurrentTask.Status <> TTaskStatus.Exception) then
              begin
                HasPendingTasks := True;
                Break;
              end;
            end;

            // C. If nothing is pending, we exit the loop
            if not HasPendingTasks then
              Break;

            // D. Wait for the current batch of tasks.
            WaitResult := TTask.WaitForAll(TasksToWaitOn, FTimeoutMs);

            if not WaitResult then
              raise Exception.CreateFmt('Graph execution timed out after %d ms.', [FTimeoutMs]);

          until FAbort;
          // --- END OF THE DYNAMIC WAIT LOOP ---

          // Set the final successful state if not aborted
          if not FAbort then
          begin
            FSuspendedStepsLock.Enter;
            try
              if FSuspendedSteps.Count > 0 then
                FinalStatus := esSuspended
              else
                FinalStatus := esCompleted;
            finally
              FSuspendedStepsLock.Leave;
            end;
          end
          else
            FinalStatus := esAborted;

        except
          on E: Exception do
          begin
            Abort; // Stop any new execution
            FinalException := E;
            FinalErrorMsg := E.Message;

            if E.Message.Contains('timed out') then
              FinalStatus := esTimeout
            else
              FinalStatus := esError;

            // Direct call to DoError (no SafeSync)
            DoError(nil, nil, E);
          end;
        end;
      finally
        // Make sure we have a valid state before exiting
        if FinalStatus = esUnknown then
          FinalStatus := esAborted;

        // Save the state in the Blackboard using the Enum's Helper method
        Blackboard.SetStatus(FinalStatus);

        // Delete the checkpoint only if it completed successfully
        if (FinalStatus = esCompleted) and Assigned(FCheckpointer) then
          FCheckpointer.DeleteCheckpoint(FCurrentThreadID);

        // GET THE FINAL RESULT
        FinalOutput := '';
        if Assigned(FEndNode) then
          FinalOutput := FEndNode.Output;

        // ONFINISH EVENT
        // We pass the Enum (FinalStatus) instead of the string
        if Assigned(FOnFinish) then
          FOnFinish(Self, InitialInput, FinalOutput, FinalStatus, FinalException);

        // Telemetry: close of the graph's span with the final status
        AiSpanAttr(LGraphSpan, 'agent.run.status',
          GetEnumName(TypeInfo(TAgentExecutionStatus), Ord(FinalStatus)));
        if FinalStatus in [esError, esTimeout] then
          AiSpanEnd(LGraphSpan, FinalErrorMsg)
        else
          AiSpanEnd(LGraphSpan);
        FRunTraceParent := '';

        // Release the busy flag
        TInterlocked.Exchange(FBusy, 0);
      end;
    end);
end;

// --- NEW: Setter for MaxConcurrentTasks ---
procedure TAIAgentManager.SetMaxConcurrentTasks(const Value: Integer);
var
  LNewValue: Integer;
begin
  LNewValue := Value;
  if LNewValue < 1 then
    LNewValue := 1;

  if FMaxConcurrentTasks <> LNewValue then
  begin
    FMaxConcurrentTasks := LNewValue;
    // --- CORRECTED: TThreadPool ---
    // Instead of recreating, we simply adjust the existing pool.
    // This is safer if there are tasks running.
    if Assigned(FThreadPool) then
      FThreadPool.SetMaxWorkerThreads(FMaxConcurrentTasks);
  end;
end;

procedure TAIAgentManager.SaveStateToStream(AStream: TStream);
var
  LRoot, LStateObj, LBlackboardObj, LNodeStatesObj, LLinkStatesObj, LNodeStateObj, LJoinInputsObj: TJSONObject;
  LNode: TAIAgentsNode;
  LLink: TAIAgentsLink;
  LWriter: TStreamWriter;
  LPair: TPair<TAIAgentsLink, string>;
begin
  LRoot := TJSONObject.Create;
  try
    LStateObj := TJSONObject.Create;
    LRoot.AddPair('executionState', LStateObj);

    // 1. Save the Blackboard
    LBlackboardObj := TJSONObject.Create;
    SerializeBlackboard(Self.Blackboard, LBlackboardObj);
    LStateObj.AddPair('blackboard', LBlackboardObj);

    // 2. Save each node's state
    LNodeStatesObj := TJSONObject.Create;
    for LNode in FNodes do
    begin
      LNodeStateObj := TJSONObject.Create;
      LNodeStateObj.AddPair('input', LNode.Input);
      LNodeStateObj.AddPair('output', LNode.Output);

      // Save the pending inputs on Join-type nodes
      LJoinInputsObj := TJSONObject.Create;
      if LNode.FJoinInputs.Count > 0 then
      begin
        for LPair in LNode.FJoinInputs do
        begin
          LJoinInputsObj.AddPair(LPair.Key.Name, LPair.Value);
        end;
      end;
      LNodeStateObj.AddPair('joinInputs', LJoinInputsObj);

      LNodeStatesObj.AddPair(LNode.Name, LNodeStateObj);
    end;
    LStateObj.AddPair('nodeStates', LNodeStatesObj);

    // 3. Save each link's state
    LLinkStatesObj := TJSONObject.Create;
    for LLink in FLinks do
    begin
      var
      LLinkStateObj := TJSONObject.Create;
      LLinkStateObj.AddPair('noCycles', LLink.NoCycles.ToString);
      LLinkStatesObj.AddPair(LLink.Name, LLinkStateObj);
    end;
    LStateObj.AddPair('linkStates', LLinkStatesObj);

    // Write to the Stream
    LWriter := TStreamWriter.Create(AStream, TEncoding.UTF8);
    try
      LWriter.Write(LRoot.ToString);
    finally
      LWriter.Free;
    end;

  finally
    LRoot.Free;
  end;
end;

procedure TAIAgentManager.SaveToStream(AStream: TStream);
var
  LRoot, LGraphObj, LNodeObj, LLinkObj, LTargetsObj, LExpressionsObj, LCondTargetsObj: TJSONObject;
  LNodesArray, LLinksArray: TJSONArray;
  LNode: TAIAgentsNode;
  LLink: TAIAgentsLink;
  LWriter: TStreamWriter;
  LPair: TPair<string, TAIAgentsNode>;
begin
  LRoot := TJSONObject.Create;
  try
    // 1. "graph" section
    LGraphObj := TJSONObject.Create;
    LGraphObj.AddPair('description', Self.Description);
    if Assigned(FStartNode) then
      LGraphObj.AddPair('startNode', FStartNode.Name)
    else
      LGraphObj.AddPair('startNode', TJSONNull.Create);

    if Assigned(FEndNode) then
      LGraphObj.AddPair('endNode', FEndNode.Name)
    else
      LGraphObj.AddPair('endNode', TJSONNull.Create);

    LGraphObj.AddPair('maxConcurrentTasks', TJSONNumber.Create(FMaxConcurrentTasks));
    LGraphObj.AddPair('timeoutMs', TJSONNumber.Create(FTimeoutMs));
    LRoot.AddPair('graph', LGraphObj);

    // 2. "nodes" section
    LNodesArray := TJSONArray.Create;
    for LNode in FNodes do
    begin
      // M-06: an OnExecute without a Tool cannot be rebuilt from the file;
      // by default it is an error instead of a silent placeholder.
      if Assigned(LNode.OnExecute) and (not Assigned(LNode.Tool)) and (not FAllowPartialSerialization) then
      begin
        LNodesArray.Free;
        raise EAiGraphError.CreateFmt('Node "%s" has an OnExecute handler that cannot be serialized. ' +
          'Attach a Tool, or set AllowPartialSerialization := True to write a diagnostic placeholder.', [LNode.Name]);
      end;

      LNodeObj := TJSONObject.Create;
      LNodeObj.AddPair('name', LNode.Name);
      LNodeObj.AddPair('description', LNode.Description);
      LNodeObj.AddPair('joinMode', GetEnumName(TypeInfo(TJoinMode), Ord(LNode.JoinMode)));
      LNodeObj.AddPair('promptName', LNode.PromptName);

      if Assigned(LNode.Tool) then
      begin
        // --- MODIFIED SECTION ---
        var
        LToolDataObj := TJSONObject.Create;
        LToolDataObj.AddPair('className', LNode.Tool.ClassName);
        LToolDataObj.AddPair('properties', TAiToolParams.ToJSON(LNode.Tool));
        LNodeObj.AddPair('tool', LToolDataObj);
        // --- END OF THE MODIFICATION ---
      end
      else
      begin
        LNodeObj.AddPair('tool', TJSONNull.Create);
      end;

      if Assigned(LNode.OnExecute) then
        LNodeObj.AddPair('onExecuteHandler', 'HandlerFor_' + LNode.Name) // Placeholder (diagnostic only, see M-06)
      else
        LNodeObj.AddPair('onExecuteHandler', TJSONNull.Create);

      if Assigned(LNode.Next) then
        LNodeObj.AddPair('nextLink', LNode.Next.Name)
      else
        LNodeObj.AddPair('nextLink', TJSONNull.Create);

      LNodesArray.Add(LNodeObj);
    end;
    LRoot.AddPair('nodes', LNodesArray);

    // 3. "links" section
    LLinksArray := TJSONArray.Create;
    for LLink in FLinks do
    begin
      LLinkObj := TJSONObject.Create;
      LLinkObj.AddPair('name', LLink.Name);
      LLinkObj.AddPair('description', LLink.Description);
      LLinkObj.AddPair('mode', GetEnumName(TypeInfo(TLinkMode), Ord(LLink.Mode)));
      LLinkObj.AddPair('maxCycles', LLink.MaxCycles.ToString);

      if Assigned(LLink.FSourceNode) then
        LLinkObj.AddPair('sourceNode', LLink.FSourceNode.Name)
      else
        LLinkObj.AddPair('sourceNode', TJSONNull.Create);

      // Save the targets in a "targets" sub-object
      LTargetsObj := TJSONObject.Create;

      if Assigned(LLink.NextA) then
        LTargetsObj.AddPair('nextA', LLink.NextA.Name)
      else
        LTargetsObj.AddPair('nextA', TJSONNull.Create);

      if Assigned(LLink.NextB) then
        LTargetsObj.AddPair('nextB', LLink.NextB.Name)
      else
        LTargetsObj.AddPair('nextB', TJSONNull.Create);

      if Assigned(LLink.NextC) then
        LTargetsObj.AddPair('nextC', LLink.NextC.Name)
      else
        LTargetsObj.AddPair('nextC', TJSONNull.Create);

      if Assigned(LLink.NextD) then
        LTargetsObj.AddPair('nextD', LLink.NextD.Name)
      else
        LTargetsObj.AddPair('nextD', TJSONNull.Create);

      if Assigned(LLink.NextNo) then
        LTargetsObj.AddPair('nextNo', LLink.NextNo.Name)
      else
        LTargetsObj.AddPair('nextNo', TJSONNull.Create);

      LLinkObj.AddPair('targets', LTargetsObj);

      // Save the expressions for the lmExpression mode
      if LLink.Mode = lmExpression then
      begin
        LExpressionsObj := TJSONObject.Create;
        LExpressionsObj.AddPair('expressionA', LLink.ExpressionA);
        LExpressionsObj.AddPair('expressionB', LLink.ExpressionB);
        LExpressionsObj.AddPair('expressionC', LLink.ExpressionC);
        LExpressionsObj.AddPair('expressionD', LLink.ExpressionD);
        LLinkObj.AddPair('expressions', LExpressionsObj);
      end;

      // Save the conditional targets
      if LLink.Mode = lmConditional then
      begin
        LLinkObj.AddPair('conditionalKey', LLink.ConditionalKey);
        if Assigned(LLink.FConditionalTargets) then
        begin
          LCondTargetsObj := TJSONObject.Create;
          for LPair in LLink.FConditionalTargets do
          begin
            LCondTargetsObj.AddPair(LPair.Key, LPair.Value.Name);
          end;
          LLinkObj.AddPair('conditionalTargets', LCondTargetsObj);
        end;
      end;

      LLinksArray.Add(LLinkObj);
    end;
    LRoot.AddPair('links', LLinksArray);

    // 4. Write the JSON to the Stream
    LWriter := TStreamWriter.Create(AStream, TEncoding.UTF8);
    try
      LWriter.Write(LRoot.ToString); // Or LRoot.ToJSON for a more compact version
    finally
      LWriter.Free;
    end;

  finally
    LRoot.Free;
  end;
end;

procedure TAIAgentManager.SetAsynchronous(const Value: Boolean);
begin
  FAsynchronous := Value;
end;

procedure TAIAgentManager.SetDescription(const Value: String);
begin
  FDescription := Value;
end;

// ... (Remaining setters unchanged) ...
procedure TAIAgentManager.SetEndNode(const Value: TAIAgentsNode);
begin
  if FEndNode <> Value then
  begin
    FEndNode := Value;
    FCompiled := False;
  end;
end;

function TAIAgentManager.SetEntryPoint(const ANodeName: string): TAIAgentManager;
begin
  Self.StartNode := FindNode(ANodeName);
  if not Assigned(Self.StartNode) then
    raise Exception.CreateFmt('Entry point node "%s" not found.', [ANodeName]);
  Result := Self;
end;

function TAIAgentManager.SetFinishPoint(const ANodeName: string): TAIAgentManager;
begin
  Self.EndNode := FindNode(ANodeName);
  if not Assigned(Self.EndNode) then
    raise Exception.CreateFmt('Finish point node "%s" not found.', [ANodeName]);
  Result := Self;
end;

procedure TAIAgentManager.SetOnConfirm(const Value: TAIAgentsOnConfirm);
begin
  FOnConfirm := Value;
end;

procedure TAIAgentManager.SetOnEnd(const Value: TAIAgentsOnEnd);
begin
  FOnEnd := Value;
end;

procedure TAIAgentManager.SetOnEnterNode(const Value: TAIAgentsOnEnterNode);
begin
  FOnEnterNode := Value;
end;

procedure TAIAgentManager.SetOnError(const Value: TAIAgentsOnError);
begin
  FOnError := Value;
end;

procedure TAIAgentManager.SetOnExitNode(const Value: TAIAgentsOnExitNode);
begin
  FOnExitNode := Value;
end;

procedure TAIAgentManager.SetOnFinish(const Value: TAIAgentsOnFinish);
begin
  FOnFinish := Value;
end;

procedure TAIAgentManager.SetOnPrint(const Value: TAIAgentsOnPrint);
begin
  if Assigned(Value) then
    FOnPrintRef := nil;
  FOnPrint := Value;
end;

procedure TAIAgentManager.SetOnPrintEvent(const APrintProc: TAgentPrintRef);
begin
  FOnPrintRef := APrintProc;
  if Assigned(FOnPrintRef) then
    FOnPrint := DoPrintFromRef
  else
    FOnPrint := nil;
end;

procedure TAIAgentManager.SetOnStart(const Value: TAIAgentsOnStart);
begin
  FOnStart := Value;
end;

procedure TAIAgentManager.SetStartNode(const Value: TAIAgentsNode);
begin
  if FStartNode <> Value then
  begin
    FStartNode := Value;
    FCompiled := False;
  end;
end;

procedure TAIAgentManager.SetCheckpointer(const Value: IAiCheckpointer);
begin
  FCheckpointer := Value;
end;

procedure TAIAgentManager.SetOnSuspend(const Value: TAIAgentsOnSuspend);
begin
  FOnSuspend := Value;
end;

// ---------------------------------------------------------------------------
// DoNodeCompleted  -- automatic checkpoint after a successful node
// ---------------------------------------------------------------------------
procedure TAIAgentManager.DoNodeCompleted(ANode: TAIAgentsNode);
var
  LSnap: TAiCheckpointSnapshot;
begin
  if not Assigned(FCheckpointer) then Exit;
  TInterlocked.Increment(FCheckpointSeq);
  LSnap := BuildSnapshot;
  try
    LSnap.CheckpointID := FCheckpointSeq;
    FCheckpointer.SaveCheckpoint(FCurrentThreadID, LSnap);
  finally
    LSnap.Free;
  end;
end;

// ---------------------------------------------------------------------------
// DoNodeSuspended  -- handles a node's suspension
// ---------------------------------------------------------------------------
procedure TAIAgentManager.DoNodeSuspended(ANode: TAIAgentsNode;
  ABeforeNode: TAIAgentsNode; ALink: TAIAgentsLink);
var
  LStep: TAiPendingStep;
  LSnap: TAiCheckpointSnapshot;
  LBeforeName, LLinkName: string;
begin
  // NOTE: IfThen is a function, not an operator: it ALWAYS evaluates both branches.
  // With IfThen(Assigned(ABeforeNode), ABeforeNode.Name, '') .Name was read on
  // nil and blew up with an AV. It happens when a node without an incoming edge suspends
  // (the graph's StartNode) or when a resumed node suspends, because
  // ResumeThread calls DoExecute(nil, nil).
  LBeforeName := '';
  if Assigned(ABeforeNode) then
    LBeforeName := ABeforeNode.Name;
  LLinkName := '';
  if Assigned(ALink) then
    LLinkName := ALink.Name;

  LStep := TAiPendingStep.Create(
    ANode.Name,
    LBeforeName,
    LLinkName,
    ANode.Input,
    'Suspended',
    ANode.SuspendReason,
    ANode.SuspendContext);

  FSuspendedStepsLock.Enter;
  try
    FSuspendedSteps.Add(LStep);
  finally
    FSuspendedStepsLock.Leave;
  end;

  Blackboard.SetStatus(esSuspended);

  if Assigned(FCheckpointer) then
  begin
    TInterlocked.Increment(FCheckpointSeq);
    LSnap := BuildSnapshot;
    try
      LSnap.CheckpointID := FCheckpointSeq;
      FCheckpointer.SaveCheckpoint(FCurrentThreadID, LSnap);
    finally
      LSnap.Free;
    end;
  end;

  // Fire OnSuspend on the main thread (TThread.Queue = non-blocking)
  if Assigned(FOnSuspend) then
  begin
    var LThreadID   := FCurrentThreadID;
    var LNodeName   := ANode.Name;
    var LReason     := ANode.SuspendReason;
    var LContext    := ANode.SuspendContext;
    TThread.Queue(nil,
      procedure
      begin
        FOnSuspend(Self, LThreadID, LNodeName, LReason, LContext);
      end);
  end;
end;

// ---------------------------------------------------------------------------
// BuildSnapshot  -- captures the graph's complete state
// ---------------------------------------------------------------------------
function TAIAgentManager.BuildSnapshot: TAiCheckpointSnapshot;
var
  LNode:     TAIAgentsNode;
  LLink:     TAIAgentsLink;
  LNodeObj:  TJSONObject;
  LJoinObj:  TJSONObject;
  LNodeStates, LLinkStates, LBBObj: TJSONObject;
  LPair:     TPair<TAIAgentsLink, string>;
begin
  Result := TAiCheckpointSnapshot.Create;
  Result.ThreadID  := FCurrentThreadID;
  Result.GraphID   := Self.Name;
  Result.CreatedAt := Now;

  // 1. Blackboard
  LBBObj := TJSONObject.Create;
  SerializeBlackboard(FBlackboard, LBBObj);
  Result.Blackboard := LBBObj;

  // 2. Nodes' state
  LNodeStates := TJSONObject.Create;
  for LNode in FNodes do
  begin
    LNodeObj := TJSONObject.Create;
    LNodeObj.AddPair('input',          LNode.Input);
    LNodeObj.AddPair('output',         LNode.Output);
    LNodeObj.AddPair('suspended',      TJSONBool.Create(LNode.FSuspended));
    LNodeObj.AddPair('suspendReason',  LNode.FSuspendReason);
    LNodeObj.AddPair('suspendContext', LNode.FSuspendContext);
    LJoinObj := TJSONObject.Create;
    LNode.FJoinLock.Enter;
    try
      for LPair in LNode.FJoinInputs do
        LJoinObj.AddPair(LPair.Key.Name, LPair.Value);
    finally
      LNode.FJoinLock.Leave;
    end;
    LNodeObj.AddPair('joinInputs', LJoinObj);
    LNodeStates.AddPair(LNode.Name, LNodeObj);
  end;
  Result.NodeStates := LNodeStates;

  // 3. Links' state
  LLinkStates := TJSONObject.Create;
  for LLink in FLinks do
  begin
    var LLinkObj := TJSONObject.Create;
    LLinkObj.AddPair('noCycles', TJSONNumber.Create(LLink.FNoCycles));
    LLinkStates.AddPair(LLink.Name, LLinkObj);
  end;
  Result.LinkStates := LLinkStates;

  // 4. Copy of the suspended steps
  FSuspendedStepsLock.Enter;
  try
    for var LStep in FSuspendedSteps do
      Result.PendingSteps.Add(TAiPendingStep.Create(
        LStep.NodeName, LStep.SourceNodeName, LStep.LinkName,
        LStep.Input, LStep.Status, LStep.SuspendReason, LStep.SuspendContext));
  finally
    FSuspendedStepsLock.Leave;
  end;
end;

// ---------------------------------------------------------------------------
// RestoreFromSnapshot  -- restores the state from a snapshot
// ---------------------------------------------------------------------------
procedure TAIAgentManager.RestoreFromSnapshot(ASnapshot: TAiCheckpointSnapshot);
var
  LNode:    TAIAgentsNode;
  LLink:    TAIAgentsLink;
  LNodeObj: TJSONObject;
  LJoinObj: TJSONObject;
  LPair:    TJSONPair;
  LSrcLink: TAIAgentsLink;
begin
  // 1. Blackboard
  if Assigned(ASnapshot.Blackboard) then
    DeserializeBlackboard(ASnapshot.Blackboard, FBlackboard);

  // 2. Nodes' state
  if Assigned(ASnapshot.NodeStates) then
    for LNode in FNodes do
    begin
      LNodeObj := ASnapshot.NodeStates.GetValue(LNode.Name) as TJSONObject;
      if not Assigned(LNodeObj) then Continue;
      LNode.FInput          := LNodeObj.GetValue<string>('input',          '');
      LNode.FOutput         := LNodeObj.GetValue<string>('output',         '');
      LNode.FSuspended      := LNodeObj.GetValue<Boolean>('suspended',     False);
      LNode.FSuspendReason  := LNodeObj.GetValue<string>('suspendReason',  '');
      LNode.FSuspendContext := LNodeObj.GetValue<string>('suspendContext', '');
      LJoinObj := LNodeObj.GetValue('joinInputs') as TJSONObject;
      if Assigned(LJoinObj) then
      begin
        LNode.FJoinLock.Enter;
        try
          LNode.FJoinInputs.Clear;
          for LPair in LJoinObj do
          begin
            LSrcLink := FindLink(LPair.JsonString.Value);
            if Assigned(LSrcLink) then
              LNode.FJoinInputs.AddOrSetValue(LSrcLink, LPair.JsonValue.Value);
          end;
        finally
          LNode.FJoinLock.Leave;
        end;
      end;
    end;

  // 3. Links' state
  if Assigned(ASnapshot.LinkStates) then
    for LLink in FLinks do
    begin
      var LLinkObj := ASnapshot.LinkStates.GetValue(LLink.Name) as TJSONObject;
      if Assigned(LLinkObj) then
        LLink.FNoCycles := LLinkObj.GetValue<Integer>('noCycles', 0);
    end;

  // 4. Rebuild the suspended steps list
  FSuspendedStepsLock.Enter;
  try
    FSuspendedSteps.Clear;
    for var LStep in ASnapshot.PendingSteps do
      FSuspendedSteps.Add(TAiPendingStep.Create(
        LStep.NodeName, LStep.SourceNodeName, LStep.LinkName,
        LStep.Input, LStep.Status, LStep.SuspendReason, LStep.SuspendContext));
  finally
    FSuspendedStepsLock.Leave;
  end;
end;

// ---------------------------------------------------------------------------
// FindLink  -- looks a link up by name
// ---------------------------------------------------------------------------
function TAIAgentManager.FindLink(const AName: string): TAIAgentsLink;
var
  LLink: TAIAgentsLink;
begin
  Result := nil;
  for LLink in FLinks do
    if SameText(LLink.Name, AName) then
      Exit(LLink);
end;

// ---------------------------------------------------------------------------
// GetSuspendedNodeNames  -- nodes that asked for human input
// ---------------------------------------------------------------------------
function TAIAgentManager.GetNodes: TArray<TAIAgentsNode>;
begin
  Result := FNodes.ToArray;
end;

function TAIAgentManager.GetSuspendedNodeNames: TArray<string>;
var
  LList: TList<string>;
  LStep: TAiPendingStep;
begin
  LList := TList<string>.Create;
  try
    FSuspendedStepsLock.Enter;
    try
      for LStep in FSuspendedSteps do
        if not LList.Contains(LStep.NodeName) then
          LList.Add(LStep.NodeName);
    finally
      FSuspendedStepsLock.Leave;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

// ---------------------------------------------------------------------------
// GetActiveThreads  -- list of active thread IDs
// ---------------------------------------------------------------------------
function TAIAgentManager.GetActiveThreads: TArray<string>;
begin
  if Assigned(FCheckpointer) then
    Result := FCheckpointer.GetActiveThreadIDs
  else
  begin
    if (FCurrentThreadID <> '') and (Blackboard.GetStatus = esSuspended) then
    begin
      SetLength(Result, 1);
      Result[0] := FCurrentThreadID;
    end
    else
      SetLength(Result, 0);
  end;
end;

// ---------------------------------------------------------------------------
// ResumeThread  -- resumes a suspended thread
// ---------------------------------------------------------------------------
function TAIAgentManager.ResumeThread(const AThreadID, ANodeName,
  AInput: string): Boolean;
var
  LSnap:        TAiCheckpointSnapshot;
  LNode:        TAIAgentsNode;
  LResumeInput: string;
  LResumeNode:  TAIAgentsNode;
  LOrchTask:    ITask;
begin
  Result := False;

  if TInterlocked.Exchange(FBusy, 1) <> 0 then
    raise Exception.Create('Agent is busy');

  try
    // 0. Make sure the graph is compiled BEFORE restoring. After an
    // app restart Run has never been called, so InEdges is
    // empty and the joins (jmAll) would fire once per branch. Compile
    // resets NoCycles to 0; RestoreFromSnapshot re-applies them later, so
    // this order is mandatory. If it was already compiled, it is a no-op.
    Compile;

    // 1. Load the checkpoint from disk (if it exists)
    LSnap := nil;
    if Assigned(FCheckpointer) then
      LSnap := FCheckpointer.LoadCheckpoint(AThreadID);

    try
      if Assigned(LSnap) then
      begin
        RestoreFromSnapshot(LSnap);
        FCurrentThreadID := AThreadID;
      end
      else if FCurrentThreadID <> AThreadID then
      begin
        TInterlocked.Exchange(FBusy, 0);
        Exit; // Thread not found on disk or in memory
      end;
    finally
      LSnap.Free;
    end;

    // 2. Locate the node
    LNode := FindNode(ANodeName);
    if not Assigned(LNode) then
    begin
      TInterlocked.Exchange(FBusy, 0);
      raise Exception.CreateFmt('Node "%s" not found in the graph', [ANodeName]);
    end;

    // 3. Prepare the node for resumption
    LNode.FInput          := AInput;
    LNode.FSuspended      := False;
    LNode.FSuspendReason  := '';
    LNode.FSuspendContext := '';

    FSuspendedStepsLock.Enter;
    try
      for var i := FSuspendedSteps.Count - 1 downto 0 do
        if SameText(FSuspendedSteps[i].NodeName, ANodeName) then
          FSuspendedSteps.Delete(i);
    finally
      FSuspendedStepsLock.Leave;
    end;

    // 4. Prepare the graph
    FAbort := False;
    Blackboard.SetStatus(esRunning);
    FActiveTasksLock.Enter;
    try
      FActiveTasks.Clear;
    finally
      FActiveTasksLock.Leave;
    end;

    // 5. Launch a new orchestrator from the resumed node
    LResumeInput := AInput;
    LResumeNode  := LNode;

    LOrchTask := TTask.Run(
      procedure
      var
        TasksToWaitOn:   TArray<ITask>;
        WaitResult:      Boolean;
        FinalStatus:     TAgentExecutionStatus;
        HasPendingTasks: Boolean;
        CurrentTask:     ITask;
        FinalOutput:     string;
        FinalException:  Exception;
      begin
        FinalStatus    := esUnknown;
        FinalException := nil;
        try
          try
            // Execute from the suspended node; aBeforeNode=nil,aLink=nil
            // skips the join gate (handled in DoExecute)
            LResumeNode.DoExecute(nil, nil);

            repeat
              FActiveTasksLock.Enter;
              try
                TasksToWaitOn := FActiveTasks.ToArray;
              finally
                FActiveTasksLock.Leave;
              end;
              HasPendingTasks := False;
              for CurrentTask in TasksToWaitOn do
              begin
                if (CurrentTask.Status <> TTaskStatus.Completed) and
                   (CurrentTask.Status <> TTaskStatus.Canceled)  and
                   (CurrentTask.Status <> TTaskStatus.Exception) then
                begin
                  HasPendingTasks := True;
                  Break;
                end;
              end;
              if not HasPendingTasks then Break;
              WaitResult := TTask.WaitForAll(TasksToWaitOn, FTimeoutMs);
              if not WaitResult then
                raise Exception.CreateFmt('Graph execution timed out after %d ms.', [FTimeoutMs]);
            until FAbort;

            if not FAbort then
            begin
              FSuspendedStepsLock.Enter;
              try
                if FSuspendedSteps.Count > 0 then
                  FinalStatus := esSuspended
                else
                  FinalStatus := esCompleted;
              finally
                FSuspendedStepsLock.Leave;
              end;
            end
            else
              FinalStatus := esAborted;

          except
            on E: Exception do
            begin
              Abort;
              FinalException := E;
              if E.Message.Contains('timed out') then
                FinalStatus := esTimeout
              else
                FinalStatus := esError;
              DoError(nil, nil, E);
            end;
          end;
        finally
          if FinalStatus = esUnknown then FinalStatus := esAborted;
          Blackboard.SetStatus(FinalStatus);

          if (FinalStatus = esCompleted) and Assigned(FCheckpointer) then
            FCheckpointer.DeleteCheckpoint(FCurrentThreadID);

          FinalOutput := '';
          if Assigned(FEndNode) then
            FinalOutput := FEndNode.Output;

          if Assigned(FOnFinish) then
            FOnFinish(Self, LResumeInput, FinalOutput, FinalStatus, FinalException);

          TInterlocked.Exchange(FBusy, 0);
        end;
      end, FThreadPool);

    if not FAsynchronous then
      LOrchTask.Wait;

    Result := True;
  except
    TInterlocked.Exchange(FBusy, 0);
    raise;
  end;
end;

{ TAIAgentsLink }

procedure TAIAgentsLink.AddConditionalTarget(const AKey: string; ANode: TAIAgentsNode);
begin
  if not Assigned(FConditionalTargets) then
    FConditionalTargets := TDictionary<string, TAIAgentsNode>.Create;
  FConditionalTargets.AddOrSetValue(AKey, ANode);
end;

procedure TAIAgentsLink.BuildManualTargets(const TargetsCSV: string; out Nodes: TList<TAIAgentsNode>);
// ... (unchanged) ...
  function ResolveToken(const S: string): TAIAgentsNode;
  begin
    Result := nil;
    if SameText(S, 'A') then
      Exit(FNextA);
    if SameText(S, 'B') then
      Exit(FNextB);
    if SameText(S, 'C') then
      Exit(FNextC);
    if SameText(S, 'D') then
      Exit(FNextD);
    if Assigned(FGraph) then
      Result := FGraph.FindNode(S);
  end;

var
  Parts: TArray<string>;
  T: string;
  N: TAIAgentsNode;
begin
  Nodes := TList<TAIAgentsNode>.Create;
  if TargetsCSV.Trim = '' then
    Exit;
  Parts := TargetsCSV.Split([',']);
  for T in Parts do
  begin
    N := ResolveToken(Trim(T));
    if Assigned(N) then
      Nodes.Add(N);
  end;
end;

constructor TAIAgentsLink.Create(aOwner: TComponent);
begin
  inherited;
  // --- MODIFIED: Constructor cleaned of duplicates ---
  FMaxCycles := 1;
  FMode := lmFanout;
  FConditionalKey := 'next_route';
  FManualTargetsKey := 'next_targets';
end;

procedure TAIAgentsLink.CreateAndQueueTask(ANodeToExecute, ASourceNode: TAIAgentsNode; ACurrentLink: TAIAgentsLink);
begin
  var
  LTask := TTask.Run(
    procedure
    begin
      // This closure now captures the method's parameters, which are stable and unique.
      if (ACurrentLink.FGraph <> nil) and ACurrentLink.FGraph.FAbort then
        Exit;
      ANodeToExecute.DoExecute(ASourceNode, ACurrentLink);
    end, FGraph.FThreadPool);

  FGraph.FActiveTasksLock.Enter;
  try
    FGraph.FActiveTasks.Add(LTask);
  finally
    FGraph.FActiveTasksLock.Leave;
  end;
end;

destructor TAIAgentsLink.Destroy;
begin
  if Assigned(FConditionalTargets) then
    FConditionalTargets.Free;

  // Unlink from the graph on destroy
  if Assigned(FGraph) then
    FGraph.RemoveComponentFromList(Self);

  inherited;
end;

procedure TAIAgentsLink.DoExecute(Sender: TAIAgentsNode);
var
  IsOk, Handled: Boolean;
  NodesToRun: TList<TAIAgentsNode>;
  Decision: string;
begin
  if (FGraph = nil) or FGraph.FAbort then
    Exit;

  // STEP 1: Run the OnExecute event for manual intervention
  Handled := False;
  IsOk := Not Sender.FError;
  if Assigned(FOnExecute) then
  begin
    try
      FOnExecute(Sender, Self, IsOk, Handled);
    except
      on E: Exception do
      begin
        FGraph.DoError(Sender, Self, E);
        Exit;
      end;
    end;
  end;

  if Handled then
    Exit;

  // STEP 2: Evaluate the IsOk result and handle failures/retries
  if not IsOk then
  begin
    Inc(FNoCycles);
    if FNoCycles >= FMaxCycles then
    begin
      var
      E := Exception.CreateFmt('Maximum retry cycles (%d) reached on link "%s" from node "%s". Aborting this path.', [FMaxCycles, Self.Name, Sender.Name]);
      FGraph.DoError(Sender, Self, E);
      Exit;
    end
    else
    begin
      if Assigned(FNextNo) then
      begin
        var
        LTask := TTask.Run(
          procedure
          begin
            if (FGraph <> nil) and not FGraph.FAbort then
              FNextNo.DoExecute(FSourceNode, Self);
          end, FGraph.FThreadPool);

        FGraph.FActiveTasksLock.Enter;
        try
          FGraph.FActiveTasks.Add(LTask);
        finally
          FGraph.FActiveTasksLock.Leave;
        end;
      end;
      Exit;
    end;
  end;

  // STEP 3: IsOk is TRUE. Build the target nodes list according to the mode.
  NodesToRun := nil;
  try
    NodesToRun := TList<TAIAgentsNode>.Create;
    case FMode of
      lmFanout:
        begin
          if Assigned(FNextA) then
            NodesToRun.Add(FNextA);
          if Assigned(FNextB) then
            NodesToRun.Add(FNextB);
          if Assigned(FNextC) then
            NodesToRun.Add(FNextC);
          if Assigned(FNextD) then
            NodesToRun.Add(FNextD);
        end;
      lmConditional:
        begin
          Decision := FGraph.Blackboard.GetString(IfThen(FConditionalKey <> '', FConditionalKey, 'next_route'));
          var
            TargetNode: TAIAgentsNode;
          if Assigned(FConditionalTargets) and FConditionalTargets.TryGetValue(Decision, TargetNode) and Assigned(TargetNode) then
            NodesToRun.Add(TargetNode)
          else if Assigned(FNextNo) then
            NodesToRun.Add(FNextNo);
        end;
      lmManual:
        begin
          Decision := FGraph.Blackboard.GetString(IfThen(FManualTargetsKey <> '', FManualTargetsKey, 'next_targets'));
          var
          ManualNodes := TList<TAIAgentsNode>.Create;
          try
            BuildManualTargets(Decision, ManualNodes);
            NodesToRun.AddRange(ManualNodes);
          finally
            ManualNodes.Free;
          end;
        end;
      lmExpression:
        begin
          var
          LBlackboardData := FGraph.Blackboard.FData;

          // --- Independent Evaluations (Parallel Logic) ---

          // 1. Evaluate A
          if Assigned(FNextA) and (FExpressionA <> '') and EvalCondition(FExpressionA, LBlackboardData) then
            NodesToRun.Add(FNextA);

          // 2. Evaluate B (It is ALWAYS evaluated, regardless of whether A was true)
          if Assigned(FNextB) and (FExpressionB <> '') and EvalCondition(FExpressionB, LBlackboardData) then
            NodesToRun.Add(FNextB);

          // 3. Evaluate C
          if Assigned(FNextC) and (FExpressionC <> '') and EvalCondition(FExpressionC, LBlackboardData) then
            NodesToRun.Add(FNextC);

          // 4. Evaluate D
          if Assigned(FNextD) and (FExpressionD <> '') and EvalCondition(FExpressionD, LBlackboardData) then
            NodesToRun.Add(FNextD);

          // --- Fallback (Default path) ---
          // Only if NONE of the above matched (the list is empty)
          // we run the "NextNo" path.
          if (NodesToRun.Count = 0) and Assigned(FNextNo) then
            NodesToRun.Add(FNextNo);
        end;
    end;
  except
    on E: Exception do
    begin
      if Assigned(NodesToRun) then
        NodesToRun.Free;
      FGraph.DoError(Sender, Self, E);
      Exit;
    end;
  end;

  // ---------------------------------------------------------------------------
  // STEP 4: Dispatch the execution to the target nodes.
  // ---------------------------------------------------------------------------
  try
    if (NodesToRun = nil) or (NodesToRun.Count = 0) then
      Exit;

    if NodesToRun.Count = 1 then
    begin
      NodesToRun[0].DoExecute(FSourceNode, Self);
    end
    else // Parallel fork with scheduler
    begin
      for var Node in NodesToRun do
      begin
        CreateAndQueueTask(Node, FSourceNode, Self);
      end;
    end;
  finally
    if Assigned(NodesToRun) then
      NodesToRun.Free;
  end;
end;

procedure TAIAgentsLink.Print(Value: String);
begin
  if Assigned(FGraph) then
    FGraph.DoPrint(Self, Value);
end;

procedure TAIAgentsLink.SetGraph(const Value: TAIAgentManager);
begin
  if Value <> FGraph then
  begin
    // 1. Unlink from the previous graph if it existed
    if Assigned(FGraph) then
      FGraph.RemoveComponentFromList(Self);

    FGraph := Value;

    // 2. Register in the new graph
    if Assigned(FGraph) then
    begin
      FGraph.AddComponentToList(Self); // <--- THIS WAS MISSING
      FGraph.FCompiled := False;
    end;
  end;
end;

procedure TAIAgentsLink.SetMaxCycles(const Value: Integer);
begin
  FMaxCycles := Value;
  if FMaxCycles < 1 then
    FMaxCycles := 1;
end;

procedure TAIAgentsLink.SetMode(const Value: TLinkMode);
begin
  if FMode <> Value then
  begin
    FMode := Value;
    if Assigned(FGraph) then
      FGraph.FCompiled := False;
  end;
end;

procedure TAIAgentsLink.SetNextA(const Value: TAIAgentsNode);
begin
  FNextA := Value;
end;

procedure TAIAgentsLink.SetNextB(const Value: TAIAgentsNode);
begin
  FNextB := Value;
end;

procedure TAIAgentsLink.SetNextC(const Value: TAIAgentsNode);
begin
  FNextC := Value;
end;

procedure TAIAgentsLink.SetNextD(const Value: TAIAgentsNode);
begin
  FNextD := Value;
end;

procedure TAIAgentsLink.SetNextNo(const Value: TAIAgentsNode);
begin
  FNextNo := Value;
end;

procedure TAIAgentsLink.SetOnExecute(const Value: TAIAgentsLinkOnExecute);
begin
  FOnExecute := Value;
end;

{ TAIAgentsNode }

constructor TAIAgentsNode.Create(aOwner: TComponent);
begin
  inherited;
  FInEdges := TList<TAIAgentsLink>.Create;
  FJoinLock := TCriticalSection.Create;
  // --- NEW: Initialize the join dictionary ---
  FJoinInputs := TDictionary<TAIAgentsLink, string>.Create;
  FJoinMode := jmAny;
end;

destructor TAIAgentsNode.Destroy;
begin
  FInEdges.Free;
  FJoinLock.Free;
  FJoinInputs.Free; // --- NEW: Free the join dictionary ---
  inherited;
end;

procedure TAIAgentsNode.Reset;
begin
  FInEdges.Clear; // structure: rebuilt in Compile
  ResetExecutionState;
end;

procedure TAIAgentsNode.ResetExecutionState;
begin
  FJoinInputs.Clear;
  Input     := '';
  Output    := '';
  FError    := False;
  FMsgError := '';
  FSuspended      := False;
  FSuspendReason  := '';
  FSuspendContext := '';
end;

procedure TAIAgentsNode.Suspend(const AReason: string; const AContext: string);
begin
  // Called from a worker thread. It only marks the state.
  // DoExecute checks this flag before calling OnExitNode and routing.
  FSuspended      := True;
  FSuspendReason  := AReason;
  FSuspendContext := AContext;
end;

// --- MODIFIED: DoExecute method with corrected JOIN logic ---
procedure TAIAgentsNode.DoExecute(aBeforeNode: TAIAgentsNode; aLink: TAIAgentsLink);
var
  CanExecute: Boolean;
begin
  if (FGraph = nil) or FGraph.FAbort then
    Exit;

  if Assigned(FGraph.OnEnterNode) then
    TThread.Synchronize(nil,
      procedure
      begin
        FGraph.OnEnterNode(FGraph, Self);
      end);

  CanExecute := False;
  // Special case: resume from ResumeThread (aBeforeNode=nil, aLink=nil)
  // with a join node (FInEdges.Count > 1). We skip the join gate.
  if (aBeforeNode = nil) and (aLink = nil) and (FInEdges.Count > 1) then
  begin
    CanExecute := True;
    // FInput was already set by ResumeThread before calling DoExecute
  end
  else if FInEdges.Count > 1 then
  begin
    FJoinLock.Enter;
    try
      // Store (or update) the arriving path's input.
      // This is vital: if a value from a previous round already existed, it is overwritten with the new one.
      if (aBeforeNode <> nil) and (aLink <> nil) then
        FJoinInputs.AddOrSetValue(aLink, aBeforeNode.Output);

      case FJoinMode of
        jmAny:
          begin
            CanExecute := True;
            // For jmAny, we take the first arrival's input
            if aBeforeNode <> nil then
              Input := aBeforeNode.Output;
          end;
        jmAll:
          begin
            // It runs if we have data from ALL the required inputs.
            if FJoinInputs.Count >= FInEdges.Count then
            begin
              CanExecute := True;
              // We consolidate all the inputs into a single string
              var
              sb := TStringBuilder.Create;
              try
                for var Value in FJoinInputs.Values do
                  sb.AppendLine(Value);
                Input := sb.ToString;
              finally
                sb.Free;
              end;
            end;
          end;
      end;
    finally
      FJoinLock.Leave;
    end;
  end
  else
  begin
    CanExecute := True;
    if aBeforeNode <> nil then
      Input := aBeforeNode.Output; // Normal behavior for nodes without join
  end;

  if not CanExecute then
    Exit;

  try
    // Clear the state at the start of each execution
    FSuspended      := False;
    FSuspendReason  := '';
    FSuspendContext := '';
    FOutput         := '';   // reset to support multiple executions of the same node

    // Telemetry: per-node span, child of the graph's span. The pool's workers
    // do not share a thread with the orchestrator: the parent travels explicitly.
    var LNodeSpan := AiSpanStart('agent.node ' + Name, skInternal, FGraph.FRunTraceParent);
    AiSpanAttr(LNodeSpan, 'agent.node.name', Name);
    try
      if Assigned(FOnExecute) then
        FOnExecute(Self, aBeforeNode, aLink, Self.Input, FOutput)
      else if Assigned(FTool) then
        FTool.Run(Self, Self.Input, FOutput);

      if FSuspended then
        AiSpanAttr(LNodeSpan, 'agent.node.suspended', True);
      AiSpanEnd(LNodeSpan);
    except
      on E: Exception do
      begin
        AiSpanEnd(LNodeSpan, E.Message);
        raise;
      end;
    end;

    if FOutput = '' then
      FOutput := Input;

    DoTraverseLinks(aBeforeNode, aLink);
  finally
    // --- STATE CLEANUP ---
    if CanExecute and (FInEdges.Count > 1) then
    begin
      FJoinLock.Enter;
      try
        // Always clear after executing, both jmAny and jmAll.
        // For jmAll: the cleanup guarantees that the next cycle (retry/loop)
        // correctly waits for all the inputs before firing again.
        FJoinInputs.Clear;
      finally
        FJoinLock.Leave;
      end;
    end;
  end;
end;

function TAIAgentsNode.CheckJoinAndPrepareInput(aBeforeNode: TAIAgentsNode;
  aLink: TAIAgentsLink): Boolean;
var
  sb: TStringBuilder;
begin
  Result := False;

  // Special case: resume from ResumeThread (aBeforeNode=nil, aLink=nil)
  // with a join node (FInEdges.Count > 1). We skip the join gate.
  if (aBeforeNode = nil) and (aLink = nil) and (FInEdges.Count > 1) then
  begin
    Result := True;
    Exit; // FInput was already set by ResumeThread
  end;

  if FInEdges.Count > 1 then
  begin
    FJoinLock.Enter;
    try
      if (aBeforeNode <> nil) and (aLink <> nil) then
        FJoinInputs.AddOrSetValue(aLink, aBeforeNode.Output);

      case FJoinMode of
        jmAny:
          begin
            Result := True;
            if aBeforeNode <> nil then
              Input := aBeforeNode.Output;
          end;
        jmAll:
          begin
            if FJoinInputs.Count >= FInEdges.Count then
            begin
              Result := True;
              sb := TStringBuilder.Create;
              try
                for var Value in FJoinInputs.Values do
                  sb.AppendLine(Value);
                Input := sb.ToString;
              finally
                sb.Free;
              end;
            end;
          end;
      end;
    finally
      FJoinLock.Leave;
    end;
  end
  else
  begin
    Result := True;
    if aBeforeNode <> nil then
      Input := aBeforeNode.Output;
  end;
end;

procedure TAIAgentsNode.DoTraverseLinks(aBeforeNode: TAIAgentsNode; aLink: TAIAgentsLink);
begin
  // Check suspension before routing to the next link
  if FSuspended then
  begin
    if Assigned(FGraph) then
      FGraph.DoNodeSuspended(Self, aBeforeNode, aLink);
    Exit; // Do not call OnExitNode, do not route to the next Link
  end;

  if Assigned(FGraph) and Assigned(FGraph.OnExitNode) then
    TThread.Synchronize(nil,
      procedure
      begin
        FGraph.OnExitNode(FGraph, Self);
      end);

  if Assigned(Next) then
  begin
    Next.FSourceNode := Self;
    Next.DoExecute(Self);
  end;

  // Checkpoint after a successful node
  if Assigned(FGraph) then
    FGraph.DoNodeCompleted(Self);
end;

procedure TAIAgentsNode.ForceFinalExecute;
begin
  try
    if Assigned(FOnExecute) then
      FOnExecute(Self, nil, nil, Self.Input, FOutput);

    if Assigned(FGraph.OnEnd) then
      TThread.Synchronize(nil,
        procedure
        begin
          FGraph.OnEnd(Self, Output);
        end);
  except
    on E: Exception do
      FGraph.DoError(Self, nil, E);
  end;
end;

procedure TAIAgentsNode.Print(Value: String);
begin
  if Assigned(FGraph) then
    FGraph.DoPrint(Self, Value);
end;

function TAIAgentsNode.RequestConfirmation(const AQuestion: string; Buttons: TMsgStates; var AResponse: string): TMsgState;
begin
  if Assigned(FGraph) then
    Result := FGraph.DoConfirm(Self, AQuestion, Buttons, AResponse)
  else
    Result := msAbort;
end;

function TAIAgentsNode.RequestInput(const ACaption, APrompt: string; var AValue: string): Boolean;
var
  Response: string;
  ModalResult: TMsgState;
begin
  Response := AValue;
  ModalResult := RequestConfirmation(ACaption + '|' + APrompt, [msOK, msCancel], Response);
  if ModalResult = msOK then
  begin
    AValue := Response;
    Result := True;
  end
  else
    Result := False;
end;

procedure TAIAgentsNode.SetError(const Value: Boolean);
begin
  FError := Value;
end;

procedure TAIAgentsNode.SetGraph(const Value: TAIAgentManager);
begin
  if Value <> FGraph then
  begin
    if Assigned(FGraph) then
      FGraph.RemoveComponentFromList(Self);
    FGraph := Value;
    if Assigned(FGraph) then
    begin
      FGraph.AddComponentToList(Self);
      FGraph.FCompiled := False;
    end;
  end;
end;

procedure TAIAgentsNode.SetInput(const Value: String);
begin
  FInput := Value;
end;

procedure TAIAgentsNode.SetJoinMode(const Value: TJoinMode);
begin
  FJoinMode := Value;
end;

procedure TAIAgentsNode.SetMsgError(const Value: String);
begin
  FMsgError := Value;
end;

procedure TAIAgentsNode.SetNext(const Value: TAIAgentsLink);
begin
  if Value <> FNext then
  begin
    if Assigned(FNext) then
      FNext.FSourceNode := nil;
    FNext := Value;
    if Assigned(FNext) then
      FNext.FSourceNode := Self;
    if Assigned(Graph) then
      Graph.FCompiled := False;
  end;
end;

procedure TAIAgentsNode.SetOnExecute(const Value: TAIAgentsNodeOnExecute);
begin
  FOnExecute := Value;
end;

procedure TAIAgentsNode.SetOutput(const Value: String);
begin
  FOutput := Value;
end;

procedure TAIAgentsNode.SetPromptName(const Value: String);
begin
  FPromptName := Value;
end;

procedure TAIAgentsNode.SetTool(const Value: TAiToolBase);
begin
  FTool := Value;
end;

{ TAIAgentsBase }
procedure TAIAgentsBase.SetDescription(const Value: String);
begin
  FDescription := Value;
end;

procedure TAIAgentsBase.SetID(const Value: String);
begin
  FID := Value;
end;

{ TAiToolBase }
procedure TAiToolBase.Run(ANode: TAIAgentsNode; const AInput: string; var AOutput: string);
begin
  Execute(ANode, AInput, AOutput);
end;

procedure TAiToolBase.SetDescription(const Value: String);
begin
  FDescription := Value;
end;

procedure TAiToolBase.SetID(const Value: String);
begin
  FID := Value;
end;

{ TAiSampleTool }
procedure TAiAgentsToolSample.Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string);
begin
  ANode.Print(Format('TAiSampleTool: Executing with input "%s"', [AInput]));
  AOutput := 'Output from TAiSampleTool: ' + AInput;
end;

end.
