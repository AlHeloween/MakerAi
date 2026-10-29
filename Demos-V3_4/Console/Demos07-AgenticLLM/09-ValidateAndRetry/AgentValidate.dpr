program AgentValidate;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — 07-AgenticLLM / 09-ValidateAndRetry
// =============================================================================
// Generation pipeline with automatic validation and rewriting:
//
//   [DraftWriter] -> [Critic (check_quality tool)] -> [Rewriter]
//
// The Critic uses check_quality to evaluate the draft with criteria
// objectives (length, contrast words, rhetorical questions).
// The Rewriter incorporates the feedback to improve the text.
//
// Concepts it covers:
//   - Private registry per node (CriticNode.Registry)
//   - Local validation tool (without LLM, pure business logic)
//   - Context passing: the Critic's output includes DRAFT + FEEDBACK
//   - Reading the intermediate blackboard to see the original draft
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
  uMakerAi.Agents,
  uMakerAi.Agents.IAiTool,
  uMakerAi.Agents.ToolRegistry,
  uMakerAi.Agents.Node.LLM,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// -----------------------------------------------------------------------------
// TQualityCheckerTool — checks quality criteria in a text
// Args:    { "text": string, "criteria": string }
// Returns: { "score": number, "issues": string, "passed": bool, "word_count": number }
// -----------------------------------------------------------------------------
type
  TQualityCheckerTool = class(TInterfacedObject, IAiTool)
  private
    FSchema: TJSONObject;
  public
    constructor Create;
    destructor  Destroy; override;
    function GetName       : String;
    function GetDescription: String;
    function GetCategory   : String;
    function GetSchema     : TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable   : Boolean;
  end;

constructor TQualityCheckerTool.Create;
var Props, Txt, Crit: TJSONObject; Req: TJSONArray;
begin
  inherited;
  FSchema := TJSONObject.Create;
  FSchema.AddPair('type', 'object');
  Props := TJSONObject.Create;
  Txt  := TJSONObject.Create; Txt.AddPair('type',  'string'); Txt.AddPair('description',  'Text to evaluate');
  Props.AddPair('text', Txt);
  Crit := TJSONObject.Create; Crit.AddPair('type', 'string'); Crit.AddPair('description', 'Quality criteria to check');
  Props.AddPair('criteria', Crit);
  FSchema.AddPair('properties', Props);
  Req := TJSONArray.Create; Req.Add('text'); Req.Add('criteria');
  FSchema.AddPair('required', Req);
end;

destructor TQualityCheckerTool.Destroy; begin FSchema.Free; inherited; end;
function TQualityCheckerTool.GetName       : String; begin Result := 'check_quality'; end;
function TQualityCheckerTool.GetDescription: String; begin Result := 'Checks text quality. Returns score (0-10), issues found, and pass/fail.'; end;
function TQualityCheckerTool.GetCategory   : String; begin Result := 'Quality'; end;
function TQualityCheckerTool.GetSchema     : TJSONObject; begin Result := FSchema; end;
function TQualityCheckerTool.IsAvailable   : Boolean; begin Result := True; end;

function TQualityCheckerTool.Execute(const AArgs: TJSONObject): TJSONObject;
var
  Txt, Crit : String;
  WordCount : Integer;
  Score     : Integer;
  Issues    : String;
  Words     : TArray<String>;
begin
  Result := nil;
  if not Assigned(AArgs) then Exit;
  AArgs.TryGetValue<String>('text',     Txt);
  AArgs.TryGetValue<String>('criteria', Crit);

  Words     := Txt.Trim.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty);
  WordCount := Length(Words);
  Score     := 10;
  Issues    := '';

  if WordCount < 50 then begin
    Dec(Score, 3); Issues := Issues + 'Too short (< 50 words). ';
  end;
  if WordCount > 500 then begin
    Dec(Score, 1); Issues := Issues + 'Too long (> 500 words). ';
  end;
  if Pos('?', Txt) = 0 then begin
    Dec(Score, 1); Issues := Issues + 'No rhetorical questions. ';
  end;
  if (Pos('however', LowerCase(Txt)) = 0) and (Pos('but', LowerCase(Txt)) = 0)
  and (Pos('although', LowerCase(Txt)) = 0) then begin
    Dec(Score, 1); Issues := Issues + 'No contrast words (however/but/although). ';
  end;
  if Score < 0 then Score := 0;

  Writeln(Format('  [check_quality] words=%d score=%d/10 issues: %s',
                 [WordCount, Score, Issues]));

  Result := TJSONObject.Create;
  Result.AddPair('score',      TJSONNumber.Create(Score));
  Result.AddPair('issues',     Issues);
  Result.AddPair('passed',     TJSONBool.Create(Score >= 7));
  Result.AddPair('word_count', TJSONNumber.Create(WordCount));
end;

// =============================================================================
// MAIN DEMO
// =============================================================================

function MakeLLMNode(Manager: TAIAgentManager; const AName, ASystemPrompt: String;
  UseTools: Boolean = False): TLLMNode;
begin
  Result := TLLMNode.Create(Manager);
  Result.Name         := AName;
  Result.Graph        := Manager;
  Result.DriverName   := DRIVER;
  Result.Model        := MODEL;
  Result.ApiKey       := API_KEY;
  Result.UseAllTools  := UseTools;
  Result.SystemPrompt := ASystemPrompt;
end;

procedure RunPipeline(const ATask: String);
var
  Manager        : TAIAgentManager;
  DraftNode      : TLLMNode;
  CriticNode     : TLLMNode;
  RewriteNode    : TLLMNode;
  CriticRegistry : TAiToolRegistry;
  Link1, Link2   : TAIAgentsLink;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('Task: ', ATask);
  Writeln(StringOfChar('=', 60));

  Manager        := TAIAgentManager.Create(nil);
  CriticRegistry := TAiToolRegistry.Create;
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 120000;

    CriticRegistry.Register(TQualityCheckerTool.Create, 'local', 'quality');

    // Node 1: Draft writer
    DraftNode := MakeLLMNode(Manager, 'DraftWriter',
      'You are a content writer. Write a draft paragraph (80-150 words) about the given topic. ' +
      'Use at least one contrast word (however/but/although) and one rhetorical question.');

    // Node 2: Critic — validates with check_quality and generates structured feedback
    CriticNode := MakeLLMNode(Manager, 'Critic',
      'You are a strict editor. Evaluate the draft using check_quality tool. ' +
      'Then provide specific improvement suggestions in this exact format: ' +
      '"DRAFT:\n[the draft]\n\nFEEDBACK:\n[your suggestions]\n\nIMPROVEMENT INSTRUCTIONS:\n[3 concrete actions]"',
      True);
    CriticNode.Registry := CriticRegistry;

    // Node 3: Rewriter — incorporates the feedback
    RewriteNode := MakeLLMNode(Manager, 'Rewriter',
      'You are an expert writer. You receive a draft and detailed feedback. ' +
      'Rewrite the draft incorporating ALL the improvement instructions. ' +
      'The rewritten version should be clearly better than the original.');

    // DraftWriter -> Critic -> Rewriter
    Link1 := TAIAgentsLink.Create(Manager); Link1.Name := 'L1'; Link1.Graph := Manager; Link1.NextA := CriticNode;  DraftNode.Next  := Link1;
    Link2 := TAIAgentsLink.Create(Manager); Link2.Name := 'L2'; Link2.Graph := Manager; Link2.NextA := RewriteNode; CriticNode.Next := Link2;

    Manager.StartNode := DraftNode;
    Manager.EndNode   := RewriteNode;
    Manager.Compile;

    Writeln;
    var FinalText := Manager.Run(ATask);

    Writeln;
    Writeln('--- Initial draft ---');
    Writeln(Manager.Blackboard.GetString('DraftWriter.output'));
    Writeln;
    Writeln('--- Critic feedback ---');
    Writeln(Manager.Blackboard.GetString('Critic.output'));
    Writeln;
    Writeln('--- Final rewritten version ---');
    Writeln(FinalText);

  finally
    CriticRegistry.Free;
    Manager.Free;
  end;
  Writeln;
end;

begin
  Writeln('=== AgentValidate ===');
  Writeln('Pipeline: DraftWriter -> Critic (check_quality) -> Rewriter');
  Writeln;
  try
    RunPipeline('The importance of sleep for productivity');
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
