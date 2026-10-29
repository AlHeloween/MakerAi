program Sequential;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 08-Orquestacion / 01-Sequential
// =============================================================================
// Linear pipeline of three specialized TLLMNodes.
// The output of each node is the input of the next.
// Fundamental pattern for composing agents.
//
// Concepts it covers:
//   - TAIAgentsLink chaining nodes linearly
//   - Intermediate outputs via Blackboard.GetString('Nodo.output')
//   - Specialization through SystemPrompt
//   - Manager.Run() -> output of the final node
//
// Pipeline: [Analizador] -> [Expansor] -> [Redactor]
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

procedure RunPipeline(const ATema: String);
var
  Manager   : TAIAgentManager;
  Analizador: TLLMNode;
  Expansor  : TLLMNode;
  Redactor  : TLLMNode;
  L1, L2    : TAIAgentsLink;
  Resultado : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATema);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    // Node 1: Extracts 5 key concepts
    Analizador := TLLMNode.Create(Manager);
    Analizador.Name         := 'Analizador';
    Analizador.Graph        := Manager;
    Analizador.DriverName   := DRIVER;
    Analizador.Model        := MODEL;
    Analizador.ApiKey       := API_KEY;
    Analizador.UseAllTools  := False;
    Analizador.SystemPrompt :=
      'You are a concept analyst. Given a topic, list exactly 5 related key ' +
      'concepts. Output ONLY the 5 concepts, one per line, without numbering.';

    // Node 2: Expands each concept with a definition
    Expansor := TLLMNode.Create(Manager);
    Expansor.Name         := 'Expansor';
    Expansor.Graph        := Manager;
    Expansor.DriverName   := DRIVER;
    Expansor.Model        := MODEL;
    Expansor.ApiKey       := API_KEY;
    Expansor.UseAllTools  := False;
    Expansor.SystemPrompt :=
      'You are a concept explainer. You receive a list of concepts (one per line). ' +
      'For each concept write a brief definition in a single sentence in English. ' +
      'Format: "Concept: definition."';

    // Node 3: Generates a short article integrating everything
    Redactor := TLLMNode.Create(Manager);
    Redactor.Name         := 'Redactor';
    Redactor.Graph        := Manager;
    Redactor.DriverName   := DRIVER;
    Redactor.Model        := MODEL;
    Redactor.ApiKey       := API_KEY;
    Redactor.UseAllTools  := False;
    Redactor.SystemPrompt :=
      'You are a technical writer. You receive concept definitions. ' +
      'Write a short article (3 paragraphs) in English that integrates ' +
      'all the concepts naturally and coherently.';

    // Encadenar: Analizador -> Expansor -> Redactor
    L1 := TAIAgentsLink.Create(Manager);
    L1.Name := 'L1'; L1.Graph := Manager; L1.NextA := Expansor;
    Analizador.Next := L1;

    L2 := TAIAgentsLink.Create(Manager);
    L2.Name := 'L2'; L2.Graph := Manager; L2.NextA := Redactor;
    Expansor.Next := L2;

    Manager.StartNode := Analizador;
    Manager.EndNode   := Redactor;
    Manager.Compile;

    Writeln;
    Writeln('Running sequential pipeline...');
    Resultado := Manager.Run(ATema);

    // Show intermediate blackboard outputs
    Writeln;
    Writeln('--- Key concepts (Analizador) ---');
    Writeln(Manager.Blackboard.GetString('Analizador.output'));
    Writeln;
    Writeln('--- Expanded concepts (Expansor) ---');
    Writeln(Manager.Blackboard.GetString('Expansor.output'));
    Writeln;
    Writeln('--- Final article (Redactor) ---');
    Writeln(Resultado);

  finally
    Manager.Free;
  end;
  Writeln;
end;

procedure RunDemo;
begin
  Writeln('=== Sequential ===');
  Writeln('Pattern: [Analizador] -> [Expansor] -> [Redactor]');
  Writeln;

  RunPipeline('Inteligencia Artificial Generativa');
  RunPipeline('Computacion en la nube');
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
