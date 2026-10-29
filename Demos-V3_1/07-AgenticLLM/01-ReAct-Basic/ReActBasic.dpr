program ReActBasic;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 07-AgenticLLM / 01-ReAct-Basic
// =============================================================================
// El patrón ReAct (Reasoning + Acting) es la base de todos los agentes LLM.
// En MakerAI se implementa con TAIAgentManager + TLLMNode.
//
// Concepts covered:
//   - TAIAgentManager: orquestador del grafo de agentes
//   - TLLMNode: nodo que contiene el loop ReAct con el proveedor LLM
//   - TAIAgentsNode: nodo genérico (pasante o con OnExecute)
//   - TAIAgentsLink: arista que conecta nodos
//   - Manager.StartNode / EndNode / Compile / Run
//   - Manager.Blackboard: estado compartido entre nodos
//   - Manager.Asynchronous=False: ejecución síncrona
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
//  Ejecuta una pregunta y muestra la respuesta
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

    // Entry node (pass-through: propagates Input -> Output)
    Start       := TAIAgentsNode.Create(Manager);
    Start.Name  := 'Start';
    Start.Graph := Manager;

    // LLM node: the agent executes the ReAct cycle
    LLMAgent              := TLLMNode.Create(Manager);
    LLMAgent.Name         := 'LLMAgent';
    LLMAgent.Graph        := Manager;
    LLMAgent.DriverName   := DRIVER;
    LLMAgent.Model        := MODEL;
    LLMAgent.ApiKey       := API_KEY;
    LLMAgent.UseAllTools  := False;
    LLMAgent.SystemPrompt :=
      'Eres un asistente conciso que responde en espanol. ' +
      'Responde siempre en una o dos frases directas y al grano.';

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
  Writeln('Presiona Enter para salir...');
  Readln;
end.
