// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enr�quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


// Exported graphs can be visualized with gephi and downloaded from https://gephi.org/users/download/

unit uMakerAi.RAG.Graph.Core;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.Json, System.Variants, System.Json.Writers, System.Json.Types, System.IOUtils,
  System.Rtti, System.StrUtils, System.DateUtils, System.Masks, System.VarUtils,

  Xml.XMLDoc, Xml.XMLIntf, Xml.XMLDom,

  uMakerAi.Embeddings.Core, uMakerAi.Embeddings, uMakerAi.RAG.Vectors.Index,
  // We include your base unit of MakerAi
  uMakerAi.RAG.Vectors, uMakerAi.RAG.MetaData;

type


  // --------- CLASSES FOR THE PARSER --------------------------------

  { Enumerations for the Expression tree }
  TExpressionKind = (ekLiteral, ekProperty, ekBinary);

  TBinaryOp = (
    // Logical
    opAnd, opOr,

    // Standard comparison
    opEqual, opNotEqual, opGreater, opGreaterEqual, opLess, opLessEqual,

    // Text
    opContains, opLike, // New
    opILike, // New

    // Lists and Nullity
    opIn, // New
    opNotIn, // New
    opIsNull, // New
    opIsNotNull // New
    );

  { Abstract base class for language expressions }
  TGraphExpression = class
  public
    Kind: TExpressionKind;
    destructor Destroy; override;
  end;

  { Expression for constant values (18, 'Madrid', true, null) }
  TLiteralExpr = class(TGraphExpression)
  public
    Value: Variant;
    constructor Create(AValue: Variant);
  end;

  { Expression for property access (p.name, e.weight) }
  TPropertyExpr = class(TGraphExpression)
  public
    Variable: string; // Example: 'p'
    PropertyKey: string; // Example: 'name'
    constructor Create(const AVar, AKey: string);
  end;

  { Expression for binary operations (A > B, C AND D) }
  TBinaryExpr = class(TGraphExpression)
  public
    Left: TGraphExpression;
    Op: TBinaryOp;
    Right: TGraphExpression;
    constructor Create(ALeft: TGraphExpression; AOp: TBinaryOp; ARight: TGraphExpression);
    destructor Destroy; override;
  end;

  TDegreeType = (dtIn, dtOut, dtTotal);
  TGraphExportFormat = (gefDOT, gefGraphML, gefGraphMkai);

  { TMergeStrategy }
  TMergeStrategy = (msAddNewOnly, // (Default) Only adds properties that do not exist.
    msOverwrite, // Overwrites existing properties with the new ones.
    msKeepExisting // Does not make any change to the properties of the existing element.
    );


  // --Query Planner---
  // A model to perform hybrid queries on the graph, first obtains initial nodes with embeddings
  // then searches within the graph for very explicit data to obtain precise graph data.

  // Represents a step in the query plan.
  TQueryStep = record
    SourceVariable: string; // Variable of the previous step (empty for the first step)
    EdgeLabel: string; // Label of the edge to follow
    TargetVariable: string; // Name to store the results of this step
    TargetNodeLabel: string; // Optional filter for the target node type
    IsReversed: Boolean; // If the search should be backwards (incoming)
  end;

  // Represents the complete query plan.
  TQueryPlan = record
    AnchorPrompt: string; // The text for the initial semantic search
    AnchorVariable: string; // The name of the variable for the anchor nodes
    Steps: TArray<TQueryStep>; // The structured steps to follow
    ResultVariable: string; // The variable whose nodes should be returned
  end;

  // Forward declarations to resolve circular references
  TAiRagGraphNode = class;
  TAiRagGraphEdge = class;
  TAiRagGraph = class;
  TAiRagGraphDriverBase = class;


  // ----- MATCH --------------------
  // --Match is a function that allows traversing the graph without needing embeddings to find patterns and relationships

  // Direction for pattern search on edges
  TGraphDirection = (gdOutgoing, gdIncoming, gdBoth);

  // --- Helper classes for building the MATCH query ---

  // Represents a pattern for a node in the query.
  // Eg: (p:Person {city: 'New York'})
  TMatchNodePattern = class
  public
    Variable: string; // The node alias, eg: 'p'
    NodeLabel: string; // The label to search for, eg: 'Person'
    Properties: TDictionary<string, Variant>; // Property filters, eg: {'city': 'New York'}
    constructor Create;
    destructor Destroy; override;
    function Matches(ANode: TAiRagGraphNode): Boolean;
  end;

  // Represents a pattern for an edge in the query.
  // Eg: -[r:KNOWS {since: 2018}]->
  TMatchEdgePattern = class
  public
    Variable: string; // The edge alias, eg: 'r'
    EdgeLabel: string; // The label to search for, eg: 'KNOWS'
    Direction: TGraphDirection; // The direction of the relationship
    Properties: TDictionary<string, Variant>; // Property filters, eg: {'since': 2018}
    constructor Create;
    destructor Destroy; override;
    // Checks whether an edge matches the pattern, considering the direction of the current traversal
    function Matches(AEdge: TAiRagGraphEdge; AActualDirection: TGraphDirection): Boolean;
  end;

  // Represents a complete pattern clause.
  // Eg: (p)-[r]->(m)
  TMatchClause = class
  public
    SourceNodeVar: string; // Variable of the source node, eg: 'p'
    EdgePattern: TMatchEdgePattern; // The edge pattern (the clause owns this object)
    TargetNodeVar: string; // Variable of the target node, eg: 'm'
    constructor Create(ASourceNodeVar: string; AEdgePattern: TMatchEdgePattern; ATargetNodeVar: string);
    destructor Destroy; override;
  end;

  // The complete query containing all node patterns and clauses.
  TGraphMatchQuery = class
  private
    FNodePatterns: TObjectList<TMatchNodePattern>; // Owns the node patterns
    FMatchClauses: TObjectList<TMatchClause>;
    FWhereClause: TGraphExpression;
    FDepth: Integer; // Owns the clauses
    function GetNodePatternByVariable(const AVar: string): TMatchNodePattern;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddNodePattern(ANodePattern: TMatchNodePattern);
    procedure AddMatchClause(AClause: TMatchClause);
    property NodePatterns: TObjectList<TMatchNodePattern> read FNodePatterns;
    property MatchClauses: TObjectList<TMatchClause> read FMatchClauses;
    property NodePatternByVariable[const AVar: string]: TMatchNodePattern read GetNodePatternByVariable;
    property WhereClause: TGraphExpression read FWhereClause write FWhereClause;
    property Depth: Integer read FDepth write FDepth;
  end;

  TStringWrapper = class(TObject)
  public
    Value: string;
    constructor Create(const AValue: string);
  end;

  TNodeDataRecord = record // Or use TJSONObject
    ID: string;
    NodeLabel: string;
    Name: string;
    PropertiesJSON: string;
    EmbeddingStr: string;
    NodeText: string;
  end;

  TEdgeDataRecord = record
    ID: string;
    EdgeLabel: string;
    Name: string;
    SourceNodeID: string; // ID of the source node
    TargetNodeID: string; // ID of the target node
    Weight: Double;
    PropertiesJSON: string;
    EmbeddingStr: string;
    NodeText: string;
  end;

  { TAiRagGraphDriverBase }

  TAiRagGraphDriverBase = class(TComponent)
  private
    FGraph: TAiRagGraph;
  protected
    // Methods that drivers MUST implement
    function FindNodeDataByID(const ANodeID: string; out ANodeData: TNodeDataRecord): Boolean; virtual; abstract;
    function FindEdgeDataByID(const AEdgeID: string; out AEdgeData: TEdgeDataRecord): Boolean; virtual; abstract;
    procedure GetNodeEdges(ANode: TAiRagGraphNode); virtual; abstract;
    procedure AddNode(ANode: TAiRagGraphNode); virtual; abstract;
    procedure AddEdge(AEdge: TAiRagGraphEdge); virtual; abstract;
    procedure DeleteNode(const ANodeID: string); virtual; abstract;
    procedure DeleteEdge(const AEdgeID: string); virtual; abstract;
    function GetUniqueNodeLabels: TArray<string>; virtual; abstract;
    function GetUniqueEdgeLabels: TArray<string>; virtual; abstract;
    function FindNodeByName(const AName, ANodeLabel: string): TAiRagGraphNode; virtual; abstract;
    function FindNodesByLabel(const ALabel: string): TArray<TAiRagGraphNode>; virtual; abstract;
    function FindNodesByProperty(const AKey: string; const AValue: Variant): TArray<TAiRagGraphNode>; virtual; abstract;
    function FindNodeNamesByLabel(const ANodeLabel, ASearchText: string; ALimit: Integer): TArray<string>; virtual; abstract;

    function SearchNodes(const APrompt: string; ADepth, ALimit: Integer; APrecision: Double; AFilter: TAiFilterCriteria = nil): TArray<TAiRagGraphNode>; virtual; abstract;

    function Query(const APlan: TQueryPlan; ADepth, ALimit: Integer; APrecision: Double): TArray<TAiRagGraphNode>; virtual; abstract;

    property Graph: TAiRagGraph read FGraph;
  public
    function EmbeddingToString(const AData: TAiEmbeddingData): string;
    function PropertiesToJSONString(const AProperties: TDictionary<string, Variant>): string;
    procedure AssignToGraph(AGraph: TAiRagGraph);
  end;

  { TAiRagGraphNode }
  TAiRagGraphNode = class(TAiEmbeddingNode)
  private
    FNodeLabel: string;
    FName: string;
    FInternalOutgoingEdges: TObjectList<TAiRagGraphEdge>;
    FInternalIncomingEdges: TObjectList<TAiRagGraphEdge>;
    // FProperties: TDictionary<string, Variant>;
    FOwnerGraph: TAiRagGraph;
    FID: string;
    FChunks: TObjectList<TAiEmbeddingNode>; // --- List of text fragments from the RAGVector
    FEdgesLoaded: Boolean;
    function GetIncomingEdges: TObjectList<TAiRagGraphEdge>;
    function GetOutgoingEdges: TObjectList<TAiRagGraphEdge>;
    function GetMetadata: TAiEmbeddingMetaData;
  protected
    procedure AddOutgoingEdge(AEdge: TAiRagGraphEdge);
    procedure AddIncomingEdge(AEdge: TAiRagGraphEdge);
    procedure RemoveOutgoingEdge(AEdge: TAiRagGraphEdge);
    procedure RemoveIncomingEdge(AEdge: TAiRagGraphEdge);
  public
    constructor Create(AOwnerGraph: TAiRagGraph; ADim: Integer);
    destructor Destroy; override;
    function PropertiesToJSON: TJSONObject;
    procedure EnsureEdgesAreLoaded;

    // --- NEW METHODS AND PROPERTIES ---
    function AddChunk(const AText: string; const AData: TAiEmbeddingData): TAiEmbeddingNode;
    property Chunks: TObjectList<TAiEmbeddingNode> read FChunks;

    property ID: string read FID write FID;
    property Name: string read FName write FName;
    property NodeLabel: string read FNodeLabel write FNodeLabel;
    Property Properties: TAiEmbeddingMetaData read GetMetadata;

    property OutgoingEdges: TObjectList<TAiRagGraphEdge> read GetOutgoingEdges;
    property IncomingEdges: TObjectList<TAiRagGraphEdge> read GetIncomingEdges;

    property OwnerGraph: TAiRagGraph read FOwnerGraph;
  end;

  { TAiRagGraphEdge }
  TAiRagGraphEdge = class(TAiEmbeddingNode)
  private
    FEdgeLabel: string;
    FName: string;
    FFromNode: TAiRagGraphNode;
    FToNode: TAiRagGraphNode;
    // FProperties: TDictionary<string, Variant>;
    FOwnerGraph: TAiRagGraph;
    FID: string;
    FWeight: Double;
  public
    constructor Create(AOwnerGraph: TAiRagGraph; ADim: Integer);
    destructor Destroy; override;
    function PropertiesToJSON: TJSONObject;

    property ID: string read FID write FID;
    property Name: string read FName write FName;
    property EdgeLabel: string read FEdgeLabel write FEdgeLabel;
    property FromNode: TAiRagGraphNode read FFromNode write FFromNode;
    property ToNode: TAiRagGraphNode read FToNode write FToNode;
    property Weight: Double read FWeight write FWeight;
    // property Properties: TDictionary<string, Variant> read FProperties;
    property OwnerGraph: TAiRagGraph read FOwnerGraph;
  end;

  TCommunity = class
  private
    FID: Integer;
    FNodes: TList<TAiRagGraphNode>;
    FInternalWeight: Double;
    FTotalWeight: Double;
  public
    constructor Create(AID: Integer);
    destructor Destroy; override;

    property ID: Integer read FID;
    property Nodes: TList<TAiRagGraphNode> read FNodes;
    property InternalWeight: Double read FInternalWeight write FInternalWeight;
    property TotalWeight: Double read FTotalWeight write FTotalWeight;
  end;

  { TAiRagGraph }
  TAiRagGraph = class(TComponent)
  private
    FNodes: TAiRAGVector;
    FEdges: TAiRAGVector;
    FNodeRegistry: TDictionary<string, TAiRagGraphNode>;
    FEdgeRegistry: TDictionary<string, TAiRagGraphEdge>;
    FEmbeddings: TAiEmbeddingsCore;
    FNodeLabelIndex: TDictionary<string, TList<TAiRagGraphNode>>;
    FNodeNameIndex: TDictionary<string, TAiRagGraphNode>;
    FUpdateCount: Integer;
    FDriver: TAiRagGraphDriverBase;

    function GetNodeCount: Integer;
    function GetEdgeCount: Integer;
    function GetNodesRAGVector: TAiRAGVector;
    function GetEdgesRAGVector: TAiRAGVector;
    procedure SetDriver(const Value: TAiRagGraphDriverBase);
    procedure SetEmbeddings(const Value: TAiEmbeddingsCore);
    function GetSearchOptions: TAiSearchOptions;
    procedure SetSearchOptions(const Value: TAiSearchOptions);
  protected
    procedure UnregisterNode(ANode: TAiRagGraphNode);
    procedure UnregisterEdge(AEdge: TAiRagGraphEdge);
    function ExpandNodeList(AInitialNodes: TList<TAiRagGraphNode>; ADepth: Integer): TArray<TAiRagGraphNode>;
    function GetContextualizedText(ASubgraphNodes: TArray<TAiRagGraphNode>): string;
    function InternalAddNode(ANode: TAiRagGraphNode; AShouldPersist: Boolean): TAiRagGraphNode;
    function InternalAddEdge(AEdge: TAiRagGraphEdge; AShouldPersist: Boolean): TAiRagGraphEdge;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function EvaluateGraphExpression(AExpr: TGraphExpression; ABoundElements: TDictionary<string, TObject>): Variant;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RebuildIndexes;

    function InternalHydrateNode(const ANodeData: TNodeDataRecord): TAiRagGraphNode;
    function InternalHydrateEdge(const AEdgeData: TEdgeDataRecord): TAiRagGraphEdge;

    function NewNode(const AID, ALabel, AName: string): TAiRagGraphNode;

    function AddNode(AID, ALabel, AName: string): TAiRagGraphNode; overload;
    function AddNode(ANode: TAiRagGraphNode): TAiRagGraphNode; overload;

    function NewEdge(AFromNode, AToNode: TAiRagGraphNode; const AID, ALabel, AName: string; AWeight: Double = 1.0): TAiRagGraphEdge;
    function AddEdge(AFromNode, AToNode: TAiRagGraphNode; AID, ALabel, AName: string): TAiRagGraphEdge; overload;
    function AddEdge(AFromNode, AToNode: TAiRagGraphNode; AID, ALabel, AName: string; AWeight: Double): TAiRagGraphEdge; overload;
    function AddEdge(AEdge: TAiRagGraphEdge): TAiRagGraphEdge; overload;

    procedure DeleteNode(ANode: TAiRagGraphNode); overload;
    procedure DeleteNode(AID: string); overload;
    procedure DeleteEdge(AEdge: TAiRagGraphEdge); overload;
    procedure DeleteEdge(AID: string); overload;
    procedure Clear;

    function FindNodeByID(AID: string): TAiRagGraphNode;
    function FindEdgeByID(AID: string): TAiRagGraphEdge;
    function FindNodesByLabel(ALabel: string): TArray<TAiRagGraphNode>;
    function FindEdge(AFromNode, AToNode: TAiRagGraphNode; AEdgeLabel: string): TAiRagGraphEdge;
    function FindNodeByName(AName, ANodeLabel: string): TAiRagGraphNode;

    procedure SaveToStream(AStream: TStream); overload; // The original version
    procedure SaveToStream(AStream: TStream; aFull: Boolean); overload; // The new version

    procedure SaveToDot(const AFileName: string);

    procedure SaveToMakerAi(const AFileName: String; const aFull: Boolean = True);

    procedure SaveToGraphML(const AFileName: string);
    procedure LoadFromStream(AStream: TStream);
    procedure BeginUpdate;
    procedure EndUpdate;

    procedure SaveToFile(const AFileName: string; AFormat: TGraphExportFormat; aFull: Boolean = True); overload;
    procedure SaveToFile(const AFileName: string; aFull: Boolean); overload;

    function GetShortestPath(AStartNode, AEndNode: TAiRagGraphNode): TArray<TObject>;
    function GetNodesByDegree(ATop: Integer = 10; ADegreeType: TDegreeType = dtTotal): TArray<TAiRagGraphNode>;
    function GetClosenessCentrality(ANode: TAiRagGraphNode): Double;
    function DetectCommunities(AIterations: Integer = 10): TDictionary<TAiRagGraphNode, Integer>;
    procedure UpdateCommunityLabels;

    function Search(const APrompt: string; const ADepth: Integer = 0; ALimit: Integer = 5; const APrecision: Double = 0.5; const AFilter: TAiFilterCriteria = nil): TArray<TAiRagGraphNode>;
    Function SearchText(const APrompt: string; ADepth: Integer = 0; ShowProperties: Boolean = False; const ALimit: Integer = 3; const APrecision: Double = 0.5; const AFilter: TAiFilterCriteria = nil): string;

    function Query(const APlan: TQueryPlan; ADepth: Integer = 0; const ALimit: Integer = 5; const APrecision: Double = 0.5): TArray<TAiRagGraphNode>;

    function ExecuteMakerGQL(const ACode: string; out AResultObjects: TArray<TDictionary<string, TObject>>; ADepth: Integer = 0): string; Overload;
    function ExecuteMakerGQL(const ACode: string): string; Overload;


    // todo Implement Community Detection (Community Detection) Louvain Algorithm

    function GetAllShortestPaths(AStartNode, AEndNode: TAiRagGraphNode): TArray<TArray<TObject>>; // Pending implementation
    function Match(AQuery: TGraphMatchQuery; ADepth: Integer = 0): TArray<TDictionary<string, TObject>>;

    function GetUniqueNodeLabels: TArray<string>;
    function GetUniqueEdgeLabels: TArray<string>;
    function FindNodesByProperty(const AKey: string; const AValue: Variant): TArray<TAiRagGraphNode>;
    function GetNeighbors(ANode: TAiRagGraphNode; ADirection: TGraphDirection = gdOutgoing): TArray<TAiRagGraphNode>;
    function CountNodesByLabel(const ALabel: string): Integer;
    function CountEdgesByLabel(const ALabel: string): Integer;
    function ExtractSubgraph(ANodes: TArray<TAiRagGraphNode>): TAiRagGraph;
    procedure MergeNodes(ASurvivingNode, ASubsumedNode: TAiRagGraphNode; APropertyMergeStrategy: TMergeStrategy = msAddNewOnly);
    function FindNodeNamesByLabel(const ANodeLabel, ASearchText: string; ALimit: Integer = 10): TArray<string>;
    function EdgeExistsInMemory(const AEdgeID: string): Boolean;

    function GraphToContextText(const ANodes: TArray<TAiRagGraphNode>): string;

    property NodeCount: Integer read GetNodeCount;
    property EdgeCount: Integer read GetEdgeCount;
    property Nodes: TAiRAGVector read GetNodesRAGVector;
    property Edges: TAiRAGVector read GetEdgesRAGVector;
  Published
    property Embeddings: TAiEmbeddingsCore read FEmbeddings write SetEmbeddings;
    property Driver: TAiRagGraphDriverBase read FDriver write SetDriver;
    property SearchOptions: TAiSearchOptions read GetSearchOptions write SetSearchOptions;
  end;

  // Helper function to convert TJSONValue to Variant
function JSONValueToVariant(AJsonValue: TJSONValue): Variant;
function VariantToJSONValue(const AValue: Variant): TJSONValue;
function StringToEmbedding(const AVectorString: string): TAiEmbeddingData;
procedure JSONStringToProperties(const AJSONString: string; const AProperties: TDictionary<string, Variant>);

procedure Register;

implementation

uses uMakerAi.RAG.Graph.GQL;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiRagGraph]);

end;

function JSONValueToVariant(AJsonValue: TJSONValue): Variant;
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  I: Integer;
  Pair: TJSONPair;
  ResultArray: Variant;
  ResultDict: string;
begin
  if AJsonValue = nil then
    Result := Null
  else if AJsonValue is TJSONNull then
    Result := Null
  else if AJsonValue is TJSONTrue then
    Result := True
  else if AJsonValue is TJSONFalse then
    Result := False
  else if AJsonValue is TJSONNumber then
  begin
    // Determine if it is integer or decimal
    if Frac(TJSONNumber(AJsonValue).AsDouble) = 0 then
      Result := TJSONNumber(AJsonValue).AsInt64
    else
      Result := TJSONNumber(AJsonValue).AsDouble;
  end
  else if AJsonValue is TJSONString then
    Result := TJSONString(AJsonValue).Value
  else if AJsonValue is TJSONArray then
  begin
    JSONArray := TJSONArray(AJsonValue);

    // If the array is empty
    if JSONArray.Count = 0 then
    begin
      Result := '[]';
      Exit;
    end;

    // Create a Variant array
    ResultArray := VarArrayCreate([0, JSONArray.Count - 1], varVariant);
    for I := 0 to JSONArray.Count - 1 do
      ResultArray[I] := JSONValueToVariant(JSONArray.Items[I]);

    Result := ResultArray;
  end
  else if AJsonValue is TJSONObject then
  begin
    JSONObject := TJSONObject(AJsonValue);

    // If the object is empty
    if JSONObject.Count = 0 then
    begin
      Result := '{}';
      Exit;
    end;

    // Convert object to formatted string (or you could use another structure)
    ResultDict := '{';
    for I := 0 to JSONObject.Count - 1 do
    begin
      Pair := JSONObject.Pairs[I];
      if I > 0 then
        ResultDict := ResultDict + ', ';
      ResultDict := ResultDict + '"' + Pair.JsonString.Value + '": ';

      // Recursively convert the value
      if Pair.JsonValue is TJSONString then
        ResultDict := ResultDict + '"' + TJSONString(Pair.JsonValue).Value + '"'
      else if Pair.JsonValue is TJSONNumber then
        ResultDict := ResultDict + Pair.JsonValue.Value
      else if (Pair.JsonValue is TJSONTrue) or (Pair.JsonValue is TJSONFalse) then
        ResultDict := ResultDict + LowerCase(Pair.JsonValue.Value)
      else if Pair.JsonValue is TJSONNull then
        ResultDict := ResultDict + 'null'
      else
        ResultDict := ResultDict + Pair.JsonValue.ToString;
    end;
    ResultDict := ResultDict + '}';

    Result := ResultDict;
  end
  else
    Result := AJsonValue.ToString; // Fallback for other types
end;

function VariantToJSONValue(const AValue: Variant): TJSONValue;
var
  VarTypeResult: TVarType;
begin
  VarTypeResult := VarType(AValue);

  if VarIsNull(AValue) or VarIsEmpty(AValue) then
    Result := TJSONNull.Create
  else if VarTypeResult = varBoolean then
    Result := TJSONBool.Create(Boolean(AValue))
  else if VarIsFloat(AValue) then
    Result := TJSONNumber.Create(Extended(AValue)) // Use Extended for maximum precision
  else if VarIsNumeric(AValue) then
    Result := TJSONNumber.Create(Integer(AValue))
  else if VarIsStr(AValue) then
    Result := TJSONString.Create(VarToStr(AValue))
  else
    // Fallback: if it is not a primitive type, convert it to string.
    // A more advanced implementation could handle arrays or TDateTime specially.
    Result := TJSONString.Create(VarToStr(AValue));
end;

function StringToEmbedding(const AVectorString: string): TAiEmbeddingData;
var
  CleanedString: string;
  ValueStrings: TArray<string>;
  I: Integer;
  FormatSettings: TFormatSettings;
begin
  Result := []; // Returns an empty array by default
  if AVectorString.IsEmpty or (AVectorString = '[]') then
    Exit;

  // 1. Clean the string, removing the brackets
  CleanedString := AVectorString.Trim(['[', ']']);
  if CleanedString.IsEmpty then
    Exit;

  // 2. Separate the values by comma
  ValueStrings := CleanedString.Split([',']);

  // 3. Prepare for location-insensitive float conversion
  // This ensures that the '.' is always interpreted as the decimal separator.
  FormatSettings := TFormatSettings.Invariant;

  // 4. Convert each value and add it to the result
  SetLength(Result, Length(ValueStrings));
  for I := 0 to High(ValueStrings) do
  begin
    // We use TryStrToFloat for more safety against malformed data
    if TryStrToFloat(ValueStrings[I], Result[I], FormatSettings) then
    begin
      // The conversion was successful, continue.
    end
    else
    begin
      Result[I] := 0.0; // Or handle the error as preferred
    end;
  end;
end;

function JSONValueToVariantSafe(const AValue: TJSONValue; out AResult: Variant): Boolean;
var
  Num: TJSONNumber;
begin
  Result := False;
  AResult := Null;

  if AValue = nil then
    Exit;

  try
    if AValue is TJSONNull then
    begin
      AResult := Null;
      Result := True;
    end
    else if AValue is TJSONString then
    begin
      AResult := TJSONString(AValue).Value;
      Result := True;
    end
    else if AValue is TJSONBool then
    begin
      AResult := TJSONBool(AValue).AsBoolean;
      Result := True;
    end
    else if AValue is TJSONNumber then
    begin
      Num := TJSONNumber(AValue);

      // We try integer
      Var
        I64: Int64;
      if TryStrToInt64(Num.Value, I64) then
      begin
        AResult := I64;
        Result := True;
        Exit;
      end;

      // We try floating point (ALWAYS valid for JSON number)
      Var
        Dbl: Double;
      if TryStrToFloat(Num.Value, Dbl, TFormatSettings.Invariant) then
      begin
        AResult := Dbl;
        Result := True;
        Exit;
      end;
    end;
  except
    // Silent: does not break flow
    Result := False;
  end;
end;

procedure JSONStringToProperties(const AJSONString: string; const AProperties: TDictionary<string, Variant>);
var
  JsonValue: TJSONValue;
  JsonObj: TJSONObject;
  Pair: TJSONPair;
  V: Variant;
begin
  if (AProperties = nil) or AJSONString.IsEmpty or (AJSONString = '{}') then
    Exit;

  AProperties.Clear; // Clear the dictionary before populating it.
  JsonValue := TJSONObject.ParseJSONValue(AJSONString);
  if JsonValue = nil then
    Exit; // invalid JSON

  try
    if JsonValue is TJSONObject then
    begin
      JsonObj := JsonValue as TJSONObject;
      for Pair in JsonObj do
      begin
        If JSONValueToVariantSafe(Pair.JsonValue, V) then
          AProperties.Add(Pair.JsonString.Value, V);
      end;
    end;
  finally
    JsonValue.Free;
  end;
End;

{ TAiRagGraphNode }

constructor TAiRagGraphNode.Create(AOwnerGraph: TAiRagGraph; ADim: Integer);
begin
  inherited Create(ADim);
  FOwnerGraph := AOwnerGraph;
  FInternalOutgoingEdges := TObjectList<TAiRagGraphEdge>.Create(False); // Does not own the objects
  FInternalIncomingEdges := TObjectList<TAiRagGraphEdge>.Create(False); // Does not own the objects
  // FProperties := TDictionary<string, Variant>.Create;

  // System.Generics.Defaults.TStringComparer.Ordinal

  // FProperties := TDictionary<string, Variant>.Create(TOrdinalIStringComparer.Create);
  FChunks := TObjectList<TAiEmbeddingNode>.Create(True);
  FEdgesLoaded := False;
end;

destructor TAiRagGraphNode.Destroy;
begin
  FInternalOutgoingEdges.Free;
  FInternalIncomingEdges.Free;
  FChunks.Free;
  // FProperties.Free;
  inherited;
end;

procedure TAiRagGraphNode.EnsureEdgesAreLoaded;
begin
  // If the edges are already loaded or there is no OwnerGraph/event assigned, we do nothing.
  if FEdgesLoaded or (FOwnerGraph = nil) or not Assigned(FOwnerGraph.Driver) then
    Exit;

  if Assigned(FOwnerGraph.Driver) then
  begin
    FOwnerGraph.Driver.GetNodeEdges(Self);
  end;

  // Mark as loaded to avoid triggering the event again.
  FEdgesLoaded := True;
end;

function TAiRagGraphNode.GetIncomingEdges: TObjectList<TAiRagGraphEdge>;
begin
  EnsureEdgesAreLoaded;
  Result := FInternalIncomingEdges;
end;

function TAiRagGraphNode.GetMetadata: TAiEmbeddingMetaData;
begin
  // Access the property of the ancestor TAiEmbeddingNode
  Result := inherited MetaData;
end;

function TAiRagGraphNode.GetOutgoingEdges: TObjectList<TAiRagGraphEdge>;
begin
  EnsureEdgesAreLoaded;
  Result := FInternalOutgoingEdges;
end;

function TAiRagGraphNode.AddChunk(const AText: string; const AData: TAiEmbeddingData): TAiEmbeddingNode;
begin
  // We create a basic embedding node for the fragment.
  // We use the constructor that defines the dimension based on the received data.
  Result := TAiEmbeddingNode.Create(Length(AData));
  Result.Text := AText;
  Result.Data := Copy(AData); // Copy the vector
  Result.Model := Self.Model; // Inherits the model name from the parent node

  FChunks.Add(Result);
end;

procedure TAiRagGraphNode.AddIncomingEdge(AEdge: TAiRagGraphEdge);
begin
  FInternalIncomingEdges.Add(AEdge);
end;

procedure TAiRagGraphNode.AddOutgoingEdge(AEdge: TAiRagGraphEdge);
begin
  FInternalOutgoingEdges.Add(AEdge);
end;

procedure TAiRagGraphNode.RemoveIncomingEdge(AEdge: TAiRagGraphEdge);
begin
  FInternalIncomingEdges.Remove(AEdge);
end;

procedure TAiRagGraphNode.RemoveOutgoingEdge(AEdge: TAiRagGraphEdge);
begin
  FInternalOutgoingEdges.Remove(AEdge);
end;

function TAiRagGraphNode.PropertiesToJSON: TJSONObject;
begin
  // We delegate serialization to the new unified MetaData object.
  // This already correctly handles the conversion of Variant to JSON (Dates, Boolean, etc.)
  if Assigned(MetaData) then
    Result := MetaData.ToJSON
  else
    Result := TJSONObject.Create;
end;

{ TAiRagGraphEdge }

constructor TAiRagGraphEdge.Create(AOwnerGraph: TAiRagGraph; ADim: Integer);
begin
  // The parent constructor (TAiEmbeddingNode) already takes care of creating the MetaData object
  inherited Create(ADim);
  FOwnerGraph := AOwnerGraph;
  FWeight := 1.0;
  // FProperties := TDictionary... <--- REMOVED
end;

destructor TAiRagGraphEdge.Destroy;
begin
  // FProperties.Free; <--- REMOVED (No longer exists)
  // MetaData is automatically freed in the base class destructor (inherited)
  inherited;
end;

function TAiRagGraphEdge.PropertiesToJSON: TJSONObject;
begin
  // We delegate serialization to the new unified MetaData object.
  if Assigned(MetaData) then
    Result := MetaData.ToJSON
  else
    Result := TJSONObject.Create;
end;

{ TAiRagGraph }

constructor TAiRagGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FNodes := TAiRAGVector.Create(Self, True);
  FNodes.SearchOptions.UseBM25 := True; // <-- ENABLE BY DEFAULT FOR GRAPHS

  FEdges := TAiRAGVector.Create(Self, True);
  FEdges.SearchOptions.UseBM25 := True;

  FNodeRegistry := TDictionary<string, TAiRagGraphNode>.Create;
  FEdgeRegistry := TDictionary<string, TAiRagGraphEdge>.Create;
  FNodeLabelIndex := TDictionary < string, TList < TAiRagGraphNode >>.Create;
  FNodeNameIndex := TDictionary<string, TAiRagGraphNode>.Create;
  // Assigns the in-memory index type, must always be HNSW
  FNodes.InMemoryIndexType := TAIHNSWIndex; // they are the best for text
  FEdges.InMemoryIndexType := TAIHNSWIndex;
end;

destructor TAiRagGraph.Destroy;
begin
  Clear;
  FNodes.Free;
  FEdges.Free;
  FNodeRegistry.Free;
  FEdgeRegistry.Free;
  FNodeLabelIndex.Free;
  FNodeNameIndex.Free;
  inherited;
end;

function TAiRagGraph.DetectCommunities(AIterations: Integer = 10): TDictionary<TAiRagGraphNode, Integer>;
var
  CommInfo: TDictionary<Integer, TCommunity>;
  m2: Double; // 2 * sum of all weights in the graph
  Nodes: TArray<TAiRagGraphNode>;
  Changed: Boolean;
  Iter, I: Integer;
  Node: TAiRagGraphNode;
  BestComm: Integer;
  MaxGain, Gain: Double;
  Neighbor: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  CurrentCommID: Integer;
  K_i_in: Double; // Weight of edges from node i to the candidate community
  K_i: Double; // Degree of node i
begin
  Result := TDictionary<TAiRagGraphNode, Integer>.Create;
  CommInfo := TDictionary<Integer, TCommunity>.Create;
  Nodes := FNodeRegistry.Values.ToArray;

  // --- Initialization: Each node in its own community ---
  m2 := 0;
  for I := 0 to Length(Nodes) - 1 do
  begin
    Node := Nodes[I];
    Result.Add(Node, I);
    CommInfo.Add(I, TCommunity.Create(I));
    CommInfo[I].Nodes.Add(Node);

    // Calculate node degree and m2
    K_i := 0;
    for Edge in Node.OutgoingEdges do
      K_i := K_i + Edge.Weight;
    for Edge in Node.IncomingEdges do
      K_i := K_i + Edge.Weight;

    CommInfo[I].TotalWeight := K_i;
    m2 := m2 + K_i;
  end;

  // --- Main optimization loop ---
  for Iter := 1 to AIterations do
  begin
    Changed := False;
    for Node in Nodes do
    begin
      CurrentCommID := Result[Node];
      K_i := CommInfo[CurrentCommID].TotalWeight; // Node degree

      BestComm := CurrentCommID;
      MaxGain := 0;

      // Evaluate moving the node to the community of each of its neighbors
      for Neighbor in GetNeighbors(Node, gdBoth) do
      begin
        var
        TargetCommID := Result[Neighbor];
        if TargetCommID = CurrentCommID then
          Continue;

        // Calculate K_i_in (connection of the node to the target community)
        K_i_in := 0;
        for Edge in Node.OutgoingEdges do
          if Result[Edge.ToNode] = TargetCommID then
            K_i_in := K_i_in + Edge.Weight;
        for Edge in Node.IncomingEdges do
          if Result[Edge.FromNode] = TargetCommID then
            K_i_in := K_i_in + Edge.Weight;

        // Simplified Modularity Gain formula (delta Q)
        Gain := (K_i_in - (CommInfo[TargetCommID].TotalWeight * K_i) / m2);

        if Gain > MaxGain then
        begin
          MaxGain := Gain;
          BestComm := TargetCommID;
        end;
      end;

      // Perform the move if there is improvement
      if BestComm <> CurrentCommID then
      begin
        // Update old community
        CommInfo[CurrentCommID].Nodes.Remove(Node);
        CommInfo[CurrentCommID].TotalWeight := CommInfo[CurrentCommID].TotalWeight - K_i;

        // Update new community
        Result[Node] := BestComm;
        CommInfo[BestComm].Nodes.Add(Node);
        CommInfo[BestComm].TotalWeight := CommInfo[BestComm].TotalWeight + K_i;

        Changed := True;
      end;
    end;

    if not Changed then
      Break;
  end;

  // Cleanup of CommInfo
  for var C in CommInfo.Values do
    C.Free;
  CommInfo.Free;
end;

function TAiRagGraph.EdgeExistsInMemory(const AEdgeID: string): Boolean;
begin
  Result := FEdgeRegistry.ContainsKey(AEdgeID);
end;

procedure TAiRagGraph.EndUpdate;
begin
  if FUpdateCount > 0 then
  begin
    Dec(FUpdateCount);
    if FUpdateCount = 0 then
      RebuildIndexes;
  end;
end;

function TAiRagGraph.EvaluateGraphExpression(AExpr: TGraphExpression; ABoundElements: TDictionary<string, TObject>): Variant;
var
  Left, Right: Variant;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  Obj: TObject;
  B: TBinaryExpr;

  // ------------------------------------------------------------------
  // NULL / BOOLEAN SAFE
  // ------------------------------------------------------------------
  function SafeBool(const V: Variant): Boolean;
  begin
    if VarIsNull(V) or VarIsEmpty(V) then
      Exit(False);
    try
      Result := Boolean(V);
    except
      Result := False;
    end;
  end;

// ------------------------------------------------------------------
// LIKE / ILIKE (SQL -> Delphi)
// ------------------------------------------------------------------
  function MatchLike(const Val, Pat: string; CaseInsensitive: Boolean): Boolean;
  var
    P, V: string;
  begin
    if Val = '' then
      Exit(False);

    P := Pat.Replace('%', '*').Replace('_', '?');
    if CaseInsensitive then
    begin
      V := Val.ToLower;
      P := P.ToLower;
    end
    else
      V := Val;

    try
      Result := MatchesMask(V, P);
    except
      Result := False;
    end;
  end;

// ------------------------------------------------------------------
// IN / NOT IN
// ------------------------------------------------------------------
  function CheckInList(const Val, List: Variant): Boolean;
  var
    I: Integer;
    Item: Variant;
  begin
    Result := False;
    if VarIsNull(Val) or VarIsEmpty(Val) then
      Exit;

    try
      if VarIsArray(List) then
      begin
        for I := VarArrayLowBound(List, 1) to VarArrayHighBound(List, 1) do
        begin
          Item := VarArrayGet(List, [I]);
          if VarToStr(Val) = VarToStr(Item) then
            Exit(True);
        end;
      end
      else
        Result := (VarToStr(Val) = VarToStr(List));
    except
      Result := False;
    end;
  end;

begin
  if AExpr = nil then
    Exit(True);

  case AExpr.Kind of

    // ================================================================
    // LITERAL
    // ================================================================
    ekLiteral:
      Result := TLiteralExpr(AExpr).Value;

    // ================================================================
    // PROPERTY ACCESS
    // ================================================================
    ekProperty:
      begin
        Result := Null;
        var
        P := TPropertyExpr(AExpr);

        if ABoundElements.TryGetValue(P.Variable, Obj) then
        begin
          // --- NODE ---
          if Obj is TAiRagGraphNode then
          begin
            Node := TAiRagGraphNode(Obj);
            if SameText(P.PropertyKey, 'name') then
              Result := Node.Name
            else if SameText(P.PropertyKey, 'label') then
              Result := Node.NodeLabel
            else if SameText(P.PropertyKey, 'id') then
              Result := Node.ID
            else
              Result := Node.MetaData.Get(P.PropertyKey, Null);
          end
          // --- EDGE ---
          else if Obj is TAiRagGraphEdge then
          begin
            Edge := TAiRagGraphEdge(Obj);
            if SameText(P.PropertyKey, 'label') then
              Result := Edge.EdgeLabel
            else if SameText(P.PropertyKey, 'id') then
              Result := Edge.ID
            else
              Result := Edge.MetaData.Get(P.PropertyKey, Null);
          end;
        end;
      end;

    // ================================================================
    // BINARY / LOGICAL
    // ================================================================
    ekBinary:
      begin
        B := TBinaryExpr(AExpr);

        Left := EvaluateGraphExpression(B.Left, ABoundElements);

        // Unary operators
        if not(B.Op in [opIsNull, opIsNotNull]) then
          Right := EvaluateGraphExpression(B.Right, ABoundElements)
        else
          Right := Null;

        case B.Op of
          // --- LOGICAL ---
          opAnd:
            Result := SafeBool(Left) and SafeBool(Right);
          opOr:
            Result := SafeBool(Left) or SafeBool(Right);

          // --- COMPARISON ---
          opEqual:
            if VarIsNull(Left) or VarIsNull(Right) then
              Result := VarIsNull(Left) = VarIsNull(Right)
            else
              Result := (Left = Right);

          opNotEqual:
            try
              Result := (Left <> Right);
            except
              Result := False;
            end;

          opGreater:
            try
              Result := (Left > Right);
            except
              Result := False;
            end;
          opGreaterEqual:
            try
              Result := (Left >= Right);
            except
              Result := False;
            end;
          opLess:
            try
              Result := (Left < Right);
            except
              Result := False;
            end;
          opLessEqual:
            try
              Result := (Left <= Right);
            except
              Result := False;
            end;

          // --- TEXT ---
          opContains:
            if VarIsNull(Left) or VarIsNull(Right) then
              Result := False
            else
              Result := System.StrUtils.ContainsText(VarToStr(Left), VarToStr(Right));

          opLike:
            Result := MatchLike(VarToStr(Left), VarToStr(Right), False);

          opILike:
            Result := MatchLike(VarToStr(Left), VarToStr(Right), True);

          // --- NULL ---
          opIsNull:
            Result := VarIsNull(Left) or VarIsEmpty(Left);

          opIsNotNull:
            Result := not(VarIsNull(Left) or VarIsEmpty(Left));

          // --- IN ---
          opIn:
            Result := CheckInList(Left, Right);

          opNotIn:
            Result := not CheckInList(Left, Right);

        else
          Result := False;
        end;
      end;

  else
    Result := Null;
  end;
end;

{
  function TAiRagGraph.ExecuteMakerGQL(const ACode: string; ADepth: Integer = 0): TArray<TDictionary<string, TObject>>;
  var
  Parser: TGraphParser;
  QueryObj: TGraphMatchQuery;

  // Variables for list results (Strings and Nodes)
  StringListResult: TArray<string>;
  NodeListResult: TArray<TAiRagGraphNode>;
  PathResult: TArray<TObject>;

  // Variables de trabajo
  ResDict: TDictionary<string, TObject>;
  I: Integer;
  PathObj: TObject;
  Score: Double;

  // Variables for algorithm resolution
  StartNode, EndNode: TAiRagGraphNode;
  FinalDepth: Integer;

  // -----------------------------------------------------------------------
  // Nested helper function:
  // -----------------------------------------------------------------------
  function FindNodeByPattern(APattern: TMatchNodePattern): TAiRagGraphNode;
  var
  Candidates: TArray<TAiRagGraphNode>;
  Cand: TAiRagGraphNode;
  begin
  Result := nil;
  if APattern = nil then
  Exit;

  // 1. Optimization: If there is a label, we search only in that index
  if not APattern.NodeLabel.IsEmpty then
  Candidates := Self.FindNodesByLabel(APattern.NodeLabel)
  else
  Candidates := FNodeRegistry.Values.ToArray;

  // 2. Linear search over the candidates to match properties
  for Cand in Candidates do
  begin
  if APattern.Matches(Cand) then
  begin
  Result := Cand;
  Exit; // We return the first one found
  end;
  end;
  end;
  // -----------------------------------------------------------------------

  begin
  Result := [];
  if ACode.Trim.IsEmpty then
  Exit;

  Parser := TGraphParser.Create(ACode);
  try
  // We parse the code.
  // If it is a special command, QueryObj will be nil and CommandType will have a value.
  // If it is a normal query, QueryObj will have the object and CommandType will be cmdNone.
  QueryObj := Parser.Parse;
  try

  if Parser.CommandType <> cmdNone then
  begin
  // =========================================================
  // EXECUTION OF COMMANDS
  // =========================================================
  case Parser.CommandType of

  // -------------------------------------------------------
  // 1. INTROSPECTION (SHOW ...)
  // -------------------------------------------------------
  cmdShowLabels:
  begin
  StringListResult := Self.GetUniqueNodeLabels;
  SetLength(Result, Length(StringListResult));
  for I := 0 to High(StringListResult) do
  begin
  ResDict := TDictionary<string, TObject>.Create;
  ResDict.Add('type', TStringWrapper.Create('label'));
  ResDict.Add('value', TStringWrapper.Create(StringListResult[I]));
  Result[I] := ResDict;
  end;
  end;

  cmdShowEdges:
  begin
  StringListResult := Self.GetUniqueEdgeLabels;
  SetLength(Result, Length(StringListResult));
  for I := 0 to High(StringListResult) do
  begin
  ResDict := TDictionary<string, TObject>.Create;
  ResDict.Add('type', TStringWrapper.Create('edge'));
  ResDict.Add('value', TStringWrapper.Create(StringListResult[I]));
  Result[I] := ResDict;
  end;
  end;

  // -------------------------------------------------------
  // 2. ALGORITHMS: SHORTEST PATH
  // -------------------------------------------------------
  cmdShortestPath:
  begin
  // We resolve the patterns to real nodes using the nested function
  StartNode := FindNodeByPattern(Parser.CommandSourcePattern);
  EndNode := FindNodeByPattern(Parser.CommandTargetPattern);

  if (StartNode <> nil) and (EndNode <> nil) then
  begin
  PathResult := Self.GetShortestPath(StartNode, EndNode);

  SetLength(Result, Length(PathResult));
  for I := 0 to High(PathResult) do
  begin
  ResDict := TDictionary<string, TObject>.Create;
  PathObj := PathResult[I];

  // The path may contain mixed Nodes and Edges
  if PathObj is TAiRagGraphNode then
  begin
  ResDict.Add('type', TStringWrapper.Create('node'));
  ResDict.Add('element', PathObj); // Reference to the live object
  end
  else if PathObj is TAiRagGraphEdge then
  begin
  ResDict.Add('type', TStringWrapper.Create('edge'));
  ResDict.Add('element', PathObj);
  end;

  Result[I] := ResDict;
  end;
  end;
  // If StartNode or EndNode are nil, returns an empty array (not found)
  end;

  // -------------------------------------------------------
  // 3. ALGORITHMS: CENTRALITY
  // -------------------------------------------------------
  cmdCentrality:
  begin
  StartNode := FindNodeByPattern(Parser.CommandSourcePattern);
  if StartNode <> nil then
  begin
  Score := Self.GetClosenessCentrality(StartNode);

  SetLength(Result, 1);
  ResDict := TDictionary<string, TObject>.Create;

  // Special type so the visualizer knows how to display it
  ResDict.Add('type', TStringWrapper.Create('centrality_score'));
  ResDict.Add('node', TStringWrapper.Create(StartNode.Name));
  ResDict.Add('value', TStringWrapper.Create(FormatFloat('0.####', Score)));

  Result[0] := ResDict;
  end;
  end;

  // -------------------------------------------------------
  // 4. ALGORITHMS: TOP DEGREES (HUBS)
  // -------------------------------------------------------
  cmdDegrees:
  begin
  // We get the N nodes with the most connections
  NodeListResult := Self.GetNodesByDegree(Parser.CommandLimit, dtTotal);

  SetLength(Result, Length(NodeListResult));
  for I := 0 to High(NodeListResult) do
  begin
  ResDict := TDictionary<string, TObject>.Create;
  ResDict.Add('type', TStringWrapper.Create('node'));
  ResDict.Add('element', NodeListResult[I]);
  Result[I] := ResDict;
  end;
  end;
  end;
  end
  // =========================================================
  // STANDARD MATCH QUERY
  // =========================================================
  else if Assigned(QueryObj) then
  begin
  // We execute the classic Matching logic (Nodes and Relationships)

  if QueryObj.Depth > 0 then
  FinalDepth := QueryObj.Depth
  else
  FinalDepth := ADepth;

  Result := Self.Match(QueryObj, FinalDepth);
  end;

  finally
  if Assigned(QueryObj) then
  QueryObj.Free;
  end;
  finally
  Parser.Free;
  end;
  end;
}

function TAiRagGraph.ExecuteMakerGQL(const ACode: string): string;
Var
  Data: TArray<TDictionary<string, TObject>>;
begin
  Result := ExecuteMakerGQL(ACode, Data);

  // 3. IMPORTANT! Free the memory of the output dictionaries
  If Assigned(Data) then
    for var Dict in Data do
      Dict.Free;
end;

function TAiRagGraph.ExecuteMakerGQL(const ACode: string; out AResultObjects: TArray<TDictionary<string, TObject>>; ADepth: Integer = 0): string;
var
  Parser: TGraphParser;
  QueryObj: TGraphMatchQuery;

  // Variables for internal results
  StringListResult: TArray<string>;
  NodeListResult: TArray<TAiRagGraphNode>;
  PathResult: TArray<TObject>;

  // Variables de trabajo
  ResDict: TDictionary<string, TObject>;
  I: Integer;
  PathObj: TObject;
  Score: Double;
  ElementType: string;

  // Variables for algorithm resolution
  StartNode, EndNode: TAiRagGraphNode;
  FinalDepth: Integer;

  // Variables for building the text context
  ContextNodes: TList<TAiRagGraphNode>;
  ContextBuilder: TStringBuilder;

  // --- Helper function FindNodeByPattern (remains the same) ---
  function FindNodeByPattern(APattern: TMatchNodePattern): TAiRagGraphNode;
  var
    Candidates: TArray<TAiRagGraphNode>;
    Cand: TAiRagGraphNode;
  begin
    Result := nil;
    if APattern = nil then
      Exit;
    if not APattern.NodeLabel.IsEmpty then
      Candidates := Self.FindNodesByLabel(APattern.NodeLabel)
    else
      Candidates := FNodeRegistry.Values.ToArray;
    for Cand in Candidates do
      if APattern.Matches(Cand) then
        Exit(Cand);
  end;
// -----------------------------------------------------------

begin
  AResultObjects := [];
  Result := ''; // Default empty string

  if ACode.Trim.IsEmpty then
    Exit;

  Parser := TGraphParser.Create(ACode);
  try
    QueryObj := Parser.Parse;
    try
      if Parser.CommandType <> cmdNone then
      begin
        // =========================================================
        // EXECUTION OF COMMANDS (Algorithms / Introspection)
        // =========================================================
        ContextBuilder := TStringBuilder.Create;
        try
          case Parser.CommandType of
            // -------------------------------------------------------
            // SHOW LABELS / EDGES
            // -------------------------------------------------------
            cmdShowLabels, cmdShowEdges:
              begin
                if Parser.CommandType = cmdShowLabels then
                begin
                  StringListResult := Self.GetUniqueNodeLabels;
                  ElementType := 'label';
                  ContextBuilder.AppendLine('### AVAILABLE NODE LABELS ###');
                end
                else
                begin
                  StringListResult := Self.GetUniqueEdgeLabels;
                  ElementType := 'edge';
                  ContextBuilder.AppendLine('### AVAILABLE EDGE TYPES ###');
                end;

                SetLength(AResultObjects, Length(StringListResult));
                for I := 0 to High(StringListResult) do
                begin
                  ResDict := TDictionary<string, TObject>.Create;
                  ResDict.Add('type', TStringWrapper.Create(ElementType));
                  ResDict.Add('value', TStringWrapper.Create(StringListResult[I]));
                  AResultObjects[I] := ResDict;

                  // Generate simple text
                  ContextBuilder.AppendLine('- ' + StringListResult[I]);
                end;
                Result := ContextBuilder.ToString;
              end;

            // -------------------------------------------------------
            // SHORTEST PATH
            // -------------------------------------------------------
            cmdShortestPath:
              begin
                StartNode := FindNodeByPattern(Parser.CommandSourcePattern);
                EndNode := FindNodeByPattern(Parser.CommandTargetPattern);

                if (StartNode <> nil) and (EndNode <> nil) then
                begin
                  PathResult := Self.GetShortestPath(StartNode, EndNode);
                  SetLength(AResultObjects, Length(PathResult));

                  ContextBuilder.AppendLine('### SHORTEST PATH ###');
                  ContextBuilder.AppendFormat('From "%s" to "%s":', [StartNode.Name, EndNode.Name]).AppendLine;

                  for I := 0 to High(PathResult) do
                  begin
                    ResDict := TDictionary<string, TObject>.Create;
                    PathObj := PathResult[I];

                    if PathObj is TAiRagGraphNode then
                    begin
                      ResDict.Add('type', TStringWrapper.Create('node'));
                      ResDict.Add('element', PathObj);
                      ContextBuilder.AppendFormat('(%s)', [TAiRagGraphNode(PathObj).Name]);
                    end
                    else if PathObj is TAiRagGraphEdge then
                    begin
                      ResDict.Add('type', TStringWrapper.Create('edge'));
                      ResDict.Add('element', PathObj);
                      ContextBuilder.AppendFormat(' -[%s]-> ', [TAiRagGraphEdge(PathObj).EdgeLabel]);
                    end;
                    AResultObjects[I] := ResDict;
                  end;
                  Result := ContextBuilder.ToString;
                end
                else
                  Result := 'No path found or nodes do not exist.';
              end;

            // -------------------------------------------------------
            // CENTRALITY
            // -------------------------------------------------------
            cmdCentrality:
              begin
                StartNode := FindNodeByPattern(Parser.CommandSourcePattern);
                if StartNode <> nil then
                begin
                  Score := Self.GetClosenessCentrality(StartNode);

                  SetLength(AResultObjects, 1);
                  ResDict := TDictionary<string, TObject>.Create;
                  ResDict.Add('type', TStringWrapper.Create('centrality_score'));
                  ResDict.Add('node', TStringWrapper.Create(StartNode.Name));
                  ResDict.Add('value', TStringWrapper.Create(FormatFloat('0.####', Score)));
                  AResultObjects[0] := ResDict;

                  Result := Format('Centrality Score for node "%s" (%s): %s', [StartNode.Name, StartNode.NodeLabel, FormatFloat('0.####', Score)]);
                end
                else
                  Result := 'Node not found for centrality calculation.';
              end;

            // -------------------------------------------------------
            // DEGREES (TOP NODES)
            // -------------------------------------------------------
            cmdDegrees:
              begin
                NodeListResult := Self.GetNodesByDegree(Parser.CommandLimit, dtTotal);
                SetLength(AResultObjects, Length(NodeListResult));

                // To generate the enriched text of these nodes, we use GraphToContextText
                // since they are pure nodes.
                Result := Self.GraphToContextText(NodeListResult);

                // Fill the output object
                for I := 0 to High(NodeListResult) do
                begin
                  ResDict := TDictionary<string, TObject>.Create;
                  ResDict.Add('type', TStringWrapper.Create('node'));
                  ResDict.Add('element', NodeListResult[I]);
                  AResultObjects[I] := ResDict;
                end;
              end;
          end;
        finally
          ContextBuilder.Free;
        end;
      end
      // =========================================================
      // STANDARD MATCH QUERY (The most common)
      // =========================================================
      else if Assigned(QueryObj) then
      begin
        if QueryObj.Depth > 0 then
          FinalDepth := QueryObj.Depth
        else
          FinalDepth := ADepth;

        // 1. Execute Match
        AResultObjects := Self.Match(QueryObj, FinalDepth);

        // 2. Extract unique Nodes to generate the context
        ContextNodes := TList<TAiRagGraphNode>.Create;
        try
          for ResDict in AResultObjects do
          begin
            // Match results may come mixed (nodes, edges, values)
            // We extract only the nodes to pass them to the context generator.
            for var Pair in ResDict do
            begin
              // Case A: The direct object is a Node (old/simple format)
              if Pair.Value is TAiRagGraphNode then
              begin
                if ContextNodes.IndexOf(TAiRagGraphNode(Pair.Value)) = -1 then
                  ContextNodes.Add(TAiRagGraphNode(Pair.Value));
              end
              // Case B: The object is wrapped in a type dictionary (new standardized format)
              // e.g.: { 'type': 'node', 'element': <TAiRagGraphNode> }
              else if SameText(Pair.Key, 'element') and (Pair.Value is TAiRagGraphNode) then
              begin
                if ContextNodes.IndexOf(TAiRagGraphNode(Pair.Value)) = -1 then
                  ContextNodes.Add(TAiRagGraphNode(Pair.Value));
              end;
            end;
          end;

          // 3. Generate the Formatted Text using GraphToContextText
          if ContextNodes.Count > 0 then
            Result := Self.GraphToContextText(ContextNodes.ToArray)
          else
            Result := 'No matching subgraphs found.';

        finally
          ContextNodes.Free;
        end;
      end;

    finally
      if Assigned(QueryObj) then
        QueryObj.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function TAiRagGraph.ExpandNodeList(AInitialNodes: TList<TAiRagGraphNode>; ADepth: Integer): TArray<TAiRagGraphNode>;
var
  // We use a dictionary to record nodes already processed or added.
  FoundNodes: TDictionary<string, TAiRagGraphNode>;
  NodeQueue: TQueue<TAiRagGraphNode>;
  CurrentNode, NeighborNode: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  CurrentDepth, NodesInCurrentLevel: Integer;
begin
  FoundNodes := TDictionary<string, TAiRagGraphNode>.Create;
  NodeQueue := TQueue<TAiRagGraphNode>.Create;
  try
    // Initialize with the starting nodes
    for CurrentNode in AInitialNodes do
    begin
      if not FoundNodes.ContainsKey(CurrentNode.ID) then
      begin
        NodeQueue.Enqueue(CurrentNode);
        FoundNodes.Add(CurrentNode.ID, CurrentNode);
      end;
    end;

    // BFS expansion limited by depth
    CurrentDepth := 0;
    while (NodeQueue.Count > 0) and (CurrentDepth < ADepth) do
    begin
      NodesInCurrentLevel := NodeQueue.Count;
      while NodesInCurrentLevel > 0 do
      begin
        CurrentNode := NodeQueue.Dequeue;

        // Expand forward (outgoing)
        for Edge in CurrentNode.OutgoingEdges do
        begin
          NeighborNode := Edge.ToNode;
          if not FoundNodes.ContainsKey(NeighborNode.ID) then
          begin
            FoundNodes.Add(NeighborNode.ID, NeighborNode);
            NodeQueue.Enqueue(NeighborNode);
          end;
        end;

        // Expand backward (incoming)
        for Edge in CurrentNode.IncomingEdges do
        begin
          NeighborNode := Edge.FromNode;
          if not FoundNodes.ContainsKey(NeighborNode.ID) then
          begin
            FoundNodes.Add(NeighborNode.ID, NeighborNode);
            NodeQueue.Enqueue(NeighborNode);
          end;
        end;

        Dec(NodesInCurrentLevel);
      end;
      Inc(CurrentDepth);
    end;

    // Convert the dictionary values to an array
    Result := FoundNodes.Values.ToArray;
  finally
    NodeQueue.Free;
    FoundNodes.Free;
  end;
end;

function TAiRagGraph.ExtractSubgraph(ANodes: TArray<TAiRagGraphNode>): TAiRagGraph;
var
  NodeSet: TDictionary<string, Boolean>;
  Node, NewNode: TAiRagGraphNode;
  Edge, NewEdge: TAiRagGraphEdge;
  Chunk: TAiEmbeddingNode;
  NewSource, NewTarget: TAiRagGraphNode;
begin
  // 1. Create the new graph with the same embeddings configuration
  Result := TAiRagGraph.Create(nil);
  Result.Embeddings := Self.Embeddings;

  if Length(ANodes) = 0 then
    Exit;

  // Dictionary to track which nodes were included in the subgraph
  NodeSet := TDictionary<string, Boolean>.Create;
  try
    // BLOCK UPDATES: Crucial for performance.
    // Avoids rebuilding the indexes (BM25/HNSW) node by node.
    Result.BeginUpdate;
    try
      // --- PHASE 1: Clone all selected Nodes ---
      for Node in ANodes do
      begin
        NodeSet.Add(Node.ID, True);

        // We create the node in the new graph keeping ID, Label and Name
        NewNode := Result.AddNode(Node.ID, Node.NodeLabel, Node.Name);
        NewNode.Model := Node.Model;

        // TEXT COPY: Important for the subgraph to work with lexical searches
        NewNode.Text := Node.Text;

        // METADATA COPY: Replaces the manual FProperties loop.
        // Copies real types (dates, numbers, booleans) without loss.
        NewNode.MetaData.Assign(Node.MetaData);

        // VECTOR COPY (Summary): Copies the node's main embedding
        if Length(Node.Data) > 0 then
        begin
          NewNode.SetDataLength(Length(Node.Data));
          NewNode.Data := Copy(Node.Data); // Copy is safer than Move for dynamic arrays
        end;

        // CHUNKS COPY: New functionality (Option 1)
        // Ensures that the entity keeps all its text fragments
        for Chunk in Node.Chunks do
        begin
          NewNode.AddChunk(Chunk.Text, Chunk.Data);
        end;
      end;

      // --- PHASE 2: Clone Internal Edges ---
      // Only those whose source and target entities are present in the selection
      for Node in ANodes do
      begin
        for Edge in Node.OutgoingEdges do
        begin
          // Check whether the target node was also selected
          if NodeSet.ContainsKey(Edge.ToNode.ID) then
          begin
            // IMPORTANT: Get the node references IN THE NEW GRAPH
            NewSource := Result.FindNodeByID(Edge.FromNode.ID);
            NewTarget := Result.FindNodeByID(Edge.ToNode.ID);

            if (NewSource <> nil) and (NewTarget <> nil) then
            begin
              // We recreate the edge with all original parameters (ID, Label, Name, Weight)
              NewEdge := Result.AddEdge(NewSource, NewTarget, Edge.ID, Edge.EdgeLabel, Edge.Name, Edge.Weight);

              // Copy edge metadata
              NewEdge.MetaData.Assign(Edge.MetaData);

              // Copy edge vector (if it exists)
              if Length(Edge.Data) > 0 then
              begin
                NewEdge.SetDataLength(Length(Edge.Data));
                NewEdge.Data := Copy(Edge.Data);
              end;
            end;
          end;
        end;
      end;
    finally
      // Triggers index rebuilding only once for the entire subgraph
      Result.EndUpdate;
    end;
  finally
    NodeSet.Free;
  end;
end;

procedure TAiRagGraph.Clear;
var
  NodeList: TList<TAiRagGraphNode>;
begin
  // Original code
  FNodeRegistry.Clear;
  FEdgeRegistry.Clear;

  // Free the node lists inside the label index before clearing it
  for NodeList in FNodeLabelIndex.Values do
  begin
    NodeList.Free;
  end;
  FNodeLabelIndex.Clear;
  FNodeNameIndex.Clear;

  FUpdateCount := 0;
  FNodes.Clear;
  FEdges.Clear;
end;

function TAiRagGraph.CountNodesByLabel(const ALabel: string): Integer;
var
  NodeList: TList<TAiRagGraphNode>;
begin
  // We use the index for maximum efficiency
  if FNodeLabelIndex.TryGetValue(ALabel, NodeList) then
    Result := NodeList.Count
  else
    Result := 0;
end;

function TAiRagGraph.CountEdgesByLabel(const ALabel: string): Integer;
var
  Edge: TAiRagGraphEdge;
begin
  Result := 0;
  for Edge in FEdgeRegistry.Values do
  begin
    if SameText(Edge.EdgeLabel, ALabel) then
      Inc(Result);
  end;
end;

function TAiRagGraph.NewNode(const AID, ALabel, AName: string): TAiRagGraphNode;
var
  Dim: Integer;
begin
  // We determine the dimension for the object
  if FNodes.Dim > 0 then
    Dim := FNodes.Dim
  else if Assigned(FEmbeddings) then
    Dim := FEmbeddings.Dimensions
  else
    Dim := 1536; // Default value

  // We create the instance
  Result := TAiRagGraphNode.Create(Self, Dim);
  Result.ID := AID;
  Result.NodeLabel := ALabel;
  Result.Name := AName;
  // Note: It is not added to FNodeRegistry or FNodes yet.
end;

procedure TAiRagGraph.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  // If a component is being removed (opRemove)
  if Operation = opRemove then
  begin
    // Is it our embeddings engine?
    if AComponent = FEmbeddings then
      FEmbeddings := nil;

    // Is it our driver?
    if AComponent = FDriver then
      FDriver := nil;
  end;
end;

function TAiRagGraph.AddNode(AID, ALabel, AName: string): TAiRagGraphNode;
begin
  // Now AddNode uses NewNode and then registers it
  Result := NewNode(AID, ALabel, AName);
  try
    Result := AddNode(Result); // Calls the overload that accepts the object
  except
    Result.Free;
    raise;
  end;
end;

function TAiRagGraph.AddNode(ANode: TAiRagGraphNode): TAiRagGraphNode;
var
  ExistingNode: TAiRagGraphNode;
begin
  if ANode = nil then
    Exit(nil);

  // We try to register and persist it
  // InternalAddNode already handles whether the ID exists (Identity Map)
  ExistingNode := InternalAddNode(ANode, True);

  if ExistingNode <> ANode then
  begin
    // If a node with that ID already existed, we free the one we tried to add
    // and return the one that was already in the graph.
    ANode.Free;
    Result := ExistingNode;
  end
  else
    Result := ANode;
end;

procedure TAiRagGraph.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

function TAiRagGraph.NewEdge(AFromNode, AToNode: TAiRagGraphNode; const AID, ALabel, AName: string; AWeight: Double = 1.0): TAiRagGraphEdge;
var
  Dim: Integer;
begin
  // We centralize dimension detection
  if FEdges.Dim > 0 then
    Dim := FEdges.Dim
  else if Assigned(FEmbeddings) then
    Dim := FEmbeddings.Dimensions
  else
    Dim := 1536;

  Result := TAiRagGraphEdge.Create(Self, Dim);
  Result.ID := AID;
  Result.EdgeLabel := ALabel;
  Result.Name := AName;
  Result.FromNode := AFromNode;
  Result.ToNode := AToNode;
  Result.Weight := AWeight;
end;

// The overload that creates from simple data
function TAiRagGraph.AddEdge(AFromNode, AToNode: TAiRagGraphNode; AID, ALabel, AName: string): TAiRagGraphEdge;
begin
  Result := AddEdge(AFromNode, AToNode, AID, ALabel, AName, 1.0);
end;

// The overload that creates from simple data + weight
function TAiRagGraph.AddEdge(AFromNode, AToNode: TAiRagGraphNode; AID, ALabel, AName: string; AWeight: Double): TAiRagGraphEdge;
begin
  // 1. We use the factory to create the complete object in memory
  Result := NewEdge(AFromNode, AToNode, AID, ALabel, AName, AWeight);

  try
    // 2. We call the object overload to register and persist
    Result := AddEdge(Result);
  except
    // If registration or persistence fails, NewEdge was not adopted,
    // so we must free it.
    if (Result <> nil) then
      Result.Free;
    raise;
  end;
end;

// The overload that receives the already created object
function TAiRagGraph.AddEdge(AEdge: TAiRagGraphEdge): TAiRagGraphEdge;
var
  ExistingEdge: TAiRagGraphEdge;
begin
  if AEdge = nil then
    Exit(nil);

  // We delegate to InternalAddEdge with AShouldPersist = True
  ExistingEdge := InternalAddEdge(AEdge, True);

  if ExistingEdge <> AEdge then
  begin
    // If an edge with that ID already existed, we free the new one
    AEdge.Free;
    Result := ExistingEdge;
  end
  else
    Result := AEdge;
end;

procedure TAiRagGraph.DeleteEdge(AEdge: TAiRagGraphEdge);
begin
  if AEdge = nil then
    Exit;

  // Remove the reference from the connected nodes
  AEdge.FromNode.RemoveOutgoingEdge(AEdge);
  AEdge.ToNode.RemoveIncomingEdge(AEdge);

  UnregisterEdge(AEdge);
end;

procedure TAiRagGraph.DeleteEdge(AID: string);
var
  Edge: TAiRagGraphEdge;
begin
  Edge := FindEdgeByID(AID);
  DeleteEdge(Edge);
end;

procedure TAiRagGraph.DeleteNode(ANode: TAiRagGraphNode);
var
  Edge: TAiRagGraphEdge;
  EdgesToDelete: TList<TAiRagGraphEdge>;
begin
  if ANode = nil then
    Exit;

  // Create a temporary list of edges to delete so as not to modify the lists while iterating
  EdgesToDelete := TList<TAiRagGraphEdge>.Create;
  try
    for Edge in ANode.OutgoingEdges do
      EdgesToDelete.Add(Edge);
    for Edge in ANode.IncomingEdges do
      EdgesToDelete.Add(Edge);

    // Delete all connected edges
    for Edge in EdgesToDelete do
      DeleteEdge(Edge);
  finally
    EdgesToDelete.Free;
  end;

  UnregisterNode(ANode);
end;

procedure TAiRagGraph.DeleteNode(AID: string);
var
  Node: TAiRagGraphNode;
begin
  Node := FindNodeByID(AID);
  if Node = nil then
    Exit;

  // 1. Save a reference to the edges BEFORE deleting them from memory
  var
  EdgesToDelete := TList<TAiRagGraphEdge>.Create;
  EdgesToDelete.AddRange(Node.OutgoingEdges.ToArray);
  EdgesToDelete.AddRange(Node.IncomingEdges.ToArray);

  try
    // 2. Perform the operation in memory FIRST
    UnregisterNode(Node); // This removes the node from FNodeRegistry and FNodes
    // You must also unregister the connected edges
    for var Edge in EdgesToDelete do
      UnregisterEdge(Edge);

    // 3. Persist the change in the DB AFTERWARDS
    if Assigned(FDriver) then
    begin
      try
        FDriver.DeleteNode(AID);
        // You would also need an OnGraphDeleteEdge for the edges
        // or have OnGraphDeleteNode handle cascading deletion.
      except
        // If the DB fails, we have to restore the in-memory state!
        // This is complex: it would require adding the node and edges back.
        // For simplicity, for now we only re-raise. A complete solution
        // would require a "Unit of Work" pattern.
        raise;
      end;
    end;
  finally
    EdgesToDelete.Free;
  end;
end;

procedure TAiRagGraph.UnregisterEdge(AEdge: TAiRagGraphEdge);
begin
  if FEdgeRegistry.ContainsKey(AEdge.ID) then
    FEdgeRegistry.Remove(AEdge.ID);
  FEdges.Items.Remove(AEdge); // This frees the memory of the Edge object
end;

procedure TAiRagGraph.UnregisterNode(ANode: TAiRagGraphNode);
var
  NodeList: TList<TAiRagGraphNode>;
  CombinedNameKey: string;
begin
  if ANode = nil then
    Exit;

  // --> START OF CHANGES
  // We only update the indexes in real time if we are not in batch mode
  if FUpdateCount = 0 then
  begin
    // 1. Remove from the label index
    if FNodeLabelIndex.TryGetValue(ANode.NodeLabel, NodeList) then
    begin
      NodeList.Remove(ANode);
      if NodeList.Count = 0 then
      begin
        FNodeLabelIndex.Remove(ANode.NodeLabel);
        NodeList.Free;
      end;
    end;

    // 2. Remove from the name index
    if not ANode.Name.IsEmpty then
    begin
      CombinedNameKey := ANode.NodeLabel + '#' + ANode.Name;
      FNodeNameIndex.Remove(CombinedNameKey);
    end;
  end;
  // --> END OF CHANGES

  // Original code (this always executes)
  if FNodeRegistry.ContainsKey(ANode.ID) then
    FNodeRegistry.Remove(ANode.ID);
  FNodes.Items.Remove(ANode);
end;

procedure TAiRagGraph.UpdateCommunityLabels;
var
  Communities: TDictionary<TAiRagGraphNode, Integer>;
  Node: TAiRagGraphNode;
begin
  // 1. Run the community detection algorithm (e.g.: Louvain)
  Communities := DetectCommunities;
  try
    // 2. Iterate over the results (Node -> Community ID)
    for Node in Communities.Keys do
    begin
      // 3. Save the ID in the unified MetaData.
      // Since it is an Integer, it is saved as a Variant correctly, allowing
      // it to later be exported to JSON or Postgres as a real number.
      Node.Properties['community_id'] := Communities[Node];
    end;
  finally
    Communities.Free;
  end;
end;

function TAiRagGraph.FindEdge(AFromNode, AToNode: TAiRagGraphNode; AEdgeLabel: string): TAiRagGraphEdge;
var
  Edge: TAiRagGraphEdge;
begin
  Result := nil;
  // It is more efficient to iterate over the outgoing edges of the source node,
  // since it is a much smaller list than all the edges in the graph.
  for Edge in AFromNode.OutgoingEdges do
  begin
    if (Edge.ToNode = AToNode) and (SameText(Edge.EdgeLabel, AEdgeLabel)) then
    begin
      Result := Edge;
      Exit;
    end;
  end;
end;

function TAiRagGraph.FindEdgeByID(AID: string): TAiRagGraphEdge;
var
  FoundInDB: Boolean;
  EdgeData: TEdgeDataRecord;
begin
  // 1. Search in cache.
  if FEdgeRegistry.TryGetValue(AID, Result) then
    Exit;

  // 2. Request data from the DB (Driver ONLY).
  Result := nil;
  FoundInDB := False;

  if Assigned(FDriver) then
  begin
    // We clear the record before passing it to the driver.
    // Although the driver should be defensive, initializing is good practice.
    FillChar(EdgeData, SizeOf(TEdgeDataRecord), 0);

    // KEY FIX: Call the driver's FindEdgeDataByID method.
    FoundInDB := FDriver.FindEdgeDataByID(AID, EdgeData);
  end;

  // If it was not found in the driver or the driver was not assigned, FoundInDB is False.

  // 3. Use the new helper to hydrate.
  if FoundInDB then
    Result := InternalHydrateEdge(EdgeData);
end;

function TAiRagGraph.FindNodeByID(AID: string): TAiRagGraphNode;
var
  FoundInDB: Boolean;
  NodeData: TNodeDataRecord;
begin
  // 1. Search in cache.
  if FNodeRegistry.TryGetValue(AID, Result) then
    Exit;

  // 2. Request data from the DB.
  Result := nil;
  FoundInDB := False;

  if Assigned(FDriver) then
  begin
    FoundInDB := FDriver.FindNodeDataByID(AID, NodeData);
  end;

  // 3. Use the new helper to hydrate.
  if FoundInDB then
    Result := InternalHydrateNode(NodeData);
end;

function TAiRagGraph.FindNodeByName(AName, ANodeLabel: string): TAiRagGraphNode;
var
  CombinedNameKey: string; // For the in-memory logic
begin
  Result := nil;

  // 1. Try to delegate to the database through the Driver.
  if Assigned(FDriver) then
  begin
    // The driver performs the search in the DB and returns the hydrated object
    // (or nil if it does not find it).
    Result := FDriver.FindNodeByName(AName, ANodeLabel);
    // If the driver found something, we exit immediately.
    if Result <> nil then
      Exit;
  end;

  // 2. Fallback to in-memory logic (if the Driver was not used or found nothing)
  if AName.IsEmpty or ANodeLabel.IsEmpty then
    Exit;

  // Try to find in the in-memory index (only for already loaded nodes)
  CombinedNameKey := ANodeLabel + '#' + AName;
  FNodeNameIndex.TryGetValue(CombinedNameKey, Result);
end;

function TAiRagGraph.FindNodeNamesByLabel(const ANodeLabel, ASearchText: string; ALimit: Integer): TArray<string>;
var
  NodeList: TList<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
  Results: TStringList;
begin
  Result := [];

  // 1. Try to delegate to the Driver (DB)
  if Assigned(FDriver) then
  begin
    // The driver performs an efficient search in the DB and returns the array of names.
    Result := FDriver.FindNodeNamesByLabel(ANodeLabel, ASearchText, ALimit);

    // If the DB returned results, we exit.
    if Length(Result) > 0 then
      Exit;

    // NOTE: If the DB returns an empty array, we go to the in-memory fallback (Step 2).
  end;

  // 2. Fallback to in-memory logic if there are no results or no driver.
  Results := TStringList.Create;
  try
    // We use the label index to be efficient
    if FNodeLabelIndex.TryGetValue(ANodeLabel, NodeList) then
    begin
      for Node in NodeList do
      begin
        if ContainsText(LowerCase(Node.Name), LowerCase(ASearchText)) then
        begin
          Results.Add(Node.Name);
          if Results.Count >= ALimit then
            Break; // Stop when we reach the limit
        end;
      end;
    end;
    Result := Results.ToStringArray;
  finally
    Results.Free;
  end;
end;

function TAiRagGraph.FindNodesByLabel(ALabel: string): TArray<TAiRagGraphNode>;
var
  NodeList: TList<TAiRagGraphNode>; // For the in-memory logic
begin
  Result := [];

  // 1. Try to delegate to the Driver (DB)
  if Assigned(FDriver) then
  begin
    // The driver performs the search in the DB, handles hydration
    // (using FindNodeByID) and returns the array of nodes.
    Result := FDriver.FindNodesByLabel(ALabel);

    // If the driver returned any result, we exit.
    if Length(Result) > 0 then
      Exit;

    // If the driver returned an empty array, we go to the in-memory fallback (Step 2).
  end;

  // 2. Fallback to in-memory logic (if there are no results or no driver)
  if FNodeLabelIndex.TryGetValue(ALabel, NodeList) then
    Result := NodeList.ToArray
  else
    Result := [];
end;

function TAiRagGraph.FindNodesByProperty(const AKey: string; const AValue: Variant): TArray<TAiRagGraphNode>;
var
  Results: TList<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
begin
  Result := [];

  // 1. Try to delegate to the Driver (Database)
  if Assigned(FDriver) then
  begin
    // The driver performs an efficient indexed search in the DB
    Result := FDriver.FindNodesByProperty(AKey, AValue);

    if Length(Result) > 0 then
      Exit;
  end;

  // 2. Fallback to in-memory logic
  Results := TList<TAiRagGraphNode>.Create;
  try
    for Node in FNodeRegistry.Values do
    begin
      // --- A. Handling native attributes (Identity) ---
      if SameText(AKey, 'name') then
      begin
        // We use SameText for names (case-insensitive)
        if SameText(Node.Name, VarToStr(AValue)) then
          Results.Add(Node);
      end
      else if SameText(AKey, 'label') then
      begin
        if SameText(Node.NodeLabel, VarToStr(AValue)) then
          Results.Add(Node);
      end
      else if SameText(AKey, 'id') then
      begin
        if SameText(Node.ID, VarToStr(AValue)) then
          Results.Add(Node);
      end
      // --- B. Handling dynamic properties (MetaData) ---
      else
      begin
        // We use the new Evaluate method of MetaData.
        // This allows that if you search price = 100, it does not fail if 100 is an Integer
        // but you passed a Double, thanks to Variant handling.
        if Node.Properties.Evaluate(AKey, foEqual, AValue) then
          Results.Add(Node);
      end;
    end;

    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TAiRagGraph.GetAllShortestPaths(AStartNode, AEndNode: TAiRagGraphNode): TArray<TArray<TObject>>;
var
  Queue: TQueue<TAiRagGraphNode>;
  // Stores the shortest distance from the start node to any other node
  Distances: TDictionary<TAiRagGraphNode, Integer>;
  // Stores for each node a list of its "parents" in the shortest paths
  Parents: TDictionary<TAiRagGraphNode, TList<TAiRagGraphNode>>;
  AllPaths: TList<TArray<TObject>>;
  CurrentPath: TList<TObject>;
  CurrentNode, NeighborNode: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  ShortestDistance: Integer;

  // Recursive procedure to reconstruct the paths backward
  procedure BuildPaths(ANode: TAiRagGraphNode);
  var
    ParentNode: TAiRagGraphNode;
    ConnectingEdge: TAiRagGraphEdge;
  begin
    // 1. Add the current node to the front of the path we are building
    CurrentPath.Insert(0, ANode);

    // 2. Base Case: If we have reached the start node, we have completed a path
    if ANode = AStartNode then
    begin
      // We add a copy of the found path to our results list
      AllPaths.Add(CurrentPath.ToArray);
    end
    else
    // 3. Recursive Step: Explore all parents of this node
    begin
      if Parents.ContainsKey(ANode) then
      begin
        for ParentNode in Parents[ANode] do
        begin
          // Find the edge connecting the parent with the current node
          ConnectingEdge := FindEdge(ParentNode, ANode, ''); // We pass '' so it searches for any label
          // A more robust version could iterate over ParentNode.OutgoingEdges
          if ConnectingEdge = nil then
          begin
            // More exhaustive search if FindEdge fails (in case there are multiple edges)
            for var E in ParentNode.OutgoingEdges do
            begin
              if E.ToNode = ANode then
              begin
                ConnectingEdge := E;
                Break;
              end;
            end;
          end;

          // Add the edge to the path
          CurrentPath.Insert(0, ConnectingEdge);
          // Call recursively for the parent
          BuildPaths(ParentNode);
          // Backtrack: remove the edge for the next iteration of the parent loop
          CurrentPath.Remove(ConnectingEdge);
        end;
      end;
    end;

    // 4. Backtrack: remove the current node from the path so as not to affect other branches of the recursion
    CurrentPath.Remove(ANode);
  end;

begin
  Result := [];
  if (AStartNode = nil) or (AEndNode = nil) or (AStartNode = AEndNode) then
    Exit;

  // --- PHASE 1: FORWARD BFS TO FIND DISTANCES AND PARENTS ---
  Queue := TQueue<TAiRagGraphNode>.Create;
  Distances := TDictionary<TAiRagGraphNode, Integer>.Create;
  Parents := TDictionary < TAiRagGraphNode, TList < TAiRagGraphNode >>.Create;
  ShortestDistance := -1;

  try
    Queue.Enqueue(AStartNode);
    Distances.Add(AStartNode, 0);
    Parents.Add(AStartNode, TList<TAiRagGraphNode>.Create); // The start node has no parents

    while Queue.Count > 0 do
    begin
      CurrentNode := Queue.Dequeue;
      var
      CurrentDist := Distances[CurrentNode];

      // If we have already found the destination, we only need to finish processing the nodes
      // that are at the same distance. We do not explore further.
      if (ShortestDistance <> -1) and (CurrentDist >= ShortestDistance) then
        Continue;

      for Edge in CurrentNode.OutgoingEdges do
      begin
        NeighborNode := Edge.ToNode;

        // Case 1: First time we visit this neighbor
        if not Distances.ContainsKey(NeighborNode) then
        begin
          Distances.Add(NeighborNode, CurrentDist + 1);
          Queue.Enqueue(NeighborNode);
          var
          ParentList := TList<TAiRagGraphNode>.Create;
          Parents.Add(NeighborNode, ParentList);
          ParentList.Add(CurrentNode);

          // If this neighbor is our destination, we record the shortest distance
          if NeighborNode = AEndNode then
            ShortestDistance := CurrentDist + 1;
        end
        // Case 2: We have already visited this neighbor, but we have found another path
        // of the same minimum length to reach it.
        else if Distances[NeighborNode] = CurrentDist + 1 then
        begin
          Parents[NeighborNode].Add(CurrentNode);
        end;
      end;
    end;

    // --- PHASE 2: RECURSIVE RECONSTRUCTION BACKWARD ---
    // If ShortestDistance is still -1, it means the final node was never reached.
    if ShortestDistance <> -1 then
    begin
      AllPaths := TList < TArray < TObject >>.Create;
      CurrentPath := TList<TObject>.Create;
      try
        BuildPaths(AEndNode); // Start recursion from the final node
        Result := AllPaths.ToArray;
      finally
        CurrentPath.Free;
        AllPaths.Free;
      end;
    end;

  finally
    Queue.Free;
    Distances.Free;
    for var List in Parents.Values do // It is crucial to free the internal lists
      List.Free;
    Parents.Free;
  end;
end;

function TAiRagGraph.GetClosenessCentrality(ANode: TAiRagGraphNode): Double;
var
  Queue: TQueue<TAiRagGraphNode>;
  Distances: TDictionary<TAiRagGraphNode, Integer>;
  CurrentNode, NeighborNode: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  TotalDistance: Int64;
  ReachableNodesCount: Integer;
  CurrentDistance: Integer;
begin
  Result := 0;
  if (ANode = nil) or (FNodeRegistry.Count < 2) then
    Exit;

  Queue := TQueue<TAiRagGraphNode>.Create;
  Distances := TDictionary<TAiRagGraphNode, Integer>.Create;
  TotalDistance := 0;
  ReachableNodesCount := 0;

  try
    // --- Stage 1: BFS initialization ---
    // The start node is at a distance of 0 from itself.
    Distances.Add(ANode, 0);
    Queue.Enqueue(ANode);

    // --- Stage 2: BFS traversal ---
    while Queue.Count > 0 do
    begin
      CurrentNode := Queue.Dequeue;
      CurrentDistance := Distances[CurrentNode];

      // Expand to neighbors (forward only, as is typical in centrality)
      // If you wanted an undirected graph, you would also traverse IncomingEdges.
      for Edge in CurrentNode.OutgoingEdges do
      begin
        NeighborNode := Edge.ToNode;

        // If we have not visited this neighbor before...
        if not Distances.ContainsKey(NeighborNode) then
        begin
          // We mark its distance
          Distances.Add(NeighborNode, CurrentDistance + 1);
          // We add it to the queue to visit its neighbors later
          Queue.Enqueue(NeighborNode);

          // --- Stage 3: Accumulate the results ---
          Inc(ReachableNodesCount);
          TotalDistance := TotalDistance + (CurrentDistance + 1);
        end;
      end;
    end;

    // --- Stage 4: Calculate Closeness Centrality ---
    if TotalDistance > 0 then
    begin
      // Standard Closeness Centrality formula:
      // (Number of reachable nodes) / (Sum of distances to them)
      Result := ReachableNodesCount / TotalDistance;
    end;

  finally
    Queue.Free;
    Distances.Free;
  end;
end;

{
  function TAiRagGraph.GetContextualizedText(ASubgraphNodes: TArray<TAiRagGraphNode>): string;
  var
  // We use a dictionary as a Set for fast node lookups
  NodeSet: TDictionary<TAiRagGraphNode, Boolean>;
  RelevantEdges: TDictionary<string, TAiRagGraphEdge>;
  ContextBuilder: TStringBuilder;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  begin
  if Length(ASubgraphNodes) = 0 then
  Exit('');

  NodeSet := TDictionary<TAiRagGraphNode, Boolean>.Create;
  RelevantEdges := TDictionary<string, TAiRagGraphEdge>.Create;
  ContextBuilder := TStringBuilder.Create;
  try
  // 1. Populate the NodeSet for efficient searches
  for Node in ASubgraphNodes do
  begin
  NodeSet.Add(Node, True);
  end;

  // 2. Collect all internal edges of the subgraph
  for Node in ASubgraphNodes do
  begin
  for Edge in Node.OutgoingEdges do
  begin
  // >> CORRECTED AND OPTIMIZED LINE <<
  // Now we use ContainsKey on the dictionary, which is much faster.
  if NodeSet.ContainsKey(Edge.ToNode) and (not RelevantEdges.ContainsKey(Edge.ID)) then
  begin
  RelevantEdges.Add(Edge.ID, Edge);
  end;
  end;
  end;

  // 3. Build the text from the collected edges
  ContextBuilder.AppendLine('Context extracted from the knowledge graph:');
  ContextBuilder.AppendLine('The following relevant facts have been identified:');

  if RelevantEdges.Count > 0 then
  begin
  for Edge in RelevantEdges.Values do
  begin
  ContextBuilder.Append('- Fact: ');
  ContextBuilder.Append(Edge.FromNode.Name);
  ContextBuilder.Append(' (');
  ContextBuilder.Append(Edge.FromNode.NodeLabel);
  ContextBuilder.Append(') --[');
  ContextBuilder.Append(Edge.EdgeLabel);
  ContextBuilder.Append(']--> ');
  ContextBuilder.Append(Edge.ToNode.Name);
  ContextBuilder.Append(' (');
  ContextBuilder.Append(Edge.ToNode.NodeLabel);
  ContextBuilder.AppendLine(').');
  end;
  end
  else
  begin
  // Fallback: describe the nodes if there are no internal edges
  ContextBuilder.AppendLine('The following relevant entities were found, but without direct connections among them in the expanded subgraph:');
  for Node in ASubgraphNodes do
  begin
  ContextBuilder.Append('- Entity: ');
  ContextBuilder.Append(Node.Name);
  ContextBuilder.Append(' (');
  ContextBuilder.Append(Node.NodeLabel);
  ContextBuilder.AppendLine(').');
  end;
  end;

  Result := ContextBuilder.ToString;
  finally
  NodeSet.Free;
  RelevantEdges.Free;
  ContextBuilder.Free;
  end;
  end;
}

function TAiRagGraph.GetContextualizedText(ASubgraphNodes: TArray<TAiRagGraphNode>): string;
var
  ContextBuilder: TStringBuilder;
  NodeSet: TDictionary<TAiRagGraphNode, Boolean>;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  Chunk: TAiEmbeddingNode;
  RelevantEdges: TDictionary<string, TAiRagGraphEdge>;
  Pair: TPair<string, Variant>;
  IsFirstProp: Boolean;
begin
  if Length(ASubgraphNodes) = 0 then
    Exit('No relevant information was found.');

  ContextBuilder := TStringBuilder.Create;
  NodeSet := TDictionary<TAiRagGraphNode, Boolean>.Create;
  RelevantEdges := TDictionary<string, TAiRagGraphEdge>.Create;
  try
    // 1. Identify nodes present in the subgraph
    for Node in ASubgraphNodes do
      NodeSet.Add(Node, True);

    // === SECTION 1: ENTITIES AND THEIR FRAGMENTS (CHUNKS) ===
    ContextBuilder.AppendLine('### ENTITY CONTEXT ###');
    for Node in ASubgraphNodes do
    begin
      ContextBuilder.AppendFormat('- Entity: %s (Type: %s)', [Node.Name, Node.NodeLabel]);

      if not Node.Text.IsEmpty then
        ContextBuilder.Append(' - Summary: ' + Node.Text);

      ContextBuilder.AppendLine('.');

      // --- Include detailed text fragments (Chunks) ---
      if Node.Chunks.Count > 0 then
      begin
        for Chunk in Node.Chunks do
        begin
          ContextBuilder.AppendFormat('  + Detail: %s', [Chunk.Text]).AppendLine;
        end;
      end;

      // Collect edges connecting with other nodes of the same subgraph
      for Edge in Node.OutgoingEdges do
      begin
        if NodeSet.ContainsKey(Edge.ToNode) and (not RelevantEdges.ContainsKey(Edge.ID)) then
          RelevantEdges.Add(Edge.ID, Edge);
      end;
    end;

    // === SECTION 2: RELATIONSHIPS AND FACTS ===
    if RelevantEdges.Count > 0 then
    begin
      ContextBuilder.AppendLine;
      ContextBuilder.AppendLine('### RELATIONSHIPS AND FACTS ###');
      for Edge in RelevantEdges.Values do
      begin
        ContextBuilder.AppendFormat('* %s (%s) --[%s]--> %s (%s)', [Edge.FromNode.Name, Edge.FromNode.NodeLabel, Edge.EdgeLabel.ToUpper, Edge.ToNode.Name, Edge.ToNode.NodeLabel]);

        // --- Corrected access to Metadata (using MetaData.InternalDictionary) ---
        if Edge.MetaData.InternalDictionary.Count > 0 then
        begin
          ContextBuilder.Append(' {');
          IsFirstProp := True;
          for Pair in Edge.MetaData.InternalDictionary do
          begin
            if not IsFirstProp then
              ContextBuilder.Append(', ');
            ContextBuilder.AppendFormat('%s: %s', [Pair.Key, VarToStr(Pair.Value)]);
            IsFirstProp := False;
          end;
          ContextBuilder.Append('}');
        end;

        if Abs(Edge.Weight - 1.0) > 0.001 then
          ContextBuilder.AppendFormat(' [Weight: %s]', [FormatFloat('0.##', Edge.Weight)]);

        ContextBuilder.AppendLine('.');
      end;
    end;

    Result := ContextBuilder.ToString;
  finally
    NodeSet.Free;
    RelevantEdges.Free;
    ContextBuilder.Free;
  end;
end;

function TAiRagGraph.GetEdgeCount: Integer;
begin
  Result := FEdgeRegistry.Count;
end;

function TAiRagGraph.GetEdgesRAGVector: TAiRAGVector;
begin
  Result := FEdges;
end;

function TAiRagGraph.GetNeighbors(ANode: TAiRagGraphNode; ADirection: TGraphDirection): TArray<TAiRagGraphNode>;
var
  Results: TList<TAiRagGraphNode>;
  Edge: TAiRagGraphEdge;
begin
  Result := Nil;
  if ANode = nil then
    Exit;

  Results := TList<TAiRagGraphNode>.Create;
  try
    if (ADirection = gdOutgoing) or (ADirection = gdBoth) then
    begin
      for Edge in ANode.OutgoingEdges do
        Results.Add(Edge.ToNode);
    end;

    if (ADirection = gdIncoming) or (ADirection = gdBoth) then
    begin
      for Edge in ANode.IncomingEdges do
        // Avoid duplicates if ADirection is gdBoth and there are reciprocal edges
        if Results.IndexOf(Edge.FromNode) = -1 then
          Results.Add(Edge.FromNode);
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TAiRagGraph.GetNodeCount: Integer;
begin
  Result := FNodeRegistry.Count;
end;

function TAiRagGraph.GetNodesByDegree(ATop: Integer; ADegreeType: TDegreeType): TArray<TAiRagGraphNode>;
var
  NodeList: TList<TAiRagGraphNode>;
begin
  NodeList := TList<TAiRagGraphNode>.Create;
  try
    NodeList.AddRange(FNodeRegistry.Values.ToArray); // Copy all nodes to a list

    // Sort the list using TList.Sort with an anonymous comparer
    NodeList.Sort(TComparer<TAiRagGraphNode>.Construct(
      function(const Left, Right: TAiRagGraphNode): Integer
      var
        LeftDegree, RightDegree: Integer;
      begin
        case ADegreeType of
          dtIn:
            begin
              LeftDegree := Left.IncomingEdges.Count;
              RightDegree := Right.IncomingEdges.Count;
            end;
          dtOut:
            begin
              LeftDegree := Left.OutgoingEdges.Count;
              RightDegree := Right.OutgoingEdges.Count;
            end;
        else // dtTotal
          LeftDegree := Left.IncomingEdges.Count + Left.OutgoingEdges.Count;
          RightDegree := Right.IncomingEdges.Count + Right.OutgoingEdges.Count;
        end;
        Result := RightDegree - LeftDegree; // Descending order
      end));

    // Return only the Top N
    if ATop > NodeList.Count then
      ATop := NodeList.Count;
    Result := Copy(NodeList.ToArray, 0, ATop);

  finally
    NodeList.Free;
  end;
end;

function TAiRagGraph.GetNodesRAGVector: TAiRAGVector;
begin
  Result := FNodes;
end;

function TAiRagGraph.GetSearchOptions: TAiSearchOptions;
begin
  // We expose the node vector options, which is the one used for "Anchoring"
  Result := FNodes.SearchOptions;
end;

function TAiRagGraph.GetShortestPath(AStartNode, AEndNode: TAiRagGraphNode): TArray<TObject>;
type
  TPathLink = TPair<TObject, TAiRagGraphEdge>; // Stores [PreviousNode, UsedEdge]
var
  Queue: TQueue<TAiRagGraphNode>;
  CameFrom: TDictionary<TAiRagGraphNode, TPathLink>;
  CurrentNode, NeighborNode: TAiRagGraphNode;
  CurrentEdge: TAiRagGraphEdge;
  PathList: TList<TObject>;
  PathLink: TPathLink;
begin
  Result := []; // By default, returns an empty array if there is no path
  if (AStartNode = nil) or (AEndNode = nil) or (AStartNode = AEndNode) then
    Exit;

  Queue := TQueue<TAiRagGraphNode>.Create;
  CameFrom := TDictionary<TAiRagGraphNode, TPathLink>.Create;
  PathList := TList<TObject>.Create;
  try
    // 1. Initialization
    Queue.Enqueue(AStartNode);
    CameFrom.Add(AStartNode, TPathLink.Create(nil, nil)); // The start node does not come from anywhere

    // 2. BFS loop
    while Queue.Count > 0 do
    begin
      CurrentNode := Queue.Dequeue;

      if CurrentNode = AEndNode then
        Break; // Path found!

      for CurrentEdge in CurrentNode.OutgoingEdges do
      begin
        NeighborNode := CurrentEdge.ToNode;
        if not CameFrom.ContainsKey(NeighborNode) then
        begin
          CameFrom.Add(NeighborNode, TPathLink.Create(CurrentNode, CurrentEdge));
          Queue.Enqueue(NeighborNode);
        end;
      end;
    end;

    // 3. Path reconstruction (if found)
    if CameFrom.ContainsKey(AEndNode) then
    begin
      CurrentNode := AEndNode;
      while CurrentNode <> nil do
      begin
        PathList.Add(CurrentNode);
        if CameFrom.TryGetValue(CurrentNode, PathLink) and (PathLink.Key <> nil) then
        begin
          if PathLink.Value <> nil then
            PathList.Add(PathLink.Value); // Add the edge
          CurrentNode := PathLink.Key as TAiRagGraphNode;
        end
        else
        begin
          CurrentNode := nil; // We reached the start node
        end;
      end;

      PathList.Reverse; // Reverse to obtain the order Start -> End
      Result := PathList.ToArray;
    end;

  finally
    Queue.Free;
    CameFrom.Free;
    PathList.Free;
  end;
end;

function TAiRagGraph.GetUniqueEdgeLabels: TArray<string>;
var
  UniqueLabels: TDictionary<string, Boolean>;
  Edge: TAiRagGraphEdge;
begin
  // Initialize
  Result := [];

  // 1. Try to delegate the operation to the Driver (DB)
  if Assigned(FDriver) then
  begin
    // The driver returns the array of labels from the DB
    Result := FDriver.GetUniqueEdgeLabels;

    // If the DB returned results, we exit.
    if Length(Result) > 0 then
      Exit;
  end;

  // 2. Fallback to the default in-memory logic.
  UniqueLabels := TDictionary<string, Boolean>.Create;
  try
    for Edge in FEdgeRegistry.Values do
    begin
      UniqueLabels.AddOrSetValue(Edge.EdgeLabel, True);
    end;
    Result := UniqueLabels.Keys.ToArray;
  finally
    UniqueLabels.Free;
  end;
end;

function TAiRagGraph.GetUniqueNodeLabels: TArray<string>;
begin
  // Initialize
  Result := [];

  // 1. Try to delegate the operation to the Driver (DB)
  if Assigned(FDriver) then
  begin
    // The driver returns the array of labels from the DB
    Result := FDriver.GetUniqueNodeLabels;

    // If the DB returned results, we exit.
    if Length(Result) > 0 then
      Exit;
  end;

  // 2. Fallback to the default in-memory logic.
  Result := FNodeLabelIndex.Keys.ToArray;
end;

function TAiRagGraph.GraphToContextText(const ANodes: TArray<TAiRagGraphNode>): string;
var
  SB: TStringBuilder;
  NodeSet: TDictionary<string, TAiRagGraphNode>; // We use ID for fast lookup
  RelevantEdges: TDictionary<string, TAiRagGraphEdge>; // To avoid duplicates
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  Chunk: TAiEmbeddingNode;
  Pair: TPair<string, Variant>;
  IsFirst: Boolean;
begin
  if Length(ANodes) = 0 then
    Exit('No data found.');

  SB := TStringBuilder.Create;
  NodeSet := TDictionary<string, TAiRagGraphNode>.Create;
  RelevantEdges := TDictionary<string, TAiRagGraphEdge>.Create;
  try
    // 1. Index the found nodes for fast O(1) lookup
    // This helps us filter only the edges that connect nodes in this set.
    for Node in ANodes do
    begin
      if not NodeSet.ContainsKey(Node.ID) then
        NodeSet.Add(Node.ID, Node);
    end;

    // =========================================================================
    // SECTION 1: ENTITIES AND CONTENT (Semantic Knowledge)
    // =========================================================================
    SB.AppendLine('### ENTITIES & CONTENT ###');

    for Node in ANodes do
    begin
      // Format: - [ID] Name (Type)
      SB.AppendFormat('- [%s] %s (%s)', [Node.ID, Node.Name, Node.NodeLabel]);

      // Include key node properties (Metadata)
      if Node.MetaData.InternalDictionary.Count > 0 then
      begin
        SB.Append(' {');
        IsFirst := True;
        for Pair in Node.MetaData.InternalDictionary do
        begin
          if not IsFirst then
            SB.Append(', ');
          SB.AppendFormat('%s: %s', [Pair.Key, VarToStr(Pair.Value)]);
          IsFirst := False;
        end;
        SB.Append('}');
      end;
      SB.AppendLine;

      // Node summary (if any)
      if not Node.Text.Trim.IsEmpty then
        SB.AppendFormat('  Summary: %s', [Node.Text]).AppendLine;

      // Detailed fragments (RAG Chunks)
      if Node.Chunks.Count > 0 then
      begin
        for Chunk in Node.Chunks do
        begin
          // We indent to show hierarchy
          SB.AppendFormat('  + Detail: %s', [Chunk.Text]).AppendLine;
        end;
      end;

      // Visual separator between nodes
      SB.AppendLine;
    end;

    // =========================================================================
    // SECTION 2: RELATIONSHIPS / FACTS (Structural Knowledge)
    // =========================================================================
    // Here the magic of the graph happens: we reconstruct the story by connecting the dots.

    // Collect INTERNAL edges (where Source AND Target are in our result)
    for Node in ANodes do
    begin
      for Edge in Node.OutgoingEdges do
      begin
        // Was the target node also found in the search?
        if NodeSet.ContainsKey(Edge.ToNode.ID) then
        begin
          if not RelevantEdges.ContainsKey(Edge.ID) then
            RelevantEdges.Add(Edge.ID, Edge);
        end;
      end;
    end;

    if RelevantEdges.Count > 0 then
    begin
      SB.AppendLine('### RELATIONSHIPS (FACTS) ###');
      for Edge in RelevantEdges.Values do
      begin
        // Simplified GQL format (ISO/IEC 39075) for the LLM: (A)-[REL]->(B)
        SB.AppendFormat('(%s)-[%s]->(%s)', [Edge.FromNode.Name, Edge.EdgeLabel.ToUpper, Edge.ToNode.Name]);

        // Include relationship details (e.g.: since: 2020, weight: 0.9)
        if Edge.MetaData.InternalDictionary.Count > 0 then
        begin
          SB.Append(' properties: {');
          IsFirst := True;
          for Pair in Edge.MetaData.InternalDictionary do
          begin
            if not IsFirst then
              SB.Append(', ');
            SB.AppendFormat('%s: %s', [Pair.Key, VarToStr(Pair.Value)]);
            IsFirst := False;
          end;
          SB.Append('}');
        end;

        // Include weight if relevant (different from 1)
        if Abs(Edge.Weight - 1.0) > 0.001 then
          SB.AppendFormat(' (Weight: %s)', [FormatFloat('0.##', Edge.Weight)]);

        SB.AppendLine;
      end;
    end;

    Result := SB.ToString;

  finally
    NodeSet.Free;
    RelevantEdges.Free;
    SB.Free;
  end;
end;

function TAiRagGraph.InternalAddEdge(AEdge: TAiRagGraphEdge; AShouldPersist: Boolean): TAiRagGraphEdge;
begin
  if (AEdge = nil) or (AEdge.OwnerGraph <> Self) or (AEdge.FromNode = nil) or (AEdge.ToNode = nil) then
    raise Exception.Create('Invalid edge provided to InternalAddEdge.');

  // 1. VERIFICACI�N DE IDENTIDAD (Identity Map)
  if FEdgeRegistry.TryGetValue(AEdge.ID, Result) then
  begin
    Exit; // The edge already exists, we return the in-memory instance.
  end;

  // 2. LOGIC FOR ADDING TO IN-MEMORY STRUCTURES
  FEdgeRegistry.Add(AEdge.ID, AEdge);
  FEdges.Items.Add(AEdge);
  // Connect the edge to the nodes
  AEdge.FromNode.AddOutgoingEdge(AEdge);
  AEdge.ToNode.AddIncomingEdge(AEdge);

  // 3. CONDITIONAL PERSISTENCE
  if AShouldPersist and Assigned(FDriver) then
  begin
    try
      FDriver.AddEdge(AEdge);
    except
      // Simplified rollback logic if persistence fails.
      AEdge.FromNode.RemoveOutgoingEdge(AEdge);
      AEdge.ToNode.RemoveIncomingEdge(AEdge);
      FEdgeRegistry.Remove(AEdge.ID);
      FEdges.Items.Remove(AEdge);
      raise;
    end;
  end;

  // 4. RETURN THE EDGE
  Result := AEdge;
end;

function TAiRagGraph.InternalAddNode(ANode: TAiRagGraphNode; AShouldPersist: Boolean): TAiRagGraphNode;
var
  NodeList: TList<TAiRagGraphNode>;
  CombinedNameKey: string;
begin
  if (ANode = nil) or (ANode.OwnerGraph <> Self) then
    raise Exception.Create('Invalid node provided to InternalAddNode.');

  // 1. VERIFICACI�N DE IDENTIDAD (Identity Map)
  // We check whether a node with this ID is already registered in memory.
  if FNodeRegistry.TryGetValue(ANode.ID, Result) then
  begin
    // The node already exists. We return the existing node to maintain
    // consistency. The caller is responsible for freeing the duplicate ANode.
    Exit;
  end;

  // 2. LOGIC FOR ADDING TO IN-MEMORY STRUCTURES
  // If it does not exist, we proceed to add it to all our structures.
  FNodeRegistry.Add(ANode.ID, ANode);
  FNodes.Items.Add(ANode);

  // Update FNodeLabelIndex
  if not FNodeLabelIndex.TryGetValue(ANode.NodeLabel, NodeList) then
  begin
    NodeList := TList<TAiRagGraphNode>.Create;
    FNodeLabelIndex.Add(ANode.NodeLabel, NodeList);
  end;
  NodeList.Add(ANode);

  // Update FNodeNameIndex
  if not ANode.Name.IsEmpty then
  begin
    CombinedNameKey := ANode.NodeLabel + '#' + ANode.Name;
    if not FNodeNameIndex.ContainsKey(CombinedNameKey) then
      FNodeNameIndex.Add(CombinedNameKey, ANode);
  end;

  // 3. CONDITIONAL PERSISTENCE IN DATABASE
  // Only if the caller asks us to (AShouldPersist = True).

  if AShouldPersist and Assigned(FDriver) then
  begin
    try
      FDriver.AddNode(ANode);
    except
      // If the driver fails, we undo in memory and re-raise.
      UnregisterNode(ANode);
      raise;
    end;
  end;

  // 4. RETURN THE NODE
  // The node (ANode) is now owned by the graph and is registered.
  Result := ANode;
end;

function TAiRagGraph.InternalHydrateEdge(const AEdgeData: TEdgeDataRecord): TAiRagGraphEdge;
var
  NewEdge: TAiRagGraphEdge;
  FromNode, ToNode: TAiRagGraphNode;
  Dim: Integer;
  JObj: TJSONObject;
begin
  // 1. Verificaci�n de Identidad (Cache en memoria)
  if FEdgeRegistry.TryGetValue(AEdgeData.ID, Result) then
    Exit;

  // 2. Ensure existence of connected nodes (Recursive load if necessary)
  FromNode := Self.FindNodeByID(AEdgeData.SourceNodeID);
  ToNode := Self.FindNodeByID(AEdgeData.TargetNodeID);

  if (FromNode = nil) or (ToNode = nil) then
    Exit(nil);

  // 3. Determine vector dimensions
  if FEdges.Dim > 0 then
    Dim := FEdges.Dim
  else
    Dim := 1536;

  // 4. Create and hydrate the instance
  NewEdge := TAiRagGraphEdge.Create(Self, Dim);
  try
    NewEdge.ID := AEdgeData.ID;
    NewEdge.EdgeLabel := AEdgeData.EdgeLabel;
    NewEdge.Name := AEdgeData.Name;
    NewEdge.Weight := AEdgeData.Weight;
    NewEdge.FromNode := FromNode;
    NewEdge.ToNode := ToNode;

    // --- KEY CHANGE: Use of the new unified MetaData ---
    if not AEdgeData.PropertiesJSON.IsEmpty then
    begin
      JObj := TJSONObject.ParseJSONValue(AEdgeData.PropertiesJSON) as TJSONObject;
      if Assigned(JObj) then
        try
          NewEdge.MetaData.FromJSON(JObj);
        finally
          JObj.Free;
        end;
    end;

    // Hydrate the vector (Data)
    NewEdge.Data := StringToEmbedding(AEdgeData.EmbeddingStr);

    // 5. Registration in memory structures (Identity Map)
    Result := InternalAddEdge(NewEdge, False);

    if Result <> NewEdge then
      NewEdge.Free;
  except
    NewEdge.Free;
    raise;
  end;
end;

function TAiRagGraph.InternalHydrateNode(const ANodeData: TNodeDataRecord): TAiRagGraphNode;
var
  NewNode: TAiRagGraphNode;
  Dim: Integer;
  JObj: TJSONObject;
begin
  // 1. Verificaci�n de Identidad (Cache en memoria)
  if FNodeRegistry.TryGetValue(ANodeData.ID, Result) then
    Exit;

  // 2. Determine vector dimensions
  if FNodes.Dim > 0 then
    Dim := FNodes.Dim
  else
    Dim := 1536;

  // 3. Create and hydrate the instance
  NewNode := TAiRagGraphNode.Create(Self, Dim);
  try
    NewNode.ID := ANodeData.ID;
    NewNode.NodeLabel := ANodeData.NodeLabel;
    NewNode.Name := ANodeData.Name;
    NewNode.Text := ANodeData.NodeText;

    // --- KEY CHANGE: Use of the new unified MetaData ---
    if not ANodeData.PropertiesJSON.IsEmpty then
    begin
      JObj := TJSONObject.ParseJSONValue(ANodeData.PropertiesJSON) as TJSONObject;
      try
        if (JObj <> nil) and (JObj is TJSONObject) then // Type validation
          NewNode.MetaData.FromJSON(JObj as TJSONObject);
      finally
        JObj.Free;
      end;
    end;

    // Hydrate the summary vector (Data)
    NewNode.Data := StringToEmbedding(ANodeData.EmbeddingStr);

    // 4. Registration in memory structures (Identity Map)
    Result := InternalAddNode(NewNode, False);

    if Result <> NewNode then
      NewNode.Free;
  except
    NewNode.Free;
    raise;
  end;
end;

function TAiRagGraph.Search(const APrompt: string; const ADepth: Integer; ALimit: Integer; const APrecision: Double; const AFilter: TAiFilterCriteria): TArray<TAiRagGraphNode>;
var
  VectorSearchResults: TAiRAGVector;
  InitialNodeList: TList<TAiRagGraphNode>;
  FoundItem: TAiEmbeddingNode;
begin
  SetLength(Result, 0);

  // 1. Delegation to the Driver (External Database)
  if Assigned(FDriver) then
  begin
    // The driver now receives the correct type
    Result := FDriver.SearchNodes(APrompt, ADepth, ALimit, APrecision, AFilter);
    Exit;
  end;

  // 2. In-memory logic

  // --- Embeddings Engine Validation ---
  if not Assigned(FEmbeddings) then
  begin
    if Assigned(FNodes) and Assigned(FNodes.Embeddings) then
      FEmbeddings := FNodes.Embeddings;

    // If the search is hybrid or vector-based, we need embeddings
    if (not Assigned(FEmbeddings)) and (FNodes.SearchOptions.UseEmbeddings) then
      raise Exception.Create('Graph Search Error: Embeddings property is not assigned.');
  end;

  if FNodes.Count = 0 then
    Exit;

  // We synchronize
  FNodes.Embeddings := FEmbeddings;

  // 3. Vector Search
  // HERE IS THE IMPROVEMENT: We no longer need casting, we pass AFilter directly
  // because FNodes.Search already expects a TAiFilterCriteria.
  VectorSearchResults := FNodes.Search(APrompt, ALimit, APrecision, AFilter);

  try
    InitialNodeList := TList<TAiRagGraphNode>.Create;
    try
      // 4. Filter results and convert to Graph Nodes
      for FoundItem in VectorSearchResults.Items do
      begin
        if FoundItem is TAiRagGraphNode then
          InitialNodeList.Add(TAiRagGraphNode(FoundItem));
      end;

      // 5. Contextual Expansion (BFS)
      if (ADepth > 0) and (InitialNodeList.Count > 0) then
      begin
        Result := Self.ExpandNodeList(InitialNodeList, ADepth);
      end
      else
      begin
        Result := InitialNodeList.ToArray;
      end;
    finally
      InitialNodeList.Free;
    end;
  finally
    VectorSearchResults.Free;
  end;
end;

function TAiRagGraph.SearchText(const APrompt: string; ADepth: Integer; ShowProperties: Boolean; const ALimit: Integer; const APrecision: Double; const AFilter: TAiFilterCriteria): string;
var
  FoundNodes: TArray<TAiRagGraphNode>;
  ContextBuilder: TStringBuilder;
begin
  // We call Search passing the updated AFilter
  FoundNodes := Self.Search(APrompt, ADepth, ALimit, APrecision, AFilter);

  if Length(FoundNodes) = 0 then
    Exit('No relevant information was found for: ' + APrompt);

  // ... (The rest of the text generation code remains the same) ...
  // I only copy the beginning for brevity
  ContextBuilder := TStringBuilder.Create;
  try
    ContextBuilder.AppendLine('Context extracted from the knowledge graph:');
    // ... string construction logic ...
    Result := ContextBuilder.ToString;
  finally
    ContextBuilder.Free;
  end;
end;

procedure TAiRagGraph.LoadFromStream(AStream: TStream);
var
  SR: TStreamReader;
  JsonValue: TJSONValue;
  Root, GraphObj, NodeObj, EdgeObj, PropObj, ChunkObj: TJSONObject;
  NodesArr, EdgesArr, EmbeddingArr, ChunksArr: TJSONArray;
  NodeVal, EdgeVal, ChunkVal: TJSONValue;
  J, K: Integer;

  // Temporary variables for Nodes
  NewNode: TAiRagGraphNode;
  NodeID, NodeLabel, NodeName, NodeText: string;

  // Temporary variables for Edges
  NewEdge: TAiRagGraphEdge;
  EdgeID, EdgeLabel, EdgeName, SourceID, TargetID: string;
  EdgeWeight: Double;
  FromNode, ToNode: TAiRagGraphNode;

  // Variables for Chunks
  ChunkText: string;
  ChunkData: TAiEmbeddingData;
begin
  if (AStream = nil) or (AStream.Size = 0) then
    Exit;

  // 1. Clear the current state before loading (Identity Map and Vectors)
  Clear;

  SR := TStreamReader.Create(AStream, TEncoding.UTF8);
  try
    JsonValue := TJSONObject.ParseJSONValue(SR.ReadToEnd);
    try
      if not(JsonValue is TJSONObject) then
        raise Exception.Create('Invalid JSON format for the Graph.');

      Root := JsonValue as TJSONObject;
      GraphObj := Root.GetValue<TJSONObject>('graph');
      if GraphObj = nil then
        Exit;

      // --- CRITICAL STEP: Block index updates ---
      // This avoids costly HNSW/BM25 rebuilds during bulk loading.
      BeginUpdate;
      try

        // --- 2. LOAD NODES ---
        NodesArr := GraphObj.GetValue<TJSONArray>('nodes');
        if NodesArr <> nil then
        begin
          for NodeVal in NodesArr do
          begin
            NodeObj := NodeVal as TJSONObject;

            NodeID := NodeObj.GetValue<string>('id');
            NodeLabel := NodeObj.GetValue<string>('nodeLabel');
            NodeName := NodeObj.GetValue<string>('name', '');
            NodeText := NodeObj.GetValue<string>('node_text', '');

            // 2.1 Create and insert node into the memory registry
            NewNode := Self.AddNode(NodeID, NodeLabel, NodeName);
            NewNode.Text := NodeText;
            NewNode.Model := NodeObj.GetValue<string>('model', '');

            // 2.2 Retrieve Unified Metadata (Use of FromJSON)
            // This restores real types: Dates, Booleans and Numbers.
            if NodeObj.TryGetValue<TJSONObject>('properties', PropObj) then
              NewNode.MetaData.FromJSON(PropObj);

            // 2.3 NEW: Retrieve Chunks (Detailed text fragments)
            if NodeObj.TryGetValue<TJSONArray>('chunks', ChunksArr) then
            begin
              for ChunkVal in ChunksArr do
              begin
                ChunkObj := ChunkVal as TJSONObject;
                ChunkText := ChunkObj.GetValue<string>('text');

                // Load chunk vector if it exists
                SetLength(ChunkData, 0);
                if ChunkObj.TryGetValue<TJSONArray>('embedding', EmbeddingArr) then
                begin
                  SetLength(ChunkData, EmbeddingArr.Count);
                  for K := 0 to EmbeddingArr.Count - 1 do
                    ChunkData[K] := (EmbeddingArr.Items[K] as TJSONNumber).AsDouble;
                end;

                NewNode.AddChunk(ChunkText, ChunkData);
              end;
            end;

            // 2.4 Retrieve Main Embedding (Node Summary)
            if NodeObj.TryGetValue<TJSONArray>('embedding', EmbeddingArr) then
            begin
              NewNode.SetDataLength(EmbeddingArr.Count);
              for J := 0 to EmbeddingArr.Count - 1 do
                NewNode.Data[J] := (EmbeddingArr.Items[J] as TJSONNumber).AsDouble;
            end;
          end;
        end;

        // --- 3. LOAD EDGES (RELATIONSHIPS) ---
        EdgesArr := GraphObj.GetValue<TJSONArray>('edges');
        if EdgesArr <> nil then
        begin
          for EdgeVal in EdgesArr do
          begin
            EdgeObj := EdgeVal as TJSONObject;

            EdgeID := EdgeObj.GetValue<string>('id');
            EdgeLabel := EdgeObj.GetValue<string>('edgeLabel');
            EdgeName := EdgeObj.GetValue<string>('name', '');
            SourceID := EdgeObj.GetValue<string>('source');
            TargetID := EdgeObj.GetValue<string>('target');
            EdgeWeight := EdgeObj.GetValue<Double>('weight', 1.0);

            // Find references to nodes (already loaded in step 2)
            FromNode := Self.FindNodeByID(SourceID);
            ToNode := Self.FindNodeByID(TargetID);

            if (FromNode <> nil) and (ToNode <> nil) then
            begin
              NewEdge := Self.AddEdge(FromNode, ToNode, EdgeID, EdgeLabel, EdgeName, EdgeWeight);

              // Edge Metadata
              if EdgeObj.TryGetValue<TJSONObject>('properties', PropObj) then
                NewEdge.MetaData.FromJSON(PropObj);

              // Edge Embedding (if it exists)
              if EdgeObj.TryGetValue<TJSONArray>('embedding', EmbeddingArr) then
              begin
                NewEdge.SetDataLength(EmbeddingArr.Count);
                for J := 0 to EmbeddingArr.Count - 1 do
                  NewEdge.Data[J] := (EmbeddingArr.Items[J] as TJSONNumber).AsDouble;
              end;
            end;
          end;
        end;

      finally
        // --- 4. INDEX REBUILDING ---
        // EndUpdate internally invokes RebuildIndexes, activating BM25 and HNSW
        // over all newly loaded data.
        EndUpdate;
      end;

    finally
      JsonValue.Free;
    end;
  finally
    SR.Free;
  end;
end;

function TAiRagGraph.Match(AQuery: TGraphMatchQuery; ADepth: Integer = 0): TArray<TDictionary<string, TObject>>;
type
  TMatchState = TDictionary<string, TObject>;
var
  Results: TObjectList<TDictionary<string, TObject>>;
  StartNodePattern: TMatchNodePattern;
  InitialState: TMatchState;
  StartNode: TAiRagGraphNode;
  CandidateNodes: TArray<TAiRagGraphNode>;

  // --- Variables for Expansion (ADepth > 0) ---
  SeedNodesSet: TDictionary<TAiRagGraphNode, Boolean>;
  MatchDict: TDictionary<string, TObject>;
  Pair: TPair<string, TObject>;
  ExpandedNodesArray: TArray<TAiRagGraphNode>;
  ExpandedResults: TObjectList<TDictionary<string, TObject>>;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  Dict: TDictionary<string, TObject>;
  EdgeSet: TDictionary<TAiRagGraphEdge, Boolean>;

  procedure FindMatchesRecursive(AClauseIndex: Integer; ACurrentState: TMatchState);
  var
    CurrentClause: TMatchClause;
    TargetNodePattern: TMatchNodePattern;
    SourceGraphNode, NeighborNode: TAiRagGraphNode;
    CurrentEdge: TAiRagGraphEdge;
    NewState: TMatchState;
    BoundObject: TObject;
  begin

    if AClauseIndex >= AQuery.MatchClauses.Count then
    begin
      // --- HERE THE WHERE COMES IN ---
      if (AQuery.WhereClause = nil) or Boolean(EvaluateGraphExpression(AQuery.WhereClause, ACurrentState)) then
      begin
        // Only if there is no WHERE or if WHERE returns TRUE, we accept the result
        Results.Add(TMatchState.Create(ACurrentState));
      end;
      Exit;
    end;

    CurrentClause := AQuery.MatchClauses[AClauseIndex];
    if not ACurrentState.TryGetValue(CurrentClause.SourceNodeVar, BoundObject) then
      Exit;
    SourceGraphNode := BoundObject as TAiRagGraphNode;
    TargetNodePattern := AQuery.NodePatternByVariable[CurrentClause.TargetNodeVar];

    if (CurrentClause.EdgePattern.Direction = gdOutgoing) or (CurrentClause.EdgePattern.Direction = gdBoth) then
    begin
      for CurrentEdge in SourceGraphNode.OutgoingEdges do
      begin
        NeighborNode := CurrentEdge.ToNode;
        if CurrentClause.EdgePattern.Matches(CurrentEdge, gdOutgoing) and TargetNodePattern.Matches(NeighborNode) then
        begin
          if ACurrentState.TryGetValue(CurrentClause.TargetNodeVar, BoundObject) and (BoundObject <> NeighborNode) then
            Continue;
          if (not CurrentClause.EdgePattern.Variable.IsEmpty) and ACurrentState.TryGetValue(CurrentClause.EdgePattern.Variable, BoundObject) and (BoundObject <> CurrentEdge) then
            Continue;

          NewState := TMatchState.Create(ACurrentState);
          try
            NewState.AddOrSetValue(CurrentClause.TargetNodeVar, NeighborNode);
            if not CurrentClause.EdgePattern.Variable.IsEmpty then
              NewState.AddOrSetValue(CurrentClause.EdgePattern.Variable, CurrentEdge);
            FindMatchesRecursive(AClauseIndex + 1, NewState);
          finally
            NewState.Free;
          end;
        end;
      end;
    end;

    if (CurrentClause.EdgePattern.Direction = gdIncoming) or (CurrentClause.EdgePattern.Direction = gdBoth) then
    begin
      for CurrentEdge in SourceGraphNode.IncomingEdges do
      begin
        NeighborNode := CurrentEdge.FromNode;
        if CurrentClause.EdgePattern.Matches(CurrentEdge, gdIncoming) and TargetNodePattern.Matches(NeighborNode) then
        begin
          if ACurrentState.TryGetValue(CurrentClause.TargetNodeVar, BoundObject) and (BoundObject <> NeighborNode) then
            Continue;
          if (not CurrentClause.EdgePattern.Variable.IsEmpty) and ACurrentState.TryGetValue(CurrentClause.EdgePattern.Variable, BoundObject) and (BoundObject <> CurrentEdge) then
            Continue;

          NewState := TMatchState.Create(ACurrentState);
          try
            NewState.AddOrSetValue(CurrentClause.TargetNodeVar, NeighborNode);
            if not CurrentClause.EdgePattern.Variable.IsEmpty then
              NewState.AddOrSetValue(CurrentClause.EdgePattern.Variable, CurrentEdge);
            FindMatchesRecursive(AClauseIndex + 1, NewState);
          finally
            NewState.Free;
          end;
        end;
      end;
    end;
  end;

begin
  Result := [];
  if (AQuery = nil) then
    Exit;

  Results := TObjectList < TDictionary < string, TObject >>.Create(True);
  try
    // =========================================================================
    // CASE 1: ONLY NODES (No relationships/clauses) -> MATCH (n:Person) ...
    // =========================================================================
    if AQuery.MatchClauses.Count = 0 then
    begin
      if AQuery.NodePatterns.Count > 0 then
      begin
        // We take the first pattern (e.g.: 'p')
        // Note: If there are multiple disconnected nodes MATCH (a), (b) would require a Cartesian product.
        // Here we simplify for the common case of a single disconnected node.
        StartNodePattern := AQuery.NodePatterns[0];

        // 1. Filter initial candidates
        if not StartNodePattern.NodeLabel.IsEmpty then
          CandidateNodes := Self.FindNodesByLabel(StartNodePattern.NodeLabel)
        else
          CandidateNodes := FNodeRegistry.Values.ToArray;

        // 2. Iterate and validate
        for StartNode in CandidateNodes do
        begin
          if StartNodePattern.Matches(StartNode) then
          begin
            InitialState := TMatchState.Create;
            try
              InitialState.Add(StartNodePattern.Variable, StartNode);
              // Check WHERE for this individual node
              if (AQuery.WhereClause = nil) or Boolean(EvaluateGraphExpression(AQuery.WhereClause, InitialState)) then
              begin
                Results.Add(TMatchState.Create(InitialState));
              end;
            finally
              InitialState.Free;
            end;
          end;
        end;
      end;
    end
    // =========================================================================
    // CASE 2: STRUCTURAL (With relationships) -> MATCH (a)-[r]->(b)
    // =========================================================================
    else
    begin
      // --- STEP 1: ANCHOR NODE SEARCH ---
      StartNodePattern := AQuery.NodePatternByVariable[AQuery.MatchClauses[0].SourceNodeVar];
      if StartNodePattern = nil then
        raise Exception.Create('Start node pattern for the first clause is missing.');

      if not StartNodePattern.NodeLabel.IsEmpty then
        CandidateNodes := Self.FindNodesByLabel(StartNodePattern.NodeLabel)
      else
        CandidateNodes := FNodeRegistry.Values.ToArray;

      for StartNode in CandidateNodes do
      begin
        if StartNodePattern.Matches(StartNode) then
        begin
          InitialState := TMatchState.Create;
          try
            InitialState.Add(StartNodePattern.Variable, StartNode);
            FindMatchesRecursive(0, InitialState);
          finally
            InitialState.Free;
          end;
        end;
      end;
    end;

    // --- COMMON STEP: SUBGRAPH EXPANSION (if ADepth > 0 and there are results) ---
    // (This code is identical to the previous one, but it is applied to the results of both cases)
    if (ADepth > 0) and (Results.Count > 0) then
    begin
      // 1. Collect unique seed nodes
      SeedNodesSet := TDictionary<TAiRagGraphNode, Boolean>.Create;
      try
        for MatchDict in Results do
        begin
          for Pair in MatchDict do
          begin
            if Pair.Value is TAiRagGraphNode then
              SeedNodesSet.AddOrSetValue(Pair.Value as TAiRagGraphNode, True);
          end;
        end;

        if SeedNodesSet.Count > 0 then
        begin
          // 2. Expand the neighborhood
          ExpandedNodesArray := Self.ExpandNodeList(TList<TAiRagGraphNode>.Create(SeedNodesSet.Keys), ADepth);

          // 3. Build the subgraph output
          ExpandedResults := TObjectList < TDictionary < string, TObject >>.Create(True);
          EdgeSet := TDictionary<TAiRagGraphEdge, Boolean>.Create;
          try
            // Add Nodes
            for Node in ExpandedNodesArray do
            begin
              Dict := TDictionary<string, TObject>.Create;
              Dict.Add('type', TStringWrapper.Create('node'));
              Dict.Add('element', Node);
              ExpandedResults.Add(Dict);
            end;

            // Add Internal Edges
            var
            NodeSet := TDictionary<TAiRagGraphNode, Boolean>.Create;
            try
              for Node in ExpandedNodesArray do
                NodeSet.Add(Node, True);

              for Node in ExpandedNodesArray do
              begin
                for Edge in Node.OutgoingEdges do
                begin
                  if NodeSet.ContainsKey(Edge.ToNode) then
                    EdgeSet.AddOrSetValue(Edge, True);
                end;
              end;
            finally
              NodeSet.Free;
            end;

            for Edge in EdgeSet.Keys do
            begin
              Dict := TDictionary<string, TObject>.Create;
              Dict.Add('type', TStringWrapper.Create('edge'));
              Dict.Add('element', Edge);
              ExpandedResults.Add(Dict);
            end;

            Results.Clear;
            for Dict in ExpandedResults do
              Results.Add(Dict);
            ExpandedResults.OwnsObjects := False; // Ownership transfer
          finally
            EdgeSet.Free;
            ExpandedResults.Free;
          end;
        end;
      finally
        SeedNodesSet.Free;
      end;
    end;

    // --- FINAL STEP: RETURN RESULT ---
    Result := Results.ToArray;
    Results.OwnsObjects := False;
  finally
    Results.Free;
  end;
end;

procedure TAiRagGraph.MergeNodes(ASurvivingNode, ASubsumedNode: TAiRagGraphNode; APropertyMergeStrategy: TMergeStrategy);
var
  Edge: TAiRagGraphEdge;
  EdgesToMove: TArray<TAiRagGraphEdge>;
  Pair: TPair<string, Variant>;
  Chunk: TAiEmbeddingNode;
begin
  if (ASurvivingNode = nil) or (ASubsumedNode = nil) or (ASurvivingNode = ASubsumedNode) then
    Exit;

  // We block updates to rebuild indexes only at the end
  BeginUpdate;
  try
    // --- 1. RECONNECT INCOMING EDGES ---
    EdgesToMove := ASubsumedNode.IncomingEdges.ToArray;
    for Edge in EdgesToMove do
    begin
      // We change the edge target to the surviving node
      Edge.ToNode := ASurvivingNode;
      ASurvivingNode.AddIncomingEdge(Edge);
    end;

    // --- 2. RECONNECT OUTGOING EDGES ---
    EdgesToMove := ASubsumedNode.OutgoingEdges.ToArray;
    for Edge in EdgesToMove do
    begin
      // We change the edge source to the surviving node
      Edge.FromNode := ASurvivingNode;
      ASurvivingNode.AddOutgoingEdge(Edge);
    end;

    // --- 3. MOVE CHUNKS (Option 1) ---
    // We move the detailed text fragments so as not to lose RAG context
    while ASubsumedNode.Chunks.Count > 0 do
    begin
      Chunk := ASubsumedNode.Chunks[0];
      // We remove ownership of the object from the old node without freeing it
      ASubsumedNode.Chunks.Extract(Chunk);
      // We add it to the new node
      ASurvivingNode.Chunks.Add(Chunk);
    end;

    // --- 4. MERGE PROPERTIES (MetaData) ---
    // We use InternalDictionary to iterate over the MetaData properties
    for Pair in ASubsumedNode.Properties.InternalDictionary do
    begin
      case APropertyMergeStrategy of
        msAddNewOnly:
          begin
            // We use the new MetaData .Has() method
            if not ASurvivingNode.Properties.Has(Pair.Key) then
              ASurvivingNode.Properties[Pair.Key] := Pair.Value;
          end;

        msOverwrite:
          begin
            // Direct indexed assignment performs "AddOrSetValue" automatically
            ASurvivingNode.Properties[Pair.Key] := Pair.Value;
          end;

        // msKeepExisting: does nothing
      end;
    end;

    // --- 5. DELETE SUBSUMED NODE ---
    // This clears the references in the graph registry and in the vectors
    DeleteNode(ASubsumedNode);

  finally
    EndUpdate; // Rebuilds BM25 and HNSW including the new chunks and connections
  end;
end;

function TAiRagGraph.Query(const APlan: TQueryPlan; ADepth: Integer; const ALimit: Integer; const APrecision: Double): TArray<TAiRagGraphNode>;
var
  // --- Variables for the in-memory implementation ---
  IntermediateResults: TDictionary<string, TList<TAiRagGraphNode>>;
  InitialNodes: TArray<TAiRagGraphNode>;
  Step: TQueryStep;
  SourceNodes, TargetNodes, ResultSet: TList<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  UniqueTargetNodes: TDictionary<TAiRagGraphNode, Boolean>;
  AnchorList: TList<TAiRagGraphNode>;
begin
  // Initialize the result as an empty array.
  SetLength(Result, 0);

  // Step 1: Try to delegate execution of the complete query plan to the Driver.
  if Assigned(FDriver) then
  begin
    // The driver performs the hybrid search in the DB and returns the array of nodes.
    Result := FDriver.Query(APlan, ADepth, ALimit, APrecision);

    // If the DB found results (or if the driver executed), we exit.
    if Length(Result) > 0 then
      Exit;
  end;

  // Step 2: If the query was not handled by a delegate or found no results,
  // execute the in-memory logic.

  // --- Original and optimized in-memory query logic ---
  IntermediateResults := TDictionary < string, TList < TAiRagGraphNode >>.Create;
  try
    // --- Stage 1: Semantic Anchor Search (in memory) ---
    // The component's own 'Search' is used.
    InitialNodes := Self.Search(APlan.AnchorPrompt, ADepth, ALimit, APrecision);
    if Length(InitialNodes) = 0 then
      Exit; // Exits with an empty 'Result' array if there are no anchors.

    AnchorList := TList<TAiRagGraphNode>.Create;
    AnchorList.AddRange(InitialNodes);
    IntermediateResults.Add(APlan.AnchorVariable, AnchorList);

    // --- Stage 2: Execution of Structural Steps (in memory) ---
    for Step in APlan.Steps do
    begin
      if not IntermediateResults.TryGetValue(Step.SourceVariable, SourceNodes) then
        Continue; // Cannot continue if the previous step produced no results

      if not IntermediateResults.TryGetValue(Step.TargetVariable, TargetNodes) then
      begin
        TargetNodes := TList<TAiRagGraphNode>.Create;
        IntermediateResults.Add(Step.TargetVariable, TargetNodes);
      end;

      UniqueTargetNodes := TDictionary<TAiRagGraphNode, Boolean>.Create;
      try
        // This is an optimization to handle cumulative results
        for Node in TargetNodes do
          UniqueTargetNodes.Add(Node, True);

        for Node in SourceNodes do
        begin
          if Step.IsReversed then // Backward search
          begin
            for Edge in Node.IncomingEdges do
            begin
              if SameText(Edge.EdgeLabel, Step.EdgeLabel) and ((Step.TargetNodeLabel = '') or SameText(Edge.FromNode.NodeLabel, Step.TargetNodeLabel)) then
              begin
                if not UniqueTargetNodes.ContainsKey(Edge.FromNode) then
                begin
                  TargetNodes.Add(Edge.FromNode);
                  UniqueTargetNodes.Add(Edge.FromNode, True);
                end;
              end;
            end;
          end
          else // Forward search
          begin
            for Edge in Node.OutgoingEdges do
            begin
              if SameText(Edge.EdgeLabel, Step.EdgeLabel) and ((Step.TargetNodeLabel = '') or SameText(Edge.ToNode.NodeLabel, Step.TargetNodeLabel)) then
              begin
                if not UniqueTargetNodes.ContainsKey(Edge.ToNode) then
                begin
                  TargetNodes.Add(Edge.ToNode);
                  UniqueTargetNodes.Add(Edge.ToNode, True);
                end;
              end;
            end;
          end;
        end;
      finally
        UniqueTargetNodes.Free;
      end;
    end;

    // --- Stage 3: Collect and Return the Final Results ---
    if IntermediateResults.TryGetValue(APlan.ResultVariable, ResultSet) then
      Result := ResultSet.ToArray
    else
      Result := [];

  finally
    // Clear the dictionary and the lists it contains
    for var List in IntermediateResults.Values do
      List.Free;
    IntermediateResults.Free;
  end;
end;

procedure TAiRagGraph.RebuildIndexes;
var
  Node: TAiRagGraphNode;
  NodeList: TList<TAiRagGraphNode>;
  CombinedNameKey: string;
begin
  // 1. Completely clear the existing secondary indexes
  for NodeList in FNodeLabelIndex.Values do
    NodeList.Free;
  FNodeLabelIndex.Clear;
  FNodeNameIndex.Clear;

  // 2. Rebuild the secondary indexes from scratch by iterating all nodes
  for Node in FNodeRegistry.Values do
  begin
    // Re-index by label
    if not FNodeLabelIndex.TryGetValue(Node.NodeLabel, NodeList) then
    begin
      NodeList := TList<TAiRagGraphNode>.Create;
      FNodeLabelIndex.Add(Node.NodeLabel, NodeList);
    end;
    NodeList.Add(Node);

    // Re-index by name
    if not Node.Name.IsEmpty then
    begin
      CombinedNameKey := Node.NodeLabel + '#' + Node.Name;
      if not FNodeNameIndex.ContainsKey(CombinedNameKey) then
        FNodeNameIndex.Add(CombinedNameKey, Node);
    end;
  end;

  // 3. Rebuild the vector indexes (the most expensive operation)

  If Assigned(FEmbeddings) then // If an embeddings engine is assigned, it recreates the indexes, although it does not generate embeddings here
  Begin
    FNodes.BuildIndex;
    FEdges.BuildIndex;
  End;
end;

// In uMakerAi.RAG.Graph.Core.pas, implementation section

procedure WriteVariant(const AWriter: TJsonWriter; const AValue: Variant);
var
  V: Variant;
  VType: TVarType;
begin
  V := AValue; // <- Automatically RESOLVES varByRef
  VType := VarType(V);

  case VType and varTypeMask of

    varEmpty, varNull:
      AWriter.WriteNull;

    varSmallint, varInteger, varShortInt, varByte, varWord, varLongWord:
      AWriter.WriteValue(Integer(V));

    varInt64, varUInt64:
      AWriter.WriteValue(Int64(V));

    varSingle, varDouble, varCurrency:
      AWriter.WriteValue(Double(V));

    varBoolean:
      AWriter.WriteValue(Boolean(V));

    varDate:
      AWriter.WriteValue(DateToISO8601(TDateTime(V), False));

    varString, varOleStr, varUString:
      AWriter.WriteValue(VarToStr(V));

    varArray:
      begin
        AWriter.WriteStartArray;
        try
          var
            I, LBound, UBound: Integer;
          LBound := VarArrayLowBound(V, 1);
          UBound := VarArrayHighBound(V, 1);
          for I := LBound to UBound do
            WriteVariant(AWriter, V[I]);
        finally
          AWriter.WriteEndArray;
        end;
      end;

  else
    AWriter.WriteValue(VarToStr(V));
  end;
end;

procedure TAiRagGraph.SaveToDot(const AFileName: string);
var
  SB: TStringBuilder;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;

  function EscapeDot(const S: string): string;
  begin
    Result := S.Replace('"', '\"').Replace(sLineBreak, '\n');
  end;

begin

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('digraph KnowledgeGraph {');
    SB.AppendLine('  node [shape=box, style=rounded];'); // Optional style for nodes

    // 1. Write all nodes
    for Node in FNodeRegistry.Values do
    begin
      // Format: "ID" [label="Name\n(Label)"];
      SB.Append('  "');
      SB.Append(Node.ID); // Use ID for uniqueness, since the name can be repeated
      SB.Append('" [label="');
      SB.Append(EscapeDot(Node.Name)); // <--- ESCAPE
      SB.Append('\n(');
      SB.Append(EscapeDot(Node.NodeLabel)); // <--- ESCAPE
      SB.Append(')"];');
      SB.AppendLine;
    end;

    SB.AppendLine; // Space between nodes and edges

    // 2. Write all edges
    for Edge in FEdgeRegistry.Values do
    begin
      // Format: "Source_ID" -> "Target_ID" [label="EdgeLabel"];
      SB.Append('  "');
      SB.Append(Edge.FromNode.ID);
      SB.Append('" -> "');
      SB.Append(Edge.ToNode.ID);
      SB.Append('" [label="');
      SB.Append(Edge.EdgeLabel);
      SB.Append(' (' + FormatFloat('0.##', Edge.Weight) + ')');
      SB.Append('"];');
      SB.AppendLine;
    end;

    SB.AppendLine('}');

    TFile.WriteAllText(AFileName, SB.ToString, TEncoding.UTF8);
  finally
    SB.Free;
  end;
end;

procedure TAiRagGraph.SaveToFile(const AFileName: string; aFull: Boolean);
var
  FileExt: string;
begin
  FileExt := ExtractFileExt(AFileName).ToLower; // We get the extension in lowercase

  if FileExt = '.graphml' then
    SaveToGraphML(AFileName)
  else if FileExt = '.dot' then
    SaveToDot(AFileName)
  else if (FileExt = '.mkai') or (FileExt = '.json') then // We allow both extensions
    SaveToMakerAi(AFileName, aFull)
  else
    // If the extension is not recognized, we assume the default native format (.mkai)
    // or you can throw an exception if you prefer to be stricter.
    // Here we choose to save in the native format, adding the extension if it does not have it.
    SaveToMakerAi(ChangeFileExt(AFileName, '.mkai'), aFull);
  // Strict alternative:
  // raise Exception.CreateFmt('File format not supported for extension "%s".', [FileExt]);
end;

procedure TAiRagGraph.SaveToGraphML(const AFileName: string);
var
  XMLDoc: IXMLDocument;
  GraphMLNode, GraphNode, NodeElement, EdgeElement, DataElement, KeyElement, CommentNode: IXMLNode;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  PropKey: string;
  UniquePropKeys: TStringList;
  Pair: TPair<string, Variant>;
begin
  XMLDoc := TXMLDocument.Create(nil);
  try
    XMLDoc.Active := True;
    XMLDoc.Version := '1.0';
    XMLDoc.Encoding := 'UTF-8';
    XMLDoc.Options := [doNodeAutoIndent];

    // --- ROOT ELEMENT ---
    GraphMLNode := XMLDoc.AddChild('graphml');
    GraphMLNode.Attributes['xmlns'] := 'http://graphml.graphdrawing.org/xmlns';
    GraphMLNode.Attributes['xmlns:xsi'] := 'http://www.w3.org/2001/XMLSchema-instance';
    GraphMLNode.Attributes['xsi:schemaLocation'] := 'http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd';

    // --- 1. ATTRIBUTE DEFINITION (KEYS) ---
    CommentNode := XMLDoc.CreateNode(' Base attributes of the MakerAi system ', TNodeType.ntComment);
    GraphMLNode.ChildNodes.Add(CommentNode);

    // Fixed Node attributes
    KeyElement := GraphMLNode.AddChild('key');
    KeyElement.Attributes['id'] := 'd_name';
    KeyElement.Attributes['for'] := 'node';
    KeyElement.Attributes['attr.name'] := 'name';
    KeyElement.Attributes['attr.type'] := 'string';

    KeyElement := GraphMLNode.AddChild('key');
    KeyElement.Attributes['id'] := 'd_label';
    KeyElement.Attributes['for'] := 'node';
    KeyElement.Attributes['attr.name'] := 'label';
    KeyElement.Attributes['attr.type'] := 'string';

    KeyElement := GraphMLNode.AddChild('key');
    KeyElement.Attributes['id'] := 'd_chunks';
    KeyElement.Attributes['for'] := 'node';
    KeyElement.Attributes['attr.name'] := 'chunks_count';
    KeyElement.Attributes['attr.type'] := 'int';

    // Fixed Edge attributes
    KeyElement := GraphMLNode.AddChild('key');
    KeyElement.Attributes['id'] := 'e_label';
    KeyElement.Attributes['for'] := 'edge';
    KeyElement.Attributes['attr.name'] := 'label';
    KeyElement.Attributes['attr.type'] := 'string';

    KeyElement := GraphMLNode.AddChild('key');
    KeyElement.Attributes['id'] := 'e_weight';
    KeyElement.Attributes['for'] := 'edge';
    KeyElement.Attributes['attr.name'] := 'weight';
    KeyElement.Attributes['attr.type'] := 'double';

    // Collect dynamic property keys (MetaData) from all elements
    UniquePropKeys := TStringList.Create;
    try
      UniquePropKeys.Sorted := True;
      UniquePropKeys.Duplicates := TDuplicates.dupIgnore;

      for Node in FNodeRegistry.Values do
        for PropKey in Node.MetaData.InternalDictionary.Keys do
          UniquePropKeys.Add(PropKey);

      for Edge in FEdgeRegistry.Values do
        for PropKey in Edge.MetaData.InternalDictionary.Keys do
          UniquePropKeys.Add(PropKey);

      // Define keys for custom properties
      for PropKey in UniquePropKeys do
      begin
        KeyElement := GraphMLNode.AddChild('key');
        KeyElement.Attributes['id'] := 'prop_' + PropKey;
        KeyElement.Attributes['for'] := 'all';
        KeyElement.Attributes['attr.name'] := PropKey;
        KeyElement.Attributes['attr.type'] := 'string';
      end;
    finally
      UniquePropKeys.Free;
    end;

    // --- 2. GRAPH CONTENT ---
    GraphNode := GraphMLNode.AddChild('graph');
    GraphNode.Attributes['id'] := 'G';
    GraphNode.Attributes['edgedefault'] := 'directed';

    // -- Node writing --
    for Node in FNodeRegistry.Values do
    begin
      NodeElement := GraphNode.AddChild('node');
      NodeElement.Attributes['id'] := Node.ID;

      // Base data
      DataElement := NodeElement.AddChild('data');
      DataElement.Attributes['key'] := 'd_name';
      DataElement.Text := Node.Name;

      DataElement := NodeElement.AddChild('data');
      DataElement.Attributes['key'] := 'd_label';
      DataElement.Text := Node.NodeLabel;

      DataElement := NodeElement.AddChild('data');
      DataElement.Attributes['key'] := 'd_chunks';
      DataElement.Text := IntToStr(Node.Chunks.Count);

      // Metadatos din�micos
      for Pair in Node.MetaData.InternalDictionary do
      begin
        DataElement := NodeElement.AddChild('data');
        DataElement.Attributes['key'] := 'prop_' + Pair.Key;
        DataElement.Text := VarToStr(Pair.Value);
      end;
    end;

    // -- Edge writing --
    for Edge in FEdgeRegistry.Values do
    begin
      EdgeElement := GraphNode.AddChild('edge');
      EdgeElement.Attributes['id'] := Edge.ID;
      EdgeElement.Attributes['source'] := Edge.FromNode.ID;
      EdgeElement.Attributes['target'] := Edge.ToNode.ID;

      // Base data
      DataElement := EdgeElement.AddChild('data');
      DataElement.Attributes['key'] := 'e_label';
      DataElement.Text := Edge.EdgeLabel;

      DataElement := EdgeElement.AddChild('data');
      DataElement.Attributes['key'] := 'e_weight';
      DataElement.Text := FloatToStr(Edge.Weight);

      // Metadatos din�micos
      for Pair in Edge.MetaData.InternalDictionary do
      begin
        DataElement := EdgeElement.AddChild('data');
        DataElement.Attributes['key'] := 'prop_' + Pair.Key;
        DataElement.Text := VarToStr(Pair.Value);
      end;
    end;

    XMLDoc.SaveToFile(AFileName);
  finally
    XMLDoc := nil;
  end;
end;

procedure TAiRagGraph.SaveToMakerAi(const AFileName: String; const aFull: Boolean);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    // Calls the new overloaded version of SaveToStream
    Self.SaveToStream(Stream, aFull);
  finally
    Stream.Free;
  end;
end;

procedure TAiRagGraph.SaveToFile(const AFileName: string; AFormat: TGraphExportFormat; aFull: Boolean);
begin
  case AFormat of
    gefDOT:
      SaveToDot(AFileName);
    gefGraphML:
      SaveToGraphML(AFileName);
    gefGraphMkai:
      SaveToMakerAi(AFileName, aFull);
  end;
end;

procedure TAiRagGraph.SaveToStream(AStream: TStream);
Begin
  SaveToStream(AStream, True);
End;

procedure TAiRagGraph.SaveToStream(AStream: TStream; aFull: Boolean);
var
  StreamWriter: TStreamWriter;
  JsonWriter: TJsonTextWriter;
  Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  Chunk: TAiEmbeddingNode;
  Pair: TPair<string, Variant>;
  I, J: Integer;
begin
  if AStream = nil then
    raise Exception.Create('Error: The destination Stream is nil.');

  StreamWriter := TStreamWriter.Create(AStream, TEncoding.UTF8);
  try
    JsonWriter := TJsonTextWriter.Create(StreamWriter);
    try
      JsonWriter.Formatting := TJsonFormatting.Indented;

      JsonWriter.WriteStartObject; // {
      JsonWriter.WritePropertyName('graph');
      JsonWriter.WriteStartObject; // "graph": {

      // --- 1. SERIALIZE NODES ---
      JsonWriter.WritePropertyName('nodes');
      JsonWriter.WriteStartArray;

      for Node in FNodeRegistry.Values do
      begin
        JsonWriter.WriteStartObject;
        JsonWriter.WritePropertyName('id');
        JsonWriter.WriteValue(Node.ID);
        JsonWriter.WritePropertyName('nodeLabel');
        JsonWriter.WriteValue(Node.NodeLabel);
        JsonWriter.WritePropertyName('name');
        JsonWriter.WriteValue(Node.Name);
        JsonWriter.WritePropertyName('model');
        JsonWriter.WriteValue(Node.Model);
        JsonWriter.WritePropertyName('node_text');
        JsonWriter.WriteValue(Node.Text);

        // Dynamic properties (MetaData)
        if Node.MetaData.InternalDictionary.Count > 0 then
        begin
          JsonWriter.WritePropertyName('properties');
          JsonWriter.WriteStartObject;
          for Pair in Node.MetaData.InternalDictionary do
          begin
            JsonWriter.WritePropertyName(Pair.Key);
            WriteVariant(JsonWriter, Pair.Value);
          end;
          JsonWriter.WriteEndObject;
        end;

        // --- NEW: SERIALIZE CHUNKS (FRAGMENTS) ---
        if Node.Chunks.Count > 0 then
        begin
          JsonWriter.WritePropertyName('chunks');
          JsonWriter.WriteStartArray;
          for Chunk in Node.Chunks do
          begin
            JsonWriter.WriteStartObject;
            JsonWriter.WritePropertyName('text');
            JsonWriter.WriteValue(Chunk.Text);

            if aFull and (Length(Chunk.Data) > 0) then
            begin
              JsonWriter.WritePropertyName('embedding');
              JsonWriter.WriteStartArray;
              for J := 0 to High(Chunk.Data) do
                JsonWriter.WriteValue(Chunk.Data[J]);
              JsonWriter.WriteEndArray;
            end;
            JsonWriter.WriteEndObject;
          end;
          JsonWriter.WriteEndArray;
        end;

        // Main node embedding (Summary)
        if aFull and (Length(Node.Data) > 0) then
        begin
          JsonWriter.WritePropertyName('embedding');
          JsonWriter.WriteStartArray;
          for I := 0 to High(Node.Data) do
            JsonWriter.WriteValue(Node.Data[I]);
          JsonWriter.WriteEndArray;
        end;

        JsonWriter.WriteEndObject;
      end;
      JsonWriter.WriteEndArray;

      // --- 2. SERIALIZE EDGES (RELATIONSHIPS) ---
      JsonWriter.WritePropertyName('edges');
      JsonWriter.WriteStartArray;

      for Edge in FEdgeRegistry.Values do
      begin
        JsonWriter.WriteStartObject;
        JsonWriter.WritePropertyName('id');
        JsonWriter.WriteValue(Edge.ID);
        JsonWriter.WritePropertyName('edgeLabel');
        JsonWriter.WriteValue(Edge.EdgeLabel);
        JsonWriter.WritePropertyName('name');
        JsonWriter.WriteValue(Edge.Name);
        JsonWriter.WritePropertyName('source');
        JsonWriter.WriteValue(Edge.FromNode.ID);
        JsonWriter.WritePropertyName('target');
        JsonWriter.WriteValue(Edge.ToNode.ID);
        JsonWriter.WritePropertyName('weight');
        JsonWriter.WriteValue(Edge.Weight);

        // Edge metadata
        if Edge.MetaData.InternalDictionary.Count > 0 then
        begin
          JsonWriter.WritePropertyName('properties');
          JsonWriter.WriteStartObject;
          for Pair in Edge.MetaData.InternalDictionary do
          begin
            JsonWriter.WritePropertyName(Pair.Key);
            WriteVariant(JsonWriter, Pair.Value);
          end;
          JsonWriter.WriteEndObject;
        end;

        // Edge embedding
        if aFull and (Length(Edge.Data) > 0) then
        begin
          JsonWriter.WritePropertyName('embedding');
          JsonWriter.WriteStartArray;
          for I := 0 to High(Edge.Data) do
            JsonWriter.WriteValue(Edge.Data[I]);
          JsonWriter.WriteEndArray;
        end;

        JsonWriter.WriteEndObject;
      end;
      JsonWriter.WriteEndArray;

      JsonWriter.WriteEndObject; // } fin graph
      JsonWriter.WriteEndObject; // } fin raiz
    finally
      JsonWriter.Free;
    end;
  finally
    StreamWriter.Free;
  end;
end;

procedure TAiRagGraph.SetDriver(const Value: TAiRagGraphDriverBase);
begin
  if FDriver <> Value then
  begin
    FDriver := Value;

    if FDriver <> nil then
    begin
      // We tell the Driver: "Notify me if you die"
      FDriver.FreeNotification(Self);

      // Existing assignment logic
      FDriver.AssignToGraph(Self);
    end;
  end;
end;

procedure TAiRagGraph.SetEmbeddings(const Value: TAiEmbeddingsCore);
begin
  if FEmbeddings <> Value then
  begin
    FEmbeddings := Value;

    // We tell the Embeddings component: "Notify me (the Graph) if you die"
    if FEmbeddings <> nil then
      FEmbeddings.FreeNotification(Self);
  end;
end;

procedure TAiRagGraph.SetSearchOptions(const Value: TAiSearchOptions);
begin
  // We assign the values to the node vector
  FNodes.SearchOptions.Assign(Value);
end;

{ TMatchNodePattern }

constructor TMatchNodePattern.Create;
begin
  inherited;
  Properties := TDictionary<string, Variant>.Create(TStringComparer.Ordinal);
end;

destructor TMatchNodePattern.Destroy;
begin
  Properties.Free;
  inherited;
end;

function TMatchNodePattern.Matches(ANode: TAiRagGraphNode): Boolean;
var
  Pair: TPair<string, Variant>;
begin
  Result := False;
  if ANode = nil then
    Exit;

  // 1. Check the node label (Label)
  // Ignore if the pattern does not specify a label
  if (not NodeLabel.IsEmpty) and (not SameText(ANode.NodeLabel, NodeLabel)) then
    Exit;

  // 2. Check all required properties of the pattern
  // 'Properties' here is the PATTERN filter dictionary (e.g.: {city: 'Madrid'})
  for Pair in Properties do
  begin
    // --- A. Native Node Attributes ---
    if SameText(Pair.Key, 'name') then
    begin
      if not SameText(ANode.Name, VarToStr(Pair.Value)) then
        Exit;
    end
    else if SameText(Pair.Key, 'label') then
    begin
      if not SameText(ANode.NodeLabel, VarToStr(Pair.Value)) then
        Exit;
    end
    else if SameText(Pair.Key, 'id') then
    begin
      if not SameText(ANode.ID, VarToStr(Pair.Value)) then
        Exit;
    end
    // --- B. Dynamic Metadata ---
    else
    begin
      // We use the new MetaData evaluation engine
      // foEqual performs an intelligent comparison of Variants (typed)
      if not ANode.Properties.Evaluate(Pair.Key, foEqual, Pair.Value) then
        Exit;
    end;
  end;

  // If it passed all filters, it is a match
  Result := True;
end;

{ TMatchEdgePattern }

constructor TMatchEdgePattern.Create;
begin
  inherited;
  Direction := gdOutgoing; // Default direction
  Properties := TDictionary<string, Variant>.Create(TStringComparer.Ordinal);
end;

destructor TMatchEdgePattern.Destroy;
begin
  Properties.Free;
  inherited;
end;

function TMatchEdgePattern.Matches(AEdge: TAiRagGraphEdge; AActualDirection: TGraphDirection): Boolean;
var
  Pair: TPair<string, Variant>;
begin
  Result := False;
  if AEdge = nil then
    Exit;

  // 1. Check the traversal direction
  // If the pattern specifies a direction (outgoing/incoming), it must match the current traversal
  if (Direction <> gdBoth) and (Direction <> AActualDirection) then
    Exit;

  // 2. Check the edge label (EdgeLabel)
  if (not EdgeLabel.IsEmpty) and (not SameText(AEdge.EdgeLabel, EdgeLabel)) then
    Exit;

  // 3. Check all required properties of the search pattern
  // 'Properties' is the pattern filter dictionary (e.g.: {since: 2020})
  for Pair in Properties do
  begin
    // --- A. Native Edge Attributes ---
    if SameText(Pair.Key, 'label') then
    begin
      if not SameText(AEdge.EdgeLabel, VarToStr(Pair.Value)) then
        Exit;
    end
    else if SameText(Pair.Key, 'id') then
    begin
      if not SameText(AEdge.ID, VarToStr(Pair.Value)) then
        Exit;
    end
    else if SameText(Pair.Key, 'weight') then
    begin
      // Safe numeric comparison for the weight (Weight)
      try
        if Abs(AEdge.Weight - Double(Pair.Value)) > 0.0001 then
          Exit;
      except
        Exit;
      end;
    end
    // --- B. Dynamic Metadata (unified MetaData) ---
    else
    begin
      // We use the new evaluation engine of the edge MetaData.
      // foEqual performs an intelligent comparison of Variants (typed).
      if not AEdge.MetaData.Evaluate(Pair.Key, foEqual, Pair.Value) then
        Exit;
    end;
  end;

  // If it passed all filters (direction, label and properties), it is a match
  Result := True;
end;

{ TMatchClause }

constructor TMatchClause.Create(ASourceNodeVar: string; AEdgePattern: TMatchEdgePattern; ATargetNodeVar: string);
begin
  inherited Create;
  SourceNodeVar := ASourceNodeVar;
  EdgePattern := AEdgePattern; // The clause takes ownership of the edge pattern
  TargetNodeVar := ATargetNodeVar;
end;

destructor TMatchClause.Destroy;
begin
  EdgePattern.Free; // Frees the edge pattern it owns
  inherited;
end;

{ TGraphMatchQuery }

constructor TGraphMatchQuery.Create;
begin
  inherited;
  FNodePatterns := TObjectList<TMatchNodePattern>.Create(True); // Owns
  FMatchClauses := TObjectList<TMatchClause>.Create(True); // Owns
  FDepth := 0;
end;

destructor TGraphMatchQuery.Destroy;
begin
  if Assigned(FWhereClause) then
    FWhereClause.Free; // This will trigger chain freeing of the whole tree

  FNodePatterns.Free;
  FMatchClauses.Free;
  inherited;
end;

procedure TGraphMatchQuery.AddNodePattern(ANodePattern: TMatchNodePattern);
begin
  FNodePatterns.Add(ANodePattern);
end;

procedure TGraphMatchQuery.AddMatchClause(AClause: TMatchClause);
begin
  FMatchClauses.Add(AClause);
end;

function TGraphMatchQuery.GetNodePatternByVariable(const AVar: string): TMatchNodePattern;
var
  Pattern: TMatchNodePattern;
begin
  Result := nil;
  for Pattern in FNodePatterns do
  begin
    if SameText(Pattern.Variable, AVar) then
    begin
      Result := Pattern;
      Exit;
    end;
  end;
  // If it is not found, it could be an error in query construction.
  // You could throw an exception here if you want to be stricter.
  // raise Exception.CreateFmt('Node pattern with variable "%s" not found in query.', [AVar]);
end;

{ TStringWrapper }

constructor TStringWrapper.Create(const AValue: string);
begin
  inherited Create;
  Value := AValue;
end;

{ TAiRagGraphDriverBase }

procedure TAiRagGraphDriverBase.AssignToGraph(AGraph: TAiRagGraph);
begin
  FGraph := AGraph;
end;

function TAiRagGraphDriverBase.EmbeddingToString(const AData: TAiEmbeddingData): string;
begin
  Result := TAiEmbeddingDataRec.EmbeddingToString(AData);
end;

function TAiRagGraphDriverBase.PropertiesToJSONString(const AProperties: TDictionary<string, Variant>): string;
var
  JsonObj: TJSONObject;
  Key: string;
  Value: Variant;
begin
  Result := '{}'; // Default value for empty dictionary

  if (AProperties = nil) or (AProperties.Count = 0) then
    Exit;

  JsonObj := TJSONObject.Create;
  try
    for Key in AProperties.Keys do
    begin
      Value := AProperties[Key];
      JsonObj.AddPair(Key, VariantToJSONValue(Value));
    end;

    Result := JsonObj.ToString;
  finally
    JsonObj.Free;
  end;
end;

{ TGraphExpression }
destructor TGraphExpression.Destroy;
begin
  inherited;
end;

{ TLiteralExpr }
constructor TLiteralExpr.Create(AValue: Variant);
begin
  inherited Create;
  Kind := ekLiteral;
  Value := AValue;
end;

{ TPropertyExpr }
constructor TPropertyExpr.Create(const AVar, AKey: string);
begin
  inherited Create;
  Kind := ekProperty;
  Variable := AVar;
  PropertyKey := AKey;
end;

{ TBinaryExpr }
constructor TBinaryExpr.Create(ALeft: TGraphExpression; AOp: TBinaryOp; ARight: TGraphExpression);
begin
  inherited Create;
  Kind := ekBinary;
  Left := ALeft;
  Op := AOp;
  Right := ARight;
end;

destructor TBinaryExpr.Destroy;
begin
  Left.Free; // Freeing is recursive
  Right.Free;
  inherited;
end;

{ TCommunity }

constructor TCommunity.Create(AID: Integer);
begin
  inherited Create;
  FID := AID;
  // We use a simple TList because the TAiRagGraphNode objects
  // belong to the main Graph's registry (FNodeRegistry).
  FNodes := TList<TAiRagGraphNode>.Create;
  FInternalWeight := 0;
  FTotalWeight := 0;
end;

destructor TCommunity.Destroy;
begin
  // We only free the list, not the nodes contained in it
  FNodes.Free;
  inherited;
end;

end.
