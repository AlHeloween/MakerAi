program GeneradorVisual;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 14: Image and Video Generation
// =============================================================================
//
// Demonstrates the two image generation routes in MakerAI:
//
//   Demo 1 — Direct TAiDalle.Generate()           gpt-image-2
//   Demo 2 — Bridge: TAiChatConnection+ImageTool   gpt-image-1
//   Demo 3 — Native Gemini (without bridge)            gemini-2.5-flash-image
//   Demo 4 — Google Imagen 4 (endpoint :predict)   imagen-4.0-generate-001
//   Demo 5 — Video with TAiVeoGenerator             veo-3.1-generate-preview
//
// Required environment variables:
//   OPENAI_API_KEY   — Demos 1 and 2
//   GEMINI_API_KEY   — Demos 3, 4 and 5
//
// Images and videos are saved in the system temporary folder.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.SyncObjs,
  System.Threading,
  System.JSON,
  System.Net.HttpClient,
  Winapi.Windows,
  uMakerAi.Core,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.OpenAi.Dalle,
  uMakerAi.Gemini.Veo,
  uMakerAi.Chat.Initializations;

const
  OPENAI_KEY = '@OPENAI_API_KEY';
  GEMINI_KEY = '@GEMINI_API_KEY';

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

function OutFile(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, AName);
end;

procedure GuardarStream(const AFilename: string; AStream: TMemoryStream);
begin
  if (AStream = nil) or (AStream.Size = 0) then Exit;
  AStream.Position := 0;
  AStream.SaveToFile(AFilename);
  Writeln('    -> ', AFilename, ' (', AStream.Size div 1024, ' KB)');
end;

// Extracts "error.message" from an API error JSON.
// Supports: pure object, array, and text-prefix + JSON (e.g. "Error 400: {...}").
function ExtraerMensajeError(const AJson: string): string;
var
  JVal: TJSONValue;
  JObj: TJSONObject;
  LJson: string;
  LPosObj, LPosArr, LPos: Integer;
begin
  Result := Copy(AJson, 1, 160);
  LPosObj := Pos('{', AJson);
  LPosArr := Pos('[', AJson);
  if (LPosObj = 0) and (LPosArr = 0) then Exit;
  if (LPosArr > 0) and ((LPosObj = 0) or (LPosArr < LPosObj)) then
    LPos := LPosArr
  else
    LPos := LPosObj;
  LJson := Copy(AJson, LPos, MaxInt);
  try
    JVal := TJSONObject.ParseJSONValue(LJson);
    if not Assigned(JVal) then Exit;
    try
      if JVal is TJSONArray then
      begin
        if (JVal as TJSONArray).Count = 0 then Exit;
        JObj := (JVal as TJSONArray).Items[0] as TJSONObject;
      end
      else
        JObj := JVal as TJSONObject;
      if not Assigned(JObj) then Exit;
      var JErr := JObj.GetValue('error') as TJSONObject;
      if Assigned(JErr) then
        Result := JErr.GetValue<string>('message');
    finally
      JVal.Free;
    end;
  except end;
end;

// =============================================================================
// Demo 1 — TAiDalle.Generate() directo
// Simplest route: instantiate TAiDalle, call Generate(), get the image.
// =============================================================================

procedure Demo1_GeneracionDirecta;
var
  Dalle: TAiDalle;
  Img:   TAiDalleImage;
  SW:    TStopwatch;
begin
  Writeln;
  Writeln('=== Demo 1: TAiDalle.Generate() — gpt-image-2 ===');

  Dalle := TAiDalle.Create(nil);
  try
    Dalle.ApiKey       := OPENAI_KEY;
    Dalle.Model        := imGptImage2;
    Dalle.Quality      := iqLow; // iqMedium/High exceeds the 60s timeout of TNetHTTPClient
    Dalle.Background   := ibOpaque;
    Dalle.OutputFormat := ifPng;

    Write('  Generating... ');
    SW  := TStopwatch.StartNew;
    Img := Dalle.Generate(
      'An orange cat reading a Delphi book in a vintage library, ' +
      'warm lighting, professional illustration style',
      '', is1024x1024);
    SW.Stop;

    if Assigned(Img) then
    begin
      Writeln(Format('OK [%d ms]', [SW.ElapsedMilliseconds]));
      if Img.RevisedPrompt <> '' then
        Writeln('  Revised prompt: ', Copy(Img.RevisedPrompt, 1, 80), '...');
      GuardarStream(OutFile('demo1-gato-delphi.png'), Img.Image);
    end
    else
      Writeln('ERROR: no result');
  finally
    Dalle.Free;
  end;
end;

// =============================================================================
// Demo 2 — Bridge: TAiChatConnection + TAiDalleImageTool
//
// Gap analysis: ModelCaps=[] / SessionCaps=[cap_GenImage]
//              → Gap=[cap_GenImage] → InternalRunImageGeneration → ImageTool
//
// The image arrives via OnReceiveDataEnd in aMsg.MediaFiles.
// In console apps without a message pump, the callback may arrive via
// TThread.Queue after AddMessageAndRun returns: the loop with
// CheckSynchronize processes the queue until the image is received.
// =============================================================================

type
  TBridgeDemo = class
  private
    FConn:      TAiChatConnection;
    FImageTool: TAiDalleImageTool;
    FDone:      TEvent;

    procedure OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
  public
    procedure Run;
  end;

procedure TBridgeDemo.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
var
  i: Integer;
  MF: TAiMediaFile;
begin
  for i := 0 to aMsg.MediaFiles.Count - 1 do
  begin
    MF := aMsg.MediaFiles[i];
    if MF.FileCategory = Tfc_Image then
    begin
      MF.SaveToFile(OutFile('demo2-logo.png'));
      Writeln(Format(#13'    -> %s (%d KB)', [OutFile('demo2-logo.png'),
        MF.Content.Size div 1024]));
    end;
  end;
  FDone.SetEvent;
end;

procedure TBridgeDemo.Run;
var
  SW: TStopwatch;
begin
  Writeln;
  Writeln('=== Demo 2: Bridge TAiChatConnection + TAiDalleImageTool ===');
  Writeln('  gpt-image-1 | ModelCaps=[] / SessionCaps=[cap_GenImage]');

  FDone      := TEvent.Create(nil, True, False, '');
  FConn      := TAiChatConnection.Create(nil);
  FImageTool := TAiDalleImageTool.Create(nil);
  try
    FConn.DriverName := 'OpenAi';
    FConn.Model      := 'gpt-image-1';
    FConn.Params.Values['Asynchronous'] := 'True';
    FConn.Params.Values['ApiKey']       := OPENAI_KEY;

    FImageTool.ApiKey    := OPENAI_KEY;
    FImageTool.Model     := imGptImage1;
    FImageTool.Quality   := iqHigh;
    FImageTool.ImageSize := is1024x1024;
    FConn.ImageTool      := FImageTool;

    FConn.OnReceiveDataEnd := OnDataEnd;

    Write('  Generating via bridge (~20 s)...');
    SW := TStopwatch.StartNew;
    FConn.AddMessageAndRun(
      'Minimalist logo: geometric musical note in blue gradient, white background',
      'user', []);

    // Process pending TThread.Queue callbacks (in case they arrive after return)
    while (FDone.WaitFor(0) = wrTimeout) and (SW.ElapsedMilliseconds < 90000) do
      CheckSynchronize(200);
    SW.Stop;

    Writeln(Format(' OK [%d ms]', [SW.ElapsedMilliseconds]));
  finally
    FConn.Free;
    FImageTool.Free;
    FDone.Free;
  end;
end;

// =============================================================================
// Demo 3 — Gemini nativo: sin bridge, completions con responseModalities
//
// ModelCaps=[cap_Image,cap_GenImage] → Gap=[] → driver sends
// responseModalities=["TEXT","IMAGE"] → the image arrives in the response.
// =============================================================================

type
  TGeminiImgDemo = class
  private
    FConn: TAiChatConnection;
    FDone: TEvent;

    procedure OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);
  public
    procedure Run;
  end;

procedure TGeminiImgDemo.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
var
  i: Integer;
  MF: TAiMediaFile;
begin
  for i := 0 to aMsg.MediaFiles.Count - 1 do
  begin
    MF := aMsg.MediaFiles[i];
    if MF.FileCategory = Tfc_Image then
    begin
      MF.SaveToFile(OutFile('demo3-gemini.png'));
      Writeln(Format(#13'    -> %s (%d KB)', [OutFile('demo3-gemini.png'),
        MF.Content.Size div 1024]));
    end;
  end;
  FDone.SetEvent;
end;

procedure TGeminiImgDemo.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  Writeln(#13'    [ERROR] ', ExtraerMensajeError(ErrorMsg));
  FDone.SetEvent;
end;

procedure TGeminiImgDemo.Run;
var
  SW: TStopwatch;
begin
  Writeln;
  Writeln('=== Demo 3: Native Gemini — gemini-2.5-flash-image ===');
  Writeln('  ModelCaps=[cap_Image,cap_GenImage] → Gap=[] → direct completions');

  FDone := TEvent.Create(nil, True, False, '');
  FConn := TAiChatConnection.Create(nil);
  try
    FConn.DriverName := 'Gemini';
    FConn.Model      := 'gemini-2.5-flash-image';
    FConn.Params.Values['Asynchronous'] := 'True';
    FConn.Params.Values['ApiKey']       := GEMINI_KEY;

    FConn.OnReceiveDataEnd := OnDataEnd;
    FConn.OnError          := OnError;

    Write('  Generating (native Gemini)...');
    SW := TStopwatch.StartNew;
    FConn.AddMessageAndRun(
      'Watercolor illustration of a futuristic city at dusk, ' +
      'purple and gold tones, fine architectural details',
      'user', []);

    while (FDone.WaitFor(0) = wrTimeout) and (SW.ElapsedMilliseconds < 90000) do
      CheckSynchronize(200);
    SW.Stop;

    Writeln(Format(' OK [%d ms]', [SW.ElapsedMilliseconds]));
  finally
    FConn.Free;
    FDone.Free;
  end;
end;

// =============================================================================
// Demo 4 — Google Imagen 4 (endpoint :predict)
//
// ModelCaps=[] / SessionCaps=[cap_GenImage] → Gap=[cap_GenImage]
// → InternalRunNativeImageGeneration → Gemini :predict endpoint
// =============================================================================

type
  TImagen4Demo = class
  private
    FConn:       TAiChatConnection;
    FDone:       TEvent;
    FErrorShown: Boolean;

    procedure OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);
  public
    procedure Run;
  end;

procedure TImagen4Demo.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
var
  i: Integer;
  MF: TAiMediaFile;
  LFound: Boolean;
begin
  LFound := False;
  for i := 0 to aMsg.MediaFiles.Count - 1 do
  begin
    MF := aMsg.MediaFiles[i];
    if MF.FileCategory = Tfc_Image then
    begin
      LFound := True;
      MF.SaveToFile(OutFile('demo4-imagen4.png'));
      Writeln(Format(#13'    -> %s (%d KB)', [OutFile('demo4-imagen4.png'),
        MF.Content.Size div 1024]));
    end;
  end;
  // Solo senalizar si hay imagen: si hay error, OnError lo senaalizara
  if LFound then FDone.SetEvent;
end;

procedure TImagen4Demo.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  // The :predict endpoint may trigger OnError twice; show only the first
  if not FErrorShown then
  begin
    FErrorShown := True;
    Writeln(#13'    [ERROR] ', ExtraerMensajeError(ErrorMsg));
  end;
  FDone.SetEvent;
end;

procedure TImagen4Demo.Run;
var
  SW: TStopwatch;
begin
  Writeln;
  Writeln('=== Demo 4: Google Imagen 4 — imagen-4.0-generate-001 ===');
  Writeln('  Internal bridge via endpoint :predict (aspect 16:9)');

  FDone := TEvent.Create(nil, True, False, '');
  FConn := TAiChatConnection.Create(nil);
  try
    FConn.DriverName := 'Gemini';
    FConn.Model      := 'imagen-4.0-generate-001';
    FConn.Params.Values['Asynchronous'] := 'True';
    FConn.Params.Values['ApiKey']       := GEMINI_KEY;
    FConn.Params.Values['aspectRatio']  := '16:9';

    FConn.OnReceiveDataEnd := OnDataEnd;
    FConn.OnError          := OnError;

    Write('  Generating Image 4 (~30 s)...');
    SW := TStopwatch.StartNew;
    FConn.AddMessageAndRun(
      'Realistic photograph of a snow-capped volcano at dawn with reflection in the lake, ' +
      'pink sky, ultra detail 4K',
      'user', []);

    while (FDone.WaitFor(0) = wrTimeout) and (SW.ElapsedMilliseconds < 120000) do
      CheckSynchronize(200);
    SW.Stop;

    Writeln(Format(' OK [%d ms]', [SW.ElapsedMilliseconds]));
  finally
    FConn.Free;
    FDone.Free;
  end;
end;

// =============================================================================
// Demo 5 — Video con TAiVeoGenerator
//
// GenerateFromText() returns ITask (real asynchronous).
// Task.Wait blocks until polling finishes and the video is ready.
// The OnProgress / OnSuccess / OnError callbacks fire from the thread
// of the task, before Task.Wait returns.
// =============================================================================

type
  TVeoDemo = class
  private
    FTieneError: Boolean;

    procedure OnProgress(Sender: TObject; const AStatus: string);
    procedure OnSuccess(Sender: TObject; ResultVideo: TAiMediaFile);
    procedure OnError(Sender: TObject; const AErrorMsg: string);
  public
    procedure Run;
  end;

procedure TVeoDemo.OnProgress(Sender: TObject; const AStatus: string);
begin
  Writeln(Format(#13'    [  ] %s', [AStatus]));
end;

procedure TVeoDemo.OnSuccess(Sender: TObject; ResultVideo: TAiMediaFile);
var
  ruta: string;
begin
  ruta := OutFile('demo5-arrecife.mp4');
  ResultVideo.SaveToFile(ruta);
  Writeln(Format(#13'    -> %s (%d KB)', [ruta, ResultVideo.bytes div 1024]));
end;

procedure TVeoDemo.OnError(Sender: TObject; const AErrorMsg: string);
begin
  FTieneError := True;
  Writeln(#13'    ERROR: ', ExtraerMensajeError(AErrorMsg));
end;

procedure TVeoDemo.Run;
var
  Veo:  TAiVeoGenerator;
  Task: ITask;
  SW:   TStopwatch;
begin
  Writeln;
  Writeln('=== Demo 5: TAiVeoGenerator — veo-3.1-generate-preview ===');
  Writeln('  Video 5 s, 720p, 16:9. May take up to 2 minutes.');

  FTieneError := False;
  Veo := TAiVeoGenerator.Create(nil);
  try
    Veo.ApiKey          := GEMINI_KEY;
    Veo.Model           := vmVeo3_1;
    Veo.AspectRatio     := ar16x9;
    Veo.Resolution      := vr720p;
    Veo.DurationSeconds := 5;

    Veo.OnProgress := OnProgress;
    Veo.OnSuccess  := OnSuccess;
    Veo.OnError    := OnError;

    Writeln('  Starting video generation...');
    SW   := TStopwatch.StartNew;
    Task := Veo.GenerateFromText(
      'A coral reef with colorful tropical fish in slow motion, ' +
      'soft and crystal-clear underwater light');

    // Task.Wait blocks until polling and download finish.
    Task.Wait;
    // Process pending callbacks in TThread.Queue (console without message pump)
    CheckSynchronize(0);
    SW.Stop;

    if not FTieneError then
      Writeln(Format('  Completed in %d s.', [SW.ElapsedMilliseconds div 1000]))
    else
      Writeln('  Finished with error (see above).');
  finally
    Veo.Free;
  end;
end;

// =============================================================================
// Punto de entrada
// =============================================================================

begin
  SetConsoleOutputCP(65001);
  Writeln('======================================================');
  Writeln(' MakerAI — Cap 14: Image and Video Generation');
  Writeln(' Demo 1: gpt-image-2  | Demo 2: gpt-image-1 (bridge)');
  Writeln(' Demo 3: Gemini flash | Demo 4: Imagen 4 | Demo 5: Veo');
  Writeln('======================================================');
  Writeln('Output: ', TPath.GetTempPath);
  Writeln;

  var TieneOpenAI := GetEnvironmentVariable('OPENAI_API_KEY') <> '';
  var TieneGemini := GetEnvironmentVariable('GEMINI_API_KEY') <> '';

  Writeln('  Environment status:');
  if TieneOpenAI then Writeln('  [OK] OPENAI_API_KEY') else Writeln('  [--] OPENAI_API_KEY not configured');
  if TieneGemini then Writeln('  [OK] GEMINI_API_KEY') else Writeln('  [--] GEMINI_API_KEY not configured');
  Writeln;

  if TieneOpenAI then
  begin
    try Demo1_GeneracionDirecta;
    except on E: Exception do Writeln('  [Demo 1 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else Writeln('--- Demo 1 skipped (OPENAI_API_KEY not configured) ---');

  if TieneOpenAI then
  begin
    try
      with TBridgeDemo.Create do try Run; finally Free; end;
    except on E: Exception do Writeln('  [Demo 2 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else Writeln('--- Demo 2 skipped (OPENAI_API_KEY not configured) ---');

  if TieneGemini then
  begin
    try
      with TGeminiImgDemo.Create do try Run; finally Free; end;
    except on E: Exception do Writeln('  [Demo 3 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else Writeln('--- Demo 3 skipped (GEMINI_API_KEY not configured) ---');

  if TieneGemini then
  begin
    try
      with TImagen4Demo.Create do try Run; finally Free; end;
    except on E: Exception do Writeln('  [Demo 4 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else Writeln('--- Demo 4 skipped (GEMINI_API_KEY not configured) ---');

  if TieneGemini then
  begin
    try
      with TVeoDemo.Create do try Run; finally Free; end;
    except on E: Exception do Writeln('  [Demo 5 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else Writeln('--- Demo 5 skipped (GEMINI_API_KEY not configured) ---');

  Writeln;
  Writeln('======================================================');
  Writeln('Demos finished. Press Enter to exit...');
  Readln;
end.
