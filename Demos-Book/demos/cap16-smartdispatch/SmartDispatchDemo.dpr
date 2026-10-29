program SmartDispatchDemo;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI -- Chapter 16: SmartDispatch -- AI with Tools without Function Calling
// =============================================================================
//
//   Demo 1 -- Basic routing with simulated tools
//             5 cases: CHAT, IMAGEGEN, WEBSEARCH, CHAT (calculation), AMBIGUOUS
//             Only requires local Ollama running at http://localhost:11434
//
//   Demo 2 -- Four tools in the dispatcher
//             IMAGE + VIDEO + TTS + WEBSEARCH active simultaneously
//             The dispatch prompt is built dynamically according to the
//             tools assigned to the connection
//
//   Demo 3 -- Hybrid: local Ollama model + real DALL-E tool (optional)
//             The local model classifies the request (no API cost)
//             DALL-E generates the real image (requires OPENAI_API_KEY)
//
// Requirements:
//   Ollama running at http://localhost:11434
//   Model gemma3:4b installed (or change MODEL to another instruction model)
//   OPENAI_API_KEY configured as environment variable (only for Demo 3)
//
// IMPORTANT: cmSmartDispatch requires Asynchronous=False
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.Messages,
  uMakerAi.Chat.Tools,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.Chat.Ollama,
  uMakerAi.OpenAi.Dalle;

const
  OLLAMA_URL = 'http://localhost:11434/';
  MODEL      = 'gemma3:4b';    // Recommended model: better instruction following than gemma4:e4b

// =============================================================================
//  Simulated (mock) tools to validate routing without real API calls
//
//  Each mock prints the argument it received from the dispatcher so it can be seen
//  that Pass 1 rewrote the request before executing the tool.
// =============================================================================

type
  TMockImageTool = class(TAiImageToolBase)
  protected
    procedure ExecuteImageGeneration(const APrompt: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

  TMockVideoTool = class(TAiVideoToolBase)
  protected
    procedure ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage); override;
  end;

  TMockSpeechTool = class(TAiSpeechToolBase)
  protected
    procedure ExecuteSpeechGeneration(const AText: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

  TMockWebSearchTool = class(TAiWebSearchToolBase)
  protected
    procedure ExecuteSearch(const AQuery: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

procedure TMockImageTool.ExecuteImageGeneration(const APrompt: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  WriteLn('    >> [IMAGEGEN] rewritten prompt: "', APrompt, '"');
  ResMsg.Prompt := '[generated image] ' + APrompt;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure TMockVideoTool.ExecuteVideoGeneration(ResMsg, AskMsg: TAiChatMessage);
begin
  // ExecuteVideoGeneration does not receive APrompt -- the prompt is in AskMsg.Prompt
  WriteLn('    >> [VIDEOGEN] original request: "', AskMsg.Prompt, '"');
  ResMsg.Prompt := '[generated video] ' + AskMsg.Prompt;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure TMockSpeechTool.ExecuteSpeechGeneration(const AText: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  WriteLn('    >> [TTS] text to read: "', Copy(AText, 1, 60), '"');
  ResMsg.Prompt := '[generated audio] ' + AText;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure TMockWebSearchTool.ExecuteSearch(const AQuery: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  WriteLn('    >> [WEBSEARCH] optimized query: "', AQuery, '"');
  ResMsg.Prompt := '[search result] ' + AQuery;
  ResMsg.Role   := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

// =============================================================================

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

procedure Probar(Conn: TAiChatConnection; const Etiqueta, Mensaje: string);
var
  Resp: string;
begin
  Write('  [', Etiqueta, '] "', Copy(Mensaje, 1, 48), '"');
  try
    Resp := Conn.AddMessageAndRun(Mensaje, 'user', []);
    WriteLn;
    WriteLn('    Response: ', Copy(Resp, 1, 80));
  except
    on E: Exception do
      WriteLn('  ERROR: ', E.ClassName, ': ', E.Message);
  end;
end;

// =============================================================================
//  Demo 1 -- Basic routing with simulated tools
//
//  Demonstrates the two-pass flow of cmSmartDispatch:
//    Pass 1 (silent): the model chooses [IMAGEGEN], [WEBSEARCH], or [CHAT]
//    Pass 2             : the framework executes the corresponding tool
//
//  The mock tools print the argument received from the dispatcher -- there you can see
//  that Pass 1 rewrote the request in English and in a more precise form.
//  Requires no API keys: only local Ollama.
// =============================================================================
procedure Demo1_RoutingBasico;
var
  Conn      : TAiChatConnection;
  ImageTool : TMockImageTool;
  SearchTool: TMockWebSearchTool;
begin
  Separador('Demo 1 -- Routing basico con herramientas simuladas');
  WriteLn('  Driver: Ollama / ', MODEL);
  WriteLn('  Tools : ImageTool [IMAGEGEN] + WebSearchTool [WEBSEARCH]');
  WriteLn('  The mock tools show the prompt rewritten by the dispatcher');
  WriteLn('');

  ImageTool  := TMockImageTool.Create(nil);
  SearchTool := TMockWebSearchTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.ImageTool     := ImageTool;
    Conn.WebSearchTool := SearchTool;

    Conn.DriverName                    := 'Ollama';
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';   // REQUIRED
    Conn.Params.Values['Max_Tokens']   := '128';

    Conn.ChatMode          := cmSmartDispatch;
    Conn.SystemPrompt.Text := 'You are a helpful assistant. Always respond in Spanish.';

    // [CHAT] -- pregunta directa de conversacion
    Probar(Conn, 'Expected CHAT    ', 'What is the capital of France?');

    // [IMAGEGEN] -- solicitud clara de generacion de imagen
    Probar(Conn, 'Expected IMAGEGEN', 'Generate an image of a cat with a cowboy hat');

    // [WEBSEARCH] -- solicitud de informacion reciente o busqueda web
    Probar(Conn, 'Expected WEBSEARCH', 'Search for recent news about artificial intelligence');

    // [CHAT] -- calculo matematico (no necesita herramientas)
    Probar(Conn, 'Expected CHAT    ', 'What is 15 multiplied by 7?');

    // Ambiguo: el modelo decide entre [IMAGEGEN] y [CHAT]
    Probar(Conn, 'AMBIGUOUS        ', 'Show me what a rainbow looks like');

    WriteLn('');
    WriteLn('-> The dispatcher rewrites requests in English for greater precision.');
    WriteLn('   [CHAT] returns the Pass 1 response directly (without Pass 2).');
    WriteLn('   The tools receive the prompt already optimized by Pass 1.');
  finally
    Conn.Free;
    ImageTool.Free;
    SearchTool.Free;
  end;
end;

// =============================================================================
//  Demo 2 -- Four tools: the dispatch prompt is dynamic
//
//  BuildSmartDispatchPrompt includes only the labels of the tools
//  that are assigned. With the 4 tools active, the model has:
//    [IMAGEGEN]  [VIDEOGEN]  [TTS]  [WEBSEARCH]  [CHAT]
//
//  Important difference from Demo 1:
//    ExecuteVideoGeneration has NO APrompt parameter (unlike
//    ExecuteImageGeneration and ExecuteSpeechGeneration). The original prompt
//    from the user is available in AskMsg.Prompt.
// =============================================================================
procedure Demo2_CuatroHerramientas;
var
  Conn      : TAiChatConnection;
  ImageTool : TMockImageTool;
  VideoTool : TMockVideoTool;
  SpeechTool: TMockSpeechTool;
  SearchTool: TMockWebSearchTool;
begin
  Separador('Demo 2 -- Cuatro herramientas: prompt de despacho dinamico');
  WriteLn('  Driver: Ollama / ', MODEL);
  WriteLn('  Tools : IMAGE + VIDEO + TTS + WEBSEARCH (5 labels available)');
  WriteLn('');

  ImageTool  := TMockImageTool.Create(nil);
  VideoTool  := TMockVideoTool.Create(nil);
  SpeechTool := TMockSpeechTool.Create(nil);
  SearchTool := TMockWebSearchTool.Create(nil);
  Conn       := TAiChatConnection.Create(nil);
  try
    Conn.ImageTool     := ImageTool;
    Conn.VideoTool     := VideoTool;
    Conn.SpeechTool    := SpeechTool;
    Conn.WebSearchTool := SearchTool;

    Conn.DriverName                    := 'Ollama';
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';   // REQUIRED
    Conn.Params.Values['Max_Tokens']   := '128';

    Conn.ChatMode          := cmSmartDispatch;
    Conn.SystemPrompt.Text := 'You are a helpful assistant. Respond in Spanish.';

    Probar(Conn, 'IMAGEGEN  ', 'Draw a mountain landscape at sunset');
    Probar(Conn, 'VIDEOGEN  ', 'Create a short video of waves on the beach');
    Probar(Conn, 'TTS       ', 'Read aloud: Welcome to MakerAI');
    Probar(Conn, 'WEBSEARCH ', 'What important news is there today?');
    Probar(Conn, 'CHAT      ', 'Explain in one sentence what artificial intelligence is');

    WriteLn('');
    WriteLn('-> With 4 tools assigned, the dispatcher knows the 5 labels.');
    WriteLn('   If a tool is unassigned, its label disappears from the prompt.');
    WriteLn('   ExecuteVideoGeneration has NO APrompt: it uses AskMsg.Prompt directly.');
  finally
    Conn.Free;
    ImageTool.Free;
    VideoTool.Free;
    SpeechTool.Free;
    SearchTool.Free;
  end;
end;

// =============================================================================
//  Demo 3 -- Hybrid: local Ollama model (classifies) + direct DALL-E (generates)
//
//  Pattern in two EXPLICIT steps:
//    Step 1 -- Ollama classifies the request and rewrites the prompt in English
//              Capturing tool: captures the rewritten prompt without generating an image
//    Step 2 -- TAiDalle.Generate() uses the captured prompt to generate the real image
//
//  Why two explicit steps?
//    TAiDalleImageTool is internally asynchronous (TTask.Run). In cmSmartDispatch
//    (which requires Asynchronous=False) the image would arrive after
//    AddMessageAndRun returns, giving an empty result. Separating the steps is more
//    clear and avoids the sync/async conflict.
// =============================================================================

type
  TCapturingImageTool = class(TAiImageToolBase)
  public
    CapturedPrompt: string;
  protected
    procedure ExecuteImageGeneration(const APrompt: string;
      ResMsg, AskMsg: TAiChatMessage); override;
  end;

procedure TCapturingImageTool.ExecuteImageGeneration(const APrompt: string;
  ResMsg, AskMsg: TAiChatMessage);
begin
  CapturedPrompt := APrompt;   // only captures; real generation happens in Step 2
  ResMsg.Prompt  := '[clasificado] ' + APrompt;
  ResMsg.Role    := 'assistant';
  ReportDataEnd(ResMsg, 'assistant', ResMsg.Prompt);
end;

procedure Demo3_Hibrido;
var
  Conn      : TAiChatConnection;
  CapTool   : TCapturingImageTool;
  Dalle     : TAiDalle;
  DalleImg  : TAiDalleImage;
  OutPath   : string;
begin
  Separador('Demo 3 -- Hibrido: Ollama (clasificador) + gpt-image-1 (generador)');
  WriteLn('  Classifier: Ollama / ', MODEL, '  (no API cost)');
  WriteLn('  Generator   : gpt-image-1  (OpenAI, direct call)');
  WriteLn('');

  CapTool := TCapturingImageTool.Create(nil);
  Conn    := TAiChatConnection.Create(nil);
  try
    Conn.ImageTool                     := CapTool;
    Conn.DriverName                    := 'Ollama';
    Conn.Params.Values['URL']          := OLLAMA_URL;
    Conn.Params.Values['Model']        := MODEL;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '128';
    Conn.ChatMode          := cmSmartDispatch;
    Conn.SystemPrompt.Text := 'Eres un asistente visual. Genera imagenes cuando se soliciten.';

    WriteLn('  Request: "Generate an image of a robot reading a Delphi book"');
    WriteLn('');
    Write('  Step 1 -- Ollama classifies... ');
    Conn.AddMessageAndRun(
      'Generate an image of a robot reading a Delphi book', 'user', []);
    WriteLn('OK');
  finally
    Conn.Free;
    // CapTool.Free: freed after using CapturedPrompt
  end;

  if CapTool.CapturedPrompt <> '' then
  begin
    WriteLn('  Rewritten prompt: "', CapTool.CapturedPrompt, '"');
    WriteLn('');
    Write('  Step 2 -- gpt-image-1 generates the image... ');
    Dalle := TAiDalle.Create(nil);
    try
      Dalle.ApiKey       := '@OPENAI_API_KEY';
      Dalle.Model        := imGptImage1;
      Dalle.Quality      := iqMedium;
      Dalle.OutputFormat := ifPng;
      DalleImg := Dalle.Generate(CapTool.CapturedPrompt, '', is1024x1024);
      if Assigned(DalleImg) and (DalleImg.Image <> nil) then
      begin
        WriteLn('OK');
        OutPath := TPath.Combine(TPath.GetTempPath, 'cap16_demo3_robot.png');
        DalleImg.Image.Position := 0;
        DalleImg.Image.SaveToFile(OutPath);
        WriteLn('  Image saved: ', OutPath,
                '  (', DalleImg.Image.Size div 1024, ' KB)');
      end
      else
        WriteLn('NO RESULT');
    finally
      Dalle.Free;
    end;
  end
  else
  begin
    WriteLn('  [NOTE] The model chose [CHAT] instead of [IMAGEGEN].');
    WriteLn('  Try a more explicit request: "draw" or "create image of..."');
  end;
  CapTool.Free;

  WriteLn('');
  WriteLn('-> The local model only produces ~10-30 tokens (classification + rewriting).');
  WriteLn('   gpt-image-1 receives the prompt already optimized in English by the dispatcher.');
  WriteLn('   This pattern separates cheap classification from expensive generation.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  TieneOpenAI: Boolean;
begin
  SetConsoleOutputCP(65001);
  WriteLn('=== MakerAI -- Chapter 16: SmartDispatch ===');
  WriteLn('Demos: intelligent routing for models without function calling');
  WriteLn('');
  WriteLn('  Local driver : Ollama -- ', OLLAMA_URL);
  WriteLn('  Model       : ', MODEL);
  WriteLn('  IMPORTANT   : cmSmartDispatch requires Asynchronous=False');
  WriteLn('');

  TieneOpenAI := GetEnvironmentVariable('OPENAI_API_KEY') <> '';

  WriteLn('  Environment status:');
  WriteLn('  Ollama -- if running at ', OLLAMA_URL, ' demos 1 and 2 work');
  if TieneOpenAI then WriteLn('  [OK] OPENAI_API_KEY detected -- Demo 3 active')
  else            WriteLn('  [--] OPENAI_API_KEY not configured -- Demo 3 skipped');

  try Demo1_RoutingBasico;
  except on E: Exception do WriteLn('  [Demo 1 ERROR] ', E.ClassName, ': ', E.Message); end;

  try Demo2_CuatroHerramientas;
  except on E: Exception do WriteLn('  [Demo 2 ERROR] ', E.ClassName, ': ', E.Message); end;

  if TieneOpenAI then
  begin
    try Demo3_Hibrido;
    except on E: Exception do WriteLn('  [Demo 3 ERROR] ', E.ClassName, ': ', E.Message); end;
  end
  else
    WriteLn(#13#10'--- Demo 3 skipped (OPENAI_API_KEY not configured) ---');

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demos completed.');
  WriteLn('  See cap16-smartdispatch.md for the complete documentation.');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('FATAL ERROR: ', E.ClassName, ' -- ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
