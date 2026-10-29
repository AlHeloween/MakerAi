program TestDebateConsole;

{$APPTYPE CONSOLE}

// =============================================================================
// Test de consola para diagnosticar uDmDebate.
// Crea el DataModule, conecta los callbacks e imprime todo en stdout.
// Usa CheckSynchronize para procesar los TThread.Queue pendientes.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude,
  uMakerAi.Agents.Node.LLM,
  uDmDebate in 'uDmDebate.pas' {DmDebate: TDataModule};

type
  // Wrapper needed because TDebateLogEvent / TDebateFinishedEvent are 'of object'
  TConsoleOut = class
  private
    FFinished : Boolean;
    FOutput   : string;
  public
    procedure OnLog(const Value: string);
    procedure OnFinished(const Value: string);
    property Finished : Boolean read FFinished;
    property Output   : string  read FOutput;
  end;

procedure TConsoleOut.OnLog(const Value: string);
begin
  Writeln(Value);
end;

procedure TConsoleOut.OnFinished(const Value: string);
begin
  FOutput   := Value;
  FFinished := True;
end;

// ---------------------------------------------------------------------------

var
  Dm      : TDmDebate;
  Console : TConsoleOut;
  Topic   : string;

begin
  try
    Topic := 'Artificial Intelligence will replace most human jobs by 2040';

    Writeln('=== TestDebateConsole ===');
    Writeln('Topic: ', Topic);
    Writeln(StringOfChar('-', 60));

    Console := TConsoleOut.Create;
    Dm      := TDmDebate.Create(nil);
    try
      Dm.OnLog      := Console.OnLog;
      Dm.OnFinished := Console.OnFinished;

      Writeln('[INFO] Starting debate...');
      Dm.RunDebate(Topic);

      // Esperar resultado procesando TThread.Queue pendientes
      Writeln('[INFO] Waiting for result (max 5 min)...');
      var TimeoutMs := 5 * 60 * 1000;  // 5 minutos
      var Elapsed   := 0;
      while (not Console.Finished) and (Elapsed < TimeoutMs) do
      begin
        CheckSynchronize(200);
        Sleep(100);
        Inc(Elapsed, 300);
      end;

      if Console.Finished then
      begin
        Writeln;
        Writeln(StringOfChar('=', 60));
        Writeln('=== FINAL VERDICT ===');
        Writeln(Console.Output);
      end
      else
        Writeln('[TIMEOUT] The debate did not finish within the expected time.');

    finally
      Dm.Free;
      Console.Free;
    end;

  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ' - ', E.Message);
    end;
  end;

  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
