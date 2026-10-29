unit uDmDebate;

// =============================================================================
// MakerAI - Demo 055: FMX Multi-Agent Debate
// DataModule with the agent graph components.
//
// Graph:
//   [Moderador] -> [Propositor] -> [Critico] -> [Rebatidor] -> [Juez]
//
// Each node is a TLLMNode with its own SystemPrompt.
// The AgentManager executes the graph asynchronously.
//
// Accumulated history:
//   - OnEnterNode (Synchronize): injects FDebateHistory into Node.Input so that
//     each agent sees the entire previous conversation, not just the previous output.
//   - OnExitNode  (Synchronize): adds the node's output to FDebateHistory.
// =============================================================================

interface

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

type
  TDebateLogEvent      = procedure(const Value: string) of object;
  TDebateFinishedEvent = procedure(const Value: string) of object;

  TDmDebate = class(TDataModule)
    AgentManager : TAIAgents;
    Moderador    : TLLMNode;
    Link1        : TAIAgentsLink;
    Propositor   : TLLMNode;
    Link2        : TAIAgentsLink;
    Critico      : TLLMNode;
    Link3        : TAIAgentsLink;
    Rebatidor    : TLLMNode;
    Link4        : TAIAgentsLink;
    Juez         : TLLMNode;
    procedure DataModuleCreate(Sender: TObject);
    procedure AgentManagerPrint(Sender: TObject; Value: string);
    procedure AgentManagerFinish(Sender: TObject; const Input, Output: string;
      Status: TAgentExecutionStatus; E: Exception);
    procedure AgentManagerEnterNode(Sender: TObject; Node: TAIAgentsNode);
    procedure AgentManagerExitNode(Sender: TObject; Node: TAIAgentsNode);
  private
    FOnLog         : TDebateLogEvent;
    FOnFinished    : TDebateFinishedEvent;
    FDebateHistory : string;  // historial acumulado del debate
    function NodeRoleLabel(const ANodeName: string): string;
  public
    procedure RunDebate(const ATopic: string);
    property OnLog      : TDebateLogEvent      read FOnLog      write FOnLog;
    property OnFinished : TDebateFinishedEvent read FOnFinished write FOnFinished;
  end;

var
  DmDebate: TDmDebate;

implementation

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// ---------------------------------------------------------------------------
// Returns the role label according to the node name.
// ---------------------------------------------------------------------------
function TDmDebate.NodeRoleLabel(const ANodeName: string): string;
begin
  if SameText(ANodeName, 'Moderador')  then Result := 'MODERATOR'
  else if SameText(ANodeName, 'Propositor') then Result := 'PROPONENT (FOR)'
  else if SameText(ANodeName, 'Critico')    then Result := 'CRITIC (AGAINST)'
  else if SameText(ANodeName, 'Rebatidor')  then Result := 'REBUTTAL (FOR)'
  else if SameText(ANodeName, 'Juez')       then Result := 'JUDGE'
  else Result := ANodeName.ToUpper;
end;

procedure TDmDebate.DataModuleCreate(Sender: TObject);

  procedure ConfigNode(Node: TLLMNode; const APrompt: string);
  begin
    Node.DriverName  := DRIVER;
    Node.Model       := MODEL;
    Node.ApiKey      := API_KEY;
    Node.UseAllTools := False;
    Node.MaxTokens   := 1024;
    Node.SystemPrompt := APrompt;
  end;

begin
  ConfigNode(Moderador,
    'You are a professional debate moderator. Introduce the topic clearly, define ' +
    'the central question and set the debate scope. Be concise (2-3 sentences). ' +
    'Do not argue for or against — just frame the discussion objectively.');

  ConfigNode(Propositor,
    'You are debating strongly IN FAVOR of the topic. The moderator''s introduction ' +
    'is in the conversation. Present exactly 3 numbered arguments IN FAVOR. ' +
    'Be persuasive and specific. Start immediately with your arguments. ' +
    'Label them: "Argument 1:", "Argument 2:", "Argument 3:".');

  ConfigNode(Critico,
    'You are a sharp debate critic arguing AGAINST the topic. ' +
    'The conversation so far contains the moderator''s introduction and the proponent''s ' +
    '3 arguments. Provide 3 specific counterarguments immediately — do NOT ask for ' +
    'clarification or more context. ' +
    'Label them: "Critique 1:", "Critique 2:", "Critique 3:". Be analytical and direct.');

  ConfigNode(Rebatidor,
    'You are defending the original FOR position. ' +
    'The conversation contains the prior debate: moderator intro, proponent arguments, ' +
    'and critic counterarguments. Respond to each critique immediately — do NOT ask ' +
    'for additional context. ' +
    'Label them: "Rebuttal 1:", "Rebuttal 2:", "Rebuttal 3:". Stay focused.');

  ConfigNode(Juez,
    'You are a fair and impartial debate judge. ' +
    'The complete debate so far is in the conversation. ' +
    'Deliver your verdict IMMEDIATELY — do NOT request missing information. ' +
    'Start with "VERDICT:" and keep your judgment under 200 words. ' +
    'Acknowledge the strongest points from both sides and declare which was more compelling.');

  AgentManager.Compile;
end;

// ---------------------------------------------------------------------------
// OnEnterNode — called via TThread.Synchronize from TLLMNode.DoExecute,
// BEFORE the LLM call. We inject the accumulated history into Node.Input
// so the agent sees the entire previous conversation.
// ---------------------------------------------------------------------------
procedure TDmDebate.AgentManagerEnterNode(Sender: TObject; Node: TAIAgentsNode);
var
  Sep, Hdr: string;
begin
  // Inject accumulated history (only if there is something — Moderator does not need it)
  if FDebateHistory <> '' then
    Node.Input := FDebateHistory;

  // Log node entry (direct call: we are already on the main thread)
  Sep := StringOfChar('=', 50);
  Hdr := '>> ' + NodeRoleLabel(Node.Name);
  if Assigned(FOnLog) then FOnLog(Sep);
  if Assigned(FOnLog) then FOnLog(Hdr);
end;

// ---------------------------------------------------------------------------
// OnExitNode — called via TThread.Synchronize from DoTraverseLinks,
// AFTER the node executes. We accumulate the output in FDebateHistory.
// ---------------------------------------------------------------------------
procedure TDmDebate.AgentManagerExitNode(Sender: TObject; Node: TAIAgentsNode);
var
  Label_: string;
begin
  Label_ := NodeRoleLabel(Node.Name);

  // Add the node's output to the accumulated history
  FDebateHistory := FDebateHistory +
    '[' + Label_ + ']:' + sLineBreak +
    Node.Output + sLineBreak + sLineBreak;

  // Log the node's output
  if Assigned(FOnLog) then
  begin
    FOnLog('[' + Label_ + ']:');
    FOnLog(Node.Output);
  end;
end;

procedure TDmDebate.AgentManagerPrint(Sender: TObject; Value: string);
var
  NodeName: string;
begin
  NodeName := '';
  if Sender is TAIAgentsNode then
    NodeName := TAIAgentsNode(Sender).Name;

  TThread.Queue(nil,
    procedure
    var
      Msg: string;
    begin
      if Assigned(FOnLog) then
      begin
        if NodeName <> '' then
          Msg := '[' + NodeName + '] ' + Value
        else
          Msg := Value;
        FOnLog(Msg);
      end;
    end);
end;

procedure TDmDebate.AgentManagerFinish(Sender: TObject; const Input, Output: string;
  Status: TAgentExecutionStatus; E: Exception);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnFinished) then
        FOnFinished(Output);
    end);
end;

procedure TDmDebate.RunDebate(const ATopic: string);
begin
  // Initialize history with the debate topic
  FDebateHistory := 'DEBATE TOPIC: ' + ATopic + sLineBreak + sLineBreak;
  AgentManager.Run(ATopic);
end;

end.
