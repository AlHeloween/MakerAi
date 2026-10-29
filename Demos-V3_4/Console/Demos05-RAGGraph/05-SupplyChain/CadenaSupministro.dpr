program CadenaSupministro;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 05-RAGGraph / 05-SupplyChain
// =============================================================================
// Supply chain analysis system with graph RAG.
// Demonstrates how TAiRagGraph models related entities and allows
// GQL queries and semantic search on the graph.
//
// Concepts it covers (section 23 of the book):
//   - Build graph: AddNode, AddEdge (with node objects, not text IDs)
//   - Node properties (.Text, .Properties[])
//   - GQL: SHOW LABELS/EDGES, MATCH with WHERE, SHORTEST PATH
//   - Semantic search: RebuildIndexes + SearchText
//   - Graph RAG pattern: ExecuteMakerGQL returns String for SystemPrompt
//   - Persistence: SaveToMakerAi / LoadFromMakerAi
//
// Provider: OpenAI (text-embedding-3-small)
//   ApiKey: OPENAI_API_KEY environment variable
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

procedure Titulo(const S: String);
begin
  Writeln;
  Writeln(StringOfChar('=', 62));
  Writeln(S);
  Writeln(StringOfChar('=', 62));
end;

procedure EjecutarGQL(RAG: TAiRagGraph; const Descripcion, Query: String);
begin
  Writeln(StringOfChar('-', 50));
  Writeln('Query: ', Descripcion);
  Writeln('GQL: ', Query);
  Writeln;
  try
    Writeln(RAG.ExecuteMakerGQL(Query));
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
  Writeln;
end;

// =============================================================================
//  Sec. 23.3 — Build the supply chain graph
// =============================================================================
procedure ConstruirGrafo(RAG: TAiRagGraph);
var
  SteelCorp, PlasticosSA, ElectroGlobal: TAiRagGraphNode;
  Chasis, Panel, Tarjeta, Motor         : TAiRagGraphNode;
  RobotA1, BrazoB2                      : TAiRagGraphNode;
  AutoFabrik, TechAssembly              : TAiRagGraphNode;
begin
  Titulo('Sec. 23.3 — Phase 1: Building the supply chain graph');

  // Providers
  SteelCorp := RAG.AddNode('prov-001', 'SUPPLIER', 'Steel Corp');
  SteelCorp.Text := 'Steel Corp supplies high-quality steel and metals for industrial manufacturing.';
  SteelCorp.Properties['country']      := 'Germany';
  SteelCorp.Properties['confianza'] := 0.95;

  PlasticosSA := RAG.AddNode('prov-002', 'SUPPLIER', 'Plastics SA');
  PlasticosSA.Text := 'Plastics SA manufactures injection-molded plastic parts.';
  PlasticosSA.Properties['country']      := 'Mexico';
  PlasticosSA.Properties['confianza'] := 0.88;

  ElectroGlobal := RAG.AddNode('prov-003', 'SUPPLIER', 'Global Electronics');
  ElectroGlobal.Text := 'Global Electronics supplies circuit boards and electronic components.';
  ElectroGlobal.Properties['country']      := 'Taiwan';
  ElectroGlobal.Properties['confianza'] := 0.92;

  // Components
  Chasis := RAG.AddNode('comp-001', 'COMPONENT', 'Metal Chassis');
  Chasis.Text := 'Welded steel chassis that supports the robot mechanical structure.';
  Chasis.Properties['peso_kg'] := 12.5;
  Chasis.Properties['material']:= 'Stainless steel';

  Panel := RAG.AddNode('comp-002', 'COMPONENT', 'Control Panel');
  Panel.Text := 'Plastic panel that houses the user interface and robot controls.';
  Panel.Properties['peso_kg'] := 1.2;
  Panel.Properties['material']:= 'Reinforced ABS';

  Tarjeta := RAG.AddNode('comp-003', 'COMPONENT', 'Controller Card');
  Tarjeta.Text := 'Electronic board with ARM microprocessor that controls all movements.';
  Tarjeta.Properties['peso_kg']    := 0.3;
  Tarjeta.Properties['processor'] := 'ARM Cortex-M7';

  Motor := RAG.AddNode('comp-004', 'COMPONENT', 'Electric Motor');
  Motor.Text := 'Precision electric motor for high-speed robotic joints.';
  Motor.Properties['peso_kg'] := 2.8;
  Motor.Properties['rpm']     := 3000;

  // Products
  RobotA1 := RAG.AddNode('prod-001', 'PRODUCT', 'Industrial Robot A1');
  RobotA1.Text := 'Industrial Robot A1 for automotive assembly. Submillimeter precision.';
  RobotA1.Properties['precio']   := 45000.0;
  RobotA1.Properties['category']:= 'Industrial';

  BrazoB2 := RAG.AddNode('prod-002', 'PRODUCT', 'Robotic Arm B2');
  BrazoB2.Text := 'Collaborative Robotic Arm B2 for work alongside human operators.';
  BrazoB2.Properties['precio']   := 28000.0;
  BrazoB2.Properties['category']:= 'Collaborative';

  // Clients
  AutoFabrik := RAG.AddNode('cli-001', 'CLIENT', 'AutoFabrik GmbH');
  AutoFabrik.Text := 'German automobile manufacturer with automated assembly lines.';
  AutoFabrik.Properties['sector'] := 'Automotive';
  AutoFabrik.Properties['pais']   := 'Germany';

  TechAssembly := RAG.AddNode('cli-002', 'CLIENT', 'TechAssembly Inc');
  TechAssembly.Text := 'American consumer electronics assembly company.';
  TechAssembly.Properties['sector']:= 'Electronics';
  TechAssembly.Properties['pais']  := 'United States';

  // Edges Provider -> Component
  RAG.AddEdge(SteelCorp,    Chasis,  'r001', 'SUPPLIES', 'supplies', 0.95);
  RAG.AddEdge(PlasticosSA,  Panel,   'r002', 'SUPPLIES', 'supplies', 0.88);
  RAG.AddEdge(ElectroGlobal,Tarjeta, 'r003', 'SUPPLIES', 'supplies', 0.92);
  RAG.AddEdge(ElectroGlobal,Motor,   'r004', 'SUPPLIES', 'supplies', 0.90);

  // Edges Component -> Product
  RAG.AddEdge(Chasis,  RobotA1, 'r005', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Panel,   RobotA1, 'r006', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Tarjeta, RobotA1, 'r007', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Motor,   RobotA1, 'r008', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Panel,   BrazoB2, 'r009', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Tarjeta, BrazoB2, 'r010', 'PART_OF', 'part of', 1.0);
  RAG.AddEdge(Motor,   BrazoB2, 'r011', 'PART_OF', 'part of', 1.0);

  // Edges Product -> Client
  RAG.AddEdge(RobotA1, AutoFabrik,   'r012', 'PURCHASED_BY', 'purchased by', 0.85);
  RAG.AddEdge(RobotA1, TechAssembly, 'r013', 'PURCHASED_BY', 'purchased by', 0.70);
  RAG.AddEdge(BrazoB2, TechAssembly, 'r014', 'PURCHASED_BY', 'purchased by', 0.90);

  Writeln(Format('  Graph built: %d nodes, %d edges.',
    [RAG.NodeCount, RAG.EdgeCount]));
end;

// =============================================================================
//  Sec. 23.4 — GQL queries
// =============================================================================
procedure SeccionGQL(RAG: TAiRagGraph);
begin
  Titulo('Sec. 23.4 — GQL queries on the graph');

  EjecutarGQL(RAG, 'Graph labels', 'SHOW LABELS');
  EjecutarGQL(RAG, 'Edge types',    'SHOW EDGES');

  EjecutarGQL(RAG,
    'All providers',
    'MATCH (p:PROVEEDOR) RETURN p');

  EjecutarGQL(RAG,
    'Components from Electronica Global',
    'MATCH (p:SUPPLIER)-[r:SUPPLIES]->(c:COMPONENT) ' +
    'WHERE p.name = "Global Electronics" RETURN c');

  EjecutarGQL(RAG,
    'Providers with high confidence (> 0.90)',
    'MATCH (p:SUPPLIER) WHERE p.confidence > 0.90 RETURN p');

  EjecutarGQL(RAG,
    'What TechAssembly Inc buys',
    'MATCH (prod:PRODUCT)-[r:PURCHASED_BY]->(c:CLIENT) ' +
    'WHERE c.name = "TechAssembly Inc" RETURN prod');

  EjecutarGQL(RAG,
    'Shortest path: Steel Corp to AutoFabrik GmbH',
    'SHORTEST PATH (n1:SUPPLIER {name: "Steel Corp"}) ' +
    'TO (n2:CLIENT {name: "AutoFabrik GmbH"})');
end;

// =============================================================================
//  Sec. 23.5 — Semantic search + Graph RAG pattern
// =============================================================================
procedure SeccionSemantica(RAG: TAiRagGraph);
var
  Preguntas: TArray<String>;
  Pregunta : String;
  Contexto : String;
  GQLQuery : String;
begin
  Titulo('Sec. 23.5 — Semantic search on the graph');
  Writeln('  (Embeddings generated with RebuildIndexes)');
  Writeln;

  Preguntas := [
    'electronic components and circuits',
    'automotive manufacturing',
    'European materials supplier'
  ];

  for Pregunta in Preguntas do
  begin
    Writeln(Format('  Search: "%s"', [Pregunta]));
    Writeln(RAG.SearchText(Pregunta, 0, True, 3, 0.1));
    Writeln;
  end;

  // Graph RAG pattern: GQL result → context for the LLM
  Titulo('Sec. 23.5 — Graph RAG pattern: context for the LLM');
  Writeln('  Question: Who supplies the components of Robot Industrial A1?');
  Writeln;

  GQLQuery :=
    'MATCH (prov:SUPPLIER)-[r:SUPPLIES]->(comp:COMPONENT)' +
    '-[p:PART_OF]->(prod:PRODUCT) ' +
    'WHERE prod.name = "Robot Industrial A1" RETURN prov, comp';

  Contexto := RAG.ExecuteMakerGQL(GQLQuery);

  Writeln('  Context obtained from the graph:');
  Writeln(Contexto);
  Writeln;
  Writeln('  Usage pattern with LLM:');
  Writeln('    AiConn.SystemPrompt := ''Answer with these graph data:'' + Contexto;');
  Writeln('    AiConn.AddMessageAndRun(Pregunta, ''user'', []);');
end;

// =============================================================================
//  PROGRAMA PRINCIPAL
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRagGraph;
begin
  Writeln('=== CadenaSupministro — Graph RAG ===');
  Writeln('Driver: ', EMB_DRIVER, ' / ', EMB_MODEL);

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRagGraph.Create(nil);
  try
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    RAG.Embeddings := EmbConn.AiEmbeddings;

    ConstruirGrafo(RAG);

    Writeln('  Generating embeddings...');
    RAG.RebuildIndexes;
    Writeln('  Done.');

    SeccionGQL(RAG);
    SeccionSemantica(RAG);

    Titulo('Persistence');
    RAG.SaveToMakerAi('cadena_suministro.json', True);
    Writeln('  Graph saved to cadena_suministro.json');
    Writeln('  To load: RAG.LoadFromMakerAi(''cadena_suministro.json'')');

    Titulo('Summary');
    Writeln('  Supply chain graph: 10 nodes, 14 edges.');
    Writeln('  GQL: MATCH/WHERE/RETURN, SHORTEST PATH.');
    Writeln('  SearchText: semantic search by embeddings.');
    Writeln('  ExecuteMakerGQL returns a String directly for the LLM SystemPrompt.');

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
