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
// Name: Gustavo Enr?quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


// -----------------------------------------------------------------------------
// CITATIONS (RAG Native) - Implementation Status
// -----------------------------------------------------------------------------
// 1. Core: TAiMediaFile.EnableCitations, Title, Context  [COMPLETED]
// 2. Core: TAiMsgCitation, TAiMsgCitations in TAiChatMessage  [COMPLETED]
// 3. Claude.GetMessages: Inject "citations": {"enabled": true}  [COMPLETED]
// 4. Claude.ProcessStreamChunk: Capture citations_delta  [ALREADY WORKING]
// 5. Claude.ParseChat: Parse char_location, page_location, etc.  [COMPLETED]
// Ref: https://docs.anthropic.com/en/docs/build-with-claude/citations
// -----------------------------------------------------------------------------
// ------ Tools that will not be implemented for now --------------------
// 1. https://platform.claude.com/docs/es/agents-and-tools/tool-use/code-execution-tool
// 2. https://platform.claude.com/docs/es/agents-and-tools/tool-use/fine-grained-tool-streaming
// 3.




// https://platform.claude.com/docs/en/intro
// https://platform.claude.com/docs/en/api/beta/messages/create  //API of the latest implementation {/beta/}

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

  // --- Classes for Context Management (Context Editing) ---

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
    // Adds a rule to clear tools when X tokens are reached
    procedure AddRule_ClearTools(TriggerTokens: Integer; KeepCount: Integer = 0; ClearAtLeast: Integer = 0);
    function ToJSONObject: TJSONObject;
    function IsEmpty: Boolean;
    procedure Clear;
  end;

  // --- Helper class for processing blocks in Streaming ---

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



  // --- Main Claude Chat Class ---

  TAiClaudeChat = Class(TAiChat)
  Private
    FStreamResponseMsg: TAiChatMessage;
    // Cache of message_start of the stream (see comment on reading)
    FStreamCacheRead: Integer;
    FStreamCacheWrite: Integer;
    FStreamContentBlocks: TObjectDictionary<Integer, TClaudeStreamContentBlock>;
    FStreamBuffer: TStringBuilder;
    FStreamLastEventType: string;

    // New features
    FEnableMemory: Boolean;
    FEnableThinking: Boolean;
    FThinkingBudget: Integer;
    FContextConfig: TClaudeContextConfig;
    FCacheSystemPrompt: Boolean;
    FCacheTTL: String;
    // Fase ago 2026
    FFastMode: Boolean;             // speed:"fast" — solo opus-5/opus-4-8
    FEnableCompaction: Boolean;     // compaction server-side (beta)
    FRefusalFallbackModel: string;  // fallbacks server-side ante refusal
    // Compaction blocks received, per assistant message: must be resent
    // whole so that the API replaces the compacted history
    FCompactionBlocks: TDictionary<TAiChatMessage, string>;
    FCacheCount: Integer; // breakpoints cache_control used in the current request (max 4 in the API)
    FCacheCtxActive: Boolean; // context caching active in this request (system/tools/last turn)
    FServiceTier: String;

    function GetToolJson(aToolFormat: TToolFormat): TJSonArray;
    function GetDynamicHeaders: TNetHeaders; // Builds Beta headers dynamically
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

    // Easy method to configure automatic context clearing
    // TriggerTokens: Starting from how many input tokens the cleaning is activated (e.g. 20000)
    // KeepLast: How many recent tool interactions to keep (e.g. 3)
    procedure ConfigureAutoContextClearing(TriggerTokens: Integer; KeepLast: Integer = 3);

    // Access to context configuration
    property ContextConfig: TClaudeContextConfig read FContextConfig;

    // Allows caching the System Prompt to save costs on long instructions
    property CacheSystemPrompt: Boolean read FCacheSystemPrompt write FCacheSystemPrompt;
    property CacheTTL: String read FCacheTTL write FCacheTTL;

  Published
    property EnableMemory: Boolean read FEnableMemory write SetEnableMemory default False;
    property EnableThinking: Boolean read FEnableThinking write SetEnableThinking default False;
    property ThinkingBudget: Integer read FThinkingBudget write SetThinkingBudget default 1024;
    Property ServiceTier: String read FServiceTier write FServiceTier;
    // Fast mode (research preview): ~2.5x more tokens/sec at 2x price.
    // Only claude-opus-5 / claude-opus-4-8 (in other models it is ignored)
    property FastMode: Boolean read FFastMode write FFastMode default False;
    // Compaction server-side (beta): as the context limit is approached, the
    // API automatically resumes old history. The driver preserves and
    // resends compaction blocks in subsequent turns
    property EnableCompaction: Boolean read FEnableCompaction
      write FEnableCompaction default False;
    // If the classifiers decline (stop_reason refusal in opus-5/fable),
    // the API retries the SAME request in this model within the same
    // call (e.g., 'claude-opus-4-8'). Empty = no fallback
    property RefusalFallbackModel: string read FRefusalFallbackModel
      write FRefusalFallbackModel;
  End;

procedure Register;

implementation


Const
  GlAIUrl = 'https://api.anthropic.com/v1/';
  CLAUDE_API_VERSION = '2023-06-01';

  // --- UPDATED BETA HEADERS ---
  // General tools (maintained)
  BETA_HDR_TOOLS = 'tools-2024-05-16';
  // Files API (maintained)
  BETA_HDR_FILES = 'files-api-2025-04-14';
  // Context / Memory Management (maintained)
  BETA_HDR_MEMORY = 'context-management-2025-06-27';
  // Thinking (maintained)
  BETA_HDR_THINKING = 'interleaved-thinking-2025-05-14';
  // Fase ago 2026
  BETA_HDR_FASTMODE = 'fast-mode-2026-02-01';             // speed:"fast" (opus-5/4.8, research preview)
  BETA_HDR_COMPACT  = 'compact-2026-01-12';               // compaction server-side
  BETA_HDR_FALLBACK = 'server-side-fallback-2026-06-01';  // fallbacks before refusal
  // Code Execution (Updated according to the doc's header list)
  BETA_HDR_CODE = 'code-execution-2025-05-22';
  // Computer Use: OBSOLETE. The current tool is computer_toolset_20260801, which does not
  // require a beta header (the API accepts this and ignores it). The previous one,
  // computer_20251124, no longer exists: the API rejects it for all models.
  // The constant is kept for backward compatibility with external code; it is not sent.
  BETA_HDR_COMPUTER = 'computer-use-2025-11-24';
  // PDFs (New: To ensure native support if base64 is sent)
  BETA_HDR_PDFS = 'pdfs-2024-09-25';
  // Header for Structured Outputs (JSON Schema & Strict Tools)
  BETA_HDR_STRUCTURED_OUTPUTS = 'structured-outputs-2025-11-13';

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
  Params.Add('Model=claude-haiku-4-5-20251001');
  Params.Add('Max_Tokens=4096');
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
    // Batch-specific headers
    Headers := [TNetHeader.Create('x-api-key', ApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('anthropic-beta', 'message-batches-2024-09-24'), // Header obligatorio para Batches
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
  // OnReceiveData assigns it in the base class (TAiChat.ClientReceiveData -> OnInternalReceiveData
  // virtual); reassigning it here skipped the mark of in-flight request of the destructor
  // Via property (not FClient directly) so that FResponseTimeOut remains consistent.
  // 300s: with native code_execution Anthropic runs server-side and does not send a single
  // byte until finished (generating an Office takes 50-70s; 60s cut it in half).
  ResponseTimeOut := 300000;

  FStreamContentBlocks := TObjectDictionary<Integer, TClaudeStreamContentBlock>.Create([doOwnsValues]);
  FStreamBuffer := TStringBuilder.Create;
  FStreamResponseMsg := nil;
  FContextConfig := TClaudeContextConfig.Create;
  FCompactionBlocks := TDictionary<TAiChatMessage, string>.Create;

  // Default values
  Model := 'claude-haiku-4-5-20251001';
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
  FCompactionBlocks.Free;
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

// Model families according to the API thinking surface (Aug 2026):
// - Adaptive-only (opus 4.7/4.8, family 5: opus/sonnet/fable/mythos):
//   budget_tokens and temperature/top_p/top_k return 400. Thinking is requested
//   with {type:"adaptive"} and depth with output_config.effort.
// - 4.6 (opus/sonnet): adaptive recommended (budget deprecated but functional),
//   sampling allowed, effort GA.
// - Legacy (<=4.5, haiku): thinking {enabled, budget_tokens} classic.
function IsClaudeAdaptiveOnly(const AModel: string): Boolean;
begin
  Result := AModel.StartsWith('claude-opus-4-7') or
            AModel.StartsWith('claude-opus-4-8') or
            AModel.StartsWith('claude-opus-5') or
            AModel.StartsWith('claude-sonnet-5') or
            AModel.StartsWith('claude-fable') or
            AModel.StartsWith('claude-mythos');
end;

function IsClaude46(const AModel: string): Boolean;
begin
  Result := AModel.StartsWith('claude-opus-4-6') or
            AModel.StartsWith('claude-sonnet-4-6');
end;

// Fast mode (speed:"fast") only exists in opus-5 and opus-4-8
function IsClaudeFastCapable(const AModel: string): Boolean;
begin
  Result := AModel.StartsWith('claude-opus-5') or
            AModel.StartsWith('claude-opus-4-8');
end;

// Messages {role:"system"} within messages[] (mid-conversation, preserve
// the prompt cache): opus-5 (and 5.5), opus-4-8, fable, mythos and sonnet-5-5.
// NOT sonnet-5 alone.
function IsClaudeMidSystemCapable(const AModel: string): Boolean;
begin
  Result := AModel.StartsWith('claude-opus-5') or
            AModel.StartsWith('claude-opus-4-8') or
            AModel.StartsWith('claude-fable') or
            AModel.StartsWith('claude-mythos') or
            AModel.StartsWith('claude-sonnet-5-5');
end;

// Forcing a tool (tool_choice "any" or {type:"tool"}) returns 400 in the
// September 2026 generation: opus-5-5, sonnet-5-5, fable-5-1 and mythos-5-1.
// There "auto" is sent (the model can still call it) instead of the error.
function IsClaudeNoForcedTool(const AModel: string): Boolean;
begin
  Result := AModel.StartsWith('claude-opus-5-5') or
            AModel.StartsWith('claude-sonnet-5-5') or
            AModel.StartsWith('claude-fable-5-1') or
            AModel.StartsWith('claude-mythos-5-1');
end;

function TAiClaudeChat.GetDynamicHeaders: TNetHeaders;
var
  BetaFeatures: TList<string>;
begin
  // Required base headers
  Result := [TNetHeader.Create('x-api-key', ApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('content-type', 'application/json')];

  BetaFeatures := TList<string>.Create;
  try
    // 1. Tools (General) - Added if there are active tools
    if Tool_Active then
      BetaFeatures.Add(BETA_HDR_TOOLS);

    // 2. Memory & Context
    if FEnableMemory or (not FContextConfig.IsEmpty) then
      BetaFeatures.Add(BETA_HDR_MEMORY);

    // 3. Code Interpreter (Code Execution)
    if cap_CodeInterpreter in ModelConfig.ModelCaps then
      BetaFeatures.Add(BETA_HDR_CODE);

    // 4. Computer Use: computer_toolset_20260801 no longer requires a beta header.
    //    The old 'computer-use-2025-11-24' is still accepted but ignored.

    // 5. Thinking: the interleaved-thinking header only applies to the legacy path
    // with budget_tokens (<=4.5). In 4.6+ adaptive thinking integrates the
    // interleaving automatically and the header is redundant.
    var LBaseModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
    if (FEnableThinking or (ModelConfig.ThinkingLevel <> tlDefault)) and
       (not IsClaudeAdaptiveOnly(LBaseModel)) and (not IsClaude46(LBaseModel)) then
      BetaFeatures.Add(BETA_HDR_THINKING);

    // 5b. Phase Aug 2026: fast mode, compaction and fallbacks (betas)
    if FFastMode and IsClaudeFastCapable(LBaseModel) then
      BetaFeatures.Add(BETA_HDR_FASTMODE);
    if FEnableCompaction then
      BetaFeatures.Add(BETA_HDR_COMPACT);
    if FRefusalFallbackModel <> '' then
      BetaFeatures.Add(BETA_HDR_FALLBACK);

    // 6. Prompt Caching: GA, no longer requires a beta header (previously 'prompt-caching-2024-07-31').

    // 7. PDFs
    // We add explicit support for PDFs
    if (cap_Pdf in ModelConfig.ModelCaps) then
      BetaFeatures.Add(BETA_HDR_PDFS);

    // 8. Files API (CRITICAL)
    // We always announce Files support for Auto-Upload
    BetaFeatures.Add(BETA_HDR_FILES);

    // Structured Outputs: Activated if we request an explicit JSON Schema
    // Optionally also if Tool_Active is true to allow "strict: true" in tools.
    if (Response_format = tiaChatRfJsonSchema) or Tool_Active then
      BetaFeatures.Add(BETA_HDR_STRUCTURED_OUTPUTS);

    // Build accumulated header separated by commas
    if BetaFeatures.Count > 0 then
    begin
      // Remove duplicates just in case
      var
      UniqueBetas := TStringList.Create;
      try
        UniqueBetas.Duplicates := dupIgnore;
        UniqueBetas.Sorted := True;
        for var Beta in BetaFeatures do
          UniqueBetas.Add(Beta);

        var
        HeaderVal := string.Join(',', UniqueBetas.ToStringArray);
        Result := Result + [TNetHeader.Create('anthropic-beta', HeaderVal)];
      finally
        UniqueBetas.Free;
      end;
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
  LIsAdaptiveThinking: Boolean;
  SystemPrompt: String;

  // Variables for message iteration (Auto-Upload)
  LMsg: TAiChatMessage;
  LMedia: TAiMediaFile;

  // Variables for new features
  jOutputFormat, jMetaData: TJSONObject;
  jSchemaParsed: TJSONValue;
  LOutputConfig: TJSONObject; // output_config: format (json_schema) y/o effort

  // Helper variables for Thinking
  LActualThinkingBudget: Integer;
  LIs46: Boolean;
begin
  LActualThinkingBudget := 0;
  LOutputConfig := nil;
  if User = '' then
    User := 'user';

  // 1. AUTO-UPLOAD
  for LMsg in Self.Messages do
  begin
    if (LMsg.Role = 'user') and (LMsg.MediaFiles.Count > 0) then
    begin
      for LMedia in LMsg.MediaFiles do
      begin
        if LMedia.IdFile.IsEmpty then
        begin
          if (cap_CodeInterpreter in ModelConfig.ModelCaps) or (not(LMedia.FileCategory in [Tfc_Image, Tfc_pdf])) then
          begin
            try
              UploadFile(LMedia);
            except
              on E: Exception do LogDebug('Auto-Upload error: ' + E.Message);
            end;
          end;
        end;
      end;
    end;
  end;

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);
  if LModel = '' then
    LModel := 'claude-haiku-4-5-20251001';

  // Classification by family (see IsClaudeAdaptiveOnly / IsClaude46 above):
  // adaptive-only = 4.7/4.8/5 (budget and sampling return 400); 4.6 = adaptive
  // recommended; rest = legacy path with budget_tokens.
  LIsAdaptiveThinking := IsClaudeAdaptiveOnly(LModel);
  LIs46 := IsClaude46(LModel);

  // ---------------------------------------------------------------------------
  // 2. THINKING BUDGET CALCULATION (legacy path only <=4.5)
  // ---------------------------------------------------------------------------
  if ModelConfig.ThinkingLevel <> tlDefault then
    FEnableThinking := True;

  if FEnableThinking and (not LIsAdaptiveThinking) and (not LIs46) then
  begin
    // Assign budget according to the selected level or use the manual one
    case ModelConfig.ThinkingLevel of
      tlLow:
        LActualThinkingBudget := 2048; // Fast, shallow
      tlMedium:
        LActualThinkingBudget := 8192; // Reasonable standard
      tlHigh:
        LActualThinkingBudget := 16384; // Deep (Mind the costs)
    else
      LActualThinkingBudget := FThinkingBudget; // Manual value
    end;

    // API minimum validation (1024)
    if LActualThinkingBudget < 1024 then
      LActualThinkingBudget := 1024;

    // MaxTokens validation: Must be strictly greater than the budget
    // We give it a margin so it can write the final response
    if Max_tokens <= LActualThinkingBudget then
      Max_tokens := LActualThinkingBudget + 4096;
  end;

  LAsincronico := Self.Asynchronous;
  FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSONObject.Create;
  Lista := TStringList.Create;
  Try
    AJSONObject.AddPair('model', LModel);

    // 3. SYSTEM PROMPT
    // cache_control breakpoint counter for this request (the API allows max 4).
    // Prefix order: tools -> system -> messages. We reserve the system and
    // tools slots before building messages so they take priority over messages.
    FCacheCount := 0;
    // Stable context caching active if the user set CacheSystemPrompt (Claude)
    // or the portable CacheContext flag (base).
    var
    LDoCache: Boolean := FCacheSystemPrompt or CacheContext;
    FCacheCtxActive := LDoCache; // visible to GetMessages (auto-cache of the last turn)
    SystemPrompt := Self.PrepareSystemMsg;
    if SystemPrompt <> '' then
    begin
      if LDoCache then
      begin
        var
        jSysArr := TJSonArray.Create;
        var
        jSysBlock := TJSONObject.Create;
        jSysBlock.AddPair('type', 'text');
        jSysBlock.AddPair('text', SystemPrompt);

        var
        jCache := TJSONObject.Create;
        jCache.AddPair('type', 'ephemeral');
        if FCacheTTL <> '' then
          jCache.AddPair('ttl', FCacheTTL);
        jSysBlock.AddPair('cache_control', jCache);
        Inc(FCacheCount); // system breakpoint (caches tools+system by prefix order)

        jSysArr.Add(jSysBlock);
        AJSONObject.AddPair('system', jSysArr);
      end
      else
        AJSONObject.AddPair('system', SystemPrompt);
    end;

    // Reservation of the tools slot: if caching is active, tool definitions
    // are cached (breakpoint on the last tool, below). It is reserved here so that
    // messages do not consume that slot.
    if LDoCache then
      Inc(FCacheCount);

    AJSONObject.AddPair('max_tokens', TJSONNumber.Create(Max_tokens));
    AJSONObject.AddPair('messages', GetMessages);

    // 4. JSON OUTPUT (STRUCTURED OUTPUTS)
    if (Response_format = tiaChatRfJsonSchema) then
    begin
      if (JsonSchema.Text <> '') then
      begin
        try
          var
          sShema := StringReplace(JsonSchema.Text, '\n', ' ', [rfReplaceAll]);
          jSchemaParsed := TJSONObject.ParseJSONValue(sShema);
          if Assigned(jSchemaParsed) and (jSchemaParsed is TJSONObject) then
          begin
            var
            jRootSchema := jSchemaParsed as TJSONObject;

            // --- AUTOMATIC FIX FOR CLAUDE ---
            // Claude requires "additionalProperties": false at the root level if it is type object.
            // We check if it is type object and if the property is missing, we add it.
            if (jRootSchema.GetValue<string>('type') = 'object') and (jRootSchema.GetValue('additionalProperties') = nil) then
            begin
              jRootSchema.AddPair('additionalProperties', TJSONBool.Create(False));
            end;
            // -----------------------------------------

            jOutputFormat := TJSONObject.Create;
            jOutputFormat.AddPair('type', 'json_schema');
            jOutputFormat.AddPair('schema', jRootSchema); // We use the already modified object
            // output_format (top-level) is deprecated API-wide: the canonical one
            // is output_config.format (added at the end together with effort)
            LOutputConfig := TJSONObject.Create;
            LOutputConfig.AddPair('format', jOutputFormat);
          end
          else if Assigned(jSchemaParsed) then
            jSchemaParsed.Free;
        except
          on E: Exception do LogDebug('JSON Schema parse error: ' + E.Message);
        end;
      end;
    end;

    // -------------------------------------------------------------------------
    // 5. THINKING PARAMETERS by model family
    // -------------------------------------------------------------------------
    if LIsAdaptiveThinking or LIs46 then
    begin
      // Family 4.6+ : adaptive thinking (auto-interleaved, without beta header).
      // Depth is requested with output_config.effort (GA since 4.6).
      // In opus-5/fable thinking is already active by default; sending
      // explicit {type:"adaptive"} is equivalent and harmless.
      if FEnableThinking then
      begin
        var
        jThink := TJSONObject.Create;
        jThink.AddPair('type', 'adaptive');
        AJSONObject.AddPair('thinking', jThink);
      end;

      if ModelConfig.ThinkingLevel <> tlDefault then
      begin
        if not Assigned(LOutputConfig) then
          LOutputConfig := TJSONObject.Create;
        // Expanded ladder (v3.8): xhigh exists since opus-4-7 (in 4.6 no:
        // it maps to high) and max since 4.6. minimal/none do not exist in
        // Claude: they are requested as low (in the 5.5 family it cannot be turned off).
        case ModelConfig.ThinkingLevel of
          tlLow, tlMinimal, tlNone:
            LOutputConfig.AddPair('effort', 'low');
          tlMedium:
            LOutputConfig.AddPair('effort', 'medium');
          tlHigh:
            LOutputConfig.AddPair('effort', 'high');
          tlXHigh:
            if LIsAdaptiveThinking then
              LOutputConfig.AddPair('effort', 'xhigh')
            else
              LOutputConfig.AddPair('effort', 'high');
          tlMax:
            LOutputConfig.AddPair('effort', 'max');
        end;
      end;

      // Sampling: in 4.7+/5 temperature/top_p/top_k return 400 — they are never
      // sent. In 4.6 they are still allowed, but only without active thinking.
      if LIs46 and (not LIsAdaptiveThinking) and (not FEnableThinking) then
      begin
        if Self.Temperature > 0 then
          AJSONObject.AddPair('temperature', TJSONNumber.Create(Self.Temperature))
        Else if Top_p > 0 then
          AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));
        if K > 0 then
          AJSONObject.AddPair('top_k', TJSONNumber.Create(K));
      end;
    end
    else if FEnableThinking then
    begin
      // Legacy path (<=4.5): manual thinking with budget_tokens
      var
      jThink := TJSONObject.Create;
      jThink.AddPair('type', 'enabled');
      jThink.AddPair('budget_tokens', TJSONNumber.Create(LActualThinkingBudget));
      AJSONObject.AddPair('thinking', jThink);

      // Temperature forced to 1.0 (API requirement for thinking)
      AJSONObject.AddPair('temperature', TJSONNumber.Create(1.0));
    end
    else
    begin
      // Legacy standard mode
      if Self.Temperature > 0 then
        AJSONObject.AddPair('temperature', TJSONNumber.Create(Self.Temperature))
      Else if Top_p > 0 then
        AJSONObject.AddPair('top_p', TJSONNumber.Create(Top_p));

      if K > 0 then
        AJSONObject.AddPair('top_k', TJSONNumber.Create(K));
    end;

    // accumulated output_config (structured outputs format and/or effort)
    if Assigned(LOutputConfig) then
      AJSONObject.AddPair('output_config', LOutputConfig);

    // 6. METADATA & SERVICE TIER
    if (Self.User <> '') and (Self.User <> 'user') then
    begin
      jMetaData := TJSONObject.Create;
      jMetaData.AddPair('user_id', Self.User);
      AJSONObject.AddPair('metadata', jMetaData);
    end;

    if (FServiceTier <> '') then
      AJSONObject.AddPair('service_tier', FServiceTier);

    // context_management: user configuration (FContextConfig) and/or
    // compaction server-side (edits.compact_20260112)
    var jContext: TJSONObject := nil;
    if not FContextConfig.IsEmpty then
      jContext := FContextConfig.ToJSONObject;
    if FEnableCompaction then
    begin
      if not Assigned(jContext) then
        jContext := TJSONObject.Create;
      var jEdits: TJSonArray := nil;
      jContext.TryGetValue<TJSonArray>('edits', jEdits);
      if not Assigned(jEdits) then
      begin
        jEdits := TJSonArray.Create;
        jContext.AddPair('edits', jEdits);
      end;
      var jCompact := TJSONObject.Create;
      jCompact.AddPair('type', 'compact_20260112');
      jEdits.Add(jCompact);
    end;
    if Assigned(jContext) then
      AJSONObject.AddPair('context_management', jContext);

    // Fast mode (research preview): only opus-5/opus-4-8; on others it is ignored
    if FFastMode then
    begin
      if IsClaudeFastCapable(LModel) then
        AJSONObject.AddPair('speed', 'fast')
      else
        LogDebug('FastMode ignored: ' + LModel + ' does not support it');
    end;

    // Server-side fallbacks: if the classifiers decline, the API retries
    // the same request on the specified model within the same call
    if FRefusalFallbackModel <> '' then
    begin
      var jFallbacks := TJSonArray.Create;
      var jFb := TJSONObject.Create;
      jFb.AddPair('model', FRefusalFallbackModel);
      jFallbacks.Add(jFb);
      AJSONObject.AddPair('fallbacks', jFallbacks);
    end;

    // 7. TOOLS
    jArrTools := TJSonArray.Create;

    if Tool_Active and (Trim(GetTools(TToolFormat.tfClaude).Text) <> '') then
    begin
      var
      jUserTools := GetToolJson(TToolFormat.tfClaude);
      if Assigned(jUserTools) then
      begin
        for var Val in jUserTools do
          jArrTools.Add(Val.Clone as TJSONObject);
        jUserTools.Free;
      end;
    end;

    // The dynamic filtering of web_search_20260209 runs with code, so
    // Anthropic AUTO-INJECTS its own 'code_execution' when that variant is
    // present. If we also declare it, it rejects the entire request with
    // 'Auto-injecting tools would conflict with existing tool names:
    // [''code_execution'']'. It is noted here so as not to declare it twice.
    var LAutoInjectsCodeExec := False;

    if cap_WebSearch in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      // Since the 4.6 family there is web_search_20260209 with dynamic filtering
      // (the model filters results with code before they enter the
      // context); previous models continue with the basic variant
      if LIsAdaptiveThinking or LIs46 then
      begin
        JTools.AddPair('type', 'web_search_20260209');
        LAutoInjectsCodeExec := True;
      end
      else
        JTools.AddPair('type', 'web_search_20250305');
      JTools.AddPair('name', 'web_search');
      jArrTools.Add(JTools);
    end;

    // It is only declared if no one is going to auto-inject it. When it is omitted for that reason,
    // the capability is NOT lost: the tool that Anthropic injects is a
    // real code_execution and the beta header is still sent the same way.
    if (cap_CodeInterpreter in ModelConfig.ModelCaps) and (not LAutoInjectsCodeExec) then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'code_execution_20250522');
      JTools.AddPair('name', 'code_execution');
      jArrTools.Add(JTools);
    end;

    if FEnableMemory then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'memory_20250818');
      JTools.AddPair('name', 'memory');
      jArrTools.Add(JTools);
    end;

    if cap_TextEditor in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'text_editor_20250728');
      JTools.AddPair('name', 'str_replace_based_edit_tool');
      jArrTools.Add(JTools);
    end;

    if cap_ComputerUse in ModelConfig.ModelCaps then
    begin
      // computer_toolset_20260801 (Aug 2026) replaces computer_20251124,
      // which the API already rejects. It is a 'toolset' type entry: it does NOT accept
      // 'name' nor 'display_width_px'/'display_height_px' nor 'enable_zoom'
      // (it responds "Extra inputs are not permitted"). The model deduces the
      // dimensions of the screenshot itself; ScreenWidth/ScreenHeight of
      // TAiComputerUseTool are still used, but only locally, to
      // normalize to 0-999 the pixel coordinates returned by Claude.
      // The toolset serves 17 tools with their own names (left_click, key,
      // scroll, zoom, screenshot...) instead of a single 'computer' tool with
      // an 'action' field: dispatch is done in DoCallFunction by ToolCall.Name.
      // Note: zoom is now always available, it no longer depends on EnableZoom.
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'computer_toolset_20260801');
      jArrTools.Add(JTools);
    end;

    if cap_Shell in ModelConfig.ModelCaps then
    begin
      JTools := TJSONObject.Create;
      JTools.AddPair('type', 'bash_20250124');
      JTools.AddPair('name', 'bash');
      jArrTools.Add(JTools);
    end;

    if jArrTools.Count > 0 then
    begin
      AJSONObject.AddPair('tools', jArrTools);

      // Cache of tool definitions: cache_control on the last tool caches
      // the whole tools block (prefix order tools->system->messages). The slot
      // was already reserved in FCacheCount next to system.
      if LDoCache then
      begin
        var
        jToolCache := TJSONObject.Create;
        jToolCache.AddPair('type', 'ephemeral');
        if FCacheTTL <> '' then
          jToolCache.AddPair('ttl', FCacheTTL);
        (jArrTools.Items[jArrTools.Count - 1] as TJSONObject).AddPair('cache_control', jToolCache);
      end;

      if (Trim(Tool_choice) <> '') then
      begin
        // Anthropic requires tool_choice as an OBJECT: {"type":"auto"|"any"|"none"}
        // or {"type":"tool","name":"x"}. The property usually arrives in format
        // OpenAI: "auto"/"none"/"required" (sometimes JSON-quoted as '"auto"')
        // or {"type":"function","function":{"name":"x"}} — here it is translated.
        // Sending it raw produces 400 "tool_choice: Input should be an object".
        var LChoiceObj: TJSONObject := nil;
        var LRaw := Trim(Tool_choice);
        var LVal := TJSONObject.ParseJSONValue(LRaw);
        try
          if LVal is TJSONObject then
          begin
            var LType := TJSONObject(LVal).GetValue<string>('type', '');
            if SameText(LType, 'function') then
            begin
              // OpenAI format with specific function → {"type":"tool","name":...}
              var LName := '';
              var LFn := TJSONObject(LVal).GetValue<TJSONObject>('function', nil);
              if Assigned(LFn) then
                LName := LFn.GetValue<string>('name', '');
              if LName <> '' then
              begin
                LChoiceObj := TJSONObject.Create;
                LChoiceObj.AddPair('type', 'tool');
                LChoiceObj.AddPair('name', LName);
              end;
            end
            else
              LChoiceObj := TJSONObject(LVal.Clone); // already in Anthropic format
          end
          else
          begin
            // Simple string (with or without JSON quotes): auto | none | required
            var LWord := LRaw.Replace('"', '').Trim.ToLower;
            if LWord = 'required' then
              LWord := 'any';
            if (LWord = 'auto') or (LWord = 'any') or (LWord = 'none') then
            begin
              LChoiceObj := TJSONObject.Create;
              LChoiceObj.AddPair('type', LWord);
            end;
          end;
        finally
          LVal.Free;
        end;
        // Sep 2026 models reject forcing a tool: it is downgraded to auto
        if Assigned(LChoiceObj) and IsClaudeNoForcedTool(LModel) then
        begin
          var LForced := LChoiceObj.GetValue<string>('type', '');
          if SameText(LForced, 'any') or SameText(LForced, 'tool') then
          begin
            LogDebug('tool_choice "' + LForced + '" not supported by ' + LModel + ': sending "auto"');
            LChoiceObj.Free;
            LChoiceObj := TJSONObject.Create;
            LChoiceObj.AddPair('type', 'auto');
          end;
        end;
        if Assigned(LChoiceObj) then
          AJSONObject.AddPair('tool_choice', LChoiceObj);
      end;
    end
    else
      jArrTools.Free;

    // 8. FINALIZATION
    Lista.CommaText := Stop;
    if Lista.Count > 0 then
    begin
      jArrStop := TJSonArray.Create;
      for I := 0 to Lista.Count - 1 do
        jArrStop.Add(Lista[I]);
      AJSONObject.AddPair('stop_sequences', jArrStop);
    end;

    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    ApplyExtraBodyParams(AJSONObject);
    Res := UTF8ToString(UTF8Encode(AJSONObject.ToJSON));
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
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
    begin
      // ISSUE #105/#118: the assistant message is accumulated in FStreamResponseMsg during
      // the stream and is archived in FMessages on close (message_stop, see OnInternalReceiveData).
      // In async, RunNew frees its own ResMsg after the POST, so we do NOT reference it.
      FStreamResponseMsg := TAiChatMessage.Create('', 'assistant');
    end;

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

      if not Assigned(Res) then
        raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

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
        St.Free
      else
      begin
        if Assigned(FCurrentPostStream) then
          FreeAndNil(FCurrentPostStream);
        FCurrentPostStream := St;
      end;
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
  // Counting variables
  aPrompt_tokens, aCompletion_tokens, aTotal_tokens, aCached_tokens: Integer;
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

  // Variables for File Navigation (Code Execution)
  jInnerContent, jResultContent: TJSONObject;
  jResultArray: TJSonArray;
  NewFile: TAiMediaFile;
  ToolUseID, FoundFileName: string;
  ScanItem: TJSONValue;
  ScanObj, InputObj: TJSONObject;

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
            var LErrorMsg := 'Error in tool "' + TC.Name + '": ' + E.Message;
            TC.Response := '{"error": "' + E.Message.Replace('"', '''') + '"}';
            TThread.Queue(nil,
              procedure
              begin
                DoError(LErrorMsg, nil);
              end);
          end;
        end;
      end);
    TaskList[AIdx].Start;
  end;

begin
  AskMsg := GetLastMessage;

  // 1. Parse Metadata
  LModel := jObj.GetValue<string>('model', '');
  Role := jObj.GetValue<string>('role', 'assistant');
  StopR := jObj.GetValue<string>('stop_reason', '');

  ResMsg.StopReason := StopR;
  if StopR = 'refusal' then
  begin
    // Safety classifiers (opus-5/fable-5) decline with HTTP 200 +
    // stop_reason:"refusal" and a stop_details object {category, explanation}.
    // The content may be empty (pre-output) or partial (mid-stream).
    ResMsg.IsRefusal := True;
    var LRefusalMsg := 'The request was declined by the model safety classifiers';
    var jStopDetails: TJSONObject := nil;
    jObj.TryGetValue<TJSONObject>('stop_details', jStopDetails);
    if Assigned(jStopDetails) then
    begin
      var LCategory := jStopDetails.GetValue<string>('category', '');
      var LExplanation := jStopDetails.GetValue<string>('explanation', '');
      if LCategory <> '' then
        LRefusalMsg := LRefusalMsg + ' (category: ' + LCategory + ')';
      if LExplanation <> '' then
        LRefusalMsg := LRefusalMsg + ': ' + LExplanation;
    end;
    DoError(LRefusalMsg, nil);
  end;

  // 2. Parse Usage (FIXED)
  aPrompt_tokens := 0;
  aCompletion_tokens := 0;
  aTotal_tokens := 0;
  aCached_tokens := 0;

  if jObj.TryGetValue<TJSONObject>('usage', uso) then
  begin
    aPrompt_tokens := uso.GetValue<Integer>('input_tokens', 0);
    aCompletion_tokens := uso.GetValue<Integer>('output_tokens', 0);

    // Cached token capture (Beta Prompt Caching)
    aCached_tokens := uso.GetValue<Integer>('cache_read_input_tokens', 0);
    ResMsg.Cache_write_tokens := uso.GetValue<Integer>('cache_creation_input_tokens', 0);

    // NOTE: input_tokens, cache_read_input_tokens and cache_creation_input_tokens
    // are DISJOINT in the Anthropic API — cached ones are NOT included in
    // input_tokens (the previous comment claimed otherwise and is false).
    // The actual prompt for the turn is the sum of the three; whoever bills must add them.
    aTotal_tokens := aPrompt_tokens + aCompletion_tokens
                   + aCached_tokens + ResMsg.Cache_write_tokens;
  end;

  // 3. Parse Content (Interleaved Blocks)
  if jObj.TryGetValue<TJSonArray>('content', choices) then
  begin
    for JVal in choices do
    begin
      if not(JVal is TJSONObject) then
        Continue;

      jContentItem := TJSONObject(JVal);
      cType := jContentItem.GetValue<string>('type');

      // A. Normal Text
      if cType = 'text' then
        Respuesta := Respuesta + jContentItem.GetValue<string>('text') + sLineBreak;

      // B. Thinking (Extended Reasoning)
      if cType = 'thinking' then
      begin
        Var
        sThinkingContent := jContentItem.GetValue<string>('thinking');

        ResMsg.ReasoningContent := ResMsg.ReasoningContent + jContentItem.GetValue<string>('thinking');
        if jContentItem.TryGetValue<string>('signature', Clave) then
          ResMsg.ThinkingSignature := Clave;

        // Trigger event for UI
        if Assigned(OnReceiveThinking) then
          OnReceiveThinking(Self, ResMsg, jObj, 'assistant', sThinkingContent);

      end;

      // C. Citations (Web Search / RAG / Documents)
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

            // Also add to Citations for unification
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

      // C2. Compaction block (beta compact-2026-01-12): it is saved in full
      // associated with the response message; GetMessages resends it in
      // subsequent turns so the API replaces the compacted history
      if cType = 'compaction' then
        FCompactionBlocks.AddOrSetValue(ResMsg, jContentItem.ToJSON);

      // D. Code Execution Output
      if (cType = 'tool_result') or (cType = 'code_execution_tool_result') then
      begin

        if jContentItem.TryGetValue<TJSONObject>('content', jInnerContent) then
        begin
          // We verify that it is a code execution result
          if jInnerContent.GetValue<string>('type') = 'code_execution_result' then
          begin
            // 2. We look for the internal 'content' array that contains the outputs (files)
            if jInnerContent.TryGetValue<TJSonArray>('content', jResultArray) then
            begin
              for var valRes in jResultArray do
              begin
                jResultContent := valRes as TJSONObject;

                // 3. We check if there is a file_id
                if jResultContent.TryGetValue<string>('file_id', Clave) then
                begin
                  // --- NAME RECOVERY LOGIC ---
                  FoundFileName := 'generated_file_' + Copy(Clave, 1, 8) + '.bin';
                  ToolUseID := jContentItem.GetValue<string>('tool_use_id', '');

                  if ToolUseID <> '' then
                  begin
                    // Scan backwards to find the input and deduce the name
                    for ScanItem in choices do
                    begin
                      if not(ScanItem is TJSONObject) then
                        Continue;
                      ScanObj := ScanItem as TJSONObject;

                      var
                        sId: String;
                      if ScanObj.TryGetValue<string>('id', sId) and (sId = ToolUseID) then
                      begin
                        if ScanObj.TryGetValue<TJSONObject>('input', InputObj) then
                        begin
                          // We search the Python code for the generated file name
                          var
                          CodeStr := InputObj.GetValue<string>('code', '');

                          // Simple heuristic: look for 'output_path = ...' or strings with extensions
                          // This is more complex in Python than in Bash, but we try something basic
                          // If the code defines output_path = ... 'file.wav'
                          var
                          PosExt := Pos('.wav', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.csv', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.png', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.pdf', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.mp3', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.json', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.xlsx', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.xls', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.zip', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.txt', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.html', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.xml', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.jpg', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.jpeg', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.gif', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.mp4', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.py', CodeStr);
                          if PosExt = 0 then
                            PosExt := Pos('.js', CodeStr);

                          if PosExt > 0 then
                          begin
                            // Try to extract the name by searching backwards from the extension
                            var
                            StartPos := LastDelimiter('''"', Copy(CodeStr, 1, PosExt));
                            if StartPos > 0 then
                            begin
                              // Calculate the real length of the extension (advance from the dot)
                              var
                              EndPos := PosExt + 1;
                              while (EndPos <= Length(CodeStr)) and CharInSet(CodeStr[EndPos], ['a'..'z','A'..'Z','0'..'9']) do
                                Inc(EndPos);
                              var
                              ExtLen := EndPos - PosExt;
                              var
                              Candidate := Copy(CodeStr, StartPos + 1, (PosExt - StartPos) + ExtLen - 1);
                              if (Length(Candidate) > 0) and (Length(Candidate) < 50) then
                                FoundFileName := Candidate;
                            end;
                          end;
                        end;
                        Break;
                      end;
                    end;
                  end;
                  // ----------------------------------------

                  NewFile := TAiMediaFile.Create;
                  NewFile.IdFile := Clave;
                  NewFile.FileName := FoundFileName;

                  try
                    DownLoadFile(NewFile);
                    ResMsg.MediaFiles.Add(NewFile);
                  except
                    NewFile.Free;
                  end;
                end;
              end;
            end;
          end;
        end

      end;
    end;
  end;

  Respuesta := Trim(Respuesta);

  // 4. Parse Tools
  var
  JToolCallArray := ExtractToolCallJson(choices);
  if JToolCallArray.Count > 0 then
    sToolCalls := JToolCallArray.Format;
  JToolCallArray.Free;

  LFunciones := ExtractToolCallFromJson(choices);

  // 5. Update Component State & Response Message (HERE IS THE FIX)
  Self.FLastContent := Respuesta;

  // Update global component counters.
  // Cache ones are accumulated JUST LIKE input/output ones: in a tool loop
  // calling each round is a billable call and the consumer only sees the
  // last message, so without accumulating here rounds 1..N-1 were lost.
  Self.Prompt_tokens := Self.Prompt_tokens + aPrompt_tokens;
  Self.Completion_tokens := Self.Completion_tokens + aCompletion_tokens;
  Self.Total_tokens := Self.Total_tokens + aTotal_tokens;
  Self.Cached_tokens := Self.Cached_tokens + aCached_tokens;
  Self.Cache_write_tokens := Self.Cache_write_tokens + ResMsg.Cache_write_tokens;

  // Update Response Message counters
  ResMsg.Prompt_tokens := aPrompt_tokens;
  ResMsg.Completion_tokens := aCompletion_tokens;
  ResMsg.Total_tokens := aTotal_tokens;
  ResMsg.Cached_tokens := aCached_tokens; // New: Cache support

  if sToolCalls.IsEmpty then
  begin
    ResMsg.Role := Role;
    ResMsg.Model := LModel;
    ResMsg.Tool_calls := sToolCalls;
    ResMsg.Prompt := ResMsg.Prompt + Respuesta;

    DoProcessResponse(AskMsg, ResMsg, Respuesta);
  end
  else
  begin
    var
    Msg := TAiChatMessage.Create(Respuesta, Role);
    Msg.Tool_calls := sToolCalls;
    Msg.ReasoningContent := ResMsg.ReasoningContent;
    Msg.ThinkingSignature := ResMsg.ThinkingSignature;
    // The counters MUST be copied: this temporary message is the one returned
    // by GetLastMessage when the response brings tool_calls, and it is from there that
    // the consumer (broker/billing) reads the turn usage. Without this, every
    // call ending in tool_calls was billed with cache_read/cache_write
    // as zero even if Anthropic had reported them.
    Msg.Prompt_tokens := aPrompt_tokens;
    Msg.Completion_tokens := aCompletion_tokens;
    Msg.Total_tokens := aTotal_tokens;
    Msg.Cached_tokens := aCached_tokens;
    Msg.Cache_write_tokens := ResMsg.Cache_write_tokens;
    Msg.Id := FMessages.Count + 1;
    FMessages.Add(Msg);
  end;

  // 6. Tool Execution
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

        _CreateTask(ToolCall, I); // subrutina local garantiza captura por valor
        Inc(I);
      end;
      // Pump Synchronize/Queue while waiting, so as not to hang the app if a
      // tool call accede a la VCL/FMX via TThread.Synchronize (issue #103).
      // NOTE: CheckSynchronize is ONLY valid on the main thread; on
      // secondary threads (Indy workers of a headless service, agent TTask)
      // it THROWS exception "CheckSynchronize called from thread X". Outside the main
      // thread we only wait. Same criterion as TMCPClientSSE.WaitForInitialization.
      while not TTask.WaitForAll(TaskList, 10) do
        if TThread.CurrentThread.ThreadID = MainThreadID then
          CheckSynchronize(0)
        else
          TThread.Sleep(10);

      var LStopLoop := False;
      for Clave in LFunciones.Keys do
      begin
        ToolCall := LFunciones[Clave];
        ToolMsg := TAiChatMessage.Create(ToolCall.Response, 'user', ToolCall.Id, ToolCall.Name);
        for var LMF in ToolCall.MediaFiles do
          ToolMsg.AddMediaFile(LMF);
        ToolCall.MediaFiles.OwnsObjects := False;
        ToolMsg.Id := FMessages.Count + 1;
        FMessages.Add(ToolMsg);
        LStopLoop := LStopLoop or ToolCall.StopAgenticLoop;
      end;

      if LStopLoop then
      begin
        // A handler requested stopping the agentic loop (tool passthrough: it
        // is executed by the end client). The turn is finished with the tool_calls
        // in ResMsg instead of resending the synthetic result to the model.
        ResMsg.Tool_calls := sToolCalls;
        DoProcessResponse(AskMsg, ResMsg, Respuesta);
        FBusy := False;
        DoStateChange(acsFinished, 'Done');
        if Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, jObj, Role, Respuesta);
      end
      else
      begin
        // ISSUE #100: en async este ParseChat corre DENTRO del callback de recepción
        // (OnInternalReceiveData -> message_stop). Re-entering with Self.Run starts a new POST
        // whose finally frees the FCurrentPostStream of the request still in flight -> AV
        // in THTTPClient.ExecuteHTTPInternal. The continuation is deferred to
        // OnRequestCompletedEvent (base), which runs when the request has already freed its stream.
        if FClient.Asynchronous then
          FPendingToolRun := True
        else
          Self.Run(Nil, ResMsg);
      end;
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
      DoStateChange(acsFinished, 'Done');

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
  line, Chunk: string;
begin

  if not FClient.Asynchronous then
    Exit;

  LogDebug('-- OnInternalReceiveData--');

  // ISSUE #124 (extends #108): FResponse accumulates raw TCP bytes in UTF-8; if a
  // chunk splits a multibyte character, DataString throws EEncodingError. It is decoded
  // only once BEFORE clearing: if it fails, the partial bytes remain in FResponse
  // (without Clear) and the next chunk completes the character.
  try
    Chunk := FResponse.DataString;
  except
    on EEncodingError do
    begin
      LogDebug('[partial UTF-8 chunk - retry with the next chunk]');
      Chunk := '';
    end;
  end;

  LogDebug(Chunk);

  AAbort := FAbort;
  if FAbort then
  begin
    FBusy := False;
    FPendingToolRun := False;
    if Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, nil, nil, 'system', 'abort');
    ClearStreamState;
    Exit;
  end;

  if Chunk <> '' then
  begin
    FStreamBuffer.Append(Chunk);
    FResponse.Clear;
  end;

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

          // Read input_tokens from message_start (Claude streaming does not include usage in message_stop).
          // And the cache ones: in streaming input_tokens is ONLY the uncached part
          // (with a prefix of 4,681 cached tokens input_tokens=6 arrives), so
          // that without cache_read/cache_creation the synthetic close usage
          // said 6 input tokens and ParseChat did not see a single cache token
          // (measured in MKAIServer on 2026-09-05: prompt_tokens=6 without details).
          var jStartUsage: TJSONObject;
          if jMessage.TryGetValue<TJSONObject>('usage', jStartUsage) then
          begin
            Self.Prompt_tokens := jStartUsage.GetValue<Integer>('input_tokens', 0);
            FStreamCacheRead   := jStartUsage.GetValue<Integer>('cache_read_input_tokens', 0);
            FStreamCacheWrite  := jStartUsage.GetValue<Integer>('cache_creation_input_tokens', 0);
          end;

          // Notify start of reception
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
          // Evitamos duplicar 'type' que ya guardamos
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
            var jCitation: TJSONObject;
            if jDelta.TryGetValue<TJSONObject>('citation', jCitation) then
              streamBlock.CitationsBuffer.Add(jCitation.Clone as TJSONObject);
          end

          // JSON Delta (Tool Arguments)
          else if deltaType = 'input_json_delta' then
          begin
            jsonDelta := jDelta.GetValue<string>('partial_json');
            streamBlock.JsonContent.Append(jsonDelta);
          end
          // Thinking Delta (Extended Reasoning)
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
              // Ignore JSON parse error at this point, it will be handled globally if it fails
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
            // This is vital because ParseChat may trigger recursion (DoCallFunction -> Run)
            // and 'Run' will create a NEW FStreamResponseMsg. If we do the nil afterwards,
            // we would delete that new object created by the recursion.
          FStreamResponseMsg := nil;

          var
          jSyntheticResponse := TJSONObject.Create;
          try
            // We use the local MsgToProcess variable instead of FStreamResponseMsg
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
            // Cache from message_start, with the same names as the real API:
            // so ParseChat reads them through the usual path and accumulates them.
            if FStreamCacheRead > 0 then
              jUsage.AddPair('cache_read_input_tokens', TJSONNumber.Create(FStreamCacheRead));
            if FStreamCacheWrite > 0 then
              jUsage.AddPair('cache_creation_input_tokens', TJSONNumber.Create(FStreamCacheWrite));
            FStreamCacheRead  := 0;
            FStreamCacheWrite := 0;
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
                // Capture 'bash_code_execution_tool_result' where the file_id comes from
                else
                begin
                  jBlockObj.AddPair('type', streamBlock.BlockType);

                  // A. Restore metadata (e.g., tool_use_id) captured in content_block_start
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

            // ISSUE #105/#118: in async, TAiChat.RunNew FREES its ResMsg right after
            // starting the POST (see branch "if FClient.Asynchronous then ResMsg.Free" in
            // uMakerAi.Chat.pas) and does NOT leave it in FMessages. That is why the previous attempt to
            // reconcile with FAsyncResMsg never worked: it pointed to an already
            // freed object. The assistant message is built HERE in MsgToProcess, so
            // we archive it directly when it is the FINAL response (without tool-loop
            // in progress: FBusy=False and without tool_calls). Same pattern as TAiChat/TAiOpenChat.
            // If there was tool_use, ParseChat already added its own message (assistant + tool),
            // so here MsgToProcess is disposable. Fix proposed by @martijntonies.
            if Assigned(MsgToProcess) and (FMessages.IndexOf(MsgToProcess) = -1) then
            begin
              if (not FBusy) and (MsgToProcess.Tool_calls = '') then
              begin
                MsgToProcess.Id := FMessages.Count + 1;
                FMessages.Add(MsgToProcess);
                MsgToProcess := nil; // propiedad transferida a FMessages; no liberar abajo
              end;
              if Assigned(MsgToProcess) then
                MsgToProcess.Free;
            end;

            // If ParseChat triggered a recursive Run due to tool calls, FBusy remained True
            // (set by the InternalRunCompletions of the new round) and already called
            // ClearStreamState before starting the new HTTP request.
            // Clearing here in that case creates a race with the callbacks of the new round.
            // We only clear when there is NO recursive run in progress (FBusy=False,
            // which is what the no-tools path does in ParseChat before returning).
            if not FBusy then
            begin
              FStreamBuffer.Clear;
              FStreamContentBlocks.Clear;
              FStreamLastEventType := '';
            end;
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
        FPendingToolRun := False;
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
  // Clears previous configurations to avoid duplicates
  FContextConfig.Clear;

  // Add the tool clearing rule
  // TriggerTokens: When the prompt exceeds this size
  // KeepLast: Keep the last N tool uses (so as not to lose immediate context)
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

    // Adds the message to the list
    aMsg.Id := FMessages.Count + 1;
    FMessages.Add(aMsg);

    If Assigned(FOnAddMessage) then
    Begin
      FOnAddMessage(Self, aMsg, Nil, aMsg.Role, aMsg.Prompt);
    End;

    // Attachment processing (MediaFiles)
    // If there are files that require pre-processing (e.g., local OCR, conversion), it is done here.
    For MF in aMsg.MediaFiles do
    Begin
      Procesado := False;
      DoProcessMediaFile(aMsg.Prompt, MF, Respuesta, Procesado); // Sends the file in case another specialized AI wants to process it
      MF.Procesado := Procesado;
      MF.Transcription := Respuesta;
      // Saves the transcriptions in the MediaFile
    End;

    FLastPrompt := aMsg.Prompt; // Updates the last recorded prompt

    If Assigned(FOnBeforeSendMessage) then
      FOnBeforeSendMessage(Self, aMsg);

    Result := aMsg;

  Except
    on E: Exception do
      raise Exception.Create('Error in InternalAddMessage: ' + E.Message);
  End;
end;

function TAiClaudeChat.GetMessages: TJSonArray;
var
  LMessage: TAiChatMessage;
  LMessageObj, LPartObj, LSourceObj, LThinkingObj: TJSONObject;
  LContentArray: TJSonArray;
  LMediaFile: TAiMediaFile;
  MediaArr: TAiMediaFilesArray;
  bHasContent: Boolean;
  IsCodeExecutionEnabled: Boolean;
  TargetCategories: TAiFileCategories;
  LLastContent: TJSonArray;
  LSupportsMidSystem: Boolean;
begin
  Result := TJSonArray.Create;
  LLastContent := nil; // contenido del ultimo mensaje emitido (auto-cache del ultimo turno)

  // Mensajes {role:"system"} dentro del historial (mid-conversation): solo
  // opus-5/4.8/fable/mythos. En modelos sin soporte se degradan a un turno
  // user envuelto en <system-reminder> (mismo perfil de cache, sin 400)
  LSupportsMidSystem := IsClaudeMidSystemCapable(
    TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model));

  // We check if the Code Interpreter is active
  IsCodeExecutionEnabled := cap_CodeInterpreter in ModelConfig.ModelCaps;

  // --- DYNAMIC FILTERING LOGIC ---
  if IsCodeExecutionEnabled then
    // If there is Code Execution, we allow EVERYTHING (Excel, Zip, Code, etc.)
    // We build a set with all possible enum values
    TargetCategories := [Low(TAiFileCategory) .. High(TAiFileCategory)]
  else
    // If not, we are strict and only allow what the component says (Vision, PDF)
    TargetCategories := Self.GetModelInputFileTypes;

  for LMessage in Self.Messages do
  begin
    LMessageObj := TJSONObject.Create;
    // Anthropic does not accept role 'tool' (OpenAI convention used by
    // external histories): tool_result goes inside a 'user' message.
    if SameText(LMessage.Role, 'tool') then
      LMessageObj.AddPair('role', 'user')
    else if SameText(LMessage.Role, 'system') and (not LSupportsMidSystem) then
      LMessageObj.AddPair('role', 'user') // fallback <system-reminder> (case 3)
    else
      LMessageObj.AddPair('role', LMessage.Role);
    LContentArray := TJSonArray.Create;

    // -------------------------------------------------------------------------
    // CASE 1: Tool Result (Role: User or 'tool' OpenAI style)
    // -------------------------------------------------------------------------
    if ((LMessage.Role = 'user') or SameText(LMessage.Role, 'tool')) and (not LMessage.ToolCallId.IsEmpty) then
    begin
      LPartObj := TJSONObject.Create;
      LPartObj.AddPair('type', 'tool_result');
      LPartObj.AddPair('tool_use_id', LMessage.ToolCallId);

      MediaArr := LMessage.MediaFiles.GetMediaList([Tfc_Image, Tfc_pdf], False);
      if Length(MediaArr) = 0 then
      begin
        // Without attachments: content as a simple string
        LPartObj.AddPair('content', LMessage.Prompt);
      end
      else
      begin
        // With attachments: content as an array [text, image/document, ...]
        var LToolContent := TJSonArray.Create;
        var LTextBlock := TJSONObject.Create;
        LTextBlock.AddPair('type', 'text');
        LTextBlock.AddPair('text', LMessage.Prompt);
        LToolContent.Add(LTextBlock);
        for LMediaFile in MediaArr do
        begin
          var LFileBlock := TJSONObject.Create;
          if LMediaFile.FileCategory = Tfc_pdf then
          begin
            // PDF Document
            LFileBlock.AddPair('type', 'document');
            var LDocSource := TJSONObject.Create;
            LDocSource.AddPair('type', 'base64');
            LDocSource.AddPair('media_type', LMediaFile.MimeType);
            LDocSource.AddPair('data', LMediaFile.Base64);
            LFileBlock.AddPair('source', LDocSource);
          end
          else
          begin
            // Image
            LFileBlock.AddPair('type', 'image');
            LSourceObj := TJSONObject.Create;
            LSourceObj.AddPair('type', 'base64');
            LSourceObj.AddPair('media_type', LMediaFile.MimeType);
            LSourceObj.AddPair('data', LMediaFile.Base64);
            LFileBlock.AddPair('source', LSourceObj);
          end;
          LToolContent.Add(LFileBlock);
        end;
        LPartObj.AddPair('content', LToolContent);
      end;

      LContentArray.Add(LPartObj);
    end

    // -------------------------------------------------------------------------
    // CASE 2: Assistant Message (Text / Thinking / Tool Request)
    // -------------------------------------------------------------------------
    else if (LMessage.Role = 'assistant') then
    begin
      // 0. Preserved compaction block (if this turn brought it): it must go
      // first — the API uses it to replace the compacted history
      var LCompactRaw: string;
      if FCompactionBlocks.TryGetValue(LMessage, LCompactRaw) then
      begin
        var LCompactVal := TJSONObject.ParseJSONValue(LCompactRaw);
        if LCompactVal is TJSONObject then
          LContentArray.Add(TJSONObject(LCompactVal))
        else
          LCompactVal.Free;
      end;

      // A. Thinking Block
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

        if (LMessage.CacheControl) and (FCacheCount < 4) then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          if FCacheTTL <> '' then
            jCache.AddPair('ttl', FCacheTTL);
          LPartObj.AddPair('cache_control', jCache);
          Inc(FCacheCount);
        end;

        LContentArray.Add(LPartObj);
      end;

      // C. Tool Use Blocks
      if LMessage.Tool_calls <> '' then
      begin
        try

{$IF CompilerVersion < 35}
          var
          LToolUseArray := TJSONUtils.ParseAsArray(LMessage.Tool_calls) as TJSonArray;
{$ELSE}
          var
          LToolUseArray := TJSonArray.ParseJSONValue(LMessage.Tool_calls) as TJSonArray;
{$ENDIF}
          if Assigned(LToolUseArray) then
          begin
            for var Val in LToolUseArray do
            begin
              var JTC := Val as TJSONObject;
              if SameText(JTC.GetValue<string>('type', ''), 'function') then
              begin
                // OpenAI format {"type":"function","function":{name,arguments}}
                // (external multi-turn histories) → Anthropic tool_use block.
                var JUse := TJSONObject.Create;
                JUse.AddPair('type', 'tool_use');
                JUse.AddPair('id', JTC.GetValue<string>('id', ''));
                var JFn := JTC.GetValue<TJSONObject>('function', nil);
                if Assigned(JFn) then
                begin
                  JUse.AddPair('name', JFn.GetValue<string>('name', ''));
                  var JArgs := TJSONObject.ParseJSONValue(JFn.GetValue<string>('arguments', '{}'));
                  if JArgs is TJSONObject then
                    JUse.AddPair('input', JArgs)
                  else
                  begin
                    JArgs.Free;
                    JUse.AddPair('input', TJSONObject.Create);
                  end;
                end;
                LContentArray.Add(JUse);
              end
              else
                LContentArray.Add(Val.Clone as TJSONObject);
            end;
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
        // System message in a model without mid-conversation support: degrade to
        // user turn with <system-reminder> wrapper (documented fallback)
        if SameText(LMessage.Role, 'system') and (not LSupportsMidSystem) then
          LPartObj.AddPair('text', '<system-reminder>' + sLineBreak +
            LMessage.Prompt + sLineBreak + '</system-reminder>')
        else
          LPartObj.AddPair('text', LMessage.Prompt);

        if (LMessage.CacheControl) and (FCacheCount < 4) then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          if FCacheTTL <> '' then
            jCache.AddPair('ttl', FCacheTTL);
          LPartObj.AddPair('cache_control', jCache);
          Inc(FCacheCount);
        end;

        LContentArray.Add(LPartObj);
        bHasContent := True;
      end;

      // B. Files (MediaFiles) - USING THE DYNAMIC FILTER
      MediaArr := LMessage.MediaFiles.GetMediaList(TargetCategories, False);

      for LMediaFile in MediaArr do
      begin
        LPartObj := TJSONObject.Create;

        // --- SUB-CASE 3.1: IMAGES ---
        if LMediaFile.FileCategory = Tfc_Image then
        begin
          LPartObj.AddPair('type', 'image');
          LSourceObj := TJSONObject.Create;

          if not LMediaFile.IdFile.IsEmpty then
          begin
            LSourceObj.AddPair('type', 'file');
            LSourceObj.AddPair('file_id', LMediaFile.IdFile);
          end
          else
          begin
            LSourceObj.AddPair('type', 'base64');
            // Automatic MimeType detection (As we fixed before)
            var
              RealMime: string := LMediaFile.MimeType;
            var
              B64Head: string := Copy(LMediaFile.Base64, 1, 15);
            if StartsStr('iVBORw', B64Head) then
              RealMime := 'image/png'
            else if StartsStr('/9j/', B64Head) then
              RealMime := 'image/jpeg'
            else if StartsStr('R0lGOD', B64Head) then
              RealMime := 'image/gif'
            else if StartsStr('UklGR', B64Head) then
              RealMime := 'image/webp';

            LSourceObj.AddPair('media_type', RealMime);
            LSourceObj.AddPair('data', LMediaFile.Base64);
          end;
          LPartObj.AddPair('source', LSourceObj);
        end

        // --- SUB-CASE 3.2: CONTAINER UPLOAD (Code Interpreter + Data Files) ---
        // Here Excel, CSV, etc. will go
        else if IsCodeExecutionEnabled and (not LMediaFile.IdFile.IsEmpty) then
        begin
          LPartObj.AddPair('type', 'container_upload');
          LPartObj.AddPair('file_id', LMediaFile.IdFile);
        end

        // --- SUB-CASE 3.3: DOCUMENTS (PDFs for vision) ---
        else
        begin
          LPartObj.AddPair('type', 'document');
          LSourceObj := TJSONObject.Create;

          if not LMediaFile.IdFile.IsEmpty then
          begin
            LSourceObj.AddPair('type', 'file');
            LSourceObj.AddPair('file_id', LMediaFile.IdFile);
          end
          else if not LMediaFile.UrlMedia.IsEmpty then
          begin
            // Direct URL — Claude downloads the document without prior upload
            LSourceObj.AddPair('type', 'url');
            LSourceObj.AddPair('url', LMediaFile.UrlMedia);
          end
          else if LMediaFile.FileCategory = Tfc_Text then
          begin
            // Plain text — send decoded, not as base64
            var LBytes := TNetEncoding.Base64.DecodeStringToBytes(LMediaFile.Base64);
            LSourceObj.AddPair('type', 'text');
            LSourceObj.AddPair('data', TEncoding.UTF8.GetString(LBytes));
          end
          else
          begin
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

        if (LMediaFile.CacheControl) and (FCacheCount < 4) then
        begin
          var
          jCache := TJSONObject.Create;
          jCache.AddPair('type', 'ephemeral');
          if FCacheTTL <> '' then
            jCache.AddPair('ttl', FCacheTTL);
          LPartObj.AddPair('cache_control', jCache);
          Inc(FCacheCount);
        end;

        LContentArray.Add(LPartObj);
        bHasContent := True;
      end;

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
    LLastContent := LContentArray; // referencia al contenido del ultimo mensaje emitido
  end;

  // Multi-turn convenience: caches the last turn (its last block) so that the
  // next request reads ALL previous history from cache. Only if context caching is
  // active, budget remains (<4 breakpoints) and the block was not marked
  // manually (CacheControl) to avoid duplicating the breakpoint.
  if FCacheCtxActive and (FCacheCount < 4) and Assigned(LLastContent) and (LLastContent.Count > 0) then
  begin
    var
    LLastBlock := LLastContent.Items[LLastContent.Count - 1] as TJSONObject;
    if LLastBlock.GetValue('cache_control') = nil then
    begin
      var
      jCacheLT := TJSONObject.Create;
      jCacheLT.AddPair('type', 'ephemeral');
      if FCacheTTL <> '' then
        jCacheLT.AddPair('ttl', FCacheTTL);
      LLastBlock.AddPair('cache_control', jCacheLT);
      Inc(FCacheCount);
    end;
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
  try // ISSUE #114: if the body throws, free Result to avoid leaking it

  // 1. Determine the base URL
  if aUrl <> '' then
    EndPointUrl := aUrl
  else
    EndPointUrl := GlAIUrl;

  sUrl := EndPointUrl + 'models';

  Client := TNetHTTPClient.Create(Nil);
  try
    // 2. Configure Claude-specific Headers
    // Note: Claude requires 'x-api-key' instead of a Bearer token, and the API version
    Headers := [TNetHeader.Create('x-api-key', aApiKey), TNetHeader.Create('anthropic-version', CLAUDE_API_VERSION), TNetHeader.Create('content-type', 'application/json')];

    // 3. Execute GET Request
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
                // Extract the model ID (e.g.: "claude-sonnet-4-5-20250514")
                sModel := (JVal as TJSONObject).GetValue<string>('id', '');
                if sModel <> '' then
                  Result.Add(sModel);
              end;
            end;
          end;
        finally
          jRes.Free;
        end;

      // 5. Add custom models registered locally (if any)
      // This is useful if the API does not return finetuned or new models that it does not list yet
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
      raise Exception.CreateFmt('Error al obtener modelos de Claude: %d - %s', [Res.StatusCode, Res.ContentAsString(TEncoding.UTF8)]);
    end;

  finally
    Client.Free;
  end;
  except // ISSUE #114: the error path must not leave Result orphaned
    Result.Free;
    raise;
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

function IsClaudeComputerToolName(const AName: string): Boolean;
// Members of computer_toolset_20260801. The toolset replaced the single tool
// 'computer' (which discriminated by the 'action' field) with 17 tools with
// their own names. 'computer' is also accepted for older histories.
const
  CComputerTools: array [0 .. 17] of string = ('computer', 'left_click',
    'right_click', 'middle_click', 'double_click', 'triple_click',
    'left_click_drag', 'left_mouse_down', 'left_mouse_up', 'mouse_move',
    'cursor_position', 'key', 'hold_key', 'type', 'scroll', 'wait',
    'screenshot', 'zoom');
var
  I: Integer;
begin
  Result := False;
  for I := Low(CComputerTools) to High(CComputerTools) do
    if SameText(AName, CComputerTools[I]) then
      Exit(True);
end;

procedure TAiClaudeChat.DoCallFunction(ToolCall: TAiToolsFunction);
var
  LScreenshot: TAiMediaFile;
begin
  // 0. Claude native Computer Use. With computer_toolset_20260801 the name of the
  //    tool IS the action (left_click, key, scroll, zoom...), so it is dispatched
  //    by name. cap_ComputerUse is required so that generic names like 'type'
  //    or 'wait' do not hijack user functions with the same name.
  if IsClaudeComputerToolName(ToolCall.Name) and
     (cap_ComputerUse in ModelConfig.ModelCaps) and
     Assigned(ChatTools.ComputerUseTool) then
  begin
    if Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall);

    if ToolCall.Response = '' then
    begin
      LScreenshot := nil;
      try
        ChatTools.ComputerUseTool.TranslateClaudeToolCall(ToolCall);
        ToolCall.Response := ChatTools.ComputerUseTool.ProcessToolCall(ToolCall, LScreenshot);
        if Assigned(LScreenshot) then
          // The screenshot must go in ToolCall.MediaFiles: ParseChat copies it to
          // ToolMsg ('user' + tool_use_id) which is serialized as tool_result with
          // image block. (Before it went to ResMsg —assistant message— and never
          // reached the model, leaving Claude "blind".)
          ToolCall.MediaFiles.Add(LScreenshot);
      except
        on E: Exception do
        begin
          FreeAndNil(LScreenshot);
          ToolCall.Response := Format('{"output":"error: %s","url":"%s"}',
            [E.Message, ChatTools.ComputerUseTool.CurrentUrl]);
        end;
      end;
    end;
    Exit;
  end;

  // ---------------------------------------------------------------------------
  // 1. Intercept BASH / SHELL Tool
  // ---------------------------------------------------------------------------
  if (ToolCall.Name = 'bash') then
  begin
    // A. Priority: User Event (OnCallToolFunction)
    // Allows the programmer to intercept, modify or block the command before executing it.
    if Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall);

    // B. Automatic Execution (TAiShell Component)
    // If the user did not fill the response in the previous event and we have the component:
    if (ToolCall.Response = '') and Assigned(ChatTools.ShellTool) then
    begin
      // Ensure it is active
      if not ChatTools.ShellTool.Active then
        ChatTools.ShellTool.Active := True;

      // Execute the command in the persistent session
      ToolCall.Response := ChatTools.ShellTool.Execute(ToolCall.Id, ToolCall.Arguments);
    end;

    // If there is no component or event, Claude will receive an empty response or error,
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
      // Save into the MediaFile object
      MemStream.Position := 0;
      aMediaFile.Content.CopyFrom(MemStream, 0);
      aMediaFile.Content.Position := 0;

      // The REAL name that the code gave the file is in the metadata
      // (GET files/{id} -> "filename"). The heuristic that deduces it from the
      // Python code often fails and leaves "generated_file_<id>.ext". An extra GET
      // per file is negligible compared to execution; if it fails, the
      // heuristic and the Content-Type fallback below remain.
      try
        var MetaRes := Client.Get(Url + 'files/' + aMediaFile.IdFile, nil, Headers);
        if MetaRes.StatusCode = 200 then
        begin
          var jMeta := TJSONObject.ParseJSONValue(MetaRes.ContentAsString) as TJSONObject;
          if Assigned(jMeta) then
          try
            var RealName := jMeta.GetValue<string>('filename', '');
            // Only the name: never a sandbox path.
            var SlashPos := RealName.LastDelimiter('/\');
            if SlashPos >= 0 then
              RealName := RealName.Substring(SlashPos + 1);
            if RealName <> '' then
              aMediaFile.FileName := RealName;
          finally
            jMeta.Free;
          end;
        end;
      except
        // without metadata: the heuristic name is preserved
      end;

      // Use HTTP Content-Type header to fix extension when filename is a .bin fallback
      var ContentType := Res.GetHeaderValue('Content-Type');
      // Strip charset/boundary suffix: "audio/wav; charset=utf-8" → "audio/wav"
      var SemiPos := Pos(';', ContentType);
      if SemiPos > 0 then
        ContentType := Trim(Copy(ContentType, 1, SemiPos - 1));
      if (ContentType <> '') and
         (not SameText(ContentType, 'application/octet-stream')) and
         (aMediaFile.FileName.EndsWith('.bin') or aMediaFile.FileName.IsEmpty) then
      begin
        var Ext := GetFileExtensionFromMimeType(ContentType);
        if Ext <> '' then
        begin
          if aMediaFile.FileName.IsEmpty then
            aMediaFile.FileName := aMediaFile.IdFile + '.' + Ext
          else
            aMediaFile.FileName := ChangeFileExt(aMediaFile.FileName, '.' + Ext);
        end;
      end;

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
