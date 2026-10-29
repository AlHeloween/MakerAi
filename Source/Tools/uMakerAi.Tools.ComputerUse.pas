unit uMakerAi.tools.ComputerUse;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math, System.StrUtils, System.Types,
  System.Generics.Collections,
  uMakerAi.Core, uMakerAi.Tools.Functions, uMakerAi.Chat.Messages;

type
  // Action types supported by Gemini 2.5
  TAiComputerActionType = (catUnknown, catClick, // click_at, left_click
    catRightClick,    // right_click
    catMiddleClick,   // middle_click
    catDoubleClick,   // double_click
    catTripleClick,   // triple_click (Claude computer_2025xxxx)
    catType,          // type_text_at
    catKeyCombination, // key_combination
    catHoldKey,       // hold_key (hold key for N seconds)
    catScroll,        // scroll_at, scroll_document
    catDrag,          // drag_and_drop
    catHover,         // hover_at
    catCursorPosition, // cursor_position (query current position)
    catZoom,          // zoom (zoom in on a region of the screenshot, computer_20251124)
    catNavigate,      // navigate, search, open_web_browser
    catScreenshot,    // screenshot (explicit request from the model)
    catWait,          // wait_5_seconds
    catTerminate,     // To stop the loop
    catGoBack, catGoForward); // go_back, go_forward

  // Structure with the already processed data (real coordinates, not normalized)
  TAiActionData = record
    ActionType: TAiComputerActionType;
    FunctionName: string;

    // Coordinates calculated to real screen pixels
    X, Y: Integer;
    DestX, DestY: Integer; // For Drag & Drop

    // Text and keyboard data
    TextToType: string;
    KeyCombo: string; // Ex: 'Control+S' (key_combination / hold_key)
    PressEnter: Boolean; // For type_text_at
    ClearBeforeTyping: Boolean; // For type_text_at (default true)
    Modifiers: string; // Modifier keys on click/scroll: 'shift', 'ctrl+alt'...
    HoldDuration: Double; // Seconds to hold the key in hold_key (default 1.0)

    // Scroll data
    ScrollDirection: string; // 'up', 'down', 'left', 'right'
    ScrollAmount: Integer; // Default 800 (according to docs)

    // Region to zoom in on (real screen pixels)
    ZoomRect: TRect;

    // Navigation data
    Url: string;
  end;

  // Result returned by your application
  TAiActionResult = record
    Success: Boolean;
    ErrorMessage: string;
    CustomOutput: string; // Optional, to return extra info
  end;

  // Eventos
  TOnExecuteAction = procedure(Sender: TObject; const ActionData: TAiActionData; var Result: TAiActionResult) of object;
  TOnRequestScreenshot = procedure(Sender: TObject; var MediaFile: TAiMediaFile) of object;
  TOnSafetyConfirmation = procedure(Sender: TObject; const Explanation: string; var Allow: Boolean) of object;

  TAiComputerUseTool = class(TComponent)
  private
    FScreenWidth: Integer;
    FScreenHeight: Integer;
    FCurrentUrl: string;

    FOnRequestScreenshot: TOnRequestScreenshot;
    FOnSafetyConfirmation: TOnSafetyConfirmation;
    FOnExecuteAction: TOnExecuteAction;
    FAreaWidth: Integer;
    FAreaTop: Integer;
    FAreaHeight: Integer;
    FAreaLeft: Integer;
    FEnableZoom: Boolean;
    FCurrentAction: TAiActionData;

    // Helpers
    function DenormalizeCoordinate(Coord, MaxPixels, Offset: Integer): Integer;

    function ParseAction(ToolCall: TAiToolsFunction; out SafetyReason: string): TAiActionData;

  public
    constructor Create(AOwner: TComponent); override;

    // Main method called from TAiGeminiChat
    // Returns the JSON string for the response and the MediaFile (Screenshot) by reference
    function ProcessToolCall(ToolCall: TAiToolsFunction; out ResponseMedia: TAiMediaFile): string;

    // Converts an X,Y point from Gemini (0-1000) to real screen pixels
    function GetRealPoint(GeminiX, GeminiY: Integer): TPoint;

    // Converts two points (TopLeft, BottomRight) from Gemini to a screen TRect
    function GetRealRect(GemX1, GemY1, GemX2, GemY2: Integer): TRect;

    // Returns a JSON array string (OpenAI format) with the definitions of all functions
    // of Computer Use. Useful for models without native support: pass the result to TAiFunctions.
    function GetFunctionDefinitions: string;

    // Translates a native Claude Computer Use tool_call (action + coordinate[px], etc.)
    // into the x,y-normalized 0-999 format that ParseAction/ProcessToolCall expect, and
    // maps the action name. Mutates ToolCall.Name and ToolCall.Arguments in place, using
    // ScreenWidth/ScreenHeight as the pixel reference. This is the single source of truth
    // for the Claude->tool translation: the Claude driver uses it server-side, and a
    // client that receives tool_calls from an OpenAI-compatible broker (without going
    // through the Claude driver) can call it before ProcessToolCall to run Computer Use
    // locally with identical behavior.
    procedure TranslateClaudeToolCall(ToolCall: TAiToolsFunction);

    // Same for the native 'computer' tool from OpenAI (Responses API, gpt-6-astra).
    // ToolCall.Name must contain the action type ('click', 'type', 'scroll'...) and
    // ToolCall.Arguments the object for that action. NOTE: an OpenAI computer_call
    // brings an ARRAY 'actions'; the driver iterates it and calls here once per action.
    procedure TranslateOpenAIToolCall(ToolCall: TAiToolsFunction);

    // Last processed action (updated before triggering OnExecuteAction).
    // Useful in OnRequestScreenshot to know the context, e.g. CurrentAction.ZoomRect
    // when CurrentAction.ActionType = catZoom.
    property CurrentAction: TAiActionData read FCurrentAction;

  published
    // Configuration of your physical screen
    property ScreenWidth: Integer read FScreenWidth write FScreenWidth default 1920;
    property ScreenHeight: Integer read FScreenHeight write FScreenHeight default 1080;

    // Simulated URL to return to the API (Gemini requirement)
    // Default: 'app://desktop'
    property CurrentUrl: string read FCurrentUrl write FCurrentUrl;

    // Eventos
    property OnExecuteAction: TOnExecuteAction read FOnExecuteAction write FOnExecuteAction;
    property OnRequestScreenshot: TOnRequestScreenshot read FOnRequestScreenshot write FOnRequestScreenshot;
    property OnSafetyConfirmation: TOnSafetyConfirmation read FOnSafetyConfirmation write FOnSafetyConfirmation;
    // If AreaWidth is 0, full screen will be assumed at runtime
    property AreaLeft: Integer read FAreaLeft write FAreaLeft default 0;
    property AreaTop: Integer read FAreaTop write FAreaTop default 0;
    property AreaWidth: Integer read FAreaWidth write FAreaWidth default 1920;
    property AreaHeight: Integer read FAreaHeight write FAreaHeight default 1080;

    // Enables Claude's 'zoom' action (computer_20251124 only). Allows the
    // model to zoom in on a region of the screenshot to read small text.
    property EnableZoom: Boolean read FEnableZoom write FEnableZoom default False;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiComputerUseTool]);
end;

{ TAiComputerUseTool }

constructor TAiComputerUseTool.Create(AOwner: TComponent);
begin
  inherited;
  FScreenWidth := 1920;
  FScreenHeight := 1080;
  FCurrentUrl := 'app://desktop';
  FEnableZoom := False;
end;

function TAiComputerUseTool.DenormalizeCoordinate(Coord, MaxPixels, Offset: Integer): Integer;
begin
  // Gemini returns 0-999. We convert to real pixels.
  if Coord < 0 then
    Coord := 0;
  if Coord > 999 then
    Coord := 999;

  // Formula: (Normalized % * Image Size) + Monitor Offset
  Result := Round((Coord / 1000) * MaxPixels) + Offset;
end;

function TAiComputerUseTool.GetRealPoint(GeminiX, GeminiY: Integer): TPoint;
begin
  Result.X := DenormalizeCoordinate(GeminiX, FAreaWidth, FAreaLeft);
  Result.Y := DenormalizeCoordinate(GeminiY, FAreaHeight, FAreaTop);
end;

function TAiComputerUseTool.GetRealRect(GemX1, GemY1, GemX2, GemY2: Integer): TRect;
begin
  Result.TopLeft := GetRealPoint(GemX1, GemY1);
  Result.BottomRight := GetRealPoint(GemX2, GemY2);
end;

procedure TAiComputerUseTool.TranslateClaudeToolCall(ToolCall: TAiToolsFunction);
// Converts the native Claude Computer Use format to the TAiComputerUseTool format.
// Claude (computer_toolset_20260801) sends one tool_use per action, named after it:
//   name="left_click", input={"coordinate":[x_px, y_px]}
// Legacy (computer_20251124, single 'computer' tool): input={"action":"left_click", ...}
// ParseAction expects: {"x":norm, "y":norm, "text":"...", ...} + ToolCall.Name = mapped action.
var
  JArgs, JNew: TJSONObject;
  Action, MappedName, SText, SDir: string;
  ScrW, ScrH, PxX, PxY, NormX, NormY, Amount: Integer;
  DDur: Double;
  // PxX/PxY are reused as the top-left corner in the 'zoom' case.

  // Claude sends the arrays SOMETIMES as a JSON array and OTHER times as a string
  // with the JSON inside, within the SAME turn:
  //     "coordinate": [299, 282]     <- the first calls
  //     "coordinate": "[299, 400]"   <- from a certain point on
  // Verified at runtime against computer_toolset_20260801 (Sep 2026). With
  // TryGetValue<TJSONArray> alone, the second form does not match, the coordinate is
  // lost and the action ends up at (0,0): a click in the corner of the screen.
  // The model then gets lost and enters a retry loop.
  // Affects 'coordinate', 'start_coordinate' and 'region'.
  function AsArray(AObj: TJSONObject; const AName: string;
    out AArr: TJSONArray; out AOwned: Boolean): Boolean;
  var
    S: string;
    V: TJSONValue;
  begin
    AOwned := False;
    AArr := nil;
    if AObj.TryGetValue<TJSONArray>(AName, AArr) then
      Exit(True);
    Result := False;
    if AObj.TryGetValue<string>(AName, S) then
    begin
      S := Trim(S);
      if S.StartsWith('[') then
      begin
        V := TJSONObject.ParseJSONValue(S);
        if V is TJSONArray then
        begin
          AArr := TJSONArray(V);
          AOwned := True;
          Result := True;
        end
        else
          V.Free;
      end;
    end;
  end;

  // Integer item from an array, tolerating whether it comes as a number or as a string.
  function ItemInt(AArr: TJSONArray; AIdx: Integer; out AValue: Integer): Boolean;
  var
    V: TJSONValue;
  begin
    Result := False;
    AValue := 0;
    if (AArr = nil) or (AIdx < 0) or (AIdx >= AArr.Count) then
      Exit;
    V := AArr.Items[AIdx];
    if V is TJSONNumber then
    begin
      AValue := TJSONNumber(V).AsInt;
      Result := True;
    end
    else
      Result := TryStrToInt(Trim(V.Value), AValue);
  end;

  // Point in pixels -> normalized 0-999. True if it was present and readable.
  function TryGetPointNorm(AObj: TJSONObject; const AName: string;
    out ANormX, ANormY: Integer): Boolean;
  var
    LArr: TJSONArray;
    LOwned: Boolean;
    LX, LY: Integer;
  begin
    Result := False;
    ANormX := 0; ANormY := 0;
    if not AsArray(AObj, AName, LArr, LOwned) then
      Exit;
    try
      if (LArr.Count >= 2) and ItemInt(LArr, 0, LX) and ItemInt(LArr, 1, LY) then
      begin
        ANormX := Round(LX / ScrW * 1000); if ANormX > 999 then ANormX := 999;
        ANormY := Round(LY / ScrH * 1000); if ANormY > 999 then ANormY := 999;
        Result := True;
      end;
    finally
      if LOwned then
        LArr.Free;
    end;
  end;

  // Zoom region: [x1,y1,x2,y2] in pixels -> two normalized points.
  function TryGetRectNorm(AObj: TJSONObject; const AName: string;
    out AX1, AY1, AX2, AY2: Integer): Boolean;
  var
    LArr: TJSONArray;
    LOwned: Boolean;
    A, B, C, D: Integer;
  begin
    Result := False;
    AX1 := 0; AY1 := 0; AX2 := 0; AY2 := 0;
    if not AsArray(AObj, AName, LArr, LOwned) then
      Exit;
    try
      if (LArr.Count >= 4) and ItemInt(LArr, 0, A) and ItemInt(LArr, 1, B) and
         ItemInt(LArr, 2, C) and ItemInt(LArr, 3, D) then
      begin
        AX1 := Round(A / ScrW * 1000); if AX1 > 999 then AX1 := 999;
        AY1 := Round(B / ScrH * 1000); if AY1 > 999 then AY1 := 999;
        AX2 := Round(C / ScrW * 1000); if AX2 > 999 then AX2 := 999;
        AY2 := Round(D / ScrH * 1000); if AY2 > 999 then AY2 := 999;
        Result := True;
      end;
    finally
      if LOwned then
        LArr.Free;
    end;
  end;

begin
  JArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if not Assigned(JArgs) then
    Exit;
  try
    // computer_toolset_20260801 (Aug 2026): the toolset serves 17 tools with
    // their own name (left_click, key, scroll, zoom, screenshot...), so the
    // action arrives in ToolCall.Name and no longer in an 'action' field. The
    // reading of 'action' is kept for histories recorded with the previous format.
    if not JArgs.TryGetValue<string>('action', Action) then
      Action := ToolCall.Name;
    if Action = '' then
      Exit;

    ScrW := FScreenWidth;
    ScrH := FScreenHeight;
    if ScrW <= 0 then ScrW := 1920;
    if ScrH <= 0 then ScrH := 1080;

    // Map Claude action names to TAiComputerUseTool action names
    if      Action = 'left_click'       then MappedName := 'click_at'
    else if Action = 'right_click'      then MappedName := 'right_click'
    else if Action = 'middle_click'     then MappedName := 'middle_click'
    else if Action = 'double_click'     then MappedName := 'double_click'
    else if Action = 'left_click_drag'  then MappedName := 'drag_and_drop'
    else if Action = 'mouse_move'       then MappedName := 'hover_at'
    else if Action = 'type'             then MappedName := 'type_text_at'
    else if Action = 'key'              then MappedName := 'key_combination'
    else if Action = 'scroll'           then MappedName := 'scroll_at'
    else if Action = 'wait'             then MappedName := 'wait_5_seconds'
    else MappedName := Action; // screenshot, go_back, go_forward pass through

    ToolCall.Name := MappedName;

    JNew := TJSONObject.Create;
    try
      // Drag: start_coordinate = origin (-> x,y); coordinate = destination (-> destination_x,y)
      if (Action = 'left_click_drag') and
         TryGetPointNorm(JArgs, 'start_coordinate', NormX, NormY) then
      begin
        JNew.AddPair('x', TJSONNumber.Create(NormX));
        JNew.AddPair('y', TJSONNumber.Create(NormY));

        if TryGetPointNorm(JArgs, 'coordinate', NormX, NormY) then
        begin
          JNew.AddPair('destination_x', TJSONNumber.Create(NormX));
          JNew.AddPair('destination_y', TJSONNumber.Create(NormY));
        end;
      end
      else if TryGetPointNorm(JArgs, 'coordinate', NormX, NormY) then
      begin
        JNew.AddPair('x', TJSONNumber.Create(NormX));
        JNew.AddPair('y', TJSONNumber.Create(NormY));
      end;

      // Text / keys / modifiers: Claude's 'text' field changes meaning by action.
      if JArgs.TryGetValue<string>('text', SText) then
      begin
        if (Action = 'key') or (Action = 'hold_key') then
          JNew.AddPair('keys', SText)
        else if Action = 'type' then
        begin
          JNew.AddPair('text', SText);
          // Claude 'type' implies neither Enter nor a position: it types into the
          // focused control. Suppress the automatic Enter (ParseAction defaults to True).
          JNew.AddPair('press_enter', TJSONBool.Create(False));
        end
        else
          // In click/scroll/triple_click the 'text' holds the modifiers
          JNew.AddPair('modifiers', SText);
      end;

      // hold_key duration (seconds). Like the coordinates, it can arrive
      // as a number or as a string ("duration": "1"), so both are accepted.
      if (Action = 'hold_key') then
      begin
        if not JArgs.TryGetValue<Double>('duration', DDur) then
          if JArgs.TryGetValue<string>('duration', SText) then
            DDur := StrToFloatDef(Trim(SText), -1)
          else
            DDur := -1;
        if DDur >= 0 then
          JNew.AddPair('duration', TJSONNumber.Create(DDur));
      end;

      // Zoom: region [x1,y1,x2,y2] (px) -> x,y + destination_x,destination_y (norm 0-999)
      if (Action = 'zoom') and TryGetRectNorm(JArgs, 'region', PxX, PxY, NormX, NormY) then
      begin
        JNew.AddPair('x', TJSONNumber.Create(PxX));
        JNew.AddPair('y', TJSONNumber.Create(PxY));
        JNew.AddPair('destination_x', TJSONNumber.Create(NormX));
        JNew.AddPair('destination_y', TJSONNumber.Create(NormY));
      end;

      // Scroll: Claude uses 'scroll_direction'/'scroll_amount'. Accept 'direction'/'amount' too.
      if JArgs.TryGetValue<string>('scroll_direction', SDir) or
         JArgs.TryGetValue<string>('direction', SDir) then
        JNew.AddPair('direction', SDir);
      if JArgs.TryGetValue<Integer>('scroll_amount', Amount) or
         JArgs.TryGetValue<Integer>('amount', Amount) or
         (JArgs.TryGetValue<string>('scroll_amount', SText) and TryStrToInt(Trim(SText), Amount)) or
         (JArgs.TryGetValue<string>('amount', SText) and TryStrToInt(Trim(SText), Amount)) then
        JNew.AddPair('magnitude', TJSONNumber.Create(Amount * 120))
      else if Action = 'scroll' then
        JNew.AddPair('magnitude', TJSONNumber.Create(800));

      ToolCall.Arguments := JNew.ToJSON;
    finally
      JNew.Free;
    end;
  finally
    JArgs.Free;
  end;
end;

procedure TAiComputerUseTool.TranslateOpenAIToolCall(ToolCall: TAiToolsFunction);
// Converts an action from OpenAI's native 'computer' tool to the canonical format
// expected by ParseAction/ProcessToolCall (x,y normalized 0-999).
// OpenAI sends: name='click', args={"button":"left","x":12,"y":528,"keys":[...]}
// The coordinates come in PIXELS of the sent image (same as Claude), not
// normalized: the 'computer' tool no longer declares display_width/height and the model
// deduces them from the screenshot itself.
var
  JArgs, JNew, JPt: TJSONObject;
  JKeys, JPath: TJSONArray;
  Action, MappedName, SText, SBtn, SDir: string;
  ScrW, ScrH, ScrollX, ScrollY, Mag, K: Integer;

  function Norm(APx, AMax: Integer): Integer;
  begin
    if AMax <= 0 then
      AMax := 1;
    Result := Round(APx / AMax * 1000);
    if Result < 0 then
      Result := 0;
    if Result > 999 then
      Result := 999;
  end;

  procedure AddXY(const AObj: TJSONObject; const AXName, AYName: string; APxX, APxY: Integer);
  begin
    AObj.AddPair(AXName, TJSONNumber.Create(Norm(APxX, ScrW)));
    AObj.AddPair(AYName, TJSONNumber.Create(Norm(APxY, ScrH)));
  end;

begin
  JArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  if not Assigned(JArgs) then
    JArgs := TJSONObject.Create; // actions without fields: screenshot, wait
  try
    Action := LowerCase(Trim(ToolCall.Name));
    if Action = '' then
      Exit;

    ScrW := FScreenWidth;
    ScrH := FScreenHeight;
    if ScrW <= 0 then
      ScrW := 1920;
    if ScrH <= 0 then
      ScrH := 1080;

    // OpenAI name mapping -> canonical. 'click' depends on the button: the
    // back/forward side mouse buttons are navigation, not a positional click.
    SBtn := '';
    JArgs.TryGetValue<string>('button', SBtn);
    SBtn := LowerCase(SBtn);

    if Action = 'click' then
    begin
      if SBtn = 'right' then
        MappedName := 'right_click'
      else if SBtn = 'wheel' then
        MappedName := 'middle_click'
      else if SBtn = 'back' then
        MappedName := 'go_back'
      else if SBtn = 'forward' then
        MappedName := 'go_forward'
      else
        MappedName := 'click_at';
    end
    else if Action = 'double_click' then MappedName := 'double_click'
    else if Action = 'move'         then MappedName := 'hover_at'
    else if Action = 'type'         then MappedName := 'type_text_at'
    else if Action = 'keypress'     then MappedName := 'key_combination'
    else if Action = 'scroll'       then MappedName := 'scroll_at'
    else if Action = 'drag'         then MappedName := 'drag_and_drop'
    else if Action = 'wait'         then MappedName := 'wait_5_seconds'
    else MappedName := Action; // screenshot pasa tal cual

    ToolCall.Name := MappedName;

    JNew := TJSONObject.Create;
    try
      // Simple coordinates (click, double_click, move, scroll)
      if JArgs.GetValue('x') <> nil then
        AddXY(JNew, 'x', 'y', JArgs.GetValue<Integer>('x'), JArgs.GetValue<Integer>('y'));

      // drag: path = [{x,y}, ...]. The canonical format only has origin and destination, so
      // the first and last points are taken; the intermediate ones are lost.
      if (Action = 'drag') and JArgs.TryGetValue<TJSONArray>('path', JPath) and (JPath.Count > 0) then
      begin
        JPt := JPath.Items[0] as TJSONObject;
        AddXY(JNew, 'x', 'y', JPt.GetValue<Integer>('x'), JPt.GetValue<Integer>('y'));
        JPt := JPath.Items[JPath.Count - 1] as TJSONObject;
        AddXY(JNew, 'destination_x', 'destination_y', JPt.GetValue<Integer>('x'), JPt.GetValue<Integer>('y'));
      end;

      // type: writes into the focused control, with no implicit Enter and no coordinates
      // (same criterion as Claude; ParseAction sets press_enter=True by default).
      if (Action = 'type') and JArgs.TryGetValue<string>('text', SText) then
      begin
        JNew.AddPair('text', SText);
        JNew.AddPair('press_enter', TJSONBool.Create(False));
      end;

      // keypress: keys is an array (["WIN","r"]) -> combo 'WIN+r'.
      // On click, that same array is the held modifiers.
      if JArgs.TryGetValue<TJSONArray>('keys', JKeys) and (JKeys.Count > 0) then
      begin
        SText := '';
        for K := 0 to JKeys.Count - 1 do
        begin
          if SText <> '' then
            SText := SText + '+';
          SText := SText + JKeys.Items[K].Value;
        end;
        if Action = 'keypress' then
          JNew.AddPair('keys', SText)
        else
          JNew.AddPair('modifiers', SText);
      end;

      // scroll: OpenAI gives displacement in pixels per axis (scroll_x/scroll_y),
      // the canonical format wants direction + magnitude. The dominant axis is taken.
      if Action = 'scroll' then
      begin
        ScrollX := 0;
        ScrollY := 0;
        JArgs.TryGetValue<Integer>('scroll_x', ScrollX);
        JArgs.TryGetValue<Integer>('scroll_y', ScrollY);
        if Abs(ScrollY) >= Abs(ScrollX) then
        begin
          Mag := Abs(ScrollY);
          if ScrollY < 0 then
            SDir := 'up'
          else
            SDir := 'down';
        end
        else
        begin
          Mag := Abs(ScrollX);
          if ScrollX < 0 then
            SDir := 'left'
          else
            SDir := 'right';
        end;
        if Mag = 0 then
          Mag := 800; // no useful displacement: the page default is used
        JNew.AddPair('direction', SDir);
        JNew.AddPair('magnitude', TJSONNumber.Create(Mag));
      end;

      ToolCall.Arguments := JNew.ToJSON;
    finally
      JNew.Free;
    end;
  finally
    JArgs.Free;
  end;
end;

function TAiComputerUseTool.ParseAction(ToolCall: TAiToolsFunction; out SafetyReason: string): TAiActionData;
var
  JArgs, JSafety: TJSONObject;
  NormX, NormY: Integer;
begin
  // Initialize record
  Result.ActionType := catUnknown;
  Result.FunctionName := ToolCall.Name;
  Result.X := 0;
  Result.Y := 0;
  Result.DestX := 0;
  Result.DestY := 0;
  Result.TextToType := '';
  Result.KeyCombo := '';
  Result.PressEnter := False;
  Result.ClearBeforeTyping := True;
  Result.Modifiers := '';
  Result.HoldDuration := 0;
  Result.ScrollDirection := '';
  Result.ScrollAmount := 0;
  Result.ZoomRect := TRect.Empty;
  Result.Url := '';
  SafetyReason := '';

  // Parse JSON Arguments
  JArgs := TJSONObject.ParseJSONValue(ToolCall.Arguments) as TJSONObject;
  try
    if not Assigned(JArgs) then
      Exit;

    // 1. Safety Decision detection (Human-in-the-loop)
    // "safety_decision": { "decision": "require_confirmation", "explanation": "..." }
    if JArgs.TryGetValue<TJSONObject>('safety_decision', JSafety) then
    begin
      var
        Decision: string;
      if JSafety.TryGetValue<string>('decision', Decision) and SameText(Decision, 'require_confirmation') then
      begin
        JSafety.TryGetValue<string>('explanation', SafetyReason);
      end;
    end;

    // 2. Mapping Function to Action Type
    var
    FName := LowerCase(Trim(ToolCall.Name));

    if (FName = 'click_at') or (FName = 'left_click') then
      Result.ActionType := catClick
    else if (FName = 'right_click') then
      Result.ActionType := catRightClick
    else if (FName = 'middle_click') then
      Result.ActionType := catMiddleClick
    else if (FName = 'double_click') then
      Result.ActionType := catDoubleClick
    else if (FName = 'triple_click') then
      Result.ActionType := catTripleClick
    else if (FName = 'type_text_at') or (FName = 'type') then
      Result.ActionType := catType
    else if (FName = 'key_combination') then
      Result.ActionType := catKeyCombination
    else if (FName = 'hold_key') then
      Result.ActionType := catHoldKey
    else if (FName = 'scroll_at') or (FName = 'scroll_document') then
      Result.ActionType := catScroll
    else if (FName = 'drag_and_drop') then
      Result.ActionType := catDrag
    else if (FName = 'hover_at') or (FName = 'mouse_move') then
      Result.ActionType := catHover
    else if (FName = 'cursor_position') or (FName = 'get_cursor_position') then
      Result.ActionType := catCursorPosition
    else if (FName = 'zoom') then
      Result.ActionType := catZoom
    else if (FName = 'navigate') or (FName = 'search') or (FName = 'open_web_browser') then
      Result.ActionType := catNavigate
    else if (FName = 'screenshot') then
      Result.ActionType := catScreenshot
    else if (FName = 'wait_5_seconds') then
      Result.ActionType := catWait
    else if (FName = 'go_back') then
      Result.ActionType := catGoBack
    else if (FName = 'go_forward') then
      Result.ActionType := catGoForward;

    // 3. Extraction and Normalization of Parameters

    // Coordinates X, Y
    if JArgs.TryGetValue<Integer>('x', NormX) then
      Result.X := DenormalizeCoordinate(NormX, FAreaWidth, FAreaLeft);

    if JArgs.TryGetValue<Integer>('y', NormY) then
      Result.Y := DenormalizeCoordinate(NormY, FAreaHeight, FAreaTop);

    // Destination Coordinates (Drag)
    if JArgs.TryGetValue<Integer>('destination_x', NormX) then
      Result.DestX := DenormalizeCoordinate(NormX, FAreaWidth, FAreaLeft);

    if JArgs.TryGetValue<Integer>('destination_y', NormY) then
      Result.DestY := DenormalizeCoordinate(NormY, FAreaHeight, FAreaTop);

    // Text and Keyboard
    JArgs.TryGetValue<string>('text', Result.TextToType);
    JArgs.TryGetValue<string>('keys', Result.KeyCombo);

    // Boolean flags (type_text_at)
    if JArgs.GetValue('press_enter') is TJSONBool then
      Result.PressEnter := JArgs.GetValue<Boolean>('press_enter')
    else
      Result.PressEnter := True;

    if JArgs.GetValue('clear_before_typing') is TJSONBool then
      Result.ClearBeforeTyping := JArgs.GetValue<Boolean>('clear_before_typing')
    else
      Result.ClearBeforeTyping := True;

    // Scroll
    JArgs.TryGetValue<string>('direction', Result.ScrollDirection);
    if not JArgs.TryGetValue<Integer>('magnitude', Result.ScrollAmount) then
      Result.ScrollAmount := 800;

    // Navigation
    JArgs.TryGetValue<string>('url', Result.Url);

    // Modifiers on click/scroll (Claude sends them in 'text'; here already normalized to 'modifiers')
    JArgs.TryGetValue<string>('modifiers', Result.Modifiers);

    // hold_key duration (seconds). Default 1.0 if not specified.
    if not JArgs.TryGetValue<Double>('duration', Result.HoldDuration) then
      Result.HoldDuration := 1.0;

    // Zoom region: built from (x,y) and (destination_x, destination_y)
    // already denormalized to real pixels.
    if Result.ActionType = catZoom then
      Result.ZoomRect := TRect.Create(Result.X, Result.Y, Result.DestX, Result.DestY);

  finally
    JArgs.Free;
  end;
end;

function TAiComputerUseTool.ProcessToolCall(ToolCall: TAiToolsFunction; out ResponseMedia: TAiMediaFile): string;
var
  ActionData: TAiActionData;
  ActionResult: TAiActionResult;
  SafetyReason: string;
  UserAllowed: Boolean;
  JResponse: TJSONObject;
begin
  ResponseMedia := nil;
  ActionResult.Success := False;
  ActionResult.ErrorMessage := 'Unknown error';
  ActionResult.CustomOutput := '';

  // 1. Parse data and detect safety
  ActionData := ParseAction(ToolCall, SafetyReason);
  FCurrentAction := ActionData; // Exposed via CurrentAction (e.g. ZoomRect in OnRequestScreenshot)

  // 2. Safety Verification (Human-in-the-loop)
  if SafetyReason <> '' then
  begin
    UserAllowed := False;
    if Assigned(FOnSafetyConfirmation) then
      FOnSafetyConfirmation(Self, SafetyReason, UserAllowed)
    else
      UserAllowed := False; // For safety, if there is no event, deny.

    if not UserAllowed then
    begin
      JResponse := TJSONObject.Create;
      try
        JResponse.AddPair('output', 'action_denied_by_user');
        JResponse.AddPair('url', FCurrentUrl);
        JResponse.AddPair('safety_acknowledgement', 'false');
        Result := JResponse.ToJSON;
      finally
        JResponse.Free;
      end;
      Exit;
    end;
  end;

  // 3. Execute Action (External Events)
  if Assigned(FOnExecuteAction) then
  begin
    try
      FOnExecuteAction(Self, ActionData, ActionResult);
    except
      on E: Exception do
      begin
        ActionResult.Success := False;
        ActionResult.ErrorMessage := E.Message;
      end;
    end;
  end
  else
  begin
    ActionResult.Success := False;
    ActionResult.ErrorMessage := 'OnExecuteAction event not assigned.';
  end;

  // Wait for the UI to react before taking screenshot (500-1000ms)
  if ActionResult.Success then
    Sleep(1000);

  // 4. Capture New State (If successful)
  if ActionResult.Success then
  begin
    if Assigned(FOnRequestScreenshot) then
      FOnRequestScreenshot(Self, ResponseMedia);

    if (ActionData.ActionType = catNavigate) and (ActionData.Url <> '') then
      FCurrentUrl := ActionData.Url;
  end;

  // 5. Build Response JSON
  JResponse := TJSONObject.Create;
  try
    if ActionResult.Success then
      JResponse.AddPair('output', 'action_executed_successfully')
    else
      JResponse.AddPair('output', 'error: ' + ActionResult.ErrorMessage);

    JResponse.AddPair('url', FCurrentUrl);

    if SafetyReason <> '' then
      JResponse.AddPair('safety_acknowledgement', 'true');

    if ActionResult.CustomOutput <> '' then
      JResponse.AddPair('data', ActionResult.CustomOutput);

    Result := JResponse.ToJSON;
  finally
    JResponse.Free;
  end;
end;

function TAiComputerUseTool.GetFunctionDefinitions: string;

  function MakeFn(const AName, ADesc: string; const AProps: TJSONObject; const ARequired: TJSONArray): TJSONObject;
  var
    JFn, JParams: TJSONObject;
    JTool: TJSONObject;
  begin
    JParams := TJSONObject.Create;
    JParams.AddPair('type', 'object');
    JParams.AddPair('properties', AProps);
    JParams.AddPair('required', ARequired);
    JFn := TJSONObject.Create;
    JFn.AddPair('name', AName);
    JFn.AddPair('description', ADesc);
    JFn.AddPair('parameters', JParams);
    JTool := TJSONObject.Create;
    JTool.AddPair('type', 'function');
    JTool.AddPair('function', JFn);
    Result := JTool;
  end;

  function CoordProps: TJSONObject;
  var JP: TJSONObject;
  begin
    Result := TJSONObject.Create;
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Normalized X coordinate 0-999 (horizontal)'); Result.AddPair('x', JP);
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Normalized Y coordinate 0-999 (vertical)');   Result.AddPair('y', JP);
  end;

  function ReqXY: TJSONArray;
  begin
    Result := TJSONArray.Create;
    Result.Add('x');
    Result.Add('y');
  end;

var
  JArray: TJSONArray;
  JProps, JP: TJSONObject;
  JReq: TJSONArray;
begin
  JArray := TJSONArray.Create;
  try
    // click_at (with optional modifiers: shift, ctrl, alt, super)
    JProps := CoordProps;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Optional modifier keys while clicking: shift, ctrl, alt, super (combinable with +)'); JProps.AddPair('modifiers', JP);
    JArray.AddElement(MakeFn('click_at', 'Left click at the given coordinates.', JProps, ReqXY));

    // right_click
    JArray.AddElement(MakeFn('right_click', 'Right click at the given coordinates.', CoordProps, ReqXY));

    // middle_click
    JArray.AddElement(MakeFn('middle_click', 'Middle click at the given coordinates.', CoordProps, ReqXY));

    // double_click
    JArray.AddElement(MakeFn('double_click', 'Double click at the given coordinates.', CoordProps, ReqXY));

    // triple_click
    JArray.AddElement(MakeFn('triple_click', 'Triple click at the given coordinates.', CoordProps, ReqXY));

    // drag_and_drop
    JProps := CoordProps;
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Drag destination X (normalized 0-999)'); JProps.AddPair('destination_x', JP);
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Drag destination Y (normalized 0-999)'); JProps.AddPair('destination_y', JP);
    JReq := ReqXY; JReq.Add('destination_x'); JReq.Add('destination_y');
    JArray.AddElement(MakeFn('drag_and_drop', 'Drags from (x,y) to (destination_x, destination_y).', JProps, JReq));

    // hover_at
    JArray.AddElement(MakeFn('hover_at', 'Moves the cursor to the coordinates without clicking.', CoordProps, ReqXY));

    // type_text_at
    JProps := CoordProps;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Text to type'); JProps.AddPair('text', JP);
    JP := TJSONObject.Create; JP.AddPair('type','boolean'); JP.AddPair('description','Press Enter at the end (default true)'); JProps.AddPair('press_enter', JP);
    JReq := ReqXY; JReq.Add('text');
    JArray.AddElement(MakeFn('type_text_at', 'Clicks at (x,y) and types the indicated text.', JProps, JReq));

    // key_combination
    JProps := TJSONObject.Create;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Key combination, e.g. "Control+S", "Alt+F4"'); JProps.AddPair('keys', JP);
    JReq := TJSONArray.Create; JReq.Add('keys');
    JArray.AddElement(MakeFn('key_combination', 'Executes a system key combination.', JProps, JReq));

    // hold_key
    JProps := TJSONObject.Create;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Key(s) to hold down, e.g. "shift", "ctrl+alt"'); JProps.AddPair('keys', JP);
    JP := TJSONObject.Create; JP.AddPair('type','number'); JP.AddPair('description','Duration in seconds (default 1.0)'); JProps.AddPair('duration', JP);
    JReq := TJSONArray.Create; JReq.Add('keys');
    JArray.AddElement(MakeFn('hold_key', 'Holds a key down for the indicated seconds.', JProps, JReq));

    // scroll_at (with optional modifiers)
    JProps := CoordProps;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Direction: up, down, left, right'); JProps.AddPair('direction', JP);
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Scroll amount in pixels (default 800)'); JProps.AddPair('magnitude', JP);
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','Optional modifier keys during scroll: shift, ctrl, alt, super'); JProps.AddPair('modifiers', JP);
    JReq := ReqXY; JReq.Add('direction');
    JArray.AddElement(MakeFn('scroll_at', 'Performs scroll at the indicated position.', JProps, JReq));

    // cursor_position
    JProps := TJSONObject.Create;
    JReq := TJSONArray.Create;
    JArray.AddElement(MakeFn('cursor_position', 'Returns the current cursor position (in data as {"x":..,"y":..}).', JProps, JReq));

    // zoom (zoom in on region: (x,y) top-left corner, (destination_x,destination_y) bottom-right)
    JProps := CoordProps;
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','X bottom-right corner of the region (normalized 0-999)'); JProps.AddPair('destination_x', JP);
    JP := TJSONObject.Create; JP.AddPair('type','integer'); JP.AddPair('description','Y bottom-right corner of the region (normalized 0-999)'); JProps.AddPair('destination_y', JP);
    JReq := ReqXY; JReq.Add('destination_x'); JReq.Add('destination_y');
    JArray.AddElement(MakeFn('zoom', 'Zooms in on a region of the screen to inspect it in detail.', JProps, JReq));

    // navigate
    JProps := TJSONObject.Create;
    JP := TJSONObject.Create; JP.AddPair('type','string'); JP.AddPair('description','URL to navigate to'); JProps.AddPair('url', JP);
    JReq := TJSONArray.Create; JReq.Add('url');
    JArray.AddElement(MakeFn('navigate', 'Navigates to the specified URL.', JProps, JReq));

    // screenshot
    JProps := TJSONObject.Create;
    JReq := TJSONArray.Create;
    JArray.AddElement(MakeFn('screenshot', 'Captures the current screen and returns it as an image.', JProps, JReq));

    // wait_5_seconds
    JProps := TJSONObject.Create;
    JReq := TJSONArray.Create;
    JArray.AddElement(MakeFn('wait_5_seconds', 'Waits 5 seconds for the UI to react.', JProps, JReq));

    // go_back
    JProps := TJSONObject.Create;
    JReq := TJSONArray.Create;
    JArray.AddElement(MakeFn('go_back', 'Navigates back in history.', JProps, JReq));

    // go_forward
    JProps := TJSONObject.Create;
    JReq := TJSONArray.Create;
    JArray.AddElement(MakeFn('go_forward', 'Navigates forward in history.', JProps, JReq));

    Result := JArray.ToJSON;
  finally
    JArray.Free;
  end;
end;

end.
