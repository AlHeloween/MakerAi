program AgentRouter;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — 07-AgenticLLM / 07-ConditionalRouter
// =============================================================================
// An LLM classifier determines the route and a conditional link dispatches
// to the correct specialist:
//
//   [Classifier] -> [RouterNode] --lmConditional--> [MathSpecialist]
//                                               \-> [ScienceSpecialist]
//                                               \-> [HistorySpecialist]
//                                                         |
//                                                  [FinalFormatter] (jmAny)
//
// Concepts it covers:
//   - TAIAgentsLink.Mode = lmConditional: routing by blackboard value
//   - TAIAgentsLink.ConditionalKey: key evaluated in the blackboard
//   - TAIAgentsLink.AddConditionalTarget: value -> destination node mapping
//   - Plain node with OnExecute: routing logic without LLM
//   - JoinMode = jmAny: the formatter accepts any of the three specialists
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

// -----------------------------------------------------------------------------
// TRouterHelper: reads the classification from the blackboard and writes the 'route' key
// -----------------------------------------------------------------------------
type
  TRouterHelper = class
  public
    procedure Execute(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
      Input: String; var Output: String);
  end;

procedure TRouterHelper.Execute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
var
  Classification: String;
  Route         : String;
  FirstWord     : String;
begin
  Classification := Trim(LowerCase(Node.Graph.Blackboard.GetString('Classifier.output')));

  // Normalize: take the first word (the LLM sometimes generates extra text)
  Route     := 'history';  // default value
  FirstWord := '';
  if Length(Classification) > 0 then
    FirstWord := Trim(Classification.Split([' ', #10, #13, #9, '.', ','])[0]);

  if      FirstWord = 'math'    then Route := 'math'
  else if FirstWord = 'science' then Route := 'science'
  else if FirstWord = 'history' then Route := 'history'
  else begin
    // Fallback: search the full text
    if      Pos('math',    Classification) > 0 then Route := 'math'
    else if Pos('science', Classification) > 0 then Route := 'science';
  end;

  Node.Graph.Blackboard.SetString('route', Route);
  Writeln(Format('  [Router] Classification="%s" -> Route="%s"', [Classification, Route]));

  // Pass the original question (not the classification text)
  if Assigned(BeforeNode) then
    Output := BeforeNode.Input
  else
    Output := Input;
end;

// -----------------------------------------------------------------------------

function MakeLLMNode(Manager: TAIAgentManager; const AName, ASystemPrompt: String): TLLMNode;
begin
  Result := TLLMNode.Create(Manager);
  Result.Name         := AName;
  Result.Graph        := Manager;
  Result.DriverName   := DRIVER;
  Result.Model        := MODEL;
  Result.ApiKey       := API_KEY;
  Result.UseAllTools  := False;
  Result.SystemPrompt := ASystemPrompt;
end;

procedure RunQuery(Manager: TAIAgentManager; const AQuestion: String);
begin
  Manager.Blackboard.Clear;
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', AQuestion);
  try
    Writeln('Answer: ', Manager.Run(AQuestion));
  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;
  Writeln;
end;

procedure RunDemo;
var
  Manager      : TAIAgentManager;
  RouterHelper : TRouterHelper;
  Classifier   : TLLMNode;
  MathSpec     : TLLMNode;
  ScienceSpec  : TLLMNode;
  HistorySpec  : TLLMNode;
  FinalFmt     : TLLMNode;
  RouterNode   : TAIAgentsNode;
  RouterLink   : TAIAgentsLink;
  CondLink     : TAIAgentsLink;
  JoinMath     : TAIAgentsLink;
  JoinSci      : TAIAgentsLink;
  JoinHist     : TAIAgentsLink;
  CondTargets  : TDictionary<String, TAIAgentsNode>;
begin
  RouterHelper := TRouterHelper.Create;
  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 90000;

    // Classifier: emits ONE word (math/science/history)
    Classifier := MakeLLMNode(Manager, 'Classifier',
      'You are a CLASSIFIER. Output ONE word only. Do not answer the question.' + #10 +
      'Given a question, output EXACTLY one of: math  science  history' + #10 +
      'No explanations. No punctuation. Just one word.');
    Classifier.MaxTokens := 3;

    // Router node: reads the classification and writes 'route' in the blackboard
    RouterNode := TAIAgentsNode.Create(Manager);
    RouterNode.Name      := 'Router';
    RouterNode.Graph     := Manager;
    RouterNode.OnExecute := RouterHelper.Execute;

    // Specialists
    MathSpec := MakeLLMNode(Manager, 'MathSpecialist',
      'You are a math expert. Answer clearly, showing all steps if needed.');

    ScienceSpec := MakeLLMNode(Manager, 'ScienceSpecialist',
      'You are a science expert. Answer with scientific accuracy and clear language.');

    HistorySpec := MakeLLMNode(Manager, 'HistorySpecialist',
      'You are a history expert. Answer with historical context and key facts.');

    // Final formatter: accepts the first one that arrives (jmAny, only one activates)
    FinalFmt := MakeLLMNode(Manager, 'FinalFormatter',
      'You receive an expert answer. Format it nicely: add a brief title, ' +
      'then the answer. Keep it concise and well-structured.');
    FinalFmt.JoinMode := jmAny;

    // Classifier -> RouterNode
    RouterLink := TAIAgentsLink.Create(Manager);
    RouterLink.Name  := 'ToRouter';
    RouterLink.Graph := Manager;
    RouterLink.NextA := RouterNode;
    Classifier.Next  := RouterLink;

    // RouterNode -> specialist according to 'route'
    CondLink := TAIAgentsLink.Create(Manager);
    CondLink.Name           := 'CondLink';
    CondLink.Graph          := Manager;
    CondLink.Mode           := lmConditional;
    CondLink.ConditionalKey := 'route';

    CondTargets := TDictionary<String, TAIAgentsNode>.Create;
    try
      CondTargets.Add('math',    MathSpec);
      CondTargets.Add('science', ScienceSpec);
      CondTargets.Add('history', HistorySpec);
      for var Pair in CondTargets do
        CondLink.AddConditionalTarget(Pair.Key, Pair.Value);
    finally
      CondTargets.Free;
    end;
    RouterNode.Next := CondLink;

    // Each specialist -> FinalFormatter
    JoinMath := TAIAgentsLink.Create(Manager);
    JoinMath.Name := 'JoinMath'; JoinMath.Graph := Manager; JoinMath.NextA := FinalFmt;
    MathSpec.Next := JoinMath;

    JoinSci := TAIAgentsLink.Create(Manager);
    JoinSci.Name := 'JoinSci'; JoinSci.Graph := Manager; JoinSci.NextA := FinalFmt;
    ScienceSpec.Next := JoinSci;

    JoinHist := TAIAgentsLink.Create(Manager);
    JoinHist.Name := 'JoinHist'; JoinHist.Graph := Manager; JoinHist.NextA := FinalFmt;
    HistorySpec.Next := JoinHist;

    Manager.StartNode := Classifier;
    Manager.EndNode   := FinalFmt;
    Manager.Compile;

    RunQuery(Manager, 'What is the square root of 144?');
    RunQuery(Manager, 'How does photosynthesis work?');
    RunQuery(Manager, 'When did World War II end?');
    RunQuery(Manager, 'What is 15 percent of 240?');
    RunQuery(Manager, 'What causes a solar eclipse?');

  finally
    Manager.Free;
    RouterHelper.Free;
  end;
end;

begin
  Writeln('=== AgentRouter ===');
  Writeln('Pattern: Classifier -> Router (lmConditional) -> Specialist -> Formatter');
  Writeln;
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
