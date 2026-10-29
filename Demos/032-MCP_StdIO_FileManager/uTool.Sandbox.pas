unit uTool.Sandbox;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  uMakerAi.MCPServer.Core; // Tu núcleo MCP

const
  // Root folder that will control the AI.
  SANDBOX_ROOT = 'd:\taller\mcpdir';

type
  // ===========================================================================
  // Arguments (DTOs) for the tools
  // ===========================================================================

  // Arguments for List and Read (They only require a path)
  TPathArgs = class
  private
    FPath: string;
  public
    [AiMCPSchemaDescription('Relative path of the file or folder (e.g.: "notes/list.txt" or "." for the root)')]
    property Path: string read FPath write FPath;
  end;

  // Arguments for Write (Path + Content)
  TWriteArgs = class
  private
    FPath: string;
    FContent: string;
  public
    [AiMCPSchemaDescription('Relative path where to save the file')]
    property Path: string read FPath write FPath;
    [AiMCPSchemaDescription('Text content to save in the file')]
    property Content: string read FContent write FContent;
  end;

  // Arguments for Copy (Source + Destination)
  TCopyArgs = class
  private
    FSource: string;
    FDestination: string;
  public
    [AiMCPSchemaDescription('Relative path of the source file')]
    property Source: string read FSource write FSource;
    [AiMCPSchemaDescription('Relative path of the new destination')]
    property Destination: string read FDestination write FDestination;
  end;

  // ===========================================================================
  // Tool Classes
  // ===========================================================================

  TListFilesTool = class(TAiMCPToolBase<TPathArgs>)
  protected
    function ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TReadTool = class(TAiMCPToolBase<TPathArgs>)
  protected
    function ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TWriteTool = class(TAiMCPToolBase<TWriteArgs>)
  protected
    function ExecuteWithParams(const AParams: TWriteArgs; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TDeleteTool = class(TAiMCPToolBase<TPathArgs>)
  protected
    function ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TCopyTool = class(TAiMCPToolBase<TCopyArgs>)
  protected
    function ExecuteWithParams(const AParams: TCopyArgs; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

// Procedure to register everything at once
procedure RegisterSandboxTools(ALogicServer: TAiMCPServer);

implementation

// =============================================================================
// Security Helpers (Sandboxing)
// =============================================================================

procedure EnsureSandboxExists;
begin
  if not TDirectory.Exists(SANDBOX_ROOT) then
    TDirectory.CreateDirectory(SANDBOX_ROOT);
end;

// Converts a relative path into an absolute one and checks that it is inside ROOT
function ResolvePath(const ARelativePath: string): string;
var
  LFullPath: string;
  LCleanRel: string;
begin
  // Normalize input
  if (ARelativePath = '') or (ARelativePath = '.') then
    LCleanRel := ''
  else
    LCleanRel := ARelativePath;

  // Build absolute path
  LFullPath := TPath.GetFullPath(TPath.Combine(SANDBOX_ROOT, LCleanRel));

  // Check security (Avoid Path Traversal: "..\..\windows")
  if not LFullPath.StartsWith(SANDBOX_ROOT, True) then
    raise Exception.CreateFmt('SECURITY: Access denied. The path "%s" is outside the sandbox.', [ARelativePath]);

  Result := LFullPath;
end;

// =============================================================================
// Tool Registration
// =============================================================================

procedure RegisterSandboxTools(ALogicServer: TAiMCPServer);
begin
  EnsureSandboxExists;

  ALogicServer.RegisterTool('fs_list', function: IAiMCPTool begin Result := TListFilesTool.Create; end);
  ALogicServer.RegisterTool('fs_read', function: IAiMCPTool begin Result := TReadTool.Create; end);
  ALogicServer.RegisterTool('fs_write', function: IAiMCPTool begin Result := TWriteTool.Create; end);
  ALogicServer.RegisterTool('fs_delete', function: IAiMCPTool begin Result := TDeleteTool.Create; end);
  ALogicServer.RegisterTool('fs_copy', function: IAiMCPTool begin Result := TCopyTool.Create; end);
end;

// =============================================================================
// Implementation: List Files
// =============================================================================

constructor TListFilesTool.Create;
begin
  inherited;
  FName := 'fs_list';
  FDescription := 'Lists the files and folders inside the working directory.';
end;

function TListFilesTool.ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject;
var
  LPath: string;
  LFiles, LDirs: TStringDynArray;
  LItem: string;
  LList: TStringBuilder;
begin
  try
    LPath := ResolvePath(AParams.Path);

    if not TDirectory.Exists(LPath) then
      Exit(TAiMCPResponseBuilder.New.AddText('Error: The directory does not exist.').Build);

    LList := TStringBuilder.Create;
    try
      LList.AppendLine('Contents of: ' + AParams.Path);
      LList.AppendLine('-----------------------------------');

      LDirs := TDirectory.GetDirectories(LPath);
      for LItem in LDirs do
        LList.AppendLine('[DIR]  ' + TPath.GetFileName(LItem));

      LFiles := TDirectory.GetFiles(LPath);
      for LItem in LFiles do
        LList.AppendLine('[FILE] ' + TPath.GetFileName(LItem));

      Result := TAiMCPResponseBuilder.New.AddText(LList.ToString).Build;
    finally
      LList.Free;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('Error listing: ' + E.Message).Build;
  end;
end;

// =============================================================================
// Implementation: Read File
// =============================================================================

constructor TReadTool.Create;
begin
  inherited;
  FName := 'fs_read';
  FDescription := 'Reads the content of a text file.';
end;

function TReadTool.ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject;
var
  LPath: string;
begin
  try
    LPath := ResolvePath(AParams.Path);
    if not TFile.Exists(LPath) then
      raise Exception.Create('File not found.');

    // We use the Core helper that already handles streams or text
    Result := TAiMCPResponseBuilder.New.AddFile(LPath).Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('Error reading file: ' + E.Message).Build;
  end;
end;

// =============================================================================
// Implementation: Write File
// =============================================================================

constructor TWriteTool.Create;
begin
  inherited;
  FName := 'fs_write';
  FDescription := 'Creates a new file or overwrites an existing one with the provided content.';
end;

function TWriteTool.ExecuteWithParams(const AParams: TWriteArgs; const AuthContext: TAiAuthContext): TJSONObject;
var
  LPath: string;
begin
  try
    LPath := ResolvePath(AParams.Path);
    // Ensure the parent folder exists
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LPath));

    TFile.WriteAllText(LPath, AParams.Content, TEncoding.UTF8);

    Result := TAiMCPResponseBuilder.New.AddText('✅ File saved successfully: ' + AParams.Path).Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('Error writing file: ' + E.Message).Build;
  end;
end;

// =============================================================================
// Implementation: Delete File
// =============================================================================

constructor TDeleteTool.Create;
begin
  inherited;
  FName := 'fs_delete';
  FDescription := 'Permanently deletes a file.';
end;

function TDeleteTool.ExecuteWithParams(const AParams: TPathArgs; const AuthContext: TAiAuthContext): TJSONObject;
var
  LPath: string;
begin
  try
    LPath := ResolvePath(AParams.Path);
    if TFile.Exists(LPath) then
    begin
      TFile.Delete(LPath);
      Result := TAiMCPResponseBuilder.New.AddText('🗑️ File deleted: ' + AParams.Path).Build;
    end
    else if TDirectory.Exists(LPath) then
    begin
       // Optional: Allow deleting folders
       TDirectory.Delete(LPath, True);
       Result := TAiMCPResponseBuilder.New.AddText('🗑️ Folder deleted: ' + AParams.Path).Build;
    end
    else
      Result := TAiMCPResponseBuilder.New.AddText('The file does not exist.').Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('Error deleting: ' + E.Message).Build;
  end;
end;

// =============================================================================
// Implementation: Copy File
// =============================================================================

constructor TCopyTool.Create;
begin
  inherited;
  FName := 'fs_copy';
  FDescription := 'Copies a file from one location to another.';
end;

function TCopyTool.ExecuteWithParams(const AParams: TCopyArgs; const AuthContext: TAiAuthContext): TJSONObject;
var
  LSrc, LDst: string;
begin
  try
    LSrc := ResolvePath(AParams.Source);
    LDst := ResolvePath(AParams.Destination);

    if not TFile.Exists(LSrc) then
      raise Exception.Create('Source file not found.');

    // Ensure destination directory
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LDst));

    TFile.Copy(LSrc, LDst, True); // True = Overwrite
    Result := TAiMCPResponseBuilder.New.AddText(Format('✅ Copied from "%s" to "%s"', [AParams.Source, AParams.Destination])).Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('Error copying: ' + E.Message).Build;
  end;
end;

end.
