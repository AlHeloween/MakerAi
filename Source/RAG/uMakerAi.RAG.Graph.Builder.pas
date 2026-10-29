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
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.RAG.Graph.Builder;

interface

uses
  System.SysUtils, System.Classes, System.Json, System.Generics.Collections,
  System.Variants, uMakerAi.RAG.Vectors, uMakerAi.Embeddings.core, uMakerAi.Embeddings,
  uMakerAi.RAG.Graph.core; // Include the graph unit

type
  { TAiRagGraphBuilder }

  TOnImportProgress = procedure(Sender: TObject; Position, Total: Integer; var Cancel: Boolean) of object;

  TAiRagGraphBuilder = class(TComponent)
  private
    FGraph: TAiRagGraph;
    FOnImportProgress: TOnImportProgress;
    procedure SetGraph(const Value: TAiRagGraph);
  protected
    procedure MergeNodeProperties(ANode: TAiRagGraphNode; ANewProperties: TJSONObject; AStrategy: TMergeStrategy);
    procedure MergeEdgeProperties(AEdge: TAiRagGraphEdge; ANewProperties: TJSONObject; AStrategy: TMergeStrategy);
    function GetOrCreateNode(ANodeObject: TJSONObject; AMergeStrategy: TMergeStrategy): TAiRagGraphNode;
    function GenerateTextForEmbedding(AName, ANodeLabel: string; AProperties: TJSONObject; AAdditionalText: String = ''): string; overload;
    function GenerateTextForEmbedding(AName, ANodeLabel: string; AProperties: TDictionary<string, Variant>; AAdditionalText: String = ''): string; overload;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    Function Process(AJsonTripletArray: string; AMergeStrategy: TMergeStrategy = msAddNewOnly): Integer; // Returns the number of inserted items
    function FindExistingNode(AName, ALabel: string): TAiRagGraphNode;

  published
    property Graph: TAiRagGraph read FGraph write SetGraph;
    Property OnImportProgress: TOnImportProgress read FOnImportProgress write FOnImportProgress;

  end;

procedure Register;

implementation

uses
  System.NetEncoding; // For Base64 if necessary

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiRagGraphBuilder]);
end;

{ TAiRagGraphBuilder }

constructor TAiRagGraphBuilder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGraph := nil;
end;

destructor TAiRagGraphBuilder.Destroy;
begin
  inherited;
end;

function TAiRagGraphBuilder.FindExistingNode(AName, ALabel: string): TAiRagGraphNode;
begin
  Result := FGraph.FindNodeByName(AName, ALabel);
end;

procedure TAiRagGraphBuilder.MergeEdgeProperties(AEdge: TAiRagGraphEdge; ANewProperties: TJSONObject; AStrategy: TMergeStrategy);
var
  Pair: TJSONPair;
  Key: string;
  Value: Variant;
begin
  if (ANewProperties = nil) or (AStrategy = msKeepExisting) or (AEdge = nil) then
    Exit;

  for Pair in ANewProperties do
  begin
    Key := Pair.JsonString.Value;
    Value := JSONValueToVariant(Pair.JsonValue); // Helper to convert TJSONValue to Variant

    case AStrategy of
      msOverwrite:
        // The indexed property by default automatically performs AddOrSetValue
        AEdge.MetaData[Key] := Value;

      msAddNewOnly:
        // Use the .Has() method of the new MetaData unit
        if not AEdge.MetaData.Has(Key) then
          AEdge.MetaData[Key] := Value;
    end;
  end;
end;

procedure TAiRagGraphBuilder.MergeNodeProperties(ANode: TAiRagGraphNode; ANewProperties: TJSONObject; AStrategy: TMergeStrategy);
var
  Pair: TJSONPair;
  Key: string;
  Value: Variant;
begin
  if (ANewProperties = nil) or (AStrategy = msKeepExisting) or (ANode = nil) then
    Exit;

  for Pair in ANewProperties do
  begin
    Key := Pair.JsonString.Value;
    Value := JSONValueToVariant(Pair.JsonValue);

    case AStrategy of
      msOverwrite:
        ANode.Properties[Key] := Value;

      msAddNewOnly:
        if not ANode.Properties.Has(Key) then
          ANode.Properties[Key] := Value;
    end;
  end;
end;

procedure TAiRagGraphBuilder.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FGraph) then
    FGraph := nil;
end;

function TAiRagGraphBuilder.GenerateTextForEmbedding(AName, ANodeLabel: string; AProperties: TJSONObject; AAdditionalText: String = ''): string;
var
  ContextBuilder: TStringBuilder;
  Pair: TJSONPair;
  PropertyValue: string;
begin
  ContextBuilder := TStringBuilder.Create;
  try
    // 1. IDENTIFICATION: Structured format for the embedding model
    ContextBuilder.AppendFormat('Entity: %s. Category: %s.', [AName, ANodeLabel]);

    // 2. PROPERTIES: Convert the JSON into descriptive sentences
    if Assigned(AProperties) then
    begin
      for Pair in AProperties do
      begin
        // Try to obtain a clean text representation of the value
        if Pair.JsonValue is TJSONString then
          PropertyValue := Pair.JsonValue.Value
        else
          PropertyValue := Pair.JsonValue.ToJSON;

        // Generate natural language for better semantic indexing
        ContextBuilder.AppendFormat(' The property %s has the value %s.', [Pair.JsonString.Value, PropertyValue]);
      end;
    end;

    // 3. ADDITIONAL CONTENT: Clean and normalize punctuation
    if not AAdditionalText.Trim.IsEmpty then
    begin
      ContextBuilder.Append(' ');
      ContextBuilder.Append(AAdditionalText.Trim);

      if not AAdditionalText.Trim.EndsWith('.') then
        ContextBuilder.Append('.');
    end;

    Result := ContextBuilder.ToString;
  finally
    ContextBuilder.Free;
  end;
end;

function TAiRagGraphBuilder.GenerateTextForEmbedding(AName, ANodeLabel: string; AProperties: TDictionary<string, Variant>; AAdditionalText: String): string;
var
  ContextBuilder: TStringBuilder;
  Pair: TPair<string, Variant>;
begin
  ContextBuilder := TStringBuilder.Create;
  try
    ContextBuilder.AppendFormat('Entity: %s. Type: %s. ', [AName, ANodeLabel]);

    if Assigned(AProperties) then
    begin
      for Pair in AProperties do
      begin
        if not SameText(Pair.Key, 'name') then
          ContextBuilder.AppendFormat('%s: %s. ', [Pair.Key, VarToStr(Pair.Value)]);
      end;
    end;

    if not AAdditionalText.IsEmpty then
      ContextBuilder.Append(AAdditionalText);

    Result := ContextBuilder.ToString;
  finally
    ContextBuilder.Free;
  end;
end;

function TAiRagGraphBuilder.GetOrCreateNode(ANodeObject: TJSONObject; AMergeStrategy: TMergeStrategy): TAiRagGraphNode;
var
  NodeName, NodeLabel, NodeText, AdditionalText: string;
  NewProperties: TJSONObject;
  CurrentPropsJson: TJSONObject;
  NeedEmbeddingUpdate: Boolean;
  LEmbeddings: TAiEmbeddingsCore;
begin
  if FGraph = nil then
    raise Exception.Create('Graph property is not assigned to the builder.');

  LEmbeddings := FGraph.Embeddings;

// 1. Extract basic data from the input JSON object
  NodeName := ANodeObject.GetValue<string>('name', '');
  NodeLabel := ANodeObject.GetValue<string>('nodeLabel', 'Undefined');

  if NodeName.Trim.IsEmpty then
    raise Exception.Create('Node name cannot be empty.');

  NewProperties := ANodeObject.GetValue<TJSONObject>('properties', nil);
  AdditionalText := ANodeObject.GetValue<string>('text', '');

  // 2. Try to find if the node already exists in the graph (by Name and Label)
  Result := FGraph.FindNodeByName(NodeName, NodeLabel);

  if Result <> nil then
  begin
    // =========================================================
    // CASE A: EXISTING NODE
    // =========================================================
    // Check if it is necessary to recalculate the summary embedding
    NeedEmbeddingUpdate := (LEmbeddings <> nil) and (Length(Result.Data) = 0);

    // Merge new properties with existing ones using the new MetaData
    if Assigned(NewProperties) then
    begin
      MergeNodeProperties(Result, NewProperties, AMergeStrategy);
      NeedEmbeddingUpdate := True;
    end;

    // If there is additional text, mark to update the summary
    if not AdditionalText.Trim.IsEmpty then
      NeedEmbeddingUpdate := True;

    if NeedEmbeddingUpdate then
    begin
      // Generate the descriptive text based on the final state of MetaData
      CurrentPropsJson := Result.Properties.ToJSON;
      try
        NodeText := GenerateTextForEmbedding(Result.Name, Result.NodeLabel, CurrentPropsJson, AdditionalText);
        Result.Text := NodeText;
      finally
        CurrentPropsJson.Free;
      end;

      // Regenerate the vector (Embedding) if an engine is assigned
      if LEmbeddings <> nil then
      begin
        Result.Model := LEmbeddings.Model;
        Result.Data := LEmbeddings.CreateEmbedding(Result.Text, 'user');
      end;

      // NOTE: The persistence driver (if any) must be notified
      // of this change by the Core or through an explicit save.
    end;
  end
  else
  begin
    // =========================================================
    // CASE B: NEW NODE (Optimized factory)
    // =========================================================
    // 1. Create the object in memory (automatically inherits MetaData)
    Result := FGraph.NewNode(TGuid.NewGuid.ToString, NodeLabel, NodeName);

    // 2. Fill dynamic properties
    if Assigned(NewProperties) then
      MergeNodeProperties(Result, NewProperties, msOverwrite);

    // 3. Generate representative text for the semantic engine
    CurrentPropsJson := Result.Properties.ToJSON;
    try
      NodeText := GenerateTextForEmbedding(Result.Name, Result.NodeLabel, CurrentPropsJson, AdditionalText);
      Result.Text := NodeText;
    finally
      CurrentPropsJson.Free;
    end;

    // 4. Calculate the vector of the new node
    if LEmbeddings <> nil then
    begin
      Result.Model := LEmbeddings.Model;
      Result.Data := LEmbeddings.CreateEmbedding(Result.Text, 'user');
    end;

// 5. Register and persist in the Graph (a single atomic step)
    FGraph.AddNode(Result);
  end;
end;

Function TAiRagGraphBuilder.Process(AJsonTripletArray: string; AMergeStrategy: TMergeStrategy): Integer;
var
  JsonValue, TripletValue: TJSONValue;
  JsonArray: TJSONArray;
  TripletObject: TJSONObject;
  SubjectObj, PredicateObj, ObjectObj: TJSONObject;
  SubjectNode, ObjectNode: TAiRagGraphNode;
  EdgeLabel, EdgeName, TextToEmbed: string;
  PredicateProps: TJSONObject;
  ExistingEdge: TAiRagGraphEdge;
  NewEdge: TAiRagGraphEdge;
  LEmbeddings: TAiEmbeddingsCore;
  NeedEmbeddingUpdate: Boolean;
  I, TotCount: Integer;
  Cancel: Boolean;
begin
  if FGraph = nil then
    raise Exception.Create('Graph property is not assigned to the builder.');

  // 1. Get the embedding engine from the graph
  LEmbeddings := FGraph.Embeddings;

  // 2. Parse the JSON
  JsonValue := TJSONObject.ParseJSONValue(AJsonTripletArray);
  try
    if not(JsonValue is TJSONArray) then
      raise Exception.Create('Input JSON is not a valid JSON array of triplets.');

    JsonArray := JsonValue as TJSONArray;

    FGraph.BeginUpdate;
    try

      I := 0;
      TotCount := JsonArray.Count;

      for TripletValue in JsonArray do
      begin
        if not(TripletValue is TJSONObject) then
          continue;

        Inc(I);

        if Assigned(FOnImportProgress) then
        begin
          // Report the current index 'i' over the total
          FOnImportProgress(Self, I, TotCount, Cancel);
          if Cancel then
            Break;
        end;

        TripletObject := TripletValue as TJSONObject;

        // Extract triple components
        SubjectObj := TripletObject.GetValue<TJSONObject>('subject', nil);
        PredicateObj := TripletObject.GetValue<TJSONObject>('predicate', nil);
        ObjectObj := TripletObject.GetValue<TJSONObject>('object', nil);

        // CASE A: Only node update (Subject without predicate)
        if (SubjectObj <> nil) and (PredicateObj = nil) and (ObjectObj = nil) then
        begin
          GetOrCreateNode(SubjectObj, AMergeStrategy);
          continue;
        end;

        // Validate triple integrity for relationships
        if (SubjectObj = nil) or (PredicateObj = nil) or (ObjectObj = nil) then
          continue;

        // 3. Process Nodes (already optimized with NewNode)
        SubjectNode := GetOrCreateNode(SubjectObj, AMergeStrategy);
        ObjectNode := GetOrCreateNode(ObjectObj, AMergeStrategy);

        if (SubjectNode <> nil) and (ObjectNode <> nil) then
        begin
          // Extract predicate data
          EdgeLabel := PredicateObj.GetValue<string>('edgeLabel', 'related_to');
          EdgeName := PredicateObj.GetValue<string>('name', '');
          PredicateProps := PredicateObj.GetValue<TJSONObject>('properties', nil);

          // 4. EDGE RECONCILIATION LOGIC
          ExistingEdge := FGraph.FindEdge(SubjectNode, ObjectNode, EdgeLabel);

          if ExistingEdge <> nil then
          begin
            // --- EXISTING EDGE ---
            NeedEmbeddingUpdate := False;

            // Merge properties
            if PredicateProps <> nil then
            begin
              MergeEdgeProperties(ExistingEdge, PredicateProps, AMergeStrategy);
              NeedEmbeddingUpdate := True; // properties changed
            end;

            // Update name if the strategy allows it
            if (not EdgeName.IsEmpty) and (AMergeStrategy = msOverwrite) then
            begin
              ExistingEdge.Name := EdgeName;
              NeedEmbeddingUpdate := True;
            end;

            // FIX: If there is an engine and the edge does NOT have a vector, regenerate it
            if (LEmbeddings <> nil) and (Length(ExistingEdge.Data) = 0) then
              NeedEmbeddingUpdate := True;

            // Regenerate embedding if necessary
            if NeedEmbeddingUpdate and (LEmbeddings <> nil) then
            begin
              TextToEmbed := SubjectNode.Name + ' ' + EdgeLabel + ' ' + ObjectNode.Name;
              ExistingEdge.Data := LEmbeddings.CreateEmbedding(TextToEmbed, '');
            end;

            // CRITICAL: If your Core does not synchronize automatically, force UPDATE
            // Uncomment if necessary:
            // if NeedEmbeddingUpdate then
            // FGraph.UpdateEdge(ExistingEdge);
          end
          else
          begin
            // --- NEW EDGE (Optimized) ---
            // 1. Create edge object in memory (without persisting)
            NewEdge := FGraph.NewEdge(SubjectNode, ObjectNode, TGuid.NewGuid.ToString, EdgeLabel, EdgeName);

            // 2. Apply properties in memory
            if PredicateProps <> nil then
              MergeEdgeProperties(NewEdge, PredicateProps, msOverwrite);

            // 3. Generate embedding if an engine is configured
            if LEmbeddings <> nil then
            begin
              TextToEmbed := SubjectNode.Name + ' ' + EdgeLabel + ' ' + ObjectNode.Name;
              NewEdge.Data := LEmbeddings.CreateEmbedding(TextToEmbed, '');
            end;

            // 4. NOW persist with all complete data (1 INSERT)
            FGraph.AddEdge(NewEdge);
          end;
        end;
      end;
    finally
      FGraph.EndUpdate;
    end;

    Result := I;
  finally
    JsonValue.Free;
  end;
end;

procedure TAiRagGraphBuilder.SetGraph(const Value: TAiRagGraph);
begin
  if FGraph <> Value then
  begin
    FGraph := Value;
    if FGraph <> nil then
      FGraph.FreeNotification(Self);
  end;
end;

end.
