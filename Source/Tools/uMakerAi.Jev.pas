// MIT License
//
// MakerAI - Jev: typed questions for the Jev model from TypeSafe AI (System One)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Jev;

// -----------------------------------------------------------------------------
// TAiJev: client for the Jev model (TypeSafe AI, https://docs.typesafe.ai).
//
// Jev is NOT a chat LLM: it does not generate text. It receives a "state" (text or JSON)
// and a map of typed questions, and returns for each one probabilities
// calibrated and a confidence. It is for fast, cheap decisions that today
// are asked of a full LLM: routing a query to the correct agent,
// classifying, filtering relevance, approving or not an action.
//
// Three question types:
//   jqChoice  selects an option from a set (max. 255). Criteria: one line
//             per option, 'key=description' (description is optional).
//   jqScore   scores against ordered levels (2 to 10). Criteria: one line
//             per level, from lowest to highest.
//   jqNoul    yes/no; returns the probability of "yes". Optional Criteria:
//             'true=...' and 'false=...'.
//
// Multiple questions travel in ONE single call (the state is charged once):
// prefer a TAiJevQuestions with everything that needs to be decided over individual
// calls.
//
// What the model does NOT do well (docs: model-jaggedness): arithmetic, counting,
// comparing dates and generating text. That goes in code; give Jev only judgment.
//
// Thresholds: confidence for the same input varies a few points between calls.
// Set Model to a concrete version (default 'jev-1.13.0', not
// 'jev-latest') before calibrating thresholds, and leave margin.
//
// DoPost is virtual: the regression suite replaces it to test without network.
//
// Other System One servers (Oct 2026): Ollama 0.35+ exposes the same
// contract at http://localhost:11434/v1/systemone with decision models
// local (nimble, tev1, clef, clef-flash). Just set Url + Model:
//   Jev.Url := 'http://localhost:11434/v1/'; Jev.Model := 'nimble';
// Differences: Choice and Score allow 2 to 26 options (the server rejects
// more with HTTP 400), requests up to 64 KiB, no API key. Clef and Clef Flash
// (Ollama 0.35.1+) read IMAGES: Ask(State, [Image1, ...], Questions).
// The default price (JEV_PRICE_PER_MILLION_INPUT) is charged only when
// Url points to TypeSafe; a manually set price is always respected.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.SyncObjs,
  uMakerAi.Core;

type
  EAiJevError = class(Exception)
  private
    FStatusCode: Integer;
  public
    constructor Create(const AMsg: string; AStatusCode: Integer = 0);
    // HTTP code of the response; 0 if the error is local (validation, parsing)
    property StatusCode: Integer read FStatusCode;
  end;

  TAiJevQuestionKind = (jqChoice, jqScore, jqNoul);

  TAiJevQuestion = class(TCollectionItem)
  private
    FName: string;
    FKind: TAiJevQuestionKind;
    FInstructions: string;
    FCriteria: TStrings;
    procedure SetCriteria(const Value: TStrings);
    function CriteriaLines: TArray<string>;
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    // Raises EAiJevError if the question does not meet the API rules
    procedure Validate;
    function ToJSON: TJSONObject;
  published
    // Question id: the answer comes back under this same name
    property Name: string read FName write FName;
    property Kind: TAiJevQuestionKind read FKind write FKind default jqChoice;
    // The question. It can refer to state fields between backticks: `consulta`
    property Instructions: string read FInstructions write FInstructions;
    property Criteria: TStrings read FCriteria write SetCriteria;
  end;

  TAiJevQuestions = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TAiJevQuestion;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TAiJevQuestion;
    // AOptions: 'key' or 'key=description'
    function AddChoice(const AName, AInstructions: string; const AOptions: array of string): TAiJevQuestion;
    // ALevels: from lowest to highest
    function AddScore(const AName, AInstructions: string; const ALevels: array of string): TAiJevQuestion;
    function AddNoul(const AName, AInstructions: string; const AWhenTrue: string = '';
      const AWhenFalse: string = ''): TAiJevQuestion;
    function Find(const AName: string): TAiJevQuestion;
    procedure Validate;
    property Items[Index: Integer]: TAiJevQuestion read GetItem; default;
  end;

  TAiJevAnswer = class
  private
    FName: string;
    FKind: TAiJevQuestionKind;
    FChoice: string;
    FScore: Double;
    FNoul: Double;
    FConfidence: Double;
    FProbabilities: TDictionary<string, Double>;
  public
    constructor Create;
    destructor Destroy; override;
    // Probability of an option (Choice) or level (Score, key '0','1',...); 0 if it does not exist
    function Probability(const AOption: string): Double;
    // Options sorted from highest to lowest probability
    function Ranked: TArray<TPair<string, Double>>;
    // The ACount most probable options (suggestions for human review)
    function Top(ACount: Integer): TArray<string>;

    property Name: string read FName;
    property Kind: TAiJevQuestionKind read FKind;
    // jqChoice: option with highest probability
    property Choice: string read FChoice;
    // jqScore: expected value between levels (0 = first level); it can fall between two
    property Score: Double read FScore;
    // jqNoul: probability of "yes" (0..1)
    property Noul: Double read FNoul;
    // jqChoice / jqScore: certainty derived from the distribution (0..1). The API does not provide it for Noul.
    property Confidence: Double read FConfidence;
    property Probabilities: TDictionary<string, Double> read FProbabilities;
  end;

  TAiJevResult = class
  private
    FModel: string;
    FInputTokens: Integer;
    FOutputTokens: Integer;
    FAnswers: TObjectDictionary<string, TAiJevAnswer>;
    function GetAnswer(const AName: string): TAiJevAnswer;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // Parses the response body from /v1/systemone
    class function FromJSON(const AJson: string): TAiJevResult;
    function TryGetAnswer(const AName: string; out AAnswer: TAiJevAnswer): Boolean;
    // Raises EAiJevError if there is no answer with that name
    property Answers[const AName: string]: TAiJevAnswer read GetAnswer; default;
    property Count: Integer read GetCount;
    // Concrete version that responded (e.g. 'jev-1.13.0' even if an alias was requested)
    property Model: string read FModel;
    property InputTokens: Integer read FInputTokens;
    property OutputTokens: Integer read FOutputTokens;
  end;

  // Jev usage: requests, tokens, and cost. Current price (Sep 2026):
  // US$0.042 per million input tokens; output is not charged.
  TAiJevUsage = record
    Requests: Int64;
    InputTokens: Int64;
    OutputTokens: Int64;
    CostUSD: Double;
  end;

  // Fires SYNCHRONOUSLY on the thread that executed the operation (not via TThread.Queue):
  // on a server that is the request thread, so the integrator knows which
  // client to charge the usage to.
  TAiJevUsageEvent = procedure(Sender: TObject; const AUsage: TAiJevUsage) of object;

  // Thread-safe accumulator (adapters call Jev in parallel)
  TAiJevUsageMeter = class
  private
    FRequests, FInputTokens, FOutputTokens: Int64;
  public
    procedure Add(AResult: TAiJevResult); overload;
    procedure Add(const AUsage: TAiJevUsage); overload;
    procedure Reset;
    // Totals with cost calculated at the given prices (US$ per million)
    function Snapshot(APricePerMillionInput, APricePerMillionOutput: Double): TAiJevUsage;
  end;

  TAiJev = class(TComponent)
  private
    FUsage: TAiJevUsageMeter;
    FPricePerMillionInput: Double;
    FPricePerMillionOutput: Double;
    FOnUsage: TAiJevUsageEvent;
    function GetUsage: TAiJevUsage;
  private
    FApiKey: string;
    FModel: string;
    FUrl: string;
    FQuestions: TAiJevQuestions;
    FMaxRetries: Integer;
    FRetryDelay: Integer;
    FTimeout: Integer;
    FLastError: string;
    FOnError: TAiErrorEvent;
    function GetApiKey: string;
    procedure SetQuestions(const Value: TAiJevQuestions);
  protected
    // Sends the body and returns the HTTP status. Virtual to replace the network in tests.
    function DoPost(const ABody: string; out AResponse: string): Integer; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // JSON request body (validates the questions and images). The
    // caller frees the result.
    function BuildRequest(AState: TJSONValue; AQuestions: TAiJevQuestions): TJSONObject; overload;
    function BuildRequest(AState: TJSONValue; AQuestions: TAiJevQuestions;
      const AImages: array of TAiMediaFile): TJSONObject; overload;

    // AQuestions = nil uses the Questions property. The caller frees the result.
    // Raises EAiJevError if the API responds with an error (after OnError and LastError).
    function Ask(const AState: string; AQuestions: TAiJevQuestions = nil): TAiJevResult; overload;
    // Structured state (JSON object or array). It does not take ownership of AState.
    function Ask(AState: TJSONValue; AQuestions: TAiJevQuestions = nil): TAiJevResult; overload;
    // With images (PNG, JPEG, or WebP, shared by all questions and
    // judged together with the state). Only models that read images, such as Clef
    // in Ollama 0.35.1+. It does not take ownership of the images.
    function Ask(const AState: string; const AImages: array of TAiMediaFile;
      AQuestions: TAiJevQuestions = nil): TAiJevResult; overload;
    function Ask(AState: TJSONValue; const AImages: array of TAiMediaFile;
      AQuestions: TAiJevQuestions = nil): TAiJevResult; overload;

    // Shortcuts for a single question
    function Choose(const AState, AInstructions: string; const AOptions: array of string;
      out AConfidence: Double): string;
    function Noul(const AState, AInstructions: string): Double;

    property LastError: string read FLastError;
    // Accumulated usage for this component since it was created or since ResetUsage
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
  published
    // Prices for CostUSD (US$ per million tokens)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per successful API call, with the usage for that call
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
    // '@TYPESAFE_API_KEY' is resolved from the environment variable
    property ApiKey: string read GetApiKey write FApiKey;
    property Model: string read FModel write FModel;
    property Url: string read FUrl write FUrl;
    // Questions defined at design time (used when Ask receives AQuestions = nil)
    property Questions: TAiJevQuestions read FQuestions write SetQuestions;
    // Retries on 429 / 503 / 529, with exponential wait from RetryDelay (ms)
    property MaxRetries: Integer read FMaxRetries write FMaxRetries default 2;
    property RetryDelay: Integer read FRetryDelay write FRetryDelay default 500;
    // Connection and response timeout (ms)
    property Timeout: Integer read FTimeout write FTimeout default 30000;
    property OnError: TAiErrorEvent read FOnError write FOnError;
  end;

const
  JEV_PRICE_PER_MILLION_INPUT = 0.042;
  JEV_DEFAULT_URL = 'https://api.typesafe.ai/v1/';

// True if Url is TypeSafe's ('' = the TypeSafe default)
function JevIsTypeSafeUrl(const AUrl: string): Boolean;
// '' -> JEV_DEFAULT_URL
function JevUrlOrDefault(const AUrl: string): string;
// Effective input price: the TypeSafe default price is not charged on
// other servers (local Ollama, etc.); a manually set price is respected.
function JevEffectiveInputPrice(const AUrl: string; APrice: Double): Double;
// Same for an adapter: the Url that counts is the one of the Jev it actually uses
// (the external one if assigned, otherwise the adapter's own).
function JevAdapterInputPrice(AExternalJev: TAiJev; const AUrl: string; APrice: Double): Double;

// Closes an adapter operation: adds its usage to the adapter total
// and fires OnUsage (synchronous, on the caller thread) if there were requests.
procedure JevReportOperation(ASender: TObject; AOperation, ATotal: TAiJevUsageMeter;
  APricePerMillionInput, APricePerMillionOutput: Double; AEvent: TAiJevUsageEvent);

// Same for a single-call operation: adds AResult to the adapter total
// and fires OnUsage with the usage for that call.
procedure JevReportResult(ASender: TObject; AResult: TAiJevResult; ATotal: TAiJevUsageMeter;
  APricePerMillionInput, APricePerMillionOutput: Double; AEvent: TAiJevUsageEvent);

procedure Register;

implementation

uses
  System.Math, System.Generics.Defaults, System.Net.HttpClient,
  System.Net.HttpClientComponent, System.Net.URLClient, System.NetEncoding,
  uMakerAi.Telemetry;

function JevIsTypeSafeUrl(const AUrl: string): Boolean;
begin
  Result := (Trim(AUrl) = '') or (Pos('typesafe.ai', LowerCase(AUrl)) > 0);
end;

function JevUrlOrDefault(const AUrl: string): string;
begin
  if Trim(AUrl) = '' then
    Result := JEV_DEFAULT_URL
  else
    Result := AUrl;
end;

function JevEffectiveInputPrice(const AUrl: string; APrice: Double): Double;
begin
  if SameValue(APrice, JEV_PRICE_PER_MILLION_INPUT) and not JevIsTypeSafeUrl(AUrl) then
    Result := 0
  else
    Result := APrice;
end;

function JevAdapterInputPrice(AExternalJev: TAiJev; const AUrl: string; APrice: Double): Double;
begin
  if Assigned(AExternalJev) then
    Result := JevEffectiveInputPrice(AExternalJev.Url, APrice)
  else
    Result := JevEffectiveInputPrice(JevUrlOrDefault(AUrl), APrice);
end;

// Actual image format from its leading bytes: 'png', 'jpeg', 'webp', or ''
function JevImageKind(const AData: TBytes): string;
begin
  Result := '';
  if (Length(AData) >= 8) and (AData[0] = $89) and (AData[1] = $50) and
     (AData[2] = $4E) and (AData[3] = $47) then
    Result := 'png'
  else if (Length(AData) >= 3) and (AData[0] = $FF) and (AData[1] = $D8) and (AData[2] = $FF) then
    Result := 'jpeg'
  else if (Length(AData) >= 12) and (AData[0] = Ord('R')) and (AData[1] = Ord('I')) and
     (AData[2] = Ord('F')) and (AData[3] = Ord('F')) and (AData[8] = Ord('W')) and
     (AData[9] = Ord('E')) and (AData[10] = Ord('B')) and (AData[11] = Ord('P')) then
    Result := 'webp';
end;

const
  JEV_MAX_CHOICE_OPTIONS = 255;
  JEV_MIN_SCORE_LEVELS = 2;
  JEV_MAX_SCORE_LEVELS = 10;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJev]);
end;

{ TAiJevUsageMeter }

procedure TAiJevUsageMeter.Add(AResult: TAiJevResult);
begin
  if AResult = nil then Exit;
  TInterlocked.Increment(FRequests);
  TInterlocked.Add(FInputTokens, Int64(AResult.InputTokens));
  TInterlocked.Add(FOutputTokens, Int64(AResult.OutputTokens));
end;

procedure TAiJevUsageMeter.Add(const AUsage: TAiJevUsage);
begin
  TInterlocked.Add(FRequests, AUsage.Requests);
  TInterlocked.Add(FInputTokens, AUsage.InputTokens);
  TInterlocked.Add(FOutputTokens, AUsage.OutputTokens);
end;

procedure TAiJevUsageMeter.Reset;
begin
  TInterlocked.Exchange(FRequests, 0);
  TInterlocked.Exchange(FInputTokens, 0);
  TInterlocked.Exchange(FOutputTokens, 0);
end;

function TAiJevUsageMeter.Snapshot(APricePerMillionInput, APricePerMillionOutput: Double): TAiJevUsage;
begin
  Result.Requests := TInterlocked.Read(FRequests);
  Result.InputTokens := TInterlocked.Read(FInputTokens);
  Result.OutputTokens := TInterlocked.Read(FOutputTokens);
  Result.CostUSD := (Result.InputTokens * APricePerMillionInput +
    Result.OutputTokens * APricePerMillionOutput) / 1E6;
end;

procedure JevReportResult(ASender: TObject; AResult: TAiJevResult; ATotal: TAiJevUsageMeter;
  APricePerMillionInput, APricePerMillionOutput: Double; AEvent: TAiJevUsageEvent);
var
  Op: TAiJevUsageMeter;
begin
  Op := TAiJevUsageMeter.Create;
  try
    Op.Add(AResult);
    JevReportOperation(ASender, Op, ATotal, APricePerMillionInput, APricePerMillionOutput, AEvent);
  finally
    Op.Free;
  end;
end;

procedure JevReportOperation(ASender: TObject; AOperation, ATotal: TAiJevUsageMeter;
  APricePerMillionInput, APricePerMillionOutput: Double; AEvent: TAiJevUsageEvent);
var
  U: TAiJevUsage;
begin
  U := AOperation.Snapshot(APricePerMillionInput, APricePerMillionOutput);
  if U.Requests = 0 then
    Exit;
  ATotal.Add(U);
  if Assigned(AEvent) then
    AEvent(ASender, U);
end;

// 'key=description' -> key, description. Without '=' the description is empty.
procedure SplitOption(const ALine: string; out AKey, ADesc: string);
var
  P: Integer;
begin
  P := Pos('=', ALine);
  if P > 0 then
  begin
    AKey := Trim(Copy(ALine, 1, P - 1));
    ADesc := Trim(Copy(ALine, P + 1, MaxInt));
  end
  else
  begin
    AKey := Trim(ALine);
    ADesc := '';
  end;
end;

function KindName(AKind: TAiJevQuestionKind): string;
begin
  case AKind of
    jqChoice: Result := 'choice';
    jqScore: Result := 'score';
  else
    Result := 'noul';
  end;
end;

{ EAiJevError }

constructor EAiJevError.Create(const AMsg: string; AStatusCode: Integer);
begin
  inherited Create(AMsg);
  FStatusCode := AStatusCode;
end;

{ TAiJevQuestion }

constructor TAiJevQuestion.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FKind := jqChoice;
  FCriteria := TStringList.Create;
end;

destructor TAiJevQuestion.Destroy;
begin
  FCriteria.Free;
  inherited;
end;

procedure TAiJevQuestion.Assign(Source: TPersistent);
begin
  if Source is TAiJevQuestion then
  begin
    FName := TAiJevQuestion(Source).FName;
    FKind := TAiJevQuestion(Source).FKind;
    FInstructions := TAiJevQuestion(Source).FInstructions;
    FCriteria.Assign(TAiJevQuestion(Source).FCriteria);
  end
  else
    inherited;
end;

function TAiJevQuestion.GetDisplayName: string;
begin
  if FName <> '' then
    Result := FName + ' (' + KindName(FKind) + ')'
  else
    Result := inherited GetDisplayName;
end;

procedure TAiJevQuestion.SetCriteria(const Value: TStrings);
begin
  FCriteria.Assign(Value);
end;

function TAiJevQuestion.CriteriaLines: TArray<string>;
var
  i: Integer;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    for i := 0 to FCriteria.Count - 1 do
      if Trim(FCriteria[i]) <> '' then
        L.Add(Trim(FCriteria[i]));
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TAiJevQuestion.Validate;
var
  Lines: TArray<string>;
  Line, Key, Desc: string;
  Seen: TDictionary<string, Boolean>;
begin
  if Trim(FName) = '' then
    raise EAiJevError.Create('Jev: a question has no Name');
  if Trim(FInstructions) = '' then
    raise EAiJevError.CreateFmt('Jev: question "%s" has no Instructions', [FName]);

  Lines := CriteriaLines;
  case FKind of
    jqChoice:
      begin
        if (Length(Lines) < 2) or (Length(Lines) > JEV_MAX_CHOICE_OPTIONS) then
          raise EAiJevError.CreateFmt('Jev: question "%s" has %d options; a Choice allows 2 to %d',
            [FName, Length(Lines), JEV_MAX_CHOICE_OPTIONS]);
        Seen := TDictionary<string, Boolean>.Create;
        try
          for Line in Lines do
          begin
            SplitOption(Line, Key, Desc);
            if Key = '' then
              raise EAiJevError.CreateFmt('Jev: question "%s" has an option with no key: "%s"', [FName, Line]);
            if Seen.ContainsKey(Key) then
              raise EAiJevError.CreateFmt('Jev: question "%s" repeats option "%s"', [FName, Key]);
            Seen.Add(Key, True);
          end;
        finally
          Seen.Free;
        end;
      end;
    jqScore:
      if (Length(Lines) < JEV_MIN_SCORE_LEVELS) or (Length(Lines) > JEV_MAX_SCORE_LEVELS) then
        raise EAiJevError.CreateFmt('Jev: question "%s" has %d levels; a Score allows %d to %d',
          [FName, Length(Lines), JEV_MIN_SCORE_LEVELS, JEV_MAX_SCORE_LEVELS]);
    jqNoul:
      ; // optional criteria
  end;
end;

function TAiJevQuestion.ToJSON: TJSONObject;
var
  Crit: TJSONObject;
  Arr: TJSONArray;
  Line, Key, Desc, WhenTrue, WhenFalse: string;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('type', KindName(FKind));
    Result.AddPair('instructions', FInstructions);
    case FKind of
      jqChoice:
        begin
          Crit := TJSONObject.Create;
          Result.AddPair('criteria', Crit);
          for Line in CriteriaLines do
          begin
            SplitOption(Line, Key, Desc);
            if Desc = '' then
              Crit.AddPair(Key, TJSONNull.Create)
            else
              Crit.AddPair(Key, Desc);
          end;
        end;
      jqScore:
        begin
          Arr := TJSONArray.Create;
          Result.AddPair('criteria', Arr);
          for Line in CriteriaLines do
            Arr.Add(Line);
        end;
      jqNoul:
        begin
          WhenTrue := '';
          WhenFalse := '';
          for Line in CriteriaLines do
          begin
            SplitOption(Line, Key, Desc);
            if SameText(Key, 'true') then
              WhenTrue := Desc
            else if SameText(Key, 'false') then
              WhenFalse := Desc;
          end;
          if (WhenTrue <> '') or (WhenFalse <> '') then
          begin
            Crit := TJSONObject.Create;
            Result.AddPair('criteria', Crit);
            if WhenTrue <> '' then
              Crit.AddPair('true', WhenTrue);
            if WhenFalse <> '' then
              Crit.AddPair('false', WhenFalse);
          end;
        end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TAiJevQuestions }

constructor TAiJevQuestions.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TAiJevQuestion);
end;

function TAiJevQuestions.GetItem(Index: Integer): TAiJevQuestion;
begin
  Result := TAiJevQuestion(inherited GetItem(Index));
end;

function TAiJevQuestions.Add: TAiJevQuestion;
begin
  Result := TAiJevQuestion(inherited Add);
end;

function TAiJevQuestions.AddChoice(const AName, AInstructions: string;
  const AOptions: array of string): TAiJevQuestion;
var
  S: string;
begin
  Result := Add;
  Result.Name := AName;
  Result.Kind := jqChoice;
  Result.Instructions := AInstructions;
  for S in AOptions do
    Result.Criteria.Add(S);
end;

function TAiJevQuestions.AddScore(const AName, AInstructions: string;
  const ALevels: array of string): TAiJevQuestion;
var
  S: string;
begin
  Result := Add;
  Result.Name := AName;
  Result.Kind := jqScore;
  Result.Instructions := AInstructions;
  for S in ALevels do
    Result.Criteria.Add(S);
end;

function TAiJevQuestions.AddNoul(const AName, AInstructions, AWhenTrue,
  AWhenFalse: string): TAiJevQuestion;
begin
  Result := Add;
  Result.Name := AName;
  Result.Kind := jqNoul;
  Result.Instructions := AInstructions;
  if AWhenTrue <> '' then
    Result.Criteria.Add('true=' + AWhenTrue);
  if AWhenFalse <> '' then
    Result.Criteria.Add('false=' + AWhenFalse);
end;

function TAiJevQuestions.Find(const AName: string): TAiJevQuestion;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if SameText(Items[i].Name, AName) then
      Exit(Items[i]);
  Result := nil;
end;

procedure TAiJevQuestions.Validate;
var
  i: Integer;
  Seen: TDictionary<string, Boolean>;
begin
  if Count = 0 then
    raise EAiJevError.Create('Jev: there are no questions');
  Seen := TDictionary<string, Boolean>.Create;
  try
    for i := 0 to Count - 1 do
    begin
      Items[i].Validate;
      if Seen.ContainsKey(Items[i].Name) then
        raise EAiJevError.CreateFmt('Jev: question name "%s" is repeated', [Items[i].Name]);
      Seen.Add(Items[i].Name, True);
    end;
  finally
    Seen.Free;
  end;
end;

{ TAiJevAnswer }

constructor TAiJevAnswer.Create;
begin
  inherited Create;
  FProbabilities := TDictionary<string, Double>.Create;
end;

destructor TAiJevAnswer.Destroy;
begin
  FProbabilities.Free;
  inherited;
end;

function TAiJevAnswer.Probability(const AOption: string): Double;
begin
  if not FProbabilities.TryGetValue(AOption, Result) then
    Result := 0;
end;

function TAiJevAnswer.Ranked: TArray<TPair<string, Double>>;
begin
  Result := FProbabilities.ToArray;
  TArray.Sort<TPair<string, Double>>(Result, TComparer<TPair<string, Double>>.Construct(
    function(const L, R: TPair<string, Double>): Integer
    begin
      Result := CompareValue(R.Value, L.Value);
      if Result = 0 then
        Result := CompareStr(L.Key, R.Key); // orden estable ante empates
    end));
end;

function TAiJevAnswer.Top(ACount: Integer): TArray<string>;
var
  R: TArray<TPair<string, Double>>;
  i: Integer;
begin
  R := Ranked;
  SetLength(Result, Min(Max(ACount, 0), Length(R)));
  for i := 0 to High(Result) do
    Result[i] := R[i].Key;
end;

{ TAiJevResult }

constructor TAiJevResult.Create;
begin
  inherited Create;
  FAnswers := TObjectDictionary<string, TAiJevAnswer>.Create([doOwnsValues]);
end;

destructor TAiJevResult.Destroy;
begin
  FAnswers.Free;
  inherited;
end;

function TAiJevResult.GetAnswer(const AName: string): TAiJevAnswer;
begin
  if not FAnswers.TryGetValue(AName, Result) then
    raise EAiJevError.CreateFmt('Jev: no answer for question "%s"', [AName]);
end;

function TAiJevResult.GetCount: Integer;
begin
  Result := FAnswers.Count;
end;

function TAiJevResult.TryGetAnswer(const AName: string; out AAnswer: TAiJevAnswer): Boolean;
begin
  Result := FAnswers.TryGetValue(AName, AAnswer);
end;

class function TAiJevResult.FromJSON(const AJson: string): TAiJevResult;
var
  Root: TJSONValue;
  Obj, Usage, Answers, A, Probs: TJSONObject;
  Pair, PP: TJSONPair;
  Ans: TAiJevAnswer;
  Kind: string;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      raise EAiJevError.Create('Jev: the response is not a JSON object');
    Obj := TJSONObject(Root);
    if not Obj.TryGetValue<TJSONObject>('answers', Answers) then
      raise EAiJevError.Create('Jev: the response does not include "answers"');

    Result := TAiJevResult.Create;
    try
      Obj.TryGetValue<string>('model', Result.FModel);
      if Obj.TryGetValue<TJSONObject>('usage', Usage) then
      begin
        Usage.TryGetValue<Integer>('input_tokens', Result.FInputTokens);
        Usage.TryGetValue<Integer>('output_tokens', Result.FOutputTokens);
      end;

      for Pair in Answers do
      begin
        if not (Pair.JsonValue is TJSONObject) then
          Continue;
        A := TJSONObject(Pair.JsonValue);
        Ans := TAiJevAnswer.Create;
        Ans.FName := Pair.JsonString.Value;
        Result.FAnswers.AddOrSetValue(Ans.FName, Ans);

        Kind := '';
        A.TryGetValue<string>('type', Kind);
        if Kind = 'choice' then
        begin
          Ans.FKind := jqChoice;
          A.TryGetValue<string>('choice', Ans.FChoice);
        end
        else if Kind = 'score' then
        begin
          Ans.FKind := jqScore;
          A.TryGetValue<Double>('score', Ans.FScore);
        end
        else if Kind = 'noul' then
        begin
          Ans.FKind := jqNoul;
          A.TryGetValue<Double>('noul', Ans.FNoul);
        end
        else
          raise EAiJevError.CreateFmt('Jev: unknown response type "%s" in "%s"', [Kind, Ans.FName]);

        A.TryGetValue<Double>('confidence', Ans.FConfidence);
        if A.TryGetValue<TJSONObject>('probabilities', Probs) then
          for PP in Probs do
            if PP.JsonValue is TJSONNumber then
              Ans.FProbabilities.AddOrSetValue(PP.JsonString.Value, TJSONNumber(PP.JsonValue).AsDouble);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Root.Free;
  end;
end;

{ TAiJev }

constructor TAiJev.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FUrl := JEV_DEFAULT_URL;
  FQuestions := TAiJevQuestions.Create(Self);
  FMaxRetries := 2;
  FRetryDelay := 500;
  FTimeout := 30000;
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
end;

destructor TAiJev.Destroy;
begin
  FQuestions.Free;
  FUsage.Free;
  inherited;
end;

function TAiJev.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevEffectiveInputPrice(FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJev.ResetUsage;
begin
  FUsage.Reset;
end;

function TAiJev.GetApiKey: string;
begin
  if (csDesigning in ComponentState) then
    Exit(FApiKey);
  if FApiKey.StartsWith('@') then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, MaxInt))
  else
    Result := FApiKey;
end;

procedure TAiJev.SetQuestions(const Value: TAiJevQuestions);
begin
  FQuestions.Assign(Value);
end;

function TAiJev.BuildRequest(AState: TJSONValue; AQuestions: TAiJevQuestions): TJSONObject;
begin
  Result := BuildRequest(AState, AQuestions, []);
end;

function TAiJev.BuildRequest(AState: TJSONValue; AQuestions: TAiJevQuestions;
  const AImages: array of TAiMediaFile): TJSONObject;
var
  Qs: TJSONObject;
  Imgs: TJSONArray;
  Encoded: TArray<string>;
  Data: TBytes;
  B64: TBase64Encoding;
  i: Integer;
begin
  if AState = nil then
    raise EAiJevError.Create('Jev: state cannot be nil');
  AQuestions.Validate;

  // Images: raw base64 (no data URL or line breaks), only PNG, JPEG
  // or WebP; validated by the bytes, not by the file extension
  SetLength(Encoded, Length(AImages));
  if Length(AImages) > 0 then
  begin
    B64 := TBase64Encoding.Create(0);
    try
      for i := 0 to High(AImages) do
      begin
        if (AImages[i] = nil) or (AImages[i].Content = nil) or (AImages[i].Content.Size = 0) then
          raise EAiJevError.CreateFmt('Jev: image %d is empty', [i + 1]);
        SetLength(Data, AImages[i].Content.Size);
        AImages[i].Content.Position := 0;
        AImages[i].Content.ReadBuffer(Data[0], Length(Data));
        if JevImageKind(Data) = '' then
          raise EAiJevError.CreateFmt('Jev: image %d ("%s") is not PNG, JPEG, or WebP',
            [i + 1, AImages[i].filename]);
        Encoded[i] := B64.EncodeBytesToString(Data);
      end;
    finally
      B64.Free;
    end;
  end;

  Result := TJSONObject.Create;
  try
    Result.AddPair('model', FModel);
    Result.AddPair('state', TJSONValue(AState.Clone));
    if Length(Encoded) > 0 then
    begin
      Imgs := TJSONArray.Create;
      Result.AddPair('images', Imgs);
      for i := 0 to High(Encoded) do
        Imgs.Add(Encoded[i]);
    end;
    Qs := TJSONObject.Create;
    Result.AddPair('questions', Qs);
    for i := 0 to AQuestions.Count - 1 do
      Qs.AddPair(AQuestions[i].Name, AQuestions[i].ToJSON);
  except
    Result.Free;
    raise;
  end;
end;

function TAiJev.DoPost(const ABody: string; out AResponse: string): Integer;
var
  HTTP: TNetHTTPClient;
  Body: TStringStream;
  Resp: IHTTPResponse;
begin
  HTTP := TNetHTTPClient.Create(nil);
  try
{$IF CompilerVersion >= 34}
    HTTP.SynchronizeEvents := False;
{$IFEND}
    HTTP.ConnectionTimeout := FTimeout;
    HTTP.ResponseTimeout := FTimeout;
    HTTP.ContentType := 'application/json';
    // Explicit UTF-8: with the default encoding the API rejects accents and symbols (400)
    Body := TStringStream.Create(ABody, TEncoding.UTF8);
    try
      Resp := HTTP.Post(FUrl + 'systemone', Body, nil,
        [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)]);
    finally
      Body.Free;
    end;
    AResponse := Resp.ContentAsString(TEncoding.UTF8);
    Result := Resp.StatusCode;
  finally
    HTTP.Free;
  end;
end;

function TAiJev.Ask(const AState: string; AQuestions: TAiJevQuestions): TAiJevResult;
var
  S: TJSONString;
begin
  S := TJSONString.Create(AState);
  try
    Result := Ask(S, AQuestions);
  finally
    S.Free;
  end;
end;

function TAiJev.Ask(const AState: string; const AImages: array of TAiMediaFile;
  AQuestions: TAiJevQuestions): TAiJevResult;
var
  S: TJSONString;
begin
  S := TJSONString.Create(AState);
  try
    Result := Ask(S, AImages, AQuestions);
  finally
    S.Free;
  end;
end;

function TAiJev.Ask(AState: TJSONValue; AQuestions: TAiJevQuestions): TAiJevResult;
begin
  Result := Ask(AState, [], AQuestions);
end;

function TAiJev.Ask(AState: TJSONValue; const AImages: array of TAiMediaFile;
  AQuestions: TAiJevQuestions): TAiJevResult;
var
  Req: TJSONObject;
  Body, Resp: string;
  Status, Attempt: Integer;
  Span: TAiSpan;
begin
  if AQuestions = nil then
    AQuestions := FQuestions;
  FLastError := '';
  Result := nil;

  Span := AiSpanStart('jev.ask', skClient);
  try
    if JevIsTypeSafeUrl(FUrl) then
      AiSpanAttr(Span, 'gen_ai.system', 'typesafe')
    else
      AiSpanAttr(Span, 'gen_ai.system', 'systemone'); // Ollama or another server
    AiSpanAttr(Span, 'gen_ai.request.model', FModel);
    AiSpanAttr(Span, 'jev.questions', Int64(AQuestions.Count));
    AiSpanAttr(Span, 'jev.images', Int64(Length(AImages)));

    Req := BuildRequest(AState, AQuestions, AImages);
    try
      Body := Req.ToJSON;
    finally
      Req.Free;
    end;

    Attempt := 0;
    repeat
      Status := DoPost(Body, Resp);
      // 429 rate limit, 529 overload (docs), 503 unavailable: transient
      if not ((Status = 429) or (Status = 503) or (Status = 529)) or (Attempt >= FMaxRetries) then
        Break;
      Inc(Attempt);
      if FRetryDelay > 0 then
        Sleep(FRetryDelay * (1 shl (Attempt - 1)));
    until False;
    AiSpanAttr(Span, 'http.response.status_code', Int64(Status));
    AiSpanAttr(Span, 'jev.retries', Int64(Attempt));

    if Status <> 200 then
      raise EAiJevError.Create(Format('Jev: HTTP %d: %s', [Status, Resp]), Status);

    Result := TAiJevResult.FromJSON(Resp);
    AiSpanAttr(Span, 'gen_ai.response.model', Result.Model);
    AiSpanAttr(Span, 'gen_ai.usage.input_tokens', Int64(Result.InputTokens));
    AiSpanAttr(Span, 'gen_ai.usage.output_tokens', Int64(Result.OutputTokens));
    AiSpanEnd(Span);
    FUsage.Add(Result);
    if Assigned(FOnUsage) then
    begin
      var U: TAiJevUsage;
      U.Requests := 1;
      U.InputTokens := Result.InputTokens;
      U.OutputTokens := Result.OutputTokens;
      U.CostUSD := (U.InputTokens * JevEffectiveInputPrice(FUrl, FPricePerMillionInput) +
        U.OutputTokens * FPricePerMillionOutput) / 1E6;
      FOnUsage(Self, U);
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      FLastError := E.Message;
      AiSpanEnd(Span, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, E.Message, E, nil);
      raise;
    end;
  end;
end;

function TAiJev.Choose(const AState, AInstructions: string; const AOptions: array of string;
  out AConfidence: Double): string;
var
  Q: TAiJevQuestions;
  R: TAiJevResult;
begin
  Q := TAiJevQuestions.Create(nil);
  try
    Q.AddChoice('q', AInstructions, AOptions);
    R := Ask(AState, Q);
    try
      Result := R['q'].Choice;
      AConfidence := R['q'].Confidence;
    finally
      R.Free;
    end;
  finally
    Q.Free;
  end;
end;

function TAiJev.Noul(const AState, AInstructions: string): Double;
var
  Q: TAiJevQuestions;
  R: TAiJevResult;
begin
  Q := TAiJevQuestions.Create(nil);
  try
    Q.AddNoul('q', AInstructions);
    R := Ask(AState, Q);
    try
      Result := R['q'].Noul;
    finally
      R.Free;
    end;
  finally
    Q.Free;
  end;
end;

end.
