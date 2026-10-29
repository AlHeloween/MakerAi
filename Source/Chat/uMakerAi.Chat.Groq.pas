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
// - YouTube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


// Models with vision currently in Groq (Apr 2026):
//   meta-llama/llama-4-scout-17b-16e-instruct  (131K ctx, 8K output, vision + tools)
//   openai/gpt-oss-120b                        (131K ctx, 65K output, vision + reasoning)
// Vision limits in Groq:
//   - Max image per URL: 20MB | per base64: 4MB
//   - Max 5 images per request (llama-4-scout)

unit uMakerAi.Chat.Groq;

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
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Embeddings, uMakerAi.Core, uMakerAi.Embeddings.Core, uMakerAi.Chat.Messages;

Type
  // This reasoning model has only been detected in Groq so far, so it is implemented only here

  TAiReasoningFormat = (rfAuto, rfParsed, rfRaw, rfHidden);
  TAiReasoningEffort = (reAuto, reNone, reDefault);

  TAiGroqChat = Class(TAiChat)
  Private
    FReasoningFormat: TAiReasoningFormat;
    FReasoningEffort: TAiReasoningEffort;
    function  BuildChunkRequestCode(const AOriginalCode: string; AOffset, AEnd: Integer): string;
    function  CallCodeInterpreterForChunk(const ACode: string): string;
    function  FetchRemainingChunks(const AOriginalCode, APartialB64: string; AOffset: Integer): string;
  Protected
    Function InitChatCompletions: String; Override;
    Function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
    procedure ProcessExecutedTools(const AExecutedToolsJSON: string; ResMsg: TAiChatMessage); override;
  Public
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;
  Published
  End;

  TAiGroqEmbeddings = Class(TAiEmbeddings)
  Public
    // groq currently does not handle embedding models
    Function CreateEmbedding(Input, User: String; Dimensions: Integer = 1536; Model: String = 'Llama3-8b-8192'; EncodingFormat: String = 'float'): TAiEmbeddingData; Override;
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://api.groq.com/openai/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGroqChat]);
end;

{ TAiOllamaChat }

class function TAiGroqChat.GetDriverName: string;
Begin
  Result := 'Groq';
End;

class procedure TAiGroqChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@GROQ_API_KEY');
  Params.Add('Model=openai/gpt-oss-20b'); // the llama-3.x were retired in Sep 2026
  Params.Add('Max_Tokens=4096');
  Params.Add('URL=https://api.groq.com/openai/v1/');
End;

class function TAiGroqChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiGroqChat.Create(Sender);
End;

constructor TAiGroqChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@GROQ_API_KEY';
  Model := 'openai/gpt-oss-20b';
  Url := GlAIUrl;
  FReasoningFormat := rfAuto;
  FReasoningEffort := reAuto;
end;

destructor TAiGroqChat.Destroy;
begin

  inherited;
end;

function TAiGroqChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel: String;
Begin

  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'openai/gpt-oss-20b';

  // Functions do not work in asynchronous mode
  // LAsincronico := Self.Asynchronous and (not Self.Tool_Active);
  LAsincronico := Self.Asynchronous;

  FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  Try

    if (ModelConfig.Format = 'Raw') and (Tool_Active or (Response_format = tiaChatRfJson) or (Response_format = tiaChatRfJsonSchema)) then
    begin
      Raise Exception.Create('Groq Error: ReasoningFormat cannot be "raw" when using Tools or JSON mode. Use "parsed" or "hidden".');
    end;

    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    If Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAi).Text) <> '') then
    Begin
{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAi).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAi).Text));
{$ENDIF}
      If Not Assigned(JArr) then
        Raise Exception.Create('The Tools property is poorly defined, must be a JsonArray');
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

    // Groq compound (Tool_Active=False + cap_CodeInterpreter): the model handles tools
    // internally, but without explicit tool_choice Groq rejects internal calls with
    // "Tool choice is none, but model called a tool". It needs tool_choice:"auto" without tools array.
    if (cap_CodeInterpreter in ModelConfig.ModelCaps) and (not Tool_Active) then
    begin
      if not Assigned(AJSONObject.GetValue('tool_choice')) then
        AJSONObject.AddPair('tool_choice', 'auto');
    end;

    // Groq explicit code_interpreter tool — only for models that require declaring it
    // (gpt-oss-20b, etc.). Compound models have it natively and reject this field.
    // Criterion: inject only if Tool_Active=True (compound uses Tool_Active=False).
    if (cap_CodeInterpreter in ModelConfig.ModelCaps) and Tool_Active then
    begin
      var JExistingTools := AJSONObject.GetValue('tools') as TJSonArray;
      if Assigned(JExistingTools) then
      begin
        var JCodeTool := TJSonObject.Create;
        JCodeTool.AddPair('type', 'code_interpreter');
        JExistingTools.Add(JCodeTool);
      end
      else
      begin
        var JToolsArr := TJSonArray.Create;
        var JCodeTool := TJSonObject.Create;
        JCodeTool.AddPair('type', 'code_interpreter');
        JToolsArr.Add(JCodeTool);
        AJSONObject.AddPair('tools', JToolsArr);
      end;
      // Groq requires tool_choice="auto" when code_interpreter is present.
      // The function-tools block above uses a TJSONObject cast that silently fails
      // for the string value "auto", so tool_choice may not have been added yet —
      // check before adding to avoid duplicate keys.
      if not Assigned(AJSONObject.GetValue('tool_choice')) then
        AJSONObject.AddPair('tool_choice', 'auto');
    end;

    AJSONObject.AddPair('messages', GetMessages);

    AJSONObject.AddPair('model', LModel);

    // Reasoning: stored strictly by model family to avoid param leak when changing model
    // - openai/gpt-oss-*: include_reasoning:true + reasoning_effort (low/medium/high)
    // - qwen/*:           reasoning_format (parsed/raw/hidden) + reasoning_effort (default/none)
    // - other models:    none of these parameters (would cause error 422)
    if LModel.StartsWith('openai/gpt-oss') then
    begin
      if ModelConfig.ThinkingLevel <> tlDefault then
      begin
        AJSONObject.AddPair('include_reasoning', TJSONBool.Create(True));
        case ModelConfig.ThinkingLevel of
          tlLow:    AJSONObject.AddPair('reasoning_effort', 'low');
          tlMedium: AJSONObject.AddPair('reasoning_effort', 'medium');
          tlHigh:   AJSONObject.AddPair('reasoning_effort', 'high');
        end;
      end;
    end
    else if LModel.StartsWith('qwen/') then
    begin
      if ModelConfig.ThinkingLevel <> tlDefault then
      begin
        // Thinking active: reasoning_format parsed + reasoning_effort=default
        var LFormat: String := ModelConfig.Format;
        if LFormat = '' then
          LFormat := 'parsed'; // default: reasoning in separate field message.reasoning
        AJSONObject.AddPair('reasoning_format', LFormat);
        AJSONObject.AddPair('reasoning_effort', 'default');
      end
      else if ModelConfig.Format <> '' then
      begin
        // Format explicitly set without ThinkingLevel (e.g., 'hidden' for non-thinking)
        AJSONObject.AddPair('reasoning_format', ModelConfig.Format);
      end
      else
      begin
        // Without explicit config = direct chat model: turn off thinking.
        // qwen3.6 by default dumps reasoning into the content, and sometimes
        // WITHOUT thinking tags (parsed is not enough: it only separates tagged content).
        // reasoning_effort none suppresses thinking completely.
        AJSONObject.AddPair('reasoning_format', 'parsed');
        AJSONObject.AddPair('reasoning_effort', 'none');
      end;
    end;
    // Other models (llama, mistral, kimi, etc.): no reasoning params

    AJSONObject.AddPair('temperature', TJSONNumber.Create(Trunc(Temperature * 100) / 100));

    // Groq docs: reasoning models use max_completion_tokens (includes reasoning tokens in the budget)
    // Only include when > 0; omitting it lets Groq use the full remaining context automatically.
    if Max_tokens > 0 then
    begin
      if LModel.StartsWith('openai/gpt-oss') or LModel.StartsWith('qwen/') then
        AJSONObject.AddPair('max_completion_tokens', TJSONNumber.Create(Max_tokens))
      else
        AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));
    end;

    If Top_p <> 0 then
      AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

    AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Trunc(Frequency_penalty * 100) / 100));
    AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Trunc(Presence_penalty * 100) / 100));
    AJSONObject.AddPair('user', User);
    AJSONObject.AddPair('n', TJSONNumber.Create(N));

    // 1. JSON Schema (Structured Outputs) — ParseJsonSchemaProperty accepts the
    // raw schema or the wrapper {name, strict, schema} and fails with a clear error
    // if JsonSchema is empty (the type alone produces a remote 400).
    if (FResponse_format = tiaChatRfJsonSchema) then
    begin
      var sSchemaName := 'structured_response';
      // NOTE: We do not send "strict": true by default to maximize compatibility
      // with Groq models that do not yet support full constrained decoding.
      var bStrict := False;
      var JInnerSchema := ParseJsonSchemaProperty(sSchemaName, bStrict);

      var JSchemaWrapper := TJSonObject.Create;
      JSchemaWrapper.AddPair('name', sSchemaName); // 'name' is MANDATORY in this structure
      if bStrict then
        JSchemaWrapper.AddPair('strict', TJSONBool.Create(True));
      JSchemaWrapper.AddPair('schema', JInnerSchema);

      var JResponseFormat := TJSonObject.Create;
      JResponseFormat.AddPair('type', 'json_schema');
      JResponseFormat.AddPair('json_schema', JSchemaWrapper);
      AJSONObject.AddPair('response_format', JResponseFormat);
    end

    // 2. JSON Mode (Simple)
    else if (FResponse_format = tiaChatRfJson) then
    begin
      var
      JResponseFormat := TJSonObject.Create;
      JResponseFormat.AddPair('type', 'json_object');
      AJSONObject.AddPair('response_format', JResponseFormat);
    end

    // 3. Text Mode (Only if explicitly specified, or leave as default)
    else if (FResponse_format = tiaChatRfText) then
    begin
      var
      JResponseFormat := TJSonObject.Create;
      JResponseFormat.AddPair('type', 'text');
      AJSONObject.AddPair('response_format', JResponseFormat);
    end;

    Lista.CommaText := Stop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    End;

    // NOTE: Groq does not support logprobs, logit_bias or top_logprobs in chat completions (error 400)

    If Seed > 0 then
      AJSONObject.AddPair('seed', TJSONNumber.Create(Seed));

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSon));
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

{ TAiGroqEmbeddings }

function TAiGroqEmbeddings.CreateEmbedding(Input, User: String; Dimensions: Integer; Model, EncodingFormat: String): TAiEmbeddingData;
Var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  jObj: TJSonObject;
  Res: IHTTPResponse;
  Response: TStringStream;
  St: TStringStream;
  sUrl: String;
begin
  // WARNING WARNING WARNING WARNING
  Raise Exception.Create('Currently Groq does not handle embedding models');

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 34}
  Client.SynchronizeEvents := False;
{$ENDIF}
  St := TStringStream.Create('', TEncoding.UTF8);
  Response := TStringStream.Create('', TEncoding.UTF8);
  sUrl := FUrl + 'embeddings';
  jObj := TJSonObject.Create;

  Try
    jObj.AddPair('input', Input);
    jObj.AddPair('model', Model);
    jObj.AddPair('user', User);
    jObj.AddPair('encoding_format', EncodingFormat);

    // St.WriteString(UTF8Encode(jObj.Format));
    St.WriteString(jObj.Format);
    St.Position := 0;

    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + FApiKey)];
    Client.ContentType := 'application/json';

    Res := Client.Post(sUrl, St, Response, Headers);
    Response.Position := 0;

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

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

function TAiGroqChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
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
    raise Exception.Create('An audio file with content is required for transcription.');

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

{ TAiGroqChat — chunking for code interpreter }

// Modifies the original Python code to print only the slice [AOffset:AEnd] of the b64.
// Looks for the FILE_B64_BEGIN / print(<expr>) / FILE_B64_END block and replaces it.
function TAiGroqChat.BuildChunkRequestCode(const AOriginalCode: string; AOffset, AEnd: Integer): string;
var
  Lines: TStringList;
  I, IBeginLine, IPrintLine, IEndLine: Integer;
  B64Expr, LLine, LTrim: string;
  SB: TStringList;
begin
  IBeginLine := -1; IPrintLine := -1; IEndLine := -1;
  B64Expr    := '';
  Lines := TStringList.Create;
  SB    := TStringList.Create;
  try
    Lines.Text := AOriginalCode;
    for I := 0 to Lines.Count - 1 do
    begin
      LTrim := Trim(Lines[I]);
      if (IBeginLine < 0) and (Pos('FILE_B64_BEGIN', LTrim) > 0) then
        IBeginLine := I
      else if (IBeginLine >= 0) and (IPrintLine < 0) and LTrim.StartsWith('print(') then
      begin
        IPrintLine := I;
        // extract expression: print(EXPR) → EXPR
        LLine := LTrim;
        if LLine.EndsWith(')') then
          B64Expr := Copy(LLine, 7, Length(LLine) - 7);  // remove 'print(' and ')'
      end
      else if (IBeginLine >= 0) and (Pos('FILE_B64_END', LTrim) > 0) then
      begin
        IEndLine := I;
        Break;
      end;
    end;

    if (IBeginLine < 0) or (B64Expr = '') or (IEndLine < 0) then
    begin
      // Pattern not found: append chunk at the end of the original code
      Result := AOriginalCode + #10 +
        '_ci_b64 = globals().get(''_ci_b64'', '''')' + #10 +
        'print(''CHUNK_START'')' + #10 +
        Format('print(_ci_b64[%d:%d])', [AOffset, AEnd]) + #10 +
        'print(''CHUNK_END'')';
      Exit;
    end;

    // Lines before the FILE_B64 block
    for I := 0 to IBeginLine - 1 do
      SB.Add(Lines[I]);

    // If the expression uses .read(), insert seek(0) with the detected buffer variable
    if Pos('.read()', B64Expr) > 0 then
    begin
      // Detect buffer variable: base64.b64encode(buf.read()) → buf
      var LBufVar := '';
      var IRead := Pos('.read()', B64Expr);
      if IRead > 1 then
      begin
        var ITmp := IRead - 1;
        while (ITmp > 0) and CharInSet(B64Expr[ITmp], ['a'..'z','A'..'Z','0'..'9','_']) do
          Dec(ITmp);
        LBufVar := Copy(B64Expr, ITmp + 1, IRead - ITmp - 1);
      end;
      if LBufVar <> '' then
        SB.Add(LBufVar + '.seek(0)');
    end;

    // Chunk block
    SB.Add('_ci_b64 = ' + B64Expr);
    SB.Add('print(''CHUNK_START'')');
    SB.Add(Format('print(_ci_b64[%d:%d])', [AOffset, AEnd]));
    SB.Add('print(''CHUNK_END'')');

    // Lines after the FILE_B64_END block
    for I := IEndLine + 1 to Lines.Count - 1 do
      SB.Add(Lines[I]);

    Result := SB.Text;
  finally
    Lines.Free;
    SB.Free;
  end;
end;

// Makes a direct HTTP call to Groq with code_interpreter and returns the concatenated tool output.
function TAiGroqChat.CallCodeInterpreterForChunk(const ACode: string): string;
const
  RETRY_MAX = 5;
var
  LClient: TNetHTTPClient;
  LReqStream, LRespStream: TStringStream;
  LHeaders: TNetHeaders;
  LRes: IHTTPResponse;
  LPayload, LMsg, LTool: TJSonObject;
  LMsgs, LTools: TJSonArray;
  LOutVal: TJSonValue;
  LExecTools: TJSonArray;
  LRetry: Integer;
  LWait: Integer;
  sBody: string;
begin
  Result := '';
  LClient := TNetHTTPClient.Create(nil);
  try
{$IF CompilerVersion >= 34}
    LClient.SynchronizeEvents := False;
{$ENDIF}
    LClient.ResponseTimeout := ResponseTimeOut;
    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey),
                 TNetHeader.Create('Content-Type',   'application/json')];

    // Build minimal payload
    LMsg := TJSonObject.Create;
    LMsg.AddPair('role', 'user');
    LMsg.AddPair('content', 'Run this Python code:' + #10 + ACode);
    LMsgs := TJSonArray.Create;
    LMsgs.Add(LMsg);

    LTool := TJSonObject.Create;
    LTool.AddPair('type', 'code_interpreter');
    LTools := TJSonArray.Create;
    LTools.Add(LTool);

    LPayload := TJSonObject.Create;
    try
      LPayload.AddPair('model',                TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model));
      LPayload.AddPair('messages',             LMsgs);
      LPayload.AddPair('tools',                LTools);
      LPayload.AddPair('tool_choice',          'auto');
      LPayload.AddPair('max_completion_tokens', TJSONNumber.Create(65536));
      LPayload.AddPair('stream',               TJSONBool.Create(False));
      sBody := LPayload.ToJSON;
    finally
      LPayload.Free;
    end;

    LRetry := 0;
    repeat
      LReqStream  := TStringStream.Create(sBody, TEncoding.UTF8);
      LRespStream := TStringStream.Create('', TEncoding.UTF8);
      try
        LRes := LClient.Post(Url + 'chat/completions', LReqStream, LRespStream, LHeaders);
        if LRes.StatusCode = 429 then
        begin
          // Rate limit — wait and retry
          LWait := 35000;
          var sErr := LRes.ContentAsString;
          var IWaitPos := Pos('try again in ', sErr);
          if IWaitPos > 0 then
          begin
            var sAfter := Copy(sErr, IWaitPos + 13, 10);
            var IDot := Pos('.', sAfter);
            var ISpace := Pos(' ', sAfter);
            var IEnd := ISpace;
            if (IDot > 0) and (IDot < ISpace) then IEnd := IDot;
            var sNum := Copy(sAfter, 1, IEnd - 1);
            var N: Double;
            if TryStrToFloat(sNum, N) then
              LWait := Trunc(N * 1000) + 3000;
          end;
          Sleep(LWait);
          Inc(LRetry);
          Continue;
        end;
        if LRes.StatusCode = 200 then
        begin
          var JResp := TJSonObject.ParseJSONValue(LRespStream.DataString) as TJSonObject;
          if Assigned(JResp) then
          try
            // Extract executed_tools from choices[0].message
            var JChoices: TJSonArray;
            if JResp.TryGetValue<TJSonArray>('choices', JChoices) and (JChoices.Count > 0) then
            begin
              var JMsgNode: TJSonObject;
              if TJSonObject(JChoices.Items[0]).TryGetValue<TJSonObject>('message', JMsgNode) then
              begin
                if JMsgNode.TryGetValue<TJSonArray>('executed_tools', LExecTools) then
                begin
                  for LOutVal in LExecTools do
                  begin
                    var sOut: string := '';
                    if (LOutVal as TJSonObject).TryGetValue<string>('output', sOut) then
                      Result := Result + sOut;
                  end;
                end;
              end;
            end;
            // compound-beta: executed_tools at root
            if (Result = '') and JResp.TryGetValue<TJSonArray>('executed_tools', LExecTools) then
              for LOutVal in LExecTools do
              begin
                var sOut: string := '';
                if (LOutVal as TJSonObject).TryGetValue<string>('output', sOut) then
                  Result := Result + sOut;
              end;
          finally
            JResp.Free;
          end;
        end;
        Break; // exit retry loop
      finally
        LReqStream.Free;
        LRespStream.Free;
      end;
    until LRetry >= RETRY_MAX;
  finally
    LClient.Free;
  end;
end;

// Extracts base64 from a tool output (with or without CHUNK_START/CHUNK_END markers).
function ExtractB64FromOutput(const AOutput: string; AExpectedLen: Integer): string;
const
  B64_CHARS = ['A'..'Z','a'..'z','0'..'9','+','/','='];
var
  iB, iE: Integer;
  sRaw, sClean: string;
begin
  Result := '';
  iB := Pos('CHUNK_START', AOutput);
  iE := Pos('CHUNK_END',   AOutput);
  if (iB > 0) and (iE > iB) then
  begin
    var iStart := iB + Length('CHUNK_START');
    while (iStart <= Length(AOutput)) and CharInSet(AOutput[iStart], [#10, #13]) do
      Inc(iStart);
    sRaw := Copy(AOutput, iStart, iE - iStart);
  end
  else
  begin
    // Without markers: take everything if >90% base64
    sRaw := AOutput;
  end;
  sClean := '';
  for var ch in sRaw do
    if CharInSet(ch, B64_CHARS) then
      sClean := sClean + ch;
  if AExpectedLen > 0 then
    Result := Copy(sClean, 1, AExpectedLen)
  else
    Result := sClean;
end;

// Requests the remaining chunks and returns the complete b64.
function TAiGroqChat.FetchRemainingChunks(const AOriginalCode, APartialB64: string; AOffset: Integer): string;
const
  CHUNK_SIZE = 40000;
var
  LFullB64: string;
  LOffset: Integer;
  LChunkCode, LOutput, LChunk: string;
begin
  LFullB64 := APartialB64;
  LOffset  := AOffset;
  repeat
    LChunkCode := BuildChunkRequestCode(AOriginalCode, LOffset, LOffset + CHUNK_SIZE);
    LOutput    := CallCodeInterpreterForChunk(LChunkCode);
    if LOutput = '' then Break;
    LChunk := ExtractB64FromOutput(LOutput, CHUNK_SIZE);
    if LChunk = '' then Break;
    LFullB64 := LFullB64 + LChunk;
    if Length(LChunk) < CHUNK_SIZE then Break; // last chunk
    Inc(LOffset, Length(LChunk));
  until False;
  Result := LFullB64;
end;

// Override: detects truncation of FILE_B64_BEGIN and completes the b64 with additional chunks.
procedure TAiGroqChat.ProcessExecutedTools(const AExecutedToolsJSON: string; ResMsg: TAiChatMessage);
var
  JArr: TJSonArray;
  JItem: TJSonObject;
  JVal: TJSonValue;
  sOutput, sCode, sFileName, sAfterBegin: string;
  sPartialB64, sFullB64: string;
  iB, iE, iNL, iDataStart, iOffset: Integer;
begin
  if AExecutedToolsJSON = '' then
  begin
    inherited ProcessExecutedTools(AExecutedToolsJSON, ResMsg);
    Exit;
  end;

  JArr := TJSonObject.ParseJSONValue(AExecutedToolsJSON) as TJSonArray; // ParseJSONValue is a class method of TJSONObject (TJSonValue does not expose it in D10.4)
  if not Assigned(JArr) then
  begin
    inherited ProcessExecutedTools(AExecutedToolsJSON, ResMsg);
    Exit;
  end;

  try
    for JVal in JArr do
    begin
      JItem := JVal as TJSonObject;
      if not Assigned(JItem) then Continue;
      var sType: string := '';
      JItem.TryGetValue<string>('type', sType);
      if (sType <> 'function') and (sType <> 'python') then Continue;

      JItem.TryGetValue<string>('output',    sOutput);
      JItem.TryGetValue<string>('arguments', sCode);

      if (sCode = '') or (sOutput = '') then Continue;

      iB := Pos('FILE_B64_BEGIN:', sOutput);
      iE := Pos('FILE_B64_END',    sOutput);

      // Only act if there is FILE_B64_BEGIN but NOT FILE_B64_END (truncated output)
      if (iB <= 0) or (iE > 0) then Continue;

      // Extract file name
      sAfterBegin := Copy(sOutput, iB + Length('FILE_B64_BEGIN:'), MaxInt);
      iNL := Pos(#10, sAfterBegin);
      if iNL = 0 then iNL := Pos(#13, sAfterBegin);
      sFileName := 'ci_output.bin';
      if iNL > 0 then
        sFileName := Trim(Copy(sAfterBegin, 1, iNL - 1));

      // Extract received partial base64
      iDataStart := iB + Length('FILE_B64_BEGIN:') + iNL;
      var sPartialRaw := Copy(sOutput, iDataStart, MaxInt);
      sPartialB64 := '';
      for var ch in sPartialRaw do
        if CharInSet(ch, ['A'..'Z','a'..'z','0'..'9','+','/','=']) then
          sPartialB64 := sPartialB64 + ch;

      iOffset := Length(sPartialB64);
      if iOffset = 0 then Continue;

      // Get remaining chunks
      sFullB64 := FetchRemainingChunks(sCode, sPartialB64, iOffset);

      if sFullB64 <> '' then
      begin
        // Replace output with the complete, well-delimited b64
        JItem.RemovePair('output');
        JItem.AddPair('output',
          'FILE_B64_BEGIN:' + sFileName + #10 + sFullB64 + #10 + 'FILE_B64_END');
      end;
    end;

    inherited ProcessExecutedTools(JArr.ToJSON, ResMsg);
  finally
    JArr.Free;
  end;
end;

Initialization

TAiChatFactory.Instance.RegisterDriver(TAiGroqChat);

end.
