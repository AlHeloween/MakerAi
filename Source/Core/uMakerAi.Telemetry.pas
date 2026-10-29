unit uMakerAi.Telemetry;

// -----------------------------------------------------------------------------
// TAiTelemetry: OpenTelemetry trace exporter (OTLP/HTTP with JSON).
//
// Design:
// - Opt-in component: if there is no enabled instance, ALL instrumentation
//   in the framework is no-op (AiSpanStart returns nil and helpers tolerate
//   nil). Zero cost for those who don't use it.
// - Exports to any OTLP/HTTP collector (Jaeger, Grafana Tempo, Langfuse,
//   Arize Phoenix, etc.) at the standard endpoint http://localhost:4318/v1/traces.
// - JSON encoding of OTLP protobuf (no protobuf dependency required).
// - Attributes following OpenTelemetry GenAI semantic conventions
//   (gen_ai.system, gen_ai.request.model, gen_ai.usage.input_tokens, ...).
// - Completed spans are queued and an exporter thread sends them in batches
//   (FlushIntervalMs); Flush forces synchronous send (tests/shutdown).
// - Automatic nesting per thread: StartSpan takes as parent the active span
//   of the current thread unless an explicit W3C traceparent is passed.
// -----------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, System.Net.HttpClient, System.Net.URLClient;

type
  // Direct mapping to OTLP SpanKind enum (see BuildOtlpKind)
  TAiSpanKind = (skInternal, skServer, skClient, skProducer, skConsumer);

  TAiSpan = class
  private
    FTraceId: string; // 32 hex
    FSpanId: string; // 16 hex
    FParentSpanId: string; // 16 hex or ''
    FName: string;
    FKind: TAiSpanKind;
    FStartUnixNano: Int64;
    FEndUnixNano: Int64;
    FAttributes: TJSONArray; // OTLP format: [{key, value:{stringValue|...}}]
    FErrorMessage: string;
    FHasError: Boolean;
    FOwnerThreadId: TThreadID;
    procedure AddAttr(const AKey: string; AValue: TJSONObject);
  public
    constructor Create(const AName: string; AKind: TAiSpanKind);
    destructor Destroy; override;
    procedure SetAttribute(const AKey, AValue: string); overload;
    procedure SetAttribute(const AKey: string; AValue: Int64); overload;
    procedure SetAttribute(const AKey: string; AValue: Double); overload;
    procedure SetAttribute(const AKey: string; AValue: Boolean); overload;
    procedure SetError(const AMessage: string);
    // W3C trace-context header to propagate the trace (e.g., in _meta MCP)
    function TraceParent: string;
    property TraceId: string read FTraceId;
    property SpanId: string read FSpanId;
    property Name: string read FName;
  end;

  TAiTelemetryLogEvent = procedure(Sender: TObject; const AMsg: string) of object;

  TAiTelemetry = class(TComponent)
  private
    class var FActive: TAiTelemetry; // global opt-in (one active instance)
  private
    FEnabled: Boolean;
    FEndpoint: string;
    FServiceName: string;
    FHeaders: TStrings; // extra headers Name=Value (e.g. Authorization=Bearer x)
    FFlushIntervalMs: Integer;
    FMaxBatchSize: Integer;
    FLock: TCriticalSection;
    FPending: TObjectList<TAiSpan>; // completed spans pending export
    FWorker: TThread;
    FStopEvent: TEvent;
    FThreadStacks: TObjectDictionary<TThreadID, TStack<TAiSpan>>; // active span per thread
    FOnLog: TAiTelemetryLogEvent;
    FDroppedSpans: Int64;
    procedure SetEnabled(const Value: Boolean);
    procedure SetHeaders(const Value: TStrings);
    procedure StartWorker;
    procedure StopWorker;
    procedure ExportPending;
    function BuildOtlpPayload(ABatch: TObjectList<TAiSpan>): TJSONObject;
    procedure DoLog(const AMsg: string);
    procedure PushThreadSpan(ASpan: TAiSpan);
    procedure PopThreadSpan(ASpan: TAiSpan);
    function PeekThreadSpan: TAiSpan;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Active (enabled) instance or nil. All framework instrumentation goes
    // through here: without an active instance nothing is created.
    class function Active: TAiTelemetry; static;

    // Creates a span. If ATraceParent is empty, the parent is the active span
    // of the current thread (if any). With a W3C traceparent
    // ('00-<trace>-<span>-..') it continues that remote trace. The span
    // remains active for the thread until closed with EndSpan.
    function StartSpan(const AName: string; AKind: TAiSpanKind = skInternal;
      const ATraceParent: string = ''): TAiSpan;

    // Ends the span and enqueues it for export (telemetry takes ownership).
    // AErrorMsg <> '' marks the span with status ERROR.
    procedure EndSpan(ASpan: TAiSpan; const AErrorMsg: string = '');

    // Synchronously exports all pending (tests / shutdown).
    procedure Flush;

    property DroppedSpans: Int64 read FDroppedSpans;
  published
    property Enabled: Boolean read FEnabled write SetEnabled default False;
    property Endpoint: string read FEndpoint write FEndpoint;
    property ServiceName: string read FServiceName write FServiceName;
    property Headers: TStrings read FHeaders write SetHeaders;
    property FlushIntervalMs: Integer read FFlushIntervalMs write FFlushIntervalMs default 2000;
    property MaxBatchSize: Integer read FMaxBatchSize write FMaxBatchSize default 200;
    property OnLog: TAiTelemetryLogEvent read FOnLog write FOnLog;
  end;

// --- No-op-safe helpers for instrumented framework code ---
// Returns nil if no active telemetry; all tolerate ASpan = nil.
function AiSpanStart(const AName: string; AKind: TAiSpanKind = skInternal;
  const ATraceParent: string = ''): TAiSpan;
procedure AiSpanEnd(ASpan: TAiSpan; const AErrorMsg: string = '');
procedure AiSpanAttr(ASpan: TAiSpan; const AKey, AValue: string); overload;
procedure AiSpanAttr(ASpan: TAiSpan; const AKey: string; AValue: Int64); overload;
procedure AiSpanAttr(ASpan: TAiSpan; const AKey: string; AValue: Boolean); overload;
// Span's traceparent (or '' if nil) for propagation (e.g., _meta MCP)
function AiSpanTraceParent(ASpan: TAiSpan): string;

procedure Register;

implementation

{$I uMakerAi.Version.inc}

const
  DEF_ENDPOINT = 'http://localhost:4318/v1/traces';
  OTEL_SCOPE_NAME = 'makerai';
  // Bound to the real framework version: it was hardcoded to '3.5' and kept
  // appearing as '3.5' even when the framework was already at 3.7, so the
  // viewer lied about which version generated the trace.
  OTEL_SCOPE_VERSION = MAKERAI_VERSION_SHORT;

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiTelemetry]);
end;

// ----------------------------------------------------------------------------
// Utilities
// ----------------------------------------------------------------------------

function NewHexId(ADigits: Integer): string;
var
  G: TGUID;
  S: string;
begin
  // A GUID provides 32 hex digits of sufficient randomness for OTLP ids
  CreateGUID(G);
  S := GUIDToString(G).Replace('{', '').Replace('}', '').Replace('-', '').ToLower;
  Result := Copy(S, 1, ADigits);
end;

function NowUnixNano: Int64;
var
  UtcNow: TDateTime;
begin
  UtcNow := TTimeZone.Local.ToUniversalTime(Now);
  // Millisecond precision expressed in nanoseconds (sufficient for traces)
  Result := DateTimeToUnix(UtcNow, True) * 1000000000 + MilliSecondOf(UtcNow) * 1000000;
end;

// Parses a W3C traceparent: '00-<32 hex traceId>-<16 hex spanId>-<flags>'
function ParseTraceParent(const AValue: string; out ATraceId, ASpanId: string): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  ATraceId := '';
  ASpanId := '';
  Parts := AValue.Split(['-']);
  if (Length(Parts) >= 3) and (Length(Parts[1]) = 32) and (Length(Parts[2]) = 16) then
  begin
    ATraceId := Parts[1].ToLower;
    ASpanId := Parts[2].ToLower;
    Result := True;
  end;
end;

// ----------------------------------------------------------------------------
// TAiSpan
// ----------------------------------------------------------------------------

constructor TAiSpan.Create(const AName: string; AKind: TAiSpanKind);
begin
  inherited Create;
  FName := AName;
  FKind := AKind;
  FTraceId := NewHexId(32);
  FSpanId := NewHexId(16);
  FStartUnixNano := NowUnixNano;
  FAttributes := TJSONArray.Create;
  FOwnerThreadId := TThread.CurrentThread.ThreadID;
end;

destructor TAiSpan.Destroy;
begin
  FAttributes.Free;
  inherited;
end;

procedure TAiSpan.AddAttr(const AKey: string; AValue: TJSONObject);
var
  Pair: TJSONObject;
begin
  Pair := TJSONObject.Create;
  Pair.AddPair('key', AKey);
  Pair.AddPair('value', AValue);
  FAttributes.AddElement(Pair);
end;

procedure TAiSpan.SetAttribute(const AKey, AValue: string);
var
  V: TJSONObject;
begin
  V := TJSONObject.Create;
  V.AddPair('stringValue', AValue);
  AddAttr(AKey, V);
end;

procedure TAiSpan.SetAttribute(const AKey: string; AValue: Int64);
var
  V: TJSONObject;
begin
  // Proto3 JSON map serializes int64 as decimal string
  V := TJSONObject.Create;
  V.AddPair('intValue', IntToStr(AValue));
  AddAttr(AKey, V);
end;

procedure TAiSpan.SetAttribute(const AKey: string; AValue: Double);
var
  V: TJSONObject;
begin
  V := TJSONObject.Create;
  V.AddPair('doubleValue', TJSONNumber.Create(AValue));
  AddAttr(AKey, V);
end;

procedure TAiSpan.SetAttribute(const AKey: string; AValue: Boolean);
var
  V: TJSONObject;
begin
  V := TJSONObject.Create;
  V.AddPair('boolValue', TJSONBool.Create(AValue));
  AddAttr(AKey, V);
end;

procedure TAiSpan.SetError(const AMessage: string);
begin
  FHasError := True;
  FErrorMessage := AMessage;
end;

function TAiSpan.TraceParent: string;
begin
  Result := '00-' + FTraceId + '-' + FSpanId + '-01';
end;

// ----------------------------------------------------------------------------
// TAiTelemetry
// ----------------------------------------------------------------------------

constructor TAiTelemetry.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := False;
  FEndpoint := DEF_ENDPOINT;
  FServiceName := 'MakerAI';
  FHeaders := TStringList.Create;
  FFlushIntervalMs := 2000;
  FMaxBatchSize := 200;
  FLock := TCriticalSection.Create;
  FPending := TObjectList<TAiSpan>.Create(True);
  FStopEvent := TEvent.Create(nil, True, False, '');
  FThreadStacks := TObjectDictionary<TThreadID, TStack<TAiSpan>>.Create([doOwnsValues]);
end;

destructor TAiTelemetry.Destroy;
begin
  if FActive = Self then
    FActive := nil;
  StopWorker;
  // Last attempt not to lose pending data
  try
    if FEnabled then
      ExportPending;
  except
    // shutdown must never fail due to telemetry
  end;
  FPending.Free;
  FThreadStacks.Free;
  FStopEvent.Free;
  FLock.Free;
  FHeaders.Free;
  inherited;
end;

class function TAiTelemetry.Active: TAiTelemetry;
begin
  Result := FActive;
  if Assigned(Result) and not Result.FEnabled then
    Result := nil;
end;

procedure TAiTelemetry.SetEnabled(const Value: Boolean);
begin
  if FEnabled = Value then
    Exit;
  FEnabled := Value;
  if csDesigning in ComponentState then
    Exit;
  if FEnabled then
  begin
    FActive := Self; // last enabled instance wins
    StartWorker;
  end
  else
  begin
    if FActive = Self then
      FActive := nil;
    StopWorker;
  end;
end;

procedure TAiTelemetry.SetHeaders(const Value: TStrings);
begin
  FHeaders.Assign(Value);
end;

procedure TAiTelemetry.StartWorker;
begin
  if Assigned(FWorker) then
    Exit;
  FStopEvent.ResetEvent;
  FWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      while FStopEvent.WaitFor(Cardinal(FFlushIntervalMs)) = wrTimeout do
      begin
        try
          ExportPending;
        except
          // never kill the exporter thread
        end;
      end;
    end);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TAiTelemetry.StopWorker;
begin
  if not Assigned(FWorker) then
    Exit;
  FStopEvent.SetEvent;
  FWorker.WaitFor;
  FreeAndNil(FWorker);
end;

procedure TAiTelemetry.DoLog(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, AMsg);
end;

// --- stack of active spans per thread (automatic nesting) ---

procedure TAiTelemetry.PushThreadSpan(ASpan: TAiSpan);
var
  Stack: TStack<TAiSpan>;
begin
  FLock.Enter;
  try
    if not FThreadStacks.TryGetValue(ASpan.FOwnerThreadId, Stack) then
    begin
      Stack := TStack<TAiSpan>.Create;
      FThreadStacks.Add(ASpan.FOwnerThreadId, Stack);
    end;
    Stack.Push(ASpan);
  finally
    FLock.Leave;
  end;
end;

procedure TAiTelemetry.PopThreadSpan(ASpan: TAiSpan);
var
  Stack: TStack<TAiSpan>;
begin
  FLock.Enter;
  try
    if FThreadStacks.TryGetValue(ASpan.FOwnerThreadId, Stack) then
      if (Stack.Count > 0) and (Stack.Peek = ASpan) then
        Stack.Pop;
    // If the closed span is not the top (out-of-order closures across threads),
    // we simply don't touch the stack: the cost is less accurate parentage.
  finally
    FLock.Leave;
  end;
end;

function TAiTelemetry.PeekThreadSpan: TAiSpan;
var
  Stack: TStack<TAiSpan>;
begin
  Result := nil;
  FLock.Enter;
  try
    if FThreadStacks.TryGetValue(TThread.CurrentThread.ThreadID, Stack) then
      if Stack.Count > 0 then
        Result := Stack.Peek;
  finally
    FLock.Leave;
  end;
end;

function TAiTelemetry.StartSpan(const AName: string; AKind: TAiSpanKind;
  const ATraceParent: string): TAiSpan;
var
  Parent: TAiSpan;
  RemoteTrace, RemoteSpan: string;
begin
  Result := TAiSpan.Create(AName, AKind);
  if (ATraceParent <> '') and ParseTraceParent(ATraceParent, RemoteTrace, RemoteSpan) then
  begin
    // Continue a remote trace (e.g., traceparent received via _meta MCP)
    Result.FTraceId := RemoteTrace;
    Result.FParentSpanId := RemoteSpan;
  end
  else
  begin
    Parent := PeekThreadSpan;
    if Assigned(Parent) then
    begin
      Result.FTraceId := Parent.FTraceId;
      Result.FParentSpanId := Parent.FSpanId;
    end;
  end;
  PushThreadSpan(Result);
end;

procedure TAiTelemetry.EndSpan(ASpan: TAiSpan; const AErrorMsg: string);
begin
  if not Assigned(ASpan) then
    Exit;
  ASpan.FEndUnixNano := NowUnixNano;
  if AErrorMsg <> '' then
    ASpan.SetError(AErrorMsg);
  PopThreadSpan(ASpan);
  FLock.Enter;
  try
    if FPending.Count < FMaxBatchSize * 10 then
      FPending.Add(ASpan) // the list takes ownership
    else
    begin
      Inc(FDroppedSpans); // backpressure: collector down and queue full
      ASpan.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAiTelemetry.Flush;
begin
  ExportPending;
end;

function TAiTelemetry.BuildOtlpPayload(ABatch: TObjectList<TAiSpan>): TJSONObject;
var
  ResourceSpans, ScopeSpans, Resource, Scope, SpanObj, StatusObj, AttrVal: TJSONObject;
  RsArray, SsArray, SpansArray, ResAttrs: TJSONArray;
  Span: TAiSpan;
  KindVal: Integer;
begin
  // OTLP/JSON structure: resourceSpans -> scopeSpans -> spans
  Result := TJSONObject.Create;
  RsArray := TJSONArray.Create;
  Result.AddPair('resourceSpans', RsArray);

  ResourceSpans := TJSONObject.Create;
  RsArray.AddElement(ResourceSpans);

  Resource := TJSONObject.Create;
  ResourceSpans.AddPair('resource', Resource);
  ResAttrs := TJSONArray.Create;
  Resource.AddPair('attributes', ResAttrs);
  AttrVal := TJSONObject.Create;
  AttrVal.AddPair('stringValue', FServiceName);
  ResAttrs.AddElement(TJSONObject.Create
    .AddPair('key', 'service.name')
    .AddPair('value', AttrVal));

  SsArray := TJSONArray.Create;
  ResourceSpans.AddPair('scopeSpans', SsArray);
  ScopeSpans := TJSONObject.Create;
  SsArray.AddElement(ScopeSpans);
  Scope := TJSONObject.Create;
  Scope.AddPair('name', OTEL_SCOPE_NAME);
  Scope.AddPair('version', OTEL_SCOPE_VERSION);
  ScopeSpans.AddPair('scope', Scope);

  SpansArray := TJSONArray.Create;
  ScopeSpans.AddPair('spans', SpansArray);

  for Span in ABatch do
  begin
    SpanObj := TJSONObject.Create;
    SpanObj.AddPair('traceId', Span.FTraceId);
    SpanObj.AddPair('spanId', Span.FSpanId);
    if Span.FParentSpanId <> '' then
      SpanObj.AddPair('parentSpanId', Span.FParentSpanId);
    SpanObj.AddPair('name', Span.FName);
    case Span.FKind of
      skInternal: KindVal := 1;
      skServer:   KindVal := 2;
      skClient:   KindVal := 3;
      skProducer: KindVal := 4;
    else
      KindVal := 5; // skConsumer
    end;
    SpanObj.AddPair('kind', TJSONNumber.Create(KindVal));
    SpanObj.AddPair('startTimeUnixNano', IntToStr(Span.FStartUnixNano));
    SpanObj.AddPair('endTimeUnixNano', IntToStr(Span.FEndUnixNano));
    SpanObj.AddPair('attributes', TJSONArray(Span.FAttributes.Clone));
    StatusObj := TJSONObject.Create;
    if Span.FHasError then
    begin
      StatusObj.AddPair('code', TJSONNumber.Create(2)); // STATUS_CODE_ERROR
      StatusObj.AddPair('message', Span.FErrorMessage);
    end
    else
      StatusObj.AddPair('code', TJSONNumber.Create(1)); // STATUS_CODE_OK
    SpanObj.AddPair('status', StatusObj);
    SpansArray.AddElement(SpanObj);
  end;
end;

procedure TAiTelemetry.ExportPending;
var
  Batch: TObjectList<TAiSpan>;
  Payload: TJSONObject;
  Http: THTTPClient;
  Body: TStringStream;
  Resp: IHTTPResponse;
  i: Integer;
  LHeaders: TNetHeaders;
begin
  // Take the batch under lock and release quickly
  FLock.Enter;
  try
    if FPending.Count = 0 then
      Exit;
    Batch := FPending;
    FPending := TObjectList<TAiSpan>.Create(True);
  finally
    FLock.Leave;
  end;

  try
    Payload := BuildOtlpPayload(Batch);
    try
      Http := THTTPClient.Create;
      try
        Http.ConnectionTimeout := 3000;
        Http.ResponseTimeout := 5000;
        Http.ContentType := 'application/json';
        LHeaders := [];
        for i := 0 to FHeaders.Count - 1 do
          if FHeaders.Names[i] <> '' then
            LHeaders := LHeaders + [TNetHeader.Create(FHeaders.Names[i], FHeaders.ValueFromIndex[i])];
        Body := TStringStream.Create(Payload.ToJSON, TEncoding.UTF8);
        try
          Resp := Http.Post(FEndpoint, Body, nil, LHeaders);
          if (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
            DoLog(Format('OTLP export failed: HTTP %d %s', [Resp.StatusCode, Resp.StatusText]))
          else
            DoLog(Format('OTLP export: %d spans', [Batch.Count]));
        finally
          Body.Free;
        end;
      finally
        Http.Free;
      end;
    finally
      Payload.Free;
    end;
  except
    on E: Exception do
      // Collector down: batch is discarded (telemetry is best-effort)
      DoLog('OTLP export exception: ' + E.Message);
  end;
  Batch.Free;
end;

// ----------------------------------------------------------------------------
// No-op-safe helpers
// ----------------------------------------------------------------------------

function AiSpanStart(const AName: string; AKind: TAiSpanKind; const ATraceParent: string): TAiSpan;
var
  T: TAiTelemetry;
begin
  Result := nil;
  T := TAiTelemetry.Active;
  if Assigned(T) then
    try
      Result := T.StartSpan(AName, AKind, ATraceParent);
    except
      Result := nil; // telemetry must never break the instrumented flow
    end;
end;

procedure AiSpanEnd(ASpan: TAiSpan; const AErrorMsg: string);
var
  T: TAiTelemetry;
begin
  if not Assigned(ASpan) then
    Exit;
  T := TAiTelemetry.Active;
  if Assigned(T) then
    try
      T.EndSpan(ASpan, AErrorMsg);
    except
      // best-effort
    end
  else
    ASpan.Free; // the instance was disabled between Start and End
end;

procedure AiSpanAttr(ASpan: TAiSpan; const AKey, AValue: string);
begin
  if Assigned(ASpan) then
    ASpan.SetAttribute(AKey, AValue);
end;

procedure AiSpanAttr(ASpan: TAiSpan; const AKey: string; AValue: Int64);
begin
  if Assigned(ASpan) then
    ASpan.SetAttribute(AKey, AValue);
end;

procedure AiSpanAttr(ASpan: TAiSpan; const AKey: string; AValue: Boolean);
begin
  if Assigned(ASpan) then
    ASpan.SetAttribute(AKey, AValue);
end;

function AiSpanTraceParent(ASpan: TAiSpan): string;
begin
  if Assigned(ASpan) then
    Result := ASpan.TraceParent
  else
    Result := '';
end;

end.
