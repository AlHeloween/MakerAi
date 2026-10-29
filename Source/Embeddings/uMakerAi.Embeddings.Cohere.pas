unit uMakerAi.Embeddings.Cohere;

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
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.URLClient, System.Net.HttpClient,
  System.Net.Mime, System.Net.HttpClientComponent,
  System.Generics.Collections,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Embeddings, uMakerAi.Embeddings.Core;

type
  TAiCohereInputType = (citSearchDocument, citSearchQuery, citClassification, citClustering);

  TAiCohereEmbeddings = class(TAiEmbeddings)
  private
    FInputType: TAiCohereInputType;
    function GetInputTypeAsString: string;
  protected
    // This method is for processing Cohere-specific response.
    procedure ParseCohereEmbedding(jObj: TJSonObject);
  public
    constructor Create(aOwner: TComponent); override;
    // We override the main method for the Cohere implementation.
    function CreateEmbedding(aInput, aUser: String; aDimensions: Integer = -1; aModel: String = ''; aEncodingFormat: String = 'float'): TAiEmbeddingData; override;
    class function GetDriverName: string; override;
    class function CreateInstance(aOwner: TComponent): TAiEmbeddings; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
  published
    property InputType: TAiCohereInputType read FInputType write FInputType;
  end;

procedure Register;

implementation


procedure Register;
Begin
  RegisterComponents('MakerAI', [TAiCohereEmbeddings]);
End;



{ TAiCohereEmbeddings }

constructor TAiCohereEmbeddings.Create(aOwner: TComponent);
begin
  inherited;
  FInputType := citSearchQuery;
end;

function TAiCohereEmbeddings.CreateEmbedding(aInput, aUser: String; aDimensions: Integer; aModel, aEncodingFormat: String): TAiEmbeddingData;
var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  jObj: TJSonObject;
  JTexts, JEmbeddingTypes: TJSONArray;
  Res: IHTTPResponse;
  ResponseStream: TStringStream;
  BodyStream: TStringStream;
  sUrl: String;
  LModel: string;
  LResponseJson: TJSonObject;
begin
  // If the event is assigned, the logic is delegated (base class behavior)
  if Assigned(OnGetEmbedding) then
  begin
    Result := inherited CreateEmbedding(aInput, aUser, aDimensions, aModel, aEncodingFormat);
    Exit;
  end;

  Client := TNetHTTPClient.Create(Nil);
  BodyStream := TStringStream.Create('', TEncoding.UTF8);
  ResponseStream := TStringStream.Create('', TEncoding.UTF8);
  jObj := TJSonObject.Create;
  try
    sUrl := FUrl + 'embed';

    if aModel <> '' then
      LModel := aModel
    else
      LModel := FModel;

    // 1. Build the JSON request body
    jObj.AddPair('model', LModel);
    jObj.AddPair('input_type', GetInputTypeAsString);

    // The API expects an array of texts. We create one with the single input.
    JTexts := TJSONArray.Create;
    JTexts.Add(aInput);
    jObj.AddPair('texts', JTexts);

    // Request only embeddings of type 'float'
    JEmbeddingTypes := TJSONArray.Create;
    JEmbeddingTypes.Add('float');
    jObj.AddPair('embedding_types', JEmbeddingTypes);

    // Optional: Cohere does not use 'dimensions' like OpenAI, but 'output_dimension'.
    // Add it if it is a valid value for Cohere.
    if (aDimensions = 256) or (aDimensions = 512) or (aDimensions = 1024) or (aDimensions = 1536) then
    begin
      jObj.AddPair('output_dimension', aDimensions);
    end
    else if (aDimensions > 0) then
    begin
      // Optional: Throw a warning or error if user specifies a dimension
      // that is not valid for this model, to avoid confusion.
      // for now, we simply ignore it.
    end;

    BodyStream.WriteString(jObj.ToString);
    BodyStream.Position := 0;

    // 2. Execute the API call
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    Client.ContentType := 'application/json';

    Res := Client.Post(sUrl, BodyStream, ResponseStream, Headers);
    ResponseStream.Position := 0;

    // 3. Process the response
    if Res.StatusCode = 200 then
    begin
      // 1. Parse the response string and cast it to a TJSONObject.
      LResponseJson := TJSonObject.ParseJSONValue(ResponseStream.DataString) as TJSonObject;
      try
        // 2. Pass the parsed JSON object directly to the parse method.
        ParseCohereEmbedding(LResponseJson);
        Result := Self.FData;
      finally
        // 3. Free the memory of the JSON object we created.
        LResponseJson.Free;
      end;
    end
    Else
    begin
      raise Exception.CreateFmt('Error in Cohere Embed API: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;

  finally
    Client.Free;
    BodyStream.Free;
    ResponseStream.Free;
    jObj.Free;
  end;
end;

function TAiCohereEmbeddings.GetInputTypeAsString: string;
begin
  case FInputType of
    citSearchDocument:
      Result := 'search_document';
    citSearchQuery:
      Result := 'search_query';
    citClassification:
      Result := 'classification';
    citClustering:
      Result := 'clustering';
  else
    Result := 'search_query'; // Safe default
  end;
end;

procedure TAiCohereEmbeddings.ParseCohereEmbedding(jObj: TJSonObject);
var
  JEmbeddingsObj: TJSonObject;
  JFloatEmbeddingsArray: TJSONArray;
  JFirstEmbedding: TJSONArray;
  J: Integer;
  JMeta, JBilledUnits: TJSonObject;
begin
  // Clear previous data
  SetLength(FData, 0);
  Fprompt_tokens := 0;
  Ftotal_tokens := 0;

  // Extract token usage
  if jObj.TryGetValue<TJSonObject>('meta', JMeta) then
    if JMeta.TryGetValue<TJSonObject>('billed_units', JBilledUnits) then
      JBilledUnits.TryGetValue<Integer>('input_tokens', Fprompt_tokens);

  Ftotal_tokens := Fprompt_tokens; // In embeddings, total = prompt

  // Navigate the Cohere response structure
  if jObj.TryGetValue<TJSonObject>('embeddings', JEmbeddingsObj) then
  begin
    // Look for the embeddings array of type 'float'
    if JEmbeddingsObj.TryGetValue<TJSONArray>('float', JFloatEmbeddingsArray) then
    begin
      // Since we only request one text, we only care about the first vector
      if JFloatEmbeddingsArray.Count > 0 then
      begin
        JFirstEmbedding := JFloatEmbeddingsArray.Items[0] as TJSONArray;
        if Assigned(JFirstEmbedding) then
        begin
          // Convert the TJSONArray to our TAiEmbeddingData (TArray<Double>)
          SetLength(FData, JFirstEmbedding.Count);
          for J := 0 to JFirstEmbedding.Count - 1 do
            FData[J] := JFirstEmbedding.Items[J].GetValue<Double>;
        end;
      end;
    end;
  end;
end;

{ TAiCohereEmbeddings - Factory class methods }

class function TAiCohereEmbeddings.GetDriverName: string;
begin
  Result := 'Cohere';
end;

class function TAiCohereEmbeddings.CreateInstance(aOwner: TComponent): TAiEmbeddings;
begin
  Result := TAiCohereEmbeddings.Create(aOwner);
end;

class procedure TAiCohereEmbeddings.RegisterDefaultParams(Params: TStrings);
begin
  Params.Values['ApiKey'] := '@COHERE_API_KEY';
  Params.Values['Url'] := 'https://api.cohere.com/v2/';
  Params.Values['Model'] := 'embed-english-v3.0';
  Params.Values['Dimensions'] := '1024';
end;

initialization
  TAiEmbeddingFactory.Instance.RegisterDriver(TAiCohereEmbeddings);

end.
