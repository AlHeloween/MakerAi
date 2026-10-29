program RAGSQLite;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 04-RAGVector / 02-SQLite
// =============================================================================
// Persistent vector store using SQLite as backend via FireDAC.
// Embeddings are saved to disk and can be reloaded between sessions.
//
// Concepts covered:
//   - TAiRAGVectorSQLiteDriver as persistence driver (FireDAC + SQLite)
//   - TFDConnection: FireDAC connection to SQLite
//   - Driver.CreateSchema(tableName): creates vector tables + FTS5
//   - Driver.Connection / TableName / Language
//   - Difference between first run (create schema + index) and later runs
//   - Search with TAiSearchOptions (vector, BM25, hybrid RRF)
//
// Requirements:
//   - MakerAI.RAG.Drivers package installed
//   - Unit: uMakerAi.RAG.Vector.Driver.SQLite
//   - FireDAC.Phys.SQLite (FireDAC SQLite driver)
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  Data.DB,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
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
  uMakerAi.RAG.Vector.Driver.SQLite;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

  DB_PATH    = 'rag_demo.db';
  TABLE_NAME = 'DelphiDocs';

const
  DOCS: array[0..5] of String = (
    'Delphi es un lenguaje de programacion orientado a objetos basado en Pascal.',
    'FireDAC es el framework de acceso a datos de Embarcadero para Delphi.',
    'FMX (FireMonkey) permite crear interfaces graficas multiplataforma con Delphi.',
    'RTL (Runtime Library) contiene las clases y funciones basicas de Delphi.',
    'VCL (Visual Component Library) es el framework GUI original de Delphi para Windows.',
    'El IDE de Delphi incluye depurador integrado, editor de codigo y disenador visual.'
  );

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn : TAiEmbeddingConnection;
  RAG     : TAiRAGVector;
  Driver  : TAiRAGVectorSQLiteDriver;
  Conn    : TFDConnection;
  I       : Integer;
  IsNew   : Boolean;
  Results : String;
begin
  Writeln('=== RAGSQLite ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln('Database: ', DB_PATH);
  Writeln;

  IsNew := not TFile.Exists(DB_PATH);

  EmbConn := TAiEmbeddingConnection.Create(nil);
  Conn    := TFDConnection.Create(nil);
  Driver  := TAiRAGVectorSQLiteDriver.Create(nil);
  RAG     := TAiRAGVector.Create(nil);
  try
    // ── Configure embeddings ─────────────────────────────────────────────
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    // ── Configure FireDAC + SQLite ───────────────────────────────────────
    Conn.DriverName                := 'SQLite';
    Conn.Params.Values['Database'] := DB_PATH;
    Conn.LoginPrompt               := False;
    Conn.Open;
    Writeln('SQLite connection opened.');

    // ── Configure SQLite driver ──────────────────────────────────────────
    Driver.Connection := Conn;
    Driver.TableName  := TABLE_NAME;
    Driver.Language   := alSpanish;

    // ── Configure RAG with SQLite driver ──────────────────────────────────
    RAG.Embeddings := EmbConn.AiEmbeddings;
    RAG.NameVec    := TABLE_NAME;
    RAG.Driver     := Driver;
    RAG.Entidad    := TABLE_NAME;

    if IsNew then
    begin
      // First run: create schema and index documents
      Writeln('New database. Creating schema and indexing...');
      Driver.CreateSchema(TABLE_NAME);
      for I := 0 to High(DOCS) do
      begin
        RAG.AddItem(DOCS[I]);
        Writeln(Format('  [%d] indexado', [I + 1]));
      end;
      Writeln(Format('%d documents saved in SQLite.', [RAG.Count]));
    end
    else
    begin
      // Later runs: data is already in SQLite
      Writeln(Format('Existing database with %d documents.', [RAG.Count]));
      Writeln('(No need to re-index.)');
    end;
    Writeln;

    // ── Search ──────────────────────────────────────────────────────────
    Writeln('--- Semantic search ---');
    Results := RAG.SearchText('frameworks GUI para interfaces graficas', 3, 0.4);
    Writeln('Query: "frameworks GUI para interfaces graficas"');
    Writeln(Results);

    Results := RAG.SearchText('acceso a base de datos', 3, 0.4);
    Writeln('Query: "acceso a base de datos"');
    Writeln(Results);

    Writeln('(To restart the demo, delete: ', DB_PATH, ')');

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
