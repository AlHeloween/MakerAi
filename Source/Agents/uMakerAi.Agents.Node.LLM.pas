// MIT License
// MakerAI - Agent System v3.4
// TLLMNode: agent node with an integrated ReAct loop.
//
// TLLMNode extends TAIAgentsNode adding an LLM model with the ability to
// call TAiToolRegistry tools automatically. The LLM → Tool → Observation
// loop is handled internally by TAiChatConnection
// (native function calling of each provider).
//
// Basic usage:
//   Node := TLLMNode.Create(Manager);
//   Node.DriverName   := 'Claude';     // empty = the skill's, or 'Claude'
//   Node.Model        := 'claude-sonnet-4-5';
//   Node.ApiKey       := '@CLAUDE_API_KEY';
//   Node.SystemPrompt := 'You are an expert assistant on...';
//   Node.UseAllTools  := True;   // injects the whole TAiToolRegistry.Instance
//
// Author: Gustavo Enriquez
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
  uMakerAi.Agents.Attributes, // TSecretAttribute
  uMakerAi.Agents.IAiTool,
  uMakerAi.Agents.ToolRegistry,
  uMakerAi.Agents.Skill,     // TAiSkill
  uMakerAi.Chat.Messages,    // TAiToolsFunction
  uMakerAi.Chat.AiConnection, // TAiChatConnection
  uMakerAi.Tools.Functions;  // TAiFunctions, TFunctionActionItem, TFunctionEvent

const
  // Driver used when neither the node nor the skill sets one
  LLMNODE_DEFAULT_DRIVER = 'Claude';

type

  // Effective chat configuration of a TLLMNode (node + skill already combined)
  TLLMNodeConfig = record
    DriverName  : String;
    Model       : String;   // '' = driver default
    ApiKey      : String;
    SystemPrompt: String;
  end;

  { TLLMNode -------------------------------------------------------------------
  Agent node with an LLM and TAiToolRegistry tools integrated.

  The ReAct loop (Think → Call Tool → Observe → repeat) is transparent:
  TAiChatConnection handles it internally via function calling. TLLMNode
  only connects each tool call's result to the TAiToolRegistry.

  Registry property:
    - nil (default) → uses TAiToolRegistry.Instance (global singleton)
    - Assign your own to isolate this node's tools

  Lifecycle of the internal objects:
    TAiChatConnection and TAiFunctions are created and freed on every
    DoExecute call so no state persists between node executions.
}
  TLLMNode = class(TAIAgentsNode)
  private
    FDriverName    : String;
    FModel         : String;
    FApiKey        : String;
    FServiceURL    : String;
    FSystemPrompt  : String;
    FMaxTokens     : Integer;
    FUseAllTools   : Boolean;
    FRegistry      : TAiToolRegistry;
    FSkill         : TAiSkill;

    // Temporary state valid only during DoExecute (one thread at a time per node)
    FActiveRegistry: TAiToolRegistry;
    // Captures the LLM's last error to re-raise it as an exception
    FLastError     : String;

    procedure SetSkill(const Value: TAiSkill);
    procedure LoadRegistryTools(AFunctions: TAiFunctions);
    // Loads into AFunctions only the AToolNames tools present in the registry
    procedure LoadSkillTools(AFunctions: TAiFunctions; AToolNames: TStrings);
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
    destructor Destroy; override;

    // Combines the node's properties with the skill's (if any):
    //   - DriverName: the node's; if empty, the skill's; if neither,
    //     LLMNODE_DEFAULT_DRIVER ('Claude').
    //   - Model: the node's; if empty, the skill's ONLY if that model
    //     belongs to the effective driver (same DriverName, or neither set
    //     a driver). A node switching to 'OpenAI' does not inherit 'claude-...'.
    //   - ApiKey: the node's; if empty, the skill's.
    //   - SystemPrompt: the skill's followed by the node's.
    // Touches no network and creates no chat: it serves to inspect the config.
    function ResolveConfig: TLLMNodeConfig;

    // Applies ResolveConfig (and ServiceURL/MaxTokens) to a chat. It is what
    // DoExecute does before loading the tools; public so it can be verified.
    procedure ConfigureChat(AChat: TAiChatConnection);

    // Reference to the registry to use. nil = TAiToolRegistry.Instance.
    property Registry: TAiToolRegistry read FRegistry write FRegistry;

    // Reusable configuration skill.
    // The node takes ownership: it frees the previous skill when a new one is assigned,
    // and frees the active skill in the destructor.
    // How it combines with the node's props: see ResolveConfig.
    // ExtraTools is loaded if UseAllTools=False and the skill has tools.
    property Skill: TAiSkill read FSkill write SetSkill;
  published
    // LLM driver name: 'OpenAI', 'Claude', 'Gemini', 'Ollama', etc.
    // Empty (default) = the skill's; without a skill (or without a driver in the skill),
    // 'Claude'.
    property DriverName   : String  read FDriverName   write FDriverName;
    // Provider-specific model (empty = uses the skill's or the driver's default)
    property Model        : String  read FModel        write FModel;
    // API key. Supports @ENV_VAR_NAME syntax for runtime resolution.
    // Empty = uses the skill's ApiKey (if assigned).
    // [TSecret]: never serialized to disk nor accepted from files.
    [TSecret('apiKey')]
    property ApiKey       : String  read FApiKey       write FApiKey;
    // Service base URL (required for Azure OpenAI and custom endpoints).
    // Maps to Chat.Params.Values['URL']. Empty = uses the driver's default endpoint.
    property ServiceURL   : String  read FServiceURL   write FServiceURL;
    // System instruction for the LLM. With a skill, it is added AFTER the
    // skill's SystemPrompt (node adjustments over the base instructions).
    property SystemPrompt : String  read FSystemPrompt write FSystemPrompt;
    // Maximum tokens in the response (0 = uses the driver's default)
    property MaxTokens    : Integer read FMaxTokens    write FMaxTokens default 0;
    // If True, automatically injects all the registry's available tools.
    // If False and there is a skill with ExtraTools, loads only those tools.
    property UseAllTools  : Boolean read FUseAllTools  write FUseAllTools default True;
  end;


procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TLLMNode]);
end;



{ TLLMNode }

constructor TLLMNode.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  // Empty: so a skill's DriverName can apply. Without a skill,
  // ResolveConfig falls back to LLMNODE_DEFAULT_DRIVER, as before.
  FDriverName     := '';
  FModel          := '';
  FApiKey         := '';
  FServiceURL     := '';
  FSystemPrompt   := '';
  FMaxTokens      := 0;
  FUseAllTools    := True;
  FRegistry       := nil;
  FActiveRegistry := nil;
  FSkill          := nil;
end;

destructor TLLMNode.Destroy;
begin
  FSkill.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// Skill setter: the node takes ownership — frees the previous skill if it exists.
// ---------------------------------------------------------------------------
procedure TLLMNode.SetSkill(const Value: TAiSkill);
begin
  if FSkill = Value then Exit;
  FSkill.Free;
  FSkill := Value;
end;

// ---------------------------------------------------------------------------
// ResolveConfig: combines node + skill (see the declaration for the rules)
// ---------------------------------------------------------------------------
function TLLMNode.ResolveConfig: TLLMNodeConfig;
var
  SkillDriver, SkillModel, SkillPrompt: String;
begin
  SkillDriver := '';
  SkillModel  := '';
  SkillPrompt := '';
  Result.ApiKey := FApiKey;
  if Assigned(FSkill) then
  begin
    SkillDriver := Trim(FSkill.DriverName);
    SkillModel  := Trim(FSkill.Model);
    SkillPrompt := Trim(FSkill.SystemPrompt);
    if Result.ApiKey = '' then
      Result.ApiKey := FSkill.ApiKey;
  end;

  // Driver
  if Trim(FDriverName) <> '' then
    Result.DriverName := Trim(FDriverName)
  else if SkillDriver <> '' then
    Result.DriverName := SkillDriver
  else
    Result.DriverName := LLMNODE_DEFAULT_DRIVER;

  // Model: the skill's only if it belongs to the effective driver. A skill without a driver
  // (typical of a SKILL.md) contributes its model only if the node did not set a
  // driver either: both stay on the default, which is what it was written for.
  if Trim(FModel) <> '' then
    Result.Model := Trim(FModel)
  else if (SkillModel <> '') and
          (SameText(SkillDriver, Result.DriverName) or
           ((SkillDriver = '') and (Trim(FDriverName) = ''))) then
    Result.Model := SkillModel
  else
    Result.Model := '';

  // System prompt: the skill's instructions + the node's adjustments
  if (SkillPrompt <> '') and (Trim(FSystemPrompt) <> '') then
    Result.SystemPrompt := SkillPrompt + sLineBreak + sLineBreak + FSystemPrompt
  else if SkillPrompt <> '' then
    Result.SystemPrompt := SkillPrompt
  else
    Result.SystemPrompt := FSystemPrompt;
end;

// ---------------------------------------------------------------------------
// ConfigureChat: applies the effective config to a freshly created chat.
// It is computed entirely BEFORE touching the chat and applied in order
// Driver -> Model -> Params: SetDriverName resets the Model and reloads the
// driver's Params, so applying the skill and then the node (as before)
// lost the skill's model and ApiKey as soon as the node had another driver.
// ---------------------------------------------------------------------------
procedure TLLMNode.ConfigureChat(AChat: TAiChatConnection);
var
  Cfg: TLLMNodeConfig;
begin
  Cfg := ResolveConfig;
  AChat.DriverName := Cfg.DriverName;
  if Cfg.Model <> '' then
    AChat.Model := Cfg.Model;

  // Parameters via TStrings (Asynchronous MUST be False in agent nodes)
  AChat.Params.Values['Asynchronous'] := 'False';
  if Cfg.ApiKey <> '' then
    AChat.Params.Values['ApiKey'] := Cfg.ApiKey;
  if FServiceURL <> '' then
    AChat.Params.Values['URL'] := FServiceURL;
  if FMaxTokens > 0 then
    AChat.Params.Values['Max_tokens'] := IntToStr(FMaxTokens);
  if Cfg.SystemPrompt <> '' then
    AChat.SystemPrompt.Text := Cfg.SystemPrompt;
end;

// ---------------------------------------------------------------------------
// Loads all the registry's tools into the TAiFunctions component.
// Each IAiTool becomes a TFunctionActionItem using SetJSon to
// transfer the name, description and full inputSchema.
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

    // Preserve the full schema without decomposing it into TFunctionParamsItems.
    // This guarantees that complex schemas (anyOf, nested objects, arrays, etc.)
    // reach GetTools() → NormalizeToolsFromSource → FormatToolList intact.
    Schema := T.GetSchema;  // Do NOT free — owned by the tool
    if Assigned(Schema) then
      Item.RawSchemaJson := Schema.ToJSON
    else
      Item.RawSchemaJson := '{"type":"object","properties":{}}';
  end;
end;

// ---------------------------------------------------------------------------
// Loads into AFunctions only the AToolNames tools present in the
// active registry. Used when UseAllTools=False and the skill defines ExtraTools.
// ---------------------------------------------------------------------------
procedure TLLMNode.LoadSkillTools(AFunctions: TAiFunctions; AToolNames: TStrings);
var
  ToolName: String;
  Tool    : IAiTool;
  Item    : TFunctionActionItem;
  Schema  : TJSONObject;
begin
  if not Assigned(AFunctions) then Exit;
  if not Assigned(FActiveRegistry) then Exit;

  for ToolName in AToolNames do
  begin
    if not FActiveRegistry.TryFind(ToolName, Tool) then
      Continue;

    Item := AFunctions.Functions.AddFunction(Tool.Name, True, HandleToolCall);
    Item.Description.Text := Tool.Description;
    Schema := Tool.GetSchema;  // Do NOT free — owned by the tool
    if Assigned(Schema) then
      Item.RawSchemaJson := Schema.ToJSON
    else
      Item.RawSchemaJson := '{"type":"object","properties":{}}';
  end;
end;

// ---------------------------------------------------------------------------
// Captures LLM errors to re-raise them as an exception in DoExecute.
// ---------------------------------------------------------------------------
procedure TLLMNode.InternalOnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FLastError := ErrorMsg;
end;

// ---------------------------------------------------------------------------
// Unified handler for all the LLM's tool calls.
// TAiChatConnection invokes this method when the model asks to execute
// a function. We look the tool up in the registry and execute it.
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

  // Parse the arguments
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
      ResultJSON := Tool.Execute(ArgsJSON);   // caller frees the result
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
// The node's main entry point. Replaces the generic DoExecute.
// Creates the chat, loads the tools and executes the node's input.
// The ReAct loop is managed internally by TAiChatConnection.
// ---------------------------------------------------------------------------
procedure TLLMNode.DoExecute(aBeforeNode: TAIAgentsNode;
  aLink: TAIAgentsLink);
var
  Chat      : TAiChatConnection;
  Functions : TAiFunctions;
  Response  : String;
begin
  // Evaluate the join logic (jmAny / jmAll) and update Self.Input.
  // If the node is not ready yet (jmAll waiting for more inputs), exit without executing.
  if not CheckJoinAndPrepareInput(aBeforeNode, aLink) then Exit;

  // Fire OnEnterNode BEFORE the LLM call so the handler can
  // modify Self.Input (e.g. inject the debate history).
  // It is called directly (no Synchronize) because only this
  // worker thread touches Self.Input at this moment, and the Blackboard is already thread-safe.
  // Note: in UI apps, the handler must be thread-safe (do not touch controls).
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
    // 1. Driver, model, credentials and prompt (node + skill)
    ConfigureChat(Chat);

    // Connect the error handler to capture LLM failures
    Chat.OnError := InternalOnError;

    // 3. Load the tools.
    //    - UseAllTools=True  → loads the whole registry (original behavior).
    //    - UseAllTools=False + Skill.ExtraTools → loads only the skill's tools.
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
    end
    else if Assigned(FSkill) and (FSkill.ExtraTools.Count > 0) then
    begin
      // UseAllTools=False but the skill declares specific tools
      LoadSkillTools(Functions, FSkill.ExtraTools);
      if Functions.Functions.Count > 0 then
      begin
        Chat.AiFunctions := Functions;
        Chat.Params.Values['ModelCaps']   := '[]';
        Chat.Params.Values['SessionCaps'] := '[]';
        Chat.Params.Values['Tool_Active'] := 'True';
      end;
    end;

    // Execute the node's input (the tools loop is automatic)
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

  // Route to the next link (equivalent to the base class's DoExecute block
  // which does not run because TLLMNode overrides DoExecute without calling inherited).
  DoTraverseLinks(aBeforeNode, aLink);
end;

initialization
  // Needed so the DFM streaming finds TLLMNode at runtime
  // (RegisterComponents only applies in the IDE; RegisterClass always applies)
  RegisterClass(TLLMNode);

end.
