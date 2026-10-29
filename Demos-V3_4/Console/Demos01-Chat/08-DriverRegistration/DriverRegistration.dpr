program DriverRegistration;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 08-DriverRegistration
// =============================================================================
// Demuestra por qué GetDriversNames() retorna TODOS los providers aunque
// el uses solo mencione uMakerAi.Chat.Ollama explícitamente.
//
// Root cause:
//   uMakerAi.Chat.AiConnection  (interface uses)
//     └─ uMakerAi.Chat.Initializations
//          └─ implementation uses all drivers:
//               OpenAI, Claude, Gemini, Ollama, Groq, DeepSeek, ...
//          Cada uno ejecuta su bloque initialization que llama
//          TAiChatFactory.Instance.RegisterDriver(...)
//
// El import de uMakerAi.Chat.Ollama en el uses del programa es redundante
// (no hace daño, pero no es necesario — Initializations ya lo registra).
//
// Concepts covered:
//   - Cómo funciona el auto-registro de drivers por initialization sections
//   - Por qué TAiChatConnection siempre tiene todos los drivers disponibles
//   - Diferencia entre "qué importé" y "qué quedó registrado"
//   - Cómo usar solo Ollama en runtime aunque todos estén registrados
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  // ── Solo importamos Ollama explícitamente (como en el ejemplo del estudiante)
  // Aun así, GetDriversNames() retornará TODOS los providers.
  // Ver la explicación en la sección PARTE 2 del demo.
  uMakerAi.Chat.Ollama,
  uMakerAI.ParamsRegistry,
  uMakerAi.Tools.Functions;

// =============================================================================
//  PARTE 1: Mostrar todos los drivers registrados
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
//  PARTE 2: Explicar por qué pasa esto
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
//  PARTE 3: Demostrar que aun con todo registrado, solo usamos Ollama
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
    Writeln('  (Nota: este demo no hace la llamada real a Ollama para no');
    Writeln('  requerir que el servidor este corriendo. La configuracion');
    Writeln('  es correcta — solo falta un Ollama local activo.)');
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
