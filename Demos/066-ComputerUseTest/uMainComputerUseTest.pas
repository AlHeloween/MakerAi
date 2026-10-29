unit uMainComputerUseTest;

// =============================================================================
//  Demo de prueba de Computer Use (Claude computer_20251124 / Gemini computerUse).
//
//  How to use:
//   1. Open a harmless target app (e.g. Notepad) and leave it visible.
//   2. Choose a provider (Claude / Gemini) and press "Run".
//   3. The model will take screenshots and control the REAL mouse/keyboard to
//      complete the task described in the prompt.
//
//  The physical executor is TAiWindowsFMXExecutor (SendInput + GDI/FMX capture).
//  Capture runs on the main thread (Synchronize) because it uses FMX.Canvas.
//
//  WARNING: it controls the real desktop. Do not leave sensitive windows in the foreground.
// =============================================================================

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.JSON, System.Net.HttpClient, System.Math, System.IOUtils,
  {$IFDEF MSWINDOWS} Winapi.Windows, FMX.Platform.Win, {$ENDIF}
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Surfaces, FMX.Dialogs,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo,
  FMX.Memo.Types, FMX.ListBox, FMX.Layouts, FMX.Edit,
  uMakerAi.Core, uMakerAi.Chat.Messages, uMakerAi.Chat.AiConnection,
  uMakerAi.Tools.ComputerUse, uMakerAi.Tools.ComputerUse.WindowsFMX,
  uMakerAi.Utils.ScreenCapture, uMakerAi.ParamsRegistry,
  uMakerAi.Chat.Initializations; // registra todos los drivers (Claude, Gemini, ...)

type
  TFormComputerUse = class(TForm)
    tbTop: TToolBar;
    lblProvider: TLabel;
    cbProvider: TComboBox;
    btnRun: TButton;
    lblStatus: TLabel;
    mePrompt: TMemo;
    meLog: TMemo;
    splV: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
  private
    FConn: TAiChatConnection;
    FCU: TAiComputerUseTool;
    FShotDir: string;   // carpeta donde se guardan los screenshots para depurar
    FShotCount: Integer;
    FLogFile: string;   // copia del log en disco (para correr sin mirar la GUI)
    FAutoRun: Boolean;  // -autorun: dispara Ejecutar al mostrarse la ventana
    procedure Log(const S: string);
    procedure SetStatus(const S: string);
    // Captura el área física y la devuelve como JPG escalado a OutW x OutH.
    function CaptureScaled(const Area: TRect; OutW, OutH: Integer): TAiMediaFile;
    // Eventos de Computer Use
    procedure DoExecuteAction(Sender: TObject; const ActionData: TAiActionData; var Result: TAiActionResult);
    procedure DoRequestScreenshot(Sender: TObject; var MediaFile: TAiMediaFile);
    procedure DoSafetyConfirmation(Sender: TObject; const Explanation: string; var Allow: Boolean);
    // Eventos de la conexión
    procedure DoReceiveEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
    procedure DoError(Sender: TObject; const ErrorMsg: string; E: Exception; const AResponse: IHTTPResponse);
  end;

var
  FormComputerUse: TFormComputerUse;

implementation

{$R *.fmx}

const
  DEF_PROMPT =
    'You are a desktop automation agent.' + sLineBreak +
    'Task: take a screenshot, locate the text area of the foreground window ' +
    '(e.g. Notepad), click on it and type exactly: ' +
    '"Hello MakerAI from Computer Use". Then take another screenshot to confirm and ' +
    'briefly describe what you see.';

procedure TFormComputerUse.FormCreate(Sender: TObject);
begin
  // Force the window to the center of the primary screen (prevents it from appearing
  // outside the visible area: it shows in the taskbar but not on screen).
  Self.Position := TFormPosition.ScreenCenter;
  Self.Width := 900;
  Self.Height := 680;

  // Computer Use component
  FCU := TAiComputerUseTool.Create(Self);
  FCU.OnExecuteAction := DoExecuteAction;
  FCU.OnRequestScreenshot := DoRequestScreenshot;
  FCU.OnSafetyConfirmation := DoSafetyConfirmation;
  FCU.EnableZoom := True; // permite la acción zoom de Claude (computer_20251124)

  // Capture area = physical primary monitor (origin 0,0).
  FCU.AreaLeft := 0;
  FCU.AreaTop := 0;
  {$IFDEF MSWINDOWS}
  FCU.AreaWidth := GetSystemMetrics(SM_CXSCREEN);
  FCU.AreaHeight := GetSystemMetrics(SM_CYSCREEN);
  {$ELSE}
  FCU.AreaWidth := 1920;
  FCU.AreaHeight := 1080;
  {$ENDIF}
  // Resolution DECLARED to the AI: the image is already sent reduced to <=1280px wide.
  // Anthropic/Gemini reduce large images on the server; if the
  // declared resolution does not match the real image, clicks drift.
  // The executor still clicks in physical pixels (DenormalizeCoordinate uses AreaWidth).
  FCU.ScreenWidth := 1280;
  FCU.ScreenHeight := Round(FCU.AreaHeight * 1280 / FCU.AreaWidth);

  // Universal connection
  FConn := TAiChatConnection.Create(Self);
  FConn.ChatTools.ComputerUseTool := FCU;
  FConn.OnReceiveDataEnd := DoReceiveEnd;
  FConn.OnError := DoError;

  // Enable cap_ComputerUse on the models we will use. None of them includes it
  // by default on purpose: it is the capability that gives the AI the real mouse and
  // keyboard, so opt-in is up to the programmer.
  // (gemini-2.5-computer-use is the exception: it is a dedicated model and already has it.)
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-4-8', 'ModelCaps',   '[cap_Image, cap_ComputerUse]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-4-8', 'SessionCaps', '[cap_Image, cap_ComputerUse]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra', 'ModelCaps',   '[cap_Image, cap_Reasoning, cap_ComputerUse]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra', 'SessionCaps', '[cap_Image, cap_Reasoning, cap_ComputerUse]');

  cbProvider.Items.Clear;
  cbProvider.Items.Add('Claude');
  cbProvider.Items.Add('Gemini');
  cbProvider.Items.Add('OpenAI (gpt-6-astra)');
  cbProvider.ItemIndex := 0;

  // Debug folder: every screenshot sent to the AI is saved here.
  FShotDir := ExtractFilePath(ParamStr(0)) + 'shots' + PathDelim;
  ForceDirectories(FShotDir);
  FShotCount := 0;

  // Log to disk, next to the exe. It is reset on every run.
  FLogFile := ExtractFilePath(ParamStr(0)) + 'run.log';
  try
    TFile.WriteAllText(FLogFile, '', TEncoding.UTF8);
  except
    FLogFile := '';
  end;

  mePrompt.Lines.Text := DEF_PROMPT;
  SetStatus('Ready. Open the target app and press Run.');
  Log(Format('Screen: %dx%d', [FCU.ScreenWidth, FCU.ScreenHeight]));
  Log('Screenshots saved in: ' + FShotDir);

  // --- Command-line startup (to run without touching the GUI) ---
  //   -provider=openai|claude|gemini   preselects the provider
  //   -prompt=<text>                   replaces the default task
  //   -autorun                         presses Run only, when shown
  for var Pi := 1 to ParamCount do
  begin
    var LP := LowerCase(ParamStr(Pi));
    if LP.StartsWith('-provider=') then
    begin
      var LProv := LP.Substring(Length('-provider='));
      if LProv = 'claude' then cbProvider.ItemIndex := 0
      else if LProv = 'gemini' then cbProvider.ItemIndex := 1
      else if (LProv = 'openai') or (LProv = 'astra') then cbProvider.ItemIndex := 2;
    end
    else if LP.StartsWith('-prompt=') then
      mePrompt.Lines.Text := ParamStr(Pi).Substring(Length('-prompt='))
    else if LP = '-autorun' then
      FAutoRun := True;
  end;

  // The trigger goes here and not in FormShow: OnShow is not hooked in the .fmx,
  // so that method never runs. ForceQueue defers to the message loop, i.e.
  // when the window is already visible.
  if FAutoRun then
  begin
    FAutoRun := False;
    TThread.ForceQueue(nil,
      procedure
      begin
        btnRunClick(btnRun);
      end);
  end;
end;

procedure TFormComputerUse.FormShow(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  H: HWND;
  WA: TRect;
  W, Ht, X, Y: Integer;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  // Repositions the real window (HWND) inside the work area of the
  // primary monitor and brings it to the front. Solves the case "it shows in the
  // taskbar but not on screen" (window outside the visible area).
  H := FormToHWND(Self);
  if H = 0 then
    Exit;
  W := 900;
  Ht := 680;
  if not SystemParametersInfo(SPI_GETWORKAREA, 0, @WA, 0) then
    WA := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
  X := WA.Left + ((WA.Width  - W)  div 2);
  Y := WA.Top  + ((WA.Height - Ht) div 2);
  if X < WA.Left then X := WA.Left;
  if Y < WA.Top  then Y := WA.Top;
  SetWindowPos(H, HWND_TOP, X, Y, W, Ht, SWP_SHOWWINDOW);
  ShowWindow(H, SW_SHOW);
  SetForegroundWindow(H);
  {$ENDIF}

end;

procedure TFormComputerUse.Log(const S: string);
var
  LLine: string;
begin
  LLine := FormatDateTime('hh:nn:ss', Now) + '  ' + S;

  // Disk copy: allows launching the demo from the command line and reviewing
  // afterwards what happened without having watched the window.
  if FLogFile <> '' then
  try
    TFile.AppendAllText(FLogFile, LLine + sLineBreak, TEncoding.UTF8);
  except
    // the log must never crash the run
  end;

  TThread.Queue(nil,
    procedure
    begin
      meLog.Lines.Add(LLine);
      meLog.GoToTextEnd;
    end);
end;

procedure TFormComputerUse.SetStatus(const S: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      lblStatus.Text := S;
    end);
end;

// -----------------------------------------------------------------------------
// Computer Use
// -----------------------------------------------------------------------------
procedure TFormComputerUse.DoExecuteAction(Sender: TObject; const ActionData: TAiActionData; var Result: TAiActionResult);
begin
  Log(Format('ACTION: %s  (x=%d y=%d mod="%s" keys="%s")',
    [ActionData.FunctionName, ActionData.X, ActionData.Y, ActionData.Modifiers, ActionData.KeyCombo]));
  Result := TAiWindowsFMXExecutor.Execute(ActionData);
  if not Result.Success then
    Log('  -> ERROR executing: ' + Result.ErrorMessage)
  else if ActionData.ActionType = catCursorPosition then
    Log('  -> cursor: ' + Result.CustomOutput);
end;

function TFormComputerUse.CaptureScaled(const Area: TRect; OutW, OutH: Integer): TAiMediaFile;
var
  Full, Scaled: FMX.Graphics.TBitmap;
  Surf: TBitmapSurface;
  SP: TBitmapCodecSaveParams;
  Strm: TMemoryStream;
  {$IFDEF MSWINDOWS} Cur: TPoint; {$ENDIF}
  cx, cy: Single;
  R: TRectF;
begin
  Result := TAiMediaFile.Create;
  if (OutW <= 0) or (OutH <= 0) then Exit;
  Full := TScreenCapture.CaptureArea(Area);
  if not Assigned(Full) then Exit;
  try
    Scaled := FMX.Graphics.TBitmap.Create(OutW, OutH);
    try
      if Scaled.Canvas.BeginScene then
      try
        Scaled.Canvas.DrawBitmap(Full, RectF(0, 0, Full.Width, Full.Height),
          RectF(0, 0, OutW, OutH), 1, False);
        // Cursor (scaled to output size) so the AI sees the pointer.
        {$IFDEF MSWINDOWS}
        if GetCursorPos(Cur) then
        begin
          cx := (Cur.X - Area.Left) * OutW / Max(1, Area.Width);
          cy := (Cur.Y - Area.Top)  * OutH / Max(1, Area.Height);
          if (cx >= 0) and (cy >= 0) and (cx < OutW) and (cy < OutH) then
          begin
            R := RectF(cx - 7, cy - 7, cx + 7, cy + 7);
            Scaled.Canvas.Fill.Color := $80FF0000;
            Scaled.Canvas.FillEllipse(R, 1);
            Scaled.Canvas.Stroke.Color := TAlphaColors.White;
            Scaled.Canvas.Stroke.Thickness := 2;
            Scaled.Canvas.DrawEllipse(R, 1);
          end;
        end;
        {$ENDIF}
      finally
        Scaled.Canvas.EndScene;
      end;

      Surf := TBitmapSurface.Create;
      try
        Surf.Assign(Scaled);
        Strm := TMemoryStream.Create;
        try
          SP.Quality := 80;
          if TBitmapCodecManager.SaveToStream(Strm, Surf, '.jpg', @SP) then
          begin
            // Copy to disk (exactly what is sent to the AI, with the cursor).
            if FShotDir <> '' then
            begin
              Inc(FShotCount);
              try
                Strm.Position := 0;
                Strm.SaveToFile(FShotDir + Format('shot_%.3d_%dx%d.jpg', [FShotCount, OutW, OutH]));
              except
                // do not block capture due to a disk write failure
              end;
            end;
            Strm.Position := 0;
            Result.LoadFromStream('screenshot.jpg', Strm);
          end;
        finally
          Strm.Free;
        end;
      finally
        Surf.Free;
      end;
    finally
      Scaled.Free;
    end;
  finally
    Full.Free;
  end;
end;

procedure TFormComputerUse.DoRequestScreenshot(Sender: TObject; var MediaFile: TAiMediaFile);
var
  Area: TRect;
  OutW, OutH: Integer;
  MF: TAiMediaFile;
begin
  if (FCU.CurrentAction.ActionType = catZoom) and not FCU.CurrentAction.ZoomRect.IsEmpty then
  begin
    // Zoom: send the region at native resolution (the AI inspects detail).
    Area := FCU.CurrentAction.ZoomRect;
    OutW := Area.Width;
    OutH := Area.Height;
  end
  else
  begin
    // Full screen: capture the physical area, send it reduced to the
    // declared resolution (ScreenWidth x ScreenHeight) so it matches.
    Area := Rect(FCU.AreaLeft, FCU.AreaTop, FCU.AreaLeft + FCU.AreaWidth, FCU.AreaTop + FCU.AreaHeight);
    OutW := FCU.ScreenWidth;
    OutH := FCU.ScreenHeight;
  end;

  MF := nil;
  // FMX.Canvas -> must run on the main thread.
  TThread.Synchronize(nil,
    procedure
    begin
      MF := CaptureScaled(Area, OutW, OutH);
    end);
  MediaFile := MF;
  Log(Format('  -> screenshot %dx%d (origin %dx%d)', [OutW, OutH, Area.Width, Area.Height]));
end;

procedure TFormComputerUse.DoSafetyConfirmation(Sender: TObject; const Explanation: string; var Allow: Boolean);
begin
  // In this test with the user present, we auto-allow but log it.
  Log('SAFETY (auto-allowed): ' + Explanation);
  Allow := True;
end;

// -----------------------------------------------------------------------------
// Conexión
// -----------------------------------------------------------------------------
procedure TFormComputerUse.DoReceiveEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
begin
  Log('=== END ===');
  if aText <> '' then
    Log('Model: ' + aText);
  SetStatus('Completed.');
  TThread.Queue(nil, procedure begin btnRun.Enabled := True; end);
end;

procedure TFormComputerUse.DoError(Sender: TObject; const ErrorMsg: string; E: Exception; const AResponse: IHTTPResponse);
begin
  Log('ERROR: ' + ErrorMsg);
  SetStatus('Error.');
  TThread.Queue(nil, procedure begin btnRun.Enabled := True; end);
end;

procedure TFormComputerUse.btnRunClick(Sender: TObject);
begin
  meLog.Lines.Clear;
  FShotCount := 0; // los screenshots de esta corrida empiezan en shot_001
  btnRun.Enabled := False;

  if cbProvider.ItemIndex = 1 then
  begin
    FConn.DriverName := 'Gemini';
    FConn.Model := 'gemini-2.5-computer-use-preview-10-2025';
    FConn.Params.Values['ApiKey'] := '@GEMINI_API_KEY';
  end
  else if cbProvider.ItemIndex = 2 then
  begin
    // gpt-6-astra: native 'computer' tool via Responses API. Unlike
    // Claude and Gemini, it sends a BATCH of actions per turn (a computer_call
    // with an 'actions' array); the driver executes them in order and returns a single
    // final screenshot.
    FConn.DriverName := 'OpenAi';
    FConn.Model := 'gpt-6-astra';
    FConn.Params.Values['ApiKey'] := '@OPENAI_API_KEY';
  end
  else
  begin
    FConn.DriverName := 'Claude';
    FConn.Model := 'claude-opus-4-8';
    FConn.Params.Values['ApiKey'] := '@CLAUDE_API_KEY';
  end;

  SetStatus('Running with ' + FConn.DriverName + '...');
  Log('Provider: ' + FConn.DriverName + '  Model: ' + FConn.Model);
  Log('You have 4 seconds to focus the target app...');

  // Small wait so the user can activate the target window.
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(4000);
      try
        FConn.AddMessageAndRun(mePrompt.Lines.Text, 'user', []);
      except
        on E: Exception do
          DoError(FConn, E.Message, E, nil);
      end;
    end).Start;
end;

end.
