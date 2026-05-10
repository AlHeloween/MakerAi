// MIT License
// MakerAI - Agent System v3.4
// MCP → IAiTool adapter: exposes each tool from an MCP server
// as an interchangeable IAiTool within TAiToolRegistry.
//
// Author: Gustavo Enríquez
// GitHub: https://github.com/gustavoeenriquez/MakerAi

unit uMakerAi.Agents.Tools.MCP;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  uMakerAi.Agents.IAiTool,
  uMakerAi.MCPClient.Core;

type

  { TAiMCPTool ------------------------------------------------------------------
    Wraps ONE specific tool from an MCP server as IAiTool.
    TAiMCPToolFactory creates one instance for each tool listed on the
    server.

    Memory contract:
      - FClient is NOT owned by this class (owner is external code).
      - FSchema is owned by this class and freed in the destructor.
      - Execute → the caller is responsible for freeing the returned TJSONObject.
  }
  TAiMCPTool = class(TInterfacedObject, IAiTool)
  private
    FClient      : TMCPClientCustom;
    FToolName    : String;
    FDescription : String;
    FSchema      : TJSONObject;   // server inputSchema; owned by this class
  public
    constructor Create(AClient: TMCPClientCustom;
                       const AToolName, ADescription: String;
                       AInputSchema: TJSONObject);  // cloned internally
    destructor Destroy; override;

    // IAiTool
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    function GetSchema: TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable: Boolean;
  end;

  { TAiMCPToolFactory -----------------------------------------------------------
    Initializes a TMCPClientCustom and creates a TAiMCPTool for each tool
    that the server declares in its tools/list response.

    Usage:
      var Tools: TArray<IAiTool>;
      Tools := TAiMCPToolFactory.CreateFromClient(MyMCPClient);
      // Add to registry:
      for var T in Tools do
        Registry.Register(T);

    Notes:
      - If the client is not initialized, calls Initialize() internally.
      - If Initialize fails returns an empty array (does not raise exception).
      - The caller is responsible for AClient lifetime.
  }
  TAiMCPToolFactory = class
  public
    class function CreateFromClient(AClient: TMCPClientCustom): TArray<IAiTool>;
  end;

implementation

{ TAiMCPTool }

constructor TAiMCPTool.Create(AClient: TMCPClientCustom;
  const AToolName, ADescription: String; AInputSchema: TJSONObject);
begin
  inherited Create;
  FClient      := AClient;
  FToolName    := AToolName;
  FDescription := ADescription;
  // Clone the schema to avoid depending on the temporary JSON object from ListTools
  if Assigned(AInputSchema) then
    FSchema := TJSONObject(AInputSchema.Clone)
  else
  begin
    FSchema := TJSONObject.Create;
    FSchema.AddPair('type', 'object');
    FSchema.AddPair('properties', TJSONObject.Create);
  end;
end;

destructor TAiMCPTool.Destroy;
begin
  FSchema.Free;
  inherited;
end;

function TAiMCPTool.GetName: String;
begin
  Result := FToolName;
end;

function TAiMCPTool.GetDescription: String;
begin
  Result := FDescription;
end;

function TAiMCPTool.GetCategory: String;
begin
  Result := 'MCP';
end;

function TAiMCPTool.GetSchema: TJSONObject;
begin
  // NO liberar — propiedad de esta clase
  Result := FSchema;
end;

function TAiMCPTool.Execute(const AArgs: TJSONObject): TJSONObject;
var
  RawResult : TJSONObject;
begin
  Result := nil;
  if not Assigned(FClient) then Exit;
  if not FClient.Available then Exit;

  // CallTool returns a TJSONObject; this class returns it directly.
  // The caller (TAiToolRegistry / agent node) is responsible for freeing it.
  RawResult := FClient.CallTool(FToolName, AArgs, nil);
  if not Assigned(RawResult) then Exit;

  // The MCP result has the form:
  //   { "content": [ { "type":"text", "text":"..." } ], "isError": false }
  // We pass it as-is — the agent knows how to interpret it.
  Result := RawResult;
end;

function TAiMCPTool.IsAvailable: Boolean;
begin
  Result := Assigned(FClient) and FClient.Available and FClient.Enabled;
end;

{ TAiMCPToolFactory }

class function TAiMCPToolFactory.CreateFromClient(
  AClient: TMCPClientCustom): TArray<IAiTool>;
var
  ListResp  : TJSONObject;
  ToolsArr  : TJSONArray;
  ToolEntry : TJSONValue;
  ToolObj   : TJSONObject;
  ToolName  : String;
  ToolDesc  : String;
  InputSch  : TJSONObject;
  ResultList: TList<IAiTool>;
  ResultObj : TJSONObject;
begin
  Result := [];
  if not Assigned(AClient) then Exit;

  // Initialize if not yet done
  if not AClient.Initialized then
  begin
    if not AClient.Initialize then
      Exit;
  end;

  if not AClient.Available then Exit;

  ResultList := TList<IAiTool>.Create;
  try
    ListResp := AClient.ListTools;
    if not Assigned(ListResp) then Exit;
    try
      // Expected structure: { "result": { "tools": [...] } }
      // Some transports omit the "result" wrapper and return { "tools": [...] }
      ToolsArr  := nil;
      ResultObj := nil;
      if ListResp.TryGetValue<TJSONObject>('result', ResultObj) then
        ResultObj.TryGetValue<TJSONArray>('tools', ToolsArr)
      else
        ListResp.TryGetValue<TJSONArray>('tools', ToolsArr);

      if not Assigned(ToolsArr) then Exit;

      for ToolEntry in ToolsArr do
      begin
        if not (ToolEntry is TJSONObject) then Continue;
        ToolObj := TJSONObject(ToolEntry);

        if not ToolObj.TryGetValue<String>('name', ToolName) then Continue;
        ToolObj.TryGetValue<String>('description', ToolDesc);

        InputSch := nil;
        ToolObj.TryGetValue<TJSONObject>('inputSchema', InputSch);

        ResultList.Add(TAiMCPTool.Create(AClient, ToolName, ToolDesc, InputSch));
      end;
    finally
      ListResp.Free;
    end;

    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

end.
