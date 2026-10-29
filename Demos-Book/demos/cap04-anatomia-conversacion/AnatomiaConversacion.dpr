program AnatomiaConversacion;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 4: Anatomy of a Conversation
// =============================================================================
// Illustrates the fundamental mechanisms of conversation management with LLMs.
// A model has no memory of its own: it "remembers" because it receives the
// full history on every call. The developer controls that history.
//
// Demonstrates:
//   - Demo 1: Multi-turn conversation — 3 turns where each follow-up question
//             leverages the context of previous turns.
//   - Demo 2: Pre-seeding with AddMessage — inject examples (few-shot) into
//             history WITHOUT calling the model. Then a single call classifies.
//   - Demo 3: History persistence — save to JSON, clear memory
//             and reload to continue the conversation where it left off.
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
//  Demo 1 — Multi-turn conversation with context
//
//  On each turn the model receives the full history:
//    Turn 1: [system] + [user T1]
//    Turn 2: [system] + [user T1] + [assistant T1] + [user T2]
//    Turn 3: [system] + [user T1] + [assistant T1] + ... + [user T3]
//
//  That is why it can answer "How do I debug it?" without repeating the context.
// =============================================================================
procedure Demo1_MultiTurno(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 1 — Multi-turn conversation');

  Conn.SystemPrompt.Text :=
    'You are a Delphi technical support assistant. Respond in Spanish, concisely.';
  Conn.NewChat;   // NewChat properly frees previous objects

  WriteLn('[Turn 1] "My application hangs on startup"');
  R := Conn.AddMessageAndRun('My application hangs on startup', 'user', []);
  WriteLn('          Assistant: ', R);
  WriteLn('          [History: ', Conn.Messages.Count, ' messages]');

  WriteLn('');
  WriteLn('[Turn 2] "It''s Delphi 12, error EAccessViolation"');
  R := Conn.AddMessageAndRun('It''s Delphi 12, error EAccessViolation', 'user', []);
  WriteLn('          Assistant: ', R);
  WriteLn('          [History: ', Conn.Messages.Count, ' messages]');

  WriteLn('');
  WriteLn('[Turn 3] "How do I debug it?" — without repeating the context');
  R := Conn.AddMessageAndRun('How do I debug it?', 'user', []);
  WriteLn('          Assistant: ', R);
  WriteLn('          [History: ', Conn.Messages.Count, ' messages |',
          ' Input tokens: ', Conn.Prompt_tokens,
          ', output: ', Conn.Completion_tokens,
          ', total: ', Conn.Total_tokens, ']');
end;

// =============================================================================
//  Demo 2 — Pre-seeding with AddMessage (conversational few-shot)
//
//  AddMessage adds messages to history WITHOUT calling the model.
//  Pattern: inject 2-3 example/response pairs → then ask the real question.
//  The model already "knows" the format without needing it explained.
// =============================================================================
procedure Demo2_FewShot(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 2 — Pre-seeding with AddMessage (few-shot)');

  Conn.SystemPrompt.Text :=
    'You are a support ticket classifier. ' +
    'Respond ONLY with valid JSON: {"categoria":"...","urgencia":"ALTA|MEDIA|BAJA"}.';
  Conn.NewChat;

  // AddMessage: adds to history WITHOUT inference cost
  WriteLn('Injecting 2 classification examples (without calling the model)...');
  Conn.AddMessage('My printer does not print', 'user');
  Conn.AddMessage('{"categoria":"HARDWARE","urgencia":"MEDIA"}', 'assistant');
  Conn.AddMessage('I cannot access my account', 'user');
  Conn.AddMessage('{"categoria":"ACCESO","urgencia":"ALTA"}', 'assistant');
  WriteLn('[History: ', Conn.Messages.Count, ' messages — these are the examples]');

  // First and only real call to the model: it already knows the expected format
  WriteLn('');
  WriteLn('Classifying: "The application closes when generating PDF reports"');
  R := Conn.AddMessageAndRun(
    'The application closes by itself when generating PDF reports', 'user', []);
  WriteLn('Response   : ', R);
  WriteLn('[History  : ', Conn.Messages.Count, ' messages in total]');
end;

// =============================================================================
//  Demo 3 — History persistence (save / load)
//
//  Saves the conversation to JSON, clears memory and reloads it to
//  continue the thread exactly where it left off — as if it never stopped.
// =============================================================================
procedure Demo3_Persistencia(Conn: TAiChatConnection);
const
  ARCHIVO = 'historial_cap04.json';
var
  R: string;
begin
  Separador('Demo 3 — History persistence (save / load)');

  Conn.SystemPrompt.Text :=
    'You are a friendly assistant. Respond in Spanish, one sentence.';
  Conn.NewChat;

  // Build history with 2 turns
  Conn.AddMessageAndRun('What is the capital of France?', 'user', []);
  Conn.AddMessageAndRun('And how many inhabitants does it have?', 'user', []);
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
  WriteLn('Continuing with restored context: "And the river that crosses it?"');
  R := Conn.AddMessageAndRun('And the river that crosses it?', 'user', []);
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
