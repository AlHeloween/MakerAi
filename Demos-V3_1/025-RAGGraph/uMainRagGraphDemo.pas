// IT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// o use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// HE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enriquez
// Social networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMainRagGraphDemo;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.JSON,
  System.Generics.Collections, System.Rtti,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation, FMX.StdCtrls,
  FMX.Memo.Types, FMX.ScrollBox, FMX.Memo, uMakerAi.Embeddings.Core,

  uMakerAi.RAG.Graph.Core, uMakerAi.RAG.Graph.Builder, uMakerAi.RAG.Graph.Driver.Postgres,
  uMakerAI.RAG.Vectors.Index, uMakerAI.RAG.MetaData,
  uMakerAi.Embeddings, uMakerAi.Chat.OpenAi, uMakerAi.RAG.Vectors, FMX.Edit, uMakerAi.Prompts,
  uMakerAi.Chat.AiConnection, uMakerAi.Chat, uMakerAi.Core, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  uMakerAi.Chat.Gemini, uMakerAi.Chat.Initializations, uMakerAi.Chat.Messages, uMakerAi.Chat.Ollama,


  FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.UI.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Phys, FireDAC.Phys.PGDef, FireDAC.FMXUI.Wait,
  FireDAC.Comp.UI, FireDAC.Phys.PG, Data.DB, FireDAC.Comp.Client, FireDAC.Comp.DataSet, FMX.Objects, FMX.Layouts, FMX.TabControl,
  FMX.ListBox, FMX.EditBox, FMX.SpinBox, FMX.SearchBox, uMakerAi.Embeddings.Ollama;

type

  TAiRagGraphNodeHacker = class helper for TAiRagGraphNode
  public
    procedure InternalAddOutgoingEdge(AEdge: TAiRagGraphEdge);
    procedure InternalAddIncomingEdge(AEdge: TAiRagGraphEdge);
  end;

  TMainRagGraphDemo = class(TForm)
    RAG: TAiRagGraph;
    AiConn: TAiChatConnection;
    AiPrompts1: TAiPrompts;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    DbConn: TFDConnection;
    MainLayout: TLayout;
    RAGBuilder1: TAiRagGraphBuilder;
    Layout1: TLayout;
    Button1: TButton;
    Image1: TImage;
    BtnSave: TButton;
    Image2: TImage;
    BtnLoad: TButton;
    Image3: TImage;
    TabControl1: TTabControl;
    TabSearch: TTabItem;
    TabAddItems: TTabItem;
    Layout2: TLayout;
    ChDetailed: TCheckBox;
    EditDepth: TEdit;
    EditLimit: TEdit;
    EditPrecision: TEdit;
    Label1: TLabel;
    label12: TLabel;
    Label2: TLabel;
    Layout3: TLayout;
    Label3: TLabel;
    MemoPrompt: TMemo;
    Layout4: TLayout;
    Label4: TLabel;
    MemoResultados: TMemo;
    Splitter1: TSplitter;
    Layout5: TLayout;
    Label5: TLabel;
    MemoToProcess: TMemo;
    Layout6: TLayout;
    Label6: TLabel;
    MemoProcessOut: TMemo;
    Splitter2: TSplitter;
    Layout7: TLayout;
    BtnAddNodos: TButton;
    Image5: TImage;
    BtnMatch: TButton;
    Image6: TImage;
    BtnConsultaQueryLLM: TButton;
    Image7: TImage;
    BtnBusquedaRAG: TButton;
    Image4: TImage;
    TabMatch: TTabItem;
    Layout8: TLayout;
    Layout9: TLayout;
    cbDirection: TComboBox;
    Label7: TLabel;
    cbStartNodeLabel: TComboBox;
    cbTargetNodeLabel: TComboBox;
    cbEdgeLabel: TComboBox;
    Label8: TLabel;
    Label9: TLabel;
    Label10: TLabel;
    edtStartNodeName: TEdit;
    Label11: TLabel;
    BtnInitMatch: TButton;
    BtnListTriplets: TButton;
    popSuggestions: TPopup;
    lbSuggestions: TListBox;
    numDepth: TSpinBox;
    chMatchShowProperties: TCheckBox;
    RAGPgDriver: TAiRagGraphPostgresDriver;
    Label13: TLabel;
    Layout10: TLayout;
    Layout11: TLayout;
    Splitter4: TSplitter;
    Label14: TLabel;
    lbQuerySteps: TListBox;
    Layout13: TLayout;
    BtnClear: TButton;
    btnAddStep: TButton;
    btnSearch: TButton;
    GroupBox1: TGroupBox;
    BtnUseInMemoryData: TSpeedButton;
    BtnUseDataBase: TSpeedButton;
    Image9: TImage;
    Image8: TImage;
    BtnLoadText: TButton;
    Image10: TImage;
    Label16: TLabel;
    BtnCrearRepositorio: TButton;
    AiOllamaEmbeddings1: TAiOllamaEmbeddings;
    Layout12: TLayout;
    Layout14: TLayout;
    Label15: TLabel;
    MemoResults: TMemo;
    Layout15: TLayout;
    Label17: TLabel;
    Splitter3: TSplitter;
    Layout16: TLayout;
    Layout17: TLayout;
    MemoMakerGQL: TMemo;
    BtnExecuteMakerGQL: TButton;
    Image11: TImage;
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnLoadClick(Sender: TObject);
    procedure BtnBusquedaRAGClick(Sender: TObject);
    procedure BtnAddNodosClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure RagGraphAddEdge(Sender: TObject; AEdge: TAiRagGraphEdge; var Handled: Boolean);
    procedure RagGraphAddNode(Sender: TObject; ANode: TAiRagGraphNode; var Handled: Boolean);
    procedure RagGraphDeleteEdge(Sender: TObject; const AEdgeID: string; var Handled: Boolean);
    procedure RagGraphDeleteNode(Sender: TObject; const ANodeID: string; var Handled: Boolean);
    procedure RagGraphFindNodeByID(Sender: TObject; const ANodeID: string; out ANodeData: TNodeDataRecord; var Found: Boolean);
    procedure RagGraphLoad(Sender: TObject; Graph: TAiRagGraph; var Handled: Boolean);
    procedure RagGraphQuery(Sender: TObject; const APlan: TQueryPlan; ADepth, ALimit: Integer; APrecision: Double; ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
    procedure RagGraphSearchNodes(Sender: TObject; const APrompt: string; ADepth, ALimit: Integer; APrecision: Double; out ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
    procedure BtnConsultaQueryLLMClick(Sender: TObject);
    procedure BtnMatchClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure btnAddStepClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure btnSearchClick(Sender: TObject);
    procedure BtnInitMatchClick(Sender: TObject);
    procedure BtnListTripletsClick(Sender: TObject);
    procedure edtStartNodeNameChangeTracking(Sender: TObject);
    procedure lbSuggestionsItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
    procedure cbStartNodeLabelChange(Sender: TObject);
    procedure edtStartNodeNameExit(Sender: TObject);
    procedure RagGetUniqueNodeLabels(Sender: TObject; Graph: TAiRagGraph; var ResultLabels: TArray<System.string>; var Handled: Boolean);
    procedure RagGetUniqueEdgeLabels(Sender: TObject; Graph: TAiRagGraph; var ResultLabels: TArray<System.string>; var Handled: Boolean);
    procedure RagFindNodeByName(Sender: TObject; Graph: TAiRagGraph; const AName, ANodeLabel: string; var ResultNode: TAiRagGraphNode; var Handled: Boolean);
    procedure RagFindNodesByProperty(Sender: TObject; Graph: TAiRagGraph; const AKey: string; const AValue: Variant; var ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
    procedure RagFindNodesByLabel(Sender: TObject; Graph: TAiRagGraph; const ALabel: string; var ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
    procedure RagGraphFindEdgeByID(Sender: TObject; const AEdgeID: string; out AEdgeData: TEdgeDataRecord; var Found: Boolean);
    procedure RagGetNodeEdges(Sender: TObject; ANode: TAiRagGraphNode; var Handled: Boolean);
    procedure RagFindNodeNamesByLabel(Sender: TObject; const ANodeLabel, ASearchText: string; ALimit: Integer; out ResultNames: TArray<System.string>; var Handled: Boolean);
    procedure BtnUseDataBaseClick(Sender: TObject);
    procedure BtnUseInMemoryDataClick(Sender: TObject);
    procedure BtnLoadTextClick(Sender: TObject);
    procedure BtnCrearRepositorioClick(Sender: TObject);
    procedure BtnExecuteMakerGQLClick(Sender: TObject);
  private
    FCurrentEntidad: String;

    // Variables for match searches
    FCurrentQuery: TGraphMatchQuery;
    FNodeVarCounter: Integer;

    Function NewQuery: TFDQuery;
    function EmbeddingToString(const AData: TAiEmbeddingData): string;
    function PropertiesToJSONString(const AProperties: TAiEmbeddingMetaData): string;
    function HydrateNodeFromQuery(AQuery: TFDQuery; AGraph: TAiRagGraph): TAiRagGraphNode;

    procedure MatchBuilder_PopulateComboBoxes;
    function MatchBuilder_GetNextNodeVar: string;
    procedure MatchBuilder_UpdateQueryVisualizer;
    procedure MatchBuilder_PopulateSuggestions(const SearchText: string);
    procedure MatchBuilder_DisplayMatchResults(const AResults: TArray<TDictionary<string, TObject>>; AShowProperties: Boolean);
    procedure MatchBuilder_DisplaySubgraphResults(const AResults: TArray<TDictionary<string, TObject>>; AShowProperties: Boolean);
    procedure MatchBuilder_DisplayProperties(AProperties: TAiEmbeddingMetaData; AOutput: TStrings; const AIndentation: string);

  public
    function ParseJsonToQueryPlan(const AJSONString: string): TQueryPlan;
  end;

var
  MainRagGraphDemo: TMainRagGraphDemo;

implementation

{$R *.fmx}

procedure TMainRagGraphDemo.BtnAddNodosClick(Sender: TObject);
Var
  Ent, Prompt, Res: String;
  Msg: TAiChatMessage;
  MF: TAiMediaFile;
begin
  Ent := Trim(MemoToProcess.Lines.Text);

  If Ent = '' then
    Raise Exception.Create('First add the text to process in the memo and then press the button to create the graph');

  Prompt := AiPrompts1.GetTemplate('CreaJSonFromTexto', ['texto=' + Ent]);
  // Memo1.Lines.Text := Prompt;

  AiConn.ModelConfig.SessionCaps := AiConn.ModelConfig.SessionCaps + [cap_ExtractCode];
  AiConn.Params.Values['Max_Tokens'] := '16000';

  Res := AiConn.AddMessageAndRun(Prompt, 'user', []);

  RAGBuilder1.Process(Res);
  RAG.RebuildIndexes;

  Exit;

  Msg := AiConn.GetLastMessage;

  MemoProcessOut.Lines.Add('');
  MemoProcessOut.Lines.Add('');
  // Memo1.Lines.Add(Res);

  { If Msg.MediaFiles.Count > 0 then
    Begin
    For MF in Msg.MediaFiles do
    Begin
    MemoProcessOut.Lines.Add('');
    MemoProcessOut.Lines.Add('');
    MemoProcessOut.Lines.Add(MF.ToString);
    RAGBuilder1.Process(MF.ToString);
    RAG.RebuildIndexes;
    End;
    ShowMessage('The json was stored correctly - Nodes:' + RAG.NodeCount.ToString);
    End
    Else
    ShowMessage('Error storing the Json');
  }
end;

procedure TMainRagGraphDemo.btnAddStepClick(Sender: TObject);
var
  SourceVar, TargetVar: string;
  SourcePattern, TargetPattern: TMatchNodePattern;
  EdgePattern: TMatchEdgePattern;
begin
  // If it is the first step, we use the anchor
  if FCurrentQuery.MatchClauses.Count = 0 then
  begin
    // Create the source node (anchor)
    SourceVar := MatchBuilder_GetNextNodeVar; // n0
    SourcePattern := TMatchNodePattern.Create;
    SourcePattern.Variable := SourceVar;
    SourcePattern.NodeLabel := cbStartNodeLabel.Text;
    if Trim(edtStartNodeName.Text) <> '' then
      SourcePattern.Properties.Add('name', edtStartNodeName.Text);
    FCurrentQuery.AddNodePattern(SourcePattern);
  end
  else
  begin
    // Otherwise, the source is the destination of the previous step
    SourceVar := FCurrentQuery.MatchClauses.Last.TargetNodeVar;
  end;

  // Create the destination node for this step
  TargetVar := MatchBuilder_GetNextNodeVar; // n1, n2, ...
  TargetPattern := TMatchNodePattern.Create;
  TargetPattern.Variable := TargetVar;
  TargetPattern.NodeLabel := cbTargetNodeLabel.Text;
  FCurrentQuery.AddNodePattern(TargetPattern);

  // Create the edge pattern
  EdgePattern := TMatchEdgePattern.Create;
  EdgePattern.Variable := 'e' + IntToStr(FCurrentQuery.MatchClauses.Count);
  EdgePattern.EdgeLabel := cbEdgeLabel.Text;
  case cbDirection.ItemIndex of
    0:
      EdgePattern.Direction := gdOutgoing;
    1:
      EdgePattern.Direction := gdIncoming;
    2:
      EdgePattern.Direction := gdBoth;
  end;

  // Add the clause to the query
  FCurrentQuery.AddMatchClause(TMatchClause.Create(SourceVar, EdgePattern, TargetVar));

  // Update the visualization
  MatchBuilder_UpdateQueryVisualizer;
end;

procedure TMainRagGraphDemo.BtnBusquedaRAGClick(Sender: TObject);
Var
  Prompt, Res: String;
  Depth, Limit: Integer;
  Precision: Single;
  Detailed: Boolean;
  AFilter: TAiFilterCriteria;
begin
  Prompt := MemoPrompt.Lines.Text;
  Depth := StrToIntDef(EditDepth.Text, 0);
  Detailed := ChDetailed.IsChecked;
  Limit := StrToIntDef(EditLimit.Text, 5);
  Precision := StrToFloatDef(EditPrecision.Text, 0.5);

  // --- optional: you can filter first to reduce the number of records ----
  AFilter := TAiFilterCriteria.Create;
  AFilter.AddEqual('empresa','APPLE');

  // we are not passing filters for now
  AFilter := Nil;

  //RAG.Search(Prompt, Depth, Limit, Precision, AFilter);

  Res := RAG.SearchText(Prompt, Depth, Detailed, Limit, Precision, AFilter);
  // -- Filter first before searching
  // -- Search by embedding
  // -- Lexical search = Word similarity
  // -- Mix the two results and categorize them
  // -- Reorder to avoid positional bias

  MemoResultados.Lines.Add(Res);
end;

procedure TMainRagGraphDemo.BtnClearClick(Sender: TObject);
Begin
  // Free the current query and create a new one
  FCurrentQuery.Free;
  FCurrentQuery := TGraphMatchQuery.Create;
  FNodeVarCounter := 0;

  // Clear the UI
  lbQuerySteps.Clear;
  MemoResults.Lines.Clear;
end;

procedure TMainRagGraphDemo.BtnConsultaQueryLLMClick(Sender: TObject);
var
  Ent, Prompt, Res, JSonPlanStr: String;
  Msg: TAiChatMessage;
  Plan: TQueryPlan;
  Results: TArray<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
  Log: TStringList;

  Depth, Limit: Integer;
  Precision: Single;
  Detailed: Boolean;
  PropPair: TPair<string, Variant>;
begin
{  Depth := StrToIntDef(EditDepth.Text, 0);
  Detailed := ChDetailed.IsChecked;
  Limit := StrToIntDef(EditLimit.Text, 5);
  Precision := StrToFloatDef(EditPrecision.Text, 0.5);

  Log := TStringList.Create;
  try
    Try
      Self.Cursor := crHourGlass; // Change the cursor to indicate that work is in progress

      // --- Step 1: Get the user query and build the prompt for the LLM ---
      Ent := MemoPrompt.Lines.Text;
      if Trim(Ent) = '' then
      begin
        ShowMessage('Please enter a query.');
        Exit;
      end;

      Log.Add('User query: "' + Ent + '"');
      Log.Add('');

      Prompt := AiPrompts1.GetTemplate('CreaJSonQueryPlan', ['texto=' + Ent]);

      // --- Step 2: Call the LLM to generate the JSON query plan ---
      // Your configuration to force the output of a text file is excellent.
      AiConn.ModelConfig.SessionCaps := AiConn.ModelConfig.SessionCaps + [cap_ExtractCode];
      Res := AiConn.AddMessageAndRun(Prompt, 'user', []);
      Msg := AiConn.GetLastMessage;

      // --- Step 3: Parse the JSON and execute the query ---
      if (Msg.MediaFiles = nil) or (Msg.MediaFiles.Count = 0) then
      begin
        ShowMessage('The LLM did not return a structured query plan.');
        Exit;
      end;

      // We assume the LLM returns a single file with the plan
      JSonPlanStr := Msg.MediaFiles[0].ToString;
      Log.Add('JSON plan received from the LLM:');
      Log.Add(JSonPlanStr);
      Log.Add('');

      Plan := ParseJsonToQueryPlan(JSonPlanStr);

      // Basic verification that the plan is valid
      if (Plan.AnchorPrompt <> '') and (Plan.AnchorVariable <> '') then
      begin
        // ---- START OF COMPLETED BLOCK ----

        Log.Add('Executing the query plan...');

        // Execute the query in the RAG component using the plan
        // We use default values for depth, limit and precision for now.
        Results := RAG.Query(Plan, Depth, Limit, Precision);

        // Format and display the results
        Log.Add('');
        Log.Add('--- Query Results ---');
        if Length(Results) > 0 then
        begin
          for Node in Results do
          begin
            Log.Add('  - ' + Node.Name + ' (Type: ' + Node.NodeLabel + ')');

            if Detailed and (Node.Properties <> nil) and (Length(Node.Properties) > 0) then
            begin
              Log.Add('  Entity properties:');
              for PropPair in Node.Properties do
              begin
                Log.Add('    • ');
                Log.Add(PropPair.Key);
                Log.Add(': ');
                try
                  Log.Add(VarToStr(PropPair.Value));
                except
                  Log.Add('<unreadable value>');
                end;
              end;
            end;
          end;
        end
        else
        begin
          Log.Add('(No results were found matching the query plan)');
        end;
      end
      else
      begin
        Log.Add('The query plan received from the LLM is invalid or incomplete.');
      end;

      MemoResultados.Lines.Assign(Log);

    except
      on E: Exception do
        ShowMessage('An error occurred during the process: ' + E.Message);
    end;
  finally
    Log.Free;
    Self.Cursor := crDefault; // Restore the cursor
  end;
}
End;

procedure TMainRagGraphDemo.BtnCrearRepositorioClick(Sender: TObject);
begin
  RAGPgDriver.TableName := 'graph_';
  RAGPgDriver.CurrentEntidad := 'DEFAULT';
  RAGPgDriver.CreateSchema('graph_', 1024);
  ShowMessage('The rag table was created');
end;

procedure TMainRagGraphDemo.BtnExecuteMakerGQLClick(Sender: TObject);
var
  Results: TArray<TDictionary<string, TObject>>;
  Depth: Integer;
begin
  // 1. Interface configuration
  Depth := Round(numDepth.Value);
  MemoResults.Lines.Clear;
  MemoResults.Lines.Add('Executing MakerGQL query...');
  Application.ProcessMessages;

  try
    // 2. Direct execution through the RAG component
    RAG.ExecuteMakerGQL(MemoMakerGQL.Lines.Text, Results, Depth);

    // 3. Results visualization
    MemoResults.Lines.Add(Format('Found %d matches.', [Length(Results)]));
    MemoResults.Lines.Add('----------------------------------');

    if Length(Results) > 0 then
    begin
      if Depth = 0 then
        MatchBuilder_DisplayMatchResults(Results, chMatchShowProperties.IsChecked)
      else
        MatchBuilder_DisplaySubgraphResults(Results, chMatchShowProperties.IsChecked);
    end
    else
      MemoResults.Lines.Add('The query returned no results.');

  except
    on E: Exception do
    begin
      // We capture any error (syntax or execution) that occurs inside ExecuteMakerGQL
      MemoResults.Lines.Add('*** QUERY ERROR ***');
      MemoResults.Lines.Add(E.Message);
    end;
  end;
end;

procedure TMainRagGraphDemo.BtnInitMatchClick(Sender: TObject);
begin
  FCurrentQuery := TGraphMatchQuery.Create;
  FNodeVarCounter := 0;

  // Populate the ComboBoxes with graph data
  MatchBuilder_PopulateComboBoxes;
end;

procedure TMainRagGraphDemo.BtnListTripletsClick(Sender: TObject);
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
    // 3. Iterate over all edges of the graph
    // Graph.Edges returns a TAiRAGVector, and its Items property is a list of embedding nodes (in this case, the edges)
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

    // 5. Sort the list to make it easier to read
    TripletList.Sort;

    // 6. Display the results in the TMemo
    MemoResults.Lines.Clear;
    MemoResults.Lines.Add(Format('--- %d triplets found in the graph ---', [TripletList.Count]));
    MemoResults.Lines.Add('');
    MemoResults.Lines.AddStrings(TripletList);

  finally
    TripletList.Free;
  end;
end;

procedure TMainRagGraphDemo.BtnLoadClick(Sender: TObject);
var
  St: TMemoryStream;
begin
  OpenDialog1.Filter := 'MakerAi Graph (*.mkai)|*.mkai';
  OpenDialog1.DefaultExt := '.mkai';
  OpenDialog1.FilterIndex := 1;
  OpenDialog1.InitialDir := 'c:\temp\';

  if OpenDialog1.Execute then
  begin
    St := TMemoryStream.Create;
    try
      St.LoadFromFile(OpenDialog1.FileName);
      St.Position := 0;
      RAG.LoadFromStream(St);
      SaveDialog1.FileName := OpenDialog1.FileName;
    finally
      St.Free;
    end;
  end;
end;

procedure TMainRagGraphDemo.BtnMatchClick(Sender: TObject);
begin
  TabControl1.ActiveTab := TabMatch;
end;

procedure TMainRagGraphDemo.BtnSaveClick(Sender: TObject);
begin
  // --- Configure the save dialog ---
  SaveDialog1.Title := 'Save Knowledge Graph';
  SaveDialog1.InitialDir := 'c:\temp\';

  // Configure the filters. The first line is the one selected by default.
  SaveDialog1.Filter := 'MakerAI Graph (*.mkai)|*.mkai|' + // Formato nativo (completo o ligero)
    'GraphML File (*.graphml)|*.graphml|' + // For Gephi, yEd
    'Graphviz DOT File (*.dot)|*.dot|' + // For Graphviz
    'JSON Graph (Legacy) (*.json)|*.json|' + // Si quieres mantener compatibilidad
    'All files (*.*)|*.*';

  // Set the default extension that will be added if the user does not type one.
  SaveDialog1.DefaultExt := '.mkai';
  SaveDialog1.FileName := 'my_knowledge_graph'; // Suggested file name

  // --- Execute the dialog and save ---
  if SaveDialog1.Execute then
  begin
    try
      // Option A: Always full save.
      // RAG.SaveToFile(SaveDialog1.FileName, True);

      var
      SaveWithEmbeddings := MessageDlg('Do you want to include the embedding data in the file?' + sLineBreak + '(The file will be much larger)', TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrYes;
      RAG.SaveToFile(SaveDialog1.FileName, SaveWithEmbeddings);

      // For now, let's use Option A for simplicity.
      // RAG.SaveToFile(SaveDialog1.FileName, True);

      // Inform the user (optional but recommended)
      ShowMessage('Graph saved successfully at: ' + SaveDialog1.FileName);

      // Update the open dialog for convenience
      OpenDialog1.FileName := SaveDialog1.FileName;
    except
      on E: Exception do
      begin
        ShowMessage('Error saving the graph: ' + E.Message);
      end;
    end;
  end;
end;

procedure TMainRagGraphDemo.btnSearchClick(Sender: TObject);
var
  Results: TArray<TDictionary<string, TObject>>;
  Depth: Integer;
begin
  if FCurrentQuery.MatchClauses.Count = 0 then
  begin
    ShowMessage('Please add at least one step to the query.');
    Exit;
  end;

  Depth := Round(numDepth.Value); // Get the value from the depth control

  MemoResults.Lines.Clear;
  MemoResults.Lines.Add('Executing query...');
  Application.ProcessMessages;

  Results := RAG.Match(FCurrentQuery, Depth);

  MemoResults.Lines.Clear;
  MemoResults.Lines.Add(Format('Found %d matches.', [Length(Results)]));
  MemoResults.Lines.Add('----------------------------------');

  if Length(Results) > 0 then
  begin
    // The display code must now differentiate between the Match result and the subgraph
    if Depth = 0 then
      MatchBuilder_DisplayMatchResults(Results, chMatchShowProperties.IsChecked) // A new method to display Match results
    else
      MatchBuilder_DisplaySubgraphResults(Results, chMatchShowProperties.IsChecked); // A new method to display the subgraph
  end;
end;

procedure TMainRagGraphDemo.BtnUseDataBaseClick(Sender: TObject);
begin
  RAG.Driver := RAGPgDriver;
  RAG.Clear;
  BtnSave.Enabled := False;
  BtnLoad.Enabled := False;
  ShowMessage('Now the Graph work with DataBase data');
end;

procedure TMainRagGraphDemo.BtnUseInMemoryDataClick(Sender: TObject);
begin
  RAG.Driver := Nil;
  RAG.Clear;
  BtnSave.Enabled := True;
  BtnLoad.Enabled := True;
  ShowMessage('Now the Graph work with memory data');
end;

procedure TMainRagGraphDemo.Button1Click(Sender: TObject);
begin
  RAG.Clear;
  MemoToProcess.Lines.Clear;
  MemoProcessOut.Lines.Clear;
  MemoResultados.Lines.Clear;
  MemoPrompt.Lines.Clear;
end;

procedure TMainRagGraphDemo.BtnLoadTextClick(Sender: TObject);
var
  TextStream: TStringStream;
begin
  OpenDialog1.Filter := 'Text Files (*.txt)|*.txt|' + 'Text Files (*.text)|*.text|' + 'JSON Files (*.json)|*.json|' + 'CSV Files (*.csv)|*.csv|' +
    'All text files (*.txt;*.text;*.json;*.csv)|*.txt;*.text;*.json;*.csv|' + 'All files (*.*)|*.*';
  OpenDialog1.DefaultExt := '.txt';
  OpenDialog1.FilterIndex := 5; // Selects "All text files" by default
  OpenDialog1.InitialDir := 'c:\temp\';

  if OpenDialog1.Execute then
  begin
    TextStream := TStringStream.Create('', TEncoding.UTF8);
    try
      TextStream.LoadFromFile(OpenDialog1.FileName);
      MemoToProcess.Lines.Text := TextStream.DataString;
    finally
      TextStream.Free;
    end;
  end;
end;

procedure TMainRagGraphDemo.cbStartNodeLabelChange(Sender: TObject);
begin
  edtStartNodeName.Text := '';
  popSuggestions.IsOpen := False;
end;

procedure TMainRagGraphDemo.edtStartNodeNameChangeTracking(Sender: TObject);
begin
  MatchBuilder_PopulateSuggestions(edtStartNodeName.Text);
end;

procedure TMainRagGraphDemo.edtStartNodeNameExit(Sender: TObject);
begin
  // Small delay to allow the click on the ListBox to be processed first
  TThread.Queue(nil,
    procedure
    begin
      if not lbSuggestions.IsFocused then
        popSuggestions.IsOpen := False;
    end);
end;

function TMainRagGraphDemo.NewQuery: TFDQuery;
begin
  Result := TFDQuery.Create(Self);
  Result.Connection := DbConn;
end;

function TMainRagGraphDemo.EmbeddingToString(const AData: TAiEmbeddingData): string;
var
  i: Integer;
  SB: TStringBuilder;
begin
  if Length(AData) = 0 then
    Exit('[]');

  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for i := 0 to High(AData) do
    begin
      SB.Append(FloatToStr(AData[i])); // Use FormatFloat if you need format/region control
      if i < High(AData) then
        SB.Append(',');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TMainRagGraphDemo.FormCreate(Sender: TObject);
begin
  FCurrentEntidad := 'CLIENTE01';
end;

function TMainRagGraphDemo.HydrateNodeFromQuery(AQuery: TFDQuery; AGraph: TAiRagGraph): TAiRagGraphNode;
var
  Dim: Integer;
begin
  if AGraph.Nodes.Dim > 0 then
    Dim := AGraph.Nodes.Dim
  else
    Dim := 1536; // Replace with your default dimension

  Result := TAiRagGraphNode.Create(AGraph, Dim);
  Result.ID := AQuery.FieldByName('id').AsString;
  Result.NodeLabel := AQuery.FieldByName('node_label').AsString;
  Result.Name := AQuery.FieldByName('name').AsString;

  if not AQuery.FieldByName('properties').IsNull then
  begin
    var LJProp := TJSONObject.ParseJSONValue(AQuery.FieldByName('properties').AsString) as TJSONObject;
    if Assigned(LJProp) then
    try
      Result.Properties.FromJSON(LJProp);
    finally
      LJProp.Free;
    end;
  end;

  if not AQuery.FieldByName('embedding').IsNull then
    Result.Data := StringToEmbedding(AQuery.FieldByName('embedding').AsString);
end;

procedure TMainRagGraphDemo.lbSuggestionsItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
begin
  if Item <> nil then
  begin
    // 1. Put the selected text in the TEdit
    edtStartNodeName.Text := Item.Text;
    // 2. Move the cursor to the end of the text
    edtStartNodeName.SetFocus;
    edtStartNodeName.GoToTextEnd;
    // 3. Hide the popup
    popSuggestions.IsOpen := False;
  end;
end;

function TMainRagGraphDemo.ParseJsonToQueryPlan(const AJSONString: string): TQueryPlan;
var
  JsonValue: TJSONValue;
  RootObject: TJSONObject;
  StepsArray: TJSONArray;
  StepValue: TJSONValue;
  StepObject: TJSONObject;
  i: Integer;
begin
  // Initialize the result with default values
  FillChar(Result, SizeOf(TQueryPlan), 0);
  Result.AnchorPrompt := '';
  Result.AnchorVariable := '';
  Result.ResultVariable := '';
  SetLength(Result.Steps, 0);

  JsonValue := TJSONObject.ParseJSONValue(AJSONString);
  if not(JsonValue is TJSONObject) then
  begin
    JsonValue.Free;
    raise Exception.Create('The provided JSON is not a valid object.');
  end;

  RootObject := JsonValue as TJSONObject;
  try
    // Extract the root fields
    Result.AnchorPrompt := RootObject.GetValue<string>('anchorPrompt', '');
    Result.AnchorVariable := RootObject.GetValue<string>('anchorVariable', '');
    Result.ResultVariable := RootObject.GetValue<string>('resultVariable', '');

    // Process the 'steps' array
    if RootObject.TryGetValue<TJSONArray>('steps', StepsArray) then
    begin
      SetLength(Result.Steps, StepsArray.Count);
      for i := 0 to StepsArray.Count - 1 do
      begin
        StepValue := StepsArray.Items[i];
        if StepValue is TJSONObject then
        begin
          StepObject := StepValue as TJSONObject;
          Result.Steps[i].SourceVariable := StepObject.GetValue<string>('sourceVariable', '');
          Result.Steps[i].EdgeLabel := StepObject.GetValue<string>('edgeLabel', '');
          Result.Steps[i].TargetVariable := StepObject.GetValue<string>('targetVariable', '');
          Result.Steps[i].TargetNodeLabel := StepObject.GetValue<string>('targetNodeLabel', '');
          Result.Steps[i].IsReversed := StepObject.GetValue<Boolean>('isReversed', False);
        end;
      end;
    end;
  finally
    JsonValue.Free;
  end;
end;

function TMainRagGraphDemo.PropertiesToJSONString(const AProperties: TAiEmbeddingMetaData): string;
var
  JsonObj: TJSONObject;
  Pair: TPair<string, Variant>;
begin
  if (AProperties = nil) or (AProperties.InternalDictionary.Count = 0) then
    Exit('{}');

  JsonObj := TJSONObject.Create;
  try
    for Pair in AProperties.InternalDictionary do
    begin
      case VarType(Pair.Value) of
        varBoolean:
          JsonObj.AddPair(Pair.Key, TJSONBool.Create(Boolean(Pair.Value)));
        varSmallint, varInteger, varByte, varShortInt, varWord, varLongWord, varInt64, varUInt64, varSingle, varDouble, varCurrency:
          JsonObj.AddPair(Pair.Key, TJSONNumber.Create(Extended(Pair.Value)));
      else
        JsonObj.AddPair(Pair.Key, TJSONString.Create(VarToStr(Pair.Value)));
      end;
    end;
    Result := JsonObj.ToString;
  finally
    JsonObj.Free;
  end;
end;

procedure TMainRagGraphDemo.RagFindNodeByName(Sender: TObject; Graph: TAiRagGraph; const AName, ANodeLabel: string; var ResultNode: TAiRagGraphNode; var Handled: Boolean);
var
  Query: TFDQuery;
begin
  Query := NewQuery;
  try
    Query.SQL.Text := 'SELECT * FROM graph_nodes WHERE entidad = :entidad AND node_label = :node_label AND name = :name LIMIT 1';
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('node_label').AsString := ANodeLabel;
    Query.ParamByName('name').AsString := AName;
    Query.Open;

    if not Query.Eof then
    begin
      // Auxiliary function to "hydrate" a node from a TFDQuery
      ResultNode := HydrateNodeFromQuery(Query, Graph);
      Handled := True;
    end
    else
    begin
      ResultNode := nil;
      Handled := True;
    end;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagFindNodeNamesByLabel(Sender: TObject; const ANodeLabel, ASearchText: string; ALimit: Integer; out ResultNames: TArray<System.string>; var Handled: Boolean);
var
  Query: TFDQuery;
  NameList: TStringList;
begin
  Query := NewQuery;
  NameList := TStringList.Create;
  try
    // The query is perfect. It uses LIKE and is case-insensitive thanks to UPPER.
    Query.SQL.Text := 'SELECT name FROM graph_nodes ' + 'WHERE entidad = :entidad AND node_label = :node_label AND UPPER(name) LIKE :search_text ' + 'ORDER BY name LIMIT :limit';

    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('node_label').AsString := ANodeLabel;
    Query.ParamByName('search_text').AsString := '%' + ASearchText.ToUpper + '%';
    Query.ParamByName('limit').AsInteger := ALimit;

    Query.Open;

    while not Query.Eof do
    begin
      NameList.Add(Query.Fields[0].AsString);
      Query.Next;
    end;

    ResultNames := NameList.ToStringArray;
    Handled := True;
  finally
    Query.Free;
    NameList.Free;
  end;
end;

procedure TMainRagGraphDemo.RagFindNodesByLabel(Sender: TObject; Graph: TAiRagGraph; const ALabel: string; var ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
var
  Query: TFDQuery;
  NodeIDs: TStringList;
  i: Integer;
begin
  if not(Sender is TAiRagGraph) then
    Exit;

  Query := NewQuery;
  NodeIDs := TStringList.Create;
  try
    // 1. Get only the IDs of the matching nodes.
    Query.SQL.Text := 'SELECT id FROM graph_nodes WHERE entidad = :entidad AND node_label = :node_label';
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('node_label').AsString := ALabel;
    Query.Open;

    while not Query.Eof do
    begin
      NodeIDs.Add(Query.FieldByName('id').AsString);
      Query.Next;
    end;

    // 2. Ask the graph to "hydrate" or return each node from its cache.
    SetLength(ResultNodes, NodeIDs.Count);
    for i := 0 to NodeIDs.Count - 1 do
    begin
      // FindNodeByID is now our only entry point to get nodes.
      // It will take care of creating the object if it does not exist, or returning the
      // existing one if it has already been loaded.
      ResultNodes[i] := Graph.FindNodeByID(NodeIDs[i]);
    end;

    Handled := True;
  finally
    Query.Free;
    NodeIDs.Free;
  end;
end;

procedure TMainRagGraphDemo.RagFindNodesByProperty(Sender: TObject; Graph: TAiRagGraph; const AKey: string; const AValue: Variant; var ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
var
  Query: TFDQuery;
  NodeList: TObjectList<TAiRagGraphNode>;
begin
  Query := NewQuery;
  NodeList := TObjectList<TAiRagGraphNode>.Create(True); // <-- ADDED LINE
  try
    if SameText(AKey, 'name') then
    begin
      Query.SQL.Text := 'SELECT * FROM graph_nodes WHERE entidad = :entidad AND name = :value';
      Query.ParamByName('value').AsString := VarToStr(AValue);
    end
    else
    begin
      Query.SQL.Text := 'SELECT * FROM graph_nodes WHERE entidad = :entidad AND properties ->> :key = :value';
      Query.ParamByName('key').AsString := AKey;
      Query.ParamByName('value').AsString := VarToStr(AValue);
    end;

    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.Open;

    while not Query.Eof do
    begin
      NodeList.Add(HydrateNodeFromQuery(Query, Graph)); // We pass 'Graph' instead of 'RAG'
      Query.Next;
    end;

    ResultNodes := NodeList.ToArray;
    NodeList.OwnsObjects := False;
    Handled := True;
  finally
    Query.Free;
    NodeList.Free;
  end;
end;

{
  procedure TMainRagGraphDemo.RagGetNodeEdges(Sender: TObject; ANode: TAiRagGraphNode; var Handled: Boolean);
  var
  Query: TFDQuery;
  Graph: TAiRagGraph;
  EdgeID: string;
  begin
  if not (Sender is TAiRagGraph) or (ANode = nil) then
  Exit;

  Graph := Sender as TAiRagGraph;
  Query := NewQuery;
  try
  // 1. We search for the IDs of all edges connected to this node.
  // We only need the IDs, the rest of the work will be done by the graph.
  Query.SQL.Text := 'SELECT id FROM graph_edges ' +
  'WHERE entidad = :entidad AND ' +
  '(source_node_id = :node_id OR target_node_id = :node_id)';
  Query.ParamByName('entidad').AsString := FCurrentEntidad;
  Query.ParamByName('node_id').AsString := ANode.ID;
  Query.Open;

  // 2. We iterate over the IDs and ask the graph to load each edge.
  while not Query.Eof do
  begin
  EdgeID := Query.FieldByName('id').AsString;
  // This is the key call.
  // FindEdgeByID is now a "get-or-create-from-db".
  // It will handle the entire loading and connection process.
  Graph.FindEdgeByID(EdgeID);
  Query.Next;
  end;

  Handled := True;
  finally
  Query.Free;
  end;
  end;
}

procedure TMainRagGraphDemo.RagGetNodeEdges(Sender: TObject; ANode: TAiRagGraphNode; var Handled: Boolean);
var
  Query: TFDQuery;
  Graph: TAiRagGraph;
  EdgeData: TEdgeDataRecord;
  EdgeID: string;
begin
  if not(Sender is TAiRagGraph) or (ANode = nil) then
    Exit;

  Graph := Sender as TAiRagGraph;
  Query := NewQuery;
  try
    // 1. We bring ALL edge data in a SINGLE query.
    Query.SQL.Text := 'SELECT id, edge_label, name, source_node_id, target_node_id, ' + 'weight, properties, embedding ' + 'FROM graph_edges ' + 'WHERE entidad = :entidad AND ' + '(source_node_id = :node_id OR target_node_id = :node_id)';
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('node_id').AsString := ANode.ID;
    Query.Open;

    // 2. We iterate over the results and ask the graph to hydrate each edge.
    while not Query.Eof do
    begin
      EdgeID := Query.FieldByName('id').AsString;

      // --- CORRECTED AND CLEAN LOGIC! ---
      // We use the new public function to check whether the edge already exists in memory.
      if not Graph.EdgeExistsInMemory(EdgeID) then
      begin
        // The edge does not exist in memory, so we create and hydrate it.
        EdgeData.ID := EdgeID;
        EdgeData.EdgeLabel := Query.FieldByName('edge_label').AsString;
        EdgeData.Name := Query.FieldByName('name').AsString;
        EdgeData.SourceNodeID := Query.FieldByName('source_node_id').AsString;
        EdgeData.TargetNodeID := Query.FieldByName('target_node_id').AsString;
        EdgeData.Weight := Query.FieldByName('weight').AsFloat;

        if not Query.FieldByName('properties').IsNull then
          EdgeData.PropertiesJSON := Query.FieldByName('properties').AsString
        else
          EdgeData.PropertiesJSON := '{}';

        if not Query.FieldByName('embedding').IsNull then
          EdgeData.EmbeddingStr := Query.FieldByName('embedding').AsString
        else
          EdgeData.EmbeddingStr := '[]';

        // We use the graph's protected method to create the object from the data.
        // To call it, we DO need the class helper here.
        Graph.InternalHydrateEdge(EdgeData);
      end;
      // --- END OF LOGIC ---

      Query.Next;
    end;
    Handled := True;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGetUniqueEdgeLabels(Sender: TObject; Graph: TAiRagGraph; var ResultLabels: TArray<System.string>; var Handled: Boolean);
var
  Query: TFDQuery;
  LabelList: TStringList;
begin
  Query := NewQuery;
  LabelList := TStringList.Create;
  try
    // 1. Define the SQL query
    Query.SQL.Text := 'SELECT DISTINCT edge_label FROM graph_edges WHERE entidad = :entidad ORDER BY edge_label';
    Query.ParamByName('entidad').AsString := FCurrentEntidad;

    // 2. Execute the query
    Query.Open;

    // 3. Iterate over the results
    while not Query.Eof do
    begin
      LabelList.Add(Query.Fields[0].AsString);
      Query.Next;
    end;

    // 4. Populate the result array
    ResultLabels := LabelList.ToStringArray;

    // 5. Mark as handled
    Handled := True;

  finally
    Query.Free;
    LabelList.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGetUniqueNodeLabels(Sender: TObject; Graph: TAiRagGraph; var ResultLabels: TArray<string>; var Handled: Boolean);
var
  Query: TFDQuery;
  LabelList: TStringList;
begin
  // We assume that the database connection is already active.
  // If not, you can add a check here.

  Query := NewQuery; // Using your helper function
  LabelList := TStringList.Create;
  try
    // 1. Define the SQL query
    Query.SQL.Text := 'SELECT DISTINCT node_label FROM graph_nodes WHERE entidad = :entidad ORDER BY node_label';
    Query.ParamByName('entidad').AsString := FCurrentEntidad;

    // 2. Execute the query
    Query.Open;

    // 3. Iterate over the results and add them to the list
    while not Query.Eof do
    begin
      LabelList.Add(Query.Fields[0].AsString);
      Query.Next;
    end;

    // 4. Convert the TStringList to a TArray<string> for the result
    ResultLabels := LabelList.ToStringArray;

    // 5. Indicate that the request has been handled by the database
    Handled := True;

  finally
    Query.Free;
    LabelList.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphAddEdge(Sender: TObject; AEdge: TAiRagGraphEdge; var Handled: Boolean);
var
  Query: TFDQuery;
begin
  Query := NewQuery;
  try
    Query.SQL.Clear;

    if Length(AEdge.Data) > 0 then
    Begin
      Query.SQL.Add('INSERT INTO graph_edges (entidad, id, edge_label, name, source_node_id, target_node_id, weight, properties, embedding) ');
      Query.SQL.Add('VALUES (:entidad, :id, :edge_label, :name, :source_node_id, :target_node_id, :weight, :properties::JsonB, ''' + EmbeddingToString(AEdge.Data) + ''')');
    End
    Else
    Begin
      Query.SQL.Add('INSERT INTO graph_edges (entidad, id, edge_label, name, source_node_id, target_node_id, weight, properties) ');
      Query.SQL.Add('VALUES (:entidad, :id, :edge_label, :name, :source_node_id, :target_node_id, :weight, :properties::JsonB)');
    End;

    // Assign values to the parameters
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('id').AsString := AEdge.ID;
    Query.ParamByName('edge_label').AsString := AEdge.EdgeLabel;
    Query.ParamByName('name').AsString := AEdge.Name;
    Query.ParamByName('source_node_id').AsString := AEdge.FromNode.ID;
    Query.ParamByName('target_node_id').AsString := AEdge.ToNode.ID;
    Query.ParamByName('weight').AsFloat := AEdge.Weight;
    Query.ParamByName('properties').AsString := PropertiesToJSONString(AEdge.MetaData);

    Query.ExecSQL;
    Handled := True;

  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphAddNode(Sender: TObject; ANode: TAiRagGraphNode; var Handled: Boolean);
var
  Query: TFDQuery;
begin
  Query := NewQuery;
  try
    if Length(ANode.Data) > 0 then
    Begin
      Query.SQL.Add('INSERT INTO graph_nodes (entidad, id, node_label, name, properties, embedding) ');
      Query.SQL.Add('VALUES (:entidad, :id, :node_label, :name, :properties::jsonb, ''' + EmbeddingToString(ANode.Data) + ''')');
    End
    Else
    Begin
      Query.SQL.Add('INSERT INTO graph_nodes (entidad, id, node_label, name, properties) ');
      Query.SQL.Add('VALUES (:entidad, :id, :node_label, :name, :properties::jsonb)');
    End;

    // Assign values to the parameters
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('id').AsString := ANode.ID;
    Query.ParamByName('node_label').AsString := ANode.NodeLabel;
    Query.ParamByName('name').AsString := ANode.Name;
    Query.ParamByName('properties').AsString := PropertiesToJSONString(ANode.Properties);

    Query.ExecSQL;
    Handled := True;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphDeleteEdge(Sender: TObject; const AEdgeID: string; var Handled: Boolean);
var
  Query: TFDQuery;
begin
  Query := NewQuery;
  try
    Query.SQL.Text := 'DELETE FROM graph_edges WHERE id = :id AND entidad = :entidad';
    Query.ParamByName('id').AsString := AEdgeID;
    Query.ParamByName('entidad').AsString := FCurrentEntidad;

    Query.ExecSQL;
    Handled := True;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphDeleteNode(Sender: TObject; const ANodeID: string; var Handled: Boolean);
var
  Query: TFDQuery;
begin
  Query := NewQuery;
  try
    Query.SQL.Text := 'DELETE FROM graph_nodes WHERE id = :id AND entidad = :entidad';

    Query.ParamByName('id').AsString := ANodeID;
    Query.ParamByName('entidad').AsString := FCurrentEntidad;

    Query.ExecSQL;
    Handled := True;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphFindEdgeByID(Sender: TObject; const AEdgeID: string; out AEdgeData: TEdgeDataRecord; var Found: Boolean);
var
  Query: TFDQuery;
begin
  Found := False;
  Query := NewQuery;
  try
    Query.SQL.Text := 'SELECT id, edge_label, name, source_node_id, target_node_id, ' + 'weight, properties, embedding ' + 'FROM graph_edges ' + 'WHERE id = :id AND entidad = :entidad';
    Query.ParamByName('id').AsString := AEdgeID;
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.Open;

    if not Query.IsEmpty then
    begin
      // We fill the record with the raw data from the DB.
      AEdgeData.ID := Query.FieldByName('id').AsString;
      AEdgeData.EdgeLabel := Query.FieldByName('edge_label').AsString;
      AEdgeData.Name := Query.FieldByName('name').AsString;
      AEdgeData.SourceNodeID := Query.FieldByName('source_node_id').AsString;
      AEdgeData.TargetNodeID := Query.FieldByName('target_node_id').AsString;
      AEdgeData.Weight := Query.FieldByName('weight').AsFloat;

      if not Query.FieldByName('properties').IsNull then
        AEdgeData.PropertiesJSON := Query.FieldByName('properties').AsString
      else
        AEdgeData.PropertiesJSON := '{}';

      if not Query.FieldByName('embedding').IsNull then
        AEdgeData.EmbeddingStr := Query.FieldByName('embedding').AsString
      else
        AEdgeData.EmbeddingStr := '[]';

      Found := True;
    end;
  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphFindNodeByID(Sender: TObject; const ANodeID: string; out ANodeData: TNodeDataRecord; var Found: Boolean);
var
  Query: TFDQuery;
begin
  Found := False;
  Query := NewQuery;
  try
    Query.SQL.Text := 'SELECT id, node_label, name, properties, embedding ' + 'FROM graph_nodes ' + 'WHERE id = :id AND entidad = :entidad';
    Query.ParamByName('id').AsString := ANodeID;
    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.Open;

    if not Query.IsEmpty then
    begin
      // Instead of creating an object, we fill the record with the raw data.
      ANodeData.ID := Query.FieldByName('id').AsString;
      ANodeData.NodeLabel := Query.FieldByName('node_label').AsString;
      ANodeData.Name := Query.FieldByName('name').AsString;

      if not Query.FieldByName('properties').IsNull then
        ANodeData.PropertiesJSON := Query.FieldByName('properties').AsString
      else
        ANodeData.PropertiesJSON := '{}';

      if not Query.FieldByName('embedding').IsNull then
        ANodeData.EmbeddingStr := Query.FieldByName('embedding').AsString
      else
        ANodeData.EmbeddingStr := '[]';

      Found := True; // We indicate that we found the data.
    end;

    // There is no longer a `Handled` in the new signature, `Found` fulfills that role.
    // We no longer create any TAiRagGraphNode here.

  finally
    Query.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphLoad(Sender: TObject; Graph: TAiRagGraph; var Handled: Boolean);
begin
  //
end;

procedure TMainRagGraphDemo.RagGraphQuery(Sender: TObject; const APlan: TQueryPlan; ADepth, ALimit: Integer; APrecision: Double; ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
var
  Graph: TAiRagGraph;
  Query: TFDQuery;
  Step: TQueryStep;
  QueryEmbedding: TAiEmbeddingData;
  EmbeddingStr: String;
  NodeIDs: TStringList;
begin
  SetLength(ResultNodes, 0);
  if not(Sender is TAiRagGraph) then
    Exit;
  Graph := Sender as TAiRagGraph;

  // We will only handle plans with an anchor and a single step, as before.
  // You could extend this with a dynamic SQL generator in the future.
  if Length(APlan.Steps) <> 1 then
  begin
    Handled := False;
    Exit;
  end;

  Query := NewQuery;
  NodeIDs := TStringList.Create;
  Step := APlan.Steps[0];
  try
    // Step 1: Get embedding (no changes)
    QueryEmbedding := Graph.Embeddings.CreateEmbedding(APlan.AnchorPrompt, 'user');
    EmbeddingStr := EmbeddingToString(QueryEmbedding);

    // Step 2: Build and execute the SQL query. We select only the IDs of the final result.
    Query.SQL.Text := 'WITH AnchorNodes AS (' + '  SELECT id' + '  FROM graph_nodes' + '  WHERE entidad = :entidad AND (embedding <-> ''' + EmbeddingStr + ''') < :distance_threshold' + '  ORDER BY embedding <-> ''' + EmbeddingStr +
      ''' LIMIT :limit' + ')' +
    // Final query: Get the IDs of the destination nodes.
      'SELECT final_node.id ' + 'FROM AnchorNodes an ' + 'JOIN graph_edges e ON an.id = e.source_node_id AND e.entidad = :entidad AND e.edge_label = :edge_label ' +
      'JOIN graph_nodes final_node ON e.target_node_id = final_node.id AND final_node.entidad = :entidad ' + 'WHERE final_node.node_label = :target_label';

    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('distance_threshold').AsFloat := 1 - APrecision;
    Query.ParamByName('limit').AsInteger := ALimit;
    Query.ParamByName('edge_label').AsString := Step.EdgeLabel;
    Query.ParamByName('target_label').AsString := Step.TargetNodeLabel;
    Query.Open;

    while not Query.Eof do
    begin
      NodeIDs.Add(Query.Fields[0].AsString);
      Query.Next;
    end;

    // Step 3: Delegated hydration and result construction
    SetLength(ResultNodes, NodeIDs.Count);
    for var i := 0 to NodeIDs.Count - 1 do
    begin
      // FindNodeByID ensures that the node exists in memory,
      // loading it if necessary.
      ResultNodes[i] := Graph.FindNodeByID(NodeIDs[i]);
    end;

    Handled := True;

  finally
    Query.Free;
    NodeIDs.Free;
  end;
end;

procedure TMainRagGraphDemo.RagGraphSearchNodes(Sender: TObject; const APrompt: string; ADepth, ALimit: Integer; APrecision: Double; out ResultNodes: TArray<uMakerAi.RAG.Graph.Core.TAiRagGraphNode>; var Handled: Boolean);
var
  Query: TFDQuery;
  Graph: TAiRagGraph;
  QueryEmbedding: TAiEmbeddingData;
  EmbeddingStr: string;
  NodeIDs: TStringList;
  InitialNodeIDs: TStringList; // To store the seed nodes
  Node: TAiRagGraphNode;
begin
  SetLength(ResultNodes, 0);
  if not(Sender is TAiRagGraph) then
    Exit;
  Graph := Sender as TAiRagGraph;

  // Step 1: Get the embedding (no changes)
  if not Assigned(Graph.Embeddings) then
    raise Exception.Create('The Embeddings engine is not assigned to the graph.');
  QueryEmbedding := Graph.Embeddings.CreateEmbedding(APrompt, 'user');
  EmbeddingStr := EmbeddingToString(QueryEmbedding);

  Query := NewQuery;
  NodeIDs := TStringList.Create;
  InitialNodeIDs := TStringList.Create;
  try
    // Step 2: Execute the SQL query (the query itself hardly changes)
    if ADepth = 0 then
    begin
      // SIMPLE CASE: Semantic search. We only need the IDs.
      Query.SQL.Text := 'SELECT id FROM graph_nodes ' + 'WHERE entidad = :entidad AND (embedding <-> ''' + EmbeddingStr + ''') < :distance_threshold ' + 'ORDER BY embedding <-> ''' + EmbeddingStr + ''' LIMIT :limit';
      Query.ParamByName('distance_threshold').AsFloat := 1 - APrecision;
    end
    else
    begin
      // COMPLEX CASE: Expansion. The CTE is perfect. We only select the IDs at the end.
      Query.SQL.Text := 'WITH RECURSIVE traversal AS (' + '  SELECT id, 1 AS depth, ARRAY[id] AS path' + '  FROM (' + '    SELECT id' + '    FROM graph_nodes' + '  WHERE entidad = :entidad AND (embedding <-> ''' + EmbeddingStr +
        ''') < :distance_threshold' + '  ORDER BY embedding <-> ''' + EmbeddingStr + '''' + '    LIMIT :limit' + '  ) AS initial' + '  UNION ALL' + '  SELECT' +
        '    CASE WHEN e.source_node_id = t.id THEN e.target_node_id ELSE e.source_node_id END AS id,' + '    t.depth + 1,' + '    t.path || CASE WHEN e.source_node_id = t.id THEN e.target_node_id ELSE e.source_node_id END' +
        '  FROM traversal t' + '  JOIN graph_edges e ON (e.source_node_id = t.id OR e.target_node_id = t.id) AND e.entidad = :entidad' + '  WHERE t.depth <= :depth' + // <= to include the final depth level
        '    AND NOT (CASE WHEN e.source_node_id = t.id THEN e.target_node_id ELSE e.source_node_id END = ANY(t.path))' + ')' +
      // Final query: we only want the unique IDs of all nodes in the subgraph
        'SELECT DISTINCT id FROM traversal';

      Query.ParamByName('distance_threshold').AsFloat := 1 - APrecision;
      Query.ParamByName('depth').AsInteger := ADepth;
    end;

    Query.ParamByName('entidad').AsString := FCurrentEntidad;
    Query.ParamByName('limit').AsInteger := ALimit;
    Query.Open;

    // We save the IDs of the seed nodes (the first results)
    // to know what to return at the end.
    while not Query.Eof do
    begin
      NodeIDs.Add(Query.Fields[0].AsString);
      if ADepth = 0 then
        InitialNodeIDs.Add(Query.Fields[0].AsString);
      Query.Next;
    end;

    // If the search was with expansion, we need to determine the seed nodes separately.
    if ADepth > 0 then
    begin
      Query.SQL.Text := 'SELECT id FROM graph_nodes ' + 'WHERE entidad = :entidad AND (embedding <-> ''' + EmbeddingStr + ''') < :distance_threshold ' + 'ORDER BY embedding <-> ''' + EmbeddingStr + ''' LIMIT :limit';
      Query.Open;
      while not Query.Eof do
      begin
        InitialNodeIDs.Add(Query.Fields[0].AsString);
        Query.Next;
      end;
    end;

    // Step 3: Delegated "hydration". We ask the graph to ensure
    // that all nodes in the subgraph exist in memory.
    for var NodeID in NodeIDs do
    begin
      // FindNodeByID will take care of loading the node from the DB if it is not
      // already in memory. This is much cleaner!
      Graph.FindNodeByID(NodeID);
    end;

    // If there was expansion, we must also ensure that all edges
    // between the nodes in the subgraph are loaded.
    if ADepth > 0 then
    begin
      for var NodeID in NodeIDs do
      begin
        Node := Graph.FindNodeByID(NodeID);
        if Node <> nil then
          Node.EnsureEdgesAreLoaded; // This will trigger OnGetNodeEdges
      end;
    end;

    // Step 4: Build the final result from the seed nodes.
    // The objects are already in the graph cache.
    SetLength(ResultNodes, InitialNodeIDs.Count);
    for var i := 0 to InitialNodeIDs.Count - 1 do
    begin
      ResultNodes[i] := Graph.FindNodeByID(InitialNodeIDs[i]);
    end;

    Handled := True;

  finally
    Query.Free;
    NodeIDs.Free;
    InitialNodeIDs.Free;
  end;
end;

{ TAiRagGraphNodeHacker }

procedure TAiRagGraphNodeHacker.InternalAddIncomingEdge(AEdge: TAiRagGraphEdge);
begin
  Self.AddIncomingEdge(AEdge); // Calls the original 'protected' method
end;

procedure TAiRagGraphNodeHacker.InternalAddOutgoingEdge(AEdge: TAiRagGraphEdge);
begin
  Self.AddOutgoingEdge(AEdge); // Calls the original 'protected' method
end;

procedure TMainRagGraphDemo.MatchBuilder_DisplayMatchResults(const AResults: TArray<TDictionary<string, TObject>>; AShowProperties: Boolean);
var
  Match: TDictionary<string, TObject>;
  VarName: TPair<string, TObject>;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  StrWrap: TStringWrapper;
  MatchIndex: Integer;
begin
  MatchIndex := 0;
  for Match in AResults do
    try
      Inc(MatchIndex);
      MemoResults.Lines.Add(Format('*** Match #%d ***', [MatchIndex]));
      for VarName in Match do
      begin
        if VarName.Value is TAiRagGraphNode then
        begin
          Node := VarName.Value as TAiRagGraphNode;
          MemoResults.Lines.Add(Format('  %s (%s): %s', [VarName.Key, Node.NodeLabel, Node.Name]));

          // --- NEW LOGIC: Show Descriptive Text ---
          if not Node.Text.IsEmpty then
            MemoResults.Lines.Add(Format('    [Context]: %s', [Node.Text]));

          if AShowProperties then
            MatchBuilder_DisplayProperties(Node.Properties, MemoResults.Lines, '    ');
        end
        else if VarName.Value is TAiRagGraphEdge then
        begin
          Edge := VarName.Value as TAiRagGraphEdge;
          MemoResults.Lines.Add(Format('  %s (%s): %s --%s--> %s', [VarName.Key, Edge.EdgeLabel, Edge.FromNode.Name, Edge.EdgeLabel, Edge.ToNode.Name]));

          // --- NEW LOGIC: Show Relationship Text ---
          if not Edge.Text.IsEmpty then
            MemoResults.Lines.Add(Format('    [Relationship]: %s', [Edge.Text]));

          if AShowProperties then
            MatchBuilder_DisplayProperties(Edge.MetaData, MemoResults.Lines, '    ');
        end
        else if VarName.Value is TStringWrapper then
        begin
          StrWrap := VarName.Value as TStringWrapper;
          MemoResults.Lines.Add(Format('  %s: %s', [VarName.Key, StrWrap.Value]));
        end;
      end;
      MemoResults.Lines.Add('');
    finally
      Match.Free;
    end;
end;

procedure TMainRagGraphDemo.MatchBuilder_DisplayProperties(AProperties: TAiEmbeddingMetaData; AOutput: TStrings; const AIndentation: string);
var
  Pair: TPair<string, Variant>;
begin
  if (AProperties = nil) or (AProperties.InternalDictionary.Count = 0) then
    Exit;

  for Pair in AProperties.InternalDictionary do
    AOutput.Add(Format('%s- %s: %s', [AIndentation, Pair.Key, VarToStr(Pair.Value)]));
end;

procedure TMainRagGraphDemo.MatchBuilder_DisplaySubgraphResults(const AResults: TArray<TDictionary<string, TObject>>; AShowProperties: Boolean);
var
  Item: TDictionary<string, TObject>;
  ElementTypeObj: TObject;
  ElementTypeStr: string;
  ElementObj: TObject;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  NodeList: TStringList;
  EdgeList: TStringList;
begin
  // We create temporary lists to separate and sort the results
  NodeList := TStringList.Create;
  EdgeList := TStringList.Create;
  try
    for Item in AResults do
    begin
      try
        ElementTypeStr := '';
        // 1. Extract the element type (sent by the Core as TStringWrapper)
        if Item.TryGetValue('type', ElementTypeObj) and (ElementTypeObj is TStringWrapper) then
          ElementTypeStr := TStringWrapper(ElementTypeObj).Value;

        // 2. Extract the real object (Node or Edge)
        if Item.TryGetValue('element', ElementObj) then
        begin
          // --- PROCESS NODE ---
          if (ElementTypeStr = 'node') and (ElementObj is TAiRagGraphNode) then
          begin
            Node := TAiRagGraphNode(ElementObj);
            NodeList.Add(Format('- %s (%s)', [Node.Name, Node.NodeLabel]));

            // Show descriptive text (RAG Context)
            if not Node.Text.IsEmpty then
              NodeList.Add(Format('    [Context]: %s', [Node.Text]));

            // Show properties if requested
            if AShowProperties then
              MatchBuilder_DisplayProperties(Node.Properties, NodeList, '    ');
          end

          // --- PROCESS EDGE ---
          else if (ElementTypeStr = 'edge') and (ElementObj is TAiRagGraphEdge) then
          begin
            Edge := TAiRagGraphEdge(ElementObj);
            EdgeList.Add(Format('- %s --[%s]--> %s', [Edge.FromNode.Name, Edge.EdgeLabel, Edge.ToNode.Name]));

            // Show descriptive text of the relationship
            if not Edge.Text.IsEmpty then
              EdgeList.Add(Format('    [Relationship]: %s', [Edge.Text]));

            // Show properties if requested
            if AShowProperties then
              MatchBuilder_DisplayProperties(Edge.MetaData, EdgeList, '    ');
          end;
        end;
      finally
        // IMPORTANT: Free the TStringWrapper 'type' since it is a temporary object
        // created by ExecuteMakerGQL for each result row.
        if Item.TryGetValue('type', ElementTypeObj) then
          ElementTypeObj.Free;

        // We free the row dictionary (Nodes/Edges are NOT freed, they belong to the Graph)
        Item.Free;
      end;
    end;

    // --- FINAL RENDERING IN THE MEMO ---
    MemoResults.Lines.BeginUpdate;
    try
      MemoResults.Lines.Clear;
      MemoResults.Lines.Add(Format('--- Expanded Subgraph: %d Nodes and %d Edges ---', [NodeList.Count, EdgeList.Count]));
      MemoResults.Lines.Add(StringOfChar('-', 40));
      MemoResults.Lines.Add('');

      // Show sorted nodes
      MemoResults.Lines.Add('--- ENTITIES (NODES) ---');
      if NodeList.Count > 0 then
      begin
        NodeList.Sort;
        MemoResults.Lines.AddStrings(NodeList);
      end
      else
        MemoResults.Lines.Add('(No nodes found)');

      MemoResults.Lines.Add('');

      // Show sorted edges
      MemoResults.Lines.Add('--- RELATIONSHIPS (EDGES) ---');
      if EdgeList.Count > 0 then
      begin
        EdgeList.Sort;
        MemoResults.Lines.AddStrings(EdgeList);
      end
      else
        MemoResults.Lines.Add('(No internal edges found in the subgraph)');

      MemoResults.Lines.Add('');
      MemoResults.Lines.Add(StringOfChar('-', 40));
      MemoResults.Lines.Add('End of subgraph report.');
    finally
      MemoResults.Lines.EndUpdate;
    end;

  finally
    NodeList.Free;
    EdgeList.Free;
  end;
end;

// ----- Match search functions ------

function TMainRagGraphDemo.MatchBuilder_GetNextNodeVar: string;
begin
  Result := 'n' + IntToStr(FNodeVarCounter);
  Inc(FNodeVarCounter);
end;

procedure TMainRagGraphDemo.MatchBuilder_PopulateComboBoxes;
var
  ALabel: string;
  List: TStringList;
begin

  List := TStringList.Create;
  Try

    // Clear and populate ComboBoxes with node labels
    cbStartNodeLabel.Items.Clear;
    cbTargetNodeLabel.Items.Clear;
    for ALabel in RAG.GetUniqueNodeLabels do
    begin
      List.Add(ALabel);
    end;

    List.Sort;
    List.Insert(0, '');

    cbStartNodeLabel.Items.Text := List.Text;
    cbTargetNodeLabel.Items.Text := List.Text;

    if cbStartNodeLabel.Items.Count > 0 then
      cbStartNodeLabel.ItemIndex := 0;

    if cbTargetNodeLabel.Items.Count > 0 then
      cbTargetNodeLabel.ItemIndex := 0;

    // Clear and populate ComboBox with edge labels
    cbEdgeLabel.Items.Clear;
    List.Clear;
    for ALabel in RAG.GetUniqueEdgeLabels do
    begin
      List.Add(ALabel);
    end;
    List.Sort;
    List.Insert(0, '');

    cbEdgeLabel.Items.Text := List.Text;

    if cbEdgeLabel.Items.Count > 0 then
      cbEdgeLabel.ItemIndex := 0;
  Finally
    List.Free;
  End;
end;

procedure TMainRagGraphDemo.MatchBuilder_PopulateSuggestions(const SearchText: string);
var
  SelectedLabel: string;
  SuggestedNames: TArray<string>;
  AName: string;
begin
  // If there is no text, hide the popup and exit
  if SearchText.Trim.IsEmpty then
  begin
    popSuggestions.IsOpen := False;
    Exit;
  end;

  // We get the selected label.
  if (cbStartNodeLabel.ItemIndex <= 0) or (cbStartNodeLabel.Selected = nil) then // <= 0 to ignore the empty item
  begin
    popSuggestions.IsOpen := False;
    Exit;
  end;
  SelectedLabel := cbStartNodeLabel.Selected.Text;
  if SelectedLabel.IsEmpty then
  begin
    popSuggestions.IsOpen := False;
    Exit;
  end;

  // We clear the previous suggestions list
  lbSuggestions.Clear;

  // --- KEY LINE CORRECTED ---
  // We call the new graph function, which will delegate to our SQL query.
  SuggestedNames := RAG.FindNodeNamesByLabel(SelectedLabel, SearchText, 15); // Limit of 15 suggestions

  // We populate the ListBox with the results
  for AName in SuggestedNames do
  begin
    lbSuggestions.Items.Add(AName);
  end;
  // --- END OF CORRECTION ---

  // We show or hide the popup based on whether we found results
  if lbSuggestions.Items.Count > 0 then
  begin
    // Position the popup below the TEdit
    {
      var LPoint := TPointF.Create(0, edtStartNodeName.Height);
      LPoint := edtStartNodeName.LocalToAbsolute(LPoint);
      LPoint := Self.AbsoluteToLocal(LPoint);
      popSuggestions.Position.Point := LPoint;
      popSuggestions.Width := edtStartNodeName.Width;
    }
    popSuggestions.IsOpen := True;
  end
  else
  begin
    popSuggestions.IsOpen := False;
  end;
end;

procedure TMainRagGraphDemo.MatchBuilder_UpdateQueryVisualizer;
var
  i: Integer;
  Clause: TMatchClause;
  SourcePattern, TargetPattern: TMatchNodePattern;
  DirectionStr: string;
begin
  lbQuerySteps.Clear;
  if FCurrentQuery.MatchClauses.Count = 0 then
    Exit;

  // Visualize the first clause in full
  Clause := FCurrentQuery.MatchClauses[0];
  SourcePattern := FCurrentQuery.NodePatternByVariable[Clause.SourceNodeVar];
  TargetPattern := FCurrentQuery.NodePatternByVariable[Clause.TargetNodeVar];
  case Clause.EdgePattern.Direction of
    gdOutgoing:
      DirectionStr := '-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']->';
    gdIncoming:
      DirectionStr := '<-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']-';
  else
    DirectionStr := '-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']-';
  end;
  lbQuerySteps.Items.Add(Format('(%s:%s) %s (%s:%s)', [SourcePattern.Variable, SourcePattern.NodeLabel, DirectionStr, TargetPattern.Variable, TargetPattern.NodeLabel]));

  // Visualize the following clauses
  for i := 1 to FCurrentQuery.MatchClauses.Count - 1 do
  begin
    Clause := FCurrentQuery.MatchClauses[i];
    TargetPattern := FCurrentQuery.NodePatternByVariable[Clause.TargetNodeVar];
    case Clause.EdgePattern.Direction of
      gdOutgoing:
        DirectionStr := '-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']->';
      gdIncoming:
        DirectionStr := '<-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']-';
    else
      DirectionStr := '-[' + Clause.EdgePattern.Variable + ':' + Clause.EdgePattern.EdgeLabel + ']-';
    end;
    lbQuerySteps.Items.Add(Format('%s (%s:%s)', [DirectionStr, TargetPattern.Variable, TargetPattern.NodeLabel]));
  end;
end;

end.
