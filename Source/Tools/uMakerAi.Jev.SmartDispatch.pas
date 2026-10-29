// MIT License
//
// MakerAI - Jev: SmartDispatch classifier with the Jev model (TypeSafe AI)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Jev.SmartDispatch;

// -----------------------------------------------------------------------------
// TAiJevDispatchClassifier: it is assigned to ChatTools.DispatchClassifier of a chat
// in ChatMode = cmSmartDispatch and replaces pass 1 (an LLM that classifies the
// request into IMAGEGEN / VIDEOGEN / TTS / WEBSEARCH / CHAT) with a question
// Choice a Jev.
//
//   Chat.ChatMode := cmSmartDispatch;
//   Chat.ChatTools.ImageTool := MiHerramientaDeImagen;
//   Chat.ChatTools.DispatchClassifier := JevDispatch;   // este componente
//
// Only the tags whose tool is assigned are offered to Jev (the chat decides them).
// If only CHAT remains, Jev is not called: the response is CHAT directly.
// With confidence < MinConfidence it returns '' and the chat does its pass 1 via LLM,
// just like without a classifier; an error also falls there (the chat absorbs it).
//
// Calibrated against jev-1.13.0 (Sep 27/2026): 15/15 on requests in
// Spanish and English, including "describe how a cat would look" -> CHAT (0.72).
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uMakerAi.Chat.Tools, uMakerAi.Jev;

type
  TAiJevDispatchClassifier = class(TAiDispatchClassifierBase)
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
    FMinConfidence: Double;
    FTagDescriptions: TStrings;
    FLastTag: string;
    FLastConfidence: Double;
    procedure SetJev(const Value: TAiJev);
    procedure SetTagDescriptions(const Value: TStrings);
    function ActiveJev: TAiJev;
    function DescriptionOf(const ATag: string): string;
    function GetUsage: TAiJevUsage;
  protected
    function ClassifyDispatch(const APrompt: string; const ATags: TArray<string>): string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Jev consumption accumulated since Create or ResetUsage (thread-safe)
    property Usage: TAiJevUsage read GetUsage;
    procedure ResetUsage;
    // Ultima eleccion de Jev aunque no superara MinConfidence ('' si no se consulto)
    property LastTag: string read FLastTag;
    property LastConfidence: Double read FLastConfidence;
  published
    // Optional: external TAiJev (shared or test double); if assigned,
    // ApiKey y Model de este componente se ignoran
    property Jev: TAiJev read FJev write SetJev;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    // Servidor System One: '' = TypeSafe; 'http://localhost:11434/v1/' = Ollama
    // (with Model := 'nimble', 'clef-flash'...). Ignored if Jev is assigned
    property Url: string read FUrl write FUrl;
    // Under the hood, the chat classifies with the LLM as always
    property MinConfidence: Double read FMinConfidence write FMinConfidence;
    // Optional: 'TAG=description' to replace the default description of a tag
    property TagDescriptions: TStrings read FTagDescriptions write SetTagDescriptions;
    // Prices for CostUSD of Usage/OnUsage (US$ per million tokens; today the
    // output is not charged)
    property PricePerMillionInput: Double read FPricePerMillionInput write FPricePerMillionInput;
    property PricePerMillionOutput: Double read FPricePerMillionOutput write FPricePerMillionOutput;
    // Once per operation with the consumption of that operation. Synchronous, in the thread
    // that executed it (on a server: that of the request, to charge the client)
    property OnUsage: TAiJevUsageEvent read FOnUsage write FOnUsage;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiJevDispatchClassifier]);
end;

{ TAiJevDispatchClassifier }

constructor TAiJevDispatchClassifier.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUsage := TAiJevUsageMeter.Create;
  FPricePerMillionInput := JEV_PRICE_PER_MILLION_INPUT;
  FApiKey := '@TYPESAFE_API_KEY';
  FModel := 'jev-1.13.0';
  FMinConfidence := 0.6;
  FTagDescriptions := TStringList.Create;
end;

destructor TAiJevDispatchClassifier.Destroy;
begin
  FTagDescriptions.Free;
  FOwnJev.Free;
  FUsage.Free;
  inherited;
end;

procedure TAiJevDispatchClassifier.SetJev(const Value: TAiJev);
begin
  if FJev = Value then
    Exit;
  if Assigned(FJev) then
    FJev.RemoveFreeNotification(Self);
  FJev := Value;
  if Assigned(FJev) then
    FJev.FreeNotification(Self);
end;

procedure TAiJevDispatchClassifier.SetTagDescriptions(const Value: TStrings);
begin
  FTagDescriptions.Assign(Value);
end;

procedure TAiJevDispatchClassifier.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FJev) then
    FJev := nil;
end;

function TAiJevDispatchClassifier.ActiveJev: TAiJev;
begin
  if Assigned(FJev) then
    Exit(FJev);
  if not Assigned(FOwnJev) then
    FOwnJev := TAiJev.Create(nil);
  FOwnJev.ApiKey := FApiKey;
  FOwnJev.Model := FModel;
  FOwnJev.Url := JevUrlOrDefault(FUrl);
  Result := FOwnJev;
end;

function TAiJevDispatchClassifier.DescriptionOf(const ATag: string): string;
begin
  Result := Trim(FTagDescriptions.Values[ATag]);
  if Result <> '' then
    Exit;
  // Redaccion calibrada contra jev-1.13.0 (15/15, espanol e ingles)
  if ATag = 'IMAGEGEN' then
    Result := 'The user asks to create, draw or generate an image, picture, logo or illustration'
  else if ATag = 'VIDEOGEN' then
    Result := 'The user asks to create or generate a video or animation'
  else if ATag = 'TTS' then
    Result := 'The user asks to read a text aloud or to produce spoken audio / a voice recording'
  else if ATag = 'WEBSEARCH' then
    Result := 'The user needs recent news, current events, live prices or information that must be looked up on the web'
  else if ATag = 'CHAT' then
    Result := 'Anything else: conversation, questions, explanations, writing, code, calculations'
  else
    Result := '';
end;

function TAiJevDispatchClassifier.ClassifyDispatch(const APrompt: string;
  const ATags: TArray<string>): string;
var
  Q: TAiJevQuestions;
  Options: TArray<string>;
  State: TJSONObject;
  R: TAiJevResult;
  i: Integer;
begin
  Result := '';
  FLastTag := '';
  FLastConfidence := 0;

  // Un solo tag posible: no hay nada que clasificar
  if Length(ATags) = 1 then
    Exit(ATags[0]);
  if Length(ATags) = 0 then
    Exit;

  SetLength(Options, Length(ATags));
  for i := 0 to High(ATags) do
    if DescriptionOf(ATags[i]) <> '' then
      Options[i] := ATags[i] + '=' + DescriptionOf(ATags[i])
    else
      Options[i] := ATags[i];

  Q := TAiJevQuestions.Create(nil);
  try
    Q.AddChoice('tag', 'Which handler should process `request`?', Options);
    State := TJSONObject.Create;
    try
      State.AddPair('request', APrompt);
      R := ActiveJev.Ask(State, Q);
    finally
      State.Free;
    end;
    try
      JevReportResult(Self, R, FUsage, JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput, FOnUsage);
      FLastTag := R['tag'].Choice;
      FLastConfidence := R['tag'].Confidence;
      if FLastConfidence >= FMinConfidence then
        Result := FLastTag;
    finally
      R.Free;
    end;
  finally
    Q.Free;
  end;
end;

function TAiJevDispatchClassifier.GetUsage: TAiJevUsage;
begin
  Result := FUsage.Snapshot(JevAdapterInputPrice(FJev, FUrl, FPricePerMillionInput), FPricePerMillionOutput);
end;

procedure TAiJevDispatchClassifier.ResetUsage;
begin
  FUsage.Reset;
end;

end.
