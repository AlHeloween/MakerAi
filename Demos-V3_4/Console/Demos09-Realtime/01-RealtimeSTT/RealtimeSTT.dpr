program RealtimeSTT;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 09-Realtime / 01-RealtimeSTT
// =============================================================================
// Real-time transcription via OpenAI Realtime API (WebSocket).
//
// Flujo:
//   1. TAIVoiceMonitor captures audio from the microphone (PCM16 44100 Hz)
//   2. The audio is automatically forwarded to TAiOpenAiRealtimeSTT
//   3. The component resamples to 24kHz and sends it to the server via WebSocket
//   4. The server VAD detects speech start/end
//   5. The transcription arrives in real time (delta) and as final text
//
// Controles:
//   - Presionar Enter para detener y salir
//
// Requiere:
//   - Variable de entorno OPENAI_API_KEY configurada
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  uMakerAi.Realtime,
  uMakerAi.Realtime.OpenAI,
  uMakerAi.Utils.VoiceMonitor;

const
  API_KEY = '@OPENAI_API_KEY';
  MODEL   = 'gpt-realtime-2.1';

var
  GDone: Boolean = False;

// =============================================================================
//  Objeto demo — agrupa el estado y los handlers de eventos
// =============================================================================

type
  TRealtimeDemo = class
  private
    FSTT:   TAiOpenAiRealtimeSTT;
    FMic:   TAIVoiceMonitor;
    FLine:  string; // accumulates the current delta (cleared on completion)
    procedure OnConnected(Sender: TObject);
    procedure OnDisconnected(Sender: TObject);
    procedure OnSessionReady(Sender: TObject);
    procedure OnSpeechStarted(Sender: TObject; AudioMs: Int64;
      const ItemId: string);
    procedure OnSpeechStopped(Sender: TObject; AudioMs: Int64;
      const ItemId: string);
    procedure OnTranscriptDelta(Sender: TObject; const Delta: string);
    procedure OnTranscriptCompleted(Sender: TObject;
      const Transcript, ItemId: string);
    procedure OnError(Sender: TObject; const ErrorMsg, ErrorCode: string);
    procedure OnCalibrated(Sender: TObject;
      const NoiseLevel, Sensitivity, StopSensitivity: Integer);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Run;
  end;

constructor TRealtimeDemo.Create;
begin
  inherited;

  // ── STT component ──────────────────────────────────────────────────────
  FSTT := TAiOpenAiRealtimeSTT.Create(nil);
  FSTT.ApiKey             := API_KEY;
  FSTT.Model              := MODEL;
  FSTT.Language           := 'es';          // 'es' = Spanish, '' = auto-detect
  FSTT.VADMode            := rvmServerVad;  // VAD on the server
  FSTT.SilenceDurationMs  := 600;           // ms of silence to cut the turn
  FSTT.PrefixPaddingMs    := 300;
  FSTT.NoiseReduction     := rnrNearField;  // headset / headphones
  FSTT.TranscriptionModel := otmGptLiveTranscribe;

  FSTT.OnConnected         := OnConnected;
  FSTT.OnDisconnected      := OnDisconnected;
  FSTT.OnSessionReady      := OnSessionReady;
  FSTT.OnSpeechStarted     := OnSpeechStarted;
  FSTT.OnSpeechStopped     := OnSpeechStopped;
  FSTT.OnTranscriptDelta   := OnTranscriptDelta;
  FSTT.OnTranscriptCompleted := OnTranscriptCompleted;
  FSTT.OnError             := OnError;

  // ── Microphone ────────────────────────────────────────────────────────────
  FMic := TAIVoiceMonitor.Create(nil);
  FMic.SampleRate         := 44100;
  FMic.SilenceDuration    := 800;
  FMic.RealtimeSTT        := FSTT;  // connect mic → STT
  FMic.OnCalibrated       := OnCalibrated;

  FLine := '';
end;

destructor TRealtimeDemo.Destroy;
begin
  FMic.Active := False;
  FMic.Free;
  FSTT.Disconnect;
  FSTT.Free;
  inherited;
end;

procedure TRealtimeDemo.Run;
begin
  Writeln('=== MakerAI — Realtime STT (OpenAI) ===');
  Writeln('Model : ', MODEL);
  Writeln('Language : es (Spanish)');
  Writeln;
  Writeln('Connecting...');

  // Connect to the server (async, does not block)
  FSTT.Connect;

  // Esperar un momento a que el WebSocket se establezca antes de activar el mic
  // El evento OnSessionReady arranca la captura cuando el servidor confirma sesion
  // (ver OnSessionReady abajo)
end;

{ Handlers de eventos }

procedure TRealtimeDemo.OnConnected(Sender: TObject);
begin
  Writeln('[+] WebSocket connected');
end;

procedure TRealtimeDemo.OnDisconnected(Sender: TObject);
begin
  Writeln('[x] Disconnected');
end;

procedure TRealtimeDemo.OnSessionReady(Sender: TObject);
begin
  Writeln('[✓] Session configured — starting microphone calibration...');
  // Activar el mic DESPUES de que el servidor confirme la sesion
  FMic.Active := True;
end;

procedure TRealtimeDemo.OnCalibrated(Sender: TObject;
  const NoiseLevel, Sensitivity, StopSensitivity: Integer);
begin
  Writeln(Format('[mic] Calibrado — ruido=%d  umbral-inicio=%d  umbral-stop=%d',
    [NoiseLevel, Sensitivity, StopSensitivity]));
  Writeln;
  Writeln('Ready. Speak into the microphone. Press Enter to exit.');
  Writeln;
end;

procedure TRealtimeDemo.OnSpeechStarted(Sender: TObject; AudioMs: Int64;
  const ItemId: string);
begin
  Write('[speech] ');
  FLine := '';
end;

procedure TRealtimeDemo.OnSpeechStopped(Sender: TObject; AudioMs: Int64;
  const ItemId: string);
begin
  Writeln; // nueva linea al terminar el habla
end;

procedure TRealtimeDemo.OnTranscriptDelta(Sender: TObject; const Delta: string);
begin
  // Escribir el delta sin salto de linea para efecto de escritura en tiempo real
  FLine := FLine + Delta;
  Write(Delta);
end;

procedure TRealtimeDemo.OnTranscriptCompleted(Sender: TObject;
  const Transcript, ItemId: string);
begin
  // We already showed the deltas; here we only confirm the final transcription
  if Transcript <> FLine then
  begin
    // The server sent a version different from the accumulated deltas
    Writeln;
    Writeln('[ok] ', Transcript);
  end
  else
    Writeln;  // just a line break to separate phrases
  FLine := '';
end;

procedure TRealtimeDemo.OnError(Sender: TObject;
  const ErrorMsg, ErrorCode: string);
begin
  Writeln;
  Writeln('[ERROR] (', ErrorCode, ') ', ErrorMsg);
  if ErrorCode = 'connection_failed' then
    GDone := True;
end;

// =============================================================================
//  Main
// =============================================================================

var
  Demo: TRealtimeDemo;

begin
  Demo := TRealtimeDemo.Create;
  try
    Demo.Run;

    // Auxiliary thread: waits for Enter while the main pump processes callbacks
    TThread.CreateAnonymousThread(procedure begin
      Readln;
      GDone := True;
    end).Start;

    // Main pump: processes TThread.Queue callbacks
    while not GDone do
      CheckSynchronize(50);

    Writeln;
    Writeln('Stopping...');
  finally
    Demo.Free;
  end;

  Writeln('Done.');
  Readln;
end.
