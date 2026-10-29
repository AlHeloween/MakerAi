unit uMakerAi.Chat.Qwen;

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
// Author: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

// Qwen Driver (Alibaba Cloud Model Studio / DashScope) - OpenAI-compatible API
// Docs: https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope
// International endpoint (Singapore): https://dashscope-intl.aliyuncs.com/compatible-mode/v1/
// Other regions: change URL (US: https://dashscope-us.aliyuncs.com/compatible-mode/v1/,
// China: https://dashscope.aliyuncs.com/compatible-mode/v1/). The API key is tied to the
// region where it was created; with a different region the API responds 401.
//
// Particularities verified at runtime (Sep 2026):
// - Reasoning comes ACTIVATED by default in hybrid models (qwen3.x, qwen-plus/flash/
//   turbo, qwen3-max, VL, omni). The driver ALWAYS controls it with enable_thinking:
//   cap_Reasoning -> true; without the cap -> false (fast mode, without paying reasoning tokens).
//   enable_thinking=false is accepted by all tested models (those that do not reason ignore it).
//   Reasoning returns in reasoning_content (captured by the base class, with and without streaming).
// - thinking_budget (reasoning tokens) derived from ThinkingLevel.
// - Models that only reason (qwq-*, *-thinking-*): enable_thinking is not sent.
//   qwq-plus ONLY responds in streaming: without stream it returns empty and without error.
// - Open-weight models (qwen3-32b, qwen3.6-27b, ...) accept enable_thinking=true only in
//   streaming (400 without stream): in synchronous mode the driver sends false.
// - tools + stream work (the documentation restriction does not apply to these models).
// - OpenAI format Vision (image_url) in qwen3.8-flash/max, qwen3.7-plus, qwen3-vl-*,
//   qwen3.8-omni-flash. Very small images (2x2) are rejected with 400.
// - Audio input (omni, asr): the API requires data URI in input_audio.data
//   ('data:audio/wav;base64,...'); the plain base64 that the common serializer builds
//   responds 400 "URL does not appear to be valid". InitChatCompletions rewrites it.
//
// Phase 2 (Sep 2026), due to capability gap like other drivers:
// - [cap_GenImage] -> Native API multimodal-generation (synchronous, returns URLs):
//   qwen-image-3.0 [default], qwen-image-2.0(-pro), qwen-image-max, z-image-turbo,
//   wan2.7-image(-pro). Size in ImageParams.Params.Values['size'] ('1024*1024').
//   Editing: attached images to the prompt (1 to 3) are the input; they go as data
//   URI. qwen-image-edit(-plus/-max) [default: plus], and also qwen-image-2.0/3.0 and
//   wan2.7-image; z-image-turbo does not edit. Without 'size' the aspect ratio is preserved.
// - [cap_GenVideo] -> wan (asynchronous task with polling every 5 s). 0 attached images
//   = text to video (wan2.6-t2v), 1 = image to video (wan2.6-i2v-flash), 2 = first and
//   last frame (wan2.2-kf2v-flash). VideoParams.Params passes as-is to the API
//   (duration, resolution, size, audio, seed...); default 720P.
// - [cap_GenAudio] -> qwen3-tts-flash via the native API (returns URL of a WAV).
//   Voice in TtsParams.Voice (default Cherry), language in TtsParams.Language.
// - [cap_Audio] / cmTranscription -> qwen3-asr-flash via chat/completions with
//   input_audio. In cmTranscription the Prompt travels as context (proper nouns,
//   jargon) and improves the spelling of the transcribed text.
// - Embeddings (uMakerAi.Embeddings.Qwen) and rerank (uMakerAi.Qwen.Rerank) go separately.

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils,
  System.RegularExpressions, System.NetEncoding,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Core, uMakerAI.chat.Messages;

Type

  TAiQwenChat = Class(TAiChat)
  Private
    Function IsThinkingOnly(Const AModel: String): Boolean;
    Function IsOpenWeight(Const AModel: String): Boolean;
    // Model for a dedicated task: session's if it belongs to that family, otherwise the default
    Function ModelFor(Const AMarker, ADefault: String): String;
    // Synchronous JSON POST (own client: not dependent on Asynchronous)
    Function PostJSON(Const AUrl: String; ABody: TJSonObject; AAsyncTask: Boolean = False): TJSonObject;
    Function GetJSON(Const AUrl: String): TJSonObject;
    Function DownloadMedia(Const AUrl, AFileName: String): TAiMediaFile;
    // DashScope native API endpoint derived from Url (compatible-mode/v1 -> api/v1)
    Function NativeUrl(Const APath: String): String;
    Procedure FixAudioDataUris(AMessages: TJSonArray);
    procedure SetTranslateTerms(const Value: TStrings);
  Protected
    FTranslateTo: String;
    FTranslateFrom: String;
    FTranslateDomain: String;
    FTranslateTerms: TStrings;
    FCumulativeStream: Boolean; // ongoing stream for a qwen-mt cumulative
    FCumSent: String;           // text already delivered to the common parser
    FCumPending: String;        // incomplete SSE line from the previous chunk
    // Body for qwen-mt: the API accepts ONLY one 'user' message (no system,
    // history or tools) and without translation_options it does not translate: it converses
    Function BuildTranslationRequest(Const AModel: String; AStream: Boolean): String;
    // qwen-mt-plus and qwen-mt-turbo emit in streaming the ACCUMULATED text in each
    // chunk (incremental_output does not change it); the common parser concatenates them.
    // Each SSE line is rewritten to the increment before passing it to the base.
    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
      var AAbort: Boolean); Override;
    Function IncrementalSSELine(Const ALine: String): String;
    Function InitChatCompletions: String; Override;
    // Image request body (generate or edit); separated to test it without network
    Function BuildImageRequest(AskMsg: TAiChatMessage): TJSonObject;
    // Video request: returns the body and in AEndpoint the path (t2v/i2v or kf2v)
    Function BuildVideoRequest(AskMsg: TAiChatMessage; out AEndpoint: String): TJSonObject;
    function InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    // TTS model according to voice (custom ones require their own model)
    Function TtsModelFor(Const AVoice: String): String;
    function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;
  Public
    Constructor Create(Sender: TComponent); Override;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;
    Destructor Destroy; Override;
  Published
    // Translation with qwen-mt-* models (ignored with any other model).
    // Destination language: name in English ('English', 'Spanish') or code ('en', 'es').
    // Empty = English
    property TranslateTo: String read FTranslateTo write FTranslateTo;
    // Source language; empty = 'auto' (detection)
    property TranslateFrom: String read FTranslateFrom write FTranslateFrom;
    // Domain context in English, e.g. 'Colombian accounting (PUC)'
    property TranslateDomain: String read FTranslateDomain write FTranslateDomain;
    // Glossary, one entry per line: source term=target term
    property TranslateTerms: TStrings read FTranslateTerms write SetTranslateTerms;
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/';
  GlDefaultModel = 'qwen3.8-flash';
  GlDefaultImageModel = 'qwen-image-3.0';
  GlDefaultEditModel = 'qwen-image-edit-plus'; // fastest editing (~9 s)
  GlDefaultTtsModel = 'qwen3-tts-flash';
  GlDefaultAsrModel = 'qwen3-asr-flash';
  GlVoiceCloneModel = 'qwen3-tts-vc-2026-01-22';  // voices qwen-tts-vc-* (TAiQwenVoices)
  GlVoiceDesignModel = 'qwen3-tts-vd-2026-01-26'; // voices qwen-tts-vd-*
  GlMediaTimeout = 180000; // an image takes 10-40 s
  GlDefaultT2VModel = 'wan2.6-t2v';        // ~45 s for 5 s video, with audio
  GlDefaultI2VModel = 'wan2.6-i2v-flash';
  GlDefaultKF2VModel = 'wan2.2-kf2v-flash';
  GlVideoTimeout = 600000;                 // wan2.7 takes ~95 s; margin for queue
  GlVideoPoll = 5000;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiQwenChat]);
end;

{ TAiQwenChat }

class function TAiQwenChat.GetDriverName: string;
Begin
  Result := 'Qwen';
End;

class procedure TAiQwenChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@DASHSCOPE_API_KEY');
  Params.Add('Model=' + GlDefaultModel);
  Params.Add('Max_Tokens=8192');
  Params.Add('URL=' + GlAIUrl);
End;

class function TAiQwenChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiQwenChat.Create(Sender);
End;

constructor TAiQwenChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@DASHSCOPE_API_KEY';
  Model := GlDefaultModel;
  Url := GlAIUrl;
  FTranslateTerms := TStringList.Create;
end;

destructor TAiQwenChat.Destroy;
begin
  FTranslateTerms.Free;
  inherited;
end;

procedure TAiQwenChat.SetTranslateTerms(const Value: TStrings);
begin
  FTranslateTerms.Assign(Value);
end;

function TAiQwenChat.IncrementalSSELine(Const ALine: String): String;
var
  V: TJSONValue;
  jChoices: TJSonArray;
  jDelta: TJSonObject;
  LFull, LInc: String;
begin
  Result := ALine;
  if not StartsText('data:', Trim(ALine)) or ContainsText(ALine, '[DONE]') then
    Exit;
  V := TJSonObject.ParseJSONValue(Trim(Copy(Trim(ALine), 6, MaxInt)));
  try
    if not (V is TJSonObject) or not TJSonObject(V).TryGetValue<TJSonArray>('choices', jChoices) or
      (jChoices.Count = 0) or not (jChoices.Items[0] as TJSonObject).TryGetValue<TJSonObject>('delta', jDelta) or
      not jDelta.TryGetValue<String>('content', LFull) then
      Exit;
    // What exceeds what has already been emitted is delivered. If the model rewrote a
    // previous section, that change is lost: what has been emitted cannot be withdrawn.
    if Length(LFull) > Length(FCumSent) then
      LInc := Copy(LFull, Length(FCumSent) + 1, MaxInt)
    else
      LInc := '';
    if Length(LFull) > Length(FCumSent) then
      FCumSent := LFull;
    jDelta.RemovePair('content').Free;
    jDelta.AddPair('content', LInc);
    Result := 'data: ' + V.ToJSON;
  finally
    V.Free;
  end;
end;

procedure TAiQwenChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
var
  S, LOut, LLine: String;
  P: Integer;
begin
  if not FCumulativeStream or not FClient.Asynchronous then
  begin
    inherited;
    Exit;
  end;
  try
    S := FResponse.DataString;
  except
    on EEncodingError do
      Exit; // split UTF-8 character: the next chunk completes it
  end;
  FResponse.Clear;
  S := FCumPending + S;
  LOut := '';
  P := Pos(#10, S);
  while P > 0 do
  begin
    LLine := Copy(S, 1, P - 1);
    Delete(S, 1, P);
    LOut := LOut + IncrementalSSELine(LLine) + #10;
    P := Pos(#10, S);
  end;
  FCumPending := S;
  if (Trim(S) = '[DONE]') or (Trim(S) = 'data: [DONE]') then
  begin
    LOut := LOut + S;
    FCumPending := '';
  end;
  FResponse.WriteString(LOut);
  inherited;
end;

function TAiQwenChat.BuildTranslationRequest(Const AModel: String; AStream: Boolean): String;
var
  jBody, jMsg, jOpts, jTerm, jStreamOpts: TJSonObject;
  jMsgs, jTerms: TJSonArray;
  LMsg: TAiChatMessage;
  I: Integer;
begin
  // The text to translate is the last user message; the rest of the history
  // is not sent (the API rejects more than one message)
  LMsg := nil;
  for I := Messages.Count - 1 downto 0 do
    if SameText(Messages[I].Role, 'user') then
    begin
      LMsg := Messages[I];
      Break;
    end;
  if (LMsg = nil) or (Trim(LMsg.Prompt) = '') then
    raise Exception.Create('Qwen: no text to translate.');

  FCumulativeStream := AStream and (ContainsText(AModel, 'qwen-mt-plus') or ContainsText(AModel, 'qwen-mt-turbo'));
  FCumSent := '';
  FCumPending := '';

  jBody := TJSonObject.Create;
  try
    jBody.AddPair('model', AModel);
    jBody.AddPair('stream', TJSONBool.Create(AStream));
    if AStream then
    begin
      jStreamOpts := TJSonObject.Create;
      jStreamOpts.AddPair('include_usage', TJSONBool.Create(True));
      jBody.AddPair('stream_options', jStreamOpts);
    end;

    jMsg := TJSonObject.Create;
    jMsg.AddPair('role', 'user');
    jMsg.AddPair('content', LMsg.Prompt);
    jMsgs := TJSonArray.Create;
    jMsgs.Add(jMsg);
    jBody.AddPair('messages', jMsgs);

    jOpts := TJSonObject.Create;
    jOpts.AddPair('source_lang', IfThen(Trim(FTranslateFrom) = '', 'auto', Trim(FTranslateFrom)));
    jOpts.AddPair('target_lang', IfThen(Trim(FTranslateTo) = '', 'English', Trim(FTranslateTo)));
    if Trim(FTranslateDomain) <> '' then
      jOpts.AddPair('domains', Trim(FTranslateDomain));
    if FTranslateTerms.Count > 0 then
    begin
      jTerms := TJSonArray.Create;
      for I := 0 to FTranslateTerms.Count - 1 do
        if Trim(FTranslateTerms.Names[I]) <> '' then
        begin
          jTerm := TJSonObject.Create;
          jTerm.AddPair('source', Trim(FTranslateTerms.Names[I]));
          jTerm.AddPair('target', Trim(FTranslateTerms.ValueFromIndex[I]));
          jTerms.Add(jTerm);
        end;
      jOpts.AddPair('terms', jTerms);
    end;
    jBody.AddPair('translation_options', jOpts);

    Result := StringReplace(jBody.ToJSON, '\/', '/', [rfReplaceAll]);
  finally
    jBody.Free;
  end;
end;

function TAiQwenChat.IsThinkingOnly(Const AModel: String): Boolean;
begin
  // Always reason: do not accept turning it off, so enable_thinking is not sent
  Result := StartsText('qwq', AModel) or ContainsText(AModel, '-thinking');
end;

function TAiQwenChat.IsOpenWeight(Const AModel: String): Boolean;
begin
  // Open weights: the size is in the name (qwen3-32b, qwen3.6-27b, qwen3-235b-a22b...)
  Result := TRegEx.IsMatch(AModel, '-\d+(\.\d+)?b(-|$)', [roIgnoreCase]);
end;

function TAiQwenChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice, jStreamOpts: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico, LThinking: Boolean;
  Res, LModel: String;
  LTemperature: Double;
begin

  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := GlDefaultModel;

  LAsincronico := Self.Asynchronous;
  FClient.Asynchronous := LAsincronico;

  // qwen-mt: own request (single user message + translation_options)
  if ContainsText(LModel, 'qwen-mt') then
    Exit(BuildTranslationRequest(LModel, LAsincronico));

  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  Try

    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));
    if LAsincronico then
    begin
      // Without this, the stream does not bring usage and token counters remain at 0
      jStreamOpts := TJSonObject.Create;
      jStreamOpts.AddPair('include_usage', TJSONBool.Create(True));
      AJSONObject.AddPair('stream_options', jStreamOpts);
    end;

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

    JArr := GetMessages;
    FixAudioDataUris(JArr);
    AJSONObject.AddPair('messages', JArr);

    AJSONObject.AddPair('model', LModel);

    // Reasoning: the API brings it ACTIVATED by default in hybrids, so it is
    // always controlled (same criteria as GLM / DeepSeek V4): cap_Reasoning
    // -> true; without the cap -> false (fast and without reasoning tokens).
    if not IsThinkingOnly(LModel) then
    begin
      LThinking := cap_Reasoning in ModelConfig.ModelCaps;
      // Open-weight models only reason in streaming (400 in synchronous)
      if LThinking and IsOpenWeight(LModel) and not LAsincronico then
        LThinking := False;
      AJSONObject.AddPair('enable_thinking', TJSONBool.Create(LThinking));
      if LThinking then
        case ModelConfig.ThinkingLevel of
          tlLow:    AJSONObject.AddPair('thinking_budget', TJSONNumber.Create(1024));
          tlMedium: AJSONObject.AddPair('thinking_budget', TJSONNumber.Create(4096));
          tlHigh:   AJSONObject.AddPair('thinking_budget', TJSONNumber.Create(16384));
          // tlDefault: without budget, the model's maximum length
        end;
    end;

    // DashScope accepts temperature in [0, 2)
    LTemperature := Trunc(Temperature * 100) / 100;
    if LTemperature >= 2 then
      LTemperature := 1.99;
    if LTemperature < 0 then
      LTemperature := 0;
    AJSONObject.AddPair('temperature', TJSONNumber.Create(LTemperature));

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

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

function TAiQwenChat.ModelFor(Const AMarker, ADefault: String): String;
begin
  Result := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if not ContainsText(Result, AMarker) then
    Result := ADefault;
end;

function TAiQwenChat.NativeUrl(Const APath: String): String;
begin
  Result := Url;
  if ContainsText(Result, 'compatible-mode/v1') then
    Result := StringReplace(Result, 'compatible-mode/v1', 'api/v1', [rfIgnoreCase]);
  if not Result.EndsWith('/') then
    Result := Result + '/';
  Result := Result + APath;
end;

function TAiQwenChat.PostJSON(Const AUrl: String; ABody: TJSonObject; AAsyncTask: Boolean): TJSonObject;
var
  Client: TNetHTTPClient;
  Body: TStringStream;
  Res: IHTTPResponse;
  V: TJSONValue;
begin
  Client := TNetHTTPClient.Create(nil);
  Body := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
  try
{$IF CompilerVersion >= 34}
    Client.SynchronizeEvents := False;
{$ENDIF}
    Client.ResponseTimeout := GlMediaTimeout;
    Client.ContentType := 'application/json';
    if AAsyncTask then
      // Long tasks (video): the API responds with a task_id to poll
      Res := Client.Post(AUrl, Body, nil, [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey),
        TNetHeader.Create('X-DashScope-Async', 'enable')])
    else
      Res := Client.Post(AUrl, Body, nil, [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)]);
    if Res.StatusCode <> 200 then
      raise Exception.CreateFmt('Qwen %d: %s', [Res.StatusCode, Res.ContentAsString(TEncoding.UTF8)]);
    V := TJSonObject.ParseJSONValue(Res.ContentAsString(TEncoding.UTF8));
    if not (V is TJSonObject) then
    begin
      V.Free;
      raise Exception.Create('Qwen: the response is not a JSON object');
    end;
    Result := TJSonObject(V);
  finally
    Body.Free;
    Client.Free;
  end;
end;

function TAiQwenChat.GetJSON(Const AUrl: String): TJSonObject;
var
  Client: TNetHTTPClient;
  Res: IHTTPResponse;
  V: TJSONValue;
begin
  Client := TNetHTTPClient.Create(nil);
  try
{$IF CompilerVersion >= 34}
    Client.SynchronizeEvents := False;
{$ENDIF}
    Res := Client.Get(AUrl, nil, [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)]);
    if Res.StatusCode <> 200 then
      raise Exception.CreateFmt('Qwen %d: %s', [Res.StatusCode, Res.ContentAsString(TEncoding.UTF8)]);
    V := TJSonObject.ParseJSONValue(Res.ContentAsString(TEncoding.UTF8));
    if not (V is TJSonObject) then
    begin
      V.Free;
      raise Exception.Create('Qwen: the response is not a JSON object');
    end;
    Result := TJSonObject(V);
  finally
    Client.Free;
  end;
end;

function TAiQwenChat.DownloadMedia(Const AUrl, AFileName: String): TAiMediaFile;
var
  Client: TNetHTTPClient;
  St: TMemoryStream;
  Res: IHTTPResponse;
begin
  Client := TNetHTTPClient.Create(nil);
  St := TMemoryStream.Create;
  try
{$IF CompilerVersion >= 34}
    Client.SynchronizeEvents := False;
{$ENDIF}
    Client.ResponseTimeout := GlMediaTimeout;
    Res := Client.Get(AUrl, St);
    if Res.StatusCode <> 200 then
      raise Exception.CreateFmt('Qwen: could not download %s (%d)', [AFileName, Res.StatusCode]);
    St.Position := 0;
    Result := TAiMediaFile.Create;
    try
      Result.LoadFromStream(AFileName, St);
    except
      Result.Free;
      raise;
    end;
  finally
    St.Free;
    Client.Free;
  end;
end;

procedure TAiQwenChat.FixAudioDataUris(AMessages: TJSonArray);
var
  VMsg, VPart: TJSONValue;
  jContent: TJSonArray;
  jAudio: TJSonObject;
  LData, LFormat: String;
begin
  if not Assigned(AMessages) then
    Exit;
  for VMsg in AMessages do
    if (VMsg is TJSonObject) and TJSonObject(VMsg).TryGetValue<TJSonArray>('content', jContent) then
      for VPart in jContent do
        if (VPart is TJSonObject) and TJSonObject(VPart).TryGetValue<TJSonObject>('input_audio', jAudio) and
          jAudio.TryGetValue<String>('data', LData) and not StartsText('data:', LData) and
          not StartsText('http', LData) then
        begin
          LFormat := jAudio.GetValue<String>('format', 'wav');
          if (LFormat = '') or SameText(LFormat, 'x-wav') then
            LFormat := 'wav';
          jAudio.RemovePair('data').Free;
          jAudio.AddPair('data', 'data:audio/' + LFormat + ';base64,' + LData);
        end;
end;

function TAiQwenChat.BuildImageRequest(AskMsg: TAiChatMessage): TJSonObject;
// Body of multimodal-generation to generate (text only) or edit (1 to 3
// images attached to the prompt, which arrive intact because cap_Image is not in the
// gap of an image model)
var
  jInput, jMsg, jPart, jParams: TJSonObject;
  jMsgs, jContent: TJSonArray;
  LSize, LModel: String;
  LImages: TAiMediaFilesArray;
  MF: TAiMediaFile;
begin
  if Trim(AskMsg.Prompt) = '' then
    raise Exception.Create('A prompt is required to generate the image.');
  LImages := AskMsg.MediaFiles.GetMediaList([Tfc_Image], False);
  if Length(LImages) > 3 then
    raise Exception.CreateFmt('Qwen: editing accepts 1 to 3 images (%d received).', [Length(LImages)]);
  if Length(LImages) > 0 then
  begin
    LModel := ModelFor('image', GlDefaultEditModel);
    if StartsText('z-image', LModel) then
      raise Exception.Create('Qwen: ' + LModel + ' only generates; to edit use qwen-image-edit-plus, ' +
        'qwen-image-2.0/3.0 or wan2.7-image.');
  end
  else
    LModel := ModelFor('image', GlDefaultImageModel);

  Result := TJSonObject.Create;
  try
    Result.AddPair('model', LModel);

    jContent := TJSonArray.Create;
    for MF in LImages do
    begin
      jPart := TJSonObject.Create;
      if (MF.Content.Size = 0) and (MF.UrlMedia <> '') then
        jPart.AddPair('image', MF.UrlMedia)
      else
        jPart.AddPair('image', 'data:' + MF.MimeType + ';base64,' + MF.Base64);
      jContent.Add(jPart);
    end;
    jPart := TJSonObject.Create;
    jPart.AddPair('text', AskMsg.Prompt);
    jContent.Add(jPart);
    jMsg := TJSonObject.Create;
    jMsg.AddPair('role', 'user');
    jMsg.AddPair('content', jContent);
    jMsgs := TJSonArray.Create;
    jMsgs.Add(jMsg);
    jInput := TJSonObject.Create;
    jInput.AddPair('messages', jMsgs);
    Result.AddPair('input', jInput);

    // Each family supports different sizes (qwen-image-plus only 1328*1328, 1664*928...).
    // When editing without explicit size, the model preserves the original aspect ratio
    // (1024x576 -> 1376x768); forcing 1024*1024 would distort it.
    LSize := ImageParams.Params.Values['size'];
    if (LSize = '') and (Length(LImages) = 0) then
      LSize := '1024*1024';
    LSize := StringReplace(LSize, 'x', '*', [rfIgnoreCase]);
    jParams := TJSonObject.Create;
    if LSize <> '' then
      jParams.AddPair('size', LSize);
    if N > 1 then
      jParams.AddPair('n', TJSONNumber.Create(N));
    if ImageParams.Params.Values['negative_prompt'] <> '' then
      jParams.AddPair('negative_prompt', ImageParams.Params.Values['negative_prompt']);
    jParams.AddPair('watermark', TJSONBool.Create(SameText(ImageParams.Params.Values['watermark'], 'true')));
    Result.AddPair('parameters', jParams);
  except
    Result.Free;
    raise;
  end;
end;

function TAiQwenChat.InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
// POST api/v1/services/aigc/multimodal-generation/generation (synchronous)
// -> output.choices[].message.content[] with {"image": url}
var
  jBody, jRes, jItem: TJSonObject;
  jChoices, jOut: TJSonArray;
  VChoice, VItem: TJSONValue;
  LUrl: String;
  LCount: Integer;
begin
  Result := '';
  FBusy := True;
  FLastError := '';
  FLastPrompt := AskMsg.Prompt;
  jBody := nil;
  jRes := nil;
  try
    DoStateChange(acsConnecting, 'Generating image...');
    jBody := BuildImageRequest(AskMsg);
    jRes := PostJSON(NativeUrl('services/aigc/multimodal-generation/generation'), jBody);

    LCount := 0;
    if jRes.TryGetValue<TJSonArray>('output.choices', jChoices) then
      for VChoice in jChoices do
        if (VChoice is TJSonObject) and TJSonObject(VChoice).TryGetValue<TJSonArray>('message.content', jOut) then
          for VItem in jOut do
            if VItem is TJSonObject then
            begin
              jItem := TJSonObject(VItem);
              if jItem.TryGetValue<String>('image', LUrl) then
              begin
                Inc(LCount);
                ResMsg.MediaFiles.Add(DownloadMedia(LUrl, Format('qwen_image_%d.png', [LCount])));
              end;
            end;
    if LCount = 0 then
      raise Exception.Create('Qwen: the response does not contain images: ' + Copy(jRes.ToJSON, 1, 300));

    if ResMsg.Role = '' then
      ResMsg.Role := 'assistant';
    DoStateChange(acsFinished, 'Done');
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, ResMsg, jRes, 'assistant', ResMsg.Prompt);
  finally
    jBody.Free;
    jRes.Free;
    FBusy := False;
  end;
end;

function TAiQwenChat.BuildVideoRequest(AskMsg: TAiChatMessage; out AEndpoint: String): TJSonObject;
// According to the images attached to the prompt:
//   0 -> text to video (t2v)        video-generation/video-synthesis, input.prompt
//   1 -> image to video (i2v)       same endpoint, input.img_url
//   2 -> first and last frame       image2video/video-synthesis, first/last_frame_url
// A -t2v model with an image switches to its -i2v counterpart (all exist: wan2.1/2.2/2.5/2.6/2.7).
// VideoParams.Params passes as-is to 'parameters' (duration, resolution, size, audio,
// seed, prompt_extend, watermark...), except negative_prompt goes in 'input'.
var
  jInput, jParams: TJSonObject;
  LImages: TAiMediaFilesArray;
  LModel, LKey, LVal: String;
  I, LInt: Integer;

  function ImageRef(MF: TAiMediaFile): String;
  begin
    if (MF.Content.Size = 0) and (MF.UrlMedia <> '') then
      Result := MF.UrlMedia
    else
      Result := 'data:' + MF.MimeType + ';base64,' + MF.Base64;
  end;

begin
  if Trim(AskMsg.Prompt) = '' then
    raise Exception.Create('A prompt is required to generate the video.');
  LImages := AskMsg.MediaFiles.GetMediaList([Tfc_Image], False);
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  case Length(LImages) of
    0:
      begin
        if not ContainsText(LModel, 't2v') then
          LModel := GlDefaultT2VModel;
        AEndpoint := 'services/aigc/video-generation/video-synthesis';
      end;
    1:
      begin
        if ContainsText(LModel, '-t2v') then
          LModel := StringReplace(LModel, '-t2v', '-i2v', [rfIgnoreCase])
        else if not ContainsText(LModel, 'i2v') then
          LModel := GlDefaultI2VModel;
        AEndpoint := 'services/aigc/video-generation/video-synthesis';
      end;
    2:
      begin
        if not ContainsText(LModel, 'kf2v') then
          LModel := GlDefaultKF2VModel;
        AEndpoint := 'services/aigc/image2video/video-synthesis';
      end;
  else
    raise Exception.CreateFmt('Qwen: video accepts 0 images (text), 1 (image to video) ' +
      'or 2 (first and last frame); %d received.', [Length(LImages)]);
  end;

  Result := TJSonObject.Create;
  try
    Result.AddPair('model', LModel);
    jInput := TJSonObject.Create;
    jInput.AddPair('prompt', AskMsg.Prompt);
    if Length(LImages) = 1 then
      jInput.AddPair('img_url', ImageRef(LImages[0]))
    else if Length(LImages) = 2 then
    begin
      jInput.AddPair('first_frame_url', ImageRef(LImages[0]));
      jInput.AddPair('last_frame_url', ImageRef(LImages[1]));
    end;
    Result.AddPair('input', jInput);

    jParams := TJSonObject.Create;
    Result.AddPair('parameters', jParams);
    for I := 0 to VideoParams.Params.Count - 1 do
    begin
      LKey := Trim(VideoParams.Params.Names[I]);
      LVal := Trim(VideoParams.Params.ValueFromIndex[I]);
      if (LKey = '') or (LVal = '') then
        Continue;
      if SameText(LKey, 'negative_prompt') then
        jInput.AddPair('negative_prompt', LVal)
      else if SameText(LVal, 'true') or SameText(LVal, 'false') then
        jParams.AddPair(LKey, TJSONBool.Create(SameText(LVal, 'true')))
      else if TryStrToInt(LVal, LInt) then
        jParams.AddPair(LKey, TJSONNumber.Create(LInt))
      else
        jParams.AddPair(LKey, LVal);
    end;

    // Without explicit size the API returns 1080P (the most expensive). 720P is requested: the
    // t2v from wan2.5/2.6 take it via 'size' (ignore 'resolution'); the rest via 'resolution'.
    if (jParams.GetValue('size') = nil) and (jParams.GetValue('resolution') = nil) then
    begin
      if (Length(LImages) = 0) and (ContainsText(LModel, 'wan2.5') or ContainsText(LModel, 'wan2.6')) then
        jParams.AddPair('size', '1280*720')
      else
        jParams.AddPair('resolution', '720P');
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TAiQwenChat.InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
// Asynchronous task: POST with X-DashScope-Async -> output.task_id; GET api/v1/tasks/{id}
// until SUCCEEDED (output.video_url, mp4 with audio in wan2.5+) or FAILED/CANCELED.
// The video is downloaded to ResMsg.MediaFiles as qwen_video.mp4 (the URL expires in 24 h).
var
  jBody, jRes, jTask: TJSonObject;
  LEndpoint, LTaskId, LStatus, LVideoUrl, LMsg: String;
  LElapsed: Integer;
begin
  Result := '';
  FBusy := True;
  FAbort := False;
  FLastError := '';
  FLastPrompt := AskMsg.Prompt;
  jBody := nil;
  jRes := nil;
  try
    jBody := BuildVideoRequest(AskMsg, LEndpoint);
    DoStateChange(acsConnecting, 'Sending video (' + jBody.GetValue<String>('model') + ')...');
    jRes := PostJSON(NativeUrl(LEndpoint), jBody, True);
    LTaskId := jRes.GetValue<String>('output.task_id', '');
    if LTaskId = '' then
      raise Exception.Create('Qwen: the response does not contain a task_id: ' + Copy(jRes.ToJSON, 1, 300));

    DoStateChange(acsToolExecuting, 'Generating video (task ' + LTaskId + ')...');
    LElapsed := 0;
    LStatus := '';
    LVideoUrl := '';
    LMsg := '';
    while (LElapsed < GlVideoTimeout) and not FAbort do
    begin
      TThread.Sleep(GlVideoPoll);
      Inc(LElapsed, GlVideoPoll);
      try
        jTask := GetJSON(NativeUrl('tasks/' + LTaskId));
      except
        Continue; // transient query error: retry until timeout
      end;
      try
        LStatus := jTask.GetValue<String>('output.task_status', '');
        LVideoUrl := jTask.GetValue<String>('output.video_url', '');
        LMsg := jTask.GetValue<String>('output.message', '');
      finally
        jTask.Free;
      end;
      if (LStatus = 'SUCCEEDED') or (LStatus = 'FAILED') or (LStatus = 'CANCELED') or (LStatus = 'UNKNOWN') then
        Break;
    end;

    if FAbort then
      Exit;
    if LStatus <> 'SUCCEEDED' then
      raise Exception.CreateFmt('Qwen: video did not complete (status=%s after %d s, task %s) %s',
        [LStatus, LElapsed div 1000, LTaskId, LMsg]);
    if LVideoUrl = '' then
      raise Exception.Create('Qwen: task completed without video_url (task ' + LTaskId + ')');

    ResMsg.MediaFiles.Add(DownloadMedia(LVideoUrl, 'qwen_video.mp4'));
    if ResMsg.Role = '' then
      ResMsg.Role := 'assistant';
    DoStateChange(acsFinished, 'Done');
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, ResMsg, nil, 'assistant', ResMsg.Prompt);
  finally
    jBody.Free;
    jRes.Free;
    FBusy := False;
  end;
end;

function TAiQwenChat.TtsModelFor(Const AVoice: String): String;
begin
  // A custom voice (TAiQwenVoices) only works with the model it was registered for:
  // chosen by the prefix of the id if the session does not set it.
  if StartsText('qwen-tts-vc-', AVoice) and not ContainsText(Model, 'tts-vc') then
    Result := GlVoiceCloneModel
  else if StartsText('qwen-tts-vd-', AVoice) and not ContainsText(Model, 'tts-vd') then
    Result := GlVoiceDesignModel
  else
    Result := ModelFor('-tts', GlDefaultTtsModel);
end;

function TAiQwenChat.InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
// POST api/v1/services/aigc/multimodal-generation/generation with input {text, voice,
// language_type} -> output.audio.url (WAV, expires in 24 h)
const
  // TtsParams.Language accepts the ISO code; the API wants the English name
  Codes: array[0..9] of string = ('es', 'en', 'zh', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'ru');
  Names: array[0..9] of string = ('Spanish', 'English', 'Chinese', 'French', 'German', 'Italian',
    'Portuguese', 'Japanese', 'Korean', 'Russian');
var
  jBody, jInput, jRes: TJSonObject;
  LVoice, LLang, LUrl, LData: String;
  I: Integer;
  MF: TAiMediaFile;
begin
  Result := '';
  if Trim(AskMsg.Prompt) = '' then
    raise Exception.Create('A text is required to generate the audio.');
  FBusy := True;
  FLastError := '';
  FLastPrompt := AskMsg.Prompt;
  jBody := TJSonObject.Create;
  jRes := nil;
  try
    DoStateChange(acsConnecting, 'Generating audio...');
    LVoice := TtsParams.Voice;
    if LVoice = '' then
      LVoice := 'Cherry';
    LLang := TtsParams.Language;
    for I := Low(Codes) to High(Codes) do
      if SameText(LLang, Codes[I]) then
        LLang := Names[I];
    if LLang = '' then
      LLang := 'Auto';

    jBody.AddPair('model', TtsModelFor(LVoice));
    jInput := TJSonObject.Create;
    jInput.AddPair('text', AskMsg.Prompt);
    jInput.AddPair('voice', LVoice);
    jInput.AddPair('language_type', LLang);
    jBody.AddPair('input', jInput);

    jRes := PostJSON(NativeUrl('services/aigc/multimodal-generation/generation'), jBody);

    if jRes.TryGetValue<String>('output.audio.url', LUrl) and (LUrl <> '') then
      MF := DownloadMedia(LUrl, 'qwen_tts.wav')
    else if jRes.TryGetValue<String>('output.audio.data', LData) and (LData <> '') then
    begin
      MF := TAiMediaFile.Create;
      MF.LoadFromBase64('qwen_tts.wav', LData);
    end
    else
      raise Exception.Create('Qwen: the response does not contain audio: ' + Copy(jRes.ToJSON, 1, 300));
    ResMsg.MediaFiles.Add(MF);

    if ResMsg.Role = '' then
      ResMsg.Role := 'assistant';
    DoStateChange(acsFinished, 'Done');
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, ResMsg, jRes, 'assistant', '');
  finally
    jBody.Free;
    jRes.Free;
    FBusy := False;
  end;
end;

function TAiQwenChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
// qwen3-asr-flash via chat/completions with input_audio (data URI). Two uses:
// - cmTranscription: the transcription IS the response (ParseJsonTranscript) and the
//   Prompt travels as context for the recognizer.
// - Phase 1 bridge (a text model receives audio): only fills
//   aMediaFile.Transcription; RunNew injects it into the prompt and the final
//   response comes from the chat model.
var
  jBody, jMsg, jPart, jAudio, jAsr, jRes, jText, jUsage: TJSonObject;
  jMsgs, jContent: TJSonArray;
  LMime, LText: String;
  LIn, LOut, LTotal: Integer;
  LBridge: Boolean;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('An audio file with content is required for transcription.');
  LBridge := ChatMode <> cmTranscription;
  jBody := TJSonObject.Create;
  jRes := nil;
  try
    DoStateChange(acsConnecting, 'Transcribing audio...');
    jBody.AddPair('model', ModelFor('-asr', GlDefaultAsrModel));
    jBody.AddPair('stream', TJSONBool.Create(False));
    jMsgs := TJSonArray.Create;
    jBody.AddPair('messages', jMsgs);

    if not LBridge and (Trim(AskMsg.Prompt) <> '') then
    begin
      jPart := TJSonObject.Create;
      jPart.AddPair('text', AskMsg.Prompt);
      jContent := TJSonArray.Create;
      jContent.Add(jPart);
      jMsg := TJSonObject.Create;
      jMsg.AddPair('role', 'system');
      jMsg.AddPair('content', jContent);
      jMsgs.Add(jMsg);
    end;

    LMime := aMediaFile.MimeType;
    if (LMime = '') or SameText(LMime, 'audio/x-wav') then
      LMime := 'audio/wav';
    jAudio := TJSonObject.Create;
    jAudio.AddPair('data', 'data:' + LMime + ';base64,' + aMediaFile.Base64);
    jPart := TJSonObject.Create;
    jPart.AddPair('type', 'input_audio');
    jPart.AddPair('input_audio', jAudio);
    jContent := TJSonArray.Create;
    jContent.Add(jPart);
    jMsg := TJSonObject.Create;
    jMsg.AddPair('role', 'user');
    jMsg.AddPair('content', jContent);
    jMsgs.Add(jMsg);

    jAsr := TJSonObject.Create;
    jAsr.AddPair('enable_itn', TJSONBool.Create(False));
    if TranscriptionParams.Language <> '' then
      jAsr.AddPair('language', TranscriptionParams.Language);
    jBody.AddPair('asr_options', jAsr);

    jRes := PostJSON(Url + 'chat/completions', jBody);
    LText := jRes.GetValue<String>('choices[0].message.content', '');
    LIn := jRes.GetValue<Integer>('usage.prompt_tokens', 0);
    LOut := jRes.GetValue<Integer>('usage.completion_tokens', 0);
    LTotal := jRes.GetValue<Integer>('usage.total_tokens', LIn + LOut);

    if LBridge then
    begin
      aMediaFile.Transcription := LText;
      aMediaFile.Procesado := True;
      Prompt_tokens := Prompt_tokens + LIn;
      Completion_tokens := Completion_tokens + LOut;
      Total_tokens := Total_tokens + LTotal;
    end
    else
    begin
      // OpenAI format of /audio/transcriptions, to reuse ParseJsonTranscript
      jText := TJSonObject.Create;
      try
        jText.AddPair('text', LText);
        jUsage := TJSonObject.Create;
        jUsage.AddPair('input_tokens', TJSONNumber.Create(LIn));
        jUsage.AddPair('output_tokens', TJSONNumber.Create(LOut));
        jUsage.AddPair('total_tokens', TJSONNumber.Create(LTotal));
        jText.AddPair('usage', jUsage);
        ParseJsonTranscript(jText, ResMsg, aMediaFile);
      finally
        jText.Free;
      end;
    end;
    Result := LText;
  finally
    jBody.Free;
    jRes.Free;
  end;
end;

initialization

TAiChatFactory.Instance.RegisterDriver(TAiQwenChat);

end.
