program D10_HumanInTheLoop;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - AutoAgents Demo 10: HumanInTheLoop
// =============================================================================
// Agent with human approval in the flow:
//   [Drafter] --suspend--> [Human Review] --> [Finalizer]
//
// The review node calls Node.Suspend() showing the draft.
// The user approves or rejects with feedback from the console.
// If approved: the Finalizer polishes the text.
// If rejected: the Drafter regenerates with the user's instructions.
//
// Uses Asynchronous=True + OnSuspend + ResumeThread for the approval cycle.
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

// =============================================================================
// Shared state for the suspend/resume cycle
// =============================================================================
var
  GSuspendThreadID : String = '';
  GSuspendNodeName : String = '';
  GSuspendReason   : String = '';
  GSuspendContext  : String = '';
  GSuspended       : Boolean = False;
  GFinished        : Boolean = False;
  GFinalOutput     : String = '';

// =============================================================================
// TDemoApp — encapsulates the agent and the approval cycle
// =============================================================================
type
  TDemoApp = class
  private
    FManager   : TAIAgentManager;
    FDrafter   : TLLMNode;
    FReviewer  : TAIAgentsNode;  // plain node that calls Suspend
    FFinalizer : TLLMNode;
    FLink1     : TAIAgentsLink;
    FLink2     : TAIAgentsLink;

    procedure OnSuspend(Sender: TObject; const AThreadID, ANodeName, AReason, AContext: string);
    procedure OnFinish(Sender: TObject; const AInput, AOutput: string;
                       Status: TAgentExecutionStatus; E: Exception);
    procedure ReviewerExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
                           Input: String; var Output: String);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Run(const ATask: String);
  end;

procedure TDemoApp.OnSuspend(Sender: TObject; const AThreadID, ANodeName, AReason, AContext: string);
begin
  TThread.Queue(nil, procedure
  begin
    GSuspendThreadID := AThreadID;
    GSuspendNodeName := ANodeName;
    GSuspendReason   := AReason;
    GSuspendContext  := AContext;
    GSuspended       := True;
  end);
end;

procedure TDemoApp.OnFinish(Sender: TObject; const AInput, AOutput: string;
  Status: TAgentExecutionStatus; E: Exception);
begin
  // esSuspended is not termination: the agent waits for human approval.
  // OnSuspend already notifies the main loop. Ignore here to avoid advancing GFinished.
  if Status = esSuspended then Exit;

  TThread.Queue(nil, procedure
  begin
    GFinalOutput := AOutput;
    GFinished    := True;
  end);
end;

procedure TDemoApp.ReviewerExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
  Input: String; var Output: String);
var
  ReviewResult: String;
begin
  // Node.Suspend() only sets a flag and returns; it does NOT block.
  // DoTraverseLinks detects FSuspended=True and does not route to the next node.
  // ResumeThread will call DoExecute again (with aBeforeNode=nil).
  // We use review_result in the blackboard to distinguish the first call vs. resumption.
  ReviewResult := Node.Graph.Blackboard.GetString('review_result');
  if ReviewResult = '' then
  begin
    // First call: save the draft and suspend for human approval
    Node.Graph.Blackboard.SetString('current_draft', Input);
    Node.Suspend('Human review required', Input);
    // Output is ignored (DoTraverseLinks will not route thanks to FSuspended=True)
  end
  else
  begin
    // Resumption: the user approved; pass the approved draft to the Finalizer
    Output := ReviewResult;
    Node.Graph.Blackboard.SetString('review_result', ''); // clear for next round
  end;
end;

constructor TDemoApp.Create;
begin
  inherited Create;

  FManager := TAIAgentManager.Create(nil);
  FManager.Asynchronous := True;   // REQUIRED for suspend/resume
  FManager.TimeoutMs    := 300000; // 5 minutes (includes human review time)
  FManager.OnSuspend    := OnSuspend;
  FManager.OnFinish     := OnFinish;

  // Node 1: Drafter — generates the initial draft
  FDrafter := TLLMNode.Create(FManager);
  FDrafter.Name         := 'Drafter';
  FDrafter.Graph        := FManager;
  FDrafter.DriverName   := DRIVER;
  FDrafter.Model        := MODEL;
  FDrafter.ApiKey       := API_KEY;
  FDrafter.UseAllTools  := False;
  FDrafter.SystemPrompt :=
    'You are a professional writer. Write a clear, engaging paragraph (100-150 words) ' +
    'about the given topic. If you receive feedback/instructions, incorporate them fully.';

  // Node 2: Human reviewer — suspends execution for approval
  FReviewer := TAIAgentsNode.Create(FManager);
  FReviewer.Name     := 'HumanReviewer';
  FReviewer.Graph    := FManager;
  FReviewer.OnExecute := ReviewerExec;

  // Node 3: Finalizer — polishes the approved text
  FFinalizer := TLLMNode.Create(FManager);
  FFinalizer.Name         := 'Finalizer';
  FFinalizer.Graph        := FManager;
  FFinalizer.DriverName   := DRIVER;
  FFinalizer.Model        := MODEL;
  FFinalizer.ApiKey       := API_KEY;
  FFinalizer.UseAllTools  := False;
  FFinalizer.SystemPrompt :=
    'You are a copy editor. You receive an approved draft. ' +
    'Polish it: fix any awkward phrasing, improve word choice, ensure good flow. ' +
    'Keep the same meaning and length. Output only the polished text.';

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

destructor TDemoApp.Destroy;
begin
  FManager.Free;
  inherited;
end;

procedure TDemoApp.Run(const ATask: String);
var
  UserInput   : String;
  Approved    : Boolean;
  Iteration   : Integer;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Task: ', ATask);
  Writeln(StringOfChar('=', 60));

  GSuspended := False;
  GFinished  := False;
  GFinalOutput := '';

  Iteration := 0;
  Approved := False;

  // Launch the agent (returns immediately because Asynchronous=True)
  FManager.Run(ATask);

  repeat
    Inc(Iteration);

    // Wait until the agent suspends or finishes
    while (not GSuspended) and (not GFinished) do
    begin
      CheckSynchronize;
      Sleep(100);
    end;

    if GFinished then
      Break;

    if GSuspended then
    begin
      GSuspended := False;

      // Show the draft to the user
      Writeln;
      Writeln(Format('--- Draft (iteration %d) ---', [Iteration]));
      Writeln(GSuspendContext);
      Writeln;
      Write('Approve this draft? (y=yes, n=no with feedback): ');
      Readln(UserInput);
      Writeln;

      if (Trim(LowerCase(UserInput)) = 's') or (Trim(LowerCase(UserInput)) = 'si') or (Trim(LowerCase(UserInput)) = 'y') then
      begin
        Approved := True;
        // Save the review result in the blackboard
        FManager.Blackboard.SetString('review_result', GSuspendContext);
        FManager.ResumeThread(GSuspendThreadID, GSuspendNodeName, GSuspendContext);
      end
      else
      begin
        // User feedback: regenerate with instructions
        if Trim(UserInput) = '' then
          UserInput := 'Please improve the text quality.';

        Writeln('Regenerating with your feedback...');
        // Cancel the current execution and relaunch with instructions
        FManager.Abort;
        Sleep(200);

        // Reset flags
        GSuspended := False;
        GFinished  := False;
        GFinalOutput := '';

        // Relaunch with the user's instructions as part of the prompt
        var NewPrompt := ATask + sLineBreak + sLineBreak +
          'PREVIOUS DRAFT (needs improvement):' + sLineBreak + GSuspendContext + sLineBreak + sLineBreak +
          'IMPROVEMENT INSTRUCTIONS: ' + UserInput;

        FManager.Run(NewPrompt);
      end;
    end;

  until Approved or GFinished;

  // Wait for the final result if the agent is still running
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
  App: TDemoApp;
begin
  Writeln('=== Demo 10 - HumanInTheLoop ===');
  Writeln('Pattern: Drafter -> [HUMAN REVIEW] -> Finalizer');
  Writeln('The agent will pause waiting for your approval.');
  Writeln;

  App := TDemoApp.Create;
  try
    App.Run('The benefits of learning a second language');
    App.Run('Why regular exercise improves mental health');
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
  Writeln('Demo finished. Press Enter to exit.');
  Readln;
end.
