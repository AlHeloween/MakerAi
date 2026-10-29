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

unit uMakerAi.Agents.Attributes;

interface

uses
  System.SysUtils, System.Rtti;

type

  TAgentCustomAttribute = Class // Base class for future tools

  End;

  // ---------------------------------------------------------------------------
  // 1. ATTRIBUTE FOR THE TOOL CLASS ([Tool])
  // Defines the general properties of the tool.
  // ---------------------------------------------------------------------------
  //[AttributeUsage(ClassServices, AllowMultiple = false, Inherited = true)]
  TToolAttribute = class(TCustomAttribute)
  private
    FName: string;
    FDescription: string;
    FCategory: string;
  public
    constructor Create(const AName, ADescription, ACategory: string);
    property Name: string read FName;
    property Description: string read FDescription;
    property Category: string read FCategory;
  end;

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // 2. ATTRIBUTE FOR TOOL PARAMETERS (PROPERTIES) ([ToolParameter])
  // Defines how a parameter is shown in the configuration dialog.
  // ---------------------------------------------------------------------------
  // Style note: Renamed to TToolParameterAttribute by Delphi convention.
  //[AttributeUsage(PropertyServices, AllowMultiple = false, Inherited = true)]
  TToolParameterAttribute = class(TCustomAttribute)
  private
    FDisplayName: string;
    FHint: string;
    FDefaultValue: string;
  public
    constructor Create(const ADisplayName, AHint: string; const ADefaultValue: string = '');
    property DisplayName: string read FDisplayName;
    property Hint: string read FHint;
    property DefaultValue: string read FDefaultValue;
  end;

  // ---------------------------------------------------------------------------
  // 3. ATTRIBUTE FOR SECRET PROPERTIES ([TSecret])
  // Marks a property as secret: it is never serialized to disk and any
  // incoming value for it is ignored when deserializing, so a tampered
  // file cannot inject credentials. The value is provided at runtime
  // (credential store or environment variable with @ENV_VAR syntax).
  // ---------------------------------------------------------------------------
  TSecretAttribute = class(TCustomAttribute)
  private
    FCredentialType: string; // 'apiKey' | 'basic' | 'bearer' | 'hmac' | 'custom'
  public
    constructor Create(const ACredentialType: string = 'apiKey');
    property CredentialType: string read FCredentialType;
  end;

implementation

{ TToolAttribute }

constructor TToolAttribute.Create(const AName, ADescription, ACategory: string);
begin
  inherited Create;
  FName := AName;
  FDescription := ADescription;
  FCategory := ACategory;
end;

{ TToolParameterAttribute }

constructor TToolParameterAttribute.Create(const ADisplayName, AHint: string; const ADefaultValue: string);
begin
  inherited Create;
  FDisplayName := ADisplayName;
  FHint := AHint;
  FDefaultValue := ADefaultValue;
end;

{ TSecretAttribute }

constructor TSecretAttribute.Create(const ACredentialType: string);
begin
  inherited Create;
  FCredentialType := ACredentialType;
end;

end.
