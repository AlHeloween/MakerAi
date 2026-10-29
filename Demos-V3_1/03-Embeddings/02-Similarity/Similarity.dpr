program Similarity;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 03-Embeddings / 02-Similarity
// =============================================================================
// Deep exploration of semantic similarity between texts.
// Builds a mini similarity matrix and finds the most similar
// to a query using linear search.
//
// Conceptos que cubre:
//   - Cosine similarity, Euclidean distance, dot product
//   - NxN matrix of similarities between a text corpus
//   - Search for the top-K most similar to a query
//   - Use case: recommendation, deduplication, basic clustering
// =============================================================================

uses
  System.SysUtils,
  System.Math,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.Embeddings.Gemini,
  uMakerAi.Embeddings.Ollama;

const
  DRIVER  = 'OpenAI';
  MODEL   = 'text-embedding-3-small';
  API_KEY = '@OPENAI_API_KEY';

// Corpus de ejemplo — frases sobre tecnología y otros temas
const
  CORPUS: array[0..7] of String = (
    'Machine learning models learn patterns from data',
    'Deep neural networks have many hidden layers',
    'Python is the most popular language for AI development',
    'The Eiffel Tower is located in Paris, France',
    'Photosynthesis converts sunlight into chemical energy',
    'Gradient descent optimizes neural network weights',
    'The Amazon rainforest produces 20% of the world oxygen',
    'Transformers use attention mechanisms for NLP tasks'
  );

// =============================================================================
//  Imprime los resultados de similitud ordenados
// =============================================================================
procedure PrintTopK(const Query: String; const Corpus: array of String;
  const Embeddings: array of TAiEmbeddingData; const QEmb: TAiEmbeddingData; K: Integer);
var
  Scores: array[0..7] of Double;
  I, J  : Integer;
  Temp  : Double;
  TempI : Integer;
  Idx   : array[0..7] of Integer;
begin
  for I := 0 to High(Corpus) do
  begin
    Scores[I] := TAiEmbeddingsCore.CosineSimilarity(QEmb, Embeddings[I]);
    Idx[I]    := I;
  end;

  // Bubble sort descendente
  for I := 0 to High(Corpus) - 1 do
    for J := 0 to High(Corpus) - I - 1 do
      if Scores[Idx[J]] < Scores[Idx[J+1]] then
      begin
        TempI := Idx[J]; Idx[J] := Idx[J+1]; Idx[J+1] := TempI;
      end;

  Writeln(Format('  Consulta: "%s"', [Query]));
  Writeln(Format('  Top %d most similar:', [K]));
  for I := 0 to Min(K - 1, High(Corpus)) do
    Writeln(Format('    [%d] %.4f — %s', [I+1, Scores[Idx[I]], Corpus[Idx[I]]]));
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  Conn          : TAiEmbeddingConnection;
  Embeddings    : array[0..7] of TAiEmbeddingData;
  QueryEmb      : TAiEmbeddingData;
  I, J          : Integer;
begin
  Writeln('=== Similarity ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.ApiKey     := API_KEY;

    // ── Paso 1: generar embeddings del corpus ─────────────────────────────
    Writeln('Generating corpus embeddings (', Length(CORPUS), ' texts)...');
    for I := 0 to High(CORPUS) do
    begin
      Write(Format('  [%d/%d] ', [I+1, Length(CORPUS)]));
      Embeddings[I] := Conn.CreateEmbedding(CORPUS[I], 'user');
      Writeln(Format('dims=%d', [Length(Embeddings[I])]));
    end;
    Writeln;

    // ── Paso 2: búsqueda por similitud ────────────────────────────────────
    Writeln('--- Similarity search ---');

    // Query 1: AI/ML topic → should find ML phrases
    QueryEmb := Conn.CreateEmbedding('How do neural networks learn?', 'user');
    PrintTopK('How do neural networks learn?', CORPUS, Embeddings, QueryEmb, 3);

    // Query 2: nature topic → should find biology/nature phrases
    QueryEmb := Conn.CreateEmbedding('Plants and nature', 'user');
    PrintTopK('Plants and nature', CORPUS, Embeddings, QueryEmb, 3);

    // ── Paso 3: matriz de similitud parcial ──────────────────────────────
    Writeln('--- Similarity matrix (first 4 texts) ---');
    Write(Format('%-6s', ['']));
    for I := 0 to 3 do
      Write(Format('  T%-3d', [I+1]));
    Writeln;
    for I := 0 to 3 do
    begin
      Write(Format('T%-4d  ', [I+1]));
      for J := 0 to 3 do
        Write(Format('%5.3f ', [TAiEmbeddingsCore.CosineSimilarity(Embeddings[I], Embeddings[J])]));
      Writeln;
    end;
    Writeln;
    Writeln('  (1.000 = identical, 0.000 = orthogonal, ~0.8+ = very similar)');

  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
