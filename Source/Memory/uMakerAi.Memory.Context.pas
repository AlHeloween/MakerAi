unit uMakerAi.Memory.Context;

// Smart Context Builder for TAiMemory.
//
// Combines three sources of candidates and selects them within a token budget:
//   1. FTS search(prompt)       → score by lexical relevance
//   2. Semantic search(prompt)  → score by cosine similarity  [if embedder available]
//   3. Recall(importance >= 7)  → high importance memories, always included
//
// Combined ranking: 0.6 * relevance + 0.4 * (importance / 10)
// Token budget: accumulates entries sorted by score until limit is reached.
// Estimation: ~4 characters per token.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Math,
  uMakerAi.Memory.Types,
  uMakerAi.Memory.Storage,
  uMakerAi.Embeddings.Core;

type
  TAiMemoryContext = class
  private
    FStorage:      IAiMemoryStorage;
    FEmbedder:     TAiEmbeddingsCore;
    FMinImportance: Integer;

    function FormatEntry(AEntry: TMemoryEntry): string;
    function EstimateTokens(const AText: string): Integer;
  public
    constructor Create(AStorage: IAiMemoryStorage; AEmbedder: TAiEmbeddingsCore = nil);

    // Builds the context block to inject into the agent's prompt
    function Build(
      const APrompt:    string;
      ATokenBudget:     Integer = 2000;
      AMinImportance:   Integer = 1;
      const ANamespace: string  = 'default'
    ): TMemoryContextResult;
  end;

implementation

// ---------------------------------------------------------------------------

constructor TAiMemoryContext.Create(AStorage: IAiMemoryStorage;
  AEmbedder: TAiEmbeddingsCore);
begin
  inherited Create;
  FStorage       := AStorage;
  FEmbedder      := AEmbedder;
  FMinImportance := 1;
end;

function TAiMemoryContext.EstimateTokens(const AText: string): Integer;
begin
  // Conservative estimation: ~4 chars per token
  Result := Max(1, Length(AText) div 4);
end;

function TAiMemoryContext.FormatEntry(AEntry: TMemoryEntry): string;
var
  TagPart: string;
begin
  if Length(AEntry.Tags) > 0 then
    TagPart := ' tags:' + AEntry.TagsAsString
  else
    TagPart := '';

  Result := Format('[%s|imp:%d|decay:%.2f%s] %s',
    [MemoryTypeToStr(AEntry.MemoryType), AEntry.Importance,
     AEntry.DecayScore, TagPart, AEntry.Content]);
end;

function TAiMemoryContext.Build(const APrompt: string; ATokenBudget: Integer;
  AMinImportance: Integer; const ANamespace: string): TMemoryContextResult;
type
  TScoredCandidate = record
    Entry:     TMemoryEntry;
    Score:     Double;
    IsOwned:   Boolean;    // True = must be freed here if not used
  end;
var
  FTSList, RecallList, SemanticList: TMemoryEntryList;
  Candidates: TArray<TScoredCandidate>;
  CandCount:  Integer;
  SeenIds:    TDictionary<Integer, Boolean>;
  I, Rank:    Integer;
  Si, Sj:     Integer;
  Stmp:       TScoredCandidate;
  FTSScore:   Double;
  Lines:      TStringList;
  TokensUsed: Integer;
  EntryTokens: Integer;
  Entry:      TMemoryEntry;
  Formatted:  string;
  EmbData:    TAiEmbeddingData;

  procedure AddCandidate(AEntry: TMemoryEntry; AScore: Double; AOwned: Boolean);
  begin
    if SeenIds.ContainsKey(AEntry.Id) then
    begin
      if AOwned then AEntry.Free;
      Exit;
    end;
    SeenIds.Add(AEntry.Id, True);
    if CandCount >= Length(Candidates) then
      SetLength(Candidates, CandCount + 64);
    Candidates[CandCount].Entry   := AEntry;
    Candidates[CandCount].Score   := AScore;
    Candidates[CandCount].IsOwned := AOwned;
    Inc(CandCount);
  end;

begin
  Result := Default(TMemoryContextResult);
  CandCount := 0;
  SetLength(Candidates, 0);
  SeenIds := TDictionary<Integer, Boolean>.Create;
  Lines   := TStringList.Create;
  try
    // ── Source 1: FTS lexical ─────────────────────────────────────────────────
    FTSList := FStorage.SearchFTS(APrompt, ANamespace, 20);
    try
      Rank := 0;
      for Entry in FTSList do
      begin
        FTSScore := Max(0.0, 1.0 - (Rank * 0.05));
        var Combined := 0.6 * FTSScore + 0.4 * (Entry.Importance / 10.0);
        AddCandidate(Entry, Combined, True); // Context owns these entries
        Inc(Rank);
      end;
    finally
      FTSList.OwnsObjects := False; // ownership transferred to Candidates
      FTSList.Free;
    end;

    // ── Source 2: Semantic (if embedder available) ────────────────────────────
    if Assigned(FEmbedder) then
    begin
      try
        EmbData := FEmbedder.CreateEmbedding(APrompt, '');
        if Length(EmbData) > 0 then
        begin
          SemanticList := FStorage.SearchSemantic(EmbData, ANamespace, 15, 0.4);
          try
            for I := 0 to SemanticList.Count - 1 do
            begin
              Entry := SemanticList[I];
              var SemScore := 0.6 * (1.0 - I * 0.06) + 0.4 * (Entry.Importance / 10.0);
              AddCandidate(Entry, SemScore, True); // Context owns semantic entries
            end;
          finally
            SemanticList.Free;
          end;
        end;
      except
        // If embedder fails, continue with FTS only
      end;
    end;

    // ── Source 3: High importance recall (always include) ─────────────────────
    RecallList := FStorage.Recall(7, ANamespace, 10);
    try
      for Entry in RecallList do
        AddCandidate(Entry, 0.9, True); // Context owns recall entries
    finally
      RecallList.OwnsObjects := False; // ownership transferred to Candidates
      RecallList.Free;
    end;

    // ── Sort by descending score — selection sort (n typically < 50) ─────────
    SetLength(Candidates, CandCount);
    for Si := 0 to CandCount - 2 do
      for Sj := Si + 1 to CandCount - 1 do
        if Candidates[Sj].Score > Candidates[Si].Score then
        begin
          Stmp := Candidates[Si]; Candidates[Si] := Candidates[Sj]; Candidates[Sj] := Stmp;
        end;

    // ── Accumulate within token budget ──────────────────────────────────────
    TokensUsed := 0;
    SetLength(Result.MemoryIds, 0);
    for I := 0 to High(Candidates) do
    begin
      Entry     := Candidates[I].Entry;
      if Entry.Importance < AMinImportance then Continue;

      Formatted := FormatEntry(Entry);
      EntryTokens := EstimateTokens(Formatted);

      if TokensUsed + EntryTokens > ATokenBudget then
      begin
        Result.Truncated := True;
        Break;
      end;

      Lines.Add(Formatted);
      TokensUsed := TokensUsed + EntryTokens;
      Inc(Result.MemoryCount);

      SetLength(Result.MemoryIds, Result.MemoryCount);
      Result.MemoryIds[Result.MemoryCount - 1] := Entry.Id;

      // Update access statistics
      FStorage.UpdateAccessStats(Entry.Id, ANamespace);
    end;

    Result.FormattedText  := Lines.Text.Trim;
    Result.TokenEstimate  := TokensUsed;

  finally
    // Free own entries that were not kept in Result
    for I := 0 to High(Candidates) do
      if Candidates[I].IsOwned then
        Candidates[I].Entry.Free;
    Lines.Free;
    SeenIds.Free;
  end;
end;

end.
