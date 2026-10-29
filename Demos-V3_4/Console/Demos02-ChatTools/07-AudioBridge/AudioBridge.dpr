program AudioBridge;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 07-AudioBridge
// =============================================================================
// Demonstrates audio input modes with gemma4 (Ollama local):
//
//   SCENARIO 1 — Native audio (cap_Audio in ModelCaps → no bridge)
//     gemma4:e4b / gemma4:e2b have native cap_Audio registered.
//     Gap = SessionCaps − ModelCaps = [] → audio is sent directly
//     to the model via the Ollama API, without going through Gemini.
//
//   SCENARIO 2 — STT Bridge (force ModelCaps=[] → Gemini transcribes → gemma4 responds)
//     Overriding ModelCaps=[] at runtime produces
//     Gap=[cap_Audio] → Phase 1 activates TAiGeminiSpeechTool.ExecuteTranscription.
//     Audio is transcribed with Gemini 2.0-flash; gemma4 receives plain text.
//     Useful when Ollama does not accept audio in the API even though the model supports it.
//
//   SCENARIO 3 — Direct TTS (text → Gemini TTS → WAV)
//     Uses TAiGeminiSpeechTool.GenerateSpeech() directly.
//
//   SCENARIO 4 — Full pipeline (audio → STT bridge → gemma4 → TTS)
//
// Requirements:
//   - Ollama running at http://localhost:11434 with gemma4:e4b and gemma4:e2b
//   - GEMINI_API_KEY environment variable with a valid key
//   - WAV/MP3/OGG/M4A audio file (first argument or requested interactively)
//
// Usage:
//   AudioBridge.exe [audio_path] [question]
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Net.HttpClient,
  TypInfo,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama,
  uMakerAi.Gemini.Speech;

// ---------------------------------------------------------------------------
const
  OLLAMA_URL  = 'http://localhost:11434/';
  E4B_MODEL   = 'gemma4:e4b';
  E2B_MODEL   = 'gemma4:e2b';
  GEMINI_KEY  = '@GEMINI_API_KEY';
  TTS_VOICE   = 'Puck';
  SEP         = '------------------------------------------------------------';

// ---------------------------------------------------------------------------
type
  TErrorCapture = class
  private
    FMsg: String;
    FCode: Integer;
  public
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AEx: Exception; const AResp: IHTTPResponse);
    function HasError: Boolean;
    procedure Clear;
    property Msg: String read FMsg;
    property Code: Integer read FCode;
  end;

procedure TErrorCapture.OnError(Sender: TObject; const ErrorMsg: string;
  AEx: Exception; const AResp: IHTTPResponse);
begin
  FMsg  := ErrorMsg;
  FCode := 0;
  if Assigned(AResp) then FCode := AResp.StatusCode;
end;

function TErrorCapture.HasError: Boolean;
begin
  Result := FMsg <> '';
end;

procedure TErrorCapture.Clear;
begin
  FMsg := '';
  FCode := 0;
end;

// ---------------------------------------------------------------------------
procedure PrintResult(const Title, Text: String);
begin
  Writeln;
  Writeln('=== ', Title, ' ===');
  if Text = '' then
    Writeln('  [NO RESULT]')
  else
    Writeln(Text);
end;

procedure PrintError(const EC: TErrorCapture);
begin
  Writeln('  [ERROR] ', EC.Msg);
  if EC.Code > 0 then
    Writeln('  HTTP ', EC.Code);
end;

// ---------------------------------------------------------------------------
// Creates an Ollama connection.
//   ForceSttBridge=True  → ModelCaps=[] forces the Gemini STT bridge
//   ForceSttBridge=False → ModelCaps from the registry (gemma4 includes native cap_Audio)
// ---------------------------------------------------------------------------
function MakeOllamaConn(const AModel: String;
  ForceSttBridge: Boolean;
  EC: TErrorCapture;
  SpeechTool: TAiGeminiSpeechTool): TAiChatConnection;
var
  Conn: TAiChatConnection;
begin
  Conn := TAiChatConnection.Create(nil);

  // IMPORTANT: SpeechTool and OnError are assigned BEFORE DriverName.
  // DriverName triggers SetupChatFromDriver → ApplyParamsToChat, which copies
  // Conn.FChatTools to the internal FChat. If SpeechTool is assigned later,
  // FChat.FChatTools.FSpeechTool remains nil and the STT bridge fails.
  Conn.SpeechTool := SpeechTool;
  Conn.OnError := EC.OnError;

  Conn.DriverName := 'Ollama';
  Conn.Params.Values['URL']          := OLLAMA_URL;
  Conn.Params.Values['Model']        := AModel;
  Conn.Params.Values['Asynchronous'] := 'False';
  Conn.Params.Values['Max_Tokens']   := '1024';
  if ForceSttBridge then
  begin
    // Gap=[cap_Audio] → Phase 1 activates TAiGeminiSpeechTool.ExecuteTranscription
    Conn.Params.Values['ModelCaps']    := '[]';
    Conn.Params.Values['SessionCaps']  := '[cap_Audio]';
    Conn.Params.Values['Tool_Active']  := 'False';
  end
  else
  begin
    // gemma4 registered with native cap_Audio → registry values are used
    // Note: Ollama does not serialize audio in the API → the model will receive empty text
    Conn.Params.Values['Tool_Active']  := 'True';
  end;
  Result := Conn;
end;

// ===========================================================================
// SCENARIO 1: Native audio — gemma4 receives the file directly
// ===========================================================================
function RunNativeAudio(const AModel, AAudioFile, AQuestion: String;
  SpeechTool: TAiGeminiSpeechTool): String;
var
  Conn      : TAiChatConnection;
  AudioFile : TAiMediaFile;
  EC        : TErrorCapture;
begin
  Result := '';
  Writeln;
  Writeln('>>> SCENARIO 1 — Native audio');
  Writeln('    Model   : ', AModel, ' (cap_Audio in ModelCaps → no STT bridge)');
  Writeln('    Audio   : ', AAudioFile);
  Writeln('    Question: ', AQuestion);
  Writeln(SEP);

  EC   := TErrorCapture.Create;
  Conn := MakeOllamaConn(AModel, False, EC, SpeechTool);
  try
    // ModelCaps from the registry includes cap_Audio → Gap = [] → audio goes directly
    // to Ollama without going through Gemini
    AudioFile := TAiMediaFile.Create;
    AudioFile.LoadFromFile(AAudioFile);
    Writeln('  Loaded: ', AudioFile.Content.Size, ' bytes  MIME: ', AudioFile.MimeType);
    Writeln('  Note: Ollama serializes audio as an image in the multimodal API.');
    Writeln('        If the model responds "attach the audio", the Ollama API');
    Writeln('        does not support native audio — use the STT bridge (Scenario 2).');
    Writeln('  Sending audio directly to ', AModel, ' via Ollama...');

    Result := Conn.AddMessageAndRun(AQuestion, 'user', [AudioFile]);

    if EC.HasError then
      PrintError(EC)
    else
      PrintResult('Response from ' + AModel + ' (native)', Result);
  finally
    Conn.Free;
    EC.Free;
  end;
end;

// ===========================================================================
// SCENARIO 2: STT Bridge — Gemini transcribes → gemma4 responds in text
// ===========================================================================
function RunSTTBridge(const AModel, AAudioFile, AQuestion: String;
  SpeechTool: TAiGeminiSpeechTool): String;
var
  Conn      : TAiChatConnection;
  AudioFile : TAiMediaFile;
  EC        : TErrorCapture;
begin
  Result := '';
  Writeln;
  Writeln('>>> SCENARIO 2 — STT Bridge (Gemini transcribes → ', AModel, ')');
  Writeln('    ModelCaps=[]  /  SessionCaps=[cap_Audio]  →  Gap=[cap_Audio]');
  Writeln('    Audio   : ', AAudioFile);
  Writeln('    Question: ', AQuestion);
  Writeln(SEP);

  EC   := TErrorCapture.Create;
  Conn := MakeOllamaConn(AModel, True, EC, SpeechTool);
  try
    // Gap=[cap_Audio] activates:
    //   Phase 1 → ExecuteTranscription(Gemini 2.0-flash) → AskMsg.Prompt increased
    //   Phase 3 → InternalRunCompletions → gemma4 receives only text
    AudioFile := TAiMediaFile.Create;
    AudioFile.LoadFromFile(AAudioFile);
    Writeln('  Loaded: ', AudioFile.Content.Size, ' bytes  MIME: ', AudioFile.MimeType);
    Writeln('  Transcribing with Gemini and sending text to ', AModel, '...');

    Result := Conn.AddMessageAndRun(AQuestion, 'user', [AudioFile]);

    if EC.HasError then
      PrintError(EC)
    else
      PrintResult('Response from ' + AModel + ' (STT bridge)', Result);
  finally
    Conn.Free;
    EC.Free;
  end;
end;

// ===========================================================================
// SCENARIO 3: Direct TTS — text → Gemini TTS → WAV file
// ===========================================================================
procedure RunTTSDirect(const AText, AOutFile: String);
var
  Audio: TAiMediaFile;
begin
  Writeln;
  Writeln('>>> SCENARIO 3 — Direct TTS (Gemini TTS → WAV)');
  Writeln('    Text  : ', Copy(AText, 1, 80), IfThen(Length(AText) > 80, '...', ''));
  Writeln('    Output: ', AOutFile);
  Writeln('    Voice : ', TTS_VOICE);
  Writeln(SEP);
  Writeln('  Generating audio with Gemini TTS...');

  Audio := TAiGeminiSpeechTool.GenerateSpeech(
    GetEnvironmentVariable('GEMINI_API_KEY'),
    AText, TTS_VOICE, nil, nil, nil);

  if Assigned(Audio) then
  begin
    try
      Audio.Content.SaveToFile(AOutFile);
      Writeln('  Saved: ', AOutFile, '  (', Audio.Content.Size, ' bytes)');
    finally
      Audio.Free;
    end;
  end
  else
    Writeln('  [ERROR] Gemini TTS did not return audio. Check GEMINI_API_KEY.');
end;

// ===========================================================================
// SCENARIO 4: Full pipeline — audio → STT bridge → gemma4 → TTS
// ===========================================================================
procedure RunFullPipeline(const AModel, AAudioFile, AQuestion: String;
  SpeechTool: TAiGeminiSpeechTool);
var
  ModelResponse : String;
  OutFile       : String;
begin
  Writeln;
  Writeln('>>> SCENARIO 4 — Full pipeline (audio → STT → ', AModel, ' → TTS)');
  Writeln(SEP);

  ModelResponse := RunSTTBridge(AModel, AAudioFile, AQuestion, SpeechTool);

  if ModelResponse = '' then
  begin
    Writeln('  [SKIP] No LLM response to convert to audio.');
    Exit;
  end;

  OutFile := ExtractFilePath(ParamStr(0)) + 'pipeline_respuesta.wav';
  RunTTSDirect(ModelResponse, OutFile);
end;

// ===========================================================================
// MAIN
// ===========================================================================
var
  AudioPath, Question : String;
  SpeechTool          : TAiGeminiSpeechTool;
  HasAudio            : Boolean;
begin
  Writeln('=== MakerAI — AudioBridge Demo (gemma4) ===');
  Writeln('Ollama models  : ', E4B_MODEL, '  /  ', E2B_MODEL);
  Writeln('Bridge STT     : TAiGeminiSpeechTool (gemini-2.0-flash)');
  Writeln('TTS            : TAiGeminiSpeechTool (gemini-2.5-flash-preview-tts)');
  Writeln;

  try
    SpeechTool := TAiGeminiSpeechTool.Create(nil);
    try
      SpeechTool.ApiKey              := GEMINI_KEY;
      SpeechTool.TranscriptionModel  := 'gemini-2.0-flash';
      SpeechTool.TranscriptionPrompt := 'Transcribe this audio accurately. ' +
                                        'If it is Spanish, transcribe in Spanish.';
      SpeechTool.Model               := 'gemini-2.5-flash-preview-tts';
      SpeechTool.Voice               := TTS_VOICE;

      // -- Audio file path -----------------------------------------------------
      HasAudio := False;
      if ParamCount >= 1 then
        AudioPath := Trim(ParamStr(1))
      else
      begin
        Write('Audio file path (Enter to skip): ');
        Readln(AudioPath);
        AudioPath := Trim(AudioPath);
      end;

      if AudioPath <> '' then
      begin
        if not FileExists(AudioPath) then
          raise Exception.CreateFmt('File not found: "%s"', [AudioPath]);
        HasAudio := True;
      end;

      // -- Question ------------------------------------------------------------
      if ParamCount >= 2 then
        Question := ParamStr(2)
      else if HasAudio then
        Question := 'Briefly summarize the audio content.'
      else
        Question := '';

      // -----------------------------------------------------------------------
      // Scenario 3: TTS (always available, does not require input audio)
      // -----------------------------------------------------------------------
      RunTTSDirect(
        'Hello! I am gemma4, a local language model running in Ollama. ' +
        'I am being tested with the MakerAI audio bridge system.',
        ExtractFilePath(ParamStr(0)) + 'tts_demo.wav');

      // -----------------------------------------------------------------------
      // Scenarios with audio
      // -----------------------------------------------------------------------
      if HasAudio then
      begin
        Writeln;
        Writeln('=== TESTS WITH AUDIO: ', ExtractFileName(AudioPath), ' ===');

        // -- Scenario 1: Native audio with e4b and e2b --
        RunNativeAudio(E4B_MODEL, AudioPath, Question, SpeechTool);
        RunNativeAudio(E2B_MODEL, AudioPath, Question, SpeechTool);

        // -- Scenario 2: STT Bridge with e4b and e2b --
        RunSTTBridge(E4B_MODEL, AudioPath, Question, SpeechTool);
        RunSTTBridge(E2B_MODEL, AudioPath, Question, SpeechTool);

        // -- Scenario 4: Full pipeline with e4b --
        RunFullPipeline(E4B_MODEL, AudioPath, Question, SpeechTool);
      end
      else
      begin
        Writeln;
        Writeln(SEP);
        Writeln('INFO: No audio file was provided.');
        Writeln('      Scenarios 1, 2, and 4 require an audio file.');
        Writeln('      Pass the path as the first argument:');
        Writeln('        AudioBridge.exe D:\path\audio.wav');
      end;

    finally
      SpeechTool.Free;
    end;

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
