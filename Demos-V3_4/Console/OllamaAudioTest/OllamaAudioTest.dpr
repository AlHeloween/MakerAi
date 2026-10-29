program OllamaAudioTest;

{$APPTYPE CONSOLE}

// =============================================================================
// OllamaAudioTest — bridge STT + TTS: gemma3:4b (Ollama) + TAiGeminiSpeechTool
// =============================================================================
// Demuestra cómo usar un modelo Ollama sin capacidad de audio nativa
// (gemma3:4b) combinado con TAiGeminiSpeechTool como bridge automático.
//
// ESCENARIO A — STT bridge (Fase 1 del orquestador):
//   ModelCaps=[] / SessionCaps=[cap_Audio]  →  Gap=[cap_Audio]
//   El orquestador detecta el gap y llama TAiGeminiSpeechTool.ExecuteTranscription
//   antes de enviar el mensaje al modelo. La transcripción se inyecta en el
//   prompt y gemma3:4b responde como si hubiera recibido texto plano.
//
// ESCENARIO B — TTS (generación de audio de la respuesta):
//   Toma el texto de respuesta del escenario A y usa TAiGeminiSpeechTool
//   para generar un archivo WAV de salida (respuesta_audio.wav).
//
// Uso:
//   OllamaAudioTest.exe [ruta_audio] [pregunta]
//
//   Si no se pasan argumentos, los pide de forma interactiva.
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
  Writeln('[ERROR DEL LLM]');
  Writeln('  Mensaje : ', ErrCap.ErrorMsg);
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
  Writeln('  Pregunta: ', AQuestion);
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
    // ModelCaps=[] → gemma3:4b no tiene audio nativo
    // SessionCaps=[cap_Audio] → queremos audio en la sesión
    // Gap=[cap_Audio] → orquestador activa bridge STT (FASE 1)
    Conn.Params.Values['ModelCaps']    := '[]';
    Conn.Params.Values['SessionCaps']  := '[cap_Audio]';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.OnError := ErrCap.OnError;

    // -- Assign the SpeechTool to the bridge --
    Conn.SpeechTool := SpeechTool;

    // -- Cargar audio --
    // IMPORTANTE: AddMessageAndRun asume ownership del TAiMediaFile.
    // NO liberar AudioFile; la lista FMessages lo libera al destruir la conexión.
    AudioFile := TAiMediaFile.Create;
    AudioFile.LoadFromFile(AAudioFile);
    Writeln('  Loaded : ', AudioFile.Content.Size, ' bytes',
            ' | MIME: ', AudioFile.MimeType,
            ' | Cat: ', GetEnumName(TypeInfo(TAiFileCategory), Ord(AudioFile.FileCategory)));
    Writeln('  Transcribing with Gemini + sending to ', MODEL, ' (please wait...)');

    // El orquestador detecta Gap=[cap_Audio]:
    //   FASE 1 → TAiGeminiSpeechTool.ExecuteTranscription(audioFile, ...)
    //          → MF.Transcription = texto
    //          → AskMsg.Prompt += '[Transcripción de audio]:...'
    //   FASE 3 → InternalRunCompletions → gemma3:4b recibe prompt aumentado
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
    'Puck',   // voz (Puck, Kore, Charon, Fenrir, Aoede, etc.)
    nil, nil, nil);

  if Assigned(AudioResult) then
  begin
    OutputFile := ExtractFilePath(ParamStr(0)) + 'respuesta_audio.wav';
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
      Question := 'Resume brevemente qué dice el audio.';

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
