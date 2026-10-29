program ChatToolsDemo;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — Chapter 20: Community ChatTools
// Demo: Four usage modes of ChatTools
// =============================================================================
//
//   Demo 4: Instantiate tools and show properties (without API key)
//   Demo 1: Direct search without LLM (requires TAVILY_API_KEY)
//   Demo 2: Direct vision without LLM   (requires OPENAI_API_KEY + image)
//   Demo 3: Full integration with Ollama + ChatTools (requires both keys)
//
// Direct call pattern (without LLM):
//   ResMsg := TAiChatMessage.Create;
//   AskMsg := TAiChatMessage.Create;
//   (Tool as IInterface).ExecuteXxx(input, ResMsg, AskMsg);
//   WriteLn(ResMsg.Prompt);
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Ollama,           // auto-registra driver 'Ollama'
  uMakerAi.Chat.Tools,            // IAiWebSearchTool, IAiVisionTool, IAiSpeechTool
  uMakerAi.ChatTools.Tavily,
  uMakerAi.ChatTools.OpenAIVision,
  uMakerAi.ChatTools.OpenAISpeech;

// ---------- Demo 1: Direct search without LLM ----------
procedure DemoDirectSearch;
var
  Search: TAiTavilyWebSearchTool;
  ResMsg: TAiChatMessage;
  AskMsg: TAiChatMessage;
  Resultado: string;
begin
  WriteLn('=== DEMO 1: Direct search (without LLM) ===');
  WriteLn('Tool: TAiTavilyWebSearchTool');
  WriteLn;

  Search := TAiTavilyWebSearchTool.Create(nil);
  ResMsg := TAiChatMessage.Create;
  AskMsg := TAiChatMessage.Create;
  try
    Search.ApiKey     := '@TAVILY_API_KEY';
    Search.MaxResults := 3;

    WriteLn('Searching: "últimas novedades Delphi 2025"');
    // ExecuteSearch es protected → se invoca via interfaz
    (Search as IAiWebSearchTool).ExecuteSearch(
      'últimas novedades Delphi 2025', ResMsg, AskMsg);

    Resultado := ResMsg.Prompt;

    WriteLn('Results (first 600 chars):');
    if Length(Resultado) > 600 then
      WriteLn(Copy(Resultado, 1, 600), #13#10'...')
    else
      WriteLn(Resultado);
  finally
    ResMsg.Free;
    AskMsg.Free;
    Search.Free;
  end;
end;

// ---------- Demo 2: Direct vision without LLM ----------
procedure DemoDirectVision(const ImagePath: string);
var
  Vision: TAiOpenAIVisionTool;
  Media : TAiMediaFile;
  ResMsg: TAiChatMessage;
  AskMsg: TAiChatMessage;
begin
  WriteLn('=== DEMO 2: Direct vision (without LLM) ===');
  WriteLn('Tool: TAiOpenAIVisionTool');
  WriteLn;

  if not FileExists(ImagePath) then
  begin
    WriteLn('Image not found: ', ImagePath);
    WriteLn('(An image .jpg or .png is required for this demo)');
    Exit;
  end;

  Vision := TAiOpenAIVisionTool.Create(nil);
  Media  := TAiMediaFile.Create;
  ResMsg := TAiChatMessage.Create;
  AskMsg := TAiChatMessage.Create;
  try
    Vision.ApiKey    := '@OPENAI_API_KEY';
    Vision.Detail    := 'high';
    Vision.MaxTokens := 512;

    Media.LoadFromFile(ImagePath);
    WriteLn('Analyzing image: ', ImagePath);

    // ExecuteImageDescription es protected → se invoca via interfaz
    (Vision as IAiVisionTool).ExecuteImageDescription(Media, ResMsg, AskMsg);

    WriteLn('Description:');
    WriteLn(ResMsg.Prompt);
  finally
    ResMsg.Free;
    AskMsg.Free;
    Vision.Free;
    Media.Free;
  end;
end;

// ---------- Demo 3: Full integration with TAiChatConnection ----------
procedure DemoIntegrated;
var
  AiConn: TAiChatConnection;
  Search: TAiTavilyWebSearchTool;
  Speech: TAiOpenAISpeechTool;
  Resp  : string;
begin
  WriteLn('=== DEMO 3: Full integration (Ollama + ChatTools) ===');
  WriteLn('Base model: Ollama llama3.2 (local, no cost)');
  WriteLn('ChatTools: Tavily (search) + OpenAI Speech');
  WriteLn;

  AiConn := TAiChatConnection.Create(nil);
  Search := TAiTavilyWebSearchTool.Create(nil);
  Speech := TAiOpenAISpeechTool.Create(nil);
  try
    // Modelo base: Ollama local
    AiConn.DriverName := 'Ollama';
    AiConn.Model      := 'llama3.2';
    AiConn.Params.Values['Url']          := 'http://localhost:11434/';
    AiConn.Params.Values['Asynchronous'] := 'False';

    // ChatTool 1: búsqueda web — activa el gap cap_WebSearch automáticamente
    Search.ApiKey        := '@TAVILY_API_KEY';
    AiConn.WebSearchTool := Search;

    // ChatTool 2: voz
    Speech.ApiKey     := '@OPENAI_API_KEY';
    Speech.Language   := 'es';
    AiConn.SpeechTool := Speech;

    WriteLn('Question: "What''s new in Delphi 13 Florence?"');
    WriteLn('(Gap Analysis will detect cap_WebSearch and call Tavily)');
    WriteLn;

    Resp := AiConn.AddMessageAndRun(
      '¿Qué novedades trae Delphi 13 Florence? Busca información actualizada.',
      'user', []);

    WriteLn('Model response:');
    WriteLn(Resp);
  finally
    AiConn.WebSearchTool := nil;  // evitar doble liberación
    AiConn.SpeechTool    := nil;
    AiConn.Free;
    Search.Free;
    Speech.Free;
  end;
end;

// ---------- Demo 4: Instantiate and show available tools ----------
procedure DemoShowTools;
var
  Search: TAiTavilyWebSearchTool;
  Vision: TAiOpenAIVisionTool;
  Speech: TAiOpenAISpeechTool;
begin
  WriteLn('=== DEMO 4: Instantiate and show available tools ===');
  WriteLn;

  Search := TAiTavilyWebSearchTool.Create(nil);
  Vision := TAiOpenAIVisionTool.Create(nil);
  Speech := TAiOpenAISpeechTool.Create(nil);
  try
    Search.ApiKey := '@TAVILY_API_KEY';
    Vision.ApiKey := '@OPENAI_API_KEY';
    Speech.ApiKey := '@OPENAI_API_KEY';

    WriteLn('Tools instantiated correctly:');
    WriteLn('  [WebSearch] ', Search.ClassName, ' — MaxResults: ', Search.MaxResults);
    WriteLn('  [Vision]    ', Vision.ClassName, ' — Detail: ',     Vision.Detail);
    WriteLn('  [Speech]    ', Speech.ClassName, ' — Language: "',  Speech.Language, '" (empty=autodetect)');
    WriteLn;
    WriteLn('Assignment pattern to TAiChatConnection:');
    WriteLn('  AiConn.WebSearchTool := Search;  // activates gap cap_WebSearch');
    WriteLn('  AiConn.VisionTool    := Vision;  // activates gap cap_Image');
    WriteLn('  AiConn.SpeechTool    := Speech;  // activates gap cap_Speech');
    WriteLn;
    WriteLn('Direct call pattern without LLM:');
    WriteLn('  ResMsg := TAiChatMessage.Create;');
    WriteLn('  AskMsg := TAiChatMessage.Create;');
    WriteLn('  (Search as IAiWebSearchTool).ExecuteSearch(query, ResMsg, AskMsg);');
    WriteLn('  WriteLn(ResMsg.Prompt);');
  finally
    Search.Free;
    Vision.Free;
    Speech.Free;
  end;
end;

// =============================================================================
begin
  WriteLn('=================================================');
  WriteLn('  Cap. 20 — ChatTools Comunitarios: Demos');
  WriteLn('=================================================');
  WriteLn;

  try
    // Demo 4: without API keys
    DemoShowTools;
    WriteLn;

    // Demo 1: requires TAVILY_API_KEY
    if GetEnvironmentVariable('TAVILY_API_KEY') <> '' then
    begin
      DemoDirectSearch;
      WriteLn;
    end
    else
      WriteLn('SKIP Demo 1: TAVILY_API_KEY not configured' + sLineBreak);

    // Demo 2: requires OPENAI_API_KEY + test image
    if GetEnvironmentVariable('OPENAI_API_KEY') <> '' then
    begin
      DemoDirectVision('test_image.jpg');
      WriteLn;
    end
    else
      WriteLn('SKIP Demo 2: OPENAI_API_KEY not configured' + sLineBreak);

    // Demo 3: requires both keys + Ollama running
    if (GetEnvironmentVariable('TAVILY_API_KEY') <> '') and
       (GetEnvironmentVariable('OPENAI_API_KEY') <> '') then
    begin
      Write('Run Demo 3 (Ollama+ChatTools integration)? [S/N]: ');
      var LResp: string;
      ReadLn(LResp);
      if SameText(Trim(LResp), 'S') then
        DemoIntegrated;
    end
    else
      WriteLn('SKIP Demo 3: requires TAVILY_API_KEY and OPENAI_API_KEY');

  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
    end;
  end;

  WriteLn;
  WriteLn('=================================================');
  WriteLn('  Presiona Enter para salir...');
  ReadLn;
end.
