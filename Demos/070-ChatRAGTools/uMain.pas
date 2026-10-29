// =============================================================================
//  Demo 070 - ChatRAGTools
//  Chat multi-proveedor (MakerAI) + RAG local con SQLite + TAiFunctions
//  (TDateTime y GraficarSerie) + TabControl con WebBrowser(Edge), TeeChart y Memo.
//
//  Construido "code-first": todos los componentes se crean y cablean en
//  FormCreate para que el demo sea autocontenido y didactico.
//  Basado en el patron de 012-ChatAllFunctions (ChatFull).
// =============================================================================
unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.JSON, System.Threading, System.IOUtils, System.DateUtils, System.Net.HttpClient,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, FMX.Memo.Types,
  FMX.Edit, FMX.ListBox, FMX.TabControl, FMX.WebBrowser,
  // TeeChart (FMX)
  FMXTee.Engine, FMXTee.Procs, FMXTee.Chart, FMXTee.Series,
  // FireDAC (SQLite embebido, sin DLL externa via SQLiteWrapper.Stat)
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async,
  FireDAC.Phys, FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat, FireDAC.FMXUI.Wait, FireDAC.Comp.UI,
  FireDAC.DApt, Data.DB, FireDAC.Comp.Client,
  // MakerAI
  uMakerAi.Core, uMakerAi.Chat, uMakerAi.Chat.Messages, uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations, uMakerAi.Tools.Functions,
  uMakerAi.RAG.Vectors, uMakerAi.RAG.Vector.Driver.SQLite,
  uMakerAi.Embeddings.Core, uMakerAi.Embeddings.OpenAi;

type
  TFormMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    // --- Componentes MakerAI (no visuales) ---
    AiConn: TAiChatConnection;
    AiFunctions1: TAiFunctions;
    Embeddings: TAiOpenAiEmbeddings;
    RAG: TAiRAGVector;
    RAGDriver: TAiRAGVectorSQLiteDriver;
    // --- SQLite ---
    FDConn: TFDConnection;
    FGUIWait: TFDGUIxWaitCursor;
    // --- UI: chat (izquierda) ---
    ComboDriver, ComboModel: TComboBox;
    ChkUseRAG: TCheckBox;
    MemoChat, MemoPrompt: TMemo;
    BtnSend, BtnLoadRAG: TButton;
    // --- UI: TabControl (derecha) ---
    Tab: TTabControl;
    tabWeb, tabChart, tabLog: TTabItem;
    WebBrowser1: TWebBrowser;
    Chart1: TChart;
    FSerie: TLineSeries;
    MemoLog: TMemo;
    procedure BuildUI;
    procedure BuildAi;
    procedure InitProviders;
    // eventos UI
    procedure ComboDriverChange(Sender: TObject);
    procedure BtnSendClick(Sender: TObject);
    procedure BtnLoadRAGClick(Sender: TObject);
    // eventos chat
    procedure AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnError(Sender: TObject; const ErrorMsg: string; AException: Exception; const AResponse: IHTTPResponse);
    // funciones (tools)
    procedure FuncGetFechaHora(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure FuncGraficarSerie(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    // helpers
    procedure AddLog(const S: string);
    procedure ChatAppend(const S: string);
    function ParseFecha(const S: string; aIndex: Integer): TDateTime;
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

const
  CHART_DT_FMT = 'dd/mm hh:nn';

// =============================================================================
//  Creacion del form
// =============================================================================
procedure TFormMain.FormCreate(Sender: TObject);
begin
  BuildUI;
  BuildAi;
  InitProviders;
  AddLog('Ready. Select provider and model, write a prompt and press Send.');
  AddLog('Tools available to the AI: GetFechaHora, GraficarSerie.');
  AddLog('Local RAG in SQLite: ' + FDConn.Params.Database);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  try
    if Assigned(FDConn) then
      FDConn.Connected := False;
  except
  end;
end;

// =============================================================================
//  UI - construida por codigo
// =============================================================================
procedure TFormMain.BuildUI;
var
  LLeft, LTopBar, LBottom: TLayout;
  Spl: TSplitter;
begin
  // ---------- Left panel (chat) ----------
  LLeft := TLayout.Create(Self);
  LLeft.Parent := Self;
  LLeft.Align := TAlignLayout.Left;
  LLeft.Width := 560;

  // top bar: selectors + RAG
  LTopBar := TLayout.Create(Self);
  LTopBar.Parent := LLeft;
  LTopBar.Align := TAlignLayout.Top;
  LTopBar.Height := 96;

  ComboDriver := TComboBox.Create(Self);
  ComboDriver.Parent := LTopBar;
  ComboDriver.Position.X := 10; ComboDriver.Position.Y := 10;
  ComboDriver.Width := 200;
  ComboDriver.OnChange := ComboDriverChange;

  ComboModel := TComboBox.Create(Self);
  ComboModel.Parent := LTopBar;
  ComboModel.Position.X := 220; ComboModel.Position.Y := 10;
  ComboModel.Width := 320;

  ChkUseRAG := TCheckBox.Create(Self);
  ChkUseRAG.Parent := LTopBar;
  ChkUseRAG.Position.X := 10; ChkUseRAG.Position.Y := 52;
  ChkUseRAG.Width := 220;
  ChkUseRAG.Text := 'Use RAG (local context)';

  BtnLoadRAG := TButton.Create(Self);
  BtnLoadRAG.Parent := LTopBar;
  BtnLoadRAG.Position.X := 240; BtnLoadRAG.Position.Y := 48;
  BtnLoadRAG.Width := 300;
  BtnLoadRAG.Text := 'Load text/file to RAG...';
  BtnLoadRAG.OnClick := BtnLoadRAGClick;

  // bottom area: prompt + send
  LBottom := TLayout.Create(Self);
  LBottom.Parent := LLeft;
  LBottom.Align := TAlignLayout.Bottom;
  LBottom.Height := 130;

  BtnSend := TButton.Create(Self);
  BtnSend.Parent := LBottom;
  BtnSend.Align := TAlignLayout.Right;
  BtnSend.Width := 90;
  BtnSend.Text := 'Send';
  BtnSend.OnClick := BtnSendClick;

  MemoPrompt := TMemo.Create(Self);
  MemoPrompt.Parent := LBottom;
  MemoPrompt.Align := TAlignLayout.Client;
  MemoPrompt.TextSettings.WordWrap := True;
  MemoPrompt.Lines.Text := 'Hello, tell me the current date and time.';

  // center: chat memo
  MemoChat := TMemo.Create(Self);
  MemoChat.Parent := LLeft;
  MemoChat.Align := TAlignLayout.Client;
  MemoChat.ReadOnly := True;
  MemoChat.TextSettings.WordWrap := True;

  // ---------- Splitter ----------
  Spl := TSplitter.Create(Self);
  Spl.Parent := Self;
  Spl.Align := TAlignLayout.Left;
  Spl.Width := 6;

  // ---------- Right TabControl ----------
  Tab := TTabControl.Create(Self);
  Tab.Parent := Self;
  Tab.Align := TAlignLayout.Client;

  tabWeb := Tab.Add;
  tabWeb.Text := 'Web (Edge)';
  WebBrowser1 := TWebBrowser.Create(Self);
  WebBrowser1.Parent := tabWeb;
  WebBrowser1.Align := TAlignLayout.Client;

  tabChart := Tab.Add;
  tabChart.Text := 'Chart (TeeChart)';
  Chart1 := TChart.Create(Self);
  Chart1.Parent := tabChart;
  Chart1.Align := TAlignLayout.Client;
  Chart1.View3D := False;
  Chart1.Title.Text.Text := 'Time series';
  FSerie := TLineSeries.Create(Chart1);
  Chart1.AddSeries(FSerie);
  FSerie.XValues.DateTime := True;
  Chart1.BottomAxis.DateTimeFormat := CHART_DT_FMT;

  tabLog := Tab.Add;
  tabLog.Text := 'Log';
  MemoLog := TMemo.Create(Self);
  MemoLog.Parent := tabLog;
  MemoLog.Align := TAlignLayout.Client;
  MemoLog.ReadOnly := True;

  Tab.ActiveTab := tabLog;

  // browser initial page
  try
    WebBrowser1.URL := 'https://makerai.cimamaker.com';
    WebBrowser1.Navigate;
  except
  end;
end;

// =============================================================================
//  Componentes MakerAI + RAG SQLite
// =============================================================================
procedure TFormMain.BuildAi;
var
  LFn: TFunctionActionItem;
  LParam: TFunctionParamsItem;
begin
  // ---- SQLite (FireDAC, embedded) ----
  FGUIWait := TFDGUIxWaitCursor.Create(Self);
  FDConn := TFDConnection.Create(Self);
  FDConn.LoginPrompt := False;
  FDConn.Params.DriverID := 'SQLite';
  FDConn.Params.Database := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rag_demo.db');
  FDConn.Params.Add('LockingMode=Normal');
  FDConn.Connected := True;

  // ---- Embeddings (OpenAI) ----
  Embeddings := TAiOpenAiEmbeddings.Create(Self);
  Embeddings.ApiKey := '@OPENAI_API_KEY';

  // ---- SQLite RAG driver (vector search in pure Delphi, without vec0) ----
  RAGDriver := TAiRAGVectorSQLiteDriver.Create(Self);
  RAGDriver.Connection := FDConn;
  RAGDriver.TableName := 'vec_docs';
  try
    RAGDriver.CreateSchema('vec_docs');
  except
    on E: Exception do
      AddLog('Warning while creating RAG schema: ' + E.Message);
  end;

  // ---- Vector store ----
  RAG := TAiRAGVector.Create(Self, True);
  RAG.Embeddings := Embeddings;
  RAG.Driver := RAGDriver;

  // ---- Chat connection ----
  AiConn := TAiChatConnection.Create(Self);
  AiConn.OnReceiveData := AiConnReceiveData;
  AiConn.OnReceiveDataEnd := AiConnReceiveDataEnd;
  AiConn.OnError := AiConnError;

  // ---- TAiFunctions with two functions ----
  AiFunctions1 := TAiFunctions.Create(Self);

  // 1) GetFechaHora
  LFn := AiFunctions1.Functions.Add;
  LFn.FunctionName := 'GetFechaHora';
  LFn.Enabled := True;
  LFn.Description.Text := 'Returns the current system date and time in ISO 8601 format.';
  LFn.OnAction := FuncGetFechaHora;
  LParam := LFn.Parameters.Add;
  LParam.Name := 'zona';
  LParam.ParamType := ptString;
  LParam.Description.Text := 'Optional time zone (informational only).';
  LParam.Required := False;

  // 2) GraficarSerie (schema with point array via RawSchemaJson)
  LFn := AiFunctions1.Functions.Add;
  LFn.FunctionName := 'GraficarSerie';
  LFn.Enabled := True;
  LFn.Description.Text := 'Plots a time series in the chart panel. ' +
    'Receives a title and an array of points {date, value}.';
  LFn.RawSchemaJson :=
    '{"type":"object","properties":{' +
    '"titulo":{"type":"string","description":"Titulo de la grafica"},' +
    '"puntos":{"type":"array","description":"Puntos de la serie de tiempo",' +
    '"items":{"type":"object","properties":{' +
    '"fecha":{"type":"string","description":"Fecha u hora en ISO 8601"},' +
    '"valor":{"type":"number","description":"Valor numerico del punto"}},' +
    '"required":["fecha","valor"]}}},"required":["puntos"]}';
  LFn.OnAction := FuncGraficarSerie;

  // connect functions to chat
  AiConn.AiFunctions := AiFunctions1;
end;

// =============================================================================
//  Proveedores y modelos
// =============================================================================
procedure TFormMain.InitProviders;
var
  List: TStringList;
begin
  try
    List := AiConn.GetDriversNames;
    try
      List.Sort;
      ComboDriver.Items.Assign(List);
      if ComboDriver.Items.Count > 0 then
      begin
        ComboDriver.ItemIndex := 0;
        ComboDriverChange(ComboDriver);
      end;
    finally
      List.Free;
    end;
  except
    on E: Exception do
      AddLog('Could not load providers: ' + E.Message);
  end;
end;

procedure TFormMain.ComboDriverChange(Sender: TObject);
var
  List: TStringList;
begin
  if not Assigned(ComboDriver.Selected) then
    Exit;

  AiConn.DriverName := Trim(ComboDriver.Selected.Text);
  // enable tools and streaming for this demo
  AiConn.Params.Values['Tool_Active'] := 'True';
  AiConn.Params.Values['Asynchronous'] := 'True';

  try
    List := AiConn.GetModels;
    try
      List.Sort;
      ComboModel.Items.Assign(List);
      if ComboModel.Items.Count > 0 then
        ComboModel.ItemIndex := 0;
    finally
      List.Free;
    end;
  except
    on E: Exception do
      AddLog('Could not load models for ' + AiConn.DriverName + ': ' + E.Message);
  end;
end;

// =============================================================================
//  Envio del prompt (con RAG opcional)
// =============================================================================
procedure TFormMain.BtnSendClick(Sender: TObject);
var
  LPrompt, LContext, LFinal: string;
begin
  LPrompt := Trim(MemoPrompt.Lines.Text);
  if LPrompt = '' then
    Exit;

  if Assigned(ComboModel.Selected) then
    AiConn.Model := Trim(ComboModel.Selected.Text);

  // RAG: retrieve local context and prepend it to the prompt
  LFinal := LPrompt;
  if ChkUseRAG.IsChecked then
  begin
    try
      LContext := RAG.SearchText(LPrompt, 5, 0.3);
      if Trim(LContext) <> '' then
      begin
        LFinal := 'Usa el siguiente CONTEXTO (recuperado de la base local) para responder.' + sLineBreak +
          '--- CONTEXTO ---' + sLineBreak + LContext + sLineBreak +
          '--- PREGUNTA ---' + sLineBreak + LPrompt;
        AddLog('RAG: context retrieved (' + Length(LContext).ToString + ' chars).');
      end
      else
        AddLog('RAG: no relevant matches.');
    except
      on E: Exception do
        AddLog('RAG error: ' + E.Message);
    end;
  end;

  ChatAppend('You: ' + LPrompt + sLineBreak + 'AI: ');
  MemoPrompt.Lines.Clear;
  BtnSend.Enabled := False;

  TTask.Run(
    procedure
    begin
      try
        AiConn.AddMessageAndRun(LFinal, 'user', []);
      except
        on E: Exception do
          TThread.Queue(nil,
            procedure
            begin
              AddLog('Error while sending: ' + E.Message);
              BtnSend.Enabled := True;
            end);
      end;
    end);
end;

// =============================================================================
//  Cargar documentos a RAG (SQLite)
// =============================================================================
procedure TFormMain.BtnLoadRAGClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  LText: string;
  N: Integer;
begin
  // if the prompt has text, index it; otherwise open a .txt file
  LText := Trim(MemoPrompt.Lines.Text);
  if LText = '' then
  begin
    Dlg := TOpenDialog.Create(Self);
    try
      Dlg.Filter := 'Texto (*.txt;*.md)|*.txt;*.md|Todos (*.*)|*.*';
      if not Dlg.Execute then
        Exit;
      LText := TFile.ReadAllText(Dlg.FileName, TEncoding.UTF8);
    finally
      Dlg.Free;
    end;
  end;

  if Trim(LText) = '' then
    Exit;

  try
    N := RAG.AddItemsFromPlainText(LText, nil, 512, 20);
    AddLog(Format('RAG: indexed %d fragments in SQLite.', [N]));
    MemoPrompt.Lines.Clear;
  except
    on E: Exception do
      AddLog('RAG: error while indexing: ' + E.Message + ' (check OPENAI_API_KEY for embeddings)');
  end;
end;

// =============================================================================
//  Eventos del chat
// =============================================================================
procedure TFormMain.AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  if aText = '' then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      MemoChat.Lines.Text := MemoChat.Lines.Text + aText;
      MemoChat.GoToTextEnd;
    end);
end;

procedure TFormMain.AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      // in sync aText carries the full response; in async it was already
      // painted in OnReceiveData, so we only close the turn.
      if (MemoChat.Lines.Text <> '') and (aText <> '') and
         (Pos(aText, MemoChat.Lines.Text) = 0) then
        MemoChat.Lines.Text := MemoChat.Lines.Text + aText;

      ChatAppend(sLineBreak + sLineBreak);
      if Assigned(aMsg) then
        AddLog(Format('Tokens -> prompt:%d  completion:%d  total:%d  (%s)',
          [aMsg.Prompt_tokens, aMsg.Completion_tokens, aMsg.Total_tokens, aMsg.Model]));
      BtnSend.Enabled := True;
    end);
end;

procedure TFormMain.AiConnError(Sender: TObject; const ErrorMsg: string; AException: Exception; const AResponse: IHTTPResponse);
begin
  TThread.Queue(nil,
    procedure
    begin
      AddLog('ERROR: ' + ErrorMsg);
      BtnSend.Enabled := True;
    end);
end;

// =============================================================================
//  Funciones (tools) llamadas por la IA
// =============================================================================
procedure TFormMain.FuncGetFechaHora(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  ToolCall.Response := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  TThread.Queue(nil,
    procedure
    begin
      AddLog('Tool GetFechaHora -> ' + ToolCall.Response);
    end);
  Handled := True;
end;

procedure TFormMain.FuncGraficarSerie(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  jObj: TJSONObject;
  jPuntos: TJSONArray;
  jVal: TJSONValue;
  jPto: TJSONObject;
  LTitulo, LFecha: string;
  LValor: Double;
  i, LCount: Integer;
begin
  Handled := True;
  jObj := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if not Assigned(jObj) then
  begin
    ToolCall.Response := 'Error: invalid JSON arguments.';
    Exit;
  end;
  try
    LTitulo := '';
    jObj.TryGetValue<string>('titulo', LTitulo);
    if not jObj.TryGetValue<TJSONArray>('puntos', jPuntos) or (jPuntos.Count = 0) then
    begin
      ToolCall.Response := 'Error: no points received to plot.';
      Exit;
    end;

    LCount := jPuntos.Count;
    // Plot on the main thread (touches the UI)
    TThread.Synchronize(nil,
      procedure
      var
        k: Integer;
        po: TJSONObject;
        f: string;
        v: Double;
      begin
        FSerie.Clear;
        if LTitulo <> '' then
        begin
          FSerie.Title := LTitulo;
          Chart1.Title.Text.Text := LTitulo;
        end;
        for k := 0 to jPuntos.Count - 1 do
        begin
          if not(jPuntos.Items[k] is TJSONObject) then
            Continue;
          po := jPuntos.Items[k] as TJSONObject;
          f := '';
          po.TryGetValue<string>('fecha', f);
          v := 0;
          po.TryGetValue<Double>('valor', v);
          FSerie.AddXY(ParseFecha(f, k), v);
        end;
        Chart1.BottomAxis.DateTimeFormat := CHART_DT_FMT;
        Tab.ActiveTab := tabChart;
        AddLog(Format('Tool GraficarSerie -> %d points. "%s"', [LCount, LTitulo]));
      end);

    ToolCall.Response := Format('OK, chart generated with %d points.', [LCount]);
  finally
    // keep touched variables to avoid hints
    jVal := nil; jPto := nil; i := 0; LFecha := ''; LValor := 0;
    if (jVal = nil) and (jPto = nil) and (i = 0) and (LFecha = '') and (LValor = 0) then ;
    jObj.Free;
  end;
end;

// =============================================================================
//  Helpers
// =============================================================================
procedure TFormMain.AddLog(const S: string);
begin
  if not Assigned(MemoLog) then
    Exit;
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
  MemoLog.GoToTextEnd;
end;

procedure TFormMain.ChatAppend(const S: string);
begin
  MemoChat.Lines.Text := MemoChat.Lines.Text + S;
  MemoChat.GoToTextEnd;
end;

function TFormMain.ParseFecha(const S: string; aIndex: Integer): TDateTime;
var
  d: TDateTime;
begin
  if (S <> '') and TryISO8601ToDate(S, d, False) then
    Exit(d);
  if (S <> '') and TryStrToDateTime(S, d) then
    Exit(d);
  if (S <> '') and TryStrToDate(S, d) then
    Exit(d);
  // fallback: consecutive days from today
  Result := Trunc(Now) + aIndex;
end;

end.
