program PromptEngineering;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 5: Prompt Engineering for Developers
// =============================================================================
// Demuestra las técnicas fundamentales de prompt engineering aplicadas
// a casos de uso reales de desarrollo de software con MakerAI.
//
// Demonstrates:
//   - Demo 1: Prompt básico vs. CRIFE — el mismo task con estructuras distintas
//             produce respuestas radicalmente diferentes en calidad y formato.
//   - Demo 2: Few-shot en el SystemPrompt — enseñar el formato con ejemplos
//             embebidos en el behavior; más limpio que pre-sembrar el historial.
//   - Demo 3: Chain of Thought — "piensa paso a paso" mejora la precisión
//             en tareas de razonamiento y cálculo.
//
// CRIFE technique (professional prompt framework):
//   C — Context:   What situation are we in?
//   R — Role:        Who are you? What expertise do you have?
//   I — Instruction: What exactly must you do?
//   F — Format:    How should the output be?
//   E — Examples/constraints: What is allowed and what is not?
//
// Configure before compiling:
//   Define GROQ_API_KEY as a system environment variable.
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Groq;    // DriverName = 'Groq' — fast and free

const
  DRIVER  = 'Groq';
  MODEL   = 'llama-3.3-70b-versatile';
  API_KEY = '@GROQ_API_KEY';

  // Correo de prueba que se clasificará en Demo 1
  EMAIL_EJEMPLO =
    'Asunto: URGENTE - Sistema caído' + #13#10 +
    'Hola, desde las 9am no podemos acceder al sistema. ' +
    'Somos 50 usuarios bloqueados. Esto nos genera pérdidas. ' +
    'Necesitamos una solución inmediata.';

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Demo 1 — Prompt básico vs. CRIFE
//
//  El mismo correo enviado dos veces con prompts muy distintos.
//  El prompt básico da un resultado impredecible y no parseable.
//  El prompt CRIFE produce JSON parseable, con categoría y urgencia definidas.
// =============================================================================
procedure Demo1_BasicoVsCRIFE(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 1 — Basic prompt vs. CRIFE');

  // ── Basic version ─────────────────────────────────────────────────────────
  WriteLn('── Basic prompt (unpredictable result): ──');
  Conn.SystemPrompt.Text := 'Eres un asistente.';
  Conn.NewChat;

  R := Conn.AddMessageAndRun(
    'Clasifica este correo: ' + EMAIL_EJEMPLO, 'user', []);
  WriteLn(R);

  // ── CRIFE version ──────────────────────────────────────────────────────────
  WriteLn('');
  WriteLn('── CRIFE prompt (deterministic and parseable result): ──');

  // ROLE + CONTEXT go in SystemPrompt (agent behavior)
  Conn.SystemPrompt.Text :=
    'ROL: Eres un sistema de clasificación de correos para un CRM empresarial.' + #13#10 +
    'CONTEXTO: Procesas correos de clientes y los enrutas al departamento correcto.' + #13#10 +
    'RESTRICCIONES: Responde ÚNICAMENTE con el JSON especificado. ' +
    'Sin texto adicional fuera del JSON.';
  Conn.NewChat;

  // INSTRUCTION + FORMAT + EXAMPLE go in the user message
  R := Conn.AddMessageAndRun(
    'INSTRUCCIÓN: Clasifica en exactamente UNA categoría: ' +
    '[SOPORTE_TECNICO, FACTURACION, VENTAS, QUEJA, OTRO]' + #13#10 +
    'FORMATO: {"categoria":"...","urgencia":"ALTA|MEDIA|BAJA","resumen":"max 10 palabras"}' + #13#10 +
    'CORREO:' + #13#10 + EMAIL_EJEMPLO,
    'user', []);
  WriteLn(R);

  WriteLn('');
  WriteLn('→ The CRIFE prompt produces JSON parseable directly in Delphi code.');
end;

// =============================================================================
//  Demo 2 — Few-Shot en el SystemPrompt
//
//  En lugar de explicar el formato con palabras, mostrar 2-3 ejemplos reales.
//  Los LLM aprenden por imitación: pocos ejemplos bien elegidos > párrafos de
//  instrucciones. Los ejemplos van en el SystemPrompt para reutilizarse
//  en cada NewChat sin tener que reinyectarlos.
// =============================================================================
procedure Demo2_FewShot(Conn: TAiChatConnection);
const
  TICKETS: array[0..2] of string = (
    'La pantalla de inicio parece diferente desde ayer',
    'Me cobraron dos veces en mi tarjeta este mes',
    'Quiero agregar 10 usuarios más a mi cuenta'
  );
var
  I: integer;
  R: string;
begin
  Separador('Demo 2 — Few-Shot in the SystemPrompt');

  // The examples are embedded in the behavior; there is no need to re-inject them
  Conn.SystemPrompt.Text :=
    'Eres un clasificador de tickets de soporte. Responde SOLO con JSON.' + #13#10 +
    'Formato: {"categoria":"SOPORTE_TECNICO|FACTURACION|VENTAS|ACCESO|HARDWARE","urgencia":"ALTA|MEDIA|BAJA"}' + #13#10 +
    '' + #13#10 +
    'EJEMPLOS:' + #13#10 +
    'Ticket:  "Mi impresora no imprime"' + #13#10 +
    'Salida:  {"categoria":"HARDWARE","urgencia":"MEDIA"}' + #13#10 +
    '' + #13#10 +
    'Ticket:  "No puedo acceder a mi cuenta"' + #13#10 +
    'Salida:  {"categoria":"ACCESO","urgencia":"ALTA"}' + #13#10 +
    '' + #13#10 +
    'Ticket:  "¿Cuándo vence mi suscripción?"' + #13#10 +
    'Salida:  {"categoria":"FACTURACION","urgencia":"BAJA"}';

  WriteLn('Classifying 3 tickets with few-shot in the SystemPrompt:');
  WriteLn('');

  for I := 0 to High(TICKETS) do
  begin
    Conn.NewChat;   // Cada ticket es independiente; historial limpio
    Write('  Ticket ', I + 1, ': "', TICKETS[I], '"');
    R := Conn.AddMessageAndRun(TICKETS[I], 'user', []);
    WriteLn(' → ', R);
  end;

  WriteLn('');
  WriteLn('→ Three calls, three valid JSONs, zero extra text.');
  WriteLn('  The examples in the SystemPrompt act as a format contract.');
end;

// =============================================================================
//  Demo 3 — Chain of Thought (Cadena de Pensamiento)
//
//  Para tareas de razonamiento o cálculo, pedir al modelo que "piense en voz
//  alta" reduce errores. La frase "Piensa paso a paso" fuerza un proceso de
//  razonamiento explícito antes de dar la respuesta final.
// =============================================================================
procedure Demo3_ChainOfThought(Conn: TAiChatConnection);
const
  PROBLEMA =
    'Una empresa tiene 3 licencias activas (plan Básico a $50/mes/licencia). ' +
    'Quieren agregar 2 licencias más. Si pasan al plan Pro ($75/mes/licencia) ' +
    'obtienen un 20% de descuento en las nuevas licencias. ' +
    '¿Cuánto pagarán en total el próximo mes con el plan Pro?';
var
  R: string;
begin
  Separador('Demo 3 — Chain of Thought');

  Conn.SystemPrompt.Text :=
    'Eres un asistente de ventas. Responde en español.';

  // ── Without Chain of Thought ───────────────────────────────────────────────────
  WriteLn('── Without Chain of Thought (direct answer): ──');
  Conn.NewChat;
  R := Conn.AddMessageAndRun(PROBLEMA, 'user', []);
  WriteLn(R);

  // ── With Chain of Thought ───────────────────────────────────────────────────
  WriteLn('');
  WriteLn('── With Chain of Thought ("think step by step"): ──');
  Conn.NewChat;
  R := Conn.AddMessageAndRun(
    PROBLEMA + #13#10#13#10 +
    'Piensa paso a paso. Muestra cada cálculo antes de dar el total.',
    'user', []);
  WriteLn(R);

  WriteLn('');
  WriteLn('→ Chain of Thought exposes the reasoning and makes errors easier to detect.');
  WriteLn('  Useful in: price calculations, logic validation, data debugging.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
begin
  WriteLn('=== MakerAI — Chapter 5: Prompt Engineering ===');
  WriteLn('Driver: ', DRIVER, ' | Model: ', MODEL);

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '600';

    Demo1_BasicoVsCRIFE(Conn);
    Demo2_FewShot(Conn);
    Demo3_ChainOfThought(Conn);

    WriteLn('');
    WriteLn(StringOfChar('=', 62));
    WriteLn('  Demo completed.');
    WriteLn(StringOfChar('=', 62));
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
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
