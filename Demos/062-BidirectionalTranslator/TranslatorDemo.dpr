// Demo of a BIDIRECTIONAL real-time TRANSLATOR (console)
// =========================================================
//
// Captures simultaneously:
//   [THEM] the audio the system PLAYS (WASAPI loopback) -> what is said
//           by the other side of the video call (Zoom, Meet, Teams, YouTube...)
//   [ME]    the microphone (WASAPI) -> what you say
//
// Each stream is sent to an OpenAI Realtime STT (VAD on the server) and each
// completed transcription is translated with TAiChatConnection.
//
//   loopback --> TAiAudioCapture --> TAiOpenAiRealtimeSTT --+
//                                                           +--> TAiChatConnection --> console
//   microphone -> TAiAudioCapture --> TAiOpenAiRealtimeSTT --+
//
// Requirements:
//   - OPENAI_API_KEY environment variable (for STT and, by default, translation).
//   - HEADPHONES recommended: with speakers the microphone also captures
//     remote audio and transcriptions are duplicated (acoustic echo).
//
// The translator is interchangeable: change TRANSLATOR_DRIVER / TRANSLATOR_MODEL /
// TRANSLATOR_URL to use Ollama or another provider (e.g. a local server).

program TranslatorDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading,
  Winapi.Windows,
  uMakerAi.Utils.AudioCapture,
  uMakerAi.Realtime,
  uMakerAi.Realtime.OpenAI,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi; // imports and auto-registers the 'OpenAi' driver (v3.4)

const
  // ==========================================================================
  // CONFIGURATION
  // ==========================================================================

  // Target language for each side
  TARGET_LANG_REMOTE = 'Spanish'; // what the other side says -> Spanish
  TARGET_LANG_LOCAL = 'English'; // what I say -> English

  // Language hint for STT (ISO-639-1: 'en', 'es'... empty = auto-detect)
  STT_LANG_REMOTE = '';
  STT_LANG_LOCAL = '';

  // Translation provider (any registered MakerAI driver).
  // For local Ollama: DRIVER='Ollama', MODEL='gpt-oss:20b', URL='http://192.168.3.121:11434/'
  TRANSLATOR_DRIVER = 'OpenAi';
  TRANSLATOR_MODEL = 'gpt-4o-mini';
  TRANSLATOR_URL = ''; // empty = default URL of the driver
  TRANSLATOR_APIKEY = '@OPENAI_API_KEY';

  STT_APIKEY = '@OPENAI_API_KEY';
  // Realtime session model (matches the driver default;
  // kept explicit so the demo does not change if the default changes).
  STT_MODEL = 'gpt-realtime-2.1';

var
  GConsoleLock: TCriticalSection;

procedure SafeWriteLn(const aText: string);
begin
  GConsoleLock.Enter;
  try
    WriteLn(aText);
  finally
    GConsoleLock.Leave;
  end;
end;

type
  // One "side" of the translator: capture + STT + translation
  TTranslatorSide = class
  private
    FTag: string; // '[ELLOS]' / '[YO]'
    FTargetLang: string;
    FClosing: Boolean;
    FCapture: TAiAudioCapture;
    FSTT: TAiOpenAiRealtimeSTT;
    FChat: TAiChatConnection;
    FChatLock: TCriticalSection;
    procedure SttSessionReady(Sender: TObject);
    procedure SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
    procedure SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure Translate(const aText: string);
  public
    constructor Create(aSource: TAiAudioSource; const aTag, aTargetLang, aSttLanguage: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
  end;

constructor TTranslatorSide.Create(aSource: TAiAudioSource; const aTag, aTargetLang, aSttLanguage: string);
begin
  inherited Create;
  FTag := aTag;
  FTargetLang := aTargetLang;
  FClosing := False;
  FChatLock := TCriticalSection.Create;

  // --- Translator (one chat per side, so calls do not cross) ---
  FChat := TAiChatConnection.Create(nil);
  FChat.DriverName := TRANSLATOR_DRIVER;
  FChat.Model := TRANSLATOR_MODEL;
  FChat.Params.Values['Asynchronous'] := 'False';
  if TRANSLATOR_APIKEY <> '' then
    FChat.Params.Values['ApiKey'] := TRANSLATOR_APIKEY;
  if TRANSLATOR_URL <> '' then
    FChat.Params.Values['Url'] := TRANSLATOR_URL;

  // --- Real-time STT (server VAD decides start/end of utterance) ---
  FSTT := TAiOpenAiRealtimeSTT.Create(nil);
  FSTT.ApiKey := STT_APIKEY;
  FSTT.Model := STT_MODEL;
  // gpt-live-transcribe (Aug 2026): better WER with background noise, accents and
  // terminology; accepts domain context (prompt + expected languages)
  FSTT.TranscriptionModel := otmGptLiveTranscribe;
  FSTT.TranscriptionPrompt := 'Work call translated in real time';
  FSTT.Language := aSttLanguage;
  if aSttLanguage = '' then
  begin
    // Guided auto-detection: the two languages the call may contain
    FSTT.Languages.Add('en');
    FSTT.Languages.Add('es');
  end;
  FSTT.OnSessionReady := SttSessionReady;
  FSTT.OnTranscriptCompleted := SttTranscriptCompleted;
  FSTT.OnError := SttError;

  // --- Audio capture (loopback or microphone) ---
  FCapture := TAiAudioCapture.Create(nil);
  FCapture.Source := aSource;
  FCapture.OutputSampleRate := 16000;
  FCapture.OutputChannels := 1;
  FCapture.RealtimeSTT := FSTT; // each PCM16 chunk is forwarded to the STT
  FCapture.OnError := CaptureError;
end;

destructor TTranslatorSide.Destroy;
begin
  Stop;
  // Wait until no translation task is using FChat
  FChatLock.Enter;
  try
    FClosing := True;
  finally
    FChatLock.Leave;
  end;
  FCapture.Free;
  FSTT.Free;
  FChat.Free;
  FChatLock.Free;
  inherited;
end;

procedure TTranslatorSide.Start;
begin
  FSTT.Connect; // asynchronous: when connected, chunks start flowing
  FCapture.Active := True;
end;

procedure TTranslatorSide.Stop;
begin
  FClosing := True;
  if Assigned(FCapture) then
    FCapture.Active := False;
  if Assigned(FSTT) and FSTT.IsConnected then
    FSTT.Disconnect;
end;

procedure TTranslatorSide.SttSessionReady(Sender: TObject);
begin
  SafeWriteLn(FTag + ' STT connected and ready.');
end;

procedure TTranslatorSide.SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
begin
  SafeWriteLn(Format('%s ERROR STT [%s]: %s', [FTag, ErrorCode, ErrorMsg]));
end;

procedure TTranslatorSide.CaptureError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR capture: ' + ErrorMessage);
end;

procedure TTranslatorSide.SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
var
  Text: string;
begin
  Text := Trim(Transcript);
  if Text = '' then
    Exit;
  SafeWriteLn(Format('%s %s', [FTag, Text]));
  Translate(Text);
end;

procedure TTranslatorSide.Translate(const aText: string);
begin
  // Translate in a task so the console event loop is not blocked
  TTask.Run(
    procedure
    var
      Prompt, Res: string;
    begin
      try
        FChatLock.Enter;
        try
          if FClosing then
            Exit;
          FChat.NewChat; // stateless translation: each utterance is independent
          Prompt := Format('Translate to %s the following text. Reply ONLY with the translation, ' +
            'without comments or quotes:'#10'%s', [FTargetLang, aText]);
          Res := FChat.AddMessageAndRun(Prompt, 'user', []);
        finally
          FChatLock.Leave;
        end;
        SafeWriteLn(Format('%s    -> %s', [FTag, Trim(Res)]));
      except
        on E: Exception do
          SafeWriteLn(Format('%s ERROR translating: %s', [FTag, E.Message]));
      end;
    end);
end;

// ============================================================================

var
  Remote, Local: TTranslatorSide;
  StopRequested: Boolean;

begin
  SetConsoleOutputCP(CP_UTF8); // tildes y caracteres especiales en consola
  StopRequested := False;
  GConsoleLock := TCriticalSection.Create;
  try
    try
      WriteLn('=== Bidirectional real-time translator (MakerAI) ===');
      WriteLn;
      WriteLn('  [THEM] system audio (loopback)  -> ' + TARGET_LANG_REMOTE);
      WriteLn('  [ME]    microphone                     -> ' + TARGET_LANG_LOCAL);
      WriteLn;
      WriteLn('  HEADPHONES recommended (prevents the microphone from capturing');
      WriteLn('  remote audio and duplicating transcriptions).');
      WriteLn;

      if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
      begin
        WriteLn('ERROR: the OPENAI_API_KEY environment variable is not defined.');
        WriteLn('Define it and run again.');
        Exit;
      end;

      Remote := TTranslatorSide.Create(asLoopback, '[THEM]', TARGET_LANG_REMOTE, STT_LANG_REMOTE);
      Local := TTranslatorSide.Create(asMicrophone, '[ME]   ', TARGET_LANG_LOCAL, STT_LANG_LOCAL);
      try
        Remote.Start;
        Local.Start;

        WriteLn('Translating... press ENTER to finish.');
        WriteLn;

        // ReadLn in a task; the main thread processes TThread.Queue events
        TTask.Run(
          procedure
          begin
            ReadLn;
            StopRequested := True;
          end);

        while not StopRequested do
          CheckSynchronize(50);

        WriteLn('Stopping...');
        Remote.Stop;
        Local.Stop;
        CheckSynchronize(200); // drain pending events
      finally
        Remote.Free;
        Local.Free;
      end;
    except
      on E: Exception do
        WriteLn(E.ClassName, ': ', E.Message);
    end;
  finally
    GConsoleLock.Free;
  end;

end.
