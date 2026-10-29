program ReActBasic;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 07-AgenticLLM / 01-ReAct-Basic
// =============================================================================
// The ReAct pattern (Reasoning + Acting) is the basis of all LLM agents.
// In MakerAI it is implemented with TAIAgentManager + TLLMNode.
//
// Concepts it covers:
//   - TAIAgentManager: agent graph orchestrator
//   - TLLMNode: node that contains the ReAct loop with the LLM provider
//   - TAIAgentsNode: generic node (pass-through or with OnExecute)
//   - TAIAgentsLink: edge that connects nodes
//   - Manager.StartNode / EndNode / Compile / Run
//   - Manager.Blackboard: shared state between nodes
//   - Manager.Asynchronous=False: synchronous execution
//
// Graph structure:
//   [Start] --> [LLMAgent] --> [End]
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// =============================================================================
//  Execute a question and show the response
// =============================================================================
procedure Preguntar(Manager: TAIAgentManager; const Pregunta: String);
begin
  Manager.Blackboard.Clear;
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', Pregunta);
  try
    Writeln('Answer: ', Manager.Run(Pregunta));
  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  Manager  : TAIAgentManager;
  Start    : TAIAgentsNode;
  LLMAgent : TLLMNode;
  Finish   : TAIAgentsNode;
begin
  Writeln('=== ReActBasic ===');
  Writeln('Driver: ', DRIVER, ' / ', MODEL);
  Writeln;

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 60000;

    // Input node (pass-through: propagates Input -> Output)
    Start       := TAIAgentsNode.Create(Manager);
    Start.Name  := 'Start';
    Start.Graph := Manager;

    // LLM node: the agent runs the ReAct cycle
    LLMAgent              := TLLMNode.Create(Manager);
    LLMAgent.Name         := 'LLMAgent';
    LLMAgent.Graph        := Manager;
    LLMAgent.DriverName   := DRIVER;
    LLMAgent.Model        := MODEL;
    LLMAgent.ApiKey       := API_KEY;
    LLMAgent.UseAllTools  := False;
    LLMAgent.SystemPrompt :=
      'You are a concise assistant that answers in Spanish. ' +
      'Always answer in one or two direct, to-the-point sentences.';

    // Output node (pass-through)
    Finish       := TAIAgentsNode.Create(Manager);
    Finish.Name  := 'End';
    Finish.Graph := Manager;

    // Connect: Start -> LLMAgent -> End
    Manager.AddEdge('Start',    'LLMAgent');
    Manager.AddEdge('LLMAgent', 'End');

    Manager.StartNode := Start;
    Manager.EndNode   := Finish;
    Manager.Compile;

    Writeln('Graph compiled. Starting questions...');
    Writeln;

    Preguntar(Manager, 'What is the capital of Mexico?');
    Preguntar(Manager, 'Who wrote One Hundred Years of Solitude?');
    Preguntar(Manager, 'What is 2 to the tenth power?');
    Preguntar(Manager, 'Explain in one sentence what an algorithm is.');
    Preguntar(Manager, 'What is the oldest programming language still in use?');

    // Show blackboard state after the last execution
    Writeln(StringOfChar('=', 60));
    Writeln('Blackboard after last execution:');
    Writeln('  LLMAgent.output = "',
      Copy(Manager.Blackboard.GetString('LLMAgent.output'), 1, 80), '..."');

  finally
    Manager.Free;
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
