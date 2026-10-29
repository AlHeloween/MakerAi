program W01_SimpleCalculator;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - AgentWorkflows W01: SimpleCalculator
// =============================================================================
// Linear pipeline of 3 nodes configured at design time:
//
//   [Parser:TLLMNode] -> [Calculator:TAIAgentsNode] -> [Formatter:TLLMNode]
//
// The Parser (LLM) extracts the mathematical expression from natural language.
// The Calculator (OnExecute) evaluates the expression arithmetically.
// The Formatter (LLM) writes the final response in natural language.
//
// All components, properties and events are in the DataModule (DFM).
// =============================================================================

uses
  System.SysUtils,
  uDmW01Calculator in 'uDmW01Calculator.pas' {DmW01: TDataModule},
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Claude;

begin
  try
    DmW01 := TDmW01.Create(nil);
    try
      DmW01.RunDemo;
    finally
      DmW01.Free;
    end;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit.');
  Readln;
end.
