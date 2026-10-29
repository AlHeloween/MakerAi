// MIT License
//
// Copyright (c) 2013 Gustavo Enriquez - CimaMaker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

{
  -------------------------------------------------------------------------------
  TAiTextEditorTool - Text Editing Component for AI
  -------------------------------------------------------------------------------

  WARNING ABOUT OPERATION MODE:

  This component is designed with an event system to virtualize input and
  output (I/O).

  1. DEFAULT MODE (Disk Access):
  If the events (OnLoadFile, OnSaveFile, etc.) are NOT assigned or if the
  "Handled" parameter is left as False, the component will execute operations
  directly on the PHYSICAL FILE SYSTEM of the operating system.

  2. INTERCEPTED MODE (Memory/UI/DB):
  To avoid disk access (e.g., to edit a TMemo or a database record),
  the programmer must assign the corresponding events, perform custom logic,
  and explicitly set:
  Handled := True;

  This stops the execution of the default file logic.
  -------------------------------------------------------------------------------
}

unit uMakerAi.Tools.TextEditor;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.StrUtils, uMakerAi.Utils.DiffUpdater, System.Generics.Collections;

type

  // Event to read content (e.g., from DB or Memory)
  TAiFileReadEvent = procedure(Sender: TObject; const Path: string; var Content: string; var Handled: Boolean) of object;
  // Event to write content
  TAiFileWriteEvent = procedure(Sender: TObject; const Path: string; const Content: string; var Handled: Boolean) of object;
  // Event to check existence
  TAiFileCheckEvent = procedure(Sender: TObject; const Path: string; var Exists: Boolean; var Handled: Boolean) of object;
  // Event for directory management
  TAiDirEvent = procedure(Sender: TObject; const Path: string; var Handled: Boolean) of object;
  // Generic event before executing a command (allows total override of logic)
  TAiCommandEvent = procedure(Sender: TObject; const Command, Path: string; Args: TJSONObject; var Result: string; var Handled: Boolean) of object;

  TAiTextEditorTool = class(TComponent)
  private
    FOnLoadFile: TAiFileReadEvent;
    FOnSaveFile: TAiFileWriteEvent;
    FOnFileExists: TAiFileCheckEvent;
    FOnEnsureDirectory: TAiDirEvent;
    FOnBeforeCommand: TAiCommandEvent;

    function CountOccurrences(const Text, SubText: string): Integer;
  protected
    // --- Virtual methods with Event support ---
    function LoadFileContent(const Path: string): string; virtual;
    procedure SaveFileContent(const Path: string; const Content: string); virtual;
    function FileExists(const Path: string): Boolean; virtual;
    function EnsureDirectory(const Path: string): Boolean; virtual;
    function ValidatePath(const APath: string): Boolean; virtual;

    // --- Specific commands ---
    function Cmd_View(const Path: string; const jArgs: TJSONObject): string; virtual;
    function Cmd_Create(const Path: string; const jArgs: TJSONObject): string; virtual;
    function Cmd_StrReplace(const Path: string; const jArgs: TJSONObject): string; virtual;
    function Cmd_Insert(const Path: string; const jArgs: TJSONObject): string; virtual;
    function Cmd_ApplyDiff(const Path: string; const jArgs: TJSONObject): string; virtual;

  public
    // Executes the tool receiving a JSON string
    function Execute(const JsonArguments: string): string; virtual;

  published
    // --- Published Events ---
    property OnLoadFile: TAiFileReadEvent read FOnLoadFile write FOnLoadFile;
    property OnSaveFile: TAiFileWriteEvent read FOnSaveFile write FOnSaveFile;
    property OnFileExists: TAiFileCheckEvent read FOnFileExists write FOnFileExists;
    property OnEnsureDirectory: TAiDirEvent read FOnEnsureDirectory write FOnEnsureDirectory;
    property OnBeforeCommand: TAiCommandEvent read FOnBeforeCommand write FOnBeforeCommand;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiTextEditorTool]);
end;

{ TAiTextEditorTool }

function TAiTextEditorTool.Execute(const JsonArguments: string): string;
var
  jVal: TJSONValue;
  jArgs: TJSONObject;
  Cmd, Path: string;
  Handled: Boolean;
begin
  jVal := TJSONObject.ParseJSONValue(JsonArguments);
  if not (jVal is TJSONObject) then
  begin
    jVal.Free;
    Exit('Error: Invalid arguments (malformed JSON).');
  end;

  jArgs := TJSONObject(jVal);
  try
    try
      // 1. Extract common parameters
      Cmd := jArgs.GetValue<string>('command');
      Path := jArgs.GetValue<string>('path');

      // Event: Allow user to fully intercept the command
      Handled := False;
      if Assigned(FOnBeforeCommand) then
        FOnBeforeCommand(Self, Cmd, Path, jArgs, Result, Handled);

      if Handled then
        Exit; // The user already generated the Result

      // 2. Validate path (basic security)
      if not ValidatePath(Path) then
        Exit('Error: Invalid or empty path.');

      if (Cmd <> 'create') and (not FileExists(Path)) then
        Exit('Error: File does not exist at path: ' + Path);

      // 3. Dispatch command
      if Cmd = 'view' then
        Result := Cmd_View(Path, jArgs)
      else if Cmd = 'create' then
        Result := Cmd_Create(Path, jArgs)
      else if Cmd = 'str_replace' then
        Result := Cmd_StrReplace(Path, jArgs)
      else if Cmd = 'insert' then
        Result := Cmd_Insert(Path, jArgs)
      else if Cmd = 'apply_diff' then
        Result := Cmd_ApplyDiff(Path, jArgs)
      else
        Result := 'Error: Unknown command "' + Cmd + '"';

    except
      on E: Exception do
        Result := 'Error executing editor (' + Cmd + '): ' + E.Message;
    end;
  finally
    jArgs.Free;
  end;
end;

// --- I/O implementation with Events ---

function TAiTextEditorTool.LoadFileContent(const Path: string): string;
var
  Handled: Boolean;
begin
  Handled := False;
  Result := '';
  // 1. Try event
  if Assigned(FOnLoadFile) then
    FOnLoadFile(Self, Path, Result, Handled);

  // 2. If not handled, use disk
  if not Handled then
  begin
    if TFile.Exists(Path) then
      Result := TFile.ReadAllText(Path, TEncoding.UTF8)
    else
      raise EFileNotFoundException.Create('File not found: ' + Path);
  end;
end;

procedure TAiTextEditorTool.SaveFileContent(const Path: string; const Content: string);
var
  Handled: Boolean;
begin
  Handled := False;
  // 1. Try event
  if Assigned(FOnSaveFile) then
    FOnSaveFile(Self, Path, Content, Handled);

  // 2. If not handled, write to disk
  if not Handled then
    TFile.WriteAllText(Path, Content, TEncoding.UTF8);
end;

function TAiTextEditorTool.FileExists(const Path: string): Boolean;
var
  Handled: Boolean;
begin
  Handled := False;
  Result := False;
  // 1. Try event
  if Assigned(FOnFileExists) then
    FOnFileExists(Self, Path, Result, Handled);

  // 2. If not handled, check disk
  if not Handled then
    Result := TFile.Exists(Path);
end;

function TAiTextEditorTool.EnsureDirectory(const Path: string): Boolean;
var
  Handled: Boolean;
  Dir: string;
begin
  Handled := False;
  Result := True; // Assume success by default

  // 1. Try event
  if Assigned(FOnEnsureDirectory) then
    FOnEnsureDirectory(Self, Path, Handled);

  // 2. If not handled, create on disk
  if not Handled then
  begin
    Dir := TPath.GetDirectoryName(Path);
    if (Dir <> '') and (not TDirectory.Exists(Dir)) then
    begin
      try
        TDirectory.CreateDirectory(Dir);
      except
        Result := False;
      end;
    end;
  end;
end;

function TAiTextEditorTool.ValidatePath(const APath: string): Boolean;
begin
  // Basic validation. Can be overridden for more complex security logic.
  Result := Trim(APath) <> '';
end;

function TAiTextEditorTool.CountOccurrences(const Text, SubText: string): Integer;
var
  P, Offset: Integer;
begin
  Result := 0;
  if (Text = '') or (SubText = '') then
    Exit;

  Offset := 1;
  P := Pos(SubText, Text, Offset);
  while P > 0 do
  begin
    Inc(Result);
    Offset := P + Length(SubText);
    P := Pos(SubText, Text, Offset);
  end;
end;

// --- Specific commands ---

function TAiTextEditorTool.Cmd_View(const Path: string; const jArgs: TJSONObject): string;
var
  FullText: string;
  Lines: TStringList;
  ViewRange: TJSonArray;
  StartL, EndL, i: Integer;
  ResBuilder: TStringBuilder;
begin
  FullText := LoadFileContent(Path);
  Lines := TStringList.Create;
  try
    Lines.Text := FullText; // TStringList handles line breaks automatically

    // Check if a range [start_line, end_line] is requested
    if jArgs.TryGetValue<TJSonArray>('view_range', ViewRange) and (ViewRange.Count = 2) then
    begin
      StartL := ViewRange.Items[0].GetValue<Integer> - 1; // Claude uses base 1 -> TStringList base 0
      EndL := ViewRange.Items[1].GetValue<Integer> - 1;

      if StartL < 0 then
        StartL := 0;
      if EndL >= Lines.Count then
        EndL := Lines.Count - 1;

      if StartL > EndL then
        Exit('Error: Invalid view range (Start > End) or out of bounds.');

      ResBuilder := TStringBuilder.Create;
      try
        for i := StartL to EndL do
          ResBuilder.AppendLine(Lines[i]);
        Result := ResBuilder.ToString;
      finally
        ResBuilder.Free;
      end;
    end
    else
    begin
      // View entire file
      Result := FullText;
    end;
  finally
    Lines.Free;
  end;
end;

function TAiTextEditorTool.Cmd_Create(const Path: string; const jArgs: TJSONObject): string;
var
  Content: string;
begin
  if FileExists(Path) then
    Exit('Error: File already exists. Use "str_replace" or "insert" to modify it.');

  Content := jArgs.GetValue<string>('file_text', '');

  if not EnsureDirectory(Path) then
    Exit('Error: Could not create directory for the file.');

  SaveFileContent(Path, Content);
  Result := 'File created successfully.';
end;

function TAiTextEditorTool.Cmd_StrReplace(const Path: string; const jArgs: TJSONObject): string;
var
  OldStr, NewStr, FileContent: string;
  Occurrences: Integer;
begin
  OldStr := jArgs.GetValue<string>('old_str');
  NewStr := jArgs.GetValue<string>('new_str');

  // Load content (triggers OnLoadFile -> reads from Memo)
  FileContent := LoadFileContent(Path);

  // 1. Validation according to DOCS: Exact count
  Occurrences := CountOccurrences(FileContent, OldStr);

  if Occurrences = 0 then
    // Official message from documentation for "No matches"
    Exit('Error: No match found for replacement. Please check your text and try again.')
  else if Occurrences > 1 then
    // Official message from documentation for "Multiple matches"
    Exit('Error: Found ' + IntToStr(Occurrences) + ' matches for replacement text. Please provide more context to make a unique match.');

  // 2. Execution: Replacement in memory
  FileContent := StringReplace(FileContent, OldStr, NewStr, []);

  // 3. PERSISTENCE: Triggers OnSaveFile -> Updates the Memo
  SaveFileContent(Path, FileContent);

  // Standard success response
  Result := 'Successfully replaced text at exactly one location.';
end;

function TAiTextEditorTool.Cmd_Insert(const Path: string; const jArgs: TJSONObject): string;
var
  NewStr, FileContent: string;
  InsertLine: Integer;
  Lines: TStringList;
begin
  // Try to read 'insert_text' first, if not present try 'new_str'
  if not jArgs.TryGetValue<string>('insert_text', NewStr) then
    if not jArgs.TryGetValue<string>('new_str', NewStr) then
      Exit('Error: No insert text provided.');

  // Claude sends the line after which to insert (base 0 or 1 depending on model, usually 0 is start)
  InsertLine := jArgs.GetValue<Integer>('insert_line');

  FileContent := LoadFileContent(Path);
  Lines := TStringList.Create;
  try
    Lines.Text := FileContent;

    // Security validation to avoid crashes
    if (InsertLine < 0) or (InsertLine > Lines.Count) then
      Exit('Error: Line number ' + IntToStr(InsertLine) + ' out of range.');

    if InsertLine = 0 then
      Lines.Insert(0, NewStr)
    else if InsertLine >= Lines.Count then
      Lines.Add(NewStr)
    else
      Lines.Insert(InsertLine, NewStr);

    SaveFileContent(Path, Lines.Text);
    Result := 'Text inserted successfully.';
  finally
    Lines.Free;
  end;
end;

function TAiTextEditorTool.Cmd_ApplyDiff(const Path: string; const jArgs: TJSONObject): string;
var
  DiffText, OriginalContent, NewContent, ErrorMsg: string;
  Applier: TDiffApplier;
begin
  DiffText := jArgs.GetValue<string>('diff_text');
  if DiffText = '' then
    Exit('Error: "diff_text" cannot be empty.');

  OriginalContent := LoadFileContent(Path);

  Applier := TDiffApplier.Create;
  try
    if Applier.Apply(OriginalContent, DiffText, NewContent, ErrorMsg) then
    begin
      SaveFileContent(Path, NewContent);
      Result := 'Diff applied successfully.';
    end
    else
      Result := 'Error applying diff: ' + ErrorMsg;
  finally
    Applier.Free;
  end;
end;

end.
