unit uMakerAi.Chat.MakerAi;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils,
  System.Generics.Collections, System.NetEncoding,
  System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent, REST.Types, REST.Client,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}

  uMakerAi.ParamsRegistry,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Core;

type
  TAiMakerAiChat = class(TAiChat)
  private
    FSessionId:          string;
    FOnProgress:         TProc<string, string, Integer>;
    FFileReaderSlug:     string;
    FFileReaderId:       Integer;
    FPendingMediaParts:  TList<TAiMediaFile>;
    // REAL usage seen in SSE chunks. The synthetic stream closure
    // filled usage with fixed zeros, so with streaming the token
    // counters of the ENTIRE application stayed at zero (the CLI showed 0 in
    // /tokens and there was no way to measure consumption). The server DOES send it,
    // in the penultimate chunk; we just had to keep it.
    FStreamPromptTok:    Integer;
    FStreamComplTok:     Integer;
    FStreamTotalTok:     Integer;
    // prompt_tokens_details.cached_tokens from the stream: the broker DOES send it
    // (measured 2026-09-05: 1828 out of 1831 in cache), but the synthetic closure
    // discarded it and in streaming Cached_tokens was always zero — without it there is
    // no way to know if the prefix cache is serving or not.
    FStreamCachedTok:    Integer;
    procedure ResetSessionId;
    procedure HandleStreamDone;
    procedure ParseAndAccumulateMediaParts(AMediaParts: TJSONArray);
    procedure ExtractMkFileBlocks(ResMsg: TAiChatMessage);
    procedure ExtractImageUrlContent(AContentArr: TJSonArray; ResMsg: TAiChatMessage);
    procedure ClearPendingMediaParts;
  protected
    Function InitChatCompletions: String; Override;
    Procedure ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage); Override;
    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;
    Procedure OnRequestCompletedEvent(const Sender: TObject; const aResponse: IHTTPResponse); Override;
  public
    constructor Create(Sender: TComponent); override;
    destructor Destroy; override;
    Procedure NewChat; Override;
    class function GetDriverName: string; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
    class function CreateInstance(Sender: TComponent): TAiChat; override;
    // Reports progress while the server processes a PDF:
    //   step  = 'extracting' | 'embedding' | 'querying'
    //   aFile = file name
    //   pct   = progress percentage for the step (0-100)
    property OnProgress: TProc<string, string, Integer> read FOnProgress write FOnProgress;
    // RAG: slug or ID of the knowledge base to connect via mk_tools.file_reader.
    // If FileReaderSlug <> '' the slug is used; if FileReaderId > 0 the ID is used.
    property FileReaderSlug: string  read FFileReaderSlug write FFileReaderSlug;
    property FileReaderId:   Integer read FFileReaderId   write FFileReaderId;
  published
  end;

procedure Register;

implementation

const
  GlMakerAiUrl = 'https://api.cimamaker.com/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiMakerAiChat]);
end;

procedure MKLog(const Tag, Msg: string);
begin
  LogDebug('[MakerAI ' + FormatDateTime('hh:nn:ss.zzz', Now) + '][' + Tag + '] ' + Msg);
end;

{ TAiMakerAiChat }

class function TAiMakerAiChat.GetDriverName: string;
begin
  Result := 'MakerAi';
end;

class procedure TAiMakerAiChat.RegisterDefaultParams(Params: TStrings);
begin
  Params.Clear;
  Params.Add('ApiKey=@MAKERAI_API_KEY');
  Params.Add('Model=mk-gpt-oss-20b');
  Params.Add('Max_Tokens=16000');
  Params.Add('Temperature=1');
  Params.Add('URL=' + GlMakerAiUrl);
  Params.Add('Tool_Active=True');
  Params.Add('Asynchronous=True');
  Params.Add('ModelCaps=[cap_Image]');
  Params.Add('SessionCaps=[cap_Image]');
end;

class function TAiMakerAiChat.CreateInstance(Sender: TComponent): TAiChat;
begin
  Result := TAiMakerAiChat.Create(Sender);
end;

procedure TAiMakerAiChat.ResetSessionId;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FSessionId := GUIDToString(LGuid);
end;

constructor TAiMakerAiChat.Create(Sender: TComponent);
begin
  inherited;
  Url := GlMakerAiUrl;  // overwrites the GlOpenAIUrl that the base class sets in Create
  // Same default as RegisterDefaultParams: without this it inherited the model
  // from TAiOpenChat (gpt-5 and later gpt-6-sol), which the broker does not serve
  Model := 'mk-gpt-oss-20b';
  ResetSessionId;
  FPendingMediaParts := TList<TAiMediaFile>.Create;
  FFileReaderId := 0;
end;

destructor TAiMakerAiChat.Destroy;
begin
  ClearPendingMediaParts;
  FPendingMediaParts.Free;
  inherited;
end;

Procedure TAiMakerAiChat.NewChat;
begin
  inherited NewChat;
  ResetSessionId;
  ClearPendingMediaParts;
end;

procedure TAiMakerAiChat.ClearPendingMediaParts;
var
  I: Integer;
begin
  for I := 0 to FPendingMediaParts.Count - 1 do
    FPendingMediaParts[I].Free;
  FPendingMediaParts.Clear;
end;

Function TAiMakerAiChat.InitChatCompletions: String;
var
  LJson: TJSonObject;
  LTools: TJSonArray;
  LPair: TJSonPair;
  LEffective: string;
  LChoiceVal: TJSonValue;
begin
  Result := inherited InitChatCompletions;

  // Always parse: session_id is injected in every request; also mk_tools,
  // tool_choice and PDF file parts according to the active caps.
  LJson := TJSonObject.ParseJSONValue(Result) as TJSonObject;
  if Assigned(LJson) then
  try
    // Remove OpenAI fields not supported by the MKAI/Claude routing.
    // frequency_penalty, presence_penalty, n: Claude API rejects them.
    // top_p: Claude rejects if top_p and temperature are present simultaneously.
    // user: MKAI does not use it; response_format:text is redundant (default).
    LPair := LJson.RemovePair('frequency_penalty');
    if Assigned(LPair) then LPair.Free;
    LPair := LJson.RemovePair('presence_penalty');
    if Assigned(LPair) then LPair.Free;
    LPair := LJson.RemovePair('n');
    if Assigned(LPair) then LPair.Free;
    LPair := LJson.RemovePair('user');
    if Assigned(LPair) then LPair.Free;
    LPair := LJson.RemovePair('top_p');
    if Assigned(LPair) then LPair.Free;
    var LRfObj: TJSONObject;
    if LJson.TryGetValue<TJSONObject>('response_format', LRfObj) then
    begin
      var sRfType: string;
      if LRfObj.TryGetValue<string>('type', sRfType) and (sRfType = 'text') then
      begin
        LPair := LJson.RemovePair('response_format');
        if Assigned(LPair) then LPair.Free;
      end;
    end;

    // Build mk_tools if any cap requires it or a file_reader is configured.
    var LNeedsMkTools :=
      (cap_WebSearch      in SessionCaps) or
      (cap_CodeInterpreter in SessionCaps) or
      (cap_ComputerUse    in SessionCaps) or
      (cap_TextEditor     in SessionCaps) or
      (cap_Shell          in SessionCaps) or
      (cap_Memory         in SessionCaps) or
      (FFileReaderSlug <> '') or (FFileReaderId > 0);

    if LNeedsMkTools then
    begin
      LPair := LJson.RemovePair('mk_tools');
      if Assigned(LPair) then LPair.Free;
      // MKAI uses mk_tools for web search — the native OpenAI web_search_options field
      // is not recognized by the server and may interfere with routing.
      LPair := LJson.RemovePair('web_search_options');
      if Assigned(LPair) then LPair.Free;
      var LMkTools := TJSONObject.Create;
      if cap_WebSearch       in SessionCaps then LMkTools.AddPair('web_search',     TJSONBool.Create(True));
      if cap_CodeInterpreter in SessionCaps then LMkTools.AddPair('code_execution', TJSONBool.Create(True));
      if cap_ComputerUse     in SessionCaps then LMkTools.AddPair('computer_use',   TJSONBool.Create(True));
      if cap_TextEditor      in SessionCaps then LMkTools.AddPair('text_editor',    TJSONBool.Create(True));
      if cap_Shell           in SessionCaps then LMkTools.AddPair('bash',           TJSONBool.Create(True));
      if cap_Memory          in SessionCaps then LMkTools.AddPair('memory',         TJSONBool.Create(True));
      if FFileReaderSlug <> '' then
      begin
        var LFR := TJSONObject.Create;
        LFR.AddPair('encyclopedia_slug', FFileReaderSlug);
        LMkTools.AddPair('file_reader', LFR);
      end
      else if FFileReaderId > 0 then
      begin
        var LFR := TJSONObject.Create;
        LFR.AddPair('encyclopedia_id', TJSONNumber.Create(FFileReaderId));
        LMkTools.AddPair('file_reader', LFR);
      end;
      LJson.AddPair('mk_tools', LMkTools);
    end;

    // reasoning_effort: top-level parameter for models with ThinkingLevel configured.
    if ModelConfig.ThinkingLevel <> tlDefault then
    begin
      LPair := LJson.RemovePair('reasoning_effort');
      if Assigned(LPair) then LPair.Free;
      var sEffort: string;
      case ModelConfig.ThinkingLevel of
        tlLow:    sEffort := 'low';
        tlHigh:   sEffort := 'high';
      else        sEffort := 'medium'; // tlMedium and any other
      end;
      LJson.AddPair('reasoning_effort', sEffort);
    end;

    // Normalize tool_choice: base class serializes it as 'tools_choice' (typo) and
    // only handles JSON objects, not plain strings like "auto"/"required"/"none".
    if Tool_Active and
       LJson.TryGetValue<TJSonArray>('tools', LTools) and
       Assigned(LTools) and (LTools.Count > 0) then
    begin
      LPair := LJson.RemovePair('tool_choice');
      if Assigned(LPair) then LPair.Free;
      LPair := LJson.RemovePair('tools_choice');
      if Assigned(LPair) then LPair.Free;

      LEffective := Tool_choice;
      if LEffective = '' then LEffective := 'auto';

      LChoiceVal := TJSonObject.ParseJSONValue(LEffective); // ParseJSONValue is a class method of TJSONObject (not exposed by TJSonValue in D10.4)
      if Assigned(LChoiceVal) and (LChoiceVal is TJSonObject) then
        LJson.AddPair('tool_choice', LChoiceVal)
      else
      begin
        FreeAndNil(LChoiceVal);
        if (Length(LEffective) >= 2) and
           (LEffective[1] = '"') and (LEffective[Length(LEffective)] = '"') then
          LEffective := Copy(LEffective, 2, Length(LEffective) - 2);
        LJson.AddPair('tool_choice', LEffective);
      end;
    end;

    // Inject PDF file parts as {type:"file"} content parts.
    // ToJSon base leaves the Tfc_Pdf case empty; we complete it here.
    // FMessages[I] is 1:1 with messages[I] in the JSON (the system prompt lives in FMessages).
    if cap_Pdf in ModelCaps then
    begin
      var LMessages: TJSONArray;
      if LJson.TryGetValue<TJSONArray>('messages', LMessages) then
      begin
        for var LFIdx := 0 to FMessages.Count - 1 do
        begin
          if LFIdx >= LMessages.Count then Break;
          var LMsg      := FMessages[LFIdx];
          var LPdfFiles := LMsg.MediaFiles.GetMediaList([Tfc_Pdf], False);
          if Length(LPdfFiles) = 0 then Continue;

          var LJsonMsg := LMessages.Items[LFIdx] as TJSONObject;

          // content should be an array (cap_Pdf in ModelCaps makes ToJSon create JContent
          // even if the Tfc_Pdf case adds nothing to the array). Handle string as fallback.
          var LContent: TJSONArray;
          var LContentVal := LJsonMsg.GetValue('content');
          if LContentVal is TJSONArray then
            LContent := TJSONArray(LContentVal)
          else
          begin
            LContent := TJSONArray.Create;
            var LTextPart := TJSONObject.Create;
            LTextPart.AddPair('type', 'text');
            LTextPart.AddPair('text', LMsg.Prompt);
            LContent.Add(LTextPart);
            LPair := LJsonMsg.RemovePair('content');
            if Assigned(LPair) then LPair.Free;
            LJsonMsg.AddPair('content', LContent);
          end;

          for var LK := 0 to High(LPdfFiles) do
          begin
            var LMedia    := LPdfFiles[LK];
            var LFileName := ExtractFileName(LMedia.Filename);
            if LFileName = '' then LFileName := 'document.pdf';

            var LFileInner := TJSONObject.Create;
            LFileInner.AddPair('filename',  LFileName);
            LFileInner.AddPair('file_data',
              'data:' + LMedia.MimeType + ';base64,' + LMedia.Base64);
            var LFilePart := TJSONObject.Create;
            LFilePart.AddPair('type', 'file');
            LFilePart.AddPair('file', LFileInner);
            LContent.Add(LFilePart);
          end;
        end;
      end;
    end;

    // session_id: identifies the session; the server recovers context between turns.
    // It is renewed in NewChat to separate different conversations.
    LPair := LJson.RemovePair('session_id');
    if Assigned(LPair) then LPair.Free;
    LJson.AddPair('session_id', FSessionId);

    Result := LJson.ToJSON;
  finally
    LJson.Free;
  end;

  MKLog('REQUEST', Copy(Result, 1, 3000));
end;

Procedure TAiMakerAiChat.ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage);
var
  LChoices: TJSonArray;
  LFirstChoice: TJSonObject;
  LMessage: TJSonObject;
  LContent: String;
  LContentArr: TJSonArray;
  LToolCalls: TJSonValue;
  LUsage: TJSonObject;
  LCompletionTokens: Integer;
  LSavedHandler: TAiChatOnDataEvent;
  LHasMkFile: Boolean;
  LHasImageArr: Boolean;
begin
  MKLog('RESPONSE', Copy(jObj.ToJSON, 1, 3000));

  LContent     := '';
  LContentArr  := nil;
  LHasMkFile   := False;
  LHasImageArr := False;

  if jObj.TryGetValue<TJSonArray>('choices', LChoices) and
     Assigned(LChoices) and (LChoices.Count > 0) then
  begin
    LFirstChoice := LChoices.Items[0] as TJSonObject;
    if Assigned(LFirstChoice) and
       LFirstChoice.TryGetValue<TJSonObject>('message', LMessage) and
       Assigned(LMessage) then
    begin
      if LMessage.TryGetValue<String>('content', LContent) then
        LHasMkFile := Pos('```mk_file:', LContent) > 0
      else if LMessage.TryGetValue<TJSonArray>('content', LContentArr) and
              Assigned(LContentArr) then
        LHasImageArr := True   // content is array (e.g. image_url from mk-claude-sonnet)
      else
      begin
        // Diagnosis: tokens consumed but without content or tool_calls.
        if not LMessage.TryGetValue<TJSonValue>('tool_calls', LToolCalls) then
        begin
          LCompletionTokens := 0;
          if jObj.TryGetValue<TJSonObject>('usage', LUsage) and Assigned(LUsage) then
            LUsage.TryGetValue<Integer>('completion_tokens', LCompletionTokens);
          if LCompletionTokens > 0 then
            MKLog('SERVER-WARN',
              'content="" + no tool_calls + completion_tokens=' +
              IntToStr(LCompletionTokens) +
              ' — possible server bug');
        end;
      end;
    end;
  end;

  if LHasMkFile or LHasImageArr then
  begin
    LSavedHandler    := OnReceiveDataEnd;
    OnReceiveDataEnd := nil;
    try
      inherited ParseChat(jObj, ResMsg);
      if LHasMkFile then
      begin
        MKLog('MK_FILE-DETECT', 'extracting mk_file blocks from prompt...');
        ExtractMkFileBlocks(ResMsg);
        MKLog('MK_FILE-DONE', IntToStr(ResMsg.MediaFiles.Count) + ' file(s) extracted');
      end
      else
      begin
        MKLog('IMAGE_URL', 'extracting image_url from content array...');
        ExtractImageUrlContent(LContentArr, ResMsg);
        MKLog('IMAGE_URL-DONE', IntToStr(ResMsg.MediaFiles.Count) + ' file(s) extracted');
      end;
    finally
      OnReceiveDataEnd := LSavedHandler;
    end;
    if Assigned(LSavedHandler) then
      LSavedHandler(Self, ResMsg, jObj, ResMsg.Role, ResMsg.Prompt);
  end
  else
  begin
    inherited ParseChat(jObj, ResMsg);
    // ISSUE #99 (regression): in async mode the base class delegates the turn closure to the
    // [DONE] handler in OnInternalReceiveData. But this driver intercepts [DONE] itself
    // (-> HandleStreamDone) and skips that handler, so for plain content nobody
    // fires FOnReceiveDataEnd/acsFinished and the client hangs (DEADLINE). We fire it
    // here. Guard 'not FPendingToolRun': if the base left a deferred tool-calling
    // continuation (ISSUE #100), we do NOT close the turn in the middle of the agentic loop.
    if FClient.Asynchronous and (not FPendingToolRun) and Assigned(FOnReceiveDataEnd) then
    begin
      DoStateChange(acsFinished, 'Done');
      FOnReceiveDataEnd(Self, ResMsg, jObj, ResMsg.Role, ResMsg.Prompt);
    end;
  end;
end;

procedure TAiMakerAiChat.ExtractMkFileBlocks(ResMsg: TAiChatMessage);
const
  COpenTag  = '```mk_file:';
  CCloseTag = '```';
var
  LText, LResult, LHeader, LFilename, LMime, LB64: string;
  LPos, LFindPos, LHeaderEnd, LClosePos, LColonPos: Integer;
  LBytes: TBytes;
  LStream: TMemoryStream;
  LMF: TAiMediaFile;
begin
  LText := ResMsg.Prompt;
  if Pos(COpenTag, LText) = 0 then Exit;

  LResult := '';
  LPos    := 1;
  LFindPos := Pos(COpenTag, LText);
  while LFindPos > 0 do
  begin
    LResult := LResult + Copy(LText, LPos, LFindPos - LPos);

    LHeaderEnd := PosEx(#10, LText, LFindPos);
    if LHeaderEnd <= 0 then
    begin
      LResult := LResult + Copy(LText, LFindPos, MaxInt);
      LPos := Length(LText) + 1;
      Break;
    end;

    LHeader   := TrimRight(Copy(LText, LFindPos + Length(COpenTag),
                                LHeaderEnd - LFindPos - Length(COpenTag)));
    LColonPos := Pos(':', LHeader);
    if LColonPos > 0 then
    begin
      LFilename := Copy(LHeader, 1, LColonPos - 1);
      LMime     := Copy(LHeader, LColonPos + 1, MaxInt);
    end else
    begin
      LFilename := LHeader;
      LMime     := 'application/octet-stream';
    end;

    LClosePos := PosEx(CCloseTag, LText, LHeaderEnd + 1);
    if LClosePos <= 0 then
    begin
      // The server omitted the closing tag — everything from LHeaderEnd+1 to the end
      // is the base64 of the file.
      LB64      := Trim(Copy(LText, LHeaderEnd + 1, MaxInt));
      LPos      := Length(LText) + 1;  // to exit the while loop
      LClosePos := Length(LText) + 1;  // end-of-string indicator
    end
    else
      LB64 := Trim(Copy(LText, LHeaderEnd + 1, LClosePos - LHeaderEnd - 1));

    if LB64 <> '' then
    try
      LBytes := TNetEncoding.Base64.DecodeStringToBytes(LB64);
      if Length(LBytes) > 0 then
      begin
        LStream := TMemoryStream.Create;
        try
          LStream.Write(LBytes[0], Length(LBytes));
          LStream.Position := 0;
          LMF := TAiMediaFile.Create;
          LMF.LoadFromStream(LFilename, LStream);
          ResMsg.AddMediaFile(LMF);
          MKLog('MK_FILE', 'extracted ' + LFilename + ' mime=' + LMime +
            ' bytes=' + IntToStr(Length(LBytes)));
        finally
          LStream.Free;
        end;
      end;
    except
      on E: Exception do
        MKLog('MK_FILE-ERR', LFilename + ': ' + E.Message);
    end;

    if LPos > Length(LText) then
      Break;
    LPos     := LClosePos + Length(CCloseTag);
    LFindPos := PosEx(COpenTag, LText, LPos);
  end;
  if LPos <= Length(LText) then
    LResult := LResult + Copy(LText, LPos, MaxInt);

  ResMsg.Prompt := Trim(LResult);
end;

// Extracts files and text from an OpenAI-style content array:
//   [{"type":"image_url","image_url":{"url":"data:mime;base64,XXX"}}, ...]
//   [{"type":"text","text":"..."}]
// mk-claude-sonnet returns generated images in this format.
procedure TAiMakerAiChat.ExtractImageUrlContent(AContentArr: TJSonArray;
  ResMsg: TAiChatMessage);
var
  LVal:   TJSonValue;
  LItem:  TJSonObject;
  LImgObj: TJSonObject;
  sType, sUrl, sMime, sB64, sExt, sFileName, sText: string;
  LColonPos, LB64Start: Integer;
  LBytes: TBytes;
  LStream: TMemoryStream;
  LMF: TAiMediaFile;
begin
  if not Assigned(AContentArr) then Exit;
  for LVal in AContentArr do
  begin
    if not (LVal is TJSonObject) then Continue;
    LItem := TJSonObject(LVal);
    if not LItem.TryGetValue<String>('type', sType) then Continue;

    if SameText(sType, 'text') then
    begin
      if LItem.TryGetValue<String>('text', sText) and (sText <> '') then
        ResMsg.Prompt := ResMsg.Prompt + sText;
    end
    else if SameText(sType, 'image_url') then
    begin
      if not LItem.TryGetValue<TJSonObject>('image_url', LImgObj) or
         not Assigned(LImgObj) then Continue;
      if not LImgObj.TryGetValue<String>('url', sUrl) then Continue;
      // sUrl = "data:image/png;base64,iVBOR..."
      if not sUrl.StartsWith('data:') then Continue;
      LColonPos := Pos(';base64,', sUrl);
      if LColonPos <= 0 then Continue;
      sMime     := Copy(sUrl, 6, LColonPos - 6);
      LB64Start := LColonPos + 8;
      sB64      := Copy(sUrl, LB64Start, MaxInt);
      // Derive extension from mime-type (image/png → png, image/jpeg → jpg)
      sExt := LowerCase(Copy(sMime, Pos('/', sMime) + 1, MaxInt));
      if sExt = 'jpeg' then sExt := 'jpg';
      if sExt = '' then sExt := 'bin';
      sFileName := 'image.' + sExt;
      try
        LBytes := TNetEncoding.Base64.DecodeStringToBytes(sB64);
        if Length(LBytes) > 0 then
        begin
          LStream := TMemoryStream.Create;
          try
            LStream.Write(LBytes[0], Length(LBytes));
            LStream.Position := 0;
            LMF := TAiMediaFile.Create;
            LMF.LoadFromStream(sFileName, LStream);
            ResMsg.AddMediaFile(LMF);
            MKLog('IMAGE_URL', 'extracted ' + sFileName + ' mime=' + sMime +
              ' bytes=' + IntToStr(Length(LBytes)));
          finally
            LStream.Free;
          end;
        end;
      except
        on E: Exception do
          MKLog('IMAGE_URL-ERR', sFileName + ': ' + E.Message);
      end;
    end;
  end;
  ResMsg.Prompt := Trim(ResMsg.Prompt);
end;

Function TAiMakerAiChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
begin
  // Reset to zero on each request: if a turn does not bring usage in its chunks, without this
  // the previous turn's values would be reused and consumption would be inflated.
  FStreamPromptTok := 0;
  FStreamComplTok  := 0;
  FStreamTotalTok  := 0;
  FStreamCachedTok := 0;
  MKLog('SEND', 'URL=' + Url + ' Model=' + Model +
    ' Async=' + BoolToStr(Asynchronous, True) +
    ' Tools=' + BoolToStr(Tool_Active, True));
  Result := inherited InternalRunCompletions(ResMsg, AskMsg);
  MKLog('SEND-END', 'sync result len=' + IntToStr(Length(Result)));
end;

procedure TAiMakerAiChat.ParseAndAccumulateMediaParts(AMediaParts: TJSONArray);
var
  LVal:    TJSONValue;
  LPart:   TJSONObject;
  LInner:  TJSONObject;
  sType, sFilename, sMime, sData, sUrl: string;
  LBytes:  TBytes;
  LStream: TMemoryStream;
  LMF:     TAiMediaFile;
  IComma:  Integer;
begin
  for LVal in AMediaParts do
  begin
    LPart := LVal as TJSONObject;
    if not Assigned(LPart) then Continue;
    sType := ''; sFilename := ''; sMime := ''; sData := '';
    LPart.TryGetValue<string>('type', sType);

    if (sType = 'audio') or (sType = 'video') or (sType = 'file') then
    begin
      if not LPart.TryGetValue<TJSONObject>(sType, LInner) then Continue;
      LInner.TryGetValue<string>('filename',  sFilename);
      LInner.TryGetValue<string>('mime_type', sMime);
      LInner.TryGetValue<string>('data',      sData);
      // URL-only variant (lazy): if it does not carry base64 but does carry an http(s) URL
      if (sData = '') then
      begin
        sUrl := '';
        LInner.TryGetValue<string>('url', sUrl);
        if sUrl.StartsWith('http', True) then
        begin
          if sFilename = '' then
            sFilename := sType + '-' + IntToStr(FPendingMediaParts.Count + 1) +
                         GetFileExtensionFromMimeType(sMime);
          LMF := TAiMediaFile.Create;
          LMF.filename := sFilename;
          LMF.UrlMedia := sUrl;          // LAZY: download on first access to .Content
          FPendingMediaParts.Add(LMF);
          MKLog('MEDIA_PART', 'lazy url ' + sType + ' ' + sFilename + ' <- ' + sUrl);
          Continue;
        end;
      end;
    end
    else if sType = 'image_url' then
    begin
      if not LPart.TryGetValue<TJSONObject>('image_url', LInner) then Continue;
      LInner.TryGetValue<string>('url', sUrl);

      // URL LAZY branch (Server piece S: media-only URL -> http(s), not data:).
      // SetUrlMedia is purely lazy (Core:1169); downloads on first access to .Content.
      if sUrl.StartsWith('http', True) then
      begin
        sMime := '';
        LInner.TryGetValue<string>('mime_type', sMime);   // optional
        LMF := TAiMediaFile.Create;
        LMF.filename := 'ci_image-' + IntToStr(FPendingMediaParts.Count + 1) +
                        GetFileExtensionFromMimeType(sMime);
        LMF.UrlMedia := sUrl;
        FPendingMediaParts.Add(LMF);
        MKLog('MEDIA_PART', 'lazy url ' + LMF.filename + ' <- ' + sUrl);
        Continue;   // accumulated; skip the shared base64 decode below
      end;

      // data:mime/type;base64,<data>  (existing branch)
      IComma := Pos(',', sUrl);
      if IComma <= 0 then Continue;
      sData := Copy(sUrl, IComma + 1, MaxInt);
      var IMime1 := Pos(':', sUrl);
      var IMime2 := Pos(';', sUrl);
      if (IMime1 > 0) and (IMime2 > IMime1) then
        sMime := Copy(sUrl, IMime1 + 1, IMime2 - IMime1 - 1);
      sFilename := 'ci_image' + GetFileExtensionFromMimeType(sMime);
    end
    else
      Continue;

    if sData = '' then Continue;
    LBytes := TNetEncoding.Base64.DecodeStringToBytes(sData);
    if Length(LBytes) = 0 then Continue;

    LStream := TMemoryStream.Create;
    try
      LStream.Write(LBytes[0], Length(LBytes));
      LStream.Position := 0;
      LMF := TAiMediaFile.Create;
      LMF.LoadFromStream(sFilename, LStream);
      FPendingMediaParts.Add(LMF);
      MKLog('MEDIA_PART', 'type=' + sType + ' file=' + sFilename +
        ' size=' + IntToStr(Length(LBytes)));
    finally
      LStream.Free;
    end;
  end;
end;

procedure TAiMakerAiChat.HandleStreamDone;
// Called when [DONE] is received from the server.
// Builds a fake OpenAI-style response JSON from the accumulated FLastContent and calls
// ParseChat, which fires DoStateChange(acsFinished) + FOnReceiveDataEnd exactly once.
//
// IMPORTANT: TempMsg is added to FMessages BEFORE ParseChat fires FOnReceiveDataEnd.
// ParseChat calls events directly (no TThread.Queue), so the main thread could wake up
// immediately and start Turn 2. Without the pre-add, InitChatCompletions would miss
// the assistant reply (race condition in multi-turn async).
var
  LFakeJson, LFakeChoice, LFakeMsg, LFakeUsage: TJSONObject;
  LFakeChoices: TJSONArray;
  LRole: string;
  TempMsg: TAiChatMessage;
  LToolCallsStr: string;
  LCombinedTools: TJSONArray;
  LSortedKeys: TList<Integer>;
begin
  LRole := FTmpRole;
  if LRole = '' then LRole := 'assistant';

  // The server streams tool_calls as SSE delta (does NOT force a complete JSON when
  // there are tools). The base class accumulated them in FTmpToolCallBuffer during the stream. Since
  // this driver intercepts [DONE] and skips the base handler that normally reconstructs them,
  // we do it here so that ParseChat sees the tools and executes them; otherwise, async+tools ends up
  // with an empty response and, after closure, no continuation (the tool is never called).
  LToolCallsStr := '';
  if FTmpToolCallBuffer.Count > 0 then
  begin
    LCombinedTools := TJSONArray.Create;
    try
      LSortedKeys := TList<Integer>.Create;
      try
        for var LKey in FTmpToolCallBuffer.Keys do
          LSortedKeys.Add(LKey);
        LSortedKeys.Sort;
        for var LKey in LSortedKeys do
          LCombinedTools.Add(FTmpToolCallBuffer[LKey].Clone as TJSONObject);
      finally
        LSortedKeys.Free;
      end;
      LToolCallsStr := LCombinedTools.ToJSON;
    finally
      LCombinedTools.Free;
      FTmpToolCallBuffer.Clear;
    end;
  end;

  LFakeJson := TJSONObject.Create;
  try
    LFakeJson.AddPair('id', 'stream-' + IntToStr(TThread.GetTickCount));
    LFakeJson.AddPair('model', Model);

    LFakeUsage := TJSONObject.Create;
    // Those from the stream, not zeros: see FStreamPromptTok.
    LFakeUsage.AddPair('prompt_tokens',     TJSONNumber.Create(FStreamPromptTok));
    LFakeUsage.AddPair('completion_tokens', TJSONNumber.Create(FStreamComplTok));
    LFakeUsage.AddPair('total_tokens',      TJSONNumber.Create(FStreamTotalTok));
    // With the same shape as the real JSON, so that TAiChat.ParseChat reads it
    // via the usual path ('prompt_tokens_details.cached_tokens').
    if FStreamCachedTok > 0 then
    begin
      var LFakeDetails := TJSONObject.Create;
      LFakeDetails.AddPair('cached_tokens', TJSONNumber.Create(FStreamCachedTok));
      LFakeUsage.AddPair('prompt_tokens_details', LFakeDetails);
    end;
    LFakeJson.AddPair('usage', LFakeUsage);

    LFakeMsg := TJSONObject.Create;
    LFakeMsg.AddPair('role', LRole);
    if FLastContent <> '' then
      LFakeMsg.AddPair('content', FLastContent);
    if LToolCallsStr <> '' then
      LFakeMsg.AddPair('tool_calls', TJSONArray(TJSONObject.ParseJSONValue(LToolCallsStr)));

    LFakeChoice := TJSONObject.Create;
    LFakeChoice.AddPair('message', LFakeMsg);
    if LToolCallsStr <> '' then
      LFakeChoice.AddPair('finish_reason', 'tool_calls')
    else
      LFakeChoice.AddPair('finish_reason', 'stop');

    LFakeChoices := TJSONArray.Create;
    LFakeChoices.Add(LFakeChoice);
    LFakeJson.AddPair('choices', LFakeChoices);

    TempMsg := TAiChatMessage.Create('', LRole);
    try
      TempMsg.Id := FMessages.Count + 1;
      FMessages.Add(TempMsg);
      var LHistMsg := TempMsg;
      TempMsg := nil;  // FMessages is owner

      // Transfer accumulated media_parts (code_execution, etc.)
      // before ParseChat so that MediaFiles.Count is correct in OnDataEnd.
      while FPendingMediaParts.Count > 0 do
      begin
        var LMF := FPendingMediaParts[0];
        FPendingMediaParts.Delete(0);  // remove without freeing
        LHistMsg.AddMediaFile(LMF);    // message takes ownership
      end;

      ParseChat(LFakeJson, LHistMsg);

      // If LHistMsg remained empty, remove it BY REFERENCE: in the tools branch, ParseChat
      // added the assistant-with-tool_calls message AND the tool-result AFTER, so the last
      // item in the list is no longer LHistMsg (a Delete(Count-1) would delete the tool-result).
      if (LHistMsg.Prompt = '') and (LHistMsg.MediaFiles.Count = 0) and (LHistMsg.Tool_calls = '') then
        FMessages.Remove(LHistMsg);
    finally
      if Assigned(TempMsg) then TempMsg.Free;
    end;

    FLastReasoning := '';
    // Do not release FBusy if a deferred tool-calling continuation remains (#100): the turn continues.
    if not FPendingToolRun then
      FBusy := False;
  finally
    LFakeJson.Free;
  end;
end;

Procedure TAiMakerAiChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
var
  LBuffer, LFullLine, LJsonStr: string;
  LChunk, LProgress: TJSONObject;
  LStep, LFile: string;
  LPct: Integer;
  P: Integer;
  LDoneReceived: Boolean;
begin
  // In sync mode there's nothing to intercept; let the base class exit early.
  if not Asynchronous then
  begin
    inherited;
    Exit;
  end;

  // ISSUE #124: if the chunk ends with an incomplete UTF-8 character, DataString
  // raises EEncodingError; we exit without Clear and the next chunk completes it.
  try
    LBuffer := FResponse.DataString;
  except
    on EEncodingError do
      Exit;
  end;
  FResponse.Clear;
  LDoneReceived := False;
  if LBuffer <> '' then
    MKLog('RAW-SSE', Copy(LBuffer, 1, 2000));

  while Pos(#10, LBuffer) > 0 do
  begin
    P := Pos(#10, LBuffer);
    LFullLine := Copy(LBuffer, 1, P - 1);
    Delete(LBuffer, 1, P);

    LJsonStr := Trim(LFullLine);
    if LJsonStr.StartsWith('data:') then
      LJsonStr := Trim(Copy(LJsonStr, 6, Length(LJsonStr)));

    // [DONE]: intercept here — we fire events ourselves in HandleStreamDone to avoid
    // double-firing (ParseChat inside the base [DONE] handler fires them too) and to
    // fix the race condition (we add to FMessages before ParseChat fires FOnReceiveDataEnd).
    if LJsonStr = '[DONE]' then
    begin
      LDoneReceived := True;
      Continue;
    end;

    // mk_progress: server progress notification during PDF processing — fire OnProgress
    // and skip; do not pass empty delta:{} to the token accumulator.
    if (Length(LJsonStr) >= 2) and (LJsonStr[1] = '{') then
    begin
      LChunk := TJSONObject.ParseJSONValue(LJsonStr) as TJSONObject;
      if Assigned(LChunk) then
      try
        // usage: arrives in the penultimate chunk of the stream. We save the last
        // one seen, which is the accumulated usage for the turn.
        var LUsage: TJSONObject;
        if LChunk.TryGetValue<TJSONObject>('usage', LUsage) and Assigned(LUsage) then
        begin
          LUsage.TryGetValue<Integer>('prompt_tokens',     FStreamPromptTok);
          LUsage.TryGetValue<Integer>('completion_tokens', FStreamComplTok);
          LUsage.TryGetValue<Integer>('total_tokens',      FStreamTotalTok);
          var LDetails: TJSONObject;
          if LUsage.TryGetValue<TJSONObject>('prompt_tokens_details', LDetails) and
             Assigned(LDetails) then
            LDetails.TryGetValue<Integer>('cached_tokens', FStreamCachedTok);
        end;

        if LChunk.TryGetValue<TJSONObject>('mk_progress', LProgress) then
        begin
          LStep := ''; LFile := ''; LPct := 0;
          LProgress.TryGetValue<string>('step', LStep);
          LProgress.TryGetValue<string>('file', LFile);
          LProgress.TryGetValue<Integer>('pct', LPct);
          MKLog('PROGRESS', 'step=' + LStep + ' file=' + LFile + ' pct=' + IntToStr(LPct));
          if Assigned(FOnProgress) then
          begin
            var CStep := LStep;
            var CFile := LFile;
            var CPct  := LPct;
            var CHandler := FOnProgress;
            TThread.Queue(nil, procedure
            begin
              CHandler(CStep, CFile, CPct);
            end);
          end;
          Continue;
        end;

        // media_parts: files generated by code_execution or other server tools
        var LChoicesArr: TJSONArray;
        var LChoiceDelta: TJSONObject;
        var LMediaParts: TJSONArray;
        if LChunk.TryGetValue<TJSONArray>('choices', LChoicesArr) and
           (LChoicesArr.Count > 0) then
        begin
          var LChoice0 := LChoicesArr.Items[0] as TJSONObject;
          if Assigned(LChoice0) and
             LChoice0.TryGetValue<TJSONObject>('delta', LChoiceDelta) and
             LChoiceDelta.TryGetValue<TJSONArray>('media_parts', LMediaParts) then
            ParseAndAccumulateMediaParts(LMediaParts);
        end;
      finally
        LChunk.Free;
      end;
    end;

    FTmpResponseText := FTmpResponseText + LFullLine + #10;
  end;

  // Partial last line without #10 — keep in buffer (may complete in next chunk).
  if LBuffer <> '' then
    FTmpResponseText := FTmpResponseText + LBuffer;

  // FResponse is empty; inherited reads '' (no change to FTmpResponseText), then
  // processes our pre-filtered lines — fires DoData for each delta token.
  inherited OnInternalReceiveData(Sender, AContentLength, AReadCount, AAbort);

  // Handle [DONE] after inherited so FLastContent is fully updated from this chunk.
  if LDoneReceived and not AAbort then
    HandleStreamDone;
end;

Procedure TAiMakerAiChat.OnRequestCompletedEvent(const Sender: TObject; const aResponse: IHTTPResponse);
var
  LBody: string;
  LJObj: TJSONObject;
  LMsg: TAiChatMessage;
begin
  LBody := Trim(FTmpResponseText);
  FTmpResponseText := '';

  // With tools in the request, the server forces a complete JSON response
  // (chat.completion) even when stream=true was requested. In that case the buffer
  // contains the full JSON (without 'data:' lines or [DONE]): process it through
  // ParseChat, which also resolves tool_calls and fires OnReceiveDataEnd.
  //
  // ISSUE #100: it is processed BEFORE inherited on purpose. If ParseChat resolves
  // tool_calls it leaves FPendingToolRun=True (deferred continuation); the inherited base
  // (which frees the stream and launches the next round if FPendingToolRun) must run
  // AFTER so that the agentic loop continuation is not lost.
  if Asynchronous and Assigned(aResponse) and
     (aResponse.StatusCode >= 200) and (aResponse.StatusCode <= 299) and
     LBody.StartsWith('{') then
  begin
    LJObj := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    if Assigned(LJObj) then
    try
      if Assigned(LJObj.GetValue('choices')) then
      begin
        MKLog('NOSTREAM-JSON', Copy(LBody, 1, 500));
        LMsg := TAiChatMessage.Create('', 'assistant');
        LMsg.Id := FMessages.Count + 1;
        FMessages.Add(LMsg);
        ParseChat(LJObj, LMsg);
      end;
    finally
      LJObj.Free;
    end;
  end;

  // Delegate HTTP-error handling, stream cleanup and the deferred tool-calling
  // continuation (FPendingToolRun) to the base class. Runs at the end (see note above).
  inherited OnRequestCompletedEvent(Sender, aResponse);
end;

initialization
  TAiChatFactory.Instance.RegisterDriver(TAiMakerAiChat);

end.
