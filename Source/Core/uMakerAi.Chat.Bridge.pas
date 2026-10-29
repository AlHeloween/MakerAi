// MIT License
// Copyright (c) 2025 Gustavo Enríquez
// uMakerAi Framework - Bridge System

unit uMakerAi.Chat.Bridge;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient,
  uMakerAi.Core, uMakerAi.Chat.Tools, uMakerAi.Chat, uMakerAi.Chat.Messages;

type
  { TAiBaseChatBridge: Internal delegation engine }
  TAiBaseChatBridge = class(TAICustomTool)
  private
    FTargetChat: TAiChat;
    FCurrentResMsg: TAiChatMessage;
    FCurrentMediaFile: TAiMediaFile;
    procedure SetTargetChat(const Value: TAiChat);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure HandleTargetData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
    procedure HandleTargetEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
    procedure HandleTargetError(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
    procedure PrepareTargetChat(AContext: IAiToolContext; AResMsg: TAiChatMessage; AMediaFile: TAiMediaFile = nil);
    property TargetChat: TAiChat read FTargetChat write SetTargetChat;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { --- SPECIALIZED BRIDGES --- }

  { Audio / Voice }
  TAiChatSpeechBridge = class(TAiSpeechToolBase)
  private
    FEngine: TAiBaseChatBridge;
    FPromptTranscription: string;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteTranscription(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); override;
    procedure ExecuteSpeechGeneration(const aText: string; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
    property PromptTranscription: string read FPromptTranscription write FPromptTranscription;
  end;

  { Vision }
  TAiChatVisionBridge = class(TAiVisionToolBase)
  private
    FEngine: TAiBaseChatBridge;
    FPromptVision: string;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteImageDescription(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
    property PromptVision: string read FPromptVision write FPromptVision;
  end;

  { Images }
  TAiChatImageBridge = class(TAiImageToolBase)
  private
    FEngine: TAiBaseChatBridge;
    FPromptImage: string;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
    property PromptImage: string read FPromptImage write FPromptImage;
  end;

  { Video }
  TAiChatVideoBridge = class(TAiVideoToolBase)
  private
    FEngine: TAiBaseChatBridge;
    FPromptVideo: string;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
    property PromptVideo: string read FPromptVideo write FPromptVideo;
  end;

  { Documents (PDF, Word, etc) }
  TAiChatDocumentBridge = class(TAiDocumentToolBase)
  private
    FEngine: TAiBaseChatBridge;
    FPromptDocument: string;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteDocumentAnalysis(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
    property PromptDocument: string read FPromptDocument write FPromptDocument;
  end;

  { Code Interpreter }
  TAiChatCodeInterpreterBridge = class(TAiCodeInterpreterToolBase)
  private
    FEngine: TAiBaseChatBridge;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteCode(const ACode, ALanguage: string; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
  end;

  { Web Search }
  TAiChatWebSearchBridge = class(TAiWebSearchToolBase)
  private
    FEngine: TAiBaseChatBridge;
    function GetChat: TAiChat;
    procedure SetChat(const Value: TAiChat);
  protected
    procedure ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Chat: TAiChat read GetChat write SetChat;
  end;

procedure Register;

implementation

{ Hack to access protected FContext }
type
  TToolAccess = class(TAICustomTool);

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiChatSpeechBridge, TAiChatVisionBridge, TAiChatImageBridge, TAiChatVideoBridge, TAiChatDocumentBridge, TAiChatCodeInterpreterBridge, TAiChatWebSearchBridge]);
end;

{ TAiBaseChatBridge }

constructor TAiBaseChatBridge.Create(AOwner: TComponent);
begin
  inherited;
end;

procedure TAiBaseChatBridge.SetTargetChat(const Value: TAiChat);
begin
  if FTargetChat <> Value then
  begin
    FTargetChat := Value;
    if Value <> nil then
      Value.FreeNotification(Self);
  end;
end;

procedure TAiBaseChatBridge.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FTargetChat) then
    FTargetChat := nil;
end;

procedure TAiBaseChatBridge.PrepareTargetChat(AContext: IAiToolContext; AResMsg: TAiChatMessage; AMediaFile: TAiMediaFile);
begin
  if not Assigned(FTargetChat) then
    raise Exception.Create('Error: Bridge without assigned target Chat.');
  Self.SetContext(AContext);
  FCurrentResMsg := AResMsg;
  FCurrentMediaFile := AMediaFile;
  FTargetChat.OnReceiveData := HandleTargetData;
  FTargetChat.OnReceiveDataEnd := HandleTargetEnd;
  FTargetChat.OnError := HandleTargetError;
  FTargetChat.Asynchronous := IsAsync;
end;

procedure TAiBaseChatBridge.HandleTargetData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
begin
  ReportData(FCurrentResMsg, aRole, aText, aResponse);
end;

procedure TAiBaseChatBridge.HandleTargetEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: String);
begin
  if Assigned(FCurrentMediaFile) then
  begin
    FCurrentMediaFile.Transcription := aText;
    FCurrentMediaFile.Procesado := True;
  end;
  ReportDataEnd(FCurrentResMsg, aRole, aText, aResponse);
end;

procedure TAiBaseChatBridge.HandleTargetError(Sender: TObject; const ErrorMsg: string; Exception: Exception; const aResponse: IHTTPResponse);
begin
  ReportError(ErrorMsg, Exception);
end;

{ --- BRIDGE IMPLEMENTATIONS --- }

{ TAiChatSpeechBridge }
constructor TAiChatSpeechBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
  FPromptTranscription := 'Transcribe this audio literally. Only the text.';
end;

destructor TAiChatSpeechBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatSpeechBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatSpeechBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatSpeechBridge.ExecuteTranscription(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg, AMediaFile);
  ReportState(acsReasoning, 'Delegating transcription...');
  FEngine.TargetChat.AddMessageAndRun(FPromptTranscription, 'user', [AMediaFile]);
end;

procedure TAiChatSpeechBridge.ExecuteSpeechGeneration(const aText: string; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg);
  ReportState(acsWriting, 'Delegating voice generation...');
  FEngine.TargetChat.AddMessageAndRun('Generate an audio with the following text: ' + aText, 'user', []);
end;

{ TAiChatVisionBridge }
constructor TAiChatVisionBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
  FPromptVision := 'Describe this image in detail.';
end;

destructor TAiChatVisionBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatVisionBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatVisionBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatVisionBridge.ExecuteImageDescription(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg, AMediaFile);
  ReportState(acsReasoning, 'Delegating vision...');
  FEngine.TargetChat.AddMessageAndRun(FPromptVision, 'user', [AMediaFile]);
end;

{ TAiChatImageBridge }
constructor TAiChatImageBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
  FPromptImage := 'Generate an image based on this description: ';
end;

destructor TAiChatImageBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatImageBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatImageBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatImageBridge.ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg);
  ReportState(acsWriting, 'Delegating image generation...');
  FEngine.TargetChat.AddMessageAndRun(FPromptImage + APrompt, 'user', []);
end;

{ TAiChatVideoBridge }
constructor TAiChatVideoBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
  FPromptVideo := 'Generate a short video based on this description: ';
end;

destructor TAiChatVideoBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatVideoBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatVideoBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatVideoBridge.ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg);
  ReportState(acsWriting, 'Delegating video generation...');
  FEngine.TargetChat.AddMessageAndRun(FPromptVideo + TAiChatMessage(AskMsg).Prompt, 'user', []);
end;

{ TAiChatDocumentBridge }
constructor TAiChatDocumentBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
  FPromptDocument := 'Analyze this document and summarize the key points.';
end;

destructor TAiChatDocumentBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatDocumentBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatDocumentBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatDocumentBridge.ExecuteDocumentAnalysis(AMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg, AMediaFile);
  ReportState(acsReasoning, 'Delegating document analysis...');
  FEngine.TargetChat.AddMessageAndRun(FPromptDocument, 'user', [AMediaFile]);
end;

{ TAiChatCodeInterpreterBridge }
constructor TAiChatCodeInterpreterBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
end;

destructor TAiChatCodeInterpreterBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatCodeInterpreterBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatCodeInterpreterBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatCodeInterpreterBridge.ExecuteCode(const ACode, ALanguage: string; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg);
  ReportState(acsWriting, 'Delegating code execution...');
  FEngine.TargetChat.AddMessageAndRun('Execute or explain this code in ' + ALanguage + ': ' + ACode, 'user', []);
end;

{ TAiChatWebSearchBridge }
constructor TAiChatWebSearchBridge.Create(AOwner: TComponent);
begin
  inherited;
  FEngine := TAiBaseChatBridge.Create(nil);
end;

destructor TAiChatWebSearchBridge.Destroy;
begin
  FEngine.Free;
  inherited;
end;

function TAiChatWebSearchBridge.GetChat: TAiChat;
begin
  Result := FEngine.TargetChat;
end;

procedure TAiChatWebSearchBridge.SetChat(const Value: TAiChat);
begin
  FEngine.TargetChat := Value;
end;

procedure TAiChatWebSearchBridge.ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage);
begin
  FEngine.PrepareTargetChat(TToolAccess(Self).FContext, ResMsg);
  ReportState(acsReasoning, 'Delegating web search...');
  FEngine.TargetChat.AddMessageAndRun('Search the internet for information about: ' + AQuery, 'user', []);
end;

end.
