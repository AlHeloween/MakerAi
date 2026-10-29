program RagChatOllamaDemo;

// =============================================================================
// DEMO 078 - Complete 100% local RAG: pgvector + Ollama (embeddings and chat)
// =============================================================================
// Demo 077 goes as far as retrieving the relevant fragments. This closes the
// cycle: it retrieves, builds the context and passes it to a local LLM so it
// can answer. No API keys, without leaving the machine.
//
// The demo is built so it is VISIBLE why RAG is needed: each
// question is asked TWICE against the same model.
//
//   WITHOUT context : the model has no way to know a private catalog, and
//                  answers anyway: it invents titles, directors and years with
//                  confidence. This is hallucination in its pure state.
//   WITH context    : the relevant records are retrieved from PostgreSQL and
//                  injected into the system prompt. The model then answers
//                  about real data, and can cite.
//
// Requires the vector table to exist and be populated: run demo 077
// first (which creates the schema, seeds movies and indexes).
//
// Configuration via environment variables (same defaults as 077):
//   PGHOST localhost   PGPORT 5432   PGDATABASE peliculasdb
//   PGUSER postgres    PGPASSWORD (obligatoria)
//   OLLAMA_URL http://localhost:11434/
//
// Usage modes:
//   RagChatOllamaDemo.exe
//   RagChatOllamaDemo.exe --chat gpt-oss:20b
//   RagChatOllamaDemo.exe --embed mxbai-embed-large --dim 1024
//   RagChatOllamaDemo.exe --ask "what horror movies are there?"
//   RagChatOllamaDemo.exe --otel
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.JSON,
  System.Diagnostics,
  System.Net.HttpClient,
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
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Ollama,
  uMakerAi.Embeddings.Core,
  uMakerAi.Embeddings.Ollama,
  uMakerAi.RAG.MetaData,
  uMakerAi.RAG.Vectors.Index,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vector.Driver.Postgres,
  uMakerAi.Telemetry;

const
  ENTIDAD = 'PELICULAS_OLLAMA';
  TOP_K = 4;

  // The system prompt is half the work in a RAG. These three rules are
  // las que evitan el fallo mas comun: que el modelo complete con lo que "sabe"
  // cuando el contexto no alcanza.
  SYSTEM_RAG = 'Eres el asistente de un catalogo de peliculas.' + sLineBreak +
    'Answer ONLY with the information from the CATALOG below.' + sLineBreak +
    'If the catalog does not contain the answer, say exactly: "I do not have that information in the catalog".' + sLineBreak +
    'Do not invent titles, directors or years. Cite the title of the movies you use.' + sLineBreak +
    'Answer in English, in at most 4 lines.' + sLineBreak + sLineBreak + 'CATALOG:' + sLineBreak;

var
  Conn: TFDConnection;
  Driver: TAiRAGVectorPostgresDriver;
  Rag: TAiRAGVector;
  Embedder: TAiOllamaEmbeddings;
  Chat: TAiOllamaChat;
  Telemetry: TAiTelemetry;
  ModeloEmb, ModeloChat, TablaVec, OllamaUrl: string;
  DimEmb: Integer;

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
  V: Integer;
  P: string;
begin
  Result := GetEnvironmentVariable('PGLIBPQ');
  if (Result <> '') and FileExists(Result) then
    Exit;
  for V := 18 downto 12 do
  begin
    P := Format('C:\Program Files\PostgreSQL\%d\bin\libpq.dll', [V]);
    if FileExists(P) then
      Exit(P);
  end;
  Result := '';
end;

procedure Separador(const ATexto: string);
begin
  Writeln('');
  Writeln('----------------------------------------------------------------------');
  Writeln(' ' + ATexto);
  Writeln('----------------------------------------------------------------------');
end;

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------
procedure Preparar;
var
  Link: TFDPhysPgDriverLink;
  LibPq: string;
  Http: THTTPClient;
  Resp: IHTTPResponse;
  Total: Integer;
begin
  Writeln('== Preparacion ==');

  // --- PostgreSQL ---
  Link := TFDPhysPgDriverLink.Create(nil);
  LibPq := FindLibPq;
  if LibPq <> '' then
    Link.VendorLib := LibPq;

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
    raise Exception.Create('Missing environment variable PGPASSWORD');
  Conn.Connected := True;
  Writeln('   postgres: ' + Conn.Params.Values['Database'] + '@' + Conn.Params.Values['Server']);

  // --- Ollama ---
  Http := THTTPClient.Create;
  try
    Http.ConnectionTimeout := 5000;
    Http.ResponseTimeout := 5000;
    try
      Resp := Http.Get(OllamaUrl.TrimRight(['/']) + '/api/tags');
    except
      on E: Exception do
        raise Exception.Create('Ollama does not respond at ' + OllamaUrl + '. Start it with "ollama serve".');
    end;
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('Ollama returned HTTP %d', [Resp.StatusCode]);
    if not Resp.ContentAsString(TEncoding.UTF8).Contains(ModeloChat) then
      raise Exception.CreateFmt('El modelo de chat "%s" no esta en Ollama. Descargalo con: ollama pull %s',
        [ModeloChat, ModeloChat]);
  finally
    Http.Free;
  end;
  Writeln('   ollama: embeddings=' + ModeloEmb + ' (dim ' + IntToStr(DimEmb) + ')  chat=' + ModeloChat);

  // --- Vector index (created and populated by demo 077) ---
  if Conn.ExecSQLScalar('select count(*) from information_schema.tables where table_name = ' + QuotedStr(TablaVec)) = 0
  then
    raise Exception.Create('The table ' + TablaVec + ' does not exist. Run demo 077-RagPostgresConsole first' +
      ' with --model ' + ModeloEmb + ' --dim ' + IntToStr(DimEmb));

  Total := Conn.ExecSQLScalar(Format('select count(*) from %s where entidad = %s', [TablaVec, QuotedStr(ENTIDAD)]));
  if Total = 0 then
    raise Exception.Create('The table ' + TablaVec + ' is empty. Run demo 077 first to index.');
  Writeln(Format('   index: %s with %d vectors', [TablaVec, Total]));

  // --- MakerAI components ---
  Embedder := TAiOllamaEmbeddings.Create(nil);
  Embedder.Url := OllamaUrl;
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
  // Hybrid: embeddings provide meaning and BM25 rescues exact terms
  // (proper names, titles), fused with RRF.
  Rag.SearchOptions.UseEmbeddings := True;
  Rag.SearchOptions.UseBM25 := True;
  Rag.SearchOptions.UseRRF := True;

  Chat := TAiOllamaChat.Create(nil);
  // TRAP of reasoning models in Ollama: num_predict (which the driver
  // takes from Max_tokens) limits ALL generated tokens, and thinking counts.
  // With qwen3.5:4b and the default of 3000, reasoning ate the whole budget
  // and the response arrived EMPTY: no error, only empty content.
  // For a RAG the chain of thought is not interesting, only the answer, so
  // it is disabled with think=false (via ModelExtraBodyParams, which the driver
  // mixes into the request root). With --think it stays active, but then a
  // much larger token budget is needed.
  Chat.Url := OllamaUrl;
  Chat.Model := ModeloChat;
  Chat.Asynchronous := False; // consola: respuesta completa de una vez
  if HasFlag('--think') then
    Chat.Max_tokens := 16000
  else
  begin
    Chat.Max_tokens := 2000;
    Chat.ModelConfig.ModelExtraBodyParams := '{"think": false}';
  end;
end;

// ---------------------------------------------------------------------------
// Retrieval
// ---------------------------------------------------------------------------
function RecuperarContexto(const APregunta: string; out ACuantos: Integer): string;
var
  Target: TAiEmbeddingNode;
  Res: TAiRAGVector;
begin
  Result := '';
  ACuantos := 0;
  Target := Rag.CreateEmbeddingNode(APregunta);
  try
    Res := Driver.Search(Target, ENTIDAD, TOP_K, 0.0, nil, Rag.SearchOptions);
    try
      if Assigned(Res) then
      begin
        ACuantos := Res.Count;
        // Builds the text block with the fragments and their metadata. Scores
        // are omitted: they do not help the model and waste tokens.
        Result := Rag.VectorToContextText(Res, True, False);
      end;
    finally
      Res.Free;
    end;
  finally
    Target.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Ask the model, with and without context
// ---------------------------------------------------------------------------
procedure Preguntar(const APregunta: string);
var
  Contexto, Respuesta: string;
  Cuantos: Integer;
  SW: TStopwatch;
begin
  Separador('QUESTION: ' + APregunta);

  // ---------- 1. Without RAG ----------
  Writeln('');
  Writeln('  [WITHOUT CONTEXT]  the model answers only with what it brings from the factory');
  Chat.Messages.Clear;
  Chat.SystemPrompt.Text := 'Respond in English, in at most 4 lines.';
  SW := TStopwatch.StartNew;
  try
    Respuesta := Chat.AddMessageAndRun(APregunta, 'user', []);
  except
    on E: Exception do
      Respuesta := '(error: ' + E.Message + ')';
  end;
  Writeln('  ' + Respuesta.Trim.Replace(sLineBreak, sLineBreak + '  '));
  Writeln(Format('  (%d ms)', [SW.ElapsedMilliseconds]));

  // ---------- 2. With RAG ----------
  Writeln('');
  Contexto := RecuperarContexto(APregunta, Cuantos);
  Writeln(Format('  [WITH CONTEXT]  %d records retrieved from PostgreSQL and injected into the system prompt', [Cuantos]));
  Chat.Messages.Clear;
  Chat.SystemPrompt.Text := SYSTEM_RAG + Contexto;
  SW := TStopwatch.StartNew;
  try
    Respuesta := Chat.AddMessageAndRun(APregunta, 'user', []);
  except
    on E: Exception do
      Respuesta := '(error: ' + E.Message + ')';
  end;
  Writeln('  ' + Respuesta.Trim.Replace(sLineBreak, sLineBreak + '  '));
  Writeln(Format('  (%d ms)', [SW.ElapsedMilliseconds]));
end;

// ---------------------------------------------------------------------------

var
  Libre: string;

begin
  Telemetry := nil;
  Conn := nil;
  Driver := nil;
  Rag := nil;
  Embedder := nil;
  Chat := nil;
  try
    try
      ModeloChat := ArgValue('--chat', 'qwen3.5:4b');
      // By default nomic-embed-text: in the tests of demo 077 it behaved
      // better than mxbai-embed-large on this Spanish corpus.
      ModeloEmb := ArgValue('--embed', 'nomic-embed-text');
      DimEmb := StrToIntDef(ArgValue('--dim', ''), 0);
      if DimEmb = 0 then
      begin
        if ModeloEmb.StartsWith('nomic-embed-text') then
          DimEmb := 768
        else if ModeloEmb.StartsWith('all-minilm') then
          DimEmb := 384
        else
          DimEmb := 1024;
      end;
      TablaVec := 'pelicula_vector_ollama_' + IntToStr(DimEmb);
      OllamaUrl := Env('OLLAMA_URL', 'http://localhost:11434/');

      if HasFlag('--otel') then
      begin
        Telemetry := TAiTelemetry.Create(nil);
        Telemetry.ServiceName := 'RagChatOllamaDemo';
        Telemetry.Enabled := True;
        Writeln('[otel] Exporting traces to ' + Telemetry.Endpoint);
      end;

      if HasFlag('--debug') then
      begin
        MakerAiDebugLogEnabled := True;
        MakerAiDebugLogPath := 'demo078.log';
        Writeln('[debug] log in demo078.log');
      end;
      Writeln('=== DEMO 078: complete 100% local RAG (pgvector + Ollama) ===');
      Writeln('');
      Preparar;

      Libre := ArgValue('--ask', '');
      if Libre <> '' then
        Preguntar(Libre)
      else
      begin
        // Questions about a PRIVATE catalog: the model cannot know them.
        // Without context it will invent; with context it will answer with real data.
        Preguntar('Which horror movies did Carla Mendez direct?');
        Preguntar('What is Orbit Zero about and in what year was it released?');
        Preguntar('Recommend an animated movie and explain why.');
        // This one is NOT in the catalog: it serves to check that the model
        // admits it does not know instead of inventing.
        Preguntar('Who directed The Godfather?');
      end;

      Writeln('');
      Writeln('OK: end-to-end RAG with local models.');
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
    Chat.Free;
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
