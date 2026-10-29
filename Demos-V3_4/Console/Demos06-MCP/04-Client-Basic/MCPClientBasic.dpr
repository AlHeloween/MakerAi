program MCPClientBasic;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 06-MCP / 04-Client-Basic
// =============================================================================
// Basic MCP client that connects via StdIO to the server compiled in
// 01-Server-StdIO and runs its tools directly.
//
// Concepts it covers:
//   - TMCPClientStdIo: MCP client for connection via stdin/stdout
//   - Client.Params.Values['Command']: path to the server executable
//   - Client.Initialize: MCP handshake (startup protocol)
//   - Client.ListTools: list server tools
//   - Client.CallTool(name, args, mediaList): call a tool
//   - Parse the MCP response (array "content" -> type:text -> text)
//
// Prerequisite: compile 01-Server-StdIO first.
//   The executable must be at: Win64\Release\MCPServerStdIO.exe
//   relative to the demo's parent directory.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  uMakerAi.MCPClient.Core,
  uMakerAi.Core;

const
  // Path to the compiled server (01-Server-StdIO), relative to the executable
  SERVER_EXE_REL = '..\01-Server-StdIO\Win64\Release\MCPServerStdIO.exe';

// =============================================================================
//  Helpers
// =============================================================================
procedure Sep(const Title: String = '');
begin
  if Title = '' then
    Writeln(StringOfChar('-', 60))
  else
  begin
    Writeln;
    Writeln(StringOfChar('=', 60));
    Writeln('  ', Title);
    Writeln(StringOfChar('=', 60));
  end;
end;

// Extracts the text from the MCP response (content array -> type:text -> text)
function ExtraerTexto(AResult: TJSONObject): String;
var
  ContentArr: TJSONArray;
  Item      : TJSONValue;
  ItemObj   : TJSONObject;
  ItemType, ItemText: String;
begin
  Result := '';
  if not Assigned(AResult) then Exit;
  if AResult.TryGetValue<TJSONArray>('content', ContentArr) then
    for Item in ContentArr do
      if Item is TJSONObject then
      begin
        ItemObj := TJSONObject(Item);
        ItemObj.TryGetValue<String>('type', ItemType);
        if ItemType = 'text' then
        begin
          ItemObj.TryGetValue<String>('text', ItemText);
          if Result <> '' then Result := Result + #10;
          Result := Result + ItemText;
        end;
      end;
end;

// =============================================================================
//  Main test
// =============================================================================
procedure RunTest;
var
  Client    : TMCPClientStdIo;
  MediaList : TObjectList<TAiMediaFile>;
  ToolsJson : TJSONObject;
  ToolsArr  : TJSONArray;
  Tool      : TJSONValue;
  ToolName, ToolDesc: String;
  Args      : TJSONObject;
  Resp      : TJSONObject;
  ServerPath: String;
begin
  Sep('Demo 04 - MCPClientBasic');

  // Resolve the server path relative to the current executable
  ServerPath := ExpandFileName(ExtractFilePath(ParamStr(0)) + SERVER_EXE_REL);
  Writeln('Server: ', ServerPath);
  Writeln;

  if not TFile.Exists(ServerPath) then
  begin
    Writeln('WARNING: Server not found at: ', ServerPath);
    Writeln('Compile 01-Server-StdIO first (Win64 Release).');
    Writeln;
    Writeln('Continuing demo with step descriptions...');
    Writeln;
    Sep('STEP 1: Initialize StdIO connection');
    Writeln('  Client.Params.Values[''Command''] := ServerPath');
    Writeln('  Client.Initialize  // handshake MCP');
    Sep('STEP 2: List tools');
    Writeln('  ToolsJson := Client.ListTools');
    Sep('STEP 3: Call tool get_datetime');
    Writeln('  Args := TJSONObject.Create;');
    Writeln('  Args.AddPair(''format'', ''readable'');');
    Writeln('  Resp := Client.CallTool(''get_datetime'', Args, MediaList)');
    Sep('STEP 4: Call tool greet');
    Writeln('  Args.AddPair(''name'', ''MakerAI'');');
    Writeln('  Args.AddPair(''language'', ''es'');');
    Writeln('  Resp := Client.CallTool(''greet'', Args, MediaList)');
    Exit;
  end;

  Client    := TMCPClientStdIo.Create(nil);
  MediaList := TObjectList<TAiMediaFile>.Create(True);
  try
    // Step 1: Configure and connect
    Client.Params.Values['Command'] := ServerPath;
    Client.Params.Values['Timeout'] := '10000';

    Sep('STEP 1: Initialize (MCP handshake)');
    if not Client.Initialize then
    begin
      Writeln('ERROR: Could not initialize the MCP server.');
      Exit;
    end;
    Writeln('Initialization OK.');

    // Step 2: List available tools
    Sep('STEP 2: ListTools');
    ToolsJson := Client.ListTools;
    try
      if Assigned(ToolsJson) then
      begin
        if ToolsJson.TryGetValue<TJSONArray>('tools', ToolsArr) then
        begin
          Writeln(Format('Tools found: %d', [ToolsArr.Count]));
          for Tool in ToolsArr do
            if Tool is TJSONObject then
            begin
              TJSONObject(Tool).TryGetValue<String>('name',        ToolName);
              TJSONObject(Tool).TryGetValue<String>('description', ToolDesc);
              Writeln(Format('  [%s] %s', [ToolName, ToolDesc]));
            end;
        end;
      end;
    finally
      ToolsJson.Free;
    end;

    // Step 3: Call get_datetime
    Sep('STEP 3: CallTool — get_datetime');
    Args := TJSONObject.Create;
    try
      Args.AddPair('format', 'readable');
      Resp := Client.CallTool('get_datetime', Args, MediaList);
      try
        if Assigned(Resp) then
          Writeln('Result: ', ExtraerTexto(Resp))
        else
          Writeln('ERROR: CallTool returned nil');
      finally
        Resp.Free;
      end;
    finally
      Args.Free;
    end;

    // Step 4: Call greet
    Sep('STEP 4: CallTool — greet');
    Args := TJSONObject.Create;
    try
      Args.AddPair('name',     'MakerAI Developer');
      Args.AddPair('language', 'es');
      Resp := Client.CallTool('greet', Args, MediaList);
      try
        if Assigned(Resp) then
          Writeln('Result: ', ExtraerTexto(Resp))
        else
          Writeln('ERROR: CallTool returned nil');
      finally
        Resp.Free;
      end;
    finally
      Args.Free;
    end;

    Sep('Demo completed OK');

  finally
    MediaList.Free;
    Client.Free;
  end;
end;

begin
  try
    RunTest;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
