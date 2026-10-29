// BIDIRECTIONAL VOICE BRIDGE in real time (console)
// =====================================================
//
// Scenario: you are in a meeting (Zoom/Meet/Teams) with an English speaker.
//
//   [THEM] The meeting audio (loopback) is transcribed (EN), translated
//           to Spanish and PLAYED with TTS in your headphones.
//   [ME]    You speak Spanish into the microphone; it is transcribed, translated to
//           English and the TTS is PLAYED on the virtual cable the meeting
//           uses as a microphone -> the other side hears you in English.
//
//   loopback --> STT(en) --> translate(es) --> TTS --> headphones (I listen)
//   microphone -> STT(es) --> translate(en) --> TTS --> CABLE Input (meeting listens)
//
// Required setup:
//   1. OPENAI_API_KEY in the environment (STT + translation + TTS).
//   2. VB-CABLE installed (https://vb-audio.com/Cable/) or any virtual cable
//      virtual. In the meeting select "CABLE Output" as MICROPHONE.
//      If there is no cable, the demo warns and plays everything on the default
//      device (test mode).
//   3. HEADPHONES: meeting audio and Spanish TTS must come out through
//      headphones so the microphone does not capture them.
//
// Anti-feedback: while our own TTS plays on the device
// captured by loopback, capture is muted (TAiAudioCapture.Muted)
// to avoid re-translating our own synthetic voice.

program VoiceBridgeDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading,
  Winapi.Windows,
  uMakerAi.Utils.AudioCapture,
  uMakerAi.Utils.AudioPlayback,
  uMakerAi.Realtime,
  uMakerAi.Realtime.OpenAI,
  uMakerAi.OpenAI.Audio,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi; // imports and auto-registers the 'OpenAi' driver (v3.4)

const
  // ==========================================================================
  // CONFIGURACION
  // ==========================================================================
  TARGET_LANG_REMOTE = 'Spanish'; // what the other side says -> Spanish (for me)
  TARGET_LANG_LOCAL = 'English'; // what I say -> English (for the meeting)

  STT_LANG_REMOTE = 'en'; // expected language of the other side ('' = auto-detect)
  STT_LANG_LOCAL = 'es'; // language I speak

  TRANSLATOR_DRIVER = 'OpenAi';
  TRANSLATOR_MODEL = 'gpt-4o-mini';
  TRANSLATOR_URL = '';
  TRANSLATOR_APIKEY = '@OPENAI_API_KEY';

  STT_APIKEY = '@OPENAI_API_KEY';
  STT_MODEL = 'gpt-realtime-2.1';

  // OpenAI TTS with trfPcm format returns PCM16 at 24 kHz mono
  TTS_PCM_RATE = 24000;

  // Substring to locate the virtual cable among the output
  // devices. In the meeting the "CABLE Output" end is selected as mic.
  MEETING_DEVICE_HINT = 'CABLE Input';

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
  // One "side" of the bridge: capture + STT + translation + TTS + playback
  TBridgeSide = class
  private
    FTag: string;
    FTargetLang: string;
    FClosing: Boolean;
    FCapture: TAiAudioCapture;
    FSTT: TAiOpenAiRealtimeSTT;
    FChat: TAiChatConnection;
    FTTS: TAiOpenAiAudio;
    FPlayer: TAiAudioPlayer;
    FMuteCapture: TAiAudioCapture; // capture to mute while MY TTS plays
    FChatLock: TCriticalSection;
    procedure SttSessionReady(Sender: TObject);
    procedure SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
    procedure SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
    procedure TranslateAndSpeak(const aText: string);
  public
    constructor Create(aSource: TAiAudioSource; const aTag, aTargetLang, aSttLanguage: string;
      aVoice: TAiTTSVoice; const aPlayerDeviceId: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Capture: TAiAudioCapture read FCapture;
    // Capture that must be muted while this side plays its TTS
    // (typically loopback, if TTS plays through a captured device).
    property MuteCapture: TAiAudioCapture read FMuteCapture write FMuteCapture;
  end;

constructor TBridgeSide.Create(aSource: TAiAudioSource; const aTag, aTargetLang, aSttLanguage: string;
  aVoice: TAiTTSVoice; const aPlayerDeviceId: string);
begin
  inherited Create;
  FTag := aTag;
  FTargetLang := aTargetLang;
  FClosing := False;
  FChatLock := TCriticalSection.Create;

  // --- Translator ---
  FChat := TAiChatConnection.Create(nil);
  FChat.DriverName := TRANSLATOR_DRIVER;
  FChat.Model := TRANSLATOR_MODEL;
  FChat.Params.Values['Asynchronous'] := 'False';
  if TRANSLATOR_APIKEY <> '' then
    FChat.Params.Values['ApiKey'] := TRANSLATOR_APIKEY;
  if TRANSLATOR_URL <> '' then
    FChat.Params.Values['Url'] := TRANSLATOR_URL;

  // --- TTS ---
  FTTS := TAiOpenAiAudio.Create(nil);
  FTTS.ApiKey := '@OPENAI_API_KEY';
  FTTS.TTSModel := TAiTTSModel.gpt_4o_mini_tts;
  FTTS.TTSVoice := aVoice;
  FTTS.TTSResponseFormat := TAiTTSResponseFormat.trfPcm; // PCM16 24 kHz mono
  FTTS.TTSSpeed := 1.0;

  // --- Player (selectable device) ---
  FPlayer := TAiAudioPlayer.Create(nil);
  FPlayer.DeviceId := aPlayerDeviceId;
  FPlayer.OnError := PlayerError;
  FPlayer.OnStateChange := PlayerStateChange;

  // --- Real-time STT ---
  FSTT := TAiOpenAiRealtimeSTT.Create(nil);
  FSTT.ApiKey := STT_APIKEY;
  FSTT.Model := STT_MODEL;
  // gpt-live-transcribe (Aug 2026): better WER with meeting noise and accents
  FSTT.TranscriptionModel := otmGptLiveTranscribe;
  FSTT.TranscriptionPrompt := 'Reunion de trabajo traducida en tiempo real';
  FSTT.Language := aSttLanguage; // el driver lo envia como languages[]
  FSTT.OnSessionReady := SttSessionReady;
  FSTT.OnTranscriptCompleted := SttTranscriptCompleted;
  FSTT.OnError := SttError;

  // --- Capture ---
  FCapture := TAiAudioCapture.Create(nil);
  FCapture.Source := aSource;
  FCapture.OutputSampleRate := 16000;
  FCapture.OutputChannels := 1;
  FCapture.RealtimeSTT := FSTT;
  FCapture.OnError := CaptureError;
end;

destructor TBridgeSide.Destroy;
begin
  Stop;
  FChatLock.Enter;
  try
    FClosing := True;
  finally
    FChatLock.Leave;
  end;
  FCapture.Free;
  FSTT.Free;
  FPlayer.Free;
  FTTS.Free;
  FChat.Free;
  FChatLock.Free;
  inherited;
end;

procedure TBridgeSide.Start;
begin
  FPlayer.Active := True;
  FSTT.Connect;
  FCapture.Active := True;
end;

procedure TBridgeSide.Stop;
begin
  FClosing := True;
  if Assigned(FCapture) then
    FCapture.Active := False;
  if Assigned(FSTT) and FSTT.IsConnected then
    FSTT.Disconnect;
  if Assigned(FPlayer) then
    FPlayer.Active := False;
end;

procedure TBridgeSide.SttSessionReady(Sender: TObject);
begin
  SafeWriteLn(FTag + ' STT connected and ready.');
end;

procedure TBridgeSide.SttError(Sender: TObject; const ErrorMsg, ErrorCode: string);
begin
  SafeWriteLn(Format('%s ERROR STT [%s]: %s', [FTag, ErrorCode, ErrorMsg]));
end;

procedure TBridgeSide.CaptureError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR capture: ' + ErrorMessage);
end;

procedure TBridgeSide.PlayerError(Sender: TObject; const ErrorMessage: string);
begin
  SafeWriteLn(FTag + ' ERROR playback: ' + ErrorMessage);
end;

procedure TBridgeSide.PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
begin
  // When our TTS finishes playing, reactivate the muted capture
  if (not aIsPlaying) and Assigned(FMuteCapture) then
    FMuteCapture.Muted := False;
end;

procedure TBridgeSide.SttTranscriptCompleted(Sender: TObject; const Transcript: string; const ItemId: string);
var
  Text: string;
begin
  Text := Trim(Transcript);
  if Text = '' then
    Exit;
  SafeWriteLn(Format('%s %s', [FTag, Text]));
  TranslateAndSpeak(Text);
end;

procedure TBridgeSide.TranslateAndSpeak(const aText: string);
begin
  TTask.Run(
    procedure
    var
      Prompt, Res: string;
      PcmStream: TMemoryStream;
      Pcm: TBytes;
    begin
      try
        // --- 1) Translate ---
        FChatLock.Enter;
        try
          if FClosing then
            Exit;
          FChat.NewChat; // each sentence is independent
          Prompt := Format('Translate to %s the following text. Reply ONLY with the translation, ' +
            'without comments or quotes:'#10'%s', [FTargetLang, aText]);
          Res := FChat.AddMessageAndRun(Prompt, 'user', []);
        finally
          FChatLock.Leave;
        end;
        Res := Trim(Res);
        if Res = '' then
          Exit;
        SafeWriteLn(Format('%s    -> %s', [FTag, Res]));

        // --- 2) TTS ---
        PcmStream := FTTS.Speech(Res); // PCM16 24 kHz mono (trfPcm)
        try
          if (PcmStream = nil) or (PcmStream.Size = 0) then
            Exit;
          SetLength(Pcm, PcmStream.Size);
          PcmStream.Position := 0;
          PcmStream.ReadBuffer(Pcm[0], PcmStream.Size);
        finally
          PcmStream.Free;
        end;

        // --- 3) Play (muting the capture that would hear us) ---
        if FClosing then
          Exit;
        if Assigned(FMuteCapture) then
          FMuteCapture.Muted := True; // se reactiva en PlayerStateChange
        FPlayer.PlayPCM16(Pcm, TTS_PCM_RATE, 1);
      except
        on E: Exception do
          SafeWriteLn(Format('%s ERROR translating/TTS: %s', [FTag, E.Message]));
      end;
    end);
end;

// ============================================================================

function FindMeetingDevice(out aDeviceId, aDeviceName: string): Boolean;
var
  D: TAiAudioDeviceInfo;
begin
  Result := False;
  aDeviceId := '';
  aDeviceName := '';
  for D in TAiAudioPlayer.GetPlaybackDevices do
    if Pos(LowerCase(MEETING_DEVICE_HINT), LowerCase(D.DeviceName)) > 0 then
    begin
      aDeviceId := D.EndpointId;
      aDeviceName := D.DeviceName;
      Exit(True);
    end;
end;

var
  Remote, Local: TBridgeSide;
  StopRequested: Boolean;
  MeetingDeviceId, MeetingDeviceName: string;
  HasCable: Boolean;
  D: TAiAudioDeviceInfo;

begin
  SetConsoleOutputCP(CP_UTF8); // tildes y caracteres especiales en consola
  StopRequested := False;
  GConsoleLock := TCriticalSection.Create;
  try
    try
      WriteLn('=== Bidirectional voice bridge in real time (MakerAI) ===');
      WriteLn;

      if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
      begin
        WriteLn('ERROR: the environment variable OPENAI_API_KEY is not defined.');
        Exit;
      end;

      WriteLn('Output devices:');
      for D in TAiAudioPlayer.GetPlaybackDevices do
        if D.IsDefault then
          WriteLn('  * ' + D.DeviceName + '  (default)')
        else
          WriteLn('  - ' + D.DeviceName);
      WriteLn;

      HasCable := FindMeetingDevice(MeetingDeviceId, MeetingDeviceName);
      if HasCable then
      begin
        WriteLn('Virtual cable found: ' + MeetingDeviceName);
        WriteLn('  -> In the meeting select "CABLE Output" as MICROPHONE.');

        // KNOWN TRAP: the VB-CABLE installer may leave "CABLE Input"
        // as the DEFAULT output device in Windows. In that case all
        // system audio (meeting + local TTS) goes to the cable and the user
        // hears nothing (see Docs/Version 3/uMakerAi-AudioBridge.md, section 4.2).
        for D in TAiAudioPlayer.GetPlaybackDevices do
          if D.IsDefault and SameText(D.EndpointId, MeetingDeviceId) then
          begin
            WriteLn;
            WriteLn('*** WARNING: "CABLE Input" is the DEFAULT output device. ***');
            WriteLn('*** This way you will hear NEITHER the meeting NOR the translation.    ***');
            WriteLn('*** Go to Settings > System > Sound and set your HEADPHONES            ***');
            WriteLn('*** as the default output before continuing.                           ***');
            Break;
          end;
      end
      else
      begin
        WriteLn('WARNING: "' + MEETING_DEVICE_HINT + '" was not found (VB-CABLE not installed?).');
        WriteLn('  TEST MODE: English TTS will play through the default device');
        WriteLn('  and will NOT reach the meeting. Install VB-CABLE for the full flow.');
        MeetingDeviceId := '';
      end;
      WriteLn;

      // [THEM]: loopback -> es; their TTS plays in MY headphones (default),
      // which is the same device captured by loopback -> it must be muted
      // while it plays (anti-feedback).
      Remote := TBridgeSide.Create(asLoopback, '[THEM]', TARGET_LANG_REMOTE, STT_LANG_REMOTE,
        TAiTTSVoice.tvNova, '');
      Remote.MuteCapture := Remote.Capture;

      // [ME]: microphone -> en; their TTS goes to the virtual cable (the meeting hears it).
      Local := TBridgeSide.Create(asMicrophone, '[ME]   ', TARGET_LANG_LOCAL, STT_LANG_LOCAL,
        TAiTTSVoice.tvOnyx, MeetingDeviceId);
      if not HasCable then
        Local.MuteCapture := Remote.Capture; // in test mode it will also play through the default device

      try
        Remote.Start;
        Local.Start;

        WriteLn('Bridge active... press ENTER to finish.');
        WriteLn;

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
        CheckSynchronize(200);
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
