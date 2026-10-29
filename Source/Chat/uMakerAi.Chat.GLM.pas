unit uMakerAi.Chat.GLM;

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
// Nombre: Gustavo Enriquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

// Driver GLM (Zhipu AI / Z.ai) - API OpenAI-compatible
// Docs: https://docs.z.ai/api-reference/llm/chat-completion
// International endpoint: https://api.z.ai/api/paas/v4/
// (Mainland China: https://open.bigmodel.cn/api/paas/v4/ - change the URL property)
//
// API particularities (Aug 2026):
// - thinking: {"type":"enabled"|"disabled"} in the request; the reasoning comes back
//   in message.reasoning_content (parsing and streaming already capture it in the base class).
// - reasoning_effort (low/medium/high) is only accepted by the glm-5.x family.
// - Sampling ranges narrower than OpenAI: temperature [0,1], top_p [0.01,1],
//   max_tokens up to 131072 (the driver applies a clamp).
// - Vision in OpenAI format (image_url); also accepts video_url and file_url.

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

  TAiGLMChat = Class(TAiChat)
  Private
    Function ModelSupportsThinking(Const AModel: String): Boolean;
  Protected
    Function InitChatCompletions: String; Override;
  Public
    Function GetMessages: TJSonArray; Override;
    Constructor Create(Sender: TComponent); Override;
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;
  Published
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://api.z.ai/api/paas/v4/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGLMChat]);
end;

{ TAiGLMChat }

class function TAiGLMChat.GetDriverName: string;
Begin
  Result := 'GLM';
End;

class procedure TAiGLMChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@GLM_API_KEY');
  Params.Add('Model=glm-4.7');
  Params.Add('Max_Tokens=8192');
  Params.Add('URL=' + GlAIUrl);
End;

class function TAiGLMChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiGLMChat.Create(Sender);
End;

constructor TAiGLMChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@GLM_API_KEY';
  Model := 'glm-4.7';
  Url := GlAIUrl;
end;

function TAiGLMChat.ModelSupportsThinking(Const AModel: String): Boolean;
begin
  // Hybrid family with controllable thinking: glm-4.5+, glm-4.6(v), glm-4.7 and
  // the whole glm-5.x family (includes glm-5v-*). Earlier models (glm-4-32b...)
  // do not accept the thinking field.
  Result := StartsText('glm-5', AModel) or StartsText('glm-4.5', AModel) or
    StartsText('glm-4.6', AModel) or StartsText('glm-4.7', AModel);
end;

function TAiGLMChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice, jThinking: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel: String;
  LTemperature, LTopP: Double;
  LMaxTokens: Integer;
begin

  If User = '' then
    User := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'glm-4.7';

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
        Raise Exception.Create('The Tools property is malformed; it must be a JsonArray');
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

    // Hybrid thinking: the API has it ENABLED by default on glm-4.7/5.x,
    // so the driver controls it explicitly (same pattern as DeepSeek V4):
    // cap_Reasoning -> enabled; without the cap -> disabled (fast/economic mode).
    // EXCEPTION: glm-5.3 uses forced thinking and does NOT accept disabled.
    // The reasoning arrives in reasoning_content (captured by the base class).
    if ModelSupportsThinking(LModel) then
    begin
      jThinking := TJSonObject.Create;
      if (cap_Reasoning in ModelConfig.ModelCaps) or StartsText('glm-5.3', LModel) then
      begin
        jThinking.AddPair('type', 'enabled');
        // reasoning_effort documented only on glm-5.2/5.3; values low/high/max
        // (API default: max). Same mapping as DeepSeek V4.
        if StartsText('glm-5.2', LModel) or StartsText('glm-5.3', LModel) then
        begin
          case ModelConfig.ThinkingLevel of
            tlLow:    AJSONObject.AddPair('reasoning_effort', 'low');
            tlMedium: AJSONObject.AddPair('reasoning_effort', 'high');
            tlHigh:   AJSONObject.AddPair('reasoning_effort', 'max');
            // tlDefault: not sent; the API uses max
          end;
        end;
      end
      else
        jThinking.AddPair('type', 'disabled');
      AJSONObject.AddPair('thinking', jThinking);
    end;

    // Z.ai clamps temperature to [0,1] (with thinking they recommend 1.0)
    LTemperature := Trunc(Temperature * 100) / 100;
    if LTemperature > 1 then
      LTemperature := 1;
    if LTemperature < 0 then
      LTemperature := 0;
    AJSONObject.AddPair('temperature', TJSONNumber.Create(LTemperature));

    // max_tokens accepts up to 131072
    LMaxTokens := Max_tokens;
    if LMaxTokens > 131072 then
      LMaxTokens := 131072;
    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(LMaxTokens));

    // top_p clamped to [0.01, 1]; 0 = not sent (uses the model default)
    If Top_p <> 0 then
    Begin
      LTopP := Top_p;
      if LTopP > 1 then
        LTopP := 1;
      if LTopP < 0.01 then
        LTopP := 0.01;
      AJSONObject.AddPair('top_p', TJSONNumber.Create(LTopP));
    End;

    Lista.CommaText := Stop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    End;

    // Note: frequency/presence_penalty, n, logprobs and seed are not sent;
    // the Z.ai API does not document them and they may be rejected.

    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));

    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

function TAiGLMChat.GetMessages: TJSonArray;
var
  I: Integer;
  JObj: TJSonObject;
  Msg: TAiChatMessage;
begin
  Result := inherited GetMessages;
  // Z.ai REQUIRES returning reasoning_content in the multi-turn history to
  // keep the reasoning coherent (docs: "remember to return the
  // historical reasoning_content"). TAiChatMessages.ToJSon does not serialize it
  // by default; same pattern as DeepSeek V4.
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

initialization

TAiChatFactory.Instance.RegisterDriver(TAiGLMChat);

end.
