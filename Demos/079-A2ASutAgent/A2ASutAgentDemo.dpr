program A2ASutAgentDemo;

// =============================================================================
// DEMO 079 - SUT agent conforming to the official A2A TCK
// =============================================================================
// The TCK (a2aproject/a2a-tck) does not only validate the protocol: to be
// able to test certain things it needs the agent under test to implement a
// scenario contract. It dispatches by the messageId PREFIX, not by the text:
//
//   tck-artifact-text      -> artifact with a TextPart "Generated text content"
//   tck-artifact-data      -> artifact with a DataPart {"key":"value","count":42}
//   tck-artifact-file      -> artifact with a FilePart of bytes (raw + filename)
//   tck-artifact-file-url  -> artifact with a FilePart by URL
//   tck-message-response   -> responds with a Message, not a Task
//   tck-input-required     -> leaves the task in input-required
//   tck-complete-task      -> completes with an agent message
//
// This demo serves two purposes at once:
//   1. It is the System Under Test used to run the full TCK.
//   2. It is the example of how to emit STRUCTURED artifacts from a graph,
//      which is the capability that was missing: until now a MakerAI agent could
//      only return plain text.
//
// The channel is the blackboard. The server seeds A2A.MessageId / A2A.TaskId /
// A2A.ContextId before running the graph, and when it finishes reads:
//   A2A.Artifacts -> JSON array of artifacts, emitted as is
//   A2A.Message   -> Message object; if present, SendMessage responds with the
//                    {"message": ...} arm of the oneof instead of {"task": ...}
//
// Usage:
//   A2ASutAgentDemo.exe [--port 9999]
//
// And in another console, the TCK:
//   python run_tck.py --sut-host http://localhost:9999 --level must
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  uMakerAi.Agents,
  uMakerAi.A2A.Server in '..\..\Source\Agents\uMakerAi.A2A.Server.pas',
  uMakerAi.Telemetry;

type
  TSutHandlers = class
  public
    procedure Escenario(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string; var Output: string);
    // Pool factory. Without this the TCK fails: it sends concurrent requests and
    // a single TAIAgentManager does not run two graphs at once, so the
    // second receives AgentBusy (-32000) and breaks envelope validation.
    procedure FabricaManager(Sender: TObject; var AManager: TAIAgentManager);
  end;

  // ---------------------------------------------------------------------------
  // Helpers to build artifacts conforming to spec 1.0.
  // In v1.0 there are no TextPart/DataPart/FilePart as distinct types: there is a
  // single Part and the content is determined by WHICH field is present (text, data, raw,
  // url), with optional mediaType and filename.
  // ---------------------------------------------------------------------------

function NuevoArtifact(const AId, ANombre: string; APart: TJSONObject): string;
var
  Arr: TJSONArray;
  Art: TJSONObject;
  Parts: TJSONArray;
begin
  Art := TJSONObject.Create;
  Art.AddPair('artifactId', AId);
  Art.AddPair('name', ANombre);
  Parts := TJSONArray.Create;
  Parts.AddElement(APart);
  Art.AddPair('parts', Parts);
  Arr := TJSONArray.Create;
  Arr.AddElement(Art);
  try
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

function PartTexto(const ATexto: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('text', ATexto);
end;

function PartDatos(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('data', TJSONObject.ParseJSONValue(AJson));
end;

function PartArchivoBytes(const ABytes, AMediaType, ANombre: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  // 'raw' travels in base64 through ProtoJSON (proto bytes are serialized this way)
  Result.AddPair('raw', TNetEncoding.Base64.Encode(ABytes));
  Result.AddPair('mediaType', AMediaType);
  Result.AddPair('filename', ANombre);
end;

function PartArchivoUrl(const AUrl, AMediaType, ANombre: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('url', AUrl);
  Result.AddPair('mediaType', AMediaType);
  Result.AddPair('filename', ANombre);
end;

function MensajeAgente(const ATexto, ATaskId, AContextId: string): string;
var
  Msg: TJSONObject;
  Parts: TJSONArray;
begin
  Msg := TJSONObject.Create;
  try
    Msg.AddPair('messageId', 'sut-' + ATaskId);
    Msg.AddPair('role', 'ROLE_AGENT');
    if ATaskId <> '' then
      Msg.AddPair('taskId', ATaskId);
    if AContextId <> '' then
      Msg.AddPair('contextId', AContextId);
    Parts := TJSONArray.Create;
    Parts.AddElement(PartTexto(ATexto));
    Msg.AddPair('parts', Parts);
    Result := Msg.ToJSON;
  finally
    Msg.Free;
  end;
end;

// -----------------------------------------------------------------------------

procedure TSutHandlers.Escenario(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: string;
  var Output: string);
var
  B: TAIBlackboard;
  MsgId, TaskId, CtxId: string;
begin
  B := Node.Graph.Blackboard;
  // The TCK dispatches by the messageId prefix, not by the content
  MsgId := B.GetString(A2A_BB_MESSAGE_ID);
  TaskId := B.GetString(A2A_BB_TASK_ID);
  CtxId := B.GetString(A2A_BB_CONTEXT_ID);
  Output := Input;

  Writeln(Format('  [SUT] messageId=%s', [MsgId]));

  // NOTE the order: 'tck-artifact-file-url' starts with 'tck-artifact-file',
  // so the more specific variant goes first.
  if MsgId.StartsWith('tck-artifact-file-url') then
    B.SetString(A2A_BB_ARTIFACTS, NuevoArtifact(TaskId + '-a', 'output',
      PartArchivoUrl('https://example.com/output.txt', 'text/plain', 'output.txt')))

  else if MsgId.StartsWith('tck-artifact-file') then
    B.SetString(A2A_BB_ARTIFACTS, NuevoArtifact(TaskId + '-a', 'output',
      PartArchivoBytes('tck', 'text/plain', 'output.txt')))

  else if MsgId.StartsWith('tck-artifact-text') then
    B.SetString(A2A_BB_ARTIFACTS, NuevoArtifact(TaskId + '-a', 'output',
      PartTexto('Generated text content')))

  else if MsgId.StartsWith('tck-artifact-data') then
    B.SetString(A2A_BB_ARTIFACTS, NuevoArtifact(TaskId + '-a', 'output',
      PartDatos('{"key": "value", "count": 42}')))

  else if MsgId.StartsWith('tck-message-response') then
    // The 'message' arm of the oneof: respond without creating a task
    B.SetString(A2A_BB_MESSAGE, MensajeAgente('Direct message response', TaskId, CtxId))

  else if MsgId.StartsWith('tck-complete-task') then
    Output := 'Hello from TCK'

  else if MsgId.StartsWith('tck-input-required') then
    Node.Suspend('The TCK requested input', 'tck-input-required')

  else
    Output := 'echo: ' + Input;
end;

procedure TSutHandlers.FabricaManager(Sender: TObject; var AManager: TAIAgentManager);
begin
  AManager := TAIAgentManager.Create(nil); // the server frees it
  AManager.AddNode('Escenario', Escenario);
  AManager.SetEntryPoint('Escenario').SetFinishPoint('Escenario');
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

var
  Server: TAiA2AServer;
  Agente: TAIAgentManager;
  Handlers: TSutHandlers;
  Port: Integer;

begin
  try
    Port := StrToIntDef(ArgValue('--port', '9999'), 9999);

    Handlers := TSutHandlers.Create;
    Agente := TAIAgentManager.Create(nil);
    Server := TAiA2AServer.Create(nil);
    try
      Agente.Name := 'SutAgent';
      Agente.AddNode('Escenario', Handlers.Escenario);
      Agente.SetEntryPoint('Escenario').SetFinishPoint('Escenario');

      Server.AgentManager := Agente;
      Server.AgentName := 'MakerAI TCK SUT';
      Server.AgentDescription := 'Conformance agent for the official A2A TCK';
      Server.Port := Port;
      Server.PublishExtendedCard := True;
      Server.OnAcquireManager := Handlers.FabricaManager;
      // High on purpose: a task suspended in input-required RETAINS its
      // manager -it is the only one that can resume it- and the TCK creates many.
      Server.MaxConcurrentTasks := 64;
      Server.Active := True;

      Writeln('=== DEMO 079: SUT agent conforming to the A2A TCK ===');
      Writeln('');
      Writeln(Format('Listening on http://localhost:%d/', [Port]));
      Writeln(Format('Agent Card:    http://localhost:%d/.well-known/agent-card.json', [Port]));
      Writeln('');
      Writeln('Now, from the TCK:');
      Writeln(Format('  python run_tck.py --sut-host http://localhost:%d --level must', [Port]));
      Writeln('');
      Writeln('Ctrl+C to stop.');
      Writeln('');

      while True do
      begin
        CheckSynchronize(200);
        Sleep(50);
      end;
    finally
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
