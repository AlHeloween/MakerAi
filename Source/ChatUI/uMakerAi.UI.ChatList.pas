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


unit uMakerAi.UI.ChatList;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors, System.Math,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.ScrollBox, FMX.StdCtrls, System.JSON,
  FMX.Memo, FMX.Objects, FMX.Ani, FMX.Styles.Objects, FMX.Menus,
  uMakerAi.UI.ChatBubble, uMakerAi.Core; // Make sure this unit is in your project path

{$WARN SYMBOL_DEPRECATED OFF}
type
  // Event types defined in the specification (req. 11)
  TChatListBubbleEvent = procedure(Sender: TObject; ABubble: TChatBubble) of object;
  TChatListCalcEvent = procedure(Sender: TObject; ABubble: TChatBubble; var ASize: TSizeF; var Handled: Boolean) of object;
  TChatListMediaFileEvent = procedure(Sender: TObject; const ABubble: TChatBubble; const AMediaFile: TAiMediaFile) of object;

  TChatList = class(TVertScrollBox)
  private
    FContentLayout: TFlowLayout;
    FLastBubble: TChatBubble;
    FLastUserName: string;

    // Fields for published properties
    FInboundColor: TAlphaColor;
    FOutboundColor: TAlphaColor;
    FAutoScroll: Boolean;
    FMaxBubbleWidthPercent: Single;
    FBubblePadding: TRectF;
    FBubbleMargins: TRectF;
    FDefaultWordWrap: Boolean;
    FGroupConsecutiveMessages: Boolean;

    // Fields for events
    FOnBeforeAddBubble: TChatListBubbleEvent;
    FOnBubbleAdded: TChatListBubbleEvent;
    FOnCalculateBubbleContentSize: TChatListCalcEvent;
    FOnBubbleAvatarClick: TChatListBubbleEvent;
    FOnBubbleExpandCollapseClick: TChatListBubbleEvent;
    FOnBubbleMoreOptionsClick: TChatListBubbleEvent;
    FOnMediaFileDblClick: TChatListMediaFileEvent;
    FAttachmentPopupMenu: TPopupMenu;
    FActiveMediaFile: TAiMediaFile;

    // Throttle for streaming: avoid resize+scroll for each chunk
    FLastRecalcTick: Cardinal;
    FRecalcQueued: Boolean;
    FRecalcPendingBubble: TChatBubble;

    // Setters for properties
    procedure SetInboundColor(const Value: TAlphaColor);
    procedure SetOutboundColor(const Value: TAlphaColor);
    procedure SetMaxBubbleWidthPercent(const Value: Single);
    procedure SetBubblePadding(const Value: TRectF);
    procedure SetBubbleMargins(const Value: TRectF);

    // Internal methods
    procedure UpdateContentLayoutHeight;
    function IsScrolledToBottom: Boolean;
    procedure InternalAddBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean);
    function TryAppendToLastBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean): Boolean;
    procedure CalculateAndSetBubbleSize(ABubble: TChatBubble);

    // Event handlers for forwarding (hooking)
    procedure DoBubbleAvatarClick(Sender: TObject);
    procedure DoBubbleExpandCollapseClick(Sender: TObject);
    procedure DoBubbleMoreOptionsClick(Sender: TObject);
    //procedure DoCalculateContentSize(Sender: TObject; var AContentSize: TSizeF);
    procedure DoBubbleMediaFileDblClick(Sender: TObject; const AMediaFile: TAiMediaFile);
    procedure DoAttachmentContextPopup(Sender: TObject; const AMediaFile: TAiMediaFile; const MousePos: TPointF);
    procedure DoBubbleRecalculateRequired(Sender: TObject);

    procedure SetAttachmentPopupMenu(const Value: TPopupMenu);

  protected
    procedure Loaded; override;
    procedure Resize; override;

    Procedure SetMemoBackVisible(Memo: TMemo; Value: Boolean);

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Public API (req. 2)
    // function AddBubble(const AText, AUserName: string; AInbound: Boolean = True): TChatBubble;
    function AddBubble(const AText: string; const AUserName: string; AMediaFiles: TAiMediaFiles; AInbound: Boolean = True): TChatBubble;
    function AddBubbleWithControl(AControl: TControl; const AUserName: string; AInbound: Boolean = True): TChatBubble;
    function AddMemoBubble(const AText: string; const AUserName: string; AInbound: Boolean = True; AWordWrap: Boolean = True): TChatBubble;
    function AddCustomBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean = True): TChatBubble;
    procedure RemoveBubble(ABubble: TChatBubble);
    procedure Clear;
    procedure ScrollToBottom;
    procedure SaveToStream(AStream: TStream);
    procedure LoadFromStream(AStream: TStream);

    property ContentLayout: TFlowLayout read FContentLayout;
    property ActiveMediaFile: TAiMediaFile read FActiveMediaFile;

  published
    // Important properties (req. 2)
    property InboundColor: TAlphaColor read FInboundColor write SetInboundColor default TAlphaColors.LightGray;
    property OutboundColor: TAlphaColor read FOutboundColor write SetOutboundColor default TAlphaColors.LightGreen;
    property AutoScroll: Boolean read FAutoScroll write FAutoScroll default True;
    property MaxBubbleWidthPercent: Single read FMaxBubbleWidthPercent write SetMaxBubbleWidthPercent;
    property BubblePadding: TRectF read FBubblePadding write SetBubblePadding;
    property BubbleMargins: TRectF read FBubbleMargins write SetBubbleMargins;
    property DefaultWordWrap: Boolean read FDefaultWordWrap write FDefaultWordWrap default False;
    property GroupConsecutiveMessages: Boolean read FGroupConsecutiveMessages write FGroupConsecutiveMessages default True;
    property AttachmentPopupMenu: TPopupMenu read FAttachmentPopupMenu write SetAttachmentPopupMenu;

    // Main events (req. 2 and 7)
    property OnBeforeAddBubble: TChatListBubbleEvent read FOnBeforeAddBubble write FOnBeforeAddBubble;
    property OnBubbleAdded: TChatListBubbleEvent read FOnBubbleAdded write FOnBubbleAdded;
    property OnCalculateBubbleContentSize: TChatListCalcEvent read FOnCalculateBubbleContentSize write FOnCalculateBubbleContentSize;
    property OnBubbleAvatarClick: TChatListBubbleEvent read FOnBubbleAvatarClick write FOnBubbleAvatarClick;
    property OnBubbleExpandCollapseClick: TChatListBubbleEvent read FOnBubbleExpandCollapseClick write FOnBubbleExpandCollapseClick;
    property OnBubbleMoreOptionsClick: TChatListBubbleEvent read FOnBubbleMoreOptionsClick write FOnBubbleMoreOptionsClick;
    property OnMediaFileDblClick: TChatListMediaFileEvent read FOnMediaFileDblClick write FOnMediaFileDblClick;

    // Inherited properties we want to expose
    property Align;
    property Anchors;
    property Position;
    property Size;
    property Visible;
    property Enabled;
    property OnClick;
    property OnDblClick;
  end deprecated 'Use TAIChatView (AIChat.Control.FMX)';

procedure Register;

implementation

{$R ..\Resources\uMakerAiUIIcons.res}  // package palette icons

{$WARN SYMBOL_DEPRECATED OFF}

procedure Register;
begin
  RegisterComponents('MakerAI UI', [TChatList]);
end;

const
  CHAT_FORMAT_VERSION = 1;

  { TChatList }

constructor TChatList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // 1. General architecture: TVertScrollBox with an internal TFlowLayout
  FContentLayout := TFlowLayout.Create(Self);
  FContentLayout.Parent := Self;
  FContentLayout.Stored := False;
  FContentLayout.Align := TAlignLayout.Top;
  FContentLayout.FlowDirection := TFlowDirection.LeftToRight;
  // Ensure the FlowLayout adjusts its width to the viewport
  // FContentLayout.Anchors := [TAnchorKind.akLeft, TAnchorKind.akTop, TAnchorKind.akRight];
  // FContentLayout.Width := Self.Width;

  // Property initialization by default
  FInboundColor := TAlphaColors.LightGray;
  FOutboundColor := TAlphaColors.LightGreen;
  FAutoScroll := True;
  FMaxBubbleWidthPercent := 0.8; // 80% of width
  FBubblePadding := TRectF.Create(8, 8, 8, 8);
  FBubbleMargins := TRectF.Create(5, 5, 5, 5);
  FDefaultWordWrap := True;
  FGroupConsecutiveMessages := True;
end;

destructor TChatList.Destroy;
begin
  // FContentLayout is freed automatically as it is a child of Self
  inherited Destroy;
end;

procedure TChatList.Loaded;
begin
  inherited;
  // Make sure the layout has the correct width when loading
  FContentLayout.Width := ClientWidth;
  FContentLayout.Height := Self.Height;
end;

procedure TChatList.LoadFromStream(AStream: TStream);
var
  LReader: TStreamReader;
  LJsonString: string;
  LJsonValue: TJSONValue;
  LRoot: TJSONObject;
  LBubblesArray: TJSONArray;
  LBubbleValue: TJSONValue;
  LNewBubble: TChatBubble;
  LVersion: Integer;
  LIsOutbound: Boolean;
begin
  if not Assigned(AStream) or (AStream.Size = 0) then
    Exit;

  AStream.Position := 0;
  LReader := TStreamReader.Create(AStream, TEncoding.UTF8);
  try
    LJsonString := LReader.ReadToEnd;
  finally
    LReader.Free;
  end;

  if LJsonString = '' then
    Exit;

  LJsonValue := TJSONObject.ParseJSONValue(LJsonString);
  if not(LJsonValue is TJSONObject) then
  begin
    if Assigned(LJsonValue) then
      LJsonValue.Free;
    raise Exception.Create('Invalid chat format.');
  end;

  LRoot := LJsonValue as TJSONObject;
  try
    if not(LRoot.TryGetValue<Integer>('version', LVersion) and (LVersion = CHAT_FORMAT_VERSION)) then
      raise Exception.Create('Chat format version not supported.');

    Self.Clear;
    Self.BeginUpdate;
    try
      if LRoot.TryGetValue<TJSONArray>('bubbles', LBubblesArray) then
      begin
        for LBubbleValue in LBubblesArray do
        begin
          if LBubbleValue is TJSONObject then
          begin
            LNewBubble := TChatBubble.Create(nil);
            try
              LNewBubble.LoadFromJsonObject(LBubbleValue as TJSONObject);

              LIsOutbound := (LNewBubble.TailPosition = tpRight);

              // We reuse the existing logic to add the bubble,
              // ensuring colors, margins, events, etc. are applied.
              AddCustomBubble(LNewBubble, LNewBubble.UserName, not LIsOutbound);

            except
              LNewBubble.Free;
              raise;
            end;
          end;
        end;
      end;
    finally
      Self.EndUpdate;
      Self.Resize;
      TThread.ForceQueue(nil,
        procedure
        begin
          ScrollToBottom;
        end);
    end;
  finally
    LRoot.Free;
  end;
end;

procedure TChatList.Resize;
var
  I: Integer;
  LControl: TControl;
  LMemo: TMemo;
begin
  inherited;

  if not Assigned(FContentLayout) then
    Exit;

  // 1. Update the container layout width (you already had this).
  FContentLayout.Width := ClientWidth;

  // 2. Iterate over all child controls (bubbles) and force a recalculation of their size.
  // Use BeginUpdate/EndUpdate to improve performance and avoid intermediate repaints.
  FContentLayout.BeginUpdate;
  try
    for I := 0 to FContentLayout.ControlsCount - 1 do
    begin
      LControl := FContentLayout.Controls[I];
      // Ensure we only process TChatBubble
      if LControl is TChatBubble then
      begin
        // Call the same method we use when adding a new bubble.
        // This method will use the NEW width of TChatList to calculate the size.
        CalculateAndSetBubbleSize(LControl as TChatBubble);

        LMemo := TChatBubble(LControl).FindFirstChild<TMemo>;
        if Assigned(LMemo) then
        Begin

          LMemo.StyleLookup := 'memostyle';
          LMemo.ApplyStyleLookup;

          var
            Bg: TFmxObject;
          Bg := LMemo.FindStyleResource('background');

          If Bg is TActiveStyleObject then
            TActiveStyleObject(Bg).Opacity := 0;
        End;

      end;
    end;
  finally
    FContentLayout.EndUpdate;
  end;

  // 3. After all bubbles have their new size (height and width),
  // we recalculate the total height of FContentLayout so that the scrollbar is correct.
  UpdateContentLayoutHeight;
end;


// --- PUBLIC METHODS ---

function TChatList.AddBubble(const AText: string; const AUserName: string; AMediaFiles: TAiMediaFiles; AInbound: Boolean): TChatBubble;
var
  LBubble: TChatBubble;
begin
  // 1. Create an empty bubble
  LBubble := TChatBubble.Create(nil);
  try
    // 2. Use the new TChatBubble method to populate it with content
    LBubble.AddContent(AText, AMediaFiles);

    // 3. Call the generic method to add it to the list
    Result := AddCustomBubble(LBubble, AUserName, AInbound);

    Var
    LMemo := Result.FindFirstChild<TMemo>;
    If Assigned(LMemo) then
    Begin

      LMemo.StyleLookup := 'memostyle';
      LMemo.ApplyStyleLookup;
      var
        Bg: TFmxObject;
      Bg := LMemo.FindStyleResource('background');

      If Bg is TActiveStyleObject then
        TActiveStyleObject(Bg).Opacity := 0;

      LBubble.RecalculateSize(LBubble.Width);
    End;

    Self.Resize;
  except
    LBubble.Free; // Free if addition fails
    raise;
  end;
end;

function TChatList.AddBubbleWithControl(AControl: TControl; const AUserName: string; AInbound: Boolean): TChatBubble;
var
  LBubble: TChatBubble;
begin
  // Creates a bubble, assigns the control, and calls the main method
  if (AControl = nil) or Assigned(AControl.Parent) then
    raise EArgumentException.Create('The control to add cannot be null or already have a parent assigned.');

  LBubble := TChatBubble.Create(nil); // No parent, will be assigned in InternalAddBubble
  try
    AControl.Parent := LBubble;
    Result := AddCustomBubble(LBubble, AUserName, AInbound);
  except
    LBubble.Free; // AControl is freed together with LBubble
    raise;
  end;
end;

function TChatList.AddCustomBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean): TChatBubble;
begin
  if (ABubble = nil) or Assigned(ABubble.Parent) then
    raise EArgumentException.Create('The bubble to add cannot be null or already have a parent assigned.');

// The central addition logic is in a private method for reuse
  InternalAddBubble(ABubble, AUserName, AInbound);
  Result := ABubble;
end;

function TChatList.AddMemoBubble(const AText: string; const AUserName: string; AInbound: Boolean; AWordWrap: Boolean): TChatBubble;
var
  LMemo: TMemo;
begin
  // Create a TMemo instead of a TText
  LMemo := TMemo.Create(nil); // No parent
  LMemo.Lines.Text := AText;
  LMemo.WordWrap := AWordWrap;
  // Recommended styles for a memo in a chat:
  LMemo.StyledSettings := LMemo.StyledSettings - [TStyledSetting.Style, TStyledSetting.Other];
  LMemo.ReadOnly := True;
  LMemo.HitTest := True; // so that click passes to the bubble
  LMemo.GoToTextBegin;
  LMemo.SelectionFill.Color := TAlphaColors.Null; // Hide selection color
  LMemo.HideSelectionOnExit := True;

  try
    Result := AddBubbleWithControl(LMemo, AUserName, AInbound);

    // Remove the memo's background to make it transparent
    LMemo.StyleLookup := 'memostyle';
    LMemo.ApplyStyleLookup;

    SetMemoBackVisible(LMemo, False);

  except
    LMemo.Free; // Free if addition fails
    raise;
  end;
end;

procedure TChatList.Clear;
begin
  while FContentLayout.ChildrenCount > 0 do
    FContentLayout.Children[0].Free;

  FLastBubble := nil;
  FLastUserName := '';
  UpdateContentLayoutHeight;
end;

procedure TChatList.RemoveBubble(ABubble: TChatBubble);
begin
  if (ABubble <> nil) and (ABubble.Parent = FContentLayout) then
  begin
    if FLastBubble = ABubble then
    begin
      FLastBubble := nil;
      FLastUserName := '';
      // Optional: find the new "last" bubble
      if FContentLayout.ControlsCount > 1 then
      begin
        var
        LNewLastBubble := FContentLayout.Controls[FContentLayout.ControlsCount - 2] as TChatBubble;
        FLastBubble := LNewLastBubble;
        FLastUserName := LNewLastBubble.UserName;
      end;
    end;
    ABubble.Free;
    UpdateContentLayoutHeight;
  end;
end;

procedure TChatList.SaveToStream(AStream: TStream);
var
  LRoot: TJSONObject;
  LBubblesArray: TJSONArray;
  I: Integer;
  LBubble: TChatBubble;
  LWriter: TStreamWriter;
begin
  if not Assigned(AStream) then
    Exit;

  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('version', TJSONNumber.Create(CHAT_FORMAT_VERSION));

    LBubblesArray := TJSONArray.Create;
    LRoot.AddPair('bubbles', LBubblesArray);

    for I := 0 to FContentLayout.ControlsCount - 1 do
    begin
      if FContentLayout.Controls[I] is TChatBubble then
      begin
        LBubble := FContentLayout.Controls[I] as TChatBubble;
        LBubblesArray.AddElement(LBubble.ToJsonObject);
      end;
    end;

    LWriter := TStreamWriter.Create(AStream, TEncoding.UTF8); // Always use UTF8
    try
      LWriter.Write(LRoot.ToJSON); // ToJSON is more readable than ToString
    finally
      LWriter.Free;
    end;

  finally
    LRoot.Free;
  end;
end;

procedure TChatList.ScrollToBottom;
begin
  // Use ForceQueue to ensure the layout has updated before scrolling
  // Logic extracted from the demo
  TThread.ForceQueue(nil,
    procedure
    begin
      if not Assigned(FContentLayout) then
        Exit;
      var
      LTargetY := FContentLayout.Height - Self.Height;
      if LTargetY > 0 then
      begin
        Self.ViewportPosition := PointF(Self.ViewportPosition.X, LTargetY);
      end;
    end);
end;

// --- INTERNAL AND PRIVATE METHODS ---

function TChatList.IsScrolledToBottom: Boolean;
const
  TOLERANCE = 5; // Pixel margin to consider at the end
begin
  Result := (Self.ViewportPosition.Y >= (FContentLayout.Height - Self.Height - TOLERANCE));
end;

procedure TChatList.InternalAddBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean);
var
  LShouldScroll: Boolean;
begin
  // 5. Flow when adding a bubble
  // Determine if scroll is needed BEFORE adding new content
  LShouldScroll := FAutoScroll or IsScrolledToBottom;

  // 6. Grouping / Append
  if FGroupConsecutiveMessages and TryAppendToLastBubble(ABubble, AUserName, AInbound) then
  begin
    ABubble.Free; // The passed bubble was not used, its content was freed inside TryAppend
    if LShouldScroll then
      ScrollToBottom;
    Exit;
  end;

  // Configuration of the new bubble
  ABubble.UserName := AUserName;
  ABubble.Title := AUserName; // By default the title is the username
  ABubble.Timestamp := FormatDateTime('hh:nn', Now);

  If AInbound then
    ABubble.TailPosition := TChatBubbleTailPosition.tpLeft
  else
    ABubble.TailPosition := TChatBubbleTailPosition.tpRight;

  ABubble.BubbleColor := IfThen(AInbound, FInboundColor, FOutboundColor);
  ABubble.Padding.Rect := FBubblePadding;
  ABubble.Margins.Rect := FBubbleMargins;

  if Assigned(FOnBeforeAddBubble) then
    FOnBeforeAddBubble(Self, ABubble);

  CalculateAndSetBubbleSize(ABubble);

  // Assign parent and hook events
  ABubble.Parent := FContentLayout;

  // 7. Event forwarding
  ABubble.OnAvatarClick := DoBubbleAvatarClick;
  ABubble.OnExpandCollapseClick := DoBubbleExpandCollapseClick;
  ABubble.OnMoreOptionsClick := DoBubbleMoreOptionsClick;
  ABubble.OnMediaFileDblClick := DoBubbleMediaFileDblClick;
  ABubble.OnAttachmentContextPopup := DoAttachmentContextPopup;
  ABubble.OnRecalculateRequired := DoBubbleRecalculateRequired;

  // Redirect the bubble's size calculation event to our own system
  // ABubble.OnCalculateContentSize := DoCalculateContentSize;

  FLastBubble := ABubble;
  FLastUserName := AUserName;

  UpdateContentLayoutHeight;

  if Assigned(FOnBubbleAdded) then
    FOnBubbleAdded(Self, ABubble);

  if LShouldScroll then
    ScrollToBottom;
end;

procedure TChatList.CalculateAndSetBubbleSize(ABubble: TChatBubble);
var
  LMaxWidthForBubble: Single;
  LBubbleHorzMargins: Single;
begin
  // 1. Calculate the horizontal margins that the bubble itself will add.
  // These are defined by the TChatList's FBubbleMargins property.
  LBubbleHorzMargins := FBubbleMargins.Left + FBubbleMargins.Right;

  // 2. Calculate the maximum available width for the bubble,
  // AND SUBTRACT the space its own margins will occupy.
  if Self.ClientWidth > 0 then
    LMaxWidthForBubble := (Self.ClientWidth * FMaxBubbleWidthPercent) - LBubbleHorzMargins
  else
    LMaxWidthForBubble := 200; // A default value

  // Make sure the width is not negative if the window is very small.
  if LMaxWidthForBubble < 0 then
    LMaxWidthForBubble := 0;

  // 3. Delegate size calculation to the bubble itself, passing it
  // the corrected width that its .Width property should have.
  ABubble.RecalculateSize(LMaxWidthForBubble);
end;

{
  function TChatList.TryAppendToLastBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean): Boolean;
  var
  LTargetText: TText;
  LTargetMemo: TMemo; // <-- New variable
  LSourceText: TText;
  LSourceMemo: TMemo; // <-- New variable
  LNewText: string;
  begin
  Result := False;
  if (FLastBubble = nil) or (FLastUserName <> AUserName) then
  Exit;

  // Additional check (you already had it commented, but it's a good idea to have it)
  // to ensure the inbound/outbound message matches the previous one.
  // if FLastBubble.TailPosition <> IfThen(AInbound, TChatBubbleTailPosition.tpLeft, TChatBubbleTailPosition.tpRight) then  Exit;

  // --- MODIFIED MERGE LOGIC ---

  // First, try to merge TMemo with TMemo.
  LTargetMemo := FLastBubble.FindFirstChild<TMemo>;
  LSourceMemo := ABubble.FindFirstChild<TMemo>;
  if (LTargetMemo <> nil) and (LSourceMemo <> nil) then
  begin
  LNewText := LSourceMemo.Lines.Text;
  // Add the new text with a line break.
  LTargetMemo.Lines.Add(LNewText);
  FLastBubble.Timestamp := FormatDateTime('hh:nn', Now);

  // Recalculate size of existing bubble
  CalculateAndSetBubbleSize(FLastBubble);
  UpdateContentLayoutHeight;
  Result := True;
  Exit; // !Important! Exit if we have already merged.
  end;

  // If TMemo merge failed, try TText with TText (your original logic).
  LTargetText := FLastBubble.FindFirstChild<TText>;
  LSourceText := ABubble.FindFirstChild<TText>;
  if (LTargetText <> nil) and (LSourceText <> nil) then
  begin
  LNewText := LSourceText.Text;
  LTargetText.Text := LTargetText.Text + sLineBreak + LNewText;
  FLastBubble.Timestamp := FormatDateTime('hh:nn', Now);

  // Recalculate size of existing bubble
  CalculateAndSetBubbleSize(FLastBubble);
  UpdateContentLayoutHeight;
  Result := True;
  // No need to Exit here because it's the last check.
  end;
  end;
}

function TChatList.TryAppendToLastBubble(ABubble: TChatBubble; const AUserName: string; AInbound: Boolean): Boolean;
var
  LTargetMemo, LSourceMemo: TMemo;
begin
  Result := False;

  // --- IMMEDIATE EXIT RULES (the ones you already had are fine) ---
  if not FGroupConsecutiveMessages then
    Exit;
  if (FLastBubble = nil) or (FLastUserName <> AUserName) then
    Exit;
  // if FLastBubble.TailPosition <> IfThen(AInbound, TChatBubbleTailPosition.tpLeft, TChatBubbleTailPosition.tpRight) then Exit;

  // --- NEW STRICT VALIDATION RULES ---
  // A message with mixed content (images, etc.) should NEVER be merged.
  // The simplest way to know is counting its children. A text-only message has 1 child (the TMemo).

  // Rule 1: The source bubble (new) must contain only one TMemo.
  if ABubble.ContentLayout.ChildrenCount <> 1 then
    Exit; // Has images, attachments, or is empty. Do not merge.
  LSourceMemo := ABubble.FindFirstChild<TMemo>;
  if not Assigned(LSourceMemo) then
    Exit; // Its only child is not a TMemo. Do not merge.

  // Rule 2: The target bubble (last in the chat) must also contain only one TMemo.
  if FLastBubble.ContentLayout.ChildrenCount <> 1 then
    Exit; // The previous bubble already has mixed content. Do not add more.
  LTargetMemo := FLastBubble.FindFirstChild<TMemo>;
  if not Assigned(LTargetMemo) then
    Exit; // The previous bubble is not text-only. Do not merge.


  // --- MERGE LOGIC (Only executed if all previous rules are met) ---
  // If we get here, we know LSourceMemo and LTargetMemo are valid.

  // Add the new text with a line break. Use Add for safety.
  LTargetMemo.Lines.Add(LSourceMemo.Lines.Text);
  FLastBubble.Timestamp := FormatDateTime('hh:nn', Now);

  // Recalculate size of existing bubble
  FLastBubble.RecalculateSize(Self.Width);
  // If you don't have RecalculateBubble, use these two lines:
  // CalculateAndSetBubbleSize(FLastBubble);
  // UpdateContentLayoutHeight;

  Result := True;

  // Note: We no longer need the TText section since all text is now
  // handled through TMemo thanks to refactoring.
  // You can safely remove that part of code.
end;

procedure TChatList.UpdateContentLayoutHeight;
var
  TotalHeight: Single;
  I: Integer;
  Control: TControl;
begin
  // Logic extracted from the demo to adjust container height
  TotalHeight := 0;
  for I := 0 to FContentLayout.ControlsCount - 1 do
  begin
    Control := FContentLayout.Controls[I];
    TotalHeight := TotalHeight + Control.Height + Control.Margins.Top + Control.Margins.Bottom;
  end;
  FContentLayout.Height := TotalHeight + FContentLayout.Padding.Top + FContentLayout.Padding.Bottom;
end;

procedure TChatList.SetAttachmentPopupMenu(const Value: TPopupMenu);
begin
  FAttachmentPopupMenu := Value;
end;

// --- SETTERS ---

procedure TChatList.SetBubbleMargins(const Value: TRectF);
begin
  FBubbleMargins := Value;
end;

procedure TChatList.SetBubblePadding(const Value: TRectF);
begin
  FBubblePadding := Value;
end;

procedure TChatList.SetInboundColor(const Value: TAlphaColor);
begin
  FInboundColor := Value;
end;

procedure TChatList.SetMaxBubbleWidthPercent(const Value: Single);
begin
  FMaxBubbleWidthPercent := EnsureRange(Value, 0.1, 1.0);
end;

procedure TChatList.SetMemoBackVisible(Memo: TMemo; Value: Boolean);
var
  Bg: TFmxObject;
begin
  Bg := Memo.FindStyleResource('background');

  If Bg is TActiveStyleObject then
    TActiveStyleObject(Bg).Opacity := 0;

end;

procedure TChatList.SetOutboundColor(const Value: TAlphaColor);
begin
  FOutboundColor := Value;
end;

procedure TChatList.DoAttachmentContextPopup(Sender: TObject; const AMediaFile: TAiMediaFile; const MousePos: TPointF);
begin
  // 1. Save the file that was clicked.
  // It is now publicly available via TChatList.ActiveMediaFile
  FActiveMediaFile := AMediaFile;

  // 2. If the user has assigned a menu, show it.
  if Assigned(FAttachmentPopupMenu) then
  begin
    // OPTIONAL but RECOMMENDED: Give the user the opportunity to prepare the menu
    // (for example, enable/disable items) via an event.
    // FAttachmentPopupMenu.TagObject := AMediaFile; // Another way to pass info
    FAttachmentPopupMenu.Popup(MousePos.X, MousePos.Y);
  end;

  // 3. Important: Clear the reference after the menu closes.
  // We do it with TThread.ForceQueue so that it runs after the menu action.
  TThread.ForceQueue(nil,
    procedure
    begin
      // FActiveMediaFile := nil;
    end);
end;

// --- EVENT HANDLER FORWARDING ---

procedure TChatList.DoBubbleAvatarClick(Sender: TObject);
begin
  if Assigned(FOnBubbleAvatarClick) then
    FOnBubbleAvatarClick(Self, Sender as TChatBubble);
end;

{
  procedure TChatList.DoBubbleExpandCollapseClick(Sender: TObject);
  begin
  if Assigned(FOnBubbleExpandCollapseClick) then
  FOnBubbleExpandCollapseClick(Self, Sender as TChatBubble);
  end;
}

procedure TChatList.DoBubbleExpandCollapseClick(Sender: TObject);
var
  ABubble: TChatBubble;
  TargetY: Single;
  ViewportHeight: Single;
  BubbleTop: Single;
begin
  // First, fire the public event so that the component's user
  // can execute their own logic if needed.
  if Assigned(FOnBubbleExpandCollapseClick) then
    FOnBubbleExpandCollapseClick(Self, Sender as TChatBubble);

  // --- START OF AUTO-SCROLL LOGIC ---

  // The bubble size has changed, so we need to recalculate
  // the total height of the content layout.
  UpdateContentLayoutHeight;

  // Cast Sender to TChatBubble to work with it.
  ABubble := Sender as TChatBubble;
  if not Assigned(ABubble) then
    Exit;

  // Use TThread.Queue so that the position calculation logic runs
  // AFTER the FMX engine has visually updated the layout.
  // This is crucial to obtain/get the correct coordinates of ABubble.Position.
  TThread.Queue(nil,
    procedure
    begin
      // Double safety check inside the thread
      if Self.IsUpdating or (ABubble = nil) then
        Exit;

      // The scrollbox is the component itself (Self)
      ViewportHeight := Self.Height;
      BubbleTop := ABubble.Position.Y;

      // Optimization: If the bubble is already completely visible, do nothing.
      if (BubbleTop >= Self.ViewportPosition.Y) and ((BubbleTop + ABubble.Height) <= (Self.ViewportPosition.Y + ViewportHeight)) then
      begin
        Exit; // Already visible, no scroll needed.
      end;

      // Calculate the target Y position to center the bubble in the viewport.
      TargetY := BubbleTop - (ViewportHeight / 2) + (ABubble.Height / 2);

      // Make sure we don't go beyond the scroll limits.
      if TargetY < 0 then
        TargetY := 0;

      if TargetY > FContentLayout.Height - ViewportHeight then
        TargetY := FContentLayout.Height - ViewportHeight;

      // Special case: if total content is smaller than visible area,
      // the scroll position should always be 0.
      if FContentLayout.Height <= ViewportHeight then
        TargetY := 0;

      // Animate the change of ViewportPosition.Y for smooth scrolling.
      TAnimator.AnimateFloat(Self, 'ViewportPosition.Y', TargetY, 0.3, TAnimationType.InOut, TInterpolationType.Quadratic);
    end);
end;

procedure TChatList.DoBubbleMediaFileDblClick(Sender: TObject; const AMediaFile: TAiMediaFile);
begin
  if Assigned(FOnMediaFileDblClick) then
    FOnMediaFileDblClick(Self, Sender as TChatBubble, AMediaFile);
end;

procedure TChatList.DoBubbleMoreOptionsClick(Sender: TObject);
begin
  if Assigned(FOnBubbleMoreOptionsClick) then
    FOnBubbleMoreOptionsClick(Self, Sender as TChatBubble);
end;

procedure TChatList.DoBubbleRecalculateRequired(Sender: TObject);
var
  ABubble: TChatBubble;
  LShouldScroll: Boolean;
  LNow: Cardinal;
begin
  if not(Sender is TChatBubble) then
    Exit;

  ABubble := Sender as TChatBubble;
  LNow := TThread.GetTickCount;

  // Throttle: max ~15 recalcs/sec during streaming.
  // Avoid resize+scroll for each chunk.
  if LNow - FLastRecalcTick < 66 then
  begin
    // Save pending bubble; enqueue deferred recalc if none already enqueued
    FRecalcPendingBubble := ABubble;
    if not FRecalcQueued then
    begin
      FRecalcQueued := True;
      TThread.ForceQueue(nil,
        procedure
        var
          LDeferred: TChatBubble;
          LScroll: Boolean;
        begin
          FRecalcQueued := False;
          LDeferred := FRecalcPendingBubble;
          FRecalcPendingBubble := nil;
          if Assigned(LDeferred) then
          begin
            FLastRecalcTick := TThread.GetTickCount;
            LScroll := FAutoScroll and IsScrolledToBottom;
            CalculateAndSetBubbleSize(LDeferred);
            UpdateContentLayoutHeight;
            if LScroll then
              ScrollToBottom;
          end;
        end);
    end;
    Exit;
  end;

  FLastRecalcTick := LNow;
  LShouldScroll := FAutoScroll and IsScrolledToBottom;
  CalculateAndSetBubbleSize(ABubble);
  UpdateContentLayoutHeight;
  if LShouldScroll then
    ScrollToBottom;
end;

{procedure TChatList.DoCalculateContentSize(Sender: TObject; var AContentSize: TSizeF);
var
  LHandled: Boolean;
begin
  LHandled := False;

  // This is the original TChatBubble event. We forward it to the more complete
  // TChatList event that includes the 'Handled' parameter.
  if Assigned(FOnCalculateBubbleContentSize) then
  begin
    FOnCalculateBubbleContentSize(Self, Sender as TChatBubble, AContentSize, LHandled);
  end;
end;
}
end.
