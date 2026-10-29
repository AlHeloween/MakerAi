program MCPServerStdIO;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 01-Server-StdIO
// =============================================================================
// MCP server via StdIO protocol (standard input/output).
// Protocol ideal for local integration as a subprocess.
//
// Concepts it covers:
//   - TAiMCPStdioServer: MCP server via stdin/stdout
//   - TAiMCPToolBase<TParams>: base class for implementing MCP tools
//   - Server.RegisterTool(name, factory): register tools
//   - Server.Start: start the JSON-RPC loop
//   - Use ErrOutput for logs (does not contaminate the JSON channel)
//
// Tools: get_datetime, greet
// Protocol: StdIO (JSON-RPC via stdin/stdout)
//
// To test: compile and run directly, or point the
//              Client (04-Client-Basic) to this executable.
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
  uMakerAi.MCPServer.Core,
  uMakerAi.MCPServer.Stdio;

// =============================================================================
//  Tool: get_datetime
//  Returns the current date and time
// =============================================================================
type
  TDateTimeParams = class
  private
    FFormat: String;
  public
    [AiMCPSchemaDescription('Desired format: "iso" (default) or "readable"')]
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
  FDescription := 'Returns the current server date and time. ' +
                  'Format "iso" returns ISO-8601; "readable" returns readable text.';
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
//  Returns a personalized greeting
// =============================================================================
type
  TGreetParams = class
  private
    FName    : String;
    FLanguage: String;
  public
    [AiMCPSchemaDescription('Name of the person to greet')]
    property Name: String read FName write FName;
    [AiMCPSchemaDescription('Greeting language: "es" Spanish (default), "en" English')]
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
  FDescription := 'Generates a personalized greeting. ' +
                  'Supports languages: "es" (Spanish) and "en" (English).';
end;

function TGreetMCPTool.ExecuteWithParams(const AParams: TGreetParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  NombrePersona, Lang, Saludo: String;
begin
  NombrePersona := Trim(AParams.Name);
  if NombrePersona = '' then NombrePersona := 'world';
  Lang := Trim(LowerCase(AParams.Language));

  if Lang = 'en' then
    Saludo := Format('Hello, %s! Welcome to MakerAI MCP Server.', [NombrePersona])
  else
    Saludo := Format('Hello, %s! Welcome to the MakerAI MCP server.', [NombrePersona]);

  Result := TAiMCPResponseBuilder.New.AddText(Saludo).Build;
end;

// =============================================================================
//  MAIN
// =============================================================================
var
  Server: TAiMCPStdioServer;

begin
  try
    Server := TAiMCPStdioServer.Create(nil);
    try
      Server.ServerName := 'MakerAI-Demo-StdIO';

      // Register tools via factory
      Server.RegisterTool('get_datetime',
        function: IAiMCPTool begin Result := TDateTimeMCPTool.Create; end);

      Server.RegisterTool('greet',
        function: IAiMCPTool begin Result := TGreetMCPTool.Create; end);

      // Start the JSON-RPC loop (blocking)
      Server.Start;

      // Logs go to ErrOutput so they do not contaminate the JSON channel in StdIO
      WriteLn(ErrOutput, '[MCPServerStdIO] Server started. Waiting for JSON-RPC commands...');
      WriteLn(ErrOutput, '[MCPServerStdIO] Tools: get_datetime, greet');

      // Keep the process alive
      while True do
        Sleep(1000);

    finally
      Server.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[MCPServerStdIO] Fatal error: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
