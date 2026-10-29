program MCPClientChat;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 05-Client-WithChat
// =============================================================================
// Integrates an MCP server with an LLM chat via TAiFunctions.
// The LLM can call MCP tools transparently.
//
// Concepts covered:
//   - TAiFunctions: collection of tools for the LLM
//   - TAiFunctions.MCPClients.Add: register an MCP server manually
//   - TMCPClientItem.TransportType := tpStdIo
//   - TMCPClientItem.Params.Values['Command']: path to the server
//   - TAiChatConnection: chat connection with tool support
//   - FAiConn.AiFunctions: link tools to the chat
//   - The LLM automatically calls MCP tools when needed
//
// Prerequisite: compile 01-Server-StdIO (Win64 Release).
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
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
  DRIVER     = 'Claude';
  MODEL      = 'claude-haiku-4-5-20251001';
  API_KEY    = '@CLAUDE_API_KEY';
  SERVER_EXE_REL = '..\01-Server-StdIO\Win64\Release\MCPServerStdIO.exe';

// =============================================================================
//  Demo
// =============================================================================
procedure RunDemo;
var
  Functions   : TAiFunctions;
  AiConn      : TAiChatConnection;
  ClientItem  : TMCPClientItem;
  ServerPath  : String;
  Pregunta    : String;
  Respuesta   : String;
begin
  Writeln('=== MCPClientChat ===');
  Writeln('LLM + MCP tools (get_datetime, greet)');
  Writeln;

  ServerPath := ExpandFileName(ExtractFilePath(ParamStr(0)) + SERVER_EXE_REL);
  Writeln('MCP server: ', ServerPath);
  Writeln;

  Functions := TAiFunctions.Create(nil);
  AiConn    := TAiChatConnection.Create(nil);
  try
    // Registrar el servidor MCP StdIO manualmente en TAiFunctions
    if TFile.Exists(ServerPath) then
    begin
      ClientItem := Functions.MCPClients.Add;
      ClientItem.Name                    := 'makerai-demo';
      ClientItem.TransportType           := tpStdIo;
      ClientItem.Params.Values['Command'] := ServerPath;

      // Inicializar el proceso del servidor
      if not ClientItem.MCPClient.Initialized then
        ClientItem.MCPClient.Initialize;

      if ClientItem.MCPClient.Available then
        Writeln('MCP server connected and available.')
      else
        Writeln('WARNING: MCP server not available. Check that the exe exists.');
    end
    else
    begin
      Writeln('WARNING: Server not found. Continuing without MCP tools.');
      Writeln('Compile 01-Server-StdIO (Win64 Release) first.');
    end;
    Writeln;

    // Configurar TAiChatConnection con las funciones MCP
    AiConn.AiFunctions              := Functions;
    AiConn.DriverName               := DRIVER;
    AiConn.Model                    := MODEL;
    AiConn.Params.Values['ApiKey']  := API_KEY;
    AiConn.RegisterUserParam(DRIVER, 'Tool_Active',     'True');
    AiConn.RegisterUserParam(DRIVER, 'Asynchronous',    'False');
    AiConn.RegisterUserParam(DRIVER, 'Max_Tokens',      '2048');
    AiConn.RegisterUserParam(DRIVER, 'ResponseTimeOut', '60000');

    AiConn.SystemPrompt.Text :=
      'Eres un asistente util. Tienes acceso a herramientas MCP: ' +
      'get_datetime (para saber la fecha y hora) y greet (para saludar). ' +
      'Usa las herramientas cuando sea apropiado. Responde en espanol.';

    // Ejecutar consultas que usan las herramientas MCP
    Writeln(StringOfChar('-', 60));
    Pregunta := 'Que fecha y hora es ahora?';
    Writeln('Pregunta: ', Pregunta);
    Respuesta := AiConn.AddMessageAndRun(Pregunta, 'user', []);
    Writeln('Respuesta: ', Respuesta);
    Writeln;

    Writeln(StringOfChar('-', 60));
    Pregunta := 'Saluda a "MakerAI" en espanol.';
    Writeln('Pregunta: ', Pregunta);
    Respuesta := AiConn.AddMessageAndRun(Pregunta, 'user', []);
    Writeln('Respuesta: ', Respuesta);
    Writeln;

    Writeln(StringOfChar('-', 60));
    Pregunta := 'Saluda a "Developer" en ingles y dime tambien la hora actual en formato ISO.';
    Writeln('Pregunta: ', Pregunta);
    Respuesta := AiConn.AddMessageAndRun(Pregunta, 'user', []);
    Writeln('Respuesta: ', Respuesta);
    Writeln;

  finally
    AiConn.Free;
    Functions.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
