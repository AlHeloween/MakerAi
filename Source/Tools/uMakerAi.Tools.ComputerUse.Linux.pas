unit uMakerAi.Tools.ComputerUse.Linux;

// =============================================================================
//  Computer Use Executor for Linux (X11).
//
//  - Input (mouse / keyboard / scroll) delegated to xdotool.
//  - Screenshot capture delegated to scrot.
//
//  Why via shell and not with libX11/XTest directly: the executor consists of two
//  handlers (OnExecuteAction / OnRequestScreenshot), so changing the engine
//  later does not affect anything else in the framework. This version starts working with
//  two apt packages; a variant using libX11+XTest via dlopen (without
//  external binaries, pattern of TOpenSSLTransport) can replace it without the
//  application noticing.
//
//  DEPENDENCIES ON THE TARGET MACHINE:
//    sudo apt-get install -y xdotool scrot
//    # and, if there is no physical screen (VPS headless):
//    sudo apt-get install -y xvfb
//    Xvfb :99 -screen 0 1280x800x24 &
//    export DISPLAY=:99
//
//  DISPLAY: by default it is inherited from the process. If the application runs as
//  a service and does not have it in the environment, set TAiLinuxExecutor.Display.
//
//  KNOWN LIMITATIONS:
//   * X11 only. Under native Wayland, xdotool does not control windows;
//     XWayland is needed (and even then it only reaches X clients).
//   * catNavigate uses xdg-open, so it needs a browser installed and a
//     registered handler. On a bare Xvfb there is none.
//   * Without a window manager (typical case of Xvfb) there is no focus by clicking on the
//     frame nor window activation: apps receive focus by pointer.
//     If desktop behavior is needed, start a lightweight WM.
//
//  The public interface (Execute / CaptureScreen) is identical to that of the
//  Windows and macOS executors, so the handler is interchangeable per
//  platform without touching the application.
// =============================================================================

interface

{$IFDEF LINUX}

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.StrUtils,
  System.IOUtils,
  uMakerAi.Tools.ComputerUse, uMakerAi.Core;

type
  TAiLinuxExecutor = class
  private
    class var FDisplay: string;
    // Executes a command and returns the exit code.
    class function Sh(const ACmd: string): Integer;
    // Executes a command and returns its standard output.
    class function ShOut(const ACmd: string): string;
    // Wraps the command with DISPLAY=... if explicitly set.
    class function WithDisplay(const ACmd: string): string;
    // Escapes an argument for the shell (single quotes).
    class function Q(const S: string): string;
    // Translates a key name to the keysym understood by xdotool.
    class function MapKey(const AName: string): string;
    // 'CTRL+A' -> 'ctrl+a'; also works for a single key.
    class function MapCombo(const ACombo: string): string;
    // X11 scroll buttons: 4 up, 5 down, 6 left, 7 right.
    class function ScrollButton(const ADirection: string): Integer;
  public
    // If left empty, the DISPLAY from the process environment is used.
    class property Display: string read FDisplay write FDisplay;

    class function Execute(const Action: TAiActionData): TAiActionResult;
    class procedure CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect;
      Quality: Integer = 70);

    // True if xdotool and scrot are available. It is advisable to call it at startup
    // to give a clear message instead of failing action by action.
    class function ToolsAvailable(out AMissing: string): Boolean;
  end;

{$ENDIF}

implementation

{$IFDEF LINUX}

uses
  Posix.Stdlib;

{ TAiLinuxExecutor }

class function TAiLinuxExecutor.Sh(const ACmd: string): Integer;
var
  M: TMarshaller;
begin
  Result := _system(M.AsAnsi(ACmd).ToPointer);
end;

class function TAiLinuxExecutor.ShOut(const ACmd: string): string;
var
  LTmp: string;
begin
  Result := '';
  LTmp := TPath.GetTempFileName;
  try
    Sh(ACmd + ' > ' + Q(LTmp) + ' 2>/dev/null');
    if TFile.Exists(LTmp) then
      Result := TFile.ReadAllText(LTmp);
  finally
    try
      TFile.Delete(LTmp);
    except
    end;
  end;
end;

class function TAiLinuxExecutor.WithDisplay(const ACmd: string): string;
begin
  if FDisplay <> '' then
    Result := 'DISPLAY=' + Q(FDisplay) + ' ' + ACmd
  else
    Result := ACmd;
end;

class function TAiLinuxExecutor.Q(const S: string): string;
begin
  // Single quotes: nothing is interpreted inside. A single quote in the text is
  // closed, escaped and reopened ('\'' is the usual idiom).
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

class function TAiLinuxExecutor.MapKey(const AName: string): string;
var
  LK: string;
  LFn: Integer;
begin
  LK := LowerCase(Trim(AName));

  if (LK = 'ctrl') or (LK = 'control') or (LK = 'ctl') then Exit('ctrl');
  if (LK = 'alt') or (LK = 'option') then Exit('alt');
  if LK = 'shift' then Exit('shift');
  if (LK = 'cmd') or (LK = 'command') or (LK = 'win') or (LK = 'super') or (LK = 'meta') then Exit('super');

  if (LK = 'enter') or (LK = 'return') then Exit('Return');
  if (LK = 'esc') or (LK = 'escape') then Exit('Escape');
  if LK = 'tab' then Exit('Tab');
  if (LK = 'backspace') or (LK = 'back') then Exit('BackSpace');
  if (LK = 'delete') or (LK = 'del') then Exit('Delete');
  if LK = 'insert' then Exit('Insert');
  if LK = 'space' then Exit('space');
  if LK = 'up' then Exit('Up');
  if LK = 'down' then Exit('Down');
  if LK = 'left' then Exit('Left');
  if LK = 'right' then Exit('Right');
  if LK = 'home' then Exit('Home');
  if LK = 'end' then Exit('End');
  if (LK = 'pageup') or (LK = 'page_up') or (LK = 'pgup') then Exit('Page_Up');
  if (LK = 'pagedown') or (LK = 'page_down') or (LK = 'pgdn') then Exit('Page_Down');

  // F1..F24
  if (Length(LK) >= 2) and (LK[1] = 'f') and
     TryStrToInt(Copy(LK, 2, MaxInt), LFn) and (LFn >= 1) and (LFn <= 24) then
    Exit('F' + IntToStr(LFn));

  Result := LK;
end;

class function TAiLinuxExecutor.MapCombo(const ACombo: string): string;
var
  LParts: TArray<string>;
  I: Integer;
begin
  Result := '';
  LParts := SplitString(ACombo, '+');
  for I := 0 to High(LParts) do
  begin
    if Trim(LParts[I]) = '' then
      Continue;
    if Result <> '' then
      Result := Result + '+';
    Result := Result + MapKey(LParts[I]);
  end;
end;

class function TAiLinuxExecutor.ScrollButton(const ADirection: string): Integer;
var
  LD: string;
begin
  LD := LowerCase(Trim(ADirection));
  if LD = 'up' then Result := 4
  else if LD = 'left' then Result := 6
  else if LD = 'right' then Result := 7
  else Result := 5; // down by default
end;

class function TAiLinuxExecutor.ToolsAvailable(out AMissing: string): Boolean;
begin
  AMissing := '';
  if Sh('command -v xdotool >/dev/null 2>&1') <> 0 then
    AMissing := 'xdotool';
  if Sh('command -v scrot >/dev/null 2>&1') <> 0 then
  begin
    if AMissing <> '' then
      AMissing := AMissing + ' and ';
    AMissing := AMissing + 'scrot';
  end;
  Result := AMissing = '';
end;

class function TAiLinuxExecutor.Execute(const Action: TAiActionData): TAiActionResult;
var
  LCmd, LMods, LKey: string;
  LBtn, LClicks, I: Integer;
  LModList: TArray<string>;
begin
  Result.Success := True;
  Result.ErrorMessage := '';
  Result.CustomOutput := '';

  try
    // Modifiers (click / scroll with shift, ctrl...): they are held pressed
    // around the action, same as in the Windows executor.
    LMods := '';
    if Trim(Action.Modifiers) <> '' then
    begin
      LModList := SplitString(Action.Modifiers, '+');
      for I := 0 to High(LModList) do
        if Trim(LModList[I]) <> '' then
        begin
          if LMods <> '' then
            LMods := LMods + ' ';
          LMods := LMods + MapKey(LModList[I]);
        end;
    end;

    if LMods <> '' then
      Sh(WithDisplay('xdotool keydown ' + LMods));
    try
      case Action.ActionType of

        catClick, catRightClick, catMiddleClick, catDoubleClick, catTripleClick:
          begin
            case Action.ActionType of
              catRightClick:  LBtn := 3;
              catMiddleClick: LBtn := 2;
            else
              LBtn := 1;
            end;
            case Action.ActionType of
              catDoubleClick: LClicks := 2;
              catTripleClick: LClicks := 3;
            else
              LClicks := 1;
            end;
            LCmd := Format('xdotool mousemove %d %d click --repeat %d --delay 60 %d',
              [Action.X, Action.Y, LClicks, LBtn]);
            Result.Success := Sh(WithDisplay(LCmd)) = 0;
          end;

        catHover:
          Result.Success := Sh(WithDisplay(Format('xdotool mousemove %d %d',
            [Action.X, Action.Y]))) = 0;

        catType:
          begin
            // Pre-click ONLY if position is given (Gemini 'type_text_at' brings it;
            // Claude's 'type' does not, and clicking at (0,0) would remove focus).
            // Identical to the Windows executor, including ClearBeforeTyping: there
            // it is also not applied, to avoid divergence between platforms.
            if (Action.X <> 0) or (Action.Y <> 0) then
            begin
              Sh(WithDisplay(Format('xdotool mousemove %d %d click 1',
                [Action.X, Action.Y])));
              Sleep(80);
            end;

            if Action.TextToType <> '' then
              Result.Success := Sh(WithDisplay('xdotool type --delay 12 -- ' +
                Q(Action.TextToType))) = 0;

            if Action.PressEnter then
            begin
              Sleep(50);
              Sh(WithDisplay('xdotool key Return'));
            end;
          end;

        catKeyCombination:
          begin
            LKey := MapCombo(Action.KeyCombo);
            if LKey = '' then
            begin
              Result.Success := False;
              Result.ErrorMessage := 'key_combination without keys';
            end
            else
              Result.Success := Sh(WithDisplay('xdotool key ' + Q(LKey))) = 0;
          end;

        catHoldKey:
          begin
            LKey := MapCombo(Action.KeyCombo);
            if LKey = '' then
            begin
              Result.Success := False;
              Result.ErrorMessage := 'hold_key without keys';
            end
            else
            begin
              Sh(WithDisplay('xdotool keydown ' + Q(LKey)));
              Sleep(Round(Max(0.1, Action.HoldDuration) * 1000));
              Result.Success := Sh(WithDisplay('xdotool keyup ' + Q(LKey))) = 0;
            end;
          end;

        catScroll:
          begin
            LBtn := ScrollButton(Action.ScrollDirection);
            // ScrollAmount comes in pixels (default 800). X11 only knows about
            // wheel "clicks", so it is approximated at ~100 px per click.
            LClicks := EnsureRange(Round(Max(1, Action.ScrollAmount) / 100), 1, 15);
            if (Action.X <> 0) or (Action.Y <> 0) then
              Sh(WithDisplay(Format('xdotool mousemove %d %d', [Action.X, Action.Y])));
            Result.Success := Sh(WithDisplay(Format('xdotool click --repeat %d --delay 30 %d',
              [LClicks, LBtn]))) = 0;
          end;

        catDrag:
          begin
            LCmd := Format('xdotool mousemove %d %d mousedown 1 mousemove %d %d',
              [Action.X, Action.Y, Action.DestX, Action.DestY]);
            Sh(WithDisplay(LCmd));
            Sleep(120); // give time for the app to process the drag
            Result.Success := Sh(WithDisplay('xdotool mouseup 1')) = 0;
          end;

        catCursorPosition:
          begin
            // Returns 'X=123 Y=456 SCREEN=0 WINDOW=...'
            Result.CustomOutput := Trim(ShOut(WithDisplay('xdotool getmouselocation --shell')));
            Result.Success := Result.CustomOutput <> '';
            if not Result.Success then
              Result.ErrorMessage := 'could not read cursor position';
          end;

        catNavigate:
          begin
            if Trim(Action.Url) = '' then
            begin
              Result.Success := False;
              Result.ErrorMessage := 'navigate without url';
            end
            else
            begin
              Result.Success := Sh(WithDisplay('xdg-open ' + Q(Action.Url) +
                ' >/dev/null 2>&1')) = 0;
              if not Result.Success then
                Result.ErrorMessage :=
                  'xdg-open failed: no browser installed or no handler registered';
              Sleep(1500); // margin for the browser to render something
            end;
          end;

        catGoBack:
          Result.Success := Sh(WithDisplay('xdotool key alt+Left')) = 0;

        catGoForward:
          Result.Success := Sh(WithDisplay('xdotool key alt+Right')) = 0;

        catWait:
          Sleep(5000);

        // They don't move anything: the capture is done later by OnRequestScreenshot, and the
        // zoom crop is read from CurrentAction.ZoomRect.
        catScreenshot, catZoom, catTerminate:
          Result.Success := True;

      else
        Result.Success := False;
        Result.ErrorMessage := 'Action not supported by TAiLinuxExecutor: ' +
          Action.FunctionName;
      end;
    finally
      if LMods <> '' then
        Sh(WithDisplay('xdotool keyup ' + LMods));
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

class procedure TAiLinuxExecutor.CaptureScreen(var MediaFile: TAiMediaFile;
  TargetArea: TRect; Quality: Integer);
var
  LTmp, LCmd: string;
  LW, LH: Integer;
begin
  LW := TargetArea.Width;
  LH := TargetArea.Height;

  LTmp := TPath.Combine(TPath.GetTempPath,
    'makerai_shot_' + FormatDateTime('hhnnsszzz', Now) + '.png');
  try
    if (LW > 0) and (LH > 0) then
      LCmd := Format('scrot -o -a %d,%d,%d,%d %s',
        [TargetArea.Left, TargetArea.Top, LW, LH, Q(LTmp)])
    else
      LCmd := 'scrot -o ' + Q(LTmp);

    if (Sh(WithDisplay(LCmd)) <> 0) or (not TFile.Exists(LTmp)) then
      raise Exception.Create('scrot could not capture the screen (check DISPLAY and that scrot is installed)');

    if not Assigned(MediaFile) then
      MediaFile := TAiMediaFile.Create;
    MediaFile.LoadFromfile(LTmp);
  finally
    try
      if TFile.Exists(LTmp) then
        TFile.Delete(LTmp);
    except
    end;
  end;
end;

{$ENDIF}

end.
