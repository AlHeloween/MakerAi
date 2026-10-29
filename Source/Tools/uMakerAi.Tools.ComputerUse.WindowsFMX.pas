unit uMakerAi.Tools.ComputerUse.WindowsFMX;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.UITypes, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  FMX.Graphics, FMX.Surfaces, FMX.Types,
  uMakerAi.Tools.ComputerUse, uMakerAi.Core, uMakerAi.Utils.ScreenCapture;

type
  TAiWindowsFMXExecutor = class
  private
    // Input Methods (pure Win32 API)
    class procedure SendMouseInput(Flags: DWORD; Data: DWORD = 0);
    class procedure SendKeyboardInput(VK: Word; Up: Boolean);
    class procedure SendUnicodeChar(C: Char);
    class function GetVirtualKey(const KeyName: string): Word;
    class procedure ParseAndExecuteCombo(const Combo: string);
    class procedure SmoothMouseMove(DestX, DestY: Integer);
    class function ModifiersDown(const Mods: string): TArray<Word>;
    class procedure ModifiersUp(const Keys: TArray<Word>);

    // Helper to draw a simulated cursor over the FMX Bitmap
    // (Since plain BitBlt capture does not include the floating cursor)
    class procedure DrawCursorOnBitmap(Bmp: FMX.Graphics.TBitmap; AreaLeft, AreaTop: Integer);
  public
    // Executes the physical action
    class function Execute(const Action: TAiActionData): TAiActionResult;

    // Captures screen by delegating to uMakerAi.Utils.ScreenCapture
    class procedure CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect; Quality: Integer = 70);
  end;

implementation

{ TAiWindowsFMXExecutor }

// =============================================================================
// INPUT SECTION (Identical to previous - Interacts with Kernel)
// =============================================================================

class procedure TAiWindowsFMXExecutor.SendMouseInput(Flags: DWORD; Data: DWORD);
var
  Input: TInput;
begin
  ZeroMemory(@Input, SizeOf(Input));
  Input.Itype := INPUT_MOUSE;
  Input.mi.dwFlags := Flags;
  Input.mi.mouseData := Data;
  SendInput(1, Input, SizeOf(TInput));
end;

class procedure TAiWindowsFMXExecutor.SendKeyboardInput(VK: Word; Up: Boolean);
var
  Input: TInput;
begin
  ZeroMemory(@Input, SizeOf(Input));
  Input.Itype := INPUT_KEYBOARD;
  Input.ki.wVk := VK;
  if Up then
    Input.ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(1, Input, SizeOf(TInput));
end;

class procedure TAiWindowsFMXExecutor.SendUnicodeChar(C: Char);
var
  Input: TInput;
begin
  ZeroMemory(@Input, SizeOf(Input));
  Input.Itype := INPUT_KEYBOARD;
  Input.ki.wScan := Ord(C);
  Input.ki.dwFlags := KEYEVENTF_UNICODE;
  SendInput(1, Input, SizeOf(TInput));

  Input.ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
  SendInput(1, Input, SizeOf(TInput));
end;

class procedure TAiWindowsFMXExecutor.SmoothMouseMove(DestX, DestY: Integer);
begin
  // SetCursorPos handles virtual coordinates automatically on modern Windows
  SetCursorPos(DestX, DestY);
end;

class function TAiWindowsFMXExecutor.GetVirtualKey(const KeyName: string): Word;
var
  K: string;
begin
  K := LowerCase(Trim(KeyName));
  if K = 'enter' then Result := VK_RETURN
  else if K = 'tab' then Result := VK_TAB
  else if (K = 'ctrl') or (K = 'control') then Result := VK_CONTROL
  else if (K = 'alt') then Result := VK_MENU
  else if (K = 'shift') then Result := VK_SHIFT
  else if (K = 'esc') or (K = 'escape') then Result := VK_ESCAPE
  else if (K = 'space') then Result := VK_SPACE
  else if (K = 'backspace') then Result := VK_BACK
  else if (K = 'delete') then Result := VK_DELETE
  else if (K = 'win') or (K = 'windows') or (K = 'meta') or (K = 'super') then Result := VK_LWIN
  else if (Length(K) = 1) and (K[1] >= 'a') and (K[1] <= 'z') then
    Result := Ord(UpCase(K[1]))
  else if (Length(K) >= 2) and (K[1] = 'f') then
    Result := VK_F1 + StrToIntDef(Copy(K, 2, 2), 1) - 1
  else
    Result := 0;
end;

class procedure TAiWindowsFMXExecutor.ParseAndExecuteCombo(const Combo: string);
var
  Parts: TArray<string>;
  Part: string;
  Keys: TList<Word>;
  VK: Word;
  I: Integer;
begin
  Parts := Combo.Replace('-', '+').Split(['+']);
  Keys := TList<Word>.Create;
  try
    for Part in Parts do
    begin
      VK := GetVirtualKey(Part);
      if VK <> 0 then
      begin
        SendKeyboardInput(VK, False);
        Keys.Add(VK);
      end;
    end;
    Sleep(50);
    for I := Keys.Count - 1 downto 0 do
      SendKeyboardInput(Keys[I], True);
  finally
    Keys.Free;
  end;
end;

class function TAiWindowsFMXExecutor.ModifiersDown(const Mods: string): TArray<Word>;
var
  Parts: TArray<string>;
  Part: string;
  VK: Word;
  L: TList<Word>;
begin
  L := TList<Word>.Create;
  try
    if Trim(Mods) <> '' then
    begin
      Parts := Mods.Replace('-', '+').Split(['+']);
      for Part in Parts do
      begin
        VK := GetVirtualKey(Part);
        if VK <> 0 then
        begin
          SendKeyboardInput(VK, False);
          L.Add(VK);
        end;
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

class procedure TAiWindowsFMXExecutor.ModifiersUp(const Keys: TArray<Word>);
var
  I: Integer;
begin
  for I := High(Keys) downto Low(Keys) do
    SendKeyboardInput(Keys[I], True);
end;

class function TAiWindowsFMXExecutor.Execute(const Action: TAiActionData): TAiActionResult;
var
  I: Integer;
  Mods: TArray<Word>;
  Pt: TPoint;
begin
  Result.Success := True;
  Result.ErrorMessage := '';
  Result.CustomOutput := '';

  try
    case Action.ActionType of
      catHover: SmoothMouseMove(Action.X, Action.Y);

      catClick: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        ModifiersUp(Mods);
      end;

      catRightClick: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_RIGHTDOWN);
        SendMouseInput(MOUSEEVENTF_RIGHTUP);
        ModifiersUp(Mods);
      end;

      catMiddleClick: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_MIDDLEDOWN);
        SendMouseInput(MOUSEEVENTF_MIDDLEUP);
        ModifiersUp(Mods);
      end;

      catDoubleClick: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        Sleep(100);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        ModifiersUp(Mods);
      end;

      catTripleClick: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        for I := 1 to 3 do
        begin
          SendMouseInput(MOUSEEVENTF_LEFTDOWN);
          SendMouseInput(MOUSEEVENTF_LEFTUP);
          if I < 3 then
            Sleep(80);
        end;
        ModifiersUp(Mods);
      end;

      catDrag: begin
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        Sleep(100);
        SmoothMouseMove((Action.X + Action.DestX) div 2, (Action.Y + Action.DestY) div 2);
        Sleep(50);
        SmoothMouseMove(Action.DestX, Action.DestY);
        Sleep(100);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
      end;

      catScroll: begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        if (Action.ScrollDirection = 'down') then
          SendMouseInput(MOUSEEVENTF_WHEEL, DWORD(-Action.ScrollAmount))
        else if (Action.ScrollDirection = 'up') then
          SendMouseInput(MOUSEEVENTF_WHEEL, DWORD(Action.ScrollAmount))
        else if (Action.ScrollDirection = 'left') then
          SendMouseInput(MOUSEEVENTF_HWHEEL, DWORD(-Action.ScrollAmount))
        else if (Action.ScrollDirection = 'right') then
          SendMouseInput(MOUSEEVENTF_HWHEEL, DWORD(Action.ScrollAmount));
        ModifiersUp(Mods);
      end;

      catCursorPosition: begin
        GetCursorPos(Pt);
        Result.CustomOutput := Format('{"x":%d,"y":%d}', [Pt.X, Pt.Y]);
      end;

      catZoom: begin
        // No physical input: the region (CurrentAction.ZoomRect) is captured
        // enlarged in the OnRequestScreenshot handler.
      end;

      catType: begin
        // Pre-click only if position provided (Gemini). Claude 'type' arrives (0,0) and should NOT
        // click: it would remove focus from the control where we need to type.
        if (Action.X <> 0) or (Action.Y <> 0) then
        begin
          SmoothMouseMove(Action.X, Action.Y);
          SendMouseInput(MOUSEEVENTF_LEFTDOWN);
          SendMouseInput(MOUSEEVENTF_LEFTUP);
          Sleep(50);
        end;
        for I := 1 to Length(Action.TextToType) do
          SendUnicodeChar(Action.TextToType[I]);
        if Action.PressEnter then
        begin
          Sleep(50);
          SendKeyboardInput(VK_RETURN, False);
          SendKeyboardInput(VK_RETURN, True);
        end;
      end;

      catKeyCombination: ParseAndExecuteCombo(Action.KeyCombo);

      catHoldKey: begin
        Mods := ModifiersDown(Action.KeyCombo);
        if Action.HoldDuration > 0 then
          Sleep(Round(Action.HoldDuration * 1000))
        else
          Sleep(1000);
        ModifiersUp(Mods);
      end;

      catWait: Sleep(5000);
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

// =============================================================================
// CAPTURE SECTION (Integration with uMakerAi.Utils.ScreenCapture)
// =============================================================================

class procedure TAiWindowsFMXExecutor.DrawCursorOnBitmap(Bmp: FMX.Graphics.TBitmap; AreaLeft, AreaTop: Integer);
var
  CursorPos: TPoint;
  RelX, RelY: Single;
  R: TRectF;
begin
  // Get global mouse position
  if not GetCursorPos(CursorPos) then Exit;

  // Calculate relative position to the captured area
  RelX := CursorPos.X - AreaLeft;
  RelY := CursorPos.Y - AreaTop;

  // If the cursor is outside the image, we draw nothing
  if (RelX < 0) or (RelY < 0) or (RelX >= Bmp.Width) or (RelY >= Bmp.Height) then
    Exit;

  // Draw a visual indicator (Red circle with white border)
  // This is easier in FMX than converting HICONs and is sufficient for the AI.
  if Bmp.Canvas.BeginScene then
  try
    R := TRectF.Create(RelX - 10, RelY - 10, RelX + 10, RelY + 10);

    // Semi-transparent Red fill
    Bmp.Canvas.Fill.Color := $80FF0000; // Alpha=128, Red
    Bmp.Canvas.FillEllipse(R, 1);

    // Solid White border for contrast
    Bmp.Canvas.Stroke.Color := TAlphaColors.White;
    Bmp.Canvas.Stroke.Thickness := 2;
    Bmp.Canvas.DrawEllipse(R, 1);
  finally
    Bmp.Canvas.EndScene;
  end;
end;

class procedure TAiWindowsFMXExecutor.CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect; Quality: Integer);
var
  Bmp: FMX.Graphics.TBitmap;
  Surf: TBitmapSurface;
  SaveParams: TBitmapCodecSaveParams;
  Stream: TMemoryStream;
  VirtualLeft, VirtualTop: Integer;
begin
  if not Assigned(MediaFile) then
    MediaFile := TAiMediaFile.Create;

  // 1. Validate the area
  if TargetArea.IsEmpty then
  begin
    VirtualLeft := GetSystemMetrics(SM_XVIRTUALSCREEN);
    VirtualTop := GetSystemMetrics(SM_YVIRTUALSCREEN);
    // If empty, we capture the entire virtual screen
    // (It is still recommended that the TAiComputerUseTool component passes an explicit area)
    TargetArea := Rect(
      VirtualLeft,
      VirtualTop,
      VirtualLeft + GetSystemMetrics(SM_CXVIRTUALSCREEN),
      VirtualTop + GetSystemMetrics(SM_CYVIRTUALSCREEN)
    );
  end;

  // 2. Use your existing library for pixel capture
  Bmp := TScreenCapture.CaptureArea(TargetArea);
  if not Assigned(Bmp) then Exit;

  try
    // 3. Draw the cursor onto the captured Bitmap
    // It is vital so that Gemini knows where the mouse is
    DrawCursorOnBitmap(Bmp, TargetArea.Left, TargetArea.Top);

    // 4. Save as compressed JPG
    Surf := TBitmapSurface.Create;
    try
      Surf.Assign(Bmp);

      Stream := TMemoryStream.Create;
      try
        SaveParams.Quality := Quality;

        if TBitmapCodecManager.SaveToStream(Stream, Surf, '.jpg', @SaveParams) then
        begin
          Stream.Position := 0;
          MediaFile.LoadFromStream('screenshot.jpg', Stream);
        end;
      finally
        Stream.Free;
      end;
    finally
      Surf.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

end.
