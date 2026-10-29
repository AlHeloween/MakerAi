program ForkJoin;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 08-Orquestacion / 02-Fork-Join
// =============================================================================
// Fork/Join pattern: an input splits into two parallel branches that
// join at a synthesis node that waits for both results (jmAll).
//
// Concepts covered:
//   - TAIAgentsLink with NextA + NextB: fork
//   - TLLMNode.JoinMode := jmAll: waits for ALL incoming inputs
//   - Parallel execution of two independent branches
//   - Blackboard to inspect each branch separately
//
// Structure:
//   [Preparador] --fork--> [AnalistaPros]  --join--\
//                      \-> [AnalistaCons] --join--> [Sintetizador (jmAll)]
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

procedure RunForkJoin(const ATema: String);
var
  Manager     : TAIAgentManager;
  Preparador  : TLLMNode;
  AnalistaPros: TLLMNode;
  AnalistaCons: TLLMNode;
  Sintetizador: TLLMNode;
  ForkLink    : TAIAgentsLink;
  JoinLinkA   : TAIAgentsLink;
  JoinLinkB   : TAIAgentsLink;
  Resultado   : String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Topic: ', ATema);
  Writeln(StringOfChar('=', 60));

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    // Node 0: Preparador — formulates the research question
    Preparador := TLLMNode.Create(Manager);
    Preparador.Name         := 'Preparador';
    Preparador.Graph        := Manager;
    Preparador.DriverName   := DRIVER;
    Preparador.Model        := MODEL;
    Preparador.ApiKey       := API_KEY;
    Preparador.UseAllTools  := False;
    Preparador.SystemPrompt :=
      'You are a research coordinator. Given a topic, formulate a ' +
      'clear and concise research question. Write ONLY the question, nothing else.';

    // Branch A: Advantages analyst
    AnalistaPros := TLLMNode.Create(Manager);
    AnalistaPros.Name         := 'AnalistaPros';
    AnalistaPros.Graph        := Manager;
    AnalistaPros.DriverName   := DRIVER;
    AnalistaPros.Model        := MODEL;
    AnalistaPros.ApiKey       := API_KEY;
    AnalistaPros.UseAllTools  := False;
    AnalistaPros.SystemPrompt :=
      'You are an advantages analyst. Given a question, respond EXACTLY with:' + #10 +
      'ADVANTAGES:' + #10 +
      '1. [advantage in one sentence]' + #10 +
      '2. [advantage in one sentence]' + #10 +
      '3. [advantage in one sentence]' + #10 +
      'Only that. No additional text.';

    // Branch B: Disadvantages analyst
    AnalistaCons := TLLMNode.Create(Manager);
    AnalistaCons.Name         := 'AnalistaCons';
    AnalistaCons.Graph        := Manager;
    AnalistaCons.DriverName   := DRIVER;
    AnalistaCons.Model        := MODEL;
    AnalistaCons.ApiKey       := API_KEY;
    AnalistaCons.UseAllTools  := False;
    AnalistaCons.SystemPrompt :=
      'You are a disadvantages analyst. Given a question, respond EXACTLY with:' + #10 +
      'DISADVANTAGES:' + #10 +
      '1. [disadvantage in one sentence]' + #10 +
      '2. [disadvantage in one sentence]' + #10 +
      '3. [disadvantage in one sentence]' + #10 +
      'Only that. No additional text.';

    // Join node: Sintetizador (jmAll — waits for both branches)
    Sintetizador := TLLMNode.Create(Manager);
    Sintetizador.Name         := 'Sintetizador';
    Sintetizador.Graph        := Manager;
    Sintetizador.DriverName   := DRIVER;
    Sintetizador.Model        := MODEL;
    Sintetizador.ApiKey       := API_KEY;
    Sintetizador.UseAllTools  := False;
    Sintetizador.JoinMode     := jmAll;
    Sintetizador.SystemPrompt :=
      'You are a balanced analyst. You receive the combined output of two researchers: ' +
      'one listing ADVANTAGES and the other listing DISADVANTAGES. ' +
      'Synthesize both into a balanced verdict of 3-4 sentences in Spanish. ' +
      'End with a clear recommendation.';

    // Fork: Preparador -> (AnalistaPros, AnalistaCons) in parallel
    ForkLink := TAIAgentsLink.Create(Manager);
    ForkLink.Name  := 'Fork'; ForkLink.Graph := Manager;
    ForkLink.NextA := AnalistaPros;
    ForkLink.NextB := AnalistaCons;
    Preparador.Next := ForkLink;

    // Join A: AnalistaPros -> Sintetizador
    JoinLinkA := TAIAgentsLink.Create(Manager);
    JoinLinkA.Name := 'JoinA'; JoinLinkA.Graph := Manager; JoinLinkA.NextA := Sintetizador;
    AnalistaPros.Next := JoinLinkA;

    // Join B: AnalistaCons -> Sintetizador
    JoinLinkB := TAIAgentsLink.Create(Manager);
    JoinLinkB.Name := 'JoinB'; JoinLinkB.Graph := Manager; JoinLinkB.NextA := Sintetizador;
    AnalistaCons.Next := JoinLinkB;

    Manager.StartNode := Preparador;
    Manager.EndNode   := Sintetizador;
    Manager.Compile;

    Writeln;
    Writeln('Running Fork/Join in parallel...');
    Resultado := Manager.Run(ATema);

    Writeln;
    Writeln('--- Research question (Preparador) ---');
    Writeln(Manager.Blackboard.GetString('Preparador.output'));
    Writeln;
    Writeln('--- ADVANTAGES analysis (AnalistaPros) ---');
    Writeln(Manager.Blackboard.GetString('AnalistaPros.output'));
    Writeln;
    Writeln('--- DISADVANTAGES analysis (AnalistaCons) ---');
    Writeln(Manager.Blackboard.GetString('AnalistaCons.output'));
    Writeln;
    Writeln('--- Final verdict (Sintetizador) ---');
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
  Writeln('=== ForkJoin ===');
  Writeln('Pattern: [Preparador] --fork--> [Pros + Cons] --join--> [Sintetizador]');
  Writeln;

  RunForkJoin('Artificial Intelligence in education');
  Writeln('Pause between topics (10s)...');
  Sleep(10000);
  RunForkJoin('Remote work for software developers');
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
