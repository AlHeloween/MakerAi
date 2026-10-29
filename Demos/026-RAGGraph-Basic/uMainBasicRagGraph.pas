unit uMainBasicRagGraph;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, System.JSON,

  uMakerAi.RAG.Graph.Core, uMakerAi.Embeddings.Core, uMakerAi.Embeddings, uMakerAi.Embeddings.Ollama, uMakerAi.Chat.Ollama, uMakerAi.RAG.Vectors.Index, uMakerAi.RAG.Vectors,

  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, uMakerAi.RAG.Graph.Builder;

type
  TForm20 = class(TForm)
    RAG: TAiRagGraph;
    AiOllamaEmbeddings1: TAiOllamaEmbeddings;
    BtnAddNodoManual: TButton;
    BtnBusquedaSemantica: TButton;
    BtnBusquedaEstructural: TButton;
    BtnBusquedaHibrida: TButton;
    GraphBuilder: TAiRagGraphBuilder;
    MemoJson: TMemo;
    BtnAddNodoFromJson: TButton;
    MemoContexto: TMemo;
    Button1: TButton;
    procedure BtnAddNodoManualClick(Sender: TObject);
    procedure BtnBusquedaSemanticaClick(Sender: TObject);
    procedure BtnBusquedaEstructuralClick(Sender: TObject);
    procedure BtnBusquedaHibridaClick(Sender: TObject);
    procedure BtnAddNodoFromJsonClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    Procedure ListarContenidoGrafo;
  public
    { Public declarations }
  end;

var
  Form20: TForm20;

implementation

{$R *.dfm}

procedure TForm20.BtnAddNodoFromJsonClick(Sender: TObject);
var
  JsonString: string;
begin
  // We assume the JSON above is in this variable
  JsonString := MemoJson.Lines.text;

  // The magic happens here:
  // 1. Parses the JSON.
  // 2. Checks whether the nodes "Steve Jobs" or "Apple" already exist (Identity Map).
  // 3. If they do not exist, creates them.
  // 4. If they have the "text" field, generates their vectors automatically (using Embeddings).
  // 5. Creates the "FOUNDED" relationship between them.

  GraphBuilder.Process(JsonString, msAddNewOnly);
  RAG.RebuildIndexes;

  ListarContenidoGrafo;
end;

procedure TForm20.BtnAddNodoManualClick(Sender: TObject);
var
  Steve, Apple: TAiRagGraphNode;
  Relacion: TAiRagGraphEdge;
begin
  // 1. Create the Nodes (Entities)
  // Syntax: AddNode(Unique_ID, Type_Label, Readable_Name)
  Steve := RAG.AddNode('id_001', 'PERSONA', 'Steve Jobs');

  // Opcional: Añadir propiedades de negocio (Metadatos)
  Steve.MetaData['nacimiento'] := 1955;
  Steve.MetaData['text'] := 'Steve Jobs, technology visionary and co-founder of Apple.';
  Steve.text := 'Steve Jobs, technology visionary and co-founder of Apple.'; // Information for the RAG


  Apple := RAG.AddNode('id_002', 'EMPRESA', 'Apple Inc.');
  Apple.MetaData['industry'] := 'Technology';
  Apple.text := 'Apple innovative technology company and creator of the IPhone';

  // 2. Create the SEMANTICS - the vector for RAG searches
  // Optional only if searching by RAG is required
  if Assigned(RAG.Embeddings) then
  Begin
    Steve.Data := RAG.Embeddings.CreateEmbedding(Steve.text, 'user');
    Apple.Data := RAG.Embeddings.CreateEmbedding(Apple.text, 'user');
  End;

  // 3. Create the Edge (Relationship)
  // Syntax: AddEdge(Source, Destination, Unique_ID, Verb_Label, Description)
  Relacion := RAG.AddEdge(Steve, Apple, 'edge_001', 'FOUNDED', 'was the founder of');

  // Optional: Qualify the relationship
  Relacion.MetaData['year'] := 1976;

  Relacion.Weight := 0.9; // Alta relevancia

  RAG.RebuildIndexes;

  ListarContenidoGrafo;
end;

procedure TForm20.BtnBusquedaEstructuralClick(Sender: TObject);
var
  Query: TGraphMatchQuery;
  // Patterns for: (Person) -[FOUNDED]-> (Company)
  P_Persona, P_Empresa: TMatchNodePattern;
  P_Relacion: TMatchEdgePattern;
begin
  Query := TGraphMatchQuery.Create;

  // We define the "Mold": We search for any PERSON...
  P_Persona := TMatchNodePattern.Create;
  P_Persona.Variable := 'p';
  P_Persona.NodeLabel := 'PERSONA';

  // ...que haya FUNDADO...
  P_Relacion := TMatchEdgePattern.Create;
  P_Relacion.EdgeLabel := 'FOUNDED';

  // ...cualquier EMPRESA.
  P_Empresa := TMatchNodePattern.Create;
  P_Empresa.Variable := 'c';
  P_Empresa.NodeLabel := 'EMPRESA';

  // We execute the pattern (p)-[r]->(c)
  Query.AddMatchClause(TMatchClause.Create('p', P_Relacion, 'c'));
  var
  Res := RAG.Match(Query);
end;

procedure TForm20.BtnBusquedaHibridaClick(Sender: TObject);
var
  Plan: TQueryPlan; // This plan is usually generated automatically by the LLM
begin
  // 1. ANCHOR (Vector): "Search for someone similar to 'The genius of Apple'"
  Plan.AnchorPrompt := 'The genius of Apple';
  Plan.AnchorVariable := 'fundador';

  // 2. NAVIGATION (Graph): "From there, search for which companies he founded"
  SetLength(Plan.Steps, 1);
  Plan.Steps[0].SourceVariable := 'fundador';
  Plan.Steps[0].EdgeLabel := 'FOUNDED';
  Plan.Steps[0].TargetVariable := 'empresa';

  Plan.ResultVariable := 'empresa';

  // Execution: Vector finds Steve -> Graph finds Pixar and Next.
  var
  Resultados := RAG.Query(Plan);

end;

procedure TForm20.BtnBusquedaSemanticaClick(Sender: TObject);
var
  Resultados: TArray<TAiRagGraphNode>;
  Prompt, Res: String;
  Depth, Limit: Integer;
  ShowProperties: Boolean;
  Precision: Double;
begin
  // The user searches for a concept, NOT an exact name.
  // In the DB there is no node called "Creator of the iPhone",
  // but the vector will find "Steve Jobs" by his description.

  Prompt := 'Fundador';

  Depth := 0;
  Limit := 5;
  Precision := 0.1;
  ShowProperties := True;

  Resultados := RAG.Search(Prompt, Depth, Limit, Precision);

  // Form 1: traverse the result and build the personalized response
  For var Node in Resultados do
  Begin
    Res := Res + sLineBreak + Node.text;
  End;

  // Form 2: get the response organized by the component
  Res := RAG.SearchText(Prompt, Depth, ShowProperties, Limit, Precision);

  MemoContexto.Lines.text := Res;
end;

procedure TForm20.Button1Click(Sender: TObject);
begin
  RAG.SaveToFile('c:\temp\grafo.txt', TGraphExportFormat.gefGraphMkai, True);
end;

procedure TForm20.ListarContenidoGrafo;
var
  Graph: TAiRagGraph;
  EdgeNode: TAiEmbeddingNode;
  Edge: TAiRagGraphEdge;
  TripletList: TStringList;
  Subject, Predicate, Obj: string;
begin
  // 1. Make sure the graph is assigned
  Graph := RAG;
  if not Assigned(Graph) then
  begin
    ShowMessage('The graph component (RAG) is not assigned.');
    Exit;
  end;

  // 2. Use a TStringList to collect and sort the triplets
  TripletList := TStringList.Create;
  try
    // 3. Iterar sobre todas las aristas del grafo
    // Graph.Edges returns a TAiRAGVector, and its Items property is a list of the embedding nodes (in this case, the edges)
    for EdgeNode in Graph.Edges.Items do
    begin
      // Make sure the element is really an edge
      if EdgeNode is TAiRagGraphEdge then
      begin
        Edge := EdgeNode as TAiRagGraphEdge;

        // 4. Format the triplet in a readable format
        Subject := Format('%s (%s)', [Edge.FromNode.Name, Edge.FromNode.NodeLabel]);
        Predicate := Edge.EdgeLabel;
        Obj := Format('%s (%s)', [Edge.ToNode.Name, Edge.ToNode.NodeLabel]);

        // Add the formatted triplet to the list
        TripletList.Add(Format('%-35s --[%s]--> %s', [Subject, Predicate, Obj]));
      end;
    end;

    // 5. Sort the list so it is easier to read
    TripletList.Sort;

    // 6. Show the results in the TMemo
    MemoContexto.Lines.Clear;
    MemoContexto.Lines.Add(Format('--- %d triplets were found in the graph ---', [TripletList.Count]));
    MemoContexto.Lines.Add('');
    MemoContexto.Lines.AddStrings(TripletList);

  finally
    TripletList.Free;
  end;

end;

end.
