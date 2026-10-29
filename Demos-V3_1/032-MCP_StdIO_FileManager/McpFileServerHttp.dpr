program McpFileServerHttp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core, uMakerAi.MCPServer.Http,

  uTool.Sandbox in 'uTool.Sandbox.pas',
  uTool.WorldTime in 'uTool.WorldTime.pas';

var
  MCPServer: TAiMCPHttpServer; // Cambiamos Stdio por Http

begin
  try
    // 1. Instantiate the HTTP server
    MCPServer := TAiMCPHttpServer.Create(nil);
    try
      // 2. Configuration
      MCPServer.Port := 8080; // Port where it will listen
      MCPServer.CorsEnabled := True; // Allow access from browsers
      MCPServer.CorsAllowedOrigins := '*';
      MCPServer.ServerName := 'Delphi-MCP-Http-Files';

      // 3. Register the tools (Exactly the same as before)
      WriteLn('Registering file tools...');
      uTool.Sandbox.RegisterSandboxTools(MCPServer);
      uTool.WorldTime.RegisterWorldTimeTool(MCPServer);

      // 4. Start
      MCPServer.Start;

      WriteLn('');
      WriteLn('==================================================');
      WriteLn(Format('✅ HTTP Server Listening on port %d', [MCPServer.Port]));
      WriteLn(Format('📂 Controlled folder: %s', [uTool.Sandbox.SANDBOX_ROOT]));
      WriteLn('==================================================');
      WriteLn('Available endpoints:');
      WriteLn('  GET  http://localhost:8080/mcp  -> Server info');
      WriteLn('  POST http://localhost:8080/mcp  -> Send JSON-RPC commands');
      WriteLn('==================================================');
      WriteLn('Press Enter to exit...');

      ReadLn; // Esperar a que el usuario presione Enter para cerrar

    except
      on E: Exception do
        WriteLn('Fatal Error: ' + E.Message);
    end;
  finally
    MCPServer.Stop;
    MCPServer.Free;
  end;
end.
