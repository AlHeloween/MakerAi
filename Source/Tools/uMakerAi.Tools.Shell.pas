unit uMakerAi.Tools.Shell;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils, System.Diagnostics,
  System.Generics.Collections, uMakerAi.Utils.System, uMakerAi.Tools.Functions, uMakerAi.Chat.Messages
{$IFDEF MSWINDOWS}
  , Winapi.Windows   // GetOEMCP: the actual code page in which cmd.exe writes
{$ENDIF}
  ;

type
  // Internal structure of a command result
  TShellExecutionResult = record
    StdOut: string;
    StdErr: string;
    ExitCode: Integer;
    TimedOut: Boolean;
  end;

  // Event to intercept/audit commands before execution
  TAiShellCommandEvent = procedure(Sender: TObject; const Command: string; const CallId: string; var Result: TShellExecutionResult; var Handled: Boolean) of object;
  TAiShellLogEvent = procedure(Sender: TObject; const Command: string; const StdOut, StdErr: string; ExitCode: Integer) of object;

  // Security mode for command filtering
  // ssmNone      : no filter (default behavior)
  // ssmBlockList : blocks commands in the list; the rest are allowed
  // ssmAllowList : only allows commands in the list; the rest are blocked
  TShellSecurityMode = (ssmNone, ssmBlockList, ssmAllowList);

  // Event raised when a command is blocked by security policy.
  // AErrorMessage can be modified to customize the message returned to the LLM.
  TAiShellSecurityEvent = procedure(Sender: TObject; const Command: string; const CallId: string; var AErrorMessage: string) of object;

  // Supported modes (to generate the correct Tool definition)

  TAiShell = class(TComponent)
  private
    FSession: TInteractiveProcessInfo;
    FTimeOut: Cardinal;
    FShellPath: string;
    FOnCommand: TAiShellCommandEvent;
    FActive: Boolean;
    FEnvironment: TStringList;
    FMaxOutputSize: Integer;
    FOnConsoleLog: TAiShellLogEvent;
    FSecurityMode: TShellSecurityMode;
    FSecurityList: TStringList;
    FOnSecurityViolation: TAiShellSecurityEvent;

    procedure SetActive(const Value: Boolean);
    function GenerateSentinel: string;
    function CleanOutput(const RawOutput, Sentinel: string): string;
    procedure StartSession;
    procedure StopSession;

    // Low-level execution (Atomic)
    function InternalExecuteCommand(const ACommand: string; TimeOutMs: Cardinal): TShellExecutionResult;

    // Provider-specific methods
    // Decodes shell output tolerating that it is NOT UTF-8.
    function DecodeShellBytes(const ABuffer: TBytes; ACount: Integer): string;
    function ExecuteClaudeAction(const CallId: string; JArgs: TJSONObject): string;
    function ExecuteOpenAIAction(const CallId: string; JArgs: TJSONObject): string;
    function ExecuteGenericAction(const CallId: string; JArgs: TJSONObject): string;
    procedure SetShellPath(const Value: string);
    procedure SetEnvironment(const Value: TStringList);
    procedure SetSecurityList(const Value: TStringList);

    // Returns '' if the command is allowed, or an error message if blocked.
    // Compares the first token of the command (executable/command name) against FSecurityList.
    function CheckSecurity(const ACommand, ACallId: string): string;

    // Internal handler used by RegisterInFunctions
    procedure OnFunctionAction(Sender: TObject; FunctionAction: TFunctionActionItem;    FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // --- SINGLE ENTRY POINT ---
    // Automatically detects the JSON format and delegates.
    function Execute(const CallId: string; const JsonArguments: string): string; overload;
    function Execute(const CallId: string; JArgs: TJSONObject): string; overload;
    function ExecuteManual(const Command: string): string;

    procedure Restart;

    { Registers the 'bash' function in a TAiFunctions for use with Ollama
      (and any provider that requires explicit tool definition).
      AFunctionName allows customizing the name if the model requires it. }
    procedure RegisterInFunctions(AFunctions: TAiFunctions;
      const AFunctionName: string = 'bash');

  published
    property Active: Boolean read FActive write SetActive default False;
    // NOTE: it is an INACTIVITY timeout, not a total duration. Each chunk
    // of output that arrives resets the clock, so a command that writes something
    // every second can run indefinitely without timing out; what triggers the
    // timeout is the command staying MUTE for this period. When it expires the
    // session is restarted (cwd and variables are lost) because the hung process
    // still occupies the pipe and would leave the shell unusable.
    property TimeOut: Cardinal read FTimeOut write FTimeOut default 30000;
    property ShellPath: string read FShellPath write SetShellPath;
    property MaxOutputSize: Integer read FMaxOutputSize write FMaxOutputSize default 20000;

    property Environment: TStringList read FEnvironment write SetEnvironment;

    // --- Security ---
    // Command filtering mode (ssmNone by default = no restrictions).
    property SecurityMode: TShellSecurityMode read FSecurityMode write FSecurityMode default ssmNone;
    // List of commands for the active mode.
    //   ssmBlockList: names of blocked commands (e.g. 'rm', 'del', 'format')
    //   ssmAllowList: names of allowed commands (e.g. 'dir', 'ls', 'echo')
    // Compared against the first token of the command, case-insensitive.
    property SecurityList: TStringList read FSecurityList write SetSecurityList;

    property OnCommand: TAiShellCommandEvent read FOnCommand write FOnCommand;
    property OnConsoleLog: TAiShellLogEvent read FOnConsoleLog write FOnConsoleLog;
    // Event raised when a command is rejected by security policy.
    property OnSecurityViolation: TAiShellSecurityEvent read FOnSecurityViolation write FOnSecurityViolation;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiShell]);
end;

{ TAiShell }

constructor TAiShell.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimeOut := 30000;
  FMaxOutputSize := 20000;
  FActive := False;
  FEnvironment := TStringList.Create;
  FSecurityMode := ssmNone;
  FSecurityList := TStringList.Create;
  FSecurityList.CaseSensitive := False;

{$IFDEF MSWINDOWS}
  FShellPath := 'cmd.exe';
{$ENDIF}
{$IFDEF POSIX}
  FShellPath := '/bin/bash';
{$ENDIF}
end;

destructor TAiShell.Destroy;
begin
  StopSession;
  FEnvironment.Free;
  FSecurityList.Free;
  inherited;
end;

procedure TAiShell.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FActive then
      StartSession
    else
      StopSession;
  end;
end;

procedure TAiShell.SetShellPath(const Value: string);
var
  WasRunning: Boolean;
begin
  // If the value is the same, do nothing
  if SameText(FShellPath, Value) then
    Exit;

  // Save whether it was running to restore state
  WasRunning := Assigned(FSession);

  // 1. Kill the current session (because it has the wrong executable)
  StopSession;

  // 2. Update the path
  FShellPath := Value;

  // 3. If it was running (or Active was True), restart with the new executable
  if WasRunning or FActive then
  begin
    StartSession;
  end;
end;

procedure TAiShell.SetEnvironment(const Value: TStringList);
begin
  FEnvironment.Assign(Value);
end;

procedure TAiShell.SetSecurityList(const Value: TStringList);
begin
  FSecurityList.Assign(Value);
end;

function TAiShell.CheckSecurity(const ACommand, ACallId: string): string;
var
  FirstWord: string;
  SpacePos: Integer;
  IsInList: Boolean;
  I: Integer;
begin
  Result := '';
  if FSecurityMode = ssmNone then
    Exit;

  // Extract the first token of the command (executable name)
  FirstWord := Trim(LowerCase(ACommand));
  SpacePos := Pos(' ', FirstWord);
  if SpacePos > 0 then
    FirstWord := Copy(FirstWord, 1, SpacePos - 1);

  // Check if the first token is in the list
  IsInList := False;
  for I := 0 to FSecurityList.Count - 1 do
  begin
    if SameText(FirstWord, Trim(FSecurityList[I])) then
    begin
      IsInList := True;
      Break;
    end;
  end;

  case FSecurityMode of
    ssmBlockList:
      if IsInList then
        Result := Format('Security violation: command "%s" is blocked.', [FirstWord]);
    ssmAllowList:
      if not IsInList then
        Result := Format('Security violation: command "%s" is not in the allowed list.', [FirstWord]);
  end;

  if (Result <> '') and Assigned(FOnSecurityViolation) then
    FOnSecurityViolation(Self, ACommand, ACallId, Result);
end;

procedure TAiShell.StartSession;
begin
  if Assigned(FSession) then
  begin
    if FSession.IsRunning then
      Exit;
    // Dead session: clean up before recreating
    StopSession;
  end;
  if Trim(FShellPath) = '' then
    raise Exception.Create('ShellPath cannot be empty.');
  FSession := TUtilsSystem.StartInteractiveProcess(FShellPath, '', FEnvironment);
end;

procedure TAiShell.StopSession;
begin
  if Assigned(FSession) then
  begin
    TUtilsSystem.StopInteractiveProcess(FSession);
    FSession := nil;
  end;
end;

procedure TAiShell.Restart;
begin
  StopSession;
  if FActive then
    StartSession;
end;

function TAiShell.GenerateSentinel: string;
begin
  Result := 'MKAI_END_' + IntToHex(Random(MaxInt), 8);
end;

function TAiShell.CleanOutput(const RawOutput, Sentinel: string): string;
begin
  Result := StringReplace(RawOutput, Sentinel, '', [rfReplaceAll]);
  Result := Trim(Result);
end;

// =============================================================================
// EXECUTION CORE (Low Level)
// =============================================================================
function TAiShell.DecodeShellBytes(const ABuffer: TBytes; ACount: Integer): string;
{$IFDEF MSWINDOWS}
var
  LEnc: TEncoding;
{$ENDIF}
begin
  if ACount <= 0 then
    Exit('');

  // The shell does NOT always speak UTF-8. cmd.exe writes in the console's OEM
  // code page (cp850 on a Spanish Windows), and TEncoding.UTF8 VALIDATES what
  // it receives: when bytes are not valid UTF-8 it raises EEncodingError instead
  // of substituting the character. Result: TAiShell would blow up on the FIRST
  // command on any non-English Windows, because even the cmd banner carries
  // accented characters. In English it was not noticed because the output is
  // pure ASCII, and on Linux it also works because bash does emit UTF-8.
  try
    Result := TEncoding.UTF8.GetString(ABuffer, 0, ACount);
  except
    on EEncodingError do
    begin
{$IFDEF MSWINDOWS}
      LEnc := TEncoding.GetEncoding(GetOEMCP);
      try
        Result := LEnc.GetString(ABuffer, 0, ACount);
      finally
        LEnc.Free;
      end;
{$ELSE}
      Result := TEncoding.ANSI.GetString(ABuffer, 0, ACount);
{$ENDIF}
    end;
  end;
end;

function TAiShell.InternalExecuteCommand(const ACommand: string; TimeOutMs: Cardinal): TShellExecutionResult;
var
  FullCommand, Sentinel: string;
  Buffer: TBytes;
  BytesRead: Integer;
  OutputBuilder, ErrorBuilder: TStringBuilder;
  StopWatch: TStopwatch;
  RawStr: string;

  InputBytes: TBytes;
  RawUtf8: UTF8String;

  IsLinuxStyle: Boolean;
begin
  Result.ExitCode := 0;
  Result.TimedOut := False;
  Result.StdOut := '';
  Result.StdErr := '';

  if not Assigned(FSession) or not FSession.IsRunning then
    StartSession;

  Sentinel := GenerateSentinel;
  OutputBuilder := TStringBuilder.Create;
  ErrorBuilder := TStringBuilder.Create;
  SetLength(Buffer, 4096);

  try
    // -------------------------------------------------------------------------
    // 1. DETERMINE SYNTAX ACCORDING TO THE SHELL (NOT ACCORDING TO THE OS)
    // -------------------------------------------------------------------------
    // If the executable contains 'wsl', 'bash', 'sh' or we are on POSIX, use Linux syntax.
    // If it is 'cmd.exe' or 'powershell', use Windows syntax.
    IsLinuxStyle := False;
{$IFDEF POSIX}
    IsLinuxStyle := True;
{$ENDIF}
    if ContainsText(ExtractFileName(FShellPath), 'wsl') or ContainsText(ExtractFileName(FShellPath), 'bash') or ContainsText(ExtractFileName(FShellPath), 'sh') then
    begin
      IsLinuxStyle := True;
    end;

    if IsLinuxStyle then
    begin
      // Linux syntax: ; for sequential (or &&), echo $? for exit code
      // Important: In WSL, the command must end with a Linux newline if possible,
      // but Delphi's StreamWriter handles it.
      FullCommand := ACommand + '; echo "EC:$? ' + Sentinel + '"' + #10;
    end
    else
    begin
      // Windows CMD syntax: & for sequential
      FullCommand := ACommand + sLineBreak + '@echo EC:%ERRORLEVEL% ' + Sentinel + sLineBreak;
    end;

    // -------------------------------------------------------------------------
    // 2. ENCODING CORRECTION (INPUT)
    // -------------------------------------------------------------------------
    RawUtf8 := UTF8String(FullCommand);
    SetLength(InputBytes, Length(RawUtf8));
    if Length(RawUtf8) > 0 then
      Move(RawUtf8[1], InputBytes[0], Length(RawUtf8));

    FSession.WriteInput(InputBytes[0], Length(InputBytes));

    // -------------------------------------------------------------------------
    // 3. READ LOOP
    // -------------------------------------------------------------------------
    StopWatch := TStopwatch.StartNew;

    while StopWatch.ElapsedMilliseconds < TimeOutMs do
    begin
      // Read STDOUT
      BytesRead := FSession.ReadOutput(Buffer[0], Length(Buffer));
      if BytesRead > 0 then
      begin
        RawStr := DecodeShellBytes(Buffer, BytesRead);

        OutputBuilder.Append(RawStr);

        if Pos(Sentinel, OutputBuilder.ToString) > 0 then
        begin
          // Drain STDERR before exiting. The sentinel travels via STDOUT, and a
          // command that only writes to STDERR (e.g. 'ls /no-existe') usually
          // delivers it at the same instant: if we left here without more, the
          // error pipe would NEVER be read and the error would be silently lost.
          repeat
            BytesRead := FSession.ReadError(Buffer[0], Length(Buffer));
            if BytesRead > 0 then
              ErrorBuilder.Append(DecodeShellBytes(Buffer, BytesRead));
          until BytesRead <= 0;

          // If the command failed and there is still nothing in STDERR, it may
          // arrive a few milliseconds after the sentinel: give it a short margin.
          // Only in that case, to avoid adding latency to commands that succeeded
          // (which are the majority).
          if (ErrorBuilder.Length = 0) and
             (not ContainsText(OutputBuilder.ToString, 'EC:0 ' + Sentinel)) then
          begin
            for var LWait := 1 to 5 do
            begin
              Sleep(15);
              repeat
                BytesRead := FSession.ReadError(Buffer[0], Length(Buffer));
                if BytesRead > 0 then
                  ErrorBuilder.Append(DecodeShellBytes(Buffer, BytesRead));
              until BytesRead <= 0;
              if ErrorBuilder.Length > 0 then
                Break;
            end;
          end;

          Break;
        end;

        StopWatch.Reset;
        StopWatch.Start;
      end;

      // Read STDERR
      BytesRead := FSession.ReadError(Buffer[0], Length(Buffer));
      if BytesRead > 0 then
      begin
        RawStr := DecodeShellBytes(Buffer, BytesRead);
        ErrorBuilder.Append(RawStr);
      end;

      Sleep(20);
    end;

    if StopWatch.ElapsedMilliseconds >= TimeOutMs then
    begin
      Result.TimedOut := True;
      // Restarting the session is mandatory, not optional: the command that
      // caused the timeout is STILL running and holds the pipe, so without this
      // all subsequent commands also time out and the session becomes unusable
      // for the rest of the process's life. Verified on Linux: after a
      // 'sleep 20' with TimeOut=3s, even an 'echo' returned timeout.
      // The price is losing the current directory and session variables,
      // which is much less harmful than a dead shell.
      Restart;
    end;

    // -------------------------------------------------------------------------
    // 4. OUTPUT PROCESSING
    // -------------------------------------------------------------------------
    Result.StdOut := CleanOutput(OutputBuilder.ToString, Sentinel);
    Result.StdErr := ErrorBuilder.ToString;

    // Capture Exit Code (Windows CMD and Linux/WSL)
    begin
      var
      OutStr := OutputBuilder.ToString;
      var
      P := Pos('EC:', OutStr);
      if P > 0 then
      begin
        var
        CodeStr := Copy(OutStr, P + 3, 5);
        var
        SpacePos := Pos(' ', CodeStr);
        if SpacePos > 0 then
        begin
          CodeStr := Copy(CodeStr, 1, SpacePos - 1);
          Result.ExitCode := StrToIntDef(CodeStr, 0);
          // Clean the ExitCode artifact from the visual output
          Result.StdOut := StringReplace(Result.StdOut, 'EC:' + CodeStr, '', []);
        end;
      end;
    end;

    if Result.StdOut.Length > FMaxOutputSize then
      Result.StdOut := Result.StdOut.Substring(0, FMaxOutputSize) + '... [Truncated]';

    if Assigned(FOnConsoleLog) then
      FOnConsoleLog(Self, ACommand, Result.StdOut, Result.StdErr, Result.ExitCode);

  finally
    OutputBuilder.Free;
    ErrorBuilder.Free;
  end;
end;

// =============================================================================
// MAIN DISPATCHER (Smart Detection)
// =============================================================================

function TAiShell.Execute(const CallId: string; const JsonArguments: string): string;
var
  JVal: TJSONValue;
  JArgs: TJSONObject;
begin
  JVal := TJSONObject.ParseJSONValue(JsonArguments);
  try
    if not (JVal is TJSONObject) then
      Exit('Error: Invalid JSON arguments.');

    JArgs := TJSONObject(JVal);
    Result := Execute(CallId, JArgs);
  finally
    JVal.Free;
  end;
end;

function TAiShell.Execute(const CallId: string; JArgs: TJSONObject): string;
begin
  // Format detection based on presence of key fields

  // CASE 1: OPENAI (Has 'commands' array)
  if JArgs.GetValue('commands') is TJSonArray then
  begin
    Result := ExecuteOpenAIAction(CallId, JArgs);
  end
  // CASE 2: CLAUDE (Has 'command' string and optional 'restart')
  else if (JArgs.GetValue('command') <> nil) or (JArgs.GetValue('restart') <> nil) then
  begin
    Result := ExecuteClaudeAction(CallId, JArgs);
  end
  // CASE 3: GENERIC (Fallback to single 'command' or 'cmd')
  else
  begin
    Result := ExecuteGenericAction(CallId, JArgs);
  end;
end;

// =============================================================================
// SPECIFIC IMPLEMENTATIONS
// =============================================================================

// --- CLAUDE ---
function TAiShell.ExecuteClaudeAction(const CallId: string; JArgs: TJSONObject): string;
var
  Cmd: string;
  ShouldRestart: Boolean;
  ExecRes: TShellExecutionResult;
  Handled: Boolean;
begin
  if JArgs.TryGetValue<Boolean>('restart', ShouldRestart) and ShouldRestart then
  begin
    Restart;
    Exit('Shell session restarted.');
  end;

  if not JArgs.TryGetValue<string>('command', Cmd) then
    Exit('Error: No command provided.');

  Result := CheckSecurity(Cmd, CallId);
  if Result <> '' then
    Exit;

  Handled := False;
  if Assigned(FOnCommand) then
    FOnCommand(Self, Cmd, CallId, ExecRes, Handled);

  if not Handled then
    ExecRes := InternalExecuteCommand(Cmd, FTimeOut);

  // Claude output format: Simple plain text
  if ExecRes.TimedOut then
    Result := 'Error: Command timed out.' + sLineBreak + ExecRes.StdOut
  else if ExecRes.StdErr <> '' then
    Result := ExecRes.StdOut + sLineBreak + 'STDERR: ' + ExecRes.StdErr
  else
  begin
    if ExecRes.StdOut = '' then
      Result := '[Command executed successfully]'
    else
      Result := ExecRes.StdOut;
  end;
end;

// --- OPENAI (GPT-5.1 Shell Tool) ---
function TAiShell.ExecuteOpenAIAction(const CallId: string; JArgs: TJSONObject): string;
var
  CommandsArray: TJSonArray;
  OutputObj, ItemOut, OutcomeObj: TJSONObject;
  OutputArray: TJSonArray;
  CmdVal: TJSONValue;
  Cmd: string;
  ExecRes: TShellExecutionResult;
  LocalTimeOut: Cardinal;
  ReqMaxOutput: Integer;
  Handled: Boolean;
  jVal: TJSONValue;
begin
  // Build the complex output object
  OutputObj := TJSONObject.Create;
  try
    OutputObj.AddPair('type', 'shell_call_output');
    OutputObj.AddPair('call_id', CallId);

    // 3. Check that it exists and is NOT TJSONNull

    LocalTimeOut := Self.FTimeOut;

    If JArgs.TryGetValue('timeout_ms', jVal) then
    Begin
      if Assigned(jVal) and not(jVal is TJSONNull) then
      begin
        // Try to convert only if it is a valid value
        if not jVal.TryGetValue<Cardinal>(LocalTimeOut) then
          LocalTimeOut := FTimeOut; // Fallback if conversion fails
      end;
    End;

    if JArgs.TryGetValue<Integer>('max_output_length', ReqMaxOutput) then
      OutputObj.AddPair('max_output_length', TJSONNumber.Create(ReqMaxOutput));

    OutputArray := TJSonArray.Create;
    OutputObj.AddPair('output', OutputArray);

    if JArgs.TryGetValue<TJSonArray>('commands', CommandsArray) then
    begin
      for CmdVal in CommandsArray do
      begin
        Cmd := CmdVal.Value;
        ItemOut := TJSONObject.Create;

        var LSecurityError := CheckSecurity(Cmd, CallId);
        if LSecurityError <> '' then
        begin
          ExecRes.StdOut := '';
          ExecRes.StdErr := LSecurityError;
          ExecRes.ExitCode := 1;
          ExecRes.TimedOut := False;
        end
        else
        begin
          Handled := False;
          if Assigned(FOnCommand) then
            FOnCommand(Self, Cmd, CallId, ExecRes, Handled);
          if not Handled then
            ExecRes := InternalExecuteCommand(Cmd, LocalTimeOut);
        end;

        // OpenAI-specific structure
        ItemOut.AddPair('stdout', ExecRes.StdOut);
        ItemOut.AddPair('stderr', ExecRes.StdErr);

        OutcomeObj := TJSONObject.Create;
        if ExecRes.TimedOut then
          OutcomeObj.AddPair('type', 'timeout')
        else
        begin
          OutcomeObj.AddPair('type', 'exit');
          OutcomeObj.AddPair('exit_code', TJSONNumber.Create(ExecRes.ExitCode));
        end;
        ItemOut.AddPair('outcome', OutcomeObj);

        OutputArray.Add(ItemOut);
      end;
    end;

    // Return JSON Stringified (OpenAI Chat Component will parse it if needed, or send raw)
    Result := OutputObj.ToJSON;
  finally
    OutputObj.Free;
  end;
end;

// --- GENERIC / FALLBACK ---
function TAiShell.ExecuteGenericAction(const CallId: string; JArgs: TJSONObject): string;
var
  Cmd: string;
  ExecRes: TShellExecutionResult;
  Handled: Boolean;
begin
  // Tries to find 'cmd' or 'command'
  if not JArgs.TryGetValue<string>('command', Cmd) then
    if not JArgs.TryGetValue<string>('cmd', Cmd) then
      Exit('Error: Unknown command format.');

  Result := CheckSecurity(Cmd, CallId);
  if Result <> '' then
    Exit;

  Handled := False;
  if Assigned(FOnCommand) then
    FOnCommand(Self, Cmd, CallId, ExecRes, Handled);

  if not Handled then
    ExecRes := InternalExecuteCommand(Cmd, FTimeOut);

  // Returns plain text by default
  if ExecRes.StdErr <> '' then
    Result := 'STDOUT: ' + ExecRes.StdOut + sLineBreak + 'STDERR: ' + ExecRes.StdErr
  else
    Result := ExecRes.StdOut;
end;

function TAiShell.ExecuteManual(const Command: string): string;
var
  ExecRes: TShellExecutionResult;
begin
  // 1. Ensure the session is alive
  if not Active then
    Active := True;

  // 2. Execute directly (skipping OnCommand security interception)
  // Uses the same TimeOut configured in the component
  ExecRes := InternalExecuteCommand(Command, FTimeOut);

  // 3. Format the result to return as a string
  // (Although the UI will update automatically via OnConsoleLog)
  if ExecRes.TimedOut then
    Result := 'Error: Command timed out.' + sLineBreak + ExecRes.StdOut
  else if ExecRes.StdErr <> '' then
    Result := ExecRes.StdOut + sLineBreak + 'STDERR: ' + ExecRes.StdErr
  else
    Result := ExecRes.StdOut;
end;

//
// function TAiShell.GetToolDefinition: string;
// begin
// case FToolMode of
// tmClaudeNative:
// Result := Format('{"type": "%s", "name": "bash"}', [FClaudeToolVersion]);
// tmOpenAINative:
// Result := '{"type": "shell"}';
// tmStandard:
// Result := '{ "type": "function", "function": { "name": "bash", "description": "Execute shell commands", "parameters": { "type": "object", "properties": { "command": { "type": "string" } }, "required": ["command"] } } }';
// end;
// end;

// =============================================================================
// REGISTRATION IN TAiFunctions
// =============================================================================

procedure TAiShell.OnFunctionAction(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  // Activate session if not active
  if not Active then
    Active := True;
  try
    ToolCall.Response := Execute(ToolCall.Id, ToolCall.Arguments);
  except
    on E: Exception do
      ToolCall.Response := 'Shell error: ' + E.ClassName + ': ' + E.Message;
  end;
  Handled := True;
end;

procedure TAiShell.RegisterInFunctions(AFunctions: TAiFunctions;
  const AFunctionName: string = 'bash');
var
  LFunc: TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  if not Assigned(AFunctions) then
    Exit;

  // Avoid duplicates
  if AFunctions.Functions.IndexOf(AFunctionName) >= 0 then
    Exit;

  LFunc := AFunctions.Functions.AddFunction(AFunctionName, True, OnFunctionAction);
  LFunc.Description.Text :=
    'Execute a shell command in a persistent session and return its output. ' +
    'The session preserves state between calls (working directory, environment variables). ' +
    'Use this to run system commands, scripts, file operations, or any shell instruction.';

  LParam := LFunc.Parameters.Add;
  LParam.Name := 'command';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam.Description.Text := 'The shell command to execute';
end;

end.
