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
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uMakerAi.Gemini.Veo;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Threading,
  System.JSON, System.Net.HttpClient, System.Net.URLClient,
{$IF CompilerVersion < 35}
  uJSONHelper, // Delphi 10.4: generic helpers GetValue<T>/TryGetValue<T> for TJSONObject
{$ENDIF}
  uMakerAi.chat.Gemini,
  uMakerAi.Core, System.Net.HttpClientComponent;

type
  // Enums for typed properties, improving Developer Experience (DX)
  TVeoModel = (vmCustom, vmVeo3_1, vmVeo3_1_Fast, vmVeo3_0, vmVeo3_0_Fast, vmVeo2_0);
  TVeoAspectRatio = (arDefault, ar16x9, ar9x16);
  TVeoResolution = (vrDefault, vr720p, vr1080p);
  TVeoPersonGeneration = (pgDefault, pgAllowAll, pgAllowAdult, pgDontAllow);

  // Events for asynchronous and UI-safe feedback
  TProgressEvent = procedure(Sender: TObject; const StatusMessage: string) of object;
  TGenerationSuccessEvent = procedure(Sender: TObject; ResultVideo: TAiMediaFile) of object;
  TGenerationErrorEvent = procedure(Sender: TObject; const ErrorMessage: string) of object;

  // --- The Specialized Component for VEO ---
  TAiVeoGenerator = class(TComponent)
  private
    // Properties
    FApiKey: string;
    FModel: TVeoModel;
    FCustomModelName: string;
    FAspectRatio: TVeoAspectRatio;
    FResolution: TVeoResolution;
    FDurationSeconds: Integer;
    FPersonGeneration: TVeoPersonGeneration;
    FSeed: Int64;
    FNegativePrompt: string;

    // Events
    FOnProgress: TProgressEvent;
    FOnSuccess: TGenerationSuccessEvent;
    FOnError: TGenerationErrorEvent;

    // Internal helper methods
    function GetEffectiveModelName: string;
    function BuildParametersJson: TJSONObject;
    procedure DoError(const AMessage: string);
    procedure DoProgress(const AMessage: string);
    procedure DoSuccess(AVideoFile: TAiMediaFile);

    // The synchronous execution engine that runs within a TTask
    procedure InternalExecuteGeneration(ARequestBody: TJSONObject);
    function DownloadVideoFile(const AVideoUri: string): TAiMediaFile;
    function GetApiKey: string;
    //function WaitForFileToBeActive(const ACloudName: string): Boolean;

  public
    constructor Create(AOwner: TComponent); override;

    // --- Public Asynchronous Methods (returning ITask) ---
    function GenerateFromText(const APrompt: string): ITask;
    function GenerateFromImage(const APrompt: string; AImage: TAiMediaFile): ITask;
    function GenerateFromFrames(const APrompt: string; AFirstFrame, ALastFrame: TAiMediaFile): ITask;
    function GenerateWithReferences(const APrompt: string; AReferenceImages: TAiMediaFilesArray): ITask;
    function ExtendVideo(const APrompt: string; AVideoToExtend: TAiMediaFile): ITask;

    function UploadFile(aMediaFile: TAiMediaFile): String;
    //function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer): String;
    procedure UploadFileSync(aMediaFile: TAiMediaFile);

  published
    property ApiKey: string read GetApiKey write FApiKey;

    property Model: TVeoModel read FModel write FModel default TVeoModel.vmVeo3_1;
    property CustomModelName: string read FCustomModelName write FCustomModelName;

    property AspectRatio: TVeoAspectRatio read FAspectRatio write FAspectRatio default TVeoAspectRatio.ar16x9;
    property Resolution: TVeoResolution read FResolution write FResolution default TVeoResolution.vr720p;
    property DurationSeconds: Integer read FDurationSeconds write FDurationSeconds default 8;
    property PersonGeneration: TVeoPersonGeneration read FPersonGeneration write FPersonGeneration default TVeoPersonGeneration.pgAllowAll;
    property NegativePrompt: string read FNegativePrompt write FNegativePrompt;
    property Seed: Int64 read FSeed write FSeed default 0;

    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnSuccess: TGenerationSuccessEvent read FOnSuccess write FOnSuccess;
    property OnError: TGenerationErrorEvent read FOnError write FOnError;
  end;

procedure Register;

implementation

uses
  System.IOUtils, System.NetConsts, System.NetEncoding, REST.JSON;

const
  GEMINI_API_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/';
  GEMINI_API_UPLOAD_URL = 'https://generativelanguage.googleapis.com/upload/v1beta/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiVeoGenerator]);
end;

{ TAiVeoGenerator }

constructor TAiVeoGenerator.Create(AOwner: TComponent);
begin
  inherited;
  FApiKey := '@GEMINI_API_KEY';

  FModel := TVeoModel.vmVeo3_1;
  FAspectRatio := TVeoAspectRatio.ar16x9;
  FResolution := TVeoResolution.vr720p;
  FDurationSeconds := 8;
  FPersonGeneration := TVeoPersonGeneration.pgAllowAll;
  FSeed := 0;
end;

function TAiVeoGenerator.BuildParametersJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  if FAspectRatio <> TVeoAspectRatio.arDefault then
    case FAspectRatio of
      ar16x9:
        Result.AddPair('aspectRatio', '16:9');
      ar9x16:
        Result.AddPair('aspectRatio', '9:16');
    end;
  if FResolution <> TVeoResolution.vrDefault then
    case FResolution of
      vr720p:
        Result.AddPair('resolution', '720p');
      vr1080p:
        Result.AddPair('resolution', '1080p');
    end;
  if FDurationSeconds > 0 then
    Result.AddPair('durationSeconds', FDurationSeconds);
  if FPersonGeneration <> TVeoPersonGeneration.pgDefault then
    case FPersonGeneration of
      pgAllowAll:
        Result.AddPair('personGeneration', 'allow_all');
      pgAllowAdult:
        Result.AddPair('personGeneration', 'allow_adult');
      pgDontAllow:
        Result.AddPair('personGeneration', 'dont_allow');
    end;
  if not FNegativePrompt.IsEmpty then
    Result.AddPair('negativePrompt', FNegativePrompt);
  if FSeed > 0 then
    Result.AddPair('seed', FSeed);
end;

procedure TAiVeoGenerator.DoError(const AMessage: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(Self, AMessage);
    end);
end;

procedure TAiVeoGenerator.DoProgress(const AMessage: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnProgress) then
        FOnProgress(Self, AMessage);
    end);
end;

procedure TAiVeoGenerator.DoSuccess(AVideoFile: TAiMediaFile);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnSuccess) then
        FOnSuccess(Self, AVideoFile);
    end);
end;

function TAiVeoGenerator.DownloadVideoFile(const AVideoUri: string): TAiMediaFile;
var
  LHttpClient: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LVideoStream: TMemoryStream;
  LHeaders: TNetHeaders;
begin
  Result := nil;
  LHttpClient := TNetHTTPClient.Create(nil);
  LVideoStream := TMemoryStream.Create;
  try
    LHeaders := [TNetHeader.Create('x-goog-api-key', Self.ApiKey)];
    LResponse := LHttpClient.Get(AVideoUri, LVideoStream, LHeaders);

    if LResponse.StatusCode = 200 then
    begin
      LVideoStream.Position := 0;
      Result := TAiMediaFile.Create;
      Result.UrlMedia := AVideoUri;
      Result.LoadFromStream(TPath.GetFileName(TURI.Create(AVideoUri).Path) + '.mp4', LVideoStream);
    end
    else
    begin
      raise Exception.CreateFmt('Error downloading video file: %d %s', [LResponse.StatusCode, LResponse.ContentAsString(TEncoding.UTF8)]);
    end;
  finally
    LHttpClient.Free;
    if Result = nil then
      LVideoStream.Free;
  end;
end;

function TAiVeoGenerator.ExtendVideo(const APrompt: string; AVideoToExtend: TAiMediaFile): ITask;
Var
  VideoUrlMedia: String;
begin
  // --- validation ---
  // Validate that the TAiMediaFile object has the URI of the VEO asset.
  if (not Assigned(AVideoToExtend)) or (AVideoToExtend.UrlMedia.IsEmpty) then
    raise Exception.Create('To extend a video, you must provide a TAiMediaFile object with its original UrlMedia property set from a previous VEO generation.');

  // simple verification that it looks like a valid URL
  if not AVideoToExtend.UrlMedia.StartsWith('https') then
    raise Exception.Create('The UrlMedia property does not appear to be a valid VEO asset URI. It should start with "https".');

  VideoUrlMedia := AVideoToExtend.UrlMedia;

  Result := TTask.Run(
    procedure
    var
      LRequest, LInstance, LVideoPart, LParams: TJSONObject;
      LInstances: TJSONArray;
    begin
      DoProgress('Starting extension for existing VEO video asset: ' + TPath.GetFileName(AVideoToExtend.UrlMedia));

      // --- Build the request body directly ---
      LRequest := TJSONObject.Create;
      try
        LInstances := TJSONArray.Create;
        LRequest.AddPair('instances', LInstances);

        LInstance := TJSONObject.Create;
        LInstances.AddElement(LInstance);
        LInstance.AddPair('prompt', TJSONString.Create(APrompt));

        LVideoPart := TJSONObject.Create;
        // The key is 'uri' and the value is the full identifier returned by the API the first time.
        LVideoPart.AddPair('uri', TJSONString.Create(VideoUrlMedia));
        LInstance.AddPair('video', LVideoPart);

        LParams := BuildParametersJson;
        LRequest.AddPair('parameters', LParams);

        // --- Execute generation ---
        InternalExecuteGeneration(LRequest);
      except
        LRequest.Free;
        raise;
      end;
    end);
end;


function TAiVeoGenerator.GenerateFromFrames(const APrompt: string; AFirstFrame, ALastFrame: TAiMediaFile): ITask;
var
  LFirstFrameClone, LLastFrameClone: TAiMediaFile;
begin
  if not Assigned(AFirstFrame) or AFirstFrame.Base64.IsEmpty or not Assigned(ALastFrame) or ALastFrame.Base64.IsEmpty then
    raise Exception.Create('Both a first and a last frame are required for interpolation.');

  // Clone for the asynchronous task
  LFirstFrameClone := TAiMediaFile.Create;
  LFirstFrameClone.Assign(AFirstFrame);
  LLastFrameClone := TAiMediaFile.Create;
  LLastFrameClone.Assign(ALastFrame);

  Result := TTask.Run(
    procedure
    var
      LRequest, LInstance, LImagePart, LLastFramePart, LParams: TJSONObject;
      LInstances: TJSONArray;
    begin
      try
        LRequest := TJSONObject.Create;
        try
          LInstances := TJSONArray.Create;
          LRequest.AddPair('instances', LInstances);

          LInstance := TJSONObject.Create;
          LInstances.AddElement(LInstance);
          LInstance.AddPair('prompt', TJSONString.Create(APrompt));

          // --- START OF CORRECTION ---
          // 1. Create and add the first image to the INSTANCE
          LImagePart := TJSONObject.Create;
          LImagePart.AddPair('mimeType', LFirstFrameClone.MimeType);
          LImagePart.AddPair('bytesBase64Encoded', LFirstFrameClone.Base64);
          LInstance.AddPair('image', LImagePart);

          // 2. Create and add the second image (lastFrame) also to the INSTANCE
          LLastFramePart := TJSONObject.Create;
          LLastFramePart.AddPair('mimeType', LLastFrameClone.MimeType);
          LLastFramePart.AddPair('bytesBase64Encoded', LLastFrameClone.Base64);
          LInstance.AddPair('lastFrame', LLastFramePart);

          // 3. The parameters object now only contains the general configuration
          LParams := BuildParametersJson;
          LRequest.AddPair('parameters', LParams);
          // --- END OF CORRECTION ---

          InternalExecuteGeneration(LRequest);
        except
          LRequest.Free;
          raise;
        end;
      finally
        // Free the clones
        LFirstFrameClone.Free;
        LLastFrameClone.Free;
      end;
    end);
end;



function TAiVeoGenerator.GenerateFromImage(const APrompt: string; AImage: TAiMediaFile): ITask;
var
  LImageClone: TAiMediaFile;
begin
  // Basic validation before creating the thread
  if not Assigned(AImage) then
    raise Exception.Create('An image object is required.');

  if AImage.UrlMedia.IsEmpty and AImage.Base64.IsEmpty then
    raise Exception.Create('The image must have either a Cloud URI (UrlMedia) or Base64 content.');

  // Clone the image object to ensure thread safety,
  // since the TTask will run in parallel.
  LImageClone := TAiMediaFile.Create;
  LImageClone.Assign(AImage);

  Result := TTask.Run(
    procedure
    var
      LRequest, LInstance, LImagePart: TJSONObject;
      LInstances: TJSONArray;
    begin
      try
        LRequest := TJSONObject.Create;
        try
          // JSON structure: { "instances": [ { ... } ], "parameters": { ... } }
          LInstances := TJSONArray.Create;
          LRequest.AddPair('instances', LInstances);

          LInstance := TJSONObject.Create;
          LInstances.AddElement(LInstance);

          // 1. Add the Prompt
          LInstance.AddPair('prompt', TJSONString.Create(APrompt));

          // 2. Add the Image
          LImagePart := TJSONObject.Create;

          // HYBRID STRATEGY:
          // Prefer using the File API URI if it exists (better performance for Veo).
          if not LImageClone.UrlMedia.IsEmpty then
          begin
            // For Veo/Vertex AI, when it is an uploaded file, we use 'uri' or 'gcsUri'
            // The Gemini Files API returns an internally accessible URI.
            LImagePart.AddPair('uri', LImageClone.UrlMedia);
            LImagePart.AddPair('mimeType', LImageClone.MimeType); // Helps the model
          end
          else
          begin
            // Fallback: If not uploaded, use Base64 (Inline)
            // Note: This only works for small images (<20MB total request)
            LImagePart.AddPair('bytesBase64Encoded', LImageClone.Base64);
            LImagePart.AddPair('mimeType', LImageClone.MimeType);
          end;

          LInstance.AddPair('image', LImagePart);

          // 3. Add the configuration parameters (Resolution, FPS, etc.)
          // Note: BuildParametersJson returns a new object; AddPair takes ownership.
          LRequest.AddPair('parameters', BuildParametersJson);

          // Execute the request (InternalExecuteGeneration handles freeing LRequest)
          InternalExecuteGeneration(LRequest);
        except
          // If an error occurs before entering InternalExecuteGeneration, free what we created.
          LRequest.Free;
          raise;
        end;
      finally
        // Free the clone created specifically for this task
        LImageClone.Free;
      end;
    end);
end;

function TAiVeoGenerator.GenerateFromText(const APrompt: string): ITask;
begin
  if APrompt.IsEmpty then
    raise Exception.Create('A non-empty prompt is required.');

  Result := TTask.Run(
    procedure
    var
      LRequest, LInstance: TJSONObject;
      LInstances: TJSONArray;
    begin
      LRequest := TJSONObject.Create;
      LInstances := TJSONArray.Create;
      LRequest.AddPair('instances', LInstances);
      LInstance := TJSONObject.Create;
      LInstances.AddElement(LInstance);
      LInstance.AddPair('prompt', TJSONString.Create(APrompt));

      InternalExecuteGeneration(LRequest);
    end);
end;

function TAiVeoGenerator.GenerateWithReferences(const APrompt: string; AReferenceImages: TAiMediaFilesArray): ITask;
var
  LClonedImages: TArray<TAiMediaFile>; // Array to store the clones
  i: Integer;
begin
  if Length(AReferenceImages) = 0 then
    raise Exception.Create('At least one reference image is required.');
  if Length(AReferenceImages) > 3 then
    raise Exception.Create('A maximum of 3 reference images are supported.');

  // Create an array of clones
  SetLength(LClonedImages, Length(AReferenceImages));
  for i := 0 to High(AReferenceImages) do
  begin
    LClonedImages[i] := TAiMediaFile.Create;
    LClonedImages[i].Assign(AReferenceImages[i]);
  end;

  Result := TTask.Run(
    procedure
    var
      LRequest, LInstance, LConfig, LRefImagePart, LParams: TJSONObject;
      LInstances, LRefImagesArray: TJSONArray;
      ClonedImg: TAiMediaFile;
    begin
      try
        LRequest := TJSONObject.Create;
        try
          LInstances := TJSONArray.Create;
          LRequest.AddPair('instances', LInstances);
          LInstance := TJSONObject.Create;
          LInstances.AddElement(LInstance);
          LInstance.AddPair('prompt', TJSONString.Create(APrompt));

          LConfig := TJSONObject.Create;
          LRefImagesArray := TJSONArray.Create;
          LConfig.AddPair('referenceImages', LRefImagesArray);

          // Iterate over the array of clones
          for ClonedImg in LClonedImages do
          begin
            LRefImagePart := TJSONObject.Create;
            LRefImagePart.AddPair('mimeType', ClonedImg.MimeType);
            LRefImagePart.AddPair('bytesBase64Encoded', ClonedImg.Base64);
            LRefImagesArray.AddElement(LRefImagePart);
          end;

          LParams := BuildParametersJson;
          LParams.AddPair('config', LConfig);
          LRequest.AddPair('parameters', LParams);

          InternalExecuteGeneration(LRequest);
        except
          LRequest.Free;
          raise;
        end;
      finally
        // Free all clones in the array
        for ClonedImg in LClonedImages do
          ClonedImg.Free;
      end;
    end);
end;

function TAiVeoGenerator.GetApiKey: string;
Begin
  // If in design mode, simply return the value as is
  if (csDesigning in ComponentState) or (csDestroying in ComponentState) then
  begin
    Result := FApiKey;
    Exit;
  end;

  // In execution mode
  if (FApiKey <> '') and (Copy(FApiKey, 1, 1) = '@') then
    // Return the value of the environment variable, removing the '@'
    Result := GetEnvironmentVariable(Copy(FApiKey, 2, Length(FApiKey)))
  else
    Result := FApiKey;
end;

function TAiVeoGenerator.GetEffectiveModelName: string;
begin
  if not FCustomModelName.IsEmpty then
  begin
    Result := FCustomModelName;
    Exit;
  end;

  case FModel of
    vmVeo3_1:
      Result := 'veo-3.1-generate-preview';
    vmVeo3_1_Fast:
      Result := 'veo-3.1-fast-generate-preview';
    // RETIRED by Google on June 30, 2026: veo-2.0 and veo-3.0 return an error
    // from the API. They are kept in the enum for DFM compatibility; migrate to
    // vmVeo3_1 / vmVeo3_1_Fast.
    vmVeo3_0:
      Result := 'veo-3.0-generate-001';
    vmVeo3_0_Fast:
      Result := 'veo-3.0-fast-generate-001';
    vmVeo2_0:
      Result := 'veo-2.0-generate-001';
  else
    raise Exception.Create('Model must be specified. Set the Model property or provide a CustomModelName.');
  end;
end;

procedure TAiVeoGenerator.InternalExecuteGeneration(ARequestBody: TJSONObject);
var
  LHttpClient: TNetHTTPClient;
  LUrl, LModelName, LOpName, PollingUrl: string;
  LResponse: IHTTPResponse;
  LBodyStream: TStringStream;
  LInitialResponse, LPollingResponse, LErrorObj, LFinalResponse: TJSONObject;
  LHeaders: TNetHeaders;
  LIsDone: Boolean;
  LPollCount: Integer;
  LResultVideo: TAiMediaFile;
begin
  LFinalResponse := nil;
  LHttpClient := TNetHTTPClient.Create(nil);
  try
    try
      // --- STEP 1: Start the long-running operation ---
      LModelName := GetEffectiveModelName;
      LUrl := TPath.Combine(GEMINI_API_BASE_URL, 'models/' + LModelName + ':predictLongRunning');

      // --- CORRECTED LINE ---
      // If parameters were not added by a specific method, add them now.
      if ARequestBody.FindValue('parameters') = nil then
        ARequestBody.AddPair('parameters', BuildParametersJson);

      LBodyStream := TStringStream.Create(ARequestBody.ToJSON, TEncoding.UTF8);
      try
        LHttpClient.ContentType := 'application/json';
        LHeaders := [TNetHeader.Create('x-goog-api-key', Self.ApiKey)];
        LResponse := LHttpClient.Post(LUrl, LBodyStream, nil, LHeaders);
      finally
        LBodyStream.Free;
      end;

      if (LResponse.StatusCode <> 200) then
        raise Exception.CreateFmt('Error starting video generation: %d, %s', [LResponse.StatusCode, LResponse.ContentAsString]);

      LInitialResponse := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      try
        if not LInitialResponse.TryGetValue<string>('name', LOpName) then
          raise Exception.Create('Operation name not found in API response.');
      finally
        LInitialResponse.Free;
      end;

      PollingUrl := TPath.Combine(GEMINI_API_BASE_URL, LOpName);

      // --- STEP 2: Polling loop ---
      LIsDone := False;
      LPollCount := 0;
      while not LIsDone do
      begin
        Inc(LPollCount);
        DoProgress('Processing video... Status check #' + LPollCount.ToString);
        Sleep(10000); // 10-second polling interval

        LResponse := LHttpClient.Get(PollingUrl, nil, LHeaders);
        if LResponse.StatusCode <> 200 then
          raise Exception.CreateFmt('Error during polling: %d, %s', [LResponse.StatusCode, LResponse.ContentAsString]);

        LPollingResponse := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
        try
          LPollingResponse.TryGetValue<Boolean>('done', LIsDone);
          if LIsDone then
            LFinalResponse := LPollingResponse.Clone as TJSONObject
          else
            LPollingResponse.Free;
        except
          LPollingResponse.Free;
          raise;
        end;
      end;

      // --- STEP 3: Process the final response ---
      if not Assigned(LFinalResponse) then
        raise Exception.Create('Operation finished but no final response was captured.');

      if LFinalResponse.TryGetValue<TJSONObject>('error', LErrorObj) then
        raise Exception.Create('Video generation failed: ' + LErrorObj.ToJSON);

      var
      LVideoUri := LFinalResponse.GetValue<string>('response.generateVideoResponse.generatedSamples[0].video.uri', '');
      if LVideoUri.IsEmpty then
        raise Exception.Create('Final response did not contain a video URI.');

      // --- STEP 4: Download the video and notify success ---
      DoProgress('Video generated. Downloading...');
      LResultVideo := DownloadVideoFile(LVideoUri);
      DoSuccess(LResultVideo);

    except
      on E: Exception do
      begin
        DoError(E.Message);
      end;
    end;
  finally
    ARequestBody.Free;
    LHttpClient.Free;
    if Assigned(LFinalResponse) then
      LFinalResponse.Free;
  end;
end;

function TAiVeoGenerator.UploadFile(aMediaFile: TAiMediaFile): String;
var
  LHttpClient: TNetHTTPClient;
  LStartUrl, LUploadUrl, LFileUri, CloudName, CloudState: string;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
  LJsonBody, LUploadResponseObj, LFileObj: TJSONObject;
  LFileStream: TStream;
  LNumBytes: Int64;
begin
  Result := '';
  LHttpClient := TNetHTTPClient.Create(Nil);

{$IF CompilerVersion >= 34}
  LHttpClient.SynchronizeEvents := False;
{$ENDIF}
  try
    LStartUrl := GEMINI_API_UPLOAD_URL + 'files?key=' + Self.ApiKey;

    LFileStream := aMediaFile.Content;
    LFileStream.Position := 0;
    LNumBytes := LFileStream.Size;

    if LNumBytes = 0 then
      raise Exception.Create('Could not obtain the file content for upload.');

    try
      LHeaders := [TNetHeader.Create('X-Goog-Upload-Protocol', 'resumable'), TNetHeader.Create('X-Goog-Upload-Command', 'start'), TNetHeader.Create('X-Goog-Upload-Header-Content-Length', LNumBytes.ToString),
        TNetHeader.Create('X-Goog-Upload-Header-Content-Type', aMediaFile.MimeType)];

      LJsonBody := TJSONObject.Create;
      try
        LFileObj := TJSONObject.Create;
        LFileObj.AddPair('display_name', TJSONString.Create(aMediaFile.filename));
        LJsonBody.AddPair('file', LFileObj);
        LHttpClient.ContentType := 'application/json';
        LResponse := LHttpClient.Post(LStartUrl, TStringStream.Create(LJsonBody.ToJSON, TEncoding.UTF8), nil, LHeaders);
      finally
        FreeAndNil(LJsonBody);
      end;

      if LResponse.StatusCode <> 200 then
        raise Exception.CreateFmt('Error starting file upload: %d %s', [LResponse.StatusCode, LResponse.StatusText]);


      LUploadUrl := LResponse.HeaderValue['X-Goog-Upload-Url'];
      if LUploadUrl = '' then
        raise Exception.Create('The upload URL was not received from the Google API.');

      LFileStream.Position := 0;
      LHeaders := [TNetHeader.Create('Content-Length', LNumBytes.ToString), TNetHeader.Create('X-Goog-Upload-Offset', '0'), TNetHeader.Create('X-Goog-Upload-Command', 'upload, finalize')];

      LHttpClient.ContentType := 'application/octet-stream';
      LResponse := LHttpClient.Post(LUploadUrl, LFileStream, nil, LHeaders);

      if LResponse.StatusCode <> 200 then
        raise Exception.CreateFmt('Error uploading file bytes: %d %s'#13#10'%s', [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);

      LUploadResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      if Assigned(LUploadResponseObj) then
        try
          if LUploadResponseObj.TryGetValue<TJSONObject>('file', LFileObj) then
          begin
            if LFileObj.TryGetValue<string>('uri', LFileUri) then
              Result := LFileUri;
            LFileObj.TryGetValue<string>('name', CloudName);
            LFileObj.TryGetValue<string>('state', CloudState);
            aMediaFile.UrlMedia := LFileUri;
            aMediaFile.CloudName := CloudName;
            aMediaFile.CloudState := CloudState;
          end;
        finally
          LUploadResponseObj.Free;
        end;
      if Result = '' then
        raise Exception.Create('The API uploaded the file but did not return a URI.');
    finally
      // The stream is not freed here because it is owned by TAiMediaFile
    end;
  finally
    LHttpClient.Free;
  end;
end;

{procedure TAiVeoGenerator.UploadFileSync(aMediaFile: TAiMediaFile);
var
  LHttpClient: TNetHTTPClient;
  LStartUrl, LUploadUrl, LFileUri, CloudName, CloudState: string;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
  LUploadResponseObj: TJSONObject;
  LFileStream: TStream;
  LNumBytes: Int64;
begin
  aMediaFile.CloudName := '';
  aMediaFile.UrlMedia := '';
  aMediaFile.CloudState := 'UPLOADING';

  LHttpClient := TNetHTTPClient.Create(Nil);
  try
    // --- STEP 1: Start the resumable upload (start command) ---
    LStartUrl := GEMINI_API_UPLOAD_URL + 'files?key=' + Self.ApiKey;

    LFileStream := aMediaFile.Content;
    LFileStream.Position := 0;
    LNumBytes := LFileStream.Size;

    if LNumBytes = 0 then
      raise Exception.Create('Cannot upload an empty file.');

    // The start request DOES NOT CARRY A BODY. Metadata goes in the headers.
    LHttpClient.ContentType := 'application/json'; // ContentType is still required
    LHeaders := [TNetHeader.Create('X-Goog-Upload-Protocol', 'resumable'), TNetHeader.Create('X-Goog-Upload-Command', 'start'), TNetHeader.Create('X-Goog-Upload-Header-Content-Length', LNumBytes.ToString),
      TNetHeader.Create('X-Goog-Upload-Header-Content-Type', aMediaFile.MimeType)];

    // Send the POST request with a NIL body
    LResponse := LHttpClient.Post(LStartUrl, TStream(nil), nil, LHeaders);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error initiating file upload: %d %s'#13#10'%s', [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);

    LUploadUrl := LResponse.HeaderValue['X-Goog-Upload-Url'];
    if LUploadUrl = '' then
      raise Exception.Create('Did not receive the upload URL from Google API. This likely means the START request failed silently. Response Body: ' + LResponse.ContentAsString);

    // --- STEP 2: Upload file bytes and finalize ---
    LFileStream.Position := 0;
    LHeaders := [TNetHeader.Create('Content-Length', LNumBytes.ToString), TNetHeader.Create('X-Goog-Upload-Offset', '0'), TNetHeader.Create('X-Goog-Upload-Command', 'upload, finalize')];

    LHttpClient.ContentType := aMediaFile.MimeType;
    LResponse := LHttpClient.Post(LUploadUrl, LFileStream, nil, LHeaders);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error uploading file bytes: %d %s'#13#10'%s', [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);

    // --- STEP 3: Process the final response (with correction) ---
    LUploadResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    if Assigned(LUploadResponseObj) then
      try
        var
          LFileObj: TJSONObject; // Variable for the nested object "file"

          // Get the nested object called "file"
        if LUploadResponseObj.TryGetValue<TJSONObject>('file', LFileObj) then
        begin
          // Now that we have LFileObj, extract values from it
          LFileObj.TryGetValue<string>('uri', LFileUri);
          LFileObj.TryGetValue<string>('name', CloudName);
          LFileObj.TryGetValue<string>('state', CloudState);

          aMediaFile.UrlMedia := LFileUri;
          aMediaFile.CloudName := CloudName;
          aMediaFile.CloudState := CloudState;

          if aMediaFile.CloudName.IsEmpty then
            raise Exception.Create('File uploaded but the final response did not contain a resource name (CloudName).');
        end
        else
        begin
          // If we don't find the "file" object, the response format is unexpected
          raise Exception.Create('File upload response has an unexpected format. Missing "file" object.');
        end;
      finally
        LUploadResponseObj.Free;
      end
    else
      raise Exception.Create('File uploaded but the final response was not a valid JSON object.');
  finally
    LHttpClient.Free;
  end;
end;

function TAiVeoGenerator.UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer): String;
var
  LHttpClient: TNetHTTPClient;
  LUrl: string;
  LResponse: IHTTPResponse;
  LRequestBody, LJson, LPart, LInlineData: TJSONObject;
  LPartsArray, LContentsArray: TJSONArray;
  CacheName, LModel: string;
begin
  Result := '';
  if not Assigned(aMediaFile) or (aMediaFile.Base64 = '') then
    raise Exception.Create('A file with Base64 content is required to create a cache.');

  LModel := GetEffectiveModelName; // TAiChatFactory.Instance.GetBaseModel(GetDriverName, Model);

  LHttpClient := TNetHTTPClient.Create(Nil);
//$IF CompilerVersion >= 35
  LHttpClient.SynchronizeEvents := False;
//$ENDIF
  try
    LUrl := GEMINI_API_BASE_URL + 'cachedContents?key=' + Self.ApiKey;

    LRequestBody := TJSONObject.Create;
    try
      LRequestBody.AddPair('model', TJSONString.Create(LModel));
      LRequestBody.AddPair('ttl', TJSONString.Create(aTTL_Seconds.ToString + 's'));

      LContentsArray := TJSONArray.Create;
      LJson := TJSONObject.Create;
      LJson.AddPair('role', TJSONString.Create('user'));
      LPartsArray := TJSONArray.Create;

      LPart := TJSONObject.Create;
      LInlineData := TJSONObject.Create;
      LInlineData.AddPair('mime_type', TJSONString.Create(aMediaFile.MimeType));
      LInlineData.AddPair('data', TJSONString.Create(aMediaFile.Base64));
      LPart.AddPair('inline_data', LInlineData);

      LPartsArray.Add(LPart);
      LJson.AddPair('parts', LPartsArray);
      LContentsArray.Add(LJson);
      LRequestBody.AddPair('contents', LContentsArray);

      LHttpClient.ContentType := 'application/json';
      var
      LBodyStream := TStringStream.Create(LRequestBody.ToJSON, TEncoding.UTF8);
      try
        LResponse := LHttpClient.Post(LUrl, LBodyStream);
      finally
        LBodyStream.Free;
      end;
    finally
      LRequestBody.Free;
    end;

    if LResponse.StatusCode = 200 then
    begin
      var
      LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      if Assigned(LResponseObj) then
        try
          if LResponseObj.TryGetValue<string>('name', CacheName) then
          begin
            aMediaFile.CacheName := CacheName;
            Result := CacheName;
            if aMediaFile.CacheName = '' then
              raise Exception.Create('API did not return a cache name (CacheName).');
          end;
        finally
          LResponseObj.Free;
        end;
    end
    else
    begin
      raise Exception.CreateFmt('Error creating content cache: %d %s'#13#10'%s', [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);
    end;
  finally
    LHttpClient.Free;
  end;
end;
}


procedure TAiVeoGenerator.UploadFileSync(aMediaFile: TAiMediaFile);
var
  LHttpClient: TNetHTTPClient;
  LStartUrl, LUploadUrl, LFileUri, CloudName, CloudState: string;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
  LJsonBody, LFileMeta, LUploadResponseObj, LFileObj: TJSONObject;
  LBodyStream: TStringStream;
  LFileStream: TStream;
  LNumBytes: Int64;
begin
  // Reset object state
  aMediaFile.CloudName := '';
  aMediaFile.UrlMedia := '';
  aMediaFile.CloudState := 'UPLOADING';

  LHttpClient := TNetHTTPClient.Create(Nil);
  try
    // --- STEP 1: Start upload session (Handshake) ---
    LStartUrl := GEMINI_API_UPLOAD_URL + 'files?key=' + Self.ApiKey;

    LFileStream := aMediaFile.Content;
    LFileStream.Position := 0;
    LNumBytes := LFileStream.Size;

    if LNumBytes = 0 then
      raise Exception.Create('Cannot upload an empty file.');

    // Build JSON metadata for the start
    LJsonBody := TJSONObject.Create;
    try
      LFileMeta := TJSONObject.Create;
      // Use the file name or a default
      LFileMeta.AddPair('display_name', TJSONString.Create(ExtractFileName(aMediaFile.FileName)));
      LJsonBody.AddPair('file', LFileMeta);

      // Convert JSON to Stream
      LBodyStream := TStringStream.Create(LJsonBody.ToJSON, TEncoding.UTF8);
    finally
      LJsonBody.Free;
    end;

    try
      LHttpClient.ContentType := 'application/json';
      LHeaders := [
        TNetHeader.Create('X-Goog-Upload-Protocol', 'resumable'),
        TNetHeader.Create('X-Goog-Upload-Command', 'start'),
        TNetHeader.Create('X-Goog-Upload-Header-Content-Length', LNumBytes.ToString),
        TNetHeader.Create('X-Goog-Upload-Header-Content-Type', aMediaFile.MimeType)
      ];

      // Initial POST with metadata
      LResponse := LHttpClient.Post(LStartUrl, LBodyStream, nil, LHeaders);
    finally
      LBodyStream.Free;
    end;

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error initiating upload handshake: %d %s'#13#10'%s',
        [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);

    // Get the upload URL from the headers
    LUploadUrl := LResponse.HeaderValue['X-Goog-Upload-Url'];
    if LUploadUrl = '' then
      raise Exception.Create('Did not receive the X-Goog-Upload-Url header from Google API.');

    // --- STEP 2: Upload file bytes (Payload) ---
    LFileStream.Position := 0;

    // Headers for the byte transfer
    LHeaders := [
      TNetHeader.Create('Content-Length', LNumBytes.ToString),
      TNetHeader.Create('X-Goog-Upload-Offset', '0'),
      TNetHeader.Create('X-Goog-Upload-Command', 'upload, finalize')
    ];

    LHttpClient.ContentType := aMediaFile.MimeType; // Important: actual file type
    LResponse := LHttpClient.Post(LUploadUrl, LFileStream, nil, LHeaders);

    if LResponse.StatusCode <> 200 then
      raise Exception.CreateFmt('Error uploading file bytes: %d %s'#13#10'%s',
        [LResponse.StatusCode, LResponse.StatusText, LResponse.ContentAsString]);

    // --- STEP 3: Process final response ---
    LUploadResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    if Assigned(LUploadResponseObj) then
      try
        // Successful response contains a 'file' object
        if LUploadResponseObj.TryGetValue<TJSONObject>('file', LFileObj) then
        begin
          LFileObj.TryGetValue<string>('uri', LFileUri);
          LFileObj.TryGetValue<string>('name', CloudName); // Format: files/abc-123
          LFileObj.TryGetValue<string>('state', CloudState); // Usually PROCESSING or ACTIVE

          aMediaFile.UrlMedia := LFileUri;
          aMediaFile.CloudName := CloudName;
          aMediaFile.CloudState := CloudState;

          if aMediaFile.UrlMedia.IsEmpty then
            raise Exception.Create('File uploaded but URI is missing in response.');
        end
        else
        begin
          raise Exception.Create('Unexpected JSON format in upload response: "file" object missing.');
        end;
      finally
        LUploadResponseObj.Free;
      end
    else
      raise Exception.Create('File uploaded but response is not a valid JSON.');

  finally
    LHttpClient.Free;
  end;
end;


{
function TAiVeoGenerator.WaitForFileToBeActive(const ACloudName: string): Boolean;
var
  LHttpClient: TNetHTTPClient;
  LUrl, LState: string;
  LResponse: IHTTPResponse;
  LResponseObj, LFileObj: TJSONObject;
  LHeaders: TNetHeaders;
  LRetryCount: Integer;
const
  MAX_RETRIES = 15; // 15 retries * 2 seconds = 30 second timeout
begin
  Result := False;
  if ACloudName.IsEmpty then
    Exit;

  DoProgress('File uploaded. Waiting for it to be processed by Google...');

  LHttpClient := TNetHTTPClient.Create(nil);
  try
    // The URL to check the file status is /v1beta/files/ID
    // ACloudName has the format "files/ID", so we use it directly.
    LUrl := TPath.Combine(GEMINI_API_BASE_URL, ACloudName) + '?key=' + Self.ApiKey;
    LHeaders := []; // No special headers needed for a simple GET

    LRetryCount := 0;
    while LRetryCount < MAX_RETRIES do
    begin
      Sleep(2000); // Wait 2 seconds between each query
      Inc(LRetryCount);

      DoProgress('Checking file status... Attempt ' + LRetryCount.ToString);

      LResponse := LHttpClient.Get(LUrl, nil, LHeaders);

      if LResponse.StatusCode = 200 then
      begin
        LResponseObj := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
        if Assigned(LResponseObj) then
          try
            if LResponseObj.TryGetValue<TJSONObject>('file', LFileObj) then
            begin
              LFileObj.TryGetValue<string>('state', LState);
              if LState.Equals('ACTIVE') then
              begin
                DoProgress('File is now active and ready to use.');
                Result := True;
                Exit; // Exit loop and function with success
              end
              else if LState.Equals('FAILED') then
              begin
                DoError('File processing failed on Google''s side.');
                Exit; // Exit with failure
              end;
              // If the state is "PROCESSING", simply continue the loop
            end;
          finally
            LResponseObj.Free;
          end;
      end
      else
      begin
        DoError('Error checking file status: ' + LResponse.StatusText);
        Exit; // Exit with failure if the status check fails
      end;
    end;

    // If we exit the loop due to timeout
    DoError('Timeout waiting for file to become active.');

  finally
    LHttpClient.Free;
  end;
end;
}

end.
