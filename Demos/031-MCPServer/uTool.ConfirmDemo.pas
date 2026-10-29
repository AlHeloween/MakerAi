unit uTool.ConfirmDemo;

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils, System.NetEncoding,
  System.JSON;

type
  // =============================================================================
  // DEMO TOOL FOR THE MRTR PATTERN (MCP spec 2026-07-28)
  // =============================================================================
  // First call: the tool does not execute anything and returns an InputRequiredResult
  // (resultType='input_required') with an ElicitRequest asking the user for confirmation,
  // plus an opaque requestState.
  // Retry: the client repeats tools/call adding inputResponses (with the
  // ElicitResult) and the echo of requestState; the tool validates and executes.
  //
  // SECURITY NOTE: requestState travels through the client and is UNTRUSTED
  // input. In production it must be protected with HMAC/AEAD if it affects
  // authorization or business logic. Here it only transports the message in
  // Base64 for demonstration purposes (an alteration only makes the request fail).

  TConfirmDemoParams = class
  private
    FOperation: string;
  public
    [AiMCPSchemaDescription('Operation that requires user confirmation (e.g.: "delete temp.txt file")')]
    property Operation: string read FOperation write FOperation;
  end;

  TConfirmDemoTool = class(TAiMCPToolBase<TConfirmDemoParams>)
  private
    function BuildInputRequired(const AOperation: string): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TConfirmDemoParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterConfirmDemoTool(ALogicServer: TAiMCPServer);

implementation

{ TConfirmDemoTool }

constructor TConfirmDemoTool.Create;
begin
  inherited;
  FName := 'confirm_demo';
  FDescription := 'Demo MRTR: ejecuta una operacion solo despues de que el usuario la confirme via elicitation (spec 2026-07-28)';
end;

// Construye el InputRequiredResult con un ElicitRequest 'user_confirmation'.
function TConfirmDemoTool.BuildInputRequired(const AOperation: string): TJSONObject;
var
  Reqs, Elicit, ElicitParams, Schema, Props, ConfirmProp: TJSONObject;
  Required: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resultType', 'input_required');

  Reqs := TJSONObject.Create;
  Result.AddPair('inputRequests', Reqs);

  Elicit := TJSONObject.Create;
  Reqs.AddPair('user_confirmation', Elicit);
  Elicit.AddPair('method', 'elicitation/create');
  ElicitParams := TJSONObject.Create;
  Elicit.AddPair('params', ElicitParams);
  ElicitParams.AddPair('mode', 'form');
  ElicitParams.AddPair('message', 'Confirma la operacion: ' + AOperation);
  Schema := TJSONObject.Create;
  ElicitParams.AddPair('requestedSchema', Schema);
  Schema.AddPair('type', 'object');
  Props := TJSONObject.Create;
  Schema.AddPair('properties', Props);
  ConfirmProp := TJSONObject.Create;
  Props.AddPair('confirm', ConfirmProp);
  ConfirmProp.AddPair('type', 'boolean');
  Required := TJSONArray.Create;
  Required.Add('confirm');
  Schema.AddPair('required', Required);

  // Estado opaco que el cliente debe ecoar en el reintento (demo: Base64).
  Result.AddPair('requestState', TNetEncoding.Base64.Encode(AOperation));
end;

function TConfirmDemoTool.ExecuteWithParams(const AParams: TConfirmDemoParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  V: TJSONValue;
  ElicitResult: TJSONObject;
  Action, DecodedState: string;
begin
  if AParams.Operation.IsEmpty then
    Exit(TAiMCPResponseBuilder.New.AddText('Error: the "Operation" parameter is required').Build);

  // Is it an MRTR retry with the elicitation response?
  if Assigned(AuthContext.InputResponses) then
  begin
    V := AuthContext.InputResponses.GetValue('user_confirmation');
    if not(V is TJSONObject) then
      // The requested response is missing: the spec says to ask again, not to fail.
      Exit(BuildInputRequired(AParams.Operation));

    ElicitResult := TJSONObject(V);
    Action := ElicitResult.GetValue<string>('action', '');

    // Verify the requestState echo (intact round-trip demo).
    // requestState is untrusted input: a corrupted value should only
    // produce a clean rejection, never an internal exception.
    DecodedState := '';
    if AuthContext.RequestState <> '' then
      try
        DecodedState := TNetEncoding.Base64.Decode(AuthContext.RequestState);
      except
        DecodedState := '';
      end;
    if DecodedState <> AParams.Operation then
      Exit(TAiMCPResponseBuilder.New.AddText('Error: invalid or missing requestState in retry').Build);

    if SameText(Action, 'accept') then
      Exit(TAiMCPResponseBuilder.New.AddText('CONFIRMED and executed: ' + AParams.Operation).Build)
    else
      Exit(TAiMCPResponseBuilder.New.AddText('CANCELLED by the user: ' + AParams.Operation).Build);
  end;

  // First call: request confirmation via MRTR.
  Result := BuildInputRequired(AParams.Operation);
end;

procedure RegisterConfirmDemoTool(ALogicServer: TAiMCPServer);
begin
  if not Assigned(ALogicServer) then
    raise Exception.Create('LogicServer cannot be null to register tools.');

  ALogicServer.RegisterTool('confirm_demo',
    function: IAiMCPTool
    begin
      Result := TConfirmDemoTool.Create;
    end);
end;

end.
