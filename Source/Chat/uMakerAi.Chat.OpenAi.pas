unit uMakerAi.Chat.OpenAi;

// MIT License
//
// Copyright (c) 2013 Gustavo Enr?quez - CimaMaker
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
// Name: Gustavo Enr?quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: +57 3128441700
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

// The documentation for this library is located at
// https://platform.openai.com/docs/guides/migrate-to-responses

// FileSearch, Retrieval, McP Remote nor DeepSearch have not been implemented directly from the OpenAI platform.
// https://platform.openai.com/docs/guides/tools-file-search

interface

uses
  System.SysUtils, System.Classes, System.Threading, System.Generics.Collections, System.IOUtils,
  System.NetEncoding, System.Net.URLClient, System.Net.HttpClient, System.StrUtils, System.Math,
  System.Net.Mime, System.Net.HttpClientComponent, System.JSON, Rest.JSON,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Core,
  uMakerAi.Tools.Functions, uMakerAi.Utils.CodeExtractor, uMakerAi.Utils.System, uMakerAi.Chat.Messages;

type

  // Event to manually handle the apply_patch tool.
  // Parameters:
  // - OperationType: 'create_file', 'update_file', 'delete_file'.
  // Path: Target file
  // Diff: The patch content (V4A diff).
  // CallId: Unique call ID
  // - aStatus: Return variable. Must be 'completed' or 'failed'.
  // - aOutput: Return variable. Success message or error description.
  TAiApplyPatchEvent = procedure(Sender: TObject; const OperationType, Path, Diff: string; const CallId: string; var aStatus, aOutput: string) of object;

  // Event to handle shell commands.
  // If Handled is True, the component assumes the user filled StdOut/StdErr/ExitCode.
  // If Handled is False, the component will attempt to run it automatically (if configured).
  TAiShellCommandEvent = procedure(Sender: TObject; const Command: string; const CallId: string; var StdOut, StdErr: string; var ExitCode: Integer; var Handled: Boolean) of object;

  TAiReasoningSummary = (rsmDefault, rsmAuto, rsmConcise, rsmDetailed);

  TAiOpenChat = class(TAiChat)
  private
    FStore: Boolean;
    FTruncation: String;
    FParallel_ToolCalls: Boolean;
    FVerbosity: String;

    // Internal state of the Responses endpoint
    FResponseId: String;
    FResponseStatus: String; // completed, failed, in_progress, incomplete
    FOnApplyPatch: TAiApplyPatchEvent;
    FOnShellCommand: TAiShellCommandEvent;
    FAllowAutoShell: Boolean;
    FReasoningSummary: TAiReasoningSummary;
    FRecursionNeeded: Boolean;
    // 'assistant' message where the stream text accumulates. It
    // is fixed at 'response.created' because when the turn closes, the last
    // message of the history may NOT be this one (e.g., a computer_call
    // raw delegated), and dumping FLastContent there would destroy it.
    FStreamTextMsg: TAiChatMessage;
    // Last effort sent to the server in THIS conversation. It serves
    // to decide whether to emit a 'configuration_update' instead of
    // changing the reasoning at the request level, which breaks the cached prefix.
    FLastEffortSent: TAiThinkingLevel;

    procedure SetStore(const Value: Boolean);
    procedure SetTruncation(const Value: String);
    procedure SetParallel_ToolCalls(const Value: Boolean);
    procedure SetVerbosity(const Value: String);

  protected
    // Override of Core methods to adapt to the new API
    procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;
    Procedure ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage); Override;
    Function InitChatCompletions: String; Override;
    Function GetTools(Funcion: TAiFunctions): TJSonArray; Reintroduce;

    // Internal methods
    procedure UpdateResponseStatus(aStatus: String);
    procedure DoCallFunction(ToolCall: TAiToolsFunction); Override;

    // Inherited methods that remain the same or are slightly adapted
    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;
    function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Factory
    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;

    Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer = 3600): String; Override;
    Function DeleteFile(aMediaFile: TAiMediaFile): String; Override;
    function DownLoadFile(aMediaFile: TAiMediaFile): String; Override;
    function DeleteAllUploadedFiles: Integer; // Deletes all files uploaded during the conversation; otherwise they will remain in the OpenAI repository
    Procedure NewChat; Override;
    function InternalRunImageVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Override;

  published
    // Specific mapped properties
    property Store: Boolean read FStore write SetStore default True;
    property Truncation: String read FTruncation write SetTruncation;
    property Parallel_ToolCalls: Boolean read FParallel_ToolCalls write SetParallel_ToolCalls default True;

    // New properties of GPT-5 / Responses API
    property Verbosity: String read FVerbosity write SetVerbosity; // low, medium, high
    property OnApplyPatch: TAiApplyPatchEvent read FOnApplyPatch write FOnApplyPatch;
    property OnShellCommand: TAiShellCommandEvent read FOnShellCommand write FOnShellCommand;
    property AllowAutoShell: Boolean read FAllowAutoShell write FAllowAutoShell default False;
    property ReasoningSummary: TAiReasoningSummary read FReasoningSummary write FReasoningSummary default rsmDefault;
  end;

procedure Register;

implementation

uses
  System.Generics.Defaults;

Const
  GlOpenAIUrl = 'https://api.openai.com/v1/';

// reasoning.effort that is sent. The GPT-6 family accepts none/low/medium/
// high/xhigh/max but NOT minimal (the 5.x does): there tlMinimal is requested as
// low to avoid a 400.
function OpenAiEffort(const AModel: string; ALevel: TAiThinkingLevel): string;
begin
  Result := ThinkingLevelToStr(ALevel);
  if (ALevel = tlMinimal) and AModel.ToLower.StartsWith('gpt-6') then
    Result := 'low';
end;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiOpenChat]);
end;

{ TAiOpenChat }

constructor TAiOpenChat.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Default configuration
  FStore := True;
  FTruncation := 'disabled';
  FParallel_ToolCalls := True;
  FVerbosity := '';
  FResponseId := '';
  FResponseStatus := '';
  FLastEffortSent := tlDefault;
  // Default URL and ApiKey
  if ApiKey = '' then
    ApiKey := '@OPENAI_API_KEY';
  if Url = '' then
    Url := GlOpenAIUrl;
  // gpt-6-sol since v3.8: successor of gpt-5.1 in the same price bracket
  // ($2/$10). It is ALWAYS assigned: the TAiChat constructor leaves 'gpt-5', so
  // the old "if Model = ''" never fired and a TAiOpenChat created
  // directly used gpt-5 (which shuts down on Dec 11, 2026), not gpt-5.1.
  Model := 'gpt-6-sol';

  FReasoningSummary := rsmDefault;
  // Capabilities configured via Initializations.pas (ModelConfig.ModelCaps/SessionCaps)
end;

function TAiOpenChat.DeleteAllUploadedFiles: Integer;
var
  I, K: Integer;
  Msg: TAiChatMessage;
  Media: TAiMediaFile;
begin
  Result := 0;

  // We iterate through all history messages
  for I := 0 to FMessages.Count - 1 do
  begin
    Msg := FMessages[I];

    // We iterate through the attached files of each message
    for K := 0 to Msg.MediaFiles.Count - 1 do
    begin
      Media := Msg.MediaFiles[K];

      // We only try to delete if it has a cloud ID assigned
      if Media.IdFile <> '' then
      begin
        try
          // We call our DeleteFile function
          // Note: DeleteFile already clears the IdFile property of the object if successful
          if DeleteFile(Media) = 'deleted' then
            Inc(Result);
        except
          // We catch exceptions silently to not stop the process
          // If a file fails, we try the next one.
        end;
      end;
    end;
  end;
end;

function TAiOpenChat.DeleteFile(aMediaFile: TAiMediaFile): String;
var
  LUrl: string;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
  LJson: TJSonObject;
begin
  Result := '';
  if (aMediaFile = nil) or (aMediaFile.IdFile = '') then
    Exit;

  // Endpoint: DELETE https://api.openai.com/v1/files/{file_id}
  LUrl := Url;
  if not LUrl.EndsWith('/') then
    LUrl := LUrl + '/';
  LUrl := LUrl + 'files/' + aMediaFile.IdFile;

  LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

  LResponse := FClient.Delete(LUrl, nil, LHeaders);

  if LResponse.StatusCode = 200 then
  begin
    LJson := TJSonObject.ParseJSONValue(LResponse.ContentAsString) as TJSonObject;
    try
      if Assigned(LJson) and LJson.GetValue<Boolean>('deleted') then
      begin
        Result := 'deleted';
        // We clear the cloud data of the object
        aMediaFile.IdFile := '';
        aMediaFile.CloudState := '';
        aMediaFile.CacheName := '';
      end
      else
        Result := 'failed';
    finally
      LJson.Free;
    end;
  end
  else
    raise Exception.CreateFmt('Error Deleting File (%d): %s', [LResponse.StatusCode, LResponse.ContentAsString]);
end;

destructor TAiOpenChat.Destroy;
begin
  inherited;
end;

class function TAiOpenChat.GetDriverName: string;
begin
  Result := 'OpenAi';
end;

class procedure TAiOpenChat.RegisterDefaultParams(Params: TStrings);
begin
  Params.Clear;
  Params.Add('ApiKey=@OPENAI_API_KEY');
  Params.Add('Model=gpt-6-sol');
  Params.Add('Url=https://api.openai.com/v1/');
end;

class function TAiOpenChat.CreateInstance(Sender: TComponent): TAiChat;
begin
  Result := TAiOpenChat.Create(Sender);
end;

{ #region Setters }
procedure TAiOpenChat.SetStore(const Value: Boolean);
begin
  FStore := Value;
end;

procedure TAiOpenChat.SetTruncation(const Value: String);
begin
  FTruncation := Value;
end;

procedure TAiOpenChat.SetParallel_ToolCalls(const Value: Boolean);
begin
  FParallel_ToolCalls := Value;
end;

procedure TAiOpenChat.SetVerbosity(const Value: String);
begin
  FVerbosity := Value;
end;
{ #endregion }

procedure TAiOpenChat.UpdateResponseStatus(aStatus: String);
begin
  FResponseStatus := aStatus;
end;

function TAiOpenChat.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer): String;
var
  LBody: TMultipartFormData;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
  LUrl: string;
  LJson: TJSonObject;
  LFileName: string;
  OldAsync: Boolean;

const
  APurpose = 'user_data';

begin
  Result := '';

  // 1. Preliminary validations
  if not Assigned(aMediaFile) then
    raise Exception.Create('The MediaFile object is not assigned.');

  // If it already has an ID, we assume it is already in the cloud and do not upload again
  if aMediaFile.IdFile <> '' then
    Exit(aMediaFile.IdFile);

  if (aMediaFile.Content.Size = 0) and (aMediaFile.Base64 = '') then
    raise Exception.Create('The file is empty (no Content nor Base64).');

  // 2. Prepare URL (ensure endpoint /files)
  // Note: Url is usually 'https://api.openai.com/v1/'
  if Url.EndsWith('/') then
    LUrl := Url + 'files'
  else
    LUrl := Url + '/files';

  // 3. Prepare the content if it comes only in Base64
  if (aMediaFile.Content.Size = 0) and (aMediaFile.Base64 <> '') then
  begin
    // We assume that LoadFromBase64 fills the Content stream or we decode here.
    // If your TAiMediaFile class does not do it automatically, here you should decode.
    // For safety, we will use the native method if it exists, or assume Content is ready.
  end;

  aMediaFile.Content.Position := 0;
  LFileName := aMediaFile.FileName;
  if LFileName = '' then
    LFileName := 'upload.pdf'; // Mandatory fallback name

  LBody := TMultipartFormData.Create;
  try
    // 4. Parameters for GPT-5 / Responses
    LBody.AddField('purpose', APurpose); // Default 'user_data'

    // stream, name, content-type (optional, usually automatic by extension)
{$IF CompilerVersion < 36}
    LBody.AddStream('file', aMediaFile.Content, LFileName);
{$ELSE}
    LBody.AddStream('file', aMediaFile.Content, False, LFileName);
{$ENDIF}

    // 5. Execute Request using FClient (Inherits Proxies/Timeouts)
    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    // Important: Do not set ContentType, the client sets it to multipart/form-data automatically

    // The calls to this function are synchronous for now
    OldAsync := FClient.Asynchronous;
    FClient.Asynchronous := False;
    Try
      LResponse := FClient.Post(LUrl, LBody, nil, LHeaders);
    Finally
      FClient.Asynchronous := OldAsync;
    End;

    // 6. Process Response
    if LResponse.StatusCode = 200 then
    begin
      LJson := TJSonObject.ParseJSONValue(LResponse.ContentAsString) as TJSonObject;
      try
        if Assigned(LJson) then
        begin
          // Get ID
          if LJson.TryGetValue<string>('id', Result) then
          begin
            // 7. Update the MediaFile object (as in the function you found)
            aMediaFile.IdFile := Result;

            // We save useful metadata if they exist
            if LJson.TryGetValue<string>('filename', LFileName) then
              aMediaFile.CloudName := LFileName;

            // We save the state (e.g., "processed", "uploaded")
            var
              LStatus: string;
            if LJson.TryGetValue<string>('status', LStatus) then
              aMediaFile.CloudState := LStatus;
          end;
        end;
      finally
        LJson.Free;
      end;
    end
    else
    begin
      // Detailed error handling
      raise Exception.CreateFmt('Error Uploading File (%d): %s', [LResponse.StatusCode, LResponse.ContentAsString]);
    end;

  finally
    LBody.Free;
    // We do not release AMediaFile.Content here, the owner is the AMediaFile object
  end;
end;

// -----------------------------------------------------------------------------
// TOOLS HELPERS
// -----------------------------------------------------------------------------

function TAiOpenChat.GetTools(Funcion: TAiFunctions): TJSonArray;
var
  ToolsString: string;
  JParsed: TJSONValue;
begin
  if Assigned(Funcion) then
  begin
    // IMPORTANT CHANGE:
    // Now we directly request the tfOpenAI format.
    // The ToolFunctions unit takes care of generating the flat structure and strict: true.
    ToolsString := Funcion.GetTools(TToolFormat.tfOpenAIResponses);

    if ToolsString = '' then
      Exit(TJSonArray.Create);

    JParsed := TJSonObject.ParseJSONValue(ToolsString);

    // We verify that it is a valid array
    if JParsed is TJSonArray then
      Result := TJSonArray(JParsed)
    else
    begin
      if Assigned(JParsed) then
        JParsed.Free;
      Result := TJSonArray.Create;
    end;
  end
  else
    Result := TJSonArray.Create;
end;

// -----------------------------------------------------------------------------
// REQUEST CONSTRUCTION (Mapping TAiChat -> Responses API JSON)
// -----------------------------------------------------------------------------
function TAiOpenChat.InitChatCompletions: String;
var
  JResult, JReasoning, JTextConfig, JFormatConfig: TJSonObject;
  JInputArray, JToolsArray: TJSonArray;
  JSystemMsg: String;
  ItemMsg: TAiChatMessage;
  I: Integer;
  LModel: String;
  DataFilesList: TStringList;
  StartIndex: Integer; // Variable nueva para control de historial
  LastMsg: TAiChatMessage;
  IsToolLoop: Boolean;
  LEffortAsConfigUpdate: Boolean; // el effort viaja como item, no a nivel de peticion
  JConfigUpd: TJSonObject;

  // Local helper (NO CHANGES with respect to the last correction)
  procedure AddMessageToInput(Msg: TAiChatMessage; TargetArray: TJSonArray);
  var
    JUserObj, JTextObj, JImageObj, JDocObj, JToolOutObj: TJSonObject;
    JContentArr: TJSonArray;
    MediaFile: TAiMediaFile;
    MediaArr: TAiMediaFilesArray;
    K: Integer;
    JPreBuilt: TJSonObject;
    PromptText: String;
    ExtraFileRefs: String;
    IsSpecialAssistant: Boolean;
  begin
    IsSpecialAssistant := (Msg.Role = 'assistant') and Msg.Prompt.Trim.StartsWith('{') and (ContainsText(Msg.Prompt, '"type":"shell_call"') or ContainsText(Msg.Prompt, '"type":"apply_patch_call"') or ContainsText(Msg.Prompt, '"type":"computer_call"'));

    if (Msg.Role = 'tool') or IsSpecialAssistant then
    begin
      if Msg.Prompt.Trim.StartsWith('{') and (ContainsText(Msg.Prompt, '"type":"apply_patch_call_output"') or ContainsText(Msg.Prompt, '"type":"computer_call_output"') or ContainsText(Msg.Prompt, '"type":"computer_call"') or ContainsText(Msg.Prompt, '"type":"shell_call_output"') or ContainsText(Msg.Prompt, '"type":"shell_call"') or
        ContainsText(Msg.Prompt, '"type":"apply_patch_call"')) then
      begin
        JPreBuilt := TJSonObject.ParseJSONValue(Msg.Prompt) as TJSonObject;
        if Assigned(JPreBuilt) then
        begin
          TargetArray.Add(JPreBuilt);
          Exit;
        end;
      end;

      if (Msg.Role = 'tool') then
      begin
        JToolOutObj := TJSonObject.Create;
        JToolOutObj.AddPair('type', 'function_call_output');
        if Msg.ToolCallId <> '' then
          JToolOutObj.AddPair('call_id', Msg.ToolCallId)
        else
          JToolOutObj.AddPair('call_id', 'call_unknown_' + IntToStr(Msg.Id));
        JToolOutObj.AddPair('output', Msg.Prompt);
        TargetArray.Add(JToolOutObj);

        // Attached files (images/PDFs returned by the MCP tool)
        // The Responses API does not accept binaries in function_call_output → they go in a
        // separate user message, immediately after the tool result.
        var LMediaArr2 := Msg.MediaFiles.GetMediaList([Tfc_Image, Tfc_pdf], False);
        if Length(LMediaArr2) > 0 then
        begin
          var JExtraUser := TJSonObject.Create;
          JExtraUser.AddPair('role', 'user');
          var JExtraContent := TJSonArray.Create;
          for var LMF2 in LMediaArr2 do
          begin
            if LMF2.FileCategory = Tfc_Image then
            begin
              var JImg := TJSonObject.Create;
              JImg.AddPair('type', 'input_image');
              JImg.AddPair('image_url', 'data:' + LMF2.MimeType + ';base64,' + LMF2.Base64);
              JExtraContent.Add(JImg);
            end
            else
            begin
              var JDoc := TJSonObject.Create;
              JDoc.AddPair('type', 'input_file');
              if LMF2.FileName <> '' then
                JDoc.AddPair('filename', LMF2.FileName)
              else
                JDoc.AddPair('filename', 'document.pdf');
              JDoc.AddPair('file_data', 'data:' + LMF2.MimeType + ';base64,' + LMF2.Base64);
              JExtraContent.Add(JDoc);
            end;
          end;
          JExtraUser.AddPair('content', JExtraContent);
          TargetArray.Add(JExtraUser);
        end;

        Exit;
      end;
    end;

    JUserObj := TJSonObject.Create;

    if Msg.Role = 'system' then
      JUserObj.AddPair('role', 'developer')
    else
      JUserObj.AddPair('role', Msg.Role);

    if Msg.Role = 'assistant' then
    begin
      // Only add the text message if it carries content (an assistant that
      // only made tool_calls arrives with empty Prompt).
      if Msg.Prompt.Trim <> '' then
      begin
        JUserObj.AddPair('content', Msg.Prompt);
        TargetArray.Add(JUserObj);
      end
      else
        JUserObj.Free;

      // History pass-through of function calling (chat-completions format:
      // assistant.tool_calls + role='tool' messages). The Responses API requires a
      // function_call item per call, with the same call_id that later
      // references the function_call_output — without this Azure/OpenAI rejects the
      // request with "No tool call found for function call output".
      if Msg.Tool_calls <> '' then
      begin
        var JTCParsed := TJSonObject.ParseJSONValue(Msg.Tool_calls);
        try
          if JTCParsed is TJSonArray then
            for var JTCItem in TJSonArray(JTCParsed) do
              if JTCItem is TJSonObject then
              begin
                var JTC := TJSonObject(JTCItem);
                var JFunc: TJSonObject := nil;
                JTC.TryGetValue<TJSonObject>('function', JFunc);
                var JCall := TJSonObject.Create;
                JCall.AddPair('type', 'function_call');
                JCall.AddPair('call_id', JTC.GetValue<string>('id', ''));
                if Assigned(JFunc) then
                begin
                  JCall.AddPair('name', JFunc.GetValue<string>('name', ''));
                  JCall.AddPair('arguments', JFunc.GetValue<string>('arguments', '{}'));
                end
                else
                begin
                  JCall.AddPair('name', JTC.GetValue<string>('name', ''));
                  JCall.AddPair('arguments', JTC.GetValue<string>('arguments', '{}'));
                end;
                TargetArray.Add(JCall);
              end;
        finally
          JTCParsed.Free;
        end;
      end;
      Exit;
    end;

    MediaArr := Msg.MediaFiles.ToMediaFileArray;
    PromptText := Msg.Prompt;
    ExtraFileRefs := '';

    if (Length(MediaArr) = 0) then
    begin
      JUserObj.AddPair('content', Msg.Prompt);
    end
    else
    begin
      JContentArr := TJSonArray.Create;

      for K := 0 to Length(MediaArr) - 1 do
      begin
        MediaFile := MediaArr[K];
        if (MediaFile.IdFile = '') and (MediaFile.Content.Size > 0) then
        begin
          try
            UploadFileToCache(MediaFile);
          except
            on E: Exception do
              LogDebug('Error uploading file to cache: ' + E.Message);
          end;
        end;

        case MediaFile.FileCategory of
          Tfc_Image:
            begin
              if Msg.Role = 'user' then
              begin
                JImageObj := TJSonObject.Create;
                JImageObj.AddPair('type', 'input_image');
                if (MediaFile.UrlMedia <> '') and (not MediaFile.UrlMedia.StartsWith('data:', True)) then
                  JImageObj.AddPair('image_url', MediaFile.UrlMedia)
                else
                  JImageObj.AddPair('image_url', 'data:' + MediaFile.MimeType + ';base64,' + MediaFile.Base64);
                if MediaFile.Detail <> '' then
                  JImageObj.AddPair('detail', MediaFile.Detail);
                JContentArr.Add(JImageObj);
              end;
            end;
          Tfc_pdf:
            begin
              JDocObj := TJSonObject.Create;
              JDocObj.AddPair('type', 'input_file');
              if MediaFile.IdFile <> '' then
                JDocObj.AddPair('file_id', MediaFile.IdFile)
              else if (MediaFile.UrlMedia <> '') and (not MediaFile.UrlMedia.StartsWith('data:', True)) then
                JDocObj.AddPair('file_url', MediaFile.UrlMedia)
              else
              begin
                if MediaFile.FileName <> '' then
                  JDocObj.AddPair('filename', MediaFile.FileName)
                else
                  JDocObj.AddPair('filename', 'document.pdf');
                JDocObj.AddPair('file_data', 'data:' + MediaFile.MimeType + ';base64,' + MediaFile.Base64);
              end;
              JContentArr.Add(JDocObj);
            end;
        else
          begin
            if MediaFile.IdFile <> '' then
            begin
              DataFilesList.Add(MediaFile.IdFile);
              ExtraFileRefs := ExtraFileRefs + Format(#13#10'[Attached File available in Python Tool: Name="%s"]', [MediaFile.FileName]);
            end;
          end;
        end;
      end;

      if (PromptText <> '') or (ExtraFileRefs <> '') then
      begin
        JTextObj := TJSonObject.Create;
        JTextObj.AddPair('type', 'input_text'); // Usuario siempre es input_text
        JTextObj.AddPair('text', PromptText + ExtraFileRefs);
        JContentArr.Add(JTextObj);
      end;

      JUserObj.AddPair('content', JContentArr);
    end;

    TargetArray.Add(JUserObj);
  end;

begin
  JResult := TJSonObject.Create;
  JToolsArray := nil;
  DataFilesList := TStringList.Create;
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  try
    JResult.AddPair('model', LModel);

    if FClient.Asynchronous then
      JResult.AddPair('stream', True);

    // 1. Instructions
    JSystemMsg := '';
    if (FMessages.Count > 0) and (FMessages[0].Role = 'system') then
      JSystemMsg := FMessages[0].Prompt
    else if SystemPrompt.Text <> '' then
      JSystemMsg := SystemPrompt.Text;

    if Memory.Count > 0 then
      JSystemMsg := JSystemMsg + sLineBreak + 'Memory context: ' + Memory.Text;

    if JSystemMsg <> '' then
      JResult.AddPair('instructions', JSystemMsg);

    // -------------------------------------------------------------------------
    // 2. INPUT (OPTIMIZED STATE MANAGEMENT)
    // -------------------------------------------------------------------------
    JInputArray := TJSonArray.Create;
    StartIndex := 0;
    LEffortAsConfigUpdate := False;

    // We check whether we have a valid response ID from the previous turn.
    // This allows using the server cache/context and avoids resending history.
    if (FResponseId <> '') and (FMessages.Count > 0) then
    begin
      JResult.AddPair('previous_response_id', FResponseId);

      LastMsg := FMessages[FMessages.Count - 1];

      // We detect whether we are in a tool loop (the last message is a tool output)
      // Note: We check for 'tool' or special assistant messages that contain outputs (legacy)
      IsToolLoop := (LastMsg.Role = 'tool') or ((LastMsg.Role = 'assistant') and ContainsText(LastMsg.Prompt, '_output"'));

      if IsToolLoop then
      begin
        // TOOL LOOP STRATEGY:
        // If we are sending a tool result, we MUST NOT resend the message
        // of the User that triggered the call, because that context already lives in 'previous_response_id'.
        // We search backwards until we find the previous User or Assistant message and cut there.
        for I := FMessages.Count - 1 downto 0 do
        begin
          if (FMessages[I].Role = 'user') or ((FMessages[I].Role = 'assistant') and (not ContainsText(FMessages[I].Prompt, '_output"'))) then
          begin
            StartIndex := I + 1; // We start strictly AFTER the user
            Break;
          end;
        end;
      end
      else
      begin
        // NORMAL STRATEGY (User Turn):
        // The last message is from the user. We look for the last assistant response to send only what is new.
        for I := FMessages.Count - 1 downto 0 do
        begin
          if (FMessages[I].Role = 'assistant') and (not ContainsText(FMessages[I].Prompt, '_output"')) then
          begin
            StartIndex := I + 1;
            Break;
          end;
        end;
      end;
    end;

    // -------------------------------------------------------------------------
    // 2b. CHANGE OF REASONING EFFORT MID-CONVERSATION
    // -------------------------------------------------------------------------
    // Changing 'reasoning.effort' at request level alters the prefix of the
    // conversation and throws away the entire prompt caching. The item
    // 'configuration_update' exists exactly for that: it applies from here on
    // forward (until another replaces it) without touching the prefix.
    //
    // It is only emitted when: (a) we continue a live conversation, (b) the
    // effort is different from the last one we sent and (c) the model understands it.
    // The gate (c) is per family and on purpose: a 'configuration_update'
    // against gpt-5.x returns 400. If a later family is added,
    // it must be added here.
    if (FResponseId <> '') and
       (ModelConfig.ThinkingLevel <> FLastEffortSent) and
       (ThinkingLevelToStr(ModelConfig.ThinkingLevel) <> '') and
       LModel.ToLower.StartsWith('gpt-6') then
    begin
      JConfigUpd := TJSonObject.Create;
      JConfigUpd.AddPair('type', 'configuration_update');
      JConfigUpd.AddPair('reasoning',
        TJSonObject.Create(TJSONPair.Create('effort', OpenAiEffort(LModel, ModelConfig.ThinkingLevel))));
      JInputArray.Add(JConfigUpd);
      LEffortAsConfigUpdate := True;
    end;
    FLastEffortSent := ModelConfig.ThinkingLevel;

    // We iterate from the calculated point (0 if new, >0 if continuation)
    for I := StartIndex to FMessages.Count - 1 do
    begin
      ItemMsg := FMessages[I];
      if (ItemMsg.Role <> 'system') then
        AddMessageToInput(ItemMsg, JInputArray);
    end;
    // -------------------------------------------------------------------------

    if JInputArray.Count > 0 then
      JResult.AddPair('input', JInputArray)
    else
      JInputArray.Free; // Avoid sending empty input if there are no new messages

    // 3. Configuration parameters
    JResult.AddPair('store', FStore);

    // Output limit. The Responses API calls it max_output_tokens (and INCLUDES
    // the reasoning tokens). Until 2026-09-30 this driver did not emit it
    // never and the component's Max_tokens was silently ignored: a client
    // asking max_tokens=200 received thousands of tokens. It is only emitted with a value
    // explicit (>0): the historical behavior was "no limit", and emitting the
    // component's default 3000 would cut off the reasoners mid-chain
    // -- whoever does not want a limit must set Max_tokens to 0.
    if Max_tokens > 0 then
      JResult.AddPair('max_output_tokens',
        TJSONNumber.Create(System.Math.Max(Max_tokens, 16)));
    if FTruncation <> 'disabled' then
      JResult.AddPair('truncation', FTruncation);

    // The effort goes at request level UNLESS we are continuing a
    // conversation and it has CHANGED: in that case it travels as an item
    // 'configuration_update' inside the input (see above), which is what
    // allows raising or lowering it without invalidating the cached prefix.
    if (not LEffortAsConfigUpdate) and
       ((ModelConfig.ThinkingLevel <> tlDefault) or (FReasoningSummary <> rsmDefault)) then
    begin
      JReasoning := TJSonObject.Create;
      // Full ladder: none / minimal / low / medium / high / xhigh / max.
      // ThinkingLevelToStr returns '' for tlDefault, which is "send nothing".
      if ThinkingLevelToStr(ModelConfig.ThinkingLevel) <> '' then
        JReasoning.AddPair('effort', OpenAiEffort(LModel, ModelConfig.ThinkingLevel));
      case FReasoningSummary of
        rsmAuto:
          JReasoning.AddPair('summary', 'auto');
        rsmConcise:
          JReasoning.AddPair('summary', 'concise');
        rsmDetailed:
          JReasoning.AddPair('summary', 'detailed');
      end;
      JResult.AddPair('reasoning', JReasoning);
    end;


    JTextConfig := TJSonObject.Create;
    if FVerbosity <> '' then
      JTextConfig.AddPair('verbosity', FVerbosity);


    // 3 - Json format -----------------------------------------


// 1. Configure Structured Output (JSON Schema)

JFormatConfig := Nil;
    if FResponse_format = tiaChatRfJsonSchema then
    begin
      // The Responses API requires name+schema at the same level as type in text.format
      // (flattened structure, NOT a json_schema sub-object) — without them the request
      // fails with 400. JsonSchema accepts the pure schema or the full wrapper
      // {name, strict, schema}.
      var sSchemaName := 'structured_response';
      var bStrict := True;
      var JInnerSchema := ParseJsonSchemaProperty(sSchemaName, bStrict);

      // A. TYPE OBJECT VALIDATION (only in strict mode, which requires
      // additionalProperties=false and all properties in 'required')
      var sSchemaType := '';
      if bStrict and JInnerSchema.TryGetValue<string>('type', sSchemaType) and (sSchemaType = 'object') then
      begin
         // 1. CORRECTION: additionalProperties: false is mandatory
         if JInnerSchema.GetValue('additionalProperties') = nil then
           JInnerSchema.AddPair('additionalProperties', TJSONBool.Create(False));

         // 2. CORRECTION: OpenAI Strict requires that ALL properties be in 'required'
         var JProps: TJSONObject;
         if JInnerSchema.TryGetValue<TJSONObject>('properties', JProps) then
         begin
           var JReq: TJSonArray;
           // Get or create 'required' array
           if not JInnerSchema.TryGetValue<TJSonArray>('required', JReq) then
           begin
             JReq := TJSonArray.Create;
             JInnerSchema.AddPair('required', JReq);
           end;

           // Iterate over all properties and ensure they are in 'required'
           for var I1 := 0 to JProps.Count - 1 do
           begin
             var PropName := JProps.Pairs[I1].JsonString.Value;
             var Found := False;

             for var K := 0 to JReq.Count - 1 do
             begin
               if JReq.Items[K].Value = PropName then
               begin
                 Found := True;
                 Break;
               end;
             end;

             // If missing, we add it to satisfy the API
             if not Found then
               JReq.Add(PropName);
           end;
         end;
      end;

      // B. FINAL CONFIGURATION (Flattened structure for Responses API)
      // These parameters go at the same level as "type", NOT inside a json_schema sub-object
      JFormatConfig := TJSonObject.Create;
      JFormatConfig.AddPair('type', 'json_schema');
      JFormatConfig.AddPair('name', sSchemaName);
      JFormatConfig.AddPair('strict', TJSONBool.Create(bStrict));
      JFormatConfig.AddPair('schema', JInnerSchema);
    end
    // 2. Configure Simple JSON (For when it is not strict Schema)
    else if FResponse_format = tiaChatRfJson then
    begin
      JFormatConfig := TJSonObject.Create;
      JFormatConfig.AddPair('type', 'json_object');
    end;

    // 3. Connect the format configuration to the Text object
    if Assigned(JFormatConfig) then
    begin
      // Ensure that JTextConfig exists (in case it was not created with verbosity earlier)
      if not Assigned(JTextConfig) then
        JTextConfig := TJSonObject.Create;

      JTextConfig.AddPair('format', JFormatConfig);
    end;

    // 4. Connect the Text object to the Root of the Request (JResult)
    // This is what makes it appear in the final JSON sent to the API
    if Assigned(JTextConfig) and (JTextConfig.Count > 0) then
    begin
      // We verify if 'text' already exists (rare, but for safety)
      if JResult.GetValue('text') = nil then
        JResult.AddPair('text', JTextConfig)
      else
        JTextConfig.Free;  // 'text' already exists, cannot add it
    end
    else
      FreeAndNil(JTextConfig);  // empty, not used




    // ---- 4. TOOLS -----------------------------------------
    if Tool_Active and Assigned(AiFunctions) then
    begin
      JToolsArray := GetTools(AiFunctions);

      // 'async' is only understood by gpt-6-astra onwards. The formatter for
      // Responses is the SAME for the entire OpenAi family, so without this
      // pruning, a tool declared async against a gpt-5.x would go with a field
      // that that model rejects. It is cleaned here, which is the only point where
      // the target model is known. Add later families here.
      if Assigned(JToolsArray) and (not LModel.ToLower.StartsWith('gpt-6')) then
        for var LTIdx := 0 to JToolsArray.Count - 1 do
          if JToolsArray.Items[LTIdx] is TJSonObject then
            TJSonObject(JToolsArray.Items[LTIdx]).RemovePair('async').Free;
    end;

    if (cap_Shell in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;
      var
      JShellTool := TJSonObject.Create;
      JShellTool.AddPair('type', 'shell');
      JToolsArray.Add(JShellTool);
    end;

    if (cap_ComputerUse in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;
      // 'computer' tool (gpt-6-astra, Aug 2026). It does NOT carry parameters: neither
      // display_width/display_height nor environment (the API responds
      // "Unknown parameter"). The model deduces dimensions from the
      // screenshot, so ScreenWidth/ScreenHeight of TAiComputerUseTool
      // are only used locally to normalize coordinates back.
      // It replaces computer_use_preview, whose dedicated model was shut down on
      // 23-Jul-2026 and that astra already rejects.
      var
      JComputerTool := TJSonObject.Create;
      JComputerTool.AddPair('type', 'computer');
      JToolsArray.Add(JComputerTool);
    end;

    if (cap_GenImage in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;
      var
      JImgTool := TJSonObject.Create;
      JImgTool.AddPair('type', 'image_generation');
      if ImageParams.Params.Count > 0 then
      begin
        if ImageParams.Params.Values['size'] <> '' then
          JImgTool.AddPair('size', ImageParams.Params.Values['size']);
        if ImageParams.Params.Values['quality'] <> '' then
          JImgTool.AddPair('quality', ImageParams.Params.Values['quality']);
      end;
      JToolsArray.Add(JImgTool);
    end;

    if (cap_CodeInterpreter in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;
      var
      JCodeTool := TJSonObject.Create;
      JCodeTool.AddPair('type', 'code_interpreter');
      var
      JContainer := TJSonObject.Create;
      JContainer.AddPair('type', 'auto');
      if DataFilesList.Count > 0 then
      begin
        var
        JFileIdsArr := TJSonArray.Create;
        for var FID in DataFilesList do
          JFileIdsArr.Add(FID);
        JContainer.AddPair('file_ids', JFileIdsArr);
      end;
      JCodeTool.AddPair('container', JContainer);
      JToolsArray.Add(JCodeTool);
    end;

    if (cap_TextEditor in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;

      var
      JPatchTool := TJSonObject.Create;
      JPatchTool.AddPair('type', 'apply_patch');
      JToolsArray.Add(JPatchTool);
    end;

    if (cap_WebSearch in ModelConfig.ModelCaps) then
    begin
      if not Assigned(JToolsArray) then
        JToolsArray := TJSonArray.Create;

      var
      JWebTool := TJSonObject.Create;
      JWebTool.AddPair('type', 'web_search');

      // If the user configured additional parameters in WebSearchParams (e.g., count=5)
      if (WebSearchParams.Params.Count > 0) then
      begin
        var
        JWebOptions := TJSonObject.Create;
        // We iterate over the key=value list
        for var I1 := 0 to WebSearchParams.Params.Count - 1 do
        begin
          var
          Key := WebSearchParams.Params.Names[I1];
          var
          Val := WebSearchParams.Params.ValueFromIndex[I1];

          if Key <> '' then
          begin
            // We try to detect if it is a number, boolean or string
            var
              IntVal: Integer;
            var
              BoolVal: Boolean;

            if TryStrToInt(Val, IntVal) then
              JWebOptions.AddPair(Key, TJSONNumber.Create(IntVal))
            else if TryStrToBool(Val, BoolVal) then
              JWebOptions.AddPair(Key, TJSONBool.Create(BoolVal))
            else
              JWebOptions.AddPair(Key, Val);
          end;
        end;

        // We only add the options object if something was actually added
        if JWebOptions.Count > 0 then
          JWebTool.AddPair('web_search', JWebOptions)
        else
          JWebOptions.Free;
      end;

      JToolsArray.Add(JWebTool);
    end;

    if Assigned(JToolsArray) then
    begin
      if JToolsArray.Count > 0 then
      begin
        JResult.AddPair('tools', JToolsArray);
        if FParallel_ToolCalls then
          JResult.AddPair('parallel_tool_calls', True);
        if Tool_choice <> '' then
        begin
          if (Tool_choice = 'auto') or (Tool_choice = 'required') or (Tool_choice = 'none') then
            JResult.AddPair('tool_choice', Tool_choice)
          else
            JResult.AddPair('tool_choice', TJSonObject.ParseJSONValue(Tool_choice));
        end;
      end
      else
        JToolsArray.Free;
    end;

    ApplyExtraBodyParams(JResult);
    Result := JResult.ToString;
  finally
    JResult.Free;
    DataFilesList.Free;
  end;
end;



// -----------------------------------------------------------------------------
// PROCESAMIENTO DE RESPUESTA
// -----------------------------------------------------------------------------

procedure TAiOpenChat.ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage);
var
  JOutput, JContent, JAnnotations: TJSonArray;
  JItem, JContentItem, JAnno: TJSonObject;
  // New variables for metadata capture
  JUsage, JUsageDetails, JInputDetails, JIncomplete: TJSonObject;
  SType, SVal, SId, SCallId, SContainerId: String;
  I, K, A: Integer;
  ToolCalls: TObjectList<TAiToolsFunction>;
  ToolCall: TAiToolsFunction;
  TaskList: array of ITask;
  NewMsg: TAiChatMessage;
  GeneratedFile: TAiMediaFile;
  WebItem: TAiWebSearchItem;
  // Computer Use: astra suele emitir texto de comentario JUNTO con el
  // computer_call (phase='commentary'), asi que FLastContent no queda vacio y
  // la condicion normal de recursion no dispararia. Esta bandera fuerza el
  // siguiente ciclo para que la IA vea el screenshot resultante.
  LComputerCallDone: Boolean;
  // Variables auxiliares para valores num?ricos
  UnixDate: Int64;
  TokenCount: Int64;

  // Local subroutine: guarantees independent capture by value in Delphi 10.4+
  procedure _CreateTask(TC: TAiToolsFunction; AIdx: Integer);
  begin
    TaskList[AIdx] := TTask.Create(
      procedure
      begin
        try
          DoCallFunction(TC);
        except
          on E: Exception do
          begin
            TC.Response := '{"error": "' + StringReplace(E.Message, '"', '''', [rfReplaceAll]) + '"}';
            TThread.Queue(nil,
              procedure
              begin
                DoError('Function Execution Error: ' + TC.Name, E);
              end);
          end;
        end;
      end);
    TaskList[AIdx].Start;
  end;

begin
  // 1. Update global response status
  if jObj.TryGetValue<String>('id', SVal) then
    FResponseId := SVal;
  if jObj.TryGetValue<String>('status', SVal) then
    UpdateResponseStatus(SVal);

  // ---------------------------------------------------------------------------
  // NEW BLOCK: Capture Metadata (Model, CreatedAt, Usage, FinishReason)
  // ---------------------------------------------------------------------------

  // A) CREATION DATE
  if jObj.TryGetValue<Int64>('created_at', UnixDate) then
  begin
    // Requires System.DateUtils in the uses
    // ResMsg.CreatedAt := TTimeZone.Local.ToLocalTime(UnixToDateTime(UnixDate));
  end;

  // B) EXACT MODEL USED
  if jObj.TryGetValue<String>('model', SVal) then
    ResMsg.Model := SVal;


  // C) COMPLETION INFORMATION (Finish Reason / Incomplete Details)
  // incomplete_details may come as null in the JSON; using TJSONValue avoids
  // the typecast failure when the value is not an object.
  var JVal: TJSONValue;
  JVal := jObj.GetValue('incomplete_details');
  if Assigned(JVal) and (JVal is TJSONObject) then
  begin
    JIncomplete := TJSONObject(JVal);
    if JIncomplete.TryGetValue<String>('reason', SVal) then
      ResMsg.FinishReason := SVal; // e.g.: "max_tokens", "safety"
  end
  else
  begin
    // incomplete_details absent or null: if status is completed, normal completion
    if FResponseStatus = 'completed' then
      ResMsg.FinishReason := 'stop';
  end;

  // D) TOKEN USAGE (Costs, Cache and Reasoning)
  if jObj.TryGetValue<TJSonObject>('usage', JUsage) then
  begin
    var LPrompt: Int64 := 0;
    var LCompletion: Int64 := 0;
    var LTotal: Int64 := 0;
    var LCached: Int64 := 0;
    var LCacheWrite: Int64 := 0;

    // Basic totals
    if JUsage.TryGetValue<Int64>('input_tokens', TokenCount) then
    begin
      ResMsg.Prompt_tokens := TokenCount;
      LPrompt := TokenCount;
    end;

    if JUsage.TryGetValue<Int64>('output_tokens', TokenCount) then
    begin
      ResMsg.Completion_tokens := TokenCount;
      LCompletion := TokenCount;
    end;

    if JUsage.TryGetValue<Int64>('total_tokens', TokenCount) then
    begin
      ResMsg.Total_tokens := TokenCount;
      LTotal := TokenCount;
    end;

    // Input Details: Tokens in Cache (Savings)
    if JUsage.TryGetValue<TJSonObject>('input_tokens_details', JInputDetails) then
    begin
      if JInputDetails.TryGetValue<Int64>('cached_tokens', TokenCount) then
      begin
        ResMsg.cached_tokens := TokenCount;
        LCached := TokenCount;
      end;

      // Cache write. Until GPT-5.5 it was free and the Responses API did not
      // report it; from GPT-5.6 it costs 1.25x the input and arrives in this same
      // object as 'cache_write_tokens'. Without reading it, the billing sees zero
      // writes always and that expense is neither charged nor recorded.
      if JInputDetails.TryGetValue<Int64>('cache_write_tokens', TokenCount) then
      begin
        ResMsg.Cache_write_tokens := TokenCount;
        LCacheWrite := TokenCount;
      end;
    end;

    // The three counters are left DISJOINT before leaving here.
    //
    // In the Responses API 'input_tokens' INCLUDES the cached and the
    // write tokens (measured against the API: input_tokens 7613 = 3 new + 7610 of
    // cache_write). Anthropic reports them separately and TAiClaudeChat exposes them
    // like that, so that the billing adds all three. Leaving them overlapping causes
    // cached tokens to be charged twice: once at input rate
    // full and once at cache rate.
    //
    // The subtraction is only applied if they are indeed contained (prompt >= cache).
    // If a provider already gave them separated, the condition is not met and nothing
    // is touched: the correction cannot backfire.
    if (LCached + LCacheWrite) > 0 then
    begin
      if LPrompt >= (LCached + LCacheWrite) then
      begin
        LPrompt := LPrompt - LCached - LCacheWrite;
        ResMsg.Prompt_tokens := LPrompt;
      end;
    end;

    // Output Details: Reasoning Tokens (Thinking)
    if JUsage.TryGetValue<TJSonObject>('output_tokens_details', JUsageDetails) then
    begin
      if JUsageDetails.TryGetValue<Int64>('reasoning_tokens', TokenCount) then
        ResMsg.Thinking_tokens := TokenCount;
    end;

    // Component counters. This override only fed ResMsg, and who
    // reads the component tokens (Prompt_tokens) received 0 with any
    // model served by this driver. The base class (uMakerAi.Chat.pas, ParseChat)
    // and TAiClaudeChat.ParseChat do accumulate them; here it was missing.
    // They are ACCUMULATED by round, like in those two, so that a tool calling loop
    // does not lose the intermediate rounds.
    Self.Prompt_tokens := Self.Prompt_tokens + Integer(LPrompt);
    Self.Completion_tokens := Self.Completion_tokens + Integer(LCompletion);
    Self.Total_tokens := Self.Total_tokens + Integer(LTotal);
    Self.Cached_tokens := Self.Cached_tokens + Integer(LCached);
    Self.Cache_write_tokens := Self.Cache_write_tokens + Integer(LCacheWrite);
  end;

  // ---------------------------------------------------------------------------
  // END NEW BLOCK
  // ---------------------------------------------------------------------------

  FLastContent := '';
  ToolCalls := TObjectList<TAiToolsFunction>.Create;

  try
    LComputerCallDone := False;

    // 2. Iterate over the 'output' array (Polymorphism: Messages, Tools, Images)
    if jObj.TryGetValue<TJSonArray>('output', JOutput) then
    begin
      for I := 0 to JOutput.Count - 1 do
      begin
        JItem := TJSonObject(JOutput.Items[I]);
        if not JItem.TryGetValue<String>('type', SType) then
          Continue;

        // --- TYPE: MESSAGE ---
        if SType = 'message' then
        begin
          if JItem.TryGetValue<TJSonArray>('content', JContent) then
          begin
            for K := 0 to JContent.Count - 1 do
            begin
              JContentItem := TJSonObject(JContent.Items[K]);
              if JContentItem.TryGetValue<String>('type', SVal) then
              begin
                // A) TEXT
                if (SVal = 'output_text') then
                begin
                  if JContentItem.TryGetValue<String>('text', SVal) then
                    FLastContent := FLastContent + SVal;

                  // B) ANNOTATIONS (Citations and Files)
                  if JContentItem.TryGetValue<TJSonArray>('annotations', JAnnotations) then
                  begin
                    for A := 0 to JAnnotations.Count - 1 do
                    begin
                      JAnno := JAnnotations.Items[A] as TJSonObject;
                      if not JAnno.TryGetValue<string>('type', SVal) then
                        Continue;

                      // 1. GENERATED FILES (Code Interpreter)
                      if SVal = 'container_file_citation' then
                      begin
                        GeneratedFile := TAiMediaFile.Create;

                        // We capture the file_id
                        if JAnno.TryGetValue<string>('file_id', SId) then
                          GeneratedFile.IdFile := SId;

                        // We capture the name
                        if JAnno.TryGetValue<string>('filename', SId) then
                          GeneratedFile.FileName := SId;

                        // CRITICAL: We capture the container_id and save it in CloudState
                        if JAnno.TryGetValue<string>('container_id', SContainerId) then
                          GeneratedFile.CloudState := SContainerId;

                        try
                          DownLoadFile(GeneratedFile);
                        except
                          on E: Exception do
                            LogDebug('Error downloading container file: ' + E.Message);
                        end;

                        // Add to the response message
                        ResMsg.MediaFiles.Add(GeneratedFile);
                      end

                      // -- Web Citations (Web Search) --
                      else if SVal = 'url_citation' then
                      begin
                        if not Assigned(ResMsg.WebSearchResponse) then
                        begin
                          ResMsg.WebSearchResponse := TAiWebSearch.Create;
                          ResMsg.WebSearchResponse.&type := 'web_search_results';
                        end;

                        WebItem := TAiWebSearchItem.Create;
                        WebItem.&type := 'url_citation';
                        JAnno.TryGetValue<Integer>('start_index', WebItem.start_index);
                        JAnno.TryGetValue<Integer>('end_index', WebItem.end_index);
                        JAnno.TryGetValue<string>('url', WebItem.Url);
                        JAnno.TryGetValue<string>('title', WebItem.title);

                        ResMsg.WebSearchResponse.annotations.Add(WebItem);
                      end;
                    end;
                  end;
                end
                // C) REFUSAL (Safety denial)
                else if (SVal = 'refusal') then
                begin
                  if JContentItem.TryGetValue<String>('refusal', SVal) then
                    FLastContent := FLastContent + ' [REFUSAL: ' + SVal + ']';
                  ResMsg.IsRefusal := True;
                end;
              end;
            end;
          end;
        end

        // --- TYPE: IMAGE GENERATION ---
        else if SType = 'image_generation_call' then
        begin
          var
          ImgBase64 := '';
          var
          ImgPrompt := '';
          var
          ImgId := '';
          var
          ImgFormat := 'png'; // Default value

          // 1. Get the Base64: The Responses API uses 'result', but we leave 'image' for safety
          if not JItem.TryGetValue<string>('result', ImgBase64) then
            JItem.TryGetValue<string>('image', ImgBase64);

          if ImgBase64 <> '' then
          begin
            // 2. Extract metadata
            JItem.TryGetValue<string>('revised_prompt', ImgPrompt);
            JItem.TryGetValue<string>('id', ImgId);
            JItem.TryGetValue<string>('output_format', ImgFormat);

            if ImgId = '' then
              ImgId := 'gen_' + IntToStr(TThread.GetTickCount);

            // 3. Create MediaFile
            GeneratedFile := TAiMediaFile.Create;

            // Load the content (Base64)
            GeneratedFile.LoadFromBase64(ImgId + '.' + ImgFormat, ImgBase64);

            // Save the revised prompt in Transcription
            GeneratedFile.Transcription := ImgPrompt;

            // Save the ID
            GeneratedFile.IdFile := ImgId;

            // 4. Add to the current response message
            ResMsg.MediaFiles.Add(GeneratedFile);

            // 5. If the text message comes empty, we put an indicator in the Prompt
            if ResMsg.Prompt = '' then
              ResMsg.Prompt := '[Image Generated] ' + Copy(ImgPrompt, 1, 50) + '...';
          end;
        end

        // --- TYPE: FUNCTION CALL (STANDARD TOOL) ---
        else if SType = 'function_call' then
        begin
          ToolCall := TAiToolsFunction.Create;

          // CRITICAL: Get call_id to respond later
          if JItem.TryGetValue<String>('call_id', SCallId) then
            ToolCall.Id := SCallId
          else if JItem.TryGetValue<String>('id', SId) then
            ToolCall.Id := SId;

          if JItem.TryGetValue<String>('name', SVal) then
            ToolCall.Name := SVal;
          if JItem.TryGetValue<String>('arguments', SVal) then
            ToolCall.Arguments := SVal;
          // Async tool flag: the turn does NOT block waiting for this
          // result, which can be delivered later with the same call_id.
          ToolCall.IsAsync := JItem.GetValue<Boolean>('async', False);

          ToolCalls.Add(ToolCall);
        end

        // --- TYPE: SHELL CALL (WITH TAISHELL AND LEGACY SUPPORT) ---
        else if SType = 'shell_call' then
        begin
          if JItem.TryGetValue<String>('call_id', SCallId) then
          begin
            // -----------------------------------------------------------------
            // 1. SAVE THE REQUEST (CALL) IN THE HISTORY
            // -----------------------------------------------------------------
            // We save the raw JSON of the 'shell_call' item as an assistant message.
            // This is crucial to maintain the chain: User -> ShellCall -> ShellOutput -> User
            var
            HistMsg := TAiChatMessage.Create(JItem.ToString, 'assistant');
            HistMsg.ToolCallId := SCallId;
            HistMsg.PreviousResponseId := FResponseId;
            HistMsg.Id := Self.Messages.Count + 1;
            Self.Messages.Add(HistMsg);

            // -----------------------------------------------------------------
            // 2. EXECUTE COMMANDS
            // -----------------------------------------------------------------
            var
              JAction: TJSonObject;
            if JItem.TryGetValue<TJSonObject>('action', JAction) then
            begin

              // OPTION A: Use ShellTool Component (Persistent Session)
              if Assigned(ChatTools.ShellTool) then
              begin
                // We delegate execution and JSON response formatting to the component
                var
                ShellJsonOutput := ChatTools.ShellTool.Execute(SCallId, JAction);

                // Create and save the tool response message
                NewMsg := TAiChatMessage.Create(ShellJsonOutput, 'tool');
                NewMsg.ToolCallId := SCallId;
                NewMsg.PreviousResponseId := FResponseId;
                NewMsg.Id := Self.Messages.Count + 1;
                Self.Messages.Add(NewMsg);
              end

              // OPTION B: Legacy Fallback (Isolated Execution)
              else
              begin
                var
                  Commands: TJSonArray;
                var
                  MaxLen: Integer := 0;

                JAction.TryGetValue<TJSonArray>('commands', Commands);
                JAction.TryGetValue<Integer>('max_output_length', MaxLen);

                var
                JOutputArr := TJSonArray.Create;

                // Iterate commands
                if Assigned(Commands) then
                  for var C := 0 to Commands.Count - 1 do
                  begin
                    var
                    CmdStr := Commands.Items[C].Value;
                    var
                    OutStd := '';
                    var
                    OutErr := '';
                    var
                    ExitCode := 0;
                    var
                    Handled := False;

                    // 1. User Event
                    if Assigned(FOnShellCommand) then
                      FOnShellCommand(Self, CmdStr, SCallId, OutStd, OutErr, ExitCode, Handled);

                    // 2. Automatic Execution
                    if (not Handled) and FAllowAutoShell then
                    begin
                      try
                        OutStd := TUtilsSystem.RunCommandLine(CmdStr);
                        ExitCode := 0;
                      except
                        on E: Exception do
                        begin
                          OutErr := E.Message;
                          ExitCode := 1;
                        end;
                      end;
                    end
                    else if not Handled then
                    begin
                      OutErr := 'Shell execution denied (ShellTool not assigned and AllowAutoShell=False).';
                      ExitCode := 126;
                    end;

                    // Truncate if necessary
                    if (MaxLen > 0) and (Length(OutStd) > MaxLen) then
                      OutStd := Copy(OutStd, 1, MaxLen) + '... [truncated]';

                    // Build individual command response
                    var
                    JCmdRes := TJSonObject.Create;
                    JCmdRes.AddPair('stdout', OutStd);
                    JCmdRes.AddPair('stderr', OutErr);

                    var
                    JOutcome := TJSonObject.Create;
                    JOutcome.AddPair('type', 'exit');
                    JOutcome.AddPair('exit_code', ExitCode);
                    JCmdRes.AddPair('outcome', JOutcome);

                    JOutputArr.Add(JCmdRes);
                  end;

                // Build final shell_call_output
                var
                OutputJson := TJSonObject.Create;
                try
                  OutputJson.AddPair('type', 'shell_call_output');
                  OutputJson.AddPair('call_id', SCallId);
                  if MaxLen > 0 then
                    OutputJson.AddPair('max_output_length', MaxLen);
                  OutputJson.AddPair('output', JOutputArr);

                  // Add message to the queue
                  NewMsg := TAiChatMessage.Create(OutputJson.ToString, 'tool');
                  NewMsg.ToolCallId := SCallId;
                  NewMsg.PreviousResponseId := FResponseId;
                  NewMsg.Id := Self.Messages.Count + 1;
                  Self.Messages.Add(NewMsg);
                finally
                  OutputJson.Free;
                end;
              end;
            end;
          end;
        end

        // --- TYPE: COMPUTER CALL (SCREEN CONTROL) ---
        // gpt-6-astra sends a BATCH: a single computer_call with an 'actions' array
        // (e.g., keypress[WIN,r] + type 'notepad' + keypress[ENTER]). They are executed in
        // order and respond with a SINGLE computer_call_output per call_id, with the
        // final screenshot: the API requires exactly one output per call.
        else if SType = 'computer_call' then
        begin
          if JItem.TryGetValue<String>('call_id', SCallId) then
          begin
            // 1. Save the raw call in history (chain User -> Call -> Output)
            var
            HistCU := TAiChatMessage.Create(JItem.ToString, 'assistant');
            HistCU.ToolCallId := SCallId;
            HistCU.PreviousResponseId := FResponseId;
            HistCU.Id := Self.Messages.Count + 1;
            Self.Messages.Add(HistCU);

            var
              LShot: TAiMediaFile;
            var
              LDelegated: Boolean;
            LShot := nil;
            // Delegated batch: no one runs it in this process. Either because the
            // interceptor claimed it, or because there is no way to do it here.
            LDelegated := False;
            try
              // 2. Execute ALL actions of the batch, in order
              var
                JActions: TJSonArray;
              if not Assigned(ChatTools.ComputerUseTool) then
              begin
                // cap_ComputerUse declares the tool to the model, so the model
                // is going to use it: without the component there is no executor or capture, and
                // a computer_call_output without image_url is a guaranteed 400. It is left
                // the raw call in history and the turn is cut, notifying,
                // because this is incomplete configuration: in OpenAI the only
                // interception point (OnCallToolFunction) lives INSIDE the
                // traversal of 'actions', which requires the component.
                LDelegated := True;
                FLastError := 'computer_call ' + SCallId +
                  ': cap_ComputerUse is active but ChatTools.ComputerUseTool is not '
                  + 'assigned. The turn is cut without responding to the model.';
                DoError(FLastError, nil);
              end
              else if not JItem.TryGetValue<TJSonArray>('actions', JActions) then
              begin
                // Unexpected form of the item: astra always sends an array
                // 'actions', even if the batch is of a single action.
                LDelegated := True;
                FLastError := 'computer_call ' + SCallId +
                  ': el item no trae el array "actions" esperado.';
                DoError(FLastError, nil);
              end
              else
              begin
                for var Ai := 0 to JActions.Count - 1 do
                begin
                  var
                  JAct := JActions.Items[Ai] as TJSonObject;
                  var
                  LCU := TAiToolsFunction.Create;
                  try
                    LCU.Id := SCallId;
                    LCU.Name := JAct.GetValue<string>('type', '');
                    LCU.Arguments := JAct.ToJSON;
                    ChatTools.ComputerUseTool.TranslateOpenAIToolCall(LCU);

                    if Assigned(FOnCallToolFunction) then
                      FOnCallToolFunction(Self, LCU);

                    // Same contract as Claude and the generic bridge of
                    // TAiChat: if the interceptor filled Response, it is not executed
                    // locally. Here the delegation is ATOMIC over the batch
                    // complete: a computer_call is a unit with a single
                    // computer_call_output, and splitting its actions between a
                    // local executor and a remote one would leave the final screenshot
                    // ownerless. The first claimed action gives up the rest.
                    if LCU.Response <> '' then
                    begin
                      LDelegated := True;
                      Break;
                    end;

                    // Only the photo after the LAST action matters: the
                    // intermediate ones are discarded to not inflate tokens or latency.
                    FreeAndNil(LShot);
                    ChatTools.ComputerUseTool.ProcessToolCall(LCU, LShot);
                  finally
                    LCU.Free;
                  end;
                end;

                // If the batch did not leave a screenshot (failed action or denied by
                // security), one is forced: the output cannot be left without
                // an image (the API asks for exactly one of image_url or file_id),
                // and also the model needs to see the resulting state.
                if (not LDelegated) and (not Assigned(LShot)) then
                begin
                  var
                  LSnap := TAiToolsFunction.Create;
                  try
                    LSnap.Id := SCallId;
                    LSnap.Name := 'screenshot';
                    LSnap.Arguments := '{}';
                    ChatTools.ComputerUseTool.ProcessToolCall(LSnap, LShot);
                  finally
                    LSnap.Free;
                  end;
                end;
              end;

              // 3. Return a single computer_call_output with the final image.
              //    If the batch was delegated, nothing is answered and no
              //    LComputerCallDone is marked: without output to send, recursing would only
              //    cause the model to receive the same call twice.
              if (not LDelegated) and (not Assigned(LShot)) then
              begin
                // The output requires exactly one image (image_url or
                // file_id). Without a screenshot -- normally because the
                // TAiComputerUseTool does not have OnExecuteAction /
                // OnRequestScreenshot assigned -- sending it is a guaranteed 400
                // so the turn is cut and recorded.
                FLastError := 'computer_call ' + SCallId +
                  ': no se pudo capturar la pantalla. Revise OnExecuteAction '
                  + 'y OnRequestScreenshot del TAiComputerUseTool.';
                DoError(FLastError, nil);
              end
              else if not LDelegated then
              begin
                LComputerCallDone := True;

                var
                JCUOut := TJSonObject.Create;
                try
                  JCUOut.AddPair('type', 'computer_call_output');
                  JCUOut.AddPair('call_id', SCallId);
                  var
                  JShotObj := TJSonObject.Create;
                  JShotObj.AddPair('type', 'computer_screenshot');
                  if Assigned(LShot) then
                    JShotObj.AddPair('image_url', 'data:' + LShot.MimeType + ';base64,' + LShot.Base64);
                  JCUOut.AddPair('output', JShotObj);

                  NewMsg := TAiChatMessage.Create(JCUOut.ToString, 'tool');
                  NewMsg.ToolCallId := SCallId;
                  NewMsg.PreviousResponseId := FResponseId;
                  NewMsg.Id := Self.Messages.Count + 1;
                  Self.Messages.Add(NewMsg);
                finally
                  JCUOut.Free;
                end;
              end;
            finally
              FreeAndNil(LShot);
            end;
          end;
        end

        // --- TYPE: APPLY PATCH (FILE EDITING) ---
        else if SType = 'apply_patch_call' then
        begin
          // 1. Extract operation data
          var
          OpType := '';
          var
          OpPath := '';
          var
          OpDiff := '';

          if JItem.TryGetValue<String>('call_id', SCallId) then
          begin
            var
              JOp: TJSonObject;
            if JItem.TryGetValue<TJSonObject>('operation', JOp) then
            begin
              JOp.TryGetValue<string>('type', OpType);
              JOp.TryGetValue<string>('path', OpPath);
              JOp.TryGetValue<string>('diff', OpDiff);
            end;

            var
            PatchStatus := 'failed';
            var
            PatchOutput := '';
            var
            Handled := False;

            // OPTION A: User Event
            if Assigned(FOnApplyPatch) then
            begin
              try
                FOnApplyPatch(Self, OpType, OpPath, OpDiff, SCallId, PatchStatus, PatchOutput);
                Handled := True;
              except
                on E: Exception do
                begin
                  PatchStatus := 'failed';
                  PatchOutput := 'Exception in OnApplyPatch: ' + E.Message;
                  Handled := True;
                end;
              end;
            end;

            // OPTION B: Automatic (TAiTextEditorTool)
            if (not Handled) and (Assigned(ChatTools.TextEditorTool)) then
            begin
              try
                var
                JCmd := TJSonObject.Create;
                try
                  if OpType = 'delete_file' then
                  begin
                    JCmd.AddPair('command', 'delete');
                    JCmd.AddPair('path', OpPath);
                  end
                  else
                  begin
                    JCmd.AddPair('command', 'apply_diff');
                    JCmd.AddPair('path', OpPath);
                    JCmd.AddPair('diff_text', OpDiff);
                  end;

                  var
                  ResStr := ChatTools.TextEditorTool.Execute(JCmd.ToString);

                  if ResStr.StartsWith('Error') then
                  begin
                    PatchStatus := 'failed';
                    PatchOutput := ResStr;
                  end
                  else
                  begin
                    PatchStatus := 'completed';
                    PatchOutput := ResStr;
                  end;
                finally
                  JCmd.Free;
                end;
              finally
              end;
            end;

            // 4. Create response message
            var
            OutputJson := TJSonObject.Create;
            try
              OutputJson.AddPair('type', 'apply_patch_call_output');
              OutputJson.AddPair('call_id', SCallId);
              OutputJson.AddPair('status', PatchStatus);
              if PatchOutput <> '' then
                OutputJson.AddPair('output', PatchOutput);

              NewMsg := TAiChatMessage.Create(OutputJson.ToString, 'tool');
              NewMsg.ToolCallId := SCallId;
              NewMsg.PreviousResponseId := FResponseId;
              NewMsg.Id := Self.Messages.Count + 1;
              Self.Messages.Add(NewMsg);
            finally
              OutputJson.Free;
            end;
          end;
        end;
      end;
    end;

    // 3. Finish processing the text message
    ResMsg.Prompt := FLastContent;
    ResMsg.PreviousResponseId := FResponseId;

    // 4. Execute standard Tools (Functions) if any
    if ToolCalls.Count > 0 then
    begin
      SetLength(TaskList, ToolCalls.Count);

      for I := 0 to ToolCalls.Count - 1 do
      begin
        ToolCall := ToolCalls[I];
        ToolCall.ResMsg := ResMsg;
        ToolCall.AskMsg := GetLastMessage; // Context

        _CreateTask(ToolCall, I); // local subroutine guarantees capture by value
      end;

      // Pump Synchronize/Queue while waiting, to avoid hanging the app if a
      // tool call accesses VCL/FMX via TThread.Synchronize (issue #103).
      // WARNING: CheckSynchronize is ONLY valid in the main thread; in secondary threads
      // (e.g., Indy workers of a headless service) it THROWS an exception
      // "CheckSynchronize called from thread X". Outside the main thread we only
      // wait (tool calls that touch UI no longer apply). Same criterion as
      // TMCPClientSSE.WaitForInitialization.
      while not TTask.WaitForAll(TaskList, 10) do
        if TThread.CurrentThread.ThreadID = MainThreadID then
          CheckSynchronize(0)
        else
          Sleep(10);

      // Create tool response messages
      for I := 0 to ToolCalls.Count - 1 do
      begin
        ToolCall := ToolCalls[I];
        NewMsg := TAiChatMessage.Create(ToolCall.Response, 'tool');
        NewMsg.ToolCallId := ToolCall.Id;
        NewMsg.FunctionName := ToolCall.Name;
        NewMsg.PreviousResponseId := FResponseId;
        for var LMF in ToolCall.MediaFiles do
          NewMsg.AddMediaFile(LMF);
        ToolCall.MediaFiles.OwnsObjects := False;
        NewMsg.Id := Self.Messages.Count + 1;
        Self.Messages.Add(NewMsg);
      end;

      // Re-run the chat with the tool results (Agentic Loop)
      Self.Run(Nil, ResMsg);
    end
    else
    begin
      // If there were no Function Calls, we check if there were Shell Calls or Patch Calls that added messages
      // to the history. If so, we must do recursion so that the AI sees the result.
      // (We check if the last message is of type 'tool')
      // The computer_call goes separately: it recurs even if there is text, because the
      // model comments each step while it continues driving the screen.
      if (Self.Messages.Count > 0) and (Self.Messages.Last.Role = 'tool') and
         ((FLastContent = '') or LComputerCallDone) then
      begin
        // Recursion for the AI to respond to the shell/patch result
        Self.Run(Nil, ResMsg);
      end
      else
      begin
        // Normal flow finished
        If cap_ExtractCode in ModelConfig.SessionCaps then
        Begin
          Var
          Code := TMarkdownCodeExtractor.Create;
          Try
            Var
            CodeFiles := Code.ExtractCodeFiles(FLastContent);
            For var CodeFile in CodeFiles do
            Begin
              Var
              St := TStringStream.Create(CodeFile.Code);
              Try
                St.Position := 0;
                var
                MF := TAiMediaFile.Create;
                MF.LoadFromStream('file.' + CodeFile.FileType, St);
                ResMsg.MediaFiles.Add(MF);
              Finally
                St.Free;
              End;
            End;
          Finally
            Code.Free;
          End;
        End;

        DoProcessResponse(GetLastMessage, ResMsg, FLastContent);

        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, jObj, 'assistant', FLastContent);
      end;
    end;

  finally
    ToolCalls.Free;
  end;
end;


// -----------------------------------------------------------------------------
// M?TODOS DE EJECUCI?N (HTTP)
// -----------------------------------------------------------------------------

function TAiOpenChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
var
  ABody, sUrl: String;
  Res: IHTTPResponse;
  St: TStringStream;
  FHeaders: TNetHeaders;
  jObj: TJSonObject;
begin
  FBusy := True;
  FAbort := False;
  FLastError := '';
  FResponseStatus := '';
  FLastContent := ''; // limpia el acumulado del turno anterior (streaming lee delta a delta)

  // 1. Ensure the USER message is in the history
  if FMessages.IndexOf(AskMsg) < 0 then
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  St := TStringStream.Create('', TEncoding.UTF8);
  if Url.EndsWith('/') then
    sUrl := Url + 'responses'
  else
    sUrl := Url + '/responses';

  try
    DoStateChange(acsConnecting, 'Sending request...');

    FHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    ABody := InitChatCompletions;
    St.WriteString(ABody);
    St.Position := 0;

    LogDebug('--Request-Body--');
    LogDebug('    ' + ABody);

    FResponse.Clear;
    Res := FClient.Post(sUrl, St, FResponse, FHeaders);

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

    if FClient.Asynchronous = False then
    begin
      // ... (Synchronous logic remains the same) ...
      if Res.StatusCode = 200 then
      begin

        LogDebug('--Response Sincrono--');
        LogDebug('    ' + Res.ContentAsString);

        jObj := TJSonObject(TJSonObject.ParseJSONValue(Res.ContentAsString));
        try
          FBusy := False;
          ParseChat(jObj, ResMsg);
          Result := FLastContent;
        finally
          FreeAndNil(jObj);
        end;
      end
      else
        Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;
  finally
    if FClient.Asynchronous = False then
      St.Free
    else
    begin
      if Assigned(FCurrentPostStream) then
        FreeAndNil(FCurrentPostStream);
      FCurrentPostStream := St;
    end;
  end;
end;

function TAiOpenChat.InternalRunImageVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  // Local variables to capture in the anonymous thread
  CaptureApiKey: string;
  CaptureUrl: string;
  CapturePrompt: string;
  CaptureModel: string;
  CaptureVideoParams: TStrings;
  CaptureImageFile: TAiMediaFile;
  CaptureResMsg: TAiChatMessage;
  LTask: ITask;
begin
  // 1. Initial Configuration (Main Thread)
  Result := 'Iniciando generaci?n de video...';

  CaptureApiKey := ApiKey;
  CaptureUrl := Url;
  if not CaptureUrl.EndsWith('/') then
    CaptureUrl := CaptureUrl + '/';

  CapturePrompt := AskMsg.Prompt;
  if CapturePrompt = '' then
    CapturePrompt := 'Generate a video';

  // Configure model
  CaptureModel := Model;
  if (Pos('sora', LowerCase(CaptureModel)) = 0) then
    CaptureModel := 'sora-2';

  // Parameters
  CaptureVideoParams := TStringList.Create;
  CaptureVideoParams.Assign(VideoParams.Params);

  // Reference image
  CaptureImageFile := nil;
  if AskMsg.MediaFiles.Count > 0 then
  begin
    var
    LFile := AskMsg.MediaFiles.GetMediaList([Tfc_Image], False);
    if Length(LFile) > 0 then
    begin
      CaptureImageFile := TAiMediaFile.Create;
      CaptureImageFile.Assign(LFile[0]);
    end;
  end;

  CaptureResMsg := ResMsg;

  // 2. Asynchronous Execution
  LTask := TTask.Run(
    procedure
    var
      AsyncClient: TNetHTTPClient;
      AsyncFormData: TMultipartFormData;
      AsyncResponse: IHTTPResponse;
      AsyncJson: TJSonObject;
      PollingUrl: string;
      VideoMedia: TAiMediaFile;
      VideoUrl: string;
      PollCount, ProgressPct: Integer;
      sPollCount: String;
      FinalStatus: string;
      ErrMessage: string;

      // CORRECTION: Explicit declaration as in your Sora unit
      AuthHeader: TNetHeaders;
      EndpointUrl: string;
    begin
      AsyncClient := TNetHTTPClient.Create(nil);
      AsyncFormData := TMultipartFormData.Create;
      try
        try
          // --- A. START JOB ---
          EndpointUrl := CaptureUrl + 'videos';

          // Explicit header construction
          AuthHeader := [TNetHeader.Create('Authorization', 'Bearer ' + CaptureApiKey)];

          AsyncFormData.AddField('prompt', CapturePrompt);
          AsyncFormData.AddField('model', CaptureModel);

          if CaptureVideoParams.Values['size'] <> '' then
            AsyncFormData.AddField('size', CaptureVideoParams.Values['size'])
          else
            AsyncFormData.AddField('size', '1280x720');

          if CaptureVideoParams.Values['seconds'] <> '' then
            AsyncFormData.AddField('seconds', CaptureVideoParams.Values['seconds'])
          else
            AsyncFormData.AddField('seconds', '4');

          if Assigned(CaptureImageFile) then
          begin
            CaptureImageFile.Content.Position := 0;
{$IF CompilerVersion < 36}
            AsyncFormData.AddStream('input_reference', CaptureImageFile.Content, CaptureImageFile.FileName, CaptureImageFile.MimeType);
{$ELSE}
            AsyncFormData.AddStream('input_reference', CaptureImageFile.Content, False, CaptureImageFile.FileName, CaptureImageFile.MimeType);
{$ENDIF}
          end;

          // CORRECTED CALL (Identical to your Sora unit)
          AsyncResponse := AsyncClient.Post(EndpointUrl, AsyncFormData, nil, AuthHeader);

          if AsyncResponse.StatusCode <> 200 then
            raise Exception.Create('Error starting Sora: ' + AsyncResponse.ContentAsString);

          AsyncJson := TJSonObject.ParseJSONValue(AsyncResponse.ContentAsString) as TJSonObject;
          try
            // Extra validation to avoid crash if id does not exist
            if (AsyncJson = nil) or (not AsyncJson.TryGetValue<String>('id', sPollCount { dummy var used for string id } )) then
            begin
              // We retry reading as string
              var
                LJobId: string;
              if (AsyncJson <> nil) and AsyncJson.TryGetValue<string>('id', LJobId) then
                PollingUrl := EndpointUrl + '/' + LJobId
              else
                raise Exception.Create('No video ID returned');
            end
            else
            begin
              // If it got here it is strange (PollCount is int), better use a direct string variable
              PollingUrl := EndpointUrl + '/' + AsyncJson.GetValue<string>('id');
            end;

            // Notify
            var
            LJobIdStr := AsyncJson.GetValue<string>('id');
            var
            LStatStr := AsyncJson.GetValue<string>('status');
            TThread.Queue(nil,
              procedure
              begin
                DoStateChange(acsToolExecuting, Format('Sora Job Started: %s (%s)', [LJobIdStr, LStatStr]));
              end);
          finally
            AsyncJson.Free;
          end;

          // --- B. POLLING LOOP ---
          PollCount := 0;

          while True do
          begin
            Inc(PollCount);
            Sleep(5000);

            // GET CALL (Also uses explicit AuthHeader)
            AsyncResponse := AsyncClient.Get(PollingUrl, nil, AuthHeader);

            if AsyncResponse.StatusCode <> 200 then
              Break;

            AsyncJson := TJSonObject.ParseJSONValue(AsyncResponse.ContentAsString) as TJSonObject;
            try
              if not Assigned(AsyncJson) then
                Continue;

              AsyncJson.TryGetValue<string>('status', FinalStatus);
              AsyncJson.TryGetValue<Integer>('progress', ProgressPct);

              TThread.Queue(nil,
                procedure
                begin
                  if Assigned(OnProgressEvent) then
                    OnProgressEvent(Self, FinalStatus, ProgressPct, 100);
                end);

              if FinalStatus = 'completed' then
                Break;
              if FinalStatus = 'failed' then
              begin
                ErrMessage := 'Video generation failed';
                var
                  JErr: TJSonObject;
                if AsyncJson.TryGetValue<TJSonObject>('error', JErr) then
                  ErrMessage := ErrMessage + ': ' + JErr.GetValue<string>('message');
                raise Exception.Create(ErrMessage);
              end;
            finally
              AsyncJson.Free;
            end;

            if PollCount > 120 then
              raise Exception.Create('Timeout generating video');
          end;

          // --- C. DOWNLOAD VIDEO ---
          TThread.Queue(nil,
            procedure
            begin
              DoStateChange(acsToolExecuting, 'Downloading video...');
            end);

          VideoUrl := PollingUrl + '/content';
          VideoMedia := TAiMediaFile.Create;
          var
          VideoStream := TMemoryStream.Create;
          try
            // GET DOWNLOAD CALL (Uses explicit AuthHeader)
            AsyncResponse := AsyncClient.Get(VideoUrl, VideoStream, AuthHeader);

            if AsyncResponse.StatusCode = 200 then
            begin
              VideoStream.Position := 0;
              VideoMedia.LoadFromStream('sora_video.mp4', VideoStream);
              // We use the job ID as the cloud name, extracted from the URL
              var
                Parts: TArray<string> := PollingUrl.Split(['/']);
              if Length(Parts) > 0 then
                VideoMedia.CloudName := Parts[High(Parts)];

              VideoMedia.CloudState := 'completed';

              TThread.Queue(nil,
                procedure
                begin
                  CaptureResMsg.MediaFiles.Add(VideoMedia);
                  CaptureResMsg.Prompt := Format('Video generated successfully.', []);

                  DoStateChange(acsFinished, 'Video Ready');
                  if Assigned(FOnReceiveDataEnd) then
                    FOnReceiveDataEnd(Self, CaptureResMsg, nil, 'assistant', CaptureResMsg.Prompt);
                end);
            end
            else
            begin
              VideoMedia.Free;
              raise Exception.Create('Error downloading content');
            end;
          except
            VideoStream.Free;
            raise;
          end;

        except
          on E: Exception do
          begin
            TThread.Queue(nil,
              procedure
              begin
                DoError('Sora Error: ' + E.Message, E);
              end);
          end;
        end;
      finally
        AsyncFormData.Free;
        AsyncClient.Free;
        CaptureVideoParams.Free;
        if Assigned(CaptureImageFile) then
          CaptureImageFile.Free;
      end;
    end);
end;

procedure TAiOpenChat.DoCallFunction(ToolCall: TAiToolsFunction);
begin
  if not Assigned(AiFunctions) then
    Exit;

  // Logic delegated to AiFunctions (supports MCP and locals)
  if not AiFunctions.DoCallFunction(ToolCall) then
  begin
    // Fallback for old direct event logic
    if Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall);
  end;
end;

function TAiOpenChat.DownLoadFile(aMediaFile: TAiMediaFile): String;
var
  LUrl: string;
  LResponse: IHTTPResponse;
  LStream: TMemoryStream;
  Headers: TNetHeaders;
  TmpClient: TNetHTTPClient;
begin
  Result := '';

  // Validate IDs
  if (aMediaFile.IdFile = '') or (aMediaFile.CloudState = '') then
    Exit;

  // Build URL
  LUrl := Format('%scontainers/%s/files/%s/content', [Url, aMediaFile.CloudState, aMediaFile.IdFile]);

  LStream := TMemoryStream.Create;
  TmpClient := TNetHTTPClient.Create(nil); // <--- We create an isolated instance
  try
    // We configure the temporary client same as the main one
    // (If you use specific SSL properties in FClient, copy them here as well)
    TmpClient.ResponseTimeout := 60000;

    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    // We use TmpClient instead of FClient
    LResponse := TmpClient.Get(LUrl, LStream, Headers);

    if LResponse.StatusCode = 200 then
    begin
      if LStream.Size > 0 then
      begin
        LStream.Position := 0;
        aMediaFile.LoadFromStream(aMediaFile.FileName, LStream);
        Result := aMediaFile.FileName;
      end
      else
        raise Exception.Create('The server returned an empty stream.');
    end
    else
      raise Exception.CreateFmt('Error downloading file (%d): %s', [LResponse.StatusCode, LResponse.StatusText]);
  finally
    TmpClient.Free;
    LStream.Free;
  end;
end;

// -----------------------------------------------------------------------------
// LEGACY METHODS / SEPARATE ENDPOINTS (Audio)
// -----------------------------------------------------------------------------
function TAiOpenChat.InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl, LModel, LVoice, LResponseFormat: string;
  LBodyStream: TStringStream;
  LResponseStream: TMemoryStream;
  LHeaders: TNetHeaders; // <--- Variable ya declarada, ahora la usaremos
  LResponse: IHTTPResponse;
  LJsonObject: TJSonObject;
  LErrorResponse: string;
  LNewAudioFile: TAiMediaFile;
  OldAsc: Boolean;
begin
  Result := ''; // The Run function returns the text, which in this case is empty.
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  // 1. Add the user message to the history to maintain consistency
  if FMessages.IndexOf(AskMsg) < 0 then // We only add it if it is not already in the list
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, Nil, AskMsg.Role, AskMsg.Prompt);
  end;

  // 2. Prepare parameters for the TTS API
  LUrl := Url + 'audio/speech';
  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  // 'tts-1'; // Or you could have a specific property for the TTS model
  LVoice := TtsParams.Voice; // We use the component property
  LResponseFormat := TtsParams.VoiceFormat; // We use the component property

  // 3. Build and execute the request
  LJsonObject := TJSonObject.Create;
  LBodyStream := nil;
  LResponseStream := TMemoryStream.Create;
  OldAsc := FClient.Asynchronous;

  try
    FClient.Asynchronous := False;

    LJsonObject.AddPair('model', LModel);
    LJsonObject.AddPair('input', AskMsg.Prompt);
    LJsonObject.AddPair('voice', LVoice);
    LJsonObject.AddPair('response_format', LResponseFormat);

    LBodyStream := TStringStream.Create(LJsonObject.ToJson, TEncoding.UTF8);

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    LBodyStream.Position := 0;
{$IFDEF APIDEBUG}
    LBodyStream.SaveToFile('c:\temp\peticionAudio.json.txt');
    LBodyStream.Position := 0;
{$ENDIF}
    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

    // 4. Process the response
    if LResponse.StatusCode = 200 then
    begin
      LNewAudioFile := TAiMediaFile.Create;
      try
        LResponseStream.Position := 0;
        LNewAudioFile.LoadFromStream('generated_audio.' + LResponseFormat, LResponseStream);

        ResMsg.MediaFiles.Add(LNewAudioFile);

        DoStateChange(acsFinished, 'Done'); // <--- FINISHED STATE
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, nil, 'model', '');
      except
        LNewAudioFile.Free;
        raise;
      end;
    end
    else
    begin
      LResponseStream.Position := 0;
      LErrorResponse := TStreamReader.Create(LResponseStream).ReadToEnd;
      FLastError := Format('Error generating audio: %d, %s', [LResponse.StatusCode, LErrorResponse]);
      DoError(FLastError, nil);
    end;
  finally

    FClient.Asynchronous := OldAsc;

    LJsonObject.Free;
    LBodyStream.Free;
    LResponseStream.Free;
  end;

  FBusy := False;

end;

function TAiOpenChat.InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LUrl, LModel, LQuality, LSize, LValue: string;
  LBodyJson: TJSonObject;
  LBodyStream: TStringStream;
  LResponseStream: TStringStream;
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LResponseJson, LImageObject: TJSonObject;
  LDataArray: TJSonArray;
  LBase64Data, LRevisedPrompt, LErrorMsg: string;
  LNewImageFile: TAiMediaFile;
  OldAsync: Boolean;
begin
  Result := '';
  FBusy := True;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := AskMsg.Prompt;

  if FMessages.IndexOf(AskMsg) < 0 then
  begin
    AskMsg.Id := FMessages.Count + 1;
    FMessages.Add(AskMsg);
    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, AskMsg, nil, AskMsg.Role, AskMsg.Prompt);
  end;

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LModel = '' then
    LModel := 'gpt-image-1';

  LUrl := Url + 'images/generations';

  // quality from ImageParams.Params or default according to model
  LQuality := ImageParams.Params.Values['quality'];
  if LQuality = '' then
  begin
    case ImageParams.Resolution of
      mrLow:  LQuality := 'low';
      mrHigh: LQuality := 'high';
    else
      // mrDefault / mrMedium
      if LModel = 'dall-e-3' then LQuality := 'standard'
      else                        LQuality := 'medium';
    end;
  end;

  // size from ImageParams.Params or default according to model
  LSize := ImageParams.Params.Values['size'];
  if LSize = '' then
  begin
    if LModel = 'dall-e-2' then LSize := '1024x1024'
    else                        LSize := '1024x1024';
  end;

  LBodyJson := TJSonObject.Create;
  LBodyStream := nil;
  LResponseStream := nil;
  LResponseJson := nil;
  OldAsync := FClient.Asynchronous;

  try
    FClient.Asynchronous := False;

    LBodyJson.AddPair('model', LModel);
    LBodyJson.AddPair('prompt', AskMsg.Prompt);
    LBodyJson.AddPair('n', TJSONNumber.Create(Max(1, N)));

    // 'response_format' and 'style' were REMOVED from the OpenAI API (2026),
    // also for dall-e-2/3: sending them produces 400 "Unknown parameter"
    // (verified against api.openai.com Jul-2026). The API decides the format:
    // the gpt-image family returns b64_json; the parsing below also covers
    // additionally 'url' for compatibility with OpenAI-compatible endpoints.

    LBodyJson.AddPair('size', LSize);

    // dall-e-2 does not accept quality
    if (LModel <> 'dall-e-2') then
      LBodyJson.AddPair('quality', LQuality);

    // Passthrough of the parameters exclusive to the gpt-image family
    // (background, output_format, output_compression, moderation). It serves
    // especially for gpt-image-2.5-flare/sunburst, which do return a
    // transparent background with a real alpha channel -> requires output_format png/webp.
    if LModel.StartsWith('gpt-image') or LModel.StartsWith('chatgpt-image') then
    begin
      LValue := ImageParams.Params.Values['background'];
      if LValue <> '' then
        LBodyJson.AddPair('background', LValue);

      LValue := ImageParams.Params.Values['output_format'];
      if LValue <> '' then
        LBodyJson.AddPair('output_format', LValue);

      LValue := ImageParams.Params.Values['output_compression'];
      if LValue <> '' then
        LBodyJson.AddPair('output_compression', TJSONNumber.Create(StrToIntDef(LValue, 100)));

      LValue := ImageParams.Params.Values['moderation'];
      if LValue <> '' then
        LBodyJson.AddPair('moderation', LValue);
    end;

    if not User.IsEmpty then
      LBodyJson.AddPair('user', User);

    LBodyStream := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
    LResponseStream := TStringStream.Create('', TEncoding.UTF8);

    LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

{$IFDEF APIDEBUG}
    LBodyStream.SaveToFile('c:\temp\openai_image_request.json');
    LBodyStream.Position := 0;
{$ENDIF}

    LResponse := FClient.Post(LUrl, LBodyStream, LResponseStream, LHeaders);

    if LResponse.StatusCode = 200 then
    begin
      LResponseJson := TJSonObject.ParseJSONValue(LResponseStream.DataString) as TJSonObject;
      if LResponseJson = nil then
        raise Exception.Create('Error parsing image generation response.');

      if LResponseJson.TryGetValue<TJSonArray>('data', LDataArray) and (LDataArray.Count > 0) then
      begin
        for var LItem in LDataArray do
        begin
          if not (LItem is TJSonObject) then Continue;
          LImageObject := LItem as TJSonObject;

          LRevisedPrompt := '';
          LImageObject.TryGetValue<string>('revised_prompt', LRevisedPrompt);
          FLastContent := IfThen(LRevisedPrompt <> '', LRevisedPrompt, AskMsg.Prompt);

          LBase64Data := '';
          LImageObject.TryGetValue<string>('b64_json', LBase64Data);
          if LBase64Data <> '' then
          begin
            LNewImageFile := TAiMediaFile.Create;
            try
              LNewImageFile.LoadFromBase64('generated_image.png', LBase64Data);
              LNewImageFile.Transcription := LRevisedPrompt;
              ResMsg.MediaFiles.Add(LNewImageFile);
            except
              LNewImageFile.Free;
              raise;
            end;
          end
          else
          begin
            // Without response_format the API may respond with 'url' (endpoints
            // OpenAI-compatible / dall-e legacy): download the image
            var LImgUrl := '';
            LImageObject.TryGetValue<string>('url', LImgUrl);
            if LImgUrl <> '' then
            begin
              LNewImageFile := TAiMediaFile.Create;
              try
                LNewImageFile.LoadFromUrl(LImgUrl);
                LNewImageFile.Transcription := LRevisedPrompt;
                ResMsg.MediaFiles.Add(LNewImageFile);
              except
                LNewImageFile.Free;
                raise;
              end;
            end;
          end;
        end;

        ResMsg.Prompt := FLastContent;
        DoStateChange(acsFinished, 'Done');
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, nil, 'model', '');
      end
      else
      begin
        FLastError := LModel + ': OK response but no image data.';
        DoError(FLastError, nil);
      end;
    end
    else
    begin
      LErrorMsg := LResponseStream.DataString;
      FLastError := Format('Error %d in image generation: %s', [LResponse.StatusCode, LErrorMsg]);
      DoError(FLastError, nil);
    end;
  finally
    FClient.Asynchronous := OldAsync;
    LBodyJson.Free;
    LBodyStream.Free;
    LResponseStream.Free;
    LResponseJson.Free;
    FBusy := False;
  end;
end;

function TAiOpenChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  Body: TMultipartFormData;
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  sUrl: String;
  Res: IHTTPResponse;
  LResponseStream: TMemoryStream;
  LTempStream: TMemoryStream;
  LResponseObj: TJSonObject;
  Granularities: TStringList; // To process the granularities
  I: Integer;
  LModel: String;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('An audio file with content is required for transcription.');

  sUrl := Url + 'audio/transcriptions';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  Client := TNetHTTPClient.Create(Nil);
{$IF CompilerVersion >= 34}
  Client.SynchronizeEvents := False;
{$ENDIF}
  LResponseStream := TMemoryStream.Create;
  Body := TMultipartFormData.Create;
  Granularities := TStringList.Create;

  LTempStream := TMemoryStream.Create;
  try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];

    // Create a temporary stream to pass it to the multipart form
    aMediaFile.Content.Position := 0;
    LTempStream.LoadFromStream(aMediaFile.Content);
    LTempStream.Position := 0;

    // --- 1. BUILDING THE MULTIPART BODY WITH GENERIC PARAMETERS ---
{$IF CompilerVersion >= 36}
    Body.AddStream('file', LTempStream, False, aMediaFile.FileName, aMediaFile.MimeType);
{$ELSE}
    Body.AddStream('file', LTempStream, aMediaFile.FileName, aMediaFile.MimeType);
{$ENDIF}
    Body.AddField('model', LModel); // Safe default

    if not AskMsg.Prompt.IsEmpty then
      Body.AddField('prompt', AskMsg.Prompt);

    // Response format (generic, as string)
    if not TranscriptionParams.ResponseFormat.IsEmpty then
      Body.AddField('response_format', TranscriptionParams.ResponseFormat)
    else
      Body.AddField('response_format', 'json'); // Default to JSON if not specified

    // Optional parameters
    if not TranscriptionParams.Language.IsEmpty then
      Body.AddField('language', TranscriptionParams.Language);

    // We use the Temperature property existing in the component
    if Self.Temperature > 0 then
      Body.AddField('temperature', FormatFloat('0.0', Self.Temperature));

    // Timestamps Granularities (process the string)
    if not TranscriptionParams.TimestampGranularities.IsEmpty then
    begin
      // We split the string by commas
      Granularities.CommaText := TranscriptionParams.TimestampGranularities;
      for I := 0 to Granularities.Count - 1 do
      begin
        // We add each granularity as a separate field with '[]'
        Body.AddField('timestamp_granularities[]', Trim(Granularities[I]));
      end;
    end;

    // TODO: Async transcription not implemented. Synchronous mode only.

    // --- 2. EXECUTION OF THE POST REQUEST ---
    begin

      Res := Client.Post(sUrl, Body, LResponseStream, Headers);

      if Res.StatusCode = 200 then
      begin

        LResponseObj := TJSonObject.ParseJSONValue(Res.ContentAsString) as TJSonObject;

        If Not Assigned(LResponseObj) then
        Begin
          LResponseObj := TJSonObject.Create(TJSonPair.Create('text', Res.ContentAsString));
        End;

        try
          // Here you call the transcript parsing procedure
          ParseJsonTranscript(LResponseObj, ResMsg, aMediaFile);
        finally
          LResponseObj.Free;
        end;

        Result := ResMsg.Prompt;
      end
      else
      begin
        Raise Exception.CreateFmt('Error in transcription: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end;
    end;

  finally
    Body.Free;
    Client.Free;
    LResponseStream.Free;
    LTempStream.Free;
  end;

end;

procedure TAiOpenChat.NewChat;
begin
  // TODO: DeleteAllUploadedFiles disabled — OpenAI does not persist files between sessions
  FResponseId := ''; // Starts a new conversation
  FLastEffortSent := tlDefault; // effort is not inherited from the previous conversation
  FStreamTextMsg := nil;       // history is cleared in inherited
  inherited;
end;

// LogDebug('--OnInternalReceiveData--');
// LogDebug(FResponse.DataString);

procedure TAiOpenChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
var
  Line, DataStr, EventType: string;
  JsonEvent, JItem, JResp, JUsage, JInputDetails, JUsageDetails: TJSonObject;
  P, OutputIndex: Integer;
  DeltaVal, ItemId, CallId, FuncName: string;
  BufferTool: TJSonObject;
  JContentArr, JAnnotations: TJSonArray;
  JContentPart, JAnno: TJSonObject;
  WebItem: TAiWebSearchItem;
  CurrentMsg, NewStreamMsg: TAiChatMessage;
  TokenCount: Int64;
  BytesBuffer: TBytes;
  SS: TStringStream;
begin
  if not FClient.Asynchronous then
    Exit;

  LogDebug('--OnInternalReceiveData--');
  // ISSUE #124: the log must not abort the stream if the chunk ends with an
  // incomplete UTF-8 character (see protected accumulation below).
  try
    LogDebug(FResponse.DataString);
  except
    on EEncodingError do
      LogDebug('[partial UTF-8 chunk - log omitted]');
  end;

  AAbort := FAbort;
  if FAbort then
  begin
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallBuffer.Clear;
    DoStateChange(acsAborted, 'Aborted');
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, nil, nil, 'system', 'abort');
    Exit;
  end;

  // ---------------------------------------------------------------------------
  // 1. Robust Accumulation (UTF-8)
  // ---------------------------------------------------------------------------
  // ISSUE #124: decode BEFORE clearing. If the chunk ends with a character
  // incomplete UTF-8, GetString/DataString throw EEncodingError: it exits without
  // Clear, the bytes remain in FResponse and the next chunk completes the character.
  try
    if FResponse is TStringStream then
    begin
      SS := TStringStream(FResponse);
      if SS.Size > 0 then
      begin
        SetLength(BytesBuffer, SS.Size);
        SS.Position := 0;
        SS.Read(BytesBuffer, 0, SS.Size);
        FTmpResponseText := FTmpResponseText + TEncoding.UTF8.GetString(BytesBuffer);
      end;
    end
    else
      FTmpResponseText := FTmpResponseText + FResponse.DataString;
  except
    on EEncodingError do
      Exit;
  end;

  FResponse.Clear;

  // ---------------------------------------------------------------------------
  // 2. Process complete lines (SSE Protocol)
  // ---------------------------------------------------------------------------
  while Pos(#10, FTmpResponseText) > 0 do
  begin
    P := Pos(#10, FTmpResponseText);
    Line := Copy(FTmpResponseText, 1, P - 1);
    Delete(FTmpResponseText, 1, P);

    // Remove trailing CR (#13) if any
    if (Line <> '') and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);

    if (Line = '') or Line.StartsWith('event:') or Line.StartsWith(':') then
      Continue;

    if Line.StartsWith('data:') then
    begin
      DataStr := Copy(Line, 6, Length(Line));
      if (DataStr <> '') and (DataStr[1] = ' ') then
        Delete(DataStr, 1, 1);

      if (DataStr = '[DONE]') then
        Continue;

      JsonEvent := TJSonObject.ParseJSONValue(DataStr) as TJSonObject;
      if not Assigned(JsonEvent) then
        Continue;

      try
        if not JsonEvent.TryGetValue<string>('type', EventType) then
          Continue;

        // ---------------------------------------------------------------------
        // A) INITIAL METADATA AND MESSAGE CREATION
        // ---------------------------------------------------------------------
        if EventType = 'response.created' then
        begin
          if JsonEvent.TryGetValue<TJSonObject>('response', JResp) then
            if JResp.TryGetValue<string>('id', ItemId) then
              FResponseId := ItemId;

          // --- IMPORTANT FIX: Automatic creation of the response message ---
          // We verify if the last message is from the user (with image) or is already complete.
          // If so, we create a new one for the Assistant to not overwrite the input.
          var
          LastM := GetLastMessage;

          if (LastM = nil) or (LastM.Role <> 'assistant') then // or (LastM.Status = 'completed') then
          begin
            NewStreamMsg := TAiChatMessage.Create('', 'assistant');
            NewStreamMsg.Id := FMessages.Count + 1;
            NewStreamMsg.PreviousResponseId := FResponseId;
            FMessages.Add(NewStreamMsg);
            // Now GetLastMessage will point to this new clean message
            FStreamTextMsg := NewStreamMsg;
          end
          else
            FStreamTextMsg := LastM;
          // ------------------------------------------------------------------

          FRecursionNeeded := False;
          DoStateChange(acsCreated, 'Response ID: ' + FResponseId);
        end

        // ---------------------------------------------------------------------
        // B) ASSISTANT TEXT (STREAMING)
        // ---------------------------------------------------------------------
        else if EventType = 'response.output_text.delta' then
        begin
          if JsonEvent.TryGetValue<string>('delta', DeltaVal) then
          begin
            // Normalize line breaks for UI (LF -> CRLF on Windows)
            DeltaVal := AdjustLineBreaks(DeltaVal, tlbsCRLF);

            FLastContent := FLastContent + DeltaVal;
            if Assigned(FOnReceiveDataEvent) then
              FOnReceiveDataEvent(Self, nil, JsonEvent, 'assistant', DeltaVal);
          end;
        end

        // ---------------------------------------------------------------------
        // C) TOOLS & THINKING (DETECTION)
        // ---------------------------------------------------------------------
        else if EventType = 'response.output_item.added' then
        begin
          if JsonEvent.TryGetValue<Integer>('output_index', OutputIndex) and JsonEvent.TryGetValue<TJSonObject>('item', JItem) then
          begin
            var
            ItemType := JItem.GetValue<string>('type');

            if ItemType = 'function_call' then
            begin
              DoStateChange(acsToolCalling, 'Detected tool call...');
              BufferTool := TJSonObject.Create;
              if JItem.TryGetValue<string>('id', ItemId) then
                BufferTool.AddPair('id', ItemId);
              if JItem.TryGetValue<string>('call_id', CallId) then
                BufferTool.AddPair('call_id', CallId);
              if JItem.TryGetValue<string>('name', FuncName) then
              begin
                BufferTool.AddPair('name', FuncName);
                BufferTool.AddPair('arguments', '');
              end;
              // The async flag travels in the item, not in the deltas: it must be
              // saved now, because it is read from the buffer when the item closes.
              if JItem.GetValue<Boolean>('async', False) then
                BufferTool.AddPair('async', TJSONBool.Create(True));
              FTmpToolCallBuffer.AddOrSetValue(OutputIndex, BufferTool);
            end
            else if ItemType = 'reasoning' then
              DoStateChange(acsReasoning, 'Thinking...');
          end;
        end

        // ---------------------------------------------------------------------
        // D) TOOL ARGUMENTS (ACCUMULATION)
        // ---------------------------------------------------------------------
        else if EventType = 'response.function_call_arguments.delta' then
        begin
          if JsonEvent.TryGetValue<Integer>('output_index', OutputIndex) and JsonEvent.TryGetValue<string>('delta', DeltaVal) then
          begin
            if FTmpToolCallBuffer.TryGetValue(OutputIndex, BufferTool) then
            begin
              var
              OldArgs := BufferTool.GetValue<string>('arguments');
              BufferTool.RemovePair('arguments');
              BufferTool.AddPair('arguments', OldArgs + DeltaVal);
            end;
          end;
        end

        // ---------------------------------------------------------------------
        // E) ITEM DONE (TOOL EXECUTION / IMAGES / CITATIONS)
        // ---------------------------------------------------------------------
        else if EventType = 'response.output_item.done' then
        begin
          if JsonEvent.TryGetValue<Integer>('output_index', OutputIndex) and JsonEvent.TryGetValue<TJSonObject>('item', JItem) then
          begin
            var
            ItemType := JItem.GetValue<string>('type');

            // 1. Function Call
            if (ItemType = 'function_call') and FTmpToolCallBuffer.TryGetValue(OutputIndex, BufferTool) then
            begin
              var
              ToolName := BufferTool.GetValue<string>('name');
              DoStateChange(acsToolExecuting, 'Executing: ' + ToolName);
              var
              ToolCall := TAiToolsFunction.Create;
              ToolCall.Id := BufferTool.GetValue<string>('call_id');
              ToolCall.Name := ToolName;
              ToolCall.Arguments := BufferTool.GetValue<string>('arguments');
              ToolCall.IsAsync := BufferTool.GetValue<Boolean>('async', False)
                                  or JItem.GetValue<Boolean>('async', False);
              FTmpToolCallBuffer.Remove(OutputIndex); // doOwnsValues frees BufferTool automatically

              // Parity with the synchronous path (ParseChat): pass ResMsg/AskMsg to the
              // handler. ResMsg = assistant message under construction (created in
              // response.created); AskMsg = last user message. Without this
              // ToolCall.ResMsg arrived nil in streaming mode.
              ToolCall.ResMsg := GetLastMessage;
              for var LIdx := FMessages.Count - 1 downto 0 do
                if FMessages[LIdx].Role = 'user' then
                begin
                  ToolCall.AskMsg := FMessages[LIdx];
                  Break;
                end;

              DoCallFunction(ToolCall);

              var
              NewMsg := TAiChatMessage.Create(ToolCall.Response, 'tool');
              NewMsg.ToolCallId := ToolCall.Id;
              NewMsg.FunctionName := ToolCall.Name;
              NewMsg.PreviousResponseId := FResponseId;
              for var LMF in ToolCall.MediaFiles do
                NewMsg.AddMediaFile(LMF);
              ToolCall.MediaFiles.OwnsObjects := False;
              NewMsg.Id := FMessages.Count + 1;
              FMessages.Add(NewMsg);
              FRecursionNeeded := True;
              ToolCall.Free;
            end

            // 2. Shell Call
            else if (ItemType = 'shell_call') then
            begin
              if JItem.TryGetValue<String>('call_id', CallId) then
              begin
                var
                  JAction: TJSonObject;
                if JItem.TryGetValue<TJSonObject>('action', JAction) then
                begin
                  if Assigned(ChatTools.ShellTool) then
                  begin
                    var
                    HistoryItem := TJSonObject.Create;
                    try
                      HistoryItem.AddPair('type', 'shell_call');
                      HistoryItem.AddPair('call_id', CallId);
                      HistoryItem.AddPair('action', TJSonObject.ParseJSONValue(JAction.ToString) as TJSONValue);
                      var
                      CallMsg := TAiChatMessage.Create(HistoryItem.ToString, 'assistant');
                      CallMsg.ToolCallId := CallId;
                      CallMsg.PreviousResponseId := FResponseId;
                      CallMsg.Id := FMessages.Count + 1;
                      FMessages.Add(CallMsg);
                    finally
                      HistoryItem.Free;
                    end;

                    var
                    ShellOutput := ChatTools.ShellTool.Execute(CallId, JAction);
                    var
                    ResultMsg := TAiChatMessage.Create(ShellOutput, 'tool');
                    ResultMsg.ToolCallId := CallId;
                    ResultMsg.PreviousResponseId := FResponseId;
                    ResultMsg.Id := FMessages.Count + 1;
                    FMessages.Add(ResultMsg);
                    FRecursionNeeded := True;
                  end;
                end;
              end;
            end

            // 2b. Computer Call (screen control)
            // Same contract as in the synchronous path: a computer_call brings an
            // ARRAY 'actions' that is executed in order, and responds with a SINGLE
            // computer_call_output with the final screenshot.
            else if (ItemType = 'computer_call') then
            begin
              if JItem.TryGetValue<String>('call_id', CallId) then
              begin
                // History: the raw call as an assistant message
                var
                CUCallMsg := TAiChatMessage.Create(JItem.ToString, 'assistant');
                CUCallMsg.ToolCallId := CallId;
                CUCallMsg.PreviousResponseId := FResponseId;
                CUCallMsg.Id := FMessages.Count + 1;
                FMessages.Add(CUCallMsg);

                var
                  LShotS: TAiMediaFile;
                var
                  LDelegatedS: Boolean;
                LShotS := nil;
                // Delegated batch: not executed in this process (see the detail
                // of the contract in the synchronous path).
                LDelegatedS := False;
                try
                  var
                    JActionsS: TJSonArray;
                  if not Assigned(ChatTools.ComputerUseTool) then
                  begin
                    // See the synchronous path: without the component there is no executor or
                    // capture, and no interception point either.
                    LDelegatedS := True;
                    FLastError := 'computer_call ' + CallId +
                      ': cap_ComputerUse is active but ChatTools.ComputerUseTool '
                      + 'is not assigned. The turn is cut without responding to the model.';
                    DoError(FLastError, nil);
                  end
                  else if not JItem.TryGetValue<TJSonArray>('actions', JActionsS) then
                  begin
                    LDelegatedS := True;
                    FLastError := 'computer_call ' + CallId +
                      ': el item no trae el array "actions" esperado.';
                    DoError(FLastError, nil);
                  end
                  else
                  begin
                    for var Ai := 0 to JActionsS.Count - 1 do
                    begin
                      var
                      JActS := JActionsS.Items[Ai] as TJSonObject;
                      var
                      LCUS := TAiToolsFunction.Create;
                      try
                        LCUS.Id := CallId;
                        LCUS.Name := JActS.GetValue<string>('type', '');
                        LCUS.Arguments := JActS.ToJSON;
                        ChatTools.ComputerUseTool.TranslateOpenAIToolCall(LCUS);

                        if Assigned(FOnCallToolFunction) then
                          FOnCallToolFunction(Self, LCUS);

                        // If the interceptor filled Response, the ENTIRE batch is
                        // considered delegated: a computer_call has a single
                        // output and cannot be split between two executors.
                        if LCUS.Response <> '' then
                        begin
                          LDelegatedS := True;
                          Break;
                        end;

                        // Only the photo of the LAST action of the batch is kept.
                        FreeAndNil(LShotS);
                        ChatTools.ComputerUseTool.ProcessToolCall(LCUS, LShotS);
                      finally
                        LCUS.Free;
                      end;
                    end;

                    // The output requires an image (one of image_url or file_id): if the
                    // batch left none, a capture is forced.
                    if (not LDelegatedS) and (not Assigned(LShotS)) then
                    begin
                      var
                      LSnapS := TAiToolsFunction.Create;
                      try
                        LSnapS.Id := CallId;
                        LSnapS.Name := 'screenshot';
                        LSnapS.Arguments := '{}';
                        ChatTools.ComputerUseTool.ProcessToolCall(LSnapS, LShotS);
                      finally
                        LSnapS.Free;
                      end;
                    end;
                  end;

                  // If the batch was delegated, no output is emitted and no
                  // recursion is asked: there is nothing to return to the model yet.
                  if (not LDelegatedS) and (not Assigned(LShotS)) then
                  begin
                    // See the synchronous path: a computer_call_output without
                    // image is a guaranteed 400, better to cut the turn.
                    FLastError := 'computer_call ' + CallId +
                      ': no se pudo capturar la pantalla. Revise OnExecuteAction '
                      + 'y OnRequestScreenshot del TAiComputerUseTool.';
                    DoError(FLastError, nil);
                  end
                  else if not LDelegatedS then
                  begin
                    var
                    JCUOutS := TJSonObject.Create;
                    try
                      JCUOutS.AddPair('type', 'computer_call_output');
                      JCUOutS.AddPair('call_id', CallId);
                      var
                      JShotS := TJSonObject.Create;
                      JShotS.AddPair('type', 'computer_screenshot');
                      if Assigned(LShotS) then
                        JShotS.AddPair('image_url', 'data:' + LShotS.MimeType + ';base64,' + LShotS.Base64);
                      JCUOutS.AddPair('output', JShotS);

                      var
                      CUResMsg := TAiChatMessage.Create(JCUOutS.ToString, 'tool');
                      CUResMsg.ToolCallId := CallId;
                      CUResMsg.PreviousResponseId := FResponseId;
                      CUResMsg.Id := FMessages.Count + 1;
                      FMessages.Add(CUResMsg);
                    finally
                      JCUOutS.Free;
                    end;

                    FRecursionNeeded := True;
                  end;
                finally
                  FreeAndNil(LShotS);
                end;
              end;
            end

            // 3. Image Generation
            else if (ItemType = 'image_generation_call') then
            begin
              var
              ImgBase64 := '';
              if not JItem.TryGetValue<string>('result', ImgBase64) then
                JItem.TryGetValue<string>('image', ImgBase64);
              if ImgBase64 <> '' then
              begin
                var
                ImgId := '';
                JItem.TryGetValue<string>('id', ImgId);
                if ImgId = '' then
                  ImgId := 'gen_' + IntToStr(TThread.GetTickCount);

                var
                ImgPrompt := '';
                JItem.TryGetValue<string>('revised_prompt', ImgPrompt);

                var
                GenImg := TAiMediaFile.Create;
                GenImg.LoadFromBase64(ImgId + '.png', ImgBase64);
                GenImg.Transcription := ImgPrompt;
                GenImg.IdFile := ImgId;

                var
                ImgMsg := TAiChatMessage.Create('', 'assistant');
                ImgMsg.Prompt := '[Generated Image] ' + ImgPrompt;
                ImgMsg.MediaFiles.Add(GenImg);
                ImgMsg.Id := FMessages.Count + 1;
                ImgMsg.PreviousResponseId := FResponseId;
                FMessages.Add(ImgMsg);

                if Assigned(FOnReceiveDataEnd) then
                  FOnReceiveDataEnd(Self, ImgMsg, JItem, 'assistant', ImgMsg.Prompt);
              end;
            end

            // 4. Message (Web Citations/Files)
            else if (ItemType = 'message') then
            begin
              CurrentMsg := GetLastMessage;
              if Assigned(CurrentMsg) and JItem.TryGetValue<TJSonArray>('content', JContentArr) then
              begin
                for var C := 0 to JContentArr.Count - 1 do
                begin
                  JContentPart := JContentArr.Items[C] as TJSonObject;
                  if JContentPart.TryGetValue<TJSonArray>('annotations', JAnnotations) then
                  begin
                    for var A := 0 to JAnnotations.Count - 1 do
                    begin
                      JAnno := JAnnotations.Items[A] as TJSonObject;
                      var
                      AnnoType := JAnno.GetValue<string>('type');

                      if AnnoType = 'url_citation' then
                      begin
                        if not Assigned(CurrentMsg.WebSearchResponse) then
                        begin
                          CurrentMsg.WebSearchResponse := TAiWebSearch.Create;
                          CurrentMsg.WebSearchResponse.&type := 'web_search_results';
                        end;
                        WebItem := TAiWebSearchItem.Create;
                        WebItem.&type := 'url_citation';
                        JAnno.TryGetValue<string>('url', WebItem.Url);
                        JAnno.TryGetValue<string>('title', WebItem.title);
                        CurrentMsg.WebSearchResponse.annotations.Add(WebItem);
                      end
                      else if AnnoType = 'container_file_citation' then
                      begin
                        var
                        GenFile := TAiMediaFile.Create;
                        if JAnno.TryGetValue<string>('file_id', ItemId) then
                          GenFile.IdFile := ItemId;
                        if JAnno.TryGetValue<string>('filename', FuncName) then
                          GenFile.FileName := FuncName;
                        if JAnno.TryGetValue<string>('container_id', CallId) then
                          GenFile.CloudState := CallId;
                        try
                          DownLoadFile(GenFile);
                        except
                          on E: Exception do
                            LogDebug('Error downloading container file (stream): ' + E.Message);
                        end;
                        CurrentMsg.MediaFiles.Add(GenFile);
                      end;
                    end;
                  end;
                end;
              end;
            end;
          end;
        end

        // ---------------------------------------------------------------------
        // F) FINALIZATION (COST METADATA, EXTRACTION AND RECURSION)
        // ---------------------------------------------------------------------
        // response.incomplete is the closure of a TRUNCATED stream (max_output_tokens
        // or content filter): same payload as completed, with incomplete_details.
        // Until 2026-09-30 only 'completed' was handled and a truncated stream did not
        // trigger OnReceiveDataEnd: the consumer waited until its timeout.
        else if (EventType = 'response.completed') or (EventType = 'response.incomplete') then
        begin
          if FRecursionNeeded then
          begin
            DoStateChange(acsConnecting, 'Sending tool results...');
            // ISSUE #100: defer the tool-calling continuation to OnRequestCompletedEvent
            // (base) instead of doing ForceQueue here, INSIDE the receive callback.
            // OnRequestCompletedEvent runs when the request has fully completed
            // and its FSourceStream/FCurrentPostStream have been safely released, eliminating the
            // race between the next POST and the final Seek of THTTPClient.ExecuteHTTPInternal.
            FPendingToolRun := True;
          end
          else
          begin
            FBusy := False;
            var
            FinalMsg := GetLastMessage;
            if Assigned(FinalMsg) and JsonEvent.TryGetValue<TJSonObject>('response', JResp) then
            begin
              if JResp.TryGetValue<TJSonObject>('usage', JUsage) then
              begin
                var LSPrompt: Int64 := 0;
                var LSCompletion: Int64 := 0;
                var LSTotal: Int64 := 0;
                var LSCached: Int64 := 0;
                var LSCacheWrite: Int64 := 0;

                // Normal tokens (Using the names of your class)
                if JUsage.TryGetValue<Int64>('total_tokens', TokenCount) then
                begin
                  FinalMsg.Total_tokens := TokenCount;
                  LSTotal := TokenCount;
                end;
                if JUsage.TryGetValue<Int64>('input_tokens', TokenCount) then
                begin
                  FinalMsg.Prompt_tokens := TokenCount;
                  LSPrompt := TokenCount;
                end;
                if JUsage.TryGetValue<Int64>('output_tokens', TokenCount) then
                begin
                  FinalMsg.Completion_tokens := TokenCount;
                  LSCompletion := TokenCount;
                end;

                // Cached Tokens
                if JUsage.TryGetValue<TJSonObject>('input_tokens_details', JInputDetails) then
                begin
                  if JInputDetails.TryGetValue<Int64>('cached_tokens', TokenCount) then
                  begin
                    FinalMsg.cached_tokens := TokenCount;
                    LSCached := TokenCount;
                  end;
                  // Cache write (GPT-5.6+). See the long comment in
                  // ParseChat: without this the cache write expense is not charged.
                  if JInputDetails.TryGetValue<Int64>('cache_write_tokens', TokenCount) then
                  begin
                    FinalMsg.Cache_write_tokens := TokenCount;
                    LSCacheWrite := TokenCount;
                  end;
                end;

                // Disjoint, as in ParseChat: 'input_tokens' of the
                // Responses API includes the cached and write tokens, and
                // the billing adds all three.
                if (LSCached + LSCacheWrite) > 0 then
                begin
                  if LSPrompt >= (LSCached + LSCacheWrite) then
                  begin
                    LSPrompt := LSPrompt - LSCached - LSCacheWrite;
                    FinalMsg.Prompt_tokens := LSPrompt;
                  end;
                end;

                // Reasoning Tokens
                if JUsage.TryGetValue<TJSonObject>('output_tokens_details', JUsageDetails) then
                  if JUsageDetails.TryGetValue<Int64>('reasoning_tokens', TokenCount) then
                    FinalMsg.Thinking_tokens := TokenCount;

                // Component counters, as in ParseChat: without this, in
                // streaming the consumption also arrived as zero to whoever reads it.
                Self.Prompt_tokens := Self.Prompt_tokens + Integer(LSPrompt);
                Self.Completion_tokens := Self.Completion_tokens + Integer(LSCompletion);
                Self.Total_tokens := Self.Total_tokens + Integer(LSTotal);
                Self.Cached_tokens := Self.Cached_tokens + Integer(LSCached);
                Self.Cache_write_tokens := Self.Cache_write_tokens + Integer(LSCacheWrite);
              end;
              if JResp.TryGetValue<string>('model', DeltaVal) then
                FinalMsg.Model := DeltaVal;
              // Truncation reason, as in synchronous mode (ParseChat).
              var JIncStream := JResp.GetValue('incomplete_details');
              if Assigned(JIncStream) and (JIncStream is TJSonObject) and
                 TJSonObject(JIncStream).TryGetValue<string>('reason', DeltaVal) then
                FinalMsg.FinishReason := DeltaVal;
            end;

            // --- Persist the accumulated text in the message (before it only traveled
            // as an OnReceiveDataEnd event parameter, without remaining in Prompt) ---
            // It is written in the stream text message, NOT in the last one of
            // history: if the turn ended with a delegated computer_call, that
            // last message carries the raw item that the client needs and
            // dumping FLastContent (usually empty) would delete it.
            if Assigned(FStreamTextMsg) then
              FStreamTextMsg.Prompt := FLastContent
            else if Assigned(FinalMsg) then
              FinalMsg.Prompt := FLastContent;

            // --- Parity with synchronous mode: consolidate in the final message the
            // media that the function calling handlers attached during the
            // turn via ToolCall.ResMsg (intermediate assistant messages from the
            // tool rounds). Without this, aMsg.MediaFiles arrived empty at
            // OnReceiveDataEnd in async. It is safe: assistant messages
            // serialize only text to the API (AddMessageToInput), so
            // moving the media does not change the following requests. The media of the
            // 'tool' messages is NOT touched (that one is resent to the model). ---
            if Assigned(FinalMsg) then
            begin
              for var LI := FMessages.Count - 1 downto 0 do
              begin
                var LPrev := FMessages[LI];
                if LPrev.Role = 'user' then
                  Break; // start of the current turn
                if (LPrev = FinalMsg) or (LPrev.Role <> 'assistant') then
                  Continue;
                for var LJ := LPrev.MediaFiles.Count - 1 downto 0 do
                  FinalMsg.AddMediaFile(LPrev.MediaFiles.Extract(LPrev.MediaFiles[LJ]));
              end;
            end;

            // --- Extraction of code to files (MarkdownCodeExtractor) ---
            If cap_ExtractCode in ModelConfig.SessionCaps then
            Begin
              Var
              Code := TMarkdownCodeExtractor.Create;
              Try
                Var
                CodeFiles := Code.ExtractCodeFiles(FLastContent);
                For var CodeFile in CodeFiles do
                Begin
                  Var
                  St := TStringStream.Create(CodeFile.Code);
                  Try
                    St.Position := 0;
                    var
                    MF := TAiMediaFile.Create;
                    MF.LoadFromStream('file.' + CodeFile.FileType, St);
                    if Assigned(FinalMsg) then
                      FinalMsg.MediaFiles.Add(MF);
                  Finally
                    St.Free;
                  End;
                End;
              Finally
                Code.Free;
              End;
            End;
            // --------------------------------------------------------------

            DoStateChange(acsFinished, 'Completed');
            if Assigned(FOnReceiveDataEnd) then
              FOnReceiveDataEnd(Self, FinalMsg, nil, 'assistant', FLastContent);
          end;
        end

        // --- G) ERRORS ---
        // response.failed is the closure of a FAILED turn (carries response.error);
        // 'error' is the loose protocol failure. Both must end through the
        // real error path: DoStateChange(acsError) alone does NOT trigger
        // OnError, so the consumer was not notified and waited for its timeout,
        // the same silence that response.incomplete had.
        else if (EventType = 'error') or (EventType = 'response.failed') then
        begin
          FBusy := False;
          var LErrMsg := '';
          if (EventType = 'response.failed') and
             JsonEvent.TryGetValue<TJSonObject>('response', JResp) then
          begin
            var JErrV := JResp.GetValue('error');
            if Assigned(JErrV) and (JErrV is TJSonObject) then
              TJSonObject(JErrV).TryGetValue<string>('message', LErrMsg);
          end;
          if LErrMsg = '' then
            LErrMsg := JsonEvent.ToString;
          DoError(LErrMsg, nil);
        end;

      finally
        JsonEvent.Free;
      end;
    end;
  end;
end;

Initialization

TAiChatFactory.Instance.RegisterDriver(TAiOpenChat);

end.
