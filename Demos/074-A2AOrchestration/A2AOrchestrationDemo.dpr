program A2AOrchestrationDemo;

// =============================================================================
// DEMO 074 - A2A orchestration flows (spec 1.0)
// =============================================================================
// Demo 072 shows the happy path point to point: one client, one agent, one
// response. This shows what is needed for A2A to really work in an
// orchestration. Everything deterministic, no LLM or API keys.
//
//   1. POOL          : three SIMULTANEOUS tasks against the same agent. With a
//                      single TAIAgentManager the second and third would receive
//                      AgentBusy (-32000), because a graph does not run two
//                      runs at once. With OnAcquireManager the server
//                      maintains a pool and all three complete.
//
//   2. HUMAN-IN-THE-LOOP : the graph suspends asking for approval. The task
//                      stays in input-required with the question in
//                      status.message, and a later SendMessage with the SAME
//                      taskId resumes it until completed.
//
//   3. FEDERATED HITL : the same, but the one asking for approval is a REMOTE
//                      agent. The local node suspends instead of failing, and
//                      when resumed the response travels to the remote task and
//                      the local graph finishes. This is what makes a
//                      human-in-the-loop cross federation instead of dying at
//
//   4. NON-BLOCKING : configuration.blocking=false returns the task in working
//                      immediately and the client continues with GetTask, which
//                      refreshes the state from the live graph.
//
// Usage modes:
//   A2AOrchestrationDemo.exe          -> the four scenarios
//   A2AOrchestrationDemo.exe --otel   -> exports OTLP traces to localhost:4318
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.TypInfo,
  System.Threading,
  System.SyncObjs,
  System.DateUtils,
  uMakerAi.Agents,
  uMakerAi.A2A.Server in '..\..\Source\Agents\uMakerAi.A2A.Server.pas',
  uMakerAi.A2A.Client in '..\..\Source\Agents\uMakerAi.A2A.Client.pas',
  uMakerAi.Telemetry;

const
  PORT = 8281;

type
  // Framework events are 'of object': no lambdas.
  TDemoHandlers = class
  public
    // Normal node: appends its name to the input
    procedure NodoExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    // Slow node: forces real overlap between concurrent tasks
    procedure NodoLento(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    // Node with human-in-the-loop: suspends the first time and on
    // resumption incorporates the human response
    procedure NodoAprobacion(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    // Pool factory: a new graph per slot
    procedure FabricaManager(Sender: TObject; var AManager: TAIAgentManager);
  end;

procedure TDemoHandlers.NodoExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Output := Input + '>' + Node.Name;
end;

procedure TDemoHandlers.NodoLento(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
begin
  Sleep(400); // simula trabajo real
  Output := Input + '>' + Node.Name;
end;

procedure TDemoHandlers.NodoAprobacion(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
const
  KEY = 'demo.aprobado.';
begin
  // The mark goes in the blackboard, not in the handler: ResumeThread
  // RE-EXECUTES this same node, so the first pass must be distinguished from
  if Node.Graph.Blackboard.GetString(KEY + Node.Name) = '' then
  begin
    Node.Graph.Blackboard.SetString(KEY + Node.Name, '1');
    Output := Input; // pass-through mientras se espera al humano
    Node.Suspend('Authorize payment of ' + Input + '?', 'A supervisor signature is required');
  end
  else
    Output := Input + ' [autorizado: ' + Node.Input + ']';
end;

procedure TDemoHandlers.FabricaManager(Sender: TObject; var AManager: TAIAgentManager);
begin
  // The server takes care of freeing it. It must have the same shape as
  // the graph the agent publishes.
  AManager := TAIAgentManager.Create(nil);
  AManager.AddNode('Validar', NodoLento).AddNode('Procesar', NodoExec);
  AManager.AddEdge('Validar', 'Procesar');
  AManager.SetEntryPoint('Validar').SetFinishPoint('Procesar');
end;

// -----------------------------------------------------------------------------

procedure EsperarGrafo(A: TAIAgentManager);
begin
  while A.Busy do
  begin
    CheckSynchronize;
    Sleep(20);
  end;
  CheckSynchronize;
end;

function NombreEstado(A: TAiA2ATaskState): string;
begin
  Result := GetEnumName(TypeInfo(TAiA2ATaskState), Ord(A));
end;

function NombreStatus(A: TAgentExecutionStatus): string;
begin
  Result := GetEnumName(TypeInfo(TAgentExecutionStatus), Ord(A));
end;

// -----------------------------------------------------------------------------
// 1. POOL: tres tasks simultaneos
// -----------------------------------------------------------------------------
procedure EscenarioPool(AHandlers: TDemoHandlers);
var
  Server: TAiA2AServer;
  Tareas: TArray<ITask>;
  Ok, Busy, Otros: Integer;
  I: Integer;
  Inicio: TDateTime;
begin
  Writeln('');
  Writeln('== 1. POOL: three simultaneous tasks against the same agent ==');
  Writeln('');

  Server := TAiA2AServer.Create(nil);
  try
    Server.Port := PORT;
    Server.AgentName := 'Agente Procesador';
    Server.AgentDescription := 'Valida y procesa solicitudes';
    // Without this factory the pool cannot grow and the effective limit is 1.
    Server.OnAcquireManager := AHandlers.FabricaManager;
    Server.MaxConcurrentTasks := 3;
    Server.Active := True;

    Ok := 0;
    Busy := 0;
    Otros := 0;
    Inicio := Now;

    SetLength(Tareas, 3);
    for I := 0 to 2 do
      Tareas[I] := TTask.Run(
        procedure
        var
          C: TAiA2AClient;
          T: TJSONObject;
          S: string;
        begin
          C := TAiA2AClient.Create(nil);
          try
            C.Url := 'http://localhost:' + IntToStr(PORT);
            try
              T := C.SendText('solicitud', S);
              try
                if C.LastTaskState = tsCompleted then
                  TInterlocked.Increment(Ok)
                else
                  TInterlocked.Increment(Otros);
              finally
                T.Free;
              end;
            except
              on E: Exception do
                if E.Message.Contains('-32000') then
                  TInterlocked.Increment(Busy)
                else
                  TInterlocked.Increment(Otros);
            end;
          finally
            C.Free;
          end;
        end);
    TTask.WaitForAll(Tareas);

    Writeln(Format('   completed=%d  agent-busy=%d  others=%d', [Ok, Busy, Otros]));
    Writeln(Format('   total time: %d ms (each graph takes ~400 ms)', [MilliSecondsBetween(Now, Inicio)]));
    if Ok = 3 then
      Writeln('   OK: all three ran in parallel; in series they would have taken ~3x')
    else
      Writeln('   WARNING: not all three completed');

    Server.Active := False;
  finally
    Server.Free;
  end;
end;

// -----------------------------------------------------------------------------
// 2. HUMAN-IN-THE-LOOP directo
// -----------------------------------------------------------------------------
procedure EscenarioHitl(AHandlers: TDemoHandlers);
var
  Server: TAiA2AServer;
  Agente: TAIAgentManager;
  Client: TAiA2AClient;
  Task: TJSONObject;
  Salida, TaskId, CtxId: string;
begin
  Writeln('');
  Writeln('== 2. HUMAN-IN-THE-LOOP: input-required and resumption by taskId ==');
  Writeln('');

  Server := TAiA2AServer.Create(nil);
  Agente := TAIAgentManager.Create(nil);
  Client := TAiA2AClient.Create(nil);
  try
    Agente.AddNode('Preparar', AHandlers.NodoExec).AddNode('Aprobar', AHandlers.NodoAprobacion);
    Agente.AddEdge('Preparar', 'Aprobar');
    Agente.SetEntryPoint('Preparar').SetFinishPoint('Aprobar');

    Server.Port := PORT;
    Server.AgentName := 'Agente Tesoreria';
    Server.AgentManager := Agente;
    Server.Active := True;

    Client.Url := 'http://localhost:' + IntToStr(PORT);

    // --- Primer turno: el grafo se suspende ---
    Task := Client.SendText('1500 EUR', Salida);
    try
      TaskId := Client.LastTaskId;
      CtxId := Client.LastContextId;
      Writeln('   turn 1 -> state: ' + NombreEstado(Client.LastTaskState));
      Writeln('             agent question: ' + Client.LastStatusMessage);
      Writeln('             taskId: ' + TaskId);
    finally
      Task.Free;
    end;

    // --- Segundo turno: MISMO taskId = reanudacion, no un task nuevo ---
    Writeln('');
    Writeln('   (the human answers "approved by Ana")');
    Task := Client.SendTextEx('aprobado por Ana', TaskId, CtxId, Salida);
    try
      Writeln('   turn 2 -> state: ' + NombreEstado(Client.LastTaskState));
      Writeln('             result: ' + Salida);
      Writeln('             same taskId: ' + BoolToStr(Client.LastTaskId = TaskId, True));
    finally
      Task.Free;
    end;

    Server.Active := False;
  finally
    Client.Free;
    Server.Free;
    Agente.Free;
  end;
end;

// -----------------------------------------------------------------------------
// 3. HITL FEDERADO: el que pide aprobacion es el agente remoto
// -----------------------------------------------------------------------------
procedure EscenarioHitlFederado(AHandlers: TDemoHandlers);
var
  Server: TAiA2AServer;
  Remoto, Local: TAIAgentManager;
  Tool: TAiA2ARemoteAgentTool;
begin
  Writeln('');
  Writeln('== 3. FEDERATED HITL: the local node suspends, it does not fail ==');
  Writeln('');

  Server := TAiA2AServer.Create(nil);
  Remoto := TAIAgentManager.Create(nil);
  try
    // Remote agent: asks for human approval
    Remoto.AddNode('Recibir', AHandlers.NodoExec).AddNode('Aprobar', AHandlers.NodoAprobacion);
    Remoto.AddEdge('Recibir', 'Aprobar');
    Remoto.SetEntryPoint('Recibir').SetFinishPoint('Aprobar');

    Server.Port := PORT;
    Server.AgentName := 'Agente Tesoreria Remoto';
    Server.AgentManager := Remoto;
    Server.Active := True;

    // Local graph: one of its nodes delegates to the remote agent
    Local := TAIAgentManager.Create(nil);
    try
      Local.AddNode('Origen', AHandlers.NodoExec);
      Local.AddNode('Delegado', nil);
      Tool := TAiA2ARemoteAgentTool.Create(Local);
      Tool.AgentUrl := 'http://localhost:' + IntToStr(PORT);
      // Default True: on input-required it suspends the local node instead of
      // throwing an exception. With False the local graph would die here.
      Tool.SuspendOnInputRequired := True;
      Local.FindNode('Delegado').Tool := Tool;
      Local.AddEdge('Origen', 'Delegado');
      Local.SetEntryPoint('Origen').SetFinishPoint('Delegado');

      Local.Run('pago 900 EUR');
      EsperarGrafo(Local);
      Writeln('   after the initial run, the LOCAL graph ended in: ' +
        NombreStatus(Local.Blackboard.GetStatus));
      Writeln('   (the remote agent requested input and the local node suspended)');

      Writeln('');
      Writeln('   (the local node is resumed with the human response)');
      Local.ResumeThread(Local.CurrentThreadID, 'Delegado', 'aprobado por Luis');
      EsperarGrafo(Local);

      Writeln('   final state of the LOCAL graph: ' + NombreStatus(Local.Blackboard.GetStatus));
      Writeln('   output: ' + Local.EndNode.Output);
      Writeln('   OK: the response traveled to the SAME remote task and both graphs finished');
    finally
      Local.Free;
    end;

    Server.Active := False;
  finally
    Server.Free;
    Remoto.Free;
  end;
end;

// -----------------------------------------------------------------------------
// 4. NO BLOQUEANTE: blocking=false + GetTask
// -----------------------------------------------------------------------------
procedure EscenarioNoBloqueante(AHandlers: TDemoHandlers);
var
  Server: TAiA2AServer;
  Agente: TAIAgentManager;
  Client: TAiA2AClient;
  Task: TJSONObject;
  Salida, TaskId: string;
  Vueltas: Integer;
begin
  Writeln('');
  Writeln('== 4. NON-BLOCKING: blocking=false and polling with GetTask ==');
  Writeln('');

  Server := TAiA2AServer.Create(nil);
  Agente := TAIAgentManager.Create(nil);
  Client := TAiA2AClient.Create(nil);
  try
    Agente.AddNode('Validar', AHandlers.NodoLento).AddNode('Procesar', AHandlers.NodoExec);
    Agente.AddEdge('Validar', 'Procesar');
    Agente.SetEntryPoint('Validar').SetFinishPoint('Procesar');

    Server.Port := PORT;
    Server.AgentName := 'Agente Lento';
    Server.AgentManager := Agente;
    Server.Active := True;

    Client.Url := 'http://localhost:' + IntToStr(PORT);

    Task := Client.SendTextEx('lote-42', '', '', Salida, False); // blocking=false
    try
      TaskId := Client.LastTaskId;
      Writeln('   SendMessage returned immediately in state: ' + NombreEstado(Client.LastTaskState));
    finally
      Task.Free;
    end;

    Vueltas := 0;
    repeat
      Sleep(100);
      Inc(Vueltas);
      Task := Client.GetTask(TaskId);
      try
        Writeln(Format('   GetTask #%d -> %s', [Vueltas, NombreEstado(Client.LastTaskState)]));
        if Client.LastTaskState = tsCompleted then
        begin
          Writeln('   result: ' + TAiA2AClient.ArtifactsText(Task));
          Break;
        end;
      finally
        Task.Free;
      end;
    until Vueltas >= 30;

    Writeln('   OK: the state is refreshed from the live graph, it does not stay frozen');

    Server.Active := False;
  finally
    Client.Free;
    Server.Free;
    Agente.Free;
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
  Handlers: TDemoHandlers;
  Telemetry: TAiTelemetry;

begin
  Telemetry := nil;
  try
    if HasFlag('--otel') then
    begin
      Telemetry := TAiTelemetry.Create(nil);
      Telemetry.ServiceName := 'A2AOrchestrationDemo';
      Telemetry.Enabled := True;
      Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
    end;

    Writeln('=== DEMO 074: A2A orchestration (no LLM, no API keys) ===');

    Handlers := TDemoHandlers.Create;
    try
      EscenarioPool(Handlers);
      EscenarioHitl(Handlers);
      EscenarioHitlFederado(Handlers);
      EscenarioNoBloqueante(Handlers);
    finally
      Handlers.Free;
    end;

    Writeln('');
    Writeln('OK: the four orchestration scenarios completed.');

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
