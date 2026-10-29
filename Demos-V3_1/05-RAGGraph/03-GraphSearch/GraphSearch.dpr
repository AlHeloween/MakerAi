program GraphSearch;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 05-RAGGraph / 03-GraphSearch
// =============================================================================
// Demonstrates the different search strategies in a Knowledge Graph.
//
// Concepts covered:
//   - Search() → TArray<TAiRagGraphNode>: result as objects
//   - SearchText() → String: result formatted as text
//   - depth=0: anchor nodes only; depth=1: nodes + direct neighbors
//   - Difference between shallow and deep search
//   - SaveToMakerAi / SaveToFile: graph persistence
//   - FindNodesByLabel: filter by entity type
//   - CountNodesByLabel / CountEdgesByLabel
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Graph.Core,
  uMakerAi.RAG.Vectors;

const
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

  GRAPH_FILE  = 'historia_tech.mkai';

// =============================================================================
//  Technology history graph
// =============================================================================
procedure ConstruirGrafoHistoria(RAG: TAiRagGraph);
var
  N: TAiRagGraphNode;
  // Décadas
  D70, D80, D90, D00, D10, D20: TAiRagGraphNode;
begin
  // Historical technology events
  N := RAG.AddNode('ev001', 'EVENT', 'Creation of UNIX');
  N.Text := 'UNIX was created at Bell Labs in 1969, basis of Linux and macOS.';
  N.Properties['año'] := 1969;

  N := RAG.AddNode('ev002', 'EVENT', 'Launch of Apple II');
  N.Text := 'Apple II in 1977, first massively successful personal computer.';
  N.Properties['año'] := 1977;

  N := RAG.AddNode('ev003', 'EVENT', 'Creation of Internet TCP/IP');
  N.Text := 'TCP/IP in 1983 standardized Internet communications.';
  N.Properties['año'] := 1983;

  N := RAG.AddNode('ev004', 'EVENT', 'Launch of Windows');
  N.Text := 'Windows 1.0 in 1985, Microsoft graphical interface.';
  N.Properties['año'] := 1985;

  N := RAG.AddNode('ev005', 'EVENT', 'Creation of World Wide Web');
  N.Text := 'Tim Berners-Lee created the WWW in 1991 at CERN.';
  N.Properties['año'] := 1991;

  N := RAG.AddNode('ev006', 'EVENT', 'Launch of Linux');
  N.Text := 'Linux kernel created by Linus Torvalds in 1991, open source OS.';
  N.Properties['año'] := 1991;

  N := RAG.AddNode('ev007', 'EVENT', 'Foundation of Google');
  N.Text := 'Google founded in 1998 by Page and Brin, revolutionized web search.';
  N.Properties['año'] := 1998;

  N := RAG.AddNode('ev008', 'EVENT', 'Creation of Wikipedia');
  N.Text := 'Wikipedia founded in 2001, collaborative encyclopedia on the internet.';
  N.Properties['año'] := 2001;

  N := RAG.AddNode('ev009', 'EVENT', 'Launch of iPhone');
  N.Text := 'Apple iPhone in 2007 revolutionized smartphones and mobility.';
  N.Properties['año'] := 2007;

  N := RAG.AddNode('ev010', 'EVENT', 'Launch of ChatGPT');
  N.Text := 'ChatGPT launched in November 2022, massively popularized LLMs.';
  N.Properties['año'] := 2022;

  // Decades as temporal nodes
  D70 := RAG.AddNode('dec70', 'DECADE', '1970s');
  D70.Text := '1970s: beginning of personal computing and UNIX.';
  D80 := RAG.AddNode('dec80', 'DECADE', '1980s');
  D80.Text := '1980s: PC, GUIs and the beginning of the global network.';
  D90 := RAG.AddNode('dec90', 'DECADE', '1990s');
  D90.Text := '1990s: Internet, web, Linux and open source software.';
  D00 := RAG.AddNode('dec00', 'DECADE', '2000s');
  D00.Text := '2000s: web 2.0, social networks and cloud computing.';
  D10 := RAG.AddNode('dec10', 'DECADE', '2010s');
  D10.Text := '2010s: mobile, big data, deep learning and smartphones.';
  D20 := RAG.AddNode('dec20', 'DECADE', '2020s');
  D20.Text := '2020s: generative AI, LLMs and transformers.';

  // Relationships event → decades
  var Ev001 := RAG.FindNodeByID('ev001');
  var Ev002 := RAG.FindNodeByID('ev002');
  var Ev003 := RAG.FindNodeByID('ev003');
  var Ev004 := RAG.FindNodeByID('ev004');
  var Ev005 := RAG.FindNodeByID('ev005');
  var Ev006 := RAG.FindNodeByID('ev006');
  var Ev007 := RAG.FindNodeByID('ev007');
  var Ev008 := RAG.FindNodeByID('ev008');
  var Ev009 := RAG.FindNodeByID('ev009');
  var Ev010 := RAG.FindNodeByID('ev010');

  RAG.AddEdge(Ev001, D70, 're001', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev002, D70, 're002', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev003, D80, 're003', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev004, D80, 're004', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev005, D90, 're005', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev006, D90, 're006', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev007, D90, 're007', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev008, D00, 're008', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev009, D00, 're009', 'OCCURRED_IN', 'occurred in');
  RAG.AddEdge(Ev010, D20, 're010', 'OCCURRED_IN', 'occurred in');

  Writeln(Format('Graph: %d nodes, %d edges.', [RAG.NodeCount, RAG.EdgeCount]));
end;

// =============================================================================
//  Compares shallow vs deep search
// =============================================================================
procedure CompararProfundidad(RAG: TAiRagGraph; const Query: String);
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Query: "', Query, '"');
  Writeln;

  Writeln('  depth=0 (anchor nodes only):');
  var R0 := RAG.SearchText(Query, 0, False, 2, 0.2);
  Writeln(R0);

  Writeln('  depth=1 (nodes + neighbors):');
  var R1 := RAG.SearchText(Query, 1, False, 2, 0.2);
  Writeln(R1);
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRagGraph;
  Nodes  : TArray<TAiRagGraphNode>;
  Node   : TAiRagGraphNode;
begin
  Writeln('=== GraphSearch ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRagGraph.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings := EmbConn.AiEmbeddings;

    ConstruirGrafoHistoria(RAG);

    Writeln('Generating embeddings...');
    RAG.RebuildIndexes;
    Writeln;

    // Statistics by type
    Writeln(StringOfChar('=', 60));
    Writeln('Statistics:');
    Writeln('  Events: ',   RAG.CountNodesByLabel('EVENT'));
    Writeln('  Decades: ',   RAG.CountNodesByLabel('DECADE'));
    Writeln('  Relationships: ', RAG.EdgeCount);
    Writeln;

    // List nodes by label
    Writeln(StringOfChar('-', 60));
    Writeln('All DECADE nodes:');
    Nodes := RAG.FindNodesByLabel('DECADE');
    for Node in Nodes do
      Writeln('  - ', Node.Name);
    Writeln;

    // Search at different depths
    CompararProfundidad(RAG, 'open source operating systems');
    CompararProfundidad(RAG, 'artificial intelligence and chatbots');

    // Search as node array
    Writeln(StringOfChar('-', 60));
    Writeln('Result as node array:');
    var ResultNodes := RAG.Search('internet search', 0, 3, 0.2);
    for var N in ResultNodes do
      Writeln(Format('  [%s] %s', [N.NodeLabel, N.Name]));
    Writeln;

    // Save graph
    Writeln(StringOfChar('-', 60));
    Writeln('Saving graph to: ', GRAPH_FILE);
    RAG.SaveToMakerAi(GRAPH_FILE, True);
    Writeln('Saved OK.');
    TFile.Delete(GRAPH_FILE);

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
