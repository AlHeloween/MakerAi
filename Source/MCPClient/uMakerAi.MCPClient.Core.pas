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

unit uMakerAi.MCPClient.Core;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.IOUtils, System.Net.URLClient, System.NetEncoding,
  System.Net.HttpClient, System.Net.Mime, System.Net.HttpClientComponent,
  System.Threading, System.Diagnostics, System.Types, System.SyncObjs,

{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
{$IFDEF POSIX}
{$ENDIF}
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Utils.System, uMakerAi.Core;

// --- Abstract Base Class ---
const
  // --- MCP 2026-07-28 (modo stateless / dual-era) ---
  // Modern protocol version: without initialize handshake or sessions; each
  // request travels with its version and identity in _meta.
  MCP_PROTOCOL_VERSION_MODERN = '2026-07-28';
  // Internal marker: the server responded as legacy (initialize handshake).
  MCP_PROTOCOL_LEGACY = 'legacy';
  // Standardized _meta keys. NOTE: they contain dots in the name, so
  // they must be read with GetValue(exact name), never with path variants.
  MCP_META_PROTOCOL_VERSION = 'io.modelcontextprotocol/protocolVersion';
  MCP_META_CLIENT_INFO = 'io.modelcontextprotocol/clientInfo';
  MCP_META_CLIENT_CAPABILITIES = 'io.modelcontextprotocol/clientCapabilities';
  MCP_META_SERVER_INFO = 'io.modelcontextprotocol/serverInfo';
  // Error codes in the MCP reserved range (-32020..-32099)
  MCP_ERROR_HEADER_MISMATCH = -32020;
  MCP_ERROR_UNSUPPORTED_PROTOCOL_VERSION = -32022;
  // Maximum rounds of the MRTR pattern (input_required -> retry) per tool call
  MCP_MRTR_MAX_ROUNDS = 3;

type

  EMCPClientException = class(Exception);
  TMCPStreamMessageEvent = procedure(Sender: TObject; const EventType, Data: string) of object;

  // Progress callback of an MCP tool (server notifications/progress).
  // NOTE: it is called from the SSE reader thread — the handler must be thread-safe.
  TMCPToolProgressProc = reference to procedure(AProgress, ATotal: Double; const AMessage: string);

  // Billing callback: it is called after each successful CallTool with the tool name.
  TMCPToolBillingProc = reference to procedure(const AToolName: string);

  // MCP 2026-07-28 (MRTR pattern): the server replied with resultType='input_required'.
  // The handler must populate AInputResponses (id->result map, e.g., ElicitResult
  // {"action":"accept","content":{...}}) from AInputRequests (map
  // id->request; can be nil if the server only asks for retry with requestState).
  // AHandled=False cancels the retry. Both objects belong to the client:
  // DO NOT free them in the handler.
  TMCPInputRequiredEvent = procedure(Sender: TObject; const AToolName: string;
    AInputRequests, AInputResponses: TJSONObject; var AHandled: Boolean) of object;

  TMCPClientCustom = class(TComponent)
  private
    FName: string;
    FOnLog: TMCPLogEvent;
    FOnStatusUpdate: TMCPStatusEvent;
    FTransportType: TToolTransportType;
    FInitialized: Boolean;
    FEnabled: Boolean;
    FTools: TStrings;
    FAvailable: Boolean;
    // FURL: string;
    // FTimeout: Integer;
    FParams: TStrings;
    FEnvVars: TStrings;
    FDisabledFunctions: TStrings;
    FURL: String;
    FServerProcess: TInteractiveProcessInfo;
    FOwnsServerProcess: Boolean;
    FOnStreamMessage: TMCPStreamMessageEvent;
    FCallLock: TCriticalSection;  // Serializes concurrent calls to the same server
    procedure SetTransportType(const Value: TToolTransportType);
    procedure SetAvailable(const Value: Boolean);
    procedure SetEnabled(const Value: Boolean);
    procedure SetInitialized(const Value: Boolean);
    procedure SetParams(const Value: TStrings);
    // procedure SetDisabledFunctions(const Value: TStrings);
    function GetParams: TStrings;
    // procedure SetCommand(const Value: string);
    function GetEnvVars: TStrings;
    procedure SetEnvVars(const Value: TStrings);
    procedure SetURL(const Value: String);
  protected
    // Configuration properties
    // FCommand: string;
    // FArguments: string;
    // FRootDirectory: string;

    // Methods to fire events
    FLastError: String;
    FBusy: Boolean;
    // --- MCP 2026-07-28 (dual-era) ---
    // '' = not probed; MCP_PROTOCOL_VERSION_MODERN = modern server
    // (stateless); MCP_PROTOCOL_LEGACY = server with initialize handshake.
    FNegotiatedProtocol: string;
    // MRTR: elicitation/input_required handler (opt-in)
    FOnInputRequired: TMCPInputRequiredEvent;
    function IsModernMode: Boolean;
    function BuildModernMeta: TJSONObject;
    procedure AttachModernMeta(AParams: TJSONObject);
    class function IsModernErrorCode(ACode: Integer): Boolean; static;
    // MRTR: True if AResult is an InputRequiredResult; extracts inputRequests
    // (pointer INSIDE AResult, do not free) and requestState.
    class function TryGetInputRequired(AResult: TJSONObject;
      out AInputRequests: TJSONObject; out ARequestState: string): Boolean; static;
    procedure DoLog(const Msg: string); virtual;
    procedure DoStatusUpdate(const StatusMsg: string); virtual;
    function IsBinaryContentType(const ContentType: string): Boolean;

    function ProcessAndExtractMedia(const AJsonResult: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
    // procedure ParamsChanged(Sender: TObject);

    function InternalStartLocalServerProcess: Boolean; Virtual;
    procedure InternalStopLocalServerProcess; Virtual;
    procedure DoStreamMessage(const EventType, Data: string); virtual;

  public
    constructor Create(AOwner: TComponent); override;
    Destructor Destroy; Override;
    Function GetParamByName(ParamName: String): String;
    Function GetDefaultParams: TStringList; Virtual;

    // The initialization function will try to connect to the server and obtain the list of tools (ListTools) and store?
    // the information in the Tools : TStrings property which is read-only.  This is done to avoid making the call
    // to the function every time the tool list is needed, saving time and connection resources.
    // It also sets the initialized property to true to indicate it has been tested.
    // if the server fails during initialization, it sets Enabled = False, otherwise

    Function Initialize: Boolean; Virtual;

    // Main public methods (full lifecycle)
    // They are virtual and abstract because their implementation depends on the protocol
    function ListTools: TJSONObject; virtual;
    function CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; virtual;
    function CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; virtual;

    // Disconnects the server (persistent connection Option D). Call to
    // free resources when the server is no longer needed.
    procedure Disconnect; virtual;

    // Public properties
    property Name: string read FName write FName;
    // property Command: string read FCommand write SetCommand;
    // property Arguments: string read FArguments write FArguments;
    // property RootDirectory: string read FRootDirectory write FRootDirectory;
    Property TransportType: TToolTransportType read FTransportType write SetTransportType;
    // property URL: string read FURL write FURL;
    // property Timeout: Integer read FTimeout write FTimeout;

    Property Tools: TStrings read FTools; // Read-only property containing ListTools after initialization
    Property Initialized: Boolean read FInitialized write SetInitialized; // Indicates it has been initialized by attempting to obtain ListTools
    Property Enabled: Boolean read FEnabled write SetEnabled; // Property indicating it will be used to build the final tools
    // If it is available after initialization, if initialization failed it stays false.
    Property Available: Boolean read FAvailable write SetAvailable;

    // MCP 2026-07-28: version negotiated with the server after the dual-era probe.
    // Read-only informational ('' = not yet probed).
    property NegotiatedProtocol: string read FNegotiatedProtocol;

    Property Params: TStrings read GetParams write SetParams; // Additional parameters in format ParamName=ParamValue
    Property EnvVars: TStrings read GetEnvVars write SetEnvVars;
    Property URL: String read FURL write SetURL;

    // Property DisabledFunctions: TStrings read FDisabledFunctions write SetDisabledFunctions;
    // List of functions that will not be executed, by default all are valid   format (ModuleName,FunctionName)

    // Public events
    property OnLog: TMCPLogEvent read FOnLog write FOnLog;
    property OnStatusUpdate: TMCPStatusEvent read FOnStatusUpdate write FOnStatusUpdate;
    property OnStreamMessage: TMCPStreamMessageEvent read FOnStreamMessage write FOnStreamMessage;
    // MCP 2026-07-28 (MRTR): if assigned, the client resolves the
    // input_required by retrying the tools/call with the handler's responses
    // (max MCP_MRTR_MAX_ROUNDS rounds). Without a handler, an input_required
    // is reported as a clear error. Assigning it also declares the capability
    // 'elicitation' in _meta.clientCapabilities.
    property OnInputRequired: TMCPInputRequiredEvent read FOnInputRequired write FOnInputRequired;
  end;

  // --- STDI/O Protocol Implementation ---
type
  TMCPClientStdIo = class(TMCPClientCustom)
  private
    FInteractiveProcess: TInteractiveProcessInfo;
    FReadThread: TThread;
    FIncomingMessages: TThreadedQueue<TJSONObject>;
    FIsRunning: Boolean;
    FRequestIDCounter: Integer;

    // Internal methods that perform the individual tasks
    procedure InternalStartServerProcess;
    procedure InternalStopServerProcess;
    function InternalInitialize: TJSONObject;
    procedure InternalSendInitializedNotification;
    // MCP 2026-07-28: dual-era probe (nil = legacy server, fall back to initialize)
    function InternalServerDiscover: TJSONObject;
    function InternalListTools: TJSONObject;
    function InternalCallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;

    // Communication helpers
    procedure InternalSendRawMessage(const AJsonString: string);
    function InternalReceiveJSONResponse(AExpectedID: Integer; ATimeoutMs: Cardinal = 10000): TJSONObject;
    function IsServerRunning: Boolean;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ReadProcessOutput; // Implementation of use still missing

    // Implementation of the public methods (orchestrate the lifecycle)
    function ListTools: TJSONObject; override;
    function CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;
    function CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;

    // Stops the server process and releases the persistent connection
    procedure Disconnect; override;
  end;

  TMCPClientHttp = class(TMCPClientCustom)
  private
    FHttpClient: TNetHTTPClient;
    FRequestIDCounter: Integer;
    FServerCapabilities: TJSONObject;

    // Methods for the MCP handshake
    procedure InternalPerformMCPInitialize;
    procedure InternalSendInitializedNotification;

    // Main method to send JSON-RPC requests via HTTP
    function InternalSendRequest(const AMethod: string; AParams: TJSONObject): TJSONObject;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Initialize: Boolean; override; // We override the base Initialize

    function ListTools: TJSONObject; override;
    function CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;
    function CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;
  end;

  TMCPClientMakerAi = class(TMCPClientCustom)
  private
    // Private field to manage HTTP requests.
    // It will be created in the constructor and automatically freed by the component.
    FHttpClient: TNetHTTPClient;

    // Private helper method. Centralizes all REST API communication logic:
    // - Builds the URL.
    // - Prepares HTTP Basic authentication.
    // - Performs the GET or POST request.
    // - Processes the response, including the "unwrap" of the DataSnap format.
    function InternalSendRequest(const AMethodName, AHttpVerb: string; ABodyStream: TStream): TJSONObject;

  public
    // Standard constructor and destructor of the component.
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Implementation of the abstract methods inherited from TMCPClientCustom.
    // These are the public methods that the rest of the application will use,
    // ensuring that the interface is identical to the other client types.

    // Overrides ListTools to call the API endpoint /listtools.
    function ListTools: TJSONObject; override;

    // Overrides CallTool to call the API endpoints /calltool/{toolname}.
    // Accepts arguments as a TJSONObject.
    function CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;

    // Overload of CallTool that accepts arguments as a TStrings for convenience.
    function CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;
  end;

  TMCPClientSSE = class(TMCPClientCustom)
  private
    FSSEThread: TThread;         // Raw TCP SSE reader thread (replaces TNetHTTPClient async GET)
    FIncomingMessages: TThreadedQueue<TJSONObject>;
    FPostEndpoint: string;
    FRequestIDCounter: Integer;  // only with AtomicIncrement: the pooled client is concurrent
    // Responses that one thread pulled from the queue but belong to ANOTHER in-flight request.
    // Previously they were freed: with two parallel tools/call on the same client
    // the other response was lost and its owner waited for CallToolTimeoutMs (180 s).
    FPendingLock: TCriticalSection;
    FStashedResponses: TObjectDictionary<Integer, TJSONObject>;
    FIsConnected: Boolean;
    FStopRequested: Boolean;
    FAsyncOpDone: Boolean;       // Set when the SSE thread exits; destructor waits on this

    FBuffer: string;

    // --- Tool progress (notifications/progress) ---
    // The same pooled client serves concurrent requests: the handler is
    // registered per calling thread and CallTool associates it with the call's progressToken.
    FProgressLock: TCriticalSection;
    FThreadProgressHandlers: TDictionary<TThreadID, TMCPToolProgressProc>;
    FTokenProgressHandlers: TDictionary<string, TMCPToolProgressProc>;
    FLastProgressTick: Int64; // GetTickCount64 of the last notification received
    // --- Tool billing ---
    // Same per-thread pattern as progress. It is invoked with the tool name after each
    // successful CallTool so the router can count and bill.
    FThreadBillingHandlers: TDictionary<TThreadID, TMCPToolBillingProc>;

    // Internal processing methods
    procedure ProcessSSELine(const ALine: string);
    procedure DispatchProgressNotification(AJson: TJSONObject);

    // Internal communication methods
    function InternalSendRequest(const AMethod: string; AParams: TJSONObject): TJSONObject;
    function InternalReceiveJSONResponse(AExpectedID: Integer; ATimeoutMs: Cardinal = 15000): TJSONObject;
    function WaitForInitialization(ATimeout: Integer): Boolean;

    // Stream control
    procedure StartEventStream;
    procedure StopEventStream;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Initialize: Boolean; override;
    function ListTools: TJSONObject; override;

    function CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;
    function CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject; overload; override;

    // Registers/clears the progress handler for the CallTool that THIS
    // thread. CallTool sends _meta.progressToken and routes notifications/progress
    // from the server to this handler. Call Clear when the request finishes.
    procedure SetThreadProgressHandler(const AHandler: TMCPToolProgressProc);
    procedure ClearThreadProgressHandler;
    // Registers/clears the billing handler (invoked after each successful CallTool).
    procedure SetThreadBillingHandler(const AHandler: TMCPToolBillingProc);
    procedure ClearThreadBillingHandler;
  end;

implementation

uses
  IdTCPClient, IdIOHandler, IdExceptionCore, uMakerAi.Telemetry;


// A token that already carries its authorization scheme ("Basic ..." or "Bearer ...")
// is used as is. It only prepends "Bearer " when the token comes bare, which
// is how it behaved before: existing tokens do not change at all.
//
// It is needed to talk to MCP servers that do not use Bearer. For example, the
// accounting server, which relays the credential to a DataSnap with HTTP Basic.
function ValorDeAutorizacion(const AToken: string): string;
begin
  if AToken.StartsWith('Basic ', True) or AToken.StartsWith('Bearer ', True) then
    Result := AToken
  else
    Result := 'Bearer ' + AToken;
end;

// Portable GetTickCount64: TThread.GetTickCount64 does not exist in Delphi 10.4.
// TStopwatch (System.Diagnostics) is monotonic and available in all
// versions and platforms; it is only used to measure time deltas (timeouts).
function MkGetTickCount64: Int64;
begin
  Result := Int64(TStopwatch.GetTimeStamp) * Int64(1000) div TStopwatch.Frequency;
end;

// ---------------------------------------------------------------------------
// Disk log for shutdown debugging — only with the MAKERAI_MCP_SHUTDOWN_LOG define
// ---------------------------------------------------------------------------
{$IFDEF MAKERAI_MCP_SHUTDOWN_LOG}
var
  GMCPShutdownLog: string = 'C:\temp\mcp_shutdown.log';

procedure MCPLog(const Msg: string);
var
  F: TextFile;
begin
  try
    AssignFile(F, GMCPShutdownLog);
    if System.SysUtils.FileExists(GMCPShutdownLog) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Msg);
    finally
      CloseFile(F);
    end;
  except
    // silent — we do not want AV inside the logger
  end;
end;
{$ENDIF MAKERAI_MCP_SHUTDOWN_LOG}

{ TMCPClientCustom }

function TMCPClientCustom.CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
begin
  Result := Nil;
end;

function TMCPClientCustom.CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
begin
  Result := Nil;
end;

constructor TMCPClientCustom.Create(AOwner: TComponent);
Var
  List: TStringList;
begin
  inherited Create(AOwner);
  FCallLock := TCriticalSection.Create;
  FName := 'MCPClient'; // Default value
  FTools := TStringList.Create;
  FParams := TStringList.Create;
  FEnvVars := TStringList.Create;
  List := GetDefaultParams;
  FServerProcess := nil;
  Try
    FParams.Assign(List);
  Finally
    List.Free;
  End;
  // TStringList(FParams).OnChange := ParamsChanged;
  FDisabledFunctions := TStringList.Create;
end;

destructor TMCPClientCustom.Destroy;
begin
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('TMCPClientCustom.Destroy BEGIN name=' + FName); {$ENDIF}

  if FOwnsServerProcess then
  begin
    {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  InternalStopLocalServerProcess...'); {$ENDIF}
    InternalStopLocalServerProcess;
    {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  InternalStopLocalServerProcess OK'); {$ENDIF}
  end;

  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FTools.Free...'); {$ENDIF}
  FTools.Free;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FParams.Free...'); {$ENDIF}
  FParams.Free;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FDisabledFunctions.Free...'); {$ENDIF}
  FDisabledFunctions.Free;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FEnvVars.Free...'); {$ENDIF}
  FEnvVars.Free;
  FCallLock.Free;
  inherited;
end;

procedure TMCPClientCustom.DoLog(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Msg);
end;

procedure TMCPClientCustom.DoStatusUpdate(const StatusMsg: string);
begin
  if Assigned(FOnStatusUpdate) then
    FOnStatusUpdate(Self, StatusMsg);
end;

procedure TMCPClientCustom.DoStreamMessage(const EventType, Data: string);
begin
  if Assigned(FOnStreamMessage) then
    FOnStreamMessage(Self, EventType, Data);
end;

function TMCPClientCustom.GetDefaultParams: TStringList;
begin
  Result := TStringList.Create;
  Try
    Result.Add('Command=npx');
    Result.Add('Arguments=');
    Result.Add('RootDir=' + TPath.GetHomePath); // A more sensible home directory
    Result.Add('PATH=C:\');
    Result.Add('ApiHeaderName=Authorization');
    Result.Add('ApiBearerToken=@MCPBearerToken');
    Result.Add('URL=http://localhost:3001/sse');
    Result.Add('Login=login');
    Result.Add('Password=password');
    Result.Add('OAuthClientId=ClientId');
    Result.Add('OAuthURL=http://localhost:6274/oauth/callback');
    Result.Add('OAuthScope=Scope');
    Result.Add('Timeout=15000');
    Result.Add('InitializeEndpointSuffix='); // Empty
    Result.Add('NotificationEndpointSuffix='); // Empty
    Result.Add('RpcEndpointSuffix='); // Empty
  Finally
  End;
end;

function TMCPClientCustom.GetEnvVars: TStrings;
begin
  Result := FEnvVars;
end;

function TMCPClientCustom.GetParamByName(ParamName: String): String;
begin
  Result := FParams.Values[ParamName];
end;

function TMCPClientCustom.GetParams: TStrings;
begin
  Result := FParams;

  { If FCommand <> '' then
    Result.Values['Command'] := FCommand;

    If FArguments <> '' then
    Result.Values['Arguments'] := FArguments;

    If FRootDirectory <> '' then
    Result.Values['RootDir'] := FRootDirectory;

    If FURL <> '' then
    Result.Values['URL'] := FURL;

    If FTimeout > 0 then
    Result.Values['FTimeout'] := FTimeout.ToString;
  }
end;

function TMCPClientCustom.Initialize: Boolean;
Var
  jTools: TJSONObject;
  jValue: TJSonValue;
begin
  Result := False;

  Try
    jTools := ListTools;
    try
      If Assigned(jTools) and (jTools.TryGetValue<TJSonValue>('tools', jValue)) and (jValue is TJSonArray) then
      Begin
        FTools.Text := jTools.Format;
        Initialized := True;
        Enabled := True;
        Available := True;
        Result := True;
      End;
    finally
      jTools.Free; // FTools stores a text copy
    end;
  Except
    FTools.Clear;
    Initialized := True;
    Enabled := False;
    Available := False;
    Result := False;
  End;
end;

function TMCPClientCustom.InternalStartLocalServerProcess: Boolean;
begin
  Result := False;
  FOwnsServerProcess := False; // Initially false
  // ...
  if Assigned(FServerProcess) and FServerProcess.IsRunning then
  begin
    DoLog('Local server process is already running. This client will just connect.');
    Result := True;
    // Do not set FOwnsServerProcess to true here if it is already running.
    // This means another client (or process) already started it.
    Exit;
  end;

  // ... (code to launch the process if it is not running)

  if Assigned(FServerProcess) and FServerProcess.IsRunning then
  begin
    Result := True;
    FOwnsServerProcess := True; // THIS client started it!?
    DoLog('Local MCP Server started successfully');
    DoStatusUpdate('Local Server running.');
    Sleep(2000);
    DoLog('Brief pause after local server start to allow initialization.');
  end;
  // ... (error handling if launching fails)
end;

procedure TMCPClientCustom.InternalStopLocalServerProcess;
begin
  // Only stop if this instance owns the process
  if FOwnsServerProcess and Assigned(FServerProcess) then
  begin
    DoLog('Stopping local MCP server process because this client owns it...');
    // Clearer message
    DoStatusUpdate('Stopping local server...');
    try
      TUtilsSystem.StopInteractiveProcess(FServerProcess);
      FServerProcess := nil; // It is important to set it to nil after stopping it
      FOwnsServerProcess := False; // We no longer own it
      DoLog('Local MCP Server stopped.');
      DoStatusUpdate('Local Server stopped.');
    except
      on E: Exception do
      begin
        FLastError := 'EXCEPTION during local server stop: ' + E.Message;
        DoLog(FLastError);
        DoStatusUpdate('Error stopping local server.');
      end;
    end;
  end
  else if Assigned(FServerProcess) then // If we do not own it but FServerProcess is not nil (e.g., if launching fails)
  begin
    // If FServerProcess is not nil but FOwnsServerProcess is false,
    // it means the process is running but this instance did not start it.
    // Do not stop it; just clear the local reference if necessary.
    FreeAndNil(FServerProcess); // Free only the TInteractiveProcessInfo object, not the actual process
  end;
end;

function TMCPClientCustom.IsBinaryContentType(const ContentType: string): Boolean;
begin
  Result := SameText(ContentType, 'image') or SameText(ContentType, 'audio') or SameText(ContentType, 'video') or SameText(ContentType, 'document') or // For PDFs, Word, Excel, etc.
    SameText(ContentType, 'archive') or // For ZIP, RAR, etc.
    SameText(ContentType, 'executable') or // For EXE, DLL, etc.
    SameText(ContentType, 'font') or // For TTF, OTF, etc.
    SameText(ContentType, 'model') or // For 3D files
    SameText(ContentType, 'database') or // For SQLite, etc.
    SameText(ContentType, 'ebook') or // For EPUB, MOBI, etc.
    SameText(ContentType, 'certificate') or // For certificates
    SameText(ContentType, 'binary'); // Generic type for binaries
end;

function TMCPClientCustom.ListTools: TJSONObject;
begin
  Result := Nil;
end;

function TMCPClientCustom.ProcessAndExtractMedia(const AJsonResult: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  LClonedResult: TJSONObject;
  LContentArray: TJSonArray;
  LContentItem: TJSONObject;
  LItemType, LBase64Data, LMimeType, LFileName: string;
  i: Integer;
begin
  Result := nil;
  // 1. Validate inputs
  if not Assigned(AJsonResult) then
    Exit;

  // MCP 2026-07-28 (MRTR pattern): resultType='input_required' means that the
  // server requests additional information by retrying the original request with
  // inputResponses — a pattern not yet supported by this client. We return a
  // clear error instead of a confusing partial result for the LLM.
  if AJsonResult.GetValue<string>('resultType', '') = 'input_required' then
  begin
    DoLog('MCP: the server returned resultType=input_required (MRTR), a pattern not supported by this client.');
    Result := TJSONObject.Create;
    Result.AddPair('error',
      'The MCP server requires additional input (MRTR, resultType=input_required), not supported by this client yet.');
    Exit;
  end;

  if not Assigned(AExtractedMedia) then
  begin
    Result := TJSONObject(AJsonResult.Clone);
    Exit;
  end;

  // 2. Clone the input JSON object so as not to modify the original.
  LClonedResult := TJSONObject(AJsonResult.Clone);
  try
    // 3. Find the 'content' array in the cloned JSON.
    if not LClonedResult.TryGetValue<TJSonArray>('content', LContentArray) then
    begin
      Result := LClonedResult;
      Exit;
    end;

    // 4. Iterate over each element of the 'content' array.
    for i := 0 to LContentArray.Count - 1 do
    begin
      if not(LContentArray.Items[i] is TJSONObject) then
        Continue;

      LContentItem := LContentArray.Items[i] as TJSONObject;

      // Check whether the item is of a type that contains binary data
      if LContentItem.TryGetValue<string>('type', LItemType) and IsBinaryContentType(LItemType) then
      begin
        // Try to obtain the base64 data and MIME type.
        if LContentItem.TryGetValue<string>('data', LBase64Data) and LContentItem.TryGetValue<string>('mimeType', LMimeType) and not LBase64Data.IsEmpty then
        begin
          // -- A binary was found --
          var
          MediaFile := TAiMediaFile.Create;

          // Generate a file name with the appropriate extension
          LFileName := Format('mcp-media-%d%s', [AExtractedMedia.Count + 1, GetFileExtensionFromMimeType(LMimeType)]);

          MediaFile.LoadFromBase64(LFileName, LBase64Data);
          AExtractedMedia.Add(MediaFile);

          // Modify the cloned JSON
          LContentItem.RemovePair('data');
          LContentItem.AddPair('dataExtracted', TJSONBool.Create(True));
          LContentItem.AddPair('mediaIdentifier', MediaFile.filename);
          LContentItem.AddPair('originalSize', TJSONNumber.Create(Length(LBase64Data))); // Optional: original size
        end;
      end;
    end;

    Result := LClonedResult;
  except
    LClonedResult.Free;
    Result := nil;
  end;
end;

procedure TMCPClientCustom.SetAvailable(const Value: Boolean);
begin
  FAvailable := Value;
end;

{ procedure TMCPClientCustom.SetCommand(const Value: string);
  begin
  // FCommand := Value;
  end;
}

{ procedure TMCPClientCustom.SetDisabledFunctions(const Value: TStrings);
  begin
  FDisabledFunctions.Assign(Value);
  end;
}

procedure TMCPClientCustom.SetEnabled(const Value: Boolean);
begin
  FEnabled := Value;
end;

procedure TMCPClientCustom.SetEnvVars(const Value: TStrings);
begin
  FEnvVars.Assign(Value);
end;

// --- MCP 2026-07-28 (modo stateless / dual-era) ---

function TMCPClientCustom.IsModernMode: Boolean;
begin
  Result := FNegotiatedProtocol = MCP_PROTOCOL_VERSION_MODERN;
end;

// Builds the _meta object that spec 2026-07-28 requires in every request of
// modern mode: protocol version, client identity, and capabilities.
// The caller takes ownership of the returned object.
function TMCPClientCustom.BuildModernMeta: TJSONObject;
var
  LClientInfo, LCaps: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(MCP_META_PROTOCOL_VERSION, MCP_PROTOCOL_VERSION_MODERN);
  LClientInfo := TJSONObject.Create;
  LClientInfo.AddPair('name', 'MakerAI Delphi Client ' + Self.Name);
  LClientInfo.AddPair('version', '3.5');
  Result.AddPair(MCP_META_CLIENT_INFO, LClientInfo);
  LCaps := TJSONObject.Create;
  // MRTR: we declare elicitation only if there is a handler — the spec prohibits the
  // server from sending inputRequests of types the client did not declare.
  if Assigned(FOnInputRequired) then
    LCaps.AddPair('elicitation', TJSONObject.Create);
  Result.AddPair(MCP_META_CLIENT_CAPABILITIES, LCaps);
end;

// Injects _meta into params when the negotiated mode is modern. If the
// request already has _meta (e.g., progressToken), the missing keys are added.
procedure TMCPClientCustom.AttachModernMeta(AParams: TJSONObject);
var
  MetaVal: TJSONValue;
  MetaObj, NewMeta: TJSONObject;
  i: Integer;
begin
  if (not IsModernMode) or (not Assigned(AParams)) then
    Exit;
  MetaVal := AParams.GetValue('_meta');
  if not Assigned(MetaVal) then
    AParams.AddPair('_meta', BuildModernMeta)
  else if MetaVal is TJSONObject then
  begin
    MetaObj := TJSONObject(MetaVal);
    if not Assigned(MetaObj.GetValue(MCP_META_PROTOCOL_VERSION)) then
    begin
      NewMeta := BuildModernMeta;
      try
        for i := 0 to NewMeta.Count - 1 do
          MetaObj.AddPair(NewMeta.Pairs[i].JsonString.Value, NewMeta.Pairs[i].JsonValue.Clone as TJSONValue);
      finally
        NewMeta.Free;
      end;
    end;
  end;
end;

// An error code from the reserved MCP range (-32020..-32099) identifies a
// modern server: the dual-era probe must NOT fall back to legacy upon receiving it.
class function TMCPClientCustom.IsModernErrorCode(ACode: Integer): Boolean;
begin
  Result := (ACode <= -32020) and (ACode >= -32099);
end;

// MRTR: detects an InputRequiredResult. AInputRequests points INSIDE
// AResult (do not free; invalid after freeing AResult). ARequestState is the
// opaque state that MUST be echoed exactly as-is in the retry.
class function TMCPClientCustom.TryGetInputRequired(AResult: TJSONObject;
  out AInputRequests: TJSONObject; out ARequestState: string): Boolean;
var
  V: TJSONValue;
begin
  AInputRequests := nil;
  ARequestState := '';
  Result := Assigned(AResult) and
    (AResult.GetValue<string>('resultType', '') = 'input_required');
  if not Result then
    Exit;
  V := AResult.GetValue('inputRequests');
  if V is TJSONObject then
    AInputRequests := TJSONObject(V);
  ARequestState := AResult.GetValue<string>('requestState', '');
end;

procedure TMCPClientCustom.SetInitialized(const Value: Boolean);
begin
  FInitialized := Value;
end;

procedure TMCPClientCustom.SetParams(const Value: TStrings);
begin
  FParams.Assign(Value);

  { FCommand := FParams.Values['Command'];
    FArguments := FParams.Values['Arguments'];
    FRootDirectory := FParams.Values['RootDir'];
    FURL := FParams.Values['URL'];
    FTimeout := StrToIntDef(FParams.Values['FTimeout'], 15000);
  }
end;

procedure TMCPClientCustom.SetTransportType(const Value: TToolTransportType);
begin
  FTransportType := Value;
end;

procedure TMCPClientCustom.SetURL(const Value: String);
begin
  FURL := Value;
end;

procedure TMCPClientCustom.Disconnect;
begin
  // Empty base implementation: subclasses with persistent connections override it
end;

{ TMCPClientStdIo }

constructor TMCPClientStdIo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FIsRunning := False;
  FRequestIDCounter := 0;
  FIncomingMessages := TThreadedQueue<TJSONObject>.Create(1000, INFINITE, 100);
  FInteractiveProcess := nil;
  DoLog('TMCPClientStdIo instance created.');
end;

destructor TMCPClientStdIo.Destroy;
var
  LJson: TJSONObject;
begin
  // The persistent connection is closed here automatically.
  // It is not necessary to call Disconnect() before freeing the component.
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('TMCPClientStdIo.Destroy BEGIN name=' + Self.Name); {$ENDIF}
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  InternalStopServerProcess...'); {$ENDIF}
  InternalStopServerProcess;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  InternalStopServerProcess OK'); {$ENDIF}
  if Assigned(FIncomingMessages) then
  begin
    {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FIncomingMessages.DoShutDown...'); {$ENDIF}
    FIncomingMessages.DoShutDown;
    while FIncomingMessages.PopItem(LJson) = wrSignaled do
    Begin
      If LJson = nil then
        Break;
      LJson.Free;
    End;
    {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FreeAndNil(FIncomingMessages)...'); {$ENDIF}
    FreeAndNil(FIncomingMessages);
    {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FIncomingMessages freed OK'); {$ENDIF}
  end;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('TMCPClientStdIo.Destroy END - calling inherited...'); {$ENDIF}
  inherited;
  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('TMCPClientStdIo.Destroy inherited OK'); {$ENDIF}
end;

function TMCPClientStdIo.IsServerRunning: Boolean;
begin
  Result := FIsRunning and Assigned(FInteractiveProcess) and FInteractiveProcess.IsRunning;
end;

// --- Full Lifecycle Methods ---

// --- Option D: persistent StdIo connection ---
// The server starts only once and remains active between calls.
// ListTools and CallTool reuse the existing connection if available.
// Lifecycle:
//   - The server starts automatically on the first call to ListTools or CallTool.
//   - It remains active to reuse the connection in subsequent calls.
//   - It stops automatically when the component is destroyed (no need to call Disconnect).
//   - Call Disconnect() explicitly only if you want to release the process before destruction.

function TMCPClientStdIo.ListTools: TJSONObject;
var
  InitResponse: TJSONObject;
begin
  Result := nil;
  FCallLock.Enter;
  try
    // If the server is already running we reuse the connection
    if IsServerRunning then
    begin
      DoLog('ListTools: server active, reusing connection.');
      Result := InternalListTools;
      Exit;
    end;

    DoLog('ListTools: starting server...');
    InternalStartServerProcess;
    if not IsServerRunning then
    begin
      DoLog('ListTools: failed to start server.');
      Available := False;
      Exit;
    end;

    // MCP 2026-07-28: dual-era probe. If the server responds to server/discover
    // it is modern (stateless, no handshake); otherwise, we fall back to legacy initialize.
    InitResponse := InternalServerDiscover;
    if Assigned(InitResponse) then
    begin
      FNegotiatedProtocol := MCP_PROTOCOL_VERSION_MODERN;
      DoLog('ListTools: modern server (2026-07-28), stateless mode.');
      InitResponse.Free;
    end
    else
    begin
      FNegotiatedProtocol := MCP_PROTOCOL_LEGACY;
      // Legacy initial handshake
      InitResponse := InternalInitialize;
      if not Assigned(InitResponse) then
      begin
        DoLog('ListTools: initialize failed. Stopping server.');
        InternalStopServerProcess;
        Available := False;
        Exit;
      end;
      InitResponse.Free;
      InternalSendInitializedNotification;
      Sleep(200); // Pause for the server to process the notification
    end;

    // The server remains active for future calls
    DoLog('ListTools: persistent connection established.');
    Result := InternalListTools;
  finally
    FCallLock.Leave;
  end;
end;

function TMCPClientStdIo.CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  InitResponse: TJSONObject;
  WasRunning: Boolean;
begin
  Result := nil;
  // Serialize concurrent calls to the same server (race condition when
  // ParseChat spawns multiple TTask with tools from the same MCP server).
  // Note: TCriticalSection in Delphi is reentrant (same thread can enter
  // several times without deadlock), so the TStrings overload that calls
  // this method does not cause a deadlock.
  FCallLock.Enter;
  try
    WasRunning := IsServerRunning;
    if WasRunning then
    begin
      // Process already active (bridge/persistent mode): call directly without full cycle.
      DoLog(Format('CallTool (persistent): %s', [AToolName]));
      Result := InternalCallTool(AToolName, AArguments, AExtractedMedia);
      Exit;
    end;

    DoLog(Format('Executing full cycle for CallTool: %s', [AToolName]));
    InternalStartServerProcess;
    try
      if not IsServerRunning then
      begin
        DoLog('Failed to start server. Aborting CallTool.');
        FreeAndNil(AArguments); // Free arguments if not going to be used
        Exit;
      end;

      // MCP 2026-07-28: dual-era probe before legacy handshake.
      InitResponse := InternalServerDiscover;
      if Assigned(InitResponse) then
      begin
        FNegotiatedProtocol := MCP_PROTOCOL_VERSION_MODERN;
        DoLog('CallTool: modern server (2026-07-28), stateless mode.');
        InitResponse.Free;
      end
      else
      begin
        FNegotiatedProtocol := MCP_PROTOCOL_LEGACY;
        // Legacy handshake
        InitResponse := InternalInitialize;
        if not Assigned(InitResponse) then
        begin
          DoLog('Initialization failed. Aborting CallTool.');
          FreeAndNil(AArguments); // Free arguments if not going to be used
          Exit;
        end;
        InitResponse.Free;
        InternalSendInitializedNotification;

        Sleep(200);
      end;

      // Perform the actual call
      Result := InternalCallTool(AToolName, AArguments, AExtractedMedia);

    finally
      InternalStopServerProcess;
      DoLog(Format('Full cycle for CallTool: %s finished.', [AToolName]));
    end;
  finally
    FCallLock.Leave;
  end;
end;

function TMCPClientStdIo.CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  ArgsObject: TJSONObject;
  i: Integer;
begin
  // Convert TStrings to TJSONObject
  ArgsObject := TJSONObject.Create;
  if Assigned(AArguments) then
  begin
    for i := 0 to AArguments.Count - 1 do
    begin
      ArgsObject.AddPair(AArguments.Names[i], AArguments.ValueFromIndex[i]);
    end;
  end;
  // Call the main version, which now owns ArgsObject
  Result := CallTool(AToolName, ArgsObject, AExtractedMedia);
end;

procedure TMCPClientStdIo.Disconnect;
begin
  FCallLock.Enter;
  try
    DoLog('Disconnect: closing persistent connection.');
    InternalStopServerProcess;
  finally
    FCallLock.Leave;
  end;
end;

procedure TMCPClientStdIo.InternalStartServerProcess;
var
  Command, Arguments, RootDir: String;
  FullCommand: string;
  AEnvironment: TStringList;
begin
  if IsServerRunning then
  begin
    DoLog('Server is already running.');
    Exit;
  end;

  // Clear zombie state: the process may have died unexpectedly leaving
  // FIsRunning=True and FReadThread/FInteractiveProcess assigned but invalid.
  // Calling Stop ensures cleanup before creating new objects.
  InternalStopServerProcess;

  DoLog('Starting MCP server process...');
  DoStatusUpdate('Starting server...');
  try
    Command := GetParamByName('Command');
    Arguments := GetParamByName('Arguments');
    RootDir := GetParamByName('RootDir');

    if Trim(Command) = '' then
    begin
      DoLog('ERROR: "Command" parameter cannot be null.');
      Exit;
    end;

    // --- FIX 1: Robust command construction ---
    // If the path has spaces and no quotes, we add them.
    if (Pos(' ', Command) > 0) and (Command[1] <> '"') then
      FullCommand := AnsiQuotedStr(Command, '"')
    else
      FullCommand := Command;

    if Trim(Arguments) <> '' then
      FullCommand := FullCommand + ' ' + Arguments;

    DoLog(Format('Executing command line: %s', [FullCommand]));

    // --- Start the process ---
    AEnvironment := TStringList.Create;
    try
      AEnvironment.AddStrings(Self.EnvVars);
      FInteractiveProcess := TUtilsSystem.StartInteractiveProcess(FullCommand, RootDir, AEnvironment);
    finally
      AEnvironment.Free;
    end;

    if not Assigned(FInteractiveProcess) or ({$IFDEF MSWINDOWS}FInteractiveProcess.ProcessID{$ELSE}FInteractiveProcess.ProcessHandle{$ENDIF} = 0) then
    begin
      FIsRunning := False;
      DoLog('ERROR: Failed to start process.');
    end
    else
    begin
      FIsRunning := True;
      DoLog(Format('Server process started successfully (PID: %d).', [{$IFDEF MSWINDOWS}FInteractiveProcess.ProcessID{$ELSE}FInteractiveProcess.ProcessHandle{$ENDIF}]));
      {$IFDEF POSIX}
      DoLog(Format('[DEBUG] PipeHandles: InputWrite=%d, OutputRead=%d, ErrorRead=%d',
        [FInteractiveProcess.PipeHandles.InputWrite,
         FInteractiveProcess.PipeHandles.OutputRead,
         FInteractiveProcess.PipeHandles.ErrorRead]));
      DoLog('[DEBUG] IsRunning (post-fork)=' + BoolToStr(FInteractiveProcess.IsRunning, True));
      {$ENDIF}

      // --- FIX 2: START THE READ THREAD ---
      // Without this, the client is deaf.
      FReadThread := TThread.CreateAnonymousThread(ReadProcessOutput);
      FReadThread.FreeOnTerminate := False; // We free it ourselves in Stop
      FReadThread.Start;
      DoLog('[DEBUG] ReadThread started, handle=' + IntToStr({$IFDEF MSWINDOWS}FReadThread.Handle{$ELSE}FReadThread.ThreadID{$ENDIF}));
    end;

  except
    on E: Exception do
    begin
      FIsRunning := False;
      DoLog(Format('EXCEPTION starting server: %s', [E.Message]));
    end;
  end;
end;


procedure TMCPClientStdIo.InternalStopServerProcess;
begin
  // Quick exit only if we are already completely stopped (all fields clean).
  // DO NOT use IsServerRunning here: if the process died unexpectedly,
  // IsServerRunning=False but FReadThread and FInteractiveProcess are still assigned
  // (zombie state). In that case we must clean them up regardless.
  if not FIsRunning and not Assigned(FReadThread) and not Assigned(FInteractiveProcess) then
    Exit;

  {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('InternalStopServerProcess BEGIN name=' + Self.Name + ' FIsRunning=' + BoolToStr(FIsRunning, True)); {$ENDIF}
  DoLog('Stopping MCP server process...');
  DoStatusUpdate('Stopping server...');
  try
    FIsRunning := False;

    // CRITICAL: correct sequence to avoid AV due to race condition.
    // The read thread may be inside FInteractiveProcess.ReadOutput() right
    // when we free the object → AV. The safe sequence is:
    //   1. Kill the process WITHOUT freeing the object → closes the pipe → ReadOutput
    //      returns 0 bytes → the thread exits its loop.
    //   2. WaitFor → wait for the thread to finish before freeing anything.
    //   3. Free FInteractiveProcess → no one uses it anymore.
    if Assigned(FInteractiveProcess) then
    begin
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  Terminate process...'); {$ENDIF}
      FInteractiveProcess.Terminate;  // kills the process; the object remains alive
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  Terminate OK'); {$ENDIF}
    end;

    if Assigned(FReadThread) then
    begin
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  WaitFor thread...'); {$ENDIF}
      FReadThread.WaitFor;           // thread already exited (pipe closed + FIsRunning=False)
      FreeAndNil(FReadThread);
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  Thread freed'); {$ENDIF}
    end;

    // Now it is safe to free the process object
    if Assigned(FInteractiveProcess) then
    begin
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  Free FInteractiveProcess...'); {$ENDIF}
      TUtilsSystem.StopInteractiveProcess(FInteractiveProcess);
      {$IFDEF MAKERAI_MCP_SHUTDOWN_LOG} MCPLog('  FInteractiveProcess freed'); {$ENDIF}
    end;

    DoLog('MCP Server stopped.');
    DoStatusUpdate('Server stopped.');
  except
    on E: Exception do
    begin
      DoStatusUpdate('Error stopping server.');
      DoLog('EXCEPTION during server stop: ' + E.Message);
    end;
  end;
  FIsRunning := False; // Ensure the state
end;

function TMCPClientStdIo.InternalInitialize: TJSONObject;
var
  RequestObj, Response: TJSONObject;
  ResultPair: TJSonValue;
begin
  Result := nil;
  if not IsServerRunning then
    Exit;

  Inc(FRequestIDCounter);
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('jsonrpc', '2.0');
    RequestObj.AddPair('id', FRequestIDCounter);
    RequestObj.AddPair('method', 'initialize');
    var
    LParams := TJSONObject.Create;
    RequestObj.AddPair('params', LParams);
    LParams.AddPair('protocolVersion', '2024-11-05');
    var
    LClientInfo := TJSONObject.Create;
    LParams.AddPair('clientInfo', LClientInfo);
    LClientInfo.AddPair('name', 'Delphi Client ' + Self.Name);
    LClientInfo.AddPair('version', '1.1.0');
    var
    LCapabilities := TJSONObject.Create;
    LParams.AddPair('capabilities', LCapabilities);
    // Add empty capabilities
    LCapabilities.AddPair('tools', TJSONObject.Create);
    LCapabilities.AddPair('resources', TJSONObject.Create);
    LCapabilities.AddPair('roots', TJSONObject.Create);

    InternalSendRawMessage(RequestObj.ToJSON);
    Response := InternalReceiveJSONResponse(FRequestIDCounter);

    if Assigned(Response) then
      try
        if (Response is TJSONObject) and TJSONObject(Response).TryGetValue('result', ResultPair) and (ResultPair is TJSONObject) then
        begin
          Result := TJSONObject(ResultPair.Clone); // Clone the result so the caller owns it
        end
        else
        begin
          DoLog('Error: Initialize response is invalid. ' + Response.ToJSON);
        end;
      finally
        Response.Free; // Free the response container
      end;
  finally
    RequestObj.Free;
  end;
end;

// MCP 2026-07-28: dual-era probe via StdIO. A modern server responds with
// a DiscoverResult; a legacy one replies -32601 (or stays silent and the
// timeout expires), in which case we return nil and the caller falls back to legacy handshake.
function TMCPClientStdIo.InternalServerDiscover: TJSONObject;
var
  RequestObj, Response, LParams: TJSONObject;
  ResultPair: TJSonValue;
  LError: TJSONObject;
begin
  Result := nil;
  if not IsServerRunning then
    Exit;

  Inc(FRequestIDCounter);
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('jsonrpc', '2.0');
    RequestObj.AddPair('id', FRequestIDCounter);
    RequestObj.AddPair('method', 'server/discover');
    LParams := TJSONObject.Create;
    RequestObj.AddPair('params', LParams);
    LParams.AddPair('_meta', BuildModernMeta);

    DoLog('Probing server/discover (dual-era)...');
    InternalSendRawMessage(RequestObj.ToJSON);
    Response := InternalReceiveJSONResponse(FRequestIDCounter, 5000);

    if Assigned(Response) then
      try
        if Response.TryGetValue('result', ResultPair) and (ResultPair is TJSONObject) then
          Result := TJSONObject(ResultPair.Clone) // the caller is the owner
        else if Response.TryGetValue<TJSONObject>('error', LError) then
          DoLog('server/discover not supported or rejected: ' + LError.ToJSON);
      finally
        Response.Free;
      end
    else
      DoLog('server/discover no response: legacy server.');
  finally
    RequestObj.Free;
  end;
end;

procedure TMCPClientStdIo.InternalSendInitializedNotification;
var
  NotificationObj: TJSONObject;
begin
  if not IsServerRunning then
    Exit;

  NotificationObj := TJSONObject.Create;
  try
    NotificationObj.AddPair('jsonrpc', '2.0');
    NotificationObj.AddPair('method', 'notifications/initialized');
    NotificationObj.AddPair('params', TJSONObject.Create);
    InternalSendRawMessage(NotificationObj.ToJSON);
  finally
    NotificationObj.Free;
  end;
end;

function TMCPClientStdIo.InternalListTools: TJSONObject;
var
  RequestObj, Response: TJSONObject;
  ResultPair: TJSonValue;
begin
  Result := nil;
  if not IsServerRunning then
    Exit;

  Inc(FRequestIDCounter);
  RequestObj := TJSONObject.Create;
  try
    RequestObj.AddPair('jsonrpc', '2.0');
    RequestObj.AddPair('id', FRequestIDCounter);
    RequestObj.AddPair('method', 'tools/list');
    var LListParams := TJSONObject.Create;
    RequestObj.AddPair('params', LListParams);
    AttachModernMeta(LListParams); // MCP 2026-07-28: _meta in every modern request

    InternalSendRawMessage(RequestObj.ToJSON);
    Response := InternalReceiveJSONResponse(FRequestIDCounter);

    if Assigned(Response) then
      try
        if (Response is TJSONObject) and TJSONObject(Response).TryGetValue('result', ResultPair) and (ResultPair is TJSONObject) then
        begin
          Result := TJSONObject(ResultPair.Clone); // Clone for the caller
        end
        else
        begin
          DoLog('Error: tools/list response is invalid. ' + Response.ToJSON);
        end;
      finally
        Response.Free;
      end;
  finally
    RequestObj.Free;
  end;
end;

function TMCPClientStdIo.InternalCallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  RequestObj, Response: TJSONObject;
  ResultPair: TJSonValue;
  LRound: Integer;
  LInputResponses, LReqs, RawResult: TJSONObject;
  LState: string;
  LHandled: Boolean;
  LSpan: TAiSpan;
begin
  Result := nil;
  if not IsServerRunning then
  begin
    FreeAndNil(AArguments);
    Exit;
  end;

  // Telemetry: one span covers all MRTR rounds of this tool call
  LSpan := AiSpanStart('mcp.client tools/call', skClient);
  AiSpanAttr(LSpan, 'mcp.method', 'tools/call');
  AiSpanAttr(LSpan, 'gen_ai.tool.name', AToolName);

  // MCP 2026-07-28 (MRTR): retry loop. If the server responds
  // input_required and OnInputRequired is set, the tools/call is repeated with the
  // handler's inputResponses and the requestState echo (max N rounds).
  LInputResponses := nil;
  LState := '';
  try
    for LRound := 1 to MCP_MRTR_MAX_ROUNDS do
    begin
      Inc(FRequestIDCounter);
      RequestObj := TJSONObject.Create;
      try
        RequestObj.AddPair('jsonrpc', '2.0');
        RequestObj.AddPair('id', FRequestIDCounter);
        RequestObj.AddPair('method', 'tools/call');

        var
        LParams := TJSONObject.Create;
        RequestObj.AddPair('params', LParams);
        LParams.AddPair('name', TJSONString.Create(AToolName));
        // Clone AArguments: the caller remains the owner of the original
        if Assigned(AArguments) then
          LParams.AddPair('arguments', AArguments.Clone as TJSONValue)
        else
          LParams.AddPair('arguments', TJSONObject.Create);
        AttachModernMeta(LParams); // MCP 2026-07-28: _meta in every modern request
        // Telemetry: propagate traceparent in _meta (convention spec 2026-07-28)
        if Assigned(LSpan) and IsModernMode then
        begin
          var LMetaV := LParams.GetValue('_meta');
          if (LMetaV is TJSONObject) and not Assigned(TJSONObject(LMetaV).GetValue('traceparent')) then
            TJSONObject(LMetaV).AddPair('traceparent', LSpan.TraceParent);
        end;
        if Assigned(LInputResponses) then
        begin
          LParams.AddPair('inputResponses', LInputResponses);
          LInputResponses := nil; // now it is property of request
        end;
        if LState <> '' then
          LParams.AddPair('requestState', LState); // literal echo, without inspecting

        DoLog(Format('Calling tool "%s" (round %d)...', [AToolName, LRound]));
        InternalSendRawMessage(RequestObj.ToJSON);

        // Use generous timeout for tool calls: network operations (SMTP, HTTP, SSH)
        // can take much longer than the initialization handshake.
        // Minimum 60s; if the Timeout parameter is set higher, use it.
        var LCallTimeout := StrToIntDef(GetParamByName('Timeout'), 60000);
        if LCallTimeout < 60000 then LCallTimeout := 60000;
        DoLog(Format('Waiting for tool response (timeout=%dms)...', [LCallTimeout]));
        Response := InternalReceiveJSONResponse(FRequestIDCounter, Cardinal(LCallTimeout));
      finally
        RequestObj.Free;
      end;

      if not Assigned(Response) then
        Exit; // timeout or no response

      try
        if Response.TryGetValue('result', ResultPair) and (ResultPair is TJSONObject) then
        begin
          RawResult := TJSONObject(ResultPair);

          // MRTR: does server request additional information?
          if TryGetInputRequired(RawResult, LReqs, LState) then
          begin
            if Assigned(LReqs) and Assigned(FOnInputRequired) then
            begin
              LInputResponses := TJSONObject.Create;
              LHandled := False;
              FOnInputRequired(Self, AToolName, LReqs, LInputResponses, LHandled);
              if not LHandled then
              begin
                FreeAndNil(LInputResponses);
                // Canceled by the handler: the guard produces a clear error
                Result := ProcessAndExtractMedia(RawResult, AExtractedMedia);
                Exit;
              end;
              Continue; // retry with responses
            end
            else if not Assigned(LReqs) then
              Continue // without inputRequests: spec allows immediate retry
            else
            begin
              // No handler assigned: clear error via the guard
              Result := ProcessAndExtractMedia(RawResult, AExtractedMedia);
              Exit;
            end;
          end;

          // Separates the response from the binary files that will become mediafiles in the response message
          Result := ProcessAndExtractMedia(RawResult, AExtractedMedia);
          Exit;
        end
        else
        begin
          var
            LError: TJSONObject;
          if Response.TryGetValue<TJSONObject>('error', LError) then
          begin
            DoLog(Format('Server error calling "%s": %s', [AToolName, LError.ToJSON]));
            // Return the error as a result so the LLM can inform the user
            Result := TJSONObject.Create;
            Result.AddPair('error', LError.ToString);
          end
          else
            DoLog(Format('Invalid server response for "%s": %s', [AToolName, Response.ToJSON]));
          Exit;
        end;
      finally
        Response.Free;
      end;
    end;

    // MRTR rounds exhausted without final result
    DoLog(Format('MRTR: rounds exhausted (%d) for "%s".', [MCP_MRTR_MAX_ROUNDS, AToolName]));
    Result := TJSONObject.Create;
    Result.AddPair('error', Format('MCP MRTR: max rounds (%d) exceeded for tool "%s".', [MCP_MRTR_MAX_ROUNDS, AToolName]));
  finally
    LInputResponses.Free; // only remains assigned if loop did not consume it
    if Assigned(Result) then
      AiSpanEnd(LSpan)
    else
      AiSpanEnd(LSpan, 'no response from MCP server');
  end;
end;

// --- Low-level methods (communication) ---
// (These methods are essentially the same as in the original demo,
// except that they now use DoLog to report)

procedure TMCPClientStdIo.ReadProcessOutput;
var
  ReadBuffer: array [0 .. 4095] of Byte;
  BytesRead: Integer;
  LineBuffer: TBytes;
  LineFeedPos: Integer;
  CurrentLine: string;
  ParsedJson: TJSONObject;
begin
  SetLength(LineBuffer, 0);
  DoLog(Format('[DEBUG] ReadThread STARTED. FIsRunning=%s Assigned=%s',
    [BoolToStr(FIsRunning, True), BoolToStr(Assigned(FInteractiveProcess), True)]));
  {$IFDEF POSIX}
  if Assigned(FInteractiveProcess) then
    DoLog(Format('[DEBUG] ReadThread OutputRead=%d IsRunning=%s',
      [FInteractiveProcess.PipeHandles.OutputRead,
       BoolToStr(FInteractiveProcess.IsRunning, True)]));
  {$ENDIF}

  // We keep the loop while the process is alive and we want to run
  while FIsRunning and Assigned(FInteractiveProcess) and FInteractiveProcess.IsRunning do
  begin
    // Read STDOUT
    BytesRead := FInteractiveProcess.ReadOutput(ReadBuffer, SizeOf(ReadBuffer));

    if BytesRead > 0 then
    begin
      // Add to the cumulative buffer
      var OldLen := Length(LineBuffer);
      SetLength(LineBuffer, OldLen + BytesRead);
      Move(ReadBuffer[0], LineBuffer[OldLen], BytesRead);

      // Process complete lines (looking for #10)
      while True do
      begin
        LineFeedPos := -1;
        for var i := 0 to Length(LineBuffer) - 1 do
          if LineBuffer[i] = 10 then // LF
          begin
            LineFeedPos := i;
            Break;
          end;

        if LineFeedPos = -1 then
          Break; // No complete line yet

        // Extract line and convert to UTF8 String
        // Note: LineFeedPos includes up to just before the LF.
        CurrentLine := TEncoding.UTF8.GetString(LineBuffer, 0, LineFeedPos).Trim;

        // Clean CR if present (#13)
        if (CurrentLine <> '') and (CurrentLine[Length(CurrentLine)] = #13) then
           SetLength(CurrentLine, Length(CurrentLine) - 1);

        if not CurrentLine.IsEmpty then
        begin
          // Tolerance for noisy servers: if the server interleaved text
          // informative without LF before the response (e.g., a banner that
          // ends attached to the JSON on the same line), we rescue the JSON-RPC
          // by searching for '{"jsonrpc"' inside the line. Without this, the first
          // response (the server/discover probe) can be lost.
          if not CurrentLine.StartsWith('{') then
          begin
            var LJsonStart := CurrentLine.IndexOf('{"jsonrpc"');
            if LJsonStart > 0 then
            begin
              DoLog('[STDOUT]: ' + CurrentLine.Substring(0, LJsonStart));
              CurrentLine := CurrentLine.Substring(LJsonStart);
            end;
          end;

          // Try to detect if it is JSON
          if CurrentLine.StartsWith('{') then
          begin
            try
              var LVal := TJSONObject.ParseJSONValue(CurrentLine);
              if not (LVal is TJSONObject) then
              begin
                LVal.Free;
                DoLog('[RAW]: ' + CurrentLine);
              end
              else
              begin
                ParsedJson := TJSONObject(LVal);
                DoLog('SERVER -> CLIENT: ' + CurrentLine);
                FIncomingMessages.PushItem(ParsedJson);
              end;
            except
              // If parsing fails, we just log it as raw text
               DoLog('[RAW]: ' + CurrentLine);
            end;
          end
          else
            DoLog('[STDOUT]: ' + CurrentLine);
        end;

        // Remove the processed line from the buffer (including the LF)
        var RemoveLen := LineFeedPos + 1;
        var NewLen := Length(LineBuffer) - RemoveLen;
        if NewLen > 0 then
          Move(LineBuffer[RemoveLen], LineBuffer[0], NewLen);
        SetLength(LineBuffer, NewLen);
      end;
    end
    else
    begin
      // Small pause to avoid burning CPU if there is no data
      Sleep(10);
    end;

    // Here you could also read ReadError if you want to see STDERR
  end;
end;

procedure TMCPClientStdIo.InternalSendRawMessage(const AJsonString: string);
var
  Bytes: TBytes;
begin
  if not IsServerRunning then Exit;

  DoLog('CLIENT -> SERVER: ' + AJsonString);
  try
    // IMPORTANT: + #10 at the end
    Bytes := TEncoding.UTF8.GetBytes(AJsonString + #10);
    FInteractiveProcess.WriteInput(Bytes[0], Length(Bytes));
  except
    on E: Exception do
      DoLog('ERROR writing to server: ' + E.Message);
  end;
end;

function TMCPClientStdIo.InternalReceiveJSONResponse(AExpectedID: Integer; ATimeoutMs: Cardinal): TJSONObject;
var
  ReceivedJson: TJSONObject;
  Stopwatch: TStopwatch;
  Id: Integer;
begin
  Result := nil;
  if not IsServerRunning then
    Exit;

  DoLog(Format('Waiting for JSON-RPC response with ID %d...', [AExpectedID]));
  Stopwatch := TStopwatch.StartNew;

  while Stopwatch.ElapsedMilliseconds < ATimeoutMs do
  begin
    if FIncomingMessages.PopItem(ReceivedJson) = wrSignaled then
    begin
      try
        if ReceivedJson.TryGetValue<Integer>('id', Id) and (Id = AExpectedID) then
        begin
          Result := ReceivedJson; // Success! Return the received object
          Exit;
        end
        else
        begin
          DoLog(Format('DEBUG: Ignoring message with ID %d (expected %d) or unsolicited notification.', [ReceivedJson.GetValue<Integer>('id', -1), AExpectedID]));
          ReceivedJson.Free; // Free the unwanted object
        end;
      except
        on E: Exception do
        begin
          DoLog('ERROR processing queued message: ' + E.Message);
          FreeAndNil(ReceivedJson);
        end;
      end;
    end;

    if not IsServerRunning then
    begin
      DoLog('ERROR: Server stopped while waiting for a response.');
      Break;
    end;
    Sleep(20); // Small pause to avoid consuming 100% CPU
  end;

  DoLog(Format('TIMEOUT: No response received for ID %d in %d ms.', [AExpectedID, ATimeoutMs]));
end;

function MergeToolLists(const ASourceName: string; ASourceJson, ATargetJson: TJSONObject; AFormat: TToolFormat): TJSONObject;
var
  LSourceTools, LTargetTools: TJSonArray;
  LSourceTool, LNewTool, LInputSchema: TJSONObject;
  LInputSchemaValue: TJSonValue;
  LToolName: string;
  i: Integer;
begin
  // 1. Validate the inputs
  if not Assigned(ASourceJson) then
  begin
    // If the source is nil, there is nothing to do. We return the target unchanged.
    Result := ATargetJson;
    Exit;
  end;

  // If the target is nil, we create a base object with an empty "tools" array.
  if not Assigned(ATargetJson) then
  begin
    ATargetJson := TJSONObject.Create;
    ATargetJson.AddPair('tools', TJSonArray.Create);
  end;

  // 2. Obtain the "tools" arrays from both JSON.
  // If they do not exist, we exit because there are no tools to process.
  if not ASourceJson.TryGetValue<TJSonArray>('tools', LSourceTools) then
  begin
    Result := ATargetJson;
    Exit;
  end;

  if not ATargetJson.TryGetValue<TJSonArray>('tools', LTargetTools) then
    raise Exception.Create('Target JSON object does not contain a "tools" array.');

  // 3. Iterate over each tool in the source JSON (Source)
  for i := 0 to LSourceTools.Count - 1 do
  begin
    if not(LSourceTools.Items[i] is TJSONObject) then
      Continue; // Skip if the item is not an object

    LSourceTool := LSourceTools.Items[i] as TJSONObject;
    LNewTool := TJSONObject.Create; // Create a new object for the transformed tool

    // 4. Transform the tool name with the prefix
    if LSourceTool.TryGetValue<string>('name', LToolName) then
    begin
      if ASourceName.IsEmpty then
        LNewTool.AddPair('name', LToolName)
      else
        LNewTool.AddPair('name', TJSONString.Create(Format('%s@%s', [ASourceName, LToolName])));
    end;

    // 5. Copy the description (common to all formats)

    Var
      Description: String;
    If LSourceTool.TryGetValue<String>('description', Description) then
      LNewTool.AddPair('description', Description);

    // 6. Normalize the input schema
    // The MCP format uses 'inputSchema', Anthropic uses 'input_schema', OpenAI uses 'parameters'
    if LSourceTool.TryGetValue('inputSchema', LInputSchemaValue) or LSourceTool.TryGetValue('input_schema', LInputSchemaValue) or LSourceTool.TryGetValue('parameters', LInputSchemaValue) then
    begin
      if LInputSchemaValue is TJSONObject then
      begin
        LInputSchema := TJSONObject(LInputSchemaValue.Clone); // We clone so as not to modify the original

        // The OpenAI format has an extra property 'type':'function' that we must add.
        if AFormat = tfOpenAI then
        begin
          LNewTool.AddPair('type', 'function');
          LNewTool.AddPair('parameters', LInputSchema); // OpenAI uses the name 'parameters'
        end
        else // Anthropic and other standard formats
        begin
          LNewTool.AddPair('input_schema', LInputSchema); // Anthropic uses 'input_schema'
        end;
      end;
    end
    else
    begin
      // If there is no schema, we create an empty one to comply with the format
      LInputSchema := TJSONObject.Create;
      LInputSchema.AddPair('type', 'object');
      LInputSchema.AddPair('properties', TJSONObject.Create);

      if AFormat = tfOpenAI then
      begin
        LNewTool.AddPair('type', 'function');
        LNewTool.AddPair('parameters', LInputSchema);
      end
      else
      begin
        LNewTool.AddPair('input_schema', LInputSchema);
      end;
    end;

    // 7. Add the transformed tool to the Target's tools array
    LTargetTools.Add(LNewTool);
  end;

  // 8. Return the modified Target object.
  Result := ATargetJson;
end;

{ TMCPClientHttp }
{ TMCPClientHttp }

constructor TMCPClientHttp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHttpClient := TNetHTTPClient.Create(Self);
  FRequestIDCounter := 0;
  FreeAndNil(FServerCapabilities);
  DoLog('TMCPClientHttp instance created.');
end;

destructor TMCPClientHttp.Destroy;
begin
  // The local server process is stopped in the destructor of TMCPClientCustom
  FreeAndNil(FServerCapabilities);
  inherited;
end;

function TMCPClientHttp.Initialize: Boolean;
const
  MAX_RETRIES_ON_FAIL = 2; // Number of connection retries if the server does not respond
var
  jTools: TJSONObject;
  jValue: TJSonValue;
  CurrentAttempt: Integer;
begin
  Result := False;
  FBusy := True;
  FLastError := '';
  Initialized := True;
  Enabled := False;
  Available := False;
  FTools.Clear;
  FNegotiatedProtocol := ''; // re-probe the server era on each Initialize

  DoStatusUpdate('Initializing MCP Client (HTTP)...');

  CurrentAttempt := 0;
  while CurrentAttempt < MAX_RETRIES_ON_FAIL do
  begin
    Inc(CurrentAttempt);
    try
      DoLog(Format('Attempting connection to server (Try %d/%d)...', [CurrentAttempt, MAX_RETRIES_ON_FAIL]));

      // MCP 2026-07-28: dual-era probe. A modern server responds to
      // server/discover; a legacy one returns a JSON-RPC/HTTP error
      // (EMCPClientException) and we fall back to the initialize handshake. Errors
      // from the network are NOT EMCPClientException and go up to the retry loop.
      if FNegotiatedProtocol = '' then
      begin
        var LProbeParams := TJSONObject.Create;
        LProbeParams.AddPair('_meta', BuildModernMeta);
        try
          var LDiscover := InternalSendRequest('server/discover', LProbeParams);
          if Assigned(LDiscover) then
          begin
            FNegotiatedProtocol := MCP_PROTOCOL_VERSION_MODERN;
            LDiscover.Free;
          end;
        except
          on E: EMCPClientException do
          begin
            FNegotiatedProtocol := MCP_PROTOCOL_LEGACY;
            DoLog('server/discover not supported, legacy handshake will be used.');
          end;
        end;
      end;

      if IsModernMode then
      begin
        // Stateless mode: no handshake or notifications/initialized.
        DoLog('Modern server (2026-07-28): stateless mode, no handshake.');
      end
      else
      begin
        // 1. Perform the MCP initialization handshake
        // Connection exceptions will be thrown here and caught below.
        InternalPerformMCPInitialize;
        DoLog('MCP Initialization successful.');

        // 2. Send the initialized notification (does not throw an exception, only logs warnings if the notification POST fails)
        InternalSendInitializedNotification;
      end;

      // 3. Get the list of tools (FTools stores a copy in text)
      jTools := ListTools;
      try
        If Assigned(jTools) and (jTools.TryGetValue<TJSonValue>('tools', jValue)) and (jValue is TJSonArray) then
        Begin
          FTools.Text := jTools.Format;
          Enabled := True;
          Available := True;
          Result := True; // ?xito
        End
        Else
        Begin
          FLastError := 'Failed to retrieve tools list after successful initialization. Server response incomplete.';
          DoLog(FLastError);
        End;
      finally
        jTools.Free;
      end;
      // With or without a list, it is not retried: the server already responded (if the
      // response is incomplete, restarting the server will not fix it)
      Break;
    except
      on E: Exception do
      begin
        FLastError := 'MCP HTTP Initialization Failed: ' + E.Message;
        DoLog(FLastError);
        DoStatusUpdate('Initialization Failed: ' + E.Message);

        // If it is a connection error (not 200 OK, timeout, etc.) and there are still retries left
        if (CurrentAttempt < MAX_RETRIES_ON_FAIL) then
        begin
          DoLog(Format('Connection failed. Attempting to start local server and retry (Attempt %d).', [CurrentAttempt]));
          InternalStopLocalServerProcess; // Stop any previous process we may have started and that failed
          if InternalStartLocalServerProcess then // Try to start the local server
          begin
            // server launch successful, the loop will retry the connection
            FNegotiatedProtocol := ''; // the newly launched server may be from another era: re-probe
            Sleep(2000); // Give the server extra time to be ready for connections
            Continue; // Return to the start of the loop to retry the connection
          end
          else
          begin
            DoLog('Failed to start local server. No more retries for this initialization cycle.');
            Break; // The local server could not be launched; end of retries
          end;
        end
        else
        begin
          DoLog('Max connection attempts reached. Initialization failed permanently.');
          Break; // Maximum retries reached
        end;
      end;
    end;
  end; // end while

  FBusy := False;
  Exit(Result);
end;

function TMCPClientHttp.ListTools: TJSONObject;
var
  LParams: TJSONObject;
begin
  FLastError := '';
  DoLog('Executing ListTools via HTTP...');
  DoStatusUpdate('Listing tools...');

  LParams := TJSONObject.Create; // Freed in InternalSendRequest
  try
    Result := InternalSendRequest('tools/list', LParams);
  except
    on E: Exception do
    begin
      FLastError := 'Error listing tools: ' + E.Message;
      DoLog(FLastError);
      Result := nil; // Retornar nil en caso de error
    end;
  end;

  if Assigned(Result) then
    DoStatusUpdate('Tools listed successfully.')
  else
    DoStatusUpdate('Failed to list tools: ' + FLastError);
end;

function TMCPClientHttp.CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  LParams: TJSONObject;
  LResultRaw: TJSONObject;
  LRound: Integer;
  LInputResponses, LReqs: TJSONObject;
  LState: string;
  LHandled: Boolean;
begin
  Result := nil;
  FLastError := '';

  DoLog(Format('Executing CallTool via HTTP: %s', [AToolName]));
  DoStatusUpdate(Format('Calling tool: %s...', [AToolName]));

  // This method takes ownership of AArguments (the caller must NOT free it).
  // MCP 2026-07-28 (MRTR): retry loop with inputResponses + echo of
  // requestState when the server responds input_required (max N rounds).
  LInputResponses := nil;
  LState := '';
  try
    try
      for LRound := 1 to MCP_MRTR_MAX_ROUNDS do
      begin
        LParams := TJSONObject.Create;
        LParams.AddPair('name', TJSONString.Create(AToolName));
        if Assigned(AArguments) then
          LParams.AddPair('arguments', AArguments.Clone as TJSONValue)
        else
          LParams.AddPair('arguments', TJSONObject.Create);
        if Assigned(LInputResponses) then
        begin
          LParams.AddPair('inputResponses', LInputResponses);
          LInputResponses := nil; // now it is property of request
        end;
        if LState <> '' then
          LParams.AddPair('requestState', LState); // literal echo, without inspecting

        LResultRaw := InternalSendRequest('tools/call', LParams); // InternalSendRequest frees LParams
        if not Assigned(LResultRaw) then
          Exit;

        try
          // MRTR: does server request additional information?
          if TryGetInputRequired(LResultRaw, LReqs, LState) then
          begin
            if Assigned(LReqs) and Assigned(FOnInputRequired) then
            begin
              LInputResponses := TJSONObject.Create;
              LHandled := False;
              FOnInputRequired(Self, AToolName, LReqs, LInputResponses, LHandled);
              if not LHandled then
              begin
                FreeAndNil(LInputResponses);
                Result := ProcessAndExtractMedia(LResultRaw, AExtractedMedia); // guard: clear error
                Exit;
              end;
              Continue; // retry with responses
            end
            else if not Assigned(LReqs) then
              Continue // without inputRequests: spec allows immediate retry
            else
            begin
              Result := ProcessAndExtractMedia(LResultRaw, AExtractedMedia); // without handler: clear error
              Exit;
            end;
          end;

          Result := ProcessAndExtractMedia(LResultRaw, AExtractedMedia);
          Exit;
        finally
          FreeAndNil(LResultRaw); // Free the RAW result after processing it
        end;
      end;

      // MRTR rounds exhausted without final result
      DoLog(Format('MRTR: rounds exhausted (%d) for "%s".', [MCP_MRTR_MAX_ROUNDS, AToolName]));
      Result := TJSONObject.Create;
      Result.AddPair('error', Format('MCP MRTR: max rounds (%d) exceeded for tool "%s".', [MCP_MRTR_MAX_ROUNDS, AToolName]));
    except
      on E: Exception do
      begin
        FLastError := Format('Error calling tool "%s": %s', [AToolName, E.Message]);
        DoLog(FLastError);
        Result := nil; // Retornar nil en caso de error
      end;
    end;
  finally
    LInputResponses.Free; // only remains assigned if loop did not consume it
    AArguments.Free; // owned by this method (previously LParams consumed it; now it is cloned per round)
  end;

  if Assigned(Result) then
    DoStatusUpdate(Format('Tool %s called successfully.', [AToolName]))
  else
    DoStatusUpdate(Format('Failed to call tool: %s. Error: %s', [AToolName, FLastError]));
end;

function TMCPClientHttp.CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  ArgsObject: TJSONObject;
  i: Integer;
begin
  ArgsObject := TJSONObject.Create;
  if Assigned(AArguments) then
  begin
    for i := 0 to AArguments.Count - 1 do
    begin
      ArgsObject.AddPair(AArguments.Names[i], AArguments.ValueFromIndex[i]);
    end;
  end;
  Result := CallTool(AToolName, ArgsObject, AExtractedMedia);
end;

procedure TMCPClientHttp.InternalPerformMCPInitialize;
var
  LRequestObj, LParams, LClientInfo, LCapabilities: TJSONObject;
  LServerInfo, LServerCapabilities: TJSONObject;
  LResultPair: TJSonValue;
  LURL: string;
  LRequestBodyStream: TStringStream;
  LHttpResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
begin
  FBusy := True;
  FLastError := '';
  LRequestObj := TJSONObject.Create;
  try
    Inc(FRequestIDCounter);
    LRequestObj.AddPair('jsonrpc', '2.0');
    LRequestObj.AddPair('id', FRequestIDCounter);
    LRequestObj.AddPair('method', 'initialize');

    LParams := TJSONObject.Create;
    LRequestObj.AddPair('params', LParams);

    LParams.AddPair('protocolVersion', '2025-06-18');

    LClientInfo := TJSONObject.Create;
    LParams.AddPair('clientInfo', LClientInfo);
    LClientInfo.AddPair('name', 'Delphi Client ' + Self.Name);
    LClientInfo.AddPair('version', '1.1.0');

    LCapabilities := TJSONObject.Create;
    LParams.AddPair('capabilities', LCapabilities);
    LCapabilities.AddPair('tools', TJSONObject.Create);
    LCapabilities.AddPair('resources', TJSONObject.Create);
    LCapabilities.AddPair('roots', TJSONObject.Create);
    // Add other client capabilities here if implemented (sampling, elicitation, logging)

    LURL := GetParamByName('URL') + GetParamByName('InitializeEndpointSuffix');

    LRequestBodyStream := TStringStream.Create(LRequestObj.ToJSON, TEncoding.UTF8);
    try
{$IFDEF APIDEBUG}
      LRequestBodyStream.SaveToFile('c:\temp\mcp_init_request.txt');
      LRequestBodyStream.Position := 0;
{$ENDIF}
{$IF CompilerVersion >= 35}
      FHttpClient.SendTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);
{$ENDIF}
      FHttpClient.ResponseTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);
      FHttpClient.ConnectionTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);

      FHttpClient.Accept := 'application/json';
      FHttpClient.ContentType := 'application/json';

      var
      BearerToken := GetParamByName('ApiBearerToken');
      if not BearerToken.IsEmpty and (BearerToken <> '@MCPBearerToken') then
      begin
        var
        HeaderName := GetParamByName('ApiHeaderName');
        if HeaderName.IsEmpty then
          HeaderName := 'Authorization';
        LHeaders := [TNetHeader.Create(HeaderName, ValorDeAutorizacion(BearerToken))];
      end
      else
        LHeaders := [];

      var
        LResponseStream: TMemoryStream; // Use MemoryStream for response
      LResponseStream := TMemoryStream.Create;
      try
        LHttpResponse := FHttpClient.Post(LURL, LRequestBodyStream, LResponseStream, LHeaders);
        LResponseStream.Position := 0; // Reset to read

{$IFDEF APIDEBUG}
        LResponseStream.SaveToFile('c:\temp\mcp_init_response.txt');
        LResponseStream.Position := 0; // Reset to read
{$ENDIF}
        var
        ResponseContent := LHttpResponse.ContentAsString(TEncoding.UTF8);
        DoLog(Format('SERVER -> CLIENT (HTTP %d): %s', [LHttpResponse.StatusCode, ResponseContent]));

        if LHttpResponse.StatusCode <> 200 then
          raise EMCPClientException.CreateFmt('HTTP initialization failed with status code %d: %s', [LHttpResponse.StatusCode, ResponseContent]);

        var LResponseVal := TJSONObject.ParseJSONValue(ResponseContent);
        if not (LResponseVal is TJSONObject) then
        begin
          LResponseVal.Free;
          raise EMCPClientException.Create('Failed to parse JSON initialization response from server.');
        end;
        var LResponseObj := TJSONObject(LResponseVal);
        try
          var
            LResponseID: Integer;
          if not LResponseObj.TryGetValue<Integer>('id', LResponseID) or (LResponseID <> FRequestIDCounter) then
            raise EMCPClientException.CreateFmt('Mismatched response ID during initialize. Expected %d, got %d. Raw: %s', [FRequestIDCounter, LResponseID, LResponseObj.ToJSON]);

          var
            LErrorObj: TJSONObject;
          if LResponseObj.TryGetValue<TJSONObject>('error', LErrorObj) then
            raise EMCPClientException.Create('Server returned a JSON-RPC error during initialization: ' + LErrorObj.ToJSON);

          if LResponseObj.TryGetValue('result', LResultPair) and (LResultPair is TJSONObject) then
          begin
            FreeAndNil(FServerCapabilities);
            if TJSONObject(LResultPair).TryGetValue<TJSONObject>('capabilities', LServerCapabilities) then
              FServerCapabilities := TJSONObject(LServerCapabilities.Clone)
            else
              DoLog('WARNING: Server capabilities not found in initialization response.');

            if TJSONObject(LResultPair).TryGetValue<TJSONObject>('serverInfo', LServerInfo) then
              DoLog(Format('Server Info: Name="%s", Version="%s"', [LServerInfo.GetValue<string>('name', ''), LServerInfo.GetValue<string>('version', '')]));
          end
          else
          begin
            raise EMCPClientException.Create('JSON-RPC initialization response is invalid or does not contain a result object.');
          end;
        finally
          LResponseObj.Free;
        end;
      finally
        LResponseStream.Free;
      end;
    finally
      LRequestBodyStream.Free;
    end;
  finally
    LRequestObj.Free;
    FBusy := False;
  end;
end;

procedure TMCPClientHttp.InternalSendInitializedNotification;
var
  LNotificationObj: TJSONObject;
  LURL: string;
  LRequestBodyStream: TStringStream;
  LHttpResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
begin
  FLastError := '';
  LNotificationObj := TJSONObject.Create;
  try
    DoLog('Sending MCP "notifications/initialized" (HTTP)...');
    LNotificationObj.AddPair('jsonrpc', '2.0');
    LNotificationObj.AddPair('method', 'notifications/initialized');
    LNotificationObj.AddPair('params', TJSONObject.Create);

    LURL := GetParamByName('URL') + GetParamByName('NotificationEndpointSuffix');

    LRequestBodyStream := TStringStream.Create(LNotificationObj.ToJSON, TEncoding.UTF8);
    try
{$IFDEF APIDEBUG}
      LRequestBodyStream.SaveToFile('c:\temp\mcp_initialized_notification.txt');
      LRequestBodyStream.Position := 0;
{$ENDIF}
      FHttpClient.ContentType := 'application/json';

      var
      BearerToken := GetParamByName('ApiBearerToken');
      if not BearerToken.IsEmpty and (BearerToken <> '@MCPBearerToken') then
      begin
        var
        HeaderName := GetParamByName('ApiHeaderName');
        if HeaderName.IsEmpty then
          HeaderName := 'Authorization';
        LHeaders := [TNetHeader.Create(HeaderName, ValorDeAutorizacion(BearerToken))];
      end
      else
        LHeaders := [];

      // Notifications do not wait for a response, but the server may respond with a 204 No Content or an empty 200 OK.
      // Here it is not expected to throw exceptions if the POST fails, only log a warning.
      var
        LResponseStream: TMemoryStream;
      LResponseStream := TMemoryStream.Create;
      try
        LHttpResponse := FHttpClient.Post(LURL, LRequestBodyStream, LResponseStream, LHeaders);
        LResponseStream.Position := 0; // Reset to read

{$IFDEF APIDEBUG}
        LResponseStream.SaveToFile('c:\temp\mcp_initialized_notification_response.txt');
{$ENDIF}
        var
        ResponseContent := LHttpResponse.ContentAsString(TEncoding.UTF8);
        DoLog(Format('SERVER -> CLIENT (HTTP %d): %s', [LHttpResponse.StatusCode, ResponseContent]));

        if LHttpResponse.StatusCode <> 200 then
          DoLog(Format('WARNING: HTTP notification failed with status code %d: %s', [LHttpResponse.StatusCode, ResponseContent]));
      finally
        LResponseStream.Free;
      end;
    finally
      LRequestBodyStream.Free;
    end;
  finally
    LNotificationObj.Free;
  end;
end;

// ********************************************************************************
// THE REQUESTED FUNCTION: TMCPClientHttp.InternalSendRequest
// ********************************************************************************
function TMCPClientHttp.InternalSendRequest(const AMethod: string; AParams: TJSONObject): TJSONObject;
var
  LRequestObj: TJSONObject;
  LRequestBodyStream: TStringStream;
  LHttpResponse: IHTTPResponse;
  LResultPair: TJSonValue;
  LURL: string;
  LHeaders: TNetHeaders;
  LResponseContent: string; // To store the response content
  LSpan: TAiSpan;
begin
  FBusy := True;
  FLastError := '';
  LSpan := nil;
  LRequestObj := TJSONObject.Create;
  try
    // Generate a new ID for the JSON-RPC request
    Inc(FRequestIDCounter);

    // Build the JSON-RPC request object
    LRequestObj.AddPair('jsonrpc', '2.0');
    LRequestObj.AddPair('id', FRequestIDCounter);
    LRequestObj.AddPair('method', AMethod);
    LRequestObj.AddPair('params', AParams); // AParams becomes owned by LRequestObj
    AttachModernMeta(AParams); // MCP 2026-07-28: _meta in every request of modern mode

    // Telemetry: MCP request span + trace context propagation in
    // _meta (traceparent convention of the 2026-07-28 spec). It must happen BEFORE
    // serializing the body.
    LSpan := AiSpanStart('mcp.client ' + AMethod, skClient);
    AiSpanAttr(LSpan, 'mcp.method', AMethod);
    if Assigned(LSpan) and Assigned(AParams) then
    begin
      AiSpanAttr(LSpan, 'gen_ai.tool.name', AParams.GetValue<string>('name', ''));
      if IsModernMode then
      begin
        var LMetaV := AParams.GetValue('_meta');
        if (LMetaV is TJSONObject) and not Assigned(TJSONObject(LMetaV).GetValue('traceparent')) then
          TJSONObject(LMetaV).AddPair('traceparent', LSpan.TraceParent);
      end;
    end;

    // Create a StringStream for the HTTP request body
    LRequestBodyStream := TStringStream.Create(LRequestObj.ToJSON, TEncoding.UTF8);
    Try
      try
        // Get the full URL for the RPC request
        LURL := GetParamByName('URL') + GetParamByName('RpcEndpointSuffix');

        DoLog(Format('CLIENT -> SERVER (HTTP POST to %s): %s', [LURL, LRequestBodyStream.DataString]));

{$IFDEF APIDEBUG}
        // Save the request to a file for debugging
        LRequestBodyStream.SaveToFile('c:\temp\mcp_rpc_request_' + AMethod.Replace('/', '_') + '.txt');
        LRequestBodyStream.Position := 0; // Reset the position for reading by TNetHTTPClient
{$ENDIF}
        // Configure the HTTP client timeouts
{$IF CompilerVersion >= 35}
        FHttpClient.SendTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);
{$ENDIF}
        FHttpClient.ResponseTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);
        FHttpClient.ConnectionTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);

        // Configure the Accept and Content-Type headers
        FHttpClient.Accept := 'application/json';
        FHttpClient.ContentType := 'application/json';

        // Prepare custom HTTP headers (e.g., Authorization)
        var
        BearerToken := GetParamByName('ApiBearerToken');
        if not BearerToken.IsEmpty and (BearerToken <> '@MCPBearerToken') then
        begin
          var
          HeaderName := GetParamByName('ApiHeaderName');
          if HeaderName.IsEmpty then
            HeaderName := 'Authorization';
          LHeaders := [TNetHeader.Create(HeaderName, ValorDeAutorizacion(BearerToken))];
        end
        else
          LHeaders := []; // Array vac?o si no hay token

        // MCP 2026-07-28: standard headers of stateless mode (also in the
        // server/discover probe, which is sent before negotiating the mode).
        if IsModernMode or (AMethod = 'server/discover') then
        begin
          LHeaders := LHeaders + [TNetHeader.Create('MCP-Protocol-Version', MCP_PROTOCOL_VERSION_MODERN),
            TNetHeader.Create('Mcp-Method', AMethod)];
          if Assigned(AParams) then
          begin
            var LToolName := AParams.GetValue<string>('name', '');
            if LToolName <> '' then
              LHeaders := LHeaders + [TNetHeader.Create('Mcp-Name', LToolName)];
          end;
        end;

        // Create a MemoryStream to receive the HTTP response
        var
          LResponseStream: TMemoryStream;
        LResponseStream := TMemoryStream.Create;
        try
          // Perform the HTTP POST request
          LHttpResponse := FHttpClient.Post(LURL, LRequestBodyStream, LResponseStream, LHeaders);
          LResponseStream.Position := 0; // Reset position for content reading

{$IFDEF APIDEBUG}
          // Save the response to a file for debugging
          LResponseStream.SaveToFile('c:\temp\mcp_rpc_response_' + AMethod.Replace('/', '_') + '.txt');
          LResponseStream.Position := 0; // Reset position for content reading
{$ENDIF}
          // Read the HTTP response content
          LResponseContent := (LHttpResponse.ContentAsString(TEncoding.UTF8));
          DoLog(Format('SERVER -> CLIENT (HTTP %d): %s', [LHttpResponse.StatusCode, LResponseContent]));

          // Verify the HTTP status code
          if LHttpResponse.StatusCode <> 200 then
            raise EMCPClientException.CreateFmt('HTTP request failed with status code %d: %s', [LHttpResponse.StatusCode, LResponseContent]);

          // Try to parse the JSON response
          var LResponseVal := TJSONObject.ParseJSONValue(LResponseContent);
          if not (LResponseVal is TJSONObject) then
          begin
            LResponseVal.Free;
            raise EMCPClientException.Create('Failed to parse JSON response from server.');
          end;
          var LResponseObj := TJSONObject(LResponseVal);
          try
            // Verify that the JSON-RPC response ID matches the request's
            var
              LResponseID: Integer;
            if not LResponseObj.TryGetValue<Integer>('id', LResponseID) or (LResponseID <> FRequestIDCounter) then
              raise EMCPClientException.CreateFmt('Mismatched response ID. Expected %d, got %d. Raw: %s', [FRequestIDCounter, LResponseID, LResponseObj.ToJSON]);

            // Check whether the JSON-RPC response contains an error
            var
              LErrorObj: TJSONObject;
            if LResponseObj.TryGetValue<TJSONObject>('error', LErrorObj) then
              raise EMCPClientException.Create('Server returned a JSON-RPC error: ' + LErrorObj.ToJSON);

            // Extract the result from the JSON-RPC response and clone it for the caller
            if LResponseObj.TryGetValue('result', LResultPair) and (LResultPair is TJSONObject) then
              Result := TJSONObject(LResultPair.Clone)
            else
              raise EMCPClientException.Create('JSON-RPC response is invalid or does not contain a result object.');
          finally
            // Free the JSON response object
            LResponseObj.Free;
          end;
        finally
          // Free the response MemoryStream
          LResponseStream.Free;
        end;
      except
        on E: Exception do
        begin
          // Capture any exception during the HTTP/JSON process, log it, and re-raise it
          FLastError := 'EXCEPTION during HTTP request: ' + E.Message;
          DoLog(FLastError);
          DoStatusUpdate('Network Error: ' + E.Message);
          raise; // Re-raise the exception so the calling method (e.g., Initialize) handles it
        end;
      end;
    Finally
      LRequestBodyStream.Free;
    End;
  finally
    // Telemetry: FLastError empty = success; with text marks the span as error
    AiSpanEnd(LSpan, FLastError);
    // Free the JSON-RPC request object (it will also free AParams, of which it became owner)
    LRequestObj.Free;
    // Free the request body StringStream
    // Reset the busy state
    FBusy := False;
  end;
end;

{ TMCPClientMakerAi }

constructor TMCPClientMakerAi.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // We create the HTTP client and assign it to the component for automatic memory management.
  FHttpClient := TNetHTTPClient.Create(Self);
  // We set the transport type so the factory and other mechanisms recognize it.
  TransportType := tpMakerAi;
  DoLog('TMCPClientMakerAi instance created.');
end;

destructor TMCPClientMakerAi.Destroy;
begin
  // FHttpClient is owned by the component, so it will be freed automatically.
  // No explicit code is needed here, but we keep the destructor in case something is added in the future.
  DoLog('TMCPClientMakerAi instance destroyed.');
  inherited;
end;

function TMCPClientMakerAi.ListTools: TJSONObject;
begin
  FLastError := '';
  DoLog('Executing ListTools via MakerAI REST client...');
  DoStatusUpdate('Listing tools...');
  try
    // The ListTools call has no body and uses the GET verb.
    Result := InternalSendRequest('listtools', 'GET', nil);

    if Assigned(Result) then
      DoStatusUpdate('Tools listed successfully.')
    else
      DoStatusUpdate('Failed to list tools: ' + FLastError);
  except
    on E: Exception do
    begin
      FLastError := 'Error listing tools: ' + E.Message;
      DoLog(FLastError);
      DoStatusUpdate('Failed to list tools: ' + E.Message);
      Result := nil; // Retornar nil en caso de error
    end;
  end;
end;

function TMCPClientMakerAi.CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  LBodyStream: TStringStream;
  LResultRaw: TJSONObject;
  LMethodName: string;
begin
  Result := nil;
  FLastError := '';
  DoLog(Format('Executing CallTool via MakerAI REST client: %s', [AToolName]));
  DoStatusUpdate(Format('Calling tool: %s...', [AToolName]));

  // We build the method name for the URL, as in your example: 'calltool/calculate'
  LMethodName := 'calltool/' + AToolName;

  // We create the POST request body from the JSON arguments.
  LBodyStream := TStringStream.Create(AArguments.ToJSON, TEncoding.UTF8);
  try
    // CallTool uses the POST verb and sends the arguments in the body.
    LResultRaw := InternalSendRequest(LMethodName, 'POST', LBodyStream);

    // Once the raw response is obtained, we process it to extract
    // possible media files, maintaining transparency with the rest of the framework.
    if Assigned(LResultRaw) then
    begin
      try
        Result := ProcessAndExtractMedia(LResultRaw, AExtractedMedia);
      finally
        FreeAndNil(LResultRaw); // We free the RAW result after processing it.
      end;
    end;

  except
    on E: Exception do
    begin
      FLastError := Format('Error calling tool "%s": %s', [AToolName, E.Message]);
      DoLog(FLastError);
      Result := nil; // Retornar nil en caso de error
    end;
  end;
  LBodyStream.Free; // We free the body stream.
  // AArguments is freed by the original caller; we do not touch it.

  if Assigned(Result) then
    DoStatusUpdate(Format('Tool %s called successfully.', [AToolName]))
  else
    DoStatusUpdate(Format('Failed to call tool: %s. Error: %s', [AToolName, FLastError]));
end;

function TMCPClientMakerAi.CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  ArgsObject: TJSONObject;
  i: Integer;
begin
  // This overload converts TStrings to TJSONObject for ease of use.
  ArgsObject := TJSONObject.Create;
  try
    if Assigned(AArguments) then
    begin
      for i := 0 to AArguments.Count - 1 do
      begin
        ArgsObject.AddPair(AArguments.Names[i], TJSONString.Create(AArguments.ValueFromIndex[i]));
      end;
    end;
    // Calls the main version of CallTool.
    Result := CallTool(AToolName, ArgsObject, AExtractedMedia);
  finally
    ArgsObject.Free; // We free the JSON object we created here.
  end;
end;

// --- Private Helper Method (Heart of the class) ---

function TMCPClientMakerAi.InternalSendRequest(const AMethodName, AHttpVerb: string; ABodyStream: TStream): TJSONObject;
var
  LResponse: IHTTPResponse;
  LURL: string;
  LAuthString: string;
  LBase64Auth: string;
  LHeaders: TNetHeaders;
  LDataSnapResultWrapper: TJSONObject;
  LDataSnapResultArray: TJSonArray;
  LResponseContent: string;
  LJsonRpcObject: TJSONObject; // Nested JSON-RPC object
  LResultPair: TJSonValue; // The final JSON-RPC result
begin
  FBusy := True;
  FLastError := '';
  LJsonRpcObject := nil;
  LDataSnapResultWrapper := nil;

  // 1. Obtain configuration parameters
  LURL := GetParamByName('URL') + '/' + AMethodName;
  var
  LUser := GetParamByName('Login');
  var
  LPass := GetParamByName('Password');
  var
  LTimeout := StrToIntDef(GetParamByName('Timeout'), 15000);

  DoLog(Format('Sending %s request to %s', [AHttpVerb, LURL]));

  // 2. Configure the HTTP client
  FHttpClient.ConnectionTimeout := LTimeout;
  FHttpClient.ResponseTimeout := LTimeout;
{$IF CompilerVersion >= 35}
  FHttpClient.SendTimeout := LTimeout;
{$ENDIF}
  FHttpClient.Accept := 'application/json';
  FHttpClient.ContentType := 'application/json';

  // 3. Prepare the HTTP Basic authentication header
  LAuthString := LUser + ':' + LPass;
  LBase64Auth := TNetEncoding.Base64.Encode(LAuthString);
  LHeaders := [TNetHeader.Create('Authorization', 'Basic ' + LBase64Auth)];

  try
    Try
      // 4. Make the HTTP call (GET or POST)
      if SameText(AHttpVerb, 'GET') then
      begin
        LResponse := FHttpClient.Get(LURL, nil, LHeaders);
      end
      else if SameText(AHttpVerb, 'POST') then
      begin
        if not Assigned(ABodyStream) then
          raise EMCPClientException.Create('POST request requires a body stream.');
        ABodyStream.Position := 0;
        LResponse := FHttpClient.Post(LURL, ABodyStream, nil, LHeaders);
      end
      else
      begin
        raise EMCPClientException.CreateFmt('Unsupported HTTP Verb: %s', [AHttpVerb]);
      end;

      // 5. Process the server response
      LResponseContent := LResponse.ContentAsString(TEncoding.UTF8);
      DoLog(Format('SERVER -> CLIENT (HTTP %d): %s', [LResponse.StatusCode, LResponseContent]));

      if LResponse.StatusCode <> 200 then
        raise EMCPClientException.CreateFmt('HTTP request failed. Code: %d. Message: %s', [LResponse.StatusCode, LResponseContent]);

      // 6. Parse the DataSnap wrapper
      var LDataSnapVal := TJSONObject.ParseJSONValue(LResponseContent);
      if not (LDataSnapVal is TJSONObject) then
      begin
        LDataSnapVal.Free;
        raise EMCPClientException.Create('Failed to parse JSON response (DataSnap wrapper).');
      end;
      LDataSnapResultWrapper := TJSONObject(LDataSnapVal);

      // 7. Access the "result" array
      if not LDataSnapResultWrapper.TryGetValue<TJSonArray>('result', LDataSnapResultArray) or (LDataSnapResultArray.Count = 0) then
        raise EMCPClientException.Create('DataSnap "result" array not found or empty.');

      // 8. FIX: The first element of the array is a JSONString containing the JSON-RPC.
      if not(LDataSnapResultArray.Items[0] is TJSONString) then
        raise EMCPClientException.Create('First element in DataSnap "result" array is not a JSON string.');

      var
      LJsonRpcString := (LDataSnapResultArray.Items[0] as TJSONString).Value;

      // 9. Parse the nested JSON-RPC
      var LJsonRpcVal := TJSONObject.ParseJSONValue(LJsonRpcString);
      if not (LJsonRpcVal is TJSONObject) then
      begin
        LJsonRpcVal.Free;
        raise EMCPClientException.Create('Failed to parse inner JSON-RPC string.');
      end;
      LJsonRpcObject := TJSONObject(LJsonRpcVal);

      // 10. EXTRACT the result (the actual payload) from the nested JSON-RPC
      if LJsonRpcObject.TryGetValue('result', LResultPair) then
      begin
        if LResultPair is TJSONObject then
        begin
          // We clone the result object so the caller owns it.
          Result := TJSONObject(LResultPair.Clone);
        end
        else
        begin
          // Handle the case where the JSON-RPC result is a simple value (string, number, boolean)
          // We wrap it in a JSON object to maintain consistency with the TMCPClientCustom contract
          Result := TJSONObject.Create;
          Result.AddPair('value', TJSONObject(LResultPair.Clone));
        end;
      end
      else
      begin
        // Check whether there is an error in the JSON-RPC
        var
          LErrorObj: TJSONObject;
        if LJsonRpcObject.TryGetValue<TJSONObject>('error', LErrorObj) then
          raise EMCPClientException.Create('Server returned a JSON-RPC error: ' + LErrorObj.ToJSON)
        else
          raise EMCPClientException.Create('JSON-RPC object does not contain "result" or "error" keys.');
      end;

    except
      on E: Exception do
      begin
        FLastError := 'EXCEPTION during HTTP request: ' + E.Message;
        DoLog(FLastError);
        DoStatusUpdate('Network Error: ' + E.Message);
        Result := nil;
      end;

    End;
  finally
    // Free the JSON objects we no longer need
    FreeAndNil(LDataSnapResultWrapper);
    FreeAndNil(LJsonRpcObject);
    FBusy := False;
  end;
end;

{ ============================================================================ }
{ TMCPClientSSE implementation }
{ ============================================================================ }

constructor TMCPClientSSE.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSSEThread := nil;
  FIncomingMessages := TThreadedQueue<TJSONObject>.Create(1000, INFINITE, 100);
  FRequestIDCounter := 0;
  FPendingLock := TCriticalSection.Create;
  FStashedResponses := TObjectDictionary<Integer, TJSONObject>.Create([doOwnsValues]);
  FIsConnected := False;
  FAsyncOpDone := True; // no async op in progress yet
  FProgressLock := TCriticalSection.Create;
  FThreadProgressHandlers := TDictionary<TThreadID, TMCPToolProgressProc>.Create;
  FTokenProgressHandlers := TDictionary<string, TMCPToolProgressProc>.Create;
  FLastProgressTick := 0;
  FThreadBillingHandlers := TDictionary<TThreadID, TMCPToolBillingProc>.Create;
end;

destructor TMCPClientSSE.Destroy;
var
  LJson: TJSONObject;
  Sw: TStopwatch;
begin
  StopEventStream; // sets FStopRequested=True → next DoReceiveDataEx sets ABort=True → DoRequestCompleted fires

  // Wait for the async GET thread to finish (it signals FAsyncOpDone via completion callbacks).
  // Cap at 3 s to avoid hanging forever if the SSE server never sends data.
  Sw := TStopwatch.StartNew;
  while (not FAsyncOpDone) and (Sw.ElapsedMilliseconds < 3000) do
    Sleep(50);
  Sleep(50); // extra buffer: give the callback time to fully return before we free FHttpClient

  if Assigned(FIncomingMessages) then
  begin
    FIncomingMessages.DoShutDown;
    // WATCH OUT for this guard: after DoShutDown and with an empty queue, PopItem does NOT
    // wait and returns wrSignaled with the item as nil. In the RTL
    // (System.Generics.Collections) the wait loop does not even execute
    // —it is cut short by `not FShutDown`— and exits through
    // `if (FShutDown and (FQueueSize = 0)) then Exit` with Result still in
    // wrSignaled. Without the Break, draining is an infinite closed loop: the
    // destructor never returns and its thread keeps spinning on TMonitor,
    // consuming an entire core forever.
    //
    // It happened on calera1 on 2026-09-18: 12 threads accumulated over 4 days, ~7 cores
    // burned for a week with zero requests. The profile showed ~70%
    // in TMonitor and ~15% in PopItem, with this destructor on the stack. The
    // TMCPClientStdIo destructor already had the guard; this one did not.
    // See docs/incidents/2026-09-18_hilos_mcp_sse_spin_tmonitor.md (MKAIServer).
    while FIncomingMessages.PopItem(LJson) = wrSignaled do
    begin
      if LJson = nil then
        Break;
      LJson.Free;
    end;
    FreeAndNil(FIncomingMessages);
  end;

  FStashedResponses.Free;  // doOwnsValues: frees orphaned responses
  FPendingLock.Free;
  FThreadProgressHandlers.Free;
  FTokenProgressHandlers.Free;
  FThreadBillingHandlers.Free;
  FProgressLock.Free;

  inherited;
end;

procedure TMCPClientSSE.SetThreadProgressHandler(const AHandler: TMCPToolProgressProc);
begin
  FProgressLock.Enter;
  try
    FThreadProgressHandlers.AddOrSetValue(TThread.Current.ThreadID, AHandler);
  finally
    FProgressLock.Leave;
  end;
end;

procedure TMCPClientSSE.ClearThreadProgressHandler;
begin
  FProgressLock.Enter;
  try
    FThreadProgressHandlers.Remove(TThread.Current.ThreadID);
  finally
    FProgressLock.Leave;
  end;
end;

procedure TMCPClientSSE.SetThreadBillingHandler(const AHandler: TMCPToolBillingProc);
begin
  FProgressLock.Enter;
  try
    FThreadBillingHandlers.AddOrSetValue(TThread.Current.ThreadID, AHandler);
  finally
    FProgressLock.Leave;
  end;
end;

procedure TMCPClientSSE.ClearThreadBillingHandler;
begin
  FProgressLock.Enter;
  try
    FThreadBillingHandlers.Remove(TThread.Current.ThreadID);
  finally
    FProgressLock.Leave;
  end;
end;

// Runs on the SSE reader thread. Resolves the handler by progressToken and
// invokes it. Any exception from the handler is absorbed: progress is best-effort.
procedure TMCPClientSSE.DispatchProgressNotification(AJson: TJSONObject);
var
  ParamsObj: TJSONObject;
  TokenVal: TJSONValue;
  Token, Msg: string;
  Progress, Total: Double;
  Handler: TMCPToolProgressProc;
begin
  ParamsObj := AJson.GetValue<TJSONObject>('params', nil);
  if not Assigned(ParamsObj) then
    Exit;

  TokenVal := ParamsObj.GetValue('progressToken');
  if not Assigned(TokenVal) then
    Exit;
  Token := TokenVal.Value; // TJSONString and TJSONNumber return their representation

  Progress := ParamsObj.GetValue<Double>('progress', 0);
  Total := ParamsObj.GetValue<Double>('total', 0);
  Msg := ParamsObj.GetValue<string>('message', '');

  // Any incoming progress extends the CallTool wait deadline.
  FLastProgressTick := MkGetTickCount64;

  Handler := nil;
  FProgressLock.Enter;
  try
    FTokenProgressHandlers.TryGetValue(Token, Handler);
  finally
    FProgressLock.Leave;
  end;

  if Assigned(Handler) then
  begin
    try
      Handler(Progress, Total, Msg);
    except
      on E: Exception do
        DoLog('SSE progress handler error: ' + E.Message);
    end;
  end;
end;

// -----------------------------------------------------------------------------
// CONNECTION AND STREAMING LOGIC
// -----------------------------------------------------------------------------

procedure TMCPClientSSE.StartEventStream;
var
  LURL: string;
begin
  if FIsConnected then
    Exit;

  LURL := GetParamByName('URL');
  if LURL.IsEmpty then
    raise EMCPClientException.Create('URL parameter is missing for SSE client.');

  FBuffer := '';
  FPostEndpoint := '';
  FStopRequested := False;
  FAsyncOpDone := False;

  DoLog('SSE: Starting raw TCP SSE stream to ' + LURL);
  FIsConnected := True;

  // Use a raw Indy TCP connection so we read ALL bytes regardless of
  // Content-Length (some MCP server binaries incorrectly set Content-Length
  // to the size of just the SSE handshake, truncating the session_id).
  FSSEThread := TThread.CreateAnonymousThread(
    procedure
    var
      Uri: TURI;
      Host, Path, Line, Request: string;
      BearerToken, HeaderName, AuthLine: string;
      Port: Integer;
      Sock: TIdTCPClient;
    begin
      try
        Uri := TURI.Create(LURL);
        Host := Uri.Host;
        Port := Uri.Port;
        if Port <= 0 then
          Port := 80;
        Path := Uri.Path;
        if Path = '' then Path := '/';
        if Uri.Query <> '' then
          Path := Path + '?' + Uri.Query;

        Sock := TIdTCPClient.Create(nil);
        try
          Sock.Host := Host;
          Sock.Port := Port;
          Sock.ConnectTimeout := 10000;
          Sock.Connect;
          Sock.IOHandler.ReadTimeout := 500;
          // Tool results can be VERY large (base64 images:
          // several MB in a single SSE line). Indy's default is 16 KB and
          // ReadLn would throw EIdReadLnMaxLineLengthExceeded killing the stream.
          Sock.IOHandler.MaxLineLength := MaxInt;

          // Send GET — do NOT send Connection: close so the server keeps the
          // TCP link open after the 81-byte handshake for future SSE events.
          // The credential also goes in the SSE stream GET: servers like
          // mkflowd require the key in EVERY request, not only in POSTs.
          AuthLine := '';
          BearerToken := GetParamByName('ApiBearerToken');
          if (not BearerToken.IsEmpty) and (BearerToken <> '@MCPBearerToken') then
          begin
            HeaderName := GetParamByName('ApiHeaderName');
            if HeaderName.IsEmpty then
              HeaderName := 'Authorization';
            AuthLine := HeaderName + ': ' + ValorDeAutorizacion(BearerToken) + #13#10;
          end;

          Request :=
            'GET ' + Path + ' HTTP/1.1' + #13#10 +
            'Host: ' + Host + ':' + IntToStr(Port) + #13#10 +
            'Accept: text/event-stream' + #13#10 +
            AuthLine +
            'Cache-Control: no-cache' + #13#10 +
            'Connection: keep-alive' + #13#10 + #13#10;
          Sock.IOHandler.Write(Request);

          // Skip HTTP response headers — intentionally ignore Content-Length
          repeat
            Line := Sock.IOHandler.ReadLn(#10, 5000);
            Line := Line.TrimRight([' ', #13]);
          until (Line = '') or FStopRequested;

          // Stream SSE body lines until stopped or connection lost.
          // Use a blocking ReadLn with a short timeout so the OS wakes this
          // thread immediately when data arrives (no 100ms polling lag on
          // loaded systems where CheckForDataOnSource can starve).
          Sock.IOHandler.ReadTimeout := 500;
          while not FStopRequested do
          begin
            try
              Line := Sock.IOHandler.ReadLn(#10);
              Line := Line.TrimRight([' ', #13]);
              ProcessSSELine(Line);
            except
              on E: EIdReadTimeout do
                ; // no data in 500ms — check FStopRequested and retry
              on E: Exception do Break;  // connection closed or read error
            end;
          end;

          DoLog('SSE: Stream ended (raw TCP)');
        finally
          try Sock.Disconnect; except end;
          Sock.Free;
        end;
      except
        on E: Exception do
          DoLog('SSE: TCP connection error: ' + E.Message);
      end;

      FIsConnected := False;
      FAsyncOpDone := True;
    end
  );
  FSSEThread.FreeOnTerminate := True;
  FSSEThread.Start;
end;

procedure TMCPClientSSE.StopEventStream;
begin
  FStopRequested := True; // This will cause Abort := True on the next OnReceiveData event
  FIsConnected := False;
end;

// (TNetHTTPClient callbacks removed — SSE stream is now read by FSSEThread via
//  raw Indy TCP, which ignores Content-Length and reads until connection close.)

procedure TMCPClientSSE.ProcessSSELine(const ALine: string);
var
  P: Integer;
  LKey, LValue: string;
  JObj: TJSONObject;
begin
  P := Pos(':', ALine);
  if P = 0 then Exit;

  LKey := Trim(Copy(ALine, 1, P - 1));
  LValue := Trim(Copy(ALine, P + 1, Length(ALine)));

  // Optional: Log to debug what arrives processed
  // DoStreamMessage(LKey, LValue);

  if SameText(LKey, 'event') and SameText(LValue, 'endpoint') then
  begin
    DoLog('SSE: Endpoint event signal received.');
  end
  else if SameText(LKey, 'data') then
  begin
    // ROBUST LOGIC:
    // If we do not yet have the POST URL (FPostEndpoint is empty)...
    // And the received data does NOT look like JSON (does not start with '{')...
    // Then we ASSUME it is the URL sent by the server.
    if (FPostEndpoint = '') and (not LValue.StartsWith('{')) then
    begin
      FPostEndpoint := LValue;

      // If the URL is relative (/messages...), we prepend the base host.
      if FPostEndpoint.StartsWith('/') then
      begin
        var BaseUri := TURI.Create(GetParamByName('URL'));
        var BaseStr := Format('%s://%s', [BaseUri.Scheme, BaseUri.Host]);
        if BaseUri.Port > 0 then
          BaseStr := BaseStr + ':' + IntToStr(BaseUri.Port);
        FPostEndpoint := BaseStr + FPostEndpoint;
      end;

      DoLog('SSE Handshake: POST Endpoint SET to: ' + FPostEndpoint);
    end
    else
    begin
      // It is a normal data message (JSON-RPC)
      try
        var LVal := TJSONObject.ParseJSONValue(LValue);
        if not (LVal is TJSONObject) then
          LVal.Free
        else
        begin
          JObj := TJSONObject(LVal);
          // Progress notifications are dispatched right here (they do not enter
          // the queue: InternalReceiveJSONResponse would discard them for not having an id).
          if (JObj.GetValue('id') = nil) and
             SameText(JObj.GetValue<string>('method', ''), 'notifications/progress') then
          begin
            DispatchProgressNotification(JObj);
            JObj.Free;
          end
          else if FIncomingMessages.PushItem(JObj) <> wrSignaled then
            JObj.Free;
        end;
      except
        // Ignore parse errors in keep-alives or garbage
      end;
    end;
  end;
end;

// -----------------------------------------------------------------------------
// INITIALIZE AND LIFECYCLE (Identical to the previous version)
// -----------------------------------------------------------------------------

function TMCPClientSSE.WaitForInitialization(ATimeout: Integer): Boolean;
var
  Sw: TStopwatch;
begin
  Result := False;
  Sw := TStopwatch.StartNew;
  while Sw.ElapsedMilliseconds < ATimeout do
  begin
    if FPostEndpoint <> '' then
      Exit(True);

    Sleep(10); // CheckSynchronize is main-thread-only; on Indy worker threads it blocks forever
  end;
end;

function TMCPClientSSE.Initialize: Boolean;
var
  InitParams, InitResult, Notif, ToolsParams, ToolsResult: TJSONObject;
begin
  Result := False;
  DoLog(Format('MCP Init START: name=%s url=%s', [Name, GetParamByName('URL')]));
  DoStatusUpdate('Connecting to MCP via SSE...');

  StartEventStream;

  if not WaitForInitialization(5000) then
  begin
    FLastError := 'Timeout waiting for SSE handshake (endpoint URL).';
    DoLog(FLastError);
    StopEventStream;
    Exit;
  end;

  DoLog('SSE: Post endpoint confirmed: ' + FPostEndpoint);

  try
    InitParams := TJSONObject.Create;
    InitParams.AddPair('protocolVersion', '2025-06-18');
    InitParams.AddPair('capabilities', TJSONObject.Create);

    var
    ClientInfo := TJSONObject.Create;
    ClientInfo.AddPair('name', 'DelphiMCPClient');
    ClientInfo.AddPair('version', '1.0');
    InitParams.AddPair('clientInfo', ClientInfo);

    DoLog('SSE: Sending initialize request...');
    InitResult := InternalSendRequest('initialize', InitParams);

    if Assigned(InitResult) then
    begin
      DoLog('SSE: initialize OK, sending initialized notification...');
      InitResult.Free;

      Notif := TJSONObject.Create;
      InternalSendRequest('notifications/initialized', Notif);

      DoLog('SSE: Requesting tools/list...');
      ToolsParams := TJSONObject.Create;
      ToolsResult := InternalSendRequest('tools/list', ToolsParams);

      if Assigned(ToolsResult) then
      begin
        try
          FTools.Text := ToolsResult.ToJSON;
          DoLog(Format('SSE: tools/list OK, %d tools loaded', [ToolsResult.Count]));
        finally
          ToolsResult.Free;
        end;
      end
      else
        DoLog('SSE: tools/list returned nil (timeout or disconnected)');

      Initialized := True;
      Available := True;
      Enabled := True;
      Result := True;
      DoStatusUpdate('SSE Client Initialized Successfully.');
    end
    else
    begin
      FLastError := 'Failed to receive response to initialize request.';
      DoLog(FLastError);
    end;

  except
    on E: Exception do
    begin
      FLastError := 'SSE Initialization Exception: ' + E.Message;
      DoLog(FLastError);
      StopEventStream;
    end;
  end;
end;

// -----------------------------------------------------------------------------
// SENDING REQUESTS (Identical to the previous version, adjusted to components)
// -----------------------------------------------------------------------------

function TMCPClientSSE.InternalSendRequest(const AMethod: string; AParams: TJSONObject): TJSONObject;
var
  Req: TJSONObject;
  Source: TStringStream;
  LHeaders: TNetHeaders;
  LocalClient: TNetHTTPClient;
  LId: Integer;
begin
  if FPostEndpoint = '' then
    raise EMCPClientException.Create('Cannot send request: Post Endpoint not initialized.');

  Req := TJSONObject.Create;
  try
    // The id goes in a LOCAL variable. Previously it was Inc(FRequestIDCounter) and then
    // it expected FRequestIDCounter: with two parallel tools/call (the driver
    // of Claude spawns a TTask per tool_use) both threads waited for the id of the
    // second and the first one timed out.
    LId := AtomicIncrement(FRequestIDCounter);
    Req.AddPair('jsonrpc', '2.0');
    Req.AddPair('method', AMethod);

    if not AMethod.StartsWith('notifications/') then
      Req.AddPair('id', LId);

    if Assigned(AParams) then
      Req.AddPair('params', AParams);

    DoLog('CLIENT (POST) -> SERVER: ' + Req.ToJSON);

    Source := TStringStream.Create(Req.ToJSON, TEncoding.UTF8);
    try
      // IMPORTANT: For the POST, we use a temporary SYNCHRONOUS client or we reuse one.
      // If we use FHttpClient, which is in Asynchronous=True mode, Post will return immediately
      // and does not guarantee order if mixed with the stream.
      // Best practice: Create a lightweight client for the synchronous POST.

      LocalClient := TNetHTTPClient.Create(nil);
      try
        LocalClient.ContentType := 'application/json';
        LocalClient.ConnectionTimeout := 10000;
        LocalClient.ResponseTimeout := 15000;

        var
        Token := GetParamByName('ApiBearerToken');
        if (Token <> '') and (Token <> '@MCPBearerToken') then
          LHeaders := [TNetHeader.Create('Authorization', ValorDeAutorizacion(Token))]
        else
          LHeaders := [];

        LocalClient.Post(FPostEndpoint, Source, nil, LHeaders);
      finally
        LocalClient.Free;
      end;

    finally
      Source.Free;
    end;

    if AMethod.StartsWith('notifications/') then
      Exit(nil);

    // tools/call can be long-running (image, external processes): timeout
    // configurable via Params['CallToolTimeoutMs'] (default 180 s) which also
    // extends while the server keeps sending notifications/progress.
    if AMethod = 'tools/call' then
      Result := InternalReceiveJSONResponse(LId,
        StrToIntDef(GetParamByName('CallToolTimeoutMs'), 180000))
    else
      Result := InternalReceiveJSONResponse(LId);

  finally
    Req.Free;
  end;
end;

function TMCPClientSSE.InternalReceiveJSONResponse(AExpectedID: Integer; ATimeoutMs: Cardinal): TJSONObject;
const
  // Absolute ceiling even if progress notifications keep arriving (10 min).
  ABS_MAX_WAIT_MS = 600000;
var
  LJson: TJSONObject;
  Sw: TStopwatch;
  Id: Integer;
  WR: TWaitResult;

  function StillWaiting: Boolean;
  begin
    // Base deadline, extended if the server keeps reporting progress
    // (a live tool should not die by timeout while it signals it is progressing).
    Result := (Sw.ElapsedMilliseconds < ATimeoutMs) or
      ((MkGetTickCount64 - FLastProgressTick < Int64(ATimeoutMs)) and
       (Sw.ElapsedMilliseconds < ABS_MAX_WAIT_MS));
  end;

  // Extracts the 'result' (or the whole message if it is an error) and frees AJson
  function TakeResult(AJson: TJSONObject): TJSONObject;
  var
    ResVal: TJSONValue;
  begin
    if AJson.TryGetValue('result', ResVal) and (ResVal is TJSONObject) then
      Result := TJSONObject(ResVal.Clone)
    else
      Result := TJSONObject(AJson.Clone);
    AJson.Free;
  end;

  // Did another thread already pull the response for THIS request from the queue?
  function TryTakeStashed(out AJson: TJSONObject): Boolean;
  begin
    FPendingLock.Enter;
    try
      Result := FStashedResponses.ContainsKey(AExpectedID);
      if Result then
        AJson := FStashedResponses.ExtractPair(AExpectedID).Value;
    finally
      FPendingLock.Leave;
    end;
  end;

begin
  Result := nil;
  Sw := TStopwatch.StartNew;

  // The pooled client handles multiple requests at once and they all share ONE
  // queue. Whoever pulls someone else's response leaves it in FStashedResponses for its
  // owner instead of freeing it (that lost responses: see the declaration).
  while StillWaiting do
  begin
    if TryTakeStashed(LJson) then
      Exit(TakeResult(LJson));

    // PopItem waits up to 100 ms (queue's PopTimeout). Any other
    // result that is not wrSignaled/wrTimeout returns immediately: pause to
    // avoid spinning idle.
    WR := FIncomingMessages.PopItem(LJson);
    if (WR <> wrSignaled) and (WR <> wrTimeout) then
      Sleep(10);
    if WR = wrSignaled then
    begin
      // After DoShutDown with an empty queue, PopItem returns wrSignaled with nil
      // (see the destructor: this is how cores burned on calera1).
      if LJson = nil then
        Break;
      if LJson.TryGetValue('id', Id) then
      begin
        if Id = AExpectedID then
          Exit(TakeResult(LJson));
        FPendingLock.Enter;
        try
          // Hygiene limit: responses whose owner already timed out never
          // get claimed. With 256 pending, something is very wrong; they are discarded.
          if FStashedResponses.Count >= 256 then
            FStashedResponses.Clear;
          FStashedResponses.AddOrSetValue(Id, LJson);
        finally
          FPendingLock.Leave;
        end;
        Continue;  // there may be more in the queue: without waiting
      end
      else
        LJson.Free;  // without id: a notification already dispatched by the reader
    end;

    if not FIsConnected then
    begin
      DoLog(Format('SSE: Connection lost while waiting for response id=%d', [AExpectedID]));
      Break;
    end;
  end;
  if Result = nil then
    DoLog(Format('SSE: Timeout/nil for response id=%d (waited %dms)', [AExpectedID, Sw.ElapsedMilliseconds]));
end;

// ListTools and CallTool are identical to the previous versions you already had
function TMCPClientSSE.ListTools: TJSONObject;
begin
  var
  Params := TJSONObject.Create;
  Result := InternalSendRequest('tools/list', Params);
end;

function TMCPClientSSE.CallTool(const AToolName: string; AArguments: TJSONObject; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  Params, ResultRaw, Meta: TJSONObject;
  Handler: TMCPToolProgressProc;
  Token: string;
begin
  Result := nil;
  Params := TJSONObject.Create;
  Params.AddPair('name', AToolName);
  if Assigned(AArguments) then
    Params.AddPair('arguments', AArguments);

  // If the calling thread registered a progress handler, we associate a
  // progressToken with THIS call and send it in _meta according to the MCP spec.
  // Fallback: if the tool runs on a thread different from the one that registered
  // (drivers that process tool-calls on another thread) and there is a SINGLE
  // handler registered, that one is used. With multiple concurrent handlers only
  // the exact thread match applies (prevents cross-talk between requests).
  Token := '';
  Handler := nil;
  FProgressLock.Enter;
  try
    if not FThreadProgressHandlers.TryGetValue(TThread.Current.ThreadID, Handler) then
      if FThreadProgressHandlers.Count = 1 then
        for Handler in FThreadProgressHandlers.Values do
          Break;
  finally
    FProgressLock.Leave;
  end;
  if Assigned(Handler) then
  begin
    Token := 'pt-' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').ToLower;
    FProgressLock.Enter;
    try
      FTokenProgressHandlers.Add(Token, Handler);
    finally
      FProgressLock.Leave;
    end;
    Meta := TJSONObject.Create;
    Meta.AddPair('progressToken', Token);
    Params.AddPair('_meta', Meta);
  end;

  if Assigned(AArguments) then
    DoLog(Format('SSE CallTool: %s args=%s', [AToolName, AArguments.ToJSON]))
  else
    DoLog(Format('SSE CallTool: %s (no args)', [AToolName]));
  try
    try
      ResultRaw := InternalSendRequest('tools/call', Params);
      if Assigned(ResultRaw) then
      begin
        DoLog('SSE CallTool result: ' + ResultRaw.ToJSON);
        Result := ProcessAndExtractMedia(ResultRaw, AExtractedMedia);
        ResultRaw.Free;
        // Notify billing handler (best-effort, same thread fallback as progress)
        if Assigned(Result) then
        begin
          var BillingHandler: TMCPToolBillingProc := nil;
          FProgressLock.Enter;
          try
            if not FThreadBillingHandlers.TryGetValue(TThread.Current.ThreadID, BillingHandler) then
              if FThreadBillingHandlers.Count = 1 then
                for BillingHandler in FThreadBillingHandlers.Values do Break;
          finally
            FProgressLock.Leave;
          end;
          if Assigned(BillingHandler) then
            try BillingHandler(AToolName); except end;
        end;
      end
      else
        DoLog('SSE CallTool: nil result (timeout or disconnected)');
    except
      on E: Exception do
        DoLog('SSE CallTool Error: ' + E.Message);
    end;
  finally
    if Token <> '' then
    begin
      FProgressLock.Enter;
      try
        FTokenProgressHandlers.Remove(Token);
      finally
        FProgressLock.Leave;
      end;
    end;
  end;
end;

function TMCPClientSSE.CallTool(const AToolName: string; AArguments: TStrings; AExtractedMedia: TObjectList<TAiMediaFile>): TJSONObject;
var
  ArgsObj: TJSONObject;
  i: Integer;
begin
  ArgsObj := TJSONObject.Create;
  if Assigned(AArguments) then
    for i := 0 to AArguments.Count - 1 do
      ArgsObj.AddPair(AArguments.Names[i], AArguments.ValueFromIndex[i]);

  Result := CallTool(AToolName, ArgsObj, AExtractedMedia);
end;

end.
