program ClaudeChatTest;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude;

type
  TTestConfig = record
    Name: string;
    ResponseFormat: string;
    ChatMedia: string;
    NativeOutput: string;
    JsonSchema: string;
    Thinking: string;
  end;

var
  CCfg: TTestConfig;

procedure ConfigureBase(A: TAiChatConnection);
begin
  A.DriverName := 'Claude';
  A.Model := 'claude-sonnet-4-5-20250929';

  A.Params.Values['ApiKey'] := '@CLAUDE_API_KEY';
  A.Params.Values['Url'] := 'https://api.anthropic.com/v1/';
  A.Params.Values['Max_Tokens'] := '16000';
  A.Params.Values['Temperature'] := '0.7';
  A.Params.Values['ResponseTimeOut'] := '600000';
  A.Params.Values['ThinkingLevel'] := 'tlDefault';

  A.Params.Values['NativeInputFiles'] := '[Tfc_Image, Tfc_Pdf]';
  A.Params.Values['NativeOutputFiles'] := '[]';
  A.Params.Values['ChatMediaSupports'] := '[Tcm_Image, Tcm_Pdf]';
  A.Params.Values['Asynchronous'] := 'False';
  A.Params.Values['Tool_Active'] := 'False';
end;

function RunSyncTest(const Cfg: TTestConfig; const Prompt: string;
                     Attachments: array of string): string;
var
  Ai: TAiChatConnection;
  MF: TAiMediaFile;
  Res: string;
  I: Integer;
  MediaList: TAiMediaFilesArray;
  FileName: string;
begin
  Writeln;
  Writeln('==============================');
  Writeln('PRUEBA: ', Cfg.Name);
  Writeln('PROMPT: ', Prompt);
  Writeln('==============================');

  // --------------------------------------------------------------
  // VALIDATE FILES BEFORE RUNNING THE TEST
  // --------------------------------------------------------------
  for I := 0 to High(Attachments) do
  begin
    FileName := Attachments[I];

    if not FileExists(FileName) then
    begin
      Writeln('WARNING: The file required for this test does NOT exist.');
      Writeln('  Path: ', FileName);
      Writeln('  ==> This test will be skipped.');
      Exit('File not found: ' + FileName);
    end;
  end;

  // --------------------------------------------------------------
  // IF THE FILES EXIST → WE RUN THE TEST NORMALLY
  // --------------------------------------------------------------

  Ai := TAiChatConnection.Create(nil);
  try
    // Standard base configuration
    ConfigureBase(Ai);

    Ai.Params.Values['Response_format'] := Cfg.ResponseFormat;

    if Cfg.ChatMedia <> '' then
      Ai.Params.Values['ChatMediaSupports'] := Cfg.ChatMedia;

    if Cfg.NativeOutput <> '' then
      Ai.Params.Values['NativeOutputFiles'] := Cfg.NativeOutput;

    if Cfg.JsonSchema <> '' then
      Ai.Params.Values['JsonSchema'] := Cfg.JsonSchema;

    if Cfg.Thinking <> '' then
      Ai.Params.Values['ThinkingLevel'] := Cfg.Thinking;

    // ------------------------------
    // Attachment handling
    // ------------------------------
    if Length(Attachments) > 0 then
    begin
      SetLength(MediaList, Length(Attachments));

      for I := 0 to High(Attachments) do
      begin
        MF := TAiMediaFile.Create;
        MF.LoadFromFile(Attachments[I]);
        MediaList[I] := MF;
      end;

      Res := Ai.AddMessageAndRun(Prompt, 'user', MediaList);
    end
    else
      Res := Ai.AddMessageAndRun(Prompt, 'user', []);

  finally
    Ai.Free;
  end;

  Writeln('RESPONSE:');
  Writeln(Res);

  Result := Res;
end;


//
// =======================================
// LOG TESTS (WITHOUT SHELL/EDIT/FUNC)
// =======================================
//

/// ///////////////////////
// BASIC CHAT
/// ///////////////////////

procedure Test_Chat1;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'BASIC CHAT 1';
  Cfg.ResponseFormat := 'tiaChatRfText';
  RunSyncTest(Cfg, 'hello, how are you today?', []);
end;


/// ///////////////////////
// JSON
/// ///////////////////////

procedure Test_JSON1;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'JSON FORMAT 1';
  Cfg.ResponseFormat := 'tiaChatRfJson';
  RunSyncTest(Cfg, 'generate a test json of 3 lines', []);
end;


/// ///////////////////////
// JSON SCHEMA
/// ///////////////////////

procedure Test_JSONSchema1;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'JSON SCHEMA 1';
  Cfg.ResponseFormat := 'tiaChatRfJsonSchema';
  Cfg.JsonSchema := '{ "type":"object","properties":{"nombre":{"type":"string"},"edad":{"type":"integer"},"email":{"type":"string","format":"email"}},"required":["nombre","email"] }';

  RunSyncTest(Cfg, 'generate a test json', []);
end;


/// ///////////////////////
// WEB SEARCH
/// ///////////////////////

procedure Test_WebSearch1;
var
  Cfg: TTestConfig;
begin
  CCfg.Name := 'WEB SEARCH 1';
  Cfg.ResponseFormat := 'tiaChatRfText';
  Cfg.ChatMedia := '[Tcm_WebSearch, Tcm_Image, Tcm_Pdf]';

  RunSyncTest(Cfg, 'search the internet about MakerAi Delphi Suite', []);
end;


/// ///////////////////////
// CODE INTERPRETER
/// ///////////////////////

procedure Test_CodeInterpreter1;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'CODE INTERPRETER 1';
  Cfg.ResponseFormat := 'tiaChatRfText';
  Cfg.ChatMedia := '[Tcm_code_interpreter, Tcm_Image, Tcm_Pdf]';

  RunSyncTest(Cfg, 'Generate a .wav file with a 1500 hz tone', []);
end;


/// ///////////////////////
// EXTRACT TEXT
/// ///////////////////////

procedure Test_ExtractText1;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'EXTRACT TEXT FILE 1';
  Cfg.ResponseFormat := 'tiaChatRfText';
  Cfg.NativeOutput := '[tfc_ExtracttextFile]';

  RunSyncTest(Cfg, 'generate a basic html, a hello world', []);
end;

procedure Test_ExtractText2;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'EXTRACT TEXT FILE 2';
  Cfg.ResponseFormat := 'tiaChatRfText';
  Cfg.NativeOutput := '[tfc_ExtracttextFile]';

  RunSyncTest(Cfg, 'generate pascal code, a hello world in console mode', []);
end;

/// ///////////////////////
// VISION
/// ///////////////////////

procedure Test_VisionImage;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'VISION IMAGE';
  Cfg.ResponseFormat := 'tiaChatRfText';
  RunSyncTest(Cfg, 'describe this image', ['medios/patito.png']);
end;

procedure Test_VisionPDF;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'VISION PDF';
  Cfg.ResponseFormat := 'tiaChatRfText';
  RunSyncTest(Cfg, 'extract the content of this invoice', ['medios/factura.pdf']);
end;

procedure Test_VisionPDFJson;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'VISION PDF JSON';
  Cfg.ResponseFormat := 'tiaChatRfJson';
  Cfg.NativeOutput := '[tfc_ExtracttextFile]';

  RunSyncTest(Cfg, 'extract the content of this invoice in a json', ['medios/factura.pdf']);
end;

/// ///////////////////////
// THINKING
/// ///////////////////////

procedure Test_Thinking;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'THINKING HIGH';
  Cfg.ResponseFormat := 'tiaChatRfText';
  Cfg.Thinking := 'tlHigh';

  RunSyncTest(Cfg, 'if I have 10 candles and light them all...', []);
end;

/// ///////////////////////
// ACKNOWLEDGMENTS
/// ///////////////////////

procedure Test_Agradecimientos;
var
  Cfg: TTestConfig;
begin
  Cfg.Name := 'ACKNOWLEDGMENTS';
  Cfg.ResponseFormat := 'tiaChatRfText';

  RunSyncTest(Cfg, 'thank those who are watching this video for watching us and making it to the end', []);
end;


//
// ======================
// GENERAL EXECUTION
// ======================
//

begin
  try
    Writeln('=== RUNNING TESTS ===');

    Test_Chat1;

    Test_JSON1;

    Test_JSONSchema1;

    Test_WebSearch1;

    Test_CodeInterpreter1;

    Test_ExtractText1;
    Test_ExtractText2;

    Test_VisionImage;
    Test_VisionPDF;
    Test_VisionPDFJson;

    Test_Thinking;
    Test_Agradecimientos;

    Writeln('');
    Writeln('=== END OF TESTS ===');
    Readln;

  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;

end.
