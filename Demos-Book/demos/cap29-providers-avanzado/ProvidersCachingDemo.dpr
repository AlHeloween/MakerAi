program ProvidersCachingDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 29: Advanced Provider Features
// =============================================================================
// Demo A — Claude Prompt Caching
//   Long system prompt (>= 2048 tokens). First call: Cache MISS.
//   Second and third: Cache HIT. Shows cache_write_tokens vs cached_tokens.
//
// Demo B — Claude Citations
//   Attached document with EnableCitations := True. The model responds
//   annotating which document fragment supported each statement.
//
// Demo C — OpenAI Auto Caching
//   gpt-5.4-mini. No extra configuration. Automatic cache in prompts
//   >= 1024 tokens. Shows cached_tokens in second call.
//
// Demo D — DeepSeek Auto Caching
//   deepseek-chat. No extra configuration. Automatic cache with
//   repeated prefixes. Shows cached_tokens in second call.
//
// Required environment variables: CLAUDE_API_KEY, OPENAI_API_KEY,
//   DEEPSEEK_API_KEY (depending on the demos run).
// =============================================================================

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Net.HttpClient,            // IHTTPResponse
  System.NetEncoding,               // TNetEncoding.Base64
  uMakerAi.Core,                 // TAiMediaFile
  uMakerAi.Chat.Messages,        // TAiChatMessage, TAiMsgCitation
  uMakerAi.Chat.AiConnection,    // TAiChatConnection
  uMakerAi.Chat.Claude,          // TAiClaudeChat
  uMakerAi.Chat.Initializations; // auto-registra todos los drivers

// ---------------------------------------------------------------------------
//  TCacheMonitor — captures cache metrics from OnReceiveDataEnd
// ---------------------------------------------------------------------------

type
  TCacheMonitor = class
  public
    PromptTokens, CachedTokens, CacheWriteTokens, CompletionTokens: Integer;
    CitationTexts: TStringList;
    LastError: string;

    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
      aResponse: TJSONObject; aRole, aText: String);
    procedure OnError(Sender: TObject; const aError: string;
      aException: Exception; const aResponse: IHTTPResponse);
    procedure Print(const Lbl: string);
    procedure PrintCitations;
  end;

constructor TCacheMonitor.Create;
begin
  inherited;
  CitationTexts := TStringList.Create;
end;

destructor TCacheMonitor.Destroy;
begin
  CitationTexts.Free;
  inherited;
end;

procedure TCacheMonitor.Reset;
begin
  PromptTokens     := 0;
  CachedTokens     := 0;
  CacheWriteTokens := 0;
  CompletionTokens := 0;
  CitationTexts.Clear;
  LastError := '';
end;

procedure TCacheMonitor.OnError(Sender: TObject; const aError: string;
  aException: Exception; const aResponse: IHTTPResponse);
begin
  LastError := aError;
end;

procedure TCacheMonitor.OnDataEnd(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: String);
var
  I: Integer;
  Cit: TAiMsgCitation;
begin
  if aRole <> 'assistant' then Exit;
  PromptTokens     := aMsg.Prompt_tokens;
  CachedTokens     := aMsg.Cached_tokens;
  CacheWriteTokens := aMsg.Cache_write_tokens;
  CompletionTokens := aMsg.Completion_tokens;

  CitationTexts.Clear;
  if Assigned(aMsg.Citations) then
    for I := 0 to aMsg.Citations.Count - 1 do
    begin
      Cit := aMsg.Citations[I];
      if Cit.Text <> '' then
        CitationTexts.Add(Copy(Cit.Text, 1, 100));
    end;
end;

procedure TCacheMonitor.Print(const Lbl: string);
begin
  WriteLn('  [', Lbl, ']');
  WriteLn('    Prompt tokens    : ', PromptTokens);
  if CachedTokens > 0 then
    WriteLn('    Cache HIT        : ', CachedTokens, ' tokens reused')
  else
    WriteLn('    Cache HIT        : 0');
  if CacheWriteTokens > 0 then
    WriteLn('    Cache MISS/WRITE : ', CacheWriteTokens, ' tokens stored in cache')
  else
    WriteLn('    Cache MISS/WRITE : 0');
  WriteLn('    Completion tokens: ', CompletionTokens);
end;

procedure TCacheMonitor.PrintCitations;
var
  I: Integer;
begin
  if CitationTexts.Count = 0 then
    WriteLn('  (no citations in this response)')
  else
    for I := 0 to CitationTexts.Count - 1 do
      WriteLn(Format('  [%d] "%s"', [I + 1, CitationTexts[I]]));
end;

// ---------------------------------------------------------------------------
//  Common helpers
// ---------------------------------------------------------------------------

procedure Separador(const Titulo: string);
begin
  WriteLn;
  WriteLn(StringOfChar('=', 64));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('=', 64));
end;

procedure SetupConn(Conn: TAiChatConnection;
  const ADriver, AModel, AApiKey: string);
begin
  Conn.DriverName                    := ADriver;
  Conn.Model                         := AModel;
  Conn.Params.Values['ApiKey']       := AApiKey;
  Conn.Params.Values['Asynchronous'] := 'False';
end;

function BuildLongPrompt(const Base: string; Times: Integer): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 1 to Times do
      SB.AppendLine(Base);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo A — Claude Prompt Caching
// ---------------------------------------------------------------------------

procedure DemoA_ClaudePromptCaching;
const
  // ~270 chars x 40 repeticiones ≈ 10 800 chars ≈ 2 700 tokens (sobre el mínimo)
  BASE_SYS =
    'You are an expert assistant in software technical documentation. ' +
    'Your goal is to analyze documents, extract key information, ' +
    'and answer questions accurately citing the relevant sections. ' +
    'When documentation is provided, read each section carefully.';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
  Resp: string;
begin
  Separador('Demo A — Claude Prompt Caching');
  WriteLn('Provider: Claude  |  Model: claude-sonnet-4-6');
  WriteLn('Minimum threshold claude-sonnet-4-6: 2,048 system prompt tokens.');
  WriteLn('First call: Cache MISS → Cache_write_tokens > 0');
  WriteLn('Second/third: Cache HIT  → Cached_tokens > 0');
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  Mon  := TCacheMonitor.Create;
  try
    SetupConn(Conn, 'Claude', 'claude-sonnet-4-6', '@CLAUDE_API_KEY');
    Conn.SystemPrompt.Text := BuildLongPrompt(BASE_SYS, 40);
    Conn.OnReceiveDataEnd  := Mon.OnDataEnd;

    // Enable explicit caching of the system prompt in TAiClaudeChat
    (Conn.AiChat as TAiClaudeChat).CacheSystemPrompt := True;

    WriteLn('--- Call 1 (Cache MISS expected) ---');
    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Cuál es tu función principal como asistente?', 'user', []);
    Mon.Print('Call 1');
    WriteLn('  Response: ', Copy(Resp, 1, 100), '...');

    WriteLn;
    WriteLn('--- Call 2 (Cache HIT expected) ---');
    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Cómo analizas los documentos?', 'user', []);
    Mon.Print('Call 2');

    WriteLn;
    WriteLn('--- Call 3 (Cache HIT confirmed) ---');
    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Qué tipo de información extraes de los documentos?', 'user', []);
    Mon.Print('Call 3');
  finally
    Conn.Free;
    Mon.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo B — Claude Citations
// ---------------------------------------------------------------------------

procedure DemoB_ClaudeCitations;
const
  DOC_TEXT =
    'MakerAI v3.4 Guide' + #13#10 +
    #13#10 +
    'Section 1: Installation' + #13#10 +
    'Compile the packages in this order:' + #13#10 +
    '1. MakerAI.dpk (runtime core, approx. 98 units)' + #13#10 +
    '2. MakerAi.RAG.Drivers.dpk (PostgreSQL database connectors)' + #13#10 +
    '3. MakerAi.UI.dpk (FMX visual components)' + #13#10 +
    '4. MakerAiDsg.dpk (design editors, requires VCL and DesignIDE)' + #13#10 +
    #13#10 +
    'Section 2: Supported providers' + #13#10 +
    'MakerAI supports these LLM providers: OpenAI, Claude, Gemini,' + #13#10 +
    'Ollama, Groq, DeepSeek, Kimi, Grok, Mistral, Cohere and LM Studio.' + #13#10 +
    'Use TAiChatConnection with the DriverName property to change providers.' + #13#10 +
    #13#10 +
    'Section 3: Autonomous agents' + #13#10 +
    'Agents in MakerAI use the ReAct pattern (Reason-Act-Observe).' + #13#10 +
    'TAIAgentManager orchestrates TAIAgentsNode nodes connected by links.' + #13#10 +
    'Nodes can run in parallel (lmFanout) or sequentially.' + #13#10 +
    #13#10 +
    'Section 4: Prompt Caching' + #13#10 +
    'Claude requires explicit caching with CacheSystemPrompt := True.' + #13#10 +
    'The system prompt must exceed 2,048 tokens (claude-sonnet-4-6).' + #13#10 +
    'OpenAI and DeepSeek apply automatic caching to prompts >= 1,024 tokens.' + #13#10 +
    'Caching reduces costs by up to 90% and latency by up to 85%.';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
  MF:   TAiMediaFile;
  B64:  string;
  Resp: string;
begin
  Separador('Demo B — Claude Citations');
  WriteLn('Provider: Claude  |  Model: claude-sonnet-4-6');
  WriteLn('Attached document with EnableCitations := True.');
  WriteLn('The model quotes verbatim the fragment supporting each answer.');
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  Mon  := TCacheMonitor.Create;
  MF   := TAiMediaFile.Create;
  try
    SetupConn(Conn, 'Claude', 'claude-sonnet-4-6', '@CLAUDE_API_KEY');
    Conn.SystemPrompt.Text :=
      'You are a technical documentation assistant. ' +
      'Answer by quoting the document verbatim when relevant.';
    Conn.OnReceiveDataEnd := Mon.OnDataEnd;
    Conn.OnError          := Mon.OnError;

    // Prepare document: encode in Base64 and configure properties
    B64 := TNetEncoding.Base64.Encode(DOC_TEXT);
    MF.LoadFromBase64('guia-makerai.txt', B64);
    MF.EnableCitations := True;  // Claude anotará las citas en la respuesta
    MF.CacheControl    := True;  // también guarda el documento en cache

    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Cuántos paquetes hay que compilar y en qué orden? ' +
      '¿Qué providers soporta MakerAI? ' +
      '¿Cómo funciona el prompt caching?',
      'user', [MF]);

    WriteLn('Model response:');
    if Resp <> '' then
      WriteLn(Resp)
    else if Mon.LastError <> '' then
      WriteLn('  [ERROR API]: ', Copy(Mon.LastError, 1, 200))
    else
      WriteLn('  (empty response)');

    WriteLn;
    WriteLn('--- Extracted citations (', Mon.CitationTexts.Count, ') ---');
    Mon.PrintCitations;
    Mon.Print('Tokens');
  finally
    // MF is a property of the message (TObjectList OwnsObjects) — do not free here
    Conn.Free;
    Mon.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo C — OpenAI Auto Caching
// ---------------------------------------------------------------------------

procedure DemoC_OpenAIAutoCaching;
const
  // ~230 chars x 30 repeticiones ≈ 6 900 chars ≈ 1 725 tokens (sobre el mínimo)
  BASE_SYS =
    'You are an expert in artificial intelligence applied to software development. ' +
    'Your role is to answer technical questions with precision and clarity. ' +
    'Always provide practical examples when possible. ';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
begin
  Separador('Demo C — OpenAI Auto Caching');
  WriteLn('Provider: OpenAI  |  Model: gpt-5.4-mini');
  WriteLn('Caching is automatic: no extra configuration required.');
  WriteLn('Threshold: >= 1,024 input tokens. Cache HIT reduces cost by 50%.');
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  Mon  := TCacheMonitor.Create;
  try
    SetupConn(Conn, 'OpenAI', 'gpt-5.4-mini', '@OPENAI_API_KEY');
    Conn.SystemPrompt.Text := BuildLongPrompt(BASE_SYS, 30);
    Conn.OnReceiveDataEnd  := Mon.OnDataEnd;

    WriteLn('--- Call 1 (no cache yet) ---');
    Mon.Reset;
    Conn.AddMessageAndRun('What is machine learning?', 'user', []);
    Mon.Print('Call 1');

    WriteLn;
    WriteLn('--- Call 2 (automatic cache expected) ---');
    Mon.Reset;
    Conn.AddMessageAndRun('What is deep learning?', 'user', []);
    Mon.Print('Call 2');
    if Mon.CachedTokens > 0 then
      WriteLn('  Cache active: ', Mon.CachedTokens, ' tokens reused (50% discount)')
    else
      WriteLn('  Cache not active yet (may take a few seconds to activate)');
  finally
    Conn.Free;
    Mon.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Demo D — DeepSeek Auto Caching
// ---------------------------------------------------------------------------

procedure DemoD_DeepSeekAutoCaching;
const
  BASE_SYS =
    'You are an assistant specialized in analyzing Delphi and Pascal source code. ' +
    'You have deep knowledge of the MakerAI framework and its components. ' +
    'You help developers integrate artificial intelligence into Delphi applications. ';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
begin
  Separador('Demo D — DeepSeek Auto Caching');
  WriteLn('Provider: DeepSeek  |  Model: deepseek-chat');
  WriteLn('Caching is automatic for repeated prefixes.');
  WriteLn('Cost on cache HIT: 0.1 USD/M tokens (vs 0.27 without cache).');
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  Mon  := TCacheMonitor.Create;
  try
    SetupConn(Conn, 'DeepSeek', 'deepseek-chat', '@DEEPSEEK_API_KEY');
    Conn.SystemPrompt.Text := BuildLongPrompt(BASE_SYS, 30);
    Conn.OnReceiveDataEnd  := Mon.OnDataEnd;

    WriteLn('--- Call 1 ---');
    Mon.Reset;
    Conn.AddMessageAndRun('What are the advantages of MakerAI?', 'user', []);
    Mon.Print('Call 1');

    WriteLn;
    WriteLn('--- Call 2 (shared prefix → cache expected) ---');
    Mon.Reset;
    Conn.AddMessageAndRun('Which providers does MakerAI support?', 'user', []);
    Mon.Print('Call 2');
    if Mon.CachedTokens > 0 then
      WriteLn('  Cache active: ', Mon.CachedTokens, ' tokens reused')
    else
      WriteLn('  Cache not active in this session');
  finally
    Conn.Free;
    Mon.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Main
// ---------------------------------------------------------------------------

var
  Opcion: Char;

begin
  try
    WriteLn('================================================================');
    WriteLn('  MakerAI — Cap 29: Caracteristicas Avanzadas por Provider');
    WriteLn('================================================================');
    WriteLn;
    WriteLn('  A — Claude Prompt Caching  (CLAUDE_API_KEY)');
    WriteLn('  B — Claude Citations        (CLAUDE_API_KEY)');
    WriteLn('  C — OpenAI Auto Caching     (OPENAI_API_KEY)');
    WriteLn('  D — DeepSeek Auto Caching   (DEEPSEEK_API_KEY)');
    WriteLn('  T — All demos');
    WriteLn;
    Write('  Option [A/B/C/D/T]: ');
    Readln(Opcion);
    Opcion := UpCase(Opcion);

    case Opcion of
      'A': DemoA_ClaudePromptCaching;
      'B': DemoB_ClaudeCitations;
      'C': DemoC_OpenAIAutoCaching;
      'D': DemoD_DeepSeekAutoCaching;
      'T':
      begin
        DemoA_ClaudePromptCaching;
        DemoB_ClaudeCitations;
        DemoC_OpenAIAutoCaching;
        DemoD_DeepSeekAutoCaching;
      end;
    else
      WriteLn('Unrecognized option: ', Opcion);
    end;

    WriteLn;
    WriteLn(StringOfChar('-', 64));
    WriteLn('  Demo completed. Press ENTER to exit...');
    Readln;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('ERROR: ', E.ClassName, ': ', E.Message);
      WriteLn('Press ENTER to exit...');
      Readln;
    end;
  end;
end.
