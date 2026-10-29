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
// Name: Gustavo Enr�quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uMakerAi.Chat.OpenAi_Deprecated;


interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Threading, System.NetEncoding, System.Types, System.NetConsts,
  System.Net.Mime,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,
  System.JSON, Rest.JSON,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.ToolFunctions, uMakerAi.Core, uMakerAi.Chat,
  uMakerAi.Embeddings, uMakerAi.Embeddings.Core, uMakerAi.Utils.CodeExtractor;

type

  TAiOpenChat = class(TAiChat)
  Private
    FStore: Boolean;
    FParallel_ToolCalls: Boolean;
    FService_Tier: String;
    procedure SetStore(const Value: Boolean);
    procedure SetParallel_ToolCalls(const Value: Boolean);
    procedure SetService_Tier(const Value: String);
  Protected
    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;

    function InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunImageDalleGeneration(ResMsg, AskMsg: TAiChatMessage): String;
    function InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeWebSearch(ResMsg, AskMsg: TAiChatMessage): String; Override;

    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
    // function InternalRunImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;

    Function InitChatCompletions: String; Override;
    Procedure ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage); Override;
    procedure ParseJsonTranscript(jObj: TJSonObject; ResMsg: TAiChatMessage; aMediaFile: TAiMediaFile);
    procedure ParseResponse(jObj: TJSonObject; ResMsg: TAiChatMessage);

    Function ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions; Override;
    Procedure DoCallFunction(ToolCall: TAiToolsFunction); Override;
    function GetTools(aToolFormat: TToolFormat): TStrings; Override;
    Function PrepareSystemMsg: String; Override; // Crea el primer mensaje del chat para system, para configurar el asistente
  Public
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    Class Function GetModels(aApiKey: String; aUrl: String = ''): TStringList; Overload; Override;
    Function GetModels: TStringList; Overload; Override;
    Function GetMessages: TJSonArray; Override;

    Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer = 3600): String; Override;

    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;

  Published
    Property Store: Boolean read FStore write SetStore;
    Property Parallel_ToolCalls: Boolean read FParallel_ToolCalls write SetParallel_ToolCalls;
    Property Service_Tier: String read FService_Tier write SetService_Tier;
  end;

  TAiOpenAiEmbeddings = class(TAiEmbeddings)
  Public
    Constructor Create(aOwner: TComponent); Override;
    Destructor Destroy; Override;
    Function CreateEmbedding(aInput, aUser: String; aDimensions: integer = -1; aModel: String = ''; aEncodingFormat: String = 'float'): TAiEmbeddingData; Override;
    Procedure ParseEmbedding(jObj: TJSonObject); Override;
  end;

//procedure Register;

implementation

//procedure Register;
//begin
//  RegisterComponents('MakerAI', [TAiOpenChat, TAiOpenAiEmbeddings]);
//end;

{ TAiChat }

Const
  GlOpenAIUrl = 'https://api.openai.com/v1/';

class function TAiOpenChat.GetDriverName: string;
Begin
  Result := 'OpenAi';
End;

class procedure TAiOpenChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@OPENAI_API_KEY');
  Params.Add('Model=gpt-4o');
  Params.Add('MaxTokens=4096');
  Params.Add('URL=https://api.openai.com/v1/');
End;

class function TAiOpenChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiOpenChat.Create(Sender);
End;

function TAiOpenChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
Var
  ABody: String;
  sUrl: String;
  Res: IHTTPResponse;
  St: TStringStream;
  FHeaders: TNetHeaders;
  jObj: TJSonObject;
begin

  FBusy := True; // Marks the system as busy
  FAbort := False; // Initializes as not aborted
  FLastError := '';
  FLastContent := '';
  FLastPrompt := '';

  St := TStringStream.Create('', TEncoding.UTF8);
  sUrl := Url + 'chat/completions';

  Try
    DoStateChange(acsConnecting, 'Sending request...');

    FHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    ABody := InitChatCompletions;

    St.WriteString(ABody);
    St.Position := 0;

    LogDebug('--Request-Body--');
    LogDebug('    ' + ABody);

    // $IFDEF APIDEBUG
    St.SaveToFile('c:\temp\peticion.txt');
    St.Position := 0;
    // $ENDIF
    FResponse.Clear;
    FResponse.Position := 0;

    Res := FClient.Post(sUrl, St, FResponse, FHeaders);

    FResponse.Position := 0;
    // $IFDEF APIDEBUG
    FResponse.SaveToFile('c:\temp\respuesta.txt');
    FResponse.Position := 0;
    // $ENDIF
    FLastContent := '';

    // If Self.Asynchronous = False then
    If FClient.Asynchronous = False then
    Begin

      LogDebug('--Response---');
      LogDebug('    ' + Res.ContentAsString);

      if Res.StatusCode = 200 then
      Begin
        jObj := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
        Try
          FBusy := False;
          ParseChat(jObj, ResMsg);
          Result := FLastContent;

        Finally
          FreeAndNil(jObj);
        End;
      End
      else
      begin
        Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end;
    End;
  Finally
    If FClient.Asynchronous = False then
      St.Free; // This doesn't work in multithreading, so it's freed when it's not.
  End;
end;

function TAiOpenChat.InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl: string;
  LBodyStream, LResponseStream: TStringStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LJsonObject, LResponseJson, LImageObject: TJSonObject;
  LDataArray: TJSonArray;
  LBase64Data: string;
  // LBinaryStream: TMemoryStream;
  LNewImageFile: TAiMediaFile;
  LErrorResponse: string;
  aPrompt_tokens, aCompletion_tokens, aTotal_tokens: integer;
  LModel: String;
begin

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  if (Pos('dall-e', LowerCase(LModel)) > 0) then
  begin
    // Uses the legacy DALL-E API
    Result := InternalRunImageDalleGeneration(ResMsg, AskMsg);
    Exit
  end;

  Result := ''; // The main function returns no text, the image goes in ResMsg
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  // 1. A�adir el mensaje del usuario al historial
  if FMessages.IndexOf(AskMsg) < 0 then
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  // 2. Preparar par�metros for the API de DALL-E
  LUrl := Url + 'images/generations'; // Asume que 'Url' es la URL base de OpenAI
  LJsonObject := TJSonObject.Create;
  LBodyStream := nil;
  LResponseStream := nil;
  LResponseJson := nil;

  try
    LJsonObject.AddPair('model', LModel); // Should be 'gpt-image-1'
    LJsonObject.AddPair('prompt', TJSONString.Create(AskMsg.Prompt));
    LJsonObject.AddPair('n', TJSONNumber.Create(n));
    // LJsonObject.AddPair('response_format', TJSONString.Create('b64_json'));
    // LJsonObject.AddPair('size', '1024x1024');

    // Optional parameters,  you can add controls for this.
    // LJsonObject.AddPair('size', '1024x1024');
    // LJsonObject.AddPair('quality', 'high');
    // LJsonObject.AddPair('output_format', 'png');

    if LModel = 'dall-e-2' then
    begin
      // LJsonObject.AddPair('quality', TJSONString.Create('hd'));
      // LJsonObject.AddPair('style', TJSONString.Create('vivid')); // vivid or natural
    end
    Else if LModel = 'dall-e-3' then
    begin
      // LJsonObject.AddPair('quality', TJSONString.Create('hd'));
      // LJsonObject.AddPair('style', TJSONString.Create('vivid')); // vivid or natural
    end;

    // A�adir identificador de usuario
    if not User.IsEmpty then
      LJsonObject.AddPair('user', TJSONString.Create(User));

    // 4. Ejecutar la petici�n HTTP
    LBodyStream := TStringStream.Create(LJsonObject.ToString, TEncoding.UTF8);
    LResponseStream := TStringStream.Create('', TEncoding.UTF8);

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

    LResponseStream.SaveToFile('c:\temp\respuesta.txt');
    LResponseStream.Position := 0;

    // 5. Procesar la respuesta
    if LResponse.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject.ParseJSONValue(LResponseStream.DataString) as TJSonObject;
      if LResponseJson = nil then
        raise Exception.Create('Error parsing JSON response from DALL-E.');

      // El objeto 'usage' puede no venir en respuestas con errores
      Var
        uso: TJSonObject;

      if LResponseJson.TryGetValue<TJSonObject>('usage', uso) then
      begin
        aPrompt_tokens := uso.GetValue<integer>('input_tokens');
        aCompletion_tokens := uso.GetValue<integer>('output_tokens');
        aTotal_tokens := uso.GetValue<integer>('total_tokens');
      end
      else
      begin
        aPrompt_tokens := 0;
        aCompletion_tokens := 0;
        aTotal_tokens := 0;
      end;

      Self.Prompt_tokens := Self.Prompt_tokens + aPrompt_tokens;
      Self.Completion_tokens := Self.Completion_tokens + aCompletion_tokens;
      Self.Total_tokens := Self.Total_tokens + aTotal_tokens;

      LDataArray := LResponseJson.GetValue<TJSonArray>('data');

      if (LDataArray <> nil) and (LDataArray.Count > 0) then
      begin
        LImageObject := LDataArray.Items[0] as TJSonObject;
        LBase64Data := LImageObject.GetValue<string>('b64_json');

        Var
          RevisedPrompt: String;
        LImageObject.TryGetValue<String>('revised_prompt', RevisedPrompt);

        FLastContent := Trim(FLastContent + sLineBreak + RevisedPrompt);

        // Crear el archivo de media y adjuntarlo al mensaje de respuesta
        LNewImageFile := TAiMediaFile.Create;
        try
          // DALL-E genera im�genes en formato PNG
          LNewImageFile.LoadFromBase64('generated_image.png', LBase64Data);
          ResMsg.MediaFiles.Add(LNewImageFile);
          ResMsg.Prompt := FLastContent;

          // Disparar el evento de fin de recepci�n de datos
         DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
          if Assigned(FOnReceiveDataEnd) then
            FOnReceiveDataEnd(Self, ResMsg, nil, 'model', '');

        except
          LNewImageFile.Free; // Free if something fails after creating it
          raise;
        end;
      end
      else
      begin
        FLastError := LModel + ' response OK but no image data received.';
        DoError(FLastError, nil);
      end;
    end
    else
    begin
      LErrorResponse := LResponseStream.DataString;
      FLastError := Format('Error generating image: %d, %s', [LResponse.StatusCode, LErrorResponse]);
      DoError(FLastError, nil);
    end;
  finally
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
    // LBinaryStream.Free;
    LResponseJson.Free; // ParseJSONValue crea un objeto que debemos liberar
    FBusy := False;
  end;
end;

function TAiOpenChat.InternalRunImageDalleGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl: string;
  LBodyStream, LResponseStream: TStringStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LJsonObject, LResponseJson, LImageObject: TJSonObject;
  LDataArray: TJSonArray;
  LBase64Data: string;
  // LBinaryStream: TMemoryStream;
  LNewImageFile: TAiMediaFile;
  LErrorResponse: string;
begin

  Result := ''; // The main function returns no text, the image goes in ResMsg
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  // 1. A�adir el mensaje del usuario al historial
  if FMessages.IndexOf(AskMsg) < 0 then
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  // 2. Preparar par�metros for the API de DALL-E
  LUrl := Url + 'images/generations'; // Asume que 'Url' es la URL base de OpenAI
  LJsonObject := TJSonObject.Create;
  LBodyStream := nil;
  LResponseStream := nil;
  // LBinaryStream := nil;
  LResponseJson := nil;

  try
    LJsonObject.AddPair('prompt', TJSONString.Create(AskMsg.Prompt));
    LJsonObject.AddPair('n', TJSONNumber.Create(n));
    LJsonObject.AddPair('response_format', TJSONString.Create('b64_json'));
    LJsonObject.AddPair('size', '1024x1024');

    if Model = 'dall-e-2' then
    begin
      // LJsonObject.AddPair('quality', TJSONString.Create('hd'));
      // LJsonObject.AddPair('style', TJSONString.Create('vivid')); // vivid or natural
    end
    Else if Model = 'dall-e-3' then
    begin
      // LJsonObject.AddPair('quality', TJSONString.Create('hd'));
      // LJsonObject.AddPair('style', TJSONString.Create('vivid')); // vivid or natural
    end;

    // A�adir identificador de usuario
    if not User.IsEmpty then
      LJsonObject.AddPair('user', TJSONString.Create(User));

    // 4. Ejecutar la petici�n HTTP
    LBodyStream := TStringStream.Create(LJsonObject.ToString, TEncoding.UTF8);
    LResponseStream := TStringStream.Create('', TEncoding.UTF8);

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

    // 5. Procesar la respuesta
    if LResponse.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject.ParseJSONValue(LResponseStream.DataString) as TJSonObject;
      if LResponseJson = nil then
        raise Exception.Create('Error parsing JSON response from DALL-E.');

      LDataArray := LResponseJson.GetValue<TJSonArray>('data');
      if (LDataArray <> nil) and (LDataArray.Count > 0) then
      begin
        LImageObject := LDataArray.Items[0] as TJSonObject;
        LBase64Data := LImageObject.GetValue<string>('b64_json');

        // Crear el archivo de media y adjuntarlo al mensaje de respuesta
        LNewImageFile := TAiMediaFile.Create;
        try
          // DALL-E genera im�genes en formato PNG
          LNewImageFile.LoadFromBase64('generated_image.png', LBase64Data);
          ResMsg.MediaFiles.Add(LNewImageFile);

          // Disparar el evento de fin de recepci�n de datos
          DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
          if Assigned(FOnReceiveDataEnd) then
            FOnReceiveDataEnd(Self, ResMsg, nil, 'model', '');

        except
          LNewImageFile.Free; // Free if something fails after creating it
          raise;
        end;
      end
      else
      begin
        FLastError := Model + ' response OK but no image data received.';
        DoError(FLastError, nil);
      end;
    end
    else
    begin
      LErrorResponse := LResponseStream.DataString;
      FLastError := Format('Error generating image: %d, %s', [LResponse.StatusCode, LErrorResponse]);
      DoError(FLastError, nil);
    end;
  finally
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
    // LBinaryStream.Free;
    LResponseJson.Free; // ParseJSONValue crea un objeto que debemos liberar
    FBusy := False;
  end;
end;

function TAiOpenChat.InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
begin
  Raise Exception.Create('This option has not yet been implemented for this model');
end;

function TAiOpenChat.InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
begin
  Raise Exception.Create('This option has not yet been implemented for this model, you must execute them from Responses');
end;

function TAiOpenChat.InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl, LModel, LVoice, LResponseFormat: string;
  LBodyStream: TStringStream;
  LResponseStream: TMemoryStream;
  LHeaders: TNetHeaders; // <--- Variable ya declarada, ahora la usaremos
  LResponse: IHTTPResponse;
  LJsonObject: TJSonObject;
  LErrorResponse: string;
  LNewAudioFile: TAiMediaFile;
begin
  Result := ''; // The Run function returns the text, which is empty in this case.
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  // 1. Add the user message to the history to maintain consistency
  if FMessages.IndexOf(AskMsg) < 0 then // Only add if not already in the list
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  // 2. Prepare parameters for the TTS API
  LUrl := Url + 'audio/speech';
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  // 'tts-1'; // Or you could have a specific property for the TTS model
  LVoice := TtsParams.Voice; // We use the property of the component
  LResponseFormat := TtsParams.VoiceFormat; // We use the property of the component

  // 3. Build and execute the request
  LJsonObject := TJSonObject.Create;
  LBodyStream := nil;
  LResponseStream := TMemoryStream.Create;
  try
    LJsonObject.AddPair('model', LModel);
    LJsonObject.AddPair('input', AskMsg.Prompt);
    LJsonObject.AddPair('voice', LVoice);
    LJsonObject.AddPair('response_format', LResponseFormat);

    LBodyStream := TStringStream.Create(LJsonObject.ToJson, TEncoding.UTF8);

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    LBodyStream.Position := 0;
{$IFDEF APIDEBUG}
    LBodyStream.SaveToFile('c:\temp\peticionAudio.json.txt');
    LBodyStream.Position := 0;
{$ENDIF}
    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

    // 4. Process the response
    if LResponse.StatusCode = 200 then
    begin
      // ... (the rest of the response processing code is correct)
      LNewAudioFile := TAiMediaFile.Create;
      try
        LResponseStream.Position := 0;
        LNewAudioFile.LoadFromStream('generated_audio.' + LResponseFormat, LResponseStream);
        // LResponseMsg := TAiChatMessage.Create('', 'model');

        ResMsg.MediaFiles.Add(LNewAudioFile);
        // ResMsg.Id := FMessages.Count + 1; // Run adds it when the process finishes
        // FMessages.Add(ResMsg);

        DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, nil, 'model', '');
      except
        LNewAudioFile.Free;
        raise;
      end;
    end
    else
    begin
      LResponseStream.Position := 0;
      LErrorResponse := TStreamReader.Create(LResponseStream).ReadToEnd;
      FLastError := Format('Error generating audio: %d, %s', [LResponse.StatusCode, LErrorResponse]);
      DoError(FLastError, nil);
    end;
  finally
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
  end;

  FBusy := False;
end;

function TAiOpenChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  Body: TMultipartFormData;
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  sUrl: String;
  Res: IHTTPResponse;
  LResponseStream: TMemoryStream;
  LTempStream: TMemoryStream;
  LResponseObj: TJSonObject;
  Granularities: TStringList; // to process the granularities
  I: integer;
  LModel: String;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('An audio file with content is required for transcription.');

  sUrl := Url + 'audio/transcriptions';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 35}
  Client.SynchronizeEvents := False;
{$ENDIF}
  LResponseStream := TMemoryStream.Create;
  Body := TMultipartFormData.Create;
  Granularities := TStringList.Create;

  LTempStream := TMemoryStream.Create;
  try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    // Crear un stream temporal para pasarlo al formulario multipart
    aMediaFile.Content.Position := 0;
    LTempStream.LoadFromStream(aMediaFile.Content);
    LTempStream.Position := 0;

    // --- 1. BUILDING THE MULTIPART BODY WITH GENERIC PARAMETERS ---
{$IF CompilerVersion >= 36}
    Body.AddStream('file', LTempStream, False, aMediaFile.FileName, aMediaFile.MimeType);
{$ELSE}
    Body.AddStream('file', LTempStream, aMediaFile.FileName, aMediaFile.MimeType);
{$ENDIF}
    Body.AddField('model', LModel); // Safe default

    if not AskMsg.Prompt.IsEmpty then
      Body.AddField('prompt', AskMsg.Prompt);

    // Response format (generic, as string)
    if not TranscriptionParams.ResponseFormat.IsEmpty then
      Body.AddField('response_format', TranscriptionParams.ResponseFormat)
    else
      Body.AddField('response_format', 'json'); // Default to JSON if not specified

    // Optional parameters
    if not TranscriptionParams.Language.IsEmpty then
      Body.AddField('language', TranscriptionParams.Language);

    // We use the existing Temperature property in the component
    if Self.Temperature > 0 then
      Body.AddField('temperature', FormatFloat('0.0', Self.Temperature));

    // Timestamps Granularities (we process the string)
    if not TranscriptionParams.TimestampGranularities.IsEmpty then
    begin
      // We split the string by commas
      Granularities.CommaText := TranscriptionParams.TimestampGranularities;
      for I := 0 to Granularities.Count - 1 do
      begin
        // We add each granularity as a separate field with '[]'
        Body.AddField('timestamp_granularities[]', Trim(Granularities[I]));
      end;
    end;

    { TODO : NOT YET READY TO USE TRANSCRIPTION IN ASYNCHRONOUS MODE, Pending implementation in the future }
    // Streaming
    // if Self.Asynchronous then
    // Body.AddField('stream', 'true');

    // --- 2. EXECUTION OF THE POST REQUEST ---

    // (The streaming/synchronous logic remains the same)
    { if Self.Asynchronous then
      begin
      FClient.Asynchronous := True;
      // The OnReceiveData logic will handle the rest
      FClient.Post(sUrl, Body, FResponse, Headers);
      Result := '';
      end
      else
    }
    begin
      Res := Client.Post(sUrl, Body, LResponseStream, Headers);

      if Res.StatusCode = 200 then
      begin

        LResponseObj := TJSonObject.ParseJSONValue(Res.ContentAsString) as TJSonObject;

        If Not Assigned(LResponseObj) then
        Begin
          LResponseObj := TJSonObject.Create(TJSonPair.Create('text', Res.ContentAsString));
        End;

        try
          // Here you call the transcription parsing procedure
          ParseJsonTranscript(LResponseObj, ResMsg, aMediaFile);
        finally
          LResponseObj.Free;
        end;

        Result := ResMsg.Prompt;
      end
      else
      begin
        Raise Exception.CreateFmt('Transcription error: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end;
    end;

  finally
    Body.Free;
    Client.Free;
    LResponseStream.Free;
    LTempStream.Free;
  end;
end;

function TAiOpenChat.InternalRunNativeWebSearch(ResMsg, AskMsg: TAiChatMessage): String;
Var
  // for the request
  LBodyJson: TJSonObject;
  LToolsArray: TJSonArray;
  LToolObject: TJSonObject;
  LBodyStream: TStringStream;
  LUrl: String;
  LModel: String;
  LHeaders: TNetHeaders;
  LastMessage: TAiChatMessage;

  // for the response
  LResponse: IHTTPResponse;
  LResponseJson: TJSonObject;

  // Auxiliary variables
  Res: String;
begin
  // Message verification
  if FMessages.Count = 0 then
    raise Exception.Create('No messages in history to perform a web search.');

  LastMessage := GetLastMessage;
  if not Assigned(LastMessage) then
    raise Exception.Create('Could not obtain the last message for web search.');

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  FBusy := True;
  FAbort := False;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := LastMessage.Prompt;

  LBodyJson := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);

  try
    // --- 1. BUILDING THE JSON BODY for the /v1/responses API ---

    // Parameter 'model' (required)
    LBodyJson.AddPair('model', LModel); // Must be a compatible model

    // Parameter 'input' - The 'Responses' API uses 'input' with the user prompt
    // Unlike 'messages', here only the last prompt is sent.
    // This API is more "stateless" (stateless) for the conversation.
    LBodyJson.AddPair('input', LastMessage.Prompt);

    // Parameter 'tools' - Here we enable web search
    LToolsArray := TJSonArray.Create;
    LToolObject := TJSonObject.Create;
    // According to your example, the type for this API is 'web_search_preview'
    LToolObject.AddPair('type', 'web_search_preview');
    LToolsArray.Add(LToolObject);
    LBodyJson.AddPair('tools', LToolsArray);

    // Generation control parameters (if the API supports them, the /v1/responses documentation must be checked)
    // We assume it supports the most common ones.
    // LBodyJson.AddPair('temperature', TJSONNumber.Create(Temperature));
    // LBodyJson.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));

    // The 'responses' API may not support streaming. We assume it does not for now.
    // If it supported it, it would be added here: LBodyJson.AddPair('stream', TJSONBool.Create(True));

    // Convert the JSON to a string and prepare it for sending

    Res := UTF8ToString(UTF8Encode(LBodyJson.ToJson));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Res := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
    LBodyStream.WriteString(Res);
    LBodyStream.Position := 0;

    // Save for debugging (optional)
{$IFDEF APIDEBUG}
    LBodyStream.SaveToFile('c:\temp\peticion_responses_websearch.json.txt');
    LBodyStream.Position := 0;
{$ENDIF}
    // --- 2. EXECUTION OF THE HTTP REQUEST TO THE CORRECT ENDPOINT ---
    LUrl := Url + 'responses'; // <<< POINTING TO THE NEW ENDPOINT
    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    FResponse.Clear;
    FResponse.Position := 0;

    LResponse := FClient.Post(LUrl, LBodyStream, FResponse, LHeaders);

    // --- 3. PROCESSING THE RESPONSE ---
    FLastContent := '';

    FResponse.Position := 0;
{$IFDEF APIDEBUG}
    FResponse.SaveToFile('c:\temp\respuesta_responses_websearch.json.txt');
{$ENDIF}
    // We assume that the response from this endpoint is not streamed (synchronous)
    if LResponse.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject(TJSonObject.ParseJSONValue(LResponse.ContentAsString));
      try
        FBusy := False;
        ParseResponse(LResponseJson, ResMsg);
        Result := FLastContent;
      finally
        FreeAndNil(LResponseJson);
      end;
    end
    else
    begin
      FBusy := False;
      Raise Exception.CreateFmt('Error from the /v1/responses endpoint: %d, %s', [LResponse.StatusCode, LResponse.ContentAsString]);
    end;

  finally
    // Free all created resources
    LBodyJson.Free;
    LBodyStream.Free;
  end;
end;

constructor TAiOpenChat.Create(Sender: TComponent);
begin
  inherited;

  ApiKey := '@OPENAI_API_KEY';
  Model := 'gpt4-o';
  n := 1;
  Response_format := TAiChatResponseFormat.tiaChatRfText;
  Temperature := 1;
  User := 'user';
  InitialInstructions.Text := 'You are a very helpful and friendly assistant';
  Max_tokens := 300;
  Url := GlOpenAIUrl;
  Top_p := 1;
  ResponseTimeOut := 60000;
  Voice := 'alloy';
  voice_format := 'mp3';
  FStore := False; // do not store info for distillation or evaluation models
  FParallel_ToolCalls := True; // By default performs parallel calls; this saves time in responses
  FService_Tier := 'auto'; // possible values auto and default  see API documentation.
end;

destructor TAiOpenChat.Destroy;
begin
  inherited;
end;

procedure TAiOpenChat.DoCallFunction(ToolCall: TAiToolsFunction);
// Var
// LFuncion: TFunctionActionItem;
// Handle: Boolean;
begin
  If Not Assigned(AiFunctions) then
    Exit;

  If AiFunctions.DoCallFunction(ToolCall) then
  Begin
    // If it executed the function
  End
  Else
  Begin
    If Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall)
  End;
end;

function TAiOpenChat.ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions;
Var
  jObj, Msg, jFunc, Arg: TJSonObject;
  JVal, JVal1: TJSonValue;
  Fun: TAiToolsFunction;
  JToolCalls: TJSonArray;
  Nom, Valor: String;
  I: integer;
begin
  Result := TAiToolsFunctions.Create;

  For JVal1 in jChoices do
  Begin
    Msg := TJSonObject(JVal1).GetValue<TJSonObject>('message');

    If Msg.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
    Begin
      For JVal in JToolCalls do
      Begin
        jObj := TJSonObject(JVal);
        If jObj.GetValue<String>('type') = 'function' then
        Begin
          jObj := TJSonObject(JVal);
          Fun := TAiToolsFunction.Create;
          Fun.Id := jObj.GetValue<String>('id');
          Fun.&Type := jObj.GetValue<String>('type');

          If jObj.TryGetValue<TJSonObject>('function', jFunc) then
          Begin
            // Fun.Name := jObj.GetValue<TJSonObject>('function').GetValue<String>('name');
            Fun.Name := jFunc.GetValue<String>('name');

            Fun.Arguments := jObj.GetValue<TJSonObject>('function').GetValue<String>('arguments');
          End;

          Try
            If (Fun.Arguments <> '') and (Fun.Arguments <> '{}') then
            Begin
              Arg := TJSonObject(TJSonObject.ParseJSONValue(Fun.Arguments));
              If Assigned(Arg) then
              Begin
                For I := 0 to Arg.Count - 1 do
                Begin
                  Nom := Arg.Pairs[I].JsonString.Value;
                  Valor := Arg.Pairs[I].JsonValue.Value;
                End;
              End;
            End;

          Except
            // If there are no parameters it does not raise an error
          End;

          Result.Add(Fun.Id, Fun);
        End;
      End;
    End;
  End;
end;

class function TAiOpenChat.GetModels(aApiKey, aUrl: String): TStringList;
Var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  Res: IHTTPResponse;
  Response: TStringStream;
  sUrl, EndPointUrl: String;
  jRes: TJSonObject;
  JArr: TJSonArray;
  JVal: TJSonValue;
  sModel: string;
  CustomModels: TArray<string>;
  I: integer;
begin
  Result := TStringList.Create;

  If aUrl <> '' then
    EndPointUrl := aUrl
  Else
    EndPointUrl := GlOpenAIUrl;

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 35}
  Client.SynchronizeEvents := False;
{$ENDIF}
  Response := TStringStream.Create('', TEncoding.UTF8);
  sUrl := EndPointUrl + 'models';

  Try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + aApiKey)];
    Client.ContentType := 'application/json';

    Res := Client.Get(sUrl, Response, Headers);

    if Res.StatusCode = 200 then
    Begin
      jRes := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
      If jRes.TryGetValue<TJSonArray>('data', JArr) then
      Begin
        For JVal in JArr do
        Begin
          sModel := JVal.GetValue<String>('id');
          If sModel <> '' then
            Result.Add(sModel);
        End;
      End;

      // Add custom models
      CustomModels := TAiChatFactory.Instance.GetCustomModels(Self.GetDriverName);

      for I := Low(CustomModels) to High(CustomModels) do
      begin
{$IF CompilerVersion <= 35.0}
        if Result.IndexOf(CustomModels[I]) = -1 then
          Result.Add(CustomModels[I]);
{$ELSE}
        if not Result.Contains(CustomModels[I]) then
          Result.Add(CustomModels[I]);
{$ENDIF}
      end;
    End
    else
    begin
      Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;
  Finally
    Client.Free;
    Response.Free;
  End;
end;

function TAiOpenChat.GetModels: TStringList;
begin
  Result := GetModels(ApiKey, Url);
end;

function TAiOpenChat.GetTools(aToolFormat: TToolFormat): TStrings;
begin
  If Assigned(AiFunctions) and Tool_Active then // If it uses tools functions
  Begin
    FTools.Text := AiFunctions.GetTools(aToolFormat);
    Result := FTools;
  End
  Else
  Begin
    FTools.Text := '';
    Result := FTools;
  End;
end;

function TAiOpenChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice, jAudio, jStrOptions, jResponseFormatObj: TJSonObject;
  JArr, jModalities: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: integer;
  LAsincronico: Boolean;
  Msg: TAiChatMessage;
  MediaFile: TAiMediaFile;
  ActiveFileId: String;
  Res: String;
  MessagesJson, NewContentArray: TJSonArray;
  LastMessageJson, JTextObj, JImageObj: TJSonObject;
  LModel: String;
begin
  // Initialization of variables and values by default
  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'gpt-4o'; // A good default model that handles multimodality

  // Functions and contextual audio generation usually do not work in stream mode
  LAsincronico := Self.Asynchronous; // Self.Asynchronous and (not Self.Tool_Active) and (Not(Tfc_Audio in NativeOutputFiles)) and (Not(Tfc_Image in NativeOutputFiles)) and (Not(Tfc_Video in NativeOutputFiles));

  //FClient.Asynchronous := LAsincronico;

  // We create the main objects that we will use
  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  try

    for I := FMessages.Count - 1 downto 0 do
    begin
      Msg := FMessages[I];
      if Assigned(Msg.MediaFiles) then
        for MediaFile in Msg.MediaFiles do
          if not MediaFile.IdFile.IsEmpty then // We use IdFile as an indicator
          begin
            ActiveFileId := MediaFile.IdFile;
            Break;
          end;
      if not ActiveFileId.IsEmpty then
        Break;
    end;

    MessagesJson := GetMessages;

    // If we find an active file and there are messages, we modify the last message
    if (not ActiveFileId.IsEmpty) and (MessagesJson.Count > 0) then
    begin
      LastMessageJson := MessagesJson.Items[MessagesJson.Count - 1] as TJSonObject;

      // We create a new 'content' array for the multimodal format
      NewContentArray := TJSonArray.Create;

      // 1. We add the original prompt text
      JTextObj := TJSonObject.Create;
      JTextObj.AddPair('type', 'text');
      JTextObj.AddPair('text', LastMessageJson.GetValue<string>('content'));
      NewContentArray.Add(JTextObj);

      // 2. We add the reference to the uploaded image/file
      JImageObj := TJSonObject.Create;
      JImageObj.AddPair('type', 'image_url'); // For OpenAI, even PDFs are treated as 'image_url' with a file_id
      JImageObj.AddPair('image_url', TJSonObject.Create.AddPair('url', 'data:file_id:' + ActiveFileId));
      NewContentArray.Add(JImageObj);

      // We replace the old 'content' (string) with the new 'content' (array)
      LastMessageJson.RemovePair('content');
      LastMessageJson.AddPair('content', NewContentArray);
    end;

    // --- 1. BASIC REQUEST PARAMETERS ---
    AJSONObject.AddPair('model', LModel);
    AJSONObject.AddPair('messages', MessagesJson);
    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    // Streaming options if active
    if (LAsincronico = True) and (Stream_Usage = True) then
    begin
      jStrOptions := TJSonObject.Create;
      jStrOptions.AddPair('include_usage', Stream_Usage);
      AJSONObject.AddPair('stream_options', jStrOptions);
    end;

    // --- 2. TOOL CONFIGURATION (FUNCTION CALLING) ---
    if Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAI).Text) <> '') then
    begin
      try

{$IF CompilerVersion < 35}
        JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAI).Text);
{$ELSE}
        JArr := TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAI).Text) as TJSonArray;
{$ENDIF}
        if not Assigned(JArr) then
          Raise Exception.Create('The Tools property has an invalid JSON format.')
        else
        begin
          AJSONObject.AddPair('tools', JArr);
          AJSONObject.AddPair('parallel_tool_calls', FParallel_ToolCalls);

          if (Trim(Tool_choice) <> '') then
          begin
            // We assume that Tool_choice can be a string 'auto', 'none', or a JSON object
            try
              jToolChoice := TJSonObject.ParseJSONValue(Tool_choice) as TJSonObject;
              AJSONObject.AddPair('tool_choice', jToolChoice);
            except
              // If it is not a JSON object, we treat it as a simple string
              AJSONObject.AddPair('tool_choice', Tool_choice);
            end;
          end;
        end;
      except
        on E: Exception do
          Raise Exception.Create('Error processing the Tools property: ' + E.Message);
      end;
    end;

    // --- 3. GENERATION AND MODALITIES CONFIGURATION ---

    if ModelConfig.ThinkingLevel <> tlDefault then // OpenAI reasoning support
    begin
      AJSONObject.AddPair('max_completion_tokens', TJSONNumber.Create(Max_tokens));
    end
    else
    begin
      AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));
    end;

    AJSONObject.AddPair('user', User);
    AJSONObject.AddPair('store', FStore); // For evaluation models

    // --- KEY LOGIC: DETERMINE THE RESPONSE TYPE ---
    if (cap_GenAudio in ModelConfig.SessionCaps) then
    begin
      // Scenario: Chat with CONTEXTUAL AUDIO response
      jModalities := TJSonArray.Create;
      jModalities.Add('text');
      jModalities.Add('audio');
      AJSONObject.AddPair('modalities', jModalities);

      jAudio := TJSonObject.Create;
      jAudio.AddPair('voice', Voice);
      jAudio.AddPair('format', voice_format);
      AJSONObject.AddPair('audio', jAudio);
    end
    else if cap_Image in ModelConfig.ModelCaps then // Adds image parameters
    Begin
      AJSONObject.AddPair('size', '1024x1024');
      var
      LToolsArray := TJSonArray.Create;
      var
      LToolObject := TJSonObject.Create;

      LToolObject.AddPair('type', 'image_generation');
      LToolsArray.Add(LToolObject);
      AJSONObject.AddPair('tools', LToolsArray);

    End
    Else
    begin
      // Scenario: TEXT-only or JSON-only chat
      jResponseFormatObj := TJSonObject.Create;
      case FResponse_format of
        tiaChatRfJson:
          jResponseFormatObj.AddPair('type', 'json_object');
        tiaChatRfJsonSchema:
          jResponseFormatObj.AddPair('type', 'json_schema');
      else // tiaChatRfText and By default
        jResponseFormatObj.AddPair('type', 'text');
      end;
      AJSONObject.AddPair('response_format', jResponseFormatObj);
    end;

    // --- 4. ADDITIONAL PARAMETERS ---
    // Stop sequences
    Lista.CommaText := Stop;
    if Lista.Count > 0 then
    begin
      JStop := TJSonArray.Create;
      for I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    end;

    // Logprobs configuration
    if Logprobs = True then
    begin
      AJSONObject.AddPair('logprobs', TJSONBool.Create(Logprobs));
      if Logit_bias <> '' then
        AJSONObject.AddPair('logit_bias', TJSONNumber.Create(Logit_bias));
      if Top_logprobs <> '' then
        AJSONObject.AddPair('top_logprobs', TJSONNumber.Create(Top_logprobs));
    end;

    // Seed for reproducibility
    if Seed > 0 then
      AJSONObject.AddPair('seed', TJSONNumber.Create(Seed));

    if cap_WebSearch in ModelConfig.ModelCaps then
    begin
      // The OpenAI API expects an object for the options, even if it is empty.
      Var
      jWebSearchOptions := TJSonObject.Create;
      AJSONObject.AddPair('web_search_options', jWebSearchOptions);
    end
    Else
    Begin
      if Top_p <> 0 then
        AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

      AJSONObject.AddPair('temperature', TJSONNumber.Create(Temperature));
      AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Frequency_penalty));
      AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Presence_penalty));
      AJSONObject.AddPair('n', TJSONNumber.Create(n));

    End;

    // --- 5. FINALIZATION AND RETURN ---
    // We get the final JSON string. We use ToString, which returns UTF8String
    // and then we convert it to a Delphi String (Unicode).
    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJson));

// Optional: clean the JSON for some cases (like backslashes)
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);

  finally
    // Memory release to avoid leaks
    AJSONObject.Free;
    Lista.Free;
  end;
end;

procedure AppendTextToFile(const FilePath, TextToAppend: string);
var
  LogFile: TextFile;
begin
  // We assign the file
  AssignFile(LogFile, FilePath);

  try
    // We open the file in "append" mode to add at the end
    if FileExists(FilePath) then
      Append(LogFile) // We open in "append" mode
    else
      Rewrite(LogFile); // We create the file if it does not exist

    // We write the text at the end of the file
    WriteLn(LogFile, TextToAppend);
  finally
    // We close the file
    CloseFile(LogFile);
  end;
end;

procedure TAiOpenChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
Var
  jObj, Delta: TJSonObject;
  JToolCalls: TJSonArray;
  sJson, Value, Role1: String;
  P: integer;

  // Variables for handling Tools (Function Calling) in Stream
  JToolCall, jFunc: TJSonValue;
  ToolIndex: integer;
  BufferObj, BufferFunc: TJSonObject;

  // Variables for reconstruction and End of Stream
  Msg: TAiChatMessage;
  CombinedTools: TJSonArray;
  Key: integer;
  sToolCallsStr: String;
  SortedKeys: TList<integer>;

  // Variables for automatic invocation logic (Fake JSON)
  FakeResponseObj: TJSonObject;
  FakeChoice: TJSonObject;
  FakeMsg: TJSonObject;
  FakeChoicesArr: TJSonArray;
  FakeUsage: TJSonObject;
  TempMsg: TAiChatMessage;

  // Variables for compatibility
  ChoicesArray: TJSonArray;
  FirstChoice: TJSonObject;
begin
//  LogDebug('--OnInternalReceiveData (OpenAI)--');
//  LogDebug('    ' + FResponse.DataString);

  // If it is not asynchronous, we exit. Synchronous logic is handled in InternalRunCompletions.
  If FClient.Asynchronous = False then
    Exit;

  AAbort := FAbort;

  // Abort handling
  If FAbort = True then
  Begin
    FBusy := False;
    FTmpToolCallBuffer.Clear; // Clear buffer if aborted
    If Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, Nil, Nil, 'system', 'abort');
    Exit;
  End;

  Try
    // Accumulate data in the text buffer
    FTmpResponseText := FTmpResponseText + FResponse.DataString;
    FResponse.Clear;
    FResponse.Position := 0;

    // Prefix cleanup if they were cut off previously
    If Copy(FTmpResponseText, 1, 5) = 'data:' then
      FTmpResponseText := Copy(FTmpResponseText, 6, Length(FTmpResponseText));

    // Loop to process each "data: {...}" line
    Repeat
      P := Pos('data:', FTmpResponseText);
      If P > 0 then
      Begin
        sJson := Trim(Copy(FTmpResponseText, 1, P - 1));
        FTmpResponseText := Copy(FTmpResponseText, P + 6, Length(FTmpResponseText));
      End
      Else
      Begin
        If Trim(FTmpResponseText) = '[DONE]' then
        Begin
          sJson := Trim(FTmpResponseText);
          FTmpResponseText := '';
        End
        Else
          sJson := ''; // Wait for more data
      End;

      // =======================================================================
      // [DONE] - END OF STREAM
      // Here we reconstruct everything and trigger automatic execution
      // =======================================================================
      If sJson = '[DONE]' then
      Begin
        sJson := '';
        sToolCallsStr := '';

        // 1. TOOL RECONSTRUCTION (Buffer to JSON String)
        if FTmpToolCallBuffer.Count > 0 then
        begin
          CombinedTools := TJSonArray.Create;
          try
            SortedKeys := TList<integer>.Create;
            try
              for Key in FTmpToolCallBuffer.Keys do
                SortedKeys.Add(Key);
              SortedKeys.Sort;

              for Key in SortedKeys do
              begin
                CombinedTools.Add(FTmpToolCallBuffer[Key].Clone as TJSonObject);
                FTmpToolCallBuffer[Key].Free;
              end;
            finally
              SortedKeys.Free;
            end;
            sToolCallsStr := CombinedTools.ToJson;
          finally
            CombinedTools.Free;
            FTmpToolCallBuffer.Clear;
          end;
        end;

        // 2. SYNTHETIC RESPONSE CONSTRUCTION (Fake JSON)
        // We create a JSON object identical to a synchronous response to pass it to ParseChat.
        FakeResponseObj := TJSonObject.Create;
        try
          FakeResponseObj.AddPair('id', 'stream-' + IntToStr(TThread.GetTickCount));
          FakeResponseObj.AddPair('model', Model);

          // Fake usage (necessary to avoid Access Violation in ParseChat)
          FakeUsage := TJSonObject.Create;
          FakeUsage.AddPair('prompt_tokens', TJSONNumber.Create(0));
          FakeUsage.AddPair('completion_tokens', TJSONNumber.Create(0));
          FakeUsage.AddPair('total_tokens', TJSONNumber.Create(0));
          FakeResponseObj.AddPair('usage', FakeUsage);

          // Structure choices[0].message
          FakeChoicesArr := TJSonArray.Create;
          FakeChoice := TJSonObject.Create;
          FakeMsg := TJSonObject.Create;

          FakeMsg.AddPair('role', FTmpRole); // Usually 'assistant'

          // If there is accumulated text content
          if FLastContent <> '' then
            FakeMsg.AddPair('content', FLastContent);

          // If there were reconstructed tools, we inject them
          if sToolCallsStr <> '' then
            FakeMsg.AddPair('tool_calls', TJSonArray(TJSonObject.ParseJSONValue(sToolCallsStr)));

          FakeChoice.AddPair('message', FakeMsg);
          FakeChoice.AddPair('finish_reason', 'stop');

          FakeChoicesArr.Add(FakeChoice);
          FakeResponseObj.AddPair('choices', FakeChoicesArr);

          // 3. CALL TO PARSECHAT
          // ParseChat will handle:
          // A) If it is a Tool Call: Execute DoCallFunction -> Add result -> Call Run() again automatically.
          // B) If it is Text: Simply process it and populate TempMsg.
          TempMsg := TAiChatMessage.Create('', FTmpRole);
          try
            ParseChat(FakeResponseObj, TempMsg);

            // 4. FINAL RESULT MANAGEMENT
            if sToolCallsStr = '' then
            begin
              // TEXT CASE: ParseChat filled TempMsg but does not add it to the list automatically.
              // We do it here.
              TempMsg.Id := FMessages.Count + 1;
              FMessages.Add(TempMsg);

              DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
              if Assigned(FOnReceiveDataEnd) then
                FOnReceiveDataEnd(Self, TempMsg, Nil, FTmpRole, FLastContent);

              TempMsg := nil; // Evitar Double Free (ahora pertenece a FMessages)
            end
            else
            begin
              // TOOL CALL CASE:
              // ParseChat already did all the work (create message, execute function, call Run).
              // We only notify the end of this reception cycle.
               DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
              if Assigned(FOnReceiveDataEnd) then
                FOnReceiveDataEnd(Self, GetLastMessage, Nil, FTmpRole, '');
            end;

          finally
            if Assigned(TempMsg) then
              TempMsg.Free;
          end;

        finally
          FakeResponseObj.Free;
        end;

        FBusy := False;
      End
      // =======================================================================
      // CHUNK PROCESSING (Partial data)
      // =======================================================================
      Else If sJson <> '' then
      Begin
        jObj := TJSonObject(TJSonObject.ParseJSONValue(sJson));
        Try
          If Assigned(jObj) then
          Begin
            Delta := nil;

            // Safe Delta extraction compatible with old and new versions
            ChoicesArray := jObj.GetValue<TJSonArray>('choices');
            if Assigned(ChoicesArray) and (ChoicesArray.Count > 0) then
            begin
{$IF CompilerVersion >= 35}
              Delta := ChoicesArray.Items[0].GetValue<TJSonObject>('delta');
{$ELSE}
              FirstChoice := ChoicesArray.GetItemAsObject(0);
              if Assigned(FirstChoice) then
                Delta := FirstChoice.GetValueAsObject('delta');
{$ENDIF}
            end;

            if Assigned(Delta) then
            begin
              // 1. ROLE HANDLING
              if Delta.TryGetValue<String>('role', Role1) then
                FTmpRole := Role1;

              // 2. CONTENT HANDLING (TEXT)
              Value := '';
              // Note: GetValue can return nil or TJSONNull; we check both cases
              if (Delta.GetValue('content') <> nil) and not(Delta.GetValue('content') is TJSONNull) then
              begin
                Value := Delta.GetValue<String>('content');
                FLastContent := FLastContent + Value;

                // Trigger data received event (typing effect)
                If (Value <> '') and Assigned(FOnReceiveDataEvent) then
                Begin
                  Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
                  FOnReceiveDataEvent(Self, Nil, jObj, FTmpRole, Value);
                End;
              end;

              // 3. TOOL HANDLING (FUNCTION CALLING) - ACCUMULATION
              if Delta.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
              begin
                for JToolCall in JToolCalls do
                begin
                  if JToolCall is TJSonObject then
                  begin
                    var
                    JTC := TJSonObject(JToolCall);

                    // We get the index
                    if JTC.TryGetValue<integer>('index', ToolIndex) then
                    begin
                      // Ensure Buffer
                      if not FTmpToolCallBuffer.TryGetValue(ToolIndex, BufferObj) then
                      begin
                        BufferObj := TJSonObject.Create;
                        FTmpToolCallBuffer.Add(ToolIndex, BufferObj);
                      end;

                      // ID and Type (Avoid duplicates: only add if they do not exist)
                      if JTC.TryGetValue<String>('id', Value) then
                        if BufferObj.GetValue('id') = nil then
                          BufferObj.AddPair('id', Value);

                      if JTC.TryGetValue<String>('type', Value) then
                        if BufferObj.GetValue('type') = nil then
                          BufferObj.AddPair('type', Value);

                      // Function data
                      if JTC.TryGetValue<TJSonObject>('function', TJSonObject(jFunc)) then
                      begin
                        if not BufferObj.TryGetValue<TJSonObject>('function', BufferFunc) then
                        begin
                          BufferFunc := TJSonObject.Create;
                          BufferObj.AddPair('function', BufferFunc);
                        end;

                        // Name (Concatenation)
                        if jFunc.TryGetValue<String>('name', Value) then
                        begin
                          var
                            OldName: string := '';
                          if BufferFunc.TryGetValue<String>('name', OldName) then
                            BufferFunc.RemovePair('name');
                          BufferFunc.AddPair('name', OldName + Value);
                        end;

                        // Arguments (Concatenation)
                        if jFunc.TryGetValue<String>('arguments', Value) then
                        begin
                          var
                            OldArgs: string := '';
                          if BufferFunc.TryGetValue<String>('arguments', OldArgs) then
                            BufferFunc.RemovePair('arguments');
                          BufferFunc.AddPair('arguments', OldArgs + Value);
                        end;
                      end;
                    end;
                  end;
                end;
              end; // End Tool Calls

            end; // End Assigned Delta
          End;
        Finally
          jObj.Free;
        End;
      End;

    Until sJson = '';

  Except
    // Silent handling of parsing errors during the stream
  End;
end;

procedure TAiOpenChat.ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage);
var
  // JSON parsing
  choices, JToolCalls: TJSonArray;
  JItem, jMessage, uso, jAudio: TJSonObject;
  JVal: TJSonValue;

  // Message data
  Role, Respuesta, sRes, sToolCalls: String;
  idAudio, AudioBase64, AudioTranscript: String;
  AudioExpiresAt: integer;

  // Tokens
  aPrompt_tokens, aCompletion_tokens, aTotal_tokens: integer;

  // Framework objects
  ToolMsg, AskMsg: TAiChatMessage; // ResMsg is the result message, AskMsg is the user message with the request
  MediaFile: TAiMediaFile;
  LFunciones: TAiToolsFunctions;
  ToolCall: TAiToolsFunction;

  // Tasks for Function Calling
  TaskList: array of ITask;
  I, NumTasks: integer;
  Clave: String;

  jWebSearch, jAnnotationItem: TJSonObject;
  jAnnotationItemValue: TJSonValue;
  jAnnotations: TJSonArray;
  LItem: TAiWebSearchItem;
  LModel: String;

  Code: TMarkdownCodeExtractor;
  CodeFile: TCodeFile;
  CodeFiles: TCodeFileList;
  MF: TAiMediaFile;
  St: TStringStream;

begin
  AskMsg := GetLastMessage; // Gets the request message

  // --- 1. METADATA AND TOKEN EXTRACTION ---
  LModel := jObj.GetValue<string>('model');

  // El objeto 'usage' puede no venir en respuestas con errores
  if jObj.TryGetValue<TJSonObject>('usage', uso) then
  begin
    aPrompt_tokens := uso.GetValue<integer>('prompt_tokens');
    aCompletion_tokens := uso.GetValue<integer>('completion_tokens');
    aTotal_tokens := uso.GetValue<integer>('total_tokens');
  end
  else
  begin
    aPrompt_tokens := 0;
    aCompletion_tokens := 0;
    aTotal_tokens := 0;
  end;

  // --- 2. PROCESSING THE 'CHOICES' (RESPONSES) ---
  if not jObj.TryGetValue<TJSonArray>('choices', choices) or (choices.Count = 0) then
  begin
    // If there are no 'choices', there is nothing to process.
    FLastError := 'API response contains no "choice".';
    DoError(FLastError, nil);
    FBusy := False;
    Exit;
  end;

  // We create the message that will represent the assistant's response.
  // It will be populated as we analyze the JSON.
  // Msg := TAiChatMessage.Create('', ''); //Is created in Run
  try
    // Normally we only process the first 'choice' (index 0), but a loop is more robust.
    for JVal in choices do
    begin
      JItem := JVal as TJSonObject;
      if not JItem.TryGetValue<TJSonObject>('message', jMessage) then
        Continue; // Ir a la siguiente 'choice' si esta no tiene un mensaje

      // --- 2.1. Extract message components ---
      Role := jMessage.GetValue<string>('role');
      Respuesta := '';
      sToolCalls := '';

      // First, we check if there is text content.
      if jMessage.TryGetValue<string>('content', sRes) then
        Respuesta := Respuesta + sRes;

      // Second, we check if there is audio content.
      if jMessage.TryGetValue<TJSonObject>('audio', jAudio) then
      begin
        AudioBase64 := '';
        AudioTranscript := ''; // Inicializamos

        jAudio.TryGetValue<string>('id', idAudio);
        jAudio.TryGetValue<string>('data', AudioBase64);
        jAudio.TryGetValue<integer>('expires_at', AudioExpiresAt);
        jAudio.TryGetValue<string>('transcript', AudioTranscript);

        // If there is audio data, we create a MediaFile and attach it.
        if not AudioBase64.IsEmpty then
        begin
          MediaFile := TAiMediaFile.Create;
          MediaFile.LoadFromBase64('response_audio.' + voice_format, AudioBase64);
          MediaFile.Transcription := AudioTranscript;
          MediaFile.idAudio := idAudio;
          ResMsg.AddMediaFile(MediaFile);
        end;

        // If there is a transcription, we use it as (or add it to) the text response.
        if not AudioTranscript.IsEmpty then
        begin
          if not Respuesta.IsEmpty then
            Respuesta := Respuesta + sLineBreak; // Add separator if text already exists
          Respuesta := Respuesta + AudioTranscript;
        end;
      end;

      // Third, we check if there are function calls.
      if jMessage.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
        sToolCalls := JToolCalls.ToJson; // Guardamos el JSON de las tool_calls

      if jMessage.TryGetValue<TJSonObject>('web_search', jWebSearch) then
      begin
        // The WebSearchResponse object is already created in the TAiChatMessage constructor
        if Assigned(ResMsg.WebSearchResponse) then
        begin
          // We populate the main data of the search object
          jWebSearch.TryGetValue<string>('type', ResMsg.WebSearchResponse.&type);
          jWebSearch.TryGetValue<string>('text', ResMsg.WebSearchResponse.Text);

          // Now, we process the annotations (the found links)
          if jWebSearch.TryGetValue<TJSonArray>('annotations', jAnnotations) then
          begin
            ResMsg.WebSearchResponse.annotations.Clear; // We clear it just in case
            for jAnnotationItemValue in jAnnotations do
            begin
              if not(jAnnotationItemValue is TJSonObject) then
                Continue;

              jAnnotationItem := jAnnotationItemValue as TJSonObject;
              LItem := TAiWebSearchItem.Create;
              try
                jAnnotationItem.TryGetValue<string>('type', LItem.&type);
                jAnnotationItem.TryGetValue<integer>('start_index', LItem.start_index);
                jAnnotationItem.TryGetValue<integer>('end_index', LItem.end_index);
                jAnnotationItem.TryGetValue<string>('url', LItem.Url);
                jAnnotationItem.TryGetValue<string>('title', LItem.title);
                ResMsg.WebSearchResponse.annotations.Add(LItem);
              except
                LItem.Free; // Free memory if there is an error populating the item
                raise;
              end;
            end;
          end;
        end;
      end;

    end;

    // --- 3. RESPONSE MESSAGE CONSTRUCTION AND STORAGE ---
    Respuesta := Trim(Respuesta);

    // We update the global token counters of the component.
    Self.Prompt_tokens := Self.Prompt_tokens + aPrompt_tokens;
    Self.Completion_tokens := Self.Completion_tokens + aCompletion_tokens;
    Self.Total_tokens := Self.Total_tokens + aTotal_tokens;
    Self.FLastContent := Respuesta;

    if sToolCalls.IsEmpty then // If it is a normal response, add the data to ResMsg
    Begin
      ResMsg.Role := Role;
      ResMsg.Tool_calls := sToolCalls;
      ResMsg.Model := LModel;
      ResMsg.Prompt := ResMsg.Prompt + Respuesta;
      ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aPrompt_tokens;
      ResMsg.Completion_tokens := ResMsg.Completion_tokens + aCompletion_tokens;
      ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;
      DoProcessResponse(AskMsg, ResMsg, Respuesta);
    End
    Else // If it has a tool call, it adds it and runs again to obtain the response
    Begin
      Var
      Msg := TAiChatMessage.Create(Respuesta, Role);
      Msg.Tool_calls := sToolCalls;
      Msg.Id := FMessages.Count + 1;
      FMessages.Add(Msg);
    End;

    // --- 4. FUNCTION CALLING HANDLING ---
    LFunciones := ExtractToolCallFromJson(choices);
    try
      if (LFunciones <> nil) and (LFunciones.Count > 0) then
      begin
        // The model wants to call one or more functions.
        NumTasks := LFunciones.Count;
        SetLength(TaskList, NumTasks);
        I := 0;

        // We create and start a task for each function call.
        for Clave in LFunciones.Keys do
        begin
          ToolCall := LFunciones[Clave];
          ToolCall.ResMsg := ResMsg;
          ToolCall.AskMsg := AskMsg;

          TaskList[I] := TTask.Create(
            procedure
            begin
              try
                DoCallFunction(ToolCall);
              except
                on E: Exception do
                  TThread.Queue(nil,
                    procedure
                    begin
                      DoError('Error executing the function "' + ToolCall.Name + '"', E);
                    end);
              end;
            end);
          TaskList[I].Start;
          Inc(I);
        end;

        // We wait for all functions to finish.
        TTask.WaitForAll(TaskList);

        // We create the 'tool' type response messages.
        for Clave in LFunciones.Keys do
        begin
          ToolCall := LFunciones[Clave];
          ToolMsg := TAiChatMessage.Create(ToolCall.Response, 'tool', ToolCall.Id, ToolCall.Name);
          ToolMsg.Id := FMessages.Count + 1;
          FMessages.Add(ToolMsg);
        end;

        // We call the API again so that it processes the results of the functions.
        Self.Run(Nil, ResMsg);
      end
      else
      begin
        // If there are no function calls, the conversation ends here.

        // Allow the end user to process or modify the response before saving it.
        // The request message and the response message plus the model response as text are passed

        If cap_ExtractCode in ModelConfig.SessionCaps then
        Begin
          Code := TMarkdownCodeExtractor.Create;
          Try

            CodeFiles := Code.ExtractCodeFiles(Respuesta);
            For CodeFile in CodeFiles do
            Begin
              St := TStringStream.Create(CodeFile.Code);
              Try
                St.Position := 0;

                MF := TAiMediaFile.Create;
                MF.LoadFromStream('file.' + CodeFile.FileType, St);
                ResMsg.MediaFiles.Add(MF);
              Finally
                St.Free;
              End;

            End;
          Finally
            Code.Free;
          End;
        End;

        DoProcessResponse(AskMsg, ResMsg, Respuesta);

        ResMsg.Prompt := Respuesta;

        FBusy := False;
        DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
        if Assigned(FOnReceiveDataEnd) then
        Begin
          FOnReceiveDataEnd(Self, ResMsg, jObj, Role, Respuesta);
        End;
      end;
    finally
      if Assigned(LFunciones) then
        LFunciones.Free;
    end;

  except
    // If any exception occurred during the process, we free the message
    // that we were creating to avoid memory leaks.
    // if Assigned(Msg) then
    // Msg.Free;
    // We mark as not busy and re-raise the exception.
    FBusy := False;
    raise;
  end;
end;

procedure TAiOpenChat.ParseJsonTranscript(jObj: TJSonObject; ResMsg: TAiChatMessage; aMediaFile: TAiMediaFile);
var
  // JSON parsing
  jUsage, jInputTokenDetails: TJSonObject;
  jArrWords, jArrSegments: TJSonArray;

  // Extracted data
  sTextoTranscrito, sTextoWords, sTextoSegments: String;
  aTotal_tokens, aInput_tokens, aOutput_tokens: integer;
  aText_tokens, aAudio_tokens: integer; // Detailed input tokens

begin
  sTextoTranscrito := '';
  aTotal_tokens := 0;
  aInput_tokens := 0;
  aOutput_tokens := 0;
  aText_tokens := 0;
  aAudio_tokens := 0;

  if not jObj.TryGetValue<string>('text', sTextoTranscrito) then
  begin
    FLastError := 'The API response does not contain the "text" field with the transcription.';
    DoError(FLastError, nil);
    FBusy := False; // Assuming you use FBusy as in ParseChat
    Exit;
  end;

  If jObj.TryGetValue<TJSonArray>('words', jArrWords) then
    sTextoWords := jArrWords.Format;

  If jObj.TryGetValue<TJSonArray>('segments', jArrSegments) then
    sTextoSegments := jArrSegments.Format;

  // --- 3. USAGE DATA EXTRACTION (TOKENS) ---
  // The 'usage' object may not be present, so we handle it safely.
  if jObj.TryGetValue<TJSonObject>('usage', jUsage) then
  begin
    // We extract the main tokens
    jUsage.TryGetValue<integer>('total_tokens', aTotal_tokens);
    jUsage.TryGetValue<integer>('input_tokens', aInput_tokens); // Cost of audio (and prompt if any)
    jUsage.TryGetValue<integer>('output_tokens', aOutput_tokens); // Cost of generated text

    // We extract the input token details (sub-object)
    // This tells us how many tokens corresponded to audio and how many to a possible text prompt.
    if jUsage.TryGetValue<TJSonObject>('input_token_details', jInputTokenDetails) then
    begin
      jInputTokenDetails.TryGetValue<integer>('text_tokens', aText_tokens);
      jInputTokenDetails.TryGetValue<integer>('audio_tokens', aAudio_tokens);
    end;
  end;

  // --- 4. UPDATE OF THE COMPONENT STATE ---
  // We update the global token counters, adding those from this call.
  Self.Total_tokens := Self.Total_tokens + aTotal_tokens;
  Self.Prompt_tokens := Self.Prompt_tokens + aInput_tokens; // 'input' is equivalent to 'prompt'
  Self.Completion_tokens := Self.Completion_tokens + aOutput_tokens; // 'output' is equivalent to 'completion'

  // We save the main result
  // Self.FLastContent := sTextoTranscrito;

  If Trim(sTextoWords + sLineBreak + sTextoSegments) <> '' then
  Begin
    aMediaFile.Transcription := Trim(sTextoWords + sLineBreak + sTextoSegments);
    aMediaFile.Detail := Trim(sTextoTranscrito);
    ResMsg.Prompt := Trim(ResMsg.Prompt + aMediaFile.Transcription);
  End
  Else
  Begin
    aMediaFile.Transcription := sTextoTranscrito;
    ResMsg.Prompt := Trim(ResMsg.Prompt + sLineBreak + sTextoTranscrito);
  End;

  ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aInput_tokens;
  ResMsg.Completion_tokens := ResMsg.Completion_tokens + aOutput_tokens;
  ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;
  ResMsg.Model := Self.Model; // It is assigned the same as the call since it does not return a different model
end;

procedure TAiOpenChat.ParseResponse(jObj: TJSonObject; ResMsg: TAiChatMessage);
var
  S, ResponseId, ImageBase64, RevisedPrompt, LModel: String;
  JOutput, jAnnotations, JContent: TJSonArray;
  JOutputItem, JContentItem, jAnnotationItem, jUsage: TJSonObject;
  WebSearch: TAiWebSearch;
  WebSearchItem: TAiWebSearchItem;
  MediaFile: TAiMediaFile;
  I, j, k: integer;
  aInput_tokens, aOutput_tokens, aTotal_tokens: integer;
begin
  if not Assigned(jObj) then
    Exit;

  // --- 1. Initialization and main data extraction ---
  FLastContent := '';
  WebSearch := nil;
  ResponseId := '';
  aInput_tokens := 0;
  aOutput_tokens := 0;
  aTotal_tokens := 0;

  try
    // Extract the ResponseId from the top level
    jObj.TryGetValue<String>('id', ResponseId);
    jObj.TryGetValue<String>('model', LModel);

    // Extract usage data (tokens)
    if jObj.TryGetValue<TJSonObject>('usage', jUsage) then
    begin
      jUsage.TryGetValue<integer>('input_tokens', aInput_tokens);
      jUsage.TryGetValue<integer>('output_tokens', aOutput_tokens);
      jUsage.TryGetValue<integer>('total_tokens', aTotal_tokens);
    end;

    // --- 2. Process the 'output' array ---
    if jObj.TryGetValue<TJSonArray>('output', JOutput) then
    begin
      for I := 0 to JOutput.Count - 1 do
      begin
        if not(JOutput.Items[I] is TJSonObject) then
          Continue;
        JOutputItem := JOutput.Items[I] as TJSonObject;

        if not JOutputItem.TryGetValue<String>('type', S) then
          Continue;

        // --- 'message' HANDLING (TEXT AND WEB SEARCH) ---
        if S = 'message' then
        begin
          if JOutputItem.TryGetValue<TJSonArray>('content', JContent) then
          begin
            for j := 0 to JContent.Count - 1 do
            begin
              if not(JContent.Items[j] is TJSonObject) then
                Continue;
              JContentItem := JContent.Items[j] as TJSonObject;

              if JContentItem.TryGetValue<string>('type', S) and (S = 'output_text') then
              begin
                JContentItem.TryGetValue<string>('text', FLastContent);

                if JContentItem.TryGetValue<TJSonArray>('annotations', jAnnotations) then
                begin
                  if not Assigned(WebSearch) then
                  begin
                    WebSearch := TAiWebSearch.Create;
                    WebSearch.annotations := TAiWebSearchArray.Create;
                  end;
                  WebSearch.Text := FLastContent;

                  for k := 0 to jAnnotations.Count - 1 do
                  begin
                    if not(jAnnotations.Items[k] is TJSonObject) then
                      Continue;
                    jAnnotationItem := jAnnotations.Items[k] as TJSonObject;
                    WebSearchItem := TAiWebSearchItem.Create;
                    try
                      jAnnotationItem.TryGetValue<string>('type', WebSearchItem.&type);
                      jAnnotationItem.TryGetValue<integer>('start_index', WebSearchItem.start_index);
                      jAnnotationItem.TryGetValue<integer>('end_index', WebSearchItem.end_index);
                      jAnnotationItem.TryGetValue<string>('url', WebSearchItem.Url);
                      jAnnotationItem.TryGetValue<string>('title', WebSearchItem.title);
                      WebSearch.annotations.Add(WebSearchItem);
                    except
                      WebSearchItem.Free;
                      raise;
                    end;
                  end;
                end;
                Break;
              end;
            end;
          end;
        end
        // --- NEW: 'image_generation_call' HANDLING ---
        else if S = 'image_generation_call' then
        begin
          ImageBase64 := '';
          RevisedPrompt := '';
          JOutputItem.TryGetValue<string>('result', ImageBase64);
          JOutputItem.TryGetValue<string>('revised_prompt', RevisedPrompt);

          if not ImageBase64.IsEmpty then
          begin
            MediaFile := TAiMediaFile.Create;
            try
              // The API returns a PNG by default. The name is not crucial.
              MediaFile.LoadFromBase64('generated_image.png', ImageBase64);
              // We use the 'Detail' property to save the revised prompt, a good practice.
              MediaFile.Detail := RevisedPrompt;
              ResMsg.AddMediaFile(MediaFile);
            except
              MediaFile.Free;
              raise;
            end;
          end;
        end;
      end;
    end;

    // --- 3. Populate the response message object (ResMsg) ---
    FLastContent := Trim(FLastContent);
    // If no text was generated (only an image), FLastContent will be empty, which is correct.
    ResMsg.Prompt := FLastContent;

    ResMsg.Role := 'assistant';
    ResMsg.PreviousResponseId := ResponseId;

    // Update token counters in the message and in the component
    ResMsg.Prompt_tokens := aInput_tokens;
    ResMsg.Completion_tokens := aOutput_tokens;
    ResMsg.Total_tokens := aTotal_tokens;
    ResMsg.Model := LModel;
    Self.Prompt_tokens := Self.Prompt_tokens + aInput_tokens;
    Self.Completion_tokens := Self.Completion_tokens + aOutput_tokens;
    Self.Total_tokens := Self.Total_tokens + aTotal_tokens;

    // Assign the web search results
    if Assigned(WebSearch) then
    begin

{$IF CompilerVersion < 35}
      if Assigned(ResMsg.WebSearchResponse) then
      Begin
        ResMsg.WebSearchResponse.Free;
        ResMsg.WebSearchResponse := Nil;
      End;
{$ELSE}
      FreeAndNil(ResMsg.WebSearchResponse);
{$ENDIF}
      ResMsg.WebSearchResponse := WebSearch;
      WebSearch := nil; // Avoid double free
    end;

    // --- 4. Trigger final events ---
    DoProcessResponse(GetLastMessage, ResMsg, FLastContent);
    DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, ResMsg, jObj, ResMsg.Role, FLastContent);

  except
    on E: Exception do
    begin
      if Assigned(WebSearch) then
        FreeAndNil(WebSearch);
      DoError('Error parsing the /v1/responses endpoint response: ' + E.Message, E);
      raise;
    end;
  end;
end;

function TAiOpenChat.PrepareSystemMsg: String;
Var
  S, Key, Val, MensajeInicial: String;
  I: integer;
  JMemory: TJSonObject;
begin
  // If the response format is Json, the instruction must always state that the format is json
  If Self.Response_format = TAiChatResponseFormat.tiaChatRfJson then
    S := 'Respond in json format'
  Else
    S := '';

  MensajeInicial := InitialInstructions.Text + sLineBreak + S;

  JMemory := TJSonObject.Create;
  Try
    Try
      For I := 0 to Memory.Count - 1 do
      Begin
        Key := Memory.KeyNames[I];
        Val := Memory.Values[Key];
        JMemory.AddPair(Key, Val);
      End;
    Except
      ON E: Exception do
      Begin
        Raise Exception.Create('Memory format must be Key=Value, not properly configured');
      End;
    End;

    If Assigned(OnInitChat) then // Gives the opportunity to initialize the chat with additional parameters such as memory
      OnInitChat(Self, 'system', MensajeInicial, JMemory);

    If Trim(MensajeInicial) <> '' then
      Result := MensajeInicial;

    If Length(Trim(JMemory.Format)) > 10 then
      Result := Result + sLineBreak + 'To Remember= ' + JMemory.Format;
  Finally
    JMemory.Free;
  End;
end;

procedure TAiOpenChat.SetParallel_ToolCalls(const Value: Boolean);
begin
  FParallel_ToolCalls := Value;
end;

procedure TAiOpenChat.SetService_Tier(const Value: String);
begin
  FService_Tier := Value;
end;

procedure TAiOpenChat.SetStore(const Value: Boolean);
begin
  FStore := Value;
end;

function TAiOpenChat.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer): String;
var
  Body: TMultipartFormData;
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  sUrl: String;
  Res: IHTTPResponse;
  LResponseJson: TJSonObject;
  LTempStream: TMemoryStream;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('A file with content is required for upload.');

  // The endpoint for uploading files is /v1/files
  sUrl := Url + 'files';

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 35}
  Client.SynchronizeEvents := False;
{$ENDIF}
  Body := TMultipartFormData.Create;

  LTempStream := TMemoryStream.Create;

  try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    // Crear un stream temporal para pasarlo al formulario multipart
    aMediaFile.Content.Position := 0;
    LTempStream.LoadFromStream(aMediaFile.Content);
    LTempStream.Position := 0;

{$IF CompilerVersion >= 36}
    Body.AddStream('file', LTempStream, False, aMediaFile.FileName, aMediaFile.MimeType);
{$ELSE}
    Body.AddStream('file', LTempStream, aMediaFile.FileName, aMediaFile.MimeType);
{$ENDIF}
    // The purpose for chat/completions must be 'vision' or similar
    Body.AddField('purpose', 'vision');

    Res := Client.Post(sUrl, Body, nil, Headers);

    if Res.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject.ParseJSONValue(Res.ContentAsString) as TJSonObject;
      try
        if LResponseJson.TryGetValue<string>('id', Result) then
        begin
          // We save the ID in the MediaFile object to use it later
          aMediaFile.IdFile := Result;
          aMediaFile.CloudState := LResponseJson.GetValue<string>('status');
          aMediaFile.CloudName := LResponseJson.GetValue<string>('filename');
          // 'CacheName' can be the same IdFile to mark it as active
          aMediaFile.CacheName := Result;
        end;
      finally
        FreeAndNil(LResponseJson);
      end;
    end
    else
    begin
      Raise Exception.CreateFmt('Error uploading file to OpenAI: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;

  finally
    Body.Free;
    Client.Free;
    LTempStream.Free;
  end;
end;

function TAiOpenChat.GetMessages: TJSonArray;
begin
  Result := FMessages.ToJson;
end;

{ TAiOpenAiEmbeddings }

constructor TAiOpenAiEmbeddings.Create(aOwner: TComponent);
begin
  inherited;
  FApiKey := '@OPENAI_API_KEY';
  FUrl := GlOpenAIUrl;
  FDimensions := 1536;
  FModel := 'text-embedding-3-small';
end;

function TAiOpenAiEmbeddings.CreateEmbedding(aInput, aUser: String; aDimensions: integer; aModel, aEncodingFormat: String): TAiEmbeddingData;
Var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  jObj: TJSonObject;
  Res: IHTTPResponse;
  Response: TStringStream;
  St: TStringStream;
  sUrl: String;
begin

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 35}
  Client.SynchronizeEvents := False;
{$ENDIF}
  St := TStringStream.Create('', TEncoding.UTF8);
  Response := TStringStream.Create('', TEncoding.UTF8);
  sUrl := FUrl + 'embeddings';
  jObj := TJSonObject.Create;

  If aModel = '' then
    aModel := FModel;

  if aDimensions <= 0 then
    aDimensions := FDimensions;

  Try
    jObj.AddPair('input', aInput); // This is added for compatibility with ollama
    jObj.AddPair('prompt', aInput);
    jObj.AddPair('model', aModel);
    jObj.AddPair('user', aUser);
    jObj.AddPair('dimensions', aDimensions);
    jObj.AddPair('encoding_format', aEncodingFormat);

    St.WriteString(jObj.ToJson);
    St.Position := 0;

    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    Headers := Headers + [TNetHeader.Create('OpenAI-Beta', 'assistants=v2')];
    Client.ContentType := 'application/json';

    Res := Client.Post(sUrl, St, Response, Headers);
    Response.Position := 0;

{$IFDEF APIDEBUG}
    Response.SaveToFile('c:\temp\response.txt');
{$ENDIF}
    if Res.StatusCode = 200 then
    Begin
      jObj := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
      ParseEmbedding(jObj);
      Result := Self.FData;

    End
    else
    begin
      Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;

  Finally
    Client.Free;
    St.Free;
    Response.Free;
    jObj.Free;
  End;
end;

destructor TAiOpenAiEmbeddings.Destroy;
begin

  inherited;
end;

procedure TAiOpenAiEmbeddings.ParseEmbedding(jObj: TJSonObject);
Var
  JArr, jData: TJSonArray;
  Emb: TAiEmbeddingData;
  JVal: TJSonValue;
  j: integer;
  Usage: TJSonObject;

begin
  jObj.TryGetValue<String>('model', FModel);

  If jObj.TryGetValue<TJSonObject>('usage', Usage) then
  Begin
    Usage.TryGetValue<integer>('prompt_tokens', Fprompt_tokens);
    Usage.TryGetValue<integer>('total_tokens', Ftotal_tokens);
  End;

  jData := jObj.GetValue<TJSonArray>('data');

  SetLength(FData, jData.Count);

  // var i := 0;
  For JVal in jData do
  Begin
    // The OpenAi embedding returns an array, but only the first one in the row is taken
    JArr := TJSonObject(JVal).GetValue<TJSonArray>('embedding');
    j := JArr.Count;
    SetLength(Emb, j);
    // FillChar(Emb, Length(Emb) * SizeOf(Double), 0);

    For j := 0 to JArr.Count - 1 do
      Emb[j] := JArr.Items[j].GetValue<Double>;

    FData := Emb;
    // Inc(i);
    Break; // If the OpenAI embedding returns several, we only take the first one; usually there is only one
  End;
end;

initialization

TAiChatFactory.Instance.RegisterDriver(TAiOpenChat);

end.