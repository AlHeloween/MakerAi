// MIT License
//
// Copyright (c) 2024 Gustavo Enríquez - CimaMaker
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

unit uMakerAi.Chat.Ollama;

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
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Core, uMakerAi.Utils.CodeExtractor, uMakerAi.Chat.Messages;

type

  TAiOllamaChat = Class(TAiChat)
  Private
    Fkeep_alive: String;
    FTmpToolCallsStr: string;
    FAsyncResMsg: TAiChatMessage; // Pending ResMsg between async tool call rounds
    procedure Setkeep_alive(const Value: String);
  Protected
    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;
    Function InitChatCompletions: String; Override;
    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    Procedure ParseChat(JObj: TJSonObject; ResMsg: TAiChatMessage); Override;
    function ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions; Override;
  Public
    Class Function GetModels(aApiKey: String; aUrl: String = ''): TStringList; Override;
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    Function GetMessages: TJSonArray; Override;

    // ----- FUNCIONES DE GESTIÓN DE MODELOS  -----------
    procedure PullModel(const aModelName: string);
    procedure CreateModel(const aNewModelName, aModelfileContent: string);
    function ShowModelInfo(const aModelName: string): TJSonObject;
    procedure CopyModel(const aSourceModel, aDestinationModel: string);
    procedure DeleteModel(const aModelName: string);

    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;

  Published
    property keep_alive: String read Fkeep_alive write Setkeep_alive;
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'http://localhost:11434/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiOllamaChat]);
end;

class function TAiOllamaChat.GetDriverName: string;
Begin
  Result := 'Ollama';
End;

class procedure TAiOllamaChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@OLLAMA_API_KEY');
  Params.Add('Model=llama3');
  Params.Add('Max_Tokens=4096');
  Params.Add('URL=http://localhost:11434/');
End;

procedure TAiOllamaChat.Setkeep_alive(const Value: String);
begin
  Fkeep_alive := Value;
end;

class function TAiOllamaChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiOllamaChat.Create(Sender);
End;

{ TAiOllamaChat }

constructor TAiOllamaChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@OLLAMA_API_KEY';
  Model := 'gpt-oss:20b';
  Url := GlAIUrl;
  keep_alive := '1m';
end;

destructor TAiOllamaChat.Destroy;
begin

  inherited;
end;

function TAiOllamaChat.ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions;
var
  LResponseObj, LMessageObj, LToolCallObj, LFunctionObj, LArgumentsObj: TJSonObject;
  LToolCallsArray: TJSonArray;
  LToolCall: TAiToolsFunction;
  LItem: TJSONValue;
begin
  Result := TAiToolsFunctions.Create;

  if (jChoices = nil) or (jChoices.Count = 0) then
    Exit;

  if not(jChoices.Items[0] is TJSonObject) then
    Exit;

  LResponseObj := jChoices.Items[0] as TJSonObject;

  if not LResponseObj.TryGetValue<TJSonObject>('message', LMessageObj) then
    Exit;

  if not LMessageObj.TryGetValue<TJSonArray>('tool_calls', LToolCallsArray) then
    Exit;

  for LItem in LToolCallsArray do
  begin
    if not(LItem is TJSonObject) then
      Continue;

    LToolCallObj := LItem as TJSonObject;

    if LToolCallObj.TryGetValue<TJSonObject>('function', LFunctionObj) then
    begin
      LToolCall := TAiToolsFunction.Create;
      try
        // Ollama now includes an 'id', but we generate it as a fallback just in case.
        LToolCall.Id := LToolCallObj.GetValue<string>('id', 'call_' + TGuid.NewGuid.ToString);
        LToolCall.Name := LFunctionObj.GetValue<string>('name', '');
        LToolCall.&Type := 'function';

        if LFunctionObj.TryGetValue<TJSonObject>('arguments', LArgumentsObj) then
          LToolCall.Arguments := LArgumentsObj.Format
        else
          LToolCall.Arguments := '{}';

        Result.Add(LToolCall.Id, LToolCall);
      except
        LToolCall.Free;
        raise;
      end;
    end;
  end;
end;

function TAiOllamaChat.GetMessages: TJSonArray;
Var
  I, J: Integer;
  Msg: TAiChatMessage;
  JObj: TJSonObject;
  jImages: TJSonArray;
begin
  Result := TJSonArray.Create;

  For I := 0 to Messages.Count - 1 do
  Begin
    Msg := Messages.Items[I];
    JObj := TJSonObject.Create;

    If Msg.ToolCallId <> '' then
      JObj.AddPair('tool_call_id', Msg.ToolCallId);

    If Msg.FunctionName <> '' then
      JObj.AddPair('name', Msg.FunctionName);

    JObj.AddPair('role', Msg.Role);

    // The Ollama API ONLY accepts content:string + images:[base64...].
    // It does not support content as an array of parts (OpenAI multipart format).
    // Images and audio are both sent in the 'images' field as base64.
    JObj.AddPair('content', Msg.Prompt);

    jImages := nil;
    For J := 0 to Msg.MediaFiles.Count - 1 do
    Begin
      if Msg.MediaFiles[J].FileCategory in [Tfc_Image, Tfc_Audio] then
      begin
        if not Assigned(jImages) then
        begin
          jImages := TJSonArray.Create;
          JObj.AddPair('images', jImages);
        end;
        jImages.Add(Msg.MediaFiles[J].Base64);
      end;
    End;

    If Msg.Tool_calls <> '' then
{$IF CompilerVersion < 35}
      JObj.AddPair('tool_calls', TJSONUtils.ParseAsArray(Msg.Tool_calls));
{$ELSE}
      JObj.AddPair('tool_calls', TJSonArray(TJSonArray.ParseJSONValue(Msg.Tool_calls)));
{$ENDIF}
    Result.Add(JObj);
  End;
end;

class function TAiOllamaChat.GetModels(aApiKey, aUrl: String): TStringList;
Var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  Res: IHTTPResponse;
  Response: TStringStream;
  sUrl, EndPointUrl: String;
  jRes: TJSonObject;
  JArr: TJSonArray;
  JVal: TJSONValue;
  sModel: string;
  CustomModels: TArray<string>;
  I: Integer;
begin
  Result := TStringList.Create;
  try // ISSUE #114: if the body throws, free Result so it is not leaked

  If aUrl <> '' then
    EndPointUrl := aUrl
  Else
    EndPointUrl := GlAIUrl;

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 34}
  Client.SynchronizeEvents := False;
{$ENDIF}
  Response := TStringStream.Create('', TEncoding.UTF8);
  sUrl := EndPointUrl + 'api/tags';

  Try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + aApiKey)];
    Client.ContentType := 'application/json';

    Res := Client.Get(sUrl, Response, Headers);

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

    if Res.StatusCode = 200 then
    Begin
      jRes := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
      try
        If jRes.TryGetValue<TJSonArray>('models', JArr) then
        Begin
          For JVal in JArr do
          Begin
            sModel := JVal.GetValue<String>('name');
            If sModel <> '' then
              Result.Add(sModel);
          End;
        End;
      finally
        jRes.Free;
      end;

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
  except // ISSUE #114: the error path must not leave Result orphaned
    Result.Free;
    raise;
  end;
end;

function TAiOllamaChat.InitChatCompletions: String;
Var
  AJSONObject, jOptions: TJSonObject;
  JArr, JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LModel: String;
begin
  // 1. Basic configuration and Model
  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  If LModel = '' then
    LModel := 'gpt-oss:20b'; // Safe fallback

  // Configure the HTTP client according to the component property
  FClient.Asynchronous := Self.Asynchronous;

  // Increase the default timeout since local models may take time to load
  if FClient.ResponseTimeout < 60000 then
    FClient.ResponseTimeout := 1000 * 60 * 5; // 5 minutes by default

  AJSONObject := TJSonObject.Create;
  jOptions := TJSonObject.Create; // Object for advanced parameters
  Lista := TStringList.Create;

  Try
    // --- ROOT PARAMETERS ---
    AJSONObject.AddPair('model', LModel);
    AJSONObject.AddPair('messages', GetMessages); // Uses GetMessages (we will review this later)

    // Respect the asynchronous setting (True/False)
    AJSONObject.AddPair('stream', TJSONBool.Create(Self.Asynchronous));

    if Fkeep_alive <> '' then
      AJSONObject.AddPair('keep_alive', Fkeep_alive);

    // 1. Structured Outputs (JSON Schema)
    if FResponse_format = tiaChatRfJsonSchema then
    begin
      // Ollama expects the schema DIRECTLY in the "format" parameter (without
      // wrappers). ParseJsonSchemaProperty extracts the inner schema if the user
      // passed the wrapper {name, strict, schema} and fails with a clear error if it is empty.
      var sSchemaName := '';
      var bStrict := False;
      var JInnerSchema := ParseJsonSchemaProperty(sSchemaName, bStrict);
      AJSONObject.AddPair('format', JInnerSchema);
    end
    // 2. JSON Mode (Simple)
    else if (FResponse_format = tiaChatRfJson) then
    begin
      AJSONObject.AddPair('format', 'json');
    end;

    // --- THINKING (Ollama v0.7.0+) ---
    // Models with native reasoning (gemma4, qwen3, deepseek-r1, etc.) require
    // "think":true at the root level to enable reasoning mode.
    if (cap_Reasoning in ModelConfig.ModelCaps) and (ModelConfig.ThinkingLevel <> tlDefault) then
      AJSONObject.AddPair('think', TJSONBool.Create(True));

    // --- HANDLING TOOLS ---
    If Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAi).Text) <> '') then
    Begin
{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAi).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAi).Text));
{$ENDIF}
      If Assigned(JArr) then
        AJSONObject.AddPair('tools', JArr);
    End;

    // --- "OPTIONS" PARAMETERS (Key difference from OpenAI) ---
    // Ollama requires encapsulating these parameters inside 'options'

    if Temperature > 0 then
      jOptions.AddPair('temperature', TJSONNumber.Create(Temperature));

    // NOTE: Ollama uses 'num_predict' instead of 'max_tokens'
    if Max_tokens > 0 then
      jOptions.AddPair('num_predict', TJSONNumber.Create(Max_tokens));

    If Top_p <> 0 then
      jOptions.AddPair('top_p', TJSONNumber.Create(Top_p));

    If Frequency_penalty <> 0 then
      jOptions.AddPair('frequency_penalty', TJSONNumber.Create(Frequency_penalty));

    If Presence_penalty <> 0 then
      jOptions.AddPair('presence_penalty', TJSONNumber.Create(Presence_penalty));

    If Seed > 0 then
      jOptions.AddPair('seed', TJSONNumber.Create(Seed));

    // Handling Stop Sequences
    Lista.CommaText := Stop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      jOptions.AddPair('stop', JStop);
    End;

    // Add the options object to the main JSON
    if jOptions.Count > 0 then
      AJSONObject.AddPair('options', jOptions)
    else
      jOptions.Free; // If it was not added to the parent, it must be freed

    // Generation of the final String
    ApplyExtraBodyParams(AJSONObject);
    Result := AJSONObject.ToJSON;

  Finally
    AJSONObject.Free;
    // jOptions is automatically freed if it was added to AJSONObject
    Lista.Free;
  End;
end;

function TAiOllamaChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
Var
  ABody: String;
  sUrl: String;
  Res: IHTTPResponse;
  St: TStringStream;
  FHeaders: TNetHeaders;
  JObj: TJSonObject;
begin

  FBusy := True; // Mark the system as busy
  FAbort := False; // Start as not aborted
  FLastError := '';
  FLastContent := '';
  FLastPrompt := '';

  DoStateChange(acsConnecting, 'Sending request...');

  // ISSUE #100: use FCurrentPostStream (not a local St) so the POST stream
  // survives in async and is safely freed in OnRequestCompletedEvent (base),
  // instead of leaking (the previous code never freed St in async).
  if Assigned(FCurrentPostStream) then
    FreeAndNil(FCurrentPostStream);
  FCurrentPostStream := TStringStream.Create('', TEncoding.UTF8);
  St := FCurrentPostStream;
  sUrl := Url + 'api/chat';

  Try
    FHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    ABody := InitChatCompletions;

    LogDebug('-Request-');
    LogDebug(ABody);

    St.WriteString(ABody);
    St.Position := 0;
    FResponse.Clear;
    FResponse.Position := 0;

    Res := FClient.Post(sUrl, St, FResponse, FHeaders);

    FLastContent := '';

    If FClient.Asynchronous = False then
    Begin
      if not Assigned(Res) then
        Raise Exception.Create('Connection error: no response received from Ollama server')
      else if Res.StatusCode = 200 then
      Begin
        Var
        S := Res.ContentAsString;

        LogDebug('-Result-');
        LogDebug(S);

        JObj := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
        Try
          FBusy := False;
          ParseChat(JObj, ResMsg);
          Result := FLastContent;
        Finally
          JObj.Free;
        End;
      End
      else
      begin
        Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end;
    End;
  Finally
    // Sync: free here (already consumed). Async: OnRequestCompletedEvent frees it
    // (base) when the request completes, safely (without leaks or use-after-free).
    If FClient.Asynchronous = False then
      FreeAndNil(FCurrentPostStream);
  End;
end;

function IsCompleteJson(const S: string): Boolean;
var
  I, Balance: Integer;
  InString, Escape: Boolean;
begin
  Balance := 0;
  InString := False;
  Escape := False;

  for I := 1 to Length(S) do
  begin
    if Escape then
    begin
      Escape := False;
      Continue;
    end;

    case S[I] of
      '\':
        if InString then
          Escape := True;

      '"':
        InString := not InString;

      '{':
        if not InString then
          Inc(Balance);

      '}':
        if not InString then
          Dec(Balance);
    end;
  end;

  Result := (Balance = 0) and (not InString);
end;

procedure TAiOllamaChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
var
  LJsonObject, LMessageObj: TJSonObject;
  LToolCallsArray: TJSonArray;
  LChunkStr, LJsonLine, LRole, LContentPart, LThinkingPart: string;
  LDone: Boolean;
  LFinalMsg: TAiChatMessage;
  LStreamFinished: Boolean;

  procedure ProcessFinalJsonObject(AJson: TJSonObject);
  var
    LMsgObj: TJSonObject;
  begin
    LStreamFinished := True;
    FBusy := False;

    // If we captured tool_calls in previous chunks but the final JSON does not have them,
    // we re-inject them so ParseChat processes them.
    if not FTmpToolCallsStr.IsEmpty then
    begin
      if not AJson.TryGetValue<TJSonObject>('message', LMsgObj) then
      begin
        LMsgObj := TJSonObject.Create;
        AJson.AddPair('message', LMsgObj);
      end;

      if LMsgObj.GetValue('tool_calls') = nil then
      begin
{$IF CompilerVersion < 35}
        LMsgObj.AddPair('tool_calls', TJSONUtils.ParseAsArray(FTmpToolCallsStr));
{$ELSE}
        LMsgObj.AddPair('tool_calls', TJSonArray(TJSonArray.ParseJSONValue(FTmpToolCallsStr)));
{$ENDIF}
      end;
    end;

    // Reuse the ResMsg from the previous round if it exists (preserves MediaFiles
    // added during tool calls). Otherwise, create a new one.
    var LOwnsMsg: Boolean;
    if Assigned(FAsyncResMsg) then
    begin
      LFinalMsg  := FAsyncResMsg;
      FAsyncResMsg := nil; // consumido
      LOwnsMsg   := False;
    end
    else
    begin
      LFinalMsg := TAiChatMessage.Create('', 'assistant');
      LOwnsMsg  := True;
    end;

    try
      ParseChat(AJson, LFinalMsg);
    except
      on E: Exception do
      begin
        if LOwnsMsg then
          LFinalMsg.Free;
        raise;
      end;
    end;

    // Clean up buffers for the next request
    FLastContent := '';
    FTmpResponseText := '';
    FTmpToolCallsStr := '';
  end;

begin
  if not Self.Asynchronous then
    Exit;

  AAbort := FAbort;
  if FAbort then
  begin
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallsStr := '';
    FAsyncResMsg := nil; // discard pending ResMsg on abort
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, nil, nil, 'system', 'abort');
    Exit;
  end;

  try
    // 1. Accumulate the new data chunk
    // ISSUE #124: if the chunk ends in an incomplete UTF-8 character, DataString
    // throws EEncodingError; it exits without doing Clear and the next chunk completes it
    // (letting it fall to the general except would abort the turn with DoError).
    try
      LChunkStr := FResponse.DataString;
    except
      on EEncodingError do
        Exit;
    end;
    FResponse.Clear;
    FTmpResponseText := FTmpResponseText + LChunkStr;
    LStreamFinished := False;

    // --- Main loop to process lines (Ollama sends one JSON per line) ---
    while Pos(#10, FTmpResponseText) > 0 do
    begin
      LJsonLine := Copy(FTmpResponseText, 1, Pos(#10, FTmpResponseText) - 1);
      Delete(FTmpResponseText, 1, Pos(#10, FTmpResponseText));

      if LJsonLine.Trim.IsEmpty then
        Continue;

      LJsonObject := TJSonObject.ParseJSONValue(LJsonLine.Trim) as TJSonObject;
      if not Assigned(LJsonObject) then
        Continue;

      try
        LDone := LJsonObject.GetValue<Boolean>('done', False);

        if not LDone then // --- INTERMEDIATE CHUNK ---
        begin
          if LJsonObject.TryGetValue<TJSonObject>('message', LMessageObj) then
          begin
            LRole := LMessageObj.GetValue<string>('role', 'assistant');

            // 1. CAPTURE TOOL CALLS (Essential for Ollama)
            if LMessageObj.TryGetValue<TJSonArray>('tool_calls', LToolCallsArray) then
            begin
              // Store the tools string. Ollama usually sends them
              // complete in a single chunk, but we overwrite it for safety.
              FTmpToolCallsStr := LToolCallsArray.ToJSON;
              DoStateChange(acsToolCalling, 'Tool call detected in stream...');
            end;

            // 2. PROCESS CONTENT
            if LMessageObj.TryGetValue<string>('content', LContentPart) and (LContentPart <> '') then
            begin
              LContentPart := StringReplace(LContentPart, #$A, sLineBreak, [rfReplaceAll]);
              FLastContent := FLastContent + LContentPart;
              if Assigned(FOnReceiveDataEvent) then
                FOnReceiveDataEvent(Self, nil, LJsonObject, LRole, LContentPart);
            end;

            // 3. PROCESS REASONING (Thinking)
            if LMessageObj.TryGetValue<string>('thinking', LThinkingPart) and (LThinkingPart <> '') then
            begin
              LThinkingPart := StringReplace(LThinkingPart, #$A, sLineBreak, [rfReplaceAll]);
              if Assigned(OnReceiveThinking) then
                OnReceiveThinking(Self, nil, LJsonObject, LRole, LThinkingPart);
            end;
          end;
        end
        else // --- FINAL CHUNK ---
        begin
          ProcessFinalJsonObject(LJsonObject);
          Break;
        end;
      finally
        LJsonObject.Free;
      end;
    end;

    // --- HANDLING FINAL CHUNK (without newline) ---
    if (not LStreamFinished) and (FTmpResponseText.Trim <> '') then
    begin
      LJsonObject := TJSonObject.ParseJSONValue(FTmpResponseText.Trim) as TJSonObject;
      if Assigned(LJsonObject) then
      try
        if LJsonObject.GetValue<Boolean>('done', False) then
          ProcessFinalJsonObject(LJsonObject);
      finally
        LJsonObject.Free;
      end;
    end;

  except
    on E: Exception do
    begin
      FBusy := False;
      FPendingToolRun := False;
      DoError('Error in OnInternalReceiveData (Ollama Stream): ' + E.Message, E);
    end;
  end;
end;


procedure TAiOllamaChat.ParseChat(JObj: TJSonObject; ResMsg: TAiChatMessage);
var
  LMessageObj: TJSonObject;
  LToolCallsArray: TJSonArray;
  LAskMsg: TAiChatMessage;
  LRole, LContent, LModel, LReasoning: string;
  LPromptTokens, LEvalTokens: Integer;

  // Tools
  LChoicesSimulado: TJSonArray;
  LFunciones: TAiToolsFunctions;
  LToolCall: TAiToolsFunction;
  LToolMsg, LHistoryToolMsg: TAiChatMessage;

  // Parallelism
  TaskList: array of ITask;
  I, NumTasks: Integer;
  Clave: String;

  // Files
  Code: TMarkdownCodeExtractor;
  CodeFiles: TCodeFileList;
  CodeFile: TCodeFile;
  MF: TAiMediaFile;
  St: TStringStream;
begin
  if not Assigned(JObj) then
    Exit;

  // 1. EXTRACT METADATA AND STATISTICS
  LModel := JObj.GetValue<string>('model', '');
  // Ollama uses specific names for tokens
  LPromptTokens := JObj.GetValue<Integer>('prompt_eval_count', 0);
  LEvalTokens := JObj.GetValue<Integer>('eval_count', 0);

  // Update the component's global counters
  Self.Prompt_tokens := Self.Prompt_tokens + LPromptTokens;
  Self.Completion_tokens := Self.Completion_tokens + LEvalTokens;
  Self.Total_tokens := Self.Total_tokens + LPromptTokens + LEvalTokens;

  // 2. VALIDATE THE EXISTENCE OF "MESSAGE"
  if not JObj.TryGetValue<TJSonObject>('message', LMessageObj) then
  begin
    // If there is no message but the JSON indicates it finished, trigger the end event
    if JObj.GetValue<Boolean>('done', False) then
    begin
      DoStateChange(acsFinished, 'Done');
      if Assigned(FOnReceiveDataEnd) then
        FOnReceiveDataEnd(Self, ResMsg, JObj, 'assistant', FLastContent);
    end;
    Exit;
  end;

  // 3. EXTRACT MESSAGE CONTENT
  LRole := LMessageObj.GetValue<string>('role', 'assistant');
  LReasoning := LMessageObj.GetValue<string>('thinking', '');
  LContent := LMessageObj.GetValue<string>('content', '');

  // Synchronize the content accumulated during streaming (FLastContent) with ResMsg
  if (FLastContent <> '') then
    ResMsg.Prompt := FLastContent
  else
  begin
    ResMsg.Prompt := LContent;
    FLastContent := LContent;
  end;

  // Configure response message properties
  ResMsg.Role := LRole;
  ResMsg.Model := LModel;
  ResMsg.ReasoningContent := LReasoning;
  ResMsg.Prompt_tokens := LPromptTokens;
  ResMsg.Completion_tokens := LEvalTokens;
  ResMsg.Total_tokens := LPromptTokens + LEvalTokens;

  // Trigger thinking event if the model returned reasoning
  if (LReasoning <> '') and Assigned(OnReceiveThinking) then
    OnReceiveThinking(Self, ResMsg, JObj, LRole, LReasoning);

  LAskMsg := GetLastMessage;

  // 4. FUNCTION CALLING LOGIC (TOOLS)
  // Check whether Ollama has returned tool_calls
  if LMessageObj.TryGetValue<TJSonArray>('tool_calls', LToolCallsArray) and (LToolCallsArray.Count > 0) then
  begin
    // --- CASE A: The model requests to execute tools ---

    // A.1 Store the assistant message (the tool request) in the history
    LHistoryToolMsg := TAiChatMessage.Create(ResMsg.Prompt, LRole);
    LHistoryToolMsg.Tool_calls := LToolCallsArray.ToJSON;
    LHistoryToolMsg.Id := FMessages.Count + 1;
    FMessages.Add(LHistoryToolMsg);

    DoStateChange(acsToolExecuting, 'Executing local tools...');

    // A.2 Extract the function definitions
    LChoicesSimulado := TJSonArray.Create;
    LFunciones := nil;
    try
      // Simulate a structure compatible with ExtractToolCallFromJson
      LChoicesSimulado.Add(JObj.Clone as TJSonObject);
      LFunciones := ExtractToolCallFromJson(LChoicesSimulado);

      if (LFunciones <> nil) and (LFunciones.Count > 0) then
      begin
        // A.3 Parallel execution of the found functions
        NumTasks := LFunciones.Count;
        SetLength(TaskList, NumTasks);
        I := 0;

        for Clave in LFunciones.Keys do
        begin
          LToolCall := LFunciones[Clave];
          LToolCall.ResMsg := ResMsg;
          LToolCall.AskMsg := LAskMsg;

          TaskList[I] := TTask.Create(
            procedure
            var
              CapturaTool: TAiToolsFunction;
            begin
              CapturaTool := LToolCall;
              try
                DoCallFunction(CapturaTool);
              except
                on E: Exception do
                begin
                  CapturaTool.Response := '{"error": "' + StringReplace(E.Message, '"', '''', [rfReplaceAll]) + '"}';
                  TThread.Queue(nil,
                    procedure
                    begin
                      DoError('Function Execution Error: ' + CapturaTool.Name, E);
                    end);
                end;
              end;
            end);
          TaskList[I].Start;
          Inc(I);
        end;

        // Wait for all functions to finish (controlled blocking).
        // Pump Synchronize/Queue so the app does not hang if a tool call accesses
        // the VCL/FMX via TThread.Synchronize (issue #103).
        // NOTE: CheckSynchronize is ONLY valid on the main thread; on secondary
        // threads (Indy workers of a headless service, agent TTask)
        // THROWS an exception "CheckSynchronize called from thread X". Outside the main
        // thread we only wait. Same criterion as TMCPClientSSE.WaitForInitialization.
        while not TTask.WaitForAll(TaskList, 10) do
          if TThread.CurrentThread.ThreadID = MainThreadID then
            CheckSynchronize(0)
          else
            TThread.Sleep(10);

        // A.4 Add the function results (role: tool) to the history
        for LToolCall in LFunciones.Values do
        begin
          LToolMsg := TAiChatMessage.Create(LToolCall.Response, 'tool', LToolCall.Id, LToolCall.Name);
          for var LMF in LToolCall.MediaFiles do
            LToolMsg.AddMediaFile(LMF);
          LToolCall.MediaFiles.OwnsObjects := False;
          LToolMsg.Id := FMessages.Count + 1;
          FMessages.Add(LToolMsg);
        end;

        // A.5 Re-run Run so the model analyzes the tool results
        // Clear ResMsg to receive the final response
        ResMsg.Prompt := '';
        ResMsg.Tool_calls := '';
        FLastContent := '';
        // In async mode, preserve ResMsg between rounds so ProcessFinalJsonObject
        // reuses it and keeps the MediaFiles added during tool calls.
        // ISSUE #100: DO NOT re-enter THTTPClient from its receive callback (this
        // ParseChat runs inside OnInternalReceiveData). Continuation is deferred to
        // OnRequestCompletedEvent (base). In sync, re-enter directly (safe).
        if Self.Asynchronous then
        begin
          FAsyncResMsg := ResMsg;
          FPendingToolRun := True;
        end
        else
          Self.Run(nil, ResMsg);
      end;
    finally
      LChoicesSimulado.Free;
      if Assigned(LFunciones) then
        LFunciones.Free;
    end;
  end
  else
  begin
    // --- CASE B: Normal text response or end of chain ---

    // B.1 Automatic extraction of code blocks if requested
    if (cap_ExtractCode in SessionCaps) and (ResMsg.Prompt <> '') then
    begin
      Code := TMarkdownCodeExtractor.Create;
      try
        CodeFiles := Code.ExtractCodeFiles(ResMsg.Prompt);
        for CodeFile in CodeFiles do
        begin
          St := TStringStream.Create(CodeFile.Code, TEncoding.UTF8);
          try
            St.Position := 0;
            MF := TAiMediaFile.Create;
            // Load the extracted code as an attachment to the message
            MF.LoadFromStream('file.' + CodeFile.FileType, St as TMemoryStream);
            ResMsg.MediaFiles.Add(MF);
          finally
            St.Free;
          end;
        end;
      finally
        Code.Free;
      end;
    end;

    // B.2 Notify response processing (External hooks)
    DoProcessResponse(LAskMsg, ResMsg, FLastContent);

    // B.3 History management (Avoid Double Add in Async)
    // In synchronous mode, TAiChat.Run adds the message when it finishes.
    // In async mode, since Run has already exited, we must add it here.
    if Self.Asynchronous and (FMessages.IndexOf(ResMsg) = -1) then
    begin
      ResMsg.Id := FMessages.Count + 1;
      FMessages.Add(ResMsg);
    end;

    // B.4 Finalization and notification to the UI
    DoStateChange(acsFinished, 'Done');

    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, ResMsg, JObj, LRole, FLastContent);

    FBusy := False;
  end;
end;

// ----- FUNCIONES DE GESTIÓN DE MODELOS  -----------

procedure TAiOllamaChat.CopyModel(const aSourceModel, aDestinationModel: string);
var
  LJsonObject: TJSonObject;
  LBodyStream: TStringStream;
  LResponse: IHTTPResponse;
  LUrl: string;
begin
  LUrl := TPath.Combine(Self.Url, 'api/copy');
  LJsonObject := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LJsonObject.AddPair('source', aSourceModel);
    LJsonObject.AddPair('destination', aDestinationModel);
    LBodyStream.WriteString(LJsonObject.ToJSON);
    LBodyStream.Position := 0;

    FClient.ContentType := 'application/json';
    LResponse := FClient.Post(LUrl, LBodyStream);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error copying model: %d - %s', [LResponse.StatusCode, LResponse.ContentAsString]);

  finally
    LJsonObject.Free;
    LBodyStream.Free;
  end;
end;

procedure TAiOllamaChat.CreateModel(const aNewModelName, aModelfileContent: string);
var
  LJsonObject: TJSonObject;
  LBodyStream: TStringStream;
  LResponse: IHTTPResponse;
  LResponseStream: TStringStream;
  LUrl: string;
  LJsonLines: TArray<string>;
  LLine: string;
  LStatusObj: TJSonObject;
  LStatus: string;
  LCompleted, LTotal: Int64;
begin
  LUrl := TPath.Combine(Self.Url, 'api/create');
  LJsonObject := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  LResponseStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LJsonObject.AddPair('name', aNewModelName);
    LJsonObject.AddPair('modelfile', aModelfileContent);
    LJsonObject.AddPair('stream', TJSONBool.Create(True)); // Always in stream for progress
    LBodyStream.WriteString(LJsonObject.ToJSON);
    LBodyStream.Position := 0;

    FClient.ContentType := 'application/json';
    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error creating model: %d - %s', [LResponse.StatusCode, LResponse.ContentAsString]);

    // Process the response in stream (line by line)
    LResponseStream.Position := 0;
    LJsonLines := LResponseStream.DataString.Split([#10], TStringSplitOptions.ExcludeEmpty);

    for LLine in LJsonLines do
    begin
      if Assigned(OnProgressEvent) then
      begin
        LStatusObj := TJSonObject.ParseJSONValue(LLine) as TJSonObject;
        if Assigned(LStatusObj) then
          try
            LStatus := LStatusObj.GetValue<string>('status');
            LCompleted := 0;
            LTotal := 0;
            LStatusObj.TryGetValue<Int64>('completed', LCompleted);
            LStatusObj.TryGetValue<Int64>('total', LTotal);
            OnProgressEvent(Self, LStatus, LCompleted, LTotal);
          finally
            LStatusObj.Free;
          end;
      end;
    end;

  finally
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
  end;
end;

procedure TAiOllamaChat.DeleteModel(const aModelName: string);
var
  LJsonObject: TJSonObject;
  LBodyStream: TStringStream;
  LResponse: IHTTPResponse;
  LUrl: string;
begin
  LUrl := TPath.Combine(Self.Url, 'api/delete');
  LJsonObject := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LJsonObject.AddPair('name', aModelName);
    LBodyStream.WriteString(LJsonObject.ToJSON);
    LBodyStream.Position := 0;

    // TNetHTTPClient.Delete needs a TStream as body
    LResponse := FClient.Delete(LUrl, LBodyStream);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error deleting model: %d - %s', [LResponse.StatusCode, LResponse.ContentAsString]);

  finally
    LJsonObject.Free;
    LBodyStream.Free;
  end;
end;

procedure TAiOllamaChat.PullModel(const aModelName: string);
var
  LJsonObject: TJSonObject;
  LBodyStream: TStringStream;
  LResponse: IHTTPResponse;
  LResponseStream: TStringStream;
  LUrl: string;
  LJsonLines: TArray<string>;
  LLine: string;
  LStatusObj: TJSonObject;
  LStatus: string;
  LCompleted, LTotal: Int64;
begin
  LUrl := TPath.Combine(Self.Url, 'api/pull');
  LJsonObject := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  LResponseStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LJsonObject.AddPair('name', aModelName);
    LJsonObject.AddPair('stream', TJSONBool.Create(True)); // Always in stream for progress
    LBodyStream.WriteString(LJsonObject.ToJSON);
    LBodyStream.Position := 0;

    FClient.ContentType := 'application/json';
    // Make the synchronous call, but Ollama returns the full stream at once
    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error downloading model: %d - %s', [LResponse.StatusCode, LResponse.ContentAsString]);

    // Process the response in stream (line by line)
    LResponseStream.Position := 0;
    LJsonLines := LResponseStream.DataString.Split([#10], TStringSplitOptions.ExcludeEmpty);

    for LLine in LJsonLines do
    begin
      // If the progress event is assigned, trigger it
      if Assigned(OnProgressEvent) then
      begin
        LStatusObj := TJSonObject.ParseJSONValue(LLine) as TJSonObject;
        if Assigned(LStatusObj) then
          try
            LStatus := LStatusObj.GetValue<string>('status');
            LCompleted := 0;
            LTotal := 0;
            // TryGetValue is safer if the fields are not always present
            LStatusObj.TryGetValue<Int64>('completed', LCompleted);
            LStatusObj.TryGetValue<Int64>('total', LTotal);
            OnProgressEvent(Self, LStatus, LCompleted, LTotal);
          finally
            LStatusObj.Free;
          end;
      end;
    end;

  finally
    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
  end;
end;

function TAiOllamaChat.ShowModelInfo(const aModelName: string): TJSonObject;
var
  LJsonObject: TJSonObject;
  LBodyStream: TStringStream;
  LResponse: IHTTPResponse;
  LUrl: string;
begin
  //Result := nil;
  LUrl := TPath.Combine(Self.Url, 'api/show');
  LJsonObject := TJSonObject.Create;
  LBodyStream := TStringStream.Create('', TEncoding.UTF8);
  try
    LJsonObject.AddPair('name', aModelName);
    LBodyStream.WriteString(LJsonObject.ToJSON);
    LBodyStream.Position := 0;

    FClient.ContentType := 'application/json';
    LResponse := FClient.Post(LUrl, LBodyStream);

    if LResponse.StatusCode = 200 then
    begin
      // The caller is responsible for freeing the returned TJSONObject
      Result := TJSonObject.ParseJSONValue(LResponse.ContentAsString) as TJSonObject;
    end
    else
    begin
      raise Exception.CreateFmt('Error getting model information: %d - %s', [LResponse.StatusCode, LResponse.ContentAsString]);
    end;

  finally
    LJsonObject.Free;
    LBodyStream.Free;
  end;
end;

initialization
  TAiChatFactory.Instance.RegisterDriver(TAiOllamaChat);

end.
