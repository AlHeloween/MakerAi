// MIT License
//
// Copyright (c) <year> <copyright holders>
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


unit uMakerAi.Utils.CodeExtractor;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  // Record to store extracted file information
  TCodeFile = record
    FileName : String;
    FileType: string;
    Code: string;
    LineNumber: Integer; // line where the block was found
  end;

  // List of code files
  TCodeFileList = TList<TCodeFile>;

  // Main class to extract code files
  TMarkdownCodeExtractor = class
  private
    FCodeFiles: TCodeFileList;
    function NormalizeLanguage(const ALanguage: string): string;
    function TryParseFenceOpen(const ALine: string; out ALanguage, AFileName: string): Boolean;
    function IsFenceClose(const ALine: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Main method to extract code files from markdown text
    function ExtractCodeFiles(const AMarkdownText: string): TCodeFileList;

    // Method to clean the file list
    procedure Clear;

    // Property to access the extracted files
    property CodeFiles: TCodeFileList read FCodeFiles;
  end;

implementation

{ TMarkdownCodeExtractor }

constructor TMarkdownCodeExtractor.Create;
begin
  inherited Create;
  FCodeFiles := TCodeFileList.Create;
end;

destructor TMarkdownCodeExtractor.Destroy;
begin
  FCodeFiles.Free;
  inherited Destroy;
end;

procedure TMarkdownCodeExtractor.Clear;
begin
  FCodeFiles.Clear;
end;

function TMarkdownCodeExtractor.NormalizeLanguage(const ALanguage: string): string;
var
  LowerLang: string;
begin
  LowerLang := LowerCase(Trim(ALanguage));

  // Normalize common language names
  if (LowerLang = 'pascal') or (LowerLang = 'delphi') or (LowerLang = 'objectpascal') then
    Result := 'delphi'
  else if (LowerLang = 'js') or (LowerLang = 'javascript') then
    Result := 'javascript'
  else if (LowerLang = 'c++') or (LowerLang = 'cpp') or (LowerLang = 'cxx') then
    Result := 'cpp'
  else if (LowerLang = 'c#') or (LowerLang = 'csharp') then
    Result := 'csharp'
  else if (LowerLang = 'py') or (LowerLang = 'python') then
    Result := 'python'
  else if LowerLang = '' then
    Result := 'text'
  else
    Result := LowerLang;
end;

function TMarkdownCodeExtractor.IsFenceClose(const ALine: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(ALine);
  Result := (Trimmed = '```');
end;

function TMarkdownCodeExtractor.TryParseFenceOpen(const ALine: string;
  out ALanguage, AFileName: string): Boolean;
var
  Trimmed, Rest, Token: string;
  ColonPos, SpacePos, QuoteStart, QuoteEnd: Integer;

  function IsWordChars(const S: string): Boolean;
  var
    j: Integer;
  begin
    Result := S <> '';
    for j := 1 to Length(S) do
      if not CharInSet(S[j], ['a'..'z', 'A'..'Z', '0'..'9', '_', '+', '#']) then
        Exit(False);
  end;

begin
  Result := False;
  ALanguage := '';
  AFileName := '';
  Trimmed := Trim(ALine);

  if not Trimmed.StartsWith('```') then
    Exit;

  Rest := Copy(Trimmed, 4, MaxInt);

  // Case 1: Just ``` (without language or file)
  if Trim(Rest) = '' then
  begin
    Result := True;
    Exit;
  end;

  // Case 2: ```language:filename.ext (colon separator)
  ColonPos := Pos(':', Rest);
  if ColonPos > 1 then
  begin
    Token := Trim(Copy(Rest, 1, ColonPos - 1));
    if IsWordChars(Token) then
    begin
      ALanguage := Token;
      AFileName := Trim(Copy(Rest, ColonPos + 1, MaxInt));
      Result := True;
      Exit;
    end;
  end;

  // Case 3: ```language title="filename.ext" (title attribute)
  SpacePos := Pos(' ', Rest);
  if SpacePos > 1 then
  begin
    Token := Copy(Rest, 1, SpacePos - 1);
    if IsWordChars(Token) then
    begin
      ALanguage := Token;
      // Look for title="..."
      Rest := Trim(Copy(Rest, SpacePos + 1, MaxInt));
      if Rest.StartsWith('title="') then
      begin
        QuoteStart := 8; // after title="
        QuoteEnd := Pos('"', Copy(Rest, QuoteStart, MaxInt));
        if QuoteEnd > 0 then
          AFileName := Copy(Rest, QuoteStart, QuoteEnd - 1);
      end;
      Result := True;
      Exit;
    end;
  end;

  // Case 4: ```language (only language, no extras)
  Token := Trim(Rest);
  if IsWordChars(Token) then
  begin
    ALanguage := Token;
    Result := True;
    Exit;
  end;

  // Does not match any known pattern
end;

function TMarkdownCodeExtractor.ExtractCodeFiles(const AMarkdownText: string): TCodeFileList;
var
  Lines: TStringList;
  i: Integer;
  CurrentLine: string;
  InCodeBlock: Boolean;
  CodeContent: TStringBuilder;
  CurrentLanguage: string;
  CurrentFileName: string;
  CodeFile: TCodeFile;
  StartLineNumber: Integer;
  ParsedLang, ParsedFileName: string;
begin
  Clear;
  Result := FCodeFiles;

  if Trim(AMarkdownText) = '' then
    Exit;

  Lines := TStringList.Create;
  CodeContent := TStringBuilder.Create;
  try
    Lines.Text := AMarkdownText;
    InCodeBlock := False;
    CurrentLanguage := '';
    CurrentFileName := '';
    StartLineNumber := 0;

    for i := 0 to Lines.Count - 1 do
    begin
      CurrentLine := Lines[i];

      if not InCodeBlock then
      begin
        if TryParseFenceOpen(CurrentLine, ParsedLang, ParsedFileName) then
        begin
          InCodeBlock := True;
          StartLineNumber := i + 1; // +1 because lines are counted from 1
          CodeContent.Clear;
          CurrentLanguage := NormalizeLanguage(ParsedLang);
          CurrentFileName := ParsedFileName;
        end;
      end
      else
      begin
        if IsFenceClose(CurrentLine) then
        begin
          InCodeBlock := False;

          // Create the code file record
          CodeFile.FileName := CurrentFileName;
          CodeFile.FileType := CurrentLanguage;
          CodeFile.Code := CodeContent.ToString;
          CodeFile.LineNumber := StartLineNumber;

          // Add only if there is content
          if Trim(CodeFile.Code) <> '' then
            FCodeFiles.Add(CodeFile);

          // Reset variables
          CurrentLanguage := '';
          CurrentFileName := '';
          CodeContent.Clear;
        end
        else
        begin
          // Line inside the code block
          if CodeContent.Length > 0 then
            CodeContent.AppendLine;
          CodeContent.Append(CurrentLine);
        end;
      end;
    end;

    // If a block remained open at the end of the text
    if InCodeBlock and (CodeContent.Length > 0) then
    begin
      CodeFile.FileName := CurrentFileName;
      CodeFile.FileType := CurrentLanguage;
      CodeFile.Code := CodeContent.ToString;
      CodeFile.LineNumber := StartLineNumber;
      FCodeFiles.Add(CodeFile);
    end;

  finally
    Lines.Free;
    CodeContent.Free;
  end;
end;

end.
