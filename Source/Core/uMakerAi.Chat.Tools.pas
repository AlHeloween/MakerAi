unit uMakerAi.Chat.Tools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Threading,
  uMakerAi.Core,
  uMakerAi.Chat.Messages; // Now we use the messages unit directly

type
  { IAiToolContext: Interface so that the Tool reports events to the main Chat.
    Allows bidirectional communication without circular dependency. }
  IAiToolContext = interface
    ['{E1D2C3B4-A5F6-4B7C-9D8E-F0A1B2C3D4E5}']
    procedure DoData(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
    procedure DoDataEnd(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
    procedure DoError(const ErrorMsg: string; E: Exception);
    procedure DoStateChange(State: TAiChatState; const Description: string = '');
    function GetAsynchronous: Boolean;
  end;

  { --- TOOL INTERFACES --- }

  IAiSpeechTool = interface
    ['{B2C3D4E5-F6A7-4B6C-9D0E-F1A2B3C4D5E6}']
    procedure ExecuteTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
    procedure ExecuteSpeechGeneration(const AText: string; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiVisionTool = interface
    ['{7A8B9C0D-E1F2-4A3B-8C4D-5E6F7A8B9C0D}']
    procedure ExecuteImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiImageTool = interface
    ['{A1B2C3D4-E5F6-4A5B-8C9D-E0F1A2B3C4D5}']
    procedure ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiVideoTool = interface
    ['{E5F6A7B8-C9D0-4E1F-A2B3-C4D5E6F7A8B9}']
    procedure ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiDocumentTool = interface
    ['{D4E5F6A7-B8C9-4D0E-1F2A-B3C4D5E6F7A8}']
    procedure ExecuteDocumentAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiCodeInterpreterTool = interface
    ['{F6A7B8C9-D0E1-4F2A-B3C4-D5E6F7A8B9C0}']
    procedure ExecuteCode(const ACode, ALanguage: string; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiWebSearchTool = interface
    ['{C3D4E5F6-A7B8-4C7D-0E1F-A2B3C4D5E6F7}']
    procedure ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage);
  end;

  IAiPdfTool = interface
    ['{C1D2E3F4-B5A6-4C7D-8E9F-A0B1C2D3E4F5}']
    procedure ExecutePdfAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
  end;

  // Intent classifier for cmSmartDispatch: replaces pass 1 (an LLM that
  // classifies) with a fast classifier. Returns one of ATags, or '' so that
  // the chat performs pass 1 with the LLM as usual (doubt, error, etc.).
  IAiDispatchClassifier = interface
    ['{F2D75772-8679-43F9-84C2-5E28E2FB3D07}']
    function ClassifyDispatch(const APrompt: string; const ATags: TArray<string>): string;
  end;

  IAiReportTool = interface
    ['{B9C0D1E2-F3A4-4B5C-6D7E-8F9A0B1C2D3E}']
    procedure ExecuteReport(ResMsg, AskMsg: TAiChatMessage);
  end;


  { --- BASE CLASSES --- }

  { TAiCustomTool: Basic context management and events reported to the main thread }
  TAiCustomTool = class(TComponent)
  protected
    FContext: IAiToolContext;
    procedure ReportData(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
    procedure ReportDataEnd(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject = nil);
    procedure ReportError(const ErrorMsg: string; E: Exception);
    procedure ReportState(State: TAiChatState; const Description: string = '');
    function IsAsync: Boolean;
  public
    destructor Destroy; override;
    procedure SetContext(AContext: IAiToolContext); virtual;
  end;

  { Specializations for the Object Inspector }

  TAiSpeechToolBase = class(TAiCustomTool, IAiSpeechTool)
  Protected
    procedure ExecuteTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); virtual;
    procedure ExecuteSpeechGeneration(const AText: string; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiVisionToolBase = class(TAiCustomTool, IAiVisionTool)
  Protected
    procedure ExecuteImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiImageToolBase = class(TAiCustomTool, IAiImageTool)
  Protected
    procedure ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiVideoToolBase = class(TAiCustomTool, IAiVideoTool)
  Protected
    procedure ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiDocumentToolBase = class(TAiCustomTool, IAiDocumentTool)
  Protected
    procedure ExecuteDocumentAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiCodeInterpreterToolBase = class(TAiCustomTool, IAiCodeInterpreterTool)
  Protected
    procedure ExecuteCode(const ACode, ALanguage: string; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiWebSearchToolBase = class(TAiCustomTool, IAiWebSearchTool)
  Protected
    procedure ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiPdfToolBase = class(TAiCustomTool, IAiPdfTool)
  Protected
    procedure ExecutePdfAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  TAiReportToolBase = class(TAiCustomTool, IAiReportTool)
  Protected
    procedure ExecuteReport(ResMsg, AskMsg: TAiChatMessage); virtual;
  end;

  // Verdict of the input guardrail (ChatTools.PromptGuard)
  TAiPromptVerdict = record
    Allowed: Boolean;
    Category: string; // category that blocked ('injection', 'sensitive_data', ...); '' if passed
    Score: Double;    // probability of that category (0..1)
    Reason: string;
  end;

  // Input guardrail: checks the user's message BEFORE sending it to the LLM,
  // after the regex sanitizer (SanitizerActive). The base allows everything.
  // If CheckPrompt raises, BlockOnError decides (True = block).
  // Implementation with Jev: TAiJevPromptGuard.
  TAiPromptGuardBase = class(TAiCustomTool)
  private
    FBlockOnError: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    function CheckPrompt(const APrompt: string): TAiPromptVerdict; virtual;
  published
    property BlockOnError: Boolean read FBlockOnError write FBlockOnError default True;
  end;

  // Base for ChatTools.DispatchClassifier. The default implementation does not
  // decide ('') and SmartDispatch continues with its pass 1 via LLM.
  TAiDispatchClassifierBase = class(TAiCustomTool, IAiDispatchClassifier)
  Protected
    function ClassifyDispatch(const APrompt: string; const ATags: TArray<string>): string; virtual;
  end;

implementation

{ TAiCustomTool }

destructor TAiCustomTool.Destroy;
begin
  // FContext is a weak reference (TAiChat is TComponent, without ref-counting).
  // If the chat that assigned it has already been freed, FContext points to freed memory.
  // Delphi's CleanupInstance would call _Release through that corrupt vtable → AV.
  // Solution: zero the field directly, without going through interface management.
  PPointer(@FContext)^ := nil;
  inherited;
end;

procedure TAiCustomTool.SetContext(AContext: IAiToolContext);
begin
  FContext := AContext;
end;

function TAiCustomTool.IsAsync: Boolean;
begin
  Result := Assigned(FContext) and FContext.GetAsynchronous;
end;

procedure TAiCustomTool.ReportData(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject);
begin
  if Assigned(FContext) then
  begin
    if IsAsync then
      TThread.Queue(nil,
        procedure
        begin
          FContext.DoData(Msg, Role, Text, AResponse);
        end)
    else
      FContext.DoData(Msg, Role, Text, AResponse);
  end;
end;

procedure TAiCustomTool.ReportDataEnd(Msg: TAiChatMessage; const Role, Text: string; AResponse: TJSONObject);
begin
  if Assigned(FContext) then
  begin
    if IsAsync then
      TThread.Queue(nil,
        procedure
        begin
          FContext.DoDataEnd(Msg, Role, Text, AResponse);
        end)
    else
      FContext.DoDataEnd(Msg, Role, Text, AResponse);
  end;
end;

procedure TAiCustomTool.ReportError(const ErrorMsg: string; E: Exception);
begin
  if Assigned(FContext) then
  begin
    if IsAsync then
      TThread.Queue(nil,
        procedure
        begin
          FContext.DoError(ErrorMsg, nil);
        end)
    else
      FContext.DoError(ErrorMsg, nil);
  end;
end;

procedure TAiCustomTool.ReportState(State: TAiChatState; const Description: string);
begin
  if Assigned(FContext) then
  begin
    if IsAsync then
      TThread.Queue(nil,
        procedure
        begin
          FContext.DoStateChange(State, Description);
        end)
    else
      FContext.DoStateChange(State, Description);
  end;
end;

{ TAiSpeechToolBase }

procedure TAiSpeechToolBase.ExecuteSpeechGeneration(const AText: string; ResMsg, AskMsg: TAiChatMessage);
begin
end;

procedure TAiSpeechToolBase.ExecuteTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiVisionToolBase }

procedure TAiVisionToolBase.ExecuteImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiImageToolBase }

procedure TAiImageToolBase.ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiVideoToolBase }

procedure TAiVideoToolBase.ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiDocumentToolBase }

procedure TAiDocumentToolBase.ExecuteDocumentAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiCodeInterpreterToolBase }

procedure TAiCodeInterpreterToolBase.ExecuteCode(const ACode, ALanguage: string; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiWebSearchToolBase }

procedure TAiWebSearchToolBase.ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiPdfToolBase }

procedure TAiPdfToolBase.ExecutePdfAnalysis(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiReportToolBase }

procedure TAiReportToolBase.ExecuteReport(ResMsg, AskMsg: TAiChatMessage);
begin
end;

{ TAiPromptGuardBase }

constructor TAiPromptGuardBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBlockOnError := True;
end;

function TAiPromptGuardBase.CheckPrompt(const APrompt: string): TAiPromptVerdict;
begin
  Result.Allowed := True;
  Result.Category := '';
  Result.Score := 0;
  Result.Reason := '';
end;

{ TAiDispatchClassifierBase }

function TAiDispatchClassifierBase.ClassifyDispatch(const APrompt: string;
  const ATags: TArray<string>): string;
begin
  Result := '';
end;

end.
