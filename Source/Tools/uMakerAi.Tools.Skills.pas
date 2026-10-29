unit uMakerAi.Tools.Skills;

// MIT License
//
// Copyright (c) 2026 Gustavo Enríquez - CimaMaker
//
// TAiSkills — on-demand skills for any chat (Agent Skills style).
//
// The model does NOT receive instructions for all skills in the system
// prompt. It only receives a catalog (name + when to use it) inside the
// description of a function, and loads the full instructions when it
// needs them by calling that function:
//
//   use_skill(name)              -> instructions of the skill
//   read_skill_file(name, path)  -> a file that accompanies the skill
//                                   (only folder skills, confined to it)
//
// Thus dozens of skills can be available without paying their tokens in
// every turn. It works with any driver with function calling, because they
// are normal TAiFunctions (and go through TAiGuardrails if any).
//
// Usage:
//   Skills.Functions := AiFunctions1;          // registers use_skill
//   Skills.LoadFromFolder('Skills');           // <dir>/<name>/SKILL.md
//   Skills.LoadFromPPM('skill-code-review');   // registry PPM
//   Skills.AddSkill('tone', 'Use it when writing emails', 'Write formally...');
//   AiConnection.AiFunctions := AiFunctions1;
//
// Security: a skill is text that the model will obey. A third-party skill
// (PPM, shared folder) is a vector for prompt injection: load only from
// trusted sources. The response of use_skill marks the origin, and
// OnBeforeUseSkill allows veto. read_skill_file never executes anything, it
// rejects paths that leave the skill folder (.., absolute, symlinks) and
// binary files or files larger than MaxFileSize.

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.StrUtils,
  uMakerAi.Skills.Format, uMakerAi.Tools.Functions, uMakerAi.Chat.Messages;

const
  AI_SKILLS_USE_FUNCTION  = 'use_skill';
  AI_SKILLS_READ_FUNCTION = 'read_skill_file';

type
  TAiSkills = class;

  TAiSkillItem = class(TCollectionItem)
  private
    FName        : string;
    FDescription : string;
    FInstructions: TStrings;
    FEnabled     : Boolean;
    FFolder      : string;
    FSource      : TAiSkillSource;
    FSourcePath  : string;
    FVersion     : string;
    FModel       : string;
    procedure SetName(const Value: string);
    procedure SetDescription(const Value: string);
    procedure SetInstructions(const Value: TStrings);
    procedure SetEnabled(const Value: Boolean);
    procedure InstructionsChanged(Sender: TObject);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure LoadFromSkillDoc(ADoc: TAiSkillDoc);

    // Skill folder (only if loaded from disk): root of read_skill_file
    property Folder: string read FFolder write FFolder;
    property Source: TAiSkillSource read FSource write FSource;
    property SourcePath: string read FSourcePath;
    property Version: string read FVersion;
    // 'model' from frontmatter (informative: TAiSkills does not change the model)
    property Model: string read FModel;
  published
    property Name: string read FName write SetName;
    // When to use the skill. It is what the model sees in the catalog: write it
    // thinking of the model ("Use it when the user asks...").
    property Description: string read FDescription write SetDescription;
    property Instructions: TStrings read FInstructions write SetInstructions;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
  end;

  TAiSkillItems = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TAiSkillItem;
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    function Add: TAiSkillItem;
    property Items[Index: Integer]: TAiSkillItem read GetItem; default;
  end;

  TAiSkillEvent = procedure(Sender: TObject; ASkill: TAiSkillItem) of object;
  TAiSkillAllowEvent = procedure(Sender: TObject; ASkill: TAiSkillItem;
    var Allow: Boolean) of object;
  TAiSkillFileEvent = procedure(Sender: TObject; ASkill: TAiSkillItem;
    const APath: string; var Allow: Boolean) of object;

  TAiSkills = class(TComponent)
  private
    FSkills          : TAiSkillItems;
    FFunctions       : TAiFunctions;
    FUseItem         : TFunctionActionItem;
    FReadItem        : TFunctionActionItem;
    FFolder          : string;
    FUseFunctionName : string;
    FReadFunctionName: string;
    FAllowFileAccess : Boolean;
    FMaxFileSize     : Integer;
    FUpdating        : Integer;
    FOnSkillLoaded   : TAiSkillEvent;
    FOnBeforeUseSkill: TAiSkillAllowEvent;
    FOnBeforeReadFile: TAiSkillFileEvent;
    procedure SetFunctions(const Value: TAiFunctions);
    procedure SetSkills(const Value: TAiSkillItems);
    procedure SetFolder(const Value: string);
    procedure SetUseFunctionName(const Value: string);
    procedure SetReadFunctionName(const Value: string);
    procedure SetAllowFileAccess(const Value: Boolean);
    procedure UnregisterTools;
    function HasFolderSkills: Boolean;
    function BuildUseDescription: string;
    function BuildUseSchema: string;
    function ListSkillFiles(ASkill: TAiSkillItem): TArray<string>;
    procedure DoUseSkillAction(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure DoReadFileAction(Sender: TObject; FunctionAction: TFunctionActionItem;
      FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Loading skills. A skill with the same name as an existing one replaces it.
    // All return the item (or the count) and throw EAiSkillError on failure.
    function AddSkill(const AName, ADescription, AInstructions: string): TAiSkillItem;
    function LoadFromFile(const APath: string): TAiSkillItem;      // SKILL.md or its folder
    function LoadFromFolder(const AFolder: string): Integer;        // <dir>/<name>/SKILL.md
    function LoadFromPPM(const AName: string; const ARegistryUrl: string = '';
                         const AVersion: string = ''): TAiSkillItem;
    function Find(const AName: string): TAiSkillItem;

    // Groups changes: the function schema is regenerated only once.
    procedure BeginUpdate;
    procedure EndUpdate;

    // Regenerates the functions in Functions (catalog and name enum).
    // Called automatically when loading, adding, or changing skills.
    procedure RegisterTools;

    // What the functions return, without going through the LLM (tests, UIs that
    // want to display the skill, or direct use).
    function ExecuteUseSkill(const AName: string): string;
    function ExecuteReadFile(const AName, APath: string): string;

    // Catalog as seen by the model
    function Catalog: string;
  published
    property Skills: TAiSkillItems read FSkills write SetSkills;
    // TAiFunctions where use_skill / read_skill_file are registered
    property Functions: TAiFunctions read FFunctions write SetFunctions;
    // Skill folder loaded at startup (runtime only)
    property Folder: string read FFolder write SetFolder;
    property UseFunctionName: string read FUseFunctionName write SetUseFunctionName;
    property ReadFunctionName: string read FReadFunctionName write SetReadFunctionName;
    // Register read_skill_file (only applies if there are folder skills)
    property AllowFileAccess: Boolean read FAllowFileAccess write SetAllowFileAccess default True;
    // Maximum size of a file read with read_skill_file (bytes)
    property MaxFileSize: Integer read FMaxFileSize write FMaxFileSize default 262144;
    // The model loaded a skill (audit, UI)
    property OnSkillLoaded: TAiSkillEvent read FOnSkillLoaded write FOnSkillLoaded;
    // Veto before delivering a skill
    property OnBeforeUseSkill: TAiSkillAllowEvent read FOnBeforeUseSkill write FOnBeforeUseSkill;
    // Veto before delivering a file (APath already resolved and validated)
    property OnBeforeReadFile: TAiSkillFileEvent read FOnBeforeReadFile write FOnBeforeReadFile;
  end;

procedure Register;

implementation

uses
  uMakerAi.Telemetry;

const
  MAX_LISTED_FILES = 50;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiSkills]);
end;

function SourceLabel(ASource: TAiSkillSource): string;
begin
  case ASource of
    ssFile: Result := 'file';
    ssPPM:  Result := 'ppm';
  else
    Result := 'inline';
  end;
end;

// Path prefix with file system case sensitivity
function PathStartsWith(const APath, APrefix: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := StartsText(APrefix, APath);
{$ELSE}
  Result := StartsStr(APrefix, APath);
{$ENDIF}
end;

// TFileAttribute members differ between Windows and POSIX: faSymLink exists in
// both and faReparsePoint only on Windows (hence the IFDEF)
{$WARN SYMBOL_PLATFORM OFF}
function IsLinkOrReparse(const APath: string): Boolean;
var
  Attrs: TFileAttributes;
begin
  Result := False;
  try
    Attrs := TFile.GetAttributes(APath, False);
  except
    Exit;
  end;
  Result := TFileAttribute.faSymLink in Attrs;
{$IFDEF MSWINDOWS}
  Result := Result or (TFileAttribute.faReparsePoint in Attrs);
{$ENDIF}
end;
{$WARN SYMBOL_PLATFORM DEFAULT}

{ TAiSkillItem }

constructor TAiSkillItem.Create(Collection: TCollection);
begin
  FInstructions := TStringList.Create;
  TStringList(FInstructions).OnChange := InstructionsChanged;
  FEnabled := True;
  FSource := ssText;
  inherited Create(Collection);
end;

destructor TAiSkillItem.Destroy;
begin
  FInstructions.Free;
  inherited;
end;

procedure TAiSkillItem.Assign(Source: TPersistent);
var
  S: TAiSkillItem;
begin
  if Source is TAiSkillItem then
  begin
    S := TAiSkillItem(Source);
    FName := S.FName;
    FDescription := S.FDescription;
    FInstructions.Assign(S.FInstructions);
    FEnabled := S.FEnabled;
    FFolder := S.FFolder;
    FSource := S.FSource;
    FSourcePath := S.FSourcePath;
    FVersion := S.FVersion;
    FModel := S.FModel;
    Changed(False);
  end
  else
    inherited;
end;

procedure TAiSkillItem.LoadFromSkillDoc(ADoc: TAiSkillDoc);
begin
  FName := ADoc.Name;
  FDescription := ADoc.Description;
  FModel := ADoc.Model;
  FSource := ADoc.Source;
  FSourcePath := ADoc.SourcePath;
  FVersion := ADoc.Version;
  if ADoc.Source = ssFile then
    FFolder := TPath.GetDirectoryName(ADoc.SourcePath)
  else
    FFolder := '';
  FInstructions.Text := ADoc.Body; // triggers Changed
end;

function TAiSkillItem.GetDisplayName: string;
begin
  Result := FName;
  if Result = '' then
    Result := inherited GetDisplayName;
end;

procedure TAiSkillItem.InstructionsChanged(Sender: TObject);
begin
  Changed(False);
end;

procedure TAiSkillItem.SetDescription(const Value: string);
begin
  if FDescription <> Value then
  begin
    FDescription := Value;
    Changed(False);
  end;
end;

procedure TAiSkillItem.SetEnabled(const Value: Boolean);
begin
  if FEnabled <> Value then
  begin
    FEnabled := Value;
    Changed(False);
  end;
end;

procedure TAiSkillItem.SetInstructions(const Value: TStrings);
begin
  FInstructions.Assign(Value);
end;

procedure TAiSkillItem.SetName(const Value: string);
begin
  if FName <> Value then
  begin
    FName := Trim(Value);
    Changed(False);
  end;
end;

{ TAiSkillItems }

function TAiSkillItems.Add: TAiSkillItem;
begin
  Result := TAiSkillItem(inherited Add);
end;

function TAiSkillItems.GetItem(Index: Integer): TAiSkillItem;
begin
  Result := TAiSkillItem(inherited Items[Index]);
end;

procedure TAiSkillItems.Update(Item: TCollectionItem);
begin
  inherited;
  if GetOwner is TAiSkills then
    TAiSkills(GetOwner).RegisterTools;
end;

{ TAiSkills }

constructor TAiSkills.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSkills := TAiSkillItems.Create(Self, TAiSkillItem);
  FUseFunctionName := AI_SKILLS_USE_FUNCTION;
  FReadFunctionName := AI_SKILLS_READ_FUNCTION;
  FAllowFileAccess := True;
  FMaxFileSize := 262144;
end;

destructor TAiSkills.Destroy;
begin
  // Functions point to methods of this object: remove them before dying
  Inc(FUpdating);
  UnregisterTools;
  FSkills.Free;
  inherited;
end;

procedure TAiSkills.Loaded;
begin
  inherited;
  if (FFolder <> '') and not (csDesigning in ComponentState) and TDirectory.Exists(FFolder) then
    LoadFromFolder(FFolder)
  else
    RegisterTools;
end;

procedure TAiSkills.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FFunctions) then
  begin
    FFunctions := nil;
    // The items are destroyed by the Functions collection
    FUseItem := nil;
    FReadItem := nil;
  end;
end;

procedure TAiSkills.SetFunctions(const Value: TAiFunctions);
begin
  if FFunctions = Value then
    Exit;
  UnregisterTools;
  if Assigned(FFunctions) then
    FFunctions.RemoveFreeNotification(Self);
  FFunctions := Value;
  if Assigned(FFunctions) then
  begin
    FFunctions.FreeNotification(Self);
    RegisterTools;
  end;
end;

procedure TAiSkills.SetSkills(const Value: TAiSkillItems);
begin
  FSkills.Assign(Value);
end;

procedure TAiSkills.SetFolder(const Value: string);
begin
  if FFolder = Value then
    Exit;
  FFolder := Value;
  // At runtime, outside DFM loading, it is applied immediately
  if (FFolder <> '') and not (csLoading in ComponentState) and
     not (csDesigning in ComponentState) and TDirectory.Exists(FFolder) then
    LoadFromFolder(FFolder);
end;

procedure TAiSkills.SetUseFunctionName(const Value: string);
begin
  if (Value = '') or (Value = FUseFunctionName) then
    Exit;
  UnregisterTools;
  FUseFunctionName := Value;
  RegisterTools;
end;

procedure TAiSkills.SetReadFunctionName(const Value: string);
begin
  if (Value = '') or (Value = FReadFunctionName) then
    Exit;
  UnregisterTools;
  FReadFunctionName := Value;
  RegisterTools;
end;

procedure TAiSkills.SetAllowFileAccess(const Value: Boolean);
begin
  if FAllowFileAccess = Value then
    Exit;
  FAllowFileAccess := Value;
  RegisterTools;
end;

procedure TAiSkills.BeginUpdate;
begin
  Inc(FUpdating);
end;

procedure TAiSkills.EndUpdate;
begin
  if FUpdating > 0 then
    Dec(FUpdating);
  if FUpdating = 0 then
    RegisterTools;
end;

function TAiSkills.Find(const AName: string): TAiSkillItem;
var
  I: Integer;
begin
  for I := 0 to FSkills.Count - 1 do
    if SameText(FSkills[I].Name, Trim(AName)) then
      Exit(FSkills[I]);
  Result := nil;
end;

function TAiSkills.AddSkill(const AName, ADescription, AInstructions: string): TAiSkillItem;
begin
  if Trim(AName) = '' then
    raise EAiSkillError.Create('TAiSkills.AddSkill: the skill needs a name');
  BeginUpdate;
  try
    Result := Find(AName);
    if not Assigned(Result) then
      Result := FSkills.Add;
    Result.Name := AName;
    Result.Description := ADescription;
    Result.Instructions.Text := AInstructions;
  finally
    EndUpdate;
  end;
end;

function TAiSkills.LoadFromFile(const APath: string): TAiSkillItem;
var
  Doc: TAiSkillDoc;
begin
  Doc := TAiSkillDoc.FromFile(APath);
  try
    BeginUpdate;
    try
      Result := Find(Doc.Name);
      if not Assigned(Result) then
        Result := FSkills.Add;
      Result.LoadFromSkillDoc(Doc);
    finally
      EndUpdate;
    end;
  finally
    Doc.Free;
  end;
end;

function TAiSkills.LoadFromFolder(const AFolder: string): Integer;
var
  F: string;
begin
  Result := 0;
  BeginUpdate;
  try
    for F in TAiSkillDoc.FindSkillFiles(AFolder) do
    begin
      LoadFromFile(F);
      Inc(Result);
    end;
  finally
    EndUpdate;
  end;
end;

function TAiSkills.LoadFromPPM(const AName, ARegistryUrl, AVersion: string): TAiSkillItem;
var
  Doc: TAiSkillDoc;
begin
  Doc := TAiSkillDoc.FromPPM(AName, AVersion, ARegistryUrl);
  try
    BeginUpdate;
    try
      Result := Find(Doc.Name);
      if not Assigned(Result) then
        Result := FSkills.Add;
      Result.LoadFromSkillDoc(Doc);
    finally
      EndUpdate;
    end;
  finally
    Doc.Free;
  end;
end;

function TAiSkills.HasFolderSkills: Boolean;
var
  I: Integer;
begin
  for I := 0 to FSkills.Count - 1 do
    if FSkills[I].Enabled and (FSkills[I].Folder <> '') then
      Exit(True);
  Result := False;
end;

function TAiSkills.Catalog: string;
var
  SB: TStringBuilder;
  I: Integer;
  S: TAiSkillItem;
  Desc: string;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to FSkills.Count - 1 do
    begin
      S := FSkills[I];
      if not S.Enabled or (S.Name = '') then
        Continue;
      // One line per skill: the catalog travels in every turn
      Desc := S.Description.Replace(#13#10, ' ').Replace(#10, ' ').Trim;
      if Desc = '' then
        Desc := '(no description)';
      SB.Append('- ').Append(S.Name).Append(': ').Append(Desc).Append(#10);
    end;
    Result := SB.ToString.TrimRight;
  finally
    SB.Free;
  end;
end;

function TAiSkills.BuildUseDescription: string;
begin
  Result :=
    'Loads the full instructions of a skill. Before doing a task that matches ' +
    'one of these skills, call this function with its name and follow the ' +
    'instructions it returns. Available skills:' + #10 + Catalog;
end;

function TAiSkills.BuildUseSchema: string;
var
  Schema, Props, NameProp: TJSONObject;
  Enum, Req: TJSONArray;
  I: Integer;
begin
  Schema := TJSONObject.Create;
  try
    Schema.AddPair('type', 'object');
    Props := TJSONObject.Create;
    Schema.AddPair('properties', Props);
    NameProp := TJSONObject.Create;
    Props.AddPair('name', NameProp);
    NameProp.AddPair('type', 'string');
    NameProp.AddPair('description', 'Name of the skill to load');
    Enum := TJSONArray.Create;
    for I := 0 to FSkills.Count - 1 do
      if FSkills[I].Enabled and (FSkills[I].Name <> '') then
        Enum.Add(FSkills[I].Name);
    NameProp.AddPair('enum', Enum);
    Req := TJSONArray.Create;
    Req.Add('name');
    Schema.AddPair('required', Req);
    Result := Schema.ToJSON;
  finally
    Schema.Free;
  end;
end;

procedure TAiSkills.UnregisterTools;
var
  Idx: Integer;
begin
  if not Assigned(FFunctions) then
  begin
    FUseItem := nil;
    FReadItem := nil;
    Exit;
  end;
  if Assigned(FUseItem) then
  begin
    Idx := FFunctions.Functions.IndexOf(FUseItem.FunctionName);
    if (Idx >= 0) and (FFunctions.Functions[Idx] = FUseItem) then
      FUseItem.Free;
    FUseItem := nil;
  end;
  if Assigned(FReadItem) then
  begin
    Idx := FFunctions.Functions.IndexOf(FReadItem.FunctionName);
    if (Idx >= 0) and (FFunctions.Functions[Idx] = FReadItem) then
      FReadItem.Free;
    FReadItem := nil;
  end;
end;

procedure TAiSkills.RegisterTools;
var
  Any: Boolean;
  I: Integer;
  P: TFunctionParamsItem;
begin
  // They are not registered in the IDE: the functions would be saved in
  // TAiFunctions's DFM with an OnAction pointing to this component, not to the form.
  if (FUpdating > 0) or not Assigned(FFunctions) or (csLoading in ComponentState) or
     (csDestroying in ComponentState) or (csDesigning in ComponentState) then
    Exit;

  Any := False;
  for I := 0 to FSkills.Count - 1 do
    if FSkills[I].Enabled and (FSkills[I].Name <> '') then
      Any := True;

  // use_skill: reuse the item if it already exists (with the same name)
  if not Assigned(FUseItem) then
  begin
    FUseItem := FFunctions.Functions.GetFunction(FUseFunctionName);
    if not Assigned(FUseItem) then
      FUseItem := FFunctions.Functions.AddFunction(FUseFunctionName, True, DoUseSkillAction);
  end;
  FUseItem.OnAction := DoUseSkillAction;
  FUseItem.Description.Text := BuildUseDescription;
  FUseItem.RawSchemaJson := BuildUseSchema;
  // Without skills, the function is not offered (an empty enum is an invalid schema)
  FUseItem.Enabled := Any;

  if FAllowFileAccess and Any and HasFolderSkills then
  begin
    if not Assigned(FReadItem) then
    begin
      FReadItem := FFunctions.Functions.GetFunction(FReadFunctionName);
      if not Assigned(FReadItem) then
        FReadItem := FFunctions.Functions.AddFunction(FReadFunctionName, True, DoReadFileAction);
    end;
    FReadItem.OnAction := DoReadFileAction;
    FReadItem.Description.Text :=
      'Reads a supporting file of a skill loaded with ' + FUseFunctionName + ' ' +
      '(references, templates, examples). Use it only when the skill instructions ' +
      'point to that file. Path is relative to the skill folder.';
    if FReadItem.Parameters.Count = 0 then
    begin
      P := FReadItem.Parameters.Add;
      P.Name := 'name';
      P.Description.Text := 'Name of the skill';
      P.ParamType := ptString;
      P.Required := True;
      P := FReadItem.Parameters.Add;
      P.Name := 'path';
      P.Description.Text := 'Relative path of the file inside the skill folder';
      P.ParamType := ptString;
      P.Required := True;
    end;
    FReadItem.Enabled := True;
  end
  else if Assigned(FReadItem) then
    FReadItem.Enabled := False;
end;

function TAiSkills.ListSkillFiles(ASkill: TAiSkillItem): TArray<string>;
var
  List: TStringList;
  Root, F, Rel: string;
begin
  Result := nil;
  if (ASkill.Folder = '') or not TDirectory.Exists(ASkill.Folder) then
    Exit;
  Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(ASkill.Folder));
  List := TStringList.Create;
  try
    for F in TDirectory.GetFiles(Root, '*', TSearchOption.soAllDirectories) do
    begin
      Rel := Copy(F, Length(Root) + 1, MaxInt).Replace('\', '/');
      if SameText(Rel, AI_SKILL_FILE_NAME) then
        Continue;
      List.Add(Rel);
      if List.Count >= MAX_LISTED_FILES then
        Break;
    end;
    List.Sort;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function TAiSkills.ExecuteUseSkill(const AName: string): string;
var
  S: TAiSkillItem;
  Allow: Boolean;
  Files: TArray<string>;
  SB: TStringBuilder;
  Span: TAiSpan;
  Names: TStringList;
  I: Integer;
begin
  S := Find(AName);
  if not Assigned(S) or not S.Enabled then
  begin
    Names := TStringList.Create;
    try
      for I := 0 to FSkills.Count - 1 do
        if FSkills[I].Enabled then
          Names.Add(FSkills[I].Name);
      Exit(Format('Error: skill "%s" not found. Available skills: %s',
        [AName, String.Join(', ', Names.ToStringArray)]));
    finally
      Names.Free;
    end;
  end;

  Allow := True;
  if Assigned(FOnBeforeUseSkill) then
    FOnBeforeUseSkill(Self, S, Allow);
  if not Allow then
    Exit(Format('Error: skill "%s" is not allowed in this session.', [S.Name]));

  Span := AiSpanStart('skill.load ' + S.Name);
  try
    AiSpanAttr(Span, 'skill.name', S.Name);
    AiSpanAttr(Span, 'skill.source', SourceLabel(S.Source));

    SB := TStringBuilder.Create;
    try
      SB.Append('<skill name="').Append(S.Name).Append('" source="')
        .Append(SourceLabel(S.Source)).Append('"');
      if S.Version <> '' then
        SB.Append(' version="').Append(S.Version).Append('"');
      SB.Append('>').Append(#10);
      if S.Source = ssPPM then
        SB.Append('(Third-party skill from the PPM registry.)').Append(#10);
      SB.Append(S.Instructions.Text.Trim).Append(#10);
      Files := ListSkillFiles(S);
      if FAllowFileAccess and (Length(Files) > 0) then
        SB.Append(#10).Append('Supporting files (read them with ').Append(FReadFunctionName)
          .Append(' when the instructions refer to them): ')
          .Append(String.Join(', ', Files)).Append(#10);
      SB.Append('</skill>');
      Result := SB.ToString;
    finally
      SB.Free;
    end;
    AiSpanEnd(Span);
  except
    on E: Exception do
    begin
      AiSpanEnd(Span, E.Message);
      raise;
    end;
  end;

  if Assigned(FOnSkillLoaded) then
    FOnSkillLoaded(Self, S);
end;

function TAiSkills.ExecuteReadFile(const AName, APath: string): string;
var
  S: TAiSkillItem;
  Root, Full, Dir, Rel: string;
  Allow: Boolean;
  Bytes: TBytes;
  I: Integer;
begin
  if not FAllowFileAccess then
    Exit('Error: file access is disabled.');
  S := Find(AName);
  if not Assigned(S) or not S.Enabled then
    Exit(Format('Error: skill "%s" not found.', [AName]));
  if S.Folder = '' then
    Exit(Format('Error: skill "%s" has no folder with supporting files.', [S.Name]));

  Rel := Trim(APath).Replace('/', PathDelim).Replace('\', PathDelim);
  if (Rel = '') or TPath.IsPathRooted(Rel) or Rel.StartsWith(PathDelim) or
     (Pos(':', Rel) > 0) then
    Exit('Error: the path must be relative to the skill folder.');

  Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(S.Folder));
  Full := TPath.GetFullPath(TPath.Combine(Root, Rel));
  // GetFullPath resolves '..': if the result left the folder, reject
  if not PathStartsWith(Full, Root) or (Length(Full) <= Length(Root)) then
    Exit('Error: the path is outside the skill folder.');
  if not TFile.Exists(Full) then
    Exit(Format('Error: file "%s" not found in skill "%s".', [APath, S.Name]));

  // A symbolic link inside the folder could point anywhere:
  // check the file and every intermediate folder.
  Dir := Full;
  while (Length(Dir) > Length(Root)) do
  begin
    if IsLinkOrReparse(Dir) then
      Exit('Error: links are not allowed in skill folders.');
    Dir := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(Dir));
  end;

  if TFile.GetSize(Full) > FMaxFileSize then
    Exit(Format('Error: file is larger than %d bytes.', [FMaxFileSize]));

  Allow := True;
  if Assigned(FOnBeforeReadFile) then
    FOnBeforeReadFile(Self, S, Full, Allow);
  if not Allow then
    Exit('Error: reading this file is not allowed.');

  Bytes := TFile.ReadAllBytes(Full);
  for I := 0 to Length(Bytes) - 1 do
    if Bytes[I] = 0 then
      Exit('Error: binary files cannot be read.');
  Result := TEncoding.UTF8.GetString(Bytes);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

procedure TAiSkills.DoUseSkillAction(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  Handled := True;
  try
    ToolCall.Response := ExecuteUseSkill(ToolCall.Params.Values['name']);
  except
    on E: Exception do
      ToolCall.Response := 'Error: ' + E.Message;
  end;
end;

procedure TAiSkills.DoReadFileAction(Sender: TObject; FunctionAction: TFunctionActionItem;
  FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  Handled := True;
  try
    ToolCall.Response := ExecuteReadFile(ToolCall.Params.Values['name'],
      ToolCall.Params.Values['path']);
  except
    on E: Exception do
      ToolCall.Response := 'Error: ' + E.Message;
  end;
end;

end.
