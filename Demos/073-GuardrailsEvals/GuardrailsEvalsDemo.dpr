program GuardrailsEvalsDemo;

// =============================================================================
// DEMO 073 - Tool-call guardrails and evals framework
// =============================================================================
// Two components that work together to put an AI in production with some
// safety net, without needing an LLM or API keys:
//
//   1. TAiGuardrails : tool-call policy. It is consulted at the choke point of
//                      TAiFunctions.DoCallFunction, so it covers equally
//                      local tools, MCP tools and AutoMCP tools.
//   2. TAiEvalRunner : evals over a generic function(Input): string target,
//                      with deterministic checks and a report for console or CI.
//
// The demo runs three blocks:
//   A. Isolated guardrails -> allowlist, wildcard blocklist, forbidden
//                            argument pattern and programmatic veto.
//   B. Integrated guardrails -> a real tool is registered in TAiFunctions and
//                            it is verified that blocking PREVENTS its execution
//                            (warning is not enough: the handler does not run).
//   C. Evals                -> a deterministic classifier is evaluated and the
//                            report is printed; the exit code reflects whether
//                            all cases passed.
//
// Usage modes:
//   GuardrailsEvalsDemo.exe            -> the three blocks
//   GuardrailsEvalsDemo.exe --json r.json -> also dumps the eval report
//   GuardrailsEvalsDemo.exe --otel     -> exports OTLP traces to localhost:4318
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Math,
  uMakerAi.Guardrails in '..\..\Source\Tools\uMakerAi.Guardrails.pas',
  uMakerAi.Evals in '..\..\Source\Core\uMakerAi.Evals.pas',
  uMakerAi.Tools.Functions,
  uMakerAi.Chat.Messages,
  uMakerAi.Telemetry;

type
  // Framework events are 'of object': they do not accept lambdas, so the
  // handlers live in a class.
  TDemoHandlers = class
  public
    ToolEjecutado: Boolean;
    BloqueosVistos: Integer;
    // Tool real registrado en TAiFunctions
    procedure ToolAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: String;
      ToolCall: TAiToolsFunction; var Handled: Boolean);
    // Guardrails
    procedure GuardBlocked(Sender: TObject; const AToolName, AArguments, AReason: string);
    procedure GuardCheck(Sender: TObject; const AToolName, AArguments: string; var AAllow: Boolean; var AReason: string);
  end;

procedure TDemoHandlers.ToolAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: String;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  // If this runs, the guardrail did NOT do its job.
  ToolEjecutado := True;
  ToolCall.Response := 'The tool ran and deleted the files';
  Handled := True;
end;

procedure TDemoHandlers.GuardBlocked(Sender: TObject; const AToolName, AArguments, AReason: string);
begin
  Inc(BloqueosVistos);
  Writeln(Format('      [OnBlocked] %-18s %s', [AToolName, AReason]));
end;

procedure TDemoHandlers.GuardCheck(Sender: TObject; const AToolName, AArguments: string;
  var AAllow: Boolean; var AReason: string);
var
  Args: string;
begin
  // NOTE: AArguments is the RAW JSON sent by the model, not an already
  // parsed value. In a Windows path the slashes are escaped by JSON
  // ("c:\\windows"), so comparing against 'c:\windows' never triggers.
  // They must be unescaped first. This is the typical error when writing a
  // filter over arguments, and it leaves the guardrail silently useless.
  Args := AArguments.ToLower.Replace('\\', '\');

  // Programmatic veto: the application code has the last word,
  // above the lists. Here: nothing may touch the system folder.
  if Args.Contains('c:\windows') then
  begin
    AAllow := False;
    AReason := 'veto programatico: ruta de sistema';
  end;
end;

// -----------------------------------------------------------------------------

procedure Probar(AGuard: TAiGuardrails; const ATool, AArgs: string);
var
  Reason: string;
begin
  if AGuard.CheckToolCall(ATool, AArgs, Reason) then
    Writeln(Format('   PERMITIDO  %-18s %s', [ATool, AArgs]))
  else
    Writeln(Format('   BLOQUEADO  %-18s %s', [ATool, AArgs]));
end;

// -----------------------------------------------------------------------------
// A. Guardrails en aislado
// -----------------------------------------------------------------------------
procedure BloqueGuardrails(AHandlers: TDemoHandlers);
var
  Guard: TAiGuardrails;
begin
  Writeln('');
  Writeln('== A. Guardrails: tool-call policy ==');
  Writeln('');

  Guard := TAiGuardrails.Create(nil);
  try
    Guard.OnBlocked := AHandlers.GuardBlocked;

    // --- A.1 Blocklist with wildcard masks ---
    Writeln('   A.1 Blocklist: shell_* and borrar_archivo');
    Guard.BlockedTools.Add('shell_*');
    Guard.BlockedTools.Add('borrar_archivo');
    Probar(Guard, 'consultar_saldo', '{}');
    Probar(Guard, 'shell_exec', '{"cmd":"ls"}');
    Probar(Guard, 'borrar_archivo', '{"path":"a.txt"}');
    Writeln('');

    // --- A.2 Strict allowlist: if it is not empty, it wins ---
    Writeln('   A.2 Strict allowlist: only consultar_*');
    Guard.BlockedTools.Clear;
    Guard.AllowedTools.Add('consultar_*');
    Probar(Guard, 'consultar_saldo', '{}');
    Probar(Guard, 'transferir', '{"monto":1000}');
    Writeln('');

    // --- A.3 Forbidden patterns in ARGUMENTS ---
    // The tool name can be harmless while the argument is not.
    Writeln('   A.3 Forbidden pattern in arguments: DROP TABLE');
    Guard.AllowedTools.Clear;
    Guard.BlockedArgPatterns.Add('DROP TABLE');
    Probar(Guard, 'ejecutar_sql', '{"q":"select * from clientes"}');
    Probar(Guard, 'ejecutar_sql', '{"q":"drop table clientes"}'); // case-insensitive
    Writeln('');

    // --- A.4 Programmatic veto ---
    Writeln('   A.4 Programmatic veto via OnCheckToolCall');
    Guard.BlockedArgPatterns.Clear;
    Guard.OnCheckToolCall := AHandlers.GuardCheck;
    Probar(Guard, 'leer_archivo', '{"path":"d:\\datos\\informe.txt"}');
    Probar(Guard, 'leer_archivo', '{"path":"c:\\windows\\system32\\config"}');
    Writeln('');

    Writeln(Format('   Total recorded blocks: %d (BlockedCount=%d)', [AHandlers.BloqueosVistos, Guard.BlockedCount]));
  finally
    Guard.Free;
  end;
end;

// -----------------------------------------------------------------------------
// B. Guardrails integrado en TAiFunctions
// -----------------------------------------------------------------------------
procedure BloqueIntegracion(AHandlers: TDemoHandlers);
var
  Guard: TAiGuardrails;
  Funcs: TAiFunctions;
  Item: TFunctionActionItem;
  ToolCall: TAiToolsFunction;
begin
  Writeln('');
  Writeln('== B. Real integration: the blocked tool does NOT run ==');
  Writeln('');

  Guard := TAiGuardrails.Create(nil);
  Funcs := TAiFunctions.Create(nil);
  ToolCall := TAiToolsFunction.Create;
  try
    // A real tool, with its handler
    Item := Funcs.Functions.Add;
    Item.FunctionName := 'borrar_todo';
    Item.Enabled := True;
    Item.OnAction := AHandlers.ToolAction;

    Guard.BlockedTools.Add('borrar_todo');
    Funcs.Guardrails := Guard; // opt-in: sin esto no hay politica

    AHandlers.ToolEjecutado := False;
    ToolCall.Name := 'borrar_todo';
    ToolCall.Arguments := '{}';

    // This is the choke point used by local tools, MCP and AutoMCP
    Funcs.DoCallFunction(ToolCall);

    Writeln('   Response returned to the LLM:');
    Writeln('     ' + ToolCall.Response);
    if AHandlers.ToolEjecutado then
      Writeln('   FAIL: the tool handler did run')
    else
      Writeln('   OK: the handler NEVER ran, and the LLM received the reason');
  finally
    ToolCall.Free;
    Funcs.Free;
    Guard.Free;
  end;
end;

// -----------------------------------------------------------------------------
// C. Evals
// -----------------------------------------------------------------------------

// The "system under test". In a real case it would be an LLM call, an
// agent or a RAG chain; here it is deterministic so the demo does not depend on
// keys or network.
function ClasificarTicket(const AInput: string): string;
var
  S: string;
begin
  S := AInput.ToLower;
  if S.Contains('invoice') or S.Contains('charge') or S.Contains('payment') then
    Result := 'category: billing'
  else if S.Contains('error') or S.Contains('failure') or S.Contains('not working') then
    Result := 'category: technical support'
  else
    Result := 'category: general';
end;

function BloqueEvals(const AJsonPath: string): Boolean;
var
  Runner: TAiEvalRunner;
  Report: TAiEvalReport;
  Json: TJSONObject;
begin
  Writeln('');
  Writeln('== C. Evals: TAiEvalRunner over a classifier ==');
  Writeln('');

  Runner := TAiEvalRunner.Create(nil);
  try
    Runner.AddCase('clasifica.facturacion')
      .Input('I received a duplicate invoice this month')
      .ExpectContains('billing');

    Runner.AddCase('clasifica.soporte')
      .Input('The application shows an error on startup')
      .ExpectEquals('category: technical support');

    Runner.AddCase('clasifica.general')
      .Input('I wanted to know the opening hours')
      .ExpectContains('general')
      .ExpectNotContains('soporte');

    Runner.AddCase('clasifica.formato')
      .Input('The payment button does not work')
      .ExpectRegex('^category: .+$')
      .ExpectMaxLength(60);

    // Para usar LLM-as-judge basta asignar Runner.Judge := <un TAiChat> y
    // agregar .ExpectJudge('el texto debe...'). Se omite aqui para no exigir
    // una API key.

    Report := Runner.Run(
      function(const AInput: string): string
      begin
        Result := ClasificarTicket(AInput);
      end);
    try
      Writeln(Report.ToText);
      Result := Report.AllPassed;

      if AJsonPath <> '' then
      begin
        Json := Report.ToJSON;
        try
          TFile.WriteAllText(AJsonPath, Json.ToJSON, TEncoding.UTF8);
          Writeln('   Reporte JSON escrito en: ' + AJsonPath);
        finally
          Json.Free;
        end;
      end;
    finally
      Report.Free;
    end;
  finally
    Runner.Free;
  end;
end;

// -----------------------------------------------------------------------------

function ArgValue(const AName: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), AName) then
      Exit(ParamStr(I + 1));
end;

function HasFlag(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AName) then
      Exit(True);
end;

var
  Handlers: TDemoHandlers;
  Telemetry: TAiTelemetry;
  TodoOk: Boolean;

begin
  Telemetry := nil;
  try
    if HasFlag('--otel') then
    begin
      Telemetry := TAiTelemetry.Create(nil);
      Telemetry.ServiceName := 'GuardrailsEvalsDemo';
      Telemetry.Enabled := True;
      Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
    end;

    Writeln('=== DEMO 073: Guardrails and Evals (no LLM, no API keys) ===');

    Handlers := TDemoHandlers.Create;
    try
      BloqueGuardrails(Handlers);
      BloqueIntegracion(Handlers);
      TodoOk := BloqueEvals(ArgValue('--json'));
    finally
      Handlers.Free;
    end;

    Writeln('');
    if TodoOk then
      Writeln('OK: all eval cases passed.')
    else
      Writeln('ATENCION: hay casos de eval fallidos.');

    if Assigned(Telemetry) then
    begin
      Telemetry.Flush;
      Telemetry.Free;
    end;

    ExitCode := IfThen(TodoOk, 0, 1);
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 2;
    end;
  end;
end.
