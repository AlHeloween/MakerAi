program KimiTest;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI - Demo 070: Kimi Async Diagnostic
// =============================================================================
// Tests the TAiKimiChat driver in synchronous and asynchronous (streaming) mode.
// Shows each token received in async to detect parsing issues.
//
// Configure KIMI_API_KEY as an environment variable before running.
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
  uMakerAi.Chat.Kimi;

const
  API_KEY = '@KIMI_API_KEY';
  // Available models:
  //   'kimi-k2'          - text + tools, 256K ctx
  //   'kimi-k2.5'        - vision + PDF + reasoning + tools
  //   'kimi-k2-thinking' - reasoning + tools, no vision
  //   'moonshot-v1-8k'   - stable legacy
  MODEL   = 'kimi-k2.5';

// =============================================================================
//  TKimiTester
// =============================================================================

type
  TKimiTester = class
  private
    FConn        : TAiChatConnection;
    FDoneEvent   : TEvent;
    FBuffer      : String;
    FTokenCount  : Integer;
    FThinkBuffer  : String;
    FThinkCount   : Integer;
    FError        : String;
    FHasError     : Boolean;
    FRawChunkLog  : TStringList;  // first N raw chunks for diagnostics

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
  public
    constructor Create;
    destructor  Destroy; override;

    procedure TestSync(const AQuestion: String; const ALabel: String = '');
    procedure TestAsync(const AQuestion: String; const ALabel: String = '';
      ATimeoutMs: Integer = 120000);
    procedure TestMultiTurnAsync;
  end;

{ TKimiTester }

constructor TKimiTester.Create;
begin
  FDoneEvent    := TEvent.Create(nil, True, False, '');
  FRawChunkLog  := TStringList.Create;

  FConn := TAiChatConnection.Create(nil);
  FConn.DriverName := 'Kimi';
  FConn.Model      := MODEL;
  FConn.Params.Values['ApiKey'] := API_KEY;

  FConn.OnReceiveData    := OnData;
  FConn.OnReceiveDataEnd := OnDataEnd;
  FConn.OnReceiveThinking := OnThinking;
  FConn.OnError          := OnError;
end;

destructor TKimiTester.Destroy;
begin
  FConn.Free;
  FDoneEvent.Free;
  FRawChunkLog.Free;
  inherited;
end;

procedure TKimiTester.ResetBuffers;
begin
  FBuffer      := '';
  FTokenCount  := 0;
  FThinkBuffer := '';
  FThinkCount  := 0;
  FHasError    := False;
  FError       := '';
  FRawChunkLog.Clear;
end;

procedure TKimiTester.SetAsync(AValue: Boolean);
begin
  if AValue then
    FConn.Params.Values['Asynchronous'] := 'True'
  else
    FConn.Params.Values['Asynchronous'] := 'False';
end;

procedure TKimiTester.OnData(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  // Capture first 5 raw chunks to see Kimi's JSON structure
  if Assigned(aResponse) and (FRawChunkLog.Count < 5) then
    FRawChunkLog.Add(aResponse.ToString);

  if aText <> '' then
  begin
    FBuffer := FBuffer + aText;
    Inc(FTokenCount);
    Write(aText);
  end;
end;

procedure TKimiTester.OnThinking(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  if aText <> '' then
  begin
    FThinkBuffer := FThinkBuffer + aText;
    Inc(FThinkCount);
  end;
end;

procedure TKimiTester.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
begin
  FDoneEvent.SetEvent;
end;

procedure TKimiTester.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  FHasError := True;
  FError    := ErrorMsg;
  if Assigned(AException) then
    FError := FError + ' [' + AException.ClassName + ': ' + AException.Message + ']';
  FDoneEvent.SetEvent;
end;

procedure TKimiTester.PrintSeparator(const ATitle: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 70));
  Writeln('  ', ATitle);
  Writeln(StringOfChar('=', 70));
end;

// -----------------------------------------------------------------------------
//  TestSync
// -----------------------------------------------------------------------------
procedure TKimiTester.TestSync(const AQuestion: String; const ALabel: String);
var
  Response: String;
  LLabel: String;
begin
  if ALabel <> '' then LLabel := ALabel else LLabel := 'Sync';
  PrintSeparator(LLabel);
  Writeln('Question : ', AQuestion);
  Writeln(StringOfChar('-', 70));

  ResetBuffers;
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
procedure TKimiTester.TestAsync(const AQuestion: String; const ALabel: String;
  ATimeoutMs: Integer);
var
  WaitResult: TWaitResult;
  LLabel: String;
begin
  if ALabel <> '' then LLabel := ALabel else LLabel := 'Async';
  PrintSeparator(LLabel);
  Writeln('Question : ', AQuestion);
  Writeln(StringOfChar('-', 70));

  ResetBuffers;
  FConn.NewChat;
  SetAsync(True);
  FDoneEvent.ResetEvent;

  Writeln('[thinking...]');
  try
    FConn.AddMessageAndRun(AQuestion, 'user', []);
  except
    on E: Exception do
    begin
      Writeln('ERROR calling AddMessageAndRun: ', E.Message);
      Exit;
    end;
  end;

  WaitResult := FDoneEvent.WaitFor(ATimeoutMs);

  Writeln;
  Writeln(StringOfChar('-', 70));

  case WaitResult of
    wrSignaled:
      if FHasError then
        Writeln('ERROR recibido: ', FError)
      else
      begin
        // Dump first raw chunks for reasoning field diagnostics
        if FRawChunkLog.Count > 0 then
        begin
          Writeln('--- RAW SSE chunks (first ' + IntToStr(FRawChunkLog.Count) + ') ---');
          var i: Integer;
          for i := 0 to FRawChunkLog.Count - 1 do
            Writeln('  [' + IntToStr(i) + '] ' + Copy(FRawChunkLog[i], 1, 200));
          Writeln;
        end;

        // Thinking summary (if any)
        if FThinkCount > 0 then
        begin
          Writeln(Format('Thinking chunks : %d  (%d chars)', [FThinkCount, Length(FThinkBuffer)]));
          Writeln('Thinking preview: ', Copy(FThinkBuffer, 1, 120), '...');
          Writeln;
        end
        else
          Writeln('Thinking chunks : 0  (no reasoning in this model/mode)');

        Writeln(Format('Text chunks     : %d  (%d chars in buffer)', [FTokenCount, Length(FBuffer)]));

        // Verify consistency with history
        if FConn.GetLastMessage <> nil then
        begin
          var LHistorial := FConn.GetLastMessage.Prompt;
          var LReasoning := FConn.GetLastMessage.ReasoningContent;
          Writeln(Format('History Prompt: %d chars', [Length(LHistorial)]));
          if LReasoning <> '' then
            Writeln(Format('History Reason: %d chars', [Length(LReasoning)]));

          Writeln;
          Writeln('--- Answer (streaming buffer) ---');
          Writeln(FBuffer);

          if LHistorial <> FBuffer then
          begin
            Writeln;
            Writeln('*** DISCREPANCY buffer vs history ***');
            Writeln(Format('  Buffer    : %d chars', [Length(FBuffer)]));
            Writeln(Format('  History : %d chars', [Length(LHistorial)]));
            // Show first/last chars to see difference
            Writeln('  Buffer    start: [' + Copy(FBuffer, 1, 30) + ']');
            Writeln('  History start: [' + Copy(LHistorial, 1, 30) + ']');
            Writeln('  Buffer    end   : [' + Copy(FBuffer, Length(FBuffer)-29, 30) + ']');
            Writeln('  History end     : [' + Copy(LHistorial, Length(LHistorial)-29, 30) + ']');
          end
          else
            Writeln('  [OK] Buffer and history match.');
        end;
      end;
    wrTimeout:
      Writeln('TIMEOUT (' + IntToStr(ATimeoutMs) + ' ms)');
  else
    Writeln('WaitFor: ', Ord(WaitResult));
  end;
end;

// -----------------------------------------------------------------------------
//  TestMultiTurnAsync
// -----------------------------------------------------------------------------
procedure TKimiTester.TestMultiTurnAsync;

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

    Write('Kimi: ');
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
  PrintSeparator('Multi-turn Async');
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
  Tester: TKimiTester;

begin
  Writeln('=== Demo 070 - Kimi Async Diagnostic ===');
  Writeln('Model  : ', MODEL);
  Writeln('APIKey : ', API_KEY);
  Writeln;

  Tester := TKimiTester.Create;
  try
    Tester.TestSync(
      'In a single sentence: what is the capital of France?',
      'Test 1 - Basic sync');

    Tester.TestAsync(
      'In a single sentence: what is the capital of Japan?',
      'Test 2 - Basic async');

    Tester.TestAsync(
      'Explain in 3 short paragraphs what artificial intelligence is.',
      'Test 3 - Async long response');

    Tester.TestMultiTurnAsync;

  finally
    Tester.Free;
  end;

  Writeln;
  Writeln('Demo finished. Press Enter to exit.');
  Readln;
end.
