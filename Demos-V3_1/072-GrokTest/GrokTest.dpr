program GrokTest;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - Demo 072: Grok Async Diagnostic
// =============================================================================
// Tests the TAiGrokChat driver in synchronous and asynchronous (streaming) mode.
// Verifica:
//   - Basic text sync/async with grok-3
//   - Reasoning with grok-3-mini (reasoning_effort=low/high, no error 400)
//   - That forbidden parameters are NOT sent in grok-4 / grok-3-mini models
//   - Vision with grok-4-0709 (if the user has access)
//   - Multi-turn async
//
// Configure GROK_API_KEY as an environment variable before running.
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
  uMakerAi.Chat.Grok;

const
  API_KEY = '@GROK_API_KEY';
  // Available models:
  //   'grok-3'               - text + tools, 131K ctx
  //   'grok-3-fast'          - text + tools, 131K ctx (same caps, fast infra)
  //   'grok-3-mini'          - text + reasoning + tools (reasoning_effort: low/high)
  //   'grok-3-mini-fast'     - same as grok-3-mini
  //   'grok-2-vision-1212'   - vision + tools
  //   'grok-4-0709'          - vision + reasoning always active + tools, 256K ctx
  //   'grok-4-fast-reasoning'- vision + reasoning + tools, 2M ctx
  MODEL_TEXT    = 'grok-3';
  MODEL_REASON  = 'grok-3-mini';
  MODEL_VISION  = 'grok-4-0709';

// =============================================================================
//  TGrokTester
// =============================================================================

type
  TGrokTester = class
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

{ TGrokTester }

constructor TGrokTester.Create;
begin
  FDoneEvent   := TEvent.Create(nil, True, False, '');
  FRawChunkLog := TStringList.Create;

  FConn := TAiChatConnection.Create(nil);
  FConn.DriverName := 'Grok';
  FConn.Model      := MODEL_TEXT;
  FConn.Params.Values['ApiKey'] := API_KEY;

  FConn.OnReceiveData     := OnData;
  FConn.OnReceiveDataEnd  := OnDataEnd;
  FConn.OnReceiveThinking := OnThinking;
  FConn.OnError           := OnError;
end;

destructor TGrokTester.Destroy;
begin
  FConn.Free;
  FDoneEvent.Free;
  FRawChunkLog.Free;
  inherited;
end;

procedure TGrokTester.ResetBuffers;
begin
  FBuffer      := '';
  FTokenCount  := 0;
  FThinkBuffer := '';
  FThinkCount  := 0;
  FHasError    := False;
  FError       := '';
  FRawChunkLog.Clear;
end;

procedure TGrokTester.SetAsync(AValue: Boolean);
begin
  if AValue then
    FConn.Params.Values['Asynchronous'] := 'True'
  else
    FConn.Params.Values['Asynchronous'] := 'False';
end;

procedure TGrokTester.OnData(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  // Capture first 3 raw chunks to see Grok's SSE structure
  if Assigned(aResponse) and (FRawChunkLog.Count < 3) then
    FRawChunkLog.Add(Copy(aResponse.ToString, 1, 250));

  if aText <> '' then
  begin
    FBuffer := FBuffer + aText;
    Inc(FTokenCount);
    Write(aText);
  end;
end;

procedure TGrokTester.OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  if aText <> '' then
  begin
    FThinkBuffer := FThinkBuffer + aText;
    Inc(FThinkCount);
  end;
end;

procedure TGrokTester.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  FDoneEvent.SetEvent;
end;

procedure TGrokTester.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FHasError := True;
  FError    := ErrorMsg;
  if Assigned(AException) then
    FError := FError + ' [' + AException.ClassName + ': ' + AException.Message + ']';
  FDoneEvent.SetEvent;
end;

procedure TGrokTester.PrintSeparator(const ATitle: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 70));
  Writeln('  ', ATitle);
  Writeln(StringOfChar('=', 70));
end;

procedure TGrokTester.PrintAsyncResult;
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
      Writeln(Format('  History : %d chars', [Length(LHistorial)]));
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
procedure TGrokTester.TestSync(const AQuestion, AModel, ALabel: String);
var
  Response: String;
begin
  PrintSeparator(ALabel + ' [' + AModel + ']');
  Writeln('Question : ', AQuestion);
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
      Writeln('Response: <empty>')
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
procedure TGrokTester.TestAsync(const AQuestion, AModel, ALabel: String;
  ATimeoutMs: Integer);
var
  WaitResult: TWaitResult;
begin
  PrintSeparator(ALabel + ' [' + AModel + ']');
  Writeln('Question : ', AQuestion);
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
procedure TGrokTester.TestMultiTurnAsync(const AModel: String);

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

    Write('Grok: ');
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
  PrintSeparator('Multi-turn Async [' + AModel + ']');
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
  Tester: TGrokTester;

begin
  Writeln('=== Demo 072 - Grok Async Diagnostic ===');
  Writeln('APIKey : ', API_KEY);
  Writeln;

  Tester := TGrokTester.Create;
  try
    // --- grok-3 (text + tools, no reasoning) ---
    Tester.TestSync(
      'In a single sentence: what is the capital of France?',
      MODEL_TEXT, 'Test 1 - Basic sync');

    Tester.TestAsync(
      'In a single sentence: what is the capital of Japan?',
      MODEL_TEXT, 'Test 2 - Basic async');

    Tester.TestAsync(
      'Explain in 3 short paragraphs what artificial intelligence is.',
      MODEL_TEXT, 'Test 3 - Async long response');

    // --- grok-3-mini (reasoning: reasoning_effort=low, no vision) ---
    // Verifies that frequency/presence/stop are NOT sent (error 400 if sent)
    Tester.TestSync(
      'How much is 347 multiplied by 28? Show the reasoning step by step.',
      MODEL_REASON, 'Test 4 - Sync reasoning');

    Tester.TestAsync(
      'How much is 347 multiplied by 28? Show the reasoning step by step.',
      MODEL_REASON, 'Test 5 - Async reasoning');

    // --- grok-4-0709 (vision + reasoning always active) ---
    // Verifies that reasoning_effort is NOT sent (error if sent)
    Tester.TestSync(
      'In a single sentence: what is the capital of Australia?',
      MODEL_VISION, 'Test 6 - Sync grok-4 (without reasoning_effort)');

    Tester.TestAsync(
      'Explain in 2 short sentences what machine learning is.',
      MODEL_VISION, 'Test 7 - Async grok-4');

    // --- Multi-turn with grok-3 ---
    Tester.TestMultiTurnAsync(MODEL_TEXT);

  finally
    Tester.Free;
  end;

  Writeln;
  Writeln('Demo finished. Press Enter to exit.');
  Readln;
end.
