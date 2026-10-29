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
// Name: Gustavo Enr�quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.RAG.Vectors;

interface

uses
  System.SysUtils, System.Math, System.Generics.Collections, System.Variants, System.StrUtils,
  System.Generics.Defaults, System.Classes, System.JSon, Rest.JSon, System.SyncObjs,
  System.NetEncoding, System.Hash,

   uMakerAi.RAG.Vectors.Index,  uMakerAi.RAG.Vectors.VQL,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Embeddings.Core, uMakerAi.RAG.MetaData;

type

  /// ---------------------------------------------------------------------------
  /// TAiEmbeddingNode identifies an embedding, including the length
  /// the model and the data, additionally allows comparing two embeddings
  /// to know their cosine similarity, converts from json to vector and from
  /// vector to json
  /// also stores the original text data of the embedding
  /// -------------------------------------------------------------------------


  TAiRAGVector = Class;

  TOnDataVecAddItem = Procedure(Sender: TObject; aItem: TAiEmbeddingNode; MetaData: TAiEmbeddingMetaData; Var Handled: Boolean) of object;
  TOnDataVecSearch = procedure(Sender: TObject; Target: TAiEmbeddingNode; const aPrompt: string; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria; var aDataVec: TAiRAGVector; var Handled: Boolean) of object;
  TOnImportProgress = procedure(Sender: TObject; Position, Total: Integer; var Cancel: Boolean) of object;



  /// ---------------------------------------------------------------------------
  /// TAIBasicEmbeddingIndex simple implementation of an embedding index
  /// which is assigned by default to the vector to perform in-memory searches
  /// however there are more efficient ways to control this in vectors of
  /// embeddings.
  /// -------------------------------------------------------------------------




  /// ---------------------------------------------------------------------------
  /// THNSWIndex implements an Approximate Nearest Neighbors (ANN) using the algorithm
  /// HNSW (Hierarchical Navigable Small World) which is much more efficient in the search
  /// in embedding vectors
  /// -------------------------------------------------------------------------




  TAiSearchOptions = class(TPersistent)
  private
    FUseEmbeddings: Boolean;
    FUseBM25: Boolean;
    FUseRRF: Boolean;
    FUseReorderABC: Boolean;
    FBM25Weight: Double;
    FEmbeddingWeight: Double;
    FOnChange: TNotifyEvent;
    FMinAbsoluteScoreEmbedding: Double;
    FMinAbsoluteScoreBM25: Double;
    procedure SetUseEmbeddings(const Value: Boolean);
    procedure SetUseBM25(const Value: Boolean);
    procedure SetUseRRF(const Value: Boolean);
    procedure SetUseReorderABC(const Value: Boolean);
    procedure SetBM25Weight(const Value: Double);
    procedure SetEmbeddingWeight(const Value: Double);
    procedure Changed;
  public
    constructor Create;
    procedure Assign(Source: TPersistent); override;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    property UseEmbeddings: Boolean read FUseEmbeddings write SetUseEmbeddings default True;
    property UseBM25: Boolean read FUseBM25 write SetUseBM25 default True;
    property UseRRF: Boolean read FUseRRF write SetUseRRF default False;
    property UseReorderABC: Boolean read FUseReorderABC write SetUseReorderABC default False;
    property BM25Weight: Double read FBM25Weight write SetBM25Weight; // Default 0.7
    property EmbeddingWeight: Double read FEmbeddingWeight write SetEmbeddingWeight; // Default 0.3
    property MinAbsoluteScoreEmbedding: Double read FMinAbsoluteScoreEmbedding write FMinAbsoluteScoreEmbedding;
    property MinAbsoluteScoreBM25: Double read FMinAbsoluteScoreBM25 write FMinAbsoluteScoreBM25;

  end;

  TAiVectorStoreDriverBase = class(TComponent)
  public
    // Driver contract — each implementation overrides these methods
    procedure Add(const aNode: TAiEmbeddingNode; const AEntidad: string); virtual; abstract;
    function Search(const ATarget: TAiEmbeddingNode; const AEntidad: string; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria; Options: TAiSearchOptions): TAiRAGVector; virtual; abstract;
    procedure Delete(const aID, AEntidad: string); virtual; abstract;
    procedure Clear(const AEntidad: string); virtual; abstract;
    // Common helpers
    function EmbeddingToString(const AData: TAiEmbeddingData): string;
    function VariantToJSONValue(const V: Variant): TJSONValue;
  end;

  /// Plug-in semantic reranker in TAiRAGVector.Reranker. Receives the
  /// query and the text of each candidate, and returns a score per text in
  /// the same order: 0..1 = relevance; negative = always discard (e.g., a
  /// passage with prompt injection). Implementation with Jev: TAiJevRAGReranker.
  TAiRAGRerankerBase = class(TComponent)
  private
    FMinScore: Double;
  public
    function Score(const AQuery: string; const ATexts: TArray<string>): TArray<Double>; virtual; abstract;
  published
    // After reranking, candidates below the threshold are discarded (0 = keep all)
    property MinScore: Double read FMinScore write FMinScore;
  end;

  /// ---------------------------------------------------------------------------
  /// TAiDataVec is the base class that allows storing sets of embeddings
  /// it is used both to represent in-memory embedding databases
  /// as well as for connecting to embedding databases.
  /// By itself it does not index or search, it is only the container; to search
  /// it is necessary to add a TAIEmbeddingIndex, although by default it has
  /// a basic search index, but there are better models.
  /// -------------------------------------------------------------------------
  TAiRAGVector = Class(TComponent)
  Private
    FActive: Boolean;
    FRagIndex: TAIEmbeddingIndex;
    FEmbeddings: TAiEmbeddingsCore;
    FItems: TList<TAiEmbeddingNode>;
    FOnDataVecAddItem: TOnDataVecAddItem;
    FOnDataVecSearch: TOnDataVecSearch;
    FDim: Integer;
    FModel: String;
    FNameVec: String;
    FDescription: String;
    FInMemoryIndexType: TAiRagIndexType;
    FOnGetEmbedding: TOnGetEmbedding;
    FOnFilterItem: TOnFilterItem;
    FBm25Index: TAIBm25Index; // The in-memory lexical index
    FLock: TMultiReadExclusiveWriteSynchronizer;
    FDriver: TAiVectorStoreDriverBase;
    FEntidad: string;
    FOwnsObjects: Boolean;
    FOnImportProgress: TOnImportProgress;
    FSearchOptions: TAiSearchOptions;
    FReranker: TAiRAGRerankerBase;
    procedure SetReranker(const Value: TAiRAGRerankerBase);
    procedure SetActive(const Value: Boolean);
    procedure SetRagIndex(const Value: TAIEmbeddingIndex);
    procedure SetEmbeddings(const Value: TAiEmbeddingsCore);
    function GetItems: TList<TAiEmbeddingNode>;
    procedure SetOnDataVecAddItem(const Value: TOnDataVecAddItem);
    procedure SetOnDataVecSearch(const Value: TOnDataVecSearch);
    procedure SetDescription(const Value: String);
    procedure SetNameVec(const Value: String);
    procedure SetInMemoryIndexType(const Value: TAiRagIndexType);
    function ReciprocalRankFusion(VectorResults: TList<TAiSearchResult>; LexicalResults: TList<TPair<Double, TAiEmbeddingNode>>; aLimit: Integer): TAiRAGVector;

    function GetLexicalLanguage: TAiLanguage;
    procedure SetLexicalLanguage(const Value: TAiLanguage);
    procedure SetDriver(const Value: TAiVectorStoreDriverBase);
    procedure SetSearchOptions(const Value: TAiSearchOptions);
    // VQL advanced post-processing
    function  ApplyMMR(ASource: TAiRAGVector; ALambda: Double; ALimit: Integer): TAiRAGVector;
    procedure ApplyDistinct(AVector: TAiRAGVector; const AField: string);
    procedure DropNode(AVector: TAiRAGVector; AIndex: Integer);
    procedure ApplyOrderBy(AVector: TAiRAGVector; AFields: TList<TOrderByField>);
    function  BuildExplainOutput(AReq: TVGQLRequest): string;
    function  BuildExtendedContextText(DataVec: TAiRAGVector; AReq: TVGQLRequest): string;
  Protected

    function DoOnGetEmbedding(aInput, aUser: String; aDimensions: Integer = -1; aModel: String = ''; aEncodingFormat: String = 'float'): TAiEmbeddingData;
    procedure InternalInit(AOwnsObjects: Boolean);
    procedure CheckIndexes;

    function InternalSearchSafe(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TList<TAiSearchResult>;
    function FilterByCriteria(const aCriteria: TAiFilterCriteria): TAiRAGVector;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function WeightedScoreFusion(VectorResults: TList<TAiSearchResult>; LexicalResults: TList<TPair<Double, TAiEmbeddingNode>>; aLimit: Integer): TAiRAGVector;
    procedure ApplyContextReordering(Vector: TAiRAGVector);
    procedure InternalNormalizeVector(aList: TList<TAiSearchResult>);
    procedure InternalNormalizeLexical(aList: TList < TPair < Double, TAiEmbeddingNode >> );

  Public
    Constructor Create(aOwner: TComponent; AOwnsObjects: Boolean); Reintroduce; Overload;
    Constructor Create(aOwner: TComponent); Overload; Override;

    Destructor Destroy; Override;

    Procedure SaveToStream(Stream: TMemoryStream);
    Function LoadFromStream(Stream: TStream): Integer;

    Procedure SaveToFile(FileName: String);
    Function LoadFromFile(FileName: String): Integer;
    Function Connect(aHost, aPort, aLogin, aPassword: String): Boolean;

    Function Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TAiRAGVector; Overload; // Final
    Function Search(Prompt: String; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TAiRAGVector; Overload; // Final

    Function SearchText(aPrompt: String; aLimit: Integer = 10; aPrecision: Double = 0.5; aFilter: TAiFilterCriteria = nil; IncludeMetadata: Boolean = True; IncludeScore: Boolean = True): String; Overload; Virtual;
    Function SearchText(aPrompt: TAiEmbeddingNode; aLimit: Integer = 10; aPresicion: Double = 0.5; aFilter: TAiFilterCriteria = nil; IncludeMetadata: Boolean = True; IncludeScore: Boolean = True): String; Overload; Virtual;

    function ExecuteVQL(const AVqlQuery: string): string; overload;

    function ExecuteVQL(const AVqlQuery: string; out AResultVector: TAiRAGVector): string; overload;

    function ExecuteRequest(ARequest: TVGQLRequest; out AResultVector: TAiRAGVector): string;

    Function VectorToContextText(DataVec: TAiRAGVector; IncludeMetadata: Boolean; IncludeScore: Boolean): String;

    procedure BuildIndex;
    procedure BuildLexicalIndex;

    function AddItem(aItem: TAiEmbeddingNode): string; overload;
    Function AddItem(aItem: TAiEmbeddingNode; MetaData: TAiEmbeddingMetaData): NativeInt; Overload; Virtual;
    Function AddItem(aText: String; MetaData: TAiEmbeddingMetaData = Nil): TAiEmbeddingNode; Overload; Virtual;

    Function AddItemsFromJSonArray(aJSonArray: TJSonArray; MetaData: TAiEmbeddingMetaData = Nil): Integer; Virtual;
    Function AddItemsFromPlainText(aText: String; MetaData: TAiEmbeddingMetaData; aLenChunk: Integer; aOverlapPct: Integer): Integer; Virtual;

    Function CreateEmbeddingNode(aText: String; aEmbeddings: TAiEmbeddingsCore = Nil): TAiEmbeddingNode;
    Function Count: Integer;
    Procedure Clear;

    procedure RegenerateAll(const aNewModel: String = ''); virtual;
    procedure Rerank(Target: TAiEmbeddingNode; aAutoRegenerate: Boolean = True); overload;
    procedure Rerank(NewPrompt: String; aAutoRegenerate: Boolean = True); overload;
    // Reorders with a semantic reranker: Idx := score and descending order.
    // Does not discard nodes (negative ones end up at the end); that is decided by the caller.
    procedure RerankWith(const AQuery: String; AReranker: TAiRAGRerankerBase);
    function FilterByMetaData(const aCriteria: TAiEmbeddingMetaData): TAiRAGVector;

    Property RagIndex: TAIEmbeddingIndex read FRagIndex write SetRagIndex;
    Property Active: Boolean read FActive write SetActive;
    Property Items: TList<TAiEmbeddingNode> read GetItems;
  Published
    Property OnDataVecAddItem: TOnDataVecAddItem read FOnDataVecAddItem write SetOnDataVecAddItem;
    Property OnDataVecSearch: TOnDataVecSearch read FOnDataVecSearch write SetOnDataVecSearch;
    Property OnGetEmbedding: TOnGetEmbedding read FOnGetEmbedding write FOnGetEmbedding;
    property OnFilterItem: TOnFilterItem read FOnFilterItem write FOnFilterItem;
    // Second semantic stage for RERANK in VQL (Req.RerankQuery). If it is
    // assigned it replaces rerank with cosine; if it fails, cosine is used.
    property Reranker: TAiRAGRerankerBase read FReranker write SetReranker;
    Property OnImportProgress: TOnImportProgress read FOnImportProgress write FOnImportProgress;

    Property Embeddings: TAiEmbeddingsCore read FEmbeddings write SetEmbeddings;
    Property Model: String read FModel;
    Property Dim: Integer read FDim;
    Property NameVec: String read FNameVec write SetNameVec;
    Property Description: String read FDescription write SetDescription;
    Property InMemoryIndexType: TAiRagIndexType read FInMemoryIndexType write SetInMemoryIndexType default TAIHNSWIndex;
    property LexicalLanguage: TAiLanguage read GetLexicalLanguage write SetLexicalLanguage;
    property Driver: TAiVectorStoreDriverBase read FDriver write SetDriver;
    property Entidad: string read FEntidad write FEntidad;
    Property OwnsObjects: Boolean read FOwnsObjects write FOwnsObjects;
    Property SearchOptions: TAiSearchOptions read FSearchOptions write SetSearchOptions;
  End;

procedure Register;

implementation

uses uMakerAi.Telemetry;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiRAGVector]);

end;


{ TOAiDataVec }

function TAiRAGVector.AddItem(aItem: TAiEmbeddingNode): string;
begin
  // Delegate to the main overload to avoid duplicating logic
  // and ensure all indexing steps are executed.
  AddItem(aItem, nil);

  // We return the Tag (GUID) as expected
  Result := aItem.Tag;
end;

function TAiRAGVector.AddItem(aItem: TAiEmbeddingNode; MetaData: TAiEmbeddingMetaData): NativeInt;
var
  Handled: Boolean;
begin
  Handled := False;

  FLock.BeginWrite;
  try
    // 1. Synchronize Metadata if passed externally
    if Assigned(MetaData) and (MetaData <> aItem.MetaData) then
      aItem.MetaData.Assign(MetaData);

    // 2. Notify the event (possibility of external handling)
    if Assigned(FOnDataVecAddItem) then
      FOnDataVecAddItem(Self, aItem, aItem.MetaData, Handled);

    // 3. L�gica de Inserci�n
    if Handled then
    begin
      // CRITICAL CORRECTION:
      // If the user set 'Handled', we assume that HE took ownership of the node.
      // We do NOT free it here. We return -1 indicating that this vector did not index it.
      Exit(-1);
    end;

    // A. Driver Persistence (Optional)
    // We add to the driver BUT we continue adding to memory so that
    // local hybrid searches work.
    if Assigned(FDriver) then
    begin
      FDriver.Add(aItem, FEntidad);
      // No salimos aqu�, continuamos para poblar la memoria cach�/�ndice
    end;

    // B. Storage in Main List (Memory)
    Result := FItems.Add(aItem);

    // C. Lexical Indexing (BM25)
    if FSearchOptions.FUseBM25 then
      FBm25Index.AddNode(aItem);

    // D. Vector Indexing (HNSW / Basic)
    // CORRECTION: Previously this was missing in the first overload
    if Assigned(FRagIndex) then
      FRagIndex.Add(aItem);

    // E. Update container metadata (Model/Dimension)
    // Only if it is the first item or to maintain consistency
    if FItems.Count = 1 then
    begin
      FModel := aItem.Model;
      FDim := aItem.Dim;
    end;

  finally
    FLock.EndWrite;
  end;
end;

function TAiRAGVector.AddItem(aText: string; MetaData: TAiEmbeddingMetaData = Nil): TAiEmbeddingNode;
var
  vData: TAiEmbeddingData;
  AddedIndex: NativeInt;
begin
  if Trim(aText) = '' then
    raise Exception.Create('The text cannot be empty');

  // 1. Generate the Embedding
  if Assigned(FEmbeddings) then
    vData := FEmbeddings.CreateEmbedding(aText, 'user')
  else
    vData := DoOnGetEmbedding(aText, 'user');

  // 2. Create the Node
  Result := TAiEmbeddingNode.Create(Length(vData));
  try
    Result.Text := aText;
    Result.Data := vData; // This automatically calculates the Magnitude if you applied the previous optimization

    if Assigned(FEmbeddings) then
      Result.Model := FEmbeddings.Model
    else
      Result.Model := FModel;

    // 3. Assign Metadata
    if Assigned(MetaData) then
      Result.MetaData.Assign(MetaData);

    // 4. Register in the system by calling the Master Logic
    AddedIndex := Self.AddItem(Result, Result.MetaData);

    // 5. Post-attempt Memory Management
    if AddedIndex = -1 then
    begin
      // SPECIAL CASE:
      // We created the node, but AddItem returned -1 (Handled).
      // It means that TAiRAGVector did NOT take ownership of the object in its FItems list.
      // But since we just created the object here (Result := ...Create),
      // if we return it, the user must know that they are responsible for freeing it.

      // Option A (Safe): If it was Handled, we assume that the event took it.
      // We return Result as is.

      // Option B (Strict): If it was not added, we free it to avoid leaks if the user ignores the result.
      // Since it is a "Factory+Add", the normal thing is to return the created object even if it was not indexed locally.
      // We keep Result.
    end;

  except
    // If something fails during creation or embedding generation, free the partial node
    Result.Free;
    raise;
  end;
end;

function TAiRAGVector.AddItemsFromJSonArray(aJSonArray: TJSonArray; MetaData: TAiEmbeddingMetaData): Integer;
Var
  JVal: TJSONValue;
  Emb: TAiEmbeddingNode;
  i: Integer;
  TextToEmbed: String;
  Cancel: Boolean;
  TotalCount: Integer;
begin
  Result := 0;
  Cancel := False;
  i := 0;

  if (aJSonArray = nil) then
    Exit;

  TotalCount := aJSonArray.Count;

  For JVal in aJSonArray do
  Begin
    // ---> INICIO LOGICA DE PROGRESO <---
    if Assigned(FOnImportProgress) then
    begin
      // Report the current index 'i' out of the total
      FOnImportProgress(Self, i, TotalCount, Cancel);
      if Cancel then
        Break;
    end;
    // ---> FIN LOGICA DE PROGRESO <---

    // Extract clean text
    if JVal is TJSONString then
      TextToEmbed := JVal.Value
    else
      TextToEmbed := JVal.ToString;

    if not TextToEmbed.IsEmpty then
    begin
      Emb := AddItem(TextToEmbed, MetaData);
      if Assigned(Emb) then
      begin
        Emb.Orden := i;
        Inc(i);
        Inc(Result); // <--- CONTAMOS NODO CREADO
      end;
    end;
  End;

  // Final report 100%
  if Assigned(FOnImportProgress) and (not Cancel) then
    FOnImportProgress(Self, TotalCount, TotalCount, Cancel);
end;

function TAiRAGVector.AddItemsFromPlainText(aText: String; MetaData: TAiEmbeddingMetaData; aLenChunk: Integer; aOverlapPct: Integer): Integer;
const
  TOLERANCE_PCT = 0.15; // 15% tolerance to search for clean cuts
var
  TotalLen, StartPos, NextStartPos: Integer;
  IdealEnd, MaxEnd, MinEnd: Integer;
  CutPos: Integer;
  OverlapChars: Integer;
  ChunkText: String;
  Emb: TAiEmbeddingNode;
  i: Integer;
  Cancel: Boolean; // <--- NEW VARIABLE

  // Local function to find the best cut point with priorities
  function FindSmartCut(LimitStart, LimitEnd: Integer): Integer;
  var
    k: Integer;
    LastPeriod, LastSpace: Integer;
    C: Char;
  begin
    LastPeriod := -1;
    LastSpace := -1;

    // We iterate backwards from the maximum allowed limit
    // We look for the "farthest" possible cut that is semantically correct
    for k := LimitEnd downto LimitStart do
    begin
      if k > TotalLen then
        Continue;

      C := aText[k];

      // Priority 1: Line break (Paragraph)
      if (C = #10) or (C = #13) then
      begin
        Result := k;
        Exit; // We found the best possible cut, we exit.
      end;

      // Priority 2: End-of-sentence punctuation
      if CharInSet(C, ['.', '?', '!', ';']) and (LastPeriod = -1) then
        LastPeriod := k;

      // Priority 3: Space
      if (C = ' ') and (LastSpace = -1) then
        LastSpace := k;
    end;

    // Decision based on priorities if there was no line break
    if LastPeriod <> -1 then
      Result := LastPeriod
    else if LastSpace <> -1 then
      Result := LastSpace
    else
      Result := -1; // We found nothing clean
  end;

begin
  Result := 0; // <--- We initialize result
  Cancel := False; // <--- We initialize cancellation

  // --- 1. Validations ---
  if aLenChunk <= 10 then
    raise Exception.Create('The Chunk size is too small.');

  if (aOverlapPct < 0) or (aOverlapPct >= 100) then
    raise Exception.Create('Overlap percentage must be between 0 and 99.');

  // We normalize the text (remove extra spaces at start/end)
  aText := aText.Trim;
  TotalLen := aText.Length; // Note: If you use older Delphi versions use Length(aText)

  if TotalLen = 0 then
    Exit;

  // We calculate overlap length in characters
  OverlapChars := Round(aLenChunk * (aOverlapPct / 100));

  // If the overlap is absurd, we adjust it
  if OverlapChars >= aLenChunk then
    OverlapChars := aLenChunk - 1;

  StartPos := 1; // Delphi Strings are base-1
  i := 0;

  // --- 2. Chunking loop ---
  while StartPos <= TotalLen do
  begin
    // ---> INICIO LOGICA DE PROGRESO <---
    if Assigned(FOnImportProgress) then
    begin
      FOnImportProgress(Self, StartPos, TotalLen, Cancel);
      if Cancel then
        Break; // We exit the loop if the user cancels
    end;
    // ---> FIN LOGICA DE PROGRESO <---

    // We define the ideal search window
    IdealEnd := StartPos + aLenChunk;

    // If what remains is less than the chunk, we take all
    if IdealEnd > TotalLen then
    begin
      ChunkText := Copy(aText, StartPos, TotalLen - StartPos + 1);

      if ChunkText <> '' then
      begin
        if Assigned(Metadata) then
          Metadata.Properties['Posicion'] := I;
        Emb := AddItem(ChunkText, MetaData);
        if Assigned(Emb) then
        begin
          Emb.Orden := i;
          Inc(Result); // <--- CONTAMOS NODO CREADO
        end;
      end;
      Break; // We finish
    end;

    // We define tolerance range:
    // We will search from a little before to a little after IdealEnd
    MinEnd := IdealEnd - Round(aLenChunk * TOLERANCE_PCT);
    MaxEnd := IdealEnd + Round(aLenChunk * TOLERANCE_PCT);

    // We do not go out of the text
    if MaxEnd > TotalLen then
      MaxEnd := TotalLen;
    // We do not go back before the current start
    if MinEnd < StartPos then
      MinEnd := StartPos;

    // We look for the smart cut
    CutPos := FindSmartCut(MinEnd, MaxEnd);

    // If we do not find a natural cut, we force cut at IdealEnd
    if CutPos = -1 then
      CutPos := IdealEnd;

    // We extract the text
    // +1 in Length if we cut at an inclusive character, but Copy handles count
    ChunkText := Copy(aText, StartPos, CutPos - StartPos + 1).Trim;

    if ChunkText <> '' then
    begin
      if Assigned(Metadata) then
        Metadata.Properties['Posicion'] := I;

      Emb := AddItem(ChunkText, MetaData);
      if Assigned(Emb) then
      begin
        Emb.Orden := i;
        Inc(Result); // <--- CONTAMOS NODO CREADO
      end;
      Inc(i);
    end;

    // --- 3. Calculation of the next step ---
    // The new start is: Where we cut MINUS the overlap
    NextStartPos := (CutPos + 1) - OverlapChars;

    // ANTI-LOOP SAFETY:
    // We ensure we always advance at least 1 character from the current start
    if NextStartPos <= StartPos then
      NextStartPos := StartPos + 1;

    if (NextStartPos > 1) and (NextStartPos < TotalLen) then
    begin
      // While the previous character is not a separator (space, dot, newline),
      // it means we are inside a word. We go back.
      while (NextStartPos > StartPos + 1) and // Do not go back further than the previous start
        (not CharInSet(aText[NextStartPos - 1], [' ', #13, #10, '.', ',', ';', ':', '!', '?'])) do
      begin
        Dec(NextStartPos);
      end;
    end;
    // =========================================================================

    StartPos := NextStartPos;
  end; // End of While

  // Optional: Report 100% at the end if it was not cancelled
  if Assigned(FOnImportProgress) and (not Cancel) then
    FOnImportProgress(Self, TotalLen, TotalLen, Cancel);
end;

procedure TAiRAGVector.ApplyContextReordering(Vector: TAiRAGVector);
var
  ReorderedArr: array of TAiEmbeddingNode;
  i, LeftIdx, RightIdx: Integer;
begin
  // 1. Basic validations
  // If it is nil or has too few elements, it is not worth reordering
  if (Vector = nil) or (Vector.Count <= 2) then
    Exit;

  // 2. Initialize temporary structure
  // We use a dynamic array for fast access by index
  SetLength(ReorderedArr, Vector.Count);

  LeftIdx := 0; // Pointer to the beginning
  RightIdx := Vector.Count - 1; // Pointer to the end

  // 3. Distribution algorithm (Two-Pointers)
  // Expected input: [1.Best, 2.Good, 3.Average, 4.Bad, 5.Worst]
  for i := 0 to Vector.Count - 1 do
  begin
    if (i mod 2 = 0) then
    begin
      // EVEN indexes (0, 2, 4...) go to the LEFT SIDE.
      // i=0 (Best) -> Pos 0
      // i=2 (Average) -> Pos 1
      ReorderedArr[LeftIdx] := Vector.Items[i];
      Inc(LeftIdx);
    end
    else
    begin
      // ODD indexes (1, 3, 5...) go to the RIGHT SIDE.
      // i=1 (Good) -> Final Pos
      // i=3 (Bad) -> Final Pos - 1
      ReorderedArr[RightIdx] := Vector.Items[i];
      Dec(RightIdx);
    end;
  end;
  // Visual result: [Best, Average, Worst, Bad, Good]
  // LLM attention: [HIGH,  Medium,   Low, Medium, HIGH]

  // 4. Dump the result into the original vector
  // We clear the internal reference list.
  // IMPORTANT: We do NOT call Vector.Clear or free objects,
  // we only empty the pointer list to fill it again in the new order.
  Vector.Items.Clear;

  for i := 0 to High(ReorderedArr) do
    Vector.Items.Add(ReorderedArr[i]);

  // Automatic cleanup of the dynamic array when leaving the scope
end;

procedure TAiRAGVector.BuildIndex;
begin
  // 1. Validation of the Vector index
  if not Assigned(FRagIndex) then
    raise Exception.Create('No index is assigned');

  // 2. Build the Vector index (HNSW or Basic)
  FRagIndex.BuildIndex(Self.FItems);

  BuildLexicalIndex;

  FActive := True;
end;

procedure TAiRAGVector.BuildLexicalIndex;
var
  i: Integer;
begin
  if not Assigned(FBm25Index) then
    FBm25Index := TAIBm25Index.Create;

  // We block writes for safety
  FLock.BeginWrite;
  try
    // 1. Clear previous garbage
    FBm25Index.Clear;

    // 2. Iterate through all in-memory items and index them
    for i := 0 to FItems.Count - 1 do
    begin
      FBm25Index.AddNode(FItems[i]);
    end;
  finally
    FLock.EndWrite;
  end;
end;

procedure TAiRAGVector.CheckIndexes;
begin
  if not Assigned(FRagIndex) then
  begin
    case FInMemoryIndexType of
      TAIBasicIndex:
        FRagIndex := TAIBasicEmbeddingIndex.Create;
      TAIHNSWIndex:
        FRagIndex := THNSWIndex.Create;
      TAIEuclideanIndex:
        FRagIndex := TAIEuclideanDistanceIndex.Create;
    else
      FRagIndex := THNSWIndex.Create; // Safe fallback
    end;

    // Bind the index to the current data
    // IMPORTANT: Pass 'Self' explicitly
    if Assigned(FRagIndex) then
      FRagIndex.BuildIndex(Self.FItems);
  end;

  if not Assigned(FBm25Index) then
    FBm25Index := TAIBm25Index.Create;
end;

procedure TAiRAGVector.Clear;
var
  i: Integer;
begin
  FLock.BeginWrite; // Multithread protection
  try
    // 1. Free node memory if we are the owners
    if FOwnsObjects then
    begin
      for i := 0 to FItems.Count - 1 do
        FItems[i].Free;
    end;

    // 2. Empty the main list
    FItems.Clear;

    // 3. Clear the Lexical index (BM25)
    if Assigned(FBm25Index) then
      FBm25Index.Clear;

    // 4. Reset the Vector index (HNSW / Basic)
    // Since HNSW and other indexes tend to accumulate data and do not have a standard Clear method
    // in your current implementation, the safest and cleanest thing is to destroy and recreate it.
    if Assigned(FRagIndex) then
    begin
      FreeAndNil(FRagIndex);
      // CheckIndexes will recreate the empty index of the correct type (HNSW/Basic)
      CheckIndexes;
    end;

  finally
    FLock.EndWrite;
  end;
end;

function TAiRAGVector.Connect(aHost, aPort, aLogin, aPassword: String): Boolean;
begin
  // this function is not needed, it is deprecated
  If not Assigned(FRagIndex) then
    Raise Exception.Create('No index is assigned');

  // Result := FRagIndex.Connect(aHost, aPort, aLogin, aPassword);
  FActive := True;
  Result := True;
end;

function TAiRAGVector.Count: Integer;
begin
  if Assigned(FItems) then
    Result := FItems.Count
  else
    Result := 0;
end;

constructor TAiRAGVector.Create(aOwner: TComponent; AOwnsObjects: Boolean);
begin
  inherited Create(aOwner); // 1. Llamar al padre
  InternalInit(AOwnsObjects); // 2. Initialize with the passed value
end;

constructor TAiRAGVector.Create(aOwner: TComponent);
begin
  inherited Create(aOwner); // 1. Llamar al padre
  InternalInit(True); // 2. Initialize with the default value
end;

function TAiRAGVector.CreateEmbeddingNode(aText: String; aEmbeddings: TAiEmbeddingsCore): TAiEmbeddingNode;
Var
  Ar: TAiEmbeddingData;
begin
  If aEmbeddings = Nil then
    aEmbeddings := FEmbeddings;

  If aEmbeddings = Nil then
    Raise Exception.Create('You must specify an embeddings model first');

  Try
    Ar := aEmbeddings.CreateEmbedding(aText, 'user');
    Result := TAiEmbeddingNode.Create(1);
    Result.Text := aText;
    Result.Data := Ar;
    Result.Model := aEmbeddings.Model;
  Finally
  End;
end;

destructor TAiRAGVector.Destroy;
var
  i: Integer;
begin
  // 1. Mark as inactive immediately
  FActive := False;

  // 2. IMPORTANT: Do not use FLock.BeginWrite here.
  // The object is being destroyed; there must be no other threads accessing it.
  // If there are, it is an external design error. Using the lock here usually causes exceptions.

  // 3. Free indexes FIRST
  // The indexes contain pointers to the Items. We must destroy the indexes
  // while the Items still exist in memory to avoid orphan pointers.
  FreeAndNil(FBm25Index);
  FreeAndNil(FRagIndex);

  // 4. Free the Items list and its objects
  if Assigned(FItems) then
  begin
    if FOwnsObjects then
    begin
      for i := 0 to FItems.Count - 1 do
        FItems[i].Free; // Free each node
    end;
    FreeAndNil(FItems); // Free the list
  end;

  // 5. Free the synchronization object at the end
  FreeAndNil(FLock);

  FSearchOptions.Free;

  // 6. Finally, the inherited part
  inherited Destroy;
end;

function TAiRAGVector.GetItems: TList<TAiEmbeddingNode>;
begin
  Result := FItems;
end;

function TAiRAGVector.GetLexicalLanguage: TAiLanguage;
begin
  If Assigned(FBm25Index) then
    Result := FBm25Index.Language
  Else
    Result := TAiLanguage.alSpanish;
end;

procedure TAiRAGVector.InternalInit(AOwnsObjects: Boolean);
begin
  FOwnsObjects := AOwnsObjects;

  // 1. Create container objects FIRST
  FLock := TMultiReadExclusiveWriteSynchronizer.Create;
  FItems := TList<TAiEmbeddingNode>.Create;
  FBm25Index := TAIBm25Index.Create;

  // 2. Set default values
  FSearchOptions := TAiSearchOptions.Create;
  FSearchOptions.UseEmbeddings := True;
  FSearchOptions.UseBM25 := False;
  FSearchOptions.UseRRF := False;
  FSearchOptions.UseReorderABC := False;

  FInMemoryIndexType := TAIHNSWIndex; // Ensures it matches the property 'default'

  // 3. Create the initial index
  // We do not call CheckIndexes here to avoid double checking; we do it explicitly
  FRagIndex := THNSWIndex.Create;
  FRagIndex.BuildIndex(Self.FItems);
end;


procedure TAiRAGVector.InternalNormalizeVector(aList: TList<TAiSearchResult>);
begin
  // The embeddings are already on a 0..1 scale (Cosine).
  // We do not apply Min-Max because 1.0 must be "real perfection", not "the best in the list".
  // We simply ensure there are no out-of-range values due to numerical error.
  for var i := 0 to aList.Count - 1 do
  begin
    var
    S := aList[i].Score;
    if S < 0 then
      S := 0;
    if S > 1 then
      S := 1;
    aList[i] := TAiSearchResult.Create(aList[i].Node, S);
  end;
end;

procedure TAiRAGVector.InternalNormalizeLexical(aList: TList < TPair < Double, TAiEmbeddingNode >> );
var
  MaxS: Double;
  i: Integer;
begin
  if aList.Count = 0 then
    Exit;

  // 1. Find the maximum BM25 score of this search
  MaxS := 0;
  for i := 0 to aList.Count - 1 do
    if aList[i].Key > MaxS then
      MaxS := aList[i].Key;

  // 2. We normalize against a "Theoretical Maximum" or a confidence value.
  // If MaxS is very small (e.g., 0.5), we do not raise it to 1.0.
  // We only divide by MaxS if MaxS is a robust score.

  // A standard technique is to divide by the current MaxS only if it is greater than 1,
  // or use a reference value so that a score of 1.0 is difficult to reach.
  for i := 0 to aList.Count - 1 do
  begin
    var
    NewScore := aList[i].Key;
    if MaxS > 0 then
      NewScore := NewScore / MaxS; // Now the best is 1.0, but only within its channel

    aList[i] := TPair<Double, TAiEmbeddingNode>.Create(NewScore, aList[i].Value);
  end;
end;

{ TAiRAGVector }

function TAiRAGVector.InternalSearchSafe(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TList<TAiSearchResult>;
var
  i: Integer;
  Emb: TAiEmbeddingNode;
  Score: Double;
  PassFilter: Boolean;
begin
  // Result list (the caller must free it)
  Result := TList<TAiSearchResult>.Create;
  try
    // Linear search / brute force
    for i := 0 to FItems.Count - 1 do
    begin
      Emb := FItems[i];

      // 1. FILTERING BY CRITERIA (pre-cosine)
      if Assigned(aFilter) and (aFilter.Count > 0) then
      begin
        // Centralized in MetaData
        if not Emb.MetaData.Matches(aFilter, Emb.Text) then
          Continue;
      end;

      // 2. FILTERING BY EVENT (optional, remains the same)
      if Assigned(FOnFilterItem) then
      begin
        PassFilter := True;
        FOnFilterItem(Self, Emb, PassFilter);
        if not PassFilter then
          Continue;
      end;

      // 3. SIMILARITY CALCULATION (thread-safe)
      Score := TAiEmbeddingNode.CosineSimilarity(Emb, Target);

      // 4. FILTERING BY PRECISION
      if (aPrecision > 0) and (Score < aPrecision) then
        Continue;

      // 5. ADD RESULT
      Result.Add(TAiSearchResult.Create(Emb, Score));
    end;

    // 6. SORT (highest score first)
    Result.Sort(TComparer<TAiSearchResult>.Construct(
      function(const Left, Right: TAiSearchResult): Integer
      begin
        Result := CompareValue(Right.Score, Left.Score);
      end));

    // 7. TRIM TOP-K
    while Result.Count > aLimit do
      Result.Delete(Result.Count - 1);

  except
    Result.Free;
    raise;
  end;
end;

function TAiRAGVector.DoOnGetEmbedding(aInput, aUser: String; aDimensions: Integer; aModel, aEncodingFormat: String): TAiEmbeddingData;
begin

  if Assigned(FOnGetEmbedding) then
    FOnGetEmbedding(Self, aInput, aUser, aModel, aEncodingFormat, aDimensions, Result)
  Else
    raise Exception.Create('The OnGetEmbedding event has not been assigned. The embedding cannot be generated.');

end;

function TAiRAGVector.ExecuteVQL(const AVqlQuery: string; out AResultVector: TAiRAGVector): string;
var
  Parser: TVGQLParser;
  AST: TVGQLQuery;
  Compiler: TVGQLCompiler;
  Req: TVGQLRequest;
begin
  Result := '';
  AResultVector := nil;
  Req := nil;

  // ---------------------------------------------------------------------------
  // 1. FRONT-END: SYNTAX PARSING (Text -> AST)
  // ---------------------------------------------------------------------------
  Parser := TVGQLParser.Create(AVqlQuery);
  try
    AST := Parser.Parse;
  finally
    Parser.Free;
  end;

  try
    // -------------------------------------------------------------------------
    // 2. MIDDLE-END: COMPILATION (AST -> Request Object)
    // -------------------------------------------------------------------------
    Compiler := TVGQLCompiler.Create;
    try
      Req := Compiler.Translate(AST);
    finally
      Compiler.Free;
      if Assigned(AST) then
        AST.Free;
    end;

    if not Assigned(Req) then
      Exit;

    Result := ExecuteRequest(Req, AResultVector);
  finally
    if Assigned(Req) then
      Req.Free;
  end;
end;

{ Executes an ALREADY COMPILED request. It is the back-end of ExecuteVQL, exposed separately
  for whoever compiles VQL on their own (e.g., to map the errors from
  parsing to HTTP codes) and does not want to reimplement the pipeline: reimplementing it
  means silently losing every clause that is not copied by hand.
  The request is NOT freed here: it belongs to the caller. }
function TAiRAGVector.ExecuteRequest(ARequest: TVGQLRequest; out AResultVector: TAiRAGVector): string;
const
  OVERFETCH_FACTOR = 3;
  OVERFETCH_MAX    = 100;
var
  Req: TVGQLRequest;
  TempOptions: TAiSearchOptions;
  i: Integer;
  MMRVector: TAiRAGVector;
  SavedEntidad: string;
  SearchLimit: Integer;
  NeedsRegen: Boolean;
begin
  Result := '';
  AResultVector := nil;
  Req := ARequest;
  if not Assigned(Req) then
    Exit;

  // ---------------------------------------------------------------------------
  // EXPLAIN: returns the execution plan without executing the search
  // ---------------------------------------------------------------------------
  if Req.Explain then
  begin
    Result := BuildExplainOutput(Req);
    Exit;
  end;

  // The compiled entity (MATCH clause) takes precedence for the duration of this query.
  // Without this, MATCH was parsed, compiled, and lost right here.
  SavedEntidad := FEntidad;
  try
    if Req.Entity <> '' then
      FEntidad := Req.Entity;

    // -------------------------------------------------------------------------
    // 3. BACK-END: DYNAMIC ENGINE CONFIGURATION
    // -------------------------------------------------------------------------
    TempOptions := TAiSearchOptions.Create;
    try
      TempOptions.UseEmbeddings := (Req.Mode = TSearchMode.smEmbeddings) or (Req.Mode = TSearchMode.smHybrid);
      TempOptions.UseBM25       := (Req.Mode = TSearchMode.smBM25) or (Req.Mode = TSearchMode.smHybrid);
      TempOptions.EmbeddingWeight := Req.WeightSemantic;
      TempOptions.BM25Weight      := Req.WeightLexical;
      TempOptions.UseRRF          := (Req.Fusion = TFusionMode.fmRRF);
      TempOptions.MinAbsoluteScoreEmbedding := Req.MinSemantic;
      TempOptions.MinAbsoluteScoreBM25      := Req.MinLexical;
      // ABC only if MMR is not used (they are alternative post-processing strategies)
      TempOptions.UseReorderABC := Req.UseReorderABC and not Req.UseMMR;
      Self.SearchOptions.Assign(TempOptions);

      // Language synchronization for BM25 -- now functional via LANGUAGE clause.
      // Only if the VQL includes it: the request's default value ('spanish') does not
      // should overwrite the language the consumer already configured on the component.
      // NOTE: this affects the in-memory BM25 index; a SQL driver has its
      // own to_tsvector language and it must be set in the driver.
      if Req.LanguageSpecified and not Req.Language.IsEmpty then
      begin
        if SameText(Req.Language, 'spanish')    then Self.LexicalLanguage := alSpanish
        else if SameText(Req.Language, 'english')    then Self.LexicalLanguage := alEnglish
        else if SameText(Req.Language, 'portuguese') then Self.LexicalLanguage := alPortuguese;
      end;

      // -----------------------------------------------------------------------
      // 4. EXECUTION OF THE MAIN VECTOR SEARCH
      // -----------------------------------------------------------------------
      // Reordering the top-K already returned by the search cannot rescue what was
      // left out of that top-K. When there is a second stage, more
      // candidates are brought in and trimmed to the requested LIMIT at the end (step 9b).
      SearchLimit := Req.Limit;
      if (Req.RerankQuery <> '') and (SearchLimit > 0) then
        SearchLimit := Min(SearchLimit * OVERFETCH_FACTOR, OVERFETCH_MAX);

      // OFFSET is applied to the already fetched result (step 9). Without requesting those
      // extra rows, skipping N returned LIMIT-N results instead of LIMIT, or
      // that is, the second page came out short and the last one empty.
      if (Req.Offset > 0) and (Req.Limit > 0) then
        SearchLimit := Max(SearchLimit, Req.Limit + Req.Offset);

      AResultVector := Self.Search(Req.Query, SearchLimit, Req.MinGlobal, Req.Filter);

      // -----------------------------------------------------------------------
      // 5. RERANK (second stage: deep semantic refinement)
      // -----------------------------------------------------------------------
      // 5a. Semantic reranker (TAiRAGVector.Reranker): scores each candidate
      //     against the query without touching embeddings. If it fails, cosine continues.
      var SemanticDone := False;
      if Assigned(FReranker) and Assigned(AResultVector) and (Req.RerankQuery <> '') and
         (AResultVector.Count > 0) then
        try
          AResultVector.RerankWith(Req.RerankQuery, FReranker);
          for i := AResultVector.Count - 1 downto 0 do
            if (AResultVector.Items[i].Idx < 0) or
               ((FReranker.MinScore > 0) and (AResultVector.Items[i].Idx < FReranker.MinScore)) then
              DropNode(AResultVector, i);
          SemanticDone := True;
        except
          SemanticDone := False; // falls back to the cosine rerank below
        end;

      if (not SemanticDone) and Assigned(AResultVector) and (Req.RerankQuery <> '') and
         (AResultVector.Count > 0) then
      begin
        AResultVector.Embeddings := Self.Embeddings;

        // Nodes coming from a driver already bring their vector, and from the same model
        // as the collection. Regenerating them meant paying for N embeddings per query to
        // reconstruct exactly what is already there. They are regenerated only if
        // truly necessary: a missing vector, one with zero magnitude (the node did not
        // survive the return trip), or one of another dimension is not usable for
        // cosine, and ranking with it would give a silently false order.
        NeedsRegen := False;
        for i := 0 to AResultVector.Count - 1 do
          if (Length(AResultVector.Items[i].Data) = 0) or
             (AResultVector.Items[i].MagnitudeValue <= 0) or
             (Assigned(FEmbeddings) and (FEmbeddings.Dimensions > 0) and
              (Length(AResultVector.Items[i].Data) <> FEmbeddings.Dimensions)) then
          begin
            NeedsRegen := True;
            Break;
          end;

        if (not NeedsRegen) and Assigned(FEmbeddings) and (AResultVector.Model <> '') and
           (not SameText(AResultVector.Model, FEmbeddings.Model)) then
          NeedsRegen := True;

        if NeedsRegen then
        begin
          AResultVector.RegenerateAll;
          AResultVector.BuildIndex;
        end;

        AResultVector.Rerank(Req.RerankQuery, Req.RerankRegenerate);

        // Re-apply the GLOBAL THRESHOLD after reranking: the new scores
        // (cosine similarity vs. the rerank query) may be lower than the threshold.
        if Req.MinGlobal > 0 then
          for i := AResultVector.Count - 1 downto 0 do
            if AResultVector.Items[i].Idx < Req.MinGlobal then
              DropNode(AResultVector, i);
      end;

      // -----------------------------------------------------------------------
      // 6a. OPTIMIZE MMR -- result diversification
      // -----------------------------------------------------------------------
      if Req.UseMMR and Assigned(AResultVector) and (AResultVector.Count > 1) then
      begin
        MMRVector := ApplyMMR(AResultVector, Req.MmrLambda, AResultVector.Count);
        // ApplyMMR returns the SAME nodes in another order, in a vector without
        // ownership. Freeing the original as is (which does have it, comes from a
        // driver) destroyed the nodes MMR had just selected and left
        // dangling pointers. Ownership is transferred before releasing it.
        MMRVector.OwnsObjects   := AResultVector.OwnsObjects;
        AResultVector.OwnsObjects := False;
        AResultVector.Free;
        AResultVector := MMRVector;
      end
      // -----------------------------------------------------------------------
      // 6b. OPTIMIZE REORDER ABC -- LLM context window optimization
      // -----------------------------------------------------------------------
      else if Assigned(AResultVector) and Req.UseReorderABC then
        ApplyContextReordering(AResultVector);

      // -----------------------------------------------------------------------
      // 7. DISTINCT ON field -- deduplication by metadata field
      // -----------------------------------------------------------------------
      if Assigned(AResultVector) and (Req.DistinctField <> '') then
        ApplyDistinct(AResultVector, Req.DistinctField);

      // -----------------------------------------------------------------------
      // 8. ORDER BY -- custom sorting
      // -----------------------------------------------------------------------
      if Assigned(AResultVector) and (Req.OrderByFields.Count > 0) then
        ApplyOrderBy(AResultVector, Req.OrderByFields);

      // -----------------------------------------------------------------------
      // 9. OFFSET -- pagination: skip the first N results
      // -----------------------------------------------------------------------
      if Assigned(AResultVector) and (Req.Offset > 0) then
        for i := 1 to Min(Req.Offset, AResultVector.Count) do
          DropNode(AResultVector, 0);

      // -----------------------------------------------------------------------
      // 9b. TRIM TO REQUESTED LIMIT -- closes the over-fetch from step 4
      // -----------------------------------------------------------------------
      if Assigned(AResultVector) and (Req.Limit > 0) then
        while AResultVector.Count > Req.Limit do
          DropNode(AResultVector, AResultVector.Count - 1);

      // -----------------------------------------------------------------------
      // 10. GENERATION OF THE FINAL OUTPUT FOR THE LLM
      // -----------------------------------------------------------------------
      if Assigned(AResultVector) then
      begin
        if Req.IncludeId or Req.IncludeRank or Req.IncludeModel then
          Result := BuildExtendedContextText(AResultVector, Req)
        else
          Result := VectorToContextText(AResultVector, Req.IncludeMetadata, Req.IncludeScore);
      end;

    finally
      TempOptions.Free;
    end;
  finally
    FEntidad := SavedEntidad;
  end;
end;

function TAiRAGVector.ApplyMMR(ASource: TAiRAGVector; ALambda: Double; ALimit: Integer): TAiRAGVector;
// Maximal Marginal Relevance: balances relevance vs. diversity in results.
// Formula: argmax_{d not in S} [ lambda * Rel(d) - (1-lambda) * max_{d' in S} Sim(d,d') ]
var
  Selected, Remaining: TList<TAiEmbeddingNode>;
  BestIdx: Integer;
  BestScore, Score, MaxSim, InterSim: Double;
  i, j: Integer;
  Item, SelItem: TAiEmbeddingNode;
begin
  Result := TAiRAGVector.Create(nil, False);
  if ASource.Count = 0 then Exit;

  // Clamp lambda to [0, 1]
  if ALambda < 0 then ALambda := 0;
  if ALambda > 1 then ALambda := 1;

  Selected  := TList<TAiEmbeddingNode>.Create;
  Remaining := TList<TAiEmbeddingNode>.Create;
  try
    for i := 0 to ASource.Count - 1 do
      Remaining.Add(ASource.Items[i]);

    while (Selected.Count < ALimit) and (Remaining.Count > 0) do
    begin
      BestIdx   := 0;
      BestScore := -MaxDouble;

      for i := 0 to Remaining.Count - 1 do
      begin
        Item := Remaining[i];

        // Diversity term: max cosine similarity to already-selected items
        if Selected.Count = 0 then
          MaxSim := 0
        else
        begin
          MaxSim := 0;
          for j := 0 to Selected.Count - 1 do
          begin
            SelItem  := Selected[j];
            InterSim := TAiEmbeddingNode.CosineSimilarity(Item, SelItem);
            if InterSim > MaxSim then
              MaxSim := InterSim;
          end;
        end;

        // MMR score: lambda * relevance - (1-lambda) * max_inter_similarity
        Score := ALambda * Item.Idx - (1.0 - ALambda) * MaxSim;
        if Score > BestScore then
        begin
          BestScore := Score;
          BestIdx   := i;
        end;
      end;

      Item := Remaining[BestIdx];
      Item.Idx := BestScore;  // update score to reflect MMR value
      Selected.Add(Item);
      Remaining.Delete(BestIdx);
    end;

    for i := 0 to Selected.Count - 1 do
      Result.Items.Add(Selected[i]);

    Result.FModel := ASource.FModel;
    Result.FDim   := ASource.FDim;
  finally
    Selected.Free;
    Remaining.Free;
  end;
end;

{ Removes a node from the result, freeing it if the vector owns it.
  Items is a flat TList<>: Items.Delete only removes the pointer, never frees.
  Drivers return vectors WITH ownership (Create(nil, True)), so each
  node discarded in the VQL post-processing (THRESHOLD, DISTINCT, OFFSET, LIMIT)
  was leaked in a long-lived server process. }
procedure TAiRAGVector.SetReranker(const Value: TAiRAGRerankerBase);
begin
  if FReranker = Value then
    Exit;
  if Assigned(FReranker) then
    FReranker.RemoveFreeNotification(Self);
  FReranker := Value;
  if Assigned(FReranker) then
    FReranker.FreeNotification(Self);
end;

procedure TAiRAGVector.RerankWith(const AQuery: String; AReranker: TAiRAGRerankerBase);
var
  Texts: TArray<string>;
  Scores: TArray<Double>;
  i: Integer;
begin
  if (FItems.Count = 0) or not Assigned(AReranker) then
    Exit;
  SetLength(Texts, FItems.Count);
  for i := 0 to FItems.Count - 1 do
    Texts[i] := FItems[i].Text;
  Scores := AReranker.Score(AQuery, Texts);
  if Length(Scores) <> FItems.Count then
    raise Exception.CreateFmt('RerankWith: the reranker returned %d scores for %d candidates',
      [Length(Scores), FItems.Count]);
  for i := 0 to FItems.Count - 1 do
    FItems[i].Idx := Scores[i];
  FItems.Sort(TComparer<TAiEmbeddingNode>.Construct(
    function(const Left, Right: TAiEmbeddingNode): Integer
    begin
      Result := CompareValue(Right.Idx, Left.Idx);
    end));
end;

procedure TAiRAGVector.DropNode(AVector: TAiRAGVector; AIndex: Integer);
var
  Node: TAiEmbeddingNode;
begin
  Node := AVector.Items[AIndex];
  AVector.Items.Delete(AIndex);
  if AVector.OwnsObjects then
    Node.Free;
end;

procedure TAiRAGVector.ApplyDistinct(AVector: TAiRAGVector; const AField: string);
// Keeps only the first occurrence of each unique value of AField.
// Items missing the field are all kept (treated as distinct).
var
  i: Integer;
  Seen: TDictionary<string, Boolean>;
  Item: TAiEmbeddingNode;
  FieldValue: Variant;
  StrVal: string;
  MissingCount: Integer;
begin
  Seen := TDictionary<string, Boolean>.Create;
  MissingCount := 0;
  try
    i := 0;
    while i < AVector.Count do
    begin
      Item := AVector.Items[i];

      if SameText(AField, 'id') or SameText(AField, 'tag') then
        StrVal := Item.Tag
      else if Assigned(Item.MetaData) and Item.MetaData.Has(AField) then
      begin
        FieldValue := Item.MetaData.Get(AField, Null);
        StrVal := VarToStr(FieldValue);
      end
      else
      begin
        // Items without the field each get a unique key so they are all kept
        StrVal := '__missing_' + IntToStr(MissingCount);
        Inc(MissingCount);
      end;

      if Seen.ContainsKey(StrVal) then
        DropNode(AVector, i)  // duplicate: remove, do not advance i
      else
      begin
        Seen.Add(StrVal, True);
        Inc(i);
      end;
    end;
  finally
    Seen.Free;
  end;
end;

procedure TAiRAGVector.ApplyOrderBy(AVector: TAiRAGVector; AFields: TList<TOrderByField>);
// Sorts AVector.Items according to the list of ORDER BY fields.
// Supports: 'score' (Idx), 'rank'/'orden' (Orden), 'model' (Model), 'id'/'tag' (Tag),
// and any metadata property name.
var
  LocalFields: TList<TOrderByField>;
  F: TOrderByField;
begin
  if (AVector = nil) or (AVector.Count <= 1) or (AFields.Count = 0) then
    Exit;

  // Copy fields into a local list so the anonymous method can safely capture it
  LocalFields := TList<TOrderByField>.Create;
  try
    for F in AFields do
      LocalFields.Add(F);

    AVector.Items.Sort(TComparer<TAiEmbeddingNode>.Construct(
      function(const Left, Right: TAiEmbeddingNode): Integer
      var
        k: Integer;
        LF: TOrderByField;
        LV, RV: Variant;
        Cmp: Integer;
      begin
        Result := 0;
        for k := 0 to LocalFields.Count - 1 do
        begin
          LF := LocalFields[k];

          // Resolve field value for Left and Right
          if SameText(LF.FieldName, 'score') then
          begin
            LV := Left.Idx;
            RV := Right.Idx;
          end
          else if SameText(LF.FieldName, 'rank') or SameText(LF.FieldName, 'orden') then
          begin
            LV := Left.Orden;
            RV := Right.Orden;
          end
          else if SameText(LF.FieldName, 'model') then
          begin
            LV := Left.Model;
            RV := Right.Model;
          end
          else if SameText(LF.FieldName, 'id') or SameText(LF.FieldName, 'tag') then
          begin
            LV := Left.Tag;
            RV := Right.Tag;
          end
          else
          begin
            LV := '';
            RV := '';
            if Assigned(Left.MetaData)  and Left.MetaData.Has(LF.FieldName)  then LV := Left.MetaData.Get(LF.FieldName, Null);
            if Assigned(Right.MetaData) and Right.MetaData.Has(LF.FieldName) then RV := Right.MetaData.Get(LF.FieldName, Null);
          end;

          // Compare values
          try
            if VarIsNumeric(LV) and VarIsNumeric(RV) then
            begin
              if Double(LV) < Double(RV) then Cmp := -1
              else if Double(LV) > Double(RV) then Cmp := 1
              else Cmp := 0;
            end
            else
              Cmp := AnsiCompareStr(VarToStr(LV), VarToStr(RV));
          except
            Cmp := 0;
          end;

          // Apply direction
          if LF.Direction = odDesc then
            Cmp := -Cmp;

          if Cmp <> 0 then
          begin
            Result := Cmp;
            Exit;
          end;
        end;
      end));
  finally
    LocalFields.Free;
  end;
end;

function TAiRAGVector.BuildExplainOutput(AReq: TVGQLRequest): string;
// Returns a human-readable description of the compiled VQL request
// without executing any search. Useful for debugging queries.
var
  SB: TStringBuilder;
  ModeStr, FusionStr, OptimStr, OrderStr: string;
  F: TOrderByField;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    case AReq.Mode of
      smHybrid:
        ModeStr := Format('HYBRID (Semantic: %.0f%% | Lexical: %.0f%%)',
          [AReq.WeightSemantic * 100, AReq.WeightLexical * 100]);
      smEmbeddings: ModeStr := 'EMBEDDINGS only';
      smBM25:       ModeStr := 'BM25 (lexical) only';
    else             ModeStr := 'HYBRID';
    end;

    if AReq.Fusion = fmRRF then FusionStr := 'RRF' else FusionStr := 'Weighted Score Fusion';

    if AReq.UseMMR then
      OptimStr := Format('MMR (lambda=%.2f)', [AReq.MmrLambda])
    else if AReq.UseReorderABC then
      OptimStr := 'REORDER ABC'
    else
      OptimStr := '(none)';

    if AReq.OrderByFields.Count = 0 then
      OrderStr := '(default: score DESC)'
    else
    begin
      OrderStr := '';
      First := True;
      for F in AReq.OrderByFields do
      begin
        if not First then OrderStr := OrderStr + ', ';
        if F.Direction = odDesc then
          OrderStr := OrderStr + F.FieldName + ' DESC'
        else
          OrderStr := OrderStr + F.FieldName + ' ASC';
        First := False;
      end;
    end;

    SB.AppendLine('## VGQL Query Plan');
    SB.AppendLine('');
    SB.AppendLine('Entity    : ' + IfThen(AReq.Entity <> '', AReq.Entity, '(default)'));
    SB.AppendLine('Query     : ' + AReq.Query);
    SB.AppendLine('Mode      : ' + ModeStr);
    SB.AppendLine('Fusion    : ' + FusionStr);
    SB.AppendLine('Language  : ' + AReq.Language);
    SB.AppendLine('Rerank    : ' + IfThen(AReq.RerankQuery <> '', AReq.RerankQuery, '(none)'));
    if AReq.MinGlobal > 0 then
      SB.AppendLine(Format('Threshold : GLOBAL %.4f', [AReq.MinGlobal]));
    if AReq.MinSemantic > 0 then
      SB.AppendLine(Format('Threshold : SEMANTIC %.4f', [AReq.MinSemantic]));
    if AReq.MinLexical > 0 then
      SB.AppendLine(Format('Threshold : LEXICAL %.4f', [AReq.MinLexical]));
    SB.AppendLine(Format('Limit     : %d / Offset: %d', [AReq.Limit, AReq.Offset]));
    SB.AppendLine('Distinct  : ' + IfThen(AReq.DistinctField <> '', AReq.DistinctField, '(none)'));
    SB.AppendLine('Order By  : ' + OrderStr);
    SB.AppendLine('Optimize  : ' + OptimStr);
    Result := SB.ToString.TrimRight;
  finally
    SB.Free;
  end;
end;

function TAiRAGVector.BuildExtendedContextText(DataVec: TAiRAGVector; AReq: TVGQLRequest): string;
// Like VectorToContextText but also emits ID, RANK, MODEL fields when requested.
var
  i: Integer;
  Emb: TAiEmbeddingNode;
  SB: TStringBuilder;
  Pair: TPair<string, Variant>;
  HasContent: Boolean;
begin
  if (DataVec = nil) or (DataVec.Count = 0) then
    Exit('');

  SB := TStringBuilder.Create;
  try
    for i := 0 to DataVec.Count - 1 do
    begin
      Emb := DataVec.Items[i];
      HasContent := False;

      if AReq.IncludeMetadata or AReq.IncludeScore or
         AReq.IncludeId or AReq.IncludeRank or AReq.IncludeModel then
      begin
        SB.Append('[');

        if AReq.IncludeRank then
        begin
          SB.AppendFormat('Rank: %d', [i + 1]);
          HasContent := True;
        end;

        if AReq.IncludeScore then
        begin
          if HasContent then SB.Append(' | ');
          SB.AppendFormat('Score: %.4f', [Emb.Idx]);
          HasContent := True;
        end;

        if AReq.IncludeId then
        begin
          if HasContent then SB.Append(' | ');
          SB.Append('ID: ' + IfThen(Emb.Tag <> '', Emb.Tag, IntToStr(i)));
          HasContent := True;
        end;

        if AReq.IncludeModel then
        begin
          if HasContent then SB.Append(' | ');
          SB.Append('Model: ' + Emb.Model);
          HasContent := True;
        end;

        if AReq.IncludeMetadata then
        begin
          // Show Tag as ID only if not already shown by IncludeId
          if (Emb.Tag <> '') and not AReq.IncludeId then
          begin
            if HasContent then SB.Append(' | ');
            SB.Append('ID: ' + Emb.Tag);
            HasContent := True;
          end;
          if Assigned(Emb.MetaData) then
          begin
            for Pair in Emb.MetaData.InternalDictionary do
            begin
              if HasContent then SB.Append(' | ');
              SB.Append(Pair.Key + ': ' + VarToStr(Pair.Value));
              HasContent := True;
            end;
          end;
        end;

        SB.AppendLine(']');
      end;

      if Emb.Text <> '' then
        SB.AppendLine(Emb.Text);

      SB.AppendLine('');
    end;
    Result := SB.ToString.TrimRight;
  finally
    SB.Free;
  end;
end;

function TAiRAGVector.ExecuteVQL(const AVqlQuery: string): string;
var
  TempVec: TAiRAGVector;
begin
  Result := ExecuteVQL(AVqlQuery, TempVec);
  if Assigned(TempVec) then
    TempVec.Free;
end;

function TAiRAGVector.FilterByCriteria(const aCriteria: TAiFilterCriteria): TAiRAGVector;
var
  i: Integer;
  Node: TAiEmbeddingNode;
  Include: Boolean;
begin
  Result := TAiRAGVector.Create(nil, False); // No owner
  FLock.BeginRead;
  try
    for i := 0 to FItems.Count - 1 do
    begin
      Node := FItems[i];
      Include := True;

      // A. Filter by Event
      if Assigned(FOnFilterItem) then
        FOnFilterItem(Self, Node, Include);

      // B. Filter by Criteria
      if Include and Assigned(aCriteria) and (aCriteria.Count > 0) then
      begin
        if not Node.MetaData.Matches(aCriteria) then
          Include := False;
      end;

      if Include then
        Result.Items.Add(Node);
    end;
  finally
    FLock.EndRead;
  end;
end;

// This method returns a TAiRAGVector that does not own the nodes (it only holds the references).
function TAiRAGVector.FilterByMetaData(const aCriteria: TAiEmbeddingMetaData): TAiRAGVector;
var
  i: Integer;
  Node: TAiEmbeddingNode;
  Include: Boolean;
  Pair: TPair<string, Variant>;
begin
  // The result is a new container that does not own the nodes (only references)
  Result := TAiRAGVector.Create(nil, False);

  FLock.BeginRead;
  try
    for i := 0 to FItems.Count - 1 do
    begin
      Node := FItems[i];
      Include := True;

      // A. Filter by Event (Highest priority)
      if Assigned(FOnFilterItem) then
        FOnFilterItem(Self, Node, Include);

      // B. Filter by Metadata Dictionary
      if Include and Assigned(aCriteria) and (aCriteria.InternalDictionary.Count > 0) then
      begin
        for Pair in aCriteria.InternalDictionary do
        begin
          // We use the new evaluation logic of the MetaData class
          // We check whether the current node meets the criterion (equality by default)
          if not Node.MetaData.Evaluate(Pair.Key, foEqual, Pair.Value) then
          begin
            Include := False;
            Break;
          end;
        end;
      end;

      if Include then
        Result.Items.Add(Node);
    end;
  finally
    FLock.EndRead;
  end;
end;

function TAiRAGVector.LoadFromFile(FileName: String): Integer;
Var
  FS: TFileStream;
begin
  if not FileExists(FileName) then
    Raise Exception.CreateFmt('The file does not exist: %s', [FileName]);

  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  Try
    // We call LoadFromStream and return its result
    Result := LoadFromStream(FS);
  Finally
    FS.Free;
  End;
end;

function TAiRAGVector.LoadFromStream(Stream: TStream): Integer;
Var
  ST: TStringStream;
  JItem, JObj: TJSONObject;
  JArr: TJSonArray;
  JVal: TJSONValue;
  Emb: TAiEmbeddingNode;
  JSONContent: string;
begin
  Result := 0; // We initialize

  if not Assigned(Stream) then
    Exit;

  // 1. Safe reading with UTF-8 encoding
  ST := TStringStream.Create('', TEncoding.UTF8);
  Try
    Stream.Position := 0;
    ST.CopyFrom(Stream, 0);
    JSONContent := ST.DataString;
  Finally
    ST.Free;
  End;

  // 2. JSON parsing
  JVal := TJSONObject.ParseJSONValue(JSONContent);
  if not(JVal is TJSONObject) then
  begin
    JVal.Free;
    Raise Exception.Create('The file format is not a valid JSON object.');
  end;

  JObj := TJSONObject(JVal);
  Try
    // 3. Write lock
    FLock.BeginWrite;
    Try
      // 4. Previous cleanup
      Self.Clear;

      // 5. Load Vector Properties
      JObj.TryGetValue<String>('name', FNameVec);
      JObj.TryGetValue<String>('description', FDescription);
      JObj.TryGetValue<String>('model', FModel);
      if JObj.TryGetValue<Integer>('dim', FDim) then;

      // 6. Load Data Array
      if JObj.TryGetValue<TJSonArray>('data', JArr) then
      Begin
        For JVal in JArr do
        Begin
          if JVal is TJSONObject then
          begin
            JItem := TJSONObject(JVal);

            // Rebuild node from JSON
            Emb := TAiEmbeddingNode.FromJSON(JItem);

            // Add to the list
            FItems.Add(Emb);

            // Index in BM25 if applicable
            if FSearchOptions.FUseBM25 then
              FBm25Index.AddNode(Emb);
          end;
        End;
      End;

      // 7. Rebuild the vector index
      if Assigned(FRagIndex) then
        FRagIndex.BuildIndex(Self.FItems);

      // ASSIGN THE FINAL RESULT
      Result := FItems.Count;

    Finally
      FLock.EndWrite;
    End;
  Finally
    JObj.Free;
  End;
end;

procedure TAiRAGVector.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  // If a component is being removed
  if Operation = opRemove then
  begin
    // Check if it is the assigned Embeddings engine
    if (AComponent = FEmbeddings) then
      FEmbeddings := nil;

    // Check if it is the assigned database Driver
    if (AComponent = FDriver) then
      FDriver := nil;

    if (AComponent = FReranker) then
      FReranker := nil;
  end;
end;

procedure TAiRAGVector.Rerank(Target: TAiEmbeddingNode; aAutoRegenerate: Boolean);
var
  i: Integer;
  Emb: TAiEmbeddingNode;
begin
  if FItems.Count = 0 then
    Exit;

  // 1. Model verification
  if (FModel <> '') and (FModel <> Target.Model) then
  begin
    if aAutoRegenerate then
      RegenerateAll(Target.Model) // Migrate the entire list to the Target model
    else
      raise Exception.Create('Rerank Error: The query model does not match and AutoRegenerate is disabled.');
  end;

  // 2. Recalculate scores (Idx) with the same model already guaranteed
  for i := 0 to FItems.Count - 1 do
  begin
    Emb := FItems[i];
    Emb.Idx := TAiEmbeddingNode.CosineSimilarity(Emb, Target);
  end;

  // 3. Reorder the list (The sorting code remains the same)
  FItems.Sort(TComparer<TAiEmbeddingNode>.Construct(
    function(const Left, Right: TAiEmbeddingNode): Integer
    const
      TOLERANCE = 1.0E-12;
    begin
      if Abs(Left.Idx - Right.Idx) < TOLERANCE then
        Result := 0
      else if Left.Idx > Right.Idx then
        Result := -1
      else
        Result := 1;
    end));
end;

function TAiRAGVector.ReciprocalRankFusion(VectorResults: TList<TAiSearchResult>; LexicalResults: TList<TPair<Double, TAiEmbeddingNode>>; aLimit: Integer): TAiRAGVector;
const
  k = 60; // Standard smoothing constant
var
  Scores: TDictionary<TAiEmbeddingNode, Double>;
  i: Integer;
  Node: TAiEmbeddingNode;
  CombinedList: TList<TPair<Double, TAiEmbeddingNode>>;
  RankScore: Double;
  MaxRRF, MinRRF, RangeRRF: Double;
begin
  Result := TAiRAGVector.Create(nil, False);
  Scores := TDictionary<TAiEmbeddingNode, Double>.Create;
  CombinedList := TList < TPair < Double, TAiEmbeddingNode >>.Create;
  try
    // 1. Process Vector Ranking
    // Note: Although VectorResults is already normalized, RRF only uses its position (i)
    if Assigned(VectorResults) then
    begin
      for i := 0 to VectorResults.Count - 1 do
      begin
        Node := VectorResults[i].Node;
        RankScore := 1.0 / (k + (i + 1));
        Scores.Add(Node, RankScore);
      end;
    end;

    // 2. Process Lexical Ranking (BM25)
    if Assigned(LexicalResults) then
    begin
      for i := 0 to LexicalResults.Count - 1 do
      begin
        Node := LexicalResults[i].Value;
        RankScore := 1.0 / (k + (i + 1));

        if Scores.ContainsKey(Node) then
          Scores[Node] := Scores[Node] + RankScore
        else
          Scores.Add(Node, RankScore);
      end;
    end;

    // 3. Convert to list to be able to normalize and sort
    for Node in Scores.Keys do
      CombinedList.Add(TPair<Double, TAiEmbeddingNode>.Create(Scores[Node], Node));

    if CombinedList.Count = 0 then
      Exit;

    // --- CRITICAL POINT: RRF SCORE NORMALIZATION ---
    // We find the Min and Max of the calculated RRF scores
    MaxRRF := -1;
    MinRRF := 999999;
    for i := 0 to CombinedList.Count - 1 do
    begin
      if CombinedList[i].Key > MaxRRF then
        MaxRRF := CombinedList[i].Key;
      if CombinedList[i].Key < MinRRF then
        MinRRF := CombinedList[i].Key;
    end;

    RangeRRF := MaxRRF - MinRRF;

    // 4. Sort descending by RRF score
    CombinedList.Sort(TComparer < TPair < Double, TAiEmbeddingNode >>.Construct(
      function(const L, R: TPair<Double, TAiEmbeddingNode>): Integer
      begin
        Result := CompareValue(R.Key, L.Key);
      end));

    // 5. Dump to the result applying the final Min-Max normalization
    // This makes the best RRF ranking have Idx = 1.0
    for i := 0 to Min(aLimit * 2, CombinedList.Count - 1) do
    begin
      Node := CombinedList[i].Value;

      if RangeRRF > 0 then
        Node.Idx := (CombinedList[i].Key - MinRRF) / RangeRRF
      else
        Node.Idx := 1.0;

      Result.Items.Add(Node);
    end;

  finally
    CombinedList.Free;
    Scores.Free;
  end;
end;

procedure TAiRAGVector.RegenerateAll(const aNewModel: String);
var
  i: Integer;
  Emb: TAiEmbeddingNode;
  NewModelName: String;
begin
  if FItems.Count = 0 then
    Exit;

  // Determine which model to use
  if aNewModel <> '' then
    NewModelName := aNewModel
  else if Assigned(FEmbeddings) then
    NewModelName := FEmbeddings.Model
  else
    NewModelName := FModel;

  // Recorrer y regenerar
  for i := 0 to FItems.Count - 1 do
  begin
    Emb := FItems[i];
    if Emb.Text = '' then
      Continue; // Optional: handle error if there is no original text

    // Generate the new vector
    if Assigned(FEmbeddings) then
    begin
      // If the programmer passed a specific model, we set it temporarily
      if aNewModel <> '' then
        FEmbeddings.Model := aNewModel;
      Emb.Data := FEmbeddings.CreateEmbedding(Emb.Text, 'user');
    end
    else
    begin
      Emb.Data := DoOnGetEmbedding(Emb.Text, 'user', -1, NewModelName);
    end;

    Emb.Model := NewModelName;
    Emb.SetDataLength(Length(Emb.Data));
  end;

  // Update container metadata
  FModel := NewModelName;
  if FItems.Count > 0 then
    FDim := FItems[0].Dim;

  // CRITICAL! The previous spatial index is no longer valid.
  BuildIndex;
end;

procedure TAiRAGVector.Rerank(NewPrompt: String; aAutoRegenerate: Boolean);
var
  Target: TAiEmbeddingNode;
begin
  if Not Assigned(FEmbeddings) and Not Assigned(FOnGetEmbedding) then
    Raise Exception.Create('Rerank: No embeddings engine is configured.');

  // We create the temporary node for the new prompt
  Target := CreateEmbeddingNode(NewPrompt);
  try
    // Pass the flag to the main implementation
    Rerank(Target, aAutoRegenerate);
  finally
    Target.Free;
  end;
end;

procedure TAiRAGVector.SaveToFile(FileName: String);
Var
  ST: TMemoryStream;
begin
  ST := TMemoryStream.Create;
  Try
    SaveToStream(ST);
    ST.SaveToFile(FileName);
  Finally
    ST.Free;
  End;
end;

procedure TAiRAGVector.SaveToStream(Stream: TMemoryStream);
Var
  Emb: TAiEmbeddingNode;
  i: Integer;
  ST: TStringStream;
  JArr: TJSonArray;
  JItem, JObj: TJSONObject;
begin
  // 1. Input validation
  If Not Assigned(Stream) then
    Raise Exception.Create('The destination Stream cannot be nil in SaveToStream.');

  // 2. Create root object
  JObj := TJSONObject.Create;
  try
    // 3. Save Vector properties
    JObj.AddPair('name', FNameVec);
    JObj.AddPair('description', FDescription);
    JObj.AddPair('model', FModel);
    JObj.AddPair('dim', TJSONNumber.Create(FDim)); // Explicit to ensure numeric type

    // 4. Create Data Array
    JArr := TJSonArray.Create;
    // IMPORTANT: When adding the pair, JObj becomes the OWNER of JArr.
    // We do not need to (and must not) free JArr manually.
    JObj.AddPair('data', JArr);

    // 5. Fill items with thread protection
    FLock.BeginRead;
    try
      For i := 0 to FItems.Count - 1 do
      Begin
        Emb := FItems[i];
        // Delegate serialization to the node (which already includes Metadata, Text, Vector)
        JItem := Emb.ToJSON;
        JArr.Add(JItem);
      End;
    finally
      FLock.EndRead;
    end;

    // 6. Write to the Stream
    // We use ToJSON (compact) instead of Format (indented) to save disk space.
    // We use UTF8 to support accents and special characters.
    ST := TStringStream.Create(JObj.ToJSON, TEncoding.UTF8);
    try
      // Copy the string stream content to the destination memory stream
      Stream.CopyFrom(ST, 0);
    finally
      ST.Free;
    end;

  finally
    // When freeing JObj, JArr and all child JItems are automatically freed.
    JObj.Free;
  end;
end;

function TAiRAGVector.Search(Target: TAiEmbeddingNode; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TAiRAGVector;
var
  Handled: Boolean;
  VectorResults: TList<TAiSearchResult>;
  LexicalRes: TList<TPair<Double, TAiEmbeddingNode>>;
  SearchResult: TAiSearchResult;
  //TempResultVec: TAiRAGVector;
  i: Integer;
  Node: TAiEmbeddingNode;
  Pair: TPair<Double, TAiEmbeddingNode>;
  RawIndexResults: TRagItems;
begin
  Result := nil;
  Handled := False;

  if FSearchOptions.UseEmbeddings and (Target.MagnitudeValue <= 0) then
  begin
    // If there is no vector in the question, semantic search is impossible.
    // We could throw an exception or automatically degrade to BM25.
    if not FSearchOptions.UseBM25 then
      raise Exception.Create('Error: The query did not generate a valid vector. Check your embeddings engine.');
  end;

  // ---------------------------------------------------------------------------
  // PHASE 1: EXTERNAL EVENTS
  // ---------------------------------------------------------------------------
  if Assigned(FOnDataVecSearch) then
  begin
    FOnDataVecSearch(Self, Target, Target.Text, aLimit, aPrecision, aFilter, Result, Handled);
    if Handled then
      Exit;
  end;

  // ---------------------------------------------------------------------------
  // PHASE 2: EXTERNAL DRIVER
  // ---------------------------------------------------------------------------
  if Assigned(FDriver) then
  begin
    Result := FDriver.Search(Target, FEntidad, aLimit, aPrecision, aFilter, FSearchOptions);
    Exit;
  end;

  // ---------------------------------------------------------------------------
  // PHASE 3: IN-MEMORY SEARCH
  // ---------------------------------------------------------------------------
  FLock.BeginRead;
  try
    VectorResults := nil;
    LexicalRes := nil;
    try
      // =======================================================================
      // SUBPHASE A: VECTOR SEARCH
      // =======================================================================
      if FSearchOptions.UseEmbeddings then
      begin
        if not Assigned(FRagIndex) then
          raise Exception.Create('No index is assigned');

        if (FModel <> '') and (Target.Model <> '') and (FModel <> Target.Model) then
          raise Exception.CreateFmt('Model Error: The vector uses "%s" but the Query uses "%s"', [FModel, Target.Model]);

        // If there is a filter or event, we use safe linear search
        if ((Assigned(aFilter) and (aFilter.Count > 0)) or Assigned(FOnFilterItem)) then
        begin
          VectorResults := InternalSearchSafe(Target, Max(50, aLimit * 5), FSearchOptions.MinAbsoluteScoreEmbedding, aFilter);
        end
        else
        begin
          // Fast path: vector index (HNSW / Basic)
          VectorResults := TList<TAiSearchResult>.Create;
          //TempResultVec
          RawIndexResults  := FRagIndex.Search(Target, Max(50, aLimit * 5), FSearchOptions.MinAbsoluteScoreEmbedding);  //<<---- Error here
          try
            if Assigned(RawIndexResults ) then
            begin
              for i := 0 to RawIndexResults.Count - 1 do
              begin
                Node := RawIndexResults [i];
                VectorResults.Add(TAiSearchResult.Create(Node, Node.Idx));
              end;
            end;
          finally
            RawIndexResults.Free;
          end;
        end;

        // Vector normalization [0..1]
        // InternalNormalizeVector(VectorResults);   //We remove this to give the real results and not the normalized ones.
      end;

      // =======================================================================
      // SUBPHASE B: LEXICAL SEARCH (BM25)
      // =======================================================================
      if FSearchOptions.UseBM25 and (Target.Text.Trim <> '') then
      begin
        LexicalRes := FBm25Index.Search(Target.Text, Max(50, aLimit * 5), aFilter);

        // Filter A: BM25 dignity
        for i := LexicalRes.Count - 1 downto 0 do
          if LexicalRes[i].Key < FSearchOptions.MinAbsoluteScoreBM25 then
            LexicalRes.Delete(i);

        // Lexical normalization [0..1]
        InternalNormalizeLexical(LexicalRes);
      end;

      // =======================================================================
      // SUBPHASE C: FUSION
      // =======================================================================
      if Assigned(VectorResults) and not Assigned(LexicalRes) then
      begin
        // VECTOR ONLY
        Result := TAiRAGVector.Create(nil, False);
        for SearchResult in VectorResults do
        begin
          SearchResult.Node.Idx := SearchResult.Score;
          Result.Items.Add(SearchResult.Node);
        end;
      end
      else if not Assigned(VectorResults) and Assigned(LexicalRes) then
      begin
        // LEXICAL ONLY
        Result := TAiRAGVector.Create(nil, False);
        for Pair in LexicalRes do
        begin
          Pair.Value.Idx := Pair.Key;
          Result.Items.Add(Pair.Value);
        end;
      end
      else if Assigned(VectorResults) and Assigned(LexicalRes) then
      begin
        // HYBRID
        if FSearchOptions.UseRRF then
          Result := ReciprocalRankFusion(VectorResults, LexicalRes, aLimit)
        else
          Result := WeightedScoreFusion(VectorResults, LexicalRes, aLimit);
      end
      else
        Result := TAiRAGVector.Create(nil, False);

      // =======================================================================
      // SUBPHASE D: FINAL FILTER AND POST-PROCESSING
      // =======================================================================
      if Assigned(Result) then
      begin
        // Final precision on unified score
        if aPrecision > 0 then
        begin
          for i := Result.Count - 1 downto 0 do
            if Result.Items[i].Idx < aPrecision then
              Result.Items.Delete(i);
        end;

        // Final Top-K
        while Result.Count > aLimit do
          Result.Items.Delete(Result.Count - 1);

        Result.FModel := Self.Model;
        Result.FDim := Self.Dim;

        if FSearchOptions.UseReorderABC and (Result.Count > 2) then
          ApplyContextReordering(Result);
      end;

    finally
      if Assigned(VectorResults) then
        VectorResults.Free;
      if Assigned(LexicalRes) then
        LexicalRes.Free;
    end;
  finally
    FLock.EndRead;
  end;
end;

function TAiRAGVector.Search(Prompt: String; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria): TAiRAGVector;
var
  Target: TAiEmbeddingNode;
  LSpan: TAiSpan;
begin
  // 1. Embeddings Engine Verification
  // Without this, we cannot convert the 'Prompt' text into numbers.
  if Not Assigned(FEmbeddings) and Not Assigned(FOnGetEmbedding) then
    Raise Exception.Create('Error: No embeddings engine is configured. Assign the Embeddings property or the OnGetEmbedding event.');

  // Telemetry: the span covers query embedding + full retrieval
  LSpan := AiSpanStart('rag.search', skInternal);
  AiSpanAttr(LSpan, 'rag.top_k', Int64(aLimit));
  AiSpanAttr(LSpan, 'rag.hybrid.embeddings', FSearchOptions.UseEmbeddings);
  AiSpanAttr(LSpan, 'rag.hybrid.bm25', FSearchOptions.UseBM25);
  try
    // 2. Vectorization
    // CreateEmbeddingNode is responsible for calling the embeddings API or the event
    Target := CreateEmbeddingNode(Prompt);
    try
      // 3. Delegation
      // We call the main overload that searches by Node + Criteria Filter
      Result := Search(Target, aLimit, aPrecision, aFilter);
      if Assigned(Result) then
        AiSpanAttr(LSpan, 'rag.results', Int64(Result.Count));
      AiSpanEnd(LSpan);
      LSpan := nil; // already consumed: the except block must not touch it again
    finally
      Target.Free;
    end;
  except
    on E: Exception do
    begin
      AiSpanEnd(LSpan, E.Message);
      raise;
    end;
  end;
end;

function TAiRAGVector.SearchText(aPrompt: TAiEmbeddingNode; aLimit: Integer; aPresicion: Double; aFilter: TAiFilterCriteria; IncludeMetadata, IncludeScore: Boolean): String;
Var
  TmpVec: TAiRAGVector;
Begin
  // Now the call is direct and explicit, passing the received criterion (or nil)
  TmpVec := Search(aPrompt, aLimit, aPresicion, aFilter);

  Try
    Result := VectorToContextText(TmpVec, IncludeMetadata, IncludeScore);
  Finally
    TmpVec.Free;
  End;
end;

procedure TAiRAGVector.SetActive(const Value: Boolean);
begin
  FActive := Value;
end;

procedure TAiRAGVector.SetDescription(const Value: String);
begin
  FDescription := Value;
end;

procedure TAiRAGVector.SetDriver(const Value: TAiVectorStoreDriverBase);
begin
  if FDriver <> Value then
  begin
    FDriver := Value;
    if Assigned(FDriver) then
      FDriver.FreeNotification(Self);
  end;
end;

procedure TAiRAGVector.SetEmbeddings(const Value: TAiEmbeddingsCore);
begin
  if FEmbeddings <> Value then
  begin
    FEmbeddings := Value;

    // Notify the component that we want to be notified when it is destroyed
    if Assigned(FEmbeddings) then
      FEmbeddings.FreeNotification(Self);

    // Your existing runtime/design-time logic
    if (csDesigning in ComponentState) then
      Exit;

    if Assigned(Value) then
    begin
      FModel := Value.Model;
      FDim := Value.Dimensions;
    end;
  end;
end;

procedure TAiRAGVector.SetInMemoryIndexType(const Value: TAiRagIndexType);
begin
  // Avoid unnecessary changes
  if FInMemoryIndexType = Value then
    Exit;

  FInMemoryIndexType := Value;

  // Protection: Do not rebuild indexes if we are loading the component (reading from DFM)
  // or if we are in the destruction process.
  if (csLoading in ComponentState) or (csDestroying in ComponentState) then
    Exit;

  // Index rebuild
  FLock.BeginWrite;
  try
    if Assigned(FRagIndex) then
      FreeAndNil(FRagIndex);

    CheckIndexes; // This will create the new index according to FInMemoryIndexType
  finally
    FLock.EndWrite;
  end;
end;

procedure TAiRAGVector.SetLexicalLanguage(const Value: TAiLanguage);
begin
  If Assigned(FBm25Index) then
    FBm25Index.Language := Value;
end;

procedure TAiRAGVector.SetNameVec(const Value: String);
begin
  FNameVec := Value;
end;

procedure TAiRAGVector.SetOnDataVecAddItem(const Value: TOnDataVecAddItem);
begin
  FOnDataVecAddItem := Value;
end;

procedure TAiRAGVector.SetOnDataVecSearch(const Value: TOnDataVecSearch);
begin
  FOnDataVecSearch := Value;
end;

procedure TAiRAGVector.SetRagIndex(const Value: TAIEmbeddingIndex);
begin
  FRagIndex := Value;
end;

procedure TAiRAGVector.SetSearchOptions(const Value: TAiSearchOptions);
begin
  FSearchOptions := Value;
end;

function TAiRAGVector.VectorToContextText(DataVec: TAiRAGVector; IncludeMetadata: Boolean; IncludeScore: Boolean): String;
var
  i: Integer;
  Emb: TAiEmbeddingNode;
  SB: TStringBuilder;
  Pair: TPair<string, Variant>;
  HasContentBefore: Boolean;
begin
  if (DataVec = nil) or (DataVec.Count = 0) then
    Exit('');

  SB := TStringBuilder.Create;
  try
    for i := 0 to DataVec.Count - 1 do
    begin
      Emb := DataVec.Items[i];
      HasContentBefore := False;

      // --- 1. Header Block (Metadata and/or Score) ---
      if IncludeMetadata or IncludeScore then
      begin
        SB.Append('[');

        // A. Show Score if requested
        if IncludeScore then
        begin
          SB.AppendFormat('Score: %.4f', [Emb.Idx]);
          HasContentBefore := True;
        end;

        // B. Show Metadata if requested
        if IncludeMetadata then
        begin
          // Separator if we already wrote the score
          if HasContentBefore then
            SB.Append(' | ');

          // ID or Tag
          if Emb.Tag <> '' then
          begin
            SB.Append('ID: ' + Emb.Tag);
            HasContentBefore := True;
          end;

          // Property dictionary
          if Assigned(Emb.MetaData) then
          begin
            for Pair in Emb.MetaData.InternalDictionary do
            begin
              if HasContentBefore then
                SB.Append(' | ');
              SB.Append(Pair.Key + ': ' + VarToStr(Pair.Value));
              HasContentBefore := True;
            end;
          end;
        end;

        SB.AppendLine(']');
      end;

      // --- 2. Text Content ---
      SB.Append(Emb.Text.Trim);

      // --- 3. Separator between fragments ---
      SB.AppendLine;
      SB.AppendLine;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAiRAGVector.WeightedScoreFusion(VectorResults: TList<TAiSearchResult>; LexicalResults: TList<TPair<Double, TAiEmbeddingNode>>; aLimit: Integer): TAiRAGVector;
var
  Scores: TDictionary<TAiEmbeddingNode, Double>;
  Node: TAiEmbeddingNode;
  i: Integer;
  CombinedList: TList<TPair<Double, TAiEmbeddingNode>>;
  W_Sem, W_Lex, TotalWeight: Double;
begin
  // The result is a new container that does not own the objects
  Result := TAiRAGVector.Create(nil, False);

  Scores := TDictionary<TAiEmbeddingNode, Double>.Create;
  CombinedList := TList < TPair < Double, TAiEmbeddingNode >>.Create;
  try
    // -------------------------------------------------------------------------
    // 1. INTERNAL WEIGHT NORMALIZATION
    // We ensure the sum of weights is exactly 1.0 so as not to dilute the score
    // -------------------------------------------------------------------------
    TotalWeight := FSearchOptions.EmbeddingWeight + FSearchOptions.BM25Weight;

    if TotalWeight > 0 then
    begin
      W_Sem := FSearchOptions.EmbeddingWeight / TotalWeight;
      W_Lex := FSearchOptions.BM25Weight / TotalWeight;
    end
    else
    begin
      // Safety fallback if both weights are 0
      W_Sem := 0.5;
      W_Lex := 0.5;
    end;

    // -------------------------------------------------------------------------
    // 2. WEIGHTED FUSION PROCESS
    // -------------------------------------------------------------------------

    // A. Add contribution from the Vector channel (Semantic)
    if Assigned(VectorResults) then
    begin
      for i := 0 to VectorResults.Count - 1 do
      begin
        // We use the real cosine similarity score multiplied by its weight
        Scores.Add(VectorResults[i].Node, VectorResults[i].Score * W_Sem);
      end;
    end;

    // B. Add contribution from the Lexical channel (BM25)
    if Assigned(LexicalResults) then
    begin
      for i := 0 to LexicalResults.Count - 1 do
      begin
        Node := LexicalResults[i].Value;
        // The lexical score already comes normalized 0..1 from InternalNormalizeLexical
        var
        LexScore := LexicalResults[i].Key * W_Lex;

        if Scores.ContainsKey(Node) then
          Scores[Node] := Scores[Node] + LexScore
        else
          Scores.Add(Node, LexScore);
      end;
    end;

    // -------------------------------------------------------------------------
    // 3. SORTING AND TOP-K SELECTION
    // -------------------------------------------------------------------------

    // We move from the dictionary to a list to be able to sort
    for Node in Scores.Keys do
      CombinedList.Add(TPair<Double, TAiEmbeddingNode>.Create(Scores[Node], Node));

    // Sort by combined score from highest to lowest
    CombinedList.Sort(TComparer < TPair < Double, TAiEmbeddingNode >>.Construct(
      function(const L, R: TPair<Double, TAiEmbeddingNode>): Integer
      begin
        Result := CompareValue(R.Key, L.Key);
      end));

    // Fill the result vector respecting the limit
    // The final combined score is stored in Idx
    for i := 0 to Min(aLimit - 1, CombinedList.Count - 1) do
    begin
      Node := CombinedList[i].Value;
      Node.Idx := CombinedList[i].Key;
      Result.Items.Add(Node);
    end;

  finally
    CombinedList.Free;
    Scores.Free;
  end;
end;

function TAiRAGVector.SearchText(aPrompt: String; aLimit: Integer; aPrecision: Double; aFilter: TAiFilterCriteria; IncludeMetadata, IncludeScore: Boolean): String;
var
  TmpVec: TAiRAGVector;
begin
  // Llamamos a Search(String...) que ya soporta Criteria
  TmpVec := Search(aPrompt, aLimit, aPrecision, aFilter);
  try
    Result := VectorToContextText(TmpVec, IncludeMetadata, IncludeScore);
  finally
    TmpVec.Free;
  end;
end;


{ TAiVectorStoreDriverBase }

function TAiVectorStoreDriverBase.EmbeddingToString(const AData: TAiEmbeddingData): string;
var
  i: Integer;
  SB: TStringBuilder;
  FS: TFormatSettings;
begin
  if Length(AData) = 0 then
    Exit('[]');
  FS := TFormatSettings.Invariant;
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for i := 0 to High(AData) do
    begin
      SB.Append(FloatToStr(AData[i], FS));
      if i < High(AData) then
        SB.Append(',');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAiVectorStoreDriverBase.VariantToJSONValue(const V: Variant): TJSONValue;
begin
  case VarType(V) of
    varSmallint, varInteger, varByte, varShortInt, varWord, varLongWord, varInt64:
      Result := TJSONNumber.Create(Int64(V));
    varSingle, varDouble, varCurrency:
      Result := TJSONNumber.Create(Double(V));
    varBoolean:
      Result := TJSONBool.Create(Boolean(V));
    varNull, varEmpty:
      Result := TJSONNull.Create;
  else
    Result := TJSONString.Create(VarToStr(V));
  end;
end;


{ TAiSearchOptions }

constructor TAiSearchOptions.Create;
begin
  inherited;
  // Requested default values
  FUseEmbeddings := True;
  FUseBM25 := True;
  FUseRRF := False;
  FUseReorderABC := False;
  FBM25Weight := 0.7;
  FEmbeddingWeight := 0.3;
end;

procedure TAiSearchOptions.Assign(Source: TPersistent);
begin
  if Source is TAiSearchOptions then
  begin
    FUseEmbeddings := TAiSearchOptions(Source).UseEmbeddings;
    FUseBM25 := TAiSearchOptions(Source).UseBM25;
    FUseRRF := TAiSearchOptions(Source).UseRRF;
    FUseReorderABC := TAiSearchOptions(Source).UseReorderABC;
    FBM25Weight := TAiSearchOptions(Source).BM25Weight;
    FEmbeddingWeight := TAiSearchOptions(Source).EmbeddingWeight;
    // Without these two, VQL THRESHOLD SEMANTIC/LEXICAL were parsed but got
    // lost right here when applying ExecuteVQL's TempOptions
    FMinAbsoluteScoreEmbedding := TAiSearchOptions(Source).MinAbsoluteScoreEmbedding;
    FMinAbsoluteScoreBM25 := TAiSearchOptions(Source).MinAbsoluteScoreBM25;
    Changed;
  end
  else
    inherited Assign(Source);
end;

procedure TAiSearchOptions.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

// Setters (boilerplate needed to detect changes)
procedure TAiSearchOptions.SetUseEmbeddings(const Value: Boolean);
begin
  if FUseEmbeddings <> Value then
  begin
    FUseEmbeddings := Value;
    Changed;
  end;
end;

procedure TAiSearchOptions.SetUseBM25(const Value: Boolean);
begin
  if FUseBM25 <> Value then
  begin
    FUseBM25 := Value;
    Changed;
  end;
end;

procedure TAiSearchOptions.SetUseRRF(const Value: Boolean);
begin
  if FUseRRF <> Value then
  begin
    FUseRRF := Value;
    Changed;
  end;
end;

procedure TAiSearchOptions.SetUseReorderABC(const Value: Boolean);
begin
  if FUseReorderABC <> Value then
  begin
    FUseReorderABC := Value;
    Changed;
  end;
end;

procedure TAiSearchOptions.SetBM25Weight(const Value: Double);
begin
  if FBM25Weight <> Value then
  begin
    FBM25Weight := Value;
    Changed;
  end;
end;

procedure TAiSearchOptions.SetEmbeddingWeight(const Value: Double);
begin
  if FEmbeddingWeight <> Value then
  begin
    FEmbeddingWeight := Value;
    Changed;
  end;
end;

end.
