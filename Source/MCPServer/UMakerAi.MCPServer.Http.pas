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
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit UMakerAi.MCPServer.Http;

interface

uses
  System.SysUtils, System.Classes,
  IdContext, IdCustomHTTPServer, IdHTTPServer,
  UMakerAi.MCPServer.Core;

type

  TAiMCPHttpServer = class(TAiMCPServer)
  private
    FHttpServer: TIdHTTPServer;

    procedure HttpCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure ParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String; var VUsername, VPassword: String; var VHandled: Boolean);
    procedure HandleOptionsRequest(AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleGetRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandlePostRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo; const AAuthContext: TAiAuthContext);
    function VerifyAndSetCORSHeaders(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
    // MCP 2026-07-28: validates Mcp-Method/Mcp-Name against the JSON-RPC body.
    // Returns '' if they match (or not applicable) or the JSON of HeaderMismatchError.
    function CheckHeaderMismatch(const ARequestBody, AHdrMethod, AHdrName: string): string;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start; Override;
    procedure Stop; Override;

  Published
    property Port;
    property Endpoint;
    property CorsEnabled;
    property CorsAllowedOrigins;
    property ApiKey;
    property OnValidateRequest;
    // ISSUE #110: client vetting on initialize + session gate on tools/resources/prompts
    property OnClientConnect;
    property OnUnauthorizedRequest;
  end;

procedure Register;

implementation

uses System.StrUtils, IdGlobal, System.JSON;

const
  HTTP_OK = 200;
  HTTP_NO_CONTENT = 204;
  HTTP_BAD_REQUEST = 400;
  HTTP_NOT_FOUND = 404; // <-- CHANGE: Added constant for clarity
  HTTP_FORBIDDEN = 403;
  HTTP_METHOD_NOT_ALLOWED = 405;
  HTTP_INTERNAL_SERVER_ERROR = 500;
  CORS_MAX_AGE_SECONDS = 86400;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMCPHttpServer]);
end;

{ TAiMCPHttpServer }

constructor TAiMCPHttpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FHttpServer := TIdHTTPServer.Create(Self);
  FHttpServer.OnCommandGet := HttpCommand;
  FHttpServer.OnCommandOther := HttpCommand;
  FHttpServer.OnParseAuthentication := ParseAuthentication;
end;

procedure TAiMCPHttpServer.ParseAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String;
  var VUsername, VPassword: String; var VHandled: Boolean);
begin
  // Without this handler, Indy responds 401 to any Authorization scheme
  // other than Basic (e.g. "Bearer <token>") before reaching HttpCommand.
  // Actual validation occurs in ValidateRequest on the raw header
  // (ApiKey / OnValidateRequest); here we only avoid premature rejection.
  VHandled := True;
end;

destructor TAiMCPHttpServer.Destroy;
begin
  FHttpServer.Free;
  inherited Destroy;
end;

procedure TAiMCPHttpServer.Start;
begin
  inherited Start;
  FHttpServer.DefaultPort := FLogicServer.Port;
  // Without BindAddress Indy listens on all interfaces (0.0.0.0)
  FHttpServer.Bindings.Clear;
  if EffectiveBindAddress <> '' then
    FHttpServer.Bindings.Add.SetBinding(EffectiveBindAddress, FLogicServer.Port);
  FHttpServer.Active := True;
end;

procedure TAiMCPHttpServer.Stop;
begin
  if FHttpServer.Active then
    FHttpServer.Active := False;
  inherited Stop;
end;

function TAiMCPHttpServer.VerifyAndSetCORSHeaders(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  Origin: string;
  AllowedOriginsList: TStringList;
  AllowedOrigin: string;
  IsAllowed: Boolean;
begin
  Result := True;
  if not FLogicServer.CorsEnabled then
    Exit;
  Origin := ARequestInfo.RawHeaders.Values['Origin'];
  AllowedOrigin := '*';
  IsAllowed := False;
  if (Origin = '') or (FLogicServer.CorsAllowedOrigins = '*') then
  begin
    IsAllowed := True;
  end
  else
  begin
    AllowedOriginsList := TStringList.Create;
    try
      AllowedOriginsList.DelimitedText := StringReplace(FLogicServer.CorsAllowedOrigins, ';', ',', [rfReplaceAll]);
      if AllowedOriginsList.IndexOf(Origin) > -1 then
      begin
        AllowedOrigin := Origin;
        IsAllowed := True;
      end;
    finally
      AllowedOriginsList.Free;
    end;
  end;

  if not IsAllowed then
  begin
    AResponseInfo.ResponseNo := HTTP_FORBIDDEN;
    AResponseInfo.ResponseText := 'CORS: Origin Not Allowed';
    Result := False;
    Exit;
  end;

  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Origin'] := AllowedOrigin;
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'POST, GET, OPTIONS';
  // ISSUE #110: accept Mcp-Session-Id (MCP standard) in addition to X-Session-ID (legacy),
  // and expose it so browser clients can read the issued session.
  // MCP 2026-07-28: also accept headers for stateless mode
  // (MCP-Protocol-Version, Mcp-Method, Mcp-Name).
  AResponseInfo.CustomHeaders.Values['Access-Control-Allow-Headers'] :=
    'Content-Type, X-Session-ID, Mcp-Session-Id, Authorization, X-API-Key, ' +
    'MCP-Protocol-Version, Mcp-Method, Mcp-Name';
  AResponseInfo.CustomHeaders.Values['Access-Control-Expose-Headers'] := 'Mcp-Session-Id';
  AResponseInfo.CustomHeaders.Values['Access-Control-Max-Age'] := IntToStr(CORS_MAX_AGE_SECONDS);
end;

procedure TAiMCPHttpServer.HttpCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  AuthContext: TAiAuthContext;
  AuthHeader: string;
begin
  // --- STEP 1: Verify and set CORS headers ---
  if not VerifyAndSetCORSHeaders(ARequestInfo, AResponseInfo) then
    Exit;

  // --- STEP 2: Authentication (Layer 1: API Key + Layer 2: Custom event) ---
  // Extract authentication header: first Authorization, then X-API-Key
  AuthHeader := ARequestInfo.RawHeaders.Values['Authorization'];
  if AuthHeader = '' then
    AuthHeader := ARequestInfo.RawHeaders.Values['X-API-Key'];

  if not ValidateRequest(AuthHeader, AContext.Binding.PeerIP, AuthContext) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.ResponseText := 'Unauthorized';
    AResponseInfo.ContentText := '{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication failed"}, "id": null}';
    AResponseInfo.ContentType := 'application/json';
    Exit;
  end;

  // --- STEP 3: Dispatch the request to the correct handler according to the HTTP method ---
  if not SameText(ARequestInfo.URI, Endpoint) then
  begin
    // If the URL is not our /mcp endpoint, return a 404 Not Found.
    AResponseInfo.ResponseNo := HTTP_NOT_FOUND;
    AResponseInfo.ResponseText := 'Not Found';
    AResponseInfo.ContentText := 'Endpoint not found. Please use ' + Endpoint;
  end
  else if SameText(ARequestInfo.Command, 'OPTIONS') then
  begin
    // The browser sends an OPTIONS request (preflight) to verify CORS.
    HandleOptionsRequest(AResponseInfo);
  end
  else if SameText(ARequestInfo.Command, 'GET') then
  begin
    // A GET request to /mcp returns server information.
    HandleGetRequest(ARequestInfo, AResponseInfo);
  end
  else if SameText(ARequestInfo.Command, 'POST') then
  begin
    // A POST request to /mcp contains a JSON-RPC procedure call.
    HandlePostRequest(ARequestInfo, AResponseInfo, AuthContext);
  end
  else
  begin
    // Any other method (PUT, DELETE, etc.) is not allowed.
    AResponseInfo.ResponseNo := HTTP_METHOD_NOT_ALLOWED;
    AResponseInfo.ResponseText := 'Method Not Allowed';
    AResponseInfo.ContentText := 'Only GET, POST, and OPTIONS are supported.';
  end;
end;

procedure TAiMCPHttpServer.HandleOptionsRequest(AResponseInfo: TIdHTTPResponseInfo);
begin
  AResponseInfo.ResponseNo := HTTP_NO_CONTENT;
  AResponseInfo.ResponseText := 'No Content';
  // Indy > 10.6 may require this to avoid the default HTML
  AResponseInfo.ContentLength := 0;
end;

procedure TAiMCPHttpServer.HandleGetRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  InfoObj: TJSONObject;
begin
  // Respond with basic server information in JSON format
  InfoObj := TJSONObject.Create;
  try
    InfoObj.AddPair('serverName', TJSONString.Create(FLogicServer.ServerName));
    InfoObj.AddPair('protocolVersion', TJSONString.Create(FLogicServer.ProtocolVersion));
    // MCP 2026-07-28: also announce support for the modern (stateless) mode.
    var LVersions := TJSONArray.Create;
    LVersions.Add(MCP_PROTOCOL_VERSION_MODERN);
    if FLogicServer.ProtocolVersion <> MCP_PROTOCOL_VERSION_MODERN then
      LVersions.Add(FLogicServer.ProtocolVersion);
    InfoObj.AddPair('supportedVersions', LVersions);
    InfoObj.AddPair('status', TJSONString.Create('active'));

    AResponseInfo.ResponseNo := HTTP_OK;
    AResponseInfo.ResponseText := 'OK';
    AResponseInfo.ContentType := 'application/json; charset=utf-8';
    AResponseInfo.ContentText := InfoObj.ToJSON; // <- Assign the JSON
  finally
    InfoObj.Free;
  end;
end;

procedure TAiMCPHttpServer.HandlePostRequest(ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo; const AAuthContext: TAiAuthContext);
var
  RequestBody, ResponseBody, SessionID, IssuedSessionID: string;
  HdrMethod, HdrName: string;
begin
  try
    RequestBody := ReadStringFromStream(ARequestInfo.PostStream, -1, IndyTextEncoding_UTF8);

    // MCP 2026-07-28: if the client sends the standard headers for stateless
    // mode, they must match the body (HeaderMismatchError -32020).
    // If they are absent (legacy client), the request is accepted as is.
    HdrMethod := ARequestInfo.RawHeaders.Values['Mcp-Method'];
    HdrName := ARequestInfo.RawHeaders.Values['Mcp-Name'];
    if (HdrMethod <> '') or (HdrName <> '') then
    begin
      ResponseBody := CheckHeaderMismatch(RequestBody, HdrMethod, HdrName);
      if ResponseBody <> '' then
      begin
        AResponseInfo.ResponseNo := HTTP_BAD_REQUEST;
        AResponseInfo.ResponseText := 'Bad Request';
        AResponseInfo.ContentType := 'application/json; charset=utf-8';
        AResponseInfo.CharSet := 'utf-8';
        AResponseInfo.ContentText := ResponseBody;
        Exit;
      end;
    end;

    // ISSUE #110: Mcp-Session-Id (MCP standard) with fallback to X-Session-ID (legacy).
    SessionID := ARequestInfo.RawHeaders.Values['Mcp-Session-Id'];
    if SessionID = '' then
      SessionID := ARequestInfo.RawHeaders.Values['X-Session-ID'];

    // Overload with session gate (Part B). If an initialize was successful with
    // gating active, IssuedSessionID carries the Mcp-Session-Id to return to the client.
    ResponseBody := FLogicServer.ExecuteRequest(RequestBody, SessionID, AAuthContext, IssuedSessionID);

    if IssuedSessionID <> '' then
      AResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := IssuedSessionID;

    AResponseInfo.ContentType := 'application/json; charset=utf-8';
    AResponseInfo.CharSet := 'utf-8';

    if ResponseBody = '' then
    begin
      AResponseInfo.ResponseNo := HTTP_NO_CONTENT;
      AResponseInfo.ResponseText := 'No Content';
      AResponseInfo.ContentLength := 0;
    end
    else
    begin
      AResponseInfo.ResponseNo := HTTP_OK;
      AResponseInfo.ResponseText := 'OK';
      AResponseInfo.ContentText := ResponseBody; // <- Assign the JSON
    end;

  except
    on E: Exception do
    begin
      AResponseInfo.ResponseNo := HTTP_INTERNAL_SERVER_ERROR;
      AResponseInfo.ResponseText := 'Internal Server Error';
      AResponseInfo.ContentText := '{"jsonrpc": "2.0", "error": {"code": -32000, "message": "Server error during POST request processing"}, "id": null}';
      AResponseInfo.ContentType := 'application/json';
    end;
  end;
end;

function TAiMCPHttpServer.CheckHeaderMismatch(const ARequestBody, AHdrMethod, AHdrName: string): string;
var
  Root: TJSONValue;
  Obj, ParamsObj: TJSONObject;
  BodyMethod, BodyName, Mismatch: string;
  IdVal: TJSONValue;
  ErrResp, ErrObj: TJSONObject;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(ARequestBody);
  if not(Root is TJSONObject) then
  begin
    Root.Free;
    Exit; // invalid body: the JSON-RPC engine will report it as parse error
  end;
  Obj := TJSONObject(Root);
  try
    BodyMethod := Obj.GetValue<string>('method', '');
    BodyName := '';
    ParamsObj := Obj.GetValue<TJSONObject>('params', nil);
    if Assigned(ParamsObj) then
      BodyName := ParamsObj.GetValue<string>('name', '');

    Mismatch := '';
    if (AHdrMethod <> '') and not SameStr(AHdrMethod, BodyMethod) then
      Mismatch := Format('Mcp-Method header (%s) does not match body method (%s)', [AHdrMethod, BodyMethod])
    else if (AHdrName <> '') and (BodyName <> '') and not SameStr(AHdrName, BodyName) then
      Mismatch := Format('Mcp-Name header (%s) does not match params.name (%s)', [AHdrName, BodyName]);

    if Mismatch = '' then
      Exit;

    ErrResp := TJSONObject.Create;
    try
      ErrResp.AddPair('jsonrpc', '2.0');
      ErrObj := TJSONObject.Create;
      ErrObj.AddPair('code', TJSONNumber.Create(MCP_ERROR_HEADER_MISMATCH));
      ErrObj.AddPair('message', Mismatch);
      ErrResp.AddPair('error', ErrObj);
      IdVal := Obj.GetValue('id');
      if Assigned(IdVal) then
        ErrResp.AddPair('id', TJSONValue(IdVal.Clone))
      else
        ErrResp.AddPair('id', TJSONNull.Create);
      Result := ErrResp.ToJSON;
    finally
      ErrResp.Free;
    end;
  finally
    Obj.Free;
  end;
end;

end.
