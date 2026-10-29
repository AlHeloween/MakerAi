program BasicEmbeddings;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 03-Embeddings / 01-BasicEmbeddings
// =============================================================================
// Generates text embeddings using an LLM provider and explores the vector
// result. First approach to the concept of vector representation.
//
// Concepts covered:
//   - Create and configure TAiEmbeddingConnection
//   - Call CreateEmbedding() to obtain a vector of floats
//   - Inspect vector dimensions
//   - Compare two texts with CosineSimilarity
//   - Difference between similar and different texts
//
// Supported providers: OpenAI, Gemini, Ollama, Cohere, Mistral
// For OpenAI: model = 'text-embedding-3-small' (1536 dims)
// For Gemini: model = 'models/text-embedding-004'
// For Ollama: model = 'nomic-embed-text' (768 dims), local URL
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

// =============================================================================
//  Prints a vector summary (first 8 values)
// =============================================================================
procedure PrintVectorSummary(const V: TAiEmbeddingData; const Name: String);
var
  I    : Integer;
  Parts: TArray<String>;
begin
  Writeln(Format('  %s: dims=%d', [Name, Length(V)]));
  if Length(V) = 0 then Exit;
  SetLength(Parts, Min(8, Length(V)));
  for I := 0 to High(Parts) do
    Parts[I] := Format('%.4f', [V[I]]);
  Writeln(Format('  First 8 values: [%s...]', [String.Join(', ', Parts)]));
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  Conn : TAiEmbeddingConnection;
  V1, V2, V3: TAiEmbeddingData;
  Sim12, Sim13: Double;
begin
  Writeln('=== BasicEmbeddings ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.ApiKey     := API_KEY;

    // ── Demo 1: generate an embedding from text ─────────────────────────────
    Writeln('--- Demo 1: Generate an embedding ---');
    Writeln('Text: "Artificial intelligence transforms the industry"');
    V1 := Conn.CreateEmbedding(
      'La inteligencia artificial transforma la industria', 'user');
    PrintVectorSummary(V1, 'V1');
    Writeln(Format('  Tokens used: prompt=%d, total=%d',
      [Conn.prompt_tokens, Conn.total_tokens]));
    Writeln;

    // ── Demo 2: similar vs. different texts ────────────────────────────
    Writeln('--- Demo 2: Cosine similarity ---');

    V2 := Conn.CreateEmbedding(
      'La IA y el machine learning cambian la industria', 'user');
    V3 := Conn.CreateEmbedding(
      'Las recetas de cocina mexicana son muy sabrosas', 'user');

    Sim12 := TAiEmbeddingsCore.CosineSimilarity(V1, V2);
    Sim13 := TAiEmbeddingsCore.CosineSimilarity(V1, V3);

    Writeln('  Text A: "Artificial intelligence transforms the industry"');
    Writeln('  Text B: "AI and machine learning change the industry"  (similar)');
    Writeln('  Text C: "Mexican cooking recipes are very tasty"  (different)');
    Writeln;
    Writeln(Format('  Similarity A↔B: %.4f  (expected: high ~0.85+)', [Sim12]));
    Writeln(Format('  Similarity A↔C: %.4f  (expected: low ~0.10-0.30)', [Sim13]));
    Writeln;

    if Sim12 > Sim13 then
      Writeln('  Correct: A is more similar to B than to C.')
    else
      Writeln('  Note: unexpected result — check the model/driver.');

    // ── Demo 3: vector magnitude ───────────────────────────────────────
    Writeln;
    Writeln('--- Demo 3: Vector properties ---');
    Writeln(Format('  Dimensions      : %d', [Length(V1)]));
    Writeln(Format('  Magnitude (norm) : %.6f', [TAiEmbeddingsCore.Magnitude(V1)]));
    Writeln(Format('  Euclidean dist.  : %.6f', [TAiEmbeddingsCore.EuclideanDistance(V1, V2)]));
    Writeln;
    Writeln('Note: An embedding with magnitude ~1.0 is normalized (L2 norm).');

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
