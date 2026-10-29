program SmartDispatch;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI - 02-ChatTools / 08-SmartDispatch
// =============================================================================
// Validates cmSmartDispatch mode: intelligent dispatch for small models
// without native function calling.
//
// Flow per message:
//   Pass 1 (silent) — the LLM receives a special system prompt and chooses
//                         tool + rewrites the prompt.
//   Pass 2              — the chosen tool is executed, or the
//                         Pass 1 response is used directly if it chooses [CHAT].
//
// Simulated tools (mock):
//   TMockImageTool     — prints the prompt instead of generating a real image
//   TMockWebSearchTool — prints the query instead of searching the internet
//
// Requirements:
//   - Ollama running at http://localhost:11434
//   - gemma3:4b model (or any local model without function calling)
//   - Change DRIVER/MODEL/OLLAMA_URL if using another provider
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.Tools,
  uMakerAi.Core,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama;

const
  DRIVER     = 'Ollama';
  MODEL      = 'gemma4:e4b';
  OLLAMA_URL = 'http://localhost:11434/';

// =============================================================================
//  Mock tools — simulate tools without real API calls
// =============================================================================

type
  TMockImageTool = class(TAiImageToolBase)
  protected
    procedure ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage); override;
  end;

  TMockWebSearchTool = class(TAiWebSearchToolBase)
  protected
    procedure ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage); override;
  end;

procedure TMockImageTool.ExecuteImageGeneration(const APrompt: string; ResMsg, AskMsg: TAiChatMessage);
begin
  Writeln('  >> [ImageTool] prompt received: "', APrompt, '"');
  ResMsg.Prompt := '[IMAGEN SIMULADA] ' + APrompt;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure TMockWebSearchTool.ExecuteSearch(const AQuery: string; ResMsg, AskMsg: TAiChatMessage);
begin
  Writeln('  >> [WebSearchTool] query received: "', AQuery, '"');
  ResMsg.Prompt := '[BUSQUEDA WEB SIMULADA] ' + AQuery;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

// =============================================================================
//  Helper: executes a message and shows the result
// =============================================================================

procedure Probar(Conn: TAiChatConnection; const Etiqueta, Mensaje: String);
var
  Resp: String;
begin
  Writeln(StringOfChar('-', 65));
  Writeln('[', Etiqueta, '] ', Mensaje);
  try
    Resp := Conn.AddMessageAndRun(Mensaje, 'user', []);
    Writeln('  Result: ', Copy(Resp, 1, 120));
  except
    on E: Exception do
      Writeln('  ERROR: ', E.ClassName, ': ', E.Message);
  end;
  Writeln;
end;

// =============================================================================
//  Main demo
// =============================================================================

procedure RunDemo;
var
  Conn      : TAiChatConnection;
  ImageTool : TMockImageTool;
  SearchTool: TMockWebSearchTool;
begin
  Writeln('=== SmartDispatch Demo ===');
  Writeln('Driver : ', DRIVER, ' / ', MODEL);
  Writeln('Mode   : cmSmartDispatch');
  Writeln('Note   : Asynchronous=False required in this mode');
  Writeln;

  ImageTool  := TMockImageTool.Create(nil);
  SearchTool := TMockWebSearchTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    // Tools assigned BEFORE DriverName (required pattern)
    Conn.ImageTool     := ImageTool;
    Conn.WebSearchTool := SearchTool;

    Conn.DriverName := DRIVER;

    // Driver params
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';

    // SmartDispatch mode
    Conn.ChatMode := cmSmartDispatch;
    Conn.SystemPrompt.Text := 'You are a helpful assistant. Respond in Spanish.';

    Writeln('Tools available to the dispatcher:');
    Writeln('  - ImageTool     => tag [IMAGEGEN]');
    Writeln('  - WebSearchTool => tag [WEBSEARCH]');
    Writeln('  - No tool      => tag [CHAT]');
    Writeln;

    // --- Test cases ---

    // Should go to [CHAT] — conversation question
    Probar(Conn, 'CHAT esperado',
      'What is the capital of France?');

    // Should go to [IMAGEGEN] — image request
    Probar(Conn, 'IMAGEGEN esperado',
      'Generate an image of a cat with a cowboy hat');

    // Should go to [WEBSEARCH] — search request
    Probar(Conn, 'WEBSEARCH esperado',
      'Search for the latest news about artificial intelligence in 2025');

    // Should go to [CHAT] — math calculation
    Probar(Conn, 'CHAT esperado',
      'How much is 15 multiplied by 7?');

    // Ambiguous: image or chat?
    Probar(Conn, 'AMBIGUO (imagen o chat?)',
      'Show me what a rainbow looks like');

    Writeln(StringOfChar('=', 65));
    Writeln('Demo finished. Total messages in history: ',
      Conn.AiChat.Messages.Count);

  finally
    Conn.Free;
    ImageTool.Free;
    SearchTool.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('FATAL: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Write('Press Enter to exit...');
  Readln;
end.
