program NativeTranscription;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 10-STT / 01-NativeTranscription
// =============================================================================
// Tests native audio transcription (InternalRunNativeTranscription) for
// the three drivers that implemented the override in May 2026:
//
//   - Groq     : whisper-large-v3 / whisper-large-v3-turbo
//                (endpoint OpenAI-compatible: /audio/transcriptions)
//   - Mistral  : voxtral-mini-latest / voxtral-small-latest
//                (endpoint OpenAI-compatible: /audio/transcriptions)
//   - Cohere   : cohere-transcribe-03-2026
//                (endpoint /v2/audio/transcriptions; language required)
//
// As a reference/baseline, OpenAI whisper-1 is also tested.
//
// Key configuration:
//   ChatMode = cmTranscription  -->  RunNew goes directly to InternalRunTranscription
//                                    without going through InternalRunCompletions.
//   Without an assigned SpeechTool     -->  InternalRunTranscription calls the override
//                                    native to the driver (not the external tool).
//   OnError captures errors     -->  RunNew swallows exceptions internally
//                                    and reports them via the OnError event.
//
// Usage:
//   NativeTranscription.exe [audio_path]
//
// Supported formats: WAV, MP3, OGG, M4A, FLAC, WEBM (depending on provider).
// Environment variables: OPENAI_API_KEY  GROQ_API_KEY  MISTRAL_API_KEY  COHERE_API_KEY
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations;

// ---------------------------------------------------------------------------
const
  SEP  = '------------------------------------------------------------';
  WIDE = '============================================================';

// ---------------------------------------------------------------------------
// TErrorCapture — captures the OnError of TAiChatConnection
// RunNew catches all exceptions internally and redirects them to OnError.
// ---------------------------------------------------------------------------
type
  TErrorCapture = class
  private
    FMsg: String;
  public
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AEx: Exception; const AResp: IHTTPResponse);
    function HasError: Boolean;
    procedure Clear;
    property Msg: String read FMsg;
  end;

procedure TErrorCapture.OnError(Sender: TObject; const ErrorMsg: string;
  AEx: Exception; const AResp: IHTTPResponse);
begin
  FMsg := ErrorMsg;
end;

function TErrorCapture.HasError: Boolean;
begin
  Result := FMsg <> '';
end;

procedure TErrorCapture.Clear;
begin
  FMsg := '';
end;

// ---------------------------------------------------------------------------
// TTestResult — result record for the final summary
// ---------------------------------------------------------------------------
type
  TTestResult = record
    Driver : String;
    Model  : String;
    Tag    : String; // short scenario (e.g.: 'lang=es', 'empty')
    OK     : Boolean;
    Output : String; // first 120 chars of the transcription or the error
  end;

var
  GResults : array of TTestResult;

procedure AddResult(const ADriver, AModel, ATag: String; AOK: Boolean;
  const AOutput: String);
var
  R: TTestResult;
begin
  R.Driver := ADriver;
  R.Model  := AModel;
  R.Tag    := ATag;
  R.OK     := AOK;
  R.Output := Copy(AOutput, 1, 120);
  SetLength(GResults, Length(GResults) + 1);
  GResults[High(GResults)] := R;
end;

// ---------------------------------------------------------------------------
// TestTranscription
//   AResponseFormat : '' = driver default | 'json' | 'verbose_json' | 'text'
//   ALanguage       : '' = do not force  | 'es' | 'en' | ...
// ---------------------------------------------------------------------------
function TestTranscription(const ADriver, AModel, AAudioFile,
  ALanguage, AResponseFormat: String): Boolean;
var
  Conn : TAiChatConnection;
  EC   : TErrorCapture;
  MF   : TAiMediaFile;
  Resp : String;
  Tag  : String;
begin
  Result := False;
  Tag    := '';
  if ALanguage <> '' then Tag := Tag + 'lang=' + ALanguage + ' ';
  if AResponseFormat <> '' then Tag := Tag + 'fmt=' + AResponseFormat;
  Tag := Trim(Tag);

  Write('  ', ADriver, '/', AModel);
  if Tag <> '' then Write(' [', Tag, ']');
  Write(' ... ');

  EC   := TErrorCapture.Create;
  Conn := TAiChatConnection.Create(nil);
  try
    // --- Basic configuration ---
    // IMPORTANT: OnError is assigned BEFORE DriverName, just like AudioBridge.
    Conn.OnError                       := EC.OnError;
    Conn.DriverName                    := ADriver;
    Conn.Params.Values['Model']        := AModel;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.ChatMode                      := cmTranscription;
    // Without SpeechTool: the driver falls back to InternalRunNativeTranscription

    // --- Transcription parameters ---
    if ALanguage <> '' then
      Conn.TranscriptionParams.Language := ALanguage;
    if AResponseFormat <> '' then
      Conn.TranscriptionParams.ResponseFormat := AResponseFormat;

    // --- Audio file ---
    // AddMessageAndRun transfers ownership of MF to the internal history.
    // Conn.Free frees the history and with it all TAiMediaFile.
    MF := TAiMediaFile.Create;
    MF.LoadFromFile(AAudioFile);

    // --- Call ---
    Resp := Conn.AddMessageAndRun('', 'user', [MF]);

    if EC.HasError then
    begin
      Writeln('FAIL');
      Writeln('    ! ', Copy(EC.Msg, 1, 300));
      AddResult(ADriver, AModel, Tag, False, EC.Msg);
    end
    else if Resp = '' then
    begin
      Writeln('EMPTY');
      AddResult(ADriver, AModel, Tag, False, '[empty response]');
    end
    else
    begin
      Writeln('OK');
      Writeln('    > ', Copy(Resp, 1, 100));
      AddResult(ADriver, AModel, Tag, True, Resp);
      Result := True;
    end;

  finally
    Conn.Free;
    EC.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TestErrorCase: empty file — must report error via OnError
// RunNew catches the exception and calls OnError (does not re-raise).
// ---------------------------------------------------------------------------
procedure TestErrorCase(const ADriver, AModel: String);
var
  Conn : TAiChatConnection;
  EC   : TErrorCapture;
  MF   : TAiMediaFile;
  Resp : String;
begin
  Write('  ', ADriver, '/', AModel, ' [empty file] ... ');

  EC   := TErrorCapture.Create;
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.OnError                       := EC.OnError;
    Conn.DriverName                    := ADriver;
    Conn.Params.Values['Model']        := AModel;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.ChatMode                      := cmTranscription;

    // Empty MF (without LoadFromFile). RunNew detects Content.Size=0 and calls OnError.
    MF   := TAiMediaFile.Create;
    Resp := Conn.AddMessageAndRun('', 'user', [MF]);

    if EC.HasError then
      Writeln('OK (error captured: ', Copy(EC.Msg, 1, 60), ')')
    else if Resp = '' then
      Writeln('OK (empty response — validation before the driver)')
    else
      Writeln('NO ERROR (unexpected — response: "', Copy(Resp, 1, 40), '")');
  finally
    Conn.Free;
    EC.Free;
  end;
end;

// ---------------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------------
var
  AudioPath : String;
  HasAudio  : Boolean;
  I         : Integer;
  OK, Total : Integer;
begin
  Writeln(WIDE);
  Writeln('  MakerAI — 10-STT / 01-NativeTranscription');
  Writeln(WIDE);
  Writeln;
  Writeln('Drivers: OpenAI (baseline), Groq, Mistral, Cohere');
  Writeln('Hook:    InternalRunNativeTranscription override');
  Writeln('Route:   ChatMode=cmTranscription → InternalRunTranscription → override');
  Writeln;

  // --- Audio file path ---
  HasAudio := False;
  if ParamCount >= 1 then
    AudioPath := Trim(ParamStr(1))
  else
  begin
    Write('Path of the audio file (WAV/MP3/OGG, Enter to skip): ');
    Readln(AudioPath);
    AudioPath := Trim(AudioPath);
  end;

  if AudioPath <> '' then
  begin
    if not FileExists(AudioPath) then
    begin
      Writeln('ERROR: File not found: "', AudioPath, '"');
      Write('Press Enter...');
      Readln;
      Halt(1);
    end;
    HasAudio := True;
    Writeln('Audio: ', ExtractFileName(AudioPath),
            '  (', TFile.GetSize(AudioPath), ' bytes)');
    Writeln;
  end;

  // ===========================================================================
  // BLOCK 0: Error case — empty file
  // Verifies that the driver detects the problem and reports it via OnError.
  // ===========================================================================
  Writeln(SEP);
  Writeln('BLOCK 0: Error handling (file without content)');
  Writeln(SEP);
  TestErrorCase('OpenAI',  'whisper-1');
  TestErrorCase('Groq',    'whisper-large-v3');
  TestErrorCase('Mistral', 'voxtral-mini-latest');
  TestErrorCase('Cohere',  'cohere-transcribe-03-2026');
  Writeln;

  if not HasAudio then
  begin
    Writeln(SEP);
    Writeln('INFO: No audio file — blocks 1-4 skipped.');
    Writeln('      Pass the path as an argument:');
    Writeln('        NativeTranscription.exe D:\path\audio.wav');
    Writeln(SEP);
  end
  else
  begin
    // =========================================================================
    // BLOCK 1: OpenAI — baseline (worked before the PR)
    // =========================================================================
    Writeln(SEP);
    Writeln('BLOCK 1: OpenAI (baseline)');
    Writeln(SEP);
    TestTranscription('OpenAI', 'whisper-1', AudioPath, '',   '');
    TestTranscription('OpenAI', 'whisper-1', AudioPath, 'en', 'verbose_json');
    Writeln;

    // =========================================================================
    // BLOCK 2: Groq — whisper OpenAI-compatible
    // =========================================================================
    Writeln(SEP);
    Writeln('BLOCK 2: Groq (whisper — OpenAI-compatible)');
    Writeln(SEP);
    TestTranscription('Groq', 'whisper-large-v3',       AudioPath, '',   '');
    TestTranscription('Groq', 'whisper-large-v3',       AudioPath, 'en', 'verbose_json');
    TestTranscription('Groq', 'whisper-large-v3-turbo', AudioPath, '',   '');
    Writeln;

    // =========================================================================
    // BLOCK 3: Mistral — Voxtral OpenAI-compatible
    // =========================================================================
    Writeln(SEP);
    Writeln('BLOCK 3: Mistral (Voxtral — OpenAI-compatible)');
    Writeln(SEP);
    TestTranscription('Mistral', 'voxtral-mini-latest', AudioPath, '',   '');
    TestTranscription('Mistral', 'voxtral-mini-latest', AudioPath, 'es', 'verbose_json');
    TestTranscription('Mistral', 'voxtral-mini-latest', AudioPath, 'en', 'text');
    Writeln;

    // =========================================================================
    // BLOCK 4: Cohere
    // Differences: language required (driver uses 'en' by default),
    // response_format not supported (ignored in the override — must not crash).
    // =========================================================================
    Writeln(SEP);
    Writeln('BLOCK 4: Cohere (language required, without response_format)');
    Writeln(SEP);
    // Without language → override uses 'en' automatically
    TestTranscription('Cohere', 'cohere-transcribe-03-2026', AudioPath, '',   '');
    // Explicit language
    TestTranscription('Cohere', 'cohere-transcribe-03-2026', AudioPath, 'en', '');
    TestTranscription('Cohere', 'cohere-transcribe-03-2026', AudioPath, 'es', '');
    // response_format ignored by Cohere — the override does not send it; must not fail
    TestTranscription('Cohere', 'cohere-transcribe-03-2026', AudioPath, 'en', 'verbose_json');
    Writeln;
  end;

  // ===========================================================================
  // FINAL SUMMARY
  // ===========================================================================
  Writeln(WIDE);
  Writeln('SUMMARY');
  Writeln(WIDE);
  OK    := 0;
  Total := Length(GResults);
  for I := 0 to Total - 1 do
  begin
    if GResults[I].OK then
    begin
      Write('  [OK]   ', GResults[I].Driver, '/', GResults[I].Model);
      if GResults[I].Tag <> '' then Write(' [', GResults[I].Tag, ']');
      Writeln;
      Inc(OK);
    end
    else
    begin
      Write('  [FAIL] ', GResults[I].Driver, '/', GResults[I].Model);
      if GResults[I].Tag <> '' then Write(' [', GResults[I].Tag, ']');
      Writeln(' — ', GResults[I].Output);
    end;
  end;
  Writeln;
  Writeln('Result: ', OK, '/', Total, ' transcriptions OK');
  Writeln(WIDE);

  Writeln;
  Write('Press Enter to exit...');
  Readln;
end.
