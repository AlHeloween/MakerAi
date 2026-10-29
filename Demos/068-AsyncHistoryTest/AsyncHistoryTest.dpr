program AsyncHistoryTest;

{$APPTYPE CONSOLE}
{$R *.res}

// Runtime test of ISSUE #105: in async, Claude must archive its responses in
// history to avoid repeating/forgetting. Multi-turn async conversation; the last turn
// must remember data given in previous turns.

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.Initializations;

type
  TAsync = class
  public
    FDone: TEvent;
    FResult, FError: string;
    constructor Create;
    destructor Destroy; override;
    procedure OnEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: string);
    procedure OnError(Sender: TObject; const ErrorMsg: string; AException: Exception; const AResponse: IHTTPResponse);
    function Wait: string;
  end;

constructor TAsync.Create;
begin
  inherited;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TAsync.Destroy;
begin
  FDone.Free;
  inherited;
end;

procedure TAsync.OnEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: string);
begin
  FResult := aText;
  FDone.SetEvent;
end;

procedure TAsync.OnError(Sender: TObject; const ErrorMsg: string; AException: Exception; const AResponse: IHTTPResponse);
begin
  FError := ErrorMsg;
  if Assigned(AResponse) and (AResponse.StatusCode > 0) then
    FError := 'HTTP=' + IntToStr(AResponse.StatusCode) + ' | ' + FError;
  FDone.SetEvent;
end;

function TAsync.Wait: string;
begin
  while FDone.WaitFor(0) <> wrSignaled do
    CheckSynchronize(100);
  if FError <> '' then
    Result := 'ERROR: ' + FError
  else
    Result := FResult;
end;

procedure RunTurn(Conn: TAiChatConnection; H: TAsync; const Q: string);
begin
  H.FResult := '';
  H.FError := '';
  H.FDone.ResetEvent;
  WriteLn('  Q: ' + Q);
  Conn.AddMessageAndRun(Q, 'user', []);
  WriteLn('  A: ' + Trim(H.Wait));
  WriteLn('');
end;

var
  Conn: TAiChatConnection;
  H: TAsync;
  LFinal: string;

begin
  try
    H := TAsync.Create;
    Conn := TAiChatConnection.Create(nil);
    try
      Conn.DriverName := 'Claude';
      Conn.Model := 'claude-opus-4-8';
      Conn.Params.Values['ApiKey'] := '@CLAUDE_API_KEY';
      Conn.Params.Values['Asynchronous'] := 'True';
      Conn.Params.Values['Max_Tokens'] := '200';
      Conn.Params.Values['Tool_Active'] := 'False';
      Conn.OnReceiveDataEnd := H.OnEnd;
      Conn.OnError := H.OnError;

      WriteLn('=== ISSUE #105: history in async (claude-opus-4-8) ===');
      WriteLn('');
      RunTurn(Conn, H, 'My favorite color is blue. Reply only: ok.');
      RunTurn(Conn, H, 'My lucky number is 42. Reply only: ok.');
      RunTurn(Conn, H, 'In one sentence, tell me my favorite color and my lucky number.');
      LFinal := LowerCase(H.FResult);

      WriteLn('=== Verdict ===');
      WriteLn(Format('  messages in history: %d', [Conn.Messages.Count]));
      if (Pos('azul', LFinal) > 0) and (Pos('42', LFinal) > 0) then
        WriteLn('OK: remembered color (blue) and number (42) from previous context -> async history correct.')
      else
        WriteLn('FAIL: did not remember previous context (blue/42) -> incomplete async history (#105).');
    finally
      Conn.Free;
      H.Free;
    end;
    WriteLn('=== END ===');
  except
    on E: Exception do
      WriteLn('FATAL: ' + E.ClassName + ': ' + E.Message);
  end;
end.
