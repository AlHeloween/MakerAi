unit uAiEditors.ChatConnectionEditor;

interface

uses
  System.Classes, System.SysUtils, DesignIntf, DesignEditors, uMakerAi.Chat.AiConnection;

type
  // Property Editor for the property DriverName
  TAiChatDriverNamePropertyEditor = class(TStringProperty)
  public
    procedure GetValues(Proc: TGetStrProc); override;
    function GetAttributes: TPropertyAttributes; override;
  end;

  // Component Editor for TAiChatConnection (optional, for future functions)
  TAiChatConnectionComponentEditor = class(TDefaultEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

procedure Register;

implementation

uses
  Vcl.Dialogs;

{ TAiChatDriverNamePropertyEditor }

function TAiChatDriverNamePropertyEditor.GetAttributes: TPropertyAttributes;
begin
  // paValueList: Shows dropdown list
  // paSortList: Sorts the list alphabetically
  // paMultiSelect: Allows multiple selection (optional)
  Result := [paValueList, paSortList];
end;

procedure TAiChatDriverNamePropertyEditor.GetValues(Proc: TGetStrProc);
var
  Connection: TAiChatConnection;
  Drivers: TArray<string>;
  Driver: string;
begin
  // Get the component instance
  Connection := GetComponent(0) as TAiChatConnection;
  if not Assigned(Connection) then
    Exit;

  try
    // Add empty option
    Proc('');

    // Get available drivers
    Drivers := Connection.GetAvailableDrivers;

    // Add each driver to the list
    for Driver in Drivers do
      Proc(Driver);
  except
    // If error, at least show empty option
    Proc('');
  end;
end;

{ TAiChatConnectionComponentEditor }

function TAiChatConnectionComponentEditor.GetVerbCount: Integer;
begin
  Result := 1; // One action in the context menu
end;

function TAiChatConnectionComponentEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := 'Reset Parameters to Defaults';
  else
    Result := '';
  end;
end;

procedure TAiChatConnectionComponentEditor.ExecuteVerb(Index: Integer);
var
  Connection: TAiChatConnection;
begin
  Connection := Component as TAiChatConnection;
  if not Assigned(Connection) then
    Exit;

  case Index of
    0: begin
         try
           Connection.ResetParamsToDefaults;
           ShowMessage('Parameters reset to defaults for driver: ' + Connection.DriverName);
           Designer.Modified; // Marks the form as modified
         except
           on E: Exception do
             ShowMessage('Error resetting parameters: ' + E.Message);
         end;
       end;
  end;
end;

procedure Register;
begin

  // Register the Property Editor for the DriverName property
  RegisterPropertyEditor(
    TypeInfo(string),              // Type of the property
    TAiChatConnection,             // Class of the component
    'DriverName',                  // Name of the property
    TAiChatDriverNamePropertyEditor // Class of the Property Editor
  );

  // Register the Component Editor (optional)
  RegisterComponentEditor(
    TAiChatConnection,                    // Class of the component
    TAiChatConnectionComponentEditor      // Class of the Component Editor
  );
end;

end.
