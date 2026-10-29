unit uMainAudioMonitor;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  System.Threading, Winapi.CommCtrl, System.Math, System.AnsiStrings,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  uMakerAi.Utils.VoiceMonitor, // Our monitor unit
{$IFDEF MSWINDOWS}
  Winapi.MMSystem,
{$ENDIF}
  Vcl.StdCtrls, System.IOUtils, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Samples.Spin, uMakerAi.Whisper, uMakerAi.Chat.Tools, uMakerAi.Core;

type
  TForm6 = class(TForm)
    ButtonStart: TButton;
    ButtonStop: TButton;
    MemoLog: TMemo;
    ProgressBarLevel: TProgressBar;
    AnimationTimer: TTimer;
    Label1: TLabel;
    SpinEditSilence: TSpinEdit;
    Label3: TLabel;
    FloatSpinEditStart: TSpinEdit;
    Label4: TLabel;
    FloatSpinEditStop: TSpinEdit;
    Label5: TLabel;
    SpinEditWakeWord: TSpinEdit;
    AIVoiceMonitor: TAIVoiceMonitor;
    Label2: TLabel;
    BtnRefreshDevices: TButton;
    OpenDialog1: TOpenDialog;
    MemoTranscription: TMemo;
    ComboBoxDevices: TComboBox;
    LabelCurrentDevice: TLabel;
    ChWakeUp: TCheckBox;
    // NEW: Controls to configure the wake word duration
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
    procedure SpinEditSilenceChange(Sender: TObject);
    procedure FloatSpinEditStartChange(Sender: TObject);
    procedure FloatSpinEditStopChange(Sender: TObject);
    procedure AnimationTimerTimer(Sender: TObject);
    // NEW: Event for the new control
    procedure SpinEditWakeWordChange(Sender: TObject);
    procedure AIVoiceMonitorChangeState(Sender: TObject; aState, aIsValidForIA: Boolean; aStream: TMemoryStream);
    procedure AIVoiceMonitorCalibrated(Sender: TObject; const aNoiseLevel, aSensitivity, aStopSensitivity: Integer);
    procedure AIVoiceMonitorError(Sender: TObject; const ErrorMessage: string);
    procedure AIVoiceMonitorUpdate(Sender: TObject; const aSoundLevel: Int64);
    procedure AIVoiceMonitorWakeWordCheck(Sender: TObject; aWakeWordStream: TMemoryStream);
    procedure AIVoiceMonitorTranscriptionFragment(Sender: TObject; aFragmentStream: TMemoryStream);
    procedure AIVoiceMonitorSpeechEnd(Sender: TObject; aIsValidForIA: Boolean; aStream: TMemoryStream);
    procedure ComboBoxDevicesChange(Sender: TObject);
    procedure BtnRefreshDevicesClick(Sender: TObject);
    procedure ChWakeUpClick(Sender: TObject);
  private
    // FAudioMonitor: TAIVoiceMonitor;
    FMaxLevelSeen: Int64;
    FCurrentSoundLevel: Int64;
    procedure ProcessVoiceCommand(const Command: String);
    procedure SendToAI(const Command: String);
    procedure LoadAudioDevices;
    procedure UpdateCurrentDeviceLabel;
    Function NewWhisper: TAIWhisper;
  public
    { Public declarations }
  end;

var
  Form6: TForm6;

implementation

{$R *.dfm}
// --- Implementation of TVoiceMonitor event handlers ---

procedure TForm6.FormCreate(Sender: TObject);
begin

  // Prepare the directory to save WAV files.
  try
    TDirectory.CreateDirectory('c:\temp');
  except
    on E: Exception do
      ShowMessage('Could not create directory c:\temp. Please create it manually. Error: ' + E.Message);
  end;

  // --- User Interface Configuration ---
  FMaxLevelSeen := 8000;
  Label1.Caption := 'Silence pause (ms):';
  SpinEditSilence.MinValue := 300;
  SpinEditSilence.MaxValue := 5000;
  SpinEditSilence.Value := DEFAULT_SILENCE_DURATION_MS * 2;
  AIVoiceMonitor.SilenceDuration := SpinEditSilence.Value;

  Label3.Caption := 'Start mult.:';
  FloatSpinEditStart.MinValue := 15; // Representa 1.5
  FloatSpinEditStart.MaxValue := 100; // Representa 10.0
  FloatSpinEditStart.Value := Round(AIVoiceMonitor.SensitivityMultiplier * 10);

  Label4.Caption := 'Stop mult.:';
  FloatSpinEditStop.MinValue := 10; // Representa 1.0
  FloatSpinEditStop.MaxValue := 50; // Representa 5.0
  FloatSpinEditStop.Value := Round(AIVoiceMonitor.StopSensitivityMultiplier * 10);

  // NEW: Configure control for wake word duration.
  Label5.Caption := 'Wake Word duration (ms):';
  SpinEditWakeWord.MinValue := 500;
  SpinEditWakeWord.MaxValue := 5000;
  SpinEditWakeWord.Value := DEFAULT_WAKE_WORD_DURATION_MS;
  AIVoiceMonitor.WakeWordDurationMs := SpinEditWakeWord.Value;

  ChWakeUp.Checked := AIVoiceMonitor.WakeWordActive;


  LoadAudioDevices;
  UpdateCurrentDeviceLabel;


  ProgressBarLevel.Min := 0;
  ProgressBarLevel.Max := FMaxLevelSeen;
  ButtonStop.Enabled := False;
  Self.Caption := 'Monitor Inactive';
end;

procedure TForm6.FormDestroy(Sender: TObject);
begin
  AnimationTimer.Enabled := False;
end;

procedure TForm6.LoadAudioDevices;
var
  Devices: TArray<TWaveInDeviceInfo>;
  I: Integer;
  DeviceID: UINT;
begin
  // Save the current selection if possible
  // (Although when reloading we usually want to see the component's actual state)

  ComboBoxDevices.Items.Clear;

  // Get the component list (which now ALREADY INCLUDES Default at position 0)
  Devices := TAIVoiceMonitor.GetWaveInDevices;

  for I := 0 to High(Devices) do
  begin
    // We save the ID in the Item object.
    // We cast to NativeInt for 32/64-bit compatibility.
    ComboBoxDevices.Items.AddObject(Devices[I].DeviceName, TObject(NativeInt(Devices[I].DeviceID)));
  end;

  // Select in the ComboBox the device configured in the component
  if ComboBoxDevices.Items.Count > 0 then
  begin
    ComboBoxDevices.ItemIndex := 0; // By default the first one (WAVE_MAPPER)

    for I := 0 to ComboBoxDevices.Items.Count - 1 do
    begin
      DeviceID := UINT(NativeInt(ComboBoxDevices.Items.Objects[I]));
      if DeviceID = AIVoiceMonitor.DeviceID then
      begin
        ComboBoxDevices.ItemIndex := I;
        Break;
      end;
    end;
  end;

  MemoLog.Lines.Add(Format('Found %d audio devices.', [Length(Devices)]));
end;

function TForm6.NewWhisper: TAIWhisper;
begin
  Result := TAIWhisper.Create(Nil);
  Result.ApiKey := 'xxxyyy';
  Result.url := 'http://192.168.3.121:5150/v1/';
  Result.Languaje := 'es';
  Result.Model := 'openai/whisper-large-v3-turbo';
end;

procedure TForm6.BtnRefreshDevicesClick(Sender: TObject);
begin
  LoadAudioDevices;
  UpdateCurrentDeviceLabel;
  MemoLog.Lines.Add('Device list updated.');
end;

procedure TForm6.ButtonStartClick(Sender: TObject);
begin
  MemoLog.Clear;
  MemoLog.Lines.Add('Activating monitor... Please keep quiet for calibration.');

  FCurrentSoundLevel := 0;
  FMaxLevelSeen := 8000; // Reset the maximum so the bar adjusts
  ProgressBarLevel.Max := FMaxLevelSeen;
  AnimationTimer.Enabled := True;

  // Disable controls
  SpinEditSilence.Enabled := False;
  FloatSpinEditStart.Enabled := False;
  FloatSpinEditStop.Enabled := False;
  SpinEditWakeWord.Enabled := False; // Disable the new control
  ButtonStart.Enabled := False;
  ButtonStop.Enabled := True;
  ComboBoxDevices.Enabled := False;

  AIVoiceMonitor.Active := True;
end;

procedure TForm6.ButtonStopClick(Sender: TObject);
begin
  AIVoiceMonitor.Active := False;
  AnimationTimer.Enabled := False;
  MemoLog.Lines.Add('Monitor deactivated.');

  // Enable controls
  ButtonStart.Enabled := True;
  ButtonStop.Enabled := False;
  SpinEditSilence.Enabled := True;
  FloatSpinEditStart.Enabled := True;
  FloatSpinEditStop.Enabled := True;
  SpinEditWakeWord.Enabled := True; // Enable the new control
  ComboBoxDevices.Enabled := True;

  ProgressBarLevel.Position := 0;
  Self.Caption := 'Monitor Inactive';
end;

procedure TForm6.ChWakeUpClick(Sender: TObject);
begin
  AIVoiceMonitor.WakeWordActive := ChWakeUp.Checked;
end;

procedure TForm6.ComboBoxDevicesChange(Sender: TObject);
var
  SelectedDeviceID: UINT;
begin
  if ComboBoxDevices.ItemIndex < 0 then
    Exit;

  // Retrieve the saved object ID
  SelectedDeviceID := UINT(NativeInt(ComboBoxDevices.Items.Objects[ComboBoxDevices.ItemIndex]));

  try
    // If the monitor is active, we must stop it before changing (the component would raise an error otherwise)
    if AIVoiceMonitor.Active then
    begin
      AIVoiceMonitor.Active := False;
      AIVoiceMonitor.DeviceID := SelectedDeviceID;
      UpdateCurrentDeviceLabel;
      MemoLog.Lines.Add('Monitor stopped to change device.');
      // Optional: Restart automatically
      // AIVoiceMonitor.Active := True;
    end
    else
    begin
      AIVoiceMonitor.DeviceID := SelectedDeviceID;
      UpdateCurrentDeviceLabel;
    end;

    MemoLog.Lines.Add(Format('Selected device: %s', [ComboBoxDevices.Items[ComboBoxDevices.ItemIndex]]));

  except
    on E: Exception do
    begin
      MemoLog.Lines.Add('Error changing device: ' + E.Message);
      ShowMessage('Error: ' + E.Message);
    end;
  end;
end;


// --- UI Control Events ---

procedure TForm6.SpinEditSilenceChange(Sender: TObject);
begin
  AIVoiceMonitor.SilenceDuration := SpinEditSilence.Value;
end;

procedure TForm6.FloatSpinEditStartChange(Sender: TObject);
begin
  AIVoiceMonitor.SensitivityMultiplier := (FloatSpinEditStart.Value / 10);
end;

procedure TForm6.FloatSpinEditStopChange(Sender: TObject);
begin
  AIVoiceMonitor.StopSensitivityMultiplier := (FloatSpinEditStop.Value / 10);
end;

procedure TForm6.SpinEditWakeWordChange(Sender: TObject);
begin
  AIVoiceMonitor.WakeWordDurationMs := SpinEditWakeWord.Value;
end;

procedure TForm6.UpdateCurrentDeviceLabel;
begin
  if Assigned(AIVoiceMonitor) then
    LabelCurrentDevice.Caption := 'Current device: ' + AIVoiceMonitor.CurrentDeviceName
  else
    LabelCurrentDevice.Caption := 'Current device: ---';
end;

procedure TForm6.AIVoiceMonitorCalibrated(Sender: TObject; const aNoiseLevel, aSensitivity, aStopSensitivity: Integer);
begin
  MemoLog.Lines.Add('--- Calibration Finished ---');
  MemoLog.Lines.Add(Format('Base noise level: %d', [aNoiseLevel]));
  MemoLog.Lines.Add(Format('START threshold adjusted to: %d', [aSensitivity]));
  MemoLog.Lines.Add(Format('STOP threshold adjusted to: %d', [aStopSensitivity]));
  MemoLog.Lines.Add('Ready! Waiting for wake word...');
end;

procedure TForm6.AIVoiceMonitorChangeState(Sender: TObject; aState, aIsValidForIA: Boolean; aStream: TMemoryStream);
var
  LocalStream: TMemoryStream;
begin
  if aState then
  begin
    // The monitor detected that the user started speaking.
    MemoLog.Lines.Add('-> You started speaking...');
  end
  else
  begin
    // The monitor detected silence and finished recording.
    MemoLog.Lines.Add('<- You stopped speaking. End of audio segment.');

    // Create a local copy of the stream BEFORE it is released by the caller
    LocalStream := TMemoryStream.Create;
    try
      if Assigned(aStream) then
      begin
        aStream.Position := 0; // Make sure we are at the beginning
        LocalStream.CopyFrom(aStream, 0); // Copy all the content
        LocalStream.Position := 0; // Reset position for later use
      end;

      // Here is the key logic: we only process the complete audio if the wake word was validated.
      if aIsValidForIA then
      begin
        MemoLog.Lines.Add('   >> CORRECT KEYWORD! Processing the complete command...');
        // In a real application, this is where you would send the complete 'LocalStream' to Whisper
        // to transcribe the command following the wake word.
        LocalStream.SaveToFile('c:\temp\grabacion_COMPLETA_VALIDA.wav');
        MemoLog.Lines.Add('      Complete audio saved to: c:\temp\grabacion_COMPLETA_VALIDA.wav');
      end
      else
      begin
        MemoLog.Lines.Add('   -- Incorrect or undetected keyword. Audio discarded.');
        // Optional: you can save the discarded audio for debugging purposes.
        LocalStream.SaveToFile('c:\temp\grabacion_descartada.wav');
      end;
    finally
      // We free our local copy
      LocalStream.Free;
    end;
    // NOTE: We do NOT free aStream here; it is the caller's responsibility (TAIVoiceMonitor)
  end;
end;

procedure TForm6.AIVoiceMonitorError(Sender: TObject; const ErrorMessage: string);
begin
  MemoLog.Lines.Add('ERROR: ' + ErrorMessage);
  ShowMessage('An error occurred in the audio monitor: ' + sLineBreak + ErrorMessage);
  ButtonStopClick(Sender);
end;

procedure TForm6.AIVoiceMonitorSpeechEnd(Sender: TObject; aIsValidForIA: Boolean; aStream: TMemoryStream);
var
  LocalStream: TMemoryStream;
  TranscriptionResult: String;
  LWhisper: TAIWhisper;
begin
  // Create a local copy of the stream for safe use
  LocalStream := TMemoryStream.Create;
  try
    // Copy the received stream content
    if Assigned(aStream) then
    begin
      aStream.Position := 0;
      LocalStream.CopyFrom(aStream, 0);
      LocalStream.Position := 0;
    end;

    // Verify that we have valid data
    if LocalStream.Size = 0 then
    begin
      MemoLog.Lines.Add('--- Warning: Empty audio stream ---');
      Exit;
    end;

    try
      // Check whether the wake word was validated
      if aIsValidForIA then
      begin
        MemoLog.Lines.Add('');
        MemoLog.Lines.Add('========================================');
        MemoLog.Lines.Add('   PROCESSING COMPLETE COMMAND');
        MemoLog.Lines.Add('   Wake Word VALIDATED ✓');
        MemoLog.Lines.Add('   Audio size: ' + FormatFloat('#,##0', LocalStream.Size) + ' bytes');
        MemoLog.Lines.Add('========================================');

        // Optional: Save the validated complete audio for debugging
{$IFDEF DEBUG}
        LocalStream.SaveToFile('c:\temp\comando_completo_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.wav');
{$ENDIF}
        // Send the complete audio to Whisper for transcription
        LWhisper := NewWhisper;
        Try
          TranscriptionResult := LWhisper.Transcription(LocalStream, 'comando_completo.wav', 'transcribe to Spanish');
        Finally
          LWhisper.Free;
        End;

        // Show the transcription result
        if TranscriptionResult <> '' then
        begin
          MemoLog.Lines.Add('');
          MemoLog.Lines.Add('>>> COMPLETE TRANSCRIPTION:');
          MemoLog.Lines.Add(TranscriptionResult);
          MemoLog.Lines.Add('');

          // Here you can process the complete command
          // For example: send to GPT, execute an action, etc.
          ProcessVoiceCommand(TranscriptionResult);
        end
        else
        begin
          MemoLog.Lines.Add('⚠ Could not transcribe the audio');
        end;
      end
      else
      begin
        MemoLog.Lines.Add('');
        MemoLog.Lines.Add('--- Discarded audio (Wake Word NOT validated) ---');
        MemoLog.Lines.Add('   Size: ' + FormatFloat('#,##0', LocalStream.Size) + ' bytes');

        // --- transcription of the total audio

        LWhisper := NewWhisper;
        Try
          TranscriptionResult := LWhisper.Transcription(LocalStream, 'fragment.wav', 'transcribe to Spanish');
        Finally
          LWhisper.Free;
        End;

        // Show the transcription result of the fragment
        if TranscriptionResult <> '' then
        begin
          MemoLog.Lines.Add('--- total audio transcribed ---');
          MemoLog.Lines.Add(TranscriptionResult);
          MemoLog.Lines.Add('');

          MemoTranscription.Lines.Add('--- total audio transcribed ---');
          MemoTranscription.Lines.Add('');
          MemoTranscription.Lines.Text := MemoTranscription.Lines.Text + ' -- ' + TranscriptionResult;
        end;

        // Optional: Save discarded audio for analysis
{$IFDEF DEBUG}
        LocalStream.SaveToFile('c:\temp\descartado_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.wav');
        MemoLog.Lines.Add('   Saved to: c:\temp\descartado_*.wav (for analysis)');
{$ENDIF}
      end;

    except
      on E: Exception do
      begin
        MemoLog.Lines.Add('');
        MemoLog.Lines.Add('❌ ERROR processing the final audio:');
        MemoLog.Lines.Add('   ' + E.Message);
      end;
    end;

  finally
    // Free our local copy
    LocalStream.Free;
  end;

  // Auto-scroll to the end of the memo
  MemoLog.SelStart := Length(MemoLog.Text);
  MemoLog.Perform(EM_SCROLLCARET, 0, 0);
end;

// --- HELPER FUNCTION TO PROCESS COMMANDS ---
procedure TForm6.ProcessVoiceCommand(const Command: String);
var
  LowerCommand: String;
begin
  LowerCommand := LowerCase(Trim(Command));

  MemoLog.Lines.Add('');
  MemoLog.Lines.Add('🎯 Processing command...');

  // Here you can implement your processing logic
  // Examples:

  if Pos('open', LowerCommand) > 0 then
  begin
    MemoLog.Lines.Add('   → Open command detected');
    // Implement open logic
  end
  else if Pos('close', LowerCommand) > 0 then
  begin
    MemoLog.Lines.Add('   → Close command detected');
    // Implement close logic
  end
  else if Pos('search', LowerCommand) > 0 then
  begin
    MemoLog.Lines.Add('   → Search command detected');
    // Implement search logic
  end
  else
  begin
    MemoLog.Lines.Add('   → Sending to AI for general processing...');
    // Send to GPT or another LLM for processing
    SendToAI(Command);
  end;
end;

// --- HELPER FUNCTION TO SEND TO AI ---
procedure TForm6.SendToAI(const Command: String);
begin
  // Here you would implement the call to your preferred LLM
  // Example with OpenAI, Claude, etc.

  MemoLog.Lines.Add('   → Processing with AI...');

  // TODO: Implement AI API call
  // Example:
  // var Response: String;
  // Response := OpenAI.Chat(Command);
  // MemoLog.Lines.Add('   AI response: ' + Response);
end;

procedure TForm6.AIVoiceMonitorTranscriptionFragment(Sender: TObject; aFragmentStream: TMemoryStream);
var
  LocalStream: TMemoryStream;
  TranscriptionResult: String;
  LWhisper: TAIWhisper;
begin
  // Create a local copy of the stream for safe use
  LocalStream := TMemoryStream.Create;
  try
    // Copy the received fragment content
    if Assigned(aFragmentStream) then
    begin
      aFragmentStream.Position := 0;
      LocalStream.CopyFrom(aFragmentStream, 0);
      LocalStream.Position := 0;
    end;

    // Verify that we have valid data
    if LocalStream.Size = 0 then
      Exit;

    try
      // Send the fragment to Whisper for transcription
      // Note: We don't need to save the file, we send the stream directly
      LWhisper := NewWhisper;;
      Try
        TranscriptionResult := LWhisper.Transcription(LocalStream, 'fragment.wav', // Virtual file name
          'transcribe to Spanish');

      Finally
        LWhisper.Free;
      End;

      // Show the transcription result of the fragment
      if TranscriptionResult <> '' then
      begin
        MemoLog.Lines.Add('--- Transcribed fragment ---');
        MemoLog.Lines.Add(TranscriptionResult);
        MemoLog.Lines.Add('');

        MemoTranscription.Lines.Add(TranscriptionResult);
      end;
    except
      on E: Exception do
      begin
        MemoLog.Lines.Add('Error transcribing fragment: ' + E.Message);
      end;
    end;
  finally
    // Always free our local copy
    LocalStream.Free;
  end;
end;

procedure TForm6.AIVoiceMonitorUpdate(Sender: TObject; const aSoundLevel: Int64);
begin
  FCurrentSoundLevel := aSoundLevel;
end;



{
procedure TForm6.AIVoiceMonitorWakeWordCheck(Sender: TObject; aWakeWordStream: TMemoryStream; var IsValid: Boolean);

var
  Res: string;
  TargetWakeWord: string;
  LWhisper: TAIWhisper;
  DurationMs: Int64;
  BytesPerSec: Integer;
  Words: TArray<string>;
  Word: string;
  CleanWord, CleanTarget: string;
  Distance: Integer;
  DetectedWord: string; // To show in the log which one triggered
begin
  // 1. Security validation
  if (aWakeWordStream = nil) or (aWakeWordStream.Size < 100) then
  begin
    IsValid := False;
    Exit;
  end;

  // Duration calculation
  BytesPerSec := AIVoiceMonitor.SampleRate * AIVoiceMonitor.Channels * (AIVoiceMonitor.BitsPerSample div 8);
  if BytesPerSec > 0 then DurationMs := (aWakeWordStream.Size * 1000) div BytesPerSec else DurationMs := 0;

  TThread.Queue(nil, procedure
  begin
    MemoLog.Lines.Add(Format('--- Verifying Wake Word (%d ms) ---', [DurationMs]));
  end);

  // 2. RESET POSITION
  aWakeWordStream.Position := 0;

  try
    LWhisper := NewWhisper;
    try
      // Transcribe audio
      Res := LWhisper.Transcription(aWakeWordStream, 'wakeword.wav', '');
    finally
      LWhisper.Free;
    end;

    // 3. INITIAL CLEANUP
    Res := Trim(Res);

    // Get Target and clean it too
    TargetWakeWord := Trim(AIVoiceMonitor.WakeWord);
    if TargetWakeWord = '' then TargetWakeWord := 'andrea';

    // Normalize the target (no accents, lowercase)
    CleanTarget := LowerCase( TAIVoiceMonitor.RemoveAccents(TargetWakeWord));

    // 4. FUZZY DETECTION LOGIC (FUZZY MATCHING)
    IsValid := False;
    DetectedWord := '';

    // Split the phrase into words (separating by spaces and punctuation)
    Words := Res.Split([' ', ',', '.', '!', '?', ';', ':'], TStringSplitOptions.ExcludeEmpty);

    for Word in Words do
    begin
      // Clean the captured word (no accents, lowercase)
      CleanWord := LowerCase(TAIVoiceMonitor.RemoveAccents(Word));

      // A) Exact match
      if CleanWord = CleanTarget then
      begin
        IsValid := True;
        DetectedWord := Word;
        Break;
      end;

      // B) Approximate match (Levenshtein)
      // Calculate the distance
      Distance := TAIVoiceMonitor.LevenshteinDistance(CleanWord, CleanTarget);

      // Allow up to 2 errors (e.g.: "Andrea" vs "Andreas" is 1, "Andrea" vs "Andre" is 1)
      // Adjust tolerance: If the word is very short (<=4), allow only 1 error.
      if (Length(CleanTarget) > 4) and (Distance <= 2) then
      begin
        IsValid := True;
        DetectedWord := Word;
        Break;
      end
      else if (Length(CleanTarget) <= 4) and (Distance <= 1) then
      begin
        IsValid := True;
        DetectedWord := Word;
        Break;
      end;
    end;

    // 5. RESULT LOG
    var ValidoLocal := IsValid; // Capture variable for anonymous thread
    var ResLocal := Res;
    var TargetLocal := TargetWakeWord;
    var DetectedLocal := DetectedWord;

    TThread.Queue(nil, procedure
    begin
      if ValidoLocal then
        MemoLog.Lines.Add(Format('  [OK] ACTIVATED! Detected "%s" (similar to "%s") in the phrase: "%s"', [DetectedLocal, TargetLocal, ResLocal]))
      else
        MemoLog.Lines.Add(Format('  [X] Ignored. Phrase: "%s" (No word similar to "%s")', [ResLocal, TargetLocal]));
    end);

  except
    on E: Exception do
    begin
      IsValid := False;
      TThread.Queue(nil, procedure
      begin
        MemoLog.Lines.Add('Error in WakeWord: ' + E.Message);
      end);
    end;
  end;
end;
}


procedure TForm6.AIVoiceMonitorWakeWordCheck(Sender: TObject; aWakeWordStream: TMemoryStream);
var
  StreamCopy: TMemoryStream;
begin
  // We create a copy of the stream because the original will be freed when leaving this event
  StreamCopy := TMemoryStream.Create;
  StreamCopy.CopyFrom(aWakeWordStream, 0);
  StreamCopy.Position := 0;

  // We launch the heavy validation in a separate thread
  TTask.Run(procedure
    var
      Res, TargetWakeWord, CleanTarget, CleanWord, DetectedWord: string;
      LWhisper: TAIWhisper;
      Words: TArray<string>;
      Word: string;
      Distance: Integer;
      IsValidResult: Boolean;
    begin
      try
        try
          LWhisper := NewWhisper; // Your factory function
          try
            Res := LWhisper.Transcription(StreamCopy, 'wakeword.wav', '');
          finally
            LWhisper.Free;
          end;

          // --- Cleanup and comparison logic ---
          Res := Trim(Res);
          TargetWakeWord := Trim(AIVoiceMonitor.WakeWord);
          if TargetWakeWord = '' then TargetWakeWord := 'andrea';

          // RemoveAccents is only a strategy in Spanish; change for other languages
          CleanTarget := LowerCase(TAIVoiceMonitor.RemoveAccents(TargetWakeWord));

          IsValidResult := False;
          DetectedWord := '';
          Words := Res.Split([' ', ',', '.', '!', '?', ';', ':'], TStringSplitOptions.ExcludeEmpty);

          for Word in Words do
          begin
            CleanWord := LowerCase(TAIVoiceMonitor.RemoveAccents(Word));
            Distance := TAIVoiceMonitor.LevenshteinDistance(CleanWord, CleanTarget);

            if (CleanWord = CleanTarget) or
               ((Length(CleanTarget) > 4) and (Distance <= 2)) or
               ((Length(CleanTarget) <= 4) and (Distance <= 1)) then
            begin
              IsValidResult := True;
              DetectedWord := Word;
              Break;
            end;
          end;

          // --- NOTIFY THE COMPONENT OF THE RESULT ---
          AIVoiceMonitor.ConfirmWakeWord(IsValidResult);

          // Log on the main thread
          TThread.Queue(nil, procedure
          begin
            if IsValidResult then
              MemoLog.Lines.Add('WakeWord detected: ' + DetectedWord)
            else
              MemoLog.Lines.Add('WakeWord not recognized in: ' + Res);
          end);

        finally
          StreamCopy.Free;
        end;
      except
        on E: Exception do
          TThread.Queue(nil, procedure begin MemoLog.Lines.Add('Error: ' + E.Message); end);
      end;
    end);
end;


procedure TForm6.AnimationTimerTimer(Sender: TObject);
const
  SMOOTHING_FACTOR = 0.2;
  PBST_NORMAL = 1;
  PBST_ERROR = 2;
  PBST_PAUSED = 3;
var
  CurrentPos, TargetPos, NewPos: Int64;
  StateStr: string;
begin
  if AIVoiceMonitor.Active then
    TargetPos := FCurrentSoundLevel
  else
    TargetPos := 0;

  if TargetPos > ProgressBarLevel.Max then
    ProgressBarLevel.Max := Round(TargetPos * 1.2); // Give some margin

  CurrentPos := ProgressBarLevel.Position;
  NewPos := CurrentPos + Round((TargetPos - CurrentPos) * SMOOTHING_FACTOR);
  ProgressBarLevel.Position := Min(NewPos, ProgressBarLevel.Max);

  case AIVoiceMonitor.State of
    msCalibrating:
      StateStr := 'Calibrating...';
    msMonitoring:
      StateStr := 'Monitoring';
    msRequestingPermission:
      StateStr := 'Requesting permission...';
    msError:
      StateStr := 'Error';
  else
    StateStr := 'Inactive';
  end;

  Self.Caption := Format('State: %s | Level: %d | Thresholds: %d / %d | Speaking: %s', [StateStr, TargetPos, AIVoiceMonitor.Sensitivity, AIVoiceMonitor.StopSensitivity, BoolToStr(AIVoiceMonitor.IsSpeaking, True)]);
end;

end.
