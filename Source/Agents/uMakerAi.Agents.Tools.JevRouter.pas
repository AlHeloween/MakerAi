// MIT License
// MakerAI - Agents: TAiJevRouterTool, graph routing with Jev (TypeSafe AI)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Agents.Tools.JevRouter;

// -----------------------------------------------------------------------------
// TAiJevRouterTool: node tool that decides the next route of the graph.
//
// Asks Jev (see uMakerAi.Jev) which of the Routes matches the node's input
// and writes the chosen key into Blackboard[RouteKey] (by default
// 'next_route'), which is what a TAIAgentsLink in lmConditional mode reads.
// It does not change the engine: the existing conditional link does the rest.
//
//   Router --(lmConditional)--> 'accounting' -> accounting agent node
//                            -> 'tax'        -> tax agent node
//                            -> NextNo       -> fallback (low confidence or error)
//
// In GraphBuilder the route keys are the idStr of the router node's output
// ports: name the ports the same as the Routes.
//
// Routes: one line per route, 'key=description'. The description is what
//   Jev reads to decide; write it as you would explain it to a receptionist.
// Flags: optional yes/no questions, one per line, 'name=question'. They travel
//   in the SAME call as the route. Their probability lands in the blackboard and
//   serves lmExpression (e.g. 'Router.jev.sources >= 0.5') or OnRoute.
//
// Keys written to the blackboard (prefix '<NodeName>.jev.') :
//   choice      route with the highest probability (even below MinConfidence)
//   confidence  confidence of that choice, '0.00'..'1.00' (decimal point)
//   top         the 3 most probable routes, comma-separated
//   <flag>      probability of each flag, '0.00'..'1.00'
//   error       message if the call failed; empty if it went well
// and RouteKey with the final route.
//
// Final route: Choice if its confidence >= MinConfidence; otherwise FallbackRoute.
// OnRoute may change it (e.g. a '_rag' suffix if a flag asks for it). A network
// or configuration error does NOT break the graph: it is logged in '.jev.error' and
// FallbackRoute is used. With an empty FallbackRoute, the conditional link falls to
// NextNo (in GraphBuilder, the out_failure port).
//
// The node's output is the input unchanged: the next agent receives the
// original query.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uMakerAi.Agents, uMakerAi.Agents.Attributes, uMakerAi.Agents.EngineRegistry,
  uMakerAi.Jev;

type
  // Allows adjusting the final route with the whole Jev response in view
  TAiJevRouteEvent = procedure(Sender: TObject; ANode: TAIAgentsNode;
    AResult: TAiJevResult; var ARoute: string) of object;

  [TToolAttribute('JevRouter',
                  'Chooses the next route of the graph with the Jev model (TypeSafe AI)',
                  'Control')]
  TAiJevRouterTool = class(TAiToolBase)
  private
    FUsage: TAiJevUsageMeter;
    FPricePerMillionInput: Double;
    FPricePerMillionOutput: Double;
    FOnUsage: TAiJevUsageEvent;
    FJev: TAiJev;
    FOwnJev: TAiJev;
    FApiKey: string;
    FModel: string;
    FUrl: string; // '' = TypeSafe (JEV_DEFAULT_URL)
    FInstructions: string;
    FRoutes: string;
    FFlags: string;
    FInputField: string;
    FRouteKey: string;
    FFallbackRoute: string;
    FMinConfidence: Double;
    FOnRoute: TAiJevRouteEvent;
    procedure SetJev(const Value: TAiJev);
    function ActiveJev: TAiJev;
    function GetUsage: TAiJevUsage;
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string;
      var AOutput: string); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public const
    ROUTE_QUESTION = 'route'; // reserved name of the route question
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev usage accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;

    // Shortcuts to build Routes / Flags from code
    procedure AddRoute(const AKey, ADescription: string);
    procedure AddFlag(const AName, AQuestion: string);
    // Questions sent to Jev (route + flags). The caller frees the result.
    function BuildQuestions: TAiJevQuestions;

    // Optional: an external TAiJev (shared, or a test double). If assigned,
    // this tool's ApiKey and Model are ignored.
    property Jev: TAiJev read FJev write SetJev;
    property OnRoute: TAiJevRouteEvent read FOnRoute write FOnRoute;
  published
    // [TSecret]: never serialized nor accepted from the graph's JSON
    [TSecret('apiKey')]
    property ApiKey: string read FApiKey write FApiKey;

    [TToolParameterAttribute('Model', 'Jev version; set it before calibrating MinConfidence',
                             'jev-1.13.0')]
    property Model: string read FModel write FModel;
    // System One server: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;

    [TToolParameterAttribute('Routes', 'One per line: key=description. The key is the value ' +
                             'received by the conditional link (port idStr in GraphBuilder)', '')]
    property Routes: string read FRoutes write FRoutes;

    [TToolParameterAttribute('Instructions', 'Routing question. Empty = a generic question ' +
                             'about the InputField field', '')]
    property Instructions: string read FInstructions write FInstructions;

    [TToolParameterAttribute('Flags', 'Optional. One per line: name=yes/no question. Its ' +
                             'probability lands in <Node>.jev.<name>', '')]
    property Flags: string read FFlags write FFlags;

    [TToolParameterAttribute('Input field', 'Name with which the node input travels in the ' +
                             'Jev state; the questions quote it between backticks', 'consulta')]
    property InputField: string read FInputField write FInputField;

    [TToolParameterAttribute('Route key', 'Blackboard key read by the conditional link ' +
                             '(its ConditionalKey)', 'next_route')]
    property RouteKey: string read FRouteKey write FRouteKey;

    [TToolParameterAttribute('Fallback route', 'Route if confidence is low or Jev fails. ' +
                             'Empty = the link falls to NextNo (out_failure)', '')]
    property FallbackRoute: string read FFallbackRoute write FFallbackRoute;

    [TToolParameterAttribute('Minimum confidence', 'Below it FallbackRoute is used', '0.5')]
    property MinConfidence: Double read FMinConfidence write FMinConfidence;
    // Prices for CostUSD of Usage/OnUsage (US$ per million tokens; currently the
    // output is not charged)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with that operation's usage. Synchronous, in the thread
    // that ran it (on a server: the request's, to bill the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

implementation

function Invariant(AValue: Double): string;
begin
  Result := FormatFloat('0.00', AValue, TFormatSettings.Invariant);
end;

{ TAiJevRouterTool }

constructor TAiJevRouterTool.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FInputField := 'consulta';
  FRouteKey := 'next_route';
  FMinConfidence := 0.5;
end;

destructor TAiJevRouterTool.Destroy;
begin
  FOwnJev.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevRouterTool.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevRouterTool.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevRouterTool.ActiveJev: TAiJev;
begin
  if Assigned(FJev) then
    Exit(FJev);
  if not Assigned(FOwnJev) then
    FOwnJev := TAiJev.Create(nil);
  // Refreshed on each use: ApiKey/Model may change between executions
  FOwnJev.ApiKey := FApiKey;
  FOwnJev.Model := FModel;
  FOwnJev.Url := JevUrlOrDefault(FUrl);
  Result := FOwnJev;
end;

procedure TAiJevRouterTool.AddRoute(const AKey, ADescription: string);
begin
  if FRoutes <> '' then
    FRoutes := FRoutes + sLineBreak;
  if ADescription <> '' then
    FRoutes := FRoutes + AKey + '=' + ADescription
  else
    FRoutes := FRoutes + AKey;
end;

procedure TAiJevRouterTool.AddFlag(const AName, AQuestion: string);
begin
  if FFlags <> '' then
    FFlags := FFlags + sLineBreak;
  FFlags := FFlags + AName + '=' + AQuestion;
end;

function TAiJevRouterTool.BuildQuestions: TAiJevQuestions;
var
  Lines: TStringList;
  Q: TAiJevQuestion;
  i, P: Integer;
  Line, Instr: string;
begin
  Result := TAiJevQuestions.Create(nil);
  try
    Instr := FInstructions;
    if Trim(Instr) = '' then
      // Wording tested against jev-1.13.0: the variant "Which route or specialist
      // should attend" lowered the confidence from 0.68 to 0.44 on the same query
      Instr := 'Which specialist should answer `' + FInputField + '`?';

    Q := Result.Add;
    Q.Name := ROUTE_QUESTION;
    Q.Kind := jqChoice;
    Q.Instructions := Instr;
    Q.Criteria.Text := FRoutes;

    Lines := TStringList.Create;
    try
      Lines.Text := FFlags;
      for i := 0 to Lines.Count - 1 do
      begin
        Line := Trim(Lines[i]);
        if Line = '' then
          Continue;
        P := Pos('=', Line);
        if P = 0 then
          raise EAiJevError.CreateFmt('JevRouter: the flag "%s" does not have the name=question form', [Line]);
        if SameText(Trim(Copy(Line, 1, P - 1)), ROUTE_QUESTION) then
          raise EAiJevError.CreateFmt('JevRouter: "%s" is a reserved name for flags', [ROUTE_QUESTION]);
        Result.AddNoul(Trim(Copy(Line, 1, P - 1)), Trim(Copy(Line, P + 1, MaxInt)));
      end;
    finally
      Lines.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TAiJevRouterTool.Execute(ANode: TAIAgentsNode; const AInput: string;
  var AOutput: string);
var
  Q: TAiJevQuestions;
  State: TJSONObject;
  R: TAiJevResult;
  Ans: TAiJevAnswer;
  BB: TAIBlackboard;
  Route, Prefix: string;
  i: Integer;
begin
  // Pass-through: the next agent receives the original query
  AOutput := AInput;
  if not Assigned(ANode) or not Assigned(ANode.Graph) then
    Exit;

  BB := ANode.Graph.Blackboard;
  Prefix := ANode.Name + '.jev.';
  Route := FFallbackRoute;
  try
    Q := BuildQuestions;
    try
      State := TJSONObject.Create;
      try
        State.AddPair(FInputField, AInput);
        R := ActiveJev.Ask(State, Q);
      finally
        State.Free;
      end;
      try
        JevReportResult(Self, R, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput, FOnUsage);
        Ans := R[ROUTE_QUESTION];
        BB.SetString(Prefix + 'choice', Ans.Choice);
        BB.SetString(Prefix + 'confidence', Invariant(Ans.Confidence));
        BB.SetString(Prefix + 'top', string.Join(',', Ans.Top(3)));
        for i := 0 to Q.Count - 1 do
          if Q[i].Name <> ROUTE_QUESTION then
            BB.SetString(Prefix + Q[i].Name, Invariant(R[Q[i].Name].Noul));

        if Ans.Confidence >= FMinConfidence then
          Route := Ans.Choice;
        if Assigned(FOnRoute) then
          FOnRoute(Self, ANode, R, Route);
      finally
        R.Free;
      end;
    finally
      Q.Free;
    end;
    BB.SetString(Prefix + 'error', '');
  except
    on E: Exception do
    begin
      // A fallen router must not take down the graph: the fallback route is taken
      BB.SetString(Prefix + 'error', E.Message);
      ANode.Print('JevRouter: ' + E.Message);
      Route := FFallbackRoute;
    end;
  end;
  BB.SetString(FRouteKey, Route);
end;

function TAiJevRouterTool.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJevRouterTool.ResetUsage;
begin
  FUsage.Reset;
end;

initialization
  TEngineRegistry.Instance.RegisterTool(
    TAiJevRouterTool, 'uMakerAi.Agents.Tools.JevRouter');

end.
