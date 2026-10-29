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
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMainDocumentManager;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants, System.JSON, System.Net.HttpClient,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Layouts, FMX.Memo,
  FMX.Edit, FMX.Memo.Types, FMX.ScrollBox,
  uMakerAi.Chat, uMakerAi.Chat.Ollama,
  uMakerAi.Embeddings.core, uMakerAi.Embeddings.Ollama,
  uMakerAi.RAG.Graph.Core,
  uMakerAi.RAG.Graph.Documents;

type
  TFormDocManager = class(TForm)
    BtnAbrir: TButton;
    BtnGenerarJson: TButton;
    BtnAgregarGrafo: TButton;
    BtnBuscar: TButton;
    BtnExtraerEntidades: TButton;
    BtnExtraerRelaciones: TButton;
    BtnAgregarRelacion: TButton;
    LblArchivo: TLabel;
    LblDocumento: TLabel;
    LblJson: TLabel;
    LblResultados: TLabel;
    MemoDocumento: TMemo;
    MemoJson: TMemo;
    MemoResultados: TMemo;
    EditBuscar: TEdit;
    OpenDialog1: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnAbrirClick(Sender: TObject);
    procedure BtnGenerarJsonClick(Sender: TObject);
    procedure BtnAgregarGrafoClick(Sender: TObject);
    procedure BtnBuscarClick(Sender: TObject);
    procedure BtnExtraerEntidadesClick(Sender: TObject);
    procedure BtnExtraerRelacionesClick(Sender: TObject);
    procedure BtnAgregarRelacionClick(Sender: TObject);
  private
    FOllamaEmbeddings: TAiOllamaEmbeddings;
    FRagGraph: TAiRagGraph;
    FDocManager: TAiRagDocumentManager;
    FOllamaChat: TAiOllamaChat;
    procedure ChatError(Sender: TObject; const ErrorMsg: string;
      Exception: Exception; const AResponse: IHTTPResponse);
  end;

var
  FormDocManager: TFormDocManager;

implementation

{$R *.fmx}

procedure TFormDocManager.FormCreate(Sender: TObject);
begin
  // Embeddings locales via Ollama
  FOllamaEmbeddings := TAiOllamaEmbeddings.Create(Self);
  FOllamaEmbeddings.Model := 'mxbai-embed-large:latest';
  FOllamaEmbeddings.Dimensions := 1024;
  FOllamaEmbeddings.Url := 'http://localhost:11434/';

  // RAG graph in memory
  FRagGraph := TAiRagGraph.Create(Self);
  FRagGraph.Embeddings := FOllamaEmbeddings;

  // Document Manager
  FDocManager := TAiRagDocumentManager.Create(Self);
  FDocManager.Graph := FRagGraph;
  FDocManager.ChunkSize := 1000;

  // Local LLM chat for JSON generation and relationship extraction
  FOllamaChat := TAiOllamaChat.Create(Self);
  FOllamaChat.Model := 'gpt-oss:20b';
  FOllamaChat.Asynchronous := False;
  FOllamaChat.OnError := ChatError;
end;

procedure TFormDocManager.FormDestroy(Sender: TObject);
begin
  FDocManager.Free;
  FOllamaChat.Free;
  FRagGraph.Free;
  FOllamaEmbeddings.Free;
end;

procedure TFormDocManager.ChatError(Sender: TObject; const ErrorMsg: string;
  Exception: Exception; const AResponse: IHTTPResponse);
begin
  ShowMessage('LLM error: ' + ErrorMsg);
end;

procedure TFormDocManager.BtnAbrirClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'Text files|*.txt|All files|*.*';
  if OpenDialog1.Execute then
  begin
    MemoDocumento.Lines.LoadFromFile(OpenDialog1.FileName);
    LblArchivo.Text := ExtractFileName(OpenDialog1.FileName);
  end;
end;

procedure TFormDocManager.BtnGenerarJsonClick(Sender: TObject);
var
  Prompt, Res: string;
begin
  if MemoDocumento.Lines.Text.Trim.IsEmpty then
  begin
    ShowMessage('First open a text document.');
    Exit;
  end;

  Prompt :=
    'Analyze the following text document and generate a hierarchical JSON with this exact structure:' + sLineBreak +
    '{' + sLineBreak +
    '  "name": "<descriptive name of the document>",' + sLineBreak +
    '  "label": "Document",' + sLineBreak +
    '  "text": "<brief summary of the complete document>",' + sLineBreak +
    '  "properties": {' + sLineBreak +
    '    "tipo": "<detected document type>",' + sLineBreak +
    '    "idioma": "<document language>"' + sLineBreak +
    '  },' + sLineBreak +
    '  "parts": [' + sLineBreak +
    '    {' + sLineBreak +
    '      "name": "<section name>",' + sLineBreak +
    '      "label": "Seccion",' + sLineBreak +
    '      "text": "<text of this section>",' + sLineBreak +
    '      "parts": []' + sLineBreak +
    '    }' + sLineBreak +
    '  ]' + sLineBreak +
    '}' + sLineBreak +
    sLineBreak +
    'Reglas:' + sLineBreak +
    '- Identify the natural sections of the text (titles, topics, thematic paragraphs)' + sLineBreak +
    '- Each "part" must have "name", "label" and "text" required' + sLineBreak +
    '- If a section has subsections, use "parts" recursively' + sLineBreak +
    '- The "text" field of each part must contain the original text, not a summary' + sLineBreak +
    '- Respond ONLY with the JSON, without additional explanations or markdown' + sLineBreak +
    sLineBreak +
    'DOCUMENTO:' + sLineBreak +
    MemoDocumento.Lines.Text;

  Cursor := crHourGlass;
  try
    FOllamaChat.Messages.Clear;
    Res := FOllamaChat.AddMessageAndRun(Prompt, 'user', []);
    MemoJson.Lines.Text := Res;
  finally
    Cursor := crDefault;
  end;
end;

procedure TFormDocManager.BtnAgregarGrafoClick(Sender: TObject);
var
  DocNode: TAiRagGraphNode;
  Parts: TArray<TDocumentPart>;
  I: Integer;
begin
  if MemoJson.Lines.Text.Trim.IsEmpty then
  begin
    ShowMessage('First generate the JSON with AI.');
    Exit;
  end;

  Cursor := crHourGlass;
  try
    try
      DocNode := FDocManager.AddDocumentFromJSON(MemoJson.Lines.Text);

      Parts := FDocManager.GetDocumentParts(DocNode);

      MemoResultados.Lines.Clear;
      MemoResultados.Lines.Add('Documento agregado: ' + DocNode.Name);
      MemoResultados.Lines.Add('Chunks creados: ' + IntToStr(Length(Parts)));
      MemoResultados.Lines.Add('');
      MemoResultados.Lines.Add('--- Document parts ---');

      for I := 0 to High(Parts) do
      begin
        MemoResultados.Lines.Add(Format('[%d] %s (%s) - Depth: %d - Path: %s',
          [Parts[I].Order, Parts[I].Name, Parts[I].PartLabel,
           Parts[I].Depth, Parts[I].Path]));
      end;
    except
      on E: Exception do
        ShowMessage('Error adding document: ' + E.Message);
    end;
  finally
    Cursor := crDefault;
  end;
end;

procedure TFormDocManager.BtnBuscarClick(Sender: TObject);
var
  Res: string;
begin
  if EditBuscar.Text.Trim.IsEmpty then
  begin
    ShowMessage('Enter a search text.');
    Exit;
  end;

  Cursor := crHourGlass;
  try
    try
      Res := FDocManager.SearchDocumentsText(EditBuscar.Text, 5, 0.3);

      MemoResultados.Lines.Clear;
      if Res.Trim.IsEmpty then
        MemoResultados.Lines.Add('No se encontraron resultados.')
      else
        MemoResultados.Lines.Text := Res;
    except
      on E: Exception do
        ShowMessage('Search error: ' + E.Message);
    end;
  finally
    Cursor := crDefault;
  end;
end;

procedure TFormDocManager.BtnExtraerEntidadesClick(Sender: TObject);
var
  Docs: TArray<TAiRagGraphNode>;
  TotalEnts, Ents: Integer;
  Doc: TAiRagGraphNode;
  Entities: TArray<TAiRagGraphNode>;
  I: Integer;
begin
  Docs := FDocManager.GetAllDocuments;
  if Length(Docs) = 0 then
  begin
    ShowMessage('There are no documents in the graph. Add one first.');
    Exit;
  end;

  Cursor := crHourGlass;
  try
    try
      FDocManager.Chat := FOllamaChat;
      TotalEnts := 0;

      for Doc in Docs do
      begin
        Ents := FDocManager.ExtractEntitiesOnly(Doc);
        TotalEnts := TotalEnts + Ents;
      end;

      MemoResultados.Lines.Clear;
      MemoResultados.Lines.Add(Format('Phase 1 complete - Entities extracted: %d', [TotalEnts]));
      MemoResultados.Lines.Add('');

      // Listar entidades encontradas
      for Doc in Docs do
      begin
        Entities := FDocManager.GetDocumentEntities(Doc);
        MemoResultados.Lines.Add('--- Entidades de: ' + Doc.Name + ' ---');
        for I := 0 to High(Entities) do
          MemoResultados.Lines.Add(Format('  [%d] %s (%s)', [I + 1, Entities[I].Name, Entities[I].NodeLabel]));
        MemoResultados.Lines.Add('');
      end;
    except
      on E: Exception do
        ShowMessage('Error extrayendo entidades: ' + E.Message);
    end;
  finally
    Cursor := crDefault;
  end;
end;

procedure TFormDocManager.BtnExtraerRelacionesClick(Sender: TObject);
var
  Docs: TArray<TAiRagGraphNode>;
  TotalRels, Rels: Integer;
  Doc: TAiRagGraphNode;
  Context: TDocumentContext;
begin
  Docs := FDocManager.GetAllDocuments;
  if Length(Docs) = 0 then
  begin
    ShowMessage('There are no documents in the graph. Add one first.');
    Exit;
  end;

  Cursor := crHourGlass;
  try
    try
      FDocManager.Chat := FOllamaChat;
      TotalRels := 0;

      for Doc in Docs do
      begin
        Rels := FDocManager.ExtractRelationshipsWithContext(Doc);
        TotalRels := TotalRels + Rels;
      end;

      MemoResultados.Lines.Clear;
      MemoResultados.Lines.Add(Format('Phase 2 complete - Relationships extracted: %d', [TotalRels]));
      MemoResultados.Lines.Add('');

      // Show complete context of the first document
      if Length(Docs) > 0 then
      begin
        Context := FDocManager.GetDocumentContext(Docs[0]);
        MemoResultados.Lines.Add('--- Document context ---');
        MemoResultados.Lines.Add(Context.GetContextText);
      end;
    except
      on E: Exception do
        ShowMessage('Error extrayendo relaciones: ' + E.Message);
    end;
  finally
    Cursor := crDefault;
  end;
end;

procedure TFormDocManager.BtnAgregarRelacionClick(Sender: TObject);
var
  FromName, ToName, EdgeLabel: string;
  FromNode, ToNode, Node: TAiRagGraphNode;
  Edge: TAiRagGraphEdge;
  I: Integer;
begin
  // Request data from the user
  FromName := '';
  if not InputQuery('Add Edge', 'Origin node name (From):', FromName) then
    Exit;
  if FromName.Trim.IsEmpty then Exit;

  ToName := '';
  if not InputQuery('Add Edge', 'Destination node name (To):', ToName) then
    Exit;
  if ToName.Trim.IsEmpty then Exit;

  EdgeLabel := '';
  if not InputQuery('Add Edge', 'Relationship type (edge label):', EdgeLabel) then
    Exit;
  if EdgeLabel.Trim.IsEmpty then Exit;

  // Find nodes by name (case-insensitive in the graph)
  FromNode := nil;
  ToNode := nil;
  for I := 0 to FRagGraph.Nodes.Items.Count - 1 do
  begin
    Node := TAiRagGraphNode(FRagGraph.Nodes.Items[I]);
    if SameText(Node.Name, FromName) then
      FromNode := Node;
    if SameText(Node.Name, ToName) then
      ToNode := Node;
    if (FromNode <> nil) and (ToNode <> nil) then
      Break;
  end;

  if FromNode = nil then
  begin
    ShowMessage('Origin node not found: ' + FromName);
    Exit;
  end;

  if ToNode = nil then
  begin
    ShowMessage('Destination node not found: ' + ToName);
    Exit;
  end;

  try
    Edge := FDocManager.AddEdge(FromNode, ToNode, EdgeLabel);
    MemoResultados.Lines.Add(Format('Edge created: %s -[%s]-> %s',
      [FromNode.Name, Edge.EdgeLabel, ToNode.Name]));
  except
    on E: Exception do
      ShowMessage('Error creating edge: ' + E.Message);
  end;
end;

end.
