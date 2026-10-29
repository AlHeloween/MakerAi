// MIT License
// MakerAI — Demo 066: AutoMCP Console Test (v2 — updated API)
//
// End-to-end test of AutoMCP system:
//   1. Installs mcp-postgres via PPM
//   2. Lists its tools
//   3. Verifies connectivity with local PostgreSQL
//   4. Interactive chat with LLM + active AutoMCP
//
// Environment variables:
//   DEMO_DRIVER  = Ollama (default)
//   DEMO_MODEL   = gpt-oss:20b (default)
//   DEMO_API_KEY = @OLLAMA_API_KEY (default)
//   DEMO_URL     = http://192.168.3.121:11434/ (default)
//   PG_CONN      = postgresql://postgres:masterkey@localhost:5432/postgres (default)

program AutoMCPConsoleTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils,
  System.IOUtils, System.Net.HttpClient, System.Generics.Collections,
  uMakerAi.Core,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Tools.Functions,
  uMakerAi.MCPClient.Core,
  uMakerAi.Chat.Initializations;

// ============================================================================
// Helpers
// ============================================================================
procedure Sep; begin Writeln(StringOfChar('-', 70)); end;
procedure OK(const S: string);   begin Writeln('  [OK]  ' + S); end;
procedure ERR(const S: string);  begin Writeln('  [ERR] ' + S); end;
procedure INFO(const S: string); begin Writeln('  [..]  ' + S); end;
procedure HDR(const S: string);
begin
  Writeln;
  Writeln('>>> ' + S);
  Sep;
end;

// ============================================================================
// Main test
// ============================================================================
type
  TPostgresAutoMCPTest = class
  private
    FFunctions: TAiFunctions;
    FAiConn   : TAiChatConnection;
    FLastError: string;
    FPGConn   : string;

    procedure OnLog(Sender: TObject; const Msg: string);
    procedure OnStatus(Sender: TObject; const Msg: string);
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);
    procedure OnState(Sender: TObject; State: TAiChatState; const Desc: string);

    procedure TestInstallPostgres;
    procedure TestListTools;
    procedure TestDirectQuery;
    procedure TestChatPostgres;
    procedure TestTTSGeminiSetup;
    procedure TestTTSGeminiDirect;
    procedure TestTTSGeminiChat;
    procedure InteractiveLoop;
  public
    constructor Create(const ADriver, AModel, AApiKey, AUrl, APGConn: string);
    destructor  Destroy; override;
    procedure   Run;
  end;

// ----------------------------------------------------------------------------
constructor TPostgresAutoMCPTest.Create(const ADriver, AModel, AApiKey, AUrl, APGConn: string);
begin
  inherited Create;
  FPGConn := APGConn;

  // TAiFunctions — AutoMCP active
  FFunctions := TAiFunctions.Create(nil);
  FFunctions.OnLog          := OnLog;
  FFunctions.OnStatusUpdate := OnStatus;
  FFunctions.AutoMCPConfig.Active      := True;
  FFunctions.AutoMCPConfig.RegistryUrl := 'https://registry.cimamaker.com';

  // TAiChatConnection
  FAiConn := TAiChatConnection.Create(nil);
  FAiConn.AiFunctions   := FFunctions;
  FAiConn.OnError       := OnError;
  FAiConn.OnStateChange := OnState;

  FAiConn.RegisterUserParam(ADriver, 'Tool_Active',   'True');
  FAiConn.RegisterUserParam(ADriver, 'Asynchronous',  'False');
  FAiConn.RegisterUserParam(ADriver, 'Max_Tokens',    '4096');
  FAiConn.RegisterUserParam(ADriver, 'ResponseTimeOut', '120000');

  FAiConn.DriverName              := ADriver;
  FAiConn.Model                   := AModel;
  FAiConn.Params.Values['ApiKey'] := AApiKey;
  if AUrl <> '' then
    FAiConn.Params.Values['Url']  := AUrl;

  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;
end;

destructor TPostgresAutoMCPTest.Destroy;
begin
  FAiConn.Free;
  FFunctions.Free;
  inherited;
end;

// --- Events ----------------------------------------------------------------
procedure TPostgresAutoMCPTest.OnLog(Sender: TObject; const Msg: string);
begin Writeln('  [MCP]  ' + Msg); end;

procedure TPostgresAutoMCPTest.OnStatus(Sender: TObject; const Msg: string);
begin Writeln('  [STS]  ' + Msg); end;

procedure TPostgresAutoMCPTest.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FLastError := ErrorMsg;
  Writeln('  [ERR]  ' + ErrorMsg);
end;

procedure TPostgresAutoMCPTest.OnState(Sender: TObject; State: TAiChatState;
  const Desc: string);
begin
  case State of
    acsToolCalling   : INFO('LLM → tool call...');
    acsToolExecuting : INFO('Ejecutando tool...');
  end;
end;

// ============================================================================
// TEST 1 — Install mcp-postgres via PPM
// ============================================================================
procedure TPostgresAutoMCPTest.TestInstallPostgres;
var
  LItem: TMCPClientItem;
begin
  HDR('TEST 1 — Install mcp-postgres from PPM');

  // Check if already present
  LItem := FFunctions.MCPClients.GetClientByName('mcp-postgres');
  if Assigned(LItem) then
  begin
    INFO('mcp-postgres already registered: ' + LItem.Params.Values['Command']);
    INFO('Available: ' + BoolToStr(LItem.MCPClient.Available, True));
    Exit;
  end;

  // Install
  INFO('Downloading and installing mcp-postgres...');
  LItem := FFunctions.InstallMCPFromPPM('mcp-postgres', '', '',
    'https://registry.cimamaker.com');

  if not Assigned(LItem) then
  begin
    ERR('InstallMCPFromPPM returned nil. Verify connectivity with PPM.');
    Exit;
  end;

  OK('Installed at: ' + LItem.Params.Values['Command']);

  // Initialize MCP process
  INFO('Initializing MCP process...');
  if not LItem.MCPClient.Initialized then
    LItem.MCPClient.Initialize;

  if LItem.MCPClient.Available then
    OK('MCP process active and available.')
  else
    ERR('The MCP process was NOT available after Initialize.');
end;

// ============================================================================
// TEST 2 — List tools of mcp-postgres server
// ============================================================================
procedure TPostgresAutoMCPTest.TestListTools;
var
  LItem: TMCPClientItem;
  LToolsJson: string;
  LRoot, LTool: TJSONObject;
  LArr: TJSONArray;
  LName, LDesc: string;
begin
  HDR('TEST 2 — List tools of mcp-postgres');

  LItem := FFunctions.MCPClients.GetClientByName('mcp-postgres');
  if not Assigned(LItem) then
  begin
    ERR('mcp-postgres is not registered. Run TEST 1 first.');
    Exit;
  end;

  if not LItem.MCPClient.Available then
  begin
    ERR('MCP process not available.');
    Exit;
  end;

  LToolsJson := LItem.MCPClient.Tools.Text;
  INFO('JSON tools raw (first 400 chars):');
  Writeln('  ' + Copy(LToolsJson, 1, 400));
  Writeln;

  LRoot := TJSONObject.ParseJSONValue(LToolsJson) as TJSONObject;
  if not Assigned(LRoot) then
  begin
    ERR('Tools JSON is not a valid object.');
    Exit;
  end;
  try
    if LRoot.TryGetValue<TJSONArray>('tools', LArr) then
    begin
      INFO(Format('%d tool(s) available:', [LArr.Count]));
      for var I := 0 to LArr.Count - 1 do
      begin
        LTool := LArr.Items[I] as TJSONObject;
        LName := '';
        LDesc := '';
        LTool.TryGetValue<string>('name', LName);
        LTool.TryGetValue<string>('description', LDesc);
        Writeln(Format('  [%d] %s — %s', [I, LName, Copy(LDesc, 1, 80)]));
      end;
    end
    else
      ERR('No "tools" field in server response.');
  finally
    LRoot.Free;
  end;
end;

// ============================================================================
// TEST 3 — Direct call to query function (without LLM)
// ============================================================================
procedure TPostgresAutoMCPTest.TestDirectQuery;
var
  LItem: TMCPClientItem;
  LArgs, LResult: TJSONObject;
  LMedia: TObjectList<TAiMediaFile>;
begin
  HDR('TEST 3 — Direct call: mcp-postgres → query "SELECT version()"');

  LItem := FFunctions.MCPClients.GetClientByName('mcp-postgres');
  if not Assigned(LItem) or not LItem.MCPClient.Available then
  begin
    ERR('mcp-postgres not available. Skipping TEST 3.');
    Exit;
  end;

  // mcp-postgres is a dispatcher with "operation" parameter
  // operations: query, execute, tables, schema, describe
  LArgs := TJSONObject.Create;
  LMedia := TObjectList<TAiMediaFile>.Create(True);
  try
    // mcp-postgres expects individual parameters, not connectionString
    LArgs.AddPair('operation', 'query');
    LArgs.AddPair('host',     'localhost');
    LArgs.AddPair('port',     TJSONNumber.Create(5432));
    LArgs.AddPair('database', 'postgres');
    LArgs.AddPair('user',     'postgres');
    LArgs.AddPair('password', 'masterkey');
    LArgs.AddPair('sql', 'SELECT version()');

    INFO('Calling mcp-postgres (op=query) with: ' + LArgs.ToJSON);
    LResult := LItem.MCPClient.CallTool('mcp-postgres', LArgs, LMedia);
    if Assigned(LResult) then
    try
      OK('Response: ' + Copy(LResult.ToJSON, 1, 400));
    finally
      LResult.Free;
    end
    else
      ERR('CallTool returned nil.');
  finally
    LArgs.Free;
    LMedia.Free;
  end;
end;

// ============================================================================
// TEST 4 — Chat with LLM + AutoMCP (same scenario as user)
// ============================================================================
procedure TPostgresAutoMCPTest.TestChatPostgres;
var
  LResp: string;
begin
  HDR('TEST 4 — LLM chat + AutoMCP: verify local postgres');
  FAiConn.NewChat;
  // Update system prompt to include mcp-postgres if already installed
  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;

  INFO('System prompt:');
  Writeln(Copy(FAiConn.SystemPrompt.Text, 1, 600));
  Writeln;
  INFO('Sending prompt...');

  FLastError := '';
  try
    LResp := FAiConn.AddMessageAndRun(
      'Puedes verificar si mi base de datos postgres local está activa? ' +
      'Usa esta cadena de conexión: ' + FPGConn +
      '. Ejecuta un SELECT 1 para confirmar que está activa.',
      'user', []);
  except
    on E: Exception do LResp := '(exception: ' + E.Message + ')';
  end;

  if LResp <> '' then
  begin
    Writeln;
    OK('LLM response:');
    Writeln(LResp);
    Writeln;
  end
  else if FLastError <> '' then
    ERR('No response, error: ' + FLastError)
  else
    ERR('No response and no error recorded.');
end;

// ============================================================================
// TEST 5 — Install mcp-tts-gemini from PPM (v1.1.0 — standard format)
// ============================================================================
procedure TPostgresAutoMCPTest.TestTTSGeminiSetup;
var
  LItem: TMCPClientItem;
begin
  HDR('TEST 5 — Install mcp-tts-gemini v1.1.0 from PPM');

  LItem := FFunctions.MCPClients.GetClientByName('mcp-tts-gemini');
  if Assigned(LItem) then
    INFO('mcp-tts-gemini already registered: ' + LItem.Params.Values['Command'])
  else
  begin
    INFO('Downloading mcp-tts-gemini from PPM...');
    LItem := FFunctions.InstallMCPFromPPM('mcp-tts-gemini', '', '',
      'https://registry.cimamaker.com');
    if not Assigned(LItem) then
    begin
      ERR('InstallMCPFromPPM returned nil.');
      Exit;
    end;
    OK('Installed at: ' + LItem.Params.Values['Command']);
  end;

  INFO('Initializing MCP process...');
  if not LItem.MCPClient.Initialized then
    LItem.MCPClient.Initialize;

  if LItem.MCPClient.Available then
  begin
    OK('Process active.');
    var LRoot := TJSONObject.ParseJSONValue(LItem.MCPClient.Tools.Text) as TJSONObject;
    if Assigned(LRoot) then
    try
      var LArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('tools', LArr) then
      begin
        INFO(Format('%d tool(s):', [LArr.Count]));
        for var I := 0 to LArr.Count - 1 do
        begin
          var LTool := LArr.Items[I] as TJSONObject;
          var LName, LDesc: string;
          LTool.TryGetValue<string>('name', LName);
          LTool.TryGetValue<string>('description', LDesc);
          Writeln(Format('  [%d] %s — %s', [I, LName, Copy(LDesc, 1, 120)]));
        end;
      end;
    finally
      LRoot.Free;
    end;
  end
  else
    ERR('MCP process not available. Verify GEMINI_API_KEY.');
end;

// ============================================================================
// TEST 6 — Direct call to tts-gemini (without LLM): see raw returned JSON
// ============================================================================
procedure TPostgresAutoMCPTest.TestTTSGeminiDirect;
var
  LItem: TMCPClientItem;
  LArgs, LResult: TJSONObject;
  LMedia: TObjectList<TAiMediaFile>;
  LToolName, LRawJson: string;
begin
  HDR('TEST 6 — Direct call to tts-gemini: "hola"');

  LItem := FFunctions.MCPClients.GetClientByName('mcp-tts-gemini');
  if not Assigned(LItem) or not LItem.MCPClient.Available then
  begin
    ERR('mcp-tts-gemini not available. Run TEST 5 first.');
    Exit;
  end;

  // Determine real TTS tool name on server
  LToolName := '';
  var LToolsRoot := TJSONObject.ParseJSONValue(LItem.MCPClient.Tools.Text) as TJSONObject;
  if Assigned(LToolsRoot) then
  try
    var LArr: TJSONArray;
    if LToolsRoot.TryGetValue<TJSONArray>('tools', LArr) and (LArr.Count > 0) then
      (LArr.Items[0] as TJSONObject).TryGetValue<string>('name', LToolName);
  finally
    LToolsRoot.Free;
  end;

  if LToolName = '' then
  begin
    ERR('No tool found in tts-gemini.');
    Exit;
  end;

  INFO('Calling tool: "' + LToolName + '" with text "hola"');

  LArgs  := TJSONObject.Create;
  LMedia := TObjectList<TAiMediaFile>.Create(True);
  try
    LArgs.AddPair('text', 'hola');

    LResult := LItem.MCPClient.CallTool(LToolName, LArgs, LMedia);
    if Assigned(LResult) then
    try
      LRawJson := LResult.ToJSON;
      Writeln;
      Writeln('  Complete raw JSON:');
      Writeln('  ' + Copy(LRawJson, 1, 1000));
      if Length(LRawJson) > 1000 then
        Writeln(Format('  ... [total %d chars]', [Length(LRawJson)]));
      Writeln;

      // Is there audio in content?
      var LContent: TJSONArray;
      if LResult.TryGetValue<TJSONArray>('content', LContent) then
      begin
        INFO(Format('%d element(s) in "content":', [LContent.Count]));
        for var I := 0 to LContent.Count - 1 do
        begin
          var LObj := LContent.Items[I] as TJSONObject;
          var LType, LMimeType, LData: string;
          LObj.TryGetValue<string>('type', LType);
          LObj.TryGetValue<string>('mimeType', LMimeType);
          LObj.TryGetValue<string>('data', LData);
          Writeln(Format('  [%d] type=%s  mimeType=%s  data_len=%d',
            [I, LType, LMimeType, Length(LData)]));
        end;
      end;

      // Did extracted media files arrive?
      if LMedia.Count > 0 then
      begin
        INFO(Format('%d extracted media file(s):', [LMedia.Count]));
        for var MF in LMedia do
        begin
          var LStream := MF.Content; // GetContent ahora resetea Position := 0
          Writeln(Format('  • %s  cat=%d  stream.Size=%d  stream.Position=%d',
            [MF.FileName, Ord(MF.FileCategory), LStream.Size, LStream.Position]));

          // Save to disk to play manually
          if LStream.Size > 0 then
          begin
            var LSavePath := TPath.Combine(TPath.GetTempPath, MF.FileName);
            LStream.SaveToFile(LSavePath);
            OK('Audio saved at: ' + LSavePath);
          end;
        end;
      end
      else
        INFO('(no extracted media files — audio may be inline in JSON)');
    finally
      LResult.Free;
    end
    else
      ERR('CallTool returned nil.');
  finally
    LArgs.Free;
    LMedia.Free;
  end;
end;

// ============================================================================
// TEST 7 — LLM chat: ask AI to use tts-gemini to say "hola"
// ============================================================================
procedure TPostgresAutoMCPTest.TestTTSGeminiChat;
var
  LResp: string;
begin
  HDR('TEST 7 — LLM chat + AutoMCP: use tts-gemini to say "hola"');
  FAiConn.NewChat;
  // Update system prompt — tts-gemini should appear as already installed
  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;

  INFO('System prompt (first 400):');
  Writeln(Copy(FAiConn.SystemPrompt.Text, 1, 400));
  Writeln;

  INFO('Prompt: use tts-gemini to say hello...');
  FLastError := '';
  try
    LResp := FAiConn.AddMessageAndRun(
      'Usa el servidor MCP mcp-tts-gemini para generar audio con el texto "hola". ' +
      'Llama a call_mcp_tool con tool_name="mcp-tts-gemini" y el texto. ' +
      'Muéstrame la respuesta JSON cruda que devuelve el servidor.',
      'user', []);
  except
    on E: Exception do LResp := '(exception: ' + E.Message + ')';
  end;

  if LResp <> '' then
  begin
    Writeln;
    OK('LLM response:');
    Writeln(LResp);
  end
  else
    ERR('No response. Error: ' + FLastError);
end;

// ============================================================================
// Interactive mode
// ============================================================================
procedure TPostgresAutoMCPTest.InteractiveLoop;
var
  LInput, LResp: string;
begin
  HDR('INTERACTIVE MODE (AutoMCP active — Ollama + gpt-oss)');
  Writeln('  /new    = new conversation');
  Writeln('  /tools  = list available tools');
  Writeln('  /exit   = exit');
  Writeln;
  FAiConn.NewChat;
  FAiConn.SystemPrompt.Text := FFunctions.GetAutoMCPSystemPrompt;

  repeat
    Write('You> ');
    Readln(LInput);
    LInput := Trim(LInput);
    if LInput = '' then Continue;
    if SameText(LInput, '/exit') then Break;
    if SameText(LInput, '/new')  then begin FAiConn.NewChat; OK('New conversation.'); Continue; end;
    if SameText(LInput, '/tools') then
    begin
      var LToolsJson := FFunctions.GetTools(tfOpenAI);
      var LRoot := TJSONObject.ParseJSONValue(LToolsJson) as TJSONObject;
      if Assigned(LRoot) then
      try
        var LArr: TJSONArray;
        if LRoot.TryGetValue<TJSONArray>('tools', LArr) then
          for var I := 0 to LArr.Count - 1 do
          begin
            var LTool := LArr.Items[I] as TJSONObject;
            var LFunc: TJSONObject;
            var LName: string;
            if LTool.TryGetValue<TJSONObject>('function', LFunc) then
              LFunc.TryGetValue<string>('name', LName)
            else
              LTool.TryGetValue<string>('name', LName);
            Writeln('  • ' + LName);
          end;
      finally
        LRoot.Free;
      end;
      Continue;
    end;

    FLastError := '';
    try
      LResp := FAiConn.AddMessageAndRun(LInput, 'user', []);
    except
      on E: Exception do LResp := '(exception: ' + E.Message + ')';
    end;
    if LResp <> '' then
    begin
      Writeln;
      Writeln('AI> ' + LResp);
      Writeln;
    end
    else if FLastError <> '' then
      ERR('Error: ' + FLastError);
  until False;
end;

// ============================================================================
// Run
// ============================================================================
procedure TPostgresAutoMCPTest.Run;
var
  LYN: string;
begin
  TestInstallPostgres;
  TestListTools;
  TestDirectQuery;
  TestChatPostgres;
  TestTTSGeminiSetup;
  TestTTSGeminiDirect;
  TestTTSGeminiChat;

  Sep;
  Write('Start interactive mode? (y/n): ');
  Readln(LYN);
  if SameText(Trim(LYN), 's') or SameText(Trim(LYN), 'y') then
    InteractiveLoop;
end;

// ============================================================================
// Main
// ============================================================================
var
  GTest: TPostgresAutoMCPTest;
  LDriver, LModel, LApiKey, LUrl, LPGConn: string;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    Writeln('╔══════════════════════════════════════════════════════════════════╗');
    Writeln('║   MakerAI — Demo 066: AutoMCP + PostgreSQL Console Test          ║');
    Writeln('╚══════════════════════════════════════════════════════════════════╝');
    Writeln;

    LDriver := GetEnvironmentVariable('DEMO_DRIVER');
    if LDriver = '' then LDriver := 'Ollama';

    LModel := GetEnvironmentVariable('DEMO_MODEL');
    if LModel = '' then LModel := 'gpt-oss:20b';

    LApiKey := GetEnvironmentVariable('DEMO_API_KEY');
    if LApiKey = '' then LApiKey := '@OLLAMA_API_KEY';

    LUrl := GetEnvironmentVariable('DEMO_URL');
    if LUrl = '' then LUrl := 'http://192.168.3.121:11434/';

    LPGConn := GetEnvironmentVariable('PG_CONN');
    if LPGConn = '' then LPGConn := 'postgresql://postgres:masterkey@localhost:5432/postgres';

    Writeln('Driver : ' + LDriver);
    Writeln('Model  : ' + LModel);
    Writeln('URL    : ' + LUrl);
    Writeln('PG     : ' + LPGConn);
    Sep;
    Writeln;

    GTest := TPostgresAutoMCPTest.Create(LDriver, LModel, LApiKey, LUrl, LPGConn);
    try
      GTest.Run;
    finally
      GTest.Free;
    end;
  except
    on E: Exception do
      Writeln('[FATAL] ' + E.ClassName + ': ' + E.Message);
  end;

  Writeln;
  Write('Press Enter to exit...');
  Readln;
end.
