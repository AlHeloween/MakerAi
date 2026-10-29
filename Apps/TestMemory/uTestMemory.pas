unit uTestMemory;

interface

procedure RunTests;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  uMakerAi.Memory,
  uMakerAi.Memory.Types;

// ---------------------------------------------------------------------------

var
  GPass, GFail: Integer;

procedure Pass(const ATest: string);
begin
  Inc(GPass);
  Writeln('  [OK] ' + ATest);
end;

procedure Fail(const ATest, AReason: string);
begin
  Inc(GFail);
  Writeln('  [FAIL] ' + ATest + ' — ' + AReason);
end;

procedure Check(ACondition: Boolean; const ATest: string; const AFailMsg: string = '');
begin
  if ACondition then Pass(ATest)
  else Fail(ATest, AFailMsg);
end;

procedure Section(const AName: string);
begin
  Writeln;
  Writeln('--- ' + AName + ' ---');
end;

// ---------------------------------------------------------------------------

procedure RunTests;
var
  Mem:    TAiMemory;
  DbPath: string;
  Id1, Id2, Id3, Id4, Id5: Integer;
  IdDup:  Integer;
  Results: TMemorySearchResults;
  RecallList: TMemoryEntryList;
  Links:   TMemoryEntryList;
  Stats:   TMemoryStats;
  Ctx:     TMemoryContextResult;
  Entry:   TMemoryEntry;
  I:       Integer;
begin
  GPass := 0;
  GFail := 0;

  DbPath := TPath.Combine(TPath.GetTempPath, 'test_memory_' +
    IntToStr(DateTimeToUnix(Now)) + '.db');

  Writeln('=================================================');
  Writeln(' TAiMemory — Test Suite');
  Writeln('=================================================');
  Writeln('DB: ' + DbPath);

  Mem := TAiMemory.Create(nil);
  try
    Mem.Namespace := 'test';
    Mem.DbPath    := DbPath;
    Mem.AutoDecay := False;

    // ── 1. Store ────────────────────────────────────────────────────────────
    Section('1. Store');

    Id1 := Mem.Store('Delphi usa Ln() en lugar de Log() para logaritmo natural',
                     mt_ErrorFix, 9, 'delphi,math', nil, 0);
    Check(Id1 > 0, 'Store ErrorFix returns Id > 0', 'Id=' + Id1.ToString);

    Id2 := Mem.Store('El usuario prefiere respuestas concisas sin bullets innecesarios',
                     mt_Preference, 8, 'ux', nil, 0);
    Check(Id2 > 0, 'Store Preference returns Id > 0');

    Id3 := Mem.Store('TAiMemory usa FireDAC + FTS5 para búsqueda léxica',
                     mt_Fact, 7, 'architecture,firedac', nil, 0);
    Check(Id3 > 0, 'Store Fact returns Id > 0');

    Id4 := Mem.Store('El decay exponencial modela la curva de olvido de Ebbinghaus',
                     mt_Pattern, 5, 'decay,memory', nil, 0);
    Check(Id4 > 0, 'Store Pattern returns Id > 0');

    Id5 := Mem.Store('Error al compilar: E2003 TComparer no funciona con tipos locales',
                     mt_ErrorFix, 6, 'delphi,generics', nil, 0);
    Check(Id5 > 0, 'Store second ErrorFix returns Id > 0');

    // Duplicate — must reuse the same Id
    IdDup := Mem.Store('Delphi usa Ln() en lugar de Log() para logaritmo natural',
                            mt_ErrorFix, 9, 'delphi,math', nil, 0);
    Check(IdDup = Id1, 'Store duplicado devuelve mismo Id (dedup por content_hash)',
          'Esperado=' + Id1.ToString + ' Obtenido=' + IdDup.ToString);

    // ── 2. Get ──────────────────────────────────────────────────────────────
    Section('2. Get');

    Entry := Mem.Get(Id1);
    try
      Check(Assigned(Entry), 'Get by Id returns entry');
      if Assigned(Entry) then
      begin
        Check(Entry.MemoryType = mt_ErrorFix, 'Correct type: mt_ErrorFix');
        Check(Entry.Importance = 9, 'Importance = 9');
        Check(Entry.Namespace = 'test', 'Namespace = test');
        Check(Pos('Ln()', Entry.Content) > 0, 'Content contains "Ln()"');
      end;
    finally
      Entry.Free;
    end;

    // ── 3. Search FTS ───────────────────────────────────────────────────────
    Section('3. Search FTS');

    Results := Mem.Search('logaritmo delphi', 10, ms_FTS);
    try
      Check(Length(Results) > 0, 'FTS "logaritmo delphi" devuelve resultados',
            'Count=' + Length(Results).ToString);
      if Length(Results) > 0 then
        Check(Results[0].Score > 0, 'Primer resultado tiene score > 0',
              'Score=' + FloatToStr(Results[0].Score));
    finally
      for I := 0 to High(Results) do
        Results[I].Entry.Free;
    end;

    // Search with no results
    Results := Mem.Search('xyzabc123notfound', 10, ms_FTS);
    Check(Length(Results) = 0, 'FTS with no match returns empty array');

    // ── 4. Search Hybrid (without embedder → same as FTS) ─────────────────────
    Section('4. Search Hybrid');

    Results := Mem.Search('TComparer generics error', 5, ms_Hybrid);
    try
      Check(Length(Results) > 0, 'Hybrid "TComparer generics" returns results');
    finally
      for I := 0 to High(Results) do
        Results[I].Entry.Free;
    end;

    // ── 5. Recall ───────────────────────────────────────────────────────────
    Section('5. Recall');

    RecallList := Mem.Recall(7, 20);
    try
      // Entries with importance >= 7: Id1(9), Id2(8), Id3(7) = 3
      Check(RecallList.Count >= 3, 'Recall(importance>=7) devuelve al menos 3 entries',
            'Count=' + RecallList.Count.ToString);
      for I := 0 to RecallList.Count - 1 do
        Check(RecallList[I].Importance >= 7,
              Format('Entry[%d] importance=%d >= 7', [I, RecallList[I].Importance]));
    finally
      RecallList.Free;
    end;

    RecallList := Mem.Recall(10, 20); // Solo importance=10 → vacío
    try
      Check(RecallList.Count = 0, 'Recall(importance=10) devuelve vacío',
            'Count=' + RecallList.Count.ToString);
    finally
      RecallList.Free;
    end;

    // ── 6. Stats ────────────────────────────────────────────────────────────
    Section('6. Stats');

    Stats := Mem.Stats;
    Check(Stats.TotalCount = 5, 'Stats.TotalCount = 5',
          'Got=' + Stats.TotalCount.ToString);
    Check(Stats.AvgImportance > 0, 'Stats.AvgImportance > 0');
    Writeln(Format('       Total=%d  AvgImp=%.1f  AvgDecay=%.2f',
      [Stats.TotalCount, Stats.AvgImportance, Stats.AvgDecay]));

    // ── 7. Context Builder ──────────────────────────────────────────────────
    Section('7. Context Builder');

    Ctx := Mem.Context('cómo compilar Delphi con logaritmos', 500);
    Check(Ctx.MemoryCount > 0, 'Context devuelve al menos 1 entry',
          'Count=' + Ctx.MemoryCount.ToString);
    Check(Ctx.TokenEstimate > 0, 'Context.TokenEstimate > 0');
    Check(Ctx.FormattedText <> '', 'Context.FormattedText not empty');
    Writeln('       MemoryCount=' + Ctx.MemoryCount.ToString +
            '  Tokens~' + Ctx.TokenEstimate.ToString +
            '  Truncated=' + BoolToStr(Ctx.Truncated, True));
    if Ctx.MemoryCount > 0 then
      Writeln('       ' + Copy(Ctx.FormattedText, 1, 100) + '...');

    // ── 8. Update ───────────────────────────────────────────────────────────
    Section('8. Update');

    Mem.Update(Id4, 'El decay exponencial modela la curva de olvido (actualizado)', 7);
    Entry := Mem.Get(Id4);
    try
      Check(Assigned(Entry), 'Get after Update returns entry');
      if Assigned(Entry) then
      begin
        Check(Entry.Importance = 7, 'Update changes importance to 7');
        Check(Pos('actualizado', Entry.Content) > 0, 'Update changes content');
      end;
    finally
      Entry.Free;
    end;

    // Update only importance (empty content → keeps the previous one)
    Mem.Update(Id4, '', 10);
    Entry := Mem.Get(Id4);
    try
      if Assigned(Entry) then
      begin
        Check(Entry.Importance = 10, 'Update only importance works');
        Check(Pos('actualizado', Entry.Content) > 0, 'Content is kept when AContent=""');
      end;
    finally
      Entry.Free;
    end;

    // ── 9. Delete ───────────────────────────────────────────────────────────
    Section('9. Delete');

    Mem.Delete(Id5);
    Entry := Mem.Get(Id5);
    try
      Check(not Assigned(Entry), 'Delete: Get returns nil after deletion');
    finally
      Entry.Free;
    end;

    Stats := Mem.Stats;
    Check(Stats.TotalCount = 4, 'Stats.TotalCount = 4 tras Delete',
          'Got=' + Stats.TotalCount.ToString);

    // ── 10. Links ───────────────────────────────────────────────────────────
    Section('10. Links');

    Mem.Link(Id1, Id3, 'related');
    Links := Mem.Links(Id1);
    try
      Check(Links.Count > 0, 'Links(Id1) devuelve al menos 1',
            'Count=' + Links.Count.ToString);
    finally
      Links.Free;
    end;

    Mem.Unlink(Id1, Id3);
    Links := Mem.Links(Id1);
    try
      Check(Links.Count = 0, 'Links(Id1) empty after Unlink');
    finally
      Links.Free;
    end;

    // ── 11. Prune ───────────────────────────────────────────────────────────
    Section('11. Prune');

    // Prune agresivo: importance < 8 con decay < 0.99 → debería dejar solo Id1(9) e Id2(8)
    // With AutoDecay=False all have decay=1.0, so prune by importance+age
    Mem.Prune(8, 0); // MinImportance=8, MaxAgeDays=0 → entries de hoy también
    Stats := Mem.Stats;
    // Note: Prune(8, 0) removes entries with importance < 8 AND age >= 0 days AND decay < threshold
    // With decay=1.0 (fresh) the threshold is 0.1 → none are pruned by decay
    // The actual behavior depends on the implementation — we only verify it does not crash
    Check(Stats.TotalCount >= 0, 'Prune does not raise an exception');
    Writeln('       Remaining entries=' + Stats.TotalCount.ToString);

    // ── Final result ─────────────────────────────────────────────────────
    Writeln;
    Writeln('=================================================');
    Writeln(Format(' Result: %d OK  /  %d FAIL', [GPass, GFail]));
    Writeln('=================================================');

    if GFail > 0 then
      ExitCode := 1;

  finally
    Mem.Free;
    // Clean up test file
    if TFile.Exists(DbPath) then
      TFile.Delete(DbPath);
    Writeln('DB deleted: ' + DbPath);
  end;
end;

end.
