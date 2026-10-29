program HerramientasSistema;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 18: System Tools
// =============================================================================
// TAiShell: the LLM executes commands in a persistent shell session.
// TAiTextEditorTool: the LLM reads and edits files in a controlled way.
//
// Required environment variables:
//   CLAUDE_API_KEY   -- Demos 1, 3, 4
//   (Local Ollama)   -- Demo 2 (qwen3.5:2b must be running in Ollama)
//
// Working folder: C:\temp\demoshell  (created automatically)
//
// Key difference from ChatTools:
//   ChatTools    -> the framework invokes them transparently to the LLM
//   These tools  -> the LLM DISCOVERS them in its list and decides when to call them
// =============================================================================

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Tools.Functions,
  uMakerAi.Tools.Shell,
  uMakerAi.Tools.TextEditor,
  uMakerAi.Chat.Initializations;

const
  WORK_DIR   = 'C:\temp\demoshell';
  CLAUDE_KEY = '@CLAUDE_API_KEY';
  CLAUDE_DRV = 'Claude';
  CLAUDE_MDL = 'claude-sonnet-4-6';
  OLLAMA_DRV = 'Ollama';
  OLLAMA_MDL = 'qwen3.5:2b';  // 2.3B -- lightweight and reliable in tool calling

// -----------------------------------------------------------------------------

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  TSistemaDemo
//
//  Container class for the 4 demos. Each demo creates and frees its own
//  objects; the class only exists to provide object handlers to the tools.
// =============================================================================
type
  TSistemaDemo = class
  private
    FTextEditor: TAiTextEditorTool;  // accessed from OnTextEditorAction

    // Tool call handlers (must be class methods -- TFunctionEvent of object)
    procedure OnTextEditorAction(Sender: TObject; FA: TFunctionActionItem;
      FN: String; TC: TAiToolsFunction; var Handled: Boolean);
    procedure OnShellLog(Sender: TObject;
      const Command, StdOut, StdErr: string; ExitCode: Integer);

    // Helpers
    procedure PrepararCarpeta;
    procedure RegistrarTextEditor(LFuncs: TAiFunctions);

    // Demos
    procedure Demo1_Shell_Claude;
    procedure Demo2_Shell_Ollama;
    procedure Demo3_TextEditor_Claude;
    procedure Demo4_Combinado;
  public
    procedure Run;
  end;

// =============================================================================
//  Handlers
// =============================================================================

procedure TSistemaDemo.OnTextEditorAction(Sender: TObject;
  FA: TFunctionActionItem; FN: String; TC: TAiToolsFunction;
  var Handled: Boolean);
begin
  WriteLn(Format('  [TextEditor] %s -> %s',
    [TC.Params.Values['command'], TC.Params.Values['path']]));
  TC.Response := FTextEditor.Execute(TC.Arguments);
  Handled := True;
end;

procedure TSistemaDemo.OnShellLog(Sender: TObject;
  const Command, StdOut, StdErr: string; ExitCode: Integer);
var
  LOut: string;
begin
  WriteLn('  [bash] $ ', Trim(Command));
  LOut := Trim(StdOut);
  if LOut <> '' then
  begin
    if Length(LOut) > 300 then
      LOut := Copy(LOut, 1, 300) + '...';
    WriteLn('  ',
      StringReplace(LOut, #10, #13#10 + '  ', [rfReplaceAll]));
  end;
end;

// =============================================================================
//  PrepararCarpeta: crea C:\temp\demoshell y tres archivos de prueba
// =============================================================================

procedure TSistemaDemo.PrepararCarpeta;
const
  // Pure LF (#10): TAiTextEditorTool and the LLMs work with \n.
  // CRLF (#13#10) makes str_replace fail because the LLM reconstructs
  // old_str with \n and the file has \r\n — they do not match.
  FIB_PAS =
    'function Fibonacci(N: Integer): Integer;'#10 +
    'begin'#10 +
    '  if N <= 1 then'#10 +
    '    Result := N'#10 +
    '  else'#10 +
    '    Result := Fibonacci(N - 1) + Fibonacci(N - 2);'#10 +
    '  // TODO: validate negative values'#10 +
    'end;'#10;

  CONFIG_TXT =
    'host=localhost'#10 +
    'port=5432'#10 +
    'database=production'#10 +
    'user=admin'#10 +
    'timeout=30'#10;

  NOTAS_TXT =
    'Team meeting - May 17, 2026'#10 +
    'Pending topics:'#10 +
    '- Review billing module'#10 +
    '- Update dependencies'#10 +
    '- Document REST API'#10;
begin
  TDirectory.CreateDirectory(WORK_DIR);
  TFile.WriteAllText(WORK_DIR + '\fibonacci.pas', FIB_PAS,   TEncoding.UTF8);
  TFile.WriteAllText(WORK_DIR + '\config.txt',    CONFIG_TXT, TEncoding.UTF8);
  TFile.WriteAllText(WORK_DIR + '\notas.txt',     NOTAS_TXT,  TEncoding.UTF8);

  WriteLn('  Working folder: ', WORK_DIR);
  WriteLn('  Files created    : fibonacci.pas, config.txt, notas.txt');
end;

// =============================================================================
//  RegistrarTextEditor: define la funcion text_editor en TAiFunctions
// =============================================================================

procedure TSistemaDemo.RegistrarTextEditor(LFuncs: TAiFunctions);
var
  LFn   : TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  LFn := LFuncs.Functions.AddFunction('text_editor', True, OnTextEditorAction);
  LFn.Description.Text :=
    'Reads and edits text files. ' +
    'view: shows the content. ' +
    'create: creates a new file with file_text. ' +
    'str_replace: replaces old_str with new_str (old_str must be unique in the file). ' +
    'insert: inserts new_str after the insert_line line. ' +
    'apply_diff: applies a unified diff.';

  LParam := LFn.Parameters.Add;
  LParam.Name := 'command';
  LParam.Description.Text := 'Action: view | create | str_replace | insert | apply_diff';
  LParam.ParamType := ptString;
  LParam.Required  := True;

  LParam := LFn.Parameters.Add;
  LParam.Name := 'path';
  LParam.Description.Text := 'Full path of the file';
  LParam.ParamType := ptString;
  LParam.Required  := True;

  LParam := LFn.Parameters.Add;
  LParam.Name := 'file_text';
  LParam.Description.Text := 'Full content of the file (only for create)';
  LParam.ParamType := ptString;
  LParam.Required  := False;

  LParam := LFn.Parameters.Add;
  LParam.Name := 'old_str';
  LParam.Description.Text :=
    'Fragmento EXACTO a reemplazar (para str_replace). Debe ser unico en el archivo.';
  LParam.ParamType := ptString;
  LParam.Required  := False;

  LParam := LFn.Parameters.Add;
  LParam.Name := 'new_str';
  LParam.Description.Text :=
    'Texto de reemplazo (para str_replace) o texto a insertar (para insert)';
  LParam.ParamType := ptString;
  LParam.Required  := False;

  LParam := LFn.Parameters.Add;
  LParam.Name := 'insert_line';
  LParam.Description.Text := 'Line number after which to insert (for insert)';
  LParam.ParamType := ptInteger;
  LParam.Required  := False;
end;

// =============================================================================
//  Demo 1 -- TAiShell + Claude
//
//  The LLM uses bash to explore the directory. SecurityMode=ssmAllowList
//  restricts commands to a safe set defined in SecurityList.
//  The shell session is persistent: cd followed by dir works as expected.
// =============================================================================
procedure TSistemaDemo.Demo1_Shell_Claude;
var
  LFuncs: TAiFunctions;
  LShell: TAiShell;
  Conn  : TAiChatConnection;
  Resp  : string;
begin
  Separador('Demo 1 -- TAiShell + Claude: explore and read files');

  LFuncs := TAiFunctions.Create(nil);
  LShell := TAiShell.Create(nil);
  Conn   := TAiChatConnection.Create(nil);
  try
    LShell.SecurityMode := ssmAllowList;
    LShell.SecurityList.CommaText := 'dir,type,tree,echo,cd';
    LShell.OnConsoleLog := OnShellLog;
    LShell.RegisterInFunctions(LFuncs, 'bash');

    Conn.DriverName := CLAUDE_DRV;
    Conn.Params.Values['ApiKey']       := CLAUDE_KEY;
    Conn.Model                         := CLAUDE_MDL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'True';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.AiFunctions := LFuncs;

    Conn.SystemPrompt.Text :=
      'You are a system assistant. You execute Windows commands with bash. ' +
      'Work ONLY in ' + WORK_DIR + '. ' +
      'Allowed commands: dir, type, tree, echo, cd. ' +
      'Always respond in Spanish.';

    WriteLn('  Task: list files and show the content of fibonacci.pas');
    WriteLn('');

    Resp := Conn.AddMessageAndRun(
      'Use dir to list the files in ' + WORK_DIR +
      ' and then use type to show the content of fibonacci.pas. ' +
      'Summarize in two or three lines what you found.',
      'user', []);

    WriteLn('');
    WriteLn('  Claude responded:');
    WriteLn('  ', StringReplace(Trim(Resp), #10, #13#10 + '  ', [rfReplaceAll]));
  finally
    Conn.Free;
    LShell.Free;
    LFuncs.Free;
  end;

  WriteLn('');
  WriteLn('-> SecurityMode=ssmAllowList: only commands in the list are allowed.');
  WriteLn('   The session is persistent: cd and dir in separate calls work.');
  WriteLn('   RegisterInFunctions registers bash with a single call method.');
end;

// =============================================================================
//  Demo 2 -- TAiShell + Ollama/qwen3.5:2b  (100% local)
//
//  The same TAiShell works with Ollama without changes. The only difference
//  is DriverName and Model. qwen3.5:2b is a local model with 2.3B parameters
//  with reliable tool calling support via Ollama.
//
//  Note: qwen3.5 is not in Initializations -> Tool_Active must be activated
//  explicitly in the code. Larger models (qwen3.5:7b, etc.)
//  are more reliable but require more VRAM.
// =============================================================================
procedure TSistemaDemo.Demo2_Shell_Ollama;
var
  LFuncs: TAiFunctions;
  LShell: TAiShell;
  Conn  : TAiChatConnection;
  Resp  : string;
begin
  Separador('Demo 2 -- TAiShell + Ollama/qwen3.5:2b (no internet, no API key)');

  LFuncs := TAiFunctions.Create(nil);
  LShell := TAiShell.Create(nil);
  Conn   := TAiChatConnection.Create(nil);
  try
    LShell.SecurityMode := ssmAllowList;
    LShell.SecurityList.CommaText := 'dir,type,echo';
    LShell.OnConsoleLog := OnShellLog;
    LShell.RegisterInFunctions(LFuncs, 'bash');

    // La unica diferencia con Demo 1: DriverName y Model
    Conn.DriverName := OLLAMA_DRV;
    Conn.Model      := OLLAMA_MDL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'True';  // qwen3.5 no esta en Initializations -> activar explicitamente
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.AiFunctions := LFuncs;

    Conn.SystemPrompt.Text :=
      'Eres un asistente de sistema. Usa bash para ejecutar comandos Windows. ' +
      'Trabaja solo en ' + WORK_DIR + '. ' +
      'Comandos disponibles: dir, type. Responde en espanol.';

    WriteLn('  Driver : ', OLLAMA_DRV, '   Model : ', OLLAMA_MDL);
    WriteLn('  Task   : list the files in ', WORK_DIR);
    WriteLn('  (The TAiShell code is identical to Demo 1)');
    WriteLn('');

    Resp := Conn.AddMessageAndRun(
      'Use dir to list the files in ' + WORK_DIR +
      ' and indicate how many files you found.',
      'user', []);

    WriteLn('');
    WriteLn('  qwen3.5:2b responded:');
    WriteLn('  ', StringReplace(Trim(Resp), #10, #13#10 + '  ', [rfReplaceAll]));
  finally
    Conn.Free;
    LShell.Free;
    LFuncs.Free;
  end;

  WriteLn('');
  WriteLn('-> Same TAiShell, different driver: only DriverName and Model change.');
  WriteLn('   qwen3.5:2b is not in Initializations -> Tool_Active is activated in the code.');
  WriteLn('   100% local: no internet, no API key, no cost per call.');
end;

// =============================================================================
//  Demo 3 -- TAiTextEditorTool + Claude
//
//  TAiTextEditorTool has no RegisterInFunctions of its own: it is registered
//  manually in TAiFunctions through RegistrarTextEditor.
//  The OnTextEditorAction handler delegates to FTextEditor.Execute(TC.Arguments).
//
//  Claude uses str_replace to edit with surgical precision: old_str
//  must match EXACTLY and UNIQUELY in the file.
// =============================================================================
procedure TSistemaDemo.Demo3_TextEditor_Claude;
var
  LFuncs  : TAiFunctions;
  Conn    : TAiChatConnection;
  Resp    : string;
  Contenido: string;
begin
  Separador('Demo 3 -- TAiTextEditorTool + Claude: read and edit code');

  LFuncs      := TAiFunctions.Create(nil);
  FTextEditor := TAiTextEditorTool.Create(nil);
  Conn        := TAiChatConnection.Create(nil);
  try
    RegistrarTextEditor(LFuncs);

    Conn.DriverName := CLAUDE_DRV;
    Conn.Params.Values['ApiKey']       := CLAUDE_KEY;
    Conn.Model                         := CLAUDE_MDL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'True';
    Conn.Params.Values['Max_Tokens']   := '2048';
    Conn.AiFunctions := LFuncs;

    Conn.SystemPrompt.Text :=
      'Eres un asistente de desarrollo Delphi experto. ' +
      'Usas text_editor para leer y editar archivos. ' +
      'Trabaja solo en ' + WORK_DIR + '. ' +
      'Always respond in Spanish.';

    WriteLn('  Task: read fibonacci.pas and add validation for N < 0');
    WriteLn('');

    Resp := Conn.AddMessageAndRun(
      'Read the file ' + WORK_DIR + '\fibonacci.pas with view. ' +
      'Then use str_replace to add at the beginning of the function body ' +
      'a guard that returns -1 when N < 0. ' +
      'Indicate exactly what change you made.',
      'user', []);

    WriteLn('');
    WriteLn('  Claude responded:');
    WriteLn('  ', StringReplace(Trim(Resp), #10, #13#10 + '  ', [rfReplaceAll]));

    WriteLn('');
    WriteLn('  fibonacci.pas after the edit:');
    WriteLn('  ' + StringOfChar('-', 50));
    Contenido := TFile.ReadAllText(WORK_DIR + '\fibonacci.pas', TEncoding.UTF8);
    WriteLn('  ', StringReplace(Trim(Contenido), #10, #13#10 + '  ', [rfReplaceAll]));
    WriteLn('  ' + StringOfChar('-', 50));
  finally
    Conn.Free;
    FTextEditor.Free;
    FTextEditor := nil;
    LFuncs.Free;
  end;

  WriteLn('');
  WriteLn('-> TAiTextEditorTool has no RegisterInFunctions: it is registered manually.');
  WriteLn('   str_replace requires old_str to be UNIQUE in the file.');
  WriteLn('   If Claude cannot guarantee it, use insert or apply_diff.');
end;

// =============================================================================
//  Demo 4 -- TAiShell + TAiTextEditorTool combinados
//
//  Two tools in a single TAiFunctions. The LLM chooses which to use in each
//  step: bash to navigate and verify; text_editor to read and modify.
//  This pattern is the basis of the code agents in chapter 26.
// =============================================================================
procedure TSistemaDemo.Demo4_Combinado;
var
  LFuncs: TAiFunctions;
  LShell: TAiShell;
  Conn  : TAiChatConnection;
  Resp  : string;
begin
  Separador('Demo 4 -- Shell + TextEditor: combined code agent');

  LFuncs      := TAiFunctions.Create(nil);
  LShell      := TAiShell.Create(nil);
  FTextEditor := TAiTextEditorTool.Create(nil);
  Conn        := TAiChatConnection.Create(nil);
  try
    // Registrar ambas herramientas en el mismo TAiFunctions
    LShell.SecurityMode := ssmAllowList;
    LShell.SecurityList.CommaText := 'dir,type,echo';
    LShell.OnConsoleLog := OnShellLog;
    LShell.RegisterInFunctions(LFuncs, 'bash');
    RegistrarTextEditor(LFuncs);

    Conn.DriverName := CLAUDE_DRV;
    Conn.Params.Values['ApiKey']       := CLAUDE_KEY;
    Conn.Model                         := CLAUDE_MDL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Tool_Active']  := 'True';
    Conn.Params.Values['Max_Tokens']   := '2048';
    Conn.AiFunctions := LFuncs;

    Conn.SystemPrompt.Text :=
      'Eres un agente de desarrollo con dos herramientas: ' +
      'bash (ejecuta comandos Windows: dir, type, echo) y ' +
      'text_editor (lee y edita archivos). ' +
      'Trabaja solo en ' + WORK_DIR + '. Responde siempre en espanol.';

    WriteLn('  Multi-step task:');
    WriteLn('    1. List files (bash)');
    WriteLn('    2. Read config.txt (text_editor)');
    WriteLn('    3. Change timeout=30 to timeout=60 (str_replace)');
    WriteLn('    4. Create resumen.txt with what was found (create)');
    WriteLn('');

    Resp := Conn.AddMessageAndRun(
      'Perform these tasks in order:'#13#10 +
      '1. Use bash (dir) to list the files in ' + WORK_DIR + '.'#13#10 +
      '2. Use text_editor (view) to read config.txt.'#13#10 +
      '3. Change timeout=30 to timeout=60 with str_replace.'#13#10 +
      '4. Create the file ' + WORK_DIR + '\resumen.txt with a brief summary ' +
      'of the files you found and the change you made.',
      'user', []);

    WriteLn('');
    WriteLn('  Claude responded:');
    WriteLn('  ', StringReplace(Trim(Resp), #10, #13#10 + '  ', [rfReplaceAll]));

    if TFile.Exists(WORK_DIR + '\resumen.txt') then
    begin
      WriteLn('');
      WriteLn('  resumen.txt generated:');
      WriteLn('  ', StringReplace(
        Trim(TFile.ReadAllText(WORK_DIR + '\resumen.txt', TEncoding.UTF8)),
        #10, #13#10 + '  ', [rfReplaceAll]));
    end;
  finally
    Conn.Free;
    FTextEditor.Free;
    FTextEditor := nil;
    LShell.Free;
    LFuncs.Free;
  end;

  WriteLn('');
  WriteLn('-> Two tools in a TAiFunctions: the LLM chooses which to use in each step.');
  WriteLn('   This pattern (shell + editor) is the basis of the agents in ch. 26.');
end;

// =============================================================================
//  Run
// =============================================================================
procedure TSistemaDemo.Run;
var
  TieneClaude: Boolean;
begin
  WriteLn('=== MakerAI -- Chapter 18: System Tools ===');
  WriteLn('');

  TieneClaude := GetEnvironmentVariable('CLAUDE_API_KEY') <> '';

  WriteLn('  Environment status:');
  if TieneClaude then WriteLn('  [OK] CLAUDE_API_KEY detected')
  else            WriteLn('  [--] CLAUDE_API_KEY not configured -- demos 1, 3, 4 skipped');
  WriteLn('  [??] Ollama: will be detected when running Demo 2 (qwen3.5:2b)');
  WriteLn('');

  PrepararCarpeta;

  if TieneClaude then
  begin
    try Demo1_Shell_Claude;
    except on E: Exception do WriteLn('  [Demo 1 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 1 skipped (CLAUDE_API_KEY not configured) ---');

  try Demo2_Shell_Ollama;
  except on E: Exception do WriteLn('  [Demo 2 ERROR] ', E.ClassName, ': ', E.Message); end;

  if TieneClaude then
  begin
    try Demo3_TextEditor_Claude;
    except on E: Exception do WriteLn('  [Demo 3 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 3 skipped (CLAUDE_API_KEY not configured) ---');

  if TieneClaude then
  begin
    try Demo4_Combinado;
    except on E: Exception do WriteLn('  [Demo 4 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else WriteLn(#13#10'--- Demo 4 skipped (CLAUDE_API_KEY not configured) ---');

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demos completed.');
  WriteLn('  See cap18-herramientas-sistema.md for the complete documentation.');
  WriteLn(StringOfChar('=', 62));
end;

// =============================================================================
begin
  try
    with TSistemaDemo.Create do
    try
      Run;
    finally
      Free;
    end;
  except
    on E: Exception do
      WriteLn('FATAL ERROR: ', E.ClassName, ' -- ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
