program AgentCheckpoints;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 07-AgenticLLM / 04-Checkpoints
// =============================================================================
// Pipeline secuencial de 3 nodos con inspeccion del blackboard en cada paso.
// Demuestra como cada nodo escribe su output al blackboard y como leerlo
// para seguir el progreso del pipeline.
//
// Concepts it covers:
//   - Manager.Blackboard.GetString('NombreNodo.output')
//   - Pipeline de 3 TLLMNodes: Extractor -> Traductor -> Resumen
//   - Lectura de checkpoints intermedios tras Manager.Run()
//   - TAIAgentsLink encadenando nodos
//
// Structure: [Extractor] -> [Translator] -> [Summarizer]
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
  Manager    : TAIAgentManager;
  Extractor  : TLLMNode;
  Translator : TLLMNode;
  Summarizer : TLLMNode;
  Link1, Link2: TAIAgentsLink;
  FinalOut   : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATopic);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    // Node 1: Keyword extractor
    Extractor := TLLMNode.Create(Manager);
    Extractor.Name         := 'Extractor';
    Extractor.Graph        := Manager;
    Extractor.DriverName   := DRIVER;
    Extractor.Model        := MODEL;
    Extractor.ApiKey       := API_KEY;
    Extractor.UseAllTools  := False;
    Extractor.SystemPrompt :=
      'You are a keyword extractor. Given a topic, list exactly 5 key terms ' +
      'in English. Output ONLY the 5 terms, one per line, no numbering.';

    // Node 2: Translator (English -> Spanish)
    Translator := TLLMNode.Create(Manager);
    Translator.Name         := 'Translator';
    Translator.Graph        := Manager;
    Translator.DriverName   := DRIVER;
    Translator.Model        := MODEL;
    Translator.ApiKey       := API_KEY;
    Translator.UseAllTools  := False;
    Translator.SystemPrompt :=
      'You are a translator from English to Spanish. ' +
      'Translate each keyword on its own line. ' +
      'Format: "English term → termino en espanol". One per line.';

    // Node 3: Summary generator
    Summarizer := TLLMNode.Create(Manager);
    Summarizer.Name         := 'Summarizer';
    Summarizer.Graph        := Manager;
    Summarizer.DriverName   := DRIVER;
    Summarizer.Model        := MODEL;
    Summarizer.ApiKey       := API_KEY;
    Summarizer.UseAllTools  := False;
    Summarizer.SystemPrompt :=
      'You are a Spanish writer. You receive a list of translated keywords. ' +
      'Write a short paragraph (3-4 sentences) in Spanish that integrates ' +
      'all those concepts naturally.';

    // Link: Extractor -> Translator -> Summarizer
    Link1 := TAIAgentsLink.Create(Manager);
    Link1.Name  := 'L1'; Link1.Graph := Manager; Link1.NextA := Translator;
    Extractor.Next := Link1;

    Link2 := TAIAgentsLink.Create(Manager);
    Link2.Name  := 'L2'; Link2.Graph := Manager; Link2.NextA := Summarizer;
    Translator.Next := Link2;

    Manager.StartNode := Extractor;
    Manager.EndNode   := Summarizer;
    Manager.Compile;

    // Run the complete pipeline
    Writeln;
    Writeln('Running pipeline...');
    FinalOut := Manager.Run(ATopic);

    // Inspect blackboard checkpoints
    Writeln;
    Writeln(StringOfChar('-', 40));
    Writeln('CHECKPOINT 1 — Extractor.output:');
    Writeln(Manager.Blackboard.GetString('Extractor.output'));
    Writeln;
    Writeln('CHECKPOINT 2 — Translator.output:');
    Writeln(Manager.Blackboard.GetString('Translator.output'));
    Writeln;
    Writeln('CHECKPOINT 3 — Summarizer.output (final output):');
    Writeln(FinalOut);

  finally
    Manager.Free;
  end;
  Writeln;
end;

procedure RunDemo;
begin
  Writeln('=== AgentCheckpoints ===');
  Writeln('Pipeline: [Extractor] -> [Translator] -> [Summarizer]');
  Writeln('Blackboard checkpoints visible after each node.');
  Writeln;

  RunPipeline('Artificial Intelligence');
  RunPipeline('Quantum Computing');
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
