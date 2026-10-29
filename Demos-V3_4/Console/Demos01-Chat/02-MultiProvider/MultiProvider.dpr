program MultiProvider;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 02-MultiProvider
// =============================================================================
// Same question, sent to multiple LLM providers one after another.
// Demonstrates that the application code does NOT change when changing provider.
//
// Conceptos que cubre:
//   - Universal connector pattern (TAiChatConnection)
//   - Provider change at runtime
//   - Comparison of responses between models
//   - Error handling per provider (invalid key, model not available)
//
// Requisitos:
//   Define the API keys as environment variables:
//   CLAUDE_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, GROQ_API_KEY
//   Local providers (Ollama) do not require an API key.
// =============================================================================

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Ollama,
  uMakerAi.Chat.Groq,
  uMakerAi.Chat.Mistral,
  uMakerAi.Chat.DeepSeek;

// ── Definition of the providers to test ───────────────────────────────────
type
  TProviderConfig = record
    Driver : String;
    Model  : String;
    ApiKey : String;
    Enabled: Boolean;
  end;

const
  PROVIDERS: array[0..4] of TProviderConfig = (
    (Driver: 'Claude';   Model: 'claude-haiku-4-5-20251001';   ApiKey: '@CLAUDE_API_KEY';  Enabled: True),
    (Driver: 'OpenAI';   Model: 'gpt-4.1-mini';                ApiKey: '@OPENAI_API_KEY';  Enabled: True),
    (Driver: 'Gemini';   Model: 'gemini-2.0-flash';            ApiKey: '@GEMINI_API_KEY';  Enabled: True),
    (Driver: 'Groq';     Model: 'llama-3.3-70b-versatile';     ApiKey: '@GROQ_API_KEY';    Enabled: True),
    (Driver: 'Ollama';   Model: 'gemma3:4b';                   ApiKey: '';                 Enabled: True)
  );

  QUESTION = 'En exactamente 2 oraciones: ¿Qué es la inteligencia artificial?';

// =============================================================================
//  Function that sends the same question to a provider and measures the time
// =============================================================================
procedure AskProvider(const Cfg: TProviderConfig; const Question: String);
var
  Conn    : TAiChatConnection;
  Response: String;
  SW      : TStopwatch;
begin
  if not Cfg.Enabled then
  begin
    Writeln(Format('[%s] — Disabled', [Cfg.Driver]));
    Exit;
  end;

  Writeln(StringOfChar('-', 60));
  Writeln(Format('▶  %s  (%s)', [Cfg.Driver, Cfg.Model]));

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := Cfg.Driver;
    Conn.Model      := Cfg.Model;

    Conn.Params.Values['ApiKey']       := Cfg.ApiKey;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';

    Conn.SystemPrompt.Text := 'Responde siempre en español de forma concisa.';

    SW := TStopwatch.StartNew;
    try
      Response := Conn.AddMessageAndRun(Question, 'user', []);
      SW.Stop;
      Writeln(Format('   Time: %d ms', [SW.ElapsedMilliseconds]));
      Writeln('   Response: ', Response);
    except
      on E: Exception do
        Writeln(Format('   ERROR: %s', [E.Message]));
    end;
  finally
    Conn.Free;
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  I: Integer;
begin
  Writeln('=== MultiProvider ===');
  Writeln('Question: ', QUESTION);
  Writeln;

  for I := Low(PROVIDERS) to High(PROVIDERS) do
    AskProvider(PROVIDERS[I], QUESTION);

  Writeln(StringOfChar('=', 60));
  Writeln('All providers answered the same question.');
  Writeln('The query code is identical for all of them.');
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
