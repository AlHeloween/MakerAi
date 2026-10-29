// MIT License
//
// MakerAI - Jev: LLM model router using the Jev model (TypeSafe AI)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Jev.ModelRouter;

// -----------------------------------------------------------------------------
// TAiJevModelRouter: chooses, for each request, the cheapest model that
// suffices. Jev does NOT choose the model (it doesn't know prices or
// capabilities): it describes the request in a single call with three
// questions, and the CODE decides with rules that can be read and changed:
//
//   task       Choice  conversation / writing / code / analysis /
//                       mathematics / data
//   difficulty  Score   0 trivial .. 3 expert
//   sensitive    Noul    legal, medical, tax or financial decisions with
//                        real consequences
//
//   level = round(difficulty)
//         + 1 if confidence in difficulty is < 0.5 (when in doubt, bump up)
//         >= CodeMinLevel if task is code, analysis or mathematics
//         >= SensitiveMinLevel if sensitive > SensitiveThreshold
//         =  3 if even the task is unknown (confidence < 0.4)
//
// The model is the cheapest Tier (Cost) whose MaxLevel reaches the level.
//
//   Router.Tiers.AddTier('fast',   'Groq',     'openai/gpt-oss-20b',   0, 0.3);
//   Router.Tiers.AddTier('standard', 'DeepSeek', 'deepseek-v4-flash',    1, 0.3);
//   Router.Tiers.AddTier('expert',  'Claude',   'claude-opus-5',        3, 15);
//   Answer := Router.Ask(Connection, Question);   // routes, applies and executes
//
// Changing the provider in TAiChatConnection recreates the internal chat and
// the history is lost. With MigrateHistory (default) the text user/assistant
// messages are copied to the new chat; tool calls are NOT copied (their format
// and ids are provider-specific). Changing only the model within the same
// provider preserves everything. The SystemPrompt lives in the connection and
// survives in both cases. Params do NOT: the new driver brings its own
// (its ApiKey '@<PROVIDER>_API_KEY' included); what must apply to all models
// (Asynchronous=False, Max_Tokens, ...) goes in ConnectionParams, applied on
// each Apply; model-specific goes in the tier's Params (applied afterwards).
// Real example: claude-opus-5 with default reasoning exceeded HTTP timeout
// (~300 s) on a design question; with ThinkingLevel=tlLow it responded in 91 s.
//
// Calibrated against jev-1.13.0 (sep 28/2026) on 16 requests of known
// difficulty: 13 exact, 2 one level higher (spends too much), 1 one level lower.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math, System.Generics.Collections,
  uMakerAi.Jev, uMakerAi.Chat.Messages, uMakerAi.Chat.AiConnection;

type
  TAiModelRoute = record
    TierName: string;
    DriverName: string;
    Model: string;
    Level: Integer;          // 0 trivial .. 3 expert
    Task: string;
    TaskConfidence: Double;
    Difficulty: Double;      // expected value 0..3
    DifficultyConfidence: Double;
    Sensitive: Double;
    Reason: string;          // why that level, readable
  end;

  TAiJevModelTier = class(TCollectionItem)
  private
    FName: string;
    FDriverName: string;
    FModel: string;
    FMaxLevel: Integer;
    FCost: Double;
    FParams: TStrings;
    procedure SetParams(const Value: TStrings);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Name: string read FName write FName;
    property DriverName: string read FDriverName write FDriverName;
    property Model: string read FModel write FModel;
    // Highest level (0..3) trusted to this model
    property MaxLevel: Integer read FMaxLevel write FMaxLevel;
    // Relative cost (e.g. US$ per million output tokens); decides among ties
    property Cost: Double read FCost write FCost;
    // 'name=value' specific to this model (e.g. ThinkingLevel, Max_Tokens);
    // applied to the connection after ConnectionParams
    property Params: TStrings read FParams write SetParams;
  end;

  TAiJevModelTiers = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TAiJevModelTier;
  public
    constructor Create(AOwner: TPersistent);
    function AddTier(const AName, ADriverName, AModel: string; AMaxLevel: Integer;
      ACost: Double): TAiJevModelTier;
    // Cheapest with MaxLevel >= ALevel; if none reaches, the one with highest MaxLevel
    function Pick(ALevel: Integer): TAiJevModelTier;
    function FindTier(const AName: string): TAiJevModelTier;
    property Items[Index: Integer]: TAiJevModelTier read GetItem; default;
  end;

  TAiJevModelRouteEvent = procedure(Sender: TObject; const APrompt: string;
    var ARoute: TAiModelRoute) of object;

  TAiJevModelRouter = class(TComponent)
  private
    FUsage: TAiJevUsageMeter;
    FPricePerMillionInput: Double;
    FPricePerMillionOutput: Double;
    FOnUsage: TAiJevUsageEvent;
    FJev: TAiJev;
    FOwnJev: TAiJev;
    FApiKey: string;
    FModel: string;
    FUrl: string; // '' = TypeSafe (JEV_DEFAULT_URL)
    FTiers: TAiJevModelTiers;
    FSensitiveThreshold: Double;
    FSensitiveMinLevel: Integer;
    FCodeMinLevel: Integer;
    FBumpOnDoubt: Boolean;
    FMigrateHistory: Boolean;
    FConnectionParams: TStrings;
    FLastRoute: TAiModelRoute;
    FOnRoute: TAiJevModelRouteEvent;
    procedure SetJev(const Value: TAiJev);
    procedure SetTiers(const Value: TAiJevModelTiers);
    procedure SetConnectionParams(const Value: TStrings);
    function ActiveJev: TAiJev;
    function GetUsage: TAiJevUsage;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev consumption accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
    // Only decides (one Jev call); does not touch any connection
    function Route(const APrompt: string): TAiModelRoute;
    // Sets DriverName/Model on the connection; migrates history if provider changes
    procedure Apply(AConnection: TAiChatConnection; const ARoute: TAiModelRoute);
    // Route + Apply + AddMessageAndRun
    function Ask(AConnection: TAiChatConnection; const APrompt: string): string;
    property LastRoute: TAiModelRoute read FLastRoute;
  published
    // Optional: external TAiJev (shared or test double)
    property Jev: TAiJev read FJev write SetJev;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    // System One server: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;
    property Tiers: TAiJevModelTiers read FTiers write SetTiers;
    property SensitiveThreshold: Double read FSensitiveThreshold write FSensitiveThreshold;
    // Minimum level for sensitive content (2 = never the cheapest model)
    property SensitiveMinLevel: Integer read FSensitiveMinLevel write FSensitiveMinLevel default 2;
    // Minimum level for code, analysis and mathematics
    property CodeMinLevel: Integer read FCodeMinLevel write FCodeMinLevel default 1;
    // Bump one level if Jev doubts the difficulty
    property BumpOnDoubt: Boolean read FBumpOnDoubt write FBumpOnDoubt default True;
    // Copy text messages when changing provider
    property MigrateHistory: Boolean read FMigrateHistory write FMigrateHistory default True;
    // 'name=value' applied to AConnection.Params on each Apply
    // (changing provider reloads the driver's default Params)
    property ConnectionParams: TStrings read FConnectionParams write SetConnectionParams;
    property OnRoute: TAiJevModelRouteEvent read FOnRoute write FOnRoute;
    // Prices for CostUSD of Usage/OnUsage (US$ per million tokens; output is currently free)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with the consumption of that operation. Synchronous, in the thread
    // that executed it (on a server: the request thread, to bill the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJevModelRouter]);
end;

function Inv(AValue: Double): string;
begin
  Result := FormatFloat('0.00', AValue, TFormatSettings.Invariant);
end;

{ TAiJevModelTier }

constructor TAiJevModelTier.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FParams := TStringList.Create;
end;

destructor TAiJevModelTier.Destroy;
begin
  FParams.Free;
  inherited;
end;

procedure TAiJevModelTier.SetParams(const Value: TStrings);
begin
  FParams.Assign(Value);
end;

function TAiJevModelTier.GetDisplayName: string;
begin
  if FName <> '' then
    Result := Format('%s (%s/%s, <= %d)', [FName, FDriverName, FModel, FMaxLevel])
  else
    Result := inherited GetDisplayName;
end;

procedure TAiJevModelTier.Assign(Source: TPersistent);
begin
  if Source is TAiJevModelTier then
  begin
    FName := TAiJevModelTier(Source).FName;
    FDriverName := TAiJevModelTier(Source).FDriverName;
    FModel := TAiJevModelTier(Source).FModel;
    FMaxLevel := TAiJevModelTier(Source).FMaxLevel;
    FCost := TAiJevModelTier(Source).FCost;
    FParams.Assign(TAiJevModelTier(Source).FParams);
  end
  else
    inherited;
end;

{ TAiJevModelTiers }

constructor TAiJevModelTiers.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TAiJevModelTier);
end;

function TAiJevModelTiers.GetItem(Index: Integer): TAiJevModelTier;
begin
  Result := TAiJevModelTier(inherited GetItem(Index));
end;

function TAiJevModelTiers.AddTier(const AName, ADriverName, AModel: string; AMaxLevel: Integer;
  ACost: Double): TAiJevModelTier;
begin
  Result := TAiJevModelTier(Add);
  Result.Name := AName;
  Result.DriverName := ADriverName;
  Result.Model := AModel;
  Result.MaxLevel := AMaxLevel;
  Result.Cost := ACost;
end;

function TAiJevModelTiers.FindTier(const AName: string): TAiJevModelTier;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if SameText(Items[i].Name, AName) then
      Exit(Items[i]);
  Result := nil;
end;

function TAiJevModelTiers.Pick(ALevel: Integer): TAiJevModelTier;
var
  i: Integer;
  T: TAiJevModelTier;
begin
  Result := nil;
  for i := 0 to Count - 1 do
  begin
    T := Items[i];
    if (T.MaxLevel >= ALevel) and ((Result = nil) or (T.Cost < Result.Cost)) then
      Result := T;
  end;
  if Result <> nil then
    Exit;
  // None reaches: the most capable available
  for i := 0 to Count - 1 do
    if (Result = nil) or (Items[i].MaxLevel > Result.MaxLevel) then
      Result := Items[i];
end;

{ TAiJevModelRouter }

constructor TAiJevModelRouter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FTiers := TAiJevModelTiers.Create(Self);
  FSensitiveThreshold := 0.6;
  FSensitiveMinLevel := 2;
  FCodeMinLevel := 1;
  FBumpOnDoubt := True;
  FMigrateHistory := True;
  FConnectionParams := TStringList.Create;
end;

destructor TAiJevModelRouter.Destroy;
begin
  FTiers.Free;
  FConnectionParams.Free;
  FOwnJev.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevModelRouter.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevModelRouter.SetTiers(const Value: TAiJevModelTiers);
begin
  FTiers.Assign(Value);
end;

procedure TAiJevModelRouter.SetConnectionParams(const Value: TStrings);
begin
  FConnectionParams.Assign(Value);
end;

procedure TAiJevModelRouter.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevModelRouter.ActiveJev: TAiJev;
begin
  if Assigned(FJev) then
    Exit(FJev);
  if not Assigned(FOwnJev) then
    FOwnJev := TAiJev.Create(nil);
  FOwnJev.ApiKey := FApiKey;
  FOwnJev.Model := FModel;
  FOwnJev.Url := JevUrlOrDefault(FUrl);
  Result := FOwnJev;
end;

function TAiJevModelRouter.Route(const APrompt: string): TAiModelRoute;
var
  Q: TAiJevQuestions;
  State: TJSONObject;
  R: TAiJevResult;
  Tier: TAiJevModelTier;
  Reasons: TStringList;
begin
  if FTiers.Count = 0 then
    raise EAiJevError.Create('JevModelRouter: no Tiers defined');

  Q := TAiJevQuestions.Create(nil);
  Reasons := TStringList.Create;
  try
    // Same questions as the calibrated prototype (router.py)
    Q.AddChoice('tarea', 'What type of task does `pregunta` ask?', [
      'conversacion=Greeting, chat or general knowledge question with short answer',
      'redaccion=Write, summarize, translate or correct a text',
      'codigo=Write, debug, review or explain programming code',
      'analisis=Reason in several steps, compare options, plan or decide',
      'matematicas=Solve calculations, numerical problems or proofs',
      'datos=Extract, classify or transform structured data']);
    Q.AddScore('dificultad', 'How difficult is it to answer `pregunta` well?', [
      'Trivial: the answer is a fact or a phrase',
      'Standard: a professional answers without research',
      'Demanding: requires several reasoning steps or long context',
      'Expert: complex design, edge cases or high cost of being wrong']);
    Q.AddNoul('sensible', 'Does `pregunta` involve legal, medical, tax or financial decisions ' +
      'where a mistake would have real consequences?');

    State := TJSONObject.Create;
    try
      State.AddPair('pregunta', APrompt);
      R := ActiveJev.Ask(State, Q);
    finally
      State.Free;
    end;
    try
      JevReportResult(Self, R, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput, FOnUsage);
      Result.Task := R['tarea'].Choice;
      Result.TaskConfidence := R['tarea'].Confidence;
      Result.Difficulty := R['dificultad'].Score;
      Result.DifficultyConfidence := R['dificultad'].Confidence;
      Result.Sensitive := R['sensible'].Noul;
    finally
      R.Free;
    end;

    // Code rules (same as prototype), with reason for each adjustment
    Result.Level := EnsureRange(Round(Result.Difficulty), 0, 3);
    Reasons.Add('difficulty ' + Inv(Result.Difficulty));
    if FBumpOnDoubt and (Result.DifficultyConfidence < 0.5) then
    begin
      Inc(Result.Level);
      Reasons.Add('doubt ' + Inv(Result.DifficultyConfidence) + ' +1');
    end;
    if ((Result.Task = 'codigo') or (Result.Task = 'analisis') or (Result.Task = 'matematicas')) and
       (Result.Level < FCodeMinLevel) then
    begin
      Result.Level := FCodeMinLevel;
      Reasons.Add(Result.Task + ' >= ' + IntToStr(FCodeMinLevel));
    end;
    if (Result.Sensitive > FSensitiveThreshold) and (Result.Level < FSensitiveMinLevel) then
    begin
      Result.Level := FSensitiveMinLevel;
      Reasons.Add('sensitive ' + Inv(Result.Sensitive) + ' >= ' + IntToStr(FSensitiveMinLevel));
    end;
    if Result.TaskConfidence < 0.4 then
    begin
      Result.Level := 3;
      Reasons.Add('task uncertain ' + Inv(Result.TaskConfidence) + ' -> 3');
    end;
    Result.Level := EnsureRange(Result.Level, 0, 3);

    Tier := FTiers.Pick(Result.Level);
    Result.TierName := Tier.Name;
    Result.DriverName := Tier.DriverName;
    Result.Model := Tier.Model;
    Reasons.Delimiter := ',';
    Reasons.StrictDelimiter := True;
    Result.Reason := Reasons.DelimitedText;
  finally
    Reasons.Free;
    Q.Free;
  end;

  if Assigned(FOnRoute) then
    FOnRoute(Self, APrompt, Result);
  FLastRoute := Result;
end;

procedure TAiJevModelRouter.Apply(AConnection: TAiChatConnection; const ARoute: TAiModelRoute);
var
  History: TList<TPair<string, string>>;
  M: TAiChatMessage;
  P: TPair<string, string>;

  procedure ApplyList(AList: TStrings);
  var
    i: Integer;
  begin
    for i := 0 to AList.Count - 1 do
      if AList.Names[i] <> '' then
        AConnection.Params.Values[AList.Names[i]] := AList.ValueFromIndex[i];
  end;

  procedure ApplyParams;
  var
    Tier: TAiJevModelTier;
  begin
    ApplyList(FConnectionParams);
    Tier := FTiers.FindTier(ARoute.TierName);
    if Assigned(Tier) then
      ApplyList(Tier.Params); // model-specific wins over global
  end;

begin
  if not Assigned(AConnection) then
    Exit;

  if SameText(AConnection.DriverName, ARoute.DriverName) then
  begin
    // Same provider: changing the model preserves the chat and its history
    if AConnection.Model <> ARoute.Model then
      AConnection.Model := ARoute.Model;
    ApplyParams;
    Exit;
  end;

  History := TList<TPair<string, string>>.Create;
  try
    // Changing provider recreates the chat: save text messages first
    if FMigrateHistory and Assigned(AConnection.Messages) then
      for M in AConnection.Messages do
        if ((M.Role = 'user') or (M.Role = 'assistant')) and (M.Prompt <> '') and (M.Tool_calls = '') then
          History.Add(TPair<string, string>.Create(M.Role, M.Prompt));

    AConnection.DriverName := ARoute.DriverName;
    AConnection.Model := ARoute.Model;
    // After model: assigning Model reloads its defaults (e.g. Max_Tokens)
    ApplyParams;

    for P in History do
      AConnection.AddMessage(P.Value, P.Key);
  finally
    History.Free;
  end;
end;

function TAiJevModelRouter.Ask(AConnection: TAiChatConnection; const APrompt: string): string;
begin
  Apply(AConnection, Route(APrompt));
  Result := AConnection.AddMessageAndRun(APrompt, 'user', []);
end;

function TAiJevModelRouter.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJevModelRouter.ResetUsage;
begin
  FUsage.Reset;
end;

end.
