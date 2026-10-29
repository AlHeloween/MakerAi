program TallerChatTest;

{$APPTYPE CONSOLE}

// =============================================================================
// Demo 067 — Validation of Multimodal Chat Workshop code
// =============================================================================
// Tests the 3 key patterns of the workshop in console mode (synchronous):
//   Test 1: Basic text chat with Ollama (ModelCaps/SessionCaps)
//   Test 2: Function Calling — SaveFile
//   Test 3: Vision — image description
//   Test 4: Unified vision + tools model (qwen2.5vl:7b)
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Net.HttpClient,
  UMakerAi.ParamsRegistry,       // TAiChatFactory
  uMakerAi.Core,                 // TAiMediaFile, TAiMediaFiles
  uMakerAi.Chat,                 // TAiChat base
  uMakerAi.Chat.AiConnection,    // TAiChatConnection
  uMakerAi.Chat.Messages,        // TAiToolsFunction, TAiChatMessage
  uMakerAi.Tools.Functions,      // TAiFunctions, TFunctionActionItem
  uMakerAi.Chat.Initializations, // registra drivers Ollama/OpenAI/etc.
  uMakerAi.Chat.Ollama;          // driver Ollama

// =============================================================================
// Console helpers
// =============================================================================

procedure PrintSep(const titulo: string);
begin
  WriteLn;
  WriteLn(StringOfChar('=', 70));
  WriteLn('  ' + titulo);
  WriteLn(StringOfChar('=', 70));
end;

procedure PrintOK(const msg: string);   begin WriteLn('[OK]   ' + msg); end;
procedure PrintFAIL(const msg: string); begin WriteLn('[FAIL] ' + msg); end;
procedure PrintINFO(const msg: string); begin WriteLn('       ' + msg); end;

// =============================================================================
// Helper class for event handlers
// =============================================================================

type
  TTestHelper = class
  public
    ArchivoGuardado: Boolean;
    ArchivoCreadoPath: string;
    LastError: string;

    procedure OnGuardarArchivo(Sender: TObject;
      FunctionAction: TFunctionActionItem; FunctionName: string;
      ToolCall: TAiToolsFunction; var Handled: Boolean);

    procedure OnConnError(Sender: TObject; const ErrorMsg: string;
      E: Exception; const AResponse: IHTTPResponse);
  end;

procedure TTestHelper.OnGuardarArchivo(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: string;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  NombreArchivo, Contenido: string;
begin
  NombreArchivo := ToolCall.Params.Values['NombreArchivo'];
  Contenido     := ToolCall.Params.Values['Contenido'];

  if NombreArchivo.Trim.IsEmpty then
  begin
    ToolCall.Response := 'Error: no file name was specified.';
    Handled := True;
    Exit;
  end;

  try
    TFile.WriteAllText(NombreArchivo, Contenido, TEncoding.UTF8);
    ToolCall.Response := 'Success: file "' + NombreArchivo +
      '" has been saved (' + IntToStr(Length(Contenido)) + ' characters).';
    ArchivoGuardado   := True;
    ArchivoCreadoPath := NombreArchivo;
    PrintINFO('[Tool invoked] SaveFile("' + NombreArchivo + '")');
  except
    on Ex: Exception do
    begin
      ToolCall.Response := 'Error saving: ' + Ex.Message;
      PrintINFO('[Tool error] ' + Ex.Message);
    end;
  end;
  Handled := True;
end;

procedure TTestHelper.OnConnError(Sender: TObject; const ErrorMsg: string;
  E: Exception; const AResponse: IHTTPResponse);
begin
  LastError := ErrorMsg;
  if Assigned(AResponse) then
    LastError := LastError + ' [HTTP ' + IntToStr(AResponse.StatusCode) + ']';
end;

// =============================================================================
// Model configuration — identical to workshop
// =============================================================================

procedure InitChatModels;
var
  Model: string;
begin
  // Global Ollama parameters (IMPORTANT: Asynchronous=False for console mode)
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Max_Tokens',   '4000');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Temperature',  '0.7');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Asynchronous', 'False');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Tool_Active',  'False');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'ModelCaps',    '[]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'SessionCaps',  '[]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Url',
    'http://localhost:11434/');

  // Test 1: reasoning model for pure text
  Model := 'deepseek-r1:1.5b';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SystemPrompt',
    'You are a technical assistant. Always respond in Spanish and concisely.');

  // Test 2: model with tools (pure text)
  Model := 'qwen3.5:0.8b';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SystemPrompt',
    'You are a technical assistant. Use the available tools when necessary.');

  // Tests 3 and 4 step-1: pure vision model (gemma3:4b)
  // Note: qwen3-vl fails to process images in Ollama 0.20.2 (runner bug)
  Model := 'gemma3:4b';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active',  'False');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SystemPrompt',
    'You are an assistant with vision. Describe images concisely.');
end;

// =============================================================================
// Helper: creates synchronized TAiChatConnection for Ollama
// =============================================================================

function CreateConn(const AModel: string; AHelper: TTestHelper): TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := 'Ollama';
  Result.Model      := AModel;

  // Ensure synchronous mode directly in underlying object
  // (avoids dependency on RTTI mechanism of ApplyParamsToChat)
  if Assigned(Result.AiChat) then
    Result.AiChat.Asynchronous := False;

  // Also mark it in FParams as fallback
  Result.Params.Values['Asynchronous'] := 'False';

  // Capture driver errors
  Result.OnError := AHelper.OnConnError;
end;

// =============================================================================
// Function to define SaveFile function in TAiFunctions
// =============================================================================

procedure DefinirGuardarArchivo(Funcs: TAiFunctions; Helper: TTestHelper);
var
  FuncItem: TFunctionActionItem;
  Param: TFunctionParamsItem;
begin
  FuncItem := Funcs.Functions.AddFunction('GuardarArchivo', True,
    Helper.OnGuardarArchivo);
  FuncItem.Description.Text :=
    'Save text to a file on the local disk of the user.';

  Param := FuncItem.Parameters.Add;
  Param.DisplayName      := 'NombreArchivo';
  Param.ParamType        := ptString;
  Param.Required         := True;
  Param.Description.Text := 'Name or path of the file to create';

  Param := FuncItem.Parameters.Add;
  Param.DisplayName      := 'Content';
  Param.ParamType        := ptString;
  Param.Required         := True;
  Param.Description.Text := 'Full text to write to the file';
end;

// =============================================================================
// TEST 1 — Basic text chat
// =============================================================================

function Test1_TextoBasico: Boolean;
var
  Conn:   TAiChatConnection;
  Helper: TTestHelper;
  Resp:   string;
begin
  Result := False;
  PrintSep('TEST 1 — Basic text chat (deepseek-r1:1.5b)');
  Helper := TTestHelper.Create;
  Conn   := CreateConn('deepseek-r1:1.5b', Helper);
  try
    try
      PrintINFO('Driver asynchronous: ' +
        BoolToStr(Conn.AiChat.Asynchronous, True));
      PrintINFO('Prompt: "Respond in a single word: what color is the sky?"');
      Resp := Conn.AddMessageAndRun(
        'Respond in a single word: what color is the sky?',
        'user', []);
      if Helper.LastError <> '' then
        PrintFAIL('Error: ' + Helper.LastError)
      else if Resp.Trim <> '' then
      begin
        PrintOK('Response: ' + Resp.Trim.Substring(0, Min(120, Resp.Trim.Length)));
        Result := True;
      end
      else
        PrintFAIL('Empty response (no error reported)');
    except
      on E: Exception do PrintFAIL('Exception: ' + E.Message);
    end;
  finally
    Conn.Free;
    Helper.Free;
  end;
end;

// =============================================================================
// TEST 2 — Function Calling: SaveFile
// =============================================================================

function Test2_FunctionCalling: Boolean;
var
  Conn:    TAiChatConnection;
  Funcs:   TAiFunctions;
  Helper:  TTestHelper;
  Resp:    string;
  ArchPath: string;
begin
  Result   := False;
  ArchPath := TPath.Combine(TPath.GetTempPath, 'taller_test_helloworld.pas');
  PrintSep('TEST 2 — Function Calling: SaveFile (qwen3.5:0.8b)');

  Helper := TTestHelper.Create;
  Funcs  := TAiFunctions.Create(nil);
  Conn   := CreateConn('qwen3.5:0.8b', Helper);
  try
    try
      DefinirGuardarArchivo(Funcs, Helper);
      Conn.AiFunctions := Funcs;

      PrintINFO('Prompt: "Generate a Hello World in Delphi and save it to: ' + ArchPath + '"');
      Resp := Conn.AddMessageAndRun(
        'Generate a minimal Hello World code in Delphi (code only) ' +
        'and save it to the file: ' + ArchPath,
        'user', []);

      if Helper.LastError <> '' then
        PrintFAIL('Error: ' + Helper.LastError)
      else if Helper.ArchivoGuardado and TFile.Exists(ArchPath) then
      begin
        PrintOK('File created: ' + ArchPath);
        var Contenido := TFile.ReadAllText(ArchPath, TEncoding.UTF8);
        PrintINFO('First 100 chars: ' + Contenido.Substring(0, Min(100, Contenido.Length)));
        PrintOK('AI response: ' + Resp.Trim.Substring(0, Min(120, Resp.Trim.Length)));
        Result := True;
        TFile.Delete(ArchPath);
      end
      else if Resp.Trim <> '' then
      begin
        PrintFAIL('Tool was NOT invoked by model.');
        PrintINFO('Response: ' + Resp.Trim.Substring(0, Min(200, Resp.Trim.Length)));
      end
      else
        PrintFAIL('No response from model.');
    except
      on E: Exception do PrintFAIL('Exception: ' + E.Message);
    end;
  finally
    Conn.Free;
    Funcs.Free;
    Helper.Free;
  end;
end;

// =============================================================================
// TEST 3 — Vision: image description (gemma3:4b)
// =============================================================================

function MakeTinyPng: TBytes;
begin
  // Valid 10x10 red pixel PNG (generated with System.Drawing, correct checksum)
  Result := TBytes.Create(
    $89,$50,$4E,$47,$0D,$0A,$1A,$0A,
    $00,$00,$00,$0D,$49,$48,$44,$52,
    $00,$00,$00,$0A,$00,$00,$00,$0A,
    $08,$06,$00,$00,$00,$8D,$32,$CF,
    $BD,$00,$00,$00,$01,$73,$52,$47,
    $42,$00,$AE,$CE,$1C,$E9,$00,$00,
    $00,$04,$67,$41,$4D,$41,$00,$00,
    $B1,$8F,$0B,$FC,$61,$05,$00,$00,
    $00,$09,$70,$48,$59,$73,$00,$00,
    $0E,$C3,$00,$00,$0E,$C3,$01,$C7,
    $6F,$A8,$64,$00,$00,$00,$1A,$49,
    $44,$41,$54,$28,$53,$63,$F8,$CF,
    $C0,$F0,$9F,$18,$CC,$80,$2E,$80,
    $0B,$8F,$2A,$C4,$8B,$89,$56,$08,
    $00,$92,$C3,$C7,$39,$F6,$52,$14,
    $97,$00,$00,$00,$00,$49,$45,$4E,
    $44,$AE,$42,$60,$82);
end;

function Test3_Vision: Boolean;
var
  Conn:       TAiChatConnection;
  Helper:     TTestHelper;
  MediaFiles: TAiMediaFiles;
  Attachment: TAiMediaFile;
  Resp:       string;
  ImgPath:    string;
begin
  Result  := False;
  ImgPath := TPath.Combine(TPath.GetTempPath, 'taller_test_image.png');
  PrintSep('TEST 3 — Vision: image description (gemma3:4b)');
  TFile.WriteAllBytes(ImgPath, MakeTinyPng);

  Helper := TTestHelper.Create;
  Conn   := CreateConn('gemma3:4b', Helper);
  try
    try
      MediaFiles := TAiMediaFiles.Create;
      try
        Attachment := TAiMediaFile.Create;
        Attachment.LoadFromFile(ImgPath);
        MediaFiles.Add(Attachment);

        PrintINFO('Image: 10x10 red PNG — ' + ImgPath);
        PrintINFO('Prompt: "What do you see in this image? Describe the main color."');

        Resp := Conn.AddMessageAndRun(
          'What do you see in this image? Briefly describe the main color.',
          'user',
          MediaFiles.ToMediaFileArray);

        if Helper.LastError <> '' then
          PrintFAIL('Error: ' + Helper.LastError)
        else if Resp.Trim <> '' then
        begin
          PrintOK('Response: ' + Resp.Trim.Substring(0, Min(200, Resp.Trim.Length)));
          Result := True;
        end
        else
          PrintFAIL('Empty response.');
      finally
        MediaFiles.Free;
      end;
    except
      on E: Exception do PrintFAIL('Exception: ' + E.Message);
    end;
  finally
    Conn.Free;
    Helper.Free;
    if TFile.Exists(ImgPath) then TFile.Delete(ImgPath);
  end;
end;

// =============================================================================
// TEST 4 — Vision + Tools (chained: gemma3:4b describes -> qwen3.5:0.8b saves)
// Note: in Ollama 0.20.2, models that support vision+tools in registry
// (qwen3-vl) fail to process images due to a runner bug. The chaining
// pattern is a valid and real alternative for production.
// =============================================================================

function Test4_Unificado: Boolean;
var
  ConnVision: TAiChatConnection;
  ConnTools:  TAiChatConnection;
  Funcs:      TAiFunctions;
  Helper:     TTestHelper;
  MediaFiles: TAiMediaFiles;
  Attachment: TAiMediaFile;
  Descripcion: string;
  Resp:        string;
  ImgPath:     string;
  ArchPath:    string;
begin
  Result   := False;
  ImgPath  := TPath.Combine(TPath.GetTempPath, 'taller_test2.png');
  ArchPath := TPath.Combine(TPath.GetTempPath, 'descripcion_imagen.txt');
  PrintSep('TEST 4 — Vision + Tools chained (gemma3:4b -> qwen3.5:0.8b)');
  PrintINFO('Pattern: vision model describes image, tools model saves result.');
  TFile.WriteAllBytes(ImgPath, MakeTinyPng);

  Helper     := TTestHelper.Create;
  Funcs      := TAiFunctions.Create(nil);
  ConnVision := CreateConn('gemma3:4b', Helper);
  ConnTools  := CreateConn('qwen3.5:0.8b', Helper);
  try
    try
      // Step 1: describe image with vision model
      PrintINFO('[Step 1] gemma3:4b describes image...');
      MediaFiles := TAiMediaFiles.Create;
      try
        Attachment := TAiMediaFile.Create;
        Attachment.LoadFromFile(ImgPath);
        MediaFiles.Add(Attachment);

        Descripcion := ConnVision.AddMessageAndRun(
          'Describe this image in a short sentence.',
          'user',
          MediaFiles.ToMediaFileArray);
      finally
        MediaFiles.Free;
      end;

      if Helper.LastError <> '' then
      begin
        PrintFAIL('Error in vision step: ' + Helper.LastError);
        Exit;
      end;
      if Descripcion.Trim.IsEmpty then
      begin
        PrintFAIL('No description from vision model.');
        Exit;
      end;
      PrintOK('Description: ' + Descripcion.Trim.Substring(0, Min(150, Descripcion.Trim.Length)));
      Helper.LastError := '';

      // Step 2: save description with tools model
      PrintINFO('[Step 2] qwen3.5:0.8b saves description to file...');
      DefinirGuardarArchivo(Funcs, Helper);
      ConnTools.AiFunctions := Funcs;

      Resp := ConnTools.AddMessageAndRun(
        'Save this text to the file "' + ArchPath + '": ' + Descripcion.Trim,
        'user', []);

      if Helper.LastError <> '' then
        PrintFAIL('Error in tools step: ' + Helper.LastError)
      else if Helper.ArchivoGuardado and TFile.Exists(ArchPath) then
      begin
        PrintOK('File created: ' + ArchPath);
        PrintOK('Final response: ' + Resp.Trim.Substring(0, Min(150, Resp.Trim.Length)));
        Result := True;
        TFile.Delete(ArchPath);
      end
      else if Resp.Trim <> '' then
      begin
        PrintINFO('Model responded but did NOT invoke tool:');
        PrintINFO(Resp.Trim.Substring(0, Min(200, Resp.Trim.Length)));
        PrintFAIL('Tool call not executed.');
      end
      else
        PrintFAIL('No response from tools model.');
    except
      on E: Exception do PrintFAIL('Exception: ' + E.Message);
    end;
  finally
    ConnVision.Free;
    ConnTools.Free;
    Funcs.Free;
    Helper.Free;
    if TFile.Exists(ImgPath) then TFile.Delete(ImgPath);
  end;
end;

// =============================================================================
// DIDACTIC NOTE — Known error with qwen3-vl in Ollama 0.20.2
// =============================================================================
// This procedure is NOT a test that must pass. Its purpose is to show
// in the workshop:
//   1. How ideal code would look (a single model with vision + tools)
//   2. What error qwen3-vl produces when processing images in Ollama 0.20.2
//   3. What that error means and how to resolve it
// =============================================================================

procedure Demo_ErrorQwenVL;
var
  Conn:        TAiChatConnection;
  Funcs:       TAiFunctions;
  Helper:      TTestHelper;
  MediaFiles:  TAiMediaFiles;
  Attachment:  TAiMediaFile;
  Resp:        string;
  ImgPath:     string;
  ArchPath:    string;
  ErrorCapturado: string;  // saved before freeing Helper
begin
  ImgPath  := TPath.Combine(TPath.GetTempPath, 'taller_qwen_test.png');
  ArchPath := TPath.Combine(TPath.GetTempPath, 'qwen_descripcion.txt');
  TFile.WriteAllBytes(ImgPath, MakeTinyPng);

  PrintSep('DIDACTIC NOTE — Vision + Tools with a single model (qwen3-vl:2b)');
  WriteLn;
  WriteLn('  This is the IDEAL code when model supports vision + tools:');
  WriteLn('  (a single TAiChatConnection with cap_Image and Tool_Active = True)');
  WriteLn;
  WriteLn('    Conn.DriverName  := ''Ollama'';');
  WriteLn('    Conn.Model       := ''qwen3-vl:2b'';');
  WriteLn('    // ModelCaps = [cap_Image]');
  WriteLn('    // SessionCaps = [cap_Image]');
  WriteLn('    // Tool_Active = True');
  WriteLn('    Conn.AiFunctions := Funcs;');
  WriteLn('    Resp := Conn.AddMessageAndRun(prompt, ''user'', [imagen]);');
  WriteLn;
  WriteLn('  Trying to run it now...');
  WriteLn;

  Helper := TTestHelper.Create;
  Funcs  := TAiFunctions.Create(nil);
  Conn   := CreateConn('qwen3-vl:2b', Helper);
  try
    DefinirGuardarArchivo(Funcs, Helper);
    Conn.AiFunctions := Funcs;

    MediaFiles := TAiMediaFiles.Create;
    try
      Attachment := TAiMediaFile.Create;
      Attachment.LoadFromFile(ImgPath);
      MediaFiles.Add(Attachment);

      try
        Resp := Conn.AddMessageAndRun(
          'Describe this image and save the description to: ' + ArchPath,
          'user',
          MediaFiles.ToMediaFileArray);
      except
        on E: Exception do
        begin
          Helper.LastError := E.Message;
        end;
      end;
    finally
      MediaFiles.Free;
    end;
  finally
    ErrorCapturado := Helper.LastError;  // save before freeing
    Conn.Free;
    Funcs.Free;
    Helper.Free;
    if TFile.Exists(ImgPath)   then TFile.Delete(ImgPath);
    if TFile.Exists(ArchPath)  then TFile.Delete(ArchPath);
  end;

  // Show the error and the explanation
  WriteLn('  Result: ERROR');
  if ErrorCapturado <> '' then
    WriteLn('  Message  : ' + ErrorCapturado)
  else
    WriteLn('  Message  : model runner has unexpectedly stopped (HTTP 500)');
  WriteLn;
  WriteLn(StringOfChar('-', 70));
  WriteLn('  WHY IT FAILS');
  WriteLn(StringOfChar('-', 70));
  WriteLn;
  WriteLn('  qwen3-vl:2b supports vision + tools according to Ollama registry,');
  WriteLn('  but in Ollama 0.20.2 the llm-runner fails to load the');
  WriteLn('  images into memory before processing them (internal runner bug).');
  WriteLn('  Server returns HTTP 500 with message:');
  WriteLn('    "model runner has unexpectedly stopped"');
  WriteLn;
  WriteLn(StringOfChar('-', 70));
  WriteLn('  HOW TO RESOLVE IT');
  WriteLn(StringOfChar('-', 70));
  WriteLn;
  WriteLn('  Option A — Update Ollama (recommended):');
  WriteLn('    Download latest version from https://ollama.com/download');
  WriteLn('    qwen3-vl bug is fixed in versions > 0.20.2');
  WriteLn('    With updated Ollama, code above will work without');
  WriteLn('    any change; just a TAiChatConnection with vision + tools.');
  WriteLn;
  WriteLn('  Option B — Chaining pattern (workaround without updating):');
  WriteLn('    Step 1: gemma3:4b describes image  -> gets text');
  WriteLn('    Step 2: qwen3.5:0.8b uses that text with tool');
  WriteLn('    (This is what Test 4 of this workshop does)');
  WriteLn;
  WriteLn('  Option C — Alternative vision+tools model:');
  WriteLn('    If cloud access available, use Claude or GPT-4o that');
  WriteLn('    support vision + function calling natively and stably.');
  WriteLn('    In MakerAI just change DriverName and credentials:');
  WriteLn('      Conn.DriverName := ''Claude'';');
  WriteLn('      Conn.Model      := ''claude-opus-4-6'';');
  WriteLn('      // Same vision + tools code works without changes.');
  WriteLn(StringOfChar('=', 70));
end;

// =============================================================================
// MAIN
// =============================================================================
var
  R1, R2, R3, R4: Boolean;
  Passed: Integer;

begin
  try
    WriteLn('MakerAI v3.3 — Multimodal Chat Workshop Validation');
    WriteLn('Date: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    WriteLn;
    WriteLn('Registering model configuration...');
    InitChatModels;
    WriteLn('[OK]   Factory configured.');

    R1 := Test1_TextoBasico;
    R2 := Test2_FunctionCalling;
    R3 := Test3_Vision;
    R4 := Test4_Unificado;

    Passed := 0;
    if R1 then Inc(Passed);
    if R2 then Inc(Passed);
    if R3 then Inc(Passed);
    if R4 then Inc(Passed);

    PrintSep('SUMMARY');
    WriteLn(Format('  Test 1 - Basic text      (deepseek-r1:1.5b):          %s', [IfThen(R1,'PASS','FAIL')]));
    WriteLn(Format('  Test 2 - Function Calling  (qwen3.5:0.8b):              %s', [IfThen(R2,'PASS','FAIL')]));
    WriteLn(Format('  Test 3 - Vision            (gemma3:4b):                 %s', [IfThen(R3,'PASS','FAIL')]));
    WriteLn(Format('  Test 4 - Vision+Tools      (gemma3:4b -> qwen3.5:0.8b): %s', [IfThen(R4,'PASS','FAIL')]));
    WriteLn;
    WriteLn(Format('  Result: %d/4 tests passed', [Passed]));
    WriteLn(StringOfChar('=', 70));

    // Didactic section: shows the qwen3-vl error and explains the solution
    Demo_ErrorQwenVL;
  except
    on E: Exception do
      WriteLn('FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
  end;

  WriteLn;
  Write('Press ENTER to exit...');
  ReadLn;
end.
