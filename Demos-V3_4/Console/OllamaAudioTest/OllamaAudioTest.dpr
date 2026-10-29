program OllamaAudioTest;

{$APPTYPE CONSOLE}

// =============================================================================
// OllamaAudioTest — bridge STT + TTS: gemma3:4b (Ollama) + TAiGeminiSpeechTool
// =============================================================================
// Demonstrates how to use an Ollama model without native audio capability
// (gemma3:4b) combined with TAiGeminiSpeechTool as an automatic bridge.
//
// SCENARIO A — STT bridge (Phase 1 of the orchestrator):
//   ModelCaps=[] / SessionCaps=[cap_Audio]  →  Gap=[cap_Audio]
//   The orchestrator detects the gap and calls TAiGeminiSpeechTool.ExecuteTranscription
//   before sending the message to the model. The transcription is injected into the
//   prompt and gemma3:4b responds as if it had received plain text.
//
// SCENARIO B — TTS (audio generation for the response):
//   Takes the response text from scenario A and uses TAiGeminiSpeechTool
//   to generate an output WAV file (response_audio.wav).
//
// Usage:
//   OllamaAudioTest.exe [audio_path] [question]
//
//   If no arguments are passed, it asks for them interactively.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Net.HttpClient,
  TypInfo,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama,
  uMakerAi.Gemini.Speech;

// ---------------------------------------------------------------------------
// Captures chat errors (TAiErrorEvent is "of object", needs a class)
// ---------------------------------------------------------------------------
type
  TErrorCapture = class
  private
    FErrorMsg   : String;
    FHttpStatus : Integer;
    FHttpBody   : String;
  public
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);
    function  HasError: Boolean;
    procedure Clear;
    property  ErrorMsg:   String  read FErrorMsg;
    property  HttpStatus: Integer read FHttpStatus;
    property  HttpBody:   String  read FHttpBody;
  end;

procedure TErrorCapture.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FErrorMsg := ErrorMsg;
  FHttpStatus := 0;
  FHttpBody   := '';
  if Assigned(AResponse) then
  begin
    FHttpStatus := AResponse.StatusCode;
    FHttpBody   := AResponse.ContentAsString;
  end;
end;

function TErrorCapture.HasError: Boolean;
begin
  Result := FErrorMsg <> '';
end;

procedure TErrorCapture.Clear;
begin
  FErrorMsg   := '';
  FHttpStatus := 0;
  FHttpBody   := '';
end;

// ---------------------------------------------------------------------------
const
  OLLAMA_URL = 'http://localhost:11434/';
  MODEL      = 'gemma3:4b';     // model WITHOUT native audio capability
  DIV_LINE   = '------------------------------------------------------------';

// ---------------------------------------------------------------------------
procedure PrintError(const ErrCap: TErrorCapture);
begin
  Writeln('[LLM ERROR]');
  Writeln('  Message : ', ErrCap.ErrorMsg);
  if ErrCap.HttpStatus > 0 then
  begin
    Writeln('  HTTP    : ', ErrCap.HttpStatus);
    Writeln('  Body:');
    Writeln(ErrCap.HttpBody);
  end;
end;

// ---------------------------------------------------------------------------
// SCENARIO A: Audio → Gemini STT bridge → gemma3:4b → text response
// ---------------------------------------------------------------------------
function RunSTTBridge(const AAudioFile, AQuestion: String): String;
var
  Conn       : TAiChatConnection;
  SpeechTool : TAiGeminiSpeechTool;
  AudioFile  : TAiMediaFile;
  ErrCap     : TErrorCapture;
begin
  Result := '';
  Writeln;
  Writeln('=== SCENARIO A — STT bridge ===');
  Writeln('  Audio   : ', AAudioFile);
  Writeln('  Question: ', AQuestion);
  Writeln(DIV_LINE);

  ErrCap     := TErrorCapture.Create;
  SpeechTool := TAiGeminiSpeechTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    // -- Configure SpeechTool (Gemini STT) --
    SpeechTool.ApiKey             := '@GEMINI_API_KEY';
    SpeechTool.TranscriptionModel := 'gemini-2.0-flash';
    SpeechTool.TranscriptionPrompt := 'Transcribe this audio accurately.';

    // -- Configure Ollama connection --
    Conn.DriverName := 'Ollama';
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    // ModelCaps=[] → gemma3:4b has no native audio
    // SessionCaps=[cap_Audio] → we want audio in the session
    // Gap=[cap_Audio] → orchestrator activates STT bridge (PHASE 1)
    Conn.Params.Values['ModelCaps']    := '[]';
    Conn.Params.Values['SessionCaps']  := '[cap_Audio]';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.OnError := ErrCap.OnError;

    // -- Assign the SpeechTool to the bridge --
    Conn.SpeechTool := SpeechTool;

    // -- Load audio --
    // IMPORTANT: AddMessageAndRun assumes ownership of TAiMediaFile.
    // DO NOT free AudioFile; the FMessages list frees it when the connection is destroyed.
    AudioFile := TAiMediaFile.Create;
    AudioFile.LoadFromFile(AAudioFile);
    Writeln('  Loaded : ', AudioFile.Content.Size, ' bytes',
            ' | MIME: ', AudioFile.MimeType,
            ' | Cat: ', GetEnumName(TypeInfo(TAiFileCategory), Ord(AudioFile.FileCategory)));
    Writeln('  Transcribing with Gemini + sending to ', MODEL, ' (please wait...)');

    // The orchestrator detects Gap=[cap_Audio]:
    //   PHASE 1 → TAiGeminiSpeechTool.ExecuteTranscription(audioFile, ...)
    //          → MF.Transcription = text
    //          → AskMsg.Prompt += '[Audio transcription]:...'
    //   PHASE 3 → InternalRunCompletions → gemma3:4b receives augmented prompt
    Result := Conn.AddMessageAndRun(AQuestion, 'user', [AudioFile]);

    Writeln;
    if ErrCap.HasError then
      PrintError(ErrCap)
    else if Result <> '' then
    begin
      Writeln('=== RESPONSE FROM ', MODEL, ' ===');
      Writeln(Result);
    end
    else
      Writeln('[NO RESPONSE] The model returned an empty string without error.');

  finally
    Conn.Free;
    SpeechTool.Free;
    ErrCap.Free;
  end;
end;

// ---------------------------------------------------------------------------
// SCENARIO B: Text → Gemini TTS → .wav file
// ---------------------------------------------------------------------------
procedure RunTTSGeneration(const AText: String);
var
  AudioResult : TAiMediaFile;
  OutputFile  : String;
begin
  Writeln;
  Writeln('=== SCENARIO B — TTS (response → audio) ===');
  Writeln('  Text: ', Copy(AText, 1, 80), IfThen(Length(AText) > 80, '...', ''));
  Writeln(DIV_LINE);

  if AText = '' then
  begin
    Writeln('  [SKIP] No text to convert to audio.');
    Exit;
  end;

  Writeln('  Generating audio with Gemini TTS (please wait...)');
  AudioResult := TAiGeminiSpeechTool.GenerateSpeech(
    GetEnvironmentVariable('GEMINI_API_KEY'),
    AText,
    'Puck',   // voice (Puck, Kore, Charon, Fenrir, Aoede, etc.)
    nil, nil, nil);

  if Assigned(AudioResult) then
  begin
    OutputFile := ExtractFilePath(ParamStr(0)) + 'response_audio.wav';
    try
      AudioResult.Content.SaveToFile(OutputFile);
      Writeln('  Audio saved: ', OutputFile,
              ' (', AudioResult.Content.Size, ' bytes)');
    finally
      AudioResult.Free;
    end;
  end
  else
    Writeln('  [ERROR] Gemini TTS did not return audio. Check GEMINI_API_KEY.');
end;

// ---------------------------------------------------------------------------
var
  AudioPath, Question, ModelResponse: String;
begin
  Writeln('=== OllamaAudioTest — Bridge STT+TTS ===');
  Writeln('Driver : Ollama / Model: ', MODEL);
  Writeln('Bridge : TAiGeminiSpeechTool (STT + TTS via Gemini API)');
  Writeln('Gap    : ModelCaps=[] / SessionCaps=[cap_Audio] → gap=[cap_Audio]');
  Writeln;

  try
    // -- Audio file path --
    if ParamCount >= 1 then
      AudioPath := ParamStr(1)
    else
    begin
      Write('Path of the audio file (wav / mp3 / ogg / m4a / flac): ');
      Readln(AudioPath);
    end;
    AudioPath := Trim(AudioPath);

    if not FileExists(AudioPath) then
      raise Exception.CreateFmt('File not found: "%s"', [AudioPath]);

    // -- Question --
    if ParamCount >= 2 then
      Question := ParamStr(2)
    else
      Question := 'Briefly summarize what the audio says.';

    // -- Scenario A: STT bridge --
    ModelResponse := RunSTTBridge(AudioPath, Question);

    // -- Scenario B: TTS of the response --
    RunTTSGeneration(ModelResponse);

  except
    on E: Exception do
    begin
      Writeln;
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
