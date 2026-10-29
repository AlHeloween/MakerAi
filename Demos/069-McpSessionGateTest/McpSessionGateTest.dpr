program McpSessionGateTest;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// Runtime test of ISSUE #110: MCP client vetting (OnClientConnect) + HTTP
// session gate by Mcp-Session-Id (Part A + Part B).
//
// Starts a real TAiMCPHttpServer (Indy) with an 'echo' tool and tests it as
// an HTTP client (THTTPClient). Validates 4 scenarios with automatic asserts:
//   PHASE 1  gating OFF (without OnClientConnect) -> tools/call works without a session.
//   PHASE 2  gating ON  -> tools/call without session = -32001; initialize emits
//           Mcp-Session-Id; tools/call with that session = OK; invalid session = -32001.
//   PHASE 3  OnUnauthorizedRequest grants access (AAllow:=True) -> tool executes.
//   PHASE 4  OnClientConnect rejects (AAllow:=False) -> initialize = error, no session.
//
// 100% local, requires no API keys. Exit code 0 if everything passes.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  UMakerAi.MCPServer.Http,
  uMakerAi.MCPServer.Core;

const
  TEST_PORT = 8765;
  BASE_URL  = 'http://localhost:8765/mcp';
  ECHO_MARK = 'ECHO_OK'; // fixed marker: proves the tool ran without depending on the param

type
  // Parameters of the echo tool (deserialized from 'arguments' via RTTI)
  TEchoParams = class
  private
    FText: string;
  public
    property Text: string read FText write FText;
  end;

  TEchoTool = class(TAiMCPToolBase<TEchoParams>)
  protected
    function ExecuteWithParams(const AParams: TEchoParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  // Hosts event handlers (of object) and observable counters.
  THarness = class
  public
    ConnectFired: Boolean;
    LastClientName: string;
    RejectClient: string; // if clientInfo.name matches (case-insensitive) -> reject
    UnauthFired: Boolean;
    AllowUnauth: Boolean; // value the handler sets in AAllow
    procedure HandleClientConnect(Sender: TObject; const AClientName, AClientVersion, AProtocolVersion: string;
      var AAllow: Boolean; var AReason: string);
    procedure HandleUnauthorized(Sender: TObject; const ASessionID, AMethod: string;
      var AAllow: Boolean; var AReason: string);
  end;

var
  GPass, GFail: Integer;

{ TEchoTool }

constructor TEchoTool.Create;
begin
  inherited;
  FName := 'echo';
  FDescription := 'Returns the received text (with a fixed execution marker)';
end;

function TEchoTool.ExecuteWithParams(const AParams: TEchoParams; const AuthContext: TAiAuthContext): TJSONObject;
begin
  Result := TAiMCPResponseBuilder.New.AddText(ECHO_MARK + ':' + AParams.Text).Build;
end;

{ THarness }

procedure THarness.HandleClientConnect(Sender: TObject; const AClientName, AClientVersion, AProtocolVersion: string;
  var AAllow: Boolean; var AReason: string);
begin
  ConnectFired := True;
  LastClientName := AClientName;
  if (RejectClient <> '') and SameText(AClientName, RejectClient) then
  begin
    AAllow := False;
    AReason := 'Client ' + AClientName + ' is not allowed by server policy';
  end;
end;

procedure THarness.HandleUnauthorized(Sender: TObject; const ASessionID, AMethod: string;
  var AAllow: Boolean; var AReason: string);
begin
  UnauthFired := True;
  AAllow := AllowUnauth;
end;

{ Helpers }

procedure Check(ACond: Boolean; const ALabel: string);
begin
  if ACond then
  begin
    Inc(GPass);
    WriteLn('  [PASS] ' + ALabel);
  end
  else
  begin
    Inc(GFail);
    WriteLn('  [FAIL] ' + ALabel);
  end;
end;

function GetRespHeader(const Resp: IHTTPResponse; const AName: string): string;
var
  H: TNameValuePair;
begin
  Result := '';
  for H in Resp.Headers do
    if SameText(H.Name, AName) then
      Exit(H.Value);
end;

function DoPost(const ABody, ASessionId: string; out AStatus: Integer; out ARespBody, ARespSession: string): Boolean;
var
  C: THTTPClient;
  SS: TStringStream;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Result := False;
  AStatus := 0;
  ARespBody := '';
  ARespSession := '';
  C := THTTPClient.Create;
  SS := TStringStream.Create(ABody, TEncoding.UTF8);
  try
    try
      if ASessionId <> '' then
        Headers := [TNameValuePair.Create('Content-Type', 'application/json'),
          TNameValuePair.Create('Mcp-Session-Id', ASessionId)]
      else
        Headers := [TNameValuePair.Create('Content-Type', 'application/json')];
      Resp := C.Post(BASE_URL, SS, nil, Headers);
      AStatus := Resp.StatusCode;
      ARespBody := Resp.ContentAsString(TEncoding.UTF8);
      ARespSession := GetRespHeader(Resp, 'Mcp-Session-Id');
      Result := True;
    except
      on E: Exception do
        WriteLn('  [HTTP ERR] ' + E.Message);
    end;
  finally
    SS.Free;
    C.Free;
  end;
end;

function InitBody(const AClientName: string): string;
begin
  Result := Format('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
    '{"protocolVersion":"2025-06-18","clientInfo":{"name":"%s","version":"1.0"}}}', [AClientName]);
end;

function CallEchoBody: string;
begin
  Result := '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":' +
    '{"name":"echo","arguments":{"text":"hola"}}}';
end;

var
  Server: TAiMCPHttpServer;
  H: THarness;
  st: Integer;
  body, sess, sid: string;

begin
  GPass := 0;
  GFail := 0;
  try
    H := THarness.Create;
    Server := TAiMCPHttpServer.Create(nil);
    try
      Server.Port := TEST_PORT;
      Server.CorsEnabled := True;
      Server.RegisterTool('echo',
        function: IAiMCPTool
        begin
          Result := TEchoTool.Create;
        end);
      Server.Start;
      WriteLn('=== ISSUE #110: MCP OnClientConnect + session gate ===');
      WriteLn('MCP HTTP server listening on ' + BASE_URL);
      WriteLn('');

      // ===================== PHASE 1: gating OFF =====================
      WriteLn('== PHASE 1: gating OFF (without OnClientConnect) ==');
      if DoPost(CallEchoBody, '', st, body, sess) then
      begin
        Check(Pos(ECHO_MARK, body) > 0, 'tools/call without session executes the tool (backward compat)');
        Check(Pos('-32001', body) = 0, 'no authorization error');
      end;
      WriteLn('');

      // ===================== PHASE 2: gating ON =====================
      WriteLn('== PHASE 2: gating ON (OnClientConnect assigned) ==');
      Server.OnClientConnect := H.HandleClientConnect;
      Server.OnUnauthorizedRequest := H.HandleUnauthorized;
      H.AllowUnauth := False;

      // 2a. tools/call sin sesion -> rechazado
      H.UnauthFired := False;
      if DoPost(CallEchoBody, '', st, body, sess) then
      begin
        Check(Pos('-32001', body) > 0, '2a. tools/call without session -> error -32001');
        Check(H.UnauthFired, '2a. OnUnauthorizedRequest was fired');
        Check(Pos(ECHO_MARK, body) = 0, '2a. the tool was NOT executed');
      end;

      // 2b. initialize -> emite Mcp-Session-Id
      H.ConnectFired := False;
      H.LastClientName := '';
      sid := '';
      if DoPost(InitBody('GoodClient'), '', st, body, sess) then
      begin
        Check(st = 200, '2b. initialize responds HTTP 200');
        Check(H.ConnectFired, '2b. OnClientConnect was fired');
        Check(H.LastClientName = 'GoodClient', '2b. received clientInfo.name = GoodClient');
        Check(sess <> '', '2b. response includes Mcp-Session-Id header');
        sid := sess;
      end;

      // 2c. tools/call con la sesion emitida -> permitido
      if DoPost(CallEchoBody, sid, st, body, sess) then
      begin
        Check(Pos(ECHO_MARK, body) > 0, '2c. tools/call with valid Mcp-Session-Id executes the tool');
        Check(Pos('-32001', body) = 0, '2c. no authorization error');
      end;

      // 2d. tools/call con sesion invalida -> rechazado
      H.UnauthFired := False;
      if DoPost(CallEchoBody, 'sesion-invalida-xyz', st, body, sess) then
      begin
        Check(Pos('-32001', body) > 0, '2d. tools/call with invalid session -> -32001');
        Check(H.UnauthFired, '2d. OnUnauthorizedRequest was fired (invalid session)');
      end;
      WriteLn('');

      // ============ PHASE 3: the event grants access ============
      WriteLn('== PHASE 3: OnUnauthorizedRequest grants access (AAllow:=True) ==');
      H.AllowUnauth := True;
      H.UnauthFired := False;
      if DoPost(CallEchoBody, '', st, body, sess) then
      begin
        Check(H.UnauthFired, '3. OnUnauthorizedRequest was fired');
        Check(Pos(ECHO_MARK, body) > 0, '3. the handler allowed the call -> tool executed');
      end;
      H.AllowUnauth := False;
      WriteLn('');

      // ============ PHASE 4: OnClientConnect rejects ============
      WriteLn('== PHASE 4: OnClientConnect rejects the client (AAllow:=False) ==');
      H.RejectClient := 'EvilClient';
      H.ConnectFired := False;
      if DoPost(InitBody('EvilClient'), '', st, body, sess) then
      begin
        Check(H.ConnectFired, '4. OnClientConnect was fired');
        Check((Pos('"error"', body) > 0) and (Pos('"result"', body) = 0),
          '4. initialize rejected -> JSON-RPC error, no result');
        Check(sess = '', '4. no Mcp-Session-Id issued to rejected client');
      end;
      H.RejectClient := '';
      WriteLn('');

      // ===================== Summary =====================
      WriteLn('========================================');
      WriteLn(Format('  PASS: %d    FAIL: %d', [GPass, GFail]));
      if GFail = 0 then
        WriteLn('  RESULT: OK - ISSUE #110 validated')
      else
        WriteLn('  RESULT: FAILURES detected');
      WriteLn('========================================');

      Server.Stop;
    finally
      Server.Free;
      H.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 2;
    end;
  end;

  if GFail > 0 then
    ExitCode := 1;
end.
