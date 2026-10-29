program MCPClientTest;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - Demo 067: Test client for FileSystemMCP (Demo 037)
// =============================================================================
// Connects via StdIO to MCP server compiled in Demo 037,
// lists available tools and runs them:
//   - ReadDirectory: lists directory contents
//   - CreateDirectory: creates a new directory
//
// Make sure the server is compiled:
//   C:\mcp\servers\FileSystemMCP.exe
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  uMakerAi.MCPClient.Core,
  uMakerAi.Core;

const
  MCP_SERVER_EXE = 'C:\mcp\servers\FileSystemMCP.exe';
  TEST_LIST_DIR  = 'C:\';
  TEST_NEW_DIR   = 'C:\mcp\test_demo067';

// -----------------------------------------------------------------------------
// Presentation helpers
// -----------------------------------------------------------------------------

procedure PrintSep(const Title: string = '');
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

procedure PrintJSON(const Label_: string; AJson: TJSONObject);
begin
  if Assigned(AJson) then
    Writeln(Label_, ': ', AJson.Format(2))
  else
    Writeln(Label_, ': <nil>');
end;

// -----------------------------------------------------------------------------
// Extract text from MCP response (array "content" -> type:text -> text)
// -----------------------------------------------------------------------------
function ExtractTextFromMCPResult(AResult: TJSONObject): string;
var
  ContentArr: TJSONArray;
  Item: TJSONValue;
  ItemObj: TJSONObject;
  ItemType, ItemText: string;
begin
  Result := '';
  if not Assigned(AResult) then Exit;

  if AResult.TryGetValue<TJSONArray>('content', ContentArr) then
  begin
    for Item in ContentArr do
    begin
      if Item is TJSONObject then
      begin
        ItemObj := TJSONObject(Item);
        ItemObj.TryGetValue<string>('type', ItemType);
        if ItemType = 'text' then
        begin
          ItemObj.TryGetValue<string>('text', ItemText);
          if Result <> '' then Result := Result + #10;
          Result := Result + ItemText;
        end;
      end;
    end;
  end;
end;

// -----------------------------------------------------------------------------
// Main test
// -----------------------------------------------------------------------------
procedure RunTest;
var
  Client   : TMCPClientStdIo;
  MediaList: TObjectList<TAiMediaFile>;
  ToolsJson: TJSONObject;
  ToolsArr : TJSONArray;
  Tool     : TJSONValue;
  ToolName, ToolDesc: string;
  Args     : TJSONObject;
  Result_  : TJSONObject;
  Output   : string;
begin
  PrintSep('Demo 067 - MCP Client Test (FileSystemMCP)');
  Writeln('Servidor: ', MCP_SERVER_EXE);
  Writeln;

  Client    := TMCPClientStdIo.Create(nil);
  MediaList := TObjectList<TAiMediaFile>.Create(True);
  try
    // ── 1. Configure StdIO connection ──────────────────────────────────────
    Client.Params.Values['Command'] := MCP_SERVER_EXE;
    Client.Params.Values['Timeout'] := '10000';

    // ── 2. Initialize (MCP handshake) ───────────────────────────────────────
    PrintSep('STEP 1: Initialize');
    if not Client.Initialize then
    begin
      Writeln('ERROR: Could not initialize MCP server.');
      Writeln('  Verify it exists: ', MCP_SERVER_EXE);
      Exit;
    end;
    Writeln('Inicializacion OK.');

    // ── 3. List tools ───────────────────────────────────────────────
    PrintSep('STEP 2: tools/list');
    ToolsJson := Client.ListTools;
    try
      if not Assigned(ToolsJson) then
      begin
        Writeln('ERROR: ListTools returned nil.');
        Exit;
      end;

      if ToolsJson.TryGetValue<TJSONArray>('tools', ToolsArr) then
      begin
        Writeln(Format('Tools found: %d', [ToolsArr.Count]));
        PrintSep;
        for Tool in ToolsArr do
        begin
          if Tool is TJSONObject then
          begin
            TJSONObject(Tool).TryGetValue<string>('name',        ToolName);
            TJSONObject(Tool).TryGetValue<string>('description', ToolDesc);
            Writeln(Format('  [%s]  %s', [ToolName, ToolDesc]));
          end;
        end;
      end
      else
        Writeln('Response: ', ToolsJson.Format(2));
    finally
      ToolsJson.Free;
    end;

    // ── 4. Call ReadDirectory ──────────────────────────────────────────────
    PrintSep(Format('STEP 3: ReadDirectory("%s")', [TEST_LIST_DIR]));
    Args := TJSONObject.Create;
    try
      Args.AddPair('DirectoryPath', TEST_LIST_DIR);
      Result_ := Client.CallTool('ReadDirectory', Args, MediaList);
    finally
      Args.Free;
    end;
    try
      Output := ExtractTextFromMCPResult(Result_);
      if Output <> '' then
        Writeln(Output)
      else if Assigned(Result_) then
        Writeln(Result_.Format(2))
      else
        Writeln('ERROR: resultado nil');
    finally
      Result_.Free;
    end;

    // ── 5. Call CreateDirectory ────────────────────────────────────────────
    PrintSep(Format('STEP 4: CreateDirectory("%s")', [TEST_NEW_DIR]));
    Args := TJSONObject.Create;
    try
      Args.AddPair('DirectoryPath', TEST_NEW_DIR);
      Result_ := Client.CallTool('CreateDirectory', Args, MediaList);
    finally
      Args.Free;
    end;
    try
      Output := ExtractTextFromMCPResult(Result_);
      if Output <> '' then
        Writeln(Output)
      else if Assigned(Result_) then
        Writeln(Result_.Format(2))
      else
        Writeln('ERROR: resultado nil');
    finally
      Result_.Free;
    end;

    // ── 6. Verify directory was created ────────────────────────────
    PrintSep('STEP 5: Verification');
    if System.SysUtils.DirectoryExists(TEST_NEW_DIR) then
      Writeln('OK - Directory created successfully: ', TEST_NEW_DIR)
    else
      Writeln('AVISO - El directorio no existe (puede ser restriccion de permisos)');

    // ── 7. Disconnect ───────────────────────────────────────────────────────
    Client.Disconnect;
    Writeln;
    Writeln('Server disconnected.');

  finally
    MediaList.Free;
    Client.Free;
  end;
end;

// =============================================================================
begin
  try
    RunTest;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
