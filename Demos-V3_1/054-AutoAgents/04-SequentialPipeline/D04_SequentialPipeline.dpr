program D04_SequentialPipeline;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - AutoAgents Demo 04: SequentialPipeline
// =============================================================================
// Three TLLMNodes chained linearly:
//   [Extractor] -> [Expander] -> [Reporter]
// The output of each node is the input of the next.
// Demonstrates composition of specialized agents in a pipeline.
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

procedure RunPipeline(const ATopic: String);
var
  Manager  : TAIAgentManager;
  Extractor: TLLMNode;
  Expander : TLLMNode;
  Reporter : TLLMNode;
  Link1    : TAIAgentsLink;
  Link2    : TAIAgentsLink;
  FinalOut : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATopic);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    // --- Node 1: Key concept extractor ---
    Extractor := TLLMNode.Create(Manager);
    Extractor.Name         := 'Extractor';
    Extractor.Graph        := Manager;
    Extractor.DriverName   := DRIVER;
    Extractor.Model        := MODEL;
    Extractor.ApiKey       := API_KEY;
    Extractor.UseAllTools  := False;
    Extractor.SystemPrompt :=
      'You are a concept extractor. Given a topic, list exactly 5 key concepts ' +
      'related to it. Output ONLY the 5 concepts, one per line, no numbering, no extra text.';

    // --- Node 2: Concept expander ---
    Expander := TLLMNode.Create(Manager);
    Expander.Name         := 'Expander';
    Expander.Graph        := Manager;
    Expander.DriverName   := DRIVER;
    Expander.Model        := MODEL;
    Expander.ApiKey       := API_KEY;
    Expander.UseAllTools  := False;
    Expander.SystemPrompt :=
      'You are a concept explainer. You receive a list of concepts (one per line). ' +
      'For each concept write a single clear sentence definition. ' +
      'Format: "ConceptName: definition sentence."';

    // --- Node 3: Report generator ---
    Reporter := TLLMNode.Create(Manager);
    Reporter.Name         := 'Reporter';
    Reporter.Graph        := Manager;
    Reporter.DriverName   := DRIVER;
    Reporter.Model        := MODEL;
    Reporter.ApiKey       := API_KEY;
    Reporter.UseAllTools  := False;
    Reporter.SystemPrompt :=
      'You are a report writer. You receive a set of concept definitions. ' +
      'Write a cohesive 3-paragraph summary that integrates all concepts naturally. ' +
      'The summary should read as a mini-article about the original topic.';

    // --- Link nodes: Extractor -> Expander -> Reporter ---
    Link1 := TAIAgentsLink.Create(Manager);
    Link1.Name  := 'Link_Extract_Expand';
    Link1.Graph := Manager;
    Link1.NextA := Expander;
    Extractor.Next := Link1;

    Link2 := TAIAgentsLink.Create(Manager);
    Link2.Name  := 'Link_Expand_Report';
    Link2.Graph := Manager;
    Link2.NextA := Reporter;
    Expander.Next := Link2;

    // --- Configure graph ---
    Manager.StartNode := Extractor;
    Manager.EndNode   := Reporter;
    Manager.Compile;

    // --- Run ---
    Writeln;
    Writeln('[Extractor] Extracting concepts...');
    FinalOut := Manager.Run(ATopic);

    // Show intermediate outputs via blackboard
    Writeln;
    Writeln('--- Extracted concepts (Extractor.output) ---');
    Writeln(Manager.Blackboard.GetString('Extractor.output'));
    Writeln;
    Writeln('--- Expanded concepts (Expander.output) ---');
    Writeln(Manager.Blackboard.GetString('Expander.output'));
    Writeln;
    Writeln('--- Final report (Reporter.output) ---');
    Writeln(FinalOut);

  finally
    Manager.Free;
  end;
  Writeln;
end;

procedure RunDemo;
begin
  Writeln('=== Demo 04 - SequentialPipeline ===');
  Writeln('Pattern: [Extractor] -> [Expander] -> [Reporter]');
  Writeln;

  RunPipeline('Machine Learning');
  RunPipeline('Blockchain technology');
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
