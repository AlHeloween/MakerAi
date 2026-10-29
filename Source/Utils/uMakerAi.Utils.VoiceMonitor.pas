// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

{

  ##  AudioRecord error codes:

  | Code | Constant | Meaning | Action |
  |------|----------|---------|--------|
  | **-3** | `ERROR_INVALID_OPERATION` | AudioRecord in invalid state | [ERR] Abort |
  | **-2** | `ERROR_BAD_VALUE` | Invalid parameters | [ERR] Abort |
  | **-6** | `ERROR_DEAD_OBJECT` | Object died | [ERR] Abort |
  | **-1** | `ERROR` | Generic error | [!] Retry |
  | **0** | - | Nothing read | [!] Retry |
  | **>0** | - | Bytes read successfully | [OK] Process |

  ---

  ##  Function flow:
  ```
  Start of loop
  v
  AudioRecord valid and recording?
   NO -> Abort with error
   YES v
  Try to read buffer
  v
  BytesRead > 0?
   YES -> Process audio, reset errors, continue
   = 0 -> Increment errors, >20? -> Abort : Retry
   < 0 -> Analyze error code
   Critical error (-3, -2, -6) -> Abort
   Transient error (-1) -> >10 consecutive?
   YES -> Abort
   NO -> Sleep(50), Retry
  v
  Finished or fatal error?
   YES -> Exit loop
   NO -> Continue loop
  v
  Finally: Release JBuffer


   Recommended values table:

  Environment	SensitivityMultiplier	StopSensitivityMultiplier
  Silent (office)	3.0 - 4.0	2.0 - 2.5
  Normal (home)	2.0 - 2.5	1.5 - 1.8
  Noisy (street)	1.5 - 2.0	1.2 - 1.5
  Distant microphone	1.2 - 1.8	1.0 - 1.2



}

unit uMakerAi.Utils.VoiceMonitor;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Variants,
  System.IOUtils, System.SyncObjs, System.Math, System.Permissions,
  System.Threading, System.Diagnostics,

uMakerAi.Realtime,  uMakerAi.Realtime.OpenAI

{$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.MMSystem
{$ENDIF}
{$IFDEF ANDROID}
  , AndroidApi.JNI.Media, AndroidApi.JNIBridge, AndroidApi.Helpers, FMX.Helpers.Android, AndroidApi.JNI.JavaTypes
{$ENDIF}
  ;

{$IFNDEF MSWINDOWS}
// Outside Windows there is no WaveIn capture: we declare the types so that the
// public interface (DeviceID, GetWaveInDevices) is the same on all platforms.
type
  UINT = Cardinal;

const
  WAVE_MAPPER = UINT(-1);
{$ENDIF}

const
  DEFAULT_SAMPLE_RATE = 44100;
  DEFAULT_CHANNELS = 1;
  DEFAULT_BITS_PER_SAMPLE = 16;
  DEFAULT_BUFFER_DURATION_MS = 100;
  DEFAULT_CALIBRATION_DURATION_SEC = 3;
  DEFAULT_SILENCE_DURATION_MS = 700;
  DEFAULT_WAKE_WORD_DURATION_MS = 2500;
  DEFAULT_TRANSCRIPTION_INTERVAL_MS = 3000;
  DEFAULT_TRANSCRIPTION_MAX_WAIT_MS = 4000;
  DEFAULT_FRAGMENT_SPLIT_RATIO = 0.35;

type

  // List available Windows audio capture devices
  TWaveInDeviceInfo = record
    DeviceID: UINT;
    DeviceName: string;
  end;

  TRiffHeader = packed record
    ChunkID: array [0 .. 3] of AnsiChar;
    ChunkSize: LongWord;
    Format: array [0 .. 3] of AnsiChar;
  end;

  TFmtChunk = packed record
    Subchunk1ID: array [0 .. 3] of AnsiChar;
    Subchunk1Size: LongWord;
    AudioFormat: SmallInt;
    NumChannels: SmallInt;
    SampleRate: LongWord;
    ByteRate: LongWord;
    BlockAlign: SmallInt;
    BitsPerSample: SmallInt;
  end;

  TDataChunk = packed record
    Subchunk2ID: array [0 .. 3] of AnsiChar;
    Subchunk2Size: LongWord;
  end;

  TAiMonitorState = (msIdle, msRequestingPermission, msCalibrating, msMonitoring, msError);

  // IMPORTANT: The stream (aStream) is valid ONLY during the execution of the event.
  // If you need to retain the data, you must copy the stream to a local instance.
  // The stream will be automatically freed after the event returns.
  TAIVoiceMonitorOnChange = procedure(Sender: TObject; aUserSpeak: Boolean; aIsValidForIA: Boolean; aStream: TMemoryStream) of object;

  // IMPORTANT: The stream (aStream) is valid ONLY during the execution of the event.
  // If you need to retain the data, you must copy the stream to a local instance.
  // The stream will be automatically freed after the event returns.
  TSpeechEndEvent = procedure(Sender: TObject; aIsValidForIA: Boolean; aStream: TMemoryStream) of object;

  // IMPORTANT: The stream (aFragmentStream) is valid ONLY during the execution of the event.
  // If you need to retain the data, you must copy the stream to a local instance.
  // The stream will be automatically freed after the event returns.
  TTranscriptionFragmentEvent = procedure(Sender: TObject; aFragmentStream: TMemoryStream) of object;

  // IMPORTANT: The stream (aWakeWordStream) is valid ONLY during the execution of the event.
  // If you need to retain the data, you must copy the stream to a local instance.

  // TWakeWordCheckEvent = procedure(Sender: TObject; aWakeWordStream: TMemoryStream; var IsValid: Boolean) of object;
  // IsValid is removed from here to be moved to an asynchronous event
  TWakeWordCheckEvent = procedure(Sender: TObject; aWakeWordStream: TMemoryStream) of object;

  TAIVoiceMonitorOnCalibrated = procedure(Sender: TObject; const aNoiseLevel, aSensitivity, aStopSensitivity: Integer) of object;
  TAIVoiceMonitorOnUpdate = procedure(Sender: TObject; const aSoundLevel: Int64) of object;
  TAIVoiceMonitorOnError = procedure(Sender: TObject; const ErrorMessage: string) of object;

  TAIVoiceMonitor = class(TComponent)
  private
    FCS: TCriticalSection;
    FBuffer: TBytes;
    FArrBuf: TArray<Boolean>;
    FFileStream: TMemoryStream;

    FIsSpeaking: Boolean;
    FActive: Boolean;
    FMonitorState: TAiMonitorState;
    FSoundLevel: Int64;
    FInDestroy: Boolean;

    FSensitivity: Integer;
    FStopSensitivity: Integer;
    FCalibrationSamples: Integer;
    FCalibrationAccumulator: Int64;
    FCalibrationDurationSec: Integer;
    FWakeWordChecked: Boolean;
    FIsWakeWordValid: Boolean;
    FWakeWordDurationMs: Integer;
    FSilenceDuration: Integer;
    FSampleRate: Integer;
    FChannels: Integer;
    FBitsPerSample: Integer;
    FBufferSize: Integer;
    FSensitivityMultiplier: Double;
    FStopSensitivityMultiplier: Double;
    FMinSensitivity: Integer;
    FMinStopSensitivity: Integer;

    FTranscriptionStopwatch: TStopwatch;
    FTranscriptionIntervalMs: Integer;
    FTranscriptionMaxWaitMs: Integer;
    FWaitingForFragmentSplit: Boolean;
    FLastTranscriptionPosition: Int64;
    FPeakLevelInFragment: Int64;
    FFragmentSplitRatio: Double;

    FPreBuffer: TMemoryStream; // Pre-recording buffer
    FPreBufferDurationMs: Integer; // Pre-buffer duration (e.g. 500ms)
    FPreBufferMaxSize: Int64; // Maximum pre-buffer size

    FRealtimeSTT: TAiRealtimeBase; // Audio destination for Realtime STT (optional)
    FOnTranscriptionFragment: TTranscriptionFragmentEvent;
    FOnChangeState: TAIVoiceMonitorOnChange;
    FOnCalibrated: TAIVoiceMonitorOnCalibrated;
    FOnUpdate: TAIVoiceMonitorOnUpdate;
    FOnError: TAIVoiceMonitorOnError;
    FOnWakeWordCheck: TWakeWordCheckEvent;

    FNoiseLevel: Integer;
    FDeviceID: UINT;
    FWakeWordActive: Boolean;
    FWakeWord: String;
    FOnSpeechEnd: TSpeechEndEvent;
{$IFDEF MSWINDOWS}
    FhWaveIn: HWAVEIN;
    FWaveHdr: TWaveHdr;
{$ENDIF}
{$IFDEF ANDROID}
    FAudioRecord: JAudioRecord;
    FCaptureThread: TThread;
{$ENDIF}
    procedure SetActive(const Value: Boolean);
    procedure SetSilenceDuration(const Value: Integer);
    procedure SetRealtimeSTT(const Value: TAiRealtimeBase);
    procedure DoError(const aMessage: string);

    procedure StartCapture;
    procedure StopCapture;
    procedure UpdateAudioBuffers;
    procedure FireTranscriptionFragment;
    procedure SetBitsPerSample(const Value: Integer);
    procedure SetChannels(const Value: Integer);
    procedure SetSampleRate(const Value: Integer);
    procedure SetDeviceID(const Value: UINT);
    procedure SetWakeWordActive(const Value: Boolean);
    procedure SetWakeWord(const Value: String);
    procedure SetOnSpeechEnd(const Value: TSpeechEndEvent);
    procedure SetPreBufferDurationMs(const Value: Integer);

  protected
    procedure Loaded; override;
    procedure DoChangeState(aIsSpeaking: Boolean);
    procedure ConvertPCMToWAV(PCMStream, WAVStream: TMemoryStream);
    procedure ProcessAudioBuffer(const aBuffer: TBytes; aSize: Integer);
    procedure CalcSilencio;
    procedure UpdatePreBufferSize;
    function GetCurrentDeviceName: string;

{$IFDEF MSWINDOWS}
    procedure StartCaptureAudioWindows;
    procedure StopCaptureAudioWindows;
{$ENDIF}
{$IFDEF ANDROID}
    procedure StartCaptureAudioAndroid;
    procedure StopCaptureAudioAndroid;
    procedure AndroidCaptureLoop;
    procedure HandlePermissionRequest(Sender: TObject; const APermissions: TArray<string>; const AGrantResults: TArray<TPermissionStatus>);
{$ENDIF}
  public
    constructor Create(aOwner: TComponent); Override;
    destructor Destroy; override;
    class function GetWaveInDevices: TArray<TWaveInDeviceInfo>;
    procedure ConfirmWakeWord(AIsValid: Boolean);

    // Auxiliary functions for Spanish to detect word similarity
    class function LevenshteinDistance(const s, t: string): Integer;
    class function RemoveAccents(const Text: string): string;

    property Active: Boolean read FActive write SetActive;
    property IsSpeaking: Boolean read FIsSpeaking;
    property Sensitivity: Integer read FSensitivity;
    property StopSensitivity: Integer read FStopSensitivity;
    property State: TAiMonitorState read FMonitorState;
    property SoundLevel: Int64 read FSoundLevel;
    property NoiseLevel: Integer read FNoiseLevel;

  published
    property SilenceDuration: Integer read FSilenceDuration write SetSilenceDuration default DEFAULT_SILENCE_DURATION_MS;
    property SensitivityMultiplier: Double read FSensitivityMultiplier write FSensitivityMultiplier;
    property StopSensitivityMultiplier: Double read FStopSensitivityMultiplier write FStopSensitivityMultiplier;
    property MinSensitivity: Integer read FMinSensitivity write FMinSensitivity default 500;
    property MinStopSensitivity: Integer read FMinStopSensitivity write FMinStopSensitivity default 250;
    property WakeWordDurationMs: Integer read FWakeWordDurationMs write FWakeWordDurationMs default DEFAULT_WAKE_WORD_DURATION_MS;
    property TranscriptionIntervalMs: Integer read FTranscriptionIntervalMs write FTranscriptionIntervalMs default DEFAULT_TRANSCRIPTION_INTERVAL_MS;
    property TranscriptionMaxWaitMs: Integer read FTranscriptionMaxWaitMs write FTranscriptionMaxWaitMs default DEFAULT_TRANSCRIPTION_MAX_WAIT_MS;
    property FragmentSplitRatio: Double read FFragmentSplitRatio write FFragmentSplitRatio;
    property OnChangeState: TAIVoiceMonitorOnChange read FOnChangeState write FOnChangeState;
    property OnCalibrated: TAIVoiceMonitorOnCalibrated read FOnCalibrated write FOnCalibrated;
    property OnUpdate: TAIVoiceMonitorOnUpdate read FOnUpdate write FOnUpdate;
    property OnError: TAIVoiceMonitorOnError read FOnError write FOnError;
    property OnWakeWordCheck: TWakeWordCheckEvent read FOnWakeWordCheck write FOnWakeWordCheck;
    property OnSpeechEnd: TSpeechEndEvent read FOnSpeechEnd write SetOnSpeechEnd;
    property OnTranscriptionFragment: TTranscriptionFragmentEvent read FOnTranscriptionFragment write FOnTranscriptionFragment;
    property SampleRate: Integer read FSampleRate write SetSampleRate default DEFAULT_SAMPLE_RATE;
    property Channels: Integer read FChannels write SetChannels default DEFAULT_CHANNELS;
    property BitsPerSample: Integer read FBitsPerSample write SetBitsPerSample default DEFAULT_BITS_PER_SAMPLE;
    property WakeWord: String read FWakeWord write SetWakeWord;
    property WakeWordActive: Boolean read FWakeWordActive write SetWakeWordActive;
    property PreBufferDurationMs: Integer read FPreBufferDurationMs write SetPreBufferDurationMs default 500;
    property DeviceID: UINT read FDeviceID write SetDeviceID default WAVE_MAPPER;
    property CurrentDeviceName: string read GetCurrentDeviceName;
    // When assigned, each captured PCM buffer is forwarded to the Realtime STT component.
    // The Realtime component manages its own VAD (server_vad) and streaming transcription.
    property RealtimeSTT: TAiRealtimeBase read FRealtimeSTT write SetRealtimeSTT;
  end;

{$IFDEF MSWINDOWS}
{$ENDIF}

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAIVoiceMonitor]);
end;

{$IFDEF MSWINDOWS}

procedure AudioCallback(HWAVEIN: HWAVEIN; uMsg: UINT; dwInstance, dwParam1, dwParam2: DWORD_PTR); stdcall;
var
  Monitor: TAIVoiceMonitor;
  WaveHdr: PWAVEHDR;
begin
  if uMsg = WIM_DATA then
  begin
    Monitor := TAIVoiceMonitor(dwInstance);
    WaveHdr := PWAVEHDR(dwParam1);
    if Assigned(Monitor) and Assigned(WaveHdr) then
    begin
      Monitor.ProcessAudioBuffer(Monitor.FBuffer, WaveHdr^.dwBytesRecorded);
      if Monitor.Active then
        // waveInAddBuffer(HWAVEIN, @Monitor.FWaveHdr, SizeOf(TWaveHdr));
        waveInAddBuffer(HWAVEIN, WaveHdr, SizeOf(TWaveHdr));
    end;
  end;
end;

class function TAIVoiceMonitor.GetWaveInDevices: TArray<TWaveInDeviceInfo>;
var
  NumDevs, I: Integer;
  Caps: TWaveInCaps;
  // No need to declare DeviceInfo here, we will use direct array access
begin
  NumDevs := waveInGetNumDevs;

  // Reserve space for physical devices + 1 (the Default/Mapper)
  SetLength(Result, NumDevs + 1);

  // 1. Add the Default Device (WAVE_MAPPER) at position 0
  Result[0].DeviceID := WAVE_MAPPER;
  Result[0].DeviceName := 'System Default (WAVE_MAPPER)';

  // 2. Add the physical devices
  if NumDevs > 0 then
  begin
    for I := 0 to NumDevs - 1 do
    begin
      // Get capabilities. Note: actual device indices start at 0
      if waveInGetDevCaps(I, @Caps, SizeOf(Caps)) = MMSYSERR_NOERROR then
      begin
        // Store at position I + 1 of the result array
        Result[I + 1].DeviceID := I;
        Result[I + 1].DeviceName := Caps.szPname;
      end;
    end;
  end;
end;

{$ELSE}

class function TAIVoiceMonitor.GetWaveInDevices: TArray<TWaveInDeviceInfo>;
begin
  // No WaveIn API: only the default device
  SetLength(Result, 1);
  Result[0].DeviceID := WAVE_MAPPER;
  Result[0].DeviceName := 'System Default';
end;

{$ENDIF}
{ TAIVoiceMonitor }

constructor TAIVoiceMonitor.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);

  FCS := TCriticalSection.Create;
  FFileStream := TMemoryStream.Create;
  FPreBuffer := TMemoryStream.Create;
  FPreBufferDurationMs := 500;

  FInDestroy := False;
  FSampleRate := DEFAULT_SAMPLE_RATE;
  FChannels := DEFAULT_CHANNELS;
  FBitsPerSample := DEFAULT_BITS_PER_SAMPLE;
  FSensitivityMultiplier := 2.0;
  FStopSensitivityMultiplier := 1.5;
  FMinSensitivity := 500;
  FMinStopSensitivity := 250;
  FWakeWordDurationMs := DEFAULT_WAKE_WORD_DURATION_MS;
  FCalibrationDurationSec := DEFAULT_CALIBRATION_DURATION_SEC;
  FSilenceDuration := DEFAULT_SILENCE_DURATION_MS;

  FTranscriptionIntervalMs := DEFAULT_TRANSCRIPTION_INTERVAL_MS;
  FTranscriptionMaxWaitMs := DEFAULT_TRANSCRIPTION_MAX_WAIT_MS;
  FLastTranscriptionPosition := 0;
  FWaitingForFragmentSplit := False;
  FPeakLevelInFragment := 0;
  FFragmentSplitRatio := DEFAULT_FRAGMENT_SPLIT_RATIO;

  FNoiseLevel := 0;

  FIsSpeaking := False;
  FMonitorState := msIdle;
  FSensitivity := 2000;
  FStopSensitivity := 1000;

  FWakeWordActive := False;
  FWakeWord := 'andrea';

  FDeviceID := WAVE_MAPPER;
  UpdateAudioBuffers;
end;

destructor TAIVoiceMonitor.Destroy;
begin
  FInDestroy := True;
  Active := False;
  FFileStream.Free;
  FPreBuffer.Free;
  FCS.Free;
  inherited;
end;

procedure TAIVoiceMonitor.UpdateAudioBuffers;
var
  NewSilenceArraySize: Integer;
begin
  // Calculate audio buffer size
  FBufferSize := (FSampleRate * FChannels * (FBitsPerSample div 8) * DEFAULT_BUFFER_DURATION_MS) div 1000;

  // Validate that the buffer has a reasonable size
  if FBufferSize < 100 then
    raise EInvalidOperation.Create('Calculated buffer size is too small. Check audio parameters.');

  if FBufferSize > 1048576 then // 1MB
    raise EInvalidOperation.Create('Calculated buffer size is too large. Check audio parameters.');

  SetLength(FBuffer, FBufferSize);

  // Calculate the size of the silence detection array
  NewSilenceArraySize := FSilenceDuration div DEFAULT_BUFFER_DURATION_MS;

  // Minimum 2 buffers for detection
  if NewSilenceArraySize < 2 then
    NewSilenceArraySize := 2;

  SetLength(FArrBuf, NewSilenceArraySize);
end;

procedure TAIVoiceMonitor.UpdatePreBufferSize;
var
  BytesPerSecond: Int64;
begin
  // Calculate how many bytes FPreBufferDurationMs milliseconds occupy
  BytesPerSecond := FSampleRate * FChannels * (FBitsPerSample div 8);
  FPreBufferMaxSize := (BytesPerSecond * FPreBufferDurationMs) div 1000;
end;

class function TAIVoiceMonitor.LevenshteinDistance(const s, t: string): Integer;
var
  d: array of array of Integer;
  I, j, cost, lenS, lenT: Integer;
begin
  lenS := Length(s);
  lenT := Length(t);
  SetLength(d, lenS + 1, lenT + 1);
  for I := 0 to lenS do
    d[I, 0] := I;
  for j := 0 to lenT do
    d[0, j] := j;
  for I := 1 to lenS do
    for j := 1 to lenT do
    begin
      if LowerCase(s[I]) = LowerCase(t[j]) then
        cost := 0
      else
        cost := 1;
      d[I, j] := Min(Min(d[I - 1, j] + 1, d[I, j - 1] + 1), d[I - 1, j - 1] + cost);
    end;
  Result := d[lenS, lenT];
end;

procedure TAIVoiceMonitor.Loaded;
begin
  inherited;
  if FActive then
    StartCapture;
end;

procedure TAIVoiceMonitor.SetActive(const Value: Boolean);
begin
  if FActive = Value then
    Exit;

  FActive := Value;

  if Not FActive then
    StopCapture;

  if (csDesigning in ComponentState) or (csLoading in ComponentState) or FInDestroy then
    Exit;
  if FActive then
    StartCapture
  else
    StopCapture;
end;

procedure TAIVoiceMonitor.SetBitsPerSample(const Value: Integer);
begin
  if FBitsPerSample = Value then
    Exit;

  if Active then
    raise EInvalidOperation.Create('Cannot change BitsPerSample while monitor is active. ' + 'Set Active to False first.');

  if not(Value in [8, 16]) then
    raise EArgumentException.CreateFmt('Invalid bits per sample: %d. ' + 'Valid values are: 8 or 16 bits.', [Value]);

  FBitsPerSample := Value;
  UpdateAudioBuffers;
end;

procedure TAIVoiceMonitor.SetChannels(const Value: Integer);
begin
  if FChannels = Value then
    Exit;

  if Active then
    raise EInvalidOperation.Create('Cannot change Channels while monitor is active. ' + 'Set Active to False first.');

  if not(Value in [1, 2]) then
    raise EArgumentException.CreateFmt('Invalid number of channels: %d. ' + 'Valid values are: 1 (mono) or 2 (stereo).', [Value]);

  FChannels := Value;
  UpdateAudioBuffers;
end;

procedure TAIVoiceMonitor.SetDeviceID(const Value: UINT);
{$IFDEF MSWINDOWS}
var
  NumDevs: Integer;
  IsWaveMapper: Boolean;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  if FDeviceID = Value then
    Exit;

  if Active then
    raise EInvalidOperation.Create('Cannot change DeviceID while monitor is active. Set Active to False first.');

  // Robust check for WAVE_MAPPER
  IsWaveMapper := (Value = WAVE_MAPPER);

  if not IsWaveMapper then
  begin
    NumDevs := waveInGetNumDevs;
    // Validate that the ID is within the range of available physical devices
    if Integer(Value) >= NumDevs then
      raise EArgumentOutOfRangeException.CreateFmt('Invalid DeviceID: %d. Valid range is 0 to %d, or WAVE_MAPPER.', [Value, NumDevs - 1]);
  end;
{$ENDIF}
  FDeviceID := Value;
end;

procedure TAIVoiceMonitor.SetOnSpeechEnd(const Value: TSpeechEndEvent);
begin
  FOnSpeechEnd := Value;
end;

procedure TAIVoiceMonitor.SetPreBufferDurationMs(const Value: Integer);
begin
  if FPreBufferDurationMs = Value then
    Exit;

  if Active then
    raise EInvalidOperation.Create('Cannot change PreBufferDurationMs while monitor is active.');

  if (Value < 100) or (Value > 2000) then
    raise EArgumentOutOfRangeException.CreateFmt('PreBufferDurationMs must be between 100 and 2000 ms. Got: %d', [Value]);

  FPreBufferDurationMs := Value;
  UpdatePreBufferSize;
end;

procedure TAIVoiceMonitor.SetRealtimeSTT(const Value: TAiRealtimeBase);
begin
  FRealtimeSTT := Value;
  // Synchronize the sample rate so the internal resampler knows the input format
  if Assigned(FRealtimeSTT) then
    FRealtimeSTT.InputSampleRate := FSampleRate;
end;

procedure TAIVoiceMonitor.SetSampleRate(const Value: Integer);
const
  // Standard supported sample rates
  VALID_SAMPLE_RATES: array [0 .. 6] of Integer = (8000, // Telephony
    11025, // Low quality
    16000, // Telephony wideband / Whisper optimal
    22050, // Medium quality
    32000, // FM Radio
    44100, // CD Audio
    48000 // Professional audio / DVD
    );
var
  I: Integer;
  IsValid: Boolean;
  ValidRatesStr: string;
begin
  // If the value hasn't changed, do nothing
  if FSampleRate = Value then
    Exit;

  // Do not allow changes while the monitor is active
  if Active then
    raise EInvalidOperation.Create('Cannot change SampleRate while monitor is active. ' + 'Set Active to False first.');

  // Validate that it is a valid sample rate
  IsValid := False;
  for I := Low(VALID_SAMPLE_RATES) to High(VALID_SAMPLE_RATES) do
  begin
    if Value = VALID_SAMPLE_RATES[I] then
    begin
      IsValid := True;
      Break;
    end;
  end;

  // If not valid, raise an exception with useful information
  if not IsValid then
  begin
    // Build string with valid rates
    ValidRatesStr := '';
    for I := Low(VALID_SAMPLE_RATES) to High(VALID_SAMPLE_RATES) do
    begin
      if I > 0 then
        ValidRatesStr := ValidRatesStr + ', ';
      ValidRatesStr := ValidRatesStr + IntToStr(VALID_SAMPLE_RATES[I]);
    end;

    raise EArgumentException.CreateFmt('Invalid sample rate: %d Hz. ' + 'Valid rates are: %s Hz.', [Value, ValidRatesStr]);
  end;

  // Assign the new value
  FSampleRate := Value;

  // Recalculate buffers with the new sample rate
  UpdateAudioBuffers;
end;

procedure TAIVoiceMonitor.SetSilenceDuration(const Value: Integer);
begin
  FSilenceDuration := Max(300, Value);
end;

procedure TAIVoiceMonitor.SetWakeWordActive(const Value: Boolean);
begin
  FWakeWordActive := Value;
end;

procedure TAIVoiceMonitor.SetWakeWord(const Value: String);
begin
  FWakeWord := Value;
end;

procedure TAIVoiceMonitor.StartCapture;
begin
  UpdateAudioBuffers;
  FCS.Enter;
  try
    FMonitorState := msCalibrating;
    FCalibrationSamples := 0;
    FCalibrationAccumulator := 0;
    FNoiseLevel := 0;
    FIsSpeaking := False;
    FWakeWordChecked := False;
    // Without wake word checker, all speech is valid for the AI.
    // (previously it remained False and OnSpeechEnd/OnChangeState delivered the audio
    // with aIsValidForIA=False, which consumers discarded)
    FIsWakeWordValid := not Assigned(FOnWakeWordCheck);
    if Length(FArrBuf) > 0 then
      FillChar(FArrBuf[0], Length(FArrBuf) * SizeOf(Boolean), 0);
    FFileStream.Clear;
  finally
    FCS.Leave;
  end;
{$IFDEF MSWINDOWS}
  StartCaptureAudioWindows;
{$ENDIF}
{$IFDEF ANDROID}
  FMonitorState := msRequestingPermission;
  PermissionsService.RequestPermissions([TPermission.RecordAudio], HandlePermissionRequest);
{$ENDIF}
end;

procedure TAIVoiceMonitor.StopCapture;
begin
{$IFDEF MSWINDOWS}
  StopCaptureAudioWindows;
{$ENDIF}
{$IFDEF ANDROID}
  StopCaptureAudioAndroid;
{$ENDIF}
  FCS.Enter;
  try
    if FIsSpeaking then
    begin
      FIsSpeaking := False;
      TThread.Queue(nil,
        procedure
        begin
          if not(csDestroying in ComponentState) then
            DoChangeState(False);
        end);
    end;
    FMonitorState := msIdle;
  finally
    FCS.Leave;
  end;
end;

procedure TAIVoiceMonitor.ProcessAudioBuffer(const aBuffer: TBytes; aSize: Integer);
var
  Sum, CurrentLevel, BytesPerSecond, CurrentDurationMs: Int64;
  NumSamples, I, TotalCalibrationSamplesNeeded, NoiseLevel: Integer;
  SampleValue: SmallInt;
  isSilentMoment, isWaitTooLong: Boolean;
  TempBuffer: TMemoryStream;
begin
  if aSize = 0 then
    Exit;

  Sum := 0;
  NumSamples := aSize div (FBitsPerSample div 8);

  if NumSamples = 0 then
    Exit;

  // Forward raw audio to the Realtime STT component if connected.
  // Sent before any processing: the server VAD handles speech/silence detection on the provider side.
  if Assigned(FRealtimeSTT) and FRealtimeSTT.IsConnected then
    FRealtimeSTT.SendAudioChunk(Copy(aBuffer, 0, aSize));

  // Calculate current audio level
  for I := 0 to NumSamples - 1 do
  begin
    SampleValue := PSmallInt(@aBuffer[I * 2])^;
    Sum := Sum + Abs(SampleValue);
  end;

  CurrentLevel := Sum div NumSamples;

  FCS.Enter;
  try
    FSoundLevel := CurrentLevel;

    case FMonitorState of
      msCalibrating:
        begin
          FCalibrationAccumulator := FCalibrationAccumulator + CurrentLevel;
          Inc(FCalibrationSamples);
          TotalCalibrationSamplesNeeded := (FCalibrationDurationSec * 1000) div DEFAULT_BUFFER_DURATION_MS;

          if FCalibrationSamples >= TotalCalibrationSamplesNeeded then
          begin
            if FCalibrationSamples > 0 then
            begin
              NoiseLevel := FCalibrationAccumulator div FCalibrationSamples;
              FNoiseLevel := NoiseLevel;
              FSensitivity := Max(FMinSensitivity, Round(NoiseLevel * FSensitivityMultiplier));
              FStopSensitivity := Max(FMinStopSensitivity, Round(NoiseLevel * FStopSensitivityMultiplier));

              if FStopSensitivity >= FSensitivity then
                FStopSensitivity := FSensitivity - 1;
            end
            else
            begin
              FNoiseLevel := 0;
              FSensitivity := 1500;
              FStopSensitivity := 750;
            end;

            FMonitorState := msMonitoring;

            TThread.Queue(nil,
              procedure
              begin
                if Assigned(FOnCalibrated) then
                  FOnCalibrated(Self, NoiseLevel, FSensitivity, FStopSensitivity);
              end);
          end;
        end;

      msMonitoring:
        begin
          // *** PRE-BUFFER MANAGEMENT ***
          if not FIsSpeaking then
          begin
            // While NOT speaking, accumulate audio in the pre-buffer
            FPreBuffer.WriteBuffer(aBuffer, aSize);

            // If the pre-buffer exceeds the maximum size, keep only the latest data
            if FPreBuffer.Size > FPreBufferMaxSize then
            begin
              // Create temporary buffer to keep only the last FPreBufferMaxSize bytes
              TempBuffer := TMemoryStream.Create;
              try
                // Position at the point where the last N bytes start
                FPreBuffer.Position := FPreBuffer.Size - FPreBufferMaxSize;

                // Copy only the last bytes to the temporary buffer
                TempBuffer.CopyFrom(FPreBuffer, FPreBufferMaxSize);

                // Clear the pre-buffer and copy back the reduced content
                FPreBuffer.Clear;
                TempBuffer.Position := 0;
                FPreBuffer.CopyFrom(TempBuffer, 0);
              finally
                TempBuffer.Free;
              end;
            end;
          end
          else
          begin
            // We are already speaking, save directly to FFileStream
            FFileStream.WriteBuffer(aBuffer, aSize);

            // --- FRAGMENTATION FOR STREAMING TRANSCRIPTION ---
            if Assigned(FOnTranscriptionFragment) then
            begin
              // Update the peak level in the current fragment
              if CurrentLevel > FPeakLevelInFragment then
                FPeakLevelInFragment := CurrentLevel;

              // Check if the minimum interval to send a fragment has passed
              if not FWaitingForFragmentSplit and (FTranscriptionStopwatch.ElapsedMilliseconds >= FTranscriptionIntervalMs) then
                FWaitingForFragmentSplit := True;

              // If waiting to split, look for an appropriate moment
              if FWaitingForFragmentSplit then
              begin
                // Relative silent moment: current level dropped significantly compared to the peak
                isSilentMoment := (FPeakLevelInFragment > FSensitivity) and (CurrentLevel < (FPeakLevelInFragment * FFragmentSplitRatio));

                // Maximum wait time exceeded
                isWaitTooLong := FTranscriptionStopwatch.ElapsedMilliseconds >= FTranscriptionMaxWaitMs;

                // Send fragment if we found a silent moment or waited too long
                if isSilentMoment or isWaitTooLong then
                begin
                  FireTranscriptionFragment;
                  FWaitingForFragmentSplit := False;
                end;
              end;
            end;

            // --- WAKE WORD CHECK ---
            if not FWakeWordChecked and Assigned(FOnWakeWordCheck) then
            begin
              BytesPerSecond := FSampleRate * FChannels * (FBitsPerSample div 8);
              CurrentDurationMs := 0;

              if BytesPerSecond > 0 then
                CurrentDurationMs := (FFileStream.Size * 1000) div BytesPerSecond;

              // If we already have enough audio to verify the wake word
              if CurrentDurationMs >= FWakeWordDurationMs then
              begin
                FWakeWordChecked := True;

                // Execute verification in async task to not block capture
                {
                  TTask.Run(
                  procedure
                  var
                  WakeStreamPCM, WakeStreamWAV: TMemoryStream;
                  FragmentSize: Int64;
                  IsValid: Boolean;
                  begin
                  WakeStreamPCM := TMemoryStream.Create;
                  try
                  // Extract the wake word fragment from the beginning of the audio
                  FCS.Enter;
                  try
                  FFileStream.Position := 0;
                  FragmentSize := (FWakeWordDurationMs * BytesPerSecond) div 1000;

                  if FragmentSize > FFileStream.Size then
                  FragmentSize := FFileStream.Size;

                  WakeStreamPCM.CopyFrom(FFileStream, FragmentSize);
                  FFileStream.Position := FFileStream.Size;
                  finally
                  FCS.Leave;
                  end;

                  // Convert to WAV to send to the checker
                  WakeStreamWAV := TMemoryStream.Create;
                  try
                  ConvertPCMToWAV(WakeStreamPCM, WakeStreamWAV);
                  IsValid := False;

                  // Only call the event if wake word is active
                  if Assigned(FOnWakeWordCheck) and FWakeWordActive then
                  FOnWakeWordCheck(Self, WakeStreamWAV, IsValid);
                  finally
                  WakeStreamWAV.Free;
                  end;


                  // Save the validation result
                  FCS.Enter;
                  try
                  FIsWakeWordValid := IsValid;
                  finally
                  FCS.Leave;
                  end;
                  finally
                  WakeStreamPCM.Free;
                  end;
                  end);
                }

                TTask.Run(
                  procedure
                  var
                    WakeStreamPCM, WakeStreamWAV: TMemoryStream;
                    FragmentSize: Int64;
                  begin
                    WakeStreamPCM := TMemoryStream.Create;
                    try
                      FCS.Enter;
                      try
                        FFileStream.Position := 0;
                        FragmentSize := (FWakeWordDurationMs * BytesPerSecond) div 1000;
                        if FragmentSize > FFileStream.Size then
                          FragmentSize := FFileStream.Size;
                        WakeStreamPCM.CopyFrom(FFileStream, FragmentSize);
                        FFileStream.Position := FFileStream.Size;
                      finally
                        FCS.Leave;
                      end;

                      WakeStreamWAV := TMemoryStream.Create;
                      try
                        ConvertPCMToWAV(WakeStreamPCM, WakeStreamWAV);
                        // TRIGGER ASYNCHRONOUS EVENT (We don't wait for the result here)
                        if Assigned(FOnWakeWordCheck) and FWakeWordActive then
                          FOnWakeWordCheck(Self, WakeStreamWAV);
                      finally
                        WakeStreamWAV.Free;
                      end;
                    finally
                      WakeStreamPCM.Free;
                    end;
                  end);

              end;

            end;
          end;

          // --- SILENCE DETECTION BUFFER UPDATE ---
          if Length(FArrBuf) > 0 then
          begin
            // Shift array one position to the left
            for I := 0 to High(FArrBuf) - 1 do
              FArrBuf[I] := FArrBuf[I + 1];

            // Add new measurement at the end
            if FIsSpeaking then
              FArrBuf[High(FArrBuf)] := (CurrentLevel > FStopSensitivity)
            else
              FArrBuf[High(FArrBuf)] := (CurrentLevel > FSensitivity);
          end;
        end;
    end;
  finally
    FCS.Leave;
  end;

  // --- NOTIFY AUDIO LEVEL TO OnUpdate EVENT ---
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnUpdate) then
        FOnUpdate(Self, CurrentLevel);
    end);

  // --- CALCULATE SILENCE DETECTION ---
  if FMonitorState = msMonitoring then
    CalcSilencio;
end;

class function TAIVoiceMonitor.RemoveAccents(const Text: string): string;
const
  Accented = 'áéíóúàèìòùâêîôûãõäëïöüñÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÄËÏÖÜÑ';
  Normal = 'aeiouaeiouaeiouaeiounAEIOUAEIOUAEIOUAEIOUN';
var
  I, p: Integer;
begin
  Result := Text;
  for I := 1 to Length(Result) do
  begin
    p := Pos(Result[I], Accented);
    if p > 0 then
      Result[I] := Normal[p];
  end;
end;

procedure TAIVoiceMonitor.CalcSilencio;
var
  I: Integer;
  AllFalse, PrevState, NewState: Boolean;
begin
  FCS.Enter;
  try
    PrevState := FIsSpeaking;
    NewState := FIsSpeaking;
    if (not FIsSpeaking) and (Length(FArrBuf) >= 2) and (FArrBuf[High(FArrBuf) - 1]) and (FArrBuf[High(FArrBuf)]) then
      NewState := True
    else if FIsSpeaking then
    begin
      AllFalse := True;
      for I := 0 to High(FArrBuf) do
      begin
        if FArrBuf[I] then
        begin
          AllFalse := False;
          Break;
        end;
      end;
      if AllFalse then
        NewState := False;
    end;
    if NewState <> PrevState then
    begin
      FIsSpeaking := NewState;
      TThread.Queue(nil,
        procedure
        begin
          DoChangeState(FIsSpeaking);
        end);
    end;
  finally
    FCS.Leave;
  end;
end;

procedure TAIVoiceMonitor.DoChangeState(aIsSpeaking: Boolean);
var
  WAVStream: TMemoryStream;
begin
  if aIsSpeaking then
  begin
    FCS.Enter;
    try
      FWakeWordChecked := False;
      FIsWakeWordValid := not Assigned(FOnWakeWordCheck);  // without wake word: valid
      FFileStream.Clear;

      // *** COPY PRE-BUFFER TO THE BEGINNING OF FILESTREAM ***
      if FPreBuffer.Size > 0 then
      begin
        FPreBuffer.Position := 0;
        FFileStream.CopyFrom(FPreBuffer, 0);
        // *** CLEAR THE PRE-BUFFER AFTER USING IT ***
        FPreBuffer.Clear;
      end;

      FLastTranscriptionPosition := 0;
      FWaitingForFragmentSplit := False;
      FPeakLevelInFragment := 0;
      FTranscriptionStopwatch.Reset;
      FTranscriptionStopwatch.Start;
    finally
      FCS.Leave;
    end;

    if Assigned(FOnChangeState) then
      FOnChangeState(Self, True, False, nil);
  end
  else
  begin
    FTranscriptionStopwatch.Stop;
    FTranscriptionStopwatch.Reset;

    if Assigned(FOnTranscriptionFragment) then
      FireTranscriptionFragment;

    FWaitingForFragmentSplit := False;
    FPeakLevelInFragment := 0;

    FCS.Enter;
    try
      FPreBuffer.Clear;
    finally
      FCS.Leave;
    end;

    WAVStream := TMemoryStream.Create;
    Try
      FCS.Enter;
      try
        ConvertPCMToWAV(FFileStream, WAVStream);
      finally
        FCS.Leave;
      end;

      WAVStream.Position := 0;

      if Assigned(FOnSpeechEnd) then
        FOnSpeechEnd(Self, FIsWakeWordValid, WAVStream);

      if Assigned(FOnChangeState) then
        FOnChangeState(Self, False, FIsWakeWordValid, WAVStream)
    Finally
      WAVStream.Free;
    End;
  end;
end;

procedure TAIVoiceMonitor.FireTranscriptionFragment;
var
  FragmentPCM, FragmentWAV: TMemoryStream;
  FragmentSize: Int64;
  PeakLevel: Int64;
begin
  // Acquire the peak level of the current fragment safely
  FCS.Enter;
  try
    PeakLevel := FPeakLevelInFragment;
  finally
    FCS.Leave;
  end;

  // --- FRAGMENT VALIDATION ---
  // If the sound peak in this fragment did not exceed the sensitivity,
  // we consider it silence and do not send it to the AI.
  if PeakLevel < FSensitivity then
  begin
    // The fragment is silence. We discard it, but must update
    // the position and reset the counters for the next fragment.
    FCS.Enter;
    try
      // Mark the silent audio as 'processed' so it is not rechecked
      FLastTranscriptionPosition := FFileStream.Size;
    finally
      FCS.Leave;
    end;

    // Reset everything for the next detection cycle.
    FTranscriptionStopwatch.Reset;
    FTranscriptionStopwatch.Start;
    FPeakLevelInFragment := 0;
    Exit; // Exit the procedure, nothing to send.
  end;

  // --- FRAGMENT EXTRACTION ---
  // If we get here, the fragment contains significant audio.
  // Proceed to extract and send it.
  FragmentPCM := TMemoryStream.Create;
  try
    FCS.Enter;
    try
      // Safety check: is there new data to process?
      if FFileStream.Size <= FLastTranscriptionPosition then
        Exit;

      // Calculate size of the new fragment
      FragmentSize := FFileStream.Size - FLastTranscriptionPosition;

      // Copy the fragment from the last processed position
      FFileStream.Position := FLastTranscriptionPosition;
      FragmentPCM.CopyFrom(FFileStream, FragmentSize);

      // Update the position for the next fragment
      FLastTranscriptionPosition := FFileStream.Size;
    finally
      FCS.Leave;
    end;

    // Reset counters for the *next* fragment.
    FTranscriptionStopwatch.Reset;
    FTranscriptionStopwatch.Start;
    FPeakLevelInFragment := 0;

    // If for some reason the fragment is empty, do not continue.
    if FragmentPCM.Size = 0 then
      Exit;

    // --- CONVERSION TO WAV AND SENDING TO EVENT ---
    FragmentWAV := TMemoryStream.Create;
    try
      // Convert PCM to WAV format
      ConvertPCMToWAV(FragmentPCM, FragmentWAV);
      FragmentWAV.Position := 0;

      // Send to main thread so it triggers the event
      // IMPORTANT: The event handler MUST copy the stream if it needs
      // to retain the data, as it will be freed immediately after the event
      TThread.Queue(nil,
        procedure
        var
          StreamToFree: TMemoryStream;
        begin
          StreamToFree := FragmentWAV;
          try
            // Only trigger the event if the component is not being destroyed
            if not(csDestroying in ComponentState) and Assigned(FOnTranscriptionFragment) then
              FOnTranscriptionFragment(Self, FragmentWAV);
          finally
            // Always free the stream after the event
            StreamToFree.Free;
          end;
        end);
    except
      // If there is an error in conversion, free the WAV stream
      FragmentWAV.Free;
      raise;
    end;
  finally
    // Always free the PCM stream
    FragmentPCM.Free;
  end;
end;

function TAIVoiceMonitor.GetCurrentDeviceName: string;
{$IFDEF MSWINDOWS}
var
  Caps: TWaveInCaps;
  IsWaveMapper: Boolean;
{$ENDIF}
begin
  Result := 'Unknown Device';

{$IFDEF MSWINDOWS}
  // Check if it's WAVE_MAPPER
  IsWaveMapper := (FDeviceID = UINT(-1)) or (Integer(FDeviceID) = -1) or (FDeviceID = $FFFFFFFF);

  if IsWaveMapper then
  begin
    Result := 'Default Device (WAVE_MAPPER)';
    Exit;
  end;

  if waveInGetDevCaps(FDeviceID, @Caps, SizeOf(Caps)) = MMSYSERR_NOERROR then
    Result := Caps.szPname
  else
    Result := Format('Device ID %d (Error getting info)', [FDeviceID]);
{$ENDIF}
end;

procedure TAIVoiceMonitor.DoError(const aMessage: string);
begin
  FMonitorState := msError;
  StopCapture;
  FActive := False;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(Self, aMessage);
    end);
end;

procedure TAIVoiceMonitor.ConfirmWakeWord(AIsValid: Boolean);
begin
  FCS.Enter;
  try
    FIsWakeWordValid := AIsValid;
  finally
    FCS.Leave;
  end;

  // It is possible that speech ended before the confirmation, so
  // in the future we can implement a routine to trigger an event with the audio here.
  // Optional: If speech already ended but we were waiting for confirmation,
  // you could trigger an extra event here if needed.
end;

procedure TAIVoiceMonitor.ConvertPCMToWAV(PCMStream, WAVStream: TMemoryStream);
var
  RiffHeader: TRiffHeader;
  FmtChunk: TFmtChunk;
  DataChunk: TDataChunk;
begin
  // Parameter validation
  if not Assigned(PCMStream) then
    raise EArgumentNilException.Create('PCMStream cannot be nil');
  if not Assigned(WAVStream) then
    raise EArgumentNilException.Create('WAVStream cannot be nil');
  if PCMStream.Size = 0 then
    raise EArgumentException.Create('PCMStream cannot be empty');

  // Prepare streams
  PCMStream.Position := 0;
  WAVStream.Clear;

  // Build FMT chunk (24 bytes total: 8 header + 16 data)
  FmtChunk.Subchunk1ID := 'fmt ';
  FmtChunk.Subchunk1Size := 16; // Size of fmt chunk data (without header)
  FmtChunk.AudioFormat := 1; // Uncompressed PCM
  FmtChunk.NumChannels := FChannels;
  FmtChunk.SampleRate := FSampleRate;
  FmtChunk.BitsPerSample := FBitsPerSample;
  FmtChunk.BlockAlign := FChannels * (FBitsPerSample div 8);
  FmtChunk.ByteRate := FSampleRate * FmtChunk.BlockAlign;

  // Build DATA chunk (8 bytes header + data)
  DataChunk.Subchunk2ID := 'data';
  DataChunk.Subchunk2Size := PCMStream.Size;

  // Build RIFF header
  RiffHeader.ChunkID := 'RIFF';
  RiffHeader.Format := 'WAVE';

  // ChunkSize = total file size - 8 bytes (ChunkID + ChunkSize)
  // = 4 (WAVE) + 24 (full fmt chunk) + 8 (data header) + PCM data
  // = 36 + PCM data
  RiffHeader.ChunkSize := 36 + PCMStream.Size;

  // Write all chunks in order
  WAVStream.WriteBuffer(RiffHeader, SizeOf(RiffHeader));
  WAVStream.WriteBuffer(FmtChunk, SizeOf(FmtChunk));
  WAVStream.WriteBuffer(DataChunk, SizeOf(DataChunk));
  WAVStream.CopyFrom(PCMStream, 0);

  // Position at beginning for later reading
  WAVStream.Position := 0;
end;

{$IFDEF MSWINDOWS}
{
  procedure TAIVoiceMonitor.StartCaptureAudioWindows;
  var
  WaveFormat: TWaveFormatEx;
  Res: MMRESULT;
  begin
  if not FActive then
  Exit;
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := FChannels;
  WaveFormat.nSamplesPerSec := FSampleRate;
  WaveFormat.wBitsPerSample := FBitsPerSample;
  WaveFormat.nBlockAlign := FChannels * (WaveFormat.wBitsPerSample div 8);
  WaveFormat.nAvgBytesPerSec := FSampleRate * WaveFormat.nBlockAlign;
  WaveFormat.cbSize := 0;
  // Res := waveInOpen(@FhWaveIn, WAVE_MAPPER, @WaveFormat, DWORD_PTR(@AudioCallback), DWORD_PTR(Self), CALLBACK_FUNCTION);
  Res := waveInOpen(@FhWaveIn, FDeviceID, @WaveFormat, DWORD_PTR(@AudioCallback), DWORD_PTR(Self), CALLBACK_FUNCTION);
  if Res <> MMSYSERR_NOERROR then
  begin
  DoError('Error opening audio device: ' + IntToStr(Res));
  Exit;
  end;
  FillChar(FWaveHdr, SizeOf(FWaveHdr), 0);
  FWaveHdr.lpData := @FBuffer[0];
  FWaveHdr.dwBufferLength := FBufferSize;
  waveInPrepareHeader(FhWaveIn, @FWaveHdr, SizeOf(FWaveHdr));
  waveInAddBuffer(FhWaveIn, @FWaveHdr, SizeOf(FWaveHdr));
  Res := waveInStart(FhWaveIn);
  if Res <> MMSYSERR_NOERROR then
  begin
  waveInClose(FhWaveIn);
  DoError('Error starting audio capture: ' + IntToStr(Res));
  end;
  end;
}

procedure TAIVoiceMonitor.StartCaptureAudioWindows;
var
  WaveFormat: TWaveFormatEx;
  Res: MMRESULT;
begin
  if not FActive then
    Exit;

  // 1. Audio format configuration (PCM)
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := FChannels;
  WaveFormat.nSamplesPerSec := FSampleRate;
  WaveFormat.wBitsPerSample := FBitsPerSample;
  WaveFormat.nBlockAlign := FChannels * (WaveFormat.wBitsPerSample div 8);
  WaveFormat.nAvgBytesPerSec := FSampleRate * WaveFormat.nBlockAlign;
  WaveFormat.cbSize := 0;

  // 2. Open the device
  // FDeviceID must contain the ID of the specific device (0, 1, 2...)
  // Or the WAVE_MAPPER value ($FFFFFFFF) for the default device.

  // FDeviceID := WAVE_MAPPER;

  Res := waveInOpen(@FhWaveIn, FDeviceID, @WaveFormat, DWORD_PTR(@AudioCallback), DWORD_PTR(Self), CALLBACK_FUNCTION);

  if Res <> MMSYSERR_NOERROR then
  begin
    FhWaveIn := 0;
    DoError('Error opening audio device (Code: ' + IntToStr(Res) + ').');
    Exit;
  end;

  // 3. Prepare the header structure
  FillChar(FWaveHdr, SizeOf(FWaveHdr), 0);
  FWaveHdr.lpData := @FBuffer[0]; // Pointer to the byte array
  FWaveHdr.dwBufferLength := FBufferSize; // Buffer size
  FWaveHdr.dwFlags := 0;

  // 4. Prepare the header (PrepareHeader)
  Res := waveInPrepareHeader(FhWaveIn, @FWaveHdr, SizeOf(TWaveHdr));
  if Res <> MMSYSERR_NOERROR then
  begin
    // If it fails, close the device before exiting
    waveInClose(FhWaveIn);
    FhWaveIn := 0;
    DoError('Error preparing audio header: ' + IntToStr(Res));
    Exit;
  end;

  // 5. Add the buffer to the recording queue
  Res := waveInAddBuffer(FhWaveIn, @FWaveHdr, SizeOf(TWaveHdr));
  if Res <> MMSYSERR_NOERROR then
  begin
    // If it fails, unprepare and close
    waveInUnprepareHeader(FhWaveIn, @FWaveHdr, SizeOf(TWaveHdr));
    waveInClose(FhWaveIn);
    FhWaveIn := 0;
    DoError('Error adding audio buffer: ' + IntToStr(Res));
    Exit;
  end;

  // 6. Start recording
  Res := waveInStart(FhWaveIn);
  if Res <> MMSYSERR_NOERROR then
  begin
    // Full cleanup on critical error starting
    waveInReset(FhWaveIn);
    waveInUnprepareHeader(FhWaveIn, @FWaveHdr, SizeOf(TWaveHdr));
    waveInClose(FhWaveIn);
    FhWaveIn := 0;
    DoError('Error starting audio capture: ' + IntToStr(Res));
  end;
end;

procedure TAIVoiceMonitor.StopCaptureAudioWindows;
begin
  if FhWaveIn <> 0 then
  begin
    waveInStop(FhWaveIn);
    waveInReset(FhWaveIn);
    waveInUnprepareHeader(FhWaveIn, @FWaveHdr, SizeOf(FWaveHdr));
    waveInClose(FhWaveIn);
    FhWaveIn := 0;
  end;
end;
{$ENDIF}
{$IFDEF ANDROID}

procedure TAIVoiceMonitor.HandlePermissionRequest(Sender: TObject; const APermissions: TArray<string>; const AGrantResults: TArray<TPermissionStatus>);
begin
  if (Length(AGrantResults) > 0) and (AGrantResults[0] = TPermissionStatus.Granted) then
    StartCaptureAudioAndroid
  else
    DoError('Permission to record audio denied.');
end;

procedure TAIVoiceMonitor.StartCaptureAudioAndroid;
var
  AudioSource, ChannelConfig, AudioFormat, MinBufferSize: Integer;
begin
  if not FActive then
    Exit;
  try
    AudioSource := TJMediaRecorder_AudioSource.JavaClass.MIC;
    ChannelConfig := TJAudioFormat.JavaClass.CHANNEL_IN_MONO;
    AudioFormat := TJAudioFormat.JavaClass.ENCODING_PCM_16BIT;
    MinBufferSize := TJAudioRecord.JavaClass.getMinBufferSize(FSampleRate, ChannelConfig, AudioFormat);
    if FBufferSize < MinBufferSize then
      FBufferSize := MinBufferSize;
    SetLength(FBuffer, FBufferSize);
    FAudioRecord := TJAudioRecord.JavaClass.init(AudioSource, FSampleRate, ChannelConfig, AudioFormat, FBufferSize);
    if FAudioRecord.getState <> TJAudioRecord.JavaClass.STATE_INITIALIZED then
    begin
      DoError('Could not initialize AudioRecord.');
      Exit;
    end;
    if Assigned(FCaptureThread) then
    begin
      FCaptureThread.Terminate;
      FCaptureThread.WaitFor;
      FCaptureThread := nil;
    end;
    FCaptureThread := TThread.CreateAnonymousThread(AndroidCaptureLoop);
    FCaptureThread.FreeOnTerminate := True;
    FAudioRecord.startRecording;
    FCaptureThread.Start;
  except
    on E: Exception do
      DoError('Exception starting capture on Android: ' + E.Message);
  end;
end;

procedure TAIVoiceMonitor.StopCaptureAudioAndroid;
var
  LThread: TThread;
begin
  if Assigned(FAudioRecord) then
  begin
    if FAudioRecord.getRecordingState = TJAudioRecord.JavaClass.RECORDSTATE_RECORDING then
      FAudioRecord.Stop;
    if FAudioRecord.getState = TJAudioRecord.JavaClass.STATE_INITIALIZED then
      FAudioRecord.release;
    FAudioRecord := nil;
  end;

  LThread := FCaptureThread;
  if Assigned(LThread) then
  begin
    LThread.Terminate;
    FCaptureThread := nil;
  end;
end;

procedure TAIVoiceMonitor.AndroidCaptureLoop;
var
  JBuffer: TJavaArray<Byte>;
  BytesRead: Integer;
  ErrorCount: Integer;
  ConsecutiveErrors: Integer;
  LastErrorCode: Integer;
begin
  JBuffer := TJavaArray<Byte>.Create(FBufferSize);
  ErrorCount := 0;
  ConsecutiveErrors := 0;
  LastErrorCode := 0;

  try
    while not TThread.CheckTerminated do
    begin
      // Check that AudioRecord is still valid
      if not Assigned(FAudioRecord) then
      begin
        TThread.Queue(nil,
          procedure
          begin
            DoError('AudioRecord instance was released unexpectedly.');
          end);
        Break;
      end;

      // Check that it is in recording state
      if FAudioRecord.getRecordingState <> TJAudioRecord.JavaClass.RECORDSTATE_RECORDING then
      begin
        TThread.Queue(nil,
          procedure
          begin
            DoError('AudioRecord is not in recording state.');
          end);
        Break;
      end;

      try
        // Attempt to read data from the audio buffer
        BytesRead := FAudioRecord.read(JBuffer, 0, FBufferSize);

        // --- CASE 1: Successful read ---
        if BytesRead > 0 then
        begin
          // Reset error counters on successful read
          ErrorCount := 0;
          ConsecutiveErrors := 0;
          LastErrorCode := 0;

          // Copy data from Java buffer to native buffer
          JNI.GetByteArrayRegion(JBuffer.GetObjectID, 0, BytesRead, PByte(FBuffer));

          // Process the audio buffer
          ProcessAudioBuffer(FBuffer, BytesRead);
        end
        // --- CASE 2: Read error ---
        else if BytesRead < 0 then
        begin
          Inc(ErrorCount);
          Inc(ConsecutiveErrors);
          LastErrorCode := BytesRead;

          // Determine the type of error according to the code
          case BytesRead of
            TJAudioRecord.JavaClass.ERROR_INVALID_OPERATION:
              begin
                // Critical error: AudioRecord in invalid state
                TThread.Queue(nil,
                  procedure
                  begin
                    DoError('AudioRecord ERROR_INVALID_OPERATION. Recording stopped.');
                  end);
                Break;
              end;

            TJAudioRecord.JavaClass.ERROR_BAD_VALUE:
              begin
                // Invalid parameters
                TThread.Queue(nil,
                  procedure
                  begin
                    DoError('AudioRecord ERROR_BAD_VALUE. Invalid parameters.');
                  end);
                Break;
              end;

            TJAudioRecord.JavaClass.ERROR_DEAD_OBJECT:
              begin
                // AudioRecord died
                TThread.Queue(nil,
                  procedure
                  begin
                    DoError('AudioRecord ERROR_DEAD_OBJECT. Recording stopped.');
                  end);
                Break;
              end;

            TJAudioRecord.JavaClass.ERROR:
              begin
                // Generic error - may be transient
                if ConsecutiveErrors >= 10 then
                begin
                  // Too many consecutive errors
                  TThread.Queue(nil,
                    procedure
                    begin
                      DoError(Format('Persistent AudioRecord ERROR after %d attempts. Recording stopped.', [ConsecutiveErrors]));
                    end);
                  Break;
                end
                else
                begin
                  // Transient error, wait before retrying
                  Sleep(50);
                end;
              end;

          else
            // Unknown error code
            if ConsecutiveErrors >= 10 then
            begin
              TThread.Queue(nil,
                procedure
                begin
                  DoError(Format('Unknown AudioRecord error code: %d after %d attempts. Recording stopped.', [BytesRead, ConsecutiveErrors]));
                end);
              Break;
            end
            else
            begin
              // Wait before retrying
              Sleep(50);
            end;
          end;

          // Diagnostic log every 5 errors (optional)
          if (ErrorCount mod 5 = 0) and (ErrorCount > 0) then
          begin
            TThread.Queue(nil,
              procedure
              begin
                if Assigned(FOnError) then
                  FOnError(Self, Format('AudioRecord warning: %d errors detected (last code: %d)', [ErrorCount, LastErrorCode]));
              end);
          end;
        end
        // --- CASE 3: Nothing read (BytesRead = 0) ---
        else
        begin
          // BytesRead = 0 is rare but not necessarily an error
          Inc(ConsecutiveErrors);

          if ConsecutiveErrors >= 20 then
          begin
            TThread.Queue(nil,
              procedure
              begin
                DoError('AudioRecord returned 0 bytes too many times. Recording stopped.');
              end);
            Break;
          end;

          // Small pause before retrying
          Sleep(10);
        end;

      except
        on E: Exception do
        begin
          // Exception in processing
          Inc(ErrorCount);
          Inc(ConsecutiveErrors);

          if ConsecutiveErrors >= 5 then
          begin
            // Too many exceptions, abort
            TThread.Queue(nil,
              procedure
              begin
                DoError(Format('Critical exception in audio capture loop: %s. Recording stopped.', [E.Message]));
              end);
            Break;
          end
          else
          begin
            // Log and continue
            TThread.Queue(nil,
              procedure
              begin
                if Assigned(FOnError) then
                  FOnError(Self, Format('Exception in audio capture (attempt %d): %s', [ConsecutiveErrors, E.Message]));
              end);
            Sleep(100);
          end;
        end;
      end;

      // Small pause between iterations to not saturate CPU
      // (only if there were no errors, since errors already have Sleep)
      if (BytesRead > 0) and (ConsecutiveErrors = 0) then
        Sleep(1);

    end; // while

  finally
    // Free the Java buffer
    JBuffer := nil;

    // Log of termination
    TThread.Queue(nil,
      procedure
      begin
        if ErrorCount > 0 then
        begin
          if Assigned(FOnError) then
            FOnError(Self, Format('Audio capture loop ended. Total errors: %d', [ErrorCount]));
        end;
      end);
  end;
end;

{$ENDIF}

end.
