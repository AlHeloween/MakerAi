unit uMakerAi.Gemini.Video;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient,
  System.Net.HttpClientComponent, System.Net.URLClient, System.Threading,
  System.IOUtils, uMakerAi.Core, uMakerAi.Chat.Tools, uMakerAi.Chat, uMakerAi.Chat.Messages;

type
  { Enums for better experience in the Object Inspector }
  TVeoAspectRatio = (arDefault, ar16_9, ar9_16);
  TVeoResolution = (vrDefault, vr720p, vr1080p);
  TVeoPersonGeneration = (pgDefault, pgAllowAll, pgAllowAdult, pgDontAllow);

  //[ComponentPlatformsAttribute(pidWin32 or pidWin64 or pidOSX32 or pidOSX64 or pidiOSArm64 or pidAndroidArm64)]
  TAiGeminiVideoTool = class(TAiVideoToolBase)
  private
    FApiKey: string;
    FModel: string;
    FUrl: string;
    FAspectRatio: TVeoAspectRatio;
    FResolution: TVeoResolution;
    FDurationSeconds: Integer;
    FPersonGeneration: TVeoPersonGeneration;
    FNegativePrompt: string;
    FSeed: Int64;

    function GetApiKey: string;
    function BuildParametersJson: TJSONObject;
    function DownloadVideo(const AVideoUri: string): TAiMediaFile;
  protected
    { implementation of IAiVideoTool }
    procedure ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage); override;

    { internal execution and polling logic }
    procedure InternalRunVeo(AResMsg, AAskMsg: TAiChatMessage);
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ApiKey: string read GetApiKey write FApiKey;
    property Model: string read FModel write FModel;
    property Url: string read FUrl write FUrl;

    { Veo configuration properties }
    property AspectRatio: TVeoAspectRatio read FAspectRatio write FAspectRatio default ar16_9;
    property Resolution: TVeoResolution read FResolution write FResolution default vr720p;
    property DurationSeconds: Integer read FDurationSeconds write FDurationSeconds default 8;
    property PersonGeneration: TVeoPersonGeneration read FPersonGeneration write FPersonGeneration default pgAllowAll;
    property NegativePrompt: string read FNegativePrompt write FNegativePrompt;
    property Seed: Int64 read FSeed write FSeed default 0;
  end;


procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGeminiVideoTool]);
end;


{ TAiGeminiVideoTool }

constructor TAiGeminiVideoTool.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FApiKey := '@GEMINI_API_KEY';
  FModel := 'veo-3.1-generate-preview';
  FUrl := 'https://generativelanguage.googleapis.com/v1beta/';
  FAspectRatio := ar16_9;
  FResolution := vr720p;
  FDurationSeconds := 8;
  FPersonGeneration := pgAllowAll;
end;

function TAiGeminiVideoTool.GetApiKey: string;
begin
  if (csDesigning in ComponentState) or (csDestroying in ComponentState) then
    Exit(FApiKey);

  if (FApiKey <> '') and (FApiKey.StartsWith('@')) then
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, MaxInt))
  else
    Result := FApiKey;
end;

function TAiGeminiVideoTool.BuildParametersJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  case FAspectRatio of
    ar16_9: Result.AddPair('aspectRatio', '16:9');
    ar9_16: Result.AddPair('aspectRatio', '9:16');
  end;

  case FResolution of
    vr720p: Result.AddPair('resolution', '720p');
    vr1080p: Result.AddPair('resolution', '1080p');
  end;

  if FDurationSeconds > 0 then
    Result.AddPair('durationSeconds', TJSONNumber.Create(FDurationSeconds));

  case FPersonGeneration of
    pgAllowAll: Result.AddPair('personGeneration', 'allow_all');
    pgAllowAdult: Result.AddPair('personGeneration', 'allow_adult');
    pgDontAllow: Result.AddPair('personGeneration', 'dont_allow');
  end;

  if not FNegativePrompt.IsEmpty then
    Result.AddPair('negativePrompt', FNegativePrompt);

  if FSeed > 0 then
    Result.AddPair('seed', TJSONNumber.Create(FSeed));
end;

procedure TAiGeminiVideoTool.ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage);
var
  LTaskMsg: TAiChatMessage;
begin
  // Veo is always asynchronous (takes minutes). We do NOT use ResMsg directly
  // because TAiChat.Run can free it before the polling ends.
  // We create our own message and queue its release after ReportDataEnd
  // to respect the FIFO order of TThread.Queue.
  LTaskMsg := TAiChatMessage.Create('', 'assistant');
  TTask.Run(procedure
  begin
    try
      InternalRunVeo(LTaskMsg, TAiChatMessage(AskMsg));
    except
      on E: Exception do ReportError('Error in Veo Tool: ' + E.Message, E);
    end;
    // ReportDataEnd already queues DoDataEnd(LTaskMsg,...) to the main thread.
    // Queue the Free after to execute in FIFO order.
    TThread.Queue(nil, procedure begin LTaskMsg.Free; end);
  end);
end;

procedure TAiGeminiVideoTool.InternalRunVeo(AResMsg, AAskMsg: TAiChatMessage);
var
  HTTP: TNetHTTPClient;
  LUrl, LOpName, LPollingUrl, LVideoUri: string;
  LRequest, LInstance, LImagePart: TJSONObject;
  LInstances: TJSONArray;
  LResponse: IHTTPResponse;
  LBody: TStringStream;
  LJSON, LErrorObj: TJSONObject;
  LIsDone: Boolean;
  LMediaArr: TAiMediaFilesArray;
  LVideoFile: TAiMediaFile;
begin
  HTTP := TNetHTTPClient.Create(nil);
  LRequest := TJSONObject.Create;
  LBody := nil;
  try
    // 1. Build initial request
    LInstances := TJSONArray.Create;
    LInstance := TJSONObject.Create;
    LInstance.AddPair('prompt', AAskMsg.Prompt);

    // Support for Image-to-Video (if there is an image in the message)
    LMediaArr := AAskMsg.MediaFiles.GetMediaList([Tfc_Image], False);
    if Length(LMediaArr) > 0 then
    begin
      LImagePart := TJSONObject.Create;
      if not LMediaArr[0].UrlMedia.IsEmpty then
        LImagePart.AddPair('uri', LMediaArr[0].UrlMedia)
      else
        LImagePart.AddPair('bytesBase64Encoded', LMediaArr[0].Base64);

      LImagePart.AddPair('mimeType', LMediaArr[0].MimeType);
      LInstance.AddPair('image', LImagePart);
    end;

    LInstances.Add(LInstance);
    LRequest.AddPair('instances', LInstances);
    LRequest.AddPair('parameters', BuildParametersJson);

    // 2. Start operation (predictLongRunning)
    LUrl := Format('%smodels/%s:predictLongRunning?key=%s', [FUrl, FModel, GetApiKey]);
    LBody := TStringStream.Create(LRequest.ToJSON, TEncoding.UTF8);
    HTTP.ContentType := 'application/json';

    ReportState(acsReasoning, 'Starting Veo video generation...');
    LResponse := HTTP.Post(LUrl, LBody);

    if LResponse.StatusCode <> 200 then
      raise Exception.Create('Error starting Veo: ' + LResponse.ContentAsString);

    LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    LOpName := LJSON.GetValue<string>('name', '');
    LJSON.Free;

    if LOpName.IsEmpty then
      raise Exception.Create('Operation name not received.');

    // 3. Polling loop
    LPollingUrl := FUrl + LOpName + '?key=' + GetApiKey;
    LIsDone := False;

    while not LIsDone do
    begin
      Sleep(10000); // Wait 10 seconds
      ReportState(acsReasoning, 'Processing video on Google servers...');

      LResponse := HTTP.Get(LPollingUrl);
      if LResponse.StatusCode = 200 then
      begin
        LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
        try
          LJSON.TryGetValue<Boolean>('done', LIsDone);
          if LIsDone then
          begin
            if LJSON.TryGetValue<TJSONObject>('error', LErrorObj) then
              raise Exception.Create('Error in operation: ' + LErrorObj.ToJSON);

            LVideoUri := LJSON.GetValue<string>('response.generateVideoResponse.generatedSamples[0].video.uri', '');
          end;
        finally
          LJSON.Free;
        end;
      end;
    end;

    // 4. Download Final Video
    if not LVideoUri.IsEmpty then
    begin
      ReportState(acsWriting, 'Downloading generated video...');
      LVideoFile := DownloadVideo(LVideoUri);
      if Assigned(LVideoFile) then
      begin
        AResMsg.MediaFiles.Add(LVideoFile);
        ReportDataEnd(AResMsg, 'assistant', '[Video generated successfully]');
      end;
    end;

  finally
    LRequest.Free;
    HTTP.Free;
    LBody.Free;
  end;
end;

function TAiGeminiVideoTool.DownloadVideo(const AVideoUri: string): TAiMediaFile;
var
  HTTP: TNetHTTPClient;
  Resp: IHTTPResponse;
  Stream: TMemoryStream;
  Headers: TNetHeaders;
begin
  Result := nil;
  HTTP := TNetHTTPClient.Create(nil);
  Stream := TMemoryStream.Create;
  try
    Headers := [TNetHeader.Create('x-goog-api-key', GetApiKey)];
    Resp := HTTP.Get(AVideoUri, Stream, Headers);
    if Resp.StatusCode = 200 then
    begin
      Stream.Position := 0;
      Result := TAiMediaFile.Create;
      Result.UrlMedia := AVideoUri;
      Result.LoadFromStream('veo_video.mp4', Stream);
    end;
  finally
    HTTP.Free;
    if not Assigned(Result) then Stream.Free;
  end;
end;

end.
