// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - YouTube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.RAG.Vectors.Index;


interface

uses
  System.SysUtils, System.Math, System.Generics.Collections, System.Variants, System.StrUtils,
  System.Generics.Defaults, System.Classes, System.JSon, Rest.JSon, System.SyncObjs,
  System.NetEncoding, System.Hash,

  uMakerAi.Embeddings.Core, uMakerAi.RAG.MetaData;

Type

  TAiEmbeddingNode = Class;

  TAiRagIndexType = (TAIBasicIndex, TAIHNSWIndex, TAIEuclideanIndex);
  TOnFilterItem = procedure(Sender: TObject; const aNode: TAiEmbeddingNode; var aInclude: Boolean) of object;

  TRagItems = TList<TAiEmbeddingNode>;

  TAiEmbeddingNode = class
  private
    FData: TAiEmbeddingData;
    FDim: Integer;
    FText: String;
    FIdx: Double;
    FModel: String;
    FMetaData: TAiEmbeddingMetaData;

    FTag: string; // GUID or DB ID (more versatile than Integer)
    FTagObject: TObject; // Reference to external objects
    FOrden: Integer;
    FMagnitude: Double;
    procedure SetData(const Value: TAiEmbeddingData); // Custom sorting

  public
    constructor Create(aDim: Integer);
    destructor Destroy; override;

    // Vector calculation methods
    class function CosineSimilarity(const A, B: TAiEmbeddingNode): Double;
    class function DotProduct(const A, B: TAiEmbeddingNode): Double;
    class function Magnitude(const A: TAiEmbeddingNode): Double;

    // Serialization
    function ToJSON: TJSONObject;
    class function FromJSON(AJSONObject: TJSONObject): TAiEmbeddingNode;
    function ToJsonArray: TJSonArray; overload;
    class function ToJsonArray(Val: TAiEmbeddingNode): TJSonArray; overload;

    // Utilities
    procedure SetDataLength(aDim: Integer);

    // Properties (without trivial setters)
    property Data: TAiEmbeddingData read FData write SetData;
    property Text: String read FText write FText;
    property Idx: Double read FIdx write FIdx;
    property Model: String read FModel write FModel;
    property MetaData: TAiEmbeddingMetaData read FMetaData;
    property Tag: string read FTag write FTag;
    property TagObject: TObject read FTagObject write FTagObject;
    property Orden: Integer read FOrden write FOrden;
    property Dim: Integer read FDim;
    property MagnitudeValue: Double read FMagnitude;
  end;


  // ============================================================================
  // AUXILIARY RECORD FOR THREAD-SAFE RESULTS
  // ============================================================================
  /// <summary>
  /// Immutable structure to store search results without modifying
  /// the original nodes. This eliminates race conditions in multithreaded scenarios.
  /// </summary>
  TAiSearchResult = record
    Node: TAiEmbeddingNode;
    FScore: Double;

    class function Create(aNode: TAiEmbeddingNode; aScore: Double): TAiSearchResult; static;

    /// <summary>
    /// Comparator for descending order by score
    /// </summary>
    class function CompareDescending(const Left, Right: TAiSearchResult): Integer; static;
    Property Score: Double Read FScore Write FScore;
  end;


  /// ---------------------------------------------------------------------------
  /// TAIEmbeddingIndex represents the base class for in-memory embedding search.
  /// It consists of a vector of nodes and an index of pointers to embeddings that allows
  /// searching and selecting candidates that meet the condition.
  /// -------------------------------------------------------------------------
  TAIEmbeddingIndex = class
  private
    FDataVec: TRagItems;
    FActive: Boolean;
  protected
    /// <summary>
    /// Clears the internal index but keeps the reference to DataVec
    /// </summary>
    procedure InternalClear; virtual; abstract;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure BuildIndex(Points: TRagItems); virtual;
    function Add(Point: TAiEmbeddingNode): Integer; virtual;
    function Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems; virtual;

    /// <summary>
    /// Clears the index and leaves it ready to be rebuilt
    /// </summary>
    procedure Clear; virtual;

    property DataVec: TRagItems read FDataVec write FDataVec;
    property Active: Boolean read FActive;
  end;


  /// ---------------------------------------------------------------------------
  /// TAIBasicEmbeddingIndex is a simple implementation of an Embedding Index
  /// that is assigned by default to the vector to perform in-memory searches.
  /// However, there are more efficient ways to handle this with embedding vectors.
  /// -------------------------------------------------------------------------

  TAIBasicEmbeddingIndex = class(TAIEmbeddingIndex)
  protected
    procedure InternalClear; override;
  public
    procedure BuildIndex(Points: TRagItems); override;
    function Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems; override;

    /// <summary>
    /// Thread-safe version that does NOT modify the original nodes
    /// </summary>
    class function InternalSearchSafe(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; Source: TRagItems): TList<TAiSearchResult>; static;

    /// <summary>
    /// Legacy version for compatibility (DEPRECATED)
    /// </summary>
    class function InternalSearch(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; Source: TRagItems): TRagItems; static;
    constructor Create; override;
    destructor Destroy; override;
  end;

  TL2Pair = TPair<Double, TAiEmbeddingNode>;


  TAIEuclideanDistanceIndex = class(TAIEmbeddingIndex)
  protected
    procedure InternalClear; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure BuildIndex(Points: TRagItems); Override;
    Function Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems; Override;
  end;


  /// ---------------------------------------------------------------------------
  /// THNSWIndex implements an Approximate Nearest Neighbors (ANN) using the
  /// HNSW (Hierarchical Navigable Small World) algorithm, which is much more efficient
  /// for searching embedding vectors.
  /// -------------------------------------------------------------------------

  TConnListArray = array of TList<Integer>;

  THNSWNode = class
  private
    FID: Integer;
    FVector: TAiEmbeddingNode;
    FConnections: array of TList<Integer>;
  public
    constructor Create(aID: Integer; aVector: TAiEmbeddingNode; aNumLevels: Integer);
    destructor Destroy; override;

    property ID: Integer read FID;
    property Vector: TAiEmbeddingNode read FVector;
    // property Connections: array of TList<Integer> read FConnections;
    function GetConnections(Level: Integer): TList<Integer>;
    function LevelCount: Integer;
  end;

  THNSWIndex = class(TAIEmbeddingIndex)
  private
    FNodes: TDictionary<Integer, THNSWNode>;
    FEntryPoint: Integer;
    FEntryLevel: Integer;
    FMaxLevel: Integer;
    FLevelMult: Double;
    FEfConstruction: Integer;
    FMaxConnections: Integer;

    function GetRandomLevel: Integer;
    procedure InsertConnection(Node: THNSWNode; Level: Integer; TargetID: Integer);
    function SearchLayer(Query: TAiEmbeddingNode; EntryPoint: Integer; Level: Integer; Ef: Integer): TList<Integer>;
  protected
    /// <summary>
    /// Clears the HNSW graph without destroying the dictionary
    /// </summary>
    procedure InternalClear; override;
  public
    constructor Create; override;
    destructor Destroy; override;

    /// <summary>
    /// Rebuilds the index from scratch (thread-safe)
    /// </summary>
    procedure BuildIndex(Points: TRagItems); override;

    function Add(Point: TAiEmbeddingNode): Integer; override;
    function Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems; override;

    /// <summary>
    /// Clears the graph and resets to initial state
    /// </summary>
    procedure Clear; override;
  end;


  // Represents the frequency of a word in a specific node
  TWordOccurrence = record
    Node: TAiEmbeddingNode;
    Count: Integer;
  end;

  TAIBm25Index = class
  private
    FInvertedIndex: TDictionary<string, TList<TWordOccurrence>>;
    FDocLengths: TDictionary<TAiEmbeddingNode, Integer>;
    FAvgDocLength: Double;
    FLanguage: TAiLanguage;
{$IF CompilerVersion >= 36}
    FStopWords: THashSet<string>;
{$ELSE}
    FStopWords: TDictionary<string, Boolean>;
{$ENDIF}
    procedure SetLanguage(const Value: TAiLanguage);
    procedure LoadDefaultStopWords(Lang: TAiLanguage);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddNode(aNode: TAiEmbeddingNode); // To index when adding
    function Search(const aQuery: string; aLimit: Integer; aFilter: TAiFilterCriteria = nil): TList<TPair<Double, TAiEmbeddingNode>>;

    procedure Clear;

    property Language: TAiLanguage read FLanguage write SetLanguage;
{$IF CompilerVersion >= 36}
    property StopWords: THashSet<string> read FStopWords; // Allows adding custom words
{$ELSE}
    property StopWords: TDictionary<string, Boolean> read FStopWords;
{$ENDIF}
    procedure Tokenize(const aText: string; aList: TStrings);

  end;



implementation

{$IF CompilerVersion < 35}
uses
  uJSONHelper;
{$ENDIF}

{ TAiEmbeddingNode }

constructor TAiEmbeddingNode.Create(aDim: Integer);
begin
  inherited Create;
  FDim := aDim;
  SetLength(FData, FDim);
  FMetaData := TAiEmbeddingMetaData.Create;
  FTag := TGuid.NewGuid.ToString; // Default unique ID
  FOrden := 0;
  FTagObject := nil;
  FMagnitude := 0;
end;

destructor TAiEmbeddingNode.Destroy;
begin
  FMetaData.Free;
  // NOTE: We do NOT free FTagObject (we are not the owner)
  inherited;
end;

procedure TAiEmbeddingNode.SetData(const Value: TAiEmbeddingData);
var
  i: Integer;
  Sum: Double;
begin
  FData := Value;
  FDim := Length(Value);
  Sum := 0;
  // Calculate magnitude on the fly so MagnitudeValue is not 0
  for i := 0 to High(FData) do
    Sum := Sum + (FData[i] * FData[i]);
  FMagnitude := Sqrt(Sum);
end;

procedure TAiEmbeddingNode.SetDataLength(aDim: Integer);
begin
  FDim := aDim;
  SetLength(FData, FDim);
end;

function TAiEmbeddingNode.ToJSON: TJSONObject;
var
  JSONArray: TJSonArray;
  Value: Double;
begin
  Result := TJSONObject.Create;
  try
    // Array of embeddings
    JSONArray := TJSonArray.Create;
    for Value in FData do
      JSONArray.Add(Value);
    Result.AddPair('data', JSONArray);

    // Basic fields
    Result.AddPair('text', FText);
    Result.AddPair('model', FModel);
    Result.AddPair('tag', FTag);
    Result.AddPair('orden', FOrden);
    Result.AddPair('idx', FIdx);

    // Metadata
    if Assigned(FMetaData) then
      Result.AddPair('metadata', FMetaData.ToJSON);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiEmbeddingNode.FromJSON(AJSONObject: TJSONObject): TAiEmbeddingNode;
var
  JSONArray: TJSonArray;
  i: Integer;
  jMeta: TJSONObject;
  Sum: Double; // <--- 1. Add variable to accumulate
begin
  if not Assigned(AJSONObject) then
    raise Exception.Create('AJSONObject cannot be nil');

  // Create instance
  JSONArray := AJSONObject.GetValue<TJSonArray>('data');
  Result := TAiEmbeddingNode.Create(JSONArray.Count);

  try
    Sum := 0.0; // <--- 2. Initialize sum

    // Load embedding data
    for i := 0 to JSONArray.Count - 1 do
    begin
      Result.FData[i] := JSONArray.Items[i].AsType<Double>;

      // <--- 3. Calculate sum of squares on the fly (without traversing array twice)
      Sum := Sum + (Result.FData[i] * Result.FData[i]);
    end;

    // <--- 4. Assign final magnitude
    Result.FMagnitude := Sqrt(Sum);

    // Basic fields
    AJSONObject.TryGetValue<String>('text', Result.FText);
    AJSONObject.TryGetValue<String>('model', Result.FModel);
    AJSONObject.TryGetValue<String>('tag', Result.FTag);
    AJSONObject.TryGetValue<Integer>('orden', Result.FOrden);
    AJSONObject.TryGetValue<Double>('idx', Result.FIdx);

    // Metadata
    if AJSONObject.TryGetValue<TJSONObject>('metadata', jMeta) then
      Result.FMetaData.FromJSON(jMeta);
  except
    Result.Free;
    raise;
  end;
end;

function TAiEmbeddingNode.ToJsonArray: TJSonArray;
var
  Value: Double;
begin
  Result := TJSonArray.Create;
  for Value in FData do
    Result.Add(Value);
end;

class function TAiEmbeddingNode.ToJsonArray(Val: TAiEmbeddingNode): TJSonArray;
var
  Value: Double;
begin
  if not Assigned(Val) then
    raise Exception.Create('Val cannot be nil');

  Result := TJSonArray.Create;
  for Value in Val.FData do
    Result.Add(Value);
end;

class function TAiEmbeddingNode.DotProduct(const A, B: TAiEmbeddingNode): Double;
var
  i: Integer;
begin
  if Length(A.FData) <> Length(B.FData) then
    raise Exception.Create('Vectors must be of the same length');

  Result := 0;
  for i := Low(A.FData) to High(A.FData) do
    Result := Result + A.FData[i] * B.FData[i];
end;

class function TAiEmbeddingNode.Magnitude(const A: TAiEmbeddingNode): Double;
var
  Sum: Double;
  i: Integer;
begin
  Sum := 0.0;
  for i := Low(A.FData) to High(A.FData) do
    Sum := Sum + A.FData[i] * A.FData[i];
  Result := Sqrt(Sum);
end;

class function TAiEmbeddingNode.CosineSimilarity(const A, B: TAiEmbeddingNode): Double;
begin
  // CRITICAL VALIDATION: If either has no magnitude, there is no similarity (0.0)
  if (A.FMagnitude <= 0) or (B.FMagnitude <= 0) then
    Exit(0.0);

  // Dot product / (MagA * MagB)
  Result := TAiEmbeddingNode.DotProduct(A, B) / (A.FMagnitude * B.FMagnitude);

  // Clean up floating point precision
  if Result > 1.0 then
    Result := 1.0
  else if Result < -1.0 then
    Result := -1.0;
end;

function CompareEmbeddings(const Left, Right: TAiEmbeddingNode; Axis: Integer): Integer;
const
  TOLERANCE = 1.0E-12;
begin
  if Abs(Left.Data[Axis] - Right.Data[Axis]) < TOLERANCE then
    Result := 0
  else if Left.Data[Axis] < Right.Data[Axis] then
    Result := -1
  else
    Result := 1;
end;


{ TAiSearchResult }

class function TAiSearchResult.Create(aNode: TAiEmbeddingNode; aScore: Double): TAiSearchResult;
begin
  Result.Node := aNode;
  Result.Score := aScore;
end;

class function TAiSearchResult.CompareDescending(const Left, Right: TAiSearchResult): Integer;
begin
  // Descending order (Higher score first)
  Result := CompareValue(Right.Score, Left.Score);
end;


{ TAIEmbeddingIndex }

constructor TAIEmbeddingIndex.Create;
begin
  inherited;
  FDataVec := nil;
  FActive := False;
end;

destructor TAIEmbeddingIndex.Destroy;
begin
  // We do not free FDataVec - we are not the owner
  inherited;
end;

function TAIEmbeddingIndex.Add(Point: TAiEmbeddingNode): Integer;
begin
  Result := -1;
  // This function must be implemented in each model only when needed
end;

procedure TAIEmbeddingIndex.BuildIndex(Points: TRagItems);
begin
  FDataVec := Points;
  FActive := True;
end;

function TAIEmbeddingIndex.Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems;
begin
  Result := nil; // Must be implemented in derived classes
end;

procedure TAIEmbeddingIndex.Clear;
begin
  InternalClear;
  FActive := False;
end;


{ TAOIBasicIndex }

procedure TAIBasicEmbeddingIndex.BuildIndex(Points: TRagItems);
begin
  if not Assigned(Points) then
    Exit; // <- Protection
  inherited;
end;

procedure TAIBasicEmbeddingIndex.InternalClear;
begin
  // No internal structure — the node database is managed by TAiRAGVector
end;

constructor TAIBasicEmbeddingIndex.Create;
begin
  Inherited;
end;

destructor TAIBasicEmbeddingIndex.Destroy;
begin
  inherited;
end;

class function TAIBasicEmbeddingIndex.InternalSearch(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; Source: TRagItems): TRagItems;
var
  SafeResults: TList<TAiSearchResult>;
  SearchResult: TAiSearchResult;
begin
  Result := TRagItems.Create;

  // Use the thread-safe version internally
  SafeResults := InternalSearchSafe(Target, aLimit, aPrecision, Source);
  try
    for SearchResult in SafeResults do
    begin
      // HERE we assign Idx (compatible with existing code)
      SearchResult.Node.Idx := SearchResult.Score;
      Result.Add(SearchResult.Node);
    end;
  finally
    SafeResults.Free;
  end;
end;

class function TAIBasicEmbeddingIndex.InternalSearchSafe(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; Source: TRagItems): TList<TAiSearchResult>;
var
  i: Integer;
  Emb: TAiEmbeddingNode;
  Score: Double;
  TempList: TList<TAiSearchResult>;
begin
  Result := TList<TAiSearchResult>.Create;
  TempList := TList<TAiSearchResult>.Create;

  try
    // ========================================================================
    // PHASE 1: Calculate similarities (100% Thread-Safe)
    // ========================================================================
    // We do not modify the original nodes at all.
    // Each thread works with its own local list.

    for i := 0 to Source.Count - 1 do
    begin
      Emb := Source.Items[i];
      Score := TAiEmbeddingNode.CosineSimilarity(Emb, Target);

      // Pre-filtering by precision (optimization)
      if (aPrecision > 0) and (Score < aPrecision) then
        Continue;

      TempList.Add(TAiSearchResult.Create(Emb, Score));
    end;

    // ========================================================================
    // PHASE 2: Sort (100% Thread-Safe)
    // ========================================================================
    // Each thread sorts its own list without touching shared data

    TempList.Sort(TComparer<TAiSearchResult>.Construct(
      function(const Left, Right: TAiSearchResult): Integer
      begin
        Result := TAiSearchResult.CompareDescending(Left, Right);
      end));

    // ========================================================================
    // PHASE 3: Build result (100% Thread-Safe)
    // ========================================================================
    // Simply copy the references - we do NOT write to the nodes

    for i := 0 to Min(aLimit - 1, TempList.Count - 1) do
    begin
      Result.Add(TempList[i]); // Read-only access to shared nodes
    end;

  finally
    TempList.Free;
  end;
end;

function TAIBasicEmbeddingIndex.Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems;
var
  SafeList: TList<TAiSearchResult>;
  Res: TAiSearchResult;
begin
  Result := TRagItems.Create;

  // Use the "Safe" version you already created, which uses temporary records
  SafeList := InternalSearchSafe(Target, aLimit, aPrecision, DataVec);
  try
    for Res in SafeList do
      Result.Add(Res.Node);
    // Note: The score will be retrieved in the main engine.
  finally
    SafeList.Free;
  end;
end;

{ TAIEuclideanDistanceIndex }

procedure TAIEuclideanDistanceIndex.InternalClear;
begin
  // No internal structure — the node database is managed by TAiRAGVector
end;

procedure TAIEuclideanDistanceIndex.BuildIndex(Points: TRagItems);
begin
  Inherited; // The base implementation is sufficient
end;

constructor TAIEuclideanDistanceIndex.Create;
begin
  Inherited;
end;

destructor TAIEuclideanDistanceIndex.Destroy;
begin
  Inherited;
end;

function TAIEuclideanDistanceIndex.Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems;
Var
  i: Integer;
  Emb: TAiEmbeddingNode;
  Distance: Double;
  Pair: TL2Pair;
  Results: TList<TL2Pair>; // Use a temporary list so as not to modify the original one
begin
  Result := TRagItems.Create;
  Results := TList < TPair < Double, TAiEmbeddingNode >>.Create;

  try
    // 1. Calculate Euclidean distance for all elements and store them in a temporary list
    for i := 0 to DataVec.Count - 1 do
    begin
      Emb := DataVec.Items[i];
      // Here we use the function from the Core unit, which you already have
      Distance := TAiEmbeddingsCore.EuclideanDistance(Emb.Data, Target.Data);
      Emb.Idx := Distance; // Store distance for reference/debugging

      // aPrecision in this context means "maximum distance"
      // If aPrecision <= 0, ignore the precision filter
      if (aPrecision <= 0) or (Distance <= aPrecision) then
      begin
        Pair := TL2Pair.Create(Distance, Emb);
        Results.Add(Pair);
      end;
    end;

    // 2. Sort the result list by distance in ASCENDING order (lower is better)
    Results.Sort(TComparer < TPair < Double, TAiEmbeddingNode >>.Construct(
      function(const Left, Right: TPair<Double, TAiEmbeddingNode>): Integer
      begin
        // Left.Key vs Right.Key for ascending order
        Result := CompareValue(Left.Key, Right.Key);
      end));

    // 3. Traverse the sorted list and add the best 'aLimit' results
    for i := 0 to Min(aLimit - 1, Results.Count - 1) do
    begin
      Result.Add(Results[i].Value);
    end;

  finally
    Results.Free;
  end;
end;



{ THNSWNode }

constructor THNSWNode.Create(aID: Integer; aVector: TAiEmbeddingNode; aNumLevels: Integer);
var
  i: Integer;
begin
  inherited Create;
  FID := aID;
  FVector := aVector;

  // Safe initialization of the connection array
  SetLength(FConnections, aNumLevels);
  try
    for i := 0 to aNumLevels - 1 do
      FConnections[i] := TList<Integer>.Create;
  except
    // If creation of any list fails, clean up what was already created
    for i := 0 to High(FConnections) do
    begin
      if Assigned(FConnections[i]) then
        FConnections[i].Free;
    end;
    raise; // Re-raise the exception
  end;
end;

destructor THNSWNode.Destroy;
var
  i: Integer;
begin
  // Defensive cleanup - Triple protection
  if Length(FConnections) > 0 then
  begin
    for i := 0 to High(FConnections) do
    begin
      // Free is safe with nil, but double validation doesn't hurt
      if Assigned(FConnections[i]) then
        FreeAndNil(FConnections[i]);
    end;
  end;

  // IMPORTANT: We do NOT free FVector - we are not the owner
  // FVector is a reference to a node in the main TAiRAGVector

  inherited;
end;

function THNSWNode.GetConnections(Level: Integer): TList<Integer>;
begin
  if (Level < 0) or (Level >= Length(FConnections)) then
    raise EArgumentOutOfRangeException.CreateFmt('Level %d out of range [0..%d]', [Level, Length(FConnections) - 1]);

  Result := FConnections[Level];
end;

function THNSWNode.LevelCount: Integer;
begin
  Result := Length(FConnections);
end;

function THNSWIndex.GetRandomLevel: Integer;
var
  R: Double;
begin
  R := Random;
  if R <= 0 then
    R := 1E-12; // avoids ln(0)

  Result := Floor(-Ln(R) * FLevelMult);

  if Result >= FMaxLevel then
    Result := FMaxLevel - 1;
end;

{ THNSWIndex }

constructor THNSWIndex.Create;
begin
  inherited;

  // HNSW configuration
  FNodes := TDictionary<Integer, THNSWNode>.Create;
  FMaxLevel := 16;
  FLevelMult := 1 / Ln(2);
  FEfConstruction := 40;
  FMaxConnections := 16;
  FEntryPoint := -1;
  FEntryLevel := -1;
end;

destructor THNSWIndex.Destroy;
begin
  // Centralized cleanup
  Clear;

  // Free the container dictionary
  FNodes.Free;

  inherited;
end;

procedure THNSWIndex.InternalClear;
var
  Node: THNSWNode;
begin
  if (FNodes = nil) then
    Exit;

  try
    for Node in FNodes.Values do
      if Assigned(Node) then
        Node.Free;

    FNodes.Clear;
  except
    // Catch any odd errors during cleanup so as not to hang the IDE
  end;
end;

procedure THNSWIndex.Clear;
begin
  // Call internal cleanup
  InternalClear;

  // Reset graph state
  FEntryPoint := -1;
  FEntryLevel := -1;

  // NOTE: Configuration parameters (FMaxLevel, FEfConstruction, etc.)
  // are NOT reset - they are persistent configuration

  // Mark as inactive
  FActive := False;
end;

procedure THNSWIndex.InsertConnection(Node: THNSWNode; Level: Integer; TargetID: Integer);
var
  CurrentList: TList<Integer>;
  TargetNode, NeighborNode: THNSWNode;
  TargetSim, NeighborSim, MinSim: Double;
  WorstIndex, i: Integer;
begin
  CurrentList := Node.GetConnections(Level);

  // Avoid duplicates
  if CurrentList.Contains(TargetID) then
    Exit;

  // If there is space, add directly
  if CurrentList.Count < FMaxConnections then
  begin
    CurrentList.Add(TargetID);
    Exit;
  end;

  // Selection policy (keep the nearest neighbors)
  if not FNodes.TryGetValue(TargetID, TargetNode) then
    Exit;

  TargetSim := TAiEmbeddingNode.CosineSimilarity(Node.Vector, TargetNode.Vector);

  MinSim := 2.0;
  WorstIndex := -1;

  for i := 0 to CurrentList.Count - 1 do
  begin
    if FNodes.TryGetValue(CurrentList[i], NeighborNode) then
    begin
      NeighborSim := TAiEmbeddingNode.CosineSimilarity(Node.Vector, NeighborNode.Vector);
      if NeighborSim < MinSim then
      begin
        MinSim := NeighborSim;
        WorstIndex := i;
      end;
    end;
  end;

  if (WorstIndex > -1) and (TargetSim > MinSim) then
    CurrentList[WorstIndex] := TargetID;
end;

function THNSWIndex.SearchLayer(Query: TAiEmbeddingNode; EntryPoint: Integer; Level: Integer; Ef: Integer): TList<Integer>;
var
  Visited: TDictionary<Integer, Boolean>;
  Candidates: TList<TPair<Double, Integer>>;
  BestCandidates: TList<TPair<Double, Integer>>;
  CurrentNode: THNSWNode;
  Distance: Double;
  i: Integer;
begin
  Result := TList<Integer>.Create;
  Visited := TDictionary<Integer, Boolean>.Create;
  Candidates := TList < TPair < Double, Integer >>.Create;
  BestCandidates := TList < TPair < Double, Integer >>.Create;

  try
    CurrentNode := FNodes[EntryPoint];
    Distance := TAiEmbeddingNode.CosineSimilarity(Query, CurrentNode.Vector);

    Candidates.Add(TPair<Double, Integer>.Create(Distance, EntryPoint));
    BestCandidates.Add(TPair<Double, Integer>.Create(Distance, EntryPoint));
    Visited.Add(EntryPoint, True);

    while Candidates.Count > 0 do
    begin
      Candidates.Sort(TComparer < TPair < Double, Integer >>.Construct(
        function(const Left, Right: TPair<Double, Integer>): Integer
        begin
          if Left.Key > Right.Key then
            Result := -1
          else if Left.Key < Right.Key then
            Result := 1
          else
            Result := 0;
        end));

      CurrentNode := FNodes[Candidates[0].Value];
      Candidates.Delete(0);

      for i in CurrentNode.GetConnections(Level) do
      begin
        if not Visited.ContainsKey(i) then
        begin
          Visited.Add(i, True);
          Distance := TAiEmbeddingNode.CosineSimilarity(Query, FNodes[i].Vector);

          if (BestCandidates.Count < Ef) or (Distance > BestCandidates.Last.Key) then
          begin
            Candidates.Add(TPair<Double, Integer>.Create(Distance, i));
            BestCandidates.Add(TPair<Double, Integer>.Create(Distance, i));

            if BestCandidates.Count > Ef then
            begin
              BestCandidates.Sort(TComparer < TPair < Double, Integer >>.Construct(
                function(const Left, Right: TPair<Double, Integer>): Integer
                begin
                  if Left.Key > Right.Key then
                    Result := -1
                  else if Left.Key < Right.Key then
                    Result := 1
                  else
                    Result := 0;
                end));
              BestCandidates.Delete(BestCandidates.Count - 1);
            end;
          end;
        end;
      end;
    end;

    for i := 0 to BestCandidates.Count - 1 do
      Result.Add(BestCandidates[i].Value);

  finally
    Visited.Free;
    Candidates.Free;
    BestCandidates.Free;
  end;
end;

function THNSWIndex.Add(Point: TAiEmbeddingNode): Integer;
var
  NodeID: Integer;
  Level: Integer;
  CurrentLevel: Integer;
  EntryPointCopy: Integer;
  W: TList<Integer>;
  Node: THNSWNode;
  i: Integer;
begin
  // Assign unique ID based on current count
  NodeID := FNodes.Count;
  Level := GetRandomLevel;

  // Create new HNSW node
  Node := THNSWNode.Create(NodeID, Point, FMaxLevel);
  try
    FNodes.Add(NodeID, Node);
  except
    Node.Free; // If dictionary insertion fails, clean up
    raise;
  end;

  // If it's the first node, it becomes the entry point
  if FEntryPoint = -1 then
  begin
    FEntryPoint := NodeID;
    FEntryLevel := Level;
    Result := NodeID;
    Exit;
  end;

  // Insert into the HNSW structure (original code is kept)
  EntryPointCopy := FEntryPoint;
  CurrentLevel := FMaxLevel - 1;

  // Descend upper levels
  while CurrentLevel > Level do
  begin
    W := SearchLayer(Point, EntryPointCopy, CurrentLevel, 1);
    try
      if W.Count > 0 then
        EntryPointCopy := W[0];
    finally
      W.Free;
    end;
    Dec(CurrentLevel);
  end;

  // Insert into target levels
  while CurrentLevel >= 0 do
  begin
    W := SearchLayer(Point, EntryPointCopy, CurrentLevel, FEfConstruction);
    try
      for i in W do
      begin
        InsertConnection(Node, CurrentLevel, i);
        InsertConnection(FNodes[i], CurrentLevel, NodeID);
      end;
      if W.Count > 0 then
        EntryPointCopy := W[0];
    finally
      W.Free;
    end;
    Dec(CurrentLevel);
  end;

  // Update entry point if this node has more levels

  if Level > FEntryLevel then
  begin
    FEntryPoint := NodeID;
    FEntryLevel := Level;
  end;

  Result := NodeID;
end;

procedure THNSWIndex.BuildIndex(Points: TRagItems);
var
  i: Integer;
  Point: TAiEmbeddingNode;
begin
  if not Assigned(Points) then
    raise Exception.Create('THNSWIndex.BuildIndex: Points cannot be nil');

  // ========================================================================
  // STEP 1: Clear the previous index
  // ========================================================================
  // CRITICAL: This prevents memory leaks if BuildIndex is called 2+ times
  Clear;

  // ========================================================================
  // STEP 2: Assign the reference to the data
  // ========================================================================

  inherited BuildIndex(Points); // Assigns FDataVec and FActive := True

  // ========================================================================
  // STEP 3: Build the HNSW graph
  // ========================================================================
  // Optimization: Pre-allocate capacity if your Delphi version supports it
  // FNodes.Capacity := Points.Count; // Not available in all versions

  for i := 0 to Points.Count - 1 do
  begin
    Point := Points.Items[i];
    Add(Point);
  end;

  // The index is now active (inherited already marked it)
end;

function THNSWIndex.Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double): TRagItems;
var
  CurrentLevel: Integer;
  EntryPointCopy: Integer;
  W: TList<Integer>;
  ResultList: TList<TPair<Double, Integer>>;
  i: Integer;
  Distance: Double;
  Node: THNSWNode;
begin
  Result := TRagItems.Create;

  if FEntryPoint = -1 then
    Exit;

  ResultList := TList < TPair < Double, Integer >>.Create;
  try
    EntryPointCopy := FEntryPoint;
    CurrentLevel := FMaxLevel - 1;

    while CurrentLevel >= 0 do
    begin
      W := SearchLayer(Target, EntryPointCopy, CurrentLevel, 1);
      try
        if W.Count > 0 then
          EntryPointCopy := W[0];
      finally
        W.Free;
      end;
      Dec(CurrentLevel);
    end;

    // W := SearchLayer(Target, EntryPointCopy, 0, aLimit * 2);

    W := SearchLayer(Target, EntryPointCopy, 0, Max(100, aLimit * 2));

    try
      for i in W do
      begin
        Node := FNodes[i];
        Distance := TAiEmbeddingNode.CosineSimilarity(Target, Node.Vector);
        if Distance >= aPrecision then
          ResultList.Add(TPair<Double, Integer>.Create(Distance, i));
      end;

      ResultList.Sort(TComparer < TPair < Double, Integer >>.Construct(
        function(const Left, Right: TPair<Double, Integer>): Integer
        begin
          if Left.Key > Right.Key then
            Result := -1
          else if Left.Key < Right.Key then
            Result := 1
          else
            Result := 0;
        end));

      for i := 0 to Min(aLimit - 1, ResultList.Count - 1) do
      begin
        Node := FNodes[ResultList[i].Value];
        Node.Vector.Idx := ResultList[i].Key;
        Result.Add(Node.Vector);
      end;
    finally
      W.Free;
    end;
  finally
    ResultList.Free;
  end;
end;


{ TAIBm25Index }

constructor TAIBm25Index.Create;
begin
  inherited Create;
  FInvertedIndex := TDictionary < string, TList < TWordOccurrence >>.Create;
  FDocLengths := TDictionary<TAiEmbeddingNode, Integer>.Create;
{$IF CompilerVersion >= 36}
  FStopWords := THashSet<string>.Create;
{$ELSE}
  FStopWords := TDictionary<string, Boolean>.Create;
{$ENDIF}
  FAvgDocLength := 0;
  Language := alSpanish; // Default
end;

destructor TAIBm25Index.Destroy;
var
  List: TList<TWordOccurrence>;
begin
  for List in FInvertedIndex.Values do
    List.Free;
  FInvertedIndex.Free;
  FDocLengths.Free;
  inherited;
end;

procedure TAIBm25Index.LoadDefaultStopWords(Lang: TAiLanguage);
const
  S_ES = 'el,la,lo,los,las,un,una,unos,unas,de,del,al,y,o,u,e,ni,que,en,a,ante,bajo,con,contra,desde,donde,durante,' +
         'este,esta,estos,estas,ese,esa,esos,esas,aquel,aquella,aquellos,aquellas,mi,tu,su,nuestro,vuestro,' +
         'me,te,se,nos,os,le,les,ser,estar,haber,tener,hacer,hay,he,ha,han,son,es,fue,sido,' +
         'está,están,estaba,como,más,pero,por,para,sin,sobre,también,muy,ya,sí,no,cuando,si,entre';
  S_EN = 'the,a,an,and,or,but,if,then,else,when,at,from,by,for,with,about,against,between,into,through,' +
         'during,before,after,above,below,to,of,in,is,are,was,were,be,been,being,have,has,had,' +
         'do,does,did,will,would,should,could,may,might,can,this,that,these,those,i,you,he,she,it,we,they,me,him,her,us,them';
var
  S: string;
  Words: TArray<string>;
  W, CleanWord: string;
begin
  FStopWords.Clear;

  case Lang of
    alSpanish:
      S := S_ES;
    alEnglish:
      S := S_EN;
  else
    S := '';
  end;

  if S <> '' then
  begin
    Words := S.Split([',']);
    for W in Words do
    begin
      CleanWord := W.Trim.ToLower;
      if CleanWord <> '' then
{$IF CompilerVersion >= 36}
        FStopWords.Add(CleanWord);
{$ELSE}
        FStopWords.AddOrSetValue(CleanWord, True);
{$ENDIF}
    end;
  end;
end;

procedure TAIBm25Index.Clear;
var
  List: TList<TWordOccurrence>;
begin
  for List in FInvertedIndex.Values do
    List.Free;
  FInvertedIndex.Clear;
  FDocLengths.Clear;
  FAvgDocLength := 0;
end;

procedure TAIBm25Index.Tokenize(const aText: string; aList: TStrings);
var
  Words: TArray<string>;
  W: string;
begin
  aList.Clear;
  if aText.IsEmpty then
    Exit;

  // Split with extended delimiters (including Spanish special characters)
  Words := aText.ToLower.Split([' ', '.', ',', ';', ':', '-', '_', '(', ')', '[', ']', '{', '}', '"', '¿', '?', '¡', '!', '/', '\', '|', #13, #10, #9], // Added TAB (#9)
  TStringSplitOptions.ExcludeEmpty);

  for W in Words do
  begin
    // Minimum length filter and stop words (using HashSet for O(1))
{$IF CompilerVersion >= 36}
    if (W.Length > 2) and not FStopWords.Contains(W) then
{$ELSE}
    if (W.Length > 2) and not FStopWords.ContainsKey(W) then
{$ENDIF}
    begin
      // OPTIONAL: Basic lemmatization to improve searches
      // if W.EndsWith('s') and (W.Length > 3) then
      // W := W.Substring(0, W.Length - 1);

      aList.Add(W);
    end;
  end;
end;

procedure TAIBm25Index.AddNode(aNode: TAiEmbeddingNode);
var
  Tokens: TStringList;
  WordCounts: TDictionary<string, Integer>;
  W: string;
  OccurList: TList<TWordOccurrence>;
  Occur: TWordOccurrence;
  TotalDocs, CurrentCount: Integer;
begin
  if aNode.Text.IsEmpty then
    Exit;

  Tokens := TStringList.Create;
  WordCounts := TDictionary<string, Integer>.Create;
  try
    Tokenize(aNode.Text, Tokens);
    if Tokens.Count = 0 then
      Exit;

    // 1. Count word frequencies in this document
    for W in Tokens do
    begin
      // TryGetValue is the most efficient way:
      // Attempts to get the value in 'CurrentCount'. Returns True if it exists.
      if WordCounts.TryGetValue(W, CurrentCount) then
      begin
        // CASE A: Already exists.
        // Increment the value we retrieved and overwrite it.
        WordCounts[W] := CurrentCount + 1;
      end
      else
      begin
        // CASE B: Does not exist.
        // Explicitly ADD it with value 1.
        WordCounts.Add(W, 1);
      end;
    end;

    // 2. Record document length
    FDocLengths.Add(aNode, Tokens.Count);

    // 3. Update the inverted index
    for W in WordCounts.Keys do
    begin
      if not FInvertedIndex.TryGetValue(W, OccurList) then
      begin
        OccurList := TList<TWordOccurrence>.Create;
        FInvertedIndex.Add(W, OccurList);
      end;

      Occur.Node := aNode;
      Occur.Count := WordCounts[W];
      OccurList.Add(Occur);
    end;

    // 4. Recalculate the average length of all documents
    TotalDocs := FDocLengths.Count;
    FAvgDocLength := ((FAvgDocLength * (TotalDocs - 1)) + Tokens.Count) / TotalDocs;

  finally
    WordCounts.Free;
    Tokens.Free;
  end;
end;

function TAIBm25Index.Search(const aQuery: string; aLimit: Integer; aFilter: TAiFilterCriteria = nil): TList<TPair<Double, TAiEmbeddingNode>>;
const
  k1 = 1.2; // Saturation frequency
  B = 0.75; // Length penalty
var
  QueryTokens: TStringList;
  QW: string;
  OccurList: TList<TWordOccurrence>;
  Occur: TWordOccurrence;
  Scores: TDictionary<TAiEmbeddingNode, Double>;
  N, n_q, f_q_d: Integer;
  IDF, Score, D_len: Double;
  Pair: TPair<TAiEmbeddingNode, Double>;
begin
  Result := TList < TPair < Double, TAiEmbeddingNode >>.Create;

  // 1. Initial validations
  if aQuery.IsEmpty or (FDocLengths.Count = 0) then
    Exit;

  QueryTokens := TStringList.Create;
  Scores := TDictionary<TAiEmbeddingNode, Double>.Create;
  try
    // 2. Tokenize the query
    Tokenize(aQuery, QueryTokens);
    if QueryTokens.Count = 0 then
      Exit;

    // N = total number of documents
    N := FDocLengths.Count;

    // 3. Process each token (OR logic)
    for QW in QueryTokens do
    begin
      if FInvertedIndex.TryGetValue(QW, OccurList) then
      begin
        // n_q = documents containing the term
        n_q := OccurList.Count;

        // Probabilistic IDF (RSJ)
        IDF := Ln((N - n_q + 0.5) / (n_q + 0.5) + 1.0);

        // Traverse occurrences
        for Occur in OccurList do
        begin
          // --- PRE-FILTERING WITH CRITERIA ---
          if Assigned(aFilter) and (aFilter.Count > 0) then
          begin
            // New centralized method
            if not Occur.Node.MetaData.Matches(aFilter) then
              Continue;
          end;
          // ---------------------------------

          // Term frequency in the document
          f_q_d := Occur.Count;

          // Document length
          D_len := FDocLengths[Occur.Node];

          // BM25
          Score := IDF * (f_q_d * (k1 + 1)) / (f_q_d + k1 * (1 - B + B * (D_len / FAvgDocLength)));

          // Accumulate score
          if Scores.ContainsKey(Occur.Node) then
            Scores[Occur.Node] := Scores[Occur.Node] + Score
          else
            Scores.Add(Occur.Node, Score);
        end;
      end;
    end;

    // 4. Convert to list
    for Pair in Scores do
      Result.Add(TPair<Double, TAiEmbeddingNode>.Create(Pair.Value, Pair.Key));

    // 5. Sort by score descending
    Result.Sort(TComparer < TPair < Double, TAiEmbeddingNode >>.Construct(
      function(const L, R: TPair<Double, TAiEmbeddingNode>): Integer
      begin
        Result := CompareValue(R.Key, L.Key);
      end));

    // 6. Limit results
    if (aLimit > 0) and (Result.Count > aLimit) then
      Result.Count := aLimit;

  finally
    Scores.Free;
    QueryTokens.Free;
  end;
end;

procedure TAIBm25Index.SetLanguage(const Value: TAiLanguage);
begin
  if FLanguage <> Value then
  begin
    FLanguage := Value;
    if FLanguage <> alCustom then
      LoadDefaultStopWords(FLanguage);
  end;
end;


end.
