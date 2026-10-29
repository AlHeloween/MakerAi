// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - YouTube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uMakerAi.Utils.ScreenCapture;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math, System.UITypes,
  FMX.Graphics, FMX.Types, FMX.Platform, FMX.Forms, FMX.Objects, FMX.Surfaces
  {$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.Messages, FMX.Platform.Win
  {$ENDIF}
  {$IFDEF MACOS}
  , Macapi.CoreGraphics, Macapi.CoreFoundation, Macapi.Foundation
  {$ENDIF}
  ;

type
  TScreenCapture = class
  private
    {$IFDEF MSWINDOWS}
    class function CaptureScreenWindows(const ARect: TRect): FMX.Graphics.TBitmap;
    {$ENDIF}
    {$IFDEF MACOS}
    class function CaptureScreenMacOS(const ARect: TRect = TRect.Empty): FMX.Graphics.TBitmap;
    {$ENDIF}
    {$IFDEF ANDROID}
    class function CaptureScreenAndroid(const ARect: TRect = TRect.Empty): FMX.Graphics.TBitmap;
    {$ENDIF}
  public
    // Captures the entire screen
    class function CaptureFullScreen: FMX.Graphics.TBitmap;

    // Captures a specific area of the screen
    class function CaptureArea(const ARect: TRect): FMX.Graphics.TBitmap;

    // Gets the screen dimensions
    class function GetScreenSize: TPoint;

    // Saves the bitmap to a file
    class procedure SaveToFile(ABitmap: FMX.Graphics.TBitmap; const AFileName: string);
    class function SelectArea(out ASelectedRect: TRect): Boolean;
  end deprecated 'Use TScreenCapture (AIChat.ScreenCapture)';


 TSelectionForm = class(TForm)
  private
    IsDragging: Boolean;
    StartPoint, EndPoint: TPointF;
    VirtualScreenLeft, VirtualScreenTop: Integer;
    HasSelection : Boolean;
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
    procedure FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
  protected
  public
     constructor Create(AOwner: TComponent); override;
    function Execute(var ASelectedRect: TRect): Boolean;
  end;



implementation

{$IFDEF MSWINDOWS}

class function TScreenCapture.CaptureScreenWindows(const ARect: TRect): FMX.Graphics.TBitmap;
var
  ScreenDC, MemDC: HDC;
  HBmp, OldBmp: HBITMAP;
  BmpInfo: TBitmapInfo;
  BmpData: Pointer;
  CaptureRect: TRect;
  VirtualLeft, VirtualTop, VirtualWidth, VirtualHeight: Integer;
  BytesPerPixel, DataSize, PixelCount, i: Integer;
  Surface: TBitmapSurface;
  pByte: System.PByte;
begin
  Result := nil;

  // Virtual screen metrics (multi-monitor support)
  VirtualLeft := GetSystemMetrics(SM_XVIRTUALSCREEN);
  VirtualTop := GetSystemMetrics(SM_YVIRTUALSCREEN);
  VirtualWidth := GetSystemMetrics(SM_CXVIRTUALSCREEN);
  VirtualHeight := GetSystemMetrics(SM_CYVIRTUALSCREEN);

  if ARect.IsEmpty then
    CaptureRect := TRect.Create(VirtualLeft, VirtualTop, VirtualLeft + VirtualWidth, VirtualTop + VirtualHeight)
  else
    CaptureRect := ARect;

  // Clip to virtual area
  CaptureRect.Left := Max(VirtualLeft, CaptureRect.Left);
  CaptureRect.Top := Max(VirtualTop, CaptureRect.Top);
  CaptureRect.Right := Min(VirtualLeft + VirtualWidth, CaptureRect.Right);
  CaptureRect.Bottom := Min(VirtualTop + VirtualHeight, CaptureRect.Bottom);

  if (CaptureRect.Width <= 0) or (CaptureRect.Height <= 0) then
    Exit;

  ScreenDC := GetDC(0);
  try
    MemDC := CreateCompatibleDC(ScreenDC);
    try
      HBmp := CreateCompatibleBitmap(ScreenDC, CaptureRect.Width, CaptureRect.Height);
      try
        OldBmp := SelectObject(MemDC, HBmp);
        try
          // Copy from virtual screen (may have negative coordinates)
          BitBlt(MemDC, 0, 0, CaptureRect.Width, CaptureRect.Height,
                 ScreenDC, CaptureRect.Left, CaptureRect.Top, SRCCOPY);

          // Prepare BITMAPINFO for 32bpp top-down
          FillChar(BmpInfo, SizeOf(BmpInfo), 0);
          BmpInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
          BmpInfo.bmiHeader.biWidth := CaptureRect.Width;
          BmpInfo.bmiHeader.biHeight := -CaptureRect.Height; // top-down
          BmpInfo.bmiHeader.biPlanes := 1;
          BmpInfo.bmiHeader.biBitCount := 32;
          BmpInfo.bmiHeader.biCompression := BI_RGB;

          BytesPerPixel := 4;
          PixelCount := CaptureRect.Width * CaptureRect.Height;
          DataSize := PixelCount * BytesPerPixel;

          GetMem(BmpData, DataSize);
          try
            if GetDIBits(MemDC, HBmp, 0, CaptureRect.Height, BmpData, BmpInfo, DIB_RGB_COLORS) = 0 then
              Exit; // GetDIBits failed

            // Ensure opaque alpha (GetDIBits usually leaves alpha = 0 or garbage)
            pByte := System.PByte(BmpData);
            for i := 0 to PixelCount - 1 do
            begin
              pByte[3] := 255; // A = 255
              Inc(pByte, 4);
            end;

            // Create TBitmapSurface and copy the bytes (BGRA format)
            Surface := TBitmapSurface.Create;
            try
              Surface.SetSize(CaptureRect.Width, CaptureRect.Height, TPixelFormat.BGRA);
              // Block copy (Surface.Bits points to internal buffer)
              Move(BmpData^, Surface.Bits^, DataSize);

              // Convert to FMX TBitmap (Assign does native conversion)
              Result := FMX.Graphics.TBitmap.Create;
              Result.Assign(Surface);

            finally
              Surface.Free;
            end;

          finally
            FreeMem(BmpData);
          end;

        finally
          // restore the original selected bitmap
          SelectObject(MemDC, OldBmp);
        end;
      finally
        DeleteObject(HBmp);
      end;
    finally
      DeleteDC(MemDC);
    end;
  finally
    ReleaseDC(0, ScreenDC);
  end;
end;




{$ENDIF}

{$IFDEF MACOS}
class function TScreenCapture.CaptureScreenMacOS(const ARect: TRect): FMX.Graphics.TBitmap;
var
  ImageRef: CGImageRef;
  CaptureRect: CGRect;
  ScreenBounds: CGRect;
  DataProvider: CGDataProviderRef;
  Data: CFDataRef;
  BmpData: TBitmapData;
  i, j: Integer;
  SrcPtr, DstPtr: PByte;
begin
  Result := nil;

  // Get the dimensions of the main screen
  ScreenBounds := CGDisplayBounds(CGMainDisplayID);

  // Determine the area to capture
  if ARect.IsEmpty then
    CaptureRect := ScreenBounds
  else
  begin
    CaptureRect.origin.x := ARect.Left;
    CaptureRect.origin.y := ARect.Top;
    CaptureRect.size.width := ARect.Width;
    CaptureRect.size.height := ARect.Height;
  end;

  // Capture the image
  ImageRef := CGDisplayCreateImageForRect(CGMainDisplayID, CaptureRect);
  if ImageRef = nil then
    Exit;

  try
    DataProvider := CGImageGetDataProvider(ImageRef);
    if DataProvider = nil then
      Exit;

    Data := CGDataProviderCopyData(DataProvider);
    if Data = nil then
      Exit;

    try
      Result := FMX.Graphics.TBitmap.Create(Round(CaptureRect.size.width), Round(CaptureRect.size.height));

      if Result.Map(TMapAccess.Write, BmpData) then
      try
        SrcPtr := CFDataGetBytePtr(Data);
        DstPtr := BmpData.Data;

        // Convert from ARGB to RGBA (FMX format)
        for i := 0 to Result.Height - 1 do
        begin
          for j := 0 to Result.Width - 1 do
          begin
            DstPtr[0] := SrcPtr[2]; // R
            DstPtr[1] := SrcPtr[1]; // G
            DstPtr[2] := SrcPtr[0]; // B
            DstPtr[3] := SrcPtr[3]; // A

            Inc(SrcPtr, 4);
            Inc(DstPtr, 4);
          end;
        end;
      finally
        Result.Unmap(BmpData);
      end;

    finally
      CFRelease(Data);
    end;
  finally
    CGImageRelease(ImageRef);
  end;
end;
{$ENDIF}

{$IFDEF ANDROID}
class function TScreenCapture.CaptureScreenAndroid(const ARect: TRect): FMX.Graphics.TBitmap;
begin
  // On Android, screen capture requires special permissions
  // and is usually done via Media Projection API
  // This is a basic implementation that requires root permissions
  // or more complex native implementation
  Result := nil;
  // TODO: Implement capture for Android
  raise Exception.Create('Screen capture not implemented for Android platform');
end;
{$ENDIF}

class function TScreenCapture.CaptureFullScreen: FMX.Graphics.TBitmap;
begin
  {$IFDEF MSWINDOWS}
  Result := CaptureScreenWindows(TRect.Create(0,0,0,0));
  {$ENDIF}
  {$IFDEF MACOS}
  Result := CaptureScreenMacOS;
  {$ENDIF}
  {$IFDEF ANDROID}
  Result := CaptureScreenAndroid;
  {$ENDIF}
  {$IFDEF IOS}
  // iOS does not allow screen capture for security reasons
  Result := nil;
  {$ENDIF}
end;

class function TScreenCapture.CaptureArea(const ARect: TRect): FMX.Graphics.TBitmap;
begin
  {$IFDEF MSWINDOWS}
  Result := CaptureScreenWindows(ARect);
  {$ENDIF}
  {$IFDEF MACOS}
  Result := CaptureScreenMacOS(ARect);
  {$ENDIF}
  {$IFDEF ANDROID}
  Result := CaptureScreenAndroid(ARect);
  {$ENDIF}
  {$IFDEF IOS}
  Result := nil;
  {$ENDIF}
end;

class function TScreenCapture.GetScreenSize: TPoint;
begin
  {$IFDEF MSWINDOWS}
  Result.X := GetSystemMetrics(SM_CXSCREEN);
  Result.Y := GetSystemMetrics(SM_CYSCREEN);
  {$ENDIF}
  {$IFDEF MACOS}
  var Bounds := CGDisplayBounds(CGMainDisplayID);
  Result.X := Round(Bounds.size.width);
  Result.Y := Round(Bounds.size.height);
  {$ENDIF}
  {$IFDEF ANDROID}
  // Implementation for Android would require JNI
  Result := TPoint.Zero;
  {$ENDIF}
  {$IFDEF IOS}
  Result := TPoint.Zero;
  {$ENDIF}
end;

class procedure TScreenCapture.SaveToFile(ABitmap: FMX.Graphics.TBitmap; const AFileName: string);
begin
  if Assigned(ABitmap) then
    ABitmap.SaveToFile(AFileName);
end;


class function TScreenCapture.SelectArea(out ASelectedRect: TRect): Boolean;
var
  F: TSelectionForm;
begin
  F := TSelectionForm.Create(nil);
  try
    Result := F.Execute(ASelectedRect);
  finally
    F.Free;
  end;
End;


{ TSelectionForm }

procedure TSelectionForm.FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    IsDragging := True;
    // HasSelection stays True to allow painting, but IsDragging has priority in the IF of Paint
    HasSelection := True;

    StartPoint := TPointF.Create(X, Y);
    EndPoint := StartPoint;

    // Force immediate repaint to erase the old green rectangle
    // and start drawing the new translucent one
    Invalidate;
  end
  else
  begin
    ModalResult := mrCancel;
    Close;
  end;
end;


procedure TSelectionForm.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if IsDragging then
  begin
    EndPoint := TPointF.Create(X, Y);
    Invalidate;
  end;
end;

procedure TSelectionForm.FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if (Button = TMouseButton.mbLeft) and IsDragging then
  begin
    IsDragging := False;
    if (Abs(EndPoint.X - StartPoint.X) > 2) and (Abs(EndPoint.Y - StartPoint.Y) > 2) then
      ModalResult := mrOk
    else
      ModalResult := mrCancel;
  end;
end;

procedure TSelectionForm.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    ModalResult := mrCancel;
    Close;
  end;
end;

procedure TSelectionForm.FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
var
  PaintRect: TRectF;
begin
  if IsDragging or HasSelection then
  begin
    PaintRect := TRectF.Create(
      Min(StartPoint.X, EndPoint.X),
      Min(StartPoint.Y, EndPoint.Y),
      Max(StartPoint.X, EndPoint.X),
      Max(StartPoint.Y, EndPoint.Y)
    );

    // --- CASE 1: DRAGGING (New Selection) ---
    if IsDragging then
    begin
      // 1. Set base color to White
      Canvas.Fill.Color := TAlphaColors.White;

      // 2. IMPORTANT: Use AOpacity parameter at 0.25 (25% visible)
      // This makes the white translucent ("milky")
      Canvas.FillRect(PaintRect, 0, 0, [], 0.25, TCornerType.Round);

      // 3. White Border
      Canvas.Stroke.Color := TAlphaColors.White;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawRect(PaintRect, 0, 0, [], 1.0); // Fully opaque border
    end

    // --- CASE 2: PREVIOUS SELECTION (Static) ---
    else if HasSelection then
    begin
      // Do not fill (FillRect) so it is transparent.

      // Only draw Green border
      Canvas.Stroke.Color := TAlphaColors.Lime;
      Canvas.Stroke.Thickness := 3;
      Canvas.DrawRect(PaintRect, 0, 0, [], 1.0);
    end;
  end;
end;

constructor TSelectionForm.Create(AOwner: TComponent);
Var
  R : TRectangle;
begin
  inherited CreateNew(AOwner); // avoids looking for .fmx/.dfm

  // basic configuration that was previously done in Execute
  BorderStyle := TFmxFormBorderStyle.None;
  FormStyle := TFormStyle.StayOnTop;
  Fill.Color := TAlphaColorRec.Black;
  Transparency := True;
  Cursor := crCross;

  R := TRectangle.Create(Self);
  R.Align := TAlignLayout.Client;
  R.Opacity := 0.3;
  R.Fill.Color := TAlphaColorRec.Black;
  R.HitTest := False;

  Self.AddObject(R);



  OnMouseDown := FormMouseDown;
  OnMouseMove := FormMouseMove;
  OnMouseUp   := FormMouseUp;
  OnKeyDown   := FormKeyDown;
  OnPaint     := FormPaint;
end;

function TSelectionForm.Execute(var ASelectedRect: TRect): Boolean;
begin
  IsDragging := False;
  HasSelection := False;

  // Get screen metrics
  VirtualScreenLeft := GetSystemMetrics(SM_XVIRTUALSCREEN);
  VirtualScreenTop  := GetSystemMetrics(SM_YVIRTUALSCREEN);

  // Position the form covering the entire virtual screen
  SetBounds(
    VirtualScreenLeft,
    VirtualScreenTop,
    GetSystemMetrics(SM_CXVIRTUALSCREEN),
    GetSystemMetrics(SM_CYVIRTUALSCREEN)
  );

  // Process the input rectangle (if any)
  if not ASelectedRect.IsEmpty then
  begin
    HasSelection := True;

    // Convert Global Coordinates -> Form Local Coordinates
    // Subtract the virtual screen origin to get the relative position within the form
    StartPoint := TPointF.Create(
      ASelectedRect.Left - VirtualScreenLeft,
      ASelectedRect.Top - VirtualScreenTop
    );

    EndPoint := TPointF.Create(
      ASelectedRect.Right - VirtualScreenLeft,
      ASelectedRect.Bottom - VirtualScreenTop
    );
  end;

  // Show
  if ShowModal = mrOk then
  begin
    // Convert Local Coordinates -> Global when exiting
    ASelectedRect := TRect.Create(
      VirtualScreenLeft + Round(Min(StartPoint.X, EndPoint.X)),
      VirtualScreenTop  + Round(Min(StartPoint.Y, EndPoint.Y)),
      VirtualScreenLeft + Round(Max(StartPoint.X, EndPoint.X)),
      VirtualScreenTop  + Round(Max(StartPoint.Y, EndPoint.Y))
    );
    Result := True;
  end
  else
    Result := False;
end;




end.
