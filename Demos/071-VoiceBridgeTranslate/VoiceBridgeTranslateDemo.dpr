// BIDIRECTIONAL VOICE BRIDGE with gpt-realtime-translate (console)
// ================================================================
//
// REFACTOR of demo 063: the STT -> LLM(translate) -> TTS pipeline of each
// direction is replaced by a SINGLE voice translation WebSocket
// (TAiOpenAiRealtimeTranslate). The server receives continuous audio and
// returns directly the translated text AND the translated TTS audio:
//
//   063 (3 hops):  loopback -> STT -> chat translates -> TTS -> speaker
//   071 (1 hop):   loopback -> gpt-realtime-translate -> speaker
//
// Advantages: lower latency (translated audio arrives streaming while
// the phrase advances), less code, a single failure point per direction.
// Difference: the server chooses the TTS voice (no configurable voice).
//
//   [THEM] The meeting audio (loopback) is translated to Spanish and plays
//           in your headphones (text + voice).
//   [ME]    You speak Spanish into the microphone; the English translation plays
//           in the virtual cable the meeting uses as a microphone.
//
// Required configuration (same as 063):
//   1. OPENAI_API_KEY in the environment.
//   2. VB-CABLE installed; in the meeting select "CABLE Output" as mic.
//      Without cable: test mode through the default device.
//   3. HEADPHONES so the microphone does not capture the meeting.
//
// Anti-feedback: while translated audio plays on the device
// captured by loopback, capture is muted (TAiAudioCapture.Muted).

program VoiceBridgeTranslateDemo;

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
  uMakerAi.Realtime.OpenAI;

const
  // ==========================================================================
  // CONFIGURATION
  // ==========================================================================
  TARGET_LANG_REMOTE = 'es'; // what the other side says -> Spanish (for me)
  TARGET_LANG_LOCAL  = 'en'; // what I say -> English (for the meeting)

  TRANSLATE_APIKEY = '@OPENAI_API_KEY';

  // Translated audio from gpt-realtime-translate is PCM16 24 kHz mono
  TR_PCM_RATE = 24000;

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
  // A "side" of the bridge: capture -> streaming translation -> playback
  TBridgeSide = class
  private
    FTag: string;
    FClosing: Boolean;
    FCapture: TAiAudioCapture;
    FTr: TAiOpenAiRealtimeTranslate;
    FPlayer: TAiAudioPlayer;
    FMuteCapture: TAiAudioCapture; // capture to mute while MY audio plays
    FSrcText: string;              // current line in source language
    FDstText: string;              // current line of translation
    procedure TrSessionReady(Sender: TObject);
    procedure TrSourceDelta(Sender: TObject; const Delta: string);
    procedure TrTranslatedDelta(Sender: TObject; const Delta: string);
    procedure TrAudioChunk(Sender: TObject; const AData: TBytes);
    procedure TrError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure CaptureError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerError(Sender: TObject; const ErrorMessage: string);
    procedure PlayerStateChange(Sender: TObject; aIsPlaying: Boolean);
    procedure FlushIfSentence(var aLine: string; const aPrefix: string);
  public
    constructor Create(aSource: TAiAudioSource;
      const aTag, aTargetLang, aPlayerDeviceId: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Capture: TAiAudioCapture read FCapture;
    property MuteCapture: TAiAudioCapture read FMuteCapture write FMuteCapture;
  end;

constructor TBridgeSide.Create(aSource: TAiAudioSource;
  const aTag, aTargetLang, aPlayerDeviceId: string);
begin
  inherited Create;
  FTag := aTag;
  FClosing := False;

  // --- Streaming voice translation (1 socket per direction) ---
  FTr := TAiOpenAiRealtimeTranslate.Create(nil);
  FTr.ApiKey := TRANSLATE_APIKEY;
  FTr.TargetLanguage := aTargetLang;
  FTr.SourceTranscription := True; // also show what was heard
  FTr.InputSampleRate := 16000;    // capture delivers 16 kHz; driver resamples
  FTr.OnSessionReady := TrSessionReady;
  FTr.OnTranscriptDelta := TrSourceDelta;
  FTr.OnAssistantTextDelta := TrTranslatedDelta;
  FTr.OnAudioChunk := TrAudioChunk;
  FTr.OnError := TrError;

  // --- Player (selectable device) ---
  FPlayer := TAiAudioPlayer.Create(nil);
  FPlayer.DeviceId := aPlayerDeviceId;
  FPlayer.OnError := PlayerError;
  FPlayer.OnStateChange := PlayerStateChange;

  // --- Capture ---
  FCapture := TAiAudioCapture.Create(nil);
  FCapture.Source := aSource;
  FCapture.OutputSampleRate := 16000;
  FCapture.OutputChannels := 1;
  FCapture.RealtimeSTT := FTr; // each PCM16 chunk is forwarded to the translator
  FCapture.OnError := CaptureError;
end;

destructor TBridgeSide.Destroy;
begin
  Stop;
  FCapture.Free;
  FTr.Free;
  FPlayer.Free;
  inherited;
end;

procedure TBridgeSide.Start;
begin
  FPlayer.Active := True;
  FTr.Connect;              // asynchronous; chunks flow once connected
  FCapture.Active := True;
end;

procedure TBridgeSide.Stop;
begin
  FClosing := True;
  if Assigned(FCapture) then
    FCapture.Active := False;
  if Assigned(FTr) and FTr.IsConnected then
    FTr.Disconnect;         // sends session.close before closing
  if Assigned(FPlayer) then
    FPlayer.Active := False;
end;

procedure TBridgeSide.TrSessionReady(Sender: TObject);
begin
  SafeWriteLn(FTag + ' translator connected (gpt-realtime-translate).');
end;

procedure TBridgeSide.TrError(Sender: TObject; const ErrorMsg, ErrorCode: string);
begin
  SafeWriteLn(Format('%s ERROR translator [%s]: %s', [FTag, ErrorCode, ErrorMsg]));
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
  // When playback queue empties, reactivate muted capture
  if (not aIsPlaying) and Assigned(FMuteCapture) then
    FMuteCapture.Muted := False;
end;

// Accumulates deltas and writes the complete line when the sentence closes
// (final punctuation) or if it grows too much.
procedure TBridgeSide.FlushIfSentence(var aLine: string; const aPrefix: string);
var
  LastCh: Char;
begin
  if aLine = '' then Exit;
  LastCh := aLine[High(aLine)];
  if CharInSet(LastCh, ['.', '?', '!']) or (Length(aLine) > 160) then
  begin
    SafeWriteLn(aPrefix + Trim(aLine));
    aLine := '';
  end;
end;

procedure TBridgeSide.TrSourceDelta(Sender: TObject; const Delta: string);
begin
  FSrcText := FSrcText + Delta;
  FlushIfSentence(FSrcText, FTag + ' ');
end;

procedure TBridgeSide.TrTranslatedDelta(Sender: TObject; const Delta: string);
begin
  FDstText := FDstText + Delta;
  FlushIfSentence(FDstText, FTag + '    -> ');
end;

procedure TBridgeSide.TrAudioChunk(Sender: TObject; const AData: TBytes);
begin
  if FClosing then Exit;
  // Mute the capture that would hear us while the translation plays;
  // it is reactivated in PlayerStateChange when the queue is empty
  if Assigned(FMuteCapture) then
    FMuteCapture.Muted := True;
  FPlayer.PlayPCM16(AData, TR_PCM_RATE, 1);
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
  SetConsoleOutputCP(CP_UTF8);
  StopRequested := False;
  GConsoleLock := TCriticalSection.Create;
  try
    try
      WriteLn('=== Voice bridge with gpt-realtime-translate (MakerAI) ===');
      WriteLn('    (1 WebSocket per direction: audio -> text + translated voice)');
      WriteLn;

      if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
      begin
        WriteLn('ERROR: the OPENAI_API_KEY environment variable is not defined.');
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
        // See demo 063 / uMakerAi-AudioBridge.md: if "CABLE Input" became the
        // default Windows output you will hear nothing
        for D in TAiAudioPlayer.GetPlaybackDevices do
          if D.IsDefault and SameText(D.EndpointId, MeetingDeviceId) then
          begin
            WriteLn;
            WriteLn('*** WARNING: "CABLE Input" is the DEFAULT Windows output. ***');
            WriteLn('*** Set your HEADPHONES as the default output before continuing. ***');
            Break;
          end;
      end
      else
      begin
        WriteLn('WARNING: "' + MEETING_DEVICE_HINT + '" was not found (VB-CABLE not installed?).');
        WriteLn('  TEST MODE: the English translation will play through the default');
        WriteLn('  device and will NOT reach the meeting.');
        MeetingDeviceId := '';
      end;
      WriteLn;

      // [THEM]: loopback -> es; translated audio plays in MY headphones
      // (same device that captures loopback -> mute while it plays)
      Remote := TBridgeSide.Create(asLoopback, '[ELLOS]', TARGET_LANG_REMOTE, '');
      Remote.MuteCapture := Remote.Capture;

      // [ME]: microphone -> en; translated audio goes to the virtual cable
      Local := TBridgeSide.Create(asMicrophone, '[YO]   ', TARGET_LANG_LOCAL,
        MeetingDeviceId);
      if not HasCable then
        Local.MuteCapture := Remote.Capture; // in test mode it plays through the default

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
