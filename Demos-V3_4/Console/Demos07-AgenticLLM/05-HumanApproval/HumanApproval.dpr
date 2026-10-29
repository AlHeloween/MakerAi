program HumanApproval;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 07-AgenticLLM / 05-HumanApproval
// =============================================================================
// Human-in-the-loop: the agent pauses waiting for human approval.
// The user can approve the draft or reject it with feedback,
// which relaunches the agent with improvement instructions.
//
// Concepts it covers:
//   - Manager.Asynchronous = True: execution in a separate thread
//   - Manager.OnSuspend: callback when the agent suspends
//   - Manager.OnFinish: callback when it finishes
//   - Node.Suspend(reason, context): pause execution
//   - Manager.ResumeThread(threadId, nodeName, context): resume
//   - Manager.Abort: cancel current execution
//   - Blackboard to pass data between OnExecute and the main loop
//
// Structure: [Drafter] -> [HumanReviewer (suspend)] -> [Finalizer]
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// Global state of the suspend/resume cycle
var
  GSuspendThreadID : String  = '';
  GSuspendNodeName : String  = '';
  GSuspendContext  : String  = '';
  GSuspended       : Boolean = False;
  GFinished        : Boolean = False;
  GFinalOutput     : String  = '';

// =============================================================================
//  TApprovalApp
// =============================================================================
type
  TApprovalApp = class
  private
    FManager   : TAIAgentManager;
    FDrafter   : TLLMNode;
    FReviewer  : TAIAgentsNode;
    FFinalizer : TLLMNode;
    FLink1, FLink2: TAIAgentsLink;

    procedure OnSuspend(Sender: TObject; const AThreadID, ANodeName,
      AReason, AContext: String);
    procedure OnFinish(Sender: TObject; const AInput, AOutput: String;
      Status: TAgentExecutionStatus; E: Exception);
    procedure ReviewerExec(Node, BeforeNode: TAIAgentsNode;
      Link: TAIAgentsLink; Input: String; var Output: String);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Run(const ATask: String);
  end;

procedure TApprovalApp.OnSuspend(Sender: TObject;
  const AThreadID, ANodeName, AReason, AContext: String);
begin
  TThread.Queue(nil, procedure
  begin
    GSuspendThreadID := AThreadID;
    GSuspendNodeName := ANodeName;
    GSuspendContext  := AContext;
    GSuspended       := True;
  end);
end;

procedure TApprovalApp.OnFinish(Sender: TObject; const AInput, AOutput: String;
  Status: TAgentExecutionStatus; E: Exception);
begin
  if Status = esSuspended then Exit;
  TThread.Queue(nil, procedure
  begin
    GFinalOutput := AOutput;
    GFinished    := True;
  end);
end;

procedure TApprovalApp.ReviewerExec(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
var
  ReviewResult: String;
begin
  ReviewResult := Node.Graph.Blackboard.GetString('review_result');
  if ReviewResult = '' then
  begin
    // First call: suspend for human review
    Node.Graph.Blackboard.SetString('current_draft', Input);
    Node.Suspend('Human review required', Input);
    // Output ignored; the agent does not advance while FSuspended=True
  end
  else
  begin
    // Resumption: user approved
    Output := ReviewResult;
    Node.Graph.Blackboard.SetString('review_result', '');
  end;
end;

constructor TApprovalApp.Create;
begin
  inherited;

  FManager := TAIAgentManager.Create(nil);
  FManager.Asynchronous := True;
  FManager.TimeoutMs    := 300000;
  FManager.OnSuspend    := OnSuspend;
  FManager.OnFinish     := OnFinish;

  // Node 1: Drafter
  FDrafter := TLLMNode.Create(FManager);
  FDrafter.Name         := 'Drafter';
  FDrafter.Graph        := FManager;
  FDrafter.DriverName   := DRIVER;
  FDrafter.Model        := MODEL;
  FDrafter.ApiKey       := API_KEY;
  FDrafter.UseAllTools  := False;
  FDrafter.SystemPrompt :=
    'You are a professional writer. Write a clear and engaging paragraph ' +
    '(80-120 words) about the given topic. If you receive improvement ' +
    'instructions, incorporate them fully. Answer in Spanish.';

  // Node 2: Human reviewer (suspends for approval)
  FReviewer := TAIAgentsNode.Create(FManager);
  FReviewer.Name      := 'HumanReviewer';
  FReviewer.Graph     := FManager;
  FReviewer.OnExecute := ReviewerExec;

  // Node 3: Finalizer
  FFinalizer := TLLMNode.Create(FManager);
  FFinalizer.Name         := 'Finalizer';
  FFinalizer.Graph        := FManager;
  FFinalizer.DriverName   := DRIVER;
  FFinalizer.Model        := MODEL;
  FFinalizer.ApiKey       := API_KEY;
  FFinalizer.UseAllTools  := False;
  FFinalizer.SystemPrompt :=
    'You are an editor. You receive an approved draft. ' +
    'Polish it: improve the flow, fix awkward sentences, optimize word ' +
    'choice. Keep the same meaning and length. ' +
    'Return only the polished text in Spanish.';

  // Chain: Drafter -> HumanReviewer -> Finalizer
  FLink1 := TAIAgentsLink.Create(FManager);
  FLink1.Name := 'L1'; FLink1.Graph := FManager; FLink1.NextA := FReviewer;
  FDrafter.Next := FLink1;

  FLink2 := TAIAgentsLink.Create(FManager);
  FLink2.Name := 'L2'; FLink2.Graph := FManager; FLink2.NextA := FFinalizer;
  FReviewer.Next := FLink2;

  FManager.StartNode := FDrafter;
  FManager.EndNode   := FFinalizer;
  FManager.Compile;
end;

destructor TApprovalApp.Destroy;
begin
  FManager.Free;
  inherited;
end;

procedure TApprovalApp.Run(const ATask: String);
var
  UserInput : String;
  Approved  : Boolean;
  Iteration : Integer;
  NewPrompt : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Task: ', ATask);
  Writeln(StringOfChar('=', 60));

  GSuspended   := False;
  GFinished    := False;
  GFinalOutput := '';
  Iteration    := 0;
  Approved     := False;

  // Launch the agent (returns immediately because Asynchronous=True)
  FManager.Run(ATask);

  repeat
    Inc(Iteration);

    // Wait until suspension or completion
    while (not GSuspended) and (not GFinished) do
    begin
      CheckSynchronize;
      Sleep(100);
    end;

    if GFinished then Break;

    if GSuspended then
    begin
      GSuspended := False;

      Writeln;
      Writeln(Format('--- Draft (iteration %d) ---', [Iteration]));
      Writeln(GSuspendContext);
      Writeln;
      Write('Do you approve this draft? (y=yes / type feedback to improve): ');
      Readln(UserInput);
      Writeln;

      if (Trim(LowerCase(UserInput)) = 'y') or
         (Trim(LowerCase(UserInput)) = 'yes') or
         (Trim(LowerCase(UserInput)) = 'y') then
      begin
        Approved := True;
        FManager.Blackboard.SetString('review_result', GSuspendContext);
        FManager.ResumeThread(GSuspendThreadID, GSuspendNodeName, GSuspendContext);
      end
      else
      begin
        // Rejected: relaunch with feedback
        if Trim(UserInput) = '' then
          UserInput := 'Please improve the text quality.';

        Writeln('Regenerating with your feedback...');
        FManager.Abort;
        Sleep(200);

        GSuspended   := False;
        GFinished    := False;
        GFinalOutput := '';

        NewPrompt := ATask + sLineBreak + sLineBreak +
          'PREVIOUS DRAFT (needs improvement):' + sLineBreak + GSuspendContext + sLineBreak + sLineBreak +
          'IMPROVEMENT INSTRUCTIONS: ' + UserInput;

        FManager.Run(NewPrompt);
      end;
    end;

  until Approved or GFinished;

  // Wait for final result
  while not GFinished do
  begin
    CheckSynchronize;
    Sleep(100);
  end;
  CheckSynchronize;

  Writeln;
  Writeln('--- Final text (polished by Finalizer) ---');
  Writeln(GFinalOutput);
  Writeln;
end;

procedure RunDemo;
var
  App: TApprovalApp;
begin
  Writeln('=== HumanApproval ===');
  Writeln('Pattern: Drafter -> [HUMAN REVIEW] -> Finalizer');
  Writeln('The agent will pause waiting for your approval.');
  Writeln;

  App := TApprovalApp.Create;
  try
    App.Run('The benefits of learning to program from childhood');
  finally
    App.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
