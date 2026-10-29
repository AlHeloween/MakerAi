program MultiAgent;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 08-Orchestration / 04-MultiAgent
// =============================================================================
// Five specialized agents perform a structured debate.
// Each agent receives the full debate history up to that point
// thanks to the OnEnterNode callback that injects the accumulated context.
//
// Concepts it covers:
//   - Manager.OnEnterNode: callback before executing each node
//   - Injection of history from the blackboard
//   - Accumulative context between nodes
//   - Linear pipeline of 5 specialized LLMNodes
//
// Pipeline: [Moderador] -> [Ponente] -> [Critico] -> [Replica] -> [Juez]
// =============================================================================

uses
  System.SysUtils,
  Winapi.Windows,
  uMakerAi.Agents,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// =============================================================================
//  TContextoDebate — injects accumulated history into each node
// =============================================================================
type
  TContextoDebate = class
  private
    FManager   : TAIAgentManager;
    FOrdenNodos: TArray<String>;
  public
    constructor Create(AManager: TAIAgentManager);
    procedure InjectarHistorial(Sender: TObject; Node: TAIAgentsNode);
  end;

constructor TContextoDebate.Create(AManager: TAIAgentManager);
begin
  FManager    := AManager;
  FOrdenNodos := ['Moderador', 'Ponente', 'Critico', 'Replica', 'Juez'];
end;

procedure TContextoDebate.InjectarHistorial(Sender: TObject; Node: TAIAgentsNode);
var
  NombreNodo, PrevOut, Historial: String;
begin
  Historial := '';
  for NombreNodo in FOrdenNodos do
  begin
    if NombreNodo = Node.Name then Break;
    PrevOut := FManager.Blackboard.GetString(NombreNodo + '.output');
    if PrevOut <> '' then
      Historial := Historial + '=== ' + NombreNodo + ' ===' + #10 + PrevOut + #10#10;
  end;
  if Historial <> '' then
    Node.Input := '--- TRANSCRIPCION DEL DEBATE ---' + #10 + Historial +
                  '--- REALIZA TU ROL ASIGNADO AHORA ---';
end;

// =============================================================================
//  Helper
// =============================================================================
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

procedure RunDebate(const ATema: String);
var
  Manager   : TAIAgentManager;
  Contexto  : TContextoDebate;
  Moderador : TLLMNode;
  Ponente   : TLLMNode;
  Critico   : TLLMNode;
  Replica   : TLLMNode;
  Juez      : TLLMNode;
  L1, L2, L3, L4: TAIAgentsLink;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Debate topic: ', ATema);
  Writeln(StringOfChar('=', 60));

  Manager  := TAIAgentManager.Create(nil);
  Contexto := TContextoDebate.Create(Manager);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 180000;
    Manager.OnEnterNode  := Contexto.InjectarHistorial;

    // Node 1: Moderator
    Moderador := MakeLLM(Manager, 'Moderador',
      'You are the debate moderator. Given a topic, formulate a clear ' +
      'proposition (statement) and introduce the debate in 2 sentences. ' +
      'Formato: "PROPOSICION: [enunciado]\nINTRODUCCION: [contexto breve]"');

    // Node 2: Speaker (IN FAVOR)
    Ponente := MakeLLM(Manager, 'Ponente',
      'You are an expert debater IN FAVOR of the proposition. ' +
      'Argue with 2 solid reasons. Each argument in 2-3 sentences. ' +
      'Formato: "ARGUMENTOS A FAVOR:\n1. [argumento]\n2. [argumento]"');

    // Node 3: Critic (AGAINST)
    Critico := MakeLLM(Manager, 'Critico',
      'You are an expert debater AGAINST the proposition. ' +
      'Refute each of the speaker''s arguments and add a new objection. ' +
      'Formato: "ARGUMENTOS EN CONTRA:\n1. [refutacion 1]\n2. [refutacion 2]\n3. [nueva objecion]"');

    // Node 4: Rebuttal
    Replica := MakeLLM(Manager, 'Replica',
      'You are the original speaker. Respond to the critic''s strongest objection. ' +
      '2-3 oraciones. Formato: "REPLICA: [tu respuesta]"');

    // Node 5: Judge
    Juez := MakeLLM(Manager, 'Juez',
      'You are an impartial judge. Evaluate both sides of the debate on: ' +
      'argument solidity, evidence, and persuasion. ' +
      'Give scores out of 10 and declare a winner with justification. ' +
      'Formato: "PUNTAJES:\n- Lado A favor: X/10\n- Lado En contra: X/10\nVEREDICTO: [ganador y razon]"');

    // Chain linearly
    L1 := TAIAgentsLink.Create(Manager); L1.Name := 'L1'; L1.Graph := Manager; L1.NextA := Ponente;   Moderador.Next := L1;
    L2 := TAIAgentsLink.Create(Manager); L2.Name := 'L2'; L2.Graph := Manager; L2.NextA := Critico;   Ponente.Next   := L2;
    L3 := TAIAgentsLink.Create(Manager); L3.Name := 'L3'; L3.Graph := Manager; L3.NextA := Replica;   Critico.Next   := L3;
    L4 := TAIAgentsLink.Create(Manager); L4.Name := 'L4'; L4.Graph := Manager; L4.NextA := Juez;      Replica.Next   := L4;

    Manager.StartNode := Moderador;
    Manager.EndNode   := Juez;
    Manager.Compile;

    Writeln;
    var Veredicto := Manager.Run(ATema);

    // Mostrar el debate completo
    Writeln;
    Writeln('--- Moderator ---');
    Writeln(Manager.Blackboard.GetString('Moderador.output'));
    Writeln;
    Writeln('--- Speaker ---');
    Writeln(Manager.Blackboard.GetString('Ponente.output'));
    Writeln;
    Writeln('--- Critic ---');
    Writeln(Manager.Blackboard.GetString('Critico.output'));
    Writeln;
    Writeln('--- Rebuttal ---');
    Writeln(Manager.Blackboard.GetString('Replica.output'));
    Writeln;
    Writeln('--- Judge''s Verdict ---');
    Writeln(Veredicto);

  finally
    Contexto.Free;
    Manager.Free;
  end;
  Writeln;
end;

procedure RunDemo;
begin
  Writeln('=== MultiAgent ===');
  Writeln('5 agents: Moderador -> Ponente -> Critico -> Replica -> Juez');
  Writeln;

  RunDebate('Artificial intelligence will eliminate more jobs than it creates');
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
