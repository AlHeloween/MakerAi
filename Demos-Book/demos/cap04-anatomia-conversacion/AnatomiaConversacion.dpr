program AnatomiaConversacion;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 4: Anatomy of a Conversation
// =============================================================================
// Ilustra los mecanismos fundamentales de la gestión de conversaciones con LLMs.
// Un modelo no tiene memoria propia: "recuerda" porque recibe el historial
// completo en cada llamada. El desarrollador controla ese historial.
//
// Demonstrates:
//   - Demo 1: Conversación multi-turno — 3 turnos donde cada pregunta de
//             seguimiento aprovecha el contexto de los turnos anteriores.
//   - Demo 2: Pre-siembra con AddMessage — inyectar ejemplos (few-shot) al
//             historial SIN llamar al modelo. Luego una sola llamada clasifica.
//   - Demo 3: Persistencia del historial — guardar a JSON, limpiar memoria
//             y recargar para continuar la conversación donde se dejó.
//
// API used:
//   Conn.AddMessageAndRun(text, role, [])  → adds a message and calls the model
//   Conn.AddMessage(text, role)            → adds to history WITHOUT calling
//   Conn.Messages.Count                   → accumulated messages
//   Conn.NewChat                          → clears history (frees objects)
//   Conn.Messages.SaveToFile(path)        → persists history in JSON
//   Conn.Messages.LoadFromFile(path)      → restores history from JSON
//   Conn.Prompt_tokens / Completion_tokens / Total_tokens → token usage
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

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Demo 1 — Conversación multi-turno con contexto
//
//  En cada turno el modelo recibe el historial completo:
//    Turn 1: [system] + [user T1]
//    Turn 2: [system] + [user T1] + [assistant T1] + [user T2]
//    Turn 3: [system] + [user T1] + [assistant T1] + ... + [user T3]
//
//  That is why it can answer "¿Cómo lo depuro?" without repeating the context.
// =============================================================================
procedure Demo1_MultiTurno(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 1 — Multi-turn conversation');

  Conn.SystemPrompt.Text :=
    'Eres un asistente de soporte técnico Delphi. Responde en español, conciso.';
  Conn.NewChat;   // NewChat libera correctamente los objetos anteriores

  WriteLn('[Turn 1] "Mi aplicación se cuelga al iniciar"');
  R := Conn.AddMessageAndRun('Mi aplicación se cuelga al iniciar', 'user', []);
  WriteLn('          Asistente: ', R);
  WriteLn('          [Historial: ', Conn.Messages.Count, ' mensajes]');

  WriteLn('');
  WriteLn('[Turn 2] "Es Delphi 12, error EAccessViolation"');
  R := Conn.AddMessageAndRun('Es Delphi 12, error EAccessViolation', 'user', []);
  WriteLn('          Asistente: ', R);
  WriteLn('          [Historial: ', Conn.Messages.Count, ' mensajes]');

  WriteLn('');
  WriteLn('[Turn 3] "¿Cómo lo depuro?" — without repeating the context');
  R := Conn.AddMessageAndRun('¿Cómo lo depuro?', 'user', []);
  WriteLn('          Asistente: ', R);
  WriteLn('          [Historial: ', Conn.Messages.Count, ' mensajes |',
          ' Tokens entrada: ', Conn.Prompt_tokens,
          ', salida: ', Conn.Completion_tokens,
          ', total: ', Conn.Total_tokens, ']');
end;

// =============================================================================
//  Demo 2 — Pre-siembra con AddMessage (few-shot conversacional)
//
//  AddMessage agrega mensajes al historial SIN llamar al modelo.
//  Patrón: inyectar 2-3 pares ejemplo/respuesta → luego preguntar real.
//  El modelo ya "conoce" el formato sin necesidad de explicárselo.
// =============================================================================
procedure Demo2_FewShot(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 2 — Pre-seeding with AddMessage (few-shot)');

  Conn.SystemPrompt.Text :=
    'Eres un clasificador de tickets de soporte. ' +
    'Responde ÚNICAMENTE con JSON válido: {"categoria":"...","urgencia":"ALTA|MEDIA|BAJA"}.';
  Conn.NewChat;

  // AddMessage: adds to history WITHOUT inference cost
  WriteLn('Injecting 2 classification examples (without calling the model)...');
  Conn.AddMessage('Mi impresora no imprime', 'user');
  Conn.AddMessage('{"categoria":"HARDWARE","urgencia":"MEDIA"}', 'assistant');
  Conn.AddMessage('No puedo acceder a mi cuenta', 'user');
  Conn.AddMessage('{"categoria":"ACCESO","urgencia":"ALTA"}', 'assistant');
  WriteLn('[History: ', Conn.Messages.Count, ' messages — these are the examples]');

  // First and only real call to the model: it already knows the expected format
  WriteLn('');
  WriteLn('Classifying: "La aplicación se cierra al generar reportes PDF"');
  R := Conn.AddMessageAndRun(
    'La aplicación se cierra sola al generar reportes PDF', 'user', []);
  WriteLn('Response   : ', R);
  WriteLn('[History  : ', Conn.Messages.Count, ' messages in total]');
end;

// =============================================================================
//  Demo 3 — Persistencia del historial (save / load)
//
//  Guarda la conversación en JSON, limpia la memoria y la recarga para
//  continuar el hilo exactamente donde se dejó — como si no hubiera parado.
// =============================================================================
procedure Demo3_Persistencia(Conn: TAiChatConnection);
const
  ARCHIVO = 'historial_cap04.json';
var
  R: string;
begin
  Separador('Demo 3 — History persistence (save / load)');

  Conn.SystemPrompt.Text :=
    'Eres un asistente amable. Responde en español, una sola oración.';
  Conn.NewChat;

  // Construir historial con 2 turnos
  Conn.AddMessageAndRun('¿Cuál es la capital de Francia?', 'user', []);
  Conn.AddMessageAndRun('¿Y cuántos habitantes tiene?', 'user', []);
  WriteLn('History created with ', Conn.Messages.Count, ' messages.');

  // Save to disk
  Conn.Messages.SaveToFile(ARCHIVO);
  WriteLn('Saved to: ', ARCHIVO);

  // Clear and verify the context was lost
  Conn.NewChat;
  WriteLn('After NewChat — messages in memory: ', Conn.Messages.Count);

  // Restore from disk
  Conn.Messages.LoadFromFile(ARCHIVO);
  WriteLn('After LoadFromFile — messages restored: ', Conn.Messages.Count);

  // Continue the conversation with full context
  WriteLn('');
  WriteLn('Continuing with restored context: "¿Y el río que la cruza?"');
  R := Conn.AddMessageAndRun('¿Y el río que la cruza?', 'user', []);
  WriteLn('Response: ', R);
  WriteLn('[The model answered with the context of the 2 previous turns]');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
begin
  WriteLn('=== MakerAI — Chapter 4: Anatomy of a Conversation ===');
  WriteLn('Driver: ', DRIVER, ' | Model: ', MODEL);

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';

    Demo1_MultiTurno(Conn);
    Demo2_FewShot(Conn);
    Demo3_Persistencia(Conn);

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
