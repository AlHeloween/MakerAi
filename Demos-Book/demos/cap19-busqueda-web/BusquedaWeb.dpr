program BusquedaWeb;

{$APPTYPE CONSOLE}

// =============================================================================
// MakerAI — Chapter 19: Web Search and External Tools
// Demo: Three web search modalities
// =============================================================================
//
//   A) Native  — Gemini with integrated Google Search
//               ModelCaps=[cap_WebSearch] → the model searches by itself
//               Requires: GEMINI_API_KEY
//
//   B) Bridge  — Tavily + Gemini via gap analysis
//               ModelCaps=[] + SessionCaps=[cap_WebSearch] + WebSearchTool=Tavily
//               MakerAI detects the gap → Tavily searches → Gemini synthesizes
//               Requires: GEMINI_API_KEY + TAVILY_API_KEY
//
//   C) Direct  — Tavily without LLM (direct call to the tool)
//               Without TAiChatConnection — immediate result, no LLM tokens
//               Requires: TAVILY_API_KEY
//
// Prerequisite: MakerAI ChatTools package installed.
//   Option A: install uMakerAi.ChatTools.bpl as a package in the IDE.
//   Option B: add AiMaker.ChatTools\Source\Web to the IDE Library Path.
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.Tools,       // IAiWebSearchTool
  uMakerAi.Chat.Gemini,      // auto-registra driver 'Gemini' en el factory
  uMakerAi.ChatTools.Tavily; // TAiTavilyWebSearchTool — paquete ChatTools

const
  MODEL_GEMINI   = 'gemini-2.0-flash';
  QUERY_DELPHI   = 'Delphi programming language 2026 Embarcadero news features';
  QUERY_PRECIOS  = 'Bitcoin BTC price today USD current value';

// =============================================================================

function KeyPresente(const EnvVar: string): Boolean;
begin
  Result := GetEnvironmentVariable(EnvVar) <> '';
end;

procedure Separador;
begin
  WriteLn(StringOfChar('─', 64));
end;

// =============================================================================
//  A) Búsqueda NATIVA — Gemini con Google Search integrado
// =============================================================================
// ModelCaps=[cap_WebSearch] means the model has native search.
// SessionCaps=[cap_WebSearch] tells MakerAI that we need it in this
// session. Since there is no gap (the model already can), it delegates to the model directly.
// =============================================================================

procedure DemoNativa;
var
  Conn: TAiChatConnection;
  Resp: string;
begin
  WriteLn('A) NATIVE search — Gemini with integrated Google Search');
  WriteLn('   ModelCaps=[cap_WebSearch] → the model searches by itself');
  Separador;
  WriteLn;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := 'Gemini';
    Conn.Model      := MODEL_GEMINI;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';
    // gemini-2.0-flash tiene cap_WebSearch nativo registrado en el framework.
    // Sobreescribimos explícitamente para que el demo sea claro y autocontenido.
    Conn.Params.Values['ModelCaps']   := '[cap_WebSearch]';
    Conn.Params.Values['SessionCaps'] := '[cap_WebSearch]';
    Conn.SystemPrompt.Text :=
      'You are an informed assistant. Use web search to provide ' +
      'up-to-date and accurate information. Respond in Spanish and mention the sources.';

    WriteLn('Question: ', QUERY_DELPHI);
    WriteLn;

    Resp := Conn.AddMessageAndRun(QUERY_DELPHI, 'user', []);
    WriteLn(Resp);
  finally
    Conn.Free;
  end;
end;

// =============================================================================
//  B) Búsqueda via BRIDGE — Tavily + Gemini (gap analysis)
// =============================================================================
// ModelCaps=[] → the model has no native search in this configuration.
// SessionCaps=[cap_WebSearch] → we need it.
// Gap = SessionCaps − ModelCaps = [cap_WebSearch].
// MakerAI detects the gap → calls Tavily → injects the results into the LLM.
// =============================================================================

procedure DemoBridge;
var
  Conn  : TAiChatConnection;
  Tavily: TAiTavilyWebSearchTool;
  Resp  : string;
begin
  WriteLn('B) Search via BRIDGE — Tavily + Gemini (gap analysis)');
  WriteLn('   ModelCaps=[] + SessionCaps=[cap_WebSearch] → MakerAI uses Tavily');
  Separador;
  WriteLn;

  Tavily := TAiTavilyWebSearchTool.Create(nil);
  Conn   := TAiChatConnection.Create(nil);
  try
    // Configurar Tavily
    Tavily.ApiKey        := '@TAVILY_API_KEY';
    Tavily.MaxResults    := 5;
    Tavily.IncludeAnswer := True;   // Tavily genera una respuesta sintetizada propia

    // Configurar la conexión con gap analysis
    Conn.DriverName := 'Gemini';
    Conn.Model      := MODEL_GEMINI;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.Params.Values['ModelCaps']    := '[]';              // sin búsqueda nativa
    Conn.Params.Values['SessionCaps']  := '[cap_WebSearch]'; // la necesitamos
    Conn.WebSearchTool := Tavily;  // MakerAI usará Tavily para cubrir el gap

    Conn.SystemPrompt.Text :=
      'You are a financial assistant. Analyze the information received from search ' +
      'and respond with concrete and up-to-date data. Respond in Spanish.';

    WriteLn('Question: ', QUERY_PRECIOS);
    WriteLn('[Tavily searches → results injected → Gemini analyzes and responds]');
    WriteLn;

    Resp := Conn.AddMessageAndRun(QUERY_PRECIOS, 'user', []);
    WriteLn(Resp);
  finally
    Conn.WebSearchTool := nil;  // evitar que Conn libere Tavily (lo liberamos nosotros)
    Conn.Free;
    Tavily.Free;
  end;
end;

// =============================================================================
//  C) Búsqueda DIRECTA — Tavily sin LLM
// =============================================================================
// Direct call to the tool without going through TAiChatConnection.
// ExecuteSearch is protected in the class but is exposed via IAiWebSearchTool.
// The result arrives in ResMsg.Prompt: "## Response" + "## Sources [1][2]..."
// Ideal for pipelines without LLM, data prefetching, or batch processing.
// =============================================================================

procedure DemoDirecta;
var
  Tavily: TAiTavilyWebSearchTool;
  ResMsg : TAiChatMessage;
  AskMsg : TAiChatMessage;
  Resultado: string;
begin
  WriteLn('C) DIRECT search — Tavily without LLM');
  WriteLn('   (TAiTavilyWebSearchTool as IAiWebSearchTool).ExecuteSearch(...)');
  Separador;
  WriteLn;

  Tavily := TAiTavilyWebSearchTool.Create(nil);
  ResMsg := TAiChatMessage.Create;
  AskMsg := TAiChatMessage.Create;
  try
    Tavily.ApiKey        := '@TAVILY_API_KEY';
    Tavily.MaxResults    := 3;
    Tavily.IncludeAnswer := True;
    Tavily.SearchDepth   := tsdBasic;

    WriteLn('Searching: "', QUERY_DELPHI, '"');
    WriteLn('(Without LLM — immediate result)');
    WriteLn;

    // ExecuteSearch es protected en la clase → se invoca via interfaz
    (Tavily as IAiWebSearchTool).ExecuteSearch(QUERY_DELPHI, ResMsg, AskMsg);

    Resultado := ResMsg.Prompt;

    WriteLn('─── ResMsg.Prompt ────────────────────────────────────────────');
    if Length(Resultado) > 1200 then
      WriteLn(Copy(Resultado, 1, 1200), #13#10'[...truncated for the demo]')
    else
      WriteLn(Resultado);
  finally
    ResMsg.Free;
    AskMsg.Free;
    Tavily.Free;
  end;
end;

// =============================================================================
begin
  try
    WriteLn;
    WriteLn('════════════════════════════════════════════════════════════════');
    WriteLn('  Ch. 19 — Web Search and External Tools');
    WriteLn('  Driver  : Gemini (gemini-2.0-flash)');
    WriteLn('  ChatTool: TAiTavilyWebSearchTool (MakerAI ChatTools)');
    WriteLn('════════════════════════════════════════════════════════════════');
    WriteLn;

    // A: Nativa — requiere GEMINI_API_KEY
    if KeyPresente('GEMINI_API_KEY') then
    begin
      DemoNativa;
      WriteLn;
    end
    else
      WriteLn('SKIP A: GEMINI_API_KEY not configured.' + sLineBreak);

    // B: Bridge — requiere GEMINI_API_KEY + TAVILY_API_KEY
    if KeyPresente('GEMINI_API_KEY') and KeyPresente('TAVILY_API_KEY') then
    begin
      DemoBridge;
      WriteLn;
    end
    else
      WriteLn('SKIP B: GEMINI_API_KEY and/or TAVILY_API_KEY not configured.' + sLineBreak);

    // C: Directa — requiere solo TAVILY_API_KEY
    if KeyPresente('TAVILY_API_KEY') then
    begin
      DemoDirecta;
      WriteLn;
    end
    else
      WriteLn('SKIP C: TAVILY_API_KEY not configured.' + sLineBreak);

  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
    end;
  end;

  WriteLn;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
