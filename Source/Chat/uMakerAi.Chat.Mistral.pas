unit uMakerAi.Chat.Mistral;

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
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Tools.Functions, uMakerAi.Core, uMakerAi.Chat.Messages;

{ TODO : Missing Mistral functions to create }
/// -----------------------------------------------------------------------------
/// Missing functions to create:
/// https://docs.mistral.ai/api/#operation/jobs_api_routes_fine_tuning_create_fine_tuning_job
/// Delete Model
/// GET List Fine Tuning Jobs
/// POST Create Fine Tuning Job
/// GET  Get Fine Tuning Job
/// POST Cancel Fine Tuning Job
/// -----------------------------------------------------------------------------

type

  TMistralFile = record
    Id: String;
    &Object: String;
    Size_Bytes: Int64;
    Created_At: Int64;
    Filename: String;
    Purpose: String;
  end;

  TAiMistralChat = Class(TAiChat)
  Private
    FOcrIncludeImages: Boolean;
    FOcrIncludeBlocks: Boolean;  // OCR 4 (Jun 2026): blocks with bounding boxes
    FTtsVoice: string;           // Voxtral TTS: voice slug from catalog /v1/audio/voices (REQUIRED)
    FTtsFormat: string;          // mp3 | wav | pcm | flac | opus
    FDocumentImageLimit: integer;
    FDocumentPageLimit: integer;
    FOcrBboxAnnotationSchema: TStringList;
    FOcrDocumentAnnotationSchema: TStringList;
    FOcrAnnotationPages: string;
    FOcrPagesNumbers: string;
    procedure SetOcrIncludeImages(const Value: Boolean);
    procedure SetDocumentImageLimit(const Value: integer);
    procedure SetDocumentPageLimit(const Value: integer);
    procedure SetOcrAnnotationPages(const Value: string);
    procedure SetOcrBboxAnnotationSchema(const Value: TStringList);
    procedure SetOcrDocumentAnnotationSchema(const Value: TStringList);
    procedure SetOcrPagesNumbers(const Value: string);
  Protected
    Function InitChatCompletions: String; Override;
    Function InitChatCompletionsFim(aPrompt, aSuffix: String): String; Virtual; // Introduced only here
    Function ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions; Override;
    Procedure ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage); Override;
    // Mistral format: delta.content as typed array (type: "text" | "thinking")
    procedure ParseDeltaContentArray(AContentArr: TJSonArray; jObj: TJSonObject); Override;

    function InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    // Voxtral TTS (Mar 2026): POST /v1/audio/speech with voxtral-mini-tts-2603
    function InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;

    // function InternalRunOcr(aMediaFile: TAiMediaFile): String;
    function ParseOcrResponse(jResponse: TJSONObject; ResMsg: TAiChatMessage): string;

    function RetrieveFileMetadata(aFileId: string): TMistralFile; virtual;
    function GetSignedUrl(aMediaFile: TAiMediaFile): string;
    function GetSignedUrlById(const aFileId: string): string;
  Public
    Constructor Create(Sender: TComponent); Override;
    // Function AddMessageFimAndRun(aPrompt, aSuffix: String): String; Virtual;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;

    // File management functions

    Function UploadFile(aMediaFile: TAiMediaFile): String; Override;
    Function DeleteFile(aMediaFile: TAiMediaFile): String; Override;
    function RetrieveFile(aFileId: string): TAiMediaFile; Override;
    Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer = 3600): String; Override;

  Published
    property OcrIncludeImages: Boolean read FOcrIncludeImages write SetOcrIncludeImages;
    // OCR 4 (Jun 23/2026): each page returns a 'blocks' array with bounding
    // boxes at paragraph level and structural labels (title, table, code...)
    property OcrIncludeBlocks: Boolean read FOcrIncludeBlocks write FOcrIncludeBlocks default False;
    // Voxtral TTS: voice slug from catalog GET /v1/audio/voices (REQUIRED
    // for the API; tested: en_paul_neutral/happy/sad..., gb_oliver_neutral,
    // gb_jane_sarcasm). The model is multilingual with any voice
    property TtsVoice: string read FTtsVoice write FTtsVoice;
    // TTS output format: mp3 (default) | wav | pcm | flac | opus
    property TtsFormat: string read FTtsFormat write FTtsFormat;
    property DocumentImageLimit: integer read FDocumentImageLimit write SetDocumentImageLimit;
    property DocumentPageLimit: integer read FDocumentPageLimit write SetDocumentPageLimit;

    property OcrDocumentAnnotationSchema: TStringList read FOcrDocumentAnnotationSchema write SetOcrDocumentAnnotationSchema;
    property OcrBboxAnnotationSchema: TStringList read FOcrBboxAnnotationSchema write SetOcrBboxAnnotationSchema;
    property OcrAnnotationPages: string read FOcrAnnotationPages write SetOcrAnnotationPages;
    property OcrPagesNumbers: string read FOcrPagesNumbers write SetOcrPagesNumbers;

  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://api.mistral.ai/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMistralChat]);
end;

{ TAiMistralChat }

class function TAiMistralChat.GetDriverName: string;
Begin
  Result := 'Mistral';
End;

function TAiMistralChat.GetSignedUrl(aMediaFile: TAiMediaFile): string;
var
  LResponse: IHTTPResponse;
  LUrl: string;
  LResponseObj: TJSONObject;
  LSignedUrl: string;
  LHeaders: TNetHeaders; // Added
begin
  Result := '';
  // MODIFIED: Check the correct field.
  if not Assigned(aMediaFile) or aMediaFile.IDFile.IsEmpty then
    raise Exception.Create('The TAiMediaFile must have a valid file ID (in IDFile) to obtain a signed URL.');

  // MODIFIED: Use the correct field to build the URL.
  LUrl := Url + 'files/' + aMediaFile.IDFile + '/url';
  LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)]; // Add the authorization header
  LResponse := FClient.Get(LUrl, nil, LHeaders); // Add the header to the request

  if not Assigned(LResponse) then
    raise Exception.CreateFmt('Connection failed: no response from %s', [LUrl]);

  if LResponse.StatusCode = 200 then
  begin
    LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      LSignedUrl := LResponseObj.GetValue<string>('url');
      Result := LSignedUrl;

      // Update the MediaFile object with the temporary URL.
      aMediaFile.UrlMedia := LSignedUrl;
      aMediaFile.CloudState := 'url-signed';
    finally
      LResponseObj.Free;
    end;
  end
  else
  begin
    aMediaFile.CloudState := 'url-sign-failed';
    FLastError := LResponse.ContentAsString;
    DoError(Format('Error obtaining signed URL: %d - %s', [LResponse.StatusCode, FLastError]), nil);
  end;
end;

function TAiMistralChat.GetSignedUrlById(const aFileId: string): string;
var
  media: TAiMediaFile;
begin
  if aFileId.IsEmpty then
    Exit('');
  media := TAiMediaFile.Create;
  try
    media.IDFile := aFileId;
    Result := Self.GetSignedUrl(media);
  finally
    media.Free;
  end;
end;

class procedure TAiMistralChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@MISTRAL_API_KEY');
  Params.Add('Model=mistral-small-latest');
  Params.Add('Max_Tokens=4096');
  Params.Add('URL=https://api.mistral.ai/v1/');
End;

function TAiMistralChat.RetrieveFile(aFileId: string): TAiMediaFile;
var
  LMetadata: TMistralFile;
  LContentStream: TMemoryStream;
  LResponse: IHTTPResponse;
  LUrl: string;
begin
  Result := nil; // Default, returns nil if something fails.
  if aFileId.IsEmpty then
    raise Exception.Create('A file ID is required to retrieve it.');

  // 1. Get metadata first to know the filename and other details.
  LMetadata := RetrieveFileMetadata(aFileId);
  if LMetadata.Id.IsEmpty then
  begin
    // Error already reported by RetrieveFileMetadata.
    Exit;
  end;

  // 2. Now, get the file content.
  LUrl := Url + 'files/' + aFileId + '/content';
  LContentStream := TMemoryStream.Create;
  try
    // The response from this endpoint is binary, not JSON.
    // Capture it directly into a TMemoryStream.
    LResponse := FClient.Get(LUrl, LContentStream);

    if LResponse.StatusCode = 200 then
    begin
      LContentStream.Position := 0;

      // Create and populate the TAiMediaFile object.
      Result := TAiMediaFile.Create;
      try
        Result.LoadFromStream(LMetadata.Filename, LContentStream);
        // Save the Mistral ID for future reference.
        // Reuse IdAudio as in other parts of the code.
        Result.IDFile := aFileId;
      except
        // If error creating or loading, free and return nil.
        FreeAndNil(Result);
        raise;
      end;
    end
    else
    begin
      // If content download fails.
      LContentStream.Position := 0;
      Var
      LStringStream := TStringStream.Create('', TEncoding.UTF8);

      try
        LStringStream.CopyFrom(LContentStream, LContentStream.Size);
        FLastError := LStringStream.DataString;
      finally
        LStringStream.Free;
      end;
      DoError(Format('Error retrieving file content: %d - %s', [LResponse.StatusCode, FLastError]), nil);
      // Result remains nil, which is what we want to return on error.
    end;
  finally
    LContentStream.Free;
  end;
end;

function TAiMistralChat.RetrieveFileMetadata(aFileId: string): TMistralFile;
var
  LResponse: IHTTPResponse;
  LUrl: string;
  LFileObj: TJSONObject;
begin
  // Initialize the result
  FillChar(Result, SizeOf(TMistralFile), 0);
  Result.Id := '';

  if aFileId.IsEmpty then
    raise Exception.Create('A file ID is required to retrieve its metadata.');

  LUrl := Url + 'files/' + aFileId;
  LResponse := FClient.Get(LUrl);

  if not Assigned(LResponse) then
    raise Exception.CreateFmt('Connection failed: no response from %s', [LUrl]);

  if LResponse.StatusCode = 200 then
  begin
    LFileObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      Result.Id := LFileObj.GetValue<string>('id');
      Result.&Object := LFileObj.GetValue<string>('object');
      Result.Size_Bytes := LFileObj.GetValue<Int64>('bytes');
      Result.Created_At := LFileObj.GetValue<Int64>('created_at');
      Result.Filename := LFileObj.GetValue<string>('filename');
      Result.Purpose := LFileObj.GetValue<string>('purpose');
    finally
      LFileObj.Free;
    end;
  end
  else
  begin
    FLastError := LResponse.ContentAsString;
    DoError(Format('Error retrieving file metadata: %d - %s', [LResponse.StatusCode, FLastError]), nil);
  end;
end;

procedure TAiMistralChat.SetDocumentImageLimit(const Value: integer);
begin
  FDocumentImageLimit := Value;
end;

procedure TAiMistralChat.SetDocumentPageLimit(const Value: integer);
begin
  FDocumentPageLimit := Value;
end;

procedure TAiMistralChat.SetOcrAnnotationPages(const Value: string);
begin
  FOcrAnnotationPages := Value;
end;

procedure TAiMistralChat.SetOcrBboxAnnotationSchema(const Value: TStringList);
begin
  FOcrBboxAnnotationSchema := Value;
end;

procedure TAiMistralChat.SetOcrDocumentAnnotationSchema(const Value: TStringList);
begin
  FOcrDocumentAnnotationSchema := Value;
end;

procedure TAiMistralChat.SetOcrIncludeImages(const Value: Boolean);
begin
  FOcrIncludeImages := Value;
end;

procedure TAiMistralChat.SetOcrPagesNumbers(const Value: string);
begin
  FOcrPagesNumbers := Value;
end;

function TAiMistralChat.UploadFile(aMediaFile: TAiMediaFile): String;
var
  LBody: TMultipartFormData;
  LTempStream: TMemoryStream;
  LResponseStream: TMemoryStream;
  LResponse: IHTTPResponse;
  LUrl: string;
  LResponseObj: TJSONObject;
  LHeaders: TNetHeaders;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('A TAiMediaFile with content is needed to upload.');

  LUrl := Url + 'files';
  LBody := TMultipartFormData.Create;
  LTempStream := TMemoryStream.Create;
  LResponseStream := TMemoryStream.Create;
  try
    aMediaFile.Content.Position := 0;
    LTempStream.LoadFromStream(aMediaFile.Content);
    LTempStream.Position := 0;

    LBody.AddField('purpose', 'ocr');

{$IF CompilerVersion >= 36}
    LBody.AddStream('file', LTempStream, False, aMediaFile.Filename, aMediaFile.MimeType);
{$ELSE}
    LBody.AddStream('file', LTempStream, aMediaFile.Filename, aMediaFile.MimeType);
{$ENDIF}
    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    LResponse := FClient.Post(LUrl, LBody, LResponseStream, LHeaders);

    if LResponse.StatusCode = 200 then
    begin
      LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      try
        Result := LResponseObj.GetValue<string>('id');
        aMediaFile.IDFile := Result;
      finally
        LResponseObj.Free;
      end;
    end
    else
    begin
      FLastError := LResponse.ContentAsString;
      DoError(Format('Error uploading file: %d - %s', [LResponse.StatusCode, FLastError]), nil);
    end;
  finally
    LBody.Free;
    LTempStream.Free;
    LResponseStream.Free;
  end;
end;

function TAiMistralChat.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer = 3600): String;
var
  FileId: string;
begin
  Result := '';
  // Call the upload function we already implemented
  FileId := Self.UploadFile(aMediaFile);

  if not FileId.IsEmpty then
  begin
    // Success. The ID is already in aMediaFile.IDFile thanks to UploadFile.
    // Use CacheName as a flag to indicate this file should be used as persistent context.
    aMediaFile.CacheName := FileId; // The value can be the FileId itself for reference.
    aMediaFile.CloudState := 'cached';
    Result := FileId;
  end;
end;

class function TAiMistralChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiMistralChat.Create(Sender);
End;

function TAiMistralChat.DeleteFile(aMediaFile: TAiMediaFile): String;
var
  LResponse: IHTTPResponse;
  LUrl: string;
  LResponseObj: TJSONObject;
begin
  Result := '';
  if not Assigned(aMediaFile) or aMediaFile.IDFile.IsEmpty then
    raise Exception.Create('The TAiMediaFile must have a valid file ID to be deleted.');

  LUrl := Url + 'files/' + aMediaFile.IDFile;
  LResponse := FClient.Delete(LUrl, nil);

  if LResponse.StatusCode = 200 then
  begin
    LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      // The delete response contains the id and a flag "deleted: true"
      if LResponseObj.GetValue<Boolean>('deleted') then
        Result := LResponseObj.GetValue<string>('id')
      else
        Result := '';
    finally
      LResponseObj.Free;
    end;
  end
  else
  begin
    FLastError := LResponse.ContentAsString;
    DoError(Format('Error deleting file: %d - %s', [LResponse.StatusCode, FLastError]), nil);
  end;
end;

constructor TAiMistralChat.Create(Sender: TComponent);
begin
  inherited;

  ApiKey := '@MISTRAL_API_KEY';
  Model := 'mistral-small-latest';
  FOcrIncludeImages := True;
  FOcrIncludeBlocks := False;
  FTtsVoice := 'en_paul_neutral'; // API requires a voice; tested runtime slug
  FTtsFormat := 'mp3';
  Url := GlAIUrl;
end;

// Voxtral TTS (Mar 2026): generates voice from text via POST /v1/audio/speech.
// Activated with the [cap_GenAudio] gap (e.g. model voxtral-mini-tts-2603).
// The response can be raw audio bytes or JSON with the field audio_data in base64
// — both forms are handled.
function TAiMistralChat.InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl, LModel: string;
  LBodyStream: TStringStream;
  LResponseStream: TMemoryStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LJsonObject: TJSONObject;
  LErrorResponse: string;
  LNewAudioFile: TAiMediaFile;
  OldAsc: Boolean;
begin
  Result := '';
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  if FMessages.IndexOf(AskMsg) < 0 then
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  LUrl := Url + 'audio/speech';
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LModel.IsEmpty then
    LModel := 'voxtral-mini-tts-2603';

  LJsonObject := TJSONObject.Create;
  LBodyStream := nil;
  LResponseStream := TMemoryStream.Create;
  OldAsc := FClient.Asynchronous;
  try
    try
      FClient.Asynchronous := False;

      LJsonObject.AddPair('model', LModel);
      LJsonObject.AddPair('input', AskMsg.Prompt);
      // The API requires 'voice' (slug from catalog) or 'ref_audio' — without either it returns 400
      LJsonObject.AddPair('voice', FTtsVoice);
      if FTtsFormat <> '' then
        LJsonObject.AddPair('response_format', FTtsFormat);

      LBodyStream := TStringStream.Create(LJsonObject.ToJSON, TEncoding.UTF8);
      LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
      FClient.ContentType := 'application/json';
      LBodyStream.Position := 0;

      LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

      if LResponse.StatusCode = 200 then
      begin
        LNewAudioFile := TAiMediaFile.Create;
        try
          LResponseStream.Position := 0;
          if Pos('json', LResponse.MimeType.ToLower) > 0 then
          begin
            // JSON response: {"audio_data":"<base64>", ...}
            var LRespBytes: TBytes;
            SetLength(LRespBytes, LResponseStream.Size);
            if LResponseStream.Size > 0 then
              LResponseStream.ReadBuffer(LRespBytes[0], LResponseStream.Size);
            var LJsonResp := TJSONObject.ParseJSONValue(
              TEncoding.UTF8.GetString(LRespBytes)) as TJSONObject;
            if not Assigned(LJsonResp) then
              raise Exception.Create('Invalid TTS JSON response');
            try
              var LB64 := LJsonResp.GetValue<string>('audio_data', '');
              if LB64 = '' then
                raise Exception.Create('TTS response without audio_data');
              var LAudioBytes := TNetEncoding.Base64.DecodeStringToBytes(LB64);
              var LAudioStream := TMemoryStream.Create;
              try
                LAudioStream.WriteBuffer(LAudioBytes[0], Length(LAudioBytes));
                LAudioStream.Position := 0;
                LNewAudioFile.LoadFromStream('generated_audio.' + FTtsFormat, LAudioStream);
              finally
                LAudioStream.Free;
              end;
            finally
              LJsonResp.Free;
            end;
          end
          else
            // Binary response: the bytes are the audio directly
            LNewAudioFile.LoadFromStream('generated_audio.' + FTtsFormat, LResponseStream);

          ResMsg.MediaFiles.Add(LNewAudioFile);
          DoStateChange(acsFinished, 'Done');
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
        var LErrBytes: TBytes;
        SetLength(LErrBytes, LResponseStream.Size);
        if LResponseStream.Size > 0 then
          LResponseStream.ReadBuffer(LErrBytes[0], LResponseStream.Size);
        LErrorResponse := TEncoding.UTF8.GetString(LErrBytes);
        FLastError := Format('Error generating audio: %d, %s', [LResponse.StatusCode, LErrorResponse]);
        DoError(FLastError, nil);
      end;
    except
      on E: Exception do
      begin
        FLastError := 'Error in Voxtral TTS: ' + E.Message;
        DoError(FLastError, E);
      end;
    end;
  finally
    FClient.Asynchronous := OldAsc;
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
    FBusy := False;
  end;
end;

function TAiMistralChat.ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions;
Var
  jObj, Msg, jFunc: TJSONObject;
  JVal, JVal1, jValToolCall: TJSonValue;
  Fun: TAiToolsFunction;
  JToolCalls: TJSonArray;
begin
  Result := TAiToolsFunctions.Create;

  For JVal1 in jChoices do
  Begin
    Msg := TJSONObject(JVal1).GetValue<TJSONObject>('message');

    If Msg.TryGetValue<TJSonValue>('tool_calls', jValToolCall) and (jValToolCall is TJSonArray) and Msg.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
    Begin
      For JVal in JToolCalls do
      Begin
        jObj := TJSONObject(JVal);
        var sType: string;
        if not jObj.TryGetValue<String>('type', sType) then sType := 'function';
        If sType = 'function' then
        Begin
          Fun := TAiToolsFunction.Create;
          Fun.Id := jObj.GetValue<String>('id');
          Fun.&Type := sType;

          If jObj.TryGetValue<TJSONObject>('function', jFunc) then
          Begin
            Fun.Name := jFunc.GetValue<String>('name');

            Fun.Arguments := jObj.GetValue<TJSONObject>('function').GetValue<String>('arguments');
          End;

          Try
            // Arguments contains the canonical JSON of parameters

          Except
            // If no parameters, do not mark error
          End;

          Result.Add(Fun.Id, Fun);
        End;
      End;
    End;
  End;
end;

procedure TAiMistralChat.ParseDeltaContentArray(AContentArr: TJSonArray; jObj: TJSonObject);
// Mistral format (2507+): delta.content is an array of typed blocks.
//   {"type": "text",     "text": "..."}            → response fragment
//   {"type": "thinking", "thinking": [{...},...]}   → internal reasoning
var
  Item     : TJSonValue;
  ItemObj  : TJSonObject;
  SType, SText, Value: string;
  JThinkArr: TJSonArray;
  ThinkItem: TJSonValue;
  ThinkText: string;
begin
  for Item in AContentArr do
  begin
    if not (Item is TJSonObject) then Continue;
    ItemObj := TJSonObject(Item);

    if not ItemObj.TryGetValue<string>('type', SType) then Continue;

    if SType = 'text' then
    begin
      // Text block: appends to accumulated content and fires OnReceiveData
      if ItemObj.TryGetValue<string>('text', SText) and (SText <> '') then
      begin
        FLastContent := FLastContent + SText;
        if Assigned(FOnReceiveDataEvent) then
        begin
          Value := StringReplace(SText, #$A, sLineBreak, [rfReplaceAll]);
          FOnReceiveDataEvent(Self, nil, jObj, FTmpRole, Value);
        end;
      end;
    end
    else if SType = 'thinking' then
    begin
      // Thinking block: concatenate text from nested array "thinking"
      ThinkText := '';
      if ItemObj.TryGetValue<TJSonArray>('thinking', JThinkArr) then
        for ThinkItem in JThinkArr do
          if (ThinkItem is TJSonObject) then
          begin
            if TJSonObject(ThinkItem).TryGetValue<string>('text', SText) then
              ThinkText := ThinkText + SText;
          end;

      if (ThinkText <> '') and Assigned(Self.OnReceiveThinking) then
      begin
        ThinkText := StringReplace(ThinkText, #$A, sLineBreak, [rfReplaceAll]);
        Self.OnReceiveThinking(Self, nil, jObj, FTmpRole, ThinkText);
      end;
    end;
    // Other future types (e.g. "tool_use") will be ignored until Mistral documents them.
  end;
end;

function TAiMistralChat.InitChatCompletions: String;
var
  AJSONObject, jToolChoice: TJSONObject;
  JArr, JStop: TJSonArray;
  Lista: TStringList;
  I: integer;
  Res: String;
  // --- Variables for Document QnA logic ---
  ActiveFileId: string;
  SignedUrl: string;
  MessagesJson: TJSonArray;
  LastMessageObj: TJSONObject;
  PromptText: string;
  NewContentArray: TJSonArray;
  Msg: TAiChatMessage;
  MediaFile: TAiMediaFile;
  JTextObj, JDocObj: TJSONObject;
  LModel: String;
begin
  // 1. --- Variable initialization ---
  AJSONObject := TJSONObject.Create;
  Lista := TStringList.Create;
  ActiveFileId := '';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  try
    // 2. --- Active Cache detection for Document QnA ---
    // Walk through message history from most recent to oldest.
    // The first file with a 'CacheName' will be used as context.
    for I := FMessages.Count - 1 downto 0 do
    begin
      Msg := FMessages[I];
      if Assigned(Msg.MediaFiles) then
      begin
        for MediaFile in Msg.MediaFiles do
        begin
          // 'CacheName' is the flag indicating this file is a persistent context.
          if not MediaFile.CacheName.IsEmpty then
          begin
            ActiveFileId := MediaFile.IDFile; // The key data is the uploaded file ID.
            Break; // Exit the MediaFiles loop.
          end;
        end;
      end;
      if not ActiveFileId.IsEmpty then
        Break; // Cache found, exit the Messages loop.
    end;

    // 3. --- Build the Messages Array ---
    // Get the standard messages JSON generated by the base class.
    MessagesJson := GetMessages;

    // If a cached file was found and there are messages, modify the last message
    // to inject the document reference.
    if (not ActiveFileId.IsEmpty) and (MessagesJson.Count > 0) then
    begin
      // Get a signed temporary URL for the file.
      SignedUrl := Self.GetSignedUrlById(ActiveFileId);
      if not SignedUrl.IsEmpty then
      begin
        // a. Get the last message object from the JSON array.
        LastMessageObj := MessagesJson.Items[MessagesJson.Count - 1] as TJSONObject;

        // b. Extract the original text (the user prompt).
        var
          LContent: TJSonValue;

        if LastMessageObj.TryGetValue('content', LContent) and (LContent is TJSONString) then
          PromptText := LContent.Value
        else
          PromptText := '';

        // c. Create the new 'content' as an array [ {type: text}, {type: document_url} ].
        NewContentArray := TJSonArray.Create;

        // c.1. Create the text object
        JTextObj := TJSONObject.Create;
        JTextObj.AddPair('type', 'text');
        JTextObj.AddPair('text', PromptText);
        NewContentArray.Add(JTextObj);

        // c.2. Create the document object
        JDocObj := TJSONObject.Create;
        JDocObj.AddPair('type', 'document_url');
        JDocObj.AddPair('document_url', SignedUrl);
        NewContentArray.Add(JDocObj);

        // d. Replace the old 'content' with the new array.
        LastMessageObj.RemovePair('content');
        LastMessageObj.AddPair('content', NewContentArray);
      end;
    end;
    AJSONObject.AddPair('messages', MessagesJson);

    // 4. --- Add standard parameters to the request ---
    AJSONObject.AddPair('model', LModel);

    if Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAi).Text) <> '') then
    begin
{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAi).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAi).Text));
{$ENDIF}
      if Not Assigned(JArr) then
        Raise Exception.Create('The Tools property is malformed; it must be a JsonArray');
      AJSONObject.AddPair('tools', JArr);

      if (Trim(Tool_choice) <> '') then
      begin
        try
{$IF CompilerVersion < 35}
          jToolChoice := TJSONUtils.ParseAsObject(Tool_choice);
{$ELSE}
          jToolChoice := TJSONObject(TJSonArray.ParseJSONValue(Tool_choice));
{$ENDIF}
          if Assigned(jToolChoice) then
            AJSONObject.AddPair('tool_choice', jToolChoice);
        except
          AJSONObject.AddPair('tool_choice', Tool_choice);
        end;
      end;
    end;

    AJSONObject.AddPair('temperature', TJSONNumber.Create(Temperature));
    if Max_tokens > 0 then
      AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));
    if Top_p > 0 then
      AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));
    if Frequency_penalty <> 0 then
      AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Trunc(Frequency_penalty * 100) / 100));
    if Presence_penalty <> 0 then
      AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Trunc(Presence_penalty * 100) / 100));
    if Seed > 0 then
      AJSONObject.AddPair('random_seed', TJSONNumber.Create(Seed));

    // 5. --- Add Mistral-specific parameters ---
    if not ActiveFileId.IsEmpty then
    begin
      if DocumentImageLimit > 0 then
        AJSONObject.AddPair('document_image_limit', TJSONNumber.Create(DocumentImageLimit));
      if DocumentPageLimit > 0 then
        AJSONObject.AddPair('document_page_limit', TJSONNumber.Create(DocumentPageLimit));
    end;

    if FResponse_format = tiaChatRfJsonSchema then
    begin
      // ParseJsonSchemaProperty accepts the bare schema or the wrapper {name, strict,
      // schema} and fails with a clear error if JsonSchema is empty.
      var sSchemaName := 'json_response';
      var bStrict := True;
      var JInnerSchema := ParseJsonSchemaProperty(sSchemaName, bStrict);

      var JSchemaObj := TJSONObject.Create;
      JSchemaObj.AddPair('name', sSchemaName);
      JSchemaObj.AddPair('schema', JInnerSchema);
      JSchemaObj.AddPair('strict', TJSONBool.Create(bStrict));

      var JFormatConfig := TJSONObject.Create;
      JFormatConfig.AddPair('type', 'json_schema');
      JFormatConfig.AddPair('json_schema', JSchemaObj);
      AJSONObject.AddPair('response_format', JFormatConfig);
    end
    else if FResponse_format = tiaChatRfJson then
      AJSONObject.AddPair('response_format', TJSONObject.Create.AddPair('type', 'json_object'))
    else
      AJSONObject.AddPair('response_format', TJSONObject.Create.AddPair('type', 'text'));

    Lista.CommaText := Stop;
    if Lista.Count > 0 then
    begin
      JStop := TJSonArray.Create;
      for I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    end;

    // 6. --- Streaming configuration ---
    FClient.Asynchronous := Self.Asynchronous;
    AJSONObject.AddPair('stream', TJSONBool.Create(FClient.Asynchronous));

    // Reasoning: Magistral uses prompt_mode=reasoning; Small4/Medium3.5 use reasoning_effort
    if ModelConfig.ThinkingLevel <> tlDefault then
    begin
      if LModel.StartsWith('magistral') then
        AJSONObject.AddPair('prompt_mode', 'reasoning')
      else
      begin
        // mistral-small-2603 (Small 4) and mistral-medium-2604 (Medium 3.5)
        case ModelConfig.ThinkingLevel of
          tlLow:    AJSONObject.AddPair('reasoning_effort', 'low');
          tlMedium: AJSONObject.AddPair('reasoning_effort', 'medium');
          tlHigh:   AJSONObject.AddPair('reasoning_effort', 'high');
        end;
      end;
    end;

    // 7. --- Finalize and return JSON ---

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);

  finally
    AJSONObject.Free;
    Lista.Free;
  end;
end;

function TAiMistralChat.InitChatCompletionsFim(aPrompt, aSuffix: String): String;
Var
  AJSONObject: TJSONObject;
  JStop: TJSonArray;
  Lista: TStringList;
  I: integer;
  LAsincronico: Boolean;
  LModel: String;
begin

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'mistral-small-latest';

  AJSONObject := TJSONObject.Create;
  Lista := TStringList.Create;

  Try
    LAsincronico := True;
    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    AJSONObject.AddPair('prompt', aPrompt);
    AJSONObject.AddPair('suffix', aSuffix);
    AJSONObject.AddPair('model', LModel);

    AJSONObject.AddPair('temperature', TJSONNumber.Create(Trunc(Temperature * 100) / 100));
    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));

    If Top_p <> 0 then
      AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

    Lista.CommaText := Stop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    End;

    If Seed > 0 then
      AJSONObject.AddPair('random_seed', TJSONNumber.Create(Seed));

    var
    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);

  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

procedure TAiMistralChat.ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage);
var
  choices: TJSonArray;
  JItem, jMessage: TJSONObject;
  JVal, JContentVal: TJSonValue;
  JContentArr: TJSonArray;
  JChunk: TJSONObject;
  JThinkingArr: TJSonArray;
  sType, sText, sThinking: String;
begin
  // Detect if content is array (Magistral reasoning) vs string (standard models)
  if jObj.TryGetValue<TJSonArray>('choices', choices) and (choices.Count > 0) then
  begin
    JItem := choices.Items[0] as TJSONObject;
    if JItem.TryGetValue<TJSONObject>('message', jMessage) then
    begin
      if jMessage.TryGetValue<TJSonValue>('content', JContentVal) and (JContentVal is TJSonArray) then
      begin
        // MAGISTRAL: content is array of typed chunks
        JContentArr := TJSonArray(JContentVal);
        sText := '';
        sThinking := '';

        for JVal in JContentArr do
        begin
          if not (JVal is TJSonObject) then
            Continue;
          JChunk := TJSonObject(JVal);

          if not JChunk.TryGetValue<String>('type', sType) then
            Continue;

          if sType = 'text' then
          begin
            var sPartText := '';
            if JChunk.TryGetValue<String>('text', sPartText) then
              sText := sText + sPartText;
          end
          else if sType = 'thinking' then
          begin
            // thinking contains an array: [{"type":"text","text":"..."}]
            if JChunk.TryGetValue<TJSonArray>('thinking', JThinkingArr) then
            begin
              for var JThinkVal in JThinkingArr do
              begin
                if (JThinkVal is TJSonObject) then
                begin
                  var JThinkingItem := TJSonObject(JThinkVal);
                  var sThinkText := '';
                  if JThinkingItem.TryGetValue<String>('text', sThinkText) then
                    sThinking := sThinking + sThinkText;
                end;
              end;
            end;
          end;
          // 'reference' chunks are ignored for now (future citations)
        end;

        // Replace content of the message with the extracted text so inherited can work
        jMessage.RemovePair('content');
        jMessage.AddPair('content', sText);

        // Save reasoning content so the base class processes it
        if sThinking <> '' then
        begin
          jMessage.RemovePair('reasoning_content');
          jMessage.AddPair('reasoning_content', sThinking);
        end;

        // Delegate to inherited ParseChat which already handles content=string + reasoning_content
        inherited ParseChat(jObj, ResMsg);
        Exit;
      end;
    end;
  end;

  // STANDARD MODELS: content is string, delegate directly
  inherited ParseChat(jObj, ResMsg);
end;

function TAiMistralChat.InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  LBodyStream: TStringStream;
  LResponseStream: TMemoryStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LJsonObject, LDocumentObj, LBboxAnnotationFormatObj, LDocumentAnnotationFormatObj: TJSONObject;
  LUrl: string;
  LDataUri: string;
  LResponseObj: TJSONObject;
  LPagesArray: TJSonArray;
  LModel: String;

  PageNumbers: TStringDynArray;
  PageNumber: string;
  PageIndex: integer;
  FileId: String;

begin
  Result := '';
  if not Assigned(aMediaFile) then
    raise Exception.Create('A TAiMediaFile is required for the OCR process.');

  FBusy := True;
  FLastError := '';
  LUrl := Url + 'ocr'; // Correct endpoint /v1/ocr, omitting /process as was before.
  LJsonObject := TJSONObject.Create;
  LDocumentObj := TJSONObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  LResponseStream := TMemoryStream.Create;
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model); // Get the base model.
  LBboxAnnotationFormatObj := nil;
  LDocumentAnnotationFormatObj := nil;

  try
    // 1. Build the JSON request body
    if LModel.IsEmpty then
    begin
      // If base model is empty, use the default model.
      LJsonObject.AddPair('model', TJSONString.Create('mistral-ocr-latest'));
    end
    else
      LJsonObject.AddPair('model', TJSONString.Create(LModel));

    // Document id.
    // LJsonObject.AddPair('id', TJSONString.Create(aMediaFile.IDFile));  //Commented because the upload process is handled internally.

    // 2. Determine document type and source
    aMediaFile.CloudState := 'ocr-processing'; // Update state

    // **NEW AUTOMATIC UPLOAD LOGIC**
    if aMediaFile.IDFile.IsEmpty then // If no ID, it hasn't been uploaded.
    begin
      // Upload the file.
      FileId := UploadFile(aMediaFile); // Upload the file to the API
      if FileId.IsEmpty then
      begin
        // Report error and exit.
        DoError('Could not upload the file to the API', nil);
        Exit;
      end;
      aMediaFile.IDFile := FileId; // Assign the ID to the MediaFile object.
    end;

    // From here, the file is uploaded, whether it came that way or was just uploaded.
    LJsonObject.AddPair('id', TJSONString.Create(aMediaFile.IDFile)); // Added after uploading the file to the API

    // if not aMediaFile.IDFile.IsEmpty then
    begin
      // Scenario A: The file was already uploaded to Mistral.
      // We need a signed URL so the OCR service can access it.
      aMediaFile.CloudState := 'ocr-getting-signed-url';
      LDataUri := GetSignedUrl(aMediaFile); // This function updates aMediaFile.CloudUri

      if LDataUri.IsEmpty then
      begin
        // GetSignedUrl already reported the error.
        DoError('Could not get the signed URL for the file with ID: ' + aMediaFile.IDFile, nil);
        aMediaFile.CloudState := 'ocr-failed: signed-url';
        Exit;
      end;

      // The OCR API expects a `document_url`, even for uploaded files.
      LDocumentObj.AddPair('document_url', LDataUri);
      LDocumentObj.AddPair('document_name', aMediaFile.Filename);
      LDocumentObj.AddPair('type', TJSONString.Create('document_url'));

    end;

    LJsonObject.AddPair('document', LDocumentObj);

    // Optional parameters
    LJsonObject.AddPair('include_image_base64', TJSONBool.Create(FOcrIncludeImages));

    // OCR 4: structural blocks with bounding boxes per page
    if FOcrIncludeBlocks then
      LJsonObject.AddPair('include_blocks', TJSONBool.Create(True));

    // Pages
    LPagesArray := TJSonArray.Create;
    try
      // Check if OcrAnnotationPages is empty
      if not OcrAnnotationPages.IsEmpty then
      begin
        // Split the OcrAnnotationPages string by commas to get page numbers
        PageNumbers := SplitString(OcrAnnotationPages, ',');

        // Iterate over page numbers and add them to the JSON array
        for PageNumber in PageNumbers do
        begin
          // Trim whitespace from the page number

          // Check if the page number is a valid integer
          if TryStrToInt(Trim(PageNumber), PageIndex) then
          begin
            // Add the page number to the JSON array
            LPagesArray.Add(PageIndex);
          end
          else
          begin
            // Handle invalid page number (optional)
            DoError('Invalid page number: ' + PageNumber, nil);
          end;
        end;
      end
      else
      begin
        // If no pages specified, add the first page (page 0)
        LPagesArray.Add(0);
      end;
      LJsonObject.AddPair('pages', LPagesArray);
    finally
      // LPagesArray.Free; //Managed by LJsonObject
    end;

    // Annotations
    if (Assigned(OcrDocumentAnnotationSchema) and (OcrDocumentAnnotationSchema.Text <> '')) then
    begin
      LDocumentAnnotationFormatObj := TJSONObject.Create;
      LDocumentAnnotationFormatObj.AddPair('type', 'json_schema');
      LDocumentAnnotationFormatObj.AddPair('json_schema', TJSONObject.ParseJSONValue(OcrDocumentAnnotationSchema.Text));
      // I assume OcrDocumentAnnotationSchema is a Json string
      LJsonObject.AddPair('document_annotation_format', LDocumentAnnotationFormatObj);

    end;

    // bbox_annotation_format
    // Only supports json_schema

    // document_annotation_format
    // Only supports json_schema

    // 3. Make the POST request to the API
    ResMsg.Prompt := LJsonObject.ToString; // Save the request
    LBodyStream.WriteString(LJsonObject.ToString);
    LBodyStream.Position := 0;

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

{$IFDEF APIDEBUG}
    LResponseStream.SaveToFile('c:\temp\response_OCR.txt'); // For Debug
    LResponseStream.Position := 0;
{$ENDIF}
    // 4. Process response
    LResponseStream.Position := 0;
    if LResponse.StatusCode = 200 then
    begin
      LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;

      try
        Result := ParseOcrResponse(LResponseObj, ResMsg);

        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, nil, 'assistant', '');

        // Move the content of aMediaFile to ResMsg
        FLastContent := ResMsg.Prompt;
        aMediaFile.CloudState := 'ocr-completed';
      finally
        LResponseObj.Free;
      end;
    end
    else
    begin
      FLastError := LResponse.ContentAsString;
      aMediaFile.CloudState := Format('ocr-failed: http-%d', [LResponse.StatusCode]);
      DoError(Format('Error in OCR: %d - %s', [LResponse.StatusCode, FLastError]), nil);
    end;

  finally
    LBodyStream.Free;
    LResponseStream.Free;
    LJsonObject.Free; // LDocumentObj belongs to LJsonObject
    if Assigned(LBboxAnnotationFormatObj) then
      LBboxAnnotationFormatObj.Free;
    if Assigned(LDocumentAnnotationFormatObj) then
      LDocumentAnnotationFormatObj.Free;
    FBusy := False;
  end;
end;

function TAiMistralChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
var
  LBaseModel: String;
  MF: TAiMediaFile;
begin
  // mistral-ocr-latest does not support the /v1/chat/completions endpoint.
  // If Phase 1 (InternalRunPDFDescription) already executed OCR successfully
  // (CloudState = 'ocr-completed'), return the result directly.
  LBaseModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LBaseModel = 'mistral-ocr-latest' then
  begin
    if Assigned(AskMsg) then
      for MF in AskMsg.MediaFiles do
        if (MF.FileCategory = Tfc_Pdf) and (MF.CloudState = 'ocr-completed') then
        begin
          Result := ResMsg.Prompt;
          Exit;
        end;
  end;
  Result := inherited InternalRunCompletions(ResMsg, AskMsg);
end;

function TAiMistralChat.ParseOcrResponse(jResponse: TJSONObject; ResMsg: TAiChatMessage): string;
var
  jPages: TJSonArray;
  jPage, jImage: TJSONObject;
  pageValue, blockValue: TJSonValue;
  sb: TStringBuilder;
  I: integer;
  imageB64, imageId: string;
  embeddedImage: TAiMediaFile;
  jImagesArray: TJSonArray;
  topLeftX, topLeftY, bottomRightX, bottomRightY: integer; // For coordinates
begin
  Result := '';
  if not Assigned(jResponse) or not Assigned(ResMsg) then
    Exit;

  // The aMediaFile object already exists, clean it in case of previous data.
  // aMediaFile.Transcription := '';
  // aMediaFile.Detail := '';
  // Clear nested MediaFiles (images extracted from OCR)
  // aMediaFile.MediaFiles.Clear;

  sb := TStringBuilder.Create;
  try
    // The main response is an object containing an array 'pages'.
    if not jResponse.TryGetValue<TJSonArray>('pages', jPages) then
    begin
      // If structure is not as expected, return raw JSON.
      Result := jResponse.Format;
      ResMsg.Prompt := Result; // Save error detail.
      Exit;
    end;

    // Iterate over each page of the document.

    for pageValue in jPages do
    begin

      if not(pageValue is TJSONObject) then
        continue;
      jPage := pageValue as TJSONObject;

      // Each page has a "markdown" field with already formatted Markdown.
      // This is the fastest and simplest way to get the text.
      if jPage.TryGetValue('markdown', blockValue) then // MODIFIED from content to markdown
      begin
        sb.AppendLine(blockValue.Value);
        sb.AppendLine('--- Page Break ---'); // Add a page separator.
      end;

      // Additionally, process structured data if needed,
      // such as embedded images in the document.
      jImagesArray := TJSonArray.Create; // Create the object

      if jPage.TryGetValue<TJSonArray>('images', jImagesArray) then
      begin
        for I := 0 to jImagesArray.Count - 1 do
        begin
          if not(jImagesArray.Items[I] is TJSONObject) then
            continue;
          jImage := jImagesArray.Items[I] as TJSONObject;

          // Extract image information
          if jImage.TryGetValue<string>('id', imageId) then;
          if jImage.TryGetValue<integer>('top_left_x', topLeftX) then;
          if jImage.TryGetValue<integer>('top_left_y', topLeftY) then;
          if jImage.TryGetValue<integer>('bottom_right_x', bottomRightX) then;
          if jImage.TryGetValue<integer>('bottom_right_y', bottomRightY) then;

          // The API returns the image in Base64 if 'include_image_base64' was true.
          if jImage.TryGetValue<string>('image_base64', imageB64) and (imageB64 <> '') then
          begin

            Var
            PosBase64 := Pos(';base64,', imageB64);
            Var
              Base64Data: String;

            if PosBase64 > 0 then
              Base64Data := Copy(imageB64, PosBase64 + Length(';base64,'), Length(imageB64))
            else
              Base64Data := imageB64; // If prefix not found, use the string
            // Create a new TAiMediaFile for the extracted image.
            embeddedImage := TAiMediaFile.Create;
            try
              // Give it a descriptive name.
              embeddedImage.LoadFromBase64(imageId, Base64Data); // Use the image id as name
              // embeddedImage.MimeType := imageMimeType;

              // Add additional information to the image description
              embeddedImage.Detail := Format('top_left_x: %d, top_left_y: %d, bottom_right_x: %d, bottom_right_y: %d', [topLeftX, topLeftY, bottomRightX, bottomRightY]);

              // Add the extracted image to the media files list of the main document.
              ResMsg.MediaFiles.Add(embeddedImage);
            except
              embeddedImage.Free;
              // Handle error if necessary.
            end;
          end;
        end;
      end;
    end;

    // The main result is the concatenated Markdown content of all pages.
    Result := sb.ToString;

    // Save the text in the corresponding properties of TAiMediaFile.
    // Use 'Transcription' for the main text.
    ResMsg.Prompt := Result;

  finally
    sb.Free;
  end;
end;

function TAiMistralChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  Body: TMultipartFormData;
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  sUrl: String;
  Res: IHTTPResponse;
  LResponseStream: TMemoryStream;
  LTempStream: TMemoryStream;
  LResponseObj: TJSonObject;
  Granularities: TStringList;
  I: Integer;
  LModel: String;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('An audio file with content is needed for transcription.');

  sUrl := Url + 'audio/transcriptions';
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 34}
  Client.SynchronizeEvents := False;
{$ENDIF}
  LResponseStream := TMemoryStream.Create;
  Body := TMultipartFormData.Create;
  Granularities := TStringList.Create;
  LTempStream := TMemoryStream.Create;
  try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    aMediaFile.Content.Position := 0;
    LTempStream.LoadFromStream(aMediaFile.Content);
    LTempStream.Position := 0;

{$IF CompilerVersion >= 36}
    Body.AddStream('file', LTempStream, False, aMediaFile.FileName, aMediaFile.MimeType);
{$ELSE}
    Body.AddStream('file', LTempStream, aMediaFile.FileName, aMediaFile.MimeType);
{$ENDIF}
    Body.AddField('model', LModel);

    if not AskMsg.Prompt.IsEmpty then
      Body.AddField('prompt', AskMsg.Prompt);

    if not TranscriptionParams.ResponseFormat.IsEmpty then
      Body.AddField('response_format', TranscriptionParams.ResponseFormat)
    else
      Body.AddField('response_format', 'json');

    if not TranscriptionParams.Language.IsEmpty then
      Body.AddField('language', TranscriptionParams.Language);

    if Self.Temperature > 0 then
      Body.AddField('temperature', FormatFloat('0.0', Self.Temperature));

    if not TranscriptionParams.TimestampGranularities.IsEmpty then
    begin
      Granularities.CommaText := TranscriptionParams.TimestampGranularities;
      for I := 0 to Granularities.Count - 1 do
        Body.AddField('timestamp_granularities[]', Trim(Granularities[I]));
    end;

    Res := Client.Post(sUrl, Body, LResponseStream, Headers);

    if Res.StatusCode = 200 then
    begin
      LResponseObj := TJSonObject.ParseJSONValue(Res.ContentAsString) as TJSonObject;
      if not Assigned(LResponseObj) then
        LResponseObj := TJSonObject.Create(TJSonPair.Create('text', Res.ContentAsString));
      try
        ParseJsonTranscript(LResponseObj, ResMsg, aMediaFile);
      finally
        LResponseObj.Free;
      end;
      Result := ResMsg.Prompt;
    end
    else
      raise Exception.CreateFmt('Error in transcription: %d, %s', [Res.StatusCode, Res.ContentAsString]);

  finally
    Body.Free;
    Client.Free;
    LResponseStream.Free;
    LTempStream.Free;
    Granularities.Free;
  end;
end;

Initialization

TAiChatFactory.Instance.RegisterDriver(TAiMistralChat);

end.
