unit uMakerAi.Agents.DmGenerator;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON, System.AnsiStrings, System.RegularExpressions, System.Math;

type
  // Internal structure to hold the information of each component to generate.
  TComponentInfo = record
  private
    FProperties: TStringList;
    procedure SetProperties(const Value: TStringList);
  public
    ComponentName: string;
    ComponentType: string;
    property Properties: TStringList read FProperties write SetProperties;
    class function New(const AName, AType: string): TComponentInfo; static;
  end;

  TDataModuleGenerator = class
  private
    FJsonGraph: TJSONObject;
    FNodeIdToNameMap: TDictionary<string, string>;
    FNodeJsonMap: TDictionary<string, TJSONObject>;
    FLinkIdToNameMap: TDictionary<string, string>;
    FComponentList: TList<TComponentInfo>;
    FAgentsComponentName: string;
    FCreateTools: Boolean;
    FBaseClassName: string;
    FUsedUnits: TStringList;
    FCalculatedWidth: Integer;
    FCalculatedHeight: Integer;

    // Parsing and internal model construction methods
    procedure ParseNodes;
    procedure ParseEdges;
    procedure GenerateToolProperties(const AToolClassName: string; AParamsJson: TJSONObject; var AToolInfo: TComponentInfo);
    procedure AddComponent(const AName, AType: string; out AComponentInfo: TComponentInfo);
    procedure Clear;
    procedure CalculateOptimalSize;

    // Utility methods (adapted from your TGraphBuilder)
    function SanitizeName(const ALabel: string): string;
    function FindPortJsonByTerminalId(ANodeJson: TJSONObject; const APortTerminalId: string): TJSONObject;
    function FindEngineObject(JsonObj: TJSONObject): TJSONObject;
    function MapPortToProperty(const APortId: string; Const ALinkInfo: TComponentInfo): string;
    function FindUnitName(const ATypeName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure GenerateFromJSON(const AJsonString: string; const AClassName: string; ACreateTools: Boolean = True);
    procedure SaveToFile(const ABaseFileName: string);
    function GetPasFileContent: string;
    function GetDfmFileContent: string;
  end;

implementation

uses
  System.Rtti, System.TypInfo,
  uMakerAi.Agents, uMakerAi.Agents.EngineRegistry;

{ TDataModuleGenerator }

constructor TDataModuleGenerator.Create;
begin
  inherited;
  FNodeIdToNameMap := TDictionary<string, string>.Create;
  FNodeJsonMap := TDictionary<string, TJSONObject>.Create;
  FLinkIdToNameMap := TDictionary<string, string>.Create;
  FComponentList := TList<TComponentInfo>.Create;
  FUsedUnits := TStringList.Create;
  FUsedUnits.Sorted := True;
  FUsedUnits.Duplicates := dupIgnore;
  FCalculatedWidth := 640;
  FCalculatedHeight := 480;
end;

destructor TDataModuleGenerator.Destroy;
begin
  Clear;
  FNodeIdToNameMap.Free;
  FNodeJsonMap.Free;
  FLinkIdToNameMap.Free;
  FComponentList.Free;
  FUsedUnits.Free;
  inherited;
end;

procedure TDataModuleGenerator.CalculateOptimalSize;
const
  // Assume a maximum size for any component (node, link, tool)
  // for the calculation. It is better to have a little extra space.
  ComponentMaxWidth = 100;
  ComponentMaxHeight = 150; // Tools can be taller
  Margin = 50; // Extra space around the last component

var
  maxX, maxY: Integer;
  LLeft, LTop: Integer;
begin
  maxX := 0;
  maxY := 0;

  if FComponentList.Count = 0 then
    Exit; // No components, use the default values

  for var CompInfo in FComponentList do
  begin
    // We read the Left and Top properties, converting them to Integer
    // Use StrToIntDef to avoid errors if the property does not exist (returns 0)
    LLeft := StrToIntDef(CompInfo.Properties.Values['Left'], 0);
    LTop := StrToIntDef(CompInfo.Properties.Values['Top'], 0);

    // We update the maximum coordinates found so far
    if LLeft > maxX then
      maxX := LLeft;

    if LTop > maxY then
      maxY := LTop;
  end;

  // We calculate the final size by adding the component size and a margin
  FCalculatedWidth := maxX + ComponentMaxWidth + Margin;
  FCalculatedHeight := maxY + ComponentMaxHeight + Margin;

  // Ensure the size is not less than a reasonable minimum
  FCalculatedWidth := Max(FCalculatedWidth, 640);
  FCalculatedHeight := Max(FCalculatedHeight, 480);
end;

procedure TDataModuleGenerator.Clear;
begin
  for var i := 0 to FComponentList.Count - 1 do
    FComponentList[i].Properties.Free;
  FComponentList.Clear;

  FNodeIdToNameMap.Clear;
  FNodeJsonMap.Clear;
  FLinkIdToNameMap.Clear;
  FUsedUnits.Clear;
  FJsonGraph.Free;
  FJsonGraph := nil;
  FCalculatedWidth := 640;
  FCalculatedHeight := 480;
end;

procedure TDataModuleGenerator.GenerateFromJSON(const AJsonString, AClassName: string; ACreateTools: Boolean);
begin
  if Assigned(FJsonGraph) then
    Clear;

  FJsonGraph := TJSONObject.ParseJSONValue(AJsonString) as TJSONObject;
  if not Assigned(FJsonGraph) then
    raise Exception.Create('Invalid JSON format for graph definition.');

  try
    FBaseClassName := AClassName;
    FCreateTools := ACreateTools;

    ParseNodes;
    ParseEdges;
    CalculateOptimalSize;
  except
    // In case of error, clean up to avoid leaving an inconsistent state.
    Clear;
    raise;
  end;
end;

procedure TDataModuleGenerator.AddComponent(const AName, AType: string; out AComponentInfo: TComponentInfo);
begin
  AComponentInfo := TComponentInfo.New(AName, AType);
  FComponentList.Add(AComponentInfo);
  // Add the unit of the component type to the 'uses' list
  var
  LUnitName := FindUnitName(AType);
  if not LUnitName.IsEmpty then
    FUsedUnits.Add(LUnitName);
end;

procedure TDataModuleGenerator.ParseNodes;
var
  LNodesArray, LPortsArray: TJSONArray; // Added LPortsArray
  LNodeJson, LPropertiesJson, LParametersJson, LEngineJson, LPositionJson, LPortJson, LPortEngineJson: TJSONObject; // Added LPortJson and LPortEngineJson
  LNodeInfo, LLinkInfo, LToolInfo, LAgentsInfo: TComponentInfo;
  LToolClassName, LJoinModeStr, LDescription, LNodeGuid, LLabel, LNodeName, LLinkName: string;
  LJoinModeOrdinal, i: Integer;
  minX, minY: Double;
  offsetX, offsetY: Double;
const
  Margin = 40;
begin
  LNodesArray := FJsonGraph.GetValue<TJSONArray>('nodes');
  if not Assigned(LNodesArray) then
    raise Exception.Create('JSON graph must contain a "nodes" array.');

  // --- STEP 1: Find the minimum coordinates for normalization ---
  minX := MaxSingle;
  minY := MaxSingle;
  for var LJsonValue in LNodesArray do
  begin
    LNodeJson := LJsonValue as TJSONObject;
    if LNodeJson.TryGetValue<TJSONObject>('position', LPositionJson) then
    begin
      minX := Min(minX, LPositionJson.GetValue<Double>('x'));
      minY := Min(minY, LPositionJson.GetValue<Double>('y'));
    end;
  end;

  offsetX := ifthen(minX < 0, -minX, 0);
  offsetY := ifthen(minY < 0, -minY, 0);

  // --- STEP 2: Generate components ---
  FAgentsComponentName := 'AIAgents1';
  AddComponent(FAgentsComponentName, 'TAIAgents', LAgentsInfo);
  LAgentsInfo.Properties.Values['Left'] := Margin.ToString;
  LAgentsInfo.Properties.Values['Top'] := Margin.ToString;

  for var LJsonValue in LNodesArray do
  begin
    LNodeJson := LJsonValue as TJSONObject;
    LNodeGuid := LNodeJson.GetValue<string>('id');
    LLabel := LNodeJson.GetValue<string>('label', 'Node_' + Copy(LNodeGuid, 2, 8));
    LNodeName := SanitizeName(LLabel);
    LLinkName := 'Link_From_' + LNodeName;

    AddComponent(LNodeName, 'TAIAgentsNode', LNodeInfo);
    AddComponent(LLinkName, 'TAIAgentsLink', LLinkInfo);

    LNodeInfo.Properties.Values['Next'] := LLinkName;
    LNodeInfo.Properties.Values['ID'] := QuotedStr(LNodeGuid);
    LNodeInfo.Properties.Values['Graph'] := FAgentsComponentName;
    LLinkInfo.Properties.Values['Graph'] := FAgentsComponentName;

    var
      nodeX, nodeY, linkTop, toolTop: Integer;
    if LNodeJson.TryGetValue<TJSONObject>('position', LPositionJson) then
    begin
      nodeX := Round(LPositionJson.GetValue<Double>('x') + offsetX) + Margin;
      nodeY := Round(LPositionJson.GetValue<Double>('y') + offsetY) + Margin;
    end
    else
    begin
      nodeX := Margin;
      nodeY := Margin + (FComponentList.Count * 120);
    end;
    linkTop := nodeY + 60;
    toolTop := nodeY + 120;

    LNodeInfo.Properties.Values['Left'] := nodeX.ToString;
    LNodeInfo.Properties.Values['Top'] := nodeY.ToString;
    LLinkInfo.Properties.Values['Left'] := nodeX.ToString;
    LLinkInfo.Properties.Values['Top'] := linkTop.ToString;

    FNodeIdToNameMap.Add(LNodeGuid, LNodeName);
    FNodeJsonMap.Add(LNodeGuid, LNodeJson);
    FLinkIdToNameMap.Add(LNodeGuid, LLinkName);

    LPropertiesJson := LNodeJson.GetValue<TJSONObject>('properties');
    if Assigned(LPropertiesJson) then
    begin
      LDescription := LPropertiesJson.GetValue<string>('metadata.description', '');
      if not LDescription.IsEmpty then
        LNodeInfo.Properties.Values['Description'] := QuotedStr(LDescription);

      // Original search for JoinMode (kept for backward compatibility)
      LEngineJson := FindEngineObject(LPropertiesJson);
      if Assigned(LEngineJson) then
      begin
        LJoinModeStr := LEngineJson.GetValue<string>('joinMode', 'jmAny');
        LJoinModeOrdinal := GetEnumValue(TypeInfo(TJoinMode), LJoinModeStr);
        if (LJoinModeOrdinal <> -1) and (LJoinModeStr <> 'jmAny') then
          LNodeInfo.Properties.Values['JoinMode'] := LJoinModeStr;
      end;

      // --- START OF MODIFICATION ---
      // New search for JoinMode nested inside the 'ports' array.
      // This will overwrite the previous value if a more specific definition is found.
      if LNodeJson.TryGetValue<TJSONArray>('ports', LPortsArray) then
      begin
        for var LPortValue in LPortsArray do
        begin
          LPortJson := LPortValue as TJSONObject;
          // We are only interested if the port is an input and has an 'engine' object
          if (LPortJson.GetValue<string>('direction') = 'input') and LPortJson.TryGetValue<TJSONObject>('engine', LPortEngineJson) then
          begin
            // If we find a 'joinMode' here, we use it and exit the loop
            if LPortEngineJson.TryGetValue<string>('joinMode', LJoinModeStr) then
            begin
              LJoinModeOrdinal := GetEnumValue(TypeInfo(TJoinMode), LJoinModeStr);
              if (LJoinModeOrdinal <> -1) and (LJoinModeStr <> 'jmAny') then
                LNodeInfo.Properties.Values['JoinMode'] := LJoinModeStr;
              Break; // Exit the port loop, we have already found the joinMode.
            end;
          end;
        end;
      end;

      LToolClassName := LPropertiesJson.GetValue<string>('toolClassName');
      if FCreateTools and (not LToolClassName.IsEmpty) then
      begin
        var
        LToolClass := TEngineRegistry.Instance.FindToolClass(LToolClassName);
        if Assigned(LToolClass) then
        begin
          var
          LToolName := SanitizeName(Copy(LToolClassName, 2, MaxInt) + '_' + LNodeName);
          AddComponent(LToolName, LToolClassName, LToolInfo);
          LToolInfo.Properties.Values['ID'] := QuotedStr(LNodeGuid);
          LToolInfo.Properties.Values['Left'] := nodeX.ToString;
          LToolInfo.Properties.Values['Top'] := toolTop.ToString;
          LNodeInfo.Properties.Values['Tool'] := LToolName;

          if LPropertiesJson.TryGetValue<TJSONObject>('parameters', LParametersJson) then
            GenerateToolProperties(LToolClassName, LParametersJson, LToolInfo);
        end;
      end;

      for i := 0 to FComponentList.Count - 1 do
        if FComponentList[i].ComponentName = FAgentsComponentName then
        begin
          if SameText(LToolClassName, 'TStartTool') then
            FComponentList[i].Properties.Values['StartNode'] := LNodeName;
          if SameText(LToolClassName, 'TEndTool') then
            FComponentList[i].Properties.Values['EndNode'] := LNodeName;
        end;
    end;
  end;
end;

procedure TDataModuleGenerator.ParseEdges;
var
  LEdgesArray: TJSONArray;
  LEdgeGroup: TDictionary<string, TList<TJSONObject>>;
  i: Integer;
  LEdgeList: TList<TJSONObject>;
  LLinkName, LTargetNodeName, LExpr: string;
begin
  LEdgesArray := FJsonGraph.GetValue<TJSONArray>('edges');
  if not Assigned(LEdgesArray) then
    Exit;

  LEdgeGroup := TDictionary < string, TList < TJSONObject >>.Create;
  try
    // --- STEP 1: GROUPING PHASE ---
    // We iterate through all edges in the JSON and group them into a dictionary
    // using the source node ID as the key.
    for var LJsonValue in LEdgesArray do
    begin
      var
      LEdgeJson := LJsonValue as TJSONObject;
      var
      LSourceNodeId := LEdgeJson.GetValue<string>('sourceNodeId');
      if not LEdgeGroup.TryGetValue(LSourceNodeId, LEdgeList) then
      begin
        LEdgeList := TList<TJSONObject>.Create;
        LEdgeGroup.Add(LSourceNodeId, LEdgeList);
      end;
      LEdgeList.Add(LEdgeJson);
    end;

    // --- STEP 2: GROUP PROCESSING PHASE ---
    // We iterate over each group of edges. Each group corresponds to a single TAIAgentsLink.
    for var LPair in LEdgeGroup do
    begin
      var
      LSourceNodeId := LPair.Key;
      LEdgeList := LPair.Value;
      if LEdgeList.Count = 0 then
        Continue;

      // Find the Link we already created in ParseNodes
      if not FLinkIdToNameMap.TryGetValue(LSourceNodeId, LLinkName) then
        Continue; // Link not found for this node, something weird happened.

      var
      LLinkInfoIndex := -1;
      for i := 0 to FComponentList.Count - 1 do
      begin
        if FComponentList[i].ComponentName = LLinkName then
        begin
          LLinkInfoIndex := i;
          Break;
        end;
      end;
      if LLinkInfoIndex = -1 then
        Continue; // Link entry not found in the list.

      var
      SharedPropertiesSet := False;
      var
      LSourceNodeJson := FNodeJsonMap[LSourceNodeId];

      // --- STEP 3: PROCESS EACH EDGE WITHIN THE GROUP ---
      // We iterate over each edge to configure the shared Link.
      for var LEdgeJson in LEdgeList do
      begin
        var
        LSourceTerminalId := LEdgeJson.GetValue<string>('sourceTerminal');
        var
        LSourcePortJson := FindPortJsonByTerminalId(LSourceNodeJson, LSourceTerminalId);
        if not Assigned(LSourcePortJson) then
          Continue;

        // Try to get the 'engine' object from the port
        Var
          LEngineJson: TJSONObject;
        if LSourcePortJson.TryGetValue<TJSONObject>('engine', LEngineJson) then
        begin
          // A) Process Shared Properties (only the first time they are found)
          if not SharedPropertiesSet then
          begin
            var
            LLinkModeStr := LEngineJson.GetValue<string>('linkMode');
            if not LLinkModeStr.IsEmpty then
            begin
              var
              LLinkMode := TLinkMode(GetEnumValue(TypeInfo(TLinkMode), LLinkModeStr));
              if LLinkMode <> lmFanout then
                FComponentList[LLinkInfoIndex].Properties.Values['Mode'] := LLinkModeStr;

              Var
                LValue: String;
              case LLinkMode of
                lmConditional:
                  Begin
                    if LEngineJson.TryGetValue<string>('linkConditionalKey', LValue) then
                      FComponentList[LLinkInfoIndex].Properties.Values['ConditionalKey'] := LValue;
                  End;
                lmManual:
                  Begin
                    if LEngineJson.TryGetValue<string>('linkManualTargetsKey', LValue) then
                      FComponentList[LLinkInfoIndex].Properties.Values['ManualTargetsKey'] := LValue;
                  End;
              end;
            end;

            var
            LMaxCycles := LEngineJson.GetValue<Integer>('linkMaxCycles', -1);
            if LMaxCycles <> -1 then // Use -1 to detect if the property exists
              if LMaxCycles <> 1 then // Only add if not the default value
                FComponentList[LLinkInfoIndex].Properties.Values['MaxCycles'] := LMaxCycles.ToString;

            SharedPropertiesSet := True;
          end;

          // B) Process Port-Specific Properties (always processed)
          if LEngineJson.TryGetValue<string>('linkExpressionA', LExpr) then
            FComponentList[LLinkInfoIndex].Properties.Values['ExpressionA'] := LExpr;
          if LEngineJson.TryGetValue<string>('linkExpressionB', LExpr) then
            FComponentList[LLinkInfoIndex].Properties.Values['ExpressionB'] := LExpr;
          if LEngineJson.TryGetValue<string>('linkExpressionC', LExpr) then
            FComponentList[LLinkInfoIndex].Properties.Values['ExpressionC'] := LExpr;
          if LEngineJson.TryGetValue<string>('linkExpressionD', LExpr) then
            FComponentList[LLinkInfoIndex].Properties.Values['ExpressionD'] := LExpr;
        end;

        // C) Assign the destination (Target) of the edge
        if FNodeIdToNameMap.TryGetValue(LEdgeJson.GetValue<string>('targetNodeId'), LTargetNodeName) then
        begin
          var
          LSourcePortId := LSourcePortJson.GetValue<string>('idStr', LSourceTerminalId);
          var
          LTargetPropName := MapPortToProperty(LSourcePortId, FComponentList[LLinkInfoIndex]);
          FComponentList[LLinkInfoIndex].Properties.Values[LTargetPropName] := LTargetNodeName;
        end;
      end;
    end;
  finally
    // Free the memory of the dictionary and all the lists it contains.
    for var LPair in LEdgeGroup do
      LPair.Value.Free;
    LEdgeGroup.Free;
  end;
end;

procedure TDataModuleGenerator.GenerateToolProperties(const AToolClassName: string; AParamsJson: TJSONObject; var AToolInfo: TComponentInfo);
var
  LRttiContext: TRttiContext;
  LRttiType: TRttiType;
  LRttiProp: TRttiProperty;
  LParamPair: TJSONPair;
  LPropValueStr: string;
begin
  var
  LToolClass := TEngineRegistry.Instance.FindToolClass(AToolClassName);
  if not Assigned(LToolClass) then
    Exit;

  LRttiContext := TRttiContext.Create;
  try
    LRttiType := LRttiContext.GetType(LToolClass);
    for LParamPair in AParamsJson do
    begin
      LRttiProp := LRttiType.GetProperty(LParamPair.JsonString.Value);
      if Assigned(LRttiProp) and LRttiProp.IsWritable then
      begin
        LPropValueStr := '';
        var
        LParamValue := LParamPair.JsonValue;

        case LRttiProp.PropertyType.TypeKind of
          tkString, tkUString:
            LPropValueStr := QuotedStr(LParamValue.Value);
          tkInteger, tkInt64:
            LPropValueStr := LParamValue.Value;
          tkFloat:
            LPropValueStr := LParamValue.Value;
          tkEnumeration:
            if LRttiProp.PropertyType.Handle = TypeInfo(Boolean) then
              LPropValueStr := LParamValue.Value
            else
              LPropValueStr := LParamValue.Value; // Assumes the enum name already comes in the JSON
        end;

        if not LPropValueStr.IsEmpty then
          AToolInfo.Properties.Add(LRttiProp.Name + ' = ' + LPropValueStr);
      end;
    end;
  finally
    LRttiContext.Free;
  end;
end;

function TDataModuleGenerator.FindEngineObject(JsonObj: TJSONObject): TJSONObject;
begin
  // This function is identical to the one in your TGraphBuilder, can be copied and pasted here.
  // ... full implementation ...
  Result := nil;
  if JsonObj = nil then
    Exit;
  if JsonObj.TryGetValue<TJSONObject>('properties.metadata.engine', Result) then
    Exit;
  if JsonObj.TryGetValue<TJSONObject>('metadata.engine', Result) then
    Exit;
  if JsonObj.TryGetValue<TJSONObject>('engine', Result) then
    Exit;
end;

function TDataModuleGenerator.FindPortJsonByTerminalId(ANodeJson: TJSONObject; const APortTerminalId: string): TJSONObject;
begin
  // This function is identical to the one in your TGraphBuilder, can be copied and pasted here.
  // ... full implementation ...
  Result := nil;
  var
    LPortsArray: TJSONArray;
  if not Assigned(ANodeJson) then
    Exit;
  if not ANodeJson.TryGetValue<TJSONArray>('ports', LPortsArray) then
    Exit;

  for var LJsonValue in LPortsArray do
  begin
    var
    LPortJson := LJsonValue as TJSONObject;
    if SameText(LPortJson.GetValue<string>('internalId'), APortTerminalId) then
    begin
      Result := LPortJson;
      Exit;
    end;
  end;
end;

function TDataModuleGenerator.FindUnitName(const ATypeName: string): string;
{ var
  LContext: TRttiContext;
  LType: TRttiType;
  LPackage: TPackage;
  I: Integer;
}
begin
  { Result := '';
    LContext := TRttiContext.Create;
    try
    // 1. Look up the RTTI type by its class name
    LType := LContext.FindType(ATypeName);

    if Assigned(LType) then
    begin
    // 2. Iterate through all packages loaded at design time
    for LPackage in TPackage.Packages do
    begin
    // 3. Check if the type is contained in the current package
    if LPackage.ContainsType(LType) then
    begin
    // 4. If found, iterate over the units of that package
    for I := 0 to LPackage.UnitCount - 1 do
    begin
    if LPackage.UnitNames[I].Contains(LType.UnitName) then
    begin
    Result := LType.UnitName;
    Exit; // Found the unit, exit.
    end;
    end;
    end;
    end;
    end;
    finally
    LContext.Free;
    end;

    // Fallback: If not found in any package (e.g., System or SysUtils classes), the unit name might be part of the fully qualified type name.
    if Result.IsEmpty and Assigned(LType) and (LType.QualifiedName.Contains('.')) then
    begin
    Result := LType.UnitName;
    end;
  }
end;

function TDataModuleGenerator.GetDfmFileContent: string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    // CORRECTED:
    SB.Append(Format('object %s: T%s', [FBaseClassName, FBaseClassName]));
    SB.AppendLine;
    SB.AppendLine(Format('  Height = %d', [FCalculatedHeight]));
    SB.AppendLine(Format('  Width = %d', [FCalculatedWidth]));

    for var CompInfo in FComponentList do
    begin
      // CORRECTED:
      SB.Append(Format('  object %s: %s', [CompInfo.ComponentName, CompInfo.ComponentType]));
      SB.AppendLine;
      for var Prop in CompInfo.Properties do
        SB.AppendLine('    ' + Prop);
      SB.AppendLine('  end');
    end;

    SB.AppendLine('end');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TDataModuleGenerator.GetPasFileContent: string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    // CORRECTED:
    SB.Append(Format('unit %s;', [FBaseClassName]));
    SB.AppendLine;
    SB.AppendLine;

    SB.AppendLine('interface');
    SB.AppendLine;

    FUsedUnits.Add('System.SysUtils');
    FUsedUnits.Add('System.Classes');
    FUsedUnits.Add('uMakerAi.Agents');
    // Make sure this unit exists or adapt it
    // FUsedUnits.Add('uMakerAi.Agents.Tools');

    SB.AppendLine('uses');
    SB.Append('  ').Append(FUsedUnits.CommaText);
    SB.AppendLine(';').AppendLine;

    SB.AppendLine('type');
    SB.Append(Format('  T%s = class(TDataModule)', [FBaseClassName]));
    SB.AppendLine;
    for var CompInfo in FComponentList do
    begin
      // CORRECTED:
      SB.Append(Format('    %s: %s;', [CompInfo.ComponentName, CompInfo.ComponentType]));
      SB.AppendLine;
    end;
    SB.AppendLine('  private');
    SB.AppendLine('    { Private declarations }');
    SB.AppendLine('  public');
    SB.AppendLine('    { Public declarations }');
    SB.AppendLine('  end;');
    SB.AppendLine;

    SB.AppendLine('var');
    // CORRECTED:
    SB.Append(Format('  Dm%s: T%s;', [FBaseClassName, FBaseClassName]));
    SB.AppendLine;
    SB.AppendLine;

    SB.AppendLine('implementation');
    SB.AppendLine;
    SB.AppendLine('{%CLASSGROUP FMX.Controls.TControl}'); // or Vcl.Controls.TControl
    SB.AppendLine;
    // CORRECTED:
    SB.Append(Format('{$R *.dfm}', [])); // No format needed, but leaving it here for consistency
    SB.AppendLine;
    SB.AppendLine;

    SB.AppendLine('end.');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TDataModuleGenerator.MapPortToProperty(const APortId: string; Const ALinkInfo: TComponentInfo): string;
var
  NextProps: TArray<string>;
  i: Integer;
begin
  NextProps := ['NextA', 'NextB', 'NextC', 'NextD'];

  if SameText(APortId, 'out_failure') then
    Result := 'NextNo'
  else
  begin
    // Find the first 'NextX' that is not used in this Link.
    for i := Low(NextProps) to High(NextProps) do
    begin

      if ALinkInfo.Properties.IndexOfName(NextProps[i]) = -1 then
      begin
        Result := NextProps[i];
        Exit;
      end;
    end;
    // If all are used, return the first one as fallback (may cause overwriting)
    Result := 'NextA';
  end;
end;

procedure TDataModuleGenerator.SaveToFile(const ABaseFileName: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := GetPasFileContent;
    SL.SaveToFile(ABaseFileName + '.pas');

    SL.Text := GetDfmFileContent;
    SL.SaveToFile(ABaseFileName + '.dfm'); // or .fmx
  finally
    SL.Free;
  end;
end;

function TDataModuleGenerator.SanitizeName(const ALabel: string): string;
begin
  Result := ALabel;
  // Remove spaces and invalid characters.
  Result := TRegEx.Replace(Result, '[^a-zA-Z0-9_]', '');
  // If empty after cleaning, generate a default name.
  if Result.IsEmpty then
    Result := 'Component' + TGuid.NewGuid.ToString.Substring(1, 8);
  // Ensure it does not start with a number.
  if (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

{ TComponentInfo }

class function TComponentInfo.New(const AName, AType: string): TComponentInfo;
begin
  Result.ComponentName := AName;
  Result.ComponentType := AType;
  Result.FProperties := TStringList.Create;
  // TStringList used for properties is case-insensitive by default, which is good for .dfm
  Result.FProperties.CaseSensitive := False;
end;

procedure TComponentInfo.SetProperties(const Value: TStringList);
begin
  FProperties.Assign(Value);
end;

end.
