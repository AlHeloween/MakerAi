program DriverRegistration;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 08-DriverRegistration
// =============================================================================
// Demonstrates why GetDriversNames() returns ALL providers even though
// uses only explicitly mentions uMakerAi.Chat.Ollama.
//
// Root cause:
//   uMakerAi.Chat.AiConnection  (interface uses)
//     └─ uMakerAi.Chat.Initializations
//          └─ implementation uses all drivers:
//               OpenAI, Claude, Gemini, Ollama, Groq, DeepSeek, ...
//          Each one executes its initialization block that calls
//          TAiChatFactory.Instance.RegisterDriver(...)
//
// The import of uMakerAi.Chat.Ollama in the program's uses clause is redundant
// (it does no harm, but it is not necessary — Initializations already registers it).
//
// Concepts covered:
//   - How driver auto-registration works through initialization sections
//   - Why TAiChatConnection always has all drivers available
//   - Difference between "what I imported" and "what ended up registered"
//   - How to use only Ollama at runtime even when all are registered
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  // ── We only import Ollama explicitly (as in the student's example)
  // Even so, GetDriversNames() will return ALL providers.
  // See the explanation in PART 2 of the demo.
  uMakerAi.Chat.Ollama,
  uMakerAI.ParamsRegistry,
  uMakerAi.Tools.Functions;

// =============================================================================
//  PART 1: Show all registered drivers
// =============================================================================

procedure MostrarDriversRegistrados;
var
  Conn    : TAiChatConnection;
  Drivers : TStringList;
  i       : Integer;
begin
  Writeln('=== PART 1: Drivers registered in the factory ===');
  Writeln;
  Writeln('  The program''s uses clause only explicitly declares: uMakerAi.Chat.Ollama');
  Writeln('  Even so, the registered drivers are:');
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Drivers := Conn.GetDriversNames;
    try
      for i := 0 to Drivers.Count - 1 do
        Writeln('    [', i + 1, '] ', Drivers[i]);
      Writeln;
      Writeln('  Total: ', Drivers.Count, ' registered drivers.');
    finally
      Drivers.Free;
    end;
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  PART 2: Explain why this happens
// =============================================================================

procedure ExplicarCausa;
begin
  Writeln;
  Writeln('=== PART 2: Why does this happen? ===');
  Writeln;
  Writeln('  Each driver auto-registers in its own initialization block:');
  Writeln;
  Writeln('  Your program');
  Writeln('    uses uMakerAi.Chat.Ollama');
  Writeln('      -> initialization: TAiChatFactory.RegisterDriver(TAiOllamaChat)');
  Writeln('         = only Ollama remains in the list');
  Writeln;
  Writeln('  If you add more drivers to uses, each one registers:');
  Writeln('    uses uMakerAi.Chat.Ollama, uMakerAi.Chat.OpenAi, uMakerAi.Chat.Gemini');
  Writeln('      -> list: Ollama, OpenAi, Gemini');
  Writeln;
  Writeln('  If you want ALL drivers at once, add the convention unit:');
  Writeln('    uses uMakerAi.Chat.Initializations');
  Writeln('      -> loads all drivers + configures params for specific models');
  Writeln('         (qwen3 reasoning, gemma3 vision, o3 thinking level, etc.)');
end;

// =============================================================================
//  PART 3: Demonstrate that even with everything registered, we only use Ollama
// =============================================================================

procedure DemostrarUsoSoloOllama;
var
  Conn: TAiChatConnection;
begin
  Writeln;
  Writeln('=== PART 3: Use only Ollama even when all are registered ===');
  Writeln;
  Writeln('  All registered drivers do not mean all are used.');
  Writeln('  With DriverName := ''Ollama'' only Ollama processes your messages.');
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := 'Ollama';
    Conn.Model      := 'llama3.2:latest';
    Conn.Params.Values['ApiKey']       := '';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';
    Conn.SystemPrompt.Text             := 'Responde siempre muy brevemente, en una frase.';

    Writeln('  Active driver: ', Conn.DriverName);
    Writeln('  Active model: ', Conn.Model);
    Writeln;
    Writeln('  (Note: this demo does not make the real call to Ollama so as not');
    Writeln('  to require the server to be running. The configuration');
    Writeln('  is correct — only a local active Ollama is missing.)');
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  MAIN
// =============================================================================

begin
  try
    MostrarDriversRegistrados;
    ExplicarCausa;
    DemostrarUsoSoloOllama;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
