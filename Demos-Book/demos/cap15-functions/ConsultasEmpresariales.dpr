program ConsultasEmpresariales;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — Chapter 15: Function Calling
// Demo: Business query system
// =============================================================================
// Shows how the LLM invokes real Delphi functions to answer questions
// business: stock, prices, and current date/time.
//
// Provider: Ollama (local, no API key)
// Model   : qwen2.5:latest   ← supports native function calling
//           llama3.3:latest  ← alternative
//
// Concepts demonstrated:
//   - TAiFunctions with three registered tools
//   - Per-function handler (OnAction) — recommended pattern
//   - ToolCall.Params.Values to read arguments (convenient form)
//   - Interactive loop: the user types questions in natural language
//   - The model decides when and with which arguments to call each function
// =============================================================================

uses
  System.SysUtils,
  System.StrUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Messages,
  uMakerAi.Tools.Functions,
  uMakerAi.Chat.Ollama;   // DriverName = 'Ollama' — auto-registro en el factory

const
  DRIVER = 'Ollama';
  MODEL  = 'gemma4:e4b';   // Soporta tool calling nativo en Ollama
  // Alternatives if the model is not installed:
  //   'gemma4:e2b'    — lighter
  //   'llama3.2:latest' — if installed with: ollama pull llama3.2
  //   'qwen2.5:latest'  — if installed with: ollama pull qwen2.5

// =============================================================================
//  TConsultasDemo
// =============================================================================
type
  TConsultasDemo = class
  private
    FAiFuncs: TAiFunctions;

    procedure OnFnStock(Sender: TObject; FA: TFunctionActionItem;
      FN: String; TC: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnPrecio(Sender: TObject; FA: TFunctionActionItem;
      FN: String; TC: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnFecha(Sender: TObject; FA: TFunctionActionItem;
      FN: String; TC: TAiToolsFunction; var Handled: Boolean);

    procedure RegistrarFunciones;
  public
    procedure Run;
  end;

// =============================================================================
//  Tool handlers
// =============================================================================

procedure TConsultasDemo.OnFnStock(Sender: TObject; FA: TFunctionActionItem;
  FN: String; TC: TAiToolsFunction; var Handled: Boolean);
var
  Codigo: string;
begin
  Codigo := TC.Params.Values['codigo_producto'];
  WriteLn('  [Tool] ConsultarStock: ', Codigo);

  case IndexText(Codigo, ['PROD001', 'PROD002', 'PROD003']) of
    0: TC.Response := '{"stock":150,"estado":"disponible","ubicacion":"Almacen A"}';
    1: TC.Response := '{"stock":3,"estado":"critico","ubicacion":"Almacen B"}';
    2: TC.Response := '{"stock":0,"estado":"agotado","ubicacion":"N/A"}';
  else
    TC.Response := '{"stock":0,"estado":"no_encontrado"}';
  end;

  Handled := True;
end;

procedure TConsultasDemo.OnFnPrecio(Sender: TObject; FA: TFunctionActionItem;
  FN: String; TC: TAiToolsFunction; var Handled: Boolean);
var
  Codigo: string;
begin
  Codigo := TC.Params.Values['codigo_producto'];
  WriteLn('  [Tool] ConsultarPrecio: ', Codigo);

  case IndexText(Codigo, ['PROD001', 'PROD002', 'PROD003']) of
    0: TC.Response := '{"precio":299.99,"moneda":"USD","descuento_pct":0}';
    1: TC.Response := '{"precio":1250.00,"moneda":"USD","descuento_pct":10}';
    2: TC.Response := '{"precio":89.50,"moneda":"USD","descuento_pct":0}';
  else
    TC.Response := '{"precio":0,"error":"no_encontrado"}';
  end;

  Handled := True;
end;

procedure TConsultasDemo.OnFnFecha(Sender: TObject; FA: TFunctionActionItem;
  FN: String; TC: TAiToolsFunction; var Handled: Boolean);
begin
  WriteLn('  [Tool] ObtenerFechaActual');
  TC.Response := Format('{"fecha":"%s","hora":"%s","dia_semana":"%s"}',
    [FormatDateTime('yyyy-mm-dd', Now),
     FormatDateTime('hh:nn:ss', Now),
     FormatDateTime('dddd', Now)]);
  Handled := True;
end;

// =============================================================================
//  Function registration
// =============================================================================

procedure TConsultasDemo.RegistrarFunciones;
var
  LFn   : TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  // ── ConsultarStock ─────────────────────────────────────────────────────────
  LFn := FAiFuncs.Functions.AddFunction('ConsultarStock', True, OnFnStock);
  LFn.Description.Text :=
    'Queries the available stock of a product given its code. ' +
    'Returns quantity in stock, status (available/critical/out of stock) and location.';
  LParam := LFn.Parameters.Add;
  LParam.Name             := 'codigo_producto';
  LParam.ParamType        := ptString;
  LParam.Required         := True;
  LParam.Description.Text := 'Product code (e.g.: PROD001, PROD002, PROD003)';

  // ── ConsultarPrecio ────────────────────────────────────────────────────────
  LFn := FAiFuncs.Functions.AddFunction('ConsultarPrecio', True, OnFnPrecio);
  LFn.Description.Text :=
    'Gets the sale price of a product in USD. ' +
    'Includes active discount if any.';
  LParam := LFn.Parameters.Add;
  LParam.Name             := 'codigo_producto';
  LParam.ParamType        := ptString;
  LParam.Required         := True;
  LParam.Description.Text := 'Product code';

  // ── ObtenerFechaActual ─────────────────────────────────────────────────────
  LFn := FAiFuncs.Functions.AddFunction('ObtenerFechaActual', True, OnFnFecha);
  LFn.Description.Text :=
    'Gets the current system date and time. ' +
    'Use when the user asks for the date, time, or day of the week.';
  // No parameters
end;

// =============================================================================
//  Run
// =============================================================================

procedure TConsultasDemo.Run;
var
  Conn    : TAiChatConnection;
  Pregunta: string;
  Resp    : string;
begin
  FAiFuncs := TAiFunctions.Create(nil);
  Conn     := TAiChatConnection.Create(nil);
  try
    RegistrarFunciones;

    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'True';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.AiFunctions := FAiFuncs;

    Conn.SystemPrompt.Text :=
      'You are a business assistant. You have access to tools to ' +
      'query stock, prices, and date/time. Use them when the user ' +
      'needs that information. Always respond in Spanish.';

    WriteLn('');
    WriteLn('=== Cap. 15 — Function Calling with Ollama ===');
    WriteLn('Driver : ', DRIVER);
    WriteLn('Model   : ', MODEL);
    WriteLn('Tools  : ConsultarStock, ConsultarPrecio, ObtenerFechaActual');
    WriteLn('Available products: PROD001, PROD002, PROD003');
    WriteLn('Type "exit" to finish.');
    WriteLn('');

    repeat
      Write('You > ');
      ReadLn(Pregunta);
      Pregunta := Trim(Pregunta);

      if Pregunta = '' then Continue;
      if SameText(Pregunta, 'exit') then Break;

      WriteLn('');
      try
        Resp := Conn.AddMessageAndRun(Pregunta, 'user', []);
        WriteLn('AI  > ', Resp);
      except
        on E: Exception do
          WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
      end;
      WriteLn('');

    until False;

  finally
    Conn.Free;
    FAiFuncs.Free;
  end;
end;

// =============================================================================
begin
  try
    with TConsultasDemo.Create do
    try
      Run;
    finally
      Free;
    end;
  except
    on E: Exception do
      WriteLn('ERROR FATAL: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
