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

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


// --------- CHANGES --------------------
// 29/08/2024 - Add handling of response_format = json_schema
// 04/11/2024 - Adds handling of detail as a property in mediafile
// 04/11/2024 - Adds handling of TAiChat.Stream_Usage - Usage statistics in OpenAi stream mode



// https://platform.openai.com/docs/guides/tools-code-interpreter

unit uMakerAi.Chat;

interface

uses
  System.SyncObjs,
  System.SysUtils, System.Classes, System.Generics.Collections, System.StrUtils,
  System.Threading, System.TypInfo, System.Types, System.Net.Mime,
  System.NetConsts, System.NetEncoding, System.Net.URLClient,
  System.Net.HttpClient, System.Net.HttpClientComponent, System.JSON, Rest.JSON, uMakerAi.Chat.Messages,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}
  uMakerAi.Tools.Functions, uMakerAi.Core, uMakerAi.Utils.CodeExtractor, uMakerAi.Tools.Shell, uMakerAi.Tools.TextEditor, uMakerAi.Tools.ComputerUse, uMakerAi.Chat.Tools, uMakerAi.Chat.Sanitizer, uMakerAi.Memory.Types,
  uMakerAi.Telemetry;

type

  TAiChatResponseFormat = (tiaChatRfText, tiaChatRfJson, tiaChatRfJsonSchema);

  TAiChatMode = (cmConversation, // Dialogue mode (Intelligent Orchestration)
    cmImageGeneration, // Force Image Generation
    cmVideoGeneration, // Force Video Generation
    cmSpeechGeneration, // Force Text to Speech (TTS)
    cmTranscription, // Force Transcription
    cmWebSearch, // Force Web Search
    cmReportGeneration, // Force Report Generation (PDF, HTML, XLSX, etc.)
    cmSmartDispatch    // Intelligent dispatch for models without function calling
    );

  TAiChatOnDataEvent = procedure(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: String) of object;
  TAiChatOnBeforeSendEvent = procedure(const Sender: TObject; var aMsg: TAiChatMessage) of object;
  TAiChatOnInitChatEvent = procedure(const Sender: TObject; aRole: String; Var aText: String; Var aMemory: TJSonObject) of object;
  TAiChatOnMediaFileEvent = Procedure(Const Sender: TObject; Prompt: String; MediaFile: TAiMediaFile; aNativeInputFiles: TAiFileCategories; Var Respuesta: String; Var aProcesado: Boolean) of object;
  TAiChatOnProcessResponseEvent = procedure(const Sender: TObject; LastMsg, ResMsg: TAiChatMessage; var Response: String) of object;
  TAiModelProgressEvent = procedure(Sender: TObject; Status: string; Completed, Total: Int64) of object; // Fired when there are long processes

  // Callback event when the chat tools tool is used
  TOnCallToolFunction = Procedure(Sender: TObject; AiToolCall: TAiToolsFunction) of object;

  TAiSanitizeAction = (saBlock, saAllow, saAllowWrapped);
  TAiSanitizeEvent = procedure(Sender: TObject; const AResult: TSanitizeResult; var AAction: TAiSanitizeAction) of object;
  // Input guardrail: AAction arrives in saBlock; the app can allow or wrap
  TAiPromptGuardEvent = procedure(Sender: TObject; const AVerdict: TAiPromptVerdict; var AAction: TAiSanitizeAction) of object;

  // Groups all chat tools into a single persistent object.
  // Assigned to TAiChat.ChatTools and TAiChatConnection.ChatTools.
  // FOwner is TComponent for compatibility with both.
  TAiChatTools = class(TPersistent)
  private
    FOwner: TComponent;
    FOnChange: TNotifyEvent;
    FSpeechTool: TAiSpeechToolBase;
    FImageTool: TAiImageToolBase;
    FVideoTool: TAiVideoToolBase;
    FWebSearchTool: TAiWebSearchToolBase;
    FVisionTool: TAiVisionToolBase;
    FPdfTool: TAiPdfToolBase;
    FReportTool: TAiReportToolBase;
    FShellTool: TAiShell;
    FTextEditorTool: TAiTextEditorTool;
    FComputerUseTool: TAiComputerUseTool;
    FDispatchClassifier: TAiDispatchClassifierBase;
    FPromptGuard: TAiPromptGuardBase;
    procedure SetSpeechTool(const Value: TAiSpeechToolBase);
    procedure SetImageTool(const Value: TAiImageToolBase);
    procedure SetVideoTool(const Value: TAiVideoToolBase);
    procedure SetWebSearchTool(const Value: TAiWebSearchToolBase);
    procedure SetVisionTool(const Value: TAiVisionToolBase);
    procedure SetPdfTool(const Value: TAiPdfToolBase);
    procedure SetReportTool(const Value: TAiReportToolBase);
    procedure SetShellTool(const Value: TAiShell);
    procedure SetTextEditorTool(const Value: TAiTextEditorTool);
    procedure SetComputerUseTool(const Value: TAiComputerUseTool);
    procedure SetDispatchClassifier(const Value: TAiDispatchClassifierBase);
    procedure SetPromptGuard(const Value: TAiPromptGuardBase);
    procedure Changed;
  public
    constructor Create(AOwner: TComponent);
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation);
    // Notifies the owner (e.g., TAiChatConnection.ChatToolsChanged) when it changes
    // any tool, to propagate the mutation to the live TAiChat.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  published
    property SpeechTool: TAiSpeechToolBase read FSpeechTool write SetSpeechTool;
    property ImageTool: TAiImageToolBase read FImageTool write SetImageTool;
    property VideoTool: TAiVideoToolBase read FVideoTool write SetVideoTool;
    property WebSearchTool: TAiWebSearchToolBase read FWebSearchTool write SetWebSearchTool;
    property VisionTool: TAiVisionToolBase read FVisionTool write SetVisionTool;
    property PdfTool: TAiPdfToolBase read FPdfTool write SetPdfTool;
    property ReportTool: TAiReportToolBase read FReportTool write SetReportTool;
    property ShellTool: TAiShell read FShellTool write SetShellTool;
    property TextEditorTool: TAiTextEditorTool read FTextEditorTool write SetTextEditorTool;
    property ComputerUseTool: TAiComputerUseTool read FComputerUseTool write SetComputerUseTool;
    // cmSmartDispatch: quick classifier that replaces step 1 with LLM
    // (e.g., TAiJevDispatchClassifier). If it doesn't decide, the LLM is used as before.
    property DispatchClassifier: TAiDispatchClassifierBase read FDispatchClassifier write SetDispatchClassifier;
    // Input guardrail: checks the user message before the LLM
    // (e.g., TAiJevPromptGuard). Runs after the regex sanitizer.
    property PromptGuard: TAiPromptGuardBase read FPromptGuard write SetPromptGuard;
  end;

  // ── TTS Parameters (Text-to-Speech) ─────────────────────────────────────────
  TAiTtsParams = class(TPersistent)
  private
    FVoice: String;
    FVoiceFormat: String;
    FLanguage: String;
    procedure SetVoice(const Value: String);
    procedure SetVoiceFormat(const Value: String);
    procedure SetLanguage(const Value: String);
  public
    procedure Assign(Source: TPersistent); override;
  published
    property Voice: String read FVoice write SetVoice;
    property VoiceFormat: String read FVoiceFormat write SetVoiceFormat;
    property Language: String read FLanguage write SetLanguage;
  end;

  // ── Transcription Parameters (STT) ───────────────────────────────────────────
  TAiTranscriptionParams = class(TPersistent)
  private
    FLanguage: String;
    FResponseFormat: String;
    FTimestampGranularities: String;
    procedure SetLanguage(const Value: String);
    procedure SetResponseFormat(const Value: String);
    procedure SetTimestampGranularities(const Value: String);
  public
    procedure Assign(Source: TPersistent); override;
  published
    property Language: String read FLanguage write SetLanguage;
    property ResponseFormat: String read FResponseFormat write SetResponseFormat;
    property TimestampGranularities: String read FTimestampGranularities write SetTimestampGranularities;
  end;

  // ── Image Generation Parameters ─────────────────────────────────────────
  TAiImageGenParams = class(TPersistent)
  private
    FParams: TStrings;
    FResolution: TAiMediaResolution;
    procedure SetParams(const Value: TStrings);
    procedure SetResolution(const Value: TAiMediaResolution);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Params: TStrings read FParams write SetParams;
    property Resolution: TAiMediaResolution read FResolution write SetResolution;
  end;

  // ── Video Generation Parameters ──────────────────────────────────────────
  TAiVideoGenParams = class(TPersistent)
  private
    FParams: TStrings;
    FResolution: TAiMediaResolution;
    procedure SetParams(const Value: TStrings);
    procedure SetResolution(const Value: TAiMediaResolution);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Params: TStrings read FParams write SetParams;
    property Resolution: TAiMediaResolution read FResolution write SetResolution;
  end;

  // ── Web Search Parameters ────────────────────────────────────────────────────
  TAiWebSearchParams = class(TPersistent)
  private
    FParams: TStrings;
    procedure SetParams(const Value: TStrings);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Params: TStrings read FParams write SetParams;
  end;

  // ── Unified model configuration (ModelCaps/SessionCaps/ThinkingLevel/Format/Tool_Active) ──

  // Fields of TAiModelConfig that the user can explicitly "pin".
  // A pinned field is NOT updated from the registry when changing models.
  TAiModelConfigField = (mcfModelCaps, mcfSessionCaps, mcfToolActive, mcfThinkingLevel);
  TAiModelConfigFields = set of TAiModelConfigField;

  TAiModelConfig = class(TPersistent)
  private
    FModelCaps: TAiCapabilities;
    FSessionCaps: TAiCapabilities;
    FThinkingLevel: TAiThinkingLevel;
    FFormat: String;
    FTool_Active: Boolean;
    FModelExtraBodyParams: String;
    FOnChange: TNotifyEvent;
    FUserFields: TAiModelConfigFields;
    procedure SetModelCaps(const Value: TAiCapabilities);
    procedure SetSessionCaps(const Value: TAiCapabilities);
    procedure SetThinkingLevel(const Value: TAiThinkingLevel);
    procedure SetFormat(const Value: String);
    procedure SetTool_Active(const Value: Boolean);
    procedure SetModelExtraBodyParams(const Value: String);
    procedure Changed;
    function GetUserConfigured: Boolean;
    procedure SetUserConfigured(const Value: Boolean);
  public
    constructor Create;
    procedure Assign(Source: TPersistent); override;
    // Applies registry params (strings 'ModelCaps', 'SessionCaps',
    // 'Tool_Active', 'ThinkingLevel') ONLY on fields that the user has not
    // explicitly set. Does not mark fields nor triggers OnChange: it is the channel
    // automatic. It is the ONLY way by which the registry reaches these 4
    // fields (v3.5: they no longer travel via Params/RTTI in TAiChatConnection).
    procedure ApplyAutoParams(AParams: TStrings);
    // Parsers from registry strings to native type
    class function StringToCaps(const S: String): TAiCapabilities; static;
    class function StringToThinkingLevel(const S: String): TAiThinkingLevel; static;
    // Notifies the owner (e.g., TAiChatConnection.ModelConfigChanged) when it changes
    // any capability/param, so that it can propagate the change to the real TAiChat.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Fields explicitly set by the user (Object Inspector or code).
    // The setters mark their field automatically; ApplyAutoParams respects them.
    property UserFields: TAiModelConfigFields read FUserFields write FUserFields;
    // True if any field is set. Assigning False clears all (returns to
    // registry on next refresh); True sets all.
    property UserConfigured: Boolean read GetUserConfigured write SetUserConfigured;
  published
    property ModelCaps: TAiCapabilities read FModelCaps write SetModelCaps;
    property SessionCaps: TAiCapabilities read FSessionCaps write SetSessionCaps;
    property ThinkingLevel: TAiThinkingLevel read FThinkingLevel write SetThinkingLevel default tlDefault;
    property Tool_Active: Boolean read FTool_Active write SetTool_Active default True;
    property Format: String read FFormat write SetFormat;
    // JSON literal (object) shallow merged into the request body before serializing.
    // Useful for vendor-specific params outside the OpenAI standard:
    //   Qwen3/llama.cpp -> {"chat_template_kwargs":{"enable_thinking":false}}
    //   llama.cpp       -> {"cache_prompt":true}
    //   Ollama          -> {"think":false}
    // Empty or invalid JSON = no effect. Client wins on key collisions.
    property ModelExtraBodyParams: String read FModelExtraBodyParams write SetModelExtraBodyParams;
  end;

  TAiChat = class(TComponent, IAiToolContext)
  Private
    FOwner: TObject;
    FApiKey: String;
    FSeed: Integer;
    FTool_choice: string;
    FN: Integer;
    FTop_p: Double;
    FLogprobs: Boolean;
    FFrequency_penalty: Double;
    FStop: string;
    FLogit_bias: String;
    FTemperature: Double;
    FPresence_penalty: Double;
    FUser: String;
    FMax_tokens: Integer;
    FAsynchronous: Boolean;
    FTop_logprobs: String;
    FModel: String;
    FSystemPrompt: TStrings;
    FCompletion_tokens: Integer;
    FTotal_tokens: Integer;
    FPrompt_tokens: Integer;
    FUrl: String;
    FResponseTimeOut: Integer;
    FOnInitChat: TAiChatOnInitChatEvent;
    FMemory: TStrings;

    FAiFunctions: TAiFunctions;
    FOnProcessMediaFile: TAiChatOnMediaFileEvent;
    FJsonSchema: TStrings;
    FStream_Usage: Boolean;
    FOnError: TAiErrorEvent;
    FOnProcessResponse: TAiChatOnProcessResponseEvent;
    FK: Integer;
    FOnProgressEvent: TAiModelProgressEvent;
    FOnReceiveThinking: TAiChatOnDataEvent;
    FTtsParams: TAiTtsParams;
    FTranscriptionParams: TAiTranscriptionParams;
    FImageGenParams: TAiImageGenParams;
    FVideoGenParams: TAiVideoGenParams;
    FWebSearchParams: TAiWebSearchParams;
    FModelConfig: TAiModelConfig;
    FOnStateChange: TAiStateChangeEvent;
    // Fired at the END of the three HTTP request finish handlers
    // (completed / error / exception). It is the last line of code that touches
    // this object in the lifecycle of an async request: the RTL only runs
    // after TBaseAsyncResult.Complete + _Release, which no longer references it.
    // An integrator freeing TAiChat from another thread MUST wait for this
    // event; doing it in OnReceiveDataEnd frees the object while the dispatch
    // async thread is still going to re-enter here (use-after-free).
    FOnHttpRequestDone: TNotifyEvent;
    FChatTools: TAiChatTools;
    FChatMode: TAiChatMode;
    FEnabledFeatures: TAiChatMediaSupports;
    FPdfTool: TAiPdfToolBase;
    FReportTool: TAiReportToolBase;
    // New orchestration system (v3.3) — ModelCaps/SessionCaps live in FModelConfig;
    // the root (GetModelCaps/GetSessionCaps below) delegates to it, without mirror fields.
    FNewSystemConfigured: Boolean; // True if ModelCaps/SessionCaps were explicitly assigned
    FSanitizerActive: Boolean;
    FOnSanitize: TAiSanitizeEvent;
    FOnPromptGuard: TAiPromptGuardEvent;
    FPersistentMemory:  TAiPersistentMemoryBase;
    FMemoryTokenBudget: Integer;
    FAutoStoreMemories: Boolean;

    procedure SetPersistentMemory(AValue: TAiPersistentMemoryBase);
    procedure SetApiKey(const Value: String);
    procedure SetFrequency_penalty(const Value: Double);
    procedure SetLogit_bias(const Value: String);
    procedure SetLogprobs(const Value: Boolean);
    procedure SetMax_tokens(const Value: Integer);
    procedure SetN(const Value: Integer);
    procedure SetPresence_penalty(const Value: Double);
    procedure SetResponse_format(const Value: TAiChatResponseFormat);
    procedure SetSeed(const Value: Integer);
    procedure SetStop(const Value: string);
    procedure SetTemperature(const Value: Double);
    procedure SetTool_choice(const Value: string);
    function GetTool_choice: string;
    procedure SetTop_p(const Value: Double);
    procedure SetUser(const Value: String);
    procedure SetAsynchronous(const Value: Boolean);
    procedure SetTop_logprobs(const Value: String);
    procedure SetOnReceiveDataEvent(const Value: TAiChatOnDataEvent);
    procedure SetOnReceiveDataEnd(const Value: TAiChatOnDataEvent);
    procedure SetModel(const Value: String);
    procedure SetSystemPrompt(const Value: TStrings);
    procedure SetOnAddMessage(const Value: TAiChatOnDataEvent);
    procedure SetOnCallToolFunction(const Value: TOnCallToolFunction);
    function GetTool_Active: Boolean;
    procedure SetTool_Active(const Value: Boolean);
    procedure SetOnBeforeSendMessage(const Value: TAiChatOnBeforeSendEvent);
    procedure SetCompletion_tokens(const Value: Integer);
    procedure SetPrompt_tokens(const Value: Integer);
    procedure SetTotal_tokens(const Value: Integer);
    procedure SetUrl(const Value: String);
    procedure SetLastError(const Value: String);
    procedure SetResponseTimeOut(const Value: Integer);
    procedure SetOnInitChat(const Value: TAiChatOnInitChatEvent);
    procedure SetMemory(const Value: TStrings);
    procedure SetJsonSchema(const Value: TStrings);

    procedure SetAiFunctions(const Value: TAiFunctions);
    procedure SetOnProcessMediaFile(const Value: TAiChatOnMediaFileEvent);
    procedure SetStream_Usage(const Value: Boolean);
    procedure SetOnError(const Value: TAiErrorEvent);
    procedure SetOnProcessResponse(const Value: TAiChatOnProcessResponseEvent);
    function GetApiKey: String;
    procedure SetK(const Value: Integer);
    procedure SetOnProgressEvent(const Value: TAiModelProgressEvent);
    procedure SetOnReceiveThinking(const Value: TAiChatOnDataEvent);
    procedure SetThinking_tokens(const Value: Integer);
    procedure SetCached_tokens(const Value: Integer);
    procedure SetSanitizerActive(const Value: Boolean);
    procedure SetOnSanitize(const Value: TAiSanitizeEvent);
    procedure SetEnabledFeatures(const Value: TAiChatMediaSupports);
    // New orchestration system (v3.3)
    function GetModelCaps: TAiCapabilities;
    function GetSessionCaps: TAiCapabilities;
    procedure SetModelCaps(const Value: TAiCapabilities);
    procedure SetSessionCaps(const Value: TAiCapabilities);
    procedure EnsureNewSystemConfig;
    //function LegacyToModelCaps: TAiCapabilities;
    //function LegacyToSessionCaps: TAiCapabilities;
    //function RunLegacy(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
    function RunNew(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
    function FileTypeInModelCaps(ACategory: TAiFileCategory): Boolean;

  Private
    // Async request in flight: turned off when data arrives and turned on when
    // the HTTP client finishes (completed, error or exception). The destructor
    // waits for it: before, freeing the chat right after OnReceiveDataEnd raced with
    // OnRequestCompletedEvent (which runs on the HTTP thread) for FCurrentPostStream and
    // caused an intermittent 'Invalid pointer operation'.
    FRequestDone: TEvent;
    // Fixed layer between the HTTP client and the virtual methods (drivers override them)
    // : marks the start and end of the request for all equally
    procedure ClientReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
    procedure ClientRequestCompleted(const Sender: TObject; const aResponse: IHTTPResponse);
    procedure ClientRequestError(const Sender: TObject; const AError: string);
    procedure ClientRequestException(const Sender: TObject; const AError: Exception);
    procedure WaitPendingRequest;
  Protected
    FClient: TNetHTTPClient;
    FTmpRole: String;
    FTmpResponseText: String;
    FTmpResponseText1: String;
    FAbort: Boolean;
    FBusy: Boolean;
    FTools: TStrings;
    FLastContent: String;
    FLastReasoning: String;  // Accumulates reasoning_content during SSE streaming
    // Real usage seen in the SSE chunks, to inject it into the synthetic close
    // of the stream. Protected and not private: drivers that reimplement their own
    // SSE handler (DeepSeek) must be able to fill them, or usage comes out as zero.
    FStreamPromptTokens: Integer;     // Tokens captured from streaming usage chunks (reset after each [DONE])
    FStreamCompletionTokens: Integer;
    // The COMPLETE usage block of the last chunk that brought it (reset after [DONE]).
    // With only prompt/completion, prompt_tokens_details.cached_tokens were lost,
    // prompt_cache_hit_tokens and completion_tokens_details.reasoning_tokens: in
    // streaming they never reached ParseChat, and in xAI (reasoning apart from
    // completion, billed) that was most of the cost.
    FStreamUsageJSON: string;
    // Real provider finish_reason, seen in the last chunk with choices.
    // The synthetic close fabricated a fixed 'stop', so a response
    // cut off by max_tokens was presented to the consumer as a clean finish.
    FStreamFinishReason: String;
    FLastPrompt: String;
    FLastError: String;
    FRunSpan: TAiSpan; // Telemetry: span of the current turn (nil = no active telemetry)
    FMessages: TAiChatMessages;
    FResponse_format: TAiChatResponseFormat;
    FResponse: TStringStream;
    FOnReceiveDataEvent: TAiChatOnDataEvent;
    FOnReceiveDataEnd: TAiChatOnDataEvent;
    FOnAddMessage: TAiChatOnDataEvent;
    FOnCallToolFunction: TOnCallToolFunction;
    FOnBeforeSendMessage: TAiChatOnBeforeSendEvent;
    FTmpToolCallBuffer: TObjectDictionary<Integer, TJSonObject>;
    FLastExecutedToolsJSON: string; // Groq code_interpreter: executed_tools top-level field
    FCurrentPostStream: TStringStream;
    // ISSUE #100: deferred tool-calling continuation in async mode.
    // It is set in ParseChat and executed in OnRequestCompletedEvent to NOT re-enter
    // THTTPClient from its own receive callback (avoids the AV in
    // THTTPClient.ExecuteHTTPInternal when freeing the FSourceStream of the in-flight request).
    FPendingToolRun: Boolean;
    FThinking_tokens: Integer;
    FCached_tokens: Integer;
    // Component-level cache WRITE token counter, twin of
    // FCached_tokens (read). Drivers that support prompt caching ACCUMULATE it
    // per round just like FPrompt_tokens, so that a tool-calling loop does not
    // lose the intermediate rounds. See TAiClaudeChat.ParseChat.
    FCache_write_tokens: Integer;
    FCacheContext: Boolean; // portable flag: cache the stable context (system + tools)

    // Returns the file types that the model natively accepts (derived from ModelConfig.ModelCaps)
    function GetModelInputFileTypes: TAiFileCategories;

    // Parses the JsonSchema property for Response_format=json_schema. Accepts the
    // pure schema or the full wrapper {name, strict, schema}; returns the inner schema
    // (caller's property) and extracts name/strict if they come in the wrapper.
    // Throws a clear exception if JsonSchema is empty or not a JSON object —
    // emitting only {"type":"json_schema"} guarantees a cryptic remote 400.
    function ParseJsonSchemaProperty(var aSchemaName: string; var aStrict: Boolean): TJSonObject;

    Procedure OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean); Virtual;

    // Extension for drivers with delta.content as a typed array (e.g., Mistral magistral).
    // The base does nothing; drivers with a non-standard format override it.
    procedure ParseDeltaContentArray(AContentArr: TJSonArray; jObj: TJSonObject); Virtual;

    Procedure OnRequestErrorEvent(const Sender: TObject; const AError: string); Virtual;
    Procedure OnRequestExceptionEvent(const Sender: TObject; const AError: Exception); Virtual;
    Procedure OnRequestCompletedEvent(const Sender: TObject; const aResponse: IHTTPResponse); Virtual;

    Function InternalAddMessage(aPrompt, aRole: String; aToolCallId: String; aFunctionName: String): TAiChatMessage; Overload; Virtual;
    Function InternalAddMessage(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage; Overload; Virtual;
    Function InternalAddMessage(aMsg: TAiChatMessage): TAiChatMessage; Overload; Virtual;

    function InternalRunSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunImageVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunWebSearch(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunReport(ResMsg, AskMsg: TAiChatMessage): String; Virtual;

    // SmartDispatch helpers (cmSmartDispatch)
    procedure InternalRunSmartDispatch(ResMsg, AskMsg: TAiChatMessage);
    function BuildSmartDispatchPrompt: String;
    procedure ParseSmartDispatchResponse(const AResponse: String; out ATag, AContent: String);
    // Tags that SmartDispatch can use: those of the assigned tools + CHAT
    function SmartDispatchTags: TArray<String>;
    // Pass 1 with ChatTools.DispatchClassifier. '' = did not decide (use the LLM)
    function ClassifySmartDispatch(const APrompt: String): String;
    // Pass 2 for a tool tag (IMAGEGEN, VIDEOGEN, TTS, WEBSEARCH)
    procedure RunSmartDispatchTool(const ATag, AContent: String; ResMsg, AskMsg: TAiChatMessage);

    Function InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunPDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;

    // Native implementations per driver (Template Method hooks)
    function InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeWebSearch(ResMsg, AskMsg: TAiChatMessage): String; Virtual;
    function InternalRunNativeReport(ResMsg, AskMsg: TAiChatMessage): String; Virtual;

    // Initializes the completions json; it is extracted separately because it is complex
    Function InitChatCompletions: String; Virtual;

    // Model families that only accept default sampling: they reject with
    // 400 any temperature/top_p/penalties, even temperature:0 (verified
    // Aug/2026 with gpt-5.6-luna on Azure; o1*/o3*/o4* have the same restriction)
    Function ModelRequiresDefaultSampling(Const aModel: String): Boolean; Virtual;
    // Families that require max_completion_tokens instead of max_tokens (gpt-5*, o1*/o3*/o4*)
    Function ModelUsesMaxCompletionTokens(Const aModel: String): Boolean; Virtual;
    // Extracts error.param from a 400 with code unsupported_parameter/unsupported_value ('' if not applicable)
    Function ExtractUnsupportedParam(Const aErrorBody: String): String;
    // Removes the rejected parameter from the body (max_tokens is renamed to
    // max_completion_tokens); if there is no change, returns the original body
    Function RemoveUnsupportedParamFromBody(Const aBody, aParam: String): String;

    // Shallow-merges ModelConfig.ModelExtraBodyParams onto AJSONObject just before
    // serializing. Silent if empty or invalid JSON. Drivers with
    // their own InitChatCompletions must invoke it before the final ToJSON.
    Procedure ApplyExtraBodyParams(AJSONObject: TJSonObject);

    Procedure ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage); Virtual;
    procedure ParseJsonTranscript(jObj: TJSonObject; ResMsg: TAiChatMessage; aMediaFile: TAiMediaFile);
    // Groq code_interpreter: downloads files from 'executed_tools' and adds them to ResMsg.MediaFiles
    procedure ProcessExecutedTools(const AExecutedToolsJSON: string; ResMsg: TAiChatMessage); virtual;
    // Streaming: combines the executed_tools of a delta by 'index' with those already
    // accumulated in FLastExecutedToolsJSON (new fields overwrite old ones)
    procedure MergeStreamExecutedTools(ADeltaTools: TJSonArray);

    Function ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions; Virtual; // Gets the list of functions from the response JSON in synchronous mode
    Procedure DoCallFunction(ToolCall: TAiToolsFunction); Virtual;
    function GetTools(aToolFormat: TToolFormat): TStrings; virtual;
    Function PrepareSystemMsg: String; Virtual; // Creates the first chat message for system, to configure the assistant
    Procedure DoProcessMediaFile(aPrompt: String; aAiMediaFile: TAiMediaFile; Var Respuesta: String; Var Procesado: Boolean);
    Function AddMessageAndRun(aPrompt, aRole: String; aToolCallId: String; aFunctionName: String): String; Overload;
    // Implementation of IAiToolContext
    procedure DoData(Msg: TAiChatMessage; const Role, Text: string; aResponse: TJSonObject = nil);
    procedure DoDataEnd(Msg: TAiChatMessage; const Role, Text: string; aResponse: TJSonObject = nil);
    function GetAsynchronous: Boolean;

    procedure DoError(const ErrorMsg: string; E: Exception); virtual;
    Procedure DoProcessResponse(aLastMsg, aResMsg: TAiChatMessage; var aResponse: String);
    procedure DoStateChange(State: TAiChatState; const Description: string = '');

    procedure Notification(AComponent: TComponent; Operation: TOperation); Override;
  Public
    Constructor Create(Sender: TComponent); Override;
    Destructor Destroy; Override;
    Function AddMessageAndRun(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String; Overload;
    Function AddMessageAndRunMsg(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage; Overload;

    Function AddMessage(aPrompt, aRole: String): TAiChatMessage; // Creates a message and adds it to the conversation
    Function NewMessage(aPrompt, aRole: String): TAiChatMessage; // Creates a message but does not add it to the conversation
    Function Run(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage = Nil): String; Virtual;
    Function GetLastMessage: TAiChatMessage;
    Function RemoveMesage(Msg: TAiChatMessage): Boolean; Overload;
    Function RemoveMesage(IdMsg: Integer): Boolean; Overload;
    Procedure AddToMemory(Key, Value: String);
    Procedure RemoveFromMemory(Key: String);
    Procedure NewChat; Virtual;
    Procedure Abort;
    Class Function GetModels(aApiKey: String; aUrl: String = ''): TStringList; Overload; virtual;
    Function GetModels: TStringList; Overload; Virtual;
    Function GetMessages: TJSonArray; Virtual;

    Function PublicChatToSend: String;

    Function FileCategoriesToString(const ACategories: TAiFileCategories): string;
    Function StringToFileCategories(const AValue: string): TAiFileCategories;

    Function UploadFile(aMediaFile: TAiMediaFile): String; Virtual;
    Function DownLoadFile(aMediaFile: TAiMediaFile): String; Virtual;
    Function CheckFileState(aMediaFile: TAiMediaFile): String; Virtual;
    Function DeleteFile(aMediaFile: TAiMediaFile): String; Virtual;
    function RetrieveFile(aFileId: string): TAiMediaFile; virtual;
    function RetrieveFileList: TAiMediaFiles; virtual;
    Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer = 3600): String; Virtual;

    class function GetDriverName: string; virtual; abstract;
    class procedure RegisterDefaultParams(Params: TStrings); virtual; abstract;
    class function CreateInstance(Sender: TComponent): TAiChat; virtual; abstract;

    Property Messages: TAiChatMessages read FMessages;
    Property LastError: String read FLastError write SetLastError;
    // Backward-compatible shortcut for drivers (points to FModelConfig.FTool_Active)
    Property Tool_Active: Boolean read GetTool_Active write SetTool_Active;
    // Backward-compatible code shortcuts (point to FModelConfig.ModelCaps/SessionCaps).
    // Not published: the visible path in the Object Inspector is ModelConfig.ModelCaps/SessionCaps
    // (single, avoids the confusing root+ModelConfig duplicate). They remain assignable in code.
    Property ModelCaps: TAiCapabilities read GetModelCaps write SetModelCaps;
    Property SessionCaps: TAiCapabilities read GetSessionCaps write SetSessionCaps;
    // ── State properties (read-only at runtime) ─────────────────────────────────────────
    Property Busy: Boolean Read FBusy;
    Property LastPrompt: String Read FLastPrompt;
    Property LastContent: String Read FLastContent;
    // ── Completions parameters (not DFM-streamed) ───────────────────────────────────────
    Property Logit_bias: String read FLogit_bias write SetLogit_bias;
    Property Logprobs: Boolean read FLogprobs write SetLogprobs;
    Property N: Integer read FN write SetN;
    Property Presence_penalty: Double read FPresence_penalty write SetPresence_penalty;
    Property Prompt_tokens: Integer read FPrompt_tokens write SetPrompt_tokens;
    Property Seed: Integer read FSeed write SetSeed;
    Property Stop: string read FStop write SetStop;
    Property Cached_tokens: Integer read FCached_tokens write SetCached_tokens;
    Property Cache_write_tokens: Integer read FCache_write_tokens write FCache_write_tokens;
    // Portable prompt caching flag. Enables caching of the stable context
    // (system + tools). In Claude it enables the cache_control breakpoints; in
    // providers with automatic server-side caching (OpenAI, DeepSeek, Kimi, Groq,
    // Gemini) it is a no-op because they already cache on their own.
    Property CacheContext: Boolean read FCacheContext write FCacheContext;
    Property Top_p: Double read FTop_p write SetTop_p;
    Property Total_tokens: Integer read FTotal_tokens write SetTotal_tokens;
    Property Thinking_tokens: Integer read FThinking_tokens write SetThinking_tokens;
    // True between the moment ParseChat defers a cycle continuation
    // of tool-calling and the start of the next POST (see ISSUE #100). It is consulted by
    // the integrator to distinguish "intermediate round, another response is coming" from
    // "turn finished": without this data, an OnReceiveDataEnd whose last message is
    // a tool result is ambiguous (passthrough due to StopAgenticLoop vs continuation).
    Property PendingToolRun: Boolean read FPendingToolRun;

  Published
    Property ApiKey: String read GetApiKey write SetApiKey;
    Property Model: String read FModel write SetModel;
    Property Frequency_penalty: Double read FFrequency_penalty write SetFrequency_penalty; // -2 to 2
    Property Top_logprobs: String read FTop_logprobs write SetTop_logprobs;
    Property Max_tokens: Integer read FMax_tokens write SetMax_tokens;
    Property Response_format: TAiChatResponseFormat read FResponse_format write SetResponse_format;
    Property Asynchronous: Boolean read FAsynchronous write SetAsynchronous;
    Property K: Integer read FK write SetK;
    // Defaults to 0; if 0 it is not sent, between 0 and 1
    // Property Tools: TStrings read GetTools;
    // Configured value ('auto', 'none', 'required', or JSON with one tool).
    // On turns that return tool results, a value that FORCES a
    // tool is read as 'auto': if it were resent, the model would have to call
    // another tool on every round and the agentic loop would never end.
    Property Tool_choice: string read GetTool_choice write SetTool_choice;
    Property User: String read FUser write SetUser;
    Property SystemPrompt: TStrings read FSystemPrompt write SetSystemPrompt;
    Property Completion_tokens: Integer read FCompletion_tokens write SetCompletion_tokens;
    Property LastExecutedToolsJSON: string read FLastExecutedToolsJSON;
    Property OnReceiveThinking: TAiChatOnDataEvent read FOnReceiveThinking write SetOnReceiveThinking;
    Property OnReceiveData: TAiChatOnDataEvent read FOnReceiveDataEvent write SetOnReceiveDataEvent;
    Property OnReceiveDataEnd: TAiChatOnDataEvent read FOnReceiveDataEnd write SetOnReceiveDataEnd;
    Property OnAddMessage: TAiChatOnDataEvent read FOnAddMessage write SetOnAddMessage;
    Property OnCallToolFunction: TOnCallToolFunction read FOnCallToolFunction write SetOnCallToolFunction;
    Property OnBeforeSendMessage: TAiChatOnBeforeSendEvent read FOnBeforeSendMessage write SetOnBeforeSendMessage;
    Property OnInitChat: TAiChatOnInitChatEvent read FOnInitChat write SetOnInitChat;
    Property OnProcessResponse: TAiChatOnProcessResponseEvent read FOnProcessResponse write SetOnProcessResponse;
    Property OnProgressEvent: TAiModelProgressEvent read FOnProgressEvent write SetOnProgressEvent;
    Property OnProcessMediaFile: TAiChatOnMediaFileEvent read FOnProcessMediaFile write SetOnProcessMediaFile;

    Property Url: String read FUrl write SetUrl;
    Property ResponseTimeOut: Integer read FResponseTimeOut write SetResponseTimeOut;
    Property Memory: TStrings read FMemory Write SetMemory;
    Property AiFunctions: TAiFunctions read FAiFunctions write SetAiFunctions;
    // ------ chat tools ------
    property ChatTools: TAiChatTools read FChatTools;

    Property JsonSchema: TStrings read FJsonSchema write SetJsonSchema;
    Property Stream_Usage: Boolean read FStream_Usage write SetStream_Usage;
    property ChatMode: TAiChatMode read FChatMode write FChatMode default cmConversation;

    property OnError: TAiErrorEvent read FOnError write SetOnError;
    property TtsParams: TAiTtsParams read FTtsParams;
    property TranscriptionParams: TAiTranscriptionParams read FTranscriptionParams;
    property ImageParams: TAiImageGenParams read FImageGenParams;
    property VideoParams: TAiVideoGenParams read FVideoGenParams;
    property WebSearchParams: TAiWebSearchParams read FWebSearchParams;
    property ModelConfig: TAiModelConfig read FModelConfig; // unified model configuration (v3.3)
    property OnStateChange: TAiStateChangeEvent read FOnStateChange write FOnStateChange;
    // See comment on FOnHttpRequestDone: safe point to free the object.
    property OnHttpRequestDone: TNotifyEvent read FOnHttpRequestDone write FOnHttpRequestDone;
    // v3.5: the root shortcuts ShellTool/TextEditorTool/ComputerUseTool were
    // removed — ALL tools live only in ChatTools.XxxTool
    property SanitizerActive: Boolean read FSanitizerActive write SetSanitizerActive;
    property OnSanitize: TAiSanitizeEvent read FOnSanitize write SetOnSanitize;
    // ChatTools.PromptGuard blocked a message; allows changing the action
    property OnPromptGuard: TAiPromptGuardEvent read FOnPromptGuard write FOnPromptGuard;
    property PersistentMemory:  TAiPersistentMemoryBase read FPersistentMemory write SetPersistentMemory;
    property MemoryTokenBudget: Integer    read FMemoryTokenBudget write FMemoryTokenBudget default 1500;
    property AutoStoreMemories: Boolean    read FAutoStoreMemories write FAutoStoreMemories default False;
    Property Temperature: Double read FTemperature write SetTemperature;
  end;

  // procedure Register;

var
  // ISSUE #115: debug log control. Opt-in: by default it does NOT write.
  // The integrator enables it with TAiChatConnection.EnableDebugLog or by setting this
  // global to True. MakerAiDebugLogPath empty = <TEMP>\makerai_debug.log.
  MakerAiDebugLogEnabled: Boolean = False;
  MakerAiDebugLogPath: string = '';

procedure LogDebug(const Mensaje: string);

implementation

uses uMakerAi.ParamsRegistry, System.IOUtils;

{ TAiChat }

Const
  GlOpenAIUrl = 'https://api.openai.com/v1/';

var
  GLogLock: TCriticalSection; // ISSUE #115: serializes log writes

procedure LogDebug(const Mensaje: string);
var
  FS: TFileStream;
  Bytes: TBytes;
  RutaLog, Linea: string;
begin
  // ISSUE #115: opt-in. By default does nothing (no cost or disk write).
  if not MakerAiDebugLogEnabled then
    Exit;
  try
    if MakerAiDebugLogPath <> '' then
      RutaLog := MakerAiDebugLogPath
    else
      RutaLog := TPath.Combine(TPath.GetTempPath, 'makerai_debug.log');

    // ISO timestamp with milliseconds + UTF-8 (TextFile lost lines with characters
    // outside cp1252 and is not thread-safe).
    Linea := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) + '  ' + Mensaje + sLineBreak;
    Bytes := TEncoding.UTF8.GetBytes(Linea);

    // Serialize: several async chats can call from different threads.
    GLogLock.Enter;
    try
      if TFile.Exists(RutaLog) then
        FS := TFileStream.Create(RutaLog, fmOpenReadWrite or fmShareDenyWrite)
      else
        FS := TFileStream.Create(RutaLog, fmCreate or fmShareDenyWrite);
      try
        FS.Seek(Int64(0), soEnd);
        if Length(Bytes) > 0 then
          FS.WriteBuffer(Bytes[0], Length(Bytes));
      finally
        FS.Free;
      end;
    finally
      GLogLock.Leave;
    end;
  except
    // Debug function — never propagates errors to the caller.
  end;
end;

procedure TAiChat.Abort;
begin
  FAbort := True;
end;

// --- This message is sent when it is a tool function, independent of the other two
function TAiChat.InternalAddMessage(aPrompt, aRole: String; aToolCallId: String; aFunctionName: String): TAiChatMessage;
Var
  Msg: TAiChatMessage;
begin
  Try
    // Adds the message to the list
    Msg := TAiChatMessage.Create(aPrompt, aRole, aToolCallId, aFunctionName);
    Msg.Id := FMessages.Count + 1;
    FMessages.Add(Msg);
    FLastPrompt := aPrompt;

    Result := Msg;
  Finally
  End;
end;

// ------- Method for handling normal chat messages
function TAiChat.InternalAddMessage(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;
Var
  Msg: TAiChatMessage;
  MF: TAiMediaFile;
begin

  Try
    // Adds the message to the list
    Msg := TAiChatMessage.Create(aPrompt, aRole);

    If Length(aMediaFiles) > 0 then
    Begin
      For MF in aMediaFiles do
      Begin
        If Assigned(MF) then
          Msg.AddMediaFile(MF);
      End;
    End;

    Result := InternalAddMessage(Msg);

  Finally
  End;
end;

// ------- Method for handling normal chat messages
function TAiChat.InternalAddMessage(aMsg: TAiChatMessage): TAiChatMessage;
Var
  TmpMsg: TAiChatMessage;
  MF: TAiMediaFile;
  MensajeInicial: String;
  Respuesta: String;
  Procesado: Boolean;
begin

  If Not Assigned(aMsg) then
    Raise Exception.Create('The aMsg parameter must be instantiated');

  Try

    MensajeInicial := Trim(Self.PrepareSystemMsg);

    // Begins with the initial instructions, different for each model
    If (FMessages.Count = 0) and (MensajeInicial <> '') then
    Begin

      TmpMsg := TAiChatMessage.Create(MensajeInicial, 'system');
      TmpMsg.Id := FMessages.Count + 1;
      FMessages.Add(TmpMsg);

      If Assigned(FOnAddMessage) then
        FOnAddMessage(Self, TmpMsg, Nil, 'system', MensajeInicial);
    End;

    // Adds the message to the list
    If Assigned(FMessages) and Assigned(aMsg) then
    Begin
      aMsg.Id := FMessages.Count + 1;
      FMessages.Add(aMsg);
    End;

    If Assigned(FOnAddMessage) then
    Begin
      FOnAddMessage(Self, aMsg, Nil, aMsg.Role, aMsg.Prompt);
    End;

    For MF in aMsg.MediaFiles do
    Begin
      If Assigned(MF) then
      Begin
        Procesado := False;
        DoProcessMediaFile(aMsg.Prompt, MF, Respuesta, Procesado); // Sends the file in case another specialized AI wants to process it, e.g.
        MF.Procesado := Procesado;
        MF.Transcription := Respuesta;
        // Saves the transcriptions in the MediaFiles, then builds the final response with all mediafiles
      End;
    End;

    FLastPrompt := aMsg.Prompt; // here it carries the Initial Prompt + the conversion of MediaFiles to text if the user allows it

    if Assigned(FOnAddMessage) then
      FOnAddMessage(Self, aMsg, Nil, aMsg.Role, aMsg.Prompt);

    If Assigned(FOnBeforeSendMessage) then
      FOnBeforeSendMessage(Self, aMsg);

    Result := aMsg;

  Finally
  End;
end;

function TAiChat.InternalRunCompletions(ResMsg, AskMsg: TAiChatMessage): String;
Var
  ABody: String;
  sUrl: String;
  Res: IHTTPResponse;
  FHeaders: TNetHeaders;
  jObj: TJSonObject;
  St: TStringStream;
begin

  FBusy := True; // Marks the system as busy
  FAbort := False; // Starts as not aborted
  FLastError := '';
  FLastContent := '';
  FLastReasoning := '';
  FLastPrompt := '';

  // Component variable to keep the stream alive in asynchronous calls
  St := TStringStream.Create('', TEncoding.UTF8);

  if Assigned(FTmpToolCallBuffer) then
    FTmpToolCallBuffer.Clear;

  // If the URL already includes 'chat/completions' (e.g., Azure with ?api-version=...) use it as is.
  if FUrl.Contains('chat/completions') then
    sUrl := FUrl
  else
    sUrl := FUrl + 'chat/completions';

  Try
    FHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + ApiKey)];
    FClient.ContentType := 'application/json';

    // Starts with the initial instructions and adds them every 20 messages to keep them from being forgotten

    ABody := InitChatCompletions;

    // ISSUE #112: opt-in request-body log (respects the logging mechanism #88:
    // LogDebug only emits if a log handler is assigned, with no overhead by default).
    // Benefits drivers that use this base InternalRunCompletions (GenericLLM,
    // LMStudio, Kimi, Mistral, Grok, DeepSeek): allows confirming that the body was
    // built correctly locally even if it arrives empty at the server.
    LogDebug('--Request-Body--');
    LogDebug('    ' + ABody);

    St.WriteString(ABody);
    St.Position := 0;

    FResponse.Clear;
    FResponse.Position := 0;

    Res := FClient.Post(sUrl, St, FResponse, FHeaders);

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

    FResponse.Position := 0;

    // New models with unknown restrictions (e.g., gpt-5.6 rejects temperature):
    // on a 400 unsupported_parameter/unsupported_value it is logged, the offending parameter is removed from the body, and it is retried — degradation with a warning
    // instead of silent failure. Only applies to the synchronous path.
    // (continued from above)
    If FClient.Asynchronous = False then
    Begin
      var LRetries := 0;
      While (Res.StatusCode = 400) and (LRetries < 3) do
      Begin
        var LParam := ExtractUnsupportedParam(Res.ContentAsString);
        If LParam = '' then
          Break;

        var LNewBody := RemoveUnsupportedParamFromBody(ABody, LParam);
        If LNewBody = ABody then
          Break; // the parameter was not in the body: there is nothing to retry

        LogDebug(Format('Model "%s" rejected parameter "%s" (400 unsupported); retrying without the parameter', [Model, LParam]));
        ABody := LNewBody;

        St.Size := 0;
        St.WriteString(ABody);
        St.Position := 0;
        FResponse.Clear;
        FResponse.Position := 0;

        Res := FClient.Post(sUrl, St, FResponse, FHeaders);
        if not Assigned(Res) then
          raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);
        FResponse.Position := 0;

        Inc(LRetries);
      End;
    End;

    FLastContent := '';
    FLastReasoning := '';

    If FClient.Asynchronous = False then
    Begin
      if Res.StatusCode = 200 then
      Begin

        var
        LParsed := TJSonObject.ParseJSONValue(Res.ContentAsString);
        if not(LParsed is TJSonObject) then
        begin
          LParsed.Free;
          raise Exception.CreateFmt('Error: Invalid JSON response: %s', [Res.ContentAsString]);
        end;
        jObj := TJSonObject(LParsed);
        Try
          FBusy := False;
          ParseChat(jObj, ResMsg);
          // Groq code_interpreter: extracts files from the executed_tools field (sync path)
          // compound-beta: executed_tools at the JSON root level
          // gpt-oss-20b: executed_tools nested in choices[0].message.executed_tools
          var JExecSync: TJSonValue;
          if jObj.TryGetValue('executed_tools', JExecSync) then
            ProcessExecutedTools(JExecSync.ToJSON, ResMsg)
          else
          begin
            var JChoicesSync: TJSonArray;
            if jObj.TryGetValue<TJSonArray>('choices', JChoicesSync) and (JChoicesSync.Count > 0) then
            begin
              var JMsgSync: TJSonObject;
              if TJSonObject(JChoicesSync.Items[0]).TryGetValue<TJSonObject>('message', JMsgSync) then
                if JMsgSync.TryGetValue('executed_tools', JExecSync) then
                  ProcessExecutedTools(JExecSync.ToJSON, ResMsg);
            end;
          end;
          Result := FLastContent;

        Finally
          FreeAndNil(jObj);
        End;
      End
      else
      begin
        FBusy := False;
        DoStateChange(acsError, Res.ContentAsString);
        Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
      end;
    End;
  Finally
    If FClient.Asynchronous = False then
      FreeAndNil(St)
    Else
    Begin
      FreeAndNil(FCurrentPostStream);
      FCurrentPostStream := St;
    End;
  End;
end;

function TAiChat.InternalRunImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiVisionTool;
begin
  Result := '';
  if Assigned(FChatTools.FVisionTool) and Supports(FChatTools.FVisionTool, IAiVisionTool, LTool) then
  begin
    if FChatTools.FVisionTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FVisionTool).SetContext(Self);
    DoStateChange(acsToolExecuting, 'Analyzing image with vision tool...');
    LTool.ExecuteImageDescription(aMediaFile, ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeImageDescription(aMediaFile, ResMsg, AskMsg);
end;

function TAiChat.InternalRunImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiImageTool;
begin
  Result := '';
  if Assigned(FChatTools.FImageTool) and Supports(FChatTools.FImageTool, IAiImageTool, LTool) then
  begin
    if FChatTools.FImageTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FImageTool).SetContext(Self);
    DoStateChange(acsToolExecuting, 'Generating image...');
    LTool.ExecuteImageGeneration(AskMsg.Prompt, ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeImageGeneration(ResMsg, AskMsg);
end;

function TAiChat.InternalRunImageVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiVideoTool;
begin
  Result := '';
  if Assigned(FChatTools.FVideoTool) and Supports(FChatTools.FVideoTool, IAiVideoTool, LTool) then
  begin
    if FChatTools.FVideoTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FVideoTool).SetContext(Self);
    DoStateChange(acsToolExecuting, 'Generating video...');
    LTool.ExecuteVideoGeneration(ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeVideoGeneration(ResMsg, AskMsg);
end;

function TAiChat.InternalRunPDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiPdfTool;
begin
  Result := '';
  if Assigned(FChatTools.FPdfTool) and Supports(FChatTools.FPdfTool, IAiPdfTool, LTool) then
  begin
    if FChatTools.FPdfTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FPdfTool).SetContext(Self);
    DoStateChange(acsToolExecuting, 'Analyzing PDF document...');
    LTool.ExecutePdfAnalysis(aMediaFile, ResMsg, AskMsg);
    if not Asynchronous then
      Result := aMediaFile.Transcription;
  end
  else
    Result := InternalRunNativePDFDescription(aMediaFile, ResMsg, AskMsg);
end;

function TAiChat.InternalRunSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiSpeechTool;
begin
  Result := '';
  if Assigned(FChatTools.FSpeechTool) and Supports(FChatTools.FSpeechTool, IAiSpeechTool, LTool) then
  begin
    if FChatTools.FSpeechTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FSpeechTool).SetContext(Self);
    DoStateChange(acsToolExecuting, 'Generating audio with external tool...');
    LTool.ExecuteSpeechGeneration(AskMsg.Prompt, ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeSpeechGeneration(ResMsg, AskMsg);
end;

function TAiChat.InternalRunTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiSpeechTool;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Content.Size = 0) then
    raise Exception.Create('An audio file with content is required for transcription.');
  if Assigned(FChatTools.FSpeechTool) and Supports(FChatTools.FSpeechTool, IAiSpeechTool, LTool) then
  begin
    if FChatTools.FSpeechTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FSpeechTool).SetContext(Self);
    LTool.ExecuteTranscription(aMediaFile, ResMsg, AskMsg);
    if not Asynchronous then
    begin
      if (ResMsg.Prompt = '') and (aMediaFile.Transcription <> '') then
        ResMsg.Prompt := aMediaFile.Transcription;
      Result := ResMsg.Prompt;
    end;
  end
  else
    Result := InternalRunNativeTranscription(aMediaFile, ResMsg, AskMsg);
end;

function TAiChat.InternalRunWebSearch(ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiWebSearchTool;
begin
  Result := '';
  if Assigned(FChatTools.FWebSearchTool) and Supports(FChatTools.FWebSearchTool, IAiWebSearchTool, LTool) then
  begin
    if FChatTools.FWebSearchTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FWebSearchTool).SetContext(Self);
    LTool.ExecuteSearch(AskMsg.Prompt, ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeWebSearch(ResMsg, AskMsg);
end;

function TAiChat.InternalRunReport(ResMsg, AskMsg: TAiChatMessage): String;
var
  LTool: IAiReportTool;
begin
  Result := '';
  if Assigned(FChatTools.FReportTool) and Supports(FChatTools.FReportTool, IAiReportTool, LTool) then
  begin
    if FChatTools.FReportTool is TAiCustomTool then
      TAiCustomTool(FChatTools.FReportTool).SetContext(Self);
    LTool.ExecuteReport(ResMsg, AskMsg);
    if not Asynchronous then
      Result := ResMsg.Prompt;
  end
  else
    Result := InternalRunNativeReport(ResMsg, AskMsg);
end;

function TAiChat.AddMessage(aPrompt, aRole: String): TAiChatMessage;
begin
  Result := InternalAddMessage(aPrompt, aRole, []);
end;

function TAiChat.AddMessageAndRun(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String;
begin
  // Pass the newly created message to Run: with Nil, the sanitizer and persistent memory
  // (which require Assigned(AskMsg) and Role='user') were never activated
  // through this path, which is the main API. RunNew does not re-add it (IndexOf guard).
  Result := Run(InternalAddMessage(aPrompt, aRole, aMediaFiles), Nil);
end;

function TAiChat.AddMessageAndRunMsg(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): TAiChatMessage;
begin
  if FAsynchronous = False then
  Begin
    AddMessageAndRun(aPrompt, aRole, aMediaFiles);
    Result := Self.GetLastMessage; // Returns the message
  End
  Else
    Raise Exception.Create('This function is not compatible with asynchronous mode')
end;

function TAiChat.AddMessageAndRun(aPrompt, aRole: String; aToolCallId: String; aFunctionName: String): String;
begin
  // Same criterion as the main overload: pass the message to Run.
  // The sanitizer/memory guards filter by Role='user', so
  // the 'tool' messages from this path do not activate anything improper.
  Result := Run(InternalAddMessage(aPrompt, aRole, aToolCallId, aFunctionName), Nil);
end;

{ TAiChatTools }

constructor TAiChatTools.Create(AOwner: TComponent);
begin
  inherited Create;
  FOwner := AOwner;
end;

destructor TAiChatTools.Destroy;
begin
  // Remove FOwner from the FFreeNotifies list of each external tool before
  // FOwner is destroyed. Otherwise, SpeechTool.FFreeNotifies will keep a
  // dangling pointer and will call Notification on freed memory → AV.
  if Assigned(FOwner) then
  begin
    if Assigned(FSpeechTool)     then FSpeechTool.RemoveFreeNotification(FOwner);
    if Assigned(FImageTool)      then FImageTool.RemoveFreeNotification(FOwner);
    if Assigned(FVideoTool)      then FVideoTool.RemoveFreeNotification(FOwner);
    if Assigned(FWebSearchTool)  then FWebSearchTool.RemoveFreeNotification(FOwner);
    if Assigned(FVisionTool)     then FVisionTool.RemoveFreeNotification(FOwner);
    if Assigned(FPdfTool)        then FPdfTool.RemoveFreeNotification(FOwner);
    if Assigned(FReportTool)     then FReportTool.RemoveFreeNotification(FOwner);
    if Assigned(FShellTool)      then FShellTool.RemoveFreeNotification(FOwner);
    if Assigned(FTextEditorTool) then FTextEditorTool.RemoveFreeNotification(FOwner);
    if Assigned(FComputerUseTool) then FComputerUseTool.RemoveFreeNotification(FOwner);
    if Assigned(FDispatchClassifier) then FDispatchClassifier.RemoveFreeNotification(FOwner);
    if Assigned(FPromptGuard) then FPromptGuard.RemoveFreeNotification(FOwner);
  end;
  inherited;
end;

procedure TAiChatTools.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if Operation = opRemove then
  begin
    if AComponent = FSpeechTool    then FSpeechTool    := nil;
    if AComponent = FImageTool     then FImageTool     := nil;
    if AComponent = FVideoTool     then FVideoTool     := nil;
    if AComponent = FWebSearchTool then FWebSearchTool := nil;
    if AComponent = FVisionTool    then FVisionTool    := nil;
    if AComponent = FPdfTool       then FPdfTool       := nil;
    if AComponent = FReportTool    then FReportTool    := nil;
    if AComponent = FShellTool     then FShellTool     := nil;
    if AComponent = FTextEditorTool then FTextEditorTool := nil;
    if AComponent = FComputerUseTool then FComputerUseTool := nil;
    if AComponent = FDispatchClassifier then FDispatchClassifier := nil;
    if AComponent = FPromptGuard then FPromptGuard := nil;
  end;
end;

procedure TAiChatTools.Assign(Source: TPersistent);
var
  Src: TAiChatTools;
begin
  if Source is TAiChatTools then
  begin
    Src := TAiChatTools(Source);
    SpeechTool     := Src.FSpeechTool;
    ImageTool      := Src.FImageTool;
    VideoTool      := Src.FVideoTool;
    WebSearchTool  := Src.FWebSearchTool;
    VisionTool     := Src.FVisionTool;
    PdfTool        := Src.FPdfTool;
    ReportTool     := Src.FReportTool;
    ShellTool      := Src.FShellTool;
    TextEditorTool := Src.FTextEditorTool;
    ComputerUseTool := Src.FComputerUseTool;
    DispatchClassifier := Src.FDispatchClassifier;
    PromptGuard := Src.FPromptGuard;
  end
  else
    inherited;
end;

procedure TAiChatTools.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TAiChatTools.SetSpeechTool(const Value: TAiSpeechToolBase);
begin
  if FSpeechTool <> Value then
  begin
    FSpeechTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetImageTool(const Value: TAiImageToolBase);
begin
  if FImageTool <> Value then
  begin
    FImageTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetVideoTool(const Value: TAiVideoToolBase);
begin
  if FVideoTool <> Value then
  begin
    FVideoTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetPromptGuard(const Value: TAiPromptGuardBase);
begin
  if FPromptGuard <> Value then
  begin
    FPromptGuard := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetDispatchClassifier(const Value: TAiDispatchClassifierBase);
begin
  if FDispatchClassifier <> Value then
  begin
    FDispatchClassifier := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetWebSearchTool(const Value: TAiWebSearchToolBase);
begin
  if FWebSearchTool <> Value then
  begin
    FWebSearchTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetVisionTool(const Value: TAiVisionToolBase);
begin
  if FVisionTool <> Value then
  begin
    FVisionTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetPdfTool(const Value: TAiPdfToolBase);
begin
  if FPdfTool <> Value then
  begin
    FPdfTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetReportTool(const Value: TAiReportToolBase);
begin
  if FReportTool <> Value then
  begin
    FReportTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetShellTool(const Value: TAiShell);
begin
  if FShellTool <> Value then
  begin
    FShellTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetTextEditorTool(const Value: TAiTextEditorTool);
begin
  if FTextEditorTool <> Value then
  begin
    FTextEditorTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

procedure TAiChatTools.SetComputerUseTool(const Value: TAiComputerUseTool);
begin
  if FComputerUseTool <> Value then
  begin
    FComputerUseTool := Value;
    if (Value <> nil) and Assigned(FOwner) then
      Value.FreeNotification(FOwner);
    Changed;
  end;
end;

{ TAiTtsParams }

procedure TAiTtsParams.SetVoice(const Value: String);
begin FVoice := Value; end;

procedure TAiTtsParams.SetVoiceFormat(const Value: String);
begin FVoiceFormat := Value; end;

procedure TAiTtsParams.SetLanguage(const Value: String);
begin FLanguage := Value; end;

procedure TAiTtsParams.Assign(Source: TPersistent);
var Src: TAiTtsParams;
begin
  if Source is TAiTtsParams then
  begin
    Src := TAiTtsParams(Source);
    FVoice := Src.FVoice;
    FVoiceFormat := Src.FVoiceFormat;
    FLanguage := Src.FLanguage;
  end else inherited;
end;

{ TAiTranscriptionParams }

procedure TAiTranscriptionParams.SetLanguage(const Value: String);
begin FLanguage := Value; end;

procedure TAiTranscriptionParams.SetResponseFormat(const Value: String);
begin FResponseFormat := Value; end;

procedure TAiTranscriptionParams.SetTimestampGranularities(const Value: String);
begin FTimestampGranularities := Value; end;

procedure TAiTranscriptionParams.Assign(Source: TPersistent);
var Src: TAiTranscriptionParams;
begin
  if Source is TAiTranscriptionParams then
  begin
    Src := TAiTranscriptionParams(Source);
    FLanguage := Src.FLanguage;
    FResponseFormat := Src.FResponseFormat;
    FTimestampGranularities := Src.FTimestampGranularities;
  end else inherited;
end;

{ TAiImageGenParams }

constructor TAiImageGenParams.Create;
begin
  inherited;
  FParams := TStringList.Create;
end;

destructor TAiImageGenParams.Destroy;
begin
  FParams.Free;
  inherited;
end;

procedure TAiImageGenParams.SetParams(const Value: TStrings);
begin FParams.Assign(Value); end;

procedure TAiImageGenParams.SetResolution(const Value: TAiMediaResolution);
begin FResolution := Value; end;

procedure TAiImageGenParams.Assign(Source: TPersistent);
var Src: TAiImageGenParams;
begin
  if Source is TAiImageGenParams then
  begin
    Src := TAiImageGenParams(Source);
    FParams.Assign(Src.FParams);
    FResolution := Src.FResolution;
  end else inherited;
end;

{ TAiVideoGenParams }

constructor TAiVideoGenParams.Create;
begin
  inherited;
  FParams := TStringList.Create;
end;

destructor TAiVideoGenParams.Destroy;
begin
  FParams.Free;
  inherited;
end;

procedure TAiVideoGenParams.SetParams(const Value: TStrings);
begin FParams.Assign(Value); end;

procedure TAiVideoGenParams.SetResolution(const Value: TAiMediaResolution);
begin FResolution := Value; end;

procedure TAiVideoGenParams.Assign(Source: TPersistent);
var Src: TAiVideoGenParams;
begin
  if Source is TAiVideoGenParams then
  begin
    Src := TAiVideoGenParams(Source);
    FParams.Assign(Src.FParams);
    FResolution := Src.FResolution;
  end else inherited;
end;

{ TAiWebSearchParams }

constructor TAiWebSearchParams.Create;
begin
  inherited;
  FParams := TStringList.Create;
end;

destructor TAiWebSearchParams.Destroy;
begin
  FParams.Free;
  inherited;
end;

procedure TAiWebSearchParams.SetParams(const Value: TStrings);
begin FParams.Assign(Value); end;

procedure TAiWebSearchParams.Assign(Source: TPersistent);
var Src: TAiWebSearchParams;
begin
  if Source is TAiWebSearchParams then
  begin
    Src := TAiWebSearchParams(Source);
    FParams.Assign(Src.FParams);
  end else inherited;
end;

{ TAiModelConfig }

constructor TAiModelConfig.Create;
begin
  inherited Create;
  FTool_Active := True;
  FThinkingLevel := tlDefault;
  FModelExtraBodyParams := '';
end;

procedure TAiModelConfig.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TAiModelConfig.SetModelCaps(const Value: TAiCapabilities);
begin
  if FModelCaps <> Value then
  begin
    FModelCaps := Value;
    Include(FUserFields, mcfModelCaps); // explicit configuration: the registry no longer updates this field
    Changed;
  end;
end;

procedure TAiModelConfig.SetSessionCaps(const Value: TAiCapabilities);
begin
  if FSessionCaps <> Value then
  begin
    FSessionCaps := Value;
    Include(FUserFields, mcfSessionCaps); // explicit configuration: the registry no longer updates this field
    Changed;
  end;
end;

procedure TAiModelConfig.SetThinkingLevel(const Value: TAiThinkingLevel);
begin
  if FThinkingLevel <> Value then
  begin
    FThinkingLevel := Value;
    Include(FUserFields, mcfThinkingLevel); // explicit configuration: the registry no longer updates this field
    Changed;
  end;
end;

procedure TAiModelConfig.SetFormat(const Value: String);
begin
  if FFormat <> Value then
  begin
    FFormat := Value;
    Changed;
  end;
end;

procedure TAiModelConfig.SetTool_Active(const Value: Boolean);
begin
  if FTool_Active <> Value then
  begin
    FTool_Active := Value;
    Include(FUserFields, mcfToolActive); // explicit configuration: the registry no longer updates this field
    Changed;
  end;
end;

procedure TAiModelConfig.SetModelExtraBodyParams(const Value: String);
begin
  if FModelExtraBodyParams <> Value then
  begin
    FModelExtraBodyParams := Value;
    Changed;
  end;
end;

procedure TAiModelConfig.Assign(Source: TPersistent);
var
  Src: TAiModelConfig;
begin
  if Source is TAiModelConfig then
  begin
    Src := TAiModelConfig(Source);
    FModelCaps := Src.FModelCaps;
    FSessionCaps := Src.FSessionCaps;
    FThinkingLevel := Src.FThinkingLevel;
    FFormat := Src.FFormat;
    FTool_Active := Src.FTool_Active;
    FModelExtraBodyParams := Src.FModelExtraBodyParams;
    FUserFields := Src.FUserFields;
  end
  else
    inherited;
end;

function TAiModelConfig.GetUserConfigured: Boolean;
begin
  Result := FUserFields <> [];
end;

procedure TAiModelConfig.SetUserConfigured(const Value: Boolean);
begin
  if Value then
    FUserFields := [mcfModelCaps, mcfSessionCaps, mcfToolActive, mcfThinkingLevel]
  else
    FUserFields := [];
end;

class function TAiModelConfig.StringToCaps(const S: String): TAiCapabilities;
var
  Item: String;
  OrdVal: Integer;
begin
  Result := [];
  for Item in S.Trim([' ', '[', ']']).Split([',']) do
  begin
    if Trim(Item) = '' then
      Continue;
    OrdVal := GetEnumValue(TypeInfo(TAiCapability), Trim(Item));
    if OrdVal >= 0 then
      Include(Result, TAiCapability(OrdVal));
  end;
end;

class function TAiModelConfig.StringToThinkingLevel(const S: String): TAiThinkingLevel;
var
  OrdVal: Integer;
begin
  Result := tlDefault;
  OrdVal := GetEnumValue(TypeInfo(TAiThinkingLevel), Trim(S));
  if OrdVal >= 0 then
    Result := TAiThinkingLevel(OrdVal);
end;

procedure TAiModelConfig.ApplyAutoParams(AParams: TStrings);
var
  S: String;
begin
  if not Assigned(AParams) then
    Exit;

  // Direct write to the fields: without marking UserFields and without OnChange —
  // this is the AUTOMATIC channel (registry). Deterministic semantics:
  //   field NOT pinned = registry value for the current model,
  //   or type default if the registry does not define the key.
  // The "else default" avoids stale values when changing models or unpinning
  // (same leak documented for Groq with ThinkingLevel/Format).
  if not(mcfModelCaps in FUserFields) then
  begin
    S := AParams.Values['ModelCaps'];
    if S <> '' then
      FModelCaps := StringToCaps(S)
    else
      FModelCaps := [];
  end;

  if not(mcfSessionCaps in FUserFields) then
  begin
    S := AParams.Values['SessionCaps'];
    if S <> '' then
      FSessionCaps := StringToCaps(S)
    else
      FSessionCaps := [];
  end;

  if not(mcfToolActive in FUserFields) then
  begin
    S := AParams.Values['Tool_Active'].Trim.ToLower;
    if S <> '' then
      FTool_Active := (S = 'true') or (S = '1') or (S = 'yes') or (S = 't')
    else
      FTool_Active := True; // constructor default
  end;

  if not(mcfThinkingLevel in FUserFields) then
  begin
    S := AParams.Values['ThinkingLevel'];
    if S <> '' then
      FThinkingLevel := StringToThinkingLevel(S)
    else
      FThinkingLevel := tlDefault;
  end;
end;

procedure TAiChat.AddToMemory(Key, Value: String);
begin
  FMemory.AddPair(Key, Value);
end;

function TAiChat.CheckFileState(aMediaFile: TAiMediaFile): String;
begin
  // Checks the state of a file
end;

constructor TAiChat.Create(Sender: TComponent);
begin
  inherited;
  FOwner := Sender;
  FMessages := TAiChatMessages.Create;
  FTools := TStringList.Create;
  FMemory := TStringList.Create;
  FJsonSchema := TStringList.Create;
  FSystemPrompt := TStringList.Create;
  FTmpToolCallBuffer := TObjectDictionary<Integer, TJSonObject>.Create([doOwnsValues]);
  FChatTools := TAiChatTools.Create(Self);
  FTtsParams := TAiTtsParams.Create;
  FTranscriptionParams := TAiTranscriptionParams.Create;
  FImageGenParams := TAiImageGenParams.Create;
  FVideoGenParams := TAiVideoGenParams.Create;
  FWebSearchParams := TAiWebSearchParams.Create;
  FModelConfig := TAiModelConfig.Create;

  FResponse := TStringStream.Create('', TEncoding.UTF8);
  FClient := TNetHTTPClient.Create(Self);
{$IF CompilerVersion >= 34} // ISSUE #119: SynchronizeEvents ya existe en 10.4 Sydney.
  // Without this, in 10.4 the TNetHTTPClient events run on the main thread
  // (SynchronizeEvents=True by default) and async tool calls block the UI.
  FClient.SynchronizeEvents := False;
{$ENDIF}
  FRequestDone := TEvent.Create(nil, True, True, '');
{$IF CompilerVersion >= 35}
  FClient.OnRequestException := Self.ClientRequestException;
{$ENDIF}
  FClient.OnReceiveData := Self.ClientReceiveData;
  FClient.OnRequestError := Self.ClientRequestError;
  FClient.OnRequestCompleted := Self.ClientRequestCompleted;
  FClient.ResponseTimeOut := 120000;

  FModel := 'gpt-5';
  FN := 1;
  FResponse_format := TAiChatResponseFormat.tiaChatRfText;
  FTemperature := 1;
  FUser := 'user';
  FSystemPrompt.Text := 'You are a very helpful and accommodating assistant';
  FMax_tokens := 3000;
  FUrl := GlOpenAIUrl;
  FTop_p := 1;
  FResponseTimeOut := 120000;
  FStream_Usage := False; // Sends per-token usage statistics
  FTool_choice := 'auto';
  FMemoryTokenBudget := 1500;
  FAutoStoreMemories := False;
  FPendingToolRun := False;
end;

function TAiChat.DeleteFile(aMediaFile: TAiMediaFile): String;
begin
  // Allows deleting a file previously uploaded to the llm
end;

destructor TAiChat.Destroy;
begin
  WaitPendingRequest;
  FCurrentPostStream.Free;
  FClient.Free;
  FResponse.Free;
  FTools.Free;
  FChatTools.Free;
  FTtsParams.Free;
  FTranscriptionParams.Free;
  FImageGenParams.Free;
  FVideoGenParams.Free;
  FWebSearchParams.Free;
  FModelConfig.Free;
  FMemory.Free;
  FJsonSchema.Free;
  FTmpToolCallBuffer.Free;
  FSystemPrompt.Free;
  NewChat;
  FMessages.Free;
  FRequestDone.Free;
  inherited;
end;

procedure TAiChat.ClientReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
begin
  if FClient.Asynchronous then
    FRequestDone.ResetEvent;
  OnInternalReceiveData(Sender, AContentLength, AReadCount, AAbort);
end;

procedure TAiChat.ClientRequestCompleted(const Sender: TObject; const aResponse: IHTTPResponse);
begin
  try
    OnRequestCompletedEvent(Sender, aResponse);
  finally
    FRequestDone.SetEvent;
  end;
end;

procedure TAiChat.ClientRequestError(const Sender: TObject; const AError: string);
begin
  try
    OnRequestErrorEvent(Sender, AError);
  finally
    FRequestDone.SetEvent;
  end;
end;

procedure TAiChat.ClientRequestException(const Sender: TObject; const AError: Exception);
begin
  try
    OnRequestExceptionEvent(Sender, AError);
  finally
    FRequestDone.SetEvent;
  end;
end;

procedure TAiChat.WaitPendingRequest;
var
  T0: Cardinal;
begin
  if (FRequestDone = nil) or (FRequestDone.WaitFor(0) = wrSignaled) then
    Exit;
  // The object is being freed: the user should no longer receive events, and if the
  // stream is still open it is cut off on the next chunk
  FOnReceiveDataEvent := nil;
  FOnReceiveDataEnd := nil;
  FOnReceiveThinking := nil;
  FOnError := nil;
  FOnStateChange := nil;
  FOnHttpRequestDone := nil;
  FOnAddMessage := nil;
  FOnCallToolFunction := nil;
  FAbort := True;
  T0 := TThread.GetTickCount;
  repeat
    if FRequestDone.WaitFor(50) = wrSignaled then
      Break;
    // With SynchronizeEvents (Delphi < 10.4) HTTP events run on the main
    // thread: the queue must be pumped so they arrive
    if TThread.CurrentThread.ThreadID = MainThreadID then
      CheckSynchronize(0);
  until TThread.GetTickCount - T0 > 15000;
end;

procedure TAiChat.DoCallFunction(ToolCall: TAiToolsFunction);
var
  LScreenshot: TAiMediaFile;
begin
  // Generic Computer Use bridge — activates for non-native models (cap_ComputerUse NOT in ModelCaps)
  // Works with any model that has Tool_Active=True; requires function definitions injected via
  // TAiComputerUseTool.GetFunctionDefinitions into the model's AiFunctions or system prompt.
  if Assigned(ChatTools.ComputerUseTool) and
     not (cap_ComputerUse in ModelConfig.ModelCaps) and
     MatchStr(LowerCase(ToolCall.Name),
       ['click_at', 'left_click', 'right_click', 'middle_click', 'double_click',
        'triple_click', 'type_text_at', 'key_combination', 'hold_key',
        'scroll_at', 'scroll_document', 'drag_and_drop', 'hover_at',
        'cursor_position', 'zoom', 'navigate', 'search', 'open_web_browser',
        'screenshot', 'wait_5_seconds', 'go_back', 'go_forward']) then
  begin
    if Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall);

    if ToolCall.Response = '' then
    begin
      LScreenshot := nil;
      try
        ToolCall.Response := ChatTools.ComputerUseTool.ProcessToolCall(ToolCall, LScreenshot);
        if Assigned(LScreenshot) then
        begin
          if Assigned(ToolCall.ResMsg) then
            ToolCall.ResMsg.MediaFiles.Add(LScreenshot)
          else
            LScreenshot.Free;
        end;
      except
        on E: Exception do
        begin
          FreeAndNil(LScreenshot);
          ToolCall.Response := Format('{"error": "%s"}', [E.Message]);
        end;
      end;
    end;
    Exit;
  end;

  If Assigned(AiFunctions) and AiFunctions.DoCallFunction(ToolCall) then
  Begin
    // If it executed the function
  End
  Else
  Begin // Executes the default function in the TAiChat component
    If Assigned(FOnCallToolFunction) then
      FOnCallToolFunction(Self, ToolCall)
  End;
end;

procedure TAiChat.DoData(Msg: TAiChatMessage; const Role, Text: string; aResponse: TJSonObject);
begin
  if Assigned(FOnReceiveDataEvent) then
    FOnReceiveDataEvent(Self, TAiChatMessage(Msg), aResponse, Role, Text);
end;

procedure TAiChat.DoDataEnd(Msg: TAiChatMessage; const Role, Text: string; aResponse: TJSonObject);
begin
  FBusy := False;
  if Assigned(FOnReceiveDataEnd) then
    FOnReceiveDataEnd(Self, TAiChatMessage(Msg), aResponse, Role, Text);
end;

procedure TAiChat.DoError(const ErrorMsg: string; E: Exception);
begin
  // Synchronous callers (consoles, scripts) do not have OnError assigned and
  // RunNew swallows the exception: LastError is the only way to see the detail.
  FLastError := ErrorMsg;

  DoStateChange(acsError, ErrorMsg);

  if Assigned(FOnError) then
    FOnError(Self, ErrorMsg, E, Nil);
end;

procedure TAiChat.DoProcessMediaFile(aPrompt: String; aAiMediaFile: TAiMediaFile; Var Respuesta: String; Var Procesado: Boolean);
begin
  Procesado := False;

  If Assigned(FOnProcessMediaFile) then
  Begin
    Respuesta := '';
    FOnProcessMediaFile(Self, aPrompt, aAiMediaFile, GetModelInputFileTypes, Respuesta, Procesado);
    aAiMediaFile.Procesado := Procesado;
    aAiMediaFile.Transcription := Respuesta;
  End;
end;

procedure TAiChat.DoProcessResponse(aLastMsg, aResMsg: TAiChatMessage; var aResponse: String);
begin
  // Telemetry: turn tokens (GenAI semconv). At this point ParseChat has already
  // accumulated the counters in the response message.
  if Assigned(FRunSpan) and Assigned(aResMsg) then
  begin
    AiSpanAttr(FRunSpan, 'gen_ai.usage.input_tokens', Int64(aResMsg.Prompt_tokens));
    AiSpanAttr(FRunSpan, 'gen_ai.usage.output_tokens', Int64(aResMsg.Completion_tokens));
  end;

  If Assigned(FOnProcessResponse) then
    FOnProcessResponse(Self, aLastMsg, aResMsg, aResponse);
end;

procedure TAiChat.DoStateChange(State: TAiChatState; const Description: string);
begin
  // Telemetry: acsFinished/acsAborted/acsError mark the real end of the turn,
  // both in sync and async (the streaming callback passes through here).
  if (State in [acsFinished, acsAborted, acsError]) and Assigned(FRunSpan) then
  begin
    if State = acsError then
      AiSpanEnd(FRunSpan, IfThen(Description <> '', Description, 'error'))
    else
      AiSpanEnd(FRunSpan, '');
    FRunSpan := nil;
  end;

  if Assigned(FOnStateChange) then
    FOnStateChange(Self, State, Description);
end;

function TAiChat.DownLoadFile(aMediaFile: TAiMediaFile): String;
begin

end;

function TAiChat.ExtractToolCallFromJson(jChoices: TJSonArray): TAiToolsFunctions;
Var
  jObj, Msg, jFunc: TJSonObject;
  JVal, JVal1, jValToolCall: TJSonValue;
  Fun: TAiToolsFunction;
  JToolCalls: TJSonArray;
  sType: String;
begin
  Result := TAiToolsFunctions.Create;

  For JVal1 in jChoices do
  Begin
    Msg := TJSonObject(JVal1).GetValue<TJSonObject>('message');

    If Msg.TryGetValue<TJSonValue>('tool_calls', jValToolCall) and (jValToolCall is TJSonArray) and Msg.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
    Begin
      For JVal in JToolCalls do
      Begin
        jObj := TJSonObject(JVal);
        // Some providers (Mistral) omit 'type'; in that case 'function' is assumed
        if not jObj.TryGetValue<String>('type', sType) then
          sType := 'function';
        If sType = 'function' then
        Begin
          jObj := TJSonObject(JVal);
          Fun := TAiToolsFunction.Create;
          Fun.Id := jObj.GetValue<String>('id');
          Fun.&Type := sType;

          If jObj.TryGetValue<TJSonObject>('function', jFunc) then
          Begin
            // Fun.Name := jObj.GetValue<TJSonObject>('function').GetValue<String>('name');
            Fun.Name := jFunc.GetValue<String>('name');

            Fun.Arguments := jObj.GetValue<TJSonObject>('function').GetValue<String>('arguments');
          End;

          Result.Add(Fun.Id, Fun);
        End;
      End;
    End;
  End;
end;

function TAiChat.GetApiKey: String;
begin
  // If in design mode, simply returns the value as is
  if (csDesigning in ComponentState) or (csDestroying in ComponentState) then
  begin
    Result := FApiKey;
    Exit;
  end;

  // In runtime mode
  if (FApiKey <> '') and (Copy(FApiKey, 1, 1) = '@') then
    // Returns the environment variable value, removing the '@'
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, Length(FApiKey)))
  else
    Result := FApiKey;
end;

function TAiChat.GetAsynchronous: Boolean;
begin
  Result := Self.Asynchronous;
end;

function TAiChat.GetLastMessage: TAiChatMessage;
begin
  Result := Nil;
  If FMessages.Count > 0 then
    Result := FMessages[FMessages.Count - 1];
end;

function TAiChat.GetMessages: TJSonArray;
begin
  Result := FMessages.ToJSon;
end;

function TAiChat.GetModels: TStringList;
begin
  Result := GetModels(ApiKey, Url);
end;

class function TAiChat.GetModels(aApiKey, aUrl: String): TStringList;
Var
  Client: TNetHTTPClient;
  Headers: TNetHeaders;
  Res: IHTTPResponse;
  Response: TStringStream;
  sUrl, EndPointUrl: String;
  jRes: TJSonObject;
  JArr: TJSonArray;
  JVal: TJSonValue;
  sModel: string;
  CustomModels: TArray<string>;
  I: Integer;
begin
  Result := TStringList.Create;
  try // ISSUE #114: if the body throws, free Result so it is not leaked

  If aUrl <> '' then
    EndPointUrl := aUrl
  Else
    EndPointUrl := GlOpenAIUrl;

  Client := TNetHTTPClient.Create(Nil);
  Response := TStringStream.Create('', TEncoding.UTF8);
  sUrl := EndPointUrl + 'models';

  Try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + aApiKey)];
    Client.ContentType := 'application/json';

    Res := Client.Get(sUrl, Response, Headers);

    if not Assigned(Res) then
      raise Exception.CreateFmt('Connection failed: no response from %s', [sUrl]);

    if Res.StatusCode = 200 then
    Begin
      var
      LParsedModels := TJSonObject.ParseJSONValue(Res.ContentAsString);
      if not(LParsedModels is TJSonObject) then
      begin
        LParsedModels.Free;
        raise Exception.CreateFmt('Error: Invalid JSON response: %s', [Res.ContentAsString]);
      end;
      jRes := TJSonObject(LParsedModels);
      Try
        If jRes.TryGetValue<TJSonArray>('data', JArr) then
        Begin
          For JVal in JArr do
          Begin
            sModel := JVal.GetValue<String>('id');
            If sModel <> '' then
              Result.Add(sModel);
          End;
        End;

        // Add custom models
        CustomModels := TAiChatFactory.Instance.GetCustomModels(Self.GetDriverName);

        for I := Low(CustomModels) to High(CustomModels) do
        begin
{$IF CompilerVersion <= 35.0}
          if Result.IndexOf(CustomModels[I]) = -1 then
            Result.Add(CustomModels[I]);
{$ELSE}
          if not Result.Contains(CustomModels[I]) then
            Result.Add(CustomModels[I]);
{$ENDIF}
        end;

      Finally
        jRes.Free;
      End;
    End
    else
    begin
      Raise Exception.CreateFmt('Error Received: %d, %s', [Res.StatusCode, Res.ContentAsString]);
    end;
  Finally
    Client.Free;
    Response.Free;
  End;
  except // ISSUE #114: the error path must not leave Result orphaned
    Result.Free;
    raise;
  end;
end;

function TAiChat.GetTools(aToolFormat: TToolFormat): TStrings;
begin
  If Assigned(FAiFunctions) and FModelConfig.FTool_Active then // If the component is assigned, it gets it from the component
  Begin
    FTools.Text := FAiFunctions.GetTools(aToolFormat);
    Result := FTools;
  End
  Else
  Begin
    FTools.Text := '';
    Result := FTools;
  End;
end;

procedure TAiChat.ApplyExtraBodyParams(AJSONObject: TJSonObject);
var
  jExtra: TJSonValue;
  jObj: TJSonObject;
  I: Integer;
  LKey: String;
  LVal: TJSonValue;
  LOld: TJSONPair;
begin
  if (FModelConfig = nil) or (Trim(FModelConfig.FModelExtraBodyParams) = '') or
     (AJSONObject = nil) then
    Exit;
  jExtra := TJSonObject.ParseJSONValue(FModelConfig.FModelExtraBodyParams);
  if not Assigned(jExtra) then
    Exit;
  try
    if not (jExtra is TJSonObject) then
      Exit;
    jObj := TJSonObject(jExtra);
    for I := jObj.Count - 1 downto 0 do
    begin
      LKey := jObj.Pairs[I].JsonString.Value;
      LVal := jObj.Pairs[I].JsonValue.Clone as TJSonValue;
      LOld := AJSONObject.RemovePair(LKey);
      if Assigned(LOld) then
        LOld.Free;
      AJSONObject.AddPair(LKey, LVal);
    end;
  finally
    jExtra.Free;
  end;
end;

function TAiChat.InitChatCompletions: String;
Var
  AJSONObject, jToolChoice: TJSonObject;
  JArr: TJSonArray;
  JStop: TJSonArray;
  Lista: TStringList;
  I: Integer;
  LAsincronico: Boolean;
  Res, LModel, sEffort: String;
begin

  If FUser = '' then
    FUser := 'user';

  LModel := TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  If LModel = '' then
    LModel := 'gpt-4o';

  // Functions do not work in asynchronous mode
  LAsincronico := Self.Asynchronous; // and (not Self.Tool_Active);

  // FClient.Asynchronous := LAsincronico;

  AJSONObject := TJSonObject.Create;
  Lista := TStringList.Create;

  Try
    AJSONObject.AddPair('stream', TJSONBool.Create(LAsincronico));

    If Tool_Active and (Trim(GetTools(TToolFormat.tfOpenAi).Text) <> '') then
    Begin

{$IF CompilerVersion < 35}
      JArr := TJSONUtils.ParseAsArray(GetTools(TToolFormat.tfOpenAi).Text);
{$ELSE}
      JArr := TJSonArray(TJSonArray.ParseJSONValue(GetTools(TToolFormat.tfOpenAi).Text));
{$ENDIF}
      If Not Assigned(JArr) then
        Raise Exception.Create('The Tools property is malformed; it must be a JsonArray');
      AJSONObject.AddPair('tools', JArr);

      If (Trim(Tool_choice) <> '') then
      Begin

{$IF CompilerVersion < 35}
        jToolChoice := TJSONUtils.ParseAsObject(Tool_choice);
{$ELSE}
        jToolChoice := TJSonObject(TJSonArray.ParseJSONValue(Tool_choice));
{$ENDIF}
        If Assigned(jToolChoice) then
          AJSONObject.AddPair('tool_choice', jToolChoice);
      End;
    End;

    AJSONObject.AddPair('messages', GetMessages); // FMessages.ToJSon);
    AJSONObject.AddPair('model', LModel);
    AJSONObject.AddPair('user', User);

    If (FResponse_format = tiaChatRfJsonSchema) then
    Begin
      // Without the json_schema {name, schema} object, OpenAI-compatible providers
      // reject the request with 400 — the type alone is not enough.
      var sSchemaName := 'structured_response';
      var bStrict := False; // no strict by default: maximum OpenAI-compatible compatibility
      var JInnerSchema := ParseJsonSchemaProperty(sSchemaName, bStrict);

      var JSchemaWrapper := TJSonObject.Create;
      JSchemaWrapper.AddPair('name', sSchemaName);
      if bStrict then
        JSchemaWrapper.AddPair('strict', TJSONBool.Create(True));
      JSchemaWrapper.AddPair('schema', JInnerSchema);

      var JResponseFormat := TJSonObject.Create;
      JResponseFormat.AddPair('type', 'json_schema');
      JResponseFormat.AddPair('json_schema', JSchemaWrapper);
      AJSONObject.AddPair('response_format', JResponseFormat);
    End
    Else If { LAsincronico or } (FResponse_format = tiaChatRfJson) then
      AJSONObject.AddPair('response_format', TJSonObject.Create.AddPair('type', 'json_object'))
    Else If (FResponse_format = tiaChatRfText) then
      AJSONObject.AddPair('response_format', TJSonObject.Create.AddPair('type', 'text'))
    Else
      AJSONObject.AddPair('response_format', TJSonObject.Create.AddPair('type', 'text'));

    sEffort := '';

    case FModelConfig.FThinkingLevel of
      tlLow:
        sEffort := 'low';
      tlMedium:
        sEffort := 'medium';
      tlHigh:
        sEffort := 'high';
    end;

    if sEffort <> '' then
    begin
      var
      jeffort := TJSonObject.Create;
      jeffort.AddPair('effort', sEffort);
      AJSONObject.AddPair('reasoning', jeffort);

      AJSONObject.AddPair('max_completion_tokens', TJSONNumber.Create(FMax_tokens));
    end
    else if FUrl.Contains('azure.com') or ModelUsesMaxCompletionTokens(LModel) then
      AJSONObject.AddPair('max_completion_tokens', TJSONNumber.Create(FMax_tokens))
    else
      AJSONObject.AddPair('max_tokens', FMax_tokens);

    Lista.CommaText := FStop;
    If Lista.Count > 0 then
    Begin
      JStop := TJSonArray.Create;
      For I := 0 to Lista.Count - 1 do
        JStop.Add(Lista[I]);
      AJSONObject.AddPair('stop', JStop);
    End;

    If FLogprobs = True then
    Begin
      If FLogit_bias <> '' then
        AJSONObject.AddPair('logit_bias', TJSONNumber.Create(FLogit_bias));

      AJSONObject.AddPair('logprobs', TJSONBool.Create(FLogprobs));

      If FTop_logprobs <> '' then
        AJSONObject.AddPair('top_logprobs', TJSONNumber.Create(FTop_logprobs));
    End;

    If Seed > 0 then
      AJSONObject.AddPair('seed', TJSONNumber.Create(FSeed));

    if cap_WebSearch in FModelConfig.FModelCaps then
    begin
      // The OpenAI API expects an object for the options, even if it is empty.
      Var
      jWebSearchOptions := TJSonObject.Create;
      AJSONObject.AddPair('web_search_options', jWebSearchOptions);
    end
    Else If not ModelRequiresDefaultSampling(LModel) then
    Begin
      // gpt-5.6*/o1*/o3*/o4* reject these parameters with 400 even if they have their
      // default value (including temperature:0), so they are omitted entirely for that family
      If FTop_p <> 0 then
        AJSONObject.AddPair('top_p', TJSONNumber.Create(FTop_p));

      AJSONObject.AddPair('temperature', TJSONNumber.Create(Trunc(FTemperature * 100) / 100));
      AJSONObject.AddPair('frequency_penalty', TJSONNumber.Create(Trunc(FFrequency_penalty * 100) / 100));
      AJSONObject.AddPair('presence_penalty', TJSONNumber.Create(Trunc(FPresence_penalty * 100) / 100));
      AJSONObject.AddPair('n', TJSONNumber.Create(FN));

    End;

    ApplyExtraBodyParams(AJSONObject);
    Res := TEncoding.UTF8.GetString(TEncoding.UTF8.GetBytes(AJSONObject.ToJSon));
    Res := StringReplace(Res, '\/', '/', [rfReplaceAll]);
    Result := StringReplace(Res, '\r\n', '', [rfReplaceAll]);
  Finally
    AJSONObject.Free;
    Lista.Free;
  End;
end;

function TAiChat.ModelRequiresDefaultSampling(Const aModel: String): Boolean;
Var
  LModel: String;
begin
  LModel := aModel.ToLower;
  Result := LModel.StartsWith('gpt-5.6') or LModel.StartsWith('gpt-6') or
            LModel.StartsWith('o1') or LModel.StartsWith('o3') or LModel.StartsWith('o4');
end;

function TAiChat.ModelUsesMaxCompletionTokens(Const aModel: String): Boolean;
Var
  LModel: String;
begin
  LModel := aModel.ToLower;
  Result := LModel.StartsWith('gpt-5') or LModel.StartsWith('gpt-6') or
            LModel.StartsWith('o1') or LModel.StartsWith('o3') or LModel.StartsWith('o4');
end;

function TAiChat.ExtractUnsupportedParam(Const aErrorBody: String): String;
Var
  jObj, jErr: TJSonObject;
  LCode, LMsg: String;
begin
  Result := '';
  jObj := TJSonObject.ParseJSONValue(aErrorBody) as TJSonObject;
  If not Assigned(jObj) then
    Exit;
  Try
    If not jObj.TryGetValue<TJSonObject>('error', jErr) then
      Exit;

    LCode := '';
    LMsg := '';
    jErr.TryGetValue<String>('code', LCode);
    jErr.TryGetValue<String>('message', LMsg);

    // OpenAI/Azure use unsupported_parameter (max_tokens in gpt-5*) and
    // unsupported_value (temperature:0 in gpt-5.6/o-series); in both cases
    // error.param brings the parameter name and omitting it is the correct degradation
    If SameText(LCode, 'unsupported_parameter') or SameText(LCode, 'unsupported_value') or LMsg.StartsWith('Unsupported parameter', True) or LMsg.StartsWith('Unsupported value', True) then
      jErr.TryGetValue<String>('param', Result);
  Finally
    jObj.Free;
  End;
end;

function TAiChat.RemoveUnsupportedParamFromBody(Const aBody, aParam: String): String;
Var
  jBody: TJSonObject;
  jPair: TJSONPair;
  LMaxTokens: Integer;
begin
  Result := aBody;
  If aParam = '' then
    Exit;

  jBody := TJSonObject.ParseJSONValue(aBody) as TJSonObject;
  If not Assigned(jBody) then
    Exit;
  Try
    If SameText(aParam, 'max_tokens') and jBody.TryGetValue<Integer>('max_tokens', LMaxTokens) then
    Begin
      // max_tokens is not removed: the correct replacement is max_completion_tokens
      jBody.RemovePair('max_tokens').Free;
      If not Assigned(jBody.GetValue('max_completion_tokens')) then
        jBody.AddPair('max_completion_tokens', TJSONNumber.Create(LMaxTokens));
    End
    Else
    Begin
      jPair := jBody.RemovePair(aParam);
      If not Assigned(jPair) then
        Exit; // it was not in the body: the original is returned so the caller does not retry
      jPair.Free;
    End;
    Result := jBody.ToJSon;
  Finally
    jBody.Free;
  End;
end;

procedure TAiChat.NewChat;
Var
  I: Integer;
begin
  For I := FMessages.Count - 1 downto 0 do
  Begin
    FMessages[I].Free;
    FMessages.Delete(I);
  End;
  FMessages.Clear;
end;

function TAiChat.NewMessage(aPrompt, aRole: String): TAiChatMessage;
begin
  Result := TAiChatMessage.Create(aPrompt, aRole);
end;

procedure TAiChat.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    FChatTools.Notification(AComponent, Operation);
    if AComponent = FPersistentMemory then
      FPersistentMemory := nil;
    if AComponent = FAiFunctions then
      FAiFunctions := nil;
  end;
end;

procedure TAiChat.SetPersistentMemory(AValue: TAiPersistentMemoryBase);
begin
  if FPersistentMemory = AValue then Exit;
  if Assigned(FPersistentMemory) then
    FPersistentMemory.RemoveFreeNotification(Self);
  FPersistentMemory := AValue;
  if Assigned(FPersistentMemory) then
    FPersistentMemory.FreeNotification(Self);
end;

procedure TAiChat.MergeStreamExecutedTools(ADeltaTools: TJSonArray);
var
  Acc: TJSonArray;
  Parsed: TJSonValue;
  NewItem, OldItem: TJSonObject;
  Pair: TJSonPair;
  i, j, NewIdx, OldIdx: Integer;
  Found: Boolean;
begin
  if (ADeltaTools = nil) or (ADeltaTools.Count = 0) then
    Exit;

  Acc := nil;
  if FLastExecutedToolsJSON <> '' then
  begin
    Parsed := TJSonObject.ParseJSONValue(FLastExecutedToolsJSON);
    if Parsed is TJSonArray then
      Acc := TJSonArray(Parsed)
    else
      Parsed.Free;
  end;
  if Acc = nil then
    Acc := TJSonArray.Create;
  try
    for i := 0 to ADeltaTools.Count - 1 do
    begin
      if not (ADeltaTools.Items[i] is TJSonObject) then
        Continue;
      NewItem := TJSonObject(ADeltaTools.Items[i]);
      NewIdx := NewItem.GetValue<Integer>('index', i);

      Found := False;
      for j := 0 to Acc.Count - 1 do
      begin
        OldItem := Acc.Items[j] as TJSonObject;
        OldIdx := OldItem.GetValue<Integer>('index', j);
        if OldIdx = NewIdx then
        begin
          // The new chunk completes the old one: its fields (e.g., 'output') win
          for Pair in NewItem do
          begin
            OldItem.RemovePair(Pair.JsonString.Value).Free;
            OldItem.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSonValue);
          end;
          Found := True;
          Break;
        end;
      end;
      if not Found then
        Acc.AddElement(NewItem.Clone as TJSonObject);
    end;
    FLastExecutedToolsJSON := Acc.ToJSON;
  finally
    Acc.Free;
  end;
end;

procedure TAiChat.OnInternalReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
Var
  jObj, Delta: TJSonObject;
  JToolCalls: TJSonArray;
  sJson, Value, Role1: String;
  P: Integer;

  // Variables for Tool handling
  jFunc: TJSonValue;

  ToolIndex: Integer;
  BufferObj, BufferFunc: TJSonObject;

  // Variables for reconstruction and End of Stream
  CombinedTools: TJSonArray;
  sToolCallsStr: String;
  SortedKeys: TList<Integer>;

  // Variables for Fake JSON
  FakeResponseObj: TJSonObject;
  FakeChoice: TJSonObject;
  FakeMsg: TJSonObject;
  FakeChoicesArr: TJSonArray;
  FakeUsage: TJSonObject;
  TempMsg: TAiChatMessage;

  // Variables for compatibility and parsing
  jArrChoices: TJSonArray;

  // Local procedure to process a JSON or Command line
  // This avoids duplicating code for the remaining buffer case
  Procedure ProcessLine(ALine: String);
  Begin
    if ALine = '' then
      Exit;

    // Remove the "data:" prefix if present
    if StartsStr('data:', ALine) then
      ALine := Trim(Copy(ALine, 6, Length(ALine)));

    if ALine = '' then
      Exit;

    // -----------------------------------------------------------------------
    // CASE 1: [DONE]
    // -----------------------------------------------------------------------
    if ALine = '[DONE]' then
    Begin
      // Finalization and Tool Reconstruction Logic
      sToolCallsStr := '';

      if FTmpToolCallBuffer.Count > 0 then
      begin
        CombinedTools := TJSonArray.Create;
        try
          SortedKeys := TList<Integer>.Create;
          try
            Var
              aKey: Integer;

            for aKey in FTmpToolCallBuffer.Keys do
              SortedKeys.Add(aKey);
            SortedKeys.Sort;
            for aKey in SortedKeys do
            begin
              CombinedTools.Add(FTmpToolCallBuffer[aKey].Clone as TJSonObject);
            end;
          finally
            SortedKeys.Free;
          end;
          sToolCallsStr := CombinedTools.ToJSon;
        finally
          CombinedTools.Free;
          FTmpToolCallBuffer.Clear;
        end;
      end;

      // Fake JSON to trick ParseChat
      FakeResponseObj := TJSonObject.Create;
      try
        FakeResponseObj.AddPair('id', 'stream-' + IntToStr(TThread.GetTickCount));
        FakeResponseObj.AddPair('model', FModel);

        // The usage exactly as the provider sent it (with its *_details), so that
        // ParseChat treats it the same as in the synchronous response. If none
        // arrived, the usual minimum.
        FakeUsage := nil;
        if FStreamUsageJSON <> '' then
          FakeUsage := TJSonObject.ParseJSONValue(FStreamUsageJSON) as TJSonObject;
        if not Assigned(FakeUsage) then
        begin
          FakeUsage := TJSonObject.Create;
          FakeUsage.AddPair('prompt_tokens', TJSONNumber.Create(FStreamPromptTokens));
          FakeUsage.AddPair('completion_tokens', TJSONNumber.Create(FStreamCompletionTokens));
          FakeUsage.AddPair('total_tokens', TJSONNumber.Create(FStreamPromptTokens + FStreamCompletionTokens));
        end;
        FakeResponseObj.AddPair('usage', FakeUsage);
        FStreamPromptTokens := 0;
        FStreamCompletionTokens := 0;
        FStreamUsageJSON := '';

        FakeChoicesArr := TJSonArray.Create;
        FakeChoice := TJSonObject.Create;
        FakeMsg := TJSonObject.Create;

        FakeMsg.AddPair('role', FTmpRole);
        if FLastContent <> '' then
          FakeMsg.AddPair('content', FLastContent);
        if FLastReasoning <> '' then
          FakeMsg.AddPair('reasoning_content', FLastReasoning); // Required by APIs with thinking (DeepSeek, Kimi, etc.)
        if sToolCallsStr <> '' then
          FakeMsg.AddPair('tool_calls', TJSonArray(TJSonObject.ParseJSONValue(sToolCallsStr)));

        FakeChoice.AddPair('message', FakeMsg);
        if FStreamFinishReason <> '' then
          FakeChoice.AddPair('finish_reason', FStreamFinishReason)
        else
          FakeChoice.AddPair('finish_reason', 'stop');
        FStreamFinishReason := '';  // like the counters: a turn without data does not inherit the previous one
        FakeChoicesArr.Add(FakeChoice);
        FakeResponseObj.AddPair('choices', FakeChoicesArr);

        TempMsg := TAiChatMessage.Create('', FTmpRole);
        try
          // The synthetic message carries as content the FLastContent already accumulated by
          // the deltas, and ParseChat adds its content to FLastContent again: without
          // restoring it, OnReceiveDataEnd received the duplicated text ('Done'#13#10'Done')
          // in ALL drivers that use this parser in async mode. Only if there was
          // content: without it, ParseChat uses the reasoning as the response and that is preserved.
          var LStreamedContent := FLastContent;
          ParseChat(FakeResponseObj, TempMsg);
          if LStreamedContent <> '' then
            FLastContent := LStreamedContent;
          // Groq code_interpreter: processes files captured during the stream (async path)
          if FLastExecutedToolsJSON <> '' then
          begin
            ProcessExecutedTools(FLastExecutedToolsJSON, TempMsg);
            FLastExecutedToolsJSON := '';
          end;
          if sToolCallsStr = '' then
          begin
            TempMsg.Id := FMessages.Count + 1;
            FMessages.Add(TempMsg);

            DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO

            if Assigned(FOnReceiveDataEnd) then
              FOnReceiveDataEnd(Self, TempMsg, Nil, FTmpRole, FLastContent);
            TempMsg := nil;
          end
          else
          begin
            // ISSUE #99/#100: if ParseChat left a deferred tool-calling continuation
            // (FPendingToolRun=True), the turn has NOT ended: the final event and
            // acsFinished will be emitted when the response without tools arrives (cycle leaf).
            // We only finish here when there is NO continuation (e.g., passthrough due to
            // StopAgenticLoop, where the tool_calls are delivered to the end client).
            if not FPendingToolRun then
            begin
              DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO

              if Assigned(FOnReceiveDataEnd) then
                FOnReceiveDataEnd(Self, GetLastMessage, Nil, FTmpRole, '');
            end;
          end;
        finally
          if Assigned(TempMsg) then
            TempMsg.Free;
        end;
      finally
        FakeResponseObj.Free;
      end;

      FLastReasoning := ''; // Clear for the next round or next request
      // ISSUE #100: if there is a deferred tool-calling continuation, the turn is still active:
      // do not release FBusy here (the next Run manages it).
      if not FPendingToolRun then
        FBusy := False;
      Exit;
    End;

    // -----------------------------------------------------------------------
    // CASE 2: JSON STANDARD
    // -----------------------------------------------------------------------
    var
    LParsedLine := TJSonObject.ParseJSONValue(ALine);
    if not(LParsedLine is TJSonObject) then
    begin
      LParsedLine.Free;
      Exit; // JSON inv?lido o incompleto
    end;
    jObj := TJSonObject(LParsedLine);

    Try
      // Detect API error inside the stream (e.g., 429 rate limit, 500, etc.)
      // Anthropic sends {"type":"error","error":{"type":"rate_limit_error","message":"..."}}
      var sStreamErrType: string;
      if jObj.TryGetValue<string>('type', sStreamErrType) and (sStreamErrType = 'error') then
      begin
        var JApiErr := jObj.GetValue<TJSonObject>('error');
        var sApiErrMsg: string := '';
        if Assigned(JApiErr) then
          JApiErr.TryGetValue<string>('message', sApiErrMsg);
        if sApiErrMsg = '' then
          sApiErrMsg := ALine;
        FBusy := False;
        FTmpToolCallBuffer.Clear;
        DoStateChange(acsError, sApiErrMsg);
        DoError(sApiErrMsg, nil);
        Exit;
      end;

      jArrChoices := jObj.GetValue<TJSonArray>('choices');
      if (jArrChoices <> nil) and (jArrChoices.Count > 0) then
      begin
        // The real provider finish_reason is kept for the synthetic close.
        var sChunkFinish: string := '';
        if jArrChoices.Items[0].TryGetValue<string>('finish_reason', sChunkFinish) and (sChunkFinish <> '') then
          FStreamFinishReason := sChunkFinish;

        Delta := jArrChoices.Items[0].GetValue<TJSonObject>('delta');
        if Assigned(Delta) then
        begin
          if Delta.TryGetValue<String>('role', Role1) then
            FTmpRole := Role1;

          // Thinking
          Value := '';
          if Delta.TryGetValue<String>('reasoning', Value) or Delta.TryGetValue<String>('reasoning_content', Value) then
          begin
            FLastReasoning := FLastReasoning + Value; // Accumulate to include in history
            if (Value <> '') and Assigned(FOnReceiveThinking) then
            begin
              Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
              FOnReceiveThinking(Self, Nil, jObj, FTmpRole, Value);
            end;
          end;

          // Content
          {if (Delta.GetValue('content') <> nil) and not(Delta.GetValue('content') is TJSONNull) then
          begin
            Value := Delta.GetValue<String>('content');
            FLastContent := FLastContent + Value;
            if Assigned(FOnReceiveDataEvent) then
            begin
              Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
              FOnReceiveDataEvent(Self, Nil, jObj, FTmpRole, Value);
            end;
          end;
          }

          var
            JVal: TJSonValue;
          JVal := Delta.GetValue('content');
          if Assigned(JVal) and (JVal is TJSONString) then
          begin
            Value := JVal.Value;
            FLastContent := FLastContent + Value;
            if Assigned(FOnReceiveDataEvent) then
            begin
              Value := StringReplace(Value, #$A, sLineBreak, [rfReplaceAll]);
              FOnReceiveDataEvent(Self, Nil, jObj, FTmpRole, Value);
            end;
          end
          else if Assigned(JVal) and (JVal is TJSonArray) then
            ParseDeltaContentArray(TJSonArray(JVal), jObj);

          // Tools
          if Delta.TryGetValue<TJSonArray>('tool_calls', JToolCalls) then
          begin
            Var
              JToolCall: TJSonValue;

            for JToolCall in JToolCalls do
            begin
              if JToolCall is TJSonObject then
              begin
                var
                JTC := TJSonObject(JToolCall);
                if JTC.TryGetValue<Integer>('index', ToolIndex) then
                begin
                  if not FTmpToolCallBuffer.TryGetValue(ToolIndex, BufferObj) then
                  begin
                    BufferObj := TJSonObject.Create;
                    FTmpToolCallBuffer.Add(ToolIndex, BufferObj);
                  end;

                  if JTC.TryGetValue<String>('id', Value) then
                    if BufferObj.GetValue('id') = nil then
                      BufferObj.AddPair('id', Value);

                  if JTC.TryGetValue<String>('type', Value) then
                    if BufferObj.GetValue('type') = nil then
                      BufferObj.AddPair('type', Value);

                  if JTC.TryGetValue<TJSonObject>('function', TJSonObject(jFunc)) then
                  begin
                    if not BufferObj.TryGetValue<TJSonObject>('function', BufferFunc) then
                    begin
                      BufferFunc := TJSonObject.Create;
                      BufferObj.AddPair('function', BufferFunc);
                    end;

                    if jFunc.TryGetValue<String>('name', Value) then
                    begin
                      var
                        OldName: string := '';
                      if BufferFunc.TryGetValue<String>('name', OldName) then
                        BufferFunc.RemovePair('name');
                      BufferFunc.AddPair('name', OldName + Value);
                    end;

                    if jFunc.TryGetValue<String>('arguments', Value) then
                    begin
                      var
                        OldArgs: string := '';
                      if BufferFunc.TryGetValue<String>('arguments', OldArgs) then
                        BufferFunc.RemovePair('arguments');
                      BufferFunc.AddPair('arguments', OldArgs + Value);
                    end;
                  end;
                end;
              end;
            end;
          end;

          // Groq code_interpreter (gpt-oss): executed_tools arrives in the DELTA, not in
          // the root. Each tool comes in two chunks with the same index: the first
          // brings only 'arguments' (the code) and the second repeats everything and adds
          // 'output' (the sandbox stdout). They are combined by index and [DONE]
          // delivers the result to ProcessExecutedTools, same as the sync path.
          var JDeltaExec: TJSonArray;
          if Delta.TryGetValue<TJSonArray>('executed_tools', JDeltaExec) then
            MergeStreamExecutedTools(JDeltaExec);
        end
        else
        begin
          // Groq compound-beta: reasoning_content arrives as a complete field in choices[0].message
          // (not as an incremental delta) in the final SSE event before [DONE]
          var JMsgFull: TJSonObject;
          if jArrChoices.Items[0].TryGetValue<TJSonObject>('message', JMsgFull) then
          begin
            var sRCFull: String := '';
            if JMsgFull.TryGetValue<String>('reasoning_content', sRCFull) and (sRCFull <> '') then
            begin
              FLastReasoning := FLastReasoning + sRCFull;
              if Assigned(FOnReceiveThinking) then
                FOnReceiveThinking(Self, Nil, jObj, FTmpRole, sRCFull);
            end;
          end;
        end;
      end;

      // Capture token usage from streaming chunks that include a root-level "usage" field.
      // Groq sends a chunk with choices:[] but real token counts before [DONE].
      // These are stored and injected into FakeUsage when [DONE] arrives.
      var JStreamUsage: TJSonObject;
      if jObj.TryGetValue<TJSonObject>('usage', JStreamUsage) then
      begin
        var aIn  := JStreamUsage.GetValue<Integer>('prompt_tokens', 0);
        var aOut := JStreamUsage.GetValue<Integer>('completion_tokens', 0);
        if aIn  > 0 then FStreamPromptTokens     := aIn;
        if aOut > 0 then FStreamCompletionTokens := aOut;
        if (aIn > 0) or (aOut > 0) then
          FStreamUsageJSON := JStreamUsage.ToJSON;
      end;

      // Groq code_interpreter: executed_tools appears at top level before [DONE]
      var JExecToolsVal: TJSonValue;
      if jObj.TryGetValue('executed_tools', JExecToolsVal) then
        FLastExecutedToolsJSON := JExecToolsVal.ToJSON;
    Finally
      jObj.Free;
    End;
  End;

begin
  LogDebug('--OnInternalReceiveData--');
  // ISSUE #108: FResponse is a UTF-8 buffer with raw TCP bytes. If a chunk splits
  // a multibyte character (common in languages with many accents), DataString throws
  // EEncodingError. The incomplete bytes remain in FResponse and the next chunk
  // completes the character, so only the log needs protection: it must NOT abort the request escaping from the callback.
  // (continued from above)
  try
    var LDbgBody := FResponse.DataString;
    if Length(LDbgBody) > 500 then
      LogDebug(Copy(LDbgBody, 1, 500) + '...[truncado]')
    else
      LogDebug(LDbgBody);
  except
    LogDebug('[chunk UTF-8 parcial - log omitido]');
  end;

  If FClient.Asynchronous = False then
    Exit;

  AAbort := FAbort;
  If FAbort = True then
  Begin
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallBuffer.Clear;
    FLastReasoning := '';
    If Assigned(FOnReceiveDataEnd) then
      FOnReceiveDataEnd(Self, Nil, Nil, 'system', 'abort');
    Exit;
  End;

  Try
    FTmpResponseText := FTmpResponseText + FResponse.DataString;
    FResponse.Clear;

    // 1. Main loop: Processes everything that has a safe line break
    while Pos(#10, FTmpResponseText) > 0 do
    begin
      P := Pos(#10, FTmpResponseText);
      sJson := Trim(Copy(FTmpResponseText, 1, P - 1)); // Trim removes leading spaces as in your error
      Delete(FTmpResponseText, 1, P);

      ProcessLine(sJson); // We process the clean line
    end;

    // 2. Safety Edge: last line without a newline
    // If what remains in the buffer is EXACTLY '[DONE]' (or with data:), we process it.
    // If it is incomplete JSON (e.g., '{"id":'), we do NOT touch it, we wait for the next packet.
    sJson := Trim(FTmpResponseText);
    if (sJson = '[DONE]') or (sJson = 'data: [DONE]') then
    begin
      ProcessLine(sJson); // We process the final DONE
      FTmpResponseText := ''; // We clear the buffer
    end;

  Except
    // Silent error handling for stream
  End;
end;

procedure TAiChat.ParseDeltaContentArray(AContentArr: TJSonArray; jObj: TJSonObject);
begin
  // Empty base implementation.
  // Drivers that receive delta.content as a typed array (e.g., Mistral magistral)
  // override this method to process the blocks {"type":"text"/"thinking",...}.
end;

procedure TAiChat.OnRequestCompletedEvent(const Sender: TObject; const aResponse: IHTTPResponse);
begin
  // The try/finally guarantees that FOnHttpRequestDone is fired on ALL exits
  // (including the HTTP error Exit): it is the signal by which the integrator knows
  // that it can now free this object without cutting the legs off the async thread.
  try
  // At this point the async request has fully completed: THTTPClient.ExecuteHTTPInternal
  // has finished (including the Seek on FSourceStream), so it is safe to free the stream.
  FreeAndNil(FCurrentPostStream);

  If Assigned(aResponse) and ((aResponse.StatusCode < 200) or (aResponse.StatusCode > 299)) then
  Begin
    // Always release the busy state on HTTP errors (e.g., 429 rate limit,
    // 500 server error, etc.). Without this the app hangs indefinitely.
    FBusy := False;
    FPendingToolRun := False; // do not continue the tool-calling cycle after an HTTP error
    FTmpToolCallBuffer.Clear;
    DoStateChange(acsError, aResponse.ContentAsString);
    if Assigned(FOnError) then
      FOnError(Self, aResponse.ContentAsString, Nil, aResponse);
    Exit;
  End;

  // ISSUE #100: deferred continuation of the tool-calling cycle in async mode.
  // It is deferred outside the completion dispatch (TThread.Queue/ForceQueue) to start
  // the next POST with the previous request already destroyed and its FSourceStream freed,
  // eliminating reentrancy and the race condition on FCurrentPostStream.
  if FPendingToolRun then
  begin
    FPendingToolRun := False;
    // REVISION 2026-08-30: the continuation is deferred to a pool task, NOT to the main thread queue.
    // TThread.Queue/ForceQueue are only drained if someone calls CheckSynchronize; a headless server (Linux daemon without a message loop, which is how this library is integrated into a broker) never does, so the async tool-calling cycle stayed queued forever and the turn died by timeout. A task achieves the same goal as ForceQueue — starting the next POST outside the completion dispatch, with FCurrentPostStream already freed a few lines above — without depending on the integrator pumping messages.
    // calls CheckSynchronize; a headless server (Linux daemon without a message
    // loop, which is how this library is integrated into a broker) never does,
    // so the asynchronous tool-calling cycle stayed queued forever and
    // the turn died by timeout. A task achieves the same goal pursued by
    // the ForceQueue — starting the next POST outside the completion dispatch,
    // (continued from above)
    // (continued from above)
    TTask.Run(
      procedure
      begin
        try
          Self.Run(nil, nil);
        except
          on E: Exception do
            // Without this the exception dies inside the task and the turn hangs
            // until the integrator timeout, without any clue as to the reason.
            DoError('Error in tool-calling continuation: ' + E.Message, E);
        end;
      end);
  end;

  finally
    if Assigned(FOnHttpRequestDone) then
      FOnHttpRequestDone(Self);
  end;
end;

procedure TAiChat.OnRequestErrorEvent(const Sender: TObject; const AError: string);
begin
  try
    FreeAndNil(FCurrentPostStream);
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallBuffer.Clear;
    DoStateChange(acsError, AError);
    If Assigned(FOnError) then
      FOnError(Self, AError, Nil, Nil);
  finally
    if Assigned(FOnHttpRequestDone) then
      FOnHttpRequestDone(Self);
  end;
end;

procedure TAiChat.OnRequestExceptionEvent(const Sender: TObject; const AError: Exception);
begin
  try
    FreeAndNil(FCurrentPostStream);
    FBusy := False;
    FPendingToolRun := False;
    FTmpToolCallBuffer.Clear;
    DoStateChange(acsError, AError.Message);
    If Assigned(FOnError) then
      FOnError(Self, AError.Message, AError, Nil);
  finally
    if Assigned(FOnHttpRequestDone) then
      FOnHttpRequestDone(Self);
  end;
end;

procedure TAiChat.ParseChat(jObj: TJSonObject; ResMsg: TAiChatMessage);
Var
  choices: TJSonArray;
  JItem: TJSonObject;
  JVal: TJSonValue;
  JToolCallsValue: TJSonValue;
  jMessage: TJSonObject;
  uso: TJSonObject;
  aPrompt_tokens, aCompletion_tokens, aTotal_tokens, aCached_tokens: Integer;
  aReasoning_tokens: Integer;
  Role, Respuesta, sReasoning: String;
  ToolMsg, AskMsg: TAiChatMessage;
  // Msg: TAiChatMessage;
  LFunciones: TAiToolsFunctions;
  ToolCall: TAiToolsFunction;

  TaskList: array of ITask;
  I, NumTasks: Integer;
  Clave, sToolCalls, sRes: String;

  Code: TMarkdownCodeExtractor;
  CodeFile: TCodeFile;
  CodeFiles: TCodeFileList;
  MF: TAiMediaFile;
  St: TStringStream;
  ModelVersion: String;

  // Local subroutine: guarantees independent capture by value in Delphi 10.4+
  // (the assignment LCaptura:=ToolCall inside the anon-proc runs when the task
  // executes, not when it is created, so ToolCall may have changed)
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
            var LErrorMsg := 'Error in "' + TC.Name + '": ' + E.Message;
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

  aPrompt_tokens := 0;
  aCompletion_tokens := 0;
  aTotal_tokens := 0;
  aReasoning_tokens := 0;
  if Assigned(jObj.GetValue('model')) then
    ModelVersion := jObj.GetValue('model').Value;
  uso := jObj.GetValue('usage') as TJSonObject;
  if Assigned(uso) then
  begin
    aPrompt_tokens := uso.GetValue<Integer>('prompt_tokens');
    aCompletion_tokens := uso.GetValue<Integer>('completion_tokens');
    aTotal_tokens := uso.GetValue<Integer>('total_tokens');
    // Tokens served from cache (automatic prompt caching of
    // OpenAI-compatible providers). DeepSeek uses 'prompt_cache_hit_tokens'; the standard
    // Chat Completions (Kimi/Moonshot, Groq, Mistral, etc.) exposes it in
    // 'prompt_tokens_details.cached_tokens'.
    aCached_tokens := 0;
    if not uso.TryGetValue<Integer>('prompt_cache_hit_tokens', aCached_tokens) then
    begin
      var jPromptDetails: TJSonObject;
      if uso.TryGetValue<TJSonObject>('prompt_tokens_details', jPromptDetails) then
        jPromptDetails.TryGetValue<Integer>('cached_tokens', aCached_tokens);
    end;

    // Cached tokens are INCLUDED within prompt_tokens in all Chat dialects
    // DeepSeek states it explicitly (prompt_tokens = hit + miss) and
    // the others expose it the same way inside prompt_tokens_details. Anthropic, on the
    // other hand, reports them separately, and TAiClaudeChat leaves them that way; whoever bills
    // SUMS prompt + cache, so leaving them overlapped charges the cached tokens
    // twice, once at full rate and once at cache rate.
    //
    // They are subtracted here so that both counters are disjoint with
    // independence from the provider. The subtraction only applies if they are actually
    // contained: if any already gives them separated (prompt < cache), nothing is touched
    // and the correction cannot backfire.
    //
    // It is not the same as the reasoning_tokens below: those also come
    // summed, but inside completion_tokens and are NOT subtracted on purpose, because they are reported separately without being billed separately.
    // (continued from above)
    if (aCached_tokens > 0) and (aPrompt_tokens >= aCached_tokens) then
      aPrompt_tokens := aPrompt_tokens - aCached_tokens;

    // Reasoning tokens of models that think before answering
    // (GLM, DeepSeek, gpt-oss...). The Chat Completions standard exposes them
    // in 'completion_tokens_details.reasoning_tokens'; some providers also leave them loose in the usage root, so both sites are tried.
    // (continued from above)
    // NOTE: they are already SUMMED inside completion_tokens. This only serves to
    // report them separately; they are not subtracted from the output nor billed
    // twice.
    if not uso.TryGetValue<Integer>('reasoning_tokens', aReasoning_tokens) then
    begin
      var jComplDetails: TJSonObject;
      if uso.TryGetValue<TJSonObject>('completion_tokens_details', jComplDetails) then
        jComplDetails.TryGetValue<Integer>('reasoning_tokens', aReasoning_tokens);
    end;
  end;

  AskMsg := GetLastMessage; // Gets the question, since ResMsg is added to the list if there are no errors.

  jObj.TryGetValue<TJSonArray>('choices', choices);

  For JVal in choices do
  Begin
    JItem := TJSonObject(JVal);
    jMessage := JItem.GetValue<TJSonObject>('message');

    Role := jMessage.GetValue<String>('role');

    if jMessage.TryGetValue<String>('reasoning', sReasoning) then // Groq
    begin
      ResMsg.ReasoningContent := sReasoning;
    end
    Else if jMessage.TryGetValue<String>('reasoning_content', sReasoning) then // DeepSeek
    begin
      ResMsg.ReasoningContent := sReasoning;
    end;

    // Groq compound-beta: code execution results arrive as blocks
    // <output>...</output> inside reasoning_content (no separate executed_tools field)
    if sReasoning <> '' then
    begin
      var sRem := sReasoning;
      var iTagO  := Pos('<output>', sRem);
      var iTagCl := Pos('</output>', sRem);
      while (iTagO > 0) and (iTagCl > iTagO) do
      begin
        var sBlock := Copy(sRem, iTagO + 8, iTagCl - iTagO - 8);
        if Trim(sBlock) <> '' then
        begin
          var JFakeArr  := TJSonArray.Create;
          var JFakeTool := TJSonObject.Create;
          JFakeTool.AddPair('type', 'python');
          JFakeTool.AddPair('output', sBlock);
          JFakeArr.AddElement(JFakeTool);
          try
            ProcessExecutedTools(JFakeArr.ToJSON, ResMsg);
          finally
            JFakeArr.Free;
          end;
        end;
        sRem  := Copy(sRem, iTagCl + 9, MaxInt);
        iTagO  := Pos('<output>', sRem);
        iTagCl := Pos('</output>', sRem);
      end;
    end;

    jMessage.TryGetValue<String>('content', sRes);

    // They are read BEFORE deciding the content: both condition whether the
    // reasoning can serve as a response.
    sToolCalls := '';
    If jMessage.TryGetValue<TJSonValue>('tool_calls', JToolCallsValue) and Assigned(JToolCallsValue) and (JToolCallsValue is TJSonArray) then
    Begin
      sToolCalls := TJSonArray(JToolCallsValue).Format;
    End;

    var LFinishR: string := '';
    JItem.TryGetValue<String>('finish_reason', LFinishR);
    // The datum was read only to decide the reasoning fallback and then discarded: the
    // ResMsg.FinishReason property existed but nobody wrote it through this path,
    // so the consumer could not distinguish a clean finish from a response
    // cut off by max_tokens. Empty is not propagated, to avoid overwriting what was already read.
    if LFinishR <> '' then
      ResMsg.FinishReason := LFinishR;

    If Not Trim(sRes).IsEmpty then
      Respuesta := Trim(Respuesta + sLineBreak + sRes)
    Else if sToolCalls.IsEmpty and (not SameText(LFinishR, 'length')) then
      // Without 'content': there are reasoners that respond ONLY in reasoning, and for
      // those the reasoning IS the response. But not in two cases:
      //   - there are tool_calls: the turn's response is the call, not the monologue.
      //   - finish_reason 'length': generation was cut off mid-sentence, so
      //     the reasoning is incomplete and is not a response.
      // Without these two brakes, the client received the model's internal monologue
      // (usually in English) as if it were the reply to the user.
      Respuesta := Trim(Respuesta + sLineBreak + sReasoning);
  End;

  Respuesta := Trim(Respuesta);

  Self.FLastContent := Trim(Self.FLastContent + sLineBreak + Respuesta);
  FPrompt_tokens := FPrompt_tokens + aPrompt_tokens;
  FCompletion_tokens := FCompletion_tokens + aCompletion_tokens;
  FTotal_tokens := FTotal_tokens + aTotal_tokens;
  FThinking_tokens := FThinking_tokens + aReasoning_tokens;

  if sToolCalls.IsEmpty then // If it is a normal response, adds the data to ResMsg
  Begin
    ResMsg.Role := Role;
    ResMsg.Model := ModelVersion;
    ResMsg.Tool_calls := sToolCalls;
    ResMsg.Prompt := ResMsg.Prompt + Respuesta;
    ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aPrompt_tokens;
    ResMsg.Completion_tokens := ResMsg.Completion_tokens + aCompletion_tokens;
    ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;
    ResMsg.Cached_tokens := ResMsg.Cached_tokens + aCached_tokens;
    ResMsg.Thinking_tokens := ResMsg.Thinking_tokens + aReasoning_tokens;
    DoProcessResponse(AskMsg, ResMsg, Respuesta);
  End
  Else // If it has a toolcall, adds it and runs again to obtain the response
  Begin
    Var
    Msg := TAiChatMessage.Create(Respuesta, Role);
    Msg.Tool_calls := sToolCalls;
    if sReasoning <> '' then
      Msg.ReasoningContent := sReasoning;  // Required by deepseek-reasoner and other models with reasoning
    Msg.Id := FMessages.Count + 1;
    FMessages.Add(Msg);
  End;

  LFunciones := ExtractToolCallFromJson(choices);

  Try
    If LFunciones.Count > 0 then
    Begin

      NumTasks := LFunciones.Count;
      SetLength(TaskList, NumTasks);
      // Adjusts the array size for the number of tasks

      I := 0;
      For Clave in LFunciones.Keys do
      Begin
        ToolCall := LFunciones[Clave];
        ToolCall.ResMsg := ResMsg; // The messages are passed in case they want to process them
        ToolCall.AskMsg := AskMsg;

        _CreateTask(ToolCall, I); // local subroutine guarantees capture by value
        Inc(I);

      End;
      // Do not use TTask.WaitForAll(TaskList) directly: it blocks the calling thread without
      // pumping the synchronization queue. If a tool call uses TThread.Synchronize/
      // TThread.Queue (e.g., to access the VCL/FMX) and this thread is the main one,
      // a deadlock occurs (issue #103). We wait with a timeout and process the
      // pending Synchronize/Queue.
      // NOTE: CheckSynchronize is NOT a no-op outside the main thread: it THROWS an exception
      // "CheckSynchronize called from thread X, which is NOT the main thread". In
      // secondary threads (Indy workers of a headless service, agent TTask)
      // we only wait. Same criterion as TMCPClientSSE.WaitForInitialization.
      while not TTask.WaitForAll(TaskList, 10) do
        if TThread.CurrentThread.ThreadID = MainThreadID then
          CheckSynchronize(0)
        else
          Sleep(10);

      var LStopLoop := False;
      For Clave in LFunciones.Keys do
      Begin
        ToolCall := LFunciones[Clave];
        ToolMsg := TAiChatMessage.Create(ToolCall.Response, 'tool', ToolCall.Id, ToolCall.Name);
        for var LMF in ToolCall.MediaFiles do
          ToolMsg.AddMediaFile(LMF);
        ToolCall.MediaFiles.OwnsObjects := False;
        ToolMsg.Id := FMessages.Count + 1;
        FMessages.Add(ToolMsg);
        LStopLoop := LStopLoop or ToolCall.StopAgenticLoop;
      End;

      if LStopLoop then
      Begin
        // A handler asked to stop the loop (tool passthrough: it is executed by the
        // end client). We finish the turn with the tool_calls in ResMsg instead
        // of resending the synthetic result to the model — models like
        // gpt-oss retry the same tool indefinitely upon seeing an 'OK'.
        FBusy := False;
        ResMsg.Role := Role;
        ResMsg.Model := ModelVersion;
        ResMsg.Tool_calls := sToolCalls;
        ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aPrompt_tokens;
        ResMsg.Completion_tokens := ResMsg.Completion_tokens + aCompletion_tokens;
        ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;
        ResMsg.Thinking_tokens := ResMsg.Thinking_tokens + aReasoning_tokens;
        DoProcessResponse(AskMsg, ResMsg, Respuesta);
      End
      else
      Begin
        if FClient.Asynchronous then
        begin
          // ISSUE #100: in async mode do NOT re-enter THTTPClient from its own
          // receive callback (this code runs inside OnInternalReceiveData).
          // Re-entering starts a new POST whose finally frees the FCurrentPostStream of
          // the still-in-flight request -> AV in THTTPClient.ExecuteHTTPInternal (Seek on
          // freed FSourceStream). Continuation is deferred to OnRequestCompletedEvent,
          // which runs when the current request has finished unwinding completely.
          FPendingToolRun := True;
        end
        else
        begin
          Self.Run(Nil, ResMsg);
        end;
      End;

    End
    Else
    Begin
      FBusy := False;

      // If it is marked to generate files, take the result and extract the files and add them as mediafiles to ResMsg

      If cap_ExtractCode in FModelConfig.FSessionCaps then
      Begin
        Code := TMarkdownCodeExtractor.Create;
        Try

          CodeFiles := Code.ExtractCodeFiles(Respuesta);
          For CodeFile in CodeFiles do
          Begin
            St := TStringStream.Create(CodeFile.Code);
            Try
              St.Position := 0;

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

      DoProcessResponse(AskMsg, ResMsg, Respuesta);

      ResMsg.Prompt := Respuesta;

      // ISSUE #99: in async mode the [DONE] handler of OnInternalReceiveData is the
      // responsible for DoStateChange(acsFinished) and for firing FOnReceiveDataEnd. If
      // ParseChat also does it, the event (and the state change) runs twice.
      // In sync mode ParseChat is the only one that fires them, so it is preserved.
      if not FClient.Asynchronous then
        DoStateChange(acsFinished, 'Done'); // <--- ESTADO FINALIZADO

      // gpt-oss-20b (Groq): executed_tools nested in choices[0].message.executed_tools.
      // It is extracted here, before OnDataEnd, so that MediaFiles.Count is correct in the callback.
      // (compound-beta uses root-level executed_tools; it was already processed via reasoning_content above)
      if ResMsg.MediaFiles.Count = 0 then
      begin
        var JChExec: TJSonArray;
        if jObj.TryGetValue<TJSonArray>('choices', JChExec) and (JChExec.Count > 0) then
        begin
          var JMsgExec: TJSonObject;
          if TJSonObject(JChExec.Items[0]).TryGetValue<TJSonObject>('message', JMsgExec) then
          begin
            var JExecVal: TJSonValue;
            if JMsgExec.TryGetValue('executed_tools', JExecVal) then
              ProcessExecutedTools(JExecVal.ToJSON, ResMsg);
          end;
        end;
      end;

      // ISSUE #99: see note above — in async it is fired by the [DONE] handler, not ParseChat.
      if not FClient.Asynchronous then
        If Assigned(FOnReceiveDataEnd) then
          FOnReceiveDataEnd(Self, ResMsg, jObj, Role, Respuesta);
    End;
  Finally
    LFunciones.Free;
  End;
end;

procedure TAiChat.ProcessExecutedTools(const AExecutedToolsJSON: string; ResMsg: TAiChatMessage);
var
  JArr: TJSonArray;
  JItem, JCI, JOutput, JFileObj: TJSonObject;
  JOutputArr: TJSonArray;
  JVal, JOutVal: TJSonValue;
  sOutType, sUrl, sMime, sName: string;
  LClient: TNetHTTPClient;
  LStream: TMemoryStream;
  LMF: TAiMediaFile;
begin
  if AExecutedToolsJSON = '' then
    Exit;
  JArr := TJSonObject.ParseJSONValue(AExecutedToolsJSON) as TJSonArray; // ParseJSONValue is a class method of TJSONObject (TJSonValue does not expose it in D10.4)
  if not Assigned(JArr) then
    Exit;
  try
    LClient := TNetHTTPClient.Create(nil);
    try
{$IF CompilerVersion >= 34}
      LClient.SynchronizeEvents := False;
{$ENDIF}
      LClient.CustomHeaders['Authorization'] := 'Bearer ' + ApiKey;
      for JVal in JArr do
      begin
        JItem := JVal as TJSonObject;
        if not Assigned(JItem) then
          Continue;
        var sToolType: string := '';
        JItem.TryGetValue<string>('type', sToolType);

        // Groq compound-beta: type='python'
        // gpt-oss-20b: type='function' (name='python'), output=stdout plain string
        if (sToolType = 'python') or (sToolType = 'function') then
        begin
          var sOutput: string := '';
          JItem.TryGetValue<string>('output', sOutput);
          if sOutput <> '' then
          begin
            // Generic marker FILE_B64_BEGIN:name.ext / FILE_B64_END
            var iB_file := Pos('FILE_B64_BEGIN:', sOutput);
            var iE_file := Pos('FILE_B64_END', sOutput);
            if (iB_file > 0) and (iE_file > iB_file) then
            begin
              var sAfterBegin := Copy(sOutput, iB_file + Length('FILE_B64_BEGIN:'), MaxInt);
              var iNL := Pos(#10, sAfterBegin);
              if iNL = 0 then iNL := Pos(#13, sAfterBegin);
              var sOutName := 'ci_output.bin';
              if iNL > 0 then
                sOutName := Trim(Copy(sAfterBegin, 1, iNL - 1));
              var iDataStart := iB_file + Length('FILE_B64_BEGIN:') + iNL;
              var sRaw_f := Copy(sOutput, iDataStart, iE_file - iDataStart);
              var sClean_f := '';
              for var ch in sRaw_f do
                if CharInSet(ch, ['A'..'Z','a'..'z','0'..'9','+','/','=']) then
                  sClean_f := sClean_f + ch;
              if sClean_f <> '' then
              begin
                var LBytes_f := TNetEncoding.Base64.DecodeStringToBytes(sClean_f);
                if Length(LBytes_f) > 0 then
                begin
                  var LStream_f := TMemoryStream.Create;
                  try
                    LStream_f.Write(LBytes_f[0], Length(LBytes_f));
                    LStream_f.Position := 0;
                    LMF := TAiMediaFile.Create;
                    LMF.LoadFromStream(sOutName, LStream_f);
                    ResMsg.AddMediaFile(LMF);
                  finally
                    LStream_f.Free;
                  end;
                end;
              end;
            end
            else
            begin
              // Legacy marker WAV_B64_BEGIN/<base64>/WAV_B64_END
              var iB_py := Pos('WAV_B64_BEGIN', sOutput);
              var iE_py := Pos('WAV_B64_END',   sOutput);
              if (iB_py > 0) and (iE_py > iB_py) then
              begin
                var sRaw := Copy(sOutput, iB_py + Length('WAV_B64_BEGIN'),
                                 iE_py - iB_py - Length('WAV_B64_BEGIN'));
                var sClean := '';
                for var ch in sRaw do
                  if CharInSet(ch, ['A'..'Z','a'..'z','0'..'9','+','/','=']) then
                    sClean := sClean + ch;
                if sClean <> '' then
                begin
                  var LBytes_py := TNetEncoding.Base64.DecodeStringToBytes(sClean);
                  if Length(LBytes_py) > 0 then
                  begin
                    var LStream_py := TMemoryStream.Create;
                    try
                      LStream_py.Write(LBytes_py[0], Length(LBytes_py));
                      LStream_py.Position := 0;
                      LMF := TAiMediaFile.Create;
                      LMF.LoadFromStream('ci_output.wav', LStream_py);
                      ResMsg.AddMediaFile(LMF);
                    finally
                      LStream_py.Free;
                    end;
                  end;
                end;
              end;
            end;
          end;
          Continue;
        end;

        if sToolType <> 'code_interpreter' then
          Continue;
        if not JItem.TryGetValue<TJSonObject>('code_interpreter', JCI) then
          Continue;
        if not JCI.TryGetValue<TJSonArray>('outputs', JOutputArr) then
          Continue;
        for JOutVal in JOutputArr do
        begin
          JOutput := JOutVal as TJSonObject;
          if not Assigned(JOutput) then
            Continue;
          sOutType := '';
          JOutput.TryGetValue<string>('type', sOutType);
          sUrl := '';
          sMime := '';
          sName := '';
          // Groq compound-beta: stdout captured as output of type 'text'.
          // Supports FILE_B64_BEGIN:name.ext/FILE_B64_END (generic) and WAV_B64_BEGIN (legacy).
          if sOutType = 'text' then
          begin
            var sText: string := '';
            JOutput.TryGetValue<string>('text', sText);
            var iB_ft := Pos('FILE_B64_BEGIN:', sText);
            var iE_ft := Pos('FILE_B64_END', sText);
            if (iB_ft > 0) and (iE_ft > iB_ft) then
            begin
              var sAfterBegin_t := Copy(sText, iB_ft + Length('FILE_B64_BEGIN:'), MaxInt);
              var iNL_t := Pos(#10, sAfterBegin_t);
              if iNL_t = 0 then iNL_t := Pos(#13, sAfterBegin_t);
              var sOutName_t := 'ci_output.bin';
              if iNL_t > 0 then
                sOutName_t := Trim(Copy(sAfterBegin_t, 1, iNL_t - 1));
              var iDataStart_t := iB_ft + Length('FILE_B64_BEGIN:') + iNL_t;
              var sB64_t := Trim(Copy(sText, iDataStart_t, iE_ft - iDataStart_t));
              var LBytes_t := TNetEncoding.Base64.DecodeStringToBytes(sB64_t);
              if Length(LBytes_t) > 0 then
              begin
                var LStream_t := TMemoryStream.Create;
                try
                  LStream_t.Write(LBytes_t[0], Length(LBytes_t));
                  LStream_t.Position := 0;
                  LMF := TAiMediaFile.Create;
                  LMF.LoadFromStream(sOutName_t, LStream_t);
                  ResMsg.AddMediaFile(LMF);
                finally
                  LStream_t.Free;
                end;
              end;
            end
            else
            begin
              var iB := Pos('WAV_B64_BEGIN', sText);
              var iE := Pos('WAV_B64_END', sText);
              if (iB > 0) and (iE > iB) then
              begin
                var sB64 := Trim(Copy(sText, iB + Length('WAV_B64_BEGIN'), iE - iB - Length('WAV_B64_BEGIN')));
                var LBytes := TNetEncoding.Base64.DecodeStringToBytes(sB64);
                var LStream64 := TMemoryStream.Create;
                try
                  LStream64.Write(LBytes[0], Length(LBytes));
                  LStream64.Position := 0;
                  LMF := TAiMediaFile.Create;
                  LMF.LoadFromStream('ci_tone.wav', LStream64);
                  ResMsg.AddMediaFile(LMF);
                finally
                  LStream64.Free;
                end;
              end;
            end;
            Continue; // text outputs have no URL, skip the download block
          end;
          // Groq returns images, files and audio as downloadable URLs
          if (sOutType = 'image') and JOutput.TryGetValue<TJSonObject>('image', JFileObj) then
          begin
            JFileObj.TryGetValue<string>('url', sUrl);
            JFileObj.TryGetValue<string>('type', sMime); // Groq: campo 'type' = MIME
            sName := 'ci_image';
          end
          else if (sOutType = 'file') and JOutput.TryGetValue<TJSonObject>('file', JFileObj) then
          begin
            JFileObj.TryGetValue<string>('url', sUrl);
            JFileObj.TryGetValue<string>('mime_type', sMime);
            JFileObj.TryGetValue<string>('name', sName);
          end
          else if (sOutType = 'audio') and JOutput.TryGetValue<TJSonObject>('audio', JFileObj) then
          begin
            JFileObj.TryGetValue<string>('url', sUrl);
            JFileObj.TryGetValue<string>('type', sMime);
            sName := 'ci_audio';
          end;
          if sUrl = '' then
            Continue;
          if sName = '' then
            sName := 'ci_output';
          if (ExtractFileExt(sName) = '') and (sMime <> '') then
          begin
            var Ext := GetFileExtensionFromMimeType(sMime);
            if Ext <> '' then
              sName := sName + '.' + Ext;
          end;
          LStream := TMemoryStream.Create;
          try
            try
              var LRes := LClient.Get(sUrl, LStream);
              if LRes.StatusCode = 200 then
              begin
                LStream.Position := 0;
                LMF := TAiMediaFile.Create;
                LMF.LoadFromStream(sName, LStream);
                ResMsg.AddMediaFile(LMF);
              end;
            except
            end;
          finally
            LStream.Free;
          end;
        end;
      end;
    finally
      LClient.Free;
    end;
  finally
    JArr.Free;
  end;
end;

{
  procedure TAiChat.ParseJsonTranscript(jObj: TJSonObject; ResMsg: TAiChatMessage; aMediaFile: TAiMediaFile);
  var
  // JSON parsing
  jUsage, jInputTokenDetails: TJSonObject;
  jArrWords, jArrSegments: TJSonArray;

  // Extracted data
  sTextoTranscrito, sTextoWords, sTextoSegments: String;
  aTotal_tokens, aInput_tokens, aOutput_tokens: integer;
  aText_tokens, aAudio_tokens: integer; // Detailed input tokens

  begin
  sTextoTranscrito := '';
  aTotal_tokens := 0;
  aInput_tokens := 0;
  aOutput_tokens := 0;
  aText_tokens := 0;
  aAudio_tokens := 0;

  if not jObj.TryGetValue<string>('text', sTextoTranscrito) then
  begin
  FLastError := 'The API response does not contain the "text" field with the transcription.';
  DoError(FLastError, nil);
  FBusy := False;
  Exit;
  end;

  If jObj.TryGetValue<TJSonArray>('words', jArrWords) then
  sTextoWords := jArrWords.Format;

  If jObj.TryGetValue<TJSonArray>('segments', jArrSegments) then
  sTextoSegments := jArrSegments.Format;

  // --- 3. USAGE DATA EXTRACTION (TOKENS) ---
  // The 'usage' object might not be present, so we handle it safely.
  if jObj.TryGetValue<TJSonObject>('usage', jUsage) then
  begin
  // We extract the main tokens
  jUsage.TryGetValue<integer>('total_tokens', aTotal_tokens);
  jUsage.TryGetValue<integer>('input_tokens', aInput_tokens); // Cost of the audio (and prompt if any)
  jUsage.TryGetValue<integer>('output_tokens', aOutput_tokens); // Cost of the generated text

  // We extract the input token details (sub-object)
  // This tells us how many tokens corresponded to the audio and how many to a possible text prompt.
  if jUsage.TryGetValue<TJSonObject>('input_token_details', jInputTokenDetails) then
  begin
  jInputTokenDetails.TryGetValue<integer>('text_tokens', aText_tokens);
  jInputTokenDetails.TryGetValue<integer>('audio_tokens', aAudio_tokens);
  end;
  end;

  // --- 4. COMPONENT STATE UPDATE ---
  // We update the global token counters, adding those from this call.
  Self.Total_tokens := Self.Total_tokens + aTotal_tokens;
  Self.Prompt_tokens := Self.Prompt_tokens + aInput_tokens; // 'input' is equivalent to 'prompt'
  Self.Completion_tokens := Self.Completion_tokens + aOutput_tokens; // 'output' is equivalent to 'completion'

  If Trim(sTextoWords + sLineBreak + sTextoSegments) <> '' then
  Begin
  aMediaFile.Transcription := Trim(sTextoWords + sLineBreak + sTextoSegments);
  aMediaFile.Detail := Trim(sTextoTranscrito);
  ResMsg.Prompt := Trim(ResMsg.Prompt + aMediaFile.Transcription);
  End
  Else
  Begin
  aMediaFile.Transcription := sTextoTranscrito;
  ResMsg.Prompt := Trim(ResMsg.Prompt + sLineBreak + sTextoTranscrito);
  End;

  ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aInput_tokens;
  ResMsg.Completion_tokens := ResMsg.Completion_tokens + aOutput_tokens;
  ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;
  end;
}

procedure TAiChat.ParseJsonTranscript(jObj: TJSonObject; ResMsg: TAiChatMessage; aMediaFile: TAiMediaFile);
var
  // JSON parsing
  jUsage, jInputTokenDetails: TJSonObject;
  jArrWords, jArrSegments: TJSonArray;

  // Extracted data
  sTextoTranscrito, sTextoWords, sTextoSegments: String;
  aTotal_tokens, aInput_tokens, aOutput_tokens: Integer;
  aText_tokens, aAudio_tokens: Integer; // Detailed input tokens

  // Auxiliary variable for the event
  AskMsg: TAiChatMessage;

begin
  sTextoTranscrito := '';
  aTotal_tokens := 0;
  aInput_tokens := 0;
  aOutput_tokens := 0;
  aText_tokens := 0;
  aAudio_tokens := 0;

  // 1. Validate main text
  if not jObj.TryGetValue<string>('text', sTextoTranscrito) then
  begin
    FLastError := 'The API response does not contain the "text" field with the transcription.';
    DoError(FLastError, nil);
    FBusy := False;
    Exit;
  end;

  // 2. Extract details (Granularity)
  If jObj.TryGetValue<TJSonArray>('words', jArrWords) then
    sTextoWords := jArrWords.Format;

  If jObj.TryGetValue<TJSonArray>('segments', jArrSegments) then
    sTextoSegments := jArrSegments.Format;

  // 3. USAGE DATA EXTRACTION (TOKENS)
  if jObj.TryGetValue<TJSonObject>('usage', jUsage) then
  begin
    jUsage.TryGetValue<Integer>('total_tokens', aTotal_tokens);
    jUsage.TryGetValue<Integer>('input_tokens', aInput_tokens);
    jUsage.TryGetValue<Integer>('output_tokens', aOutput_tokens);

    if jUsage.TryGetValue<TJSonObject>('input_token_details', jInputTokenDetails) then
    begin
      jInputTokenDetails.TryGetValue<Integer>('text_tokens', aText_tokens);
      jInputTokenDetails.TryGetValue<Integer>('audio_tokens', aAudio_tokens);
    end;
  end;

  // 4. COMPONENT STATE AND MESSAGE UPDATE
  Self.Total_tokens := Self.Total_tokens + aTotal_tokens;
  Self.Prompt_tokens := Self.Prompt_tokens + aInput_tokens;
  Self.Completion_tokens := Self.Completion_tokens + aOutput_tokens;

  // Assign to the media file
  if Trim(sTextoWords + sLineBreak + sTextoSegments) <> '' then
  begin
    aMediaFile.Transcription := Trim(sTextoWords + sLineBreak + sTextoSegments);
    aMediaFile.Detail := Trim(sTextoTranscrito);
  end
  else
  begin
    aMediaFile.Transcription := sTextoTranscrito;
  end;

  // Mark as processed so it is not resent infinitely in a loop
  aMediaFile.Procesado := True;

  // Outside cmTranscription this is the Phase 1 bridge of RunNew (a
  // text model receives audio): the transcription is INPUT for the model, which responds
  // afterwards. Before, it was written to ResMsg and OnReceiveDataEnd was fired with the
  // raw text, before the real response (and the response was added afterwards to
  // the same ResMsg). Only in cmTranscription is the transcription the response.
  if FChatMode <> cmTranscription then
    Exit;

  // Update the response message (ResMsg)
  if ResMsg.Prompt <> '' then
    ResMsg.Prompt := ResMsg.Prompt + sLineBreak + sTextoTranscrito
  else
    ResMsg.Prompt := sTextoTranscrito;

  ResMsg.Prompt_tokens := ResMsg.Prompt_tokens + aInput_tokens;
  ResMsg.Completion_tokens := ResMsg.Completion_tokens + aOutput_tokens;
  ResMsg.Total_tokens := ResMsg.Total_tokens + aTotal_tokens;

  // Assign role if it does not have one
  if ResMsg.Role = '' then
    ResMsg.Role := 'assistant';

  // --- 5. FIRE EVENTS (NEW BLOCK) ---

  // A) Get the original message (User) to pass as context
  AskMsg := GetLastMessage;

  // B) Notify internal processing (useful for logs or hooks)
  DoProcessResponse(AskMsg, ResMsg, sTextoTranscrito);

  // C) Notify state change to the UI
  DoStateChange(acsFinished, 'Transcription Completed');

  If Self.Asynchronous and Assigned(FOnReceiveDataEvent) then
    FOnReceiveDataEvent(Self, ResMsg, jObj, 'assistant', sTextoTranscrito);

  // D) Fire final data event (Crucial for the UI to receive the text)
  if Assigned(FOnReceiveDataEnd) then
    FOnReceiveDataEnd(Self, ResMsg, jObj, 'assistant', sTextoTranscrito);

  // Release the busy state
  FBusy := False;
end;

function TAiChat.PrepareSystemMsg: String;
Var
  S, Key, Val, MensajeInicial: String;
  I: Integer;
  JMemory: TJSonObject;
begin
  // If the response format is Json, it must always carry in the instruction that the format is json
  If Self.Response_format = TAiChatResponseFormat.tiaChatRfJson then
    S := 'Respond in json format'
  Else
    S := '';

  MensajeInicial := FSystemPrompt.Text + sLineBreak + S;

  JMemory := TJSonObject.Create;
  Try
    Try
      For I := 0 to FMemory.Count - 1 do
      Begin
        Key := FMemory.KeyNames[I];
        Val := FMemory.Values[Key];
        JMemory.AddPair(Key, Val);
      End;
    Except
      ON E: Exception do
      Begin
        Raise Exception.Create('The memory format must be Key=Value; it is not configured correctly');
      End;
    End;

    If Assigned(FOnInitChat) then // Gives the opportunity to initialize the chat with additional parameters such as memory
      FOnInitChat(Self, 'system', MensajeInicial, JMemory);

    If Trim(MensajeInicial) <> '' then
      Result := MensajeInicial;

    If Length(Trim(JMemory.Format)) > 10 then
      Result := Result + sLineBreak + 'To Remember= ' + JMemory.Format;
  Finally
    JMemory.Free;
  End;
end;

function TAiChat.PublicChatToSend: String;
begin
  Result := InitChatCompletions;
end;

procedure TAiChat.RemoveFromMemory(Key: String);
begin
  FMemory.Values[Key] := '';
end;

function TAiChat.RemoveMesage(IdMsg: Integer): Boolean;
Var
  I: Integer;
  Msg: TAiChatMessage;
begin
  For I := 0 to FMessages.Count - 1 do
  Begin
    Msg := FMessages[I];
    If Msg.Id = IdMsg then
    Begin
      FMessages.Remove(Msg);
      Break;
    End;
  End;
  Result := True;
end;

function TAiChat.RetrieveFile(aFileId: string): TAiMediaFile;
begin
  Result := Nil; // Base class does nothing
end;

function TAiChat.RetrieveFileList: TAiMediaFiles;
begin
  Result := Nil; // Base class does nothing
end;

{ //original validated and tested
  Function TAiChat.Run(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
  Var
  MF: TAiMediaFile;
  LOwnsResMsg: Boolean; // Flag to control ownership of the object
  begin
  Result := '';
  LOwnsResMsg := False;

  // If a ResMsg object is not passed, we create one locally.
  // In this case, Run is the "owner" and responsible for its lifecycle if it is not added to the list.
  If Not Assigned(ResMsg) then
  begin
  ResMsg := TAiChatMessage.Create('', 'assistant');
  LOwnsResMsg := True;
  end;

  Try
  // If the message is passed to run directly, it adds it to the message list
  If Assigned(AskMsg) then
  InternalAddMessage(AskMsg);

  Try
  // Gets the last message corresponding to the request
  if not Assigned(AskMsg) then
  AskMsg := GetLastMessage;

  // If there are unprocessed messages, it will try to process them before passing it to the chat
  if Assigned(AskMsg) and (AskMsg.HasUnprocessedItems) then
  begin
  for MF in AskMsg.MediaFiles do
  begin
  If MF.FileCategory in NativeInputFiles then
  Begin
  // Existing file processing logic...
  if (not(Tcm_Audio in ChatMediaSupports)) and (MF.FileCategory = Tfc_Audio) and (not MF.Procesado) then
  InternalRunTranscription(MF, ResMsg, AskMsg)
  else if (not(Tcm_pdf in ChatMediaSupports)) and (MF.FileCategory = Tfc_pdf) and (not MF.Procesado) then
  InternalRunPDFDescription(MF, ResMsg, AskMsg)
  Else if (not(Tcm_Image in ChatMediaSupports)) and (MF.FileCategory = Tfc_Image) and (not MF.Procesado) and (Not(Tfc_Video in NativeOutputFiles)) then
  InternalRunImageDescription(MF, ResMsg, AskMsg)
  Else if (Not(Tcm_Video in ChatMediaSupports)) and (Tfc_Video in NativeOutputFiles) then
  InternalRunImageVideoGeneration(ResMsg, AskMsg)
  Else
  Begin
  InternalRunCompletions(ResMsg, AskMsg);

  // --- FIX 1: Async handling inside the file loop ---
  If FClient.Asynchronous = True then
  Begin
  if LOwnsResMsg then // Only free if we created it
  begin
  ResMsg.Free;
  ResMsg := Nil;
  end;
  Exit; // Exit to avoid adding it to the list below
  End;
  End;
  end
  Else
  Begin
  InternalRunCompletions(ResMsg, AskMsg);

  // --- FIX 2: Async handling else native ---
  If FClient.Asynchronous = True then
  Begin
  if LOwnsResMsg then
  begin
  ResMsg.Free;
  ResMsg := Nil;
  end;
  Exit;
  End;
  End;
  end;
  end
  Else
  Begin
  // Main logic without pending files to process
  if (Not(Tcm_Image in ChatMediaSupports)) and (Tfc_Image in NativeOutputFiles) then
  InternalRunImageGeneration(ResMsg, AskMsg)
  Else if (Not(Tcm_Audio in ChatMediaSupports)) and (Tfc_Audio in NativeOutputFiles) then
  InternalRunSpeechGeneration(ResMsg, AskMsg)
  Else if (Not(Tcm_Video in ChatMediaSupports)) and (Tfc_Video in NativeOutputFiles) then
  InternalRunImageVideoGeneration(ResMsg, AskMsg)
  Else if (Not(tcm_WebSearch in ChatMediaSupports)) and (Tfc_WebSearch in NativeInputFiles) then
  InternalRunWebSearch(ResMsg, AskMsg)
  Else
  Begin
  InternalRunCompletions(ResMsg, AskMsg);

  // --- FIX 3: Main Async handling (Where you got the error) ---
  If FClient.Asynchronous = True then
  Begin
  // FIXED: We only free if Run created the object.
  // If it comes from ParseChat (Tool Call), LOwnsResMsg is False, it is not freed here,
  // avoiding the Double Free in OnInternalReceiveData.
  if LOwnsResMsg then
  begin
  ResMsg.Free;
  ResMsg := Nil;
  end;
  Exit; // We exit immediately.
  End;

  End;
  End;

  // Only if it reaches here (Synchronous Mode)
  If Assigned(ResMsg) then
  Result := ResMsg.Prompt;

  If (AskMsg.Role <> 'tool') and (AskMsg.ToolCallId = '') then
  Begin
  If Assigned(ResMsg) then
  Begin
  ResMsg.Id := FMessages.Count + 1;
  FMessages.Add(ResMsg);
  End;
  End;

  Except
  On E: Exception do
  Begin
  // Safe cleanup in case of error
  If LOwnsResMsg and Assigned(ResMsg) then
  begin
  // We verify that it is not in the list before freeing
  if FMessages.IndexOf(ResMsg) = -1 then
  ResMsg.Free;
  end;
  DoError(E.Message, E);
  End;
  End;

  Finally
  End;
  end;
}

procedure TAiChat.SetSanitizerActive(const Value: Boolean);
begin
  FSanitizerActive := Value;
end;

procedure TAiChat.SetOnSanitize(const Value: TAiSanitizeEvent);
begin
  FOnSanitize := Value;
end;

function TAiChat.FileTypeInModelCaps(ACategory: TAiFileCategory): Boolean;
begin
  case ACategory of
    Tfc_Image:
      Result := cap_Image in FModelConfig.FModelCaps;
    Tfc_Audio:
      Result := cap_Audio in FModelConfig.FModelCaps;
    Tfc_Video:
      Result := cap_Video in FModelConfig.FModelCaps;
    Tfc_Pdf:
      Result := cap_Pdf in FModelConfig.FModelCaps;
  else
    Result := False; // unknown types always need a bridge (OnProcessMediaFile)
  end;
end;

function TAiChat.GetModelInputFileTypes: TAiFileCategories;
begin
  Result := [Tfc_Text];
  if cap_Image in FModelConfig.FModelCaps then Include(Result, Tfc_Image);
  if cap_Audio in FModelConfig.FModelCaps then Include(Result, Tfc_Audio);
  if cap_Video in FModelConfig.FModelCaps then Include(Result, Tfc_Video);
  if cap_Pdf in FModelConfig.FModelCaps then Include(Result, Tfc_Pdf);
end;


function TAiChat.RunNew(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
var
  MF: TAiMediaFile;
  LOwnsResMsg: Boolean;
  LRes: String;
  LProc: Boolean;
  Gap: TAiCapabilities;
begin
  Result := '';
  LOwnsResMsg := False;
  Gap := FModelConfig.FSessionCaps - FModelConfig.FModelCaps; // Central gap calculation
  FMessages.ModelCaps := FModelConfig.FModelCaps; // synchronizes native types for ToJSon

  // --- PREPARATION ---
  if not Assigned(ResMsg) then
  begin
    ResMsg := TAiChatMessage.Create('', 'assistant');
    LOwnsResMsg := True;
  end;

  try
    if Assigned(AskMsg) and (FMessages.IndexOf(AskMsg) = -1) then
      InternalAddMessage(AskMsg);

    if not Assigned(AskMsg) then
      AskMsg := GetLastMessage;

    if not Assigned(AskMsg) then
      raise Exception.Create('There is no valid message to process in TAiChat.Run');

    // --- PHASE 1: INPUT BRIDGE (cmConversation only) ---
    if FChatMode = cmConversation then
    begin
      for MF in AskMsg.MediaFiles do
      begin
        if not FileTypeInModelCaps(MF.FileCategory) and not MF.Procesado then
        begin
          // Priority 1: manual event
          if Assigned(FOnProcessMediaFile) then
          begin
            LRes := '';
            LProc := False;
            FOnProcessMediaFile(Self, AskMsg.Prompt, MF, GetModelInputFileTypes, LRes, LProc);
            MF.Procesado := LProc;
            MF.Transcription := LRes;
          end;
          // Priority 2: automatic bridge according to gap
          if not MF.Procesado then
          begin
            case MF.FileCategory of
              Tfc_Audio:
                if cap_Audio in Gap then
                  InternalRunTranscription(MF, ResMsg, AskMsg);
              Tfc_Image:
                if cap_Image in Gap then
                  InternalRunImageDescription(MF, ResMsg, AskMsg);
              Tfc_Pdf:
                if cap_Pdf in Gap then
                  InternalRunPDFDescription(MF, ResMsg, AskMsg);
            end;
          end;
        end;
      end;
    end;

    // Inject PHASE 1 transcriptions into the user message prompt,
    // so that the model receives the textual content of the processed audio.
    var LTranscriptions := AskMsg.GetMediaTranscription;
    if LTranscriptions <> '' then
    begin
      if AskMsg.Prompt <> '' then
        AskMsg.Prompt := AskMsg.Prompt + sLineBreak + '[Audio transcription]:' + sLineBreak + LTranscriptions
      else
        AskMsg.Prompt := LTranscriptions;
    end;

    // --- PHASE 2: GROUNDING (excludes SmartDispatch: routing is done by the LLM in Phase 3) ---
    if (FChatMode <> cmSmartDispatch) and (cap_WebSearch in Gap) then
    begin
      DoStateChange(acsReasoning, 'Running Web Search Bridge...');
      InternalRunWebSearch(ResMsg, AskMsg);
    end;

    // --- PHASE 3: OUTPUT ORCHESTRATION ---
    case FChatMode of
      cmConversation:
        begin
          // Unified gap analysis
          if cap_GenVideo in Gap then
            InternalRunImageVideoGeneration(ResMsg, AskMsg)
          else if cap_GenImage in Gap then
            InternalRunImageGeneration(ResMsg, AskMsg)
          else if cap_GenAudio in Gap then
            InternalRunSpeechGeneration(ResMsg, AskMsg)
          else if cap_GenReport in Gap then
            InternalRunReport(ResMsg, AskMsg)
          else
            InternalRunCompletions(ResMsg, AskMsg);
          // cap_ExtractCode is handled internally by InternalRunCompletions via FModelConfig.FSessionCaps
        end;
      // Forced modes: skip gap analysis, direct call
      cmImageGeneration:
        InternalRunImageGeneration(ResMsg, AskMsg);
      cmVideoGeneration:
        InternalRunImageVideoGeneration(ResMsg, AskMsg);
      cmSpeechGeneration:
        InternalRunSpeechGeneration(ResMsg, AskMsg);
      cmWebSearch:
        InternalRunWebSearch(ResMsg, AskMsg);
      cmReportGeneration:
        InternalRunReport(ResMsg, AskMsg);
      cmTranscription:
        begin
          for MF in AskMsg.MediaFiles do
            if (MF.FileCategory = Tfc_Audio) and not MF.Procesado then
            begin
              InternalRunTranscription(MF, ResMsg, AskMsg);
              Break;
            end;
        end;
      cmSmartDispatch:
        begin
          if FClient.Asynchronous then
            raise Exception.Create('cmSmartDispatch does not support asynchronous mode. Use Asynchronous = False.');
          InternalRunSmartDispatch(ResMsg, AskMsg);
        end;
    end;

    // --- ASYNC/SYNC MANAGEMENT ---
    if FClient.Asynchronous then
    begin
      if LOwnsResMsg then
      begin
        ResMsg.Free;
        ResMsg := Nil;
      end;
      Exit;
    end;

    if Assigned(ResMsg) then
    begin
      Result := ResMsg.Prompt;
      // The assistant response is ALWAYS archived in the history, also
      // when AskMsg is a tool result (continuation): before it was freed and the
      // integrator lost the ResMsg metadata (Cache_write_tokens/
      // Cached_tokens from Claude, ReasoningContent, MediaFiles) because
      // GetLastMessage returned the tool message and not the assistant one.
      if FMessages.IndexOf(ResMsg) = -1 then // guard: avoid double-add (e.g., Cohere ParseChat already added it)
      begin
        ResMsg.Id := FMessages.Count + 1;
        FMessages.Add(ResMsg);
      end;
    end;

  except
    on E: Exception do
    begin
      if LOwnsResMsg and Assigned(ResMsg) then
        if FMessages.IndexOf(ResMsg) = -1 then
          ResMsg.Free;
      DoError(E.Message, E);
    end;
  end;
end;

function TAiChat.Run(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
var
  LSanitizeResult: TSanitizeResult;
  LSanitizeAction: TAiSanitizeAction;
  LVerdict:        TAiPromptVerdict;
  LMemory:         IAiPersistentMemory;
  LMemCtx:         string;
  LOrigPrompt:     string;
  LMemWrapper:     string;
begin
  // Telemetry: a span covers the complete turn (phases, tool calls, parsing).
  // Nested Runs (continuation after tool calls) reuse the turn span.
  if not Assigned(FRunSpan) then
  begin
    FRunSpan := AiSpanStart('chat ' + FModel, skClient);
    AiSpanAttr(FRunSpan, 'gen_ai.operation.name', 'chat');
    AiSpanAttr(FRunSpan, 'gen_ai.request.model', FModel);
    AiSpanAttr(FRunSpan, 'gen_ai.system', GetDriverName);
  end;

  if FSanitizerActive and Assigned(AskMsg) and (AskMsg.Role = 'user') and (AskMsg.Prompt <> '') then
  begin
    LSanitizeResult := TSanitizerPipeline.Run(AskMsg.Prompt);
    if LSanitizeResult.IsSuspicious then
    begin
      LSanitizeAction := saBlock; // default action: block
      if Assigned(FOnSanitize) then
        FOnSanitize(Self, LSanitizeResult, LSanitizeAction);
      case LSanitizeAction of
        saBlock:
        begin
          DoError('Possible prompt injection detected. Message blocked by the sanitizer.', nil);
          Result := '';
          Exit;
        end;
        saAllow:
          ; // continues without modifying the prompt
        saAllowWrapped:
          AskMsg.Prompt := LSanitizeResult.WrappedText;
      end;
    end;
  end;

  // Semantic input guardrail (ChatTools.PromptGuard): second layer, after
  // the regex sanitizer. It judges what no regex anticipates (injections
  // rephrased, credentials, harmful requests, out of scope).
  if Assigned(FChatTools.FPromptGuard) and Assigned(AskMsg) and (AskMsg.Role = 'user') and
     (AskMsg.Prompt <> '') then
  begin
    FChatTools.FPromptGuard.SetContext(Self);
    try
      LVerdict := FChatTools.FPromptGuard.CheckPrompt(AskMsg.Prompt);
    except
      on E: Exception do
      begin
        LVerdict.Allowed := not FChatTools.FPromptGuard.BlockOnError;
        LVerdict.Category := 'error';
        LVerdict.Score := 0;
        LVerdict.Reason := 'prompt guard unavailable: ' + E.Message;
      end;
    end;
    if not LVerdict.Allowed then
    begin
      AiSpanAttr(FRunSpan, 'guardrail.input.category', LVerdict.Category);
      LSanitizeAction := saBlock; // default action: block
      if Assigned(FOnPromptGuard) then
        FOnPromptGuard(Self, LVerdict, LSanitizeAction);
      case LSanitizeAction of
        saBlock:
        begin
          DoError('Message blocked by the input guardrail: ' + LVerdict.Reason, nil);
          Result := '';
          Exit;
        end;
        saAllow:
          ; // continues without modifying the prompt
        saAllowWrapped:
          AskMsg.Prompt := TSanitizerPipeline.Run(AskMsg.Prompt).WrappedText;
      end;
    end;
  end;

  // Inject memory context before sending to the LLM. Best-effort: a failure of the
  // memory storage (locked SQLite, full disk, etc.) should not bring down the
  // chat call; only the memory context of this turn is lost.
  LOrigPrompt := '';
  LMemWrapper := '';
  if Assigned(FPersistentMemory) and Assigned(AskMsg) and (AskMsg.Role = 'user') and
     Supports(FPersistentMemory, IAiPersistentMemory, LMemory) then
  begin
    try
      LOrigPrompt := AskMsg.Prompt;
      LMemCtx := LMemory.BuildContext(AskMsg.Prompt, FMemoryTokenBudget);
      if LMemCtx <> '' then
      begin
        LMemWrapper := '--- Memory context ---' + sLineBreak + LMemCtx +
                        sLineBreak + '--- End of context ---' + sLineBreak + sLineBreak;
        AskMsg.Prompt := LMemWrapper + AskMsg.Prompt;
      end;
    except
      on E: Exception do
      begin
        LogDebug('PersistentMemory.BuildContext failed, continuing without memory context: ' + E.Message);
        LMemWrapper := '';
      end;
    end;
  end;

  Result := RunNew(AskMsg, ResMsg);

  // Remove the memory context block from the history: it already traveled in the body of
  // this request; we do not leave it "baked" into AskMsg.Prompt for future turns
  // (it would be resent completely on each subsequent turn, in addition to the fresh injection
  // for that turn). Only the exact prefix we added above is removed; what RunNew
  // added afterwards (e.g., Phase 1 audio transcription) is preserved intact.
  if (LMemWrapper <> '') and Assigned(AskMsg) and AskMsg.Prompt.StartsWith(LMemWrapper) then
    AskMsg.Prompt := Copy(AskMsg.Prompt, Length(LMemWrapper) + 1, MaxInt);

  // Save the original prompt in memory after receiving a response. Best-effort.
  if FAutoStoreMemories and (LOrigPrompt <> '') and Assigned(LMemory) then
  begin
    try
      LMemory.AutoStore(LOrigPrompt, 5);
    except
      on E: Exception do
        LogDebug('PersistentMemory.AutoStore failed: ' + E.Message);
    end;
  end;

  // Notify the complete exchange for automatic analysis (see TAiMemory.Analyzer
  // / AnalysisInterval). Independent of AutoStoreMemories: if there is no Analyzer
  // configured on the implementation side, NotifyExchange is a no-op. In
  // Asynchronous mode, Result may arrive empty (the real response arrives via callback),
  // so the analysis of that turn degrades to only the user prompt.
  if (LOrigPrompt <> '') and Assigned(LMemory) then
  begin
    try
      LMemory.NotifyExchange(LOrigPrompt, Result);
    except
      on E: Exception do
        LogDebug('PersistentMemory.NotifyExchange failed: ' + E.Message);
    end;
  end;

  // Telemetry (synchronous backstop): normally the span is closed in
  // DoStateChange (acsFinished/acsError); this covers early exits.
  // In async it is NOT closed here: the real end arrives via the callback.
  if (not Asynchronous) and Assigned(FRunSpan) then
  begin
    AiSpanEnd(FRunSpan, FLastError);
    FRunSpan := nil;
  end;
end;

function TAiChat.RemoveMesage(Msg: TAiChatMessage): Boolean;
begin
  // Remove returns the index of the removed element. If it is >= 0, it was successful.
  Result := FMessages.Remove(Msg) >= 0;
end;

procedure TAiChat.SetAiFunctions(const Value: TAiFunctions);
begin
  if FAiFunctions = Value then Exit;
  if Assigned(FAiFunctions) then
    FAiFunctions.RemoveFreeNotification(Self);
  FAiFunctions := Value;
  if Assigned(FAiFunctions) then
    FAiFunctions.FreeNotification(Self);
end;

procedure TAiChat.SetApiKey(const Value: String);
begin
  FApiKey := Value;
end;

procedure TAiChat.SetAsynchronous(const Value: Boolean);
begin
  FAsynchronous := Value;
  FClient.Asynchronous := Value;
end;

procedure TAiChat.SetCompletion_tokens(const Value: Integer);
begin
  FCompletion_tokens := Value;
end;

procedure TAiChat.SetFrequency_penalty(const Value: Double);
begin
  FFrequency_penalty := Value;
end;

procedure TAiChat.SetSystemPrompt(const Value: TStrings);
begin
  FSystemPrompt.Assign(Value);
end;

procedure TAiChat.SetJsonSchema(const Value: TStrings);
begin
  FJsonSchema.Assign(Value);
end;

function TAiChat.ParseJsonSchemaProperty(var aSchemaName: string; var aStrict: Boolean): TJSonObject;
var
  JSchemaValue: TJSONValue;
  JWrapped: TJSONValue;
begin
  JSchemaValue := nil;
  if Trim(FJsonSchema.Text) <> '' then
    JSchemaValue := TJSonObject.ParseJSONValue(FJsonSchema.Text);

  if not(JSchemaValue is TJSonObject) then
  begin
    JSchemaValue.Free;
    Raise Exception.Create('Response_format = json_schema requires a valid JSON object in the JsonSchema property');
  end;

  JWrapped := TJSonObject(JSchemaValue).GetValue('schema');
  if JWrapped is TJSonObject then
  begin
    // Wrapper {name, strict, schema}: the parts are extracted
    Result := TJSonObject(JWrapped.Clone);
    TJSonObject(JSchemaValue).TryGetValue<string>('name', aSchemaName);
    TJSonObject(JSchemaValue).TryGetValue<Boolean>('strict', aStrict);
    JSchemaValue.Free;
  end
  else
    Result := TJSonObject(JSchemaValue);
end;

procedure TAiChat.SetK(const Value: Integer);
begin
  FK := Value;
end;

procedure TAiChat.SetLastError(const Value: String);
begin
  FLastError := Value;
end;

procedure TAiChat.SetLogit_bias(const Value: String);
begin
  FLogit_bias := Value;
end;

procedure TAiChat.SetLogprobs(const Value: Boolean);
begin
  FLogprobs := Value;
end;

procedure TAiChat.SetMax_tokens(const Value: Integer);
begin
  FMax_tokens := Value;
end;

procedure TAiChat.SetMemory(const Value: TStrings);
begin
  FMemory.Text := Value.Text;
end;

procedure TAiChat.SetModel(const Value: String);
begin
  FModel := Value;
end;

procedure TAiChat.SetN(const Value: Integer);
begin
  FN := Value;
end;

procedure TAiChat.SetOnAddMessage(const Value: TAiChatOnDataEvent);
begin
  FOnAddMessage := Value;
end;

procedure TAiChat.SetOnBeforeSendMessage(const Value: TAiChatOnBeforeSendEvent);
begin
  FOnBeforeSendMessage := Value;
end;

procedure TAiChat.SetOnCallToolFunction(const Value: TOnCallToolFunction);
begin
  FOnCallToolFunction := Value;
end;

procedure TAiChat.SetOnError(const Value: TAiErrorEvent);
begin
  FOnError := Value;
end;

procedure TAiChat.SetOnInitChat(const Value: TAiChatOnInitChatEvent);
begin
  FOnInitChat := Value;
end;

procedure TAiChat.SetOnProcessMediaFile(const Value: TAiChatOnMediaFileEvent);
begin
  FOnProcessMediaFile := Value;
end;

procedure TAiChat.SetOnProcessResponse(const Value: TAiChatOnProcessResponseEvent);
begin
  FOnProcessResponse := Value;
end;

procedure TAiChat.SetOnProgressEvent(const Value: TAiModelProgressEvent);
begin
  FOnProgressEvent := Value;
end;

procedure TAiChat.SetOnReceiveDataEnd(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveDataEnd := Value;
end;

procedure TAiChat.SetOnReceiveDataEvent(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveDataEvent := Value;
end;

procedure TAiChat.SetOnReceiveThinking(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveThinking := Value;
end;

procedure TAiChat.SetPresence_penalty(const Value: Double);
begin
  FPresence_penalty := Value;
end;

procedure TAiChat.SetPrompt_tokens(const Value: Integer);
begin
  FPrompt_tokens := Value;
end;

procedure TAiChat.SetResponseTimeOut(const Value: Integer);
begin
  If Value < 61000 then
    FResponseTimeOut := 61000
  Else
    FResponseTimeOut := Value;

  FClient.ResponseTimeOut := FResponseTimeOut;
end;

procedure TAiChat.SetResponse_format(const Value: TAiChatResponseFormat);
begin
  FResponse_format := Value;
end;

procedure TAiChat.SetSeed(const Value: Integer);
begin
  FSeed := Value;
end;

procedure TAiChat.SetStop(const Value: string);
begin
  FStop := Value;
end;

procedure TAiChat.SetStream_Usage(const Value: Boolean);
begin
  FStream_Usage := Value;
end;

procedure TAiChat.SetTemperature(const Value: Double);
begin
  FTemperature := Value;
end;

procedure TAiChat.SetThinking_tokens(const Value: Integer);
begin
  FThinking_tokens := Value;
end;

procedure TAiChat.SetCached_tokens(const Value: Integer);
begin
  FCached_tokens := Value;
end;

procedure TAiChat.SetEnabledFeatures(const Value: TAiChatMediaSupports);
begin
  FEnabledFeatures := Value;
end;

function TAiChat.GetModelCaps: TAiCapabilities;
begin
  Result := FModelConfig.ModelCaps;
end;

function TAiChat.GetSessionCaps: TAiCapabilities;
begin
  Result := FModelConfig.SessionCaps;
end;

procedure TAiChat.SetModelCaps(const Value: TAiCapabilities);
begin
  FModelConfig.ModelCaps := Value;
  FNewSystemConfigured := True;
end;

procedure TAiChat.SetSessionCaps(const Value: TAiCapabilities);
begin
  FModelConfig.SessionCaps := Value;
  FNewSystemConfigured := True;
end;

procedure TAiChat.EnsureNewSystemConfig;
begin
  // stub — new system config is applied via SetModelCaps/SetSessionCaps
end;

{function TAiChat.LegacyToModelCaps: TAiCapabilities;
begin
  Result := [];
end;

function TAiChat.LegacyToSessionCaps: TAiCapabilities;
begin
  Result := [];
end;

function TAiChat.RunLegacy(AskMsg: TAiChatMessage; ResMsg: TAiChatMessage): String;
begin
  Result := RunNew(AskMsg, ResMsg);
end;
}

function TAiChat.GetTool_Active: Boolean;
begin
  Result := FModelConfig.FTool_Active;
end;

procedure TAiChat.SetTool_Active(const Value: Boolean);
begin
  FModelConfig.FTool_Active := Value;
end;

procedure TAiChat.SetTool_choice(const Value: string);
begin
  FTool_choice := Value;
end;

// Effective tool_choice of the request. Forcing a tool ('required'/'any' or a
// specific function) applies to the FIRST call of the turn: on the rounds that
// return tool results, 'auto' is requested, or the model is forced to
// call another tool every time (measured with Claude Sonnet 5: 231 requests in an
// endless loop, fix Sep 29 2026). All drivers read this property.
function TAiChat.GetTool_choice: string;
var
  LWord: string;
  LLast: TAiChatMessage;
begin
  Result := FTool_choice;
  LWord := FTool_choice.Replace('"', '').Trim.ToLower;
  if (LWord = '') or (LWord = 'auto') or (LWord = 'none') then
    Exit;
  if (not Assigned(FMessages)) or (FMessages.Count = 0) then
    Exit;
  LLast := FMessages[FMessages.Count - 1];
  if SameText(LLast.Role, 'tool') or (LLast.ToolCallId <> '') then
    Result := 'auto';
end;

procedure TAiChat.SetTop_logprobs(const Value: String);
begin
  FTop_logprobs := Value;
end;

procedure TAiChat.SetTop_p(const Value: Double);
Var
  TmpVal: Double;
begin
  // 0 (or negative) = do NOT send top_p in the payload and let the server apply
  // its default. InitChatCompletions already covers that case (If FTop_p <> 0), but
  // the previous clamp to 0.1 made it unreachable; some models/routes reject
  // any top_p different from theirs (mk-kimi-k2: "only 0.95 is allowed" -> 503).
  If Value <= 0 then
    TmpVal := 0
  Else If Value > 1 then
    TmpVal := 1
  Else If Value < 0.1 then
    TmpVal := 0.1
  Else
    TmpVal := Value;

  FTop_p := TmpVal;
end;

procedure TAiChat.SetTotal_tokens(const Value: Integer);
begin
  FTotal_tokens := Value;
end;

procedure TAiChat.SetUrl(const Value: String);
begin
  If Value <> '' then
    FUrl := Value
  Else
    FUrl := GlOpenAIUrl;
end;

procedure TAiChat.SetUser(const Value: String);
begin
  FUser := Value;
end;

Function TAiChat.FileCategoriesToString(const ACategories: TAiFileCategories): string;
var
  Category: TAiFileCategory;
  Parts: TStringDynArray;
begin
  SetLength(Parts, 0);
  if ACategories = [] then
    Exit('');

  for Category := Low(TAiFileCategory) to High(TAiFileCategory) do
  begin
    if Category in ACategories then
      Parts := Parts + [GetEnumName(TypeInfo(TAiFileCategory), Ord(Category))];
  end;
  Result := String.Join(',', Parts);
End;

Function TAiChat.StringToFileCategories(const AValue: string): TAiFileCategories;
var
  CategoryName: string;
  EnumValue: Integer;
begin
  Result := []; // We start with an empty set
  if AValue.IsEmpty then
    Exit;

  // We use TStringHelper's Split to divide by commas
  for CategoryName in AValue.Split([',']) do
  begin
    try
      // We get the enum ordinal value from its name
      EnumValue := GetEnumValue(TypeInfo(TAiFileCategory), Trim(CategoryName));
      // We include the value in the resulting set
      Include(Result, TAiFileCategory(EnumValue));
    except
      // Optional: Ignore invalid category names or raise an exception
      // Here we simply ignore them.
    end;
  end;
End;

function TAiChat.UploadFile(aMediaFile: TAiMediaFile): String;
begin
  // Overridden to upload a file to the model and return the file URI in the model
end;

function TAiChat.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer = 3600): String;
begin
  // Allows uploading files to cache; it can be moved between different requests of the same chat
end;

{ --- Default InternalRunNative* (Template Method hooks) --- }

function TAiChat.InternalRunNativeSpeechGeneration(ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native TTS. Assign a SpeechTool to ChatTools.');
end;

function TAiChat.InternalRunNativeTranscription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native transcription. Assign a SpeechTool to ChatTools.');
end;

function TAiChat.InternalRunNativeImageDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native vision. Assign a VisionTool to ChatTools.');
end;

function TAiChat.InternalRunNativeImageGeneration(ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native image generation. Assign an ImageTool to ChatTools.');
end;

function TAiChat.InternalRunNativeVideoGeneration(ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native video generation. Assign a VideoTool to ChatTools.');
end;

function TAiChat.InternalRunNativePDFDescription(aMediaFile: TAiMediaFile; ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native PDF support. Assign a PdfTool to ChatTools.');
end;

function TAiChat.InternalRunNativeWebSearch(ResMsg, AskMsg: TAiChatMessage): String;
begin
  Result := '';
  raise Exception.Create('This driver does not have native web search. Assign a WebSearchTool to ChatTools.');
end;

function TAiChat.InternalRunNativeReport(ResMsg, AskMsg: TAiChatMessage): String;
begin
  // Default: any driver can generate a text report via completions
  Result := InternalRunCompletions(ResMsg, AskMsg);
end;

{ --- SmartDispatch helpers --- }

procedure TAiChat.InternalRunSmartDispatch(ResMsg, AskMsg: TAiChatMessage);
var
  LSavedSystemPrompt : String;
  LOnData            : TAiChatOnDataEvent;
  LOnDataEnd         : TAiChatOnDataEvent;
  LSavedMessages     : TAiChatMessages;
  LTempSys           : TAiChatMessage;
  LTempUsr           : TAiChatMessage;
  LTag               : String;
  LContent           : String;
  LDispatchMsg       : TAiChatMessage;
  LDispatchPrompt    : String;
begin
  // --- Fast Pass 1: dedicated classifier (ChatTools.DispatchClassifier) ---
  // If it decides, the LLM classification call is saved. Differences from the
  // LLM pass: the tool receives the original prompt (the classifier does not
  // rewrite it) and CHAT responds with normal completions, WITH history (the
  // LLM pass responds in an isolated two-message context).
  LTag := ClassifySmartDispatch(AskMsg.Prompt);
  if LTag = 'CHAT' then
  begin
    InternalRunCompletions(ResMsg, AskMsg);
    Exit;
  end
  else if LTag <> '' then
  begin
    RunSmartDispatchTool(LTag, AskMsg.Prompt, ResMsg, AskMsg);
    Exit;
  end;

  LSavedSystemPrompt := FSystemPrompt.Text;
  LOnData            := FOnReceiveDataEvent;
  LOnDataEnd         := FOnReceiveDataEnd;
  LDispatchPrompt    := BuildSmartDispatchPrompt;

  // --- Pass 1: isolated context — only [system dispatch, user request] without history ---
  // Swap FMessages to a 2-message list so GetMessages sends only dispatch context
  LSavedMessages := FMessages;
  FMessages := TAiChatMessages.Create;
  FMessages.ModelCaps := LSavedMessages.ModelCaps;
  LTempSys := TAiChatMessage.Create(LDispatchPrompt, 'system');
  LTempSys.Id := 1;
  FMessages.Add(LTempSys);
  LTempUsr := TAiChatMessage.Create(AskMsg.Prompt, 'user');
  LTempUsr.Id := 2;
  FMessages.Add(LTempUsr);

  FOnReceiveDataEvent := nil;
  FOnReceiveDataEnd   := nil;
  FSystemPrompt.Text  := LDispatchPrompt;

  LDispatchMsg := TAiChatMessage.Create;
  try
    try
      DoStateChange(acsReasoning, 'Analyzing request...');
      // AskMsg = LTempUsr (already in the temporary FMessages): drivers do
      // AskMsg.Id := ... if it is not in the list, and with nil that was an AV that
      // RunNew's except converted into a silent empty response.
      InternalRunCompletions(LDispatchMsg, LTempUsr);
    except
      on E: Exception do
      begin
        DoError('SmartDispatch Pass1: ' + E.Message, E);
        raise;
      end;
    end;
  finally
    LTempSys.Free;             // TAiChatMessages is TList<T> — items are NOT auto-freed
    LTempUsr.Free;
    FMessages.Free;
    FMessages := LSavedMessages;
    FSystemPrompt.Text  := LSavedSystemPrompt;
    FOnReceiveDataEvent := LOnData;
    FOnReceiveDataEnd   := LOnDataEnd;
  end;

  ParseSmartDispatchResponse(LDispatchMsg.Prompt, LTag, LContent);
  LDispatchMsg.Free;

  // --- Pass 2: execute tool or return direct response ---
  if LTag = 'CHAT' then
  begin
    ResMsg.Prompt := LContent;
    ResMsg.Role   := 'assistant';
    DoData(ResMsg, 'assistant', LContent);
    DoDataEnd(ResMsg, 'assistant', LContent);
  end
  else
    RunSmartDispatchTool(LTag, LContent, ResMsg, AskMsg);
end;

procedure TAiChat.RunSmartDispatchTool(const ATag, AContent: String; ResMsg, AskMsg: TAiChatMessage);
var
  LToolAsk: TAiChatMessage;
begin
  LToolAsk := TAiChatMessage.Create;
  try
    LToolAsk.Prompt := AContent;
    LToolAsk.Role   := 'user';
    DoStateChange(acsToolExecuting, 'Executing: ' + ATag);
    if ATag = 'IMAGEGEN' then
      InternalRunImageGeneration(ResMsg, LToolAsk)
    else if ATag = 'VIDEOGEN' then
      InternalRunImageVideoGeneration(ResMsg, LToolAsk)
    else if ATag = 'TTS' then
      InternalRunSpeechGeneration(ResMsg, LToolAsk)
    else if ATag = 'WEBSEARCH' then
      InternalRunWebSearch(ResMsg, LToolAsk)
    else
      InternalRunCompletions(ResMsg, AskMsg);
  finally
    LToolAsk.Free;
  end;
end;

function TAiChat.SmartDispatchTags: TArray<String>;
var
  L: TList<String>;
begin
  L := TList<String>.Create;
  try
    if Assigned(FChatTools.FImageTool) then
      L.Add('IMAGEGEN');
    if Assigned(FChatTools.FVideoTool) then
      L.Add('VIDEOGEN');
    if Assigned(FChatTools.FSpeechTool) then
      L.Add('TTS');
    if Assigned(FChatTools.FWebSearchTool) then
      L.Add('WEBSEARCH');
    L.Add('CHAT');
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TAiChat.ClassifySmartDispatch(const APrompt: String): String;
var
  LClassifier: IAiDispatchClassifier;
  LTags: TArray<String>;
  LTag: String;
begin
  Result := '';
  if not Assigned(FChatTools.FDispatchClassifier) or
     not Supports(FChatTools.FDispatchClassifier, IAiDispatchClassifier, LClassifier) then
    Exit;

  LTags := SmartDispatchTags;
  FChatTools.FDispatchClassifier.SetContext(Self);
  DoStateChange(acsReasoning, 'Classifying request...');
  try
    Result := UpperCase(Trim(LClassifier.ClassifyDispatch(APrompt, LTags)));
  except
    // A failed classifier does not break the chat: it falls back to the LLM pass. It does not
    // fire OnError (many apps treat it as fatal); the classifier
    // logs its own error (e.g., TAiJev.LastError / OnError).
    on E: Exception do
    begin
      DoStateChange(acsReasoning, 'Classifier unavailable, using the LLM: ' + E.Message);
      Exit('');
    end;
  end;

  // Only tags whose tool is assigned are accepted
  for LTag in LTags do
    if LTag = Result then
      Exit;
  Result := '';
end;

function TAiChat.BuildSmartDispatchPrompt: String;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('You are a task dispatcher. Your ONLY job is to classify the user request and output exactly one line.');
    Lines.Add('Output format: [TAG] rewritten_request');
    Lines.Add('');
    Lines.Add('Available tags:');
    if Assigned(FChatTools.FImageTool) then
      Lines.Add('  [IMAGEGEN] <image description> — use when user asks to create, draw, or generate an image');
    if Assigned(FChatTools.FVideoTool) then
      Lines.Add('  [VIDEOGEN] <video description> — use when user asks to create or generate a video');
    if Assigned(FChatTools.FSpeechTool) then
      Lines.Add('  [TTS] <text to speak> — use when user asks to read aloud or generate audio/speech');
    if Assigned(FChatTools.FWebSearchTool) then
      Lines.Add('  [WEBSEARCH] <optimized search query> — use when user asks for recent news, current info, or web search');
    Lines.Add('  [CHAT] <your answer> — use for general conversation, questions, calculations, or anything else');
    Lines.Add('');
    Lines.Add('STRICT RULES:');
    Lines.Add('  - Output ONLY the single line [TAG] content. No other text, no explanations, no apologies.');
    Lines.Add('  - Do NOT say you cannot generate images/video — just use the appropriate tag.');
    Lines.Add('  - Always pick exactly ONE tag. [CHAT] is the fallback for anything not matched above.');
    Lines.Add('');
    Lines.Add('Examples:');
    Lines.Add('  User: draw a red cat => [IMAGEGEN] a red cat');
    Lines.Add('  User: latest AI news => [WEBSEARCH] latest artificial intelligence news 2025');
    Lines.Add('  User: what is 2+2 => [CHAT] 4');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

procedure TAiChat.ParseSmartDispatchResponse(const AResponse: String; out ATag, AContent: String);
var
  S: String;
  P: Integer;
begin
  ATag    := 'CHAT';
  AContent := AResponse;
  S := Trim(AResponse);
  if (S <> '') and (S[1] = '[') then
  begin
    P := Pos(']', S);
    if P > 1 then
    begin
      ATag     := UpperCase(Trim(Copy(S, 2, P - 2)));
      AContent := Trim(Copy(S, P + 1, MaxInt));
      // If the tag is not recognized, return the original response as CHAT
      if (ATag <> 'IMAGEGEN') and (ATag <> 'VIDEOGEN') and
         (ATag <> 'TTS') and (ATag <> 'WEBSEARCH') and
         (ATag <> 'CHAT') then
      begin
        ATag     := 'CHAT';
        AContent := AResponse;
      end;
    end;
  end;
end;

initialization
  GLogLock := TCriticalSection.Create; // ISSUE #115

finalization
  GLogLock.Free;

end.
