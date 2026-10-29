program ChatHistory;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 04-ChatHistory
// =============================================================================
// Multi-turn conversation: the LLM remembers what was said previously
// because each call to AddMessageAndRun() accumulates the history internally.
//
// Conceptos que cubre:
//   - Automatic message history (user / assistant alternated)
//   - Reference to previous messages within the conversation
//   - Clear history with ClearMessages()
//   - Inspect the history with Messages.Count
//   - Manage context size (truncate history when it grows)
//
// Importante:
//   Each provider has a context token limit. If the conversation
//   is very long, eventually the history must be cleared or summarized.
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
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
//  Utilidad: imprime el turno de la conversación con formato
// =============================================================================
procedure PrintTurn(const Role, Text: String; TurnNum: Integer);
begin
  Writeln;
  if Role = 'user' then
    Writeln(Format('[Turn %d] User: %s', [TurnNum, Text]))
  else
    Writeln(Format('[Turn %d] Assistant: %s', [TurnNum, Text]));
end;

// =============================================================================
//  DEMO 1 — Conversación simple de 4 turnos
// =============================================================================
procedure DemoConversacionSimple(Conn: TAiChatConnection);
const
  PREGUNTAS: array[0..3] of String = (
    'Mi nombre es Carlos y me gustan los dinosaurios.',
    '¿Cuál es tu dinosaurio favorito y por qué?',
    '¿Recuerdas cómo me llamo?',
    'Recomiéndame 3 libros sobre el tema que mencioné al inicio.'
  );
var
  I       : Integer;
  Response: String;
begin
  Writeln('─── Simple conversation (4 turns) ───');
  Conn.Messages.Clear;

  for I := 0 to High(PREGUNTAS) do
  begin
    PrintTurn('user', PREGUNTAS[I], I + 1);
    Response := Conn.AddMessageAndRun(PREGUNTAS[I], 'user', []);
    PrintTurn('assistant', Response, I + 1);
    Writeln(Format('  [Historial: %d mensajes acumulados]', [Conn.Messages.Count]));
  end;
  Writeln;
end;

// =============================================================================
//  DEMO 2 — Conversación con reset a mitad
// =============================================================================
procedure DemoConReset(Conn: TAiChatConnection);
var
  Response: String;
begin
  Writeln('─── Conversación con reset ───');
  Conn.Messages.Clear;

  // Primera conversación
  Conn.AddMessageAndRun('El código secreto de hoy es ALFA-7.', 'user', []);
  Conn.AddMessageAndRun('¿Recuerdas el código secreto?', 'user', []);

  Writeln('Before reset — the LLM remembers the code:');
  Response := Conn.AddMessageAndRun('¿Cuál era el código exacto?', 'user', []);
  Writeln('  ', Response);

  // Reset del historial
  Conn.Messages.Clear;
  Writeln;
  Writeln(Format('History cleared. Messages: %d', [Conn.Messages.Count]));

  // Segunda conversación — no recuerda nada de la anterior
  Response := Conn.AddMessageAndRun(
    '¿Cuál era el código secreto que te mencioné?', 'user', []);
  Writeln('After reset — the LLM no longer remembers:');
  Writeln('  ', Response);
  Writeln;
end;

// =============================================================================
//  DEMO 3 — Chat interactivo por consola (hasta escribir "salir")
// =============================================================================
procedure DemoChatInteractivo(Conn: TAiChatConnection);
var
  Input   : String;
  Response: String;
  Turn    : Integer;
begin
  Writeln('─── Interactive chat (type "salir" to finish) ───');
  Conn.Messages.Clear;
  Turn := 0;

  repeat
    Write('You: ');
    Readln(Input);
    Input := Trim(Input);

    if (Input = '') or (SameText(Input, 'salir')) then
      Break;

    Inc(Turn);
    Response := Conn.AddMessageAndRun(Input, 'user', []);
    Writeln('AI: ', Response);
    Writeln(Format('  [%d messages in history]', [Conn.Messages.Count]));
    Writeln;
  until False;

  Writeln(Format('Conversation finished. Total turns: %d', [Turn]));
  Writeln;
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
begin
  Writeln('=== ChatHistory ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';

    Conn.SystemPrompt.Text :=
      'Eres un asistente amigable. Recuerdas todo lo dicho en la conversación. ' +
      'Responde siempre en español.';

    DemoConversacionSimple(Conn);
    DemoConReset(Conn);
    DemoChatInteractivo(Conn);

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
