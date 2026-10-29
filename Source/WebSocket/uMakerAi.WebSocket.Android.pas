// MakerAI Suite — TLS Transport Android via javax.net.ssl.SSLSocketFactory (JNI)
//
// TAndroidSSLTransport implements ITlsTransport using Android's native TLS stack
// (BoringSSL — no external DLLs or extra network permission beyond INTERNET).
//
// JNI memory management:
//   - jobjects returned by JNI are local; they are converted to global refs with
//     NewGlobalRef to survive across calls.
//   - ReleaseRefs() deletes all global refs in Disconnect/Destroy.
//   - TThread threads in Delphi/Android are auto-attached to the JVM; GetCurrentEnv
//     calls AttachCurrentThread as an additional safety measure for pure native threads.
//
// Prerequisite in AndroidManifest.xml:
//   <uses-permission android:name="android.permission.INTERNET"/>
//
// Author: Gustavo Enriquez
// Email: gustavoeenriquez@gmail.com

unit uMakerAi.WebSocket.Android;

interface

{$IFDEF ANDROID}

uses
  System.SysUtils,
  uMakerAi.WebSocket.Client;

type
  TAndroidSSLTransport = class(TInterfacedObject, ITlsTransport)
  private
    FConnected:    Boolean;
    // Global JNI references (valid across native method calls)
    FSocket:       jobject;     // javax.net.ssl.SSLSocket
    FInputStream:  jobject;     // java.io.InputStream
    FOutputStream: jobject;     // java.io.OutputStream
    FReadBuf:      jbyteArray;  // byte[READ_BUF_SIZE] reusable for reads
    // Cached method IDs after Connect (valid for the process lifetime)
    FMidISRead:     jmethodID;  // InputStream.read([BII)I
    FMidOSWrite:    jmethodID;  // OutputStream.write([BII)V
    FMidSetTimeout: jmethodID;  // Socket.setSoTimeout(I)V
    FMidClose:      jmethodID;  // Socket.close()V
    procedure ReleaseRefs;
    function  GetCurrentEnv: PJNIEnv;
    // True if there was a pending exception (always clears it)
    function  CheckAndClearException(const E: PJNIEnv): Boolean;
  public
    constructor Create;
    destructor  Destroy; override;
    // ITlsTransport
    function  Connect(const AHost: string; APort: Integer): Boolean;
    procedure Disconnect;
    function  SendAll(const AData: TBytes): Boolean;
    function  RecvSome(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
    function  IsConnected: Boolean;
  end;

{$ELSE}
// Empty stub on non-Android platforms
type
  TAndroidSSLTransport = class(TInterfacedObject)
  end;
{$ENDIF}

implementation

{$IFDEF ANDROID}

uses
  Androidapi.Jni,       // jboolean, jbyte, jint, jobject, jclass, jmethodID, jvalue, PJNIEnv …
  Androidapi.JNIBridge; // TJNIResolver

const
  READ_BUF_SIZE   = 32768;
  JNI_VERSION_1_6 = $00010006;
  JNI_OK          = 0;
  JNI_EDETACHED   = -2;
  JNI_ABORT       = 2; // ReleaseByteArrayElements: do not copy back to Java heap

// ---------------------------------------------------------------------------
//  GetCurrentEnv — PJNIEnv for the current thread
//  Attaches the thread to the JVM if not yet attached (e.g., pure native threads).
// ---------------------------------------------------------------------------
function TAndroidSSLTransport.GetCurrentEnv: PJNIEnv;
var
  VM:     PJavaVM;
  EnvPtr: Pointer;
  Res:    jint;
begin
  Result := nil;
  VM     := TJNIResolver.GetJavaVM;
  if VM = nil then Exit;
  // GetEnv returns the env of the current thread if attached
  Res := VM^.GetEnv(VM, @EnvPtr, JNI_VERSION_1_6);
  if Res = JNI_EDETACHED then
    VM^.AttachCurrentThread(VM, @EnvPtr, nil);
  Result := PJNIEnv(EnvPtr);
end;

// ---------------------------------------------------------------------------
//  CheckAndClearException — True if there was an exception; always clears it.
// ---------------------------------------------------------------------------
function TAndroidSSLTransport.CheckAndClearException(const E: PJNIEnv): Boolean;
begin
  Result := E^.ExceptionCheck(E) <> 0;
  if Result then
    E^.ExceptionClear(E);
end;

// ---------------------------------------------------------------------------
//  ReleaseRefs — releases all global JNI references
// ---------------------------------------------------------------------------
procedure TAndroidSSLTransport.ReleaseRefs;
var
  E: PJNIEnv;
begin
  E := GetCurrentEnv;
  if E = nil then Exit;
  if FSocket       <> nil then begin E^.DeleteGlobalRef(E, FSocket);       FSocket       := nil; end;
  if FInputStream  <> nil then begin E^.DeleteGlobalRef(E, FInputStream);  FInputStream  := nil; end;
  if FOutputStream <> nil then begin E^.DeleteGlobalRef(E, FOutputStream); FOutputStream := nil; end;
  if FReadBuf      <> nil then begin E^.DeleteGlobalRef(E, FReadBuf);      FReadBuf      := nil; end;
end;

constructor TAndroidSSLTransport.Create;
begin
  inherited;
  FConnected     := False;
  FSocket        := nil;
  FInputStream   := nil;
  FOutputStream  := nil;
  FReadBuf       := nil;
  FMidISRead     := nil;
  FMidOSWrite    := nil;
  FMidSetTimeout := nil;
  FMidClose      := nil;
end;

destructor TAndroidSSLTransport.Destroy;
begin
  Disconnect;
  inherited;
end;

// ---------------------------------------------------------------------------
//  Connect — establishes TCP + TLS connection using javax.net.ssl.SSLSocketFactory
//
//  JNI flow:
//   1. SSLSocketFactory.getDefault()  → factory
//   2. factory.createSocket(host, port) → SSLSocket (connects TCP + starts TLS)
//   3. sslSocket.startHandshake()       → completes TLS handshake
//   4. Cache getInputStream/getOutputStream and their method IDs
//   5. Create reusable byte[] for reads
// ---------------------------------------------------------------------------
function TAndroidSSLTransport.Connect(const AHost: string; APort: Integer): Boolean;
var
  E: PJNIEnv;
  // Local JNI classes
  CSSLFactory, CActualFactory, CSocket, CIS, COS: jclass;
  // Local method IDs
  MGetDefault, MCreateSocket, MStartHandshake, MGetIS, MGetOS: jmethodID;
  // Local JNI objects (local refs — either deleted or made global)
  LFactory, LSocket, LIS, LOS: jobject;
  LReadBuf: jbyteArray;
  JHost: jstring;
  Args: array[0..1] of jvalue;
begin
  Result     := False;
  FConnected := False;

  E := GetCurrentEnv;
  if E = nil then Exit;

  // 1. javax.net.ssl.SSLSocketFactory.getDefault()
  CSSLFactory := E^.FindClass(E, 'javax/net/ssl/SSLSocketFactory');
  if CheckAndClearException(E) or (CSSLFactory = nil) then Exit;

  MGetDefault := E^.GetStaticMethodID(E, CSSLFactory,
    'getDefault', '()Ljavax/net/ssl/SocketFactory;');
  if CheckAndClearException(E) or (MGetDefault = nil) then
  begin
    E^.DeleteLocalRef(E, CSSLFactory);
    Exit;
  end;

  LFactory := E^.CallStaticObjectMethod(E, CSSLFactory, MGetDefault);
  E^.DeleteLocalRef(E, CSSLFactory);
  if CheckAndClearException(E) or (LFactory = nil) then Exit;

  // 2. factory.createSocket(host, port)
  //    Use the actual class of the factory to look up the method (may be a subclass)
  CActualFactory := E^.GetObjectClass(E, LFactory);
  MCreateSocket  := E^.GetMethodID(E, CActualFactory,
    'createSocket', '(Ljava/lang/String;I)Ljava/net/Socket;');
  E^.DeleteLocalRef(E, CActualFactory);
  if CheckAndClearException(E) or (MCreateSocket = nil) then
  begin
    E^.DeleteLocalRef(E, LFactory);
    Exit;
  end;

  JHost    := E^.NewStringUTF(E, MarshaledAString(UTF8Encode(AHost)));
  Args[0].l := JHost;
  Args[1].i := APort;
  LSocket  := E^.CallObjectMethodA(E, LFactory, MCreateSocket, @Args[0]);
  E^.DeleteLocalRef(E, JHost);
  E^.DeleteLocalRef(E, LFactory);
  if CheckAndClearException(E) or (LSocket = nil) then Exit;

  // Convert socket to global ref
  FSocket := E^.NewGlobalRef(E, LSocket);
  E^.DeleteLocalRef(E, LSocket);

  // 3. sslSocket.startHandshake() — forces TLS handshake now (fail fast)
  CSocket         := E^.GetObjectClass(E, FSocket);
  MStartHandshake := E^.GetMethodID(E, CSocket, 'startHandshake', '()V');
  if (not CheckAndClearException(E)) and (MStartHandshake <> nil) then
  begin
    E^.CallVoidMethod(E, FSocket, MStartHandshake);
    if CheckAndClearException(E) then
    begin
      // TLS handshake failed
      E^.DeleteLocalRef(E, CSocket);
      ReleaseRefs;
      Exit;
    end;
  end;

  // 4a. Cache method IDs of Socket (inherited by SSLSocket)
  FMidSetTimeout := E^.GetMethodID(E, CSocket, 'setSoTimeout', '(I)V');
  FMidClose      := E^.GetMethodID(E, CSocket, 'close', '()V');
  CheckAndClearException(E); // ignore if any missing (very unlikely)

  // 4b. getInputStream / getOutputStream
  MGetIS := E^.GetMethodID(E, CSocket, 'getInputStream',  '()Ljava/io/InputStream;');
  MGetOS := E^.GetMethodID(E, CSocket, 'getOutputStream', '()Ljava/io/OutputStream;');
  E^.DeleteLocalRef(E, CSocket);
  if CheckAndClearException(E) then begin ReleaseRefs; Exit; end;

  LIS := E^.CallObjectMethod(E, FSocket, MGetIS);
  if CheckAndClearException(E) or (LIS = nil) then begin ReleaseRefs; Exit; end;
  FInputStream := E^.NewGlobalRef(E, LIS);
  E^.DeleteLocalRef(E, LIS);

  LOS := E^.CallObjectMethod(E, FSocket, MGetOS);
  if CheckAndClearException(E) or (LOS = nil) then begin ReleaseRefs; Exit; end;
  FOutputStream := E^.NewGlobalRef(E, LOS);
  E^.DeleteLocalRef(E, LOS);

  // 4c. Cache InputStream.read and OutputStream.write
  CIS        := E^.FindClass(E, 'java/io/InputStream');
  FMidISRead := E^.GetMethodID(E, CIS, 'read', '([BII)I');
  E^.DeleteLocalRef(E, CIS);
  COS         := E^.FindClass(E, 'java/io/OutputStream');
  FMidOSWrite := E^.GetMethodID(E, COS, 'write', '([BII)V');
  E^.DeleteLocalRef(E, COS);
  if CheckAndClearException(E) or (FMidISRead = nil) or (FMidOSWrite = nil) then
  begin
    ReleaseRefs;
    Exit;
  end;

  // 5. Reusable Java byte[] read buffer
  LReadBuf := E^.NewByteArray(E, READ_BUF_SIZE);
  if CheckAndClearException(E) or (LReadBuf = nil) then begin ReleaseRefs; Exit; end;
  FReadBuf := jbyteArray(E^.NewGlobalRef(E, LReadBuf));
  E^.DeleteLocalRef(E, LReadBuf);

  FConnected := True;
  Result     := True;
end;

// ---------------------------------------------------------------------------
//  Disconnect — closes the socket and releases all JNI references
// ---------------------------------------------------------------------------
procedure TAndroidSSLTransport.Disconnect;
var
  E: PJNIEnv;
begin
  FConnected := False;
  if (FSocket <> nil) and (FMidClose <> nil) then
  begin
    E := GetCurrentEnv;
    if E <> nil then
    begin
      E^.CallVoidMethod(E, FSocket, FMidClose);
      E^.ExceptionClear(E); // ignore errors on close
    end;
  end;
  ReleaseRefs;
end;

// ---------------------------------------------------------------------------
//  SendAll — sends complete AData via OutputStream.write(byte[],0,len)
// ---------------------------------------------------------------------------
function TAndroidSSLTransport.SendAll(const AData: TBytes): Boolean;
var
  E:    PJNIEnv;
  JBuf: jbyteArray;
  Total: Integer;
  Args: array[0..2] of jvalue;
begin
  Result := False;
  if not FConnected or (FOutputStream = nil) or (Length(AData) = 0) then Exit;

  Total := Length(AData);
  E     := GetCurrentEnv;
  if E = nil then Exit;

  // Create temporary Java byte[] with the data to send
  JBuf := E^.NewByteArray(E, Total);
  if JBuf = nil then Exit;
  E^.SetByteArrayRegion(E, JBuf, 0, Total, pjbyte(@AData[0]));

  Args[0].l := JBuf;
  Args[1].i := 0;
  Args[2].i := Total;
  E^.CallVoidMethodA(E, FOutputStream, FMidOSWrite, @Args[0]);
  E^.DeleteLocalRef(E, JBuf);

  Result := not CheckAndClearException(E);
  if not Result then
    FConnected := False;
end;

// ---------------------------------------------------------------------------
//  RecvSome — reads up to READ_BUF_SIZE bytes with timeout ATimeoutMs (ms)
//  Returns: >0 = bytes in ABuf, 0 = timeout, -1 = error / connection closed
//
//  Distinguishes SocketTimeoutException (normal timeout) from IOException (error).
// ---------------------------------------------------------------------------
function TAndroidSSLTransport.RecvSome(var ABuf: TBytes; ATimeoutMs: Integer): Integer;
var
  E:         PJNIEnv;
  Args:      array[0..2] of jvalue;
  N:         jint;
  BufPtr:    pjbyte;
  ExObj:     jobject;
  TCls:      jclass;
  IsTimeout: Boolean;
begin
  Result := -1;
  if not FConnected or (FInputStream = nil) then Exit;

  E := GetCurrentEnv;
  if E = nil then Exit;

  // Set read timeout on the socket before each recv
  if FMidSetTimeout <> nil then
  begin
    Args[0].i := ATimeoutMs;
    E^.CallVoidMethodA(E, FSocket, FMidSetTimeout, @Args[0]);
    CheckAndClearException(E); // non-critical if it fails
  end;

  // InputStream.read(readBuf, 0, READ_BUF_SIZE) — blocks until ATimeoutMs
  Args[0].l := FReadBuf;
  Args[1].i := 0;
  Args[2].i := READ_BUF_SIZE;
  N := E^.CallIntMethodA(E, FInputStream, FMidISRead, @Args[0]);

  if E^.ExceptionCheck(E) <> 0 then
  begin
    // Determine if it's a timeout (recoverable) or real error (fatal)
    ExObj     := E^.ExceptionOccurred(E);  // OK to call with pending exception
    E^.ExceptionClear(E);                   // clear before calling FindClass

    TCls      := E^.FindClass(E, 'java/net/SocketTimeoutException');
    IsTimeout := (TCls <> nil) and (ExObj <> nil) and
                 (E^.IsInstanceOf(E, ExObj, TCls) <> 0);

    if TCls  <> nil then E^.DeleteLocalRef(E, TCls);
    if ExObj <> nil then E^.DeleteLocalRef(E, ExObj);
    CheckAndClearException(E); // clear possible exception from FindClass

    if IsTimeout then
      Result := 0   // timeout — the reader thread will retry
    else
    begin
      FConnected := False;
      Result     := -1;
    end;
    Exit;
  end;

  if N <= 0 then
  begin
    // read() returned -1: end of stream (socket cleanly closed)
    FConnected := False;
    Exit;
  end;

  // Copy N bytes from FReadBuf (Java heap) to ABuf (Delphi heap)
  SetLength(ABuf, N);
  BufPtr := E^.GetByteArrayElements(E, FReadBuf, nil);
  if BufPtr <> nil then
  begin
    Move(BufPtr^, ABuf[0], N);
    E^.ReleaseByteArrayElements(E, FReadBuf, BufPtr, JNI_ABORT);
  end;

  Result := N;
end;

function TAndroidSSLTransport.IsConnected: Boolean;
begin
  Result := FConnected and (FSocket <> nil);
end;

{$ENDIF} // ANDROID

end.
