unit uMakerAi.Agents.GraphBuilder;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections, System.Classes, System.Math,
  uMakerAi.Agents;

type
  // Structural error of the graph (M-02). The declaration lives in uMakerAi.Agents
  // (SaveToStream also uses it, M-06); this alias preserves compatibility.
  EAiGraphError = uMakerAi.Agents.EAiGraphError;

  TGraphBuilder = class
  private
  // IMPROVEMENT: Constants to avoid "Magic Strings" and typos.
    const
    // Main structure
    cJsonNodes = 'nodes';
    cJsonEdges = 'edges';
    cJsonProperties = 'properties';

    // Node properties
    cJsonNodeId = 'id';
    cJsonNodeLabel = 'label';
    cJsonNodePorts = 'ports';
    cJsonToolClassName = 'toolClassName';
    cJsonParameters = 'parameters';
    cJsonMetadataDescription = 'metadata.description'; // We use the dot to denote nesting

    // Port properties
    cJsonPortInternalId = 'internalId';
    cJsonPortId = 'idStr';
    cJsonPortCategory = 'category';
    cJsonPortCategoryAccessory = 'accessory';

    // Edge properties
    cJsonEdgeSourceNodeId = 'sourceNodeId';
    cJsonEdgeTargetNodeId = 'targetNodeId';
    cJsonEdgeSourceTerminal = 'sourceTerminal';
    cJsonEdgeDescription = 'description';

    // Engine properties
    cJsonEngine = 'engine';
    cJsonEngineJoinMode = 'joinMode';
    cJsonEngineLinkMode = 'linkMode';
    cJsonEngineLinkMaxCycles = 'linkMaxCycles';
    cJsonEngineLinkCondKey = 'linkConditionalKey';
    cJsonEngineLinkManualKey = 'linkManualTargetsKey';
    cJsonEngineLinkExprA = 'linkExpressionA';
    cJsonEngineLinkExprB = 'linkExpressionB';
    cJsonEngineLinkExprC = 'linkExpressionC';
    cJsonEngineLinkExprD = 'linkExpressionD';

    // Special ports
    cPortOutFailure = 'out_failure';

    cJsonMetadata = 'metadata'; // <-- New constant
    cJsonDescription = 'description'; // <-- New constant

  private
    FAgents: TAIAgents;
    FJsonGraph: TJSONObject;
    FNodeMap: TDictionary<string, TAIAgentsNode>;
    FNodeJsonMap: TDictionary<string, TJSONObject>;
    FStrictValidation: Boolean;

    procedure ParseNodes;
    procedure ParseEdges;
    procedure SetToolParameters(ATool: TAiToolBase; AParamsJson: TJSONObject);
    function FindPortJsonByTerminalId(ANodeJson: TJSONObject; const APortTerminalId: string): TJSONObject;
    function FindEngineObject(JsonObj: TJSONObject): TJSONObject;

  public
    constructor Create(AAgents: TAIAgents);
    destructor Destroy; override;

    procedure BuildFromJson(const AJsonString: string);

    // M-02: with True (default) the JSON's structural defects raise
    // EAiGraphError (edge to a non-existent node, undeclared port, excess
    // of outputs). With False the historical behavior is kept of
    // warning through the log and continuing (with silent loss of edges).
    property StrictValidation: Boolean read FStrictValidation write FStrictValidation default True;
  end;

implementation

uses
  System.Rtti, System.TypInfo,
  uMakerAi.Agents.EngineRegistry;

{ TGraphBuilder }

constructor TGraphBuilder.Create(AAgents: TAIAgents);
begin
  inherited Create;
  if not Assigned(AAgents) then
    raise Exception.Create('TGraphBuilder requires a valid TAIAgents instance.');
  FAgents := AAgents;
  FNodeMap := TDictionary<string, TAIAgentsNode>.Create;
  FNodeJsonMap := TDictionary<string, TJSONObject>.Create;
  FStrictValidation := True;
end;

destructor TGraphBuilder.Destroy;
begin
  FNodeMap.Free;
  FNodeJsonMap.Free;
  inherited;
end;

procedure TGraphBuilder.BuildFromJson(const AJsonString: string);
begin
  FJsonGraph := TJSONObject.ParseJSONValue(AJsonString) as TJSONObject;
  if not Assigned(FJsonGraph) then
    raise Exception.Create('Invalid JSON format for graph definition.');

  try
    FAgents.ClearGraph;
    FNodeMap.Clear;
    FNodeJsonMap.Clear;

    ParseNodes;
    ParseEdges;
    FAgents.Compile;

  finally
    FJsonGraph.Free;
    FJsonGraph := nil; // Good practice to avoid dangling pointers
  end;
end;

// IMPROVEMENT: The original function is kept, but a comment about its nature is added.
// This function performs a deep recursive search to find an object with the 'engine' key.
// It is robust if the location of the 'engine' object is not fixed.
// If the JSON structure were constant (e.g. 'properties.engine'),
// a direct lookup would be more efficient.
function TGraphBuilder.FindEngineObject(JsonObj: TJSONObject): TJSONObject;
var
  Pair: TJSONPair;
  Value: TJSONValue;
  I: Integer;
begin
  Result := nil;
  if JsonObj = nil then
    Exit;

  for Pair in JsonObj do
  begin
    if SameText(Pair.JsonString.Value, cJsonEngine) and (Pair.JsonValue is TJSONObject) then
      Exit(TJSONObject(Pair.JsonValue));

    Value := Pair.JsonValue;

    if Value is TJSONObject then
    begin
      Result := FindEngineObject(TJSONObject(Value));
      if Assigned(Result) then
        Exit;
    end
    else if Value is TJSONArray then
    begin
      for I := 0 to TJSONArray(Value).Count - 1 do
      begin
        if TJSONArray(Value).Items[I] is TJSONObject then
        begin
          Result := FindEngineObject(TJSONObject(TJSONArray(Value).Items[I]));
          if Assigned(Result) then
            Exit;
        end;
      end;
    end;
  end;
end;

procedure TGraphBuilder.ParseNodes;
var
  LNodesArray: TJSONArray;
  LNodeJson, LPropertiesJson, LParametersJson, LEngineJson, LMetadataJson: TJSONObject;
  LNode: TAIAgentsNode;
  LToolClassName, LJoinModeStr, LDescription, LNodeGuid, LLabel: string;
  LToolClass: TClass;
  LTool: TAiToolBase;
  LJoinModeOrdinal: Integer;
begin
  LNodesArray := FJsonGraph.GetValue<TJSONArray>(cJsonNodes);
  if not Assigned(LNodesArray) then
    raise Exception.CreateFmt('JSON graph must contain a "%s" array.', [cJsonNodes]);

  for var LJsonValue in LNodesArray do
  begin
    LNodeJson := LJsonValue as TJSONObject;
    LNodeGuid := LNodeJson.GetValue<string>(cJsonNodeId);
    LLabel := LNodeJson.GetValue<string>(cJsonNodeLabel, 'Node_' + Copy(LNodeGuid, 2, 8));

    LLabel := StringReplace(LLabel, ' ', '', [rfReplaceAll]); // Names cannot contain spaces

    // 1. Create the node instance
    LNode := TAIAgentsNode.Create(FAgents);

    // 2. Assign fundamental properties
    LNode.ID := LNodeGuid; // Assign the original GUID to the existing ID property
    LNode.Name := LLabel;
    LNode.Graph := FAgents;
    LNode.JoinMode := jmAny;
    LTool := nil; // Good practice to initialize the reference

    // 3. Process the JSON properties
    if LNodeJson.TryGetValue<TJSONObject>(cJsonProperties, LPropertiesJson) then
    begin
      // 3.1. Read the description (nested and safe)
      if LPropertiesJson.TryGetValue<TJSONObject>(cJsonMetadata, LMetadataJson) then
        LDescription := LMetadataJson.GetValue<string>(cJsonDescription, '')
      else
        LDescription := '';
      LNode.Description := LDescription;

      // 3.2. Find the 'engine' object to configure JoinMode
      LEngineJson := FindEngineObject(LPropertiesJson);
      if Assigned(LEngineJson) then
      begin
        LJoinModeStr := LEngineJson.GetValue<string>(cJsonEngineJoinMode, 'jmAny');
        LJoinModeOrdinal := GetEnumValue(TypeInfo(TJoinMode), LJoinModeStr);
        if LJoinModeOrdinal <> -1 then
          LNode.JoinMode := TJoinMode(LJoinModeOrdinal);
      end;

      // 3.3. Create and configure the associated tool (Tool)
      LToolClassName := LPropertiesJson.GetValue<string>(cJsonToolClassName,'');
      if not LToolClassName.IsEmpty then
      begin
        LToolClass := TEngineRegistry.Instance.FindToolClass(LToolClassName);
        if Assigned(LToolClass) then
        begin
          LTool := TAiToolBase(TComponentClass(LToolClass).Create(LNode));
          LNode.Tool := LTool;
          LTool.Description := LDescription; // Also assign the description to the tool

          // Assign parameters to the tool using RTTI
          if LPropertiesJson.TryGetValue<TJSONObject>(cJsonParameters, LParametersJson) then
            SetToolParameters(LTool, LParametersJson);
        end
        else
          raise Exception.CreateFmt('Tool class "%s" not found or not registered.', [LToolClassName]);
      end;

      // 3.4. Identify special nodes (Start/End)
      if SameText(LToolClassName, 'TStartTool') then
        FAgents.StartNode := LNode;
      if SameText(LToolClassName, 'TEndTool') then
        FAgents.EndNode := LNode;
    end;

    // 4. Register the node in the dictionaries for the 'ParseEdges' step
    FNodeMap.Add(LNodeGuid, LNode);
    FNodeJsonMap.Add(LNodeGuid, LNodeJson);
  end;
end;


procedure TGraphBuilder.ParseEdges;
var
  LEdgesArray: TJSONArray;
  LEdgeJson, LSourceNodeJson, LSourcePortJson, LPropertiesJson, LEngineJson: TJSONObject;
  LSourceNode, LTargetNode: TAIAgentsNode;
  LSourceNodeId, LTargetNodeId, LSourceTerminalId, LSourcePortId, LSourcePortCategory: string;
  LLink: TAIAgentsLink;
  LLinkModeStr: string;
  LLinkModeOrdinal: Integer;
begin
  LEdgesArray := FJsonGraph.GetValue<TJSONArray>(cJsonEdges);
  if not Assigned(LEdgesArray) then
    Exit;

  for var LJsonValue in LEdgesArray do
  begin
    LEdgeJson := LJsonValue as TJSONObject;
    LSourceNodeId := LEdgeJson.GetValue<string>(cJsonEdgeSourceNodeId);
    LTargetNodeId := LEdgeJson.GetValue<string>(cJsonEdgeTargetNodeId);
    LSourceTerminalId := LEdgeJson.GetValue<string>(cJsonEdgeSourceTerminal);

    if not(FNodeMap.TryGetValue(LSourceNodeId, LSourceNode) and FNodeMap.TryGetValue(LTargetNodeId, LTargetNode)) then
    begin
      if FStrictValidation then
        raise EAiGraphError.CreateFmt('Edge references a non-existent node (source "%s" -> target "%s").',
          [LSourceNodeId, LTargetNodeId]);
      Continue;
    end;

    if not FNodeJsonMap.TryGetValue(LSourceNodeId, LSourceNodeJson) then
      Continue;

    LSourcePortJson := FindPortJsonByTerminalId(LSourceNodeJson, LSourceTerminalId);
    if not Assigned(LSourcePortJson) then
    begin
      if FStrictValidation then
        raise EAiGraphError.CreateFmt('Source port "%s" is not declared on node "%s".',
          [LSourceTerminalId, LSourceNode.Name]);
      Continue;
    end;

    LSourcePortCategory := LSourcePortJson.GetValue<string>(cJsonPortCategory, 'tool');
    if SameText(LSourcePortCategory, cJsonPortCategoryAccessory) then
      Continue;

    // IMPROVEMENT: The Link creation logic is more explicit.
    // A single Link is created per source node the first time an outgoing edge is found.
    LLink := LSourceNode.Next;
    if not Assigned(LLink) then
    begin
      LLink := TAIAgentsLink.Create(FAgents);
      LLink.Graph := FAgents;
      LLink.Name := 'Link_From_' + LSourceNode.Name;
      LSourceNode.Next := LLink;

      // The Link properties are read from the SOURCE NODE's 'engine' object.
      LEngineJson := FindEngineObject(LSourceNodeJson);
      if Assigned(LEngineJson) then
      begin
        LLinkModeStr := LEngineJson.GetValue<string>(cJsonEngineLinkMode, 'lmFanout');
        LLinkModeOrdinal := GetEnumValue(TypeInfo(TLinkMode), LLinkModeStr);
        if LLinkModeOrdinal <> -1 then
          LLink.Mode := TLinkMode(LLinkModeOrdinal);

        LLink.MaxCycles := LEngineJson.GetValue<Integer>(cJsonEngineLinkMaxCycles, 1);
        LLink.ConditionalKey := LEngineJson.GetValue<string>(cJsonEngineLinkCondKey, 'next_route');
        LLink.ManualTargetsKey := LEngineJson.GetValue<string>(cJsonEngineLinkManualKey, 'next_targets');
        LLink.ExpressionA := LEngineJson.GetValue<string>(cJsonEngineLinkExprA, '');
        LLink.ExpressionB := LEngineJson.GetValue<string>(cJsonEngineLinkExprB, '');
        LLink.ExpressionC := LEngineJson.GetValue<string>(cJsonEngineLinkExprC, '');
        LLink.ExpressionD := LEngineJson.GetValue<string>(cJsonEngineLinkExprD, '');
      end;

      if LEdgeJson.TryGetValue<TJSONObject>(cJsonProperties, LPropertiesJson) then
      begin
        LLink.Description := LPropertiesJson.GetValue<string>(cJsonEdgeDescription, '');
      end;
    end;

    LSourcePortId := LSourcePortJson.GetValue<string>(cJsonPortId, LSourceTerminalId);

    // The out_failure port is the error branch in ALL modes (M-07):
    // it must be evaluated before the mode, or in lmConditional it would be registered
    // as a value condition "out_failure" and the node would be left without a failure output.
    if SameText(LSourcePortId, cPortOutFailure) then
    begin
      LLink.NextNo := LTargetNode;
    end
    else if LLink.Mode = lmConditional then
    begin
      LLink.AddConditionalTarget(LSourcePortId, LTargetNode);
    end
    else
    begin
        // IMPROVEMENT: Assignment logic to NextA/B/C/D simplified and less repetitive.
        var
          LNextSlots: array [0 .. 3] of PPointer;
        LNextSlots[0] := @LLink.NextA;
        LNextSlots[1] := @LLink.NextB;
        LNextSlots[2] := @LLink.NextC;
        LNextSlots[3] := @LLink.NextD;

        var
        LAssigned := False;
        for var I := 0 to High(LNextSlots) do
        begin
          if LNextSlots[I]^ = nil then
          begin
            LNextSlots[I]^ := LTargetNode;
            LAssigned := True;
            break;
          end;
        end;

        if not LAssigned then
        begin
          if FStrictValidation then
            raise EAiGraphError.CreateFmt('More than %d standard output ports connected from node "%s" (connection to "%s"). ' +
              'Use lmConditional/lmManual for N-way routing or set StrictValidation:=False to keep the legacy behavior of dropping the edge.',
              [Length(LNextSlots), LSourceNode.Name, LTargetNode.Name]);
          LSourceNode.Print(Format('Warning: More than %d standard output ports connected from node %s. Connection to %s ignored.', [Length(LNextSlots), LSourceNode.Name, LTargetNode.Name]));
        end;
    end;
  end;
end;

procedure TGraphBuilder.SetToolParameters(ATool: TAiToolBase; AParamsJson: TJSONObject);
begin
  // M-04: delegates to the single mapper. TAiToolParams.FromJSON is tolerant of
  // typed values or string values, excludes the reserved properties
  // (Name/Tag/ID/Description) and ignores those marked [TSecret].
  TAiToolParams.FromJSON(ATool, AParamsJson);
end;

function TGraphBuilder.FindPortJsonByTerminalId(ANodeJson: TJSONObject; const APortTerminalId: string): TJSONObject;
var
  LPortsArray: TJSONArray;
  LPortJson: TJSONObject;
begin
  Result := nil;
  if not Assigned(ANodeJson) then
    Exit;
  if not ANodeJson.TryGetValue<TJSONArray>(cJsonNodePorts, LPortsArray) then
    Exit;

  for var LJsonValue in LPortsArray do
  begin
    LPortJson := LJsonValue as TJSONObject;
    if SameText(LPortJson.GetValue<string>(cJsonPortInternalId), APortTerminalId) then
    begin
      Result := LPortJson;
      Exit;
    end;
  end;
end;

end.
