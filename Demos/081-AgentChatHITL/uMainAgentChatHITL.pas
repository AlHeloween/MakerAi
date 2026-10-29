// Demo 081 - Human-in-the-loop integrated into the chat
//
// Shows how an agent graph requests user intervention WITHOUT modal
// windows or blocked threads: the approval node suspends the graph
// (TAiWaitApprovalTool -> Node.Suspend), the question appears as another
// chat message (TAIChatView) and the user's next answer in
// TAIChatInput resumes execution with ResumeThread. Since nothing stays
// waiting, the same pattern works on Windows, Android and Linux.
//
// Also, with TAiFileCheckpointer the suspension survives app shutdown:
// on startup pending threads are detected (GetActiveThreads) and the next
// chat answer resumes them, even after restarting the process.
//
// Requires no API keys: the nodes do deterministic work so the
// suspension/resumption flow is clear. In a real app, "Prepare" and
// "Execute" would use TAiChatConnection or other tools.

unit uMainAgentChatHITL;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls, FMX.Layouts,
  FMX.Controls.Presentation,
  uMakerAi.Core,
  uMakerAi.Agents,
  uMakerAi.Agents.Checkpoint,
  uMakerAi.Agents.Tools.Approval,
  AIChat.Types,
  AIChat.Control.FMX,
  AIChat.Input;

type
  TFormAgentChatHITL = class(TForm)
    LayoutTop: TLayout;
    lblEstado: TLabel;
    ChatView1: TAIChatView;
    ChatInput1: TAIChatInput;
    procedure FormCreate(Sender: TObject);
    procedure ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
    procedure ChatInput1Cancel(Sender: TObject);
  private
    FAgent: TAIAgentManager;
    FPendingThreadID: string; // <> '' when the graph waits for the user response
    FPendingNodeName: string; // node to be resumed (here always 'Approve')
    procedure BuildGraph;
    procedure NodePreparar(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    procedure NodeEjecutar(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    procedure AgentSuspended(Sender: TObject; const AThreadID, ANodeName, AReason, AContext: string);
    procedure AgentFinished(Sender: TObject; const Input, Output: string; Status: TAgentExecutionStatus; E: Exception);
    procedure AgentSay(const AText: string);
    procedure SetEstado(const AText: string);
    function CheckpointDir: string;
  end;

var
  FormAgentChatHITL: TFormAgentChatHITL;

implementation

{$R *.fmx}

const
  NODO_APROBACION = 'Aprobar';

procedure TFormAgentChatHITL.FormCreate(Sender: TObject);
var
  LThreads: TArray<string>;
begin
  BuildGraph;

  // The suspension is persisted to disk: if the app closes with a pending question,
  // on startup it is recovered and can be resumed.
  ForceDirectories(CheckpointDir);
  FAgent.Checkpointer := TAiFileCheckpointer.Create(CheckpointDir);
  FAgent.OnSuspend := AgentSuspended;
  FAgent.OnFinish := AgentFinished;

  AgentSay('Hello. Ask me for a task (for example: **publish the sales report**).' + sLineBreak +
    'I will prepare a plan and ask for approval right here, in the chat, before executing it.');
  SetEstado('Ready');

  // Human-in-the-loop durable: threads suspended from a previous session
  LThreads := FAgent.GetActiveThreads;
  if Length(LThreads) > 0 then
  begin
    FPendingThreadID := LThreads[0];
    FPendingNodeName := NODO_APROBACION;
    AgentSay('I have a task suspended from a previous session waiting for your approval. ' +
      'Your next answer resumes it ("yes" approves, anything else cancels).');
    SetEstado('Waiting for your answer (task recovered from checkpoint)');
  end;
end;

procedure TFormAgentChatHITL.BuildGraph;
var
  LNode: TAIAgentsNode;
  LTool: TAiWaitApprovalTool;
begin
  FAgent := TAIAgentManager.Create(Self);
  // Asynchronous: Run returns immediately and the result arrives through events.
  // Nothing blocks the UI thread or leaves a worker waiting.
  FAgent.Asynchronous := True;

  // Prepare -> Approve (suspends) -> Execute
  FAgent.AddNode('Preparar', NodePreparar);
  FAgent.AddNode(NODO_APROBACION, nil);
  FAgent.AddNode('Ejecutar', NodeEjecutar);
  FAgent.AddEdge('Preparar', NODO_APROBACION);
  FAgent.AddEdge(NODO_APROBACION, 'Ejecutar');
  FAgent.SetEntryPoint('Preparar');
  FAgent.SetFinishPoint('Ejecutar');

  // The factory tool for HITL: when executed it suspends the graph and fires
  // OnSuspend; on resumption it lets the human response through as Output.
  LNode := FAgent.FindNode(NODO_APROBACION);
  LTool := TAiWaitApprovalTool.Create(LNode);
  LTool.SuspendReason := 'I need your approval before executing this plan:';
  LTool.ContextKey := 'plan'; // blackboard key that travels as context
  LNode.Tool := LTool;
end;

// ---------------------------------------------------------------------------
// Graph nodes (run in pool threads; do not touch the UI)
// ---------------------------------------------------------------------------

procedure TFormAgentChatHITL.NodePreparar(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
var
  LPlan: string;
begin
  // Here the real work would go (a TAiChatConnection that generates the plan, etc.)
  LPlan := 'Plan for "' + Trim(Input) + '":' + sLineBreak +
    '1. Gather the necessary information' + sLineBreak +
    '2. Prepare the result draft' + sLineBreak +
    '3. Publish the final version';
  Node.Graph.Blackboard.SetString('plan', LPlan);
  Output := LPlan;
end;

procedure TFormAgentChatHITL.NodeEjecutar(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
var
  LResp: string;
begin
  // Input is the answer the user wrote in the chat when resuming
  LResp := Trim(Input).ToLower;
  if LResp.StartsWith('si') or LResp.StartsWith('ok') or LResp.StartsWith('yes') or
     LResp.StartsWith('dale') or (Pos('aprob', LResp) > 0) then
    Output := 'Approved. Executing the plan:' + sLineBreak +
      Node.Graph.Blackboard.GetString('plan') + sLineBreak +
      '**Task completed.**'
  else
    Output := 'Understood, I will not execute the plan (you said: "' + Trim(Input) + '"). ' +
      'Write a new request whenever you want.';
end;

// ---------------------------------------------------------------------------
// Agent events (arrive in pool threads -> TThread.Queue for the UI)
// ---------------------------------------------------------------------------

procedure TFormAgentChatHITL.AgentSuspended(Sender: TObject; const AThreadID, ANodeName, AReason, AContext: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      FPendingThreadID := AThreadID;
      FPendingNodeName := ANodeName;
      ChatInput1.Busy := False;
      AgentSay(AReason + sLineBreak + sLineBreak + AContext + sLineBreak + sLineBreak +
        'Answer **yes** to approve; any other answer cancels.');
      SetEstado('The agent is waiting for your answer');
    end);
end;

procedure TFormAgentChatHITL.AgentFinished(Sender: TObject; const Input, Output: string; Status: TAgentExecutionStatus; E: Exception);
var
  LError: string;
begin
  // Do not capture E inside the closure: the exception is freed when returning
  if Assigned(E) then
    LError := E.Message
  else
    LError := '';

  TThread.Queue(nil,
    procedure
    begin
      case Status of
        esSuspended:
          ; // the UI was already updated in AgentSuspended
        esCompleted:
          begin
            ChatInput1.Busy := False;
            AgentSay(Output);
            SetEstado('Ready');
          end;
      else
        begin
          ChatInput1.Busy := False;
          if LError <> '' then
            AgentSay('Agent error: ' + LError)
          else
            AgentSay('The graph finished with an unexpected state.');
          SetEstado('Error');
        end;
      end;
    end);
end;

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

procedure TFormAgentChatHITL.ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
var
  LThreadID: string;
begin
  if Trim(APrompt) = '' then
  begin
    ChatInput1.Busy := False;
    Exit;
  end;

  ChatView1.AddUserMessage(APrompt);
  ChatInput1.Busy := True;

  if FPendingThreadID <> '' then
  begin
    // There is a suspended graph: this answer resumes it where it left off
    LThreadID := FPendingThreadID;
    FPendingThreadID := '';
    SetEstado('Resuming the agent...');
    if not FAgent.ResumeThread(LThreadID, FPendingNodeName, APrompt) then
    begin
      ChatInput1.Busy := False;
      AgentSay('I could not resume the suspended task; start a new request.');
      SetEstado('Ready');
    end;
  end
  else
  begin
    // New clean run (the empty seed forces ResetExecutionState)
    SetEstado('Agent working...');
    FAgent.Run(APrompt,
      procedure(B: TAIBlackboard)
      begin
        // no preloaded keys; the previous reset guarantees clean state
      end);
  end;
end;

procedure TFormAgentChatHITL.ChatInput1Cancel(Sender: TObject);
begin
  ChatInput1.Busy := False;
end;

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

procedure TFormAgentChatHITL.AgentSay(const AText: string);
begin
  ChatView1.AddMessage(TChatRole.crAssistant, AText);
end;

procedure TFormAgentChatHITL.SetEstado(const AText: string);
begin
  lblEstado.Text := 'Status: ' + AText;
end;

function TFormAgentChatHITL.CheckpointDir: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'Checkpoints');
end;

end.
