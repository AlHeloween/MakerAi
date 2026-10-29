program PrimerChat;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 3: Your First Chat with MakerAI
// =============================================================================
// El demo más simple posible con TAiChatConnection: configurar el proveedor,
// enviar mensajes en un bucle y recibir respuestas.
//
// Concepts it covers:
//   - Create and configure TAiChatConnection
//   - Select provider with DriverName
//   - API key from environment variable with @VARNAME syntax
//   - Synchronous call with AddMessageAndRun()
//   - Automatic history: the model "remembers" without additional code
//   - Clear history with NewChat
//   - Inspect Messages.Count
//
// How to change provider:
//   Modify DRIVER, MODEL and API_KEY. The rest of the code does not change.
//   That is MakerAI's core value proposition.
//
// Configure before compiling:
//   Define GROQ_API_KEY as a system environment variable.
//   Free alternatives: Ollama (local, no key), Gemini (GEMINI_API_KEY).
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  // ── Importing the driver activates its auto-registration in the factory ──────────────
  // You only need to import the unit; TAiChatConnection finds it by name.
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Groq;      // DriverName = 'Groq'

  // uMakerAi.Chat.Claude;  // DriverName = 'Claude'
  // uMakerAi.Chat.OpenAi;  // DriverName = 'OpenAI'
  // uMakerAi.Chat.Gemini;  // DriverName = 'Gemini'
  // uMakerAi.Chat.Ollama;  // DriverName = 'Ollama'  (local, no API key)

const
  // ── Change here to use another provider ──────────────────────────────────
  DRIVER  = 'Groq';
  MODEL   = 'llama-3.3-70b-versatile';
  API_KEY = '@GROQ_API_KEY';   // '@VAR' → GetEnvironmentVariable('VAR')

procedure RunDemo;
var
  Conn    : TAiChatConnection;
  Prompt  : string;
  Respuesta: string;
begin
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';

    Conn.SystemPrompt.Text :=
      'Eres un asistente amable y conciso. Responde siempre en español.';

    WriteLn('');
    WriteLn('=== MakerAI — Chapter 3: First Chat ===');
    WriteLn('Provider : ', DRIVER);
    WriteLn('Model   : ', MODEL);
    WriteLn('Commands : "salir", "limpiar", "mensajes"');
    WriteLn('');

    repeat
      Write('You > ');
      ReadLn(Prompt);
      Prompt := Trim(Prompt);

      if Prompt = '' then
        Continue;

      if SameText(Prompt, 'salir') then
        Break;

      if SameText(Prompt, 'limpiar') then
      begin
        Conn.NewChat;   // Libera los objetos correctamente y limpia el historial
        WriteLn('   [History cleared]');
        WriteLn('');
        Continue;
      end;

      if SameText(Prompt, 'mensajes') then
      begin
        WriteLn('   [Messages in history: ', Conn.Messages.Count, ']');
        WriteLn('');
        Continue;
      end;

      try
        Respuesta := Conn.AddMessageAndRun(Prompt, 'user', []);
        WriteLn('AI  > ', Respuesta);
      except
        on E: Exception do
          WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
      end;
      WriteLn('');

    until False;

    WriteLn('');
    WriteLn('Session ended. Total messages: ', Conn.Messages.Count);

  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
