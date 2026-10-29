// MIT License
//
// Copyright (c) 2024 Gustavo Enríquez - CimaMaker
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
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Memory;

// TAiMemory — semantic persistent memory layer for AI agents.
//
// Public API of 5 core operations (equivalent to engram-core in Python):
//   Store   — persists content with type, importance, tags, TTL
//   Search  — FTS / semantic / hybrid search
//   Recall  — retrieves high-importance memories
//   Delete  — deletes by ID
//   Stats   — namespace statistics
//
// Extended operations:
//   Context — Smart Context Builder with token budget
//   Update  — updates content / importance of an existing entry
//   Prune   — removes old low-importance entries
//   Link    — creates a relation between two memories (knowledge graph)
//   Export / Import — JSON portability
//
// Persistence is autonomous: creates and manages its own SQLite file in DbPath.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.DateUtils, System.Math, System.IOUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Memory.Types,
  uMakerAi.Memory.Storage,
  uMakerAi.Memory.Decay,
  uMakerAi.Memory.Context,
  uMakerAi.Embeddings.Core;

type
  TOnMemoryStore  = procedure(Sender: TObject; AEntry: TMemoryEntry) of object;
  TOnMemorySearch = procedure(Sender: TObject; const AQuery: string;
                              const AResults: TMemorySearchResults) of object;

  TAiMemory = class(TAiPersistentMemoryBase)
  private
    FStorage:     IAiMemoryStorage;
    FContext:     TAiMemoryContext;
    FEmbedder:    TAiEmbeddingsCore;
    FNamespace:   string;
    FDbPath:      string;
    FAutoDecay:   Boolean;

    FOnStore:     TOnMemoryStore;
    FOnSearch:    TOnMemorySearch;

    // Automatic conversation analysis (fact extraction via cheap LLM)
    FAnalyzer:            TAiChatConnection;
    FAnalysisInterval:    Integer;
    FExchangeBuffer:      TStringBuilder;
    FTurnsSinceAnalysis:  Integer;

    procedure SetEmbedder(AValue: TAiEmbeddingsCore);
    procedure SetDbPath(const AValue: string);
    procedure SetAnalyzer(AValue: TAiChatConnection);
    procedure EnsureStorage;
    function  OwnsEntry(AId: Integer): Boolean;
    procedure RebuildContext;
    function  FuseRRF(AFTS, ASemantic: TMemoryEntryList; ALimit: Integer): TMemorySearchResults;
    function  DoAnalyzeAndStore(const AConversationText: string): Integer;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    // ── Core API (5 operations) ──────────────────────────────────────────────

    // Saves a memory. Returns the assigned Id.
    // If the content already exists in the namespace (same hash), updates instead of duplicating.
    function Store(
      const AContent:  string;
      AType:           TMemoryType      = mt_Fact;
      AImportance:     Integer          = 5;
      const ATags:     string           = '';   // CSV
      AMetadata:       TJSONObject      = nil;
      ATtlDays:        Integer          = 0     // 0 = no expiration
    ): Integer;

    // Search. AMode = ms_Hybrid uses FTS + semantic with RRF fusion.
    function Search(
      const AQuery: string;
      ALimit:       Integer          = 10;
      AMode:        TMemorySearchMode = ms_Hybrid
    ): TMemorySearchResults;

    // Retrieves memories with importance >= AMinImportance, sorted by imp descending.
    function Recall(
      AMinImportance: Integer = 7;
      ALimit:         Integer = 20
    ): TMemoryEntryList;

    // Deletes the memory with the given Id. False if the Id does not exist in the
    // active namespace (nothing is deleted).
    function Delete(AId: Integer): Boolean;

    // Statistics for the current namespace.
    function Stats: TMemoryStats;

    // ── Extended operations ──────────────────────────────────────────────────

    // Builds a text block with the most relevant memories for APrompt.
    // Ready to inject as part of the system prompt.
    function Context(
      const APrompt:  string;
      ATokenBudget:   Integer = 2000;
      AMinImportance: Integer = 1
    ): TMemoryContextResult;

    // Retrieves an entry by Id.
    function Get(AId: Integer): TMemoryEntry;

    // Updates content and/or importance of an existing entry.
    procedure Update(
      AId:         Integer;
      const AContent: string  = '';
      AImportance: Integer    = -1   // -1 = do not change
    );

    // Removes entries with low decay and age greater than AMaxAgeDays.
    procedure Prune(AMinImportance: Integer = 3; AMaxAgeDays: Integer = 90);

    // Removes memories that have exceeded their TTL.
    procedure CleanupExpired;

    // Regenerates embeddings for entries that do not have an embedding stored.
    // Requires Embedder assigned.
    procedure BackfillEmbeddings;

    // Exports all memories of the current namespace to JSON.
    function ExportToJSON: TJSONArray;

    // Imports memories from a TJSONArray (generated by ExportToJSON).
    procedure ImportFromJSON(AData: TJSONArray);

    // Creates a directed relation between two memories. False if either of the
    // IDs does not exist in the active namespace (nothing is touched).
    function Link(AFromId, AToId: Integer; const ARelation: string = 'related'): Boolean;
    function Unlink(AFromId, AToId: Integer): Boolean;
    function  Links(AId: Integer): TMemoryEntryList;

    // Recalculates decay_score of all memories in the namespace.
    // Call periodically (e.g., at session start).
    procedure RefreshDecay;

    // ── IAiPersistentMemory (override of TAiPersistentMemoryBase) ──────────────
    function  BuildContext(const APrompt: string; ATokenBudget: Integer): string; override;
    procedure AutoStore(const AContent: string; AImportance: Integer); override;
    procedure NotifyExchange(const AUserPrompt, AAssistantResponse: string); override;

    // Forces analysis of the accumulated buffer right now, without waiting for
    // AnalysisInterval (manual use: "remember this" button, cron, etc.).
    // Requires Analyzer assigned. Returns how many memories were saved.
    function AnalyzeNow: Integer;

  published
    // Cheap LLM used to analyze the conversation and extract what is worth
    // remembering (see AnalysisInterval / AnalyzeNow). If not assigned, feature is off.
    property Analyzer: TAiChatConnection read FAnalyzer write SetAnalyzer;

    // Every how many user/assistant exchanges the automatic analysis is triggered.
    // 0 = disabled (only manual trigger via AnalyzeNow).
    property AnalysisInterval: Integer read FAnalysisInterval write FAnalysisInterval default 10;
    // Active namespace — isolates memories between agents/projects
    property Namespace:  string           read FNamespace  write FNamespace;

    // Path to the SQLite file where memories persist.
    property DbPath:     string           read FDbPath     write SetDbPath;

    // Embedder for semantic search (optional). If nil = FTS only.
    property Embedder:   TAiEmbeddingsCore read FEmbedder  write SetEmbedder;

    // If True, calls RefreshDecay on every Recall (Store does not trigger it).
    property AutoDecay:  Boolean          read FAutoDecay  write FAutoDecay default False;

    property OnStore:    TOnMemoryStore   read FOnStore    write FOnStore;
    property OnSearch:   TOnMemorySearch  read FOnSearch   write FOnSearch;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI.Memory', [TAiMemory]);
end;

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

constructor TAiMemory.Create(AOwner: TComponent);
begin
  inherited;
  FNamespace  := 'default';
  FDbPath     := TPath.Combine(TPath.GetHomePath, 'ai_memory.db');
  FAutoDecay  := False;
  FAnalysisInterval   := 10;
  FExchangeBuffer     := TStringBuilder.Create;
  FTurnsSinceAnalysis := 0;
end;

destructor TAiMemory.Destroy;
begin
  FContext.Free;
  FExchangeBuffer.Free;
  // FStorage is an interface — it releases itself when leaving scope
  inherited;
end;

// ---------------------------------------------------------------------------
// Setters that invalidate storage/context if configuration changes
// ---------------------------------------------------------------------------

procedure TAiMemory.SetDbPath(const AValue: string);
begin
  if FDbPath = AValue then Exit;
  FDbPath  := AValue;
  FStorage := nil;
  FreeAndNil(FContext);
end;

procedure TAiMemory.SetEmbedder(AValue: TAiEmbeddingsCore);
begin
  if FEmbedder = AValue then Exit;
  if Assigned(FEmbedder) then
    FEmbedder.RemoveFreeNotification(Self);
  FEmbedder := AValue;
  if Assigned(FEmbedder) then
    FEmbedder.FreeNotification(Self);
  RebuildContext;
end;

procedure TAiMemory.SetAnalyzer(AValue: TAiChatConnection);
begin
  if FAnalyzer = AValue then Exit;
  if Assigned(FAnalyzer) then
    FAnalyzer.RemoveFreeNotification(Self);
  FAnalyzer := AValue;
  if Assigned(FAnalyzer) then
    FAnalyzer.FreeNotification(Self);
end;

procedure TAiMemory.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FAnalyzer then
      FAnalyzer := nil;

    if AComponent = FEmbedder then
    begin
      // Context retains the embedder: rebuild without it (only FTS remains)
      FEmbedder := nil;
      RebuildContext;
    end;
  end;
end;

procedure TAiMemory.EnsureStorage;
begin
  if Assigned(FStorage) then Exit;

  FStorage := TAiMemorySQLiteStorage.CreateWithPath(FDbPath);

  RebuildContext;
end;

procedure TAiMemory.RebuildContext;
begin
  FreeAndNil(FContext);
  if Assigned(FStorage) then
    FContext := TAiMemoryContext.Create(FStorage, FEmbedder);
end;

// ---------------------------------------------------------------------------
// FuseRRF — Reciprocal Rank Fusion to combine FTS + semantic
// ---------------------------------------------------------------------------

function TAiMemory.FuseRRF(AFTS, ASemantic: TMemoryEntryList;
  ALimit: Integer): TMemorySearchResults;
const
  K = 60; // standard RRF constant
var
  Scores: TDictionary<Integer, Double>;
  ById:   TDictionary<Integer, TMemoryEntry>;
  All:    TObjectList<TMemoryEntry>;
  E:      TMemoryEntry;
  I:      Integer;
  Si, Sj: Integer;
  SA, SB: Double;

  procedure AddRank(AList: TMemoryEntryList);
  var
    Rank: Integer;
    Item: TMemoryEntry;
  begin
    Rank := 1;
    for Item in AList do
    begin
      if not Scores.ContainsKey(Item.Id) then
        Scores.Add(Item.Id, 0);
      Scores[Item.Id] := Scores[Item.Id] + 1.0 / (K + Rank);
      Inc(Rank);
    end;
  end;

  // Dedup by Id: FTS and semantic return DIFFERENT objects for the same
  // row, so comparing references (All.Contains) would duplicate results.
  // The discarded duplicate is freed here: the caller sets OwnsObjects=False
  // on the input lists before freeing them, no one else owns it.
  procedure Merge(AList: TMemoryEntryList);
  var
    Item: TMemoryEntry;
  begin
    for Item in AList do
      if not ById.ContainsKey(Item.Id) then
      begin
        ById.Add(Item.Id, Item);
        All.Add(Item);
      end
      else
        Item.Free;
  end;

begin
  Scores := TDictionary<Integer, Double>.Create;
  ById   := TDictionary<Integer, TMemoryEntry>.Create;
  All    := TObjectList<TMemoryEntry>.Create(False);
  try
    AddRank(AFTS);
    AddRank(ASemantic);

    // Merge all unique entries (by Id)
    Merge(AFTS);
    Merge(ASemantic);

    // Sort by descending RRF score — selection sort
    for Si := 0 to All.Count - 2 do
      for Sj := Si + 1 to All.Count - 1 do
      begin
        SA := 0; SB := 0;
        Scores.TryGetValue(All[Si].Id, SA);
        Scores.TryGetValue(All[Sj].Id, SB);
        if SB > SA then
        begin
          E := All[Si]; All[Si] := All[Sj]; All[Sj] := E;
        end;
      end;

    SetLength(Result, Min(ALimit, All.Count));
    for I := 0 to High(Result) do
    begin
      Result[I].Entry     := All[I];
      Result[I].Score     := 0;
      Result[I].MatchType := 'hybrid';
      Scores.TryGetValue(All[I].Id, Result[I].Score);
    end;
    // Those left out of the limit are not in Result and no one else owns them:
    // free them here to avoid memory leak.
    for I := Length(Result) to All.Count - 1 do
      All[I].Free;
  finally
    Scores.Free;
    ById.Free;
    All.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

function TAiMemory.Store(const AContent: string; AType: TMemoryType;
  AImportance: Integer; const ATags: string; AMetadata: TJSONObject;
  ATtlDays: Integer): Integer;
var
  Entry: TMemoryEntry;
begin
  EnsureStorage;

  Entry := TMemoryEntry.Create;
  try
    Entry.Content    := AContent;
    Entry.MemoryType := AType;
    Entry.Importance := Max(1, Min(10, AImportance));
    Entry.Namespace  := FNamespace;
    Entry.DecayScore := 1.0;

    if ATags <> '' then
      Entry.Tags := ATags.Split([',']);

    if Assigned(AMetadata) then
      Entry.Metadata := AMetadata.ToJSON
    else
      Entry.Metadata := '{}';

    if ATtlDays > 0 then
      Entry.ExpiresAt := Now + ATtlDays;

    // Generate embedding if embedder is present
    if Assigned(FEmbedder) then
    begin
      try
        Entry.Embedding := FEmbedder.CreateEmbedding(AContent, '');
      except
        // Embedding fails → save without embedding
      end;
    end;

    Result := FStorage.StoreEntry(Entry);

    if Assigned(FOnStore) then
      FOnStore(Self, Entry);
  finally
    Entry.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

function TAiMemory.Search(const AQuery: string; ALimit: Integer;
  AMode: TMemorySearchMode): TMemorySearchResults;
var
  FTSList, SemList: TMemoryEntryList;
  I:                Integer;
begin
  EnsureStorage;

  case AMode of
    ms_FTS:
    begin
      FTSList := FStorage.SearchFTS(AQuery, FNamespace, ALimit);
      try
        SetLength(Result, FTSList.Count);
        for I := 0 to FTSList.Count - 1 do
        begin
          Result[I].Entry     := FTSList[I];
          Result[I].Score     := 1.0 - (I * 0.05);
          Result[I].MatchType := 'fts';
          FStorage.UpdateAccessStats(FTSList[I].Id, FNamespace);
        end;
      finally
        FTSList.OwnsObjects := False; // ownership transferred to Result entries
        FTSList.Free;
      end;
    end;

    ms_Semantic:
    begin
      Result := nil;
      if not Assigned(FEmbedder) then Exit;
      try
        var EmbData := FEmbedder.CreateEmbedding(AQuery, '');
        SemList := FStorage.SearchSemantic(EmbData, FNamespace, ALimit);
        try
          SetLength(Result, SemList.Count);
          for I := 0 to SemList.Count - 1 do
          begin
            Result[I].Entry     := SemList[I];
            Result[I].Score     := 1.0 - (I * 0.06);
            Result[I].MatchType := 'semantic';
            FStorage.UpdateAccessStats(SemList[I].Id, FNamespace);
          end;
        finally
          SemList.Free;
        end;
      except
        Result := nil;
      end;
    end;

    ms_Hybrid:
    begin
      FTSList := FStorage.SearchFTS(AQuery, FNamespace, ALimit * 2);
      SemList := TMemoryEntryList.Create(True);
      try
        if Assigned(FEmbedder) then
        begin
          try
            var EmbData := FEmbedder.CreateEmbedding(AQuery, '');
            var Tmp := FStorage.SearchSemantic(EmbData, FNamespace, ALimit * 2);
            try
              for var E in Tmp do SemList.Add(E);
            finally
              Tmp.Free;
            end;
          except
            // semantic fails → only FTS
          end;
        end;

        if SemList.Count = 0 then
        begin
          // Without semantic, degrade to pure FTS
          SetLength(Result, Min(ALimit, FTSList.Count));
          for I := 0 to High(Result) do
          begin
            Result[I].Entry     := FTSList[I];
            Result[I].Score     := 1.0 - (I * 0.05);
            Result[I].MatchType := 'fts';
            FStorage.UpdateAccessStats(FTSList[I].Id, FNamespace);
          end;
          // FTSList brings up to ALimit*2 entries; those that did not go to Result
          // are not owned by anyone else (the finally removes OwnsObjects before
          // freeing the list): free them here to avoid leak.
          for I := Length(Result) to FTSList.Count - 1 do
            FTSList[I].Free;
        end
        else
          Result := FuseRRF(FTSList, SemList, ALimit);

      finally
        FTSList.OwnsObjects := False; // ownership transferred to Result entries
        SemList.OwnsObjects := False;
        FTSList.Free;
        SemList.Free;
      end;
    end;
  end;

  if Assigned(FOnSearch) then
    FOnSearch(Self, AQuery, Result);
end;

// ---------------------------------------------------------------------------
// Recall
// ---------------------------------------------------------------------------

function TAiMemory.Recall(AMinImportance: Integer; ALimit: Integer): TMemoryEntryList;
begin
  EnsureStorage;
  Result := FStorage.Recall(AMinImportance, FNamespace, ALimit);
  if FAutoDecay then RefreshDecay;
end;

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

function TAiMemory.Delete(AId: Integer): Boolean;
begin
  EnsureStorage;
  Result := OwnsEntry(AId);
  if Result then
    FStorage.DeleteById(AId, FNamespace);
end;

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

function TAiMemory.Stats: TMemoryStats;
begin
  EnsureStorage;
  Result := FStorage.Stats(FNamespace);
end;

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

function TAiMemory.Context(const APrompt: string; ATokenBudget: Integer;
  AMinImportance: Integer): TMemoryContextResult;
begin
  EnsureStorage;
  Result := FContext.Build(APrompt, ATokenBudget, AMinImportance, FNamespace);
end;

// ---------------------------------------------------------------------------
// IAiPersistentMemory
// ---------------------------------------------------------------------------

function TAiMemory.BuildContext(const APrompt: string; ATokenBudget: Integer): string;
begin
  Result := Context(APrompt, ATokenBudget).FormattedText;
end;

procedure TAiMemory.AutoStore(const AContent: string; AImportance: Integer);
begin
  Store(AContent, mt_Fact, AImportance);
end;

// ---------------------------------------------------------------------------
// Automatic conversation analysis (fact extraction via cheap LLM)
// ---------------------------------------------------------------------------

procedure TAiMemory.NotifyExchange(const AUserPrompt, AAssistantResponse: string);
begin
  if not Assigned(FAnalyzer) then
    Exit; // feature completely off without Analyzer configured

  FExchangeBuffer.Append('Usuario: ').Append(AUserPrompt).Append(sLineBreak);
  FExchangeBuffer.Append('Asistente: ').Append(AAssistantResponse).Append(sLineBreak).Append(sLineBreak);
  Inc(FTurnsSinceAnalysis);

  // Buffer accumulates whenever Analyzer is present, regardless of
  // AnalysisInterval: if auto-trigger is off (0), it is still available
  // for a manual AnalyzeNow call.
  if (FAnalysisInterval > 0) and (FTurnsSinceAnalysis >= FAnalysisInterval) then
    AnalyzeNow;
end;

function TAiMemory.AnalyzeNow: Integer;
var
  LConversationText: string;
begin
  Result := 0;
  if not Assigned(FAnalyzer) or (FExchangeBuffer.Length = 0) then
    Exit;

  // Snapshot + immediate reset: if analysis fails later, we don't retry
  // the same window forever (avoids unbounded buffer growth).
  LConversationText   := FExchangeBuffer.ToString;
  FExchangeBuffer.Clear;
  FTurnsSinceAnalysis := 0;

  Result := DoAnalyzeAndStore(LConversationText);
end;

function TAiMemory.DoAnalyzeAndStore(const AConversationText: string): Integer;
var
  LPrompt, LResponse, LJsonText, LTypeStr, LContent, LTags: string;
  LJsonValue: TJSONValue;
  LJsonObj: TJSONObject;
  LMemories: TJSONArray;
  LItem: TJSONObject;
  LWorthSaving: Boolean;
  LImportance, LStart, LEnd, I: Integer;
begin
  Result := 0;

  // Extraction via prompt (not via Response_format:=tiaChatRfJsonSchema): Analyzer
  // can be any of the 12 providers, including cheap local models (Ollama, LM Studio)
  // where strict JSON mode is not always reliably supported, and it could also
  // clash with Tool_Active in some providers (e.g., Gemini). The text is parsed
  // defensively below.
  LPrompt :=
    'Analyze the following conversation fragment and decide if it contains information ' +
    'worth remembering long-term: facts about the user, preferences, decisions made, ' +
    'solutions to errors, work patterns. Ignore greetings, trivial chat, or one-off ' +
    'questions without reusable information.' + sLineBreak + sLineBreak +
    'Answer ONLY with a JSON object (no additional text, no markdown code blocks) ' +
    'with this exact form:' + sLineBreak +
    '{"worth_saving": boolean, "memories": [{"content": string, "type": ' +
    '"fact"|"preference"|"decision"|"error_fix"|"pattern"|"workflow"|"summary"|"custom", ' +
    '"importance": 1-10, "tags": "csv"}]}' + sLineBreak +
    'If there is nothing memorable, answer {"worth_saving": false, "memories": []}.' +
    sLineBreak + sLineBreak +
    'Conversation:' + sLineBreak + AConversationText;

  try
    LResponse := FAnalyzer.AddMessageAndRun(LPrompt, 'user', []);
  except
    on E: Exception do
    begin
      LogDebug('TAiMemory.Analyzer failed to analyze the conversation: ' + E.Message);
      Exit;
    end;
  end;

  // Tolerate that the model may wrap the response in text/markdown around
  // the JSON: we take only what is between the first '{' and the last '}'.
  LStart := Pos('{', LResponse);
  LEnd   := LastDelimiter('}', LResponse);
  if (LStart = 0) or (LEnd < LStart) then
  begin
    LogDebug('TAiMemory.Analyzer: response without recognizable JSON, discarded.');
    Exit;
  end;
  LJsonText := Copy(LResponse, LStart, LEnd - LStart + 1);

  LJsonValue := TJSONObject.ParseJSONValue(LJsonText);
  if not Assigned(LJsonValue) then
  begin
    LogDebug('TAiMemory.Analyzer: invalid JSON, discarded.');
    Exit;
  end;

  try
    if not (LJsonValue is TJSONObject) then
      Exit;
    LJsonObj := TJSONObject(LJsonValue);

    LWorthSaving := False;
    LJsonObj.TryGetValue('worth_saving', LWorthSaving);
    if not LWorthSaving then
      Exit;

    LMemories := LJsonObj.GetValue<TJSONArray>('memories');
    if not Assigned(LMemories) then
      Exit;

    for I := 0 to LMemories.Count - 1 do
    begin
      if not (LMemories.Items[I] is TJSONObject) then
        Continue;
      LItem := TJSONObject(LMemories.Items[I]);

      LContent := '';
      LItem.TryGetValue('content', LContent);
      if Trim(LContent) = '' then
        Continue;

      LTypeStr := 'custom';
      LItem.TryGetValue('type', LTypeStr);
      LImportance := 5;
      LItem.TryGetValue('importance', LImportance);
      LTags := '';
      LItem.TryGetValue('tags', LTags);

      Store(LContent, StrToMemoryType(LTypeStr), LImportance, LTags);
      Inc(Result);
    end;
  finally
    LJsonValue.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Get
// ---------------------------------------------------------------------------

function TAiMemory.Get(AId: Integer): TMemoryEntry;
begin
  EnsureStorage;
  Result := FStorage.GetById(AId, FNamespace);
  if Assigned(Result) then
    FStorage.UpdateAccessStats(AId, FNamespace);
end;

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

procedure TAiMemory.Update(AId: Integer; const AContent: string;
  AImportance: Integer);
var
  Current:      TMemoryEntry;
  NewContent:   string;
  NewImportance: Integer;
begin
  EnsureStorage;
  Current := FStorage.GetById(AId, FNamespace);
  if not Assigned(Current) then Exit;
  try
    if AContent <> '' then NewContent := AContent else NewContent := Current.Content;
    if AImportance >= 0 then NewImportance := AImportance else NewImportance := Current.Importance;
    FStorage.UpdateContent(AId, NewContent, NewImportance, FNamespace);
  finally
    Current.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Prune — removes old low-importance entries with low decay
// ---------------------------------------------------------------------------

procedure TAiMemory.Prune(AMinImportance: Integer; AMaxAgeDays: Integer);
var
  AllEntries: TMemoryEntryList;
  E: TMemoryEntry;
  Cutoff: TDateTime;
begin
  EnsureStorage;
  Cutoff     := Now - AMaxAgeDays;
  AllEntries := FStorage.ExportAll(FNamespace);
  try
    for E in AllEntries do
    begin
      if (E.Importance < AMinImportance) and
         (E.CreatedAt < Cutoff) and
         (TAiMemoryDecay.Compute(E.Importance, E.AccessCount, E.AccessedAt) < 0.2) then
        FStorage.DeleteById(E.Id, FNamespace);
    end;
  finally
    AllEntries.Free;
  end;
end;

// ---------------------------------------------------------------------------
// CleanupExpired
// ---------------------------------------------------------------------------

procedure TAiMemory.CleanupExpired;
begin
  EnsureStorage;
  FStorage.CleanupExpired(FNamespace);
end;

// ---------------------------------------------------------------------------
// BackfillEmbeddings
// ---------------------------------------------------------------------------

procedure TAiMemory.BackfillEmbeddings;
var
  AllEntries: TMemoryEntryList;
  E: TMemoryEntry;
begin
  if not Assigned(FEmbedder) then Exit;
  EnsureStorage;
  AllEntries := FStorage.ExportAll(FNamespace);
  try
    for E in AllEntries do
    begin
      if Length(E.Embedding) = 0 then
      begin
        try
          var Emb := FEmbedder.CreateEmbedding(E.Content, '');
          if Length(Emb) > 0 then
          begin
            // Re-store with embedding — storage does upsert by content_hash
            var NewEntry := TMemoryEntry.Create;
            try
              NewEntry.Assign(E);
              NewEntry.Embedding := Emb;
              FStorage.StoreEntry(NewEntry);
            finally
              NewEntry.Free;
            end;
          end;
        except
          // Continue with next
        end;
      end;
    end;
  finally
    AllEntries.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Export / Import
// ---------------------------------------------------------------------------

function TAiMemory.ExportToJSON: TJSONArray;
var
  AllEntries: TMemoryEntryList;
  E: TMemoryEntry;
begin
  EnsureStorage;
  Result     := TJSONArray.Create;
  AllEntries := FStorage.ExportAll(FNamespace);
  try
    for E in AllEntries do
      Result.AddElement(E.ToJSON);
  finally
    AllEntries.Free;
  end;
end;

procedure TAiMemory.ImportFromJSON(AData: TJSONArray);
var
  I:     Integer;
  Entry: TMemoryEntry;
begin
  EnsureStorage;
  for I := 0 to AData.Count - 1 do
  begin
    Entry := TMemoryEntry.FromJSON(AData.Items[I] as TJSONObject);
    try
      // Import ALWAYS to the active namespace: the "namespace" from JSON
      // cannot be used to write into another agent's namespace (issue #127).
      Entry.Namespace := FNamespace;
      FStorage.StoreEntry(Entry);
    finally
      Entry.Free;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Graph
// ---------------------------------------------------------------------------

function TAiMemory.Link(AFromId, AToId: Integer; const ARelation: string): Boolean;
begin
  EnsureStorage;
  Result := OwnsEntry(AFromId) and OwnsEntry(AToId);
  if Result then
    FStorage.LinkEntries(AFromId, AToId, ARelation, FNamespace);
end;

function TAiMemory.Unlink(AFromId, AToId: Integer): Boolean;
begin
  EnsureStorage;
  Result := OwnsEntry(AFromId) and OwnsEntry(AToId);
  if Result then
    FStorage.UnlinkEntries(AFromId, AToId, FNamespace);
end;

// Returns True if the Id exists in the active namespace. The storage already filters by
// namespace; this only serves to inform the caller (MCP tools used to respond
// "deleted"/"linked" even when the operation did nothing).
// Does not use Get: it should not count as an access.
function TAiMemory.OwnsEntry(AId: Integer): Boolean;
var
  Entry: TMemoryEntry;
begin
  Entry := FStorage.GetById(AId, FNamespace);
  Result := Assigned(Entry);
  Entry.Free;
end;

function TAiMemory.Links(AId: Integer): TMemoryEntryList;
begin
  EnsureStorage;
  Result := FStorage.GetLinks(AId, FNamespace);
end;

// ---------------------------------------------------------------------------
// RefreshDecay — recalculates decay_score of all memories in the namespace
// ---------------------------------------------------------------------------

procedure TAiMemory.RefreshDecay;
var
  AllEntries: TMemoryEntryList;
  E:     TMemoryEntry;
  Score: Double;
begin
  EnsureStorage;
  AllEntries := FStorage.ExportAll(FNamespace);
  try
    for E in AllEntries do
    begin
      Score := TAiMemoryDecay.Compute(E.Importance, E.AccessCount, E.AccessedAt);
      if Abs(Score - E.DecayScore) > 0.01 then
        FStorage.UpdateDecayScore(E.Id, Score, FNamespace);
    end;
  finally
    AllEntries.Free;
  end;
end;

end.
