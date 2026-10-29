program McpFileServerSSE;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core, uMakerAi.MCPServer.Bridge, uMakerAi.MCPServer.SSE,

  uTool.Sandbox in 'uTool.Sandbox.pas';

// Your file tools

var
  MCPServer: TAiMCPSSEHttpServer;

begin
  try
    // --- 1. Create SSE Server Instance ---
    MCPServer := TAiMCPSSEHttpServer.Create(nil);
    try
      // --- 2. Configuration ---
      MCPServer.Port := 8080; // TCP Port
      MCPServer.CorsEnabled := True; // Required for Claude Desktop
      MCPServer.CorsAllowedOrigins := '*';
      MCPServer.ServerName := 'Delphi-MCP-SSE-Files';

      // Optional route configuration (these are the defaults)
      // MCPServer.SseEndpoint := '/sse';
      // MCPServer.MessagesEndpoint := '/messages';

      // --- 3. Register Tools ---
      WriteLn('Registering file tools...');
      uTool.Sandbox.RegisterSandboxTools(MCPServer);

      // --- 4. Start Server ---
      MCPServer.Start;

      WriteLn('');
      WriteLn('===========================================================');
      WriteLn('✅ MCP SSE SERVER ACTIVE');
      WriteLn(Format('   Port: %d', [MCPServer.Port]));
      WriteLn(Format('   Folder: %s', [uTool.Sandbox.SANDBOX_ROOT]));
      WriteLn('===========================================================');
      WriteLn('');
      WriteLn('--- CONFIGURATION FOR CLAUDE DESKTOP ---');
      WriteLn('Copy and paste this into your "claude_desktop_config.json":');
      WriteLn('');
      WriteLn('{');
      WriteLn('  "mcpServers": {');
      WriteLn('    "delphi-sse-files": {');
      WriteLn('      "command": "ruta\\al\\ejecutable\\McpFileServerSSE.exe",');
      WriteLn('      "args": []');
      WriteLn('    }');
      WriteLn('  }');
      WriteLn('}');
      WriteLn('');
      WriteLn('NOTE: Claude Desktop will launch this executable automatically.');
      WriteLn('If you want to test it manually via HTTP, the SSE endpoint is:');
      WriteLn('http://localhost:8080/sse');
      WriteLn('');
      WriteLn('Press Enter to stop the server...');

      // Keep alive until the user decides to exit
      ReadLn;

    except
      on E: Exception do
        WriteLn('Error Fatal al iniciar: ' + E.Message);
    end;
  finally
    // Cleanup
    if Assigned(MCPServer) then
    begin
      MCPServer.Stop;
      MCPServer.Free;
    end;
  end;

end.
