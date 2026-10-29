program GraphGQL;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 05-RAGGraph / 04-GQL
// =============================================================================
// MakerGQL: Cypher-like query language for MakerAI graphs.
// Allows querying the graph with declarative MATCH/WHERE/RETURN syntax.
//
// Concepts covered:
//   - ExecuteMakerGQL(code): executes a GQL query
//   - SHOW LABELS: lists node labels present
//   - SHOW EDGES: lists edge types
//   - MATCH (n:Label) RETURN n: search by label
//   - MATCH (a)-[r:LABEL]->(b) RETURN a, r, b: relationships
//   - WHERE: filters on properties
//   - SHORTEST PATH FROM (...) TO (...): shortest path
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Graph.Core,
  uMakerAi.RAG.Vectors;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

// =============================================================================
//  Movies and directors graph
// =============================================================================
procedure ConstruirGrafoPeliculas(RAG: TAiRagGraph);
var
  N: TAiRagGraphNode;
  // Directors
  Nolan, Spielberg, Kubrick, Cameron: TAiRagGraphNode;
  // Movies
  Inception, Interstellar, Schindler, ET, Odyssey,
  Shining, Titanic, Avatar: TAiRagGraphNode;
  // Genres
  SciFi, Drama, Terror, Aventura: TAiRagGraphNode;
begin
  // Directors
  Nolan := RAG.AddNode('d001', 'DIRECTOR', 'Christopher Nolan');
  Nolan.Text := 'Christopher Nolan, British director of complex scientific thrillers.';
  Nolan.Properties['nacionalidad'] := 'British';

  Spielberg := RAG.AddNode('d002', 'DIRECTOR', 'Steven Spielberg');
  Spielberg.Text := 'Steven Spielberg, American director of adventure, drama and science fiction.';
  Spielberg.Properties['nacionalidad'] := 'American';

  Kubrick := RAG.AddNode('d003', 'DIRECTOR', 'Stanley Kubrick');
  Kubrick.Text := 'Stanley Kubrick, visionary director of science fiction and horror.';
  Kubrick.Properties['nacionalidad'] := 'American';

  Cameron := RAG.AddNode('d004', 'DIRECTOR', 'James Cameron');
  Cameron.Text := 'James Cameron, director of action thrillers and visual science fiction.';
  Cameron.Properties['nacionalidad'] := 'Canadian';

  // Movies
  Inception := RAG.AddNode('p001', 'MOVIE', 'Inception');
  Inception.Text := 'Inception 2010: dreams within dreams, science fiction thriller.';
  Inception.Properties['año']  := 2010;
  Inception.Properties['nota'] := 8.8;

  Interstellar := RAG.AddNode('p002', 'MOVIE', 'Interstellar');
  Interstellar.Text := 'Interstellar 2014: space travel and wormholes, epic drama.';
  Interstellar.Properties['año']  := 2014;
  Interstellar.Properties['nota'] := 8.6;

  Schindler := RAG.AddNode('p003', 'MOVIE', 'Schindler''s List');
  Schindler.Text := 'Schindler''s List 1993: historical drama of the Holocaust.';
  Schindler.Properties['año']  := 1993;
  Schindler.Properties['nota'] := 8.9;

  ET := RAG.AddNode('p004', 'MOVIE', 'E.T.');
  ET.Text := 'E.T. the Extra-Terrestrial 1982: adventure of a boy with a friendly alien.';
  ET.Properties['año']  := 1982;
  ET.Properties['nota'] := 7.9;

  Odyssey := RAG.AddNode('p005', 'MOVIE', '2001: A Space Odyssey');
  Odyssey.Text := '2001: A Space Odyssey 1968, philosophical space travel and mysterious monolith.';
  Odyssey.Properties['año']  := 1968;
  Odyssey.Properties['nota'] := 8.3;

  Shining := RAG.AddNode('p006', 'MOVIE', 'The Shining');
  Shining.Text := 'The Shining 1980: isolated hotel and madness, psychological horror.';
  Shining.Properties['año']  := 1980;
  Shining.Properties['nota'] := 8.4;

  Titanic := RAG.AddNode('p007', 'MOVIE', 'Titanic');
  Titanic.Text := 'Titanic 1997: epic romance on the sinking ship.';
  Titanic.Properties['año']  := 1997;
  Titanic.Properties['nota'] := 7.9;

  Avatar := RAG.AddNode('p008', 'MOVIE', 'Avatar');
  Avatar.Text := 'Avatar 2009: planet Pandora and struggle for natural resources.';
  Avatar.Properties['año']  := 2009;
  Avatar.Properties['nota'] := 7.9;

  // Genres
  SciFi    := RAG.AddNode('g001', 'GENRE', 'Science Fiction');
  Drama    := RAG.AddNode('g002', 'GENERO', 'Drama');
  Terror   := RAG.AddNode('g003', 'GENRE', 'Horror');
  Aventura := RAG.AddNode('g004', 'GENRE', 'Adventure');

  SciFi.Text    := 'Science fiction: genre of futuristic technology and alternate spaces.';
  Drama.Text    := 'Drama: genre of deep emotions and human conflicts.';
  Terror.Text   := 'Horror: genre of fear, suspense and dark atmospheres.';
  Aventura.Text := 'Adventure: genre of travel, action and discoveries.';

  // Director → Movie
  RAG.AddEdge(Nolan,     Inception,     'r001', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Nolan,     Interstellar,  'r002', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Spielberg, Schindler,     'r003', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Spielberg, ET,            'r004', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Kubrick,   Odyssey,       'r005', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Kubrick,   Shining,       'r006', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Cameron,   Titanic,       'r007', 'DIRECTED', 'directed', 0.9);
  RAG.AddEdge(Cameron,   Avatar,        'r008', 'DIRECTED', 'directed', 0.9);

  // Movie → Genre
  RAG.AddEdge(Inception,    SciFi,    'g001', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Interstellar, SciFi,    'g002', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Interstellar, Drama,    'g003', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Schindler,    Drama,    'g004', 'IS_GENRE', 'is genre');
  RAG.AddEdge(ET,           Aventura, 'g005', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Odyssey,      SciFi,    'g006', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Shining,      Terror,   'g007', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Titanic,      Drama,    'g008', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Avatar,       SciFi,    'g009', 'IS_GENRE', 'is genre');
  RAG.AddEdge(Avatar,       Aventura, 'g010', 'IS_GENRE', 'is genre');

  Writeln(Format('Graph ready: %d nodes, %d edges.', [RAG.NodeCount, RAG.EdgeCount]));
  Writeln;
end;

// =============================================================================
//  Ejecuta una consulta GQL y muestra el resultado
// =============================================================================
procedure EjecutarGQL(RAG: TAiRagGraph; const Descripcion, Query: String);
var
  Resultado: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Consulta: ', Descripcion);
  Writeln('GQL: ', Query);
  Writeln;
  try
    Resultado := RAG.ExecuteMakerGQL(Query);
    Writeln(Resultado);
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRagGraph;
begin
  Writeln('=== GraphGQL ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRagGraph.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings := EmbConn.AiEmbeddings;

    ConstruirGrafoPeliculas(RAG);

    Writeln('Generating embeddings...');
    RAG.RebuildIndexes;
    Writeln;

    // ── Exploration commands ───────────────────────────────────────────
    EjecutarGQL(RAG,
      'List node labels',
      'SHOW LABELS');

    EjecutarGQL(RAG,
      'List edge types',
      'SHOW EDGES');

    // ── Basic MATCH queries ───────────────────────────────────────────
    EjecutarGQL(RAG,
      'All directors',
      'MATCH (d:DIRECTOR) RETURN d');

    EjecutarGQL(RAG,
      'Movies by Christopher Nolan',
      'MATCH (d:DIRECTOR)-[r:DIRECTED]->(p:MOVIE) WHERE d.nombre = "Christopher Nolan" RETURN p');

    // ── Queries with WHERE ───────────────────────────────────────────────
    EjecutarGQL(RAG,
      'Movies with rating > 8.5',
      'MATCH (p:MOVIE) WHERE p.nota > 8.5 RETURN p');

    EjecutarGQL(RAG,
      'Movies before 1990',
      'MATCH (p:MOVIE) WHERE p.año < 1990 RETURN p');

    // ── Complete relationships ──────────────────────────────────────────────
    EjecutarGQL(RAG,
      'Science fiction movies with their director',
      'MATCH (d:DIRECTOR)-[r:DIRIGIO]->(p:PELICULA)-[g:ES_DE_GENERO]->(gen:GENERO) ' +
      'WHERE gen.nombre = "Science Fiction" RETURN d, p');

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
