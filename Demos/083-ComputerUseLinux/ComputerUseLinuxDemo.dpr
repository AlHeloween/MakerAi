program ComputerUseLinuxDemo;

{
  Demo 083 - Computer Use on Linux (X11).

  Runs a real agentic Computer Use cycle on an X screen: the model
  requests screenshots, clicks and types, and the demo returns the new state.

  It is the same subsystem as demo 066 on Windows; the only thing that changes are the
  two handlers of TAiComputerUseTool, which here point to TAiLinuxExecutor
  (xdotool + scrot) instead of the Win32 executor.

  INTENDED FOR A VIRTUAL SCREEN (Xvfb). This is how a broker runs on a
  headless VPS, and it also avoids the risk of 066: there the capture is the
  user's REAL desktop and is sent entirely to the provider. Here only what is
  inside the virtual display is seen.

    sudo apt-get install -y xvfb xdotool scrot x11-apps
    Xvfb :99 -screen 0 1280x800x24 &
    DISPLAY=:99 xedit /tmp/prueba.txt &
    DISPLAY=:99 ./ComputerUseLinuxDemo

  If it points to a display with a physical screen (:0), the entire desktop is captured
  and sent to the provider. Check what is on screen BEFORE.
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Tools.Functions,
  uMakerAi.Tools.ComputerUse,
{$IFDEF LINUX}
  uMakerAi.Tools.ComputerUse.Linux,
{$ENDIF}
  uMakerAi.ParamsRegistry,
  uMakerAi.Chat.Initializations;

{$IFDEF LINUX}

const
  CDefaultPrompt =
    'You are a desktop automation agent. ' +
    'Task: take a screenshot, locate the text area of the editor on ' +
    'screen, click on it and type exactly: ' +
    '"Hello MakerAI from Linux". Then take another screenshot to confirm and ' +
    'describe briefly what you see.';

type
  THandlers = class
  public
    ShotDir: string;
    ShotCount: Integer;
    Actions: Integer;
    procedure ExecuteAction(Sender: TObject; const ActionData: TAiActionData;
      var Result: TAiActionResult);
    procedure RequestShot(Sender: TObject; var MediaFile: TAiMediaFile);
    procedure RawToolCall(Sender: TObject; AiToolCall: TAiToolsFunction);
  end;

procedure Log(const S: string);
begin
  WriteLn(FormatDateTime('hh:nn:ss  ', Now), S);
end;

procedure THandlers.ExecuteAction(Sender: TObject; const ActionData: TAiActionData;
  var Result: TAiActionResult);
begin
  Inc(Actions);
  Log(Format('ACTION %-18s x=%d y=%d dest=%d,%d scroll=%s/%d combo="%s" text="%s"',
    [ActionData.FunctionName, ActionData.X, ActionData.Y,
     ActionData.DestX, ActionData.DestY,
     ActionData.ScrollDirection, ActionData.ScrollAmount, ActionData.KeyCombo,
     Copy(ActionData.TextToType, 1, 40)]));

  Result := TAiLinuxExecutor.Execute(ActionData);

  if not Result.Success then
    Log('   -> FAILED: ' + Result.ErrorMessage)
  else if Result.CustomOutput <> '' then
    Log('   -> ' + StringReplace(Result.CustomOutput, sLineBreak, ' ', [rfReplaceAll]));
end;

procedure THandlers.RawToolCall(Sender: TObject; AiToolCall: TAiToolsFunction);
begin
  // Diagnostic only: the tool_call is logged EXACTLY as it arrives from the provider,
  // before TranslateXxxToolCall converts it to the canonical format. It is the only
  // way to see whether a missing coordinate was omitted by the model or lost by the
  // translation. Response is NOT touched: filling it would delegate the action and the driver
  // would not execute it locally (see demo 082).
  Log(Format('   RAW name=%s args=%s',
    [AiToolCall.Name, Copy(AiToolCall.Arguments, 1, 200)]));
end;

procedure THandlers.RequestShot(Sender: TObject; var MediaFile: TAiMediaFile);
var
  LTool: TAiComputerUseTool;
  LArea: TRect;
begin
  LTool := Sender as TAiComputerUseTool;
  LArea := TRect.Create(LTool.AreaLeft, LTool.AreaTop,
    LTool.AreaLeft + LTool.AreaWidth, LTool.AreaTop + LTool.AreaHeight);

  TAiLinuxExecutor.CaptureScreen(MediaFile, LArea);

  if Assigned(MediaFile) then
  begin
    Inc(ShotCount);
    // Debug copy: allows seeing exactly what was sent to the model.
    try
      MediaFile.SaveToFile(TPath.Combine(ShotDir,
        Format('shot_%.3d.png', [ShotCount])));
    except
    end;
    Log(Format('   -> screenshot %d (%d bytes)', [ShotCount, MediaFile.bytes]));
  end;
end;

function ArgValue(const AName, ADefault: string): string;
var
  I: Integer;
  S: string;
begin
  Result := ADefault;
  for I := 1 to ParamCount do
  begin
    S := ParamStr(I);
    if S.StartsWith(AName + '=') then
      Exit(S.Substring(Length(AName) + 1));
  end;
end;

function HasArg(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AName) then
      Exit(True);
end;

var
  LConn: TAiChatConnection;
  LTool: TAiComputerUseTool;
  LH: THandlers;
  LProvider, LPrompt, LDisplay, LMissing, LRes: string;
  LW, LH2: Integer;

begin
  try
    if HasArg('--help') or HasArg('-h') then
    begin
      WriteLn('Demo 083 - Computer Use on Linux');
      WriteLn('  --provider=openai|claude   (default: openai)');
      WriteLn('  --display=:99              (default: the DISPLAY of the environment)');
      WriteLn('  --width=1280 --height=800  (size of the X screen)');
      WriteLn('  --prompt=<text>');
      WriteLn('');
      WriteLn('Requires OPENAI_API_KEY or CLAUDE_API_KEY, and xdotool + scrot.');
      Halt(0);
    end;

    LProvider := LowerCase(ArgValue('--provider', 'openai'));
    LPrompt := ArgValue('--prompt', CDefaultPrompt);
    LDisplay := ArgValue('--display', '');
    LW := StrToIntDef(ArgValue('--width', '1280'), 1280);
    LH2 := StrToIntDef(ArgValue('--height', '800'), 800);

    if LDisplay <> '' then
      TAiLinuxExecutor.Display := LDisplay;

    if not TAiLinuxExecutor.ToolsAvailable(LMissing) then
    begin
      WriteLn('ERROR: missing ', LMissing, '. Install with:');
      WriteLn('  sudo apt-get install -y xdotool scrot');
      Halt(2);
    end;

    LH := THandlers.Create;
    LTool := TAiComputerUseTool.Create(nil);
    LConn := TAiChatConnection.Create(nil);
    try
      LH.ShotDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'shots');
      ForceDirectories(LH.ShotDir);

      // Captured area = entire X screen. Since it is <= 1280 wide, the
      // resolution DECLARED to the model matches the image and there is no need to
      // rescale: clicks land where the model thinks.
      LTool.AreaLeft := 0;
      LTool.AreaTop := 0;
      LTool.AreaWidth := LW;
      LTool.AreaHeight := LH2;
      LTool.ScreenWidth := LW;
      LTool.ScreenHeight := LH2;
      LTool.OnExecuteAction := LH.ExecuteAction;
      LTool.OnRequestScreenshot := LH.RequestShot;

      LConn.ChatTools.ComputerUseTool := LTool;
      LConn.OnCallToolFunction := LH.RawToolCall;

      if LProvider = 'claude' then
      begin
        LConn.DriverName := 'Claude';
        LConn.Model := 'claude-opus-4-8';
        LConn.Params.Values['ApiKey'] := '@CLAUDE_API_KEY';
        TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-4-8',
          'ModelCaps', '[cap_Image, cap_ComputerUse]');
        TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-4-8',
          'SessionCaps', '[cap_Image, cap_ComputerUse]');
      end
      else
      begin
        LConn.DriverName := 'OpenAi';
        LConn.Model := 'gpt-6-astra';
        LConn.Params.Values['ApiKey'] := '@OPENAI_API_KEY';
        TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra',
          'ModelCaps', '[cap_Image, cap_Reasoning, cap_ComputerUse]');
        TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra',
          'SessionCaps', '[cap_Image, cap_Reasoning, cap_ComputerUse]');
      end;

      LConn.Params.Values['Asynchronous'] := 'False';

      Log(Format('Provider: %s  Model: %s', [LConn.DriverName, LConn.Model]));
      Log(Format('X screen: %dx%d  DISPLAY=%s', [LW, LH2,
        IfThen(LDisplay <> '', LDisplay, GetEnvironmentVariable('DISPLAY'))]));
      Log('Screenshots in: ' + LH.ShotDir);
      Log('--- start ---');

      LRes := LConn.AddMessageAndRun(LPrompt, 'user', []);

      Log('--- end ---');
      if LConn.LastError <> '' then
        Log('LastError: ' + LConn.LastError);
      Log(Format('Actions executed: %d   Screenshots: %d',
        [LH.Actions, LH.ShotCount]));
      WriteLn;
      WriteLn('Model response:');
      WriteLn(LRes);

      if (LH.Actions = 0) then
      begin
        WriteLn;
        WriteLn('WARNING: the model did not use the tool in this turn.');
        Halt(3);
      end;
    finally
      LConn.Free;
      LTool.Free;
      LH.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.

{$ELSE}

begin
  WriteLn('Demo 083 only runs on Linux: it uses xdotool and scrot on X11.');
  WriteLn('It compiles on Windows on purpose, so as not to break the group project.');
end.

{$ENDIF}
