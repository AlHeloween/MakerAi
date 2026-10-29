// IT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// o use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// HE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enr�quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uVeoDemo;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.IOUtils, System.JSON, System.Rtti,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Platform,

  uMakerAi.Gemini.Veo, uMakerAi.UI.ChatInput, FMX.Layouts, uMakerAi.UI.ChatList,
  uMakerAi.Core, uMakerAi.utils.System,

  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo, FMX.ListBox, FMX.Menus;

type

  TVeoGenerationMode = (gmAuto, // The procedure decides automatically (default behavior)
    gmFrames, // Force interpolation mode (first/last frame)
    gmReferences // Force reference images mode
    );

  TForm11 = class(TForm)
    AiVeo: TAiVeoGenerator;
    MainLayout: TLayout;
    Layout1: TLayout;
    Layout2: TLayout;
    Splitter1: TSplitter;
    Modo: TGroupBox;
    rbAuto: TRadioButton;
    rbInter: TRadioButton;
    rbReference: TRadioButton;
    SaveDialog1: TSaveDialog;
    cbModel: TComboBox;
    Model: TLabel;
    Label2: TLabel;
    cbAspectRatio: TComboBox;
    Label3: TLabel;
    cbResolution: TComboBox;
    Label1: TLabel;
    cbPersonGeneration: TComboBox;
    Label4: TLabel;
    cbDuration: TComboBox;
    Layout3: TLayout;
    Layout4: TLayout;
    Memo1: TMemo;
    Layout5: TLayout;
    LayoutLog: TLayout;
    Label5: TLabel;
    Label6: TLabel;
    memoLog: TMemo;
    ChatList1: TChatList;
    Splitter2: TSplitter;
    Layout6: TLayout;
    ChatInput1: TChatInput;
    LayoutNegativePrompt: TLayout;
    Label7: TLabel;
    MemoNegativePrompt: TMemo;
    Label8: TLabel;
    PopupMenu1: TPopupMenu;
    MnuCopy: TMenuItem;
    MnuSave: TMenuItem;
    MnuPlay: TMenuItem;
    AniIndicator1: TAniIndicator;
    procedure ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
    procedure ChatInput1SlideChange(Sender: TObject; Data: TImageData);
    procedure AiVeoSuccess(Sender: TObject; ResultVideo: TAiMediaFile);
    procedure AiVeoProgress(Sender: TObject; const StatusMessage: string);
    procedure AiVeoError(Sender: TObject; const ErrorMessage: string);
    procedure ChatInput1Cancel(Sender: TObject);
    procedure MnuCopyClick(Sender: TObject);
    Function CopyToClipBoard(AMediaFile: TAiMediaFile): Boolean;
    procedure MnuSaveClick(Sender: TObject);
    procedure MnuPlayClick(Sender: TObject);
  private
    procedure ExecuteVeoTask(const APrompt: string; aMediaFiles: TAiMediaFiles; aMode: TVeoGenerationMode = gmAuto);
    function AllFilesAreImages: Boolean;
    function GetSelectedVeoMode: TVeoGenerationMode;
    procedure UpdateModeSelectorUI;
  public
  end;

var
  Form11: TForm11;

implementation

{$R *.fmx}

function TForm11.GetSelectedVeoMode: TVeoGenerationMode;
begin
  // The ItemIndex of the TRadioGroup corresponds directly to the order of our enum

  Result := gmAuto;

  if rbAuto.IsChecked then
    Result := gmAuto;
  if rbInter.IsChecked then
    Result := gmFrames;
  if rbReference.IsChecked then
    Result := gmReferences;
end;

procedure TForm11.MnuCopyClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
begin
  LMediaFile := ChatList1.ActiveMediaFile;

  if (LMediaFile <> nil) then
  begin
    // We simply call the method. All the complex logic is encapsulated!
    if CopyToClipBoard(LMediaFile) then
    begin
      // Optional: Notify the user that the copy was successful
      // ShowMessage('Content copied to clipboard.');
    end
    else
    begin
      // Optional: Notify if the file type cannot be copied
      showMessage('This type of file cannot be copied to the clipboard.');
    end;
  end;

end;

procedure TForm11.MnuPlayClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
  LTempPath: string;
  LFileStream: TFileStream;
  AppService: IFMXApplicationService;
begin
  // 1. Get the active file from TChatList
  LMediaFile := ChatList1.ActiveMediaFile;

  if LMediaFile = nil then
  begin
    showMessage('Error: No file has been selected.');
    Exit;
  end;

  // 2. Verify that the file has content to save
  if (LMediaFile.Content = nil) or (LMediaFile.Content.size = 0) then
  begin
    showMessage('The selected file is empty.');
    Exit;
  end;

  // 3. Build the temporary file path
  try
    LTempPath := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, LMediaFile.FileName);

    // 4. Save the stream content to the temporary file
    LMediaFile.Content.Position := 0; // Always rewind before reading
    LFileStream := TFileStream.Create(LTempPath, fmCreate);
    try
      LFileStream.CopyFrom(LMediaFile.Content, LMediaFile.Content.size);
    finally
      LFileStream.Free;
    end;
    LMediaFile.Content.Position := 0; // Leave it ready for future reads

    // 5. Use the platform service to open the file
    if TPlatformServices.Current.SupportsPlatformService(IFMXApplicationService, IInterface(AppService)) then
    begin
      if not TUtilsSystem.ShellOpenFile(LTempPath) then
      begin
        showMessage('Could not open the file. Check whether you have an application installed for this type of file (' + System.IOUtils.TPath.GetExtension(LMediaFile.FileName) + ').');
      end;
    end
    else
    begin
      showMessage('The service to open files is not available on this platform.');
    end;

  except
    on E: Exception do
    begin
      // Capture any error during file creation
      showMessage('An error occurred while trying to open the file: ' + E.Message);
    end;
  end;

end;

procedure TForm11.MnuSaveClick(Sender: TObject);
var
  LMediaFile: TAiMediaFile;
begin
  LMediaFile := ChatList1.ActiveMediaFile;

  if (LMediaFile <> nil) then
  begin
    SaveDialog1.FileName := LMediaFile.FileName;
    If SaveDialog1.Execute then
      LMediaFile.SaveToFile(SaveDialog1.FileName);
  end;
end;

procedure TForm11.UpdateModeSelectorUI;
var
  attachments: TArray<TImageData>;
  attachmentCount: Integer;
  areAllImages: Boolean;
begin
  // 1. Get the list of attachments and their count.
  attachments := ChatInput1.GetAttachments;
  attachmentCount := Length(attachments);

  // 2. Determine whether all files in the list are images.
  // We call our refactored function that needs no parameters.
  areAllImages := AllFilesAreImages;

  // 3. Apply the UI logic based on the file count and whether they are images.

  // Case A: There are exactly 2 files and ALL are images.
  if (attachmentCount = 2) and areAllImages then
  begin
    // With 2 images, all options are potentially valid.
    rbAuto.Enabled := True;
    rbInter.Enabled := True;
    rbReference.Enabled := True;
  end
  // Case B: There are exactly 3 files and ALL are images.
  else if (attachmentCount = 3) and areAllImages then
  begin
    // With 3 images, interpolation is not possible.
    // We enable the corresponding options and select 'Auto' by default.
    rbAuto.Enabled := True;
    rbAuto.IsChecked := True; // We select 'Auto'
    rbInter.Enabled := False; // We disable 'Interpolate'
    rbReference.Enabled := True;
  end
  // Case C: Any other situation (0, 1, 4+ files, or if there are files that are not images).
  else
  begin
    // In any other case, we disable all special options.
    // 'Auto' remains selected by default but disabled.
    rbAuto.Enabled := False;
    rbAuto.IsChecked := True;
    rbInter.Enabled := False;
    rbReference.Enabled := False;
  end;
end;

// Helper function to check if all files in the list are images
procedure TForm11.AiVeoError(Sender: TObject; const ErrorMessage: string);
begin
  memoLog.Lines.Add(ErrorMessage);
  showMessage(ErrorMessage);
end;

procedure TForm11.AiVeoProgress(Sender: TObject; const StatusMessage: string);
begin
  ChatInput1.AddStatus(StatusMessage);
  memoLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + ': ' + StatusMessage);
  memoLog.GoToLineEnd;
end;

procedure TForm11.AiVeoSuccess(Sender: TObject; ResultVideo: TAiMediaFile);
var
  LSaveDialog: TSaveDialog;
  LBaseFileName, LMetaDataFileName: string;
  LJson: TJSONObject;
  MediaFiles: TAiMediaFiles;
begin

  ChatInput1.Busy := False;
  AniIndicator1.Visible := False;
  AniIndicator1.Enabled := False;

  MediaFiles := TAiMediaFiles.Create;
  MediaFiles.Add(ResultVideo);

  ChatList1.AddBubble('Result:', 'Model', MediaFiles, False);

  memoLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + ': Video downloaded successfully.');

  LSaveDialog := TSaveDialog.Create(Self);
  try
    LSaveDialog.Title := 'Save Generated Video';
    LSaveDialog.Filter := 'MPEG-4 Video (*.mp4)|*.mp4';
    LSaveDialog.DefaultExt := 'mp4';

    if LSaveDialog.Execute then
    begin
      LBaseFileName := LSaveDialog.FileName;

      // Save the video file (.mp4)
      try
        ResultVideo.SaveToFile(LBaseFileName);
        memoLog.Lines.Add('Video file saved to: ' + LBaseFileName);
      except
        on E: Exception do
        begin
          showMessage('Failed to save video file: ' + E.Message);
          Exit;
        end;
      end;

      // Create the metadata file name
      LMetaDataFileName := TPath.ChangeExtension(LBaseFileName, '.veometa');

      // --- START OF NEW LOGIC ---
      // 1. Get the complete JSON object (including Base64)
      LJson := ResultVideo.ToJsonObject;
      try
        // 2. Remove the "base64" key/value pair from the JSON object
        LJson.RemovePair('base64');
        memoLog.Lines.Add('Metadata prepared (Base64 content excluded).');

        // 3. Save the modified JSON (without Base64) to the file
        TFile.WriteAllText(LMetaDataFileName, LJson.ToJSON);
        memoLog.Lines.Add('Metadata saved to: ' + LMetaDataFileName);
      finally
        LJson.Free; // Free the JSON object
      end;
      // --- END OF NEW LOGIC ---
    end
    else
    begin
      memoLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + ': Video generation successful, but file saving was cancelled by the user.');
    end;
  finally
    LSaveDialog.Free;
  end;
end;

function TForm11.AllFilesAreImages: Boolean;
var
  attachments: TArray<TImageData>;
  imageData: TImageData;
  fileExtension: string;
  contentType: TContentType;
begin
  // 1. Get the list of all attachments of the component.
  attachments := ChatInput1.GetAttachments;

  // 2. If the list is empty, the condition "all are images" is not met.
  if Length(attachments) = 0 then
  begin
    Result := False;
    Exit;
  end;

  // 3. We assume all files are images until proven otherwise.
  Result := True;

  // 4. Iterate over each attachment.
  for imageData in attachments do
  begin
    // 5. Extract the file name extension safely.
    fileExtension := TPath.GetExtension(imageData.FileName);

    // 6. KEY CALL: Use the component's public function to determine the content type
    // based on the component's internal logic and its ValidExtensions property.
    contentType := ChatInput1.GetContentTypeFromValidExtensions(fileExtension);

    // 7. Validate whether the returned content type is an image.
    if contentType <> ctImage then
    begin
      // If we find a SINGLE file that is not classified as an image,
      // the general condition fails. We set the result to False
      // and exit the loop and the function immediately.
      Result := False;
      Exit;
    end;
  end;

  // 8. If the loop completes without finding any file that is not an image,
  // the initial assumption (Result := True) is correct and is returned.
end;

function AllMediaFilesAreImages(aMediaFiles: TAiMediaFiles): Boolean;
var
  MF: TAiMediaFile;
begin
  Result := True;
  if aMediaFiles.Count = 0 then
    Exit(False); // No files, so not "all are images"
  for MF in aMediaFiles do
  begin
    if MF.FileCategory <> TAiFileCategory.Tfc_Image then
      Exit(False); // Found one that is not an image, fail
  end;
end;

procedure TForm11.ExecuteVeoTask(const APrompt: string; aMediaFiles: TAiMediaFiles; aMode: TVeoGenerationMode = gmAuto);
var
  LVideoFileToExtend: TAiMediaFile;
  LMetaDataFileName: string;
  LJsonValue: TJSONValue;
  LJsonObj: TJSONObject;
  LErrorMsg: string;
begin
  // --- MUTUALLY EXCLUSIVE DECISION LOGIC ---

  // CASE 1: There is a single file and it is a VIDEO. The only option is to extend it.
  if (aMediaFiles.Count = 1) and (aMediaFiles[0].FileCategory = TAiFileCategory.Tfc_Video) then
  begin
    memoLog.Lines.Add('Detected 1 video. Checking for metadata to extend...');

    // 1. Determine the expected metadata file path (e.g. 'my_video.veometa')
    LMetaDataFileName := TPath.ChangeExtension(aMediaFiles[0].FullFileName, '.veometa');

    // 2. Verify whether the metadata file exists.
    if not TFile.Exists(LMetaDataFileName) then
    begin
      LErrorMsg := 'Error: Metadata file (' + TPath.GetFileName(LMetaDataFileName) + ') not found.' + sLineBreak + sLineBreak + 'This video cannot be extended because its original VEO identifier is missing. ' +
        'Only videos previously generated and saved by this application can be extended.';
      memoLog.Lines.Add(LErrorMsg);
      showMessage(LErrorMsg);
      Exit; // Exit the function, cannot continue.
    end;

    // 3. If it exists, proceed to load and use it.
    LVideoFileToExtend := TAiMediaFile.Create;
    try
      try
        // 3.1. Read the text file content.
        var
        LJsonText := TFile.ReadAllText(LMetaDataFileName);

        // 3.2. Parse the text into a JSON object.
        LJsonValue := TJSONObject.ParseJSONValue(LJsonText);

        // 3.3. Ensure the parsing resulted in an object and not another JSON value type.
        if not Assigned(LJsonValue) or not(LJsonValue is TJSONObject) then
          raise Exception.Create('Metadata file is not a valid JSON object.');

        LJsonObj := LJsonValue as TJSONObject;

        // 3.4. Use the existing method to load all JSON data into our object.
        LVideoFileToExtend.LoadFromJsonObject(LJsonObj);

        // 3.5. A final validation to ensure the most important data (UrlMedia) is present.
        if LVideoFileToExtend.UrlMedia.IsEmpty then
          raise Exception.Create('Metadata file does not contain the required "urlMedia" identifier.');

      except
        on E: Exception do
        begin
          LErrorMsg := 'Error processing metadata file: ' + E.Message;
          memoLog.Lines.Add(LErrorMsg);
          showMessage(LErrorMsg);
          Exit; // Exit if there is an error with the metadata.
        end;
      end;

      // 4. If everything went well, LVideoFileToExtend is now a valid object.
      memoLog.Lines.Add('Metadata loaded. Initiating video extension...');
      AiVeo.ExtendVideo(APrompt, LVideoFileToExtend);

    finally
      LVideoFileToExtend.Free; // The object only lives during this call.
    end;
  end

  // CASE 2: There is one or more files and ALL are IMAGES.
  else if (aMediaFiles.Count > 0) and AllMediaFilesAreImages(aMediaFiles) then
  begin
    // Now we decide what to do with these images
    case aMediaFiles.Count of
      1: // With a single image, the only option is Image-to-Video
        begin
          memoLog.Lines.Add('Detected 1 image. Starting mode: Image to Video...');
          AiVeo.GenerateFromImage(APrompt, aMediaFiles[0]);
        end;

      2: // With two images, it can be Interpolation or References.
        begin
          // We use the aMode parameter to decide. By default (gmAuto), we assume Interpolation.
          if (aMode = gmAuto) or (aMode = gmFrames) then
          begin
            memoLog.Lines.Add('Detected 2 images. Starting mode: Interpolation (Frames)...');
            AiVeo.GenerateFromFrames(APrompt, aMediaFiles[0], aMediaFiles[1]);
          end
          else // aMode = gmReferences
          begin
            memoLog.Lines.Add('Detected 2 images. Forcing mode: Reference Images...');
            AiVeo.GenerateWithReferences(APrompt, aMediaFiles.ToMediaFileArray);
          end;
        end;

      3: // With three images, it can be Interpolation (if forced) or References.
        begin
          // By default (gmAuto), we assume References, which is the most common use case for 3 images.
          if (aMode = gmAuto) or (aMode = gmReferences) then
          begin
            memoLog.Lines.Add('Detected 3 images. Starting mode: Reference Images...');
            AiVeo.GenerateWithReferences(APrompt, aMediaFiles.ToMediaFileArray);
          end
          else // aMode = gmFrames
          begin
            // The user is forcing a mode that is not compatible with 3 images
            raise Exception.Create('Interpolation (Frames) mode only supports exactly 2 images. 3 were provided.');
          end;
        end
    else
      // If there are more than 3 images, the only option is References, but the API has a limit.
      if aMediaFiles.Count > 3 then
      begin
        raise Exception.Create('VEO only supports a maximum of 3 reference images. ' + aMediaFiles.Count.ToString + ' were provided.');
      end;
    end;
  end

  // CASE 3: There are NO media files. The only option is Text-to-Video.
  else if (aMediaFiles.Count = 0) then
  begin
    memoLog.Lines.Add('No files detected. Starting mode: Text to Video...');
    AiVeo.GenerateFromText(APrompt);
  end

  // CASE 4: Invalid combination (e.g. images and videos, or text files).
  else
  begin
    LErrorMsg := 'Unsupported file combination for video generation. Please provide only images or a single video.';
    memoLog.Lines.Add('ERROR: ' + LErrorMsg);
    // Optional: raise Exception.Create(LErrorMsg);
  end;
end;

procedure TForm11.ChatInput1Cancel(Sender: TObject);
begin
  ChatInput1.Busy := False;
  AniIndicator1.Visible := False;
  AniIndicator1.Enabled := False;
end;

procedure TForm11.ChatInput1SendEvent(Sender: TObject; APrompt: string; aMediaFiles: TAiMediaFiles; aAudioStream: TMemoryStream);
Var
  Model: TVeoModel; // = (vmCustom, vmVeo3_1, vmVeo3_1_Fast, vmVeo3_0, vmVeo3_0_Fast, vmVeo2_0);
  Ratio: TVeoAspectRatio; // = (arDefault, ar16x9, ar9x16);
  Resolution: TVeoResolution; // = (vrDefault, vr720p, vr1080p);
  Person: TVeoPersonGeneration; // = (pgDefault, pgAllowAll, pgAllowAdult, pgDontAllow);
  Duration: Integer;
  NegativePrompt: String;

begin

  AniIndicator1.Visible := True;
  AniIndicator1.Enabled := True;
  memoLog.Lines.Clear;

  Model := TVeoModel(cbModel.ItemIndex); // = (vmCustom, vmVeo3_1, vmVeo3_1_Fast, vmVeo3_0, vmVeo3_0_Fast, vmVeo2_0);
  Ratio := TVeoAspectRatio(cbAspectRatio.ItemIndex); // = (arDefault, ar16x9, ar9x16);
  Resolution := TVeoResolution(cbResolution.ItemIndex); // = (vrDefault, vr720p, vr1080p);
  Person := TVeoPersonGeneration(cbPersonGeneration.ItemIndex); // = (pgDefault, pgAllowAll, pgAllowAdult, pgDontAllow);
  Duration := StrToIntDef(cbDuration.Text, 8);
  NegativePrompt := Trim(MemoNegativePrompt.Lines.Text);

  AiVeo.Model := Model;
  AiVeo.AspectRatio := Ratio;
  AiVeo.Resolution := Resolution;
  AiVeo.PersonGeneration := Person;
  AiVeo.DurationSeconds := Duration;
  AiVeo.NegativePrompt := NegativePrompt;

  if (aMediaFiles.Count = 1) and (aMediaFiles[0].FileCategory = TAiFileCategory.Tfc_Video) then
  begin
    // The TAiMediaFile still has the FullFileName, which is what we need.
    // We simply clear the TMemoryStream to free RAM.
    aMediaFiles[0].Content.Clear;
    memoLog.Lines.Add('[Optimization] Video content cleared from memory for extension task.');
  end;

  try
    ChatList1.AddBubble(APrompt, 'user', aMediaFiles, True);

    ExecuteVeoTask(APrompt, aMediaFiles, GetSelectedVeoMode);

    MemoNegativePrompt.Lines.Clear;

  except
    on E: Exception do
      showMessage('Error: ' + E.Message);
  end;

end;

procedure TForm11.ChatInput1SlideChange(Sender: TObject; Data: TImageData);
Begin
  UpdateModeSelectorUI;
end;

function TForm11.CopyToClipBoard(AMediaFile: TAiMediaFile): Boolean;
var
  ClipboardSvc: IFMXClipboardService;
  LBitmap: FMX.Graphics.TBitmap;
  LText: string;
begin
  Result := False;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, IInterface(ClipboardSvc)) then
    Exit; // No hay servicio de portapapeles disponible

  // Before any operation, make sure the stream is at the beginning.
  if Assigned(AMediaFile.Content) then
    AMediaFile.Content.Position := 0;

  // The copy logic depends on the file category
  case AMediaFile.FileCategory of
    Tfc_Image:
      begin
        if (AMediaFile.Content = nil) or (AMediaFile.Content.size = 0) then
          Exit;
        LBitmap := FMX.Graphics.TBitmap.Create;
        try
          LBitmap.LoadFromStream(AMediaFile.Content);
          ClipboardSvc.SetClipboard(LBitmap); // FMX sabe c�mo poner un TBitmap en el portapapeles
          Result := True;
        finally
          LBitmap.Free;
        end;
      end;

    Tfc_Text, tfc_ExtracttextFile:
      begin
        if (AMediaFile.Content = nil) or (AMediaFile.Content.size = 0) then
          Exit;

        // We read the stream content as UTF-8 text (the most common)
        var
        LReader := TStreamReader.Create(AMediaFile.Content, TEncoding.UTF8);
        try
          LText := LReader.ReadToEnd;
          // We use TValue.From<string> to pass it to the clipboard as plain text
          ClipboardSvc.SetClipboard(TValue.From<string>(LText));
          Result := True;
        finally
          LReader.Free;
        end;
      end;

    // For other file types (PDF, DOC, Audio, etc.), the standard clipboard
    // has no "native" format for them. The best option is to copy
    // the file PATH if it exists, or do nothing.
    // In this case, since the content is in a TMemoryStream, there is no path
    // that we can copy that another application could understand.
    // Therefore, for these types, we do nothing and the method returns False.
  else
    Result := False;
  end;

  // We rewind the stream in case it needs to be reused later.
  if Assigned(AMediaFile.Content) then
    AMediaFile.Content.Position := 0;

end;

end.
