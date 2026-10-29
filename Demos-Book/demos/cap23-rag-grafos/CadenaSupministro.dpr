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
  uMakerAi.Chat.OpenAi;  // auto-registra driver 'OpenAI' en el factory

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
  NodoFabrica := Grafo.AddNode('fab:fabrica_norte', 'fabricante',  'Fábrica Norte');

  // ── Products ─────────────────────────────────────────────────────────────
  NodoWidgetPro := Grafo.AddNode('prod:widget_pro', 'producto',    'Widget Pro');
  NodoCompA     := Grafo.AddNode('prod:comp_a',     'producto',    'Componente A');

  // ── Distributors ────────────────────────────────────────────────────────
  NodoDN := Grafo.AddNode('dist:dist_norte', 'distribuidor', 'Distribuidor Norte');
  NodoDS := Grafo.AddNode('dist:dist_sur',   'distribuidor', 'Distribuidor Sur');

  // ── Customers ──────────────────────────────────────────────────────────────
  NodoEmpABC := Grafo.AddNode('cli:empresa_abc', 'cliente', 'Empresa ABC');
  NodoEmpXYZ := Grafo.AddNode('cli:empresa_xyz', 'cliente', 'Empresa XYZ');

  // ── Supply edges ─────────────────────────────────────────────────────────
  Grafo.AddEdge(NodoMateria, NodoFabrica, 'sum:1', 'PROVEE', 'MateriaSAS provee Fábrica Norte');
  Grafo.AddEdge(NodoTech,    NodoFabrica, 'sum:2', 'PROVEE', 'TechParts provee Fábrica Norte');

  // ── Manufacturing edges ────────────────────────────────────────────────
  Grafo.AddEdge(NodoFabrica, NodoWidgetPro, 'fab:1', 'FABRICA', 'Fábrica Norte fabrica Widget Pro');
  Grafo.AddEdge(NodoFabrica, NodoCompA,     'fab:2', 'FABRICA', 'Fábrica Norte fabrica Componente A');

  // ── Distribution edges ───────────────────────────────────────────────
  Grafo.AddEdge(NodoDN, NodoWidgetPro, 'dis:1', 'DISTRIBUYE', 'Dist Norte distribuye Widget Pro');
  Grafo.AddEdge(NodoDS, NodoWidgetPro, 'dis:2', 'DISTRIBUYE', 'Dist Sur distribuye Widget Pro');

  // ── Purchase edges ─────────────────────────────────────────────────────
  Grafo.AddEdge(NodoEmpABC, NodoDN, 'com:1', 'COMPRA_DE', 'Empresa ABC compra de Dist Norte');
  Grafo.AddEdge(NodoEmpXYZ, NodoDS, 'com:2', 'COMPRA_DE', 'Empresa XYZ compra de Dist Sur');

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
    WriteLn('▶ Which products Fábrica Norte manufactures:');
    Resultado := Grafo.ExecuteMakerGQL(
      'MATCH (f:fabricante)-[FABRICA]->(p:producto) RETURN p');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ Shortest path: supplier → customer:');
    Resultado := Grafo.ExecuteMakerGQL(
      'SHORTEST PATH (s:proveedor) TO (c:cliente)');
    WriteLn(Resultado);

    WriteLn;
    WriteLn('▶ Direct neighbors of Empresa ABC (GetNeighbors method):');
    Nodo    := Grafo.FindNodeByID('cli:empresa_abc');
    Vecinos := Grafo.GetNeighbors(Nodo, gdBoth);
    for N in Vecinos do
      WriteLn('   → [', N.NodeLabel, '] ', N.Name);

    WriteLn;
    WriteLn(Format('Grafo: %d nodos, %d aristas',
      [Grafo.NodeCount, Grafo.EdgeCount]));

    // Guardar para uso en sección B
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
  PREGUNTA = '¿Qué proveedores abastecen a Fábrica Norte y qué productos fabrica?';
  ESQUEMA  =
    'Labels (nodos): proveedor, fabricante, producto, distribuidor, cliente' + sLineBreak +
    'Edges (aristas): PROVEE, FABRICA, DISTRIBUYE, COMPRA_DE' + sLineBreak +
    'Propiedad de nodo: name (string), ej: name = ''Fábrica Norte''' + sLineBreak +
    'Sintaxis: MATCH (a:label)-[r:EDGE]->(b:label) WHERE a.name = ''valor'' RETURN a, r, b';
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

    // Paso 1 — El LLM genera la consulta GQL
    Conn.SystemPrompt.Text :=
      'Eres un experto en GQL (Graph Query Language) de MakerAI.' + sLineBreak +
      'Esquema del grafo:' + sLineBreak + ESQUEMA + sLineBreak +
      'REGLAS ESTRICTAS:' + sLineBreak +
      '- Genera UNA SOLA consulta MATCH en una sola línea.' + sLineBreak +
      '- Usa WHERE para filtrar por name: WHERE b.name = ''Fábrica Norte''' + sLineBreak +
      '- Devuelve solo la consulta GQL, sin explicaciones.';

    GQLQuery := Conn.AddMessageAndRun(PREGUNTA, 'user', []).Trim;
    // Quitar markdown code fences si el modelo las incluyó (ej: ```gql...```)
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

    // Paso 2 — Ejecutar la consulta en el grafo local
    Contexto := Grafo.ExecuteMakerGQL(GQLQuery);
    WriteLn('[Graph context]: ', Contexto);
    WriteLn;

    // Paso 3 — El LLM sintetiza la respuesta final
    Conn.NewChat;
    Conn.SystemPrompt.Text :=
      'Eres un asistente de análisis de cadena de suministro. ' +
      'Responde en español de forma clara y concisa, usando solo los datos del grafo proporcionados.';

    Resp := Conn.AddMessageAndRun(
      PREGUNTA + #13#10 +
      'Datos del grafo de conocimiento:' + #13#10 + Contexto,
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
