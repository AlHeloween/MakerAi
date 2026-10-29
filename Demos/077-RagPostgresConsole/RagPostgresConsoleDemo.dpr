program RagPostgresConsoleDemo;

// =============================================================================
// DEMO 077 - Vector RAG over PostgreSQL + pgvector, from the console
// =============================================================================
// The RAG demos with Postgres (021, 023, 025) are all graphical, so there
// was no way to exercise the stack without opening the IDE. This does it
// headless, with LOCAL embeddings via Ollama: it needs no API key.
//
// Walkthrough:
//   1. Connects to PostgreSQL and checks the pgvector extension.
//   2. Checks that Ollama responds and that the embeddings model exists.
//   3. Creates the vector schema if missing (CreateSchema is idempotent:
//      CREATE TABLE/INDEX IF NOT EXISTS, including the HNSW index).
//   4. Seeds example movies into the 'pelicula' table (only missing ones,
//      comparing by title).
//   5. Indexes movies that still have no vector, generating the embedding
//      with Ollama and persisting via TAiRAGVectorPostgresDriver.
//   6. Semantic searches, and one with a metadata filter (TAiFilterCriteria).
//
// IMPORTANT about dimensions: the 'pelicula_vector' table in this database uses
// vector(1536) because it was indexed with OpenAI's text-embedding-3-small. Ollama
// models produce a different dimension (mxbai-embed-large = 1024,
// nomic-embed-text = 768) and also live in ANOTHER vector space, so
// mixing them in the same table would give meaningless results. That is why this
// demo uses its own table, with the dimension of the model it is given.
//
// Configuration via environment variables (with default values):
//   PGHOST      localhost      PGPORT      5432
//   PGDATABASE  peliculasdb    PGUSER      postgres
//   PGPASSWORD  (required)     PGLIBPQ     path to libpq.dll (autodetection)
//   OLLAMA_URL  http://localhost:11434/
//
// Usage modes:
//   RagPostgresConsoleDemo.exe
//   RagPostgresConsoleDemo.exe --model nomic-embed-text --dim 768
//   RagPostgresConsoleDemo.exe --no-seed      (does not insert new movies)
//   RagPostgresConsoleDemo.exe --reindex      (deletes vectors and reindexes)
//   RagPostgresConsoleDemo.exe --otel         (OTLP traces to localhost:4318)
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.JSON,
  System.Net.HttpClient,
  System.Generics.Collections,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.DApt,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param,
  FireDAC.Stan.Error,
  FireDAC.Phys,
  FireDAC.Comp.Client,
  // Sin esto FireDAC aborta con "Object factory for class ... TFDGUIxWaitCursor"
  // en cuanto abre la conexion. Es una app de consola, asi que la variante
  // que toca es ConsoleUI (existe en Windows y en Linux por igual).
  FireDAC.ConsoleUI.Wait,
  uMakerAi.Embeddings.Core,
  uMakerAi.Embeddings.Ollama,
  uMakerAi.RAG.MetaData,
  uMakerAi.RAG.Vectors.Index,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vector.Driver.Postgres,
  uMakerAi.Telemetry;

const
  ENTIDAD = 'PELICULAS_OLLAMA';

type
  TPeliSeed = record
    Titulo: string;
    Anio: Integer;
    Director: string;
    GeneroId: Integer;
    Sinopsis: string;
  end;

  // Example movies. Synopses were chosen with varied vocabulary so
  // semantic search has something to distinguish: there are pairs that
  // share a genre but not words, and vice versa.
const
  SEMILLAS: array [0 .. 14] of TPeliSeed = (
    (Titulo: 'The Last Train to Nowhere'; Anio: 2013; Director: 'Irene Vasquez'; GeneroId: 2;
     Sinopsis: 'A woman travels for three days by rail to say goodbye to her dying father.'),
    (Titulo: 'Phoenix Protocol'; Anio: 2021; Director: 'Diego Salazar'; GeneroId: 1;
     Sinopsis: 'A special operations team must recover a stolen weapon before dawn.'),
    (Titulo: 'The House of Clocks'; Anio: 2019; Director: 'Carla Mendez'; GeneroId: 5;
     Sinopsis: 'A restorer discovers that every clock in the mansion marks the time of a death.'),
    (Titulo: 'Orbit Zero'; Anio: 2024; Director: 'Marco Velez'; GeneroId: 4;
     Sinopsis: 'The crew of a space station loses contact with Earth and rations oxygen.'),
    (Titulo: 'My Astronaut Mother-in-Law'; Anio: 2022; Director: 'Pablo Ortiz'; GeneroId: 3;
     Sinopsis: 'A clumsy son-in-law must live for a week with the first woman to set foot on Mars.'),
    (Titulo: 'Little Paper Giants'; Anio: 2023; Director: 'Estudio Pixelia'; GeneroId: 6;
     Sinopsis: 'Origami that comes to life defends a children''s library from humidity and oblivion.'),
    (Titulo: 'Salt Scars'; Anio: 2011; Director: 'Sofia Duarte'; GeneroId: 2;
     Sinopsis: 'Two fisherwomen sisters reunite after twenty years in a ruined coastal town.'),
    (Titulo: 'Scarlet Code'; Anio: 2020; Director: 'Diego Salazar'; GeneroId: 1;
     Sinopsis: 'An analyst discovers that the attack she is investigating was planned by her own department.'),
    (Titulo: 'The Whisper of the Well'; Anio: 2016; Director: 'Carla Mendez'; GeneroId: 5;
     Sinopsis: 'An entire town falls silent every time someone peers into the cemetery well.'),
    (Titulo: 'The Moons of Ithaca'; Anio: 2018; Director: 'Marco Velez'; GeneroId: 4;
     Sinopsis: 'Colonists on a frozen moon decide whether to return home or sever the bond forever.'),
    (Titulo: 'Divorce in Three Acts'; Anio: 2017; Director: 'Pablo Ortiz'; GeneroId: 3;
     Sinopsis: 'An acting couple rehearses their separation in front of the audience every night.'),
    (Titulo: 'The Gear Garden'; Anio: 2025; Director: 'Estudio Pixelia'; GeneroId: 6;
     Sinopsis: 'A girl builds mechanical flowers to bring spring back to a gray city.'),
    (Titulo: 'Nobody Sleeps in August'; Anio: 2012; Director: 'Irene Vasquez'; GeneroId: 2;
     Sinopsis: 'During a heat wave, the residents of a building discover everyone''s secrets.'),
    (Titulo: 'Broken Border'; Anio: 2015; Director: 'Lucia Fernandez'; GeneroId: 1;
     Sinopsis: 'A forest ranger faces alone a gang that smuggles goods through the mountains.'),
    (Titulo: 'The Vigil'; Anio: 2014; Director: 'Sofia Duarte'; GeneroId: 5;
     Sinopsis: 'Una enfermera de turno nocturno jura que los pacientes hablan mientras duermen.'));

var
  Conn: TFDConnection;
  Driver: TAiRAGVectorPostgresDriver;
  Rag: TAiRAGVector;
  Embedder: TAiOllamaEmbeddings;
  Telemetry: TAiTelemetry;
  ModeloEmb: string;
  DimEmb: Integer;
  TablaVec: string;

  // ---------------------------------------------------------------------------

function Env(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

function HasFlag(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AName) then
      Exit(True);
end;

function ArgValue(const AName, ADefault: string): string;
var
  I: Integer;
begin
  Result := ADefault;
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), AName) then
      Exit(ParamStr(I + 1));
end;

function FindLibPq: string;
var
  Base: string;
  V: Integer;
begin
  Result := GetEnvironmentVariable('PGLIBPQ');
  if (Result <> '') and FileExists(Result) then
    Exit;
  // Autodeteccion: la mas nueva primero
  for V := 18 downto 12 do
  begin
    Base := Format('C:\Program Files\PostgreSQL\%d\bin\libpq.dll', [V]);
    if FileExists(Base) then
      Exit(Base);
  end;
  Result := ''; // que FireDAC lo busque en el PATH
end;

// ---------------------------------------------------------------------------
// 1. PostgreSQL
// ---------------------------------------------------------------------------
procedure ConectarPostgres;
var
  Link: TFDPhysPgDriverLink;
  LibPq, Ver: string;
begin
  Writeln('== 1. PostgreSQL ==');

  Link := TFDPhysPgDriverLink.Create(nil);
  LibPq := FindLibPq;
  if LibPq <> '' then
  begin
    Link.VendorLib := LibPq;
    Writeln('   libpq: ' + LibPq);
  end
  else
    Writeln('   libpq: not found, it will be searched in PATH');

  Conn := TFDConnection.Create(nil);
  Conn.DriverName := 'PG';
  Conn.Params.Values['Server'] := Env('PGHOST', 'localhost');
  Conn.Params.Values['Port'] := Env('PGPORT', '5432');
  Conn.Params.Values['Database'] := Env('PGDATABASE', 'peliculasdb');
  Conn.Params.Values['User_Name'] := Env('PGUSER', 'postgres');
  Conn.Params.Values['Password'] := Env('PGPASSWORD', '');
  Conn.Params.Values['CharacterSet'] := 'UTF8';
  Conn.LoginPrompt := False;

  if Conn.Params.Values['Password'] = '' then
    raise Exception.Create('Falta la variable de entorno PGPASSWORD');

  Conn.Connected := True;
  Ver := Conn.ExecSQLScalar('select version()');
  Writeln('   connected to ' + Conn.Params.Values['Database'] + '@' + Conn.Params.Values['Server'] + ':' +
    Conn.Params.Values['Port']);
  Writeln('   ' + Copy(Ver, 1, 60));

  if Conn.ExecSQLScalar('select count(*) from pg_extension where extname = ''vector''') = 0 then
    raise Exception.Create('The pgvector extension is not installed in this database');
  Writeln('   pgvector: present (' + VarToStr(Conn.ExecSQLScalar('select extversion from pg_extension where extname=''vector''')) + ')');
end;

// ---------------------------------------------------------------------------
// 2. Ollama
// ---------------------------------------------------------------------------
procedure VerificarOllama(const AUrl: string);
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  Root: TJSONObject;
  Models: TJSONArray;
  V: TJSONValue;
  Nombre, Lista: string;
  Encontrado: Boolean;
begin
  Writeln('');
  Writeln('== 2. Ollama ==');

  Http := THTTPClient.Create;
  try
    Http.ConnectionTimeout := 5000;
    Http.ResponseTimeout := 5000;
    try
      Resp := Http.Get(AUrl.TrimRight(['/']) + '/api/tags');
    except
      on E: Exception do
        raise Exception.Create('Ollama does not respond at ' + AUrl + '. Start it with "ollama serve". Detail: ' + E.Message);
    end;
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('Ollama returned HTTP %d', [Resp.StatusCode]);

    Root := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8)) as TJSONObject;
    try
      Encontrado := False;
      Lista := '';
      if Root.TryGetValue<TJSONArray>('models', Models) then
        for V in Models do
          if V is TJSONObject then
          begin
            Nombre := TJSONObject(V).GetValue<string>('name', '');
            if Nombre.StartsWith(ModeloEmb) then
              Encontrado := True;
            if Nombre.Contains('embed') then
              Lista := Lista + '  ' + Nombre;
          end;
      if not Encontrado then
        raise Exception.CreateFmt('The model "%s" is not in Ollama. Available embedding models:%s' + sLineBreak +
          'Download it with: ollama pull %s', [ModeloEmb, Lista, ModeloEmb]);
      Writeln('   embeddings model: ' + ModeloEmb + '  (dim ' + IntToStr(DimEmb) + ')');
    finally
      Root.Free;
    end;
  finally
    Http.Free;
  end;
end;

// ---------------------------------------------------------------------------
// 3-4. Esquema y siembra
// ---------------------------------------------------------------------------
procedure CrearEsquema;
begin
  Writeln('');
  Writeln('== 3. Vector schema ==');

  // Base catalog. The demo claims to be self-contained, but it assumed
  // that 'pelicula' and 'genero' already existed from demos 021/023: on a
  // newly created database seeding died with 'relation "pelicula" does not exist'.
  // They are created here if missing, so it starts against an empty database.
  Conn.ExecSQL(
    'create table if not exists genero (' +
    '  id serial primary key,' +
    '  nombre varchar(80) not null unique)');
  Conn.ExecSQL(
    'create table if not exists pelicula (' +
    '  id serial primary key,' +
    '  titulo varchar(200) not null,' +
    '  anio integer,' +
    '  director varchar(150),' +
    '  genero_id integer references genero(id),' +
    '  sinopsis text,' +
    '  creado timestamp default now())');
  // Genres 1..6 are the ones referenced by the seeds via GeneroId; without
  // them the insertion violates the foreign key in a new database.
  Conn.ExecSQL(
    'insert into genero (id, nombre) values ' +
    '(1,''Accion''),(2,''Drama''),(3,''Comedia''),' +
    '(4,''Ciencia ficcion''),(5,''Suspenso''),(6,''Documental'') ' +
    'on conflict (id) do nothing');
  // In a DO block: 'select setval(...)' returns a result set and FireDAC
  // refuses to execute it with ExecSQL ("use Open method for SELECT-like commands").
  Conn.ExecSQL(
    'do $$ begin perform setval(pg_get_serial_sequence(''genero'',''id''), ' +
    'greatest((select max(id) from genero), 1)); end $$');
  Writeln('   base catalog: genero and pelicula tables ready');

  Driver.CreateSchema(TablaVec, DimEmb);
  Writeln('   table ' + TablaVec + ' ready (vector(' + IntToStr(DimEmb) + '), cosine HNSW index, GIN over properties and FTS)');
  Writeln('   note: pelicula_vector is not touched, it is vector(1536) from OpenAI');
end;

function SembrarPeliculas: Integer;
var
  Q: TFDQuery;
  S: TPeliSeed;
  I: Integer;
begin
  Result := 0;
  Writeln('');
  Writeln('== 4. Movie seeding ==');

  if HasFlag('--no-seed') then
  begin
    Writeln('   --no-seed: nothing is inserted');
    Exit;
  end;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    for I := Low(SEMILLAS) to High(SEMILLAS) do
    begin
      S := SEMILLAS[I];
      // Idempotent: compares by title so the demo can be run several times
      Q.SQL.Text := 'select count(*) from pelicula where titulo = :t';
      Q.ParamByName('t').AsString := S.Titulo;
      Q.Open;
      if Q.Fields[0].AsInteger > 0 then
      begin
        Q.Close;
        Continue;
      end;
      Q.Close;

      Q.SQL.Text := 'insert into pelicula (titulo, anio, director, genero_id, sinopsis, creado) ' +
        'values (:t, :a, :d, :g, :s, now())';
      Q.ParamByName('t').AsString := S.Titulo;
      Q.ParamByName('a').AsInteger := S.Anio;
      Q.ParamByName('d').AsString := S.Director;
      Q.ParamByName('g').AsInteger := S.GeneroId;
      Q.ParamByName('s').AsString := S.Sinopsis;
      Q.ExecSQL;
      Inc(Result);
    end;
  finally
    Q.Free;
  end;

  Writeln(Format('   inserted %d new movies (duplicates are skipped by title)', [Result]));
  // ExecSQLScalar returns Variant: it must be converted, %d does not accept it
  Writeln('   total in catalog: ' + VarToStr(Conn.ExecSQLScalar('select count(*) from pelicula')));
end;

// ---------------------------------------------------------------------------
// 5. Indexado
// ---------------------------------------------------------------------------
function IndexarPendientes: Integer;
var
  Q: TFDQuery;
  Meta: TAiEmbeddingMetaData;
  Yaestan: TDictionary<string, Boolean>;
  Texto, PeliId: string;
  Nodo: TAiEmbeddingNode;
begin
  Result := 0;
  Writeln('');
  Writeln('== 5. Indexing with Ollama ==');

  if HasFlag('--reindex') then
  begin
    Driver.Clear(ENTIDAD);
    Writeln('   --reindex: previous vectors deleted');
  end;

  Yaestan := TDictionary<string, Boolean>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;

    // Which movies already have a vector in THIS table and entity
    Q.SQL.Text := Format('select properties->>''pelicula_id'' as pid from %s where entidad = :e', [TablaVec]);
    Q.ParamByName('e').AsString := ENTIDAD;
    Q.Open;
    while not Q.Eof do
    begin
      if not Q.Fields[0].IsNull then
        Yaestan.AddOrSetValue(Q.Fields[0].AsString, True);
      Q.Next;
    end;
    Q.Close;
    Writeln(Format('   already indexed: %d', [Yaestan.Count]));

    Q.SQL.Text := 'select p.id, p.titulo, p.anio, p.director, coalesce(g.nombre, ''?'') as genero, ' +
      'coalesce(p.sinopsis, '''') as sinopsis from pelicula p left join genero g on g.id = p.genero_id order by p.id';
    Q.Open;
    while not Q.Eof do
    begin
      PeliId := Q.FieldByName('id').AsString;
      if Yaestan.ContainsKey(PeliId) then
      begin
        Q.Next;
        Continue;
      end;

      // WHAT is vectorized matters as much as the model. The first version of
      // this demo indexed "Title (year). Director: X. Genre: Y. Synopsis",
      // and retrieval was poor: all documents started with the
      // same template, so the embedding was dominated by
      // boilerplate and scores clustered in a narrow band (0.57-0.66).
      // Putting the semantically loaded content first -title and synopsis- and
      // leaving the record at the end noticeably improves separation.
      // The record is still worth including: it allows asking about director or
      // genre in natural language. And for exact filtering there are the
      // metadata, which do not depend on the embedding.
      Texto := Format('%s. %s (%s, %d, dirigida por %s)', [Q.FieldByName('titulo').AsString,
        Q.FieldByName('sinopsis').AsString, Q.FieldByName('genero').AsString, Q.FieldByName('anio').AsInteger,
        Q.FieldByName('director').AsString]);

      Meta := TAiEmbeddingMetaData.Create;
      try
        // Metadata is what later allows filtering without recomputing vectors
        Meta['pelicula_id'] := PeliId;
        Meta['titulo'] := Q.FieldByName('titulo').AsString;
        Meta['anio'] := Q.FieldByName('anio').AsInteger;
        Meta['director'] := Q.FieldByName('director').AsString;
        Meta['genero'] := Q.FieldByName('genero').AsString;

        Nodo := Rag.AddItem(Texto, Meta); // genera el embedding y persiste via driver
        if Assigned(Nodo) then
          Inc(Result);
        Write('.');
      finally
        Meta.Free;
      end;
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
    Yaestan.Free;
  end;

  Writeln('');
  Writeln(Format('   indexed now: %d', [Result]));
  Writeln(Format('   total vectors in %s: %s', [TablaVec,
    VarToStr(Conn.ExecSQLScalar(Format('select count(*) from %s where entidad = %s', [TablaVec, QuotedStr(ENTIDAD)])))]));
end;

// ---------------------------------------------------------------------------
// 6. Busquedas
// ---------------------------------------------------------------------------
procedure Buscar(const APrompt: string; ALimit: Integer; AFilter: TAiFilterCriteria; const ATitulo: string = '');
var
  Res: TAiRAGVector;
  Nodo: TAiEmbeddingNode;
  Target: TAiEmbeddingNode;
begin
  Writeln('');
  if ATitulo <> '' then
    Writeln('   ' + ATitulo)
  else
    Writeln('   query: "' + APrompt + '"');

  Target := Rag.CreateEmbeddingNode(APrompt);
  try
    Res := Driver.Search(Target, ENTIDAD, ALimit, 0.0, AFilter, Rag.SearchOptions);
    try
      if (Res = nil) or (Res.Count = 0) then
        Writeln('     (no results)')
      else
        for Nodo in Res.Items do
          Writeln(Format('     [%.4f] %-28s %s %s', [Nodo.Idx, VarToStr(Nodo.MetaData['titulo']),
            VarToStr(Nodo.MetaData['anio']), VarToStr(Nodo.MetaData['genero'])]));
    finally
      Res.Free;
    end;
  finally
    Target.Free;
  end;
end;

procedure Busquedas;
var
  Filtro: TAiFilterCriteria;
begin
  Writeln('');
  Writeln('== 6. Semantic search ==');

  // None of these queries shares the exact words with the synopsis:
  // if it returns what is expected, the embedding is doing its job.
  Buscar('spacecraft and travel outside the solar system', 3, nil);
  Buscar('something scary in an old house', 3, nil);
  Buscar('a story to laugh with the in-laws', 3, nil);
  Buscar('reunion between relatives after many years', 3, nil);

  Writeln('');
  Writeln('== 7. Search with metadata filter ==');
  Writeln('   (the filter is applied in SQL over properties, without recomputing vectors)');

  Filtro := TAiFilterCriteria.Create;
  try
    Filtro.AddGreater('anio', 2019);
    Buscar('space science fiction', 5, Filtro);
  finally
    Filtro.Free;
  end;

  // -------------------------------------------------------------------------
  // Embeddings only vs hybrid
  // -------------------------------------------------------------------------
  // Embeddings understand meaning but lose rare terms and
  // proper names; BM25 does exactly the opposite. The Postgres driver
  // resolves lexical matching with ts_rank_cd over the search_vector column (GIN
  // index, 'spanish' configuration) and fuses both rankings with RRF.
  Writeln('');
  Writeln('== 8. Embeddings only vs hybrid (BM25 + RRF) ==');

  Rag.SearchOptions.UseEmbeddings := True;
  Rag.SearchOptions.UseBM25 := False;
  Rag.SearchOptions.UseRRF := False;
  Buscar('origami that defends a library', 3, nil, 'embeddings only  -> "origami that defends a library"');

  Rag.SearchOptions.UseBM25 := True;
  Rag.SearchOptions.UseRRF := True;
  Buscar('origami that defends a library', 3, nil, 'hybrid BM25+RRF  -> the same query');

  // A proper name is the case where it shows most
  Rag.SearchOptions.UseBM25 := False;
  Rag.SearchOptions.UseRRF := False;
  Buscar('movies by Estudio Pixelia', 3, nil, 'embeddings only  -> "movies by Estudio Pixelia"');

  Rag.SearchOptions.UseBM25 := True;
  Rag.SearchOptions.UseRRF := True;
  Buscar('movies by Estudio Pixelia', 3, nil, 'hybrid BM25+RRF  -> the same query');
end;

// ---------------------------------------------------------------------------

begin
  Telemetry := nil;
  Conn := nil;
  Driver := nil;
  Rag := nil;
  Embedder := nil;
  try
    try
      ModeloEmb := ArgValue('--model', 'mxbai-embed-large');
      DimEmb := StrToIntDef(ArgValue('--dim', ''), 0);
      if DimEmb = 0 then
      begin
        // Dimensiones conocidas de los modelos de embeddings de Ollama
        if ModeloEmb.StartsWith('nomic-embed-text') then
          DimEmb := 768
        else if ModeloEmb.StartsWith('all-minilm') then
          DimEmb := 384
        else
          DimEmb := 1024; // mxbai-embed-large
      end;
      TablaVec := 'pelicula_vector_ollama_' + IntToStr(DimEmb);

      if HasFlag('--otel') then
      begin
        Telemetry := TAiTelemetry.Create(nil);
        Telemetry.ServiceName := 'RagPostgresConsoleDemo';
        Telemetry.Enabled := True;
        Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
      end;

      Writeln('=== DEMO 077: vector RAG over PostgreSQL + pgvector (local embeddings) ===');
      Writeln('');

      ConectarPostgres;
      VerificarOllama(Env('OLLAMA_URL', 'http://localhost:11434/'));

      Embedder := TAiOllamaEmbeddings.Create(nil);
      Embedder.Url := Env('OLLAMA_URL', 'http://localhost:11434/');
      Embedder.Model := ModeloEmb;
      Embedder.Dimensions := DimEmb;

      Driver := TAiRAGVectorPostgresDriver.Create(nil);
      Driver.Connection := Conn;
      Driver.TableName := TablaVec;
      Driver.CurrentEntidad := ENTIDAD;

      Rag := TAiRAGVector.Create(nil);
      Rag.Embeddings := Embedder;
      Rag.Driver := Driver;
      Rag.Entidad := ENTIDAD;

      CrearEsquema;
      SembrarPeliculas;
      IndexarPendientes;
      Busquedas;

      Writeln('');
      Writeln('OK: the full RAG cycle over pgvector worked with local embeddings.');
      ExitCode := 0;
    except
      on E: Exception do
      begin
        Writeln('');
        Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Rag.Free;
    Driver.Free;
    Embedder.Free;
    if Assigned(Conn) then
    begin
      Conn.Connected := False;
      Conn.Free;
    end;
    if Assigned(Telemetry) then
    begin
      Telemetry.Flush;
      Telemetry.Free;
    end;
  end;
end.
