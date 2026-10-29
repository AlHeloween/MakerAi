program EmbeddingsDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 21: Embeddings: The language of vectors
// =============================================================================
// Three demos using TAiEmbeddingConnection + TAiEmbeddingsCore with local Ollama.
//
// Required models (Ollama, no internet, no API key):
//   snowflake-arctic-embed  -- 1024 dims, BERT  (main model)
//   mxbai-embed-large       -- 1024 dims, BERT  (comparison Demo 3)
//   embeddinggemma          --  768 dims, Gemma3 (comparison Demo 3)
//
// To install models: ollama pull snowflake-arctic-embed
//                        ollama pull mxbai-embed-large
//                        ollama pull embeddinggemma
// =============================================================================

uses
  System.SysUtils, System.Classes,
  uMakerAi.Embeddings,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.Ollama;  // auto-registra el driver en initialization

// ---------------------------------------------------------------------------
//  Driver and model constants
// ---------------------------------------------------------------------------
const
  OLLAMA_DRV    = 'Ollama';
  MDL_SNOWFLAKE = 'snowflake-arctic-embed';
  MDL_MXBAI     = 'mxbai-embed-large';
  MDL_GEMMA     = 'embeddinggemma';

// ---------------------------------------------------------------------------
//  Demo 1 corpus: 6 sentences, broad thematic range
// ---------------------------------------------------------------------------
const
  D1_QUERY = 'How to program an application in Delphi';

  D1_CORPUS: array[0..5] of string = (
    'Delphi is an object-oriented programming language',
    'RAD Studio allows compiling applications for Windows and Android',
    'FMX components facilitate the design of cross-platform interfaces',
    'Artificial intelligence transforms the way software is developed',
    'Coffee is the favorite drink of programmers',
    'The average temperature on the surface of Mars is minus 60 degrees'
  );

// ---------------------------------------------------------------------------
//  Demo 2 corpus: 15 sentences, semantic search with FindTopK
// ---------------------------------------------------------------------------
const
  D2_QUERIES: array[0..2] of string = (
    'visual components for user interfaces',
    'local models without needing internet or API key',
    'search and retrieval of semantic information'
  );

  D2_CORPUS: array[0..14] of string = (
    'FireMonkey allows designing cross-platform interfaces in Delphi',  // 0
    'TChatList and TChatInput are FMX components of MakerAI',             // 1
    'Delphi compiles native code for Windows, Android and iOS',          // 2
    'Ollama runs language models locally without connection',    // 3
    'gemma, llama and mistral are open-source models that run on CPU',  // 4
    'Embeddings convert text into numeric vectors',             // 5
    'Cosine similarity measures the angle between two vectors',             // 6
    'RAG combines semantic search with text generation',            // 7
    'TAiChat is the abstract base class of all drivers in MakerAI', // 8
    'AI agents execute tools and make autonomous decisions', // 9
    'The vector database stores embeddings for efficient search', // 10
    'MakerAI supports OpenAI, Claude, Gemini, Ollama and more providers',   // 11
    'The MCP protocol connects tool servers to LLM models', // 12
    'Python is widely used in data science and artificial intelligence', // 13
    'Italian cuisine is famous for its pasta and artisanal pizzas' // 14
  );

// ---------------------------------------------------------------------------
//  Demo 3 corpus: 8 sentences, comparison of three models
// ---------------------------------------------------------------------------
const
  D3_QUERY = 'natural language processing with neural networks';

  D3_CORPUS: array[0..7] of string = (
    'Transformers are the base architecture of modern LLMs',
    'GPT, Claude and Gemini are large-scale language models',
    'Natural language processing analyzes and understands human text',
    'Neural networks learn patterns from large datasets',
    'Delphi compiles highly efficient native code for multiple platforms',
    'FireDAC is the data access framework of RAD Studio',
    'The solar system has eight planets orbiting around the Sun',
    'Gazpacho recipe includes tomato, cucumber, garlic and olive oil'
  );

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// Visual score bar (0.0-1.0 -> 20 chars)
function ScoreBar(Score: Double): string;
var
  Filled: Integer;
begin
  Filled := Round(Score * 20);
  if Filled < 0  then Filled := 0;
  if Filled > 20 then Filled := 20;
  Result := '[' + StringOfChar('#', Filled) + StringOfChar('.', 20 - Filled) + ']';
end;

// Generates embeddings for an array of sentences and returns TAiEmbeddingList
function BuildCorpus(Conn: TAiEmbeddingConnection;
  const Textos: array of string): TAiEmbeddingList;
var
  I: Integer;
begin
  SetLength(Result, Length(Textos));
  for I := 0 to High(Textos) do
    Result[I] := Conn.CreateEmbedding(Textos[I], '');
end;

// ---------------------------------------------------------------------------
//  Demo 1 -- Cosine similarity: close and distant sentences
// ---------------------------------------------------------------------------

procedure Demo1_Similitud;
var
  Conn:    TAiEmbeddingConnection;
  QVec:    TAiEmbeddingData;
  Corpus:  TAiEmbeddingList;
  Results: TAiSimilarityList;
  I:       Integer;
begin
  Separador('Demo 1 -- Cosine similarity: close and distant sentences');
  WriteLn('  Model : ', MDL_SNOWFLAKE, '  [1024 dims]');
  WriteLn('  Query  : "', D1_QUERY, '"');
  WriteLn('');

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := OLLAMA_DRV;
    Conn.Model      := MDL_SNOWFLAKE;

    Write('  Calculating embeddings...');
    Corpus := BuildCorpus(Conn, D1_CORPUS);
    QVec   := Conn.CreateEmbedding(D1_QUERY, '');
    WriteLn(Format(' OK  (%d dims x %d sentences)', [Length(QVec), Length(D1_CORPUS)]));

    // FindTopK with K = total: returns the whole corpus sorted by similarity
    Results := TAiEmbeddingsCore.FindTopK(QVec, Corpus, Length(D1_CORPUS));

    WriteLn('');
    WriteLn('  Similarity ranking  (1.0 = identical, 0.0 = unrelated):');
    WriteLn('  ' + StringOfChar('=', 60));
    for I := 0 to High(Results) do
      WriteLn(Format('  #%d  %.3f  %s  %s',
        [I + 1,
         Results[I].Score,
         ScoreBar(Results[I].Score),
         Copy(D1_CORPUS[Results[I].Index], 1, 42)]));
    WriteLn('  ' + StringOfChar('=', 60));
    WriteLn('');
    WriteLn('-> "Coffee" rises to #2 because "programmers" is close to "programming".');
    WriteLn('   Embeddings capture lexical affinity, not just complete topics.');
    WriteLn('   Mars gets the lowest score: a completely unrelated topic to the query.');

  finally
    Conn.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo 2 -- Semantic search with FindTopK
// ---------------------------------------------------------------------------

procedure Demo2_FindTopK;
var
  Conn:    TAiEmbeddingConnection;
  QVec:    TAiEmbeddingData;
  Corpus:  TAiEmbeddingList;
  Results: TAiSimilarityList;
  Q, K:    Integer;
begin
  Separador('Demo 2 -- Semantic search with FindTopK');
  WriteLn('  Model : ', MDL_SNOWFLAKE, '  [1024 dims]');
  WriteLn('  Corpus : ', Length(D2_CORPUS), ' sentences  |  Top-K = 3');
  WriteLn('');

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := OLLAMA_DRV;
    Conn.Model      := MDL_SNOWFLAKE;

    // Pre-calcular embeddings del corpus (una sola vez, reutilizar en las 3 queries)
    Write('  Indexing corpus...');
    Corpus := BuildCorpus(Conn, D2_CORPUS);
    WriteLn(Format(' OK  (%d embeddings ready)', [Length(Corpus)]));
    WriteLn('');

    for Q := 0 to High(D2_QUERIES) do
    begin
      WriteLn(Format('  [Q%d] "%s"', [Q + 1, D2_QUERIES[Q]]));
      QVec    := Conn.CreateEmbedding(D2_QUERIES[Q], '');
      Results := TAiEmbeddingsCore.FindTopK(QVec, Corpus, 3);

      for K := 0 to High(Results) do
        WriteLn(Format('       #%d  %.3f  %s',
          [K + 1,
           Results[K].Score,
           Copy(D2_CORPUS[Results[K].Index], 1, 55)]));
      WriteLn('');
    end;

    WriteLn('-> RAG pattern: the corpus is indexed ONCE, queried N times.');
    WriteLn('   In production, embeddings live in a vector database');
    WriteLn('   (ch. 22-23). FindTopK is the semantic search engine.');

  finally
    Conn.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo 3 -- The three models head to head
// ---------------------------------------------------------------------------

procedure Demo3_Comparacion;
const
  MODELS: array[0..2] of string = (MDL_SNOWFLAKE, MDL_MXBAI, MDL_GEMMA);
  DIMS:   array[0..2] of string = ('1024d', '1024d', ' 768d');
var
  Conn:    TAiEmbeddingConnection;
  QVec:    TAiEmbeddingData;
  Corpus:  TAiEmbeddingList;
  Results: TAiSimilarityList;
  M, K:    Integer;
begin
  Separador('Demo 3 -- The three models head to head');
  WriteLn('  Query : "', D3_QUERY, '"');
  WriteLn('  Corpus: ', Length(D3_CORPUS), ' sentences  |  Top-3 per model');
  WriteLn('');

  for M := 0 to High(MODELS) do
  begin
    WriteLn(Format('  %-30s  (%s)', [MODELS[M], DIMS[M]]));
    WriteLn('  ' + StringOfChar('-', 55));

    Conn := TAiEmbeddingConnection.Create(nil);
    try
      Conn.DriverName := OLLAMA_DRV;
      Conn.Model      := MODELS[M];

      Corpus  := BuildCorpus(Conn, D3_CORPUS);
      QVec    := Conn.CreateEmbedding(D3_QUERY, '');
      Results := TAiEmbeddingsCore.FindTopK(QVec, Corpus, 3);

      for K := 0 to High(Results) do
        WriteLn(Format('  #%d  %.3f  %s',
          [K + 1,
           Results[K].Score,
           Copy(D3_CORPUS[Results[K].Index], 1, 52)]));
      WriteLn('');
    finally
      Conn.Free;
    end;
  end;

  WriteLn('-> The three models usually agree on semantic ORDER,');
  WriteLn('   but their absolute scores differ (BERT-1024 vs Gemma-768).');
  WriteLn('   To compare across models, always use relative ranking,');
  WriteLn('   never the score value as an absolute threshold.');
end;

// ---------------------------------------------------------------------------
//  Main program
// ---------------------------------------------------------------------------

begin
  WriteLn('=== MakerAI -- Chapter 21: Embeddings: The language of vectors ===');
  WriteLn('');
  WriteLn('  Local models (Ollama, no internet, no API key):');
  WriteLn('    snowflake-arctic-embed   [1024 dims, BERT,   334M params]');
  WriteLn('    mxbai-embed-large        [1024 dims, BERT,   334M params]');
  WriteLn('    embeddinggemma           [ 768 dims, Gemma3, 308M params]');
  WriteLn('');
  WriteLn('  Note: each CreateEmbedding makes an HTTP call to localhost:11434.');
  WriteLn('  In production, corpus embeddings are precomputed and persisted.');

  try
    Demo1_Similitud;
    Demo2_FindTopK;
    Demo3_Comparacion;

    WriteLn('');
    WriteLn(StringOfChar('=', 62));
    WriteLn('  Demos completed.');
    WriteLn('  See cap21-embeddings.md for the complete documentation.');
    WriteLn(StringOfChar('=', 62));

  except
    on E: Exception do
    begin
      WriteLn('');
      WriteLn('[ERROR] ', E.ClassName, ': ', E.Message);
    end;
  end;

  WriteLn('');
  Write('Press Enter to exit...');
  ReadLn;
end.
