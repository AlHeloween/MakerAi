program MCPElicitationDemo;

// =============================================================================
// DEMO 075 - MCP elicitation (MRTR pattern) from the CLIENT side
// =============================================================================
// Demo 031 shows the server side: a tool that asks for confirmation. This
// shows the other half, which is what must be implemented when MakerAI
// CONSUMES an MCP server: how to respond to that request.
//
// The contract: when a tool returns resultType='input_required', the client
// fires OnInputRequired with the server's inputRequests. The handler must
// fill AInputResponses and set AHandled := True; the client then repeats
// the call automatically, echoing requestState. If nobody handles the
// event, the call ends with input_required unresolved.
//
// Three scenarios, all in-process (server and client in the same exe), no
// LLM or API keys:
//
//   A. The user ACCEPTS   -> the tool executes the operation.
//   B. The user REJECTS   -> the tool does NOT execute and reports it.
//   C. WITHOUT handler    -> the call returns raw input_required; this is
//                           the typical failure when integrating a server that
//                           uses elicitation, and it is worth seeing explicitly.
//
// Usage modes:
//   MCPElicitationDemo.exe          -> the three scenarios
//   MCPElicitationDemo.exe --otel   -> exports OTLP traces to localhost:4318
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  uMakerAi.Core,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Http,
  uMakerAi.MCPClient.Core,
  uMakerAi.Telemetry,
  uTool.Aprobacion in 'uTool.Aprobacion.pas';

const
  PORT = 8285;

type
  // Framework events are 'of object': no lambdas.
  TDemoHandlers = class
  public
    Aceptar: Boolean;        // what the "user" answers
    MensajeRecibido: string; // the question sent by the server
    Invocaciones: Integer;
    procedure InputRequired(Sender: TObject; const AToolName: string;
      AInputRequests, AInputResponses: TJSONObject; var AHandled: Boolean);
  end;

procedure TDemoHandlers.InputRequired(Sender: TObject; const AToolName: string;
  AInputRequests, AInputResponses: TJSONObject; var AHandled: Boolean);
var
  V: TJSONValue;
  Respuesta, Contenido: TJSONObject;
begin
  Inc(Invocaciones);

  // 1. Read what the server asks for. The key ('autorizacion') is chosen by the tool;
  //    in a real client all entries of inputRequests are traversed.
  V := AInputRequests.GetValue('autorizacion');
  if V is TJSONObject then
    MensajeRecibido := TJSONObject(V).GetValue<string>('params.message', '');

  Writeln('      [OnInputRequired] tool="' + AToolName + '"');
  Writeln('      [OnInputRequired] question: ' + MensajeRecibido);

  // 2. Here the real interaction with the user would go (a dialog, a card
  //    in the chat, a notification...). The demo answers automatically.
  Respuesta := TJSONObject.Create;
  if Aceptar then
  begin
    Respuesta.AddPair('action', 'accept');
    Contenido := TJSONObject.Create;
    Contenido.AddPair('confirmar', TJSONBool.Create(True));
    Respuesta.AddPair('content', Contenido);
    Writeln('      [OnInputRequired] the user ACCEPTS');
  end
  else
  begin
    // 'decline' = the user said no. ('cancel' would abort the flow.)
    Respuesta.AddPair('action', 'decline');
    Writeln('      [OnInputRequired] the user REJECTS');
  end;

  // 3. The response is returned under the SAME key used by the server.
  AInputResponses.AddPair('autorizacion', Respuesta);

  // 4. Without this the client does not retry and the call is left half done.
  AHandled := True;
end;

// -----------------------------------------------------------------------------

function TextoDeRespuesta(ARes: TJSONObject): string;
var
  Arr: TJSONArray;
  V: TJSONValue;
  S: string;
begin
  Result := '';
  if not Assigned(ARes) then
    Exit('(no response)');
  // The server builder returns {"content":[{"type":"text","text":"..."}]}
  if ARes.TryGetValue<TJSONArray>('content', Arr) then
    for V in Arr do
      if (V is TJSONObject) and TJSONObject(V).TryGetValue<string>('text', S) then
      begin
        if Result <> '' then
          Result := Result + ' ';
        Result := Result + S;
      end;
  if Result = '' then
    Result := ARes.ToJSON;
end;

procedure Escenario(const ATitulo: string; AServer: TAiMCPHttpServer;
  AHandlers: TDemoHandlers; AUsarHandler, AAceptar: Boolean);
var
  Client: TMCPClientHttp;
  Args, Res: TJSONObject;
  Media: TObjectList<TAiMediaFile>;
begin
  Writeln('');
  Writeln('   --- ' + ATitulo + ' ---');

  Client := TMCPClientHttp.Create(nil);
  Media := TObjectList<TAiMediaFile>.Create(True);
  try
    // The server in this demo publishes RPC at the root of its Endpoint
    Client.Params.Values['RpcEndpointSuffix'] := '';
    Client.Params.Values['InitializeEndpointSuffix'] := '';
    Client.Params.Values['NotificationEndpointSuffix'] := '';
    Client.Params.Values['Timeout'] := '15000';
    Client.Params.Values['URL'] := Format('http://localhost:%d%s', [PORT, AServer.Endpoint]);
    Client.Initialize;

    AHandlers.Aceptar := AAceptar;
    AHandlers.Invocaciones := 0;
    if AUsarHandler then
      Client.OnInputRequired := AHandlers.InputRequired;

    Args := TJSONObject.Create;
    Args.AddPair('monto', '1500 EUR');
    Res := Client.CallTool('autorizar_transferencia', Args, Media);
    try
      Writeln('   result: ' + TextoDeRespuesta(Res));
      Writeln(Format('   times input was requested from the user: %d', [AHandlers.Invocaciones]));
    finally
      Res.Free;
    end;
  finally
    Media.Free;
    Client.Free;
  end;
end;

// -----------------------------------------------------------------------------

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
  Server: TAiMCPHttpServer;
  Handlers: TDemoHandlers;
  Telemetry: TAiTelemetry;

begin
  Telemetry := nil;
  try
    if HasFlag('--otel') then
    begin
      Telemetry := TAiTelemetry.Create(nil);
      Telemetry.ServiceName := 'MCPElicitationDemo';
      Telemetry.Enabled := True;
      Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
    end;

    Writeln('=== DEMO 075: MCP elicitation (MRTR) from the client ===');
    Writeln('');
    Writeln('== In-process MCP server with a tool that requires authorization ==');

    Server := TAiMCPHttpServer.Create(nil);
    Handlers := TDemoHandlers.Create;
    try
      Server.Port := PORT;
      Server.RegisterTool('autorizar_transferencia',
        function: IAiMCPTool
        begin
          Result := TAprobacionTool.Create;
        end);
      Server.Start;
      Writeln(Format('   listening on http://localhost:%d%s', [PORT, Server.Endpoint]));

      Escenario('A. The user ACCEPTS', Server, Handlers, True, True);
      Escenario('B. The user REJECTS', Server, Handlers, True, False);
      Escenario('C. WITHOUT an OnInputRequired handler', Server, Handlers, False, False);

      Writeln('');
      Writeln('   In C the tool never runs: the response carries unresolved');
      Writeln('   input_required. If an MCP server uses elicitation');
      Writeln('   and the client does not handle OnInputRequired, this is what you see.');

      Server.Stop;
    finally
      Handlers.Free;
      Server.Free;
    end;

    Writeln('');
    Writeln('OK: the three elicitation scenarios completed.');

    if Assigned(Telemetry) then
    begin
      Telemetry.Flush;
      Telemetry.Free;
    end;
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
