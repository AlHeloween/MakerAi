program MultiFunctions;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 02-MultiFunctions
// =============================================================================
// The LLM has access to SEVERAL functions and decides which one(s) to use based on
// context. It can invoke functions in sequence or combine results.
//
// Concepts covered:
//   - Register multiple functions in TAiFunctions
//   - The LLM chains functions automatically (multi-step tool use)
//   - Each function has its own class handler (TFunctionEvent)
//   - A query may require N function calls before responding
//
// Functions in this demo:
//   get_weather(city)                  → clima actual
//   convert_currency(amount, from, to) → conversión de divisa
//   calculate(expression)              → calculadora básica
// =============================================================================

uses
  System.SysUtils,
  System.JSON,
  System.Math,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Messages,
  uMakerAi.Tools.Functions,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Groq;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

// =============================================================================
//  TMultiFunctionsDemo
// =============================================================================
type
  TMultiFunctionsDemo = class
  private
    FAiFunctions: TAiFunctions;

    procedure OnFnGetWeather(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnConvertCurrency(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure OnFnCalculate(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);

    function SimpleCalc(const Expr: String): Double;
    procedure RegisterFunctions;
  public
    procedure Run;
  end;

// =============================================================================
//  Implementaciones de las funciones
// =============================================================================

procedure TMultiFunctionsDemo.OnFnGetWeather(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: String;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Args: TJSONObject;
  City: String;
begin
  Writeln(Format('    ↳ get_weather(%s)', [ToolCall.Arguments]));

  Args := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(Args) then
  try
    City := Args.GetValue<String>('city', 'desconocida');
  finally
    Args.Free;
  end
  else
    City := 'desconocida';

  ToolCall.Response := Format(
    '{"city":"%s","temp_c":24,"condition":"Parcialmente nublado","wind_kmh":15}',
    [City]);
  Handled := True;
end;

procedure TMultiFunctionsDemo.OnFnConvertCurrency(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: String;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
const
  // Tasas aproximadas respecto al USD
  NAMES : array[0..4] of String  = ('USD','MXN','EUR','GBP','CAD');
  RATES : array[0..4] of Double  = (1.0, 17.5, 0.92, 0.79, 1.36);
var
  Args      : TJSONObject;
  Amount    : Double;
  FromCur   : String;
  ToCur     : String;
  FromRate  : Double;
  ToRate    : Double;
  Converted : Double;
  I         : Integer;
begin
  Writeln(Format('    ↳ convert_currency(%s)', [ToolCall.Arguments]));

  Args := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if not Assigned(Args) then
  begin
    ToolCall.Response := '{"error":"invalid args"}';
    Handled := True;
    Exit;
  end;
  try
    Amount  := Args.GetValue<Double>('amount', 0);
    FromCur := Args.GetValue<String>('from_currency', 'USD');
    ToCur   := Args.GetValue<String>('to_currency', 'MXN');
  finally
    Args.Free;
  end;

  FromRate := 1.0;
  ToRate   := 1.0;
  for I := Low(NAMES) to High(NAMES) do
  begin
    if SameText(NAMES[I], FromCur) then FromRate := RATES[I];
    if SameText(NAMES[I], ToCur)   then ToRate   := RATES[I];
  end;

  Converted := Amount / FromRate * ToRate;

  ToolCall.Response := Format(
    '{"original":%.2f,"from":"%s","to":"%s","converted":%.2f,"rate":%.4f}',
    [Amount, FromCur, ToCur, Converted, ToRate / FromRate]);
  Handled := True;
end;

function TMultiFunctionsDemo.SimpleCalc(const Expr: String): Double;
var
  Parts: TArray<String>;
  A, B : Double;
begin
  Result := 0;
  if Expr.Contains('+') then
  begin
    Parts := Expr.Split(['+']);
    if (Length(Parts) >= 2) and TryStrToFloat(Trim(Parts[0]), A) and
       TryStrToFloat(Trim(Parts[1]), B) then
      Result := A + B;
  end
  else if Expr.Contains('-') then
  begin
    Parts := Expr.Split(['-']);
    if (Length(Parts) >= 2) and TryStrToFloat(Trim(Parts[0]), A) and
       TryStrToFloat(Trim(Parts[1]), B) then
      Result := A - B;
  end
  else if Expr.Contains('*') then
  begin
    Parts := Expr.Split(['*']);
    if (Length(Parts) >= 2) and TryStrToFloat(Trim(Parts[0]), A) and
       TryStrToFloat(Trim(Parts[1]), B) then
      Result := A * B;
  end
  else if Expr.Contains('/') then
  begin
    Parts := Expr.Split(['/']);
    if (Length(Parts) >= 2) and TryStrToFloat(Trim(Parts[0]), A) and
       TryStrToFloat(Trim(Parts[1]), B) and (B <> 0) then
      Result := A / B;
  end;
end;

procedure TMultiFunctionsDemo.OnFnCalculate(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: String;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Args  : TJSONObject;
  Expr  : String;
  Res   : Double;
begin
  Writeln(Format('    ↳ calculate(%s)', [ToolCall.Arguments]));

  Args := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if Assigned(Args) then
  try
    Expr := Args.GetValue<String>('expression', '0');
  finally
    Args.Free;
  end
  else
    Expr := '0';

  Res := SimpleCalc(Expr);
  ToolCall.Response := Format('{"expression":"%s","result":%s}',
    [Expr, FloatToStr(RoundTo(Res, -4))]);
  Handled := True;
end;

// =============================================================================
//  Registra las 3 funciones en FAiFunctions
// =============================================================================
procedure TMultiFunctionsDemo.RegisterFunctions;
var
  LFn   : TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  // ── get_weather ─────────────────────────────────────────────────────────────
  LFn := FAiFunctions.Functions.AddFunction('get_weather', True, OnFnGetWeather);
  LFn.Description.Text := 'Gets the current weather of a city: temperature, condition and wind.';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'city'; LParam.ParamType := ptString; LParam.Required := True;
  LParam.Description.Text := 'Name of the city';

  // ── convert_currency ────────────────────────────────────────────────────────
  LFn := FAiFunctions.Functions.AddFunction('convert_currency', True, OnFnConvertCurrency);
  LFn.Description.Text := 'Converts an amount from one currency to another. Supports USD, MXN, EUR, GBP, CAD.';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'amount'; LParam.ParamType := ptFloat; LParam.Required := True;
  LParam.Description.Text := 'Amount to convert';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'from_currency'; LParam.ParamType := ptString; LParam.Required := True;
  LParam.Description.Text := 'Source currency (USD, MXN, EUR...)';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'to_currency'; LParam.ParamType := ptString; LParam.Required := True;
  LParam.Description.Text := 'Target currency';

  // ── calculate ───────────────────────────────────────────────────────────────
  LFn := FAiFunctions.Functions.AddFunction('calculate', True, OnFnCalculate);
  LFn.Description.Text := 'Evaluates a simple mathematical expression such as "15 + 27" or "100 * 3.14".';
  LParam := LFn.Parameters.Add;
  LParam.Name := 'expression'; LParam.ParamType := ptString; LParam.Required := True;
  LParam.Description.Text := 'Mathematical expression to calculate';
end;

// =============================================================================
//  Run
// =============================================================================
procedure TMultiFunctionsDemo.Run;
var
  Conn: TAiChatConnection;
  Res : String;
begin
  Writeln('=== MultiFunctions ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln('Available functions: get_weather, convert_currency, calculate');
  Writeln;

  FAiFunctions := TAiFunctions.Create(nil);
  try
    RegisterFunctions;

    Conn := TAiChatConnection.Create(nil);
    try
      Conn.DriverName := DRIVER;
      Conn.Model      := MODEL;
      Conn.Params.Values['ApiKey']       := API_KEY;
      Conn.Params.Values['Asynchronous'] := 'False';
      Conn.Params.Values['Max_Tokens']   := '1024';
      Conn.Params.Values['Tool_Active']  := 'True';
      Conn.AiFunctions := FAiFunctions;

      Conn.SystemPrompt.Text :=
        'You are an intelligent assistant with access to tools. ' +
        'Use them when the user needs them. Respond in Spanish.';

      // ── P1: one function ────────────────────────────────────────────────────
      Writeln(StringOfChar('-', 60));
      Writeln('P1 — One function: "What is 347 × 28?"');
      Res := Conn.AddMessageAndRun('How much is 347 × 28?', 'user', []);
      Writeln('R: ', Res);
      Conn.Messages.Clear;
      Writeln;

      // ── P2: two functions ──────────────────────────────────────────────────
      Writeln(StringOfChar('-', 60));
      Writeln('P2 — Two functions: weather + currency conversion');
      Res := Conn.AddMessageAndRun(
        '¿Cómo está el clima en Guadalajara y cuánto son 500 USD en MXN?',
        'user', []);
      Writeln('R: ', Res);
      Conn.Messages.Clear;
      Writeln;

      // ── P3: chained ────────────────────────────────────────────────────
      Writeln(StringOfChar('-', 60));
      Writeln('P3 — Chained: temperature conversion + currency conversion');
      Res := Conn.AddMessageAndRun(
        'Si en Ciudad de México hay 18°C, ¿cuánto es eso en Fahrenheit? ' +
        '(usa calculate: F = 18 * 9/5 + 32, es decir 18 * 1.8 + 32). ' +
        'Además, ¿cuántos euros son 1800 MXN?',
        'user', []);
      Writeln('R: ', Res);

    finally
      Conn.Free;
    end;
  finally
    FAiFunctions.Free;
  end;
end;

// =============================================================================
//  Punto de entrada
// =============================================================================
begin
  try
    with TMultiFunctionsDemo.Create do
    try
      Run;
    finally
      Free;
    end;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
