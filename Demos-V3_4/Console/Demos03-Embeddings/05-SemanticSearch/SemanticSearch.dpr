program SemanticSearch;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 03-Embeddings / 05-SemanticSearch
// =============================================================================
// Complete semantic search pipeline in 5 phases + FAQ Bot.
// Contrasts syntactic vs semantic search and demonstrates that embeddings
// find meaning, not just exact text.
//
// Concepts covered (sections 21.0 and 21.10 of the book):
//   - Syntactic vs semantic search (practical contrast)
//   - Phase 1: Document preparation
//   - Phase 2-3: Vectorization and indexing with TAiEmbeddingConnection
//   - Phase 4: User query vectorization
//   - Phase 5: Search, ranking and Top-K with FindTopK
//   - FAQ Bot: answer questions in natural language
//   - Warning: embedding model is immutable in the index
//
// Provider: local Ollama (no cost, no API key)
//   Main model: mxbai-embed-large:latest
//   Alternatives:     snowflake-arctic-embed:latest
//                     embeddinggemma:latest
// =============================================================================

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.Ollama;

const
  DRIVER = 'Ollama';
  MODEL  = 'mxbai-embed-large:latest';
  URL    = 'http://localhost:11434/api/';

// =============================================================================
//  Tipos locales
// =============================================================================
type
  TDocumento = record
    Id: Integer;
    Titulo: String;
    Contenido: String;
  end;

  TDocVectorizado = record
    Doc: TDocumento;
    Vector: TAiEmbeddingData;
  end;

// =============================================================================
//  Document base (book sec. 21.10.2)
// =============================================================================
const
  DOCS: array[0..6] of TDocumento = (
    (Id:1; Titulo:'The cardiovascular system';
     Contenido:'The heart pumps blood to all organs of the human body'),
    (Id:2; Titulo:'The water cycle';
     Contenido:'Water evaporates from the oceans, forms clouds, and falls as rain'),
    (Id:3; Titulo:'Medical professions';
     Contenido:'Doctors, nurses, and specialists work in hospitals'),
    (Id:4; Titulo:'Urban transport';
     Contenido:'Cars, buses, and trains transport people in the city'),
    (Id:5; Titulo:'Programming in Delphi';
     Contenido:'Delphi is an object-oriented programming language for Windows'),
    (Id:6; Titulo:'Artificial Intelligence';
     Contenido:'Large language models process text using neural networks'),
    (Id:7; Titulo:'The carbon cycle';
     Contenido:'Plants absorb CO2, animals release it when breathing')
  );

// =============================================================================
//  Example FAQ (book sec. 21.10.8)
// =============================================================================
type
  TFAQItem = record
    Pregunta: String;
    Respuesta: String;
  end;

const
  FAQ: array[0..4] of TFAQItem = (
    (Pregunta:'How do I change my password?';
     Respuesta:'Go to Settings > Security > Change password'),
    (Pregunta:'How do I download my data?';
     Respuesta:'In Settings > Privacy > Export my data'),
    (Pregunta:'What are the business hours?';
     Respuesta:'Monday to Friday 9 AM to 6 PM, Saturdays 10 AM to 3 PM'),
    (Pregunta:'How do I contact support?';
     Respuesta:'Email: support@company.com | Tel: +52-55-1234-5678'),
    (Pregunta:'How do I cancel my subscription?';
     Respuesta:'In Settings > Subscription > Cancel plan')
  );

// -----------------------------------------------------------------------------
//  Helper
// -----------------------------------------------------------------------------
procedure Titulo(const S: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 62));
  Writeln(S);
  Writeln(StringOfChar('=', 62));
end;

// =============================================================================
//  Section 0 — Syntactic vs semantic search (book sec. 21.0)
// =============================================================================
procedure MostrarContraste;
begin
  Titulo('Sec. 21.0 — Syntactic vs semantic search');

  Writeln('  SYNTACTIC search looks for exact text:');
  Writeln;

  var Termino := 'doctor';
  var Sinonimos: TArray<String> := ['physician', 'cardiologist', 'nurse', 'clinician', 'medical'];
  for var S in Sinonimos do
    Writeln(Format('    "%s" = "%s" -> %s', [Termino, S,
      IfThen(SameText(S, Termino), 'ENCONTRADO', 'no encontrado')]));

  Writeln;
  Writeln('  SEMANTIC search would find all of the above');
  Writeln('  because it understands they are synonyms. We demonstrate this below.');
end;

// =============================================================================
//  Phases 1-3 — Preparation, vectorization and indexing (book sec. 21.10.2-3)
// =============================================================================
function CrearIndice(Conn: TAiEmbeddingConnection): TArray<TDocVectorizado>;
var
  I: Integer;
begin
  Titulo('Sec. 21.10.2-21.10.3 — Phases 1-3: Vectorization and indexing');

  Writeln(Format('  Indexing %d documents with %s/%s ...', [Length(DOCS), DRIVER, MODEL]));
  Writeln(Format('  Model used: %s  <- DO NOT change when querying', [MODEL]));
  Writeln;

  SetLength(Result, Length(DOCS));
  for I := 0 to High(DOCS) do
  begin
    Result[I].Doc := DOCS[I];
    var Texto := DOCS[I].Titulo + '. ' + DOCS[I].Contenido;
    Result[I].Vector := Conn.CreateEmbedding(Texto, 'user');
    Writeln(Format('  [%d/%d] (%d dims) %s',
      [I+1, Length(DOCS), Length(Result[I].Vector), DOCS[I].Titulo]));
  end;
end;

// =============================================================================
//  Phases 4-5 — Query and ranking (book sec. 21.10.4-5)
// =============================================================================
procedure BuscarEn(Conn: TAiEmbeddingConnection;
  const Indice: TArray<TDocVectorizado>;
  const Consulta: String; TopK: Integer = 3);
var
  I: Integer;
  Candidatos: TAiEmbeddingList;
begin
  Writeln(Format('  Query: "%s"', [Consulta]));

  var QVec := Conn.CreateEmbedding(Consulta, 'user');

  SetLength(Candidatos, Length(Indice));
  for I := 0 to High(Indice) do
    Candidatos[I] := Indice[I].Vector;

  var Res := TAiEmbeddingsCore.FindTopK(QVec, Candidatos, TopK);

  for I := 0 to High(Res) do
    Writeln(Format('    [%d] %.4f — %s', [I+1, Res[I].Score, Indice[Res[I].Index].Doc.Titulo]));
  Writeln;
end;

procedure SeccionBusqueda(Conn: TAiEmbeddingConnection;
  const Indice: TArray<TDocVectorizado>);
begin
  Titulo('Sec. 21.10.4-21.10.5 — Phases 4-5: Query and ranking');
  Writeln('  Note: queries use synonyms, not exact text from the documents');
  Writeln;

  BuscarEn(Conn, Indice, 'doctor and hospital', 3);
  BuscarEn(Conn, Indice, 'the heart and blood', 3);
  BuscarEn(Conn, Indice, 'rain and ocean', 3);
  BuscarEn(Conn, Indice, 'software and source code', 3);
  BuscarEn(Conn, Indice, 'CO2 and photosynthesis', 3);
end;

// =============================================================================
//  FAQ Bot (book sec. 21.10.8)
// =============================================================================
procedure SeccionFAQBot(Conn: TAiEmbeddingConnection);
var
  Vectores: TAiEmbeddingList;
  I: Integer;
begin
  Titulo('Sec. 21.10.8 — FAQ Bot: answers without exact text match');

  Writeln('  Indexing FAQ questions...');
  SetLength(Vectores, Length(FAQ));
  for I := 0 to High(FAQ) do
  begin
    Vectores[I] := Conn.CreateEmbedding(FAQ[I].Pregunta, 'user');
    Writeln(Format('  [%d] %s', [I+1, FAQ[I].Pregunta]));
  end;

  Writeln;
  Writeln('  Answering user questions (phrased differently):');
  Writeln;

  var Preguntas: TArray<String> := [
    'I forgot my password, what do I do?',
    'I want to export my personal information',
    'what time does the office open?',
    'I need to talk to someone for help',
    'I no longer want the service'
  ];

  for var Pregunta in Preguntas do
  begin
    var QVec := Conn.CreateEmbedding(Pregunta, 'user');
    var Res  := TAiEmbeddingsCore.FindTopK(QVec, Vectores, 1);

    if Length(Res) > 0 then
    begin
      var Idx  := Res[0].Index;
      var Conf := Res[0].Score;
      Writeln(Format('  User     : "%s"', [Pregunta]));
      Writeln(Format('  FAQ match: "%s"  (confidence: %.0f%%)', [FAQ[Idx].Pregunta, Conf*100]));
      Writeln(Format('  Answer   : %s', [FAQ[Idx].Respuesta]));
      Writeln;
    end;
  end;
end;

// =============================================================================
//  MAIN PROGRAM
// =============================================================================
procedure RunDemo;
var
  Conn: TAiEmbeddingConnection;
begin
  Writeln('=== SemanticSearch — Complete semantic search pipeline ===');
  Writeln('Driver: ', DRIVER, ' | Model: ', MODEL);

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Url        := URL;

    MostrarContraste;

    var Indice := CrearIndice(Conn);

    SeccionBusqueda(Conn, Indice);
    SeccionFAQBot(Conn);

    Titulo('Summary');
    Writeln('  5-phase pipeline executed successfully');
    Writeln('  Semantic search found documents by meaning,');
    Writeln('  not by exact text match.');
    Writeln('  The FAQ Bot answered without needing text identical to the indexed one.');
    Writeln(Format('  Model: %s — reindex if the model changes', [MODEL]));

  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
