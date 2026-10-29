// MIT License
//
// MakerAI - Jev: calibrated judge for TAiEvalRunner with the Jev model (TypeSafe AI)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Jev.Evals;

// -----------------------------------------------------------------------------
// TAiJevEvalScorer: assign to TAiEvalRunner.Scorer and it answers the
// ExpectScore('criterion', min) checks with the calibrated probability that the
// output meets the criterion. Compared to ExpectJudge (an LLM that says PASS/FAIL)
// it is faster and cheaper, and the minimum is adjusted in code.
//
//   Runner.Scorer := JevScorer;          // this component
//   Runner.AddCase('courtesy')
//     .Input('My invoice is wrong')
//     .ExpectScore('Polite and professional', 0.7);
//
// A Noul question about {input, response}: "Does `response` satisfy this
// criterion: <criterion>?". A Jev error propagates and the runner marks the
// check as failed with the reason.
//
// Calibrated against jev-1.13.0 (Sep 27/2026) on 10 criterion/response pairs
// in Spanish (language, accounting data present, invented figures, refusing to
// reveal a key, courtesy): those that comply >= 0.97, those that do not <= 0.02.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uMakerAi.Evals, uMakerAi.Jev;

type
  TAiJevEvalScorer = class(TAiEvalScorerBase)
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
    FLastScore: Double;
    procedure SetJev(const Value: TAiJev);
    function ActiveJev: TAiJev;
    function GetUsage: TAiJevUsage;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev usage accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
    function Score(const ACriteria, AInput, AActual: string): Double; override;
    // Probability of the last evaluated check (-1 if none evaluated yet)
    property LastScore: Double read FLastScore;
  published
    // Optional: external TAiJev (shared or test double); if assigned,
    // this component's ApiKey and Model are ignored
    property Jev: TAiJev read FJev write SetJev;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    // System One server: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;
    // Prices for CostUSD of Usage/OnUsage (US$ per million tokens; currently
    // output is not charged)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with that operation's usage. Synchronous, on the thread
    // that executed it (on a server: the request thread, to bill the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJevEvalScorer]);
end;

{ TAiJevEvalScorer }

constructor TAiJevEvalScorer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FLastScore := -1;
end;

destructor TAiJevEvalScorer.Destroy;
begin
  FOwnJev.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevEvalScorer.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevEvalScorer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevEvalScorer.ActiveJev: TAiJev;
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

function TAiJevEvalScorer.Score(const ACriteria, AInput, AActual: string): Double;
var
  Q: TAiJevQuestions;
  State: TJSONObject;
  R: TAiJevResult;
begin
  Q := TAiJevQuestions.Create(nil);
  try
    // Calibrated wording (10/10): the criterion goes in the question, not in the state
    Q.AddNoul('pass', 'Does `response` satisfy this criterion: ' + ACriteria + '?');
    State := TJSONObject.Create;
    try
      if AInput <> '' then
        State.AddPair('input', AInput);
      State.AddPair('response', AActual);
      R := ActiveJev.Ask(State, Q);
    finally
      State.Free;
    end;
    try
      JevReportResult(Self, R, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput, FOnUsage);
      Result := R['pass'].Noul;
    finally
      R.Free;
    end;
  finally
    Q.Free;
  end;
  FLastScore := Result;
end;

function TAiJevEvalScorer.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJevEvalScorer.ResetUsage;
begin
  FUsage.Reset;
end;

end.
