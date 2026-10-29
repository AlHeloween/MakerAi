program AdvancedParams;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 05-AdvancedParams
// =============================================================================
// Exploration of all advanced parameters of TAiChatConnection.
//
// Concepts covered:
//   - Temperature     : controls randomness (0=deterministic, 1=creative)
//   - MaxTokens       : token limit in the response
//   - SystemPrompt    : system instructions (personality, constraints)
//   - ThinkingLevel   : extended reasoning (Claude, Gemini)
//   - ResponseFormat  : free text vs. structured JSON
//   - Stop sequences  : stop generation at a specific token
//   - Timeout         : maximum response wait time
//   - Model switching : change model without recreating the connection
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
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

// Helper para separar secciones en la salida
procedure Section(const Title: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 60));
  Writeln('  ', Title);
  Writeln(StringOfChar('=', 60));
end;

// =============================================================================
//  DEMO 1 — Efecto de Temperature
// =============================================================================
procedure DemoTemperature(Conn: TAiChatConnection);
const
  PROMPT = 'Give me a creative metaphor to describe programming.';
  TEMPS  : array[0..2] of String = ('0.0', '0.7', '1.5');
var
  T   : String;
  Res : String;
begin
  Section('Temperature (0.0 = deterministic  /  1.5 = very creative)');

  for T in TEMPS do
  begin
    Conn.Messages.Clear;
    Conn.Params.Values['Temperature'] := T;
    Res := Conn.AddMessageAndRun(PROMPT, 'user', []);
    Writeln(Format('  Temperature=%s:', [T]));
    Writeln('  ', Res);
    Writeln;
  end;

  // Restaurar valor normal
  Conn.Params.Values['Temperature'] := '0.7';
end;

// =============================================================================
//  DEMO 2 — MaxTokens: respuesta corta vs. larga
// =============================================================================
procedure DemoMaxTokens(Conn: TAiChatConnection);
const
  PROMPT = 'Explain what machine learning is.';
var
  Tokens : String;
  Res    : String;
begin
  Section('MaxTokens (controls the maximum response length)');

  for Tokens in ['50', '200', '1000'] do
  begin
    Conn.Messages.Clear;
    Conn.Params.Values['Max_Tokens'] := Tokens;
    Res := Conn.AddMessageAndRun(PROMPT, 'user', []);
    Writeln(Format('  MaxTokens=%s → %d characters', [Tokens, Length(Res)]));
    Writeln('  ', Copy(Res, 1, 120), '...');
    Writeln;
  end;

  // Restaurar
  Conn.Params.Values['Max_Tokens'] := '1024';
end;

// =============================================================================
//  DEMO 3 — SystemPrompt: cambia la personalidad del LLM
// =============================================================================
procedure DemoSystemPrompt(Conn: TAiChatConnection);
const
  PREGUNTA = '¿Cómo aprender a programar?';
  SISTEMAS : array[0..2] of String = (
    'You are a formal university professor. Use technical terminology.',
    'You are a 14-year-old friend. Speak like a teenager, with emojis.',
    'You are a 17th-century Caribbean pirate. You only speak like a pirate.'
  );
var
  S   : String;
  Res : String;
  I   : Integer;
begin
  Section('SystemPrompt (changes the personality without changing the question)');
  Writeln('  Same question: "', PREGUNTA, '"');
  Writeln;

  I := 1;
  for S in SISTEMAS do
  begin
    Conn.Messages.Clear;
    Conn.SystemPrompt.Text := S;
    Res := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln(Format('  Persona %d: %s', [I, Copy(S, 1, 45), '...']));
    Writeln('  Response: ', Copy(Res, 1, 150));
    Writeln;
    Inc(I);
  end;

  // Restaurar
  Conn.SystemPrompt.Text := 'Always respond in Spanish.';
end;

// =============================================================================
//  DEMO 4 — Respuesta en formato JSON estructurado
// =============================================================================
procedure DemoJSONMode(Conn: TAiChatConnection);
var
  Res    : String;
  JObj   : TJSONObject;
begin
  Section('JSON Mode (response structured as JSON)');

  Conn.Messages.Clear;
  Conn.SystemPrompt.Text :=
    'Always respond in valid JSON, with no additional text. ' +
    'The JSON must have exactly these fields: ' +
    '"nombre", "capital", "poblacion_millones", "idioma_oficial".';

  Conn.Params.Values['Response_format'] := 'json';
  Conn.Params.Values['Max_Tokens']      := '256';

  Res := Conn.AddMessageAndRun('Give me info about Mexico.', 'user', []);
  Writeln('  Raw response:');
  Writeln('  ', Res);

  // Parsear y acceder a campos
  try
    JObj := TJSONObject.ParseJSONValue(Res) as TJSONObject;
    if Assigned(JObj) then
    try
      Writeln;
      Writeln('  Parsed:');
      Writeln('    Name    : ', JObj.GetValue<String>('nombre', '?'));
      Writeln('    Capital   : ', JObj.GetValue<String>('capital', '?'));
      Writeln('    Population : ', JObj.GetValue<Double>('poblacion_millones', 0):0:1, 'M');
      Writeln('    Language    : ', JObj.GetValue<String>('idioma_oficial', '?'));
    finally
      JObj.Free;
    end;
  except
    Writeln('  (Could not parse the JSON)');
  end;

  // Restaurar
  Conn.Params.Values['Response_format'] := '';
end;

// =============================================================================
//  DEMO 5 — ThinkingLevel: razonamiento extendido
//  (Solo soportado en Claude con modelos que soporten extended thinking)
// =============================================================================
procedure DemoThinkingLevel(Conn: TAiChatConnection);
var
  Res: String;
begin
  Section('ThinkingLevel (extended reasoning — Claude)');
  Writeln('  Note: Requires a model that supports Extended Thinking.');
  Writeln('  In models that do not support it, the parameter is ignored.');
  Writeln;

  Conn.Messages.Clear;
  Conn.Params.Values['ThinkingLevel'] := 'tlMedium';  // tlLow, tlMedium, tlHigh
  Conn.Params.Values['Max_Tokens']    := '2048';

  Res := Conn.AddMessageAndRun(
    'Solve step by step: If I have 3 boxes with 4 balls each, ' +
    'and I give away half of all the balls, how many do I have left?',
    'user', []);

  Writeln('  Response (with reasoning):');
  Writeln('  ', Res);

  // Restaurar
  Conn.Params.Values['ThinkingLevel'] := 'tlDefault';
  Conn.Params.Values['Max_Tokens']    := '1024';
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
begin
  Writeln('=== AdvancedParams ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']            := API_KEY;
    Conn.Params.Values['Asynchronous']      := 'False';
    Conn.Params.Values['Max_Tokens']        := '1024';
    Conn.Params.Values['Temperature']       := '0.7';
    Conn.Params.Values['ResponseTimeOut']   := '120000';  // 2 min

    Conn.SystemPrompt.Text := 'Always respond in Spanish.';

    DemoTemperature(Conn);
    DemoMaxTokens(Conn);
    DemoSystemPrompt(Conn);
    DemoJSONMode(Conn);
    DemoThinkingLevel(Conn);

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
