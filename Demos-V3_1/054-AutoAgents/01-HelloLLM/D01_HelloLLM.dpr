program D01_HelloLLM;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - AutoAgents Demo 01: HelloLLM
// =============================================================================
// Minimal graph of 3 nodes: StartNode -> TLLMNode -> EndNode.
// Demonstrates the basic structure of an agent graph with an LLM node
// central without tools.
//
// Structure:
//   [Start] --(lmFanout)--> [LLMNode] --(lmFanout)--> [End]
//
// Start and End are pass-through nodes (without OnExecute): they propagate Input -> Output.
// LLMNode contains the ReAct loop with the configured LLM provider.
// =============================================================================

uses
  System.SysUtils,
  System.Generics.Collections,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

procedure RunDemo;
var
  Manager  : TAIAgentManager;
  StartNode: TAIAgentsNode;
  LLMNode  : TLLMNode;
  EndNode  : TAIAgentsNode;
  Questions: array[0..2] of string;
  I: Integer;
begin
  Writeln('=== Demo 01 — HelloLLM ===');
  Writeln('Driver : ', DRIVER);
  Writeln('Model  : ', MODEL);
  Writeln;

  Questions[0] := 'What is the capital of France?';
  Questions[1] := 'Who wrote Don Quixote of La Mancha?';
  Questions[2] := 'Explain in one sentence what photosynthesis is.';

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 30000;

    // Entry node: pass-through (without OnExecute propagates Input -> Output)
    StartNode       := TAIAgentsNode.Create(Manager);
    StartNode.Name  := 'Start';
    StartNode.Graph := Manager;

    // Central LLM node: executes the ReAct loop with the configured provider
    LLMNode              := TLLMNode.Create(Manager);
    LLMNode.Name         := 'LLMNode';
    LLMNode.Graph        := Manager;
    LLMNode.DriverName   := DRIVER;
    LLMNode.Model        := MODEL;
    LLMNode.ApiKey       := API_KEY;
    LLMNode.UseAllTools  := False;
    LLMNode.SystemPrompt :=
      'You are a concise assistant. Always answer in a single short and direct sentence.';

    // Exit node: pass-through (receives Output from LLMNode)
    EndNode       := TAIAgentsNode.Create(Manager);
    EndNode.Name  := 'End';
    EndNode.Graph := Manager;

    // Connect: Start -> LLMNode -> End
    Manager.AddEdge('Start', 'LLMNode');
    Manager.AddEdge('LLMNode', 'End');

    Manager.StartNode := StartNode;
    Manager.EndNode   := EndNode;
    Manager.Compile;

    // Run several independent questions
    for I := 0 to High(Questions) do
    begin
      // Clear blackboard state between questions (releases previous AskMsg/ResMsg
      // and allows Run to create a fresh AskMsg from the new prompt)
      Manager.Blackboard.Clear;

      Writeln(StringOfChar('-', 60));
      Writeln('Question : ', Questions[I]);
      try
        Writeln('Answer: ', Manager.Run(Questions[I]));
      except
        on E: Exception do
          Writeln('ERROR: ', E.Message);
      end;
      Writeln;
    end;

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
  Writeln('Demo finished. Press Enter to exit.');
  Readln;
end.
