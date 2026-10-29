program DemoMemoryChat;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — DemoMemoryChat
// =============================================================================
// REPL interactivo que demuestra TAiMemory + TAiChatConnection integrados.
//
// Each user prompt:
//   1. Builds a context block from the memory DB
//   2. Injects it automatically into the prompt via PersistentMemory
//   3. Calls the LLM and shows the response in streaming
//   4. If AutoStoreMemories=True, stores the original prompt in memory
//
// Comandos especiales:
//   /quit              — salir
//   /new               — new chat session (keeps memory)
//   /stats             — memory DB statistics
//   /memories [query]  — últimas memorias o búsqueda
//   /store <text>     — store memory manually
//   /importance N      — importance for the next /store (1-10, default 5)
//   /debug             — show the context that would be injected into the next prompt
//
// Configure provider and API key with environment variables or at REPL startup.
// =============================================================================

uses
  System.SysUtils,
  // FireDAC SQLite (required by TAiMemory)
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.VCLUI.Wait,
  // Available chat drivers
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Groq,
  uMakerAi.Chat.Ollama,
  // Demo
  uDemoMemoryChat in 'uDemoMemoryChat.pas';

begin
  try
    RunDemo;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
