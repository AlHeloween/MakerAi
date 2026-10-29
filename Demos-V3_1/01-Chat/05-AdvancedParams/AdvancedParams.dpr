program AdvancedParams;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 05-AdvancedParams
// =============================================================================
// Exploration of all advanced parameters of TAiChatConnection.
//
// Conceptos que cubre:
//   - Temperature     : controls randomness (0=deterministic, 1=creative)
//   - MaxTokens       : limit of tokens in the response
//   - SystemPrompt    : system instructions (personality, constraints)
//   - ThinkingLevel   : extended reasoning (Claude, Gemini)
//   - ResponseFormat  : free text vs. structured JSON
//   - Stop sequences  : stop generation at a specific token
//   - Timeout         : maximum wait time for response
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

// Helper to separate sections in the output
procedure Section(const Title: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 60));
  Writeln('  ', Title);
  Writeln(StringOfChar('=', 60));
end;

// =============================================================================
//  DEMO 1 — Temperature effect
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

  // Restore normal value
  Conn.Params.Values['Temperature'] := '0.7';
end;

// =============================================================================
//  DEMO 2 — MaxTokens: short vs. long response
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

  // Restore
  Conn.Params.Values['Max_Tokens'] := '1024';
end;

// =============================================================================
//  DEMO 3 — SystemPrompt: changes the LLM personality
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
  Section('SystemPrompt (changes personality without changing the question)');
  Writeln('  Same question: "', PREGUNTA, '"');
  Writeln;

  I := 1;
  for S in SISTEMAS do
  begin
    Conn.Messages.Clear;
    Conn.SystemPrompt.Text := S;
    Res := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln(Format('  Person %d: %s', [I, Copy(S, 1, 45), '...']));
    Writeln('  Response: ', Copy(Res, 1, 150));
    Writeln;
    Inc(I);
  end;

  // Restore
  Conn.SystemPrompt.Text := 'Always respond in Spanish.';
end;

// =============================================================================
//  DEMO 4 — Response in structured JSON format
// =============================================================================
procedure DemoJSONMode(Conn: TAiChatConnection);
var
  Res    : String;
  JObj   : TJSONObject;
begin
  Section('JSON Mode (structured response as JSON)');

  Conn.Messages.Clear;
  Conn.SystemPrompt.Text :=
    'Responde SIEMPRE en JSON válido, sin texto adicional. ' +
    'The JSON must have exactly these fields: ' +
    '"nombre", "capital", "poblacion_millones", "idioma_oficial".';

  Conn.Params.Values['Response_format'] := 'json';
  Conn.Params.Values['Max_Tokens']      := '256';

  Res := Conn.AddMessageAndRun('Give me info about Mexico.', 'user', []);
  Writeln('  Raw response:');
  Writeln('  ', Res);

  // Parse and access fields
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
    Writeln('  (Could not parse JSON)');
  end;

  // Restore
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
  Writeln('  On models that do not support it, the parameter is ignored.');
  Writeln;

  Conn.Messages.Clear;
  Conn.Params.Values['ThinkingLevel'] := 'tlMedium';  // tlLow, tlMedium, tlHigh
  Conn.Params.Values['Max_Tokens']    := '2048';

  Res := Conn.AddMessageAndRun(
    'Resuelve paso a paso: Si tengo 3 cajas con 4 pelotas cada una, ' +
    'and I give away half of all the balls, how many do I have left?',
    'user', []);

  Writeln('  Response (with reasoning):');
  Writeln('  ', Res);

  // Restore
  Conn.Params.Values['ThinkingLevel'] := 'tlDefault';
  Conn.Params.Values['Max_Tokens']    := '1024';
end;

// =============================================================================
//  Main DEMO
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
