program MCPServerHTTP;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 02-Server-HTTP
// =============================================================================
// MCP server via HTTP protocol (JSON-RPC over HTTP).
// Protocol ideal for REST clients or remote integrations.
//
// Concepts covered:
//   - TAiMCPHttpServer: MCP server via HTTP
//   - Server.Port: listening port (default 8080)
//   - Server.CorsEnabled / CorsAllowedOrigins: CORS for web access
//   - Same set of tools as the StdIO server
//
// Endpoints:
//   GET  http://localhost:8080/mcp  -> Server info
//   POST http://localhost:8080/mcp  -> JSON-RPC commands
//
// Tools: get_datetime, greet (same as 01-Server-StdIO)
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
  uMakerAi.MCPServer.Core,
  uMakerAi.MCPServer.Http;

// =============================================================================
//  Tool: get_datetime
// =============================================================================
type
  TDateTimeParams = class
  private
    FFormat: String;
  public
    [AiMCPSchemaDescription('Format: "iso" (ISO-8601, default) or "readable" (readable text)')]
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
  FDescription := 'Returns the current date and time of the server in the requested format.';
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
    Saludo := Format('Hello, %s! Welcome to MakerAI MCP HTTP Server.', [NombrePersona])
  else
    Saludo := Format('Hello, %s! Welcome to the MakerAI MCP HTTP server.', [NombrePersona]);
  Result := TAiMCPResponseBuilder.New.AddText(Saludo).Build;
end;

// =============================================================================
//  MAIN
// =============================================================================
var
  Server: TAiMCPHttpServer;

begin
  try
    Server := TAiMCPHttpServer.Create(nil);
    try
      Server.ServerName       := 'MakerAI-Demo-HTTP';
      Server.Port             := 8080;
      Server.CorsEnabled      := True;
      Server.CorsAllowedOrigins := '*';

      // Register tools
      Server.RegisterTool('get_datetime',
        function: IAiMCPTool begin Result := TDateTimeMCPTool.Create; end);
      Server.RegisterTool('greet',
        function: IAiMCPTool begin Result := TGreetMCPTool.Create; end);

      Server.Start;

      Writeln;
      Writeln('=== MCPServerHTTP ===');
      Writeln(Format('HTTP server listening on port %d', [Server.Port]));
      Writeln('Registered tools: get_datetime, greet');
      Writeln;
      Writeln('Endpoints:');
      Writeln(Format('  GET  http://localhost:%d/mcp  -> Server info', [Server.Port]));
      Writeln(Format('  POST http://localhost:%d/mcp  -> JSON-RPC commands', [Server.Port]));
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
