program HelloChat;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 01-HelloChat
// =============================================================================
// The simplest possible demo: configure a connection, send a message,
// print the response.
//
// Concepts covered:
//   - Create and configure TAiChatConnection
//   - Import the desired provider's driver
//   - Synchronous call with AddMessageAndRun()
//   - API key resolution from environment variables (@VARNAME)
//
// How to change provider:
//   Just modify DRIVER, MODEL, and API_KEY.
//   The rest of the code does not change — that is the core value proposition
//   of MakerAI: a universal connector for all LLMs.
//
// Configure before compiling (or define as environment variables):
//   CLAUDE_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY...
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  // ── Available drivers ──────────────────────────────────────────────────
  // Importing the driver activates its automatic registration in the factory.
  // You only need to import it; TAiChatConnection will find it by name.
  uMakerAi.Chat.Claude,    // DriverName = 'Claude'
  uMakerAi.Chat.OpenAi,    // DriverName = 'OpenAI'
  uMakerAi.Chat.Gemini,    // DriverName = 'Gemini'
  uMakerAi.Chat.Ollama,    // DriverName = 'Ollama'  (local, without API key)
  uMakerAi.Chat.Groq,      // DriverName = 'Groq'
  uMakerAi.Chat.Mistral;   // DriverName = 'Mistral'

const
  // ── Change here to use another provider ────────────────────────────────
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';   // '@VAR' → GetEnvironmentVariable('VAR')
  // ────────────────────────────────────────────────────────────────────────

  SYSTEM_PROMPT = 'You are a helpful and concise assistant. Always respond in Spanish.';

// =============================================================================
//  DEMO
// =============================================================================

procedure RunDemo;
var
  Conn    : TAiChatConnection;
  Prompt  : String;
  Response: String;
begin
  Writeln('=== HelloChat ===');
  Writeln('Driver : ', DRIVER);
  Writeln('Model  : ', MODEL);
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    // ── Minimal configuration ─────────────────────────────────────────────
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';  // synchronous call
    Conn.Params.Values['Max_Tokens']   := '1024';

    Conn.SystemPrompt.Text := SYSTEM_PROMPT;

    // ── Question 1: simple text ─────────────────────────────────────────
    Prompt := 'What is the capital of France? Answer in a single sentence.';
    Writeln('Question: ', Prompt);

    Response := Conn.AddMessageAndRun(Prompt, 'user', []);
    Writeln('Response: ', Response);
    Writeln;

    // ── Question 2: more elaborate ────────────────────────────────────────
    // Note: AddMessageAndRun() accumulates history. The second question
    // may refer to the first one. See demo 04-ChatHistory for details.
    Prompt := 'Now give me 3 curious facts about that city.';
    Writeln('Question: ', Prompt);

    Response := Conn.AddMessageAndRun(Prompt, 'user', []);
    Writeln('Response: ', Response);

  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
