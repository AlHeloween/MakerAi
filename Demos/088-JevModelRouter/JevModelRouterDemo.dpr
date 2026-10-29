program JevModelRouterDemo;

// =============================================================================
// DEMO 088 - Model router with Jev: the cheapest model that suffices
// =============================================================================
// TAiJevModelRouter describes each request with Jev (task, difficulty,
// sensitivity) and chooses in code the cheapest tier that suffices:
//
//   level 0  Groq     openai/gpt-oss-20b     trivial
//   level 1  DeepSeek deepseek-v4-flash      standard
//   level 2  Claude   claude-sonnet-5        demanding / sensitive
//   level 3  Claude   claude-opus-5          expert
//
//   A. Standalone requests: each is answered by the chosen model, and
//      TAiJevEvalScorer measures whether the response is correct and useful. It is the
//      quality test: that the cheap model answers well what it is assigned.
//   B. A conversation that starts trivial (Groq) and scales to expert
//      (Claude Opus): the history is migrated between providers and the new model
//      must remember what was said in the first turn.
//
// Requires TYPESAFE_API_KEY, GROQ_API_KEY, DEEPSEEK_API_KEY and CLAUDE_API_KEY.
// Responses are limited to 1200 tokens to cap the cost.
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.StrUtils,
  System.Net.HttpClient,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,   // registers the drivers (Groq, DeepSeek, Claude...)
  uMakerAi.Jev in '..\..\Source\Tools\uMakerAi.Jev.pas',
  uMakerAi.Jev.Evals in '..\..\Source\Tools\uMakerAi.Jev.Evals.pas',
  uMakerAi.Jev.ModelRouter in '..\..\Source\Tools\uMakerAi.Jev.ModelRouter.pas';

const
  PETICIONES: array[0..7] of string = (
    'Hello, good morning',
    'Translate to English: the meeting is postponed to Monday',
    'Write a Delphi function that reverses a string',
    'Explain the difference between an abstract class and an interface in Delphi',
    'I get an access violation when freeing a TStringList inside a finally, what could it be?',
    'Can I deduct housing loan interest from income tax if I am self-employed in Colombia?',
    'Compare PostgreSQL and SQL Server for a multi-company ERP and recommend one with arguments',
    'Design the multi-tenant architecture of an accounting ERP with PostgreSQL, offline synchronization and auditing');

  CRITERIO_CALIDAD = 'It correctly and usefully answers the user request in `input`';

type
  // Framework events are 'of object': the handler lives in a class
  TErrores = class
  public
    Ultimo: string;
    procedure OnError(Sender: TObject; const ErrorMsg: string; Exception: Exception;
      const AResponse: IHTTPResponse);
  end;

var
  Errores: TErrores;

procedure TErrores.OnError(Sender: TObject; const ErrorMsg: string; Exception: Exception;
  const AResponse: IHTTPResponse);
begin
  Ultimo := ErrorMsg;
end;

function Corto(const S: string; N: Integer): string;
begin
  Result := StringReplace(StringReplace(Trim(S), #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  if Length(Result) > N then
    Result := Copy(Result, 1, N) + '...';
end;

procedure Configurar(ARouter: TAiJevModelRouter);
var
  T: TAiJevModelTier;
begin
  // Groq retired the llama-3.x (model_not_found, Sep 2026): gpt-oss-20b is its fast model
  ARouter.Tiers.AddTier('fast',   'Groq',     'openai/gpt-oss-20b', 0, 0.3);
  ARouter.Tiers.AddTier('standard', 'DeepSeek', 'deepseek-v4-flash',  1, 0.4);
  // Claude: low reasoning and no web search. With the defaults, Opus exceeded
  // the HTTP timeout (~300 s) on the architecture question; this way it answered in 91 s.
  T := ARouter.Tiers.AddTier('demanding', 'Claude', 'claude-sonnet-5', 2, 15);
  T.Params.Add('ThinkingLevel=tlLow');
  T.Params.Add('SessionCaps=[cap_Image, cap_Pdf]');
  T := ARouter.Tiers.AddTier('expert', 'Claude', 'claude-opus-5', 3, 25);
  T.Params.Add('ThinkingLevel=tlLow');
  T.Params.Add('SessionCaps=[cap_Image, cap_Pdf]');
  T.Params.Add('Max_Tokens=3000');
  // Changing provider reloads the driver Params: this applies to all
  ARouter.ConnectionParams.Add('Asynchronous=False');
  ARouter.ConnectionParams.Add('Max_Tokens=1200');
end;

procedure BloquePeticiones(ARouter: TAiJevModelRouter; AScorer: TAiJevEvalScorer);
var
  P, Resp: string;
  Conn: TAiChatConnection;
  R: TAiModelRoute;
  SW: TStopwatch;
  Q: Double;
  Buenas: Integer;
begin
  Writeln('--- A. Each request to the cheapest model that suffices ---');
  Writeln;
  Buenas := 0;
  for P in PETICIONES do
  begin
    Conn := TAiChatConnection.Create(nil);
    try
      Conn.OnError := Errores.OnError;
      Errores.Ultimo := '';
      R := ARouter.Route(P);
      ARouter.Apply(Conn, R);
      SW := TStopwatch.StartNew;
      Resp := Conn.AddMessageAndRun(P, 'user', []);
      SW.Stop;
      Q := AScorer.Score(CRITERIO_CALIDAD, P, Resp);
      if Q >= 0.7 then
        Inc(Buenas);
      Writeln(Format('[level %d] %-9s %-22s %5d ms  quality %.2f', [R.Level, R.TierName, R.Model,
        SW.ElapsedMilliseconds, Q]));
      Writeln('  question: ', Corto(P, 90));
      Writeln('  reason:   ', R.Reason);
      Writeln('  response: ', Corto(Resp, 110));
      if Errores.Ultimo <> '' then
        Writeln('  ERROR: ', Corto(Errores.Ultimo, 200));
      Writeln;
    finally
      Conn.Free;
    end;
  end;
  Writeln(Format('Useful responses (quality >= 0.70): %d of %d', [Buenas, Length(PETICIONES)]));
  Writeln;
end;

procedure BloqueConversacion(ARouter: TAiJevModelRouter; AScorer: TAiJevEvalScorer);
const
  TURNO1 = 'Hello, my name is Gustavo and I have a hardware store in Bogota that sells screws wholesale.';
  TURNO2 = 'Design an expansion plan to three cities for my business, taking into account what I told you.';
var
  Conn: TAiChatConnection;
  Resp: string;
  Q: Double;
begin
  Writeln('--- B. A conversation that scales across providers ---');
  Writeln;
  Conn := TAiChatConnection.Create(nil);
  try
    Resp := ARouter.Ask(Conn, TURNO1);
    Writeln(Format('Turn 1 -> %s / %s (level %d)', [ARouter.LastRoute.DriverName,
      ARouter.LastRoute.Model, ARouter.LastRoute.Level]));
    Writeln('  ', Corto(Resp, 110));

    Resp := ARouter.Ask(Conn, TURNO2);
    Writeln(Format('Turn 2 -> %s / %s (level %d), messages in the conversation: %d',
      [ARouter.LastRoute.DriverName, ARouter.LastRoute.Model, ARouter.LastRoute.Level,
       Conn.Messages.Count]));
    Writeln('  ', Corto(Resp, 160));

    // The new model can only know this if the history was migrated
    Q := AScorer.Score('It builds on the fact that the user owns a hardware store in Bogota ' +
      'selling screws wholesale', TURNO2, Resp);
    Writeln(Format('  Remembers the business from turn 1: %s (Jev %.2f; mentions hardware store/screws: %s)',
      [IfThen(Q >= 0.7, 'yes', 'NO'), Q,
       IfThen(ContainsText(Resp, 'ferreter') or ContainsText(Resp, 'tornillo'), 'si', 'no')]));
  finally
    Conn.Free;
  end;
  Writeln;
end;

var
  Router: TAiJevModelRouter;
  Scorer: TAiJevEvalScorer;
begin
  try
    if GetEnvironmentVariable('TYPESAFE_API_KEY') = '' then
    begin
      Writeln('The TYPESAFE_API_KEY environment variable is missing (https://console.typesafe.ai/keys).');
      ExitCode := 2;
      Exit;
    end;
    Errores := TErrores.Create;
    Router := TAiJevModelRouter.Create(nil);
    Scorer := TAiJevEvalScorer.Create(nil);
    try
      Configurar(Router);
      BloquePeticiones(Router, Scorer);
      BloqueConversacion(Router, Scorer);
    finally
      Router.Free;
      Scorer.Free;
      Errores.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
