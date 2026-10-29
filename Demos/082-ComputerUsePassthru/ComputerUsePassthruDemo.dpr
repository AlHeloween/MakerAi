program ComputerUsePassthruDemo;

{
  Demo 082 - Computer Use: who executes the action.

  A computer_call can be resolved in three ways, and this demo exercises
  all of them against the real API, without touching the screen:

    1. DELEGATED  - OnCallToolFunction fills ToolCall.Response, so the
                   driver does NOT execute anything locally. This is what a broker
                   headless that forwards the call to its remote client does.
    2. NO TOOL  - cap_ComputerUse is active but
                   ChatTools.ComputerUseTool is missing: incomplete configuration, the
                   turn is cut off with LastError instead of sending an invalid
                   output.
    3. LOCAL     - there is an executor: the driver executes, captures, responds with a
                   computer_call_output and recurses (normal agentic loop).

  Each case runs in synchronous and streaming mode, because the OpenAI
  driver has TWO separate implementations of computer_call.

  The executor for local cases is simulated: it returns success and a 1x1
  PNG as a "screenshot". This validates the complete round trip without moving the
  mouse or sending your desktop to the provider (demo 066 does that).

  Output: exit code 0 if everything that could be verified passed; 1 if something failed.
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Tools.Functions,
  uMakerAi.Tools.ComputerUse,
  uMakerAi.ParamsRegistry,
  uMakerAi.Chat.Initializations;

const
  // Valid 1x1 PNG. Acts as a screenshot without touching the real screen.
  CPng1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8' +
            'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  CDefaultModel = 'gpt-6-astra';
  CDefaultPrompt = 'Take control of the screen: take a screenshot and tell me ' +
                   'briefly what you see.';

type
  // What is expected from the turn, depending on who must execute the action.
  TCaseKind = (ckDelegated, ckMissingTool, ckLocal);

  TSpy = class
  public
    Calls: Integer; // veces que se disparo OnCallToolFunction
    Execs: Integer; // veces que se disparo OnExecuteAction
    Shots: Integer; // veces que se disparo OnRequestScreenshot
    Names: string;
    Done: Boolean;
    Intercept: Boolean;
    // If it is 1, it delegates from the first action. With a larger value it lets the
    // agentic loop do N-1 local rounds before cutting it.
    DelegateFrom: Integer;
    procedure ToolHandler(Sender: TObject; AiToolCall: TAiToolsFunction);
    procedure DataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSonObject; aRole, aText: String);
    procedure ExecuteAction(Sender: TObject; const ActionData: TAiActionData;
      var Result: TAiActionResult);
    procedure RequestShot(Sender: TObject; var MediaFile: TAiMediaFile);
  end;

var
  GModel: string = CDefaultModel;
  GPrompt: string = CDefaultPrompt;
  GFailures: Integer = 0;
  GSkips: Integer = 0;
  GPasses: Integer = 0;

procedure TSpy.ToolHandler(Sender: TObject; AiToolCall: TAiToolsFunction);
begin
  Inc(Calls);
  if Names <> '' then
    Names := Names + ', ';
  Names := Names + AiToolCall.Name;

  // The framework gate: if the handler leaves Response filled, the driver considers the
  // action executed elsewhere and does not touch it. Same contract in Claude,
  // in Gemini and in the generic TAiChat bridge.
  if Intercept and (Calls >= DelegateFrom) then
    AiToolCall.Response := '{"output":"delegated_to_remote_client"}';
end;

procedure TSpy.DataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSonObject; aRole, aText: String);
begin
  Done := True;
end;

procedure TSpy.ExecuteAction(Sender: TObject; const ActionData: TAiActionData;
  var Result: TAiActionResult);
begin
  Inc(Execs);
  Result.Success := True; // ejecutor simulado: nada se mueve de verdad
end;

procedure TSpy.RequestShot(Sender: TObject; var MediaFile: TAiMediaFile);
begin
  Inc(Shots);
  MediaFile := TAiMediaFile.Create;
  MediaFile.LoadFromBase64('shot.png', CPng1x1);
end;

function Kind(const S: string): string;
begin
  if ContainsText(S, '"type":"computer_call_output"') then
    Result := 'computer_call_output'
  else if ContainsText(S, '"type":"computer_call"') then
    Result := 'computer_call'
  else
    Result := 'texto';
end;

procedure RunCase(AKind: TCaseKind; AAsync: Boolean);
var
  Chat: TAiOpenChat;
  CU: TAiComputerUseTool;
  Spy: TSpy;
  Res, Title, Why: string;
  I, Waited, NOut, NCall: Integer;
  HasTool, WithExecutor, Ok: Boolean;
begin
  case AKind of
    ckDelegated:
      Title := 'DELEGATED (headless broker)';
    ckMissingTool:
      Title := 'WITHOUT assigned ComputerUseTool';
  else
    Title := 'LOCAL (simulated executor)';
  end;
  Title := Title + IfThen(AAsync, ' - streaming', ' - synchronous');

  HasTool := AKind <> ckMissingTool;
  WithExecutor := AKind = ckLocal;

  WriteLn('');
  WriteLn('==============================================================');
  WriteLn('CASE: ', Title);
  WriteLn('==============================================================');

  CU := nil;
  Spy := TSpy.Create;
  Chat := TAiOpenChat.Create(nil);
  try
    Spy.Intercept := AKind <> ckMissingTool;
    // In the local case, two real rounds are left before cutting the loop.
    // (The integer IfThen lives in System.Math and would clash with the one in System.StrUtils.)
    if AKind = ckLocal then
      Spy.DelegateFrom := 3
    else
      Spy.DelegateFrom := 1;

    Chat.ApiKey := '@OPENAI_API_KEY';
    Chat.Model := GModel;
    // Computer Use is deliberately OPT-IN: without cap_ComputerUse the 'computer' tool
    // is not even declared. The documented alternative is the registry, before
    // creating the component:
    //   TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra',
    //     'ModelCaps', '[cap_Image, cap_Reasoning, cap_ComputerUse]');
    Chat.ModelCaps := [cap_Image, cap_Reasoning, cap_ComputerUse];
    Chat.SessionCaps := [cap_Image, cap_Reasoning, cap_ComputerUse];
    Chat.Asynchronous := AAsync; // True = streaming
    Chat.OnCallToolFunction := Spy.ToolHandler;
    Chat.OnReceiveDataEnd := Spy.DataEnd;

    if HasTool then
    begin
      CU := TAiComputerUseTool.Create(nil);
      if WithExecutor then
      begin
        CU.OnExecuteAction := Spy.ExecuteAction;
        CU.OnRequestScreenshot := Spy.RequestShot;
      end;
      Chat.ChatTools.ComputerUseTool := CU;
    end;

    try
      Res := Chat.AddMessageAndRun(GPrompt, 'user', []);

      if AAsync then
      begin
        Waited := 0;
        while (not Spy.Done) and (Waited < 180000) do
        begin
          Sleep(200);
          Inc(Waited, 200);
        end;
        Sleep(3000); // gracia: el ultimo tramo del stream corre en su hilo
      end;

      if Res.Trim <> '' then
        WriteLn('Response: ', Copy(Res.Trim, 1, 160));
    except
      on E: Exception do
      begin
        WriteLn('EXCEPTION: ', E.ClassName, ': ', E.Message);
        Inc(GFailures);
        Exit;
      end;
    end;

    if Chat.LastError <> '' then
      WriteLn('LastError: ', Copy(Chat.LastError, 1, 220));

    WriteLn(Format('Events: OnCallToolFunction=%d (%s)  OnExecuteAction=%d  OnRequestScreenshot=%d',
      [Spy.Calls, Spy.Names, Spy.Execs, Spy.Shots]));

    NOut := 0;
    NCall := 0;
    WriteLn('History (', Chat.Messages.Count, ' messages):');
    for I := 0 to Chat.Messages.Count - 1 do
    begin
      WriteLn(Format('  [%d] role=%-9s len=%-6d %s', [I, Chat.Messages[I].Role,
        Length(Chat.Messages[I].Prompt), Kind(Chat.Messages[I].Prompt)]));
      if Kind(Chat.Messages[I].Prompt) = 'computer_call_output' then
        Inc(NOut);
      if Kind(Chat.Messages[I].Prompt) = 'computer_call' then
        Inc(NCall);
    end;
    WriteLn('Summary: computer_call=', NCall, '  computer_call_output=', NOut);

    if NCall = 0 then
    begin
      // The model decides whether to use the tool. If it did not use it, there is nothing to
      // verify; it is not a framework failure.
      WriteLn('SKIP: the model did not use the computer tool in this turn.');
      Inc(GSkips);
      Exit;
    end;

    Ok := True;
    Why := '';
    case AKind of
      ckDelegated:
        begin
          if NOut <> 0 then
          begin
            Ok := False;
            Why := 'a computer_call_output was emitted despite delegation';
          end
          else if (Spy.Execs <> 0) or (Spy.Shots <> 0) then
          begin
            Ok := False;
            Why := 'it was executed locally despite delegation';
          end;
        end;
      ckMissingTool:
        begin
          if NOut <> 0 then
          begin
            Ok := False;
            Why := 'a computer_call_output was emitted without an image (400 guaranteed)';
          end
          else if Chat.LastError = '' then
          begin
            Ok := False;
            Why := 'the turn was cut off without warning by LastError';
          end;
        end;
      ckLocal:
        begin
          if NOut = 0 then
          begin
            Ok := False;
            Why := 'no computer_call_output was emitted';
          end
          else if (Spy.Execs = 0) or (Spy.Shots = 0) then
          begin
            Ok := False;
            Why := 'the local executor was not called';
          end;
        end;
    end;

    if Ok then
    begin
      WriteLn('PASS');
      Inc(GPasses);
    end
    else
    begin
      WriteLn('FAIL: ', Why);
      Inc(GFailures);
    end;
  finally
    Chat.Free;
    if Assigned(CU) then
      CU.Free;
    Spy.Free;
  end;
end;

procedure Usage;
begin
  WriteLn('Demo 082 - Computer Use: who executes the action');
  WriteLn('');
  WriteLn('  ComputerUsePassthruDemo.exe [options]');
  WriteLn('');
  WriteLn('  --case=all|delegated|missing|local   (default: all)');
  WriteLn('  --mode=both|sync|stream              (default: both)');
  WriteLn('  --model=<id>                         (default: ', CDefaultModel, ')');
  WriteLn('  --prompt=<text>');
  WriteLn('  --help');
  WriteLn('');
  WriteLn('Requires the OPENAI_API_KEY environment variable.');
  WriteLn('Makes REAL calls to the API. Does not touch the screen.');
end;

function ArgValue(const AName, ADefault: string): string;
var
  I: Integer;
  S: string;
begin
  Result := ADefault;
  for I := 1 to ParamCount do
  begin
    S := ParamStr(I);
    if S.StartsWith(AName + '=') then
      Exit(S.Substring(Length(AName) + 1));
  end;
end;

function HasArg(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AName) then
      Exit(True);
end;

var
  LCase, LMode: string;
  LDoSync, LDoStream: Boolean;

begin
  try
    if HasArg('--help') or HasArg('-h') then
    begin
      Usage;
      Halt(0);
    end;

    if GetEnvironmentVariable('OPENAI_API_KEY') = '' then
    begin
      WriteLn('ERROR: the OPENAI_API_KEY environment variable is missing.');
      Halt(2);
    end;

    LCase := LowerCase(ArgValue('--case', 'all'));
    LMode := LowerCase(ArgValue('--mode', 'both'));
    GModel := ArgValue('--model', CDefaultModel);
    GPrompt := ArgValue('--prompt', CDefaultPrompt);

    LDoSync := (LMode = 'both') or (LMode = 'sync');
    LDoStream := (LMode = 'both') or (LMode = 'stream');

    WriteLn('Model: ', GModel);

    if (LCase = 'all') or (LCase = 'delegated') then
    begin
      if LDoSync then
        RunCase(ckDelegated, False);
      if LDoStream then
        RunCase(ckDelegated, True);
    end;

    if (LCase = 'all') or (LCase = 'missing') then
    begin
      if LDoSync then
        RunCase(ckMissingTool, False);
      if LDoStream then
        RunCase(ckMissingTool, True);
    end;

    if (LCase = 'all') or (LCase = 'local') then
    begin
      if LDoSync then
        RunCase(ckLocal, False);
      if LDoStream then
        RunCase(ckLocal, True);
    end;

    WriteLn('');
    WriteLn('==============================================================');
    WriteLn(Format('RESULT: %d PASS, %d FAIL, %d SKIP',
      [GPasses, GFailures, GSkips]));
    WriteLn('==============================================================');

    if GFailures > 0 then
      Halt(1);
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.ClassName, ': ', E.Message);
      Halt(3);
    end;
  end;

end.
