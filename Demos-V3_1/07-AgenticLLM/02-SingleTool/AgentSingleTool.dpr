program AgentSingleTool;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 07-AgenticLLM / 02-SingleTool
// =============================================================================
// The agent uses a custom tool via TAiToolRegistry.
// The LLM automatically decides when to call it (automatic ReAct cycle).
//
// Concepts covered:
//   - IAiTool: tool interface for agents
//   - TAiToolRegistry.Instance.Register: register tools globally
//   - TLLMNode.UseAllTools=True: expose all registered tools
//   - GetSchema: JSON Schema of tool parameters
//   - Execute: tool implementation
//   - ReAct cycle: LLM decides → calls tool → LLM interprets result
//
// Tool: calculator (add, subtract, multiply, divide)
// Structure: [Start] --> [CalculatorAgent] --> [End]
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

// =============================================================================
//  TCalculatorTool
// =============================================================================
type
  TCalculatorTool = class(TInterfacedObject, IAiTool)
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

constructor TCalculatorTool.Create;
var
  Props, Op, Num: TJSONObject;
  Enum, Req     : TJSONArray;
begin
  inherited Create;
  FSchema := TJSONObject.Create;
  FSchema.AddPair('type', 'object');

  Props := TJSONObject.Create;

  Op := TJSONObject.Create;
  Op.AddPair('type', 'string');
  Op.AddPair('description', 'Operation to perform');
  Enum := TJSONArray.Create;
  Enum.Add('add'); Enum.Add('subtract'); Enum.Add('multiply'); Enum.Add('divide');
  Op.AddPair('enum', Enum);
  Props.AddPair('operation', Op);

  Num := TJSONObject.Create;
  Num.AddPair('type', 'number');
  Num.AddPair('description', 'First operand');
  Props.AddPair('a', Num);

  Num := TJSONObject.Create;
  Num.AddPair('type', 'number');
  Num.AddPair('description', 'Second operand');
  Props.AddPair('b', Num);

  FSchema.AddPair('properties', Props);

  Req := TJSONArray.Create;
  Req.Add('operation'); Req.Add('a'); Req.Add('b');
  FSchema.AddPair('required', Req);
end;

destructor TCalculatorTool.Destroy;
begin
  FSchema.Free;
  inherited;
end;

function TCalculatorTool.GetName       : String; begin Result := 'calculator'; end;
function TCalculatorTool.GetDescription: String; begin Result := 'Performs arithmetic operations: addition, subtraction, multiplication, and division'; end;
function TCalculatorTool.GetCategory   : String; begin Result := 'Math'; end;
function TCalculatorTool.GetSchema     : TJSONObject; begin Result := FSchema; end;
function TCalculatorTool.IsAvailable   : Boolean; begin Result := True; end;

function TCalculatorTool.Execute(const AArgs: TJSONObject): TJSONObject;
var
  Op      : String;
  A, B    : Double;
  Res     : Double;
begin
  Result := nil;
  if not Assigned(AArgs) then Exit;

  AArgs.TryGetValue<String>('operation', Op);
  AArgs.TryGetValue<Double>('a', A);
  AArgs.TryGetValue<Double>('b', B);

  Writeln(Format('  [calculator] %s(%g, %g)', [Op, A, B]));

  Res := 0;
  if      Op = 'add'      then Res := A + B
  else if Op = 'subtract' then Res := A - B
  else if Op = 'multiply' then Res := A * B
  else if Op = 'divide'   then
  begin
    if B = 0 then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', 'Division by zero');
      Exit;
    end;
    Res := A / B;
  end;

  Writeln(Format('  [calculator] => %g', [Res]));

  Result := TJSONObject.Create;
  Result.AddPair('result', TJSONNumber.Create(Res));
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunQuery(Manager: TAIAgentManager; const AQuestion: String);
begin
  Manager.Blackboard.Clear;
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', AQuestion);
  Writeln;
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
  Manager  : TAIAgentManager;
  Start    : TAIAgentsNode;
  LLMAgent : TLLMNode;
  Finish   : TAIAgentsNode;
begin
  Writeln('=== AgentSingleTool ===');
  Writeln('Driver: ', DRIVER, ' / ', MODEL);
  Writeln;

  // Register the tool in the global registry
  TAiToolRegistry.Instance.Register(TCalculatorTool.Create, 'local', 'math');
  Writeln('Registered tools: ', TAiToolRegistry.Instance.Count);
  Writeln;

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Manager.TimeoutMs    := 60000;

    Start       := TAIAgentsNode.Create(Manager);
    Start.Name  := 'Start';
    Start.Graph := Manager;

    LLMAgent              := TLLMNode.Create(Manager);
    LLMAgent.Name         := 'CalculatorAgent';
    LLMAgent.Graph        := Manager;
    LLMAgent.DriverName   := DRIVER;
    LLMAgent.Model        := MODEL;
    LLMAgent.ApiKey       := API_KEY;
    LLMAgent.UseAllTools  := True; // exposes all tools from the registry
    LLMAgent.SystemPrompt :=
      'You are a math assistant. ' +
      'ALWAYS use the calculator tool for any arithmetic operation. ' +
      'Never calculate mentally. Respond in Spanish.';

    Finish       := TAIAgentsNode.Create(Manager);
    Finish.Name  := 'End';
    Finish.Graph := Manager;

    Manager.AddEdge('Start',            'CalculatorAgent');
    Manager.AddEdge('CalculatorAgent',  'End');

    Manager.StartNode := Start;
    Manager.EndNode   := Finish;
    Manager.Compile;

    RunQuery(Manager, 'What is 1234 multiplied by 5678?');
    RunQuery(Manager, 'What is (100 + 200) divided by 15?');
    RunQuery(Manager, 'Calculate 15 percent of 840.');
    RunQuery(Manager, 'What is 999 minus 456, and then multiply that result by 3?');

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
  Writeln('Press Enter to exit...');
  Readln;
end.
