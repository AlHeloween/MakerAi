program RAGPostgres;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 04-RAGVector / 03-Postgres
// =============================================================================
// Persistent vector store with PostgreSQL pgvector extension.
// Ideal for production with large document volumes.
//
// Concepts covered:
//   - TAiRAGVectorPostgresDriver as vector driver in PostgreSQL
//   - TFDConnection: FireDAC connection to PostgreSQL
//   - Driver.CreateSchema(tableName, dim): creates table with vector column
//   - Save and retrieve embeddings from pgvector
//   - Vector search and hybrid search with pgvector
//
// Prerequisites:
//   1. PostgreSQL installed and running
//   2. pgvector extension installed: CREATE EXTENSION IF NOT EXISTS vector;
//   3. Adjust the connection constants below
//   4. MakerAI.RAG.Drivers package installed
// =============================================================================

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Phys,
  FireDAC.Comp.Client,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vectors.Index,
  uMakerAi.RAG.MetaData,
  uMakerAi.RAG.Vector.Driver.Postgres;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

  // ── Adjust according to your PostgreSQL installation ───────────────────────────
  PG_SERVER   = 'localhost';
  PG_PORT     = '5432';
  PG_DATABASE = 'makerai_demo';
  PG_USER     = 'postgres';
  PG_PASSWORD = 'postgres';

  TABLE_NAME  = 'PGVectorDemo';
  EMB_DIM     = 1536; // dimension of text-embedding-3-small

const
  DOCS: array[0..4] of String = (
    'PostgreSQL is an advanced relational database management system.',
    'pgvector adds vector support and similarity search to PostgreSQL.',
    'IVFFlat and HNSW indexes accelerate vector search in large datasets.',
    'Vector embeddings enable semantic search over text in PostgreSQL.',
    'The PostgreSQL vector extension supports cosine and Euclidean distance.'
  );

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn : TAiEmbeddingConnection;
  RAG     : TAiRAGVector;
  Driver  : TAiRAGVectorPostgresDriver;
  Conn    : TFDConnection;
  I       : Integer;
  Results : String;
begin
  Writeln('=== RAGPostgres ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln('PostgreSQL: ', PG_SERVER, ':', PG_PORT, '/', PG_DATABASE);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  Conn    := TFDConnection.Create(nil);
  Driver  := TAiRAGVectorPostgresDriver.Create(nil);
  RAG     := TAiRAGVector.Create(nil);
  try
    // ── Configure embeddings ─────────────────────────────────────────────
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    // ── Configure FireDAC + PostgreSQL ───────────────────────────────────
    Conn.DriverName                  := 'PG';
    Conn.Params.Values['Server']     := PG_SERVER;
    Conn.Params.Values['Port']       := PG_PORT;
    Conn.Params.Values['Database']   := PG_DATABASE;
    Conn.Params.Values['User_Name']  := PG_USER;
    Conn.Params.Values['Password']   := PG_PASSWORD;
    Conn.LoginPrompt                 := False;

    try
      Conn.Open;
    except
      on E: Exception do
      begin
        Writeln('ERROR: Could not connect to PostgreSQL.');
        Writeln('  ', E.Message);
        Writeln('Verify that PostgreSQL is running and pgvector is installed:');
        Writeln('  CREATE EXTENSION IF NOT EXISTS vector;');
        Exit;
      end;
    end;
    Writeln('Successfully connected to PostgreSQL.');
    Writeln;

    // ── Configure Postgres driver ────────────────────────────────────────
    Driver.Connection := Conn;
    Driver.TableName  := TABLE_NAME;
    Driver.Language   := alSpanish;

    // ── Configure RAG with Postgres driver ────────────────────────────────
    RAG.Embeddings := EmbConn.AiEmbeddings;
    RAG.NameVec    := TABLE_NAME;
    RAG.Driver     := Driver;
    RAG.Entidad    := TABLE_NAME;

    // Create schema with correct dimension for the model
    Writeln('Creating schema in PostgreSQL...');
    Driver.CreateSchema(TABLE_NAME, EMB_DIM);
    Writeln('Schema ready.');
    Writeln;

    // Index documents
    Writeln('Indexing ', Length(DOCS), ' documents...');
    for I := 0 to High(DOCS) do
    begin
      RAG.AddItem(DOCS[I]);
      Writeln(Format('  [%d] saved in pgvector', [I + 1]));
    end;
    Writeln;

    // Search
    Writeln('--- Semantic search ---');
    Results := RAG.SearchText('vector database extensions', 3, 0.4);
    Writeln('Query: "vector database extensions"');
    Writeln(Results);

    Results := RAG.SearchText('vector search performance', 3, 0.4);
    Writeln('Query: "vector search performance"');
    Writeln(Results);

  finally
    RAG.Free;
    Driver.Free;
    Conn.Free;
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
