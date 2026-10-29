unit uTool.Aprobacion;

// =============================================================================
// MCP tool with MRTR pattern (Multi-Round Tool Request, spec 2026-07-28)
// =============================================================================
// SERVER side of elicitation. The flow has two rounds:
//
//   Round 1: the tool does NOT execute anything. It returns an InputRequiredResult
//             (resultType='input_required') with an ElicitRequest describing
//             what it needs from the user, plus an opaque requestState.
//   Round 2: the client repeats tools/call adding inputResponses (with the
//             user's response) and the echo of requestState. Only then does the
//             tool validate and execute.
//
// It is the mechanism that lets a tool ask for confirmation without the
// server having to keep a session: all state travels in requestState.
//
// SECURITY: requestState goes through the client, so it is UNTRUSTED input.
// Here it only carries the amount in Base64 for demonstration purposes. In
// production, if it affects authorization or business logic, it must be signed
// with HMAC/AEAD; otherwise the client can alter it at will.
// =============================================================================

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils, System.NetEncoding, System.JSON;

type
  TAprobacionParams = class
  private
    FMonto: string;
  public
    [AiMCPSchemaDescription('Amount of the transfer to authorize (e.g.: "1500 EUR")')]
    property Monto: string read FMonto write FMonto;
  end;

  TAprobacionTool = class(TAiMCPToolBase<TAprobacionParams>)
  private
    function ConstruirInputRequired(const AMonto: string): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAprobacionParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

implementation

constructor TAprobacionTool.Create;
begin
  inherited;
  FName := 'autorizar_transferencia';
  FDescription := 'Executes a transfer only after the user authorizes it via elicitation (MRTR)';
end;

function TAprobacionTool.ConstruirInputRequired(const AMonto: string): TJSONObject;
var
  Reqs, Elicit, ElicitParams, Schema, Props, PropConfirm: TJSONObject;
  Required: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resultType', 'input_required');

  Reqs := TJSONObject.Create;
  Result.AddPair('inputRequests', Reqs);

  // The key ('autorizacion') is the identifier with which the client must
  // return its response in inputResponses.
  Elicit := TJSONObject.Create;
  Reqs.AddPair('autorizacion', Elicit);
  Elicit.AddPair('method', 'elicitation/create');

  ElicitParams := TJSONObject.Create;
  Elicit.AddPair('params', ElicitParams);
  ElicitParams.AddPair('mode', 'form');
  ElicitParams.AddPair('message', 'Authorize the transfer of ' + AMonto + '?');

  // The schema tells the client what shape the expected response has
  Schema := TJSONObject.Create;
  ElicitParams.AddPair('requestedSchema', Schema);
  Schema.AddPair('type', 'object');
  Props := TJSONObject.Create;
  Schema.AddPair('properties', Props);
  PropConfirm := TJSONObject.Create;
  Props.AddPair('confirmar', PropConfirm);
  PropConfirm.AddPair('type', 'boolean');
  Required := TJSONArray.Create;
  Required.Add('confirmar');
  Schema.AddPair('required', Required);

  Result.AddPair('requestState', TNetEncoding.Base64.Encode(AMonto));
end;

function TAprobacionTool.ExecuteWithParams(const AParams: TAprobacionParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  V: TJSONValue;
  Respuesta: TJSONObject;
  Accion, EstadoDecodificado: string;
begin
  if AParams.Monto.IsEmpty then
    Exit(TAiMCPResponseBuilder.New.AddText('Error: the "Monto" parameter is required').Build);

  // Is this the retry with the user's response?
  if Assigned(AuthContext.InputResponses) then
  begin
    V := AuthContext.InputResponses.GetValue('autorizacion');
    if not(V is TJSONObject) then
      // What was requested is missing: the spec says to ask again, not to fail.
      Exit(ConstruirInputRequired(AParams.Monto));

    Respuesta := TJSONObject(V);
    Accion := Respuesta.GetValue<string>('action', '');

    // Verify the requestState echo. It is untrusted input: a corrupt value
    // must produce a clean rejection, never an internal exception.
    EstadoDecodificado := '';
    if AuthContext.RequestState <> '' then
      try
        EstadoDecodificado := TNetEncoding.Base64.Decode(AuthContext.RequestState);
      except
        EstadoDecodificado := '';
      end;
    if EstadoDecodificado <> AParams.Monto then
      Exit(TAiMCPResponseBuilder.New.AddText('Error: invalid or missing requestState in retry').Build);

    if SameText(Accion, 'accept') then
      Exit(TAiMCPResponseBuilder.New.AddText('AUTHORIZED and executed transfer of ' + AParams.Monto).Build)
    else
      Exit(TAiMCPResponseBuilder.New.AddText('REJECTED by the user: ' + AParams.Monto).Build);
  end;

  // First call: request authorization.
  Result := ConstruirInputRequired(AParams.Monto);
end;

end.
