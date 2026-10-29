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

unit uMakerAi.VersionPropertyEditor;

interface

uses
  System.SysUtils, System.Classes, DesignIntf, DesignEditors, VCL.Dialogs,
  uMakerAi.Chat.AiConnection;

type
  // Custom Property Editor for the Version property
  TVersionPropertyEditor = class(TStringProperty)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
    //function GetValue: string; override;
    //procedure SetValue(const Value: string); override;
  end;

procedure Register;

implementation

uses
  uMakerAi.Dsg.AboutDialog;

{ TVersionPropertyEditor }

procedure Register;
begin
  // Register the Property Editor for the Version property
  // of the TAiChatConnection class
  RegisterPropertyEditor(TypeInfo(string), // Property type (string)
    TAiChatConnection, // Class that contains the property
    'Version', // Property name
    TVersionPropertyEditor // Property Editor class
    );

End;

function TVersionPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  // paDialog allows showing the three-dot button
  // paReadOnly makes the property not directly editable
  Result := [paDialog, paReadOnly];
end;

procedure TVersionPropertyEditor.Edit;
var
  AboutForm: TAboutDialog;
begin
  // Create and show the About dialog
  AboutForm := TAboutDialog.Create(nil);
  try
    AboutForm.ShowModal;
  finally
    AboutForm.Free;
  end;
end;

{
function TVersionPropertyEditor.GetValue: string;
begin
  // Display the current version in the Object Inspector
   //\$I uMakerAi.Version.inc
  //Result := MAKERAI_VERSION_FULL;
end;

procedure TVersionPropertyEditor.SetValue(const Value: string);
begin
  // Do not allow changing the value (read only)
  // Optionally you could show an explanatory message
end;
}

end.
