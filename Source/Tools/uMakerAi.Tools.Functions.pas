// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enríquez
// Social media:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Tools.Functions;

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Generics.Collections,
  System.JSON, Rest.JSON, System.IOUtils, uMakerAi.Guardrails,
  System.Net.HttpClient, System.NetEncoding,
  System.SyncObjs,
  Data.Db,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Core, uMakerAi.MCPClient.Core, uMakerAi.Chat.Messages;

const
  // Internal separator between the MCP server name and the tool name.
  // It MUST NOT appear in the name of a TMCPClientItem (validated in SetName).
  MCP_TOOL_SEP = '_99_';

type

  TFunctionActionItem = class;

  TFunctionEvent = Procedure(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: String; ToolCall: TAiToolsFunction; Var Handled: Boolean) Of Object;

  TToolstype = (tt_function, ttNone);

  TToolsParamType = (ptString, ptInteger, ptBoolean, ptFloat, ptDate, ptTime, ptDateTime, ptBase64);

  TFunctionParamsItem = Class(TCollectionItem)
  Private
    FName: String;
    FCollection: TCollection;
    FParamType: TToolsParamType;
    FRequired: Boolean;
    FDescription: TStrings;
    FEnum: String;
    procedure SetName(const Value: String);
    procedure SetDescription(const Value: TStrings);
    procedure SetEnum(const Value: String);
    procedure SetParamType(const Value: TToolsParamType);
    procedure SetRequired(const Value: Boolean);
  protected
    function GetDisplayName: string; Override;
    procedure SetDisplayName(const Value: string); Override;
  public
    constructor Create(Collection: TCollection); Override;
    Destructor Destroy; Override;
    function GetNamePath: string; override;
    procedure Assign(Source: TPersistent); override;
    Function ToJSon(Detail: Boolean = False): TJSonObject;
    procedure SetJSon(Value: TJSonObject);

  Published
    Property Name: String read FName write SetName;
    Property ParamType: TToolsParamType read FParamType write SetParamType;
    Property Description: TStrings read FDescription write SetDescription;
    Property Enum: String read FEnum write SetEnum;
    Property Required: Boolean read FRequired write SetRequired;
  End;

  TFunctionParamsItems = class(TOwnedCollection)
  Private
    [weak]
    FOwner: TPersistent;
    function GetParams(Index: Integer): TFunctionParamsItem;
    procedure SetParams(Index: Integer; const Value: TFunctionParamsItem);
  Protected
    function GetOwner: TPersistent; override;
    procedure SetItemName(Item: TCollectionItem); override;
    procedure Update(Item: TCollectionItem); override;
    Function GetParamByName(aParamName: String): TFunctionParamsItem;
  Public
    constructor Create(AOwner: TPersistent; ItemClass: TCollectionItemClass);
    Destructor Destroy; Override;
    function Add: TFunctionParamsItem;
    Function ToJSon(Detail: Boolean = False): TJSonObject;
    property Params[Index: Integer]: TFunctionParamsItem read GetParams write SetParams; default;
  Published
  end;

  TFunctionActionItem = class(TCollectionItem)
  private
    FEnabled: Boolean;
    FName: String;
    FOnAction: TFunctionEvent;
    FCollection: TCollection;
    FDefault: Boolean;
    FDescription: TStrings;
    FTagObject: TObject;
    FTag: Integer;
    FParams: TFunctionParamsItems;
    FToolType: TToolstype;
    FScript: TStrings;
    // Full JSON schema (not decomposed). When assigned,
    // ToJSon uses it directly instead of rebuilding from TFunctionParamsItems.
    // Useful for tools with complex schemas (anyOf, nested objects, etc.)
    FRawSchemaJson: String;
    // Async tool calling (Responses API, gpt-6-astra and later): the model
    // keeps reasoning, calling other tools, or answering independent
    // parts while the application executes THIS one. The result is
    // returned later with its original call_id. Providers that do not
    // support it simply do not see the field.
    FIsAsync: Boolean;
    procedure SetEnabled(const Value: Boolean);
    procedure SetOnAction(const Value: TFunctionEvent);
    procedure SetDefault(const Value: Boolean);
    procedure SetFunctionDoc(const Value: TStrings);
    procedure SetTag(const Value: Integer);
    procedure SetTagObject(const Value: TObject);
    procedure SetToolType(const Value: TToolstype);
    procedure SetScript(const Value: TStrings);
    { Private declarations }
  protected
    function GetDisplayName: string; Override;
    procedure SetDisplayName(const Value: string); Override;
  public
    constructor Create(Collection: TCollection); Override;
    Destructor Destroy; Override;
    function GetNamePath: string; override;
    procedure Assign(Source: TPersistent); override;

    Function ToJSon(Detail: Boolean = False): TJSonObject;
    Procedure SetJSon(Value: TJSonObject);

    Property TagObject: TObject read FTagObject write SetTagObject;
    // Full JSON schema (alternative to TFunctionParamsItems for complex schemas)
    property RawSchemaJson: String read FRawSchemaJson write FRawSchemaJson;
    // Declares the tool as asynchronous to providers that support it.
    property IsAsync: Boolean read FIsAsync write FIsAsync;
  published
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    property FunctionName: string read GetDisplayName write SetDisplayName;
    property OnAction: TFunctionEvent read FOnAction write SetOnAction;
    Property Description: TStrings read FDescription write SetFunctionDoc;
    Property Script: TStrings read FScript write SetScript;
    Property Parameters: TFunctionParamsItems Read FParams Write FParams;
    Property Default: Boolean read FDefault write SetDefault;
    Property Tag: Integer read FTag write SetTag;
    Property ToolType: TToolstype read FToolType write SetToolType;
  end;

  TFunctionActionItems = class(TOwnedCollection)
  Private
    [weak]
    FOwner: TPersistent;
    function GetActionItem(Index: Integer): TFunctionActionItem;
    procedure SetActionItem(Index: Integer; Value: TFunctionActionItem);
  Protected
    function GetOwner: TPersistent; override;
    procedure SetItemName(Item: TCollectionItem); override;
    procedure Update(Item: TCollectionItem); override;
    Function GetItemByName(aTagName: String): TFunctionActionItem;
  Public
    constructor Create(AOwner: TPersistent; ItemClass: TCollectionItemClass);
    Destructor Destroy; Override;
    function Add: TFunctionActionItem;
    Function IndexOf(Nombre: String): Integer;
    Function GetFunction(Nombre: String): TFunctionActionItem;
    Function AddFunction(Nombre: String; Enabled: Boolean; Action: TFunctionEvent): TFunctionActionItem;
    Function ToJSon(aDetail: Boolean = False): TJSonArray;
    Procedure SaveToFile(FileName: String);
    Procedure LoadFromFile(FileName: String);

    property Items[Index: Integer]: TFunctionActionItem read GetActionItem write SetActionItem; default;
  Published
  end;

  TMCPClientItem = class(TCollectionItem)
  private
    FEnabled: Boolean;
    FMCPClient: TMCPClientCustom;
    FOwned: Boolean;   // False = client is externally managed; destructor will not free it
    FConnected: Boolean;
    FParams: TStrings;
    FEnvVars: TStrings;
    FName: string;
    // "Proxy" properties to make configuration easier in the Object Inspector
    function GetName: string;
    function GetTransportType: TToolTransportType;
    procedure SetName(const Value: string);
    procedure SetTransportType(const Value: TToolTransportType);
    procedure SetEnabled(const Value: Boolean);
    procedure SetConnected(const Value: Boolean);
    // function GetDisabledFunctions: TStrings;
    function GetParams: TStrings;
    // procedure SetDisabledFunctions(const Value: TStrings);
    procedure SetParams(const Value: TStrings);
    function GetConfiguration: string;
    procedure SetConfiguration(const Value: string);
    function GetEnvVars: TStrings;
    procedure SetEnvVars(const Value: TStrings);
    // Automatic propagation to the real client when edited in-place
    procedure OnFParamsChanged(Sender: TObject);
    procedure OnFEnvVarsChanged(Sender: TObject);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure UpdateClientProperties;
    // Property to access the real client object
    property MCPClient: TMCPClientCustom read FMCPClient;
  published
    Property Connected: Boolean read FConnected write SetConnected;
    property Enabled: Boolean read FEnabled write SetEnabled;
    property Name: string read GetName write SetName;
    property TransportType: TToolTransportType read GetTransportType write SetTransportType;
    property Params: TStrings read GetParams write SetParams;
    Property EnvVars: TStrings read GetEnvVars write SetEnvVars;
    // property DisabledFunctions: TStrings read GetDisabledFunctions write SetDisabledFunctions;
    property Configuration: string read GetConfiguration write SetConfiguration;

  end;

  TMCPClientItems = class(TOwnedCollection)
  private
    [weak]
    FOwner: TPersistent;

    function GetClient(Index: Integer): TMCPClientItem;
    procedure SetClient(Index: Integer; const Value: TMCPClientItem);

  protected
    function GetOwner: TPersistent; override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    Destructor Destroy; Override;
    function Add: TMCPClientItem;
    function GetClientByName(const AName: string): TMCPClientItem;
    Function GetClientsList: TStringList;
    Function GetFunctionList(Name: String): TStringList;
    property Items[Index: Integer]: TMCPClientItem read GetClient write SetClient; default;
  end;

  // TAutoMCPConfig: grouped configuration for the AutoMCP / PPM subsystem.
  // Appears in the Object Inspector as an expandable property (+).
  // Note: OnAutoMCPRequest remains in TAiFunctions (OI Events tab).
  TAutoMCPConfig = class(TPersistent)
  private
    FActive: Boolean;
    FRegistryUrl: String;
    FWorkingDir: String;
    FAllowed: TStringList;
    FBlocked: TStringList;
    FConfigFile: String;
    FAutoLoad: Boolean;
    FOnActiveChanged: TNotifyEvent; // notifies TAiFunctions when Active changes
    function GetAllowed: TStrings;
    function GetBlocked: TStrings;
    procedure SetAllowed(const Value: TStrings);
    procedure SetBlocked(const Value: TStrings);
    procedure SetActive(const Value: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    // Active: when True, creates the 3 internal PPM functions and exposes them to the LLM.
    // When False, hides them (without destroying them). Re-enable = available again.
    property Active: Boolean read FActive write SetActive default False;
    // RegistryUrl: base URL of the PPM registry.
    property RegistryUrl: String read FRegistryUrl write FRegistryUrl;
    // Allowed: whitelist of permitted packages. If it has entries, only those can be installed.
    property Allowed: TStrings read GetAllowed write SetAllowed;
    // Blocked: blacklist of blocked packages. If Allowed is empty, everything except these is allowed.
    property Blocked: TStrings read GetBlocked write SetBlocked;
    // WorkingDir: base directory where PPM packages are installed.
    // Empty = ~/.ppm/mcp/<package_name>/ (system default).
    property WorkingDir: String read FWorkingDir write FWorkingDir;
    // ConfigFile: path to the JSON file with MCP servers (Claude Desktop format).
    // Empty = automatically detects the default Claude Desktop path depending on the OS.
    property ConfigFile: String read FConfigFile write FConfigFile;
    // AutoLoad: if True, imports ConfigFile automatically when the component loads (Loaded).
    property AutoLoad: Boolean read FAutoLoad write FAutoLoad default False;
  end;

  TAiFunctions = Class(TComponent)
  Private
    FFunctions: TFunctionActionItems;
    FMCPClients: TMCPClientItems;
    FOnStatusUpdate: TMCPStatusEvent;
    FOnLog: TMCPLogEvent;
    FOnMCPStreamMessage: TMCPStreamMessageEvent;
    FAutoMCPConfig: TAutoMCPConfig;
    FOnAutoMCPRequest: TAutoMCPRequestEvent;
    FInstalledPackages: TStringList; // packages already installed in this session
    // AutoMCP: internal functions (invisible to the developer, not in FFunctions)
    FAutoMCPFunctions: TFunctionActionItems;
    FAutoMCPLock: TCriticalSection; // serializes calls to call_mcp_tool
    // Guardrails: tool call security policy (opt-in)
    FGuardrails: TAiGuardrails;
    procedure SetGuardrails(const Value: TAiGuardrails);
    procedure SetOnMCPStreamMessage(const Value: TMCPStreamMessageEvent);
    procedure SetAutoMCPConfig(const Value: TAutoMCPConfig);
    function IsAutoMCPAllowed(const APkgName: string): Boolean;
    // Returns the effective MCP configuration file path:
    // ConfigFile if assigned, otherwise <exedir>\mcp_servers.json
    function GetEffectiveMCPConfigPath: String;
    // AutoMCP: creates ppm_search, ppm_install, call_mcp_tool as internal functions
    procedure CreateInternalPPMFunctions;
    // Callback for TAutoMCPConfig.SetActive — synchronizes state when Active changes
    procedure OnAutoMCPActiveChanged(Sender: TObject);
    // AutoMCP: internal handlers for the 3 PPM functions
    procedure InternalAutoMCP_PpmSearch(ToolCall: TAiToolsFunction);
    procedure InternalAutoMCP_PpmInstall(ToolCall: TAiToolsFunction);
    procedure InternalAutoMCP_CallMcpTool(ToolCall: TAiToolsFunction);
  Protected

    procedure DoLog(const Msg: string); virtual;
    procedure DoStatusUpdate(const StatusMsg: string); virtual;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  Public
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    procedure Loaded; override;
    function GetTools(aToolFormat: TToolFormat): String; Virtual;
    Function DoCallFunction(ToolCall: TAiToolsFunction): Boolean; Virtual;

    // InitAutoMCP: installs mcp-ppm as the AutoMCP system bootstrap.
    // It is called automatically from Loaded if AutoMCP=True.
    // It can be called manually if AutoMCP is enabled at runtime.
    procedure InitAutoMCP;
    // SetFunctionEnable  Returns True if it finds the function and can update the state
    Function SetFunctionEnable(FunctionName: String; Enabled: Boolean): Boolean;
    Function SetMCPClientEnable(Name: String; Enabled: Boolean): Boolean;
    function ExtractFunctionNames: TStringList;

    // IMPORTANT: the aMCPClient parameter must be created with owner = Nil  aMCPClient:= TMCPClientCustom(NIL);
    procedure AddMCPClient(aMCPClient: TMCPClientCustom);
    // Like AddMCPClient but does NOT take ownership — client is managed by an external pool.
    procedure AddBorrowedMCPClient(aMCPClient: TMCPClientCustom);

    // Overload 1: Receives the already parsed JSON object (ideal if the JSON comes from an API or stream)
    function ImportClaudeMCPConfiguration(AConfig: TJSonObject): Integer; overload;

    // Overload 2: Receives the file path (or uses GetEffectiveMCPConfigPath if empty)
    function ImportClaudeMCPConfiguration(const AJsonFilePath: string = ''): Integer; overload;

    // SaveMCPConfiguration: serializes the current MCPClients to the JSON file.
    // AFilePath empty = uses GetEffectiveMCPConfigPath.
    // Returns True if it saved successfully.
    function SaveMCPConfiguration(const AFilePath: string = ''): Boolean;

    // PPM integration (public MCP tool registry)
    // SearchPPMMCP: searches for MCP tools in the registry. The caller frees the TJSONObject.
    function SearchPPMMCP(const AQuery: String; APage: Integer = 1; APerPage: Integer = 20;
      const ARegistryUrl: String = 'https://registry.cimamaker.com'): TJSONObject;

    // ImportMCPFromPPM: registers an MCP tool from PPM as a StdIo stub without downloading.
    // Useful when the binary is already installed manually; the caller must assign
    // Params['Command'] with the path to the executable before enabling the item.
    // AVersion empty = resolves the latest available version.
    function ImportMCPFromPPM(const AName: String; const AVersion: String = '';
      const ARegistryUrl: String = 'https://registry.cimamaker.com'): TMCPClientItem;

    // InstallMCPFromPPM: downloads the .paipkg from the registry, extracts the binary, and
    // registers the StdIo client ready to use.
    // AVersion empty    = resolves the latest available version.
    // AInstallDir empty = ~/.ppm/mcp/<AName>/
    // Returns the configured TMCPClientItem, or nil if it fails.
    function InstallMCPFromPPM(const AName: String; const AVersion: String = '';
      const AInstallDir: String = '';
      const ARegistryUrl: String = 'https://registry.cimamaker.com'): TMCPClientItem;

    // GetMCPSchema: returns the JSON Schema of an MCP tool from the registry.
    // The caller is responsible for freeing the returned TJSONObject.
    // AVersion empty = resolves the latest available version.
    function GetMCPSchema(const AName: String; const AVersion: String = '';
      const ARegistryUrl: String = 'https://registry.cimamaker.com'): TJSONObject;

    // GetAutoMCPSystemPrompt: returns a ready-to-use system prompt that instructs
    // the LLM to use the PPM tools (ppm_search, ppm_install, call_mcp_tool).
    // The developer must assign it manually to the chat component's SystemPrompt.
    // Includes the list of already installed tools, if any.
    function GetAutoMCPSystemPrompt: String;
  Published
    Property Functions: TFunctionActionItems read FFunctions write FFunctions;
    Property MCPClients: TMCPClientItems read FMCPClients write FMCPClients;

    property OnLog: TMCPLogEvent read FOnLog write FOnLog;
    property OnStatusUpdate: TMCPStatusEvent read FOnStatusUpdate write FOnStatusUpdate;
    property OnMCPStreamMessage: TMCPStreamMessageEvent read FOnMCPStreamMessage write SetOnMCPStreamMessage;

    // AutoMCPConfig: grouped configuration for the AutoMCP / PPM subsystem.
    // Expandable in the Object Inspector with (+).
    property AutoMCPConfig: TAutoMCPConfig read FAutoMCPConfig write SetAutoMCPConfig;
    // OnAutoMCPRequest: dynamic callback to approve/deny installations at runtime.
    // It takes priority over Allowed/Blocked. AAllow=True by default.
    property OnAutoMCPRequest: TAutoMCPRequestEvent read FOnAutoMCPRequest write FOnAutoMCPRequest;

    // Guardrails: if assigned, every tool call (local, MCP, or AutoMCP) goes through
    // the policy BEFORE executing; a block is reported to the LLM as an error
    // JSON without executing the tool.
    property Guardrails: TAiGuardrails read FGuardrails write SetGuardrails;

  End;


  // It is necessary to normalize function call formats depending on the driver
  // since Anthropic, OpenAI, and Gemini have subtle differences.

  // Internal class to represent a tool in normalized (neutral) form
  TNormalizedTool = class
  private
    FName: string;
    FDescription: string;
    FInputSchema: TJSonObject; // Always cloned and owned by us
    FIsAsync: Boolean;
  public
    constructor Create(const AName, ADescription: string; AInputSchema: TJSonObject);
    destructor Destroy; override;
    property Name: string read FName;
    property Description: string read FDescription;
    property InputSchema: TJSonObject read FInputSchema;
    // Survives normalization so it can be re-emitted in the formats that
    // understand it (today only tfOpenAIResponses). The others ignore it.
    property IsAsync: Boolean read FIsAsync write FIsAsync;
  end;

  TJsonToolUtils = class
  private
    // --- DETECTION, NORMALIZATION, AND FORMATTING METHODS ---
    class function DetectInputFormat(AJsonTool: TJSonObject): TToolFormat;

    class procedure NormalizeFromMCP(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
    class procedure NormalizeFromOpenAI(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
    class procedure NormalizeFromAnthropic(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
    class procedure NormalizeFromGemini(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);

    class function FormatAsMCP(ANormalizedTool: TNormalizedTool): TJSonObject;
    class function FormatAsOpenAI(ANormalizedTool: TNormalizedTool): TJSonObject;
    class function FormatAsOpenAIResponses(ANormalizedTool: TNormalizedTool): TJSonObject;
    class function FormatAsAnthropic(ANormalizedTool: TNormalizedTool): TJSonObject;
    // class function FormatAsGemini(ANormalizedTool: TNormalizedTool): TJSonObject;

    class function FormatAsGeminiFunctionDeclaration(ANormalizedTool: TNormalizedTool): TJSonObject;
    // class function FormatAsCohere(ANormalizedTool: TNormalizedTool): TJSonObject;

    // Original explicit version (useful if detection fails or for specific cases)
    class function MergeToolLists(const ASourceName: string; ASourceJson: TJSonObject; AInputFormat: TToolFormat; ATargetJson: TJSonObject; AOutputFormat: TToolFormat): TJSonObject; overload;

    class procedure CleanInputSchema(ASchema: TJSonObject);

    class procedure CleanJsonTree(AValue: TJSONValue);
    class procedure EnforceStrictSchema(ASchema: TJSONValue);
  public

    // Overload with automatic input format detection
    class function MergeToolLists(const ASourceName: string; ASourceJson: TJSonObject; ATargetJson: TJSonObject; AOutputFormat: TToolFormat): TJSonObject; overload;

    // Normalizes the tools from a source JSON object and adds them to a list.
    class procedure NormalizeToolsFromSource(const ASourceName: string; ASourceJson: TJSonObject; ANormalizedList: TList<TNormalizedTool>);

    // Formats a list of normalized tools to the desired output format.
    class function FormatToolList(ANormalizedList: TList<TNormalizedTool>; AOutputFormat: TToolFormat): TJSonObject;

  end;

procedure Register;

implementation

uses uMakerAi.Chat, System.Zip, System.IniFiles, uMakerAi.Telemetry;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiFunctions]);
end;

{ TWebTagActionItem }

constructor TFunctionActionItem.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FCollection := Collection;
  FEnabled := True;
  FDescription := TStringList.Create;
  FScript := TStringList.Create;
  FParams := TFunctionParamsItems.Create(Self, TFunctionParamsItem);
end;

destructor TFunctionActionItem.Destroy;
begin
  FDescription.Free;
  FParams.Free;
  FScript.Free;
  inherited;
end;

// ISSUE #125: see note in TFunctionParamsItem.Assign.
procedure TFunctionActionItem.Assign(Source: TPersistent);
var
  Src: TFunctionActionItem;
begin
  if Source is TFunctionActionItem then
  begin
    Src := TFunctionActionItem(Source);
    FEnabled := Src.FEnabled;
    FName := Src.FName;
    FOnAction := Src.FOnAction;
    FDefault := Src.FDefault;
    FDescription.Assign(Src.FDescription);
    FTagObject := Src.FTagObject;
    FTag := Src.FTag;
    FToolType := Src.FToolType;
    FScript.Assign(Src.FScript);
    FParams.Assign(Src.FParams);
    FRawSchemaJson := Src.FRawSchemaJson;
    FIsAsync := Src.FIsAsync;
    Changed(False);
  end
  else
    inherited;
end;

function TFunctionActionItem.GetDisplayName: string;
begin
  Inherited GetDisplayName;
  Result := FName;
end;

function TFunctionActionItem.GetNamePath: string;
begin
  Result := inherited GetNamePath + Self.FunctionName; // Format('MyField%d',[Index]);
end;

procedure TFunctionActionItem.SetDefault(const Value: Boolean);
var
  I: Integer;
begin
  // First, removes the default from the other items
  If Value = True then
  Begin
    for I := 0 to FCollection.Count - 1 do
      TFunctionActionItem(FCollection.Items[I]).Default := False;
  End;

  // Self.Collection

  FDefault := Value;
end;

procedure TFunctionActionItem.SetDisplayName(const Value: string);
var
  I: Integer;
  Action: TFunctionActionItem;
begin
  if CompareText(Value, FName) <> 0 then
  begin
    if FCollection <> nil then
      for I := 0 to FCollection.Count - 1 do
      begin
        Action := TFunctionActionItem(FCollection.Items[I]);
        if (Action <> Self) and (Action is TFunctionActionItem) and (CompareText(Value, Action.FunctionName) = 0) then
          raise Exception.Create('duplicate action name');
      end;
    FName := Value;
    Changed(False);
  end;

  If FName = '' then
  Begin
    FName := Value;
    Changed(False);
  End;
end;

procedure TFunctionActionItem.SetEnabled(const Value: Boolean);
begin
  FEnabled := Value;
end;

procedure TFunctionActionItem.SetFunctionDoc(const Value: TStrings);
begin
  If Length(Value.Text) > 1024 then
    Raise Exception.Create('Exceeds the maximum description limit of 1024 characters');

  FDescription.Text := Value.Text;
end;

procedure TFunctionActionItem.SetJSon(Value: TJSonObject);
Var
  aTipo, ADescription, aParamName, aScript: String;
  jFunc, jParameters, jProperties, jParam: TJSonObject;
  jReq: TJSonArray;
  jVal: TJSONValue;
  aEnabled, aDefault: Boolean;
  aParam: TFunctionParamsItem;
  I: Integer;
begin
  aTipo := Value.GetValue<String>('type');
  If aTipo = 'function' then
    ToolType := TToolstype.tt_function
  Else
    ToolType := TToolstype.ttNone;

  If Value.TryGetValue<Boolean>('enabled', aEnabled) then
    Enabled := aEnabled;

  If Value.TryGetValue<Boolean>('default', aDefault) then
    Default := aDefault;

  If Value.TryGetValue<TJSonObject>('function', jFunc) then
  Begin
    If jFunc.TryGetValue<String>('description', ADescription) then
      Description.Text := ADescription;

    If jFunc.TryGetValue<String>('script', aScript) then
      FScript.Text := aScript;

    jFunc.TryGetValue<Boolean>('enabled', FEnabled);

    If jFunc.TryGetValue<TJSonObject>('parameters', jParameters) then
    Begin
      If jParameters.GetValue<String>('type') = 'object' then
      Begin
        If jParameters.TryGetValue<TJSonObject>('properties', jProperties) then
        Begin
          For I := 0 to jProperties.Count - 1 do
          Begin

            aParamName := jProperties.Pairs[I].JsonString.Value;
            jParam := TJSonObject(jProperties.Pairs[I].JsonValue);

            aParam := Parameters.Add;
            aParam.Name := aParamName;
            aParam.SetJSon(jParam);
          End;
        End;

        If jParameters.TryGetValue<TJSonArray>('required', jReq) then
        Begin
          For jVal in jReq do
          Begin
            If Assigned(Parameters.GetParamByName(jVal.Value)) then
              Parameters.GetParamByName(jVal.Value).Required := True;
          End;
        End;
      End;
    End;
  End;

end;

procedure TFunctionActionItem.SetOnAction(const Value: TFunctionEvent);
begin
  FOnAction := Value;
  Changed(False);
end;

procedure TFunctionActionItem.SetScript(const Value: TStrings);
begin
  FScript.Text := Value.Text;
end;

procedure TFunctionActionItem.SetTag(const Value: Integer);
begin
  FTag := Value;
end;

procedure TFunctionActionItem.SetTagObject(const Value: TObject);
begin
  FTagObject := Value;
end;

procedure TFunctionActionItem.SetToolType(const Value: TToolstype);
begin
  FToolType := Value;
end;

function TFunctionActionItem.ToJSon(Detail: Boolean = False): TJSonObject;
Var
  Fun, Params: TJSonObject;

begin
  // Later they may create other kinds of tools; for now there are only functions
  Result := Nil;

  If (Self.Enabled) and (Self.ToolType = tt_function) then
  Begin
    Result := TJSonObject.Create;
    Fun := TJSonObject.Create;
    Fun.AddPair('name', FunctionName);
    Fun.AddPair('description', FDescription.Text.Trim);

    If Detail then
    Begin
      Fun.AddPair('script', FScript.Text.Trim);
      Fun.AddPair('enabled', FEnabled);
      Fun.AddPair('default', FDefault);
    End;

    // Prefer RawSchemaJson (full schema) over rebuilding from TFunctionParamsItems
    if FRawSchemaJson <> '' then
      Params := TJSonObject(TJSonObject.ParseJSONValue(FRawSchemaJson))
    else
      Params := Parameters.ToJSon(Detail);

    If Assigned(Params) then
      Fun.AddPair('parameters', Params);

    // It is only written when True: an explicit "async": false adds nothing
    // and would clutter the schema of providers that do not know it.
    If FIsAsync then
      Fun.AddPair('async', TJSONBool.Create(True));

    Result.AddPair('type', 'function');
    Result.AddPair('function', Fun);
  End;

end;

{ TFunctionActionItems }

function TFunctionActionItems.Add: TFunctionActionItem;
Var
  Item: TCollectionItem;
begin
  Item := Inherited Add;
  Result := TFunctionActionItem(Item);
end;

function TFunctionActionItems.AddFunction(Nombre: String; Enabled: Boolean; Action: TFunctionEvent): TFunctionActionItem;
Var
  Item: TFunctionActionItem;
Begin
  Item := TFunctionActionItem(Add);
  Item.FunctionName := Nombre;
  Item.Enabled := Enabled;
  Item.OnAction := Action;
  Result := Item;
End;

constructor TFunctionActionItems.Create(AOwner: TPersistent; ItemClass: TCollectionItemClass);
begin
  FOwner := AOwner;
  inherited Create(Self, ItemClass);
end;

destructor TFunctionActionItems.Destroy;
begin

  inherited;
end;

function TFunctionActionItems.GetActionItem(Index: Integer): TFunctionActionItem;
begin
  Result := TFunctionActionItem(inherited Items[Index]);
end;

function TFunctionActionItems.GetFunction(Nombre: String): TFunctionActionItem;
Var
  I: Integer;
  Item: TFunctionActionItem;
Begin
  Result := Nil;
  I := IndexOf(Nombre);
  If I >= 0 then
  Begin
    Item := TFunctionActionItem(Items[I]);
    Result := Item;
  End;
end;

function TFunctionActionItems.GetItemByName(aTagName: String): TFunctionActionItem;
var
  I: Integer;
  CurItem, DefItem: TFunctionActionItem;

begin
  I := 0;
  Result := Nil;
  DefItem := Nil;
  while I < Count do
  begin
    CurItem := Items[I] as TFunctionActionItem;

    If (CurItem.Default and CurItem.Enabled) then // If there is a default item, it is found here
      DefItem := CurItem;

    if (CompareText(CurItem.FunctionName, aTagName) = 0) and CurItem.Enabled then
    begin
      Result := CurItem;
      Break;
    end;
    Inc(I);
  end;

  If Result = Nil then // If no match is found, it is sent to the default event
    Result := DefItem;

end;

function TFunctionActionItems.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TFunctionActionItems.IndexOf(Nombre: String): Integer;
Var
  I: Integer;
  Item: TFunctionActionItem;
Begin
  Result := -1;
  For I := 0 to Self.Count - 1 do
  Begin
    Item := TFunctionActionItem(Self.Items[I]);
    If (Item <> Nil) and (AnsiUpperCase(Nombre) = AnsiUpperCase(Item.FunctionName)) then
    Begin
      Result := I;
      Break;
    End;
  End;
end;

procedure TFunctionActionItems.LoadFromFile(FileName: String);
Var
  Funcs: TJSonArray;
  jFunc: TJSonObject;
  jVal: TJSONValue;
  Lista: TStringStream;
  FuncName: String;
  Item: TFunctionActionItem;
begin
  If Not TFile.Exists(FileName) then
    Raise Exception.Create('File "' + FileName + '" not found on the system');

  Lista := TStringStream.Create('', TEncoding.UTF8);
  try
    Lista.LoadFromFile(FileName);
    var LParsed := TJSonObject.ParseJSONValue(Lista.DataString);
    if not (LParsed is TJSonArray) then
    begin
      LParsed.Free;
      Raise Exception.Create('The file does not contain a valid JSON array');
    end;
    Funcs := TJSonArray(LParsed);
    try
      Self.Clear;

      For jVal in Funcs do
      Begin
        jFunc := TJSonObject(jVal);
        If jFunc.GetValue<String>('type') = 'function' then
        Begin
          FuncName := jFunc.GetValue<TJSonObject>('function').GetValue<String>('name');
          Item := Self.Add;
          Item.FunctionName := FuncName;
          Item.SetJSon(jFunc);
        End;
      End;
    Finally
      Funcs.Free;
    End;
  Finally
    Lista.Free;
  End;
end;

procedure TFunctionActionItems.SaveToFile(FileName: String);
Var
  Funcs: TJSonArray;
  Lista: TStringStream;
begin
  Funcs := ToJSon(True);
  Lista := TStringStream.Create(Funcs.Format, TEncoding.UTF8);
  Try
    Lista.SaveToFile(FileName);
  Finally
    Funcs.Free;
    Lista.Free;
  End;
end;

procedure TFunctionActionItems.SetActionItem(Index: Integer; Value: TFunctionActionItem);
begin
  Items[Index].Assign(Value);
end;

procedure TFunctionActionItems.SetItemName(Item: TCollectionItem);
var
  I, J: Integer;
  ItemName: string;
  CurItem: TFunctionActionItem;
begin
  J := 1;
  while True do
  begin
    ItemName := Format('FunctionItem%d', [J]); { do not localize }
    I := 0;
    while I < Count do
    begin
      CurItem := Items[I] as TFunctionActionItem;
      if (CurItem <> Item) and (CompareText(CurItem.FunctionName, ItemName) = 0) then
      begin
        Inc(J);
        Break;
      end;
      Inc(I);
    end;
    if I >= Count then
    begin
      (Item as TFunctionActionItem).FunctionName := ItemName;
      Break;
    end;
  end;
end;

function TFunctionActionItems.ToJSon(aDetail: Boolean = False): TJSonArray;
Var
  I: Integer;
  Item: TFunctionActionItem;
  JObj: TJSonObject;
begin
  Result := TJSonArray.Create;

  For I := 0 to Count - 1 do
  Begin
    Item := TFunctionActionItem(GetItem(I));
    JObj := Item.ToJSon(aDetail);
    If Assigned(JObj) then
      Result.Add(JObj);
  End;
end;

procedure TFunctionActionItems.Update(Item: TCollectionItem);
begin
  inherited;
  { + !!  if (FWebDispatcher <> nil) and
    not (csLoading in FWebDispatcher.ComponentState) then }
end;

{ TFunctionParamsItem }

constructor TFunctionParamsItem.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FCollection := Collection;
  FDescription := TStringList.Create;
end;

destructor TFunctionParamsItem.Destroy;
begin
  Description.Free;
  inherited;
end;

// ISSUE #125: collection items need Assign for streaming of
// inherited forms/data modules; without it, TPersistent.Assign raises
// "Cannot assign TFunctionParamsItem to TFunctionParamsItem".
procedure TFunctionParamsItem.Assign(Source: TPersistent);
var
  Src: TFunctionParamsItem;
begin
  if Source is TFunctionParamsItem then
  begin
    Src := TFunctionParamsItem(Source);
    FName := Src.FName;
    FParamType := Src.FParamType;
    FRequired := Src.FRequired;
    FDescription.Assign(Src.FDescription);
    FEnum := Src.FEnum;
    Changed(False);
  end
  else
    inherited;
end;

function TFunctionParamsItem.GetDisplayName: string;
begin
  Inherited GetDisplayName;
  Result := FName;
end;

function TFunctionParamsItem.GetNamePath: string;
begin
  Result := inherited GetNamePath + Format('Param%d', [Index]);
  // Result := inherited GetNamePath + Self.name; // Format('MyField%d',[Index]);
end;

procedure TFunctionParamsItem.SetDescription(const Value: TStrings);
begin
  FDescription.Text := Value.Text;
end;

procedure TFunctionParamsItem.SetDisplayName(const Value: string);
var
  I: Integer;
  Param: TFunctionParamsItem;
begin
  if CompareText(Value, FName) <> 0 then
  begin
    if FCollection <> nil then
      for I := 0 to FCollection.Count - 1 do
      begin
        Param := TFunctionParamsItem(FCollection.Items[I]);
        if (Param <> Self) and (Param is TFunctionParamsItem) and (CompareText(Value, Param.FName) = 0) then
          raise Exception.Create('The parameter name is duplicated');
      end;
    FName := Value;
    Changed(False);
  end;

  If FName = '' then
  Begin
    FName := Value;
    Changed(False);
  End;
end;

procedure TFunctionParamsItem.SetEnum(const Value: String);
begin
  FEnum := Value;
end;

procedure TFunctionParamsItem.SetJSon(Value: TJSonObject);
Var
  aType, ADescription: String;
  jEnum: TJSonArray;
  jVal: TJSONValue;
  Lista: TStringList;
begin
  aType := Value.GetValue<String>('type');
  If aType = 'string' then
    ParamType := TToolsParamType.ptString
  Else If aType = 'integer' then
    ParamType := TToolsParamType.ptInteger
  Else If aType = 'boolean' then
    ParamType := TToolsParamType.ptBoolean
  Else If aType = 'float' then
    ParamType := TToolsParamType.ptFloat
  Else If aType = 'date' then
    ParamType := TToolsParamType.ptDate
  Else If aType = 'time' then
    ParamType := TToolsParamType.ptTime
  Else If aType = 'datetime' then
    ParamType := TToolsParamType.ptDateTime
  Else
    ParamType := TToolsParamType.ptString;

  If Value.TryGetValue<String>('description', ADescription) then
    FDescription.Text := ADescription;

  If Value.TryGetValue<TJSonArray>('enum', jEnum) then
  Begin
    Lista := TStringList.Create;
    Try
      For jVal in jEnum do
      Begin
        If ParamType in [ptInteger, ptBoolean, ptFloat] then
          Lista.Add(jVal.Value)
        Else
          Lista.Add(jVal.Value);
      End;
      FEnum := Lista.CommaText;
    Finally
      Lista.Free;
    End;
  End;
end;

procedure TFunctionParamsItem.SetName(const Value: String);
begin
  FName := Value;
end;

procedure TFunctionParamsItem.SetParamType(const Value: TToolsParamType);
begin
  FParamType := Value;
end;

procedure TFunctionParamsItem.SetRequired(const Value: Boolean);
begin
  FRequired := Value;
end;

function TFunctionParamsItem.ToJSon(Detail: Boolean = False): TJSonObject;
Var
  Tipo: String;
  jEnum: TJSonArray;
  I: Integer;
  Lista: TStringList;
begin
  Result := TJSonObject.Create;
  Case FParamType of
    ptString, ptBase64:
      Tipo := 'string';
    ptInteger:
      Tipo := 'integer';
    ptBoolean:
      Tipo := 'boolean';
    ptFloat:
      Tipo := 'float';
    ptDate:
      Tipo := 'date';
    ptTime:
      Tipo := 'time';
    ptDateTime:
      Tipo := 'datetime';
  End;

  Result.AddPair('type', Tipo);
  If Self.Description.Text.Trim <> '' then
    Result.AddPair('description', Description.Text.Trim);
  If Enum.Trim <> '' then
  Begin
    Lista := TStringList.Create;
    Try
      Lista.CommaText := Enum.Trim;
      I := Lista.Count;
      If I > 0 then
      Begin
        jEnum := TJSonArray.Create;
        Result.AddPair('enum', jEnum);
        For I := 0 to Lista.Count - 1 do
        Begin
          If FParamType in [ptString, ptDate, ptTime, ptDateTime, ptBase64] then
            jEnum.Add('"' + Lista[I].Trim + '"')
          Else If FParamType in [ptInteger, ptBoolean, ptFloat] then
            jEnum.Add(Lista[I].Trim)
        End;
      End;
    Finally
      Lista.Free;
    End;
  End;
end;

{ TFunctionParamsItems }

function TFunctionParamsItems.Add: TFunctionParamsItem;
Var
  Item: TCollectionItem;
begin
  Item := Inherited Add;
  Result := TFunctionParamsItem(Item);
end;

constructor TFunctionParamsItems.Create(AOwner: TPersistent; ItemClass: TCollectionItemClass);
begin
  FOwner := AOwner;
  inherited Create(Self, ItemClass);
end;

destructor TFunctionParamsItems.Destroy;
begin

  inherited;
end;

function TFunctionParamsItems.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TFunctionParamsItems.GetParamByName(aParamName: String): TFunctionParamsItem;
var
  I: Integer;
  CurItem: TFunctionParamsItem;
begin
  I := 0;
  Result := Nil;
  while I < Count do
  begin
    CurItem := Items[I] as TFunctionParamsItem;

    if (CompareText(CurItem.Name, aParamName) = 0) then
    begin
      Result := CurItem;
      Break;
    end;
    Inc(I);
  end;
end;

function TFunctionParamsItems.GetParams(Index: Integer): TFunctionParamsItem;
begin
  Result := TFunctionParamsItem(inherited Items[Index]);
end;

procedure TFunctionParamsItems.SetItemName(Item: TCollectionItem);
var
  I, J: Integer;
  ItemName: string;
  CurItem: TFunctionParamsItem;
begin
  J := 1;
  while True do
  begin
    ItemName := Format('Param%d', [J]); { do not localize }
    I := 0;
    while I < Count do
    begin
      CurItem := Items[I] as TFunctionParamsItem;
      if (CurItem <> Item) and (CompareText(CurItem.Name, ItemName) = 0) then
      begin
        Inc(J);
        Break;
      end;
      Inc(I);
    end;
    if I >= Count then
    begin
      (Item as TFunctionParamsItem).Name := ItemName;
      Break;
    end;
  end;
end;

procedure TFunctionParamsItems.SetParams(Index: Integer; const Value: TFunctionParamsItem);
begin
  Items[Index].Assign(Value);
end;

function TFunctionParamsItems.ToJSon(Detail: Boolean = False): TJSonObject;
Var
  CurItem: TFunctionParamsItem;
  jProperties: TJSonObject;
  jRequired: TJSonArray;
  I: Integer;
begin
  Result := Nil;

  If Count > 0 then
  Begin
    Result := TJSonObject.Create;

    Result.AddPair('type', 'object');

    jProperties := TJSonObject.Create;
    jRequired := TJSonArray.Create;
    Result.AddPair('properties', jProperties);

    For I := 0 to Count - 1 do
    Begin
      CurItem := TFunctionParamsItem(Items[I]);
      jProperties.AddPair(CurItem.Name, CurItem.ToJSon(Detail));

      If CurItem.Required then
        jRequired.Add(CurItem.Name);
    End;
    If jRequired.Count > 0 then
      Result.AddPair('required', jRequired)
    else
      jRequired.Free;
  End;
end;

procedure TFunctionParamsItems.Update(Item: TCollectionItem);
begin
  inherited;
  { + !!  if (FWebDispatcher <> nil) and
    not (csLoading in FWebDispatcher.ComponentState) then }

end;

{ TAiFunctions }

{ procedure TAiFunctions.AddMCPClient(aMCPClient: TMCPClientCustom);
  var
  NewItem: TMCPClientItem;
  begin
  if not Assigned(aMCPClient) then
  raise Exception.Create('Attempted to add a null TMCPClient object.');

  if aMCPClient.Name.Trim.IsEmpty then
  raise Exception.Create('The TMCPClient must have a Name property assigned before being added.');

  // 1. Check whether a client with the same name already exists to avoid duplicates.
  if Assigned(FMCPClients.GetClientByName(aMCPClient.Name)) then
  raise Exception.CreateFmt('An MCP client with the name "%s" already exists.', [aMCPClient.Name]);

  aMCPClient.OnStreamMessage := FOnMCPStreamMessage;

  // And we also make sure to connect OnLog and OnStatusUpdate
  aMCPClient.OnLog := FOnLog;
  aMCPClient.OnStatusUpdate := FOnStatusUpdate;

  // 2. Create a new item in the collection.
  // This Add creates a TMCPClientItem that in turn creates a default TMCPClientStdIo.
  NewItem := FMCPClients.Add;

  // 3. Replace the default client with the one passed in by the user.
  // First, free the one that was created automatically.
  FreeAndNil(NewItem.FMCPClient);

  // Now assign the user's client. NewItem becomes the owner.
  NewItem.FMCPClient := aMCPClient;

  // 4. Synchronize the wrapper properties with the client state.
  // Properties such as Name, Params, etc. already work as proxies,
  // but Enabled is a direct property of TMCPClientItem.
  NewItem.Enabled := aMCPClient.Enabled;
  NewItem.Connected := False; // It is always added as disconnected. Connecting is a later action.

  // Optional: log the event
  DoLog(Format('MCP client "%s" added programmatically.', [aMCPClient.Name]));
  end;
}

procedure TAiFunctions.AddMCPClient(aMCPClient: TMCPClientCustom);
var
  NewItem: TMCPClientItem;
begin
  if not Assigned(aMCPClient) then
    raise Exception.Create('Attempted to add a null TMCPClient object.');

  if aMCPClient.Name.Trim.IsEmpty then
    raise Exception.Create('The TMCPClient must have a Name property assigned before being added.');

  // 1. Check for duplicates
  if Assigned(FMCPClients.GetClientByName(aMCPClient.Name)) then
    raise Exception.CreateFmt('An MCP client with the name "%s" already exists.', [aMCPClient.Name]);

  // Connect events
  aMCPClient.OnStreamMessage := FOnMCPStreamMessage;
  aMCPClient.OnLog := FOnLog;
  aMCPClient.OnStatusUpdate := FOnStatusUpdate;

  // 2. Create new item (this creates its own nil or default FMCPClient and EMPTY FParams)
  NewItem := FMCPClients.Add;

  // 3. Replace internal client
  if Assigned(NewItem.FMCPClient) then
    FreeAndNil(NewItem.FMCPClient);
  NewItem.FMCPClient := aMCPClient;

  // 4. --- [CRITICAL FIX] REVERSE SYNCHRONIZATION ---
  // We must copy the real client's configuration TO the wrapper (Item)
  // so the wrapper holds the "truth" and does not overwrite with empty values afterward.

  NewItem.FParams.Assign(aMCPClient.Params); // <--- THIS WAS MISSING
  NewItem.FEnvVars.Assign(aMCPClient.EnvVars); // <--- THIS WAS MISSING
  NewItem.Name := aMCPClient.Name; // Synchronize name
  NewItem.Enabled := aMCPClient.Enabled; // Synchronize enabled

  // Important: Synchronize TransportType in the wrapper without triggering client recreation
  // We access the private variable or use a cast if necessary,
  // but when using the Item's TransportType property, it will verify that the internal object
  // already has that type and will not destroy it.
  NewItem.TransportType := aMCPClient.TransportType;

  NewItem.Connected := False;

  DoLog(Format('MCP client "%s" added and synchronized.', [aMCPClient.Name]));
end;

procedure TAiFunctions.AddBorrowedMCPClient(aMCPClient: TMCPClientCustom);
var
  NewItem: TMCPClientItem;
begin
  if not Assigned(aMCPClient) then
    raise Exception.Create('Attempted to add a null TMCPClient object.');
  if aMCPClient.Name.Trim.IsEmpty then
    raise Exception.Create('The TMCPClient must have Name assigned.');
  if Assigned(FMCPClients.GetClientByName(aMCPClient.Name)) then
    raise Exception.CreateFmt('An MCP client with the name "%s" already exists.', [aMCPClient.Name]);

  // Do NOT overwrite the client's existing event handlers — the pooled client
  // already has its log bridge wired from initialization.

  NewItem := FMCPClients.Add;
  if Assigned(NewItem.FMCPClient) then
    FreeAndNil(NewItem.FMCPClient);
  NewItem.FMCPClient := aMCPClient;
  NewItem.FOwned     := False;   // pool owns the client; this item is just a reference

  NewItem.FParams.Assign(aMCPClient.Params);
  NewItem.FEnvVars.Assign(aMCPClient.EnvVars);
  NewItem.Name          := aMCPClient.Name;
  NewItem.Enabled       := aMCPClient.Enabled;
  NewItem.TransportType := aMCPClient.TransportType;
  NewItem.Connected     := False;

  DoLog(Format('MCP client "%s" added (borrowed, no ownership).', [aMCPClient.Name]));
end;

constructor TAiFunctions.Create(AOwner: TComponent);
begin
  inherited;
  FFunctions := TFunctionActionItems.Create(Self, TFunctionActionItem);
  FMCPClients := TMCPClientItems.Create(Self);
  FAutoMCPConfig := TAutoMCPConfig.Create;
  FAutoMCPConfig.FOnActiveChanged := OnAutoMCPActiveChanged;
  FInstalledPackages := TStringList.Create;
  FAutoMCPFunctions := TFunctionActionItems.Create(Self, TFunctionActionItem);
  FAutoMCPLock := TCriticalSection.Create;
end;

destructor TAiFunctions.Destroy;
begin
  FFunctions.Free;
  FMCPClients.Free;
  FAutoMCPConfig.Free;
  FInstalledPackages.Free;
  FAutoMCPFunctions.Free;
  FAutoMCPLock.Free;
  inherited;
end;

function TAiFunctions.DoCallFunction(ToolCall: TAiToolsFunction): Boolean;
var
  Funcion: TFunctionActionItem;
  PosAt: Integer;
  ServerName, ActualToolName: string;
  ClientItem: TMCPClientItem;
  ArgsObject, ResultObject: TJSonObject;
  AExtractedMedia: TObjectList<TAiMediaFile>; // Lista temporal
  MF: TAiMediaFile;
  LSpan: TAiSpan;
begin
  Result := False;

  AExtractedMedia := TObjectList<TAiMediaFile>.Create;

  // Telemetry: span per tool execution (GenAI semconv). It is nested
  // automatically into the chat turn span when running on the same thread.
  LSpan := AiSpanStart('execute_tool ' + ToolCall.Name);
  AiSpanAttr(LSpan, 'gen_ai.operation.name', 'execute_tool');
  AiSpanAttr(LSpan, 'gen_ai.tool.name', ToolCall.Name);

  try
    if SameText(Copy(ToolCall.Name, 1, Length('local' + MCP_TOOL_SEP)), 'local' + MCP_TOOL_SEP) then
      ToolCall.Name := Copy(ToolCall.Name, Length('local' + MCP_TOOL_SEP) + 1, Length(ToolCall.Name));

    // Guardrails: security policy before ANY tool execution
    // (local, MCP, or AutoMCP). If it blocks, the tool is NOT executed and the LLM
    // receives the reason as an error so it can rethink its plan.
    if Assigned(FGuardrails) then
    begin
      var LGuardReason: string;
      if not FGuardrails.CheckToolCall(ToolCall.Name, ToolCall.Arguments, LGuardReason) then
      begin
        var LErrObj := TJSonObject.Create;
        try
          LErrObj.AddPair('error', 'Blocked by guardrails: ' + LGuardReason);
          ToolCall.Response := LErrObj.ToJSON;
        finally
          LErrObj.Free;
        end;
        AiSpanAttr(LSpan, 'guardrail.blocked', True);
        DoLog('Guardrails blocked the tool "' + ToolCall.Name + '": ' + LGuardReason);
        Result := True; // handled: it is reported to the LLM without executing the tool
        Exit;
      end;
    end;

    PosAt := Pos(MCP_TOOL_SEP, ToolCall.Name);

    // AutoMCP: dispatch to internal handlers before searching in FFunctions.
    // Lazy init: creates the functions if Active=True but they do not exist yet.
    if FAutoMCPConfig.Active and (PosAt = 0) then
    begin
      if FAutoMCPFunctions.Count = 0 then
        CreateInternalPPMFunctions;
      if SameText(ToolCall.Name, 'ppm_search') then
      begin
        InternalAutoMCP_PpmSearch(ToolCall);
        Result := True;
        Exit;
      end
      else if SameText(ToolCall.Name, 'ppm_install') then
      begin
        InternalAutoMCP_PpmInstall(ToolCall);
        Result := True;
        Exit;
      end
      else if SameText(ToolCall.Name, 'call_mcp_tool') then
      begin
        InternalAutoMCP_CallMcpTool(ToolCall);
        Result := True;
        Exit;
      end;
    end;

    if PosAt = 0 then // --- It is a local function ---
    begin
      Funcion := FFunctions.GetFunction(ToolCall.Name);
      if Assigned(Funcion) and Assigned(Funcion.OnAction) then
        Funcion.OnAction(Self, Funcion, ToolCall.Name, ToolCall, Result);
    end
    else // --- It is a call to an MCP client ---
    begin
      ServerName := Copy(ToolCall.Name, 1, PosAt - 1);
      ActualToolName := Copy(ToolCall.Name, PosAt + Length(MCP_TOOL_SEP), Length(ToolCall.Name));

      ClientItem := FMCPClients.GetClientByName(ServerName);
      if Assigned(ClientItem) and ClientItem.Enabled and ClientItem.MCPClient.Available then
      begin
        ResultObject := nil;
        try
          ClientItem.MCPClient.OnLog := FOnLog;
          ClientItem.MCPClient.OnStatusUpdate := FOnStatusUpdate;

          var LParsedArgs := TJSonObject.ParseJSONValue(ToolCall.Arguments);
          if LParsedArgs is TJSonObject then
            ArgsObject := TJSonObject(LParsedArgs)
          else
          begin
            LParsedArgs.Free;
            ArgsObject := TJSonObject.Create; // Fallback: empty object if Arguments is ''
          end;
          ResultObject := ClientItem.MCPClient.CallTool(ActualToolName, ArgsObject, AExtractedMedia);

          if Assigned(ResultObject) then
          begin
            ToolCall.Response := ResultObject.ToJSon;
            ResultObject.Free;

            If AExtractedMedia.Count > 0 then
            Begin
              // Extracted files → ToolCall.MediaFiles (drivers transfer them
              // to the ToolMsg so the LLM sees them in the next turn).
              // Additionally, they are cloned to ResMsg so the app receives them
              // in OnReceiveDataEnd without ownership conflicts.
              For MF In AExtractedMedia do
              Begin
                ToolCall.MediaFiles.Add(MF); // original → ToolMsg (via driver)

                If Assigned(ToolCall.ResMsg) then
                Begin
                  var LClone := TAiMediaFile.Create;
                  LClone.LoadFromBase64(MF.FileName, MF.Base64); // MimeType derived from the filename
                  TAiChatMessage(ToolCall.ResMsg).AddMediaFile(LClone); // clone → app
                End;
              End;
              AExtractedMedia.OwnsObjects := False;
            End;
          end
          else
          begin
            // CallTool returned nil: the process failed to start or did not respond.
            // Available was already set to False by TMCPClientStdIo.
            ToolCall.Response := Format(
              '{"error":"MCP server ''%s'' failed to initialize (binary crashed or did not respond). ' +
              'The binary may be missing runtime dependencies or be incompatible with this system."}',
              [ServerName]);
          end;

          Result := True;

        except
          on E: Exception do
          begin
            // ArgsObject is not freed here: CallTool takes ownership of the object.
            // If the exception occurs BEFORE CallTool, ArgsObject is lost,
            // but that is preferable to a double-free if it occurs AFTER.
            FreeAndNil(ResultObject);
            ClientItem.MCPClient.Available := False;
            ToolCall.Response := Format('{"error":"%s"}',
              [StringReplace(E.Message, '"', '\"', [rfReplaceAll])]);
            Result := True; // Return True so the LLM receives the error message
          end;
        end;
      end
      else
      begin
        // The name contains MCP_TOOL_SEP but there is NO MCP server backing
        // it. Before returning the error, it is searched by FULL name among the
        // registered functions: '_99_' is our internal convention, not
        // a reserved sequence, and whoever declares a tool has every
        // right to call it 'alfa_99_beta'. Without this exit path, such a tool
        // was mute: it responded 'MCP server not found' and the model
        // invented an explanation about a downed server instead of emitting
        // the tool_call.
        Funcion := FFunctions.GetFunction(ToolCall.Name);
        if Assigned(Funcion) and Assigned(Funcion.OnAction) then
          Funcion.OnAction(Self, Funcion, ToolCall.Name, ToolCall, Result)
        else
        begin
          // Client not found, disabled, or unavailable.
          // Set Response so the driver can send a valid tool result to the LLM.
          if not Assigned(ClientItem) then
            ToolCall.Response := Format('{"error":"MCP server ''%s'' not found"}', [ServerName])
          else if not ClientItem.Enabled then
            ToolCall.Response := Format('{"error":"MCP server ''%s'' is disabled"}', [ServerName])
          else
            ToolCall.Response := Format('{"error":"MCP server ''%s'' is not available"}', [ServerName]);
          Result := True;
        end;
      end;
    end;

  finally
    // Telemetry: a ToolCall.Response with '"error"' marks the span as failed
    if Result and Assigned(LSpan) and (Pos('"error"', ToolCall.Response) > 0) then
      AiSpanEnd(LSpan, 'tool returned error response')
    else if not Result then
      AiSpanEnd(LSpan, 'tool not found or not handled')
    else
      AiSpanEnd(LSpan);
    // Free the temporary list.
    // If we transferred the files, OwnsObjects will be False and it will not delete them.
    // If something failed, OwnsObjects will be True and it will delete the temporaries to avoid leaks.
    if Assigned(AExtractedMedia) then
      AExtractedMedia.Free;
  end;
end;

procedure TAiFunctions.DoLog(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Msg);

end;

procedure TAiFunctions.SetGuardrails(const Value: TAiGuardrails);
begin
  if FGuardrails <> Value then
  begin
    FGuardrails := Value;
    if Assigned(FGuardrails) then
      FGuardrails.FreeNotification(Self);
  end;
end;

procedure TAiFunctions.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FGuardrails) then
    FGuardrails := nil;
end;

procedure TAiFunctions.DoStatusUpdate(const StatusMsg: string);
begin
  if Assigned(FOnStatusUpdate) then
    FOnStatusUpdate(Self, StatusMsg);
end;

function TAiFunctions.ExtractFunctionNames: TStringList;
var
  JsonArray: TJSonArray;
  ArrayItem: TJSONValue;
  FunctionObj: TJSonObject;
  NameValue: TJSONValue;
  FunctionName, JsonString: string;
  I: Integer;
begin
  Result := TStringList.Create;

  try
    JsonString := GetTools(TToolFormat.tfOpenAI);

    // Parse the JSON as an array
    var LParsedVal := TJSonObject.ParseJSONValue(JsonString);
    if not (LParsedVal is TJSonArray) then
    begin
      LParsedVal.Free;
      raise Exception.Create('Invalid JSON or not an array');
    end;
    JsonArray := TJSonArray(LParsedVal);

    try
      // Iterate over each element of the array
      for I := 0 to JsonArray.Count - 1 do
      begin
        ArrayItem := JsonArray.Items[I];
        if ArrayItem is TJSonObject then
        begin
          // Verify that it is of type "function"
          if TJSonObject(ArrayItem).GetValue('type') <> nil then
          begin
            if TJSonObject(ArrayItem).GetValue('type').Value = 'function' then
            begin
              // Get the "function" object
              FunctionObj := TJSonObject(ArrayItem).GetValue('function') as TJSonObject;
              if FunctionObj <> nil then
              begin
                // Get the value of the "name" field
                NameValue := FunctionObj.GetValue('name');
                if NameValue <> nil then
                begin
                  FunctionName := NameValue.Value;
                  // Replace the MCP separator with --> for display
                  FunctionName := StringReplace(FunctionName, MCP_TOOL_SEP, '-->', [rfReplaceAll]);
                  Result.Add(FunctionName);
                end;
              end;
            end;
          end;
        end;
      end;

    finally
      JsonArray.Free;
    end;

  except
    on E: Exception do
    begin
      Result.Free;
      raise Exception.Create('Error processing JSON: ' + E.Message);
    end;
  end;
end;

{ function TAiFunctions.ExtractFunctionNames1: TStringList;
  var
  JsonObj: TJSonObject;
  ToolsArray: TJSonArray;
  ToolItem: TJSONValue;
  NameValue: TJSONValue;
  I: Integer;
  JsonString: string;
  begin
  Result := TStringList.Create;

  try
  JsonString := GetTools(TToolFormat.tfOpenAI);

  Result.Text := JSonString;
  Exit;


  // Parse the JSON
  JsonObj := TJSonObject.ParseJSONValue(JsonString) as TJSonObject;

  if JsonObj = nil then
  raise Exception.Create('Invalid JSON');

  try
  // Get the "tools" array
  ToolsArray := JsonObj.GetValue('tools') as TJSonArray;
  if ToolsArray <> nil then
  Begin
  // Iterate over each element of the array
  for I := 0 to ToolsArray.Count - 1 do
  begin
  ToolItem := ToolsArray.Items[I];
  if ToolItem is TJSonObject then
  begin
  // Get the value of the "name" field
  NameValue := TJSonObject(ToolItem).GetValue('name');
  if NameValue <> nil then
  Result.Add(NameValue.Value);
  end;
  end;
  End;

  finally
  JsonObj.Free;
  end;

  except
  on E: Exception do
  begin
  Result.Free;
  raise Exception.Create('Error processing JSON: ' + E.Message);
  end;
  end;
  end;
}

{ function TAiFunctions.GetTools(aToolFormat: TToolFormat): String;
  var
  MergedToolsObj: TJSonObject;
  LocalToolsArray, jResToolArray: TJSonArray;
  ClientItem: TMCPClientItem;
  SourceJson: TJSonObject;
  SourceJsonStr: string;
  JsonValue: TJSonValue;
  I: Integer;
  begin
  MergedToolsObj := nil;
  LocalToolsArray := nil;
  SourceJson := nil;
  try
  jResToolArray := Nil;
  // 1. Get the local functions
  LocalToolsArray := FFunctions.ToJSon;

  // 2. Create the final JSON object that will contain all tools
  MergedToolsObj := TJSonObject.Create;
  // Add the local tools to the new tools array.
  // Use Clone so MergedToolsObj owns the data.
  MergedToolsObj.AddPair('tools', TJSonObject(LocalToolsArray.Clone));

  // 3. Iterate over MCP clients and merge their tools

  if not(csDesigning in ComponentState) then
  Begin
  For I := 0 to FMCPClients.Count - 1 do
  Begin
  ClientItem := TMCPClientItem(FMCPClients.Items[I]);
  // ClientItem.Enabled := True;

  if ClientItem.Enabled then
  begin
  // Initialize the client if it has not been initialized already. This gets the tool list.
  if not ClientItem.MCPClient.Initialized then
  ClientItem.MCPClient.Initialize;

  // If the client is available (initialization was successful)...
  if ClientItem.MCPClient.Available then
  begin
  SourceJsonStr := ClientItem.MCPClient.Tools.Text;
  if not SourceJsonStr.IsEmpty then
  begin
  JsonValue := TJSonObject.ParseJSONValue(SourceJsonStr);
  if JsonValue is TJSonObject then
  begin
  SourceJson := TJSonObject(JsonValue);
  try
  // Use the helper function to merge the tools
  // Assume OpenAI format as a common standard for output

  // TJsonToolUtils.MergeToolLists(ClientItem.Name, SourceJson, MergedToolsObj, TToolFormat.tfOpenAI);
  TJsonToolUtils.MergeToolLists(ClientItem.Name, SourceJson, MergedToolsObj, aToolFormat);

  finally
  SourceJson.Free;
  SourceJson := nil;
  end;
  end
  else
  JsonValue.Free;
  end;
  end;
  end;
  End;
  End;

  // 4. Format the final JSON as a string

  Var
  JArr: TJSonArray;

  If MergedToolsObj.TryGetValue<TJSonArray>('tools', JArr) then
  jResToolArray := TJSonArray(JArr.Clone)
  Else
  jResToolArray := TJSonArray.Create;

  Try
  Result := jResToolArray.ToJSon;
  Finally
  jResToolArray.Free;
  End;

  finally
  FreeAndNil(MergedToolsObj);
  FreeAndNil(LocalToolsArray);
  // SourceJson is already freed inside the loop
  end;
  end;
}

function TAiFunctions.GetTools(aToolFormat: TToolFormat): String;
var
  LAllNormalizedTools: TList<TNormalizedTool>;
  FinalToolsObj: TJSonObject;
  LocalToolsObj: TJSonObject;
  ClientItem: TMCPClientItem;
  ClientToolsJson: TJSonObject;
  JsonValue: TJSONValue;
  I: Integer;
begin

  LAllNormalizedTools := TObjectList<TNormalizedTool>.Create(True);
  FinalToolsObj := nil;
  LocalToolsObj := nil;

  try
    // 1. NORMALIZE LOCAL FUNCTIONS
    // Convert the TJSonArray of local functions to a TJSonObject with the "tools" key
    LocalToolsObj := TJSonObject.Create;
    var LLocalTools := FFunctions.ToJSon;
    LocalToolsObj.AddPair('tools', LLocalTools);
    // Empty source = NO prefix: local functions travel to the provider with their
    // real name. The 'local_99_' prefix confused Claude in multi-turn
    // continuations (with the renamed tool_use in history, it re-executed the tool
    // instead of responding). Dispatch does not need it: DoCallFunction resolves names
    // without a separator as local functions, and still accepts legacy 'local_99_'.
    TJsonToolUtils.NormalizeToolsFromSource('', LocalToolsObj, LAllNormalizedTools);

    // 1b. AUTOMCP INTERNAL FUNCTIONS (ppm_search, ppm_install, call_mcp_tool)
    // Lazy init: if Active=True but the functions do not exist yet (e.g.: Active enabled
    // at runtime after Loaded), creates them now.
    if FAutoMCPConfig.Active and not (csDesigning in ComponentState) then
    begin
      if FAutoMCPFunctions.Count = 0 then
        CreateInternalPPMFunctions;
      var LAutoObj := TJSonObject.Create;
      try
        LAutoObj.AddPair('tools', FAutoMCPFunctions.ToJSon);
        // Same as local ones: no prefix (ppm_search/ppm_install/call_mcp_tool
        // are dispatched by clean name in DoCallFunction).
        TJsonToolUtils.NormalizeToolsFromSource('', LAutoObj, LAllNormalizedTools);
      finally
        LAutoObj.Free;
      end;
    end;

    // 2. NORMALIZE MCP CLIENT FUNCTIONS
    if not(csDesigning in ComponentState) then
    begin
      for I := 0 to FMCPClients.Count - 1 do
      begin
        ClientItem := TMCPClientItem(FMCPClients.Items[I]);
        if not ClientItem.Enabled then
          Continue;

        if not ClientItem.MCPClient.Initialized then
          ClientItem.MCPClient.Initialize;

        if ClientItem.MCPClient.Available then
        begin
          var
          SourceJsonStr := ClientItem.MCPClient.Tools.Text;
          if not SourceJsonStr.IsEmpty then
          begin
            JsonValue := TJSonObject.ParseJSONValue(SourceJsonStr);
            try
              if JsonValue is TJSonObject then
              begin
                ClientToolsJson := TJSonObject(JsonValue);
                TJsonToolUtils.NormalizeToolsFromSource(ClientItem.Name, ClientToolsJson, LAllNormalizedTools);
              end;
            finally
              JsonValue.Free;
            end;
          end;
        end;
      end;
    end;

    // 3. FORMAT THE COMPLETE MASTER LIST AT THE END
    FinalToolsObj := TJsonToolUtils.FormatToolList(LAllNormalizedTools, aToolFormat);

    // Extract the 'tools' array for the final result
    Var
      LResultArray: TJSonArray;
    if FinalToolsObj.TryGetValue<TJSonArray>('tools', LResultArray) then
      Result := LResultArray.ToJSon
    else
      Result := '[]';

  finally
    LAllNormalizedTools.Free; // Frees the list and all TNormalizedTool objects inside it
    FinalToolsObj.Free;
    LocalToolsObj.Free;
  end;
end;

// =============================================================================
// OVERLOAD 2: File Wrapper (Receives String)
// =============================================================================

function TAiFunctions.ImportClaudeMCPConfiguration(const AJsonFilePath: string): Integer;
var
  LFinalPath: string;
  LJsonContent: string;
  LRootObj: TJSonObject;
begin
  Result := 0;
  LFinalPath := AJsonFilePath;

  // If no path is specified, use the component's effective path
  if LFinalPath.IsEmpty then
    LFinalPath := GetEffectiveMCPConfigPath;

  // 2. Existence validation
  if not TFile.Exists(LFinalPath) then
  begin
    DoLog('ImportClaude: File not found at ' + LFinalPath);
    Exit;
  end;

  try
    // 3. Safe loading of content
    LJsonContent := TFile.ReadAllText(LFinalPath, TEncoding.UTF8);

    if LJsonContent.Trim.IsEmpty then
    begin
      DoLog('ImportClaude: The file is empty.');
      Exit;
    end;

    // 4. Parse and validate the JSON object
    var
    LJsonValue := TJSonObject.ParseJSONValue(LJsonContent);

    if Assigned(LJsonValue) and (LJsonValue is TJSonObject) then
    begin
      LRootObj := LJsonValue as TJSonObject;
      try
        DoLog('Importing MCP servers from: ' + LFinalPath);
        // CALL TO REFACTORED VERSION (the one handling StdIo and SSE)
        Result := ImportClaudeMCPConfiguration(LRootObj);
      finally
        LRootObj.Free;
      end;
    end
    else
    begin
      if Assigned(LJsonValue) then
        LJsonValue.Free;
      DoLog('ImportClaude: The content is not a valid JSON object.');
    end;

  except
    on E: Exception do
      DoLog('ImportClaude: Fatal error reading or parsing: ' + E.Message);
  end;
end;

procedure TAiFunctions.Loaded;
var
  I: Integer;
begin
  inherited;
  // Force a final property update once the entire FMX has loaded.
  // This corrects any mismatch caused by load order.
  if Assigned(FMCPClients) then
  begin
    for I := 0 to FMCPClients.Count - 1 do
    begin
      // Ensure the internal client exists and has the correct data
      if Assigned(FMCPClients[I]) then
        FMCPClients[I].UpdateClientProperties;
    end;
  end;

  // Automatic loading of MCP servers from a JSON file (Claude Desktop format)
  if FAutoMCPConfig.AutoLoad and not (csDesigning in ComponentState) then
  begin
    var LCount := ImportClaudeMCPConfiguration(FAutoMCPConfig.ConfigFile);
    if LCount > 0 then
      DoLog(Format('AutoLoad: %d MCP server(s) loaded from configuration.', [LCount]));
  end;

  // AutoMCP: internal functions are created lazily in GetTools/DoCallFunction.
  // InitAutoMCP can be called manually to force initialization at runtime.
end;

// =============================================================================
// OVERLOAD 1: Core logic (Receives TJSONObject)
// =============================================================================
{ function TAiFunctions.ImportClaudeMCPConfiguration(AConfig: TJSonObject): Integer;
  var
  McpServers, ServerObj, EnvObj: TJSonObject;
  ArgsArray: TJSonArray;
  ServerPair, EnvPair: TJSONPair;
  NewClient: TMCPClientStdIo;
  ArgsString, ArgValStr, ServerName: string;
  I: Integer;
  Val: TJSONValue;
  begin
  Result := 0;

  if not Assigned(AConfig) then
  begin
  DoLog('ImportClaude: JSON Configuration object is nil.');
  Exit;
  end;

  try
  // Look for the root "mcpServers" key
  if AConfig.TryGetValue<TJSonObject>('mcpServers', McpServers) then
  begin
  for ServerPair in McpServers do
  begin
  ServerName := ServerPair.JsonString.Value;

  // 1. Evitar duplicados
  if Assigned(FMCPClients.GetClientByName(ServerName)) then
  begin
  DoLog(Format('ImportClaude: Client "%s" already exists. Skipping.', [ServerName]));
  Continue;
  end;

  ServerObj := ServerPair.JsonValue as TJSonObject;
  if not Assigned(ServerObj) then
  Continue;

  // 2. Create the StdIo client (Owner = nil)
  NewClient := TMCPClientStdIo.Create(nil);
  try
  NewClient.Name := ServerName;

  // --- COMMAND ---
  if ServerObj.TryGetValue('command', Val) then
  NewClient.Params.Values['Command'] := Val.Value;

  // --- ARGS ---
  ArgsString := '';
  if ServerObj.TryGetValue<TJSonArray>('args', ArgsArray) then
  begin
  for I := 0 to ArgsArray.Count - 1 do
  begin
  ArgValStr := ArgsArray.Items[I].Value;
  // Handling spaces in arguments: wrap in quotes if necessary
  if (Pos(' ', ArgValStr) > 0) and (not ArgValStr.StartsWith('"')) then
  ArgValStr := '"' + ArgValStr + '"';

  if ArgsString.IsEmpty then
  ArgsString := ArgValStr
  else
  ArgsString := ArgsString + ' ' + ArgValStr;
  end;
  end;
  NewClient.Params.Values['Arguments'] := ArgsString;

  // --- ENV ---
  if ServerObj.TryGetValue<TJSonObject>('env', EnvObj) then
  begin
  for EnvPair in EnvObj do
  begin
  NewClient.EnvVars.Values[EnvPair.JsonString.Value] := EnvPair.JsonValue.Value;
  end;
  end;

  // Default root directory (optional)
  NewClient.Params.Values['RootDir'] := TPath.GetHomePath;

  // 3. Add to the central collection
  try
  AddMCPClient(NewClient);
  Inc(Result);
  DoLog(Format('ImportClaude: Imported server "%s".', [ServerName]));
  except
  on E: Exception do
  begin
  DoLog(Format('ImportClaude: Error adding "%s": %s', [ServerName, E.Message]));
  if NewClient.Owner = nil then
  NewClient.Free;
  end;
  end;

  except
  on E: Exception do
  begin
  DoLog('ImportClaude: Unexpected error processing server entry: ' + E.Message);
  if NewClient.Owner = nil then
  NewClient.Free;
  end;
  end;
  end;
  end
  else
  begin
  DoLog('ImportClaude: "mcpServers" key not found in JSON.');
  end;
  except
  on E: Exception do
  DoLog('ImportClaude: Error parsing configuration object: ' + E.Message);
  end;
  end;
}

function TAiFunctions.ImportClaudeMCPConfiguration(AConfig: TJSonObject): Integer;
var
  LMcpServers, LServerObj, LEnvObj: TJSonObject;
  LArgsArray: TJSonArray;
  LServerPair, LEnvPair: TJSONPair;
  LClientItem: TMCPClientItem;
  LServerName, LCommand, LUrl, LArgsString: string;
  I: Integer;
begin
  Result := 0;
  if not Assigned(AConfig) then
    Exit;

  // Try to find the root node
  if not AConfig.TryGetValue<TJSonObject>('mcpServers', LMcpServers) then
  begin
    DoLog('ImportClaude: Node "mcpServers" was not found.');
    Exit;
  end;

  for LServerPair in LMcpServers do
  begin
    LServerName := LServerPair.JsonString.Value;

    // 1. Evitar duplicados
    if Assigned(FMCPClients.GetClientByName(LServerName)) then
      Continue;

    LServerObj := LServerPair.JsonValue as TJSonObject;

    // 2. Create the Item in the collection (the Wrapper)
    LClientItem := FMCPClients.Add;
    LClientItem.Name := LServerName;

    // --- CASE A: Local Server (StdIo) ---
    if LServerObj.TryGetValue<string>('command', LCommand) then
    begin
      LClientItem.TransportType := tpStdIo;
      LClientItem.Params.Values['Command'] := LCommand;

      // Process Arguments
      if LServerObj.TryGetValue<TJSonArray>('args', LArgsArray) then
      begin
        LArgsString := '';
        for I := 0 to LArgsArray.Count - 1 do
        begin
          var
          LArg := LArgsArray.Items[I].Value;
          // If the argument has spaces and no quotes, wrap it
          if (Pos(' ', LArg) > 0) and (not LArg.StartsWith('"')) then
            LArg := '"' + LArg + '"';

          LArgsString := LArgsString + LArg + ' ';
        end;
        LClientItem.Params.Values['Arguments'] := LArgsString.Trim;
      end;

      // Default RootDir
      LClientItem.Params.Values['RootDir'] := TPath.GetHomePath;
    end
    // --- CASE B: Remote Server (URL / SSE) ---
    else if LServerObj.TryGetValue<string>('url', LUrl) then
    begin
      LClientItem.TransportType := tpSSE; // Standard for remote MCP
      LClientItem.Params.Values['URL'] := LUrl;
    end;

    // --- ENVIRONMENT VARIABLES (Common to both) ---
    if LServerObj.TryGetValue<TJSonObject>('env', LEnvObj) then
    begin
      for LEnvPair in LEnvObj do
      begin
        LClientItem.EnvVars.Values[LEnvPair.JsonString.Value] := LEnvPair.JsonValue.Value;
      end;
    end;

    // 3. FINALIZATION AND SYNCHRONIZATION (Crucial in your library)
    LClientItem.Enabled := True;

    // This transfers Params and EnvVars from the Item to the internal FMCPClient
    LClientItem.UpdateClientProperties;

    Inc(Result);
    DoLog(Format('ImportClaude: Server "%s" loaded successfully.', [LServerName]));
  end;
end;

function TAiFunctions.SetFunctionEnable(FunctionName: String; Enabled: Boolean): Boolean;
Var
  Item: TFunctionActionItem;
begin
  Result := False;
  Item := Functions.GetFunction(FunctionName);
  If Assigned(Item) then
  Begin
    Item.Enabled := Enabled;
    Result := True;
  End;
end;

function TAiFunctions.SetMCPClientEnable(Name: String; Enabled: Boolean): Boolean;
Var
  Item: TMCPClientItem;
begin
  Result := False;
  Item := Self.FMCPClients.GetClientByName(Name);
  If Assigned(Item) then
  Begin
    Item.Enabled := Enabled;
    Result := True;
  End;
end;

procedure TAiFunctions.SetOnMCPStreamMessage(const Value: TMCPStreamMessageEvent);
var
  I: Integer;
begin
  FOnMCPStreamMessage := Value;
  // Propagate to all current clients
  for I := 0 to FMCPClients.Count - 1 do
    if Assigned(FMCPClients[I].MCPClient) then
      FMCPClients[I].MCPClient.OnStreamMessage := Value;
end;

// ---------------------------------------------------------------------------
// PPM Integration — helpers privados a nivel de unidad
// ---------------------------------------------------------------------------

// Simple GET; returns the body as a string or '' if it fails.
function PPMHttpGetStr(const AUrl: String): String;
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
begin
  Result := '';
  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 15000;
    LClient.ResponseTimeout   := 15000;
    try
      LResponse := LClient.Get(AUrl);
      if LResponse.StatusCode = 200 then
        Result := LResponse.ContentAsString(TEncoding.UTF8);
    except
      // Network error: returns empty
    end;
  finally
    LClient.Free;
  end;
end;

// Downloads AUrl (following 3xx redirects) to ADestFile.
// Returns True if the download was successful and the file has content.
function PPMHttpDownload(const AUrl, ADestFile: String): Boolean;
var
  LClient: THTTPClient;
  LStream: TFileStream;
  LResponse: IHTTPResponse;
begin
  Result := False;
  LClient := THTTPClient.Create;
  try
    LClient.ConnectionTimeout := 15000;
    LClient.ResponseTimeout   := 120000;  { 2 min — .paipkg puede ser 5-10 MB }
    try
      LStream := TFileStream.Create(ADestFile, fmCreate);
      try
        LResponse := LClient.Get(AUrl, LStream);
        Result := (LResponse.StatusCode = 200) and (LStream.Size > 0);
      finally
        LStream.Free;
      end;
    except
      // Network or write error: returns False
    end;
  finally
    LClient.Free;
  end;
end;

// Resolves the version to use: if AVersion is not empty, returns it directly;
// if empty, queries /v1/packages/:name and returns the latest non-yanked version.
function PPMResolveVersion(const ARegistryUrl, AName, AVersion: String): String;
var
  LBody: String;
  LJson, LPackage, LVer: TJSONObject;
  LVersions: TJSONArray;
  LYankedVal: TJSONValue;
  I: Integer;
begin
  Result := AVersion;
  if Result <> '' then
    Exit;

  LBody := PPMHttpGetStr(ARegistryUrl + '/v1/packages/' + AName);
  if LBody = '' then
    Exit;

  LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
  if not Assigned(LJson) then
    Exit;
  try
    if LJson.TryGetValue<TJSONObject>('package', LPackage) and
       LPackage.TryGetValue<TJSONArray>('versions', LVersions) then
    begin
      for I := 0 to LVersions.Count - 1 do
      begin
        LVer := LVersions.Items[I] as TJSONObject;
        LYankedVal := LVer.FindValue('yanked');
        if not (Assigned(LYankedVal) and (LYankedVal is TJSONTrue)) then
        begin
          LVer.TryGetValue<String>('version', Result);
          Break;
        end;
      end;
    end;
  finally
    LJson.Free;
  end;
end;

// Extracts the contents of a .paipkg (ZIP) to ADestDir and returns the path
// of the entrypoint declared in pai.package [mcp] entrypoint=...
// If there is no manifest, tries to find the first .exe (Windows) or binary
// without extension (Linux) in the ZIP root.
// Returns '' if extraction failed or the entrypoint was not found.
function PPMExtractBinary(const APaipkgPath, ADestDir: String): String;
var
  LZip       : TZipFile;
  I          : Integer;
  LFileName  : String;
  LDestPath  : String;
  LBytes     : TBytes;
  LStream    : TFileStream;
  LManifest  : String;
  LEntrypoint: String;
  LIni       : TMemIniFile;
begin
  Result := '';

  if not TDirectory.Exists(ADestDir) then
    TDirectory.CreateDirectory(ADestDir);

  LZip := TZipFile.Create;
  try
    LZip.Open(APaipkgPath, zmRead);
    try
      // Extract all files to the destination directory preserving structure
      for I := 0 to LZip.FileCount - 1 do
      begin
        LFileName := LZip.FileName[I];
        // Ignore directory entries
        if LFileName.EndsWith('/') or LFileName.EndsWith('\') then Continue;

        // Normalize separators and build destination path
        LFileName := StringReplace(LFileName, '/', PathDelim, [rfReplaceAll]);
        LFileName := StringReplace(LFileName, '\', PathDelim, [rfReplaceAll]);
        LDestPath := TPath.Combine(ADestDir, LFileName);

        // Create intermediate subdirectories if needed
        var LDestDir := TPath.GetDirectoryName(LDestPath);
        if not TDirectory.Exists(LDestDir) then
          TDirectory.CreateDirectory(LDestDir);

        LZip.Read(LZip.FileName[I], LBytes);
        if Length(LBytes) = 0 then Continue;

        try
          LStream := TFileStream.Create(LDestPath, fmCreate);
          try
            LStream.WriteBuffer(LBytes[0], Length(LBytes));
          finally
            LStream.Free;
          end;
        except
          on E: EFCreateError do
          begin
            // File in use (MCP process running) — skip and continue.
            // If the entrypoint already exists we will use it in the manifest step.
          end;
        end;
      end;
    finally
      LZip.Close;
    end;
  finally
    LZip.Free;
  end;

  // Read entrypoint from the pai.package manifest
  LManifest := TPath.Combine(ADestDir, 'pai.package');
  LEntrypoint := '';
  if TFile.Exists(LManifest) then
  begin
    LIni := TMemIniFile.Create(LManifest);
    try
{$IFDEF MSWINDOWS}
      LEntrypoint := LIni.ReadString('mcp', 'entrypoint', '');
{$ELSE}
      // On Linux prefer entrypoint_lin64; fallback to entrypoint
      LEntrypoint := LIni.ReadString('mcp', 'entrypoint_lin64', '');
      if LEntrypoint = '' then
        LEntrypoint := LIni.ReadString('mcp', 'entrypoint', '');
{$ENDIF}
    finally
      LIni.Free;
    end;
  end;

  if LEntrypoint <> '' then
  begin
    LDestPath := TPath.Combine(ADestDir, LEntrypoint);
    if TFile.Exists(LDestPath) then
    begin
{$IFDEF POSIX}
      TFile.SetAttributes(LDestPath,
        TFile.GetAttributes(LDestPath) + [TFileAttribute.faOwnerExecute]);
{$ENDIF}
      Result := LDestPath;
      Exit;
    end;
  end;

  // Fallback: first .exe on Windows, or first file without extension on Linux
  // Recursive search to support packages with bin/win64/ structure
  if TDirectory.Exists(ADestDir) then
  begin
{$IFDEF MSWINDOWS}
    var LFiles := TDirectory.GetFiles(ADestDir, '*.exe', TSearchOption.soAllDirectories);
{$ELSE}
    var LFiles := TDirectory.GetFiles(ADestDir, '*', TSearchOption.soAllDirectories);
{$ENDIF}
    for var LF in LFiles do
    begin
{$IFNDEF MSWINDOWS}
      if TPath.GetExtension(LF) <> '' then Continue;
{$ENDIF}
      if SameText(TPath.GetFileName(LF), 'pai.package') then Continue;
{$IFDEF POSIX}
      TFile.SetAttributes(LF,
        TFile.GetAttributes(LF) + [TFileAttribute.faOwnerExecute]);
{$ENDIF}
      Result := LF;
      Break;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// AutoMCP helpers
// ---------------------------------------------------------------------------

procedure TAiFunctions.OnAutoMCPActiveChanged(Sender: TObject);
// Called when AutoMCPConfig.Active changes at runtime.
// Active=True  → creates the functions if they do not exist yet (lazy).
// Active=False → clears FAutoMCPFunctions for a clean state when reactivated.
begin
  if csDesigning in ComponentState then Exit;
  if FAutoMCPConfig.Active then
  begin
    if FAutoMCPFunctions.Count = 0 then
      CreateInternalPPMFunctions;
    DoLog('[AutoMCP] Activated. Functions: ppm_search, ppm_install, call_mcp_tool.');
  end
  else
  begin
    FAutoMCPFunctions.Clear;
    DoLog('[AutoMCP] Deactivated. Internal functions removed.');
  end;
end;

procedure TAiFunctions.InitAutoMCP;
// Forces creation of the 3 internal PPM functions at runtime.
// Normally it is NOT necessary to call it — the functions are created lazily
// in the first GetTools() or DoCallFunction() when Active=True.
// Useful if the developer needs the functions to exist before the first chat
// (e.g.: to show the system prompt with the functions already listed).
begin
  if csDesigning in ComponentState then Exit;
  if not FAutoMCPConfig.Active then Exit;
  if FAutoMCPFunctions.Count > 0 then Exit; // already initialized

  CreateInternalPPMFunctions;
  DoLog('[AutoMCP] Initialized manually. Functions: ppm_search, ppm_install, call_mcp_tool.');
end;

procedure TAiFunctions.CreateInternalPPMFunctions;
var
  LFn: TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  FAutoMCPFunctions.Clear;

  // --- ppm_search ---
  LFn := TFunctionActionItem(FAutoMCPFunctions.Add);
  LFn.FunctionName := 'ppm_search';
  LFn.Description.Text :=
    'Search for MCP tools in the PPM registry (registry.cimamaker.com). ' +
    'Returns a list of available tools matching the query with their names, ' +
    'descriptions and available functions. Call this before ppm_install.';
  LFn.Enabled := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'query';
  LParam.Description.Text := 'Search keywords (e.g.: github, postgres, slack, kubernetes, filesystem)';
  LParam.ParamType := ptString;
  LParam.Required := True;

  // --- ppm_install ---
  LFn := TFunctionActionItem(FAutoMCPFunctions.Add);
  LFn.FunctionName := 'ppm_install';
  LFn.Description.Text :=
    'Download and install an MCP tool from the PPM registry. ' +
    'After installation the tool is immediately ready to use with call_mcp_tool. ' +
    'Call this autonomously when you need a tool — do not ask the user for confirmation. ' +
    'Use force=true to force reinstall/update even if already installed.';
  LFn.Enabled := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'tool_name';
  LParam.Description.Text := 'Exact PPM package name (e.g.: mcp-github, mcp-postgres, mcp-slack)';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'force';
  LParam.Description.Text := 'Set to true to force reinstall/update even if the tool is already installed';
  LParam.ParamType := ptBoolean;
  LParam.Required := False;

  // --- call_mcp_tool ---
  LFn := TFunctionActionItem(FAutoMCPFunctions.Add);
  LFn.FunctionName := 'call_mcp_tool';
  LFn.Description.Text :=
    'Call a specific function on an installed MCP tool. ' +
    'Use ppm_search to discover tools and ppm_install to install them first if needed. ' +
    'The available function names are returned by ppm_install.';
  LFn.Enabled := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'tool_name';
  LParam.Description.Text := 'Name of the installed MCP tool (e.g.: mcp-github)';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'function_name';
  LParam.Description.Text := 'Name of the function to call on the tool (from ppm_install result)';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name := 'arguments';
  LParam.Description.Text := 'JSON string with the function arguments (e.g.: {"query":"pascal","limit":10})';
  LParam.ParamType := ptString;
  LParam.Required := True;
end;

procedure TAiFunctions.InternalAutoMCP_PpmSearch(ToolCall: TAiToolsFunction);
var
  LQuery: string;
  LResult: TJSONObject;
  LTools: TJSONArray;
  LSb: TStringBuilder;
begin
  LQuery := '';
  var LArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgs) then
  try
    LArgs.TryGetValue<string>('query', LQuery);
    LQuery := Trim(LQuery);
  finally
    LArgs.Free;
  end;

  DoLog('[AutoMCP] ppm_search: "' + LQuery + '"');
  DoStatusUpdate('Searching for "' + LQuery + '" in the PPM registry...');

  LResult := SearchPPMMCP(LQuery, 1, 20, FAutoMCPConfig.RegistryUrl);
  if not Assigned(LResult) then
  begin
    ToolCall.Response := 'Could not connect to the PPM registry. Check your Internet connection.';
    Exit;
  end;

  LSb := TStringBuilder.Create;
  try
    if LResult.TryGetValue<TJSONArray>('tools', LTools) and (LTools.Count > 0) then
    begin
      var LShown   := 0;
      var LFiltered := 0;
      for var I := 0 to LTools.Count - 1 do
      begin
        var LTool := LTools.Items[I] as TJSONObject;
        var LName, LDesc, LVer: string;
        LTool.TryGetValue<string>('name', LName);
        LTool.TryGetValue<string>('description', LDesc);
        LTool.TryGetValue<string>('version', LVer);
        // Apply Allowed/Blocked policy before showing to the LLM
        if not IsAutoMCPAllowed(LName) then
        begin
          Inc(LFiltered);
          Continue;
        end;
        LSb.AppendLine(Format('• %s (v%s): %s', [LName, LVer, LDesc]));
        Inc(LShown);
      end;

      if LShown > 0 then
      begin
        // Insert header at the beginning of the result
        var LHeader := Format('Found %d tools for "%s":', [LShown, LQuery]);
        if LFiltered > 0 then
          LHeader := LHeader + Format(' (%d blocked by policy)', [LFiltered]);
        ToolCall.Response := LHeader + sLineBreak + LSb.ToString +
          sLineBreak + 'To use a tool: call ppm_install("<name>"), then call_mcp_tool.';
      end
      else if LFiltered > 0 then
        ToolCall.Response := Format(
          'Found %d tools for "%s" but they are all blocked by the AutoMCP policy.',
          [LFiltered, LQuery])
      else
        ToolCall.Response := Format('No tools were found for "%s" in the PPM registry.', [LQuery]);
    end
    else
      ToolCall.Response := Format('No tools were found for "%s" in the PPM registry.', [LQuery]);
  finally
    LSb.Free;
    LResult.Free;
  end;
end;

procedure TAiFunctions.InternalAutoMCP_PpmInstall(ToolCall: TAiToolsFunction);
var
  LToolName: string;
  LForce: Boolean;
  LItem: TMCPClientItem;
  LFuncNames: TStringList;
begin
  LToolName := '';
  LForce    := False;
  var LArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgs) then
  try
    LArgs.TryGetValue<string>('tool_name', LToolName);
    LArgs.TryGetValue<Boolean>('force', LForce);
    LToolName := Trim(LToolName);
  finally
    LArgs.Free;
  end;

  if LToolName = '' then
  begin
    ToolCall.Response := '{"ok":false,"error":"tool_name parameter is required"}';
    Exit;
  end;

  // Check whitelist/blacklist policy
  if not IsAutoMCPAllowed(LToolName) then
  begin
    ToolCall.Response := Format(
      '{"ok":false,"error":"Installation of ''%s'' is not allowed by AutoMCP policy"}',
      [LToolName]);
    Exit;
  end;

  DoLog('[AutoMCP] ppm_install: "' + LToolName + '"' + IfThen(LForce, ' (force)', ''));
  DoStatusUpdate('Installing "' + LToolName + '" from PPM...');

  // Record the attempt BEFORE installing it to avoid infinite loops in case of error
  if FInstalledPackages.IndexOf(LowerCase(LToolName)) < 0 then
    FInstalledPackages.Add(LowerCase(LToolName));

  // If it is already registered: reuse it unless force=true
  LItem := FMCPClients.GetClientByName(LToolName);
  if Assigned(LItem) and not LForce then
    DoLog('[AutoMCP] "' + LToolName + '" already installed, reusing.')
  else
  begin
    // force=true or not installed: download/reinstall from PPM
    if Assigned(LItem) and LForce then
    begin
      DoLog('[AutoMCP] "' + LToolName + '" force reinstall — stopping previous process.');
      LItem.MCPClient.Disconnect;
    end;
    LItem := InstallMCPFromPPM(LToolName, '', FAutoMCPConfig.WorkingDir, FAutoMCPConfig.RegistryUrl);
  end;

  if not Assigned(LItem) then
  begin
    ToolCall.Response := Format(
      '{"ok":false,"error":"Could not install ''%s''. Check the package name in PPM and the Internet connection. Do not try to install this package again in this session."}',
      [LToolName]);
    Exit;
  end;

  // Initialize the MCP process
  if not LItem.MCPClient.Initialized then
    LItem.MCPClient.Initialize;

  // Disabled in GetTools: the LLM accesses it only via call_mcp_tool (avoids race conditions)
  LItem.Enabled := False;

  // Collect available functions to inform the LLM
  LFuncNames := TStringList.Create;
  try
    var LToolsJson := TJSONObject.ParseJSONValue(LItem.MCPClient.Tools.Text);
    if Assigned(LToolsJson) then
    try
      var LToolsArr: TJSONArray;
      if LToolsJson.TryGetValue<TJSONArray>('tools', LToolsArr) then
        for var LT in LToolsArr do
        begin
          var LFName: string;
          if (LT is TJSONObject) and TJSONObject(LT).TryGetValue<string>('name', LFName) then
            LFuncNames.Add(LFName);
        end;
    finally
      LToolsJson.Free;
    end;

    var LFuncList := '';
    if LFuncNames.Count > 0 then
      LFuncList := LFuncNames.CommaText;

    if LFuncList <> '' then
      ToolCall.Response := Format(
        '{"ok":true,"message":"''%s'' ready. REQUIRED ACTION: call NOW call_mcp_tool with tool_name=''%s'' and function_name=one of [%s] with the original arguments. Do NOT call ppm_search."}',
        [LToolName, LToolName, LFuncList])
    else
      ToolCall.Response := Format(
        '{"ok":true,"message":"''%s'' started. Call call_mcp_tool with tool_name=''%s'' and the original arguments. Do NOT call ppm_search."}',
        [LToolName, LToolName]);
  finally
    LFuncNames.Free;
  end;

  DoLog('[AutoMCP] "' + LToolName + '" ready at ' + LItem.Params.Values['Command']);
end;

procedure TAiFunctions.InternalAutoMCP_CallMcpTool(ToolCall: TAiToolsFunction);
var
  LToolName, LFuncName, LArgStr: string;
  LClientItem: TMCPClientItem;
  LArgsJson, LResult: TJSONObject;
  LExtractedMedia: TObjectList<TAiMediaFile>;
  MF: TAiMediaFile;
begin
  LToolName := '';
  LFuncName := '';
  LArgStr := '{}';
  var LArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgs) then
  try
    LArgs.TryGetValue<string>('tool_name', LToolName);
    LArgs.TryGetValue<string>('function_name', LFuncName);
    LArgs.TryGetValue<string>('arguments', LArgStr);
    LToolName := Trim(LToolName);
    LFuncName := Trim(LFuncName);
    LArgStr   := Trim(LArgStr);
    if LArgStr = '' then LArgStr := '{}';
  finally
    LArgs.Free;
  end;

  // Normalize LFuncName: the LLM may send the combined name "server_99_func"
  // (result of normalization in GetTools). Extract the part after the last MCP_TOOL_SEP.
  if Pos(MCP_TOOL_SEP, LFuncName) > 0 then
  begin
    var LSepIdx := Pos(MCP_TOOL_SEP, LFuncName);
    while True do
    begin
      var LNext := PosEx(MCP_TOOL_SEP, LFuncName, LSepIdx + 1);
      if LNext = 0 then Break;
      LSepIdx := LNext;
    end;
    LFuncName := Copy(LFuncName, LSepIdx + Length(MCP_TOOL_SEP), MaxInt);
  end;

  DoLog(Format('[AutoMCP] call_mcp_tool: %s → %s', [LToolName, LFuncName]));
  DoStatusUpdate(Format('Executing %s.%s...', [LToolName, LFuncName]));

  LClientItem := FMCPClients.GetClientByName(LToolName);
  if not Assigned(LClientItem) then
  begin
    ToolCall.Response := Format(
      '{"error":"Tool ''%s'' is not installed. Use ppm_install first."}',
      [LToolName]);
    Exit;
  end;

  if not LClientItem.MCPClient.Initialized then
    LClientItem.MCPClient.Initialize;

  if not LClientItem.MCPClient.Available then
  begin
    ToolCall.Response := Format(
      '{"error":"MCP server ''%s'' is not available. It may require reinstallation."}',
      [LToolName]);
    Exit;
  end;

  // Resolve the exact tool name on the server (dash vs underscore).
  // If the name does not match any known function, return an error with the
  // list of valid names so the LLM can use them directly.
  if LFuncName <> '' then
  begin
    var LFuncFound := False;
    var LValidFuncs := TStringList.Create;
    try
      var LToolsRoot := TJSONObject.ParseJSONValue(LClientItem.MCPClient.Tools.Text) as TJSONObject;
      if Assigned(LToolsRoot) then
      try
        var LToolsArr: TJSONArray;
        if LToolsRoot.TryGetValue<TJSONArray>('tools', LToolsArr) then
          for var LT in LToolsArr do
            if LT is TJSONObject then
            begin
              var LActualName: string;
              if TJSONObject(LT).TryGetValue<string>('name', LActualName) then
              begin
                LValidFuncs.Add(LActualName);
                var LNormActual := StringReplace(LActualName, '-', '_', [rfReplaceAll]);
                var LNormFunc   := StringReplace(LFuncName,   '-', '_', [rfReplaceAll]);
                if SameText(LNormActual, LNormFunc) then
                begin
                  LFuncName := LActualName; // exact name that the server recognizes
                  LFuncFound := True;
                end;
              end;
            end;
      finally
        LToolsRoot.Free;
      end;
      // If the name was not found and we have the list, return an error with valid names
      if not LFuncFound and (LValidFuncs.Count > 0) then
      begin
        ToolCall.Response := Format(
          '{"error":"Function ''%s'' does not exist in ''%s''. Valid names: [%s]. Use one of these exactly."}',
          [LFuncName, LToolName, LValidFuncs.CommaText]);
        Exit;
      end;
    finally
      LValidFuncs.Free;
    end;
  end;

  // Serialize concurrent calls to the same client
  FAutoMCPLock.Enter;
  try
    LArgsJson := TJSONObject.ParseJSONValue(LArgStr) as TJSONObject;
    if not Assigned(LArgsJson) then
      LArgsJson := TJSONObject.Create; // fallback: empty object

    LExtractedMedia := TObjectList<TAiMediaFile>.Create;
    try
      LResult := LClientItem.MCPClient.CallTool(LFuncName, LArgsJson, LExtractedMedia);
      try
        if Assigned(LResult) then
          ToolCall.Response := LResult.ToJson
        else
          ToolCall.Response := Format(
            '{"error":"MCP server ''%s'' did not respond to the call ''+LFuncName+''"}',
            [LToolName]);

        // Propagate extracted media files to the ToolCall (images, audio, etc.)
        for MF in LExtractedMedia do
        begin
          ToolCall.MediaFiles.Add(MF);
          if Assigned(ToolCall.ResMsg) then
          begin
            var LClone := TAiMediaFile.Create;
            LClone.LoadFromBase64(MF.FileName, MF.Base64);
            TAiChatMessage(ToolCall.ResMsg).AddMediaFile(LClone);
          end;
        end;
        if LExtractedMedia.Count > 0 then
          LExtractedMedia.OwnsObjects := False;
      finally
        LResult.Free;
      end;
    finally
      LExtractedMedia.Free;
    end;
  finally
    FAutoMCPLock.Leave;
  end;
end;

function TAiFunctions.GetAutoMCPSystemPrompt: String;
var
  LSb: TStringBuilder;
  I: Integer;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.AppendLine(
      'You have access to the PPM registry (PascalAI Package Manager) with more than 150 ' +
      'MCP tools covering GitHub, PostgreSQL, Slack, Jira, Stripe, DuckDB, ' +
      'Kubernetes, AWS S3, Azure, Kafka, GraphQL, and many more.');
    LSb.AppendLine;
    LSb.AppendLine('When the user asks you for something that requires access to external services, ' +
      'act AUTONOMOUSLY following this flow without asking for permission:');
    LSb.AppendLine('  1. Call ppm_search with keywords to find the appropriate tool.');
    LSb.AppendLine('  2. Call ppm_install with the exact package name to install it.');
    LSb.AppendLine('  3. Call call_mcp_tool with the tool name, function, and JSON arguments.');
    LSb.AppendLine;
    LSb.AppendLine('Conventions:');
    LSb.AppendLine('- Package names follow the pattern mcp-<service> (e.g.: mcp-github, mcp-postgres).');
    LSb.AppendLine('- Arguments for call_mcp_tool must be valid JSON as a string.');
    LSb.AppendLine('- Respond in the same language as the user.');
    LSb.AppendLine('- For audio/TTS tools: always request WAV format if the tool supports it (parameter format="wav" or similar). Only use MP3 or other formats if WAV is not available.');
    LSb.AppendLine;
    LSb.AppendLine('CRITICAL EXECUTION RULES (mandatory):');
    LSb.AppendLine('- Execute tools SEQUENTIALLY, one at a time. Always wait for the call_mcp_tool result before calling any other tool.');
    LSb.AppendLine('- If you already have an ACTIVE tool that can solve the task, use it DIRECTLY. Do NOT call ppm_search or ppm_install in parallel while call_mcp_tool is executing.');
    LSb.AppendLine('- NEVER call ppm_search after call_mcp_tool executed the operation (successful or with error). ppm_search only serves to discover new tools, not to retry.');
    LSb.AppendLine('- If call_mcp_tool returns a network, authentication, credential, or permission error: report the error directly to the user. Do NOT look for alternative tools.');
    LSb.AppendLine('- If call_mcp_tool returns "function not found": use the valid names indicated by the error and retry ONCE. If it still fails, report to the user.');

    // Classify enabled clients: active (process running) vs registered (process not started)
    var LHasActive := False;
    var LHasRegistered := False;
    for I := 0 to FMCPClients.Count - 1 do
      if FMCPClients[I].Enabled then
      begin
        if FMCPClients[I].MCPClient.Available then
          LHasActive := True
        else
          LHasRegistered := True;
      end;

    // Active servers: skip ppm_search and ppm_install; include the exact list of tools with parameters
    if LHasActive then
    begin
      LSb.AppendLine;
      LSb.AppendLine('ACTIVE MCP TOOLS (process already running — skip ppm_search and ppm_install, go directly to step 3):');
      LSb.AppendLine('IMPORTANT: use EXCLUSIVELY the function names and parameters indicated here. Do not invent names.');
      for I := 0 to FMCPClients.Count - 1 do
        if FMCPClients[I].Enabled and FMCPClients[I].MCPClient.Available then
        begin
          // If the tools cache is empty (server loaded from config without Initialize),
          // call Initialize now to populate the cache before building the prompt
          if FMCPClients[I].MCPClient.Tools.Text.IsEmpty then
            FMCPClients[I].MCPClient.Initialize;
          var LToolsJson := FMCPClients[I].MCPClient.Tools.Text;
          var LJObj := TJSONObject.ParseJSONValue(LToolsJson);
          if Assigned(LJObj) then
          try
            var LJTools: TJSONValue;
            if LJObj.TryGetValue('tools', LJTools) and (LJTools is TJSONArray) then
            begin
              var LArr := TJSONArray(LJTools);
              for var J := 0 to LArr.Count - 1 do
              begin
                var LTool := LArr.Items[J];
                if LTool is TJSONObject then
                begin
                  var LName: string;
                  if TJSONObject(LTool).TryGetValue<string>('name', LName) then
                  begin
                    LSb.Append('  ' + FMCPClients[I].Name + ' / ' + LName);
                    // Extract parameters from inputSchema
                    var LSchema: TJSONObject;
                    if TJSONObject(LTool).TryGetValue<TJSONObject>('inputSchema', LSchema) then
                    begin
                      var LProps: TJSONObject;
                      var LRequired: TJSONArray;
                      var LReqSet := TStringList.Create;
                      try
                        if LSchema.TryGetValue<TJSONArray>('required', LRequired) then
                          for var R in LRequired do
                            LReqSet.Add(R.Value);
                        if LSchema.TryGetValue<TJSONObject>('properties', LProps) then
                        begin
                          var LParamStr := '';
                          for var P in LProps do
                          begin
                            var LPName := P.JsonString.Value;
                            var LOptional := LReqSet.IndexOf(LPName) < 0;
                            if LParamStr <> '' then LParamStr := LParamStr + ', ';
                            if LOptional then
                              LParamStr := LParamStr + LPName + '?'
                            else
                              LParamStr := LParamStr + LPName;
                          end;
                          if LParamStr <> '' then
                            LSb.Append('(' + LParamStr + ')');
                        end;
                      finally
                        LReqSet.Free;
                      end;
                    end;
                    LSb.AppendLine;
                  end;
                end;
              end;
              LSb.AppendLine;
            end
            else
              LSb.AppendLine('- ' + FMCPClients[I].Name);
          finally
            LJObj.Free;
          end
          else
            LSb.AppendLine('- ' + FMCPClients[I].Name);
        end;
    end;

    // Registered servers but process not yet started: skip ppm_search, call ppm_install to start
    if LHasRegistered then
    begin
      LSb.AppendLine;
      LSb.AppendLine('REGISTERED MCP TOOLS (binary already installed — skip ppm_search, call ppm_install to start the process, then call_mcp_tool):');
      for I := 0 to FMCPClients.Count - 1 do
        if FMCPClients[I].Enabled and not FMCPClients[I].MCPClient.Available then
          LSb.AppendLine('- ' + FMCPClients[I].Name);
    end;

    Result := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

function TAiFunctions.IsAutoMCPAllowed(const APkgName: string): Boolean;
// Evaluates whether a package can be installed according to the AutoMCP policy.
// Order: OnAutoMCPRequest → Whitelist (if not empty) → Blacklist → allow.
var
  LAllow: Boolean;
begin
  LAllow := True;

  // 1. Dynamic callback (highest priority)
  if Assigned(FOnAutoMCPRequest) then
  begin
    FOnAutoMCPRequest(Self, APkgName, LAllow);
    Result := LAllow;
    Exit;
  end;

  // 2. Whitelist: if it has entries, only those packages are allowed
  if FAutoMCPConfig.FAllowed.Count > 0 then
  begin
    Result := FAutoMCPConfig.FAllowed.IndexOf(APkgName) >= 0;
    Exit;
  end;

  // 3. Blacklist: packages that are always blocked
  if FAutoMCPConfig.FBlocked.IndexOf(APkgName) >= 0 then
  begin
    Result := False;
    Exit;
  end;

  Result := True;
end;

procedure TAiFunctions.SetAutoMCPConfig(const Value: TAutoMCPConfig);
begin
  FAutoMCPConfig.Assign(Value);
end;

// ---------------------------------------------------------------------------
// TAutoMCPConfig
// ---------------------------------------------------------------------------

constructor TAutoMCPConfig.Create;
begin
  inherited Create;
  FActive := False;
  FRegistryUrl := 'https://registry.cimamaker.com';
  FAllowed := TStringList.Create;
  FBlocked := TStringList.Create;
end;

destructor TAutoMCPConfig.Destroy;
begin
  FAllowed.Free;
  FBlocked.Free;
  inherited;
end;

procedure TAutoMCPConfig.Assign(Source: TPersistent);
var
  Src: TAutoMCPConfig;
begin
  if Source is TAutoMCPConfig then
  begin
    Src := TAutoMCPConfig(Source);
    FActive      := Src.FActive;
    FRegistryUrl := Src.FRegistryUrl;
    FWorkingDir  := Src.FWorkingDir;
    FAllowed.Assign(Src.FAllowed);
    FBlocked.Assign(Src.FBlocked);
    FConfigFile  := Src.FConfigFile;
    FAutoLoad    := Src.FAutoLoad;
  end
  else
    inherited Assign(Source);
end;

function TAutoMCPConfig.GetAllowed: TStrings;
begin
  Result := FAllowed;
end;

function TAutoMCPConfig.GetBlocked: TStrings;
begin
  Result := FBlocked;
end;

procedure TAutoMCPConfig.SetActive(const Value: Boolean);
begin
  if FActive = Value then Exit;
  FActive := Value;
  // Notify TAiFunctions so it creates or clears the internal functions
  if Assigned(FOnActiveChanged) then
    FOnActiveChanged(Self);
end;

procedure TAutoMCPConfig.SetAllowed(const Value: TStrings);
begin
  FAllowed.Assign(Value);
end;

procedure TAutoMCPConfig.SetBlocked(const Value: TStrings);
begin
  FBlocked.Assign(Value);
end;

// ---------------------------------------------------------------------------
// Config file helpers
// ---------------------------------------------------------------------------

function TAiFunctions.GetEffectiveMCPConfigPath: String;
begin
  if FAutoMCPConfig.ConfigFile <> '' then
    Result := FAutoMCPConfig.ConfigFile
  else
    Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'mcp_servers.json');
end;

function TAiFunctions.SaveMCPConfiguration(const AFilePath: string): Boolean;

  // Splits an argument line respecting double quotes.
  // Ex: '-y "path with spaces" --flag' → ['-y', 'path with spaces', '--flag']
  function SplitArgs(const AArgs: string): TArray<string>;
  var
    LList: TList<string>;
    I: Integer;
    LToken: string;
    LInQuote: Boolean;
    C: Char;
  begin
    LList := TList<string>.Create;
    try
      LToken   := '';
      LInQuote := False;
      for I := 1 to Length(AArgs) do
      begin
        C := AArgs[I];
        if C = '"' then
          LInQuote := not LInQuote
        else if (C = ' ') and not LInQuote then
        begin
          if LToken <> '' then
          begin
            LList.Add(LToken);
            LToken := '';
          end;
        end
        else
          LToken := LToken + C;
      end;
      if LToken <> '' then
        LList.Add(LToken);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;

var
  LPath: String;
  LRoot, LServers, LServerObj, LEnvObj: TJSONObject;
  LArgsArray: TJSONArray;
  LItem: TMCPClientItem;
  LArgs: TArray<string>;
  LCmd, LUrl, LArgsStr, LDir: string;
  I, J: Integer;
begin
  Result := False;
  LPath := AFilePath;
  if LPath = '' then
    LPath := GetEffectiveMCPConfigPath;

  LRoot := TJSONObject.Create;
  try
    LServers := TJSONObject.Create;
    LRoot.AddPair('mcpServers', LServers);

    for I := 0 to FMCPClients.Count - 1 do
    begin
      LItem := FMCPClients[I];

      LServerObj := TJSONObject.Create;

      case LItem.TransportType of
        tpStdIo:
        begin
          LCmd := LItem.Params.Values['Command'];
          LServerObj.AddPair('command', LCmd);

          LArgsStr := LItem.Params.Values['Arguments'];
          if LArgsStr <> '' then
          begin
            LArgsArray := TJSONArray.Create;
            LArgs := SplitArgs(LArgsStr);
            for J := 0 to High(LArgs) do
              LArgsArray.Add(LArgs[J]);
            LServerObj.AddPair('args', LArgsArray);
          end;

          LDir := LItem.Params.Values['RootDir'];
          if LDir <> '' then
            LServerObj.AddPair('rootDir', LDir);
        end;

        tpSSE, tpHttp:
        begin
          LUrl := LItem.Params.Values['URL'];
          LServerObj.AddPair('url', LUrl);
        end;
      end;

      // Variables de entorno
      if LItem.EnvVars.Count > 0 then
      begin
        LEnvObj := TJSONObject.Create;
        for J := 0 to LItem.EnvVars.Count - 1 do
          LEnvObj.AddPair(LItem.EnvVars.Names[J], LItem.EnvVars.ValueFromIndex[J]);
        LServerObj.AddPair('env', LEnvObj);
      end;

      LServers.AddPair(LItem.Name, LServerObj);
    end;

    // Create directory if it does not exist
    var LDir2 := TPath.GetDirectoryName(LPath);
    if (LDir2 <> '') and not TDirectory.Exists(LDir2) then
      TDirectory.CreateDirectory(LDir2);

    TFile.WriteAllText(LPath, LRoot.Format(2), TEncoding.UTF8);
    Result := True;
    DoLog('SaveMCPConfig: ' + IntToStr(FMCPClients.Count) + ' server(s) saved to ' + LPath);
  except
    on E: Exception do
      DoLog('SaveMCPConfig: Error saving: ' + E.Message);
  end;
  LRoot.Free;
end;

// ---------------------------------------------------------------------------

function TAiFunctions.SearchPPMMCP(const AQuery: String; APage, APerPage: Integer;
  const ARegistryUrl: String): TJSONObject;
var
  LUrl, LBody: String;
begin
  Result := nil;
  LUrl := Format('%s/v1/mcp/discover?q=%s&page=%d&per_page=%d',
    [ARegistryUrl,
     TNetEncoding.URL.Encode(AQuery),
     APage,
     APerPage]);
  LBody := PPMHttpGetStr(LUrl);
  if LBody <> '' then
    Result := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
end;

function TAiFunctions.ImportMCPFromPPM(const AName, AVersion, ARegistryUrl: String): TMCPClientItem;
// Registers a StdIo stub without downloading. Useful if the binary is already installed.
// The caller must assign Params['Command'] with the path to the exe before enabling.
var
  LVersion: String;
  LClientItem: TMCPClientItem;
begin
  Result := nil;

  // Avoid duplicates
  LClientItem := FMCPClients.GetClientByName(AName);
  if Assigned(LClientItem) then
  begin
    Result := LClientItem;
    Exit;
  end;

  LVersion := PPMResolveVersion(ARegistryUrl, AName, AVersion);
  if LVersion = '' then
  begin
    DoLog(Format('ImportPPM: Could not resolve the version of "%s".', [AName]));
    Exit;
  end;

  LClientItem := FMCPClients.Add;
  LClientItem.Name := AName;
  LClientItem.TransportType := tpStdIo;
  LClientItem.Params.Values['Command'] := '';        // The caller must assign the path to the exe
  LClientItem.Params.Values['Arguments'] := '--protocol stdio';
  LClientItem.Params.Values['RootDir'] := TPath.GetHomePath;
  LClientItem.Enabled := False;
  LClientItem.UpdateClientProperties;

  Result := LClientItem;
  DoLog(Format('ImportPPM: "%s" v%s registered as stub. Assign Params[''Command''] before enabling.',
    [AName, LVersion]));
end;

function TAiFunctions.InstallMCPFromPPM(const AName, AVersion, AInstallDir,
  ARegistryUrl: String): TMCPClientItem;
var
  LVersion, LTempFile, LInstallDir, LExePath, LDownloadUrl: String;
  LClientItem: TMCPClientItem;
begin
  Result := nil;

  // If it is already registered, return the existing one without reinstalling
  LClientItem := FMCPClients.GetClientByName(AName);
  if Assigned(LClientItem) then
  begin
    Result := LClientItem;
    DoLog(Format('InstallPPM: "%s" is already registered.', [AName]));
    Exit;
  end;

  // Resolve version
  LVersion := PPMResolveVersion(ARegistryUrl, AName, AVersion);
  if LVersion = '' then
  begin
    DoLog(Format('InstallPPM: Could not resolve the version of "%s".', [AName]));
    Exit;
  end;

  // Determine installation directory
  if AInstallDir <> '' then
    LInstallDir := TPath.Combine(AInstallDir, AName)
  else
    LInstallDir := TPath.Combine(TPath.GetHomePath,
      '.ppm' + TPath.DirectorySeparatorChar +
      'mcp' + TPath.DirectorySeparatorChar + AName);

  // Download .paipkg to a temporary file
  LDownloadUrl := Format('%s/v1/packages/%s/%s/download', [ARegistryUrl, AName, LVersion]);
  LTempFile    := TPath.Combine(TPath.GetTempPath, AName + '-' + LVersion + '.paipkg');

  DoLog(Format('InstallPPM: Downloading "%s" v%s...', [AName, LVersion]));
  if not PPMHttpDownload(LDownloadUrl, LTempFile) then
  begin
    DoLog(Format('InstallPPM: Error downloading "%s".', [AName]));
    Exit;
  end;

  try
    // Extract the binary for the current platform
    DoLog(Format('InstallPPM: Extracting to "%s"...', [LInstallDir]));
    LExePath := PPMExtractBinary(LTempFile, LInstallDir);
    if LExePath = '' then
    begin
      DoLog(Format('InstallPPM: No compatible binary found in the package for "%s".', [AName]));
      Exit;
    end;
  finally
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
  end;

  // Register as a StdIo client ready to use
  LClientItem := FMCPClients.Add;
  LClientItem.Name            := AName;
  LClientItem.TransportType   := tpStdIo;
  LClientItem.Params.Values['Command']   := LExePath;
  LClientItem.Params.Values['Arguments'] := '--protocol stdio';
  LClientItem.Params.Values['RootDir']   := LInstallDir;
  LClientItem.Enabled := True;
  LClientItem.UpdateClientProperties;

  Result := LClientItem;
  DoLog(Format('InstallPPM: "%s" v%s installed at "%s".', [AName, LVersion, LExePath]));

  // Persist to the configuration file so AutoLoad loads it in the next session
  SaveMCPConfiguration;
end;

function TAiFunctions.GetMCPSchema(const AName, AVersion, ARegistryUrl: String): TJSONObject;
var
  LVersion, LUrl, LBody: String;
begin
  Result := nil;
  LVersion := PPMResolveVersion(ARegistryUrl, AName, AVersion);
  if LVersion = '' then
    Exit;
  LUrl  := Format('%s/v1/packages/%s/%s/schema', [ARegistryUrl, AName, LVersion]);
  LBody := PPMHttpGetStr(LUrl);
  if LBody <> '' then
    Result := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
end;

{ MCPClient }

{ TMCPClientItem }

constructor TMCPClientItem.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FEnabled := True;
  FOwned := True;
  FConnected := False;
  FParams := TStringList.Create;
  FEnvVars := TStringList.Create;

  // By default, we create a StdIo client
  FMCPClient := Nil; // TMCPClientStdIo.Create(nil); // No Owner so we control it ourselves
  FName := 'MCPClient';
  // FMCPClient.Name := 'NewMCPClient';

  // FIX: Always create the default client (StdIo).
  // This ensures that if SetParams is called before SetTransportType,
  // there is an object where the data can be saved.
  FMCPClient := TMCPClientStdIo.Create(nil);
  FMCPClient.Name := FName; //'MCPClient' + IntToStr(ID); // Temporary name

  // Synchronize initial params (StdIo defaults to the Wrapper)
  FParams.Assign(FMCPClient.Params);

  // Propagate in-place changes (e.g. Item.Params.Values['k'] := 'v') to the real client
  TStringList(FParams).OnChange   := OnFParamsChanged;
  TStringList(FEnvVars).OnChange  := OnFEnvVarsChanged;

end;

destructor TMCPClientItem.Destroy;
begin
  FParams.Free;
  FEnvVars.Free;
  if FOwned and Assigned(FMCPClient) then
    FreeAndNil(FMCPClient);
  inherited;
end;

// ISSUE #125: see note in TFunctionParamsItem.Assign. FMCPClient is not copied:
// each item owns its internal client (FOwned), and copying the pointer
// would cause a double free; the proxy properties are copied and
// UpdateClientProperties propagates them to the real client.
procedure TMCPClientItem.Assign(Source: TPersistent);
var
  Src: TMCPClientItem;
begin
  if Source is TMCPClientItem then
  begin
    Src := TMCPClientItem(Source);
    FEnabled := Src.FEnabled;
    FConnected := Src.FConnected;
    FName := Src.FName;
    SetTransportType(Src.GetTransportType); // recreates the internal client if the type differs
    FParams.Assign(Src.FParams);   // OnChange propaga a FMCPClient.Params
    FEnvVars.Assign(Src.FEnvVars); // OnChange propaga a FMCPClient.EnvVars
    UpdateClientProperties;        // sincroniza nombre/enabled al cliente interno
    Changed(False);
  end
  else
    inherited;
end;

function TMCPClientItem.GetConfiguration: string;
begin
  Result := Format('(%s, Click [...] to edit)', ['Properties']);
end;

{
  function TMCPClientItem.GetDisabledFunctions: TStrings;
  begin
  if Assigned(FMCPClient) then
  Result := FMCPClient.DisabledFunctions
  else
  Result := nil;
  end;
}

function TMCPClientItem.GetDisplayName: string;
begin
  Result := GetName;
  if Result.IsEmpty then
    Result := inherited GetDisplayName;
end;

function TMCPClientItem.GetEnvVars: TStrings;
begin
  Result := FEnvVars;
  {
    if Assigned(FMCPClient) then
    Begin
    Result := FMCPClient.EnvVars;
    End
    else
    Result := nil;
  }
end;

function TMCPClientItem.GetName: string;
begin
  Result := FName;

  if Result.IsEmpty then
    Result := inherited GetDisplayName;

  {
    if Assigned(FMCPClient) then
    Result := FMCPClient.Name
    else
    Result := inherited GetDisplayName;
  }
end;

function TMCPClientItem.GetParams: TStrings;
begin
  Result := FParams;
  {
    if Assigned(FMCPClient) then
    Begin
    Result := FMCPClient.Params;
    End
    else
    Result := nil;
  }
end;

function TMCPClientItem.GetTransportType: TToolTransportType;
begin
  Result := tpStdIo; // Default value
  if Assigned(FMCPClient) then
    Result := FMCPClient.TransportType;
end;

procedure TMCPClientItem.SetConfiguration(const Value: string);
begin
  // Nothing needs to be done here; it only needs to exist.
end;

procedure TMCPClientItem.SetConnected(const Value: Boolean);
var
  // OwnerComponent: TAiFunctions;
  // IsDesignTime: Boolean;
  ClientTools: TJSonObject;
  // ToolCount: Integer;
  // ToolArray: TJSonArray;
begin
  // Only act if the value really changes
  if FConnected = Value then
    Exit;

  // --- DESIGN-TIME VALIDATION LOGIC ---

  // 1. Only validate when it is activated (set to True)
  if not Value then
  Begin
    FConnected := Value;
    Changed(False);
    Exit;
  End;

  try
    try
      // We try to get the tool list. This is the "live" test.
      ClientTools := Self.MCPClient.ListTools;

      if Not Assigned(ClientTools) then
      begin
        // If ListTools returns nil, it is a connection or protocol error.
        Raise Exception.Create(Format('[ERR] Connection failure for "%s".'#13#10#13#10'Check the configuration (Command, URL, etc.) and the server logs.', [Self.Name]));
      end
      Else
      Begin
        ClientTools.Free;
        FConnected := Value;
        Changed(False);
      End;

    except
      on E: Exception do
      begin
        // Catch any other exception
        Raise Exception.Create(Format('[ERR] An exception occurred while validating "%s".'#13#10#13#10'%s: %s', [Self.Name, E.ClassName, E.Message]));
      end;
    end;
  finally
  end;
end;

{
  procedure TMCPClientItem.SetDisabledFunctions(const Value: TStrings);
  begin
  if Assigned(FMCPClient) and Assigned(Value) then
  begin
  FMCPClient.DisabledFunctions.Assign(Value);
  Changed(False); // Notifies the IDE that the item has changed.
  end;
  end;
}

procedure TMCPClientItem.SetEnabled(const Value: Boolean);
begin
  if FEnabled <> Value then
  begin
    FEnabled := Value;
    Changed(False);
  end;
end;

procedure TMCPClientItem.SetEnvVars(const Value: TStrings);
begin
  FEnvVars.Assign(Value);
  // OnFEnvVarsChanged is triggered automatically by the OnChange event of FEnvVars
  Changed(False);
end;

procedure TMCPClientItem.SetName(const Value: string);
begin
  if Pos(MCP_TOOL_SEP, Value) > 0 then
    raise EArgumentException.CreateFmt(
      'The MCP server name "%s" cannot contain the reserved separator "%s".',
      [Value, MCP_TOOL_SEP]);

  if FName <> Value then
  begin
    FName := Value;

    // Synchronize with the standard collection method so it appears in the TreeView
    inherited SetDisplayName(Value);

    // If the internal client exists, pass it the name
    if Assigned(FMCPClient) then
      FMCPClient.Name := Value;

    Changed(False);
  end;

  {
    SetDisplayName(Value);
    if Assigned(FMCPClient) then
    begin
    if FMCPClient.Name <> Value then
    begin
    FMCPClient.Name := Value;
    Changed(False);
    end;
    end;
  }
end;

procedure TMCPClientItem.OnFParamsChanged(Sender: TObject);
begin
  if Assigned(FMCPClient) then
    FMCPClient.Params.Assign(FParams);
end;

procedure TMCPClientItem.OnFEnvVarsChanged(Sender: TObject);
begin
  if Assigned(FMCPClient) then
    FMCPClient.EnvVars.Assign(FEnvVars);
end;

procedure TMCPClientItem.SetParams(const Value: TStrings);
begin
  FParams.Assign(Value);
  // OnFParamsChanged is triggered automatically by the OnChange event of FParams
  Changed(False);
end;

procedure TMCPClientItem.SetTransportType(const Value: TToolTransportType);
begin
  // Check whether it really changed or whether the object does not exist
  if not Assigned(FMCPClient) or (FMCPClient.TransportType <> Value) then
  begin
    // Free the previous client
    FreeAndNil(FMCPClient);

    // Create the new one according to the selected type
    case Value of
      tpStdIo:
        FMCPClient := TMCPClientStdIo.Create(nil);
      tpHttp:
        FMCPClient := TMCPClientHttp.Create(nil);
      tpSSE:
        FMCPClient := TMCPClientSSE.Create(nil);
      tpMakerAi:
        FMCPClient := TMCPClientMakerAi.Create(nil);
    else
      raise ENotSupportedException.Create('MCP protocol not supported');
    end;

    // =========================================================================
    // FIX: Assign the type explicitly TO THE NEW OBJECT
    // before synchronizing the rest of the properties.
    // =========================================================================
    FMCPClient.TransportType := Value;

    // Now, transfer name, params, envVars, etc.
    UpdateClientProperties;

    Changed(False);
  end;
end;

procedure TMCPClientItem.UpdateClientProperties;
begin
  // Ensure we have a client to which the data can be transferred
  if not Assigned(FMCPClient) then
    Exit;

  // 1. Transfer the transport type
  FMCPClient.TransportType := Self.GetTransportType; // We get the type from FMCPClient itself

  // 2. Transfer the name (using GetDisplayName, which is the 'Name' setter)
  FMCPClient.Name := FName;  //Self.GetDisplayName;

  // 3. Transfer the 'Enabled' state
  FMCPClient.Enabled := Self.FEnabled;

  // 4. Transfer the parameters (copy the contents of our local list)
  FMCPClient.Params.Assign(Self.FParams);

  // 5. Transfer the environment variables
  FMCPClient.EnvVars.Assign(Self.FEnvVars);
end;

{ TMCPClientItems }

function TMCPClientItems.Add: TMCPClientItem;
begin
  Result := TMCPClientItem(inherited Add);
end;

constructor TMCPClientItems.Create(AOwner: TPersistent);
begin
  FOwner := AOwner;
  inherited Create(Self, TMCPClientItem);

end;

destructor TMCPClientItems.Destroy;
begin
  inherited;
end;

function TMCPClientItems.GetClient(Index: Integer): TMCPClientItem;
begin
  Result := TMCPClientItem(inherited Items[Index]);
end;

function TMCPClientItems.GetClientByName(const AName: string): TMCPClientItem;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Count - 1 do
  begin
    if CompareText(Items[I].Name, AName) = 0 then
    begin
      Result := Items[I];
      Exit;
    end;
  end;
end;

function TMCPClientItems.GetClientsList: TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create;
  for I := 0 to Count - 1 do
    Result.Add(Items[I].Name);
end;

function TMCPClientItems.GetFunctionList(Name: String): TStringList;
{ Var
  Item: TMCPClientItem;
  jTools: TJSonObject;
}
begin
  Result := Nil;
  { Item := GetClientByName(Name);

    If Assigned(Item) and Assigned(Item.MCPClient) then
    jTools := Item.MCPClient.ListTools;
  }
end;

function TMCPClientItems.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

procedure TMCPClientItems.SetClient(Index: Integer; const Value: TMCPClientItem);
begin
  Items[Index].Assign(Value);
end;

procedure TMCPClientItems.Update(Item: TCollectionItem);
begin
  inherited;
end;

{ TJsonToolUtils }

constructor TNormalizedTool.Create(const AName, ADescription: string; AInputSchema: TJSonObject);
begin
  inherited Create;
  FName := AName;
  FDescription := ADescription;
  FInputSchema := AInputSchema;
end;

destructor TNormalizedTool.Destroy;
begin
  FInputSchema.Free;
  inherited;
end;

class procedure TJsonToolUtils.CleanInputSchema(ASchema: TJSonObject);
begin
  // Call the recursive worker function to clean the entire tree.
  CleanJsonTree(ASchema);
end;

// The real engine: a recursive function that traverses ANY JSON tree.
class procedure TJsonToolUtils.CleanJsonTree(AValue: TJSONValue);
var
  LObject: TJSonObject;
  LArray: TJSonArray;
  LPair: TJSONPair;
  LItem: TJSONValue;
begin
  if not Assigned(AValue) then
    Exit;

  // Case 1: The value is a JSON Object
  if AValue is TJSonObject then
  begin
    LObject := AValue as TJSonObject;
    // 1. Action: Remove unwanted keys at the current level.
    LObject.RemovePair('additionalProperties');
    LObject.RemovePair('$schema');

    // 2. Traversal: Call itself for each child value of the object.
    // It is important to iterate over a copy of the pairs if modifying,
    // but since RemovePair handles this internally, a for-in loop is safe.
    for LPair in LObject do
    begin
      CleanJsonTree(LPair.JsonValue);
    end;
  end
  // Case 2: The value is a JSON Array
  else if AValue is TJSonArray then
  begin
    LArray := AValue as TJSonArray;
    // Traversal: Call itself for each element of the array.
    for LItem in LArray do
    begin
      CleanJsonTree(LItem);
    end;
  end;
  // Case 3: It is a simple value (string, number, etc.). Nothing is done.
end;

{ TJsonToolUtils }

// ==============================================================================
// NEW DETECTION FUNCTION
// ==============================================================================
class function TJsonToolUtils.DetectInputFormat(AJsonTool: TJSonObject): TToolFormat;
var
  LTypeValue: TJSONValue;
begin
  Result := tfUnknown;
  if not Assigned(AJsonTool) then
    Exit;

  // Gemini
  if AJsonTool.FindValue('functionDeclarations') <> nil then
    Exit(tfGemini);

  // OpenAI Family Detection
  if AJsonTool.TryGetValue('type', LTypeValue) and (LTypeValue is TJSONString) and (LTypeValue.Value = 'function') then
  begin
    // Key differentiation:
    // tfOpenAI (Legacy/Chat): Has a "function" key containing the details.
    // tfOpenAIResponses (New): Has "name" directly at the root and does NOT have a "function" key.

    if AJsonTool.FindValue('function') <> nil then
      Exit(tfOpenAI)
    else if AJsonTool.FindValue('name') <> nil then
      Exit(tfOpenAIResponses);

    // By default, if ambiguous, assume the new standard if it has a name
    Exit(tfOpenAIResponses);
  end;

  // Anthropic
  if AJsonTool.FindValue('input_schema') <> nil then
    Exit(tfClaude);

  // MCP
  if AJsonTool.FindValue('inputSchema') <> nil then
    Exit(tfMCP);
end;

class procedure TJsonToolUtils.EnforceStrictSchema(ASchema: TJSONValue);
var
  JObj, JProps: TJSonObject;
  jReq: TJSonArray;
  PropName: string;
  I: Integer;
  ExistsInReq: Boolean;
  TypeV: TJSONValue;
begin
  if not(ASchema is TJSonObject) then
    Exit;

  JObj := TJSonObject(ASchema);

  // Check whether it is an object (has properties or is explicitly type object)
  // 'type' can be an ARRAY in JSON Schema (e.g. ["integer","string"]):
  // GetValue<string> crashes with TJSONArray (seen 2026-09-30 with the tools
  // from MKAIServer memory against gpt-6). Tolerant reading: here we only
  // care about knowing whether the node is an object.
  TypeV := JObj.GetValue('type');
  if (JObj.TryGetValue<TJSonObject>('properties', JProps)) or
     ((TypeV is TJSONString) and (TJSONString(TypeV).Value = 'object')) then
  begin
    // RULE 1: additionalProperties: false is MANDATORY
    if JObj.GetValue('additionalProperties') <> nil then
      JObj.RemovePair('additionalProperties');
    JObj.AddPair('additionalProperties', False);

    // RULE 2: All fields defined in properties must be in required
    if Assigned(JProps) then
    begin
      // Get or create the required array
      if not JObj.TryGetValue<TJSonArray>('required', jReq) then
      begin
        jReq := TJSonArray.Create;
        JObj.AddPair('required', jReq);
      end;

      for I := 0 to JProps.Count - 1 do
      begin
        PropName := JProps.Pairs[I].JsonString.Value;

        // Check whether it already exists in required to avoid duplicates
        ExistsInReq := False;
        for var J := 0 to jReq.Count - 1 do
        begin
          if jReq.Items[J].Value = PropName then
          begin
            ExistsInReq := True;
            Break;
          end;
        end;

        if not ExistsInReq then
          jReq.Add(PropName);

        // Recursion: Apply strict rules to children (nested objects)
        EnforceStrictSchema(JProps.Pairs[I].JsonValue);
      end;
    end;
  end;
end;

// ==============================================================================
// NORMALIZATION METHODS (unchanged)
// ==============================================================================
class procedure TJsonToolUtils.NormalizeFromMCP(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
var
  LName, LDescription: string;
  LInputSchema: TJSonObject;
  LSchemaValue: TJSONValue;
begin
  if not AJsonTool.TryGetValue<string>('name', LName) then
    Exit;
  AJsonTool.TryGetValue<string>('description', LDescription);

  if AJsonTool.TryGetValue('inputSchema', LSchemaValue) and (LSchemaValue is TJSonObject) then
  Begin
    LInputSchema := TJSonObject(LSchemaValue.Clone);
    CleanInputSchema(LInputSchema);
  End
  else
    LInputSchema := TJSonObject.Create; // Create an empty schema if it does not exist

  AToolList.Add(TNormalizedTool.Create(LName, LDescription, LInputSchema));
end;

class procedure TJsonToolUtils.NormalizeFromAnthropic(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
var
  LName, LDescription: string;
  LInputSchema: TJSonObject;
  LSchemaValue: TJSONValue;
begin
  if not AJsonTool.TryGetValue<string>('name', LName) then
    Exit;
  AJsonTool.TryGetValue<string>('description', LDescription);

  if AJsonTool.TryGetValue('input_schema', LSchemaValue) and (LSchemaValue is TJSonObject) then
  Begin
    LInputSchema := TJSonObject(LSchemaValue.Clone);
    CleanInputSchema(LInputSchema);
  End
  else
    LInputSchema := TJSonObject.Create;

  AToolList.Add(TNormalizedTool.Create(LName, LDescription, LInputSchema));
end;

{ class procedure TJsonToolUtils.NormalizeFromOpenAI(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
  var
  LName, LDescription: string;
  LInputSchema: TJSonObject;
  LSchemaValue: TJSonValue;
  begin
  if not AJsonTool.TryGetValue<string>('name', LName) then
  Exit;
  AJsonTool.TryGetValue<string>('description', LDescription);

  if AJsonTool.TryGetValue('parameters', LSchemaValue) and (LSchemaValue is TJSonObject) then
  LInputSchema := TJSonObject(LSchemaValue.Clone)
  else
  LInputSchema := TJSonObject.Create;

  AToolList.Add(TNormalizedTool.Create(LName, LDescription, LInputSchema));
  end;
}

// ==============================================================================
// CORRECTED OPENAI NORMALIZATION FUNCTION
// ==============================================================================
class procedure TJsonToolUtils.NormalizeFromOpenAI(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
var
  LName, LDescription: string;
  LInputSchema: TJSonObject;
  LSchemaValue: TJSONValue;
  LFunctionObject, LDataSource: TJSonObject; // LDataSource will point to the correct object
begin
  // First, determine where to read the data from.
  // Try to find the nested 'function' object.
  if AJsonTool.TryGetValue<TJSonObject>('function', LFunctionObject) then
  begin
    // Nested format: {"type": "function", "function": {"name": ...}}
    LDataSource := LFunctionObject;
  end
  else
  begin
    // Flat format: {"type": "function", "name": ...}
    LDataSource := AJsonTool;
  end;

  // Now extract the data using LDataSource, which points to the correct place.
  if not LDataSource.TryGetValue<string>('name', LName) then
    Exit; // If there is no name, it is not a valid tool.

  LDataSource.TryGetValue<string>('description', LDescription);

  if LDataSource.TryGetValue('parameters', LSchemaValue) and (LSchemaValue is TJSonObject) then
  Begin
    LInputSchema := TJSonObject(LSchemaValue.Clone);
    CleanInputSchema(LInputSchema);
  End
  else
  begin
    // Minimum valid schema: Claude and other providers require type=object even without parameters
    LInputSchema := TJSonObject.Create;
    LInputSchema.AddPair('type', 'object');
    LInputSchema.AddPair('properties', TJSonObject.Create);
  end;

  var LNorm := TNormalizedTool.Create(LName, LDescription, LInputSchema);
  // 'async' can come at the root (Responses flat format) or inside
  // 'function' (classic format); LDataSource already points to the correct place.
  LNorm.IsAsync := LDataSource.GetValue<Boolean>('async', False);
  AToolList.Add(LNorm);
end;

class procedure TJsonToolUtils.NormalizeToolsFromSource(const ASourceName: string; ASourceJson: TJSonObject; ANormalizedList: TList<TNormalizedTool>);
var
  LSourceToolsArray: TJSonArray;
  I: Integer;
  LSourceTool: TJSonObject;
  LDetectedFormat: TToolFormat;
begin
  if not Assigned(ASourceJson) or not ASourceJson.TryGetValue<TJSonArray>('tools', LSourceToolsArray) or (LSourceToolsArray.Count = 0) then
    Exit; // No tools to process

  // Detect format from the first tool
  if not(LSourceToolsArray.Items[0] is TJSonObject) then
    Exit;
  LDetectedFormat := DetectInputFormat(LSourceToolsArray.Items[0] as TJSonObject);
  if LDetectedFormat = tfUnknown then
    Exit; // Unrecognized format

  // Normalize each tool
  for I := 0 to LSourceToolsArray.Count - 1 do
  begin
    if not(LSourceToolsArray.Items[I] is TJSonObject) then
      Continue;
    LSourceTool := LSourceToolsArray.Items[I] as TJSonObject;

    // Save the current count to know which tools were added
    var
    LInitialCount := ANormalizedList.Count;

    case LDetectedFormat of
      tfMCP:
        NormalizeFromMCP(LSourceTool, ANormalizedList);
      tfClaude:
        NormalizeFromAnthropic(LSourceTool, ANormalizedList);

      tfOpenAI, tfOpenAIResponses: // Both use the same reading normalizer
        NormalizeFromOpenAI(LSourceTool, ANormalizedList);

      tfGemini:
        NormalizeFromGemini(LSourceTool, ANormalizedList);
    end;

    // Apply the source prefix to the newly added tools
    if not ASourceName.IsEmpty then
    begin
      for var J := LInitialCount to ANormalizedList.Count - 1 do
        ANormalizedList[J].FName := Format('%s%s%s', [ASourceName, MCP_TOOL_SEP, ANormalizedList[J].Name]);
    end;
  end;
end;

class procedure TJsonToolUtils.NormalizeFromGemini(AJsonTool: TJSonObject; AToolList: TList<TNormalizedTool>);
var
  LFuncDeclarations: TJSonArray;
  I: Integer;
  LFuncDecl, LSchema: TJSonObject;
  LSchemaValue: TJSONValue;
  LName, LDescription: string;
begin
  // Gemini format has a 'functionDeclarations' array inside each 'tool'
  if not AJsonTool.TryGetValue<TJSonArray>('functionDeclarations', LFuncDeclarations) then
    Exit;

  for I := 0 to LFuncDeclarations.Count - 1 do
  begin
    if not(LFuncDeclarations.Items[I] is TJSonObject) then
      Continue;
    LFuncDecl := LFuncDeclarations.Items[I] as TJSonObject;

    if not LFuncDecl.TryGetValue<string>('name', LName) then
      Continue;
    LFuncDecl.TryGetValue<string>('description', LDescription);

    if LFuncDecl.TryGetValue('parameters', LSchemaValue) and (LSchemaValue is TJSonObject) then
    Begin
      LSchema := TJSonObject(LSchemaValue.Clone);
      CleanInputSchema(LSchema);
    End
    else
      LSchema := TJSonObject.Create;

    AToolList.Add(TNormalizedTool.Create(LName, LDescription, LSchema));
  end;
end;

// ==============================================================================
// FORMATTING METHODS (unchanged)
// ==============================================================================
class function TJsonToolUtils.FormatAsMCP(ANormalizedTool: TNormalizedTool): TJSonObject;
begin
  Result := TJSonObject.Create;
  Result.AddPair('name', ANormalizedTool.Name);
  Result.AddPair('description', ANormalizedTool.Description);
  Result.AddPair('inputSchema', TJSonObject(ANormalizedTool.InputSchema.Clone));
end;

class function TJsonToolUtils.FormatAsAnthropic(ANormalizedTool: TNormalizedTool): TJSonObject;
begin
  Result := TJSonObject.Create;
  Result.AddPair('name', ANormalizedTool.Name);
  Result.AddPair('description', ANormalizedTool.Description);
  Result.AddPair('input_schema', TJSonObject(ANormalizedTool.InputSchema.Clone));
end;

{ class function TJsonToolUtils.FormatAsCohere(ANormalizedTool: TNormalizedTool): TJSonObject;
  var
  LParamDefs, LParam, LInputSchema, LProperties: TJSonObject;
  LRequiredArray: TJSonArray;
  LPair: TJSONPair;
  LReqValue, LDesc, LType: TJSONValue; // Variables declared at the beginning
  IsRequired: Boolean;
  begin
  Result := TJSonObject.Create;
  Result.AddPair('name', ANormalizedTool.Name);
  Result.AddPair('description', ANormalizedTool.Description);

  LInputSchema := ANormalizedTool.InputSchema;
  if not Assigned(LInputSchema) or not LInputSchema.TryGetValue<TJSonObject>('properties', LProperties) then
  begin
  Exit;
  end;

  LParamDefs := TJSonObject.Create;
  Result.AddPair('parameter_definitions', LParamDefs);

  LRequiredArray := nil;
  LInputSchema.TryGetValue<TJSonArray>('required', LRequiredArray);

  for LPair in LProperties do
  begin
  if not (LPair.JsonValue is TJSonObject) then Continue;

  LParam := TJSonObject.Create;
  var LPropObj := LPair.JsonValue as TJSonObject;

  if LPropObj.TryGetValue<TJSONValue>('description', LDesc) then
  LParam.AddPair('description', LDesc.Clone as TJSONString);
  if LPropObj.TryGetValue<TJSONValue>('type', LType) then
  LParam.AddPair('type', LType.Clone as TJSONString);

  IsRequired := False;
  if Assigned(LRequiredArray) then
  begin
  for LReqValue in LRequiredArray do
  begin
  if SameText(LReqValue.Value, LPair.JsonString.Value) then
  begin
  IsRequired := True;
  Break;
  end;
  end;
  end;
  LParam.AddPair('required', TJSONBool.Create(IsRequired));

  LParamDefs.AddPair(LPair.JsonString.Value, LParam);
  end;
  end;
}

{
  class function TJsonToolUtils.FormatAsOpenAI(ANormalizedTool: TNormalizedTool): TJSonObject;
  begin
  Result := TJSonObject.Create;
  Result.AddPair('type', 'function');
  Result.AddPair('name', ANormalizedTool.Name);
  Result.AddPair('description', ANormalizedTool.Description);
  Result.AddPair('parameters', TJSonObject(ANormalizedTool.InputSchema.Clone));
  end;
}

// ==============================================================================
// FORMATTING FUNCTION FOR OPENAI (CORRECTED AND DEFINITIVE VERSION)
// ==============================================================================
class function TJsonToolUtils.FormatAsOpenAI(ANormalizedTool: TNormalizedTool): TJSonObject;
var
  LFunctionObject: TJSonObject;
begin
  // 1. Create the internal "function" object that will contain the details.
  LFunctionObject := TJSonObject.Create;
  LFunctionObject.AddPair('name', ANormalizedTool.Name);
  LFunctionObject.AddPair('description', ANormalizedTool.Description);

  // 2. Only add 'parameters' if the schema has content.
  if Assigned(ANormalizedTool.InputSchema) and (ANormalizedTool.InputSchema.Count > 0) then
    LFunctionObject.AddPair('parameters', TJSonObject(ANormalizedTool.InputSchema.Clone));

  // 3. Create the main outer object.
  Result := TJSonObject.Create;
  Result.AddPair('type', 'function');
  Result.AddPair('function', LFunctionObject); // <-- Add the internal object
end;

class function TJsonToolUtils.FormatAsOpenAIResponses(ANormalizedTool: TNormalizedTool): TJSonObject;
var
  LParams: TJSonObject;
begin
  // Responses API format (Flat + Strict)
  // {
  // "type": "function",
  // "name": "tool_name",
  // "description": "...",
  // "parameters": { ... },
  // "strict": true
  // }

  Result := TJSonObject.Create;
  Result.AddPair('type', 'function');
  Result.AddPair('name', ANormalizedTool.Name);

  // Async tool calling: the model keeps working while the application
  // executes this tool, and the result is delivered later with its call_id.
  // Only the Responses API of gpt-6-astra and later understands it; that is why it
  // is emitted here and not in the other formatters.
  if ANormalizedTool.IsAsync then
    Result.AddPair('async', TJSONBool.Create(True));

  if not ANormalizedTool.Description.IsEmpty then
    Result.AddPair('description', ANormalizedTool.Description);

  // Only add parameters if they exist
  if Assigned(ANormalizedTool.InputSchema) and (ANormalizedTool.InputSchema.Count > 0) then
  begin
    // Clone the original schema so as not to modify the base reference
    LParams := TJSonObject(ANormalizedTool.InputSchema.Clone);

    // ---> HERE IS THE MAGIC: Force the schema to comply with Strict Mode <---
    EnforceStrictSchema(LParams);

    Result.AddPair('parameters', LParams);
  end
  else
  begin
    // OpenAI Strict requires a parameters schema even if it is empty
    // It must be: "parameters": {"type": "object", "properties": {}, "additionalProperties": false, "required": []}
    LParams := TJSonObject.Create;
    LParams.AddPair('type', 'object');
    LParams.AddPair('properties', TJSonObject.Create);
    LParams.AddPair('additionalProperties', False);
    LParams.AddPair('required', TJSonArray.Create);
    Result.AddPair('parameters', LParams);
  end;

  // The Responses API strongly recommends strict: true
  Result.AddPair('strict', True);
end;

class function TJsonToolUtils.FormatToolList(ANormalizedList: TList<TNormalizedTool>; AOutputFormat: TToolFormat): TJSonObject;
var
  LFinalToolsArray: TJSonArray;
  LNormTool: TNormalizedTool;
  LFormattedTool: TJSonObject;
begin
  Result := TJSonObject.Create;
  LFinalToolsArray := TJSonArray.Create;
  Result.AddPair('tools', LFinalToolsArray);

  if ANormalizedList.Count = 0 then
    Exit;

  if AOutputFormat = tfGemini then
  begin
    // --- SPECIAL LOGIC FOR GEMINI: Group everything into a single block ---
    var
    LDeclarationsArray := TJSonArray.Create;
    for LNormTool in ANormalizedList do
    begin
      LDeclarationsArray.Add(FormatAsGeminiFunctionDeclaration(LNormTool));
    end;

    var
    LGeminiToolWrapper := TJSonObject.Create;
    LGeminiToolWrapper.AddPair('functionDeclarations', LDeclarationsArray);
    LFinalToolsArray.Add(LGeminiToolWrapper);
  end
  else
  begin
    // --- STANDARD LOGIC FOR OTHER FORMATS: One tool per object ---
    for LNormTool in ANormalizedList do
    begin
      LFormattedTool := nil;
      case AOutputFormat of
        tfMCP:
          LFormattedTool := FormatAsMCP(LNormTool);
        tfClaude:
          LFormattedTool := FormatAsAnthropic(LNormTool);
        tfOpenAI:
          LFormattedTool := FormatAsOpenAI(LNormTool);
        tfOpenAIResponses:
          LFormattedTool := FormatAsOpenAIResponses(LNormTool);
        // tfCohere:
        // LFormattedTool := FormatAsCohere(LNormTool);
      end;

      if Assigned(LFormattedTool) then
        LFinalToolsArray.Add(LFormattedTool);
    end;
  end;
end;

{ class function TJsonToolUtils.FormatAsGemini(ANormalizedTool: TNormalizedTool): TJSonObject;
  var
  LFuncDecl: TJSonObject;
  LFuncDeclsArray: TJSonArray;
  begin
  // Create the nested Gemini structure
  LFuncDecl := TJSonObject.Create;
  LFuncDecl.AddPair('name', ANormalizedTool.Name);
  LFuncDecl.AddPair('description', ANormalizedTool.Description);
  LFuncDecl.AddPair('parameters', TJSonObject(ANormalizedTool.InputSchema.Clone));

  LFuncDeclsArray := TJSonArray.Create;
  LFuncDeclsArray.Add(LFuncDecl);

  Result := TJSonObject.Create;
  Result.AddPair('functionDeclarations', LFuncDeclsArray);
  end;
}

class function TJsonToolUtils.FormatAsGeminiFunctionDeclaration(ANormalizedTool: TNormalizedTool): TJSonObject;
begin
  // Creates only the function declaration object, not the wrapper.
  Result := TJSonObject.Create;
  Result.AddPair('name', ANormalizedTool.Name);
  Result.AddPair('description', ANormalizedTool.Description);

  // Only add 'parameters' if the schema has content.
  if Assigned(ANormalizedTool.InputSchema) and (ANormalizedTool.InputSchema.Count > 0) then
    Result.AddPair('parameters', TJSonObject(ANormalizedTool.InputSchema.Clone));
end;

// ==============================================================================
// PUBLIC FUNCTIONS
// ==============================================================================

// OVERLOAD with automatic detection
class function TJsonToolUtils.MergeToolLists(const ASourceName: string; ASourceJson: TJSonObject; ATargetJson: TJSonObject; AOutputFormat: TToolFormat): TJSonObject;
var
  LSourceToolsArray: TJSonArray;
  LFirstTool: TJSonObject;
  LDetectedFormat: TToolFormat;
begin
  // 1. Try to detect the format from the first tool in the array
  LDetectedFormat := tfUnknown;
  if Assigned(ASourceJson) and ASourceJson.TryGetValue<TJSonArray>('tools', LSourceToolsArray) and (LSourceToolsArray.Count > 0) and (LSourceToolsArray.Items[0] is TJSonObject) then
  begin
    LFirstTool := LSourceToolsArray.Items[0] as TJSonObject;
    LDetectedFormat := DetectInputFormat(LFirstTool);
  end;

  // 2. If detection fails, we cannot continue.
  if LDetectedFormat = tfUnknown then
  begin
    // We could raise an exception or simply return the target unchanged.
    // Returning the target is safer.
    // raise EJSON.CreateFmt('Could not detect tool format for source "%s".', [ASourceName]);
    Result := ATargetJson;
    Exit;
  end;

  // 3. Call the main function with the detected format.
  Result := MergeToolLists(ASourceName, ASourceJson, LDetectedFormat, ATargetJson, AOutputFormat);
end;


// EXPLICIT VERSION (corrected final main logic)

class function TJsonToolUtils.MergeToolLists(const ASourceName: string; ASourceJson: TJSonObject; AInputFormat: TToolFormat; ATargetJson: TJSonObject; AOutputFormat: TToolFormat): TJSonObject;
var
  LSourceToolsArray, LFinalToolsArray: TJSonArray;
  LNormalizedTools: TList<TNormalizedTool>;
  I: Integer;
  LSourceTool, LFormattedTool: TJSonObject;
  LNormTool: TNormalizedTool;
begin
  // 1. Validate and prepare source and target JSON
  if not Assigned(ASourceJson) or not ASourceJson.TryGetValue<TJSonArray>('tools', LSourceToolsArray) then
  begin
    Result := ATargetJson; // Nothing to process
    Exit;
  end;

  if not Assigned(ATargetJson) then
  begin
    ATargetJson := TJSonObject.Create;
    ATargetJson.AddPair('tools', TJSonArray.Create);
  end;

  if not ATargetJson.TryGetValue<TJSonArray>('tools', LFinalToolsArray) then
    raise Exception.Create('Target JSON object does not contain a "tools" array.');

  // 2. Normalize the source tools into an internal list
  LNormalizedTools := TObjectList<TNormalizedTool>.Create(True);
  try
    for I := 0 to LSourceToolsArray.Count - 1 do
    begin
      if not(LSourceToolsArray.Items[I] is TJSonObject) then
        Continue;
      LSourceTool := LSourceToolsArray.Items[I] as TJSonObject;

      case AInputFormat of
        tfMCP:
          NormalizeFromMCP(LSourceTool, LNormalizedTools);
        tfClaude:
          NormalizeFromAnthropic(LSourceTool, LNormalizedTools);

        // Support both OpenAI formats on input (the NormalizeFromOpenAI function detects the internal structure)
        tfOpenAI, tfOpenAIResponses:
          NormalizeFromOpenAI(LSourceTool, LNormalizedTools);

        tfGemini:
          NormalizeFromGemini(LSourceTool, LNormalizedTools);
      else
        Continue; // Ignore unsupported formats
      end;
    end;

    // If no tools were normalized, there is nothing else to do.
    if LNormalizedTools.Count = 0 then
    begin
      Result := ATargetJson;
      Exit;
    end;

    // 3. Pre-process the names of all normalized tools
    for LNormTool in LNormalizedTools do
    begin
      if not ASourceName.IsEmpty then
        LNormTool.FName := Format('%s%s%s', [ASourceName, MCP_TOOL_SEP, LNormTool.Name]);
    end;

    // 4. Format and add to the target
    if AOutputFormat = tfGemini then
    begin
      // --- SPECIAL LOGIC FOR GEMINI: Group everything into a single block ---
      var
      LDeclarationsArray := TJSonArray.Create;
      for LNormTool in LNormalizedTools do
      begin
        // Use the helper function that formats an individual declaration
        LDeclarationsArray.Add(FormatAsGeminiFunctionDeclaration(LNormTool));
      end;

      // Create the single 'tool' wrapper object
      var
      LGeminiToolWrapper := TJSonObject.Create;
      LGeminiToolWrapper.AddPair('functionDeclarations', LDeclarationsArray);

      // Add this single object to the final tools array
      LFinalToolsArray.Add(LGeminiToolWrapper);
    end
    else
    begin
      // --- STANDARD LOGIC FOR OTHER FORMATS: One tool per object ---
      for LNormTool in LNormalizedTools do
      begin
        LFormattedTool := nil;
        case AOutputFormat of
          tfMCP:
            LFormattedTool := FormatAsMCP(LNormTool);
          tfClaude:
            LFormattedTool := FormatAsAnthropic(LNormTool);
          tfOpenAI:
            LFormattedTool := FormatAsOpenAI(LNormTool); // Legacy (Wrapper function)
          tfOpenAIResponses:
            LFormattedTool := FormatAsOpenAIResponses(LNormTool); // New (Flat)
        end;

        if Assigned(LFormattedTool) then
          LFinalToolsArray.Add(LFormattedTool);
      end;
    end;

  finally
    LNormalizedTools.Free; // Frees the list and all TNormalizedTool objects inside it.
  end;

  Result := ATargetJson;
end;

end.
