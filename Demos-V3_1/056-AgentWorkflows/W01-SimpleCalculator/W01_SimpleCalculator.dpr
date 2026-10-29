program W01_SimpleCalculator;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - AgentWorkflows W01: SimpleCalculator
// =============================================================================
// Linear pipeline of 3 nodes configured at design time:
//
//   [Parser:TLLMNode] -> [Calculator:TAIAgentsNode] -> [Formatter:TLLMNode]
//
// El Parser (LLM) extrae la expresion matematica del lenguaje natural.
// El Calculator (OnExecute) evalua la expresion aritmeticamente.
// El Formatter (LLM) redacta la respuesta final en lenguaje natural.
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
  Writeln('Presiona Enter para salir.');
  Readln;
end.
