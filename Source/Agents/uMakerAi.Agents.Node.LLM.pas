// MIT License
// MakerAI - Agent System v3.4
// TLLMNode: agent node with integrated ReAct loop.
//
// TLLMNode extends TAIAgentsNode by adding an LLM model with capacity to
// call tools from TAiToolRegistry automatically. The LLM →
// Tool → Observation is handled internally by TAiChatConnection
// (native function calling of each provider).
//
// Basic usage:
//   Node := TLLMNode.Create(Manager);
//   Node.DriverName   := 'Claude';
//   Node.Model        := 'claude-sonnet-4-5';
//   Node.ApiKey       := '@CLAUDE_API_KEY';
//   Node.SystemPrompt := 'You are an expert assistant in...';
//   Node.UseAllTools  := True;   // injects all of TAiToolRegistry.Instance
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
    System.Net.HttpClient,     // IHTTPResponse (for TAiErrorEvent)
  uMakerAi.Agents,
  uMakerAi.Agents.IAiTool,
  uMakerAi.Agents.ToolRegistry,
  uMakerAi.Chat.Messages,    // TAiToolsFunction
  uMakerAi.Tools.Functions;  // TAiFunctions, TFunctionActionItem, TFunctionEvent

type

  { TLLMNode -------------------------------------------------------------------
    Agent node with LLM and integrated TAiToolRegistry tools.

    The ReAct loop (Think -> Call Tool -> Observe -> repeat) is transparent:
    TAiChatConnection handles it internally via function calling. TLLMNode
    only connects the result of each tool call to TAiToolRegistry.

    Registry property:
      - nil (default) -> uses TAiToolRegistry.Instance (global singleton)
      - Assign your own to isolate this node's tools

    Lifecycle of internal objects:
      TAiChatConnection and TAiFunctions are created and freed on each DoExecute
      call so no state persists between node executions.
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

    // Reference to the registry to use. nil = TAiToolRegistry.Instance.
    property Registry: TAiToolRegistry read FRegistry write FRegistry;
  published
    // LLM driver name: 'OpenAI', 'Claude', 'Gemini', 'Ollama', etc.
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
// Loads all registry tools into the TAiFunctions component.
// Each IAiTool becomes a TFunctionActionItem using SetJSon to
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
    // Register in TAiFunctions with the unified handler
    Item := AFunctions.Functions.AddFunction(T.Name, True, HandleToolCall);
    Item.Description.Text := T.Description;

    // Preserve the complete schema without decomposing it into TFunctionParamsItems.
    // This ensures complex schemas (anyOf, nested objects, arrays, etc.)
    // arrive intact to GetTools() -> NormalizeToolsFromSource -> FormatToolList.
    Schema := T.GetSchema;  // Do NOT free - owned by the tool
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
// Unified handler for all LLM tool calls.
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

  // Parse arguments
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
      ResultJSON := Tool.Execute(ArgsJSON);       // caller frees the result
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
// Creates the chat, loads tools and executes the node input.
// The ReAct loop is managed internally by TAiChatConnection.
// ---------------------------------------------------------------------------
procedure TLLMNode.DoExecute(aBeforeNode: TAIAgentsNode;
  aLink: TAIAgentsLink);
var
  Chat      : TAiChatConnection;
  Functions : TAiFunctions;
  Response  : String;
begin
  // Evaluate join logic (jmAny / jmAll) and update Self.Input.
  // If the node is not ready yet (jmAll waiting for more inputs), exit without executing.
  if not CheckJoinAndPrepareInput(aBeforeNode, aLink) then Exit;

  // Fire OnEnterNode BEFORE the LLM call so the handler can
  // modify Self.Input (e.g. inject debate history).
  // Called directly (without Synchronize) because Self.Input is only touched by this
  // worker thread at this time, and Blackboard is already thread-safe.
  // Note: in UI apps, the handler must be thread-safe (no UI controls).
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
    // Configure the chat
    Chat.DriverName := FDriverName;
    if FModel <> '' then
      Chat.Model := FModel;

    // Connect error handler to capture LLM failures
    Chat.OnError := InternalOnError;

    // Parameters via TStrings (Asynchronous MUST be False in agent nodes)
    Chat.Params.Values['Asynchronous'] := 'False';
    if FApiKey <> '' then
      Chat.Params.Values['ApiKey'] := FApiKey;
    if FMaxTokens > 0 then
      Chat.Params.Values['Max_tokens'] := IntToStr(FMaxTokens);
    if FSystemPrompt <> '' then
      Chat.SystemPrompt.Text := FSystemPrompt;

    // Load registry tools into TAiFunctions
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
      // Some drivers (Claude, Gemini) have it False by default.
      Chat.Params.Values['Tool_Active'] := 'True';
    end;

    // Execute the node input (the tools loop is automatic)
    Response := Chat.AddMessageAndRun(Self.Input, 'user', []);

    // If the LLM reported an error and the response is empty, propagate it
    if (Response = '') and (FLastError <> '') then
      raise Exception.Create('[TLLMNode] LLM error: ' + FLastError);

    Self.Output := Response;

    // Publish to the Blackboard so other nodes can read it
    if Assigned(Self.Graph) and Assigned(Self.Graph.Blackboard) then
      Self.Graph.Blackboard.SetString(Self.Name + '.output', Response);

  finally
    // Disconnect the functions BEFORE freeing to avoid dangling references
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
