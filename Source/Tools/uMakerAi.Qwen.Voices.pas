unit uMakerAi.Qwen.Voices;

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
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

// Custom voices for Qwen TTS (Alibaba Model Studio):
//   - CloneVoice: clones a voice from an audio sample (qwen-voice-enrollment)
//   - DesignVoice: creates a voice from a text description (qwen-voice-design)
//   - ListVoices / DeleteVoice
// API: POST api/v1/services/audio/tts/customization {model, input:{action,...}}
//
// The returned id is used as the voice for standard TTS: TtsParams.Voice := Id in a
// 'Qwen' connection with cap_GenAudio. A custom voice ONLY works with the model
// for which it was registered (qwen3-tts-flash rejects it); the chat driver chooses
// that model only by the id prefix (qwen-tts-vc-* / qwen-tts-vd-*).
//
// Clone voices only with consent of the voice owner.
// Verified at runtime (Sep 2026) against dashscope-intl.

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,
  uMakerAi.Core;

type
  TAiQwenVoiceKind = (qvkClone, qvkDesign);

  TAiQwenVoiceInfo = record
    Voice: string;        // id for TtsParams.Voice
    TargetModel: string;  // TTS model it works with
    Language: string;
    Created: string;
    Kind: TAiQwenVoiceKind;
  end;

  TAiQwenVoices = class(TComponent)
  private
    FApiKey: string;
    FUrl: string;
    FCloneModel: string;
    FDesignModel: string;
    FLastDesignFallback: string;
    function GetApiKey: string;
    function Call(const AModel: string; AInput: TJSONObject; AParams: TJSONObject = nil): TJSONObject;
    function KindModel(AKind: TAiQwenVoiceKind): string;
  protected
    // Transport: JSON body -> JSON response. Virtual for testing without network.
    function Post(const ABody: string): string; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    // Clones a voice from a sample (10-20 s of clean speech recommended).
    // APreferredName: letters, numbers and _ (incorporated into the id). Returns the id.
    function CloneVoice(AAudio: TAiMediaFile; const APreferredName: string;
      const ALanguage: string = ''): string; overload;
    function CloneVoice(const AAudioFile, APreferredName: string;
      const ALanguage: string = ''): string; overload;
    // Designs a voice from a description ('Adult male voice, calm...').
    // APreview receives the sample audio (WAV) if assigned. Returns the id.
    function DesignVoice(const ADescription, APreviewText, APreferredName: string;
      const ALanguage: string = ''; APreview: TAiMediaFile = nil): string;
    function ListVoices(AKind: TAiQwenVoiceKind; APageSize: Integer = 100): TArray<TAiQwenVoiceInfo>;
    procedure DeleteVoice(const AVoice: string);
    // Reason if the last designed voice fell into fallback mode (e.g. 'wer_too_high':
    // the description could not be followed well); empty if it came out as requested
    property LastDesignFallback: string read FLastDesignFallback;
  published
    // '@VARIABLE' reads the key from that environment variable
    property ApiKey: string read FApiKey write FApiKey;
    property Url: string read FUrl write FUrl;
    // Target TTS model for cloned / designed voices
    property CloneModel: string read FCloneModel write FCloneModel;
    property DesignModel: string read FDesignModel write FDesignModel;
  end;

procedure Register;

implementation

const
  GlVoicesUrl = 'https://dashscope-intl.aliyuncs.com/api/v1/services/audio/tts/customization';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiQwenVoices]);
end;

{ TAiQwenVoices }

constructor TAiQwenVoices.Create(AOwner: TComponent);
begin
  inherited;
  FApiKey := '@DASHSCOPE_API_KEY';
  FUrl := GlVoicesUrl;
  FCloneModel := 'qwen3-tts-vc-2026-01-22';
  FDesignModel := 'qwen3-tts-vd-2026-01-26';
end;

function TAiQwenVoices.GetApiKey: string;
begin
  if FApiKey.StartsWith('@') then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, MaxInt))
  else
    Result := FApiKey;
end;

function TAiQwenVoices.KindModel(AKind: TAiQwenVoiceKind): string;
begin
  if AKind = qvkClone then
    Result := 'qwen-voice-enrollment'
  else
    Result := 'qwen-voice-design';
end;

function TAiQwenVoices.Post(const ABody: string): string;
var
  Client: TNetHTTPClient;
  Body: TStringStream;
  Res: IHTTPResponse;
begin
  Client := TNetHTTPClient.Create(nil);
  Body := TStringStream.Create(ABody, TEncoding.UTF8);
  try
{$IF CompilerVersion >= 34}
    Client.SynchronizeEvents := False;
{$ENDIF}
    Client.ResponseTimeout := 120000;
    Client.ContentType := 'application/json';
    Res := Client.Post(FUrl, Body, nil, [TNetHeader.Create('Authorization', 'Bearer ' + GetApiKey)]);
    Result := Res.ContentAsString(TEncoding.UTF8);
    if Res.StatusCode <> 200 then
      raise Exception.CreateFmt('Qwen voices %d: %s', [Res.StatusCode, Result]);
  finally
    Body.Free;
    Client.Free;
  end;
end;

function TAiQwenVoices.Call(const AModel: string; AInput: TJSONObject; AParams: TJSONObject): TJSONObject;
var
  jBody: TJSONObject;
  V: TJSONValue;
begin
  jBody := TJSONObject.Create;
  try
    jBody.AddPair('model', AModel);
    jBody.AddPair('input', AInput);
    if Assigned(AParams) then
      jBody.AddPair('parameters', AParams);
    V := TJSONObject.ParseJSONValue(Post(jBody.ToJSON));
  finally
    jBody.Free;
  end;
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise Exception.Create('Qwen voices: response is not a JSON object');
  end;
  Result := TJSONObject(V);
end;

function TAiQwenVoices.CloneVoice(AAudio: TAiMediaFile; const APreferredName, ALanguage: string): string;
var
  jInput, jAudio, jRes: TJSONObject;
  LMime: string;
begin
  if not Assigned(AAudio) or (AAudio.Content.Size = 0) then
    raise Exception.Create('Qwen voices: an audio sample with content is required.');
  LMime := AAudio.MimeType;
  if (LMime = '') or SameText(LMime, 'audio/x-wav') then
    LMime := 'audio/wav';
  jInput := TJSONObject.Create;
  jInput.AddPair('action', 'create');
  jInput.AddPair('target_model', FCloneModel);
  jInput.AddPair('preferred_name', APreferredName);
  jAudio := TJSONObject.Create;
  jAudio.AddPair('data', 'data:' + LMime + ';base64,' + AAudio.Base64);
  jInput.AddPair('audio', jAudio);
  if ALanguage <> '' then
    jInput.AddPair('language', ALanguage);
  jRes := Call(KindModel(qvkClone), jInput);
  try
    Result := jRes.GetValue<string>('output.voice', '');
    if Result = '' then
      raise Exception.Create('Qwen voices: response does not contain voice id: ' + Copy(jRes.ToJSON, 1, 300));
  finally
    jRes.Free;
  end;
end;

function TAiQwenVoices.CloneVoice(const AAudioFile, APreferredName, ALanguage: string): string;
var
  MF: TAiMediaFile;
begin
  MF := TAiMediaFile.Create;
  try
    MF.LoadFromfile(AAudioFile);
    Result := CloneVoice(MF, APreferredName, ALanguage);
  finally
    MF.Free;
  end;
end;

function TAiQwenVoices.DesignVoice(const ADescription, APreviewText, APreferredName, ALanguage: string;
  APreview: TAiMediaFile): string;
var
  jInput, jParams, jRes: TJSONObject;
  LB64: string;
begin
  if Trim(ADescription) = '' then
    raise Exception.Create('Qwen voices: a voice description is required.');
  FLastDesignFallback := '';
  jInput := TJSONObject.Create;
  jInput.AddPair('action', 'create');
  jInput.AddPair('target_model', FDesignModel);
  jInput.AddPair('voice_prompt', ADescription);
  jInput.AddPair('preview_text', APreviewText);
  jInput.AddPair('preferred_name', APreferredName);
  if ALanguage <> '' then
    jInput.AddPair('language', ALanguage);
  jParams := TJSONObject.Create;
  jParams.AddPair('response_format', 'wav');
  jRes := Call(KindModel(qvkDesign), jInput, jParams);
  try
    Result := jRes.GetValue<string>('output.voice', '');
    if Result = '' then
      raise Exception.Create('Qwen voices: response does not contain voice id: ' + Copy(jRes.ToJSON, 1, 300));
    if jRes.GetValue<Boolean>('output.fallback_mode', False) then
      FLastDesignFallback := jRes.GetValue<string>('output.fallback_reason', 'fallback');
    if Assigned(APreview) then
    begin
      LB64 := jRes.GetValue<string>('output.preview_audio.data', '');
      if LB64 <> '' then
        APreview.LoadFromBase64('qwen_voice_preview.wav', LB64);
    end;
  finally
    jRes.Free;
  end;
end;

function TAiQwenVoices.ListVoices(AKind: TAiQwenVoiceKind; APageSize: Integer): TArray<TAiQwenVoiceInfo>;
var
  jInput, jRes: TJSONObject;
  jList: TJSONArray;
  V: TJSONValue;
  LInfo: TAiQwenVoiceInfo;
begin
  SetLength(Result, 0);
  jInput := TJSONObject.Create;
  jInput.AddPair('action', 'list');
  jInput.AddPair('page_size', TJSONNumber.Create(APageSize));
  jInput.AddPair('page_index', TJSONNumber.Create(0));
  jRes := Call(KindModel(AKind), jInput);
  try
    if jRes.TryGetValue<TJSONArray>('output.voice_list', jList) then
      for V in jList do
        if V is TJSONObject then
        begin
          LInfo.Voice := TJSONObject(V).GetValue<string>('voice', '');
          LInfo.TargetModel := TJSONObject(V).GetValue<string>('target_model', '');
          LInfo.Language := TJSONObject(V).GetValue<string>('language', '');
          LInfo.Created := TJSONObject(V).GetValue<string>('gmt_create', '');
          LInfo.Kind := AKind;
          Result := Result + [LInfo];
        end;
  finally
    jRes.Free;
  end;
end;

procedure TAiQwenVoices.DeleteVoice(const AVoice: string);
var
  jInput: TJSONObject;
  LKind: TAiQwenVoiceKind;
begin
  // The id prefix tells which service created it
  if AVoice.StartsWith('qwen-tts-vd-') then
    LKind := qvkDesign
  else
    LKind := qvkClone;
  jInput := TJSONObject.Create;
  jInput.AddPair('action', 'delete');
  jInput.AddPair('voice', AVoice);
  Call(KindModel(LKind), jInput).Free;
end;

end.
