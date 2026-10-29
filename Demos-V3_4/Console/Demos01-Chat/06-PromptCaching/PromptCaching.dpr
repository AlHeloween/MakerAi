program PromptCaching;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 01-Chat / 06-PromptCaching
// =============================================================================
// Verifies Prompt Caching support in Claude, OpenAI and DeepSeek.
//
// Concepts covered:
//   - Claude: CacheSystemPrompt + CacheTTL  → cache_read/write_input_tokens
//   - OpenAI: automatic (≥1024 tokens)     → cached_tokens in usage
//   - DeepSeek: automatic by prefix      → prompt_cache_hit_tokens in usage
//
// Observe in the output:
//   Call 1: cached_read=0, cache_write>0   (MISS: written to cache)
//   Call 2: cached_read>0, cache_write=0   (HIT:  read from cache)
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.DeepSeek,
  uMakerAi.Chat.Initializations;

// -----------------------------------------------------------------------------
// System prompt long enough to exceed the cache threshold:
//   claude-haiku-4-5  : minimum 4096 tokens (~16000 chars)
//   claude-sonnet-4-6 : minimum 2048 tokens (~8000 chars)
//   OpenAI / DeepSeek : minimum 1024 tokens (~4000 chars)
// -----------------------------------------------------------------------------
function BuildLongSystemPrompt: String;
const
  BLOQUE =
    'You are an expert assistant in artificial intelligence specialized in helping ' +
    'Delphi developers integrate LLMs into their applications with MakerAI Suite. ' +
    'You know in depth the models of OpenAI (GPT-4.1, o3, o4-mini, gpt-image-1), ' +
    'Anthropic Claude (Opus 4.7, Sonnet 4.6, Haiku 4.5), Google Gemini (2.5 Flash/Pro), ' +
    'DeepSeek (V3.2 chat, R1 reasoner), Groq (Llama-4, Kimi-K2, Qwen3), ' +
    'Mistral (Large, Magistral, devstral), Cohere (Command-A), xAI Grok (grok-3, grok-4). ' +
    'When you explain concepts you use examples in Delphi code using TAiChatConnection. ' +
    'You recommend the appropriate model according to: speed, cost, reasoning, multimodality, ' +
    'support for images/audio/video/PDF, or autonomous agents with function calling. ';
var
  I: Integer;
begin
  Result := '';
  for I := 1 to 30 do   // 30 * ~680 chars ≈ 20400 chars ≈ 5100 tokens
    Result := Result + BLOQUE;
end;

// -----------------------------------------------------------------------------
// Prints the token statistics of the last response
// -----------------------------------------------------------------------------
procedure PrintTokenStats(const Prefijo: String; Msgs: TAiChatMessages);
var
  Msg: TAiChatMessage;
begin
  if Msgs.Count = 0 then Exit;
  Msg := Msgs.Items[Msgs.Count - 1];
  Write(Prefijo);
  Write(Format('  prompt=%d  compl=%d',
    [Msg.Prompt_tokens, Msg.Completion_tokens]));
  if Msg.Cached_tokens > 0 then
    Write(Format('  [HIT cached_read=%d]', [Msg.Cached_tokens]))
  else
    Write('  [MISS cached_read=0]');
  if Msg.Cache_write_tokens > 0 then
    Write(Format('  [cache_write=%d]', [Msg.Cache_write_tokens]));
  Writeln;
end;

// =============================================================================
//  TEST CLAUDE — CacheSystemPrompt=True, CacheTTL='1h'
// =============================================================================
procedure TestClaude;
const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';
  PREGUNTA = 'What is the best model for analyzing extensive PDF documents?';
var
  Conn : TAiChatConnection;
  Resp : String;
begin
  Writeln('━━━ CLAUDE — CacheSystemPrompt + CacheTTL ━━━');
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';
    Conn.SystemPrompt.Text := BuildLongSystemPrompt;

    // Enable system prompt caching with extended TTL
    if Conn.AiChat is TAiClaudeChat then
    begin
      (Conn.AiChat as TAiClaudeChat).CacheSystemPrompt := True;
      (Conn.AiChat as TAiClaudeChat).CacheTTL          := '1h';
    end;

    // Call 1 — expect MISS: the system prompt is written to cache
    Writeln('  Call 1 (expecting MISS + cache_write):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

    Writeln;

    // Call 2 — expect HIT: the system prompt is already in cache
    Writeln('  Call 2 (expecting HIT):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

  finally
    Conn.Free;
  end;
  Writeln;
end;

// =============================================================================
//  TEST OPENAI — Automatic caching (no additional configuration)
// =============================================================================
procedure TestOpenAI;
const
  DRIVER  = 'OpenAI';
  MODEL   = 'gpt-4.1-mini';
  API_KEY = '@OPENAI_API_KEY';
  PREGUNTA = 'What is the best model for analyzing extensive PDF documents?';
var
  Conn : TAiChatConnection;
  Resp : String;
begin
  Writeln('━━━ OPENAI — Automatic caching ━━━');
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';
    Conn.SystemPrompt.Text := BuildLongSystemPrompt;

    // No additional configuration: OpenAI automatically caches prefixes ≥1024 tokens

    Writeln('  Call 1 (expecting MISS):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

    Writeln;

    Writeln('  Call 2 (expecting HIT):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

  finally
    Conn.Free;
  end;
  Writeln;
end;

// =============================================================================
//  TEST DEEPSEEK — Automatic caching by prefix
// =============================================================================
procedure TestDeepSeek;
const
  DRIVER  = 'DeepSeek';
  MODEL   = 'deepseek-chat';
  API_KEY = '@DEEPSEEK_API_KEY';
  PREGUNTA = 'What is the best model for analyzing extensive PDF documents?';
var
  Conn : TAiChatConnection;
  Resp : String;
begin
  Writeln('━━━ DEEPSEEK — Automatic caching by prefix ━━━');
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Params.Values['ApiKey']       := API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '256';
    Conn.SystemPrompt.Text := BuildLongSystemPrompt;

    // No configuration: DeepSeek automatically caches repeated prefixes

    Writeln('  Call 1 (expecting MISS):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

    Writeln;

    Writeln('  Call 2 (expecting HIT):');
    Conn.Messages.Clear;
    Resp := Conn.AddMessageAndRun(PREGUNTA, 'user', []);
    Writeln('  Response: ', Copy(Resp, 1, 80), '...');
    PrintTokenStats('  Tokens:', Conn.Messages);

  finally
    Conn.Free;
  end;
  Writeln;
end;

// =============================================================================
//  MAIN
// =============================================================================
begin
  Writeln('=== PromptCaching Demo — MakerAI Suite ===');
  Writeln('Verifies that cached_read > 0 in Call 2 of each provider.');
  Writeln('Note: cache HITs may take a few seconds to activate.');
  Writeln;
  try
    TestClaude;
    TestOpenAI;
    TestDeepSeek;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln('Press Enter to exit...');
  Readln;
end.
