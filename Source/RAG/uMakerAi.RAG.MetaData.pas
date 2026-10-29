unit uMakerAi.RAG.MetaData;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON,
  System.Variants,
  System.StrUtils,
  System.DateUtils,
  System.Math,
  System.Masks, // Needed to simulate LIKE
  System.VarUtils;

type
  TAiLanguage = (alSpanish, alEnglish, alPortuguese, alCustom);

  { Logical operator to determine how items in the list are evaluated }
  TLogicalOperator = (loAnd, loOr);

  { Superset of unified operators (Memory + SQL) }
  TFilterOperator = (
    // Basic
    foEqual,   // =
    foNotEqual, // <>
    foGreater,  // >
    foGreaterOrEqual, // >=
    foLess,     // <
    foLessOrEqual, // <=

    // Advanced Text
    foContains,    // String contains (LIKE %val%) / JSON @>
    foStartsWith,  // String starts with (LIKE val%)
    foEndsWith,    // String ends with (LIKE %val)
    foLike,        // Standard SQL pattern (with % and _)
    foILike,       // Case insensitive Like

    // Lists and Ranges
    foIn,          // IN (list)
    foNotIn,       // NOT IN (list)
    foBetween,     // Range (requires two values)

    // Existence and Structure
    foIsNull,      // Value is null or key does not exist
    foIsNotNull,   // Value is not null and key exists
    foExists,      // The key exists (regardless of value)

    // --- MISSING ADDITIONS ---
    foExistsAny,   // ?| (Any of the keys exists in the JSON)
    foExistsAll    // ?& (All keys exist in the JSON)
    );

  TAiEmbeddingMetaData = class;
  TAiFilterCriteria = class; // Forward declaration


  { Structure to store an individual condition OR a subgroup }
  TFilterCriterion = record
    Key: string;
    Op: TFilterOperator;
    Value: Variant;
    Value2: Variant; // Used only for foBetween

    // --- SUPPORT FOR DECISION TREE (VGQL) ---
    IsGroup: Boolean;
    SubCriteria: TAiFilterCriteria;

    constructor Create(const AKey: string; AOp: TFilterOperator; const AVal: Variant); overload;
    constructor Create(const AKey: string; AOp: TFilterOperator; const AVal, AVal2: Variant); overload;
    constructor CreateGroup(ASub: TAiFilterCriteria);
  end;

  { Container class for complex search criteria (Recursive) }
  TAiFilterCriteria = class
  private
    FCriteria: TList<TFilterCriterion>;
    FLogicalOp: TLogicalOperator;
    function GetCount: Integer;
    function GetItem(Index: Integer): TFilterCriterion;
  public
    { Constructor with option to define logic (Default = AND for compatibility) }
    constructor Create(ALogic: TLogicalOperator = loAnd);
    destructor Destroy; override;

    procedure Clear;

    // Fluent methods to easily build filters
    function Add(const Key: string; Op: TFilterOperator; const Value: Variant): TAiFilterCriteria; overload;
    function Add(const Key: string; Op: TFilterOperator; const Value, Value2: Variant): TAiFilterCriteria; overload;

// Method to add subgroups (Needed for the VGQL Compiler)
    function AddGroup(ALogic: TLogicalOperator): TAiFilterCriteria;

    function AddEqual(const Key: string; const Value: Variant): TAiFilterCriteria;
    function AddGreater(const Key: string; const Value: Variant): TAiFilterCriteria;
    function AddLess(const Key: string; const Value: Variant): TAiFilterCriteria;
    function AddBetween(const Key: string; const Min, Max: Variant): TAiFilterCriteria;
    function AddIn(const Key: string; const Values: Variant): TAiFilterCriteria; // Values can be Variant Array
    function AddLike(const Key, Pattern: string; CaseInsensitive: Boolean = True): TAiFilterCriteria;

    // Compatibility loading from old MetaData (all foEqual)
    procedure LoadFromMetaData(AMeta: TAiEmbeddingMetaData);

    property LogicalOp: TLogicalOperator read FLogicalOp write FLogicalOp;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TFilterCriterion read GetItem; default;
    property List: TList<TFilterCriterion> read FCriteria;
  end;

  { TAiEmbeddingMetaData: Node attribute store }
  TAiEmbeddingMetaData = class
  private
    FProperties: TDictionary<string, Variant>;
    FTagString: string;
    FData: TStrings;
    FTagObject: TObject;

    function GetProperty(const Name: string): Variant;
    procedure SetProperty(const Name: string; const Value: Variant);
    procedure SetData(const Value: TStrings);

    // Internal comparison helpers
    function CompareNumbers(const A, B: Variant; Op: TFilterOperator): Boolean;
    function CompareStrings(const A, B: string; Op: TFilterOperator): Boolean;
    function CheckInList(const Val: Variant; const List: Variant; Negate: Boolean): Boolean;
    function CheckLike(const Val, Pattern: string; CaseInsensitive: Boolean): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Assign(Source: TAiEmbeddingMetaData);
    function Has(const Name: string): Boolean;
    function Get(const Name: string; Default: Variant): Variant;
    procedure Remove(const Name: string);

    { Evaluates whether this MetaData meets a specific criterion }
    function Evaluate(const Name: string; Op: TFilterOperator; const Value: Variant): Boolean; Overload;
    function Evaluate(const Name: string; Op: TFilterOperator; const Value, Value2: Variant; const ANodeText: string = ''): Boolean; Overload;

    { Evaluates whether this MetaData meets the criteria tree }
    function Matches(Criteria: TAiFilterCriteria; const ANodeText: string = ''): Boolean;

    { JSON serialization }
    function ToJSON: TJSONObject;
    procedure FromJSON(aJSON: TJSONObject);

    property Properties[const Name: string]: Variant read GetProperty write SetProperty; default;
    property InternalDictionary: TDictionary<string, Variant> read FProperties;
    property Data: TStrings read FData write SetData;
    property TagString: string read FTagString write FTagString;
    property TagObject: TObject read FTagObject write FTagObject;
  end;

implementation

{ TFilterCriterion }

constructor TFilterCriterion.Create(const AKey: string; AOp: TFilterOperator; const AVal: Variant);
begin
  Key := AKey;
  Op := AOp;
  Value := AVal;
  Value2 := Unassigned;
  IsGroup := False;
  SubCriteria := nil;
end;

constructor TFilterCriterion.Create(const AKey: string; AOp: TFilterOperator; const AVal, AVal2: Variant);
begin
  Key := AKey;
  Op := AOp;
  Value := AVal;
  Value2 := AVal2;
  IsGroup := False;
  SubCriteria := nil;
end;

constructor TFilterCriterion.CreateGroup(ASub: TAiFilterCriteria);
begin
  IsGroup := True;
  SubCriteria := ASub;
  Key := '';
  Op := foEqual; // Not relevant for groups
  Value := Unassigned;
  Value2 := Unassigned;
end;

{ TAiFilterCriteria }

constructor TAiFilterCriteria.Create(ALogic: TLogicalOperator);
begin
  FCriteria := TList<TFilterCriterion>.Create;
  FLogicalOp := ALogic;
end;

destructor TAiFilterCriteria.Destroy;
var
  C: TFilterCriterion;
begin
  // Recursive memory release for nested groups
  for C in FCriteria do
  begin
    if C.IsGroup and Assigned(C.SubCriteria) then
      C.SubCriteria.Free;
  end;
  FCriteria.Free;
  inherited;
end;

procedure TAiFilterCriteria.Clear;
var
  C: TFilterCriterion;
begin
  for C in FCriteria do
  begin
    if C.IsGroup and Assigned(C.SubCriteria) then
      C.SubCriteria.Free;
  end;
  FCriteria.Clear;
end;

function TAiFilterCriteria.GetCount: Integer;
begin
  Result := FCriteria.Count;
end;

function TAiFilterCriteria.GetItem(Index: Integer): TFilterCriterion;
begin
  Result := FCriteria[Index];
end;

function TAiFilterCriteria.Add(const Key: string; Op: TFilterOperator; const Value: Variant): TAiFilterCriteria;
begin
  FCriteria.Add(TFilterCriterion.Create(Key, Op, Value));
  Result := Self;
end;

function TAiFilterCriteria.Add(const Key: string; Op: TFilterOperator; const Value, Value2: Variant): TAiFilterCriteria;
begin
  FCriteria.Add(TFilterCriterion.Create(Key, Op, Value, Value2));
  Result := Self;
end;

function TAiFilterCriteria.AddGroup(ALogic: TLogicalOperator): TAiFilterCriteria;
var
  Sub: TAiFilterCriteria;
begin
  Sub := TAiFilterCriteria.Create(ALogic);
  FCriteria.Add(TFilterCriterion.CreateGroup(Sub));
  Result := Sub;
end;

function TAiFilterCriteria.AddEqual(const Key: string; const Value: Variant): TAiFilterCriteria;
begin
  Result := Add(Key, foEqual, Value);
end;

function TAiFilterCriteria.AddGreater(const Key: string; const Value: Variant): TAiFilterCriteria;
begin
  Result := Add(Key, foGreater, Value);
end;

function TAiFilterCriteria.AddLess(const Key: string; const Value: Variant): TAiFilterCriteria;
begin
  Result := Add(Key, foLess, Value);
end;

function TAiFilterCriteria.AddBetween(const Key: string; const Min, Max: Variant): TAiFilterCriteria;
begin
  Result := Add(Key, foBetween, Min, Max);
end;

function TAiFilterCriteria.AddIn(const Key: string; const Values: Variant): TAiFilterCriteria;
begin
  Result := Add(Key, foIn, Values);
end;

function TAiFilterCriteria.AddLike(const Key, Pattern: string; CaseInsensitive: Boolean): TAiFilterCriteria;
begin
  if CaseInsensitive then
    Result := Add(Key, foILike, Pattern)
  else
    Result := Add(Key, foLike, Pattern);
end;

procedure TAiFilterCriteria.LoadFromMetaData(AMeta: TAiEmbeddingMetaData);
var
  Pair: TPair<string, Variant>;
begin
  if not Assigned(AMeta) then
    Exit;

  // Legacy compatibility
  for Pair in AMeta.InternalDictionary do
    AddEqual(Pair.Key, Pair.Value);
end;

{ TAiEmbeddingMetaData }

constructor TAiEmbeddingMetaData.Create;
begin
  inherited Create;
  FProperties := TDictionary<string, Variant>.Create(TStringComparer.Ordinal);
  FData := TStringList.Create;
  FTagString := '';
  FTagObject := nil;
end;

destructor TAiEmbeddingMetaData.Destroy;
begin
  FData.Free;
  FProperties.Free;
  inherited;
end;

procedure TAiEmbeddingMetaData.Clear;
begin
  FProperties.Clear;
  FData.Clear;
  FTagString := '';
  FTagObject := nil;
end;

procedure TAiEmbeddingMetaData.Assign(Source: TAiEmbeddingMetaData);
var
  Pair: TPair<string, Variant>;
begin
  if not Assigned(Source) then
    Exit;
  Clear;
  FTagString := Source.TagString;
  FTagObject := Source.TagObject;
  FData.Assign(Source.Data);
  for Pair in Source.InternalDictionary do
    SetProperty(Pair.Key, Pair.Value);
end;

function TAiEmbeddingMetaData.Has(const Name: string): Boolean;
begin
  Result := FProperties.ContainsKey(Name);
end;

function TAiEmbeddingMetaData.Get(const Name: string; Default: Variant): Variant;
begin
  if not FProperties.TryGetValue(Name, Result) then
    Result := Default;
end;

procedure TAiEmbeddingMetaData.Remove(const Name: string);
begin
  FProperties.Remove(Name);
end;

function TAiEmbeddingMetaData.GetProperty(const Name: string): Variant;
begin
  if not FProperties.TryGetValue(Name, Result) then
    Result := Null;
end;

procedure TAiEmbeddingMetaData.SetProperty(const Name: string; const Value: Variant);
begin
  FProperties.AddOrSetValue(Name, Value);
end;

procedure TAiEmbeddingMetaData.SetData(const Value: TStrings);
begin
  if Assigned(Value) then
    FData.Assign(Value)
  else
    FData.Clear;
end;

{ --- Comparison Helpers --- }

function TAiEmbeddingMetaData.CompareNumbers(const A, B: Variant; Op: TFilterOperator): Boolean;
var
  D1, D2: Double;
  I1, I2: Int64;
  TypeA, TypeB: Word;
  IsIntA, IsIntB: Boolean;
begin
  TypeA := VarType(A) and varTypeMask;
  TypeB := VarType(B) and varTypeMask;

  // Check if they are native integer types (Byte, Integer, Int64, etc.)
  // This is crucial for large IDs that Double would lose precision.
  IsIntA := (TypeA = varInt64) or (TypeA = varInteger) or (TypeA = varSmallint) or (TypeA = varByte) or (TypeA = varShortInt) or (TypeA = varWord) or (TypeA = varLongWord);
  IsIntB := (TypeB = varInt64) or (TypeB = varInteger) or (TypeB = varSmallint) or (TypeB = varByte) or (TypeB = varShortInt) or (TypeB = varWord) or (TypeB = varLongWord);

  // 1. Fast and Precise Path: 64-bit Integer Comparison
  if IsIntA and IsIntB then
  begin
    try
      I1 := A;
      I2 := B;
      case Op of
        foEqual:          Result := I1 = I2;
        foNotEqual:       Result := I1 <> I2;
        foGreater:        Result := I1 > I2;
        foGreaterOrEqual: Result := I1 >= I2;
        foLess:           Result := I1 < I2;
        foLessOrEqual:    Result := I1 <= I2;
      else
        Result := False;
      end;
      Exit;
    except
      // If direct conversion fails (unlikely if VarType says it's int), fall back to Double
    end;
  end;

  // 2. Standard Path: Floating Point Comparison
  try
    D1 := Double(A);
    D2 := Double(B);
  except
    // If unable to convert to number, return false
    Exit(False);
  end;

  case Op of
    foEqual:
      Result := SameValue(D1, D2, 0.00001);
    foNotEqual:
      Result := not SameValue(D1, D2, 0.00001);
    foGreater:
      Result := D1 > D2;
    foGreaterOrEqual:
      Result := D1 >= D2;
    foLess:
      Result := D1 < D2;
    foLessOrEqual:
      Result := D1 <= D2;
  else
    Result := False;
  end;
end;

function TAiEmbeddingMetaData.CompareStrings(const A, B: string; Op: TFilterOperator): Boolean;
begin
  case Op of
    foEqual:
      Result := SameText(A, B);
    foNotEqual:
      Result := not SameText(A, B);
    foContains:
      Result := ContainsText(A, B);
    foStartsWith:
      Result := StartsText(B, A);
    foEndsWith:
      Result := EndsText(B, A);
    foGreater:
      Result := CompareText(A, B) > 0;
    foLess:
      Result := CompareText(A, B) < 0;
  else
    Result := False;
  end;
end;

function TAiEmbeddingMetaData.CheckLike(const Val, Pattern: string; CaseInsensitive: Boolean): Boolean;
var
  LVal, LPat: string;
begin
  LPat := Pattern.Replace('%', '*').Replace('_', '?');
  LVal := Val;

  if CaseInsensitive then
  begin
    LPat := LPat.ToLower;
    LVal := LVal.ToLower;
  end;

  Result := MatchesMask(LVal, LPat);
end;

function TAiEmbeddingMetaData.CheckInList(const Val: Variant; const List: Variant; Negate: Boolean): Boolean;
var
  i: Integer;
  Item: Variant;
  ValStr: string;
begin
  Result := False;
  if not VarIsArray(List) then
  begin
    Result := (Val = List);
    if Negate then
      Result := not Result;
    Exit;
  end;

  ValStr := VarToStrDef(Val, '');
  for i := VarArrayLowBound(List, 1) to VarArrayHighBound(List, 1) do
  begin
    Item := VarArrayGet(List, [i]);
    if SameText(ValStr, VarToStrDef(Item, '')) then
    begin
      Result := True;
      Break;
    end;
  end;

  if Negate then
    Result := not Result;
end;

{ --- Main Evaluation --- }

function TAiEmbeddingMetaData.Evaluate(const Name: string; Op: TFilterOperator; const Value: Variant): Boolean;
begin
  Result := Evaluate(Name, Op, Value, Unassigned);
end;

{ --- Implementation of Evaluate --- }

{ --- Implementation of Evaluate --- }

function TAiEmbeddingMetaData.Evaluate(const Name: string; Op: TFilterOperator; const Value, Value2: Variant; const ANodeText: string = ''): Boolean;
var
  PropValue: Variant;
  Exists: Boolean;
  DTProp, DTVal1, DTVal2: TDateTime;
  IsDateComparison: Boolean;
  i: Integer;
begin
  // 1. Injection of virtual field 'text' (Node content)
  if SameText(Name, 'text') then
  begin
    PropValue := ANodeText;
    Exists := True;
  end
  else
    Exists := FProperties.TryGetValue(Name, PropValue);

  // 2. Existence and nullity evaluation
  case Op of
    foExists:
      Exit(Exists);
    foIsNull:
      Exit(not Exists or VarIsNull(PropValue));
    foIsNotNull:
      Exit(Exists and not VarIsNull(PropValue));
  end;

  // If the property does not exist or is null, it cannot meet comparison criteria
  if not Exists or VarIsNull(PropValue) then
    Exit(False);

  // 3. List operators (IN / NOT IN)
  if Op in [foIn, foNotIn] then
    Exit(CheckInList(PropValue, Value, Op = foNotIn));

  // 4. Set operators (JSON Arrays) - ExistsAny / ExistsAll
  if Op in [foExistsAny, foExistsAll] then
  begin
    // Only supported if the property is an Array (e.g., Tags: ["A", "B"])
    if VarIsArray(PropValue) then
    begin
      // If the searched value is an array (Any of these tags exist)
      if VarIsArray(Value) then
      begin
        if Op = foExistsAny then
        begin
          // ?| : Is any element of Value in PropValue?
          for i := VarArrayLowBound(Value, 1) to VarArrayHighBound(Value, 1) do
            if CheckInList(VarArrayGet(Value, [i]), PropValue, False) then
              Exit(True);
          Exit(False);
        end
        else // foExistsAll
        begin
          // ?& : Are all elements of Value in PropValue?
          for i := VarArrayLowBound(Value, 1) to VarArrayHighBound(Value, 1) do
            if not CheckInList(VarArrayGet(Value, [i]), PropValue, False) then
              Exit(False);
          Exit(True);
        end;
      end
      else
      begin
        // If Value is simple, behaves like CONTAINS in list
        Exit(CheckInList(Value, PropValue, False));
      end;
    end;
    // If property is not an array, fail (or you could treat it as string contains)
    Exit(False);
  end;

  // 5. Text pattern operators (LIKE / ILIKE)
  if Op in [foLike, foILike] then
    Exit(CheckLike(VarToStr(PropValue), VarToStr(Value), Op = foILike));

  // 6. DATE COMPARISON DETECTION
  // Check if the property is a date or a string in ISO8601 format
  IsDateComparison := (VarType(PropValue) = varDate) or
                      ((VarType(PropValue) = varString) and TryISO8601ToDate(VarToStr(PropValue), DTProp));

  if IsDateComparison then
  begin
    // Ensure DTProp has the correct value
    if VarType(PropValue) = varDate then
      DTProp := VarToDateTime(PropValue); // We already have it, but for safety in flow

    if Op = foBetween then
    begin
      // For BETWEEN, both limits must be valid dates
      if TryISO8601ToDate(VarToStr(Value), DTVal1) and TryISO8601ToDate(VarToStr(Value2), DTVal2) then
        Exit((DTProp >= DTVal1) and (DTProp <= DTVal2))
      else
        Exit(False);
    end
    else if TryISO8601ToDate(VarToStr(Value), DTVal1) then
    begin
      // Standard date comparisons
      case Op of
        foEqual:          Exit(DTProp = DTVal1);
        foNotEqual:       Exit(DTProp <> DTVal1);
        foGreater:        Exit(DTProp > DTVal1);
        foGreaterOrEqual: Exit(DTProp >= DTVal1);
        foLess:           Exit(DTProp < DTVal1);
        foLessOrEqual:    Exit(DTProp <= DTVal1);
      end;
    end;
  end;

  // 7. NUMERIC COMPARISON DETECTION
  // We use VarIsNumeric to avoid exceptions. CompareNumbers handles precision.
  if VarIsNumeric(PropValue) and VarIsNumeric(Value) then
  begin
    if Op = foBetween then
    begin
      if VarIsNumeric(Value2) then
        Exit((Double(PropValue) >= Double(Value)) and (Double(PropValue) <= Double(Value2)))
      else
        Exit(False);
    end;

    // Call to the optimized helper
    Exit(CompareNumbers(PropValue, Value, Op));
  end;

  // 8. DEFAULT COMPARISON (STRINGS / TEXT)
  // Final fallback for strings
  if Op = foBetween then
  begin
    Exit((VarToStr(PropValue) >= VarToStr(Value)) and
         (VarToStr(PropValue) <= VarToStr(Value2)));
  end;

  // Delegate to CompareStrings (which handles Contains, StartsWith, EndsWith, etc.)
  Result := CompareStrings(VarToStr(PropValue), VarToStr(Value), Op);
end;

{ --- New Recursive Matches (Composite Pattern) --- }

function TAiEmbeddingMetaData.Matches(Criteria: TAiFilterCriteria; const ANodeText: string = ''): Boolean;
var
  Criterion: TFilterCriterion;
  CurrentMatch: Boolean;
begin
  if (Criteria = nil) or (Criteria.Count = 0) then
    Exit(True);

  // AND logic: Assume True and exit at first False
  if Criteria.LogicalOp = loAnd then
  begin
    Result := True;
    for Criterion in Criteria.List do
    begin
      // If it's a group, recursive
      if Criterion.IsGroup then
        CurrentMatch := Matches(Criterion.SubCriteria, ANodeText)
      else
        CurrentMatch := Evaluate(Criterion.Key, Criterion.Op, Criterion.Value, Criterion.Value2, ANodeText);

      if not CurrentMatch then
      begin
        Result := False;
        Break;
      end;
    end;
  end
  // OR logic: Assume False and exit at first True
  else
  begin
    Result := False;
    for Criterion in Criteria.List do
    begin
      if Criterion.IsGroup then
        CurrentMatch := Matches(Criterion.SubCriteria, ANodeText)
      else
        CurrentMatch := Evaluate(Criterion.Key, Criterion.Op, Criterion.Value, Criterion.Value2, ANodeText);

      if CurrentMatch then
      begin
        Result := True;
        Break;
      end;
    end;
  end;
end;

{ --- JSON --- }

function TAiEmbeddingMetaData.ToJSON: TJSONObject;
var
  Pair: TPair<string, Variant>;
  JVal: TJSONValue;
  V: Variant;
begin
  Result := TJSONObject.Create;
  try
    if not FTagString.IsEmpty then
      Result.AddPair('tagString', FTagString);

    if FData.Count > 0 then
      Result.AddPair('_data_text', FData.Text);

    for Pair in FProperties do
    begin
      V := Pair.Value;
      case VarType(V) and varTypeMask of
        varSmallint, varInteger, varByte, varShortInt, varWord, varLongWord, varInt64:
          JVal := TJSONNumber.Create(Int64(V));
        varSingle, varDouble, varCurrency:
          JVal := TJSONNumber.Create(Double(V));
        varBoolean:
          JVal := TJSONBool.Create(Boolean(V));
        varDate:
          JVal := TJSONString.Create(DateToISO8601(TDateTime(V), True));
        varNull, varEmpty:
          JVal := TJSONNull.Create;
      else
        JVal := TJSONString.Create(VarToStr(V));
      end;
      Result.AddPair(Pair.Key, JVal);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TAiEmbeddingMetaData.FromJSON(aJSON: TJSONObject);
var
  i: Integer;
  Pair: TJSONPair;
  S: string;
  DT: TDateTime;
begin
  if not Assigned(aJSON) then
    Exit;
  Clear;
  for i := 0 to aJSON.Count - 1 do
  begin
    Pair := aJSON.Pairs[i];
    S := Pair.JsonString.Value;

    if SameText(S, 'tagString') then
      FTagString := Pair.JsonValue.Value
    else if SameText(S, '_data_text') then
      FData.Text := Pair.JsonValue.Value
    else
    begin
      if Pair.JsonValue is TJSONNumber then
      begin
        if ContainsText(Pair.JsonValue.ToJSON, '.') then
          SetProperty(S, TJSONNumber(Pair.JsonValue).AsDouble)
        else
          SetProperty(S, TJSONNumber(Pair.JsonValue).AsInt64);
      end
      else if Pair.JsonValue is TJSONBool then
        SetProperty(S, TJSONBool(Pair.JsonValue).AsBoolean)
      else if Pair.JsonValue is TJSONNull then
        SetProperty(S, Null)
      else
      begin
        if TryISO8601ToDate(Pair.JsonValue.Value, DT) then
          SetProperty(S, DT)
        else
          SetProperty(S, Pair.JsonValue.Value);
      end;
    end;
  end;
end;

end.
