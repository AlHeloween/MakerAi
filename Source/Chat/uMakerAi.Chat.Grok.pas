unit uMakerAi.Chat.Grok;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Threading,
  System.Variants, System.Net.Mime, System.IOUtils, System.Generics.Collections,
  System.NetEncoding,
  System.JSON, System.StrUtils, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent,
  REST.JSON, REST.Types, REST.Client,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Embeddings, uMakerAi.Core, uMakerAi.Chat.Messages;

Type

  TAiGrokChat = Class(TAiChat)
  Private
    FVideoDurationSeconds: Integer;
  Protected
    Function InitChatCompletions: String; Override;
    function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;

  Public
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;
  Published
    // Duration of the video generated with grok-imagine-video (max 15 seconds per xAI docs)
    property VideoDurationSeconds: Integer read FVideoDurationSeconds write FVideoDurationSeconds default 5;
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://api.x.ai/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGrokChat]);
end;

{ TAiGrokChat }

class function TAiGrokChat.GetDriverName: string;
Begin
  Result := 'Grok';
End;

class procedure TAiGrokChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@GROK_API_KEY');
  Params.Add('Model=grok-4.3');
  Params.Add('Max_Tokens=4096');
  Params.Add('URL=https://api.x.ai/v1/');
End;

class function TAiGrokChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiGrokChat.Create(Sender);
End;

constructor TAiGrokChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@GROK_API_KEY';
  // grok-3 was removed from the API (Aug 2026); grok-4.3 is the production model
  Model := 'grok-4.3';
  FVideoDurationSeconds := 5;
  Url := GlAIUrl;
end;

destructor TAiGrokChat.Destroy;
begin

  inherited;
end;

function TAiGrokChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel: String;
  LIsRestrictedModel, LSupportsReasoningEffort, LLegacyReasoningEffort: Boolean;
begin

  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'grok-4.3';

  // All current family (grok-4.x, grok-build) forbids frequency/presence/stop.
  // grok-3-mini/grok-code-fast-1 are kept in case the user points to a
  // endpoint compatible with older models.
  LIsRestrictedModel       := LModel.StartsWith('grok-4') or LModel.StartsWith('grok-build') or
                              LModel.StartsWith('grok-3-mini') or (LModel = 'grok-code-fast-1');
  // reasoning_effort. Measured against api.x.ai on 2026-10-01: grok-4.3, 4.6 and 4.7
  // accept low / medium / high / xhigh; grok-build-0.1 REJECTS it with 400
  // ("does not support parameter reasoningEffort"). Previously it was only sent to
  // grok-3-mini and the level requested by the client for a grok-4 was lost in
  // silence. grok-3-mini (removed) only knew low/high.
  LLegacyReasoningEffort   := LModel.StartsWith('grok-3-mini');
  LSupportsReasoningEffort := LModel.StartsWith('grok-4') or LLegacyReasoningEffort;

  LAsincronico := Self.Asynchronous;

  FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  Try

    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    // In streaming, xAI only sends the usage block if requested (measured on
    // 2026-09-28): without this, the turn ended with Prompt_tokens =
    // Completion_tokens = 0 and whoever bills by tokens charged zero.
    if LAsincronico then
    begin
      var jStreamOpts := TJSonObject.Create;
      jStreamOpts.AddPair('include_usage', TJSONBool.Create(True));
      AJSONObject.AddPair('stream_options', jStreamOpts);
    end;

    If Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAI).Text) <> '') then
    Begin

{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAI).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAI).Text));
{$ENDIF}
      If Not Assigned(JArr) then
        Raise Exception.Create('The Tools property is malformed, it must be a JsonArray');
      AJSONObject.AddPair('tools', JArr);

      If (Trim(Tool_choice) <> '') then
      Begin

{$IF CompilerVersion < 35}
        jToolChoice := TJSONUtils.ParseAsObject(Tool_choice);
{$ELSE}
        jToolChoice := TJSonObject(TJSonArray.ParseJSONValue(Tool_choice));
{$ENDIF}
        If Assigned(jToolChoice) then
          AJSONObject.AddPair('tool_choice', jToolChoice);
      End;
    End;

    AJSONObject.AddPair('messages', GetMessages);

    AJSONObject.AddPair('model', LModel);

    AJSONObject.AddPair('temperature', TJSONNumber.Create(Trunc(Temperature * 100) / 100));
    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));

    If Top_p <> 0 then
      AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

    // frequency_penalty and presence_penalty forbidden in grok-4 series, grok-3-mini and grok-code-fast-1
    if (not LIsRestrictedModel) and (Frequency_penalty <> 0) then
      AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Trunc(Frequency_penalty * 100) / 100));
    if (not LIsRestrictedModel) and (Presence_penalty <> 0) then
      AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Trunc(Presence_penalty * 100) / 100));

    if ModelConfig.Format <> '' then
      AJSONObject.AddPair('reasoning_format', ModelConfig.Format); // 'parsed, raw, hidden';

    // reasoning_effort (see LSupportsReasoningEffort). xAI ladder:
    // low / medium / high (default) / xhigh. tlNone does not exist in xAI (all grok-4
    // always reason): send the minimum, low. tlDefault sends nothing.
    if LSupportsReasoningEffort and (ModelConfig.ThinkingLevel <> tlDefault) then
    begin
      if LLegacyReasoningEffort then
      begin
        // grok-3-mini only knew low/high
        case ModelConfig.ThinkingLevel of
          tlNone, tlMinimal, tlLow, tlMedium: AJSONObject.AddPair('reasoning_effort', 'low');
          tlHigh, tlXHigh, tlMax:             AJSONObject.AddPair('reasoning_effort', 'high');
        end;
      end
      else
        case ModelConfig.ThinkingLevel of
          tlNone, tlMinimal, tlLow: AJSONObject.AddPair('reasoning_effort', 'low');
          tlMedium:                 AJSONObject.AddPair('reasoning_effort', 'medium');
          tlHigh:                   AJSONObject.AddPair('reasoning_effort', 'high');
          tlXHigh, tlMax:           AJSONObject.AddPair('reasoning_effort', 'xhigh');
        end;
    end;

    AJSONObject.AddPair('user', User);
    AJSONObject.AddPair('n', TJSONNumber.Create(N));

    if cap_WebSearch in ModelConfig.ModelCaps then
    begin
      Var
      jWebSearchOptions := TJSonObject.Create;
      jWebSearchOptions.AddPair('mode', 'auto');
      // jWebSearchOptions.AddPair('return_citations', 'true');
      AJSONObject.AddPair('search_parameters', jWebSearchOptions);
    end;

    if FResponse_format = tiaChatRfJsonSchema then
    begin
      // ParseJsonSchemaProperty accepts the pure schema or the wrapper {name, strict,
      // schema} and fails with a clear error if JsonSchema is empty.
      var sSchemaName := 'structured_response';
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
      AJSONObject.AddPair('response_format', TJSONObject.Create.AddPair('type', 'json_object'));

    // stop forbidden in grok-4 series, grok-3-mini and grok-code-fast-1
    if not LIsRestrictedModel then
    begin
      Lista.CommaText := Stop;
      If Lista.Count > 0 then
      Begin
        JStop := TJSonArray.Create;
        For I := 0 to Lista.Count - 1 do
          JStop.Add(Lista[I]);
        AJSONObject.AddPair('stop', JStop);
      End;
    end;

    If Logprobs = True then
    Begin
      If Logit_bias <> '' then
        AJSONObject.AddPair('logit_bias', TJSONNumber.Create(Logit_bias));

      AJSONObject.AddPair('logprobs', TJSONBool.Create(Logprobs));

      If Top_logprobs <> '' then
        AJSONObject.AddPair('top_logprobs', TJSONNumber.Create(Top_logprobs));
    End;

    If Seed > 0 then
      AJSONObject.AddPair('seed', TJSONNumber.Create(Seed));

    // Like the base class: without this ModelConfig.ModelExtraBodyParams never
    // reached Grok because this override did not call it.
    ApplyExtraBodyParams(AJSONObject);

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

// xAI API responses for web search
// search_parameters was deprecated in January 2026 (returns 410 "Live search is deprecated").
// New API: POST /v1/responses with tools=[{type:"web_search"}]
// Response format: output[].type="message" → content[].type="output_text" → text
function TAiGrokChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
var
  ABody, sUrl, SType, SVal, sRole, sContent: String;
  Res: IHTTPResponse;
  FHeaders: TNetHeaders;
  jReq, jRes, jItem, jContentItem: TJSonObject;
  jInput, jMessages, jOutput, jContent, jTools: TJSonArray;
  jTool: TJSonObject;
  St: TStringStream;
  LModel: String;
  I, K: Integer;
begin
  // Without web search active → normal chat/completions flow
  if not (cap_WebSearch in ModelConfig.ModelCaps) then
  begin
    Result := inherited InternalRunCompletions(ResMsg, AskMsg);
    Exit;
  end;

  // Web search active → xAI Agent Tools API (POST /v1/responses)
  FBusy        := True;
  FAbort       := False;
  FLastError   := '';
  FLastContent := '';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LModel = '' then
    LModel := 'grok-4.3';

  sUrl := Url;
  if not sUrl.EndsWith('/') then
    sUrl := sUrl + '/';
  sUrl := sUrl + 'responses';

  jInput    := nil;
  jMessages := nil;
  jTools    := nil;
  jTool     := nil;
  jReq      := nil;
  St        := nil;
  try
    // Build input: messages from history with "system" → "developer"
    jInput    := TJSonArray.Create;
    jMessages := GetMessages;
    for I := 0 to jMessages.Count - 1 do
    begin
      var jOrig := jMessages.Items[I] as TJSonObject;
      var jNew  := TJSonObject.Create;
      jOrig.TryGetValue<String>('role', sRole);
      if sRole = 'system' then
        jNew.AddPair('role', 'developer')
      else
        jNew.AddPair('role', sRole);
      if jOrig.TryGetValue<String>('content', sContent) then
        jNew.AddPair('content', sContent)
      else
      begin
        var jCont: TJSONValue;
        if jOrig.TryGetValue<TJSONValue>('content', jCont) then
          jNew.AddPair('content', TJSONObject.ParseJSONValue(jCont.ToJSON));
      end;
      jInput.Add(jNew);
    end;
    FreeAndNil(jMessages);

    // Build request body
    jTools := TJSonArray.Create;
    jTool  := TJSonObject.Create;
    jTool.AddPair('type', 'web_search');
    jTools.Add(jTool); jTool := nil;

    jReq := TJSonObject.Create;
    jReq.AddPair('model',  LModel);
    jReq.AddPair('input',  jInput);  jInput := nil;
    jReq.AddPair('tools',  jTools);  jTools := nil;
    jReq.AddPair('stream', TJSONBool.Create(False));

    ABody := jReq.ToJSON;
    St    := TStringStream.Create(ABody, TEncoding.UTF8);

    FHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType  := 'application/json';
    FClient.Asynchronous := False;
    FResponse.Clear;
    DoStateChange(acsConnecting, 'Sending web search...');

    Res := FClient.Post(sUrl, St, FResponse, FHeaders);

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

    if Res.StatusCode = 200 then
    begin
      var LParsed := TJSonObject.ParseJSONValue(Res.ContentAsString);
      if not (LParsed is TJSonObject) then
      begin
        LParsed.Free;
        raise Exception.CreateFmt('Invalid JSON response: %s', [Res.ContentAsString]);
      end;
      jRes := TJSonObject(LParsed);
      try
        FLastContent := '';
        if jRes.TryGetValue<TJSonArray>('output', jOutput) then
          for I := 0 to jOutput.Count - 1 do
          begin
            if not (jOutput.Items[I] is TJSonObject) then Continue;
            jItem := jOutput.Items[I] as TJSonObject;
            if not jItem.TryGetValue<String>('type', SType) then Continue;
            if SType = 'message' then
              if jItem.TryGetValue<TJSonArray>('content', jContent) then
                for K := 0 to jContent.Count - 1 do
                begin
                  if not (jContent.Items[K] is TJSonObject) then Continue;
                  jContentItem := jContent.Items[K] as TJSonObject;
                  if jContentItem.TryGetValue<String>('type', SVal) and (SVal = 'output_text') then
                    if jContentItem.TryGetValue<String>('text', SVal) then
                      FLastContent := FLastContent + SVal;
                end;
          end;
        ResMsg.Prompt := FLastContent;
        FBusy         := False;
        Result        := FLastContent;
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, jRes, 'assistant', FLastContent);
      finally
        FreeAndNil(jRes);
      end;
    end
    else
      raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
  finally
    FreeAndNil(jMessages);
    FreeAndNil(jInput);
    FreeAndNil(jTools);
    FreeAndNil(jTool);
    FreeAndNil(jReq);
    FreeAndNil(St);
  end;
end;

function TAiGrokChat.InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LBodyJson, LResponseJson, LImageObject: TJSonObject;
  LDataArray: TJSonArray;
  LBodyStream: TStringStream;
  LUrl: String;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LNewMediaFile: TAiMediaFile;
  LImageUrl, LRevisedPrompt, LBase64Data: string;
  LModel: String;
begin
  Result := ''; // The main output is the MediaFile in ResMsg
  FBusy := True;
  FAbort := False;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  // 1. Validation and configuration
  if AskMsg.Prompt.IsEmpty then
    raise Exception.Create('A prompt is required to generate an image.');

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  if LModel = '' then
    LModel := 'grok-imagine-image'; // Default for image (grok-2-image was removed)

  LUrl := Url + 'images/generations'; // Base URL + endpoint

  // 2. Build the JSON request body
  LBodyJson := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LBodyJson.AddPair('prompt', AskMsg.Prompt);
    LBodyJson.AddPair('model', LModel);

    if Self.N > 0 then
      LBodyJson.AddPair('n', TJSONNumber.Create(Self.N));

    // if not Self.ImageResponseFormat.IsEmpty then
    // LBodyJson.AddPair('response_format', Self.ImageResponseFormat);

    // 3. Prepare and execute the HTTP call
    LBodyStream.WriteString(LBodyJson.ToJSON);
    LBodyStream.Position := 0;
{$IFDEF APIDEBUG}
    LBodyStream.SaveToFile('c:\temp\grok_image_request.json');
    LBodyStream.Position := 0;
{$ENDIF}
    // Grok uses Bearer token for authorization
    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';
    FResponse.Clear;

    LResponse := FClient.Post(LUrl, LBodyStream, FResponse, LHeaders);

    // 4. Process the response
    FResponse.Position := 0;
    FLastContent := LResponse.ContentAsString(TEncoding.UTF8);
{$IFDEF APIDEBUG}
    FResponse.SaveToFile('c:\temp\grok_image_response.json');
{$ENDIF}
    if LResponse.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject.ParseJSONValue(FLastContent) as TJSonObject;
      try
        if LResponseJson.TryGetValue<TJSonArray>('data', LDataArray) then
        begin
          for var LJsonValue in LDataArray do
          begin
            if not(LJsonValue is TJSonObject) then
              continue;

            LImageObject := LJsonValue as TJSonObject;
            LNewMediaFile := TAiMediaFile.Create;
            try
              // Extract the revised prompt and save it (it's useful information)
              LImageObject.TryGetValue<string>('revised_prompt', LRevisedPrompt);
              LNewMediaFile.Transcription := LRevisedPrompt;
              FLastContent := LRevisedPrompt;
              ResMsg.Prompt := FLastContent;

              // CASE A: The response is a URL
              if LImageObject.TryGetValue<string>('url', LImageUrl) then
              begin
                // Download the image from the URL and load it into the MediaFile
                // You'll need a function to download, for example:
                LNewMediaFile.LoadFromUrl(LImageUrl); // Assuming you have this function
              end
              // CASE B: The response is Base64
              else if LImageObject.TryGetValue<string>('b64_json', LBase64Data) then
              begin
                LNewMediaFile.LoadFromBase64('generated_image.png', LBase64Data);
              end;

              // Add the MediaFile to the response message
              ResMsg.MediaFiles.Add(LNewMediaFile);
            except
              LNewMediaFile.Free;
              raise;
            end;
          end;
        end;

        // Trigger the completion event
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, LResponseJson, 'model', '');

      finally
        LResponseJson.Free;
      end;
    end
    else
    begin
      FLastError := Format('Error generating image with Grok: %d, %s', [LResponse.StatusCode, FLastContent]);
      DoError(FLastError, nil);
    end;

  finally
    LBodyJson.Free;
    LBodyStream.Free;
    FBusy := False;
  end;
end;

function TAiGrokChat.InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
// grok-imagine-video (Aug 2026): asynchronous job with polling.
// POST /v1/videos/generations {model, prompt, duration} -> request_id
// GET  /v1/videos/{request_id} -> status pending|done|failed|expired + video.url
// The final video is downloaded and attached as TAiMediaFile (mp4) in ResMsg.
const
  POLL_INTERVAL_MS = 3000;
  TIMEOUT_MS       = 300000; // 5 min: a 15-second video takes ~1-3 min
var
  LModel, LUrl, LRequestId, LStatus, LVideoUrl: string;
  LBodyJson, LRespJson, LVideoObj: TJSonObject;
  LBodyStream: TStringStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LNewMediaFile: TAiMediaFile;
  LElapsed: Integer;
begin
  Result := '';
  FBusy := True;
  FAbort := False;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  if AskMsg.Prompt.IsEmpty then
    raise Exception.Create('A prompt is required to generate a video.');

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if (LModel = '') or (not LModel.StartsWith('grok-imagine-video')) then
    LModel := 'grok-imagine-video';

  LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
  FClient.ContentType := 'application/json';

  LBodyJson := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  try
    try
      // 1. Start the job
      LBodyJson.AddPair('model', LModel);
      LBodyJson.AddPair('prompt', AskMsg.Prompt);
      if FVideoDurationSeconds > 0 then
        LBodyJson.AddPair('duration', TJSONNumber.Create(FVideoDurationSeconds));

      LBodyStream.WriteString(LBodyJson.ToJSON);
      LBodyStream.Position := 0;

      FResponse.Clear;
      LResponse := FClient.Post(Url + 'videos/generations', LBodyStream, FResponse, LHeaders);
      if LResponse.StatusCode <> 200 then
        raise Exception.CreateFmt('Error starting video with Grok: %d, %s',
          [LResponse.StatusCode, LResponse.ContentAsString(TEncoding.UTF8)]);

      LRespJson := TJSonObject.ParseJSONValue(LResponse.ContentAsString(TEncoding.UTF8)) as TJSonObject;
      try
        if not LRespJson.TryGetValue<string>('request_id', LRequestId) then
          raise Exception.Create('The videos/generations response does not contain request_id');
      finally
        LRespJson.Free;
      end;

      // 2. Polling until done/failed/expired
      DoStateChange(acsToolExecuting, 'Generating video (job ' + LRequestId + ')...');
      LElapsed := 0;
      LStatus := 'pending';
      LVideoUrl := '';
      while (LElapsed < TIMEOUT_MS) and not FAbort do
      begin
        TThread.Sleep(POLL_INTERVAL_MS);
        Inc(LElapsed, POLL_INTERVAL_MS);

        FResponse.Clear;
        LResponse := FClient.Get(Url + 'videos/' + LRequestId, FResponse, LHeaders);
        if LResponse.StatusCode <> 200 then
          Continue; // transient polling error: retry until timeout

        LRespJson := TJSonObject.ParseJSONValue(LResponse.ContentAsString(TEncoding.UTF8)) as TJSonObject;
        try
          if Assigned(LRespJson) then
          begin
            LRespJson.TryGetValue<string>('status', LStatus);
            if (LStatus = 'done') and LRespJson.TryGetValue<TJSonObject>('video', LVideoObj) then
              LVideoObj.TryGetValue<string>('url', LVideoUrl);
          end;
        finally
          LRespJson.Free;
        end;

        if (LStatus = 'done') or (LStatus = 'failed') or (LStatus = 'expired') then
          Break;
      end;

      if FAbort then
        Exit;
      if LStatus <> 'done' then
        raise Exception.CreateFmt('Video generation not completed (status=%s after %d seconds)',
          [LStatus, LElapsed div 1000]);
      if LVideoUrl = '' then
        raise Exception.Create('The job ended with done but does not include video.url');

      // 3. Download the video and attach it to the message
      LNewMediaFile := TAiMediaFile.Create;
      try
        LNewMediaFile.LoadFromUrl(LVideoUrl);
        LNewMediaFile.Transcription := AskMsg.Prompt;
        ResMsg.MediaFiles.Add(LNewMediaFile);
      except
        LNewMediaFile.Free;
        raise;
      end;

      FLastContent := LVideoUrl;
      ResMsg.Prompt := LVideoUrl;
      Result := LVideoUrl;

      if Assigned(FOnReceiveDataEnd) then
        FOnReceiveDataEnd(Self, ResMsg, nil, 'model', FLastContent);
    except
      on E: Exception do
      begin
        FLastError := E.Message;
        DoError(FLastError, E);
      end;
    end;
  finally
    LBodyJson.Free;
    LBodyStream.Free;
    FBusy := False;
  end;
end;

Initialization

TAiChatFactory.Instance.RegisterDriver(TAiGrokChat);

end.
