unit uMakerAi.Chat.DeepSeek;

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
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Embeddings, uMakerAi.Core, uMakerAI.chat.Messages;

Type

  TAiDeepSeekChat = Class(TAiChat)
  Private
    FTmpReasoning: String; // Accumulates reasoning_content during SSE streaming (deepseek-reasoner)
  Protected
    Function InitChatCompletions: String; Override;
    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;
  Public
    Function GetMessages: TJSonArray; Override;
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;
  Published
  End;

procedure Register;

implementation

// Models of the V4 era that accept the 'thinking' block. They are listed
// explicitly because the API changed name in Sep 2026: the canonical name is
// 'deepseek-flash' and 'deepseek-v4-flash' remains as a legacy alias. The
// legacy aliases (deepseek-chat / deepseek-reasoner) also route to deepseek-flash
// and accept the parameter (verified at runtime Sep-2026). If the model is not
// here then 'thinking' is not sent and the API default (thinking ON) is used.
function ModelSupportsThinking(const AModel: String): Boolean;
begin
  Result := StartsText('deepseek-v4', AModel)      // deepseek-v4-pro / legacy v4-flash
         or StartsText('deepseek-flash', AModel)   // canonical since Sep 2026
         or SameText(AModel, 'deepseek-chat')
         or SameText(AModel, 'deepseek-reasoner');
end;

Const
  GlAIUrl = 'https://api.deepseek.com/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiDeepSeekChat]);
end;

{ TAiDeepSeekChat }

class function TAiDeepSeekChat.GetDriverName: string;
Begin
  Result := 'DeepSeek';
End;

class procedure TAiDeepSeekChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@DEEPSEEK_API_KEY');
  Params.Add('Model=deepseek-flash');
  Params.Add('Max_Tokens=8192');
  Params.Add('URL=https://api.deepseek.com/v1/');
End;

class function TAiDeepSeekChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiDeepSeekChat.Create(Sender);
End;

constructor TAiDeepSeekChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@DEEPSEEK_API_KEY';

  // deepseek-chat/deepseek-reasoner officially retired on Jul 24, 2026.
  // Sep 2026: the canonical name is 'deepseek-flash'; 'deepseek-v4-flash'
  // remains accepted as a legacy alias but that model has been retired.
  Model := 'deepseek-flash';
  Url := GlAIUrl;
end;

destructor TAiDeepSeekChat.Destroy;
begin

  inherited;
end;

function TAiDeepSeekChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel: String;
begin

  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'deepseek-flash';

  LAsincronico := Self.Asynchronous;
  FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  Try

    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    If Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAi).Text) <> '') then
    Begin

{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAi).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAi).Text));
{$ENDIF}
      If Not Assigned(JArr) then
        Raise Exception.Create('The Tools property is malformed, it must be a JsonArray');
      AJSONObject.AddPair('tools', JArr);

      If (Trim(Tool_choice) <> '') then
      Begin

{$IF CompilerVersion < 35}
        jToolChoice := TJSONUtils.ParseAsObject(Tool_choice);
{$ELSE}
        jToolChoice := TJSonObject(TJSONObject.ParseJSONValue(Tool_choice));
{$ENDIF}
        If Assigned(jToolChoice) then
          AJSONObject.AddPair('tool_choice', jToolChoice);
      End;
    End;

    AJSONObject.AddPair('messages', GetMessages);

    AJSONObject.AddPair('model', LModel);

    // V4 (Apr 2026): the API has thinking ENABLED by default with effort=high.
    // The driver controls it explicitly: cap_Reasoning enables thinking mode
    // (reasoning_effort according to ThinkingLevel); without the cap it sends disabled
    // to preserve the fast/cheap behavior like deepseek-chat.
    // In thinking mode the API ignores temperature/top_p/penalties (no error).
    if ModelSupportsThinking(LModel) then
    begin
      var jThinking := TJSonObject.Create;
      if cap_Reasoning in ModelConfig.ModelCaps then
      begin
        jThinking.AddPair('type', 'enabled');
        case ModelConfig.ThinkingLevel of
          tlLow:    AJSONObject.AddPair('reasoning_effort', 'low');
          tlMedium: AJSONObject.AddPair('reasoning_effort', 'high');
          tlHigh:   AJSONObject.AddPair('reasoning_effort', 'max');
          // tlDefault: not sent, API uses high
        end;
      end
      else
        jThinking.AddPair('type', 'disabled');
      AJSONObject.AddPair('thinking', jThinking);
    end;

    AJSONObject.AddPair('temperature', TJSONNumber.Create(Trunc(Temperature * 100) / 100));
    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));

    If Top_p <> 0 then
      AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

    AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Trunc(Frequency_penalty * 100) / 100));
    AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Trunc(Presence_penalty * 100) / 100));
    AJSONObject.AddPair('user', User);
    AJSONObject.AddPair('n', TJSONNumber.Create(N));

    Lista.CommaText := Stop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    End;

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

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

function TAiDeepSeekChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
begin
  FTmpReasoning := ''; // Reset before each new request
  // Reset to zero on each request: without this a turn without usage in its chunks
  // would inherit counters from the previous turn and inflate consumption.
  FStreamPromptTokens := 0;
  FStreamCompletionTokens := 0;
  FStreamFinishReason := '';
  Result := inherited InternalRunCompletions(ResMsg, AskMsg);
end;

function TAiDeepSeekChat.GetMessages: TJSonArray;
var
  I: Integer;
  JObj: TJSonObject;
  Msg: TAiChatMessage;
begin
  Result := inherited GetMessages;
  // For deepseek-reasoner: the assistant message with tool_calls MUST include
  // reasoning_content in the history. TAiChatMessages.ToJSon does not serialize it by default.
  if Self.Messages.Count <> Result.Count then Exit;
  for I := 0 to Self.Messages.Count - 1 do
  begin
    Msg := Self.Messages.Items[I];
    if (Msg.ReasoningContent <> '') and (Result.Items[I] is TJSonObject) then
    begin
      JObj := TJSonObject(Result.Items[I]);
      if JObj.GetValue('reasoning_content') = nil then
        JObj.AddPair('reasoning_content', Msg.ReasoningContent);
    end;
  end;
end;

procedure TAiDeepSeekChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
Var
  // Shared variables between the main body and ProcessLine (closure)
  jObj, Delta: TJSonObject;
  JToolCalls: TJSonArray;
  sJson, Value, Role1: String;
  P: Integer;
  jFunc: TJSonValue;
  ToolIndex: Integer;
  BufferObj, BufferFunc: TJSonObject;
  CombinedTools: TJSonArray;
  sToolCallsStr: String;
  SortedKeys: TList<Integer>;
  FakeResponseObj, FakeChoice, FakeMsg: TJSonObject;
  FakeChoicesArr: TJSonArray;
  FakeUsage: TJSonObject;
  TempMsg: TAiChatMessage;
  jArrChoices: TJSonArray;

  // Exact copy of ProcessLine from the base class (TAiChat.OnInternalReceiveData).
  // Handles SSE delta and [DONE] with tool_calls reconstruction.
  Procedure ProcessLine(ALine: String);
  Begin
    if ALine = '' then Exit;

    if StartsStr('data:', ALine) then
      ALine := Trim(Copy(ALine, 6, Length(ALine)));
    if ALine = '' then Exit;

    // -------------------------------------------------------------------
    // CASE 1: [DONE] — end of SSE stream
    // -------------------------------------------------------------------
    if ALine = '[DONE]' then
    Begin
      sToolCallsStr := '';
      if FTmpToolCallBuffer.Count > 0 then
      begin
        CombinedTools := TJSonArray.Create;
        try
          SortedKeys := TList<Integer>.Create;
          try
            Var aKey: Integer;
            for aKey in FTmpToolCallBuffer.Keys do
              SortedKeys.Add(aKey);
            SortedKeys.Sort;
            for aKey in SortedKeys do
              CombinedTools.Add(FTmpToolCallBuffer[aKey].Clone as TJSonObject);
          finally
            SortedKeys.Free;
          end;
          sToolCallsStr := CombinedTools.ToJSon;
        finally
          CombinedTools.Free;
          FTmpToolCallBuffer.Clear;
        end;
      end;

      FakeResponseObj := TJSonObject.Create;
      try
        FakeResponseObj.AddPair('id', 'stream-' + IntToStr(TThread.GetTickCount));
        FakeResponseObj.AddPair('model', Model);
        FakeUsage := TJSonObject.Create;
        // The tokens seen in the stream, not zeros: see capture in ProcessLine.
        FakeUsage.AddPair('prompt_tokens', TJSONNumber.Create(FStreamPromptTokens));
        FakeUsage.AddPair('completion_tokens', TJSONNumber.Create(FStreamCompletionTokens));
        FakeUsage.AddPair('total_tokens', TJSONNumber.Create(FStreamPromptTokens + FStreamCompletionTokens));
        FakeResponseObj.AddPair('usage', FakeUsage);
        FStreamPromptTokens := 0;
        FStreamCompletionTokens := 0;
        FakeChoicesArr := TJSonArray.Create;
        FakeChoice := TJSonObject.Create;
        FakeMsg := TJSonObject.Create;
        FakeMsg.AddPair('role', FTmpRole);
        if FLastContent <> '' then
          FakeMsg.AddPair('content', FLastContent);
        if FTmpReasoning <> '' then
          FakeMsg.AddPair('reasoning_content', FTmpReasoning); // Required by deepseek-reasoner in tool_calls
        if sToolCallsStr <> '' then
          FakeMsg.AddPair('tool_calls', TJSonArray(TJSonObject.ParseJSONValue(sToolCallsStr)));
        FakeChoice.AddPair('message', FakeMsg);
        if FStreamFinishReason <> '' then
          FakeChoice.AddPair('finish_reason', FStreamFinishReason)
        else
          FakeChoice.AddPair('finish_reason', 'stop');
        FStreamFinishReason := '';
        FakeChoicesArr.Add(FakeChoice);
        FakeResponseObj.AddPair('choices', FakeChoicesArr);
        TempMsg := TAiChatMessage.Create('', FTmpRole);
        try
          // If there are tool_calls, force Asynchronous=True before ParseChat.
          // This prevents external changes (ParamsChanged, etc.) from having
          // set FAsynchronous=False and causing the second round to come out with stream=false.
          if sToolCallsStr <> '' then
            Self.Asynchronous := True;
          // Same fix as in TAiChat: ParseChat again adds to FLastContent the
          // content of the synthetic message (which IS FLastContent) and OnReceiveDataEnd
          // received the duplicated text. Without content, the fallback to reasoning is kept.
          var LStreamedContent := FLastContent;
          ParseChat(FakeResponseObj, TempMsg);
          if LStreamedContent <> '' then
            FLastContent := LStreamedContent;
          if sToolCallsStr = '' then
          begin
            // In async, ParseChat does NOT trigger FOnReceiveDataEnd/acsFinished (guard
            // 'if not FClient.Asynchronous' in base, fix #99). The [DONE] handler is
            // responsible for emitting the final event here (same as the base and the
            // JSON stream=false path of this same driver).
            if FMessages.IndexOf(TempMsg) = -1 then
            begin
              TempMsg.Id := FMessages.Count + 1;
              FMessages.Add(TempMsg);
            end;
            DoStateChange(acsFinished, 'Done');
            if Assigned(FOnReceiveDataEnd) then
              FOnReceiveDataEnd(Self, TempMsg, Nil, FTmpRole, FLastContent);
            TempMsg := nil; // owned by FMessages
          end
          else
          begin
            // Tool calls: ParseChat (base) executed the tools and left
            // FPendingToolRun=True; the continuation (second async round) is deferred
            // by the base's OnRequestCompletedEvent. The second round will emit its own
            // final event. We do not set FBusy=False here: the turn is still active.
            DoStateChange(acsToolCalling, 'Executing tools, second round in progress...');
          end;
        finally
          if Assigned(TempMsg) then TempMsg.Free;
        end;
      finally
        FakeResponseObj.Free;
      end;
      if sToolCallsStr = '' then
        FBusy := False; // text: everything finished
      // tool_calls: FBusy remains True — closed by the second round
      FTmpReasoning := ''; // Clear for the next round or next request
      Exit;
    End;

    // -------------------------------------------------------------------
    // CASE 2: Standard SSE JSON with delta
    // -------------------------------------------------------------------
    var LParsedLine := TJSonObject.ParseJSONValue(ALine);
    if not (LParsedLine is TJSonObject) then
    begin
      LParsedLine.Free;
      Exit;
    end;
    jObj := TJSonObject(LParsedLine);
    Try
      jArrChoices := jObj.GetValue<TJSonArray>('choices');
      if (jArrChoices <> nil) and (jArrChoices.Count > 0) then
      begin
        // Keep the real finish_reason from the provider for the synthetic closure.
        var sChunkFinish: string := '';
        if jArrChoices.Items[0].TryGetValue<string>('finish_reason', sChunkFinish) and (sChunkFinish <> '') then
          FStreamFinishReason := sChunkFinish;

        Delta := jArrChoices.Items[0].GetValue<TJSonObject>('delta');
        if Assigned(Delta) then
        begin
          if Delta.TryGetValue<String>('role', Role1) then
            FTmpRole := Role1;

          Value := '';
          if Delta.TryGetValue<String>('reasoning', Value) or
             Delta.TryGetValue<String>('reasoning_content', Value) then
          begin
            FTmpReasoning := FTmpReasoning + Value; // Accumulate to include in history
            if (Value <> '') and Assigned(OnReceiveThinking) then
            begin
              Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
              OnReceiveThinking(Self, Nil, jObj, FTmpRole, Value);
            end;
          end;

          var JVal: TJSonValue;
          JVal := Delta.GetValue('content');
          if Assigned(JVal) and (JVal is TJSONString) then
          begin
            Value := JVal.Value;
            FLastContent := FLastContent + Value;
            if Assigned(FOnReceiveDataEvent) and (Value <> '') then
            begin
              Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
              FOnReceiveDataEvent(Self, Nil, jObj, FTmpRole, Value);
            end;
          end
          else if Assigned(JVal) and (JVal is TJSonArray) then
            ParseDeltaContentArray(TJSonArray(JVal), jObj);

          if Delta.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
          begin
            Var JToolCall: TJSonValue;
            for JToolCall in JToolCalls do
            begin
              if JToolCall is TJSonObject then
              begin
                var JTC := TJSonObject(JToolCall);
                if JTC.TryGetValue<Integer>('index', ToolIndex) then
                begin
                  if not FTmpToolCallBuffer.TryGetValue(ToolIndex, BufferObj) then
                  begin
                    BufferObj := TJSonObject.Create;
                    FTmpToolCallBuffer.Add(ToolIndex, BufferObj);
                  end;
                  if JTC.TryGetValue<String>('id', Value) then
                    if BufferObj.GetValue('id') = nil then
                      BufferObj.AddPair('id', Value);
                  if JTC.TryGetValue<String>('type', Value) then
                    if BufferObj.GetValue('type') = nil then
                      BufferObj.AddPair('type', Value);
                  if JTC.TryGetValue<TJSonObject>('function', TJSonObject(jFunc)) then
                  begin
                    if not BufferObj.TryGetValue<TJSonObject>('function', BufferFunc) then
                    begin
                      BufferFunc := TJSonObject.Create;
                      BufferObj.AddPair('function', BufferFunc);
                    end;
                    if jFunc.TryGetValue<String>('name', Value) then
                    begin
                      var OldName: string := '';
                      if BufferFunc.TryGetValue<String>('name', OldName) then
                        BufferFunc.RemovePair('name');
                      BufferFunc.AddPair('name', OldName + Value);
                    end;
                    if jFunc.TryGetValue<String>('arguments', Value) then
                    begin
                      var OldArgs: string := '';
                      if BufferFunc.TryGetValue<String>('arguments', OldArgs) then
                        BufferFunc.RemovePair('arguments');
                      BufferFunc.AddPair('arguments', OldArgs + Value);
                    end;
                  end;
                end;
              end;
            end;
          end;
        end;
      end;

      // Real usage of the turn. It arrives in a chunk with empty choices, just before
      // [DONE], so it is read at the root level and NOT inside the if of choices.
      // Without this the synthetic closure below filled zeros and all DeepSeek
      // traffic in streaming was counted (and billed) as zero.
      var JStreamUsage: TJSonObject;
      if jObj.TryGetValue<TJSonObject>('usage', JStreamUsage) and Assigned(JStreamUsage) then
      begin
        var aIn  := JStreamUsage.GetValue<Integer>('prompt_tokens', 0);
        var aOut := JStreamUsage.GetValue<Integer>('completion_tokens', 0);
        if aIn  > 0 then FStreamPromptTokens     := aIn;
        if aOut > 0 then FStreamCompletionTokens := aOut;
      end;
    Finally
      jObj.Free;
    End;
  End; // ProcessLine

begin
  LogDebug('--OnInternalReceiveData DeepSeek--');
  // ISSUE #124: the log must not abort the stream if the chunk ends with an incomplete
  // UTF-8 character; the accumulation below is already protected by its try/except.
  try
    var LDbgBody := FResponse.DataString;
    if Length(LDbgBody) > 500 then
      LogDebug(Copy(LDbgBody, 1, 500) + '...[truncated]')
    else
      LogDebug(LDbgBody);
  except
    on EEncodingError do
      LogDebug('[partial UTF-8 chunk - log omitted]');
  end;

  If FClient.Asynchronous = False then Exit;

  AAbort := FAbort;
  If FAbort = True then
  Begin
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallBuffer.Clear;
    FTmpReasoning := '';
    If Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, Nil, Nil, 'system', 'abort');
    Exit;
  End;

  Try
    FTmpResponseText := FTmpResponseText + FResponse.DataString;
    FResponse.Clear;

    // -------------------------------------------------------------------
    // DEEPSEEK BLOCK: Complete JSON with choices[0].message
    // When DeepSeek uses stream=false with FClient.Asynchronous=True, the
    // response arrives as a complete JSON object (not SSE lines with delta).
    // We detect it at the beginning to process it directly.
    // -------------------------------------------------------------------
    sJson := Trim(FTmpResponseText);
    if StartsStr('{', sJson) then
    begin
      var LParsed := TJSonObject.ParseJSONValue(sJson);
      if LParsed is TJSonObject then
      begin
        var LJObj := TJSonObject(LParsed);
        try
          var LChoices: TJSonArray;
          var LChoice: TJSonObject;
          var LMessage: TJSonObject;
          LChoices := nil; LMessage := nil;
          if LJObj.TryGetValue<TJSonArray>('choices', LChoices) and
             Assigned(LChoices) and (LChoices.Count > 0) and
             (LChoices.Items[0] is TJSonObject) then
          begin
            LChoice := TJSonObject(LChoices.Items[0]);
            if LChoice.TryGetValue<TJSonObject>('message', LMessage) then
            begin
              var LFinishReason: string := '';
              LChoice.TryGetValue<String>('finish_reason', LFinishReason);
              if not LMessage.TryGetValue<String>('role', FTmpRole) then
                FTmpRole := 'assistant';
              FTmpResponseText := '';
              FBusy := False;
              TempMsg := TAiChatMessage.Create('', FTmpRole);
              try
                ParseChat(LJObj, TempMsg);
                if LFinishReason <> 'tool_calls' then
                begin
                  // Text response: add to history
                  if FMessages.IndexOf(TempMsg) = -1 then
                  begin
                    TempMsg.Id := FMessages.Count + 1;
                    FMessages.Add(TempMsg);
                  end;
                  DoStateChange(acsFinished, 'Done');
                  if Assigned(FOnReceiveDataEnd) then
                    FOnReceiveDataEnd(Self, TempMsg, Nil, FTmpRole, FLastContent);
                  TempMsg := nil; // owned by FMessages
                end
                else
                begin
                  // Tool calls: ParseChat (base) executed the tools and left
                  // FPendingToolRun=True; the second async round defers it to
                  // OnRequestCompletedEvent of the base. Do not fire event here.
                  DoStateChange(acsToolCalling, 'Second round in progress...');
                end;
              finally
                if Assigned(TempMsg) then TempMsg.Free;
              end;
              Exit; // DeepSeek JSON processed — do not continue with SSE flow
            end;
          end;
        finally
          LJObj.Free;
        end;
      end
      else
        LParsed.Free;
    end;

    // -------------------------------------------------------------------
    // STANDARD SSE FLOW (stream=true, delta by lines)
    // -------------------------------------------------------------------

    // 1. Main loop: process complete lines terminated by #10
    while Pos(#10, FTmpResponseText) > 0 do
    begin
      P := Pos(#10, FTmpResponseText);
      sJson := Trim(Copy(FTmpResponseText, 1, P - 1));
      Delete(FTmpResponseText, 1, P);
      ProcessLine(sJson);
    end;

    // 2. Safety edge: [DONE] without final line break
    sJson := Trim(FTmpResponseText);
    if (sJson = '[DONE]') or (sJson = 'data: [DONE]') then
    begin
      ProcessLine(sJson);
      FTmpResponseText := '';
    end;

  Except
    // Silent error handling for stream (same as base class)
  End;
end;

initialization

TAiChatFactory.Instance.RegisterDriver(TAiDeepSeekChat);

end.
