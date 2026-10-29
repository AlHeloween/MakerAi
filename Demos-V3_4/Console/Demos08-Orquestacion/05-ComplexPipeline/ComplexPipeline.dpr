program ComplexPipeline;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 08-Orquestacion / 05-ComplexPipeline
// =============================================================================
// Complex pipeline that combines all patterns:
//   1. Sequential: Clasificador -> Contextualizador
//   2. Fork/Join: two parallel branches (Pros + Cons) -> Sintetizador
//   3. Sequential final: Sintetizador -> Redactor
//
// Given a topic:
//   [Contextualizador] --fork--> [AnalistaPros]  \
//                             \-> [AnalistaCons] --> [Sintetizador (jmAll)] -> [Redactor]
//
// Concepts it covers:
//   - Combination of Sequential + Fork/Join patterns in a single graph
//   - Pipeline with 5 LLM nodes in a mixed topology
//   - Complete inspection of the blackboard
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

function MakeLLM(Manager: TAIAgentManager; const AName, APrompt: String): TLLMNode;
begin
  Result := TLLMNode.Create(Manager);
  Result.Name         := AName;
  Result.Graph        := Manager;
  Result.DriverName   := DRIVER;
  Result.Model        := MODEL;
  Result.ApiKey       := API_KEY;
  Result.UseAllTools  := False;
  Result.SystemPrompt := APrompt;
end;

procedure RunComplexPipeline(const ATema: String);
var
  Manager          : TAIAgentManager;
  Contextualizador : TLLMNode;
  AnalistaPros     : TLLMNode;
  AnalistaCons     : TLLMNode;
  Sintetizador     : TLLMNode;
  Redactor         : TLLMNode;
  ForkLink         : TAIAgentsLink;
  JoinA, JoinB     : TAIAgentsLink;
  SintToRedactor   : TAIAgentsLink;
  Resultado        : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATema);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 180000;

    // Node 1 (sequential): Contextualizador — prepares the topic context
    Contextualizador := MakeLLM(Manager, 'Contextualizador',
      'You are a context analyst. Given a topic, write a ' +
      'brief description (2 sentences) that establishes the context for ' +
      'un analisis de pros y contras. Responde en espanol.');

    // Branch A (fork): advantages analyst
    AnalistaPros := MakeLLM(Manager, 'AnalistaPros',
      'You are an advantages analyst. You receive context about a topic. ' +
      'List the 3 main advantages, one per line. ' +
      'Formato: "PROS:\n+ [ventaja 1]\n+ [ventaja 2]\n+ [ventaja 3]"');

    // Branch B (fork): disadvantages analyst
    AnalistaCons := MakeLLM(Manager, 'AnalistaCons',
      'You are a disadvantages analyst. You receive context about a topic. ' +
      'List the 3 main disadvantages, one per line. ' +
      'Formato: "CONS:\n- [desventaja 1]\n- [desventaja 2]\n- [desventaja 3]"');

    // Join node (jmAll): Sintetizador — combines pros and cons
    Sintetizador := MakeLLM(Manager, 'Sintetizador',
      'You are a synthesizer. You receive the combined output of two analysts: ' +
      'one with PROS and the other with CONS. Synthesize into 2 paragraphs in English: ' +
      'el primero resume las ventajas, el segundo las desventajas.');
    Sintetizador.JoinMode := jmAll;

    // Final node (sequential): Redactor — generates the final article
    Redactor := MakeLLM(Manager, 'Redactor',
      'You are a writer. You receive a synthesized pros and cons analysis. ' +
      'Write a 3-paragraph opinion article in English that ' +
      'presente el tema de forma equilibrada y concluya con una recomendacion.');

    // Sequential link: Contextualizador -> Fork
    ForkLink := TAIAgentsLink.Create(Manager);
    ForkLink.Name := 'Fork'; ForkLink.Graph := Manager;
    ForkLink.NextA := AnalistaPros;
    ForkLink.NextB := AnalistaCons;
    Contextualizador.Next := ForkLink;

    // Join A: AnalistaPros -> Sintetizador
    JoinA := TAIAgentsLink.Create(Manager);
    JoinA.Name := 'JoinA'; JoinA.Graph := Manager; JoinA.NextA := Sintetizador;
    AnalistaPros.Next := JoinA;

    // Join B: AnalistaCons -> Sintetizador
    JoinB := TAIAgentsLink.Create(Manager);
    JoinB.Name := 'JoinB'; JoinB.Graph := Manager; JoinB.NextA := Sintetizador;
    AnalistaCons.Next := JoinB;

    // Sequential link: Sintetizador -> Redactor
    SintToRedactor := TAIAgentsLink.Create(Manager);
    SintToRedactor.Name := 'SintToRed'; SintToRedactor.Graph := Manager;
    SintToRedactor.NextA := Redactor;
    Sintetizador.Next := SintToRedactor;

    Manager.StartNode := Contextualizador;
    Manager.EndNode   := Redactor;
    Manager.Compile;

    Writeln;
    Writeln('Running complex pipeline...');
    Resultado := Manager.Run(ATema);

    // Inspect all checkpoints
    Writeln;
    Writeln('--- Context (Contextualizador) ---');
    Writeln(Manager.Blackboard.GetString('Contextualizador.output'));
    Writeln;
    Writeln('--- Advantages (AnalistaPros) ---');
    Writeln(Manager.Blackboard.GetString('AnalistaPros.output'));
    Writeln;
    Writeln('--- Disadvantages (AnalistaCons) ---');
    Writeln(Manager.Blackboard.GetString('AnalistaCons.output'));
    Writeln;
    Writeln('--- Synthesis (Sintetizador) ---');
    Writeln(Manager.Blackboard.GetString('Sintetizador.output'));
    Writeln;
    Writeln('--- Final article (Redactor) ---');
    Writeln(Resultado);

  finally
    Manager.Free;
  end;
  Writeln;
end;

procedure PrintException(E: Exception);
var
  Agg: EAggregateException;
  I  : Integer;
begin
  if E is EAggregateException then
  begin
    Agg := EAggregateException(E);
    for I := 0 to Agg.Count - 1 do
      Writeln('  [', I, '] ', Agg.InnerExceptions[I].ClassName, ': ',
        Agg.InnerExceptions[I].Message);
  end
  else
    Writeln(E.ClassName, ': ', E.Message);
end;

procedure RunDemo;
begin
  Writeln('=== ComplexPipeline ===');
  Writeln('Combined patterns: Sequential + Fork/Join');
  Writeln('Contextualizador -> [Pros + Cons] -> Sintetizador -> Redactor');
  Writeln;

  RunComplexPipeline('Automatizacion industrial con robotica e IA');
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
    begin
      Writeln('FATAL:');
      PrintException(E);
    end;
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
