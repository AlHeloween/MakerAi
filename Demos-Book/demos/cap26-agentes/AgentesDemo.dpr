program AgentesDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 26: Building Agents with TLLMNode
// =============================================================================
// Two orchestration scenarios with TAIAgentManager:
//
// Scenario A -- Without TLLMNode: manual pipeline with TAIAgentsNode + OnExecute.
//   Each node invokes TAiChatConnection directly inside the handler.
//   Handlers are class methods because OnExecute is "of object".
//   Shows that nodes can mix LLM logic and ordinary logic.
//
// Scenario B -- With TLLMNode: autonomous agent with IAiTool tools.
//   TLLMNode handles the ReAct loop (Reason->Act->Observe) internally.
//   Tools are implemented as TInterfacedObject + IAiTool.
//   TAiToolRegistry is the central tool catalog.
//
// Driver: Claude (CLAUDE_API_KEY). Change DRV/MDL/APIKEY for another provider.
// =============================================================================

uses
  System.SysUtils, System.Classes, System.JSON, System.Math,
  uMakerAi.Agents,               // TAIAgentManager, TAIAgentsNode, TAIBlackboard
  uMakerAi.Agents.Node.LLM,     // TLLMNode
  uMakerAi.Agents.IAiTool,      // IAiTool
  uMakerAi.Agents.ToolRegistry, // TAiToolRegistry
  uMakerAi.Chat.AiConnection,   // TAiChatConnection (conector universal)
  uMakerAi.Chat.Initializations; // auto-registra todos los drivers

// ---------------------------------------------------------------------------
//  Configuracion del provider
// ---------------------------------------------------------------------------

const
  DRV    = 'Claude';
  MDL    = 'claude-haiku-4-5-20251001';
  APIKEY = '@CLAUDE_API_KEY';

// Test text for the editorial pipeline
const
  TEXTO_PRUEBA =
    'Large language models are transforming enterprise ' +
    'software development. Frameworks like MakerAI allow Delphi teams ' +
    'to integrate artificial intelligence without abandoning their existing ' +
    'technology stack. The combination of FMX components with autonomous ' +
    'agents opens new possibilities for process automation.';

// ---------------------------------------------------------------------------
//  Helpers de presentacion
// ---------------------------------------------------------------------------

procedure Separador(const Titulo: string);
begin
  WriteLn;
  WriteLn(StringOfChar('-', 64));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 64));
end;

// ===========================================================================
//  SCENARIO A -- Manual pipeline without TLLMNode
// ===========================================================================
//  Wrapper class required because TAIAgentsNodeOnExecute is "of object":
//  handlers must be methods of a class instance.
//
//  Graph: Analyze --> Summarize --> Format
//    Node 1 (Analyze):  calls the LLM to detect topic and tone
//    Node 2 (Summarize):   calls the LLM to generate an executive summary
//    Node 3 (Format): local logic -- does not need LLM
//
//  TAIAgentManager.Asynchronous := False --> Manager.Run() blocks.
// ===========================================================================

type
  TDemoA = class
  private
    FDriver : String;
    FModel  : String;
    FApiKey : String;
    // Synchronous LLM call -- safe from manager worker threads
    function LlmCall(const AInput, ASystem: String): String;
    // Handlers "of object" -- one per pipeline node
    procedure OnAnalizar(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
      Input: String; var Output: String);
    procedure OnResumir(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
      Input: String; var Output: String);
    procedure OnFormatear(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
      Input: String; var Output: String);
  public
    constructor Create(const ADriver, AModel, AApiKey: String);
    function Run(const ATexto: String): String;
  end;

{ TDemoA }

constructor TDemoA.Create(const ADriver, AModel, AApiKey: String);
begin
  FDriver := ADriver;
  FModel  := AModel;
  FApiKey := AApiKey;
end;

function TDemoA.LlmCall(const AInput, ASystem: String): String;
var
  Chat: TAiChatConnection;
begin
  Chat := TAiChatConnection.Create(nil);
  try
    Chat.DriverName                    := FDriver;
    Chat.Model                         := FModel;
    Chat.Params.Values['ApiKey']       := FApiKey;
    Chat.Params.Values['Asynchronous'] := 'False'; // sincrono en worker thread
    Chat.SystemPrompt.Text             := ASystem;
    Result := Chat.AddMessageAndRun(AInput, 'user', []);
  finally
    Chat.Free;
  end;
end;

procedure TDemoA.OnAnalizar(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
  Input: String; var Output: String);
begin
  WriteLn('    [Analyze] identifying topic and tone...');
  Output := LlmCall(
    'Analyze the following text. Identify in 3 lines: ' +
    '1) Main topic, 2) Tone (formal or informal), 3) Target audience.' +
    #13#10 + 'Text: ' + Input,
    'You are an expert editorial analyst. Respond in Spanish, maximum 3 lines.');
end;

procedure TDemoA.OnResumir(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
  Input: String; var Output: String);
begin
  WriteLn('    [Summarize] generating executive summary...');
  Output := LlmCall(
    'Based on the following editorial analysis, write an executive summary ' +
    'of exactly 2 sentences that capture the essence of the content.' +
    #13#10 + 'Analysis: ' + Input,
    'You are an expert writer. Be precise. Respond in Spanish.');
end;

procedure TDemoA.OnFormatear(Node, Before: TAIAgentsNode; Link: TAIAgentsLink;
  Input: String; var Output: String);
begin
  WriteLn('    [Format] applying final structure (without LLM)...');
  // This node uses local logic -- shows that nodes can mix LLM and code
  Output :=
    StringOfChar('=', 50) + sLineBreak +
    '  EDITORIAL SUMMARY' + sLineBreak +
    StringOfChar('=', 50) + sLineBreak +
    Input + sLineBreak +
    StringOfChar('-', 50);
end;

function TDemoA.Run(const ATexto: String): String;
var
  Manager: TAIAgentManager;
begin
  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;   // Manager.Run() bloquea hasta completar
    Manager
      .AddNode('Analizar',  OnAnalizar)
      .AddNode('Resumir',   OnResumir)
      .AddNode('Formatear', OnFormatear)
      .AddEdge('Analizar',  'Resumir')
      .AddEdge('Resumir',   'Formatear')
      .SetEntryPoint('Analizar')
      .SetFinishPoint('Formatear')
      .Compile;
    Result := Manager.Run(ATexto);
  finally
    Manager.Free;
  end;
end;

// ===========================================================================
//  SCENARIO B -- IAiTool tools for TLLMNode
// ===========================================================================
//  Each tool implements IAiTool as TInterfacedObject.
//  Memory contract (defined in uMakerAi.Agents.IAiTool):
//    GetSchema --> DO NOT free; the TJSONObject is owned by the tool
//    Execute   --> the caller frees the returned TJSONObject
// ===========================================================================

type
  // Tool 1: System date and time (no parameters)
  TFechaHoraTool = class(TInterfacedObject, IAiTool)
  private
    FSchema: TJSONObject;
  public
    destructor Destroy; override;
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    function GetSchema: TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable: Boolean;
  end;

  // Tool 2: Arithmetic calculator (a, b, operation)
  TCalculadoraTool = class(TInterfacedObject, IAiTool)
  private
    FSchema: TJSONObject;
  public
    destructor Destroy; override;
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    function GetSchema: TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable: Boolean;
  end;

{ TFechaHoraTool }

destructor TFechaHoraTool.Destroy;
begin
  FSchema.Free;
  inherited;
end;

function TFechaHoraTool.GetName: String;
begin
  Result := 'FechaHoraActual';
end;

function TFechaHoraTool.GetDescription: String;
begin
  Result := 'Gets the current system date and time';
end;

function TFechaHoraTool.GetCategory: String;
begin
  Result := 'System';
end;

function TFechaHoraTool.GetSchema: TJSONObject;
begin
  if FSchema = nil then
  begin
    FSchema := TJSONObject.Create;
    FSchema.AddPair('type', 'object');
    FSchema.AddPair('properties', TJSONObject.Create); // sin parametros
  end;
  Result := FSchema;
end;

function TFechaHoraTool.Execute(const AArgs: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('fecha_hora', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
end;

function TFechaHoraTool.IsAvailable: Boolean;
begin
  Result := True;
end;

{ TCalculadoraTool }

destructor TCalculadoraTool.Destroy;
begin
  FSchema.Free;
  inherited;
end;

function TCalculadoraTool.GetName: String;
begin
  Result := 'Calculadora';
end;

function TCalculadoraTool.GetDescription: String;
begin
  Result := 'Performs basic arithmetic operations between two numbers';
end;

function TCalculadoraTool.GetCategory: String;
begin
  Result := 'Mathematics';
end;

function TCalculadoraTool.GetSchema: TJSONObject;
var
  Props, AProp, BProp, OpProp: TJSONObject;
  EnumArr, Required: TJSONArray;
begin
  if FSchema = nil then
  begin
    FSchema := TJSONObject.Create;
    FSchema.AddPair('type', 'object');

    Props := TJSONObject.Create;

    AProp := TJSONObject.Create;
    AProp.AddPair('type', 'number');
    AProp.AddPair('description', 'First operand');
    Props.AddPair('a', AProp);

    BProp := TJSONObject.Create;
    BProp.AddPair('type', 'number');
    BProp.AddPair('description', 'Second operand');
    Props.AddPair('b', BProp);

    EnumArr := TJSONArray.Create;
    EnumArr.Add('sumar');
    EnumArr.Add('restar');
    EnumArr.Add('multiplicar');
    EnumArr.Add('dividir');

    OpProp := TJSONObject.Create;
    OpProp.AddPair('type', 'string');
    OpProp.AddPair('description', 'Arithmetic operation to perform');
    OpProp.AddPair('enum', EnumArr);
    Props.AddPair('operacion', OpProp);

    FSchema.AddPair('properties', Props);

    Required := TJSONArray.Create;
    Required.Add('a');
    Required.Add('b');
    Required.Add('operacion');
    FSchema.AddPair('required', Required);
  end;
  Result := FSchema;
end;

function TCalculadoraTool.Execute(const AArgs: TJSONObject): TJSONObject;
var
  A, B, Res: Double;
  Op: String;
begin
  Result := TJSONObject.Create;
  if not Assigned(AArgs) then
  begin
    Result.AddPair('error', 'Required arguments');
    Exit;
  end;
  try
    A  := AArgs.GetValue<Double>('a');
    B  := AArgs.GetValue<Double>('b');
    Op := AArgs.GetValue<String>('operacion').ToLower.Trim;
  except
    Result.AddPair('error', 'Invalid parameters');
    Exit;
  end;

  if      Op = 'sumar'       then Res := A + B
  else if Op = 'restar'      then Res := A - B
  else if Op = 'multiplicar' then Res := A * B
  else if Op = 'dividir' then
  begin
    if B = 0 then
    begin
      Result.AddPair('error', 'Division by zero');
      Exit;
    end;
    Res := A / B;
  end
  else
  begin
    Result.AddPair('error', 'Unknown operation: ' + Op);
    Exit;
  end;

  Result.AddPair('resultado', TJSONNumber.Create(Res));
end;

function TCalculadoraTool.IsAvailable: Boolean;
begin
  Result := True;
end;

// ---------------------------------------------------------------------------
//  Demo A -- Pipeline editorial de 3 nodos
// ---------------------------------------------------------------------------

procedure DemoA;
var
  Demo: TDemoA;
  Resultado: String;
begin
  Separador('Demo A -- Editorial pipeline without TLLMNode (3 nodes in sequence)');
  WriteLn('  Text: "', Copy(TEXTO_PRUEBA, 1, 58), '..."');
  WriteLn('  Graph: Analyze --> Summarize --> Format');
  WriteLn;

  Demo := TDemoA.Create(DRV, MDL, APIKEY);
  try
    Resultado := Demo.Run(TEXTO_PRUEBA);
    WriteLn;
    WriteLn(Resultado);
  finally
    Demo.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo B -- TLLMNode con herramientas IAiTool
// ---------------------------------------------------------------------------

procedure DemoB;
var
  Manager : TAIAgentManager;
  Node    : TLLMNode;
  P, R    : String;
  Preguntas: array[0..1] of string;
begin
  Separador('Demo B -- TLLMNode with IAiTool tools (autonomous agent)');

  // 1. Register tools in the global singleton
  TAiToolRegistry.Instance.Register(TFechaHoraTool.Create,  'local');
  TAiToolRegistry.Instance.Register(TCalculadoraTool.Create, 'local');
  WriteLn(Format('  Tools in registry: %d', [TAiToolRegistry.Instance.Count]));
  WriteLn;

  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;

    // 2. Create TLLMNode as a component owned by the manager.
    //    When using Manager as owner, the node auto-registers in the list
    //    of components via TComponent's Notification mechanism.
    Node := TLLMNode.Create(Manager);
    Node.Name         := 'Agente';
    Node.Graph        := Manager;    // necesario para Blackboard y link traversal
    Node.DriverName   := DRV;
    Node.ApiKey       := APIKEY;
    Node.Model        := MDL;
    Node.SystemPrompt :=
      'You are an assistant with access to tools. ' +
      'For the current date/time use FechaHoraActual. ' +
      'For arithmetic calculations use Calculadora. ' +
      'Show the result clearly and concisely.';
    Node.UseAllTools  := True;   // inyecta todo el TAiToolRegistry.Instance

    Manager
      .SetEntryPoint('Agente')
      .SetFinishPoint('Agente')
      .Compile;

    // 3. Queries that require tool use
    Preguntas[0] := 'What is the current system date and time?';
    Preguntas[1] := 'What is 1247 multiplied by 38? And that result divided by 7?';

    for P in Preguntas do
    begin
      WriteLn('  Question: ', P);
      R := Manager.Run(P);
      WriteLn('  Answer: ', R);
      WriteLn;
    end;

  finally
    TAiToolRegistry.Instance.Clear;   // limpiar el registry al terminar el demo
    Manager.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Programa principal
// ---------------------------------------------------------------------------

begin
  WriteLn('=== MakerAI -- Chapter 26: Building Agents with TLLMNode ===');
  WriteLn;
  WriteLn('  Demo A: TAIAgentsNode + manual OnExecute (code-first, without TLLMNode)');
  WriteLn('  Demo B: TLLMNode + IAiTool (component-first, autonomous agent)');
  WriteLn;
  WriteLn('  Driver: ', DRV, '  Model: ', MDL);
  WriteLn('  API Key: ', APIKEY, '  (CLAUDE_API_KEY environment variable)');

  try
    DemoA;
    DemoB;

    WriteLn;
    WriteLn(StringOfChar('=', 64));
    WriteLn('  Demos completados.');
    WriteLn(StringOfChar('=', 64));
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('[ERROR] ', E.ClassName, ': ', E.Message);
    end;
  end;

  WriteLn;
  Write('Press Enter to exit...');
  ReadLn;
end.
