program ChatTools;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 7: ChatTools — Superpowers for Any Model
// =============================================================================
// Demonstrates the MakerAI ChatTools system: the mechanism that lets you give
// additional capabilities to models that do not have them natively.
//
// Central concept: Gap = SessionCaps - ModelCaps
//   When the model does not have a capability the session needs,
//   MakerAI looks for an assigned ChatTool to cover that gap.
//   The model never knows it is receiving external help.
//
// Demonstrates:
//   - Demo 1: Vision bridge — Groq (pure text) "sees" images via Ollama
//             gemma3:4b describes the image → Groq reasons about the description
//   - Demo 2: Direct use of VisionTool — without going through the LLM
//             TAiOllamaVisionTool.DescribeFromFile() as a direct call
//   - Demo 3: Path A/B pattern — how information flows in ChatTools
//
// Prerequisites:
//   GROQ_API_KEY  → environment variable (for the main LLM in Demo 1)
//   Ollama        → running on localhost:11434 with model gemma3:4b
//                   Install: https://ollama.com
//                   Download model: ollama pull gemma3:4b
//   Demo 3 is conceptual and requires no external services.
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Groq,       // DriverName = 'Groq' — main LLM (text only)
  uMakerAi.Ollama.Vision;   // TAiOllamaVisionTool — vision bridge via Ollama

const
  // Main LLM — pure text, ModelCaps = []  (no native vision)
  LLM_DRIVER  = 'Groq';
  LLM_MODEL   = 'llama-3.3-70b-versatile';
  LLM_API_KEY = '@GROQ_API_KEY';

  // VisionTool — vision model in Ollama
  OLLAMA_URL   = 'http://localhost:11434/';
  VISION_MODEL = 'gemma3:4b';   // Alternativas: 'llava:latest', 'moondream:latest'

  // Test image (present in all Windows installations)
  IMG_PATH = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Checks whether Ollama is running on the local port.
// =============================================================================
function OllamaDisponible: Boolean;
var
  Client: THTTPClient;
begin
  Result := False;
  Client := THTTPClient.Create;
  try
    try
      Client.Get(OLLAMA_URL);
      Result := True;
    except
      Result := False;
    end;
  finally
    Client.Free;
  end;
end;

// =============================================================================
//  Demo 1 — Vision bridge: Groq (pure text) + Ollama (vision)
//
//  Groq llama-3.3-70b-versatile has no vision capability (ModelCaps = []).
//  By assigning TAiOllamaVisionTool, MakerAI activates the bridge automatically:
//
//    1. App sends: image + "describe 3 visual elements"
//    2. MakerAI detects: Groq cannot see images (Gap)
//    3. VisionTool calls gemma3:4b in Ollama:
//       → gemma3 describes the image in text
//    4. MakerAI injects the description as context for Groq:
//       → "Image description: [gemma3 text]"
//    5. Groq reasons about the description and responds
//
//  Groq never received the image directly. Only text.
// =============================================================================
procedure Demo1_VisionBridge;
var
  Conn      : TAiChatConnection;
  VisionTool: TAiOllamaVisionTool;
  MF        : TAiMediaFile;
  Files     : TAiMediaFilesArray;
  R         : string;
begin
  Separador('Demo 1 — Bridge de visión (Groq + Ollama)');

  if not TFile.Exists(IMG_PATH) then
  begin
    WriteLn('  Imagen no encontrada: ', IMG_PATH);
    WriteLn('  Adjust IMG_PATH to a JPEG image on your system.');
    Exit;
  end;

  WriteLn('  Main LLM: ', LLM_DRIVER, ' / ', LLM_MODEL, '  [ModelCaps = []]');
  WriteLn('  VisionTool   : Ollama / ', VISION_MODEL, '         [sees the image]');
  WriteLn('  Image        : ', TPath.GetFileName(IMG_PATH));
  WriteLn('');

  // El VisionTool: describe imágenes usando gemma3:4b en Ollama
  VisionTool := TAiOllamaVisionTool.Create(nil);
  VisionTool.Url   := OLLAMA_URL;
  VisionTool.Model := VISION_MODEL;
  // Prompt sent to the vision model (in Spanish)
  VisionTool.Prompt := 'Describe esta imagen en detalle en español.';

  // La conexión principal con Groq — texto puro
  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := LLM_DRIVER;
    Conn.Model      := LLM_MODEL;
    Conn.Params.Values['ApiKey']       := LLM_API_KEY;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '512';
    // SessionCaps indicates that this session needs vision.
    // Gap = [cap_Image] - [] = [cap_Image] → MakerAI activates the VisionTool bridge.
    Conn.Params.Values['SessionCaps']  := '[cap_Image]';

    // Assign the bridge: Groq now "sees" through Ollama
    Conn.VisionTool := VisionTool;

    Conn.SystemPrompt.Text :=
      'Eres un asistente de análisis visual. Recibirás descripciones en texto ' +
      'de imágenes y responderás preguntas sobre ellas. Responde en español, conciso.';

    // Load the image into a TAiMediaFile
    // NOTE: AddMessageAndRun takes ownership of the TAiMediaFile items in the array.
    // Do not call MF.Free afterwards — the internal message releases them.
    MF := TAiMediaFile.Create;
    MF.LoadFromFile(IMG_PATH);
    SetLength(Files, 1);
    Files[0] := MF;

    // Send image + question to the LLM
    // The bridge activates automatically: gemma3 describes → Groq reasons
    Write('  Processing (gemma3 describes image, Groq reasons)... ');
    R := Conn.AddMessageAndRun(
      'Describe 3 elementos visuales principales que observas en la imagen.',
      'user', Files);
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Groq response (reasoned about gemma3 description):');
    WriteLn('  ', R);

  finally
    Conn.Free;
    VisionTool.Free;
  end;

  WriteLn('');
  WriteLn('→ Groq never received the image directly.');
  WriteLn('  It received the text description generated by gemma3:4b in Ollama.');
  WriteLn('  Changing VisionTool = changing VisionTool.Model. Nothing else.');
end;

// =============================================================================
//  Demo 2 — Direct use of VisionTool (without LLM)
//
//  ChatTools are independent components that can be used directly,
//  without needing to configure a complete TAiChatConnection.
//
//  TAiOllamaVisionTool.DescribeFromFile() is a class method that:
//    - Creates a temporary connection to Ollama
//    - Sends the image to the vision model
//    - Returns the description as a string
//    - Closes the connection
//
//  Useful when you only need to describe an image without conversation.
// =============================================================================
procedure Demo2_DirectTool;
var
  Descripcion: string;
begin
  Separador('Demo 2 — Uso directo del VisionTool (sin LLM)');

  if not TFile.Exists(IMG_PATH) then
  begin
    WriteLn('  Imagen no encontrada: ', IMG_PATH);
    Exit;
  end;

  WriteLn('  Calling TAiOllamaVisionTool.DescribeFromFile() directly...');
  WriteLn('  (Without TAiChatConnection — VisionTool operates independently)');
  WriteLn('');

  // Class method: no Create/Free needed, calls the model directly
  Write('  Describing image with gemma3:4b... ');
  try
    Descripcion := TAiOllamaVisionTool.DescribeFromFile(
      IMG_PATH,
      'Describe brevemente esta imagen en español (máximo 2 oraciones).',
      OLLAMA_URL);
    WriteLn('OK');
    WriteLn('');
    WriteLn('  Description from gemma3:4b:');
    WriteLn('  ', Descripcion);
  except
    on E: Exception do
    begin
      WriteLn('ERROR');
      WriteLn('  ', E.Message);
    end;
  end;

  WriteLn('');
  WriteLn('→ ChatTools are reusable, independent components.');
  WriteLn('  You can call them directly anywhere in your code.');
end;

// =============================================================================
//  Demo 3 — Path A vs Path B (conceptual)
//
//  When a ChatTool processes a file, it has two paths to communicate
//  the result. The choice determines whether the LLM sees the result or not.
//
//  This demo requires no external services — it is an illustrated explanation.
// =============================================================================
procedure Demo3_CaminoAvsB;
begin
  Separador('Demo 3 — Patron Camino A vs Camino B');

  WriteLn('  Cuando un ChatTool procesa un archivo, elige cómo comunicar');
  WriteLn('  the result. This decision completely defines the data flow.');
  WriteLn('');
  WriteLn('  PATH A — result goes to the LLM (comprehension tool):');
  WriteLn('  ─────────────────────────────────────────────────────────────');
  WriteLn('');
  WriteLn('    aMediaFile.Transcription := TextoExtraido;  // LLM will see this');
  WriteLn('    aMediaFile.Procesado      := True;           // signal to the orchestrator');
  WriteLn('');
  WriteLn('    Flow: Image ──> VisionTool describes ──> text in Transcription');
  WriteLn('                                               ──> LLM receives ──> reasons');
  WriteLn('');
  WriteLn('    Path A tools (input comprehension):');
  WriteLn('      VisionTool  → image  converts to text description');
  WriteLn('      SpeechTool  → audio   converts to text transcription');
  WriteLn('      PdfTool     → PDF     converts to extracted text');
  WriteLn('');
  WriteLn('  PATH B — result goes to the user (generation tool):');
  WriteLn('  ─────────────────────────────────────────────────────────────');
  WriteLn('');
  WriteLn('    MFAudio := TAiMediaFile.Create;');
  WriteLn('    MFAudio.LoadFromStream(''respuesta.mp3'', AudioStream);');
  WriteLn('    ResMsg.AddMediaFile(MFAudio);   // goes directly to the user');
  WriteLn('');
  WriteLn('    Flow: LLM text ──> TTSTool generates audio ──> MP3');
  WriteLn('                                                 ──> user receives');
  WriteLn('                                   (the LLM never saw the audio)');
  WriteLn('');
  WriteLn('    Herramientas Camino B (generación de salida):');
  WriteLn('      SpeechTool  → texto  convierte a audio generado (MP3/WAV)');
  WriteLn('      ImageTool   → prompt convierte a imagen generada (PNG/JPG)');
  WriteLn('      VideoTool   → prompt convierte a video generado (MP4)');
  WriteLn('      ReportTool  → datos  convierte a PDF generado');
  WriteLn('');
  WriteLn('  Tabla de decision:');
  WriteLn('  ┌─────────────────┬──────────────┬──────────────────────────┐');
  WriteLn('  │ Tool            │ Tipo         │ LLM ve el resultado?     │');
  WriteLn('  ├─────────────────┼──────────────┼──────────────────────────┤');
  WriteLn('  │ VisionTool      │ Comprension  │ Si — razona la descripc. │');
  WriteLn('  │ SpeechTool (STT)│ Comprension  │ Si — razona la transcrip.│');
  WriteLn('  │ PdfTool         │ Comprension  │ Si — razona el contenido │');
  WriteLn('  │ SpeechTool (TTS)│ Generacion   │ No — audio va al usuario │');
  WriteLn('  │ ImageTool       │ Generacion   │ No — imagen va al usuario│');
  WriteLn('  │ VideoTool       │ Generacion   │ No — video va al usuario │');
  WriteLn('  └─────────────────┴──────────────┴──────────────────────────┘');
  WriteLn('');
  WriteLn('→ Pregunta clave: ¿necesitas que el LLM procese el resultado?');
  WriteLn('  Si  → Camino A: aMediaFile.Transcription + Procesado = True');
  WriteLn('  No  → Camino B: ResMsg.AddMediaFile(archivoGenerado)');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  OllamaOK: Boolean;
begin
  WriteLn('=== MakerAI — Capítulo 7: ChatTools ===');
  WriteLn('Gap = SessionCaps - ModelCaps -> VisionTool cubre la brecha');

  OllamaOK := OllamaDisponible;
  WriteLn('');

  if OllamaOK then
    WriteLn('[OK] Ollama detectado en ', OLLAMA_URL)
  else
  begin
    WriteLn('[!!] Ollama no detectado en ', OLLAMA_URL);
    WriteLn('     Demos 1 y 2 requieren Ollama con gemma3:4b.');
    WriteLn('     Para instalar: https://ollama.com');
    WriteLn('     Para el modelo: ollama pull gemma3:4b');
    WriteLn('     Solo se ejecutara el Demo 3 (conceptual, sin servicios externos).');
  end;

  if OllamaOK then
  begin
    Demo1_VisionBridge;
    Demo2_DirectTool;
  end;

  Demo3_CaminoAvsB;

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demo completado.');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('');
  WriteLn('Presiona Enter para salir...');
  ReadLn;
end.
