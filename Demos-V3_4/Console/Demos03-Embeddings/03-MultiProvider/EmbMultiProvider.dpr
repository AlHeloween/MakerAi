program EmbMultiProvider;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 03-Embeddings / 03-MultiProvider
// =============================================================================
// Generates the same embedding with different providers and compares:
// vector dimensions, response time, and similarity between providers.
//
// Concepts covered:
//   - TAiEmbeddingConnection as a universal interface for embeddings
//   - Provider switching at runtime (same as TAiChatConnection)
//   - Dimension differences between models (512, 768, 1536, 3072...)
//   - Embeddings from different models are NOT directly comparable
//   - Use case: choose provider based on cost/speed/quality
//
// Default providers and models:
//   OpenAI  → text-embedding-3-small  (1536 dims)
//   Gemini  → models/text-embedding-004 (768 dims)
//   Ollama  → nomic-embed-text  (768 dims, local)
// =============================================================================

uses
  System.SysUtils,
  System.Diagnostics,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.Embeddings.Gemini,
  uMakerAi.Embeddings.Ollama;

// Test texts — similar to each other
const
  TEXT_A = 'Artificial intelligence is transforming software development';
  TEXT_B = 'Machine learning and AI are revolutionizing tech';

type
  TProviderConfig = record
    Driver : String;
    Model  : String;
    ApiKey : String;
    Url    : String;
    Enabled: Boolean;
  end;

const
  PROVIDERS: array[0..2] of TProviderConfig = (
    (Driver: 'OpenAI';  Model: 'text-embedding-3-small';      ApiKey: '@OPENAI_API_KEY';  Url: ''; Enabled: True),
    (Driver: 'Gemini';  Model: 'models/text-embedding-004';   ApiKey: '@GEMINI_API_KEY';  Url: ''; Enabled: True),
    (Driver: 'Ollama';  Model: 'nomic-embed-text';            ApiKey: '';                 Url: 'http://localhost:11434/api/'; Enabled: True)
  );

// =============================================================================
//  Tests a provider: generates two embeddings and calculates similarity
// =============================================================================
procedure TestProvider(const Cfg: TProviderConfig);
var
  Conn    : TAiEmbeddingConnection;
  V1, V2  : TAiEmbeddingData;
  SW      : TStopwatch;
  ElapsedA: Int64;
  Sim     : Double;
begin
  if not Cfg.Enabled then
  begin
    Writeln(Format('[%s] — skipped', [Cfg.Driver]));
    Exit;
  end;

  Writeln(StringOfChar('-', 60));
  Writeln(Format('Provider  : %s', [Cfg.Driver]));
  Writeln(Format('Model     : %s', [Cfg.Model]));

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := Cfg.Driver;
    Conn.Model      := Cfg.Model;
    Conn.ApiKey     := Cfg.ApiKey;
    if Cfg.Url <> '' then
      Conn.Url := Cfg.Url;

    try
      // Embedding A
      SW := TStopwatch.StartNew;
      V1 := Conn.CreateEmbedding(TEXT_A, 'user');
      ElapsedA := SW.ElapsedMilliseconds;

      // Embedding B
      V2 := Conn.CreateEmbedding(TEXT_B, 'user');

      Sim := TAiEmbeddingsCore.CosineSimilarity(V1, V2);

      Writeln(Format('Dimensions: %d', [Length(V1)]));
      Writeln(Format('Time (A)   : %d ms', [ElapsedA]));
      Writeln(Format('Similarity : %.4f  (A↔B, same semantics)', [Sim]));
      Writeln(Format('Tokens     : %d', [Conn.total_tokens]));
    except
      on E: Exception do
        Writeln(Format('ERROR     : %s', [E.Message]));
    end;
  finally
    Conn.Free;
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  I: Integer;
begin
  Writeln('=== EmbMultiProvider ===');
  Writeln('Same two texts, different embedding providers.');
  Writeln;
  Writeln('Text A: "', TEXT_A, '"');
  Writeln('Text B: "', TEXT_B, '"');
  Writeln;
  Writeln('Note: dimensions and similarities VARY by model.');
  Writeln('      DO NOT compare vectors from different models with each other.');
  Writeln;

  for I := Low(PROVIDERS) to High(PROVIDERS) do
    TestProvider(PROVIDERS[I]);

  Writeln(StringOfChar('=', 60));
  Writeln('Summary:');
  Writeln('  - Each model has its own dimensions and scale.');
  Writeln('  - For production: choose ONE model and use it consistently.');
  Writeln('  - OpenAI: high quality, paid. Ollama: local, free.');
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
