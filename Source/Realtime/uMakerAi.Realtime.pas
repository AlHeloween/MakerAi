// MakerAI Suite — Abstract base class for Realtime STT components
// Provides: PCM16 resampler, thread-safe event dispatchers, driver factory
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.Realtime;

interface

uses
  System.SysUtils, System.Classes, System.Math,
  System.Generics.Collections, System.SyncObjs, System.Threading;

type
  // Voice activity detection mode
  TAiRealtimeVADMode = (
    rvmServerVad,   // Energy-based VAD (server)
    rvmSemanticVad, // Semantic VAD (server)
    rvmManual       // Client controls commit manually
  );

  // Background noise reduction
  TAiRealtimeNoiseReduction = (
    rnrNone,      // No reduction
    rnrNearField, // Headset microphone
    rnrFarField   // Laptop/room microphone
  );

  // Event types
  TAiRealtimeTranscriptDeltaEvent = procedure(Sender: TObject;
    const Delta: string) of object;

  TAiRealtimeTranscriptCompletedEvent = procedure(Sender: TObject;
    const Transcript: string; const ItemId: string) of object;

  TAiRealtimeErrorEvent = procedure(Sender: TObject;
    const ErrorMsg, ErrorCode: string) of object;

  TAiRealtimeSpeechEvent = procedure(Sender: TObject;
    AudioMs: Int64; const ItemId: string) of object;

  // Assistant text (complete or delta) — full-duplex voice drivers
  TAiRealtimeAssistantTextEvent = procedure(Sender: TObject;
    const AText: string) of object;

  // Assistant TTS audio chunk (PCM16)
  TAiRealtimeAudioChunkEvent = procedure(Sender: TObject;
    const AData: TBytes) of object;

  TAiRealtimeBase = class;
  TAiRealtimeClass = class of TAiRealtimeBase;

  // -------------------------------------------------------------------
  // Driver factory
  // -------------------------------------------------------------------
  TAiRealtimeFactory = class
  strict private
    class var FInstance: TAiRealtimeFactory;
  strict private
    // Instance field: inside 'class var' it would also be class-level and no one
    // would free it (leak reported when closing any app using realtime)
    FDrivers: TDictionary<string, TAiRealtimeClass>;
    constructor Create;
    class destructor ClassDestroy;
  public
    destructor Destroy; override;
    class function Instance: TAiRealtimeFactory;
    procedure RegisterDriver(const AName: string; AClass: TAiRealtimeClass);
    function  CreateDriver(const AName: string; AOwner: TComponent): TAiRealtimeBase;
    function  DriverNames: TArray<string>;
  end;

  // -------------------------------------------------------------------
  // Abstract base class
  // -------------------------------------------------------------------
  TAiRealtimeBase = class(TComponent)
  private
    FApiKey:          string;
    FModel:           string;
    FLanguage:        string;
    FInputSampleRate: Integer;
    FVADMode:         TAiRealtimeVADMode;
    FVADThreshold:    Single;
    FSilenceDurationMs: Integer;
    FPrefixPaddingMs:   Integer;
    FNoiseReduction:  TAiRealtimeNoiseReduction;
    FConnected:       Boolean;
    FOnConnected:     TNotifyEvent;
    FOnDisconnected:  TNotifyEvent;
    FOnSessionReady:  TNotifyEvent;
    FOnSpeechStarted: TAiRealtimeSpeechEvent;
    FOnSpeechStopped: TAiRealtimeSpeechEvent;
    FOnTranscriptDelta:     TAiRealtimeTranscriptDeltaEvent;
    FOnTranscriptCompleted: TAiRealtimeTranscriptCompletedEvent;
    FOnError:         TAiRealtimeErrorEvent;
    function GetResolvedApiKey: string;
  protected
    // Each driver indicates the sample rate it needs for audio
    function GetTargetSampleRate: Integer; virtual; abstract;
    // The driver implements actual sending to WebSocket
    procedure InternalSendAudio(const ResampledPCM16: TBytes); virtual; abstract;
    procedure InternalConnect;    virtual; abstract;
    procedure InternalDisconnect; virtual; abstract;
    procedure InternalCommitAudio; virtual; abstract;
    procedure InternalClearAudio;  virtual; abstract;
    // Linear PCM16 resampler (mono)
    function ResamplePCM16(const Input: TBytes; FromHz, ToHz: Integer): TBytes;
    // Thread-safe dispatchers (all via TThread.Queue to main thread)
    procedure DoConnected;
    procedure DoDisconnected;
    procedure DoSessionReady;
    procedure DoSpeechStarted(AudioMs: Int64; const ItemId: string);
    procedure DoSpeechStopped(AudioMs: Int64; const ItemId: string);
    procedure DoTranscriptDelta(const Delta: string);
    procedure DoTranscriptCompleted(const Transcript, ItemId: string);
    procedure DoError(const ErrorMsg, ErrorCode: string);
    property ResolvedApiKey: string read GetResolvedApiKey;
    property Connected: Boolean read FConnected write FConnected;
  public
    constructor Create(AOwner: TComponent); override;
    // Connect/Disconnect to provider
    procedure Connect;
    procedure Disconnect;
    // Send PCM16 audio chunk (automatically resampled according to provider).
    // virtual so TAiRealtimeConnection can delegate without double resampling.
    procedure SendAudioChunk(const PCM16Data: TBytes); virtual;
    // Manual VAD control (only when VADMode = rvmManual)
    procedure CommitAudio;
    procedure ClearAudio;
    class function GetDriverName:    string; virtual; abstract;
    class function GetDefaultModel:  string; virtual; abstract;
    property IsConnected:    Boolean read FConnected;
    property TargetSampleRate: Integer read GetTargetSampleRate;
  published
    property ApiKey:   string  read FApiKey   write FApiKey;
    property Model:    string  read FModel    write FModel;
    property Language: string  read FLanguage write FLanguage;
    // Sample rate of audio delivered via SendAudioChunk (before resampling)
    property InputSampleRate: Integer read FInputSampleRate write FInputSampleRate
      default 44100;
    property VADMode:          TAiRealtimeVADMode       read FVADMode        write FVADMode        default rvmServerVad;
    property VADThreshold:     Single                   read FVADThreshold   write FVADThreshold;
    property SilenceDurationMs: Integer                 read FSilenceDurationMs write FSilenceDurationMs default 500;
    property PrefixPaddingMs:  Integer                  read FPrefixPaddingMs  write FPrefixPaddingMs  default 300;
    property NoiseReduction:   TAiRealtimeNoiseReduction read FNoiseReduction  write FNoiseReduction   default rnrNearField;
    property OnConnected:    TNotifyEvent               read FOnConnected    write FOnConnected;
    property OnDisconnected: TNotifyEvent               read FOnDisconnected write FOnDisconnected;
    property OnSessionReady: TNotifyEvent               read FOnSessionReady write FOnSessionReady;
    property OnSpeechStarted:       TAiRealtimeSpeechEvent          read FOnSpeechStarted       write FOnSpeechStarted;
    property OnSpeechStopped:       TAiRealtimeSpeechEvent          read FOnSpeechStopped       write FOnSpeechStopped;
    property OnTranscriptDelta:     TAiRealtimeTranscriptDeltaEvent read FOnTranscriptDelta     write FOnTranscriptDelta;
    property OnTranscriptCompleted: TAiRealtimeTranscriptCompletedEvent read FOnTranscriptCompleted write FOnTranscriptCompleted;
    property OnError: TAiRealtimeErrorEvent read FOnError write FOnError;
  end;

  // -------------------------------------------------------------------
  // Base for full-duplex voice drivers (STT + LLM + TTS)
  // Adds assistant output: text (delta and complete) and TTS audio.
  // Drivers: TAiMakerAiRealtimeChat, TAiGrokRealtimeChat
  // -------------------------------------------------------------------
  TAiRealtimeVoiceBase = class(TAiRealtimeBase)
  private
    FOnAssistantText:      TAiRealtimeAssistantTextEvent;
    FOnAssistantTextDelta: TAiRealtimeAssistantTextEvent;
    FOnAudioChunk:         TAiRealtimeAudioChunkEvent;
    FOnAudioDone:          TNotifyEvent;
  protected
    // Thread-safe dispatchers (via TThread.Queue to main thread)
    procedure DoAssistantText(const AText: string);
    procedure DoAssistantTextDelta(const ADelta: string);
    procedure DoAudioChunk(const AData: TBytes);
    procedure DoAudioDone;
  published
    // Complete assistant response text (at end of turn)
    property OnAssistantText: TAiRealtimeAssistantTextEvent
      read FOnAssistantText write FOnAssistantText;
    // Streaming text fragments (drivers that support it)
    property OnAssistantTextDelta: TAiRealtimeAssistantTextEvent
      read FOnAssistantTextDelta write FOnAssistantTextDelta;
    // Assistant TTS audio in PCM16 (sample rate according to driver)
    property OnAudioChunk: TAiRealtimeAudioChunkEvent
      read FOnAudioChunk write FOnAudioChunk;
    // End of audio for current turn
    property OnAudioDone: TNotifyEvent
      read FOnAudioDone write FOnAudioDone;
  end;

implementation

{ TAiRealtimeFactory }

constructor TAiRealtimeFactory.Create;
begin
  inherited;
  FDrivers := TDictionary<string, TAiRealtimeClass>.Create;
end;

destructor TAiRealtimeFactory.Destroy;
begin
  FDrivers.Free;
  inherited;
end;

class destructor TAiRealtimeFactory.ClassDestroy;
begin
  FreeAndNil(FInstance);
end;

class function TAiRealtimeFactory.Instance: TAiRealtimeFactory;
begin
  if not Assigned(FInstance) then
    FInstance := TAiRealtimeFactory.Create;
  Result := FInstance;
end;

procedure TAiRealtimeFactory.RegisterDriver(const AName: string;
  AClass: TAiRealtimeClass);
begin
  FDrivers.AddOrSetValue(AName, AClass);
end;

function TAiRealtimeFactory.CreateDriver(const AName: string;
  AOwner: TComponent): TAiRealtimeBase;
var
  Cls: TAiRealtimeClass;
begin
  if not FDrivers.TryGetValue(AName, Cls) then
    raise EArgumentException.CreateFmt(
      'Realtime driver "%s" not found. Add the driver unit to the uses clause.', [AName]);
  Result := Cls.Create(AOwner);
end;

function TAiRealtimeFactory.DriverNames: TArray<string>;
begin
  Result := FDrivers.Keys.ToArray;
end;

{ TAiRealtimeBase }

constructor TAiRealtimeBase.Create(AOwner: TComponent);
begin
  inherited;
  FInputSampleRate  := 44100;
  FVADMode          := rvmServerVad;
  FVADThreshold     := 0.5;
  FSilenceDurationMs := 500;
  FPrefixPaddingMs  := 300;
  FNoiseReduction   := rnrNearField;
  FConnected        := False;
end;

function TAiRealtimeBase.GetResolvedApiKey: string;
begin
  if (Length(FApiKey) > 1) and (FApiKey[1] = '@') then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, MaxInt))
  else
    Result := FApiKey;
end;

// Linear PCM16 mono resampler.
// Converts a signal from FromHz to ToHz using linear interpolation.
function TAiRealtimeBase.ResamplePCM16(const Input: TBytes;
  FromHz, ToHz: Integer): TBytes;
var
  InSamples, OutSamples, i, SrcIdx: Integer;
  SrcPos, Frac: Double;
  S0, S1, OutSample: SmallInt;
begin
  if (FromHz = ToHz) or (Length(Input) = 0) then
  begin
    Result := Copy(Input);
    Exit;
  end;
  InSamples  := Length(Input) div 2; // PCM16 = 2 bytes/sample
  OutSamples := Round(InSamples * ToHz / FromHz);
  SetLength(Result, OutSamples * 2);
  for i := 0 to OutSamples - 1 do
  begin
    SrcPos := i * FromHz / ToHz;
    SrcIdx := Trunc(SrcPos);
    Frac   := SrcPos - SrcIdx;
    Move(Input[SrcIdx * 2], S0, 2);
    if SrcIdx + 1 < InSamples then
      Move(Input[(SrcIdx + 1) * 2], S1, 2)
    else
      S1 := S0;
    OutSample := SmallInt(Round(S0 + Frac * (S1 - S0)));
    Move(OutSample, Result[i * 2], 2);
  end;
end;

procedure TAiRealtimeBase.Connect;
begin
  InternalConnect;
end;

procedure TAiRealtimeBase.Disconnect;
begin
  if FConnected then
    InternalDisconnect;
end;

procedure TAiRealtimeBase.SendAudioChunk(const PCM16Data: TBytes);
var
  Resampled: TBytes;
  TargetHz:  Integer;
begin
  if not FConnected then Exit;
  if Length(PCM16Data) = 0 then Exit;
  TargetHz := GetTargetSampleRate;
  if FInputSampleRate <> TargetHz then
    Resampled := ResamplePCM16(PCM16Data, FInputSampleRate, TargetHz)
  else
    Resampled := PCM16Data;
  InternalSendAudio(Resampled);
end;

procedure TAiRealtimeBase.CommitAudio;
begin
  if FConnected then InternalCommitAudio;
end;

procedure TAiRealtimeBase.ClearAudio;
begin
  if FConnected then InternalClearAudio;
end;

{ Dispatchers — always to main thread via TThread.Queue }

procedure TAiRealtimeBase.DoConnected;
begin
  FConnected := True;
  if Assigned(FOnConnected) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnConnected) then FOnConnected(Self);
    end);
end;

procedure TAiRealtimeBase.DoDisconnected;
begin
  FConnected := False;
  if Assigned(FOnDisconnected) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnDisconnected) then FOnDisconnected(Self);
    end);
end;

procedure TAiRealtimeBase.DoSessionReady;
begin
  if Assigned(FOnSessionReady) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnSessionReady) then FOnSessionReady(Self);
    end);
end;

procedure TAiRealtimeBase.DoSpeechStarted(AudioMs: Int64; const ItemId: string);
begin
  if Assigned(FOnSpeechStarted) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnSpeechStarted) then FOnSpeechStarted(Self, AudioMs, ItemId);
    end);
end;

procedure TAiRealtimeBase.DoSpeechStopped(AudioMs: Int64; const ItemId: string);
begin
  if Assigned(FOnSpeechStopped) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnSpeechStopped) then FOnSpeechStopped(Self, AudioMs, ItemId);
    end);
end;

procedure TAiRealtimeBase.DoTranscriptDelta(const Delta: string);
begin
  if Assigned(FOnTranscriptDelta) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnTranscriptDelta) then FOnTranscriptDelta(Self, Delta);
    end);
end;

procedure TAiRealtimeBase.DoTranscriptCompleted(const Transcript, ItemId: string);
begin
  if Assigned(FOnTranscriptCompleted) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnTranscriptCompleted) then
        FOnTranscriptCompleted(Self, Transcript, ItemId);
    end);
end;

procedure TAiRealtimeBase.DoError(const ErrorMsg, ErrorCode: string);
begin
  if Assigned(FOnError) then
    TThread.Queue(nil, procedure begin
      if Assigned(FOnError) then FOnError(Self, ErrorMsg, ErrorCode);
    end);
end;

{ TAiRealtimeVoiceBase — dispatchers of assistant output }

procedure TAiRealtimeVoiceBase.DoAssistantText(const AText: string);
var
  LText: string;
begin
  if not Assigned(FOnAssistantText) then Exit;
  LText := AText;
  TThread.Queue(nil, procedure begin
    if Assigned(FOnAssistantText) then FOnAssistantText(Self, LText);
  end);
end;

procedure TAiRealtimeVoiceBase.DoAssistantTextDelta(const ADelta: string);
var
  LDelta: string;
begin
  if not Assigned(FOnAssistantTextDelta) then Exit;
  LDelta := ADelta;
  TThread.Queue(nil, procedure begin
    if Assigned(FOnAssistantTextDelta) then FOnAssistantTextDelta(Self, LDelta);
  end);
end;

procedure TAiRealtimeVoiceBase.DoAudioChunk(const AData: TBytes);
var
  LData: TBytes;
begin
  if not Assigned(FOnAudioChunk) then Exit;
  LData := AData; // TBytes is dynamic array: assignment increments refcount
  TThread.Queue(nil, procedure begin
    if Assigned(FOnAudioChunk) then FOnAudioChunk(Self, LData);
  end);
end;

procedure TAiRealtimeVoiceBase.DoAudioDone;
begin
  if not Assigned(FOnAudioDone) then Exit;
  TThread.Queue(nil, procedure begin
    if Assigned(FOnAudioDone) then FOnAudioDone(Self);
  end);
end;

end.
