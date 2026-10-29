program A2APushDemo;

// =============================================================================
// DEMO 080 - A2A push notifications: the agent notifies your webhook
// =============================================================================
// SSE streaming is useful when the client can stay connected waiting.
// Push notifications are for the opposite: long tasks where the
// client disconnects and wants to be notified when they finish. The agent makes
// a POST to the URL you register.
//
// Everything happens in a single process and without API keys:
//   - an A2A agent (graph with a slow node) on port 8282
//   - your own webhook receiver on 8283, to see what arrives
//
// Walkthrough:
//   1. Config via CRUD: CreateTaskPushNotificationConfig on an already
//      created task, then Get / List / Delete.
//   2. Config IN the request itself: configuration.taskPushNotificationConfig
//      inside SendMessage, which avoids the second call.
//   3. Check what the webhook receives: Authorization header and payload.
//
// Usage:
//   A2APushDemo.exe [--port 8282] [--hook-port 8283]
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.Net.HttpClient,
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer,
  uMakerAi.Agents,
  uMakerAi.A2A.Server in '..\..\Source\Agents\uMakerAi.A2A.Server.pas',
  uMakerAi.A2A.Client in '..\..\Source\Agents\uMakerAi.A2A.Client.pas';

type
  // What the webhook received, to be able to show it
  TAviso = record
    Auth: string;
    Cuerpo: string;
  end;

  // Webhook receiver: a minimal HTTP server that records what arrives.
  TReceptorWebhook = class
  private
    FHttp: TIdHTTPServer;
    FLock: TCriticalSection;
    FAvisos: TList<TAviso>;
    procedure OnPost(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    // TIdHTTPServer only knows Basic. If an Authorization with another
    // scheme (Bearer, for example) arrives, it answers 401 by itself and OnCommandGet doesn't
    // even notice. Marking it as handled lets the request through.
    procedure OnParseAuth(AContext: TIdContext; const AAuthType, AAuthData: string;
      var VUsername, VPassword: string; var VHandled: Boolean);
  public
    constructor Create(APort: Integer);
    destructor Destroy; override;
    function Cuantos: Integer;
    function Ultimo: TAviso;
    procedure Limpiar;
    // Waits for something to arrive, up to ATimeoutMs. Returns False if nothing arrived.
    function EsperarAviso(ATimeoutMs: Integer): Boolean;
  end;

  THandlers = class
  public
    procedure NodoLento(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    procedure Fabrica(Sender: TObject; var AManager: TAIAgentManager);
  end;

  { TReceptorWebhook }

constructor TReceptorWebhook.Create(APort: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FAvisos := TList<TAviso>.Create;
  FHttp := TIdHTTPServer.Create(nil);
  FHttp.DefaultPort := APort;
  FHttp.OnCommandGet := OnPost;
  FHttp.OnCommandOther := OnPost;
  FHttp.OnParseAuthentication := OnParseAuth;
  FHttp.Active := True;
end;

destructor TReceptorWebhook.Destroy;
begin
  FHttp.Active := False;
  FHttp.Free;
  FAvisos.Free;
  FLock.Free;
  inherited;
end;

procedure TReceptorWebhook.OnParseAuth(AContext: TIdContext; const AAuthType, AAuthData: string;
  var VUsername, VPassword: string; var VHandled: Boolean);
begin
  VHandled := True;
end;

procedure TReceptorWebhook.OnPost(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo);
var
  Aviso: TAviso;
  SS: TStringStream;
begin
  Aviso.Auth := ARequestInfo.RawHeaders.Values['Authorization'];
  Aviso.Cuerpo := '';
  if Assigned(ARequestInfo.PostStream) then
  begin
    ARequestInfo.PostStream.Position := 0;
    SS := TStringStream.Create('', TEncoding.UTF8);
    try
      SS.CopyFrom(ARequestInfo.PostStream, 0);
      Aviso.Cuerpo := SS.DataString;
    finally
      SS.Free;
    end;
  end;

  FLock.Enter;
  try
    FAvisos.Add(Aviso);
  finally
    FLock.Leave;
  end;

  AResponseInfo.ResponseNo := 200;
  AResponseInfo.ContentText := '{"ok":true}';
  AResponseInfo.ContentType := 'application/json';
end;

function TReceptorWebhook.Cuantos: Integer;
begin
  FLock.Enter;
  try
    Result := FAvisos.Count;
  finally
    FLock.Leave;
  end;
end;

function TReceptorWebhook.Ultimo: TAviso;
begin
  FLock.Enter;
  try
    Result := FAvisos.Last;
  finally
    FLock.Leave;
  end;
end;

procedure TReceptorWebhook.Limpiar;
begin
  FLock.Enter;
  try
    FAvisos.Clear;
  finally
    FLock.Leave;
  end;
end;

function TReceptorWebhook.EsperarAviso(ATimeoutMs: Integer): Boolean;
var
  Esperado: Integer;
begin
  Esperado := 0;
  while (Cuantos = 0) and (Esperado < ATimeoutMs) do
  begin
    Sleep(50);
    Inc(Esperado, 50);
  end;
  Result := Cuantos > 0;
end;

{ THandlers }

procedure THandlers.NodoLento(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Sleep(600); // simulates long work: this is the use case for push
  Output := Input + ' [procesado]';
end;

procedure THandlers.Fabrica(Sender: TObject; var AManager: TAIAgentManager);
begin
  AManager := TAIAgentManager.Create(nil);
  AManager.AddNode('Procesar', NodoLento);
  AManager.SetEntryPoint('Procesar').SetFinishPoint('Procesar');
end;

// -----------------------------------------------------------------------------

function ArgValue(const AName, ADefault: string): string;
var
  I: Integer;
begin
  Result := ADefault;
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), AName) then
      Exit(ParamStr(I + 1));
end;

function Rpc(const AUrl, AJson: string): TJSONObject;
var
  Http: THTTPClient;
  Body: TStringStream;
begin
  Http := THTTPClient.Create;
  Body := TStringStream.Create(AJson, TEncoding.UTF8);
  try
    Http.ContentType := 'application/json';
    Http.ResponseTimeout := 60000;
    Result := TJSONObject(TJSONObject.ParseJSONValue(Http.Post(AUrl, Body).ContentAsString(TEncoding.UTF8)));
  finally
    Body.Free;
    Http.Free;
  end;
end;

var
  Server: TAiA2AServer;
  Agente: TAIAgentManager;
  Handlers: THandlers;
  Receptor: TReceptorWebhook;
  Puerto, PuertoHook: Integer;
  Url, HookUrl, TaskId: string;
  R: TJSONObject;
  Aviso: TAviso;
  Recibidos: Integer;

begin
  try
    Puerto := StrToIntDef(ArgValue('--port', '8282'), 8282);
    PuertoHook := StrToIntDef(ArgValue('--hook-port', '8283'), 8283);
    Url := Format('http://localhost:%d/', [Puerto]);
    HookUrl := Format('http://localhost:%d/webhook', [PuertoHook]);

    Writeln('=== DEMO 080: A2A push notifications ===');
    Writeln('');

    Recibidos := 0;
    Handlers := THandlers.Create;
    Agente := TAIAgentManager.Create(nil);
    Server := TAiA2AServer.Create(nil);
    Receptor := TReceptorWebhook.Create(PuertoHook);
    try
      Agente.AddNode('Procesar', Handlers.NodoLento);
      Agente.SetEntryPoint('Procesar').SetFinishPoint('Procesar');
      Server.AgentManager := Agente;
      Server.AgentName := 'Agente con avisos';
      Server.OnAcquireManager := Handlers.Fabrica;
      Server.MaxConcurrentTasks := 8;
      Server.Port := Puerto;
      Server.Active := True;

      Writeln('   A2A agent  : ' + Url);
      Writeln('   webhook     : ' + HookUrl);

      // ---------------------------------------------------------------------
      Writeln('');
      Writeln('== 1. Register the webhook with CRUD ==');
      Writeln('');

      // A task that keeps working, to register the notice before it
      // finishes. With blocking=false SendMessage returns immediately.
      R := Rpc(Url, '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{' +
        '"message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"lote-1"}]},' +
        '"configuration":{"blocking":false}}}');
      try
        TaskId := R.GetValue<TJSONObject>('result').GetValue<TJSONObject>('task').GetValue<string>('id');
      finally
        R.Free;
      end;
      Writeln('   task created: ' + TaskId);

      R := Rpc(Url, Format('{"jsonrpc":"2.0","id":2,"method":"CreateTaskPushNotificationConfig","params":' +
        '{"taskId":"%s","config":{"id":"cfg-1","url":"%s",' +
        '"authentication":{"scheme":"Bearer","credentials":"mi-token-secreto"}}}}', [TaskId, HookUrl]));
      try
        Writeln('   config registered: ' + R.GetValue<TJSONObject>('result').ToJSON);
      finally
        R.Free;
      end;

      R := Rpc(Url, Format('{"jsonrpc":"2.0","id":3,"method":"ListTaskPushNotificationConfigs",' +
        '"params":{"taskId":"%s"}}', [TaskId]));
      try
        Writeln('   list: ' + R.GetValue<TJSONObject>('result').ToJSON);
      finally
        R.Free;
      end;

      Writeln('');
      Writeln('   waiting for the notice...');
      if Receptor.EsperarAviso(15000) then
      begin
        Aviso := Receptor.Ultimo;
        Inc(Recibidos);
        Writeln('   NOTICE RECEIVED');
        Writeln('     Authorization: ' + Aviso.Auth);
        Writeln('     body: ' + Copy(Aviso.Cuerpo, 1, 150) + '...');
        Writeln('   (the payload is a StreamResponse, with the task inside "task")');
      end
      else
        Writeln('   WARNING: no notice arrived');

      // ---------------------------------------------------------------------
      Writeln('');
      Writeln('== 2. Register the webhook IN the request itself ==');
      Writeln('');
      Writeln('   (configuration.taskPushNotificationConfig, without a second call)');
      Receptor.Limpiar;

      R := Rpc(Url, Format('{"jsonrpc":"2.0","id":4,"method":"SendMessage","params":{' +
        '"message":{"messageId":"m2","role":"ROLE_USER","parts":[{"text":"lote-2"}]},' +
        '"configuration":{"blocking":false,"taskPushNotificationConfig":' +
        '{"id":"cfg-2","url":"%s","authentication":{"scheme":"Bearer","credentials":"otro-token"}}}}}',
        [HookUrl]));
      try
        Writeln('   task: ' + R.GetValue<TJSONObject>('result').GetValue<TJSONObject>('task')
          .GetValue<string>('id'));
      finally
        R.Free;
      end;

      Writeln('   waiting for the notice...');
      if Receptor.EsperarAviso(15000) then
      begin
        Aviso := Receptor.Ultimo;
        Inc(Recibidos);
        Writeln('   NOTICE RECEIVED with Authorization: ' + Aviso.Auth);
      end
      else
        Writeln('   WARNING: no notice arrived');

      // ---------------------------------------------------------------------
      Writeln('');
      Writeln('== 3. Delete is idempotent ==');
      Writeln('');
      R := Rpc(Url, Format('{"jsonrpc":"2.0","id":5,"method":"DeleteTaskPushNotificationConfig",' +
        '"params":{"taskId":"%s","id":"cfg-1"}}', [TaskId]));
      try
        Writeln('   first delete : ' + BoolToStr(R.GetValue('error') = nil, True) + ' (no error)');
      finally
        R.Free;
      end;
      R := Rpc(Url, Format('{"jsonrpc":"2.0","id":6,"method":"DeleteTaskPushNotificationConfig",' +
        '"params":{"taskId":"%s","id":"cfg-1"}}', [TaskId]));
      try
        Writeln('   second delete: ' + BoolToStr(R.GetValue('error') = nil, True) +
          ' (deleting what is no longer there is not an error either)');
      finally
        R.Free;
      end;

      Writeln('');
      if Recibidos = 2 then
      begin
        Writeln('OK: the agent notified an external webhook when completing its tasks.');
        ExitCode := 0;
      end
      else
      begin
        Writeln(Format('FAILURE: 2 notices were expected and %d arrived.', [Recibidos]));
        Writeln('The configuration CRUD DOES work; what fails is DELIVERY');
        Writeln('when nobody queries the task (blocking=false). See the CLAUDE.md');
        Writeln('of this demo for the real state of the limitation.');
        ExitCode := 1;
      end;
      Server.Active := False;
    finally
      Receptor.Free;
      Server.Free;
      Agente.Free;
      Handlers.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
