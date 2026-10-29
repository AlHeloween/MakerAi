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
    WriteLn('    Cache HIT        : ', CachedTokens, ' tokens reutilizados')
  else
    WriteLn('    Cache HIT        : 0');
  if CacheWriteTokens > 0 then
    WriteLn('    Cache MISS/WRITE : ', CacheWriteTokens, ' tokens guardados en cache')
  else
    WriteLn('    Cache MISS/WRITE : 0');
  WriteLn('    Completion tokens: ', CompletionTokens);
end;

procedure TCacheMonitor.PrintCitations;
var
  I: Integer;
begin
  if CitationTexts.Count = 0 then
    WriteLn('  (sin citas en esta respuesta)')
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
    'Eres un asistente experto en documentacion tecnica de software. ' +
    'Tu objetivo es analizar documentos, extraer informacion clave, ' +
    'y responder preguntas con precision citando las secciones relevantes. ' +
    'Cuando se te proporcione documentacion, lee cada seccion cuidadosamente.';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
  Resp: string;
begin
  Separador('Demo A — Claude Prompt Caching');
  WriteLn('Provider: Claude  |  Modelo: claude-sonnet-4-6');
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
    Mon.Print('Llamada 1');
    WriteLn('  Response: ', Copy(Resp, 1, 100), '...');

    WriteLn;
    WriteLn('--- Call 2 (Cache HIT expected) ---');
    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Cómo analizas los documentos?', 'user', []);
    Mon.Print('Llamada 2');

    WriteLn;
    WriteLn('--- Call 3 (Cache HIT confirmed) ---');
    Mon.Reset;
    Resp := Conn.AddMessageAndRun(
      '¿Qué tipo de información extraes de los documentos?', 'user', []);
    Mon.Print('Llamada 3');
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
    'Guia de MakerAI v3.4' + #13#10 +
    #13#10 +
    'Seccion 1: Instalacion' + #13#10 +
    'Compilar los paquetes en este orden:' + #13#10 +
    '1. MakerAI.dpk (nucleo runtime, aprox 98 unidades)' + #13#10 +
    '2. MakerAi.RAG.Drivers.dpk (conectores de base de datos PostgreSQL)' + #13#10 +
    '3. MakerAi.UI.dpk (componentes visuales FMX)' + #13#10 +
    '4. MakerAiDsg.dpk (editores de diseno, requiere VCL y DesignIDE)' + #13#10 +
    #13#10 +
    'Seccion 2: Providers soportados' + #13#10 +
    'MakerAI soporta estos providers de LLM: OpenAI, Claude, Gemini,' + #13#10 +
    'Ollama, Groq, DeepSeek, Kimi, Grok, Mistral, Cohere y LM Studio.' + #13#10 +
    'Use TAiChatConnection con la propiedad DriverName para cambiar providers.' + #13#10 +
    #13#10 +
    'Seccion 3: Agentes autonomos' + #13#10 +
    'Los agentes en MakerAI usan el patron ReAct (Razonar-Actuar-Observar).' + #13#10 +
    'TAIAgentManager orquesta nodos TAIAgentsNode conectados por enlaces.' + #13#10 +
    'Los nodos pueden ejecutarse en paralelo (lmFanout) o secuencialmente.' + #13#10 +
    #13#10 +
    'Seccion 4: Prompt Caching' + #13#10 +
    'Claude requiere caching explicito con CacheSystemPrompt := True.' + #13#10 +
    'El system prompt debe superar 2 048 tokens (claude-sonnet-4-6).' + #13#10 +
    'OpenAI y DeepSeek aplican caching automatico en prompts >= 1 024 tokens.' + #13#10 +
    'El caching reduce costos hasta 90% y latencia hasta 85%.';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
  MF:   TAiMediaFile;
  B64:  string;
  Resp: string;
begin
  Separador('Demo B — Claude Citations');
  WriteLn('Provider: Claude  |  Modelo: claude-sonnet-4-6');
  WriteLn('Attached document with EnableCitations := True.');
  WriteLn('The model quotes verbatim the fragment supporting each answer.');
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  Mon  := TCacheMonitor.Create;
  MF   := TAiMediaFile.Create;
  try
    SetupConn(Conn, 'Claude', 'claude-sonnet-4-6', '@CLAUDE_API_KEY');
    Conn.SystemPrompt.Text :=
      'Eres un asistente de documentacion tecnica. ' +
      'Responde citando textualmente el documento cuando sea relevante.';
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
    'Eres un experto en inteligencia artificial aplicada al desarrollo de software. ' +
    'Tu rol es responder preguntas tecnicas con precision y claridad. ' +
    'Siempre proporciona ejemplos practicos cuando sea posible. ';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
begin
  Separador('Demo C — OpenAI Auto Caching');
  WriteLn('Provider: OpenAI  |  Modelo: gpt-5.4-mini');
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
    Conn.AddMessageAndRun('¿Qué es el machine learning?', 'user', []);
    Mon.Print('Llamada 1');

    WriteLn;
    WriteLn('--- Call 2 (automatic cache expected) ---');
    Mon.Reset;
    Conn.AddMessageAndRun('¿Qué es el deep learning?', 'user', []);
    Mon.Print('Llamada 2');
    if Mon.CachedTokens > 0 then
      WriteLn('  Cache activo: ', Mon.CachedTokens, ' tokens reutilizados (50% descuento)')
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
    'Eres un asistente especializado en analisis de codigo fuente Delphi y Pascal. ' +
    'Tienes profundo conocimiento del framework MakerAI y sus componentes. ' +
    'Ayudas a desarrolladores a integrar inteligencia artificial en aplicaciones Delphi. ';
var
  Conn: TAiChatConnection;
  Mon:  TCacheMonitor;
begin
  Separador('Demo D — DeepSeek Auto Caching');
  WriteLn('Provider: DeepSeek  |  Modelo: deepseek-chat');
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
    Conn.AddMessageAndRun('¿Cuáles son las ventajas de MakerAI?', 'user', []);
    Mon.Print('Llamada 1');

    WriteLn;
    WriteLn('--- Call 2 (shared prefix → cache expected) ---');
    Mon.Reset;
    Conn.AddMessageAndRun('¿Qué providers soporta MakerAI?', 'user', []);
    Mon.Print('Llamada 2');
    if Mon.CachedTokens > 0 then
      WriteLn('  Cache activo: ', Mon.CachedTokens, ' tokens reutilizados')
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
