program ConditionalRouter;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 08-Orchestration / 03-ConditionalRouter
// =============================================================================
// An LLM classifier determines the route at runtime.
// A router node (plain node with OnExecute) reads the classification from
// the blackboard and writes the key 'ruta'. A conditional link dispatches
// to the correct specialist.
//
// Concepts it covers:
//   - TAIAgentsLink.Mode := lmConditional
//   - TAIAgentsLink.ConditionalKey: key in the blackboard that decides the route
//   - TAIAgentsLink.AddConditionalTarget(key, node)
//   - TAIAgentsNode.OnExecute: routing logic without LLM
//   - TLLMNode.JoinMode := jmAny: the formatter only receives one specialist
//
// Structure:
//   [Clasificador] -> [Router (OnExecute)] --lmConditional-->
//     math    -> [EspecialistaMath]     \
//     science -> [EspecialistaCiencia]  --> [Formatter (jmAny)]
//     history -> [EspecialistaHistoria] /
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

// =============================================================================
//  TRouterLogic: routing logic without LLM
// =============================================================================
type
  TRouterLogic = class
  public
    procedure Execute(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
      Input: String; var Output: String);
  end;

procedure TRouterLogic.Execute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
var
  Clasificacion, Ruta, PrimeraP: String;
begin
  Clasificacion := Trim(LowerCase(Node.Graph.Blackboard.GetString('Clasificador.output')));

  // Take the first word of the classification
  Ruta := 'history'; // default
  PrimeraP := '';
  if Length(Clasificacion) > 0 then
  begin
    var Parts := Clasificacion.Split([' ', #10, #13, #9, '.', ',']);
    if Length(Parts) > 0 then
      PrimeraP := Trim(Parts[0]);
  end;

  if PrimeraP = 'math' then Ruta := 'math'
  else if PrimeraP = 'science' then Ruta := 'science'
  else if PrimeraP = 'history' then Ruta := 'history'
  else
  begin
    if Clasificacion.Contains('math') then Ruta := 'math'
    else if Clasificacion.Contains('science') then Ruta := 'science'
    else if Clasificacion.Contains('history') then Ruta := 'history';
  end;

  Node.Graph.Blackboard.SetString('ruta', Ruta);
  Writeln(Format('  [Router] Classification="%s" -> Route="%s"', [Clasificacion, Ruta]));

  // Pass the original question (not the classification)
  if Assigned(BeforeNode) then
    Output := BeforeNode.Input
  else
    Output := Input;
end;

// =============================================================================
//  Helper: create TLLMNode
// =============================================================================
function MakeLLM(Manager: TAIAgentManager; const AName, APrompt: String;
  UseTools: Boolean = False): TLLMNode;
begin
  Result := TLLMNode.Create(Manager);
  Result.Name         := AName;
  Result.Graph        := Manager;
  Result.DriverName   := DRIVER;
  Result.Model        := MODEL;
  Result.ApiKey       := API_KEY;
  Result.UseAllTools  := UseTools;
  Result.SystemPrompt := APrompt;
end;

procedure RunQuery(Manager: TAIAgentManager; const APregunta: String);
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', APregunta);
  try
    Writeln;
    Writeln('Answer: ', Manager.Run(APregunta));
  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;
  Writeln;
end;

procedure RunDemo;
var
  Manager       : TAIAgentManager;
  RouterLogic   : TRouterLogic;
  Clasificador  : TLLMNode;
  RouterNode    : TAIAgentsNode;
  EspMath       : TLLMNode;
  EspCiencia    : TLLMNode;
  EspHistoria   : TLLMNode;
  Formatter     : TLLMNode;
  ToRouter      : TAIAgentsLink;
  CondLink      : TAIAgentsLink;
  JoinMath      : TAIAgentsLink;
  JoinCiencia   : TAIAgentsLink;
  JoinHistoria  : TAIAgentsLink;
  Targets       : TDictionary<String, TAIAgentsNode>;
begin
  Writeln('=== ConditionalRouter ===');
  Writeln('Pattern: Clasificador -> Router -> Especialista (math|science|history) -> Formatter');
  Writeln;

  RouterLogic := TRouterLogic.Create;
  Manager     := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 90000;

    // Classifier: returns ONE word
    Clasificador := MakeLLM(Manager, 'Clasificador',
      'You are a CLASSIFIER. Your job is to return ONE single word.' + #10 +
      'Given a question, respond ONLY with one of these exact words: math  science  history' + #10 +
      'Sin explicaciones. Sin puntuacion. Solo una palabra.');
    Clasificador.MaxTokens := 3;

    // Router: node without LLM that reads the blackboard
    RouterNode := TAIAgentsNode.Create(Manager);
    RouterNode.Name      := 'Router';
    RouterNode.Graph     := Manager;
    RouterNode.OnExecute := RouterLogic.Execute;

    // Specialists
    EspMath := MakeLLM(Manager, 'EspecialistaMath',
      'You are a mathematics expert. Answer the question clearly ' +
      'mostrando todos los pasos si hay calculos. Responde en espanol.');

    EspCiencia := MakeLLM(Manager, 'EspecialistaCiencia',
      'You are a science expert. Answer with scientific precision ' +
      'usando lenguaje claro. Responde en espanol.');

    EspHistoria := MakeLLM(Manager, 'EspecialistaHistoria',
      'You are a history expert. Answer with historical context ' +
      'y datos clave. Responde en espanol.');

    // Final formatter: jmAny (only one specialist arrives)
    Formatter := MakeLLM(Manager, 'Formatter',
      'You receive an expert''s answer. ' +
      'Format it: add a brief title, then the structured answer. ' +
      'Mantén la concision. Responde en espanol.');
    Formatter.JoinMode := jmAny;

    // Link: Classifier -> Router
    ToRouter := TAIAgentsLink.Create(Manager);
    ToRouter.Name := 'ToRouter'; ToRouter.Graph := Manager; ToRouter.NextA := RouterNode;
    Clasificador.Next := ToRouter;

    // Conditional link: Router -> (EspMath | EspCiencia | EspHistoria)
    CondLink := TAIAgentsLink.Create(Manager);
    CondLink.Name := 'CondLink'; CondLink.Graph := Manager;
    CondLink.Mode := lmConditional;
    CondLink.ConditionalKey := 'ruta';

    Targets := TDictionary<String, TAIAgentsNode>.Create;
    try
      Targets.Add('math',    EspMath);
      Targets.Add('science', EspCiencia);
      Targets.Add('history', EspHistoria);
      for var Pair in Targets do
        CondLink.AddConditionalTarget(Pair.Key, Pair.Value);
    finally
      Targets.Free;
    end;
    RouterNode.Next := CondLink;

    // Joins: each specialist -> Formatter
    JoinMath := TAIAgentsLink.Create(Manager);
    JoinMath.Name := 'JoinMath'; JoinMath.Graph := Manager; JoinMath.NextA := Formatter;
    EspMath.Next := JoinMath;

    JoinCiencia := TAIAgentsLink.Create(Manager);
    JoinCiencia.Name := 'JoinCiencia'; JoinCiencia.Graph := Manager; JoinCiencia.NextA := Formatter;
    EspCiencia.Next := JoinCiencia;

    JoinHistoria := TAIAgentsLink.Create(Manager);
    JoinHistoria.Name := 'JoinHistoria'; JoinHistoria.Graph := Manager; JoinHistoria.NextA := Formatter;
    EspHistoria.Next := JoinHistoria;

    Manager.StartNode := Clasificador;
    Manager.EndNode   := Formatter;
    Manager.Compile;

    // Queries from different categories
    RunQuery(Manager, 'What is the square root of 225?');
    RunQuery(Manager, 'How does photosynthesis work?');
    RunQuery(Manager, 'When did World War II end?');
    RunQuery(Manager, 'What is 18 percent of 350?');
    RunQuery(Manager, 'What causes a solar eclipse?');

  finally
    Manager.Free;
    RouterLogic.Free;
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
