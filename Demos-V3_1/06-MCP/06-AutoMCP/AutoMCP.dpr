program AutoMCP;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 06-AutoMCP
// =============================================================================
// AutoMCP: downloads and installs MCP servers from the PPM registry
// (https://registry.cimamaker.com) automatically.
// The LLM can use the installed tools without manual configuration.
//
// Concepts covered:
//   - FFunctions.AutoMCPConfig.Active: activates the AutoMCP system
//   - FFunctions.AutoMCPConfig.RegistryUrl: PPM registry URL
//   - FFunctions.InstallMCPFromPPM(name, params, env, registryUrl)
//   - FFunctions.GetAutoMCPSystemPrompt(): system prompt for AutoMCP
//   - TMCPClientItem.MCPClient.Initialize: start the server process
//   - TMCPClientItem.MCPClient.Available: check availability
//   - TAiChatConnection with auto-installed MCP tools
//
// PPM packages installed: mcp-calculator (if available in the registry)
// PPM registry: https://registry.cimamaker.com
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Tools.Functions,
  uMakerAi.MCPClient.Core,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

const
  DRIVER      = 'Claude';
  MODEL       = 'claude-haiku-4-5-20251001';
  API_KEY     = '@CLAUDE_API_KEY';
  REGISTRY    = 'https://registry.cimamaker.com';
  MCP_PACKAGE = 'mcp-calculator';

// =============================================================================
//  Demo
// =============================================================================
type
  TAutoMCPDemo = class
  private
    FFunctions: TAiFunctions;
    FAiConn   : TAiChatConnection;
    FLastError: String;

    procedure OnLog   (Sender: TObject; const Msg: String);
    procedure OnStatus(Sender: TObject; const Msg: String);
    procedure OnError (Sender: TObject; const ErrorMsg: String;
      AException: Exception; const AResponse: IHTTPResponse);
    procedure OnState (Sender: TObject; State: TAiChatState; const Desc: String);

    procedure InstalarPaquete;
    procedure ListarHerramientas;
    procedure ChatConHerramientas;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Run;
  end;

constructor TAutoMCPDemo.Create;
begin
  inherited;

  FFunctions := TAiFunctions.Create(nil);
  FFunctions.OnLog          := OnLog;
  FFunctions.OnStatusUpdate := OnStatus;

  // Activate AutoMCP with the PPM registry
  FFunctions.AutoMCPConfig.Active      := True;
  FFunctions.AutoMCPConfig.RegistryUrl := REGISTRY;

  FAiConn := TAiChatConnection.Create(nil);
  FAiConn.AiFunctions              := FFunctions;
  FAiConn.OnError                  := OnError;
  FAiConn.OnStateChange            := OnState;
  FAiConn.DriverName               := DRIVER;
  FAiConn.Model                    := MODEL;
  FAiConn.Params.Values['ApiKey']  := API_KEY;
  FAiConn.RegisterUserParam(DRIVER, 'Tool_Active',     'True');
  FAiConn.RegisterUserParam(DRIVER, 'Asynchronous',    'False');
  FAiConn.RegisterUserParam(DRIVER, 'Max_Tokens',      '4096');
  FAiConn.RegisterUserParam(DRIVER, 'ResponseTimeOut', '120000');

  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;
end;

destructor TAutoMCPDemo.Destroy;
begin
  FAiConn.Free;
  FFunctions.Free;
  inherited;
end;

procedure TAutoMCPDemo.OnLog(Sender: TObject; const Msg: String);
begin
  Writeln('  [MCP] ', Msg);
end;

procedure TAutoMCPDemo.OnStatus(Sender: TObject; const Msg: String);
begin
  Writeln('  [STS] ', Msg);
end;

procedure TAutoMCPDemo.OnError(Sender: TObject; const ErrorMsg: String;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FLastError := ErrorMsg;
  Writeln('  [ERR] ', ErrorMsg);
end;

procedure TAutoMCPDemo.OnState(Sender: TObject; State: TAiChatState;
  const Desc: String);
begin
  case State of
    acsToolCalling  : Writeln('  [LLM] Calling tool...');
    acsToolExecuting: Writeln('  [LLM] Executing...');
  end;
end;

procedure TAutoMCPDemo.InstalarPaquete;
var
  LItem: TMCPClientItem;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('STEP 1 — Install ', MCP_PACKAGE, ' from PPM');
  Writeln(StringOfChar('-', 60));

  // Check if already installed
  LItem := FFunctions.MCPClients.GetClientByName(MCP_PACKAGE);
  if Assigned(LItem) then
  begin
    Writeln('  Already installed: ', LItem.Params.Values['Command']);
    if not LItem.MCPClient.Initialized then
      LItem.MCPClient.Initialize;
    Writeln('  Available: ', BoolToStr(LItem.MCPClient.Available, True));
    Exit;
  end;

  // Install from PPM
  Writeln('  Downloading and installing ', MCP_PACKAGE, '...');
  try
    LItem := FFunctions.InstallMCPFromPPM(MCP_PACKAGE, '', '', REGISTRY);
    if not Assigned(LItem) then
    begin
      Writeln('  WARNING: InstallMCPFromPPM returned nil.');
      Writeln('  Possible causes: no connectivity or package not available.');
      Exit;
    end;

    Writeln('  Installed at: ', LItem.Params.Values['Command']);

    // Initialize the process
    if not LItem.MCPClient.Initialized then
      LItem.MCPClient.Initialize;

    if LItem.MCPClient.Available then
      Writeln('  MCP server active and available.')
    else
      Writeln('  WARNING: The MCP server is not available.');
  except
    on E: Exception do
      Writeln('  ERROR installing: ', E.Message);
  end;
end;

procedure TAutoMCPDemo.ListarHerramientas;
var
  LItem    : TMCPClientItem;
  LToolsJ  : TJSONObject;
  LArr     : TJSONArray;
  LName, LDesc: String;
  T        : TJSONValue;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('STEP 2 — List tools of ', MCP_PACKAGE);
  Writeln(StringOfChar('-', 60));

  LItem := FFunctions.MCPClients.GetClientByName(MCP_PACKAGE);
  if not Assigned(LItem) or not LItem.MCPClient.Available then
  begin
    Writeln('  Package not available, skipping.');
    Exit;
  end;

  LToolsJ := LItem.MCPClient.ListTools;
  try
    if Assigned(LToolsJ) and LToolsJ.TryGetValue<TJSONArray>('tools', LArr) then
    begin
      Writeln(Format('  Tools found: %d', [LArr.Count]));
      for T in LArr do
        if T is TJSONObject then
        begin
          TJSONObject(T).TryGetValue<String>('name',        LName);
          TJSONObject(T).TryGetValue<String>('description', LDesc);
          Writeln(Format('    [%s] %s', [LName, LDesc]));
        end;
    end;
  finally
    LToolsJ.Free;
  end;
end;

procedure TAutoMCPDemo.ChatConHerramientas;
var
  Pregunta, Resp: String;
begin
  Writeln(StringOfChar('=', 60));
  Writeln('STEP 3 — LLM chat + AutoMCP tools');
  Writeln(StringOfChar('-', 60));

  // Update the system prompt with the available tools
  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;

  Pregunta := 'How much is 1234 times 5678?';
  Writeln('Question: ', Pregunta);
  try
    Resp := FAiConn.AddMessageAndRun(Pregunta, 'user', []);
    Writeln('Answer: ', Resp);
  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;
  Writeln;

  Pregunta := 'What is the square root of 144?';
  Writeln('Question: ', Pregunta);
  try
    Resp := FAiConn.AddMessageAndRun(Pregunta, 'user', []);
    Writeln('Answer: ', Resp);
  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;
end;

procedure TAutoMCPDemo.Run;
begin
  Writeln('=== AutoMCP Demo ===');
  Writeln('PPM registry: ', REGISTRY);
  Writeln('Package to install: ', MCP_PACKAGE);
  Writeln;

  InstalarPaquete;
  Writeln;
  ListarHerramientas;
  Writeln;
  ChatConHerramientas;
end;

var
  Demo: TAutoMCPDemo;

begin
  try
    Demo := TAutoMCPDemo.Create;
    try
      Demo.Run;
    finally
      Demo.Free;
    end;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
