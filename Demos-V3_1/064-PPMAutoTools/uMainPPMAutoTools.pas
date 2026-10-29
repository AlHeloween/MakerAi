// MIT License
//
// MakerAI - Demo 064: PPM Auto Tools
// Demonstrates how the LLM can discover, install, and run MCP tools
// from the PPM registry fully autonomously.
//
// Autonomous flow:
//   1. User asks for something requiring external access (e.g.: "search Pascal repos on GitHub")
//   2. LLM calls ppm_search("github") → sees mcp-github available
//   3. LLM calls ppm_install("mcp-github") → binary downloaded and configured
//   4. LLM calls call_mcp_tool("mcp-github", "search_repos", '{"query":"pascal"}')
//   5. Result returned to LLM → response to user

unit uMainPPMAutoTools;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.JSON, System.Generics.Collections, System.Threading, System.StrUtils,
  System.Net.HttpClient, System.SyncObjs,

  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Layouts, FMX.StdCtrls, FMX.Edit, FMX.Memo, FMX.Memo.Types,
  FMX.Controls.Presentation, FMX.ScrollBox, FMX.ListBox,
  FMX.Objects,

  uMakerAi.Core, uMakerAi.Chat, uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection, uMakerAi.Chat.Initializations,
  uMakerAi.Chat.OpenAi, uMakerAi.Chat.Claude, uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Ollama, uMakerAi.Chat.Groq, uMakerAi.Chat.Grok,
  uMakerAi.Chat.DeepSeek, uMakerAi.Chat.Mistral, uMakerAi.Chat.Cohere,
  uMakerAi.Chat.Kimi, uMakerAi.Chat.LMStudio, uMakerAi.Chat.GenericLLM,
  uMakerAi.Tools.Functions, uMakerAi.MCPClient.Core,
  uMakerAi.UI.ChatList, uMakerAi.UI.ChatInput, uMakerAi.UI.ChatBubble;

type
  TfrmPPMAutoTools = class(TForm)
    // -- Non-visual components --
    AiConn: TAiChatConnection;
    AiFunctions1: TAiFunctions;

    // -- Main layout --
    MainLayout: TLayout;

    // -- Left panel (configuration) --
    LeftPanel: TLayout;
    RectLeft: TRectangle;
    LblTitulo: TLabel;
    LblDriver: TLabel;
    ComboDriver: TComboBox;
    LblModel: TLabel;
    ComboModel: TComboBox;
    LblApiKey: TLabel;
    EditApiKey: TEdit;
    ChAsync: TCheckBox;
    LineSep1: TLine;
    LblInstalados: TLabel;
    MemoInstalados: TMemo;
    LineSep2: TLine;
    LblLog: TLabel;
    MemoLog: TMemo;

    // -- Right panel (chat) --
    ChatPanel: TLayout;
    ChatList1: TChatList;
    AniIndicator1: TAniIndicator;
    RectStatus: TRectangle;
    LblStatus: TLabel;
    ChatInput1: TChatInput;

    procedure FormCreate(Sender: TObject);
    procedure ComboDriverChange(Sender: TObject);
    procedure ComboModelChange(Sender: TObject);
    procedure EditApiKeyChange(Sender: TObject);
    procedure ChatInput1SendEvent(Sender: TObject; APrompt: string;
      aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
    procedure ChatInput1Cancel(Sender: TObject);
    procedure AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnError(Sender: TObject; const ErrorMsg: string;
      Exception: Exception; const aResponse: IHTTPResponse);
    procedure AiConnStateChange(Sender: TObject; State: TAiChatState;
      const Description: string);
    procedure AiFunctions1Log(Sender: TObject; const Msg: string);
    procedure AiFunctions1StatusUpdate(Sender: TObject; const StatusMsg: string);
    procedure FormDestroy(Sender: TObject);

    // -- Handlers for the 3 PPM functions --
    procedure OnPpmSearch(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnPpmInstall(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnCallMcpTool(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);

  private
    FLastBubble: TChatBubble;
    FMCPLock: TCriticalSection; // Serializa llamadas concurrentes a CallTool

    procedure AddLog(const AMsg: string);
    procedure SetStatus(const AMsg: string);
    procedure AddInstalledTool(const AName, AExePath: string);
    procedure InitFunctions;
    procedure InitSystemPrompt;
    procedure InitDrivers;
    function  GetInstalledToolsFile: string;
    procedure SaveInstalledTools;
    procedure LoadInstalledTools;
    procedure UpdateSystemPromptWithInstalledTools;
  end;

var
  frmPPMAutoTools: TfrmPPMAutoTools;

implementation

{$R *.fmx}

const
  // Prompt that explains to the LLM how to use PPM tools autonomously
  SYSTEM_PROMPT =
    'You are an intelligent assistant with access to the PPM registry (PascalAI Package Manager), ' +
    'a catalog of more than 158 MCP tools covering GitHub, PostgreSQL, Slack, Jira, ' +
    'Stripe, DuckDB, Kubernetes, AWS S3, Azure, Kafka, GraphQL and many more.' + sLineBreak +
    sLineBreak +
    'When the user asks for something that requires access to external services, act ' +
    'AUTONOMOUSLY following this flow without asking for permission:' + sLineBreak +
    '  1. Call ppm_search with keywords to find the right tool.' + sLineBreak +
    '  2. Call ppm_install with the exact package name to install it.' + sLineBreak +
    '  3. Call call_mcp_tool with the tool name, function, and JSON arguments.' + sLineBreak +
    sLineBreak +
    'Important conventions:' + sLineBreak +
    '- Package names follow the mcp-<service> pattern (e.g.: mcp-github, mcp-postgres).' + sLineBreak +
    '- call_mcp_tool arguments must be a valid JSON string.' + sLineBreak +
    '- If an installation fails, inform the user clearly.' + sLineBreak +
    '- Respond in the same language as the user.';

{ TfrmPPMAutoTools }

// ---------------------------------------------------------------------------
// Persistencia de herramientas instaladas
// ---------------------------------------------------------------------------

function TfrmPPMAutoTools.GetInstalledToolsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) +
            '.ppm\ppm_installed.json';
end;

procedure TfrmPPMAutoTools.SaveInstalledTools;
var
  LArr: TJSONArray;
  LObj: TJSONObject;
  LItem: TMCPClientItem;
  I: Integer;
  LSL: TStringList;
begin
  LArr := TJSONArray.Create;
  try
    for I := 0 to AiFunctions1.MCPClients.Count - 1 do
    begin
      LItem := AiFunctions1.MCPClients[I];
      LObj := TJSONObject.Create;
      LObj.AddPair('name',      LItem.Name);
      LObj.AddPair('command',   LItem.Params.Values['Command']);
      LObj.AddPair('arguments', LItem.Params.Values['Arguments']);
      LObj.AddPair('rootdir',   LItem.Params.Values['RootDir']);
      LArr.Add(LObj);
    end;
    var LDir := ExtractFileDir(GetInstalledToolsFile);
    if not DirectoryExists(LDir) then
      ForceDirectories(LDir);
    LSL := TStringList.Create;
    try
      LSL.Text := LArr.Format;
      LSL.SaveToFile(GetInstalledToolsFile, TEncoding.UTF8);
    finally
      LSL.Free;
    end;
  finally
    LArr.Free;
  end;
end;

procedure TfrmPPMAutoTools.LoadInstalledTools;
var
  LJson: string;
  LArr: TJSONArray;
  LItem: TMCPClientItem;
  LSL: TStringList;
begin
  if not FileExists(GetInstalledToolsFile) then Exit;
  try
    LSL := TStringList.Create;
    try
      LSL.LoadFromFile(GetInstalledToolsFile, TEncoding.UTF8);
      LJson := LSL.Text;
    finally
      LSL.Free;
    end;
    LArr := TJSONObject.ParseJSONValue(LJson) as TJSONArray;
    if not Assigned(LArr) then Exit;
    try
      for var LVal in LArr do
      begin
        if not (LVal is TJSONObject) then Continue;
        var LO   := TJSONObject(LVal);
        var LName := LO.GetValue<string>('name', '');
        var LCmd  := LO.GetValue<string>('command', '');
        if (LName = '') or (LCmd = '') then Continue;
        if not FileExists(LCmd) then
        begin
          AddLog('LoadTools: executable not found for "' + LName + '", ignoring.');
          Continue;
        end;
        if Assigned(AiFunctions1.MCPClients.GetClientByName(LName)) then Continue;

        LItem := AiFunctions1.MCPClients.Add;
        LItem.Name          := LName;
        LItem.TransportType := tpStdIo;
        LItem.Params.Values['Command']   := LCmd;
        LItem.Params.Values['Arguments'] := LO.GetValue<string>('arguments', '--protocol stdio');
        LItem.Params.Values['RootDir']   := LO.GetValue<string>('rootdir', '');
        LItem.Enabled := False;
        LItem.UpdateClientProperties;

        AddInstalledTool(LName, LCmd);
        AddLog('LoadTools: "' + LName + '" restored from disk.');
      end;
    finally
      LArr.Free;
    end;
  except
    on E: Exception do
      AddLog('LoadTools: error loading tools — ' + E.Message);
  end;
  UpdateSystemPromptWithInstalledTools;
end;

procedure TfrmPPMAutoTools.UpdateSystemPromptWithInstalledTools;
var
  LSb: TStringBuilder;
  I: Integer;
begin
  if AiFunctions1.MCPClients.Count = 0 then
  begin
    AiConn.SystemPrompt.Text := SYSTEM_PROMPT;
    Exit;
  end;
  LSb := TStringBuilder.Create;
  try
    LSb.Append(SYSTEM_PROMPT);
    LSb.AppendLine;
    LSb.AppendLine;
    LSb.AppendLine('MCP TOOLS ALREADY INSTALLED (do not use ppm_install for these):');
    for I := 0 to AiFunctions1.MCPClients.Count - 1 do
      LSb.AppendLine('- ' + AiFunctions1.MCPClients[I].Name +
        ' (use call_mcp_tool directly, without ppm_install)');
    LSb.AppendLine('For these tools: skip ppm_search and ppm_install, go straight to step 3.');
    AiConn.SystemPrompt.Text := LSb.ToString;
  finally
    LSb.Free;
  end;
end;

procedure TfrmPPMAutoTools.FormDestroy(Sender: TObject);
begin
  FMCPLock.Free;
end;

procedure TfrmPPMAutoTools.FormCreate(Sender: TObject);
var
  LDrivers, LModels: TStringList;
begin
  FLastBubble := nil;
  FMCPLock := TCriticalSection.Create;

  // Register available drivers
  InitDrivers;

  // Configure the 3 PPM functions in AiFunctions1
  InitFunctions;

  // Assign base system prompt
  InitSystemPrompt;

  // Connect AiFunctions1 with AiConn
  AiConn.AiFunctions := AiFunctions1;

  // Connect status and log events
  AiConn.OnStateChange        := AiConnStateChange;
  AiFunctions1.OnLog          := AiFunctions1Log;
  AiFunctions1.OnStatusUpdate := AiFunctions1StatusUpdate;

  // Restore tools installed in previous sessions
  LoadInstalledTools;

  // Populate driver combo
  LDrivers := AiConn.GetDriversNames;
  try
    LDrivers.Sort;
    ComboDriver.Items.Assign(LDrivers);
    if ComboDriver.Items.Count > 0 then
    begin
      // Try to preselect OpenAI
      var Idx := ComboDriver.Items.IndexOf('OpenAI');
      if Idx >= 0 then
        ComboDriver.ItemIndex := Idx
      else
        ComboDriver.ItemIndex := 0;
      ComboDriverChange(nil);
    end;
  finally
    LDrivers.Free;
  end;
end;

procedure TfrmPPMAutoTools.InitDrivers;
begin
  // Base configurations per driver
  AiConn.RegisterUserParam('OpenAI',    'Asynchronous', 'True');
  AiConn.RegisterUserParam('OpenAI',    'Tool_Active',  'True');
  AiConn.RegisterUserParam('Claude',    'Asynchronous', 'True');
  AiConn.RegisterUserParam('Claude',    'Tool_Active',  'True');
  AiConn.RegisterUserParam('Gemini',    'Asynchronous', 'True');
  AiConn.RegisterUserParam('Gemini',    'Tool_Active',  'True');
  AiConn.RegisterUserParam('Groq',      'Asynchronous', 'True');
  AiConn.RegisterUserParam('Groq',      'Tool_Active',  'True');
  AiConn.RegisterUserParam('Ollama',    'Asynchronous', 'True');
  AiConn.RegisterUserParam('Ollama',    'Tool_Active',  'True');
  AiConn.RegisterUserParam('Ollama',    'Url',          'http://localhost:11434/');
end;

procedure TfrmPPMAutoTools.InitFunctions;
var
  LFn: TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  AiFunctions1.Functions.Clear;

  // --- Función 1: ppm_search ---
  LFn := TFunctionActionItem(AiFunctions1.Functions.Add);
  LFn.FunctionName := 'ppm_search';
  LFn.Description.Text :=
    'Search for MCP tools in the PPM registry. Returns a list of available tools ' +
    'matching the query. Use this before calling ppm_install.';
  LFn.OnAction := OnPpmSearch;

  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name            := 'query';
  LParam.Description.Text := 'Search keywords (e.g.: github, postgres, slack, kubernetes)';
  LParam.ParamType        := ptString;
  LParam.Required         := True;

  // --- Función 2: ppm_install ---
  LFn := TFunctionActionItem(AiFunctions1.Functions.Add);
  LFn.FunctionName := 'ppm_install';
  LFn.Description.Text :=
    'Download and install an MCP tool from the PPM registry. ' +
    'After installation the tool is ready to use with call_mcp_tool. ' +
    'Do NOT ask for user confirmation — install immediately when needed.';
  LFn.OnAction := OnPpmInstall;

  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name            := 'tool_name';
  LParam.Description.Text := 'Exact PPM package name (e.g.: mcp-github, mcp-postgres, mcp-slack)';
  LParam.ParamType        := ptString;
  LParam.Required         := True;

  // --- Función 3: call_mcp_tool ---
  LFn := TFunctionActionItem(AiFunctions1.Functions.Add);
  LFn.FunctionName := 'call_mcp_tool';
  LFn.Description.Text :=
    'Call a specific function on an installed MCP tool. ' +
    'Use ppm_search and ppm_install first if the tool is not yet installed. ' +
    'You can get the available function names and their schemas from ppm_search results.';
  LFn.OnAction := OnCallMcpTool;

  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name            := 'tool_name';
  LParam.Description.Text := 'Name of the installed MCP tool (e.g.: mcp-github)';
  LParam.ParamType        := ptString;
  LParam.Required         := True;

  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name            := 'function_name';
  LParam.Description.Text := 'Name of the function to call on the tool (from its schema)';
  LParam.ParamType        := ptString;
  LParam.Required         := True;

  LParam := TFunctionParamsItem(LFn.Parameters.Add);
  LParam.Name            := 'arguments';
  LParam.Description.Text := 'JSON string with the function arguments (e.g.: {"query":"pascal","limit":10})';
  LParam.ParamType        := ptString;
  LParam.Required         := True;
end;

procedure TfrmPPMAutoTools.InitSystemPrompt;
begin
  AiConn.SystemPrompt.Text := SYSTEM_PROMPT;
end;

// ---------------------------------------------------------------------------
// Handlers de funciones PPM
// ---------------------------------------------------------------------------

procedure TfrmPPMAutoTools.OnPpmSearch(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: string;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LQuery: string;
  LResult: TJSONObject;
  LTools: TJSONArray;
  LTool: TJSONObject;
  LSb: TStringBuilder;
  I: Integer;
begin
  var LArgsS := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsS) then
  try
    LArgsS.TryGetValue<string>('query', LQuery);
    LQuery := Trim(LQuery);
  finally
    LArgsS.Free;
  end;
  AddLog('ppm_search: "' + LQuery + '"...');
  SetStatus('Searching "' + LQuery + '" in PPM registry...');

  LResult := AiFunctions1.SearchPPMMCP(LQuery);
  if not Assigned(LResult) then
  begin
    ToolCall.Response := 'Could not connect to PPM registry. Check connection.';
    Handled := True;
    Exit;
  end;

  try
    // Format results compactly for the LLM
    LSb := TStringBuilder.Create;
    try
      if LResult.TryGetValue<TJSONArray>('tools', LTools) and (LTools.Count > 0) then
      begin
        LSb.AppendLine(Format('Found %d tools for "%s":', [LTools.Count, LQuery]));
        LSb.AppendLine;
        for I := 0 to LTools.Count - 1 do
        begin
          LTool := LTools.Items[I] as TJSONObject;
          var LName, LDesc, LVer: string;
          LTool.TryGetValue<string>('name',        LName);
          LTool.TryGetValue<string>('description', LDesc);
          LTool.TryGetValue<string>('version',     LVer);

          LSb.AppendLine(Format('• %s (v%s)', [LName, LVer]));
          LSb.AppendLine('  ' + LDesc);

          // Include available operations from the schema if present
          var LSchema: TJSONObject;
          if LTool.TryGetValue<TJSONObject>('schema', LSchema) then
          begin
            var LInput: TJSONObject;
            if LSchema.TryGetValue<TJSONObject>('inputSchema', LInput) then
            begin
              var LProps: TJSONObject;
              if LInput.TryGetValue<TJSONObject>('properties', LProps) then
              begin
                // Extract operations from the enum if it exists
                var LOpEnum: TJSONArray;
                var LOp: TJSONObject;
                if LProps.TryGetValue<TJSONObject>('operation', LOp) and
                   LOp.TryGetValue<TJSONArray>('enum', LOpEnum) then
                begin
                  var LOps := TStringList.Create;
                  try
                    for var J := 0 to LOpEnum.Count - 1 do
                      LOps.Add(LOpEnum.Items[J].Value);
                    LSb.AppendLine('  Operaciones: ' + LOps.CommaText);
                  finally
                    LOps.Free;
                  end;
                end;
              end;
            end;
          end;
          LSb.AppendLine;
        end;
        LSb.AppendLine('To use a tool: first call ppm_install("<name>"), then call_mcp_tool.');
      end
      else
        LSb.AppendLine(Format('No tools found for "%s" in PPM registry.', [LQuery]));

      ToolCall.Response := LSb.ToString;
    finally
      LSb.Free;
    end;
  finally
    LResult.Free;
  end;

  AddLog('ppm_search: OK (' + LQuery + ')');
  Handled := True;
end;

procedure TfrmPPMAutoTools.OnPpmInstall(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: string;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LToolName: string;
  LItem: TMCPClientItem;
begin
  var LArgsI := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsI) then
  try
    LArgsI.TryGetValue<string>('tool_name', LToolName);
    LToolName := Trim(LToolName);
  finally
    LArgsI.Free;
  end;
  AddLog('ppm_install: "' + LToolName + '"...');

  // If client already registered, reuse it without downloading again
  LItem := AiFunctions1.MCPClients.GetClientByName(LToolName);
  if Assigned(LItem) then
  begin
    AddLog('ppm_install: "' + LToolName + '" already installed, reusing.');
    SetStatus('"' + LToolName + '" already available.');
  end
  else
  begin
    SetStatus('Installing package "' + LToolName + '" from PPM...');
    LItem := AiFunctions1.InstallMCPFromPPM(LToolName);
  end;

  if Assigned(LItem) then
  begin
    // Initialize MCP client (starts process and queries tools/list)
    AddLog('ppm_install: initializing process "' + LToolName + '"...');
    if LItem.MCPClient.Initialize then
    begin
      // Disable client so GetTools does not expose its tools
      // directly to LLM. Thus LLM can only access them through
      // call_mcp_tool (our handler), avoiding parallel calls
      // uncontrolled that would cause race conditions in TMCPClientStdIo.
      LItem.Enabled := False;

      // Extract real function names from tools/list to inform LLM
      var LFuncNames := TStringList.Create;
      try
        var LToolsJson := TJSONObject.ParseJSONValue(LItem.MCPClient.Tools.Text);
        if Assigned(LToolsJson) then
        try
          var LToolsArr: TJSONArray;
          if LToolsJson.TryGetValue<TJSONArray>('tools', LToolsArr) then
            for var LT in LToolsArr do
            begin
              var LFName: string;
              if (LT is TJSONObject) and TJSONObject(LT).TryGetValue<string>('name', LFName) then
                LFuncNames.Add(LFName);
            end;
        finally
          LToolsJson.Free;
        end;
      except
        // if parse fails, continue without function list
      end;

      var LFuncList := '';
      if LFuncNames.Count > 0 then
        LFuncList := sLineBreak + 'Available functions: ' + LFuncNames.CommaText
      else
        LFuncList := '';

      LFuncNames.Free;

      ToolCall.Response := Format(
        'Tool "%s" installed and initialized successfully.' + sLineBreak +
        'Executable: %s' + sLineBreak +
        'You can now call it with call_mcp_tool.%s',
        [LToolName, LItem.Params.Values['Command'], LFuncList]);

      AddInstalledTool(LToolName, LItem.Params.Values['Command']);
      AddLog('ppm_install: OK → ' + LItem.Params.Values['Command']);
      SaveInstalledTools;
      UpdateSystemPromptWithInstalledTools;
    end
    else
    begin
      ToolCall.Response := Format(
        'Tool "%s" installed but the process could not be initialized. ' +
        'Verify that the executable exists and is compatible.', [LToolName]);
      AddLog('ppm_install: WARN - process not started for ' + LToolName);
    end;
  end
  else
  begin
    ToolCall.Response := Format(
      'Could not install "%s". Verify the package name and the connection.', [LToolName]);
    AddLog('ppm_install: ERROR - ' + LToolName);
  end;

  Handled := True;
end;

procedure TfrmPPMAutoTools.OnCallMcpTool(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: string;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LToolName, LFuncName, LArgStr: string;
  LClientItem: TMCPClientItem;
  LArgsJson: TJSONObject;
  LResult: TJSONObject;
  LMedia: TObjectList<TAiMediaFile>;
begin
  // Global critical section: serializes concurrent calls to any MCP client
  // (TMCPClientStdIo is not thread-safe — two parallel calls to same client
  //  produce race conditions → EInvalidPointer)
  FMCPLock.Enter;
  try

  var LArgsC := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsC) then
  try
    LArgsC.TryGetValue<string>('tool_name',     LToolName);
    LArgsC.TryGetValue<string>('function_name', LFuncName);
    LArgsC.TryGetValue<string>('arguments',     LArgStr);
    LToolName := Trim(LToolName);
    LFuncName := Trim(LFuncName);
    LArgStr   := Trim(LArgStr);
  finally
    LArgsC.Free;
  end;

  AddLog(Format('call_mcp_tool: %s → %s', [LToolName, LFuncName]));
  SetStatus(Format('Executing %s.%s...', [LToolName, LFuncName]));

  // Find installed client
  LClientItem := AiFunctions1.MCPClients.GetClientByName(LToolName);
  if not Assigned(LClientItem) then
  begin
    ToolCall.Response := Format(
      'The tool "%s" is not installed. Use ppm_install first.', [LToolName]);
    Handled := True;
    Exit;
  end;

  // Connect MCP client log to demo log to see server errors
  LClientItem.MCPClient.OnLog := AiFunctions1Log;
  LClientItem.MCPClient.OnStatusUpdate := AiFunctions1StatusUpdate;

  // Parse arguments before checking connection_string
  LArgsJson := nil;
  if (LArgStr <> '') and (LArgStr <> '{}') then
  begin
    LArgsJson := TJSONObject.ParseJSONValue(LArgStr) as TJSONObject;
    if not Assigned(LArgsJson) then
    begin
      ToolCall.Response := Format('Argumentos JSON inválidos para "%s": %s', [LFuncName, LArgStr]);
      Handled := True;
      Exit;
    end;
  end
  else
    LArgsJson := TJSONObject.Create;

  // If LLM passes connection_string, use it as process startup argument.
  // mcp-postgres (and many other MCP tools) need connection as argument
  // positional when starting process (e.g.: mcp-postgres.exe postgresql://user:pass@host/db).
  var LConnStr: string;
  var LConnStrUpdated := False;
  if LArgsJson.TryGetValue<string>('connection_string', LConnStr) and (LConnStr <> '') then
  begin
    LClientItem.MCPClient.Params.Values['Arguments'] := LConnStr;
    LArgsJson.RemovePair('connection_string');
    LConnStrUpdated := True;
    AddLog('call_mcp_tool: connection_string → startup arg: ' + LConnStr);
  end;

  // Initialize if not done yet, OR re-initialize if connection_string updated.
  // Re-initialize needed because ppm_install started server without connection_string,
  // so previous tools/list may be empty or incomplete.
  if not LClientItem.MCPClient.Initialized or LConnStrUpdated then
  begin
    AddLog('call_mcp_tool: initializing ' + LToolName + '...');
    LClientItem.MCPClient.Initialized := False;
    if not LClientItem.MCPClient.Initialize then
    begin
      ToolCall.Response := Format(
        'Could not initialize "%s". ' +
        'Verify that the executable exists and supports --protocol stdio.', [LToolName]);
      Handled := True;
      Exit;
    end;
  end;

  LMedia := TObjectList<TAiMediaFile>.Create(True);
  try
    try
      AddLog('call_mcp_tool: starting CallTool...');
      // NOTE: CallTool takes ownership of LArgsJson and frees it internally.
      // Do NOT call LArgsJson.Free after this call.
      LResult := LClientItem.MCPClient.CallTool(LFuncName, LArgsJson, LMedia);
      LArgsJson := nil; // Ya fue liberado por CallTool
      AddLog('call_mcp_tool: CallTool completed. Result=' + BoolToStr(Assigned(LResult), True));
      try
        if Assigned(LResult) then
          ToolCall.Response := LResult.Format
        else
        begin
          // Include real available functions to help the LLM correct the name
          var LAvailFuncs := '';
          var LToolsJson := TJSONObject.ParseJSONValue(LClientItem.MCPClient.Tools.Text);
          if Assigned(LToolsJson) then
          try
            var LToolsArr: TJSONArray;
            if LToolsJson.TryGetValue<TJSONArray>('tools', LToolsArr) then
            begin
              var LSb := TStringList.Create;
              try
                for var LT in LToolsArr do
                begin
                  var LFN: string;
                  if (LT is TJSONObject) and TJSONObject(LT).TryGetValue<string>('name', LFN) then
                    LSb.Add(LFN);
                end;
                if LSb.Count > 0 then
                  LAvailFuncs := ' Funciones disponibles en ' + LToolName + ': ' + LSb.CommaText + '.';
              finally
                LSb.Free;
              end;
            end;
          finally
            LToolsJson.Free;
          end;
          ToolCall.Response := Format(
            'Function "%s" not found in "%s".%s',
            [LFuncName, LToolName, LAvailFuncs]);
        end;
      finally
        LResult.Free;
      end;
    except
      on E: Exception do
      begin
        AddLog('EXCEPTION in CallTool [' + E.ClassName + ']: ' + E.Message);
        ToolCall.Response := Format('Error executing "%s": %s — %s', [LFuncName, E.ClassName, E.Message]);
        LArgsJson := nil; // already freed or not — avoid double-free
      end;
    end;
  finally
    LMedia.Free;
  end;

  AddLog('call_mcp_tool: OK → ' + LToolName + '.' + LFuncName);
  Handled := True;

  finally
    FMCPLock.Leave;
  end;
end;

// ---------------------------------------------------------------------------
// Chat handlers
// ---------------------------------------------------------------------------

procedure TfrmPPMAutoTools.ChatInput1SendEvent(Sender: TObject; APrompt: string;
  aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
var
  LFiles: TAiMediaFilesArray;
begin
  // Configure chat parameters before each call
  AiConn.Params.Values['Asynchronous'] := BoolToStr(ChAsync.IsChecked, True);
  AiConn.Params.Values['Tool_Active']  := 'True';

  FLastBubble := nil;
  ChatList1.AddBubble(APrompt, 'Usuario', aMediaFiles, False);

  // Clone MediaFiles in main thread BEFORE TTask.Run.
  // DoSendEvent (TChatInput) frees aMediaFiles when this handler returns;
  // if captured in closure, background thread would access a
  // freed object → EInvalidPointer.
  LFiles := aMediaFiles.ToMediaFileArray;

  AniIndicator1.Visible := True;
  AniIndicator1.Enabled := True;

  TTask.Run(
    procedure
    begin
      try
        AiConn.AddMessageAndRun(APrompt, 'user', LFiles);
      except
        on E: Exception do
          AddLog('ERROR chat: ' + E.Message);
      end;
    end);
end;

procedure TfrmPPMAutoTools.ChatInput1Cancel(Sender: TObject);
begin
  AiConn.Abort;
  TThread.Queue(nil,
    procedure
    begin
      ChatInput1.Busy := False;
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;
    end);
end;

procedure TfrmPPMAutoTools.AiConnReceiveData(const Sender: TObject;
  aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  if not ChAsync.IsChecked then Exit;
  if aText = '' then Exit;

  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FLastBubble) then
        FLastBubble.AppendText(aText)
      else
        FLastBubble := ChatList1.AddBubble(aText, aRole, nil);
      ChatList1.RecalcSize;
    end);
end;

procedure TfrmPPMAutoTools.AiConnReceiveDataEnd(const Sender: TObject;
  aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      ChatInput1.Busy := False;
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;

      if not ChAsync.IsChecked then
        FLastBubble := ChatList1.AddBubble(aText, aRole, aMsg.MediaFiles);

      ChatList1.RecalcSize;
      FLastBubble := nil;
      LblStatus.Text := '';
    end);
end;

procedure TfrmPPMAutoTools.AiConnError(Sender: TObject; const ErrorMsg: string;
  Exception: Exception; const aResponse: IHTTPResponse);
begin
  TThread.Queue(nil,
    procedure
    begin
      ChatInput1.Busy := False;
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;
      LblStatus.Text := '';
      var LExClass := '';
      if Assigned(Exception) then LExClass := '[' + Exception.ClassName + '] ';
      AddLog('ERROR ' + LExClass + ': ' + ErrorMsg);
      ChatList1.AddBubble('⚠ ' + LExClass + ErrorMsg, 'System', nil);
    end);
end;

// ---------------------------------------------------------------------------
// Driver/Model combo
// ---------------------------------------------------------------------------

procedure TfrmPPMAutoTools.ComboDriverChange(Sender: TObject);
const
  // Drivers that do not need an API key
  NO_KEY_DRIVERS: array[0..2] of string = ('Ollama', 'LMStudio', 'GenericLLM');
var
  LDriverName, LEnvKey, LAutoKey: string;
  LModels: TStringList;
  I: Integer;
  LNeedsKey: Boolean;
begin
  if not Assigned(ComboDriver.Selected) then Exit;

  LDriverName := Trim(ComboDriver.Selected.Text);
  AiConn.DriverName := LDriverName;

  // Auto-detect API key environment variable
  LNeedsKey := True;
  for I := Low(NO_KEY_DRIVERS) to High(NO_KEY_DRIVERS) do
    if SameText(LDriverName, NO_KEY_DRIVERS[I]) then
    begin
      LNeedsKey := False;
      Break;
    end;

  if LNeedsKey then
  begin
    LEnvKey := UpperCase(LDriverName) + '_API_KEY';
    LAutoKey := GetEnvironmentVariable(LEnvKey);
    if LAutoKey <> '' then
    begin
      AiConn.Params.Values['ApiKey'] := LAutoKey;
      EditApiKey.Text := '(auto: ' + LEnvKey + ')';
    end
    else if Copy(EditApiKey.Text, 1, 5) = '(auto' then
      EditApiKey.Text := '';  // clear placeholder from another driver
  end
  else
  begin
    AiConn.Params.Values['ApiKey'] := '';
    EditApiKey.Text := '(not required)';
  end;

  LModels := AiConn.GetModels;
  try
    LModels.Sort;
    ComboModel.Items.Assign(LModels);
    if ComboModel.Items.Count > 0 then
      ComboModel.ItemIndex := 0;
  finally
    LModels.Free;
  end;

  // Synchronize async checkbox with driver parameter
  ChAsync.IsChecked := StrToBoolDef(AiConn.Params.Values['Asynchronous'], True);
end;

procedure TfrmPPMAutoTools.EditApiKeyChange(Sender: TObject);
var
  LKey: string;
begin
  LKey := EditApiKey.Text;
  // Ignore informational placeholders
  if Copy(LKey, 1, 1) = '(' then Exit;
  AiConn.Params.Values['ApiKey'] := LKey;
end;

procedure TfrmPPMAutoTools.ComboModelChange(Sender: TObject);
begin
  if Assigned(ComboModel.Selected) then
    AiConn.Model := Trim(ComboModel.Selected.Text);
end;

// ---------------------------------------------------------------------------
// Helpers de log e UI
// ---------------------------------------------------------------------------

procedure TfrmPPMAutoTools.SetStatus(const AMsg: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      LblStatus.Text := AMsg;
    end);
end;

procedure TfrmPPMAutoTools.AiConnStateChange(Sender: TObject; State: TAiChatState;
  const Description: string);
const
  STATE_ICONS: array[TAiChatState] of string = (
    '',                          // acsIdle
    'Connecting...',             // acsConnecting
    '',                          // acsCreated
    'Reasoning...',              // acsReasoning
    'Generating response...',    // acsWriting
    'Calling tool...',           // acsToolCalling
    'Executing tool...',         // acsToolExecuting
    '',                          // acsFinished
    '',                          // acsAborted
    'Loading...',                // acsLoading
    'Processing...',             // acsProcessing
    ''                           // acsError
  );
begin
  SetStatus(STATE_ICONS[State]);
end;

procedure TfrmPPMAutoTools.AiFunctions1Log(Sender: TObject; const Msg: string);
begin
  // Filter low-level messages (very verbose) to not saturate status
  if (Pos('DEBUG', Msg) > 0) or (Pos('Waiting for', Msg) > 0) or
     (Pos('TIMEOUT', Msg) > 0) then
    Exit;
  SetStatus(Msg);
  AddLog(Msg);
end;

procedure TfrmPPMAutoTools.AiFunctions1StatusUpdate(Sender: TObject; const StatusMsg: string);
begin
  SetStatus(StatusMsg);
end;

procedure TfrmPPMAutoTools.AddLog(const AMsg: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoLog.Lines.Add(FormatDateTime('[hh:nn:ss] ', Now) + AMsg);
      MemoLog.GoToTextEnd;
    end);
end;

procedure TfrmPPMAutoTools.AddInstalledTool(const AName, AExePath: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoInstalados.Lines.Add('✓ ' + AName);
    end);
end;

end.
