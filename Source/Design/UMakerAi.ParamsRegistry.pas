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
// - YouTube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit UMakerAi.ParamsRegistry;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.Generics.Defaults, System.SyncObjs,
  UMakerAi.Chat, uMakerAi.Embeddings;

type
  TAiChatClass = class of TAiChat;


  TAiChatFactory = class
  private
  class var
    FInstance: TAiChatFactory;
    FRegisteredClasses: TDictionary<string, TAiChatClass>;
    // The key can now be "DriverName" or "DriverName@ModelName"
    FUserParams: TDictionary<string, TStringList>;

    FCustomModels: TDictionary<string, String>; // DriverName -> TStringList

    // Counter that increases on EACH mutation of the registry. Allows
    // consumers to cache the registry view and know, with an integer comparison,
    // if their copy is still valid. It is touched very rarely:
    // registrations happen at startup.
    FVersion: Integer;

    // Internal function to create the composite key.
    class function GetCompositeKey(const DriverName, ModelName: string): string; static;
    procedure BumpVersion;

  public
    // Current version of the registry (see FVersion).
    function Version: Integer;
    constructor Create;
    destructor Destroy; override;
    class function Instance: TAiChatFactory;

    // Existing methods (some with new signature)
    procedure RegisterDriver(AClass: TAiChatClass); overload;
    procedure RegisterDriver(AClass: TAiChatClass; const ADriverName: string); overload;
    // Now accepts an optional ModelName to get hierarchical parameters.
    procedure GetDriverParams(const DriverName, ModelName: string; Params: TStrings; ExpandVariables: Boolean = True);
    function CreateDriver(const DriverName: string): TAiChat;
    function GetRegisteredDrivers: TArray<string>;
    function HasDriver(const DriverName: string): Boolean;

    // Main version to register a parameter for a specific model.
    procedure RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string); Overload;
    // Overload to register a parameter at Driver level (compatibility and convenience).
    procedure RegisterUserParam(const DriverName, ParamName, ParamValue: string); Overload;

    // Clears the parameters (with overload for model).
    procedure ClearRegisterParams(const DriverName: String; ModelName: string = '');

    // --- New methods for handling custom models ---
    procedure RegisterCustomModel(const DriverName, CustomModelName, ModelBaseName: string);
    function GetBaseModel(const DriverName, CustomModel: string): string;
    function GetCustomModels(const DriverName: string): TArray<string>;
    function HasCustomModel(const DriverName, CustomModelName: string): Boolean;
    procedure ClearCustomModels(const DriverName: string);

  end;

  TAiEmbeddingsClass = class of TAiEmbeddings;

  TAiEmbeddingFactory = class
  private
  class var
    FInstance: TAiEmbeddingFactory;
    FRegisteredClasses: TDictionary<string, TAiEmbeddingsClass>;
    FUserParams: TDictionary<string, TStringList>;
    class function GetCompositeKey(const DriverName, ModelName: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TAiEmbeddingFactory;

    procedure RegisterDriver(AClass: TAiEmbeddingsClass); overload;
    procedure RegisterDriver(AClass: TAiEmbeddingsClass; const ADriverName: string); overload;
    function CreateDriver(const DriverName: string): TAiEmbeddings;
    procedure GetDriverParams(const DriverName, ModelName: string; Params: TStrings; ExpandVariables: Boolean = True);
    function GetRegisteredDrivers: TArray<string>;
    function HasDriver(const DriverName: string): Boolean;

    procedure RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string); overload;
    procedure RegisterUserParam(const DriverName, ParamName, ParamValue: string); overload;
    procedure ClearRegisterParams(const DriverName: String; ModelName: string = '');
  end;

implementation

{ TAiChatFactory }

// Internal function to create the composite key
class function TAiChatFactory.GetCompositeKey(const DriverName, ModelName: string): string;
begin
  if ModelName.IsEmpty then
    Result := DriverName
  else
    Result := DriverName + '@' + ModelName;
end;

procedure TAiChatFactory.BumpVersion;
begin
  TInterlocked.Increment(FVersion);
end;

function TAiChatFactory.Version: Integer;
begin
  Result := TInterlocked.CompareExchange(FVersion, 0, 0); // atomic read
end;

constructor TAiChatFactory.Create;
begin
  inherited;
  FRegisteredClasses := TDictionary<string, TAiChatClass>.Create(TIStringComparer.Ordinal);
  FUserParams := TDictionary<string, TStringList>.Create(TIStringComparer.Ordinal);
  FCustomModels := TDictionary<string, String>.Create(TIStringComparer.Ordinal);
end;

destructor TAiChatFactory.Destroy;
begin
  for var SL in FUserParams.Values do
    SL.Free;
  FUserParams.Free;
  FRegisteredClasses.Free;
  FCustomModels.Free;
  inherited;
end;

class function TAiChatFactory.Instance: TAiChatFactory;
begin
  if not Assigned(FInstance) then
    FInstance := TAiChatFactory.Create;
  Result := FInstance;
end;

procedure TAiChatFactory.RegisterDriver(AClass: TAiChatClass);
begin
  FRegisteredClasses.AddOrSetValue(AClass.GetDriverName, AClass);
  BumpVersion; // invalidates cached registry views
end;

procedure TAiChatFactory.RegisterDriver(AClass: TAiChatClass; const ADriverName: string);
begin
  if ADriverName <> '' then
    FRegisteredClasses.AddOrSetValue(ADriverName, AClass);
  BumpVersion; // invalidates cached registry views
end;

procedure TAiChatFactory.GetDriverParams(const DriverName, ModelName: string; Params: TStrings; ExpandVariables: Boolean);
var
  LModel: string;
  DriverClass: TAiChatClass;
  UserParamList: TStringList;
  I: Integer;
  EnvVarName, EnvVarValue, Key: String;
begin
  Params.Clear;

  // Level 1: Load default parameters from the driver class
  if FRegisteredClasses.TryGetValue(DriverName, DriverClass) then
    DriverClass.RegisterDefaultParams(Params);

  Params.Text := Trim(Params.Text); // Removes the last LineBreak

  // Level 2: Merge with custom driver-level parameters
  Key := GetCompositeKey(DriverName, '');
  if FUserParams.TryGetValue(Key, UserParamList) then
  begin
    For I := 0 to UserParamList.Count - 1 do
      Params.Values[UserParamList.Names[I]] := UserParamList.ValueFromIndex[I];
  end;

  // Level 3: Merge with custom model-level parameters
  // Without ModelName, it uses the model resolved by levels 1 and 2 (the driver's default
  // or catalog model). Previously level 3 was skipped and a connection without
  // Model used that model WITHOUT its parameters (e.g. Qwen without cap_Image, Groq without
  // reasoning nor Max_Tokens): empty Model and Model = default gave different chat.
  LModel := ModelName;
  if LModel.IsEmpty then
    LModel := Params.Values['Model'];
  if not LModel.IsEmpty then
  begin
    Key := GetCompositeKey(DriverName, LModel);
    if FUserParams.TryGetValue(Key, UserParamList) then
    begin
      For I := 0 to UserParamList.Count - 1 do
        Params.Values[UserParamList.Names[I]] := UserParamList.ValueFromIndex[I];
    end;
  end;

  If ExpandVariables = True then // Should expand variables with environment variables
  Begin
    // Expansion of Environment Variables
    for I := Params.Count - 1 downto 0 do
    begin

      Var
      Valor := Params[I];
      if (Trim(Params[I]) <> '') and (Params.ValueFromIndex[I] <> '') and (Params.ValueFromIndex[I].StartsWith('@')) then
      begin
        EnvVarName := Params.ValueFromIndex[I].Substring(1);
        EnvVarValue := Trim(GetEnvironmentVariable(EnvVarName));
        If EnvVarValue <> '' then
          Params.ValueFromIndex[I] := EnvVarValue;
      end;
    end;
  End;
end;

function TAiChatFactory.CreateDriver(const DriverName: string): TAiChat;
var
  DriverClass: TAiChatClass;
begin
  // Driver not registered: a diagnosable error that lists available drivers.
  // The lookup is case-insensitive; if the expected driver does not appear in the list,
  // the unit 'uMakerAi.Chat.Initializations' is likely missing from the uses clause (it registers all drivers).
  if not FRegisteredClasses.TryGetValue(DriverName, DriverClass) then
    raise Exception.CreateFmt(
      'Driver "%s" is not registered. Available drivers: [%s]. ' +
      'Suggestion: add the unit uMakerAi.Chat.Initializations to the uses clause to ' +
      'register all drivers.',
      [DriverName, String.Join(', ', GetRegisteredDrivers)]);

  Result := DriverClass.CreateInstance(Nil);
end;

function TAiChatFactory.GetRegisteredDrivers: TArray<string>;
begin
  Result := FRegisteredClasses.Keys.ToArray;
end;

function TAiChatFactory.HasDriver(const DriverName: string): Boolean;
begin
  Result := FRegisteredClasses.ContainsKey(DriverName);
end;

procedure TAiChatFactory.ClearRegisterParams(const DriverName: String; ModelName: string = '');
var
  UserParamList: TStringList;
  Key: string;
begin
  Key := GetCompositeKey(DriverName, ModelName);
  if FUserParams.TryGetValue(Key, UserParamList) then
  begin
    UserParamList.Clear;
  end;
  BumpVersion; // invalidates cached registry views
end;

// Main version to register a parameter for a specific model.
procedure TAiChatFactory.RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string);
var
  UserParamList: TStringList;
  Key: string;
begin
  Key := GetCompositeKey(DriverName, ModelName);
  if not FUserParams.TryGetValue(Key, UserParamList) then
  begin
    UserParamList := TStringList.Create;
    FUserParams.Add(Key, UserParamList);
  end;
  UserParamList.Values[ParamName] := ParamValue;
  BumpVersion; // invalidates cached registry views
end;

// Overload to register a parameter at Driver level.
procedure TAiChatFactory.RegisterUserParam(const DriverName, ParamName, ParamValue: string);
begin
  // Calls the main version with an empty ModelName.
  RegisterUserParam(DriverName, '', ParamName, ParamValue);
  BumpVersion; // invalidates cached registry views
end;


// Implementation of the new methods for custom models
// Implementation of the new methods for custom models
// Implementation of the new methods for custom models


procedure TAiChatFactory.RegisterCustomModel(const DriverName, CustomModelName, ModelBaseName: string);
var
  Key : String;
begin
  // Checks that ModelName is not empty
  if CustomModelName.IsEmpty then
    raise Exception.Create('CustomModelName cannot be empty when registering a custom model.');

  if ModelBaseName.IsEmpty then
    raise Exception.Create('ModelBaseName cannot be empty when registering a custom model.');

  Key := GetCompositeKey(DriverName, CustomModelName);

  FCustomModels.AddOrSetValue(Key, ModelBaseName);  // Adds or updates the associated model

  BumpVersion; // invalidates cached registry views
end;

function TAiChatFactory.GetBaseModel(const DriverName, CustomModel: string): string;
var
  CompositeKey: string;
begin
  // Creates the composite key
  CompositeKey := GetCompositeKey(DriverName, CustomModel);

  // Attempts to get the BaseModel for the CustomModel
  if not FCustomModels.TryGetValue(CompositeKey, Result) then
    Result := CustomModel; // Default value if not found
end;



function TAiChatFactory.GetCustomModels(const DriverName: string): TArray<string>;
var
  CustomModel: string;
  CompositeKey: string;
begin
  // Iterates through the dictionary and filters CustomModels for the given DriverName
  var List: TList<string> := TList<string>.Create;
  try
    for CompositeKey in FCustomModels.Keys do
    begin
      // Checks if the DriverName matches the beginning of the composite key
      if CompositeKey.StartsWith(DriverName + '@') then
      begin
        // Extracts the CustomModel from the composite key
        CustomModel := Copy(CompositeKey, Length(DriverName) + 2, Length(CompositeKey)); // +2 for the @
        List.Add(CustomModel);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TAiChatFactory.HasCustomModel(const DriverName, CustomModelName: string): Boolean;
var
  CompositeKey: string;
begin
  // Creates the composite key
  CompositeKey := GetCompositeKey(DriverName, CustomModelName);

  // Checks if the composite key exists in the dictionary
  Result := FCustomModels.ContainsKey(CompositeKey);
end;

procedure TAiChatFactory.ClearCustomModels(const DriverName: string);
var
  CompositeKey: string;
  KeysToRemove: TList<string>;
begin

  // Creates a list to store the keys to be removed
  KeysToRemove := TList<string>.Create;
  try
    // Iterates through the dictionary and looks for keys belonging to the given DriverName
    for CompositeKey in FCustomModels.Keys do
    begin
      // Checks if the DriverName matches the beginning of the composite key
      if CompositeKey.StartsWith(DriverName + '@') then
      begin
        // Adds the key to the list of keys to remove
        KeysToRemove.Add(CompositeKey);
      end;
    end;

    // Removes the found keys from the dictionary
    for CompositeKey in KeysToRemove do
    begin
      FCustomModels.Remove(CompositeKey);
    end;
  finally
    KeysToRemove.Free;
  end;
  BumpVersion; // invalidates cached registry views
end;


{ TAiEmbeddingFactory }

class function TAiEmbeddingFactory.GetCompositeKey(const DriverName, ModelName: string): string;
begin
  if ModelName.IsEmpty then
    Result := DriverName
  else
    Result := DriverName + '@' + ModelName;
end;

constructor TAiEmbeddingFactory.Create;
begin
  inherited;
  FRegisteredClasses := TDictionary<string, TAiEmbeddingsClass>.Create(TIStringComparer.Ordinal);
  FUserParams := TDictionary<string, TStringList>.Create(TIStringComparer.Ordinal);
end;

destructor TAiEmbeddingFactory.Destroy;
begin
  for var SL in FUserParams.Values do
    SL.Free;
  FUserParams.Free;
  FRegisteredClasses.Free;
  inherited;
end;

class function TAiEmbeddingFactory.Instance: TAiEmbeddingFactory;
begin
  if not Assigned(FInstance) then
    FInstance := TAiEmbeddingFactory.Create;
  Result := FInstance;
end;

procedure TAiEmbeddingFactory.RegisterDriver(AClass: TAiEmbeddingsClass);
begin
  FRegisteredClasses.AddOrSetValue(AClass.GetDriverName, AClass);
end;

procedure TAiEmbeddingFactory.RegisterDriver(AClass: TAiEmbeddingsClass; const ADriverName: string);
begin
  if ADriverName <> '' then
    FRegisteredClasses.AddOrSetValue(ADriverName, AClass);
end;

procedure TAiEmbeddingFactory.GetDriverParams(const DriverName, ModelName: string; Params: TStrings; ExpandVariables: Boolean);
var
  LModel: string;
  DriverClass: TAiEmbeddingsClass;
  UserParamList: TStringList;
  I: Integer;
  EnvVarName, EnvVarValue, Key: String;
begin
  Params.Clear;

  // Level 1: Default parameters from the driver class
  if FRegisteredClasses.TryGetValue(DriverName, DriverClass) then
    DriverClass.RegisterDefaultParams(Params);

  Params.Text := Trim(Params.Text);

  // Level 2: Custom driver-level parameters
  Key := GetCompositeKey(DriverName, '');
  if FUserParams.TryGetValue(Key, UserParamList) then
  begin
    for I := 0 to UserParamList.Count - 1 do
      Params.Values[UserParamList.Names[I]] := UserParamList.ValueFromIndex[I];
  end;

  // Level 3: Custom model-level parameters
  // Without ModelName, it uses the model resolved by levels 1 and 2 (the driver's default
  // or catalog model). Previously level 3 was skipped and a connection without
  // Model used that model WITHOUT its parameters (e.g. Qwen without cap_Image, Groq without
  // reasoning nor Max_Tokens): empty Model and Model = default gave different chat.
  LModel := ModelName;
  if LModel.IsEmpty then
    LModel := Params.Values['Model'];
  if not LModel.IsEmpty then
  begin
    Key := GetCompositeKey(DriverName, LModel);
    if FUserParams.TryGetValue(Key, UserParamList) then
    begin
      for I := 0 to UserParamList.Count - 1 do
        Params.Values[UserParamList.Names[I]] := UserParamList.ValueFromIndex[I];
    end;
  end;

  // Expansion of Environment Variables
  if ExpandVariables then
  begin
    for I := Params.Count - 1 downto 0 do
    begin
      if (Trim(Params[I]) <> '') and (Params.ValueFromIndex[I] <> '') and (Params.ValueFromIndex[I].StartsWith('@')) then
      begin
        EnvVarName := Params.ValueFromIndex[I].Substring(1);
        EnvVarValue := Trim(GetEnvironmentVariable(EnvVarName));
        if EnvVarValue <> '' then
          Params.ValueFromIndex[I] := EnvVarValue;
      end;
    end;
  end;
end;

function TAiEmbeddingFactory.CreateDriver(const DriverName: string): TAiEmbeddings;
var
  DriverClass: TAiEmbeddingsClass;
begin
  Result := nil;
  if FRegisteredClasses.TryGetValue(DriverName, DriverClass) then
    Result := DriverClass.CreateInstance(nil);
end;

function TAiEmbeddingFactory.GetRegisteredDrivers: TArray<string>;
begin
  Result := FRegisteredClasses.Keys.ToArray;
end;

function TAiEmbeddingFactory.HasDriver(const DriverName: string): Boolean;
begin
  Result := FRegisteredClasses.ContainsKey(DriverName);
end;

procedure TAiEmbeddingFactory.RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string);
var
  UserParamList: TStringList;
  Key: string;
begin
  Key := GetCompositeKey(DriverName, ModelName);
  if not FUserParams.TryGetValue(Key, UserParamList) then
  begin
    UserParamList := TStringList.Create;
    FUserParams.Add(Key, UserParamList);
  end;
  UserParamList.Values[ParamName] := ParamValue;
end;

procedure TAiEmbeddingFactory.RegisterUserParam(const DriverName, ParamName, ParamValue: string);
begin
  RegisterUserParam(DriverName, '', ParamName, ParamValue);
end;

procedure TAiEmbeddingFactory.ClearRegisterParams(const DriverName: String; ModelName: string);
var
  UserParamList: TStringList;
  Key: string;
begin
  Key := GetCompositeKey(DriverName, ModelName);
  if FUserParams.TryGetValue(Key, UserParamList) then
    UserParamList.Clear;
end;

initialization

// The instance is created on demand
finalization

if Assigned(TAiChatFactory.FInstance) then
begin
  TAiChatFactory.FInstance.Free;
  TAiChatFactory.FInstance := nil;
end;

if Assigned(TAiEmbeddingFactory.FInstance) then
begin
  TAiEmbeddingFactory.FInstance.Free;
  TAiEmbeddingFactory.FInstance := nil;
end;

end.
