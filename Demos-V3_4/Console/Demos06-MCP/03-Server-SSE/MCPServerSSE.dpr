program MCPServerSSE;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 03-Server-SSE
// =============================================================================
// MCP server via SSE protocol (Server-Sent Events over HTTP).
// Modern protocol compatible with Claude Desktop and standard MCP clients.
//
// Concepts it covers:
//   - TAiMCPSSEHttpServer: MCP server via SSE + HTTP
//   - Difference SSE vs HTTP vs StdIO
//   - SSE endpoints: /sse (stream) and /messages (commands)
//   - Configuration for Claude Desktop
//
// Endpoints:
//   GET  http://localhost:8080/sse       -> SSE stream (connect first)
//   POST http://localhost:8080/messages  -> JSON-RPC commands
//
// Tools: get_datetime, greet
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
  uMakerAi.MCPServer.Core,
  uMakerAi.MCPServer.Bridge,
  uMakerAi.MCPServer.SSE;

// =============================================================================
//  Tool: get_datetime
// =============================================================================
type
  TDateTimeParams = class
  private
    FFormat: String;
  public
    [AiMCPSchemaDescription('Format: "iso" (ISO-8601) or "readable" (readable text)')]
    property Format: String read FFormat write FFormat;
  end;

  TDateTimeMCPTool = class(TAiMCPToolBase<TDateTimeParams>)
  protected
    function ExecuteWithParams(const AParams: TDateTimeParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

constructor TDateTimeMCPTool.Create;
begin
  inherited;
  FName        := 'get_datetime';
  FDescription := 'Returns the current server date and time.';
end;

function TDateTimeMCPTool.ExecuteWithParams(const AParams: TDateTimeParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Fmt, Resultado: String;
begin
  Fmt := Trim(LowerCase(AParams.Format));
  if Fmt = 'readable' then
    Resultado := FormatDateTime('"Today is" dddd, d "of" mmmm "of" yyyy, "at" hh:nn:ss', Now)
  else
    Resultado := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  Result := TAiMCPResponseBuilder.New.AddText(Resultado).Build;
end;

// =============================================================================
//  Tool: greet
// =============================================================================
type
  TGreetParams = class
  private
    FName    : String;
    FLanguage: String;
  public
    [AiMCPSchemaDescription('Name of the person to greet')]
    property Name: String read FName write FName;
    [AiMCPSchemaDescription('Language: "es" Spanish (default), "en" English')]
    property Language: String read FLanguage write FLanguage;
  end;

  TGreetMCPTool = class(TAiMCPToolBase<TGreetParams>)
  protected
    function ExecuteWithParams(const AParams: TGreetParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

constructor TGreetMCPTool.Create;
begin
  inherited;
  FName        := 'greet';
  FDescription := 'Generates a personalized greeting in Spanish or English.';
end;

function TGreetMCPTool.ExecuteWithParams(const AParams: TGreetParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  NombrePersona, Lang, Saludo: String;
begin
  NombrePersona := Trim(AParams.Name);
  if NombrePersona = '' then NombrePersona := 'mundo';
  Lang := Trim(LowerCase(AParams.Language));
  if Lang = 'en' then
    Saludo := Format('Hello, %s! Welcome to MakerAI MCP SSE Server.', [NombrePersona])
  else
    Saludo := Format('Hola, %s! Bienvenido al servidor MCP SSE de MakerAI.', [NombrePersona]);
  Result := TAiMCPResponseBuilder.New.AddText(Saludo).Build;
end;

// =============================================================================
//  MAIN
// =============================================================================
var
  Server: TAiMCPSSEHttpServer;

begin
  try
    Server := TAiMCPSSEHttpServer.Create(nil);
    try
      Server.ServerName         := 'MakerAI-Demo-SSE';
      Server.Port               := 8080;
      Server.CorsEnabled        := True;
      Server.CorsAllowedOrigins := '*';

      // Register tools
      Server.RegisterTool('get_datetime',
        function: IAiMCPTool begin Result := TDateTimeMCPTool.Create; end);
      Server.RegisterTool('greet',
        function: IAiMCPTool begin Result := TGreetMCPTool.Create; end);

      Server.Start;

      Writeln;
      Writeln('=== MCPServerSSE ===');
      Writeln(Format('SSE server active on port %d', [Server.Port]));
      Writeln('Tools: get_datetime, greet');
      Writeln;
      Writeln('SSE endpoints:');
      Writeln(Format('  GET  http://localhost:%d/sse       -> SSE stream', [Server.Port]));
      Writeln(Format('  POST http://localhost:%d/messages  -> JSON-RPC commands', [Server.Port]));
      Writeln;
      Writeln('Configuration for Claude Desktop (claude_desktop_config.json):');
      Writeln('{');
      Writeln('  "mcpServers": {');
      Writeln('    "makerai-demo": {');
      Writeln('      "command": "ruta\\al\\MCPServerSSE.exe",');
      Writeln('      "args": []');
      Writeln('    }');
      Writeln('  }');
      Writeln('}');
      Writeln;
      Writeln('Press Enter to stop...');
      Readln;

    finally
      Server.Stop;
      Server.Free;
    end;
  except
    on E: Exception do
      Writeln('Fatal error: ', E.ClassName, ': ', E.Message);
  end;
end.
