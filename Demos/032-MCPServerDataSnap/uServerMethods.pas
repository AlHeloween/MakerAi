unit uServerMethods;

interface

uses System.SysUtils, System.Classes, System.Json, System.IOUtils,
  Datasnap.DSServer, Datasnap.DSAuth, uMakerAi.MCPServer.Core,
  uMakerAi.MCPServer.Direct, Datasnap.DSSession;

type
{$METHODINFO ON}
  TSSE = class(TDataModule)
    MCPDirect: TAiMCPDirectConnection;
    procedure DataModuleDestroy(Sender: TObject);
    procedure DataModuleCreate(Sender: TObject);
  private
    Procedure InitMCP;
  public
    { Public declarations }
    function EchoString(Value: string): string;
    function ReverseString(Value: string): string;
    function ListTools: TJSONObject;
    function CallTool(ToolName: string; Args: TJSONObject): TJSONObject;
  end;
{$METHODINFO OFF}

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}

uses System.StrUtils, uTool.Datasnap.FileAccess;

procedure TSSE.DataModuleCreate(Sender: TObject);
begin
  InitMCP;
end;

procedure TSSE.DataModuleDestroy(Sender: TObject);
begin
  MCPDirect.Stop;
end;

function TSSE.EchoString(Value: string): string;
begin
  Result := Value;
end;

function TSSE.ReverseString(Value: string): string;
begin
  Result := System.StrUtils.ReverseString(Value);
end;

procedure TSSE.InitMCP;
var
  UserConfig: TFileAccessConfig;
begin

  // 1. Configurar Usuario (Contexto de Seguridad)
  // DataSnap gives us the current session info
  if TDSSessionManager.GetThreadSession <> nil then
    MCPDirect.User := TDSSessionManager.GetThreadSession.UserName;

  // 1. Create custom configuration for this user
  UserConfig := TFileAccessConfig.Create;

  // Limpiar defaults si quieres ser estricto
  UserConfig.ClearPermissions;

  // Agregar carpeta privada del usuario
  UserConfig.AddAllowedPath('C:\Users\' + TDSSessionManager.GetThreadSession.UserName);
  UserConfig.AddAllowedPath('C:\Empresa\DocumentosPublicos');
  UserConfig.AddAllowedPath(TPath.GetTempPath);

  // Agregar extensiones permitidas
  UserConfig.AddAllowedExtension('.txt');
  UserConfig.AddAllowedExtension('.pdf');

  // 2. Register tools passing them THIS configuration
  // Note: The tools will use this config but will NOT release it (FOwnsConfig=False)
  // We must make sure the configuration lives as long as the tools.
  // Since the tools and the DataModule die together at the end of the session,
  // we can let UserConfig be released in DataModuleDestroy or use an interface for reference counting.

  // TRICK: To simplify memory management without interfaces, we can make
  // the FIRST tool the owner of the config, or register them manually.

  MCPDirect.RegisterTool('list_files',
    function: IAiMCPTool
    begin
      Result := TListFilesTool.Create(UserConfig);
    end);

  // 3. Arrancar
  MCPDirect.Start;
end;

function TSSE.CallTool(ToolName: string; Args: TJSONObject): TJSONObject;
var
  ArgsClone: TJSONObject;
begin
  // Remembering the ownership topic: we clone so that McpDirect owns its copy
  if Assigned(Args) then
    ArgsClone := Args.Clone as TJSONObject
  else
    ArgsClone := TJSONObject.Create;

  try
    Result := MCPDirect.CallTool(ToolName, ArgsClone);
  except
    ArgsClone.Free;
    raise;
  end;
end;

function TSSE.ListTools: TJSONObject;
begin
  Result := MCPDirect.ListTools;
end;

end.
