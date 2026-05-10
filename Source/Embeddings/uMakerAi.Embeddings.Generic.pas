unit uMakerAi.Embeddings.Generic;

// MIT License
//
// Copyright (c) 2013 Gustavo Enriquez - CimaMaker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// o use, copy, modify, merge, publish, distribute, sublicense, and/or sell
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
// Nombre: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

// Generic embeddings driver for any API-compatible endpoint
// OpenAI de embeddings (POST /embeddings con body {input, model, dimensions}).
// Soporta: vLLM, llama.cpp, OpenLLM, Text Embeddings Inference (TEI),
//          Hugging Face Inference Endpoints, FastEmbed-server, y cualquier
//          proveedor con interfaz OpenAI-compatible.
//
// Minimal usage:
//   EmbConn.DriverName := 'GenericLLM';
//   EmbConn.Url        := 'http://localhost:8080/v1/';
//   EmbConn.Model      := 'BAAI/bge-m3';
//   EmbConn.ApiKey     := 'optional-token';
//
// El campo ParseEmbedding soporta dos formatos de respuesta:
//   Formato OpenAI:    {"data": [{"embedding": [...]}]}
//   Formato directo:   {"embedding": [...]}   (usado por algunos servidores locales)

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.URLClient, System.Net.HttpClient,
  System.Net.Mime, System.Net.HttpClientComponent,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Embeddings, uMakerAi.Embeddings.Core;

type
  // Generic driver for any OpenAI-compatible embeddings API.
  // Configure Url, ApiKey and Model at design time or in code.
  // Permite registrar el mismo driver bajo nombres distintos mediante
  // CustomDriverName, igual que TAiGenericChat, para tener varios proveedores
  // simultaneous generics in the same project.
  TAiGenericEmbeddings = class(TAiEmbeddings)
  private
    FCustomDriverName: string;
    procedure SetCustomDriverName(const Value: string);
  public
    constructor Create(aOwner: TComponent); override;
    function  CreateEmbedding(aInput, aUser: String; aDimensions: Integer = -1;
      aModel: String = ''; aEncodingFormat: String = 'float'): TAiEmbeddingData; override;
    procedure ParseEmbedding(jObj: TJSONObject); override;
    class function GetDriverName: string; override;
    class function CreateInstance(aOwner: TComponent): TAiEmbeddings; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
  published
    // Nombre con el que este componente se registra en la factory.
    // Allows using multiple instances pointing to different APIs.
    // Ej: 'AzureEmb', 'LocalTEI', 'VllmServer'
    property CustomDriverName: string read FCustomDriverName write SetCustomDriverName;
  end;


procedure Register;


implementation


procedure Register;
Begin
  RegisterComponents('MakerAI', [TAiGenericEmbeddings]);
End;



{ TAiGenericEmbeddings }

procedure TAiGenericEmbeddings.SetCustomDriverName(const Value: string);
begin
  if FCustomDriverName = Value then Exit;
  FCustomDriverName := Value;
// Register the class in the factory under the custom name.
  // 'GenericLLM' siempre queda registrado (via initialization).
  if Value <> '' then
    TAiEmbeddingFactory.Instance.RegisterDriver(TAiGenericEmbeddings, Value);
end;

constructor TAiGenericEmbeddings.Create(aOwner: TComponent);
begin
  inherited;
end;

function TAiGenericEmbeddings.CreateEmbedding(aInput, aUser: String;
  aDimensions: Integer; aModel, aEncodingFormat: String): TAiEmbeddingData;
var
  Client   : TNetHTTPClient;
  Headers  : TNetHeaders;
  jReq     : TJSONObject;
  jResp    : TJSONObject;
  Res      : IHTTPResponse;
  StReq    : TStringStream;
  StResp   : TStringStream;
  sUrl     : String;
begin
  Result := nil;

  if aModel = '' then
    aModel := FModel;

  if aDimensions <= 0 then
    aDimensions := FDimensions;

  // Normalizar URL: asegurar que termina en /
  sUrl := FUrl.TrimRight(['/']) + '/embeddings';

  Client := TNetHTTPClient.Create(nil);
{$IF CompilerVersion >= 35}
  Client.SynchronizeEvents := False;
{$ENDIF}
  StReq  := TStringStream.Create('', TEncoding.UTF8);
  StResp := TStringStream.Create('', TEncoding.UTF8);
  jReq   := TJSONObject.Create;
  jResp  := nil;

  try
    // Standard OpenAI-compatible fields
    jReq.AddPair('input', aInput);
    jReq.AddPair('model', aModel);

    if aUser <> '' then
      jReq.AddPair('user', aUser);

    if aDimensions > 0 then
      jReq.AddPair('dimensions', TJSONNumber.Create(aDimensions));

    if aEncodingFormat <> '' then
      jReq.AddPair('encoding_format', aEncodingFormat);

    StReq.WriteString(jReq.ToJSON);
    StReq.Position := 0;

    Headers := [];
    if FApiKey <> '' then
      Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    Client.ContentType := 'application/json';
    Res := Client.Post(sUrl, StReq, StResp, Headers);

    if Res.StatusCode = 200 then
    begin
      jResp := TJSONObject(TJSONObject.ParseJSONValue(Res.ContentAsString));
      if Assigned(jResp) then
        ParseEmbedding(jResp);
      Result := FData;
    end
    else
      raise Exception.CreateFmt('GenericEmbeddings error %d: %s',
        [Res.StatusCode, Res.ContentAsString]);

  finally
    Client.Free;
    StReq.Free;
    StResp.Free;
    jReq.Free;
    if Assigned(jResp) then
      jResp.Free;
  end;
end;

procedure TAiGenericEmbeddings.ParseEmbedding(jObj: TJSONObject);
var
  jData    : TJSONArray;
  jFirst   : TJSONObject;
  jVec     : TJSONArray;
  jUsage   : TJSONObject;
  Emb      : TAiEmbeddingData;
  i        : Integer;
begin
  // Tokens de uso (opcional — no todos los servidores lo reportan)
  if jObj.TryGetValue<TJSONObject>('usage', jUsage) then
  begin
    jUsage.TryGetValue<Integer>('prompt_tokens', Fprompt_tokens);
    jUsage.TryGetValue<Integer>('total_tokens',  Ftotal_tokens);
  end;

  // Format 1 — Standard OpenAI: {"data": [{"embedding": [...]}]}
  if jObj.TryGetValue<TJSONArray>('data', jData) and (jData.Count > 0) then
  begin
    jFirst := jData.Items[0] as TJSONObject;
    if jFirst.TryGetValue<TJSONArray>('embedding', jVec) then
    begin
      SetLength(Emb, jVec.Count);
      for i := 0 to jVec.Count - 1 do
        Emb[i] := jVec.Items[i].GetValue<Double>;
      FData := Emb;
    end;
    Exit;
  end;

  // Formato 2 — directo: {"embedding": [...]}  (llama.cpp, algunos servidores locales)
  if jObj.TryGetValue<TJSONArray>('embedding', jVec) then
  begin
    SetLength(Emb, jVec.Count);
    for i := 0 to jVec.Count - 1 do
      Emb[i] := jVec.Items[i].GetValue<Double>;
    FData := Emb;
  end;
end;

{ Factory methods }

class function TAiGenericEmbeddings.GetDriverName: string;
begin
  Result := 'GenericLLM';
end;

class function TAiGenericEmbeddings.CreateInstance(aOwner: TComponent): TAiEmbeddings;
begin
  Result := TAiGenericEmbeddings.Create(aOwner);
end;

class procedure TAiGenericEmbeddings.RegisterDefaultParams(Params: TStrings);
begin
  Params.Values['ApiKey']     := '';
  Params.Values['Url']        := 'http://localhost:8080/v1/';
  Params.Values['Model']      := '';
  Params.Values['Dimensions'] := '-1';
end;

initialization
  TAiEmbeddingFactory.Instance.RegisterDriver(TAiGenericEmbeddings);

end.
