program MultiplesProviders;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 6: Working with Multiple Providers
// =============================================================================
// Demonstrates MakerAI's core portability principle: application code
// does NOT change when changing provider. Only DriverName changes.
//
// Demonstrates:
//   - Demo 1: The same question to multiple providers — identical code,
//             comparable results, different times and styles.
//   - Demo 2: Fallback pattern — if the primary provider fails (timeout, API key
//             invalid, rate limit), the code automatically tries the
//             secondary. Application logic does not know which provider answered.
//
// Configure providers:
//   GROQ_API_KEY   → free, recommended to get started (Enabled: True)
//   CLAUDE_API_KEY → Anthropic Claude
//   OPENAI_API_KEY → OpenAI GPT
//   GEMINI_API_KEY → Google Gemini
//   Ollama         → local, no API key (requires Ollama installed and running)
//
//   Set Enabled = False for providers whose API key you have not configured.
// =============================================================================

uses
  System.SysUtils,
  System.Diagnostics,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  // ── Cada import activa el auto-registro del driver ────────────────────────
  uMakerAi.Chat.Claude,    // DriverName = 'Claude'
  uMakerAi.Chat.OpenAi,   // DriverName = 'OpenAI'
  uMakerAi.Chat.Gemini,   // DriverName = 'Gemini'
  uMakerAi.Chat.Groq,     // DriverName = 'Groq'
  uMakerAi.Chat.Ollama;   // DriverName = 'Ollama' (local, no API key)

// =============================================================================
//  Provider configuration
// =============================================================================
type
  TProviderCfg = record
    Driver : string;
    Model  : string;
    ApiKey : string;
    Enabled: Boolean;
  end;

const
  // Enable/disable according to the API keys you have available.
  // Groq is enabled by default — it is free.
  PROVIDERS: array[0..4] of TProviderCfg = (
    (Driver: 'Groq';   Model: 'llama-3.3-70b-versatile';   ApiKey: '@GROQ_API_KEY';   Enabled: True),
    (Driver: 'Claude'; Model: 'claude-haiku-4-5-20251001'; ApiKey: '@CLAUDE_API_KEY'; Enabled: False),
    (Driver: 'OpenAI'; Model: 'gpt-4.1-mini';              ApiKey: '@OPENAI_API_KEY'; Enabled: False),
    (Driver: 'Gemini'; Model: 'gemini-2.0-flash';          ApiKey: '@GEMINI_API_KEY'; Enabled: False),
    (Driver: 'Ollama'; Model: 'gemma3:4b';                 ApiKey: '';                Enabled: False)
  );

  PREGUNTA = 'In exactly 2 sentences: What is artificial intelligence?';

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Utility: creates and configures a connection with standard parameters.
//  The caller is responsible for freeing the object with Free.
// =============================================================================
function CrearConexion(const Cfg: TProviderCfg): TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := Cfg.Driver;
  Result.Model      := Cfg.Model;

  Result.Params.Values['ApiKey']       := Cfg.ApiKey;
  Result.Params.Values['Asynchronous'] := 'False';
  Result.Params.Values['Max_Tokens']   := '256';

  Result.SystemPrompt.Text := 'Responde siempre en español de forma concisa.';
end;

// =============================================================================
//  Demo 1 — The same question to multiple providers
//
//  The code that sends the question is identical for each provider.
//  The only difference is DriverName — the universal connector handles the rest.
// =============================================================================
procedure Demo1_MultiProvider;
var
  Cfg : TProviderCfg;
  Conn: TAiChatConnection;
  SW  : TStopwatch;
  R   : string;
begin
  Separador('Demo 1 — Same question, multiple providers');
  WriteLn('Question: "', PREGUNTA, '"');

  for Cfg in PROVIDERS do
  begin
    WriteLn('');

    if not Cfg.Enabled then
    begin
      WriteLn('[', Cfg.Driver, '] — disabled (set Enabled = True in PROVIDERS)');
      Continue;
    end;

    Write('[', Cfg.Driver, ' / ', Cfg.Model, '] ...');
    Conn := CrearConexion(Cfg);
    try
      SW := TStopwatch.StartNew;
      try
        R := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
        SW.Stop;
        WriteLn(' ', SW.ElapsedMilliseconds, ' ms');
        WriteLn('  ', R);
      except
        on E: Exception do
        begin
          SW.Stop;
          WriteLn(' ERROR');
          WriteLn('  ', E.Message);
        end;
      end;
    finally
      Conn.Free;
    end;
  end;

  WriteLn('');
  WriteLn('→ The send/receive code is literally the same for each provider.');
  WriteLn('  Changing provider = changing DriverName. Nothing else.');
end;

// =============================================================================
//  Demo 2 — Fallback pattern
//
//  Resilience architecture: if the primary provider fails, use the secondary.
//  The application code that calls PreguntarConFallback() does not know — nor does it
//  care— which provider answered in the end.
// =============================================================================
function PreguntarConFallback(const Pregunta: string): string;
const
  // Primary provider: Groq (fast, free)
  PRIMARY: TProviderCfg = (
    Driver: 'Groq'; Model: 'llama-3.3-70b-versatile';
    ApiKey: '@GROQ_API_KEY'; Enabled: True);

  // Fallback provider: Claude (reliable, paid)
  FALLBACK: TProviderCfg = (
    Driver: 'Claude'; Model: 'claude-haiku-4-5-20251001';
    ApiKey: '@CLAUDE_API_KEY'; Enabled: True);
var
  Conn: TAiChatConnection;
begin
  Result := '';

  // Try with the primary provider
  Write('  Trying with ', PRIMARY.Driver, ' (primary)...');
  Conn := CrearConexion(PRIMARY);
  try
    try
      Result := Conn.AddMessageAndRun(Pregunta, 'user', []);
      WriteLn(' OK (', PRIMARY.Driver, ' responded)');
      Exit;
    except
      on E: Exception do
        WriteLn(' FAILED: ', E.Message);
    end;
  finally
    Conn.Free;
  end;

  // The primary failed — try with the fallback
  Write('  Trying with ', FALLBACK.Driver, ' (fallback)...');
  Conn := CrearConexion(FALLBACK);
  try
    try
      Result := Conn.AddMessageAndRun(Pregunta, 'user', []);
      WriteLn(' OK (fallback ', FALLBACK.Driver, ' responded)');
    except
      on E: Exception do
      begin
        WriteLn(' ALSO FAILED: ', E.Message);
        Result := '[Error: no provider available]';
      end;
    end;
  finally
    Conn.Free;
  end;
end;

procedure Demo2_Fallback;
var
  R: string;
begin
  Separador('Demo 2 — Fallback pattern');
  WriteLn('Question: "', PREGUNTA, '"');
  WriteLn('');

  R := PreguntarConFallback(PREGUNTA);

  WriteLn('');
  WriteLn('Final response: ', R);
  WriteLn('');
  WriteLn('→ The code that calls PreguntarConFallback() does not know which provider');
  WriteLn('  answered. The resilience logic is encapsulated.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
begin
  WriteLn('=== MakerAI — Chapter 6: Multiple Providers ===');
  WriteLn('Modify the PROVIDERS array to enable more providers.');

  Demo1_MultiProvider;
  Demo2_Fallback;

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demo completed.');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
