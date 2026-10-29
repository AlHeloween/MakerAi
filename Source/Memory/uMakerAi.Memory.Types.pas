unit uMakerAi.Memory.Types;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
{$IF CompilerVersion < 35}
  uJSONHelper, // Delphi 10.4: generic helper GetValue<T> from TJSONObject
{$ENDIF}
  System.JSON, System.DateUtils;

type
  // Semantic category of memory
  TMemoryType = (
    mt_Fact,        // objective fact: "the user uses Delphi 13"
    mt_Preference,  // preference: "prefers short answers"
    mt_Decision,    // decision made: "we use SQLite as backend"
    mt_ErrorFix,    // learned fix: "that bug is solved with X"
    mt_Pattern,     // detected pattern: "always asks about RAG first"
    mt_Workflow,    // step-by-step procedure
    mt_Summary,     // session or conversation summary
    mt_Custom       // free usage
  );

  TMemorySearchMode = (
    ms_FTS,         // only full-text search (FTS5)
    ms_Semantic,    // only vector search by embeddings
    ms_Hybrid       // FTS + semantic with RRF fusion
  );

  // Atomic memory record — equivalent to MemoryEntry from engram-core
  TMemoryEntry = class
  public
    Id:           Integer;
    Content:      string;
    MemoryType:   TMemoryType;
    Importance:   Integer;        // 1–10
    Namespace:    string;
    Tags:         TArray<string>;
    Metadata:     string;         // JSON serialized
    ContentHash:  string;         // SHA-256[:16] for dedup
    Embedding:    TArray<Double>; // nil if no embedder
    DecayScore:   Double;         // 0.0–1.0
    CreatedAt:    TDateTime;
    AccessedAt:   TDateTime;
    AccessCount:  Integer;
    ExpiresAt:    TDateTime;      // 0 = no TTL

    constructor Create;
    function    TagsAsString: string;    // CSV of tags
    function    ToJSON: TJSONObject;
    procedure   Assign(ASource: TMemoryEntry);
    class function FromJSON(AObj: TJSONObject): TMemoryEntry;
  end;

  TMemoryEntryList = TObjectList<TMemoryEntry>;

  TMemorySearchResult = record
    Entry:     TMemoryEntry;     // not owned — the caller manages lifetime
    Score:     Double;
    MatchType: string;           // 'fts' | 'semantic' | 'hybrid'
  end;

  TMemorySearchResults = TArray<TMemorySearchResult>;

  TMemoryStats = record
    Namespace:     string;
    TotalCount:    Integer;
    AvgImportance: Double;
    AvgDecay:      Double;
    OldestEntry:   TDateTime;
    NewestEntry:   TDateTime;
    ExpiredCount:  Integer;
    function ToJSON: TJSONObject;
  end;

  TMemoryContextResult = record
    FormattedText: string;
    MemoryCount:   Integer;
    TokenEstimate: Integer;
    Truncated:     Boolean;
    MemoryIds:     TArray<Integer>;
  end;

  // Minimal interface so TAiChat can use TAiMemory without depending on the RAG.Drivers package
  IAiPersistentMemory = interface
    ['{A7F3E21C-4D5B-4E8F-9A0C-3B6D7E2F1948}']
    function  BuildContext(const APrompt: string; ATokenBudget: Integer): string;
    procedure AutoStore(const AContent: string; AImportance: Integer);
    // Notifies a complete user/assistant exchange. Implementations that
    // support automatic analysis (see TAiMemory.Analyzer) accumulate and, when
    // the configured threshold is reached, extract and save what is worth remembering.
    // No-op by default (see TAiPersistentMemoryBase).
    procedure NotifyExchange(const AUserPrompt, AAssistantResponse: string);
  end;

  // Specialization for the Object Inspector (same pattern as TAiSpeechToolBase/
  // TAiImageToolBase in uMakerAi.Chat.Tools.pas): TAiChat.PersistentMemory is typed
  // to this class instead of generic TComponent, so the component selection combo
  // filters only compatible instances and the compiler validates the type.
  // The concrete implementation with FireDAC storage (TAiMemory) lives in
  // MakerAi.RAG.Drivers.dpk and inherits from this base, which only depends on this core
  // package (MakerAI.dpk).
  TAiPersistentMemoryBase = class(TComponent, IAiPersistentMemory)
  protected
    function  BuildContext(const APrompt: string; ATokenBudget: Integer): string; virtual;
    procedure AutoStore(const AContent: string; AImportance: Integer); virtual;
    procedure NotifyExchange(const AUserPrompt, AAssistantResponse: string); virtual;
  end;

// Conversion helpers for TMemoryType
function  MemoryTypeToStr(AType: TMemoryType): string;
function  StrToMemoryType(const AStr: string): TMemoryType;

implementation

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

{ TAiPersistentMemoryBase }

function TAiPersistentMemoryBase.BuildContext(const APrompt: string; ATokenBudget: Integer): string;
begin
  Result := '';
end;

procedure TAiPersistentMemoryBase.AutoStore(const AContent: string; AImportance: Integer);
begin
end;

procedure TAiPersistentMemoryBase.NotifyExchange(const AUserPrompt, AAssistantResponse: string);
begin
end;

function MemoryTypeToStr(AType: TMemoryType): string;
const
  Names: array[TMemoryType] of string = (
    'fact', 'preference', 'decision', 'error_fix',
    'pattern', 'workflow', 'summary', 'custom'
  );
begin
  Result := Names[AType];
end;

function StrToMemoryType(const AStr: string): TMemoryType;
var
  T: TMemoryType;
begin
  Result := mt_Custom;
  for T := Low(TMemoryType) to High(TMemoryType) do
    if SameText(MemoryTypeToStr(T), AStr) then
      Exit(T);
end;

// ---------------------------------------------------------------------------
// TMemoryEntry
// ---------------------------------------------------------------------------

constructor TMemoryEntry.Create;
begin
  inherited;
  MemoryType  := mt_Fact;
  Importance  := 5;
  Namespace   := 'default';
  DecayScore  := 1.0;
  CreatedAt   := Now;
  AccessedAt  := Now;
  AccessCount := 0;
  Metadata    := '{}';
end;

procedure TMemoryEntry.Assign(ASource: TMemoryEntry);
begin
  Id           := ASource.Id;
  Content      := ASource.Content;
  MemoryType   := ASource.MemoryType;
  Importance   := ASource.Importance;
  Namespace    := ASource.Namespace;
  Tags         := Copy(ASource.Tags);
  Metadata     := ASource.Metadata;
  ContentHash  := ASource.ContentHash;
  Embedding    := Copy(ASource.Embedding);
  DecayScore   := ASource.DecayScore;
  CreatedAt    := ASource.CreatedAt;
  AccessedAt   := ASource.AccessedAt;
  AccessCount  := ASource.AccessCount;
  ExpiresAt    := ASource.ExpiresAt;
end;

function TMemoryEntry.TagsAsString: string;
begin
  Result := String.Join(',', Tags);
end;

function TMemoryEntry.ToJSON: TJSONObject;
var
  TagArr: TJSONArray;
  T: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',           TJSONNumber.Create(Id));
  Result.AddPair('content',      Content);
  Result.AddPair('memory_type',  MemoryTypeToStr(MemoryType));
  Result.AddPair('importance',   TJSONNumber.Create(Importance));
  Result.AddPair('namespace',    Namespace);
  Result.AddPair('content_hash', ContentHash);
  Result.AddPair('decay_score',  TJSONNumber.Create(DecayScore));
  Result.AddPair('access_count', TJSONNumber.Create(AccessCount));
  Result.AddPair('created_at',   DateToISO8601(CreatedAt, False));
  Result.AddPair('accessed_at',  DateToISO8601(AccessedAt, False));
  if ExpiresAt > 0 then
    Result.AddPair('expires_at', DateToISO8601(ExpiresAt, False));
  TagArr := TJSONArray.Create;
  for T in Tags do
    TagArr.Add(T);
  Result.AddPair('tags', TagArr);
  Result.AddPair('metadata', TJSONObject.ParseJSONValue(Metadata) as TJSONValue);
end;

class function TMemoryEntry.FromJSON(AObj: TJSONObject): TMemoryEntry;
var
  TagArr: TJSONArray;
  I: Integer;
begin
  Result := TMemoryEntry.Create;
  if AObj.TryGetValue('id', Result.Id) then ;
  AObj.TryGetValue('content',      Result.Content);
  AObj.TryGetValue('importance',   Result.Importance);
  AObj.TryGetValue('namespace',    Result.Namespace);
  AObj.TryGetValue('content_hash', Result.ContentHash);
  AObj.TryGetValue('decay_score',  Result.DecayScore);
  AObj.TryGetValue('access_count', Result.AccessCount);

  var TypeStr: string;
  if AObj.TryGetValue('memory_type', TypeStr) then
    Result.MemoryType := StrToMemoryType(TypeStr);

  var DateStr: string;
  if AObj.TryGetValue('created_at',  DateStr) then Result.CreatedAt  := ISO8601ToDate(DateStr, False);
  if AObj.TryGetValue('accessed_at', DateStr) then Result.AccessedAt := ISO8601ToDate(DateStr, False);
  if AObj.TryGetValue('expires_at',  DateStr) then Result.ExpiresAt  := ISO8601ToDate(DateStr, False);

  TagArr := AObj.GetValue<TJSONArray>('tags');
  if Assigned(TagArr) then
  begin
    SetLength(Result.Tags, TagArr.Count);
    for I := 0 to TagArr.Count - 1 do
      Result.Tags[I] := TagArr.Items[I].Value;
  end;

  var MetaVal: TJSONValue;
  if AObj.TryGetValue('metadata', MetaVal) then
    Result.Metadata := MetaVal.ToJSON;
end;

// ---------------------------------------------------------------------------
// TMemoryStats
// ---------------------------------------------------------------------------

function TMemoryStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('namespace',      Namespace);
  Result.AddPair('total_count',    TJSONNumber.Create(TotalCount));
  Result.AddPair('avg_importance', TJSONNumber.Create(AvgImportance));
  Result.AddPair('avg_decay',      TJSONNumber.Create(AvgDecay));
  Result.AddPair('expired_count',  TJSONNumber.Create(ExpiredCount));
  if OldestEntry > 0 then
    Result.AddPair('oldest_entry', DateToISO8601(OldestEntry, False));
  if NewestEntry > 0 then
    Result.AddPair('newest_entry', DateToISO8601(NewestEntry, False));
end;

end.
