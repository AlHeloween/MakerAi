program PromptCacheTest;

{$APPTYPE CONSOLE}
{$R *.res}

// Runtime test of prompt caching in Claude.
// Fires 2 requests with the SAME large system prompt (>1024 tokens) and the
// portable CacheContext flag enabled. Expected:
//   Request 1 -> cache_write > 0 (writes the system into cache)
//   Request 2 -> cache_read  > 0 (reads the system from cache; same prefix)
// Requires CLAUDE_API_KEY in the environment.

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.Initializations;

type
  TCap = class
  public
    Input, CacheWrite, CacheRead: Integer;
    procedure OnEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSonObject; aRole, aText: string);
    procedure OnError(Sender: TObject; const ErrorMsg: string;
      AException: Exception; const AResponse: IHTTPResponse);
  end;

procedure TCap.OnEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSonObject; aRole, aText: string);
begin
  if Assigned(aMsg) then
  begin
    Input := aMsg.Prompt_tokens;
    CacheWrite := aMsg.Cache_write_tokens;
    CacheRead := aMsg.Cached_tokens;
  end;
end;

procedure TCap.OnError(Sender: TObject; const ErrorMsg: string;
  AException: Exception; const AResponse: IHTTPResponse);
begin
  if Assigned(AResponse) and (AResponse.StatusCode > 0) then
    WriteLn('  ERROR HTTP=' + IntToStr(AResponse.StatusCode) + ' | ' + ErrorMsg)
  else
    WriteLn('  ERROR: ' + ErrorMsg);
end;

function BigSystem: string;
var
  I: Integer;
begin
  Result := 'You are an expert assistant in the MakerAI framework for Delphi. ' +
    'Always respond very briefly. Reference context you must consider:' + sLineBreak;
  for I := 1 to 70 do
    Result := Result + Format(
      'Rule %d: MakerAI unifies multiple LLM providers (OpenAI, Claude, Gemini, Ollama, ' +
      'Groq, Mistral, DeepSeek, Kimi, Grok, Cohere) under the TAiChatConnection component, ' +
      'with support for vector and graph RAG, MCP protocol, autonomous agents and ' +
      'native tools (vision, voice, web search, image and video generation).', [I]) + sLineBreak;
end;

procedure RunOne(Conn: TAiChatConnection; Cap: TCap; const ALabel, APrompt: string);
var
  R: string;
begin
  WriteLn('=== ' + ALabel + ' ===');
  Cap.Input := 0; Cap.CacheWrite := 0; Cap.CacheRead := 0;
  R := Conn.AddMessageAndRun(APrompt, 'user', []);
  WriteLn('  Response: ' + Trim(R));
  WriteLn(Format('  input=%d  cache_write=%d  cache_read=%d',
    [Cap.Input, Cap.CacheWrite, Cap.CacheRead]));
end;

var
  Conn: TAiChatConnection;
  Cap: TCap;

begin
  try
    Cap := TCap.Create;
    Conn := TAiChatConnection.Create(nil);
    try
      Conn.DriverName := 'Claude';
      Conn.Model := 'claude-opus-4-8';
      Conn.Params.Values['ApiKey'] := '@CLAUDE_API_KEY';
      Conn.Params.Values['Asynchronous'] := 'False';
      Conn.Params.Values['Max_Tokens'] := '300';
      Conn.Params.Values['Tool_Active'] := 'False';
      Conn.Params.Values['CacheContext'] := 'True'; // <-- flag portable de prompt caching
      Conn.SystemPrompt.Text := BigSystem;
      Conn.OnReceiveDataEnd := Cap.OnEnd;
      Conn.OnError := Cap.OnError;

      WriteLn('Model: claude-opus-4-8  | CacheContext=True');
      WriteLn(Format('System prompt: %d chars', [Length(Conn.SystemPrompt.Text)]));
      WriteLn('');

      RunOne(Conn, Cap, 'Request 1 (cache_write>0: writes system + turn)', 'Say "hello" in a single word.');
      WriteLn('');
      Sleep(1500);
      RunOne(Conn, Cap, 'Request 2 (cache_read>0: reads system + turn 1)', 'Now say "goodbye" in a single word.');
      var LRead2 := Cap.CacheRead;
      WriteLn('');
      Sleep(1500);
      RunOne(Conn, Cap, 'Request 3 (larger cache_read: prefix grew with turn 2)', 'And now say "thanks" in a single word.');

      WriteLn('');
      WriteLn('=== Verdict ===');
      if Cap.CacheRead > 0 then
        WriteLn('OK: caching effective. cache_read Req2=' + IntToStr(LRead2) +
                ', Req3=' + IntToStr(Cap.CacheRead) +
                ' (the cached prefix grows with each turn via auto-cache of the last turn).')
      else
        WriteLn('ATTENTION: cache_read=0 (caching not effective, review)');
    finally
      Conn.Free;
      Cap.Free;
    end;
    WriteLn('=== END ===');
  except
    on E: Exception do
      WriteLn('FATAL: ' + E.ClassName + ': ' + E.Message);
  end;
end.
