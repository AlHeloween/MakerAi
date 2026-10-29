unit uMakerAi.Ollama.Ocr;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient,
  System.Net.HttpClientComponent, System.Net.URLClient, System.Threading,
  System.StrUtils,
  uMakerAi.Core,
  uMakerAi.Chat.Tools,
  uMakerAi.Chat.Messages;

type
  { TAiOllamaOcrTool: OCR tool using vision models in Ollama }

  TAiOllamaOcrTool = class(TAiVisionToolBase)
  private
    FUrl: string;
    FModel: string;
    FPrompt: string;
    FKeepAlive: string;
    FStream: Boolean;
    FApiKey: string;
    FTimeout: Integer;
    function GetApiKey: string;
    procedure SetTimeout(const Value: Integer);
  protected
    procedure ExecuteImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage); override;
    function InternalRunOllamaOCR(aMediaFile: TAiMediaFile; ResMsg: TAiChatMessage; const AOverridePrompt: string): string;
  public
    constructor Create(AOwner: TComponent); override;

    { Static methods }
    class function ExtractText(AMediaFile: TAiMediaFile; const APrompt: string = ''; const AUrl: string = ''): string;
    class function ExtractTextFromFile(const AFilePath: string; const APrompt: string = ''; const AUrl: string = ''): string;
    class function ExtractTextFromStream(AStream: TStream; const AFileName: string; const APrompt: string = ''; const AUrl: string = ''): string;

  published
    property ApiKey: string read FApiKey write FApiKey;
    property Url: string read FUrl write FUrl;
    property Model: string read FModel write FModel;
    property KeepAlive: string read FKeepAlive write FKeepAlive;
    property Stream: Boolean read FStream write FStream default False;
    property Prompt: string read FPrompt write FPrompt;
    Property Timeout : Integer read FTimeout write SetTimeout;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiOllamaOcrTool]);
end;

{ TAiOllamaOcrTool }

constructor TAiOllamaOcrTool.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Important: The base URL. InternalRun will handle ensuring the endpoint /api/chat
  FUrl := 'http://localhost:11434/';
  FModel := 'deepseek-ocr:latest';
  FPrompt := '<|grounding|>Convert the document to markdown';
  FKeepAlive := '1m';
  FTimeout := 60000;
  FStream := False;
end;

function TAiOllamaOcrTool.GetApiKey: string;
begin
  if (csDesigning in ComponentState) then Exit(FApiKey);
  if FApiKey.StartsWith('@') then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, MaxInt))
  else
    Result := FApiKey;
end;

procedure TAiOllamaOcrTool.ExecuteImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage);
var
  LPrompt: string;
begin
  // Capture the prompt before any async operation to avoid
  // accessing AskMsg when it might be freed inside the TTask.
  LPrompt := '';
  if Assigned(AskMsg) then
    LPrompt := AskMsg.Prompt;

  InternalRunOllamaOCR(aMediaFile, ResMsg, LPrompt);
end;

function TAiOllamaOcrTool.InternalRunOllamaOCR(aMediaFile: TAiMediaFile; ResMsg: TAiChatMessage; const AOverridePrompt: string): string;
var
  HTTP: TNetHTTPClient;
  LBody: TStringStream;
  LRequestJson, LOptions, LMessage, LMsgResponse: TJSONObject;
  LMessagesArray, LImagesArray: TJSONArray;
  LResponse: IHTTPResponse;
  LResponseJson: TJSONObject;
  LFinalPrompt, LContent, LActualApiKey, LFullUrl: string;
begin
  Result := '';
  if not Assigned(aMediaFile) or not Assigned(ResMsg) then Exit;

  // 1. Ensure correct endpoint (/api/chat)
  LFullUrl := FUrl + 'api/chat';

  LFinalPrompt := IfThen(AOverridePrompt.IsEmpty, FPrompt, AOverridePrompt);
  if LFinalPrompt.IsEmpty then LFinalPrompt := '<|grounding|>Convert the document to markdown';

  //The prompt for DeepSeek OCR is very strict, must have a #10 and then the text without space
  //The prompt text must be in Chinese or English, it does not accept prompts in other languages
  //The text of the PDF or image can be in Spanish or other languages
  //Is used by default <|grounding|> so that it also extracts the boundings of the texts
  //The boundings are proportional, they do not correspond to the real value, it is necessary to scale them according
  //to the image size
  //LFinalPrompt := ' Free OCR';  //OK some documents
  //LFinalPrompt := #10+'<|grounding|>Convert the document to markdown'; //the most precise extracts the boundings and texts with precision

  LFinalPrompt := #10 + LFinalPrompt;

  HTTP := TNetHTTPClient.Create(nil);
  LRequestJson := TJSONObject.Create;
  try
    LActualApiKey := GetApiKey;

    // A. Payload root
    LRequestJson.AddPair('model', FModel);
    LRequestJson.AddPair('stream', TJSONBool.Create(FStream));
    LRequestJson.AddPair('keep_alive', FKeepAlive);

    // B. Message structure (Same as your TAiOllamaChat.GetMessages)
    LMessagesArray := TJSONArray.Create;
    LMessage := TJSONObject.Create;
    LMessage.AddPair('role', 'user');
    LMessage.AddPair('content', LFinalPrompt);

    LImagesArray := TJSONArray.Create;
    LImagesArray.Add(aMediaFile.Base64);
    LMessage.AddPair('images', LImagesArray);

    LMessagesArray.Add(LMessage);
    LRequestJson.AddPair('messages', LMessagesArray);

    // C. Options (Crucial for DeepSeek-OCR)
    LOptions := TJSONObject.Create;
    LOptions.AddPair('temperature', TJSONNumber.Create(0.12));
    LOptions.AddPair('num_predict', TJSONNumber.Create(16000));
    LOptions.AddPair('top_p', TJSONNumber.Create(1.0));
    LRequestJson.AddPair('options', LOptions);


    LBody := TStringStream.Create(LRequestJson.ToJSON, TEncoding.UTF8);
    try
      HTTP.ContentType := 'application/json';
      HTTP.ResponseTimeout := FTimeOut; // 5 minutes (like in your Chat)

      if not LActualApiKey.IsEmpty then
        HTTP.CustomHeaders['Authorization'] := 'Bearer ' + LActualApiKey;

      ReportState(acsWriting, 'Ollama analyzing image...');
      LResponse := HTTP.Post(LFullUrl, LBody);

       if LResponse.StatusCode = 200 then
      begin
        LResponseJson := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
        try
          if Assigned(LResponseJson) then
          begin
            // Ollama /api/chat returns { "message": { "content": "..." } }
            if LResponseJson.TryGetValue('message', LMsgResponse) then
              LContent := LMsgResponse.GetValue<string>('content', '')
            else
              LContent := LResponseJson.GetValue<string>('response', '');

            ResMsg.Prompt := LContent;
            ResMsg.Role := 'assistant';
            ResMsg.Model := FModel;

            aMediaFile.Procesado := True;
            aMediaFile.Transcription := LContent;
            Result := LContent;

            ReportDataEnd(ResMsg, 'assistant', LContent, LResponseJson);
            ReportState(acsFinished, 'OCR Completed');
          end;
        finally
          LResponseJson.Free;
        end;
      end
      else
        ReportError(Format('Ollama HTTP %d: %s', [LResponse.StatusCode, LResponse.ContentAsString]), nil);
    finally
      LBody.Free;
    end;
  finally
    LRequestJson.Free;
    HTTP.Free;
  end;
end;

procedure TAiOllamaOcrTool.SetTimeout(const Value: Integer);
begin
  If Value <= 30000 then
     FTimeOut := 30000
  Else
    FTimeout := Value;
end;

{ --- Static methods --- }

class function TAiOllamaOcrTool.ExtractText(AMediaFile: TAiMediaFile; const APrompt, AUrl: string): string;
var
  LInstance: TAiOllamaOcrTool;
  LResMsg: TAiChatMessage;
begin
  Result := '';
  if not Assigned(AMediaFile) then Exit;
  LInstance := TAiOllamaOcrTool.Create(nil);
  LResMsg := TAiChatMessage.Create('', 'assistant');
  try
    if AUrl <> '' then LInstance.Url := AUrl;
    Result := LInstance.InternalRunOllamaOCR(AMediaFile, LResMsg, APrompt);
  finally
    LResMsg.Free;
    LInstance.Free;
  end;
end;

class function TAiOllamaOcrTool.ExtractTextFromFile(const AFilePath, APrompt, AUrl: string): string;
var
  LMedia: TAiMediaFile;
begin
  Result := '';
  if not FileExists(AFilePath) then Exit;
  LMedia := TAiMediaFile.Create;
  try
    LMedia.LoadFromFile(AFilePath);
    Result := ExtractText(LMedia, APrompt, AUrl);
  finally
    LMedia.Free;
  end;
end;

class function TAiOllamaOcrTool.ExtractTextFromStream(AStream: TStream; const AFileName, APrompt, AUrl: string): string;
var
  LMedia: TAiMediaFile;
  LMemStream: TMemoryStream;
begin
  Result := '';
  if not Assigned(AStream) then Exit;
  LMedia := TAiMediaFile.Create;
  LMemStream := TMemoryStream.Create;
  try
    AStream.Position := 0;
    LMemStream.LoadFromStream(AStream);
    LMedia.LoadFromStream(AFileName, LMemStream);
    Result := ExtractText(LMedia, APrompt, AUrl);
  finally
    LMemStream.Free;
    LMedia.Free;
  end;
end;

end.
