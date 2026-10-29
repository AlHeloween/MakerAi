unit uMakerAi.Jev.Guardrails;

// -----------------------------------------------------------------------------
// TAiJevGuardrailClassifier: assigned to TAiGuardrails.Classifier, it judges
// with Jev every tool call that the lists (AllowedTools, BlockedTools,
// BlockedArgPatterns) let through. Complements the lists: these catch what can
// be enumerated ('rm -rf', 'DROP TABLE'); Jev catches what cannot, such as an
// email to an external party with a password in the body or a transfer to an
// unknown account.
//
//   Guardrails.Classifier := JevGuard;   // this component
//
// Two judgments in ONE call on {tool, description?, arguments}:
//
//   1. Risk (Noul, always): if P(risk) >= BlockThreshold, block. Policy
//      is the question and defines what counts as risk: adjust it to the domain.
//      Empty: without Categories, DEFAULT_POLICY is used (strict: any payment
//      or deletion counts as risk); with Categories, ABUSE_POLICY (only the
//      abusive), because the control by operation type is already done by the
//      categories. With DEFAULT_POLICY a normal pay_invoice gave 0.88.
//   2. Permission category (Choice, optional): if Categories is not empty,
//      classify the call ('read', 'write', 'financial', ...) and block if the
//      probability of any BlockedCategories reaches CategoryThreshold
//      (even if not the most probable: when in doubt between 'write' and
//      'financial', the policy of 'financial' prevails). OnCategorized allows
//      auditing each call and changing the decision.
//
// ToolDescriptions ('name=description') adds a description of the tool to the
// state. It is needed with domain names that Jev reads literally:
// 'anular_comprobante' came out as 'read' (0.83); with "generates the reversal
// receipt" it comes out as 'write' (0.95).
//
// If Jev does not respond (network, 401, ...): BlockOnError = True (default)
// blocks; False lets it through. The block reason remains in AReason and in
// OnBlocked.
//
// Calibrated against jev-1.13.0 (sep 27/2026). Risk, 13 tool calls: safe
// <= 0.17, dangerous >= 0.88. Categories, 20 tool calls in 6 categories:
// 19/20 without descriptions, 20/20 with the description of anular_comprobante.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uMakerAi.Guardrails, uMakerAi.Jev;

type
  // Category audit; AAllow/AReason arrive with the decision already made
  // (risk and blocked categories) and the handler can change them.
  TAiJevToolCategorizedEvent = procedure(Sender: TObject; const AToolName, AArguments,
    ACategory: string; AConfidence: Double; var AAllow: Boolean; var AReason: string) of object;

  TAiJevGuardrailClassifier = class(TAiGuardrailClassifierBase)
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
    FPolicy: string;
    FBlockThreshold: Double;
    FBlockOnError: Boolean;
    FLastRisk: Double;
    FCategories: TStrings;
    FBlockedCategories: TStrings;
    FCategoryThreshold: Double;
    FToolDescriptions: TStrings;
    FLastCategory: string;
    FLastCategoryConfidence: Double;
    FOnCategorized: TAiJevToolCategorizedEvent;
    procedure SetJev(const Value: TAiJev);
    procedure SetCategories(const Value: TStrings);
    procedure SetBlockedCategories(const Value: TStrings);
    procedure SetToolDescriptions(const Value: TStrings);
    function ActiveJev: TAiJev;
    function GetUsage: TAiJevUsage;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public const
    DEFAULT_POLICY =
      'Could executing the tool `tool` with the arguments `arguments` cause harm: deleting or ' +
      'overwriting data, exposing credentials or private information, moving money, or running ' +
      'destructive system commands?';
    // Calibrated on 19 tool calls (13 risk + 6 legitimate business
    // operations): dangerous >= 0.64, legitimate <= 0.35, 0 errors
    ABUSE_POLICY =
      'Does calling the tool `tool` with the arguments `arguments` look abusive or malicious rather ' +
      'than a normal business operation: destroying data in bulk, leaking credentials or private ' +
      'data, sending money to unknown parties, or escalating privileges?';
    CATEGORY_QUESTION = 'Which kind of action does calling `tool` with `arguments` perform?';
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev consumption accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
    function CheckToolCall(const AToolName, AArguments: string; out AReason: string): Boolean; override;
    // Risk probability of the last evaluated tool call (-1 if Jev failed)
    property LastRisk: Double read FLastRisk;
    // Category and confidence of the last tool call ('' if no Categories or Jev failed)
    property LastCategory: string read FLastCategory;
    property LastCategoryConfidence: Double read FLastCategoryConfidence;
  published
    // Optional: external TAiJev (shared or test double); if assigned,
    // ApiKey and Model of this component are ignored
    property Jev: TAiJev read FJev write SetJev;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    // System One server: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;
    // Yes/no question about `tool` and `arguments`; empty = DEFAULT_POLICY, or
    // ABUSE_POLICY if Categories exist
    property Policy: string read FPolicy write FPolicy;
    property BlockThreshold: Double read FBlockThreshold write FBlockThreshold;
    property BlockOnError: Boolean read FBlockOnError write FBlockOnError default True;
    // Permission categories, one per line 'key=description'. Empty = no categorization
    property Categories: TStrings read FCategories write SetCategories;
    // Keys from Categories that are always blocked
    property BlockedCategories: TStrings read FBlockedCategories write SetBlockedCategories;
    property CategoryThreshold: Double read FCategoryThreshold write FCategoryThreshold;
    // Optional: 'tool_name=description' for tools whose name is not enough
    property ToolDescriptions: TStrings read FToolDescriptions write SetToolDescriptions;
    property OnCategorized: TAiJevToolCategorizedEvent read FOnCategorized write FOnCategorized;
    // Prices for CostUSD in Usage/OnUsage (US$ per million tokens; today
    // output is not charged)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with the consumption of that operation. Synchronous, in the thread
    // that executed it (on a server: the request thread, to charge the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJevGuardrailClassifier]);
end;

function Inv(AValue: Double): string;
begin
  Result := FormatFloat('0.00', AValue, TFormatSettings.Invariant);
end;

{ TAiJevGuardrailClassifier }

constructor TAiJevGuardrailClassifier.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FPolicy := '';
  FBlockThreshold := 0.5;
  FBlockOnError := True;
  FLastRisk := -1;
  FCategories := TStringList.Create;
  FBlockedCategories := TStringList.Create;
  FCategoryThreshold := 0.5;
  FToolDescriptions := TStringList.Create;
end;

destructor TAiJevGuardrailClassifier.Destroy;
begin
  FCategories.Free;
  FBlockedCategories.Free;
  FToolDescriptions.Free;
  FOwnJev.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevGuardrailClassifier.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevGuardrailClassifier.SetCategories(const Value: TStrings);
begin
  FCategories.Assign(Value);
end;

procedure TAiJevGuardrailClassifier.SetBlockedCategories(const Value: TStrings);
begin
  FBlockedCategories.Assign(Value);
end;

procedure TAiJevGuardrailClassifier.SetToolDescriptions(const Value: TStrings);
begin
  FToolDescriptions.Assign(Value);
end;

procedure TAiJevGuardrailClassifier.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevGuardrailClassifier.ActiveJev: TAiJev;
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

function TAiJevGuardrailClassifier.CheckToolCall(const AToolName, AArguments: string;
  out AReason: string): Boolean;
var
  Q: TAiJevQuestions;
  QC: TAiJevQuestion;
  State: TJSONObject;
  R: TAiJevResult;
  Instr, Desc, Key: string;
  UseCategories: Boolean;
  i: Integer;
  P, WorstP: Double;
  WorstKey: string;
begin
  Result := True;
  AReason := '';
  FLastRisk := -1;
  FLastCategory := '';
  FLastCategoryConfidence := 0;
  WorstP := -1;
  WorstKey := '';

  UseCategories := FCategories.Count > 0;
  Instr := FPolicy;
  if Trim(Instr) = '' then
    if UseCategories then
      Instr := ABUSE_POLICY
    else
      Instr := DEFAULT_POLICY;

  try
    Q := TAiJevQuestions.Create(nil);
    try
      Q.AddNoul('risk', Instr);
      if UseCategories then
      begin
        QC := Q.Add;
        QC.Name := 'category';
        QC.Kind := jqChoice;
        QC.Instructions := CATEGORY_QUESTION;
        QC.Criteria.Assign(FCategories);
      end;
      State := TJSONObject.Create;
      try
        State.AddPair('tool', AToolName);
        Desc := Trim(FToolDescriptions.Values[AToolName]);
        if Desc <> '' then
          State.AddPair('description', Desc);
        // The arguments go as raw JSON text, just as the guardrail receives them
        State.AddPair('arguments', AArguments);
        R := ActiveJev.Ask(State, Q);
      finally
        State.Free;
      end;
      try
        JevReportResult(Self, R, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput, FOnUsage);
        FLastRisk := R['risk'].Noul;
        if UseCategories then
        begin
          FLastCategory := R['category'].Choice;
          FLastCategoryConfidence := R['category'].Confidence;
          // The most probable blocked category, even if not the choice
          for i := 0 to FBlockedCategories.Count - 1 do
          begin
            Key := Trim(FBlockedCategories[i]);
            if Key = '' then
              Continue;
            P := R['category'].Probability(Key);
            if P > WorstP then
            begin
              WorstP := P;
              WorstKey := Key;
            end;
          end;
        end;
      finally
        R.Free;
      end;
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      if FBlockOnError then
      begin
        AReason := 'Jev guardrail unavailable: ' + E.Message;
        Exit(False);
      end;
      Exit(True);
    end;
  end;

  if FLastRisk >= FBlockThreshold then
  begin
    Result := False;
    AReason := Format('Jev risk %s >= %s', [Inv(FLastRisk), Inv(FBlockThreshold)]);
  end
  else if (WorstKey <> '') and (WorstP >= FCategoryThreshold) then
  begin
    Result := False;
    AReason := Format('Jev category %s %s >= %s is blocked', [WorstKey, Inv(WorstP), Inv(FCategoryThreshold)]);
  end;

  if UseCategories and Assigned(FOnCategorized) then
    FOnCategorized(Self, AToolName, AArguments, FLastCategory, FLastCategoryConfidence, Result, AReason);
end;

function TAiJevGuardrailClassifier.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJevGuardrailClassifier.ResetUsage;
begin
  FUsage.Reset;
end;

end.
