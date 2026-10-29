// MIT License
//
// Copyright (c) 2013 Gustavo Enríquez - CimaMaker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// o use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// HE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
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
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uTool.FileAccess;

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON;

type
  // =============================================================================
  // TOOL FOR LISTING FILES
  // =============================================================================
  TListFilesParams = class
  private
    FPath: string;
    FPattern: string;
    FIncludeSubdirs: Boolean;
    FShowDetails: Boolean;
  public
    [AiMCPSchemaDescription('Path of the folder to list')]
    property Path: string read FPath write FPath;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Search pattern (e.g.: "*.pas", "*.txt") - default: "*.*"')]
    property Pattern: string read FPattern write FPattern;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Include subdirectories (default: false)')]
    property IncludeSubdirs: Boolean read FIncludeSubdirs write FIncludeSubdirs;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Show details (size, date) - default: false)')]
    property ShowDetails: Boolean read FShowDetails write FShowDetails;
  end;

  TListFilesTool = class(TAiMCPToolBase<TListFilesParams>)
  private
    class var FAllowedPaths: TList<string>;
    class var FAllowedExtensions: TList<string>;
    class function IsPathAllowed(const APath: string): Boolean;
    class function IsExtensionAllowed(const AFilePath: string): Boolean;
    class function NormalizePath(const APath: string): string;
  protected
    // CHANGE: The function now returns TJSONObject
    function ExecuteWithParams(const AParams: TListFilesParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; Override;
    class constructor Create;
    class destructor Destroy;
    class procedure AddAllowedPath(const APath: string);
    class procedure AddAllowedExtension(const AExtension: string);
    class procedure ClearAllowedPathsAndExtensions;
    class procedure SetDefaultConfiguration;
  end;

  // =============================================================================
  // TOOL FOR READING FILES
  // =============================================================================
  TReadFileParams = class
    // ... (no changes)
  private
    FFilePath: string;
  public
    [AiMCPSchemaDescription('Full path of the file to read')]
    property FilePath: string read FFilePath write FFilePath;
  end;

  TReadFileTool = class(TAiMCPToolBase<TReadFileParams>)
  private const
    MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB
  protected
    // CHANGE: The function now returns TJSONObject
    function ExecuteWithParams(const AParams: TReadFileParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; Override;
  end;

  // =============================================================================
  // TOOL FOR WRITING FILES
  // =============================================================================
  TWriteFileParams = class
    // ... (no changes)
  private
    FFilePath: string;
    FContent: string;
    FAppend: Boolean;
    FCreateDirs: Boolean;
  public
    [AiMCPSchemaDescription('Full path of the file to write')]
    property FilePath: string read FFilePath write FFilePath;
    [AiMCPSchemaDescription('Content to write in the file')]
    property Content: string read FContent write FContent;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Append to the end of the file (default: false = overwrite)')]
    property Append: Boolean read FAppend write FAppend;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Create directories if they do not exist (default: true)')]
    property CreateDirs: Boolean read FCreateDirs write FCreateDirs;
  end;

  TWriteFileTool = class(TAiMCPToolBase<TWriteFileParams>)
  protected
    // CHANGE: The function now returns TJSONObject
    function ExecuteWithParams(const AParams: TWriteFileParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; Override;
  end;

procedure RegisterTools(ALogicServer: TAiMCPServer);

implementation

uses
  System.StrUtils;

{ TListFilesTool }

// ... (RegisterTools and the configuration methods of TListFilesTool do not change)
procedure RegisterTools(ALogicServer: TAiMCPServer);
begin
  if not Assigned(ALogicServer) then
    raise Exception.Create('LogicServer no puede ser nulo para registrar herramientas.');
  ALogicServer.RegisterTool('list_files', function: IAiMCPTool begin Result := TListFilesTool.Create; end);
  ALogicServer.RegisterTool('read_file', function: IAiMCPTool begin Result := TReadFileTool.Create; end);
  ALogicServer.RegisterTool('write_file', function: IAiMCPTool begin Result := TWriteFileTool.Create; end);
end;

class constructor TListFilesTool.Create;
begin
  FAllowedPaths := TList<string>.Create;
  FAllowedExtensions := TList<string>.Create;
  SetDefaultConfiguration;
end;

class destructor TListFilesTool.Destroy;
begin
  FAllowedPaths.Free;
  FAllowedExtensions.Free;
end;

constructor TListFilesTool.Create;
begin
  inherited;
  FName := 'list_files';
  FDescription := 'Lists files in allowed folders with security filters';
end;

class procedure TListFilesTool.SetDefaultConfiguration;
begin
  ClearAllowedPathsAndExtensions;
  AddAllowedPath(TPath.GetTempPath);
  AddAllowedPath(TPath.GetDocumentsPath);
  AddAllowedPath(ExtractFilePath(ParamStr(0)));
  AddAllowedExtension('.txt');
  AddAllowedExtension('.json');
  AddAllowedExtension('.xml');
  AddAllowedExtension('.csv');
  AddAllowedExtension('.log');
  AddAllowedExtension('.md');
  // For security, we do not add executable or system extensions.
  // We also add common image, document and audio extensions so that `read_file` can return them.
  AddAllowedExtension('.png');
  AddAllowedExtension('.jpg');
  AddAllowedExtension('.jpeg');
  AddAllowedExtension('.gif');
  AddAllowedExtension('.bmp');
  AddAllowedExtension('.pdf');
  AddAllowedExtension('.docx');
  AddAllowedExtension('.xlsx');
  AddAllowedExtension('.mp3');
  AddAllowedExtension('.wav');
end;

class procedure TListFilesTool.AddAllowedPath(const APath: string);
var
  NormalizedPath: string;
begin
  if not TDirectory.Exists(APath) then
    Exit;
  NormalizedPath := NormalizePath(APath);
  if FAllowedPaths.IndexOf(NormalizedPath) = -1 then
    FAllowedPaths.Add(NormalizedPath);
end;

class procedure TListFilesTool.AddAllowedExtension(const AExtension: string);
var
  Ext: string;
begin
  Ext := Trim(LowerCase(AExtension));
  if not Ext.StartsWith('.') then
    Ext := '.' + Ext;
  if FAllowedExtensions.IndexOf(Ext) = -1 then
    FAllowedExtensions.Add(Ext);
end;

class procedure TListFilesTool.ClearAllowedPathsAndExtensions;
begin
  FAllowedPaths.Clear;
  FAllowedExtensions.Clear;
end;

class function TListFilesTool.NormalizePath(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetFullPath(APath));
end;

class function TListFilesTool.IsPathAllowed(const APath: string): Boolean;
var
  NormalizedRequestPath, AllowedPath: string;
begin
  Result := False;
  NormalizedRequestPath := NormalizePath(APath);
  for AllowedPath in FAllowedPaths do
  begin
    if SameText(NormalizedRequestPath, AllowedPath) or NormalizedRequestPath.StartsWith(AllowedPath) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TListFilesTool.IsExtensionAllowed(const AFilePath: string): Boolean;
var
  Ext: string;
begin
  if FAllowedExtensions.Count = 0 then
    Exit(True);
  Ext := LowerCase(TPath.GetExtension(AFilePath));
  Result := FAllowedExtensions.IndexOf(Ext) > -1;
end;


// The function returns a structured TJSONObject.
function TListFilesTool.ExecuteWithParams(const AParams: TListFilesParams; const AuthContext: TAiAuthContext): TJSONObject;
var
  SearchPattern: string;
  Files: TStringDynArray;
  FilePath: string;
  ResultObject: TJSONObject;
  FilesArray: TJSONArray;
  FileObject: TJSONObject;
  FileInfo: TSearchRec;
begin
  try
    if not TDirectory.Exists(AParams.Path) then
      raise Exception.Create('The folder does not exist: ' + AParams.Path);

    if not IsPathAllowed(AParams.Path) then
      raise Exception.Create('Access denied to the folder: ' + AParams.Path);

    SearchPattern := AParams.Pattern;
    if SearchPattern.IsEmpty then
      SearchPattern := '*.*';

    if AParams.IncludeSubdirs then
      Files := TDirectory.GetFiles(AParams.Path, SearchPattern, TSearchOption.soAllDirectories)
    else
      Files := TDirectory.GetFiles(AParams.Path, SearchPattern, TSearchOption.soTopDirectoryOnly);

    ResultObject := TJSONObject.Create;
    FilesArray := TJSONArray.Create;
    ResultObject.AddPair('files', FilesArray);

    for FilePath in Files do
    begin
      if IsExtensionAllowed(FilePath) then
      begin
        FileObject := TJSONObject.Create;
        FileObject.AddPair('path', FilePath);
        FileObject.AddPair('name', TPath.GetFileName(FilePath));

        if AParams.ShowDetails then
        begin
          if FindFirst(FilePath, faAnyFile, FileInfo) = 0 then
          try
            FileObject.AddPair('size', TJSONNumber.Create(FileInfo.Size));
            FileObject.AddPair('modified', TJSONString.Create(FormatDateTime('c', FileInfo.TimeStamp)));
          finally
            FindClose(FileInfo);
          end;
        end;
        FilesArray.AddElement(FileObject);
      end;
    end;

    ResultObject.AddPair('count', TJSONNumber.Create(Int64(FilesArray.Count)));
    ResultObject.AddPair('message', Format('%d files found in "%s".', [FilesArray.Count, AParams.Path]));

    // We return the JSON of the file list inside the "content" response format
    Result := TAiMCPResponseBuilder.New.AddText(ResultObject.ToJSON).Build;
    ResultObject.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('❌ Error listing files: ' + E.Message).Build;
  end;
end;

{ TReadFileTool }

constructor TReadFileTool.Create;
begin
  inherited;
  FName := 'read_file';
  FDescription := 'Reads and returns the content of a file (text or binary) with security restrictions.';
end;

// CHANGE: The function now returns the file using the builder.
function TReadFileTool.ExecuteWithParams(const AParams: TReadFileParams; const AuthContext: TAiAuthContext): TJSONObject;
var
  FileSize: Int64;
  FS: TFileStream;
begin
  try
    if not TFile.Exists(AParams.FilePath) then
      raise Exception.Create('The file does not exist: ' + AParams.FilePath);

    if not TListFilesTool.IsPathAllowed(ExtractFileDir(AParams.FilePath)) then
      raise Exception.Create('Access denied to the file path.');

    if not TListFilesTool.IsExtensionAllowed(AParams.FilePath) then
      raise Exception.Create('File type not allowed for reading: ' + TPath.GetExtension(AParams.FilePath));

    FS := TFileStream.Create(AParams.FilePath, fmOpenRead or fmShareDenyNone);
    try
      FileSize := FS.Size;
    finally
      FS.Free;
    end;
    if FileSize > MAX_FILE_SIZE then
      raise Exception.CreateFmt('File too large: %d bytes (maximum allowed: %d bytes)', [FileSize, MAX_FILE_SIZE]);

    // We use the builder to return the file. It handles everything.
    Result := TAiMCPResponseBuilder.New
      .AddFile(AParams.FilePath)
      .Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('❌ Error reading file: ' + E.Message).Build;
  end;
end;

{ TWriteFileTool }

constructor TWriteFileTool.Create;
begin
  inherited;
  FName := 'write_file';
  FDescription := 'Writes or appends content to text files with security restrictions.';
end;

// CHANGE: The function now returns a simple confirmation JSON.
function TWriteFileTool.ExecuteWithParams(const AParams: TWriteFileParams; const AuthContext: TAiAuthContext): TJSONObject;
var
  FileDir: string;
  CreateDirs: Boolean;
begin
  try
    FileDir := ExtractFileDir(AParams.FilePath);

    if not TListFilesTool.IsPathAllowed(FileDir) then
      raise Exception.Create('Access denied for writing to: ' + FileDir);

    if not TListFilesTool.IsExtensionAllowed(AParams.FilePath) then
      raise Exception.Create('File type not allowed for writing: ' + TPath.GetExtension(AParams.FilePath));

    CreateDirs := AParams.CreateDirs;
    if CreateDirs and not TDirectory.Exists(FileDir) then
      TDirectory.CreateDirectory(FileDir);

    if AParams.Append then
      TFile.AppendAllText(AParams.FilePath, AParams.Content, TEncoding.UTF8)
    else
      TFile.WriteAllText(AParams.FilePath, AParams.Content, TEncoding.UTF8);

    Result := TAiMCPResponseBuilder.New
      .AddText(Format('✅ File saved successfully at: %s', [AParams.FilePath]))
      .Build;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('❌ Error writing file: ' + E.Message).Build;
  end;
end;

end.
