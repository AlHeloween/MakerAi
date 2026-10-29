program RAGHybrid;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 04-RAGVector / 04-HybridSearch
// =============================================================================
// Combines vector search (semantic) with lexical search (BM25).
// Hybrid search outperforms each method alone in many cases.
//
// Conceptos que cubre:
//   - TAiSearchOptions: UseEmbeddings, UseBM25, UseRRF
//   - Reciprocal Rank Fusion (RRF): combines vector + BM25 rankings
//   - When vector search fails (exact technical terms)
//   - When BM25 fails (synonyms, paraphrases)
//   - The hybrid combination captures both cases
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vectors.Index;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

// Corpus with technical terms and mixed semantic text
const
  CORPUS: array[0..9] of String = (
    'La funcion SHA256 genera un hash criptografico de 256 bits.',
    'El algoritmo de hashing es fundamental para la seguridad de contraseñas.',
    'HTTPS usa TLS para cifrar las comunicaciones web de forma segura.',
    'SQL injection es un ataque donde codigo malicioso se inyecta en consultas.',
    'Los ataques de ciberseguridad pueden comprometer datos sensibles.',
    'REST API permite comunicacion entre servicios usando HTTP y JSON.',
    'GraphQL es una alternativa a REST para consultar datos de forma flexible.',
    'Docker containeriza aplicaciones para facilitar el despliegue.',
    'Kubernetes orquesta contenedores Docker a escala empresarial.',
    'DevOps combina desarrollo y operaciones para entregas continuas.'
  );

// =============================================================================
//  Compares the 3 search modes for the same query
// =============================================================================
procedure CompararModos(RAG: TAiRAGVector; const Query: String);
var
  Opts   : TAiSearchOptions;
  Results: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Consulta: "', Query, '"');
  Writeln;

  Opts := RAG.SearchOptions;

  // Mode 1: vector only
  Opts.UseEmbeddings := True;
  Opts.UseBM25       := False;
  Opts.UseRRF        := False;
  Results := RAG.SearchText(Query, 3, 0.0, nil, False, True);
  Writeln('VECTOR (semantic):');
  Writeln(Results);

  // Mode 2: BM25 only (lexical)
  Opts.UseEmbeddings := False;
  Opts.UseBM25       := True;
  Opts.UseRRF        := False;
  Results := RAG.SearchText(Query, 3, 0.0, nil, False, True);
  Writeln('BM25 (lexical):');
  Writeln(Results);

  // Mode 3: hybrid RRF
  Opts.UseEmbeddings := True;
  Opts.UseBM25       := True;
  Opts.UseRRF        := True;
  Results := RAG.SearchText(Query, 3, 0.0, nil, False, True);
  Writeln('HYBRID (RRF):');
  Writeln(Results);
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRAGVector;
  I      : Integer;
begin
  Writeln('=== RAGHybrid ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRAGVector.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings        := EmbConn.AiEmbeddings;
    RAG.NameVec           := 'TechDocs';
    RAG.InMemoryIndexType := TAIHNSWIndex;

    Writeln('Indexing corpus...');
    for I := 0 to High(CORPUS) do
      RAG.AddItem(CORPUS[I]);

    RAG.BuildIndex;
    RAG.BuildLexicalIndex;
    Writeln(Format('%d documents indexed.', [RAG.Count]));
    Writeln;

    // Query 1: exact technical term → BM25 wins
    CompararModos(RAG, 'SHA256 hash');

    // Query 2: semantic → vector wins
    CompararModos(RAG, 'proteccion de comunicaciones en internet');

    // Query 3: mix → hybrid wins
    CompararModos(RAG, 'seguridad en bases de datos SQL');

  finally
    RAG.Free;
    EmbConn.Free;
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
  Writeln('Presiona Enter para salir...');
  Readln;
end.
