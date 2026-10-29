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
// Name: Gustavo Enr�quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uMakerAi.UI.ChatBubble;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors, System.Math,
  System.UIConsts, System.Generics.Collections, System.IOUtils, FMX.Styles.Objects, System.JSON,

  uMakerAi.Core,
{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}

  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.Memo, FMX.TextLayout, FMX.ImgList,
  FMX.StdCtrls, FMX.Objects, FMX.Forms;

type
  TChatBubbleTailPosition = (tpLeft, tpRight);
  TChatBubblePart = (bpNone, bpBackground, bpHeader, bpAvatar, bpContent, bpExpandCollapse, bpMoreOptions);
  TTailStyle = (tsSimple, tsOrganic, tsComic, tsSharp);

  TCalculateContentSizeEvent = procedure(Sender: TObject; var AContentSize: TSizeF) of object;
  TRequiredSizeEvent = procedure(Sender: TObject; const ACalculatedHeight: Single) of object;
  TMediaFileEvent = procedure(Sender: TObject; const AMediaFile: TAiMediaFile) of object;
  TAttachmentContextEvent = procedure(Sender: TObject; const AMediaFile: TAiMediaFile; const MousePos: TPointF) of object;

  TListImages = TDictionary<String, TBitMap>;

  TChatBubble = class(TControl)
  private
    FGradientBrush: TBrush;
    FAvatarBrush: TBrush;
    FStrokeBrush: TStrokeBrush;
    FCornerRadius: Single;
    FBubbleColor: TAlphaColor;
    FGradientTransparency: Single;
    FTailPosition: TChatBubbleTailPosition;
    FTailOffsetPercent: Single;
    FTailWidth: Single;
    FTailHeight: Single;
    FTailCurveBias: Single;
    FTailSharpness: Single;
    FTailStyle: TTailStyle;
    FHeaderVisible: Boolean;
    FAvatar: TBitMap;
    FTitle: string;
    FTimestamp: string;
    FHeaderColorFactor: Single;
    FScaledAvatar: TBitMap;
    FAutoSize: Boolean;
    FIsCollapsed: Boolean;
    FCollapsedHeight: Single;
    FOriginalHeight: Single;
    FMoreOptionsVisible: Boolean;
    FLayoutCalculated: Boolean;
    FHotPart: TChatBubblePart;
    FDownPart: TChatBubblePart;
    FHeaderRect: TRectF;
    FAvatarRect: TRectF;
    FExpandCollapseRect: TRectF;
    FContentRect: TRectF;
    FMoreOptionsRect: TRectF;
    FLightenFactor: Single;
    FTimestampFont: TFont;
    FTitleFont: TFont;
    FImages: TImageList;
    FImageIndex: Integer;

    FOnAvatarClick: TNotifyEvent;
    FOnExpandCollapseClick: TNotifyEvent;
    FOnMoreOptionsClick: TNotifyEvent;
    // FOnCalculateContentSize: TCalculateContentSizeEvent;
    FOnRequiredSizeCalculated: TRequiredSizeEvent;
    FUserName: String;

    FContentLayout: TLayout; // Container for all dynamic content
    FDocIcons: TListImages;
    FContentFont: TFont;
    FMediaFiles: TAiMediaFiles;
    FOnMediaFileDblClick: TMediaFileEvent;
    FOnAttachmentContextPopup: TAttachmentContextEvent;
    FOnRecalculateRequired: TNotifyEvent; // ImageList for document icons

    procedure ClearContentControls;
    procedure LoadDocIconsFromResources;
    function CreateImageView(AMediaFile: TAiMediaFile): TImage;
    function CreateDocumentView(AMediaFile: TAiMediaFile): TLayout;
    // procedure ContentSizeCalculator(Sender: TObject; var AContentSize: TSizeF);
    procedure ContentSizeCalculator(AContentWidth: Single; var AContentSize: TSizeF);

    procedure SetCornerRadius(const Value: Single);
    procedure SetBubbleColor(const Value: TAlphaColor);
    procedure SetGradientTransparency(const Value: Single);
    procedure SetTailPosition(const Value: TChatBubbleTailPosition);
    procedure SetTailOffsetPercent(const Value: Single);
    procedure SetTailWidth(const Value: Single);
    procedure SetTailHeight(const Value: Single);
    procedure SetHeaderVisible(const Value: Boolean);
    procedure SetAvatar(const Value: TBitMap);
    procedure SetInternalAvatar(const Value: TBitMap; AResetImageIndex: Boolean = True);
    procedure SetTitle(const Value: string);
    procedure SetTimestamp(const Value: string);
    procedure SetHeaderColorFactor(const Value: Single);
    procedure SetAutoSize(const Value: Boolean);
    procedure SetIsCollapsed(const Value: Boolean);
    procedure SetCollapsedHeight(const Value: Single);
    procedure SetMoreOptionsVisible(const Value: Boolean);
    procedure SetLightenFactor(const Value: Single);
    procedure SetTimestampFont(const Value: TFont);
    procedure SetTitleFont(const Value: TFont);
    procedure SetTailSharpness(const Value: Single);
    procedure SetTailCurveBias(const Value: Single);
    procedure SetTailStyle(const Value: TTailStyle);
    procedure SetImageIndex(const Value: Integer);
    procedure SetImages(const Value: TImageList);
    procedure SetUserName(const Value: String);

    procedure InvalidateLayout;
    procedure CalculateLayout;
    procedure UpdateBubblePathData(APath: TPathData);
    procedure UpdateBubblePathDatatsSimple(APath: TPathData);
    procedure UpdateBubblePathDatatsOrganic(APath: TPathData);
    procedure UpdateBubblePathDatatsComic(APath: TPathData);
    procedure UpdateBubblePathDatatsSharp(APath: TPathData);
    function HitTest(const APoint: TPointF): TChatBubblePart;
    function CalculateRequiredHeightForAutoSize: Single;
    procedure UpdateScaledAvatar;
    procedure FontChanged(Sender: TObject);
    procedure ConfigureGradientToLighterColor;
    procedure UpdateAndNotifyRequiredHeight;
    procedure UpdateStructureAndSize;
    procedure UpdateAvatarFromImageList;
    procedure SetContentFont(const Value: TFont);
    procedure DoMediaFileDblClick(Sender: TObject);
    procedure DoContentMouseEnter(Sender: TObject);
    procedure DoContentMouseLeave(Sender: TObject);

  protected
    procedure Paint; override;
    procedure Loaded; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure Resize; override;
    procedure UpdatePaddings;
    procedure DoRealign; override;
    procedure HandleMouseDownOnAttachment(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);

    class function DarkenColor(AColor: TAlphaColor; AFactor: Single): TAlphaColor; static;
    class function LightenColor(AColor: TAlphaColor; AFactor: Single): TAlphaColor; static;

    Function LoadImageFromResource(ABitmap: TBitMap; const ResourceName: string): Boolean;
    function AddBitmapToImageList(ABitmap: TBitMap; ImageList: TImageList; const ItemName: string = ''): Integer;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    class function CalculateMemoSize(const AMemo: TMemo; AMaxWidth: Single): TSizeF;
    class function CalculateTextSize(AText: TText): TSizeF; static;

    function CalculateBubbleSizeForContent(const AContentSize: TSizeF): TSizeF;
    // class function CalculateBubbleSize(const AContentSize: TSizeF; AHeaderVisible, AMoreOptionsVisible: Boolean; ATailPosition: TChatBubbleTailPosition; ATailWidth: Single): TSizeF; static;
    function FindFirstChild<T: TControl>: T;
    Procedure SetSizeByContent(const AContentSize: TSizeF);

    procedure RecalculateSize(AMaxWidth: Single);
    procedure AddContent(const AText: string; AMediaFiles: TAiMediaFiles = nil);

    procedure AppendText(const ATextFragment: string);

    property ContentLayout: TLayout Read FContentLayout;
    property MediaFiles: TAiMediaFiles read FMediaFiles;

    function ToJsonObject: TJSONObject;
    procedure LoadFromJsonObject(AJsonObject: TJSONObject);

  published
    property Align;
    property Anchors;
    property AutoSize: Boolean read FAutoSize write SetAutoSize default False;
    property Avatar: TBitMap read FAvatar write SetAvatar;
    property BubbleColor: TAlphaColor read FBubbleColor write SetBubbleColor;
    property ClipChildren default False;
    property ClipParent default False;
    property CollapsedHeight: Single read FCollapsedHeight write SetCollapsedHeight;
    property CornerRadius: Single read FCornerRadius write SetCornerRadius;
    property Cursor default crDefault;
    property DragMode default TDragMode.dmManual;
    property EnableDragHighlight default True;
    property Enabled default True;
    property GradientTransparency: Single read FGradientTransparency write SetGradientTransparency;
    property HeaderColorFactor: Single read FHeaderColorFactor write SetHeaderColorFactor;
    property HeaderVisible: Boolean read FHeaderVisible write SetHeaderVisible default True;
    property Height;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    property Images: TImageList read FImages write SetImages;
    property IsCollapsed: Boolean read FIsCollapsed write SetIsCollapsed default False;
    property LightenFactor: Single read FLightenFactor write SetLightenFactor;
    property Locked default False;
    property Margins;
    property MoreOptionsVisible: Boolean read FMoreOptionsVisible write SetMoreOptionsVisible default True;
    property Opacity;
    property PopupMenu;
    property Position;
    property RotationAngle;
    property RotationCenter;
    property Scale;
    property Size;
    property TailCurveBias: Single read FTailCurveBias write SetTailCurveBias;
    property TailHeight: Single read FTailHeight write SetTailHeight;
    property TailOffsetPercent: Single read FTailOffsetPercent write SetTailOffsetPercent;
    property TailPosition: TChatBubbleTailPosition read FTailPosition write SetTailPosition default tpLeft;
    property TailSharpness: Single read FTailSharpness write SetTailSharpness;
    property TailStyle: TTailStyle read FTailStyle write SetTailStyle default tsSimple;
    property TailWidth: Single read FTailWidth write SetTailWidth;
    property Timestamp: String read FTimestamp write SetTimestamp;
    property TimestampFont: TFont read FTimestampFont write SetTimestampFont;
    property Title: String read FTitle write SetTitle;
    property TitleFont: TFont read FTitleFont write SetTitleFont;
    property ContentFont: TFont read FContentFont write SetContentFont;
    property TouchTargetExpansion;
    property UserName: String read FUserName write SetUserName;
    property Visible;
    property Width;

    // Events
    property OnAvatarClick: TNotifyEvent read FOnAvatarClick write FOnAvatarClick;
    // property OnCalculateContentSize: TCalculateContentSizeEvent read FOnCalculateContentSize write FOnCalculateContentSize;
    property OnExpandCollapseClick: TNotifyEvent read FOnExpandCollapseClick write FOnExpandCollapseClick;
    property OnMoreOptionsClick: TNotifyEvent read FOnMoreOptionsClick write FOnMoreOptionsClick;
    property OnRequiredSizeCalculated: TRequiredSizeEvent read FOnRequiredSizeCalculated write FOnRequiredSizeCalculated;
    property OnMediaFileDblClick: TMediaFileEvent read FOnMediaFileDblClick write FOnMediaFileDblClick;
    property OnAttachmentContextPopup: TAttachmentContextEvent read FOnAttachmentContextPopup write FOnAttachmentContextPopup;
    property OnRecalculateRequired: TNotifyEvent read FOnRecalculateRequired write FOnRecalculateRequired;

    property OnApplyStyleLookup;
    property OnCanFocus;
    property OnClick;
    property OnDblClick;
    property OnDragDrop;
    property OnDragEnd;
    property OnDragEnter;
    property OnDragLeave;
    property OnDragOver;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnPaint;
    property OnPainting;
    property OnResize;
    property OnResized;
  end deprecated 'Use TAIChatView (AIChat.Control.FMX)';

procedure Register;

implementation

{$WARN SYMBOL_DEPRECATED OFF}

{$IFNDEF UIRESOURCES_LOADED}
{$DEFINE UIRESOURCES_LOADED}
{$R UIResources.res}
{$ENDIF}

procedure Register;
begin
  RegisterComponents('MakerAI UI', [TChatBubble]);
end;

{ TChatBubble }

const
  HEADER_HEIGHT = 30;
  AVATAR_SIZE = 24;
  ICON_SIZE = 16;
  CONTENT_PADDING = 8;
  HEADER_PADDING = 4;
  ICON_PADDING = 4;
  TIMESTAMP_AREA_WIDTH = 50;

  CONTENT_MARGIN_TOP = 8;
  CONTENT_MARGIN_LEFT = 8;
  CONTENT_MARGIN_RIGHT = 8;
  CONTENT_MARGIN_BOTTOM = 8;
  ICON_AREA_HEIGHT = ICON_SIZE + (ICON_PADDING * 2);

constructor TChatBubble.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Size.SetPlatformDefaultWithoutNotification(False);
  FGradientBrush := TBrush.Create(TBrushKind.Gradient, TAlphaColors.Null);

  FAvatarBrush := TBrush.Create(TBrushKind.Bitmap, TAlphaColors.Null);
  FAvatarBrush.Bitmap.WrapMode := TWrapMode.TileStretch;

  FStrokeBrush := TStrokeBrush.Create(TBrushKind.Solid, TAlphaColors.Black);
  FScaledAvatar := TBitMap.Create;
  FCornerRadius := 10;
  FBubbleColor := TAlphaColorRec.LightCyan;
  FGradientTransparency := 0.7;
  FLightenFactor := 0.7;
  FTailPosition := tpLeft;
  FTailOffsetPercent := 0.2;
  FTailWidth := 12;
  FTailHeight := 20;
  TailStyle := tsSharp;
  TailCurveBias := 0.8;
  TailSharpness := 1;
  FHeaderVisible := True;
  FHeaderColorFactor := 0.9;
  FAvatar := TBitMap.Create;
  FTitle := 'User';
  FTimestamp := '00:00';
  FAutoSize := False;
  FIsCollapsed := False;
  FCollapsedHeight := 48;
  FOriginalHeight := 0;
  FMoreOptionsVisible := True;
  FTitleFont := TFont.Create;
  FTitleFont.Size := 11;
  FTitleFont.Style := [TFontStyle.fsBold];
  FTitleFont.OnChanged := FontChanged;
  FTimestampFont := TFont.Create;
  FTimestampFont.Size := 10;
  FTimestampFont.OnChanged := FontChanged;
  FContentFont := TFont.Create;
  FContentFont.Size := 12; // A reasonable default size
  FContentFont.OnChanged := FontChanged; // We reuse the event you already have

  FLayoutCalculated := False;
  FHotPart := bpNone;
  FDownPart := bpNone;
  Padding.Rect := TRectF.Create(8, 8, 8, 8);
  FImageIndex := -1;
  FImages := nil;

  FDocIcons := TListImages.Create;
  LoadDocIconsFromResources;

  FContentLayout := TLayout.Create(Self);
  FContentLayout.Parent := Self;
  FContentLayout.Align := TAlignLayout.Client; // The layout will fill the padding area
  FMediaFiles := TAiMediaFiles.Create;


  // We assign the size calculator to the event you already have
  // OnCalculateContentSize := ContentSizeCalculator;

end;

function TChatBubble.CreateDocumentView(AMediaFile: TAiMediaFile): TLayout;
var
  Icon: TImage;
  LblFileName, LblInfo: TLabel;
  IconKey: string;
begin
  // Create the container layout for the document
  Result := TLayout.Create(nil);
  Result.Height := 48; // Fixed height for the document view
  Result.Align := TAlignLayout.Top;
  Result.Margins.Bottom := 8;
  Result.TagObject := AMediaFile;
  Result.OnDblClick := DoMediaFileDblClick;
  Result.HitTest := True;
  Result.OnMouseEnter := DoContentMouseEnter;
  Result.OnMouseLeave := DoContentMouseLeave;
  Result.OnMouseDown := HandleMouseDownOnAttachment;

  // Create the icon
  Icon := TImage.Create(Result);
  Icon.Parent := Result;
  Icon.Align := TAlignLayout.Left;
  Icon.Width := 40;
  Icon.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  Icon.HitTest := False;

  // Select the correct icon based on the category
  case AMediaFile.FileCategory of
    Tfc_pdf:
      IconKey := 'pdf';
    Tfc_Document:
      IconKey := 'doc';
    Tfc_Audio:
      IconKey := 'audio';
    Tfc_Video:
      IconKey := 'video';
    Tfc_Image:
      IconKey := 'image'; // Generic icon if it cannot be displayed
  else
    IconKey := 'unknown';
  end;

  Var
    BM: TBitMap;
  If FDocIcons.TryGetValue(IconKey, BM) then
    Icon.Bitmap.Assign(BM);

  // Create label for the file name
  LblFileName := TLabel.Create(Result);
  LblFileName.Parent := Result;
  LblFileName.Align := TAlignLayout.Client;
  LblFileName.Text := System.IOUtils.TPath.GetFileName(AMediaFile.filename);
  LblFileName.Font.Style := [TFontStyle.fsBold];
  LblFileName.VertTextAlign := TTextAlign.Leading;
  LblFileName.Margins.Top := 4;

  // Create label for additional information (size, type, etc.)
  LblInfo := TLabel.Create(Result);
  LblInfo.Parent := Result;
  LblInfo.Align := TAlignLayout.Client;
  LblInfo.Text := Format('%.2f KB', [AMediaFile.bytes / 1024]); // Example info
  LblInfo.Font.Size := 10;
  LblInfo.FontColor := TAlphaColors.Dimgray;
  LblInfo.VertTextAlign := TTextAlign.Trailing;
  LblInfo.Margins.Bottom := 4;

end;

function TChatBubble.CreateImageView(AMediaFile: TAiMediaFile): TImage;
const
  MAX_IMAGE_WIDTH = 250;
  MAX_IMAGE_HEIGHT = 300;
begin
  Result := TImage.Create(nil); // It will be added to FContentLayout, without owner
  try
    // Load the image from the media file stream
    AMediaFile.Content.Position := 0;
    Result.Bitmap.LoadFromStream(AMediaFile.Content);
    AMediaFile.Content.Position := 0;

    // Calculate size maintaining the aspect ratio
    var
    LRatio := Result.Bitmap.Width / Result.Bitmap.Height;
    Result.Width := MAX_IMAGE_WIDTH;
    Result.Height := Result.Width / LRatio;

    if Result.Height > MAX_IMAGE_HEIGHT then
    begin
      Result.Height := MAX_IMAGE_HEIGHT;
      Result.Width := Result.Height * LRatio;
    end;

    Result.Align := TAlignLayout.Top;
    Result.Margins.Bottom := 8; // Space between this and the next control
    Result.WrapMode := TImageWrapMode.Fit;

    Result.TagObject := AMediaFile;
    Result.OnDblClick := DoMediaFileDblClick; // <-- We assign our handler.
    Result.HitTest := True;
    Result.OnMouseEnter := DoContentMouseEnter;
    Result.OnMouseLeave := DoContentMouseLeave;
    Result.OnMouseDown := HandleMouseDownOnAttachment;
  except
    // If loading fails, free and return nil
    Result.Free;
    Result := nil;
  end;
end;

class function TChatBubble.DarkenColor(AColor: TAlphaColor; AFactor: Single): TAlphaColor;
var
  R, G, B, A: Byte;
  Rec: TAlphaColorRec;
begin
  Rec.Color := AColor;
  R := Round(Rec.R * AFactor);
  G := Round(Rec.G * AFactor);
  B := Round(Rec.B * AFactor);
  A := Rec.A;
  Result := MakeColor(R, G, B, A);

end;

destructor TChatBubble.Destroy;
begin
  FGradientBrush.Free;
  FAvatarBrush.Free;
  FStrokeBrush.Free;
  FAvatar.Free;
  FTitleFont.Free;
  FTimestampFont.Free;
  FContentFont.Free;
  FScaledAvatar.Free;
  FDocIcons.Free;
  FMediaFiles.Free;
  inherited Destroy;
end;

procedure TChatBubble.InvalidateLayout;
begin
  FLayoutCalculated := False;
  Repaint;
end;

class function TChatBubble.LightenColor(AColor: TAlphaColor; AFactor: Single): TAlphaColor;
var
  ColorRec: TAlphaColorRec;
begin
  ColorRec.Color := AColor;
  ColorRec.R := ColorRec.R + Round((255 - ColorRec.R) * AFactor);
  ColorRec.G := ColorRec.G + Round((255 - ColorRec.G) * AFactor);
  ColorRec.B := ColorRec.B + Round((255 - ColorRec.B) * AFactor);
  Result := ColorRec.Color;
end;

procedure TChatBubble.LoadDocIconsFromResources;
  procedure AddIcon(const aName, AResName: string);
  var
    BM: TBitMap;
  begin
    try
      BM := TBitMap.Create;
      try
        if LoadImageFromResource(BM, AResName) then
        begin
          try
            FDocIcons.Add(aName, BM); // AddBitmapToImageList(BM, FDocIcons, aName);
          finally
          end;
        end;
      finally
        // BM.Free;  //not freed because it remains in the list
      end;
    except
      // Handle error if the resource is not found
    end;
  end;

begin

  try

    // Load ImageList1
    AddIcon('pdf', 'IMG_PDF_PNG');
    AddIcon('doc', 'IMG_DOC_PNG');
    AddIcon('image', 'IMG_IMAGE_PNG');
    AddIcon('audio', 'IMG_AUDIO_PNG');
    AddIcon('video', 'IMG_VIDEO_PNG');
    AddIcon('unknown', 'IMG_UNKNOWN_PNG');
    // LoadImg('IMG_UNKNOWN_PNG', FImageList1);

  finally
  end;
end;

procedure TChatBubble.Loaded;
begin
  inherited;
  if FAutoSize or FIsCollapsed then
    UpdateAndNotifyRequiredHeight;
end;

procedure TChatBubble.LoadFromJsonObject(AJsonObject: TJSONObject);
var
  LText: string;
  LMediaFiles: TAiMediaFiles;
  LMediaArray: TJSONArray;
  LMediaValue: TJSONValue;
  LNewMediaFile: TAiMediaFile;
  LOrdValue: Integer;
begin
  // 1. Read simple properties of the bubble
  AJsonObject.TryGetValue<string>('username', FUserName);
  AJsonObject.TryGetValue<string>('title', FTitle);
  AJsonObject.TryGetValue<string>('timestamp', FTimestamp);
  if AJsonObject.TryGetValue<Integer>('tailPosition', LOrdValue) then
    FTailPosition := TChatBubbleTailPosition(LOrdValue);
  AJsonObject.TryGetValue<TAlphaColor>('bubbleColor', FBubbleColor);
  AJsonObject.TryGetValue<Integer>('imageIndex', FImageIndex);

  // 2. Deserialize text and media files
  AJsonObject.TryGetValue<string>('text', LText);

  LMediaFiles := TAiMediaFiles.Create;
  try
    if AJsonObject.TryGetValue<TJSONArray>('mediaFiles', LMediaArray) then
    begin
      for LMediaValue in LMediaArray do
      begin
        if LMediaValue is TJSONObject then
        begin
          LNewMediaFile := TAiMediaFile.Create; // Use the default constructor
          try
            // Here is the other part of the magic: TAiMediaFile loads from the JSON
            LNewMediaFile.LoadFromJsonObject(LMediaValue as TJSONObject);
            LMediaFiles.Add(LNewMediaFile);
          except
            LNewMediaFile.Free;
            raise;
          end;
        end;
      end;
    end;

    // 3. We use AddContent to build the visual content with the deserialized data.
    // This reuses all your UI logic, it is the correct way to do it!
    AddContent(LText, LMediaFiles);

  finally
    // AddContent clones the media files thanks to our robust `Assign`,
    // so we can safely free our temporary list.
    LMediaFiles.Free;
  end;
end;

function TChatBubble.AddBitmapToImageList(ABitmap: TBitMap; ImageList: TImageList; const ItemName: string): Integer;
var
  SourceItem: TSourceItem;
  DestinationItem: TDestinationItem;
  FinalName: string;
begin
  Result := -1;

  if not Assigned(ABitmap) or not Assigned(ImageList) then
    Exit;

  try
    // Generate name if not provided
    if ItemName = '' then
      FinalName := 'Item_' + IntToStr(ImageList.Source.Count)
    else
      FinalName := ItemName;

    // Add the image to the ImageList Source
    SourceItem := TSourceItem(ImageList.Source.Add);
    SourceItem.MultiResBitmap.Add;
    SourceItem.MultiResBitmap.Items[0].Bitmap.Assign(ABitmap);
    SourceItem.Name := FinalName;

    // Add a destination item that maps to this source
    DestinationItem := TDestinationItem(ImageList.Destination.Add);
    DestinationItem.Layers.Add;
    DestinationItem.Layers[0].SourceRect.Rect := RectF(0, 0, ABitmap.Width, ABitmap.Height);
    DestinationItem.Layers[0].Name := FinalName;
    // DestinationItem.Name := FinalName + '_Dest';

    // Return the index of the added item
    Result := ImageList.Source.Count - 1;

  except
    on E: Exception do
    begin
      // ShowMessage('Error adding bitmap to ImageList: ' + E.Message);
      Result := -1;
    end;
  end;
end;

function TChatBubble.LoadImageFromResource(ABitmap: TBitMap; const ResourceName: string): Boolean;
var
  ResourceStream: TResourceStream;
begin
  Result := False;
  try
    ResourceStream := TResourceStream.Create(HInstance, ResourceName, RT_RCDATA);
    try
      if ResourceStream.Size > 0 then
      begin
        ABitmap.LoadFromStream(ResourceStream);
        Result := True;
      end;
    finally
      ResourceStream.Free;
    end;
  except
    // Any exception (including EResNotFound) is handled silently
    Result := False;
  end;

  // If it could not be loaded, create a blank bitmap
  if not Result then
  begin
    ABitmap.SetSize(32, 32); // Default size, you can adjust it
    ABitmap.Clear(TAlphaColorRec.Null); // Transparent
  end;
end;

procedure TChatBubble.AddContent(const AText: string; AMediaFiles: TAiMediaFiles);
var
  LMediaFile: TAiMediaFile;
  NewMediaFile: TAiMediaFile;
  LContentControl: TControl;
  LMemo: TMemo;
begin
  // 1. Clear all previous content (visual and data)
  ClearContentControls;
  FMediaFiles.Clear;

  // 2. --- FIRST: PROCESS AND ADD ALL MEDIA FILES ---
  if Assigned(AMediaFiles) then
  begin
    for LMediaFile in AMediaFiles do
    begin
      // We clone the media file so the bubble owns it
      NewMediaFile := TAiMediaFile.Create;
      try
        NewMediaFile.Assign(LMediaFile);
        FMediaFiles.Add(NewMediaFile);

        // We create the visual view for the cloned file
        LContentControl := nil;
        if NewMediaFile.FileCategory = Tfc_Image then
        begin
          LContentControl := CreateImageView(NewMediaFile);
        end;

        if not Assigned(LContentControl) then
          LContentControl := CreateDocumentView(NewMediaFile);

        // We add the file view to the layout
        if Assigned(LContentControl) then
          LContentControl.Parent := FContentLayout;

      except
        NewMediaFile.Free;
        raise;
      end;
    end;
  end;

  // 3. --- SECOND: ADD THE TEXT AT THE END OF EVERYTHING ---
  if not AText.IsEmpty then
  begin
    LMemo := TMemo.Create(nil);
    LMemo.Parent := FContentLayout; // It is added as the last child
    LMemo.Align := TAlignLayout.Client;
    LMemo.WordWrap := True;
    LMemo.ReadOnly := True;
    LMemo.HitTest := True; // Changed so clicks pass to the bubble
    LMemo.ShowScrollBars := False;
    LMemo.StyledSettings := [];
    LMemo.TextSettings.Font.Assign(FContentFont);
    LMemo.TextSettings.HorzAlign := TTextAlign.Leading;
    LMemo.Text := AText;
    LMemo.Height := 50; // The height will be recalculated later
    LMemo.Margins.Top := 4;

    LMemo.StyleLookup := 'memostyle';
    LMemo.ApplyStyleLookup;
    {
      var
      Bg: TFmxObject;
      Bg := LMemo.FindStyleResource('background');

      If Bg is TActiveStyleObject then
      TActiveStyleObject(Bg).Opacity := 0;

    }

    var
    Bg := LMemo.FindStyleResource('background');

    if Bg is TActiveStyleObject then
    begin
      // CASE 1: immediate success (normal flow). We apply transparency now.
      TActiveStyleObject(Bg).Opacity := 0;
    end
    else
    begin
      // CASE 2: Fails (stream loading flow).
      // We schedule the modification to run in the next UI cycle.
      TThread.Queue(nil,
        procedure
        var
          DelayedBg: TFmxObject;
        begin
          // By the time this code runs, the memo will already be "alive" in the form.
          // We check that the control has not been destroyed in the meantime (good practice).
          LMemo.StyleLookup := 'memostyle';
          LMemo.ApplyStyleLookup;

          if Assigned(LMemo) and not (csDestroying in LMemo.ComponentState) then
          begin
            DelayedBg := LMemo.FindStyleResource('background');
            if DelayedBg is TActiveStyleObject then
              TActiveStyleObject(DelayedBg).Opacity := 0;
          end;
        end);
    end;
  end;
end;

{
procedure TChatBubble.AppendText(const ATextFragment: string);
var
  LMemo: TMemo;
begin
  // 1. Buscamos el control TMemo dentro de la burbuja.
  LMemo := FindFirstChild<TMemo>;

  // 2. If there is no TMemo, we cannot add text.
  if not Assigned(LMemo) then
    Exit;

  // Optional: For a better experience, if the memo has scroll,
  // and the user has moved it, we might not scroll to the end.
  // For now, we assume we always want to see the end.
  // LShouldScrollToEnd := (LMemo.ViewportPosition.Y >= LMemo.ContentBounds.Height - LMemo.Height - 5);

  // 3. A�adimos el nuevo fragmento de texto.
  // LMemo.Lines.Add() would add a new line. To concatenate, we use Lines.Text.
  LMemo.Lines.Text := LMemo.Lines.Text + ATextFragment;

  // If you use a Delphi version that supports it, you could use LMemo.Text instead of LMemo.Lines.Text
  // LMemo.Text := LMemo.Text + ATextFragment;

  // 4. We scroll inside the memo to show the new text if necessary
  LMemo.GoToTextEnd;

  // 5. CRUCIAL! We notify the parent (TChatList) that our content has changed
  // and that a recalculation of our size is necessary.
  // if Assigned(FOnRecalculateRequired) then
  // FOnRecalculateRequired(Self);
end;
}



procedure TChatBubble.AppendText(const ATextFragment: string);
var
  LMemo: TMemo;
  Bg: TFmxObject;
begin
  // 1. Buscamos el control TMemo dentro de la burbuja.
  LMemo := FindFirstChild<TMemo>;

  // 2. If there is no TMemo (e.g. there was only an image), WE CREATE IT NOW.
  if not Assigned(LMemo) then
  begin
    LMemo := TMemo.Create(nil);
    LMemo.Parent := FContentLayout;
    LMemo.Align := TAlignLayout.Client;
    LMemo.WordWrap := True;
    LMemo.ReadOnly := True;
    LMemo.HitTest := True;
    LMemo.ShowScrollBars := False;
    LMemo.StyledSettings := [];
    LMemo.TextSettings.Font.Assign(FContentFont);
    LMemo.TextSettings.HorzAlign := TTextAlign.Leading;
    LMemo.Margins.Top := 4;

    // Style configuration (same code as in AddContent)
    LMemo.StyleLookup := 'memostyle';
    LMemo.ApplyStyleLookup;

    Bg := LMemo.FindStyleResource('background');
    if Bg is TActiveStyleObject then
      TActiveStyleObject(Bg).Opacity := 0
    else
    begin
      TThread.Queue(nil, procedure
      var DelayedBg: TFmxObject;
      begin
        if Assigned(LMemo) and not (csDestroying in LMemo.ComponentState) then
        begin
          LMemo.StyleLookup := 'memostyle';
          LMemo.ApplyStyleLookup;
          DelayedBg := LMemo.FindStyleResource('background');
          if DelayedBg is TActiveStyleObject then
            TActiveStyleObject(DelayedBg).Opacity := 0;
        end;
      end);
    end;
  end;

  // 3. A�adimos el nuevo fragmento de texto.
  LMemo.Lines.Text := LMemo.Lines.Text + ATextFragment;

  // 4. We scroll to the end and notify changes
  LMemo.GoToTextEnd;

  // Notify the parent to recalculate size.
  // InvalidateLayout is redundant here: RecalculateSize already triggers it
  // via Self.Height := ... -> Resize -> InvalidateLayout.
  if Assigned(FOnRecalculateRequired) then
    FOnRecalculateRequired(Self);
end;


function TChatBubble.CalculateBubbleSizeForContent(const AContentSize: TSizeF): TSizeF;
var
  RequiredWidth, RequiredHeight: Single;
begin
  // --- HEIGHT CALCULATION ---
  RequiredHeight := 0;

  // 1. Add Header height if visible
  if Self.HeaderVisible then
    RequiredHeight := RequiredHeight + HEADER_HEIGHT;

  // 2. Add vertical paddings + the content height passed to us
  // RequiredHeight := RequiredHeight + Padding.Top + AContentSize.Height + Padding.Bottom;
  RequiredHeight := RequiredHeight + AContentSize.Height;

  // 3. Add icon area height if visible
  if Self.MoreOptionsVisible then
    RequiredHeight := RequiredHeight + ICON_AREA_HEIGHT
  Else
    RequiredHeight := RequiredHeight + Padding.Bottom;

  // --- WIDTH CALCULATION (You already had it, it is kept) ---
  RequiredWidth := Self.TailWidth + Padding.Left + AContentSize.Width + Padding.Right;

  Result := TSizeF.Create(RequiredWidth, RequiredHeight);
end;

procedure TChatBubble.CalculateLayout;
var
  BubbleRect, HeaderContentRect: TRectF;
  IconY: Single;
begin
  if FLayoutCalculated or (Width <= 0) or (Height <= 0) then
    Exit;

  BubbleRect := Self.LocalRect;
  if FTailPosition = tpLeft then
    BubbleRect.Left := BubbleRect.Left + FTailWidth
  else
    BubbleRect.Right := BubbleRect.Right - FTailWidth;

  if FHeaderVisible then
  begin
    FHeaderRect := TRectF.Create(BubbleRect.Left, BubbleRect.Top, BubbleRect.Right, BubbleRect.Top + HEADER_HEIGHT);
    HeaderContentRect := FHeaderRect;
    HeaderContentRect.Inflate(-HEADER_PADDING, -HEADER_PADDING);
    if FTailPosition = tpLeft then
      FAvatarRect.TopLeft := HeaderContentRect.TopLeft
    else
      FAvatarRect.TopLeft := PointF(HeaderContentRect.Right - AVATAR_SIZE, HeaderContentRect.Top);
    FAvatarRect.Width := AVATAR_SIZE;
    FAvatarRect.Height := AVATAR_SIZE;
    FAvatarRect.Offset(0, (HeaderContentRect.Height - AVATAR_SIZE) / 2);
  end
  else
  begin
    FHeaderRect := TRectF.Empty;
    FAvatarRect := TRectF.Empty;
  end;

  if FHeaderVisible then
    FContentRect.Top := FHeaderRect.Bottom + Padding.Top
  else
    FContentRect.Top := BubbleRect.Top + Padding.Top;
  FContentRect.Left := BubbleRect.Left + Padding.Left;
  FContentRect.Right := BubbleRect.Right - Padding.Right;

  if FMoreOptionsVisible then
  begin
    IconY := BubbleRect.Bottom - ICON_PADDING - ICON_SIZE;
    FMoreOptionsRect := TRectF.Create(BubbleRect.Right - ICON_PADDING - ICON_SIZE, IconY, BubbleRect.Right - ICON_PADDING, BubbleRect.Bottom - ICON_PADDING);
    FExpandCollapseRect := TRectF.Create(FMoreOptionsRect.Left - ICON_PADDING - ICON_SIZE, IconY, FMoreOptionsRect.Left - ICON_PADDING, BubbleRect.Bottom - ICON_PADDING);
    FContentRect.Bottom := FExpandCollapseRect.Top - ICON_PADDING;
  end
  else
  begin
    FContentRect.Bottom := BubbleRect.Bottom - Padding.Bottom;
    FMoreOptionsRect := TRectF.Empty;
    FExpandCollapseRect := TRectF.Empty;
  end;

  FLayoutCalculated := True;
  UpdateScaledAvatar;
end;

class function TChatBubble.CalculateMemoSize(const AMemo: TMemo; AMaxWidth: Single): TSizeF;
begin
  // WE NO LONGER NEED TTextLayout. The TMemo can do it by itself.

  // 1. Make sure the TMemo has the width with which we want to measure.
  // Although RecalculateSize already does it, this is a double safety.
  if Abs(AMemo.Width - AMaxWidth) > 1 then
    AMemo.Width := AMaxWidth;

  // 2. Let the TMemo calculate its content. ContentBounds.Height will give us the
  // exact height of the text with WordWrap applied.
  // We add the internal TMemo paddings for the total size.
  var
  LHeight := AMemo.ContentBounds.Height + AMemo.Padding.Top + AMemo.Padding.Bottom;

  // 3. We return the size. For width, we use AMaxWidth for consistency.
  Result := TSizeF.Create(AMaxWidth, LHeight);
end;

class function TChatBubble.CalculateTextSize(AText: TText): TSizeF;
var
  Layout: TTextLayout;
begin
  Layout := TTextLayoutManager.DefaultTextLayout.Create;
  try
    Layout.BeginUpdate;
    try
      Layout.Text := AText.Text;
      Layout.Font.Assign(AText.Font);
      Layout.Color := AText.Color;
      Layout.WordWrap := AText.WordWrap;
      Layout.HorizontalAlign := AText.HorzTextAlign;
      Layout.VerticalAlign := AText.VertTextAlign;
      if AText.Width > 0 then
        Layout.MaxSize := TPointF.Create(AText.Width, 9999999)
      else
        Layout.MaxSize := TPointF.Create(200, 200);
    finally
      Layout.EndUpdate;
    end;
    Result := TSizeF.Create(Layout.TextRect.Width, Layout.TextRect.Height + 20);
  finally
    Layout.Free;
  end;
end;

procedure TChatBubble.ClearContentControls;
begin
  while FContentLayout.ChildrenCount > 0 do
    FContentLayout.Children[0].Free;
end;

function TChatBubble.CalculateRequiredHeightForAutoSize: Single;
var
  LContentSize: TSizeF;
  HeaderHeight, IconsHeight: Single;
begin
  LContentSize := TSizeF.Create(0, 0);
  // if Assigned(FOnCalculateContentSize) then
  // FOnCalculateContentSize(Self, LContentSize);

  HeaderHeight := 0;
  if FHeaderVisible then
    HeaderHeight := HEADER_HEIGHT;

  IconsHeight := 0;
  if FMoreOptionsVisible then
    IconsHeight := ICON_SIZE + (ICON_PADDING * 2);

  Result := HeaderHeight + Padding.Top + LContentSize.Height + Padding.Bottom + IconsHeight;
end;

procedure TChatBubble.DoContentMouseEnter(Sender: TObject);
begin
  Self.Cursor := crHandPoint;
end;

procedure TChatBubble.DoContentMouseLeave(Sender: TObject);
begin
  Self.Cursor := crDefault;
end;

procedure TChatBubble.DoMediaFileDblClick(Sender: TObject);
var
  LControl: TControl;
  LMediaFile: TAiMediaFile;
begin
  // We verify that Sender is a control and has a TagObject
  if (Sender is TControl) then
  begin
    LControl := Sender as TControl;
    if (LControl.TagObject is TAiMediaFile) then
    begin
      // We retrieve the TAiMediaFile object we associated earlier
      LMediaFile := LControl.TagObject as TAiMediaFile;

      // We fire our own event to notify the outside (TChatList)
      if Assigned(FOnMediaFileDblClick) then
        FOnMediaFileDblClick(Self, LMediaFile);
    end;
  end;
end;

procedure TChatBubble.DoRealign;
begin
  UpdatePaddings;
  InvalidateLayout;
  inherited;
end;

function TChatBubble.FindFirstChild<T>: T;
var
  i: Integer;
  Child: TFmxObject;
begin
  Result := nil;

  // First, we check whether FContentLayout itself is of the searched type.
  // It is unlikely for TMemo/TImage, but it is a complete check.
  if FContentLayout is T then
  begin
    Result := T(FContentLayout);
    Exit;
  end;

  // If not, we search inside FContentLayout's children.
  // This is the key part of the fix.
  if Assigned(FContentLayout) then
  begin
    for i := 0 to FContentLayout.ChildrenCount - 1 do
    begin
      Child := FContentLayout.Children[i];
      if Child is T then
      begin
        Result := T(Child);
        Exit; // We found the first one, we exit.
      end;
    end;
  end;
end;

procedure TChatBubble.FontChanged(Sender: TObject);
begin
  Repaint;
end;

procedure TChatBubble.HandleMouseDownOnAttachment(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  LControl: TControl;
  LMediaFile: TAiMediaFile;
  LScreenPos: TPointF;
begin
  if (Button = TMouseButton.mbRight) and Assigned(FOnAttachmentContextPopup) then
  begin
    LControl := Sender as TControl;
    if (LControl.TagObject is TAiMediaFile) then
    begin
      LMediaFile := LControl.TagObject as TAiMediaFile;

      // We convert the coordinates to screen
      {$IF CompilerVersion >= 35}
      LScreenPos := LControl.LocalToScreen(PointF(X, Y));
      {$ELSE}
      // In Delphi 10.4.2, LocalToScreen is protected, we use LocalToAbsolute + Scene
      LScreenPos := LControl.LocalToAbsolute(PointF(X, Y));
      if (LControl.Root <> nil) and (LControl.Root.GetObject is TCommonCustomForm) then
        LScreenPos := TCommonCustomForm(LControl.Root.GetObject).ClientToScreen(LScreenPos);
      {$ENDIF}

      // We fire the event toward the parent (TChatList)
      FOnAttachmentContextPopup(Self, LMediaFile, LScreenPos);
    end;
  end;
end;

function TChatBubble.HitTest(const APoint: TPointF): TChatBubblePart;
begin
  Result := bpNone;
  if not Visible then
    Exit;
  CalculateLayout;
  if FExpandCollapseRect.Contains(APoint) then
    Exit(bpExpandCollapse);
  if FMoreOptionsVisible and FMoreOptionsRect.Contains(APoint) then
    Exit(bpMoreOptions);
  if FHeaderVisible and FAvatarRect.Contains(APoint) then
    Exit(bpAvatar);
  if FHeaderVisible and FHeaderRect.Contains(APoint) then
    Exit(bpHeader);
  Result := bpBackground;
end;

procedure TChatBubble.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    FDownPart := HitTest(TPointF.Create(X, Y));
  end;
end;

procedure TChatBubble.MouseMove(Shift: TShiftState; X, Y: Single);
var
  CurrentHotPart: TChatBubblePart;
begin
  inherited;
  CurrentHotPart := HitTest(TPointF.Create(X, Y));
  if FHotPart <> CurrentHotPart then
  begin
    FHotPart := CurrentHotPart;
    Repaint;
  end;
  case CurrentHotPart of
    bpAvatar, bpExpandCollapse, bpMoreOptions:
      Cursor := crHandPoint;
  else
    Cursor := crDefault;
  end;
end;

procedure TChatBubble.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if (Button = TMouseButton.mbLeft) and (FDownPart <> bpNone) then
  begin
    if FDownPart = HitTest(TPointF.Create(X, Y)) then
    begin
      case FDownPart of
        bpAvatar:
          if Assigned(FOnAvatarClick) then
            FOnAvatarClick(Self);
        bpExpandCollapse:
          begin
            Self.IsCollapsed := not Self.IsCollapsed;
            if Assigned(FOnExpandCollapseClick) then
              FOnExpandCollapseClick(Self);
          end;
        bpMoreOptions:
          if Assigned(FOnMoreOptionsClick) then
            FOnMoreOptionsClick(Self);
      end;
    end;
  end;
  FDownPart := bpNone;
end;

procedure TChatBubble.ConfigureGradientToLighterColor;
var
  LighterColor: TAlphaColor;
begin
  LighterColor := LightenColor(FBubbleColor, LightenFactor);
  if FTailPosition = tpLeft then
  begin
    FGradientBrush.Gradient.Color := FBubbleColor;
    FGradientBrush.Gradient.Color1 := LighterColor;
    FGradientBrush.Gradient.StartPosition.Point := PointF(0, 0.5);
    FGradientBrush.Gradient.StopPosition.Point := PointF(1, 0.5);
  end
  else
  begin
    FGradientBrush.Gradient.Color := FBubbleColor;
    FGradientBrush.Gradient.Color1 := LighterColor;
    FGradientBrush.Gradient.StartPosition.Point := PointF(1, 0.5);
    FGradientBrush.Gradient.StopPosition.Point := PointF(0, 0.5);
  end;
end;

procedure TChatBubble.ContentSizeCalculator(AContentWidth: Single; var AContentSize: TSizeF);
var
  i: Integer;
  LControl: TControl;
  LTotalHeight: Single;
  LMemo: TMemo;
  LastControl: TObject;
  MemoSize: TSizeF;
  LoopLimit: Integer;
begin
  LTotalHeight := 0;

  if FContentLayout.ChildrenCount = 0 then
  begin
    AContentSize := TSizeF.Create(AContentWidth, 0);
    Exit;
  end;

  LastControl := FContentLayout.Children[FContentLayout.ChildrenCount - 1];
  if (LastControl is TMemo) then
    LoopLimit := FContentLayout.ChildrenCount - 2
  else
  begin
    LoopLimit := FContentLayout.ChildrenCount - 1;
    LastControl := nil;
  end;

  for i := 0 to LoopLimit do
  begin
    LControl := FContentLayout.Children[i] as TControl;
    LTotalHeight := LTotalHeight + LControl.Height + LControl.Margins.Top + LControl.Margins.Bottom;
  end;

  if Assigned(LastControl) then
  begin
    LMemo := LastControl as TMemo;
    MemoSize := TChatBubble.CalculateMemoSize(LMemo, AContentWidth);

    LMemo.Height := Ceil(MemoSize.Height)+8;
    LTotalHeight := LTotalHeight + LMemo.Height + LMemo.Margins.Top + LMemo.Margins.Bottom+10;
  end;

  AContentSize.Width := FContentLayout.Width;
  AContentSize.Height := LTotalHeight;
end;

procedure TChatBubble.Paint;
var
  LPath: TPathData;
  LHeaderColor, LTitleColor, IconColor: TAlphaColor;
  IconCenter: TPointF;
  TitleRect, TimestampRect, AvailableHeaderTextRect: TRectF;
begin
  CalculateLayout;
  LPath := TPathData.Create;
  try
    UpdateBubblePathData(LPath);
    ConfigureGradientToLighterColor;
    Canvas.FillPath(LPath, 1, FGradientBrush);
    FStrokeBrush.Color := DarkenColor(FBubbleColor, 0.8);
    Canvas.DrawPath(LPath, 1, FStrokeBrush);
  finally
    LPath.Free;
  end;

  if FHeaderVisible then
  begin
    LHeaderColor := DarkenColor(FBubbleColor, FHeaderColorFactor);
    Canvas.Fill.Color := LHeaderColor;
    Canvas.FillRect(FHeaderRect, FCornerRadius, FCornerRadius, [TCorner.TopLeft, TCorner.TopRight], 1);

    if Assigned(FAvatar) and not FAvatar.IsEmpty then
      Canvas.FillEllipse(FAvatarRect, 1.0, FAvatarBrush);

    LTitleColor := DarkenColor(FBubbleColor, 0.5);
    Canvas.Fill.Color := LTitleColor;

    if FTailPosition = tpLeft then
      AvailableHeaderTextRect := TRectF.Create(FAvatarRect.Right + HEADER_PADDING, FHeaderRect.Top, FHeaderRect.Right - HEADER_PADDING, FHeaderRect.Bottom)
    else
      AvailableHeaderTextRect := TRectF.Create(FHeaderRect.Left + HEADER_PADDING, FHeaderRect.Top, FAvatarRect.Left - HEADER_PADDING, FHeaderRect.Bottom);

    TimestampRect := TRectF.Create(AvailableHeaderTextRect.Right - TIMESTAMP_AREA_WIDTH, AvailableHeaderTextRect.Top, AvailableHeaderTextRect.Right, AvailableHeaderTextRect.Bottom);
    TitleRect := TRectF.Create(AvailableHeaderTextRect.Left, AvailableHeaderTextRect.Top, TimestampRect.Left, AvailableHeaderTextRect.Bottom);

    Canvas.Font.Assign(FTitleFont);
    Canvas.FillText(TitleRect, FTitle, False, 1, [], TTextAlign.Leading, TTextAlign.Center);

    Canvas.Font.Assign(FTimestampFont);
    Canvas.Fill.Color := TAlphaColors.Dimgray;
    Canvas.FillText(TimestampRect, FTimestamp, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  end;

  if FMoreOptionsVisible then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Thickness := 1.5;
    IconColor := TAlphaColors.Dimgray;
    if FHotPart = bpExpandCollapse then
      IconColor := TAlphaColors.Black;
    Canvas.Stroke.Color := IconColor;
    IconCenter := FExpandCollapseRect.CenterPoint;
    if FIsCollapsed then
    begin
      Canvas.DrawLine(PointF(IconCenter.X, IconCenter.Y + 2), PointF(IconCenter.X - 4, IconCenter.Y - 2), 1);
      Canvas.DrawLine(PointF(IconCenter.X, IconCenter.Y + 2), PointF(IconCenter.X + 4, IconCenter.Y - 2), 1);
    end
    else
    begin
      Canvas.DrawLine(PointF(IconCenter.X, IconCenter.Y - 2), PointF(IconCenter.X - 4, IconCenter.Y + 2), 1);
      Canvas.DrawLine(PointF(IconCenter.X, IconCenter.Y - 2), PointF(IconCenter.X + 4, IconCenter.Y + 2), 1);
    end;
    IconColor := TAlphaColors.Dimgray;
    if FHotPart = bpMoreOptions then
      IconColor := TAlphaColors.Black;
    Canvas.Fill.Color := IconColor;
    IconCenter := FMoreOptionsRect.CenterPoint;
    Canvas.FillEllipse(RectF(IconCenter.X - 5 - 1.5, IconCenter.Y - 1.5, IconCenter.X - 5 + 1.5, IconCenter.Y + 1.5), 1);
    Canvas.FillEllipse(RectF(IconCenter.X - 1.5, IconCenter.Y - 1.5, IconCenter.X + 1.5, IconCenter.Y + 1.5), 1);
    Canvas.FillEllipse(RectF(IconCenter.X + 5 - 1.5, IconCenter.Y - 1.5, IconCenter.X + 5 + 1.5, IconCenter.Y + 1.5), 1);
  end;
end;

procedure TChatBubble.RecalculateSize(AMaxWidth: Single);
var
  LContentSize: TSizeF;
  LRequiredSize: TSizeF;
  i: Integer;
  LControl: TControl;
  LMemo: TMemo;
  MaxContentWidth: Single;
begin
  // 1. Calculate the content width.
  MaxContentWidth := AMaxWidth - Self.TailWidth - (Padding.Left + Padding.Right);
  if MaxContentWidth < 0 then
    MaxContentWidth := 0;

  // 2. IMPOSE the width on the layout and the TMemo.
  FContentLayout.Width := MaxContentWidth;
  FContentLayout.BeginUpdate;
  try
    for i := 0 to FContentLayout.ChildrenCount - 1 do
    begin
      LControl := FContentLayout.Children[i] as TControl;
      if LControl is TMemo then
      begin
        LMemo := LControl as TMemo;
        LMemo.Width := MaxContentWidth;
      end;
    end;
  finally
    FContentLayout.EndUpdate;
  end;

  // 3. --- HERE IS THE OTHER KEY CHANGE! ---
  // We call the new version of ContentSizeCalculator, passing it
  // the MaxContentWidth value that we know is correct.
  ContentSizeCalculator(MaxContentWidth, LContentSize);

  // 4. We calculate the final size of the bubble.
  LRequiredSize := CalculateBubbleSizeForContent(LContentSize);

  // 5. We apply the size.
  Self.Width := AMaxWidth;
  Self.Height := LRequiredSize.Height;
end;

procedure TChatBubble.Resize;
begin
  inherited;
  UpdatePaddings;
  InvalidateLayout;
end;

procedure TChatBubble.SetAvatar(const Value: TBitMap);
begin
  SetInternalAvatar(Value);
end;

procedure TChatBubble.SetInternalAvatar(const Value: TBitMap; AResetImageIndex: Boolean = True);
begin
  if Assigned(Value) then
    FAvatar.Assign(Value)
  else
    FAvatar.SetSize(0, 0);

  if AResetImageIndex then
    FImageIndex := -1;

  UpdateScaledAvatar;
  Repaint;
end;

procedure TChatBubble.SetAutoSize(const Value: Boolean);
begin
  if FAutoSize <> Value then
  begin
    FAutoSize := Value;
    if FAutoSize then
      UpdateAndNotifyRequiredHeight;
  end;
end;

procedure TChatBubble.SetBubbleColor(const Value: TAlphaColor);
begin
  if FBubbleColor <> Value then
  begin
    FBubbleColor := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetCollapsedHeight(const Value: Single);
begin
  if FCollapsedHeight <> Value then
  begin
    FCollapsedHeight := Value;
    if IsCollapsed then
      UpdateAndNotifyRequiredHeight;
  end;
end;

procedure TChatBubble.SetContentFont(const Value: TFont);
begin
  FContentFont.Assign(Value);
  Repaint;
end;

procedure TChatBubble.SetCornerRadius(const Value: Single);
begin
  if FCornerRadius <> Value then
  begin
    FCornerRadius := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetGradientTransparency(const Value: Single);
begin
  if FGradientTransparency <> Value then
  begin
    FGradientTransparency := Min(1.0, Max(0.0, Value));
    Repaint;
  end;
end;

procedure TChatBubble.SetHeaderColorFactor(const Value: Single);
begin
  if FHeaderColorFactor <> Value then
  begin
    FHeaderColorFactor := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetHeaderVisible(const Value: Boolean);
begin
  if FHeaderVisible <> Value then
  begin
    FHeaderVisible := Value;
    InvalidateLayout;
    UpdateStructureAndSize
  end;
end;

procedure TChatBubble.SetImageIndex(const Value: Integer);
begin
  if FImageIndex <> Value then
  begin
    FImageIndex := Value;
    UpdateAvatarFromImageList;
  end;
end;

procedure TChatBubble.SetImages(const Value: TImageList);
begin
  if FImages <> Value then
  begin
    FImages := Value;
    UpdateAvatarFromImageList;
  end;
end;

procedure TChatBubble.SetIsCollapsed(const Value: Boolean);
begin
  if FIsCollapsed <> Value then
  begin
    if Value and not FAutoSize and (Self.Height > FCollapsedHeight) then
    begin
      FOriginalHeight := Self.Height;
    end;
    FIsCollapsed := Value;
    if not Value and not FAutoSize and (FOriginalHeight <= FCollapsedHeight) then
    begin
      FOriginalHeight := 0;
    end;
    UpdateStructureAndSize;
  end;
end;

procedure TChatBubble.SetLightenFactor(const Value: Single);
begin
  FLightenFactor := Value;
end;

procedure TChatBubble.SetMoreOptionsVisible(const Value: Boolean);
begin
  if FMoreOptionsVisible <> Value then
  begin
    FMoreOptionsVisible := Value;
    InvalidateLayout;
    UpdateStructureAndSize;
  end;
end;

procedure TChatBubble.SetSizeByContent(const AContentSize: TSizeF);
var
  LRequiredSize: TSizeF;
begin
  // 1. Calculate the total required size for the bubble using the existing helper function.
  // This function already considers whether the header is visible, the option icons,
  // the margins and the tail width (TailWidth).
  LRequiredSize := CalculateBubbleSizeForContent(AContentSize);

  // 2. Assign the new size (width and height) to the component.
  // When the size changes, the OnResize event will be fired, which in turn
  // calls InvalidateLayout, forcing the component to recalculate its internal areas
  // and redraw itself correctly.
  Self.Height := LRequiredSize.Height;
  Self.Width := LRequiredSize.Width - 30;
end;

procedure TChatBubble.UpdateAndNotifyRequiredHeight;
var
  LRequiredHeight: Single;
begin
  if FIsCollapsed then
  begin
    LRequiredHeight := FCollapsedHeight;
  end
  else
  begin
    if FAutoSize then
    begin
      LRequiredHeight := CalculateRequiredHeightForAutoSize;
    end
    else
    begin
      if FOriginalHeight > FCollapsedHeight then
        LRequiredHeight := FOriginalHeight
      else
        LRequiredHeight := CalculateRequiredHeightForAutoSize;
    end;
  end;

  if Assigned(FOnRequiredSizeCalculated) then
  begin
    FOnRequiredSizeCalculated(Self, LRequiredHeight);
  end
  else if Abs(Self.Height - LRequiredHeight) > 1 then
  begin
    Self.Height := LRequiredHeight;
  end;
end;

procedure TChatBubble.SetTailSharpness(const Value: Single);
begin
  If (Value >= 0) and (Value <= 1) then
    FTailSharpness := Value;
end;

procedure TChatBubble.SetTailCurveBias(const Value: Single);
begin
  If (Value >= 0) and (Value <= 1) then
    FTailCurveBias := Value;
end;

procedure TChatBubble.SetTailHeight(const Value: Single);
begin
  if FTailHeight <> Value then
  begin
    FTailHeight := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetTailOffsetPercent(const Value: Single);
var
  ClampedValue: Single;
begin
  ClampedValue := Min(1.0, Max(0.0, Value));
  if FTailOffsetPercent <> ClampedValue then
  begin
    FTailOffsetPercent := ClampedValue;
    Repaint;
  end;
end;

procedure TChatBubble.SetTailPosition(const Value: TChatBubbleTailPosition);
begin
  if FTailPosition <> Value then
  begin
    FTailPosition := Value;
    InvalidateLayout;
    DoRealign;
  end;
end;

procedure TChatBubble.SetTailStyle(const Value: TTailStyle);
begin
  FTailStyle := Value;
  Repaint;
end;

procedure TChatBubble.SetTailWidth(const Value: Single);
begin
  if FTailWidth <> Value then
  begin
    FTailWidth := Value;
    InvalidateLayout;
    UpdateStructureAndSize;
  end;
end;

procedure TChatBubble.SetTimestamp(const Value: string);
begin
  if FTimestamp <> Value then
  begin
    FTimestamp := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetTimestampFont(const Value: TFont);
begin
  FTimestampFont.Assign(Value);
end;

procedure TChatBubble.SetTitle(const Value: string);
begin
  if FTitle <> Value then
  begin
    FTitle := Value;
    Repaint;
  end;
end;

procedure TChatBubble.SetTitleFont(const Value: TFont);
begin
  FTitleFont.Assign(Value);
end;

procedure TChatBubble.SetUserName(const Value: String);
begin
  FUserName := Value;
end;

function TChatBubble.ToJsonObject: TJSONObject;
var
  LMemo: TMemo;
  LText: string;
  LMediaArray: TJSONArray;
  LMediaFile: TAiMediaFile;
begin
  Result := TJSONObject.Create;

  // 1. Save simple properties of the bubble
  Result.AddPair('username', FUserName);
  Result.AddPair('title', FTitle);
  Result.AddPair('timestamp', FTimestamp);
  Result.AddPair('tailPosition', Ord(FTailPosition));
  Result.AddPair('bubbleColor', FBubbleColor);
  Result.AddPair('imageIndex', FImageIndex);

  // 2. Save the text (if it exists)
  LMemo := FindFirstChild<TMemo>;
  if Assigned(LMemo) then
    LText := LMemo.Lines.Text
  else
    LText := '';
  Result.AddPair('text', LText);

  // 3. Save the attachments (delegating to TAiMediaFile.ToJsonObject)
  LMediaArray := TJSONArray.Create;
  try
    for LMediaFile in FMediaFiles do
    begin
      // Here is the magic: TAiMediaFile knows how to convert itself to JSON
      LMediaArray.AddElement(LMediaFile.ToJsonObject);
    end;
    Result.AddPair('mediaFiles', LMediaArray);
  except
    LMediaArray.Free; // Free in case of error
    raise;
  end;
end;

procedure TChatBubble.UpdateAvatarFromImageList;
var
  LTempBitmap: TBitMap;
  Sz: TSizeF;
begin
  if (FImages <> nil) and (FImageIndex >= 0) and (FImageIndex < FImages.Count) then
  begin
    try
      Sz := TSizeF.Create(AVATAR_SIZE, AVATAR_SIZE);
      if (Sz.Width > 0) and (Sz.Height > 0) then
      begin
        LTempBitmap := FImages.Bitmap(Sz, FImageIndex);
        if Assigned(LTempBitmap) then
        begin
          SetInternalAvatar(LTempBitmap, False);
        end;
      end
      else
      begin
        SetInternalAvatar(nil, False);
      end;
    finally
      // LTempBitmap.Free;
    end;
  end
  else
  begin
    if FImageIndex = -1 then
      SetInternalAvatar(nil, False);
  end;
end;

procedure TChatBubble.UpdateBubblePathData(APath: TPathData);
begin
  case TailStyle of
    tsSimple:
      UpdateBubblePathDatatsSimple(APath);
    tsOrganic:
      UpdateBubblePathDatatsOrganic(APath);
    tsComic:
      UpdateBubblePathDatatsComic(APath);
    tsSharp:
      UpdateBubblePathDatatsSharp(APath);
  end;
end;

procedure TChatBubble.UpdateBubblePathDatatsSimple(APath: TPathData);
var
  R: TRectF;
  TailY, TotalHeightForTail: Single;
begin
  APath.Clear;
  R := Self.LocalRect;

  if FTailPosition = tpLeft then
    R.Left := R.Left + FTailWidth
  else
    R.Right := R.Right - FTailWidth;

  if (R.Width < (FCornerRadius * 2)) or (R.Height < (FCornerRadius * 2)) then
    Exit;

  TotalHeightForTail := R.Height - (FCornerRadius * 2);
  TailY := R.Top + FCornerRadius + (TotalHeightForTail * FTailOffsetPercent);

  APath.MoveTo(PointF(R.Left + FCornerRadius, R.Top));
  APath.LineTo(PointF(R.Right - FCornerRadius, R.Top));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 270, 90);

  if FTailPosition = tpRight then
  begin
    APath.LineTo(PointF(R.Right, TailY - (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Right + FTailWidth, TailY), PointF(R.Right, TailY + (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Right, R.Bottom - FCornerRadius));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 0, 90);
  APath.LineTo(PointF(R.Left + FCornerRadius, R.Bottom));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 90, 90);

  if FTailPosition = tpLeft then
  begin
    APath.LineTo(PointF(R.Left, TailY + (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Left - FTailWidth, TailY), PointF(R.Left, TailY - (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Left, R.Top + FCornerRadius));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 180, 90);

  APath.ClosePath;
end;

procedure TChatBubble.UpdatePaddings;
var
  LCalculatedPadding: TRectF;
begin
  if FTailPosition = tpLeft then
  begin
    LCalculatedPadding.Left := FTailWidth + CONTENT_MARGIN_LEFT;
    LCalculatedPadding.Right := CONTENT_MARGIN_RIGHT;
  end
  else
  begin
    LCalculatedPadding.Left := CONTENT_MARGIN_LEFT;
    LCalculatedPadding.Right := FTailWidth + CONTENT_MARGIN_RIGHT;
  end;

  if FHeaderVisible then
    LCalculatedPadding.Top := HEADER_HEIGHT + CONTENT_MARGIN_TOP
  else
    LCalculatedPadding.Top := CONTENT_MARGIN_TOP;

  if FMoreOptionsVisible then
    LCalculatedPadding.Bottom := ICON_AREA_HEIGHT + CONTENT_MARGIN_BOTTOM
  else
    LCalculatedPadding.Bottom := CONTENT_MARGIN_BOTTOM;

  if not Padding.Rect.EqualsTo(LCalculatedPadding) then
  begin
    Padding.Rect := LCalculatedPadding;
  end;
end;

procedure TChatBubble.UpdateBubblePathDatatsOrganic(APath: TPathData);
var
  R: TRectF;
  TailY, TotalHeightForTail: Single;
const
  TailCurveIntensity = 0.7;
begin
  APath.Clear;
  R := Self.LocalRect;

  if FTailPosition = tpLeft then
    R.Left := R.Left + FTailWidth
  else
    R.Right := R.Right - FTailWidth;

  if (R.Width < (FCornerRadius * 2)) or (R.Height < (FCornerRadius * 2)) then
    Exit;

  TotalHeightForTail := R.Height - (FCornerRadius * 2);
  TailY := R.Top + FCornerRadius + (TotalHeightForTail * FTailOffsetPercent);

  APath.MoveTo(PointF(R.Left + FCornerRadius, R.Top));
  APath.LineTo(PointF(R.Right - FCornerRadius, R.Top));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 270, 90);

  if FTailPosition = tpRight then
  begin
    APath.LineTo(PointF(R.Right, TailY - (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Right + (FTailWidth * TailCurveIntensity), TailY), PointF(R.Right + FTailWidth, TailY));
    APath.QuadCurveTo(PointF(R.Right + (FTailWidth * TailCurveIntensity), TailY), PointF(R.Right, TailY + (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Right, R.Bottom - FCornerRadius));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 0, 90);
  APath.LineTo(PointF(R.Left + FCornerRadius, R.Bottom));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 90, 90);

  if FTailPosition = tpLeft then
  begin
    APath.LineTo(PointF(R.Left, TailY + (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Left - (FTailWidth * TailCurveIntensity), TailY), PointF(R.Left - FTailWidth, TailY));
    APath.QuadCurveTo(PointF(R.Left - (FTailWidth * TailCurveIntensity), TailY), PointF(R.Left, TailY - (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Left, R.Top + FCornerRadius));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 180, 90);

  APath.ClosePath;
end;

procedure TChatBubble.UpdateBubblePathDatatsComic(APath: TPathData);
var
  R: TRectF;
  TailY, TotalHeightForTail: Single;
const
  TailConcavity = 0.3;
begin
  APath.Clear;
  R := Self.LocalRect;

  if FTailPosition = tpLeft then
    R.Left := R.Left + FTailWidth
  else
    R.Right := R.Right - FTailWidth;

  if (R.Width < (FCornerRadius * 2)) or (R.Height < (FCornerRadius * 2)) then
    Exit;

  TotalHeightForTail := R.Height - (FCornerRadius * 2);
  TailY := R.Top + FCornerRadius + (TotalHeightForTail * FTailOffsetPercent);

  APath.MoveTo(PointF(R.Left + FCornerRadius, R.Top));
  APath.LineTo(PointF(R.Right - FCornerRadius, R.Top));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 270, 90);

  if FTailPosition = tpRight then
  begin
    APath.LineTo(PointF(R.Right, TailY - (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Right + (FTailWidth / 2) + (FTailWidth * TailConcavity), TailY - (FTailHeight / 4)), PointF(R.Right + FTailWidth, TailY));
    APath.QuadCurveTo(PointF(R.Right + (FTailWidth / 2) + (FTailWidth * TailConcavity), TailY + (FTailHeight / 4)), PointF(R.Right, TailY + (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Right, R.Bottom - FCornerRadius));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 0, 90);
  APath.LineTo(PointF(R.Left + FCornerRadius, R.Bottom));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 90, 90);

  if FTailPosition = tpLeft then
  begin
    APath.LineTo(PointF(R.Left, TailY + (FTailHeight / 2)));
    APath.QuadCurveTo(PointF(R.Left - (FTailWidth / 2) - (FTailWidth * TailConcavity), TailY + (FTailHeight / 4)), PointF(R.Left - FTailWidth, TailY));
    APath.QuadCurveTo(PointF(R.Left - (FTailWidth / 2) - (FTailWidth * TailConcavity), TailY - (FTailHeight / 4)), PointF(R.Left, TailY - (FTailHeight / 2)));
  end;

  APath.LineTo(PointF(R.Left, R.Top + FCornerRadius));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 180, 90);

  APath.ClosePath;
end;

procedure TChatBubble.UpdateBubblePathDatatsSharp(APath: TPathData);
var
  R: TRectF;
  TailY, TotalHeightForTail: Single;
  TopBase, BottomBase, CP1, CP2, TailTip: TPointF;
  ArcYOffset: Single;
begin
  APath.Clear;
  R := Self.LocalRect;
  if FTailPosition = tpLeft then
    R.Left := R.Left + FTailWidth
  else
    R.Right := R.Right - FTailWidth;
  if (R.Width < (FCornerRadius * 2)) or (R.Height < (FCornerRadius * 2)) then
    Exit;
  TotalHeightForTail := R.Height - (FCornerRadius * 2);
  TailY := R.Top + FCornerRadius + (TotalHeightForTail * FTailOffsetPercent);

  APath.MoveTo(PointF(R.Left + FCornerRadius, R.Top));
  APath.LineTo(PointF(R.Right - FCornerRadius, R.Top));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 270, 90);

  if FTailPosition = tpRight then
  begin
    TopBase := PointF(R.Right, TailY - (FTailHeight / 2));
    BottomBase := PointF(R.Right, TailY + (FTailHeight / 2));
    APath.LineTo(TopBase);
    ArcYOffset := FTailHeight * TailCurveBias;
    TailTip := PointF(R.Right + FTailWidth, TailY + ArcYOffset);
    CP1.X := R.Right + (FTailWidth * TailSharpness * 0.6);
    CP1.Y := TopBase.Y + (ArcYOffset * 0.3);
    APath.CurveTo(CP1, PointF(TailTip.X - (FTailWidth * (1 - TailSharpness) * 0.3), TailTip.Y), TailTip);
    CP2.X := R.Right + (FTailWidth * TailSharpness * 0.6);
    CP2.Y := BottomBase.Y + (ArcYOffset * 0.3);
    APath.CurveTo(PointF(TailTip.X - (FTailWidth * (1 - TailSharpness) * 0.3), TailTip.Y), CP2, BottomBase);
  end;

  APath.LineTo(PointF(R.Right, R.Bottom - FCornerRadius));
  APath.AddArc(PointF(R.Right - FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 0, 90);
  APath.LineTo(PointF(R.Left + FCornerRadius, R.Bottom));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Bottom - FCornerRadius), PointF(FCornerRadius, FCornerRadius), 90, 90);

  if FTailPosition = tpLeft then
  begin
    BottomBase := PointF(R.Left, TailY + (FTailHeight / 2));
    TopBase := PointF(R.Left, TailY - (FTailHeight / 2));
    APath.LineTo(BottomBase);
    ArcYOffset := FTailHeight * TailCurveBias;
    TailTip := PointF(R.Left - FTailWidth, TailY + ArcYOffset);
    CP1.X := R.Left - (FTailWidth * TailSharpness * 0.6);
    CP1.Y := BottomBase.Y + (ArcYOffset * 0.3);
    APath.CurveTo(CP1, PointF(TailTip.X + (FTailWidth * (1 - TailSharpness) * 0.3), TailTip.Y), TailTip);
    CP2.X := R.Left - (FTailWidth * TailSharpness * 0.6);
    CP2.Y := TopBase.Y + (ArcYOffset * 0.3);
    APath.CurveTo(PointF(TailTip.X + (FTailWidth * (1 - TailSharpness) * 0.3), TailTip.Y), CP2, TopBase);
  end;
  APath.LineTo(PointF(R.Left, R.Top + FCornerRadius));
  APath.AddArc(PointF(R.Left + FCornerRadius, R.Top + FCornerRadius), PointF(FCornerRadius, FCornerRadius), 180, 90);
  APath.ClosePath;
end;

procedure TChatBubble.UpdateScaledAvatar;
begin
  if (Assigned(FAvatar) and not FAvatar.IsEmpty) and (FAvatarRect.Width > 0) and (FAvatarRect.Height > 0) then
  begin
    FScaledAvatar.SetSize(Round(FAvatarRect.Width), Round(FAvatarRect.Height));
    FScaledAvatar.Canvas.BeginScene;
    try
      // *** CHANGE: The canvas is cleared with white to give the avatar a solid background. ***
      // This fixes problems with images that have transparency.
      FScaledAvatar.Canvas.Clear(TAlphaColors.White);
      FScaledAvatar.Canvas.DrawBitmap(FAvatar, FAvatar.BoundsF, FScaledAvatar.BoundsF, 1.0, True);
    finally
      FScaledAvatar.Canvas.EndScene;
    end;
    FAvatarBrush.Bitmap.Bitmap.Assign(FScaledAvatar);
  end
  else
  begin
    // If there is no avatar, we clear the brush so it does not show the previous one
    if Assigned(FAvatarBrush.Bitmap.Bitmap) then
      FAvatarBrush.Bitmap.Bitmap.SetSize(0, 0);
  end;
end;

procedure TChatBubble.UpdateStructureAndSize;
begin
  UpdateAndNotifyRequiredHeight;
  DoRealign;
end;

end.
