// Name: Gustavo Enríquez
// Social Media:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - YouTube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit UMakerAi.MCPServer.SSE;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.SyncObjs,
  System.Threading,
  IdContext, IdCustomHTTPServer, IdHTTPServer, IdGlobal, IdSocketHandle,
  UMakerAi.MCPServer.Core;

type
  // Event to handle HTTP routes that are not /sse or /messages (e.g., serving
  // static files like generated images). AHandled=True avoids the 404.
  TAiMCPUnhandledRequestEvent = procedure(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
    AResponseInfo: TIdHTTPResponseInfo; var AHandled: Boolean) of object;
  // Represents an active SSE session
  TMCPSSESession = class
  public
    SessionID: string;
    // Message queue. We use String because JSON is already text.
    Outbox: TThreadedQueue<string>;
    LastActivity: TDateTime;
    constructor Create(const AID: string);
    destructor Destroy; override;
  end;

  TAiMCPSSEHttpServer = class(TAiMCPServer)
  private
    FHttpServer: TIdHTTPServer;
    FSessions: TObjectDictionary<string, TMCPSSESession>;
    FSessionsLock: TCriticalSection;

    // Endpoint configuration
    FSseEndpoint: string; // default '/sse'
    FMessagesEndpoint: string; // default '/messages'
    FOnUnhandledRequest: TAiMCPUnhandledRequestEvent;

    // Indy events
    procedure OnCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure OnCommandOther(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure OnParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String; var VUsername, VPassword: String; var VHandled: Boolean);

    // Specific handlers
    procedure HandleSSEConnection(AContext: TIdContext; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandlePostMessage(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo; const AAuthContext: TAiAuthContext);

    // Helpers
    function GetOrCreateSession(const AID: string): TMCPSSESession;
    function GenerateSessionID: string;
    procedure VerifyAndSetCORSHeaders(AResponseInfo: TIdHTTPResponseInfo);

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start; override;
    procedure Stop; override;

    // Sends an arbitrary JSON-RPC notification through the SSE channel of a session.
    // Best-effort: if the session does not exist or its queue is full, it is discarded.
    procedure PushNotification(const ASessionID, ANotificationJson: string);

    // Configuration properties
  published
    property SseEndpoint: string read FSseEndpoint write FSseEndpoint;
    property MessagesEndpoint: string read FMessagesEndpoint write FMessagesEndpoint;
    property ApiKey;
    property OnValidateRequest;
    // HTTP routes outside /sse and /messages (static files, health checks...).
    // It is invoked BEFORE MCP authentication — the handler decides its own auth.
    property OnUnhandledRequest: TAiMCPUnhandledRequestEvent read FOnUnhandledRequest write FOnUnhandledRequest;
  end;

procedure Register;

implementation

uses
  System.DateUtils;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMCPSSEHttpServer]);
end;

{ TMCPSSESession }

constructor TMCPSSESession.Create(const AID: string);
begin
  inherited Create;
  SessionID := AID;
  // Capacity: 1000 messages.
  // PushTimeout: INFINITE (Producer waits if full)
  // PopTimeout: 1000ms (IMPORTANT: Do not use INFINITE here to allow heartbeat)
  Outbox := TThreadedQueue<string>.Create(1000, INFINITE, 1000);
  LastActivity := Now;
end;

destructor TMCPSSESession.Destroy;
begin
  Outbox.DoShutDown; // Unblock any thread waiting
  Outbox.Free;
  inherited;
end;

{ TAiMCPSSEHttpServer }

constructor TAiMCPSSEHttpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FSessions := TObjectDictionary<string, TMCPSSESession>.Create([doOwnsValues]);
  FSessionsLock := TCriticalSection.Create;

  FHttpServer := TIdHTTPServer.Create(Self);
  // Assign handlers
  FHttpServer.OnCommandGet := OnCommandGet;
  FHttpServer.OnCommandOther := OnCommandOther;
  FHttpServer.OnParseAuthentication := OnParseAuthentication;

  // Vital configuration for SSE
  FHttpServer.KeepAlive := True;
  FHttpServer.AutoStartSession := False;
  FHttpServer.ReuseSocket := rsTrue;  // Allows re-bind while CLOSE_WAIT is still active

  // Default endpoints
  FSseEndpoint := '/sse';
  FMessagesEndpoint := '/messages';
end;

destructor TAiMCPSSEHttpServer.Destroy;
begin
  Stop;
  FHttpServer.Free; // The server must die before the sessions
  FSessions.Free;
  FSessionsLock.Free;
  inherited;
end;

procedure TAiMCPSSEHttpServer.Start;
begin
  inherited Start;

  // Enables notifications/progress: the core delegates delivery by session here.
  FLogicServer.OnSendNotification :=
    procedure(const ASessionID, ANotificationJson: string)
    begin
      PushNotification(ASessionID, ANotificationJson);
    end;

  if not FHttpServer.Active then
  begin
    FHttpServer.DefaultPort := FLogicServer.Port;
    // Without BindAddress Indy listens on all interfaces (0.0.0.0)
    FHttpServer.Bindings.Clear;
    if EffectiveBindAddress <> '' then
      FHttpServer.Bindings.Add.SetBinding(EffectiveBindAddress, FLogicServer.Port);
    FHttpServer.Active := True;
  end;
end;

procedure TAiMCPSSEHttpServer.PushNotification(const ASessionID, ANotificationJson: string);
var
  Session: TMCPSSESession;
begin
  // Push INSIDE the lock: the session is destroyed under this same lock upon
  // disconnect, so it is still alive here. The QueueSize check guarantees that
  // we never block while holding the lock (PushTimeout of the queue is INFINITE).
  FSessionsLock.Enter;
  try
    if FSessions.TryGetValue(ASessionID, Session) then
      if Session.Outbox.QueueSize < 900 then
        Session.Outbox.PushItem(ANotificationJson);
  finally
    FSessionsLock.Leave;
  end;
end;

procedure TAiMCPSSEHttpServer.Stop;
begin
  if FHttpServer.Active then
    FHttpServer.Active := False;

  // Clear all active sessions
  FSessionsLock.Enter;
  try
    FSessions.Clear;
  finally
    FSessionsLock.Leave;
  end;

  inherited Stop;
end;

function TAiMCPSSEHttpServer.GenerateSessionID: string;
begin
  Result := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').ToLower;
end;

function TAiMCPSSEHttpServer.GetOrCreateSession(const AID: string): TMCPSSESession;
begin
  FSessionsLock.Enter;
  try
    if not FSessions.TryGetValue(AID, Result) then
    begin
      Result := TMCPSSESession.Create(AID);
      FSessions.Add(AID, Result);
    end;
    Result.LastActivity := Now;
  finally
    FSessionsLock.Leave;
  end;
end;

procedure TAiMCPSSEHttpServer.VerifyAndSetCORSHeaders(AResponseInfo: TIdHTTPResponseInfo);
begin
  if not FLogicServer.CorsEnabled then
    Exit;

  // For development and Claude Desktop, '*' usually works,
  // but some strict tools require the exact origin.
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Origin'] := '*';
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'GET, POST, OPTIONS';
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Headers'] := 'Content-Type, Cache-Control, X-Session-ID';
  AResponseInfo.CustomHeaders.Values['Access-Control-Expose-Headers'] := 'Content-Type';
end;

// Main handler for GET
procedure TAiMCPSSEHttpServer.OnCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  AuthContext: TAiAuthContext;
  AuthHeader: string;
var
  Handled: Boolean;
begin
  VerifyAndSetCORSHeaders(AResponseInfo);

  // Routes outside the MCP protocol (static files, health...) — before MCP auth.
  if (ARequestInfo.URI <> FSseEndpoint) and (ARequestInfo.Document <> FMessagesEndpoint) and
     (ARequestInfo.URI <> FMessagesEndpoint) and Assigned(FOnUnhandledRequest) then
  begin
    Handled := False;
    FOnUnhandledRequest(AContext, ARequestInfo, AResponseInfo, Handled);
    if Handled then
      Exit;
  end;

  // Authentication on SSE connection
  AuthHeader := ARequestInfo.RawHeaders.Values['Authorization'];
  if AuthHeader = '' then
    AuthHeader := ARequestInfo.RawHeaders.Values['X-API-Key'];

  if not ValidateRequest(AuthHeader, AContext.Binding.PeerIP, AuthContext) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.ContentText := '{"error": "Authentication failed"}';
    AResponseInfo.ContentType := 'application/json';
    Exit;
  end;

  if ARequestInfo.Command = 'OPTIONS' then
  begin
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.ContentLength := 0;
  end
  else if (ARequestInfo.Command = 'POST') and
          ((ARequestInfo.URI = FMessagesEndpoint) or (ARequestInfo.Document = FMessagesEndpoint)) then
  begin
    HandlePostMessage(AContext, ARequestInfo, AResponseInfo, AuthContext);
  end
  else if ARequestInfo.URI = FSseEndpoint then
  begin
    HandleSSEConnection(AContext, AResponseInfo);
  end
  else
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := 'Not Found. Use ' + FSseEndpoint + ' for SSE.';
  end;
end;

// Handler for POST and OPTIONS
procedure TAiMCPSSEHttpServer.OnParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String;
  var VUsername, VPassword: String; var VHandled: Boolean);
begin
  // Without this handler, Indy responds 401 to any Authorization scheme
  // other than Basic (e.g. "Bearer <token>") before reaching the handlers.
  // Actual validation happens in ValidateRequest on the raw header
  // (ApiKey / OnValidateRequest); here we only avoid premature rejection.
  VHandled := True;
end;

procedure TAiMCPSSEHttpServer.OnCommandOther(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  AuthContext: TAiAuthContext;
  AuthHeader: string;
begin
  VerifyAndSetCORSHeaders(AResponseInfo);

  if ARequestInfo.Command = 'OPTIONS' then
  begin
    AResponseInfo.ResponseNo := 204;
    AResponseInfo.ContentLength := 0;
    Exit;
  end;

  // Authentication on each POST
  AuthHeader := ARequestInfo.RawHeaders.Values['Authorization'];
  if AuthHeader = '' then
    AuthHeader := ARequestInfo.RawHeaders.Values['X-API-Key'];

  if not ValidateRequest(AuthHeader, AContext.Binding.PeerIP, AuthContext) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.ContentText := '{"error": "Authentication failed"}';
    AResponseInfo.ContentType := 'application/json';
    Exit;
  end;

  if (ARequestInfo.Command = 'POST') and ((ARequestInfo.URI = FMessagesEndpoint) or (ARequestInfo.Document = FMessagesEndpoint)) then
  begin
    HandlePostMessage(AContext, ARequestInfo, AResponseInfo, AuthContext);
  end
  else
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := 'Endpoint not found or method not allowed.';
  end;
end;

// =============================================================================
// CRITICAL SSE LOGIC
// =============================================================================

procedure TAiMCPSSEHttpServer.HandleSSEConnection(AContext: TIdContext; AResponseInfo: TIdHTTPResponseInfo);
var
  SessionID: string;
  Session: TMCPSSESession;
  Msg: string;
  PopResult: TWaitResult;
  HandshakeStr: string;
  BytesToSend: TIdBytes;
begin
  // 1. Configure Session
  SessionID := GenerateSessionID;
  Session := GetOrCreateSession(SessionID);

  WriteLn(Format('SSE: Client Connected (Session: %s)', [SessionID]));

  try
    // 2. HTTP Headers for Streaming — written MANUALLY.
    // Do not use AResponseInfo.WriteHeader: in Indy from Delphi 13, with
    // ContentLength=-1 and without ContentText/Stream, WriteHeader auto‑generates a
    // body "<HTML><BODY><B>200 OK</B></BODY></HTML>" and sends Content-Length:39,
    // causing correct HTTP clients (curl, python, Claude Desktop) to cut the
    // SSE stream after 39 bytes. SSE requires total absence of Content-Length
    // (read until connection close).
    var Hdr :=
      'HTTP/1.1 200 OK' + #13#10 +
      'Content-Type: text/event-stream; charset=utf-8' + #13#10 +
      'Cache-Control: no-cache' + #13#10 +
      'Connection: keep-alive' + #13#10 +
      'X-Accel-Buffering: no' + #13#10;
    if FLogicServer.CorsEnabled then
      Hdr := Hdr + 'Access-Control-Allow-Origin: *' + #13#10;
    Hdr := Hdr + #13#10;
    AContext.Connection.IOHandler.Write(ToBytes(Hdr, IndyTextEncoding_UTF8));

    // Mark as written so Indy does NOT generate its own headers
    // when this handler returns.
    AResponseInfo.HeaderHasBeenWritten := True;

    // 3. Send MCP Handshake (Protocol)
    // Tells the client where to send POST commands
    var
    FullMsgUrl := Format('%s?session_id=%s', [FMessagesEndpoint, SessionID]);

    HandshakeStr := 'event: endpoint' + #10 + 'data: ' + FullMsgUrl + #10#10;

    AContext.Connection.IOHandler.Write(ToBytes(HandshakeStr, IndyTextEncoding_UTF8));

    // 4. Main Streaming Loop (Keep-Alive Loop)
    while AContext.Connection.Connected do
    begin
      // Try to pop a message from the queue.
      // Timeout of 1000ms (1 second) defined in TMCPSSESession constructor.
      PopResult := Session.Outbox.PopItem(Msg);

      if PopResult = wrSignaled then
      begin
        // --- CASE A: There is a message to send ---
        // SSE format: "data: <content>\n\n"
        var
        Payload := 'data: ' + Msg + #10#10;

        // Write Bytes directly to avoid character corruption
        BytesToSend := ToBytes(Payload, IndyTextEncoding_UTF8);
        AContext.Connection.IOHandler.Write(BytesToSend);

        Session.LastActivity := Now;
      end
      else if PopResult = wrTimeout then
      begin
        // --- CASE B: No messages (Idle) ---
        // Send a comment "ping" to keep the connection alive
        // and avoid antivirus/proxy timeouts.
        var
        Ping := ': keep-alive' + #10#10;
        AContext.Connection.IOHandler.Write(ToBytes(Ping, IndyTextEncoding_ASCII));
      end
      else if PopResult = wrAbandoned then
      begin
        // The queue was destroyed (Server shutting down)
        Break;
      end;

      // Proactive disconnection check
      // If the client closed the socket, this will throw a safe exception.
      // AContext.Connection.CheckForDisconnect(True, True);

      if AContext.Connection.IOHandler <> nil then
        AContext.Connection.IOHandler.CheckForDisconnect(True, True);

    end;

  except
    on E: Exception do
    begin
      // It is normal to see "Connection Closed Gracefully" or "Socket Error" when the client disconnects.
      // We do not treat it as a critical error.
    end;
  end;

  // 5. Cleanup after exiting the loop
  FSessionsLock.Enter;
  try
    if FSessions.ContainsKey(SessionID) then
      FSessions.Remove(SessionID);
  finally
    FSessionsLock.Leave;
  end;

  WriteLn(Format('SSE: Client Disconnected (Session: %s)', [SessionID]));
end;

// =============================================================================
// POST LOGIC (MESSAGES)
// =============================================================================

procedure TAiMCPSSEHttpServer.HandlePostMessage(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo; const AAuthContext: TAiAuthContext);
var
  SessionID: string;
  Session: TMCPSSESession;
  JsonBody: string;
  ResponseJson: string;
  Stream: TStringStream;
begin
  // 1. Validate Session ID
  SessionID := ARequestInfo.Params.Values['session_id'];
  if SessionID = '' then
  begin
    AResponseInfo.ResponseNo := 400;
    AResponseInfo.ContentText := 'Missing session_id parameter';
    Exit;
  end;

  // 2. Look for Active Session
  FSessionsLock.Enter;
  try
    if not FSessions.TryGetValue(SessionID, Session) then
      Session := nil;
  finally
    FSessionsLock.Leave;
  end;

  if Session = nil then
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := 'Session not found or expired';
    Exit;
  end;

  // 3. Read Body
  if ARequestInfo.PostStream = nil then
  begin
    AResponseInfo.ResponseNo := 400;
    Exit;
  end;

  // Read UTF8 string safely
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    Stream.CopyFrom(ARequestInfo.PostStream, 0);
    JsonBody := Stream.DataString;
  finally
    Stream.Free;
  end;

  // 4. Execute Logic (Core)
  try
    // tools/call may take minutes (image generation, external processes).
    // It runs async: the POST replies 202 immediately and both
    // notifications/progress and the result travel via the SSE channel.
    // The remaining methods (initialize, tools/list...) are fast and run inline.
    var LMethod := '';
    var LParsed := TJSONObject.ParseJSONValue(JsonBody);
    try
      if LParsed is TJSONObject then
        LMethod := TJSONObject(LParsed).GetValue<string>('method', '');
    finally
      LParsed.Free;
    end;

    if SameText(LMethod, 'tools/call') then
    begin
      // Capture SessionID (string) and NOT the Session object: if the client
      // disconnects during execution, PushNotification simply discards.
      var LBody := JsonBody;
      var LSessionID := SessionID;
      var LAuth := AAuthContext;
      TTask.Run(
        procedure
        var
          Resp: string;
        begin
          try
            Resp := FLogicServer.ExecuteRequest(LBody, LSessionID, LAuth);
          except
            on E: Exception do
              Resp := '';
          end;
          if Resp <> '' then
            PushNotification(LSessionID, Resp);
        end);
    end
    else
    begin
      // ExecuteRequest returns the JSON response (with authentication context)
      ResponseJson := FLogicServer.ExecuteRequest(JsonBody, SessionID, AAuthContext);

      // 5. Send Response via SSE CHANNEL (Not via HTTP response)
      if ResponseJson <> '' then
        Session.Outbox.PushItem(ResponseJson);
    end;

    // 6. Respond to POST with "202 Accepted"
    // This tells the client: "I received your order, wait for the response on the stream".
    AResponseInfo.ResponseNo := 202;
    AResponseInfo.ContentText := 'Accepted';
    AResponseInfo.ContentType := 'text/plain';

  except
    on E: Exception do
    begin
      AResponseInfo.ResponseNo := 500;
      AResponseInfo.ContentText := 'Internal Error: ' + E.Message;
    end;
  end;
end;

end.
