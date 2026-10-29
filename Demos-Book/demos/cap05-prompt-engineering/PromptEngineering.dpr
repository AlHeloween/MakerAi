program PromptEngineering;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 5: Prompt Engineering for Developers
// =============================================================================
// Demonstrates the fundamental prompt engineering techniques applied
// to real software development use cases with MakerAI.
//
// Demonstrates:
//   - Demo 1: Basic prompt vs. CRIFE — the same task with different structures
//             produces radically different responses in quality and format.
//   - Demo 2: Few-shot in the SystemPrompt — teach the format with examples
//             embedded in the behavior; cleaner than pre-seeding the history.
//   - Demo 3: Chain of Thought — "think step by step" improves accuracy
//             in reasoning and calculation tasks.
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

  // Test email to be classified in Demo 1
  EMAIL_EJEMPLO =
    'Subject: URGENT - System down' + #13#10 +
    'Hello, since 9am we cannot access the system. ' +
    'We are 50 blocked users. This causes us losses. ' +
    'We need an immediate solution.';

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Demo 1 — Basic prompt vs. CRIFE
//
//  The same email sent twice with very different prompts.
//  The basic prompt gives an unpredictable, non-parseable result.
//  The CRIFE prompt produces parseable JSON, with defined category and urgency.
// =============================================================================
procedure Demo1_BasicoVsCRIFE(Conn: TAiChatConnection);
var
  R: string;
begin
  Separador('Demo 1 — Basic prompt vs. CRIFE');

  // ── Basic version ─────────────────────────────────────────────────────────
  WriteLn('── Basic prompt (unpredictable result): ──');
  Conn.SystemPrompt.Text := 'You are an assistant.';
  Conn.NewChat;

  R := Conn.AddMessageAndRun(
    'Classify this email: ' + EMAIL_EJEMPLO, 'user', []);
  WriteLn(R);

  // ── CRIFE version ──────────────────────────────────────────────────────────
  WriteLn('');
  WriteLn('── CRIFE prompt (deterministic and parseable result): ──');

  // ROLE + CONTEXT go in SystemPrompt (agent behavior)
  Conn.SystemPrompt.Text :=
    'ROLE: You are an email classification system for a business CRM.' + #13#10 +
    'CONTEXT: You process customer emails and route them to the correct department.' + #13#10 +
    'CONSTRAINTS: Respond ONLY with the specified JSON. ' +
    'No additional text outside the JSON.';
  Conn.NewChat;

  // INSTRUCTION + FORMAT + EXAMPLE go in the user message
  R := Conn.AddMessageAndRun(
    'INSTRUCTION: Classify into exactly ONE category: ' +
    '[TECHNICAL_SUPPORT, BILLING, SALES, COMPLAINT, OTHER]' + #13#10 +
    'FORMAT: {"categoria":"...","urgencia":"HIGH|MEDIUM|LOW","resumen":"max 10 words"}' + #13#10 +
    'EMAIL:' + #13#10 + EMAIL_EJEMPLO,
    'user', []);
  WriteLn(R);

  WriteLn('');
  WriteLn('→ The CRIFE prompt produces JSON parseable directly in Delphi code.');
end;

// =============================================================================
//  Demo 2 — Few-Shot in the SystemPrompt
//
//  Instead of explaining the format in words, show 2-3 real examples.
//  LLMs learn by imitation: a few well-chosen examples > paragraphs of
//  instructions. Examples go in the SystemPrompt to be reused
//  in every NewChat without having to re-inject them.
// =============================================================================
procedure Demo2_FewShot(Conn: TAiChatConnection);
const
  TICKETS: array[0..2] of string = (
    'The home screen looks different since yesterday',
    'I was charged twice on my card this month',
    'I want to add 10 more users to my account'
  );
var
  I: integer;
  R: string;
begin
  Separador('Demo 2 — Few-Shot in the SystemPrompt');

  // The examples are embedded in the behavior; there is no need to re-inject them
  Conn.SystemPrompt.Text :=
    'You are a support ticket classifier. Respond ONLY with JSON.' + #13#10 +
    'Format: {"categoria":"TECHNICAL_SUPPORT|BILLING|SALES|ACCESS|HARDWARE","urgencia":"HIGH|MEDIUM|LOW"}' + #13#10 +
    '' + #13#10 +
    'EXAMPLES:' + #13#10 +
    'Ticket:  "My printer does not print"' + #13#10 +
    'Output:  {"categoria":"HARDWARE","urgencia":"MEDIUM"}' + #13#10 +
    '' + #13#10 +
    'Ticket:  "I cannot access my account"' + #13#10 +
    'Output:  {"categoria":"ACCESS","urgencia":"HIGH"}' + #13#10 +
    '' + #13#10 +
    'Ticket:  "When does my subscription expire?"' + #13#10 +
    'Output:  {"categoria":"BILLING","urgencia":"LOW"}';

  WriteLn('Classifying 3 tickets with few-shot in the SystemPrompt:');
  WriteLn('');

  for I := 0 to High(TICKETS) do
  begin
    Conn.NewChat;   // Each ticket is independent; clean history
    Write('  Ticket ', I + 1, ': "', TICKETS[I], '"');
    R := Conn.AddMessageAndRun(TICKETS[I], 'user', []);
    WriteLn(' → ', R);
  end;

  WriteLn('');
  WriteLn('→ Three calls, three valid JSONs, zero extra text.');
  WriteLn('  The examples in the SystemPrompt act as a format contract.');
end;

// =============================================================================
//  Demo 3 — Chain of Thought
//
//  For reasoning or calculation tasks, asking the model to "think out loud"
//  reduces errors. The phrase "Think step by step" forces an explicit
//  reasoning process before giving the final answer.
// =============================================================================
procedure Demo3_ChainOfThought(Conn: TAiChatConnection);
const
  PROBLEMA =
    'A company has 3 active licenses (Basic plan at $50/month/license). ' +
    'They want to add 2 more licenses. If they switch to the Pro plan ($75/month/license) ' +
    'they get a 20% discount on the new licenses. ' +
    'How much will they pay in total next month with the Pro plan?';
var
  R: string;
begin
  Separador('Demo 3 — Chain of Thought');

  Conn.SystemPrompt.Text :=
    'You are a sales assistant. Respond in Spanish.';

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
    'Think step by step. Show each calculation before giving the total.',
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
