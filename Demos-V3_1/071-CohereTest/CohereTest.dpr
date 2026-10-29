program CohereTest;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - Demo 071: Cohere Async Diagnostic
// =============================================================================
// Prueba el driver TCohereChat en modo sincrono y asincronico (streaming).
// Muestra cada token recibido en async para detectar problemas de parseo.
// Incluye prueba con modelo reasoning (command-a-reasoning-08-2025).
//
// Configure COHERE_API_KEY as an environment variable before running.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Cohere;

const
  API_KEY = '@COHERE_API_KEY';
  // Available models:
  //   'command-a-03-2025'           - texto + tools, 256K ctx (flagship)
  //   'command-a-reasoning-08-2025' - texto + tools + reasoning, 32K output
  //   'command-a-vision-07-2025'    - vision, sin tools
  //   'command-r7b-12-2024'         - ligero, texto + tools
  MODEL_TEXT     = 'command-a-03-2025';
  MODEL_REASON   = 'command-a-reasoning-08-2025';

// =============================================================================
//  TCohereTest
// =============================================================================

type
  TCohereTest = class
  private
    FConn        : TAiChatConnection;
    FDoneEvent   : TEvent;
    FBuffer      : String;
    FTokenCount  : Integer;
    FThinkBuffer : String;
    FThinkCount  : Integer;
    FError       : String;
    FHasError    : Boolean;
    FRawChunkLog : TStringList;

    procedure OnData(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);

    procedure PrintSeparator(const ATitle: String);
    procedure SetAsync(AValue: Boolean);
    procedure ResetBuffers;
    procedure PrintAsyncResult;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure TestSync(const AQuestion, AModel, ALabel: String);
    procedure TestAsync(const AQuestion, AModel, ALabel: String;
      ATimeoutMs: Integer = 120000);
    procedure TestMultiTurnAsync(const AModel: String);
  end;

{ TCohereTest }

constructor TCohereTest.Create;
begin
  FDoneEvent   := TEvent.Create(nil, True, False, '');
  FRawChunkLog := TStringList.Create;

  FConn := TAiChatConnection.Create(nil);
  FConn.DriverName := 'Cohere';
  FConn.Model      := MODEL_TEXT;
  FConn.Params.Values['ApiKey'] := API_KEY;

  FConn.OnReceiveData    := OnData;
  FConn.OnReceiveDataEnd := OnDataEnd;
  FConn.OnReceiveThinking := OnThinking;
  FConn.OnError          := OnError;
end;

destructor TCohereTest.Destroy;
begin
  FConn.Free;
  FDoneEvent.Free;
  FRawChunkLog.Free;
  inherited;
end;

procedure TCohereTest.ResetBuffers;
begin
  FBuffer      := '';
  FTokenCount  := 0;
  FThinkBuffer := '';
  FThinkCount  := 0;
  FHasError    := False;
  FError       := '';
  FRawChunkLog.Clear;
end;

procedure TCohereTest.SetAsync(AValue: Boolean);
begin
  if AValue then
    FConn.Params.Values['Asynchronous'] := 'True'
  else
    FConn.Params.Values['Asynchronous'] := 'False';
end;

procedure TCohereTest.OnData(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  // Capture first 3 raw chunks to see Cohere's SSE structure
  if Assigned(aResponse) and (FRawChunkLog.Count < 3) then
    FRawChunkLog.Add(Copy(aResponse.ToString, 1, 250));

  if aText <> '' then
  begin
    FBuffer := FBuffer + aText;
    Inc(FTokenCount);
    Write(aText);
  end;
end;

procedure TCohereTest.OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  if aText <> '' then
  begin
    FThinkBuffer := FThinkBuffer + aText;
    Inc(FThinkCount);
  end;
end;

procedure TCohereTest.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  FDoneEvent.SetEvent;
end;

procedure TCohereTest.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FHasError := True;
  FError    := ErrorMsg;
  if Assigned(AException) then
    FError := FError + ' [' + AException.ClassName + ': ' + AException.Message + ']';
  FDoneEvent.SetEvent;
end;

procedure TCohereTest.PrintSeparator(const ATitle: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 70));
  Writeln('  ', ATitle);
  Writeln(StringOfChar('=', 70));
end;

procedure TCohereTest.PrintAsyncResult;
var
  LHistorial, LReasoning: String;
begin
  Writeln;
  Writeln(StringOfChar('-', 70));

  if FHasError then
  begin
    Writeln('ERROR: ', FError);
    Exit;
  end;

  // Raw chunks
  if FRawChunkLog.Count > 0 then
  begin
    Writeln('--- RAW SSE chunks (first ' + IntToStr(FRawChunkLog.Count) + ') ---');
    var i: Integer;
    for i := 0 to FRawChunkLog.Count - 1 do
      Writeln('  [' + IntToStr(i) + '] ' + FRawChunkLog[i]);
    Writeln;
  end;

  // Thinking
  if FThinkCount > 0 then
  begin
    Writeln(Format('Thinking chunks : %d  (%d chars)', [FThinkCount, Length(FThinkBuffer)]));
    Writeln('Thinking preview: ' + Copy(FThinkBuffer, 1, 120) + '...');
    Writeln;
  end
  else
    Writeln('Thinking chunks : 0  (no reasoning in this model/mode)');

  Writeln(Format('Text chunks     : %d  (%d chars in buffer)', [FTokenCount, Length(FBuffer)]));

  // Consistency with history
  if FConn.GetLastMessage <> nil then
  begin
    LHistorial := FConn.GetLastMessage.Prompt;
    LReasoning := FConn.GetLastMessage.ReasoningContent;
    Writeln(Format('History Prompt: %d chars', [Length(LHistorial)]));
    if LReasoning <> '' then
      Writeln(Format('History Reason: %d chars', [Length(LReasoning)]));

    Writeln;
    Writeln('--- Answer ---');
    Writeln(FBuffer);

    if LHistorial <> FBuffer then
    begin
      Writeln;
      Writeln('*** DISCREPANCY buffer vs history ***');
      Writeln(Format('  Buffer    : %d chars', [Length(FBuffer)]));
      Writeln(Format('  Historial : %d chars', [Length(LHistorial)]));
      Writeln('  Buffer    start: [' + Copy(FBuffer, 1, 40) + ']');
      Writeln('  History start: [' + Copy(LHistorial, 1, 40) + ']');
      Writeln('  Buffer    end   : [' + Copy(FBuffer, Length(FBuffer)-39, 40) + ']');
      Writeln('  History end     : [' + Copy(LHistorial, Length(LHistorial)-39, 40) + ']');
    end
    else
      Writeln('  [OK] Buffer and history match.');
  end;
end;

// -----------------------------------------------------------------------------
//  TestSync
// -----------------------------------------------------------------------------
procedure TCohereTest.TestSync(const AQuestion, AModel, ALabel: String);
var
  Response: String;
begin
  PrintSeparator(ALabel + ' [' + AModel + ']');
  Writeln('Pregunta : ', AQuestion);
  Writeln(StringOfChar('-', 70));

  ResetBuffers;
  FConn.Model := AModel;
  FConn.NewChat;
  SetAsync(False);
  try
    Response := FConn.AddMessageAndRun(AQuestion, 'user', []);
    if FHasError then
      Writeln('ERROR: ', FError)
    else if Response = '' then
      Writeln('Respuesta: <vacia>')
    else
      Writeln('Answer: ', Response);
  except
    on E: Exception do
      Writeln('EXCEPTION: ', E.ClassName, ' - ', E.Message);
  end;
end;

// -----------------------------------------------------------------------------
//  TestAsync
// -----------------------------------------------------------------------------
procedure TCohereTest.TestAsync(const AQuestion, AModel, ALabel: String;
  ATimeoutMs: Integer);
var
  WaitResult: TWaitResult;
begin
  PrintSeparator(ALabel + ' [' + AModel + ']');
  Writeln('Pregunta : ', AQuestion);
  Writeln(StringOfChar('-', 70));

  ResetBuffers;
  FConn.Model := AModel;
  FConn.NewChat;
  SetAsync(True);
  FDoneEvent.ResetEvent;

  Write('[streaming] ');
  try
    FConn.AddMessageAndRun(AQuestion, 'user', []);
  except
    on E: Exception do
    begin
      Writeln;
      Writeln('ERROR calling AddMessageAndRun: ', E.Message);
      Exit;
    end;
  end;

  WaitResult := FDoneEvent.WaitFor(ATimeoutMs);
  if WaitResult = wrTimeout then
  begin
    Writeln;
    Writeln('TIMEOUT (' + IntToStr(ATimeoutMs) + ' ms)');
    Exit;
  end;

  PrintAsyncResult;
end;

// -----------------------------------------------------------------------------
//  TestMultiTurnAsync
// -----------------------------------------------------------------------------
procedure TCohereTest.TestMultiTurnAsync(const AModel: String);

  procedure SendTurn(const AQuestion: String; ATurn: Integer);
  var
    WaitResult: TWaitResult;
  begin
    Writeln;
    Writeln(Format('-- Turn %d --', [ATurn]));
    Writeln('User: ', AQuestion);

    ResetBuffers;
    FDoneEvent.ResetEvent;
    SetAsync(True);

    Write('Cohere: ');
    FConn.AddMessageAndRun(AQuestion, 'user', []);
    WaitResult := FDoneEvent.WaitFor(120000);

    Writeln;
    if WaitResult = wrSignaled then
    begin
      if FHasError then
        Writeln('  ERROR: ', FError)
      else
      begin
        if FThinkCount > 0 then
          Writeln(Format('  [thinking: %d chunks]', [FThinkCount]));
        Writeln(Format('  [text: %d chunks, %d chars]', [FTokenCount, Length(FBuffer)]));
      end;
    end
    else
      Writeln('  TIMEOUT');
  end;

begin
  PrintSeparator('Multi-turno Async [' + AModel + ']');
  FConn.Model := AModel;
  FConn.NewChat;

  SendTurn('Hello! My name is Gustavo. Remember it.', 1);
  SendTurn('What is my name?', 2);
  SendTurn('How many messages have we exchanged in this conversation?', 3);

  Writeln;
  Writeln(Format('Messages in history: %d', [FConn.Messages.Count]));
end;

// =============================================================================
//  MAIN
// =============================================================================

var
  Tester: TCohereTest;

begin
  Writeln('=== Demo 071 - Cohere Async Diagnostic ===');
  Writeln('APIKey : ', API_KEY);
  Writeln;

  Tester := TCohereTest.Create;
  try
    // --- command-a-03-2025 (text + tools, no reasoning) ---
    Tester.TestSync(
      'En una sola oracion: cual es la capital de Francia?',
      MODEL_TEXT, 'Test 1 - Sync basico');

    Tester.TestAsync(
      'En una sola oracion: cual es la capital de Japon?',
      MODEL_TEXT, 'Test 2 - Async basico');

    Tester.TestAsync(
      'Explica en 3 parrafos breves que es la inteligencia artificial.',
      MODEL_TEXT, 'Test 3 - Async respuesta larga');

    // --- command-a-reasoning-08-2025 (reasoning) ---
    Tester.TestSync(
      'Cuanto es 347 multiplicado por 28? Muestra el razonamiento.',
      MODEL_REASON, 'Test 4 - Sync reasoning');

    Tester.TestAsync(
      'Cuanto es 347 multiplicado por 28? Muestra el razonamiento.',
      MODEL_REASON, 'Test 5 - Async reasoning');

    // --- Multi-turn with command-a ---
    Tester.TestMultiTurnAsync(MODEL_TEXT);

  finally
    Tester.Free;
  end;

  Writeln;
  Writeln('Demo finished. Press Enter to exit.');
  Readln;
end.
