program AgentCheckpointDBDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Comp.Client,
  FireDAC.ConsoleUI.Wait,
  Data.DB,
  uMakerAi.Agents,
  uMakerAi.Agents.Checkpoint,
  uMakerAi.Agents.Checkpoint.DB;

// ---------------------------------------------------------------------------
// Demo 054 — TAiDatabaseCheckpointer with SQLite
//
// Agent flow:
//   Start -> Process -> Approve (SUSPEND) -> Finish
//
// Phase 1: The agent runs and suspends at the "Approve" node.
//         The checkpoint is saved automatically in the SQLite DB.
//
// Phase 2: The user presses ENTER (simulates operator approval).
//         ResumeThread is called to resume from "Finish".
//         The checkpoint is deleted on completion.
//
// If there are previous checkpoints in the DB, the demo offers to resume them.
// ---------------------------------------------------------------------------

type
  TDemo = class
  private
    FAgents: TAIAgentManager;
    FConnection: TFDConnection;
    FCheckpointer: IAiCheckpointer;
    FSuspendedThreadID: string;
    procedure SetupDatabase;
    procedure BuildGraph;
    procedure WaitForCompletion;
    procedure Println(const Msg: string);
    // Agent events — exact signatures according to TAIAgentsOnXxx
    procedure DoPrint(Sender: TObject; Value: string);
    procedure DoEnd(Node: TAIAgentsNode; Value: string);
    procedure DoError(Sender: TObject; Node: TAIAgentsNode;
      Link: TAIAgentsLink; E: Exception; var Abort: Boolean);
    procedure DoSuspend(Sender: TObject;
      const AThreadID, ANodeName, AReason, AContext: string);
    // Node executors — TAIAgentsNodeOnExecute signature
    procedure InicioExec(Node, BeforeNode: TAIAgentsNode;
      Link: TAIAgentsLink; Input: string; var Output: string);
    procedure ProcesarExec(Node, BeforeNode: TAIAgentsNode;
      Link: TAIAgentsLink; Input: string; var Output: string);
    procedure AprobarExec(Node, BeforeNode: TAIAgentsNode;
      Link: TAIAgentsLink; Input: string; var Output: string);
    procedure FinalizarExec(Node, BeforeNode: TAIAgentsNode;
      Link: TAIAgentsLink; Input: string; var Output: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ TDemo }

procedure TDemo.Println(const Msg: string);
begin
  Writeln('[DEMO] ' + Msg);
end;

constructor TDemo.Create;
var
  LCp: TAiDatabaseCheckpointer;
begin
  inherited Create;
  FSuspendedThreadID := '';
  SetupDatabase;
  LCp := TAiDatabaseCheckpointer.Create(FConnection);
  LCp.CreateSchema;
  FCheckpointer := LCp;
  FAgents := TAIAgentManager.Create(nil);
  FAgents.Checkpointer := FCheckpointer;
  FAgents.OnPrint   := DoPrint;
  FAgents.OnEnd     := DoEnd;
  FAgents.OnError   := DoError;
  FAgents.OnSuspend := DoSuspend;
end;

destructor TDemo.Destroy;
begin
  FAgents.Free;
  FCheckpointer := nil;
  FConnection.Free;
  inherited;
end;

procedure TDemo.SetupDatabase;
var
  DBPath: string;
begin
  DBPath := ChangeFileExt(ParamStr(0), '.db');
  FConnection := TFDConnection.Create(nil);
  FConnection.DriverName := 'SQLite';
  FConnection.Params.Values['Database'] := DBPath;
  FConnection.Params.Values['OpenMode'] := 'CreateUTF8';
  FConnection.LoginPrompt := False;
  FConnection.Open;
  Println('SQLite DB: ' + DBPath);
end;

procedure TDemo.BuildGraph;
begin
  FAgents.ClearGraph;
  FAgents
    .AddNode('Start',    InicioExec)
    .AddNode('Process',  ProcesarExec)
    .AddNode('Approve',   AprobarExec)
    .AddNode('Finish', FinalizarExec);
  FAgents.AddEdge('Start',   'Process');
  FAgents.AddEdge('Process', 'Approve');
  FAgents.AddEdge('Approve',  'Finish');
  FAgents.SetEntryPoint('Start').SetFinishPoint('Finish');
end;

procedure TDemo.WaitForCompletion;
begin
  while FAgents.Busy do
  begin
    CheckSynchronize;
    Sleep(50);
  end;
  CheckSynchronize;
  Println('--- Execution cycle finished. ---');
end;

procedure TDemo.DoPrint(Sender: TObject; Value: string);
begin
  TThread.Synchronize(nil, procedure begin
    Writeln('[AGENT] ' + Value);
  end);
end;

procedure TDemo.DoEnd(Node: TAIAgentsNode; Value: string);
begin
  TThread.Synchronize(nil, procedure begin
    Writeln;
    Println('Flow completed successfully.');
    Println('Final output: "' + Value + '"');
  end);
end;

procedure TDemo.DoError(Sender: TObject; Node: TAIAgentsNode;
  Link: TAIAgentsLink; E: Exception; var Abort: Boolean);
var
  LNodeName, LMsg: string;
begin
  LNodeName := '';
  if Assigned(Node) then LNodeName := Node.Name;
  LMsg := '';
  if Assigned(E) then LMsg := E.ClassName + ': ' + E.Message;
  TThread.Synchronize(nil, procedure begin
    Writeln('[ERROR] Node: ' + LNodeName);
    if LMsg <> '' then
      Writeln('[ERROR] ' + LMsg);
  end);
  Abort := False;
end;

procedure TDemo.DoSuspend(Sender: TObject;
  const AThreadID, ANodeName, AReason, AContext: string);
begin
  TThread.Synchronize(nil, procedure begin
    Writeln;
    Println('*** AGENT SUSPENDED — Human action required ***');
    Println('  Thread ID  : ' + AThreadID);
    Println('  Node       : ' + ANodeName);
    Println('  Reason     : ' + AReason);
    Println('  Context    : ' + AContext);
    FSuspendedThreadID := AThreadID;
  end);
end;

{ Executors de nodos }

procedure TDemo.InicioExec(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: string; var Output: string);
begin
  TThread.Synchronize(nil, procedure begin
    Println('[Start] Process received: "' + Input + '"');
  end);
  Output := 'Proceso iniciado: ' + Input;
end;

procedure TDemo.ProcesarExec(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: string; var Output: string);
begin
  TThread.Synchronize(nil, procedure begin
    Println('[Process] Processing data...');
  end);
  Sleep(400);
  Output := 'Datos procesados. ' + Input;
end;

procedure TDemo.AprobarExec(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: string; var Output: string);
begin
  TThread.Synchronize(nil, procedure begin
    Println('[Approve] Request sent to operator. Suspending...');
  end);
  Output := Input;
  // Suspends execution; the framework saves the checkpoint automatically
  Node.Suspend('Aprobacion requerida por operador', 'Datos listos: ' + Input);
end;

procedure TDemo.FinalizarExec(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: string; var Output: string);
begin
  TThread.Synchronize(nil, procedure begin
    Println('[Finish] Process completed. Input: "' + Input + '"');
  end);
  Output := 'COMPLETADO: ' + Input;
end;

{ Logica principal }

procedure TDemo.Run;
var
  ActiveThreads: TArray<string>;
  Choice: string;
  I: Integer;
begin
  Writeln;
  Writeln('============================================');
  Writeln('   MakerAI — Demo 054: Checkpoint DB      ');
  Writeln('============================================');
  Writeln('Flow: Start -> Process -> Approve (SUSPEND) -> Finish');
  Writeln('Checkpointer: TAiDatabaseCheckpointer (SQLite via FireDAC)');
  Writeln;

  // Check whether there are suspended threads from previous runs
  ActiveThreads := FCheckpointer.GetActiveThreadIDs;
  if Length(ActiveThreads) > 0 then
  begin
    Println(Format('Found %d suspended thread(s) in DB:',
      [Length(ActiveThreads)]));
    for I := 0 to High(ActiveThreads) do
      Println(Format('  [%d] %s', [I + 1, ActiveThreads[I]]));
    Writeln;
    Write('Resume the first thread? (Y/N): ');
    Readln(Choice);
    if Choice.Trim.ToUpper = 'Y' then
    begin
      BuildGraph;
      Println('Resuming thread: ' + ActiveThreads[0]);
      // 'Finish' is the node that follows the suspension point ('Approve')
      FAgents.ResumeThread(ActiveThreads[0], 'Finish', 'Approved from DB');
      WaitForCompletion;
      FCheckpointer.DeleteCheckpoint(ActiveThreads[0]);
      Println('Checkpoint deleted from DB.');
    end
    else
      Println('Operation cancelled.');
    Exit;
  end;

  // =========================================================================
  // PHASE 1: First run — the agent suspends at "Approve"
  // =========================================================================
  Writeln;
  Println('=== PHASE 1: First run ===');
  Writeln;
  Writeln('  Start -> Process -> Approve (suspends) -> Finish (pending)');
  Writeln;

  BuildGraph;
  FAgents.Run('Solicitud-2026-001');
  WaitForCompletion;

  if FSuspendedThreadID = '' then
  begin
    Println('The agent finished without suspending (unexpected).');
    Exit;
  end;

  // Show state saved in the DB
  Writeln;
  Println('=== CHECKPOINT SAVED IN SQLITE DB ===');
  Println('Thread ID : ' + FSuspendedThreadID);
  Println('DB file   : ' + ChangeFileExt(ParamStr(0), '.db'));
  Println('The state persists. You can restart the app and the thread');
  Println('will appear as suspended when running the demo again.');
  Writeln;

  // =========================================================================
  // PHASE 2: Resume — simulates operator approval
  // =========================================================================
  Println('=== PHASE 2: Resume after approval ===');
  Write('Press ENTER to simulate operator approval...');
  Readln;

  Writeln;
  Println('Resuming execution from "Finish"...');
  // 'Finish' is the first pending node after the suspension point
  FAgents.ResumeThread(FSuspendedThreadID, 'Finish',
    'Approved by human operator');
  WaitForCompletion;

  // Cleanup
  FCheckpointer.DeleteCheckpoint(FSuspendedThreadID);
  Writeln;
  Println('Checkpoint deleted from DB.');
  Println('Demo finished successfully.');
end;

// ---------------------------------------------------------------------------

var
  Demo: TDemo;
begin
  try
    Demo := TDemo.Create;
    try
      Demo.Run;
    finally
      Demo.Free;
    end;
    Writeln;
    Write('Press ENTER to exit...');
    Readln;
  except
    on E: Exception do
    begin
      Writeln('Error fatal: ', E.ClassName, ' - ', E.Message);
      Write('Press ENTER to exit...');
      Readln;
    end;
  end;
end.
