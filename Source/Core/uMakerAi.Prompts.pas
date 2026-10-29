unit uMakerAi.Prompts;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.HttpClient, System.NetEncoding, System.RegularExpressions,
  uMakerAi.Skills.Format;

const
  PPM_DEFAULT_REGISTRY = AI_PPM_DEFAULT_REGISTRY;

type
  TAiPromptItem = Class(TCollectionItem)
  Private
    fNombre          : String;
    FString          : TStrings;
    fDescripcion     : String;
    FSkillModel      : String;
    FSkillAllowedTools: String;
    FSkillDescription: String;
    function GetString: TStrings;
  Protected
    Procedure SetStrings(aValue: TStrings);
    function GetDisplayName: string; Override;
  Public
    constructor Create(Collection: TCollection); Override;
    destructor Destroy; Override;
  Published
    Property Nombre     : String  read fNombre      Write fNombre;
    Property Descripcion: String  read fDescripcion Write fDescripcion;
    Property Strings    : TStrings Read GetString   Write SetStrings;
    // Skill metadata (empty if the item is a prompt, not a skill)
    // Model recommended by the skill (frontmatter YAML: model: claude-opus-4-6)
    Property SkillModel      : String read FSkillModel       write FSkillModel;
    // Allowed tools, comma-separated (frontmatter: allowed-tools)
    Property SkillAllowedTools: String read FSkillAllowedTools write FSkillAllowedTools;
    // When to use the skill (frontmatter: description). Description, on the other hand,
    // tells where the item was loaded from.
    Property SkillDescription: String read FSkillDescription write FSkillDescription;
  End;

  TAiPrompts = class(TComponent)
  private
    FItems         : TCollection;
    FPPMRegistryUrl: String;
    function PPMHttpGet(const AUrl: String): String;
    function ConvertPPMTemplate(const AText: String): String;
    function ResolvePPMVersion(const AName, AVersion: String): String;
    // Creates or updates the item AName with the content of a parsed skill
    function StoreSkill(const AName, ADescripcion: String; ADoc: TAiSkillDoc): TAiPromptItem;
  protected
  public
    Constructor Create(aOwner: TComponent); Override;
    Destructor Destroy; Override;
    Function IndexOf(Nombre: String): Integer;
    Function GetNombre(Index: Integer): String;
    Function GetString(Nombre: String): String;
    Function GetStringByIndex(Index: Integer): String;
    Function AddString(Nombre, Data: String): TAiPromptItem;
    Function GetTemplate(Nombre: String; Params: Array of String): String; Overload;
    Function GetTemplate(Nombre: String; Params: TStringList): String; Overload;
    Function GetTemplate(Nombre: String; Params: TJSonObject): String; Overload;

    // Integration with PPM (public registry of prompts and skills)
    // SearchPPM: searches the registry. The caller is responsible for freeing the TJSONObject.
    // AType can be 'prompt', 'skill', 'pai', etc.
    function SearchPPM(const AQuery: String; const AType: String = 'prompt';
      APage: Integer = 1; APerPage: Integer = 20): TJSONObject;

    // LoadFromPPM: downloads a prompt (/raw) and adds it to Items.
    // Converts placeholders {{var}} → <#var>. If it already exists, updates it.
    // AVersion empty = resolves the latest available version.
    function LoadFromPPM(const AName: String; const AVersion: String = ''): TAiPromptItem;

    // LoadSkillFromPPM: downloads a skill (/skill), parses the YAML frontmatter
    // and stores the Markdown body in Strings.Text (without frontmatter).
    // SkillModel and SkillAllowedTools are available in the resulting item.
    // AVersion empty = resolves the latest available version.
    function LoadSkillFromPPM(const AName: String; const AVersion: String = ''): TAiPromptItem;

    // Local skills (SKILL.md format, same as PPM and Agent Skills).
    // LoadSkillFromFile: APath is the .md file or the folder containing
    //   SKILL.md. The item is named after the 'name' in frontmatter (or the
    //   folder). Unlike PPM methods, raises EAiSkillError if the file does not
    //   exist: it is a configuration error, not a network error.
    // LoadSkillsFromFolder: loads <AFolder>/SKILL.md and <AFolder>/<sub>/SKILL.md
    //   (the usual form of a skills directory). Returns how many were loaded.
    function LoadSkillFromFile(const APath: String): TAiPromptItem;
    function LoadSkillsFromFolder(const AFolder: String): Integer;

    // Copies the instructions of the item ANombre to a SystemPrompt:
    //   Prompts.ApplySkill('revisor', AiConnection.SystemPrompt);
    // AAppend=False replaces content; True appends it at the end (separated
    // by a blank line). Works for TAiChat, TAiChatConnection or
    // any TStrings. Returns False if the item does not exist.
    function ApplySkill(const ANombre: String; ASystemPrompt: TStrings;
      AAppend: Boolean = False): Boolean;

  published
    Property Items: TCollection Read FItems Write FItems;
    // URL of the PPM registry. Default: https://registry.cimamaker.com
    property PPMRegistryUrl: String read FPPMRegistryUrl write FPPMRegistryUrl;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiPrompts]);
end;

constructor TAiPromptItem.Create(Collection: TCollection);
Begin
  Inherited Create(Collection);
  FString := TStringList.Create;
End;

Procedure TAiPromptItem.SetStrings(aValue: TStrings);
Begin
  FString.Assign(aValue);
End;

function TAiPromptItem.GetDisplayName: string;
Begin
  Result := fNombre;
End;

function TAiPromptItem.GetString: TStrings;
begin
  Result := FString;
end;

// *************************************************************
// *************************************************************

Constructor TAiPrompts.Create(aOwner: TComponent);
Begin
  Inherited Create(aOwner);
  FItems := TCollection.Create(TAiPromptItem);
  FPPMRegistryUrl := PPM_DEFAULT_REGISTRY;
End;

Function TAiPrompts.IndexOf(Nombre: String): Integer;
Var
  I: Integer;
  Item: TAiPromptItem;
Begin
  Result := -1;
  For I := 0 to FItems.Count - 1 do
  Begin
    Item := TAiPromptItem(FItems.Items[I]);
    If (Item <> Nil) and (AnsiUpperCase(Nombre) = AnsiUpperCase(Item.Nombre)) then
    Begin
      Result := I;
      Break;
    End;
  End;
End;

Function TAiPrompts.GetString(Nombre: String): String;
Var
  I: Integer;
  Item: TAiPromptItem;
Begin
  Result := '';
  I := IndexOf(Nombre);
  If I >= 0 then
  Begin
    Item := TAiPromptItem(FItems.Items[I]);
    Result := Item.Strings.Text;
  End;
End;

function TAiPrompts.GetTemplate(Nombre: String; Params: TStringList): String;
Var
  I: Integer;
  Res, Nom, Val: String;
begin
  Res := GetString(Nombre);

  For I := 0 to Params.Count - 1 do
  Begin
    Nom := Params.Names[I];
    Val := Params.Values[Nom];
    Res := StringReplace(Res,'<#'+Nom+'>',Val,[rfReplaceAll,rfIgnoreCase]);
  End;

  Result := Res;
end;

function TAiPrompts.GetTemplate(Nombre: String; Params: array of String): String;
Var
  I, P: Integer;
  Res, S, Nom, Val: String;
begin
  Res := GetString(Nombre);
  For I := 0 to Length(Params) - 1 do
  Begin
    S := Params[I];
    P := Pos('=',S);
    If  p <= 0 then
      Raise Exception.Create('Parameters must have the form Name=Value');

    Nom := Copy(S, 1, P - 1);
    Val := Copy(S, P + 1, Length(S));
    Res := StringReplace(Res,'<#'+Nom+'>',Val,[rfReplaceAll,rfIgnoreCase]);
  End;

  Result := Res;
end;

function TAiPrompts.GetTemplate(Nombre: String; Params: TJSonObject): String;
Var
  Pair : TJSonPair;
  Res, Nom, Val: String;
begin
  Res := GetString(Nombre);
  For Pair in Params do
  Begin
    Nom := Pair.JsonString.Value;
    Val := Pair.JsonValue.Value;
    Res := StringReplace(Res,'<#'+Nom+'>',Val,[rfReplaceAll,rfIgnoreCase]);
  End;

  Result := Res;
end;

Function TAiPrompts.AddString(Nombre, Data: String): TAiPromptItem;
Var
  Item: TAiPromptItem;
Begin
  Item := TAiPromptItem(FItems.Add);
  Item.Nombre := Nombre;
  Item.Strings.Text := Data;
  Result := Item;
End;

destructor TAiPromptItem.Destroy;
Begin
  FString.Free;
  Inherited;
End;

Destructor TAiPrompts.Destroy;
Begin
  FItems.Free;
  Inherited;
End;

Function TAiPrompts.GetNombre(Index: Integer): String;
Begin
  Result := '';
  If (Index >= 0) and (Index < FItems.Count) then
    Result := TAiPromptItem(FItems.Items[Index]).Nombre;
End;

Function TAiPrompts.GetStringByIndex(Index: Integer): String;
Begin
  Result := '';
  If (Index >= 0) and (Index < FItems.Count) then
    Result := TAiPromptItem(FItems.Items[Index]).Strings.Text;
End;

// ---------------------------------------------------------------------------
// PPM Integration
// ---------------------------------------------------------------------------

function TAiPrompts.PPMHttpGet(const AUrl: String): String;
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
begin
  Result := '';
  LClient := THTTPClient.Create;
  try
    try
      LResponse := LClient.Get(AUrl);
      if LResponse.StatusCode = 200 then
        Result := LResponse.ContentAsString(TEncoding.UTF8);
    except
      // Network error: returns empty
    end;
  finally
    LClient.Free;
  end;
end;

function TAiPrompts.ConvertPPMTemplate(const AText: String): String;
begin
  // Converts PPM placeholders {{varname}} → MakerAI format <#varname>
  Result := TRegEx.Replace(AText, '\{\{(\w+)\}\}', '<#$1>');
end;

function TAiPrompts.ResolvePPMVersion(const AName, AVersion: String): String;
begin
  Result := AVersion;
  if Result <> '' then
    Exit;
  // Highest non-retracted version by semver (formerly: the first in the list).
  // Network errors are silenced: TAiPrompts API returns nil/'' on failure.
  try
    Result := TAiPPMClient.ResolveVersion(FPPMRegistryUrl, AName);
  except
    Result := '';
  end;
end;

function TAiPrompts.SearchPPM(const AQuery: String; const AType: String;
  APage, APerPage: Integer): TJSONObject;
var
  LUrl, LBody: String;
begin
  Result := nil;
  LUrl := Format('%s/v1/search?q=%s&type=%s&page=%d&per_page=%d',
    [FPPMRegistryUrl,
     TNetEncoding.URL.Encode(AQuery),
     AType,
     APage,
     APerPage]);
  LBody := PPMHttpGet(LUrl);
  if LBody <> '' then
    Result := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
end;

function TAiPrompts.LoadFromPPM(const AName: String; const AVersion: String): TAiPromptItem;
var
  LVersion, LUrl, LBody: String;
  LIdx: Integer;
begin
  Result := nil;
  LVersion := ResolvePPMVersion(AName, AVersion);
  if LVersion = '' then
    Exit;

  LUrl := Format('%s/v1/packages/%s/%s/raw', [FPPMRegistryUrl, AName, LVersion]);
  LBody := PPMHttpGet(LUrl);
  if LBody = '' then
    Exit;

  // Reuse existing item if one with the same name already exists
  LIdx := IndexOf(AName);
  if LIdx >= 0 then
    Result := TAiPromptItem(FItems.Items[LIdx])
  else
  begin
    Result := TAiPromptItem(FItems.Add);
    Result.Nombre := AName;
  end;
  Result.Descripcion := 'PPM: ' + AName + ' v' + LVersion;
  Result.Strings.Text := ConvertPPMTemplate(LBody);
end;

// ---------------------------------------------------------------------------
// LoadSkillFromPPM — the SKILL.md format is understood by uMakerAi.Skills.Format
// (single parser for the framework)
// ---------------------------------------------------------------------------
function TAiPrompts.LoadSkillFromPPM(const AName: String;
  const AVersion: String): TAiPromptItem;
var
  Doc : TAiSkillDoc;
begin
  Result := nil;
  Doc := TAiSkillDoc.Create;
  try
    // Historical contract of TAiPrompts: nil on any failure, no exception
    try
      Doc.LoadFromPPM(AName, AVersion, FPPMRegistryUrl);
    except
      Exit;
    end;

    Result := StoreSkill(AName, 'PPM skill: ' + AName + ' v' + Doc.Version, Doc);
  finally
    Doc.Free;
  end;
end;

function TAiPrompts.StoreSkill(const AName, ADescripcion: String;
  ADoc: TAiSkillDoc): TAiPromptItem;
var
  LIdx: Integer;
begin
  // Reuse existing item or create a new one
  LIdx := IndexOf(AName);
  if LIdx >= 0 then
    Result := TAiPromptItem(FItems.Items[LIdx])
  else
  begin
    Result := TAiPromptItem(FItems.Add);
    Result.Nombre := AName;
  end;
  Result.Descripcion       := ADescripcion;
  Result.Strings.Text      := ADoc.Body;
  Result.SkillModel        := ADoc.Model;
  Result.SkillAllowedTools := String.Join(',', ADoc.AllowedTools.ToStringArray);
  Result.SkillDescription  := ADoc.Description;
end;

// ---------------------------------------------------------------------------
// Local Skills
// ---------------------------------------------------------------------------
function TAiPrompts.LoadSkillFromFile(const APath: String): TAiPromptItem;
var
  Doc: TAiSkillDoc;
begin
  Doc := TAiSkillDoc.FromFile(APath);
  try
    Result := StoreSkill(Doc.Name, 'Skill: ' + Doc.SourcePath, Doc);
  finally
    Doc.Free;
  end;
end;

function TAiPrompts.LoadSkillsFromFolder(const AFolder: String): Integer;
var
  LFile: String;
begin
  Result := 0;
  for LFile in TAiSkillDoc.FindSkillFiles(AFolder) do
  begin
    LoadSkillFromFile(LFile);
    Inc(Result);
  end;
end;

function TAiPrompts.ApplySkill(const ANombre: String; ASystemPrompt: TStrings;
  AAppend: Boolean): Boolean;
var
  LIdx: Integer;
  LText: String;
begin
  Result := False;
  if not Assigned(ASystemPrompt) then
    Exit;
  LIdx := IndexOf(ANombre);
  if LIdx < 0 then
    Exit;

  LText := TAiPromptItem(FItems.Items[LIdx]).Strings.Text.Trim;
  if AAppend and (ASystemPrompt.Text.Trim <> '') then
    ASystemPrompt.Text := ASystemPrompt.Text.TrimRight + sLineBreak + sLineBreak + LText
  else
    ASystemPrompt.Text := LText;
  Result := True;
end;

end.
