program Streaming;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 03-Streaming
// =============================================================================
// Shows the LLM response token by token as it arrives (streaming),
// without waiting for generation to finish.
//
// Concepts covered:
//   - OnReceiveData event    (fires for each fragment received)
//   - OnReceiveDataEnd event (fires when the stream ends)
//   - Visual difference between waiting for the full response vs. streaming
//   - Measuring time to first token (TTFT) and total time
//
// Note: Asynchronous = False is still synchronous in that
// AddMessageAndRun() does not return until it finishes, but the events
// OnReceiveData fire on the main thread as the fragments
// arrive → you can print progressively.
// =============================================================================

uses
  System.SysUtils,
  System.Diagnostics,
  System.JSON,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Ollama,
  uMakerAi.Chat.Groq;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// =============================================================================
//  TStreamingDemo — encapsulates the connection and streaming handlers
// =============================================================================
type
  TStreamingDemo = class
  private
    FConn        : TAiChatConnection;
    // Metrics for Demo 2
    FSW          : TStopwatch;
    FFirstTokenMs: Int64;
    FTokenCount  : Integer;
    // State for Demo 3
    FFullResponse: String;
    FFragCount   : Integer;

    // ── Demo 2 handlers: print each fragment in real time ──────────────
    procedure OnChunk(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnDone(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);

    // ── Demo 3 handlers: accumulate + show progress dots ───────────────
    procedure OnProgressChunk(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnProgressDone(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);

    procedure DemoSinStreaming;
    procedure DemoConStreaming;
    procedure DemoStreamingConProgreso;
  public
    procedure Run;
  end;

// =============================================================================
//  Handlers para Demo 2
// =============================================================================

procedure TStreamingDemo.OnChunk(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  if FFirstTokenMs = 0 then
    FFirstTokenMs := FSW.ElapsedMilliseconds;
  Write(aText);
  Inc(FTokenCount);
end;

procedure TStreamingDemo.OnDone(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  FSW.Stop;
end;

// =============================================================================
//  Handlers para Demo 3
// =============================================================================

procedure TStreamingDemo.OnProgressChunk(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  FFullResponse := FFullResponse + aText;
  Inc(FFragCount);
  Write('.');
  if FFragCount mod 40 = 0 then Writeln;
end;

procedure TStreamingDemo.OnProgressDone(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  Writeln;
  Writeln;
  Writeln('Complete response:');
  Writeln(FFullResponse);
  Writeln(Format('(Total: %d fragments)', [FFragCount]));
end;

// =============================================================================
//  DEMO 1 — Sin streaming (bloquea hasta recibir respuesta completa)
// =============================================================================
procedure TStreamingDemo.DemoSinStreaming;
var
  SW      : TStopwatch;
  Response: String;
begin
  Writeln('--- WITHOUT STREAMING ---');
  Writeln('(Waits until the response is complete before displaying it)');
  Writeln;

  FConn.Messages.Clear;
  // No streaming events assigned
  FConn.OnReceiveData    := nil;
  FConn.OnReceiveDataEnd := nil;

  SW := TStopwatch.StartNew;
  Response := FConn.AddMessageAndRun(
    'Escribe un párrafo de 5 oraciones describiendo el ciclo del agua.',
    'user', []);
  SW.Stop;

  Writeln(Response);
  Writeln;
  Writeln(Format('Total time: %d ms', [SW.ElapsedMilliseconds]));
  Writeln;
end;

// =============================================================================
//  DEMO 2 — Con streaming (imprime cada fragmento conforme llega)
// =============================================================================
procedure TStreamingDemo.DemoConStreaming;
var
  SW: TStopwatch;
begin
  Writeln('--- WITH STREAMING ---');
  Writeln('(Each fragment is printed as it arrives from the server)');
  Writeln;

  FConn.Messages.Clear;
  FFirstTokenMs := 0;
  FTokenCount   := 0;
  FSW           := TStopwatch.StartNew;

  FConn.OnReceiveData    := OnChunk;
  FConn.OnReceiveDataEnd := OnDone;

  SW := TStopwatch.StartNew;
  FConn.AddMessageAndRun(
    'Escribe un párrafo de 5 oraciones describiendo el ciclo del agua.',
    'user', []);
  SW.Stop;

  Writeln;
  Writeln;
  Writeln(Format('Time to first token: %d ms', [FFirstTokenMs]));
  Writeln(Format('Total time             : %d ms', [SW.ElapsedMilliseconds]));
  Writeln(Format('Fragments received     : %d', [FTokenCount]));
  Writeln;
end;

// =============================================================================
//  DEMO 3 — Streaming con progreso visual (puntos)
// =============================================================================
procedure TStreamingDemo.DemoStreamingConProgreso;
begin
  Writeln('--- STREAMING WITH VISUAL PROGRESS ---');
  Writeln('(The dots represent fragments; the response is shown at the end)');
  Writeln;

  FConn.Messages.Clear;
  FFullResponse := '';
  FFragCount    := 0;

  FConn.OnReceiveData    := OnProgressChunk;
  FConn.OnReceiveDataEnd := OnProgressDone;

  FConn.AddMessageAndRun(
    '¿Cuáles son los 5 planetas más grandes del sistema solar? Lista solo sus nombres.',
    'user', []);
  Writeln;
end;

// =============================================================================
//  Run — punto de entrada del demo
// =============================================================================
procedure TStreamingDemo.Run;
begin
  Writeln('=== Streaming ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  FConn := TAiChatConnection.Create(nil);
  try
    FConn.DriverName := DRIVER;
    FConn.Model      := MODEL;

    FConn.Params.Values['ApiKey']       := API_KEY;
    FConn.Params.Values['Asynchronous'] := 'False';
    FConn.Params.Values['Max_Tokens']   := '512';

    FConn.SystemPrompt.Text := 'Always respond in Spanish.';

    DemoSinStreaming;
    DemoConStreaming;
    DemoStreamingConProgreso;

  finally
    FConn.Free;
  end;
end;

// =============================================================================
//  Punto de entrada
// =============================================================================
begin
  try
    with TStreamingDemo.Create do
    try
      Run;
    finally
      Free;
    end;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
