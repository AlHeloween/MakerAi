TAIVoiceMonitor - Intelligent Voice Detection Component
What is TAIVoiceMonitor?
TAIVoiceMonitor is an advanced Delphi/Object Pascal component designed for intelligent real-time voice detection. Its main strength lies in its ability to self-calibrate to the sound environment and automatically detect when a person starts and stops speaking.
Main Features
🎯 Automatic Voice Detection
Distinguishes between ambient noise and human voice
Automatically detects start and end of speech
No manual threshold configuration required
🔧 Intelligent Auto-Calibration
When activated, analyzes ambient noise for 3 seconds
Automatically calculates optimal sensitivity thresholds
Adapts to different environments (quiet office, noisy place, etc.)
🎙️ Multi-Platform Capture
Windows: Uses Windows WaveIn API
Android: Uses Android AudioRecord with permission handling
Abstracts platform differences for the developer
🔊 Real-Time Transcription
Divides audio into intelligent fragments during speech
Detects natural pauses to create coherent fragments
Perfect for integrating with transcription services like OpenAI Whisper
How It Works?
Phase 1: Automatic Calibration
1. User activates the component
2. Monitor listens to environment for 3 seconds
3. Calculates average ambient noise level
4. Sets dynamic thresholds:
   - Start sensitivity = AmbientNoise × 4.0
   - Stop sensitivity = AmbientNoise × 2.0
Phase 2: Intelligent Detection
1. Constantly monitors audio level
2. When it exceeds start threshold → "Starts speaking"
3. Captures all audio while speaking
4. When below stop threshold for 1 second → "Stops speaking"
5. Delivers complete audio in WAV format
Phase 3: Additional Processing
Wake Word Verification: Analyzes first seconds for activation words
Transcription Fragments: Divides audio into chunks for real-time transcription
Memory Management: Efficiently handles audio buffers
Typical Use Cases
🤖 Voice Assistants
procedure TForm1.VoiceMonitorChangeState(Sender: TObject; aState: Boolean; 
  aIsValidForIA: Boolean; aStream: TMemoryStream);
begin
  if aState then
    ShowMessage('Listening...')
  else
  begin
    ShowMessage('Processing audio...');
    // Send aStream to transcription service
    ProcessAudioWithWhisper(aStream);
  end;
end;
📝 Text Dictation
procedure TForm1.OnTranscriptionFragment(Sender: TObject; aFragmentStream: TMemoryStream);
begin
  // Transcribe fragment in real time
  TranscribeFragment(aFragmentStream);
end;
🔊 Voice Activity Detection (VAD)
procedure TForm1.VoiceMonitorUpdate(Sender: TObject; const aSoundLevel: Int64);
begin
  ProgressBar1.Position := aSoundLevel; // Visualize sound level
  Label1.Caption := 'Speaking: ' + BoolToStr(VoiceMonitor1.IsSpeaking, True);
end;
Advantages over Other Approaches
❌ Traditional Manual Approach
Requires manually adjusting thresholds
Does not adapt to different environments
Complex configuration for end user
✅ TAIVoiceMonitor
Plug & Play: Just activate and it works
Self-adaptive: Calibrates automatically
Robust: Works in variable environments
Multi-platform: Same code for Windows and Android
Basic Implementation Example
procedure TForm1.FormCreate(Sender: TObject);
begin
  VoiceMonitor1.OnChangeState := VoiceMonitorChangeState;
  VoiceMonitor1.OnCalibrated := VoiceMonitorCalibrated;
  VoiceMonitor1.OnError := VoiceMonitorError;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  VoiceMonitor1.Active := True; // That's it!
end;

procedure TForm1.VoiceMonitorCalibrated(Sender: TObject; 
  const aNoiseLevel, aSensitivity, aStopSensitivity: Integer);
begin
  Memo1.Lines.Add(Format('Calibrated - Noise: %d, Sensitivity: %d/%d', 
    [aNoiseLevel, aSensitivity, aStopSensitivity]));
end;

procedure TForm1.VoiceMonitorChangeState(Sender: TObject; aState: Boolean; 
  aIsValidForIA: Boolean; aStream: TMemoryStream);
begin
  if aState then
  begin
    Label1.Caption := '🎤 Listening...';
    Label1.Font.Color := clRed;
  end
  else
  begin
    Label1.Caption := '✅ Audio captured';
    Label1.Font.Color := clGreen;
    
    // Here you have complete audio in WAV format
    if Assigned(aStream) then
    begin
      SaveAudioToFile(aStream); // Save file
      // or send to transcription service
    end;
  end;
end;

Next Steps
With this introduction, you already understand the purpose and basic operation of the component. In the following sections of the manual we will explore:
Detailed property configuration
Integration with AI services (OpenAI, Google Speech, etc.)
Advanced event handling
Performance optimization
Resolution of common problems
The TAIVoiceMonitor component will allow you to create sophisticated voice applications with very few lines of code!




TAIVoiceMonitor Component Properties
Public Properties (Read Only)
Active: Boolean
Controls whether the voice monitor is active or inactive
When activated, starts capture and automatic calibration
When deactivated, stops all audio capture
IsSpeaking: Boolean
Indicates whether voice/speech is currently being detected
Updates automatically based on audio levels and sensitivity
Sensitivity: Integer
Sensitivity level calculated automatically during calibration
Determines minimum threshold to detect speech start
Calculated as: ambient noise × SensitivityMultiplier
StopSensitivity: Integer
Sensitivity level to detect end of speech
Always lower than Sensitivity to avoid abrupt cuts
Calculated as: ambient noise × StopSensitivityMultiplier
State: TAiMonitorState
Current monitor state: msIdle, msRequestingPermission, msCalibrating, msMonitoring, msError
SoundLevel: Int64
Current sound level in real time
Updates constantly during capture
Configurable Properties (Published)
SilenceDuration: Integer (Default: 1000ms)
Minimum silence duration required to consider speech ended
Values less than 300ms are automatically adjusted to 300ms
SensitivityMultiplier: Double (Default: 4.0)
Multiplier to calculate start sensitivity based on ambient noise
Higher values = more sensitive to weak sounds
Lower values = less sensitive, requires more volume
StopSensitivityMultiplier: Double (Default: 2.0)
Multiplier to calculate when speech ends
Must be lower than SensitivityMultiplier to work correctly
WakeWordDurationMs: Integer (Default: 1000ms)
Duration of audio fragment sent for wake word verification
Defines how many milliseconds of speech start are captured for analysis
TranscriptionIntervalMs: Integer (Default: 1500ms)
Minimum interval between real-time transcription fragments
Controls how frequently fragments are sent for transcription
TranscriptionMaxWaitMs: Integer (Default: 4000ms)
Maximum wait time before forcing a transcription fragment send
Avoids fragments too long if there are no natural pauses
FragmentSplitRatio: Double (Default: 0.35)
Ratio to detect natural pauses and divide transcription fragments
Used when current level is less than peak × ratio (moment of relative silence)
Events
OnChangeState - Fires when changing between speech/silence 
OnCalibrated - Fires when automatic calibration completes
OnUpdate - Fires constantly with current sound level 
OnError - Fires when an error occurs 
OnWakeWordCheck - Fires to verify wake word OnTranscriptionFragment - Fires with audio fragments for real-time transcription 

Example:

Complete Demo - TAIVoiceMonitor with AI
This demo shows a complete voice assistant implementation using TAIVoiceMonitor integrated with AI services (Whisper for transcription and OpenAI for responses).
Demo Architecture
User speaks → VoiceMonitor → Whisper (Wake Word) → IA Chat → Audio Response
     ↓              ↓              ↓                   ↓              ↓
  Capture      Detection      Verification        Processing     Reproduction
   Audio        of Voice      "Sofia"            of Command      of Audio
Main Components
1. TAIVoiceMonitor - Intelligent Voice Monitor
AIVoiceMonitor: TAIVoiceMonitor;
Automatically detects start/end of voice
Self-calibrates to environment
Generates fragments for real-time transcription
2. TAIWhisper - Audio Transcription
Whisper: TAIWhisper;
Converts audio to text using OpenAI Whisper
Used to verify wake word "Sofia"
Transcribes fragments in real time
3. TAiChatConnection - AI Connection
AiConn: TAiChatConnection;
Sends voice commands to AI services (OpenAI, Claude, etc.)
Handles multimedia responses (text, audio, images)
Manages contextual conversations
4. TMediaPlayer - Audio Playback
MediaPlayer1: TMediaPlayer;
Plays audio responses generated by AI
Visual System States
The demo uses an enum to represent visual states:
TImageStatus = (
  isInactive,      // System off
  isPreparing,     // Calibrating environment
  isListening,     // Waiting for wake word
  isUserTalking,   // User speaking
  isIaTalking      // AI responding
);
Each state changes the main button icon to give immediate visual feedback.
Detailed Operation Flow
Phase 1: System Activation
procedure TFVoiceMonitor.StartMonitoring;
begin
  MemoLog.Lines.Clear;
  LblStatus.Text := 'Status: Preparing environment, please wait';
  
  // Configure display
  FCurrentSoundLevel := 0;
  FMaxLevelSeen := 100;
  ProgressBarLevel.Max := FMaxLevelSeen;
  
  // Activate components
  AnimationTimer.Enabled := True;
  AIVoiceMonitor.Active := True;  // Starts auto-calibration!
  BtnPlay.ImageIndex := Integer(TImageStatus.isPreparing);
end;
What happens here?
Event log is cleared
Progress bar is initialized to show audio levels
Monitor is activated which automatically starts 3-second calibration
Visual state changes to "Preparing"
Phase 2: Automatic Calibration
procedure TFVoiceMonitor.AIVoiceMonitorCalibrated(Sender: TObject; 
  const aNoiseLevel, aSensitivity, aStopSensitivity: Integer);
begin
  LblStatus.Text := 'Status: Listening...';
  BtnPlay.ImageIndex := Integer(TImageStatus.isListening);
end;
What happens here?
Monitor finished analyzing ambient noise
Automatically calculated optimal thresholds
System ready to detect wake word "Sofia"
Visual state changes to "Listening"
Phase 3: Voice Detection
procedure TFVoiceMonitor.AIVoiceMonitorChangeState(Sender: TObject; 
  aState, aIsValidForIA: Boolean; aStream: TMemoryStream);
begin
  if aState then
  begin
    // User started speaking!
    MemoLog.Lines.Add('-> You started speaking...');
    BtnPlay.ImageIndex := Integer(TImageStatus.isUserTalking);
  end
  else
  begin
    // User finished speaking
    BtnPlay.ImageIndex := Integer(TImageStatus.isListening);
    
    if aIsValidForIA then  // Wake word "Sofia" detected!
    begin
      // Process complete command with AI
      MF := TAiMediaFile.Create;
      MF.LoadFromStream('nothing.wav', aStream);
      Res := AiConn.AddMessageAndRun('','user',[MF]);
    end;
    // If not valid, it is automatically discarded
  end;
end;
What happens here?
When aState = True: User started speaking → Visual state "Speaking"
When aState = False: User finished → Verifies if wake word was valid
Only if aIsValidForIA = True the command is processed with AI
Invalid audio is automatically discarded
Phase 4: Wake Word Verification
procedure TFVoiceMonitor.AIVoiceMonitorWakeWordCheck(Sender: TObject; 
  aWakeWordStream: TMemoryStream; var IsValid: Boolean);
var
  Res: string;
begin
  // Transcribe first seconds of audio
  Res := LowerCase(Whisper.Transcription(aWakeWordStream, 'nothing.wav', ''));
  
  // Contains "sofia"?
  IsValid := AnsiContainsText(Res, 'sofia');
  
  // Log result
  if IsValid then
    MemoLog.Lines.Add('-->"' + Res + '"<-- → YES, it is the correct word!')
  else
    MemoLog.Lines.Add('-->"' + Res + '"<-- → NO, incorrect word.');
end;
What happens here?
Executes in parallel while user speaks
Only analyzes first 1000ms of audio (configurable)
Uses Whisper to convert audio to text
Searches for word "sofia" (case insensitive)
Result determines if complete audio will be processed
Phase 5: Real-Time Transcription
procedure TFVoiceMonitor.AIVoiceMonitorTranscriptionFragment(Sender: TObject; 
  aFragmentStream: TMemoryStream);
begin
  TTask.Run(
    procedure
    var
      Whi: TAIWhisper;
      Res: String;
    begin
      // Create separate instance for thread
      Whi := TAIWhisper.Create(nil);
      try
        // Configure credentials
        Whi.ApiKey := Whisper.ApiKey;
        Whi.Model := Whisper.Model;
        Whi.Url := Whisper.Url;
        
        // Transcribe fragment
        Res := Whi.Transcription(aFragmentStream, 'nothing.wav', '');
        
        // Show text in real time
        TThread.Queue(nil,
          procedure
          begin
            MemoPrompt.Lines.Text := MemoPrompt.Lines.Text + Res + ' ';
          end);
      finally
        Whi.Free;
      end;
    end);
end;
What happens here?
Executes every 1.5 seconds while user speaks
Creates intelligent fragments based on natural pauses
Transcribes each fragment in parallel (does not block UI)
Shows text in real time as user speaks
User sees their dictation appear while speaking!
Phase 6: AI Response Processing
procedure TFVoiceMonitor.AiConnReceiveDataEnd(const Sender: TObject; 
  aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
var
  MF: TAiMediaFile;
  Ext, FileName: String;
begin
  // AI can respond with multiple file types
  if Assigned(aMsg) and (aMsg.MediaFiles.Count > 0) then
  begin
    for MF in aMsg.MediaFiles do
    begin
      Ext := LowerCase(ExtractFileExt(MF.FileName));
      
      case Ext of
        '.wav', '.mp3': 
        begin
          // Audio response - play immediately
          MF.SaveToFile(FileName);
          MediaPlayer1.FileName := FileName;
          MediaPlayer1.Play;
        end;
        
        '.jpg', '.png', '.bmp': 
        begin
          // Response with image - show in interface
          // Image1.Bitmap.LoadFromFile(FileName);
        end;
        
        '.txt', '.pas', '.js': 
        begin
          // Code/text response - show in editor
          // MemoCode.Lines.LoadFromStream(MF.Content);
        end;
      end;
    end;
  end;
end;
What happens here?
AI processes voice command and can respond with multiple formats
Audio: Plays automatically (AI talking back)
Images: Shown in interface
Code/Text: Shown in editors
Videos: Can open in players
Phase 7: Real-Time Visual Feedback
procedure TFVoiceMonitor.AnimationTimerTimer(Sender: TObject);
const
  SMOOTHING_FACTOR = 0.2;  // Animation smoothing
var
  CurrentPos, TargetPos, NewPos: Double;
  StateStr: string;
begin
  // Get target sound level
  if AIVoiceMonitor.Active then
    TargetPos := FCurrentSoundLevel
  else
    TargetPos := 0;
    
  // Adjust scale dynamically
  if TargetPos > ProgressBarLevel.Max then
    ProgressBarLevel.Max := Round(TargetPos * 1.2);
    
  // Smooth animation toward target
  CurrentPos := ProgressBarLevel.Value;
  NewPos := CurrentPos + Round((TargetPos - CurrentPos) * SMOOTHING_FACTOR);
  ProgressBarLevel.Value := Min(NewPos, ProgressBarLevel.Max);
  
  // Show current state
  case AIVoiceMonitor.State of
    msCalibrating: StateStr := 'Calibrating...';
    msMonitoring: StateStr := 'Monitoring';
    msRequestingPermission: StateStr := 'Requesting permission...';
    msError: StateStr := 'Error';
  else
    StateStr := 'Inactive';
  end;
end;
What happens here?
Timer that executes every few milliseconds
Updates progress bar with smooth animation
Adjusts scale automatically according to volume
Shows current system state
Provides continuous visual feedback to user
Required Configuration
1. API Keys
// In FormCreate event or similar
Whisper.ApiKey := 'your-openai-api-key';
AiConn.ApiKey := 'your-openai-api-key';
2. Wake Word Configuration
AIVoiceMonitor.WakeWordDurationMs := 1000;  // First 1000ms to verify
3. Transcription Configuration
AIVoiceMonitor.TranscriptionIntervalMs := 1500;     // Fragment every 1.5s
AIVoiceMonitor.TranscriptionMaxWaitMs := 4000;      // Maximum 4s per fragment
AIVoiceMonitor.FragmentSplitRatio := 0.35;          // Detect pauses at 35% of peak
Error Handling
Voice Monitor Error
procedure TFVoiceMonitor.AIVoiceMonitorError(Sender: TObject; const ErrorMessage: string);
begin
  MemoLog.Lines.Add('ERROR: ' + ErrorMessage);
  ShowMessage('An error occurred in the audio monitor: ' + sLineBreak + ErrorMessage);
  StopMonitoring;  // Stop everything safely
end;
AI Connection Error
procedure TFVoiceMonitor.AiConnError(Sender: TObject; const ErrorMsg: string; 
  Exception: Exception; const AResponse: IHTTPResponse);
begin
  // Handle API errors (limits, connection, etc.)
  MemoLog.Lines.Add('AI Error: ' + ErrorMsg);
end;
Advantages of This Implementation
✅ Complete Voice Assistant System
Intelligent wake word ("Sofia")
Real-time transcription
AI multimedia responses
Continuous visual feedback
✅ Resource Efficiency
Only processes audio when valid wake word is detected
Parallel transcription does not block interface
Automatic memory management
✅ Professional User Experience
Clear visual states
Immediate feedback
Automatic calibration
Robust error handling
✅ Flexibility
Configurable wake word
Multiple AI services supported
Automatic multimedia responses
Easy customization
Extended Use Cases
🏠 Home Automation
if AnsiContainsText(Res, 'turn on lights') then
  // Send command to home automation system
💼 Productivity
if AnsiContainsText(Res, 'schedule meeting') then
  // Integrate with calendar
🎮 Gaming
if AnsiContainsText(Res, 'pause game') then
  // Voice game control
🚗 Automotive
if AnsiContainsText(Res, 'navigate to') then
  // Integrate with GPS/navigation
This demo shows how to create a complete and professional voice assistant with very few lines of code, leveraging the power of the TAIVoiceMonitor component.



Configuration Form - TAIVoiceMonitor
Configurable Parameters of TAIVoiceMonitor
🎯 Category: Voice Detection
1. SilenceDuration (Integer) - Silence Duration
pascal
property SilenceDuration: Integer default DEFAULT_SILENCE_DURATION_MS; // 1000ms
What does it do?
Defines how long silence must be detected to consider user finished speaking
Avoids premature cuts if there are natural pauses while speaking
Recommended configuration:
Fast: 500-800ms (for short commands)
Normal: 1000-1500ms (natural conversation)
Slow: 2000-3000ms (for people who speak slowly)
Suggested control: SpinEdit with range 300-5000ms

2. SensitivityMultiplier (Double) - Sensitivity Multiplier
pascal
property SensitivityMultiplier: Double default 4.0;
What does it do?
Multiplies ambient noise level to determine when voice detection starts
Sensitivity = AmbientNoise × SensitivityMultiplier
Recommended configuration:
Quiet environment: 2.0-3.0 (quiet office, silent home)
Normal environment: 3.0-5.0 (office with moderate noise)
Noisy environment: 5.0-8.0 (cafeteria, street)
Suggested control: FloatSpinEdit with range 1.0-10.0, increments 0.5

3. StopSensitivityMultiplier (Double) - Stop Multiplier
pascal
property StopSensitivityMultiplier: Double default 2.0;
What does it do?
Multiplies ambient noise level to determine when to stop detection
StopSensitivity = AmbientNoise × StopSensitivityMultiplier
IMPORTANT: Must be lower than SensitivityMultiplier
Recommended configuration:
Always lower than SensitivityMultiplier
Typical difference: 1.5-2.0 points less than SensitivityMultiplier
Example: If SensitivityMultiplier=4.0, then StopSensitivityMultiplier=2.0-2.5
Suggested control: FloatSpinEdit with automatic validation

🔊 Category: Wake Word
4. WakeWordDurationMs (Integer) - Keyword Duration
pascal
property WakeWordDurationMs: Integer default DEFAULT_WAKE_WORD_DURATION_MS; // 1000ms
What does it do?
Defines how many milliseconds of audio start are sent to verify wake word
Only analyzes the beginning of audio, not the entire command
Recommended configuration:
Short wake word ("OK", "Hey"): 500-800ms
Normal wake word ("Sofia", "Alexa"): 1000-1500ms
Complete phrase ("Hello computer"): 2000-3000ms
Suggested control: SpinEdit with range 500-3000ms

📝 Category: Real-Time Transcription
5. TranscriptionIntervalMs (Integer) - Transcription Interval
pascal
property TranscriptionIntervalMs: Integer default DEFAULT_TRANSCRIPTION_INTERVAL_MS; // 1500ms
What does it do?
Minimum time between real-time transcription fragments
Avoids fragments too short that would be useless
Recommended configuration:
Fast real-time: 1000-1500ms (very reactive transcription)
Quality/speed balance: 1500-2500ms (recommended)
Quality priority: 2500-4000ms (longer fragments)
Suggested control: SpinEdit with range 1000-5000ms

6. TranscriptionMaxWaitMs (Integer) - Maximum Wait Time
pascal
property TranscriptionMaxWaitMs: Integer default DEFAULT_TRANSCRIPTION_MAX_WAIT_MS; // 4000ms
What does it do?
Maximum time before forcing a fragment send
Avoids a very long phrase never being processed for lack of pauses
Recommended configuration:
Always greater than TranscriptionIntervalMs
Typically: 2-3x TranscriptionIntervalMs
Example: If TranscriptionIntervalMs=1500ms, then TranscriptionMaxWaitMs=4000ms
Suggested control: SpinEdit with automatic validation

7. FragmentSplitRatio (Double) - Fragment Split Ratio
pascal
property FragmentSplitRatio: Double default DEFAULT_FRAGMENT_SPLIT_RATIO; // 0.35
What does it do?
Detects natural pauses to intelligently divide fragments
When current level < (PeakLevel × FragmentSplitRatio) = pause detected
Recommended configuration:
Very pause sensitive: 0.20-0.30 (divides at minimal pauses)
Normal sensitivity: 0.30-0.40 (natural pauses)
Less sensitive: 0.40-0.60 (only pronounced pauses)
Suggested control: FloatSpinEdit with range 0.1-0.8, increments 0.05

Configuration Form Design
Suggested Visual Structure:
pascal
TConfigForm = class(TForm)
private
  // Voice Detection Controls
  SpinSilenceDuration: TSpinEdit;
  FloatSpinSensitivityMultiplier: TFloatSpinEdit;
  FloatSpinStopSensitivityMultiplier: TFloatSpinEdit;
  
  // Wake Word Controls  
  SpinWakeWordDuration: TSpinEdit;
  
  // Transcription Controls
  SpinTranscriptionInterval: TSpinEdit;
  SpinTranscriptionMaxWait: TSpinEdit;
  FloatSpinFragmentSplitRatio: TFloatSpinEdit;
  
  // Preset Controls
  ComboPresets: TComboBox;
  BtnSavePreset: TButton;
  BtnLoadPreset: TButton;
  
  // Live Testing
  BtnTestCalibration: TButton;
  ProgressBarTestLevel: TProgressBar;
  LabelTestResults: TLabel;
end;
Recommended Presets:
🏠 Quiet Environment (Home/Private Office)
pascal
procedure LoadQuietPreset;
begin
  SilenceDuration := 800;
  SensitivityMultiplier := 2.5;
  StopSensitivityMultiplier := 1.5;
  WakeWordDurationMs := 1000;
  TranscriptionIntervalMs := 1200;
  TranscriptionMaxWaitMs := 3500;
  FragmentSplitRatio := 0.25;
end;
🏢 Normal Environment (Shared Office)
pascal
procedure LoadNormalPreset;
begin
  SilenceDuration := 1000;
  SensitivityMultiplier := 4.0;
  StopSensitivityMultiplier := 2.0;
  WakeWordDurationMs := 1000;
  TranscriptionIntervalMs := 1500;
  TranscriptionMaxWaitMs := 4000;
  FragmentSplitRatio := 0.35;
end;
🔊 Noisy Environment (Public Place)
pascal
procedure LoadNoisyPreset;
begin
  SilenceDuration := 1500;
  SensitivityMultiplier := 6.0;
  StopSensitivityMultiplier := 3.0;
  WakeWordDurationMs := 1500;
  TranscriptionIntervalMs := 2000;
  TranscriptionMaxWaitMs := 5000;
  FragmentSplitRatio := 0.45;
end;
Important Validations:
pascal
procedure ValidateConfiguration;
begin
  // StopSensitivity must be lower than Sensitivity
  if StopSensitivityMultiplier >= SensitivityMultiplier then
    StopSensitivityMultiplier := SensitivityMultiplier - 0.5;
    
  // MaxWait must be greater than Interval
  if TranscriptionMaxWaitMs <= TranscriptionIntervalMs then
    TranscriptionMaxWaitMs := TranscriptionIntervalMs * 2;
    
  // Minimum SilenceDuration
  if SilenceDuration < 300 then
    SilenceDuration := 300;
    
  // FragmentSplitRatio in valid range
  if FragmentSplitRatio < 0.1 then FragmentSplitRatio := 0.1;
  if FragmentSplitRatio > 0.8 then FragmentSplitRatio := 0.8;
end;
Live Testing:
pascal
procedure TestCurrentConfiguration;
begin
  // Apply temporary configuration
  TestVoiceMonitor.SilenceDuration := SpinSilenceDuration.Value;
  TestVoiceMonitor.SensitivityMultiplier := FloatSpinSensitivityMultiplier.Value;
  // ... etc
  
  // Activate for 10 seconds to test
  TestVoiceMonitor.Active := True;
  TestTimer.Interval := 10000; // 10 seconds
  TestTimer.Enabled := True;
  
  BtnTestCalibration.Text := 'Testing... (10s)';
  BtnTestCalibration.Enabled := False;
end;
UI/UX Tips:
📊 Visual Indicators
Progress bar showing real-time sound levels
Threshold indicators (lines on bar showing Sensitivity/StopSensitivity)
Visual monitor state (Calibrating/Listening/Error)
🔧 Smart Controls
Sliders with labels for more intuitive values
Real-time validation with help messages
"Restore Defaults" button to return to default values
💾 Persistence
Save configuration automatically
Multiple profiles (Home, Office, Mobile)
Import/Export configurations
🎯 Configuration Wizard
Initial wizard that guides first configuration
Automatic environment test that suggests presets
Contextual explanations for each parameter
Example Code - Apply Configuration:
pascal
procedure ApplyConfigurationToVoiceMonitor(VoiceMonitor: TAIVoiceMonitor);
begin
  VoiceMonitor.SilenceDuration := SpinSilenceDuration.Value;
  VoiceMonitor.SensitivityMultiplier := FloatSpinSensitivityMultiplier.Value;
  VoiceMonitor.StopSensitivityMultiplier := FloatSpinStopSensitivityMultiplier.Value;
  VoiceMonitor.WakeWordDurationMs := SpinWakeWordDuration.Value;
  VoiceMonitor.TranscriptionIntervalMs := SpinTranscriptionInterval.Value;
  VoiceMonitor.TranscriptionMaxWaitMs := SpinTranscriptionMaxWait.Value;
  VoiceMonitor.FragmentSplitRatio := FloatSpinFragmentSplitRatio.Value;
end;
This configuration form will allow users to completely customize VoiceMonitor behavior according to their specific environment and usage needs.
