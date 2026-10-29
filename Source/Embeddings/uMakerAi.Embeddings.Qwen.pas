unit uMakerAi.Embeddings.Qwen;

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

// Qwen Embeddings (Alibaba Model Studio / DashScope). The compatible-mode/v1/embeddings
// endpoint accepts the same body as OpenAI, so TAiOpenAiEmbeddings is inherited and only
// URL, key, and model change. Verified at runtime (Sep 2026): text-embedding-v4 [default],
// text-embedding-v3, qwen3.7-text-embedding. v4 dimensions: 64, 128, 256, 512, 768, 1024
// (default), 1536 and 2048. The key is tied to the region: with another URL the API responds 401.

interface

uses
  System.SysUtils, System.Classes,
  uMakerAi.ParamsRegistry, uMakerAi.Embeddings, uMakerAi.Embeddings.Core, uMakerAi.Embeddings.OpenAi;

type
  TAiQwenEmbeddings = class(TAiOpenAiEmbeddings)
  public
    constructor Create(aOwner: TComponent); override;
    class function GetDriverName: string; override;
    class function CreateInstance(aOwner: TComponent): TAiEmbeddings; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
  end;

procedure Register;

implementation

const
  GlQwenUrl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/';
  GlQwenModel = 'text-embedding-v4';
  GlQwenDimensions = 1024;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiQwenEmbeddings]);
end;

{ TAiQwenEmbeddings }

constructor TAiQwenEmbeddings.Create(aOwner: TComponent);
begin
  inherited;
  ApiKey := '@DASHSCOPE_API_KEY';
  Url := GlQwenUrl;
  Model := GlQwenModel;
  Dimensions := GlQwenDimensions;
end;

class function TAiQwenEmbeddings.GetDriverName: string;
begin
  Result := 'Qwen';
end;

class function TAiQwenEmbeddings.CreateInstance(aOwner: TComponent): TAiEmbeddings;
begin
  Result := TAiQwenEmbeddings.Create(aOwner);
end;

class procedure TAiQwenEmbeddings.RegisterDefaultParams(Params: TStrings);
begin
  Params.Values['ApiKey'] := '@DASHSCOPE_API_KEY';
  Params.Values['Url'] := GlQwenUrl;
  Params.Values['Model'] := GlQwenModel;
  Params.Values['Dimensions'] := IntToStr(GlQwenDimensions);
end;

initialization
  TAiEmbeddingFactory.Instance.RegisterDriver(TAiQwenEmbeddings);

end.
