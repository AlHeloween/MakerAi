// MIT License
// MakerAI - Sistema de Agentes v3.4
// TLLMNode: nodo de agente con loop ReAct integrado.
//
// TLLMNode extends TAIAgentsNode by adding an LLM model with capacity to
// call tools from TAiToolRegistry automatically. The LLM →
// Tool → Observation is handled internally by TAiChatConnection
// (function calling nativo de cada proveedor).
//
// Basic usage:
//   Node := TLLMNode.Create(Manager);
//   Node.DriverName   := 'Claude';
//   Node.Model        := 'claude-sonnet-4-5';
//   Node.ApiKey       := '@CLAUDE_API_KEY';
//   Node.SystemPrompt := 'Eres un asistente experto en...';
//   Node.UseAllTools  := True;   // inyecta todo el TAiToolRegistry.Instance
//
// Author: Gustavo Enríquez
// GitHub: https://github.com/gustavoeenriquez/MakerAi

unit uMakerAi.Agents.Node.LLM;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,     // IHTTPResponse (para TAiErrorEvent)
  uMakerAi.Agents,
  uMakerAi.Agents.IAiTool,
  uMakerAi.Agents.ToolRegistry,
  uMakerAi.Chat.Messages,    // TAiToolsFunction
  uMakerAi.Tools.Functions;  // TAiFunctions, TFunctionActionItem, TFunctionEvent

type

  { TLLMNode -------------------------------------------------------------------
    Nodo de agente con LLM y herramientas del TAiToolRegistry integradas.

    El loop ReAct (Think → Call Tool → Observe → repeat) es transparente:
    TAiChatConnection lo maneja internamente vía function calling. TLLMNode
    sólo conecta el resultado de cada tool call al TAiToolRegistry.

    Propiedad Registry:
      - nil (default) → usa TAiToolRegistry.Instance (singleton global)
      - Asignar uno propio para aislar las herramientas de este nodo

    Ciclo de vida de los objetos internos:
      TAiChatConnection y TAiFunctions se crean y liberan en cada llamada a
      DoExecute para que no persista estado entre ejecuciones del nodo.
  }
  TLLMNode = class(TAIAgentsNode)
  private
    FDriverName    : String;
    FModel         : String;
    FApiKey        : String;
    FSystemPrompt  : String;
    FMaxTokens     : Integer;
    FUseAllTools   : Boolean;
    FRegistry      : TAiToolRegistry;

    // Temporary state valid only during DoExecute (one thread at a time per node)
    FActiveRegistry: TAiToolRegistry;
    // Captures the last LLM error to re-throw it as exception
    FLastError     : String;

    procedure LoadRegistryTools(AFunctions: TAiFunctions);
    procedure HandleToolCall(Sender: TObject;
                             FunctionAction: TFunctionActionItem;
                             FunctionName: String;
                             ToolCall: TAiToolsFunction;
                             var Handled: Boolean);
    procedure InternalOnError(Sender: TObject; const ErrorMsg: string;
                              AException: Exception; const AResponse: IHTTPResponse);
  protected
    procedure DoExecute(aBeforeNode: TAIAgentsNode;
                        aLink: TAIAgentsLink); override;
  public
    constructor Create(aOwner: TComponent); override;

    // Referencia al registry a usar. nil = TAiToolRegistry.Instance.
    property Registry: TAiToolRegistry read FRegistry write FRegistry;
  published
    // Nombre del driver LLM: 'OpenAI', 'Claude', 'Gemini', 'Ollama', etc.
    property DriverName   : String  read FDriverName   write FDriverName;
    // Provider-specific model (empty = uses driver default)
    property Model        : String  read FModel        write FModel;
    // API key. Supports @ENV_VAR_NAME syntax for runtime resolution.
    property ApiKey       : String  read FApiKey       write FApiKey;
    // System instruction for the LLM
    property SystemPrompt : String  read FSystemPrompt write FSystemPrompt;
    // Maximum tokens in response (0 = uses driver default)
    property MaxTokens    : Integer read FMaxTokens    write FMaxTokens default 0;
    // If True, automatically injects all available tools from the registry
    property UseAllTools  : Boolean read FUseAllTools  write FUseAllTools default True;
  end;


procedure Register;

implementation

uses
  uMakerAi.Chat.AiConnection;   // TAiChatConnection

procedure Register;
begin
  RegisterComponents('MakerAI', [TLLMNode]);
end;



{ TLLMNode }

constructor TLLMNode.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  FDriverName    := 'Claude';
  FModel         := '';
  FApiKey        := '';
  FSystemPrompt  := '';
  FMaxTokens     := 0;
  FUseAllTools   := True;
  FRegistry      := nil;
  FActiveRegistry := nil;
end;

// ---------------------------------------------------------------------------
// Carga todas las herramientas del registry en el componente TAiFunctions.
// Cada IAiTool se convierte en un TFunctionActionItem usando SetJSon para
// transfer the name, description and complete inputSchema.
// ---------------------------------------------------------------------------
procedure TLLMNode.LoadRegistryTools(AFunctions: TAiFunctions);
var
  Tools  : TArray<IAiTool>;
  T      : IAiTool;
  Item   : TFunctionActionItem;
  Schema : TJSONObject;
begin
  if not Assigned(AFunctions) then Exit;
  if not Assigned(FActiveRegistry) then Exit;

  Tools := FActiveRegistry.GetAll;
  for T in Tools do
  begin
    // Registrar en TAiFunctions con el handler unificado
    Item := AFunctions.Functions.AddFunction(T.Name, True, HandleToolCall);
    Item.Description.Text := T.Description;

    // Preservar el schema completo sin descomponerlo en TFunctionParamsItems.
    // Esto garantiza que schemas complejos (anyOf, nested objects, arrays, etc.)
    // lleguen intactos a GetTools() → NormalizeToolsFromSource → FormatToolList.
    Schema := T.GetSchema;  // NO liberar — propiedad de la herramienta
    if Assigned(Schema) then
      Item.RawSchemaJson := Schema.ToJSON
    else
      Item.RawSchemaJson := '{"type":"object","properties":{}}';
  end;
end;

// ---------------------------------------------------------------------------
// Captures LLM errors to re-throw them as exception in DoExecute.
// ---------------------------------------------------------------------------
procedure TLLMNode.InternalOnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FLastError := ErrorMsg;
end;

// ---------------------------------------------------------------------------
// Handler unificado para todas las tool calls del LLM.
// TAiChatConnection invokes this method when the model requests to execute
// a function. We look for the tool in the registry and execute.
// ---------------------------------------------------------------------------
procedure TLLMNode.HandleToolCall(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: String;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Tool      : IAiTool;
  ArgsJSON  : TJSONObject;
  ResultJSON: TJSONObject;
begin
  Handled := False;
  if not Assigned(FActiveRegistry) then Exit;

  if not FActiveRegistry.TryFind(FunctionName, Tool) then
  begin
    ToolCall.Response := Format('{"error":"Tool ''%s'' not found in registry"}', [FunctionName]);
    Handled := True;
    Exit;
  end;

  // Parsear argumentos
  ArgsJSON := nil;
  if ToolCall.Arguments <> '' then
  begin
    try
      ArgsJSON := TJSONObject(TJSONObject.ParseJSONValue(ToolCall.Arguments));
    except
      ArgsJSON := nil;
    end;
  end;

  ResultJSON := nil;
  try
    try
      ResultJSON := Tool.Execute(ArgsJSON);   // caller libera el resultado
      if Assigned(ResultJSON) then
        ToolCall.Response := ResultJSON.ToJSON
      else
        ToolCall.Response := '{"result":"ok"}';
    except
      on E: Exception do
        ToolCall.Response := Format('{"error":"%s"}', [E.Message]);
    end;
  finally
    ArgsJSON.Free;
    ResultJSON.Free;
  end;

  Handled := True;
end;

// ---------------------------------------------------------------------------
// Main entry point of the node. Replaces the generic DoExecute.
// Crea el chat, carga las herramientas y ejecuta el input del nodo.
// El loop ReAct es gestionado internamente por TAiChatConnection.
// ---------------------------------------------------------------------------
procedure TLLMNode.DoExecute(aBeforeNode: TAIAgentsNode;
  aLink: TAIAgentsLink);
var
  Chat      : TAiChatConnection;
  Functions : TAiFunctions;
  Response  : String;
begin
  // Evaluar logica de join (jmAny / jmAll) y actualizar Self.Input.
  // Si el nodo no esta listo aun (jmAll esperando mas inputs), salir sin ejecutar.
  if not CheckJoinAndPrepareInput(aBeforeNode, aLink) then Exit;

  // Disparar OnEnterNode ANTES de la llamada al LLM para que el handler pueda
  // modificar Self.Input (p.ej. inyectar historial del debate).
  // Se llama directo (sin Synchronize) porque Self.Input solo lo toca este
  // worker thread en este momento, y Blackboard ya es thread-safe.
  // Nota: en apps con UI, el handler debe ser thread-safe (no tocar controles).
  if Assigned(Self.Graph) and Assigned(Self.Graph.OnEnterNode) then
    Self.Graph.OnEnterNode(Self.Graph, Self);

  // Determine the active registry for this execution
  if Assigned(FRegistry) then
    FActiveRegistry := FRegistry
  else
    FActiveRegistry := TAiToolRegistry.Instance;

  FLastError := '';
  Chat      := TAiChatConnection.Create(nil);
  Functions := TAiFunctions.Create(nil);
  try
    // Configurar el chat
    Chat.DriverName := FDriverName;
    if FModel <> '' then
      Chat.Model := FModel;

    // Conectar handler de errores para capturar fallos del LLM
    Chat.OnError := InternalOnError;

    // Parameters via TStrings (Asynchronous MUST be False in agent nodes)
    Chat.Params.Values['Asynchronous'] := 'False';
    if FApiKey <> '' then
      Chat.Params.Values['ApiKey'] := FApiKey;
    if FMaxTokens > 0 then
      Chat.Params.Values['Max_tokens'] := IntToStr(FMaxTokens);
    if FSystemPrompt <> '' then
      Chat.SystemPrompt.Text := FSystemPrompt;

    // Cargar herramientas del registry en TAiFunctions
    if FUseAllTools and (FActiveRegistry.Count > 0) then
    begin
      LoadRegistryTools(Functions);
      Chat.AiFunctions := Functions;

      // Clear ModelCaps/SessionCaps: LLMNode uses only TAiFunctions.
      // Without this, the driver may add built-in tools (web_search,
      // code_execution, etc.) that our code does not know how to handle.
      Chat.Params.Values['ModelCaps']   := '[]';
      Chat.Params.Values['SessionCaps'] := '[]';

      // Tool_Active must be True for the driver to send the tools to the LLM.
      // Algunos drivers (Claude, Gemini) lo tienen en False por defecto.
      Chat.Params.Values['Tool_Active'] := 'True';
    end;

    // Execute the node input (the tools loop is automatic)
    Response := Chat.AddMessageAndRun(Self.Input, 'user', []);

    // If the LLM reported an error and the response is empty, propagate it
    if (Response = '') and (FLastError <> '') then
      raise Exception.Create('[TLLMNode] LLM error: ' + FLastError);

    Self.Output := Response;

    // Publicar en el Blackboard para que otros nodos puedan leerlo
    if Assigned(Self.Graph) and Assigned(Self.Graph.Blackboard) then
      Self.Graph.Blackboard.SetString(Self.Name + '.output', Response);

  finally
    // Desconectar el functions ANTES de liberar para evitar referencias colgantes
    Chat.AiFunctions := nil;
    Functions.Free;
    Chat.Free;
    FActiveRegistry := nil;
  end;

  // Enrutar al siguiente link (equivalente al bloque de DoExecute del base class
  // que no se ejecuta porque TLLMNode sobreescribe DoExecute sin llamar inherited).
  DoTraverseLinks(aBeforeNode, aLink);
end;

initialization
  // Necesario para que el DFM streaming encuentre TLLMNode en runtime
  // (RegisterComponents solo aplica en el IDE; RegisterClass aplica siempre)
  RegisterClass(TLLMNode);

end.
