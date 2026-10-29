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
//
unit uMCP.ClientEditorProperties;

interface

uses
  System.SysUtils, DesignIntf, DesignEditors, System.UITypes,
  uMakerAi.Tools.Functions, // For TMCPClientItem
  uMCPClientEditor; // For TFMCPClientEditor, assuming it is in this unit

type
  TMCPClientItemEditor = class(TClassProperty) // We use TClassProperty because we edit an object
  public
    procedure Edit; override;
    function GetAttributes: TPropertyAttributes; override;
  end;

procedure Register;

implementation

uses
  System.Classes, Vcl.Dialogs, uMakerAi.Core,
  uMakerAi.MCPClient.Core; // Necessary for Get/SetProperties

procedure Register;
begin
  // We register the editor for the "Configuration" property of the TMCPClientItem class
  RegisterPropertyEditor(TypeInfo(string), // The type of the property (string)
    TMCPClientItem, // The class that contains the property
    'Configuration', // The name of the property
    TMCPClientItemEditor // Our editor class
    );
end;

{ TMCPClientItemEditor }

procedure TMCPClientItemEditor.Edit;
var
  ClientItem: TMCPClientItem;
  EditorForm: TFMCPClientEditor;
  Props, VarEnv: TStringList;
begin
  // GetComponent(0) returns the instance of TMCPClientItem being edited.
  ClientItem := GetComponent(0) as TMCPClientItem;

  // We create the editor form
  EditorForm := TFMCPClientEditor.Create(Nil);
  try
    // 1. Load the current state of ClientItem into the form
    EditorForm.EditName.Text := ClientItem.Name;
    EditorForm.EditProtocol.ItemIndex := Ord(ClientItem.TransportType);

    Props := TStringList.Create;
    VarEnv := TStringList.Create;
    try
      // You can also add the TStrings of Params and DisabledFunctions if you want
      Props.AddStrings(ClientItem.Params);
      VarEnv.AddStrings(ClientItem.EnvVars);

      EditorForm.SetProperties(Props, VarEnv);
    finally
      Props.Free;
      VarEnv.Free;
    end;

    // 2. Show the form modally
    if EditorForm.ShowModal = mrOk then
    begin
      // 3. If the user presses OK, update the original ClientItem
      ClientItem.Name := EditorForm.EditName.Text;
      ClientItem.TransportType := TToolTransportType(EditorForm.EditProtocol.ItemIndex);

      Props := TStringList.Create;
      VarEnv := TStringList.Create;
      try
        EditorForm.GetProperties(Props, VarEnv);
        ClientItem.Params.Assign(Props);
        ClientItem.EnvVars.Assign(VarEnv);
        Modified;
      finally
        Props.Free;
        VarEnv.Free;
      end;
    end;
  finally
    EditorForm.Free;
  end;
end;

function TMCPClientItemEditor.GetAttributes: TPropertyAttributes;
begin
  // paDialog: Shows the [...] button
  // paReadOnly: Makes the value not editable directly in the grid.
  Result := [paDialog, paReadOnly];
end;

end.
