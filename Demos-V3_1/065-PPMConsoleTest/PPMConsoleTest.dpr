// MIT License
// MakerAI - Demo 065: PPM Console Test
// Isolated test of PPM flow: search → download → extract → initialize
// Run from console: PPMConsoleTest.exe

program PPMConsoleTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  System.Net.HttpClient, System.Net.URLClient,
  System.JSON, System.Math, System.Generics.Collections,
  uMakerAi.Core,
  uMakerAi.Tools.Functions,
  uMakerAi.MCPClient.Core,
  uMakerAi.Chat.Initializations;

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------
procedure Log(const S: string); begin Writeln(S); end;
procedure Sep; begin Writeln(StringOfChar('-', 60)); end;
procedure OK(const S: string); begin Writeln('[OK]  ' + S); end;
procedure ERR(const S: string); begin Writeln('[ERR] ' + S); end;
procedure INFO(const S: string); begin Writeln('[..] ' + S); end;

// ---------------------------------------------------------------------------
// Test 1: Verify connectivity with registry
// ---------------------------------------------------------------------------
procedure TestHealth;
var
  LClient: THTTPClient;
  LResp: IHTTPResponse;
begin
  Sep;
  Log('TEST 1 — Registry health check');
  LClient := THTTPClient.Create;
  try
    try
      LResp := LClient.Get('https://registry.cimamaker.com/v1/health');
      if LResp.StatusCode = 200 then
        OK('Registry accessible. Response: ' + LResp.ContentAsString(TEncoding.UTF8))
      else
        ERR('Status: ' + IntToStr(LResp.StatusCode));
    except
      on E: Exception do
        ERR('Excepcion: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LClient.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Test 2: Search MCP tools
// ---------------------------------------------------------------------------
procedure TestSearch(const AQuery: string);
var
  LFunctions: TAiFunctions;
  LResult: TJSONObject;
  LTools: TJSONArray;
  I: Integer;
begin
  Sep;
  Log('TEST 2 — SearchPPMMCP("' + AQuery + '")');
  LFunctions := TAiFunctions.Create(nil);
  try
    // OnLog requiere 'of object' — se omite en console test
    try
      LResult := LFunctions.SearchPPMMCP(AQuery);
      if not Assigned(LResult) then
      begin
        ERR('SearchPPMMCP returned nil');
        Exit;
      end;
      try
        Log('JSON received (first 300 chars): ' +
            Copy(LResult.ToJSON, 1, 300));

        if LResult.TryGetValue<TJSONArray>('tools', LTools) then
        begin
          OK(Format('Found %d tools', [LTools.Count]));
          for I := 0 to Min(LTools.Count - 1, 4) do
          begin
            var LTool := LTools.Items[I] as TJSONObject;
            var LName, LDesc: string;
            LTool.TryGetValue<string>('name', LName);
            LTool.TryGetValue<string>('description', LDesc);
            Log(Format('  [%d] %s — %s', [I, LName, Copy(LDesc, 1, 60)]));
          end;
        end
        else
          ERR('Field "tools" not found in response');
      finally
        LResult.Free;
      end;
    except
      on E: Exception do
        ERR('Excepcion en SearchPPMMCP: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LFunctions.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Test 3: Resolve package version
// ---------------------------------------------------------------------------
procedure TestResolveVersion(const AName: string);
var
  LClient: THTTPClient;
  LResp: IHTTPResponse;
  LJson, LPackage, LVer: TJSONObject;
  LVersions: TJSONArray;
  LBody, LVersion: string;
begin
  Sep;
  Log('TEST 3 — Resolve version of "' + AName + '"');
  LClient := THTTPClient.Create;
  try
    try
      LResp := LClient.Get('https://registry.cimamaker.com/v1/packages/' + AName);
      Log('Status: ' + IntToStr(LResp.StatusCode));
      LBody := LResp.ContentAsString(TEncoding.UTF8);
      Log('Body (first 400): ' + Copy(LBody, 1, 400));

      if LResp.StatusCode = 200 then
      begin
        LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
        if Assigned(LJson) then
        try
          if LJson.TryGetValue<TJSONObject>('package', LPackage) and
             LPackage.TryGetValue<TJSONArray>('versions', LVersions) and
             (LVersions.Count > 0) then
          begin
            LVer := LVersions.Items[0] as TJSONObject;
            LVer.TryGetValue<string>('version', LVersion);
            OK('Version resolved: ' + LVersion);
          end
          else
            ERR('Unexpected JSON structure');
        finally
          LJson.Free;
        end
        else
          ERR('Could not parse JSON');
      end;
    except
      on E: Exception do
        ERR('Excepcion: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LClient.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Test 4: Download .paipkg and list its contents
// ---------------------------------------------------------------------------
procedure TestDownloadAndInspect(const AName: string);
var
  LClient: THTTPClient;
  LStream: TFileStream;
  LResp: IHTTPResponse;
  LUrl, LTempFile: string;
  LZip: TZipFile;
  I: Integer;
begin
  Sep;
  Log('TEST 4 — Download + inspect "' + AName + '"');

  // First resolve version manually for test
  LUrl := Format('https://registry.cimamaker.com/v1/packages/%s/latest/download', [AName]);
  // Try with "latest" as alias
  LTempFile := TPath.Combine(TPath.GetTempPath, AName + '-test.paipkg');

  INFO('Downloading from: ' + LUrl);
  LClient := THTTPClient.Create;
  try
    try
      LStream := TFileStream.Create(LTempFile, fmCreate);
      try
        LResp := LClient.Get(LUrl, LStream);
        Log('Status descarga: ' + IntToStr(LResp.StatusCode) +
            ' | Bytes: ' + IntToStr(LStream.Size));
      finally
        LStream.Free;
      end;

      if (LResp.StatusCode = 200) and TFile.Exists(LTempFile) and
         (TFile.GetSize(LTempFile) > 0) then
      begin
        OK('File downloaded: ' + LTempFile);
        // Inspect ZIP
        LZip := TZipFile.Create;
        try
          try
            LZip.Open(LTempFile, zmRead);
            Log('Entries in ZIP:');
            for I := 0 to LZip.FileCount - 1 do
              Log('  ' + LZip.FileName[I]);
            LZip.Close;
          except
            on E: Exception do
              ERR('Error opening ZIP: ' + E.ClassName + ' — ' + E.Message);
          end;
        finally
          LZip.Free;
        end;
      end
      else
        ERR('Download failed or empty file');
    except
      on E: Exception do
        ERR('Exception during download: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LClient.Free;
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
  end;
end;

// ---------------------------------------------------------------------------
// Test 5: Complete InstallMCPFromPPM
// ---------------------------------------------------------------------------
procedure TestInstall(const AName: string);
var
  LFunctions: TAiFunctions;
  LItem: TMCPClientItem;
begin
  Sep;
  Log('TEST 5 — InstallMCPFromPPM("' + AName + '")');
  LFunctions := TAiFunctions.Create(nil);
  try
    // OnLog requiere 'of object' — se omite en console test
    try
      LItem := LFunctions.InstallMCPFromPPM(AName);
      if Assigned(LItem) then
      begin
        OK('Installed. Exe: ' + LItem.Params.Values['Command']);
        INFO('Initializing MCP client...');
        try
          if LItem.MCPClient.Initialize then
            OK('Client initialized. Tools available via MCP.')
          else
            ERR('Could not initialize MCP client');
        except
          on E: Exception do
            ERR('Exception in Initialize: ' + E.ClassName + ' — ' + E.Message);
        end;
      end
      else
        ERR('InstallMCPFromPPM returned nil');
    except
      on E: Exception do
        ERR('Exception in InstallMCPFromPPM: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LFunctions.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Test 6: Direct CallTool (reproduces "Invalid pointer operation")
// ---------------------------------------------------------------------------
procedure TestCallTool(const AName, AToolName: string);
var
  LFunctions: TAiFunctions;
  LItem: TMCPClientItem;
  LArgs: TJSONObject;
  LMedia: TObjectList<TAiMediaFile>;
  LResult: TJSONObject;
begin
  Sep;
  Log('TEST 6 — CallTool directo: ' + AName + ' -> ' + AToolName);
  LFunctions := TAiFunctions.Create(nil);
  try
    try
      // Install (or retrieve if already exists)
      LItem := LFunctions.InstallMCPFromPPM(AName);
      if not Assigned(LItem) then
      begin
        ERR('Could not get client for: ' + AName);
        Exit;
      end;
      OK('Client ready. Exe: ' + LItem.Params.Values['Command']);

      // Initialize (gets tool list and marks Available=True)
      INFO('Calling Initialize...');
      if not LItem.MCPClient.Initialize then
      begin
        ERR('Initialize returned False — client not available');
        Exit;
      end;
      OK('Initialize OK. Available=' + BoolToStr(LItem.MCPClient.Available, True));

      // Call tool directly
      // mcp-postgres: tool = 'postgres', args = {connection:{...}, operation:'tables'}
      INFO('Calling CallTool("' + AToolName + '")...');
      LMedia := TObjectList<TAiMediaFile>.Create(True);
      LArgs  := TJSONObject.Create;
      var LConn := TJSONObject.Create;
      LConn.AddPair('host',     'localhost');
      LConn.AddPair('port',     TJSONNumber.Create(5432));
      LConn.AddPair('database', 'postgres');
      LConn.AddPair('user',     'postgres');
      LConn.AddPair('password', 'masterkey');
      LArgs.AddPair('connection', LConn);
      LArgs.AddPair('operation',  'tables');
      try
        LResult := LItem.MCPClient.CallTool(AToolName, LArgs, LMedia);
        // NOTE: LArgs ownership passes to CallTool — do not call LArgs.Free
        if Assigned(LResult) then
        begin
          OK('CallTool exitoso. Respuesta (primeros 200 chars): ' +
             Copy(LResult.ToJSON, 1, 200));
          LResult.Free;
        end
        else
          ERR('CallTool returned nil (timeout or server error)');
      except
        on E: Exception do
          ERR('EXCEPTION in CallTool: ' + E.ClassName + ' — ' + E.Message);
      end;
      LMedia.Free;

    except
      on E: Exception do
        ERR('EXCEPTION in TestCallTool: ' + E.ClassName + ' — ' + E.Message);
    end;
  finally
    LFunctions.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    Writeln('=== PPM Console Test ===');
    Writeln('Registry: https://registry.cimamaker.com');
    Writeln;

    TestHealth;
    TestSearch('postgres');
    TestResolveVersion('mcp-postgres');
    TestDownloadAndInspect('mcp-postgres');
    TestInstall('mcp-postgres');
    TestCallTool('mcp-postgres', 'postgres');

    Sep;
    Writeln('=== FIN ===');
  except
    on E: Exception do
    begin
      ERR('FATAL EXCEPTION: ' + E.ClassName + ' — ' + E.Message);
    end;
  end;

  Writeln;
  Write('Press Enter to exit...');
  Readln;
end.
