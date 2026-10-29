program SkillsDemo;

// =============================================================================
// DEMO 091 - Skills: reusable instructions for chats and agents
// =============================================================================
// A skill is a SKILL.md: YAML frontmatter (name, when to use it) + the
// instructions in Markdown. It is the format of Agent Skills and of the
// PPM registry. The skills\ folder of this demo brings three:
//
//   invoices        with a supporting file (plantilla.md)
//   delphi-reviewer  code review rules
//   support-tone    tone for replying to customers
//
//   A. TAiSkills (on demand): the model sees only the catalog and loads the
//      skill it needs with use_skill; if the instructions ask for it, it reads
//      the supporting files with read_skill_file. A question that does not
//      match any skill loads nothing.
//   B. TLLMNode + TAiSkill (fixed personality): an agent node takes the
//      skill as its base; ResolveConfig shows how it combines with the node.
//   C. TAiPrompts.ApplySkill (by hand): copies a skill's instructions
//      into a connection's SystemPrompt.
//
// Uso:
//   SkillsDemo.exe                                  (OpenAI gpt-5.6-luna)
//   SkillsDemo.exe --driver Claude --model claude-haiku-4-5-20251001
//   SkillsDemo.exe --driver Groq --model openai/gpt-oss-120b
//   SkillsDemo.exe --ppm        (adds skill-code-review from the PPM registry)
//
// La API key se toma de <DRIVER>_API_KEY (OPENAI_API_KEY, CLAUDE_API_KEY...).
// =============================================================================

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Net.HttpClient,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,   // registra los drivers
  uMakerAi.Tools.Functions,
  uMakerAi.Prompts,
  uMakerAi.Agents,
  uMakerAi.Agents.Skill in '..\..\Source\Agents\uMakerAi.Agents.Skill.pas',
  uMakerAi.Agents.Node.LLM in '..\..\Source\Agents\uMakerAi.Agents.Node.LLM.pas',
  uMakerAi.Skills.Format in '..\..\Source\Core\uMakerAi.Skills.Format.pas',
  uMakerAi.Tools.Skills in '..\..\Source\Tools\uMakerAi.Tools.Skills.pas';

const
  CODIGO_CON_ERRORES =
    'procedure Cargar;'#10 +
    'var L: TStringList;'#10 +
    'begin'#10 +
    '  L := TStringList.Create;'#10 +
    '  L.LoadFromFile(''datos.txt'');'#10 +
    '  try'#10 +
    '    Procesar(L);'#10 +
    '  except'#10 +
    '  end;'#10 +
    'end;';

type
  // Framework events are 'of object': handlers live in a class
  TEventos = class
  public
    Cargados: string;
    Error: string;
    procedure SkillLoaded(Sender: TObject; ASkill: TAiSkillItem);
    procedure OnError(Sender: TObject; const ErrorMsg: string; Exception: Exception;
      const AResponse: IHTTPResponse);
  end;

procedure TEventos.SkillLoaded(Sender: TObject; ASkill: TAiSkillItem);
begin
  Cargados := Cargados + ASkill.Name + ' ';
end;

procedure TEventos.OnError(Sender: TObject; const ErrorMsg: string; Exception: Exception;
  const AResponse: IHTTPResponse);
begin
  Error := ErrorMsg;
end;

var
  GDriver, GModel, GApiKey, GSkillsDir: string;
  GUsarPPM: Boolean;

procedure LeerArgumentos;
var
  I: Integer;
begin
  GDriver := 'OpenAI';
  GModel := 'gpt-5.6-luna';
  GUsarPPM := False;
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--driver') and (I < ParamCount) then
    begin
      Inc(I);
      GDriver := ParamStr(I);
      GModel := '';
    end
    else if SameText(ParamStr(I), '--model') and (I < ParamCount) then
    begin
      Inc(I);
      GModel := ParamStr(I);
    end
    else if SameText(ParamStr(I), '--ppm') then
      GUsarPPM := True;
    Inc(I);
  end;
  GApiKey := '@' + UpperCase(GDriver) + '_API_KEY';
end;

// La carpeta skills\ está junto al .dpr; el .exe queda en Win64\Release
function BuscarCarpetaSkills: string;
var
  Dir: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for I := 0 to 3 do
  begin
    Result := TPath.Combine(Dir, 'skills');
    if TDirectory.Exists(Result) then
      Exit;
    Dir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir));
  end;
  raise Exception.Create('The demo skills\ folder was not found');
end;

procedure Titulo(const S: string);
begin
  Writeln;
  Writeln(StringOfChar('=', 78));
  Writeln(' ', S);
  Writeln(StringOfChar('=', 78));
end;

function NuevaConexion(Eventos: TEventos): TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := GDriver;
  if GModel <> '' then
    Result.Model := GModel;
  Result.Params.Values['ApiKey'] := GApiKey;
  Result.Params.Values['Asynchronous'] := 'False';
  Result.Params.Values['Tool_Active'] := 'True';
  Result.Params.Values['Max_tokens'] := '2000';
  Result.OnError := Eventos.OnError;
end;

// ---------------------------------------------------------------------------
// A. TAiSkills: skills bajo demanda
// ---------------------------------------------------------------------------
procedure BloqueA(Eventos: TEventos);
const
  PREGUNTAS: array[0..3] of string = (
    'Hazme la factura para Ferreteria El Tornillo por 3 horas de capacitacion en Delphi a 150.000 pesos la hora.',
    'Revisa este codigo:'#10 + CODIGO_CON_ERRORES,
    'Un cliente escribe: "Llevo tres dias sin poder entrar al sistema y nadie me responde". Contestale.',
    'Cuanto es 17 por 23? Responde solo el numero.');
var
  Conn: TAiChatConnection;
  Funcs: TAiFunctions;
  Skills: TAiSkills;
  P, R: string;
begin
  Titulo('A. TAiSkills: el modelo carga el skill que necesita');
  Conn := NuevaConexion(Eventos);
  Funcs := TAiFunctions.Create(nil);
  Skills := TAiSkills.Create(nil);
  try
    Skills.OnSkillLoaded := Eventos.SkillLoaded;
    Skills.Functions := Funcs;
    Writeln('Skills loaded from ', GSkillsDir, ': ', Skills.LoadFromFolder(GSkillsDir));
    if GUsarPPM then
    try
      Skills.LoadFromPPM('skill-code-review');
      Writeln('From the PPM registry: skill-code-review');
    except
      on E: Exception do
        Writeln('PPM not available: ', E.Message);
    end;
    Conn.AiFunctions := Funcs;

    Writeln;
    Writeln('Catalog seen by the model (only this travels in each turn):');
    Writeln(Skills.Catalog);

    for P in PREGUNTAS do
    begin
      Eventos.Cargados := '';
      Eventos.Error := '';
      Conn.NewChat;
      Writeln;
      Writeln('>>> ', P.Replace(#10, ' ').Substring(0, 90));
      R := Conn.AddMessageAndRun(P, 'user', []);
      if Eventos.Cargados = '' then
        Writeln('[skills loaded: none]')
      else
        Writeln('[skills loaded: ', Trim(Eventos.Cargados), ']');
      if Eventos.Error <> '' then
        Writeln('ERROR: ', Eventos.Error)
      else
        Writeln(R.Trim);
    end;
  finally
    Conn.AiFunctions := nil;
    Skills.Free;
    Funcs.Free;
    Conn.Free;
  end;
end;

// ---------------------------------------------------------------------------
// B. TLLMNode con TAiSkill: el skill como personalidad fija del nodo
// ---------------------------------------------------------------------------
procedure BloqueB;
var
  Manager: TAIAgentManager;
  Node: TLLMNode;
  Cfg: TLLMNodeConfig;
begin
  Titulo('B. TLLMNode + TAiSkill: el skill como base del nodo');
  Manager := TAIAgentManager.Create(nil);
  try
    Manager.Asynchronous := False;
    Node := TLLMNode.Create(Manager);
    Node.Name := 'Revisor';
    // El nodo toma posesión del skill (no liberarlo a mano)
    Node.Skill := TAiSkill.FromFolder(TPath.Combine(GSkillsDir, 'revisor-delphi'));
    Node.DriverName := GDriver;
    Node.Model := GModel;
    Node.ApiKey := GApiKey;
    Node.SystemPrompt := 'Responde en español y en menos de 120 palabras.';
    Node.UseAllTools := False;
    Manager.StartNode := Node;
    Manager.EndNode := Node;

    Cfg := Node.ResolveConfig;
    Writeln('Driver: ', Cfg.DriverName, '   Model: ', Cfg.Model);
    Writeln('SystemPrompt = skill instructions + node instructions (',
      Length(Cfg.SystemPrompt), ' characters)');
    Writeln;
    Writeln(Manager.Run(CODIGO_CON_ERRORES).Trim);
  finally
    Manager.Free;
  end;
end;

// ---------------------------------------------------------------------------
// C. TAiPrompts.ApplySkill: el skill copiado al SystemPrompt a mano
// ---------------------------------------------------------------------------
procedure BloqueC(Eventos: TEventos);
var
  Prompts: TAiPrompts;
  Conn: TAiChatConnection;
begin
  Titulo('C. TAiPrompts.ApplySkill: el skill fijo en el SystemPrompt');
  Prompts := TAiPrompts.Create(nil);
  Conn := NuevaConexion(Eventos);
  try
    Prompts.LoadSkillsFromFolder(GSkillsDir);
    Prompts.ApplySkill('tono-soporte', Conn.SystemPrompt);
    Writeln('Connection SystemPrompt: ', Conn.SystemPrompt.Count, ' lines from the tono-soporte skill');
    Writeln;
    Writeln(Conn.AddMessageAndRun(
      'El cliente dice: "Me cobraron dos veces la mensualidad". Responde.', 'user', []).Trim);
  finally
    Conn.Free;
    Prompts.Free;
  end;
end;

var
  Eventos: TEventos;
begin
  // Consola en UTF-8 para ver bien las tildes
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  Eventos := TEventos.Create;
  try
    try
      LeerArgumentos;
      GSkillsDir := BuscarCarpetaSkills;
      Writeln('Driver: ', GDriver, '   Model: ', IfThen(GModel = '', '(driver default)', GModel));
      BloqueA(Eventos);
      BloqueB;
      BloqueC(Eventos);
      ExitCode := 0;
    except
      on E: Exception do
      begin
        Writeln('ERROR: ', E.ClassName, ': ', E.Message);
        ExitCode := 2;
      end;
    end;
  finally
    Eventos.Free;
  end;
end.
