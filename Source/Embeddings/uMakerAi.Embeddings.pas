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


unit uMakerAi.Embeddings;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Threading, System.NetConsts,
  System.Variants, System.Net.Mime, System.IOUtils, System.Generics.Collections,
  System.NetEncoding,
  System.JSON, System.StrUtils, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent,
  REST.JSON, REST.Types, REST.Client,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}

  uMakerAi.Embeddings.core;

type
  // For compatibility, we keep the name, but now it inherits from the base class.
  TAiEmbeddings = class(TAiEmbeddingsCore)
  private
    procedure SetApiKey(const Value: String);
    function GetApiKey: String;
    procedure SetUrl(const Value: String);
  protected
    FApiKey: String;
    FUrl: String;
    // This method is now 'override' to provide the specific implementation.
  public
    constructor Create(aOwner: TComponent); override;
    // This method is specific to the OpenAI implementation.
    procedure ParseEmbedding(JObj: TJsonObject); Virtual;
    function CreateEmbedding(aInput, aUser: String; aDimensions: Integer = -1; aModel: String = ''; aEncodingFormat: String = 'float'): TAiEmbeddingData; override;
    // Class methods for the pattern Factory (TAiEmbeddingFactory)
    class function GetDriverName: string; virtual;
    class function CreateInstance(aOwner: TComponent): TAiEmbeddings; virtual;
    class procedure RegisterDefaultParams(Params: TStrings); virtual;
  published
    // Properties specific to this implementation.
    property ApiKey: String read GetApiKey write SetApiKey;
    property Url: String read FUrl write SetUrl;
  end;

implementation

const
  GlOpenAIUrl = 'https://api.openai.com/v1/';

  { TAiEmbeddings }

constructor TAiEmbeddings.Create(aOwner: TComponent);
begin
  inherited; // Calls the constructor of Core.TAiEmbeddings.
  Url := GlOpenAIUrl;
  FModel := 'text-embedding-3-small';
end;

procedure TAiEmbeddings.ParseEmbedding(JObj: TJsonObject);
var
  JArrData, JArrVector: TJSONArray;
  Emb: TAiEmbeddingData;
  JVal: TJSONValue;
  Usage: TJSONObject;
  i: Integer;
begin
  // Initial validation
  if not Assigned(JObj) then
    Exit;

  // 1. Get the model
  JObj.TryGetValue<String>('model', FModel);

  // 2. Token usage (optional)
  if JObj.TryGetValue<TJSONObject>('usage', Usage) then
  begin
    Usage.TryGetValue<Integer>('prompt_tokens', Fprompt_tokens);
    Usage.TryGetValue<Integer>('total_tokens', Ftotal_tokens);
  end;

  // 3. Get the 'data' array with validation
  if not JObj.TryGetValue<TJSONArray>('data', JArrData) then
    raise Exception.Create('API response does not contain the expected data array ("data").');

  if JArrData.Count = 0 then
    raise Exception.Create('The data array ("data") is empty.');

  // Prepare array for multiple embeddings (although we only use the first one)
  SetLength(FData, JArrData.Count);

  // 4. Process the first embedding (compatibility with original version)
  for JVal in JArrData do
  begin
    // Validate that it is an object
    if not (JVal is TJSONObject) then
      raise Exception.Create('Invalid data item format in the JSON response.');

    // 5. Get the embedding vector
    if not TJSONObject(JVal).TryGetValue<TJSONArray>('embedding', JArrVector) then
      raise Exception.Create('The "embedding" field was not found in the response data.');

    if JArrVector.Count = 0 then
      raise Exception.Create('The embedding vector is empty.');

    // 6. Dimension and fill the vector with type validation
    SetLength(Emb, JArrVector.Count);
    for i := 0 to JArrVector.Count - 1 do
    begin
      if not JArrVector.Items[i].TryGetValue<Double>(Emb[i]) then
        Emb[i] := 0.0; // Default value if conversion fails.
    end;

    // 7. Assign the processed embedding
    FData := Emb;

    // We only process the first element (original behavior)
    Break;
  end;
end;

function TAiEmbeddings.CreateEmbedding(aInput, aUser: String; aDimensions: Integer; aModel, aEncodingFormat: String): TAiEmbeddingData;
var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  RequestBody, ResponseJSON: TJSONObject;
  Res: IHTTPResponse;
  ResponseStream: TStringStream;
  RequestStream: TStringStream;
  sUrl: String;
begin
  // Delegation to event if assigned
  if Assigned(OnGetEmbedding) then
  begin
    Result := inherited CreateEmbedding(aInput, aUser, aDimensions, aModel, aEncodingFormat);
    Exit;
  end;

  Client := TNetHTTPClient.Create(nil);
{$IF CompilerVersion >= 34}
  Client.SynchronizeEvents := False;
{$ENDIF}
  RequestStream := TStringStream.Create('', TEncoding.UTF8);
  ResponseStream := TStringStream.Create('', TEncoding.UTF8);
  RequestBody := TJSONObject.Create;

  try
    // Build URL by removing trailing slashes
    sUrl := FUrl.TrimRight(['/']) + '/embeddings';

    // Set default values
    if aModel = '' then
      aModel := FModel;
    if aDimensions <= 0 then
      aDimensions := FDimensions;

    // Construction of the request JSON
    RequestBody.AddPair('input', aInput);     // OpenAI
    RequestBody.AddPair('prompt', aInput);    // Compatibility with Ollama
    RequestBody.AddPair('model', aModel);
    RequestBody.AddPair('user', aUser);
    RequestBody.AddPair('dimensions', TJSONNumber.Create(aDimensions));
    RequestBody.AddPair('encoding_format', aEncodingFormat);

    // Write the JSON to the stream
    RequestStream.WriteString(RequestBody.Format);
    RequestStream.Position := 0;

    // Set headers
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    Headers := Headers + [TNetHeader.Create('OpenAI-Beta', 'assistants=v2')];

    Client.ContentType := 'application/json';

    // Make the request
    Res := Client.Post(sUrl, RequestStream, ResponseStream, Headers);
    ResponseStream.Position := 0;

{$IFDEF APIDEBUG}
    ResponseStream.SaveToFile('c:\temp\response.txt');
{$ENDIF}

    if Res.StatusCode = 200 then
    begin
      // Parse the JSON response
      ResponseJSON := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      try
        if not Assigned(ResponseJSON) then
          raise Exception.Create('The API response is not valid JSON.');

        ParseEmbedding(ResponseJSON);
        Result := Self.FData;
      finally
        ResponseJSON.Free;
      end;
    end
    else
    begin
      raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;
  finally
    Client.Free;
    RequestStream.Free;
    ResponseStream.Free;
    RequestBody.Free;
  end;
end;

function TAiEmbeddings.GetApiKey: String;
begin
  if (csDesigning in ComponentState) or (csDestroying in ComponentState) then
  begin
    Result := FApiKey;
    Exit;
  end;
  if (FApiKey <> '') and (FApiKey.StartsWith('@')) then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, Length(FApiKey)))
  else
    Result := FApiKey;
end;

procedure TAiEmbeddings.SetApiKey(const Value: String);
begin
  FApiKey := Value;
end;

procedure TAiEmbeddings.SetUrl(const Value: String);
begin
  if Value <> '' then
    FUrl := Value
  else
    FUrl := GlOpenAIUrl;
end;

class function TAiEmbeddings.GetDriverName: string;
begin
  Result := '';
end;

class function TAiEmbeddings.CreateInstance(aOwner: TComponent): TAiEmbeddings;
begin
  Result := TAiEmbeddings.Create(aOwner);
end;

class procedure TAiEmbeddings.RegisterDefaultParams(Params: TStrings);
begin
  Params.Values['ApiKey'] := '@OPENAI_API_KEY';
  Params.Values['Url'] := GlOpenAIUrl;
  Params.Values['Model'] := 'text-embedding-3-small';
  Params.Values['Dimensions'] := '1536';
end;

end.
