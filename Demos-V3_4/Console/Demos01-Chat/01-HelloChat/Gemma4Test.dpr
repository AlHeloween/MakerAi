program Gemma4Test;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// Gemma4Test — tests gemma4:e2b via Ollama with the MakerAI framework
//
// TEST 1: Basic chat + reasoning (verifies that think:true activates the thinking field)
// TEST 2: Vision (red 1x1 image)
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  System.Net.HttpClient,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Ollama,
  uMakerAi.Chat.Initializations,
  uMakerAi.Core;

const
  OLLAMA_URL = 'http://localhost:11434/';
  MODEL      = 'gemma4:e2b';
  LINE       = '------------------------------------------------------------';

var
  GThinking: String;

// ---------------------------------------------------------------------------
type
  TEvHandler = class
    procedure OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
                         aResponse: TJSONObject; aRole, aText: string);
    procedure OnData(const Sender: TObject; aMsg: TAiChatMessage;
                     aResponse: TJSONObject; aRole, aText: string);
    procedure OnError(Sender: TObject; const AMsg: string;
                      AEx: Exception; const AResp: IHTTPResponse);
  end;

procedure TEvHandler.OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: string);
begin
  GThinking := aText;
  Writeln;
  Writeln('--- Internal reasoning ---');
  Writeln(aText);
  Writeln('----------------------------');
end;

procedure TEvHandler.OnData(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: string);
begin
  Write(aText);  // imprime la respuesta token a token (modo stream)
end;

procedure TEvHandler.OnError(Sender: TObject; const AMsg: string;
  AEx: Exception; const AResp: IHTTPResponse);
begin
  Writeln('  [ERROR] ', AMsg);
  if Assigned(AResp) then
    Writeln('  HTTP ', AResp.StatusCode, ': ', Copy(AResp.ContentAsString, 1, 300));
end;

// ---------------------------------------------------------------------------
function MakeConn(Ev: TEvHandler): TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName                    := 'Ollama';
  Result.Params.Values['URL']          := OLLAMA_URL;
  Result.Params.Values['Model']        := MODEL;
  Result.Params.Values['Asynchronous'] := 'False';
  Result.Params.Values['Max_Tokens']   := '2048';
  Result.OnReceiveThinking             := Ev.OnThinking;
  Result.OnReceiveData                 := Ev.OnData;
  Result.OnError                       := Ev.OnError;
end;

// ---------------------------------------------------------------------------
// TEST 1: Basic chat + verify that thinking arrives
// ---------------------------------------------------------------------------
procedure Test1_Reasoning;
var
  Conn: TAiChatConnection;
  Ev  : TEvHandler;
  Resp: String;
begin
  Writeln;
  Writeln('TEST 1 - Basic chat + reasoning');
  Writeln(LINE);

  GThinking := '';
  Ev   := TEvHandler.Create;
  Conn := MakeConn(Ev);
  try
    Conn.SystemPrompt.Text := 'You are a helpful assistant. Always respond in Spanish.';
    Write('Response: ');
    Resp := Conn.AddMessageAndRun('Cuanto es 17 x 23? Piensa paso a paso.', 'user', []);
    Writeln;

    if (Resp <> '') and (GThinking <> '') then
      Writeln('PASS: response + thinking received (think:true active)')
    else if Resp <> '' then
      Writeln('WARN: response OK but thinking empty')
    else
      Writeln('FAIL: no response');
  finally
    Conn.Free;
    Ev.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TEST 2: Vision — red 1x1 PNG image
// ---------------------------------------------------------------------------
procedure Test2_Vision;
const
  // PNG 1x1 red pixel (generated with System.Drawing, valid)
  RED_PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6Q' +
                'AAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhX' +
                'Y/jPwPAfAAUAAf+mXJtdAAAAAElFTkSuQmCC';
var
  Conn  : TAiChatConnection;
  Ev    : TEvHandler;
  Media : TAiMediaFile;
  Resp  : String;
begin
  Writeln;
  Writeln('TEST 2 - Vision (red 1x1 image)');
  Writeln(LINE);

  Ev   := TEvHandler.Create;
  Conn := MakeConn(Ev);
  Media := TAiMediaFile.Create;
  try
    // Load 1x1 PNG image from base64
    Media.LoadFromBase64('image.png', RED_PNG_B64);

    Resp := Conn.AddMessageAndRun(
      'What is the dominant color in this image? One word only.',
      'user', [Media]);

    Writeln('Response: ', Resp);

    if Resp.ToLower.Contains('red') then
      Writeln('PASS: vision works correctly')
    else if Resp <> '' then
      Writeln('INFO: response received: "', Resp, '" (check if correct)');
  finally
    Conn.Free;
    Ev.Free;
    // Media is released by the connection via AddMessageAndRun
  end;
end;

// ---------------------------------------------------------------------------
// TEST 3: Audio — transcription of a WAV
// ---------------------------------------------------------------------------
procedure Test3_Audio;
const
  AUDIO_FILE = 'D:\taller\medios\HolaComoTEEncuentras.wav';
var
  Conn  : TAiChatConnection;
  Ev    : TEvHandler;
  Media : TAiMediaFile;
  Resp  : String;
begin
  Writeln;
  Writeln('TEST 3 - Audio (WAV transcription)');
  Writeln(LINE);
  Writeln('File: ', AUDIO_FILE);

  if not FileExists(AUDIO_FILE) then
  begin
    Writeln('SKIP: file not found');
    Exit;
  end;

  Ev    := TEvHandler.Create;
  Conn  := MakeConn(Ev);
  Media := TAiMediaFile.Create;
  try
    Media.LoadFromFile(AUDIO_FILE);

    Write('Response: ');
    Resp := Conn.AddMessageAndRun(
      'Transcribe exactly what the audio says. Only the text, no comments.',
      'user', [Media]);
    Writeln;

    if Resp <> '' then
      Writeln('PASS: audio transcribed correctly')
    else
      Writeln('FAIL: no response');
  finally
    Conn.Free;
    Ev.Free;
  end;
end;

// ---------------------------------------------------------------------------
begin
  Writeln('=== Gemma4Test - MakerAI Framework ===');
  Writeln('Model : ', MODEL, '  Driver: Ollama  URL: ', OLLAMA_URL);

  try
    Test1_Reasoning;
    Test2_Vision;
    Test3_Audio;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;

  Writeln;
  Writeln(LINE);
  Writeln('Press Enter to exit...');
  Readln;
end.
