program AgentParallelFork;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — 07-AgenticLLM / 06-ParallelFork
// =============================================================================
// Fork/Join pattern with TLLMNodes running in parallel:
//
//   [InputPrep] --ForkLink--> [ProsAnalyst]  --JoinLinkA--\
//                          \-> [ConsAnalyst] --JoinLinkB--> [Synthesizer] (jmAll)
//
// Two nodes analyze the same topic in parallel (advantages and disadvantages).
// The synthesizer node waits for BOTH results (jmAll) before executing.
//
// Concepts it covers:
//   - ForkLink with NextA + NextB: fork to two nodes in parallel
//   - JoinMode = jmAll: wait for ALL input nodes to complete
//   - Reading the intermediate blackboard by node name
//   - TThreadPool internally manages concurrency
//   - EAggregateException: composite exception from multiple threads
// =============================================================================

uses
  System.SysUtils,
  System.Threading,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

procedure RunParallelResearch(const ATopic: String);
var
  Manager   : TAIAgentManager;
  InputPrep : TLLMNode;
  ProsNode  : TLLMNode;
  ConsNode  : TLLMNode;
  SynthNode : TLLMNode;
  ForkLink  : TAIAgentsLink;
  JoinLinkA : TAIAgentsLink;
  JoinLinkB : TAIAgentsLink;
  FinalOut  : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATopic);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    // Preparation node: formulates a research question about the topic
    InputPrep := TLLMNode.Create(Manager);
    InputPrep.Name         := 'InputPrep';
    InputPrep.Graph        := Manager;
    InputPrep.DriverName   := DRIVER;
    InputPrep.Model        := MODEL;
    InputPrep.ApiKey       := API_KEY;
    InputPrep.UseAllTools  := False;
    InputPrep.SystemPrompt :=
      'You are a research coordinator. Given a topic, write a single clear ' +
      'research question about it. Output ONLY the question, nothing else.';

    // Branch A: advantages analysis
    ProsNode := TLLMNode.Create(Manager);
    ProsNode.Name         := 'ProsAnalyst';
    ProsNode.Graph        := Manager;
    ProsNode.DriverName   := DRIVER;
    ProsNode.Model        := MODEL;
    ProsNode.ApiKey       := API_KEY;
    ProsNode.UseAllTools  := False;
    ProsNode.SystemPrompt :=
      'You are a PRO analyst. Your output must be STRICTLY formatted.' + #10 +
      'Given a research question, respond with EXACTLY:' + #10 +
      'PROS:' + #10 +
      '1. [one sentence advantage]' + #10 +
      '2. [one sentence advantage]' + #10 +
      '3. [one sentence advantage]' + #10 +
      'Nothing else.';

    // Branch B: disadvantages analysis
    ConsNode := TLLMNode.Create(Manager);
    ConsNode.Name         := 'ConsAnalyst';
    ConsNode.Graph        := Manager;
    ConsNode.DriverName   := DRIVER;
    ConsNode.Model        := MODEL;
    ConsNode.ApiKey       := API_KEY;
    ConsNode.UseAllTools  := False;
    ConsNode.SystemPrompt :=
      'You are a CON analyst. Your output must be STRICTLY formatted.' + #10 +
      'Given a research question, respond with EXACTLY:' + #10 +
      'CONS:' + #10 +
      '1. [one sentence disadvantage]' + #10 +
      '2. [one sentence disadvantage]' + #10 +
      '3. [one sentence disadvantage]' + #10 +
      'Nothing else.';

    // Synthesizer: waits for BOTH branches (jmAll)
    SynthNode := TLLMNode.Create(Manager);
    SynthNode.Name         := 'Synthesizer';
    SynthNode.Graph        := Manager;
    SynthNode.DriverName   := DRIVER;
    SynthNode.Model        := MODEL;
    SynthNode.ApiKey       := API_KEY;
    SynthNode.UseAllTools  := False;
    SynthNode.JoinMode     := jmAll;  // espera ProsNode Y ConsNode
    SynthNode.SystemPrompt :=
      'You are a balanced analyst. You receive the combined output of two researchers: ' +
      'one listed PROS and another listed CONS. ' +
      'Synthesize them into a balanced verdict paragraph of 4-5 sentences. ' +
      'Start with "VERDICT:" and end with a clear recommendation.';

    // Fork: InputPrep -> ProsNode and ConsNode in parallel
    ForkLink := TAIAgentsLink.Create(Manager);
    ForkLink.Name  := 'ForkLink';
    ForkLink.Graph := Manager;
    ForkLink.NextA := ProsNode;
    ForkLink.NextB := ConsNode;
    InputPrep.Next := ForkLink;

    // Join A: ProsNode -> Synthesizer
    JoinLinkA := TAIAgentsLink.Create(Manager);
    JoinLinkA.Name  := 'JoinLinkFromPros';
    JoinLinkA.Graph := Manager;
    JoinLinkA.NextA := SynthNode;
    ProsNode.Next   := JoinLinkA;

    // Join B: ConsNode -> Synthesizer
    JoinLinkB := TAIAgentsLink.Create(Manager);
    JoinLinkB.Name  := 'JoinLinkFromCons';
    JoinLinkB.Graph := Manager;
    JoinLinkB.NextA := SynthNode;
    ConsNode.Next   := JoinLinkB;

    Manager.StartNode := InputPrep;
    Manager.EndNode   := SynthNode;
    Manager.Compile;

    Writeln;
    Writeln('Running parallel research (ProsAnalyst || ConsAnalyst)...');
    FinalOut := Manager.Run(ATopic);

    Writeln;
    Writeln('--- Research question (InputPrep) ---');
    Writeln(Manager.Blackboard.GetString('InputPrep.output'));
    Writeln;
    Writeln('--- PROS analysis ---');
    Writeln(Manager.Blackboard.GetString('ProsAnalyst.output'));
    Writeln;
    Writeln('--- CONS analysis ---');
    Writeln(Manager.Blackboard.GetString('ConsAnalyst.output'));
    Writeln;
    Writeln('--- Final verdict (Synthesizer, jmAll) ---');
    Writeln(FinalOut);

  finally
    Manager.Free;
  end;
  Writeln;
end;

procedure PrintException(E: Exception; const APrefix: String = '');
var
  AggE: EAggregateException;
  I: Integer;
begin
  if E is EAggregateException then
  begin
    AggE := EAggregateException(E);
    Writeln(APrefix, 'AggregateException (', AggE.Count, ' internal):');
    for I := 0 to AggE.Count - 1 do
      Writeln(APrefix, '  [', I, '] ', AggE.InnerExceptions[I].ClassName,
              ': ', AggE.InnerExceptions[I].Message);
  end
  else
    Writeln(APrefix, E.ClassName, ': ', E.Message);
end;

begin
  Writeln('=== AgentParallelFork ===');
  Writeln('Pattern: Fork/Join — two parallel branches + synthesizer (jmAll)');
  Writeln;
  try
    RunParallelResearch('Artificial intelligence in education');
  except
    on E: Exception do
    begin
      Writeln('FATAL: ');
      PrintException(E, '  ');
    end;
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
