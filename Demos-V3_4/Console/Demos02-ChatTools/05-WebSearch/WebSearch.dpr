program WebSearch;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 05-WebSearch
// =============================================================================
// The LLM searches the internet to answer questions with recent information,
// overcoming the "knowledge cutoff" limitation.
//
// Concepts covered:
//   - Enable web search with cap_WebSearch in Capabilities
//   - Providers with native search: Gemini (Google Search), Grok (X/Twitter)
//   - Claude provider: uses Brave Search if the API key is configured
//   - Difference between responses with and without web search
//   - The citations/sources returned by the LLM
//
// Supported providers:
//   - Gemini    → Google Search integrated, no extra configuration
//   - Grok      → X/Twitter + web, no extra configuration
//   - Claude    → Requires BRAVE_API_KEY (or Bing) configured in the provider
//   - OpenAI    → Requires additional tool configuration
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Grok;

const
  // Gemini tiene búsqueda web nativa sin configuración extra
  DRIVER  = 'Gemini';
  MODEL   = 'gemini-2.0-flash';
  API_KEY = '@GEMINI_API_KEY';

// Preguntas que requieren información actual
const
  PREGUNTAS: array[0..3] of String = (
    'What are the latest artificial intelligence news this week?',
    'What is the current price of the dollar against the Mexican peso?',
    'What is the latest LLM model released by Anthropic?',
    'What important technology events happened this month?'
  );

// =============================================================================
//  Compares responses WITH and WITHOUT web search for the same question
// =============================================================================
procedure CompararConSinBusqueda(Conn: TAiChatConnection; const Question: String);
var
  Res: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', Question);
  Writeln;

  // ── WITHOUT web search ─────────────────────────────────────────────────
  Conn.Messages.Clear;
  Conn.Params.Values['WebSearch'] := 'False';

  Res := Conn.AddMessageAndRun(Question, 'user', []);
  Writeln('WITHOUT web search:');
  Writeln('  ', Copy(Res, 1, 200), '...');
  Writeln;

  // ── WITH web search ─────────────────────────────────────────────────
  Conn.Messages.Clear;
  Conn.Params.Values['WebSearch'] := 'True';

  Res := Conn.AddMessageAndRun(Question, 'user', []);
  Writeln('WITH web search:');
  Writeln('  ', Copy(Res, 1, 400));
  Writeln;
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
  Res : String;
  I   : Integer;
begin
  Writeln('=== WebSearch ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;
  Writeln('Gemini has native access to Google Search.');
  Writeln('Grok uses the X/Twitter web. Claude requires a Brave API key.');
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';

    Conn.SystemPrompt.Text :=
      'You are an assistant that can search the internet. ' +
      'When you use web search, mention the sources consulted. ' +
      'Respond in Spanish.';

    // ── Demo 1: Comparison with/without search ─────────────────────────────
    Writeln('=== COMPARISON: with vs. without web search ===');
    CompararConSinBusqueda(Conn,
      'What is the most powerful LLM available today?');

    // ── Demo 2: Questions that need current info ───────────────────────
    Writeln('=== QUESTIONS THAT REQUIRE CURRENT INFORMATION ===');
    Conn.Params.Values['WebSearch'] := 'True';

    for I := Low(PREGUNTAS) to High(PREGUNTAS) do
    begin
      Conn.Messages.Clear;
      Writeln(StringOfChar('-', 60));
      Writeln(Format('Question %d: %s', [I+1, PREGUNTAS[I]]));
      Res := Conn.AddMessageAndRun(PREGUNTAS[I], 'user', []);
      Writeln('Response: ');
      Writeln(Copy(Res, 1, 500));
      Writeln;
    end;

    // ── Demo 3: Cite sources ─────────────────────────────────────────────
    Writeln(StringOfChar('-', 60));
    Writeln('Demo 3: Response with cited sources');
    Conn.Messages.Clear;
    Conn.SystemPrompt.Text :=
      'Respond with sources. At the end include a section "Sources:" with ' +
      'the consulted URLs. Respond in Spanish.';

    Res := Conn.AddMessageAndRun(
      'What is the Model Context Protocol (MCP) from Anthropic and what is it for?',
      'user', []);
    Writeln(Res);

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
