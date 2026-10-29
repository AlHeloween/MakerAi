unit uMakerAi.Chat.Messages;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  Rest.JSON, REST.Json.Types, System.Net.Mime, System.NetEncoding, System.TypInfo, System.Types, System.SyncObjs,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Core; // Assuming TAiMediaFiles, TAiWebSearch and TAiMetadata are here

Type

  TAiMsgCitation = class;
  TAiMsgCitations = class;
  TAiChatMessage = Class;

  // Citations relate the detail of the answer with the original text.
  // They can work as details for web searches, within a PDF, in RAG, etc.
  // They are especially used as a property in TAiMessage.

  TAiCitationSourceType = (cstUnknown, cstDocument, cstWeb, cstFile, cstDatabase);

  // Class that handles the functions of the tools
  TAiToolsFunction = class(TObject)
  private
    FParams: TStringList;
    FParamsCachedArgs: string;
    function GetParams: TStringList;
  public
    id: string;
    &Type: string;
    name: string;
    Description: String; // Function description
    Arguments: string; // Parameters in JSON format (canonical). Always use this field.
    &Function: string; // Complete serialized definition of the function (JFunc.Format)
    Response: String; // Response to the LLM: plain text or JSON string, both are valid
    Metadata: TAiMetadata; // Additional metadata that can be sent to the function
    AskMsg: TAiChatMessage; // TAiChatMessage representing the question
    ResMsg: TAiChatMessage; // TAiChatMessage representing the response
    MediaFiles: TAiMediaFiles; // Files extracted by the tool (e.g., images returned by MCP)
    // If the handler sets it to True, TAiChat does NOT continue the agentic loop after
    // executing the tools of this turn: the tool_call must return to the caller
    // (pass-through case: the tool is executed by the final client, not by this process).
    // Prevents insistent models (gpt-oss) from retrying the tool in a loop when
    // receiving a synthetic 'OK' response.
    StopAgenticLoop: Boolean;
    // The 'function_call' item from the Responses API comes marked with async:true
    // when the tool was declared asynchronous. It is propagated so that the caller
    // knows that it does NOT have to block the turn waiting for this result: it can
    // return it later referencing the same call_id.
    IsAsync: Boolean;

    Constructor Create;
    Destructor Destroy; Override;
    Procedure ParseFunction(JObj: TJSONObject); // This function will be replaced by these two as needed

    Procedure Assign(aSource: TAiToolsFunction);

    // Params: easy access to the tool call arguments as Name=Value.
    // Parsed from Arguments (JSON) in a lazy way. Example: ToolCall.Params.Values['PDFFileName']
    property Params: TStringList read GetParams;
  end;

  TAiToolsFunctions = Class(TDictionary<String, TAiToolsFunction>)
  Private
  Protected
    procedure ValueNotify(const Value: TAiToolsFunction; Action: TCollectionNotification); override;
  Public
    Function ToOutputJSon: TJSonArray;
    Function ToFunctionsJSon: TJSonArray;
    Procedure AddFunction(aBody: String); Overload;
    Procedure AddFunction(aBody: TJSONObject); Overload;
  End;

  TAiChatMessage = Class(TObject)
  Private
    FPreviousResponseId: String;
    [JSONMarshalled(False)]
    FWebSearchResponse: TAiWebSearch;
    FReasoningContent: String;
    FIsToolCallResponse: Boolean;
    FModel: String;
    [JSONMarshalled(False)]
    FCitations: TAiMsgCitations;
    FStopReason: String;
    FIsRefusal: Boolean;
    FThinkingSignature: String;
    FCacheControl: Boolean;
    FThinking_tokens: Integer;
    FFinishReason: String;
    FCached_tokens: Integer;
    FCacheWrite_tokens: Integer;
    [JSONMarshalled(False)]
    FLock: TCriticalSection;
    procedure SetRole(const Value: String);
    procedure SetPrompt(const Value: String);
    procedure SetFunctionName(const Value: String);
    procedure SetToolCallId(const Value: String);
    procedure SetTool_calls(const Value: String);
    procedure SetFId(const Value: Integer);
    procedure SetCompletion_tokens(const Value: Integer);
    procedure SetPrompt_tokens(const Value: Integer);
    procedure SetTotal_tokens(const Value: Integer);
    procedure SetFPreviousResponseId(const Value: String);
    procedure SetWebSearchResponse(const Value: TAiWebSearch);
    procedure SetReasoningContent(const Value: String);
    procedure SetIsToolCallResponse(const Value: Boolean);
    procedure SetModel(const Value: String);
    procedure SetCitations(const Value: TAiMsgCitations);
    procedure SetIsRefusal(const Value: Boolean);
    procedure SetStopReason(const Value: String);
    procedure SetThinking_tokens(const Value: Integer);
    procedure SetFinishReason(const Value: String);
    procedure SetCached_tokens(const Value: Integer);
    procedure SetCache_write_tokens(const Value: Integer);
  Protected
    FRole: String;
    FPrompt: String;
    FCompletion_tokens: Integer;
    FTotal_tokens: Integer;
    FPrompt_tokens: Integer;
    FId: Integer;
    FToolCallId: String;
    FFunctionName: String;
    FTool_calls: String;
    [JSONMarshalled(False)]
    FMediaFiles: TAiMediaFiles;
  Public
    Constructor Create; overload;
    Constructor Create(aPrompt, aRole: String; aToolCallId: String = ''; aFunctionName: String = ''); overload;
    Destructor Destroy; Override;

    Procedure AddMediaFile(aMediaFile: TAiMediaFile);
    Procedure LoadMediaFromFile(aFileName: String);
    Procedure LoadMediaFromStream(aFileName: String; Stream: TMemoryStream);
    Procedure LoadMediaFromBase64(aFileName: String; aBase64: String);

    Function HasUnprocessedItems: Boolean;
    Function GetMediaTranscription: String; // Returns the transcriptions of all media files

    Function StreamToBase64(Stream: TMemoryStream): String;
    Function ToJSon: TJSonArray; // Converts the object into a JSON to send to the API

    Property id: Integer Read FId Write SetFId;
    Property Role: String read FRole write SetRole;
    Property Prompt: String read FPrompt write SetPrompt;
    Property Prompt_tokens: Integer read FPrompt_tokens Write SetPrompt_tokens;
    Property Completion_tokens: Integer read FCompletion_tokens Write SetCompletion_tokens;
    Property Total_tokens: Integer read FTotal_tokens Write SetTotal_tokens;
    Property Thinking_tokens: Integer read FThinking_tokens write SetThinking_tokens;
    Property Cached_tokens: Integer read FCached_tokens write SetCached_tokens;
    Property Cache_write_tokens: Integer read FCacheWrite_tokens write SetCache_write_tokens;

    Property Model: String read FModel write SetModel;
    Property ToolCallId: String read FToolCallId write SetToolCallId;
    Property FunctionName: String read FFunctionName write SetFunctionName;
    Property Tool_calls: String read FTool_calls write SetTool_calls;
    Property MediaFiles: TAiMediaFiles Read FMediaFiles;
    Property WebSearchResponse: TAiWebSearch read FWebSearchResponse write SetWebSearchResponse;
    Property PreviousResponseId: String read FPreviousResponseId Write SetFPreviousResponseId; // New property
    Property ReasoningContent: String read FReasoningContent write SetReasoningContent;
    Property IsToolCallResponse: Boolean read FIsToolCallResponse write SetIsToolCallResponse;
    property Citations: TAiMsgCitations read FCitations write SetCitations;
    Property StopReason: String read FStopReason write SetStopReason;
    Property IsRefusal: Boolean read FIsRefusal write SetIsRefusal;
    Property ThinkingSignature: String read FThinkingSignature write FThinkingSignature; // For now only for Claude
    Property CacheControl: Boolean read FCacheControl write FCacheControl; // For now only used in Claude to indicate messages that should be kept in Cache
    Property FinishReason: String read FFinishReason write SetFinishReason;
  End;

  TAiChatMessages = Class(TList<TAiChatMessage>) // future update: change TList to TObjectList
  Private
    FModelCaps: TAiCapabilities;
    function GetAsText: String;
    procedure SetAsText(const Value: String);
  Protected
  Public
    Function ToJSon: TJSonArray;
    Function ExportChatHistory: TJSONObject;
    Function ToJsonChatArchive: TJSONObject;
    Procedure SaveToStream(Stream: TStream);
    Procedure SaveToFile(FileName: String);
    Procedure LoadFromStream(Stream: TStream);
    Procedure LoadFromFile(FileName: String);
    Property AsText: String Read GetAsText Write SetAsText;
    Property ModelCaps: TAiCapabilities read FModelCaps write FModelCaps;
  End;

  // Base class for any type of data source.
  TAiSourceData = class
  public
    id: string; // Internal ID (e.g., 'doc-0', 'file-123')
    Title: string; // Title of the web page, document, etc.
    Content: string; // Snippet, file content, etc.
    Url: string; // URL if it's a web source.
    Metadata: TAiMetadata; // For any other data (author, date, etc.)

    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TAiSourceData);
  end;

  // Represents a specific source linked to a citation.
  TAiCitationSource = class
  public
    SourceType: TAiCitationSourceType;
    DataSource: TAiSourceData;

    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TAiCitationSource);
  end;

  // Represents a citation within the model's response text.
  TAiMsgCitation = class
  public
    StartIndex: Integer; // Starting position of the cited text in the response.
    EndIndex: Integer; // Ending position.
    Text: String; // The exact text fragment that was cited.
    Sources: TObjectList<TAiCitationSource>; // List of sources for this fragment.

    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TAiMsgCitation);
  end;

  // A collection of citations for a message.
  TAiMsgCitations = class(TObjectList<TAiMsgCitation>)
  public
    procedure Assign(Source: TAiMsgCitations);
  end;

implementation

{ TAiChatMessage }

procedure TAiChatMessage.AddMediaFile(aMediaFile: TAiMediaFile);
begin
  FLock.Enter;
  Try
    FMediaFiles.Add(aMediaFile);
  Finally
    FLock.Leave;
  End;
end;

constructor TAiChatMessage.Create;
begin
  Create('', '');
end;

constructor TAiChatMessage.Create(aPrompt, aRole: String; aToolCallId: String = ''; aFunctionName: String = '');
begin
  Inherited Create;
  FLock := TCriticalSection.Create;
  Self.FRole := aRole;
  Self.FPrompt := aPrompt;
  Self.FFunctionName := aFunctionName;
  Self.FToolCallId := aToolCallId;
  FMediaFiles := TAiMediaFiles.Create;
  FWebSearchResponse := TAiWebSearch.Create;
  FPreviousResponseId := ''; // Initialize the new property
  FCitations := TAiMsgCitations.Create(True);
  FCacheControl := False;
end;

destructor TAiChatMessage.Destroy;
begin
  FMediaFiles.Free;
  FCitations.Free;
  FWebSearchResponse.Free;
  FLock.Free;
  inherited;
end;

function TAiChatMessage.GetMediaTranscription: String;
Var
  MF: TAiMediaFile;
begin
  FLock.Enter;
  Try
    Result := '';

    for MF in MediaFiles do
    begin
      If MF.Procesado = True then
        Result := Trim(Result + sLineBreak + MF.Transcription);
    end;
  Finally
    FLock.Leave;
  End;
end;

function TAiChatMessage.HasUnprocessedItems: Boolean;
Var
  MF: TAiMediaFile;
begin
  FLock.Enter;
  Try
    Result := False;

    for MF in MediaFiles do
    begin
      If MF.Procesado = False then
      Begin
        Result := True;
        Break;
      End;
    end;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.LoadMediaFromBase64(aFileName, aBase64: String);
Var
  Media: TAiMediaFile;
begin
  FLock.Enter;
  Try
    If Length(Trim(aBase64)) < 100 then
      Raise Exception.Create('The Base64 is empty, it will not be loaded');

    If aFileName = '' then // See how to assign a name from the stream content
      aFileName := 'imagen.jpg';

    Media := TAiMediaFile.Create;
    Media.LoadFromBase64(aFileName, aBase64);

    AddMediaFile(Media);
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.LoadMediaFromFile(aFileName: String);
Var
  Media: TAiMediaFile;
begin
  FLock.Enter;
  Try
    If Not FileExists(aFileName) then
      Raise Exception.Create('The file "' + aFileName + '" was not found');

    Media := TAiMediaFile.Create;
    Media.LoadFromFile(aFileName);
    AddMediaFile(Media);
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.LoadMediaFromStream(aFileName: String; Stream: TMemoryStream);
Var
  Media: TAiMediaFile;
begin
  FLock.Enter;
  Try
    If Stream.Size <= 100 then
      Raise Exception.Create('The stream is empty');

    If aFileName = '' then // See how to assign a name from the stream content
      aFileName := 'imagen.jpg';

    Media := TAiMediaFile.Create;
    Media.LoadFromStream(aFileName, Stream);
    Self.AddMediaFile(Media);
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetCached_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FCached_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetCache_write_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FCacheWrite_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetCitations(const Value: TAiMsgCitations);
var
  SourceCitation: TAiMsgCitation;
  NewCitation: TAiMsgCitation;
begin
  FLock.Enter;
  Try

    // Always clear the destination list first.
    // Since the list owns its objects, this will destroy them correctly.
    FCitations.Clear;

    // If the source list is nil or empty, we are done.
    if not Assigned(Value) or (Value.Count = 0) then
      Exit;

    // Iterate over the source list and create clones of each object.
    for SourceCitation in Value do
    begin
      // 1. Create a new instance of the citation object.
      NewCitation := TAiMsgCitation.Create;
      try
        // 2. Use the Assign method we just created to clone the content.
        NewCitation.Assign(SourceCitation);
        // 3. Add the new cloned object to our list.
        FCitations.Add(NewCitation);
      except
        // In case of error during assignment, ensure memory is freed.
        NewCitation.Free;
        raise;
      end;
    end;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetCompletion_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FCompletion_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetFId(const Value: Integer);
begin
  FLock.Enter;
  Try
    FId := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetFinishReason(const Value: String);
begin
  FLock.Enter;
  Try
    FFinishReason := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetFPreviousResponseId(const Value: String);
begin
  FLock.Enter;
  Try
    FPreviousResponseId := Value;
  Finally
    FLock.Leave;

  End;
end;

procedure TAiChatMessage.SetFunctionName(const Value: String);
begin
  FLock.Enter;
  Try
    FFunctionName := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetIsRefusal(const Value: Boolean);
begin
  FLock.Enter;
  Try
    FIsRefusal := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetIsToolCallResponse(const Value: Boolean);
begin
  FLock.Enter;
  Try
    FIsToolCallResponse := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetModel(const Value: String);
begin
  FLock.Enter;
  Try
    FModel := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetPrompt(const Value: String);
begin
  FLock.Enter;
  Try
    FPrompt := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetPrompt_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FPrompt_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetReasoningContent(const Value: String);
begin
  FLock.Enter;
  Try
    FReasoningContent := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetRole(const Value: String);
begin
  FLock.Enter;
  Try
    FRole := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetStopReason(const Value: String);
begin
  FLock.Enter;
  Try
    FStopReason := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetThinking_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FThinking_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetToolCallId(const Value: String);
begin
  FLock.Enter;
  Try
    FToolCallId := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetTool_calls(const Value: String);
begin
  FLock.Enter;
  Try
    FTool_calls := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetTotal_tokens(const Value: Integer);
begin
  FLock.Enter;
  Try
    FTotal_tokens := Value;
  Finally
    FLock.Leave;
  End;
end;

procedure TAiChatMessage.SetWebSearchResponse(const Value: TAiWebSearch);
begin
  FLock.Enter;
  Try
    if FWebSearchResponse <> Value then
    begin
      FWebSearchResponse.Free;
      FWebSearchResponse := Value;
    end;
  Finally
    FLock.Leave;
  End;
end;

function TAiChatMessage.StreamToBase64(Stream: TMemoryStream): String;
begin
  FLock.Enter;
  Try
    Stream.Position := 0;
    Result := TNetEncoding.Base64.EncodeBytesToString(Stream.Memory, Stream.Size);
  Finally
    FLock.Leave;
  End;
end;

function TAiChatMessage.ToJSon: TJSonArray;
Var
  Msg: TAiChatMessage;
  JObj, JMsg: TJSONObject;
  JContent: TJSonArray;
  ImagePayload: TStringStream;
  Base64, Mime: String;
  MediaArr: TAiMediaFilesArray;
begin
  // This function only takes the current message and a single image, the first one found in the list
  // This is especially done for models that only accept one image per request and not a full chat

  FLock.Enter;
  Try

    Result := TJSonArray.Create;

    Msg := Self;
    JObj := TJSONObject.Create;
    JObj.AddPair('role', Msg.FRole);

    If Msg.FToolCallId <> '' then
      JObj.AddPair('tool_call_id', Msg.FToolCallId);

    If (Msg.FFunctionName <> '') then // and (Msg.FRole <> 'tool') then
      JObj.AddPair('name', Msg.FFunctionName);

    // From all media files, select the images that we can handle for now
    // and images that have not been preprocessed, in case the model does not handle images, previously
    // they should have been processed at the moment of adding the message to the chat
    MediaArr := Msg.MediaFiles.GetMediaList([Tfc_Image], False);

    If (Length(MediaArr) > 0) then
    Begin

      JContent := TJSonArray.Create;
      JMsg := TJSONObject.Create;
      JMsg.AddPair('type', 'text');
      JMsg.AddPair('text', Msg.FPrompt);
      JContent.Add(JMsg);

      If Msg.MediaFiles.Count > 0 then // Only take the first image
      Begin
        Base64 := Msg.MediaFiles[0].Base64;
        Mime := Msg.MediaFiles[0].MimeType;

        ImagePayload := TStringStream.Create('{"type": "image_url", "image_url": {"url": "data:' + Mime + ';base64,' + Base64 + '"}}', TEncoding.UTF8);
        try
          JContent.Add(TJSONObject.ParseJSONValue(ImagePayload.DataString) as TJSONObject);
        finally
          ImagePayload.Free;
        end;

      End;
      JObj.AddPair('content', JContent);
    End
    Else
    Begin

      JObj.AddPair('content', Msg.FPrompt);
    End;

    If Msg.FTool_calls <> '' then

{$IF CompilerVersion < 35}
      JObj.AddPair('tool_calls', TJSONUtils.ParseAsArray(Msg.FTool_calls));
{$ELSE}
      JObj.AddPair('tool_calls', TJSonArray(TJSonArray.ParseJSONValue(Msg.FTool_calls)));
{$ENDIF}
    Result.Add(JObj);
  Finally
    FLock.Leave;
  End;
end;




{ TAiChatMessages }

function TAiChatMessages.ExportChatHistory: TJSONObject;
Var
  JObj, JItem: TJSONObject;
  JArr: TJSonArray;
  I: Integer;
  Item: TAiChatMessage;
begin
  JObj := TJSONObject.Create;
  JArr := TJSonArray.Create;

  Try
    JObj.AddPair('model', 'MakerAiChat');
    JObj.AddPair('type', 'Messages');
    JObj.AddPair('ver', '1.0');

    For I := 0 to Self.Count - 1 do
    Begin
      Item := Self.Items[I];
      JItem := TJSONObject.Create;

      JItem.AddPair('role', Item.Role);
      JItem.AddPair('prompt', Item.Prompt);
      JArr.Add(JItem);
    End;
    JObj.AddPair('data', JArr);
    Result := JObj;

  Finally
    // jObj.Free;
  End;
end;



function TAiChatMessages.GetAsText: String;
Var
  St: TStringStream;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  Try
    SaveToStream(St);
    Result := St.DataString;
  Finally
    St.Free;
  End;
end;

procedure TAiChatMessages.LoadFromFile(FileName: String);
Var
  St: TStringStream;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  Try
    If FileExists(FileName) then
    Begin
      St.LoadFromFile(FileName);
      St.Position := 0;
      LoadFromStream(St);
    End;
  Finally
    St.Free;
  End;
end;

procedure TAiChatMessages.LoadFromStream(Stream: TStream);
Var
  JObj, JItem: TJSONObject;
  JArr: TJSonArray;
  sJson, Model, S: String;
  St: TStringStream;
  Item: TAiChatMessage;
  I: Integer;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  Try
    St.LoadFromStream(Stream);
    sJson := St.DataString;

    JObj := TJSONObject(TJSONObject.ParseJSONValue(sJson));

    If Assigned(JObj) and (JObj.TryGetValue<String>('model', Model)) then
    Begin
      If (Model = 'AiOpenChat') or (Model = 'MakerAiChat') then
      Begin
        JArr := TJSonArray(JObj.GetValue<TJSonArray>('data'));

        S := JArr.Format;
        If JArr.Count > 0 then
          Self.Clear;

        For I := 0 to JArr.Count - 1 do
        Begin

{$IF CompilerVersion < 35}
          JItem := JArr.GetItemAsObject(I);
{$ELSE}
          JItem := TJSONObject(JArr[I]);
{$ENDIF}
          Item := TJSon.JsonToObject<TAiChatMessage>(JItem);
          Self.Add(Item);
        End;
      End;
    End;
  Finally
    St.Free;
    FreeAndNil(JObj);
  End;
end;

procedure TAiChatMessages.SaveToFile(FileName: String);
Var
  St: TStringStream;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  Try
    Self.SaveToStream(St);
    St.Position := 0;
    St.SaveToFile(FileName);
  Finally
    St.Free;
  End;
end;

function TAiChatMessages.ToJsonChatArchive: TJSONObject;
Var
  JArr: TJSonArray;
  JItem: TJSONObject;
  I: Integer;
  Item: TAiChatMessage;
begin
  Result := TJSONObject.Create;
  JArr := TJSonArray.Create;

  Result.AddPair('model', 'MakerAiChat');
  Result.AddPair('type', 'Messages');
  Result.AddPair('ver', '1.0');

  For I := 0 to Self.Count - 1 do
  Begin
    Item := Self.Items[I];
    JItem := TJSon.ObjectToJsonObject(Item);
    JArr.Add(JItem);
  End;

  Result.AddPair('data', JArr);
end;

procedure TAiChatMessages.SaveToStream(Stream: TStream);
Var
  JObj: TJSONObject;
  St: TStringStream;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  JObj := ToJsonChatArchive;
  Try
    St.WriteString(JObj.Format);
    St.SaveToStream(Stream);
  Finally
    St.Free;
    JObj.Free;
  End;
end;

procedure TAiChatMessages.SetAsText(const Value: String);
Var
  St: TStringStream;
begin
  St := TStringStream.Create('', TEncoding.UTF8);
  Try
    If Trim(Value) <> '' then
    Begin
      St.WriteString(Value);
      St.Position := 0;
      LoadFromStream(St);
    End;
  Finally
    St.Free;
  End;
end;

function TAiChatMessages.ToJSon: TJSonArray;
Var
  I, J: Integer;
  Msg: TAiChatMessage;
  JObj, JMsg: TJSONObject;
  JObjImg, jImgUrl, jAudio: TJSONObject;
  JContent: TJSonArray;
  Base64, Mime: String;
  MediaArr: TAiMediaFilesArray;
  S: String;
  MediaFile: TAiMediaFile;
  LPendingMedia: TList<TAiMediaFile>; // native media from tool results, pending to be dumped
  LPendingNames: TStringList; // names of the tools that returned it
  LResult: TJSonArray;

  // Returns the content of a text attachment as a string (UTF-8).
  function MediaFileAsText(AMediaFile: TAiMediaFile): String;
  var
    LTextBytes: TBytes;
  begin
    Result := '';
    if AMediaFile.Content.Size <= 0 then
      Exit;
    AMediaFile.Content.Position := 0;
    SetLength(LTextBytes, AMediaFile.Content.Size);
    AMediaFile.Content.ReadBuffer(LTextBytes[0], AMediaFile.Content.Size);
    Result := TEncoding.UTF8.GetString(LTextBytes);
  end;

  // Dumps the accumulated native media from a group of tool results as a synthetic
  // 'user' message. The OpenAI contract requires that ALL 'tool' messages
  // are placed immediately after the assistant that requested them (one per tool_call_id)
  // with nothing in between, so this is called just before the first non-'tool' message
  // and when closing the loop, never between two tool results.
  procedure FlushToolMedia;
  var
    LObj, LPart, LUrlObj, LAudObj: TJSONObject;
    LArr: TJSonArray;
    LMF: TAiMediaFile;
    K: Integer;
  begin
    if LPendingMedia.Count = 0 then
      Exit;

    LArr := TJSonArray.Create;
    LPart := TJSONObject.Create;
    LPart.AddPair('type', 'text');
    LPart.AddPair('text', '[Attachments returned by the tool ' + LPendingNames.CommaText +
      '. The textual result goes in the previous tool message.]');
    LArr.Add(LPart);

    for K := 0 to LPendingMedia.Count - 1 do
    begin
      LMF := LPendingMedia[K];
      case LMF.FileCategory of
        Tfc_Image:
          begin
            LUrlObj := TJSONObject.Create;
            LUrlObj.AddPair('url', 'data:' + LMF.MimeType + ';base64,' + LMF.Base64);
            if LMF.Detail <> '' then
              LUrlObj.AddPair('detail', LMF.Detail);
            LPart := TJSONObject.Create;
            LPart.AddPair('type', 'image_url');
            LPart.AddPair('image_url', LUrlObj);
            LArr.Add(LPart);
          end;
        Tfc_Audio:
          begin
            LAudObj := TJSONObject.Create;
            LAudObj.AddPair('data', LMF.Base64);
            LAudObj.AddPair('format', StringReplace(LMF.MimeType, 'audio/', '', [rfReplaceAll]));
            LPart := TJSONObject.Create;
            LPart.AddPair('type', 'input_audio');
            LPart.AddPair('input_audio', LAudObj);
            LArr.Add(LPart);
          end;
      end;
    end;

    LObj := TJSONObject.Create;
    LObj.AddPair('role', 'user');
    LObj.AddPair('content', LArr);
    LResult.Add(LObj);

    LPendingMedia.Clear;
    LPendingNames.Clear;
  end;

begin
  Result := TJSonArray.Create;
  LResult := Result; // visible for FlushToolMedia

  LPendingMedia := TList<TAiMediaFile>.Create;
  LPendingNames := TStringList.Create;
  try
    LPendingNames.Duplicates := dupIgnore;
    LPendingNames.Sorted := True;

  For I := 0 to Count - 1 do
  Begin
    Msg := Self.Items[I];

    // Close the group of tool results: accumulated media is dumped BEFORE this
    // message, which is no longer a 'tool'.
    if not SameText(Msg.FRole, 'tool') then
      FlushToolMedia;

    JObj := TJSONObject.Create;
    JObj.AddPair('role', Msg.FRole);

    If Msg.FToolCallId <> '' then
      JObj.AddPair('tool_call_id', Msg.FToolCallId);

    If Msg.FFunctionName <> '' then
      JObj.AddPair('name', Msg.FFunctionName);

    // Messages with role:'tool' ALWAYS carry a content string: the OpenAI/Groq
    // contract rejects arrays in tool results ("messages[N].content must
    // be a string"), and Chat Completions does not accept images in role 'tool'
    // in any way. Drivers with their own serializer handle it natively
    // (Claude: content blocks inside tool_result; Gemini: extra parts in the
    // same turn; Ollama: images field), so this is only for the OpenAI-compatible
    // family:
    //   - text attachments are inlined into the result string;
    //   - native media (image/audio) is accumulated and dumped after the group
    //     as a synthetic 'user' message (see FlushToolMedia);
    //   - if the model does not declare the capability, it falls back to the
    //     transcription left by the vision/audio bridge.
    // NOTE: if this grows, tool result images are re-sent in every subsequent
    // turn. If it ever becomes a token issue, the solution is NOT a flag here
    // but a pruning in TAiChat that honors the four serializers equally;
    // today Claude/Gemini/Ollama already behave this way and nobody has reported it.
    if SameText(Msg.FRole, 'tool') then
    begin
      var LToolText := Msg.FPrompt;

      // Text attachments: inline, without extra message and without loss.
      for MediaFile in Msg.MediaFiles.GetMediaList([Tfc_Text], False) do
      begin
        var LFileText := MediaFileAsText(MediaFile);
        if LFileText <> '' then
          LToolText := LToolText + sLineBreak + '[File: ' + MediaFile.Filename + ']' + sLineBreak + LFileText;
      end;

      // Bridge transcription. TAiChat.RunNew already injects it into the Prompt of
      // the AskMsg, and in a continuation the AskMsg IS this tool message: without the
      // Pos() the text would appear duplicated.
      var LToolTrans := Msg.GetMediaTranscription;
      if (LToolTrans <> '') and (Pos(LToolTrans, LToolText) = 0) then
        LToolText := LToolText + sLineBreak + '[Attachment description]: ' + LToolTrans;

      JObj.AddPair('content', LToolText);
      Result.Add(JObj);

      // Native media -> buffer; FlushToolMedia dumps it when closing the group.
      var LToolNative: TAiFileCategories := [];
      if cap_Image in FModelCaps then Include(LToolNative, Tfc_Image);
      if cap_Audio in FModelCaps then Include(LToolNative, Tfc_Audio);
      if LToolNative <> [] then
        for MediaFile in Msg.MediaFiles.GetMediaList(LToolNative, False) do
        begin
          LPendingMedia.Add(MediaFile);
          if Msg.FFunctionName <> '' then
            LPendingNames.Add(Msg.FFunctionName);
        end;

      Continue;
    end;

    // Filter files that the model accepts natively (derived from FModelCaps)
    var LNativeTypes: TAiFileCategories := [Tfc_Text];
    if cap_Image in FModelCaps then Include(LNativeTypes, Tfc_Image);
    if cap_Audio in FModelCaps then Include(LNativeTypes, Tfc_Audio);
    if cap_Video in FModelCaps then Include(LNativeTypes, Tfc_Video);
    if cap_Pdf   in FModelCaps then Include(LNativeTypes, Tfc_Pdf);
    MediaArr := Msg.MediaFiles.GetMediaList(LNativeTypes, False);

    If (Length(MediaArr) > 0) then
    Begin

      JContent := TJSonArray.Create;
      JMsg := TJSONObject.Create;
      JMsg.AddPair('type', 'text');
      JMsg.AddPair('text', Msg.FPrompt);
      JContent.Add(JMsg);

      For J := 0 to Length(MediaArr) - 1 do // OpenAI allows uploading Base64 or URL, always upload Base64 by standard
      Begin
        MediaFile := MediaArr[J];

        Case MediaFile.FileCategory of
          TAiFileCategory.Tfc_Image:
            Begin
              Base64 := MediaFile.Base64;
              Mime := MediaFile.MimeType;

              // This is another way to do the same with JSON directly
              S := 'data:' + Mime + ';base64,' + Base64;

              jImgUrl := TJSONObject.Create;
              jImgUrl.AddPair('url', S);

              If MediaFile.Detail <> '' then // If it defines high or low.
                jImgUrl.AddPair('detail', MediaFile.Detail);

              JObjImg := TJSONObject.Create;
              JObjImg.AddPair('type', 'image_url');
              JObjImg.AddPair('image_url', jImgUrl);

              JContent.Add(JObjImg);

            End;
          TAiFileCategory.Tfc_Audio:
            Begin
              If MediaFile.IdAudio <> '' then // If it is a model response, use this
              Begin
                jAudio := TJSONObject.Create;
                jAudio.AddPair('id', MediaFile.IdAudio);
                JObj.AddPair('audio', jAudio);
              End
              Else // If it is user audio, use this
              Begin
                jAudio := TJSONObject.Create;
                jAudio.AddPair('data', MediaFile.Base64);
                jAudio.AddPair('format', StringReplace(MediaFile.MimeType, 'audio/', '', [rfReplaceAll]));

                JMsg := TJSONObject.Create;
                JMsg.AddPair('type', 'input_audio');
                JMsg.AddPair('input_audio', jAudio);
                JContent.Add(JMsg);
              End;
            End;

          TAiFileCategory.Tfc_Video:
            Begin
            end;
          TAiFileCategory.Tfc_Pdf: // Completions does not handle PDF yet, must use Responses
            Begin
            end;
          TAiFileCategory.Tfc_Document:
            Begin
            end;
          TAiFileCategory.Tfc_Text:
            Begin
              if MediaFile.Content.Size > 0 then
              begin
                MediaFile.Content.Position := 0;
                var LTextBytes: TBytes;
                SetLength(LTextBytes, MediaFile.Content.Size);
                MediaFile.Content.ReadBuffer(LTextBytes[0], MediaFile.Content.Size);
                var LFileText := TEncoding.UTF8.GetString(LTextBytes);
                JMsg := TJSONObject.Create;
                JMsg.AddPair('type', 'text');
                JMsg.AddPair('text', '[File: ' + MediaFile.Filename + ']' + sLineBreak + LFileText);
                JContent.Add(JMsg);
              end;
            end;
          TAiFileCategory.Tfc_CalcSheet:
            Begin
            end;
          TAiFileCategory.Tfc_Presentation:
            Begin
            end;
          TAiFileCategory.Tfc_CompressFile:
            Begin
            end;
          TAiFileCategory.Tfc_Web:
            Begin
            end;
          TAiFileCategory.Tfc_GraphicDesign:
            Begin
            end;
          TAiFileCategory.Tfc_Unknown:
            Begin
            end;

        Else
          Begin
            JObj.AddPair('content', Msg.FPrompt);
          End;
        End;
      End;

      JObj.AddPair('content', JContent);

    End
    Else // If it has no media files, simply send the prompt
    Begin
      JObj.AddPair('content', Msg.FPrompt);
    End;

    If Msg.FTool_calls <> '' then

{$IF CompilerVersion < 35}
      JObj.AddPair('tool_calls', TJSONUtils.ParseAsArray(Msg.FTool_calls));
{$ELSE}
      JObj.AddPair('tool_calls', TJSonArray(TJSonArray.ParseJSONValue(Msg.FTool_calls)));
{$ENDIF}

    // reasoning_content is saved in TAiChatMessage.ReasoningContent for UI display
    // (via OnReceiveThinking), but it is NOT re-sent to the API in the history.
    // Drivers that require it (DeepSeek) add it in their own GetMessages override.

    Result.Add(JObj);
  end;

    // The history may end in a group of tool results (continuation):
    // its media dumps here.
    FlushToolMedia;
  finally
    LPendingMedia.Free;
    LPendingNames.Free;
  end;
end;

procedure TAiSourceData.Assign(Source: TAiSourceData);
var
  Pair: TPair<string, string>;
begin
  if not Assigned(Source) or (Source = Self) then
    Exit;

  Self.id := Source.id;
  Self.Title := Source.Title;
  Self.Content := Source.Content;
  Self.Url := Source.Url;

  // Clear the destination metadata dictionary.
  Self.Metadata.Clear;

  // Iterate over each key-value pair in the source dictionary
  // and add it to the destination dictionary. This is the correct way.
  for Pair in Source.Metadata do
  begin
    Self.Metadata.Add(Pair.Key, Pair.Value);
  end;
end;

{ ------------------------------------------------------------------------------ }
{ TAiSourceData }
{ ------------------------------------------------------------------------------ }

constructor TAiSourceData.Create;
begin
  inherited Create;
  // It is crucial to instantiate the Metadata object to avoid memory access errors.
  Metadata := TAiMetadata.Create;
end;

destructor TAiSourceData.Destroy;
begin
  // Free the object we created in the constructor.
  Metadata.Free;
  inherited Destroy;
end;

procedure TAiCitationSource.Assign(Source: TAiCitationSource);
begin
  if not Assigned(Source) or (Source = Self) then
    Exit;
  Self.SourceType := Source.SourceType;
  Self.DataSource.Assign(Source.DataSource);
end;
{ ------------------------------------------------------------------------------ }
{ TAiCitationSource }
{ ------------------------------------------------------------------------------ }

constructor TAiCitationSource.Create;
begin
  inherited Create;
  // Initialize the source type to a safe default value.
  SourceType := cstUnknown;
  // Instantiate the data container so it is ready to be used.
  DataSource := TAiSourceData.Create;
end;

destructor TAiCitationSource.Destroy;
begin
  // Free the data object that belongs to it.
  DataSource.Free;
  inherited Destroy;
end;

procedure TAiMsgCitation.Assign(Source: TAiMsgCitation);
var
  SourceItem: TAiCitationSource;
  NewItem: TAiCitationSource;
begin
  if not Assigned(Source) or (Source = Self) then
    Exit;

  Self.StartIndex := Source.StartIndex;
  Self.EndIndex := Source.EndIndex;
  Self.Text := Source.Text;

  // Perform a deep copy of the sources list
  Self.Sources.Clear;
  for SourceItem in Source.Sources do
  begin
    NewItem := TAiCitationSource.Create;
    NewItem.Assign(SourceItem);
    Self.Sources.Add(NewItem);
  end;
end;

{ ------------------------------------------------------------------------------ }
{ TAiMsgCitation }
{ ------------------------------------------------------------------------------ }

constructor TAiMsgCitation.Create;
begin
  inherited Create;
  // Initialize primitive values.
  StartIndex := 0;
  EndIndex := 0;
  Text := '';
  // Create the list of sources and tell it that it owns the objects
  // it contains (parameter 'True'). This simplifies memory management,
  // because when the list is freed, all sources will be automatically freed.
  Sources := TObjectList<TAiCitationSource>.Create(True);
end;

destructor TAiMsgCitation.Destroy;
begin
  // Free the list of sources. Thanks to AOwnsObjects=True,
  // all TAiCitationSource objects in the list will be automatically destroyed.
  Sources.Free;
  inherited Destroy;
end;

{ TAiMsgCitations }

procedure TAiMsgCitations.Assign(Source: TAiMsgCitations);
var
  SourceCitation: TAiMsgCitation;
  NewCitation: TAiMsgCitation;
begin
  // 1. Avoid self-assignment
  if Source = Self then
    Exit;

  // 2. Clear the destination list. Since TObjectList is the owner,
  // this will free any TAiMsgCitation objects that already exist.
  Self.Clear;

  // 3. If the source is nil, there is nothing to do.
  if not Assigned(Source) then
    Exit;

  // 4. Iterate over the source list
  for SourceCitation in Source do
  begin
    // 5. Create a new instance of the destination object
    NewCitation := TAiMsgCitation.Create;
    try
      // 6. Use the Assign method of the individual object to copy the data (deep copy)
      NewCitation.Assign(SourceCitation);
      // 7. Add the newly cloned object to our list (Self)
      Self.Add(NewCitation);
    except
      // In case of an error, ensure that the object we just created is freed
      NewCitation.Free;
      raise;
    end;
  end;
end;

{ TAiToolFunction }

procedure TAiToolsFunction.Assign(aSource: TAiToolsFunction);
begin
  Self.id := aSource.id;
  Self.&Type := aSource.&Type;
  Self.name := aSource.name;
  Self.Description := aSource.Description;
  Self.Arguments := aSource.Arguments;
  Self.&Function := aSource.&Function;
  Self.Response := aSource.Response;
  Self.IsAsync := aSource.IsAsync;
  Metadata.JsonText := aSource.Metadata.JsonText;
end;

constructor TAiToolsFunction.Create;
begin
  inherited;
  Metadata := TAiMetadata.Create;
  MediaFiles := TAiMediaFiles.Create;
end;

destructor TAiToolsFunction.Destroy;
begin
  Metadata.Free;
  MediaFiles.Free;
  FParams.Free;
  inherited;
end;

function TAiToolsFunction.GetParams: TStringList;
var
  JObj: TJSONValue;
  JPair: TJSONPair;
begin
  if (FParams = nil) or (FParamsCachedArgs <> Arguments) then
  begin
    if FParams = nil then
      FParams := TStringList.Create;
    FParams.Clear;
    FParamsCachedArgs := Arguments;
    if Arguments <> '' then
    begin
      JObj := TJSONObject.ParseJSONValue(Arguments);
      if JObj is TJSONObject then
      try
        for JPair in TJSONObject(JObj) do
        begin
          if JPair.JsonValue is TJSONString then
            FParams.Values[JPair.JsonString.Value] := JPair.JsonValue.Value
          else
            FParams.Values[JPair.JsonString.Value] := JPair.JsonValue.ToString;
        end;
      finally
        JObj.Free;
      end;
    end;
  end;
  Result := FParams;
end;

procedure TAiToolsFunction.ParseFunction(JObj: TJSONObject);
Var
  JFunc: TJSONObject;
begin
  JFunc := JObj.GetValue<TJSONObject>('function');

  Name := JFunc.GetValue<String>('name');
  Self.Description := JFunc.GetValue<String>('description');
  &Function := JFunc.Format;
end;

{ TAitools_outputs }

procedure TAiToolsFunctions.AddFunction(aBody: TJSONObject);
Var
  Func, Func1: TAiToolsFunction;
begin
  Func := TAiToolsFunction.Create;
  Func.ParseFunction(aBody);

  If Self.TryGetValue(Func.name, Func1) = False then
    Self.Add(Func.name, Func)
  Else
  Begin
    Func1.Assign(Func);
    Func.Free;
  End;
end;

procedure TAiToolsFunctions.ValueNotify(const Value: TAiToolsFunction; Action: TCollectionNotification);
begin
  case Action of
    cnDeleting, cnRemoved:
      Value.Free;
  end;
  inherited;
end;

procedure TAiToolsFunctions.AddFunction(aBody: String);
Var
  Func: TJSONObject;
begin
  Func := TJSONObject(TJSONObject.ParseJSONValue(aBody));
  AddFunction(Func);
end;

function TAiToolsFunctions.ToFunctionsJSon: TJSonArray;
Var
  Clave: String;
  TObj: TJSONObject;
  Func: TAiToolsFunction;
begin
  Result := TJSonArray.Create;

  For Clave in Self.Keys do
  Begin
    Func := Self.Items[Clave];
    TObj := TJSONObject.Create;
    TObj.AddPair('type', 'function');
    TObj.AddPair('function', TJSONObject(TJSONObject.ParseJSONValue(Func.&Function)));
    Result.Add(TObj);
  End;
end;

function TAiToolsFunctions.ToOutputJSon: TJSonArray;
Var
  Clave: String;
  TObj: TJSONObject;
begin
  Result := TJSonArray.Create;

  For Clave in Self.Keys do // The key is the function name
  Begin
    TObj := TJSONObject.Create;
    TObj.AddPair('tool_call_id', Self.Items[Clave].id);
    TObj.AddPair('output', Self.Items[Clave].Response);
    Result.Add(TObj);
  End;
end;

end.
