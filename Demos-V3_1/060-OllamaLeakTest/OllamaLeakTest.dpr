program OllamaLeakTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.Chat.Ollama,
  uMakerAi.Chat;

// ---------------------------------------------------------------------------
// Memory leak test with TAiOllamaChat + gemma3:1b
// ReportMemoryLeaksOnShutdown is native in Delphi 10.3+ (integrated FastMM)
// ---------------------------------------------------------------------------

procedure RunTest;
var
  Chat: TAiOllamaChat;
  Respuesta: string;
begin
  Writeln('=== OllamaLeakTest ===');
  Writeln('Model : gemma3:1b');
  Writeln('URL    : http://localhost:11434/');
  Writeln;

  Chat := TAiOllamaChat.Create(nil);
  try
    Chat.Model        := 'gemma3:1b';
    Chat.Url          := 'http://localhost:11434/';
    Chat.Asynchronous := False;
    Chat.Max_tokens   := 256;

    Write('Sending question... ');
    Respuesta := Chat.AddMessageAndRun('¿Cuánto es 2 + 2? Responde en una sola frase.', 'user', []);
    Writeln('OK');
    Writeln;
    Writeln('Model response:');
    Writeln('  ', Respuesta);
    Writeln;
    Writeln('Tokens used:');
    Writeln('  Prompt     : ', Chat.Prompt_tokens);
    Writeln('  Completion : ', Chat.Completion_tokens);
    Writeln('  Total      : ', Chat.Total_tokens);
  finally
    Chat.Free;
    Writeln;
    Writeln('TAiOllamaChat released.');
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;

  try
    RunTest;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' - ', E.Message);
  end;

end.
