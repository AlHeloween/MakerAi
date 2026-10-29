program WhisperDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 12: Speech-to-Text: Whisper and alternative providers
// =============================================================================
// Demonstrates batch audio transcription with TAIWhisper and TAiOpenAiAudio.
// All demos use the same input audio file.
//
//   Demo 1 -- TAIWhisper + OpenAI (whisper-1) -- base case
//     Direct transcription: load stream, call Transcription().
//     The API key is taken from OPENAI_API_KEY; the default model is whisper-1.
//
//   Demo 2 -- TAIWhisper + Groq (whisper-large-v3-turbo)
//     Identical to Demo 1. Only Url and ApiKey change.
//     Groq runs Whisper on LPU: up to 216x real time.
//     Requires GROQ_API_KEY configured.
//
//   Demo 3 -- TAIWhisper + whisper.cpp local (total privacy)
//     Identical to Demo 1. Only Url and ApiKey change (can be any string).
//     Requires the whisper.cpp server running at WHISPER_LOCAL_URL.
//     If the server is not available, the demo shows instructions and continues.
//
//   Demo 4 -- Word timestamps with verbose_json
//     ResponseFormat = 'verbose_json' + timestamp_granularities = 'word'.
//     Only available with whisper-1 and classic Whisper providers.
//     Parses the response JSON and shows [time] word by word.
//
//   Demo 5 -- TAiOpenAiAudio + gpt-4o-transcribe + logprobs
//     Modern component. TranscriptionLogprobs = True requests confidence
//     per token. Tokens with Exp(logprob) < 0.8 are marked as uncertain [?token?].
//
//   Demo 6 -- Diarization with gpt-4o-transcribe-diarize
//     Identifies who spoke which fragment. No Python, no GPU, in the cloud.
//     Parses Result.RawJson -> 'segments' -> speaker + text + start.
//
// Requirements:
//   Demos 1, 4, 5, 6:  OPENAI_API_KEY in environment variables
//   Demo 2:            GROQ_API_KEY in environment variables
//   Demo 3:            whisper.cpp server at WHISPER_LOCAL_URL
//   All:               An audio file at AUDIO_PATH (MP3, WAV, M4A, OGG...)
//
// To get a test audio file:
//   First run Demo 2 of chapter 11 (TTS) which generates an MP3,
//   or record any voice note from your phone and copy it to AUDIO_PATH.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.Generics.Collections,
  WinApi.Windows,
  uMakerAi.Core,
  uMakerAi.Whisper,
  uMakerAi.OpenAI.Audio;

const
  // Path to the input audio file.
  // Supported formats: mp3, mp4, m4a, ogg, wav, webm, flac.
  AUDIO_PATH = 'C:\Users\Public\Documents\sample.mp3';

  // URL of the local whisper.cpp server (Demo 3).
  // Start with: whisper-server -m models/ggml-turbo.bin -l es --port 8080
  WHISPER_LOCAL_URL = 'http://localhost:8080/v1/';

// =============================================================================

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

function EncontrarAudio: string;
var
  RutaLocal: string;
  Exts: array[0..5] of string;
  i: Integer;
  Archivos: TArray<string>;
begin
  if TFile.Exists(AUDIO_PATH) then
    Exit(AUDIO_PATH);

  // Search in the executable directory
  Exts[0] := 'mp3';  Exts[1] := 'wav';  Exts[2] := 'ogg';
  Exts[3] := 'm4a';  Exts[4] := 'webm'; Exts[5] := 'mp4';
  for i := 0 to High(Exts) do
  begin
    RutaLocal := ExtractFilePath(ParamStr(0)) + 'sample.' + Exts[i];
    if TFile.Exists(RutaLocal) then
      Exit(RutaLocal);
  end;

  Archivos := TDirectory.GetFiles(
    ExtractFilePath(ParamStr(0)), '*.mp3', TSearchOption.soTopDirectoryOnly);
  if Length(Archivos) > 0 then
    Exit(Archivos[0]);

  Archivos := TDirectory.GetFiles(
    ExtractFilePath(ParamStr(0)), '*.wav', TSearchOption.soTopDirectoryOnly);
  if Length(Archivos) > 0 then
    Exit(Archivos[0]);

  Result := '';
end;

// =============================================================================
//  Demo 1 -- TAIWhisper + OpenAI (caso base)
//
//  Transcription(Stream, NombreArchivo, HintPrompt): String
//  The HintPrompt improves accuracy in technical terminology or proper names.
//  Example: 'This is a medical call' improves 'glomerulonefritis'.
// =============================================================================
procedure Demo1_OpenAI(const AudioPath: string);
var
  Whisper: TAIWhisper;
  Stream : TMemoryStream;
  Texto  : string;
begin
  Separador('Demo 1 -- TAIWhisper + OpenAI (whisper-1)');

  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    Whisper.ApiKey         := '@OPENAI_API_KEY';  // default
    Whisper.Model          := 'whisper-1';
    Whisper.Languaje       := 'es';
    Whisper.ResponseFormat := 'text';

    Stream.LoadFromFile(AudioPath);
    WriteLn('  File    : ', ExtractFileName(AudioPath));
    WriteLn('  Size    : ', Stream.Size div 1024, ' KB');
    WriteLn('');

    Write('  Transcribing (whisper-1)... ');
    Texto := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Result:');
    WriteLn('  ', Texto);
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('-> Pattern: TAIWhisper.Transcription(Stream, FileName, HintPrompt).');
  WriteLn('   Change only Url + ApiKey to point to Groq or whisper.cpp.');
end;

// =============================================================================
//  Demo 2 -- El mismo codigo con Groq (hasta 216x tiempo real)
//
//  The code is identical to Demo 1. Only Url and ApiKey change.
//  Groq uses LPU (Language Processing Unit) to run Whisper at maximum
//  speed: 60 minutes of audio are transcribed in ~13 seconds.
// =============================================================================
procedure Demo2_Groq(const AudioPath: string);
var
  Whisper: TAIWhisper;
  Stream : TMemoryStream;
  Texto  : string;
begin
  Separador('Demo 2 -- TAIWhisper + Groq (whisper-large-v3-turbo)');

  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    // *** Unica diferencia respecto al Demo 1: Url y ApiKey ***
    Whisper.Url    := 'https://api.groq.com/openai/v1/';
    Whisper.ApiKey := '@GROQ_API_KEY';
    Whisper.Model  := 'whisper-large-v3-turbo';  // 216x tiempo real
    Whisper.Languaje       := 'es';
    Whisper.ResponseFormat := 'text';

    Stream.LoadFromFile(AudioPath);
    WriteLn('  File    : ', ExtractFileName(AudioPath));
    WriteLn('');

    Write('  Transcribing (whisper-large-v3-turbo on Groq LPU)... ');
    Texto := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Result:');
    WriteLn('  ', Texto);
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('-> whisper-large-v3-turbo: quality close to large-v3, 216x faster.');
  WriteLn('   Groq free tier: up to 2 hours of audio per clock hour.');
end;

// =============================================================================
//  Demo 3 -- El mismo codigo con whisper.cpp local (sin internet)
//
//  whisper.cpp exposes the same HTTP API as OpenAI. No data leaves
//  your machine. Ideal for environments with privacy restrictions.
//
//  To start the local server (Windows):
//    whisper-server.exe -m models\ggml-turbo.bin -l es --port 8080
//
//  The demo detects if the server is not available and shows instructions.
// =============================================================================
procedure Demo3_Local(const AudioPath: string);
var
  Whisper: TAIWhisper;
  Stream : TMemoryStream;
  Texto  : string;
begin
  Separador('Demo 3 -- TAIWhisper + whisper.cpp local (total privacy)');
  WriteLn('  Expected server at: ', WHISPER_LOCAL_URL);
  WriteLn('');

  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    // *** Unica diferencia: Url local; ApiKey puede ser cualquier string ***
    Whisper.Url    := WHISPER_LOCAL_URL;
    Whisper.ApiKey := 'local';  // whisper.cpp no valida la clave
    Whisper.Model  := 'turbo';  // nombre del modelo cargado en el servidor
    Whisper.Languaje       := 'es';
    Whisper.ResponseFormat := 'text';

    Stream.LoadFromFile(AudioPath);

    Write('  Transcribing (whisper.cpp local)... ');
    try
      Texto := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
      WriteLn('OK');
      WriteLn('');
      WriteLn('  Result:');
      WriteLn('  ', Texto);
    except
      on E: Exception do
      begin
        WriteLn('SERVER NOT AVAILABLE');
        WriteLn('');
        WriteLn('  To run this demo:');
        WriteLn('  1. Download whisper.cpp: https://github.com/ggml-org/whisper.cpp');
        WriteLn('  2. Compile: cmake -B build && cmake --build build --config Release');
        WriteLn('  3. Download model: bash models/download-ggml-model.sh turbo');
        WriteLn('  4. Start server:');
        WriteLn('       whisper-server.exe -m models\ggml-turbo.bin -l es --port 8080');
        WriteLn('');
        WriteLn('  The Delphi code does not change. Only the URL.');
      end;
    end;
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('-> No data leaves your machine. No cost per request.');
  WriteLn('   int8 quantization (ggml-turbo-q5_0.bin): size ~600 MB.');
end;

// =============================================================================
//  Demo 4 -- Timestamps por palabra con verbose_json
//
//  ResponseFormat = 'verbose_json' returns the full text plus an array
//  'words' with the start time of each word. Useful for:
//    - Karaoke / subtitle synchronization
//    - Highlighting words while audio plays
//    - Detecting long pauses in speech
//
//  Only available with whisper-1 (and Groq whisper-large-v3).
//  The gpt-4o-transcribe models do not support verbose_json.
// =============================================================================
procedure Demo4_Timestamps(const AudioPath: string);
var
  Whisper : TAIWhisper;
  Stream  : TMemoryStream;
  JSON    : string;
  JObj    : TJSONObject;
  JWords  : TJSONArray;
  JW      : TJSONObject;
  i       : Integer;
  Palabra : string;
  Inicio  : Double;
begin
  Separador('Demo 4 -- Word timestamps (verbose_json)');

  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    Whisper.ApiKey                  := '@OPENAI_API_KEY';
    Whisper.Model                   := 'whisper-1';
    Whisper.Languaje                := 'es';
    Whisper.ResponseFormat          := 'verbose_json';
    Whisper.timestamp_granularities := 'word';

    Stream.LoadFromFile(AudioPath);
    WriteLn('  Requesting word timestamps...');
    WriteLn('');

    Write('  Transcribing... ');
    JSON := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
    WriteLn('OK');
    WriteLn('');

    JObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
    if not Assigned(JObj) then
    begin
      WriteLn('  ERROR: respuesta no es JSON valido.');
      Exit;
    end;
    try
      // Texto completo
      WriteLn('  Full text:');
      WriteLn('  ', JObj.GetValue<string>('text'));
      WriteLn('');

      // Timestamps por palabra
      JWords := JObj.GetValue<TJSONArray>('words');
      if Assigned(JWords) and (JWords.Count > 0) then
      begin
        WriteLn('  Words with timestamp (first 20):');
        for i := 0 to Min(JWords.Count - 1, 19) do
        begin
          JW     := JWords.Items[i] as TJSONObject;
          Inicio  := JW.GetValue<Double>('start');
          Palabra := JW.GetValue<string>('word');
          WriteLn(Format('    [%5.2fs]  %s', [Inicio, Trim(Palabra)]));
        end;
        if JWords.Count > 20 then
          WriteLn(Format('    ... (%d words in total)', [JWords.Count]));
      end
      else
        WriteLn('  (no words in response — verify that the audio has speech)');
    finally
      JObj.Free;
    end;
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('-> verbose_json also contains "segments" with timestamps per phrase.');
  WriteLn('   Groq whisper-large-v3 also supports verbose_json.');
  WriteLn('   gpt-4o-transcribe does NOT support verbose_json (degrades to json).');
end;

// =============================================================================
//  Demo 5 -- TAiOpenAiAudio + gpt-4o-transcribe + logprobs
//
//  gpt-4o-transcribe has a WER of 2.46% (almost 4x better than whisper-1).
//  With TranscriptionLogprobs=True, the API returns the probability of each
//  token. This allows marking low-confidence words for human review.
//
//  Prob = Exp(logprob):
//    Prob = 1.0  -> total certainty
//    Prob = 0.8  -> good confidence (common threshold)
//    Prob = 0.5  -> half probability
//    Prob < 0.3  -> probable transcription error
// =============================================================================
procedure Demo5_Logprobs(const AudioPath: string);
var
  Audio  : TAiOpenAiAudio;
  MF     : TAiMediaFile;
  Res    : TTranscriptionResult;
  JToken : TJSONObject;
  Token  : string;
  LogP   : Double;
  Prob   : Double;
  i      : Integer;
begin
  Separador('Demo 5 -- TAiOpenAiAudio + gpt-4o-transcribe + logprobs');

  Audio := TAiOpenAiAudio.Create(nil);
  MF    := TAiMediaFile.Create;
  try
    Audio.ApiKey                 := '@OPENAI_API_KEY';
    Audio.TranscriptionModel     := tmGpt4oTranscribe;  // WER 2.46%
    Audio.TranscriptionLanguage  := 'es';
    Audio.TranscriptionLogprobs  := True;               // pedir confianza por token

    MF.LoadFromFile(AudioPath);
    WriteLn('  Model   : gpt-4o-transcribe (WER 2.46%)');
    WriteLn('  Logprobs: True (confidence per token)');
    WriteLn('');

    Write('  Transcribing... ');
    Res := Audio.Transcribe(MF);
    try
      WriteLn('OK');
      WriteLn('');
      WriteLn('  Full text:');
      WriteLn('  ', Res.Text);
      WriteLn('');

      if Assigned(Res.Logprobs) and (Res.Logprobs.Count > 0) then
      begin
        WriteLn('  Confidence analysis (? = Prob < 0.8):');
        Write('  ');
        for i := 0 to Res.Logprobs.Count - 1 do
        begin
          JToken := Res.Logprobs.Items[i] as TJSONObject;
          Token  := JToken.GetValue<string>('token');
          LogP   := JToken.GetValue<Double>('logprob');
          Prob   := Exp(LogP);

          if Prob < 0.8 then
            Write('[?' + Token + '?]')  // baja confianza
          else
            Write(Token);               // alta confianza
        end;
        WriteLn;
        WriteLn('');
        WriteLn(Format('  Total tokens: %d', [Res.Logprobs.Count]));
      end
      else
        WriteLn('  (logprobs not returned -- verify that the model is gpt-4o-transcribe)');
    finally
      Res.Free;
    end;
  finally
    MF.Free;
    Audio.Free;
  end;

  WriteLn('');
  WriteLn('-> Logprob = ln(probability). Exp(logprob) gives the probability 0..1.');
  WriteLn('   Recommended threshold: 0.8. Tokens below that threshold deserve review.');
  WriteLn('   Only available with gpt-4o-transcribe and gpt-4o-mini-transcribe.');
end;

// =============================================================================
//  Demo 6 -- Diarizacion: quien hablo que
//
//  gpt-4o-transcribe-diarize identifies the different speakers and associates
//  each fragment with a speaker. No Python, no GPU, in the OpenAI cloud.
//
//  Ideal for:
//    - Meeting minutes ("SPEAKER_0 proposed..., SPEAKER_1 replied...")
//    - Interviews and podcasts
//    - Call centers (customer vs. agent)
//
//  Note: requires audio with two or more distinct voices for
//  diarization to be visible in the output.
// =============================================================================
procedure Demo6_Diarizacion(const AudioPath: string);
var
  Audio : TAiOpenAiAudio;
  MF    : TAiMediaFile;
  Res   : TTranscriptionResult;
  JSegs : TJSONArray;
  JSeg  : TJSONObject;
  i     : Integer;
  Speaker, Texto: string;
  Inicio: Double;
begin
  Separador('Demo 6 -- Diarization (gpt-4o-transcribe-diarize)');

  Audio := TAiOpenAiAudio.Create(nil);
  MF    := TAiMediaFile.Create;
  try
    Audio.ApiKey                        := '@OPENAI_API_KEY';
    Audio.TranscriptionModel            := tmGpt4oDiarize;
    Audio.TranscriptionResponseFormat   := trfDiarizedJson;
    Audio.TranscriptionLanguage         := 'es';

    MF.LoadFromFile(AudioPath);
    WriteLn('  Model   : gpt-4o-transcribe-diarize');
    WriteLn('  Format  : diarized_json');
    WriteLn('');

    Write('  Transcribing with speaker identification... ');
    Res := Audio.Transcribe(MF);
    try
      WriteLn('OK');
      WriteLn('');
      WriteLn('  Full transcription:');
      WriteLn('  ', Res.Text);
      WriteLn('');

      if Assigned(Res.RawJson) then
      begin
        JSegs := Res.RawJson.GetValue('segments') as TJSONArray;  // nil-safe (non-generic)
        if Assigned(JSegs) and (JSegs.Count > 0) then
        begin
          WriteLn('  Segments by speaker:');
          for i := 0 to JSegs.Count - 1 do
          begin
            JSeg    := JSegs.Items[i] as TJSONObject;
            Speaker := JSeg.GetValue<string>('speaker');
            Texto   := JSeg.GetValue<string>('text');
            Inicio  := JSeg.GetValue<Double>('start');
            WriteLn(Format('    [%5.1fs]  %-12s %s', [Inicio, Speaker + ':', Trim(Texto)]));
          end;
        end
        else
        begin
          WriteLn('  (a single speaker detected or audio too short)');
          WriteLn('  Tip: use an audio with two or more distinct voices to see');
          WriteLn('       diarization in action.');
        end;
      end;
    finally
      Res.Free;
    end;
  finally
    MF.Free;
    Audio.Free;
  end;

  WriteLn('');
  WriteLn('-> The labels SPEAKER_0, SPEAKER_1... are automatic.');
  WriteLn('   To rename them, map Speaker -> real name in your application.');
  WriteLn('   Open source alternative: WhisperX + pyannote (see section 12.6).');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  AudioPath     : string;
  TieneOpenAI   : Boolean;
  TieneGroq     : Boolean;
begin
  SetConsoleOutputCP(65001);  // UTF-8 in Windows console
  WriteLn('=== MakerAI -- Chapter 12: Whisper and Batch STT ===');
  WriteLn('Demos: 6 ways to transcribe audio in Delphi.');
  WriteLn('');

  // Verificar recursos disponibles
  AudioPath   := EncontrarAudio;
  TieneOpenAI := GetEnvironmentVariable('OPENAI_API_KEY') <> '';
  TieneGroq   := GetEnvironmentVariable('GROQ_API_KEY') <> '';

  WriteLn('  Status:');
  if TieneOpenAI then
    WriteLn('  [OK] OPENAI_API_KEY detected')
  else
    WriteLn('  [--] OPENAI_API_KEY not configured -- demos 1,4,5,6 skipped');

  if TieneGroq then
    WriteLn('  [OK] GROQ_API_KEY detected')
  else
    WriteLn('  [--] GROQ_API_KEY not configured -- demo 2 skipped');

  if AudioPath <> '' then
    WriteLn('  [OK] Audio found: ', ExtractFileName(AudioPath))
  else
  begin
    WriteLn('  [--] Audio not found at: ', AUDIO_PATH);
    WriteLn('       Copy an MP3/WAV file to that path and run again.');
    WriteLn('       Or run Demo 2 of cap11 (TTS) to generate one.');
    WriteLn('');
    WriteLn('Press Enter to exit...');
    ReadLn;
    Exit;
  end;

  // Demos con OpenAI (1, 4, 5, 6)
  if TieneOpenAI then
  begin
    Demo1_OpenAI(AudioPath);
    Demo4_Timestamps(AudioPath);
    Demo5_Logprobs(AudioPath);
    Demo6_Diarizacion(AudioPath);
  end
  else
  begin
    WriteLn('');
    WriteLn('--- Demos 1, 4, 5, 6 skipped (OPENAI_API_KEY not configured) ---');
  end;

  // Demo con Groq (2)
  if TieneGroq then
    Demo2_Groq(AudioPath)
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 2 skipped (GROQ_API_KEY not configured) ---');
    WriteLn('    Register for free at console.groq.com to get your key.');
  end;

  // Demo local (3) -- siempre se intenta, maneja el error internamente
  Demo3_Local(AudioPath);

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demos completed.');
  WriteLn('  Ch.12 also covers Realtime STT (WebSocket).');
  WriteLn('  See: Demos/Console/Demos09-Realtime/01-RealtimeSTT/');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' -- ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
