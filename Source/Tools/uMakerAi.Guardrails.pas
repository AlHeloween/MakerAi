// MIT License
//
// MakerAI - Guardrails: security policy for tool calls (phase 3)
//
// Name: Gustavo Enriquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Guardrails;

// -----------------------------------------------------------------------------
// TAiGuardrails: intercepts tool executions BEFORE they occur.
//
// It is assigned to TAiFunctions.Guardrails; DoCallFunction consults CheckToolCall
// before dispatching any tool (local, MCP or AutoMCP). If the policy
// blocks, the tool is NOT executed and the LLM receives a JSON error explaining the
// reason (it may reconsider its plan).
//
// Politica (en orden de evaluacion):
//   1. Enabled=False               -> all allowed (no-op).
//   2. AllowedTools no vacia       -> whitelist estricta (comodin * soportado).
//   3. BlockedTools                -> blocklist by name (wildcard *).
//   4. BlockedArgPatterns          -> forbidden substrings in the arguments
//                                     JSON (case-insensitive; p.ej. 'rm -rf',
//                                     'DROP TABLE', '..\').
//   5. Classifier                  -> semantic judgment of the risk of what the
//                                     listas dejaron pasar (p.ej.
//                                     TAiJevGuardrailClassifier). Si lanza una
//                                     excepcion, bloquea (falla cerrado).
//   6. OnCheckToolCall             -> veto/permiso programatico final.
//
// Cada bloqueo dispara OnBlocked (auditoria) e incrementa BlockedCount.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Masks;

type
  // Programmatic veto/permission. AAllow arrives with the verdict of the lists;
  // the handler can reverse it in any direction and explain it in AReason.
  TAiGuardrailCheckEvent = procedure(Sender: TObject; const AToolName, AArguments: string;
    var AAllow: Boolean; var AReason: string) of object;

  // Audit: it is triggered for every blocked tool call.
  TAiGuardrailBlockedEvent = procedure(Sender: TObject;
    const AToolName, AArguments, AReason: string) of object;

  // Clasificador semantico enchufable en TAiGuardrails.Classifier. Solo se
  // query for the tool calls that the lists already allowed.
  TAiGuardrailClassifierBase = class(TComponent)
  public
    // True = allow. If it returns False, AReason explains the block.
    function CheckToolCall(const AToolName, AArguments: string; out AReason: string): Boolean; virtual; abstract;
  end;

  TAiGuardrails = class(TComponent)
  private
    FEnabled: Boolean;
    FAllowedTools: TStrings;
    FBlockedTools: TStrings;
    FBlockedArgPatterns: TStrings;
    FOnCheckToolCall: TAiGuardrailCheckEvent;
    FOnBlocked: TAiGuardrailBlockedEvent;
    FBlockedCount: Int64;
    FClassifier: TAiGuardrailClassifierBase;
    procedure SetClassifier(const Value: TAiGuardrailClassifierBase);
    procedure SetAllowedTools(const Value: TStrings);
    procedure SetBlockedTools(const Value: TStrings);
    procedure SetBlockedArgPatterns(const Value: TStrings);
    class function MatchesAny(AList: TStrings; const AValue: string): Boolean; static;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // True = allowed. If it returns False, AReason explains the block and it is already
    // disparo OnBlocked / se incremento BlockedCount.
    function CheckToolCall(const AToolName, AArguments: string; out AReason: string): Boolean;

    property BlockedCount: Int64 read FBlockedCount;
  published
    property Enabled: Boolean read FEnabled write FEnabled default True;
    // Whitelist estricta (si no esta vacia, solo estos tools pueden ejecutarse).
    // Acepta comodines de mascara: 'file_*', '*_read', etc.
    property AllowedTools: TStrings read FAllowedTools write SetAllowedTools;
    // Blocklist by name (mask wildcards)
    property BlockedTools: TStrings read FBlockedTools write SetBlockedTools;
    // Forbidden substrings inside the argument JSON (case-insensitive)
    property BlockedArgPatterns: TStrings read FBlockedArgPatterns write SetBlockedArgPatterns;
    // Semantic risk judgment (step 5); nil = not used
    property Classifier: TAiGuardrailClassifierBase read FClassifier write SetClassifier;
    property OnCheckToolCall: TAiGuardrailCheckEvent read FOnCheckToolCall write FOnCheckToolCall;
    property OnBlocked: TAiGuardrailBlockedEvent read FOnBlocked write FOnBlocked;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGuardrails]);
end;

{ TAiGuardrails }

constructor TAiGuardrails.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
  FAllowedTools := TStringList.Create;
  FBlockedTools := TStringList.Create;
  FBlockedArgPatterns := TStringList.Create;
end;

destructor TAiGuardrails.Destroy;
begin
  FAllowedTools.Free;
  FBlockedTools.Free;
  FBlockedArgPatterns.Free;
  inherited;
end;

procedure TAiGuardrails.SetClassifier(const Value: TAiGuardrailClassifierBase);
begin
  if FClassifier = Value then
    Exit;
  if Assigned(FClassifier) then
    FClassifier.RemoveFreeNotification(Self);
  FClassifier := Value;
  if Assigned(FClassifier) then
    FClassifier.FreeNotification(Self);
end;

procedure TAiGuardrails.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FClassifier) then
    FClassifier := nil;
end;

procedure TAiGuardrails.SetAllowedTools(const Value: TStrings);
begin
  FAllowedTools.Assign(Value);
end;

procedure TAiGuardrails.SetBlockedTools(const Value: TStrings);
begin
  FBlockedTools.Assign(Value);
end;

procedure TAiGuardrails.SetBlockedArgPatterns(const Value: TStrings);
begin
  FBlockedArgPatterns.Assign(Value);
end;

class function TAiGuardrails.MatchesAny(AList: TStrings; const AValue: string): Boolean;
var
  i: Integer;
  Pattern: string;
begin
  Result := False;
  for i := 0 to AList.Count - 1 do
  begin
    Pattern := Trim(AList[i]);
    if Pattern = '' then
      Continue;
    // TMask supports * and ? ; case-insensitive comparison via lowercase
    if MatchesMask(AValue.ToLower, Pattern.ToLower) then
      Exit(True);
  end;
end;

function TAiGuardrails.CheckToolCall(const AToolName, AArguments: string; out AReason: string): Boolean;
var
  i: Integer;
  Pattern: string;
begin
  Result := True;
  AReason := '';

  if not FEnabled then
    Exit;

  // 1. Whitelist estricta
  if (FAllowedTools.Count > 0) and (not MatchesAny(FAllowedTools, AToolName)) then
  begin
    Result := False;
    AReason := Format('tool "%s" is not in the allowed list', [AToolName]);
  end;

  // 2. Blocklist by name
  if Result and MatchesAny(FBlockedTools, AToolName) then
  begin
    Result := False;
    AReason := Format('tool "%s" is blocked by policy', [AToolName]);
  end;

  // 3. Forbidden patterns in the arguments
  if Result then
    for i := 0 to FBlockedArgPatterns.Count - 1 do
    begin
      Pattern := Trim(FBlockedArgPatterns[i]);
      if (Pattern <> '') and ContainsText(AArguments, Pattern) then
      begin
        Result := False;
        AReason := Format('arguments contain forbidden pattern "%s"', [Pattern]);
        Break;
      end;
    end;

  // 4. Semantic classifier: only for what the lists let through
  if Result and Assigned(FClassifier) then
    try
      Result := FClassifier.CheckToolCall(AToolName, AArguments, AReason);
    except
      on E: Exception do
      begin
        // Fail closed: without a verdict the tool is not executed
        Result := False;
        AReason := 'guardrail classifier error: ' + E.Message;
      end;
    end;

  // 5. Programmatic veto/permission (can reverse the previous verdict)
  if Assigned(FOnCheckToolCall) then
    FOnCheckToolCall(Self, AToolName, AArguments, Result, AReason);

  if not Result then
  begin
    if AReason = '' then
      AReason := 'blocked by guardrails policy';
    Inc(FBlockedCount);
    if Assigned(FOnBlocked) then
      FOnBlocked(Self, AToolName, AArguments, AReason);
  end;
end;

end.
