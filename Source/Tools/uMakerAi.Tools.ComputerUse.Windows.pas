unit uMakerAi.Tools.ComputerUse.Windows;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections,
  System.StrUtils, Vcl.Forms, Vcl.Graphics, System.Types,
  uMakerAi.Tools.ComputerUse, uMakerAi.Core;

type
  TAiWindowsExecutor = class
  private
    class procedure SendMouseInput(Flags: DWORD; Data: DWORD = 0);
    class procedure SendKeyboardInput(VK: Word; Up: Boolean);
    class procedure SendUnicodeChar(C: Char);
    class function GetVirtualKey(const KeyName: string): Word;
    class procedure ParseAndExecuteCombo(const Combo: string);
    class procedure SmoothMouseMove(DestX, DestY: Integer);
    // Presses the modifier keys and returns their VK codes to release them later.
    class function ModifiersDown(const Mods: string): TArray<Word>;
    class procedure ModifiersUp(const Keys: TArray<Word>);
  public
    // Executes the physical action based on the processed data
    class function Execute(const Action: TAiActionData): TAiActionResult;

    // Helper to capture the screen and return it as TAiMediaFile
    // Quality: 1-100 (JPG compression). Recommended: 60-75 for speed.
    class procedure CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect; Quality: Integer = 70);
  end;

implementation

uses
  System.IOUtils, Vcl.Imaging.jpeg, Vcl.Imaging.pngimage;

{ TAiWindowsExecutor }

// -----------------------------------------------------------------------------
// HELPER: SendInput Wrapper
// -----------------------------------------------------------------------------
class procedure TAiWindowsExecutor.SendMouseInput(Flags: DWORD; Data: DWORD);
var
  Input: TInput;
begin
  ZeroMemory(@Input, SizeOf(Input));
  Input.Itype := INPUT_MOUSE;
  Input.mi.dwFlags := Flags;
  Input.mi.mouseData := Data;
  SendInput(1, Input, SizeOf(TInput));
end;

class procedure TAiWindowsExecutor.SendKeyboardInput(VK: Word; Up: Boolean);
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

class procedure TAiWindowsExecutor.SendUnicodeChar(C: Char);
var
  Input: TInput;
begin
  ZeroMemory(@Input, SizeOf(Input));
  Input.Itype := INPUT_KEYBOARD;
  Input.ki.wScan := Ord(C);
  Input.ki.dwFlags := KEYEVENTF_UNICODE;
  SendInput(1, Input, SizeOf(TInput));

  // Release (necessary for some unicode inputs)
  Input.ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
  SendInput(1, Input, SizeOf(TInput));
end;

class procedure TAiWindowsExecutor.SmoothMouseMove(DestX, DestY: Integer);
begin
  // SetCursorPos is instant and is what Gemini generally expects.
  // If one wanted to simulate human movement, an interpolation algorithm would go here.
  SetCursorPos(DestX, DestY);
end;

// -----------------------------------------------------------------------------
// HELPER: Key Mapping
// -----------------------------------------------------------------------------
class function TAiWindowsExecutor.GetVirtualKey(const KeyName: string): Word;
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
  else if (K = 'up') then Result := VK_UP
  else if (K = 'down') then Result := VK_DOWN
  else if (K = 'left') then Result := VK_LEFT
  else if (K = 'right') then Result := VK_RIGHT
  else if (K = 'home') then Result := VK_HOME
  else if (K = 'end') then Result := VK_END
  else if (K = 'page_up') then Result := VK_PRIOR
  else if (K = 'page_down') then Result := VK_NEXT
  else if (K = 'win') or (K = 'windows') or (K = 'meta') or (K = 'super') then Result := VK_LWIN
  else if (Length(K) = 1) and (K[1] >= 'a') and (K[1] <= 'z') then
    Result := Ord(UpCase(K[1])) // A-Z
  else if (Length(K) >= 2) and (K[1] = 'f') then // F1-F12
    Result := VK_F1 + StrToIntDef(Copy(K, 2, 2), 1) - 1
  else
    Result := 0;
end;

class procedure TAiWindowsExecutor.ParseAndExecuteCombo(const Combo: string);
var
  Parts: TArray<string>;
  Part: string;
  Keys: TList<Word>;
  VK: Word;
  I: Integer;
begin
  // Example: "Control+Shift+S"
  // Replace common separators
  Parts := Combo.Replace('-', '+').Split(['+']);
  Keys := TList<Word>.Create;
  try
    // 1. Press Down Sequence
    for Part in Parts do
    begin
      VK := GetVirtualKey(Part);
      if VK <> 0 then
      begin
        SendKeyboardInput(VK, False); // Key Down
        Keys.Add(VK);
      end;
    end;

    // Small pause to ensure the app detects the combo
    Sleep(50);

    // 2. Release Sequence (Reverse Order)
    for I := Keys.Count - 1 downto 0 do
    begin
      SendKeyboardInput(Keys[I], True); // Key Up
    end;
  finally
    Keys.Free;
  end;
end;

class function TAiWindowsExecutor.ModifiersDown(const Mods: string): TArray<Word>;
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
          SendKeyboardInput(VK, False); // Key Down
          L.Add(VK);
        end;
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

class procedure TAiWindowsExecutor.ModifiersUp(const Keys: TArray<Word>);
var
  I: Integer;
begin
  for I := High(Keys) downto Low(Keys) do
    SendKeyboardInput(Keys[I], True); // Key Up (reverse order)
end;

// -----------------------------------------------------------------------------
// MAIN EXECUTION LOGIC
// -----------------------------------------------------------------------------
class function TAiWindowsExecutor.Execute(const Action: TAiActionData): TAiActionResult;
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
      // --- MOUSE ---
      catHover:
      begin
        SmoothMouseMove(Action.X, Action.Y);
      end;

      catClick:
      begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        ModifiersUp(Mods);
      end;

      catRightClick:
      begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_RIGHTDOWN);
        SendMouseInput(MOUSEEVENTF_RIGHTUP);
        ModifiersUp(Mods);
      end;

      catMiddleClick:
      begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_MIDDLEDOWN);
        SendMouseInput(MOUSEEVENTF_MIDDLEUP);
        ModifiersUp(Mods);
      end;

      catDoubleClick:
      begin
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        Sleep(100); // Typical pause for double click
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        SendMouseInput(MOUSEEVENTF_LEFTUP);
        ModifiersUp(Mods);
      end;

      catTripleClick:
      begin
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

      catDrag:
      begin
        SmoothMouseMove(Action.X, Action.Y);
        SendMouseInput(MOUSEEVENTF_LEFTDOWN);
        Sleep(100); // Pause to start drag

        // Simple interpolated movement so that the OS detects the drag
        // Move halfway
        SmoothMouseMove((Action.X + Action.DestX) div 2, (Action.Y + Action.DestY) div 2);
        Sleep(50);
        // Move to destination
        SmoothMouseMove(Action.DestX, Action.DestY);
        Sleep(100);

        SendMouseInput(MOUSEEVENTF_LEFTUP);
      end;

      catScroll:
      begin
        // Move mouse to position to ensure the scroll affects the correct window
        Mods := ModifiersDown(Action.Modifiers);
        SmoothMouseMove(Action.X, Action.Y);

        // Default magnitude in Gemini is 800 (WHEEL_DELTA is 120)
        // 800 normalized units ~ several wheel steps.

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

      catCursorPosition:
      begin
        GetCursorPos(Pt);
        Result.CustomOutput := Format('{"x":%d,"y":%d}', [Pt.X, Pt.Y]);
      end;

      catZoom:
      begin
        // No physical input required: the region (Action.ZoomRect) is captured zoomed
        // in the OnRequestScreenshot handler via CurrentAction.ZoomRect.
      end;

      // --- KEYBOARD ---
      catType:
      begin
        // Pre-click ONLY if a position was specified (Gemini 'type_text_at' brings it).
        // Claude's 'type' action does NOT carry coordinates (types in the focused control) -> arrives (0,0);
        // clicking (0,0) would remove focus. Therefore we only click when X/Y != 0.
        if (Action.X <> 0) or (Action.Y <> 0) then
        begin
          SmoothMouseMove(Action.X, Action.Y);
          SendMouseInput(MOUSEEVENTF_LEFTDOWN);
          SendMouseInput(MOUSEEVENTF_LEFTUP);
          Sleep(50); // Wait for focus
        end;

        // Type Unicode text
        for I := 1 to Length(Action.TextToType) do
          SendUnicodeChar(Action.TextToType[I]);

        if Action.PressEnter then
        begin
          Sleep(50);
          SendKeyboardInput(VK_RETURN, False);
          SendKeyboardInput(VK_RETURN, True);
        end;
      end;

      catKeyCombination:
      begin
        ParseAndExecuteCombo(Action.KeyCombo);
      end;

      catHoldKey:
      begin
        // Holds the key(s) pressed during HoldDuration seconds.
        Mods := ModifiersDown(Action.KeyCombo);
        if Action.HoldDuration > 0 then
          Sleep(Round(Action.HoldDuration * 1000))
        else
          Sleep(1000);
        ModifiersUp(Mods);
      end;

      // --- OTHERS ---
      catWait:
      begin
        Sleep(5000); // Gemini defines wait_5_seconds
      end;

      catNavigate:
      begin
         // Here we do nothing physical on Desktop,
         // but we could open the default browser if we wanted.
         // for now, we assume logical success and return the URL in the main component.
      end;

    else
      // catScreenshot and others are handled externally or do not require input action
    end;

  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

// -----------------------------------------------------------------------------
// HELPER: Screen Capture
// -----------------------------------------------------------------------------
{class procedure TAiWindowsExecutor.CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect; Quality: Integer = 70);
var
  DC: HDC;
  Bmp: TBitmap;
  Jpg: TJPEGImage;
  Stream: TMemoryStream;
  ScreenWidth, ScreenHeight: Integer;
begin
  if not Assigned(MediaFile) then
    MediaFile := TAiMediaFile.Create;

  // 1. Get actual dimensions of the primary monitor
  // Note: For multi-monitor support, extra logic would be required (EnumDisplayMonitors)
  ScreenWidth := GetSystemMetrics(SM_CXSCREEN);
  ScreenHeight := GetSystemMetrics(SM_CYSCREEN);

  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(ScreenWidth, ScreenHeight);
    DC := GetDC(0); // 0 = Desktop HWND
    try
      // Fast BitBlt copy
      BitBlt(Bmp.Canvas.Handle, 0, 0, ScreenWidth, ScreenHeight, DC, 0, 0, SRCCOPY);
    finally
      ReleaseDC(0, DC);
    end;

    // Optional: Draw cursor (Gemini helps to know where the mouse is)

    var CursorPos: TPoint;
    var IconInfo: TIconInfo;
    GetCursorPos(CursorPos);
    if GetIconInfo(GetCursor, IconInfo) then
    begin
      DrawIcon(Bmp.Canvas.Handle, CursorPos.X - IconInfo.xHotspot, CursorPos.Y - IconInfo.yHotspot, GetCursor);
      DeleteObject(IconInfo.hbmMask);
      DeleteObject(IconInfo.hbmColor);
    end;


    // 2. Compress to JPEG
    Jpg := TJPEGImage.Create;
    try
      Jpg.Assign(Bmp);
      Jpg.CompressionQuality := Quality; // 70 is a good quality/size balance
      Jpg.Compress;

      Stream := TMemoryStream.Create;
      Jpg.SaveToStream(Stream);
      Stream.Position := 0;

      // 3. Load into MediaFile
      MediaFile.LoadFromStream('screenshot.jpg', Stream);

      // Free Stream (LoadFromStream usually copies, or TAiMediaFile takes ownership, check base implementation)
      // Assuming LoadFromStream copies:
      Stream.Free;
    finally
      Jpg.Free;
    end;
  finally
    Bmp.Free;
  end;
end;
}


class procedure TAiWindowsExecutor.CaptureScreen(var MediaFile: TAiMediaFile; TargetArea: TRect; Quality: Integer);
var
  DC: HDC;
  Bmp: TBitmap;
  Jpg: TJPEGImage;
  Stream: TMemoryStream;
  W, H: Integer;

  // Variables for capturing the cursor
  CursorInfo: TCursorInfo;
  IconInfo: TIconInfo;
//  hIcon: HICON;
begin
  // 1. Ensure the output object exists
  if not Assigned(MediaFile) then
    MediaFile := TAiMediaFile.Create;

  // 2. Calculate dimensions based on the requested rectangle
  W := TargetArea.Width;
  H := TargetArea.Height;

  // Safety fallback: If the area is invalid, capture the full primary monitor
  if (W <= 0) or (H <= 0) then
  begin
    W := GetSystemMetrics(SM_CXSCREEN);
    H := GetSystemMetrics(SM_CYSCREEN);
    TargetArea := Rect(0, 0, W, H);
  end;

  Bmp := TBitmap.Create;
  try
    // pf24bit is sufficient and faster for JPEGs
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(W, H);

    DC := GetDC(0); // 0 = Handle to the entire desktop
    try
      // 3. Pixel capture (BitBlt)
      // Copy from the screen DC to the Bitmap canvas.
      // Use TargetArea.Left and Top as source coordinates (Source X, Source Y).
      BitBlt(Bmp.Canvas.Handle, 0, 0, W, H, DC, TargetArea.Left, TargetArea.Top, SRCCOPY);

      // 4. Draw the cursor (overlay)
      // This is crucial so that the AI knows where the pointer is relative to the image.
      {
      CursorInfo.cbSize := SizeOf(CursorInfo);
      if GetCursorInfo(CursorInfo) and (CursorInfo.flags = CURSOR_SHOWING) then
      begin
        hIcon := CopyIcon(CursorInfo.hCursor);
        if hIcon <> 0 then
        try
          if GetIconInfo(hIcon, IconInfo) then
          begin
            // Calculate relative position:
            // ActualMousePosition - CaptureOrigin - IconHotspotOffset
            DrawIcon(Bmp.Canvas.Handle,
                     CursorInfo.ptScreenPos.x - TargetArea.Left - IconInfo.xHotspot,
                     CursorInfo.ptScreenPos.y - TargetArea.Top - IconInfo.yHotspot,
                     hIcon);

            // Clean up icon resources
            DeleteObject(IconInfo.hbmMask);
            DeleteObject(IconInfo.hbmColor);
          end;
        finally
          DestroyIcon(hIcon);
        end;
      end;
      }

    finally
      ReleaseDC(0, DC);
    end;

    // 5. Compression and saving
    Jpg := TJPEGImage.Create;
    try
      Jpg.Assign(Bmp);
      Jpg.CompressionQuality := Quality; // Recommended: 60-75 for speed/size
      Jpg.Compress;

      Stream := TMemoryStream.Create;
      try
        Jpg.SaveToStream(Stream);
        Stream.Position := 0;

        // Load into the MediaFile
        // The name 'screenshot.jpg' helps TAiMediaFile detect the correct MimeType
        MediaFile.LoadFromStream('screenshot.jpg', Stream);
      finally
        Stream.Free;
      end;
    finally
      Jpg.Free;
    end;

  finally
    Bmp.Free;
  end;
end;

end.
