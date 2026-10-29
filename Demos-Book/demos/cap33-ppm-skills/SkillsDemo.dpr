program SkillsDemo;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — Chapter 33: PPM Skills for Claude Code and Delphi agents
// =============================================================================
//
// Demonstrates the three key operations with TAiPrompts + PPM:
//
//   1. DescubrirSkills  — SearchPPM(type='skill') lists the registry catalog
//   2. CargarSkill      — LoadSkillFromPPM downloads and parses YAML frontmatter
//   3. UsarSkillComoAgente — Strings.Text as SystemPrompt in TAiChatConnection
//
// TAiPrompts.LoadSkillFromPPM:
//   - Calls GET /v1/packages/{name}/{version}/skill
//   - Extracts from YAML frontmatter: model, allowed-tools
//   - Stores ONLY the Markdown body in Strings.Text (without frontmatter)
//   - Exposes SkillModel and SkillAllowedTools in the resulting item
//
// Requires: GROQ_API_KEY (for part 3)
// =============================================================================

uses
  System.SysUtils, System.JSON,
  uMakerAi.Prompts,         // TAiPrompts, TAiPromptItem
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Groq;       // auto-registers driver 'Groq'

// -----------------------------------------------------------------------------
//  1. Discover skills available in the PPM registry
// -----------------------------------------------------------------------------
procedure DescubrirSkills(Prompts: TAiPrompts);
var
  Json    : TJSONObject;
  Pkgs    : TJSONArray;
  Pkg     : TJSONObject;
  Name    : string;
  Desc    : string;
  I       : Integer;
begin
  WriteLn('--- 1. Discover skills in the registry ---');
  Json := Prompts.SearchPPM('', 'skill', 1, 10);  // query vacío = todos los skills
  if not Assigned(Json) then
  begin
    WriteLn('  Could not connect to the registry.');
    WriteLn;
    Exit;
  end;
  try
    if Json.TryGetValue<TJSONArray>('packages', Pkgs) then
    begin
      WriteLn('  Available skills: ', Pkgs.Count);
      for I := 0 to Pkgs.Count - 1 do
      begin
        Pkg  := Pkgs.Items[I] as TJSONObject;
        Name := '';
        Desc := '';
        Pkg.TryGetValue<String>('name',        Name);
        Pkg.TryGetValue<String>('description', Desc);
        WriteLn('  ', I + 1, '. ', Name);
        WriteLn('     ', Desc);
      end;
    end
    else
      WriteLn('  (no results)');
  finally
    Json.Free;
  end;
  WriteLn;
end;

// -----------------------------------------------------------------------------
//  2. Load skill: parsed frontmatter, body in Strings.Text
// -----------------------------------------------------------------------------
procedure CargarSkill(Prompts: TAiPrompts; const AName: string);
var
  Skill: TAiPromptItem;
  N, I : Integer;
begin
  WriteLn('--- 2. Load skill: ', AName, ' ---');
  Skill := Prompts.LoadSkillFromPPM(AName);
  if not Assigned(Skill) then
  begin
    WriteLn('  Not found or no connection.');
    WriteLn;
    Exit;
  end;

  WriteLn('  Name       : ', Skill.Nombre);
  WriteLn('  Description: ', Skill.Descripcion);
  WriteLn('  SkillModel : ', Skill.SkillModel);
  WriteLn('  AllowedTools: ', Skill.SkillAllowedTools);
  WriteLn('  Lines in body: ', Skill.Strings.Count);
  WriteLn;
  WriteLn('  First 6 lines of the body (without frontmatter):');
  N := Skill.Strings.Count;
  if N > 6 then N := 6;
  for I := 0 to N - 1 do
    WriteLn('  | ', Skill.Strings[I]);
  if Skill.Strings.Count > 6 then
    WriteLn('  | [...', Skill.Strings.Count - 6, ' more lines]');
  WriteLn;
end;

// -----------------------------------------------------------------------------
//  3. Use the skill as a system prompt in a MakerAI agent
// -----------------------------------------------------------------------------
procedure UsarSkillComoAgente(Prompts: TAiPrompts; const AName: string);
var
  Skill   : TAiPromptItem;
  AiConn  : TAiChatConnection;
  Modelo  : string;
  Revision: string;
const
  // Deliberately insecure Delphi code (SQL injection) for the skill to detect
  CODIGO_SQL_INJECTION =
    'procedure TForm1.ButtonClick(Sender: TObject);' + sLineBreak +
    'var S: string;' + sLineBreak +
    'begin' + sLineBreak +
    '  S := Edit1.Text;' + sLineBreak +
    '  Query1.SQL.Text := ''SELECT * FROM clientes WHERE nombre = '' + S;' + sLineBreak +
    '  Query1.Open;' + sLineBreak +
    'end;';
begin
  WriteLn('--- 3. Skill as the agent''s system prompt (Groq) ---');

  // The skill is already cached in Prompts.Items; just look it up by name
  Skill := Prompts.LoadSkillFromPPM(AName);
  if (Skill = nil) or (Skill.Strings.Count = 0) then
  begin
    WriteLn('  Skill not available, skipping.');
    WriteLn;
    Exit;
  end;

  // The skill recommends claude-opus-4-6; we use Groq as a low-cost local driver.
  // For production: driver='Claude', Model=Skill.SkillModel
  Modelo := 'llama-3.3-70b-versatile';

  WriteLn('  Skill        : ', Skill.Nombre);
  WriteLn('  Driver used  : Groq (', Modelo, ')');
  WriteLn('  Skill suggests: ', Skill.SkillModel);
  WriteLn('  Tools (info) : ', Skill.SkillAllowedTools);
  WriteLn;

  AiConn := TAiChatConnection.Create(nil);
  try
    AiConn.DriverName                    := 'Groq';
    AiConn.Params.Values['ApiKey']       := '@GROQ_API_KEY';
    AiConn.Model                         := Modelo;
    AiConn.Params.Values['Asynchronous'] := 'False';
    AiConn.SystemPrompt.Text             := Skill.Strings.Text; // cuerpo sin frontmatter

    WriteLn('  Code to review:');
    WriteLn('  ', StringReplace(CODIGO_SQL_INJECTION, sLineBreak, sLineBreak + '  ', []));
    WriteLn;
    WriteLn('  Agent review:');
    Revision := AiConn.AddMessageAndRun(
      'Revisa el siguiente código Delphi e identifica problemas:' +
      sLineBreak + CODIGO_SQL_INJECTION, 'user', []);
    WriteLn(Revision);
  finally
    AiConn.Free;
  end;
  WriteLn;
end;

// =============================================================================
const
  SKILL_NAME = 'skill-code-review';

begin
  WriteLn('==============================================');
  WriteLn('  Ch. 33 — PPM Skills for Claude Code');
  WriteLn('==============================================');
  WriteLn;

  var Prompts := TAiPrompts.Create(nil);
  try
    // 1. Discover skills in the registry
    DescubrirSkills(Prompts);

    // 2. Load skill with parsed frontmatter
    CargarSkill(Prompts, SKILL_NAME);

    // 3. Use skill as an agent (requires GROQ_API_KEY)
    if GetEnvironmentVariable('GROQ_API_KEY') <> '' then
      UsarSkillComoAgente(Prompts, SKILL_NAME)
    else
      WriteLn('SKIP part 3: GROQ_API_KEY not configured.');

  finally
    Prompts.Free;
  end;

  WriteLn;
  WriteLn('To enable in Claude Code:');
  WriteLn('  ppm install ', SKILL_NAME);
  WriteLn('  ppm skill install-claude');
  WriteLn('  -> /', SKILL_NAME, ' available in Claude Code');
  WriteLn;
  WriteLn('Demo completed. Press Enter to exit.');
  ReadLn;
end.
