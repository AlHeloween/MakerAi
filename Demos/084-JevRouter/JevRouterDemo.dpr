program JevRouterDemo;

// =============================================================================
// DEMO 084 - Route queries to specialized agents with Jev (TypeSafe AI)
// =============================================================================
// Jev does not generate text: it answers typed questions with calibrated
// probabilities. Here it decides, BEFORE spending an LLM, which specialized agent
// should handle each query and whether that agent needs its RAG version
// (slow, cites standards) or whether the fast one is enough.
//
// A single Jev call per query, with three question classes:
//   domain           Choice : which specialist (relative: which of all)
//   touches_<domain> Noul   : one per domain (absolute: detects queries
//                             that cross two areas, e.g. accounting+tax)
//   needs_sources    Noul   : whether a standard, rate or deadline must be cited
//
// The final decision is made by CODE (RouteQuery): thresholds, agent catalog and
// rules stay visible and can be changed without touching the questions.
//
// Block B shows the Choose and Noul shortcuts for a single question.
//
// Block C does the same INSIDE an agent graph: a node with
// TAiJevRouterTool writes the route to the blackboard and an lmConditional link
// follows it. OnRoute combines the route with the 'sources' flag to choose between
// the fast accounting agent and the normative one; low confidence falls to NextNo.
//
// Requires the TYPESAFE_API_KEY environment variable (https://console.typesafe.ai/keys).
// Cost: ~700 input tokens per query at US$0.042 per million.
//
// Usage modes:
//   JevRouterDemo.exe                         -> example queries
//   JevRouterDemo.exe "query 1" "query 2" -> your own queries
// =============================================================================

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.StrUtils,
  uMakerAi.Jev in '..\..\Source\Tools\uMakerAi.Jev.pas',
  uMakerAi.Agents,
  uMakerAi.Agents.Tools.JevRouter in '..\..\Source\Agents\uMakerAi.Agents.Tools.JevRouter.pas';

type
  TAgente = record
    Nombre: string;
    Dominio: string;
    ConRag: Boolean;
  end;

  // Framework events are 'of object': handlers live in a class
  TGrafoHandlers = class
  public
    // Agent node: in a real app the LLM would go here (with or without RAG)
    procedure AgenteExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
      Input: string; var Output: string);
    procedure FinExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
      Input: string; var Output: string);
    // accounting + high 'sources' flag -> accounting_normative; otherwise, accounting_fast
    procedure AjustarRuta(Sender: TObject; ANode: TAIAgentsNode;
      AResult: TAiJevResult; var ARoute: string);
  end;

const
  // What Jev reads to choose: descriptions as you would give them to a receptionist
  DOMINIOS: array[0..4] of string = (
    'contable=Accounting records: journal entries, PUC accounts, vouchers, reconciliations, financial statements, IFRS',
    'tributario=Taxes in Colombia: income tax, VAT, withholding at source, ICA, returns, DIAN, electronic invoicing',
    'legal=Commercial and civil law: contracts, companies, legal collection, lawsuits, liability',
    'laboral=Employee relations: payroll, social benefits, social security, employment contracts, dismissals',
    'general=Anything else: greetings, system usage, questions that are not from a specialized area');

  // Agent catalog: a domain can have a fast version (without RAG) and one with RAG
  AGENTES: array[0..5] of TAgente = (
    (Nombre: 'contable_rapido';    Dominio: 'contable';   ConRag: False),
    (Nombre: 'contable_normativo'; Dominio: 'contable';   ConRag: True),
    (Nombre: 'tributario';         Dominio: 'tributario'; ConRag: True),
    (Nombre: 'legal';              Dominio: 'legal';      ConRag: True),
    (Nombre: 'laboral';            Dominio: 'laboral';    ConRag: False),
    (Nombre: 'general';            Dominio: 'general';    ConRag: False));

  UMBRAL_DOMINIO = 0.5;  // below: it is not clear what it is about -> general
  UMBRAL_RAG     = 0.5;
  UMBRAL_CRUCE   = 0.7;  // another domain with high Noul -> composite query

  CONSULTAS_EJEMPLO: array[0..7] of string = (
    'Good morning, how do I change my system password?',
    'How do I record the September payroll payment?',
    'What does IAS 16 say about the useful life of assets?',
    'What is the withholding at source rate for fees for natural persons?',
    'A client has not paid an invoice from 8 months ago, what can I do?',
    'I sold a fixed asset at a profit, how do I record it and how much tax do I pay on the occasional gain?',
    'I am going to dismiss a worker without just cause, how much do I owe them?',
    'I got a strange error');

var
  TotalTokens: Int64 = 0;

function Clave(const AOpcion: string): string;
begin
  Result := AOpcion.Substring(0, AOpcion.IndexOf('='));
end;

function Descripcion(const AOpcion: string): string;
begin
  Result := AOpcion.Substring(AOpcion.IndexOf('=') + 1);
end;

// Questions are built once and reused for all queries
procedure ArmarPreguntas(AQ: TAiJevQuestions);
var
  D: string;
begin
  AQ.AddChoice('dominio', 'Que especialista debe responder `consulta`?', DOMINIOS);
  for D in DOMINIOS do
    if Clave(D) <> 'general' then
      AQ.AddNoul('toca_' + Clave(D), 'Responder `consulta` requiere conocimiento de este tema: ' +
        Descripcion(D) + '?');
  AQ.AddNoul('necesita_fuentes',
    'Responder bien `consulta` exige citar o verificar una norma, articulo, resolucion, tarifa, ' +
    'plazo o documento especifico, en lugar de explicar un concepto general?',
    'Depende de un texto normativo o documento concreto y vigente',
    'Se responde con conocimiento general o un procedimiento conocido');
end;

// Rules in code: easy to audit and change
procedure EnrutarConsulta(AJev: TAiJev; AQ: TAiJevQuestions; const AConsulta: string);
var
  State: TJSONObject;
  R: TAiJevResult;
  Dominio, Agente, Tambien, D: string;
  NecesitaRag: Boolean;
  i: Integer;
begin
  State := TJSONObject.Create;
  try
    State.AddPair('consulta', AConsulta);
    R := AJev.Ask(State, AQ);
  finally
    State.Free;
  end;
  try
    Inc(TotalTokens, R.InputTokens);

    Dominio := R['dominio'].Choice;
    if R['dominio'].Confidence < UMBRAL_DOMINIO then
      Dominio := 'general';
    NecesitaRag := R['necesita_fuentes'].Noul >= UMBRAL_RAG;

    // Domain agent: with RAG if needed and available; otherwise, whatever exists
    Agente := '';
    for i := Low(AGENTES) to High(AGENTES) do
      if (AGENTES[i].Dominio = Dominio) and (AGENTES[i].ConRag = NecesitaRag) then
        Agente := AGENTES[i].Nombre;
    if Agente = '' then
      for i := Low(AGENTES) to High(AGENTES) do
        if AGENTES[i].Dominio = Dominio then
        begin
          Agente := AGENTES[i].Nombre;
          if NecesitaRag and not AGENTES[i].ConRag then
            Agente := Agente + ' (pide fuentes y no tiene RAG)';
          Break;
        end;

    // Queries that cross domains
    Tambien := '';
    for D in DOMINIOS do
      if (Clave(D) <> 'general') and (Clave(D) <> Dominio) and
         (R['toca_' + Clave(D)].Noul >= UMBRAL_CRUCE) then
        Tambien := Tambien + ' ' + Clave(D);

    Writeln(AConsulta);
    Writeln(Format('  -> %s   (domain %s, confidence %.2f, needs sources %.2f)',
      [Agente, R['dominio'].Choice, R['dominio'].Confidence, R['necesita_fuentes'].Noul]));
    if Tambien <> '' then
      Writeln('     also consult:' + Tambien);
    Writeln('     alternatives: ' + string.Join(', ', R['dominio'].Top(3)));
    Writeln;
  finally
    R.Free;
  end;
end;

procedure BloqueAtajos(AJev: TAiJev);
var
  Conf, P: Double;
  Tarea: string;
begin
  Writeln('--- B. Shortcuts for a single question ---');
  Tarea := AJev.Choose('Traduce al ingles: la reunion se aplaza para el lunes',
    'Que tipo de tarea pide el texto?', ['conversacion', 'redaccion', 'codigo', 'analisis'], Conf);
  Writeln(Format('Choose -> %s (confidence %.2f)', [Tarea, Conf]));

  P := AJev.Noul('Mi pago lleva 3 dias fallando y necesito resolverlo hoy',
    'El mensaje expresa urgencia?');
  Writeln(Format('Noul   -> urgency %.2f', [P]));
  Writeln;
end;

{ TGrafoHandlers }

procedure TGrafoHandlers.AgenteExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
  Input: string; var Output: string);
begin
  Output := Format('%s handles: "%s"', [Node.Name, Input]);
end;

procedure TGrafoHandlers.FinExec(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink;
  Input: string; var Output: string);
begin
  Output := Input;
end;

procedure TGrafoHandlers.AjustarRuta(Sender: TObject; ANode: TAIAgentsNode;
  AResult: TAiJevResult; var ARoute: string);
begin
  if ARoute = 'contable' then
    if AResult['fuentes'].Noul >= UMBRAL_RAG then
      ARoute := 'contable_normativo'
    else
      ARoute := 'contable_rapido';
end;

// Block C: routing inside a graph. The Reception node has no
// OnExecute: its Tool (TAiJevRouterTool) writes 'next_route' and the link
// lmConditional follows it. No match or low confidence -> NextNo.
procedure BloqueGrafo(const AConsultas: array of string);
var
  Grafo: TAIAgentManager;
  Handlers: TGrafoHandlers;
  Router: TAiJevRouterTool;
  Targets: TDictionary<string, string>;
  D, C: string;
  i: Integer;
begin
  Writeln('--- C. The same routing inside an agent graph ---');
  Writeln;
  Grafo := TAIAgentManager.Create(nil);
  Handlers := TGrafoHandlers.Create;
  try
    Grafo.AddNode('Recepcion', nil).AddNode('humano', Handlers.AgenteExec).AddNode('Fin', Handlers.FinExec);
    for i := Low(AGENTES) to High(AGENTES) do
      Grafo.AddNode(AGENTES[i].Nombre, Handlers.AgenteExec);

    Router := TAiJevRouterTool.Create(Grafo);
    for D in DOMINIOS do
      Router.AddRoute(Clave(D), Descripcion(D));
    Router.AddFlag('fuentes', 'Answering `consulta` well requires citing a specific standard, article, rate or deadline?');
    // Same question as block A: the wording moves the confidence
    Router.Instructions := 'Which specialist should answer `consulta`?';
    Router.MinConfidence := UMBRAL_DOMINIO;
    Router.OnRoute := Handlers.AjustarRuta;
    Grafo.FindNode('Recepcion').Tool := Router;

    // Route key -> node. 'contable' does not appear: OnRoute converts it into
    // contable_rapido or contable_normativo.
    Targets := TDictionary<string, string>.Create;
    try
      for i := Low(AGENTES) to High(AGENTES) do
        Targets.Add(AGENTES[i].Nombre, AGENTES[i].Nombre);
      Grafo.AddConditionalEdge('Recepcion', 'Enrutador', Targets);
    finally
      Targets.Free;
    end;
    Grafo.FindNode('Recepcion').Next.NextNo := Grafo.FindNode('humano');
    for i := Low(AGENTES) to High(AGENTES) do
      Grafo.AddEdge(AGENTES[i].Nombre, 'Fin');
    Grafo.AddEdge('humano', 'Fin');
    Grafo.SetEntryPoint('Recepcion').SetFinishPoint('Fin');

    for C in AConsultas do
    begin
      // Run with seed: each query starts with a clean blackboard
      Grafo.Run(C, procedure(B: TAIBlackboard) begin end);
      while Grafo.Busy do
      begin
        CheckSynchronize;
        Sleep(20);
      end;
      CheckSynchronize;

      Writeln(Grafo.EndNode.Output);
      Writeln(Format('  route=%s  choice=%s  confidence=%s  sources=%s%s', [
        Grafo.Blackboard.GetString('next_route'),
        Grafo.Blackboard.GetString('Recepcion.jev.choice'),
        Grafo.Blackboard.GetString('Recepcion.jev.confidence'),
        Grafo.Blackboard.GetString('Recepcion.jev.fuentes'),
        IfThen(Grafo.Blackboard.GetString('Recepcion.jev.error') <> '',
          '  error=' + Grafo.Blackboard.GetString('Recepcion.jev.error'), '')]));
      Writeln;
    end;
  finally
    Grafo.Free;
    Handlers.Free;
  end;
end;

var
  Jev: TAiJev;
  Preguntas: TAiJevQuestions;
  i: Integer;
begin
  try
    if GetEnvironmentVariable('TYPESAFE_API_KEY') = '' then
    begin
      Writeln('Missing environment variable TYPESAFE_API_KEY (https://console.typesafe.ai/keys).');
      ExitCode := 2;
      Exit;
    end;

    Jev := TAiJev.Create(nil);
    Preguntas := TAiJevQuestions.Create(nil);
    try
      // Model queda en 'jev-1.13.0': los umbrales de arriba se calibran contra esa version
      ArmarPreguntas(Preguntas);

      Writeln('--- A. Route queries to specialized agents ---');
      Writeln;
      if ParamCount > 0 then
        for i := 1 to ParamCount do
          EnrutarConsulta(Jev, Preguntas, ParamStr(i))
      else
        for i := Low(CONSULTAS_EJEMPLO) to High(CONSULTAS_EJEMPLO) do
          EnrutarConsulta(Jev, Preguntas, CONSULTAS_EJEMPLO[i]);

      BloqueAtajos(Jev);

      Writeln(Format('Input tokens in block A: %d  (~US$%.5f)',
        [TotalTokens, TotalTokens * 0.042 / 1E6]));
      Writeln;

      if ParamCount > 0 then
      begin
        var Propias: TArray<string>;
        SetLength(Propias, ParamCount);
        for i := 1 to ParamCount do
          Propias[i - 1] := ParamStr(i);
        BloqueGrafo(Propias);
      end
      else
        BloqueGrafo(CONSULTAS_EJEMPLO);
    finally
      Preguntas.Free;
      Jev.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
