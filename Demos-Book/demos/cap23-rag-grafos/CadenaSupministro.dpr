program CadenaSupministro;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — Chapter 23: Graph RAG
// Demo: Supply chain — knowledge graph + LLM integration
// =============================================================================
//
//   A) Graph construction and GQL queries (without API key)
//      TAiRagGraph + structural GQL via ExecuteMakerGQL
//
//   B) Natural language → GQL → response via LLM (requires OPENAI_API_KEY)
//      The model generates the GQL query; the graph executes it; the model responds
//
// Prerequisite: MakerAI package installed.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.RAG.Graph.Core,
  uMakerAi.RAG.Graph.GQL,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi;  // auto-registers driver 'OpenAI' in the factory

const
  GRAFO_FILE    = 'cadena_suministro.makerAi';
  MODEL_OPENAI  = 'gpt-4o-mini';

// =============================================================================

function KeyPresente(const EnvVar: string): Boolean;
begin
  Result := GetEnvironmentVariable(EnvVar) <> '';
end;

procedure Separador;
begin
  WriteLn(StringOfChar('─', 64));
end;

// =============================================================================
//  Construction of the supply chain graph
// =============================================================================

function BuildSupplyChainGraph: TAiRagGraph;
var
  Grafo                     : TAiRagGraph;
  NodoMateria, NodoTech     : TAiRagGraphNode;
  NodoFabrica               : TAiRagGraphNode;
  NodoWidgetPro, NodoCompA  : TAiRagGraphNode;
  NodoDN, NodoDS            : TAiRagGraphNode;
  NodoEmpABC, NodoEmpXYZ    : TAiRagGraphNode;
begin
  Grafo := TAiRagGraph.Create(nil);

  // ── Suppliers ──────────────────────────────────────────────────────────
  NodoMateria := Grafo.AddNode('prov:materiasas',  'proveedor',    'MateriaSAS');
  NodoTech    := Grafo.AddNode('prov:techparts',   'proveedor',    'TechParts Ltd');

  // ── Manufacturer ────────────────────────────────────────────────────────────
  NodoFabrica := Grafo.AddNode('fab:fabrica_norte', 'fabricante',  'North Factory');

  // ── Products ─────────────────────────────────────────────────────────────
  NodoWidgetPro := Grafo.AddNode('prod:widget_pro', 'producto',    'Widget Pro');
  NodoCompA     := Grafo.AddNode('prod:comp_a',     'producto',    'Component A');

  // ── Distributors ────────────────────────────────────────────────────────
  NodoDN := Grafo.AddNode('dist:dist_norte', 'distribuidor', 'North Distributor');
  NodoDS := Grafo.AddNode('dist:dist_sur',   'distribuidor', 'South Distributor');

  // ── Customers ──────────────────────────────────────────────────────────────
  NodoEmpABC := Grafo.AddNode('cli:empresa_abc', 'cliente', 'Company ABC');
  NodoEmpXYZ := Grafo.AddNode('cli:empresa_xyz', 'cliente', 'Company XYZ');

  // ── Supply edges ─────────────────────────────────────────────────────────
  Grafo.AddEdge(NodoMateria, NodoFabrica, 'sum:1', 'PROVEE', 'MateriaSAS supplies North Factory');
  Grafo.AddEdge(NodoTech,    NodoFabrica, 'sum:2', 'PROVEE', 'TechParts supplies North Factory');

  // ── Manufacturing edges ────────────────────────────────────────────────
  Grafo.AddEdge(NodoFabrica, NodoWidgetPro, 'fab:1', 'FABRICA', 'North Factory manufactures Widget Pro');
  Grafo.AddEdge(NodoFabrica, NodoCompA,     'fab:2', 'FABRICA', 'North Factory manufactures Component A');

  // ── Distribution edges ───────────────────────────────────────────────
  Grafo.AddEdge(NodoDN, NodoWidgetPro, 'dis:1', 'DISTRIBUYE', 'North Distributor distributes Widget Pro');
  Grafo.AddEdge(NodoDS, NodoWidgetPro, 'dis:2', 'DISTRIBUYE', 'South Distributor distributes Widget Pro');

  // ── Purchase edges ─────────────────────────────────────────────────────
  Grafo.AddEdge(NodoEmpABC, NodoDN, 'com:1', 'COMPRA_DE', 'Company ABC buys from North Distributor');
  Grafo.AddEdge(NodoEmpXYZ, NodoDS, 'com:2', 'COMPRA_DE', 'Company XYZ buys from South Distributor');

  Result := Grafo;
end;

// =============================================================================
//  A) GQL query demo
// =============================================================================

procedure DemoGQL;
var
  Grafo    : TAiRagGraph;
  Resultado: string;
  Nodo     : TAiRagGraphNode;
  Vecinos  : TArray<TAiRagGraphNode>;
  N        : TAiRagGraphNode;
begin
  WriteLn('A) GQL queries on the supply chain graph');
  WriteLn('   (Without API key — in-memory structural operations)');
  Separador;

  Grafo := BuildSupplyChainGraph;
  try
    WriteLn;
    WriteLn('▶ Graph schema:');
    Resultado := Grafo.ExecuteMakerGQL('SHOW LABELS');
    WriteLn(Resultado);
    Resultado := Grafo.ExecuteMakerGQL('SHOW EDGES');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ All suppliers that supply factories:');
    Resultado := Grafo.ExecuteMakerGQL(
      'MATCH (p:proveedor)-[PROVEE]->(f:fabricante) RETURN p, f');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ Which products North Factory manufactures:');
    Resultado := Grafo.ExecuteMakerGQL(
      'MATCH (f:fabricante)-[FABRICA]->(p:producto) RETURN p');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ Shortest path: supplier → customer:');
    Resultado := Grafo.ExecuteMakerGQL(
      'SHORTEST PATH (s:proveedor) TO (c:cliente)');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ Direct neighbors of Company ABC (GetNeighbors method):');
    Nodo    := Grafo.FindNodeByID('cli:empresa_abc');
    Vecinos := Grafo.GetNeighbors(Nodo, gdBoth);
    for N in Vecinos do
      WriteLn('   → [', N.NodeLabel, '] ', N.Name);

    WriteLn;
    WriteLn(Format('Graph: %d nodes, %d edges',
      [Grafo.NodeCount, Grafo.EdgeCount]));

    // Save for use in section B
    Grafo.SaveToMakerAi(GRAFO_FILE);
    WriteLn('Graph saved in: ', GRAFO_FILE);
  finally
    Grafo.Free;
  end;
end;

// =============================================================================
//  B) LLM integration — natural language → GQL → response
// =============================================================================

procedure DemoLLM;
const
  PREGUNTA = 'Which suppliers supply North Factory and what products does it manufacture?';
  ESQUEMA  =
    'Labels (nodes): proveedor, fabricante, producto, distribuidor, cliente' + sLineBreak +
    'Edges (edges): PROVEE, FABRICA, DISTRIBUYE, COMPRA_DE' + sLineBreak +
    'Node property: name (string), e.g.: name = ''North Factory''' + sLineBreak +
    'Syntax: MATCH (a:label)-[r:EDGE]->(b:label) WHERE a.name = ''value'' RETURN a, r, b';
var
  Grafo   : TAiRagGraph;
  Conn    : TAiChatConnection;
  GQLQuery: string;
  Contexto: string;
  Resp    : string;
begin
  WriteLn('B) LLM integration — natural language → GQL → response (OpenAI)');
  Separador;

  Grafo := BuildSupplyChainGraph;
  Conn  := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := 'OpenAI';
    Conn.Model      := MODEL_OPENAI;
    Conn.Params.Values['ApiKey']       := '@OPENAI_API_KEY';
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';

    WriteLn;
    WriteLn('Question: ', PREGUNTA);
    WriteLn;

    // Step 1 — The LLM generates the GQL query
    Conn.SystemPrompt.Text :=
      'You are an expert in GQL (Graph Query Language) for MakerAI.' + sLineBreak +
      'Graph schema:' + sLineBreak + ESQUEMA + sLineBreak +
      'STRICT RULES:' + sLineBreak +
      '- Generate a SINGLE MATCH query on one line.' + sLineBreak +
      '- Use WHERE to filter by name: WHERE b.name = ''North Factory''' + sLineBreak +
      '- Return only the GQL query, without explanations.';

    GQLQuery := Conn.AddMessageAndRun(PREGUNTA, 'user', []).Trim;
    // Remove markdown code fences if the model included them (e.g.: ```gql...```)
    if GQLQuery.StartsWith('`') then
    begin
      var LF := GQLQuery.IndexOf(#10);
      if LF > 0 then
        GQLQuery := GQLQuery.Substring(LF + 1).Trim;
      if GQLQuery.EndsWith('```') then
        GQLQuery := GQLQuery.Substring(0, GQLQuery.Length - 3).Trim;
    end;
    WriteLn('[GQL generated by OpenAI]: ', GQLQuery);
    WriteLn;

    // Step 2 — Execute the query on the local graph
    Contexto := Grafo.ExecuteMakerGQL(GQLQuery);
    WriteLn('[Graph context]: ', Contexto);
    WriteLn;

    // Step 3 — The LLM synthesizes the final response
    Conn.NewChat;
    Conn.SystemPrompt.Text :=
      'You are a supply chain analysis assistant. ' +
      'Respond in English clearly and concisely, using only the data provided by the graph.';

    Resp := Conn.AddMessageAndRun(
      PREGUNTA + #13#10 +
      'Knowledge graph data:' + #13#10 + Contexto,
      'user', []);

    WriteLn('[Final response]:');
    WriteLn(Resp);
  finally
    Conn.Free;
    Grafo.Free;
  end;
end;

// =============================================================================
begin
  try
    WriteLn;
    WriteLn('════════════════════════════════════════════════════════════════');
    WriteLn('  Ch. 23 — Graph RAG: Supply chain');
    WriteLn('  Engine   : TAiRagGraph (MakerAI in-memory)');
    WriteLn('  Language: GQL — Graph Query Language (ExecuteMakerGQL)');
    WriteLn('════════════════════════════════════════════════════════════════');
    WriteLn;

    DemoGQL;
    WriteLn;

    if KeyPresente('OPENAI_API_KEY') then
      DemoLLM
    else
      WriteLn('SKIP B: OPENAI_API_KEY not configured.');

  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
    end;
  end;

  WriteLn;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
