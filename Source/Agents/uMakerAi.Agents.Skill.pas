unit uMakerAi.Agents.Skill;

// MIT License
//
// Copyright (c) 2026 Gustavo Enriquez - CimaMaker
//
// TAiSkill — reusable configuration for an LLM agent.
//
// Encapsulates: DriverName, Model, ApiKey, SystemPrompt and a list of
// additional tools (ExtraTools) identified by name in the
// TAiToolRegistry. Accepts two formats:
//
//   1) SKILL.md — the format of the Agent Skills and of the PPM registry
//      (YAML frontmatter + Markdown instructions). It is understood by
//      uMakerAi.Skills.Format; the body becomes SystemPrompt, 'model' becomes
//      Model and 'allowed-tools' becomes ExtraTools. As a MakerAI extension the
//      'driver' key is also accepted in the frontmatter.
//
//        Node.Skill := TAiSkill.FromPPM('skill-code-review');
//        Node.Skill := TAiSkill.FromFolder('skills\reviewer');   // SKILL.md
//
//   2) Own JSON (developer's local files):
//      {
//        "name":         "code-reviewer",
//        "description":  "Reviews code for bugs and improvements",
//        "driverName":   "Claude",
//        "model":        "claude-sonnet-4-6",
//        "apiKey":       "@CLAUDE_API_KEY",
//        "systemPrompt": "You are an expert reviewer...",
//        "extraTools":   ["filesystem", "git"]
//      }
//
// Security: 'apiKey' is ONLY read from the JSON, which is a file of the
// developer's own. A SKILL.md (from disk or from the registry) is third-party
// content and never provides credentials: without this, a downloaded skill could
// ask for '@ANY_VARIABLE' and the node would send that secret to the provider.
//
// Author: Gustavo Enriquez
// GitHub: https://github.com/gustavoeenriquez/MakerAi

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uMakerAi.Skills.Format;

type
  // Format the skill was loaded from
  TAiSkillFormat = (sfNone, sfJSON, sfSkillMd);

{ TAiSkill -----------------------------------------------------------------
  Reusable configuration container for LLM nodes and chat connections.

  Merge rules when applied to a TLLMNode (see TLLMNode.ResolveConfig):
    - DriverName / Model / ApiKey: the node's explicit value wins; if the
      node leaves it empty the skill's value is used. The skill's Model is
      only used if it belongs to the effective driver.
    - SystemPrompt: they are CONCATENATED — first the skill's (the base
      instructions) and then the node's (adjustments for that node).
    - ExtraTools is ALWAYS additive: it adds to the already-loaded tools.

  Memory management:
    - When assigned to TLLMNode.Skill, the node takes ownership and frees
      the skill in its destructor.
    - For standalone use, the caller is responsible for freeing the instance.
}
  TAiSkill = class
  private
    FName        : String;
    FDescription : String;
    FDriverName  : String;
    FModel       : String;
    FApiKey      : String;
    FSystemPrompt: String;
    FExtraTools  : TStringList;
    FFormat      : TAiSkillFormat;
    FSource      : TAiSkillSource;
    FSourcePath  : String;
    FVersion     : String;

    procedure ParseJSON(AJson: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;

    // Clears all fields back to the initial empty state
    procedure Clear;

    // Loads from a JSON string (own format)
    procedure LoadFromJSON(const AJsonStr: String);

  // Loads from disk. A folder or a .md file is read as SKILL.md;
  // any other file, as JSON (backward compatibility).
    procedure LoadFromFile(const APath: String);

  // Loads an already-parsed SKILL.md (or its text)
    procedure LoadFromSkillDoc(ADoc: TAiSkillDoc);
    procedure LoadFromSkillText(const AText: String);

  // Downloads the SKILL.md from the PPM registry.
  // AName: package name ('skill-code-review'; also accepts
  //   'code-review' and tries the 'skill-' prefix).
  // ARegistryUrl: registry URL; empty = https://registry.cimamaker.com.
  // AVersion: empty = the latest non-yanked version.
    procedure LoadFromPPM(const AName: String; const ARegistryUrl: String = '';
                          const AVersion: String = '');

  // Factories — create, load and return an instance ready to use.
  // The caller takes ownership of the returned object.
    class function FromJSON(const AJsonStr: String): TAiSkill;
    class function FromFile(const APath: String): TAiSkill;
  // Explicit SKILL.md (file) or the folder containing it
    class function FromSkillFile(const APath: String): TAiSkill;
    class function FromFolder(const AFolder: String): TAiSkill;
    class function FromPPM(const AName: String; const ARegistryUrl: String = '';
                           const AVersion: String = ''): TAiSkill;

  // Identifier name of the skill (matches the name in PPM)
    property Name: String read FName write FName;
  // Human-readable description of the skill
    property Description: String read FDescription write FDescription;
  // Suggested LLM driver ('OpenAI', 'Claude', 'Gemini', etc.)
    property DriverName: String read FDriverName write FDriverName;
  // Suggested model (empty = driver default)
    property Model: String read FModel write FModel;
  // API key; supports @ENV_VAR syntax for runtime resolution.
  // Only loaded from JSON (never from a SKILL.md).
    property ApiKey: String read FApiKey write FApiKey;
  // Skill's system prompt — the main reusable contribution
    property SystemPrompt: String read FSystemPrompt write FSystemPrompt;
  // Names of TAiToolRegistry tools to activate for this skill.
  // Names that do not exist in the registry are ignored when loading the tools
  // (e.g. 'Read'/'Bash' from a skill written for Claude Code).
    property ExtraTools: TStringList read FExtraTools;
  // Format and origin of the last load
    property Format: TAiSkillFormat read FFormat;
    property Source: TAiSkillSource read FSource;
    property SourcePath: String read FSourcePath;
  // Version of the PPM package (empty if not from the registry)
    property Version: String read FVersion;
  end;

implementation

{ TAiSkill }

constructor TAiSkill.Create;
begin
  inherited Create;
  FExtraTools            := TStringList.Create;
  FExtraTools.Duplicates := dupIgnore;
  FExtraTools.CaseSensitive := False;
end;

destructor TAiSkill.Destroy;
begin
  FExtraTools.Free;
  inherited;
end;

procedure TAiSkill.Clear;
begin
  FName         := '';
  FDescription  := '';
  FDriverName   := '';
  FModel        := '';
  FApiKey       := '';
  FSystemPrompt := '';
  FExtraTools.Clear;
  FFormat       := sfNone;
  FSource       := ssText;
  FSourcePath   := '';
  FVersion      := '';
end;

procedure TAiSkill.ParseJSON(AJson: TJSONObject);
var
  JArr: TJSONArray;
  I   : Integer;
begin
  if not Assigned(AJson) then Exit;

  FName         := AJson.GetValue<String>('name',         '');
  FDescription  := AJson.GetValue<String>('description',  '');
  FDriverName   := AJson.GetValue<String>('driverName',   '');
  FModel        := AJson.GetValue<String>('model',        '');
  FApiKey       := AJson.GetValue<String>('apiKey',       '');
  FSystemPrompt := AJson.GetValue<String>('systemPrompt', '');

  FExtraTools.Clear;
  if AJson.TryGetValue<TJSONArray>('extraTools', JArr) then
    for I := 0 to JArr.Count - 1 do
      FExtraTools.Add(JArr.Items[I].Value);
end;

procedure TAiSkill.LoadFromJSON(const AJsonStr: String);
var
  JVal: TJSONValue;
begin
  JVal := TJSONObject.ParseJSONValue(AJsonStr);
  if not (JVal is TJSONObject) then
  begin
    JVal.Free;
    raise EAiSkillError.CreateFmt('TAiSkill: invalid JSON — not an object: %s',
                                  [Copy(AJsonStr, 1, 80)]);
  end;
  try
    Clear;
    ParseJSON(TJSONObject(JVal));
    FFormat := sfJSON;
  finally
    JVal.Free;
  end;
end;

procedure TAiSkill.LoadFromSkillDoc(ADoc: TAiSkillDoc);
begin
  Clear;
  if not Assigned(ADoc) then Exit;

  FName         := ADoc.Name;
  FDescription  := ADoc.Description;
  FModel        := ADoc.Model;
  FSystemPrompt := ADoc.Body;
  FExtraTools.Assign(ADoc.AllowedTools);
  // MakerAI extension: the SKILL.md can set the driver
  FDriverName   := ADoc.Extra.Values['driver'];
  if FDriverName = '' then
    FDriverName := ADoc.Extra.Values['drivername'];
  // ApiKey: never from a SKILL.md (see the security note above)
  FFormat       := sfSkillMd;
  FSource       := ADoc.Source;
  FSourcePath   := ADoc.SourcePath;
  FVersion      := ADoc.Version;
end;

procedure TAiSkill.LoadFromSkillText(const AText: String);
var
  Doc: TAiSkillDoc;
begin
  Doc := TAiSkillDoc.Parse(AText);
  try
    LoadFromSkillDoc(Doc);
  finally
    Doc.Free;
  end;
end;

procedure TAiSkill.LoadFromFile(const APath: String);
var
  Doc: TAiSkillDoc;
begin
  if TDirectory.Exists(APath) or SameText(TPath.GetExtension(APath), '.md') then
  begin
    Doc := TAiSkillDoc.FromFile(APath);
    try
      LoadFromSkillDoc(Doc);
    finally
      Doc.Free;
    end;
    Exit;
  end;

  if not TFile.Exists(APath) then
    raise EAiSkillError.CreateFmt('TAiSkill: file not found: %s', [APath]);
  LoadFromJSON(TFile.ReadAllText(APath, TEncoding.UTF8));
  FSource := ssFile;
  FSourcePath := APath;
end;

procedure TAiSkill.LoadFromPPM(const AName: String; const ARegistryUrl: String;
  const AVersion: String);
var
  Doc: TAiSkillDoc;
begin
  Doc := TAiSkillDoc.FromPPM(AName, AVersion, ARegistryUrl);
  try
    LoadFromSkillDoc(Doc);
  finally
    Doc.Free;
  end;
end;

// --- Factories --------------------------------------------------------------

class function TAiSkill.FromJSON(const AJsonStr: String): TAiSkill;
begin
  Result := TAiSkill.Create;
  try
    Result.LoadFromJSON(AJsonStr);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkill.FromFile(const APath: String): TAiSkill;
begin
  Result := TAiSkill.Create;
  try
    Result.LoadFromFile(APath);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkill.FromSkillFile(const APath: String): TAiSkill;
var
  Doc: TAiSkillDoc;
begin
  Result := TAiSkill.Create;
  try
    Doc := TAiSkillDoc.FromFile(APath);
    try
      Result.LoadFromSkillDoc(Doc);
    finally
      Doc.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkill.FromFolder(const AFolder: String): TAiSkill;
begin
  Result := FromSkillFile(AFolder);
end;

class function TAiSkill.FromPPM(const AName: String; const ARegistryUrl: String;
  const AVersion: String): TAiSkill;
begin
  Result := TAiSkill.Create;
  try
    Result.LoadFromPPM(AName, ARegistryUrl, AVersion);
  except
    Result.Free;
    raise;
  end;
end;

end.
