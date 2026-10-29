program McpFileServerStIO;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core in '..\Source\MCPServer\uMakerAi.MCPServer.Core.pas',
  uMakerAi.MCPServer.Stdio in '..\Source\MCPServer\uMakerAi.MCPServer.Stdio.pas',
  uTool.Sandbox in 'uTool.Sandbox.pas',
  uTool.WorldTime in 'uTool.WorldTime.pas';

var
  MCPServer: TAiMCPStdioServer;

begin
  try
    // 1. Create the server (Stdio mode for local integration)
    // Note: We use Stdio because it is the standard for local AI tools
    MCPServer := TAiMCPStdioServer.Create(nil);
    try
      // 2. Basic configuration
      MCPServer.ServerName := 'Delphi-FileManager-MCP';

      // 3. Register the Sandbox tools
      WriteLn(ErrOutput, 'Registering file tools...'); // ErrOutput to avoid polluting Stdin/Stdout
      uTool.Sandbox.RegisterSandboxTools(MCPServer);
      uTool.WorldTime.RegisterWorldTimeTool(MCPServer);

      // 4. Start server
      MCPServer.Start;
      WriteLn(ErrOutput, '✅ MCP File Server started.');
      WriteLn(ErrOutput, '📂 Controlled folder: ' + uTool.Sandbox.SANDBOX_ROOT);
      WriteLn(ErrOutput, 'Waiting for JSON-RPC commands via Stdin...');

      // 5. Infinite loop to keep the app alive
      while True do
        Sleep(1000);

    except
      on E: Exception do
        WriteLn(ErrOutput, 'Fatal error: ' + E.Message);
    end;
  finally
    MCPServer.Free;
  end;
end.
