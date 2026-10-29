program AsistenteVoz;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 11: Voice — From audio to text and from text to voice
// =============================================================================
// Demonstrates the complete voice flow with MakerAI: STT, TTS and pipeline
// integrated. All demos use only the OpenAI API.
//
//   Demo 1 — STT with TAIWhisper (standalone)
//     Transcribes an MP3/WAV audio file to text using Whisper.
//     Direct API: does not require TAiChatConnection.
//
//   Demo 2 — TTS with TAiOpenAiAudio (standalone)
//     Converts text to voice and saves the resulting MP3 to disk.
//     Direct API: tts-1 / tts-1-hd models, 11 different voices.
//
//   Demo 3 — Complete voice assistant (manual pipeline)
//     Audio MP3 → Whisper (STT) → gpt-4o-mini (LLM) → TTS → MP3
//     Shows how to chain the three phases in a single function.
//
//   Demo 4 — cmTranscription via TAiChatConnection
//     TAiChatConnection.ChatMode = cmTranscription + assigned SpeechTool.
//     Clean pattern to integrate STT in applications with chat history.
//
// Note about microphone:
//   TAiVoiceMonitor (real-time capture) and Realtime modes are covered
//   in Chapter 12. Here we work exclusively with audio files.
//
// Requirements:
//   All demos: OPENAI_API_KEY in environment variables
//   Demos 1, 3, 4:   An MP3 or WAV audio file (see AUDIO_PATH)
//
// How to test without your own audio file:
//   Record any voice note from your phone and copy it to AUDIO_PATH,
//   or first run Demo 2 (generates an MP3) and use it as input.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi,    // DriverName = 'OpenAI' — auto-registers on import
  uMakerAi.Whisper,        // TAIWhisper — legacy STT, simple and direct
  uMakerAi.OpenAI.Audio;   // TAiOpenAiAudio — modern TTS with typed enums

const
  OPENAI_DRIVER = 'OpenAI';
  OPENAI_MODEL  = 'gpt-4o-mini';

  // Path to the input audio file for STT demos.
  // Formats supported by Whisper: mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm.
  // If the file does not exist, the STT demos are skipped with instructions.
  AUDIO_PATH = 'C:\Users\Public\Documents\sample.mp3';

  // Output files for the TTS demos (created or overwritten).
  OUTPUT_TTS_DEMO2    = 'C:\Users\Public\Documents\tts_demo2.mp3';
  OUTPUT_TTS_PIPELINE = 'C:\Users\Public\Documents\tts_demo3.mp3';

// =============================================================================
procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
function OpenAiApiKeyDisponible: Boolean;
begin
  Result := GetEnvironmentVariable('OPENAI_API_KEY') <> '';
end;

// =============================================================================
//  Searches for the audio file in AUDIO_PATH and in the executable directory.
// =============================================================================
function EncontrarAudio: string;
var
  RutaLocal: string;
  Exts     : array[0..5] of string;
  i        : Integer;
begin
  if TFile.Exists(AUDIO_PATH) then
    Exit(AUDIO_PATH);

  // Search in the executable directory (formats supported by Whisper)
  Exts[0] := 'mp3';  Exts[1] := 'wav';  Exts[2] := 'ogg';
  Exts[3] := 'm4a';  Exts[4] := 'webm'; Exts[5] := 'mp4';
  for i := 0 to High(Exts) do
  begin
    RutaLocal := ExtractFilePath(ParamStr(0)) + 'sample.' + Exts[i];
    if TFile.Exists(RutaLocal) then
      Exit(RutaLocal);
  end;

  // Search for any MP3 or WAV in the executable directory
  var Archivos := TDirectory.GetFiles(
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
//  Demo 1 — Direct STT with TAIWhisper
//
//  TAIWhisper is the legacy interface for Whisper. Simple and direct:
//  loads the audio into a TMemoryStream and calls Transcription().
//  Does not require TAiChatConnection — it is an independent component.
//
//  API:
//    Whisper.Transcription(Stream, FileName, Prompt): String
//    Whisper.Languaje := 'es';   // ISO-639-1; blank = auto-detect
//    Whisper.Model   := 'whisper-1';  // only public model as of May 2026
// =============================================================================
procedure Demo1_STT_Whisper(const AudioPath: string);
var
  Whisper: TAIWhisper;
  Stream : TMemoryStream;
  Texto  : string;
begin
  Separador('Demo 1 — STT with TAIWhisper (direct transcription)');

  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    Whisper.ApiKey  := '@OPENAI_API_KEY';
    Whisper.Model   := 'whisper-1';
    Whisper.Languaje := 'es';    // note: property with intentional typo in the source

    Stream.LoadFromFile(AudioPath);
    WriteLn('  File     : ', ExtractFileName(AudioPath));
    WriteLn('  Size     : ', Stream.Size div 1024, ' KB');
    WriteLn('');

    Write('  Transcribing... ');
    Texto := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Transcription:');
    WriteLn('  ', Texto);
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('→ Pattern: TAIWhisper.Transcription(Stream, FileName, HintPrompt).');
  WriteLn('  The "prompt" parameter is an optional hint to improve accuracy.');
  WriteLn('  For example: ''This is a medical call'' improves technical terms.');
end;

// =============================================================================
//  Demo 2 — Direct TTS with TAiOpenAiAudio
//
//  TAiOpenAiAudio is the modern OpenAI Audio API. Uses typed enums
//  instead of strings to avoid typing errors in model/voice.
//
//  API:
//    Audio.Speech(Text): TMemoryStream   // returns the audio in memory
//    Audio.TTSModel  := tts_1;            // o tts_1_hd, gpt_4o_mini_tts
//    Audio.TTSVoice  := tvAlloy;          // 11 voices: alloy, ash, ballad...
//    Audio.TTSResponseFormat := trfMp3;   // mp3, opus, aac, flac, wav, pcm
//    Audio.TTSSpeed  := 1.0;             // 0.25 to 4.0
// =============================================================================
procedure Demo2_TTS_OpenAiAudio;
const
  TEXTO_DEMO =
    'Hello. I am a voice assistant created with MakerAI and Delphi. ' +
    'This is a demonstration of voice synthesis using the OpenAI API. ' +
    'The text you hear was generated in real time from a Delphi application.';
var
  Audio : TAiOpenAiAudio;
  Stream: TMemoryStream;
begin
  Separador('Demo 2 — TTS with TAiOpenAiAudio (voice synthesis)');

  WriteLn('  Text    : ', Copy(TEXTO_DEMO, 1, 60), '...');
  WriteLn('  Length  : ', Length(TEXTO_DEMO), ' characters');
  WriteLn('');

  Audio := TAiOpenAiAudio.Create(nil);
  try
    Audio.ApiKey            := '@OPENAI_API_KEY';
    Audio.TTSModel          := tts_1;          // standard, low latency
    Audio.TTSVoice          := tvNova;          // female voice, clear and expressive
    Audio.TTSResponseFormat := trfMp3;
    Audio.TTSSpeed          := 1.0;

    Write('  Generating audio (voice: Nova, model: tts-1)... ');
    Stream := Audio.Speech(TEXTO_DEMO);
    try
      if Stream.Size > 0 then
      begin
        Stream.SaveToFile(OUTPUT_TTS_DEMO2);
        WriteLn('OK');
        WriteLn('  Saved: ', OUTPUT_TTS_DEMO2);
        WriteLn('  Size    : ', Stream.Size div 1024, ' KB');
      end
      else
        WriteLn('ERROR — empty stream');
    finally
      Stream.Free;
    end;
  finally
    Audio.Free;
  end;

  WriteLn('');
  WriteLn('→ Speech() returns TMemoryStream — save with SaveToFile().');
  WriteLn('  Available voices: Alloy, Ash, Ballad, Coral, Echo, Fable,');
  WriteLn('                     Onyx, Nova, Sage, Shimmer, Verse.');
  WriteLn('  TTSInstructions   := ''Speak slowly and clearly'' — free tone.');
end;

// =============================================================================
//  Demo 3 — Asistente de voz completo (pipeline manual)
//
//  Chains three phases without magic:
//    1. STT: audio file → text (TAIWhisper)
//    2. LLM: text → AI response (TAiChatConnection with OpenAI)
//    3. TTS: response → MP3 audio (TAiOpenAiAudio)
//
//  This "manual" pattern gives full control over each phase.
//  Chapter 12 shows how to do it in real time with TAiVoiceMonitor.
// =============================================================================
procedure Demo3_PipelineCompleto(const AudioPath: string);
var
  Whisper : TAIWhisper;
  Audio   : TAiOpenAiAudio;
  Conn    : TAiChatConnection;
  Stream  : TMemoryStream;
  Pregunta: string;
  Respuesta: string;
begin
  Separador('Demo 3 — Voice assistant: Audio → STT → LLM → TTS → Audio');

  WriteLn('  Phase 1 of 3: Transcribe input audio...');

  // ── Phase 1: STT ─────────────────────────────────────────────────────────
  Whisper := TAIWhisper.Create(nil);
  Stream  := TMemoryStream.Create;
  try
    Whisper.ApiKey   := '@OPENAI_API_KEY';
    Whisper.Languaje := 'es';

    Stream.LoadFromFile(AudioPath);
    Write('    Transcribing ', ExtractFileName(AudioPath), '... ');
    Pregunta := Whisper.Transcription(Stream, ExtractFileName(AudioPath), '');
    WriteLn('OK');
    WriteLn('    Text: ', Pregunta);
  finally
    Stream.Free;
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('  Phase 2 of 3: Send to LLM (gpt-4o-mini)...');

  // ── Phase 2: LLM ─────────────────────────────────────────────────────────
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := OPENAI_DRIVER;
    Conn.Model      := OPENAI_MODEL;
    Conn.Params.Values['ApiKey']       := '@OPENAI_API_KEY';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';
    Conn.SystemPrompt.Text :=
      'You are a friendly voice assistant. Always respond in English, ' +
      'concisely (maximum 3 sentences) and in a conversational tone. ' +
      'Your responses will be converted to voice, so avoid lists or formatting.';

    Conn.NewChat;
    Write('    Calling ', OPENAI_MODEL, '... ');
    Respuesta := Conn.AddMessageAndRun(Pregunta, 'user', []);
    WriteLn('OK');
    WriteLn('    Response: ', Respuesta);
  finally
    Conn.Free;
  end;

  WriteLn('');
  WriteLn('  Phase 3 of 3: Synthesize response to voice...');

  // ── Phase 3: TTS ─────────────────────────────────────────────────────────
  Audio := TAiOpenAiAudio.Create(nil);
  try
    Audio.ApiKey   := '@OPENAI_API_KEY';
    Audio.TTSModel := tts_1;
    Audio.TTSVoice := tvAlloy;

    Write('    Generating audio... ');
    Stream := Audio.Speech(Respuesta);
    try
      if Stream.Size > 0 then
      begin
        Stream.SaveToFile(OUTPUT_TTS_PIPELINE);
        WriteLn('OK');
        WriteLn('    Saved: ', OUTPUT_TTS_PIPELINE);
      end
      else
        WriteLn('ERROR — empty stream');
    finally
      Stream.Free;
    end;
  finally
    Audio.Free;
  end;

  WriteLn('');
  WriteLn('→ Complete pipeline in 3 independent phases.');
  WriteLn('  Each phase can be replaced: Gemini STT, Groq LLM, ElevenLabs TTS...');
  WriteLn('  Ch.12 shows the same flow with real-time microphone input.');
end;

// =============================================================================
//  Demo 4 — cmTranscription via TAiChatConnection
//
//  TAiChatConnection.ChatMode := cmTranscription delegates transcription
//  to the assigned SpeechTool, integrating STT into message history.
//
//  Advantage vs. Demo 1: the result stays in Messages — useful when you want
//  to chain transcription with a later chat turn.
//
//  Pattern:
//    Conn.SpeechTool  := Whisper;       // audio tool
//    Conn.ChatMode    := cmTranscription;
//    MF.LoadFromFile('audio.mp3');       // FileCategory → Tfc_Audio
//    R := Conn.AddMessageAndRun('', 'user', [MF]);   // R = transcribed text
// =============================================================================
procedure Demo4_cmTranscription(const AudioPath: string);
var
  Whisper: TAIWhisper;
  Conn   : TAiChatConnection;
  MF     : TAiMediaFile;
  Texto  : string;
begin
  Separador('Demo 4 — cmTranscription via TAiChatConnection');

  Whisper := TAIWhisper.Create(nil);
  Conn    := TAiChatConnection.Create(nil);
  MF      := TAiMediaFile.Create;
  try
    // Configure the SpeechTool
    Whisper.ApiKey   := '@OPENAI_API_KEY';
    Whisper.Languaje := 'es';

    // Configure the connection with forced transcription mode
    Conn.DriverName              := OPENAI_DRIVER;
    Conn.Model                   := OPENAI_MODEL;
    Conn.Params.Values['ApiKey'] := '@OPENAI_API_KEY';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.SpeechTool  := Whisper;          // ← assign STT tool
    Conn.ChatMode    := cmTranscription;  // ← force STT mode

    // Load the audio into a TAiMediaFile
    // LoadFromFile detects the extension → FileCategory = Tfc_Audio (ord=2)
    MF.LoadFromFile(AudioPath);
    WriteLn('  File    : ', ExtractFileName(AudioPath));
    WriteLn('  Category: Tfc_Audio (ord=', Ord(MF.FileCategory), ')');
    WriteLn('');

    Conn.NewChat;
    Write('  Transcribing via ChatMode... ');

    // The [MF] array carries the audio; the prompt text stays empty.
    // IMPORTANT: AddMessageAndRun transfers ownership of MF to the connection
    // (FMediaFiles is a TObjectList — frees MF in Conn.Free → NewChat).
    // Set MF := nil to avoid double-free in the finally block.
    Texto := Conn.AddMessageAndRun('', 'user', [MF]);
    MF := nil;   // ownership transferred — Conn.Free frees MF via NewChat
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Transcription:');
    WriteLn('  ', Texto);
    WriteLn('');
    WriteLn('  Historial de mensajes: ', Conn.Messages.Count,
            ' (user + assistant)');
  finally
    MF.Free;     // nil-safe: only frees if AddMessageAndRun did not run
    Conn.Free;   // → NewChat → frees messages (and MF if MF <> nil)
    Whisper.Free;
  end;

  WriteLn('');
  WriteLn('→ cmTranscription integrates STT into history (Conn.Messages).');
  WriteLn('  After transcription, you can change ChatMode to cmConversation');
  WriteLn('  and call AddMessageAndRun() — the LLM will see the transcribed text.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  AudioPath   : string;
  TieneApiKey : Boolean;
  TieneAudio  : Boolean;
begin
  WriteLn('=== MakerAI — Chapter 11: Voice (STT and TTS) ===');
  WriteLn('Requirement: OPENAI_API_KEY in environment variables.');
  WriteLn('STT demos: an MP3/WAV audio file at ', AUDIO_PATH);

  // Check availability
  TieneApiKey := OpenAiApiKeyDisponible;
  AudioPath   := EncontrarAudio;
  TieneAudio  := AudioPath <> '';

  WriteLn('');
  WriteLn('  Status:');
  if TieneApiKey then
    WriteLn('  [OK] OPENAI_API_KEY detected')
  else
    WriteLn('  [--] OPENAI_API_KEY not configured → all demos will be skipped');

  if TieneAudio then
    WriteLn('  [OK] Audio found: ', ExtractFileName(AudioPath))
  else
  begin
    WriteLn('  [--] Audio not found (', AUDIO_PATH, ')');
    WriteLn('       Demos 1, 3 and 4 will be skipped.');
    WriteLn('       Run Demo 2 first to generate an MP3,');
    WriteLn('       then copy it to the expected path.');
  end;

  if not TieneApiKey then
  begin
    WriteLn('');
    WriteLn('  Configure OPENAI_API_KEY and run again.');
    Exit;
  end;

  // ── STT demos (require audio file) ───────────────────────────────────────
  if TieneAudio then
    Demo1_STT_Whisper(AudioPath)
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 1 skipped (audio not found) ---');
  end;

  // ── TTS demo (always available if API key present) ───────────────────────
  Demo2_TTS_OpenAiAudio;

  // ── Complete pipeline (requires audio) ───────────────────────────────────
  if TieneAudio then
    Demo3_PipelineCompleto(AudioPath)
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 3 skipped (audio not found) ---');
    WriteLn('  Tip: use the MP3 generated by Demo 2 as STT input.');
  end;

  // ── cmTranscription (requires audio) ─────────────────────────────────────
  if TieneAudio then
    Demo4_cmTranscription(AudioPath)
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 4 skipped (audio not found) ---');
  end;

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demo completed.');
  WriteLn('  Generated audio files:');
  if TFile.Exists(OUTPUT_TTS_DEMO2)    then WriteLn('    ', OUTPUT_TTS_DEMO2);
  if TFile.Exists(OUTPUT_TTS_PIPELINE) then WriteLn('    ', OUTPUT_TTS_PIPELINE);
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
