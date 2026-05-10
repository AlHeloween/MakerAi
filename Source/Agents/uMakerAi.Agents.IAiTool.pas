// MIT License
// MakerAI - Sistema de Agentes v3.4
// Unified tool interface for the agent system redesign.
//
// Author: Gustavo Enríquez
// GitHub: https://github.com/gustavoeenriquez/MakerAi

unit uMakerAi.Agents.IAiTool;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti;

type

  { IAiTool ----------------------------------------------------------------
    Unified interface for all tools in the agent system.
    Any tool (MCP, function, sub-agent, shell) implements this
    interface to be interchangeable within TAiToolRegistry.

    Memory contract:
      - GetSchema   → Do NOT free; the object is owned by the tool.
      - Execute     → The caller is responsible for freeing the TJSONObject
                      returned (may be nil if no result).
  }
  IAiTool = interface
    ['{3F7A9B2E-C154-4D8A-B3F1-0E9A7C6D5824}']
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    // Returns the JSON Schema of parameters. Do NOT free.
    function GetSchema: TJSONObject;
    // Executes the tool with JSON arguments. Caller frees the result.
    function Execute(const AArgs: TJSONObject): TJSONObject;
    // Indicates if the tool is available for use.
    function IsAvailable: Boolean;

    property Name        : String       read GetName;
    property Description : String       read GetDescription;
    property Category    : String       read GetCategory;
  end;

  { TAiToolBase_IAiTool ------------------------------------------------------
    Adapter that wraps TAiToolBase (legacy node system) as IAiTool,
    allowing use in TAiToolRegistry without modifying existing code.

    Usage:
      var Tool: IAiTool := TAiToolBase_IAiTool.Create(MyLegacyTool, True);
  }
  TAiToolBase_IAiTool = class(TInterfacedObject, IAiTool)
  private
    FTool     : TObject;   // TAiToolBase — avoids circular dependency
    FOwnsTool : Boolean;
    FSchema   : TJSONObject;
  public
    constructor Create(ATool: TObject; AOwns: Boolean = False);
    destructor  Destroy; override;
    // IAiTool
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    function GetSchema: TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable: Boolean;
  end;

  { TAiNullTool ---------------------------------------------------------------
    Empty implementation of IAiTool. Useful as placeholder or in tests.
  }
  TAiNullTool = class(TInterfacedObject, IAiTool)
  private
    FName        : String;
    FDescription : String;
  public
    constructor Create(const AName: String = 'null';
                       const ADescription: String = 'No-op tool');
    function GetName: String;
    function GetDescription: String;
    function GetCategory: String;
    function GetSchema: TJSONObject;
    function Execute(const AArgs: TJSONObject): TJSONObject;
    function IsAvailable: Boolean;
  end;

implementation

{ TAiToolBase_IAiTool }

constructor TAiToolBase_IAiTool.Create(ATool: TObject; AOwns: Boolean);
begin
  inherited Create;
  FTool     := ATool;
  FOwnsTool := AOwns;
  FSchema   := nil;
end;

destructor TAiToolBase_IAiTool.Destroy;
begin
  FSchema.Free;
  if FOwnsTool then
    FTool.Free;
  inherited;
end;

function TAiToolBase_IAiTool.GetName: String;
begin
  // Access via RTTI to the published name of TAiToolBase
  if Assigned(FTool) and (FTool is TComponent) then
    Result := TComponent(FTool).Name
  else
    Result := '';
end;

function TAiToolBase_IAiTool.GetDescription: String;
begin
  // Try to read the Description property via RTTI if exists
  Result := '';
  if not Assigned(FTool) then Exit;
  try
    var Ctx := TRttiContext.Create;
    try
      var RttiType := Ctx.GetType(FTool.ClassType);
      var Prop     := RttiType.GetProperty('Description');
      if Assigned(Prop) then
        Result := Prop.GetValue(FTool).AsString;
    finally
      Ctx.Free;
    end;
  except
    Result := FTool.ClassName;
  end;
end;

function TAiToolBase_IAiTool.GetCategory: String;
begin
  Result := 'Legacy';
end;

function TAiToolBase_IAiTool.GetSchema: TJSONObject;
begin
  if not Assigned(FSchema) then
  begin
    FSchema := TJSONObject.Create;
    FSchema.AddPair('type', 'object');
    FSchema.AddPair('properties', TJSONObject.Create);
  end;
  Result := FSchema;
end;

function TAiToolBase_IAiTool.Execute(const AArgs: TJSONObject): TJSONObject;
var
  Input, Output: String;
begin
  Result := nil;
  if not Assigned(FTool) then Exit;

  // Converts JSON args to plain string for TAiToolBase
  if Assigned(AArgs) then
    Input := AArgs.ToJSON
  else
    Input := '';

  Output := '';

  // Calls Execute via RTTI (signature: Execute(ANode, AInput, var AOutput))
  try
    var Ctx := TRttiContext.Create;
    try
      var RttiType := Ctx.GetType(FTool.ClassType);
      var Method   := RttiType.GetMethod('Execute');
      if Assigned(Method) then
      begin
        var Args: TArray<TValue>;
        SetLength(Args, 3);
        Args[0] := TValue.From<TObject>(nil); // ANode = nil
        Args[1] := Input;
        Args[2] := Output;
        Method.Invoke(FTool, Args);
        Output := Args[2].AsString;
      end;
    finally
      Ctx.Free;
    end;
  except
    Output := '';
  end;

  if Output <> '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('result', Output);
  end;
end;

function TAiToolBase_IAiTool.IsAvailable: Boolean;
begin
  Result := Assigned(FTool);
end;

{ TAiNullTool }

constructor TAiNullTool.Create(const AName, ADescription: String);
begin
  inherited Create;
  FName        := AName;
  FDescription := ADescription;
end;

function TAiNullTool.GetName: String;
begin
  Result := FName;
end;

function TAiNullTool.GetDescription: String;
begin
  Result := FDescription;
end;

function TAiNullTool.GetCategory: String;
begin
  Result := 'Null';
end;

function TAiNullTool.GetSchema: TJSONObject;
begin
  Result := nil;
end;

function TAiNullTool.Execute(const AArgs: TJSONObject): TJSONObject;
begin
  Result := nil;
end;

function TAiNullTool.IsAvailable: Boolean;
begin
  Result := False;
end;

end.
