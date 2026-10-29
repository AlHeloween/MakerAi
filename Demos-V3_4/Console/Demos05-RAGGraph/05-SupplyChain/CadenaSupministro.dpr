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
  Writeln('Consulta: ', Descripcion);
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
  Titulo('Sec. 23.3 — Fase 1: Construyendo el grafo de cadena de suministro');

  // Providers
  SteelCorp := RAG.AddNode('prov-001', 'PROVEEDOR', 'Steel Corp');
  SteelCorp.Text := 'Steel Corp provee acero y metales de alta calidad para manufactura industrial.';
  SteelCorp.Properties['pais']      := 'Alemania';
  SteelCorp.Properties['confianza'] := 0.95;

  PlasticosSA := RAG.AddNode('prov-002', 'PROVEEDOR', 'Plasticos SA');
  PlasticosSA.Text := 'Plasticos SA fabrica piezas de plastico moldeado por inyeccion.';
  PlasticosSA.Properties['pais']      := 'Mexico';
  PlasticosSA.Properties['confianza'] := 0.88;

  ElectroGlobal := RAG.AddNode('prov-003', 'PROVEEDOR', 'Electronica Global');
  ElectroGlobal.Text := 'Electronica Global suministra tarjetas de circuito y componentes electronicos.';
  ElectroGlobal.Properties['pais']      := 'Taiwan';
  ElectroGlobal.Properties['confianza'] := 0.92;

  // Components
  Chasis := RAG.AddNode('comp-001', 'COMPONENTE', 'Chasis Metalico');
  Chasis.Text := 'Chasis de acero soldado que soporta la estructura mecanica del robot.';
  Chasis.Properties['peso_kg'] := 12.5;
  Chasis.Properties['material']:= 'Acero inoxidable';

  Panel := RAG.AddNode('comp-002', 'COMPONENTE', 'Panel de Control');
  Panel.Text := 'Panel de plastico que aloja la interfaz de usuario y los controles del robot.';
  Panel.Properties['peso_kg'] := 1.2;
  Panel.Properties['material']:= 'ABS reforzado';

  Tarjeta := RAG.AddNode('comp-003', 'COMPONENTE', 'Tarjeta Controladora');
  Tarjeta.Text := 'Tarjeta electronica con microprocesador ARM que controla todos los movimientos.';
  Tarjeta.Properties['peso_kg']    := 0.3;
  Tarjeta.Properties['procesador'] := 'ARM Cortex-M7';

  Motor := RAG.AddNode('comp-004', 'COMPONENTE', 'Motor Electrico');
  Motor.Text := 'Motor electrico de precision para articulaciones roboticas de alta velocidad.';
  Motor.Properties['peso_kg'] := 2.8;
  Motor.Properties['rpm']     := 3000;

  // Products
  RobotA1 := RAG.AddNode('prod-001', 'PRODUCTO', 'Robot Industrial A1');
  RobotA1.Text := 'Robot Industrial A1 para ensamblaje automotriz. Precision submilimetrica.';
  RobotA1.Properties['precio']   := 45000.0;
  RobotA1.Properties['categoria']:= 'Industrial';

  BrazoB2 := RAG.AddNode('prod-002', 'PRODUCTO', 'Brazo Robotico B2');
  BrazoB2.Text := 'Brazo Robotico B2 colaborativo para trabajo junto a operadores humanos.';
  BrazoB2.Properties['precio']   := 28000.0;
  BrazoB2.Properties['categoria']:= 'Colaborativo';

  // Clients
  AutoFabrik := RAG.AddNode('cli-001', 'CLIENTE', 'AutoFabrik GmbH');
  AutoFabrik.Text := 'Fabricante aleman de automoviles con lineas de ensamblaje automatizadas.';
  AutoFabrik.Properties['sector'] := 'Automotriz';
  AutoFabrik.Properties['pais']   := 'Alemania';

  TechAssembly := RAG.AddNode('cli-002', 'CLIENTE', 'TechAssembly Inc');
  TechAssembly.Text := 'Empresa americana de ensamblaje de electronica de consumo.';
  TechAssembly.Properties['sector']:= 'Electronica';
  TechAssembly.Properties['pais']  := 'Estados Unidos';

  // Edges Provider -> Component
  RAG.AddEdge(SteelCorp,    Chasis,  'r001', 'SUMINISTRA', 'suministra', 0.95);
  RAG.AddEdge(PlasticosSA,  Panel,   'r002', 'SUMINISTRA', 'suministra', 0.88);
  RAG.AddEdge(ElectroGlobal,Tarjeta, 'r003', 'SUMINISTRA', 'suministra', 0.92);
  RAG.AddEdge(ElectroGlobal,Motor,   'r004', 'SUMINISTRA', 'suministra', 0.90);

  // Edges Component -> Product
  RAG.AddEdge(Chasis,  RobotA1, 'r005', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Panel,   RobotA1, 'r006', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Tarjeta, RobotA1, 'r007', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Motor,   RobotA1, 'r008', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Panel,   BrazoB2, 'r009', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Tarjeta, BrazoB2, 'r010', 'PARTE_DE', 'parte de', 1.0);
  RAG.AddEdge(Motor,   BrazoB2, 'r011', 'PARTE_DE', 'parte de', 1.0);

  // Edges Product -> Client
  RAG.AddEdge(RobotA1, AutoFabrik,   'r012', 'COMPRADO_POR', 'comprado por', 0.85);
  RAG.AddEdge(RobotA1, TechAssembly, 'r013', 'COMPRADO_POR', 'comprado por', 0.70);
  RAG.AddEdge(BrazoB2, TechAssembly, 'r014', 'COMPRADO_POR', 'comprado por', 0.90);

  Writeln(Format('  Graph built: %d nodes, %d edges.',
    [RAG.NodeCount, RAG.EdgeCount]));
end;

// =============================================================================
//  Sec. 23.4 — GQL queries
// =============================================================================
procedure SeccionGQL(RAG: TAiRagGraph);
begin
  Titulo('Sec. 23.4 — GQL queries on the graph');

  EjecutarGQL(RAG, 'Etiquetas del grafo', 'SHOW LABELS');
  EjecutarGQL(RAG, 'Tipos de aristas',    'SHOW EDGES');

  EjecutarGQL(RAG,
    'All providers',
    'MATCH (p:PROVEEDOR) RETURN p');

  EjecutarGQL(RAG,
    'Components from Electronica Global',
    'MATCH (p:PROVEEDOR)-[r:SUMINISTRA]->(c:COMPONENTE) ' +
    'WHERE p.name = "Electronica Global" RETURN c');

  EjecutarGQL(RAG,
    'Providers with high confidence (> 0.90)',
    'MATCH (p:PROVEEDOR) WHERE p.confianza > 0.90 RETURN p');

  EjecutarGQL(RAG,
    'What TechAssembly Inc buys',
    'MATCH (prod:PRODUCTO)-[r:COMPRADO_POR]->(c:CLIENTE) ' +
    'WHERE c.name = "TechAssembly Inc" RETURN prod');

  EjecutarGQL(RAG,
    'Shortest path: Steel Corp to AutoFabrik GmbH',
    'SHORTEST PATH (n1:PROVEEDOR {name: "Steel Corp"}) ' +
    'TO (n2:CLIENTE {name: "AutoFabrik GmbH"})');
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

  // Patron RAG Grafo: resultado de GQL → contexto para el LLM
  Titulo('Sec. 23.5 — Graph RAG pattern: context for the LLM');
  Writeln('  Question: Who supplies the components of Robot Industrial A1?');
  Writeln;

  GQLQuery :=
    'MATCH (prov:PROVEEDOR)-[r:SUMINISTRA]->(comp:COMPONENTE)' +
    '-[p:PARTE_DE]->(prod:PRODUCTO) ' +
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
