program ChatModesDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 13: Chat Modes -- The Orchestrator in Detail
// =============================================================================
//
// Demonstrates the different TAiChatMode values of TAiChatConnection:
//
//   Demo 1 -- cmConversation  (default)    Text chat with OpenAI
//   Demo 2 -- cmWebSearch     (forced)    Web search with citations (OpenAI Search)
//   Demo 3 -- cmSpeechGeneration (forced) Text to speech (OpenAI TTS)
//   Demo 4 -- cmTranscription  (forced)   Audio transcription (Whisper)
//   Demo 5 -- Runtime mode change    One connection, three modes
//
// Required environment variables:
//   OPENAI_API_KEY   -- All demos
//   Demo 4:    requires an audio file at AUDIO_PATH.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Winapi.Windows,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.OpenAI.Audio,
  uMakerAi.OpenAI.WebSearch,
  uMakerAi.OpenAI.Audio.Tool,
  uMakerAi.Chat.Initializations;

const
  AUDIO_PATH = 'C:\Users\Public\Documents\sample.mp3';

// =============================================================================

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

function OutFile(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, AName);
end;

function EncontrarAudio: string;
var
  RutaLocal: string;
  Exts: array[0..4] of string;
  i: Integer;
  Archivos: TArray<string>;
begin
  if TFile.Exists(AUDIO_PATH) then
    Exit(AUDIO_PATH);

  Exts[0] := 'mp3'; Exts[1] := 'wav'; Exts[2] := 'm4a';
  Exts[3] := 'ogg'; Exts[4] := 'webm';
  for i := 0 to High(Exts) do
  begin
    RutaLocal := ExtractFilePath(ParamStr(0)) + 'sample.' + Exts[i];
    if TFile.Exists(RutaLocal) then
      Exit(RutaLocal);
  end;

  Archivos := TDirectory.GetFiles(
    ExtractFilePath(ParamStr(0)), '*.mp3', TSearchOption.soTopDirectoryOnly);
  if Length(Archivos) > 0 then Exit(Archivos[0]);

  Result := '';
end;

// =============================================================================
//  Demo 1 -- cmConversation (modo inteligente por defecto)
//
//  The default ChatMode. The framework applies gap analysis automatically
//  based on ModelCaps vs SessionCaps. With no special capabilities configured,
//  it uses InternalRunCompletions as output (normal text chat).
//
//  Key: AddMessageAndRun returns the text directly in synchronous mode.
// =============================================================================
procedure Demo1_Conversation;
var
  Conn: TAiChatConnection;
  Resp: string;
begin
  Separador('Demo 1 -- cmConversation (intelligent mode by default)');

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.Model                        := 'gpt-4.1-mini';
    Conn.Params.Values['Asynchronous']:= 'False';
    // ChatMode por defecto es cmConversation -- no es necesario especificarlo
    // Conn.ChatMode := cmConversation;

    Conn.SystemPrompt.Text :=
      'Eres un asistente tecnico especializado en Delphi. ' +
      'Responde de forma concisa, en una o dos frases.';

    WriteLn('  Prompt: What is the main advantage of Delphi over other IDEs?');
    WriteLn('');

    Write('  Waiting for response... ');
    Resp := Conn.AddMessageAndRun(
      'Cual es la principal ventaja de Delphi frente a otras IDEs?', 'user', []);
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Response:');
    WriteLn('  ', Resp);
  finally
    Conn.Free;
  end;

  WriteLn('');
  WriteLn('-> cmConversation applies gap analysis: ModelCaps vs SessionCaps.');
  WriteLn('   With no gaps configured, it always calls InternalRunCompletions.');
  WriteLn('   Add SessionCaps=[cap_GenImage] + ImageTool to enable images.');
end;

// =============================================================================
//  Demo 2 -- cmWebSearch (busqueda web forzada con citas)
//
//  Forced mode: direct InternalRunWebSearch, without gap analysis.
//  TAiOpenAiWebSearchTool uses gpt-4o-mini-search-preview, which has web search
//  built in. The result arrives in Resp and the citations in
//  Conn.Messages.Last.Citations.
//
//  Difference from cmConversation + cap_WebSearch:
//    cmWebSearch     -> raw tool result (without LLM synthesis)
//    cmConversation  -> LLM synthesizes the result before responding
// =============================================================================
procedure Demo2_WebSearch;
var
  Conn:      TAiChatConnection;
  SearchTool:TAiOpenAiWebSearchTool;
  Resp:      string;
  Msg:       TAiChatMessage;
  Cit:       TAiMsgCitation;
  Src:       TAiCitationSource;
  nCitas:    Integer;
begin
  Separador('Demo 2 -- cmWebSearch (direct search with citations)');

  SearchTool := TAiOpenAiWebSearchTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.ChatMode                     := cmWebSearch;
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.WebSearchTool                := SearchTool;

    SearchTool.ApiKey := '@OPENAI_API_KEY';

    WriteLn('  Query: "Delphi 13 Florence new features 2026"');
    WriteLn('  Search model: gpt-4o-mini-search-preview');
    WriteLn('');

    Write('  Searching... ');
    Resp := Conn.AddMessageAndRun('Delphi 13 Florence novedades 2026', 'user', []);
    WriteLn('OK');
    WriteLn('');

    if Resp = '' then
    begin
      WriteLn('  WARNING: the search returned an empty result.');
      WriteLn('  Possible causes:');
      WriteLn('    - OPENAI_API_KEY not configured or no access to search models.');
      WriteLn('    - API quota exhausted or network error.');
    end
    else
    begin
      WriteLn('  Result (first 300 chars):');
      WriteLn('  ', Copy(Resp, 1, 300));
    end;

    nCitas := 0;
    if Conn.Messages.Count > 0 then
    begin
      Msg := Conn.Messages.Last;
      if Msg.Citations.Count > 0 then
      begin
        WriteLn('');
        WriteLn('  Sources found:');
        for Cit in Msg.Citations do
          for Src in Cit.Sources do
          begin
            Inc(nCitas);
            if Src.DataSource.Title <> '' then
              WriteLn(Format('    [%d] %s', [nCitas, Src.DataSource.Title]));
            if Src.DataSource.Url <> '' then
              WriteLn(Format('        %s', [Copy(Src.DataSource.Url, 1, 80)]));
          end;
      end;
    end;
    if nCitas = 0 then
      WriteLn('  (no citations in the response)');
  finally
    Conn.Free;
    SearchTool.Free;
  end;

  WriteLn('');
  WriteLn('-> TAiOpenAiWebSearchTool uses gpt-4o-mini-search-preview.');
  WriteLn('   Citations are in Conn.Messages.Last.Citations.');
  WriteLn('   Only requires OPENAI_API_KEY with access to search models.');
end;

// =============================================================================
//  Demo 3 -- cmSpeechGeneration (texto a voz directo)
//
//  Forced mode: direct InternalRunSpeechGeneration, without completions.
//  The user text is converted to audio WITHOUT going through the LLM.
//  The audio remains in Conn.Messages.Last.MediaFiles[0].
// =============================================================================
procedure Demo3_SpeechGeneration;
var
  Conn:      TAiChatConnection;
  SpeechTool:TAiOpenAiSpeechTool;
  Resp:      string;
  Msg:       TAiChatMessage;
  MF:        TAiMediaFile;
  AudioPath: string;
  i:         Integer;
begin
  Separador('Demo 3 -- cmSpeechGeneration (text to speech)');

  SpeechTool := TAiOpenAiSpeechTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.ChatMode                     := cmSpeechGeneration;
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.SpeechTool                   := SpeechTool;

    SpeechTool.ApiKey   := '@OPENAI_API_KEY';
    SpeechTool.TTSVoice := tvAlloy;
    SpeechTool.TTSModel := tts_1;

    WriteLn('  Text: "Welcome to MakerAI, the AI platform for Delphi."');
    WriteLn('  Voice: Alloy | Model: TTS-1');
    WriteLn('');

    Write('  Generating audio... ');
    Resp := Conn.AddMessageAndRun(
      'Welcome to MakerAI, the artificial intelligence platform for Delphi.',
      'user', []);
    WriteLn('OK  [', Resp, ']');

    if Conn.Messages.Count > 0 then
    begin
      Msg := Conn.Messages.Last;
      for i := 0 to Msg.MediaFiles.Count - 1 do
      begin
        MF := Msg.MediaFiles[i];
        if MF.FileCategory = Tfc_Audio then
        begin
          AudioPath := OutFile('cap13_demo3_tts.mp3');
          MF.SaveToFile(AudioPath);
          WriteLn('  Audio saved: ', AudioPath,
                  ' (', MF.Bytes div 1024, ' KB)');
          Break;
        end;
      end;
      if Msg.MediaFiles.Count = 0 then
        WriteLn('  (no audio file in response)');
    end;
  finally
    Conn.Free;
    SpeechTool.Free;
  end;

  WriteLn('');
  WriteLn('-> cmSpeechGeneration: the user text is converted directly.');
  WriteLn('   No intermediate LLM. The audio remains in Conn.Messages.Last.MediaFiles.');
end;

// =============================================================================
//  Demo 4 -- cmTranscription (transcripcion de audio con Whisper)
//
//  Forced mode: InternalRunTranscription on the first audio file
//  among the attachments. The transcribed text arrives directly as the return value of
//  AddMessageAndRun (synchronous mode).
//
//  TAiOpenAiSpeechTool implements TTS and STT in a single component.
// =============================================================================
procedure Demo4_Transcription(const AudioPath: string);
var
  Conn:      TAiChatConnection;
  SpeechTool:TAiOpenAiSpeechTool;
  AudioMF:   TAiMediaFile;
  Resp:      string;
begin
  Separador('Demo 4 -- cmTranscription (audio transcription)');

  SpeechTool := TAiOpenAiSpeechTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.ChatMode                     := cmTranscription;
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.SpeechTool                   := SpeechTool;

    SpeechTool.ApiKey                := '@OPENAI_API_KEY';
    SpeechTool.TranscriptionModel    := tmWhisper1;
    SpeechTool.TranscriptionLanguage := 'es';

    // AudioMF is created without an explicit free: AddMessageAndRun adds it to
    // AskMsg.MediaFiles (TObjectList with OwnsObjects=True) and Conn.Free
    // frees that whole chain. Manual free here would cause a double-free.
    AudioMF := TAiMediaFile.Create;
    AudioMF.LoadFromFile(AudioPath);

    WriteLn('  File    : ', ExtractFileName(AudioPath));
    WriteLn('  Model   : whisper-1');
    WriteLn('');

    Write('  Transcribing... ');
    Resp := Conn.AddMessageAndRun('', 'user', [AudioMF]);
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Transcription:');
    WriteLn('  ', Resp);
  finally
    Conn.Free;
    // AudioMF NO se libera aqui: la conexion es la duena
    SpeechTool.Free;
  end;

  WriteLn('');
  WriteLn('-> cmTranscription processes the FIRST audio file among attachments.');
  WriteLn('   The transcribed text is returned by AddMessageAndRun (sync mode).');
  WriteLn('   TAiOpenAiSpeechTool implements TTS + STT in a single component.');
end;

// =============================================================================
//  Demo 5 -- Cambio de modo en tiempo de ejecucion
//
//  Demonstrates that ChatMode is just a property: changing it between calls
//  changes the behavior without recreating the connection.
//
//    Round 1 -- cmConversation  -> LLM text (OpenAI)
//    Round 2 -- cmWebSearch     -> search result (OpenAI search tool)
//    Round 3 -- cmConversation  -> back to text (OpenAI)
// =============================================================================
procedure Demo5_CambioModo;
var
  Conn:      TAiChatConnection;
  SearchTool:TAiOpenAiWebSearchTool;
  Resp:      string;
  nCitas:    Integer;
  Msg:       TAiChatMessage;
  Cit:       TAiMsgCitation;
  Src:       TAiCitationSource;
begin
  Separador('Demo 5 -- ChatMode change at runtime');

  SearchTool := TAiOpenAiWebSearchTool.Create(nil);
  SearchTool.ApiKey := '@OPENAI_API_KEY';
  Conn       := TAiChatConnection.Create(nil);
  try
    // --- Ronda 1: modo conversacion (texto OpenAI) ---
    // WebSearchTool NO asignado: cmConversation no lo usa;
    // asignarlo antes del cambio de driver contamina el driver OpenAI.
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.Model                        := 'gpt-4.1-mini';
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.ChatMode                     := cmConversation;

    WriteLn('  [1] ChatMode = cmConversation  (OpenAI)');
    Write('      Question: "Explain in one sentence what TAiChatMode is." ... ');
    Resp := Conn.AddMessageAndRun(
      'Explain in one sentence what TAiChatMode is in MakerAI for Delphi.',
      'user', []);
    WriteLn('OK');
    WriteLn('      Response: ', Copy(Resp, 1, 120));
    WriteLn('');

    // --- Ronda 2: cambio a busqueda web (OpenAI search tool) ---
    Conn.Messages.Clear;
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.WebSearchTool                := SearchTool;  // asignar AQUI, solo para esta ronda
    Conn.ChatMode                     := cmWebSearch;

    WriteLn('  [2] ChatMode = cmWebSearch  (same Conn object, different mode)');
    Write('      Query: "RAD Studio Delphi new features 2026" ... ');
    Resp := Conn.AddMessageAndRun('RAD Studio Delphi new features 2026', 'user', []);
    WriteLn('OK');
    WriteLn('      Response: ', Copy(Resp, 1, 120));

    nCitas := 0;
    if Conn.Messages.Count > 0 then
    begin
      Msg := Conn.Messages.Last;
      for Cit in Msg.Citations do
        for Src in Cit.Sources do
          Inc(nCitas);
    end;
    WriteLn(Format('      Citations: %d', [nCitas]));
    WriteLn('');

    // --- Ronda 3: de vuelta a conversacion (OpenAI) ---
    Conn.Messages.Clear;
    Conn.WebSearchTool                := nil;  // limpiar ANTES del cambio de driver
    Conn.DriverName                   := 'OpenAI';
    Conn.Params.Values['ApiKey']      := '@OPENAI_API_KEY';
    Conn.Params.Values['Asynchronous']:= 'False';
    Conn.ChatMode                     := cmConversation;

    WriteLn('  [3] ChatMode = cmConversation  (back to initial mode)');
    Write('      Question: "What is the difference between OOP and procedural?" ... ');
    Resp := Conn.AddMessageAndRun(
      'In one sentence, what is the main difference between object-oriented programming and procedural programming?',
      'user', []);
    WriteLn('OK');
    WriteLn('      Response: ', Copy(Resp, 1, 120));
  finally
    Conn.Free;
    SearchTool.Free;
  end;

  WriteLn('');
  WriteLn('-> ChatMode is just a property: changing it between calls changes');
  WriteLn('   the behavior without recreating the connection.');
  WriteLn('   Rule: assign/clear ChatTools per round according to the mode.');
  WriteLn('   WebSearchTool should only be assigned in the cmWebSearch round.');
  WriteLn('   Messages.Clear prevents context from different modes from mixing.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  TieneOpenAI: Boolean;
  AudioPath:   string;
begin
  SetConsoleOutputCP(65001);
  WriteLn('=== MakerAI -- Chapter 13: Chat Modes ===');
  WriteLn('Demos: 5 modes of TAiChatConnection.ChatMode');
  WriteLn('');

  TieneOpenAI := GetEnvironmentVariable('OPENAI_API_KEY') <> '';
  AudioPath   := EncontrarAudio;

  WriteLn('  Environment status:');
  if TieneOpenAI then WriteLn('  [OK] OPENAI_API_KEY detectado')
  else            WriteLn('  [--] OPENAI_API_KEY no configurado -- todos los demos omitidos');
  if AudioPath <> '' then
    WriteLn('  [OK] Audio: ', ExtractFileName(AudioPath))
  else
    WriteLn('  [--] Audio no encontrado en ', AUDIO_PATH, ' -- demo 4 omitido');

  if TieneOpenAI then
  begin
    try Demo1_Conversation;
    except on E: Exception do WriteLn('  [Demo 1 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 1 skipped (OPENAI_API_KEY not configured) ---');

  if TieneOpenAI then
  begin
    try Demo2_WebSearch;
    except on E: Exception do WriteLn('  [Demo 2 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 2 skipped (OPENAI_API_KEY not configured) ---');

  if TieneOpenAI then
  begin
    try Demo3_SpeechGeneration;
    except on E: Exception do WriteLn('  [Demo 3 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 3 skipped (OPENAI_API_KEY not configured) ---');

  if TieneOpenAI and (AudioPath <> '') then
  begin
    try Demo4_Transcription(AudioPath);
    except on E: Exception do WriteLn('  [Demo 4 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 4 skipped ---');
    if not TieneOpenAI then WriteLn('    OPENAI_API_KEY not configured');
    if AudioPath = '' then
    begin
      WriteLn('    Audio not found. Copy an MP3/WAV to: ', AUDIO_PATH);
      WriteLn('    Or run Demo 3 (generates an MP3) and copy it to that path.');
    end;
  end;

  if TieneOpenAI then
  begin
    try Demo5_CambioModo;
    except on E: Exception do WriteLn('  [Demo 5 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 5 skipped (OPENAI_API_KEY not configured) ---');

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demos completed.');
  WriteLn('  See cap13-chatmodes.md for the complete documentation.');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('FATAL ERROR: ', E.ClassName, ' -- ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
