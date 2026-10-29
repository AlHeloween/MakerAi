unit UMakerAi.MCPServer.Stdio;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Threading, System.AnsiStrings, System.IOUtils,
  UMakerAi.MCPServer.Core;

type
  // forward declaration for the thread
  TAiMCPStdioServer = class;

  { TStdioWorkerThread
    This thread handles the blocking task of reading from Standard Input }
  TStdioWorkerThread = class(TThread)
  private
    FServer: TAiMCPStdioServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AServer: TAiMCPStdioServer);
  end;

  { TAiMCPStdioServer
    The main component that manages Stdio communication }
  TAiMCPStdioServer = class(TAiMCPServer)
  private
    FWorkerThread: TStdioWorkerThread;
    FOutputLock: TCriticalSection; // For safe writes to Stdout from multiple threads

    procedure ProcessRequest(const ARequestJson: string);
    procedure SendResponse(const AResponseJson: string);
    procedure SetConsoleIOToUTF8;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start; Override;
    procedure Stop; Override;
  end;

procedure Register;

implementation

uses System.Character {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMCPStdioServer]);
end;

{ TStdioWorkerThread }

constructor TStdioWorkerThread.Create(AServer: TAiMCPStdioServer);
begin
  inherited Create(True); // The thread is created suspended
  FServer := AServer;
  FreeOnTerminate := False;
end;

{
procedure TStdioWorkerThread.Execute;
var
  JsonRequestLine: string;
begin
  while not Terminated do
  begin
    try
      // Read a complete line from Standard Input.
      // This call is blocking and would wait until receiving an LF (#10).
      System.ReadLn(JsonRequestLine);

      // If the thread was terminated while waiting or the line is empty, we continue.
      if Terminated or (JsonRequestLine = '') then
        Continue;

      // Each line is a complete JSON request. We process it.
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(FServer) and FServer.IsActive then
            FServer.ProcessRequest(JsonRequestLine);
        end);
    except
      on E: EInOutError do
      begin
        // This occurs if the stdin pipe is closed. It is the normal way to terminate.
        if not Terminated then
          Break;
      end;
      on E: Exception do
      begin
        // Other type of error, we terminate the loop.
        if not Terminated then
          Break;
      end;
    end;
  end;
end;

}

procedure TStdioWorkerThread.Execute;
var
  JsonRequestLine: string;
{$IFDEF MSWINDOWS}
  StdinHandle: THandle;
  RawLine: TBytes;
  B: Byte;
  BytesRead: DWORD;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  // Read raw bytes from stdin pipe and decode as UTF-8.
  // System.ReadLn converts using the ANSI code page (CP1252 on most Windows
  // systems), which corrupts multi-byte UTF-8 sequences. ReadFile + UTF-8
  // decoding is the correct approach when stdin is a pipe.
  StdinHandle := GetStdHandle(STD_INPUT_HANDLE);
  SetLength(RawLine, 0);
{$ENDIF}
  while not Terminated do
  begin
    try
{$IFDEF MSWINDOWS}
      // Accumulate bytes until LF, then decode the complete line as UTF-8.
      repeat
        if not ReadFile(StdinHandle, B, 1, BytesRead, nil) or (BytesRead = 0) then
        begin
          // Pipe closed (EOF)
          if Length(RawLine) > 0 then
            Break; // process the last partial line
          Exit;
        end;
        if B = 10 then Break; // LF = end of line
        if B <> 13 then // skip CR
        begin
          SetLength(RawLine, Length(RawLine) + 1);
          RawLine[High(RawLine)] := B;
        end;
      until False;
      JsonRequestLine := TEncoding.UTF8.GetString(RawLine);
      SetLength(RawLine, 0);
{$ELSE}
      System.ReadLn(JsonRequestLine);
{$ENDIF}

      if Terminated or (JsonRequestLine = '') then
        Continue;

      if Assigned(FServer) and FServer.IsActive then
      begin
        try
          FServer.ProcessRequest(JsonRequestLine);
        except
          // Catch exceptions so that a logic error does not kill the reading thread
        end;
      end;
    except
      on E: EInOutError do
      begin
        if not Terminated then Break;
      end;
      on E: Exception do
      begin
        if not Terminated then Break;
      end;
    end;
  end;
end;


{ TAiMCPStdioServer }

constructor TAiMCPStdioServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOutputLock := TCriticalSection.Create; // To protect Stdout
end;

destructor TAiMCPStdioServer.Destroy;
begin
  FOutputLock.Free;
  inherited Destroy;
end;

procedure TAiMCPStdioServer.Start;
begin

  if IsActive then
    Exit;

  SetConsoleIOToUTF8;

  Inherited Start;
  FWorkerThread := TStdioWorkerThread.Create(Self);
  FWorkerThread.Start;
end;

procedure TAiMCPStdioServer.Stop;
begin
  if not IsActive then
    Exit;

  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.Terminate;
    // We do not call WaitFor: ReadLn(Input) is blocking and uninterruptible.
    // The thread will exit naturally upon detecting EOF on stdin.
    FWorkerThread := nil;
  end;

  inherited Stop;
end;

procedure TAiMCPStdioServer.ProcessRequest(const ARequestJson: string);
var
  ResponseBody: string;
begin
  if not IsActive then
    Exit;

  // We delegate the heavy work to the logic server
  ResponseBody := FLogicServer.ExecuteRequest(ARequestJson, ''); // Session does not apply in Stdio

  // If there is a response to send (not a notification)
  if ResponseBody <> '' then
  begin
    SendResponse(ResponseBody);
  end;
end;

procedure TAiMCPStdioServer.SendResponse(const AResponseJson: string);
{$IFDEF MSWINDOWS}
var
  StdoutHandle: THandle;
  Bytes: TBytes;
  Written: DWORD;
{$ENDIF}
begin
  // Write directly to the Windows stdout handle so the response reaches
  // the MCP client even when the process is started without a console window
  // (e.g., spawned headless by Claude Code). System.WriteLn + Flush(Output)
  // does not flush the pipe in that scenario.
  FOutputLock.Enter;
  try
{$IFDEF MSWINDOWS}
    StdoutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    Bytes := TEncoding.UTF8.GetBytes(AResponseJson + #10);
    WriteFile(StdoutHandle, Bytes[0], Length(Bytes), Written, nil);
{$ELSE}
    System.WriteLn(AResponseJson);
    Flush(Output);
{$ENDIF}
  finally
    FOutputLock.Leave;
  end;
end;

procedure TAiMCPStdioServer.SetConsoleIOToUTF8;
begin
{$IFDEF MSWINDOWS}
  // Force UTF-8 (Codepage 65001) so that JSON does not break
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
{$ENDIF}
end;

end.
