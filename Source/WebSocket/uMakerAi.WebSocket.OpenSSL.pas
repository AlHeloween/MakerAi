unit uMakerAi.WebSocket.OpenSSL;

{
  TOpenSSLTransport — ITlsTransport via libssl.so (dlopen) + POSIX sockets
  Platforms: Linux64, macOS
  Android uses TAndroidSSLTransport (uMakerAi.WebSocket.Android.pas)
  Requires: libssl3 or libssl1.1 (Linux) / LibreSSL or Homebrew OpenSSL (macOS)
}

interface

{$IF NOT DEFINED(MSWINDOWS) AND NOT DEFINED(ANDROID)}

uses
  System.SysUtils,
  uMakerAi.WebSocket.Client;

type
  TOpenSSLTransport = class(TInterfacedObject, ITlsTransport)
  private
    FSocket:    Integer;    // POSIX socket fd; -1 = not connected
    FHost:      string;
    FLibSSL:    NativeUInt; // handle de dlopen (0 = no cargada)
    FCtx:       Pointer;   // SSL_CTX*
    FSSL:       Pointer;   // SSL*
    FConnected: Boolean;
    FInsecureSkipVerify: Boolean;

    // Pointers to OpenSSL functions
    FSSL_CTX_new:              function(method: Pointer): Pointer; cdecl;
    FSSL_CTX_free:             procedure(ctx: Pointer); cdecl;
    FSSL_CTX_set_verify:       procedure(ctx: Pointer; mode: Integer; cb: Pointer); cdecl;
    FTLS_client_method:        function: Pointer; cdecl;
    FSSL_new:                  function(ctx: Pointer): Pointer; cdecl;
    FSSL_free:                 procedure(ssl: Pointer); cdecl;
    FSSL_set_fd:               function(ssl: Pointer; fd: Integer): Integer; cdecl;
    // NOTE: SSL_set_tlsext_host_name is NOT a function exported by libssl; it is
    // a MACRO of ssl.h over SSL_ctrl. Looking it up with dlsym always returns
    // nil (verified with nm -D on libssl.so.3), so SNI was silently skipped and
    // the handshake died with "sslv3 alert handshake failure"
    // against any host behind a CDN — which today is almost any.
    // It is sent via SSL_ctrl, which is exported.
    FSSL_ctrl:                 function(ssl: Pointer; cmd: Integer; larg: NativeInt; parg: Pointer): NativeInt; cdecl;
    FSSL_connect:              function(ssl: Pointer): Integer; cdecl;
    FSSL_read:                 function(ssl: Pointer; buf: Pointer; num: Integer): Integer; cdecl;
    FSSL_write:                function(ssl: Pointer; buf: Pointer; num: Integer): Integer; cdecl;
    // Certificate verification. SSL_VERIFY_PEER validates the CHAIN but NOT the
    // hostname: a valid certificate from another domain would pass the filter. To
    // bind the certificate to the host you must also call SSL_set1_host
    // (exported from OpenSSL 1.1.0), which sets the X509_VERIFY_PARAM.
    FSSL_CTX_set_default_verify_paths: function(ctx: Pointer): Integer; cdecl;
    FSSL_set1_host:            function(ssl: Pointer; host: PAnsiChar): Integer; cdecl;
    FSSL_get_verify_result:    function(ssl: Pointer): NativeInt; cdecl;

    procedure LoadLibSSL;
    procedure UnloadLibSSL;
    function  TcpConnect(const AHost: string; APort: Integer): Boolean;
    procedure TcpClose;
    function  RecvRaw(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
  public
    constructor Create;
    destructor  Destroy; override;
    // ITlsTransport
    function  Connect(const AHost: string; APort: Integer): Boolean;
    procedure Disconnect;
    function  SendAll(const AData: TBytes): Boolean;
    function  RecvSome(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
    function  IsConnected: Boolean;

    // Default False: the server certificate IS VALIDATED (chain against the
    // system CA store + hostname). Set it to True only for testing
    // against endpoints with self-signed or expired certificates; leaves the
    // connection exposed to a man-in-the-middle.
    property InsecureSkipVerify: Boolean read FInsecureSkipVerify write FInsecureSkipVerify;
  end;

{$ELSE}
// Empty stub on Windows and Android — TOpenSSLTransport is not used on these platforms
type
  TOpenSSLTransport = class(TInterfacedObject)
  end;
{$ENDIF}

implementation

{$IF NOT DEFINED(MSWINDOWS) AND NOT DEFINED(ANDROID)}

uses
  System.StrUtils,
  Posix.Dlfcn,
  Posix.SysSocket,
  Posix.NetDB,
  Posix.SysSelect,
  Posix.SysTime,
  Posix.Unistd,
  Posix.Errno;

const
  SSL_VERIFY_NONE = 0;
  SSL_VERIFY_PEER = 1;
  X509_V_OK       = 0;

{ TOpenSSLTransport }

constructor TOpenSSLTransport.Create;
begin
  inherited;
  FSocket := -1;
  FLibSSL := 0;
  FCtx    := nil;
  FSSL    := nil;
end;

destructor TOpenSSLTransport.Destroy;
begin
  Disconnect;
  inherited;
end;

// ---------------------------------------------------------------------------
//  LoadLibSSL — dynamic loading of libssl in preference order
// ---------------------------------------------------------------------------
procedure TOpenSSLTransport.LoadLibSSL;

  function TryLoad(const AName: string): NativeUInt;
  begin
    Result := dlopen(PAnsiChar(AnsiString(AName)), RTLD_LAZY);
  end;

  procedure Bind(var APtr; const AName: string);
  begin
    Pointer(APtr) := dlsym(FLibSSL, PAnsiChar(AnsiString(AName)));
  end;

begin
  if FLibSSL <> 0 then Exit;  // already loaded

  FLibSSL := TryLoad('libssl.so.3');
  if FLibSSL = 0 then
    FLibSSL := TryLoad('libssl.so.1.1');
  if FLibSSL = 0 then
    FLibSSL := TryLoad('libssl.dylib');   // macOS (Homebrew / LibreSSL)
  if FLibSSL = 0 then
    raise Exception.Create('OpenSSL not found: install libssl3 or libssl1.1');

  Bind(FTLS_client_method,        'TLS_client_method');
  Bind(FSSL_CTX_new,              'SSL_CTX_new');
  Bind(FSSL_CTX_free,             'SSL_CTX_free');
  Bind(FSSL_CTX_set_verify,       'SSL_CTX_set_verify');
  Bind(FSSL_new,                  'SSL_new');
  Bind(FSSL_free,                 'SSL_free');
  Bind(FSSL_set_fd,               'SSL_set_fd');
  Bind(FSSL_ctrl,                 'SSL_ctrl');
  Bind(FSSL_connect,              'SSL_connect');
  Bind(FSSL_read,                 'SSL_read');
  Bind(FSSL_write,                'SSL_write');
  Bind(FSSL_CTX_set_default_verify_paths, 'SSL_CTX_set_default_verify_paths');
  Bind(FSSL_set1_host,            'SSL_set1_host');
  Bind(FSSL_get_verify_result,    'SSL_get_verify_result');

  if not (Assigned(FSSL_CTX_new) and Assigned(FSSL_connect) and
          Assigned(FSSL_read)    and Assigned(FSSL_write)) then
    raise Exception.Create('OpenSSL: critical symbols not found in the library');
end;

procedure TOpenSSLTransport.UnloadLibSSL;
begin
  if FLibSSL <> 0 then
  begin
    dlclose(FLibSSL);
    FLibSSL := 0;
  end;
end;

// ---------------------------------------------------------------------------
//  TcpConnect — POSIX getaddrinfo + socket + connect
// ---------------------------------------------------------------------------
function TOpenSSLTransport.TcpConnect(const AHost: string; APort: Integer): Boolean;
var
  Hints: addrinfo;
  Res, Cur: Paddrinfo;
  PortStr: AnsiString;
  SockFd: Integer;
begin
  Result := False;
  FillChar(Hints, SizeOf(Hints), 0);
  Hints.ai_family   := AF_UNSPEC;
  Hints.ai_socktype := SOCK_STREAM;

  PortStr := AnsiString(IntToStr(APort));
  if getaddrinfo(PAnsiChar(AnsiString(AHost)), PAnsiChar(PortStr), Hints, Res) <> 0 then
    Exit;

  try
    Cur := Res;
    while Cur <> nil do
    begin
      SockFd := Posix.SysSocket.socket(Cur^.ai_family, Cur^.ai_socktype, Cur^.ai_protocol);
      if SockFd >= 0 then
      begin
        if Posix.SysSocket.connect(SockFd, Cur^.ai_addr^, Cur^.ai_addrlen) = 0 then
        begin
          FSocket := SockFd;
          Exit(True);
        end;
        __close(SockFd);
      end;
      Cur := Cur^.ai_next;
    end;
  finally
    freeaddrinfo(Res^);
  end;
end;

procedure TOpenSSLTransport.TcpClose;
begin
  if FSocket >= 0 then
  begin
    __close(FSocket);
    FSocket := -1;
  end;
end;

// ---------------------------------------------------------------------------
//  ITlsTransport implementation
// ---------------------------------------------------------------------------
function TOpenSSLTransport.Connect(const AHost: string; APort: Integer): Boolean;
var
  LHostAnsi: AnsiString;
  LVerify: NativeInt;
begin
  Result   := False;
  FConnected := False;
  FHost    := AHost;

  LoadLibSSL;

  if not TcpConnect(AHost, APort) then
    raise Exception.CreateFmt('OpenSSL: could not connect via TCP to %s:%d', [AHost, APort]);

  // Create SSL context
  FCtx := FSSL_CTX_new(FTLS_client_method);
  if FCtx = nil then
    raise Exception.Create('OpenSSL: SSL_CTX_new failed');

  // Server certificate verification.
  if FInsecureSkipVerify then
    FSSL_CTX_set_verify(FCtx, SSL_VERIFY_NONE, nil)
  else
  begin
    // Trust chain: system CAs (/etc/ssl/certs on Debian/Ubuntu).
    if not Assigned(FSSL_CTX_set_default_verify_paths) then
      raise Exception.Create('OpenSSL: SSL_CTX_set_default_verify_paths not available; ' +
        'cannot validate the certificate (use InsecureSkipVerify to accept the risk)');
    if FSSL_CTX_set_default_verify_paths(FCtx) <> 1 then
      raise Exception.Create('OpenSSL: could not load system CA store ' +
        '(install ca-certificates)');
    FSSL_CTX_set_verify(FCtx, SSL_VERIFY_PEER, nil);
  end;

  // Create SSL session
  FSSL := FSSL_new(FCtx);
  if FSSL = nil then
    raise Exception.Create('OpenSSL: SSL_new failed');

  // Associate socket
  if FSSL_set_fd(FSSL, FSocket) <> 1 then
    raise Exception.Create('OpenSSL: SSL_set_fd failed');

  // SNI (Server Name Indication) — via SSL_ctrl, because the "nice" version
  // is a macro and does not exist as a symbol. Without SNI, api.openai.com (and everything
  // living behind Cloudflare) aborts the handshake with alert 40.
  // 55 = SSL_CTRL_SET_TLSEXT_HOSTNAME, 0 = TLSEXT_NAMETYPE_host_name.
  LHostAnsi := AnsiString(AHost);
  if Assigned(FSSL_ctrl) and (LHostAnsi <> '') then
    FSSL_ctrl(FSSL, 55, 0, PAnsiChar(LHostAnsi));

  // Binds the certificate to THIS host. Without this, SSL_VERIFY_PEER would accept a
  // valid certificate issued for any other domain: the chain would be
  // fine and the name would not be checked. It is the classic flaw of half‑baked
  // validations. SSL_set1_host exists since OpenSSL 1.1.0.
  if (not FInsecureSkipVerify) and (LHostAnsi <> '') then
  begin
    if not Assigned(FSSL_set1_host) then
      raise Exception.Create('OpenSSL: SSL_set1_host not available (libssl < 1.1.0); ' +
        'without hostname verification it cannot be considered secure');
    if FSSL_set1_host(FSSL, PAnsiChar(LHostAnsi)) <> 1 then
      raise Exception.CreateFmt('OpenSSL: SSL_set1_host failed for "%s"', [AHost]);
  end;

  // TLS handshake
  if FSSL_connect(FSSL) <> 1 then
  begin
    // If the handshake failed due to certificate, SSL_get_verify_result tells
    // why (18 = self signed, 10 = expired, 62 = hostname mismatch...).
    LVerify := X509_V_OK;
    if Assigned(FSSL_get_verify_result) then
      LVerify := FSSL_get_verify_result(FSSL);
    if LVerify <> X509_V_OK then
      raise Exception.CreateFmt(
        'OpenSSL: certificate of %s rejected (X509_V code %d). ' +
        'If the endpoint uses a self‑signed certificate, set InsecureSkipVerify := True.',
        [AHost, LVerify]);
    raise Exception.Create('OpenSSL: SSL_connect failed — TLS handshake rejected' +
      IfThen(Assigned(FSSL_ctrl), '', ' (also SSL_ctrl could not be linked: there will be no SNI)'));
  end;

  FConnected := True;
  Result     := True;
end;

procedure TOpenSSLTransport.Disconnect;
begin
  FConnected := False;

  if FSSL <> nil then
  begin
    FSSL_free(FSSL);
    FSSL := nil;
  end;

  if FCtx <> nil then
  begin
    FSSL_CTX_free(FCtx);
    FCtx := nil;
  end;

  TcpClose;
  // We do not call UnloadLibSSL here — the library remains loaded for reconnections
end;

function TOpenSSLTransport.SendAll(const AData: TBytes): Boolean;
var
  Total, Written: Integer;
  Offset: Integer;
begin
  Result := False;
  if (FSSL = nil) or (Length(AData) = 0) then Exit;

  Total  := Length(AData);
  Offset := 0;
  while Offset < Total do
  begin
    Written := FSSL_write(FSSL, @AData[Offset], Total - Offset);
    if Written <= 0 then Exit;
    Inc(Offset, Written);
  end;
  Result := True;
end;

// ---------------------------------------------------------------------------
//  RecvRaw — waits for TCP data with timeout using select()
//  Returns: >0 = bytes read into ABuf, 0 = timeout, -1 = error/close
// ---------------------------------------------------------------------------
function TOpenSSLTransport.RecvRaw(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
var
  FdSet: fd_set;
  TV: timeval;
  SR: Integer;
begin
  Result := -1;
  if FSocket < 0 then Exit;

  __FD_ZERO(FdSet);
  __FD_SET(FSocket, FdSet);
  TV.tv_sec  := ATimeoutMs div 1000;
  TV.tv_usec := (ATimeoutMs mod 1000) * 1000;

  SR := select(FSocket + 1, @FdSet, nil, nil, @TV);
  if SR = 0 then
    Exit(0)   // timeout
  else if SR < 0 then
    Exit(-1); // error

  SetLength(ABuf, 32768);
  Result := FSSL_read(FSSL, @ABuf[0], Length(ABuf));
  if Result > 0 then
    SetLength(ABuf, Result)
  else
  begin
    SetLength(ABuf, 0);
    Result := -1;  // SSL_read returned 0 (close) or <0 (error)
  end;
end;

function TOpenSSLTransport.RecvSome(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
begin
  Result := RecvRaw(ABuf, ATimeoutMs);
end;

function TOpenSSLTransport.IsConnected: Boolean;
begin
  Result := FConnected and (FSocket >= 0) and (FSSL <> nil);
end;

{$IFEND} // NOT MSWINDOWS AND NOT ANDROID

end.
