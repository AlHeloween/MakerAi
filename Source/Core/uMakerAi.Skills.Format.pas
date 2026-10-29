unit uMakerAi.Skills.Format;

// MIT License
//
// Copyright (c) 2026 Gustavo Enríquez - CimaMaker
//
// SKILL.md format: a skill is a Markdown file with a YAML frontmatter block
// at the beginning (between two '---' lines) and instructions in the body.
// It is the format of Claude's Agent Skills and the one published by the
// PPM registry (type 'skill').
//
//   ---
//   name: code-review
//   description: Reviews code for errors. Use it when...
//   allowed-tools:
//     - Read
//     - Grep
//   model: claude-opus-4-6
//   ---
//   You are an expert code reviewer...
//
// This unit is the ONLY one that understands the format. It is used by
// TAiPrompts (Core), TAiSkill/TLLMNode (Agents) and TAiSkills (Tools), so
// that the same skill works equally in a chat, in an agent node, or as a
// template, whether it comes from a local folder or the registry.
//
// From YAML we understand what real skills use: scalars (with or without
// quotes, with trailing '#' comment), lists '- x', inline lists '[a, b]'
// or 'a, b', and blocks '|' / '>'. It is not a full YAML parser.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Net.HttpClient, System.Net.URLClient;

const
  AI_SKILL_FILE_NAME       = 'SKILL.md';
  AI_PPM_DEFAULT_REGISTRY  = 'https://registry.cimamaker.com';
  AI_PPM_SKILL_PREFIX      = 'skill-';

type
  EAiSkillError = class(Exception);

  // Where the skill came from. Important for security: a PPM skill is
  // third-party content (credentials are not accepted from it, see TAiSkill).
  TAiSkillSource = (ssText, ssFile, ssPPM);

  TAiSkillDoc = class
  private
    FName           : string;
    FDescription    : string;
    FModel          : string;
    FBody           : string;
    FSourcePath     : string;
    FVersion        : string;
    FSource         : TAiSkillSource;
    FHasFrontmatter : Boolean;
    FAllowedTools   : TStringList;
    FExtra          : TStringList;
    procedure ParseFrontmatter(const ALines: TArray<string>; AEnd: Integer);
    procedure SetScalar(const AKey, AValue: string);
    procedure SetList(const AKey: string; AValues: TStrings);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Assign(ASource: TAiSkillDoc);

    // Parses the full text of a SKILL.md. Without frontmatter, all text is
    // the body (a loose Markdown is also a valid skill).
    procedure LoadFromText(const AText: string);

    // APath can be the .md file or a folder containing SKILL.md.
    // If the frontmatter does not have 'name', the folder name (or the file
    // name without extension) is used.
    procedure LoadFromFile(const APath: string);

    // Downloads the skill from the PPM registry. AVersion empty = the latest
    // unyanked version. If AName does not exist and does not start with
    // 'skill-', it retries with the prefix ('code-review' -> 'skill-code-review').
    procedure LoadFromPPM(const AName: string; const AVersion: string = '';
                          const ARegistryUrl: string = '');

    // Factories: the caller frees the returned object.
    class function Parse(const AText: string): TAiSkillDoc;
    class function FromFile(const APath: string): TAiSkillDoc;
    class function FromPPM(const AName: string; const AVersion: string = '';
                           const ARegistryUrl: string = ''): TAiSkillDoc;

    // Paths to SKILL.md files in a folder: the one in the folder itself (if
    // any) and the one in each direct subfolder. This is the usual layout of
    // a skills directory: skills/<name>/SKILL.md. Alphabetical order.
    class function FindSkillFiles(const AFolder: string): TArray<string>;

    // True if the text looks like an HTML page: a web server that responds
    // 200 with its page instead of a 404 should not be mistaken for a skill.
    class function LooksLikeHtml(const AText: string): Boolean;

    property Name          : string         read FName        write FName;
    property Description   : string         read FDescription write FDescription;
    property Model         : string         read FModel       write FModel;
    // Instructions (Markdown without the frontmatter)
    property Body          : string         read FBody        write FBody;
    // Tool names declared in 'allowed-tools'
    property AllowedTools  : TStringList    read FAllowedTools;
    // Remaining scalar keys from the frontmatter (Name=Value, keys in lowercase)
    property Extra         : TStringList    read FExtra;
    property Source        : TAiSkillSource read FSource      write FSource;
    // Local file or registry URL from which it was loaded
    property SourcePath    : string         read FSourcePath  write FSourcePath;
    // PPM package version (empty for local skills)
    property Version       : string         read FVersion     write FVersion;
    property HasFrontmatter: Boolean        read FHasFrontmatter;
  end;

  // Minimal read-only client for the PPM registry.
  TAiPPMClient = class
  public
    // GET to a registry URL. Returns the body with status 200 and raises
    // EAiSkillError in any other case, with the registry's 'message' if it
    // carries one. AStatus receives the HTTP code (0 if connection failed).
    class function Get(const AUrl: string; out AStatus: Integer): string;

    // Package metadata (/v1/packages/<name>). The caller frees.
    class function GetPackage(const ARegistryUrl, AName: string): TJSONObject;
    // Same, but returns nil if the package does not exist (404) instead of raising.
    class function TryGetPackage(const ARegistryUrl, AName: string): TJSONObject;

    // Latest unyanked (semver) version of the package; '' if none.
    class function ResolveVersion(const ARegistryUrl, AName: string): string;

    // Compares two semver versions 'x.y.z' (the -pre suffix is ignored).
    class function CompareVersions(const A, B: string): Integer;

    // Effective registry: ARegistryUrl without trailing '/', or the default.
    class function RegistryOrDefault(const ARegistryUrl: string): string;
  end;

implementation

uses
  System.StrUtils, System.NetEncoding;

const
  PPM_TIMEOUT_MS = 20000;

{ helpers }

// Removes enclosing quotes, or the trailing '#' comment if there are no quotes.
function CleanScalar(const AValue: string): string;
var
  V: string;
  P: Integer;
begin
  V := Trim(AValue);
  if (Length(V) >= 2) and
     (((V[1] = '"') and (V[Length(V)] = '"')) or
      ((V[1] = '''') and (V[Length(V)] = ''''))) then
    Exit(Copy(V, 2, Length(V) - 2));

  // In YAML a comment starts with ' #' (the '#' attached is part of the value)
  P := Pos(' #', V);
  if P > 0 then
    V := Trim(Copy(V, 1, P - 1));
  Result := V;
end;

function IndentOf(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and (ALine[Result + 1] = ' ') do
    Inc(Result);
end;

// 'a, b' or '[a, b]' -> list
procedure SplitInlineList(const AValue: string; AList: TStrings);
var
  V, Item: string;
begin
  V := Trim(AValue);
  if V.StartsWith('[') and V.EndsWith(']') then
    V := Copy(V, 2, Length(V) - 2);
  for Item in V.Split([',']) do
    if CleanScalar(Item) <> '' then
      AList.Add(CleanScalar(Item));
end;

{ TAiSkillDoc }

constructor TAiSkillDoc.Create;
begin
  inherited Create;
  FAllowedTools := TStringList.Create;
  FExtra := TStringList.Create;
end;

destructor TAiSkillDoc.Destroy;
begin
  FAllowedTools.Free;
  FExtra.Free;
  inherited;
end;

procedure TAiSkillDoc.Clear;
begin
  FName := '';
  FDescription := '';
  FModel := '';
  FBody := '';
  FSourcePath := '';
  FVersion := '';
  FSource := ssText;
  FHasFrontmatter := False;
  FAllowedTools.Clear;
  FExtra.Clear;
end;

procedure TAiSkillDoc.Assign(ASource: TAiSkillDoc);
begin
  if not Assigned(ASource) then
  begin
    Clear;
    Exit;
  end;
  FName := ASource.FName;
  FDescription := ASource.FDescription;
  FModel := ASource.FModel;
  FBody := ASource.FBody;
  FSourcePath := ASource.FSourcePath;
  FVersion := ASource.FVersion;
  FSource := ASource.FSource;
  FHasFrontmatter := ASource.FHasFrontmatter;
  FAllowedTools.Assign(ASource.FAllowedTools);
  FExtra.Assign(ASource.FExtra);
end;

procedure TAiSkillDoc.SetScalar(const AKey, AValue: string);
begin
  if AKey = 'name' then
    FName := AValue
  else if AKey = 'description' then
    FDescription := AValue
  else if AKey = 'model' then
    FModel := AValue
  else if (AKey = 'allowed-tools') or (AKey = 'allowed_tools') then
  begin
    FAllowedTools.Clear;
    SplitInlineList(AValue, FAllowedTools);
  end
  else
    FExtra.Values[AKey] := AValue;
end;

procedure TAiSkillDoc.SetList(const AKey: string; AValues: TStrings);
begin
  if (AKey = 'allowed-tools') or (AKey = 'allowed_tools') then
    FAllowedTools.Assign(AValues)
  else
    // The lists we don't know are stored as 'a, b' to avoid losing them
    FExtra.Values[AKey] := String.Join(', ', AValues.ToStringArray);
end;

procedure TAiSkillDoc.ParseFrontmatter(const ALines: TArray<string>; AEnd: Integer);
var
  I, J, ColonPos, BaseIndent: Integer;
  Line, Key, Value, Style: string;
  Items: TStringList;
  Block: TStringBuilder;
begin
  Items := TStringList.Create;
  try
    I := 1;
    while I < AEnd do
    begin
      Line := ALines[I];
      if (Trim(Line) = '') or Trim(Line).StartsWith('#') then
      begin
        Inc(I);
        Continue;
      end;

      ColonPos := Line.IndexOf(':');
      // Only top-level keys (no indentation); everything else is consumed
      // below as part of the previous key
      if (ColonPos <= 0) or (IndentOf(Line) > 0) then
      begin
        Inc(I);
        Continue;
      end;

      Key := Trim(Line.Substring(0, ColonPos)).ToLower;
      Value := Trim(Line.Substring(ColonPos + 1));

      if (Value = '|') or (Value = '>') or (Value = '|-') or (Value = '>-') then
      begin
        // Block: the indented lines that follow. '|' preserves line breaks,
        // '>' folds them into spaces.
        Style := Value;
        Block := TStringBuilder.Create;
        try
          J := I + 1;
          BaseIndent := -1;
          while (J < AEnd) and ((Trim(ALines[J]) = '') or (IndentOf(ALines[J]) > 0)) do
          begin
            if Trim(ALines[J]) <> '' then
            begin
              if BaseIndent < 0 then
                BaseIndent := IndentOf(ALines[J]);
              if Block.Length > 0 then
              begin
                if Style.StartsWith('|') then Block.Append(#10) else Block.Append(' ');
              end;
              Block.Append(Copy(ALines[J], BaseIndent + 1, MaxInt).TrimRight);
            end
            else if Style.StartsWith('|') and (Block.Length > 0) then
              Block.Append(#10);
            Inc(J);
          end;
          SetScalar(Key, Block.ToString.Trim);
        finally
          Block.Free;
        end;
        I := J;
        Continue;
      end;

      if Value = '' then
      begin
        // Possible list '- x' in the following lines
        Items.Clear;
        J := I + 1;
        while (J < AEnd) and ((Trim(ALines[J]) = '') or Trim(ALines[J]).StartsWith('- ')
               or (Trim(ALines[J]) = '-')) do
        begin
          if Trim(ALines[J]).StartsWith('- ') then
            Items.Add(CleanScalar(Trim(ALines[J]).Substring(2)));
          Inc(J);
        end;
        if Items.Count > 0 then
          SetList(Key, Items)
        else
          SetScalar(Key, '');
        I := J;
        Continue;
      end;

      // Plain scalar. In YAML it can continue on indented lines (long broken
      // descriptions): they are folded with spaces.
      J := I + 1;
      while (J < AEnd) and (Trim(ALines[J]) <> '') and (IndentOf(ALines[J]) > 0)
            and not Trim(ALines[J]).StartsWith('- ') do
      begin
        Value := Value + ' ' + Trim(ALines[J]);
        Inc(J);
      end;
      SetScalar(Key, CleanScalar(Value));
      I := J;
    end;
  finally
    Items.Free;
  end;
end;

procedure TAiSkillDoc.LoadFromText(const AText: string);
var
  Text: string;
  Lines: TArray<string>;
  I, FmEnd: Integer;
  Buf: TStringBuilder;
begin
  Clear;
  Text := AText;
  // BOM that survived reading
  if (Text <> '') and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);

  Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  FmEnd := -1;
  if (Length(Lines) > 1) and (Trim(Lines[0]) = '---') then
    for I := 1 to High(Lines) do
      if Trim(Lines[I]) = '---' then
      begin
        FmEnd := I;
        Break;
      end;

  if FmEnd < 0 then
  begin
    // Without frontmatter (or without closing): everything is body
    FBody := Trim(Text.Replace(#13#10, #10));
    Exit;
  end;

  FHasFrontmatter := True;
  ParseFrontmatter(Lines, FmEnd);

  Buf := TStringBuilder.Create;
  try
    for I := FmEnd + 1 to High(Lines) do
    begin
      if I > FmEnd + 1 then
        Buf.Append(#10);
      Buf.Append(Lines[I]);
    end;
    FBody := Trim(Buf.ToString);
  finally
    Buf.Free;
  end;
end;

procedure TAiSkillDoc.LoadFromFile(const APath: string);
var
  LFile: string;
begin
  if TDirectory.Exists(APath) then
    LFile := TPath.Combine(APath, AI_SKILL_FILE_NAME)
  else
    LFile := APath;

  if not TFile.Exists(LFile) then
    raise EAiSkillError.CreateFmt('Skill not found: %s', [LFile]);

  LoadFromText(TFile.ReadAllText(LFile, TEncoding.UTF8));
  FSource := ssFile;
  FSourcePath := LFile;

  if FName = '' then
  begin
    if SameText(TPath.GetFileName(LFile), AI_SKILL_FILE_NAME) then
      FName := TPath.GetFileName(ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(LFile)))
    else
      FName := TPath.GetFileNameWithoutExtension(LFile);
  end;
end;

procedure TAiSkillDoc.LoadFromPPM(const AName, AVersion, ARegistryUrl: string);
var
  Registry, PkgName, LVersion, Url, Body, TypeStr: string;
  Pkg: TJSONObject;
  Status: Integer;
begin
  if Trim(AName) = '' then
    raise EAiSkillError.Create('LoadFromPPM: missing skill name');

  Registry := TAiPPMClient.RegistryOrDefault(ARegistryUrl);
  PkgName := Trim(AName);

  // Metadata: confirm it exists, it is a skill and give the version.
  // Only a 404 triggers the retry with prefix; a network failure is reported
  // as is instead of disguised as "not found".
  Pkg := TAiPPMClient.TryGetPackage(Registry, PkgName);
  if not Assigned(Pkg) and not StartsText(AI_PPM_SKILL_PREFIX, PkgName) then
  begin
    // 'code-review' -> 'skill-code-review' (PPM naming convention)
    Pkg := TAiPPMClient.TryGetPackage(Registry, AI_PPM_SKILL_PREFIX + PkgName);
    if Assigned(Pkg) then
      PkgName := AI_PPM_SKILL_PREFIX + PkgName;
  end;
  if not Assigned(Pkg) then
    raise EAiSkillError.CreateFmt('Skill "%s" not found in the PPM registry (%s)',
      [AName, Registry]);
  try
    TypeStr := '';
    Pkg.TryGetValue<string>('package.type', TypeStr);
    if (TypeStr <> '') and not SameText(TypeStr, 'skill') then
      raise EAiSkillError.CreateFmt(
        'The PPM package "%s" is of type "%s", not a skill', [PkgName, TypeStr]);
  finally
    Pkg.Free;
  end;

  LVersion := Trim(AVersion);
  if LVersion = '' then
    LVersion := TAiPPMClient.ResolveVersion(Registry, PkgName);
  if LVersion = '' then
    raise EAiSkillError.CreateFmt('The PPM skill "%s" has no available versions', [PkgName]);

  Url := Format('%s/v1/packages/%s/%s/skill',
    [Registry, TNetEncoding.URL.Encode(PkgName), TNetEncoding.URL.Encode(LVersion)]);
  Body := TAiPPMClient.Get(Url, Status);

  LoadFromText(Body);
  FSource := ssPPM;
  FSourcePath := Url;
  FVersion := LVersion;
  if FName = '' then
    FName := PkgName;
end;

class function TAiSkillDoc.Parse(const AText: string): TAiSkillDoc;
begin
  Result := TAiSkillDoc.Create;
  try
    Result.LoadFromText(AText);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkillDoc.FromFile(const APath: string): TAiSkillDoc;
begin
  Result := TAiSkillDoc.Create;
  try
    Result.LoadFromFile(APath);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkillDoc.FromPPM(const AName, AVersion, ARegistryUrl: string): TAiSkillDoc;
begin
  Result := TAiSkillDoc.Create;
  try
    Result.LoadFromPPM(AName, AVersion, ARegistryUrl);
  except
    Result.Free;
    raise;
  end;
end;

class function TAiSkillDoc.FindSkillFiles(const AFolder: string): TArray<string>;
var
  List: TStringList;
  Dir, F: string;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
    Exit;
  List := TStringList.Create;
  try
    F := TPath.Combine(AFolder, AI_SKILL_FILE_NAME);
    if TFile.Exists(F) then
      List.Add(F);
    for Dir in TDirectory.GetDirectories(AFolder) do
    begin
      F := TPath.Combine(Dir, AI_SKILL_FILE_NAME);
      if TFile.Exists(F) then
        List.Add(F);
    end;
    List.Sort;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

class function TAiSkillDoc.LooksLikeHtml(const AText: string): Boolean;
var
  Head: string;
begin
  Head := Copy(TrimLeft(AText), 1, 64).ToLower;
  Result := Head.StartsWith('<!doctype html') or Head.StartsWith('<html');
end;

{ TAiPPMClient }

class function TAiPPMClient.RegistryOrDefault(const ARegistryUrl: string): string;
begin
  Result := Trim(ARegistryUrl);
  if Result = '' then
    Result := AI_PPM_DEFAULT_REGISTRY;
  while Result.EndsWith('/') do
    Result := Copy(Result, 1, Length(Result) - 1);
end;

class function TAiPPMClient.Get(const AUrl: string; out AStatus: Integer): string;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Msg, CType: string;
  Err: TJSONValue;
begin
  AStatus := 0;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := PPM_TIMEOUT_MS;
    Client.ResponseTimeout := PPM_TIMEOUT_MS;
    try
      Resp := Client.Get(AUrl);
    except
      on E: Exception do
        raise EAiSkillError.CreateFmt('Could not connect to the PPM registry (%s): %s',
          [AUrl, E.Message]);
    end;
    AStatus := Resp.StatusCode;
    Result := Resp.ContentAsString(TEncoding.UTF8);
    CType := Resp.MimeType.ToLower;

    if AStatus <> 200 then
    begin
      Msg := '';
      Err := TJSONObject.ParseJSONValue(Result);
      try
        if Err is TJSONObject then
          TJSONObject(Err).TryGetValue<string>('message', Msg);
      finally
        Err.Free;
      end;
      if Msg = '' then
        Msg := 'HTTP ' + IntToStr(AStatus);
      raise EAiSkillError.CreateFmt('PPM registry: %s (%s)', [Msg, AUrl]);
    end;

    // A 200 with HTML is the site's page, not the requested resource (badly
    // formed URL or wrong host). Previously this ended in "invalid JSON".
    if CType.Contains('text/html') or TAiSkillDoc.LooksLikeHtml(Result) then
      raise EAiSkillError.CreateFmt(
        'The URL returned an HTML page, not a PPM registry resource: %s ' +
        '(check the registry URL)', [AUrl]);
  finally
    Client.Free;
  end;
end;

class function TAiPPMClient.GetPackage(const ARegistryUrl, AName: string): TJSONObject;
var
  Body: string;
  Status: Integer;
  V: TJSONValue;
begin
  Body := Get(Format('%s/v1/packages/%s',
    [RegistryOrDefault(ARegistryUrl), TNetEncoding.URL.Encode(AName)]), Status);
  V := TJSONObject.ParseJSONValue(Body);
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise EAiSkillError.CreateFmt('Unexpected response from the PPM registry for "%s"', [AName]);
  end;
  Result := TJSONObject(V);
end;

class function TAiPPMClient.TryGetPackage(const ARegistryUrl, AName: string): TJSONObject;
var
  Body: string;
  Status: Integer;
  V: TJSONValue;
begin
  Result := nil;
  Status := 0;
  try
    Body := Get(Format('%s/v1/packages/%s',
      [RegistryOrDefault(ARegistryUrl), TNetEncoding.URL.Encode(AName)]), Status);
  except
    on E: EAiSkillError do
    begin
      if Status = 404 then
        Exit;
      raise;
    end;
  end;
  V := TJSONObject.ParseJSONValue(Body);
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise EAiSkillError.CreateFmt('Unexpected response from the PPM registry for "%s"', [AName]);
  end;
  Result := TJSONObject(V);
end;

class function TAiPPMClient.CompareVersions(const A, B: string): Integer;

  function Parts(const S: string): TArray<Integer>;
  var
    Core: string;
    Items: TArray<string>;
    I: Integer;
  begin
    Core := Trim(S);
    if Core.StartsWith('v') or Core.StartsWith('V') then
      Delete(Core, 1, 1);
    I := Core.IndexOfAny(['-', '+']);
    if I >= 0 then
      Core := Core.Substring(0, I);
    Items := Core.Split(['.']);
    SetLength(Result, 3);
    for I := 0 to 2 do
      if I < Length(Items) then
        Result[I] := StrToIntDef(Items[I], 0)
      else
        Result[I] := 0;
  end;

var
  PA, PB: TArray<Integer>;
  I: Integer;
begin
  PA := Parts(A);
  PB := Parts(B);
  for I := 0 to 2 do
    if PA[I] <> PB[I] then
      Exit(PA[I] - PB[I]);
  Result := 0;
end;

class function TAiPPMClient.ResolveVersion(const ARegistryUrl, AName: string): string;
var
  Pkg, Ver: TJSONObject;
  Versions: TJSONArray;
  Yanked: TJSONValue;
  V: string;
  I: Integer;
begin
  Result := '';
  Pkg := GetPackage(ARegistryUrl, AName);
  try
    if not Pkg.TryGetValue<TJSONArray>('package.versions', Versions) then
      Exit;
    // The greatest semver: no trust in the order they arrive
    for I := 0 to Versions.Count - 1 do
    begin
      if not (Versions.Items[I] is TJSONObject) then
        Continue;
      Ver := TJSONObject(Versions.Items[I]);
      Yanked := Ver.FindValue('yanked');
      if Assigned(Yanked) and (Yanked is TJSONTrue) then
        Continue;
      if Ver.TryGetValue<string>('version', V) and
         ((Result = '') or (CompareVersions(V, Result) > 0)) then
        Result := V;
    end;
  finally
    Pkg.Free;
  end;
end;

end.
