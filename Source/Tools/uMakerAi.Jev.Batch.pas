unit uMakerAi.Jev.Batch;

// -----------------------------------------------------------------------------
// TAiJevBatchLabeler: applies the same questions (Questions) to many rows,
// one call to Jev per row, in parallel, and returns a report with the
// label, confidence and alternatives for each row, total cost and the
// list of doubtful rows for human review.
//
//   Labeler.Questions.AddChoice('category', 'What category does `item` have?',
//     ['spam=Unsolicited advertising', 'urgent=Requires action today', 'archive']);
//   Report := Labeler.Run(Texts);            // the caller frees the report
//   for Item in Report.NeedsReview do ...      // what is worth reviewing manually
//
// Input: texts (each travels as {ItemField: text}) or already built JSON
// states, for rows with several fields ({movement, type, ...}).
//
// The label is the answer to LabelQuestion (empty = the first Choice
// question). The other questions are answered in the same call and remain in
// Item.Result. A row with confidence < ReviewThreshold is marked for
// review; a row with error stores the message and the batch continues.
//
// Concurrency: MaxParallel simultaneous calls, each with its own
// TAiJev. With an external Jev assigned it runs serially (the shared component
// is not thread-safe). OnProgress is fired from the pool threads:
// to touch the UI, use TThread.Queue in the handler. Cancel stops the batch;
// unprocessed rows remain with Error = 'cancelled'.
//
// Validated sep 28/2026 reproducing in Delphi the experiment of classifying
// 126 movements against 225 accounts of the PUC (demo 087).
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.Threading, System.SyncObjs, System.Diagnostics,
  uMakerAi.Jev;

type
  TAiJevBatchItem = class
  private
    FIndex: Integer;
    FInput: string;
    FChoice: string;
    FConfidence: Double;
    FTop: TArray<string>;
    FNeedsReview: Boolean;
    FError: string;
    FResult: TAiJevResult;
  public
    destructor Destroy; override;
    // Position in the input (0..N-1)
    property Index: Integer read FIndex;
    // Row text, or the serialized JSON state
    property Input: string read FInput;
    // Label: the choice of LabelQuestion
    property Choice: string read FChoice;
    property Confidence: Double read FConfidence;
    // The 3 most probable labels (suggestions for the reviewer)
    property Top: TArray<string> read FTop;
    property NeedsReview: Boolean read FNeedsReview;
    // '' if the row was processed correctly
    property Error: string read FError;
    // Full response (all questions); nil if there was an error
    property Result: TAiJevResult read FResult;
  end;

  TAiJevBatchReport = class
  private
    FItems: TObjectList<TAiJevBatchItem>;
    FMeter: TAiJevUsageMeter; // consumption of this batch (for OnUsage)
    FInputTokens: Int64;
    FCostUSD: Double;
    FElapsedMs: Int64;
    FCancelled: Boolean;
    function GetErrorCount: Integer;
    function GetReviewCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // Rows with low confidence (without error), in input order
    function NeedsReview: TArray<TAiJevBatchItem>;
    // index;label;confidence;review;top;error;input (UTF-8, separator ';')
    procedure SaveToCSV(const AFileName: string);
    property Items: TObjectList<TAiJevBatchItem> read FItems;
    property InputTokens: Int64 read FInputTokens;
    property CostUSD: Double read FCostUSD;
    property ElapsedMs: Int64 read FElapsedMs;
    property Cancelled: Boolean read FCancelled;
    property ErrorCount: Integer read GetErrorCount;
    property ReviewCount: Integer read GetReviewCount;
  end;

  // Fired from pool threads; use TThread.Queue for the UI
  TAiJevBatchProgressEvent = procedure(Sender: TObject; ADone, ATotal: Integer) of object;

  TAiJevBatchLabeler = class(TComponent)
  private
    FUsage: TAiJevUsageMeter;
    FPricePerMillionOutput: Double;
    FOnUsage: TAiJevUsageEvent;
    FJev: TAiJev;
    FApiKey: string;
    FModel: string;
    FUrl: string; // '' = TypeSafe (JEV_DEFAULT_URL)
    FQuestions: TAiJevQuestions;
    FItemField: string;
    FLabelQuestion: string;
    FReviewThreshold: Double;
    FMaxParallel: Integer;
    FPricePerMillion: Double;
    FCancelled: Boolean;
    FDone: Integer;
    FOnProgress: TAiJevBatchProgressEvent;
    procedure SetJev(const Value: TAiJev);
    procedure SetQuestions(const Value: TAiJevQuestions);
    function NewJev: TAiJev;
    function ResolveLabelQuestion: string;
    procedure ProcessItem(AJev: TAiJev; AItem: TAiJevBatchItem; AState: TJSONValue;
      const ALabelQ: string; AReport: TAiJevBatchReport; ATotal: Integer);
    function InternalRun(const AStates: TArray<TJSONValue>; const AInputs: TArray<string>): TAiJevBatchReport;
    function GetUsage: TAiJevUsage;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev consumption accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
    // Each text travels as {ItemField: text}. The caller frees the report.
    function Run(const ATexts: TArray<string>): TAiJevBatchReport; overload;
    // Already built JSON states (does not take ownership). The caller frees the report.
    function Run(const AStates: TArray<TJSONObject>): TAiJevBatchReport; overload;
    // Stops the current batch (safe from another thread)
    procedure Cancel;
  published
    // Optional: external TAiJev (shared or test double); if assigned,
    // ApiKey and Model are ignored and rows are processed serially
    property Jev: TAiJev read FJev write SetJev;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    // System One server: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;
    // Questions applied to each row
    property Questions: TAiJevQuestions read FQuestions write SetQuestions;
    // Name of the field that carries each text (Run with texts)
    property ItemField: string read FItemField write FItemField;
    // Question that provides the label; empty = the first Choice
    property LabelQuestion: string read FLabelQuestion write FLabelQuestion;
    property ReviewThreshold: Double read FReviewThreshold write FReviewThreshold;
    property MaxParallel: Integer read FMaxParallel write FMaxParallel default 8;
    // USD per million input tokens (for CostUSD)
    property PricePerMillion: Double read FPricePerMillion write FPricePerMillion;
    property OnProgress: TAiJevBatchProgressEvent read FOnProgress write FOnProgress;
    // Prices for CostUSD of Usage/OnUsage (USD per million tokens; today output is not charged)
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with the consumption of that operation. Synchronous, in the thread
    // that executed it (on a server: the request thread, to charge the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

procedure Register;

implementation

uses
  System.StrUtils;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJevBatchLabeler]);
end;

{ TAiJevBatchItem }

destructor TAiJevBatchItem.Destroy;
begin
  FResult.Free;
  inherited;
end;

{ TAiJevBatchReport }

constructor TAiJevBatchReport.Create;
begin
  inherited Create;
  FItems := TObjectList<TAiJevBatchItem>.Create(True);
  FMeter := TAiJevUsageMeter.Create;
end;

destructor TAiJevBatchReport.Destroy;
begin
  FItems.Free;
  FMeter.Free;
  inherited;
end;

function TAiJevBatchReport.GetErrorCount: Integer;
var
  It: TAiJevBatchItem;
begin
  Result := 0;
  for It in FItems do
    if It.FError <> '' then
      Inc(Result);
end;

function TAiJevBatchReport.GetReviewCount: Integer;
var
  It: TAiJevBatchItem;
begin
  Result := 0;
  for It in FItems do
    if It.FNeedsReview then
      Inc(Result);
end;

function TAiJevBatchReport.NeedsReview: TArray<TAiJevBatchItem>;
var
  L: TList<TAiJevBatchItem>;
  It: TAiJevBatchItem;
begin
  L := TList<TAiJevBatchItem>.Create;
  try
    for It in FItems do
      if It.FNeedsReview then
        L.Add(It);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TAiJevBatchReport.SaveToCSV(const AFileName: string);
var
  SL: TStringList;
  It: TAiJevBatchItem;

  function Q(const S: string): string;
  begin
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('index;label;confidence;review;top;error;input');
    for It in FItems do
      SL.Add(Format('%d;%s;%s;%s;%s;%s;%s', [It.FIndex, Q(It.FChoice),
        FormatFloat('0.00', It.FConfidence, TFormatSettings.Invariant),
        IfThen(It.FNeedsReview, 'yes', 'no'), Q(string.Join(',', It.FTop)), Q(It.FError),
        Q(StringReplace(It.FInput, sLineBreak, ' ', [rfReplaceAll]))]));
    SL.SaveToFile(AFileName, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

{ TAiJevBatchLabeler }

constructor TAiJevBatchLabeler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FQuestions := TAiJevQuestions.Create(Self);
  FItemField := 'item';
  FReviewThreshold := 0.6;
  FMaxParallel := 8;
  FPricePerMillion := 0.042;
end;

destructor TAiJevBatchLabeler.Destroy;
begin
  FQuestions.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevBatchLabeler.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevBatchLabeler.SetQuestions(const Value: TAiJevQuestions);
begin
  FQuestions.Assign(Value);
end;

procedure TAiJevBatchLabeler.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevBatchLabeler.NewJev: TAiJev;
begin
  Result := TAiJev.Create(nil);
  Result.ApiKey := FApiKey;
  Result.Model := FModel;
  Result.Url := JevUrlOrDefault(FUrl);
end;

procedure TAiJevBatchLabeler.Cancel;
begin
  FCancelled := True;
end;

function TAiJevBatchLabeler.ResolveLabelQuestion: string;
var
  i: Integer;
begin
  if FLabelQuestion <> '' then
  begin
    if FQuestions.Find(FLabelQuestion) = nil then
      raise EAiJevError.CreateFmt('JevBatch: LabelQuestion "%s" is not in Questions', [FLabelQuestion]);
    Exit(FLabelQuestion);
  end;
  for i := 0 to FQuestions.Count - 1 do
    if FQuestions[i].Kind = jqChoice then
      Exit(FQuestions[i].Name);
  Result := ''; // no Choice: no label, only Item.Result
end;

procedure TAiJevBatchLabeler.ProcessItem(AJev: TAiJev; AItem: TAiJevBatchItem; AState: TJSONValue;
  const ALabelQ: string; AReport: TAiJevBatchReport; ATotal: Integer);
var
  R: TAiJevResult;
  Done: Integer;
begin
  if FCancelled then
    AItem.FError := 'cancelled'
  else
    try
      R := AJev.Ask(AState, FQuestions);
      AItem.FResult := R;
      TInterlocked.Add(AReport.FInputTokens, Int64(R.InputTokens));
      AReport.FMeter.Add(R);
      if ALabelQ <> '' then
      begin
        AItem.FChoice := R[ALabelQ].Choice;
        AItem.FConfidence := R[ALabelQ].Confidence;
        AItem.FTop := R[ALabelQ].Top(3);
        AItem.FNeedsReview := AItem.FConfidence < FReviewThreshold;
      end;
    except
      on E: Exception do
        AItem.FError := E.Message; // row fails, batch continues
    end;

  Done := TInterlocked.Increment(FDone);
  if Assigned(FOnProgress) then
    FOnProgress(Self, Done, ATotal);
end;

function TAiJevBatchLabeler.InternalRun(const AStates: TArray<TJSONValue>;
  const AInputs: TArray<string>): TAiJevBatchReport;
var
  Report: TAiJevBatchReport;
  LabelQ: string;
  Pool: TThreadPool;
  SW: TStopwatch;
  i, Total: Integer;
  It: TAiJevBatchItem;
begin
  FQuestions.Validate; // configuration errors before spending a call
  LabelQ := ResolveLabelQuestion;
  FCancelled := False;
  FDone := 0;
  Total := Length(AStates);

  Report := TAiJevBatchReport.Create;
  try
    for i := 0 to Total - 1 do
    begin
      It := TAiJevBatchItem.Create;
      It.FIndex := i;
      It.FInput := AInputs[i];
      Report.FItems.Add(It);
    end;

    SW := TStopwatch.StartNew;
    if Assigned(FJev) or (FMaxParallel <= 1) or (Total <= 1) then
    begin
      for i := 0 to Total - 1 do
        if Assigned(FJev) then
          ProcessItem(FJev, Report.FItems[i], AStates[i], LabelQ, Report, Total)
        else
        begin
          var J := NewJev;
          try
            ProcessItem(J, Report.FItems[i], AStates[i], LabelQ, Report, Total);
          finally
            J.Free;
          end;
        end;
    end
    else
    begin
      Pool := TThreadPool.Create;
      try
        Pool.SetMinWorkerThreads(1);
        Pool.SetMaxWorkerThreads(FMaxParallel);
        TParallel.For(0, Total - 1,
          procedure(AIndex: Integer)
          var
            J: TAiJev;
          begin
            J := NewJev; // one TAiJev per row: component is not thread-safe
            try
              ProcessItem(J, Report.FItems[AIndex], AStates[AIndex], LabelQ, Report, Total);
            finally
              J.Free;
            end;
          end, Pool);
      finally
        Pool.Free;
      end;
    end;
    SW.Stop;

    Report.FElapsedMs := SW.ElapsedMilliseconds;
    Report.FCancelled := FCancelled;
    Report.FCostUSD := Report.FInputTokens * JevAdapterInputPrice(FJev, FUrl, FPricePerMillion) / 1E6;
    // One OnUsage per batch. PricePerMillion (historical) is the input price
    JevReportOperation(Self, Report.FMeter, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillion), FPricePerMillionOutput, FOnUsage);
  except
    Report.Free;
    raise;
  end;
  Result := Report;
end;

function TAiJevBatchLabeler.Run(const ATexts: TArray<string>): TAiJevBatchReport;
var
  States: TArray<TJSONValue>;
  i: Integer;
begin
  SetLength(States, Length(ATexts));
  try
    for i := 0 to High(ATexts) do
      States[i] := TJSONObject.Create.AddPair(FItemField, ATexts[i]);
    Result := InternalRun(States, ATexts);
  finally
    for i := 0 to High(States) do
      States[i].Free;
  end;
end;

function TAiJevBatchLabeler.Run(const AStates: TArray<TJSONObject>): TAiJevBatchReport;
var
  States: TArray<TJSONValue>;
  Inputs: TArray<string>;
  i: Integer;
begin
  SetLength(States, Length(AStates));
  SetLength(Inputs, Length(AStates));
  for i := 0 to High(AStates) do
  begin
    States[i] := AStates[i];
    Inputs[i] := AStates[i].ToJSON;
  end;
  Result := InternalRun(States, Inputs);
end;

function TAiJevBatchLabeler.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillion), FPricePerMillionOutput);
end;

procedure TAiJevBatchLabeler.ResetUsage;
begin
  FUsage.Reset;
end;

end.
