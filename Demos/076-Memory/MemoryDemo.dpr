program MemoryDemo;

// =============================================================================
// DEMO 076 - TAiMemory: persistent semantic memory
// =============================================================================
// A chat without memory starts from zero in every session. TAiMemory stores
// facts, preferences and decisions in SQLite (FTS5) and retrieves them later by
// relevance, so they survive application shutdown.
//
// Demo walkthrough:
//   1. Store    : store memories with type, importance, tags and TTL.
//   2. Search   : search by text (FTS5) and see each result's score.
//   3. Recall   : bring only what matters, without a prior query.
//   4. Context  : build the text block ready to inject into the system
//                 prompt, respecting a token budget.
//   5. Stats    : namespace status.
//   6. Persistence: reopen the database and check everything is still there.
//
// WITHOUT an API KEY it works in FTS mode (ms_FTS): lexical search over SQLite.
// With OPENAI_API_KEY defined an embedder is attached and search becomes
// hybrid (ms_Hybrid): FTS + semantics fused with RRF, which is what
// allows finding "duplicate charge" by searching "billing problem".
//
// Usage modes:
//   MemoryDemo.exe            -> uses a temporary database and deletes it at the end
//   MemoryDemo.exe --keep     -> keeps the .db file for inspection
//   MemoryDemo.exe --otel     -> exports OTLP traces to localhost:4318
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.TypInfo,
  // FireDAC: in a console app the driver and factories must be explicitly
  // linked, or TAiMemory fails when opening the database with "Object factory for
  // class ... is missing".
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  uMakerAi.Memory.Types,
  uMakerAi.Memory,
  uMakerAi.Embeddings.Core,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.Telemetry;

function HasFlag(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AName) then
      Exit(True);
end;

function NombreTipo(A: TMemoryType): string;
begin
  Result := GetEnumName(TypeInfo(TMemoryType), Ord(A));
end;

// -----------------------------------------------------------------------------

procedure Sembrar(AMem: TAiMemory);
begin
  Writeln('');
  Writeln('== 1. Store: store typed memories ==');
  Writeln('');

  // Importance 1-10: this is what later filters Recall and orders Context.
  AMem.Store('The user works with Delphi 13 Florence on Windows', mt_Fact, 8, 'environment,delphi');
  AMem.Store('Prefers short answers with code examples', mt_Preference, 9, 'style');
  AMem.Store('It was decided to use SQLite as the RAG backend instead of Postgres', mt_Decision, 9, 'architecture,rag');
  AMem.Store('The "vec0 not found" error is resolved by copying vec0.dll next to the exe', mt_ErrorFix, 7, 'rag,sqlite');
  AMem.Store('Usually asks about performance before the API', mt_Pattern, 5, 'style');
  AMem.Store('A duplicate charge is claimed through the billing form', mt_Fact, 6, 'support');
  // Con TTL: caduca sola a los 7 dias. Util para contexto de una sola sesion.
  AMem.Store('Current session: reviewing the agents module', mt_Summary, 3, 'session', nil, 7);

  Writeln('   stored 7 memories (one with a 7-day TTL)');
  Writeln('   note: Store deduplicates by content hash within the namespace,');
  Writeln('         so repeating the same text updates instead of duplicating.');
end;

procedure Buscar(AMem: TAiMemory; AModo: TMemorySearchMode; const AConsulta: string);
var
  Res: TMemorySearchResults;
  I: Integer;
begin
  Writeln('');
  Writeln('   consulta: "' + AConsulta + '"');
  Res := AMem.Search(AConsulta, 3, AModo);
  if Length(Res) = 0 then
    Writeln('     (no results)')
  else
    for I := 0 to High(Res) do
      Writeln(Format('     [%.3f %-8s] %s', [Res[I].Score, Res[I].MatchType, Res[I].Entry.Content]));
end;

procedure Recordar(AMem: TAiMemory);
var
  Lista: TMemoryEntryList;
  E: TMemoryEntry;
begin
  Writeln('');
  Writeln('== 3. Recall: only what matters, without a query ==');
  Writeln('');

  // Without a query: returns the most important items. This is what is used
  // when opening a new session, before the user has written anything.
  Lista := AMem.Recall(8, 10);
  try
    for E in Lista do
      Writeln(Format('     imp=%d %-14s %s', [E.Importance, NombreTipo(E.MemoryType), E.Content]));
  finally
    Lista.Free;
  end;
end;

procedure ArmarContexto(AMem: TAiMemory);
var
  Ctx: TMemoryContextResult;
begin
  Writeln('');
  Writeln('== 4. Context: block ready for the system prompt ==');
  Writeln('');

  // Token budget deliberately low so the trimming is visible.
  Ctx := AMem.Context('How do I configure the project RAG?', 200, 1);
  Writeln(Format('   memories included: %d   estimated tokens: %d   truncated: %s',
    [Ctx.MemoryCount, Ctx.TokenEstimate, BoolToStr(Ctx.Truncated, True)]));
  Writeln('   ---------------- bloque generado ----------------');
  Writeln(Ctx.FormattedText);
  Writeln('   ------------------------------------------------');
end;

procedure MostrarStats(AMem: TAiMemory);
var
  S: TMemoryStats;
begin
  Writeln('');
  Writeln('== 5. Namespace stats ==');
  Writeln('');
  S := AMem.Stats;
  Writeln(Format('   namespace=%s  total=%d  importancia media=%.2f  decay medio=%.2f  expiradas=%d',
    [S.Namespace, S.TotalCount, S.AvgImportance, S.AvgDecay, S.ExpiredCount]));
end;

// -----------------------------------------------------------------------------

var
  Mem: TAiMemory;
  Embedder: TAiOpenAiEmbeddings;
  Telemetry: TAiTelemetry;
  DbPath, ApiKey: string;
  ModoBusqueda: TMemorySearchMode;
  Total: Integer;

begin
  Telemetry := nil;
  Embedder := nil;
  DbPath := TPath.Combine(TPath.GetTempPath, 'makerai_demo076_memoria.db');

  try
    if HasFlag('--otel') then
    begin
      Telemetry := TAiTelemetry.Create(nil);
      Telemetry.ServiceName := 'MemoryDemo';
      Telemetry.Enabled := True;
      Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
    end;

    Writeln('=== DEMO 076: TAiMemory, persistent semantic memory ===');

    // Empezar siempre limpio para que el demo sea reproducible
    if TFile.Exists(DbPath) then
      TFile.Delete(DbPath);

    ApiKey := GetEnvironmentVariable('OPENAI_API_KEY');
    if ApiKey <> '' then
    begin
      Embedder := TAiOpenAiEmbeddings.Create(nil);
      Embedder.ApiKey := ApiKey;
      Embedder.Model := 'text-embedding-3-small';
      ModoBusqueda := ms_Hybrid;
      Writeln('   embedder: OpenAI text-embedding-3-small -> busqueda HIBRIDA (FTS + semantica)');
    end
    else
    begin
      ModoBusqueda := ms_FTS;
      Writeln('   without OPENAI_API_KEY -> FTS search (lexical). Define the variable');
      Writeln('   to see semantic search and RRF fusion.');
    end;
    Writeln('   database: ' + DbPath);

    Mem := TAiMemory.Create(nil);
    try
      Mem.Namespace := 'demo076';
      Mem.DbPath := DbPath;
      if Assigned(Embedder) then
        Mem.Embedder := Embedder;

      Sembrar(Mem);

      Writeln('');
      Writeln('== 2. Search: recuperar por relevancia ==');
      Buscar(Mem, ModoBusqueda, 'sqlite');
      Buscar(Mem, ModoBusqueda, 'short answers');
      // Esta es la que separa FTS de semantica: no comparte palabras con la
      // memoria que deberia encontrar ("cobro duplicado ... facturacion").
      Buscar(Mem, ModoBusqueda, 'duplicate charge');

      Recordar(Mem);
      ArmarContexto(Mem);
      MostrarStats(Mem);
    finally
      Mem.Free;
    end;

    // --- 6. Persistencia: reabrir y comprobar que sigue todo ---
    Writeln('');
    Writeln('== 6. Persistencia: se cerro la base y se vuelve a abrir ==');
    Writeln('');
    Mem := TAiMemory.Create(nil);
    try
      Mem.Namespace := 'demo076';
      Mem.DbPath := DbPath;
      Total := Mem.Stats.TotalCount;
      Writeln(Format('   memorias recuperadas del disco: %d', [Total]));
      if Total > 0 then
        Writeln('   OK: la memoria sobrevive al cierre de la aplicacion')
      else
        Writeln('   ATENCION: no se recupero nada del disco');
    finally
      Mem.Free;
    end;

    if HasFlag('--keep') then
      Writeln('')
    else
    begin
      if TFile.Exists(DbPath) then
        TFile.Delete(DbPath);
      Writeln('');
      Writeln('   (temporary database deleted; use --keep to keep it)');
    end;

    Writeln('');
    Writeln('OK: memory demo completed.');

    if Assigned(Telemetry) then
    begin
      Telemetry.Flush;
      Telemetry.Free;
    end;
    Embedder.Free;
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
      Embedder.Free;
      ExitCode := 1;
    end;
  end;
end.
