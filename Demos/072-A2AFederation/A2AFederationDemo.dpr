program A2AFederationDemo;

// =============================================================================
// DEMO 072 - Agent federation with the A2A protocol (spec 1.0)
// =============================================================================
// Shows the three roles of MakerAI's A2A stack, without needing an LLM or
// API keys (nodes are deterministic text transformations):
//
//   1. SERVER   : a TAIAgentManager graph ("Editor Agent") exposed as an
//                 A2A agent via TAiA2AServer (Agent Card + JSON-RPC).
//   2. CLIENT   : TAiA2AClient discovers the Agent Card and sends a message.
//   3. FEDERATION: a local graph ("Writer Agent") delegates one of its nodes
//                 to the remote agent using TAiA2ARemoteAgentTool.
//
// Usage modes:
//   A2AFederationDemo.exe                        -> full demo in one process
//   A2AFederationDemo.exe --serve [--port 8280]  -> server only (Ctrl+C)
//   A2AFederationDemo.exe --client --url http://host:8280 [text...]
//   A2AFederationDemo.exe --otel                 -> exports OTLP traces to :4318
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.TypInfo,
  uMakerAi.Agents,
  uMakerAi.A2A.Server in '..\..\Source\Agents\uMakerAi.A2A.Server.pas',
  uMakerAi.A2A.Client in '..\..\Source\Agents\uMakerAi.A2A.Client.pas',
  uMakerAi.Telemetry;

type
  // ---------------------------------------------------------------------------
  // Nodes of the REMOTE agent ("Editor Agent"): cleans and signs text
  // ---------------------------------------------------------------------------
  TEditorHandlers = class
  public
    procedure LimpiarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    procedure FirmarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
  end;

  // ---------------------------------------------------------------------------
  // Nodes of the LOCAL agent ("Writer Agent"): prepares, delegates and publishes
  // ---------------------------------------------------------------------------
  TRedactorHandlers = class
  public
    procedure PrepararExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    procedure PublicarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
  end;

procedure TEditorHandlers.LimpiarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  // Normalizes multiple spaces and trims ends
  Output := Input.Trim;
  while Output.Contains('  ') do
    Output := Output.Replace('  ', ' ');
end;

procedure TEditorHandlers.FirmarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Output := Input + ' [reviewed by the Editor Agent]';
end;

procedure TRedactorHandlers.PrepararExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Output := 'DRAFT: ' + Input;
end;

procedure TRedactorHandlers.PublicarExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Output := '>>> PUBLISHED: ' + Input;
end;

// -----------------------------------------------------------------------------

procedure WaitForGraph(AAgents: TAIAgentManager);
begin
  while AAgents.Busy do
  begin
    CheckSynchronize;
    Sleep(50);
  end;
  CheckSynchronize;
end;

function BuildEditorAgent(AHandlers: TEditorHandlers): TAIAgentManager;
begin
  Result := TAIAgentManager.Create(nil);
  Result.Name := 'EditorAgent';
  Result.AddNode('Limpiar', AHandlers.LimpiarExec).AddNode('Firmar', AHandlers.FirmarExec);
  Result.AddEdge('Limpiar', 'Firmar');
  Result.SetEntryPoint('Limpiar').SetFinishPoint('Firmar');
end;

procedure RunServeMode(APort: Integer);
var
  Editor: TAIAgentManager;
  Handlers: TEditorHandlers;
  Server: TAiA2AServer;
begin
  Handlers := TEditorHandlers.Create;
  Editor := BuildEditorAgent(Handlers);
  Server := TAiA2AServer.Create(nil);
  try
    Server.AgentManager := Editor;
    Server.AgentName := 'Editor Agent';
    Server.AgentDescription := 'Cleans and signs text (MakerAI A2A demo)';
    Server.Port := APort;
    Server.Active := True;
    Writeln(Format('A2A agent listening on http://localhost:%d', [APort]));
    Writeln('  Agent Card: http://localhost:' + IntToStr(APort) + '/.well-known/agent-card.json');
    Writeln('Ctrl+C to stop.');
    while True do
    begin
      CheckSynchronize;
      Sleep(200);
    end;
  finally
    Server.Free;
    Editor.Free;
    Handlers.Free;
  end;
end;

procedure RunClientMode(const AUrl, AText: string);
var
  Client: TAiA2AClient;
  Card, Task: TJSONObject;
  OutText: string;
begin
  Client := TAiA2AClient.Create(nil);
  try
    Client.Url := AUrl;
    Writeln('1) Downloading Agent Card from ' + AUrl + ' ...');
    Card := Client.FetchAgentCard;
    try
      Writeln('   Agent: ' + Card.GetValue<string>('name', '?') + ' — ' +
        Card.GetValue<string>('description', ''));
    finally
      Card.Free;
    end;

    Writeln('2) Sending message: "' + AText + '"');
    Task := Client.SendText(AText, OutText);
    try
      Writeln('   Task ' + Client.LastTaskId + ' -> ' + Client.LastState);
      Writeln('   Response: ' + OutText);
    finally
      Task.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure RunFullDemo(APort: Integer; const AText: string);
var
  EditorHandlers: TEditorHandlers;
  RedactorHandlers: TRedactorHandlers;
  Editor, Redactor: TAIAgentManager;
  Server: TAiA2AServer;
  Tool: TAiA2ARemoteAgentTool;
begin
  Writeln('=== DEMO A2A: agent federation in a single process ===');
  Writeln;

  EditorHandlers := TEditorHandlers.Create;
  RedactorHandlers := TRedactorHandlers.Create;
  Editor := BuildEditorAgent(EditorHandlers);
  Redactor := TAIAgentManager.Create(nil);
  Server := TAiA2AServer.Create(nil);
  try
    // 1) Expose the Editor Agent via A2A
    Server.AgentManager := Editor;
    Server.AgentName := 'Editor Agent';
    Server.AgentDescription := 'Cleans and signs text (MakerAI A2A demo)';
    Server.Port := APort;
    Server.Active := True;
    Writeln(Format('[server] Editor Agent published at http://localhost:%d', [APort]));

    // 2) Test the pure client against the server
    Writeln;
    Writeln('[client] Consuming the remote agent directly:');
    RunClientMode('http://localhost:' + IntToStr(APort), AText);

    // 3) Federation: the Writer Agent delegates its 'Edit' node to the remote
    Writeln;
    Writeln('[federation] Local graph: Prepare -> Edit(A2A remote) -> Publish');
    Redactor.Name := 'WriterAgent';
    Redactor.AddNode('Preparar', RedactorHandlers.PrepararExec);
    Redactor.AddNode('Editar', nil);
    Redactor.AddNode('Publicar', RedactorHandlers.PublicarExec);
    Tool := TAiA2ARemoteAgentTool.Create(Redactor);
    Tool.AgentUrl := 'http://localhost:' + IntToStr(APort);
    Redactor.FindNode('Editar').Tool := Tool;
    Redactor.AddEdge('Preparar', 'Editar');
    Redactor.AddEdge('Editar', 'Publicar');
    Redactor.SetEntryPoint('Preparar').SetFinishPoint('Publicar');

    Redactor.Run(AText);
    WaitForGraph(Redactor);

    Writeln('  Final status: ' + GetEnumName(TypeInfo(TAgentExecutionStatus),
      Ord(Redactor.Blackboard.GetStatus)));
    Writeln('  Result      : ' + Redactor.EndNode.Output);
    Writeln;
    if Redactor.Blackboard.GetStatus = esCompleted then
      Writeln('OK: A2A federation worked end to end.')
    else
      Writeln('ERROR: the local graph did not complete.');

    Server.Active := False;
  finally
    Server.Free;
    Redactor.Free;
    Editor.Free;
    RedactorHandlers.Free;
    EditorHandlers.Free;
  end;
end;

// -----------------------------------------------------------------------------

var
  i: Integer;
  Param, Url, InputText: string;
  Port: Integer;
  ServeMode, ClientMode, OtelMode: Boolean;
  Telemetry: TAiTelemetry;

begin
  try
    Port := 8280;
    Url := '';
    InputText := '';
    ServeMode := False;
    ClientMode := False;
    OtelMode := False;
    Telemetry := nil;

    i := 1;
    while i <= ParamCount do
    begin
      Param := LowerCase(ParamStr(i));
      if Param = '--serve' then
        ServeMode := True
      else if Param = '--client' then
        ClientMode := True
      else if Param = '--otel' then
        OtelMode := True
      else if (Param = '--port') and (i < ParamCount) then
      begin
        Inc(i);
        Port := StrToIntDef(ParamStr(i), Port);
      end
      else if (Param = '--url') and (i < ParamCount) then
      begin
        Inc(i);
        Url := ParamStr(i);
      end
      else
        InputText := Trim(InputText + ' ' + ParamStr(i));
      Inc(i);
    end;

    if InputText = '' then
      InputText := 'hello   world  federated';

    if OtelMode then
    begin
      Telemetry := TAiTelemetry.Create(nil);
      Telemetry.ServiceName := 'A2AFederationDemo';
      Telemetry.Enabled := True;
      Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
    end;

    try
      if ServeMode then
        RunServeMode(Port)
      else if ClientMode then
      begin
        if Url = '' then
          Url := 'http://localhost:' + IntToStr(Port);
        RunClientMode(Url, InputText);
      end
      else
        RunFullDemo(Port, InputText);
    finally
      Telemetry.Free; // flush pending spans in the destructor
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
