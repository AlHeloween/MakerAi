program MCPServerRAG;

(*
  Demo 037-MCPServerRAG

  MCP server (SSE protocol by default) that exposes a real RAG system
  backed by SQL Server 2025 (TAiRAGVector + TAiRAGVectorMSSQLDriver +
  TAiOpenAiEmbeddings).

  Configuration: MCPServerRAG.ini next to the executable (created with defaults
  on first run). See sections [Server], [Database], [Embeddings],
  [Search].

  Authentication: hardcoded login/password in uTool.RAG (RAG_LOGIN/RAG_PASSWORD).
  The client must send one of:
    Authorization: Basic base64(user:password)
    Authorization: Bearer user:password
    X-API-Key: user:password

  Usage:
    MCPServerRAG.exe [--config <path.ini>] [--protocol sse|http|stdio] [--port N]
  (command-line parameters take priority over the .ini)
*)

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  uTool.RAG in 'uTool.RAG.pas';

var
  MCPServer: TAiMCPServer;
  Cfg: TRagServerConfig;
  IniPath, CliProtocol: string;
  CliPort, i: Integer;

begin
  IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'MCPServerRAG.ini');
  CliProtocol := '';
  CliPort := 0;

  i := 1;
  while i <= ParamCount do
  begin
    if SameText(ParamStr(i), '--config') and (i < ParamCount) then
    begin
      Inc(i);
      IniPath := ParamStr(i);
    end
    else if SameText(ParamStr(i), '--protocol') and (i < ParamCount) then
    begin
      Inc(i);
      CliProtocol := LowerCase(ParamStr(i));
    end
    else if SameText(ParamStr(i), '--port') and (i < ParamCount) then
    begin
      Inc(i);
      CliPort := StrToIntDef(ParamStr(i), 0);
    end;
    Inc(i);
  end;

  try
    Cfg := LoadServerConfig(IniPath);
    if CliProtocol <> '' then
      Cfg.Protocol := CliProtocol;
    if CliPort > 0 then
      Cfg.Port := CliPort;

    InitRagEngine(Cfg);
    try
      if SameText(Cfg.Protocol, 'sse') then
        MCPServer := TAiMCPSSEHttpServer.Create(nil)
      else if SameText(Cfg.Protocol, 'http') then
        MCPServer := TAiMCPHttpServer.Create(nil)
      else
        MCPServer := TAiMCPStdioServer.Create(nil);

      try
        MCPServer.ServerName := 'mcp-rag-vector';
        MCPServer.Port := Cfg.Port;
        MCPServer.CorsEnabled := True;
        MCPServer.CorsAllowedOrigins := '*';

        uTool.RAG.RegisterTools(MCPServer); // registers the tool and hooks authentication

        MCPServer.Start;
        WriteLn(ErrOutput, Format('[mcp-rag-vector] ready. protocol=%s port=%d config=%s',
          [Cfg.Protocol, Cfg.Port, IniPath]));

        while True do
          Sleep(1000);
      finally
        MCPServer.Free;
      end;
    finally
      DoneRagEngine;
    end;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-rag-vector] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;
end.
