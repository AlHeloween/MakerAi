program RAGVQL;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 04-RAGVector / 05-VQL
// =============================================================================
// VQL (Vector Query Language) — advanced queries on the vector store
// using SQL-like syntax adapted to vector search.
//
// Concepts covered:
//   - TAiRAGVector.ExecuteVQL() for VQL queries
//   - SELECT, SEARCH NEAR, WHERE, ORDER BY, LIMIT
//   - Metadata filtering with operators
//   - Combination of semantic search + structured filters
//
// Basic VQL syntax:
//   SEARCH "<query>" NEAR <field>
//   WHERE metadata.<field> = <value>
//   ORDER BY score DESC
//   LIMIT N
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vectors.Index,
  uMakerAi.RAG.MetaData;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

// Corpus with metadata
type
  TDocMeta = record
    Text    : String;
    Categoria: String;
    Año     : Integer;
    Autor   : String;
  end;

const
  CORPUS: array[0..7] of TDocMeta = (
    (Text: 'Machine learning is a subfield of artificial intelligence.'; Categoria: 'IA'; Año: 2023; Autor: 'Lopez'),
    (Text: 'Deep neural networks learn hierarchical representations.'; Categoria: 'IA'; Año: 2023; Autor: 'Garcia'),
    (Text: 'Python is the most popular language for data science.'; Categoria: 'Programming'; Año: 2022; Autor: 'Martinez'),
    (Text: 'Delphi allows creating native cross-platform applications.'; Categoria: 'Programming'; Año: 2024; Autor: 'Lopez'),
    (Text: 'Transformers revolutionized natural language processing.'; Categoria: 'IA'; Año: 2024; Autor: 'Hernandez'),
    (Text: 'Rust guarantees memory safety without a garbage collector.'; Categoria: 'Programming'; Año: 2023; Autor: 'Garcia'),
    (Text: 'ChatGPT popularized the use of LLMs in consumer applications.'; Categoria: 'IA'; Año: 2022; Autor: 'Martinez'),
    (Text: 'TypeScript adds static types to the JavaScript ecosystem.'; Categoria: 'Programming'; Año: 2022; Autor: 'Hernandez')
  );

// =============================================================================
//  Indexes the corpus with metadata
// =============================================================================
procedure IndexarCorpus(RAG: TAiRAGVector);
var
  I   : Integer;
  Meta: TAiEmbeddingMetaData;
begin
  Writeln('Indexing corpus with metadata...');
  for I := 0 to High(CORPUS) do
  begin
    Meta := TAiEmbeddingMetaData.Create;
    try
      Meta['categoria'] := CORPUS[I].Categoria;
      Meta['año']       := CORPUS[I].Año;
      Meta['autor']     := CORPUS[I].Autor;
      RAG.AddItem(CORPUS[I].Text, Meta);
    finally
      Meta.Free;
    end;
    Write('.');
  end;
  Writeln;
  RAG.BuildIndex;
  RAG.BuildLexicalIndex;
  Writeln(Format('%d documents indexed.', [RAG.Count]));
  Writeln;
end;

// =============================================================================
//  Executes a VQL query and shows the result
// =============================================================================
procedure EjecutarVQL(RAG: TAiRAGVector; const Descripcion, Query: String);
var
  Resultado: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Query: ', Descripcion);
  Writeln('VQL:');
  Writeln('  ', Query);
  Writeln;
  try
    Resultado := RAG.ExecuteVQL(Query);
    Writeln('Result:');
    Writeln(Resultado);
  except
    on E: Exception do
      Writeln('Error in VQL: ', E.Message);
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRAGVector;
begin
  Writeln('=== RAGVQL ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRAGVector.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings        := EmbConn.AiEmbeddings;
    RAG.NameVec           := 'TechPapers';
    RAG.InMemoryIndexType := TAIHNSWIndex;

    IndexarCorpus(RAG);

    // Progressive VQL queries
    EjecutarVQL(RAG,
      'Simple semantic search',
      'SEARCH "artificial intelligence and neural networks" LIMIT 3');

    EjecutarVQL(RAG,
      'Search filtered by category',
      'SEARCH "machine learning" WHERE metadata.categoria = "IA" LIMIT 3');

    EjecutarVQL(RAG,
      'Search filtered by year',
      'SEARCH "programming languages" WHERE metadata.año >= 2023 LIMIT 3');

    EjecutarVQL(RAG,
      'Search with multiple filters',
      'SEARCH "machine learning" WHERE metadata.categoria = "IA" AND metadata.año = 2024 LIMIT 3');

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
  Writeln('Press Enter to exit...');
  Readln;
end.
