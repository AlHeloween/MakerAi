unit uMainChatToolsOllamaDemo;

// Demo 013 - Ollama ChatTools (gemma3:4b)
// Demonstrates the main capabilities of ChatTools with Ollama:
// Mode 0: Chat + Functions (TAiFunctions: get_datetime, calculate, get_weather)
// Mode 1: Native vision (gemma3:4b analyzes images)
// Mode 2: Web Search (bridge via AiGeminiWebSearchTool)
// Mode 3: PDF (bridge via AiOllamaPdfTool / OCR)
// Mode 4: Generate Image (bridge via AiDalleImageTool / DALL-E)
// Mode 5: TTS - Text to Speech (bridge via AiGeminiSpeechTool)

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Net.HttpClient,
  System.IOUtils, System.JSON, System.Math, System.DateUtils, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Objects, FMX.WebBrowser, FMX.TabControl, FMX.StdCtrls, FMX.Layouts,
  FMX.Memo.Types, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo,
  FMX.ListBox,
  uMakerAi.Core, uMakerAi.Chat.Messages, uMakerAi.Chat.Tools,
  uMakerAi.OpenAI.Sora, uMakerAi.OpenAI.Dalle, uMakerAi.Ollama.Ocr,
  uMakerAi.Gemini.Speech, uMakerAi.Gemini.WebSearch,
  uMakerAi.Chat, uMakerAi.Chat.Ollama,
  uMakerAi.Utils.AudioPushStream,
  uMakerAi.Tools.Functions;

type
  TForm26 = class(TForm)
    AiOllamaChat1: TAiOllamaChat;
    AiGeminiWebSearchTool1: TAiGeminiWebSearchTool;
    AiGeminiSpeechTool1: TAiGeminiSpeechTool;
    AiOllamaPdfTool1: TAiOllamaOcrTool;
    AiDalleImageTool1: TAiDalleImageTool;
    AiSoraVideoTool1: TAiSoraVideoTool;
    Layout1: TLayout;
    Layout2: TLayout;
    Layout3: TLayout;
    Layout4: TLayout;
    Layout5: TLayout;
    Layout6: TLayout;
    Splitter1: TSplitter;
    Splitter2: TSplitter;
    TabControl1: TTabControl;
    TabWebItem: TTabItem;
    TImageItem: TTabItem;
    TabTexto: TTabItem;
    TabThinking: TTabItem;
    WebBrowser1: TWebBrowser;
    Image1: TImage;
    MemoTexto: TMemo;
    MemoThinking: TMemo;
    MemoChatList: TMemo;
    Label1: TLabel;
    MemoPrompt: TMemo;
    Label2: TLabel;
    ComboModo: TComboBox;
    BtnEnviar: TButton;
    BtnAdjuntar: TButton;
    BtnLimpiar: TButton;
    LblEstado: TLabel;
    OpenDialog1: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure AiOllamaChat1StateChange(Sender: TObject; State: TAiChatState; const Description: string);
    procedure AiOllamaChat1ReceiveThinking(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiOllamaChat1ReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiOllamaChat1ReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiOllamaChat1Error(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
    procedure AiOllamaChat1CallToolFunction(Sender: TObject; AiToolCall: TAiToolsFunction);
    procedure BtnEnviarClick(Sender: TObject);
    procedure BtnAdjuntarClick(Sender: TObject);
    procedure BtnLimpiarClick(Sender: TObject);
    procedure ComboModoChange(Sender: TObject);
  private
    FAudio: TAudioPushStream;
    FAiFunctions: TAiFunctions;
    FArchivoAdjunto: TAiMediaFile;
    FStreamBuffer: string;
    FUltimoTmpVideo: string;  // ruta del último video temporal (para limpieza)
    procedure InicializarFunciones;
    procedure ConfigurarModo(aModo: Integer);
    procedure AgregarAlChat(const aRol, aTexto: string);
    function SimpleCalc(const aExpr: string): string;
    procedure OnFnGetDateTime(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnCalculate(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnGetWeather(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    // Renderizado web
    procedure MostrarEnWebBrowser(const aContenido: string; aEsHtml: Boolean);
    function MarkdownParaHtml(const aMd: string): string;
    function EsHtml(const aTexto: string): Boolean;
    function EsMarkdown(const aTexto: string): Boolean;
    function ExtVideoDeFileType(const aMimeType, aFilename: string): string;
  public
  end;

var
  Form26: TForm26;

implementation

{$R *.fmx}
// -----------------------------------------------------------------------------
// Private helpers
// -----------------------------------------------------------------------------

procedure TForm26.AgregarAlChat(const aRol, aTexto: string);
begin
  if aRol <> '' then
    MemoChatList.Lines.Add('--- ' + aRol.ToUpper + ' ---');
  MemoChatList.Lines.Add(aTexto);
  MemoChatList.Lines.Add('');
  MemoChatList.GoToTextEnd;
end;

// Evaluator of two-operand expressions: A op B  (+, -, *, /)
function TForm26.SimpleCalc(const aExpr: string): string;
var
  LExpr: string;
  LPos, I: Integer;
  LLeft, LRight, LResult: Double;
  LOp: Char;
begin
  Result := 'Could not evaluate: ' + aExpr;
  LExpr := Trim(aExpr);
  LOp := #0;
  LPos := 0;

  // Search for + or - (low priority) from right to left
  for I := Length(LExpr) downto 2 do
    if CharInSet(LExpr[I], ['+', '-']) then
    begin
      LPos := I;
      LOp := LExpr[I];
      Break;
    end;

  // If not found, search for * or /
  if LPos = 0 then
    for I := Length(LExpr) downto 2 do
      if CharInSet(LExpr[I], ['*', '/']) then
      begin
        LPos := I;
        LOp := LExpr[I];
        Break;
      end;

  if (LPos = 0) or (LOp = #0) then
    Exit;
  if not TryStrToFloat(Trim(Copy(LExpr, 1, LPos - 1)), LLeft) then
    Exit;
  if not TryStrToFloat(Trim(Copy(LExpr, LPos + 1, MaxInt)), LRight) then
    Exit;

  case LOp of
    '+':
      LResult := LLeft + LRight;
    '-':
      LResult := LLeft - LRight;
    '*':
      LResult := LLeft * LRight;
    '/':
      if LRight <> 0 then
        LResult := LLeft / LRight
      else
      begin
        Result := 'Error: division by zero';
        Exit;
      end;
  else
    Exit;
  end;
  Result := FloatToStr(LResult);
end;

// -----------------------------------------------------------------------------
// TAiFunctions handlers
// -----------------------------------------------------------------------------

procedure TForm26.OnFnGetDateTime(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LFmt: string;
  LNow: TDateTime;
  LFmtVal: TJSONValue;
begin
  LNow := Now;
  LFmt := 'yyyy-mm-dd hh:nn:ss';
  var LArgsD := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsD) then
  try
    LFmtVal := LArgsD.GetValue('format');
    if Assigned(LFmtVal) then
      LFmt := LFmtVal.Value;
  finally
    LArgsD.Free;
  end;
  ToolCall.Response := '{"datetime":"' + FormatDateTime(LFmt, LNow) + '","timestamp":' + IntToStr(DateTimeToUnix(LNow)) + ',"day_of_week":"' + FormatDateTime('dddd', LNow) + '"}';
  Handled := True;
end;

procedure TForm26.OnFnCalculate(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LExpr: string;
  LVal: TJSONValue;
begin
  LExpr := '';
  var LArgsC := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsC) then
  try
    LVal := LArgsC.GetValue('expression');
    if Assigned(LVal) then
      LExpr := LVal.Value;
  finally
    LArgsC.Free;
  end;
  ToolCall.Response := '{"expression":"' + LExpr + '","result":"' + SimpleCalc(LExpr) + '"}';
  Handled := True;
end;

procedure TForm26.OnFnGetWeather(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  LCity: string;
  LTemp: Integer;
  LVal: TJSONValue;
  LConds: array [0 .. 3] of string;
begin
  LCity := 'ciudad desconocida';
  var LArgsW := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(LArgsW) then
  try
    LVal := LArgsW.GetValue('city');
    if Assigned(LVal) then
      LCity := LVal.Value;
  finally
    LArgsW.Free;
  end;
  LTemp := 10 + Random(28);
  LConds[0] := 'Soleado';
  LConds[1] := 'Nublado';
  LConds[2] := 'Parcialmente nublado';
  LConds[3] := 'Lluvia ligera';
  ToolCall.Response := Format('{"city":"%s","temperature_c":%d,"condition":"%s","humidity":%d,"wind_kmh":%d}', [LCity, LTemp, LConds[Random(4)], 40 + Random(50), 5 + Random(35)]);
  Handled := True;
end;

// -----------------------------------------------------------------------------
// Initialization of TAiFunctions with 3 tools
// -----------------------------------------------------------------------------

procedure TForm26.InicializarFunciones;
var
  LFn: TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  FAiFunctions := TAiFunctions.Create(Self);

  // Tool 1: get_datetime
  LFn := FAiFunctions.Functions.AddFunction('get_datetime', True, OnFnGetDateTime);
  LFn.Description.Text := 'Gets the current date and time of the system.';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'format';
  LParam.ParamType := ptString;
  LParam.Required := False;
  LParam.Description.Text := 'Output format. Default: yyyy-mm-dd hh:nn:ss';

  // Tool 2: calculate
  LFn := FAiFunctions.Functions.AddFunction('calculate', True, OnFnCalculate);
  LFn.Description.Text := 'Calculates a basic mathematical expression with two operands (+, -, *, /).';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'expression';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam.Description.Text := 'Expression to calculate. Examples: 256 * 7, 100 / 4, 1500 + 200';

  // Tool 3: get_weather
  LFn := FAiFunctions.Functions.AddFunction('get_weather', True, OnFnGetWeather);
  LFn.Description.Text := 'Gets the current weather of a city (simulated data for demo).';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'city';
  LParam.ParamType := ptString;
  LParam.Required := True;
  LParam.Description.Text := 'Name of the city. Examples: Buenos Aires, Madrid, Mexico City';

  AiOllamaChat1.AiFunctions := FAiFunctions;
end;

// -----------------------------------------------------------------------------
// Mode configuration
// -----------------------------------------------------------------------------

procedure TForm26.ConfigurarModo(aModo: Integer);
begin
  FreeAndNil(FArchivoAdjunto);
  FStreamBuffer := '';
  MemoTexto.Lines.Clear;
  MemoThinking.Lines.Clear;

  AiOllamaChat1.Model := 'gemma3:4b';
  AiOllamaChat1.Asynchronous := True;
  AiOllamaChat1.Tool_Active := False;
  AiOllamaChat1.ModelConfig.ModelCaps := [];
  AiOllamaChat1.ModelConfig.SessionCaps := [];
  BtnAdjuntar.Enabled := False;

  case aModo of
    0: // Chat + Funciones
      begin
        AiOllamaChat1.Tool_Active := True;
        LblEstado.Text := 'Mode 0: Chat + Functions';
        Label2.Text := 'Test: "What time is it?" / "Calculate 256 * 7" / "Weather in Buenos Aires?"';
        AgregarAlChat('', '=== Chat + Functions (get_datetime, calculate, get_weather) ===');
      end;

    1: // Vision nativa
      begin
        AiOllamaChat1.ModelConfig.ModelCaps := [cap_Image];
        AiOllamaChat1.ModelConfig.SessionCaps := [cap_Image];
        BtnAdjuntar.Enabled := True;
        LblEstado.Text := 'Mode 1: Vision (gemma3:4b)';
        Label2.Text := 'Attach an image (JPG/PNG/WebP) and ask a question about it.';
        AgregarAlChat('', '=== Vision: gemma3:4b analyzes images natively ===');
      end;

    2: // Web Search (bridge Gemini)
      begin
        AiOllamaChat1.ModelConfig.SessionCaps := [cap_WebSearch];
        LblEstado.Text := 'Mode 2: Web Search (Gemini bridge)';
        Label2.Text := 'Ask about current events or recent information.';
        AgregarAlChat('', '=== Web Search: grounding via Gemini + response with gemma3:4b ===');
      end;

    3: // PDF (bridge Ollama OCR)
      begin
        AiOllamaChat1.ModelConfig.SessionCaps := [cap_Pdf];
        BtnAdjuntar.Enabled := True;
        LblEstado.Text := 'Mode 3: PDF (Ollama OCR bridge)';
        Label2.Text := 'Attach a PDF and ask questions about its content.';
        AgregarAlChat('', '=== PDF: OCR via Ollama + analysis with gemma3:4b ===');
      end;

    4: // Generar Imagen (bridge DALL-E)
      begin
        AiOllamaChat1.ModelConfig.SessionCaps := [cap_GenImage];
        LblEstado.Text := 'Mode 4: Generate Image (DALL-E bridge)';
        Label2.Text := 'Describe the image to generate. Requires OPENAI_API_KEY.';
        AgregarAlChat('', '=== Image Generation: gemma3:4b refines prompt + DALL-E generates ===');
      end;

    5: // TTS (bridge Gemini Speech)
      begin
        AiOllamaChat1.ModelConfig.SessionCaps := [cap_GenAudio];
        LblEstado.Text := 'Mode 5: Text to Speech (Gemini Speech bridge)';
        Label2.Text := 'Write the text you want to hear. Requires GEMINI_API_KEY.';
        AgregarAlChat('', '=== TTS: gemma3:4b prepares text + Gemini Speech converts it to voice ===');
      end;
  end;
end;

// -----------------------------------------------------------------------------
// Form events
// -----------------------------------------------------------------------------

procedure TForm26.FormCreate(Sender: TObject);
begin
  Caption := 'Demo 013 - Ollama ChatTools (gemma3:4b)';
  FAudio := TAudioPushStream.Create;
  InicializarFunciones;
  ConfigurarModo(0);
  ComboModo.ItemIndex := 0;
end;

procedure TForm26.FormDestroy(Sender: TObject);
begin
  FAudio.Stop;
  FreeAndNil(FAudio);
  FreeAndNil(FArchivoAdjunto);
  // Limpiar video temporal
  if (FUltimoTmpVideo <> '') and TFile.Exists(FUltimoTmpVideo) then
    TFile.Delete(FUltimoTmpVideo);
end;

// -----------------------------------------------------------------------------
// Eventos de UI
// -----------------------------------------------------------------------------

procedure TForm26.BtnEnviarClick(Sender: TObject);
var
  LPrompt: string;
  LMedia: TAiMediaFilesArray;
begin
  LPrompt := Trim(MemoPrompt.Text);
  if LPrompt = '' then
    Exit;

  FStreamBuffer := '';
  MemoTexto.Lines.Clear;
  SetLength(LMedia, 0);
  if Assigned(FArchivoAdjunto) then
  begin
    SetLength(LMedia, 1);
    LMedia[0] := FArchivoAdjunto;
  end;

  AgregarAlChat('Usuario', LPrompt);
  MemoPrompt.Text := '';

  AiOllamaChat1.AddMessageAndRun(LPrompt, 'user', LMedia);

  // The session takes ownership of the media file, clear local reference
  FArchivoAdjunto := nil;
end;

procedure TForm26.BtnAdjuntarClick(Sender: TObject);
var
  LModo: Integer;
begin
  LModo := ComboModo.ItemIndex;
  OpenDialog1.Filter := '';
  if LModo = 1 then
    OpenDialog1.Filter := 'Imagenes|*.jpg;*.jpeg;*.png;*.gif;*.webp;*.bmp|'
  else if LModo = 3 then
    OpenDialog1.Filter := 'Documentos PDF|*.pdf|';
  OpenDialog1.Filter := OpenDialog1.Filter + 'Todos los archivos|*.*';

  if not OpenDialog1.Execute then
    Exit;

  FreeAndNil(FArchivoAdjunto);
  FArchivoAdjunto := TAiMediaFile.Create;
  FArchivoAdjunto.LoadFromFile(OpenDialog1.FileName);
  AgregarAlChat('Sistema', 'Attachment: ' + System.IOUtils.TPath.GetFileName(OpenDialog1.FileName));
  LblEstado.Text := 'File ready: ' + System.IOUtils.TPath.GetFileName(OpenDialog1.FileName);
end;

procedure TForm26.BtnLimpiarClick(Sender: TObject);
begin
  AiOllamaChat1.NewChat;
  FreeAndNil(FArchivoAdjunto);
  FStreamBuffer := '';
  MemoChatList.Lines.Clear;
  MemoThinking.Lines.Clear;
  MemoTexto.Lines.Clear;
  Image1.Bitmap.SetSize(0, 0);
  FAudio.Stop;
  ConfigurarModo(ComboModo.ItemIndex);
end;

procedure TForm26.ComboModoChange(Sender: TObject);
begin
  AiOllamaChat1.NewChat;
  MemoChatList.Lines.Clear;
  ConfigurarModo(ComboModo.ItemIndex);
end;

// -----------------------------------------------------------------------------
// TAiOllamaChat events
// -----------------------------------------------------------------------------

procedure TForm26.AiOllamaChat1StateChange(Sender: TObject; State: TAiChatState; const Description: string);
var
  LEnabled: Boolean;
begin
  LEnabled := State in [acsIdle, acsFinished, acsError, acsAborted];
  BtnEnviar.Enabled := LEnabled;
  BtnLimpiar.Enabled := LEnabled;
  ComboModo.Enabled := LEnabled;
  BtnAdjuntar.Enabled := LEnabled and (ComboModo.ItemIndex in [1, 3]);

  case State of
    acsConnecting:
      LblEstado.Text := 'Connecting...';
    acsReasoning:
      LblEstado.Text := 'Reasoning...';
    acsWriting:
      LblEstado.Text := 'Generating response...';
    acsToolCalling:
      LblEstado.Text := 'Calling tool: ' + Description;
    acsToolExecuting:
      LblEstado.Text := 'Executing: ' + Description;
    acsFinished:
      LblEstado.Text := 'Ready';
    acsError:
      LblEstado.Text := 'Error';
    acsAborted:
      LblEstado.Text := 'Aborted';
  end;
end;

procedure TForm26.AiOllamaChat1ReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  FStreamBuffer := FStreamBuffer + aText;
  MemoTexto.Text := FStreamBuffer;
  MemoTexto.GoToTextEnd;
  if TabControl1.ActiveTab <> TabTexto then
    TabControl1.ActiveTab := TabTexto;
end;

procedure TForm26.AiOllamaChat1ReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
var
  MF: TAiMediaFile;
  LTexto: string;
  LStream: TMemoryStream;
  LBmp: TBitmap;
  LExt, LTmpFile: string;
begin
  LTexto := aText;
  if (LTexto = '') and (FStreamBuffer <> '') then
    LTexto := FStreamBuffer;

  MemoTexto.Lines.Clear;
  FStreamBuffer := '';

  // Decide how to show the response text
  if LTexto <> '' then
  begin
    if EsHtml(LTexto) then
    begin
      // Pure HTML → render in WebBrowser
      MostrarEnWebBrowser(LTexto, True);
      AgregarAlChat('IA', '[HTML generado - ver pestana Web]');
    end
    else if EsMarkdown(LTexto) then
    begin
      // Markdown → convert to HTML and render in WebBrowser
      MostrarEnWebBrowser(MarkdownParaHtml(LTexto), True);
      AgregarAlChat('IA', '[Markdown generado - ver pestana Web]');
    end
    else
    begin
      // Plain text → normal history
      AgregarAlChat('IA', LTexto);
    end;
  end;

  // Process media files in the response
  for MF in aMsg.MediaFiles do
  begin
    case MF.FileCategory of

      Tfc_Image:
        begin
          LStream := TMemoryStream.Create;
          try
            MF.Content.Position := 0;
            LStream.CopyFrom(MF.Content, 0);
            LStream.Position := 0;
            LBmp := TBitmap.Create;
            try
              LBmp.LoadFromStream(LStream);
              Image1.Bitmap.Assign(LBmp);
            finally
              LBmp.Free;
            end;
          finally
            LStream.Free;
          end;
          TabControl1.ActiveTab := TImageItem;
          AgregarAlChat('Sistema', '[Generated image - see Image tab]');
        end;

      Tfc_Audio:
        begin
          MF.Content.Position := 0;
          FAudio.PushWavData(MF.Content);
          AgregarAlChat('Sistema', '[TTS audio playing...]');
        end;

      Tfc_Video:
        begin
          // Save to temporary disk and render with WebBrowser
          LExt := ExtVideoDeFileType(MF.MimeType, MF.filename);
          LTmpFile := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
            'mkrai_video_' + IntToStr(DateTimeToUnix(Now)) + LExt);
          // Delete previous if it exists
          if (FUltimoTmpVideo <> '') and TFile.Exists(FUltimoTmpVideo) then
            TFile.Delete(FUltimoTmpVideo);
          FUltimoTmpVideo := LTmpFile;
          MF.Content.Position := 0;
          MF.Content.SaveToFile(LTmpFile);
          WebBrowser1.Navigate(LTmpFile);
          TabControl1.ActiveTab := TabWebItem;
          AgregarAlChat('Sistema', '[Video saved: ' + System.IOUtils.TPath.GetFileName(LTmpFile) + ']');
        end;

      Tfc_Web:
        begin
          // HTML/web file: navigate or save to temp and open
          if MF.FullFileName <> '' then
            WebBrowser1.Navigate(MF.FullFileName)
          else if (MF.Content <> nil) and (MF.Content.Size > 0) then
          begin
            // Save to temp and navigate
            LTmpFile := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
              'mkrai_web_' + IntToStr(DateTimeToUnix(Now)) + '.html');
            MF.Content.Position := 0;
            MF.Content.SaveToFile(LTmpFile);
            WebBrowser1.Navigate('file:///' + LTmpFile.Replace('\', '/'));
          end;
          TabControl1.ActiveTab := TabWebItem;
          AgregarAlChat('Sistema', '[Web content - see Web tab]');
        end;

    end;
  end;
end;

procedure TForm26.AiOllamaChat1ReceiveThinking(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  MemoThinking.Lines.Add(aText);
  MemoThinking.GoToTextEnd;
  if TabControl1.ActiveTab <> TabThinking then
    TabControl1.ActiveTab := TabThinking;
end;

procedure TForm26.AiOllamaChat1Error(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
begin
  AgregarAlChat('Error', ErrorMsg);
  LblEstado.Text := 'Error';

  AiOllamaChat1StateChange(Self, TAiChatState.acsError, ErrorMsg);
end;

procedure TForm26.AiOllamaChat1CallToolFunction(Sender: TObject; AiToolCall: TAiToolsFunction);
begin
  // Fallback: function not found in FAiFunctions
  AgregarAlChat('Herramienta', 'Function not implemented: ' + AiToolCall.Name);
  AiToolCall.Response := '{"error":"Function not implemented: ' + AiToolCall.Name + '"}';
end;

// -----------------------------------------------------------------------------
// Web rendering helpers
// -----------------------------------------------------------------------------

function TForm26.EsHtml(const aTexto: string): Boolean;
var
  LTrim: string;
begin
  LTrim := LowerCase(TrimLeft(aTexto));
  Result := LTrim.StartsWith('<!doctype') or
            LTrim.StartsWith('<html') or
            (LTrim.Contains('<head') and LTrim.Contains('<body'));
end;

function TForm26.EsMarkdown(const aTexto: string): Boolean;
begin
  // Detects markdown by presence of common patterns
  Result := aTexto.Contains('```') or
            aTexto.Contains('**') or
            aTexto.Contains('## ') or
            (aTexto.StartsWith('# ') and (Pos(sLineBreak, aTexto) > 0)) or
            (aTexto.StartsWith('- ') and (Pos(sLineBreak, aTexto) > 0));
end;

function TForm26.ExtVideoDeFileType(const aMimeType, aFilename: string): string;
begin
  // Try by file name first
  Result := LowerCase(ExtractFileExt(aFilename));
  if Result <> '' then Exit;
  // Determine extension by MIME type
  if aMimeType.Contains('mp4') then Result := '.mp4'
  else if aMimeType.Contains('webm') then Result := '.webm'
  else if aMimeType.Contains('ogg') then Result := '.ogv'
  else if aMimeType.Contains('quicktime') then Result := '.mov'
  else Result := '.mp4'; // fallback
end;

// Saves the content in a temporary HTML file and navigates with WebBrowser
procedure TForm26.MostrarEnWebBrowser(const aContenido: string; aEsHtml: Boolean);
var
  LFile: string;
begin
  LFile := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
    'mkrai_render_' + IntToStr(DateTimeToUnix(Now)) + '.html');
  TFile.WriteAllText(LFile, aContenido, TEncoding.UTF8);
  WebBrowser1.Navigate('file:///' + LFile.Replace('\', '/'));
  TabControl1.ActiveTab := TabWebItem;
end;

// Converts basic Markdown to HTML with minimal styles
function TForm26.MarkdownParaHtml(const aMd: string): string;
var
  LLineas: TStringList;
  LSB: TStringBuilder;
  LLinea, LTrim: string;
  LEnBloque: Boolean;
  I: Integer;
begin
  LLineas := TStringList.Create;
  LSB := TStringBuilder.Create;
  try
    LLineas.Text := aMd;
    LEnBloque := False;

    LSB.Append('<!DOCTYPE html><html><head><meta charset="UTF-8">');
    LSB.Append('<style>');
    LSB.Append('body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;');
    LSB.Append('max-width:900px;margin:20px auto;padding:0 16px;line-height:1.6;color:#333;}');
    LSB.Append('pre{background:#f6f8fa;border:1px solid #e1e4e8;border-radius:6px;');
    LSB.Append('padding:12px;overflow:auto;font-size:14px;}');
    LSB.Append('code{background:#f6f8fa;padding:2px 5px;border-radius:3px;font-size:90%;}');
    LSB.Append('h1,h2,h3,h4{margin-top:1.2em;margin-bottom:0.4em;}');
    LSB.Append('blockquote{border-left:4px solid #dfe2e5;margin:0;padding:0 1em;color:#6a737d;}');
    LSB.Append('table{border-collapse:collapse;width:100%;}');
    LSB.Append('th,td{border:1px solid #dfe2e5;padding:6px 12px;}');
    LSB.Append('th{background:#f6f8fa;}');
    LSB.Append('</style></head><body>');

    for I := 0 to LLineas.Count - 1 do
    begin
      LLinea := LLineas[I];
      LTrim := Trim(LLinea);

      // Bloque de código
      if LTrim.StartsWith('```') then
      begin
        if LEnBloque then
        begin
          LSB.Append('</code></pre>');
          LEnBloque := False;
        end
        else
        begin
          LSB.Append('<pre><code>');
          LEnBloque := True;
        end;
        Continue;
      end;

      if LEnBloque then
      begin
        // Escape HTML inside the block
        LLinea := LLinea.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;');
        LSB.Append(LLinea + sLineBreak);
        Continue;
      end;

      // Encabezados
      if LTrim.StartsWith('#### ') then
        LSB.Append('<h4>' + Copy(LTrim, 6, MaxInt) + '</h4>')
      else if LTrim.StartsWith('### ') then
        LSB.Append('<h3>' + Copy(LTrim, 5, MaxInt) + '</h3>')
      else if LTrim.StartsWith('## ') then
        LSB.Append('<h2>' + Copy(LTrim, 4, MaxInt) + '</h2>')
      else if LTrim.StartsWith('# ') then
        LSB.Append('<h1>' + Copy(LTrim, 3, MaxInt) + '</h1>')
      // Separador horizontal
      else if (LTrim = '---') or (LTrim = '***') or (LTrim = '___') then
        LSB.Append('<hr>')
      // Elemento de lista
      else if LTrim.StartsWith('- ') or LTrim.StartsWith('* ') then
        LSB.Append('<li>' + Copy(LTrim, 3, MaxInt) + '</li>')
      else if LTrim.StartsWith('> ') then
        LSB.Append('<blockquote>' + Copy(LTrim, 3, MaxInt) + '</blockquote>')
      else if LTrim = '' then
        LSB.Append('<br>')
      else
      begin
        // Paragraph line: show as <p>
        // Note: inline conversion (bold/italic) would require regex; plain text is shown
        LSB.Append('<p>' + LTrim + '</p>');
      end;
    end;

    if LEnBloque then
      LSB.Append('</code></pre>');

    LSB.Append('</body></html>');
    Result := LSB.ToString;
  finally
    LLineas.Free;
    LSB.Free;
  end;
end;

end.
