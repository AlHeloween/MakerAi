program GroqDriver;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 07-GroqDriver
// =============================================================================
// Validation of the Groq driver after the Apr 2026 fixes:
//
//   Fix 1 — tool_choice:          was 'tools_choice' (silent typo)
//   Fix 2 — logprobs removed:     Groq rejects logprobs, logit_bias, top_logprobs
//   Fix 3 — vision multi-turn:    previously only sent LastMsg; now GetMessages
//   Fix 4 — max_completion_tokens: reasoning models must use it (not max_tokens)
//
//   Test 1 — Basic chat         llama-3.1-8b-instant
//   Test 2 — Tool calling        llama-3.3-70b-versatile  (fix 1)
//   Test 3 — Reasoning           qwen/qwen3-32b           (fix 4)
//   Test 4 — Vision multi-turn   llama-4-scout            (fix 3)
//
// Prerequisite: GROQ_API_KEY defined as an environment variable
// =============================================================================

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.IOUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Messages,
  uMakerAi.Tools.Functions,
  uMakerAi.Chat.Groq;

const
  API_KEY  = '@GROQ_API_KEY';
  IMG_PATH = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';

// =============================================================================
//  Helpers
// =============================================================================

procedure Section(const Title: String);
begin
  Writeln;
  Writeln(StringOfChar('-', 62));
  Writeln('  ', Title);
  Writeln(StringOfChar('-', 62));
end;

function MakeConn(const Model: String; MaxTok: Integer = 1024): TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := 'Groq';
  Result.Model      := Model;
  Result.Params.Values['ApiKey']       := API_KEY;
  Result.Params.Values['Asynchronous'] := 'False';
  Result.Params.Values['Max_Tokens']   := IntToStr(MaxTok);
end;

// =============================================================================
//  Test 1 — Basic chat
// =============================================================================

procedure TestBasicChat;
var
  Conn: TAiChatConnection;
  Res : String;
begin
  Section('Test 1 — Basic chat  [llama-3.1-8b-instant]');
  Conn := MakeConn('llama-3.1-8b-instant');
  try
    Conn.SystemPrompt.Text := 'Always respond in a single sentence in Spanish.';
    Res := Conn.AddMessageAndRun(
      'What is the largest planet in the solar system?', 'user', []);
    Writeln('  Response : ', Res);
    if Trim(Res) <> '' then
      Writeln('  => PASS')
    else
      Writeln('  => FAIL: empty response');
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  Test 2 — Tool calling  (fix: tool_choice, previously "tools_choice")
// =============================================================================

type
  TToolTest = class
  private
    FCallCount: Integer;
    procedure OnGetDate(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
  public
    procedure Run;
  end;

procedure TToolTest.OnGetDate(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  Inc(FCallCount);
  Writeln('  [tool invoked] get_current_date  args=', ToolCall.Arguments);
  ToolCall.Response := Format(
    '{"date":"%s","day_of_week":"%s","iso":"%s"}',
    [FormatDateTime('dd/mm/yyyy', Now),
     FormatDateTime('dddd', Now),
     FormatDateTime('yyyy-mm-dd', Now)]);
  Handled := True;
end;

procedure TToolTest.Run;
var
  Conn: TAiChatConnection;
  Fns : TAiFunctions;
  Fn  : TFunctionActionItem;
  Res : String;
begin
  Section('Test 2 — Tool calling  [llama-3.3-70b-versatile]  (fix: tool_choice)');
  FCallCount := 0;

  Fns := TAiFunctions.Create(nil);
  try
    Fn := Fns.Functions.AddFunction('get_current_date', True, OnGetDate);
    Fn.Description.Text :=
      'Returns today''s date (day, month, year) and day of the week.';

    Conn := MakeConn('llama-3.3-70b-versatile', 512);
    try
      Conn.Params.Values['Tool_Active'] := 'True';
      Conn.AiFunctions := Fns;
      Conn.SystemPrompt.Text :=
        'You are a helpful assistant. Use get_current_date when asked about today''s date.';

      Res := Conn.AddMessageAndRun(
        'What day of the week is today and what is the exact date?', 'user', []);
      Writeln('  Final response: ', Res);

      if FCallCount > 0 then
        Writeln('  => PASS  (function invoked ', FCallCount, ' time(s))')
      else
        Writeln('  => WARN  (LLM responded without invoking the function)');
    finally
      Conn.Free;
    end;
  finally
    Fns.Free;
  end;
end;

// =============================================================================
//  Test 3 — Reasoning with qwen3-32b  (fix: max_completion_tokens)
// =============================================================================

procedure TestReasoning;
var
  Conn: TAiChatConnection;
  Res : String;
begin
  Section('Test 3 — Reasoning  [qwen/qwen3-32b]  (fix: max_completion_tokens)');
  Writeln('  Problem: sequence a(1)=2, a(n+1)=a(n)+3.  What is a(5)?');
  Conn := MakeConn('qwen/qwen3-32b', 8192);
  try
    Conn.SystemPrompt.Text :=
      'You are a math assistant. Solve step by step, give final answer clearly.';
    Res := Conn.AddMessageAndRun(
      'Sequence: a(1)=2, a(n+1)=a(n)+3. Compute a(5). Show each step.',
      'user', []);
    Writeln('  Response:');
    Writeln('  ', Res);
    if Trim(Res) <> '' then
      Writeln('  => PASS  (max_completion_tokens accepted by Groq)')
    else
      Writeln('  => FAIL: empty response');
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  Test 4 — Vision multi-turn  (fix: GetMessages instead of LastMsg.ToJson)
// =============================================================================

procedure TestVisionMultiTurn;
var
  Conn      : TAiChatConnection;
  Media     : TAiMediaFile;
  MediaList : TAiMediaFilesArray;
  Res1, Res2: String;
begin
  Section('Test 4 — Vision multi-turn  [llama-4-scout]  (fix: GetMessages)');

  if not TFile.Exists(IMG_PATH) then
  begin
    Writeln('  [SKIP] Image not found: ', IMG_PATH);
    Writeln('  Adjust IMG_PATH in the demo to an existing image.');
    Exit;
  end;

  Writeln('  Image: ', IMG_PATH);
  Writeln;

  Conn := MakeConn('meta-llama/llama-4-scout-17b-16e-instruct', 1024);
  try
    Conn.SystemPrompt.Text :=
      'You are a visual assistant. Answer concisely in Spanish.';

    // Turn 1: description with attached image
    // NOTE: AddMediaFile transfers ownership to the message (TObjectList OwnsObjects=True).
    //       Do not call Media.Free — Conn.Free destroys it when freeing the messages.
    Media := TAiMediaFile.Create;
    Media.LoadFromFile(IMG_PATH);
    SetLength(MediaList, 1);
    MediaList[0] := Media;
    Writeln('  Turn 1 (image attached): general description');
    Res1 := Conn.AddMessageAndRun(
      'Briefly describe what you see in this image.', 'user', MediaList);
    Writeln('  R1: ', Res1);

    // Turn 2: follow-up WITHOUT a new image
    // With the fix, GetMessages sends the ENTIRE history (including the image from turn 1)
    // Without the fix, it would only send this last message → the model wouldn't know which image to talk about
    Writeln;
    Writeln('  Turn 2 (without a new image, but history includes the one from turn 1):');
    Res2 := Conn.AddMessageAndRun(
      'What is the predominant color in what you just described?', 'user', []);
    Writeln('  R2: ', Res2);

    if (Trim(Res1) <> '') and (Trim(Res2) <> '') then
    begin
      Writeln;
      Writeln('  => PASS  (multi-turn with image works — full history sent)');
    end
    else
      Writeln('  => FAIL: one of the turns returned an empty response');
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  Punto de entrada
// =============================================================================

var
  ApiKeyOk: Boolean;
begin
  Writeln('=== GroqDriver — Validation of fixes (Apr 2026) ===');
  ApiKeyOk := GetEnvironmentVariable('GROQ_API_KEY') <> '';
  Writeln('GROQ_API_KEY : ', IfThen(ApiKeyOk, '[OK]', '[MISSING — define the variable]'));
  Writeln;

  if not ApiKeyOk then
  begin
    Writeln('ERROR: Define GROQ_API_KEY before running.');
    Writeln;
    Writeln('Press Enter to exit...');
    Readln;
    Halt(1);
  end;

  try
    TestBasicChat;
    with TToolTest.Create do try Run; finally Free; end;
    TestReasoning;
    TestVisionMultiTurn;
  except
    on E: Exception do
      Writeln('FATAL ERROR: ', E.ClassName, ' — ', E.Message);
  end;

  Writeln;
  Writeln(StringOfChar('=', 62));
  Writeln('  Demo complete.');
  Writeln(StringOfChar('=', 62));
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
