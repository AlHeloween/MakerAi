program GraphBuilder;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 05-RAGGraph / 02-GraphBuilder
// =============================================================================
// Builds a more complex graph and navigates relationships between nodes.
// Shows how to traverse neighbors, find paths, and analyze the graph.
//
// Concepts covered:
//   - Scientific domain graph (disciplines, concepts, authors)
//   - FindNodesByLabel: search nodes by label
//   - FindNodeByName: search node by name
//   - GetNeighbors: neighbors of a node
//   - GetShortestPath: shortest path between nodes
//   - GetNodesByDegree: most connected nodes
//   - Semantic search with depth (depth > 0)
// =============================================================================

uses
  System.SysUtils,
  System.Generics.Collections,
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
//  Computer science graph
// =============================================================================
procedure ConstruirGrafoCiencias(RAG: TAiRagGraph);
var
  // Disciplines
  IA, ML, DL, NLP, CV: TAiRagGraphNode;
  // Techniques
  NN, CNN, RNN, Transformer, RAGTech: TAiRagGraphNode;
  // Frameworks
  TensorFlow, PyTorch, Keras: TAiRagGraphNode;
begin
  Writeln('Building computer science graph...');

  // --- Disciplines ---
  IA := RAG.AddNode('d001', 'DISCIPLINE', 'Artificial Intelligence');
  IA.Text := 'Artificial Intelligence: branch of computer science that simulates cognitive capabilities.';

  ML := RAG.AddNode('d002', 'DISCIPLINE', 'Machine Learning');
  ML.Text := 'Machine Learning: subfield of AI that learns patterns from data.';

  DL := RAG.AddNode('d003', 'DISCIPLINE', 'Deep Learning');
  DL.Text := 'Deep Learning: ML with deep neural networks of multiple layers.';

  NLP := RAG.AddNode('d004', 'DISCIPLINE', 'Natural Language Processing');
  NLP.Text := 'NLP: branch of AI for understanding and generating text in human language.';

  CV := RAG.AddNode('d005', 'DISCIPLINE', 'Computer Vision');
  CV.Text := 'Computer Vision: AI for interpreting and analyzing images and video.';

  // --- Techniques ---
  NN := RAG.AddNode('t001', 'TECHNIQUE', 'Neural Networks');
  NN.Text := 'Artificial neural networks inspired by the human brain.';

  CNN := RAG.AddNode('t002', 'TECHNIQUE', 'CNN');
  CNN.Text := 'Convolutional Neural Networks, specialized in image analysis.';

  RNN := RAG.AddNode('t003', 'TECHNIQUE', 'RNN');
  RNN.Text := 'Recurrent Neural Networks, for sequences and temporal data.';

  Transformer := RAG.AddNode('t004', 'TECHNIQUE', 'Transformer');
  Transformer.Text := 'Transformer architecture with attention, basis of GPT and BERT.';

  RAGTech := RAG.AddNode('t005', 'TECHNIQUE', 'RAG');
  RAGTech.Text := 'Retrieval Augmented Generation: combines vector search with LLMs.';

  // --- Frameworks ---
  TensorFlow := RAG.AddNode('f001', 'FRAMEWORK', 'TensorFlow');
  TensorFlow.Text := 'TensorFlow: Google ML framework for production.';

  PyTorch := RAG.AddNode('f002', 'FRAMEWORK', 'PyTorch');
  PyTorch.Text := 'PyTorch: Meta ML framework, popular in research.';

  Keras := RAG.AddNode('f003', 'FRAMEWORK', 'Keras');
  Keras.Text := 'Keras: high-level API for building neural networks.';

  // --- Hierarchical relationships ---
  RAG.AddEdge(IA, ML,  'h001', 'INCLUDES', 'includes');
  RAG.AddEdge(ML, DL,  'h002', 'INCLUDES', 'includes');
  RAG.AddEdge(DL, NLP, 'h003', 'ENABLES', 'enables');
  RAG.AddEdge(DL, CV,  'h004', 'ENABLES', 'enables');

  // --- Relationships technique → discipline ---
  RAG.AddEdge(NN,          ML,  'u001', 'USED_IN', 'used in');
  RAG.AddEdge(CNN,         CV,  'u002', 'USED_IN', 'used in');
  RAG.AddEdge(RNN,         NLP, 'u003', 'USED_IN', 'used in');
  RAG.AddEdge(Transformer, NLP, 'u004', 'USED_IN', 'used in');
  RAG.AddEdge(RAGTech,     NLP, 'u005', 'USED_IN', 'used in');

  // --- Relationships framework → technique ---
  RAG.AddEdge(TensorFlow, NN,          'i001', 'IMPLEMENTS', 'implements');
  RAG.AddEdge(PyTorch,    Transformer, 'i002', 'IMPLEMENTS', 'implements');
  RAG.AddEdge(Keras,      CNN,         'i003', 'IMPLEMENTS', 'implements');

  Writeln(Format('Graph ready: %d nodes, %d edges.', [RAG.NodeCount, RAG.EdgeCount]));
  Writeln;
end;

// =============================================================================
//  Shows neighbors of a node
// =============================================================================
procedure MostrarVecinos(RAG: TAiRagGraph; const NodeName, NodeLabel: String);
var
  Node     : TAiRagGraphNode;
  Vecinos  : TArray<TAiRagGraphNode>;
  Vecino   : TAiRagGraphNode;
begin
  Node := RAG.FindNodeByName(NodeName, NodeLabel);
  if not Assigned(Node) then
  begin
    Writeln('Node not found: ', NodeName);
    Exit;
  end;

  Writeln(StringOfChar('-', 60));
  Writeln('Neighbors of "', Node.Name, '" (', Node.NodeLabel, '):');

  Vecinos := RAG.GetNeighbors(Node, gdOutgoing);
  if Length(Vecinos) = 0 then
    Writeln('  (no outgoing neighbors)')
  else
    for Vecino in Vecinos do
      Writeln(Format('  --> %s (%s)', [Vecino.Name, Vecino.NodeLabel]));
end;

// =============================================================================
//  Shortest path between two nodes
// =============================================================================
procedure MostrarCaminoMinimo(RAG: TAiRagGraph;
  const NombreA, LabelA, NombreB, LabelB: String);
var
  NodeA, NodeB: TAiRagGraphNode;
  Camino      : TArray<TObject>;
  I           : Integer;
  Obj         : TObject;
begin
  NodeA := RAG.FindNodeByName(NombreA, LabelA);
  NodeB := RAG.FindNodeByName(NombreB, LabelB);

  if not Assigned(NodeA) or not Assigned(NodeB) then
  begin
    Writeln('Nodes not found for shortest path.');
    Exit;
  end;

  Writeln(StringOfChar('-', 60));
  Writeln(Format('Shortest path: "%s" --> "%s"', [NombreA, NombreB]));

  Camino := RAG.GetShortestPath(NodeA, NodeB);
  if Length(Camino) = 0 then
  begin
    Writeln('  (no path)');
    Exit;
  end;

  for I := 0 to High(Camino) do
  begin
    Obj := Camino[I];
    if Obj is TAiRagGraphNode then
      Write(Format('[%s]', [(Obj as TAiRagGraphNode).Name]))
    else if Obj is TAiRagGraphEdge then
      Write(Format('--%s-->', [(Obj as TAiRagGraphEdge).EdgeLabel]));
  end;
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn  : TAiEmbeddingConnection;
  RAG      : TAiRagGraph;
  TopNodes : TArray<TAiRagGraphNode>;
  Node     : TAiRagGraphNode;
begin
  Writeln('=== GraphBuilder ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRagGraph.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings := EmbConn.AiEmbeddings;

    ConstruirGrafoCiencias(RAG);

    Writeln('Generating embeddings...');
    RAG.RebuildIndexes;
    Writeln('Ready.');
    Writeln;

    // Neighbors
    MostrarVecinos(RAG, 'Deep Learning', 'DISCIPLINE');
    MostrarVecinos(RAG, 'PyTorch', 'FRAMEWORK');
    Writeln;

    // Shortest path
    MostrarCaminoMinimo(RAG,
      'PyTorch', 'FRAMEWORK',
      'Procesamiento de Lenguaje Natural', 'DISCIPLINA');
    Writeln;

    // Most connected nodes
    Writeln(StringOfChar('-', 60));
    Writeln('Top 3 most connected nodes:');
    TopNodes := RAG.GetNodesByDegree(3);
    for Node in TopNodes do
      Writeln(Format('  %s (%s)', [Node.Name, Node.NodeLabel]));
    Writeln;

    // Semantic search with depth=1 (expands neighbors)
    Writeln(StringOfChar('-', 60));
    Writeln('Semantic search with expansion (depth=1):');
    Writeln('"text generation with transformers"');
    Writeln(RAG.SearchText('text generation with transformers', 1, False, 3, 0.2));

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
