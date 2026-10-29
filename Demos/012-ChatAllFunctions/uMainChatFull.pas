// MIT License
//
// Copyright (c) 2013 Gustavo Enríquez - CimaMaker
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
// Name: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMainChatFull;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.IOUtils, System.Rtti, System.JSON, System.Net.HttpClient, System.Threading, System.ZLib,
  System.StrUtils, System.TypInfo, System.Math, System.Generics.Collections,
  System.Net.HttpClientComponent,

  uMakerAi.UI.ChatBubble, uMakerAi.UI.ChatInput, uMakerAi.Core, uMakerAi.Chat,
  uMakerAi.Utils.System, uMakerAi.UI.ChatList, uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.OpenAi, uMakerAi.Chat.Initializations, uMakerAi.Chat.Messages,
  uMakerAi.Chat.DeepSeek, uMakerAi.Chat.Claude, uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Kimi, uMakerAi.Chat.LMStudio, uMakerAi.OpenAi.Sora,
  uMakerAi.Chat.GenericLLM, uMakerAi.Utils.ScreenCapture,

  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types, FMX.Layouts,
  FMX.Styles.Objects, FMX.Platform, FMX.ScrollBox, FMX.Memo, FMX.Edit, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Objects, FMX.Menus, FMX.ListBox,

  uMakerAi.Chat.Mistral, uMakerAi.Chat.Ollama, uMakerAi.Chat.Groq, uMakerAi.Chat.Grok, uMakerAi.Whisper,
  uMakerAi.Utils.VoiceMonitor, System.Actions, FMX.ActnList, uMakerAi.RAG.Vectors, uMakerAi.Tools.Functions,
  uMakerAi.Embeddings.Core, uMakerAi.Embeddings, uMakerAi.Embeddings.OpenAi, uMakerAi.MCPServer.Core, uMakerAi.MCPServer.Http,

  System.ImageList, FMX.ImgList, FMX.TabControl, uMakerAi.Tools.Shell, uMakerAi.Tools.TextEditor, uMakerAi.Chat.Cohere,
  uMakerAi.Utils.DiffUpdater, uMakerAi.Prompts, uMakerAi.Tools.ComputerUse, uMakerAi.Tools.ComputerUse.WindowsFMX, uMakerAi.Chat.Tools;

type

  TSafetyState = (stWaiting, stAllow, stDeny); // states of the computer use safety process

  TForm2 = class(TForm)
    PopupMenu1: TPopupMenu;
    MnuCopy: TMenuItem;
    MnuSave: TMenuItem;
    MnuPlay: TMenuItem;
    SaveDialog1: TSaveDialog;
    AiConn: TAiChatConnection;
    MainLayout: TLayout;
    MainChatLayout: TLayout;
    ChatList1: TChatList;
    Layout3: TLayout;
    Layout2: TLayout;

    ComboDriver: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    ComboModels: TComboBox;
    ListBox1: TListBox;
    ListBoxItem1: TListBoxItem;
    LblTotaltokens: TLabel;
    EditTotalTokens: TEdit;
    ListBoxItem2: TListBoxItem;
    LblPrompTokens: TLabel;
    EditPromptTokens: TEdit;
    ListBoxItem3: TListBoxItem;
    LblCompletionTokens: TLabel;
    EditCompletionTokens: TEdit;
    ListBoxGroupHeader2: TListBoxGroupHeader;
    ListBoxItem5: TListBoxItem;
    ChAsincrono: TCheckBox;
    ListBoxItem11: TListBoxItem;
    ChJSonFormat: TCheckBox;
    ListBoxItem12: TListBoxItem;
    ChUseTools: TCheckBox;
    ListBoxItem4: TListBoxItem;
    Label5: TLabel;
    EditMaxTokens: TEdit;
    ListBoxItem9: TListBoxItem;
    LblTemperature: TLabel;
    TrackTemperature: TTrackBar;
    ListBoxItem8: TListBoxItem;
    Label4: TLabel;
    EditCompletionModel: TEdit;
    ListBoxItem10: TListBoxItem;
    ChWebSearch: TCheckBox;
    ListBoxItem13: TListBoxItem;
    ChCodeInterpreter: TCheckBox;
    ListBoxItem14: TListBoxItem;
    ChExtractFiles: TCheckBox;
    ListBoxItem15: TListBoxItem;
    Label6: TLabel;
    EditThinkingLevel: TComboBox;
    ListBoxItem16: TListBoxItem;
    Label7: TLabel;
    EditVoices: TEdit;
    ListBoxItem7: TListBoxItem;
    Label3: TLabel;
    EditChatMediaSupports: TEdit;
    ListBoxItem17: TListBoxItem;
    Label8: TLabel;
    EditNativeInputFiles: TEdit;
    ListBoxItem18: TListBoxItem;
    Label9: TLabel;
    EditNativeOutputFiles: TEdit;
    ListBoxItem19: TListBoxItem;
    Label10: TLabel;
    EditVoiceFormat: TEdit;
    Rectangle1: TRectangle;
    Label11: TLabel;
    ListBoxGroupHeader3: TListBoxGroupHeader;
    Rectangle2: TRectangle;
    Label12: TLabel;
    ListBoxGroupHeader4: TListBoxGroupHeader;
    Rectangle3: TRectangle;
    Label13: TLabel;
    ListBoxGroupHeader1: TListBoxGroupHeader;
    Rectangle4: TRectangle;
    Label14: TLabel;
    ListBoxGroupHeader5: TListBoxGroupHeader;
    Rectangle5: TRectangle;
    Label15: TLabel;
    ListBoxItem6: TListBoxItem;
    ModelCapabilitiesCombo: TCalloutRectangle;
    ChModelImage: TCheckBox;
    ChModelVideo: TCheckBox;
    ChModelAudio: TCheckBox;
    ChModelPDF: TCheckBox;
    AIVoiceMonitor1: TAIVoiceMonitor;
    AIWhisper1: TAIWhisper;
    ListBoxGroupHeader6: TListBoxGroupHeader;
    Rectangle6: TRectangle;
    Label16: TLabel;
    ListBoxItem20: TListBoxItem;
    ChEnableListening: TCheckBox;
    ListBoxItem21: TListBoxItem;
    ChEnableWordDetection: TCheckBox;
    ListBoxItem22: TListBoxItem;
    Label17: TLabel;
    EditWakeWord: TEdit;
    ListBoxItem23: TListBoxItem;
    ChSendAudioToIA: TCheckBox;
    MenuBar1: TMenuBar;
    MnuFile: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MnuSaveToFile: TMenuItem;
    MnuLoadFromFile: TMenuItem;
    MnuNewChat: TMenuItem;
    ToolBar1: TToolBar;
    BtnNewChat: TButton;
    BtnSaveDataBase: TButton;
    BtnOpenDataBase: TButton;
    BtnSaveChat: TButton;
    BtnOpenChat: TButton;
    ImageList1: TImageList;
    ActionList1: TActionList;
    ac_NewChat: TAction;
    Image1: TImage;
    Image2: TImage;
    Image3: TImage;
    Image4: TImage;
    Image5: TImage;
    AiFunctions1: TAiFunctions;
    AiRAGVector1: TAiRAGVector;
    ac_LoadChatFromFile: TAction;
    ac_SaveChatToFile: TAction;
    ac_LoadKnowledgeFromFile: TAction;
    ac_SaveKnowledgeToFile: TAction;
    ac_AddItemToDatabase: TAction;
    ac_Config: TAction;
    BtnConfig: TButton;
    Image6: TImage;
    BtnAddItemToDatabase: TButton;
    Image7: TImage;
    BtnAbout: TButton;
    Image8: TImage;
    BtnHelp: TButton;
    Image9: TImage;
    ac_help: TAction;
    ac_about: TAction;
    MenuItem1: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem7: TMenuItem;
    MenuItem8: TMenuItem;
    OpenDialog1: TOpenDialog;
    AiOpenAiEmbeddings1: TAiOpenAiEmbeddings;
    Layout1: TLayout;
    LblLog: TLabel;
    ChatInput1: TChatInput;
    AniIndicator1: TAniIndicator;
    ac_LoadMCPConfig: TAction;
    BtnLoadMcpServerConfig: TButton;
    Image10: TImage;
    BtnShowBilling: TButton;
    Image11: TImage;
    AiOpenChat1: TAiOpenChat;
    Layout10: TLayout;
    MemoThinking: TMemo;
    Splitter1: TSplitter;
    ChModelAny: TCheckBox;
    ListBoxItem24: TListBoxItem;
    Label19: TLabel;
    EditThinkingTokens: TEdit;
    LayoutArtefacts: TLayout;
    TabControl1: TTabControl;
    TabUsageItem: TTabItem;
    TabShellTool: TTabItem;
    TabEditTool: TTabItem;
    MemoTokenUsageHistory: TMemo;
    MemoShellTool: TMemo;
    AiShell1: TAiShell;
    ListBoxItem25: TListBoxItem;
    ChShellTool: TCheckBox;
    ListBoxItem26: TListBoxItem;
    ChEditTool: TCheckBox;
    MemoEditTool: TMemo;
    SplitterArtefacts: TSplitter;
    Rectangle7: TRectangle;
    ListBoxItem27: TListBoxItem;
    Label22: TLabel;
    EditURL: TEdit;
    AiTextEditorTool1: TAiTextEditorTool;
    Layout4: TLayout;
    MemoEditCommandLog: TMemo;
    Splitter3: TSplitter;
    TabChatParams: TTabItem;
    MemoUsedChatParams: TMemo;
    Button2: TButton;
    Image12: TImage;
    Rectangle8: TRectangle;
    Label25: TLabel;
    Rectangle9: TRectangle;
    Label26: TLabel;
    Rectangle10: TRectangle;
    Label24: TLabel;
    Rectangle11: TRectangle;
    Label21: TLabel;
    Rectangle12: TRectangle;
    Label23: TLabel;
    Rectangle13: TRectangle;
    Label20: TLabel;
    Layout5: TLayout;
    EditCaption: TEdit;
    Edit1: TEdit;
    BtnJSonShema: TSpeedButton;
    AiPrompts1: TAiPrompts;
    AiGeminiChat1: TAiGeminiChat;
    AiComputerUseTool1: TAiComputerUseTool;
    ListBoxItem28: TListBoxItem;
    chComputerUse: TCheckBox;
    BtnSelectArea: TSpeedButton;
    AiOllamaChat1: TAiOllamaChat;
    ListBoxItem29: TListBoxItem;
    Label18: TLabel;
    EditEnabledFeatures: TEdit;
    AiGenericChat1: TAiGenericChat;

    procedure ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
    procedure ChatList1MediaFileDblClick(Sender: TObject; const ABubble: TChatBubble; const AMediaFile: TAiMediaFile);
    procedure ChatList1BeforeAddBubble(Sender: TObject; ABubble: TChatBubble);
    procedure MnuCopyClick(Sender: TObject);
    procedure MnuSaveClick(Sender: TObject);
    procedure MnuPlayClick(Sender: TObject);
    procedure AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure AiConnError(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
    procedure FormCreate(Sender: TObject);
    procedure ComboDriverChange(Sender: TObject);
    procedure ComboModelsChange(Sender: TObject);
    procedure TrackTemperatureTracking(Sender: TObject);
    procedure ChatInput1Cancel(Sender: TObject);
    procedure ChModelImageChange(Sender: TObject);
    procedure EditChatMediaSupportsExit(Sender: TObject);
    procedure EditChatMediaSupportsEnter(Sender: TObject);
    procedure ChatInput1TranscriptText(Sender: TObject; aFragmentStream: TMemoryStream; out aTransriptText: string);
    procedure ChEnableListeningChange(Sender: TObject);
    procedure ChEnableWordDetectionChange(Sender: TObject);
    procedure EditWakeWordChange(Sender: TObject);
    procedure ac_NewChatExecute(Sender: TObject);
    procedure ac_LoadChatFromFileExecute(Sender: TObject);
    procedure ac_SaveChatToFileExecute(Sender: TObject);
    procedure ac_LoadKnowledgeFromFileExecute(Sender: TObject);
    procedure ac_SaveKnowledgeToFileExecute(Sender: TObject);
    procedure ac_AddItemToDatabaseExecute(Sender: TObject);
    procedure ac_ConfigExecute(Sender: TObject);
    procedure ac_helpExecute(Sender: TObject);
    procedure ac_aboutExecute(Sender: TObject);
    procedure BtnNewChatClick(Sender: TObject);
    procedure BtnOpenChatClick(Sender: TObject);
    procedure BtnSaveChatClick(Sender: TObject);
    procedure BtnOpenDataBaseClick(Sender: TObject);
    procedure BtnSaveDataBaseClick(Sender: TObject);
    procedure BtnAddItemToDatabaseClick(Sender: TObject);
    procedure BtnHelpClick(Sender: TObject);
    procedure BtnAboutClick(Sender: TObject);
    procedure BtnConfigClick(Sender: TObject);
    procedure AiFunctions1Functions0GetSystemDateTimeAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure AiFunctions1Functions1AddInfoToRAGAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure AiFunctions1Functions2SearchInRagAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure ac_LoadMCPConfigExecute(Sender: TObject);
    procedure BtnLoadMcpServerConfigClick(Sender: TObject);
    procedure BtnShowBillingClick(Sender: TObject);
    procedure AiConnReceiveThinking(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
    procedure ChShellToolChange(Sender: TObject);
    procedure ChEditToolChange(Sender: TObject);
    procedure AiShell1ConsoleLog(Sender: TObject; const Command, StdOut, StdErr: string; ExitCode: Integer);
    procedure AiTextEditorTool1BeforeCommand(Sender: TObject; const Command, Path: string; Args: TJSONObject; var Result: string; var Handled: Boolean);
    procedure AiTextEditorTool1EnsureDirectory(Sender: TObject; const Path: string; var Handled: Boolean);
    procedure AiTextEditorTool1FileExists(Sender: TObject; const Path: string; var Exists, Handled: Boolean);
    procedure AiTextEditorTool1LoadFile(Sender: TObject; const Path: string; var Content: string; var Handled: Boolean);
    procedure AiTextEditorTool1SaveFile(Sender: TObject; const Path, Content: string; var Handled: Boolean);
    procedure Button2Click(Sender: TObject);
    procedure BtnJSonShemaClick(Sender: TObject);
    procedure AiComputerUseTool1ExecuteAction(Sender: TObject; const ActionData: TAiActionData; var Result: TAiActionResult);
    procedure AiComputerUseTool1RequestScreenshot(Sender: TObject; var MediaFile: TAiMediaFile);
    procedure AiComputerUseTool1SafetyConfirmation(Sender: TObject; const Explanation: string; var Allow: Boolean);
    procedure BtnSelectAreaClick(Sender: TObject);
    procedure AiFunctions1Functions3AdicionaFacturaAlERPAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
    procedure EditEnabledFeaturesEnter(Sender: TObject);
    procedure EditEnabledFeaturesExit(Sender: TObject);
  private
    FLastBubble: TChatBubble;
    FPrompt_tokens: Integer;
    FCompletion_tokens: Integer;
    FTotal_tokens: Integer;
    FThinking_tokens: Integer;
    FActiveModelEdit: TEdit;
    FLastNewText: String;
    FJSonShema: String; // Temporarily stores the jsonshemma
    FNoImage: Integer; // Temporary for image capture;
    FSafetyState: TSafetyState; // State of the computer use safety

    Function CopyToClipBoard(AMediaFile: TAiMediaFile): Boolean;
    Procedure AssignModel(Const DriverName, ModelName: String);
    Procedure InitModelCapabilitiesCombo(Edit: TEdit);
    Procedure AssignAiConnParams;
    function PackString(const Texto: string): TMemoryStream; // to compress output files
    function UnpackString(StreamComprimido: TStream): string; // to decompress output files
    Function PackStream(StreamOrigen: TStream): TMemoryStream;
    Function UnpackStream(StreamComprimido: TStream): TMemoryStream;
    procedure SaveCombinedChatToStream(AContainerStream: TStream; AChatUIStream, AHistoryStream: TStream);
    procedure LoadCombinedChatFromStream(AContainerStream: TStream; out AChatUIStream: TStream; out AHistoryStream: TStream);
    procedure SaveRAGToStream(AContainerStream: TStream; ASourceDataStream: TStream);
    function LoadRAGFromStream(AContainerStream: TStream): TMemoryStream;
    Procedure AddLog(Value: String);
    //procedure LoadMCPClientsFromJSON(AJsonString: string; AFunctions: TAiFunctions);
    function WebSearchToString(AWebSearch: TAiWebSearch): String; // Retrieves web search details
  public
    Procedure ShowArtefacts(Visible: Boolean);
    Procedure InitChats;  //Parameterizes models by default
  end;

var
  Form2: TForm2;

implementation

{$R *.fmx}

uses uMemoPropertiesEdit;

const
  // Versioning options for the format created for this model.
  MKCHAT_MAGIC_HEADER: array [0 .. 3] of AnsiChar = 'MKCH';
  MKCHAT_FORMAT_VERSION: Word = 1;

  MKRAG_MAGIC_HEADER: array [0 .. 3] of AnsiChar = 'MKRG';
  MKRAG_FORMAT_VERSION: Word = 1;

procedure LogPruebas(const Mensaje: string);
var
  Archivo: TextFile;
  RutaLog: string;
begin
  // ---------------------------------------------------------------------------------
  // -------- DISABLED OPTION IS ONLY A TEST LOG--------------------------
  // ---------------------------------------------------------------------------------

  { RutaLog := 'd:\videos\logPruebas.txt';

    try
    AssignFile(Archivo, RutaLog);

    // If the file exists, it opens it for appending; if not, it creates it
    if FileExists(RutaLog) then
    Append(Archivo)
    else
    Rewrite(Archivo);

    // Writes the line with date/time
    // WriteLn(Archivo, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - ' + Mensaje);
    WriteLn(Archivo, Mensaje);

    finally
    CloseFile(Archivo);
    end;
  }
end;

procedure TForm2.ac_aboutExecute(Sender: TObject);
Var
  Bm: TBitMap;
  FileName: String;
begin
  // ---------------------------------------------------------------------------------
  // -------- DISABLED OPTION IS ONLY A TEST LOG--------------------------
  // ---------------------------------------------------------------------------------

  { Inc(FNoImage);
    Bm := TScreenCapture.CaptureFullScreen;
    FileName := Edit1.Text + ':' + '_' + FNoImage.ToString + '_' + EditCaption.Text;
    FileName := StringReplace(FileName, ' ', '_', [rfReplaceAll]);
    FileName := StringReplace(FileName, ':', '_', [rfReplaceAll]);
    FileName := 'D:\Videos\' + FileName + '.png';
    TScreenCapture.SaveToFile(Bm, FileName)
  }
end;

procedure TForm2.ac_AddItemToDatabaseExecute(Sender: TObject);
begin
  //
end;

procedure TForm2.ac_ConfigExecute(Sender: TObject);
begin
  //
end;

procedure TForm2.ac_helpExecute(Sender: TObject);
begin
  //
end;

procedure TForm2.ac_LoadChatFromFileExecute(Sender: TObject);
var
  LUIStream, LHistoryStream: TStream;
  LFileStream: TFileStream;
begin
  OpenDialog1.DefaultExt := '.mkchat';
  OpenDialog1.Filter := 'MKChat Files (*.mkchat)|*.mkchat|All Files (*.*)|*.*';
  OpenDialog1.Title := 'Load Chat Session';

  if OpenDialog1.Execute then
  begin
    LUIStream := nil;
    LHistoryStream := nil;
    LFileStream := TFileStream.Create(OpenDialog1.FileName, fmOpenRead);
    try
      // 1. Use our helper procedure to unpack
      LoadCombinedChatFromStream(LFileStream, LUIStream, LHistoryStream);

      // 2. Load each part into its corresponding component
      if Assigned(LUIStream) then
      begin
        LUIStream.Position := 0;
        ChatList1.LoadFromStream(LUIStream);
      end;

      if Assigned(LHistoryStream) then
      begin
        LHistoryStream.Position := 0;
        // Assuming AiConn.Messages has a LoadFromStream method
        AiConn.Messages.LoadFromStream(LHistoryStream);
      end;

    finally
      // LoadCombinedChatFromStream crea nuevas instancias, debemos liberarlas
      LUIStream.Free;
      LHistoryStream.Free;
      LFileStream.Free;
    end;
  end;
end;

procedure TForm2.ac_LoadKnowledgeFromFileExecute(Sender: TObject);
var
  LDataStream: TMemoryStream;
  LFileStream: TFileStream;
begin
  OpenDialog1.DefaultExt := '.mkrag';
  OpenDialog1.Filter := 'MKRAG Files (*.mkrag)|*.mkrag|All Files (*.*)|*.*';
  OpenDialog1.Title := 'Load RAG Vector Data';

  if OpenDialog1.Execute then
  begin
    LDataStream := nil;
    LFileStream := TFileStream.Create(OpenDialog1.FileName, fmOpenRead);
    try
      // 1. Use our helper function to read and decompress
      LDataStream := LoadRAGFromStream(LFileStream);

      // 2. If everything went well, LDataStream contains the data ready to use
      if Assigned(LDataStream) then
      begin
        AiRAGVector1.LoadFromStream(LDataStream);
        ShowMessage('Knowledge database loaded "' + OpenDialog1.FileName + '"');
      end;
    finally
      // We free the streams. LDataStream was created by LoadRAGFromStream.
      LDataStream.Free;
      LFileStream.Free;
    end;
  end;
end;

procedure TForm2.ac_LoadMCPConfigExecute(Sender: TObject);
var
  LImportedCount: Integer;
begin
  // 1. Configure the dialog
  OpenDialog1.DefaultExt := '.json';
  OpenDialog1.Filter := 'JSON Files (*.json)|*.json|MCP Config (*.mcpconf)|*.mcpconf|All Files (*.*)|*.*';
  OpenDialog1.Title := 'Select MCP configuration file';
  OpenDialog1.InitialDir := '%APPDATA%\Claude\';
  OpenDialog1.FileName := 'claude_desktop_config.json';

  if OpenDialog1.Execute then
  begin
    try
      // 2. DELEGACIÓN TOTAL:
      // We call the component method passing the file path.
      // The component takes care of reading the file, parsing it, creating the clients
      // and synchronizing the internal engines.
      LImportedCount := AiFunctions1.ImportClaudeMCPConfiguration(OpenDialog1.FileName);

      // 3. Feedback based on the result
      if LImportedCount > 0 then
      begin
        AddLog(Format('Success: %d MCP servers imported from %s',
               [LImportedCount, ExtractFileName(OpenDialog1.FileName)]));

        ShowMessage(Format('Configuration loaded successfully.'#13#10 +
                           'Imported servers: %d', [LImportedCount]));
      end
      else
      begin
        AddLog('Warning: The file was read but no valid MCP servers were found.');
        ShowMessage('No MCP server configurations were found in the selected file.');
      end;

    except
      on E: Exception do
      begin
        AddLog('ERROR importing MCP: ' + E.Message);
        ShowMessage('Error processing configuration file:' + sLineBreak + E.Message);
      end;
    end;
  end;
end;

procedure TForm2.ac_NewChatExecute(Sender: TObject);
begin
  AiConn.NewChat;
  ChatList1.Clear;
  AiRAGVector1.Clear;
  MemoThinking.Lines.Clear;
end;

procedure TForm2.ac_SaveChatToFileExecute(Sender: TObject);
var
  LUIStream: TMemoryStream;
  LHistoryStream: TMemoryStream;
  LFileStream: TFileStream;
begin
  SaveDialog1.DefaultExt := '.mkchat';
  SaveDialog1.Filter := 'MKChat Files (*.mkchat)|*.mkchat|All Files (*.*)|*.*';
  SaveDialog1.Title := 'Save Chat Session';

  if SaveDialog1.Execute then
  begin
    LUIStream := TMemoryStream.Create;
    try
      LHistoryStream := TMemoryStream.Create;
      try
        // 1. Save each part in its own stream in memory
        ChatList1.SaveToStream(LUIStream);
        AiConn.Messages.SaveToStream(LHistoryStream);

        // 2. Create the destination file
        LFileStream := TFileStream.Create(SaveDialog1.FileName, fmCreate);
        try
          // 3. Use our helper procedure to pack them
          SaveCombinedChatToStream(LFileStream, LUIStream, LHistoryStream);
        finally
          LFileStream.Free;
        end;
      finally
        LHistoryStream.Free;
      end;
    finally
      LUIStream.Free;
    end;
  end;
end;

procedure TForm2.ac_SaveKnowledgeToFileExecute(Sender: TObject);
var
  LSourceStream: TMemoryStream;
  LFileStream: TFileStream;
begin
  SaveDialog1.DefaultExt := '.mkrag';
  SaveDialog1.Filter := 'MKRAG Files (*.mkrag)|*.mkrag|All Files (*.*)|*.*';
  SaveDialog1.Title := 'Save RAG Vector Data';

  if SaveDialog1.Execute then
  begin
    LSourceStream := TMemoryStream.Create;
    try
      // 1. Get the RAG data in a stream
      AiRAGVector1.SaveToStream(LSourceStream);

      LFileStream := TFileStream.Create(SaveDialog1.FileName, fmCreate);
      try
        // 2. Use our helper function to save in the correct format
        SaveRAGToStream(LFileStream, LSourceStream);
      finally
        LFileStream.Free;
      end;
    finally
      LSourceStream.Free;
    end;
  end;
end;

procedure TForm2.AddLog(Value: String);
begin
  TThread.Queue(nil,
    procedure
    begin
      LblLog.Text := 'Log: ' + Value;
    end);

end;

procedure TForm2.AiComputerUseTool1ExecuteAction(Sender: TObject; const ActionData: TAiActionData; var Result: TAiActionResult);
begin
  // A single line to delegate all the dirty work
  Result := TAiWindowsFMXExecutor.Execute(ActionData);

  // Opcional: Loguear en un Memo
  MemoEditTool.Lines.Add(Format('Windows action executed: %s (Success: %s)', [ActionData.FunctionName, BoolToStr(Result.Success, True)]));
end;

procedure TForm2.AiComputerUseTool1RequestScreenshot(Sender: TObject; var MediaFile: TAiMediaFile);
var
  R: TRect;
begin
  // Defines the rectangle based on the component configuration
  R := Rect(AiComputerUseTool1.AreaLeft, AiComputerUseTool1.AreaTop, AiComputerUseTool1.AreaLeft + AiComputerUseTool1.AreaWidth, AiComputerUseTool1.AreaTop + AiComputerUseTool1.AreaHeight);

  // Calls the new FMX Windows Executor unit
  TAiWindowsFMXExecutor.CaptureScreen(MediaFile, R, 70);
end;

procedure TForm2.AiComputerUseTool1SafetyConfirmation(Sender: TObject; const Explanation: string; var Allow: Boolean);
begin
  // 1. We initialize the state variable "flag"
  FSafetyState := stWaiting;

  // 2. We trigger the UI on the main thread asynchronously (Queue)
  // We use Queue instead of Synchronize to fire and forget.
  TThread.Queue(nil,
    procedure
    begin
      // This code runs on the Main Thread (UI)
      MessageDlg('[!] Gemini requests security confirmation.' + sLineBreak + 'Reason: ' + Explanation, TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0,
        // Anonymous callback that runs when the dialog closes
        procedure(const AResult: TModalResult)
        begin
          if AResult = mrYes then
            FSafetyState := stAllow
          else
            FSafetyState := stDeny;
        end);
    end);

  // 3. Wait loop on the secondary thread (Background Thread)
  // We wait until the variable changes state.
  while FSafetyState = stWaiting do
  begin
    // Important: Sleep to avoid consuming 100% CPU in the empty loop
    Sleep(100);

    // Optional: Check if the thread was terminated to avoid hang
    if TThread.CurrentThread.CheckTerminated then
      Exit;
  end;

  // 4. We assign the final result
  Allow := (FSafetyState = stAllow);
end;

procedure TForm2.AiConnError(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
begin

  TThread.Queue(nil,
    procedure
    begin
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;
      ChatInput1.Busy := False;
      ShowMessage(ErrorMsg);
    end);
end;

procedure TForm2.AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin

  if Not ChAsincrono.IsChecked then
    Exit;

  If aText = '' then
    Exit;

  TThread.Queue(nil,
    procedure
    begin
      If Assigned(FLastBubble) then
        FLastBubble.AppendText(aText)
      Else
        FLastBubble := ChatList1.AddBubble(aText, aRole, Nil);

      ChatList1.RecalcSize;
    end);
end;

procedure TForm2.AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin

  For Var MF in aMsg.MediaFiles do
  Begin
    MF.SaveToFile('miarchivo');
  End;

  TThread.Queue(nil,
    procedure
    begin
      ChatInput1.Busy := False;
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;
    end);

  MemoTokenUsageHistory.Lines.Add(Format('Model: %s, Input: %d, Output %d, Total: %d', [aMsg.Model, aMsg.Prompt_tokens, aMsg.Completion_tokens, aMsg.Total_tokens]));

  FPrompt_tokens := FPrompt_tokens + aMsg.Prompt_tokens;
  FCompletion_tokens := FCompletion_tokens + aMsg.Completion_tokens;
  FTotal_tokens := FTotal_tokens + aMsg.Total_tokens;
  FThinking_tokens := FThinking_tokens + aMsg.Thinking_tokens;

  EditPromptTokens.Text := Format('%d', [FPrompt_tokens]);
  EditCompletionTokens.Text := Format('%d', [FCompletion_tokens]);
  EditTotalTokens.Text := Format('%d', [FTotal_tokens]);
  EditThinkingTokens.Text := Format('%d', [FThinking_tokens]);
  EditCompletionModel.Text := aMsg.Model;

  // aMsg.Model;

  TThread.Queue(nil,
    procedure
    begin
      if Not ChAsincrono.IsChecked then
        FLastBubble := ChatList1.AddBubble(aText, aRole, aMsg.MediaFiles)
      else
      Begin

        If aMsg.MediaFiles.Count > 0 then
        Begin
          // If Assigned(FLastBubble) then
          // FLastBubble.AddContent('', aMsg.MediaFiles)
          // Else
          FLastBubble := ChatList1.AddBubble('', aRole, aMsg.MediaFiles);
        End;
      End;

      // Adds web search details, additional source info
      If Assigned(aMsg.WebSearchResponse) and (aMsg.WebSearchResponse.annotations.Count > 0) then
      Begin
        Var
        WebRes := WebSearchToString(aMsg.WebSearchResponse);
        If Assigned(FLastBubble) then
          FLastBubble.AppendText(WebRes);
      End;

      // Adds the transcription in (transcriptions or image generation)

      For Var MF in aMsg.MediaFiles do
      Begin

        If MF.Transcription <> '' then
        Begin
          If Assigned(FLastBubble) then
            FLastBubble.AppendText(MF.Transcription)
          else
            FLastBubble := ChatList1.AddBubble(MF.Transcription, aRole, Nil);
        End;
      End;

      FLastBubble := Nil;
    end);

  TTask.Run(
    procedure
    begin
      Try
        Sleep(2000);

        LogPruebas('');
        LogPruebas('Result: ' + aRole);
        LogPruebas('   ' + aText);
        LogPruebas('');
        LogPruebas('-----------------------------------------------------------------------------------------------');

        ac_aboutExecute(Nil);
      Except

      End;
    end);

end;

procedure TForm2.AiConnReceiveThinking(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoThinking.BeginUpdate;
      Try
        MemoThinking.Lines.Text := MemoThinking.Lines.Text + aText;
        MemoThinking.GoToTextEnd;
      Finally
        MemoThinking.EndUpdate;
      End;
    end);
end;

procedure TForm2.AiFunctions1Functions0GetSystemDateTimeAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  ToolCall.Response := FormatDateTime('YYYY-MM-DD  hh:nn:ss', Now);
  Handled := True;
end;

procedure TForm2.AiFunctions1Functions1AddInfoToRAGAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
Var
  InfoToSave: String;
begin
  AddLog('Adicionando a RAG..');
  Try
    InfoToSave := Trim(ToolCall.Params.Values['InfoToSave']);
    If InfoToSave <> '' then
    Begin
      Try
        AiRAGVector1.AddItem(InfoToSave);

        ToolCall.Response := 'Ok';

        AddLog('');

      Except
        ON E: Exception do
        Begin
          ToolCall.Response := E.Message;
          AddLog('Adicionando a RAG Error');

        End;
      End;
    End
    Else
      ToolCall.Response := 'The InfoToSave parameter cannot be empty';
  Finally
    AddLog('');
  End;

  Handled := True;

end;

procedure TForm2.AiFunctions1Functions2SearchInRagAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
Var
  SearchText: String;
begin
  AddLog('Consultando RAG..');
  Try

    SearchText := Trim(ToolCall.Params.Values['SearchText']);
    If SearchText <> '' then
    Begin
      Try
        ToolCall.Response := AiRAGVector1.SearchText(SearchText, 10, 0.3); // 0.3 is more permissive for the index handled by RAG

      Except
        ON E: Exception do
        Begin
          ToolCall.Response := E.Message;
        End;
      End;
    End
    Else
      ToolCall.Response := 'The SearchText parameter cannot be empty';
  Finally
    AddLog('');
  End;

  Handled := True;

end;

procedure TForm2.AiFunctions1Functions3AdicionaFacturaAlERPAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: string; ToolCall: TAiToolsFunction; var Handled: Boolean);
Var
  sJson: String;
begin

end;

procedure TForm2.AiShell1ConsoleLog(Sender: TObject; const Command, StdOut, StdErr: string; ExitCode: Integer);
begin
  // We capture the data needed for the main thread
  // TThread.Queue takes an anonymous method
  TThread.Queue(nil,
    procedure
    begin
      // --- HERE INSIDE WE ARE ALREADY ON THE MAIN THREAD (UI) ---

      // 1. Pintar Comando
      MemoShellTool.Lines.Add(Format('root@makerai:~$ %s', [Command]));

      // 2. Pintar Salidas
      if StdOut <> '' then
      Begin
        Var
        aStdOut := StringReplace(StdOut, #$A, #$D#$A, [rfReplaceAll]);
        MemoShellTool.Lines.Add(aStdOut);
      End;

      if StdErr <> '' then
        MemoShellTool.Lines.Add('ERROR: ' + StdErr);

      // 3. Scroll to the end (VCL version)
      MemoShellTool.GoToTextEnd;
    end);
end;

procedure TForm2.AssignAiConnParams;

// Helper to build the sets []
  procedure AddToSet(var ASetString: String; const AValue: String);
  begin
    if ASetString = '' then
      ASetString := AValue
    else
      ASetString := ASetString + ',' + AValue;
  end;

var
  ModelCaps, SessionCaps: String;
  Opt, sUrl: String;
begin
  AiConn.Params.BeginUpdate;
  try
    AiConn.Params.Clear;

    // --- 1. BASIC CONFIGURATION ---
    sUrl := Trim(EditURL.Text);
    if sUrl <> '' then
      AiConn.Params.Values['Url'] := sUrl;

    AiConn.Params.Values['Tool_Active'] := BoolToStr(ChUseTools.IsChecked, True);
    AiConn.Params.Values['Asynchronous'] := BoolToStr(ChAsincrono.IsChecked, True);
    AiConn.Params.Values['Max_Tokens'] := StrToIntDef(EditMaxTokens.Text, 8000).ToString;
    AiConn.Params.Values['Temperature'] := FloatToStr(TrackTemperature.Value / 10);
    AiConn.Params.Values['Voice'] := EditVoices.Text;
    AiConn.Params.Values['Voice_Format'] := EditVoiceFormat.Text;

    // --- 2. ENUMERADOS ---
    if ChJSonFormat.IsChecked then
      AiConn.Params.Values['Response_format'] := IfThen(FJSonShema <> '', 'tiaChatRfJsonSchema', 'tiaChatRfJson')
    else
      AiConn.Params.Values['Response_format'] := 'tiaChatRfText';

    if (FJSonShema <> '') and ChJSonFormat.IsChecked then
      AiConn.Params.Values['JsonSchema'] := FJSonShema;

    AiConn.Params.Values['ThinkingLevel'] := GetEnumName(TypeInfo(TAiThinkingLevel), Max(0, EditThinkingLevel.ItemIndex));

    // --- 3. ModelCaps (new system v3.3) ---
    // EditChatMediaSupports -> input media caps that the model supports natively
    // EditNativeInputFiles  -> native GENERATION caps of the model
    //                          (e.g., cap_GenImage for Gemini image via completions)
    ModelCaps := '';

    Opt := LowerCase(EditChatMediaSupports.Text);
    if Opt.Contains('image') then AddToSet(ModelCaps, 'cap_Image');
    if Opt.Contains('audio') then AddToSet(ModelCaps, 'cap_Audio');
    if Opt.Contains('video') then AddToSet(ModelCaps, 'cap_Video');
    if Opt.Contains('pdf')   then AddToSet(ModelCaps, 'cap_Pdf');

    // Native tools of the model
    if ChWebSearch.IsChecked       then AddToSet(ModelCaps, 'cap_WebSearch');
    if ChCodeInterpreter.IsChecked then AddToSet(ModelCaps, 'cap_CodeInterpreter');
    if chComputerUse.IsChecked     then AddToSet(ModelCaps, 'cap_ComputerUse');
    if ChShellTool.IsChecked       then AddToSet(ModelCaps, 'cap_Shell');
    if ChEditTool.IsChecked        then AddToSet(ModelCaps, 'cap_TextEditor');

    // Native generation of the model (EditNativeInputFiles repurposed)
    Opt := LowerCase(EditNativeInputFiles.Text);
    if Opt.Contains('image') then AddToSet(ModelCaps, 'cap_GenImage');
    if Opt.Contains('audio') then AddToSet(ModelCaps, 'cap_GenAudio');
    if Opt.Contains('video') then AddToSet(ModelCaps, 'cap_GenVideo');

    // --- 4. SessionCaps (new system v3.3) ---
    // EditEnabledFeatures   -> desired input media caps in session
    // EditNativeOutputFiles -> caps de GENERACION deseados
    //                          Gap = SessionCaps - ModelCaps activa bridge/tool automaticamente
    SessionCaps := '';

    Opt := LowerCase(EditEnabledFeatures.Text);
    if Opt.Contains('image') then AddToSet(SessionCaps, 'cap_Image');
    if Opt.Contains('audio') then AddToSet(SessionCaps, 'cap_Audio');
    if Opt.Contains('video') then AddToSet(SessionCaps, 'cap_Video');
    if Opt.Contains('pdf')   then AddToSet(SessionCaps, 'cap_Pdf');

    // Desired tools in the session
    if ChWebSearch.IsChecked       then AddToSet(SessionCaps, 'cap_WebSearch');
    if ChCodeInterpreter.IsChecked then AddToSet(SessionCaps, 'cap_CodeInterpreter');
    if chComputerUse.IsChecked     then AddToSet(SessionCaps, 'cap_ComputerUse');
    if ChShellTool.IsChecked       then AddToSet(SessionCaps, 'cap_Shell');
    if ChEditTool.IsChecked        then AddToSet(SessionCaps, 'cap_TextEditor');

    // Generacion deseada en sesion
    Opt := LowerCase(EditNativeOutputFiles.Text);
    if Opt.Contains('image') then AddToSet(SessionCaps, 'cap_GenImage');
    if Opt.Contains('audio') then AddToSet(SessionCaps, 'cap_GenAudio');
    if Opt.Contains('video') then AddToSet(SessionCaps, 'cap_GenVideo');

    if ChExtractFiles.IsChecked    then AddToSet(SessionCaps, 'cap_ExtractCode');

    // --- 5. FINAL ASSIGNMENT (new system v3.3) ---
    AiConn.Params.Values['ModelCaps']   := '[' + ModelCaps + ']';
    AiConn.Params.Values['SessionCaps'] := '[' + SessionCaps + ']';

    // Log visual
    MemoUsedChatParams.Lines.Assign(AiConn.Params);
    MemoUsedChatParams.Lines.Insert(0, 'Model: ' + AiConn.Model);
    MemoUsedChatParams.Lines.Insert(0, 'Driver: ' + AiConn.DriverName);

  finally
    AiConn.Params.EndUpdate;
  end;
end;

procedure TForm2.AssignModel(const DriverName, ModelName: String);

// Helper: extracts input media caps (cap_Image, cap_Audio, cap_Video, cap_Pdf)
// from ModelCaps or SessionCaps in format [cap_Image,cap_Audio,...]
  function BuildMediaString(const AParamValue: String): String;
  var
    LConf: String;
    Parts: TStringList;
  begin
    Result := '';
    LConf := LowerCase(AParamValue);
    Parts := TStringList.Create;
    try
      // 'cap_image' y 'cap_genimage' son substrings distintos, no hay colision
      if LConf.Contains('cap_image') then Parts.Add('Image');
      if LConf.Contains('cap_audio') then Parts.Add('Audio');
      if LConf.Contains('cap_video') then Parts.Add('Video');
      if LConf.Contains('cap_pdf')   then Parts.Add('Pdf');
      Result := Parts.CommaText;
    finally
      Parts.Free;
    end;
  end;

// Auxiliar: extrae caps de generacion (cap_GenImage, cap_GenAudio, cap_GenVideo)
  function BuildGenString(const AParamValue: String): String;
  var
    LConf: String;
    Parts: TStringList;
  begin
    Result := '';
    LConf := LowerCase(AParamValue);
    Parts := TStringList.Create;
    try
      if LConf.Contains('cap_genimage')  then Parts.Add('Image');
      if LConf.Contains('cap_genaudio')  then Parts.Add('Audio');
      if LConf.Contains('cap_genvideo')  then Parts.Add('Video');
      if LConf.Contains('cap_genreport') then Parts.Add('Report');
      Result := Parts.CommaText;
    finally
      Parts.Free;
    end;
  end;

var
  LParams: TStrings;
  LModelCaps, LSessionCaps: String;
begin
  // 1. DRIVER ASSIGNMENT (loads DefaultParams from the Factory into AiConn.Params)
  AiConn.DriverName := DriverName;
  AiConn.Model := ModelName;

  // Direct access to abbreviate
  LParams := AiConn.Params;

  // 2. VALORES ESCALARES (UI)
  EditURL.Text := LParams.Values['Url'];
  EditMaxTokens.Text := LParams.Values['Max_Tokens'];

  // Temperatura: de 0.7 (float) a 7 (trackbar)
  TrackTemperature.Value := StrToFloatDef(LParams.Values['Temperature'], 0.7) * 10;

  ChAsincrono.IsChecked := StrToBoolDef(LParams.Values['Asynchronous'], False);
  ChUseTools.IsChecked := StrToBoolDef(LParams.Values['Tool_Active'], False);

  // Formato JSON
  ChJSonFormat.IsChecked := SameText(LParams.Values['Response_format'], 'tiaChatRfJson') or SameText(LParams.Values['Response_format'], 'tiaChatRfJsonSchema');
  FJSonShema := LParams.Values['JsonSchema'];

  // Voz
  EditVoices.Text := LParams.Values['Voice'];
  EditVoiceFormat.Text := LParams.Values['Voice_Format'];

  // Thinking Level (Enum)
  EditThinkingLevel.ItemIndex := Max(0, GetEnumValue(TypeInfo(TAiThinkingLevel), LParams.Values['ThinkingLevel']));

  // 3. CAPABILITIES - new system v3.3 (ModelCaps / SessionCaps)
  LModelCaps   := LowerCase(LParams.Values['ModelCaps']);
  LSessionCaps := LowerCase(LParams.Values['SessionCaps']);

  // Tool checkboxes (from ModelCaps)
  ChWebSearch.IsChecked       := LModelCaps.Contains('cap_websearch');
  ChCodeInterpreter.IsChecked := LModelCaps.Contains('cap_codeinterpreter');
  chComputerUse.IsChecked     := LModelCaps.Contains('cap_computeruse');
  ChShellTool.IsChecked       := LModelCaps.Contains('cap_shell');
  ChEditTool.IsChecked        := LModelCaps.Contains('cap_texteditor');
  // cap_ExtractCode belongs to SessionCaps (output cap, not model)
  ChExtractFiles.IsChecked    := LSessionCaps.Contains('cap_extractcode');

  // 4. CAMPOS DE CAPACIDADES DE MEDIOS (Edits)
  // EditChatMediaSupports -> ModelCaps: native input media of the model
  // EditNativeInputFiles  -> ModelCaps: generacion nativa (Gemini image, etc.)
  // EditEnabledFeatures   -> SessionCaps: input media deseado en sesion
  // EditNativeOutputFiles -> SessionCaps: generacion deseada (Gap activa bridge)
  EditChatMediaSupports.Text := BuildMediaString(LParams.Values['ModelCaps']);
  EditNativeInputFiles.Text  := BuildGenString(LParams.Values['ModelCaps']);
  EditEnabledFeatures.Text   := BuildMediaString(LParams.Values['SessionCaps']);
  EditNativeOutputFiles.Text := BuildGenString(LParams.Values['SessionCaps']);

  // Confirmation log in the UI
  AddLog(Format('Model loaded: %s (%s)', [ModelName, DriverName]));
end;

procedure TForm2.BtnNewChatClick(Sender: TObject);
begin
  ac_NewChatExecute(Sender);
end;

procedure TForm2.BtnConfigClick(Sender: TObject);
begin
  ac_ConfigExecute(Sender);
end;

procedure TForm2.BtnAddItemToDatabaseClick(Sender: TObject);
begin
  ac_AddItemToDatabaseExecute(Sender);
end;

procedure TForm2.BtnSaveDataBaseClick(Sender: TObject);
begin
  ac_SaveKnowledgeToFileExecute(Sender);
end;

procedure TForm2.BtnShowBillingClick(Sender: TObject);
begin
  ShowArtefacts(Not LayoutArtefacts.Visible);
  TabControl1.ActiveTab := TabUsageItem;
end;

procedure TForm2.Button2Click(Sender: TObject);
begin
  ShowArtefacts(Not LayoutArtefacts.Visible);
  TabControl1.ActiveTab := TabChatParams;
end;

procedure TForm2.BtnOpenDataBaseClick(Sender: TObject);
begin
  ac_LoadKnowledgeFromFileExecute(Sender);
end;

procedure TForm2.BtnSaveChatClick(Sender: TObject);
begin
  ac_SaveChatToFileExecute(Sender);
end;

procedure TForm2.BtnOpenChatClick(Sender: TObject);
begin
  ac_LoadChatFromFileExecute(Sender);
end;

procedure TForm2.BtnAboutClick(Sender: TObject);
begin
  ac_aboutExecute(Sender);
end;

procedure TForm2.BtnHelpClick(Sender: TObject);
begin
  ac_helpExecute(Sender);
end;

procedure TForm2.BtnLoadMcpServerConfigClick(Sender: TObject);
begin
  ac_LoadMCPConfigExecute(Self);
end;

procedure TForm2.ChatInput1Cancel(Sender: TObject);
begin
  AiConn.Abort;
  TThread.Queue(nil,
    procedure
    begin
      ChatInput1.Busy := False;
      AniIndicator1.Visible := False;
      AniIndicator1.Enabled := False;
    end);
end;

procedure TForm2.ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
Var
  MF: TAiMediaFile;
begin

  // These are the parameters with which the current request is executed
  AssignAiConnParams;

  // ---------------------------------------------------------------------------------
  // -------- DISABLED OPTION IS ONLY A TEST LOG--------------------------
  // ---------------------------------------------------------------------------------
  LogPruebas('');
  LogPruebas('Prueba: ' + EditCaption.Text);
  LogPruebas('');
  LogPruebas('Parameters:');

  For Var I := 0 to MemoUsedChatParams.Lines.Count - 1 do
  Begin
    Var
    S := MemoUsedChatParams.Lines[I];
    LogPruebas('   ' + S);
  End;

  LogPruebas('');
  LogPruebas('Prompt:');
  LogPruebas('   ' + APrompt);
  // ---------------------------------------------------------------------------------
  // ---------------------------------------------------------------------------------

  AniIndicator1.Visible := True;
  AniIndicator1.Enabled := True;

  // Clears memoThinking for the next call
  MemoThinking.Lines.Clear;

  If ChSendAudioToIA.IsChecked then
  Begin
    // If there is an audio recorded by the control, it is added, only if the communication is audio only since the text was transcribed in APrompt
    If Assigned(aAudioStream) and (aAudioStream.size > 100) then
    Begin
      MF := TAiMediaFile.Create;
      MF.LoadFromStream('miaudio.wav', aAudioStream);
      aMediaFiles.Add(MF);
    End;
  End
  Else
  Begin

  End;

  FLastBubble := Nil;
  ChatList1.AddBubble(APrompt, 'Usuario', aMediaFiles, False);

  TTask.Run(
    procedure
    begin
      Try
        // The result is obtained in the event to get the mediafiles if any
        AiConn.AddMessageAndRun(APrompt, 'user', aMediaFiles.ToMediaFileArray);

        TThread.Queue(nil,
          procedure
          begin
            Try

            Finally
            End;
          end);

      Except
        On E: Exception do
        Begin

        End;
      End;
    end);

end;

procedure TForm2.ChatInput1TranscriptText(Sender: TObject; aFragmentStream: TMemoryStream; out aTransriptText: string);
begin
  if Assigned(aFragmentStream) and (aFragmentStream.size > 100) then
    aTransriptText := Trim(AIWhisper1.Transcription(aFragmentStream, 'dummy.wav', 'user'));
end;

procedure TForm2.ChatList1BeforeAddBubble(Sender: TObject; ABubble: TChatBubble);
begin
  ABubble.MoreOptionsVisible := False;
  ABubble.HeaderVisible := False;
end;

procedure TForm2.ChatList1MediaFileDblClick(Sender: TObject; const ABubble: TChatBubble; const AMediaFile: TAiMediaFile);
begin
  ShowMessage(AMediaFile.FileName);
end;

procedure TForm2.ChEditToolChange(Sender: TObject);
begin
  ShowArtefacts(ChEditTool.IsChecked);

  If ChEditTool.IsChecked then
    TabControl1.ActiveTab := TabEditTool;
end;

procedure TForm2.ChEnableListeningChange(Sender: TObject);
begin
  ChatInput1.MicVisible := ChEnableListening.IsChecked;
end;

procedure TForm2.ChEnableWordDetectionChange(Sender: TObject);
begin
  AIVoiceMonitor1.WakeWordActive := ChEnableWordDetection.IsChecked;
end;

procedure TForm2.ChModelImageChange(Sender: TObject);
Var
  List: TStringList;
begin
  List := TStringList.Create;
  Try
    if ChModelImage.IsChecked then
      List.Add('Image');
    if ChModelAudio.IsChecked then
      List.Add('Audio');
    if ChModelVideo.IsChecked then
      List.Add('Video');
    if ChModelPDF.IsChecked then
      List.Add('PDF');
    if ChModelAny.IsChecked then
      List.Add('ANY');

    FActiveModelEdit.Text := List.CommaText;
  Finally
    List.Free;
  End;
end;

procedure TForm2.ChShellToolChange(Sender: TObject);
begin
  ShowArtefacts(ChShellTool.IsChecked);

  If ChShellTool.IsChecked then
    TabControl1.ActiveTab := TabShellTool;
end;

procedure TForm2.ComboDriverChange(Sender: TObject);
Var
  DriverName: String;
  List: TStringList;
begin
  If Assigned(ComboDriver.Selected) then
  Begin
    DriverName := Trim(ComboDriver.Text);

    Edit1.Text := DriverName;

    AiConn.DriverName := DriverName;
    Cursor := crHourGlass;
    EditURL.Text := '';

    ShowMessage(AiConn.Params.Text);

    List := AiConn.GetModels;
    Try
      List.Sort;
      ComboModels.Items.Text := List.Text;
    Finally
      List.Free;
      Cursor := crDefault;
    End;
  End;

end;

procedure TForm2.ComboModelsChange(Sender: TObject);
Var
  DriverName, ModelName: String;
begin
  If Assigned(ComboModels.Selected) then
  Begin
    DriverName := ComboDriver.Text;
    ModelName := ComboModels.Text;
    AssignModel(DriverName, ModelName);
  End;
end;

function TForm2.CopyToClipBoard(AMediaFile: TAiMediaFile): Boolean;
var
  ClipboardSvc: IFMXClipboardService;
  LBitmap: FMX.Graphics.TBitMap;
  LText: string;
begin
  Result := False;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, IInterface(ClipboardSvc)) then
    Exit; // No hay servicio de portapapeles disponible

  // Before any operation, make sure the stream is at the beginning.
  if Assigned(AMediaFile.Content) then
    AMediaFile.Content.Position := 0;

  // The copy logic depends on the file category
  case AMediaFile.FileCategory of
    Tfc_Image:
      begin
        if (AMediaFile.Content = nil) or (AMediaFile.Content.size = 0) then
          Exit;
        LBitmap := FMX.Graphics.TBitMap.Create;
        try
          LBitmap.LoadFromStream(AMediaFile.Content);
          ClipboardSvc.SetClipboard(LBitmap); // FMX knows how to put a TBitmap on the clipboard
          Result := True;
        finally
          LBitmap.Free;
        end;
      end;

    Tfc_Text, tfc_ExtracttextFile:
      begin
        if (AMediaFile.Content = nil) or (AMediaFile.Content.size = 0) then
          Exit;

        // We read the stream content as UTF-8 text (the most common)
        var
        LReader := TStreamReader.Create(AMediaFile.Content, TEncoding.UTF8);
        try
          LText := LReader.ReadToEnd;
          // We use TValue.From<string> to pass it to the clipboard as plain text
          ClipboardSvc.SetClipboard(TValue.From<string>(LText));
          Result := True;
        finally
          LReader.Free;
        end;
      end;

    // For other file types (PDF, DOC, Audio, etc.), the standard clipboard
    // has no "native" format for them. The best option is to copy
    // the file PATH if it exists, or do nothing.
    // In this case, since the content is in a TMemoryStream, there is no path
    // que podamos copiar que otra aplicación pueda entender.
    // Therefore, for these types, we do nothing and the method returns False.
  else
    Result := False;
  end;

  // We rewind the stream in case it needs to be reused later.
  if Assigned(AMediaFile.Content) then
    AMediaFile.Content.Position := 0;
end;

procedure TForm2.EditWakeWordChange(Sender: TObject);
begin
  AIVoiceMonitor1.WakeWord := Trim(LowerCase(EditWakeWord.Text));
end;

procedure TForm2.EditChatMediaSupportsEnter(Sender: TObject);
begin
  if Sender is TEdit then
    InitModelCapabilitiesCombo(Sender as TEdit);

  // Now we include the new field in the validation of the "Any" option
  ChModelAny.Visible := (Sender = EditNativeInputFiles) or (Sender = EditChatMediaSupports) or (Sender = EditEnabledFeatures);
end;

procedure TForm2.EditChatMediaSupportsExit(Sender: TObject);
begin
  ModelCapabilitiesCombo.Visible := False;
end;

procedure TForm2.EditEnabledFeaturesEnter(Sender: TObject);
begin
  // We initialize the capability selection combo for this Edit
  if Sender is TEdit then
    InitModelCapabilitiesCombo(TEdit(Sender));

  // As with ChatMediaSupports, we allow the "Any" option
  // to enable all logical functions at once.
  ChModelAny.Visible := True;
end;

procedure TForm2.EditEnabledFeaturesExit(Sender: TObject);
begin
  // We hide the selection panel when leaving focus
  ModelCapabilitiesCombo.Visible := False;
end;

procedure TForm2.FormCreate(Sender: TObject);
Var
  List: TStringList;
begin

  InitChats;

  FNoImage := 0;
  ShowArtefacts(False);

  FPrompt_tokens := 0;
  FCompletion_tokens := 0;
  FTotal_tokens := 0;
  FThinking_tokens := 0;

  ModelCapabilitiesCombo.Visible := False;

  // BtnJSonShema.Visible := False;  //Funcionalidad no implementada todavía

  Try
    List := AiConn.GetDriversNames;
    Try
      List.Sort;
      ComboDriver.Items.Text := List.Text;
      If ComboDriver.Items.Count > 0 then
        ComboDriver.ItemIndex := 0;
    Finally
      List.Free;
    End;
  Except

  End;
end;

procedure TForm2.InitChats;
begin
  // ===================================================================
  // DRIVER CONFIGURATION (new system v3.3 - ModelCaps/SessionCaps)
  // ===================================================================

  // Ollama: plain text by default, without native tools
  AiConn.RegisterUserParam('Ollama', 'Max_Tokens',   '8000');
  AiConn.RegisterUserParam('Ollama', 'Url',          'http://192.168.3.121:11434/');
  AiConn.RegisterUserParam('Ollama', 'Temperature',  '0.7');
  AiConn.RegisterUserParam('Ollama', 'Asynchronous', 'True');
  AiConn.RegisterUserParam('Ollama', 'Tool_Active',  'False');
  // Empty ModelCaps/SessionCaps = plain text, without special capabilities
  AiConn.RegisterUserParam('Ollama', 'ModelCaps',    '[]');
  AiConn.RegisterUserParam('Ollama', 'SessionCaps',  '[]');

  // GenericLLM: local endpoint configuration
  AiConn.RegisterUserParam('GenericLLM', 'Url',    'http://192.168.3.121:5050/v1/');
  AiConn.RegisterUserParam('GenericLLM', 'ApiKey', 'sk-demo-1234567890');

end;

procedure TForm2.InitModelCapabilitiesCombo(Edit: TEdit);
Var
  Opt: String;
  LocalPoint, ScreenPoint: TPointF;
begin
  FActiveModelEdit := Edit;

  ScreenPoint := Edit.LocalToScreen(Edit.Position.Point);
  LocalPoint := MainLayout.ScreenToLocal(ScreenPoint);

  // ModelCapabilitiesCombo.Parent := Edit;
  ModelCapabilitiesCombo.Position.Y := LocalPoint.Y - (Edit.Height * 1.5);
  ModelCapabilitiesCombo.Position.X := LocalPoint.X + Edit.Width;

  Opt := LowerCase(Edit.Text);
  ChModelImage.IsChecked := Opt.Contains('image');
  ChModelVideo.IsChecked := Opt.Contains('video');
  ChModelAudio.IsChecked := Opt.Contains('audio');
  ChModelPDF.IsChecked := Opt.Contains('pdf');
  ChModelAny.IsChecked := Opt.Contains('any');
  ModelCapabilitiesCombo.Visible := True;
end;

procedure TForm2.LoadCombinedChatFromStream(AContainerStream: TStream; out AChatUIStream, AHistoryStream: TStream);
var
  LHeader: array [0 .. 3] of AnsiChar;
  LVersion: Word;
  LCompressedStream: TMemoryStream;
  LSize: Int64;
begin
  AChatUIStream := nil;
  AHistoryStream := nil;
  AContainerStream.Position := 0;

  // 1. Validate header and version
  if (AContainerStream.Read(LHeader, SizeOf(LHeader)) <> SizeOf(LHeader)) or (not CompareMem(@LHeader, @MKCHAT_MAGIC_HEADER, SizeOf(LHeader))) then // *** CORRECTED LINE ***
    raise Exception.Create('Invalid .mkchat file format.');

  if (AContainerStream.Read(LVersion, SizeOf(LVersion)) <> SizeOf(LVersion)) or (LVersion <> MKCHAT_FORMAT_VERSION) then
    raise Exception.Create('Unsupported .mkchat file version.');

  // 2. Read the UI block
  if AContainerStream.Read(LSize, SizeOf(LSize)) <> SizeOf(LSize) then
    raise Exception.Create('Corrupted .mkchat file (UI size).');

  LCompressedStream := TMemoryStream.Create;
  try
    LCompressedStream.CopyFrom(AContainerStream, LSize);
    AChatUIStream := UnpackStream(LCompressedStream);
  finally
    LCompressedStream.Free;
  end;

  // 3. Read the History block
  if AContainerStream.Read(LSize, SizeOf(LSize)) <> SizeOf(LSize) then
    raise Exception.Create('Corrupted .mkchat file (History size).');

  LCompressedStream := TMemoryStream.Create;
  try
    LCompressedStream.CopyFrom(AContainerStream, LSize);
    AHistoryStream := UnpackStream(LCompressedStream);
  finally
    LCompressedStream.Free;
  end;
end;


{procedure TForm2.LoadMCPClientsFromJSON(AJsonString: string; AFunctions: TAiFunctions);
var
  LJson, LMcpServers, LServerConfig, LEnvObject: TJSONObject;
  LPair, LEnvPair: TJSONPair;
  LClientItem: TMCPClientItem;
  LServerName, LCommand: string;
  LArgsArray: TJSONArray;
  LArgsBuilder: TStringBuilder;
  I: Integer;
begin
  if not Assigned(AFunctions) then
    Exit;

  // 1. We clear the previous configuration to avoid conflicts
  AFunctions.MCPClients.Clear;
  AddLog('Starting MCP server loading from JSON...');

  LJson := nil;
  try
    Try
      // 2. Parse the JSON
      LJson := TJSONObject.ParseJSONValue(AJsonString) as TJSONObject;
      if not Assigned(LJson) then
      begin
        AddLog('Error: The provided JSON is not a valid object.');
        Exit;
      end;

      // 3. Access the root node "mcpServers"
      if not LJson.TryGetValue<TJSONObject>('mcpServers', LMcpServers) then
      begin
        AddLog('Error: The key "mcpServers" was not found in the JSON.');
        Exit;
      end;

      // 4. Iterate over the defined servers
      for LPair in LMcpServers do
      begin
        LServerName := LPair.JsonString.Value;
        LServerConfig := LPair.JsonValue as TJSONObject;

        // 5. Detect if it is a StdIo server (based on the presence of "command")
        if LServerConfig.TryGetValue<string>('command', LCommand) then
        begin
          AddLog(Format('Processing StdIo server: "%s"', [LServerName]));

          // Create the item in the collection
          LClientItem := AFunctions.MCPClients.Add;
          LClientItem.Name := LServerName;

          // Set the transport type FIRST
          LClientItem.TransportType := tpStdIo;

          // 6. Configure PARAMS (This is what the internal engine reads)
          // We use .Values['Key'] to ensure we overwrite or create the pair correctly
          LClientItem.Params.Values['Command'] := LCommand;

          // Process arguments if they exist
          if LServerConfig.TryGetValue<TJSONArray>('args', LArgsArray) then
          begin
            LArgsBuilder := TStringBuilder.Create;
            try
              for I := 0 to LArgsArray.Count - 1 do
              begin
                // We concatenate arguments with a space
                LArgsBuilder.Append(LArgsArray.Items[I].Value).Append(' ');
              end;
              LClientItem.Params.Values['Arguments'] := LArgsBuilder.ToString.Trim;
            finally
              LArgsBuilder.Free;
            end;
          end;

          // Important: Ensure RootDir is not null (use the default home as the IDE does)
          if LClientItem.Params.Values['RootDir'] = '' then
            LClientItem.Params.Values['RootDir'] := System.IOUtils.TPath.GetHomePath;

          // 7. Process Environment Variables (env)
          // These are critical so servers like SQLite or Postgres find their paths/keys
          if LServerConfig.TryGetValue<TJSONObject>('env', LEnvObject) then
          begin
            for LEnvPair in LEnvObject do
            begin
              LClientItem.EnvVars.Values[LEnvPair.JsonString.Value] := LEnvPair.JsonValue.Value;
            end;
          end;

          // 8. SINCRONIZACIÓN FINAL
          // We enable the client
          LClientItem.Enabled := True;

          // We call UpdateClientProperties so that TMCPClientItem
          // creates and initializes the internal TMCPClientStdIo with the Params and EnvVars we just filled.
          LClientItem.UpdateClientProperties;

          AddLog(Format('  - Server "%s" loaded and ready.', [LServerName]));
        end;
      end;

      AddLog('MCP StdIo configuration loading completed.');

    except
      on E: Exception do
        AddLog('Critical error during JSON loading: ' + E.Message);
    End;

  finally
    if Assigned(LJson) then
      LJson.Free;
  end;
end;
}

function TForm2.LoadRAGFromStream(AContainerStream: TStream): TMemoryStream;
var
  LHeader: array [0 .. 3] of AnsiChar;
  LVersion: Word;
  ZStream: TZDecompressionStream;
begin
  AContainerStream.Position := 0;

  if (AContainerStream.Read(LHeader, SizeOf(LHeader)) <> SizeOf(LHeader)) or (not CompareMem(@LHeader, @MKRAG_MAGIC_HEADER, SizeOf(LHeader))) then
    raise Exception.Create('Invalid .mkrag file format.');

  if (AContainerStream.Read(LVersion, SizeOf(LVersion)) <> SizeOf(LVersion)) or (LVersion <> MKRAG_FORMAT_VERSION) then
    raise Exception.Create('Unsupported .mkrag file version.');

  // The rest of the stream is the compressed data. We decompress it.
  Result := TMemoryStream.Create;
  // AContainerStream is already positioned right after the header.
  ZStream := TZDecompressionStream.Create(AContainerStream);
  try
    Result.CopyFrom(ZStream, 0);
    Result.Position := 0;
  finally
    ZStream.Free;
  end;
end;

procedure TForm2.MnuCopyClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
begin
  LMediaFile := ChatList1.ActiveMediaFile;

  if (LMediaFile <> nil) then
  begin
    // We simply call the method. All the complex logic is encapsulated!
    if CopyToClipBoard(LMediaFile) then
    begin
      // Optional: Notify the user that the copy was successful
      // ShowMessage('Content copied to clipboard.');
    end
    else
    begin
      // Optional: Notify if the file type is not copyable
      ShowMessage('This file type cannot be copied to the clipboard.');
    end;
  end;
end;

procedure TForm2.MnuPlayClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
  LTempPath: string;
  LFileStream: TFileStream;
  AppService: IFMXApplicationService;
begin
  // 1. Get the active file from TChatList
  LMediaFile := ChatList1.ActiveMediaFile;

  if LMediaFile = nil then
  begin
    ShowMessage('Error: No file has been selected.');
    Exit;
  end;

  // 2. Verify that the file has content to save
  if (LMediaFile.Content = nil) or (LMediaFile.Content.size = 0) then
  begin
    ShowMessage('The selected file is empty.');
    Exit;
  end;

  // 3. Build the temporary file path
  try
    LTempPath := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, LMediaFile.FileName);

    // 4. Save the stream content to the temporary file
    LMediaFile.Content.Position := 0; // Siempre rebobinar antes de leer
    LFileStream := TFileStream.Create(LTempPath, fmCreate);
    try
      LFileStream.CopyFrom(LMediaFile.Content, LMediaFile.Content.size);
    finally
      LFileStream.Free;
    end;
    LMediaFile.Content.Position := 0; // Leave it ready for future reads

    // 5. Use the platform service to open the file
    if TPlatformServices.Current.SupportsPlatformService(IFMXApplicationService, IInterface(AppService)) then
    begin
      if not TUtilsSystem.ShellOpenFile(LTempPath) then
      begin
        ShowMessage('The file could not be opened. Check if you have an application installed for this file type (' + System.IOUtils.TPath.GetExtension(LMediaFile.FileName) + ').');
      end;
    end
    else
    begin
      ShowMessage('The service for opening files is not available on this platform.');
    end;

  except
    on E: Exception do
    begin
      // Capture any error during file creation
      ShowMessage('An error occurred while trying to open the file: ' + E.Message);
    end;
  end;
end;

procedure TForm2.MnuSaveClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
begin
  LMediaFile := ChatList1.ActiveMediaFile;

  if (LMediaFile <> nil) then
  begin
    SaveDialog1.FileName := LMediaFile.FileName;
    If SaveDialog1.Execute then
      LMediaFile.SaveToFile(SaveDialog1.FileName);
  end;
end;

procedure TForm2.TrackTemperatureTracking(Sender: TObject);
begin
  LblTemperature.Text := 'Temperature: ' + FormatFloat('0.0', TrackTemperature.Value / 10);
end;

function TForm2.UnpackStream(StreamComprimido: TStream): TMemoryStream;
var
  ZStream: TZDecompressionStream;
begin
  Result := TMemoryStream.Create;
  StreamComprimido.Position := 0;

  // Decompress to the result stream
  ZStream := TZDecompressionStream.Create(StreamComprimido);
  try
    Result.CopyFrom(ZStream, 0);
  finally
    ZStream.Free;
  end;

  // Position the stream at the beginning for later use
  Result.Position := 0;
end;

function TForm2.UnpackString(StreamComprimido: TStream): string;
var
  StreamDestino: TMemoryStream;
  ZStream: TZDecompressionStream;
  Datos: TBytes;
begin
  StreamComprimido.Position := 0;
  StreamDestino := TMemoryStream.Create;
  try
    // Decompress the stream
    ZStream := TZDecompressionStream.Create(StreamComprimido);
    try
      StreamDestino.CopyFrom(ZStream, 0);
    finally
      ZStream.Free;
    end;

    // Convert the decompressed bytes to string
    StreamDestino.Position := 0;
    SetLength(Datos, StreamDestino.size);
    StreamDestino.ReadBuffer(Datos[0], StreamDestino.size);
    Result := TEncoding.UTF8.GetString(Datos);
  finally
    StreamDestino.Free;
  end;
end;

function TForm2.WebSearchToString(AWebSearch: TAiWebSearch): String;
var
  Sb: TStringBuilder;
  I: Integer;
  Item: TAiWebSearchItem;
begin
  Result := '';

  // 1. Validaciones de seguridad
  if not Assigned(AWebSearch) then
    Exit;
  if not Assigned(AWebSearch.annotations) then
    Exit;
  if AWebSearch.annotations.Count = 0 then
    Exit;

  Sb := TStringBuilder.Create;
  try
    Sb.AppendLine;
    Sb.AppendLine('--- Fuentes consultadas ---');

    // 2. Iterate over the annotations
    for I := 0 to AWebSearch.annotations.Count - 1 do
    begin
      Item := AWebSearch.annotations[I];

      // Format: [1] Site title
      // URL: https://...

      Sb.Append('[').Append(I + 1).Append('] ');

      if Item.Title <> '' then
        Sb.AppendLine(Item.Title)
      else
        Sb.AppendLine('No title');

      if Item.Url <> '' then
        Sb.Append('    Enlace: ').AppendLine(Item.Url);

      // Optional: Show indices if you are debugging where they fit in the text
      // Sb.AppendFormat('    (Index: %d - %d)', [Item.start_index, Item.end_index]);

      Sb.AppendLine;
    end;

    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TForm2.PackStream(StreamOrigen: TStream): TMemoryStream;
var
  ZStream: TZCompressionStream;
begin
  Result := TMemoryStream.Create;
  StreamOrigen.Position := 0;

  // Compress to the result stream
  ZStream := TZCompressionStream.Create(Result);
  try
    ZStream.CopyFrom(StreamOrigen, 0);
  finally
    ZStream.Free;
  end;

  // Position the stream at the beginning for later use
  Result.Position := 0;
end;

function TForm2.PackString(const Texto: string): TMemoryStream;
var
  StreamOrigen: TMemoryStream;
  ZStream: TZCompressionStream;
  Datos: TBytes;
begin
  Result := TMemoryStream.Create;
  StreamOrigen := TMemoryStream.Create;
  try
    // Convert the string to UTF-8 bytes
    Datos := TEncoding.UTF8.GetBytes(Texto);
    StreamOrigen.WriteBuffer(Datos[0], Length(Datos));
    StreamOrigen.Position := 0;

    // Compress to the result stream
    ZStream := TZCompressionStream.Create(Result);
    try
      ZStream.CopyFrom(StreamOrigen, 0);
    finally
      ZStream.Free;
    end;

    // Position the stream at the beginning for later use
    Result.Position := 0;
  finally
    StreamOrigen.Free;
  end;
end;

procedure TForm2.SaveCombinedChatToStream(AContainerStream, AChatUIStream, AHistoryStream: TStream);
var
  LCompressedUI: TMemoryStream;
  LCompressedHistory: TMemoryStream;
  LSize: Int64;
begin
  // 1. Compress both input streams
  LCompressedUI := PackStream(AChatUIStream);
  try
    LCompressedHistory := PackStream(AHistoryStream);
    try
      // 2. Write the header and version
      AContainerStream.Write(MKCHAT_MAGIC_HEADER, SizeOf(MKCHAT_MAGIC_HEADER));
      AContainerStream.Write(MKCHAT_FORMAT_VERSION, SizeOf(MKCHAT_FORMAT_VERSION));

      // 3. Write the UI block
      LSize := LCompressedUI.size;
      AContainerStream.Write(LSize, SizeOf(LSize)); // Write size
      LCompressedUI.Position := 0;
      AContainerStream.CopyFrom(LCompressedUI, 0); // Write data

      // 4. Write the History block
      LSize := LCompressedHistory.size;
      AContainerStream.Write(LSize, SizeOf(LSize)); // Write size
      LCompressedHistory.Position := 0;
      AContainerStream.CopyFrom(LCompressedHistory, 0); // Write data

    finally
      LCompressedHistory.Free;
    end;
  finally
    LCompressedUI.Free;
  end;
end;

procedure TForm2.SaveRAGToStream(AContainerStream: TStream; ASourceDataStream: TStream);
var
  ZStream: TZCompressionStream; // *** MODIFICADO ***
begin
  AContainerStream.WriteBuffer(MKRAG_MAGIC_HEADER, SizeOf(MKRAG_MAGIC_HEADER));
  AContainerStream.WriteBuffer(MKRAG_FORMAT_VERSION, SizeOf(MKRAG_FORMAT_VERSION));

  // We compress directly to the final stream for greater memory efficiency
  ASourceDataStream.Position := 0;
  ZStream := TZCompressionStream.Create(AContainerStream);
  try
    ZStream.CopyFrom(ASourceDataStream, 0);
  finally
    ZStream.Free;
  end;
end;

procedure TForm2.ShowArtefacts(Visible: Boolean);
begin
  If Not(ChShellTool.IsChecked or ChEditTool.IsChecked) then
  Begin
    LayoutArtefacts.Visible := Visible;
    SplitterArtefacts.Visible := Visible;
  End
  Else
  Begin
    Var
    Vis := ChShellTool.IsChecked or ChEditTool.IsChecked or Visible;
    LayoutArtefacts.Visible := Vis;
    SplitterArtefacts.Visible := Vis;

  End;

  If SplitterArtefacts.Visible then
    SplitterArtefacts.Position.X := 100;

end;

procedure TForm2.BtnSelectAreaClick(Sender: TObject);
var
  SelRect: TSelectionForm;
  lRect: TRect;
begin
  // 1. Inicializar lRect con los valores actuales del componente
  // If it has never been selected (all 0), IsEmpty will be True and will show nothing, which is correct.
  if (AiComputerUseTool1.AreaWidth > 0) and (AiComputerUseTool1.AreaHeight > 0) then
  begin
    lRect := TRect.Create(AiComputerUseTool1.AreaLeft, AiComputerUseTool1.AreaTop, AiComputerUseTool1.AreaLeft + AiComputerUseTool1.AreaWidth, AiComputerUseTool1.AreaTop + AiComputerUseTool1.AreaHeight);
  end
  else
    lRect := TRect.Empty;

  SelRect := TSelectionForm.Create(nil);
  try
    // 2. We pass lRect by reference (var)
    if SelRect.Execute(lRect) then
    begin
      AiComputerUseTool1.AreaLeft := lRect.Left;
      AiComputerUseTool1.AreaTop := lRect.Top;
      AiComputerUseTool1.AreaWidth := lRect.Width;
      AiComputerUseTool1.AreaHeight := lRect.Height;
    end;
  finally
    SelRect.Free;
  end;
end;

procedure TForm2.BtnJSonShemaClick(Sender: TObject);
begin
  FMemoPropertiesEdit := TFMemoPropertiesEdit.Create(Self);
  FMemoPropertiesEdit.SetData('Edit JSonschema, empty for free json', FJSonShema, False, False);
  If FMemoPropertiesEdit.ShowModal = MrOk then
    FJSonShema := FMemoPropertiesEdit.GetContent;
  FMemoPropertiesEdit.Free;
end;

{
  -------------------------------------------------------------------------------
  TAiTextEditorTool - Componente de Edición de Texto para IA
  -------------------------------------------------------------------------------

  ADVERTENCIA SOBRE EL MODO DE OPERACIÓN:

  Este componente está diseñado con un sistema de eventos para virtualizar la
  entrada y salida (I/O).

  1. MODO POR DEFECTO (Acceso a Disco):
  Si NO se asignan los eventos (OnLoadFile, OnSaveFile, etc.) o si el parámetro
  "Handled" se deja en False, el componente ejecutará las operaciones directamente
  sobre el SISTEMA DE ARCHIVOS FÍSICO del sistema operativo.

  2. MODO INTERCEPTADO (Memoria/UI/DB):
  Para evitar el acceso al disco (ej. para editar un TMemo o un registro de BD),
  el programador debe asignar los eventos correspondientes, realizar la lógica
  personalizada y establecer explícitamente:
  Handled := True;

  Esto detiene la ejecución de la lógica predeterminada de archivos.
  -------------------------------------------------------------------------------
}

// 1. File loading: Instead of reading from disk, we read what is in the Memo.
procedure TForm2.AiTextEditorTool1LoadFile(Sender: TObject; const Path: string; var Content: string; var Handled: Boolean);
begin
  // Asignamos el texto actual del Memo a la variable Content que espera el componente
  Content := MemoEditTool.Lines.Text;

  // Indicamos que ya lo manejamos nosotros, así no busca en disco
  Handled := True;
end;

// 2. File saving: Instead of writing to disk, we update the Memo.
procedure TForm2.AiTextEditorTool1SaveFile(Sender: TObject; const Path, Content: string; var Handled: Boolean);
begin
  // We update the Memo with the new content processed by the tool

  TThread.Queue(nil,
    procedure

    var
      SelPos: Integer;
    begin
      // 1. Actualización Atómica en FMX
      // FMX suele ser más eficiente asignando directamente a .Text
      MemoEditTool.Model.Lines.BeginUpdate; // Freezes repainting
      try
        MemoEditTool.Text := Content;
      finally
        MemoEditTool.Model.Lines.EndUpdate;
      end;

      // 2. Visual logic: Find and highlight
      if FLastNewText <> '' then
      begin
        // We search for the position (Base 1)
        SelPos := Pos(FLastNewText, Content);

        if SelPos > 0 then
        begin
          MemoEditTool.SetFocus;

          // FMX: SelStart is Base 0
          MemoEditTool.SelStart := SelPos - 1;
          MemoEditTool.SelLength := Length(FLastNewText);

          // FMX SCROLL HACK:
          // FMX does not have a simple public native "ScrollToCaret" in all versions.
          // However, when giving focus and setting the selection, most platforms (Android/iOS/Win)
          // try to show the cursor.

          // If you notice it does not scroll in your Delphi version, this code
          // forces the Memo to recognize the cursor position:
          MemoEditTool.Repaint;
        end;
      end;

    end);

  // Optional: Scroll to the end or the beginning if you want
  // MemoEditTool.GoToTextEnd;

  Handled := True;
end;

// 3. Check Existence: We simulate whether the file exists or not.
procedure TForm2.AiTextEditorTool1FileExists(Sender: TObject; const Path: string; var Exists, Handled: Boolean);
begin
  // LÓGICA:
  // If we are going to execute the 'create' command, the component expects the file NOT to exist.
  // Si vamos a ejecutar 'str_replace' o 'view', espera que SÍ exista.

  // For this demo, we assume the file "exists" if the Memo has something written.
  // If the Memo is empty, we say it does not exist (allowing use of the 'create' command).
  Exists := (MemoEditTool.Lines.Count > 0) or (Trim(MemoEditTool.Text) <> '');

  Handled := True;
end;

// 4. Directories: Since it is in memory, we always "succeed" with directories.
procedure TForm2.AiTextEditorTool1EnsureDirectory(Sender: TObject; const Path: string; var Handled: Boolean);
begin
  // We do not need to create real folders.
  // We simply say "ready, folder created/verified".
  Handled := True;
end;

// 5. Before the Command: Useful for debugging or prior validation.
procedure TForm2.AiTextEditorTool1BeforeCommand(Sender: TObject; const Command, Path: string; Args: TJSONObject; var Result: string; var Handled: Boolean);
var
  sArgs: string;
  OldStr, NewStr, FileContent: string;
  Occurrences: Integer;

  // Local function to normalize EVERYTHING to #10 (Unix/AI Standard)
  function NormalizeToLF(const S: string): string;
  begin
    // Step 1: Convert Windows CRLF to LF
    Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
    // Step 2: Convert old Mac CR to LF (just in case)
    Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  end;

// Count of occurrences over normalized text
  function CountOccurrencesLocal(const Text, SubText: string): Integer;
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

begin
  // --- LOGGING ---
  sArgs := '';
  FLastNewText := '';

  if Assigned(Args) then
    sArgs := Args.Format;

  if sArgs <> '' then
  begin
    TThread.Queue(nil,
      procedure
      begin
        MemoEditCommandLog.BeginUpdate;
        try
          MemoEditCommandLog.Lines.Add(Command + ' : ' + Path + sLineBreak + sArgs);
          MemoEditCommandLog.Lines.Add('');
          MemoEditCommandLog.GoToTextEnd;
        finally
          MemoEditCommandLog.EndUpdate;
        end;
      end);
  end;

  // --- INTERCEPTAR STR_REPLACE ---
  if Command = 'str_replace' then
  begin
    // 1. Obtener argumentos crudos
    OldStr := Args.GetValue<string>('old_str');
    NewStr := Args.GetValue<string>('new_str');

    // We save for visual effects (scroll)
    FLastNewText := NewStr;

    // 2. NORMALIZATION (The key to success)
    // We convert what is in the Memo to LF format
    FileContent := NormalizeToLF(MemoEditTool.Text);

    // Convertimos lo que manda Claude a formato LF
    OldStr := NormalizeToLF(OldStr);
    NewStr := NormalizeToLF(NewStr);

    // 3. VALIDATION (Using the normalized variables)
    Occurrences := CountOccurrencesLocal(FileContent, OldStr);

    if Occurrences = 0 then
    begin
      // Tip: We add a hint to the error for visual debugging
      Result := 'Error: No match found for replacement.' + sLineBreak + 'Hint: Check whitespace and indentation exactly.';
      Handled := True;
      Exit;
    end
    else if Occurrences > 1 then
    begin
      Result := 'Error: Found ' + IntToStr(Occurrences) + ' matches. Context must be unique.';
      Handled := True;
      Exit;
    end;

    // 4. EXECUTION (On normalized text)
    // rfReplaceAll is not necessary because we validate count=1, but it does not hurt.
    FileContent := StringReplace(FileContent, OldStr, NewStr, []);

    // 5. ACTUALIZACIÓN VISUAL
    MemoEditTool.Model.Lines.BeginUpdate;
    try
      // TMemo en FMX/VCL acepta #10 y lo renderiza bien.
      // When assigning it, the Memo could internally convert it back to OS native,
      // but the replacement was already successful.
      MemoEditTool.Text := FileContent;
    finally
      MemoEditTool.Model.Lines.EndUpdate;
    end;

    Result := 'Successfully replaced text at exactly one location.';
    Handled := True;
  end
  else if Command = 'str_replace' then
  begin
    // ... tu lógica existente ...
  end
  // --- NEW: INTERCEPT APPLY_DIFF (Optional, for normalization) ---
  else if Command = 'apply_diff' then
  begin
    // GPT-5 sometimes sends diffs with LF (#10) line breaks,
    // mientras que tu Memo en Windows podría tener CRLF (#13#10).
    // To ensure patching does not fail due to invisible line breaks:

    // 1. Obtener argumentos
    var
    DiffText := Args.GetValue<string>('diff_text');

    // 2. Normalize the Memo content (Original) to LF
    FileContent := NormalizeToLF(MemoEditTool.Text);

    // 3. Normalize the Diff to LF (just in case)
    DiffText := NormalizeToLF(DiffText);

    // 4. Instantiate the applier manually here to use the normalized texts
    var
    Applier := TDiffApplier.Create;
    var
      NewContent, ErrorMsg: string;
    try
      if Applier.Apply(FileContent, DiffText, NewContent, ErrorMsg) then
      begin
        // ÉXITO: Actualizar Memo
        TThread.Queue(nil,
          procedure
          begin
            MemoEditTool.Model.Lines.BeginUpdate;
            try
              MemoEditTool.Text := NewContent;
            finally
              MemoEditTool.Model.Lines.EndUpdate;
            end;
          end);

        Result := 'Diff aplicado exitosamente.';
      end
      else
      begin
        // FALLO
        Result := 'Error applying diff: ' + ErrorMsg;
      end;
    finally
      Applier.Free;
    end;

    // We mark it as handled so the component does not try to do it again
    Handled := True;
  end
  else
  begin
    Handled := False;
  end;

end;

end.



procedure TForm2.AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin

  For Var MF in aMsg.MediaFiles do
  Begin
    MF.SaveToFile('miarchivo');
  End;


  For Var MF in aMsg.MediaFiles do
  Begin

    If MF.ToString <> '' then
    Begin
        Var YourJSonHere := MF.ToString;
    End;
  End;
end;




