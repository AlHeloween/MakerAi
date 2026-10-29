unit uMakerAi.Agents.EngineRegistry;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.Variants, System.TypInfo,
  // "Engine" dependencies
  uMakerAi.Agents, uMakerAi.Agents.Attributes;

type
  // This is the data "contract" that the Designer will receive.
  // It is a simple record, does not contain classes or complex logic.
  TToolBlueprint = record
    ToolClassName: string;
    DisplayName: string;
    Description: string;
    Category: string;
    Schema: TJSONObject;
  end;

  // --- CHANGE 1: New structure to store the class AND its unit name. ---
  // This enriches the record so that the code generator knows which units to include.
  TToolInfo = record
    ToolClass: TClass;
    UnitName: string;
  end;

  // The Singleton that acts as our "black box".
  TEngineRegistry = class
  private
    class var
      FInstance: TEngineRegistry;
    // --- CHANGE 2: The dictionary now stores the TToolInfo record. ---
    FRegisteredTools: TDictionary<string, TToolInfo>;
    constructor Create;
  public
    destructor Destroy; override;
    class property Instance: TEngineRegistry read FInstance;

    // --- CHANGE 3: The registration method now requires the unit name. ---
    procedure RegisterTool(ToolClass: TClass; const AUnitName: string);

    function FindToolClass(const AToolClassName: string): TClass;

    // --- CHANGE 4: New method so that the generator can query the unit name. ---
    function GetUnitForToolClass(const AToolClassName: string): string;

    function GetToolBlueprints: TArray<TToolBlueprint>;
  end;

  // TAgentHandlerRegistry does not require changes.
  TAgentHandlerRegistry = class
  private
  class var
    FInstance: TAgentHandlerRegistry;
    FNodeHandlers: TDictionary<string, TAIAgentsNodeOnExecute>;
    FLinkHandlers: TDictionary<string, TAIAgentsLinkOnExecute>;
    constructor Create;
  public
    destructor Destroy; override;
    class property Instance: TAgentHandlerRegistry read FInstance;

    procedure RegisterNodeHandler(const AName: string; AHandler: TAIAgentsNodeOnExecute);
    procedure RegisterLinkHandler(const AName: string; AHandler: TAIAgentsLinkOnExecute);
    function FindNodeHandler(const AName: string): TAIAgentsNodeOnExecute;
    function FindLinkHandler(const AName: string): TAIAgentsLinkOnExecute;
  end;

implementation

uses System.Rtti;

// Internal helper to generate JSON schemas for parameters.
// Does not require changes.
type
  TSchemaGen_Internal = class
  private
    class function DelphiTypeToJSONType(APropType: TRttiType): string;
    class function DelphiTypeToJSONFormat(APropType: TRttiType): string;
  public
    class function GenerateSchemaFor(AClass: TClass): TJSONObject;
  end;

{ TEngineRegistry }

constructor TEngineRegistry.Create;
begin
  inherited;
  // --- CHANGE 5: The dictionary is created with the new value type (TToolInfo). ---
  FRegisteredTools := TDictionary<string, TToolInfo>.Create;
end;

destructor TEngineRegistry.Destroy;
begin
  FRegisteredTools.Free;
  inherited;
end;

function TEngineRegistry.FindToolClass(const AToolClassName: string): TClass;
var
  LToolInfo: TToolInfo;
begin
  // --- CHANGE 6: The search now extracts the TClass from the TToolInfo record. ---
  if FRegisteredTools.TryGetValue(AToolClassName, LToolInfo) then
    Result := LToolInfo.ToolClass
  else
    Result := nil;
end;

// --- CHANGE 7: Implementation of the new method to get the unit. ---
function TEngineRegistry.GetUnitForToolClass(const AToolClassName: string): string;
var
  LToolInfo: TToolInfo;
begin
  if FRegisteredTools.TryGetValue(AToolClassName, LToolInfo) then
    Result := LToolInfo.UnitName
  else
    Result := '';
end;

// --- CHANGE 8: Implementation of the modified registration method. ---
procedure TEngineRegistry.RegisterTool(ToolClass: TClass; const AUnitName: string);
var
  LToolInfo: TToolInfo;
begin
  if not ToolClass.InheritsFrom(TAiToolBase) then
    raise Exception.CreateFmt('Cannot register class "%s" because it does not inherit from TAiToolBase.', [ToolClass.ClassName]);

  // Fill the record with all necessary information.
  LToolInfo.ToolClass := ToolClass;
  LToolInfo.UnitName := AUnitName;

  FRegisteredTools.Add(ToolClass.ClassName, LToolInfo);
end;

function TEngineRegistry.GetToolBlueprints: TArray<TToolBlueprint>;
var
  LToolInfo: TToolInfo;   // The loop variable is now of type TToolInfo.
  ToolClass: TClass;      // Local variable to maintain clarity of existing code.
  LContext: TRttiContext;
  LRttiType: TRttiType;
  ClassToolAttr: TToolAttribute;
  i: Integer;
begin
  SetLength(Result, FRegisteredTools.Count);
  i := 0;
  LContext := TRttiContext.Create;
  try
    // --- CHANGE 9: The loop iterates over the TToolInfo values of the dictionary. ---
    for LToolInfo in FRegisteredTools.Values do
    begin
      // Extract the class from the record so that the rest of the code works without changes.
      ToolClass := LToolInfo.ToolClass;

      LRttiType := LContext.GetType(ToolClass);
      ClassToolAttr := nil;

      for var Attr in LRttiType.GetAttributes do
      begin
        if Attr is TToolAttribute then
        begin
          ClassToolAttr := Attr as TToolAttribute;
          Break;
        end;
      end;

      Result[i].ToolClassName := ToolClass.ClassName;

      if Assigned(ClassToolAttr) then
      begin
        Result[i].DisplayName := ClassToolAttr.Name;
        Result[i].Description := ClassToolAttr.Description;
        Result[i].Category := ClassToolAttr.Category;
      end
      else
      begin
        Result[i].DisplayName := ToolClass.ClassName.Substring(1);
        Result[i].Description := 'No description provided.';
        Result[i].Category := 'Uncategorized';
      end;

      Result[i].Schema := TSchemaGen_Internal.GenerateSchemaFor(ToolClass);

      Inc(i);
    end;
  finally
    LContext.Free;
  end;
end;

{ TSchemaGen_Internal }

// This class does not need any modifications.
class function TSchemaGen_Internal.GenerateSchemaFor(AClass: TClass): TJSONObject;
var
  LContext: TRttiContext;
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  ParamAttr: TToolParameterAttribute;
  LProperties, LPropSchema: TJSONObject;
  JsonType: string;
begin
  Result := TJSONObject.Create;
  LProperties := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('title', AClass.ClassName.Substring(1));
  Result.AddPair('properties', LProperties);

  LContext := TRttiContext.Create;
  try
    LRttiType := LContext.GetType(AClass);
    for LProp in LRttiType.GetProperties do
    begin
      ParamAttr := nil;
      for var Attr in LProp.GetAttributes do
        if Attr is TToolParameterAttribute then
        begin
          ParamAttr := Attr as TToolParameterAttribute;
          Break;
        end;

      if Assigned(ParamAttr) then
      begin
        LPropSchema := TJSONObject.Create;
        LPropSchema.AddPair('title', ParamAttr.DisplayName);
        LPropSchema.AddPair('description', ParamAttr.Hint);
        JsonType := DelphiTypeToJSONType(LProp.PropertyType);
        LPropSchema.AddPair('type', JsonType);

        var
        LFormat := DelphiTypeToJSONFormat(LProp.PropertyType);
        if not LFormat.IsEmpty then
          LPropSchema.AddPair('format', LFormat);

        if not ParamAttr.DefaultValue.IsEmpty then
        begin
          var
          PropTypeKind := LProp.PropertyType.TypeKind;
          if (PropTypeKind = tkInteger) or (PropTypeKind = tkInt64) then
            LPropSchema.AddPair('default', TJSONNumber.Create(StrToIntDef(ParamAttr.DefaultValue, 0)))
          else if PropTypeKind = tkFloat then
            LPropSchema.AddPair('default', TJSONNumber.Create(StrToFloatDef(ParamAttr.DefaultValue, 0.0)))
          else if PropTypeKind = tkEnumeration then
            if LProp.PropertyType.Handle = TypeInfo(Boolean) then
              LPropSchema.AddPair('default', TJSONBool.Create(SameText(ParamAttr.DefaultValue, 'True')))
            else
              LPropSchema.AddPair('default', TJSONString.Create(ParamAttr.DefaultValue))
          else
            LPropSchema.AddPair('default', TJSONString.Create(ParamAttr.DefaultValue));
        end;

        if (LProp.PropertyType.TypeKind = tkEnumeration) and (LProp.PropertyType.Handle <> TypeInfo(Boolean)) then
        begin
          var
          LEnumArray := TJSONArray.Create;
          var
          RttiEnum := LProp.PropertyType as TRttiEnumerationType;
          for var EnumName in RttiEnum.GetNames do
            LEnumArray.Add(EnumName);
          LPropSchema.AddPair('enum', LEnumArray);
        end;

        LProperties.AddPair(LProp.Name, LPropSchema);
      end;
    end;
  finally
    LContext.Free;
  end;
end;

class function TSchemaGen_Internal.DelphiTypeToJSONType(APropType: TRttiType): string;
begin
  if not Assigned(APropType) then
    Exit('string');
  case APropType.TypeKind of
    tkInteger, tkInt64:
      Result := 'integer';
    tkFloat:
      Result := 'number';
    tkEnumeration:
      if APropType.Handle = TypeInfo(Boolean) then
        Result := 'boolean'
      else
        Result := 'string';
    tkString, tkUString, tkChar, tkWChar, tkLString, tkWString:
      Result := 'string';
    tkClass:
      if APropType.Handle = TypeInfo(TDateTime) then
        Result := 'string'
      else if APropType.Handle = TypeInfo(TDate) then
        Result := 'string'
      else if APropType.Handle = TypeInfo(TTime) then
        Result := 'string'
      else
        Result := 'string';
  else
    Result := 'string';
  end;
end;

class function TSchemaGen_Internal.DelphiTypeToJSONFormat(APropType: TRttiType): string;
begin
  Result := '';
  if not Assigned(APropType) then
    Exit;
  if APropType.Handle = TypeInfo(TDateTime) then
    Result := 'date-time'
  else if APropType.Handle = TypeInfo(TDate) then
    Result := 'date'
  else if APropType.Handle = TypeInfo(TTime) then
    Result := 'time';
end;

{ TAgentHandlerRegistry }

// This class does not need any modifications.
constructor TAgentHandlerRegistry.Create;
begin
  inherited;
  FNodeHandlers := TDictionary<string, TAIAgentsNodeOnExecute>.Create;
  FLinkHandlers := TDictionary<string, TAIAgentsLinkOnExecute>.Create;
end;

destructor TAgentHandlerRegistry.Destroy;
begin
  FNodeHandlers.Free;
  FLinkHandlers.Free;
  inherited;
end;

function TAgentHandlerRegistry.FindNodeHandler(const AName: string): TAIAgentsNodeOnExecute;
begin
  FNodeHandlers.TryGetValue(AName, Result);
end;

function TAgentHandlerRegistry.FindLinkHandler(const AName: string): TAIAgentsLinkOnExecute;
begin
  FLinkHandlers.TryGetValue(AName, Result);
end;

procedure TAgentHandlerRegistry.RegisterNodeHandler(const AName: string; AHandler: TAIAgentsNodeOnExecute);
begin
  FNodeHandlers.AddOrSetValue(AName, AHandler);
end;

procedure TAgentHandlerRegistry.RegisterLinkHandler(const AName: string; AHandler: TAIAgentsLinkOnExecute);
begin
  FLinkHandlers.AddOrSetValue(AName, AHandler);
end;

initialization
  TEngineRegistry.FInstance := TEngineRegistry.Create;
  TAgentHandlerRegistry.FInstance := TAgentHandlerRegistry.Create;

finalization
  TEngineRegistry.FInstance.Free;
  TAgentHandlerRegistry.FInstance.Free;

end.
