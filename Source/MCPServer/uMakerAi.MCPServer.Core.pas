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
// Name: Gustavo Enr?quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.MCPServer.Core;

interface

uses
  System.SysUtils, System.Classes, System.JSON, Rest.JSON, System.Rtti, System.StrUtils,
  System.ConvUtils, System.IOUtils, System.NetEncoding, System.Net.Mime, IdGlobalProtocols,
  System.Generics.Collections, System.SyncObjs, System.TypInfo, uMakerAi.Tools.Functions;

type

  // Progress callback for long-running tools (MCP notifications/progress).
  // AProgress advances toward ATotal (convention: ATotal=1.0 and AProgress in 0..1).
  TAiMCPProgressProc = reference to procedure(AProgress, ATotal: Double; const AMessage: string);

  // Delivery of a JSON-RPC notification to a session client (implemented by
  // the transport; in SSE it is a push to the session Outbox).
  TAiMCPSendNotificationProc = reference to procedure(const ASessionID, ANotificationJson: string);

  TAiAuthContext = record
    IsAuthenticated: Boolean;
    UserID: string;
    UserName: string;
    Roles: TArray<string>;
    // Assigned by the server in tools/call when the request carries _meta.progressToken
    // and the transport supports notifications. Tools invoke it if Assigned to
    // emit notifications/progress without knowing the session or the token.
    OnProgress: TAiMCPProgressProc;
    // --- MCP 2026-07-28, MRTR pattern ---
    // If the tools/call request is an MRTR retry, the responses arrive here
    // from the client to the previous inputRequests (map id->result, e.g.
    // ElicitResult) and the opaque requestState emitted by the tool. InputResponses
    // belongs to the request: tools MUST NOT free it or retain the
    // reference. WARNING: requestState travels through the client and must be treated as
    // untrusted input (protect integrity if it affects authorization/logic).
    InputResponses: TJSONObject;
    RequestState: string;
  end;

  // Custom validation event (Layer 2).
  // AAuthHeader: value of the Authorization or X-API-Key header.
  // ARemoteIP: client IP.
  // AAuthContext: authentication context to populate.
  // AIsValid: True if the request is valid.
  TAiMCPValidateEvent = procedure(Sender: TObject; const AAuthHeader, ARemoteIP: string;
    out AAuthContext: TAiAuthContext; out AIsValid: Boolean) of object;

  // ISSUE #110: fired during 'initialize' with the client identity
  // (clientInfo.name/version + protocolVersion). Setting AAllow:=False rejects the
  // connection by returning a JSON-RPC error with AReason. 100% opt-in: if not assigned
  // the handler, nothing changes.
  TAiMCPClientConnectEvent = procedure(Sender: TObject;
    const AClientName, AClientVersion, AProtocolVersion: string;
    var AAllow: Boolean; var AReason: string) of object;

  // ISSUE #110 (Part B): fired when a request to tools/, resources/, or
  // prompts/ arrives WITHOUT an authorized session (no 'initialize' was performed or the
  // Mcp-Session-Id is not valid). The handler can allow the request
  // (AAllow:=True) or customize the rejection reason (AReason). It is only evaluated
  // when session gating is active (OnClientConnect is assigned).
  TAiMCPUnauthorizedEvent = procedure(Sender: TObject;
    const ASessionID, AMethod: string;
    var AAllow: Boolean; var AReason: string) of object;

  TAiMCPResponseBuilder = class
  private
    FContentArray: TJSONArray;
    constructor Create;
  public
    class function New: TAiMCPResponseBuilder;
    destructor Destroy; override;

    // Adds a simple text block to the response
    function AddText(const AText: string): TAiMCPResponseBuilder;

    // Adds a file from a disk path
    function AddFile(const AFilePath: string; AFileName: string = ''): TAiMCPResponseBuilder;

    // Adds a file from a TStream
    function AddFileFromStream(AStream: TStream; const AFileName: string; const AMimeType: string): TAiMCPResponseBuilder;

    // Builds the final JSON object that will be returned as 'result' in the tool call
    function Build: TJSONObject;
  end;

  TAiMCPSchemaUtils = class
  public
    class function GenerateSchema(AClass: TClass): TJSONObject;
  end;

  TAiMCPSerializerUtils = class
  public
    class function Deserialize<T: class, constructor>(JSON: TJSONObject): T;
    class procedure DeserializeObject(Instance: TObject; JSON: TJSONObject);
    // ----------------------
  end;

  AiMCPOptionalAttribute = class(TCustomAttribute)
  end;

  AiMCPSchemaDescriptionAttribute = class(TCustomAttribute)
  private
    FDescription: string;
  public
    constructor Create(const ADescription: string);
    property Description: string read FDescription;
  end;

  AiMCPSchemaEnumAttribute = class(TCustomAttribute)
  private
    FValues: TArray<string>;
  public
    constructor Create(const AValues: array of string);
    property Values: TArray<string> read FValues;
  end;

  //
  // --- SECTION: MakerAi Suite - Tool Base Types ---
  //
type
  IAiMCPTool = interface
    ['{B1A4D0F8-9A7B-4C6C-8D1F-4B9E3A5F7C1E}']
    function GetName: string;
    function GetDescription: string;
    // Returns a NEW object on each call: the caller owns it
    // (TAiMCPToolBase<T> generates it from the parameter class)
    function GetInputSchema: TJSONObject;
    // function Execute(const Arguments: TJSONObject): string;
    function Execute(const Arguments: TJSONObject; const AuthContext: TAiAuthContext): TJSONObject;

    property Name: string read GetName;
    property Description: string read GetDescription;
    property InputSchema: TJSONObject read GetInputSchema;
  end;

  TAiMCPToolBase<T: class, constructor> = class(TInterfacedObject, IAiMCPTool)
  protected
    FName: string;
    FDescription: string;
    // function ExecuteWithParams(const Params: T): string; virtual; abstract;
    function ExecuteWithParams(const Params: T; const AuthContext: TAiAuthContext): TJSONObject; virtual; abstract;
  public
    constructor Create; virtual;
    function GetName: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    // function Execute(const Arguments: TJSONObject): string;
    function Execute(const Arguments: TJSONObject; const AuthContext: TAiAuthContext): TJSONObject;
  end;

  //
  // --- SECTION: MakerAi Suite - Resource Base Types ---
  //
type
  IAiMCPResource = interface
    ['{E6A3B2C9-5D8F-4A1E-B9C2-7D8F9A0B1C3D}']
    function GetURI: string;
    function GetName: string;
    function GetDescription: string;
    function GetMimeType: string;
    function Read: string;

    property URI: string read GetURI;
    property Name: string read GetName;
    property Description: string read GetDescription;
    property MimeType: string read GetMimeType;
  end;

  TAiMCPResourceBase<T: class, constructor> = class(TInterfacedObject, IAiMCPResource)
  protected
    FURI: string;
    FName: string;
    FDescription: string;
    FMimeType: string;
    function GetResourceData: T; virtual; abstract;
  public
    constructor Create; virtual;
    function GetURI: string;
    function GetName: string;
    function GetDescription: string;
    function GetMimeType: string;
    function Read: string;
  end;

  //
  // --- SECTION: MakerAi Suite - Main Server Class ---
  //
type
  TAiMCPToolFactory = reference to function: IAiMCPTool;
  TAiMCPResourceFactory = reference to function: IAiMCPResource;

  TAiMCPLogicServer = class(TObject)
  private
    // --- Settings Fields ---
    FPort: Integer;
    FHost: string;
    FServerName: string;
    FServerVersion: string;
    FProtocolVersion: string;
    FCorsEnabled: Boolean;
    FCorsAllowedOrigins: string;
    FSettingsFile: string;

    // --- Internal State ---
    FIsActive: Boolean;
    FToolFactories: TDictionary<string, TAiMCPToolFactory>;
    FResourceFactories: TDictionary<string, TAiMCPResourceFactory>;
    FActiveTools: TDictionary<string, IAiMCPTool>;
    FActiveResources: TDictionary<string, IAiMCPResource>;
    FUser: String;
    FOnSendNotification: TAiMCPSendNotificationProc;
    FOnClientConnect: TAiMCPClientConnectEvent; // ISSUE #110: client vetting in initialize
    // ISSUE #110 (Part B): registry of authorized sessions + opt-in gating.
    FAuthorizedSessions: TDictionary<string, TDateTime>;
    FSessionsLock: TCriticalSection;
    FOnUnauthorizedRequest: TAiMCPUnauthorizedEvent;

    // --- Private Methods ---
    // Engine shared by all ExecuteRequest overloads. AEnforceSession
    // enables session gating (only the HTTP transport activates it). In an
    // successful 'initialize' returns the issued session in AIssuedSessionID.
    function DoExecuteRequest(const ARequestJson, ASessionID: string;
      const AAuthContext: TAiAuthContext; AEnforceSession: Boolean;
      out AIssuedSessionID: string): string;
    class function RequiresSession(const AMethodName: string): Boolean; static;
    function ParseJSONRequest(const RequestBody: string): TJSONObject;
    function ExtractRequestID(JSONRequest: TJSONObject): TValue;
    function CreateJSONResponse(const RequestID: TValue): TJSONObject;
    procedure AddRequestIDToResponse(Response: TJSONObject; const RequestID: TValue);
    function CreateErrorResponse(const RequestID: TValue; ErrorCode: Integer; const ErrorMessage: string): string;
    function ExecuteMethodCall(const MethodName: string; Params: TJSONObject; const SessionID: string; const AAuthContext: TAiAuthContext): TValue;
    function HandleCoreMethod(const Method: string; const Params: TJSONObject): TValue;
    function HandleToolsMethod(const Method: string; const Params: TJSONObject; const ASessionID: string; const AAuthContext: TAiAuthContext): TValue;
    function HandleResourcesMethod(const Method: string; const Params: TJSONObject): TValue;
    function HandlePromptsMethod(const Method: string; const Params: TJSONObject): TValue;
    function Core_Initialize(const Params: TJSONObject): TValue;
    function Core_Ping: TValue;
    // --- MCP 2026-07-28 (modo stateless / dual-era) ---
    function Core_ServerDiscover(const Params: TJSONObject): TValue;
    class function GetRequestMeta(Params: TJSONObject): TJSONObject; static;
    class function GetModernProtocolVersion(Params: TJSONObject): string; static;
    class procedure GetClientInfoFromMeta(Params: TJSONObject; out AName, AVersion: string); static;
    function VetClientAllowed(const AClientName, AClientVersion, AProtocolVersion: string; out AReason: string): Boolean;
    function CreateErrorResponseWithData(const RequestID: TValue; ErrorCode: Integer;
      const ErrorMessage: string; AData: TJSONObject): string;
    procedure DecorateModernResult(AResult: TJSONObject);
    class procedure AddCacheHints(AResult: TJSONObject; ATtlMs: Integer); static;
    function Tools_ListTools: TValue;
    function Tools_CallTool(const Params: TJSONObject; const ASessionID: string; const AAuthContext: TAiAuthContext): TValue;
    function BuildProgressNotification(const ATokenJson: string; AProgress, ATotal: Double; const AMessage: string): string;
    function Resources_ListResources: TValue;
    function Resources_ReadResource(const Params: TJSONObject): TValue;
    function Resources_ListTemplates: TValue;
    procedure SetUser(const Value: String);
    procedure SetSettingsFile(const Value: String);

  Protected
    procedure LoadSettingsDefaults;
    procedure CreateDefaultSettingsFile;
    procedure LoadSettingsFromFile;

  public
    constructor Create(const ASettingsFile: string = '');
    destructor Destroy; override;

    procedure RegisterTool(const Name: string; Factory: TAiMCPToolFactory);
    procedure RegisterResource(const URI: string; Factory: TAiMCPResourceFactory);

    procedure Start;
    procedure Stop;

    function ExecuteRequest(const ARequestJson: string; const ASessionID: string): string; overload;
    function ExecuteRequest(const ARequestJson: string; const ASessionID: string; const AAuthContext: TAiAuthContext): string; overload;
    // ISSUE #110 (Part B): overload with session gating (used by the HTTP transport).
    // If the request was a successful 'initialize', AIssuedSessionID carries the new
    // Mcp-Session-Id that the transport must return to the client in the header.
    function ExecuteRequest(const ARequestJson: string; const ASessionID: string;
      const AAuthContext: TAiAuthContext; out AIssuedSessionID: string): string; overload;

    // --- ISSUE #110 (Part B): authorized session management ---
    // Gating is only activated when an OnClientConnect handler is assigned:
    // without it, the server behaves as before (accepts everything).
    function SessionEnforcementActive: Boolean;
    function IsSessionAuthorized(const ASessionID: string): Boolean;
    procedure RegisterAuthorizedSession(const ASessionID: string);
    procedure RemoveAuthorizedSession(const ASessionID: string);
    function NewSessionId: string;
    property SettingsFile: String read FSettingsFile write SetSettingsFile;
    property IsActive: Boolean read FIsActive;
    // Public properties for settings for convenience
    property Port: Integer read FPort write FPort;
    property Host: string read FHost write FHost;
    property ServerName: string read FServerName write FServerName;
    property ServerVersion: string read FServerVersion write FServerVersion;
    property ProtocolVersion: string read FProtocolVersion write FProtocolVersion;
    property CorsEnabled: Boolean read FCorsEnabled write FCorsEnabled;
    property CorsAllowedOrigins: string read FCorsAllowedOrigins write FCorsAllowedOrigins;
    property User: String read FUser write SetUser;
    // It is assigned by the transport (SSE) to enable notifications/progress.
    // If it is nil, tools simply do not receive OnProgress in their AuthContext.
    property OnSendNotification: TAiMCPSendNotificationProc read FOnSendNotification write FOnSendNotification;
    // ISSUE #110: opt-in client vetting on connect (initialize).
    property OnClientConnect: TAiMCPClientConnectEvent read FOnClientConnect write FOnClientConnect;
    // ISSUE #110 (Part B): fired when a request arrives without an authorized session.
    property OnUnauthorizedRequest: TAiMCPUnauthorizedEvent read FOnUnauthorizedRequest write FOnUnauthorizedRequest;

  end;

  TAiMCPServer = class(TComponent)
  private
    FActive: Boolean;
    FCorsEnabled: Boolean;
    FEndPoint: String;
    FCorsAllowedOrigins: string;
    FServerName: String;
    FAiFunctions: TAiFunctions;
    FApiKey: string;
    FOnValidateRequest: TAiMCPValidateEvent;
    FBindAddress: string;
    function GetEndpoint: string;
    function GetPort: Integer;
    procedure SetPort(const Value: Integer);
    function GetUser: String;
    procedure SetUser(const Value: String);
    function GetSettingsFile: String;
    procedure SetSettingsFile(const Value: String);
    function GetServerName: String;
    procedure SetServerName(const Value: String);
    function GetServerVersion: String;
    procedure SetServerVersion(const Value: String);
    function GetOnClientConnect: TAiMCPClientConnectEvent;
    procedure SetOnClientConnect(const Value: TAiMCPClientConnectEvent);
    function GetOnUnauthorizedRequest: TAiMCPUnauthorizedEvent;
    procedure SetOnUnauthorizedRequest(const Value: TAiMCPUnauthorizedEvent);
    procedure SetAiFunctions(const Value: TAiFunctions);
    // Helper: registers a single function. Being in a separate method,
    // each call has its own capture frame — guarantees that the
    // factory closure does not share AItem with other loop iterations.
    procedure InternalRegisterOneFunction(AItem: TFunctionActionItem);
  protected
    // We make it protected so descendants can access it directly.
    FLogicServer: TAiMCPLogicServer;
    // We make the setter protected so only descendants control the state.
    procedure SetActive(const Value: Boolean);
    Procedure InternalRegisterFromAiFunctions;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    // Request validation: Layer 1 (API Key) + Layer 2 (custom event)
    function ValidateRequest(const AAuthHeader, ARemoteIP: string; out AAuthContext: TAiAuthContext): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // We make Start and Stop virtual so descendants can extend them.
    procedure Start; virtual;
    procedure Stop; virtual;

    procedure RegisterTool(const Name: string; Factory: TAiMCPToolFactory);
    procedure RegisterResource(const URI: string; Factory: TAiMCPResourceFactory);

    procedure LoadSettingsDefaults;
    procedure CreateDefaultSettingsFile;
    procedure LoadSettingsFromFile;

    property Port: Integer read GetPort write SetPort;
    // Local IP where network transports listen (SSE/HTTP). Empty = all
    // interfaces (historical behavior). If empty, the
    // environment variable MCP_BIND_ADDRESS is used, so a service binds to 127.0.0.1
    // from its systemd unit without recompiling the program that uses it.
    property BindAddress: string read FBindAddress write FBindAddress;
    // BindAddress or, if empty, MCP_BIND_ADDRESS ('' = all)
    function EffectiveBindAddress: string;
    property Endpoint: string read GetEndpoint;
    property CorsEnabled: Boolean read FCorsEnabled write FCorsEnabled;
    property CorsAllowedOrigins: string read FCorsAllowedOrigins write FCorsAllowedOrigins;

    // Properties common to all servers
    property LogicServer: TAiMCPLogicServer read FLogicServer;
    property IsActive: Boolean read FActive;
    property User: String read GetUser Write SetUser;
    property SettingsFile: String read GetSettingsFile write SetSettingsFile;
  Published
    Property ServerName: String read GetServerName write SetServerName;
    // Version reported by initialize in serverInfo (delegates to the logic engine)
    property ServerVersion: String read GetServerVersion write SetServerVersion;
    property AiFunctions: TAiFunctions read FAiFunctions write SetAiFunctions;
    // Authentication: If ApiKey is configured, validates "Authorization: Bearer <key>" or "X-API-Key: <key>"
    property ApiKey: string read FApiKey write FApiKey;
    // Custom event for advanced validation (JWT, OAuth, DB lookup, etc.)
    property OnValidateRequest: TAiMCPValidateEvent read FOnValidateRequest write FOnValidateRequest;
    // ISSUE #110: opt-in client vetting upon receiving 'initialize' (proxy to the logic engine)
    property OnClientConnect: TAiMCPClientConnectEvent read GetOnClientConnect write SetOnClientConnect;
    // ISSUE #110 (Part B): rejection of requests without an authorized session (proxy to the logic engine)
    property OnUnauthorizedRequest: TAiMCPUnauthorizedEvent read GetOnUnauthorizedRequest write SetOnUnauthorizedRequest;
  end;

const
  // --- MCP 2026-07-28 (modo stateless / dual-era) ---
  // Version moderna soportada ademas de la legacy (ProtocolVersion del servidor).
  MCP_PROTOCOL_VERSION_MODERN = '2026-07-28';
  // Claves _meta estandarizadas por la spec 2026-07-28. OJO: llevan puntos en el
  // nombre, por lo que SIEMPRE deben leerse con GetValue(nombre exacto) y nunca
  // con las variantes por path (GetValue<T>/TryGetValue<T>), que interpretan el
  // punto como separador de niveles.
  MCP_META_PROTOCOL_VERSION = 'io.modelcontextprotocol/protocolVersion';
  MCP_META_CLIENT_INFO = 'io.modelcontextprotocol/clientInfo';
  MCP_META_CLIENT_CAPABILITIES = 'io.modelcontextprotocol/clientCapabilities';
  MCP_META_SERVER_INFO = 'io.modelcontextprotocol/serverInfo';
  // Codigos de error del rango reservado MCP (-32020..-32099)
  MCP_ERROR_HEADER_MISMATCH = -32020;
  MCP_ERROR_UNSUPPORTED_PROTOCOL_VERSION = -32022;

implementation

uses
  System.IniFiles, System.JSON.Writers, uMakerAi.MCPServer.Bridge, uMakerAi.Telemetry;

const
  // JSON-RPC 2.0 Error Codes
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;

  //
  // --- SECTION: Internal Helper Classes (Definition of methods) ---
  //
type
  TInternalSchemaGenerator = class
  private
    class function GetJsonTypeFromRttiType(RttiType: TRttiType): string;
    class function GetPropertyJsonName(Prop: TRttiProperty): string;
    class function IsRequiredProperty(Prop: TRttiProperty): Boolean;
  public
    class function GenerateSchema(Cls: TClass): TJSONObject;
  end;

  TInternalSerializer = class
  private
    class var FContext: TRttiContext;
    class function ConvertJsonToValue(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure DeserializeObject(Instance: TObject; const JSON: TJSONObject);
  end;

  // --- Public Utility Class Implementations ---

class function TAiMCPSchemaUtils.GenerateSchema(AClass: TClass): TJSONObject;
begin
  // This is fine because GenerateSchema is NOT a generic method.
  Result := TInternalSchemaGenerator.GenerateSchema(AClass);
end;

class procedure TAiMCPSerializerUtils.DeserializeObject(Instance: TObject; JSON: TJSONObject);
begin
  // Since this method is NOT generic, it CAN call a local type from the implementation.
  TInternalSerializer.DeserializeObject(Instance, JSON);
end;
// -----------------------------------------------------------

class function TAiMCPSerializerUtils.Deserialize<T>(JSON: TJSONObject): T;
begin
  Result := T.Create;
  try
    // Now we call the public intermediary, which is valid for the compiler.
    DeserializeObject(Result, JSON);
  except
    Result.Free;
    raise;
  end;
end;

// --- Attribute Implementations ---

constructor AiMCPSchemaDescriptionAttribute.Create(const ADescription: string);
begin
  inherited Create;
  FDescription := ADescription;
end;

constructor AiMCPSchemaEnumAttribute.Create(const AValues: array of string);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FValues, Length(AValues));
  for I := 0 to High(AValues) do
    FValues[I] := AValues[I];
end;

// -----------------------------------------------------------------------------
// --- Implementation: TAiMCPToolBase<T> ---
// -----------------------------------------------------------------------------
constructor TAiMCPToolBase<T>.Create;
begin
  inherited Create;
end;

function TAiMCPToolBase<T>.GetName: string;
begin
  Result := FName;
end;

function TAiMCPToolBase<T>.GetDescription: string;
begin
  Result := FDescription;
end;

function TAiMCPToolBase<T>.GetInputSchema: TJSONObject;
begin
  Result := TAiMCPSchemaUtils.GenerateSchema(T);
end;

function TAiMCPToolBase<T>.Execute(const Arguments: TJSONObject; const AuthContext: TAiAuthContext): TJSONObject;
var
  ParamsInstance: T;
begin
  // The deserialization code is the same
  if not Assigned(Arguments) then
    raise Exception.Create('Arguments cannot be nil for tool execution.');

  ParamsInstance := TAiMCPSerializerUtils.Deserialize<T>(Arguments);
  try
    // The difference is that now the result is a TJSONObject
    Result := ExecuteWithParams(ParamsInstance, AuthContext);
  finally
    ParamsInstance.Free;
  end;
end;

// -----------------------------------------------------------------------------
// --- Implementation: TAiMCPResourceBase<T> ---
// -----------------------------------------------------------------------------
constructor TAiMCPResourceBase<T>.Create;
begin
  inherited Create;
end;

function TAiMCPResourceBase<T>.GetURI: string;
begin
  Result := FURI;
end;

function TAiMCPResourceBase<T>.GetName: string;
begin
  Result := FName;
end;

function TAiMCPResourceBase<T>.GetDescription: string;
begin
  Result := FDescription;
end;

function TAiMCPResourceBase<T>.GetMimeType: string;
begin
  Result := FMimeType;
end;

function TAiMCPResourceBase<T>.Read: string;
var
  ResourceData: T;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Prop: TRttiProperty;
begin
  ResourceData := GetResourceData;
  try
    if SameText(FMimeType, 'application/json') then
    begin
      Result := TJson.ObjectToJsonString(ResourceData);
    end
    else // Assumes other text-based mime-types
    begin
      RttiContext := TRttiContext.Create;
      try
        RttiType := RttiContext.GetType(ResourceData.ClassType);
        Prop := RttiType.GetProperty('Content');
        if Assigned(Prop) and (Prop.PropertyType.TypeKind in [tkString, tkUString, tkLString, tkWString]) then
        begin
          Result := Prop.GetValue(TObject(ResourceData)).AsString;
        end
        else
          Result := 'Error: Resource object does not have a readable string property named "Content".';
      finally
        RttiContext.Free;
      end;
    end;
  finally
    ResourceData.Free;
  end;
end;

// -----------------------------------------------------------------------------
// --- TAiMCPServer Implementation ---
// -----------------------------------------------------------------------------

constructor TAiMCPLogicServer.Create(const ASettingsFile: string);
begin
  inherited Create;
  FIsActive := False;
  FToolFactories := TDictionary<string, TAiMCPToolFactory>.Create;
  FResourceFactories := TDictionary<string, TAiMCPResourceFactory>.Create;
  FActiveTools := TDictionary<string, IAiMCPTool>.Create;
  FActiveResources := TDictionary<string, IAiMCPResource>.Create;
  FAuthorizedSessions := TDictionary<string, TDateTime>.Create;
  FSessionsLock := TCriticalSection.Create;

  if ASettingsFile = '' then
    FSettingsFile := ChangeFileExt(ParamStr(0), '.ini')
  else
    FSettingsFile := ASettingsFile;

  LoadSettingsDefaults;

  if TFile.Exists(FSettingsFile) then
    LoadSettingsFromFile;
end;

destructor TAiMCPLogicServer.Destroy;
begin
  Stop;
  FToolFactories.Free;
  FResourceFactories.Free;
  FActiveTools.Free;
  FActiveResources.Free;
  FAuthorizedSessions.Free;
  FSessionsLock.Free;
  inherited;
end;

procedure TAiMCPLogicServer.RegisterTool(const Name: string; Factory: TAiMCPToolFactory);
begin
  if FIsActive then
    raise Exception.Create('Cannot register tools while the server is active.');
  FToolFactories.AddOrSetValue(Name, Factory);
end;

procedure TAiMCPLogicServer.RegisterResource(const URI: string; Factory: TAiMCPResourceFactory);
begin
  if FIsActive then
    raise Exception.Create('Cannot register resources while the server is active.');
  FResourceFactories.AddOrSetValue(URI, Factory);
end;

procedure TAiMCPLogicServer.SetSettingsFile(const Value: String);
begin
  FSettingsFile := Value;
end;

procedure TAiMCPLogicServer.SetUser(const Value: String);
begin
  FUser := Value;
end;

procedure TAiMCPLogicServer.Start;
var
  Pair: TPair<string, TAiMCPToolFactory>;
  ResourcePair: TPair<string, TAiMCPResourceFactory>;
begin
  if FIsActive then
    Exit;

  // 1. Clear any previous active instance to avoid duplicates on restarts
  FActiveTools.Clear;
  FActiveResources.Clear;

  // 2. Run the tool factories.
  // Each Pair.Value is a function that, when called, returns an IAiMCPTool instance.
  for Pair in FToolFactories do
  begin
    // Important: Pair.Key is the registered name, Pair.Value() creates the instance.
    FActiveTools.Add(Pair.Key, Pair.Value());
  end;

  // 3. Run the resource factories.
  for ResourcePair in FResourceFactories do
  begin
    FActiveResources.Add(ResourcePair.Key, ResourcePair.Value());
  end;

  FIsActive := True;
end;

procedure TAiMCPLogicServer.Stop;
begin
  if not FIsActive then
    Exit;
  FActiveTools.Clear;
  FActiveResources.Clear;
  FIsActive := False;
end;

procedure TAiMCPLogicServer.LoadSettingsDefaults;
begin
  FPort := 3000;
  FHost := 'localhost';
  FServerName := 'MakerAi-MCPServer';
  FServerVersion := '1.0.0';
  FProtocolVersion := '2025-03-26';
  FCorsEnabled := True;
  FCorsAllowedOrigins := '*';
end;

procedure TAiMCPLogicServer.CreateDefaultSettingsFile;
var
  IniFile: TIniFile;
begin
  IniFile := TIniFile.Create(FSettingsFile);
  try
    IniFile.WriteInteger('Server', 'Port', FPort);
    IniFile.WriteString('Server', 'Host', FHost);
    IniFile.WriteString('Server', 'Name', FServerName);
    IniFile.WriteString('Protocol', 'Version', FProtocolVersion);
    IniFile.WriteBool('CORS', 'Enabled', FCorsEnabled);
    IniFile.WriteString('CORS', 'AllowedOrigins', FCorsAllowedOrigins);
  finally
    IniFile.Free;
  end;
end;

procedure TAiMCPLogicServer.LoadSettingsFromFile;
var
  IniFile: TIniFile;
begin

  if FSettingsFile = '' then
    FSettingsFile := ChangeFileExt(ParamStr(0), '.ini');

  if not TFile.Exists(FSettingsFile) then
    Exit;

  IniFile := TIniFile.Create(FSettingsFile);
  try
    FPort := IniFile.ReadInteger('Server', 'Port', FPort);
    FHost := IniFile.ReadString('Server', 'Host', FHost);
    FServerName := IniFile.ReadString('Server', 'Name', FServerName);
    FProtocolVersion := IniFile.ReadString('Protocol', 'Version', FProtocolVersion);
    FCorsEnabled := IniFile.ReadBool('CORS', 'Enabled', FCorsEnabled);
    FCorsAllowedOrigins := IniFile.ReadString('CORS', 'AllowedOrigins', FCorsAllowedOrigins);
  finally
    IniFile.Free;
  end;
end;

// Overload without AuthContext: backward compatible (Stdio, Direct)
function TAiMCPLogicServer.ExecuteRequest(const ARequestJson: string; const ASessionID: string): string;
var
  LAuthContext: TAiAuthContext;
begin
  LAuthContext := Default(TAiAuthContext);
  LAuthContext.IsAuthenticated := (FUser <> '');
  LAuthContext.UserID := FUser;
  Result := ExecuteRequest(ARequestJson, ASessionID, LAuthContext);
end;

// Overload with AuthContext: used by SSE (without HTTP session gating)
function TAiMCPLogicServer.ExecuteRequest(const ARequestJson: string; const ASessionID: string; const AAuthContext: TAiAuthContext): string;
var
  LIssued: string;
begin
  Result := DoExecuteRequest(ARequestJson, ASessionID, AAuthContext, False, LIssued);
end;

// ISSUE #110 (Part B): overload with session gating, used by the HTTP transport.
function TAiMCPLogicServer.ExecuteRequest(const ARequestJson: string; const ASessionID: string;
  const AAuthContext: TAiAuthContext; out AIssuedSessionID: string): string;
begin
  Result := DoExecuteRequest(ARequestJson, ASessionID, AAuthContext, True, AIssuedSessionID);
end;

class function TAiMCPLogicServer.RequiresSession(const AMethodName: string): Boolean;
begin
  // initialize/ping do not require a session (initialize creates it).
  Result := StartsText('tools/', AMethodName) or StartsText('resources/', AMethodName) or
    StartsText('prompts/', AMethodName);
end;

function TAiMCPLogicServer.SessionEnforcementActive: Boolean;
begin
  // 100% opt-in: gating is only activated if the user assigned OnClientConnect.
  Result := Assigned(FOnClientConnect);
end;

function TAiMCPLogicServer.NewSessionId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G);
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
end;

function TAiMCPLogicServer.IsSessionAuthorized(const ASessionID: string): Boolean;
begin
  if Trim(ASessionID) = '' then
    Exit(False);
  FSessionsLock.Enter;
  try
    Result := FAuthorizedSessions.ContainsKey(ASessionID);
  finally
    FSessionsLock.Leave;
  end;
end;

procedure TAiMCPLogicServer.RegisterAuthorizedSession(const ASessionID: string);
begin
  if Trim(ASessionID) = '' then
    Exit;
  FSessionsLock.Enter;
  try
    FAuthorizedSessions.AddOrSetValue(ASessionID, Now);
  finally
    FSessionsLock.Leave;
  end;
end;

procedure TAiMCPLogicServer.RemoveAuthorizedSession(const ASessionID: string);
begin
  FSessionsLock.Enter;
  try
    FAuthorizedSessions.Remove(ASessionID);
  finally
    FSessionsLock.Leave;
  end;
end;

function TAiMCPLogicServer.DoExecuteRequest(const ARequestJson, ASessionID: string;
  const AAuthContext: TAiAuthContext; AEnforceSession: Boolean; out AIssuedSessionID: string): string;
var
  JSONRequest, JSONResponse, Params: TJSONObject;
  RequestID: TValue;
  MethodName: string;
  IsNotification: Boolean;
  ExecuteResult: TValue;
  LSpan: TAiSpan;
  LSpanErr: string;
begin
  AIssuedSessionID := '';
  LSpan := nil;
  LSpanErr := '';

  if not FIsActive then
  begin
    Result := '{"jsonrpc": "2.0", "error": {"code": -32000, "message": "Server not active"}, "id": null}';
    Exit;
  end;

  JSONRequest := nil;
  JSONResponse := nil;
  RequestID := TValue.Empty;

  try
    try
      JSONRequest := ParseJSONRequest(ARequestJson);
      RequestID := ExtractRequestID(JSONRequest);
      MethodName := JSONRequest.GetValue<string>('method', '');
      IsNotification := not Assigned(JSONRequest.GetValue('id'));

      if IsNotification then
      begin
        Exit('');
      end;

      // Params are extracted before the gate: modern mode (spec 2026-07-28,
      // stateless) is detected by _meta['io.modelcontextprotocol/protocolVersion'].
      var
      ParamsValue := JSONRequest.GetValue('params');
      if Assigned(ParamsValue) and (ParamsValue is TJSONObject) then
        Params := ParamsValue as TJSONObject
      else
        Params := nil;

      // --- MCP 2026-07-28: per-request version negotiation ---
      // If the client declares a modern version that we do not support, it responds
      // UnsupportedProtocolVersionError with the list of supported versions so
      // that the client can retry with a compatible one.
      var LModernProto: string := GetModernProtocolVersion(Params);

      // Telemetry: if the client propagated traceparent in _meta (convention of
      // spec 2026-07-28), the server span continues that remote trace.
      var LTraceParent: string := '';
      var LMetaTel := GetRequestMeta(Params);
      if Assigned(LMetaTel) then
      begin
        var VTp := LMetaTel.GetValue('traceparent');
        if VTp is TJSONString then
          LTraceParent := TJSONString(VTp).Value;
      end;
      LSpan := AiSpanStart('mcp.server ' + MethodName, skServer, LTraceParent);
      AiSpanAttr(LSpan, 'mcp.method', MethodName);
      AiSpanAttr(LSpan, 'mcp.modern', LModernProto <> '');

      if (LModernProto <> '') and (LModernProto <> MCP_PROTOCOL_VERSION_MODERN) then
      begin
        LSpanErr := 'Unsupported protocol version: ' + LModernProto;
        var LSupported := TJSONArray.Create;
        LSupported.Add(MCP_PROTOCOL_VERSION_MODERN);
        if FProtocolVersion <> MCP_PROTOCOL_VERSION_MODERN then
          LSupported.Add(FProtocolVersion);
        var LData := TJSONObject.Create;
        LData.AddPair('supported', LSupported);
        LData.AddPair('requested', LModernProto);
        Result := CreateErrorResponseWithData(RequestID, MCP_ERROR_UNSUPPORTED_PROTOCOL_VERSION,
          'Unsupported protocol version', LData);
        Exit;
      end;

      // --- ISSUE #110 (Part B): session gate ---
      // Only when the transport requests it (HTTP) and gating is active
      // (OnClientConnect is assigned). tools/resources/prompts require a session created
      // previously by a successful 'initialize'. Exception (spec 2026-07-28): a
      // modern request is stateless and does not use sessions; vetting of
      // OnClientConnect is applied per request with the identity carried in _meta.
      if AEnforceSession and SessionEnforcementActive and RequiresSession(MethodName) and
        (not IsSessionAuthorized(ASessionID)) then
      begin
        if LModernProto <> '' then
        begin
          var LCliName, LCliVersion, LVetReason: string;
          GetClientInfoFromMeta(Params, LCliName, LCliVersion);
          if not VetClientAllowed(LCliName, LCliVersion, LModernProto, LVetReason) then
          begin
            LSpanErr := LVetReason;
            Result := CreateErrorResponse(RequestID, -32001, LVetReason);
            Exit;
          end;
        end
        else
        begin
          var LAllow: Boolean := False;
          var LReason: string := 'Unauthorized: a valid Mcp-Session-Id is required. Call initialize first.';
          if Assigned(FOnUnauthorizedRequest) then
            FOnUnauthorizedRequest(Self, ASessionID, MethodName, LAllow, LReason);
          if not LAllow then
          begin
            if Trim(LReason) = '' then
              LReason := 'Unauthorized';
            LSpanErr := LReason;
            Result := CreateErrorResponse(RequestID, -32001, LReason);
            Exit;
          end;
        end;
      end;

      JSONResponse := CreateJSONResponse(RequestID);

      ExecuteResult := ExecuteMethodCall(MethodName, Params, ASessionID, AAuthContext);

      // --- ISSUE #110 (Part B): issue session after successful 'initialize' ---
      // Core_Initialize already passed vetting (OnClientConnect). We reuse the
      // incoming Mcp-Session-Id if it came and is valid; otherwise, we issue a new one.
      if AEnforceSession and SessionEnforcementActive and (MethodName = 'initialize') then
      begin
        if IsSessionAuthorized(ASessionID) then
          AIssuedSessionID := ASessionID
        else
          AIssuedSessionID := NewSessionId;
        RegisterAuthorizedSession(AIssuedSessionID);
      end;

      if ExecuteResult.IsEmpty then
        JSONResponse.AddPair('result', TJSONNull.Create)
      else if ExecuteResult.IsType<TJSONObject> then
      begin
        var LResultObj := ExecuteResult.AsType<TJSONObject>;
        // MCP 2026-07-28: mandatory resultType + serverInfo in _meta.
        // Legacy clients ignore fields they do not know, so
        // always decorating is harmless and keeps a single code path.
        DecorateModernResult(LResultObj);
        JSONResponse.AddPair('result', LResultObj);
      end
      else
        JSONResponse.AddPair('result', TJSONString.Create(ExecuteResult.ToString));

      Result := JSONResponse.ToJSON;

    except
      on E: Exception do
      begin
        var
        ErrorCode := JSONRPC_INTERNAL_ERROR;
        // Spec 2026-07-28: only an unknown METHOD is -32601; a tool or
        // nonexistent resource is Invalid Params (-32602, previously -32002/-32601).
        if Pos('not found', E.Message) > 0 then
        begin
          if StartsText('Method', E.Message) then
            ErrorCode := JSONRPC_METHOD_NOT_FOUND
          else
            ErrorCode := JSONRPC_INVALID_PARAMS;
        end;
        if Pos('Invalid params', E.Message) > 0 then
          ErrorCode := JSONRPC_INVALID_PARAMS;

        if Assigned(JSONRequest) and RequestID.IsEmpty then
          RequestID := ExtractRequestID(JSONRequest);

        LSpanErr := E.Message;
        Result := CreateErrorResponse(RequestID, ErrorCode, E.Message);
      end;
    end;
  finally
    AiSpanEnd(LSpan, LSpanErr);
    JSONRequest.Free;
    JSONResponse.Free;
  end;
end;

function TAiMCPLogicServer.ParseJSONRequest(const RequestBody: string): TJSONObject;
var
  ParsedValue: TJSONValue;
begin
  ParsedValue := TJSONObject.ParseJSONValue(RequestBody, False);
  if not(ParsedValue is TJSONObject) then
  begin
    ParsedValue.Free;
    raise Exception.Create('Invalid JSON request: Not a JSON object.');
  end;
  Result := TJSONObject(ParsedValue);
end;

function TAiMCPLogicServer.ExtractRequestID(JSONRequest: TJSONObject): TValue;
var
  IdValue: TJSONValue;
begin
  IdValue := JSONRequest.GetValue('id');
  if not Assigned(IdValue) or (IdValue is TJSONNull) then
    Exit(TValue.Empty);

  if IdValue is TJSONNumber then
    Result := TValue.From<Int64>((IdValue as TJSONNumber).AsInt64)
  else if IdValue is TJSONString then
    Result := TValue.From<string>((IdValue as TJSONString).Value)
  else
    Result := TValue.Empty;
end;

function TAiMCPLogicServer.CreateJSONResponse(const RequestID: TValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  AddRequestIDToResponse(Result, RequestID);
end;

procedure TAiMCPLogicServer.AddRequestIDToResponse(Response: TJSONObject; const RequestID: TValue);
begin
  if RequestID.IsEmpty then
    Response.AddPair('id', TJSONNull.Create)
  else if RequestID.IsType<String> then
    Response.AddPair('id', RequestID.AsString)
  else if RequestID.IsOrdinal then
    Response.AddPair('id', TJSONNumber.Create(RequestID.AsInt64))
  else
    Response.AddPair('id', TJSONNull.Create);
end;

function TAiMCPLogicServer.CreateErrorResponse(const RequestID: TValue; ErrorCode: Integer; const ErrorMessage: string): string;
var
  JSONResponse, ErrorObj: TJSONObject;
begin
  JSONResponse := TJSONObject.Create;
  try
    JSONResponse.AddPair('jsonrpc', '2.0');
    ErrorObj := TJSONObject.Create;
    ErrorObj.AddPair('code', TJSONNumber.Create(ErrorCode));
    ErrorObj.AddPair('message', ErrorMessage);
    JSONResponse.AddPair('error', ErrorObj);
    AddRequestIDToResponse(JSONResponse, RequestID);
    Result := JSONResponse.ToJSON;
  finally
    JSONResponse.Free;
  end;
end;

function TAiMCPLogicServer.ExecuteMethodCall(const MethodName: string; Params: TJSONObject; const SessionID: string; const AAuthContext: TAiAuthContext): TValue;
begin
  if Trim(MethodName) = '' then
    raise Exception.CreateHelp('Method not specified.', JSONRPC_INVALID_REQUEST);

  if StartsText('tools/', MethodName) then
    Result := HandleToolsMethod(MethodName, Params, SessionID, AAuthContext)
  else if StartsText('resources/', MethodName) then
    Result := HandleResourcesMethod(MethodName, Params)
  else if StartsText('prompts/', MethodName) then
    Result := HandlePromptsMethod(MethodName, Params)
  else if (MethodName = 'initialize') or (MethodName = 'ping') or (MethodName = 'server/discover') then
    Result := HandleCoreMethod(MethodName, Params)
  else
    raise Exception.CreateFmt('Method [%s] not found.', [MethodName]);
end;

function TAiMCPLogicServer.HandleCoreMethod(const Method: string; const Params: TJSONObject): TValue;
begin
  if Method = 'initialize' then
    Result := Core_Initialize(Params)
  else if Method = 'ping' then
    Result := Core_Ping
  else if Method = 'server/discover' then
    Result := Core_ServerDiscover(Params)
  else
    Result := TValue.Empty;
end;

function TAiMCPLogicServer.HandleToolsMethod(const Method: string; const Params: TJSONObject; const ASessionID: string; const AAuthContext: TAiAuthContext): TValue;
begin
  if Method = 'tools/list' then
    Result := Tools_ListTools
  else if Method = 'tools/call' then
    Result := Tools_CallTool(Params, ASessionID, AAuthContext)
  else
    raise Exception.CreateFmt('Method %s not handled by Tools capability', [Method]);
end;

function TAiMCPLogicServer.HandleResourcesMethod(const Method: string; const Params: TJSONObject): TValue;
begin
  if Method = 'resources/list' then
    Result := Resources_ListResources
  else if Method = 'resources/read' then
    Result := Resources_ReadResource(Params)
  else if Method = 'resources/templates/list' then
    Result := Resources_ListTemplates
  else
    raise Exception.CreateFmt('Method %s not handled by Resources capability', [Method]);
end;

function TAiMCPLogicServer.HandlePromptsMethod(const Method: string; const Params: TJSONObject): TValue;
var
  ResultJSON: TJSONObject;
begin
  // We do not expose prompts, but respond to 'prompts/list' with an empty list so as not to
  // return -32601: real clients (e.g. opencode) discard the server if this
  // method fails during the handshake. ISSUE #109.
  if Method = 'prompts/list' then
  begin
    ResultJSON := TJSONObject.Create;
    ResultJSON.AddPair('prompts', TJSONArray.Create);
    AddCacheHints(ResultJSON, 60000); // spec 2026-07-28: prompts/list is CacheableResult
    Result := TValue.From<TJSONObject>(ResultJSON);
  end
  else
    raise Exception.CreateFmt('Method %s not handled by Prompts capability', [Method]);
end;

function TAiMCPLogicServer.Core_Initialize(const Params: TJSONObject): TValue;
var
  ResultJSON, Capabilities, ToolsCap, ResourcesCap, ServerInfo: TJSONObject;
begin
  // ISSUE #110: opt-in client vetting. If a handler exists, the identity is passed
  // (clientInfo + protocolVersion) and can reject the connection (AAllow:=False) ->
  // an exception is raised that the JSON-RPC layer converts into an error for the client.
  if Assigned(FOnClientConnect) then
  begin
    var LCliName: string := '';
    var LCliVersion: string := '';
    var LCliProto: string := '';
    if Assigned(Params) then
    begin
      LCliProto := Params.GetValue<string>('protocolVersion', '');
      var jClientInfo: TJSONObject;
      if Params.TryGetValue<TJSONObject>('clientInfo', jClientInfo) and Assigned(jClientInfo) then
      begin
        LCliName := jClientInfo.GetValue<string>('name', '');
        LCliVersion := jClientInfo.GetValue<string>('version', '');
      end;
    end;
    var LReason: string;
    if not VetClientAllowed(LCliName, LCliVersion, LCliProto, LReason) then
      raise Exception.Create(LReason);
  end;

  ResultJSON := TJSONObject.Create;
  ResultJSON.AddPair('protocolVersion', FProtocolVersion);
  Capabilities := TJSONObject.Create;
  ResultJSON.AddPair('capabilities', Capabilities);
  ToolsCap := TJSONObject.Create;
  Capabilities.AddPair('tools', ToolsCap);
  ResourcesCap := TJSONObject.Create;
  Capabilities.AddPair('resources', ResourcesCap);
  ServerInfo := TJSONObject.Create;
  ResultJSON.AddPair('serverInfo', ServerInfo);
  ServerInfo.AddPair('name', FServerName);
  ServerInfo.AddPair('version', FServerVersion);
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

function TAiMCPLogicServer.Core_Ping: TValue;
begin
  Result := TValue.From<TJSONObject>(TJSONObject.Create);
end;

// -----------------------------------------------------------------------------
// --- MCP 2026-07-28 (modo stateless / dual-era) ---
// -----------------------------------------------------------------------------

// Returns the _meta object from the request params, or nil if not present.
// The object belongs to the request; the caller MUST NOT free it.
class function TAiMCPLogicServer.GetRequestMeta(Params: TJSONObject): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if Assigned(Params) then
  begin
    V := Params.GetValue('_meta');
    if V is TJSONObject then
      Result := TJSONObject(V);
  end;
end;

// Protocol version declared by the client in _meta (modern mode).
// Empty string = legacy request (handshake initialize / no metadata).
class function TAiMCPLogicServer.GetModernProtocolVersion(Params: TJSONObject): string;
var
  Meta: TJSONObject;
  V: TJSONValue;
begin
  Result := '';
  Meta := GetRequestMeta(Params);
  if Assigned(Meta) then
  begin
    // GetValue with exact name: the key contains dots and the variants by
    // path would interpret them as level separators.
    V := Meta.GetValue(MCP_META_PROTOCOL_VERSION);
    if V is TJSONString then
      Result := TJSONString(V).Value;
  end;
end;

// Extracts clientInfo.name/version from _meta (modern mode).
class procedure TAiMCPLogicServer.GetClientInfoFromMeta(Params: TJSONObject; out AName, AVersion: string);
var
  Meta: TJSONObject;
  V: TJSONValue;
begin
  AName := '';
  AVersion := '';
  Meta := GetRequestMeta(Params);
  if Assigned(Meta) then
  begin
    V := Meta.GetValue(MCP_META_CLIENT_INFO);
    if V is TJSONObject then
    begin
      AName := TJSONObject(V).GetValue<string>('name', '');
      AVersion := TJSONObject(V).GetValue<string>('version', '');
    end;
  end;
end;

// Shared vetting (ISSUE #110 + modern mode): queries OnClientConnect if
// it is assigned. Returns False with AReason when the server rejects the client.
function TAiMCPLogicServer.VetClientAllowed(const AClientName, AClientVersion, AProtocolVersion: string;
  out AReason: string): Boolean;
var
  LAllow: Boolean;
begin
  AReason := '';
  Result := True;
  if not Assigned(FOnClientConnect) then
    Exit;
  LAllow := True;
  FOnClientConnect(Self, AClientName, AClientVersion, AProtocolVersion, LAllow, AReason);
  if not LAllow then
  begin
    if Trim(AReason) = '' then
      AReason := 'Connection rejected by server policy';
    Result := False;
  end;
end;

// Variant of CreateErrorResponse with a 'data' object (takes ownership of AData).
function TAiMCPLogicServer.CreateErrorResponseWithData(const RequestID: TValue; ErrorCode: Integer;
  const ErrorMessage: string; AData: TJSONObject): string;
var
  JSONResponse, ErrorObj: TJSONObject;
begin
  JSONResponse := TJSONObject.Create;
  try
    JSONResponse.AddPair('jsonrpc', '2.0');
    ErrorObj := TJSONObject.Create;
    ErrorObj.AddPair('code', TJSONNumber.Create(ErrorCode));
    ErrorObj.AddPair('message', ErrorMessage);
    if Assigned(AData) then
      ErrorObj.AddPair('data', AData);
    JSONResponse.AddPair('error', ErrorObj);
    AddRequestIDToResponse(JSONResponse, RequestID);
    Result := JSONResponse.ToJSON;
  finally
    JSONResponse.Free;
  end;
end;

// Annotates a result with the fields required by spec 2026-07-28: resultType
// ('complete' unless the method has already set it) and serverInfo inside _meta.
procedure TAiMCPLogicServer.DecorateModernResult(AResult: TJSONObject);
var
  MetaVal: TJSONValue;
  MetaObj, ServerInfo: TJSONObject;
begin
  if not Assigned(AResult) then
    Exit;
  if not Assigned(AResult.GetValue('resultType')) then
    AResult.AddPair('resultType', 'complete');
  MetaVal := AResult.GetValue('_meta');
  if not Assigned(MetaVal) then
  begin
    MetaObj := TJSONObject.Create;
    AResult.AddPair('_meta', MetaObj);
  end
  else if MetaVal is TJSONObject then
    MetaObj := TJSONObject(MetaVal)
  else
    Exit;
  if not Assigned(MetaObj.GetValue(MCP_META_SERVER_INFO)) then
  begin
    ServerInfo := TJSONObject.Create;
    ServerInfo.AddPair('name', FServerName);
    ServerInfo.AddPair('version', FServerVersion);
    MetaObj.AddPair(MCP_META_SERVER_INFO, ServerInfo);
  end;
end;

// ttlMs/cacheScope (CacheableResult interface from spec 2026-07-28) in the
// cacheable results: freshness hints so the client reduces polling.
class procedure TAiMCPLogicServer.AddCacheHints(AResult: TJSONObject; ATtlMs: Integer);
begin
  if not Assigned(AResult.GetValue('ttlMs')) then
    AResult.AddPair('ttlMs', TJSONNumber.Create(ATtlMs));
  if not Assigned(AResult.GetValue('cacheScope')) then
    AResult.AddPair('cacheScope', 'private');
end;

// MCP 2026-07-28: discovery without handshake. Returns supported versions,
// capabilities and server identity. It also works as a probe for
// compatibility for dual-era clients (a legacy server responds -32601).
function TAiMCPLogicServer.Core_ServerDiscover(const Params: TJSONObject): TValue;
var
  ResultJSON, Capabilities, MetaObj, ServerInfo: TJSONObject;
  Versions: TJSONArray;
  CliName, CliVersion, CliProto, VetReason: string;
begin
  // Opt-in vetting with the _meta identity: modern equivalent of the vetting
  // that Core_Initialize applies in the legacy handshake.
  CliProto := GetModernProtocolVersion(Params);
  GetClientInfoFromMeta(Params, CliName, CliVersion);
  if not VetClientAllowed(CliName, CliVersion, CliProto, VetReason) then
    raise Exception.Create(VetReason);

  ResultJSON := TJSONObject.Create;
  ResultJSON.AddPair('resultType', 'complete');
  Versions := TJSONArray.Create;
  Versions.Add(MCP_PROTOCOL_VERSION_MODERN);
  if FProtocolVersion <> MCP_PROTOCOL_VERSION_MODERN then
    Versions.Add(FProtocolVersion); // la version legacy sigue disponible via initialize
  ResultJSON.AddPair('supportedVersions', Versions);
  Capabilities := TJSONObject.Create;
  Capabilities.AddPair('tools', TJSONObject.Create);
  Capabilities.AddPair('resources', TJSONObject.Create);
  ResultJSON.AddPair('capabilities', Capabilities);
  MetaObj := TJSONObject.Create;
  ServerInfo := TJSONObject.Create;
  ServerInfo.AddPair('name', FServerName);
  ServerInfo.AddPair('version', FServerVersion);
  MetaObj.AddPair(MCP_META_SERVER_INFO, ServerInfo);
  ResultJSON.AddPair('_meta', MetaObj);
  AddCacheHints(ResultJSON, 3600000); // server identity changes little: 1 hour
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

function TAiMCPLogicServer.Tools_ListTools: TValue;
var
  ResultJSON, ToolJSON: TJSONObject;
  ToolsArray: TJSONArray;
  Tool: IAiMCPTool;
  Schema: TJSONObject;
  Names: TArray<string>;
  ToolName: string;
begin
  ResultJSON := TJSONObject.Create;
  ToolsArray := TJSONArray.Create;
  ResultJSON.AddPair('tools', ToolsArray);
  // Spec 2026-07-28: deterministic order (by name) so that clients
  // can cache the list and improve the LLM prompt cache hit rate.
  Names := FActiveTools.Keys.ToArray;
  TArray.Sort<string>(Names);
  for ToolName in Names do
  begin
    Tool := FActiveTools[ToolName];
    ToolJSON := TJSONObject.Create;
    ToolJSON.AddPair('name', Tool.Name);
    ToolJSON.AddPair('description', Tool.Description);
    // GetInputSchema returns a new schema (see IAiMCPTool): AddPair takes
    // ownership. Cloning it, as was done, lost the original on every tools/list
    // (MCP server that grew in memory with every request).
    Schema := Tool.GetInputSchema;
    if Assigned(Schema) then
      ToolJSON.AddPair('inputSchema', Schema)
    else
      ToolJSON.AddPair('inputSchema', TJSONObject.Create);
    ToolsArray.AddElement(ToolJSON);
  end;
  AddCacheHints(ResultJSON, 60000); // spec 2026-07-28: tools/list is CacheableResult
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

// Builds the JSON-RPC for notifications/progress according to the MCP spec.
// ATokenJson is the raw progressToken value ("abc" or 42) to preserve its type.
function TAiMCPLogicServer.BuildProgressNotification(const ATokenJson: string; AProgress, ATotal: Double; const AMessage: string): string;
var
  Root, ParamsObj: TJSONObject;
  TokenVal: TJSONValue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('jsonrpc', '2.0');
    Root.AddPair('method', 'notifications/progress');
    ParamsObj := TJSONObject.Create;
    Root.AddPair('params', ParamsObj);

    TokenVal := TJSONObject.ParseJSONValue(ATokenJson);
    if not Assigned(TokenVal) then
      TokenVal := TJSONString.Create(ATokenJson);
    ParamsObj.AddPair('progressToken', TokenVal);

    ParamsObj.AddPair('progress', TJSONNumber.Create(AProgress));
    if ATotal > 0 then
      ParamsObj.AddPair('total', TJSONNumber.Create(ATotal));
    if AMessage <> '' then
      ParamsObj.AddPair('message', AMessage);

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TAiMCPLogicServer.Tools_CallTool(const Params: TJSONObject; const ASessionID: string; const AAuthContext: TAiAuthContext): TValue;
var
  ToolName: string;
  Arguments: TJSONObject;
  Tool: IAiMCPTool;
  ResultJSON: TJSONObject;
  MetaObj: TJSONObject;
  TokenVal: TJSONValue;
  TokenJson, SessionForProgress: string;
  ExecContext: TAiAuthContext;
begin
  if not Assigned(Params) then
    raise Exception.CreateHelp('Invalid params for tools/call. Expected a JSON object.', JSONRPC_INVALID_PARAMS);

  ToolName := Params.GetValue<string>('name', '');
  Arguments := Params.GetValue<TJSONObject>('arguments', nil);

  if ToolName = '' then
    raise Exception.CreateHelp('Invalid params: Tool "name" not provided in tools/call', JSONRPC_INVALID_PARAMS);

  // MCP progress: if the client sent _meta.progressToken and the transport
  // supports notifications, the tool receives OnProgress in its AuthContext.
  ExecContext := AAuthContext;

  // MCP 2026-07-28 (MRTR): if it is a retry, inputResponses/requestState
  // travel as siblings of name/arguments in params and are delivered to the tool
  // via AuthContext. The object belongs to the request: the tool does not free it.
  ExecContext.InputResponses := Params.GetValue<TJSONObject>('inputResponses', nil);
  ExecContext.RequestState := Params.GetValue<string>('requestState', '');

  TokenJson := '';
  MetaObj := Params.GetValue<TJSONObject>('_meta', nil);
  if Assigned(MetaObj) then
  begin
    TokenVal := MetaObj.GetValue('progressToken');
    if Assigned(TokenVal) and not(TokenVal is TJSONNull) then
      TokenJson := TokenVal.ToJSON; // preserves string or number type
  end;

  if (TokenJson <> '') and Assigned(FOnSendNotification) then
  begin
    SessionForProgress := ASessionID;
    ExecContext.OnProgress :=
      procedure(AProgress, ATotal: Double; const AMessage: string)
      begin
        try
          FOnSendNotification(SessionForProgress, BuildProgressNotification(TokenJson, AProgress, ATotal, AMessage));
        except
          // Progress is best-effort: it must never bring down tool execution.
        end;
      end;
  end;

  if FActiveTools.TryGetValue(ToolName, Tool) then
  begin
    // Telemetry: span per tool execution, nested under the request span
    var LSpan := AiSpanStart('mcp.tool ' + ToolName);
    AiSpanAttr(LSpan, 'gen_ai.tool.name', ToolName);
    AiSpanAttr(LSpan, 'mcp.mrtr.retry', Assigned(ExecContext.InputResponses));
    try
      ResultJSON := Tool.Execute(Arguments, ExecContext);
      AiSpanEnd(LSpan);
    except
      on E: Exception do
      begin
        AiSpanEnd(LSpan, E.Message);
        raise;
      end;
    end;
  end
  else
    raise Exception.CreateFmt('Tool not found: %s', [ToolName]);

  // Pass the resulting TJSONObject to TValue
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

function TAiMCPLogicServer.Resources_ListResources: TValue;
var
  ResultJSON, ResourceObj: TJSONObject;
  ResourcesArray: TJSONArray;
  Resource: IAiMCPResource;
  URIs: TArray<string>;
  URI: string;
begin
  ResultJSON := TJSONObject.Create;
  ResourcesArray := TJSONArray.Create;
  ResultJSON.AddPair('resources', ResourcesArray);
  // Spec 2026-07-28: deterministic order (by URI), same as tools/list.
  URIs := FActiveResources.Keys.ToArray;
  TArray.Sort<string>(URIs);
  for URI in URIs do
  begin
    Resource := FActiveResources[URI];
    ResourceObj := TJSONObject.Create;
    ResourceObj.AddPair('uri', Resource.URI);
    ResourceObj.AddPair('name', Resource.Name);
    ResourceObj.AddPair('description', Resource.Description);
    ResourceObj.AddPair('mimeType', Resource.MimeType);
    ResourcesArray.AddElement(ResourceObj);
  end;
  AddCacheHints(ResultJSON, 60000); // spec 2026-07-28: resources/list is CacheableResult
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

function TAiMCPLogicServer.Resources_ReadResource(const Params: TJSONObject): TValue;
var
  URI, ResourceText: string;
  ResultJSON, ContentItem: TJSONObject;
  ContentsArray: TJSONArray;
  Resource: IAiMCPResource;
begin
  if not Assigned(Params) then
    raise Exception.CreateHelp('Invalid params for resources/read. Expected a JSON object.', JSONRPC_INVALID_PARAMS);

  URI := Params.GetValue<string>('uri', '');
  if URI = '' then
    raise Exception.CreateHelp('Invalid params: Resource "uri" not provided in resources/read', JSONRPC_INVALID_PARAMS);

  ResultJSON := TJSONObject.Create;
  ContentsArray := TJSONArray.Create;
  ResultJSON.AddPair('contents', ContentsArray);
  ContentItem := TJSONObject.Create;
  ContentsArray.AddElement(ContentItem);

  if FActiveResources.TryGetValue(URI, Resource) then
  begin
    ContentItem.AddPair('uri', Resource.URI);
    ContentItem.AddPair('mimeType', Resource.MimeType);
    try
      ResourceText := Resource.Read;
      ContentItem.AddPair('text', ResourceText);
    except
      on E: Exception do
        raise Exception.Create('Error reading resource: ' + E.Message);
    end;
  end
  else
  begin
    raise Exception.CreateFmt('Resource not found: %s', [URI]);
  end;
  AddCacheHints(ResultJSON, 60000); // spec 2026-07-28: resources/read is CacheableResult
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

function TAiMCPLogicServer.Resources_ListTemplates: TValue;
var
  ResultJSON: TJSONObject;
  TemplatesArray: TJSONArray;
begin
  ResultJSON := TJSONObject.Create;
  TemplatesArray := TJSONArray.Create;
  ResultJSON.AddPair('resourceTemplates', TemplatesArray);
  AddCacheHints(ResultJSON, 60000); // spec 2026-07-28: resources/templates/list is CacheableResult
  Result := TValue.From<TJSONObject>(ResultJSON);
end;

// -----------------------------------------------------------------------------
// --- TInternalSchemaGenerator Implementation ---
// -----------------------------------------------------------------------------

{ class function TInternalSchemaGenerator.GenerateSchema(Cls: TClass): TJSONObject;
  var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Properties, PropSchema: TJSONObject;
  RequiredArray, EnumArray: TJSONArray;
  JsonName: string;
  RttiProp: TRttiProperty;
  Attr: TCustomAttribute;
  begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Properties := TJSONObject.Create;
  Result.AddPair('properties', Properties);
  RequiredArray := TJSONArray.Create;
  Result.AddPair('required', RequiredArray);

  RttiContext := TRttiContext.Create;
  try
  RttiType := RttiContext.GetType(Cls);
  for RttiProp in RttiType.GetProperties do
  begin
  if RttiProp.Visibility in [mvPublic, mvPublished] then
  begin
  JsonName := GetPropertyJsonName(RttiProp);
  PropSchema := TJSONObject.Create;
  Properties.AddPair(JsonName, PropSchema);
  PropSchema.AddPair('type', GetJsonTypeFromRttiType(RttiProp.PropertyType));

  for Attr in RttiProp.GetAttributes do
  begin
  if Attr is AiMCPSchemaDescriptionAttribute then
  PropSchema.AddPair('description', (Attr as AiMCPSchemaDescriptionAttribute).Description)
  else if Attr is AiMCPSchemaEnumAttribute then
  begin
  EnumArray := TJSONArray.Create;
  for var Value in (Attr as AiMCPSchemaEnumAttribute).Values do
  EnumArray.Add(Value);
  PropSchema.AddPair('enum', EnumArray);
  end;
  end;

  if IsRequiredProperty(RttiProp) then
  RequiredArray.Add(JsonName);
  end;
  end;
  finally
  RttiContext.Free;
  end;
  end;
}

class function TInternalSchemaGenerator.GenerateSchema(Cls: TClass): TJSONObject;
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Properties, PropSchema: TJSONObject;
  RequiredArray, EnumArray: TJSONArray;
  JsonName: string;
  RttiProp: TRttiProperty;
  Attr: TCustomAttribute;
  PropTypeStr: string;
  // New variables to handle arrays
  DynArrayType: TRttiDynamicArrayType;
  ElementType: TRttiType;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Properties := TJSONObject.Create;
  Result.AddPair('properties', Properties);
  RequiredArray := TJSONArray.Create;
  Result.AddPair('required', RequiredArray);

  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.GetType(Cls);
    for RttiProp in RttiType.GetProperties do
    begin
      if RttiProp.Visibility in [mvPublic, mvPublished] then
      begin
        JsonName := GetPropertyJsonName(RttiProp);
        PropSchema := TJSONObject.Create;
        Properties.AddPair(JsonName, PropSchema);

        // 1. Get the base type
        PropTypeStr := GetJsonTypeFromRttiType(RttiProp.PropertyType);
        PropSchema.AddPair('type', PropTypeStr);

        // 2. Specific logic for Arrays (NEW)
        if PropTypeStr = 'array' then
        begin
          if RttiProp.PropertyType is TRttiDynamicArrayType then
          begin
            DynArrayType := TRttiDynamicArrayType(RttiProp.PropertyType);
            ElementType := DynArrayType.ElementType;

            // Define what is inside the array (items)
            var
            ItemsObj := TJSONObject.Create;
            ItemsObj.AddPair('type', GetJsonTypeFromRttiType(ElementType));
            PropSchema.AddPair('items', ItemsObj);
          end
          else
          begin
            // Fallback in case it is a static array or another unsupported complex type
            var
            ItemsObj := TJSONObject.Create;
            ItemsObj.AddPair('type', 'string');
            PropSchema.AddPair('items', ItemsObj);
          end;
        end;

        // 3. Handling of attributes (Description and Enums) - (Same as before)
        for Attr in RttiProp.GetAttributes do
        begin
          if Attr is AiMCPSchemaDescriptionAttribute then
            PropSchema.AddPair('description', (Attr as AiMCPSchemaDescriptionAttribute).Description)
          else if Attr is AiMCPSchemaEnumAttribute then
          begin
            EnumArray := TJSONArray.Create;
            for var Value in (Attr as AiMCPSchemaEnumAttribute).Values do
              EnumArray.Add(Value);
            PropSchema.AddPair('enum', EnumArray);
          end;
        end;

        if IsRequiredProperty(RttiProp) then
          RequiredArray.Add(JsonName);
      end;
    end;
  finally
    RttiContext.Free;
  end;
end;

class function TInternalSchemaGenerator.GetJsonTypeFromRttiType(RttiType: TRttiType): string;
begin
  case RttiType.TypeKind of
    tkInteger, tkInt64:
      Result := 'integer';
    tkFloat:
      Result := 'number';
    tkString, tkLString, tkWString, tkUString:
      Result := 'string';
    tkEnumeration:
      if RttiType.Name = 'Boolean' then
        Result := 'boolean'
      else
        Result := 'string';
    tkClass:
      Result := 'object';
    tkDynArray, tkArray:
      Result := 'array';
  else
    Result := 'string';
  end;
end;

class function TInternalSchemaGenerator.GetPropertyJsonName(Prop: TRttiProperty): string;
begin
  Result := LowerCase(Prop.Name[1]) + Copy(Prop.Name, 2, Length(Prop.Name));
end;

class function TInternalSchemaGenerator.IsRequiredProperty(Prop: TRttiProperty): Boolean;
{$IF CompilerVersion < 35}
var
  Arr: TArray<TCustomAttribute>;
  I: Integer;
begin
  Arr := Prop.GetAttributes;
  Result := False;
  for I := Low(Arr) to High(Arr) do
    Result := Result or (Arr[I] is AiMCPOptionalAttribute);
  Result := not Result;
end;
{$ELSE}
begin
  Result := not Prop.HasAttribute<AiMCPOptionalAttribute>;
end;
{$ENDIF}

// -----------------------------------------------------------------------------
// --- TInternalSerializer Implementation ---
// -----------------------------------------------------------------------------

class constructor TInternalSerializer.Create;
begin
  FContext := TRttiContext.Create;
end;

class destructor TInternalSerializer.Destroy;
begin
  FContext.Free;
end;

class procedure TInternalSerializer.DeserializeObject(Instance: TObject; const JSON: TJSONObject);
var
  RttiType: TRttiType;
  PropName: string;
  JsonValue: TJSONValue;
  PropValue: TValue;
  RttiProp: TRttiProperty;
begin
  RttiType := FContext.GetType(Instance.ClassType);
  for RttiProp in RttiType.GetProperties do
  begin
    if not RttiProp.IsWritable then
      Continue;

    PropName := TInternalSchemaGenerator.GetPropertyJsonName(RttiProp);
    JsonValue := JSON.GetValue(PropName);

    if Assigned(JsonValue) then
    begin
      PropValue := ConvertJsonToValue(JsonValue, RttiProp.PropertyType);
      if not PropValue.IsEmpty then
        RttiProp.SetValue(Instance, PropValue);
    end;
  end;
end;

class function TInternalSerializer.ConvertJsonToValue(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
begin
  Result := TValue.Empty;
  if (JsonValue = nil) or (JsonValue is TJSONNull) then
    Exit;

  case RttiType.TypeKind of
    tkInteger, tkInt64:
      if JsonValue is TJSONNumber then
        Result := (JsonValue as TJSONNumber).AsInt64
      else
        raise EConversionError.CreateFmt('JSON value for an integer property is not a number: %s', [JsonValue.ToString]);

    tkFloat:
      if JsonValue is TJSONNumber then
        Result := (JsonValue as TJSONNumber).AsDouble
      else
        raise EConversionError.CreateFmt('JSON value for a float property is not a number: %s', [JsonValue.ToString]);

    tkString, tkUString, tkWString, tkLString:
      if JsonValue is TJSONString then
        Result := (JsonValue as TJSONString).Value
      else
        Result := JsonValue.Value;

    tkEnumeration:
      if RttiType.Handle = TypeInfo(Boolean) then
      begin
        if JsonValue is TJSONBool then
          Result := (JsonValue as TJSONBool).AsBoolean
        else
          raise EConversionError.CreateFmt('JSON value for a boolean property is not a boolean: %s', [JsonValue.ToString]);
      end
      else
      begin
        if JsonValue is TJSONString then
          Result := TValue.FromOrdinal(RttiType.Handle, GetEnumValue(RttiType.Handle, (JsonValue as TJSONString).Value))
        else
          raise EConversionError.CreateFmt('JSON value for an enum property is not a string: %s', [JsonValue.ToString]);
      end;
  end;
end;


// -----------------------------------------------------------------------------
// --- TAiMCPResponseBuilder Implementation ---
// -----------------------------------------------------------------------------

constructor TAiMCPResponseBuilder.Create;
begin
  inherited;
  FContentArray := TJSONArray.Create;
end;

destructor TAiMCPResponseBuilder.Destroy;
begin
  FContentArray.Free;
  inherited;
end;

class function TAiMCPResponseBuilder.New: TAiMCPResponseBuilder;
begin
  Result := TAiMCPResponseBuilder.Create;
end;

function TAiMCPResponseBuilder.AddText(const AText: string): TAiMCPResponseBuilder;
var
  LTextItem: TJSONObject;
begin
  Result := Self;
  LTextItem := TJSONObject.Create;
  LTextItem.AddPair('type', 'text');
  LTextItem.AddPair('text', AText);
  FContentArray.AddElement(LTextItem);
end;

function TAiMCPResponseBuilder.AddFile(const AFilePath: string; AFileName: string = ''): TAiMCPResponseBuilder;
var
  LFileStream: TFileStream;
  LMimeType: string;
begin
  Result := Self;
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('File not found: %s', [AFilePath]);

  LMimeType := GetMimeTypeFromFile(AFilePath);
  if AFileName = '' then
    AFileName := TPath.GetFileName(AFilePath);

  LFileStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    AddFileFromStream(LFileStream, AFileName, LMimeType);
  finally
    LFileStream.Free;
  end;
end;

function TAiMCPResponseBuilder.AddFileFromStream(AStream: TStream; const AFileName: string; const AMimeType: string): TAiMCPResponseBuilder;
var
  LFileItem: TJSONObject;
  LBytes: TBytes;
  LBase64: string;
  LType: string;
begin
  Result := Self;
  AStream.Position := 0;
  SetLength(LBytes, AStream.Size);
  AStream.ReadBuffer(LBytes, Length(LBytes));

  LBase64 := TNetEncoding.Base64.EncodeBytesToString(LBytes);

  LFileItem := TJSONObject.Create;

  // Map the MimeType to the 'type' expected by the client
  if StartsText('image/', AMimeType) then
    LType := 'image'
  else if StartsText('audio/', AMimeType) then
    LType := 'audio'
  else if StartsText('video/', AMimeType) then
    LType := 'video'
  else if SameText(AMimeType, 'application/pdf') then
    LType := 'document'
  else
    LType := 'binary'; // A generic type

  LFileItem.AddPair('type', LType);
  LFileItem.AddPair('mimeType', AMimeType);
  LFileItem.AddPair('data', LBase64);
  LFileItem.AddPair('fileName', AFileName); // Opcional, pero buena pr?ctica

  FContentArray.AddElement(LFileItem);
end;

function TAiMCPResponseBuilder.Build: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('content', FContentArray.Clone as TJSONArray);
end;

{ TAiMCPServer }

constructor TAiMCPServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEndPoint := '/mcp';
  FActive := False;
  FLogicServer := TAiMCPLogicServer.Create;
end;

procedure TAiMCPServer.CreateDefaultSettingsFile;
begin
  FLogicServer.CreateDefaultSettingsFile
end;

destructor TAiMCPServer.Destroy;
begin
  Stop;
  FLogicServer.Free;
  inherited Destroy;
end;

function TAiMCPServer.GetEndpoint: string;
begin
  Result := FEndPoint;
end;

function TAiMCPServer.GetPort: Integer;
begin
  Result := FLogicServer.Port;
end;

function TAiMCPServer.EffectiveBindAddress: string;
begin
  Result := Trim(FBindAddress);
  if Result = '' then
    Result := Trim(GetEnvironmentVariable('MCP_BIND_ADDRESS'));
end;

function TAiMCPServer.GetServerName: String;
begin
  Result := FServerName;
end;

function TAiMCPServer.GetServerVersion: String;
begin
  Result := FLogicServer.ServerVersion;
end;

procedure TAiMCPServer.SetServerVersion(const Value: String);
begin
  FLogicServer.ServerVersion := Value;
end;

function TAiMCPServer.GetOnClientConnect: TAiMCPClientConnectEvent;
begin
  Result := FLogicServer.OnClientConnect;
end;

procedure TAiMCPServer.SetOnClientConnect(const Value: TAiMCPClientConnectEvent);
begin
  FLogicServer.OnClientConnect := Value;
end;

function TAiMCPServer.GetOnUnauthorizedRequest: TAiMCPUnauthorizedEvent;
begin
  Result := FLogicServer.OnUnauthorizedRequest;
end;

procedure TAiMCPServer.SetOnUnauthorizedRequest(const Value: TAiMCPUnauthorizedEvent);
begin
  FLogicServer.OnUnauthorizedRequest := Value;
end;

function TAiMCPServer.GetSettingsFile: String;
begin
  Result := FLogicServer.SettingsFile;
end;

function TAiMCPServer.GetUser: String;
begin
  Result := FLogicServer.User;
end;

procedure TAiMCPServer.InternalRegisterOneFunction(AItem: TFunctionActionItem);
begin
  // Each call to this method creates its own capture frame on the heap.
  // The closure captures AItem from this frame, not from the parent loop.
  // This way each factory has its own independent TFunctionActionItem.
  RegisterTool(AItem.FunctionName,
    function: IAiMCPTool
    begin
      Result := TTAiFunctionToolProxy.Create(FAiFunctions, AItem);
    end);
end;

procedure TAiMCPServer.InternalRegisterFromAiFunctions;
var
  I: Integer;
begin
  if not Assigned(FAiFunctions) then
    Exit;

  for I := 0 to FAiFunctions.Functions.Count - 1 do
    if FAiFunctions.Functions[I].Enabled then
      InternalRegisterOneFunction(FAiFunctions.Functions[I]);
end;

procedure TAiMCPServer.LoadSettingsDefaults;
begin
  FLogicServer.LoadSettingsDefaults;
end;

procedure TAiMCPServer.LoadSettingsFromFile;
begin
  FLogicServer.LoadSettingsFromFile;
end;

procedure TAiMCPServer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  // If the operation is remove (opRemove) and the component is the one we have stored
  if (Operation = opRemove) and (AComponent = FAiFunctions) then
  begin
    // We safely set the reference to NIL
    FAiFunctions := nil;

    // Optional: If the server was active and depended on these functions,
    // you could decide to stop it or simply log a warning.
    if FActive then
    begin
      // You could call Stop; if you consider that without functions the server should not continue.
    end;
  end;
end;

procedure TAiMCPServer.RegisterResource(const URI: string; Factory: TAiMCPResourceFactory);
begin
  FLogicServer.RegisterResource(URI, Factory);
end;

procedure TAiMCPServer.RegisterTool(const Name: string; Factory: TAiMCPToolFactory);
begin
  FLogicServer.RegisterTool(Name, Factory)
end;

procedure TAiMCPServer.SetActive(const Value: Boolean);
begin
  FActive := Value;
end;

procedure TAiMCPServer.SetAiFunctions(const Value: TAiFunctions);
begin
  if FAiFunctions <> Value then
  begin
    FAiFunctions := Value;

    // If a component is assigned, we ask it to notify us of its destruction
    if Assigned(FAiFunctions) then
      FAiFunctions.FreeNotification(Self);
  end;
end;

function TAiMCPServer.ValidateRequest(const AAuthHeader, ARemoteIP: string; out AAuthContext: TAiAuthContext): Boolean;
var
  ProvidedKey: string;
begin
  Result := True;
  AAuthContext := Default(TAiAuthContext);

  // Layer 1: API Key validation
  if FApiKey <> '' then
  begin
    // Extract key from "Bearer <key>" or direct value
    if AAuthHeader.StartsWith('Bearer ', True) then
      ProvidedKey := Trim(Copy(AAuthHeader, 8, Length(AAuthHeader)))
    else
      ProvidedKey := Trim(AAuthHeader);

    if not SameStr(ProvidedKey, FApiKey) then
    begin
      Result := False;
      Exit;
    end;

    AAuthContext.IsAuthenticated := True;
    AAuthContext.UserID := FLogicServer.User;
  end;

  // Layer 2: Custom validation event (JWT, OAuth, DB lookup, etc.)
  if Assigned(FOnValidateRequest) then
    FOnValidateRequest(Self, AAuthHeader, ARemoteIP, AAuthContext, Result)
  else if FApiKey = '' then
  begin
    // Without API Key or event -> backward compatible (allow everything)
    AAuthContext.IsAuthenticated := True;
    AAuthContext.UserID := FLogicServer.User;
  end;
end;

procedure TAiMCPServer.SetPort(const Value: Integer);
begin
  FLogicServer.Port := Value;
end;

procedure TAiMCPServer.SetServerName(const Value: String);
begin
  If Value <> FServerName then
  Begin
    FServerName := Value;
    FLogicServer.ServerName := Value;
  End;
end;

procedure TAiMCPServer.SetSettingsFile(const Value: String);
begin
  FLogicServer.SettingsFile := Value;
end;

procedure TAiMCPServer.SetUser(const Value: String);
begin
  FLogicServer.User := Value;
end;

procedure TAiMCPServer.Start;
begin
  if FActive then
    Exit;

  // 1. KEY STEP: Before starting the LogicServer, we register
  // automatically the functions of the linked component.
  InternalRegisterFromAiFunctions;

  // 2. Start the logic engine (which will instantiate the Proxies created above)
  FLogicServer.Start;

  FActive := True;
end;

procedure TAiMCPServer.Stop;
begin
  if not FActive then
    Exit;
  FLogicServer.Stop;
  FActive := False;
end;

end.
