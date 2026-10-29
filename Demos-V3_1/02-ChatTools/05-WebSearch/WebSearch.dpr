program WebSearch;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 05-WebSearch
// =============================================================================
// The LLM searches the internet to answer questions with recent information,
// superando la limitación del "knowledge cutoff".
//
// Concepts it covers:
//   - cap_WebSearch in ModelCaps activates search automatically
//   - Gemini (Google Search) has native cap_WebSearch — always active
//   - Claude uses only its internal knowledge (without native web search)
//   - Difference between responses with and without web search
//
// Comparison: Claude (without web) vs Gemini (with integrated web)
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.Gemini;

const
  // Claude — sin búsqueda web (solo conocimiento interno)
  DRIVER_SIN  = 'Claude';
  MODEL_SIN   = 'claude-haiku-4-5-20251001';
  API_KEY_SIN = '@CLAUDE_API_KEY';

  // Gemini — con búsqueda web nativa (cap_WebSearch en ModelCaps)
  DRIVER_CON  = 'Gemini';
  MODEL_CON   = 'gemini-3-flash-preview';
  API_KEY_CON = '@GEMINI_API_KEY';

// Questions that require current information
const
  PREGUNTAS: array[0..3] of String = (
    '¿Cuáles son las últimas noticias de inteligencia artificial de esta semana?',
    '¿Cuál es el precio actual del dólar respecto al peso mexicano?',
    '¿Cuál es el último modelo de LLM lanzado por Anthropic?',
    'What important technological events occurred this month?'
  );

// =============================================================================
//  Compara respuesta CON y SIN búsqueda web para la misma pregunta
// =============================================================================
procedure CompararConSinBusqueda(ConnSin, ConnCon: TAiChatConnection;
                                  const Question: String);
var
  Res: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', Question);
  Writeln;

  // ── SIN búsqueda web (Claude) ─────────────────────────────────────────
  ConnSin.Messages.Clear;
  Res := ConnSin.AddMessageAndRun(Question, 'user', []);
  Writeln('WITHOUT web search (Claude — internal knowledge only):');
  Writeln('  ', Copy(Res, 1, 200), '...');
  Writeln;

  // ── CON búsqueda web (Gemini) ─────────────────────────────────────────
  ConnCon.Messages.Clear;
  Res := ConnCon.AddMessageAndRun(Question, 'user', []);
  Writeln('WITH web search (Gemini — integrated Google Search):');
  Writeln('  ', Copy(Res, 1, 400));
  Writeln;
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  ConnSin : TAiChatConnection;   // Claude — sin web search
  ConnCon : TAiChatConnection;   // Gemini — con web search
  Res     : String;
  I       : Integer;
begin
  Writeln('=== WebSearch ===');
  Writeln('WITHOUT search: ', DRIVER_SIN, ' (', MODEL_SIN, ')');
  Writeln('WITH search: ', DRIVER_CON, ' (', MODEL_CON, ')');
  Writeln;
  Writeln('Gemini has cap_WebSearch in ModelCaps: Google Search always active.');
  Writeln('Claude uses only its internal knowledge (without native web search).');
  Writeln;

  ConnSin := TAiChatConnection.Create(nil);
  ConnCon := TAiChatConnection.Create(nil);
  try
    // Conexión SIN web search — Claude
    ConnSin.DriverName := DRIVER_SIN;
    ConnSin.Model      := MODEL_SIN;
    ConnSin.Params.Values['ApiKey']       := API_KEY_SIN;
    ConnSin.Params.Values['Asynchronous'] := 'False';
    ConnSin.Params.Values['Max_Tokens']   := '1024';
    ConnSin.SystemPrompt.Text :=
      'Responde basándote únicamente en tu conocimiento interno. Responde en español.';

    // Conexión CON web search — Gemini
    ConnCon.DriverName := DRIVER_CON;
    ConnCon.Model      := MODEL_CON;
    ConnCon.Params.Values['ApiKey']       := API_KEY_CON;
    ConnCon.Params.Values['Asynchronous'] := 'False';
    ConnCon.Params.Values['Max_Tokens']   := '1024';
    ConnCon.SystemPrompt.Text :=
      'Eres un asistente con acceso a búsqueda web. ' +
      'Cuando uses búsqueda web, menciona las fuentes consultadas. ' +
      'Responde en español.';

    // ── Demo 1: Comparación con/sin búsqueda ─────────────────────────────
    Writeln('=== COMPARISON: with vs. without web search ===');
    CompararConSinBusqueda(ConnSin, ConnCon,
      '¿Cuál es el LLM más potente disponible hoy?');

    // ── Demo 2: Preguntas que necesitan info actual ───────────────────────
    Writeln('=== PREGUNTAS QUE REQUIEREN INFORMACIÓN ACTUAL (Gemini) ===');
    for I := Low(PREGUNTAS) to High(PREGUNTAS) do
    begin
      ConnCon.Messages.Clear;
      Writeln(StringOfChar('-', 60));
      Writeln(Format('Question %d: %s', [I+1, PREGUNTAS[I]]));
      Res := ConnCon.AddMessageAndRun(PREGUNTAS[I], 'user', []);
      Writeln('Response: ');
      Writeln(Copy(Res, 1, 500));
      Writeln;
    end;

    // ── Demo 3: Citar fuentes ─────────────────────────────────────────────
    Writeln(StringOfChar('-', 60));
    Writeln('Demo 3: Response with cited sources (Gemini)');
    ConnCon.Messages.Clear;
    ConnCon.SystemPrompt.Text :=
      'Responde con fuentes. Al final incluye una sección "Fuentes:" con ' +
      'las URLs consultadas. Responde en español.';

    Res := ConnCon.AddMessageAndRun(
      '¿Qué es Model Context Protocol (MCP) de Anthropic y para qué sirve?',
      'user', []);
    Writeln(Res);

  finally
    ConnSin.Free;
    ConnCon.Free;
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
