unit uMCPServerAiFunctionsDm;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils,

  uMakerAi.Core,
  uMakerAi.Tools.Functions,
  uMakerAi.MCPServer.Core,
  uMakerAi.MCPServer.Stdio,
  uMakerAi.Chat.Messages,
  uMakerAi.MCPServer.Bridge, UMakerAi.MCPServer.Http;

type
  TMCPServerAiFunctionsDm = class(TDataModule)
    AiFunctions1: TAiFunctions;
    AiMCPServer1: TAiMCPStdioServer;
    AiMCPHttpServer1: TAiMCPHttpServer;
    procedure AiFunctions1Functions0GetFechaHoraAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure DataModuleCreate(Sender: TObject);
  private
    procedure SetupAiFunctions;
  public
    procedure StartServer;
  end;

var
  MCPServerAiFunctionsDm: TMCPServerAiFunctionsDm;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}

procedure TMCPServerAiFunctionsDm.AiFunctions1Functions0GetFechaHoraAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  ToolCall.Response := FormatDateTime('YYYY_MM_DD hh:nn:ss', Now);
  Handled := True;
end;


procedure TMCPServerAiFunctionsDm.StartServer;
var
  I: Integer;
  Func: TFunctionActionItem;
begin
  WriteLn(ErrOutput, '');
  WriteLn(ErrOutput, '=== MCP Server with TAiFunctions ===');

  // Start the desired server (change here to use StdIO instead)
  //AiMCPServer1.Start;
  AiMCPHttpServer1.Start;

  // Show information according to the active protocol
  if AiMCPHttpServer1.IsActive then
  begin
    WriteLn(ErrOutput, 'Protocol : HTTP');
    WriteLn(ErrOutput, 'Server  : ' + AiMCPHttpServer1.ServerName);
    WriteLn(ErrOutput, 'Port    : ' + IntToStr(AiMCPHttpServer1.Port));
    WriteLn(ErrOutput, 'Endpoint  : ' + AiMCPHttpServer1.Endpoint);
    WriteLn(ErrOutput, 'URL       : http://localhost:' + IntToStr(AiMCPHttpServer1.Port) + AiMCPHttpServer1.Endpoint);
    WriteLn(ErrOutput, 'CORS      : ' + IfThen(AiMCPHttpServer1.CorsEnabled,
      'Enabled (' + AiMCPHttpServer1.CorsAllowedOrigins + ')', 'Disabled'));
    WriteLn(ErrOutput, '');
    WriteLn(ErrOutput, 'Usage examples with curl:');
    WriteLn(ErrOutput, '  List tools:');
    WriteLn(ErrOutput, '    curl -X POST http://localhost:' + IntToStr(AiMCPHttpServer1.Port) +
      AiMCPHttpServer1.Endpoint + ' -H "Content-Type: application/json"' +
      ' -d "{""jsonrpc"":""2.0"",""method"":""tools/list"",""id"":1}"');
    WriteLn(ErrOutput, '  Call tool:');
    WriteLn(ErrOutput, '    curl -X POST http://localhost:' + IntToStr(AiMCPHttpServer1.Port) +
      AiMCPHttpServer1.Endpoint + ' -H "Content-Type: application/json"' +
      ' -d "{""jsonrpc"":""2.0"",""method"":""tools/call"",""params"":{""name"":""<tool>"",""arguments"":{}},""id"":2}"');
  end
  else if AiMCPServer1.IsActive then
  begin
    WriteLn(ErrOutput, 'Protocol : StdIO');
    WriteLn(ErrOutput, 'Server  : ' + AiMCPServer1.ServerName);
    WriteLn(ErrOutput, 'Usage       : Register this executable as a subprocess in the MCP client.');
    WriteLn(ErrOutput, '            The client writes to stdin and reads responses from stdout.');
    WriteLn(ErrOutput, '            Diagnostic messages (like this one) go to stderr.');
  end;

  // List the registered tools
  WriteLn(ErrOutput, '');
  WriteLn(ErrOutput, 'Registered tools (' + IntToStr(AiFunctions1.Functions.Count) + '):');
  for I := 0 to AiFunctions1.Functions.Count - 1 do
  begin
    Func := AiFunctions1.Functions[I];
    WriteLn(ErrOutput, '  [' + IntToStr(I + 1) + '] ' + Func.FunctionName +
      ' - ' + Func.Description.Text.Trim);
  end;

  WriteLn(ErrOutput, '');
  WriteLn(ErrOutput, '✅ Server started. Waiting for JSON-RPC requests...');
  WriteLn(ErrOutput, '');
end;


procedure TMCPServerAiFunctionsDm.DataModuleCreate(Sender: TObject);
begin
  SetupAiFunctions;
end;

procedure TMCPServerAiFunctionsDm.SetupAiFunctions;
begin
{

// This is another way to attach functions manually and not through the Delphi IDE
var
  Func: TFunctionActionItem;
  Param: TFunctionParamsItem;
begin
  AiFunctions1.Functions.Clear;

  // --- FUNCTION 1: System Information ---
  Func := AiFunctions1.Functions.Add;
  Func.FunctionName := 'get_system_info';
  Func.Description.Text := 'Returns basic information about the Delphi server.';
  Func.OnAction := OnGetSystemInfo;

  // --- FUNCTION 2: Write Note ---
  Func := AiFunctions1.Functions.Add;
  Func.FunctionName := 'write_note';
  Func.Description.Text := 'Saves a text note on the server.';
  Func.OnAction := OnWriteNote;

  // Parameter: Title
  Param := Func.Parameters.Add;
  Param.Name := 'title';
  Param.ParamType := ptString;
  Param.Description.Text := 'File title';
  Param.Required := True;

  // Parameter: Content
  Param := Func.Parameters.Add;
  Param.Name := 'content';
  Param.ParamType := ptString;
  Param.Description.Text := 'Note content';
  Param.Required := True;

}

end;


end.
