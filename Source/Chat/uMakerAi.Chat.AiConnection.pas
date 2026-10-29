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
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Chat.AiConnection;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Threading, System.NetEncoding, System.Rtti, System.TypInfo, System.StrUtils,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,
  System.JSON, Rest.JSON,
  uMakerAi.ParamsRegistry, uMakerAi.Tools.Functions, uMakerAi.Core, uMakerAi.Chat,
  uMakerAi.Tools.Shell, uMakerAi.Tools.TextEditor, uMakerAi.Tools.ComputerUse, uMakerAi.Chat.Tools, uMakerAi.Chat.Messages,
  uMakerAi.Memory.Types;

type
  TOnChatModelChangeEvent = procedure(Sender: TObject; const OldChat, NewChat: TAiChat) of object;

  TAiChatConnection = class(TComponent)
  private
    FChat: TAiChat;
    FDriverName: String;
    FModel: String;
    FParams: TStrings;
    // Cached view of the registry for the current driver/model pair. Avoids
    // re-reading the global registry on every assignment to Params. Invalidated by
    // key (driver|model|expansion) and by registry version.
    FRegCache: TStringList;
    FRegCacheKey: String;
    FRegCacheVersion: Integer;
    FMessages: TAiChatMessages;
    FMessagesOwn: TAiChatMessages; // Instance of messages that we own
    // FInitialInstructions: TStrings;
    FMemory: TStrings;
    FAiFunctions: TAiFunctions;
    FPrompt_tokens: integer;
    FCompletion_tokens: integer;
    FTotal_tokens: integer;

    // Events
    FOnReceiveData: TAiChatOnDataEvent;
    FOnReceiveDataEnd: TAiChatOnDataEvent;
    FOnAddMessage: TAiChatOnDataEvent;
    FOnCallToolFunction: TOnCallToolFunction;
    FOnBeforeSendMessage: TAiChatOnBeforeSendEvent;
    FOnInitChat: TAiChatOnInitChatEvent;
    FOnProcessMediaFile: TAiChatOnMediaFileEvent;
    FOnError: TAiErrorEvent;
    FOnChatModelChange: TOnChatModelChangeEvent;
    FOnProcessResponse: TAiChatOnProcessResponseEvent;
    FVersion: String;

    FOnReceiveThinking: TAiChatOnDataEvent;
    FChatTools: TAiChatTools;
    FSystemPrompt: TStrings;
    FOnStateChange: TAiStateChangeEvent;
    FChatMode: TAiChatMode;
    FSanitizerActive: Boolean;
    FOnSanitize: TAiSanitizeEvent;
    FOnPromptGuard: TAiPromptGuardEvent;

    FTtsParams: TAiTtsParams;
    FTranscriptionParams: TAiTranscriptionParams;
    FImageGenParams: TAiImageGenParams;
    FVideoGenParams: TAiVideoGenParams;
    FWebSearchParams: TAiWebSearchParams;
    FModelConfig: TAiModelConfig;

    // Structured response: passthrough to the driver (does not travel via Params/RTTI)
    FResponse_format: TAiChatResponseFormat;
    FJsonSchema: TStrings;

    FPersistentMemory:  TAiPersistentMemoryBase;
    FMemoryTokenBudget: Integer;
    FAutoStoreMemories: Boolean;
    FInternalParamsUpdate: Boolean; // guard: internal edits of FParams do not re-trigger ParamsChanged

    // v3.5 — Typed channel: ModelCaps/SessionCaps/Tool_Active/ThinkingLevel no longer
    // travel via Params/RTTI; their only channel is ModelConfig (+ registry via
    // ApplyAutoParams). These helpers maintain that rule.
    procedure StripModelConfigKeys(AParams: TStrings);
    procedure MigrateModelConfigParams(AParams: TStrings);
    procedure ApplyModelConfigToChat(AChat: TAiChat);

    // Setters and Getters
    procedure SetDriverName(const Value: String);
    procedure SetModel(const Value: String);
    procedure SetParams(const Value: TStrings);
    procedure SetChat(const Value: TAiChat);
    function GetLastError: String;
    function GetBusy: Boolean;
    procedure ParamsChanged(Sender: TObject);
    procedure ModelConfigChanged(Sender: TObject);
    procedure ChatToolsChanged(Sender: TObject);

    // Accessors for code shortcuts ModelCaps/SessionCaps/Tool_Active
    function GetModelCaps: TAiCapabilities;
    procedure SetModelCaps(const Value: TAiCapabilities);
    function GetSessionCaps: TAiCapabilities;
    procedure SetSessionCaps(const Value: TAiCapabilities);
    function GetTool_Active: Boolean;
    procedure SetTool_Active(const Value: Boolean);

    procedure SetCompletion_tokens(const Value: integer);
    procedure SetMemory(const Value: TStrings);
    procedure SetOnAddMessage(const Value: TAiChatOnDataEvent);
    procedure SetOnBeforeSendMessage(const Value: TAiChatOnBeforeSendEvent);
    procedure SetOnCallToolFunction(const Value: TOnCallToolFunction);
    procedure SetOnError(const Value: TAiErrorEvent);
    procedure SetOnInitChat(const Value: TAiChatOnInitChatEvent);
    procedure SetOnProcessMediaFile(const Value: TAiChatOnMediaFileEvent);
    procedure SetOnProcessResponse(const Value: TAiChatOnProcessResponseEvent);
    procedure SetOnReceiveData(const Value: TAiChatOnDataEvent);
    procedure SetOnReceiveDataEnd(const Value: TAiChatOnDataEvent);
    procedure SetPrompt_tokens(const Value: integer);
    procedure SetTotal_tokens(const Value: integer);
    procedure SetOnReceiveThinking(const Value: TAiChatOnDataEvent);

    procedure SetSystemPrompt(const Value: TStrings);
    procedure SetChatMode(const Value: TAiChatMode);

    procedure SetAiFunctions(const Value: TAiFunctions);
    procedure SetSanitizerActive(const Value: Boolean);
    procedure SetOnSanitize(const Value: TAiSanitizeEvent);
    procedure SetOnPromptGuard(const Value: TAiPromptGuardEvent);
    procedure SetPersistentMemory(const Value: TAiPersistentMemoryBase);
    procedure SetMemoryTokenBudget(const Value: Integer);
    procedure SetAutoStoreMemories(const Value: Boolean);
    procedure SetTtsParams(const Value: TAiTtsParams);
    procedure SetTranscriptionParams(const Value: TAiTranscriptionParams);
    procedure SetImageGenParams(const Value: TAiImageGenParams);
    procedure SetVideoGenParams(const Value: TAiVideoGenParams);
    procedure SetWebSearchParams(const Value: TAiWebSearchParams);
    procedure SetModelConfig(const Value: TAiModelConfig);
    procedure SetResponse_format(const Value: TAiChatResponseFormat);
    procedure SetJsonSchema(const Value: TStrings);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure ValideChat;
    // Copies the sub-object media params (Tts/Transcription/Image/Video/WebSearch) to the chat.
    // Needed on each execution: editing C.VideoParams.Params.Values[...] changes the
    // connection copy without going through the setter, and the already created chat would not notice.
    procedure SyncMediaParams;
    procedure UpdateAndApplyParams;
    procedure SetupChatFromDriver;
    procedure ApplyParamsToChat(AChat: TAiChat; AParams: TStrings);
    procedure ApplyEventsToChat(AChat: TAiChat; SetToNil: Boolean = False);
    Procedure OnInternalReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: String);
    // Adds the origin parameters to destination, returns destination if needed, the result remains in destination.
    Function MergeParams(Origin, Destination: TStrings): TStrings;
    procedure Loaded; override;

  public
    constructor Create(Sender: TComponent); override;
    destructor Destroy; override;

    Procedure UpdateParamsFromRegistry;
    function AddMessageAndRun(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String; overload;
    function AddMessage(aPrompt, aRole: String): TAiChatMessage;
    function NewMessage(aPrompt, aRole: String): TAiChatMessage;
    function Run(aMsg: TAiChatMessage = nil): String; virtual;
    function GetLastMessage: TAiChatMessage;
    function RemoveMesage(Msg: TAiChatMessage): Boolean; overload;
    function RemoveMesage(IdMsg: integer): Boolean; overload;
    procedure AddToMemory(Key, Value: String);
    procedure RemoveFromMemory(Key: String);
    procedure NewChat;
    procedure Abort;
    // ISSUE #115: control of debug log (opt-in). Delegates to the global
    // MakerAiDebugLogEnabled / MakerAiDebugLogPath from uMakerAi.Chat.
    procedure EnableDebugLog(const APath: string = '');
    procedure DisableDebugLog;
    function IsDebugLogEnabled: Boolean;
    function GetMessages: TJSonArray; virtual;
    function GetDriversNames: TStringList; virtual;
    function GetAvailableDrivers: TArray<string>;
    function GetModels: TStringList; overload; virtual;
    class function AvailableDrivers: TArray<string>; static;
    class function DriverNames: TStringList; static;
    function IsDriverAvailable(const DriverName: string): Boolean;
    procedure ResetParamsToDefaults;

    procedure RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string); overload;
    procedure RegisterUserParam(const DriverName, ParamName, ParamValue: string); overload;
    procedure ClearRegisterParams(const DriverName: String; ModelName: string = '');
    procedure RegisterCustomModel(const DriverName, CustomModelName, ModelBaseName: string);
    procedure ClearCustomModels(const DriverName: string);
    function GetBaseModel(const DriverName, CustomModel: string): string;

    function CreateChatForDriver(const aDriverName, aModel: string): TAiChatConnection;

    function UploadFile(aMediaFile: TAiMediaFile): String;
    function CheckFileState(aMediaFile: TAiMediaFile): String;
    function DeleteFile(aMediaFile: TAiMediaFile): String;
    function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer = 3600): String;

    property Messages: TAiChatMessages read FMessages;
    property LastError: String read GetLastError;
    property Busy: Boolean read GetBusy;
    property AiChat: TAiChat read FChat;

    // Code shortcuts, symmetric with TAiChat: the state lives in ModelConfig
    // (these aliases only delegate and set the pin UserFields as the sub-object).
    // Not published: the Object Inspector shows only ModelConfig.*
    property ModelCaps: TAiCapabilities read GetModelCaps write SetModelCaps;
    property SessionCaps: TAiCapabilities read GetSessionCaps write SetSessionCaps;
    property Tool_Active: Boolean read GetTool_Active write SetTool_Active;

  published
    property DriverName: String read FDriverName write SetDriverName;
    property Model: String read FModel write SetModel;
    property Params: TStrings read FParams write SetParams;
    // property InitialInstructions: TStrings read FInitialInstructions write SetInitialInstructions;
    property SystemPrompt: TStrings read FSystemPrompt write SetSystemPrompt;
    property Memory: TStrings read FMemory write SetMemory;
    property AiFunctions: TAiFunctions read FAiFunctions write SetAiFunctions;
    property Prompt_tokens: integer read FPrompt_tokens write SetPrompt_tokens;
    property Completion_tokens: integer read FCompletion_tokens write SetCompletion_tokens;
    property Total_tokens: integer read FTotal_tokens write SetTotal_tokens;

    Property OnReceiveThinking: TAiChatOnDataEvent read FOnReceiveThinking write SetOnReceiveThinking;
    property OnReceiveData: TAiChatOnDataEvent read FOnReceiveData write SetOnReceiveData;
    property OnReceiveDataEnd: TAiChatOnDataEvent read FOnReceiveDataEnd write SetOnReceiveDataEnd;
    property OnAddMessage: TAiChatOnDataEvent read FOnAddMessage write SetOnAddMessage;
    property OnCallToolFunction: TOnCallToolFunction read FOnCallToolFunction write SetOnCallToolFunction;
    property OnBeforeSendMessage: TAiChatOnBeforeSendEvent read FOnBeforeSendMessage write SetOnBeforeSendMessage;
    property OnInitChat: TAiChatOnInitChatEvent read FOnInitChat write SetOnInitChat;
    property OnProcessMediaFile: TAiChatOnMediaFileEvent read FOnProcessMediaFile write SetOnProcessMediaFile;
    property OnError: TAiErrorEvent read FOnError write SetOnError;
    property OnChatModelChange: TOnChatModelChangeEvent read FOnChatModelChange write FOnChatModelChange;
    property OnProcessResponse: TAiChatOnProcessResponseEvent read FOnProcessResponse write SetOnProcessResponse;
    Property Version: String Read FVersion;
    property ChatMode: TAiChatMode read FChatMode write SetChatMode default cmConversation;
    property OnStateChange: TAiStateChangeEvent read FOnStateChange write FOnStateChange;
    property SanitizerActive: Boolean read FSanitizerActive write SetSanitizerActive default False;
    property OnSanitize: TAiSanitizeEvent read FOnSanitize write SetOnSanitize;
    property OnPromptGuard: TAiPromptGuardEvent read FOnPromptGuard write SetOnPromptGuard;

    property PersistentMemory:  TAiPersistentMemoryBase read FPersistentMemory  write SetPersistentMemory;
    property MemoryTokenBudget: Integer    read FMemoryTokenBudget  write SetMemoryTokenBudget default 1500;
    property AutoStoreMemories: Boolean    read FAutoStoreMemories  write SetAutoStoreMemories default False;

    property TtsParams: TAiTtsParams read FTtsParams write SetTtsParams;
    property TranscriptionParams: TAiTranscriptionParams read FTranscriptionParams write SetTranscriptionParams;
    property ImageParams: TAiImageGenParams read FImageGenParams write SetImageGenParams;
    property VideoParams: TAiVideoGenParams read FVideoGenParams write SetVideoGenParams;
    property WebSearchParams: TAiWebSearchParams read FWebSearchParams write SetWebSearchParams;
    property ModelConfig: TAiModelConfig read FModelConfig write SetModelConfig;

    // Structured response: with tiaChatRfJsonSchema the schema goes in JsonSchema
    // (pure schema or full wrapper {name, schema}); arrives at the driver via
    // ApplyParamsToChat, same as SystemPrompt/Memory.
    property Response_format: TAiChatResponseFormat read FResponse_format write SetResponse_format default tiaChatRfText;
    property JsonSchema: TStrings read FJsonSchema write SetJsonSchema;

    // v3.5: the root shortcuts (SpeechTool, ImageTool, ...) have been removed.
    // ALL tools are assigned via ChatTools.XxxTool — the same surface
    // in TAiChat and TAiChatConnection. The streaming DFM/FMX resolves
    // references to components of TPersistent sub-objects via fixups.
    property ChatTools: TAiChatTools read FChatTools;

  end;

procedure Register;

implementation

{$I ..\Core\uMakerAi.Version.inc}
{$R ..\Resources\uMakerAiResources.res}

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiChatConnection]);
end;

{ TAiChatConnection }

constructor TAiChatConnection.Create(Sender: TComponent);
begin
  inherited;
  FChat := nil;
  FChatTools := TAiChatTools.Create(Self);
  FChatTools.OnChange := ChatToolsChanged;
  FSystemPrompt := TStringList.Create;
  FMemory := TStringList.Create;
  FMessagesOwn := TAiChatMessages.Create;
  FMessages := FMessagesOwn; // By default, FMessages points to our own instance
  FParams := TStringList.Create;
  TStringList(FParams).OnChange := ParamsChanged;
  TStringList(FSystemPrompt).OnChange := ParamsChanged;
  TStringList(FMemory).OnChange := ParamsChanged;
  FVersion := MAKERAI_VERSION_FULL;

  FTtsParams := TAiTtsParams.Create;
  FTranscriptionParams := TAiTranscriptionParams.Create;
  FImageGenParams := TAiImageGenParams.Create;
  FVideoGenParams := TAiVideoGenParams.Create;
  FWebSearchParams := TAiWebSearchParams.Create;
  FModelConfig := TAiModelConfig.Create;
  FModelConfig.OnChange := ModelConfigChanged;

  FResponse_format := tiaChatRfText;
  FJsonSchema := TStringList.Create;
  TStringList(FJsonSchema).OnChange := ParamsChanged; // direct mutation (JsonSchema.Text := ...) also propagates

  FPersistentMemory  := nil;
  FMemoryTokenBudget := 1500;
  FAutoStoreMemories := False;
end;

destructor TAiChatConnection.Destroy;
begin
  FreeAndNil(FChat);  // nil before freeing FSystemPrompt/FMemory/FParams (OnChange=ParamsChanged checks FChat)

  FRegCache.Free;

  FChatTools.Free;
  FSystemPrompt.Free;
  FJsonSchema.Free; // after FreeAndNil(FChat): its OnChange=ParamsChanged queries FChat
  FMemory.Free;

  FTtsParams.Free;
  FTranscriptionParams.Free;
  FImageGenParams.Free;
  FVideoGenParams.Free;
  FWebSearchParams.Free;
  FModelConfig.Free;

  // FMessages is just a reference, NOT freed
  FMessagesOwn.Free;
  FParams.Free;
  inherited;
end;

{ procedure TAiChatConnection.SetDriverName(const Value: String);
  begin
  if FDriverName <> Value then
  begin
  FDriverName := Value;
  FModel := ''; // When changing driver, reset the model.
  UpdateAndApplyParams;

  if not(csDesigning in ComponentState) then
  begin
  SetupChatFromDriver;
  end;
  end;
  end;
}

procedure TAiChatConnection.SetDriverName(const Value: String);
begin
  if FDriverName <> Value then
  begin
    FDriverName := Value;
    FModel := '';

    // Only update the FParams list with the defaults of the new driver,
    // but do NOT apply them to the old chat if we are going to change it immediately.

    // Option A (Simple): Leave it as is (works, but applies params to the old chat).
    // UpdateAndApplyParams;

    // Option B (Optimization): Load params but do not apply to the old chat.
    if not(csDesigning in ComponentState) then
    begin
      // Load defaults into FParams without applying them to the current FChat
      // (You could refactor UpdateAndApplyParams to accept a boolean 'ApplyToChat')
      UpdateAndApplyParams;
      SetupChatFromDriver; // This will create the new chat and apply the params to it
    end
    else
    begin
      // In design time only update params visually
      UpdateAndApplyParams;
    end;
  end;
end;

procedure TAiChatConnection.SetModel(const Value: String);
begin
  if FModel <> Value then
  begin
    FModel := Value;
    // Previously, this did:
    //   TAiChatFactory.Instance.RegisterUserParam(FDriverName, FModel, 'Model', FModel);
    // i.e., it WROTE to the GLOBAL registry on every model change, only
    // so that the value would come back in GetDriverParams and beat the
    // 'Model=<default>' from RegisterDefaultParams of the driver.
    //
    // That was state of THIS connection traveling through a global variable: on a
    // server with multiple concurrent requests, that write ran simultaneously with
    // reads from other threads on the same structures, without any synchronization.
    // Measured with the conn.concurrent.setup case from the test suite:
    // 1 out of 320,000 setups ended with EInvalidPointer.
    //
    // The model is now imposed at the end of UpdateAndApplyParams, on FParams,
    // which is local to the connection. Same effect, without touching the global registry.
    UpdateAndApplyParams;
  end;
end;

procedure TAiChatConnection.SetParams(const Value: TStrings);
begin
  if Assigned(Value) then
    FParams.Assign(Value);
end;

procedure TAiChatConnection.ParamsChanged(Sender: TObject);
begin
  if FInternalParamsUpdate then
    Exit; // internal edit (migration of typed keys): do not re-apply

  if Assigned(FChat) then
  begin
    ApplyParamsToChat(FChat, FParams);
  end;
end;

procedure TAiChatConnection.ModelConfigChanged(Sender: TObject);
begin
  // Propagates changes made via Connection.ModelConfig.Xxx := ... (direct mutation of the
  // sub-object) to the real TAiChat. SetModelConfig already covers assignment of the whole object;
  // this covers the path that previously required a manual SyncModelConfig (see Apps/MakerAIChat).
  if Assigned(FChat) then
    ApplyModelConfigToChat(FChat);
end;

// Copies the user's explicit configuration to the chat and completes the fields
// NOT set with the registry values for the current driver/model.
// This is the ONLY path by which ModelCaps/SessionCaps/Tool_Active/
// ThinkingLevel reach the chat (v3.5: removed from the Params/RTTI channel).
procedure TAiChatConnection.ApplyModelConfigToChat(AChat: TAiChat);
var
  LRegParams: TStringList;
begin
  if not Assigned(AChat) then
    Exit;

  AChat.ModelConfig.Assign(FModelConfig); // explicit intention (with UserFields marks)

  if (FDriverName <> '') and TAiChatFactory.Instance.HasDriver(FDriverName) then
  begin
    LRegParams := TStringList.Create;
    try
      TAiChatFactory.Instance.GetDriverParams(FDriverName, FModel, LRegParams, False);
      AChat.ModelConfig.ApplyAutoParams(LRegParams); // registry fills what is not set
    finally
      LRegParams.Free;
    end;
  end;
end;

// Removes the 4 typed keys from a param list (e.g., the registry view)
// so they never enter FParams or pass through RTTI injection.
procedure TAiChatConnection.StripModelConfigKeys(AParams: TStrings);
const
  Keys: array [0 .. 3] of string = ('ModelCaps', 'SessionCaps', 'Tool_Active', 'ThinkingLevel');
var
  K: string;
  I: integer;
begin
  if not Assigned(AParams) then
    Exit;
  for K in Keys do
  begin
    I := AParams.IndexOfName(K);
    if I >= 0 then
      AParams.Delete(I);
  end;
end;

// Backward compatibility: if the user (old DFM or code) wrote the typed keys
// in Params, they are interpreted as EXPLICIT configuration:
// applied to ModelConfig, pinned (UserFields), and removed from Params.
// The presence of the key sets the field even if the value matches the current
// (e.g., agents write SessionCaps=[] to force empty caps).
procedure TAiChatConnection.MigrateModelConfigParams(AParams: TStrings);
var
  I: integer;
  Val: string;
begin
  if not Assigned(AParams) then
    Exit;

  FInternalParamsUpdate := True;
  try
    I := AParams.IndexOfName('ModelCaps');
    if I >= 0 then
    begin
      FModelConfig.ModelCaps := TAiModelConfig.StringToCaps(AParams.ValueFromIndex[I]);
      FModelConfig.UserFields := FModelConfig.UserFields + [mcfModelCaps];
      AParams.Delete(I);
    end;

    I := AParams.IndexOfName('SessionCaps');
    if I >= 0 then
    begin
      FModelConfig.SessionCaps := TAiModelConfig.StringToCaps(AParams.ValueFromIndex[I]);
      FModelConfig.UserFields := FModelConfig.UserFields + [mcfSessionCaps];
      AParams.Delete(I);
    end;

    I := AParams.IndexOfName('Tool_Active');
    if I >= 0 then
    begin
      Val := AParams.ValueFromIndex[I].Trim.ToLower;
      FModelConfig.Tool_Active := (Val = 'true') or (Val = '1') or (Val = 'yes') or (Val = 't');
      FModelConfig.UserFields := FModelConfig.UserFields + [mcfToolActive];
      AParams.Delete(I);
    end;

    I := AParams.IndexOfName('ThinkingLevel');
    if I >= 0 then
    begin
      FModelConfig.ThinkingLevel := TAiModelConfig.StringToThinkingLevel(AParams.ValueFromIndex[I]);
      FModelConfig.UserFields := FModelConfig.UserFields + [mcfThinkingLevel];
      AParams.Delete(I);
    end;
  finally
    FInternalParamsUpdate := False;
  end;
end;

{ procedure TAiChatConnection.SetupChatFromDriver;
  var
  OldChat, NewChat: TAiChat;
  begin

  if csLoading in ComponentState then
  Exit;

  if FDriverName = '' then
  begin
  if Assigned(FChat) then
  FreeAndNil(FChat);
  Exit;
  end;

  OldChat := FChat;
  FChat := nil;

  NewChat := TAiChatFactory.Instance.CreateDriver(FDriverName);
  if not Assigned(NewChat) then
  raise Exception.CreateFmt('Failed to create driver instance for "%s"', [FDriverName]);

  if Assigned(FOnChatModelChange) then
  FOnChatModelChange(Self, OldChat, NewChat);

  ApplyParamsToChat(NewChat, FParams);
  ApplyEventsToChat(NewChat);

  SetChat(NewChat);

  if Assigned(OldChat) then
  OldChat.Free;
  end;
}

procedure TAiChatConnection.SetupChatFromDriver;
var
  OldChat, NewChat: TAiChat;
begin
  if csLoading in ComponentState then
    Exit;

  if FDriverName = '' then
  begin
    if Assigned(FChat) then
      FreeAndNil(FChat);
    Exit;
  end;

  OldChat := FChat;
  FChat := nil; // Temporarily unbind to avoid side effects in the Setter

  NewChat := TAiChatFactory.Instance.CreateDriver(FDriverName);
  if not Assigned(NewChat) then
    raise Exception.CreateFmt('Failed to create driver instance for "%s"', [FDriverName]);

  if Assigned(FOnChatModelChange) then
    FOnChatModelChange(Self, OldChat, NewChat);

  // When calling SetChat, it will take care of applying Params and Events
  SetChat(NewChat);

  if Assigned(OldChat) then
    OldChat.Free;
end;

{ procedure TAiChatConnection.UpdateAndApplyParams;
  Var
  LParams: TStringList;
  begin

  if csLoading in ComponentState then
  Exit;

  if FDriverName = '' then
  begin
  FParams.Clear;
  Exit;
  end;

  if TAiChatFactory.Instance.HasDriver(FDriverName) then
  begin
  Var
  ShouldExpand := not(csDesigning in ComponentState);
  LParams := TStringList.Create;
  Try
  TAiChatFactory.Instance.GetDriverParams(FDriverName, FModel, LParams, ShouldExpand);
  MergeParams(LParams, FParams).Text; // Adds or updates FParams from LParams
  Finally
  LParams.Free;
  End;
  end
  else
  FParams.Clear;

  if Assigned(FChat) then
  begin
  ApplyParamsToChat(FChat, FParams);
  end;
  end;
}

procedure TAiChatConnection.UpdateAndApplyParams;
var
  LRegistryParams: TStringList;
  ShouldExpand: Boolean;
  LCacheKey: String;
  LRegVersion: Integer;
begin
  if csLoading in ComponentState then
    Exit;

  if FDriverName = '' then
  begin
    FParams.Clear;
    Exit;
  end;

  if TAiChatFactory.Instance.HasDriver(FDriverName) then
  begin
    // Safety: Do not expand API keys at design time
    ShouldExpand := not(csDesigning in ComponentState);

    // Cached registry view per connection.
    //
    // This method is called on EVERY assignment to Params (ParamsChanged), i.e.,
    // about eight times per request on a server, and each call re-read the
    // entire global registry. It now re-reads only when the driver, the model,
    // the expansion mode, or the registry version changes (the latter only
    // increments on startup registrations). The rest are cache hits.
    LCacheKey := FDriverName + '|' + FModel + '|' + BoolToStr(ShouldExpand, True);
    LRegVersion := TAiChatFactory.Instance.Version;
    if (not Assigned(FRegCache)) or (FRegCacheKey <> LCacheKey) or
       (FRegCacheVersion <> LRegVersion) then
    begin
      if not Assigned(FRegCache) then
        FRegCache := TStringList.Create;
      TAiChatFactory.Instance.GetDriverParams(FDriverName, FModel, FRegCache, ShouldExpand);

      // v3.5: ModelCaps/SessionCaps/Tool_Active/ThinkingLevel do NOT travel via Params.
      // They are removed from the registry view before merging; they reach the chat via
      // ApplyModelConfigToChat (typed channel ModelConfig + ApplyAutoParams).
      StripModelConfigKeys(FRegCache);

      FRegCacheKey     := LCacheKey;
      FRegCacheVersion := LRegVersion;
    end;

    // Work on a COPY: MergeParams may modify the source list, and the cached one must remain intact for the next hit.
    LRegistryParams := TStringList.Create;
    try
      LRegistryParams.Assign(FRegCache);

      // 2. Intelligent synchronization:
      // Instead of a simple Merge, we ensure FParams reflects the structure of the new model.

      FParams.BeginUpdate;
      try
        // NOTE: MergeParams updates FParams with registry values; keys that the registry
        // brings for the current driver/model OVERWRITE what was in FParams (needed so that
        // changing the model refreshes Max_Tokens, ModelCaps, etc. and does not leave values
        // from the previous model). Keys unknown to the registry are preserved.
        // For durable customization use:
        //   - TAiChatFactory.Instance.RegisterUserParam(...)  (user level in registry)
        //   - Connection.ModelConfig.ModelCaps/SessionCaps    (explicit; ApplyParamsToChat
        //     respects it via UserConfigured and the registry no longer overrides it)
        MergeParams(LRegistryParams, FParams);

        // The model is state of THIS connection. It is imposed AFTER the merge
        // because the registry brings 'Model=<default of the driver>' (level 1,
        // RegisterDefaultParams) and would otherwise overwrite the requested model. Previously
        // this was solved by writing the model to the global registry from
        // SetModel; see the note there.
        if FModel <> '' then
          FParams.Values['Model'] := FModel;
      finally
        FParams.EndUpdate;
      end;

    finally
      LRegistryParams.Free;
    end;
  end
  else
    FParams.Clear;

  // 3. Inject the final parameters into the Chat engine
  if Assigned(FChat) then
  begin
    ApplyParamsToChat(FChat, FParams);
  end;
end;

procedure TAiChatConnection.UpdateParamsFromRegistry;
begin
  UpdateAndApplyParams;
end;

procedure TAiChatConnection.ValideChat;
begin
  if not Assigned(FChat) and (FDriverName <> '') then
  begin
    SetupChatFromDriver;
  end;

  if not Assigned(FChat) then
    raise Exception.Create('A valid DriverName must be specified to create a Chat instance.');
end;

procedure TAiChatConnection.SyncMediaParams;
begin
  if not Assigned(FChat) then
    Exit;
  FChat.TtsParams.Assign(FTtsParams);
  FChat.TranscriptionParams.Assign(FTranscriptionParams);
  FChat.ImageParams.Assign(FImageGenParams);
  FChat.VideoParams.Assign(FVideoGenParams);
  FChat.WebSearchParams.Assign(FWebSearchParams);
end;

procedure TAiChatConnection.ApplyParamsToChat(AChat: TAiChat; AParams: TStrings);
var
  LContext: TRttiContext;
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  LValue: TValue;
  I: integer;
  ParamName, ParamValue: string;
  LIntVal: Int64;
  LFloatVal: Double;
begin
  if not Assigned(AChat) then
    Exit;

  // v3.5: if Params contains typed keys (old DFM or user code), they are
  // migrated to ModelConfig as explicit configuration and removed from Params.
  MigrateModelConfigParams(AParams);

  // 1. DIRECT STRUCTURE ASSIGNMENTS (Priority v1.5)
  AChat.AiFunctions := Self.AiFunctions;

  // Inject orchestrator state
  AChat.ChatMode := Self.ChatMode;

  // Inject tools (ChatTools)
  AChat.ChatTools.Assign(Self.FChatTools);

  // Inject sanitizer configuration
  AChat.SanitizerActive := Self.FSanitizerActive;

  // Inject persistent memory
  AChat.PersistentMemory  := Self.FPersistentMemory;
  AChat.MemoryTokenBudget := Self.FMemoryTokenBudget;
  AChat.AutoStoreMemories := Self.FAutoStoreMemories;

  // Inject special parameter sub-objects
  AChat.TtsParams.Assign(Self.FTtsParams);
  AChat.TranscriptionParams.Assign(Self.FTranscriptionParams);
  AChat.ImageParams.Assign(Self.FImageGenParams);
  AChat.VideoParams.Assign(Self.FVideoGenParams);
  AChat.WebSearchParams.Assign(Self.FWebSearchParams);

  // Typed channel: explicit user config + registry for what is not set
  ApplyModelConfigToChat(AChat);

  // Base context
  AChat.Memory.Text := Self.Memory.Text;
  AChat.SystemPrompt.Text := Self.SystemPrompt.Text;

  // Structured response (direct passthrough; Params/RTTI may overwrite
  // Response_format below if the user explicitly set it in Params)
  AChat.Response_format := FResponse_format;
  AChat.JsonSchema.Text := FJsonSchema.Text;

  // 2. DYNAMIC INJECTION VIA PARAMS (RTTI)
  if not Assigned(AParams) or (AParams.Count <= 0) then
    Exit;

  LContext := TRttiContext.Create;
  try
    LRttiType := LContext.GetType(AChat.ClassType);

    for I := 0 to AParams.Count - 1 do
    begin
      ParamName := AParams.Names[I];
      ParamValue := AParams.Values[ParamName].Trim;

      if ParamName.IsEmpty then
        Continue;

      // Historical alias: the catalog (OpenAI TTS) and the demo 012 use 'Voice_Format',
      // but the property is TtsParams.VoiceFormat; without this it was silently ignored
      if SameText(ParamName, 'Voice_Format') then
        ParamName := 'VoiceFormat';

      // v3.5: typed keys are NEVER injected via RTTI (their only channel is
      // ModelConfig). After StripModelConfigKeys/MigrateModelConfigParams they
      // should not be here; this skip is the safety net.
      if SameText(ParamName, 'ModelCaps') or SameText(ParamName, 'SessionCaps') or
         SameText(ParamName, 'Tool_Active') or SameText(ParamName, 'ThinkingLevel') then
        Continue;

      // Search first in the main object, then in TPersistent sub-objects (2-level RTTI)
      var LTarget: TObject := AChat;
      LProp := LRttiType.GetProperty(ParamName);

      if not Assigned(LProp) then
      begin
        for var LSubPropDef in LRttiType.GetProperties do
        begin
          if LSubPropDef.PropertyType.IsInstance then
          begin
            var LSubObj := LSubPropDef.GetValue(AChat).AsObject;
            if LSubObj is TPersistent then
            begin
              var LSubType := LContext.GetType(LSubObj.ClassType);
              var LSubProp := LSubType.GetProperty(ParamName);
              if Assigned(LSubProp) and LSubProp.IsWritable then
              begin
                LProp := LSubProp;
                LTarget := LSubObj;
                Break;
              end;
            end;
          end;
        end;
      end;

      if Assigned(LProp) and LProp.IsWritable then
      begin
        try
          case LProp.PropertyType.TypeKind of
            tkInteger, tkInt64:
              if TryStrToInt64(ParamValue, LIntVal) then
                LProp.SetValue(LTarget, LIntVal);

            tkFloat:
              if TryStrToFloat(ParamValue, LFloatVal, TFormatSettings.Invariant) or
                 TryStrToFloat(ParamValue, LFloatVal) then
                LProp.SetValue(LTarget, LFloatVal);

            tkString, tkUString, tkWideString:
              LProp.SetValue(LTarget, ParamValue);

            tkEnumeration:
              begin
                if LProp.PropertyType.Handle = TypeInfo(Boolean) then
                  LValue := MatchStr(LowerCase(ParamValue), ['true', '1', 'yes', 't'])
                else
                  LValue := TValue.FromOrdinal(LProp.PropertyType.Handle, GetEnumValue(LProp.PropertyType.Handle, ParamValue));
                LProp.SetValue(LTarget, LValue);
              end;

            tkSet:
              begin
                var
                LSetType := LProp.PropertyType as TRttiSetType;
                if LSetType.ElementType.TypeKind = tkEnumeration then
                begin
                  var
                  LEnumType := LSetType.ElementType;
                  var
                    SetAsInt: NativeInt := 0;

                  if (not ParamValue.IsEmpty) and (ParamValue <> '[]') then
                  begin
                    var
                    CleanValue := ParamValue.Trim(['[', ']', ' ']);
                    var
                    EnumNames := CleanValue.Split([',']);
                    for var EnumName in EnumNames do
                    begin
                      var
                      TrimmedName := Trim(EnumName);
                      if not TrimmedName.IsEmpty then
                      begin
                        // GetEnumValue is case-sensitive according to the Enum defined in uMakerAi.Core
                        var
                        OrdinalValue := GetEnumValue(LEnumType.Handle, TrimmedName);
                        if OrdinalValue >= 0 then
                          SetAsInt := SetAsInt or (1 shl OrdinalValue);
                      end;
                    end;
                  end;
                  TValue.Make(@SetAsInt, LSetType.Handle, LValue);
                  LProp.SetValue(LTarget, LValue);
                end;
              end;

            tkClass:
              begin
                if LProp.PropertyType.QualifiedName.EndsWith('TStrings') then
                begin
                  var
                  LStringsProp := LProp.GetValue(LTarget).AsObject as TStrings;
                  if Assigned(LStringsProp) then
                    LStringsProp.Text := StringReplace(ParamValue, '|', sLineBreak, [rfReplaceAll]);
                end;
              end;
          end;
        except
          // Silent failure for individual property to avoid stopping the rest of the injection
        end;
      end;
    end;
  finally
    LContext.Free;
  end;
end;

procedure TAiChatConnection.ApplyEventsToChat(AChat: TAiChat; SetToNil: Boolean);
begin
  if not Assigned(AChat) then
    Exit;

  if SetToNil then
  begin
    AChat.OnReceiveData := nil;
    AChat.OnReceiveDataEnd := nil;
    AChat.OnReceiveThinking := Nil;
    AChat.OnAddMessage := nil;
    AChat.OnCallToolFunction := nil;
    AChat.OnBeforeSendMessage := nil;
    AChat.OnInitChat := nil;
    AChat.OnProcessMediaFile := nil;
    AChat.OnProcessResponse := nil;
    AChat.OnError := nil;
    AChat.OnStateChange := nil;
    AChat.OnSanitize := nil;
    AChat.OnPromptGuard := nil;

  end
  else
  begin
    AChat.OnReceiveData := Self.OnReceiveData;
    AChat.OnReceiveDataEnd := OnInternalReceiveDataEnd; // Self.OnReceiveDataEnd;
    AChat.OnReceiveThinking := Self.OnReceiveThinking;
    AChat.OnAddMessage := Self.OnAddMessage;
    AChat.OnCallToolFunction := Self.OnCallToolFunction;
    AChat.OnBeforeSendMessage := Self.OnBeforeSendMessage;
    AChat.OnInitChat := Self.OnInitChat;
    AChat.OnProcessMediaFile := Self.OnProcessMediaFile;
    AChat.OnProcessResponse := Self.OnProcessResponse;
    AChat.OnError := Self.OnError;
    AChat.OnStateChange := Self.FOnStateChange;
    AChat.OnSanitize := Self.FOnSanitize;
    AChat.OnPromptGuard := Self.FOnPromptGuard;
  end;
end;

procedure TAiChatConnection.ResetParamsToDefaults;
begin
  UpdateAndApplyParams;
end;

procedure TAiChatConnection.RegisterUserParam(const DriverName, ModelName, ParamName, ParamValue: string);
begin
  TAiChatFactory.Instance.RegisterUserParam(DriverName, ModelName, ParamName, ParamValue);
  if (DriverName = FDriverName) and (ModelName = FModel) then
    UpdateAndApplyParams;
end;

procedure TAiChatConnection.RegisterUserParam(const DriverName, ParamName, ParamValue: string);
begin
  TAiChatFactory.Instance.RegisterUserParam(DriverName, ParamName, ParamValue);
  if (DriverName = FDriverName) then
    UpdateAndApplyParams;
end;

procedure TAiChatConnection.ClearRegisterParams(const DriverName: String; ModelName: string);
begin
  TAiChatFactory.Instance.ClearRegisterParams(DriverName, ModelName);
  if (DriverName = FDriverName) then
    UpdateAndApplyParams;
end;

procedure TAiChatConnection.RegisterCustomModel(const DriverName, CustomModelName, ModelBaseName: string);
begin
  TAiChatFactory.Instance.RegisterCustomModel(DriverName, CustomModelName, ModelBaseName);
  // If we are using this driver, refresh the available model list
  if DriverName = FDriverName then
    UpdateAndApplyParams;
end;

procedure TAiChatConnection.ClearCustomModels(const DriverName: string);
begin
  TAiChatFactory.Instance.ClearCustomModels(DriverName);
  if DriverName = FDriverName then
    UpdateAndApplyParams;
end;

function TAiChatConnection.GetBaseModel(const DriverName, CustomModel: string): string;
begin
  Result := TAiChatFactory.Instance.GetBaseModel(DriverName, CustomModel);
end;

function TAiChatConnection.CreateChatForDriver(const aDriverName, aModel: string): TAiChatConnection;
var
  LChat: TAiChat;
  LModels: TStringList;
begin
  if not IsDriverAvailable(aDriverName) then
    raise Exception.CreateFmt('Driver "%s" not found or is not registered.', [aDriverName]);

  // Validate that the driver and model exist
  LChat := TAiChatFactory.Instance.CreateDriver(aDriverName);
  Try
    if not Assigned(LChat) then
      raise Exception.CreateFmt('Failed to create an instance for driver "%s".', [aDriverName]);

    LModels := LChat.GetModels;
    Try
      LModels.Sort;

      If LModels.IndexOf(aModel) < 0 then
        raise Exception.CreateFmt('Failed to create an instance, model "%s" not found.', [aModel]);

    Finally
      LModels.Free;
    End;

  Finally
    LChat.Free;
  End;
  Result := TAiChatConnection.Create(Self.Owner);
  Result.DriverName := aDriverName;
  Result.Model := aModel;
end;

// --- Action and façade methods ---

procedure TAiChatConnection.Abort;
begin
  ValideChat;
  FChat.Abort;
end;

function TAiChatConnection.AddMessage(aPrompt, aRole: String): TAiChatMessage;
begin
  ValideChat;
  Result := FChat.AddMessage(aPrompt, aRole);
end;

function TAiChatConnection.AddMessageAndRun(aPrompt, aRole: String; aMediaFiles: TAiMediaFilesArray): String;
begin
  ValideChat;
  SyncMediaParams;
  Result := FChat.AddMessageAndRun(aPrompt, aRole, aMediaFiles);
end;

procedure TAiChatConnection.AddToMemory(Key, Value: String);
begin
  ValideChat;
  FMemory.AddPair(Key, Value);
  FChat.AddToMemory(Key, Value);
end;

function TAiChatConnection.CheckFileState(aMediaFile: TAiMediaFile): String;
begin
  ValideChat;
  Result := FChat.CheckFileState(aMediaFile);
end;

function TAiChatConnection.DeleteFile(aMediaFile: TAiMediaFile): String;
begin
  ValideChat;
  Result := FChat.DeleteFile(aMediaFile);
end;

function TAiChatConnection.GetAvailableDrivers: TArray<string>;
begin
  Result := TAiChatFactory.Instance.GetRegisteredDrivers;
end;

class function TAiChatConnection.AvailableDrivers: TArray<string>;
begin
  Result := TAiChatFactory.Instance.GetRegisteredDrivers;
end;

class function TAiChatConnection.DriverNames: TStringList;
var
  D: string;
begin
  Result := TStringList.Create;
  for D in TAiChatFactory.Instance.GetRegisteredDrivers do
    Result.Add(D);
end;

function TAiChatConnection.GetBusy: Boolean;
begin
  if Assigned(FChat) then
    Result := FChat.Busy
  else
    Result := False;
end;

function TAiChatConnection.GetDriversNames: TStringList;
var
  AvailableDrivers: TArray<string>;
  DriverName: string;
begin
  Result := TStringList.Create;
  AvailableDrivers := TAiChatFactory.Instance.GetRegisteredDrivers;
  for DriverName in AvailableDrivers do
    Result.Add(DriverName);
end;

function TAiChatConnection.GetLastError: String;
begin
  if Assigned(FChat) then
    Result := FChat.LastError
  else
    Result := '';
end;

function TAiChatConnection.GetLastMessage: TAiChatMessage;
begin
  ValideChat;
  Result := FChat.GetLastMessage;
end;

function TAiChatConnection.GetMessages: TJSonArray;
begin
  ValideChat;
  Result := FChat.GetMessages;
end;

function TAiChatConnection.GetModels: TStringList;
begin
  ValideChat;
  Result := FChat.GetModels;
end;

function TAiChatConnection.IsDriverAvailable(const DriverName: string): Boolean;
begin
  Result := TAiChatFactory.Instance.HasDriver(DriverName);
end;

procedure TAiChatConnection.Loaded;
begin
  inherited;
  SetupChatFromDriver;
end;

function TAiChatConnection.MergeParams(Origin, Destination: TStrings): TStrings;
var
  I: integer;
begin
  // Origin (registry) takes precedence: updates the key if it exists or adds it if not,
  // without duplication. Destination only keeps keys that Origin does not bring.
  Result := Destination;
  for I := 0 to Origin.Count - 1 do
  begin
    Destination.Values[Origin.Names[I]] := Origin.ValueFromIndex[I];
  end;
end;

procedure TAiChatConnection.NewChat;
begin
  ValideChat;
  FChat.NewChat;
end;

function TAiChatConnection.NewMessage(aPrompt, aRole: String): TAiChatMessage;
begin
  ValideChat;
  Result := FChat.NewMessage(aPrompt, aRole);
end;

procedure TAiChatConnection.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if Operation = opRemove then
  begin
    // 1. Clear tool references in the Connection
    FChatTools.Notification(AComponent, Operation);
    if AComponent = FAiFunctions then
      FAiFunctions := nil;

    // 2. IMPORTANT: If there is an active chat, synchronize the 'nil'
    // to prevent the main Chat from trying to use a destroyed object.
    if Assigned(FChat) then
    begin
      FChat.ChatTools.Notification(AComponent, Operation);
      if AComponent = FAiFunctions then
        FChat.AiFunctions := nil;
    end;

    if AComponent = FPersistentMemory then
    begin
      FPersistentMemory := nil;
      if Assigned(FChat) then
        FChat.PersistentMemory := nil;
    end;
  end;
end;

procedure TAiChatConnection.OnInternalReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: String);
begin
  if Assigned(aMsg) then
  begin
    Prompt_tokens := Prompt_tokens + aMsg.Prompt_tokens;
    Completion_tokens := Completion_tokens + aMsg.Completion_tokens;
    Total_tokens := Total_tokens + aMsg.Total_tokens;
  end;

  If Assigned(FOnReceiveDataEnd) then
    FOnReceiveDataEnd(Sender, aMsg, aResponse, aRole, aText);
end;

procedure TAiChatConnection.RemoveFromMemory(Key: String);
begin
  ValideChat;
  FMemory.Values[Key] := '';
  FChat.RemoveFromMemory(Key);
end;

function TAiChatConnection.RemoveMesage(Msg: TAiChatMessage): Boolean;
begin
  ValideChat;
  Result := FChat.RemoveMesage(Msg);
end;

function TAiChatConnection.RemoveMesage(IdMsg: integer): Boolean;
begin
  ValideChat;
  Result := FChat.RemoveMesage(IdMsg);
end;

function TAiChatConnection.Run(aMsg: TAiChatMessage = nil): String;
begin
  ValideChat;
  SyncMediaParams;
  Result := FChat.Run(aMsg, nil)
end;

function TAiChatConnection.UploadFile(aMediaFile: TAiMediaFile): String;
begin
  ValideChat;
  Result := FChat.UploadFile(aMediaFile);
end;

function TAiChatConnection.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: integer): String;
begin
  ValideChat;
  Result := FChat.UploadFileToCache(aMediaFile, aTTL_Seconds);
end;

// --- Property and Event Setters ---

procedure TAiChatConnection.SetChat(const Value: TAiChat);
begin
  if FChat <> Value then
  begin
    // If there was a previous chat, apply configuration
    if Assigned(FChat) then
    Begin
      ApplyEventsToChat(FChat);
      ApplyParamsToChat(FChat, FParams);
    End;

    // Assign the new chat
    FChat := Value;

    if Assigned(FChat) then
    begin
      // Apply events and parameters to the new chat
      ApplyEventsToChat(FChat);
      ApplyParamsToChat(FChat, FParams);

      // * CORRECTION: Point FMessages to the chat's messages
      // (We do NOT create or free anything, just change the reference)
      FMessages := FChat.Messages;
    end
    else
    begin
      // * CORRECTION: If there is no chat, revert to using our own instance
      // (We do NOT create a new one, we use FMessagesOwn which already exists)
      FMessages := FMessagesOwn;
    end;
  end;
end;

procedure TAiChatConnection.SetCompletion_tokens(const Value: integer);
begin
  FCompletion_tokens := Value;
end;

procedure TAiChatConnection.SetMemory(const Value: TStrings);
begin
  FMemory.Assign(Value);
  if Assigned(FChat) then
    FChat.Memory.Assign(Value);
end;

procedure TAiChatConnection.SetOnAddMessage(const Value: TAiChatOnDataEvent);
begin
  FOnAddMessage := Value;
  if Assigned(FChat) then
    FChat.OnAddMessage := Value;
end;

procedure TAiChatConnection.SetOnBeforeSendMessage(const Value: TAiChatOnBeforeSendEvent);
begin
  FOnBeforeSendMessage := Value;
  if Assigned(FChat) then
    FChat.OnBeforeSendMessage := Value;
end;

procedure TAiChatConnection.SetOnCallToolFunction(const Value: TOnCallToolFunction);
begin
  FOnCallToolFunction := Value;
  if Assigned(FChat) then
    FChat.OnCallToolFunction := Value;
end;

procedure TAiChatConnection.SetOnError(const Value: TAiErrorEvent);
begin
  FOnError := Value;
  if Assigned(FChat) then
    FChat.OnError := Value;
end;

procedure TAiChatConnection.SetOnInitChat(const Value: TAiChatOnInitChatEvent);
begin
  FOnInitChat := Value;
  if Assigned(FChat) then
    FChat.OnInitChat := Value;
end;

procedure TAiChatConnection.SetOnProcessMediaFile(const Value: TAiChatOnMediaFileEvent);
begin
  FOnProcessMediaFile := Value;
  if Assigned(FChat) then
    FChat.OnProcessMediaFile := Value;
end;

procedure TAiChatConnection.SetOnProcessResponse(const Value: TAiChatOnProcessResponseEvent);
begin
  FOnProcessResponse := Value;
  if Assigned(FChat) then
    FChat.OnProcessResponse := Value;
end;

procedure TAiChatConnection.SetOnReceiveData(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveData := Value;
  if Assigned(FChat) then
    FChat.OnReceiveData := Value;
end;

procedure TAiChatConnection.SetOnReceiveDataEnd(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveDataEnd := Value;
  // if Assigned(FChat) then
  // FChat.OnReceiveDataEnd := Value;
end;

procedure TAiChatConnection.SetOnReceiveThinking(const Value: TAiChatOnDataEvent);
begin
  FOnReceiveThinking := Value;
  if Assigned(FChat) then
    FChat.OnReceiveThinking := Value;
end;

procedure TAiChatConnection.SetPrompt_tokens(const Value: integer);
begin
  FPrompt_tokens := Value;
end;

procedure TAiChatConnection.SetSystemPrompt(const Value: TStrings);
begin
  FSystemPrompt.Assign(Value);
  if Assigned(FChat) then
    FChat.SystemPrompt.Assign(Value);
end;

procedure TAiChatConnection.SetTotal_tokens(const Value: integer);
begin
  FTotal_tokens := Value;
end;

// -------------------------

procedure TAiChatConnection.SetChatMode(const Value: TAiChatMode);
begin
  if FChatMode <> Value then
  begin
    FChatMode := Value;
    if Assigned(FChat) then
      FChat.ChatMode := Value;
  end;
end;

procedure TAiChatConnection.SetAiFunctions(const Value: TAiFunctions);
begin
  if FAiFunctions <> Value then
  begin
    FAiFunctions := Value;
    if FAiFunctions <> nil then
      FAiFunctions.FreeNotification(Self);
    if Assigned(FChat) then
      FChat.AiFunctions := Value;
  end;
end;

procedure TAiChatConnection.SetSanitizerActive(const Value: Boolean);
begin
  FSanitizerActive := Value;
  if Assigned(FChat) then
    FChat.SanitizerActive := Value;
end;

procedure TAiChatConnection.SetOnSanitize(const Value: TAiSanitizeEvent);
begin
  FOnSanitize := Value;
  if Assigned(FChat) then
    FChat.OnSanitize := Value;
end;

procedure TAiChatConnection.SetOnPromptGuard(const Value: TAiPromptGuardEvent);
begin
  FOnPromptGuard := Value;
  if Assigned(FChat) then
    FChat.OnPromptGuard := Value;
end;

procedure TAiChatConnection.SetPersistentMemory(const Value: TAiPersistentMemoryBase);
begin
  if FPersistentMemory = Value then Exit;
  if Assigned(FPersistentMemory) then
    FPersistentMemory.RemoveFreeNotification(Self);
  FPersistentMemory := Value;
  if Assigned(FPersistentMemory) then
    FPersistentMemory.FreeNotification(Self);
  if Assigned(FChat) then
    FChat.PersistentMemory := Value;
end;

procedure TAiChatConnection.SetMemoryTokenBudget(const Value: Integer);
begin
  FMemoryTokenBudget := Value;
  if Assigned(FChat) then
    FChat.MemoryTokenBudget := Value;
end;

procedure TAiChatConnection.SetAutoStoreMemories(const Value: Boolean);
begin
  FAutoStoreMemories := Value;
  if Assigned(FChat) then
    FChat.AutoStoreMemories := Value;
end;

procedure TAiChatConnection.SetTtsParams(const Value: TAiTtsParams);
begin
  FTtsParams.Assign(Value);
  if Assigned(FChat) then
    FChat.TtsParams.Assign(Value);
end;

procedure TAiChatConnection.SetTranscriptionParams(const Value: TAiTranscriptionParams);
begin
  FTranscriptionParams.Assign(Value);
  if Assigned(FChat) then
    FChat.TranscriptionParams.Assign(Value);
end;

procedure TAiChatConnection.SetImageGenParams(const Value: TAiImageGenParams);
begin
  FImageGenParams.Assign(Value);
  if Assigned(FChat) then
    FChat.ImageParams.Assign(Value);
end;

procedure TAiChatConnection.SetVideoGenParams(const Value: TAiVideoGenParams);
begin
  FVideoGenParams.Assign(Value);
  if Assigned(FChat) then
    FChat.VideoParams.Assign(Value);
end;

procedure TAiChatConnection.SetWebSearchParams(const Value: TAiWebSearchParams);
begin
  FWebSearchParams.Assign(Value);
  if Assigned(FChat) then
    FChat.WebSearchParams.Assign(Value);
end;

procedure TAiChatConnection.SetModelConfig(const Value: TAiModelConfig);
begin
  FModelConfig.Assign(Value);
  if Assigned(FChat) then
    FChat.ModelConfig.Assign(Value);
end;

procedure TAiChatConnection.SetResponse_format(const Value: TAiChatResponseFormat);
begin
  FResponse_format := Value;
  if Assigned(FChat) then
    FChat.Response_format := Value;
end;

procedure TAiChatConnection.SetJsonSchema(const Value: TStrings);
begin
  FJsonSchema.Assign(Value);
  if Assigned(FChat) then
    FChat.JsonSchema.Assign(Value);
end;

// Propagates mutations of Connection.ChatTools.XxxTool to the live TAiChat
// (same pattern as ModelConfigChanged). FChatTools.SetXxxTool already calls
// Value.FreeNotification(FOwner) and Notification handles opRemove.
procedure TAiChatConnection.ChatToolsChanged(Sender: TObject);
begin
  if Assigned(FChat) then
    FChat.ChatTools.Assign(FChatTools);
end;

// ── Code shortcuts ModelCaps/SessionCaps/Tool_Active ──────────────────────
// Pure delegation to FModelConfig: the sub-object setter marks the pin
// (UserFields) and triggers OnChange -> ModelConfigChanged -> live chat.

function TAiChatConnection.GetModelCaps: TAiCapabilities;
begin
  Result := FModelConfig.ModelCaps;
end;

procedure TAiChatConnection.SetModelCaps(const Value: TAiCapabilities);
begin
  FModelConfig.ModelCaps := Value;
end;

function TAiChatConnection.GetSessionCaps: TAiCapabilities;
begin
  Result := FModelConfig.SessionCaps;
end;

procedure TAiChatConnection.SetSessionCaps(const Value: TAiCapabilities);
begin
  FModelConfig.SessionCaps := Value;
end;

function TAiChatConnection.GetTool_Active: Boolean;
begin
  Result := FModelConfig.Tool_Active;
end;

procedure TAiChatConnection.SetTool_Active(const Value: Boolean);
begin
  FModelConfig.Tool_Active := Value;
end;

// ISSUE #115: Convenient API for debug log (opt-in).
procedure TAiChatConnection.EnableDebugLog(const APath: string = '');
begin
  MakerAiDebugLogPath := APath;   // empty = <TEMP>\makerai_debug.log
  MakerAiDebugLogEnabled := True;
end;

procedure TAiChatConnection.DisableDebugLog;
begin
  MakerAiDebugLogEnabled := False;
end;

function TAiChatConnection.IsDebugLogEnabled: Boolean;
begin
  Result := MakerAiDebugLogEnabled;
end;

end.
