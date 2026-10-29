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
// Nombre: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: +57 3128441700
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


// -----------------------------------------------------------------------------
// CITATIONS (RAG Nativo) - Estado de implementation
// -----------------------------------------------------------------------------
// 1. Core: TAiMediaFile.EnableCitations, Title, Context  [COMPLETED]
// 2. Core: TAiMsgCitation, TAiMsgCitations in TAiChatMessage  [COMPLETED]
// 3. Claude.GetMessages: Inject "citations": {"enabled": true}  [COMPLETED]
// 4. Claude.ProcessStreamChunk: Capture citations_delta  [WAS ALREADY WORKING]
// 5. Claude.ParseChat: Parse char_location, page_location, etc.  [COMPLETED]
// Ref: https://docs.anthropic.com/en/docs/build-with-claude/citations
// -----------------------------------------------------------------------------
// ------ Tools that will not be implemented for now --------------------
// 1. https://platform.claude.com/docs/es/agents-and-tools/tool-use/code-execution-tool
// 2. https://platform.claude.com/docs/es/agents-and-tools/tool-use/fine-grained-tool-streaming
// 3.




// https://platform.claude.com/docs/en/intro
//https://platform.claude.com/docs/en/api/beta/messages/create  //api of the last implementation {/beta/}

unit uMakerAi.Chat.Claude;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Threading, System.Variants, System.Net.Mime, System.IOUtils,
  System.Generics.Collections, System.NetEncoding, System.JSON,
  System.StrUtils, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent, REST.JSON, REST.Types, REST.Client,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.ParamsRegistry, uMakerAi.Chat, uMakerAi.Tools.Functions, uMakerAi.Core,
  uMakerAi.Utils.CodeExtractor, uMakerAi.Chat.Messages;

type

  // --- Classes for Context management (Context Editing) ---

  TClaudeContextTrigger = class
  public
    TriggerType: string; // By default 'input_tokens'
    Value: Integer;
    constructor Create(aValue: Integer; aType: string = 'input_tokens');
  end;

  TClaudeContextEdit = class
  public
    EditType: string; // 'clear_tool_uses_20250919'
    Trigger: TClaudeContextTrigger;
    Keep_ToolUses: Integer;
    ClearAtLeast_InputTokens: Integer;
    constructor Create;
    destructor Destroy; override;
    function ToJSONObject: TJSONObject;
  end;

  TClaudeContextConfig = class
  private
    FEdits: TObjectList<TClaudeContextEdit>;
  public
    constructor Create;
    destructor Destroy; override;
    // Adds a rule to clean tools when X tokens are reached
    procedure AddRule_ClearTools(TriggerTokens: Integer; KeepCount: Integer = 0; ClearAtLeast: Integer = 0);
    function ToJSONObject: TJSONObject;
    function IsEmpty: Boolean;
    procedure Clear;
  end;

  // --- Helper class to process blocks in Streaming ---

  TClaudeStreamContentBlock = class
  public
    BlockType: string; // 'text', 'tool_use', 'thinking', 'redacted_thinking'
    TextContent: TStringBuilder;
    JsonContent: TStringBuilder; // To accumulate partial JSON arguments
    ToolFunction: TAiToolsFunction;
    Signature: TStringBuilder;
    CitationsBuffer: TJSonArray;
    ExtraData: TJSONObject;
    constructor Create;
    destructor Destroy; override;
  end;



  // --- Main Chat Claude Class ---

  TAiClaudeChat = Class(TAiChat)
  Private
    FStreamResponseMsg: TAiChatMessage;
    FStreamContentBlocks: TDictionary<Integer, TClaudeStreamContentBlock>;
    FStreamBuffer: TStringBuilder;
    FStreamLastEventType: string;

    // New features
    FEnableMemory: Boolean;
    FEnableThinking: Boolean;
    FThinkingBudget: Integer;
    FContextConfig: TClaudeContextConfig;
    FCacheSystemPrompt: Boolean;
    FServiceTier: String;

    function GetToolJson(aToolFormat: TToolFormat): TJSonArray;
    function GetDynamicHeaders: TNetHeaders; // Construye headers Beta dynamicmente
    function GetFileHeaders: TNetHeaders;
    procedure ClearStreamState;
    procedure ProcessStreamChunk(const AChunk: string);

    procedure SetEnableMemory(const Value: Boolean);
    procedure SetEnableThinking(const Value: Boolean);
    procedure SetThinkingBudget(const Value: Integer);

  Protected
    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Override;
    Function InternalAddMessage(aMsg: TAiChatMessage): TAiChatMessage; Overload; Override;

    Function InitChatCompletions: String; Override;
    Procedure ParseChat(jObj: TJSONObject; ResMsg: TAiChatMessage); Override;
    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Override;

    Function ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions; Override;
    procedure DoCallFunction(ToolCall: TAiToolsFunction); Override;

    function ExtractToolCallJson(jChoices: TJSonArray): TJSonArray;

  Public
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;

    Class Function GetModels(aApiKey: String; aUrl: String = ''): TStringList; Override;
    Function GetMessages: TJSonArray; Override;

    // --- File Management (File API) ---
    Function UploadFile(aMediaFile: TAiMediaFile): String; Override;
    Function DownLoadFile(aMediaFile: TAiMediaFile): String; Override;
    Function CheckFileState(aMediaFile: TAiMediaFile): String; Override;
    Function DeleteFile(aMediaFile: TAiMediaFile): String; Override;
    function RetrieveFile(aFileId: string): TAiMediaFile; Override;
    function RetrieveFileList: TAiMediaFiles; Override;
    Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer = 3600): String; Override;
    function CreateMessageBatch(InputFileId: string): string; // Allows processing uploaded files

    class function GetDriverName: string; Override;
    class procedure RegisterDefaultParams(Params: TStrings); Override;
    class function CreateInstance(Sender: TComponent): TAiChat; Override;

    // easy method to configure automatic context cleanup
    // TriggerTokens: Starting from how many input tokens cleanup is activated (e.g. 20000)
    // KeepLast: How many recent tool interactions to keep (e.g. 3)
    procedure ConfigureAutoContextClearing(TriggerTokens: Integer; KeepLast: Integer = 3);

    // Access to context configuration
    property ContextConfig: TClaudeContextConfig read FContextConfig;

    // Allows caching the System Prompt to save costs on long instructions
    property CacheSystemPrompt: Boolean read FCacheSystemPrompt write FCacheSystemPrompt;

  Published
    property EnableMemory: Boolean read FEnableMemory write SetEnableMemory default False;
    property EnableThinking: Boolean read FEnableThinking write SetEnableThinking default False;
    property ThinkingBudget: Integer read FThinkingBudget write SetThinkingBudget default 1024;
    Property ServiceTier: String read FServiceTier write FServiceTier;
  End;

procedure Register;

implementation

Const
  GlAIUrl = 'https://api.anthropic.com/v1/';
  CLAUDE_API_VERSION = '2023-06-01';

  // Headers Beta (Constants)
  BETA_HDR_TOOLS = 'tools-2024-05-16';
  BETA_HDR_FILES = 'files-api-2025-04-14';
  BETA_HDR_MEMORY = 'context-management-2025-06-27';
  BETA_HDR_THINKING = 'interleaved-thinking-2025-05-14';
  BETA_HDR_CODE = 'code-execution-2025-08-25';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiClaudeChat]);
end;


// =============================================================================
// Context Management Helper Classes
// =============================================================================

constructor TClaudeContextTrigger.Create(aValue: Integer; aType: string);
begin
  Value := aValue;
  TriggerType := aType;
end;

constructor TClaudeContextEdit.Create;
begin
  EditType := 'clear_tool_uses_20250919';
  Trigger := nil;
  Keep_ToolUses := 0;
  ClearAtLeast_InputTokens := 0;
end;

destructor TClaudeContextEdit.Destroy;
begin
  Trigger.Free;
  inherited;
end;

function TClaudeContextEdit.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', EditType);

  if Assigned(Trigger) then
  begin
    var
    jTrigger := TJSONObject.Create;
    jTrigger.AddPair('type', Trigger.TriggerType);
    jTrigger.AddPair('value', TJSONNumber.Create(Trigger.Value));
    Result.AddPair('trigger', jTrigger);
  end;

  if Keep_ToolUses > 0 then
  begin
    var
    jKeep := TJSONObject.Create;
    jKeep.AddPair('type', 'tool_uses');
    jKeep.AddPair('value', TJSONNumber.Create(Keep_ToolUses));
    Result.AddPair('keep', jKeep);
  end;

  if ClearAtLeast_InputTokens > 0 then
  begin
    var
    jClear := TJSONObject.Create;
    jClear.AddPair('type', 'input_tokens');
    jClear.AddPair('value', TJSONNumber.Create(ClearAtLeast_InputTokens));
    Result.AddPair('clear_at_least', jClear);
  end;
end;

procedure TClaudeContextConfig.Clear;
begin
  FEdits.Clear;
end;

constructor TClaudeContextConfig.Create;
begin
  FEdits := TObjectList<TClaudeContextEdit>.Create(True);
end;

destructor TClaudeContextConfig.Destroy;
begin
  FEdits.Free;
  inherited;
end;

procedure TClaudeContextConfig.AddRule_ClearTools(TriggerTokens: Integer; KeepCount: Integer; ClearAtLeast: Integer);
var
  Rule: TClaudeContextEdit;
begin
  Rule := TClaudeContextEdit.Create;
  Rule.Trigger := TClaudeContextTrigger.Create(TriggerTokens);
  Rule.Keep_ToolUses := KeepCount;
  Rule.ClearAtLeast_InputTokens := ClearAtLeast;
  FEdits.Add(Rule);
end;

function TClaudeContextConfig.IsEmpty: Boolean;
begin
  Result := FEdits.Count = 0;
end;

function TClaudeContextConfig.ToJSONObject: TJSONObject;
var
  jArr: TJSonArray;
  Edit: TClaudeContextEdit;
begin
  if IsEmpty then
    Exit(nil);

  Result := TJSONObject.Create;
  jArr := TJSonArray.Create;
  for Edit in FEdits do
    jArr.Add(Edit.ToJSONObject);

  Result.AddPair('edits', jArr);
end;

// =============================================================================
// Streaming Helper Classes
// =============================================================================

constructor TClaudeStreamContentBlock.Create;
begin
  TextContent := TStringBuilder.Create;
  JsonContent := TStringBuilder.Create;
  Signature := TStringBuilder.Create;
  CitationsBuffer := TJSonArray.Create;
  ExtraData := TJSONObject.Create;
  ToolFunction := nil;
end;

destructor TClaudeStreamContentBlock.Destroy;
begin
  TextContent.Free;
  JsonContent.Free;
  ToolFunction.Free;
  Signature.Free;
  CitationsBuffer.Free;
  ExtraData.Free;
  inherited;
end;


// =============================================================================
// TAiClaudeChat Implementation
// =============================================================================

class function TAiClaudeChat.GetDriverName: string;
Begin
  Result := 'Claude';
End;

class procedure TAiClaudeChat.RegisterDefaultParams(Params: TStrings);
Begin
  Params.Clear;
  Params.Add('ApiKey=@CLAUDE_API_KEY');
  Params.Add('Model=claude-sonnet-4-5-20250514');
  Params.Add('MaxTokens=4096');
  Params.Add('URL=https://api.anthropic.com/v1/');
End;

class function TAiClaudeChat.CreateInstance(Sender: TComponent): TAiChat;
Begin
  Result := TAiClaudeChat.Create(Sender);
End;

function TAiClaudeChat.CreateMessageBatch(InputFileId: string): string;
var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  ReqStream: TStringStream;
  Res: IHTTPResponse;
  jReq, jRes: TJSONObject;
begin
  if InputFileId.IsEmpty then
    raise Exception.Create('InputFileId is required');

  Client := TNetHTTPClient.Create(Nil);
  try
    // Specific headers for Batches
    Headers := [TNetHeader.Create('x-api-key', ApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('anthropic-beta', 'message-batches-2024-09-24'), // Mandatory header for Batches
    TNetHeader.Create('content-type', 'application/json')];

    // Build the body
    jReq := TJSONObject.Create;
    try
      jReq.AddPair('input_file_id', InputFileId);
      jReq.AddPair('endpoint', '/v1/messages');

      ReqStream := TStringStream.Create(jReq.ToJSON, TEncoding.UTF8);
    finally
      jReq.Free;
    end;

    try
      Res := Client.Post(Url + 'messages/batches', ReqStream, nil, Headers);

      if Res.StatusCode = 200 then
      begin
        jRes := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
        try
          Result := jRes.GetValue<string>('id'); // Save this ID to check status later
        finally
          jRes.Free;
        end;
      end
      else
        raise Exception.CreateFmt('Error creating Batch: %d - %s', [Res.StatusCode, Res.ContentAsString]);
    finally
      ReqStream.Free;
    end;
  finally
    Client.Free;
  end;
end;

constructor TAiClaudeChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '@CLAUDE_API_KEY';
  FClient.OnReceiveData := Self.OnInternalReceiveData;
  ResponseTimeOut := 300000; // code_execution server-side can take >60s without sending bytes

  FStreamContentBlocks := TDictionary<Integer, TClaudeStreamContentBlock>.Create;
  FStreamBuffer := TStringBuilder.Create;
  FStreamResponseMsg := nil;
  FContextConfig := TClaudeContextConfig.Create;

  // Default values
  Model := 'claude-sonnet-4-5-20250514';
  Max_tokens := 4096;
  Url := GlAIUrl;
  FEnableMemory := False;
  FEnableThinking := False;
  FThinkingBudget := 1024;

  FCacheSystemPrompt := False;

end;

destructor TAiClaudeChat.Destroy;
begin
  ClearStreamState;
  FStreamContentBlocks.Free;
  FStreamBuffer.Free;
  FContextConfig.Free;
  inherited;
end;

// --- Property Setters ---

procedure TAiClaudeChat.SetEnableMemory(const Value: Boolean);
begin
  FEnableMemory := Value;
  if Value then
    ModelConfig.ModelCaps := ModelConfig.ModelCaps + [cap_Memory]
  else
    ModelConfig.ModelCaps := ModelConfig.ModelCaps - [cap_Memory];
end;

procedure TAiClaudeChat.SetEnableThinking(const Value: Boolean);
begin
  FEnableThinking := Value;
end;

procedure TAiClaudeChat.SetThinkingBudget(const Value: Integer);
begin
  FThinkingBudget := Value;
end;

// --- Header Generation ---

function TAiClaudeChat.GetDynamicHeaders: TNetHeaders;
var
  BetaFeatures: TList<string>;
  HeaderVal: string;
begin
  // 1. Base Headers (IMPORTANT: The version must be 2023-06-01 so that the betas work on top)
  Result := [
    TNetHeader.Create('x-api-key', ApiKey),
    TNetHeader.Create('anthropic-version', '2023-06-01'),
    TNetHeader.Create('content-type', 'application/json')
  ];

  BetaFeatures := TList<string>.Create;
  try
    // -------------------------------------------------------------------------
    // ACTIVATION OF BETAS (HEADERS) - critical TO AVOID ERROR "EXTRA INPUTS"
    // -------------------------------------------------------------------------

    // 1. MANDATORY: Enable modern tools (structured output base)
    // According to your doc, this is the most recent version for tools
    BetaFeatures.Add('token-efficient-tools-2025-02-19');

    // 2. MANDATORY: Enable extended Output capabilities
    // It is very likely that 'output_format' depends on this beta or the previous one
    BetaFeatures.Add('output-128k-2025-02-19');

    // 3. Files API (To upload files, images, pdfs as 'file_id')
    // We always enable it to avoid errors if a file is uploaded
    BetaFeatures.Add('files-api-2025-04-14');

    // 4. Memory & Context Management (Only if it is used, but it doesn't hurt to have it)
    if FEnableMemory or (not FContextConfig.IsEmpty) then
      BetaFeatures.Add('context-management-2025-06-27');

    // 5. Code Execution (If enabled in ChatMediaSupports)
    if cap_CodeInterpreter in ModelConfig.ModelCaps then
      BetaFeatures.Add('code-execution-2025-08-25');

    // 6. Thinking / Reasoning (If enabled)
    if FEnableThinking or (ModelConfig.ThinkingLevel <> tlDefault) then
      BetaFeatures.Add('interleaved-thinking-2025-05-14');

    // 7. Prompt Caching
    if FCacheSystemPrompt then
      BetaFeatures.Add('prompt-caching-2024-07-31');

    // 8. Computer Use
    if cap_ComputerUse in ModelConfig.ModelCaps then
      BetaFeatures.Add('computer-use-2025-01-24');

    // -------------------------------------------------------------------------
    // BUILD HEADER
    // -------------------------------------------------------------------------
    if BetaFeatures.Count > 0 then
    begin
      // Join the betas separated by commas
      HeaderVal := string.Join(',', BetaFeatures.ToArray);
      Result := Result + [TNetHeader.Create('anthropic-beta', HeaderVal)];
    end;

  finally
    BetaFeatures.Free;
  end;
end;

function TAiClaudeChat.GetFileHeaders: TNetHeaders;
begin
  Result := [TNetHeader.Create('x-api-key', ApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('anthropic-beta', 'files-api-2025-04-14')];
end;


// --- Payload Construction ---

function TAiClaudeChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice: TJSONObject;
  jArrTools, jArrStop: TJSonArray;
  JTools: TJSONObject;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel: String;
  SystemPrompt: String;

  // Variables for message iteration (Auto-Upload)
  LMsg: TAiChatMessage;
  LMedia: TAiMediaFile;

  // Variables for new features (API 2025)
  jOutputConfig, jOutputFormat, jMetaData: TJSONObject;
  jSchemaParsed: TJSONValue;
begin
  // We inherit the User from the parent if not defined
  if User = '' then
    User := 'user';

  // ---------------------------------------------------------------------------
  // AUTO-UPLOAD: Automatic file upload to Files API
  // ---------------------------------------------------------------------------
  for LMsg in Self.Messages do
  begin
    // We are only interested in files that the user sends and that are not processed
    if (LMsg.Role = 'user') and (LMsg.MediaFiles.Count > 0) then
    begin
      for LMedia in LMsg.MediaFiles do
      begin
        // If the file still has no ID (has not been uploaded)
        if LMedia.IdFile.IsEmpty then
        begin
          // automatic upload condition:
          // 1. If Code Interpreter is active (needs file_id).
          // 2. OR IF the file is NOT PDF or Image (Excel, CSV, etc. force using Files API).
          if (cap_CodeInterpreter in ModelConfig.ModelCaps) or (not(LMedia.FileCategory in [Tfc_Image, Tfc_pdf])) then
          begin
            try
              // UploadFile automatically fills LMedia.IdFile
              UploadFile(LMedia);
            except
              // We allow continuing; if upload fails, the prompt may fail, but we don't block everything.
              on E: Exception do
                DoError('Auto-upload warning for ' + LMedia.FileName + ': ' + E.Message, E);
            end;
          end;
        end;
      end;
    end;
  end;
  // ---------------------------------------------------------------------------

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LModel = '' then
    LModel := 'claude-3-7-sonnet-20250219'; // Safe default if there is no model

  // ---------------------------------------------------------------------------
  // LOGIC: Thinking (Reasoning)
  // We synchronize the generic ThinkingLevel property with Claude's internal flag
  // ---------------------------------------------------------------------------
  if ModelConfig.ThinkingLevel <> tlDefault then
  begin
    FEnableThinking := True;
    // If we use thinking, we ensure sufficient max_tokens
    if Max_tokens < 4096 then
       Max_tokens := 8192;
    // Thinking forces temperature 1.0
    Self.Temperature := 1.0;
  end;

  LAsincronico := Self.Asynchronous;
  FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSONObject.Create;
  Lista := TStringList.Create;
  Try
    AJSONObject.AddPair('model', LModel);

    // -------------------------------------------------------------------------
    // SYSTEM PROMPT (with support for Prompt Caching)
    // -------------------------------------------------------------------------
    SystemPrompt := Self.PrepareSystemMsg;
    if SystemPrompt <> '' then
    begin
      // If system cache is active
      if FCacheSystemPrompt then
      begin
        var jSysArr := TJSonArray.Create;
        var jSysBlock := TJSONObject.Create;

        jSysBlock.AddPair('type', 'text');
        jSysBlock.AddPair('text', SystemPrompt);

        var jCache := TJSONObject.Create;
        jCache.AddPair('type', 'ephemeral');
        jSysBlock.AddPair('cache_control', jCache);

        jSysArr.Add(jSysBlock);
        AJSONObject.AddPair('system', jSysArr);
      end
      else
      begin
        // Standard format
        AJSONObject.AddPair('system', SystemPrompt);
      end;
    end;

    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));
    AJSONObject.AddPair('messages', GetMessages); // GetMessages manages the message content

    // =========================================================================
    // NEW FEATURES (API 2025)
    // =========================================================================

    // 1. JSON OUTPUT FORMAT / STRUCTURED OUTPUTS
    // Check if the inherited Response_format property indicates JSON or Schema
    //The API does not support it yet, it will be enabled when available in the API
    {
    if (Response_format in [tiaChatRfJson, tiaChatRfJsonSchema]) then
    begin
      jOutputFormat := TJSONObject.Create;
      jOutputFormat.AddPair('type', 'json_schema');

      // Try to read the schema from the inherited JsonSchema property (TStrings)
      if (JsonSchema.Text <> '') then
      begin
        try
          jSchemaParsed := TJSONObject.ParseJSONValue(JsonSchema.Text);
          if Assigned(jSchemaParsed) and (jSchemaParsed is TJSONObject) then
            jOutputFormat.AddPair('schema', jSchemaParsed as TJSONObject)
          else
          begin
            if Assigned(jSchemaParsed) then jSchemaParsed.Free;
            // Fallback schema
            var jGen := TJSONObject.Create;
            jGen.AddPair('type', 'object');
            jOutputFormat.AddPair('schema', jGen);
          end;
        except
           // Fallback on parsing error
           var jGen := TJSONObject.Create;
           jGen.AddPair('type', 'object');
           jOutputFormat.AddPair('schema', jGen);
        end;
      end
      else
      begin
        // If JSON is requested but no schema is defined, we send generic Object
        var jGen := TJSONObject.Create;
        jGen.AddPair('type', 'object');
        jOutputFormat.AddPair('schema', jGen);
      end;

      AJSONObject.AddPair('output_format', jOutputFormat);
    end;
    }

    // 2. OUTPUT CONFIG (Reasoning Effort)
    // Maps the inherited ThinkingLevel property to Claude's new standard
    if (ModelConfig.ThinkingLevel <> tlDefault) then
    begin
      jOutputConfig := TJSONObject.Create;
      case ModelConfig.ThinkingLevel of
        tlLow:    jOutputConfig.AddPair('effort', 'low');
        tlMedium: jOutputConfig.AddPair('effort', 'medium');
        tlHigh:   jOutputConfig.AddPair('effort', 'high');
      end;
      AJSONObject.AddPair('output_config', jOutputConfig);
    end;

    // 3. SERVICE TIER (New property of TAiClaudeChat)
    if (FServiceTier <> '') then
      AJSONObject.AddPair('service_tier', FServiceTier);

    // 4. METADATA (User ID)
    // Maps the inherited User property to metadata.user_id
    if (Self.User <> '') and (Self.User <> 'user') then
    begin
      jMetaData := TJSONObject.Create;
      jMetaData.AddPair('user_id', Self.User);
      AJSONObject.AddPair('metadata', jMetaData);
    end;

    // =========================================================================
    // SPECIFIC AND LEGACY CONFIGURATIONS
    // =========================================================================

    // Thinking (Manual Budget Mode)
    // We only add it if OutputConfig (ThinkingLevel) is NOT used, to avoid conflict.
    if (FEnableThinking) and (ModelConfig.ThinkingLevel = tlDefault) then
    begin
      var jThink := TJSONObject.Create;
      jThink.AddPair('type', 'enabled');
      jThink.AddPair('budget_tokens', TJSONNumber.Create(FThinkingBudget));
      AJSONObject.AddPair('thinking', jThink);
    end;

    // Context Management (Garbage Collection)
    if not FContextConfig.IsEmpty then
    begin
      var jContext := FContextConfig.ToJSONObject;
      if Assigned(jContext) then
        AJSONObject.AddPair('context_management', jContext);
    end;

    // -------------------------------------------------------------------------
    // TOOLS CONSTRUCTION
    // -------------------------------------------------------------------------
    jArrTools := TJSonArray.Create;

    // 1. User Defined Tools (From the component's Tools property)
    if Tool_Active and (Trim(GetTools(TToolFormat.tfClaude).Text) <> '') then
    begin
      var jUserTools := GetToolJson(TToolFormat.tfClaude);
      if Assigned(jUserTools) then
      begin
        for var Val in jUserTools do
          jArrTools.Add(Val.Clone as TJSONObject);
      end;
    end;

    // 2. Native: Web Search
    if cap_WebSearch in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'web_search_20250305');
      JTools.AddPair('name', 'web_search');
      // Additional options if they exist in WebSearchParams
      jArrTools.Add(JTools);
    end;

    // 3. Native: Code Execution
    if cap_CodeInterpreter in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'code_execution_20250825');
      JTools.AddPair('name', 'code_execution');
      jArrTools.Add(JTools);
    end;

    // 4. Native: Memory
    if FEnableMemory then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'memory_20250818');
      JTools.AddPair('name', 'memory');
      jArrTools.Add(JTools);
    end;

    // 5. Native: Text Editor
    if cap_TextEditor in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'text_editor_20250728');
      JTools.AddPair('name', 'str_replace_based_edit_tool');
      jArrTools.Add(JTools);
    end;

    // 6. Native: Computer Use
    if cap_ComputerUse in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'computer_20241022');
      JTools.AddPair('name', 'computer');
      // Default values required by the API
      JTools.AddPair('display_width_px', TJSONNumber.Create(1024));
      JTools.AddPair('display_height_px', TJSONNumber.Create(768));
      jArrTools.Add(JTools);
    end;

    // 7. Native: Bash / Shell
    if cap_Shell in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'bash_20250124');
      JTools.AddPair('name', 'bash');
      jArrTools.Add(JTools);
    end;

    // Inject tools into the main JSON
    if jArrTools.Count > 0 then
    begin
      AJSONObject.AddPair('tools', jArrTools);

      // Tool Choice (Auto, Any, Tool)
      if (Trim(Tool_choice) <> '') then
      begin
        try
          jToolChoice := TJSONObject.ParseJSONValue(Tool_choice) as TJSONObject;
          if Assigned(jToolChoice) then
            AJSONObject.AddPair('tool_choice', TJSONObject(jToolChoice.Clone));
        except
          // If it is a simple string like 'auto' or 'any'
          // Claude requires an object for 'any' or 'tool', but 'auto' is implicit default.
          // Here we try to adapt it, but ideally Tool_choice should already be a valid JSON string for Claude.
          if (Tool_choice = 'auto') or (Tool_choice = 'any') then
          begin
             var jSimpleChoice := TJSONObject.Create;
             jSimpleChoice.AddPair('type', Tool_choice);
             AJSONObject.AddPair('tool_choice', jSimpleChoice);
          end
          else
             AJSONObject.AddPair('tool_choice', Tool_choice);
        end;
      end;
    end
    else
      jArrTools.Free;

    // -------------------------------------------------------------------------
    // STANDARD PARAMETERS
    // -------------------------------------------------------------------------

    // Temperature: Thinking requires 1.0 (or null).
    if not FEnableThinking then
    begin
      // We only send temperature if it was modified from default (usually 0 or 1)
      if Self.Temperature <> 0 then
        AJSONObject.AddPair('temperature', TJSONNumber.Create(Self.Temperature));
    end
    else
      AJSONObject.AddPair('temperature', TJSONNumber.Create(1.0));

    // Top P (Generally incompatible with Thinking)
    //if not FEnableThinking then
    //  if Top_p <> 0 then
    //    AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

    // Stop Sequences
    Lista.CommaText := Stop;
    if Lista.Count > 0 then
    begin
      jArrStop := TJSonArray.Create;
      for I := 0 to Lista.Count - 1 do
        jArrStop.Add(Lista[I]);
      AJSONObject.AddPair('stop_sequences', jArrStop);
    end;

    // Stream
    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    // -------------------------------------------------------------------------
    // FINAL serialization
    // -------------------------------------------------------------------------
    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]); // Escape cleanup
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);

  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;



// --- Request Execution ---

Function TAiClaudeChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
Var
  ABody: String;
  sUrl: String;
  Res: IHTTPResponse;
  St: TStringStream;
  FHeaders: TNetHeaders;
  jObj: TJSONObject;
begin
  FBusy := True;
  FAbort := False;
  FLastError := '';
  FLastContent := '';
  FLastPrompt := '';
  ClearStreamState;

  sUrl := Url + 'messages';

  try
    DoStateChange(acsConnecting, 'Sending request...');

    FHeaders := GetDynamicHeaders;
    FClient.ContentType := 'application/json';
    FClient.Asynchronous := Self.Asynchronous;

    if FClient.Asynchronous then
      FStreamResponseMsg := TAiChatMessage.Create('', 'assistant');

    ABody := InitChatCompletions;

    LogDebug('-- Request body --');
    LogDebug(ABody);

    St := TStringStream.Create(ABody, TEncoding.UTF8);
    try
      St.Position := 0;
{$IFDEF APIDEBUG}
      St.SaveToFile('c:\temp\claude_req.json');
      St.Position := 0;
{$ENDIF}
      FResponse.Clear;

      Res := FClient.Post(sUrl, St, FResponse, FHeaders);

      if not FClient.Asynchronous then
      begin

        LogDebug('-- Response Sinchronous  --');
        LogDebug(Res.ContentAsString);

        if Res.StatusCode = 200 then
        begin
          jObj := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
          try
            ParseChat(jObj, ResMsg);
            Result := FLastContent;
          finally
            jObj.Free;
          end;
        end
        else
          raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end
      else
      begin
        Result := '';
      end;
    finally
      if not FClient.Asynchronous then
        St.Free;
    end;
  finally
    if not FClient.Asynchronous then
      FBusy := False;
  end;
End;

// --- Synchronous Response Parsing ---

procedure TAiClaudeChat.ParseChat(jObj: TJSONObject; ResMsg: TAiChatMessage);
Var
  choices: TJSonArray;
  jContentItem: TJSONObject;
  JVal: TJSONValue;
  uso: TJSONObject;
  aPrompt_tokens, aCompletion_tokens, aTotal_tokens: Integer;
  Role, Respuesta, StopR: String;
  LFunciones: TAiToolsFunctions;
  ToolCall: TAiToolsFunction;
  ToolMsg, AskMsg: TAiChatMessage;
  TaskList: array of ITask;
  I, NumTasks: Integer;
  Clave, sToolCalls, LModel, cType: String;
  code: TMarkdownCodeExtractor;
  CodeFiles: TCodeFileList;
  MF: TAiMediaFile;
  St: TStringStream;

  jCitationsArr: TJSonArray;
  jCitVal: TJSONValue;
  jCitObj: TJSONObject;
  SearchItem: TAiWebSearchItem;

  jInnerContent, jInnerItem: TJSONObject;
  jInnerArray: TJSonArray;
  NewFile: TAiMediaFile;

  ToolUseID, Cmd, FoundFileName: string;
  ScanItem: TJSONValue;
  ScanObj, InputObj: TJSONObject;
  CmdParts: TArray<string>;
begin
  AskMsg := GetLastMessage;

  // Parse Metadata
  // Id := jObj.GetValue('id').Value;
  LModel := jObj.GetValue('model').Value;
  Role := jObj.GetValue('role').Value;
  StopR := jObj.GetValue<string>('stop_reason', '');

  ResMsg.StopReason := StopR;
  if StopR = 'refusal' then
    ResMsg.IsRefusal := True;

  if jObj.TryGetValue<TJSONObject>('usage', uso) then
  begin
    // We use TryGetValue to avoid failures if the JSON number does not convert directly
    if not uso.TryGetValue<Integer>('input_tokens', aPrompt_tokens) then
      aPrompt_tokens := 0;

    if not uso.TryGetValue<Integer>('output_tokens', aCompletion_tokens) then
      aCompletion_tokens := 0;

    // Claude does NOT send 'total_tokens', we must add it manually
    aTotal_tokens := aPrompt_tokens + aCompletion_tokens;
  end
  else
  begin
    aPrompt_tokens := 0;
    aCompletion_tokens := 0;
    aTotal_tokens := 0;
  end;

  // 3. Accumulate in the component's GLOBAL properties (session statistics)
  Self.Prompt_tokens := Self.Prompt_tokens + aPrompt_tokens;
  Self.Completion_tokens := Self.Completion_tokens + aCompletion_tokens;
  Self.Total_tokens := Self.Total_tokens + aTotal_tokens;

  // 4. Assign to the RESPONSE MESSAGE (ResMsg)
  // This is crucial so that the returned message has the consumption info
  ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aPrompt_tokens;
  ResMsg.Completion_tokens := ResMsg.Completion_tokens + aCompletion_tokens;
  ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;

  // Parse Content (Interleaved)
  jObj.TryGetValue<TJSonArray>('content', choices);

  for JVal in choices do
  begin
    jContentItem := TJSONObject(JVal);
    cType := jContentItem.GetValue<string>('type');

    if cType = 'text' then
      Respuesta := Respuesta + jContentItem.GetValue<string>('text') + sLineBreak;

    if cType = 'thinking' then
    begin
      ResMsg.ReasoningContent := ResMsg.ReasoningContent + jContentItem.GetValue<string>('thinking');

      ResMsg.ThinkingSignature := jContentItem.GetValue<string>('signature');
    end;

    // C. Citations (search Web / RAG / Documents)
    if jContentItem.TryGetValue<TJSonArray>('citations', jCitationsArr) then
    begin
      for jCitVal in jCitationsArr do
      begin
        jCitObj := jCitVal as TJSONObject;
        var citType := jCitObj.GetValue<string>('type', '');

        // --- Document citations -> TAiMsgCitation ---
        if (citType = 'char_location') or (citType = 'page_location')
           or (citType = 'content_block_location') then
        begin
          var LCitation := TAiMsgCitation.Create;
          LCitation.Text := jCitObj.GetValue<string>('cited_text', '');

          var LSource := TAiCitationSource.Create;
          LSource.SourceType := cstDocument;
          LSource.DataSource.Title := jCitObj.GetValue<string>('document_title', '');
          LSource.DataSource.Id := jCitObj.GetValue<Integer>('document_index', 0).ToString;

          if citType = 'char_location' then
          begin
            LCitation.StartIndex := jCitObj.GetValue<Integer>('start_char_index', 0);
            LCitation.EndIndex := jCitObj.GetValue<Integer>('end_char_index', 0);
          end
          else if citType = 'page_location' then
          begin
            LCitation.StartIndex := jCitObj.GetValue<Integer>('start_page_number', 0);
            LCitation.EndIndex := jCitObj.GetValue<Integer>('end_page_number', 0);
          end
          else if citType = 'content_block_location' then
          begin
            LCitation.StartIndex := jCitObj.GetValue<Integer>('start_block_index', 0);
            LCitation.EndIndex := jCitObj.GetValue<Integer>('end_block_index', 0);
          end;

          LCitation.Sources.Add(LSource);
          ResMsg.Citations.Add(LCitation);
        end

        // --- Web citations (existing compatibility) ---
        else if citType = 'web_search_result_location' then
        begin
          if not Assigned(ResMsg.WebSearchResponse) then
            ResMsg.WebSearchResponse := TAiWebSearch.Create;

          SearchItem := TAiWebSearchItem.Create;
          SearchItem.&type := 'web_search_result_location';
          SearchItem.Title := jCitObj.GetValue<string>('title', '');
          SearchItem.Url := jCitObj.GetValue<string>('url', '');
          ResMsg.WebSearchResponse.annotations.Add(SearchItem);

          // also add to Citations for unification
          var LCitation := TAiMsgCitation.Create;
          LCitation.Text := jCitObj.GetValue<string>('cited_text', '');
          var LSource := TAiCitationSource.Create;
          LSource.SourceType := cstWeb;
          LSource.DataSource.Title := jCitObj.GetValue<string>('title', '');
          LSource.DataSource.Url := jCitObj.GetValue<string>('url', '');
          LCitation.Sources.Add(LSource);
          ResMsg.Citations.Add(LCitation);
        end;
      end;
    end;

    if ContainsText(cType, 'tool_result') or ContainsText(cType, 'code_execution') then
    begin
      // Navigate the deep structure to find the file_id
      if jContentItem.TryGetValue<TJSONObject>('content', jInnerContent) then
      begin
        if jInnerContent.TryGetValue<TJSonArray>('content', jInnerArray) then
        begin
          for var valInner in jInnerArray do
          begin
            jInnerItem := valInner as TJSONObject;

            // we found a file_id?
            if jInnerItem.TryGetValue<string>('file_id', Clave) then
            begin
              // --- INTELLIGENT NAME RETRIEVAL ---
              FoundFileName := 'generated_file_' + Copy(Clave, 1, 8); // Temporary name

              // 1. We get the ID of the tool that generated this result
              ToolUseID := jContentItem.GetValue<string>('tool_use_id', '');

              if ToolUseID <> '' then
              begin
                // 2. We search the entire content array for the original command
                // Note: 'choices' is the TJSONArray we are iterating
                for ScanItem in choices do
                begin
                  ScanObj := ScanItem as TJSONObject;
                  // ID match and that it is a tool_use

                  Var
                    sId: String;
                  If ScanObj.TryGetValue<string>('id', sId) and (sId = ToolUseID) then
                  Begin
                    Var
                      sIdType: String;
                    If ScanObj.TryGetValue<string>('type', sIdType) and (sIdType = 'server_tool_use') then
                    begin
                      if ScanObj.TryGetValue<TJSONObject>('input', InputObj) then
                      begin
                        Cmd := InputObj.GetValue<string>('command', '');
                        // The standard pattern is: cp /path/name.ext $OUTPUT_DIR/
                        if Cmd.StartsWith('cp ') then
                        begin

                          // Simple parsing by spaces
                          CmdParts := Cmd.Split([' ']);
                          if Length(CmdParts) >= 2 then
                          begin
                            // CmdParts[1] should be "/tmp/frecuencia_333hz.wav"
                            // We use ExtractFileName (System.SysUtils)

                            Var
                            sPath := CmdParts[1];
{$IFDEF MSWINDOWS}
                            sPath := StringReplace(sPath, '/', '\', [rfReplaceAll]);
{$ENDIF}
                            FoundFileName := ExtractFileName(sPath);
                          end;

                        end;
                      end;
                      Break; // We found the parent, we exit the scan
                    end;
                  End;

                end;
              end;
              // -------------------------------------------

              NewFile := TAiMediaFile.Create;
              NewFile.IdFile := Clave; // file_011CV...
              // NewFile.FileCategory := Tfc_Document;
              NewFile.FileName := FoundFileName; // ?Correct name assigned!

              DownLoadFile(NewFile);

              ResMsg.MediaFiles.Add(NewFile);
            end;
          end;
        end;
      end;
    end;

  end;

  Respuesta := Trim(Respuesta);

  // Parse Tools
  Var
  JToolCallArray := ExtractToolCallJson(choices);
  if JToolCallArray.Count > 0 then
    sToolCalls := JToolCallArray.Format;
  JToolCallArray.Free;

  LFunciones := ExtractToolCallFromJson(choices);

  // Update ResMsg
  Self.FLastContent := Respuesta;
  Prompt_tokens := Prompt_tokens + aPrompt_tokens;
  Completion_tokens := Completion_tokens + aCompletion_tokens;
  Total_tokens := Total_tokens + aTotal_tokens;

  if sToolCalls.IsEmpty then
  begin
    ResMsg.Role := Role;
    ResMsg.Model := LModel;
    ResMsg.Tool_calls := sToolCalls;
    ResMsg.Prompt := ResMsg.Prompt + Respuesta;
    // (Metrics updates)
    DoProcessResponse(AskMsg, ResMsg, Respuesta);
  end
  else
  begin
    Var
    Msg := TAiChatMessage.Create(Respuesta, Role);
    Msg.Tool_calls := sToolCalls;
    Msg.ReasoningContent := ResMsg.ReasoningContent; // Preserve thinking
    Msg.ThinkingSignature := ResMsg.ThinkingSignature;
    Msg.Id := FMessages.Count + 1;
    FMessages.Add(Msg);
  end;

  try
    if LFunciones.Count > 0 then
    begin
      NumTasks := LFunciones.Count;
      SetLength(TaskList, NumTasks);
      I := 0;
      for Clave in LFunciones.Keys do
      begin
        ToolCall := LFunciones[Clave];
        ToolCall.ResMsg := ResMsg;
        ToolCall.AskMsg := AskMsg;
        TaskList[I] := TTask.Create(
          procedure
          begin
            DoCallFunction(ToolCall);
          end);
        TaskList[I].Start;
        Inc(I);
      end;
      TTask.WaitForAll(TaskList);

      for Clave in LFunciones.Keys do
      begin
        ToolCall := LFunciones[Clave];
        ToolMsg := TAiChatMessage.Create(ToolCall.Response, 'user', ToolCall.Id, ToolCall.Name);
        ToolMsg.Id := FMessages.Count + 1;
        FMessages.Add(ToolMsg);
      end;
      Self.Run(Nil, ResMsg);
    end
    else
    begin
      if cap_ExtractCode in ModelConfig.SessionCaps then
      begin
        code := TMarkdownCodeExtractor.Create;
        try
          CodeFiles := code.ExtractCodeFiles(Respuesta);
          for var CodeFile in CodeFiles do
          begin
            St := TStringStream.Create(CodeFile.code);
            try
              St.Position := 0;
              MF := TAiMediaFile.Create;
              MF.LoadFromStream('file.' + CodeFile.FileType, St);
              ResMsg.MediaFiles.Add(MF);
            finally
              St.Free;
            end;
          end;
        finally
          code.Free;
        end;
      end;

      DoProcessResponse(AskMsg, ResMsg, Respuesta);
      ResMsg.Prompt := Respuesta;
      FBusy := False;
      DoStateChange(acsFinished, 'Done'); // <--- FINISHED STATE
      if Assigned(FOnReceiveDataEnd) then
        FOnReceiveDataEnd(Self, ResMsg, jObj, Role, Respuesta);
    end;
  finally
    LFunciones.Free;
  end;
end;

// --- Streaming Parser (Async) ---

procedure TAiClaudeChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
var
  line: string;
begin

  if not FClient.Asynchronous then
    Exit;

  LogDebug('-- OnInternalReceiveData--');
  LogDebug(FResponse.DataString);


  AAbort := FAbort;
  if FAbort then
  begin
    FBusy := False;
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, nil, nil, 'system', 'abort');
    ClearStreamState;
    Exit;
  end;

  FStreamBuffer.Append(UTF8Encode(FResponse.DataString));
  FResponse.Clear;

  var
  bufferContent := FStreamBuffer.ToString;
  var
  lastLF := LastDelimiter(#10, bufferContent);

  if lastLF > 0 then
  begin
    var
    processableContent := Copy(bufferContent, 1, lastLF);
    FStreamBuffer.Remove(0, lastLF);

    for line in processableContent.Split([#10]) do
    begin
      var
      line1 := Trim(line);
      if not line1.IsEmpty then
        ProcessStreamChunk(line1);
    end;
  end;
end;

procedure TAiClaudeChat.ProcessStreamChunk(const AChunk: string);
var
  jData, jDelta, jBlock, jMessage: TJSONObject;
  eventType, textDelta, jsonDelta, StopReason: string;
  blockIndex: Integer;
  streamBlock: TClaudeStreamContentBlock;
begin
  // 1. Process event line (event: ...)
  if AChunk.StartsWith('event:') then
  begin
    FStreamLastEventType := Trim(Copy(AChunk, 7, Length(AChunk)));
    Exit;
  end;

  // 2. Process data line (data: ...)
  if AChunk.StartsWith('data:') then
  begin
    if FStreamLastEventType = '' then
      Exit;

    var
    jsonDataStr := Trim(Copy(AChunk, 6, Length(AChunk)));
    if jsonDataStr.IsEmpty then
      Exit;

    jData := TJSONObject.ParseJSONValue(jsonDataStr) as TJSONObject;
    if not Assigned(jData) then
      Exit;

    try
      eventType := jData.GetValue<string>('type');

      // =======================================================================
      // EVENT: message_start
      // Start of a new assistant message
      // =======================================================================
      If AnsiLowerCase(eventType) = 'message_start' then
      begin
        if Assigned(FStreamResponseMsg) then
        begin
          jMessage := jData.GetValue<TJSONObject>('message');
          FStreamResponseMsg.ToolCallId := jMessage.GetValue<string>('id'); // Claude message ID
          FStreamResponseMsg.Model := jMessage.GetValue<string>('model');
          FStreamResponseMsg.Role := jMessage.GetValue<string>('role');

          // Notify reception start
          if Assigned(OnReceiveData) then
            OnReceiveData(Self, FStreamResponseMsg, jData, 'assistant', '');
        end;
      end

      // =======================================================================
      // EVENT: content_block_start
      // Start of a block (Text, Tool Use, Thinking)
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'content_block_start' then
      begin
        blockIndex := jData.GetValue<Integer>('index');
        jBlock := jData.GetValue<TJSONObject>('content_block');

        streamBlock := TClaudeStreamContentBlock.Create;
        streamBlock.BlockType := jBlock.GetValue<string>('type');

        for var Pair in jBlock do
        begin
          // We avoid duplicating 'type' which we already saved
          if Pair.JsonString.Value <> 'type' then
            streamBlock.ExtraData.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
        end;

        // If it is a tool, we initialize the structure
        if streamBlock.BlockType = 'tool_use' then
        begin
          streamBlock.ToolFunction := TAiToolsFunction.Create;
          streamBlock.ToolFunction.Id := jBlock.GetValue<string>('id');
          streamBlock.ToolFunction.Name := jBlock.GetValue<string>('name');
          streamBlock.ToolFunction.&Type := 'function';
        end;

        FStreamContentBlocks.Add(blockIndex, streamBlock);
      end

      // =======================================================================
      // EVENT: content_block_delta
      // Incremental data for an existing block
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'content_block_delta' then
      begin
        blockIndex := jData.GetValue<Integer>('index');
        if FStreamContentBlocks.TryGetValue(blockIndex, streamBlock) then
        begin
          jDelta := jData.GetValue<TJSONObject>('delta');
          var
          deltaType := jDelta.GetValue<string>('type');

          // Text Delta
          if deltaType = 'text_delta' then
          begin
            textDelta := jDelta.GetValue<string>('text');
            streamBlock.TextContent.Append(textDelta);

            // We only add to the main content if it is a visible text block
            if streamBlock.BlockType = 'text' then
            begin
              FLastContent := FLastContent + textDelta;
              if Assigned(OnReceiveData) then
                OnReceiveData(Self, FStreamResponseMsg, jData, 'assistant', textDelta);
            end;
          end

          else if deltaType = 'citations_delta' then
          begin
            var
            jCitation := jDelta.GetValue<TJSONObject>('citation');
            if Assigned(jCitation) then
            begin
              // We accumulate the JSON in the block buffer.
              // TClaudeStreamContentBlock must have: CitationsBuffer: TJSonArray;
              streamBlock.CitationsBuffer.Add(jCitation.Clone as TJSONObject);
            end;
          end

          // JSON Delta (Tool Arguments)
          else if deltaType = 'input_json_delta' then
          begin
            jsonDelta := jDelta.GetValue<string>('partial_json');
            streamBlock.JsonContent.Append(jsonDelta);
          end
          // Thinking Delta (Extended Thinking)
          else if deltaType = 'thinking_delta' then
          begin
            textDelta := jDelta.GetValue<string>('thinking');
            streamBlock.TextContent.Append(textDelta);

            if Assigned(OnReceiveThinking) then
              OnReceiveThinking(Self, FStreamResponseMsg, jData, 'assistant', textDelta);
          end
          // Signature Delta (Signature for Thinking)
          else if deltaType = 'signature_delta' then
          begin
            var
            sig := jDelta.GetValue<string>('signature');
            streamBlock.Signature.Append(sig);
          end;
        end;
      end

      // =======================================================================
      // EVENT: content_block_stop
      // End of a specific block
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'content_block_stop' then
      begin
        blockIndex := jData.GetValue<Integer>('index');
        if FStreamContentBlocks.TryGetValue(blockIndex, streamBlock) then
        begin
          // If a tool block ended, we parse the accumulated JSON arguments
          if streamBlock.BlockType = 'tool_use' then
          begin
            try
              var
              jInput := TJSONObject.ParseJSONValue(streamBlock.JsonContent.ToString) as TJSONObject;
              if Assigned(jInput) then
              begin
                streamBlock.ToolFunction.Arguments := jInput.Format;
                jInput.Free;
              end;
            except
              // Ignore JSON parsing error at this point, it will be handled globally if it fails
            end;
          end;
        end;
      end

      // =======================================================================
      // EVENT: message_delta
      // Message-level changes (Stop Reason, Usage)
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'message_delta' then
      begin
        jDelta := jData.GetValue<TJSONObject>('delta');
        if Assigned(jDelta) then
        begin
          StopReason := jDelta.GetValue<string>('stop_reason', '');
          if StopReason <> '' then
            FStreamResponseMsg.StopReason := StopReason;
        end;

        var
        jUsage := jData.GetValue<TJSONObject>('usage');
        if Assigned(jUsage) then
          FStreamResponseMsg.Completion_tokens := jUsage.GetValue<Integer>('output_tokens');
      end

      // =======================================================================
      // EVENT: message_stop
      // End of the complete message. Reconstruction and execution.
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'message_stop' then
      begin
        if Assigned(FStreamResponseMsg) then
        begin
          // 1. We save a local reference to work safely.
          var
            MsgToProcess: TAiChatMessage := FStreamResponseMsg;

            // 2. IMPORTANT: We unlink the global variable BEFORE calling ParseChat.
            // This is vital because ParseChat can trigger recursion (DoCallFunction -> Run)
            // and 'Run' would create a NEW FStreamResponseMsg. If we do the nil after,
            // we would delete that new object created by recursion.
          FStreamResponseMsg := nil;

          var
          jSyntheticResponse := TJSONObject.Create;
          try
            // We use the local variable MsgToProcess instead of FStreamResponseMsg
            jSyntheticResponse.AddPair('id', MsgToProcess.ToolCallId);
            jSyntheticResponse.AddPair('type', 'message');
            jSyntheticResponse.AddPair('role', 'assistant');
            jSyntheticResponse.AddPair('model', MsgToProcess.Model);

            if MsgToProcess.StopReason <> '' then
              jSyntheticResponse.AddPair('stop_reason', MsgToProcess.StopReason)
            else
              jSyntheticResponse.AddPair('stop_reason', TJSONNull.Create);

            var
            jUsage := TJSONObject.Create;
            jUsage.AddPair('input_tokens', TJSONNumber.Create(Prompt_tokens));
            jUsage.AddPair('output_tokens', TJSONNumber.Create(MsgToProcess.Completion_tokens));
            jSyntheticResponse.AddPair('usage', jUsage);

            var
            jContentArr := TJSonArray.Create;
            // We sort the blocks to maintain the correct sequence
            var
            SortedKeys := TList<Integer>.Create(FStreamContentBlocks.Keys);
            try
              SortedKeys.Sort;
              for var Key in SortedKeys do
              begin
                streamBlock := FStreamContentBlocks[Key];
                var
                jBlockObj := TJSONObject.Create;

                // --- CASE 1: TEXT ( + Citations) ---
                if (streamBlock.BlockType = 'text') then
                begin
                  jBlockObj.AddPair('type', 'text');
                  jBlockObj.AddPair('text', streamBlock.TextContent.ToString);

                  // Inject accumulated citations (RAG / Web Search)
                  if streamBlock.CitationsBuffer.Count > 0 then
                    jBlockObj.AddPair('citations', streamBlock.CitationsBuffer.Clone as TJSonArray);

                  jContentArr.Add(jBlockObj);
                end

                // --- CASE 2: TOOL USE (Tool Use) ---
                else if (streamBlock.BlockType = 'tool_use') and Assigned(streamBlock.ToolFunction) then
                begin
                  jBlockObj.AddPair('type', 'tool_use');
                  jBlockObj.AddPair('id', streamBlock.ToolFunction.Id);
                  jBlockObj.AddPair('name', streamBlock.ToolFunction.Name);

                  var
                  sArgs := streamBlock.JsonContent.ToString;
                  if sArgs.IsEmpty then
                    sArgs := '{}';

                  try
                    var
                    jInputObj := TJSONObject.ParseJSONValue(sArgs);
                    if Assigned(jInputObj) then
                      jBlockObj.AddPair('input', jInputObj)
                    else
                      jBlockObj.AddPair('input', TJSONObject.Create);
                  except
                    jBlockObj.AddPair('input', TJSONObject.Create);
                  end;
                  jContentArr.Add(jBlockObj);
                end

                // --- CASE 3: THINKING (Claude 4.5 / 3.7) ---
                else if (streamBlock.BlockType = 'thinking') then
                begin
                  jBlockObj.AddPair('type', 'thinking');
                  jBlockObj.AddPair('thinking', streamBlock.TextContent.ToString);
                  if streamBlock.Signature.Length > 0 then
                    jBlockObj.AddPair('signature', streamBlock.Signature.ToString);
                  jContentArr.Add(jBlockObj);
                end

                // --- CASE 4: GENERIC BLOCKS (Code Execution Results, etc.) ---
                // Capture 'bash_code_execution_tool_result' where the file_id comes
                else
                begin
                  jBlockObj.AddPair('type', streamBlock.BlockType);

                  // A. Restore metadata (e.g. tool_use_id) captured in content_block_start
                  if Assigned(streamBlock.ExtraData) and (streamBlock.ExtraData.Count > 0) then
                  begin
                    for var Pair in streamBlock.ExtraData do
                      jBlockObj.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
                  end;

                  // B. Restore accumulated content (result JSON)
                  if streamBlock.JsonContent.Length > 0 then
                  begin
                    try
                      var
                      jCont := TJSONObject.ParseJSONValue(streamBlock.JsonContent.ToString);
                      if Assigned(jCont) then
                        jBlockObj.AddPair('content', jCont); // Usually it is an object or array
                    except
                      // Fallback if it is not valid JSON
                    end;
                  end;

                  jContentArr.Add(jBlockObj);
                end;
              end;
              jSyntheticResponse.AddPair('content', jContentArr);
            finally
              SortedKeys.Free;
            end;

            // 3. We call ParseChat with the local reference.
            // If this triggers a new Run, FStreamResponseMsg (Global) will already be free.
            ParseChat(jSyntheticResponse, MsgToProcess);

          finally
            jSyntheticResponse.Free;

            // Local buffer cleanup
            FStreamBuffer.Clear;
            FStreamContentBlocks.Clear;
            FStreamLastEventType := '';
            FBusy := False;
          end;
        end;
      end

      // =======================================================================
      // EVENT: Error
      // =======================================================================
      Else If AnsiLowerCase(eventType) = 'error' then
      begin
        var
        jError := jData.GetValue<TJSONObject>('error');
        var
        ErrMsg := 'Unknown Error';
        if Assigned(jError) then
          ErrMsg := jError.GetValue<string>('message', 'Unknown');

        DoError('Claude Stream Error: ' + ErrMsg, nil);
        ClearStreamState;
        FBusy := False;
      end;

    finally
      jData.Free;
      FStreamLastEventType := '';
    end;
  end;
end;

procedure TAiClaudeChat.ClearStreamState;
begin
  FStreamBuffer.Clear;
  FStreamContentBlocks.Clear;
  FreeAndNil(FStreamResponseMsg);
  FStreamLastEventType := '';
end;

procedure TAiClaudeChat.ConfigureAutoContextClearing(TriggerTokens: Integer; KeepLast: Integer);
begin
  // Limpia configuraciones previas para evitar duplicados
  // Limpia configuraciones previas para evitar duplicados
  FContextConfig.Clear;

  // Add the tool cleanup rule
  // TriggerTokens: When the prompt exceeds this size
  // KeepLast: Keep the last N tool uses (to not lose immediate context)
  // ClearAtLeast: 0 (Default, lets Claude decide how much to delete)
  FContextConfig.AddRule_ClearTools(TriggerTokens, KeepLast, 0);
end;

// --- Internal Overrides ---

function TAiClaudeChat.InternalAddMessage(aMsg: TAiChatMessage): TAiChatMessage;
Var
  Respuesta: String;
  MF: TAiMediaFile;
  Procesado: Boolean;
begin
  Try

    // Add the message to the list
    aMsg.Id := FMessages.Count + 1;
    FMessages.Add(aMsg);

    If Assigned(FOnAddMessage) then
    Begin
      FOnAddMessage(Self, aMsg, Nil, aMsg.Role, aMsg.Prompt);
    End;

    // Processing of attached files (MediaFiles)
    // If there are files that require pre-processing (e.g.: local OCR, conversion), it is done here.
    For MF in aMsg.MediaFiles do
    Begin
      Procesado := False;
      DoProcessMediaFile(aMsg.Prompt, MF, Respuesta, Procesado); // sends the file in case another specialized AI wants to process it
      MF.Procesado := Procesado;
      MF.Transcription := Respuesta;
      // Save the transcriptions in the MediaFile
    End;

    FLastPrompt := aMsg.Prompt; // Update the registered last prompt

    If Assigned(FOnBeforeSendMessage) then
      FOnBeforeSendMessage(Self, aMsg);

    Result := aMsg;

  Except
    on E: Exception do
      raise Exception.Create('Error in InternalAddMessage: ' + E.Message);
  End;
end;

{ function TAiClaudeChat.GetMessages: TJSonArray;
  var
  LMessage: TAiChatMessage;
  LMessageObj, LPartObj, LSourceObj, LThinkingObj: TJSONObject;
  LContentArray: TJSonArray;
  LMediaFile: TAiMediaFile;
  MediaArr: TAiMediaFilesArray;
  bHasContent: Boolean;
  IsCodeExecutionEnabled: Boolean;

  begin
  Result := TJSonArray.Create;
  IsCodeExecutionEnabled := cap_CodeInterpreter in ModelConfig.ModelCaps;

  for LMessage in Self.Messages do
  begin
  LMessageObj := TJSONObject.Create;
  LMessageObj.AddPair('role', LMessage.Role);
  LContentArray := TJSonArray.Create;

  // -------------------------------------------------------------------------
  // CASE 1: Tool Result (Role: User)
  // -------------------------------------------------------------------------
  if (LMessage.Role = 'user') and (not LMessage.ToolCallId.IsEmpty) then
  begin
  LPartObj := TJSONObject.Create;
  LPartObj.AddPair('type', 'tool_result');
  LPartObj.AddPair('tool_use_id', LMessage.ToolCallId);
  LPartObj.AddPair('content', LMessage.Prompt);
  LContentArray.Add(LPartObj);
  end

  // -------------------------------------------------------------------------
  // CASO 2: Mensaje del Asistente (Texto / Thinking / Tool Request)
  // -------------------------------------------------------------------------
  else if (LMessage.Role = 'assistant') then
  begin
  // --- FIX: Inject Thinking Block ---
  // If the message has thinking AND signature, it must go FIRST.
  // Claude requires this mandatorily if there is a tool_use afterwards.
  if (FEnableThinking) and (LMessage.ThinkingContent <> '') and (LMessage.ThinkingSignature <> '') then
  begin
  LThinkingObj := TJSONObject.Create;
  LThinkingObj.AddPair('type', 'thinking');
  LThinkingObj.AddPair('thinking', LMessage.ThinkingContent);
  LThinkingObj.AddPair('signature', LMessage.ThinkingSignature);
  LContentArray.Add(LThinkingObj);
  end;

  // A. Visible text
  // We add text if it exists, BUT if it is a tools-only message,
  // LMessage.Prompt could be empty or contain the previous text.
  if not LMessage.Prompt.IsEmpty then
  begin
  LPartObj := TJSONObject.Create;
  LPartObj.AddPair('type', 'text');
  LPartObj.AddPair('text', LMessage.Prompt);

  // --- NEW: Cache Control Injection ---
  if LMessage.CacheControl then
  begin
  var
  jCache := TJSONObject.Create;
  jCache.AddPair('type', 'ephemeral');
  LPartObj.AddPair('cache_control', jCache);
  end;

  LContentArray.Add(LPartObj);
  bHasContent := True;
  end;

  // B. Tool Use Blocks (Tool Use)
  if LMessage.Tool_calls <> '' then
  begin
  try
  var
  LToolUseArray := TJSonArray.ParseJSONValue(LMessage.Tool_calls) as TJSonArray;
  if Assigned(LToolUseArray) then
  begin
  for var Val in LToolUseArray do
  LContentArray.Add(Val.Clone as TJSONObject);
  LToolUseArray.Free;
  end;
  except
  // If parsing tool_calls fails, we try to recover something or ignore it
  end;
  end;
  end

  // -------------------------------------------------------------------------
  // CASE 3: Standard User Message (Text + Multimedia)
  // -------------------------------------------------------------------------
  else
  begin
  bHasContent := False;

  // Text
  if not LMessage.Prompt.IsEmpty then
  begin
  LPartObj := TJSONObject.Create;
  LPartObj.AddPair('type', 'text');
  LPartObj.AddPair('text', LMessage.Prompt);
  LContentArray.Add(LPartObj);
  bHasContent := True;
  end;

  // Attached files
  MediaArr := LMessage.MediaFiles.GetMediaList(Self.GetModelInputFileTypes, False);


  for LMediaFile in MediaArr do
  begin
  LPartObj := TJSONObject.Create;

  // A. Define the block type
  case LMediaFile.FileCategory of
  Tfc_Image:
  LPartObj.AddPair('type', 'image');
  else
  // PDF, Text, CSV, JSON -> All go as 'document'
  LPartObj.AddPair('type', 'document');
  end;

  LSourceObj := TJSONObject.Create;

  // B. Decide whether to send REFERENCE (File API) or VALUE (Base64)
  if not LMediaFile.IdFile.IsEmpty then
  begin
  // --- NEW: Use Files API reference (more efficient / Code Interpreter) ---
  LSourceObj.AddPair('type', 'file');
  LSourceObj.AddPair('file_id', LMediaFile.IdFile);
  end
  else
  begin
  // --- LEGACY: Send content in Base64 (Only small images or if not uploaded) ---
  LSourceObj.AddPair('type', 'base64');
  LSourceObj.AddPair('media_type', LMediaFile.MimeType);
  LSourceObj.AddPair('data', LMediaFile.Base64);
  end;

  LPartObj.AddPair('source', LSourceObj);

  // C. Extra metadata for Documents (Citations, Cache, Context)
  if LPartObj.GetValue<string>('type') = 'document' then
  begin
  // File name (helps Claude identify it in the Python code)
  if not LMediaFile.FileName.IsEmpty then
  LPartObj.AddPair('title', LMediaFile.FileName);
  end;

  // Cache Control (generic)
  if LMediaFile.CacheControl then
  begin
  var
  jCache := TJSONObject.Create;
  jCache.AddPair('type', 'ephemeral');
  LPartObj.AddPair('cache_control', jCache);
  end;

  LContentArray.Add(LPartObj);
  bHasContent := True;
  end;

  // protection contra contenido empty
  if not bHasContent then
  begin
  LPartObj := TJSONObject.Create;
  LPartObj.AddPair('type', 'text');
  LPartObj.AddPair('text', ' '); // Empty space to avoid API error
  LContentArray.Add(LPartObj);
  end;
  end;

  LMessageObj.AddPair('content', LContentArray);
  Result.Add(LMessageObj);
  end;
  end;
}

function TAiClaudeChat.GetMessages: TJSonArray;
var
  LMessage: TAiChatMessage;
  LMessageObj, LPartObj, LSourceObj, LThinkingObj: TJSONObject;
  LContentArray: TJSonArray;
  LMediaFile: TAiMediaFile;
  MediaArr: TAiMediaFilesArray;
  bHasContent: Boolean;
  IsCodeExecutionEnabled: Boolean;
begin
  Result := TJSonArray.Create;

  // We check if Code Interpreter is active
  IsCodeExecutionEnabled := cap_CodeInterpreter in ModelConfig.ModelCaps;

  for LMessage in Self.Messages do
  begin
    LMessageObj := TJSONObject.Create;
    LMessageObj.AddPair('role', LMessage.Role);
    LContentArray := TJSonArray.Create;

    // -------------------------------------------------------------------------
    // CASE 1: Tool Result (Role: User)
    // -------------------------------------------------------------------------
    if (LMessage.Role = 'user') and (not LMessage.ToolCallId.IsEmpty) then
    begin
      LPartObj := TJSONObject.Create;
      LPartObj.AddPair('type', 'tool_result');
      LPartObj.AddPair('tool_use_id', LMessage.ToolCallId);
      LPartObj.AddPair('content', LMessage.Prompt);
      LContentArray.Add(LPartObj);
    end

    // -------------------------------------------------------------------------
    // CASO 2: Mensaje del Asistente (Texto / Thinking / Tool Request)
    // -------------------------------------------------------------------------
    else if (LMessage.Role = 'assistant') then
    begin
      // A. Thinking Block (High Priority for Claude 4.5/3.7)
      if (FEnableThinking) and (LMessage.ReasoningContent <> '') and (LMessage.ThinkingSignature <> '') then
      begin
        LThinkingObj := TJSONObject.Create;
        LThinkingObj.AddPair('type', 'thinking');
        LThinkingObj.AddPair('thinking', LMessage.ReasoningContent);
        LThinkingObj.AddPair('signature', LMessage.ThinkingSignature);
        LContentArray.Add(LThinkingObj);
      end;

      // B. Visible text
      if not LMessage.Prompt.IsEmpty then
      begin
        LPartObj := TJSONObject.Create;
        LPartObj.AddPair('type', 'text');
        LPartObj.AddPair('text', LMessage.Prompt);

        // Cache Control
        if LMessage.CacheControl then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          LPartObj.AddPair('cache_control', jCache);
        end;

        LContentArray.Add(LPartObj);
      end;

      // C. Tool Use Blocks
      if LMessage.Tool_calls <> '' then
      begin
        try
          var
          LToolUseArray := TJSonArray.ParseJSONValue(LMessage.Tool_calls) as TJSonArray;
          if Assigned(LToolUseArray) then
          begin
            for var Val in LToolUseArray do
              LContentArray.Add(Val.Clone as TJSONObject);
            LToolUseArray.Free;
          end;
        except
          on E: Exception do LogDebug('Tool calls parse error: ' + E.Message);
        end;
      end;
    end

    // -------------------------------------------------------------------------
    // CASE 3: Standard User Message (Text + Files)
    // -------------------------------------------------------------------------
    else
    begin
      bHasContent := False;

      // A. Text
      if not LMessage.Prompt.IsEmpty then
      begin
        LPartObj := TJSONObject.Create;
        LPartObj.AddPair('type', 'text');
        LPartObj.AddPair('text', LMessage.Prompt);

        // Cache Control for user text
        if LMessage.CacheControl then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          LPartObj.AddPair('cache_control', jCache);
        end;

        LContentArray.Add(LPartObj);
        bHasContent := True;
      end;

      // B. Files (MediaFiles)
      MediaArr := LMessage.MediaFiles.GetMediaList(Self.GetModelInputFileTypes, False);

      for LMediaFile in MediaArr do
      begin
        LPartObj := TJSONObject.Create;

        // --- SUB-CASE 3.1: IMAGES ---
        // Images always go as an 'image' block, either by FileID or Base64
        if LMediaFile.FileCategory = Tfc_Image then
        begin
          LPartObj.AddPair('type', 'image');
          LSourceObj := TJSONObject.Create;

          if not LMediaFile.IdFile.IsEmpty then
          begin
            LSourceObj.AddPair('type', 'file'); // Files API
            LSourceObj.AddPair('file_id', LMediaFile.IdFile);
          end
          else
          begin
            LSourceObj.AddPair('type', 'base64'); // Legacy Base64
            LSourceObj.AddPair('media_type', LMediaFile.MimeType);
            LSourceObj.AddPair('data', LMediaFile.Base64);
          end;
          LPartObj.AddPair('source', LSourceObj);
        end

        // --- SUB-CASE 3.2: CONTAINER UPLOAD (Code Interpreter + Data Files) ---
        // If it is Code Interpreter AND the file is uploaded (IdFile) AND it is NOT an image.
        // This is mandatory for Excel, CSV, JSON, etc.
        else if IsCodeExecutionEnabled and (not LMediaFile.IdFile.IsEmpty) then
        begin
          LPartObj.AddPair('type', 'container_upload');
          LPartObj.AddPair('file_id', LMediaFile.IdFile);

          // Note: 'container_upload' does NOT support 'source', 'title' or 'citations'.
          // It is a direct mount in the sandbox file system.
        end

        // --- SUB-CASE 3.3: DOCUMENTS (PDFs / Text for Reading) ---
        // If it is not an image and we don't use Container Upload (or we don't have an ID), we go with Document.
        else
        begin
          LPartObj.AddPair('type', 'document');
          LSourceObj := TJSONObject.Create;

          if not LMediaFile.IdFile.IsEmpty then
          begin
            LSourceObj.AddPair('type', 'file');
            LSourceObj.AddPair('file_id', LMediaFile.IdFile);
          end
          else
          begin
            // Fallback Base64 (Only PDF officially supports this)
            LSourceObj.AddPair('type', 'base64');
            LSourceObj.AddPair('media_type', LMediaFile.MimeType);
            LSourceObj.AddPair('data', LMediaFile.Base64);
          end;

          LPartObj.AddPair('source', LSourceObj);

          // Title: prioritize LMediaFile.Title, fallback to FileName
          if not LMediaFile.Title.IsEmpty then
            LPartObj.AddPair('title', LMediaFile.Title)
          else if not LMediaFile.FileName.IsEmpty then
            LPartObj.AddPair('title', LMediaFile.FileName);

          // Context
          if not LMediaFile.Context.IsEmpty then
            LPartObj.AddPair('context', LMediaFile.Context);

          // Citations (Native RAG)
          if LMediaFile.EnableCitations then
          begin
            var jCit := TJSONObject.Create;
            jCit.AddPair('enabled', TJSONBool.Create(True));
            LPartObj.AddPair('citations', jCit);
          end;
        end;

        // Cache Control (Applies to all media blocks)
        if LMediaFile.CacheControl then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          LPartObj.AddPair('cache_control', jCache);
        end;

        LContentArray.Add(LPartObj);
        bHasContent := True;
      end;

      // protection contra contenido empty
      if not bHasContent then
      begin
        LPartObj := TJSONObject.Create;
        LPartObj.AddPair('type', 'text');
        LPartObj.AddPair('text', ' ');
        LContentArray.Add(LPartObj);
      end;
    end;

    LMessageObj.AddPair('content', LContentArray);
    Result.Add(LMessageObj);
  end;
end;

class function TAiClaudeChat.GetModels(aApiKey, aUrl: String): TStringList;
var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  Res: IHTTPResponse;
  sUrl, EndPointUrl, sModel: string;
  jRes: TJSONObject;
  jArr: TJSonArray;
  JVal: TJSONValue;
  CustomModels: TArray<string>;
  I: Integer;
begin
  Result := TStringList.Create;

  // 1. Determine the base URL
  if aUrl <> '' then
    EndPointUrl := aUrl
  else
    EndPointUrl := GlAIUrl;

  sUrl := EndPointUrl + 'models';

  Client := TNetHTTPClient.Create(Nil);
  try
    // 2. Configure Claude-specific headers
    // Note: Claude requires 'x-api-key' instead of Bearer token, and the API version
    Headers := [TNetHeader.Create('x-api-key', aApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('content-type', 'application/json')];

    // 3. Execute GET request
    Res := Client.Get(sUrl, nil, Headers);

    if Res.StatusCode = 200 then
    begin
      jRes := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      if Assigned(jRes) then
        try
          // 4. Parse the JSON response
          // The structure is: { "data": [ {"id": "...", ...}, ... ] }
          if jRes.TryGetValue<TJSonArray>('data', jArr) then
          begin
            for JVal in jArr do
            begin
              if JVal is TJSONObject then
              begin
                // Extract the model ID (e.g: "claude-sonnet-4-5-20250514")
                sModel := (JVal as TJSONObject).GetValue<string>('id', '');
                if sModel <> '' then
                  Result.Add(sModel);
              end;
            end;
          end;
        finally
          jRes.Free;
        end;

      // 5. Add locally registered custom models (if any)
      // This is useful if the API does not return fine-tuned or new models that it doesn't even list
      CustomModels := TAiChatFactory.Instance.GetCustomModels(GetDriverName);
      for I := Low(CustomModels) to High(CustomModels) do
      begin
        if Result.IndexOf(CustomModels[I]) = -1 then
          Result.Add(CustomModels[I]);
      end;

    end
    else
    begin
      // HTTP error handling
      raise Exception.CreateFmt('Error getting Claude models: %d - %s', [Res.StatusCode, Res.ContentAsString(TEncoding.UTF8)]);
    end;

  finally
    Client.Free;
  end;
end;

function TAiClaudeChat.GetToolJson(aToolFormat: TToolFormat): TJSonArray;
begin
  Result := Nil;
  var
  JsonStr := Trim(inherited GetTools(tfClaude).Text);
  if (JsonStr = '') or (not Tool_Active) then
    Exit;
  Result := TJSONObject.ParseJSONValue(JsonStr) as TJSonArray;
end;

function TAiClaudeChat.ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions;
Var
  Arg: TJSONObject;
  JVal1: TJSONValue;
  Fun: TAiToolsFunction;
  I: Integer;
begin
  Result := TAiToolsFunctions.Create;
  For JVal1 in jChoices do
  Begin
    if JVal1.GetValue<String>('type') = 'tool_use' then
    begin
      Fun := TAiToolsFunction.Create;
      Fun.Id := JVal1.GetValue<String>('id');
      Fun.&Type := 'function';
      Fun.Name := JVal1.GetValue<String>('name');
      if JVal1.TryGetValue<TJSONObject>('input', Arg) then
      begin
        Fun.Arguments := Arg.Format;
      end;
      Result.Add(Fun.Id, Fun);
    end;
  End;
end;

function TAiClaudeChat.ExtractToolCallJson(jChoices: TJSonArray): TJSonArray;
Var
  jObj, Arg: TJSONObject;
  JVal1: TJSONValue;
begin
  Result := TJSonArray.Create;
  For JVal1 in jChoices do
  Begin
    if JVal1.GetValue<String>('type') = 'tool_use' then
    begin
      jObj := TJSONObject.Create;
      jObj.AddPair('type', 'tool_use');
      jObj.AddPair('id', JVal1.GetValue<String>('id'));
      jObj.AddPair('name', JVal1.GetValue<String>('name'));
      if JVal1.TryGetValue<TJSONObject>('input', Arg) then
        jObj.AddPair('input', TJSONObject(Arg.Clone));
      Result.Add(jObj);
    end;
  End;
end;

// --- File Management Implementation ---

function TAiClaudeChat.UploadFile(aMediaFile: TAiMediaFile): String;
var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  Body: TMultipartFormData;
  ResponseStream: TMemoryStream;
  Res: IHTTPResponse;
  jObj: TJSONObject;
  TempStream: TMemoryStream;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('Empty file content');

  Client := TNetHTTPClient.Create(Nil);
  ResponseStream := TMemoryStream.Create;
  Body := TMultipartFormData.Create;
  TempStream := TMemoryStream.Create;
  try
    Headers := GetFileHeaders;
    aMediaFile.Content.Position := 0;
    TempStream.LoadFromStream(aMediaFile.Content);
    TempStream.Position := 0;

{$IF CompilerVersion >= 36}
    Body.AddStream('file', TempStream, False, aMediaFile.FileName, aMediaFile.MimeType);
{$ELSE}
    Body.AddStream('file', TempStream, aMediaFile.FileName, aMediaFile.MimeType);
{$ENDIF}
    Body.AddField('purpose', 'assistants'); // Claude usually infers, but good practice

    Res := Client.Post(Url + 'files', Body, ResponseStream, Headers);

    if Res.StatusCode = 200 then
    begin
      jObj := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      try
        Result := jObj.GetValue<string>('id');
        aMediaFile.IdFile := Result;
      finally
        jObj.Free;
      end;
    end
    else
      raise Exception.CreateFmt('Upload Error: %d - %s', [Res.StatusCode, Res.ContentAsString]);
  finally
    Body.Free;
    ResponseStream.Free;
    Client.Free;
    TempStream.Free;
  end;
end;

function TAiClaudeChat.RetrieveFile(aFileId: string): TAiMediaFile;
var
  Client: TNetHTTPClient;
  Res: IHTTPResponse;
  jObj: TJSONObject;
begin
  if aFileId.IsEmpty then
    Exit(nil);
  Client := TNetHTTPClient.Create(Nil);
  try
    Res := Client.Get(Url + 'files/' + aFileId, nil, GetFileHeaders);
    if Res.StatusCode = 200 then
    begin
      jObj := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      try
        Result := TAiMediaFile.Create;
        Result.IdFile := jObj.GetValue<string>('id');
        Result.FileName := jObj.GetValue<string>('filename');
      finally
        jObj.Free;
      end;
    end
    else
      raise Exception.Create('Retrieve File Error');
  finally
    Client.Free;
  end;
end;

function TAiClaudeChat.RetrieveFileList: TAiMediaFiles;
var
  Client: TNetHTTPClient;
  Res: IHTTPResponse;
  jRes: TJSONObject;
  jArr: TJSonArray;
  JVal: TJSONValue;
  MF: TAiMediaFile;
begin
  Result := TAiMediaFiles.Create;
  Client := TNetHTTPClient.Create(Nil);
  try
    Res := Client.Get(Url + 'files', nil, GetFileHeaders);
    if Res.StatusCode = 200 then
    begin
      jRes := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      if Assigned(jRes) then
      try
        if jRes.TryGetValue<TJSonArray>('data', jArr) then
          for JVal in jArr do
            if JVal is TJSONObject then
            begin
              MF := TAiMediaFile.Create;
              MF.IdFile := (JVal as TJSONObject).GetValue<string>('id', '');
              MF.FileName := (JVal as TJSONObject).GetValue<string>('filename', '');
              Result.Add(MF);
            end;
      finally
        jRes.Free;
      end;
    end
    else
      raise Exception.CreateFmt('RetrieveFileList Error: %d - %s',
        [Res.StatusCode, Res.ContentAsString]);
  finally
    Client.Free;
  end;
end;

procedure TAiClaudeChat.DoCallFunction(ToolCall: TAiToolsFunction);
begin

  // ---------------------------------------------------------------------------
  // 1. Intercept BASH / SHELL Tool
  // ---------------------------------------------------------------------------
  if (ToolCall.Name = 'bash') then
  begin
    // A. Priority: User Event (OnCallToolFunction)
    // Allows the programmer to intercept, modify or block the command before executing it.
    if Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall);

    // B. Automatic execution (TAiShell Component)
    // If the user did not fill the response in the previous event and we have the component:
    if (ToolCall.Response = '') and Assigned(ChatTools.ShellTool) then
    begin
      // Ensure it is active
      if not ChatTools.ShellTool.Active then
        ChatTools.ShellTool.Active := True;

      // Execute the command in the persistent session
      ToolCall.Response := ChatTools.ShellTool.Execute(ToolCall.Id, ToolCall.Arguments);
    end;

    // If there is no component or event, Claude would receive an empty or error response,
    // which is fine, but ideally ChatTools.ShellTool should be assigned.
    Exit;
  end;

  // 2. Intercept Native Editing Tool
  if ((ToolCall.Name = 'str_replace_based_edit_tool') or (ToolCall.Name = 'str_replace_editor')) and Assigned(ChatTools.TextEditorTool) then
  begin
    ToolCall.Response := ChatTools.TextEditorTool.Execute(ToolCall.Arguments);
    Exit;
  end;

  // 3. Check External Component (AiFunctions)
  if Assigned(AiFunctions) and AiFunctions.DoCallFunction(ToolCall) then
  begin
    Exit;
  end;

  // 4. User Event
  if Assigned(FOnCallToolFunction) then
    FOnCallToolFunction(Self, ToolCall);
end;

function TAiClaudeChat.DownLoadFile(aMediaFile: TAiMediaFile): String;
var
  Client: TNetHTTPClient;
  Res: IHTTPResponse;
  Headers: TNetHeaders;
  MemStream: TMemoryStream;
begin
  Result := '';
  if (not Assigned(aMediaFile)) or (aMediaFile.IdFile.IsEmpty) then
    raise Exception.Create('File ID is missing');

  Client := TNetHTTPClient.Create(Nil);
  MemStream := TMemoryStream.Create;
  try
    // We use GetFileHeaders which already includes 'anthropic-beta: files-api-2025-04-14'
    Headers := GetFileHeaders;

    // Endpoint: https://api.anthropic.com/v1/files/{file_id}/content
    Res := Client.Get(Url + 'files/' + aMediaFile.IdFile + '/content', MemStream, Headers);

    if Res.StatusCode = 200 then
    begin
      // Save to the MediaFile object
      MemStream.Position := 0;
      aMediaFile.Content.CopyFrom(MemStream, 0);
      aMediaFile.Content.Position := 0;

      // Try to determine the extension if it doesn't have one
      if aMediaFile.FileName.IsEmpty then
        aMediaFile.FileName := aMediaFile.IdFile + '.bin'; // Default

      Result := aMediaFile.IdFile;
    end
    else
      raise Exception.CreateFmt('Download Error: %d - %s', [Res.StatusCode, Res.ContentAsString]);
  finally
    MemStream.Free;
    Client.Free;
  end;
end;

function TAiClaudeChat.DeleteFile(aMediaFile: TAiMediaFile): String;
var
  Client: TNetHTTPClient;
  Res: IHTTPResponse;
  jObj: TJSONObject;
begin
  Client := TNetHTTPClient.Create(Nil);
  try
    Res := Client.Delete(Url + 'files/' + aMediaFile.IdFile, nil, GetFileHeaders);
    if Res.StatusCode = 200 then
    begin
      jObj := TJSONObject.ParseJSONValue(Res.ContentAsString) as TJSONObject;
      Result := jObj.GetValue<string>('id');
      jObj.Free;
    end;
  finally
    Client.Free;
  end;
end;

function TAiClaudeChat.CheckFileState(aMediaFile: TAiMediaFile): String;
var
  Tmp: TAiMediaFile;
begin
  Tmp := RetrieveFile(aMediaFile.IdFile);
  if Assigned(Tmp) then
  begin
    Result := Tmp.IdFile;
    Tmp.Free;
  end
  else
    Result := '';
end;

function TAiClaudeChat.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer): String;
begin
  Result := UploadFile(aMediaFile);
end;

initialization

TAiChatFactory.Instance.RegisterDriver(TAiClaudeChat);

end.
